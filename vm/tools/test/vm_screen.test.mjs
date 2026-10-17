// web/vm/vm_screen.js against a DOM just large enough for it: which platform
// view holds the screen, which part of it shows and how large, and what it
// tells v86 about input.

import assert from 'node:assert/strict';
import { afterEach, beforeEach, test } from 'node:test';

import { createVmScreen } from '../../../web/vm/vm_screen.js';

class FakeElement {

  children = [];
  parentNode = null;
  style = {};
  className = '';
  tabIndex = -1;
  clientWidth = 0;
  clientHeight = 0;
  focused = 0;
  #listeners = new Map();

  constructor(tagName, document) {
    this.tagName = tagName.toUpperCase();
    this.ownerDocument = document;
    const classes = () => new Set(this.className.split(' ').filter(Boolean));
    this.classList = {
      toggle: (name, on) => {
        const set = classes();
        if (on) set.add(name);
        else set.delete(name);
        this.className = [...set].join(' ');
      },
      contains: name => classes().has(name),
    };
  }

  appendChild(child) {
    child.remove();
    child.parentNode = this;
    this.children.push(child);
    return child;
  }

  remove() {
    if (!this.parentNode) return;
    const siblings = this.parentNode.children;
    siblings.splice(siblings.indexOf(this), 1);
    this.parentNode = null;
  }

  contains(other) {
    for (let node = other; node; node = node.parentNode) if (node === this) return true;
    return false;
  }

  /** An element the page holds, which is the only kind DOM focus can go to. */
  get isConnected() {
    return this.parentNode !== null;
  }

  closest(selector) {
    for (let node = this; node; node = node.parentNode) if (node.tagName === selector.toUpperCase()) return node;
    return null;
  }

