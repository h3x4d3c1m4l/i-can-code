// Boots the image in vm/build/ in v86 under Node, for the build's own checks.
//
// The shipped image has no shell on any terminal. bootImage() can add one on ttyS0 by editing
// this emulator's in-memory copy of /etc/inittab before the guest starts, so what is checked
// is the image as it ships, plus one line that only exists in the checker's RAM.

import { V86 } from "v86";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { performance } from "node:perf_hooks";
import { machine } from "../../image/machine.mjs";
import { buildDir, repoDir } from "./dirs.mjs";

export { buildDir, repoDir };

const wasmPath = fileURLToPath(new URL("v86.wasm", import.meta.resolve("v86")));
const encoder = new TextEncoder();
const decoder = new TextDecoder();

export const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

/**
 * Starts the built image and resolves once the guest is running.
 *
 * Every setting defaults to vm/image/machine.mjs. With `debugShell` the resolved `shell` is a
 * root shell on ttyS0 that has answered once. `fetches` records every rootfs file v86 loads
 * from vm/build/rootfs-flat/, from the first one on.
 */
export async function bootImage({
    memoryMiB = machine.memoryMiB,
    vgaMiB = machine.vgaMiB,
    cmdline = machine.cmdline,
    debugShell = true,
    echo = false,
} = {}) {
    const files = {
        bzImage: path.join(buildDir, "bzImage"),
        fsJson: path.join(buildDir, "fs.json"),
        flat: path.join(buildDir, "rootfs-flat"),
        bios: path.join(buildDir, "bios/seabios.bin"),
        vgaBios: path.join(buildDir, "bios/vgabios.bin"),
    };
    for (const [name, file] of Object.entries(files)) {
        if (!fs.existsSync(file)) throw new Error(`${name} missing at ${file}; run \`just build-vm-image\``);
    }

    const t0 = performance.now();
    const emu = new V86({
        wasm_path: wasmPath,
        bios: { url: files.bios },
        vga_bios: { url: files.vgaBios },
        bzimage: { url: files.bzImage },
        cmdline,
        memory_size: memoryMiB * 1024 * 1024,
        vga_memory_size: vgaMiB * 1024 * 1024,
        uart1: machine.uart1,
        // v86's docs have these two swapped: basefs is fs2json's JSON, baseurl the blob store.
        filesystem: { basefs: files.fsJson, baseurl: files.flat + "/" },
        autostart: false,
        disable_keyboard: true,
        disable_mouse: true,
    });
    await new Promise(resolve => emu.add_listener("emulator-loaded", resolve));
    const loadedMs = performance.now() - t0;

    const fetches = new FetchLog(emu, files.fsJson);
    const shell = debugShell ? new Shell(emu, { echo }) : null;
    if (debugShell) {
        const inittab = decoder.decode(await emu.read_file("/etc/inittab"));
        await emu.create_file("/etc/inittab", encoder.encode(inittab + "ttyS0::respawn:-/bin/sh\n"));
    }
    await emu.run();
    if (shell) await shell.ready();
    return { emu, shell, fetches, t0, loadedMs, readyMs: performance.now() - t0 };
}

/** Records which rootfs files v86 loads, by path: since the last clear(), and since boot. */
export class FetchLog {

    constructor(emu, fsJson) {
        this.entries = [];
        this.everything = [];
        this.byBlob = new Map();
        const walk = (nodes, dir) => {
            for (const node of nodes) {
                const p = `${dir}/${node[0]}`;
                if ((node[3] & 0xF000) === 0x4000) walk(node[6], p);
                else if ((node[3] & 0xF000) === 0x8000) this.byBlob.set(node[6], p);
            }
        };
        walk(JSON.parse(fs.readFileSync(fsJson, "utf8")).fsroot, "");
        const storage = emu.fs9p.storage;
        const load = storage.load_from_server.bind(storage);
        storage.load_from_server = (blob, size) => {
            const entry = { path: this.byBlob.get(blob) ?? blob, size };
            this.entries.push(entry);
            this.everything.push(entry);
            return load(blob, size);
        };
    }

    clear() {
        this.entries = [];
    }

    get paths() {
        return this.entries.map(e => e.path);
    }

    get bytes() {
        return this.entries.reduce((sum, e) => sum + e.size, 0);
    }

}

/**
 * A root shell on ttyS0, with echo and prompts turned off so a command's output is exactly what
 * it printed. Each command ends with a marker the shell computes, which its own input can never
 * contain.
 */
export class Shell {

    constructor(emu, { echo = false } = {}) {
        this.emu = emu;
        this.buffer = "";
        this.waiters = [];
        this.seq = 1000;
        this.checkQueued = false;
        emu.add_listener("serial0-output-byte", byte => {
            const c = String.fromCharCode(byte);
            this.buffer += c;
            if (echo) process.stdout.write(c);
            // Matching once per burst rather than per byte keeps a boot log's worth of output
            // from costing a regex scan of the whole buffer for every character.
            if (!this.checkQueued) {
                this.checkQueued = true;
                setImmediate(() => {
                    this.checkQueued = false;
                    this.check();
                });
            }
        });
    }

    check() {
        for (const waiter of [...this.waiters]) {
            const match = this.buffer.match(waiter.pattern);
            if (match) {
                this.waiters.splice(this.waiters.indexOf(waiter), 1);
                clearTimeout(waiter.timer);
                waiter.resolve(match);
            }
        }
    }

    waitFor(pattern, timeoutMs = 600_000) {
        return new Promise((resolve, reject) => {
            const match = this.buffer.match(pattern);
            if (match) return resolve(match);
            const waiter = { pattern, resolve };
            waiter.timer = setTimeout(() => {
                this.waiters.splice(this.waiters.indexOf(waiter), 1);
                reject(new Error(`timed out after ${timeoutMs} ms waiting for ${pattern}`));
            }, timeoutMs);
            this.waiters.push(waiter);
        });
    }

    async ready() {
        // ash asks the terminal for its cursor position (ESC [6n) after the first prompt.
        await this.waitFor(/# (\x1b\[6n)?$/);
        await this.run("stty -echo -onlcr; PS1=; PS2=");
    }

    /** Runs `command`, resolving with its output, its exit status and the host's wall time. */
    async run(command, timeoutMs = 600_000) {
        const n = ++this.seq;
        this.buffer = "";
        const t0 = performance.now();
        this.emu.serial0_send(`${command}\necho "@@$((${n}+0))@@ rc=$?"\n`);
        const match = await this.waitFor(new RegExp(`@@${n}@@ rc=(\\d+)\\r?\\n`), timeoutMs);
        return {
            out: this.buffer.slice(0, match.index).replace(/\r\n/g, "\n").trimEnd(),
            rc: Number(match[1]),
            ms: performance.now() - t0,
        };
    }

    /** Like run(), but throws unless the command exits 0. */
    async ok(command, timeoutMs) {
        const result = await this.run(command, timeoutMs);
        if (result.rc !== 0) throw new Error(`\`${command}\` exited ${result.rc}:\n${result.out}`);
        return result;
    }

}
