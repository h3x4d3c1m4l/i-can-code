//! The X window watcher (README 6.7 and 6.10). The guest has no window manager, so the agent does
//! the three things of one the page needs: it reports the run's top-level windows for Flutter to
//! frame, gives them keyboard focus, and delivers a close button's request to them.
//!
//! It is not a window manager: it never redirects a map or a configure, so windows sit wherever the
//! program puts them and nothing reparents them.
//!
//! It runs on a thread of its own, which owns the X connection. Every question to the server waits
//! for as long as the server takes to answer, and a program can make that forever: a client that
//! grabs the server, or a drawing so large the server is busy for seconds. The event loop that
//! answers PING never waits on X; it hears from the watcher through [`Windows`].

use crate::proto::{MAX_WINDOWS, WindowEntry};
use crate::wake;
use std::collections::{HashMap, HashSet};
use std::io;
use std::os::fd::{AsRawFd, RawFd};
use std::thread;
use std::time::{Duration, Instant};
use x11rb::connection::Connection;
use x11rb::cookie::Cookie;
use x11rb::errors::{ConnectionError, ReplyError};
use x11rb::protocol::Event;
use x11rb::protocol::xproto::{
    Allow, AtomEnum, ButtonIndex, ChangeWindowAttributesAux, ClientMessageEvent, ConnectionExt as _, EventMask,
    GetGeometryReply, GetPropertyReply, GetWindowAttributesReply, GrabMode, InputFocus, ModMask, Place, Window,
};
use x11rb::rust_connection::RustConnection;

/// WINDOW frames for a run are at least this far apart. The first change after a quiet spell goes
/// out at once, because Flutter frames the window from it and the window's pixels are on screen
/// already; a burst after it becomes one frame at the end of this interval.
pub const COALESCE: Duration = Duration::from_millis(16);

/// Titles are cut to this many characters. 32 windows of 80 characters, four bytes each at most,
/// keep a WINDOW frame under the host's 16 KiB limit.
pub const MAX_TITLE_CHARS: usize = 80;

/// Property reads ask for this many 32-bit units: enough for a title of MAX_TITLE_CHARS.
const TITLE_UNITS: u32 = 128;

/// The watcher's thread does no deep recursion and keeps no large buffers on its stack.
const STACK_BYTES: usize = 256 * 1024;

pub type Error = ConnectionError;

/// What the watcher tells the event loop.
#[derive(Debug)]
pub enum Note {
    /// Run `run`'s windows changed, as README 6.7's list.
    Windows { run: u32, windows: Vec<WindowEntry> },
    /// A close button's window does not take WM_DELETE_WINDOW, so run `run` has to end.
    CloseRefused { run: u32 },
    /// The X connection broke and the watcher has stopped.
    Lost(String),
}

enum Command {
    Begin { run: u32, handed_over: Option<u32> },
    End,
    Close { run: u32, xid: u32 },
}

/// The event loop's end of the watcher's thread. Every call returns at once.
pub struct Windows {
    commands: wake::Sender<Command>,
    notes: wake::Receiver<Note>,
}

impl Windows {
    /// Starts watching on a thread of its own.
    pub fn spawn(watcher: Watcher) -> io::Result<Windows> {
        let (commands, command_receiver) = wake::channel()?;
        let (note_sender, notes) = wake::channel()?;
        thread::Builder::new()
            .name("x11".into())
            .stack_size(STACK_BYTES)
            .spawn(move || serve(watcher, &command_receiver, &note_sender))?;
        Ok(Windows { commands, notes })
    }

    /// Polls readable when [`Windows::notes`] may have something.
    pub fn fd(&self) -> RawFd {
        self.notes.fd()
    }

    /// Starts watching for run `run`. `handed_over` is the warm root's `.`; `None` for a cold
    /// interpreter, whose first mapped top-level is taken as its main window instead. It MUST be
    /// called before the program can map a window, or that window is not the run's.
    pub fn begin_run(&self, run: u32, handed_over: Option<u32>) {
        let _ = self.commands.send(Command::Begin { run, handed_over });
    }

