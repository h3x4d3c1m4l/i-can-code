// The agent's control line (ttyS1) as the build tools speak it: frames through web/vm/vm_protocol.js,
// requests answered by id, and the credit window of README section 7. It talks to a raw V86, so it
// serves both a booting build machine and a VmHost's restored one.

import {
  CreditedSender,
  decodeMessage,
  encodeMessage,
  FrameDecoder,
  MAX_PAYLOAD_TO_HOST,
} from '../../../web/vm/vm_protocol.js';

export class AgentLine {

  /** Every message the agent sent, in order, with the host time it arrived. */
  received = [];

  #emulator;
  #decoder = new FrameDecoder({ maxPayload: MAX_PAYLOAD_TO_HOST });
  #sender;
  #pending = [];
  #flushQueued = false;
  #waiters = new Set();
  #nextId;

  /**
   * @param {object} emulator A V86 with uart1.
   * @param {object} [options]
   * @param {number} [options.firstId] README section 3: ids come from one counter that never
   *     repeats while the page lives. A tool that restores the same snapshot again MUST keep
   *     using one line, so its ids go on counting.
   * @param {(message: object) => void} [options.onMessage] Sees every message as it arrives.
   */
  constructor(emulator, { firstId = 1, onMessage = () => {} } = {}) {
    this.#emulator = emulator;
    this.#nextId = firstId;
    this.onMessage = onMessage;
    this.#sender = new CreditedSender(bytes => emulator.serial_send_bytes(1, bytes));
    emulator.add_listener('serial1-output-byte', byte => {
      this.#pending.push(byte);
      // One decode per v86 slice rather than per byte.
      if (!this.#flushQueued) {
        this.#flushQueued = true;
        queueMicrotask(() => this.#flush());
      }
    });
  }

  /** After a restore: the agent that owed credit, and any half frame, belong to the old machine. */
  reset() {
    this.#pending.length = 0;
    this.#decoder.reset();
    this.#sender.reset();
  }

  /** A new id, for a RUN whose files have to be written under its id before it is sent. */
  reserveId() {
    return this.#nextId++;
  }

  /** Sends a message and returns its id. `id` defaults to a new one. */
  send(type, body = {}, { id = this.#nextId++, data } = {}) {
    this.#sender.send(encodeMessage({ type, id, body: data ? undefined : body, data }));
    return id;
  }

  /**
   * Sends a request and resolves with the first message carrying its id whose type is in
   * `answers`. An ERROR with that id rejects.
   */
  request(type, body, { answers, timeoutMs = 30_000 } = {}) {
    const id = this.send(type, body);
    return this.waitFor(message => message.id === id && (answers.includes(message.type) || message.type === 'ERROR'),
      timeoutMs, `${answers.join(' or ')} to ${type}#${id}`).then(message => {
      if (message.type === 'ERROR') {
        throw new Error(`${type}#${id}: ERROR ${message.body.code}: ${message.body.message}`);
      }
      return message;
    });
  }

  /** Resolves with the first message from now on that `predicate` accepts. */
  waitFor(predicate, timeoutMs, what = 'a message') {
    return new Promise((resolve, reject) => {
      const waiter = { predicate, resolve };
      waiter.timer = setTimeout(() => {
        this.#waiters.delete(waiter);
        reject(new Error(`no ${what} within ${timeoutMs} ms`));
      }, timeoutMs);
      this.#waiters.add(waiter);
    });
  }

  #flush() {
    this.#flushQueued = false;
    const bytes = Uint8Array.from(this.#pending);
    this.#pending.length = 0;
    for (const event of this.#decoder.push(bytes)) {
      if (event.error) {
        this.received.push({ type: 'DROPPED', error: event.error, at: performance.now() });
        continue;
      }
      const decoded = decodeMessage(event.frame, { from: 'agent' });
      if (decoded.error) {
        this.received.push({ type: 'INVALID', error: decoded.error, field: decoded.field, at: performance.now() });
        continue;
      }
      const message = { ...decoded.message, at: performance.now() };
      this.received.push(message);
      if (message.type === 'CREDIT') this.#sender.grant(message.body.bytes);
      this.onMessage(message);
      for (const waiter of [...this.#waiters]) {
        if (waiter.predicate(message)) {
          this.#waiters.delete(waiter);
          clearTimeout(waiter.timer);
          waiter.resolve(message);
        }
      }
    }
  }

}
