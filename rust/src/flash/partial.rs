//! Writing only the pages that differ.
//!
//! Ported from `partial-flashing.ts` in microbit-foundation/microbit-connection
//! (MIT), itself drawn from microsoft/pxt-microbit (MIT).
//!
//! See `docs/microbit-usb.md` for why this runs code on the board rather than
//! comparing hashes from the hex.

use crate::dap::adi::ArmDebug;
use crate::dap::cortex_m::{CortexM, REGISTER_LR, REGISTER_PC, REGISTER_SP};
use crate::dap::DapError;
use crate::flash::blobs::{COMPUTE_CHECKSUMS, DATA_ADDRESS, FLASH_PAGE, LOAD_ADDRESS, STACK_ADDRESS};
use crate::flash::util::{only_changed, page_align_blocks, Page};
use crate::transport::DapTransport;

/// Asks the board to hash every one of its own flash pages.
///
/// Returns two words per page, in page order from the start of flash, which is
/// what [`crate::flash::util::only_changed`] expects.
///
/// Reads flash and nothing else. The processor is halted and its RAM overwritten
/// to do it, so whatever was running does not survive.
pub async fn read_flash_checksums<T: DapTransport>(
    debug: &mut ArmDebug<T>,
    page_size: u32,
    page_count: u32,
) -> Result<Vec<u32>, DapError> {
    {
        let mut core = CortexM::new(debug);
        core.execute(
            LOAD_ADDRESS,
            &COMPUTE_CHECKSUMS,
            STACK_ADDRESS,
            // Thumb code is entered with the low bit set.
            LOAD_ADDRESS + 1,
            // Returning is not how this one ends; it runs to its own breakpoint.
            0xFFFF_FFFF,
            &[DATA_ADDRESS, 0, page_size, page_count],
        )
        .await?;
    }

    debug.read_block(DATA_ADDRESS, (page_count * 2) as usize).await
}

/// What a flash would have to write, and how much of the flash that is.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FlashPlan {
    /// Every page of the image, changed or not.
    pub total: usize,
    /// The pages the board does not already hold.
    pub changed: Vec<Page>,
}

impl FlashPlan {
    /// Whether writing page by page is still the cheaper way round.
    ///
    /// Past half the flash it is not: every page costs a blob run and a block
    /// write over SWD, while DAPLink erases and programs the whole thing itself.
    pub fn worth_partial(&self) -> bool {
        self.changed.len() <= self.total / 2
    }
}

/// Works out which pages of `image` the board does not already have.
///
/// `image` is the whole of flash from address 0, the way
/// [`crate::flash::image::flash_image`] pads it. Reads the board and writes
/// nothing.
pub async fn plan_flash<T: DapTransport>(
    debug: &mut ArmDebug<T>,
    image: &[u8],
    page_size: u32,
    page_count: u32,
) -> Result<FlashPlan, DapError> {
    let checksums = read_flash_checksums(debug, page_size, page_count).await?;
    let pages = page_align_blocks(image, 0, page_size);
    let total = pages.len();

    Ok(FlashPlan {
        total,
        changed: only_changed(pages, &checksums, page_size),
    })
}

/// Writes `pages` into the target's flash, one page at a time.
///
/// The caller MUST have connected SWD. Erases and writes flash: a failure part
/// way through leaves the board holding some of the new program and some of the
/// old, which only a full flash repairs.
///
/// `on_progress` is called with a fraction between 0 and 1.
pub async fn write_pages<T: DapTransport>(
    debug: &mut ArmDebug<T>,
    pages: &[Page],
    page_size: u32,
    mut on_progress: impl FnMut(f32),
) -> Result<(), DapError> {
    if pages.is_empty() {
        on_progress(1.0);
        return Ok(());
    }

    CortexM::new(debug).reset_and_halt().await?;
    debug.write_block(LOAD_ADDRESS, &FLASH_PAGE).await?;

    // The first page is staged here; every later one was staged while the page
    // before it was being written.
    stage(debug, &pages[0], staging_address(0, page_size)).await?;

    for (index, page) in pages.iter().enumerate() {
        start_page_write(debug, page, staging_address(index, page_size), page_size).await?;

        // While the target erases and writes, which is the slow part.
        if let Some(next) = pages.get(index + 1) {
            stage(debug, next, staging_address(index + 1, page_size)).await?;
        }

        CortexM::new(debug).wait_for_halt().await?;
        on_progress((index + 1) as f32 / pages.len() as f32);
    }

    Ok(())
}

/// Which of the two staging slots a page goes in.
///
/// Two, so that the next page can be sent while the target is still writing
/// this one. Which slot an index takes does not matter; that they alternate
/// does.
fn staging_address(index: usize, page_size: u32) -> u32 {
    if index.is_multiple_of(2) {
        DATA_ADDRESS + page_size
    } else {
        DATA_ADDRESS
    }
}

/// Puts a page's bytes in the target's RAM, where the blob copies them from.
async fn stage<T: DapTransport>(debug: &mut ArmDebug<T>, page: &Page, address: u32) -> Result<(), DapError> {
    let words: Vec<u32> = page
        .data
        .as_chunks::<4>()
        .0
        .iter()
        .map(|bytes| u32::from_le_bytes(*bytes))
        .collect();

    debug.write_block(address, &words).await
}

/// Starts the blob on one page and returns without waiting for it.
///
/// Entered past the breakpoint in the blob's first word, with LR pointing at
/// it, so the copy stops the processor by returning.
async fn start_page_write<T: DapTransport>(
    debug: &mut ArmDebug<T>,
    page: &Page,
    staged_at: u32,
    page_size: u32,
) -> Result<(), DapError> {
    let mut core = CortexM::new(debug);

    core.halt().await?;
    core.write_core_register(REGISTER_PC, LOAD_ADDRESS + 4 + 1).await?;
    core.write_core_register(REGISTER_LR, LOAD_ADDRESS + 1).await?;
    core.write_core_register(REGISTER_SP, STACK_ADDRESS).await?;
    core.write_core_register(0, page.target_address).await?;
    core.write_core_register(1, staged_at).await?;
    core.write_core_register(2, page_size / 4).await?;

    core.start().await?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn plan(total: usize, changed: usize) -> FlashPlan {
        FlashPlan {
            total,
            changed: vec![
                Page {
                    target_address: 0,
                    data: Vec::new(),
                };
                changed
            ],
        }
    }

    #[test]
    fn a_few_changed_pages_are_worth_writing_one_at_a_time() {
        assert!(plan(128, 3).worth_partial());
    }

    #[test]
    fn past_half_the_flash_they_are_not() {
        assert!(plan(128, 64).worth_partial());
        assert!(!plan(128, 65).worth_partial());
    }
}