    pub fn end_run(&self) {
        let _ = self.commands.send(Command::End);
    }

    /// What a close button on window `xid` does. A window that cannot be asked comes back as
    /// [`Note::CloseRefused`].
    pub fn close(&self, run: u32, xid: u32) {
        let _ = self.commands.send(Command::Close { run, xid });
    }

    /// What the watcher said since the last call. A watcher that has stopped leaves a
    /// [`Note::Lost`] last.
    pub fn notes(&self) -> Vec<Note> {
        self.notes
            .drain()
            .unwrap_or_else(|wake::Gone| vec![Note::Lost("the watcher's thread is gone".into())])
    }
}

fn serve(mut watcher: Watcher, commands: &wake::Receiver<Command>, notes: &wake::Sender<Note>) {
    if let Err(error) = watch(&mut watcher, commands, notes) {
        let _ = notes.send(Note::Lost(error.to_string()));
    }
}

/// The watcher's loop. poll(2) is only ever reached straight after [`Watcher::process`]: x11rb
/// reads events into its own queue while it waits for a reply, and an event left there would wait
/// for whatever next made the socket readable.
fn watch(watcher: &mut Watcher, commands: &wake::Receiver<Command>, notes: &wake::Sender<Note>) -> Result<(), Error> {
    loop {
        let Ok(received) = commands.drain() else {
            return Ok(());
        };
        for command in received {
            match command {
                Command::Begin { run, handed_over } => watcher.begin_run(run, handed_over),
                Command::End => watcher.end_run(),
                Command::Close { run, xid } => {
                    if watcher.close(run, xid)? == Close::Unsupported && notes.send(Note::CloseRefused { run }).is_err()
                    {
                        return Ok(());
                    }
                }
            }
        }
        let now = Instant::now();
        watcher.process(now)?;
        if let Some((run, windows)) = watcher.due(now)? {
            if notes.send(Note::Windows { run, windows }).is_err() {
                return Ok(());
            }
            continue;
        }
        let mut fds = [pollfd(watcher.fd()), pollfd(commands.fd())];
        poll(&mut fds, watcher.deadline(), Instant::now())?;
    }
}

fn pollfd(fd: RawFd) -> libc::pollfd {
    libc::pollfd {
        fd,
        events: libc::POLLIN,
        revents: 0,
    }
}

/// Waits until an fd is readable or `deadline` passes. An error on the X socket shows up as the
/// next read's error, so only poll(2)'s own failure is one here.
fn poll(fds: &mut [libc::pollfd], deadline: Option<Instant>, now: Instant) -> Result<(), Error> {
    let timeout = deadline.map_or(-1, |deadline| {
        // Rounded up, so the thread does not wake just short of the deadline.
        let ms = deadline.saturating_duration_since(now).as_micros().div_ceil(1000);
        libc::c_int::try_from(ms).unwrap_or(libc::c_int::MAX)
    });
    // SAFETY: the pointer and length describe `fds`, which outlives the call.
    if unsafe { libc::poll(fds.as_mut_ptr(), fds.len() as libc::nfds_t, timeout) } == -1 {
        let error = io::Error::last_os_error();
        if error.kind() != io::ErrorKind::Interrupted {
            return Err(ConnectionError::IoError(error));
        }
    }
    Ok(())
}

struct Atoms {
    wm_protocols: u32,
    wm_delete_window: u32,
    net_wm_name: u32,
    utf8_string: u32,
}

/// What became of a close button's request.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Close {
    /// The window takes WM_DELETE_WINDOW and has been sent it; the program decides.
    Asked,
    /// The window does not take WM_DELETE_WINDOW: the caller ends the run, as a window manager
    /// would kill the client.
    Unsupported,
    /// Not one of the run's windows, or gone already.
    Unknown,
}

