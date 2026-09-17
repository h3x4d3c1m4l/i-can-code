//! Turning a parsed hex into the bytes flash should end up holding.
//!
//! Ported from `extractFlashAndUicr` in `partial-flashing.ts` in
//! microbit-foundation/microbit-connection (MIT).

use crate::hex::intel::HexMap;

/// The whole of flash as the hex describes it, gaps filled with `0xFF`.
///
/// Padded rather than sparse because the board hashes every page it has, and a
/// page the hex says nothing about is one that has to come out erased. A page
/// that is already erased then hashes the same and is left alone.
///
/// `flash_size` is what the chip reports, which is also what keeps UICR out of
/// the image: a MicroPython hex carries words at 0x10001000, far past the end of
/// flash.
pub fn flash_image(map: &HexMap, flash_size: u32) -> Vec<u8> {
    map.slice(0, flash_size, 0xFF)
}

/// Where UICR sits in the address map. Not flash, and not part of a flash
/// image, but a MicroPython hex carries words for it.
const UICR_START: u32 = 0x1000_1000;
const UICR_END: u32 = 0x1000_2000;

/// The words a hex puts in UICR, in address order.
///
/// A partial flash writes flash and nothing else, so these say what it would be
/// leaving behind. Only whole words are reported; a hex that covers three bytes
/// of one describes nothing a caller could write.
pub fn uicr_entries(map: &HexMap) -> Vec<(u32, u32)> {
    let mut entries = Vec::new();
    let mut address = UICR_START;

    while address < UICR_END {
        let bytes: Option<Vec<u8>> = (0..4).map(|offset| map.get(address + offset)).collect();

        if let Some(bytes) = bytes {
            let value = u32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]);
            entries.push((address, value));
        }

        address += 4;
    }

    entries
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_gap_in_the_hex_comes_out_erased() {
        let mut map = HexMap::default();
        map.set_range(0, &[1, 2, 3, 4]);
        map.set_range(16, &[5]);

        let image = flash_image(&map, 32);

        assert_eq!(image.len(), 32);
        assert_eq!(&image[..4], &[1, 2, 3, 4]);
        assert_eq!(&image[4..16], &[0xFF; 12]);
        assert_eq!(image[16], 5);
        assert_eq!(image[31], 0xFF);
    }

    #[test]
    fn the_uicr_words_come_out_in_address_order() {
        let mut map = HexMap::default();
        map.set_range(0, &[0xAA; 8]);
        map.set_range(0x1000_1014, &0x1234_5678u32.to_le_bytes());
        map.set_range(0x1000_1080, &0x0000_00FFu32.to_le_bytes());

        assert_eq!(
            uicr_entries(&map),
            vec![(0x1000_1014, 0x1234_5678), (0x1000_1080, 0x0000_00FF)]
        );
    }

    #[test]
    fn half_a_uicr_word_is_not_a_word() {
        // Nothing could be written from it, and writing the other half as zeroes
        // would clear bits the hex never asked about.
        let mut map = HexMap::default();
        map.set_range(0x1000_1014, &[0x12, 0x34]);

        assert!(uicr_entries(&map).is_empty());
    }

    #[test]
    fn what_the_hex_holds_above_flash_is_left_out() {
        let mut map = HexMap::default();
        map.set_range(0, &[0xAA; 4]);
        map.set_range(0x1000_1000, &[0xBB; 4]);

        let image = flash_image(&map, 512 * 1024);

        assert_eq!(image.len(), 512 * 1024);
        assert!(!image[4..].contains(&0xBB));
    }
}
