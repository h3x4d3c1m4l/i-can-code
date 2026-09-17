//! Intel HEX, as the micro:bit's firmware ships in.
//!
//! Format reference: <https://developer.arm.com/documentation/ka003292/latest>

use std::collections::BTreeMap;
use std::fmt::Write as _;

const RECORD_DATA: u8 = 0x00;
const RECORD_END_OF_FILE: u8 = 0x01;
const RECORD_EXTENDED_SEGMENT: u8 = 0x02;
const RECORD_START_SEGMENT: u8 = 0x03;
const RECORD_EXTENDED_LINEAR: u8 = 0x04;
const RECORD_START_LINEAR: u8 = 0x05;

/// How many data bytes a record carries. Sixteen is what the micro:bit's own
/// firmware uses, and matching it keeps a rewritten hex diffable against it.
const BYTES_PER_RECORD: usize = 16;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum HexError {
    /// A line that should have started with `:`.
    NotARecord { line: usize },
    /// A line whose length or hex digits do not parse.
    Malformed { line: usize },
    /// The record's own checksum byte disagrees with its contents.
    BadChecksum { line: usize },
    /// A record type this does not handle.
    UnknownRecord { line: usize, kind: u8 },
}

/// The bytes of a hex file, by address.
///
/// Sparse on purpose: a firmware hex covers a few separate stretches of flash
/// and says nothing about the gaps, which are erased rather than zero.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct HexMap {
    bytes: BTreeMap<u32, u8>,
    /// Kept so a rewritten hex ends the way the original did. The micro:bit's
    /// firmware carries a start-segment record, and dropping it would change a
    /// file we otherwise only meant to edit.
    start_record: Option<(u8, [u8; 4])>,
}

impl HexMap {
    pub fn get(&self, address: u32) -> Option<u8> {
        self.bytes.get(&address).copied()
    }

    pub fn set(&mut self, address: u32, value: u8) {
        self.bytes.insert(address, value);
    }

    /// Writes `data` from `address` on.
    pub fn set_range(&mut self, address: u32, data: &[u8]) {
        for (offset, byte) in data.iter().enumerate() {
            self.bytes.insert(address + offset as u32, *byte);
        }
    }

    /// Forgets everything in `start..end`, leaving it erased rather than zero.
    pub fn clear_range(&mut self, start: u32, end: u32) {
        let addresses: Vec<u32> = self.bytes.range(start..end).map(|(a, _)| *a).collect();
        for address in addresses {
            self.bytes.remove(&address);
        }
    }

    /// `end - start` bytes, with `fill` wherever the map says nothing.
    pub fn slice(&self, start: u32, end: u32, fill: u8) -> Vec<u8> {
        let mut out = vec![fill; (end - start) as usize];
        for (address, byte) in self.bytes.range(start..end) {
            out[(address - start) as usize] = *byte;
        }
        out
    }

    /// The stretches of flash the file actually covers, lowest first.
    pub fn blocks(&self) -> Vec<(u32, u32)> {
        let mut blocks: Vec<(u32, u32)> = Vec::new();

        for &address in self.bytes.keys() {
            match blocks.last_mut() {
                Some(last) if last.1 + 1 == address => last.1 = address,
                _ => blocks.push((address, address)),
            }
        }

        blocks
    }

    pub fn is_empty(&self) -> bool {
        self.bytes.is_empty()
    }
}

/// Reads a hex file into a map of addresses to bytes.
pub fn parse(text: &str) -> Result<HexMap, HexError> {
    let mut map = HexMap::default();
    let mut upper: u32 = 0;

    for (index, raw) in text.lines().enumerate() {
        let line = index + 1;
        let record = raw.trim_end_matches(['\r', '\n']);

        if record.is_empty() {
            continue;
        }

        let Some(body) = record.strip_prefix(':') else {
            return Err(HexError::NotARecord { line });
        };

        let bytes = decode(body).ok_or(HexError::Malformed { line })?;

        // Length, two address bytes, type, and the checksum.
        if bytes.len() < 5 || bytes.len() != 5 + usize::from(bytes[0]) {
            return Err(HexError::Malformed { line });
        }

        // Every byte including the checksum sums to zero in the low byte.
        if bytes.iter().fold(0u8, |sum, b| sum.wrapping_add(*b)) != 0 {
            return Err(HexError::BadChecksum { line });
        }

        let offset = u32::from(u16::from_be_bytes([bytes[1], bytes[2]]));
        let kind = bytes[3];
        let data = &bytes[4..bytes.len() - 1];

        match kind {
            RECORD_DATA => map.set_range(upper | offset, data),
            RECORD_END_OF_FILE => break,
            RECORD_EXTENDED_LINEAR => {
                let high = u16::from_be_bytes([data[0], data[1]]);
                upper = u32::from(high) << 16;
            }
            RECORD_EXTENDED_SEGMENT => {
                let high = u16::from_be_bytes([data[0], data[1]]);
                upper = u32::from(high) << 4;
            }
            RECORD_START_SEGMENT | RECORD_START_LINEAR => {
                let mut kept = [0u8; 4];
                kept[..data.len().min(4)].copy_from_slice(&data[..data.len().min(4)]);
                map.start_record = Some((kind, kept));
            }
            other => return Err(HexError::UnknownRecord { line, kind: other }),
        }
    }

    Ok(map)
}

