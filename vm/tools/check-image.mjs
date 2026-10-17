// Boots the image in vm/build/ and checks what the build promises: Xorg at the machine's screen
// size with no blanking, a Tk program running as the student that takes a click, typed keys
// and the wheel, stdlib imports that fetch no source files, and no getty or syslog left running.
// Writes vm/build/check-image.json and exits 1 if any check failed. See docs/vm-build.md.
//
// Usage: node check-image.mjs [--vga-mib N] [--memory-mib N] [--cmdline "..."] [--echo]

import fs from "node:fs";
import path from "node:path";
import { parseArgs } from "node:util";
import { performance } from "node:perf_hooks";
import { bootImage, buildDir, sleep } from "./lib/image-boot.mjs";
import { machine } from "../image/machine.mjs";

const { values: opts } = parseArgs({
    options: {
        "vga-mib": { type: "string" },
        "memory-mib": { type: "string" },
        cmdline: { type: "string" },
        echo: { type: "boolean", default: false },
        out: { type: "string", default: path.join(buildDir, "check-image.json") },
    },
});

setTimeout(() => {
    console.error("check-image: gave up after 20 minutes");
    process.exit(2);
}, 20 * 60_000).unref();

const encoder = new TextEncoder();
const checks = [];
const numbers = {};
const check = (name, passed, detail) => {
    checks.push({ check: name, passed, detail });
    console.log(`${passed ? "PASS" : "FAIL"}  ${name}: ${detail}`);
};
const info = (name, value) => {
    numbers[name] = value;
    console.log(`info  ${name}: ${typeof value === "string" ? value : JSON.stringify(value)}`);
};

const settings = {
    vgaMiB: opts["vga-mib"] ? Number(opts["vga-mib"]) : machine.vgaMiB,
    memoryMiB: opts["memory-mib"] ? Number(opts["memory-mib"]) : machine.memoryMiB,
    cmdline: opts.cmdline ?? machine.cmdline,
};
info("settings", settings);

const { emu, shell: sh, fetches, loadedMs, readyMs } = await bootImage({ ...settings, echo: opts.echo });
info("emulatorLoadedMs", Math.round(loadedMs));
info("bootToShellMs", Math.round(readyMs));
const bootFetches = { files: fetches.entries.length, bytes: fetches.bytes };
info("bootFetches", bootFetches);

// The machine as booted.
info("cmdline", (await sh.ok("cat /proc/cmdline")).out);
// The Dockerfile's kernel stage builds in what the guest used to load, so there is nothing to load.
const kernel = (await sh.ok("uname -r; [ -e /proc/modules ] && echo /proc/modules; [ -e /lib/modules ] && echo /lib/modules; true")).out.split("\n");
info("kernel", kernel[0]);
check("no module loader and no /lib/modules", kernel.length === 1, kernel.length === 1 ? `Linux ${kernel[0]}` : `found ${kernel.slice(1).join(", ")}`);
info("inputDevices", (await sh.ok("cd /dev/input && for f in *; do [ -L $f ] && echo \"$f -> $(readlink $f)\" || echo $f; done; cd /")).out.split("\n"));
info("drm", (await sh.run("dmesg | grep -i -E 'bochs|fb0|drm|video' | cut -c16-")).out.split("\n"));
const fbSize = (await sh.run("cat /sys/class/graphics/fb0/virtual_size")).out.trim();
info("fb0VirtualSize", fbSize);

const processes = (await sh.ok("ps -o user,comm | awk 'NR > 1'")).out.split("\n").map(l => l.trim());
const unwanted = processes.filter(l => /getty|syslogd|klogd/.test(l));
check("no getty or syslog", unwanted.length === 0,
    unwanted.length ? `running: ${unwanted.join(", ")}` : `${processes.length} processes, none of getty, agetty, syslogd, klogd`);

const inittab = (await sh.ok("grep -v '^#' /etc/inittab | grep -v '^$'")).out.split("\n");
const gettyLines = inittab.filter(l => /getty/.test(l));
check("inittab has no getty", gettyLines.length === 0, gettyLines.join(" | ") || inittab.join(" | "));

const student = (await sh.run("id student; stat -c '%U %a %n' /home/student /icc/in")).out;
check("student and /icc/in", /uid=1000\(student\) gid=1000\(student\)/.test(student) && /root 700 \/icc\/in/.test(student),
    student.replace(/\n/g, " | "));

