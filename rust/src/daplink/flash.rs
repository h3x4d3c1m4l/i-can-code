//! Writing a whole hex to the board through DAPLink's own flash commands.
//!
//! Ported from `daplink.ts` in microbit-foundation/microbit-connection (MIT).
//!
//! This is the slow path, and the one partial flashing falls back to. DAPLink
//! does the erasing and programming itself; nothing here touches SWD.

use crate::dap::cmsis::CmsisDap;
use crate::dap::DapError;
use crate::transport::DapTransport;

pub const DAPLINK_VENDOR_FLASH_RESET: u8 = 0x89;
pub const DAPLINK_VENDOR_FLASH_OPEN: u8 = 0x8A;
pub const DAPLINK_VENDOR_FLASH_CLOSE: u8 = 0x8B;
pub const DAPLINK_VENDOR_FLASH_WRITE: u8 = 0x8C;

/// DAPLink answers with an `error_t` in byte 1.
const ERROR_SUCCESS: u8 = 0;
/// What it sends when it has read the hex's end-of-file record.
const ERROR_SUCCESS_DONE: u8 = 18;

/// The stream is Intel HEX. DAPLink can take a raw binary too; this does not.
const STREAM_TYPE_HEX: u32 = 1;

/// A write carries a length byte and then this much.
const MAX_WRITE: usize = 62;

/// Sends `hex` to the board and resets it.
///
/// `hex` is the file's own text, which DAPLink parses; it is not decoded here.
/// `on_progress` is called with a fraction between 0 and 1.
///
/// The board reboots into the new program when this returns. The caller MUST
/// treat anything it knew about the target as stale afterwards.
pub async fn full_flash<T: DapTransport>(
    dap: &mut CmsisDap<T>,
    hex: &str,
    mut on_progress: impl FnMut(f32),
) -> Result<(), DapError> {
    let response = dap
        .send(DAPLINK_VENDOR_FLASH_OPEN, &STREAM_TYPE_HEX.to_le_bytes())
        .await?;
    expect_success(DAPLINK_VENDOR_FLASH_OPEN, &response)?;

    match stream(dap, hex, &mut on_progress).await {
        Ok(()) => {}
        Err(error) => {
            // Leaving the stream open wedges DAPLink for the next attempt.
            let _ = dap.send(DAPLINK_VENDOR_FLASH_CLOSE, &[]).await;
            return Err(error);
        }
    }

    let response = dap.send(DAPLINK_VENDOR_FLASH_CLOSE, &[]).await?;
    expect_success(DAPLINK_VENDOR_FLASH_CLOSE, &response)?;

    dap.send(DAPLINK_VENDOR_FLASH_RESET, &[]).await?;

    Ok(())
}

async fn stream<T: DapTransport>(
    dap: &mut CmsisDap<T>,
    hex: &str,
    on_progress: &mut impl FnMut(f32),
) -> Result<(), DapError> {
    let bytes = hex.as_bytes();
    let mut offset = 0usize;

    while offset < bytes.len() {
        let end = (offset + MAX_WRITE).min(bytes.len());
        let piece = &bytes[offset..end];

        let mut payload = Vec::with_capacity(piece.len() + 1);
        payload.push(piece.len() as u8);
        payload.extend_from_slice(piece);

        let response = dap.send(DAPLINK_VENDOR_FLASH_WRITE, &payload).await?;

        on_progress(offset as f32 / bytes.len() as f32);
        offset = end;

        // The status is read but deliberately not checked for failure. A V1
        // board reports ERROR_ERASE_SECTOR late in a flash that then succeeds,
        // and dapjs never checked it either. The one value that matters is the
        // one that says the hex is finished.
        if response.get(1) == Some(&ERROR_SUCCESS_DONE) {
            break;
        }
    }

    on_progress(1.0);
    Ok(())
}

