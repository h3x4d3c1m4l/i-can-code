//! The ARM Debug Interface: SWD access to the Cortex-M in a micro:bit.
//!
//! Owns the SWD connection's lifecycle, the Debug Port and Access Port
//! registers, and the caching that keeps a memory read to one packet.
//!
//! Ported from `arm-debug.ts` in microbit-foundation/microbit-connection (MIT),
//! derived from dapjs (Copyright Arm Limited 2018, Microsoft Corporation, MIT).
//!
//! Protocol reference: <https://developer.arm.com/documentation/ihi0031/a/>

use crate::dap::cmsis::{CmsisDap, DapOperation, ABORT_ALL, AP, DP};
use crate::dap::DapError;
use crate::transport::DapTransport;

// Debug Port registers.
const DP_ABORT: u8 = 0x0;
const DP_DPIDR: u8 = 0x0;
const DP_CTRL_STAT: u8 = 0x4;
const DP_SELECT: u8 = 0x8;

// Access Port registers. Byte addresses, already shifted to sit where a transfer
// operation's A[3:2] bits go.
const AP_CSW: u8 = 0x00;
const AP_TAR: u8 = 0x04;
const AP_DRW: u8 = 0x0C;

// CSW: what kind of memory access the AP performs.
const CSW_SIZE32: u32 = 1 << 1;
const CSW_ADDRINC_SINGLE: u32 = 1 << 4;
const CSW_DBGSTATUS: u32 = 1 << 6;
const CSW_RESERVED: u32 = 1 << 24;
const CSW_HPROT1: u32 = 1 << 25;
const CSW_MASTERTYPE: u32 = 1 << 29;
const CSW_VALUE: u32 = CSW_ADDRINC_SINGLE | CSW_DBGSTATUS | CSW_RESERVED | CSW_HPROT1 | CSW_MASTERTYPE;

// Which AP, and which bank of its registers, DP_SELECT points at.
const APSEL: u32 = 0xFF00_0000;
const APBANKSEL: u32 = 0x0000_00F0;

// CTRL/STAT: asking for power, and being told it arrived.
const CSYSPWRUPREQ: u32 = 1 << 30;
const CDBGPWRUPREQ: u32 = 1 << 28;
const CSYSPWRUPACK: u32 = 1 << 31;
const CDBGPWRUPACK: u32 = 1 << 29;

/// TAR auto-increments within this window and wraps at its edge, so a block
/// read re-addresses there. The nRF52833 promises no more than this minimum.
const AUTOINC_PAGE_SIZE: u32 = 1 << 10;

/// 10 MHz. Comfortably inside what DAPLink and the nRF52833 both do.
const CLOCK_FREQUENCY: u32 = 10_000_000;

/// How many times the power-up acknowledgement is asked for before giving up.
///
/// No sleep between attempts: each is a USB round trip, so the transport paces
/// the loop and this layer needs no clock.
const POWER_UP_ATTEMPTS: usize = 200;

/// SWD access to the target behind a CMSIS-DAP debug unit.
pub struct ArmDebug<T: DapTransport> {
    dap: CmsisDap<T>,
    connected: bool,

    /// The last value written to `DP_SELECT`, and to the AP's `CSW`.
    ///
    /// A memory read writes both every time, and re-sending a value the target
    /// already holds costs a wire transaction. Dropped when a transfer fails,
    /// which may have applied some of its writes.
    selected_address: Option<u32>,
    csw_value: Option<u32>,
}

impl<T: DapTransport> ArmDebug<T> {
    pub fn new(dap: CmsisDap<T>) -> ArmDebug<T> {
        ArmDebug {
            dap,
            connected: false,
            selected_address: None,
            csw_value: None,
        }
    }

    pub fn dap(&mut self) -> &mut CmsisDap<T> {
        &mut self.dap
    }

    /// Brings up SWD, retrying past replies left over from an earlier session.
    ///
    /// Only a mismatch is retried, because that is what a stale reply looks
    /// like. Everything else fails on the spot.
    pub async fn connect(&mut self) -> Result<(), DapError> {
        const MAX_RETRIES: usize = 3;

        let mut last_error = None;

        for attempt in 0..MAX_RETRIES {
            if attempt > 0 {
                self.dap.drain_stale_responses().await?;
            }

            match self.connect_once().await {
                Ok(()) => return Ok(()),
                Err(error @ DapError::ResponseMismatch { .. }) => last_error = Some(error),
                Err(error) => return Err(error),
            }
        }

        Err(last_error.unwrap_or(DapError::Truncated { command: 0, length: 0 }))
    }

