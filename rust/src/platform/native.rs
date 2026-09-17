use std::time::Duration;

/// Yields for `millis`.
///
/// Needs a tokio runtime, which only `cargo test` and a future desktop build
/// provide.
pub async fn sleep(millis: u32) {
    tokio::time::sleep(Duration::from_millis(u64::from(millis))).await;
}
