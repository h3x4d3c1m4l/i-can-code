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

/// Debug Fault Status Register. Its bits are cleared by writing one.
const DFSR: u32 = 0xE000_ED30;
const DFSR_HALTED: u32 = 1 << 0;
const DFSR_BKPT: u32 = 1 << 1;
const DFSR_DWTTRAP: u32 = 1 << 2;

/// Application Interrupt and Reset Control Register.
const NVIC_AIRCR: u32 = 0xE000_ED0C;
const NVIC_AIRCR_VECTKEY: u32 = 0x5FA << 16;
const NVIC_AIRCR_SYSRESETREQ: u32 = 1 << 2;

/// How many times a state change is asked about before giving up. Each attempt
/// is a USB round trip, so the transport paces the loop and no timer is needed.
const STATE_ATTEMPTS: usize = 500;

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
        if !self.is_halted().await? {
            return Ok(());
        }

        // The fault status bits latch. Writing one back clears them, so the
        // next halt reports its own reason.
        self.debug
            .write_mem32(DFSR, DFSR_DWTTRAP | DFSR_BKPT | DFSR_HALTED)
            .await?;
        self.debug.write_mem32(DHCSR, DBGKEY | C_DEBUGEN).await?;

        self.wait_until(false).await
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

        Err(DapError::Transfer {
            response: 0,
            completed: 0,
            total: 1,
        })
    }

    async fn wait_until(&mut self, halted: bool) -> Result<(), DapError> {
        for _ in 0..STATE_ATTEMPTS {
            if self.is_halted().await? == halted {
                return Ok(());
            }
        }

        Err(DapError::Transfer {
            response: 0,
            completed: 0,
            total: 1,
        })
    }
}
