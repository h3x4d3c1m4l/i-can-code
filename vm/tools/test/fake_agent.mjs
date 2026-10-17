// A stand-in for icc-agent that speaks the protocol from vm/protocol/README.md
// through web/vm/vm_protocol.js, so the host's run layer can be tested without
// an image. Each test decides how it answers a RUN.

import { decodeMessage, encodeMessage, FrameDecoder, MAX_PAYLOAD_TO_AGENT } from '../../../web/vm/vm_protocol.js';

export class FakeAgent {

  /** Every message the host sent, since construction. */
  received = [];
  /** A stopped agent (SIGSTOP) reads nothing and answers nothing. */
  frozen = false;
  /** Answers STOP with EXIT. */
  answersStop = true;
  /** An ERROR code to answer RUN with instead of STARTED. */
  refuse = null;
  /** Called with the run id and the RUN body, after STARTED. */
  onRun = () => {};
  onClose = () => {};

  #emulator;
  #decoder = new FrameDecoder({ maxPayload: MAX_PAYLOAD_TO_AGENT });
  #run = null;

  constructor(emulator) {
    this.#emulator = emulator;
  }

  /** The snapshot's agent: waiting, owing no credit, with no run. */
  reset() {
    this.#decoder.reset();
    this.#run = null;
    this.frozen = false;
  }

  receive(bytes) {
    if (this.frozen) return;
    this.send('CREDIT', { bytes: bytes.length }, 0);
    for (const event of this.#decoder.push(bytes)) {
      if (!event.frame) continue;
      const decoded = decodeMessage(event.frame, { from: 'host' });
      if (decoded.error) throw new Error(`the host sent an invalid ${decoded.error}`);
      this.received.push(decoded.message);
      this.#handle(decoded.message);
    }
  }

  send(type, body, id, data) {
    this.#emulator.agentSend(encodeMessage({ type, id, body, data }));
  }

  output(stream, bytes) {
    this.send(stream === 'stdout' ? 'STDOUT' : 'STDERR', undefined, this.#run, bytes);
  }

  exit(body) {
    const run = this.#run;
    this.#run = null;
    this.send('EXIT', { code: 0, signal: null, reason: 'exit', truncated: false, ms: 10, ...body }, run);
  }

  get run() {
    return this.#run;
  }

  #handle({ type, id, body }) {
    switch (type) {
      case 'HELLO':
        this.send('READY', { agent: 'fake', python: 'Python 3.12.14', tk: '8.6.16', tz: body.tz, warm: true }, id);
        return;
      case 'PING':
        this.send('PONG', {}, id);
        return;
      case 'RUN': {
        const missing = body.files.filter(name => !this.#emulator.files.has(`/icc/in/r${id}-${name}`));
        if (missing.length) {
          this.send('ERROR', { code: 'bad_files', message: `missing ${missing.join(' ')}` }, id);
          return;
        }
        if (this.refuse) {
          this.send('ERROR', { code: this.refuse, message: 'refused by the test' }, id);
          return;
        }
        this.#run = id;
        this.send('STARTED', { pid: 42, warm: true }, id);
        this.onRun(id, body);
        return;
      }
      case 'STOP':
        if (id === this.#run && this.answersStop) this.exit({ code: null, signal: 9, reason: 'stopped' });
        return;
      case 'CLOSE':
        if (id === this.#run) this.onClose(body.xid);
        return;
    }
  }

}
