//! Stopping and starting the Cortex-M4 in a micro:bit.
//!
//! The debug registers are memory-mapped, so [`crate::dap::adi::ArmDebug`] is
//! all it takes.
//!
//! Ported from `cortex-m.ts` in microbit-foundation/microbit-connection (MIT),
//! itself derived from dapjs (Copyright Arm Limited 2018, Microsoft
//! Corporation, MIT).

use crate::dap::adi::ArmDebug;
use crate::dap::DapError;
use crate::transport::DapTransport;

/// Debug Halting Control and Status Register.
const DHCSR: u32 = 0xE000_EDF0;
const C_DEBUGEN: u32 = 1 << 0;
const C_HALT: u32 = 1 << 1;
const S_HALT: u32 = 1 << 17;
const S_RESET_ST: u32 = 1 << 25;
/// Every write to DHCSR carries this key, or it is ignored.
const DBGKEY: u32 = 0xA05F << 16;

/// Debug Core Register Selector and Data Register: the pair that reads and
/// writes the processor's own registers while it is halted.
const DCRSR: u32 = 0xE000_EDF4;
const DCRDR: u32 = 0xE000_EDF8;
/// Set in DHCSR once a register transfer has finished.
const S_REGRDY: u32 = 1 << 16;
/// Set in DCRSR to make the transfer a write.
const REGWNR: u32 = 1 << 16;

/// The general-purpose registers, and the four the debug unit numbers after
/// them.
pub const REGISTER_SP: u8 = 13;
pub const REGISTER_LR: u8 = 14;
pub const REGISTER_PC: u8 = 15;
pub const REGISTER_PSR: u8 = 16;

/// Thumb state. Anything else and the processor faults on the first
/// instruction.
const PSR_THUMB: u32 = 0x0100_0000;

/// Debug Fault Status Register. Its bits are cleared by writing one.
const DFSR: u32 = 0xE000_ED30;
const DFSR_HALTED: u32 = 1 << 0;
const DFSR_BKPT: u32 = 1 << 1;
const DFSR_DWTTRAP: u32 = 1 << 2;

/// Debug Exception and Monitor Control Register, and the bit in it that makes
/// the processor halt at the reset vector instead of running from it.
const DEMCR: u32 = 0xE000_EDFC;
const DEMCR_VC_CORERESET: u32 = 1 << 0;

/// Application Interrupt and Reset Control Register.
const NVIC_AIRCR: u32 = 0xE000_ED0C;
const NVIC_AIRCR_VECTKEY: u32 = 0x5FA << 16;
const NVIC_AIRCR_SYSRESETREQ: u32 = 1 << 2;

/// How many times a state change is asked about before giving up. Each attempt
/// is a USB round trip, so the transport paces the loop and no timer is needed.
const STATE_ATTEMPTS: usize = 500;

/// A register transfer reports itself finished in DHCSR. Reading a value the
/// processor had not yet produced would otherwise pass silently.
fn expect_ready(results: &[u32]) -> Result<(), DapError> {
    match results.first() {
        Some(status) if status & S_REGRDY != 0 => Ok(()),
        _ => Err(DapError::Timeout {
            stage: "a core register transfer",
        }),
    }
}

/// The processor, as far as the debug unit is concerned.
pub struct CortexM<'a, T: DapTransport> {
    debug: &'a mut ArmDebug<T>,
}

