//! The table a MicroPython hex carries describing its own flash layout.
//!
//! Ported from `flash-regions.ts` in microbit-foundation/microbit-fs (MIT).
//!
//! The reference tries a UICR block first and falls back to this table. That
//! UICR block is V1's, and a V2 hex has none, so only the table is ported here.
//!
//! The table sits at the end of the MicroPython region and is read upwards: a
//! 16-byte header, with the region rows stacked *below* it.
//!
//! ```text
//!   header - n*16 | region row n
//!   ...           | ...
//!   header        | MAGIC_1 | VERSION | TABLE_LEN | REG_COUNT | P_SIZE | MAGIC_2
//! ```

use crate::hex::fs::FsLayout;
use crate::hex::intel::HexMap;

const MAGIC_1: u32 = 0x597F_30FE;
const MAGIC_2: u32 = 0xC1B1_D79D;

const ROW_LEN: u32 = 16;

/// The row that describes where files live.
const REGION_ID_FS: u8 = 3;

/// Where to stop searching downwards. Below this is the SoftDevice, which
/// carries no table.
const SEARCH_FLOOR: u32 = 0x1000;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RegionError {
    /// No header with both magic words. Not a MicroPython hex, or not one whose
    /// layout is described this way.
    NoTable,
    /// The header is there but names no filesystem region.
    NoFilesystem,
    /// The header's page size is not one a flash could have.
    BadPageSize { page_size: u32 },
}

/// One row of the table.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Region {
    pub id: u8,
    pub start: u32,
    pub length: u32,
}

/// What the table says about the flash it describes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FlashRegions {
    pub page_size: u32,
    pub regions: Vec<Region>,
}

impl FlashRegions {
    pub fn region(&self, id: u8) -> Option<Region> {
        self.regions.iter().copied().find(|r| r.id == id)
    }
}

/// Reads the table out of a parsed hex.
pub fn read(map: &HexMap) -> Result<FlashRegions, RegionError> {
    let header = find_header(map).ok_or(RegionError::NoTable)?;

    let version_and_len = word(map, header + 4).ok_or(RegionError::NoTable)?;
    let counts = word(map, header + 8).ok_or(RegionError::NoTable)?;

    let region_count = counts & 0xFFFF;
    let page_size_log2 = counts >> 16;

    // A page size the hardware could not have means the header was matched by
    // accident, or read at the wrong offset.
    if !(9..=16).contains(&page_size_log2) {
        return Err(RegionError::BadPageSize {
            page_size: 1u32.checked_shl(page_size_log2).unwrap_or(0),
        });
    }
    let page_size = 1u32 << page_size_log2;

    // The rows are stacked downwards from the header, first row nearest it.
    let mut regions = Vec::with_capacity(region_count as usize);
    for index in 0..region_count {
        let row = header.checked_sub((index + 1) * ROW_LEN).ok_or(RegionError::NoTable)?;

        let first = word(map, row).ok_or(RegionError::NoTable)?;
        let length = word(map, row + 4).ok_or(RegionError::NoTable)?;

        regions.push(Region {
            id: (first & 0xFF) as u8,
            start: ((first >> 16) & 0xFFFF) * page_size,
            length,
        });
    }

    // Version is read only to keep the offset honest; nothing branches on it.
    let _version = version_and_len & 0xFFFF;

    Ok(FlashRegions { page_size, regions })
}

/// Where the filesystem lives, according to the hex itself.
///
/// The end is rounded up to a whole page: the row's length is what MicroPython
/// reserved, and a filesystem is made of pages.
pub fn fs_layout(map: &HexMap) -> Result<FsLayout, RegionError> {
    let table = read(map)?;
    let fs = table.region(REGION_ID_FS).ok_or(RegionError::NoFilesystem)?;

    let pages = fs.length.div_ceil(table.page_size);

    Ok(FsLayout {
        start: fs.start,
        end: fs.start + pages * table.page_size,
        page_size: table.page_size,
    })
}

