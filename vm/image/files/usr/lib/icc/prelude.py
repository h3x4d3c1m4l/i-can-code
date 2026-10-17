"""The warm interpreter: the student's own python3, started by icc-agent at PREPARE.

It imports what student programs import and draws every kind of widget once, so
fontconfig and Xft have their fonts loaded before any program arrives. Then it
creates the Tk root the program will get, waits for one program, and runs it as
``__main__`` with its first Tk() handed that root. It is used once: every run starts
from a restored snapshot.

A run may carry ``icc_setup.py`` beside its program: the page's own code, which this
file runs first and removes (run_setup).

The agent owns everything else. This file speaks only to it, over two pipes:

- fd 3, read: one JSON line, ``{"dir", "entry", "argv", "tz"}``, the program to run.
- fd 4, write: ``warm <python> <tk> <xid>`` once the warm-up is done, ``xid`` being
  the X window of the root ``.`` the program will get; ``hint <kind>`` before the
  program exits; and ``done`` once it is done but for the interpreter's teardown.

The program runs in this process, so it can write to fd 4 as well. The agent takes
each line at most once per run and only the hint kinds the protocol has; a process
the program forks or starts does not get the pipe at all.
"""

import os

GO_FD = 3
STATUS_FD = 4

#: The page's code for every run, beside the program. Coupled to ``vmSetupFile`` in
#: lib/services/vm/vm_runtime.dart.
SETUP = "icc_setup.py"

# A program the program starts must not inherit the agent's pipes. Forked children are
# handled in run(): close-on-exec does nothing for a fork.
os.set_inheritable(GO_FD, False)
os.set_inheritable(STATUS_FD, False)

import atexit
import gc
import json
import linecache
import random
import sys
import threading
import time
import types

import _tkinter
# set_class() needs it, and importing it only then would read seven files over 9p in that run.
import ctypes
# From Python 3.13 on the interpreter prints an uncaught exception, a SyntaxError included,
# through traceback, so a run's first error read eight modules over 9p: about 2 s.
import traceback
# A misspelled keyword ("whille") is a SyntaxError that asks difflib for the word that was meant.
# traceback does not import it, and it is three more files for the typo students make most.
import difflib

# Imported for the program: each of these costs a run several files over 9p otherwise.
import collections
import datetime
import itertools
import math
import re
import string
import tkinter
import tkinter.colorchooser
import tkinter.filedialog
import tkinter.font
import tkinter.messagebox
import tkinter.scrolledtext
import tkinter.simpledialog
import tkinter.ttk as ttk
import turtle

# A 4 x 4 PNG, so the warm-up decodes a PhotoImage through Tk's PNG reader.
_PNG = "iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAEElEQVR42mP4z8AARwzEcQCukw/xOF6MEQAAAABJRU5ErkJggg=="