    async fn connect_once(&mut self) -> Result<(), DapError> {
        if self.connected {
            return Ok(());
        }

        self.dap.swj_clock(CLOCK_FREQUENCY).await?;

        if let Err(error) = self.dap.connect().await {
            // The transport stays open so the caller can drain and retry
            // without losing the claim.
            let _ = self.dap.clear_abort().await;
            return Err(error);
        }

        self.dap.configure_transfer(0, 100, 0).await?;

        // The JTAG-to-SWD switch sequence from the ADI spec: ones to reach a
        // known line state, the magic 0xE79E low byte first, ones again, then
        // zeroes to leave SWD idle.
        self.dap.swj_sequence(&[0xFF; 7]).await?;
        self.dap.swj_sequence(&[0x9E, 0xE7]).await?;
        self.dap.swj_sequence(&[0xFF; 7]).await?;
        self.dap.swj_sequence(&[0x00]).await?;

        self.connected = true;

        match self.power_up().await {
            Ok(()) => Ok(()),
            Err(error) => {
                self.reset_state();
                Err(error)
            }
        }
    }

    /// Reads the DP's id, clears sticky errors and powers the debug domains up.
    async fn power_up(&mut self) -> Result<(), DapError> {
        // The value is unused. What matters is that the DP answers at all.
        self.read_dp(DP_DPIDR).await?;

        self.transfer_sequence(&[
            &[DapOperation::write(DP, DP_ABORT, ABORT_ALL)],
            &[DapOperation::write(DP, DP_SELECT, u32::from(AP_CSW))],
            &[DapOperation::write(DP, DP_CTRL_STAT, CSYSPWRUPREQ | CDBGPWRUPREQ)],
        ])
        .await?;

        let mask = CDBGPWRUPACK | CSYSPWRUPACK;

        for _ in 0..POWER_UP_ATTEMPTS {
            if self.read_dp(DP_CTRL_STAT).await? & mask == mask {
                return Ok(());
            }
        }

        Err(DapError::Transfer {
            response: 0,
            completed: 0,
            total: 1,
        })
    }

    /// Forgets the connection and the caches without touching the transport.
    ///
    /// MUST follow anything that resets the target, such as a DAPLink flash or
    /// a core reset.
    pub fn reset_state(&mut self) {
        self.connected = false;
        self.selected_address = None;
        self.csw_value = None;
    }

    pub async fn disconnect(&mut self) -> Result<(), DapError> {
        if !self.connected {
            return Ok(());
        }

        if self.dap.disconnect().await.is_err() {
            let _ = self.dap.clear_abort().await;
        }

        self.reset_state();
        Ok(())
    }

    /// Reads one 32-bit word from the target's memory map.
    pub async fn read_mem32(&mut self, address: u32) -> Result<u32, DapError> {
        let operations = self.read_mem32_ops(address);
        let values = self.transfer(&operations).await?;

        values
            .first()
            .copied()
            .ok_or(DapError::Truncated { command: 0, length: 0 })
    }

    pub async fn write_mem32(&mut self, address: u32, value: u32) -> Result<(), DapError> {
        let operations = self.write_mem32_ops(address, value);
        self.transfer(&operations).await?;
        Ok(())
    }

    /// Reads `count` words from `address`.
    ///
    /// Two nested loops, both for hardware limits: TAR wraps at a 1KB boundary,
    /// and one `DAP_TransferBlock` carries only what fits in a packet.
    pub async fn read_block(&mut self, address: u32, count: usize) -> Result<Vec<u32>, DapError> {
        let mut values = Vec::with_capacity(count);
        let mut remaining = count;
        let mut at = address;

        while remaining > 0 {
            let to_page_edge = (AUTOINC_PAGE_SIZE - (at % AUTOINC_PAGE_SIZE)) as usize / 4;
            let chunk = remaining.min(to_page_edge);

            self.address_for_block(at).await?;

            let max_words = self.dap.block_size() / 4;
            let mut left = chunk;
            while left > 0 {
                let words = left.min(max_words);
                values.extend(self.dap.transfer_block_read(AP, AP_DRW, words).await?);
                left -= words;
            }

            at += (chunk * 4) as u32;
            remaining -= chunk;
        }

        Ok(values)
    }

