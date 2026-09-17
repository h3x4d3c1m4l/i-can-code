//! Fills DAPLink's buffers so it stops eating the target's serial output.
//!
//! Ported from `cdc-saturation.ts` in microbit-foundation/microbit-connection
//! (MIT). The V1 half is left out: it needs a Thumb blob for the nRF51's
//! byte-at-a-time UART, and a V1 is turned away by board id first.
//!
//! See `docs/microbit-usb.md` for what DAPLink does and why this is needed.

use crate::dap::adi::ArmDebug;
use crate::dap::DapError;
use crate::transport::DapTransport;

/// The base of the nRF52833's RAM, so this overwrites the running program.
pub const LOAD_ADDRESS: u32 = 0x2000_0000;

/// Enough to fill the buffers of every known interface chip, with room to
/// spare. About 178 ms at 115200 baud.
const BYTE_COUNT: u32 = 2048;

// nRF52833 UARTE registers, base 0x40002000.
const UARTE_TASKS_STARTTX: u32 = 0x4000_2008;
const UARTE_TASKS_STOPTX: u32 = 0x4000_210C;
const UARTE_EVENTS_ENDTX: u32 = 0x4000_2120;
const UARTE_EVENTS_TXSTOPPED: u32 = 0x4000_2158;
const UARTE_ENABLE: u32 = 0x4000_2500;
const UARTE_PSEL_TXD: u32 = 0x4000_250C;
const UARTE_BAUDRATE: u32 = 0x4000_2524;
const UARTE_TXD_PTR: u32 = 0x4000_2544;
const UARTE_TXD_MAXCNT: u32 = 0x4000_2548;

/// Selects UARTE, the DMA-driven mode, over the legacy UART.
const UARTE_MODE: u32 = 8;

/// The baud rate register's encoding of 115200.
const BAUDRATE_115200: u32 = 0x01D7_E000;

/// The pin a micro:bit V2 talks to its interface chip on.
const V2_TX_PIN: u32 = 6;

/// Each attempt is a USB round trip, so this is also the timeout.
const POLL_ATTEMPTS: usize = 2000;

/// Pushes NUL bytes out of the target's UART until DAPLink stops consuming.
///
/// The caller MUST have halted the processor, and MUST reset it afterwards.
/// This overwrites RAM at [`LOAD_ADDRESS`]; only the reset repairs that.
pub async fn saturate<T: DapTransport>(debug: &mut ArmDebug<T>) -> Result<(), DapError> {
    // The program that was running may be half way through its own transfer.
    debug.write_mem32(UARTE_EVENTS_TXSTOPPED, 0).await?;
    debug.write_mem32(UARTE_TASKS_STOPTX, 1).await?;
    for _ in 0..100 {
        if debug.read_mem32(UARTE_EVENTS_TXSTOPPED).await? != 0 {
            break;
        }
    }

    // The previous program may never have set the peripheral up, so no
    // register here can be assumed to hold anything.
    debug.write_mem32(UARTE_ENABLE, 0).await?;
    debug.write_mem32(UARTE_PSEL_TXD, V2_TX_PIN).await?;
    debug.write_mem32(UARTE_BAUDRATE, BAUDRATE_115200).await?;
    debug.write_mem32(UARTE_ENABLE, UARTE_MODE).await?;

    let zeroes = vec![0u32; (BYTE_COUNT / 4) as usize];
    debug.write_block(LOAD_ADDRESS, &zeroes).await?;

    debug.write_mem32(UARTE_TXD_PTR, LOAD_ADDRESS).await?;
    debug.write_mem32(UARTE_TXD_MAXCNT, BYTE_COUNT).await?;
    debug.write_mem32(UARTE_EVENTS_ENDTX, 0).await?;
    debug.write_mem32(UARTE_TASKS_STARTTX, 1).await?;

    // The DMA engine runs independently of the halted processor.
    for _ in 0..POLL_ATTEMPTS {
        if debug.read_mem32(UARTE_EVENTS_ENDTX).await? != 0 {
            return Ok(());
        }
    }

    // Not an error. The bytes that did get out may have been enough, and failing
    // a connection over a workaround is worse than the problem it works around.
    Ok(())
}
