// The VM's display in the page: the one element tree v86 draws into, and the
// Flutter platform views that show it. Browser only.
//
// Flutter can hold more than one platform view of the display at a time: a
// layout switch or a route replacement builds the new view before it disposes
// the old one. Each view id therefore gets an element of its own, and the single
// v86 screen moves into the newest. Handing every view the same element would
// let the old view's teardown take it out from under the new one.

const STYLE_ID = 'icc-vm-screen-style';

/** Scales this close to 1 are drawn at 1, pixel for pixel, rather than blurred
 *  by a resample nobody would notice the size of. */
const SNAP_TO_ONE = 0.02;

/** How many frames a focus request waits for its view's element to reach the
 *  document. Flutter asks for focus in the frame that builds the view, and the
 *  engine puts the element in the page a frame or two later. */
const FOCUS_FRAMES = 10;

// The crop box shows one part of the screen: the screen sits inside it at a
// negative offset, and the box clips the rest. v86 maps a pointer by its place
// in the screen box's bounding rect, which includes that offset, so a click
// lands on the guest pixel under it at any offset and scale.
//
// v86 sizes its canvas with inline styles computed from its own scale, and
// divides that scale by a fractional devicePixelRatio, which would leave the
// canvas smaller than the box its mouse maps clicks onto. The stylesheet wins
// over those inline styles, so the canvas always fills the screen box exactly.
// v86 also sets `image-rendering: pixelated` inline whenever its own scale is
// whole, which it always is here; shrunk that way, a one-pixel line can vanish,
// so the stylesheet decides that too. The text layer only ever shows before X
// starts, which no restored machine is.
//
// v86's absolute mouse hides the pointer (`cursor: none`, set inline on the
// screen box) because a guest with a hardware cursor draws its own. Xorg on
// fbdev draws none, so the page was left with no pointer at all over the
// program's window. A rule with !important beats that inline style.
const STYLE = `
.icc-vm-view { width: 100%; height: 100%; display: flex; align-items: center; justify-content: center;
  overflow: hidden; outline: none; cursor: default; }
.icc-vm-view, .icc-vm-crop, .icc-vm-screen, .icc-vm-screen > canvas { cursor: default !important; }
.icc-vm-crop { position: relative; flex: none; overflow: hidden; }
.icc-vm-screen { position: absolute; left: 0; top: 0; }
.icc-vm-screen > canvas { display: block !important; width: 100% !important; height: 100% !important;
  image-rendering: auto !important; }
.icc-vm-screen.icc-vm-pixelated > canvas { image-rendering: pixelated !important; }
.icc-vm-screen > div { display: none !important; }
`;

/**
 * @param {object} [options]
 * @param {Document} [options.document]
 * @param {number} [options.width] The guest's screen, in guest pixels.
 * @param {number} [options.height]
 * @param {(event: {viewId: number, inside: boolean}) => void} [options.onFocus]
 *     DOM focus entering or leaving a view's element.
 * @returns {VmScreen}
 */
export function createVmScreen(options = {}) {
  return new VmScreen(options);
}

export class VmScreen {

  /** The screen's scale on the page: CSS pixels per guest pixel. */
  scale = 1;

  #document;
  #width;
  #height;
  #onFocus;
  #crop;
  #screen;
  #views = new Map();
  #holder = null;
  #emulator = null;
  #keyboard = false;
  #mouse = false;
  #background = '';
  #viewport;
  #wantsFocus = false;
  #destroyed = false;

  constructor({ document = globalThis.document, width = 800, height = 600, onFocus = () => {} } = {}) {
    this.#document = document;
    this.#width = width;
    this.#height = height;
    this.#onFocus = onFocus;
    this.#viewport = this.#wholeScreen();
    installStyle(document);
    this.#crop = document.createElement('div');
    this.#crop.className = 'icc-vm-crop';
    this.#screen = document.createElement('div');
    this.#screen.className = 'icc-vm-screen';
    // v86 finds these by tag name and draws into them.
    this.#screen.appendChild(document.createElement('div'));
    this.#screen.appendChild(document.createElement('canvas'));
    this.#crop.appendChild(this.#screen);
    this.#size(1);
  }