/// The windows of the run in progress.
struct RunWindows {
    id: u32,
    /// The X window of `.`, the Tk root the warm interpreter handed over. The top-level the server
    /// lists is Tk's wrapper around it, which exists only once Tk first maps the root.
    handed_over: Option<Window>,
    /// The warm root's top-level, Tk's wrapper around `.`, which `.`'s ReparentNotify names.
    main: Option<Window>,
    /// The first top-level the run mapped: a cold interpreter's main window.
    first: Option<Window>,
    /// Top-levels mapped during the run that still exist.
    mapped: HashSet<Window>,
    /// The viewable ones, most recently mapped last: where focus goes when the focused one leaves.
    viewable: Vec<Window>,
    focus: Option<Window>,
}

pub struct Watcher {
    conn: RustConnection,
    state: State,
}

/// What the watcher knows, apart from the connection it learns it through: requests borrow the
/// connection until their replies are read, and events are handled while they are outstanding.
///
/// Nearly all of it comes from events. The server reports every change to the root window's
/// children as SubstructureNotify, with the geometry and the stacking order in them, so a list
/// needs a round trip only for what no event carries: a window's title and WM_TRANSIENT_FOR,
/// read once and again after a PropertyNotify. Asking for everything each time cost 5 requests a
/// window, and a round trip that grew to 150 ms with 13 windows while Tk was busy drawing them.
struct State {
    root: Window,
    atoms: Atoms,
    run: Option<RunWindows>,
    /// When the first change not yet reported happened.
    dirty: Option<Instant>,
    /// The run's last list that differed from the one before it, and when it was read.
    sent: Option<(Instant, Vec<WindowEntry>)>,
    /// The root window's children, bottom to top.
    stack: Vec<Window>,
    /// False when an event named a sibling [`State::stack`] does not hold, which a QueryTree
    /// then puts right.
    stack_known: bool,
    tops: HashMap<Window, Top>,
}

/// What is known of one child of the root window.
#[derive(Debug, Default)]
struct Top {
    /// x, y, width and height, as ConfigureNotify gives them. `None` for a window that existed
    /// before the watcher did and has not been configured since.
    geometry: Option<(i16, i16, u16, u16)>,
    override_redirect: bool,
    /// Its PropertyNotify is selected.
    watched: bool,
    /// The title and WM_TRANSIENT_FOR, until a PropertyNotify says one of them changed.
    names: Option<(String, Option<u32>)>,
}

/// What one list has to ask the server about a window.
struct Asked<'c> {
    window: Window,
    geometry: Option<(
        Cookie<'c, RustConnection, GetGeometryReply>,
        Cookie<'c, RustConnection, GetWindowAttributesReply>,
    )>,
    names: Option<[Cookie<'c, RustConnection, GetPropertyReply>; 3]>,
}

impl Watcher {
    /// Connects to the display and watches the root window's children.
    pub fn connect(display: &str) -> Result<Watcher, String> {
        let (conn, screen) = RustConnection::connect(Some(display)).map_err(|error| format!("{display}: {error}"))?;
        let root = conn.setup().roots[screen].root;
        let atom = |name: &[u8]| -> Result<u32, String> {
            let reply = conn
                .intern_atom(false, name)
                .map_err(|e| e.to_string())?
                .reply()
                .map_err(|e| e.to_string())?;
            Ok(reply.atom)
        };
        let atoms = Atoms {
            wm_protocols: atom(b"WM_PROTOCOLS")?,
            wm_delete_window: atom(b"WM_DELETE_WINDOW")?,
            net_wm_name: atom(b"_NET_WM_NAME")?,
            utf8_string: atom(b"UTF8_STRING")?,
        };
        // SubstructureNotify, not SubstructureRedirect: the agent watches the map, it does not
        // decide it. Any number of clients may select this one.
        let events = ChangeWindowAttributesAux::new().event_mask(EventMask::SUBSTRUCTURE_NOTIFY);
        conn.change_window_attributes(root, &events)
            .map_err(|e| e.to_string())?
            .check()
            .map_err(|e| format!("watching the root window: {e}"))?;
        // After the selection, so no change falls between the tree and the first event.
        let stack = conn
            .query_tree(root)
            .map_err(|e| e.to_string())?
            .reply()
            .map_err(|e| format!("the root window's children: {e}"))?
            .children;
        let tops = stack.iter().map(|&window| (window, Top::default())).collect();
        Ok(Watcher {
            conn,
            state: State {
                root,
                atoms,
                run: None,
                dirty: None,
                sent: None,
                stack,
                stack_known: true,
                tops,
            },
        })
    }

