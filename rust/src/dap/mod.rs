//! Framing and validating CMSIS-DAP commands over a
//! [`crate::transport::DapTransport`].
//!
//! Ported from `cmsis-dap.ts` in microbit-foundation/microbit-connection (MIT),
//! derived from dapjs (Copyright Arm Limited 2018, Microsoft Corporation, MIT).
//!
//! Protocol reference:
//! <https://www.keil.com/pack/doc/CMSIS/DAP/html/group__DAP__Commands__gr.html>

pub mod adi;
pub mod cmsis;
pub mod cortex_m;

use std::fmt;

use crate::transport::TransportError;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DapError {
    Transport(TransportError),

    /// The response did not begin with the command it was answering.
    ///
    /// Usually a reply left over from an interrupted session rather than a
    /// protocol fault. [`cmsis::CmsisDap::drain_stale_responses`] clears those.
    ResponseMismatch {
        expected: u8,
        actual: u8,
    },

    /// A command that answers OK or ERROR answered ERROR.
    BadStatus {
        command: u8,
        status: u8,
    },

    /// A register access failed, or fewer completed than were sent.
    ///
    /// `completed` says where in the batch it stopped, which separates "the
    /// target is gone" from "the twelfth write was refused".
    Transfer {
        response: u8,
        completed: usize,
        total: usize,
    },

    /// The device answered with fewer bytes than the command's reply needs.
    Truncated {
        command: u8,
        length: usize,
    },

    /// Something that is asked for until it happens never happened.
    ///
    /// `stage` names what was being waited for, because every one of these
    /// looks the same on the wire: the last read succeeded and said no.
    Timeout {
        stage: &'static str,
    },
}

impl fmt::Display for DapError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            DapError::Transport(inner) => write!(f, "{inner}"),
            DapError::ResponseMismatch { expected, actual } => {
                write!(f, "bad response for command {expected:#04x}: got {actual:#04x}")
            }
            DapError::BadStatus { command, status } => {
                write!(f, "bad status for command {command:#04x}: {status:#04x}")
            }
            DapError::Transfer {
                response,
                completed,
                total,
            } => {
                let reason = crate::dap::cmsis::transfer_response_message(*response);
                write!(f, "{reason}, at operation {completed} of {total}")
            }
            DapError::Truncated { command, length } => {
                write!(f, "response to command {command:#04x} was only {length} bytes")
            }
            DapError::Timeout { stage } => write!(f, "gave up waiting for {stage}"),
        }
    }
}

impl From<TransportError> for DapError {
    fn from(error: TransportError) -> DapError {
        DapError::Transport(error)
    }
}
