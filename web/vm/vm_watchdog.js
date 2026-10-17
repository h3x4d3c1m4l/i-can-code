// The deadlines of vm/protocol/README.md section 9.7, counted in the time the
// guest could have used rather than in wall-clock time.

/** How often the watchdog samples, and the most one sample may add, in ms. */
export const SAMPLE_MS = 100;

/**
 * The most time rootfs fetches may hold one deadline, in ms: as long as one
 * fetch attempt may take. Past it, a guest that keeps the network busy is
 * counted like any other, so a hung agent cannot hide behind a stream of reads.
 */
export const FETCH_HOLD_CAP_MS = 30_000;

/**
 * A deadline that counts only active time (README 9.7).
 *
 * It samples every 100 ms and adds the time since the sample before, capped at
 * 100 ms, so a main thread that was busy elsewhere (a restore, a GC, Flutter's
 * layout) costs the guest one sample rather than the whole gap.
 *
 * Two things hold the count. A pause, for a stopped CPU or a hidden page,
 * stops it, and the last resume restarts the deadline in full: a guest that has
 * just got its CPU back needs the whole allowance to answer. A rootfs fetch in
 * flight only suspends it, up to FETCH_HOLD_CAP_MS per deadline, and the count
 * goes on from where it stood once the fetch lands. Restarting on every fetch
 * would let a hung agent live for good while its guest reads a file every half
 * second.
 */
export class Watchdog {

  #timeoutMs = 0;
  #onExpire = null;
  #holds = new Set();
  #fetching = false;
  #remaining = 0;
  #fetchHeldMs = 0;
  #last = 0;
  #timer = null;
  #now;

  /** @param {{now?: () => number}} [options] */
  constructor({ now = () => performance.now() } = {}) {
    this.#now = now;
  }

  /** Arms the deadline: `onExpire` runs once, after `timeoutMs` of active time
   *  without a kick(). Re-arming replaces the previous deadline. */
  start(timeoutMs, onExpire) {
    this.#timeoutMs = timeoutMs;
    this.#onExpire = onExpire;
    this.#rearm();
  }

  /** Proof of life: restarts the deadline in full. Does nothing while disarmed. */
  kick() {
    if (this.#onExpire) this.#rearm();
  }

  stop() {
    this.#onExpire = null;
    this.#clear();
  }

  /** Stops the count until every reason paused so far has been resumed. */
  pause(reason) {
    this.#holds.add(reason);
    this.#clear();
  }

  /** The last resume restarts an armed deadline in full. */
  resume(reason) {
    if (!this.#holds.delete(reason) || !this.#onExpire) return;
    this.#remaining = this.#timeoutMs;
    this.#count();
  }

  /** Whether a rootfs file is on its way. The count is suspended meanwhile, not restarted. */
  setFetching(fetching) {
    this.#fetching = Boolean(fetching);
  }

  get armed() {
    return this.#onExpire !== null;
  }

  /** Whether active time is being taken off the deadline right now. */
  get counting() {
    return this.#timer !== null && !this.#fetchExcused();
  }

  #rearm() {
    this.#remaining = this.#timeoutMs;
    this.#fetchHeldMs = 0;
    this.#count();
  }

  #count() {
    this.#clear();
    if (this.#holds.size > 0) return;
    this.#last = this.#now();
    this.#timer = setInterval(() => this.#sample(), SAMPLE_MS);
  }

  #fetchExcused() {
    return this.#fetching && this.#fetchHeldMs < FETCH_HOLD_CAP_MS;
  }

  #sample() {
    const now = this.#now();
    const step = Math.min(now - this.#last, SAMPLE_MS);
    this.#last = now;
    if (this.#fetchExcused()) {
      this.#fetchHeldMs += step;
      return;
    }
    this.#remaining -= step;
    if (this.#remaining > 0) return;
    const onExpire = this.#onExpire;
    this.stop();
    onExpire();
  }

  #clear() {
    if (this.#timer === null) return;
    clearInterval(this.#timer);
    this.#timer = null;
  }

}
