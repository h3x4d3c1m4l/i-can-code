//! Which micro:bit is on the other end of the cable.
//!
//! Ported from `board-id.ts` and `board-serial-info.ts` in
//! microbit-foundation/microbit-connection (MIT).

/// The hardware generation a board id names.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BoardVersion {
    V1,
    V2,
}

/// A micro:bit board id: the first four hex characters of a DAPLink serial.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BoardId(u16);

impl BoardId {
    /// V2 is four ids. The micro:bit support docs list only 9903 and 9904, so a
    /// check written from them rejects current V2.21 hardware.
    const V1_IDS: [u16; 2] = [0x9900, 0x9901];
    const V2_IDS: [u16; 4] = [0x9903, 0x9904, 0x9905, 0x9906];

    /// The id, or `None` for one neither generation claims.
    pub fn new(id: u16) -> Option<BoardId> {
        let known = Self::V1_IDS.contains(&id) || Self::V2_IDS.contains(&id);
        known.then_some(BoardId(id))
    }

    /// Parses four hex characters with no `0x` prefix, as they appear in a
    /// serial number.
    pub fn parse(value: &str) -> Option<BoardId> {
        u16::from_str_radix(value, 16).ok().and_then(BoardId::new)
    }

    pub fn version(self) -> BoardVersion {
        if Self::V1_IDS.contains(&self.0) {
            BoardVersion::V1
        } else {
            BoardVersion::V2
        }
    }

    /// The id back as it is written, lower case and four characters wide.
    pub fn to_hex(self) -> String {
        format!("{:04x}", self.0)
    }
}

/// What a DAPLink serial number says about the board carrying it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BoardSerialInfo {
    pub board_id: BoardId,
    pub family_id: String,
    /// The interface chip. `DETAILS.TXT` on the mounted volume prints the same
    /// value as `HIC ID`, which is how one of these can be checked by hand.
    pub hic: String,
}

impl BoardSerialInfo {
    /// A DAPLink serial is 48 characters: id, family id, then padding and the
    /// HIC id in the last eight.
    const SERIAL_LEN: usize = 48;

    /// Reads a serial apart, or `None` when the id is not one we know.
    ///
    /// A wrong length is accepted, as upstream does: every field is read from a
    /// fixed end of the string.
    pub fn from_serial(serial: &str) -> Option<BoardSerialInfo> {
        if serial.len() < 8 {
            return None;
        }

        Some(BoardSerialInfo {
            board_id: BoardId::parse(&serial[0..4])?,
            family_id: serial[4..8].to_string(),
            hic: serial[serial.len() - 8..].to_string(),
        })
    }

    /// Whether this serial is the length DAPLink is supposed to report.
    pub fn is_expected_length(serial: &str) -> bool {
        serial.len() == Self::SERIAL_LEN
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The V2.21 board this was developed against. Its last eight characters
    /// match the `HIC ID` in its own DETAILS.TXT.
    const REAL_SERIAL: &str = "990636020005282026fc669c6d36d053000000006e052820";

    #[test]
    fn reads_a_real_v2_serial() {
        let info = BoardSerialInfo::from_serial(REAL_SERIAL).expect("parses");

        assert_eq!(info.board_id.to_hex(), "9906");
        assert_eq!(info.board_id.version(), BoardVersion::V2);
        assert_eq!(info.family_id, "3602");
        assert_eq!(info.hic, "6e052820");
        assert!(BoardSerialInfo::is_expected_length(REAL_SERIAL));
    }

    #[test]
    fn accepts_every_v2_id_including_the_two_the_docs_omit() {
        for id in ["9903", "9904", "9905", "9906"] {
            let board = BoardId::parse(id).unwrap_or_else(|| panic!("{id} should be a V2 board"));
            assert_eq!(board.version(), BoardVersion::V2, "{id}");
        }
    }

    #[test]
    fn accepts_both_v1_ids() {
        for id in ["9900", "9901"] {
            let board = BoardId::parse(id).unwrap_or_else(|| panic!("{id} should be a V1 board"));
            assert_eq!(board.version(), BoardVersion::V1, "{id}");
        }
    }

    #[test]
    fn rejects_an_id_no_generation_claims() {
        // 9902 sits between the two blocks and belongs to neither.
        assert_eq!(BoardId::parse("9902"), None);
        assert_eq!(BoardId::parse("0000"), None);
        assert_eq!(BoardId::parse("zzzz"), None);
    }

    #[test]
    fn rejects_a_serial_too_short_to_read() {
        assert_eq!(BoardSerialInfo::from_serial("9906"), None);
        assert_eq!(BoardSerialInfo::from_serial(""), None);
    }
}
