//! Framing CMSIS-DAP commands.

use crate::dap::DapError;
use crate::transport::{DapTransport, PACKET_SIZE};

pub const DAP_INFO: u8 = 0x00;
pub const DAP_TRANSFER: u8 = 0x05;
pub const DAP_TRANSFER_BLOCK: u8 = 0x06;
pub const DAP_CONNECT: u8 = 0x02;
pub const DAP_DISCONNECT: u8 = 0x03;
pub const DAP_TRANSFER_CONFIGURE: u8 = 0x04;
pub const DAP_WRITE_ABORT: u8 = 0x08;
pub const DAP_SWJ_CLOCK: u8 = 0x11;
pub const DAP_SWJ_SEQUENCE: u8 = 0x12;

/// Commands whose second response byte is a status rather than data.
const STATUS_CHECK_COMMANDS: [u8; 5] = [
    DAP_DISCONNECT,
    DAP_WRITE_ABORT,
    DAP_SWJ_CLOCK,
    DAP_SWJ_SEQUENCE,
    DAP_TRANSFER_CONFIGURE,
];

const DAP_OK: u8 = 0x00;

/// `DAP_Connect` answers 0 when the mode it was asked for is not available.
const DAP_CONNECT_FAILED: u8 = 0x00;

/// Which port an operation addresses.
pub const DP: u8 = 0x00;
pub const AP: u8 = 0x01;

/// Which direction. These are bits in the same byte as the port and register,
/// which is why they are masks rather than an enum.
pub const WRITE: u8 = 0x00;
pub const READ: u8 = 0x02;

/// `DAP_Transfer` answers a bitfield. Only the first bit is success.
const TRANSFER_OK: u8 = 0x01;
const TRANSFER_WAIT: u8 = 0x02;
const TRANSFER_FAULT: u8 = 0x04;
const TRANSFER_ERROR: u8 = 0x08;
const TRANSFER_MISMATCH: u8 = 0x10;

/// Every bit of `ABORT` that clears a sticky error.
pub const ABORT_ALL: u32 = (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4);

/// `[DAP index, count u16, register]` in front of a block transfer's payload.
const BLOCK_HEADER_SIZE: usize = 4;
/// `[DAP index, count]` in front of a transfer's operations.
const TRANSFER_HEADER_SIZE: usize = 2;
/// One operation: the port/mode/register byte plus a 32-bit value.
const TRANSFER_OPERATION_SIZE: usize = 5;

/// One register access in a `DAP_Transfer` batch.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DapOperation {
    pub port: u8,
    pub mode: u8,
    pub register: u8,
    /// Ignored for a read, and sent as zero.
    pub value: u32,
}

impl DapOperation {
    pub fn read(port: u8, register: u8) -> DapOperation {
        DapOperation {
            port,
            mode: READ,
            register,
            value: 0,
        }
    }

    pub fn write(port: u8, register: u8, value: u32) -> DapOperation {
        DapOperation {
            port,
            mode: WRITE,
            register,
            value,
        }
    }

    pub fn is_read(self) -> bool {
        self.mode == READ
    }
}

/// Puts a transfer response code into words.
pub fn transfer_response_message(response: u8) -> &'static str {
    if response == 0 {
        "no ACK, the target is not responding"
    } else if response & TRANSFER_WAIT != 0 {
        "target busy, retries exhausted"
    } else if response & TRANSFER_FAULT != 0 {
        "access fault"
    } else if response & TRANSFER_ERROR != 0 {
        "protocol error"
    } else if response & TRANSFER_MISMATCH != 0 {
        "value mismatch"
    } else {
        "transfer failed"
    }
}

/// What `DAP_Info` can be asked for. The ones that answer a string.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum DapInfoId {
    VendorName = 0x01,
    ProductName = 0x02,
    SerialNumber = 0x03,
    ProtocolVersion = 0x04,
}

/// A CMSIS-DAP conversation over one transport.
pub struct CmsisDap<T: DapTransport> {
    transport: T,
}

impl<T: DapTransport> CmsisDap<T> {
    pub fn new(transport: T) -> CmsisDap<T> {
        CmsisDap { transport }
    }

