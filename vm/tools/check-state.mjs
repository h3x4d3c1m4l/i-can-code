// Restores the image bundle through web/vm/vm_host.js, as a page does, and checks the machine it
// holds: READY {warm: true} soon after each restore, a read-only root, a Tk window from the warm
// interpreter, every variant of the Tk() handover, STOP, and what each run has to read over 9p.
// Every run starts from a fresh restore, because the warm interpreter serves one program.
// Writes vm/build/check-state.json and exits 1 if any check failed.
//
// Usage: node check-state.mjs [--image DIR] [--only NAME]...
//
// It sends RUN, which icc-agent only implements far enough for these checks (supervisor.rs).

import fs from 'node:fs';
import path from 'node:path';
import { parseArgs } from 'node:util';

import { loadBundle, openHost, restoreAndGreet } from './lib/bundle.mjs';
import { imageDir } from './lib/dirs.mjs';
import { buildDir, sleep } from './lib/image-boot.mjs';

const { values: opts } = parseArgs({
  options: {
    image: { type: 'string' },
    only: { type: 'string', multiple: true },
  },
});

setTimeout(() => {
  console.error('check-state: gave up after 20 minutes');
  process.exit(2);
}, 20 * 60_000).unref();

const imageRoot = imageDir;
const dir = opts.image ?? path.join(imageRoot, JSON.parse(fs.readFileSync(path.join(imageRoot, 'manifest.json'), 'utf8')).imageId);
const bundle = await loadBundle(dir);
const { manifest } = bundle;

const checks = [];
const numbers = {};
const check = (name, passed, detail) => {
  checks.push({ check: name, passed, detail });
  console.log(`${passed ? 'PASS' : 'FAIL'}  ${name}: ${detail}`);
};
const info = (name, value) => {
  numbers[name] = value;
  console.log(`info  ${name}: ${typeof value === 'string' ? value : JSON.stringify(value)}`);
};
const wanted = name => !opts.only || opts.only.includes(name);

const fetched = [];
const { host, line, loadMs } = await openHost(bundle, {
  onEvent(event) {
    if (event.type === 'rootfs-fetched') fetched.push(event.path);
    if (event.type === 'fetch-failed') console.error('fetch-failed', event);
  },
});
const emu = host.emulator;
info('image', { imageId: manifest.imageId, stateBytes: manifest.state.bytes, interpreter: manifest.interpreter });
info('hostLoadMs', Math.round(loadMs));

// Every guest read of a file that reaches the 9p server. With the page cache holding what a run
// needs there are none; a page that has not fetched the file before fetches it over the network.
const reads = [];
const fs9p = emu.fs9p;
const read = fs9p.Read.bind(fs9p);
fs9p.Read = (inode, offset, count) => {
  reads.push(inode);
  return read(inode, offset, count);
};

/** A directory listing is answered from v86's inode table; only a file's data can need a fetch. */
function isFile(inode) {
  return (fs9p.inodes[inode]?.mode & 0xF000) === 0x8000;
}

/** Guest paths by inode. v86 keeps no parent link on a file inode, so its own GetFullPath
 *  cannot name one; this walks the tree instead, once per restore. */
let paths = null;
function pathOf(inode) {
  if (!paths?.has(inode)) {
    paths = new Map();
    const pending = [[0, '']];
    while (pending.length > 0) {
      const [dir, prefix] = pending.pop();
      for (const [name, index] of fs9p.inodes[dir].direntries) {
        if (name === '.' || name === '..') continue;
        paths.set(index, `${prefix}/${name}`);
        if ((fs9p.inodes[index].mode & 0xF000) === 0x4000) pending.push([index, `${prefix}/${name}`]);
      }
    }
  }
  return paths.get(inode) ?? `inode ${inode}`;
}

const RESTORES = 5;
const readyTimes = [];
for (let i = 0; i < RESTORES; i++) {
  const greeted = await restoreAndGreet(bundle, host, line);
  readyTimes.push({ readyMs: Math.round(greeted.readyMs), restoreMs: Math.round(greeted.restoreMs), warm: greeted.ready.warm });
}
info('restore to READY', readyTimes);
const slowest = Math.max(...readyTimes.map(r => r.readyMs));
check('READY {warm: true} within 300 ms of every restore', readyTimes.every(r => r.warm) && slowest <= 300,
  `${RESTORES} restores, READY after ${readyTimes.map(r => r.readyMs).join(', ')} ms; warm on ${readyTimes.filter(r => r.warm).length}`);

