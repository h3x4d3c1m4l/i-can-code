//! Moving fixed-size packets between the host and the interface chip.
//!
//! The lowest layer of the USB stack. It knows no DAP commands.
//!
//! Ported from `transport.ts` in microbit-foundation/microbit-connection (MIT),
//! derived from dapjs (Copyright Arm Limited 2018, Microsoft Corporation, MIT).

pub mod usb;

use std::fmt;

/// Every CMSIS-DAP packet is this long, in both directions.
pub const PACKET_SIZE: usize = 64;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TransportError {
    /// Nothing plugged in, or permission never granted.
    NoDevice,

    /// Another tab, MakeCode or a stray `pyocd` holds the interface. A case of
    /// its own because it is the likeliest thing to go wrong in a classroom.
    Busy,

    /// No vendor-class interface carries bulk endpoints, which is what a
    /// micro:bit V1 looks like. See `docs/microbit-usb.md`.
    NoBulkInterface,

    /// The transfer failed, usually the cable coming out mid-operation.
    Io(String),
}

impl fmt::Display for TransportError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            TransportError::NoDevice => write!(f, "no micro:bit available"),
            TransportError::Busy => write!(f, "the micro:bit's debug interface is held by something else"),
            TransportError::NoBulkInterface => {
                write!(f, "no CMSIS-DAP v2 interface with bulk endpoints")
            }
            TransportError::Io(message) => write!(f, "USB transfer failed: {message}"),
        }
    }
}

/// Raw packet I/O against something that speaks CMSIS-DAP.
///
/// A trait so the layers above can be driven by a recorded sequence in a test.
/// Deliberately not `Send`: a device is a `JsValue` on the web, so everything
/// above this is single-threaded.
#[allow(async_fn_in_trait)]
pub trait DapTransport {
    /// Reads one packet. Blocks until the device answers.
    async fn read(&mut self) -> Result<Vec<u8>, TransportError>;

    /// Writes one packet. Data shorter than [`PACKET_SIZE`] is padded by the
    /// implementation, never by the caller.
    async fn write(&mut self, data: &[u8]) -> Result<(), TransportError>;
}
