//! What the chip on the board says about itself.

use crate::dap::adi::ArmDebug;
use crate::dap::DapError;
use crate::transport::DapTransport;

use crate::board_id::BoardSerialInfo;
use crate::dap::cmsis::DapInfoId;
use crate::dap::cortex_m::CortexM;
use crate::daplink::cdc_saturation::saturate;
use crate::daplink::read_unique_id;

/// Nordic's Factory Information Configuration Registers.
///
/// A flash is planned against these, so they are read from the chip rather than
/// taken from the hex or assumed.
const FICR_CODEPAGESIZE: u32 = 0x1000_0010;
const FICR_CODESIZE: u32 = 0x1000_0014;

/// How the target's flash is laid out.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FlashLayout {
    /// Bytes in one page. 4096 on an nRF52833.
    pub page_size: u32,
    /// How many pages. 128 on an nRF52833, so 512 KB in all.
    pub page_count: u32,
}

impl FlashLayout {
    pub fn total_bytes(self) -> u32 {
        self.page_size * self.page_count
    }

    /// Whether these numbers could describe a real nRF flash.
    ///
    /// A target that is not ready answers zeroes rather than failing, and a zero
    /// page size divides by zero three layers up.
    pub fn is_plausible(self) -> bool {
        self.page_size.is_power_of_two()
            && self.page_size >= 1024
            && self.page_count > 0
            && self.page_size.checked_mul(self.page_count).is_some()
    }
}

/// Reads the flash layout out of FICR.
///
/// The caller MUST have connected SWD first. Retries because a target does not
/// answer for a moment after a reset; each attempt is a USB round trip.
pub async fn read_flash_layout<T: DapTransport>(debug: &mut ArmDebug<T>) -> Result<FlashLayout, DapError> {
    const ATTEMPTS: usize = 20;

    let mut last_error = None;

    for _ in 0..ATTEMPTS {
        match read_layout_once(debug).await {
            Ok(layout) if layout.is_plausible() => return Ok(layout),
            Ok(_) => continue,
            Err(error) => last_error = Some(error),
        }
    }

    Err(last_error.unwrap_or(DapError::Timeout {
        stage: "FICR to report a flash layout",
    }))
}

async fn read_layout_once<T: DapTransport>(debug: &mut ArmDebug<T>) -> Result<FlashLayout, DapError> {
    let page_size = debug.read_mem32(FICR_CODEPAGESIZE).await?;
    let page_count = debug.read_mem32(FICR_CODESIZE).await?;

    Ok(FlashLayout { page_size, page_count })
}

/// Everything one look at a connected board turns up.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BoardReport {
    pub vendor: Option<String>,
    pub product: Option<String>,
    pub protocol_version: Option<String>,
    /// The 48-character DAPLink unique id, wherever it came from.
    pub unique_id: Option<String>,
    /// True when the id came over the DAP vendor command, which is the source
    /// that survives a browser anonymizing serial numbers.
    pub from_vendor_command: bool,
    pub serial_info: Option<BoardSerialInfo>,
    pub layout: FlashLayout,
}

/// Asks a freshly opened board everything worth knowing about it.
///
/// Leaves SWD disconnected. Only the FICR read needs the debug port, and a REPL
/// session should not hold the target's debug domain powered.
pub async fn read_board_report<T: DapTransport>(
    debug: &mut ArmDebug<T>,
    usb_serial: Option<&str>,
) -> Result<BoardReport, DapError> {
    // A session interrupted mid-flash leaves replies queued; reading those
    // makes every command afterwards look like a protocol fault.
    debug.dap().drain_stale_responses().await?;

    let vendor = debug.dap().info_string(DapInfoId::VendorName).await?;
    let product = debug.dap().info_string(DapInfoId::ProductName).await?;
    let protocol_version = debug.dap().info_string(DapInfoId::ProtocolVersion).await?;

    // Only the vendor command survives a browser anonymizing the descriptor,
    // so it goes first.
    let (unique_id, from_vendor_command) = match read_unique_id(debug.dap()).await {
        Some(id) => (Some(id), true),
        None => (usb_serial.map(str::to_string), false),
    };

    debug.connect().await?;
    let layout = read_flash_layout(debug).await?;
    let _ = debug.disconnect().await;

    Ok(BoardReport {
        serial_info: unique_id.as_deref().and_then(BoardSerialInfo::from_serial),
        vendor,
        product,
        protocol_version,
        unique_id,
        from_vendor_command,
        layout,
    })
}

/// Halts the board, fills DAPLink's buffers, and resets it.
///
/// The three steps only make sense together: nothing may execute while the
/// saturation writes over RAM, and only the reset repairs that. See
/// `docs/microbit-usb.md`.
///
/// The caller MUST discard buffered serial before calling this, because the
/// output this produces is the point of it.
pub async fn restart_for_serial<T: DapTransport>(debug: &mut ArmDebug<T>) -> Result<(), DapError> {
    debug.connect().await?;

    {
        let mut core = CortexM::new(debug);
        core.halt().await?;
    }

    // Best effort. A board whose buffers are already full needs none of this.
    let _ = saturate(debug).await;

    let mut core = CortexM::new(debug);
    core.reset().await?;

    let _ = debug.disconnect().await;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_nrf52833_layout_is_half_a_megabyte() {
        let layout = FlashLayout {
            page_size: 4096,
            page_count: 128,
        };

        assert!(layout.is_plausible());
        assert_eq!(layout.total_bytes(), 512 * 1024);
    }

    #[test]
    fn a_target_that_is_not_ready_yet_is_not_an_answer() {
        // Zeroes come back before the target is up.
        let zeroes = FlashLayout {
            page_size: 0,
            page_count: 0,
        };

        assert!(!zeroes.is_plausible());
    }

    #[test]
    fn rejects_a_page_size_that_is_not_a_power_of_two() {
        let odd = FlashLayout {
            page_size: 3000,
            page_count: 128,
        };

        assert!(!odd.is_plausible());
    }

    #[test]
    fn rejects_a_page_count_that_would_overflow_the_total() {
        let huge = FlashLayout {
            page_size: 4096,
            page_count: u32::MAX,
        };

        assert!(!huge.is_plausible());
    }
}