    fn fd(&self) -> RawFd {
        self.conn.stream().as_raw_fd()
    }

    fn begin_run(&mut self, id: u32, handed_over: Option<u32>) {
        self.state.run = Some(RunWindows {
            id,
            handed_over,
            main: None,
            first: None,
            mapped: HashSet::new(),
            viewable: Vec::new(),
            focus: None,
        });
        self.state.dirty = None;
        self.state.sent = None;
    }

    fn end_run(&mut self) {
        self.state.run = None;
        self.state.dirty = None;
        self.state.sent = None;
    }

    /// When the next WINDOW is due.
    fn deadline(&self) -> Option<Instant> {
        let since = self.state.dirty?;
        Some(match &self.state.sent {
            Some((at, _)) => since.max(*at + COALESCE),
            None => since,
        })
    }

    fn process(&mut self, now: Instant) -> Result<(), Error> {
        process(&self.conn, &mut self.state, now)
    }

    /// The run and its windows, bottom to top, when a change is due at `now` and the list differs
    /// from the last one. A change that leaves the list as it was, such as a window's first
    /// ReparentNotify ahead of its MapNotify, holds up nothing after it.
    fn due(&mut self, now: Instant) -> Result<Option<(u32, Vec<WindowEntry>)>, Error> {
        let id = match (self.deadline(), &self.state.run) {
            (Some(deadline), Some(run)) if now >= deadline => run.id,
            _ => return Ok(None),
        };
        self.state.dirty = None;
        let windows = self.windows(now)?;
        if self.state.sent.as_ref().is_some_and(|(_, last)| *last == windows) {
            return Ok(None);
        }
        self.state.sent = Some((now, windows.clone()));
        Ok(Some((id, windows)))
    }

    /// The run's windows, from what the events said and, for what they did not, the server.
    fn windows(&mut self, now: Instant) -> Result<Vec<WindowEntry>, Error> {
        // A window mapped while the first pass waited needs a second; more than that is a
        // program mapping windows faster than they can be read, and the next list has them.
        for _ in 0..2 {
            if !self.read_unknown(now)? {
                break;
            }
        }
        let state = &self.state;
        let Some(run) = &state.run else {
            return Ok(Vec::new());
        };
        let main = match run.handed_over {
            Some(_) => run.main,
            None => run.first,
        };
        let mut entries: Vec<WindowEntry> = state
            .stack
            .iter()
            .filter(|window| run.mapped.contains(window))
            .filter_map(|&window| {
                let top = state.tops.get(&window).filter(|top| !top.override_redirect)?;
                let (x, y, w, h) = top.geometry?;
                let (title, transient_for) = top.names.clone().unwrap_or_default();
                Some(WindowEntry {
                    xid: window,
                    title,
                    x: x.into(),
                    y: y.into(),
                    w,
                    h,
                    mapped: run.viewable.contains(&window),
                    root: main == Some(window),
                    transient_for,
                })
            })
            .collect();
        // The highest in the stacking order are the ones on screen.
        let excess = entries.len().saturating_sub(MAX_WINDOWS);
        entries.drain(..excess);
        Ok(entries)
    }

