//! Sends the core's panics to Dart.
//!
//! The wasm build is `panic_abort`, so a panic never reaches Dart as the
//! `PanicException` flutter_rust_bridge documents: the instance traps, the call
//! it happened in never answers, and the panic's text is only in the console.
//! The hook installed here sends that text on a stream as well, which works
//! from whichever thread panicked.

use std::panic::PanicHookInfo;
use std::sync::OnceLock;

use crate::api::types::CorePanic;
use crate::frb_generated::StreamSink;

/// Where panics go, once Dart has asked for them.
///
/// A `OnceLock` and not a `Mutex`: the hook reads it on the main thread, where
/// a contended lock would be an `Atomics.wait` the browser refuses.
static LISTENER: OnceLock<StreamSink<CorePanic>> = OnceLock::new();

/// Wraps the panic hook already installed, so the console keeps its message.
///
/// MUST run after flutter_rust_bridge's own hooks are in place, or they replace
/// this one.
pub fn install() {
    let previous = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        previous(info);
        if let Some(sink) = LISTENER.get() {
            // A closed stream has nobody left to tell.
            let _ = sink.add(describe(info));
        }
    }));
}

/// Sends every later panic to `sink`. Only the first call counts: a later sink
/// is dropped, which closes its stream.
pub fn listen(sink: StreamSink<CorePanic>) {
    let _ = LISTENER.set(sink);
}

fn describe(info: &PanicHookInfo) -> CorePanic {
    let payload = info.payload();
    // `panic!` with a bare literal carries a `&str`, and with arguments a `String`.
    let message = payload
        .downcast_ref::<&str>()
        .map(|text| (*text).to_owned())
        .or_else(|| payload.downcast_ref::<String>().cloned())
        .unwrap_or_else(|| "(a panic with a payload that is not text)".to_owned());

    CorePanic {
        message,
        location: info
            .location()
            .map(|at| format!("{}:{}:{}", at.file(), at.line(), at.column())),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    /// What [`describe`] makes of the panic `f` raises.
    ///
    /// The hook is global to the test binary, so it is swapped back at once.
    fn described(f: impl FnOnce() + std::panic::UnwindSafe) -> CorePanic {
        static SEEN: Mutex<Option<CorePanic>> = Mutex::new(None);

        let previous = std::panic::take_hook();
        std::panic::set_hook(Box::new(|info| *SEEN.lock().unwrap() = Some(describe(info))));
        let _ = std::panic::catch_unwind(f);
        std::panic::set_hook(previous);

        SEEN.lock().unwrap().take().expect("the hook ran")
    }

    // One test rather than one per case: two at once would swap the hook under
    // each other.
    #[test]
    fn describes_literal_and_formatted_panics() {
        let literal = described(|| panic!("plain"));
        assert_eq!(literal.message, "plain");
        assert!(literal
            .location
            .expect("has a location")
            .starts_with("src/panic_report.rs:"));

        let index = 3;
        let formatted = described(move || panic!("index {index}"));
        assert_eq!(formatted.message, "index 3");
    }
}
