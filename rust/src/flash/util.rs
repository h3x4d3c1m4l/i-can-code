//! Deciding which flash pages actually differ.
//!
//! Ported from `partial-flashing-utils.ts` in
//! microbit-foundation/microbit-connection (MIT), itself drawn from
//! microsoft/pxt-microbit (MIT).

/// The two seeds the board's own checksum routine starts from. They are part of
/// the protocol, not a choice: the blob that runs on the target uses these, so a
/// different pair would make every page look changed.
const SEED_0: u32 = 0x2F9B_E6CC;
const SEED_1: u32 = 0x1EC3_A6C8;

const MIX_1: u32 = 0xCC9E_2D51;
const MIX_2: u32 = 0x1B87_3593;
const MIX_3: u32 = 0xE654_6B64;

/// One page of a program, with the address it belongs at.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Page {
    pub target_address: u32,
    pub data: Vec<u8>,
}

/// The pair of hashes the board computes for a page.
///
/// Two of them rather than one because the board's routine tracks two states in
/// parallel, which is cheaper on a Cortex-M than a wider hash.
///
/// `data` is read four bytes at a time, little endian. A length that is not a
/// multiple of four reads whatever follows, so callers pass whole pages.
pub fn murmur3_core(data: &[u8]) -> (u32, u32) {
    let mut h0 = SEED_0;
    let mut h1 = SEED_1;

    for word in data.as_chunks::<4>().0 {
        let mut k = u32::from_le_bytes(*word);
        k = k.wrapping_mul(MIX_1);
        k = k.rotate_left(15);
        k = k.wrapping_mul(MIX_2);

        h0 ^= k;
        h1 ^= k;
        h0 = h0.rotate_left(13);
        h1 = h1.rotate_left(13);
        h0 = h0.wrapping_mul(5).wrapping_add(MIX_3);
        h1 = h1.wrapping_mul(5).wrapping_add(MIX_3);
    }

    (h0, h1)
}

/// Splits `data` into whole pages, each padded with `0xFF`.
///
/// A program rarely starts on a page boundary, so the first page is padded at
/// the front and carries the address of the boundary below it. Flash is erased
/// and written by the page, and that is the unit the board works in.
pub fn page_align_blocks(data: &[u8], target_address: u32, page_size: u32) -> Vec<Page> {
    let size = page_size as usize;
    let mut pages = Vec::new();
    let mut index = 0usize;

    while index < data.len() {
        let mut page = vec![0xFF; size];

        let at = target_address + index as u32;
        let leading = at & (page_size - 1);
        let page_address = at - leading;

        while index < data.len() {
            let offset = target_address + index as u32;
            if offset >= page_address + page_size {
                break;
            }
            page[(offset - page_address) as usize] = data[index];
            index += 1;
        }

        pages.push(Page {
            target_address: page_address,
            data: page,
        });
    }

    pages
}

