pub mod microbit;
pub mod types;

/// Runs once, when Dart calls `RustLib.init()`.
///
/// Installs flutter_rust_bridge's panic hook and logger, so a Rust panic reaches
/// the browser console as a message instead of as an unreachable trap.
#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