    /// Asks the server what the list needs and no event said, in one round trip, and handles the
    /// events read meanwhile. Returns whether it asked anything.
    fn read_unknown(&mut self, now: Instant) -> Result<bool, Error> {
        let conn = &self.conn;
        let state = &mut self.state;
        let Some(run) = &state.run else {
            return Ok(false);
        };
        let tree = if state.stack_known {
            None
        } else {
            Some(conn.query_tree(state.root)?)
        };
        let mut asked = Vec::new();
        for &window in state.stack.iter().filter(|window| run.mapped.contains(window)) {
            let top = state.tops.entry(window).or_default();
            if top.override_redirect {
                continue;
            }
            let geometry = match top.geometry {
                None => Some((conn.get_geometry(window)?, conn.get_window_attributes(window)?)),
                Some(_) => None,
            };
            let names = match top.names {
                None => Some([
                    conn.get_property(
                        false,
                        window,
                        state.atoms.net_wm_name,
                        state.atoms.utf8_string,
                        0,
                        TITLE_UNITS,
                    )?,
                    conn.get_property(false, window, AtomEnum::WM_NAME, AtomEnum::ANY, 0, TITLE_UNITS)?,
                    conn.get_property(false, window, AtomEnum::WM_TRANSIENT_FOR, AtomEnum::WINDOW, 0, 1)?,
                ]),
                Some(_) => None,
            };
            if geometry.is_some() || names.is_some() {
                asked.push(Asked {
                    window,
                    geometry,
                    names,
                });
            }
        }
        if tree.is_none() && asked.is_empty() {
            return Ok(false);
        }
        if let Some(tree) = tree {
            match tree.reply() {
                Ok(tree) => {
                    state.stack = tree.children;
                    state.stack_known = true;
                }
                Err(error) => fail(error)?,
            }
        }
        for request in asked {
            // A window destroyed since it was asked about answers with an error; its
            // DestroyNotify is on its way and takes it off the list.
            let top = state.tops.entry(request.window).or_default();
            if let Some((geometry, attributes)) = request.geometry {
                if let (Ok(geometry), Ok(attributes)) = (geometry.reply(), attributes.reply()) {
                    top.geometry = Some((geometry.x, geometry.y, geometry.width, geometry.height));
                    top.override_redirect = attributes.override_redirect;
                }
            }
            if let Some([net_name, name, transient]) = request.names {
                let net_name = net_name.reply().ok();
                let name = name.reply().ok();
                let transient = transient.reply().ok();
                let title = title(net_name.as_ref(), name.as_ref(), state.atoms.utf8_string);
                let transient_for = transient
                    .filter(|reply| reply.type_ == u32::from(AtomEnum::WINDOW))
                    .and_then(|reply| reply.value32().and_then(|mut values| values.next()));
                top.names = Some((title, transient_for));
            }
        }
        // x11rb read these while it waited: handled now, not at the next wakeup.
        process(conn, state, now)?;
        Ok(true)
    }

    /// What the close button on window `xid`'s frame does, for run `run`.
    fn close(&mut self, run: u32, xid: u32) -> Result<Close, Error> {
        let atoms = &self.state.atoms;
        if !self
            .state
            .run
            .as_ref()
            .is_some_and(|current| current.id == run && current.mapped.contains(&xid))
        {
            return Ok(Close::Unknown);
        }
        let protocols = match self
            .conn
            .get_property(false, xid, atoms.wm_protocols, AtomEnum::ATOM, 0, 64)?
            .reply()
        {
            Ok(reply) => reply,
            Err(error) => return fail(error).map(|()| Close::Unknown),
        };
        let listed = protocols
            .value32()
            .is_some_and(|mut values| values.any(|atom| atom == atoms.wm_delete_window));
        if !listed {
            return Ok(Close::Unsupported);
        }
        let message = ClientMessageEvent::new(
            32,
            xid,
            atoms.wm_protocols,
            [atoms.wm_delete_window, x11rb::CURRENT_TIME, 0, 0, 0],
        );
        // An empty event mask sends it to the client that created the window, which is what a
        // window manager's close button does.
        self.conn
            .send_event(false, xid, EventMask::NO_EVENT, message)?
            .ignore_error();
        self.conn.flush()?;
        Ok(Close::Asked)
    }
}