/// Keeps only the pages whose contents differ from what the board reports.
///
/// `checksums` is what the board's own routine produced: two words per page, in
/// page order from the start of flash. A page the board said nothing about is
/// kept, because not knowing is not the same as matching.
pub fn only_changed(pages: Vec<Page>, checksums: &[u32], page_size: u32) -> Vec<Page> {
    pages
        .into_iter()
        .filter(|page| {
            let index = (page.target_address / page_size) as usize;

            let Some(pair) = checksums.get(index * 2..index * 2 + 2) else {
                return true;
            };

            murmur3_core(&page.data) != (pair[0], pair[1])
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Taken from the reference implementation, run on these exact inputs. The
    /// board computes the same values in its own code, so a difference here is a
    /// difference the hardware would see.
    #[test]
    fn matches_the_reference_hashes() {
        assert_eq!(murmur3_core(&[]), (0x2F9B_E6CC, 0x1EC3_A6C8));
        assert_eq!(murmur3_core(&[0, 0, 0, 0]), (0x5694_0923, 0x2E91_7E9C));
        assert_eq!(murmur3_core(&[0xFF; 4]), (0x3C9E_482A, 0x149B_D29D));
        assert_eq!(murmur3_core(&[1, 2, 3, 4, 5, 6, 7, 8]), (0xFE11_EB0B, 0x8765_C60B));
    }

    #[test]
    fn matches_the_reference_on_whole_pages() {
        // The size it is actually used at, where an error in the loop would
        // otherwise be hidden by a short input.
        let ones = vec![0xFFu8; 4096];
        let zeroes = vec![0u8; 4096];
        let counting: Vec<u8> = (0..4096).map(|i| (i & 0xFF) as u8).collect();

        assert_eq!(murmur3_core(&ones), (0x9AEE_1B69, 0x0EAB_16A3));
        assert_eq!(murmur3_core(&zeroes), (0xA272_6F26, 0xE531_30FE));
        assert_eq!(murmur3_core(&counting), (0xD668_A173, 0xACB7_FBD4));
    }

    #[test]
    fn an_erased_page_and_a_written_one_do_not_collide() {
        let erased = vec![0xFFu8; 4096];
        let mut written = erased.clone();
        // One byte, in the middle, of a page that is otherwise identical.
        written[2048] = 0x00;

        assert_ne!(murmur3_core(&erased), murmur3_core(&written));
    }

    #[test]
    fn a_program_starting_mid_page_is_padded_at_the_front() {
        let pages = page_align_blocks(&[1, 2, 3, 4], 0x1002, 4096);

        assert_eq!(pages.len(), 1);
        assert_eq!(pages[0].target_address, 0x1000);
        assert_eq!(&pages[0].data[..4], &[0xFF, 0xFF, 1, 2]);
        assert_eq!(pages[0].data[4], 3);
        assert_eq!(pages[0].data[4095], 0xFF);
    }

    #[test]
    fn a_program_spanning_a_boundary_becomes_two_pages() {
        let data = vec![0xAAu8; 4096];
        let pages = page_align_blocks(&data, 0x1800, 4096);

        assert_eq!(pages.len(), 2);
        assert_eq!(pages[0].target_address, 0x1000);
        assert_eq!(pages[1].target_address, 0x2000);
        // The first page holds the second half of its own span.
        assert_eq!(pages[0].data[0x7FF], 0xFF);
        assert_eq!(pages[0].data[0x800], 0xAA);
        assert_eq!(pages[1].data[0x7FF], 0xAA);
        assert_eq!(pages[1].data[0x800], 0xFF);
    }

    #[test]
    fn a_page_the_board_already_has_is_dropped() {
        let data = vec![0x11u8; 4096];
        let pages = page_align_blocks(&data, 0x2000, 4096);
        let (h0, h1) = murmur3_core(&pages[0].data);

        // Page index 2, so its pair sits at words 4 and 5.
        let mut checksums = vec![0u32; 6];
        checksums[4] = h0;
        checksums[5] = h1;

        assert!(only_changed(pages, &checksums, 4096).is_empty());
    }

    #[test]
    fn a_page_the_board_says_nothing_about_is_kept() {
        // Not knowing is not the same as matching, and writing a page twice is
        // cheaper than leaving the board running the wrong one.
        let pages = page_align_blocks(&[1, 2, 3, 4], 0x8000, 4096);

        assert_eq!(only_changed(pages.clone(), &[], 4096), pages);
    }

    #[test]
    fn one_changed_page_among_matching_ones_is_the_only_one_kept() {
        let data = vec![0x22u8; 4096 * 3];
        let pages = page_align_blocks(&data, 0, 4096);

        let mut checksums = vec![0u32; 6];
        for (index, page) in pages.iter().enumerate() {
            let (h0, h1) = murmur3_core(&page.data);
            checksums[index * 2] = h0;
            checksums[index * 2 + 1] = h1;
        }
        // The board holds something else in the middle page.
        checksums[2] ^= 1;

        let changed = only_changed(pages, &checksums, 4096);

        assert_eq!(changed.len(), 1);
        assert_eq!(changed[0].target_address, 4096);
    }
}
