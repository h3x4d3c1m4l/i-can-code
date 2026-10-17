import assert from 'node:assert/strict';
import { beforeEach, test } from 'node:test';

import { Watchdog } from '../../../web/vm/vm_host.js';
import { FETCH_HOLD_CAP_MS } from '../../../web/vm/vm_watchdog.js';

const MINUTE = 60_000;

let expired;
let watchdog;

beforeEach(t => {
  // The watchdog samples on an interval and reads the time through the clock it is given.
  t.mock.timers.enable({ apis: ['setInterval', 'Date'] });
  expired = 0;
  watchdog = new Watchdog({ now: () => Date.now() });
});

const onExpire = () => { expired++; };

/** Mocked time moves Date to the end of a tick before the interval runs, so a
 *  tick longer than one sample would look to the watchdog like a stalled thread. */
function advance(t, ms) {
  for (; ms >= 100; ms -= 100) t.mock.timers.tick(100);
  if (ms > 0) t.mock.timers.tick(ms);
}

test('expires once the timeout passes without a kick', t => {
  watchdog.start(1000, onExpire);
  advance(t, 999);
  assert.equal(expired, 0);
  advance(t, 1);
  assert.equal(expired, 1);
  assert.equal(watchdog.armed, false);
});

test('expires only once', t => {
  watchdog.start(1000, onExpire);
  advance(t, 10 * MINUTE);
  assert.equal(expired, 1);
});

test('a kick restarts the deadline in full', t => {
  watchdog.start(1000, onExpire);
  advance(t, 900);
  watchdog.kick();
  advance(t, 900);
  assert.equal(expired, 0);
  advance(t, 100);
  assert.equal(expired, 1);
});

test('stop disarms it, and a later kick does not re-arm it', t => {
  watchdog.start(1000, onExpire);
  watchdog.stop();
  watchdog.kick();
  advance(t, 10 * MINUTE);
  assert.equal(expired, 0);
  assert.equal(watchdog.armed, false);
});

test('a backgrounded tab never expires it, however long it stays hidden', t => {
  watchdog.start(1000, onExpire);
  advance(t, 900);
  watchdog.pause('hidden');
  assert.equal(watchdog.counting, false);
  advance(t, 60 * MINUTE);
  assert.equal(expired, 0);
  assert.equal(watchdog.armed, true);
});

test('resuming restarts the deadline in full rather than finishing the old one', t => {
  watchdog.start(1000, onExpire);
  advance(t, 900);
  watchdog.pause('cpu');
  advance(t, 5 * MINUTE);
  watchdog.resume('cpu');
  advance(t, 999);
  assert.equal(expired, 0);
  advance(t, 1);
  assert.equal(expired, 1);
});

test('counts only once every reason has been resumed', t => {
  watchdog.start(1000, onExpire);
  watchdog.pause('hidden');
  watchdog.pause('cpu');
  watchdog.resume('hidden');
  advance(t, 10 * MINUTE);
  assert.equal(expired, 0);
  watchdog.resume('cpu');
  assert.equal(watchdog.counting, true);
  advance(t, 1000);
  assert.equal(expired, 1);
});

test('pausing twice for one reason needs one resume', t => {
  watchdog.start(1000, onExpire);
  watchdog.pause('cpu');
  watchdog.pause('cpu');
  watchdog.resume('cpu');
  advance(t, 1000);
  assert.equal(expired, 1);
});

test('resuming a reason that was never paused does not move the deadline', t => {
  watchdog.start(1000, onExpire);
  advance(t, 900);
  watchdog.resume('hidden');
  advance(t, 100);
  assert.equal(expired, 1);
});

test('started while paused, it waits for the resume before counting', t => {
  watchdog.pause('hidden');
  watchdog.start(1000, onExpire);
  assert.equal(watchdog.counting, false);
  advance(t, 10 * MINUTE);
  assert.equal(expired, 0);
  watchdog.resume('hidden');
  advance(t, 1000);
  assert.equal(expired, 1);
});

test('a main thread busy elsewhere costs one sample, not the whole gap', t => {
  watchdog.start(1000, onExpire);
  advance(t, 100);
  // Five seconds pass with the interval late by all of them, as behind a long task.
  t.mock.timers.setTime(Date.now() + 5000);
  advance(t, 100);
  assert.equal(expired, 0);
  advance(t, 700);
  assert.equal(expired, 0);
  advance(t, 100);
  assert.equal(expired, 1);
});

test('re-arming replaces the timeout and the callback', t => {
  let second = 0;
  watchdog.start(1000, onExpire);
  advance(t, 500);
  watchdog.start(2000, () => { second++; });
  advance(t, 1999);
  assert.deepEqual([expired, second], [0, 0]);
  advance(t, 1);
  assert.deepEqual([expired, second], [0, 1]);
});

// Rootfs fetches

test('short fetches over and over do not hand a hung guest a fresh deadline', t => {
  watchdog.start(1000, onExpire);
  // Were each fetch to restart the deadline, a 20 ms fetch every 700 ms would keep it from ever expiring.
  for (let cycle = 0; cycle < 3 && expired === 0; cycle++) {
    advance(t, 700);
    watchdog.setFetching(true);
    advance(t, 20);
    watchdog.setFetching(false);
  }
  assert.equal(expired, 1);
});

test('a fetch in flight suspends the count, and it goes on from where it stood', t => {
  watchdog.start(1000, onExpire);
  advance(t, 600);
  watchdog.setFetching(true);
  assert.equal(watchdog.counting, false);
  advance(t, 20_000);
  assert.equal(expired, 0);
  watchdog.setFetching(false);
  assert.equal(watchdog.counting, true);
  advance(t, 300);
  assert.equal(expired, 0);
  advance(t, 100);
  assert.equal(expired, 1);
});

test('fetches hold one deadline for at most FETCH_HOLD_CAP_MS in all', t => {
  watchdog.start(1000, onExpire);
  watchdog.setFetching(true);
  advance(t, FETCH_HOLD_CAP_MS - 100);
  assert.equal(watchdog.counting, false);
  advance(t, 100);
  assert.equal(watchdog.counting, true, 'past the cap the fetch no longer excuses the guest');
  advance(t, 900);
  assert.equal(expired, 0);
  advance(t, 100);
  assert.equal(expired, 1);
});

test('the cap counts across fetches, and a kick gives it back', t => {
  watchdog.start(1000, onExpire);
  for (let i = 0; i < 3; i++) {
    watchdog.setFetching(true);
    advance(t, FETCH_HOLD_CAP_MS / 3);
    watchdog.setFetching(false);
  }
  watchdog.setFetching(true);
  assert.equal(watchdog.counting, true, 'the cap is spent');
  watchdog.kick();
  assert.equal(watchdog.counting, false, 'a new deadline has a new allowance');
  advance(t, 10 * MINUTE);
  assert.equal(expired, 1, 'and that one runs out too');
});

test('getting the CPU back restarts the deadline in full, fetch or no fetch', t => {
  watchdog.start(1000, onExpire);
  advance(t, 800);
  watchdog.setFetching(true);
  watchdog.pause('cpu');
  advance(t, MINUTE);
  watchdog.setFetching(false);
  watchdog.resume('cpu');
  advance(t, 999);
  assert.equal(expired, 0);
  advance(t, 1);
  assert.equal(expired, 1);
});
