//! The types that cross the bridge.
//!
//! Apart from the functions so that adding a field is visibly a change to the
//! Dart surface.

/// A micro:bit this origin already has permission for.
///
/// Every field is optional: a browser may withhold the serial number, which
/// takes the board id with it, and the screen still has to name the device.
pub struct MicrobitDeviceInfo {
    /// What the device calls itself, such as "BBC micro:bit CMSIS-DAP".
    pub product: Option<String>,
    /// The full DAPLink serial, as reported over USB.
    pub serial_number: Option<String>,
    /// The board id as four hex characters, e.g. `9906`.
    pub board_id: Option<String>,
    pub board_version: Option<MicrobitBoardVersion>,
}

/// Which generation of micro:bit a board id names.
pub enum MicrobitBoardVersion {
    /// Supported for flashing, but not for everything V2 can do.
    V1,
    V2,
}

/// What the interface chip says about itself and the board behind it, read over
/// the wire rather than out of the USB descriptor.
pub struct MicrobitBoardInfo {
    /// `DAP_Info` vendor name, such as "Arm".
    pub vendor: Option<String>,
    /// `DAP_Info` product name, such as "DAPLink CMSIS-DAP".
    pub product: Option<String>,
    /// The CMSIS-DAP protocol version the firmware implements.
    pub protocol_version: Option<String>,
    /// The full 48-character DAPLink unique id.
    pub unique_id: Option<String>,
    /// Four hex characters, e.g. `9906`.
    pub board_id: Option<String>,
    pub board_version: Option<MicrobitBoardVersion>,
    pub id_source: MicrobitIdSource,
    /// Bytes in one flash page, read out of Nordic's FICR over SWD. 4096 on an
    /// nRF52833.
    pub page_size: u32,
    /// How many pages the target's flash has. 128 on an nRF52833.
    pub page_count: u32,
}

/// Where the board id came from.
///
/// Reported because only the vendor command survives a browser anonymizing the
/// USB serial number, so this says whether that is happening.
pub enum MicrobitIdSource {
    /// Read over CMSIS-DAP, from the interface chip itself.
    VendorCommand,
    /// Fallback: the USB descriptor's serial number.
    UsbSerial,
    /// Neither answered anything a board id could be read out of.
    Unknown,
}

/// Why talking to the board did not work.
pub struct MicrobitError {
    pub failure: MicrobitFailure,
    /// Untranslated, for whoever is debugging. The screen picks its own sentence
    /// from the failure.
    pub message: String,
}

pub enum MicrobitFailure {
    /// Nothing to talk to: unplugged, or permission never granted.
    NoDevice,
    /// Something else holds the debug interface: another tab, MakeCode, the
    /// online Python editor, a stray `pyocd`.
    Busy,
    /// A board that is not a V2. Most likely a micro:bit V1, whose debug
    /// interface speaks CMSIS-DAP v1 over HID and which cannot run the
    /// MicroPython this app flashes.
    UnsupportedBoard,
    /// The conversation itself went wrong.
    Protocol,
}

/// What the screen asks the session to do.
///
/// Queued rather than called, because the session owns the board.
pub enum MicrobitCommand {
    /// Open the first board this origin can see and report on it.
    ///
    /// `interrupt` breaks into MicroPython's prompt once it is up. A screen
    /// that wants the board's own program to run leaves it false.
    Connect { interrupt: bool },
    /// Let go of it. The session stays up and can connect again.
    Disconnect,
    /// Start the board over: a hard reset, so it boots and runs `main.py` again.
    Restart { interrupt: bool },
    /// Send bytes to the target's UART, verbatim. What the reader typed.
    Write { data: Vec<u8> },
    /// Put `main_py` on the board, built into a copy of `firmware`.
    ///
    /// The firmware travels with every flash rather than being held here: the
    /// session owns no memory between commands, and a megabyte of text once per
    /// flash is nothing beside the twenty seconds the flash itself takes.
    Flash { firmware: String, main_py: String },
    /// End the session with this id. Another session's is ignored, because a
    /// screen being disposed of shares its queue with the screen that replaced
    /// it.
    Stop { session: u64 },
}

/// What the session says back.
///
/// A failure arrives here, never as a stream error: a stream that ends on the
/// first problem cannot report the next one.
pub enum MicrobitEvent {
    Connected {
        info: MicrobitBoardInfo,
    },
    /// Bytes the target printed, in order.
    ///
    /// Not text: MicroPython can split one UTF-8 sequence across two reads, so
    /// Dart decodes the stream.
    Serial {
        data: Vec<u8>,
    },
    Disconnected,
    /// How many of the board's flash pages the new program would change, out of
    /// how many it has. Worked out before anything is written.
    FlashPlan {
        changed: u32,
        total: u32,
    },
    /// The board could not say which pages differ, so the flash writes all of
    /// them. Not a failure: the write still happens.
    FlashPlanUnknown {
        message: String,
    },
    /// How far a flash has got, between 0 and 1.
    FlashProgress {
        fraction: f32,
    },
    /// The board has been written and has restarted into the new program.
    Flashed,
    Failed {
        failure: MicrobitFailure,
        message: String,
    },
}
