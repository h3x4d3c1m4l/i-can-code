pub mod diagnostics;
pub mod microbit;
pub mod types;

/// Runs once, when Dart calls `RustLib.init()`.
///
/// Installs flutter_rust_bridge's panic hook and logger, so a Rust panic reaches
/// the browser console as a message before the instance traps, and then the hook
/// that hands the same panic to [`diagnostics::core_panics`].
#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
    crate::panic_report::install();
}
