//! Putting a student's files into a MicroPython hex.

use crate::hex::flash_regions::{fs_layout, RegionError};
use crate::hex::fs::{build_spans, FsError};
use crate::hex::intel::{parse, write, HexError, HexMap};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BuildError {
    Hex(HexError),
    Region(RegionError),
    Fs(FsError),
}

/// Returns `firmware` with `files` written into its filesystem.
///
/// The firmware decides where that is: the layout comes out of the hex's own
/// region table, never from a constant here, so a different MicroPython build
/// lands in the right place without this knowing about it.
///
/// Any filesystem already in the hex is dropped. This writes a fresh one rather
/// than editing what is there.
pub fn build_hex(firmware: &str, files: &[(&str, &[u8])]) -> Result<String, BuildError> {
    Ok(write(&build_map(firmware, files)?))
}

/// The same thing as bytes by address, before it is written back out.
///
/// What a caller that has to reason about the flash itself works from. Turning
/// the text back into a map costs a second parse of a megabyte.
pub fn build_map(firmware: &str, files: &[(&str, &[u8])]) -> Result<HexMap, BuildError> {
    let mut map = parse(firmware).map_err(BuildError::Hex)?;
    let layout = fs_layout(&map).map_err(BuildError::Region)?;
    let spans = build_spans(layout, files).map_err(BuildError::Fs)?;

    map.clear_range(layout.start, layout.end);

    for (address, bytes) in spans {
        map.set_range(address, &bytes);
    }

    Ok(map)
}
