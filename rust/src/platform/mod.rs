//! What differs between a browser worker and a host process.
//!
//! Only the clock. nusb's own backends are the USB split.

#[cfg(target_arch = "wasm32")]
mod web;
#[cfg(target_arch = "wasm32")]
pub use web::sleep;

#[cfg(not(target_arch = "wasm32"))]
mod native;
#[cfg(not(target_arch = "wasm32"))]
pub use native::sleep;
