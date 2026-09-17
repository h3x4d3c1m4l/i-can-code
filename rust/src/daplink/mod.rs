//! DAPLink's own vendor commands, which sit outside CMSIS-DAP proper.
//!
//! Ported from `daplink.ts` in microbit-foundation/microbit-connection (MIT).

pub mod cdc_saturation;
pub mod flash;
pub mod serial;

use crate::dap::cmsis::CmsisDap;
use crate::dap::DapError;
use crate::transport::DapTransport;

/// DAPLink's vendor command range starts here.
pub const DAPLINK_VENDOR_READ_UNIQUE_ID: u8 = 0x80;

/// The board's unique id, asked of the interface chip.
///
/// Preferred over `USBDevice.serialNumber`, which Chrome may anonymize. Answers
/// `None` when the command is unsupported, so a caller can fall back to the
/// descriptor. See `docs/microbit-usb.md`.
pub async fn read_unique_id<T: DapTransport>(dap: &mut CmsisDap<T>) -> Option<String> {
    match dap.vendor_string(DAPLINK_VENDOR_READ_UNIQUE_ID).await {
        Ok(id) => id,
        Err(DapError::Transport(_)) => None,
        Err(_) => None,
    }
}