impl<'a, T: DapTransport> CortexM<'a, T> {
    pub fn new(debug: &'a mut ArmDebug<T>) -> CortexM<'a, T> {
        CortexM { debug }
    }

    pub async fn is_halted(&mut self) -> Result<bool, DapError> {
        Ok(self.debug.read_mem32(DHCSR).await? & S_HALT != 0)
    }

    /// Stops the processor where it is, keeping its memory and registers.
    ///
    /// Used to stop the target touching RAM while something else writes to it.
    pub async fn halt(&mut self) -> Result<(), DapError> {
        if self.is_halted().await? {
            return Ok(());
        }

        self.debug.write_mem32(DHCSR, DBGKEY | C_DEBUGEN | C_HALT).await?;
        self.wait_until(true).await
    }

    /// Lets the processor carry on from where it was halted.
    pub async fn resume(&mut self) -> Result<(), DapError> {
        if !self.start().await? {
            return Ok(());
        }

        self.wait_until(false).await
    }

    /// Starts the processor without waiting for it to be running.
    ///
    /// Answers whether it was halted to begin with. What this is for is code
    /// that stops itself: a page write can be over before a caller could
    /// observe the running state, and waiting for a state that has already
    /// passed never ends.
    pub async fn start(&mut self) -> Result<bool, DapError> {
        if !self.is_halted().await? {
            return Ok(false);
        }

        // The fault status bits latch. Writing one back clears them, so the
        // next halt reports its own reason.
        self.debug
            .write_mem32(DFSR, DFSR_DWTTRAP | DFSR_BKPT | DFSR_HALTED)
            .await?;
        self.debug.write_mem32(DHCSR, DBGKEY | C_DEBUGEN).await?;

        Ok(true)
    }

    /// Waits until the processor has stopped itself, at a breakpoint or a fault.
    pub async fn wait_for_halt(&mut self) -> Result<(), DapError> {
        self.wait_until(true).await
    }

    /// Resets the whole system and lets it boot from its reset vector.
    ///
    /// The C startup runs again, restoring every initialised global, so this is
    /// what makes it safe to have written over RAM beforehand. A soft reboot
    /// does not do that.
    pub async fn reset(&mut self) -> Result<(), DapError> {
        self.debug
            .write_mem32(NVIC_AIRCR, NVIC_AIRCR_VECTKEY | NVIC_AIRCR_SYSRESETREQ)
            .await?;

        // The reset takes the debug port's answers with it for a moment, so a
        // failed read here is the reset happening rather than a fault.
        for _ in 0..STATE_ATTEMPTS {
            if let Ok(dhcsr) = self.debug.read_mem32(DHCSR).await {
                if dhcsr & S_RESET_ST == 0 {
                    return Ok(());
                }
            }
        }

        Err(DapError::Timeout {
            stage: "the reset to finish",
        })
    }

    /// Resets the processor and catches it at the reset vector.
    ///
    /// What comes back has run none of its own program: peripherals reset,
    /// interrupts off, RAM nobody is using. Anything that runs code on the
    /// target MUST start here. Halting a running program instead leaves its
    /// peripherals live, and the first interrupt to fire runs a handler whose
    /// stack and data the uploaded code has overwritten.
    pub async fn reset_and_halt(&mut self) -> Result<(), DapError> {
        self.halt().await?;

        let demcr = self.debug.read_mem32(DEMCR).await?;
        self.debug.write_mem32(DEMCR, demcr | DEMCR_VC_CORERESET).await?;

        self.reset().await?;
        self.wait_until(true).await?;

        // Vector catch belongs to this call and nothing else: left set, the
        // board would halt on its next reset rather than boot.
        self.debug.write_mem32(DEMCR, demcr).await
    }

    /// Reads one of the processor's registers. The caller MUST have halted it.
    pub async fn read_core_register(&mut self, register: u8) -> Result<u32, DapError> {
        let select = self.debug.write_mem32_ops(DCRSR, u32::from(register));
        let status = self.debug.read_mem32_ops(DHCSR);
        let value = self.debug.read_mem32_ops(DCRDR);

        let results = self.debug.transfer_sequence(&[&select, &status, &value]).await?;
        expect_ready(&results)?;

        results.get(1).copied().ok_or(DapError::Truncated {
            command: 0,
            length: results.len(),
        })
    }

    /// Writes one of the processor's registers. The caller MUST have halted it.
    pub async fn write_core_register(&mut self, register: u8, value: u32) -> Result<(), DapError> {
        let data = self.debug.write_mem32_ops(DCRDR, value);
        let select = self.debug.write_mem32_ops(DCRSR, u32::from(register) | REGWNR);
        let status = self.debug.read_mem32_ops(DHCSR);

        let results = self.debug.transfer_sequence(&[&data, &select, &status]).await?;
        expect_ready(&results)
    }

    /// Puts `code` in the target's RAM and runs it until it halts.
    ///
    /// `code` MUST end in a breakpoint, which is what stops it: there is no
    /// other way back. `registers` fills r0 upwards, and MUST NOT be longer than
    /// the twelve general-purpose registers.
    ///
    /// The processor's own memory and registers are overwritten, so whatever was
    /// running is gone.
    pub async fn execute(
        &mut self,
        address: u32,
        code: &[u32],
        stack: u32,
        pc: u32,
        lr: u32,
        registers: &[u32],
    ) -> Result<(), DapError> {
        debug_assert!(registers.len() <= 12, "only twelve general-purpose registers");

        self.halt().await?;
        self.debug.write_block(address, code).await?;

        self.write_core_register(REGISTER_PC, pc).await?;
        self.write_core_register(REGISTER_LR, lr).await?;
        self.write_core_register(REGISTER_SP, stack).await?;
        self.write_core_register(REGISTER_PSR, PSR_THUMB).await?;

        for (index, value) in registers.iter().enumerate() {
            self.write_core_register(index as u8, *value).await?;
        }

        self.resume().await?;
        self.wait_until(true).await
    }

    async fn wait_until(&mut self, halted: bool) -> Result<(), DapError> {
        for _ in 0..STATE_ATTEMPTS {
            if self.is_halted().await? == halted {
                return Ok(());
            }
        }

        Err(DapError::Timeout {
            stage: if halted {
                "the processor to halt"
            } else {
                "the processor to start"
            },
        })
    }
}