/// Handles every event the connection holds, whether it came in over the socket or was read
/// while waiting for a reply.
fn process(conn: &RustConnection, state: &mut State, now: Instant) -> Result<(), Error> {
    while let Some(event) = conn.poll_for_event()? {
        state.on_event(conn, event, now)?;
    }
    conn.flush()
}

impl State {
    fn on_event(&mut self, conn: &RustConnection, event: Event, now: Instant) -> Result<(), Error> {
        match event {
            Event::CreateNotify(e) if e.parent == self.root => {
                self.restack(e.window, Some(Stack::Top));
                self.tops.insert(
                    e.window,
                    Top {
                        geometry: Some((e.x, e.y, e.width, e.height)),
                        override_redirect: e.override_redirect,
                        ..Top::default()
                    },
                );
                self.watch_names(conn, e.window)?;
            }
            // Menus, combobox lists and tooltips: a window manager leaves them alone too.
            Event::MapNotify(e) if e.event == self.root && !e.override_redirect => {
                let Some(run) = &mut self.run else {
                    return Ok(());
                };
                run.first.get_or_insert(e.window);
                run.mapped.insert(e.window);
                run.viewable.retain(|&w| w != e.window);
                run.viewable.push(e.window);
                // Clicks into it are routed through the agent first, for click to focus.
                conn.grab_button(
                    false,
                    e.window,
                    EventMask::BUTTON_PRESS,
                    GrabMode::SYNC,
                    GrabMode::ASYNC,
                    x11rb::NONE,
                    x11rb::NONE,
                    ButtonIndex::ANY,
                    ModMask::ANY,
                )?
                .ignore_error();
                self.watch_names(conn, e.window)?;
                self.focus(conn, Some(e.window))?;
                self.mark(now);
            }
            Event::UnmapNotify(e) if e.event == self.root => self.left(conn, e.window, now)?,
            Event::DestroyNotify(e) if e.event == self.root => {
                self.restack(e.window, None);
                self.tops.remove(&e.window);
                if let Some(run) = &mut self.run {
                    run.mapped.remove(&e.window);
                }
                self.left(conn, e.window, now)?;
            }
            Event::ConfigureNotify(e) if e.event == self.root => {
                let top = self.tops.entry(e.window).or_default();
                top.geometry = Some((e.x, e.y, e.width, e.height));
                top.override_redirect = e.override_redirect;
                let place = if e.above_sibling == x11rb::NONE {
                    Stack::Bottom
                } else {
                    Stack::Above(e.above_sibling)
                };
                self.restack(e.window, Some(place));
                self.mark(now);
            }
            Event::ReparentNotify(e) if e.event == self.root => {
                if e.parent == self.root {
                    self.restack(e.window, Some(Stack::Top));
                    let top = self.tops.entry(e.window).or_default();
                    top.geometry = None;
                    top.override_redirect = e.override_redirect;
                } else {
                    self.restack(e.window, None);
                    self.tops.remove(&e.window);
                    if let Some(run) = self.run.as_mut().filter(|run| run.handed_over == Some(e.window)) {
                        run.main = Some(e.parent);
                    }
                }
                self.mark(now);
            }
            Event::CirculateNotify(e) if e.event == self.root => {
                let place = if e.place == Place::ON_TOP {
                    Stack::Top
                } else {
                    Stack::Bottom
                };
                self.restack(e.window, Some(place));
                self.mark(now);
            }
            Event::GravityNotify(e) if e.event == self.root => {
                if let Some((x, y, _, _)) = self.tops.get_mut(&e.window).and_then(|top| top.geometry.as_mut()) {
                    (*x, *y) = (e.x, e.y);
                }
                self.mark(now);
            }
            Event::PropertyNotify(e) => {
                let names = [
                    AtomEnum::WM_NAME.into(),
                    AtomEnum::WM_TRANSIENT_FOR.into(),
                    self.atoms.net_wm_name,
                ];
                if names.contains(&e.atom) {
                    if let Some(top) = self.tops.get_mut(&e.window) {
                        top.names = None;
                    }
                    self.mark(now);
                }
            }
            // The passive grab from MapNotify fired: the pointer is frozen until this replays the
            // press to wherever it was going, so Tk sees an ordinary click.
            Event::ButtonPress(e) => {
                if self.run.as_ref().is_some_and(|run| run.viewable.contains(&e.event)) {
                    self.focus(conn, Some(e.event))?;
                }
                conn.allow_events(Allow::REPLAY_POINTER, e.time)?.ignore_error();
            }
            _ => {}
        }
        Ok(())
    }