/**
 * Runs `source` as main.py on a freshly restored machine and resolves once it has exited.
 * `during(run)` runs alongside it, and may STOP it.
 */
async function run(source, { argv = [], timeoutMs = 60_000, during } = {}) {
  await restoreAndGreet(bundle, host, line);
  fetched.length = 0;
  reads.length = 0;
  const id = line.reserveId();
  await emu.create_file(`/icc/in/r${id}-main.py`, new TextEncoder().encode(source));
  const sent = performance.now();
  line.send('RUN', { entry: 'main.py', files: ['main.py'], argv, stdin: false, output_cap: 262_144 }, { id });
  const context = { id, sent, stop: () => line.send('STOP', {}, { id }) };
  const extra = during?.(context);
  const end = await line.waitFor(m => m.id === id && (m.type === 'EXIT' || m.type === 'ERROR'), timeoutMs, `EXIT of run ${id}`)
    .catch(error => ({ type: 'TIMEOUT', body: { message: error.message }, at: performance.now() }));
  if (end.type === 'TIMEOUT') line.send('STOP', {}, { id });
  const messages = line.received.filter(m => m.id === id && m.at >= sent);
  const text = type => Buffer.concat(messages.filter(m => m.type === type).map(m => Buffer.from(m.data))).toString();
  const startedAt = messages.find(m => m.type === 'STARTED')?.at;
  return {
    sent,
    started: messages.find(m => m.type === 'STARTED')?.body ?? null,
    exit: end.type === 'EXIT' ? end.body : null,
    error: end.type === 'ERROR' || end.type === 'TIMEOUT' ? end.body : null,
    stdout: text('STDOUT'),
    stderr: text('STDERR'),
    hints: messages.filter(m => m.type === 'HINT').map(m => m.body.kind),
    startedMs: startedAt ? Math.round(startedAt - sent) : null,
    exitMs: Math.round(end.at - sent),
    reads: [...new Set(reads.filter(isFile).map(pathOf))].filter(p => !p.startsWith('/icc/in/')),
    fetched: [...fetched],
    extra: await extra,
  };
}

const json = result => {
  try {
    return JSON.parse(result.stdout.trim().split('\n').at(-1));
  } catch {
    return null;
  }
};
const summary = result => `exit ${JSON.stringify(result.exit ?? result.error)}; stdout ${JSON.stringify(result.stdout.slice(0, 600))}` +
  (result.stderr ? `; stderr ${JSON.stringify(result.stderr.slice(0, 600))}` : '') +
  (result.hints.length ? `; hints ${result.hints.join(',')}` : '');
const runReads = {};

// What v86 would draw: the pixel at (x, y) of the guest's framebuffer.
const vga = emu.v86.cpu.devices.vga;
const pixel = (x, y) => {
  const at = (vga.svga_offset + y * vga.svga_width + x) * 4;
  return '#' + [2, 1, 0].map(i => vga.svga_memory[at + i].toString(16).padStart(2, '0')).join('');
};

if (wanted('read-only')) {
  const result = await run(`
import json, os
root = [line.split() for line in open("/proc/mounts") if line.split()[1] == "/"]
print(json.dumps(dict(root=root, readonly=bool(os.statvfs("/").f_flag & os.ST_RDONLY),
                      tmp=bool(os.statvfs("/tmp").f_flag & os.ST_RDONLY), uid=os.getuid())))
`);
  const out = json(result);
  runReads['read-only'] = result.reads;
  check('/ is mounted read-only', out?.readonly === true && out.root.every(m => m[3].split(',').includes('ro')) && out.tmp === false,
    `${JSON.stringify(out?.root)}; statvfs ST_RDONLY on / ${out?.readonly}, on /tmp ${out?.tmp}; the program ran as uid ${out?.uid}`);
}