// Imports read unchecked-hash pycs and never the source beside them. The first Python of the
// boot runs here, so the fetch log sees every file the import reads.
for (const [label, code] of [
    ["import random", "import random"],
    ["import random, again", "import random"],
    ["import the usual modules", "import tkinter, tkinter.ttk, tkinter.messagebox, tkinter.font, json, datetime, math, time, collections, re, string, itertools"],
]) {
    fetches.clear();
    const r = await sh.run(`python3 -c '${code}'`);
    const sources = fetches.paths.filter(p => p.endsWith(".py"));
    check(`${label} fetches no .py`, r.rc === 0 && sources.length === 0,
        `rc=${r.rc}, ${Math.round(r.ms)} ms, ${fetches.entries.length} files fetched (${fetches.bytes} B)` +
        (sources.length ? `; sources: ${sources.join(" ")}` : ""));
    info(`fetched: ${label}`, fetches.paths);
}
const pycFlags = (await sh.run("python3 -c \"import importlib.util, random; print(int.from_bytes(open(importlib.util.cache_from_source(random.__file__), 'rb').read(8)[4:8], 'little'))\"")).out;
check("random's pyc is unchecked-hash", pycFlags.trim() === "1", `flags=${pycFlags.trim()} (1 = hash-based, unchecked)`);

const tz = await sh.run("python3 -c \"import zoneinfo, datetime; print(datetime.datetime(2026, 1, 1, tzinfo=zoneinfo.ZoneInfo('America/Sao_Paulo')).utcoffset(), len(zoneinfo.available_timezones()))\"");
check("complete tzdata", tz.rc === 0 && /^-1 day, 21:00:00 \d+$/.test(tz.out) && Number(tz.out.split(" ").pop()) > 400, tz.out);

// A binary run twice is read over 9p once: the page cache keeps it (rootflags ignoreqv).
const speed = [];
for (let i = 0; i < 3; i++) {
    fetches.clear();
    speed.push(Math.round((await sh.ok("python3 -c pass")).ms));
}
check("a second run is served from the page cache", fetches.entries.length === 0,
    `third python3 -c pass fetched ${fetches.entries.length} files ${fetches.paths.join(" ")}`);
info("python3 -c pass, host ms", speed);
info("20000 getpid(), guest s", (await sh.ok("python3 -c 'import os, time; t = time.perf_counter(); [os.getpid() for _ in range(20000)]; print(round(time.perf_counter() - t, 3))'")).out);

// Xorg, started the way the agent will start it.
let t = performance.now();
const xorg = await sh.run("Xorg :0 -nolisten tcp -s 0 -dpms vt7 -logfile /tmp/xorg.log >/dev/null 2>&1 & " +
    "(i=0; until xwininfo -display :0 -root >/dev/null 2>&1; do i=$((i + 1)); [ $i -gt 600 ] && exit 1; sleep 0.1; done)", 120_000);
check("Xorg starts", xorg.rc === 0, `${Math.round(performance.now() - t)} ms until xwininfo answered`);
const root = (await sh.run("xwininfo -display :0 -root | grep -E 'Width|Height|Depth'")).out.replace(/\s+/g, " ").trim();
const { width, height } = machine.screen;
check(`X screen is ${width}x${height}`, root.includes(`Width: ${width}`) && root.includes(`Height: ${height}`), root);
const xlog = (await sh.run("grep -E '\\(EE\\)|\\(WW\\)|Adding extended input device|Using input driver|Option \"(BlankTime|DPMS|DontVTSwitch)\"' /tmp/xorg.log | cut -c14-")).out.split("\n");
info("xorgLog", xlog);
const added = xlog.filter(l => /Adding extended input device/.test(l));
check("Xorg opened the three input devices", ["keyboard", "pointer", "wheel"].every(n => added.some(l => l.includes(`"${n}"`))),
    added.join(" | ") || "none");
// In TrueColor, DRM's fbdev emulation takes a colormap only for the console's 16 entries, so
// fbdev's 256-entry loads fail with EINVAL. A TrueColor visual never reads the colormap.
const cmap = xlog.filter(l => /\(EE\) FBDEV\(0\): FBIOPUTCMAP: Invalid argument/.test(l));
const errors = xlog.filter(l => /\(EE\)/.test(l) && !/\(EE\) error, \(NI\)/.test(l) && !cmap.includes(l));
check("Xorg logged no errors besides FBIOPUTCMAP", errors.length === 0,
    (errors.join(" | ") || "no other (EE) lines") + `; FBIOPUTCMAP failed ${cmap.length} times`);