    /// Sends one command and returns its whole response packet.
    ///
    /// `&mut self` is what keeps two callers from interleaving conversations on
    /// one pipe. Upstream needs a promise queue for that.
    pub async fn send(&mut self, command: u8, data: &[u8]) -> Result<Vec<u8>, DapError> {
        let mut packet = Vec::with_capacity(data.len() + 1);
        packet.push(command);
        packet.extend_from_slice(data);

        self.transport.write(&packet).await?;
        let response = self.transport.read().await?;

        let Some(&echoed) = response.first() else {
            return Err(DapError::Truncated { command, length: 0 });
        };

        if echoed != command {
            return Err(DapError::ResponseMismatch {
                expected: command,
                actual: echoed,
            });
        }

        if STATUS_CHECK_COMMANDS.contains(&command) {
            let status = *response.get(1).ok_or(DapError::Truncated {
                command,
                length: response.len(),
            })?;

            if status != DAP_OK {
                return Err(DapError::BadStatus { command, status });
            }
        }

        Ok(response)
    }

    /// One of `DAP_Info`'s string fields, or `None` where it is empty.
    ///
    /// Firmware tends to count the terminating NUL in the length, so the result
    /// is trimmed rather than trusted.
    pub async fn info_string(&mut self, id: DapInfoId) -> Result<Option<String>, DapError> {
        let response = self.send(DAP_INFO, &[id as u8]).await?;
        Ok(read_counted_string(&response))
    }

    /// Reads a vendor command that answers a counted string. The vendor range
    /// 0x80..=0x9F is DAPLink's own, framed like `DAP_Info`.
    pub async fn vendor_string(&mut self, command: u8) -> Result<Option<String>, DapError> {
        let response = self.send(command, &[]).await?;
        Ok(read_counted_string(&response))
    }

    /// Reads a vendor command that answers a counted run of bytes.
    ///
    /// Bytes rather than a string: MicroPython can split one UTF-8 sequence
    /// across two reads, so the caller decodes the stream.
    pub async fn vendor_bytes(&mut self, command: u8, data: &[u8]) -> Result<Vec<u8>, DapError> {
        let response = self.send(command, data).await?;

        let length = usize::from(*response.get(1).ok_or(DapError::Truncated {
            command,
            length: response.len(),
        })?);

        if length == 0 {
            return Ok(Vec::new());
        }

        response
            .get(2..2 + length)
            .map(<[u8]>::to_vec)
            .ok_or(DapError::Truncated {
                command,
                length: response.len(),
            })
    }

    /// Throws away replies left over from an interrupted session.
    ///
    /// Without this every command is answered by the one before it. Reads until
    /// a known probe matches, then reads as many again: each stale reply
    /// consumed displaced one still queued.
    pub async fn drain_stale_responses(&mut self) -> Result<(), DapError> {
        const MAX_ATTEMPTS: usize = 10;

        for attempt in 0..MAX_ATTEMPTS {
            self.transport.write(&[DAP_INFO, DapInfoId::VendorName as u8]).await?;

            let response = self.transport.read().await?;

            if response.first() == Some(&DAP_INFO) {
                for _ in 0..attempt {
                    self.transport.read().await?;
                }
                return Ok(());
            }
        }

        // Not an error. The caller's own first command will fail with a
        // mismatch if this really did not clear, and that says more.
        Ok(())
    }

    /// How many bytes of payload fit in one block transfer.
    ///
    /// A packet less the block header and the command byte. That is 14 words on
    /// a 64-byte packet, so reading a flash page is a loop.
    pub fn block_size(&self) -> usize {
        PACKET_SIZE - BLOCK_HEADER_SIZE - 1
    }

    /// Clears every sticky error bit in `ABORT`.
    ///
    /// MUST follow any failed transfer. A sticky error latches, so one bad read
    /// otherwise fails every transfer after it.
    pub async fn clear_abort(&mut self) -> Result<(), DapError> {
        let mut data = [0u8; 5];
        data[1..5].copy_from_slice(&ABORT_ALL.to_le_bytes());
        self.send(DAP_WRITE_ABORT, &data).await?;
        Ok(())
    }

