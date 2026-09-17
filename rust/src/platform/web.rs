/// Yields for `millis`.
///
/// MUST NOT be replaced by a spin. A worker that never yields keeps a core busy
/// and starves the other workers in the pool.
pub async fn sleep(millis: u32) {
    gloo_timers::future::TimeoutFuture::new(millis).await;
}