if (wanted('window')) {
  const SWATCH = '#3366cc';
  const result = await run(`
import tkinter as tk
root = tk.Tk()
root.title("check-state")
tk.Frame(root, width=160, height=80, bg="${SWATCH}").pack()
tk.Label(root, text="Hello", font=("Helvetica", 16, "bold")).pack()
tk.Button(root, text="Click").pack()
root.mainloop()
`, {
    async during({ sent, stop }) {
      // With no window manager the window sits at +0+0, so the swatch covers (80, 40).
      const before = pixel(80, 40);
      let seen = null;
      while (performance.now() - sent < 30_000) {
        if (pixel(80, 40) === SWATCH) {
          seen = performance.now() - sent;
          break;
        }
        await sleep(5);
      }
      const stopped = performance.now();
      stop();
      return { before, windowMs: seen === null ? null : Math.round(seen), stopSentAt: stopped };
    },
  });
  runReads.window = result.reads;
  const { windowMs, before } = result.extra;
  check('a Tk window from the warm interpreter reaches the framebuffer', windowMs !== null,
    `pixel (80, 40) was ${before} before the run and ${SWATCH} ${windowMs} ms after RUN; STARTED after ${result.startedMs} ms`);
  info('RUN to window ms', windowMs);
  check('STOP ends the run', result.exit?.reason === 'stopped' && result.exit.signal === 9,
    `${summary(result)}; EXIT ${Math.round(result.sent + result.exitMs - result.extra.stopSentAt)} ms after STOP`);
  info('fetched by the window run', result.fetched);
}

