// A root shell on the kernel console (ttyS0), which only a debug bundle has
// (`just build-vm-state --debug-shell`). The shipped image runs no shell at all;
// this is how a check reaches inside a guest the agent would not let it touch.

/** Waits for text on a byte stream, with timers that do not outlive the wait. */
class Transcript {

  text = '';
  #waiters = [];

  constructor(emulator, event, { limit = 4 * 1024 * 1024 } = {}) {
    emulator.add_listener(event, byte => {
      this.text += String.fromCharCode(byte);
      if (this.text.length > limit) this.text = this.text.slice(-limit / 2);
      for (const waiter of [...this.#waiters]) waiter.check();
    });
  }

  /** Resolves with the match of `pattern` in the text after `from`. */
  waitFor(pattern, { from = 0, timeoutMs = 60_000 } = {}) {
    return new Promise((resolve, reject) => {
      const waiter = {
        check: () => {
          const match = this.text.slice(from).match(pattern);
          if (!match) return;
          this.#waiters.splice(this.#waiters.indexOf(waiter), 1);
          clearTimeout(timer);
          resolve({ match, index: from + match.index });
        },
      };
      const timer = setTimeout(() => {
        this.#waiters.splice(this.#waiters.indexOf(waiter), 1);
        reject(new Error(`Timed out waiting for ${pattern}.`));
      }, timeoutMs);
      this.#waiters.push(waiter);
      waiter.check();
    });
  }

}

/** The debug bundle's root shell on ttyS0. Kernel messages land there too. */
export class ConsoleShell {

  #emulator;
  #transcript;
  #sequence = 1000;

  constructor(emulator) {
    this.#emulator = emulator;
    this.#transcript = new Transcript(emulator, 'serial0-output-byte');
  }

  /** Everything ttyS0 has printed, kernel messages included. */
  get transcript() {
    return this.#transcript.text;
  }

  send(text) {
    this.#emulator.serial0_send(text);
  }

  /**
   * Runs `command` and resolves with its output. Both markers are computed by
   * the shell, so the echo of the command line, which the shell's line editor
   * wraps at 80 columns, can never match either of them.
   *
   * @returns {Promise<{out: string, rc: number, ms: number, sentAt: number, doneAt: number}>}
   *     `sentAt` and `doneAt` are host wall-clock times (Date.now()).
   */
  async run(command, timeoutMs = 60_000) {
    const n = ++this.#sequence;
    const from = this.#transcript.text.length;
    const sentAt = Date.now();
    const started = performance.now();
    this.send(`echo "@@S$((${n}+0))@@"; ${command}; echo "@@E$((${n}+0))@@ rc=$?"\n`);
    const end = await this.#transcript.waitFor(new RegExp(`@@E${n}@@ rc=(\\d+)`), { from, timeoutMs });
    const doneAt = Date.now();
    const start = await this.#transcript.waitFor(new RegExp(`@@S${n}@@\\r?\\n`), { from });
    const out = this.#transcript.text.slice(start.index + start.match[0].length, end.index)
      .replace(/\r/g, '').trim();
    return { out, rc: Number(end.match[1]), ms: performance.now() - started, sentAt, doneAt };
  }

}
