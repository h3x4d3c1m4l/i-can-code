//! The target's UART, reached through DAPLink's vendor commands.
//!
//! Ported from `daplink.ts` in microbit-foundation/microbit-connection (MIT).

use crate::dap::cmsis::CmsisDap;
use crate::dap::DapError;
use crate::transport::DapTransport;

pub const DAPLINK_VENDOR_READ_SETTINGS: u8 = 0x81;
pub const DAPLINK_VENDOR_WRITE_SETTINGS: u8 = 0x82;
pub const DAPLINK_VENDOR_SERIAL_READ: u8 = 0x83;
pub const DAPLINK_VENDOR_SERIAL_WRITE: u8 = 0x84;

/// What MicroPython's REPL speaks.
pub const MICROBIT_BAUD_RATE: u32 = 115_200;

/// What one counted payload fits in a packet.
const MAX_WRITE: usize = 62;

/// A bound rather than "until empty": a board printing in a tight loop
/// produces faster than reads retire, so an unbounded drain never returns.
const MAX_READS_PER_DRAIN: usize = 32;

/// Reads whatever the target has printed since the last look. Empty is the
/// ordinary answer, not an error.
pub async fn read<T: DapTransport>(dap: &mut CmsisDap<T>) -> Result<Vec<u8>, DapError> {
    dap.vendor_bytes(DAPLINK_VENDOR_SERIAL_READ, &[]).await
}

/// Reads until a read comes back short, or the bound is reached.
///
/// One read per poll retires about 4 KB/s against 115200 baud's 11.5 KB/s, so a
/// `print` in a loop would fall further behind on every pass.
pub async fn read_drain<T: DapTransport>(dap: &mut CmsisDap<T>) -> Result<Vec<u8>, DapError> {
    let mut out = Vec::new();

    for _ in 0..MAX_READS_PER_DRAIN {
        let chunk = read(dap).await?;
        let short = chunk.len() < MAX_WRITE;
        out.extend(chunk);

        if short {
            break;
        }
    }

    Ok(out)
}

/// Throws away whatever is already buffered, without reporting it.
///
/// What the board printed before anyone was watching belongs to the previous
/// session.
pub async fn discard_buffered<T: DapTransport>(dap: &mut CmsisDap<T>) -> Result<usize, DapError> {
    let mut discarded = 0;

    for _ in 0..MAX_READS_PER_DRAIN {
        let chunk = read(dap).await?;
        if chunk.is_empty() {
            break;
        }
        discarded += chunk.len();
    }

    Ok(discarded)
}

/// Sends bytes to the target's UART, in as many writes as it takes.
pub async fn write<T: DapTransport>(dap: &mut CmsisDap<T>, data: &[u8]) -> Result<(), DapError> {
    for chunk in data.chunks(MAX_WRITE) {
        let mut payload = Vec::with_capacity(chunk.len() + 1);
        payload.push(chunk.len() as u8);
        payload.extend_from_slice(chunk);

        dap.send(DAPLINK_VENDOR_SERIAL_WRITE, &payload).await?;
    }

    Ok(())
}

/// The baud rate DAPLink is currently decoding the target's UART at.
pub async fn baud_rate<T: DapTransport>(dap: &mut CmsisDap<T>) -> Result<u32, DapError> {
    let response = dap.send(DAPLINK_VENDOR_READ_SETTINGS, &[]).await?;

    let bytes = response.get(1..5).ok_or(DapError::Truncated {
        command: DAPLINK_VENDOR_READ_SETTINGS,
        length: response.len(),
    })?;

    Ok(u32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]))
}

/// Sets the baud rate DAPLink decodes at.
///
/// On a V1 this can reset the target, so upstream re-initialises SWD after it.
/// A V2 is unaffected.
pub async fn set_baud_rate<T: DapTransport>(dap: &mut CmsisDap<T>, rate: u32) -> Result<(), DapError> {
    dap.send(DAPLINK_VENDOR_WRITE_SETTINGS, &rate.to_le_bytes()).await?;
    Ok(())
}