// Blanking and DPMS as the server reports them, through the same Xlib a program links.
const saver = await sh.run("DISPLAY=:0 python3 -c \"" +
    "import ctypes as c; x = c.CDLL('libX11.so.6'); e = c.CDLL('libXext.so.6'); x.XOpenDisplay.restype = c.c_void_p; d = x.XOpenDisplay(None); " +
    "v = [c.c_int() for _ in range(4)]; x.XGetScreenSaver(c.c_void_p(d), *[c.byref(i) for i in v]); " +
    "a, b = c.c_int(), c.c_int(); has = e.DPMSQueryExtension(c.c_void_p(d), c.byref(a), c.byref(b)); " +
    "lvl = c.c_ushort(); on = c.c_ubyte(); has and e.DPMSInfo(c.c_void_p(d), c.byref(lvl), c.byref(on)); " +
    "print('timeout', v[0].value, 'dpms-extension', has, 'dpms-on', on.value)\"");
check("no screen saver or DPMS", /^timeout 0 dpms-extension \d dpms-on 0$/.test(saver.out.trim()), saver.out.trim() || `rc=${saver.rc}`);

// A Tk program as the student: a Button, an Entry and a Listbox. It reports its state to a
// file the root shell reads, so nothing about the check depends on the program's stdout.
const APP = `
import json, os, tkinter as tk
root = tk.Tk()
root.title("check-image")
state = {"clicked": 0, "typed": None}
def hit():
    state["clicked"] += 1
button = tk.Button(root, text="Klik", command=hit)
button.pack(padx=40, pady=20)
entry = tk.Entry(root)
entry.pack(padx=20, pady=10)
def typed(event):
    state["typed"] = entry.get()
entry.bind("<Return>", typed)
listbox = tk.Listbox(root, height=5)
for i in range(100):
    listbox.insert("end", "regel %d" % i)
listbox.pack(pady=10)
swatch = tk.Frame(root, width=40, height=20, bg="#3366cc")
swatch.pack(pady=10)
def geometry(w):
    return [w.winfo_rootx(), w.winfo_rooty(), w.winfo_width(), w.winfo_height()]
def dump():
    state.update(button=geometry(button), entry=geometry(entry), listbox=geometry(listbox), swatch=geometry(swatch),
                 yview=listbox.yview()[0], focus=str(root.focus_get()),
                 screen=[root.winfo_screenwidth(), root.winfo_screenheight(), root.winfo_screendepth()])
    with open("/tmp/check/state.tmp", "w") as f:
        json.dump(state, f)
    os.replace("/tmp/check/state.tmp", "/tmp/check/state.json")
    root.after(100, dump)
# Before any update(): the window must still be unmapped, or the wait never ends.
root.wait_visibility(root)
root.update()
dump()
root.mainloop()
`;
await sh.ok("rm -rf /tmp/check; mkdir -m 0777 /tmp/check");
await emu.create_file("/tmp/check/app.py", encoder.encode(APP));
const readState = async () => {
    const r = await sh.run("cat /tmp/check/state.json 2>/dev/null");
    return r.rc === 0 && r.out ? JSON.parse(r.out) : null;
};
// Host sleeps say nothing about how far the guest got, least of all on a loaded machine, so
// every check polls for the state it expects and gives up only after a generous deadline.
// A null read is "the guest has not answered yet", not an answer: readState gives one before the
// program's first dump, and once for a `cat` over the serial line that came back empty. Judging
// it threw a TypeError out of the predicate instead of polling again, and the last real state is
// what makes a check that does time out say what the guest was showing.
const until = async (read, done, timeoutMs = 15_000) => {
    const start = performance.now();
    let value = await read();
    while (!(value !== null && done(value)) && performance.now() - start < timeoutMs) {
        await sleep(250);
        const next = await read();
        if (next !== null) value = next;
    }
    return value;
};
t = performance.now();
await sh.ok("su -s /bin/sh student -c 'DISPLAY=:0 exec python3 /tmp/check/app.py' >/tmp/check/app.log 2>&1 &");
let state = null;
while (!state && performance.now() - t < 120_000) {
    await sleep(250);
    state = await readState();
}
check("a Tk window opens for the student", !!state,
    state ? `${Math.round(performance.now() - t)} ms from a cold python3` : (await sh.run("cat /tmp/check/app.log")).out);