    /// Clocks raw bits onto SWDIO/SWCLK, for the JTAG-to-SWD switch sequence.
    pub async fn swj_sequence(&mut self, bits: &[u8]) -> Result<(), DapError> {
        let mut payload = Vec::with_capacity(bits.len() + 1);
        // The length is in bits. 256 wraps to 0, which the protocol reads as
        // 256; nothing here sends that many.
        payload.push((bits.len() * 8) as u8);
        payload.extend_from_slice(bits);
        self.send(DAP_SWJ_SEQUENCE, &payload).await?;
        Ok(())
    }

    pub async fn swj_clock(&mut self, frequency: u32) -> Result<(), DapError> {
        self.send(DAP_SWJ_CLOCK, &frequency.to_le_bytes()).await?;
        Ok(())
    }

    /// Attaches to the target in the debugger's default mode, which is SWD here.
    pub async fn connect(&mut self) -> Result<(), DapError> {
        let response = self.send(DAP_CONNECT, &[0]).await?;

        match response.get(1) {
            Some(&mode) if mode != DAP_CONNECT_FAILED => Ok(()),
            _ => Err(DapError::BadStatus {
                command: DAP_CONNECT,
                status: DAP_CONNECT_FAILED,
            }),
        }
    }

    pub async fn disconnect(&mut self) -> Result<(), DapError> {
        self.send(DAP_DISCONNECT, &[]).await?;
        Ok(())
    }

    /// Sets how the debug unit retries a target that answers WAIT.
    pub async fn configure_transfer(
        &mut self,
        idle_cycles: u8,
        wait_retry: u16,
        match_retry: u16,
    ) -> Result<(), DapError> {
        let mut data = [0u8; 5];
        data[0] = idle_cycles;
        data[1..3].copy_from_slice(&wait_retry.to_le_bytes());
        data[3..5].copy_from_slice(&match_retry.to_le_bytes());
        self.send(DAP_TRANSFER_CONFIGURE, &data).await?;
        Ok(())
    }

    /// Runs a batch of register accesses as one `DAP_Transfer`, returning one
    /// word per read.
    ///
    /// One packet, so nothing interleaves. An AP read is three accesses that
    /// only mean anything together: select the bank, set the address, read.
    pub async fn transfer(&mut self, operations: &[DapOperation]) -> Result<Vec<u32>, DapError> {
        if operations.is_empty() {
            return Ok(Vec::new());
        }

        let mut data = vec![0u8; TRANSFER_HEADER_SIZE + operations.len() * TRANSFER_OPERATION_SIZE];
        // Byte 0 is the DAP index, which SWD ignores.
        data[1] = operations.len() as u8;

        for (index, operation) in operations.iter().enumerate() {
            let offset = TRANSFER_HEADER_SIZE + index * TRANSFER_OPERATION_SIZE;
            data[offset] = operation.port | operation.mode | operation.register;
            data[offset + 1..offset + 5].copy_from_slice(&operation.value.to_le_bytes());
        }

        let expected_reads = operations.iter().filter(|o| o.is_read()).count();

        match self.transfer_inner(&data, operations.len(), expected_reads).await {
            Ok(values) => Ok(values),
            Err(error) => {
                // This call is lost either way, but a sticky error would fail
                // every transfer after it too.
                let _ = self.clear_abort().await;
                Err(error)
            }
        }
    }

    async fn transfer_inner(&mut self, data: &[u8], total: usize, expected_reads: usize) -> Result<Vec<u32>, DapError> {
        let result = self.send(DAP_TRANSFER, data).await?;

        let completed = usize::from(*result.get(1).ok_or(DapError::Truncated {
            command: DAP_TRANSFER,
            length: result.len(),
        })?);
        let response = *result.get(2).ok_or(DapError::Truncated {
            command: DAP_TRANSFER,
            length: result.len(),
        })?;

        if response != TRANSFER_OK {
            return Err(DapError::Transfer {
                response,
                completed,
                total,
            });
        }

        if completed != total {
            return Err(DapError::Transfer {
                response,
                completed,
                total,
            });
        }

        read_words(&result, 3, expected_reads).ok_or(DapError::Truncated {
            command: DAP_TRANSFER,
            length: result.len(),
        })
    }