/// Searches downwards for a header carrying both magic words.
///
/// Downwards because the table sits at the top of the MicroPython region, and
/// the first match from above is the one that belongs to it. Word-aligned, since
/// that is how it is written.
fn find_header(map: &HexMap) -> Option<u32> {
    let highest = map
        .blocks()
        .iter()
        .filter(|(start, _)| *start < 0x0008_0000)
        .map(|(_, end)| *end)
        .max()?;

    let mut address = highest & !0x3;

    while address > SEARCH_FLOOR {
        if word(map, address) == Some(MAGIC_1) && word(map, address + 12) == Some(MAGIC_2) {
            return Some(address);
        }
        address -= 4;
    }

    None
}

/// A little-endian word, or `None` when any of its bytes is missing.
fn word(map: &HexMap, address: u32) -> Option<u32> {
    let mut value = 0u32;
    for offset in 0..4 {
        value |= u32::from(map.get(address + offset)?) << (8 * offset);
    }
    Some(value)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Builds a table the way a MicroPython hex carries one.
    fn table_at(header: u32, page_size_log2: u16, rows: &[(u8, u16, u32)]) -> HexMap {
        let mut map = HexMap::default();

        // Something below the table, so `find_header` has a block to search from.
        map.set_range(0x1000, &[0x00; 16]);

        map.set_range(header, &MAGIC_1.to_le_bytes());
        map.set_range(header + 4, &1u32.to_le_bytes());
        let counts = (u32::from(page_size_log2) << 16) | rows.len() as u32;
        map.set_range(header + 8, &counts.to_le_bytes());
        map.set_range(header + 12, &MAGIC_2.to_le_bytes());

        for (index, (id, start_page, length)) in rows.iter().enumerate() {
            let row = header - (index as u32 + 1) * ROW_LEN;
            let first = (u32::from(*start_page) << 16) | u32::from(*id);
            map.set_range(row, &first.to_le_bytes());
            map.set_range(row + 4, &length.to_le_bytes());
        }

        map
    }

    #[test]
    fn reads_the_rows_stacked_under_the_header() {
        let map = table_at(0x0006_7FF0, 12, &[(3, 109, 24576), (2, 28, 309836), (1, 1, 110592)]);

        let table = read(&map).expect("reads");

        assert_eq!(table.page_size, 4096);
        assert_eq!(
            table.region(3),
            Some(Region {
                id: 3,
                start: 0x0006_D000,
                length: 24576
            })
        );
        assert_eq!(
            table.region(1),
            Some(Region {
                id: 1,
                start: 0x0000_1000,
                length: 110592
            })
        );
    }

    #[test]
    fn the_filesystem_layout_comes_out_page_aligned() {
        // A length that is not a whole number of pages still describes pages.
        let map = table_at(0x0006_7FF0, 12, &[(3, 109, 24576 - 100)]);

        let layout = fs_layout(&map).expect("reads");

        assert_eq!(layout.start, 0x0006_D000);
        assert_eq!(layout.end, 0x0007_3000);
        assert_eq!(layout.page_size, 4096);
    }

    #[test]
    fn refuses_a_hex_with_no_table() {
        let mut map = HexMap::default();
        map.set_range(0x1000, &[0xAB; 64]);

        assert_eq!(read(&map), Err(RegionError::NoTable));
    }

    #[test]
    fn refuses_a_table_that_names_no_filesystem() {
        let map = table_at(0x0006_7FF0, 12, &[(2, 28, 309836), (1, 1, 110592)]);

        assert_eq!(fs_layout(&map), Err(RegionError::NoFilesystem));
    }

    #[test]
    fn refuses_a_page_size_no_flash_has() {
        // A stray match on the magic words would otherwise divide by whatever
        // happened to be in the next word.
        let map = table_at(0x0006_7FF0, 40, &[(3, 109, 24576)]);

        assert!(matches!(read(&map), Err(RegionError::BadPageSize { .. })));
    }
}
