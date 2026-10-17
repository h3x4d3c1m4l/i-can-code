//! What the core reports about itself rather than about a board.

use crate::api::types::CorePanic;
use crate::frb_generated::StreamSink;

/// Streams every panic the core has from now on, on any thread.
///
/// The stream stays open for the life of the page. Only the first call is
/// listened to; a later one's stream closes at once.
pub async fn core_panics(sink: StreamSink<CorePanic>) {
    crate::panic_report::listen(sink);
}