    /// Reads `count` words from one register with `DAP_TransferBlock`.
    ///
    /// `count` MUST be within [`CmsisDap::block_size`] divided by four.
    pub async fn transfer_block_read(&mut self, port: u8, register: u8, count: usize) -> Result<Vec<u32>, DapError> {
        debug_assert!(count * 4 <= self.block_size(), "block read longer than one packet");

        let mut data = [0u8; BLOCK_HEADER_SIZE];
        data[1..3].copy_from_slice(&(count as u16).to_le_bytes());
        data[3] = port | READ | register;

        match self.transfer_block_inner(&data, count, true).await {
            Ok(values) => Ok(values),
            Err(error) => {
                let _ = self.clear_abort().await;
                Err(error)
            }
        }
    }

    /// Writes `values` to one register with `DAP_TransferBlock`.
    pub async fn transfer_block_write(&mut self, port: u8, register: u8, values: &[u32]) -> Result<(), DapError> {
        debug_assert!(
            values.len() * 4 <= self.block_size(),
            "block write longer than one packet"
        );

        let mut data = vec![0u8; BLOCK_HEADER_SIZE + values.len() * 4];
        data[1..3].copy_from_slice(&(values.len() as u16).to_le_bytes());
        data[3] = port | WRITE | register;

        for (index, value) in values.iter().enumerate() {
            let offset = BLOCK_HEADER_SIZE + index * 4;
            data[offset..offset + 4].copy_from_slice(&value.to_le_bytes());
        }

        match self.transfer_block_inner(&data, values.len(), false).await {
            Ok(_) => Ok(()),
            Err(error) => {
                let _ = self.clear_abort().await;
                Err(error)
            }
        }
    }

    async fn transfer_block_inner(&mut self, data: &[u8], count: usize, reading: bool) -> Result<Vec<u32>, DapError> {
        let result = self.send(DAP_TRANSFER_BLOCK, data).await?;

        let truncated = DapError::Truncated {
            command: DAP_TRANSFER_BLOCK,
            length: result.len(),
        };

        // A block transfer counts in 16 bits, unlike a plain transfer's 8.
        let completed = match (result.get(1), result.get(2)) {
            (Some(&low), Some(&high)) => usize::from(u16::from_le_bytes([low, high])),
            _ => return Err(truncated),
        };
        let response = *result.get(3).ok_or(truncated.clone())?;

        if response != TRANSFER_OK || completed != count {
            return Err(DapError::Transfer {
                response,
                completed,
                total: count,
            });
        }

        if !reading {
            return Ok(Vec::new());
        }

        read_words(&result, 4, count).ok_or(truncated)
    }

    pub fn into_transport(self) -> T {
        self.transport
    }
}

/// Reads `count` little-endian words out of `bytes`, starting at `offset`.
fn read_words(bytes: &[u8], offset: usize, count: usize) -> Option<Vec<u32>> {
    let slice = bytes.get(offset..offset + count * 4)?;

    Some(
        slice
            .as_chunks::<4>()
            .0
            .iter()
            .copied()
            .map(u32::from_le_bytes)
            .collect(),
    )
}

