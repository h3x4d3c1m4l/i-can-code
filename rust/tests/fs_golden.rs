//! Holds the filesystem builder against output from `@microbit/microbit-fs`.
//!
//! The fixtures are the region bytes that library produces, recorded rather than
//! recomputed: a golden that is regenerated on every run adopts an upstream
//! change silently, which is the one thing it exists to catch. Regenerate them
//! deliberately with `tool/generate_fs_fixtures.js`.

use rust_core::hex::fs::{build, FsLayout};

/// The V2 filesystem region, as `getIntelHexDeviceMemInfo` reads it out of
/// micropython-microbit-v2.1.1.hex.
const V2: FsLayout = FsLayout {
    start: 0x0006_D000,
    end: 0x0007_3000,
    page_size: 4096,
};

fn golden(name: &str) -> Vec<u8> {
    let path = format!("{}/tests/fixtures/fs/{name}.bin", env!("CARGO_MANIFEST_DIR"));
    std::fs::read(&path).unwrap_or_else(|e| panic!("cannot read {path}: {e}"))
}

/// Reports the first difference rather than 24576 bytes of noise.
fn assert_matches(name: &str, actual: &[u8]) {
    let expected = golden(name);

    assert_eq!(actual.len(), expected.len(), "{name}: wrong region length");

    if let Some(at) = (0..expected.len()).find(|&i| actual[i] != expected[i]) {
        let from = at.saturating_sub(8);
        let to = (at + 8).min(expected.len());
        panic!(
            "{name}: first difference at 0x{at:04x}\n  expected {:02x?}\n  actual   {:02x?}",
            &expected[from..to],
            &actual[from..to]
        );
    }
}

#[test]
fn a_region_with_no_files_is_left_alone() {
    // Not even the persistent marker: the reference writes that only when it
    // writes a file.
    assert_matches("empty", &build(V2, &[]).expect("builds"));
}

#[test]
fn one_file_that_fits_in_a_single_chunk() {
    let content = b"from microbit import *\ndisplay.scroll(\"hi\")\n";
    assert_matches("one-chunk", &build(V2, &[("main.py", content)]).expect("builds"));
}

#[test]
fn a_file_that_ends_exactly_on_a_chunk_boundary() {
    // Header plus data lands on 126, so the end offset wraps to zero.
    let content = vec![b'x'; 126 - 9];
    assert_matches("exact-chunk", &build(V2, &[("main.py", &content)]).expect("builds"));
}

#[test]
fn a_file_one_byte_past_a_chunk_boundary() {
    // Forces a second chunk holding a single byte, which is where an off-by-one
    // in the end offset shows up.
    let content = vec![b'x'; 126 - 8];
    assert_matches("chunk-plus-one", &build(V2, &[("main.py", &content)]).expect("builds"));
}

#[test]
fn a_file_spanning_four_chunks_links_them_both_ways() {
    let content = "print(\"line\")\n".repeat(30);
    assert_matches(
        "many-chunks",
        &build(V2, &[("main.py", content.as_bytes())]).expect("builds"),
    );
}

#[test]
fn two_files_carry_on_from_where_the_first_stopped() {
    let files: [(&str, &[u8]); 2] = [
        ("main.py", b"import helper\nhelper.go()\n"),
        ("helper.py", b"def go():\n    print(\"helping\")\n"),
    ];
    assert_matches("two-files", &build(V2, &files).expect("builds"));
}

#[test]
fn a_name_at_the_length_limit_shares_its_chunk_with_the_data() {
    let name = format!("{}.py", "a".repeat(100));
    assert_matches("long-name", &build(V2, &[(name.as_str(), b"pass\n")]).expect("builds"));
}
