//! The [`DapTransport`] a real micro:bit is on the other end of.

use nusb::transfer::{Buffer, Bulk, In, Out};
use nusb::{DeviceInfo, Endpoint, Interface};

use crate::transport::{DapTransport, TransportError, PACKET_SIZE};

/// DAPLink on a micro:bit. Vendor 0x0D28 is Arm; product 0x0204 is the board.
pub const MICROBIT_VENDOR_ID: u16 = 0x0D28;
pub const MICROBIT_PRODUCT_ID: u16 = 0x0204;

/// CMSIS-DAP sits on a vendor-specific interface.
const CMSIS_DAP_INTERFACE_CLASS: u8 = 0xFF;

/// Every micro:bit this origin may see.
pub async fn list_microbits() -> Result<Vec<DeviceInfo>, TransportError> {
    let devices = nusb::list_devices()
        .await
        .map_err(|e| TransportError::Io(e.to_string()))?;

    Ok(devices
        .filter(|d| d.vendor_id() == MICROBIT_VENDOR_ID && d.product_id() == MICROBIT_PRODUCT_ID)
        .collect())
}

/// One claimed CMSIS-DAP v2 interface, with its two bulk endpoints.
pub struct UsbTransport {
    /// Dropping this releases the claim, which the endpoints below need.
    _interface: Interface,
    endpoint_in: Endpoint<Bulk, In>,
    endpoint_out: Endpoint<Bulk, Out>,
}

impl UsbTransport {
    /// Opens [info] and claims its CMSIS-DAP interface.
    pub async fn open(info: &DeviceInfo) -> Result<UsbTransport, TransportError> {
        let device = info.open().await.map_err(map_open_error)?;

        let configuration = device
            .configurations()
            .next()
            .ok_or_else(|| TransportError::Io("device reports no configuration".to_string()))?;

        // Not the first 0xFF interface: a V2 has two and the first has no
        // endpoints, so claiming it succeeds and every transfer then goes
        // nowhere. See `docs/microbit-usb.md`.
        let mut selected = None;
        for alt in configuration.interface_alt_settings() {
            if alt.class() != CMSIS_DAP_INTERFACE_CLASS {
                continue;
            }

            let mut address_in = None;
            let mut address_out = None;
            for endpoint in alt.endpoints() {
                let address = endpoint.address();
                // Bit 7 of an endpoint address is its direction.
                if address & 0x80 != 0 {
                    address_in.get_or_insert(address);
                } else {
                    address_out.get_or_insert(address);
                }
            }

            if let (Some(address_in), Some(address_out)) = (address_in, address_out) {
                selected = Some((alt.interface_number(), address_in, address_out));
                break;
            }
        }

        let Some((number, address_in, address_out)) = selected else {
            return Err(TransportError::NoBulkInterface);
        };

        let interface = device.claim_interface(number).await.map_err(map_open_error)?;

        let endpoint_in = interface
            .endpoint::<Bulk, In>(address_in)
            .map_err(|e| TransportError::Io(e.to_string()))?;
        let endpoint_out = interface
            .endpoint::<Bulk, Out>(address_out)
            .map_err(|e| TransportError::Io(e.to_string()))?;

        Ok(UsbTransport {
            _interface: interface,
            endpoint_in,
            endpoint_out,
        })
    }
}

impl DapTransport for UsbTransport {
    async fn read(&mut self) -> Result<Vec<u8>, TransportError> {
        self.endpoint_in.submit(Buffer::new(PACKET_SIZE));

        let completion = self.endpoint_in.next_complete().await;
        let length = completion.actual_len;
        let buffer = completion
            .into_result()
            .map_err(|e| TransportError::Io(e.to_string()))?;

        Ok(buffer[..length].to_vec())
    }

    async fn write(&mut self, data: &[u8]) -> Result<(), TransportError> {
        // CMSIS-DAP reads a fixed size, so a short write leaves the device
        // waiting for the rest.
        let mut packet = vec![0u8; PACKET_SIZE];
        let length = data.len().min(PACKET_SIZE);
        packet[..length].copy_from_slice(&data[..length]);

        self.endpoint_out.submit(Buffer::from(packet));

        self.endpoint_out
            .next_complete()
            .await
            .into_result()
            .map(|_| ())
            .map_err(|e| TransportError::Io(e.to_string()))
    }
}

/// Tells "someone else has it" apart from every other reason opening fails,
/// because that one the reader can fix themselves.
fn map_open_error(error: nusb::Error) -> TransportError {
    match error.kind() {
        nusb::ErrorKind::Busy => TransportError::Busy,
        nusb::ErrorKind::NotFound => TransportError::NoDevice,
        _ => TransportError::Io(error.to_string()),
    }
}