if (!state) await finish();

check(`Tk sees a ${width}x${height} screen`, state.screen[0] === width && state.screen[1] === height,
    `winfo_screen: ${state.screen.join(" x ")}`);

// What the browser will draw: v86's own idea of the mode, and the pixels X put in VGA memory.
const vga = emu.v86.cpu.devices.vga;
check(`v86 shows a ${width}x${height} 32-bit mode`, vga.svga_width === width && vga.svga_height === height && vga.svga_bpp === 32,
    `svga ${vga.svga_width}x${vga.svga_height}x${vga.svga_bpp}, offset ${vga.svga_offset}, ${vga.vga_memory_size / 2 ** 20} MiB`);
const pixel = (x, y) => {
    const at = (vga.svga_offset + y * vga.svga_width + x) * 4;
    return "#" + [2, 1, 0].map(i => vga.svga_memory[at + i].toString(16).padStart(2, "0")).join("");
};
const centre = ([x, y, w, h]) => [x + w / 2, y + h / 2];
const swatchPixel = await until(async () => pixel(...centre(state.swatch).map(Math.round)), p => p === "#3366cc");
check("a Tk colour reaches v86's framebuffer", swatchPixel === "#3366cc", `pixel under a #3366cc Frame: ${swatchPixel}`);
const pointAt = async ([x, y]) => {
    emu.bus.send("mouse-absolute", [x, y, state.screen[0], state.screen[1]]);
    await sleep(300);
};
const click = async () => {
    emu.bus.send("mouse-click", [true, false, false]);
    await sleep(150);
    emu.bus.send("mouse-click", [false, false, false]);
};

await pointAt(centre(state.button));
await click();
state = await until(readState, s => s.clicked > 0);
check("a synthetic click reaches a Tk Button", state.clicked === 1, `command ran ${state.clicked} time(s)`);

// Typing into an Entry the student clicked into. Where keys go when nothing was clicked is the
// agent's focus rule (the X watcher), which this image does not have yet.
await pointAt(centre(state.entry));
await click();
await sleep(500);
await emu.keyboard_send_scancodes([0x23, 0xA3, 0x17, 0x97, 0x1C, 0x9C], 40);
state = await until(readState, s => s.typed !== null);
check("scancodes reach a Tk Entry", state.typed === "hi", `Entry after h, i, Return: ${JSON.stringify(state.typed)}; focus ${state.focus}`);

await pointAt(centre(state.listbox));
const before = state.yview;
for (let i = 0; i < 3; i++) {
    // What the browser adapter sends for one notch downwards.
    emu.bus.send("mouse-wheel", [-1, 0]);
    await sleep(200);
}
state = await until(readState, s => s.yview > before);
check("the wheel scrolls a Tk Listbox", state.yview > before, `yview ${before} -> ${state.yview}`);

info("free -m with X and the program", (await sh.run("free -m | awk 'NR == 2'")).out.replace(/\s+/g, " "));
const sources = fetches.everything.filter(e => e.path.endsWith(".py"));
check("no .py fetched all session", sources.length === 0,
    `${fetches.everything.length} fetches since boot, ${sources.length} of them .py ${sources.map(e => e.path).join(" ")}`);
const warnings = (await sh.run("dmesg | grep -i -E 'soft lockup|rcu.*stall|hung task|oops|bug:' | grep -v -E 'command line|stall warnings suppressed' | head -5")).out;
check("no lockup, stall or oops in dmesg", warnings === "", warnings || "none");

await finish();

async function finish() {
    const stats = path.join(buildDir, "rootfs-stats.json");
    if (fs.existsSync(stats)) info("rootfs", JSON.parse(fs.readFileSync(stats, "utf8")));
    fs.writeFileSync(opts.out, JSON.stringify({ checks, numbers }, null, 1));
    const failed = checks.filter(c => !c.passed);
    console.log(`\n${checks.length - failed.length} of ${checks.length} checks passed; written to ${opts.out}`);
    await emu.destroy();
    process.exit(failed.length ? 1 : 0);
}
