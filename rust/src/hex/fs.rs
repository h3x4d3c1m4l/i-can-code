//! MicroPython's on-flash filesystem.
//!
//! Ported from `micropython-fs-builder.ts` in microbit-foundation/microbit-fs
//! (MIT), which follows
//! <https://github.com/bbcmicrobit/micropython/blob/v1.0.1/source/microbit/filesystem.c>.
//!
//! The region is a list of 128-byte chunks. A chunk carries a marker at its head
//! and a pointer to the next chunk in its tail, so a file is a doubly linked
//! list: the first chunk is marked [`MARKER_FILE_START`] and every later one
//! points back at its predecessor. Chunk indices start at 1, because 0 means
//! freed.
//!
//! The last page of the region belongs to MicroPython, which uses it for bulk
//! erase bookkeeping, so no file may go there.

const CHUNK_LEN: usize = 128;
/// One marker byte at the head and one pointer byte at the tail.
const CHUNK_DATA_LEN: usize = CHUNK_LEN - 2;
const TAIL_INDEX: usize = CHUNK_LEN - 1;

const MARKER_FREED: u8 = 0x00;
const MARKER_PERSISTENT: u8 = 0xFD;
const MARKER_FILE_START: u8 = 0xFE;
const MARKER_UNUSED: u8 = 0xFF;

/// A chunk index is one byte and may not collide with a marker, which leaves
/// 256 minus the four marker values.
const MAX_CHUNKS: usize = 256 - 4;

/// MicroPython refuses a longer one.
const MAX_FILENAME_LEN: usize = 120;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FsError {
    /// A name MicroPython will not accept: empty, or over 120 bytes.
    FilenameLength,
    /// The reference implementation refuses a file with no content, so this does
    /// too rather than writing something it would not.
    Empty,
    /// The files do not fit in the region.
    OutOfSpace,
    /// The region is too small to hold its own persistent page.
    RegionTooSmall,
}

/// Where the filesystem lives in the target's flash.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FsLayout {
    pub start: u32,
    /// Exclusive.
    pub end: u32,
    pub page_size: u32,
}

impl FsLayout {
    /// The page MicroPython keeps for itself, which is the last one.
    pub fn persistent_page(self) -> u32 {
        self.end - self.page_size
    }

    /// Where chunk 1 begins.
    ///
    /// Usually [`FsLayout::start`]. A region with room for more than
    /// [`MAX_CHUNKS`] moves up instead, because a chunk index is one byte and
    /// the chunks past that could never be pointed at.
    pub fn first_chunk_address(self) -> u32 {
        let widest = (CHUNK_LEN * MAX_CHUNKS) as u32;
        self.start.max(self.end.saturating_sub(widest))
    }

    /// How many chunks a file may use.
    pub fn chunk_count(self) -> usize {
        let usable = self.persistent_page().saturating_sub(self.first_chunk_address());
        usable as usize / CHUNK_LEN
    }

    pub fn len(self) -> usize {
        (self.end - self.start) as usize
    }

    pub fn is_empty(self) -> bool {
        self.end <= self.start
    }
}

/// What has to be written to flash, as address-and-bytes pairs.
///
/// Only the chunks a file occupies, whole, plus the single persistent-data
/// marker. Everything else in the region stays erased, so a flasher is not asked
/// to write pages of `0xFF`.
pub fn build_spans(layout: FsLayout, files: &[(&str, &[u8])]) -> Result<Vec<(u32, Vec<u8>)>, FsError> {
    if layout.is_empty() || layout.len() < layout.page_size as usize {
        return Err(FsError::RegionTooSmall);
    }

    if files.is_empty() {
        return Ok(Vec::new());
    }

    let base = layout.first_chunk_address();
    let capacity = layout.chunk_count();

    let mut spans = Vec::new();
    let mut next_free = 1usize;

    for (name, content) in files {
        let chunks = chunk_file(name, content)?;
        let span = chunks.len();

        if next_free + span - 1 > capacity {
            return Err(FsError::OutOfSpace);
        }

        for (position, mut chunk) in chunks.into_iter().enumerate() {
            let index = next_free + position;

            chunk[0] = if position == 0 {
                MARKER_FILE_START
            } else {
                // Points back at the chunk before it.
                (index - 1) as u8
            };

            // Every chunk but the last points at the one after it; the last
            // keeps the 0xFF it was filled with.
            if position + 1 < span {
                chunk[TAIL_INDEX] = (index + 1) as u8;
            }

            spans.push((base + ((index - 1) * CHUNK_LEN) as u32, chunk.to_vec()));
        }

        next_free += span;
    }

    // MicroPython's bulk-erase bookkeeping. Written only once something else is,
    // which is what the reference implementation does.
    spans.push((layout.persistent_page(), vec![MARKER_PERSISTENT]));

    Ok(spans)
}