  /** v86's screen container: pass it as the machine's `screen`. */
  get container() {
    return this.#screen;
  }

  /** The view the screen is in now, or null. */
  get viewId() {
    return this.#holder;
  }

  /** The part of the screen shown, in guest pixels: `{x, y, width, height}`. */
  get viewport() {
    const { x, y, width, height } = this.#viewport;
    return { x, y, width, height };
  }

  /**
   * The element for platform view `viewId`: Flutter's view factory. The screen
   * moves into it, as the newest view.
   */
  viewElement(viewId) {
    this.releaseView(viewId);
    const element = this.#document.createElement('div');
    element.className = 'icc-vm-view';
    element.tabIndex = 0;
    element.style.background = this.#background;
    const view = { element, observer: null, listeners: [] };
    const listen = (type, handler) => {
      element.addEventListener(type, handler);
      view.listeners.push([type, handler]);
    };
    // Focus moving between elements inside the view is neither leaving nor entering.
    listen('focusin', event => {
      if (!element.contains(event.relatedTarget)) this.#onFocus({ viewId, inside: true });
    });
    listen('focusout', event => {
      if (!element.contains(event.relatedTarget)) this.#onFocus({ viewId, inside: false });
    });
    if (typeof ResizeObserver === 'function') {
      view.observer = new ResizeObserver(() => {
        if (this.#holder === viewId) this.#fit();
      });
      view.observer.observe(element);
    }
    this.#views.set(viewId, view);
    this.#hold(viewId);
    return element;
  }

  /**
   * Forgets view `viewId`, which Flutter is disposing. If it held the screen,
   * the newest view left takes it.
   */
  releaseView(viewId) {
    const view = this.#views.get(viewId);
    if (!view) return;
    view.observer?.disconnect();
    for (const [type, handler] of view.listeners) view.element.removeEventListener(type, handler);
    this.#views.delete(viewId);
    if (this.#holder !== viewId) return;
    this.#holder = null;
    const newest = [...this.#views.keys()].pop();
    if (newest === undefined) this.#crop.remove();
    else this.#hold(newest);
  }

  /**
   * Shows the part of the screen at `x`, `y` of `width` × `height` guest
   * pixels, clamped to the screen, drawn at `scale` CSS pixels per guest pixel.
   * Without a scale it is drawn as large as fits the view, keeping its shape;
   * with no arguments at all, that is the whole screen.
   *
   * A caller that passes a scale MUST size the view to `width × scale` by
   * `height × scale`: the view clips to its own box, and nothing else here
   * reads it.
   */
  setViewport({ x = 0, y = 0, width = this.#width, height = this.#height, scale = null } = {}) {
    const left = clamp(Math.round(x), 0, this.#width - 1);
    const top = clamp(Math.round(y), 0, this.#height - 1);
    const right = clamp(Math.round(x + width), left + 1, this.#width);
    const bottom = clamp(Math.round(y + height), top + 1, this.#height);
    const valid = [x, y, width, height].every(Number.isFinite) && width > 0 && height > 0;
    this.#viewport = valid
      ? { x: left, y: top, width: right - left, height: bottom - top, scale: scale > 0 ? scale : null }
      : this.#wholeScreen();
    this.#fit();
  }

  /** Hands the screen's input to `emulator` once the machine exists. Keys and
   *  the mouse stay off until setKeyboardEnabled and setMouseEnabled say otherwise. */
  attach(emulator) {
    this.#emulator = emulator;
    // v86 creates its input adapters enabled, and they listen on the whole window.
    emulator.add_listener?.('emulator-started', () => this.#apply());
    this.#apply();
  }

  detach() {
    this.#emulator = null;
  }

  /** v86 listens for keys on the window, so this is what keeps typing into the
   *  rest of the app from reaching the guest. */
  setKeyboardEnabled(enabled) {
    this.#keyboard = Boolean(enabled);
    this.#apply();
  }

  setMouseEnabled(enabled) {
    this.#mouse = Boolean(enabled);
    this.#apply();
  }

  /**
   * Moves DOM focus into the view that shows the screen, waiting for its
   * element if the request came before the page had it: the display is built
   * by the same frame that asks for focus, and its element arrives after.
   */
  focusElement() {
    this.#wantsFocus = true;
    this.#takeFocus(0);
  }

  #takeFocus(attempt) {
    if (!this.#wantsFocus || this.#destroyed) return;
    const element = this.#views.get(this.#holder)?.element;
    if (element?.isConnected) {
      this.#wantsFocus = false;
      element.focus({ preventScroll: true });
      return;
    }
    const window = this.#document.defaultView;
    if (attempt >= FOCUS_FRAMES || typeof window?.requestAnimationFrame !== 'function') {
      this.#wantsFocus = false;
      return;
    }
    window.requestAnimationFrame(() => this.#takeFocus(attempt + 1));
  }

  /**
   * Moves DOM focus out of the view without blurring: a blur leaves focus on
   * the body, which Flutter reads as its whole view losing focus.
   */
  releaseFocus() {
    this.#wantsFocus = false;
    const element = this.#views.get(this.#holder)?.element;
    if (!element) return;
    const flutterView = element.closest?.('flutter-view');
    if (flutterView) flutterView.focus({ preventScroll: true });
    else element.blur();
  }

  /** The colour around the screen when the view is larger than it, as CSS. */
  setBackground(css) {
    this.#background = css;
    for (const { element } of this.#views.values()) element.style.background = css;
  }

  destroy() {
    if (this.#destroyed) return;
    this.#destroyed = true;
    for (const viewId of [...this.#views.keys()]) this.releaseView(viewId);
    this.#crop.remove();
    this.#emulator = null;
  }

  #wholeScreen() {
    return { x: 0, y: 0, width: this.#width, height: this.#height, scale: null };
  }

  #hold(viewId) {
    const view = this.#views.get(viewId);
    view.element.appendChild(this.#crop);
    this.#holder = viewId;
    this.#fit();
  }

  /**
   * Draws the viewport at the scale it was given, or at the largest that fits
   * the view. The crop box is exactly the drawn part: the view centres it, and
   * a box larger than what it shows would take clicks that land on nothing.
   */
  #fit() {
    let scale = this.#viewport.scale;
    if (scale === null) {
      const element = this.#views.get(this.#holder)?.element;
      const width = element?.clientWidth ?? 0;
      const height = element?.clientHeight ?? 0;
      if (!width || !height) return;
      scale = Math.min(width / this.#viewport.width, height / this.#viewport.height);
      if (Math.abs(scale - 1) < SNAP_TO_ONE) scale = 1;
    }
    this.#size(scale);
  }

  #size(scale) {
    this.scale = scale;
    const { x, y, width, height } = this.#viewport;
    Object.assign(this.#crop.style, { width: px(width * scale), height: px(height * scale) });
    Object.assign(this.#screen.style, {
      width: px(this.#width * scale),
      height: px(this.#height * scale),
      left: px(-x * scale),
      top: px(-y * scale),
    });
    // Nearest-neighbour is exact only where a guest pixel covers whole device
    // pixels; anywhere else it drops or doubles rows, and a resample reads better.
    const devicePixels = scale * (this.#document.defaultView?.devicePixelRatio ?? 1);
    this.#screen.classList.toggle('icc-vm-pixelated', devicePixels >= 1 && Math.abs(devicePixels - Math.round(devicePixels)) < 1e-6);
  }

  #apply() {
    this.#emulator?.keyboard_set_enabled?.(this.#keyboard);
    this.#emulator?.mouse_set_enabled?.(this.#mouse);
  }

}

function clamp(value, low, high) {
  return Math.min(Math.max(value, low), high);
}

/** CSS pixels, without the float noise a scale leaves in the last digits. */
function px(value) {
  return `${Math.round(value * 1000) / 1000}px`;
}

function installStyle(document) {
  if (document.getElementById(STYLE_ID)) return;
  const style = document.createElement('style');
  style.id = STYLE_ID;
  style.textContent = STYLE;
  document.head.appendChild(style);
}