def warm_up():
    """Draws each widget type once in a root of its own, then destroys it."""
    root = tkinter.Tk()
    root.withdraw()
    top = tkinter.Toplevel(root)
    fonts = [
        tkinter.font.Font(root, family=family, size=size, weight=weight, slant=slant)
        for family, size, weight, slant in [
            ("Helvetica", 16, "bold", "roman"),
            ("Arial", 12, "normal", "italic"),
            ("Times", 14, "bold", "italic"),
            ("Courier", 12, "normal", "roman"),
            ("Courier", 12, "bold", "roman"),
        ]
    ]
    image = tkinter.PhotoImage(master=root, data=_PNG)
    tkinter.Label(top, text="Label", fg="red", bg="light blue", font=fonts[0]).pack()
    tkinter.Label(top, image=image).pack()
    tkinter.Button(top, text="Button", font=fonts[1]).pack()
    entry = tkinter.Entry(top, font=fonts[3])
    entry.insert(0, "Entry")
    entry.pack()
    tkinter.Text(top, height=2, font=fonts[4]).pack()
    tkinter.scrolledtext.ScrolledText(top, height=2).pack()
    canvas = tkinter.Canvas(top, width=120, height=60, bg="white")
    canvas.create_text(30, 10, text="text")
    canvas.create_text(30, 30, text="bold", font=fonts[0], fill="dark green")
    canvas.create_text(30, 50, text="italic", font=fonts[2])
    canvas.create_line(0, 0, 120, 60, width=3, fill="orange")
    canvas.create_rectangle(60, 5, 80, 25, fill="yellow", outline="black")
    canvas.create_oval(85, 5, 115, 25, fill="purple")
    canvas.create_polygon(60, 55, 70, 35, 80, 55, fill="gray50")
    canvas.create_arc(85, 30, 115, 58, start=0, extent=270, fill="pink")
    canvas.create_image(100, 50, image=image)
    canvas.pack()
    listbox = tkinter.Listbox(top, height=2)
    listbox.insert("end", "Listbox")
    listbox.pack()
    tkinter.Checkbutton(top, text="Checkbutton").pack()
    tkinter.Radiobutton(top, text="Radiobutton", value=1).pack()
    tkinter.Scale(top, orient="horizontal").pack()
    tkinter.Spinbox(top, from_=0, to=9).pack()
    tkinter.Message(top, text="Message").pack()
    frame = tkinter.LabelFrame(top, text="LabelFrame")
    tkinter.OptionMenu(frame, tkinter.StringVar(root, "a"), "a", "b").pack()
    frame.pack()
    menu = tkinter.Menu(top, tearoff=False)
    menu.add_command(label="Menu")
    top.configure(menu=menu)
    tkinter.Scrollbar(top, orient="horizontal").pack(fill="x")
    ttk.Label(top, text="ttk.Label").pack()
    ttk.Button(top, text="ttk.Button").pack()
    ttk.Entry(top).pack()
    ttk.Combobox(top, values=["ttk.Combobox"]).pack()
    ttk.Checkbutton(top, text="ttk.Checkbutton").pack()
    ttk.Radiobutton(top, text="ttk.Radiobutton").pack()
    ttk.Scale(top).pack()
    ttk.Spinbox(top, from_=0, to=9).pack()
    ttk.Progressbar(top, value=40).pack()
    ttk.Separator(top).pack(fill="x")
    notebook = ttk.Notebook(top)
    notebook.add(ttk.Frame(notebook), text="ttk.Notebook")
    notebook.pack()
    tree = ttk.Treeview(top, columns=("a",), height=1)
    tree.insert("", "end", text="ttk.Treeview", values=("a",))
    tree.pack()
    root.update()
    # Focus is what creates an X input context, and a key press what reads the keymap.
    entry.focus_force()
    entry.event_generate("<KeyPress-a>")
    root.update()
    # A dialog shown and answered, so its script, its fonts and msgcat are loaded.
    root.after(100, lambda: root.setvar("::tk::Priv(button)", "ok"))
    tkinter.messagebox.showinfo("warm-up", "warm-up", parent=top)
    root.destroy()
    # Tk keeps the display connection, and with it Xft's fonts, after the last root is gone.
    # What the destroy left queued is handled now, not by the program's first update().
    while root.tk.dooneevent(_tkinter.ALL_EVENTS | _tkinter.DONT_WAIT):
        pass


def fresh_root():
    """Returns the root the program gets: a new one, in the state a cold Tk() leaves it in.

    Its window is mapped at the first idle, unless the program withdraws or iconifies it
    before then, exactly as a cold root's is. Nothing may process Tcl events between this
    and the handover, or that first idle would come too early.
    """
    root = tkinter.Tk()
    # Creates the X window of ``.`` without mapping it, which is the first thing Tk does
    # when it maps the root, so the agent learns its id now. The top-level window the
    # agent sees is Tk's wrapper, and that only exists once the root is first mapped.
    xid = root.winfo_id()
    # Both belong to an interpreter, so the warm-up's went with its root. Sourcing the
    # message box's script took 434 ms of a first messagebox's 1150 ms in v86, and
    # neither processes an event.
    root.tk.eval("auto_load ::tk::MessageBox")
    for font in ("TkDefaultFont", "TkCaptionFont", "TkHeadingFont", "TkTextFont", "TkFixedFont", "TkMenuFont"):
        root.tk.call("font", "measure", font, "Hg")
    return root, xid