fn expect_success(command: u8, response: &[u8]) -> Result<(), DapError> {
    let status = *response.get(1).ok_or(DapError::Truncated {
        command,
        length: response.len(),
    })?;

    if status == ERROR_SUCCESS {
        Ok(())
    } else {
        Err(DapError::BadStatus { command, status })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::transport::{TransportError, PACKET_SIZE};
    use std::collections::VecDeque;

    struct MockTransport {
        responses: VecDeque<Vec<u8>>,
        written: Vec<Vec<u8>>,
    }

    impl DapTransport for MockTransport {
        async fn read(&mut self) -> Result<Vec<u8>, TransportError> {
            self.responses
                .pop_front()
                .ok_or_else(|| TransportError::Io("nothing scripted".to_string()))
        }

        async fn write(&mut self, data: &[u8]) -> Result<(), TransportError> {
            self.written.push(data.to_vec());
            Ok(())
        }
    }

    fn packet(bytes: &[u8]) -> Vec<u8> {
        let mut out = vec![0u8; PACKET_SIZE];
        out[..bytes.len()].copy_from_slice(bytes);
        out
    }

    fn block_on<F: std::future::Future>(future: F) -> F::Output {
        use std::task::{Context, Poll, Waker};

        let mut context = Context::from_waker(Waker::noop());
        let mut future = Box::pin(future);

        loop {
            if let Poll::Ready(value) = future.as_mut().poll(&mut context) {
                return value;
            }
        }
    }

    /// Enough replies for an open, `writes` writes, a close and a reset.
    fn script(writes: usize, last_write_status: u8) -> MockTransport {
        let mut responses = vec![packet(&[DAPLINK_VENDOR_FLASH_OPEN, ERROR_SUCCESS])];

        for index in 0..writes {
            let status = if index + 1 == writes {
                last_write_status
            } else {
                ERROR_SUCCESS
            };
            responses.push(packet(&[DAPLINK_VENDOR_FLASH_WRITE, status]));
        }

        responses.push(packet(&[DAPLINK_VENDOR_FLASH_CLOSE, ERROR_SUCCESS]));
        responses.push(packet(&[DAPLINK_VENDOR_FLASH_RESET, ERROR_SUCCESS]));

        MockTransport {
            responses: responses.into(),
            written: Vec::new(),
        }
    }

    #[test]
    fn sends_the_hex_in_length_prefixed_pieces() {
        let hex = "x".repeat(MAX_WRITE + 10);
        let mut dap = CmsisDap::new(script(2, ERROR_SUCCESS));

        block_on(full_flash(&mut dap, &hex, |_| {})).expect("flashes");

        let written = dap.into_transport().written;
        // Open, two writes, close, reset.
        assert_eq!(written.len(), 5);
        assert_eq!(written[1][0], DAPLINK_VENDOR_FLASH_WRITE);
        assert_eq!(written[1][1], MAX_WRITE as u8, "length byte");
        assert_eq!(written[2][1], 10, "the remainder");
    }

    #[test]
    fn stops_when_daplink_says_the_hex_is_finished() {
        // The board reports DONE while there is still text left, which is what
        // happens when the end-of-file record is not the last line.
        let hex = "y".repeat(MAX_WRITE * 4);
        let mut dap = CmsisDap::new(script(1, ERROR_SUCCESS_DONE));

        block_on(full_flash(&mut dap, &hex, |_| {})).expect("flashes");

        let written = dap.into_transport().written;
        assert_eq!(written.len(), 4, "open, one write, close, reset");
    }

    #[test]
    fn a_failed_open_never_starts_writing() {
        let responses = vec![packet(&[DAPLINK_VENDOR_FLASH_OPEN, 5])];
        let mut dap = CmsisDap::new(MockTransport {
            responses: responses.into(),
            written: Vec::new(),
        });

        let error = block_on(full_flash(&mut dap, "anything", |_| {})).expect_err("refuses");

        assert_eq!(
            error,
            DapError::BadStatus {
                command: DAPLINK_VENDOR_FLASH_OPEN,
                status: 5,
            }
        );
    }

    #[test]
    fn a_write_error_is_ignored_because_a_v1_reports_one_and_still_succeeds() {
        let hex = "z".repeat(10);
        // 16 is ERROR_ERASE_SECTOR, which a V1 sends late in a flash that works.
        let mut dap = CmsisDap::new(script(1, 16));

        block_on(full_flash(&mut dap, &hex, |_| {})).expect("carries on");
    }

    #[test]
    fn a_failure_part_way_through_still_closes_the_stream() {
        // Two replies: the open, then a write answering the wrong command. A
        // stream left open wedges the next attempt.
        let responses = vec![
            packet(&[DAPLINK_VENDOR_FLASH_OPEN, ERROR_SUCCESS]),
            packet(&[DAPLINK_VENDOR_FLASH_RESET, ERROR_SUCCESS]),
            packet(&[DAPLINK_VENDOR_FLASH_CLOSE, ERROR_SUCCESS]),
        ];
        let mut dap = CmsisDap::new(MockTransport {
            responses: responses.into(),
            written: Vec::new(),
        });

        block_on(full_flash(&mut dap, "data", |_| {})).expect_err("fails");

        let written = dap.into_transport().written;
        assert_eq!(written.last().map(|w| w[0]), Some(DAPLINK_VENDOR_FLASH_CLOSE));
    }

    #[test]
    fn progress_ends_at_one() {
        let hex = "q".repeat(MAX_WRITE * 3);
        let mut dap = CmsisDap::new(script(3, ERROR_SUCCESS));

        let mut seen = Vec::new();
        block_on(full_flash(&mut dap, &hex, |fraction| seen.push(fraction))).expect("flashes");

        assert_eq!(seen.first(), Some(&0.0));
        assert_eq!(seen.last(), Some(&1.0));
        assert!(seen.windows(2).all(|pair| pair[0] <= pair[1]), "never goes backwards");
    }
}