  addEventListener(type, handler) {
    if (!this.#listeners.has(type)) this.#listeners.set(type, []);
    this.#listeners.get(type).push(handler);
  }

  removeEventListener(type, handler) {
    const handlers = this.#listeners.get(type) ?? [];
    handlers.splice(handlers.indexOf(handler), 1);
  }

  dispatch(type, event) {
    for (const handler of [...(this.#listeners.get(type) ?? [])]) handler(event);
  }

  set id(value) {
    this.ownerDocument.register(value, this);
  }

  focus() {
    this.focused++;
  }

  blur() {}

}

class FakeDocument {

  head = new FakeElement('head', this);
  defaultView = { devicePixelRatio: 1, requestAnimationFrame: callback => frames.push(callback) };
  #byId = new Map();

  createElement(tag) {
    return new FakeElement(tag, this);
  }

  register(id, element) {
    this.#byId.set(id, element);
  }

  getElementById(id) {
    return this.#byId.get(id) ?? null;
  }

}

let observers;

/** Animation frames asked for and not yet run. */
let frames;

/** Runs the frames asked for so far, and the ones they ask for, up to `count`. */
function flushFrames(count = 12) {
  for (let i = 0; i < count && frames.length; i++) {
    const pending = frames;
    frames = [];
    for (const callback of pending) callback();
  }
}

class FakeResizeObserver {

  constructor(callback) {
    this.callback = callback;
    observers.push(this);
  }

  observe(element) {
    this.element = element;
  }

  disconnect() {
    this.disconnected = true;
  }

}

function fakeEmulator() {
  const calls = [];
  const listeners = {};
  return {
    calls,
    keyboard_set_enabled: enabled => calls.push(['keyboard', enabled]),
    mouse_set_enabled: enabled => calls.push(['mouse', enabled]),
    add_listener: (name, listener) => { listeners[name] = listener; },
    emit: name => listeners[name]?.(),
  };
}

let document;

beforeEach(() => {
  frames = [];
  document = new FakeDocument();
  observers = [];
  globalThis.ResizeObserver = FakeResizeObserver;
});

afterEach(() => {
  delete globalThis.ResizeObserver;
});

/** The view element the screen is in: the screen sits in a crop box of its own. */
const holderOf = screen => screen.container.parentNode?.parentNode ?? null;

/** Sizes a view's element as layout would, and lets its observer see it. */
function resize(element, width, height) {
  element.clientWidth = width;
  element.clientHeight = height;
  for (const observer of observers) if (observer.element === element && !observer.disconnected) observer.callback();
}

test('holds a div and a canvas for v86, and installs its style once', () => {
  const screen = createVmScreen({ document });
  createVmScreen({ document });
  assert.deepEqual(screen.container.children.map(c => c.tagName), ['DIV', 'CANVAS']);
  assert.equal(document.head.children.length, 1);
});

test('the screen moves into the newest view, and back when that one goes', () => {
  const screen = createVmScreen({ document });
  const first = screen.viewElement(1);
  assert.equal(holderOf(screen), first);
  const second = screen.viewElement(2);
  assert.equal(holderOf(screen), second);
  assert.equal(first.children.length, 0);
  screen.releaseView(2);
  assert.equal(holderOf(screen), first);
  assert.equal(screen.viewId, 1);
  screen.releaseView(1);
  assert.equal(holderOf(screen), null);
  assert.equal(screen.viewId, null);
});

test('a replaced view disposed after its successor was built leaves the screen with the successor', () => {
  const screen = createVmScreen({ document });
  screen.viewElement(1);
  const successor = screen.viewElement(2);
  screen.releaseView(1);
  assert.equal(holderOf(screen), successor);
  assert.equal(observers[0].disconnected, true);
});

test('scales to fit its view, and draws at 1 when that is within 2 %', () => {
  const screen = createVmScreen({ document });
  const view = screen.viewElement(1);
  resize(view, 400, 400);
  assert.equal(screen.scale, 0.5);
  assert.deepEqual([screen.container.style.width, screen.container.style.height], ['400px', '300px']);
  assert.equal(screen.container.classList.contains('icc-vm-pixelated'), false);
  resize(view, 808, 700);
  assert.equal(screen.scale, 1);
  assert.deepEqual([screen.container.style.width, screen.container.style.height], ['800px', '600px']);
  assert.equal(screen.container.classList.contains('icc-vm-pixelated'), true);
});

test('a view that is not showing the screen does not rescale it', () => {
  const screen = createVmScreen({ document });
  const first = screen.viewElement(1);
  const second = screen.viewElement(2);
  resize(second, 1600, 1200);
  resize(first, 400, 300);
  assert.equal(screen.scale, 2);
});

test('keys and the mouse stay off until asked for, and v86 is told again once it runs', () => {
  const screen = createVmScreen({ document });
  const emulator = fakeEmulator();
  screen.attach(emulator);
  assert.deepEqual(emulator.calls, [['keyboard', false], ['mouse', false]]);
  screen.setKeyboardEnabled(true);
  screen.setMouseEnabled(true);
  emulator.calls.length = 0;
  emulator.emit('emulator-started');
  assert.deepEqual(emulator.calls, [['keyboard', true], ['mouse', true]]);
});

test('reports focus entering and leaving a view, not moving inside it', () => {
  const focus = [];
  const screen = createVmScreen({ document, onFocus: event => focus.push(event) });
  const view = screen.viewElement(4);
  const outside = document.createElement('div');
  view.dispatch('focusin', { relatedTarget: outside });
  view.dispatch('focusout', { relatedTarget: screen.container });
  view.dispatch('focusout', { relatedTarget: outside });
  assert.deepEqual(focus, [{ viewId: 4, inside: true }, { viewId: 4, inside: false }]);
});

test('a focus request waits for the view\'s element to reach the page', () => {
  const screen = createVmScreen({ document });
  const flutterView = document.createElement('flutter-view');
  const view = screen.viewElement(1);
  // Flutter asks in the frame that builds the display; the engine puts the
  // element in the page after it.
  screen.focusElement();
  assert.equal(view.focused, 0);
  flutterView.appendChild(view);
  flushFrames();
  assert.equal(view.focused, 1);
});

test('a focus request the page never takes up gives in, and does not come back later', () => {
  const screen = createVmScreen({ document });
  const view = screen.viewElement(1);
  screen.focusElement();
  flushFrames();
  document.createElement('flutter-view').appendChild(view);
  flushFrames();
  assert.equal(view.focused, 0);
});

test('a focus request the display takes back is dropped', () => {
  const screen = createVmScreen({ document });
  const flutterView = document.createElement('flutter-view');
  const view = screen.viewElement(1);
  screen.focusElement();
  screen.releaseFocus();
  flutterView.appendChild(view);
  flushFrames();
  assert.equal(view.focused, 0);
});

test('releasing focus hands it to the flutter-view rather than blurring', () => {
  const screen = createVmScreen({ document });
  const flutterView = document.createElement('flutter-view');
  const view = screen.viewElement(1);
  flutterView.appendChild(view);
  screen.focusElement();
  assert.equal(view.focused, 1);
  screen.releaseFocus();
  assert.equal(flutterView.focused, 1);
});

test('the background colour reaches every view, later ones included', () => {
  const screen = createVmScreen({ document });
  const first = screen.viewElement(1);
  screen.setBackground('#123456');
  const second = screen.viewElement(2);
  assert.equal(first.style.background, '#123456');
  assert.equal(second.style.background, '#123456');
});

/** What the crop box and the screen in it are set to, as CSS. */
function geometry(screen) {
  const crop = screen.container.parentNode.style;
  const { width, height, left, top } = screen.container.style;
  return { crop: [crop.width, crop.height], screen: [width, height], at: [left, top] };
}

test('shows the part of the screen it is given, at the scale it is given', () => {
  const screen = createVmScreen({ document });
  screen.viewElement(1);
  screen.setViewport({ x: 100, y: 50, width: 237, height: 113, scale: 1 });
  assert.equal(screen.scale, 1);
  assert.deepEqual(screen.viewport, { x: 100, y: 50, width: 237, height: 113 });
  assert.deepEqual(geometry(screen), { crop: ['237px', '113px'], screen: ['800px', '600px'], at: ['-100px', '-50px'] });
  assert.equal(screen.container.classList.contains('icc-vm-pixelated'), true);

  screen.setViewport({ x: 100, y: 50, width: 237, height: 113, scale: 0.5 });
  assert.deepEqual(geometry(screen), { crop: ['118.5px', '56.5px'], screen: ['400px', '300px'], at: ['-50px', '-25px'] });
  assert.equal(screen.container.classList.contains('icc-vm-pixelated'), false, 'half a device pixel per guest pixel');
});

test('a given scale does not follow the view, which its caller sizes', () => {
  const screen = createVmScreen({ document });
  const view = screen.viewElement(1);
  screen.setViewport({ x: 0, y: 0, width: 200, height: 100, scale: 1 });
  resize(view, 400, 400);
  assert.equal(screen.scale, 1);
  assert.deepEqual(geometry(screen).crop, ['200px', '100px']);
});

test('draws nearest-neighbour only where a guest pixel covers whole device pixels', () => {
  document.defaultView.devicePixelRatio = 2;
  const screen = createVmScreen({ document });
  screen.viewElement(1);
  screen.setViewport({ width: 800, height: 600, scale: 0.5 });
  assert.equal(screen.container.classList.contains('icc-vm-pixelated'), true);
  document.defaultView.devicePixelRatio = 1.25;
  screen.setViewport({ width: 800, height: 600, scale: 0.8 });
  assert.equal(screen.container.classList.contains('icc-vm-pixelated'), true);
  screen.setViewport({ width: 800, height: 600, scale: 1 });
  assert.equal(screen.container.classList.contains('icc-vm-pixelated'), false, '1.25 device pixels per guest pixel');
});

test('without a scale, the part shown fits the view', () => {
  const screen = createVmScreen({ document });
  const view = screen.viewElement(1);
  resize(view, 400, 400);
  screen.setViewport({ x: 0, y: 500, width: 200, height: 100 });
  assert.equal(screen.scale, 2);
  assert.deepEqual(geometry(screen), { crop: ['400px', '200px'], screen: ['1600px', '1200px'], at: ['0px', '-1000px'] });
});

test('keeps the part shown on the screen, and shows all of it for nonsense', () => {
  const screen = createVmScreen({ document });
  screen.viewElement(1);
  screen.setViewport({ x: -20, y: 580, width: 100, height: 100, scale: 1 });
  assert.deepEqual(screen.viewport, { x: 0, y: 580, width: 80, height: 20 });
  screen.setViewport({ x: 0, y: 0, width: 0, height: 100, scale: 1 });
  assert.deepEqual(screen.viewport, { x: 0, y: 0, width: 800, height: 600 });
  screen.setViewport({ x: Number.NaN, y: 0, width: 10, height: 10 });
  assert.deepEqual(screen.viewport, { x: 0, y: 0, width: 800, height: 600 });
});

test('destroying it takes the screen out of the page', () => {
  const screen = createVmScreen({ document });
  const view = screen.viewElement(1);
  screen.destroy();
  assert.equal(view.children.length, 0);
  assert.equal(holderOf(screen), null);
});