    pub async fn write_block(&mut self, address: u32, values: &[u32]) -> Result<(), DapError> {
        let mut index = 0;
        let mut at = address;

        while index < values.len() {
            let to_page_edge = (AUTOINC_PAGE_SIZE - (at % AUTOINC_PAGE_SIZE)) as usize / 4;
            let chunk = (values.len() - index).min(to_page_edge);

            self.address_for_block(at).await?;

            let max_words = self.dap.block_size() / 4;
            let mut written = 0;
            while written < chunk {
                let words = (chunk - written).min(max_words);
                let from = index + written;
                self.dap
                    .transfer_block_write(AP, AP_DRW, &values[from..from + words])
                    .await?;
                written += words;
            }

            at += (chunk * 4) as u32;
            index += chunk;
        }

        Ok(())
    }

    /// Points the AP at `address` with auto-increment on, ready for a block.
    async fn address_for_block(&mut self, address: u32) -> Result<(), DapError> {
        let csw = self.write_ap_ops(AP_CSW, CSW_VALUE | CSW_SIZE32);
        let tar = self.write_ap_ops(AP_TAR, address);
        self.transfer_sequence(&[&csw, &tar]).await?;
        Ok(())
    }

    /// Runs each group as its own `DAP_Transfer`. A group is what has to reach
    /// the target together.
    pub async fn transfer_sequence(&mut self, groups: &[&[DapOperation]]) -> Result<Vec<u32>, DapError> {
        let mut values = Vec::new();

        for group in groups {
            values.extend(self.transfer(group).await?);
        }

        Ok(values)
    }

    /// A transfer with the redundant writes taken out.
    async fn transfer(&mut self, operations: &[DapOperation]) -> Result<Vec<u32>, DapError> {
        let filtered: Vec<DapOperation> = operations
            .iter()
            .copied()
            .filter(|operation| !self.is_cached(*operation))
            .collect();

        if filtered.is_empty() {
            return Ok(Vec::new());
        }

        match self.dap.transfer(&filtered).await {
            Ok(values) => {
                for operation in &filtered {
                    self.remember(*operation);
                }
                Ok(values)
            }
            Err(error) => {
                // Some of the batch may have landed, so what the target holds
                // is no longer known.
                self.selected_address = None;
                self.csw_value = None;
                Err(error)
            }
        }
    }

    fn is_cached(&self, operation: DapOperation) -> bool {
        if operation.is_read() {
            return false;
        }

        match (operation.port, operation.register) {
            (DP, DP_SELECT) => self.selected_address == Some(operation.value),
            (AP, AP_CSW) => self.csw_value == Some(operation.value),
            _ => false,
        }
    }

    fn remember(&mut self, operation: DapOperation) {
        if operation.is_read() {
            return;
        }

        match (operation.port, operation.register) {
            (DP, DP_SELECT) => self.selected_address = Some(operation.value),
            (AP, AP_CSW) => self.csw_value = Some(operation.value),
            _ => {}
        }
    }

    async fn read_dp(&mut self, register: u8) -> Result<u32, DapError> {
        let values = self.transfer(&[DapOperation::read(DP, register)]).await?;

        values
            .first()
            .copied()
            .ok_or(DapError::Truncated { command: 0, length: 0 })
    }

    /// Two accesses: point `DP_SELECT` at the right AP and bank, then read.
    fn read_ap_ops(&self, register: u8) -> Vec<DapOperation> {
        let address = u32::from(register) & (APSEL | APBANKSEL);

        vec![
            DapOperation::write(DP, DP_SELECT, address),
            DapOperation::read(AP, register),
        ]
    }

    fn write_ap_ops(&self, register: u8, value: u32) -> Vec<DapOperation> {
        let address = u32::from(register) & (APSEL | APBANKSEL);

        vec![
            DapOperation::write(DP, DP_SELECT, address),
            DapOperation::write(AP, register, value),
        ]
    }

    /// Set the access size and address, then read the data register.
    pub fn read_mem32_ops(&self, address: u32) -> Vec<DapOperation> {
        let mut operations = self.write_ap_ops(AP_CSW, CSW_VALUE | CSW_SIZE32);
        operations.extend(self.write_ap_ops(AP_TAR, address));
        operations.extend(self.read_ap_ops(AP_DRW));
        operations
    }

    pub fn write_mem32_ops(&self, address: u32, value: u32) -> Vec<DapOperation> {
        let mut operations = self.write_ap_ops(AP_CSW, CSW_VALUE | CSW_SIZE32);
        operations.extend(self.write_ap_ops(AP_TAR, address));
        operations.extend(self.write_ap_ops(AP_DRW, value));
        operations
    }

    pub fn into_dap(self) -> CmsisDap<T> {
        self.dap
    }
}
