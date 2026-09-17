//! Builds against the real MicroPython firmware, not a synthetic hex.
//!
//! Skipped when the firmware is absent, the way the Dart tests skip without a
//! `python3`. Fetch it with `just fetch-microbit-firmware`.

use rust_core::hex::builder::build_hex;
use rust_core::hex::flash_regions::fs_layout;
use rust_core::hex::intel::{parse, HexMap};

const FIRMWARE: &str = "../assets/microbit/micropython-microbit-v2.1.1.hex";

fn firmware() -> Option<String> {
    let path = format!("{}/{FIRMWARE}", env!("CARGO_MANIFEST_DIR"));
    std::fs::read_to_string(path).ok()
}

fn golden(name: &str) -> Vec<u8> {
    let path = format!("{}/tests/fixtures/fs/{name}.bin", env!("CARGO_MANIFEST_DIR"));
    std::fs::read(&path).unwrap_or_else(|e| panic!("cannot read {path}: {e}"))
}

#[test]
fn the_firmware_describes_its_own_filesystem() {
    let Some(firmware) = firmware() else {
        eprintln!("skipped: no firmware, run `just fetch-microbit-firmware`");
        return;
    };

    let layout = fs_layout(&parse(&firmware).expect("parses")).expect("has a table");

    // What @microbit/microbit-fs reads out of this same file.
    assert_eq!(layout.start, 446464);
    assert_eq!(layout.end, 471040);
    assert_eq!(layout.page_size, 4096);
}

#[test]
fn a_built_hex_carries_the_filesystem_the_reference_would_have_written() {
    let Some(firmware) = firmware() else {
        eprintln!("skipped: no firmware, run `just fetch-microbit-firmware`");
        return;
    };

    let before = parse(&firmware).expect("parses");
    let layout = fs_layout(&before).expect("has a table");

    let content = b"from microbit import *\ndisplay.scroll(\"hi\")\n";
    let built = build_hex(&firmware, &[("main.py", content)]).expect("builds");
    let after = parse(&built).expect("parses back");

    assert_eq!(
        after.slice(layout.start, layout.end, 0xFF),
        golden("one-chunk"),
        "the filesystem region differs from the reference"
    );
}

#[test]
fn nothing_outside_the_filesystem_is_touched() {
    let Some(firmware) = firmware() else {
        eprintln!("skipped: no firmware, run `just fetch-microbit-firmware`");
        return;
    };

    let before = parse(&firmware).expect("parses");
    let layout = fs_layout(&before).expect("has a table");

    let built = build_hex(&firmware, &[("main.py", b"pass\n")]).expect("builds");
    let after = parse(&built).expect("parses back");

    // Everything the firmware covers, minus the region this is allowed to write.
    // A builder that shifted an address or dropped a record shows up here rather
    // than as a board that will not boot.
    let mut differences = Vec::new();
    for (start, end) in before.blocks() {
        for address in start..=end {
            if (layout.start..layout.end).contains(&address) {
                continue;
            }
            if before.get(address) != after.get(address) {
                differences.push(address);
            }
        }
    }

    assert!(
        differences.is_empty(),
        "{} addresses changed outside the filesystem, first at 0x{:08X}",
        differences.len(),
        differences.first().copied().unwrap_or_default()
    );
}

#[test]
fn a_rebuild_replaces_the_previous_filesystem() {
    let Some(firmware) = firmware() else {
        eprintln!("skipped: no firmware, run `just fetch-microbit-firmware`");
        return;
    };

    let layout = fs_layout(&parse(&firmware).expect("parses")).expect("has a table");

    // Building on top of a hex that already has files must not leave the old
    // ones behind, which is what a student replacing their program does.
    let first = build_hex(&firmware, &[("main.py", b"print(\"one\")\n")]).expect("builds");
    let second = build_hex(&first, &[("main.py", b"print(\"two\")\n")]).expect("rebuilds");

    let fresh = build_hex(&firmware, &[("main.py", b"print(\"two\")\n")]).expect("builds");

    let region = |hex: &str| -> Vec<u8> { parse(hex).expect("parses").slice(layout.start, layout.end, 0xFF) };

    assert_eq!(region(&second), region(&fresh));
}

#[test]
fn an_empty_map_has_no_table_to_read() {
    assert!(fs_layout(&HexMap::default()).is_err());
}
