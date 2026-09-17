//! The public flutter_rust_bridge surface.
//!
//! No function here may be `#[frb(sync)]`. A sync call runs on the Dart main
//! thread, where a `std::sync::Mutex` under `+atomics` becomes an
//! `Atomics.wait` that browsers refuse.
//!
//! No function here may hold a device between calls either. See
//! `docs/microbit-usb.md`.

use crate::frb_generated::StreamSink;

use crate::api::types::{
    MicrobitBoardInfo, MicrobitBoardVersion, MicrobitCommand, MicrobitDeviceInfo, MicrobitError, MicrobitEvent,
    MicrobitFailure, MicrobitIdSource,
};
use crate::board_id::{BoardSerialInfo, BoardVersion};
use crate::device::BoardReport;
use crate::session::{self, SessionCommand, SessionEvent};
use crate::transport::usb::list_microbits;
use crate::transport::TransportError;

/// Whether this environment has a USB transport at all.
///
/// On the web that is `navigator.usb`, which Firefox and Safari lack. Says
/// nothing about a board being plugged in or permitted; both of those are an
/// empty list.
pub async fn microbit_transport_available() -> bool {
    nusb::list_devices().await.is_ok()
}

/// Every micro:bit this origin already has permission for.
///
/// Empty until Dart has asked for permission in `Window` scope, which a worker
/// cannot do. Opens nothing, so a board another tab is holding still appears.
pub async fn microbit_list_devices() -> Vec<MicrobitDeviceInfo> {
    // Filtered in the transport, beside the constants the session opens by.
    // Repeating it here is how a list and a connect come to disagree.
    let Ok(devices) = list_microbits().await else {
        return Vec::new();
    };

    devices
        .iter()
        .map(|d| {
            let serial = d.serial_number();
            // An anonymized serial parses to nothing, so the board id is
            // optional here. The vendor command needs the device open.
            let info = serial.and_then(BoardSerialInfo::from_serial);

            MicrobitDeviceInfo {
                product: d.product_string().map(str::to_string),
                serial_number: serial.map(str::to_string),
                board_id: info.as_ref().map(|i| i.board_id.to_hex()),
                board_version: info.map(|i| match i.board_id.version() {
                    BoardVersion::V1 => MicrobitBoardVersion::V1,
                    BoardVersion::V2 => MicrobitBoardVersion::V2,
                }),
            }
        })
        .collect()
}

/// Runs one micro:bit session, returning when it is stopped or superseded.
///
/// The board lives on this function's stack for as long as the session lasts.
/// Everything else reaches it through [`microbit_send_command`].
pub async fn microbit_run_session(sink: StreamSink<MicrobitEvent>) {
    session::run(|event| sink.add(to_event(event)).is_ok()).await;
}

/// Queues a command for the running session.
///
/// Returns once it is queued, not once it is done. Answers arrive on the
/// session's stream.
pub async fn microbit_send_command(command: MicrobitCommand) {
    session::send(match command {
        MicrobitCommand::Connect => SessionCommand::Connect,
        MicrobitCommand::Disconnect => SessionCommand::Disconnect,
        MicrobitCommand::Restart => SessionCommand::Restart,
        MicrobitCommand::Write { data } => SessionCommand::Write(data),
        MicrobitCommand::Stop => SessionCommand::Stop,
    });
}

fn to_event(event: SessionEvent) -> MicrobitEvent {
    match event {
        SessionEvent::Connected(report) => MicrobitEvent::Connected {
            info: board_info(*report),
        },
        SessionEvent::Serial(data) => MicrobitEvent::Serial { data },
        SessionEvent::Disconnected => MicrobitEvent::Disconnected,
        SessionEvent::Failed(error) => {
            let mapped = to_error(error);
            MicrobitEvent::Failed {
                failure: mapped.failure,
                message: mapped.message,
            }
        }
    }
}

/// Restates a [`BoardReport`] in the bridge's own terms.
fn board_info(report: BoardReport) -> MicrobitBoardInfo {
    MicrobitBoardInfo {
        vendor: report.vendor,
        product: report.product,
        protocol_version: report.protocol_version,
        board_id: report.serial_info.as_ref().map(|i| i.board_id.to_hex()),
        board_version: report.serial_info.as_ref().map(|i| match i.board_id.version() {
            BoardVersion::V1 => MicrobitBoardVersion::V1,
            BoardVersion::V2 => MicrobitBoardVersion::V2,
        }),
        id_source: match (&report.serial_info, report.from_vendor_command) {
            (None, _) => MicrobitIdSource::Unknown,
            (Some(_), true) => MicrobitIdSource::VendorCommand,
            (Some(_), false) => MicrobitIdSource::UsbSerial,
        },
        unique_id: report.unique_id,
        page_size: report.layout.page_size,
        page_count: report.layout.page_count,
    }
}

fn to_error(error: TransportError) -> MicrobitError {
    MicrobitError {
        failure: match error {
            TransportError::NoDevice => MicrobitFailure::NoDevice,
            TransportError::Busy => MicrobitFailure::Busy,
            TransportError::NoBulkInterface => MicrobitFailure::UnsupportedBoard,
            TransportError::Io(_) => MicrobitFailure::Protocol,
        },
        message: error.to_string(),
    }
}