def handover(root):
    """Makes the program's first Tk() take ``root``'s interpreter instead of creating one.

    Wraps ``_tkinter.create`` rather than replacing ``tkinter.Tk``, so ``class App(tk.Tk)``
    and every other use of the class still works: Tk.__init__ runs as it always does, on
    an interpreter that has its fonts loaded already.
    """
    app = root.tk
    # The commands this Tk instance registered call back into it; Tk.__init__ registers
    # its own again on the same interpreter.
    for name in root._tclCommands or ():
        app.deletecommand(name)
    root._tclCommands = None
    if tkinter._default_root is root:
        tkinter._default_root = None
    create = _tkinter.create
    objects = bool(tkinter.wantobjects)
    warm = [app]

    def warm_create(screenName=None, baseName=None, className="Tk", interactive=False,
                    wantobjects=False, wantTk=True, sync=False, use=None):
        if (not warm or screenName is not None or not wantTk or sync or use is not None
                or interactive or bool(wantobjects) != objects):
            if warm and wantTk:
                # Its window would otherwise appear at the program's first idle.
                warm.pop().call("wm", "withdraw", ".")
            app = create(screenName, baseName, className, interactive, wantobjects, wantTk, sync, use)
        else:
            app = warm.pop()
            # What _tkinter and Tk make of className in a new interpreter: argv0 is className
            # with its first letter lowered, the application name its last path segment, and
            # the class that name in title case. Tk reads both when it first maps the window.
            argv0 = className[:1].lower() + className[1:] if "A" <= className[:1] <= "Z" else className
            name = argv0.rpartition("/")[2] or "tk"
            if name != "tk":
                app.call("tk", "appname", name)
                set_class(app, name[:1].upper() + name[1:].lower())
        if wantTk:
            roots.append(app)
        return app

    _tkinter.create = warm_create


def set_class(app, cls):
    """Renames the class of ``.``, which Tk only allows from C once the window exists.

    ``.cget("class")`` still answers ``Tk``: that is the option the window was created with.
    """
    libtk = ctypes.CDLL("libtk8.6.so")
    libtk.Tk_MainWindow.restype = ctypes.c_void_p
    libtk.Tk_MainWindow.argtypes = [ctypes.c_void_p]
    libtk.Tk_SetClass.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    libtk.Tk_SetClass(libtk.Tk_MainWindow(app.interpaddr()), cls.encode())


roots = []
looped = False


def watch_mainloop():
    """Records whether the program entered a main loop, for the tk_no_mainloop hint."""
    method = tkinter.Misc.mainloop
    function = tkinter.mainloop

    def mainloop(self, n=0):
        global looped
        looped = True
        return method(self, n)

    def module_mainloop(n=0):
        global looped
        looped = True
        return function(n)

    tkinter.Misc.mainloop = mainloop
    tkinter.mainloop = module_mainloop


def hint():
    """Tells the agent when the program ends with a window that exiting will close."""
    if not looped and any(left_open(app) for app in roots):
        report(b"hint tk_no_mainloop\n")


def report(line):
    """A status line to the agent. The program may have closed fd 4 itself."""
    try:
        os.write(STATUS_FD, line)
    except OSError:
        pass


def close_status():
    try:
        os.close(STATUS_FD)
    except OSError:
        pass