/// The whole region as bytes, `0xFF` where nothing was written.
///
/// What [`build_spans`] produces, painted onto an erased region. Useful for
/// comparing against a recorded filesystem; a flasher wants the spans.
pub fn build(layout: FsLayout, files: &[(&str, &[u8])]) -> Result<Vec<u8>, FsError> {
    let spans = build_spans(layout, files)?;
    let mut region = vec![MARKER_UNUSED; layout.len()];

    for (address, bytes) in spans {
        let at = (address - layout.start) as usize;
        region[at..at + bytes.len()].copy_from_slice(&bytes);
    }

    Ok(region)
}

/// How many chunks a file will occupy, without building it.
pub fn chunk_span(name: &str, content: &[u8]) -> usize {
    let total = header_len(name) + content.len() + 1;
    total.div_ceil(CHUNK_DATA_LEN)
}

/// `[end offset, name length, name...]`, which shares the first chunk with the
/// start of the content.
fn header_len(name: &str) -> usize {
    2 + name.len()
}

/// Splits a file into chunk-sized pieces, with the data in place but the marker
/// and tail still unset.
fn chunk_file(name: &str, content: &[u8]) -> Result<Vec<[u8; CHUNK_LEN]>, FsError> {
    if name.is_empty() || name.len() > MAX_FILENAME_LEN {
        return Err(FsError::FilenameLength);
    }
    if content.is_empty() {
        return Err(FsError::Empty);
    }

    let header = header_len(name);

    let mut payload = Vec::with_capacity(header + content.len() + 1);
    // Where the last chunk's data ends, counted within a chunk's data area. Zero
    // means the file finishes exactly on a boundary.
    payload.push(((header + content.len()) % CHUNK_DATA_LEN) as u8);
    payload.push(name.len() as u8);
    payload.extend_from_slice(name.as_bytes());
    payload.extend_from_slice(content);
    // The reference appends this, and MicroPython reads it back.
    payload.push(MARKER_UNUSED);

    Ok(payload
        .chunks(CHUNK_DATA_LEN)
        .map(|piece| {
            let mut chunk = [MARKER_UNUSED; CHUNK_LEN];
            chunk[1..1 + piece.len()].copy_from_slice(piece);
            chunk
        })
        .collect())
}

/// Whether a marker means the chunk holds nothing.
pub fn is_free(marker: u8) -> bool {
    marker == MARKER_UNUSED || marker == MARKER_FREED
}

#[cfg(test)]
mod tests {
    use super::*;

    const V2: FsLayout = FsLayout {
        start: 0x0006_D000,
        end: 0x0007_3000,
        page_size: 4096,
    };

    #[test]
    fn the_last_page_is_not_available_to_files() {
        // Six pages of region, five of storage. A capacity counted off the whole
        // region would let a file run into MicroPython's own page.
        assert_eq!(V2.len(), 24576);
        assert_eq!(V2.chunk_count() * CHUNK_LEN, 20480);
        assert_eq!(V2.persistent_page(), 0x0007_2000);
    }

    #[test]
    fn a_region_wider_than_the_index_starts_higher_up() {
        // A chunk index is one byte, so chunks below this point could never be
        // pointed at. The start moves up rather than the count being truncated.
        let wide = FsLayout {
            start: 0x0000_0000,
            end: 0x0010_0000,
            page_size: 4096,
        };

        assert_eq!(wide.first_chunk_address(), 0x0010_0000 - (128 * 252));
        assert!(wide.chunk_count() <= MAX_CHUNKS);
    }

    #[test]
    fn refuses_a_name_micropython_would_not_take() {
        let long = "a".repeat(MAX_FILENAME_LEN + 1);

        assert_eq!(build(V2, &[("", b"x")]), Err(FsError::FilenameLength));
        assert_eq!(build(V2, &[(long.as_str(), b"x")]), Err(FsError::FilenameLength));
    }

    #[test]
    fn refuses_a_file_with_no_content() {
        assert_eq!(build(V2, &[("main.py", b"")]), Err(FsError::Empty));
    }

    #[test]
    fn refuses_more_than_fits() {
        let big = vec![b'x'; 20480];

        assert_eq!(build(V2, &[("main.py", &big)]), Err(FsError::OutOfSpace));
    }

    #[test]
    fn fills_the_region_right_up_to_the_persistent_page() {
        // One byte short of the capacity, which must still fit: an off-by-one in
        // the space check shows up here and nowhere else.
        let span = V2.chunk_count();
        let content = vec![b'x'; span * CHUNK_DATA_LEN - 2 - "main.py".len() - 1];

        assert_eq!(chunk_span("main.py", &content), span);
        let region = build(V2, &[("main.py", &content)]).expect("fits exactly");
        assert_eq!(region[(V2.persistent_page() - V2.start) as usize], MARKER_PERSISTENT);
    }

    #[test]
    fn a_second_file_starts_after_the_first() {
        let files: [(&str, &[u8]); 2] = [("a.py", b"1"), ("b.py", b"2")];
        let region = build(V2, &files).expect("builds");

        assert_eq!(region[0], MARKER_FILE_START);
        assert_eq!(region[CHUNK_LEN], MARKER_FILE_START);
        // Neither runs on into the other.
        assert_eq!(region[TAIL_INDEX], MARKER_UNUSED);
    }
}