    /// Moves `window` in the stacking order, or takes it out of it with `None`.
    fn restack(&mut self, window: Window, place: Option<Stack>) {
        self.stack.retain(|&w| w != window);
        match place {
            None => {}
            Some(Stack::Top) => self.stack.push(window),
            Some(Stack::Bottom) => self.stack.insert(0, window),
            Some(Stack::Above(sibling)) => match self.stack.iter().position(|&w| w == sibling) {
                Some(at) => self.stack.insert(at + 1, window),
                None => {
                    self.stack.push(window);
                    self.stack_known = false;
                }
            },
        }
    }

    /// Selects the window's PropertyNotify, which is what says its title changed. Titles are read
    /// when the list is sent. A window gone already is no loss.
    fn watch_names(&mut self, conn: &RustConnection, window: Window) -> Result<(), Error> {
        let top = self.tops.entry(window).or_default();
        if !top.watched {
            top.watched = true;
            let events = ChangeWindowAttributesAux::new().event_mask(EventMask::PROPERTY_CHANGE);
            conn.change_window_attributes(window, &events)?.ignore_error();
        }
        Ok(())
    }

    /// A top-level was unmapped or destroyed.
    fn left(&mut self, conn: &RustConnection, window: Window, now: Instant) -> Result<(), Error> {
        let Some(run) = &mut self.run else {
            return Ok(());
        };
        run.viewable.retain(|&w| w != window);
        if run.focus == Some(window) {
            let next = run.viewable.last().copied();
            self.focus(conn, next)?;
        }
        self.mark(now);
        Ok(())
    }

    /// With no window manager nothing else sets the focus, and the server's default, the window
    /// under the pointer, sends typing nowhere when a dialog opens away from the pointer.
    fn focus(&mut self, conn: &RustConnection, window: Option<Window>) -> Result<(), Error> {
        let Some(run) = &mut self.run else {
            return Ok(());
        };
        run.focus = window;
        let target = window.unwrap_or(u32::from(InputFocus::POINTER_ROOT));
        conn.set_input_focus(InputFocus::POINTER_ROOT, target, x11rb::CURRENT_TIME)?
            .ignore_error();
        Ok(())
    }

    fn mark(&mut self, now: Instant) {
        if self.run.is_some() {
            self.dirty.get_or_insert(now);
        }
    }
}

/// Where an event puts a window among its siblings.
enum Stack {
    Top,
    Bottom,
    Above(Window),
}

/// A protocol error about one request is no reason to drop the connection; a broken one is.
fn fail(error: ReplyError) -> Result<(), Error> {
    match error {
        ReplyError::ConnectionError(error) => Err(error),
        ReplyError::X11Error(_) => Ok(()),
    }
}