/// Reads `[command, length, bytes...]` into a string.
///
/// `None` for a zero length, and for bytes that are not UTF-8: these fields are
/// ASCII, so anything else is not one.
fn read_counted_string(response: &[u8]) -> Option<String> {
    let length = usize::from(*response.get(1)?);
    if length == 0 {
        return None;
    }

    let bytes = response.get(2..2 + length)?;
    let text = std::str::from_utf8(bytes).ok()?;
    let trimmed = text.trim_end_matches('\0').trim();

    (!trimmed.is_empty()).then(|| trimmed.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::transport::{TransportError, PACKET_SIZE};
    use std::collections::VecDeque;

    /// Answers from a script and records what it was asked, so framing can be
    /// checked without a board.
    struct MockTransport {
        responses: VecDeque<Vec<u8>>,
        written: Vec<Vec<u8>>,
    }

    impl MockTransport {
        fn new(responses: Vec<Vec<u8>>) -> MockTransport {
            MockTransport {
                responses: responses.into(),
                written: Vec::new(),
            }
        }
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

    /// Lays `bytes` out as the device would answer: a full packet, zero padded.
    fn packet(bytes: &[u8]) -> Vec<u8> {
        let mut out = vec![0u8; PACKET_SIZE];
        out[..bytes.len()].copy_from_slice(bytes);
        out
    }

    fn counted(command: u8, text: &str) -> Vec<u8> {
        let mut bytes = vec![command, text.len() as u8];
        bytes.extend_from_slice(text.as_bytes());
        packet(&bytes)
    }

    fn block_on<F: std::future::Future>(future: F) -> F::Output {
        // Nothing here yields to a reactor, so spinning on `poll` keeps an
        // async runtime out of the dependency list.
        use std::task::{Context, Poll, Waker};

        let mut context = Context::from_waker(Waker::noop());
        let mut future = Box::pin(future);

        loop {
            if let Poll::Ready(value) = future.as_mut().poll(&mut context) {
                return value;
            }
        }
    }

    #[test]
    fn puts_the_command_byte_in_front_of_its_payload() {
        let mut dap = CmsisDap::new(MockTransport::new(vec![packet(&[DAP_INFO, 0])]));

        block_on(dap.send(DAP_INFO, &[0x01])).expect("sends");

        assert_eq!(dap.into_transport().written, vec![vec![DAP_INFO, 0x01]]);
    }

    #[test]
    fn reads_a_counted_string() {
        let mut dap = CmsisDap::new(MockTransport::new(vec![counted(DAP_INFO, "ARM")]));

        let name = block_on(dap.info_string(DapInfoId::VendorName)).expect("reads");

        assert_eq!(name.as_deref(), Some("ARM"));
    }

    #[test]
    fn trims_the_terminator_firmware_counts_in_the_length() {
        let mut dap = CmsisDap::new(MockTransport::new(vec![counted(DAP_INFO, "DAPLink\0")]));

        let name = block_on(dap.info_string(DapInfoId::ProductName)).expect("reads");

        assert_eq!(name.as_deref(), Some("DAPLink"));
    }

    #[test]
    fn reads_an_empty_field_as_nothing_rather_than_a_failure() {
        let mut dap = CmsisDap::new(MockTransport::new(vec![packet(&[DAP_INFO, 0])]));

        let name = block_on(dap.info_string(DapInfoId::SerialNumber)).expect("reads");

        assert_eq!(name, None);
    }

    #[test]
    fn refuses_a_response_answering_a_different_command() {
        let mut dap = CmsisDap::new(MockTransport::new(vec![packet(&[DAP_CONNECT, 0x01])]));

        let error = block_on(dap.send(DAP_INFO, &[0x01])).expect_err("mismatches");

        assert_eq!(
            error,
            DapError::ResponseMismatch {
                expected: DAP_INFO,
                actual: DAP_CONNECT,
            }
        );
    }

    #[test]
    fn checks_the_status_byte_only_where_there_is_one() {
        // DAP_SWJ_CLOCK answers OK or ERROR in byte 1.
        let mut failing = CmsisDap::new(MockTransport::new(vec![packet(&[DAP_SWJ_CLOCK, 0xFF])]));
        let error = block_on(failing.send(DAP_SWJ_CLOCK, &[])).expect_err("bad status");
        assert_eq!(
            error,
            DapError::BadStatus {
                command: DAP_SWJ_CLOCK,
                status: 0xFF,
            }
        );

        // DAP_INFO's byte 1 is a length, so 0xFF there is not an error.
        let mut fine = CmsisDap::new(MockTransport::new(vec![packet(&[DAP_INFO, 0xFF])]));
        assert!(block_on(fine.send(DAP_INFO, &[0x01])).is_ok());
    }

    #[test]
    fn resynchronises_past_a_stale_answer_and_the_one_it_displaced() {
        // One leftover reply, then the real one. Reading the leftover pulled
        // the queue forward by one, so one more read is owed.
        let mut dap = CmsisDap::new(MockTransport::new(vec![
            packet(&[DAP_CONNECT, 0x01]),
            packet(&[DAP_INFO, 0x03]),
            packet(&[DAP_INFO, 0x03]),
        ]));

        block_on(dap.drain_stale_responses()).expect("drains");

        let transport = dap.into_transport();
        assert!(transport.responses.is_empty(), "every stale reply consumed");
        assert_eq!(transport.written.len(), 2, "one probe per attempt");
    }
}