def left_open(app):
    """A root the program neither destroyed nor withdrew.

    Also one that was never drawn, because nothing ran the event loop: that window never
    appearing is the same mistake, and the likelier one.
    """
    try:
        return app.call("wm", "state", ".") in ("normal", "zoomed")
    except tkinter.TclError:
        return False


def read_go():
    line = b""
    while not line.endswith(b"\n"):
        chunk = os.read(GO_FD, 4096)
        if not chunk:
            sys.exit("icc prelude: the agent closed the go pipe")
        line += chunk
    os.close(GO_FD)
    return json.loads(line)


def run(go):
    """Runs the program as python3 would run it as a script, and exits the way it would."""
    path = os.path.join(go["dir"], go["entry"])
    os.environ["TZ"] = go["tz"]
    time.tzset()
    # Seeded when the snapshot was taken, so every run would otherwise roll the same dice.
    random.seed()
    os.chdir(go["dir"])
    sys.argv = [go["entry"], *go["argv"]]
    sys.path[0] = go["dir"]
    run_setup()
    main = types.ModuleType("__main__")
    main.__file__ = path
    main.__cached__ = None
    sys.modules["__main__"] = main
    os.register_at_fork(after_in_child=close_status)
    with open(path, "rb") as f:
        source = f.read()
    # sys.excepthook prints the traceback the exception carries, not the one it is handed,
    # so the frames of this file are cut off the exception itself.
    try:
        code = compile(source, path, "exec")
    except SyntaxError as error:
        sys.excepthook(type(error), error.with_traceback(None), None)
        code = None
    if code is None:
        status, hinted = 1, False
    else:
        try:
            exec(code, main.__dict__)
        except SystemExit as error:
            status, hinted = exit_code(error), True
        except BaseException as error:
            # No hint: the traceback already says why the window closed.
            trace = error.__traceback__.tb_next
            sys.excepthook(type(error), error.with_traceback(trace), trace)
            status, hinted = 1, False
        else:
            status, hinted = 0, True
    finish(status, hinted)


def run_setup():
    """Runs the page's setup, if the run carries one, before the program and out of its sight.

    The file goes first, so the program's directory holds only its own files. A setup that
    raises prints its traceback and the program still runs.
    """
    path = os.path.abspath(SETUP)
    try:
        with open(path, "rb") as f:
            source = f.read()
    except FileNotFoundError:
        return
    os.remove(path)
    # The file is gone, so a traceback would otherwise quote none of its lines.
    lines = source.decode("utf-8", "replace").splitlines(True)
    linecache.cache[path] = (len(source), None, lines, path)
    try:
        exec(compile(source, path, "exec"), {"__name__": "icc_setup"})
    except BaseException as error:
        trace = error.__traceback__.tb_next
        sys.excepthook(type(error), error.with_traceback(trace), trace)


def exit_code(error):
    """The status python3 exits with for an uncaught SystemExit, printing what it prints."""
    if error.code is None:
        return 0
    if isinstance(error.code, int):
        return error.code
    print(error.code, file=sys.stderr)
    return 1


def finish(status, hinted):
    """Does what python3 does after a script up to its own teardown, then exits with ``status``.

    It waits for the program's threads and runs its atexit handlers, in that order, as
    Py_FinalizeEx does; neither runs twice, so the teardown after this finds nothing left
    of either. ``done`` then lets the agent end every other process the program started,
    so the teardown does not share the CPU with them.
    """
    threading._shutdown()
    atexit._run_exitfuncs()
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.flush()
        except Exception:
            pass
    if hinted:
        hint()
    report(b"done\n")
    sys.exit(status)


warm_up()
root, root_xid = fresh_root()
python = sys.version.split()[0]
tk_patchlevel = root.tk.getvar("tk_patchLevel")
handover(root)
del root
watch_mainloop()
gc.collect()
os.write(STATUS_FD, f"warm {python} {tk_patchlevel} {root_xid}\n".encode())
run(read_go())