/// `_NET_WM_NAME` in UTF-8 if it is set, else `WM_NAME`, cut to MAX_TITLE_CHARS characters with
/// control characters left out.
fn title(net_name: Option<&GetPropertyReply>, name: Option<&GetPropertyReply>, utf8_string: u32) -> String {
    let text = match (net_name, name) {
        (Some(reply), _) if reply.type_ == utf8_string && !reply.value.is_empty() => {
            String::from_utf8_lossy(&reply.value).into_owned()
        }
        (_, Some(reply)) if reply.type_ == u32::from(AtomEnum::STRING) => latin1(&reply.value),
        (_, Some(reply)) => String::from_utf8_lossy(&reply.value).into_owned(),
        _ => String::new(),
    };
    clean_title(&text)
}

/// The ICCCM's STRING is Latin-1.
fn latin1(bytes: &[u8]) -> String {
    bytes.iter().map(|&byte| char::from(byte)).collect()
}

fn clean_title(text: &str) -> String {
    text.chars().filter(|c| !c.is_control()).take(MAX_TITLE_CHARS).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn property(type_: u32, value: &[u8]) -> GetPropertyReply {
        GetPropertyReply {
            format: 8,
            sequence: 0,
            length: 0,
            type_,
            bytes_after: 0,
            value_len: value.len() as u32,
            value: value.to_vec(),
        }
    }

    const UTF8: u32 = 300;
    const STRING: u32 = 31;

    #[test]
    fn prefers_the_utf8_title() {
        let net = property(UTF8, "My game 🎲".as_bytes());
        let old = property(STRING, b"My game ?");
        assert_eq!(title(Some(&net), Some(&old), UTF8), "My game 🎲");
    }

    #[test]
    fn falls_back_to_wm_name_in_latin1() {
        let net = property(0, b"");
        let old = property(STRING, b"caf\xe9");
        assert_eq!(title(Some(&net), Some(&old), UTF8), "café");
        assert_eq!(title(None, None, UTF8), "");
    }

    #[test]
    fn cuts_long_titles_and_drops_control_characters() {
        let long = "x".repeat(200);
        let net = property(UTF8, long.as_bytes());
        assert_eq!(title(Some(&net), None, UTF8).chars().count(), MAX_TITLE_CHARS);
        let net = property(UTF8, b"een\ttwee\nnul\0");
        assert_eq!(title(Some(&net), None, UTF8), "eentweenul");
    }

    fn state(stack: &[Window]) -> State {
        State {
            root: 1,
            atoms: Atoms {
                wm_protocols: 0,
                wm_delete_window: 0,
                net_wm_name: 0,
                utf8_string: 0,
            },
            run: None,
            dirty: None,
            sent: None,
            stack: stack.to_vec(),
            stack_known: true,
            tops: HashMap::new(),
        }
    }

    #[test]
    fn keeps_the_stacking_order_the_events_describe() {
        let mut state = state(&[10, 20, 30]);
        state.restack(40, Some(Stack::Top));
        assert_eq!(state.stack, [10, 20, 30, 40]);
        state.restack(40, Some(Stack::Above(10)));
        assert_eq!(state.stack, [10, 40, 20, 30]);
        state.restack(30, Some(Stack::Bottom));
        assert_eq!(state.stack, [30, 10, 40, 20]);
        state.restack(10, None);
        assert_eq!(state.stack, [30, 40, 20]);
        assert!(state.stack_known);
    }

    #[test]
    fn a_sibling_it_does_not_know_makes_it_read_the_tree() {
        let mut state = state(&[10, 20]);
        state.restack(20, Some(Stack::Above(99)));
        assert_eq!(state.stack, [10, 20]);
        assert!(!state.stack_known);
    }

    #[test]
    fn the_longest_list_fits_one_frame() {
        let window = WindowEntry {
            xid: u32::MAX,
            title: "🎲".repeat(MAX_TITLE_CHARS),
            x: i32::MIN,
            y: i32::MIN,
            w: u16::MAX,
            h: u16::MAX,
            mapped: false,
            root: false,
            transient_for: Some(u32::MAX),
        };
        let message = crate::proto::Message::Window(crate::proto::Window {
            windows: vec![window; MAX_WINDOWS],
        });
        assert!(message.encode(1).is_ok());
    }
}