/// Writes a map back out as a hex file.
///
/// Not byte-identical to the file it was read from: record lengths and where the
/// extended-address records fall are the writer's choice, and this one rewrites
/// them its own way. What survives is the address-to-byte mapping.
pub fn write(map: &HexMap) -> String {
    let mut out = String::new();
    let mut upper: Option<u32> = None;

    for (start, end) in map.blocks() {
        let mut address = start;

        while address <= end {
            let high = address >> 16;
            if upper != Some(high) {
                let bytes = (high as u16).to_be_bytes();
                push_record(&mut out, 0, RECORD_EXTENDED_LINEAR, &bytes);
                upper = Some(high);
            }

            // A record may not cross a 64KB boundary, because its own address
            // field is only 16 bits wide.
            let to_boundary = 0x1_0000 - u32::from(address as u16);
            let remaining = end - address + 1;
            let len = (BYTES_PER_RECORD as u32).min(to_boundary).min(remaining);

            let data: Vec<u8> = (0..len).map(|i| map.get(address + i).unwrap_or(0xFF)).collect();
            push_record(&mut out, address as u16, RECORD_DATA, &data);

            address += len;
        }
    }

    if let Some((kind, data)) = map.start_record {
        push_record(&mut out, 0, kind, &data);
    }

    push_record(&mut out, 0, RECORD_END_OF_FILE, &[]);
    out
}

fn push_record(out: &mut String, offset: u16, kind: u8, data: &[u8]) {
    let mut sum = (data.len() as u8)
        .wrapping_add((offset >> 8) as u8)
        .wrapping_add(offset as u8)
        .wrapping_add(kind);

    let _ = write!(out, ":{:02X}{:04X}{:02X}", data.len(), offset, kind);
    for byte in data {
        let _ = write!(out, "{byte:02X}");
        sum = sum.wrapping_add(*byte);
    }
    let _ = writeln!(out, "{:02X}", sum.wrapping_neg());
}

fn decode(body: &str) -> Option<Vec<u8>> {
    if !body.len().is_multiple_of(2) {
        return None;
    }

    body.as_bytes()
        .chunks(2)
        .map(|pair| u8::from_str_radix(std::str::from_utf8(pair).ok()?, 16).ok())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_data_records_through_an_extended_address() {
        let hex = ":020000040001F9\n:0400000012345678E8\n:00000001FF\n";
        let map = parse(hex).expect("parses");

        assert_eq!(map.get(0x0001_0000), Some(0x12));
        assert_eq!(map.get(0x0001_0003), Some(0x78));
        assert_eq!(map.get(0x0001_0004), None);
    }

    #[test]
    fn refuses_a_record_whose_checksum_does_not_agree() {
        // The same record with its last byte turned into something else.
        let hex = ":0400000012345678E9\n:00000001FF\n";

        assert_eq!(parse(hex), Err(HexError::BadChecksum { line: 1 }));
    }

    #[test]
    fn refuses_a_line_that_is_not_a_record() {
        assert_eq!(parse("not a record\n"), Err(HexError::NotARecord { line: 1 }));
    }

    #[test]
    fn refuses_a_record_shorter_than_its_own_length_byte() {
        assert_eq!(parse(":10000000ABCDEF\n"), Err(HexError::Malformed { line: 1 }));
    }

    #[test]
    fn stops_at_the_end_of_file_record() {
        // Anything after it belongs to no file and must not be read.
        let hex = ":00000001FF\n:0400000012345678E8\n";

        assert!(parse(hex).expect("parses").is_empty());
    }

    #[test]
    fn a_written_hex_reads_back_the_same() {
        let mut map = HexMap::default();
        map.set_range(0x0000_0000, &[1, 2, 3]);
        // A second block, far enough away to need its own extended address.
        map.set_range(0x0002_0000, &[4, 5, 6]);

        assert_eq!(parse(&write(&map)).expect("parses"), map);
    }

    #[test]
    fn a_block_crossing_a_64k_boundary_is_split() {
        // A record's address field is 16 bits, so one cannot straddle the edge.
        let mut map = HexMap::default();
        map.set_range(0x0000_FFF8, &[0xAA; 16]);

        let written = write(&map);
        assert_eq!(parse(&written).expect("parses"), map);
        assert!(written.contains(":020000040001"), "expected a new extended address");
    }

    #[test]
    fn blocks_are_the_stretches_actually_covered() {
        let mut map = HexMap::default();
        map.set_range(0x100, &[1, 2, 3]);
        map.set_range(0x200, &[4]);

        assert_eq!(map.blocks(), vec![(0x100, 0x102), (0x200, 0x200)]);
    }

    #[test]
    fn clearing_leaves_a_gap_rather_than_zeroes() {
        let mut map = HexMap::default();
        map.set_range(0x100, &[1, 2, 3, 4]);
        map.clear_range(0x101, 0x103);

        assert_eq!(map.get(0x101), None);
        assert_eq!(map.slice(0x100, 0x104, 0xFF), vec![1, 0xFF, 0xFF, 4]);
    }
}