// The handover (prelude.py): each case holds the program's view to what a cold python3 gives,
// as measured in an i386 container with Xvfb.
const H = `
import json, sys, time, tkinter as tk
from tkinter import messagebox
def info(w):
    t = w.tk
    return dict(title=w.title(), cls=w.winfo_class(), appname=t.call("tk", "appname"), state=w.state(),
                mapped=w.winfo_ismapped(), viewable=w.winfo_viewable(), geometry=w.winfo_geometry(),
                default=tk._default_root is w, stack=list(t.splitlist(t.call("wm", "stackorder", "."))))
`;
const CASES = [
  {
    name: 'handover: Tk()',
    source: H + `
t0 = time.perf_counter()
root = tk.Tk()
t1 = time.perf_counter()
before = info(root)
tk.Label(root, text="hello").pack()
root.update()
print(json.dumps(dict(tk_ms=round((t1 - t0) * 1000), before=before, after=info(root))))
`,
    // A cold root is unmapped and 1x1 until the first update maps it.
    expect: (o, r) => o.before.mapped === 0 && o.before.geometry === '1x1+0+0' && o.before.title === 'tk' &&
      o.before.cls === 'Tk' && o.before.default && o.after.viewable === 1 && o.after.stack.join() === '.' &&
      r.hints.join() === 'tk_no_mainloop',
  },
  {
    name: 'handover: class App(tk.Tk)',
    source: H + `
class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("App")
        tk.Label(self, text="x").pack()
app = App()
app.update()
print(json.dumps(dict(isinstance=isinstance(app, tk.Tk), type=type(app).__name__, info=info(app))))
`,
    expect: o => o.isinstance && o.type === 'App' && o.info.title === 'App' && o.info.viewable === 1 && o.info.default,
  },
  {
    name: 'handover: Tk(className=...)',
    source: H + `
root = tk.Tk(className="myGame")
root.option_add("Mygame.Label.background", "yellow")
l = tk.Label(root, text="x"); l.pack()
root.update()
print(json.dumps(dict(info=info(root), bg=str(l.cget("background")))))
`,
    expect: o => o.info.title === 'myGame' && o.info.cls === 'Mygame' && o.info.appname === 'myGame' && o.bg === 'yellow',
  },
  {
    name: 'handover: a second Tk()',
    source: H + `
a = tk.Tk()
t0 = time.perf_counter()
b = tk.Tk()
t1 = time.perf_counter()
a.update(); b.update()
print(json.dumps(dict(second_ms=round((t1 - t0) * 1000), same=a.tk is b.tk, a=info(a), b=info(b))))
`,
    expect: o => !o.same && o.a.title === 'tk' && o.b.title === 'tk #2' && o.a.viewable === 1 && o.b.viewable === 1 && o.a.default && !o.b.default,
  },
  {
    name: 'handover: withdraw() then a messagebox',
    source: H + `
root = tk.Tk()
root.withdraw()
def check():
    kids = root.tk.splitlist(root.tk.call("winfo", "children", "."))
    print(json.dumps(dict(root=info(root), kids={str(k): int(root.tk.call("winfo", "ismapped", k)) for k in kids})), flush=True)
    root.setvar("::tk::Priv(button)", "ok")
root.after(1500, check)
messagebox.showinfo("t", "m")
`,
    expect: o => o.root.mapped === 0 && o.root.state === 'withdrawn' && o.root.geometry === '1x1+0+0' &&
      o.kids['.__tk__messagebox'] === 1 && o.root.stack.join() === '.__tk__messagebox',
  },
  {
    name: 'handover: a messagebox with no root',
    source: H + `
import tkinter.commondialog as cd
temp = cd._get_temp_root
def patched():
    r = temp()
    def check():
        kids = r.tk.splitlist(r.tk.call("winfo", "children", "."))
        print(json.dumps(dict(root=info(r), temporary=getattr(r, "_temporary", None), kids={str(k): int(r.tk.call("winfo", "ismapped", k)) for k in kids})), flush=True)
        r.setvar("::tk::Priv(button)", "ok")
    r.after(1500, check)
    return r
cd._get_temp_root = patched
messagebox.showinfo("t", "m")
`,
    expect: o => o.temporary && o.root.mapped === 0 && o.root.geometry === '1x1+0+0' && o.kids['.__tk__messagebox'] === 1,
  },
  {
    name: 'handover: Tcl() leaves the warm root for Tk()',
    source: H + `
t = tk.Tcl()
t0 = time.perf_counter()
r = tk.Tk()
print(json.dumps(dict(tk_ms=round((time.perf_counter() - t0) * 1000), separate=r.tk is not t.tk, info=info(r))))
`,
    // r is a root left open without a main loop, so its window never appears: the hint's case.
    expect: (o, r) => o.separate && o.info.title === 'tk' && o.info.mapped === 0 && r.hints.join() === 'tk_no_mainloop',
  },
  {
    name: 'handover: iconify() before the first update',
    source: H + `
t0 = time.perf_counter()
root = tk.Tk()
root.iconify()
t1 = time.perf_counter()
root.update()
print(json.dumps(dict(iconify_ms=round((t1 - t0) * 1000), info=info(root))))
`,
    // No window manager to iconify it, so it maps as a cold one does, and nothing waits for one.
    expect: o => o.iconify_ms < 500 && o.info.viewable === 1,
  },
  {
    name: 'mainloop() ended by destroy() sends no hint',
    source: H + `
root = tk.Tk()
root.after(300, root.destroy)
root.mainloop()
print("{}")
`,
    expect: (o, r) => r.hints.length === 0 && r.exit?.code === 0,
  },
  {
    name: 'tkinter.mainloop() ended by quit() sends no hint',
    source: H + `
root = tk.Tk()
root.after(300, root.quit)
tk.mainloop()
print("{}")
`,
    expect: (o, r) => r.hints.length === 0 && r.exit?.code === 0,
  },
  {
    name: 'a traceback starts at the program',
    source: `
def f():
    raise ValueError("boom")
print("{}")
f()
`,
    expect: (o, r) => r.exit?.code === 1 && r.stderr.startsWith('Traceback (most recent call last):\n  File "/run/icc/work/main.py", line 5, in <module>') &&
      r.stderr.trim().endsWith('ValueError: boom') && !r.stderr.includes('prelude'),
  },
  {
    name: 'a syntax error prints as python3 prints it',
    source: 'print("{}"\n',
    expect: (o, r) => r.exit?.code === 1 && r.stderr.startsWith('  File "/run/icc/work/main.py", line 1') && r.stderr.includes('SyntaxError'),
  },
  {
    name: 'argv, __file__, __name__ and the working directory',
    argv: ['een', 'twee'],
    source: `
import json, os, sys
print(json.dumps(dict(argv=sys.argv, file=__file__, name=__name__, cwd=os.getcwd(), path0=sys.path[0], tz=os.environ.get("TZ"))))
`,
    expect: o => JSON.stringify(o) === JSON.stringify({ argv: ['main.py', 'een', 'twee'], file: '/run/icc/work/main.py', name: '__main__',
      cwd: '/run/icc/work', path0: '/run/icc/work', tz: 'UTC' }),
  },
];

