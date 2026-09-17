//! The two ARM Thumb programs that run on the board itself.
//!
//! Taken verbatim from microsoft/pxt-microbit (MIT), by way of
//! `partial-flashing.ts` in microbit-foundation/microbit-connection (MIT). The C
//! they were built from is at
//! <https://github.com/microsoft/pxt-microbit/blob/dec5b871/external/sha/source/main.c>.
//!
//! Neither is decompiled or re-derived here. What matters for reviewing this
//! file is the register convention each expects, which is written down beside
//! it, because the words themselves say nothing.
//!
//! Both are loaded at [`LOAD_ADDRESS`] and both end at a breakpoint, which is
//! how the debugger knows they are done. They differ in where that breakpoint
//! is: the checksum blob carries its own, while the page writer is entered past
//! the one in its first word and returns to it.
//!
//! Both MUST be run on a processor that was reset into a halted state. See
//! [`crate::dap::cortex_m::CortexM::reset_and_halt`].

/// Where a blob is written and run. The base of the target's RAM, which is why
/// whatever was running there is gone afterwards.
pub const LOAD_ADDRESS: u32 = 0x2000_0000;

/// The stack a blob runs on.
pub const STACK_ADDRESS: u32 = 0x2000_1000;

/// Where a blob puts its results, and where a page's contents are staged.
///
/// Far enough above the stack that neither reaches the other.
pub const DATA_ADDRESS: u32 = 0x2000_2000;

/// Computes a murmur3 pair over every flash page, on the board.
///
/// `void computeHashes(uint32_t *dst, uint8_t *ptr, uint32_t pageSize, uint32_t numPages)`
///
/// Entered with r0 = where to write the results, r1 = 0 (the start of flash),
/// r2 = the page size, r3 = how many pages. It writes `numPages * 2` words at
/// r0, which the caller reads back.
///
/// **This blob only reads flash.** A mistake in the registers around it costs a
/// wrong answer, not a damaged board, which is why it is the one to get working
/// first.
///
/// Laid out six words to a row, as the source has it, so the two can be read
/// side by side. rustfmt would reflow that into rows of nine.
#[rustfmt::skip]
pub const COMPUTE_CHECKSUMS: [u32; 48] = [
    0x4c27b5f0, 0x44a52680, 0x22009201, 0x91004f25, 0x00769303, 0x24080013,
    0x25010019, 0x40eb4029, 0xd0002900, 0x3c01407b, 0xd1f52c00, 0x468c0091,
    0xa9044665, 0x506b3201, 0xd1eb42b2, 0x089b9b01, 0x23139302, 0x9b03469c,
    0xd104429c, 0x2000be2a, 0x449d4b15, 0x9f00bdf0, 0x4d149e02, 0x49154a14,
    0x3e01cf08, 0x2111434b, 0x491341cb, 0x405a434b, 0x4663405d, 0x230541da,
    0x4b10435a, 0x466318d2, 0x230541dd, 0x4b0d435d, 0x2e0018ed, 0x6002d1e7,
    0x9a009b01, 0x18d36045, 0x93003008, 0xe7d23401, 0xfffffbec, 0xedb88320,
    0x00000414, 0x1ec3a6c8, 0x2f9be6cc, 0xcc9e2d51, 0x1b873593, 0xe6546b64,
];

/// Copies one page from RAM into flash.
///
/// Entered with r0 = the flash address to write, r1 = where the page is staged
/// in RAM, r2 = the page size in words. Unlike the other blob it is entered at
/// `LOAD_ADDRESS + 4`, past the breakpoint in the first word.
///
/// **This blob erases and writes flash.** Nothing here is checked by the
/// hardware afterwards.
#[rustfmt::skip]
pub const FLASH_PAGE: [u32; 36] = [
    // bkpt, which LR points at so that returning halts the processor.
    0xbe00be00,
    0x2502b5f0, 0x4c204b1f, 0xf3bf511d, 0xf3bf8f6f, 0x25808f4f, 0x002e00ed,
    0x2f00595f, 0x25a1d0fc, 0x515800ed, 0x2d00599d, 0x2500d0fc, 0xf3bf511d,
    0xf3bf8f6f, 0x25808f4f, 0x002e00ed, 0x2f00595f, 0x2501d0fc, 0xf3bf511d,
    0xf3bf8f6f, 0x599d8f4f, 0xd0fc2d00, 0x25002680, 0x00f60092, 0xd1094295,
    0x511a2200, 0x8f6ff3bf, 0x8f4ff3bf, 0x2a00599a, 0xbdf0d0fc, 0x5147594f,
    0x2f00599f, 0x3504d0fc, 0x46c0e7ec, 0x4001e000, 0x00000504,
];

// The three addresses are picked by hand, so moving one has to be caught here
// rather than by a board that runs the result. COMPUTE_CHECKSUMS is the longer
// of the two blobs.
const _: () = assert!(
    LOAD_ADDRESS + (COMPUTE_CHECKSUMS.len() * 4) as u32 <= STACK_ADDRESS,
    "a blob would run into its own stack"
);
const _: () = assert!(STACK_ADDRESS < DATA_ADDRESS, "the stack would run into the results");

#[cfg(test)]
mod tests {
    use super::*;

    /// A word dropped or transposed in a copy-paste is silent otherwise: the
    /// blob still loads and still runs, and answers nonsense.
    #[test]
    fn the_blobs_are_the_length_the_source_gives() {
        assert_eq!(COMPUTE_CHECKSUMS.len(), 48);
        assert_eq!(FLASH_PAGE.len(), 36);
    }

    #[test]
    fn each_blob_starts_and_ends_where_the_source_does() {
        assert_eq!(COMPUTE_CHECKSUMS[0], 0x4c27b5f0);
        assert_eq!(COMPUTE_CHECKSUMS[47], 0xe6546b64);

        // The first word is the breakpoint LR is pointed at.
        assert_eq!(FLASH_PAGE[0], 0xbe00be00);
        assert_eq!(FLASH_PAGE[35], 0x00000504);
    }

    #[test]
    fn the_checksum_blob_carries_the_seeds_the_port_uses() {
        // The same two words as `flash::util`. If these ever disagree, every
        // page looks changed and partial flashing silently becomes a full one.
        assert!(COMPUTE_CHECKSUMS.contains(&0x1ec3a6c8));
        assert!(COMPUTE_CHECKSUMS.contains(&0x2f9be6cc));
    }
}