for (const test of CASES) {
  if (!wanted(test.name)) continue;
  const result = await run(test.source, { argv: test.argv ?? [] });
  runReads[test.name] = result.reads;
  const out = json(result);
  let passed = false;
  try {
    passed = Boolean(test.expect(out ?? {}, result));
  } catch {
    passed = false;
  }
  check(test.name, passed, `${summary(result)}; ${result.exitMs} ms RUN to EXIT`);
}

// Runs that should read nothing over 9p: each file they read is a fetch on a page that has not
// fetched it before, and the program waits for it.
const QUIET = [
  {
    name: 'fonts students name read nothing over 9p',
    source: `
import tkinter as tk
root = tk.Tk()
canvas = tk.Canvas(root, width=400, height=400)
canvas.pack()
y = 10
for family in ("Arial", "Helvetica", "Times", "Times New Roman", "Courier", "Courier New", "Verdana", "Comic Sans MS"):
    for style in ("normal", "bold", "italic", "bold italic"):
        canvas.create_text(10, y, anchor="nw", text=family + " " + style, font=(family, 12, style))
        y += 4
tk.Label(root, text="Label", font=("Times", 20)).pack()
root.update()
print("{}")
`,
  },
  {
    name: 'the usual widgets read nothing over 9p',
    source: `
import tkinter as tk
from tkinter import ttk, messagebox, simpledialog
import random, math, time, datetime
root = tk.Tk()
root.title("Spel")
root.geometry("400x300")
frame = tk.Frame(root, bg="lightgreen")
frame.pack(fill="both", expand=True)
tk.Label(frame, text="Score: 0", font=("Arial", 16, "bold"), fg="navy").grid(row=0, column=0)
entry = tk.Entry(frame)
entry.grid(row=1, column=0)
tk.Button(frame, text="Gooi", command=lambda: None).grid(row=2, column=0)
ttk.Combobox(frame, values=["a", "b"]).grid(row=3, column=0)
ttk.Progressbar(frame, value=random.randint(0, 100)).grid(row=4, column=0)
canvas = tk.Canvas(frame, width=120, height=80, bg="white")
canvas.create_oval(10, 10, 60, 60, fill="red")
canvas.create_text(90, 40, text=str(datetime.date.today()))
canvas.grid(row=5, column=0)
root.update()
print("{}")
`,
  },
];

for (const test of QUIET) {
  if (!wanted(test.name)) continue;
  const result = await run(test.source);
  runReads[test.name] = result.reads;
  check(test.name, result.exit?.code === 0 && result.reads.length === 0,
    `${result.reads.length} files read: ${result.reads.join(' ') || 'none'}; ${summary(result)}`);
}

if (wanted('stop')) {
  const result = await run('while True:\n    pass\n', {
    async during({ stop }) {
      await line.waitFor(m => m.type === 'STARTED', 10_000, 'STARTED').catch(() => null);
      await sleep(500);
      const at = performance.now();
      stop();
      return { stopAt: at };
    },
  });
  const exitAt = line.received.find(m => m.type === 'EXIT' && m.body.reason === 'stopped' && m.at >= result.extra.stopAt)?.at;
  const ms = exitAt ? Math.round(exitAt - result.extra.stopAt) : null;
  check('STOP ends a busy loop', result.exit?.reason === 'stopped', `${summary(result)}; EXIT ${ms} ms after STOP`);
  info('STOP to EXIT ms', ms);
}

info('files read over 9p per run (page-cache misses; /icc/in excluded)', Object.fromEntries(Object.entries(runReads).map(([k, v]) => [k, v.length])));
info('files read over 9p, by path', [...new Set(Object.values(runReads).flat())].sort());
info('host rootfs fetches over the whole check', host.stats);
info('memory', host.memoryUsage());

const passed = checks.every(c => c.passed);
fs.writeFileSync(path.join(buildDir, 'check-state.json'), JSON.stringify({ image: manifest.imageId, checks, numbers, runReads }, null, 1) + '\n');
console.log(`${checks.filter(c => c.passed).length} of ${checks.length} checks passed`);
await host.destroy();
process.exit(passed ? 0 : 1);
