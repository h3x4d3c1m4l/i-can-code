# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**I Can Code** — a **web-only** Flutter app that teaches programming. Assignments are plain files under `assets/lessons/`; the student's code runs in the browser. No backend, no login, no persistence.

Two things it is deliberately **not** scoped to:

- **It is not a Python app.** Python is the first language it teaches and the only runtime that exists so far (CPython built for `wasm32-wasi`), but the app is meant to teach others. Keep Python out of names, copy and marks that are not specifically about running Python — the app mark is a face drawn from code characters (`AppLogo`), not `py`.
- **It is not a De Haagse Hogeschool product.** THUAS is one of the colour presets it ships with, nothing more — see *Theming*.

## Commands

Flutter is managed via FVM (`.fvmrc` pins the version). Use `fvm flutter` / `fvm dart`, never bare `flutter` / `dart`.

```bash
fvm flutter pub get                     # dependencies
fvm dart run build_runner build         # code generation
fvm dart run build_runner watch         # ... in watch mode, while developing
fvm flutter gen-l10n                    # regenerate localizations from the ARB files
fvm dart analyze                        # lint
fvm flutter test                        # tests
fvm flutter build web                   # compile only; `just build` is the build that ships

just build                              # build with CanvasKit bundled, then tool/finish_web_build.dart
just serve-build                        # serve build/web on :8080, to watch a release build load

fvm dart run tool/try_lesson.dart <lesson.md>                       # list its sections
fvm dart run tool/try_lesson.dart <lesson.md> <n> --code 'print(1)' # run one, see the verdict

just build-rust-core                # regenerate the bridge and rebuild web/pkg/
just test-rust                          # the Rust core's own tests
just gen-rust-licenses                  # rewrite the crates' licence texts, after a Cargo.lock change
```

The `just` recipes need a Rust toolchain, and so does CI, which runs the same
build. See `docs/rust-core-build.md`.

`try_lesson.dart` runs a section through the **real** `PythonAttemptRunner`, so a lesson can be written and checked without the app. It uses the machine's own `python3` rather than the `wasm32-wasi` build the app ships, so check `python3 --version` before trusting a result that turns on a language feature.

After touching any `@observable` / `@readonly` / `@action`, `@freezed`, `@RoutePage()` or `@TailorMixin` annotated code, re-run `build_runner`.

### `sdk:` in pubspec.yaml is the *language version*, not the SDK

It is what the compiler allows this package's own source — generated code included — to use, and it is why the generator versions are pinned exactly.

It sat at `^3.12.0` for a long time: Dart 3.13 dropped `final` on constructor parameters, which `freezed 3.2.5` still emitted, so declaring 3.12 kept that syntax legal. `freezed 4.0.1` no longer emits it, and both `freezed 4.x` and `theme_tailor 4.x` declare `sdk: >=3.13.0`, so it is now `^3.13.0`.

Watch the same trap if a generator ever has to be held back again: `dart analyze` accepts code the compiler rejects, so **lint stays green while every build and test fails**. Verify a version bump with `fvm flutter test` and `fvm flutter build web`, never with `dart analyze` alone.

The generators gate the analyzer version for each other, and the narrowest one wins. `mobx_codegen` capped `analyzer <13` until 2.7.8 widened it, which is what unblocked freezed 4.x, and 2.8.0 narrowed it again to `^13.3.0`. With `theme_tailor 4.0.1` (`^13.0.0`) and `auto_route_generator 10.6.0` (`<14`) that holds `freezed` at 4.0.1 and `build_runner` at 2.16.1, which both want analyzer 14 from their next patch on. When a generator refuses to resolve, `fvm flutter pub get` names the package in the way.

## Architecture

### Widget file placement

Every widget lives under `lib/views/`, except `lib/app.dart` (the app shell).

Placement is **scoped by usage** — a widget lives as close to its only consumer as possible, and only moves up once a second screen needs it:

```text
lib/views/
  base/                     # ScreenBase & friends — closed; nothing goes in or out
  components/               # widgets used by 2+ screens (or by the app shell)
    app_header.dart
    loading_overlay.dart
  <some>_screen/
    <some>_screen.dart            # the four-file Screen pattern (see below)
    <some>_screen_controller.dart
    <some>_screen_view.dart
    <some>_screen_view_model.dart
    components/             # widgets used only by this screen
```

Rules of thumb:

- **One consumer → the screen's own `components/`. Two or more (or the app shell) → the shared `lib/views/components/`.** Applies to primitives too: a "generic-looking" widget only one screen uses stays scoped to that screen. Promote it when a second consumer appears; don't pre-promote it.
- Subfolders (`buttons/`, `dialogs/`, ...) are created inside a `components/` folder when there is **more than one** of a kind, or when there is a good reason to group.
- Imports point inward-to-outward: a screen-scoped widget may import from `lib/views/components/`, never the reverse.

### Workarounds get their own widget

Where a widget *lives* is the section above; this is about what earns being one. When something needs a trick to work — a framework quirk to route around, a clip that has to be undone, a measurement that drives a rebuild — **that trick gets its own widget, and everything else uses it as a plain drop-in.** A workaround spread across its call sites is a contract each of them can break silently, and none of them can check.

Two things come with the deal:

- **Name the trick.** A `RelaxedHorizontalClipper` says what it does; a bare inlined `CustomClipper` does not.
- **Write down the framework behaviour you are leaning on**, because that is what makes a workaround reviewable instead of load-bearing folklore.

### Screen pattern

Every screen is four classes wired together by `ScreenBase<TViewModel, TController, TView>` (`lib/views/base/`):

- **Screen** — the `StatefulWidget`; creates ViewModel, Controller and View via factory methods. Carries `@RoutePage()`.
- **ViewModel** (`ScreenViewModelBase` + MobX `Store`) — reactive state via `@readonly` / `@action`; generates a `*.g.dart`.
- **Controller** (`ScreenControllerBase`) — logic and event handlers; holds the ViewModel and a `BuildContextAccessor`.
- **View** (`ScreenViewBase`) — pure UI; reads the ViewModel, calls the Controller. Its `body` getter is the screen.

`.templates/view/` holds the scaffolds — start from those rather than copying an existing screen by hand.

Navigation is auto_route. A controller that needs to navigate goes through its `BuildContextAccessor`, and **must** check `_disposed` before touching `contextAccessor.buildContext` — the accessor is only assigned once the screen has built, so a controller that navigates from its constructor would otherwise read it too early. `InitializationScreenController` is the worked example.

### The bar

**The header belongs to no screen.** `AppHeaderHost` (`lib/views/components/`) sits above the router in the app shell, so navigating cannot move it: the mark, the cog and the popover state are one widget for the life of the app, and only what actually changed about the trail fades over. It was the first child of every screen's own column once, which meant a new screen brought a new bar — rebuilt from nothing on arrival and dragged along by whatever transition the page had.

A screen fills it by wrapping its body in `AppHeaderPublisher` and handing over an `AppHeaderBuilder`. A *builder*, not a built bar: the host resolves it inside its own `Observer`, so the lesson's step and the locale keep the trail and the progress bar current without the screen pushing anything at them. Below no host — a widget test that builds one screen — the publisher is a pass-through and the screen renders as it always did.

**The bar brings its own `Overlay` and `Navigator`** — `OverlayHost`, wrapped around everything the host lays out. Above the router means above the router's `Navigator`, and that is what the cog's popover (`OverlayPortal` throws without an `Overlay`) and its reset dialog (`showFDialog` looks up a `Navigator`) had been finding all along. Without it the cog is a red error box whose width squeezes the trail out of the row beside it. It covers the window rather than the bar, because both escape it: a menu clipped to 76px would end inside the bar, and a barrier has to dim the page it is asking about. It is built from a `Page` rather than `onGenerateRoute`, which caches the child it was handed on the first frame and would freeze the router under it on the screen it started on.

`test/views/app_header_host_test.dart` builds the host with **nothing above it**, the way the shell has nothing above it. A harness that wrapped it in a `Navigator` is what let this ship.

Two rules it exists to keep:

- **Publishing and releasing are deferred by a microtask.** The bar is built before the screen under it, so filling it from `initState` would rebuild a widget Flutter has already built this frame.
- **The bar belongs to the last screen still standing**, not to whoever spoke last. More than one screen is mounted at a time: a pushed screen leaves the one under it standing, and a replaced one is disposed only *after* its successor is built. So the host keeps a claim per screen in arrival order — bottom to top of the page stack — and a screen that leaves hands the bar back to the one underneath instead of emptying it. Emptying on release is what left the subject picker with no bar at all once the catalog above it was closed: auto_route keeps the page it already has, so nothing publishes on the way back down.

**Zen mode.** A lesson is read, so its bar starts out of the way: on a screen whose header says `offersZen` — only the lesson screen — the bar is gone when the lesson opens. It is **one thing the reader turns on and off, by a button each way**: the host floats one in the band the bar left behind to bring it back, and the bar carries one to put it away again. The answer is scoped to the lesson being read — **every lesson opens without the bar**, because asking for it back was about the lesson in front of the reader and not about every lesson after it — and it is not persisted either, since reading one lesson without the chrome is not a setting about the app.

Three rules behind that shape:

- **Nothing reveals the bar by itself.** It was a band along the top edge that the pointer reached into once, and a bar that came and went with the pointer moved the page under the reader's hands. With a button each way the bar only ever appears because the reader asked.
- **The page keeps its box.** It has the whole window whether the bar is showing or not, and the bar is drawn *over* it. Insetting the page instead reflowed the lesson on every press of either button, and cut what was scrolled past against an invisible edge with empty space above it.
- **A hidden bar keeps the one thing that was worth reading.** `AppHeaderConfig.zenLabel` is a few characters the host draws beside the floating button while the bar is away — on a lesson, the step the reader is on. It is the least of the progress bar that still says where they are, and it is a string rather than two numbers because the host places it and does not count. Null on the end page, which is not a step. The digits are a shorthand, so a screen reader is given `zenSemanticsLabel` and the digits are excluded rather than read twice.

- **A hidden bar must leave a way back.** The floating button waits in the band the bar left behind, in the cog's own column and at the cog's own height, so pressing it puts the cog under the pointer without either of them having moved — and it is a real focusable button, reachable by pointer, touch and tab alike. Meanwhile the bar itself is taken out of the focus *and* semantics trees, because off screen is not gone: it would otherwise still be read out and still take the tab meant for the page.

**The page runs under the bar and pads for it itself.** The host gives every screen the whole window; what keeps a first screenful clear of the bar is `AppHeader.height`, added to the screen's own scroll padding — which is why that constant appears in three views. Everything scrolled past then passes under the bar instead of being cut off above it. The catalog is slivers and starts with `BarClearanceSliver` instead: a pinned sliver of that height that paints nothing, so the headings that stick in it pin below the bar rather than behind it.

**The bar takes an edge once content is under it**, a line and a shadow along its bottom. At the top of a page there is none, because the bar and the page are one surface there. `AppHeaderPublisher` reads it off the scroll notifications bubbling up from its own page and reports it per screen, so a screen that comes back on top brings its own answer with it. Only a vertical scroll view whose top is under the bar counts, so an editor or a terminal scrolling inside itself does not. A disposed scroll view sends nothing on its way out, so the publisher drops gone ones after every frame while it tracks any. Without that, a lesson step left scrolled would hand its edge to the next one.

**The bar's contents stop at `breakpoints.xl`**, centred, while its surface stays full width — it is the top of the window, not a card in it. `xl` (1280) is the first Tailwind step that clears the widest column the app lays out, a lesson's two-column step at `1120 + 26`, so on a wide monitor the cog sits at the edge of the widest page instead of out in a corner. `AppHeader.chromeInset()` is that same measurement, and the host stands the button that brings a hidden bar back on it, which is what keeps the two in one column at every width.

**The trail is shortened, never scrolled.** `ShrinkingTrail` (`lib/views/components/`) lays the crumbs out, and when they do not fit it takes room from every crumb but the last, the widest first, so "Python" stays whole while a long group name gets its ellipsis. The last crumb is where the reader is: it gives up room only once the others are down to a letter and an ellipsis, and below that crumbs leave from the front, divider and all, until what is left fits. It is a render object and not a `Row` of `Flexible`s, because a flex layout splits the free width evenly and does not pass on what a short child leaves unused: the long crumb was cut while the row still had room for it. The crumbs are the header's own `_Crumb`, drawn from forui's `FBreadcrumbStyle`. forui's `FBreadcrumbItem` only works inside an `FBreadcrumb`, and that is a plain `Row`.

**A crumb that was cut says its whole name on hover.** `ShortenedTip` (`lib/views/components/`) is a `HoverTip` that opens only while a text under it is cut: a one-line text narrower than its line, which is the trail's own test for having shortened it, or a wrapped text past its `maxLines`, which is how a catalog tile cuts its title. The two are told apart because a wrapped text is always narrower than its one long line. It asks on the hover instead of keeping the answer, so a window that grows needs no rebuild to take the tip away. A crumb that fits opens none, and the tip is not in the crumb's semantics: a cut `Text` still reads out the whole label.

**A lesson's trail names its group**, between the subject and the lesson, when the lesson has one. A group is a heading in the catalog and not a screen, so that crumb opens the catalog at the heading (see *Anchors*).

**The version is named once, on the home screen**, beside the mark and not inside the app crumb — the crumb is the app's *name*, and a version tacked onto it would be read out as part of it on every screen. The two are set at different sizes on one line, so the trail aligns them on their **baseline**; centring their boxes leaves the smaller one sitting low. `appVersion` (`lib/app_info.dart`) reads it back out of the running build through `package_info_plus`, so it cannot drift from `pubspec.yaml` — on the web that is a fetch of the `version.json` the build writes beside `index.html`, same origin and so untouched by cross-origin isolation. `main()` awaits `loadPackageInfo()`, which registers the `PackageInfo` in GetIt; it is **not** an initialization step, because that screen's failures are fatal and a version string is not worth failing a start over. It is null when there is nothing to show — the plugin answers empty strings rather than throwing when `version.json` is missing, and a widget test registers nothing at all — and the bar then omits it.

`HeaderIconButton` is the icon button all three are — the cog, and the two that hide and show the bar. Not `AppButton.icon`, which is padded `19 × 19` to stand beside a line of text and is far too big for a 76px bar.

**The mark in the bar is an easter egg.** Pressed, `PlayfulAppLogo` plays a random `LogoTrick`, so a new trick is a new case of that enum and nothing else. It gives nothing away: no pointer cursor, no tab stop, no semantics. Every trick MUST start and end on `LogoPose.rest`, and `test/views/playful_app_logo_test.dart` holds that for every case. The initialization screen's mark winks once, when everything is in, and the screen goes on only once the eye is open again (`WinkingAppLogo`, which calls `InitializationScreenController.proceed`; see *Three loading states*). The splash in `web/index.html` stays still, so the wink is the first thing the face does. The mark everywhere else stays still.

### Introductions

The first time a screen is opened in this browser, it can dim the window and light up one part at a time, with a tip under each explaining what it does. **`AppHeaderHost` runs every introduction**, including ones about a screen's own page, because the bar's introduction starts by bringing the bar out of zen mode and only the host can do that. The code is the host's `_HostTour` mixin, in `app_header_host_tour.dart`. That file is a `part` of the host so the mixin can reach its private state, and the host only calls `_followTour` and reports the bar through three `_tourBar…` hooks. A screen asks for them through its header:

- `AppHeaderConfig.barTourId` introduces the bar: the show-bar button, every crumb with an `AppCrumb.tip`, `trailing` when it has a `trailingTip`, the cog, and the hide button. The lesson screen uses `'lesson'`.
- `AppHeaderConfig.tours` holds `AppTour`s about the page, offered for as long as the header builder offers them. The lesson screen offers `'deep-dive'` while an optional step is showing, and it points at the whole `OptionalStepBanner` row. A page's parts are named by an enum of their own, as the bar's are by `AppHeaderPart`: `LessonTourPart` for the lesson screen.

A part is found by wrapping it in `TourTarget(id: ...)`, anywhere under the host. **Not a `GlobalKey`**: `FadeThrough` and `StepTransition` keep the outgoing copy mounted while the new one comes in, and two copies of one key throw. With a registry, the later copy wins. A stop whose target is not on screen is skipped.

Rules it keeps:

- **What is lit is live.** `SpotlightScrim` cuts the hole out of its paint *and* its hit test with one `ClipPath`, so a press in the hole reaches the real control and a press anywhere else is swallowed. The show-bar stop has no Next: the reader presses the button. A lit control that navigates ends the introduction, because the screen stops offering it.
- **The hole is a squircle**, which is why this is not showcaseview or tutorial_coach_mark: both only cut a rounded rectangle or a circle. The path is even-odd, **not `Path.combine`**, which came out as the whole rectangle on the web build, so there was nothing lit and nothing to press. The widget tests passed either way. Check a change to the scrim in a browser.
- **Seen is recorded however it ends**: Klaar, Overslaan, Escape, the hide button, or a lit control that navigated. `TourStore` keeps it in `shared_preferences` under `tours.seen`, swallows its failures like `ProgressStore` does, and is loaded by the initialization screen. Clearing progress does **not** clear it.
- The page is out of the focus and semantics trees while one runs. The tip takes the keyboard (`AppButton.autofocus`) and is a `FocusTraversalGroup` rather than a `FocusScope`, so Tab can still reach the show-bar button that the first stop asks for.

**When you build something new that a student has to find or understand, consider giving it a stop.** That means a `TourTarget` on the part and a stop in an existing tour, or a new `AppTour` with an id of its own. A new id reaches every student, including ones who have seen the others. Adding a stop to a tour they have already seen reaches only new students.

### Debug menu

**Alt+B** (Option+B on a Mac) opens `DebugMenu`, **in release builds too**, so a simulation can be shown on the deployed site. The app is open source, so the key hides nothing. In a debug build the cog offers it as well, through `DebugMenu.opener`. It is a `HardwareKeyboard` handler rather than `Shortcuts`, because on a freshly opened page nothing has focus, and it matches the *physical* B because Option+B types "∫". **Alt and no other modifier**: ⌘⌥B is Chrome's bookmark manager on a Mac, and Alt+Shift+B moves to the bookmarks bar in Chrome and Edge. Firefox on Windows and Linux uses Alt+B as a menu access key (Bookmarks in English, *Bestand* in Dutch), and skips it because the page has already handled it.

It offers five things:

- "Colour vision" draws the whole window as protanopia, deuteranopia, tritanopia or achromatopsia (see below).
- "Show tips again" clears `TourStore`. The current screen then offers its introduction again right away.
- "Ask again" clears `MobileBrowserWarning`, which shows at the next start and only in a mobile browser.
- "Throw test error" throws an error nothing catches, only in a build that reports errors (see *Error reporting*).
- "Feature toggles" switches each toggle the course names, and all of them off at once (see *Feature toggles*).

Put new developer tools here too, each as a `_DebugRow` of one line. The panel scrolls, because the toggles are as many as the course names. Its text is not localized: a student only meets it by knowing the key.

**The colour vision simulation is `ColorVisionFilter`** (`lib/views/components/`), around `AppHeaderHost` in the shell, so the bar, the dialogs and the introduction are drawn with it too. The three dichromacies are Machado et al.'s matrices at full severity. They work on linear RGB, so they sit between `ColorFilter.srgbToLinearGamma` and `linearToSrgbGamma`. Achromatopsia is Rec. 709 luminance. `ColorVisionController` holds the choice and does not persist it, so a reload draws the real colours. The filter is a render object that pushes its layers only while a simulation is on, **not a `ColorFiltered` put in and taken out**: changing the shape of the tree rebuilds everything under it, the router's pages and the debug dialog the simulation was picked in included. Off, it composites nothing, which is what a release build gets.

### Feature toggles

**There are two kinds, and they share one set of names.**

- **Dynamic** toggles are named by the course: `feature:` in a lesson's document-level metadata, `{#week-5 feature=bestanden}` on a group's heading in the contents file. `docs/lesson-format.md` is the author-facing spec. There is no list of them in the app; `Course.features` is whatever the files use.
- **Static** toggles are declared in code, for a part of the app that is not ready to be shown: a `StaticFeatureToggle` in `kStaticFeatureToggles` (`lib/services/feature_toggles.dart`), and a `FeatureGate` (`lib/views/components/`) around what it hides. `tkinterFeature` is the first. It hides the Tkinter page's card, the cog's *Code-editor* item and the about screen's Tkinter row, and reads through `tkinterShown`, which is also false in a build without the VM image. A getter rather than a gate, because the cog's menu takes item groups and the catalog spaces its cards by which are there.

One set of names means one switch: a static `tkinter` and a lesson that says `feature: tkinter` are hidden and shown together. The debug menu offers both kinds in one list, `featureToggleNames`. Every toggle is off until it is switched on, in debug builds too.

`FeatureToggles` (`lib/services/`) holds which are on. It is persisted per browser under `features.enabled`, swallows its failures like `TourStore`, and is loaded by the initialization screen, before the first catalog. Clearing progress does not clear it.

Things that are easy to get wrong:

- **`Course` keeps every lesson.** A toggle changes while the app runs, so nothing is dropped at parse time the way a step for an unready `runtime` is. What is shown is derived: `visibleCourse` for the subject picker and the catalog, `visibleLessonAfter` for "Volgende les". Both read the toggles, so an `Observer` that calls them follows a switch in the debug menu. That is why the outer builders of both screens are `Observer`s, with `warnWhenNoObservables: false`: a course that names no toggle reads none.
- **A `FeatureGate` does not build what it hides**, and nothing guards a route yet. A screen behind a static toggle is still reached by its address, as a hidden lesson is.
- **Hidden is not listed, and nothing more.** An address still opens a hidden lesson, and from there "Volgende les" leads to the next lesson that is shown. Progress and drafts load from the whole course, so a lesson that comes back brings its ticks.
- **Both translations must agree**, a lesson's `feature` as much as its `id`, and every contents file must give a group the same one. `Course.fromFiles` refuses a mismatch, because one language would list a lesson the other hides.
- **A `feature` on a step is refused**, like `group` on a lesson, so it cannot sit in a file doing nothing.

### Motion

**A duration reaches an animated widget through `context.motion(duration)`**, which returns `Duration.zero` when `MediaQueryData.disableAnimations` is set — on the web, `prefers-reduced-motion: reduce`. The animation still ends where it was going, it just gets there in one frame. `ConfettiBurst`, which draws nothing at all under that flag, is the one thing that opts out of animating rather than shortening.

Two swaps are animated, and both are their own widget for the reason above:

- `FadeThrough` (`lib/views/components/`) — the trail and the chrome beside the cog. The old fades out and *then* the new fades in, over one `AnimatedSwitcher` controller split by two `Interval`s. Not a crossfade: two lines of text at half opacity on top of each other read as a rendering fault rather than as a change.
- `StepTransition` (`lib/views/lesson_screen/components/`) — one step of a lesson out, the next in, in the direction the student is travelling. The direction is `LessonScreenViewModel.forward`, set at the moment of the move: by the time the view rebuilds, the step being left is already gone. Note what it leans on — `AnimatedSwitcher` gives the same `transitionBuilder` both children and says nothing about which is which, so the builder compares the child it is handed against the current one by key, and **must be a new closure on every build** or the outgoing step keeps the transition it arrived with.

### State management

MobX for all reactive state. `@readonly` generates a private field plus a public getter; mutations go in `@action` methods. Wrap anything that should rebuild in `Observer` from `flutter_mobx`.

**An `Observer` only tracks what is read during its own build.** A `LayoutBuilder`, `Builder` with a deferred callback, or anything else whose closure runs at *layout* time reads observables outside that window, so the `Observer` never re-runs and the screen silently stops updating — no error, just a button that appears to do nothing. Prefer `MediaQuery.sizeOf(context)` for responsive decisions: it answers during build and rebuilds on change. If a `LayoutBuilder` is genuinely needed, put an `Observer` *inside* it.

App-wide state is a plain MobX store registered in GetIt from `setupServices()` in `main.dart` — `LocaleController` is the example. **`setupServices()` does no I/O**: work that can fail or take time belongs to `InitializationScreen`, which can show progress and offer a retry.

Three things are awaited by `main()` before `runApp` instead. `LocaleController.load()` and `ThemeModeController.load()` have to be: the initialization screen is itself themed and localized, so reading either there would paint it wrong and flip. `loadPackageInfo()` (see *The bar*) does not have to be, but it is one small same-origin file and reading it here spares the home screen a loading state. All three swallow their own failure and fall back, so none has anything a retry could fix.

`Course` is deliberately registered *by* the initialization screen rather than in `main`, so reaching any screen past it guarantees every lesson is parsed and no later screen needs a loading state for it.

### Code generation

Four generators are active:

- **MobX** — `*.g.dart` for ViewModels and stores
- **freezed** — `*.freezed.dart` / `*.g.dart` for data classes
- **auto_route** — `app_router.gr.dart` for the route table
- **theme_tailor** — `app_theme.tailor.dart` for the theme extension (`copyWith` / `lerp` / equality)

Generated files are excluded from linting (`analysis_options.yaml`) and must never be edited by hand.

### UI library

**forui** for every widget, plus its bundled Lucide icons. **No Material, no Cupertino, no fluent_ui.** The shell is a `WidgetsApp.router` rather than a `MaterialApp` precisely so a stray Material widget looks wrong instead of quietly theming itself.

**A hint that opens on a press is an `FPopover`, never an `FTooltip`.** forui's tooltip is hover-and-long-press by design: its hover branch wraps the child in a `Listener` that hides the tip on *every* pointer down, so a tap opens and closes it within one gesture and nothing is ever read. A popover adds no gesture of its own, which is why `SettingsMenu` says the popover "does not open itself" — the trigger is an ordinary `FTappable`, and that is also what puts it in the tab order and makes Enter work. `HintMark` (`lib/views/components/`) is that question mark: beside the catalog's *Verdieping* heading and beside the same word as a badge on a step. A `MouseRegion` around its trigger opens it on hover with **no dwell time**, because forui's tooltip waits out half a second and on a mark that size that reads as nothing happening. Its press is `show` and not `toggle`: the pointer is already inside by the time a click lands, so toggling would close what the hover opened.

**The other half of that rule**: a hint that belongs to hover *is* an `FTooltip`, and the pointer-down that rules it out above is exactly what it wants. `HoverTip` (`lib/views/components/`) is that tooltip. `StepProgressBar` names each step with one, and the back chevron of a step names where it goes through `AppButton.tip`: the press under that hover is a move to another step, so the tip has to be gone by the time the new one is drawn. Both name a step through `StepProgressBar.tipFor`, so one step has one name. "Volgende" carries none. Two things `HoverTip` sets:

- **No dwell time**, for the reason `HintMark` gives.
- **No long press.** forui opens a tooltip on a long press by wrapping the child in a recogniser, which wins the arena from the child's own tap after half a second. A button held down a moment too long showed its tip and never fired.

`AppButton` also hands its tip to a screen reader as the button's tooltip, unless the tip only repeats the label.

**forui's floating surfaces are reshaped in `buildAppTheme()`.** forui draws a popover, a menu's item group, an item's hover fill and a tooltip with a `RoundedSuperellipseBorder` of its own, which is a different curve from `squircle()`. `test/views/app_header_test.dart` opens the cog's menu, hovers an item and fails on any `RoundedSuperellipseBorder` it finds, and `test/views/hover_tip_test.dart` holds a tooltip's shape. A tooltip takes a tighter radius than a popover: one line of a tip is under 30px tall, and a squircle bows inward past half the shortest side. A forui widget that floats and is new to the app SHOULD be checked the same way.

**Every dialog is opened by `showAppDialog` and laid out by `AppDialog`** (`lib/views/components/app_dialog.dart`). The first hangs it off `OverlayHost`'s Navigator, so the barrier covers the bar as well as the page. The second sets the title, the body and the buttons, which stand in an `AppButtonRow` at the end edge. Its column stretches, because a `Wrap` is only as wide as its buttons: in a column that does not stretch it, `WrapAlignment.end` has no room to move them, and they sat at the start edge under any text wider than they were. `test/views/app_dialog_test.dart` holds that with the app's real fonts.

**A dialog that scrolls says so.** What scrolls is a `ScrollCard` (`lib/views/components/`): a card that cuts its content off at its own rounded edge, shades the edge that has more beyond it (`ScrollShadows`) and keeps its thumb showing at rest, because text cut off between two lines looks complete. On the code surface the content fades into the card instead, since a shadow does not show on dark. The content is the one part of an `AppDialog` that gives way to a short window, so text that is long enough to need room goes in the card too, as on the console's help, and not in `body`.

**Every rounded corner is a squircle, and a text field is the one control that cannot be given one.** forui types a field's border as Material's `InputBorder`, whose concrete forms draw a plain rounded rectangle, so `squircle()` cannot reach it. `SquircleInputBorder` (`lib/theme/`) is an `InputBorder` subclass that hands every question to the real squircle; `PredictionField` restates all five of forui's border states with it, because the border carries its own colour and replacing one replaces the colour with it.

The one Material import in the codebase is `package:material_ui/material_ui.dart show ThemeExtension` in `lib/theme/app_theme.dart` — forui types its extension map against that class, and Flutter 3.47's `package:flutter/material.dart` declares a *different* one. Importing the wrong `ThemeExtension` fails with a type error that does not mention either package.

### Theming

```text
lib/theme/theme.dart                      # buildAppTheme() -> FThemeData
lib/theme/app_theme.dart                  # the app's own tokens (theme_tailor), context.appTheme
lib/theme/shape_metrics.dart              # corner radii + the FBorderRadius scale
lib/theme/presets/app_color_preset.dart   # the colour presets
lib/theme/presets/neobrutalism_palette.dart  # the unbranded preset's colours
lib/theme/presets/thuas_palette.dart      # De Haagse Hogeschool's house style, transcribed
```

**A preset changes colour and nothing else.** The type scale, the two font families and the radii belong to the app and are shared by every preset. `AppColorPreset.neutral` is the default and is what the app looks like unbranded; `AppColorPreset.thuas` is a skin. Adding a preset means adding a case to `AppColorPreset.resolve()` and nothing else.

**The neutral preset is neobrutalism *as a palette only*** — the flat yellow accent, the cream page, the near-black ink. None of the movement's other devices: no thick outlines, no hard offset shadows. Borrowing one would put it in the shared metrics, where every preset would inherit it.

**Every preset has both brightnesses.** `resolve({brightness})` returns the scheme; `buildAppTheme({preset, brightness})` builds it. The mode itself is `ThemeModeController` (`lib/services/`) — system/light/dark, persisted in `shared_preferences` like progress, and swallowing its failures the same way. It is one of the three things `main()` awaits before `runApp` (see *State management*), because the initialization screen is itself themed and would otherwise paint light and flip.

`AppThemeMode.brightnessFor(platform)` is the whole decision, so it can be tested without a widget tree. The shell reads it in `_ThemedBody`, which exists as a widget rather than a closure so its `Observer` runs in a real build and so it can see the `MediaQuery` that `WidgetsApp` installs below the state above it.

**A fill token is not a text token.** `primary` is a fill: the neutral accent is 1.2:1 on the page and the THUAS green 2.63:1 on white, so neither can carry text. That is why `link` is a role of its own in `AppSemanticColors` rather than reusing `primary` — and why prose links are underlined as well as coloured. The THUAS house style has *no* colour that works as link text on white; it uses the mid grey, and the underline is what makes it a link.

`test/theme/theme_test.dart` asserts every pairing across **all four** schemes (2 presets × 2 brightnesses). `test/theme/palette_test.dart` renders a real catalog tile and asserts that more than 1% of its pixels carry colour — the tripwire for a preset silently coming out greyscale, which is what shipped when the app was pinned to forui's neutral scheme and measured 0.00%.

**Every rounded corner is a squircle.** Draw one with `squircle(radius)` from `shape_metrics.dart` and a `ShapeDecoration` — never `BoxDecoration.borderRadius`, which can only make a plain rounded rectangle. `kSquircleScale` converts the design's CSS radii to `ContinuousRectangleBorder`'s tighter curve; it is the one number to turn if corners look wrong. A continuous rectangle does **not** clamp an over-large radius — past half the shortest side it bows inward — so a small square tile uses `squircleOf(radius, size:)` instead.

The **one** exception is the tick on a finished catalog tile (`CompletedBadge`), which is a `CircleBorder`. The rule is about corners, and that badge is a lamp: a flat disc lit by three stacked shadows — a tight core, a halo and a wide bloom, all at zero offset — because one shadow cannot make a glow. A small blur draws a ring around the badge and a large one thins the colour to nothing, most visibly on the dark card, where a translucent green barely lifts the surface under it. It carries no outline: one was tried and read as a second shape rather than as a crisper edge. It is not the neobrutalist hard offset shadow the preset leaves out either — that is a device of the whole style and would live in the shared metrics.

Every number that badge draws with — its size, the tick and each layer of the glow — is a constant at the top of `CompletedBadge`, because the look is a matter of taste and nothing else reads them. The widget tests hold the *shape* of the thing (a circle, no outline, a glow that spreads and fades outward) and pin none of the values, so tuning one does not turn the suite red.

`progressComplete` is that lamp's colour, and no longer an alias of `success`: "your check passed" and "this is done" are different things, and a deeper green went muddy under a glow. The neutral preset lights it with `NeobrutalismPalette.complete`; THUAS keeps its corporate green, because its house style has no vivid one and a preset may not invent colours it does not own.

`AppButton` exists rather than forui's `FButton` because the design's padding is `38 × 19` against forui's `10 × 11`, and forui fills a button with a `BoxDecoration` that cannot carry a squircle. It is built on forui's `FTappable`, so hover, focus and button semantics still come from the framework.

Its three tones are a rank: `primary` carries the reader forward, `neutral` is the quieter one beside it, `outline` is quieter still and is what a step *back* takes. An outlined button has no fill to fade, so its hover and press tint the page with `neutralButton` instead. Its edge and its label are drawn in that same colour — the one `neutral` is *filled* with, so the two read as one button with and without its fill — rather than in the quiet `border` a card takes, which is too faint against the cream page to say "this is a control". `AppButtonTone.outline` is one button's own edge and **not** the neobrutalist outline the preset leaves out, which goes round everything and would live in the shared metrics.

**A button is a slab, and the body ink is a line.** `neutral` used to be filled with the page's `foreground`; on the light neutral preset that is the near-black `inkLight`, which at 38 × 19 read as a hole punched in the cream rather than as a control. It is now `AppSemanticColors.neutralButton`, a role of its own, so a preset can want its buttons softer than its prose without softening the prose with them. The neutral preset does — `NeobrutalismPalette.controlLight`, the darkest step of the warm grey `inkMutedLight` belongs to — and it is a *light*-scheme answer only: an off-white slab on a dark page is quiet already, so the dark scheme still fills with `inkDark`, and THUAS with a `corporateGrey` that was never black to begin with. The token is a text colour as well as a fill, because the outlined tone has no fill to carry a label, so `theme_test` holds it against the page and a card on top of its own foreground. `AppButton.icon` is the icon-only form; it **requires** a `semanticsLabel`, because there is no text in it to fall back on.

**A button is the same height whatever is in it** — a 20px glyph, a line of text whose height is the font's, or both. `AppButton` settles that in itself: its content is a `Stack` over two invisible, zero-wide children, an empty `Text` in the label's own style and a `SizedBox(height: _iconSize)`, so every button comes out `max(line height, glyph)` tall. Neither is a number stated there — the first is asked of the font through the ambient `DefaultTextStyle`, the second is the app's own icon size — which is the whole point: padding the glyph to match would be guessing at Lexend's metrics and would drift the moment the type scale moved.

That is what lets `AppButtonRow` be a **`Wrap`**, so a row of buttons breaks into lines instead of overflowing. It was an `IntrinsicHeight` around a `Row`, which equalised the heights but could only ever do it for one line — and a lesson's three controls (back, Run, Volgende) want ~490px against the 462px the narrower of its two columns has at `lg`, which is the yellow overflow bars over the last button.

**A button must not resize when it starts working.** `AppButton.busy` keeps the label laid out (`Visibility.maintain`) and puts the spinner in a `Positioned.fill`, so neither the label swap nor the spinner's own height can change the button's size. Swapping the label for a shorter "Bezig…" makes the button jump the moment it is pressed, which reads as the layout breaking.

**forui defaults every tappable's cursor to `MouseCursor.defer`**, which on the web leaves the ordinary arrow over buttons, breadcrumb crumbs and the settings cog. `buildAppTheme()` sets it once on `FStyle.tappableStyle`; every widget style inherits from that one, so nothing needs a `MouseRegion` of its own.

Responsive layout goes through **`context.theme.breakpoints`**, which are Tailwind's. The lesson's two-column step stacks below `lg` (1024) and scrolls as one page there; side by side each column scrolls on its own, so reading down the prose leaves the editor and its output where they are. Note that `Expanded(flex:)` is an *integer* ratio against a default of 1 — `flex: 11` is an 11:1 split, not 1:1.1, which is how the prose column once came out one word wide.

`AppSemanticColors` names the roles forui has no slot for — `warning`, `success`, the code editor's surface, the progress bar. **Write a colour there, not inline in a widget**, and read it through `context.appTheme.colors`. Each `*Foreground` is stated next to its fill on purpose: the THUAS corporate green reaches only 2.63:1 against white, so picking a foreground at the call site is exactly how a screen ends up illegible. `test/theme/theme_test.dart` asserts every pairing clears WCAG AA in every preset — **add a pair there when you add a colour.**

`context.appTheme` falls back to the neutral preset when the ambient theme carries no extension (a widget test that builds its own `FTheme`), so it never null-checks.

**Emoji are Noto Color Emoji, bundled, and never the platform's.** `kEmojiFontFamily` is the last entry of `fontFamilyFallback` on every style in `AppTextStyles` and on both of forui's typefaces, so it is reached only for a glyph Fredoka, Lexend and JetBrains Mono cannot draw. It is a fallback and never a `fontFamily`. Left to the platform the same lesson would show Apple's emoji on a Mac, Google's on Android and Microsoft's on Windows; on the web the engine downloads Noto from `fonts.gstatic.com` per student, on demand, which is the request the other three fonts were bundled to avoid. The COLRv1 build ships rather than the CBDT one — vector, and half the size. Every lesson step carries an `emoji` in its metadata. A lesson carries an `icon` instead (see *Illustrations*). See `docs/lesson-format.md`.

**Illustrations.** A lesson names a picture from the app's own set with `icon:`, and `CourseIcon` (`lib/services/lessons/`, plain Dart because the parser runs on the Dart VM) is that set: one SVG per case under `assets/icons/`, named by its key. A subject's icon is a case in `subjectIcon()` beside `subjectLabel()`, because its contents files say nothing about the subject itself. The set belongs to the app, which is open source, so a course can pick from it and nothing more.

`DuotoneIcon` (`lib/views/components/`) is the workaround widget that draws one, in `illustrationLine` and `illustrationFill`:

- **Every icon is in one file, compiled at build time.** `bin/bundle_icons.dart` is the asset transformer on `assets/icons.bin`, the way `bin/bundle_lessons.dart` is on the course: it compiles the SVG of every `CourseIcon` with `vector_graphics_compiler`, used as a library, into one `IconBundle` (`lib/services/icons/`). So the app makes one request for all of them and has no XML parser at runtime; the SVGs themselves are not assets. The committed `assets/icons.bin` is an empty placeholder. The bundle is fetched by the first icon drawn, after the first frame, so it is not part of a cold start.
- **The compiler's three optimizers are off.** All of them need Skia's path ops through FFI, which a transformer does not load, and the overdraw pass cuts fills out from under each other, which leaves seams once the colours change.
- **`IconBundle.decode` copies each icon into a buffer of its own.** vector_graphics views a picture's floats in place, which needs them aligned to the start of a buffer, and in the bundle an icon starts wherever the one before it ended. Handed a view instead, every icon decodes to nothing, silently.
- **A compiled picture keeps its colours**, and one `ColorFilter` over the whole of it is all that can change them; `ColorMapper` and `SvgTheme` reach only SVG parsed at runtime. So every file is drawn in two keys, pure red for the outline and pure green for the shapes inside it, and one `ColorFilter.matrix` sends red to the line colour and green to the fill. Skia applies the matrix to unpremultiplied colour, so an antialiased edge comes out as the same blend of the two theme colours. `test/views/duotone_icon_test.dart` holds every file to the two keys, the files to `CourseIcon`, and renders the result in all four schemes.
- **An icon never stands on `primary`**, only on the page or a card: in a dark scheme its line is the accent itself, because an off-white line over a full yellow fill barely parted from it. Its fill there is the accent at 20% over the page. The line clears 3:1 against its fill, the page and a card, which `theme_test` holds.
- **A picture that fails to load is an empty box and no error**, which is why the test holds the names, the files and the bundle to each other, and draws them. Check a change in a browser: the tests draw on the CPU, not on CanvasKit.

Fonts are **bundled** under `assets/fonts/`, not fetched at runtime — a font request per student to a third party is both a privacy question and a flash of unstyled text on every cold load. Each family's `OFL-<family>.txt` sits beside its files; a new font brings its licence text with it.

**Fredoka and Lexend are variable fonts, one file each**, the unmodified `Fredoka[wdth,wght].ttf` and `Lexend[wght].ttf` of google/fonts under a name without brackets. A `FontWeight` sets the `wght` axis, so `pubspec.yaml` states no weight for either: a weight there would pin the file to that one. Fredoka's own default is 300, which no style asks for, so a weight that stopped reaching the axis would show as every heading going light. `test/theme/variable_font_test.dart` holds that each weight the app uses is a different drawing. The web engine downloads every font in the manifest before the first frame, which is why nine files became two.

**`pubspec.yaml` bundles a family called `Roboto` that is the Lexend file.** The app draws nothing in Roboto. Flutter's web engine downloads it from `fonts.gstatic.com` on every cold start unless the manifest has a family by that name, and uses it for text that names no family. The same test holds the alias.

**A character none of the bundled fonts has is a request to Google.** The engine fetches a Noto font for it from `fonts.gstatic.com` the first time it is drawn. That is why the console's hint says "Pijl-omhoog" and not `↑`, which Lexend lacks. Check a new symbol in interface text against the font it is set in.

**The code face is JetBrains Mono NL, the build with no ligatures.** The ordinary build draws `!=` as a struck-through equals sign and `>=` as `≥`, and a student who has just been told to type two characters cannot find either on a keyboard. The font is the only place to turn them off: `FontFeature.disable('calt')` on a `TextStyle` reaches the prose and the read-only cards, but `re_editor` builds its own style and passes no `fontFeatures` on, so the editor, where the typing happens, would have kept them. The files are the unmodified `JetBrainsMonoNL-Regular.ttf` and `-Medium.ttf` of the upstream release, and they stay two static files: upstream's variable build is the one with ligatures. `test/theme/code_font_test.dart` draws each operator whole and a character at a time and fails when the two differ.

### Running it

`.vscode/launch.json` holds the run configurations; the app is web-only, so they all are.

Every one of them serves `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp` via `--web-header`, which is what makes the page **cross-origin isolated** and so gives it `SharedArrayBuffer`, WebAssembly threads and `Atomics.wait`. `flutter run` has no dedicated switch for this.

Two things follow:

- `require-corp` makes the browser refuse any cross-origin subresource that does not opt in with its own CORP/CORS header. Everything the app loads is bundled — the fonts included, which is part of why they were bundled, and CanvasKit, which `flutter build web` points at `www.gstatic.com` unless it is given `--no-web-resources-cdn` — so nothing is at risk today. **Add a CDN script or a remote font and it will fail to load under these configurations only.** The "no isolation" configuration exists to rule the headers in or out when something stops loading.
- `flutter build web` serves nothing, so a **deployed** build is only isolated if its host sets the same two headers. Isolation is a property of the response, not of the bundle.

GitHub Pages cannot send a header, and the interactive console *does* depend on `SharedArrayBuffer`, so `web/coi-serviceworker.js` re-issues every response with the two headers from a service worker. It is a **no-op wherever they already arrive** — it returns early while `crossOriginIsolated` is true, which is every configuration above — so it does nothing at all from the IDE.

Two things about it:

- It is **vendored and stays unmodified**. The app's own adjustments go in the two `<script>` blocks around it in `web/index.html`. One of those is a workaround: upstream reloads only when it finds an already-*active* worker, and on a first visit the registration resolves while the worker is still installing — so the page would stay un-isolated until someone reloaded by hand. Waiting on `serviceWorker.ready` and reloading once is the fix.
- `credentialless` is forced off, so the deployed site lands on exactly the `require-corp` the dev server serves. A subresource that breaks in only one of the two environments is the whole reason to keep them identical.

No service worker means no console — private browsing, storage disabled, no https. `PythonRepl.isSupported` reports that and the screen says so rather than disappearing.

### Addresses

```text
/                                              the subject picker
/licenses                                      the licences of the app and of what it ships
/about                                         which build this is, and what it is made of
/learn-python                                  that subject's lessons
/learn-python?group=week-1                     ... scrolled to that group, which lights up
/learn-python?lesson=uitvoer                   ... scrolled to that lesson's card
/learn-python/uitvoer                          resume: wherever you left off
/learn-python/uitvoer/zelf-printen             one step, named by its section id
/learn-python/repl                             the interactive console
/learn-python/microbit                         a program of your own, on a board
/learn-python/microbit-repl                    MicroPython's own prompt, on a board
/learn-python/microbit/dobbelsteen             a project, on a board or in the VM
/learn-python/tkinter                          a program with windows, in the VM
/editor-settings                               the code editor settings, from the cog
```

`repl`, `microbit`, `microbit-repl` and `tkinter` sit where a lesson id goes, so all four are **reserved**: a lesson must not use any of them, and `test/content/lessons_test.dart` holds that. Their routes are declared *above* the lesson routes, the same arrangement as `/initialization` above the subject catch-all, because auto_route would otherwise read them as lessons by those names.

**The two micro:bit addresses are two screens, not two views of one**, because they want opposite things of a board: a prompt has to interrupt whatever is running, and a program has to be left alone to run. `MicrobitSessionController.interrupt` is that difference and the only one — both screens share a view model and a controller (`lib/views/components/microbit/`), and differ in their View. A screen that lets the program run also expects no MicroPython banner, since the board only prints one on its way into the prompt.

**A project has no step in its address.** It shows every task up to the one in front of the student, and which one that is comes from progress, not from the address. It sits under `microbit` because the first projects were programs for a board, and a project on the machine (`runtime: tkinter`) has the same address. Three segments long it would otherwise read as a lesson step, so it is declared above that route. A project's lesson address, typed or bookmarked, still reaches the lesson route: `ProjectGuard` (`lib/routing/`) sends it on. Everything the app builds itself goes through `openingRoute()`, which picks the right one.

The step is a **`LessonSection.id`, never a position** — the same reason progress keys on it. A pasted or bookmarked link still opens the step it named after the author reorders the lesson, and an id the lesson no longer has resolves like the bare form rather than showing nothing.

**A page may appear in the route table only once.** auto_route matches on an exact segment count, so the bare lesson address cannot be an optional segment on the route below — and a second `AutoRoute` for the same page throws `Route name must be unique` **when the router is first built**, which is after codegen and after `flutter build web` have both passed. It therefore redirects to the reserved section id `resume`, which no lesson may use; the screen already treats an unknown id as "resume" and rewrites the address to the section it lands on.

`test/routing/app_router_test.dart` builds the router, which is the only place that validation happens. Add to it when you touch the table — a green analyze and a green build prove nothing here.

`/:subjectSlug` is a catch-all, so `/initialization`, `/licenses`, `/about` and `/editor-settings` must stay declared above it.

### The catalog

**A subject's lessons are tiles of 3:4 in a grid**, as wide as a lesson's two-column step (1120) and four to a row there. `TileGrid` (`lib/views/catalog_screen/components/`) puts as many in a row as stay 240 wide, down to one. A `CatalogTile` holds the lesson's icon on a panel the colour of the page, over its title, its subtitle and how far in the student is, and its height comes from `CatalogTile.heightFor`:

- **The text never gives way.** Its block is as tall as two lines of title and three of subtitle, measured with a `TextPainter` at the reader's own text size, and the panel takes what the 3:4 shape leaves. Text that runs longer ends in an ellipsis. Scaled up far enough, the tile grows taller than 3:4 rather than cutting a line.
- **A cut text says itself in full** on hover and when the keyboard is on the tile: the tile is wrapped in a `ShortenedTip`, which asks the clamp whether it cut anything.
- **The *Extra* pages are tiles too**, with their glyph (`>_`, or an emoji) on the panel in place of an icon.

The home screen keeps rows, one per subject: `SubjectCard` (`lib/views/subjects_screen/components/`). Both wear `BevelledCard` (`lib/views/components/`), the card that rises off its collar on hover and sinks into it on press.

### Anchors

**The catalog's address can name a place on it**: `?group=<LessonGroup.id>` or `?lesson=<Lesson.id>`. The catalog scrolls there and lights it up, with a ring in the text colour that runs outward from the part and fades, twice. A group lights its heading and every card under it. Ids and never positions or titles, for the reason progress keys on them. An id the course does not have names nothing, and the catalog opens at its top. Given both, the lesson wins.

It is a query parameter and not a second `#`. The route already sits behind the hash, and a `#` inside a fragment is not valid in a URL, so a chat app is free to mangle one. `BootstrapGuard` carries the query over the bootstrap. **The anchor stays in the address**, as an anchor on the web does: a reload scrolls there again.

Three things hold it together:

- **The view reads the anchor off the screen's own widget at every build** (`context.widget as CatalogScreen`). auto_route hands a page that only changed its query new arguments in place, which is what a link pasted into a tab with the catalog open does. `ScreenBase` makes the view model once, so nothing else would see it, and `base/` stays closed. A change *to* an anchor is a request. A change to none is not, so a reader who navigates back keeps their place.
- **`catalogRoute()` gives a route with an anchor a `UniqueKey`.** Arguments that did not change move nothing, so a group crumb pressed a second time would do nothing. Every `CatalogRoute` that carries an anchor MUST be built there. Without an anchor there is no key, and the catalog a reader returns to is the one they left.
- **Every tile is built, on screen or not**: a run is a `TileGrid`, rows in a box, not a sliver grid. `AnchorTarget` scrolls by `getOffsetToReveal`, which adds up scroll extents, and a lazy grid only estimates the rows it has not laid out. The same call already leaves room for the pinned slivers ahead of a part, the `BarClearanceSliver` and the stuck heading, which is why a tile lands under its heading and not behind it. A tile in a group's first row comes to rest with the heading in its own spot, a tile's clearance below where it pins.

`CatalogAnchorScope` owns the one `AnimationController` the ring runs on, so a heading and its cards pulse as one. An `AnchorTarget` wraps each part: it scrolls itself there, says it has arrived, and draws from that clock. The ring is the text colour because the accent cannot be the signal: the neutral yellow is 1.2:1 on the page. For a reader who asked for less motion the page jumps and one ring stands still for a moment, which is why the ring's duration does not go through `context.motion`.

**A right click on a lesson tile or a group heading opens `CopyLinkMenu`**: the cog's kind of menu with one item, which copies `catalogAddress()` and says "Gekopieerd" for a second before it closes. Shift+F10 and the menu key open it on a tile with the focus, and a screen reader gets the copy as a custom action on the tile's own node. There is no long press, for the reason `HoverTip` gives, so a touch screen has no way to it. The tiles under *Extra* have none: each has an address of its own.

`BrowserMenuSuppressor` keeps the browser's own menu off those parts. `BrowserContextMenu` is one switch for the whole page, and `SelectableCode` needs it on everywhere else, so the switch is thrown only while the pointer is over a part. **None of that runs under `flutter test`. Check a change to it in a browser.**

`catalogAddress()` puts the route in the fragment. That is Flutter's hash URL strategy, which the app leaves at its default; a path strategy would need the function to change with it.

`test/views/catalog_anchor_navigation_test.dart` goes through the real router: an address pasted over an open catalog, a cold start past the bootstrap, and the crumb pressed twice.

### Progress

`ProgressStore` (`lib/services/progress/`) remembers which sections a student has finished, in `shared_preferences` — which on web is `localStorage`. It is a MobX store, so a tick appears on the catalog the moment a step passes rather than on the next visit.

Two things it is deliberately not:

- **Not per person.** There is no login, so this is per browser. A student who switches machine starts again.
- **Not a record.** Every read and write swallows its own failure — a browser that refuses storage (private mode, storage disabled) must not keep the app from starting. Nothing may depend on progress being correct.

Keyed on `LessonSection.id`, never on a step's position, so a tick survives the author reordering a lesson. See `docs/lesson-format.md`.

**What a student typed comes back too.** `CodeDraftStore`, beside it, keeps each exercise's code under its section id, so a reload or a later visit opens the editor on it. A change is in memory at once and in storage **once typing pauses for `writeDelay` (1 s)**, not on Run: a reload has to find what was typed after the last run as well. The delay is for Android rather than the web. Chrome, Firefox and Safari already batch localStorage writes in the browser process, but DataStore, which `shared_preferences` uses there, rewrites its whole file on every call. `LessonScreenController` flushes at once on Run, on a move to another step, on leaving the lesson and on `AppLifecycleListener.onHide`. That last one is what saves a closed or reloaded tab: Flutter web reports `visibilitychange` as `hidden`, and a tab that closes takes the pending timer with it. Code equal to a starter block, in any locale, is not a draft and removes the one there was, so "Code herstellen" forgets it and a starter the author rewrites still reaches a student who never touched it. "Voortgang wissen" clears drafts along with the ticks. A page with an editor of its own and no section, which today is only the Tkinter page, keeps its program in the same store under a page key (`pageKeyFor`), and `load` finds those by their `draft.` prefix because no course names them.

### Code editor settings

The cog's **Code-editor** item opens `EditorSettingsScreen` (`/editor-settings`). Today it holds one setting, under *Geavanceerd*: the Python the machine runs before every program, on the Tkinter page and in a project on it. So the item is offered only while `tkinterShown` is: a build without the image has nothing behind it, and with the toggle off the page it is about is hidden.

`EditorSettings` (`lib/services/`) is the store. It is per browser and swallows its failures like `ThemeModeController`, and it is loaded by the initialization screen. **A value equal to its default is not stored**, so a better default later reaches everyone who never changed it, and "Standaard herstellen" removes the key rather than writing the default. It writes on every change rather than after a pause: this screen is visited rarely. "Voortgang wissen" leaves it alone, because a setting is not progress.

**"Voortgang wissen" is always in the cog**, greyed out while there is nothing to clear, and a press on it then says why. Both stores load only the keys of lessons the course has now, so a renamed lesson id leaves its old keys behind where nothing reads them. `hasProgress` and `hasDrafts` count those as well (`_hasUnlisted`), and `clear()` removes every key under the store's own prefixes. Without that, the option disappeared after a rename while storage still held data that nothing could clear. That cost a debugging session twice.

### The end of a lesson

The last step does not lead out of the lesson. It leads to the lesson's **end
page** — `LessonCompletePanel`, drawn by the lesson screen in place of a step —
which names what was finished and offers the two ways on: the next lesson, or
the catalog. It is what the "Volgende les" jump hangs off, and the app had no
onward path at all before it.

**It names the lesson "Volgende les" opens**, in a line above the buttons:
"Hierna:", that lesson's group, its icon and its title. The button cannot say
which lesson without growing as long as the title, and a tip behind a hover says
nothing on a touch screen. So that one button carries no `tip`, which would open
on top of the line to repeat it. The back chevron has one, naming the last step.

It is **not a section.** It has no id, counts towards no `stepCount`, keeps no
progress and draws no dot on the progress bar, so `docs/lesson-format.md` says
nothing about it and a lesson file cannot declare one. It is not in the address
either: a reload comes back to the last step, not here.

`ConfettiBurst` fires over it, once, and **only when this visit is what
finished the lesson**. The transition is read around the write in
`LessonScreenController._remember`, not off the last step, because the last step
is not always the one that completes a lesson — a student who left a gap and came
back finishes it in the middle. Opening a lesson that was already finished gets
the end page and no confetti; a step skipped on the way makes the page say
"einde van" rather than "afgerond".

Two smaller bursts sit beside it, both just for fun. A step the student got right
fires `ConfettiBurst.small`, one puff: a passed exercise or order-lines step, a
prediction that matched, and the pick that solves a match-pairs board. It comes out
of the Run button that earned it, which it finds as `TourTarget(id: LessonTourPart.run)`
a frame after it appears, and from the bottom centre when there is none on screen:
a board, or a button scrolled away while the run was going. A wrong prediction completes its step and fires nothing. The end page carries a quiet "Meer confetti" link that fires the
full burst again, shown only when this visit earned the first one; the last three
presses stay mounted so a new press adds to the flakes in the air instead of
wiping them. Both are keyed on a counter in the view model, which is what makes a
repeat fire again.

The burst draws **nothing** when `MediaQuery.disableAnimationsOf` is set — on
the web that is `prefers-reduced-motion: reduce`, which the engine maps onto both
`reduceMotion` and `disableAnimations`. Its colours come from the preset's own
tokens rather than a token of its own: flakes in flight need no paired foreground
and no contrast floor, and a new preset gets confetti in its palette for free.

**Every `LessonRoute` is built through `lessonRoute()`** (`lib/routing/`), which
keys the screen on the lesson. auto_route keys a page on its route *name* alone,
so replacing one `LessonRoute` with another updates the page in place — same
element, same `State`, and so the previous lesson's view model. The widget key is
the only thing that makes a jump to a different lesson a different screen, and
keying every step of a lesson the same way is what keeps moving *within* one from
throwing that state away. A route parsed from the address carries no key, so the
first move away from a cold-loaded step rebuilds the screen once.

### Three loading states

They cover three different windows and are not interchangeable:

1. **`web/index.html`** — before Flutter exists at all. Cannot reach the theme, so it restates the neutral preset's colours in CSS by hand, light and dark; changing the preset means changing that block too. An inline script reads `localStorage['theme.mode']` — `SharedPreferencesAsync` stores web keys **verbatim, no `flutter.` prefix**, JSON-encoded — and falls back to `prefers-color-scheme`, so a student who forced light on a dark machine gets no flash. That literal key is coupled to `ThemeModeControllerBase.storageKey`.
2. **`InitializationScreen`** — work the app does once it is running: reading the course bundle, and nothing else. It shows which step is in flight, retries a bounded number of times, then offers a retry button. The bound matters: everything it waits on is a bundled asset, so a failure means a broken build rather than a server that might come back.
3. **`LoadingOverlay`** — anything a screen waits on afterwards.

**The splash is the initialization screen, drawn before Flutter exists**, so the hand-over moves nothing. Same column, same measurements, the same `LoadingOverlay` card with the same `ProgressRing`, and the title in Fredoka from the bundled file. Measured in Chrome, the mark, the title, the card and its text land on the same pixels in both. Three things it restates and MUST be changed alongside:

- **The layout and the type**, from `InitializationScreenView`, `LoadingOverlay`, `ProgressRing` and the error notice. The squircles are drawn by a script, from the path `ContinuousRectangleBorder` draws at the box's own size, because CSS has no squircle.
- **The words**, in the app's language: the one stored under `locale.language` (`LocaleControllerBase.storageKey`), else the browser's first that the app speaks, else Dutch. Each is an ARB string but the error card's body, which only the splash says. The splash says "Laden…" throughout; the engine's own steps are not words a student needs.
- **The font file.** CSS fetches Fredoka as the splash first draws, and the engine's own request for it is then answered from the HTTP cache. Measured on a cold load: the second request is a revalidation, not a download. Lexend is fetched by CSS only for the error card's body.

**The splash stays under the app until the curtain has opened.** `appRunner.runApp()` settles as soon as Dart's `main()` starts, and the first frame reaches the screen later: measured, ~70 ms later on a warm start and ~430 ms on a cold one, most of it the GPU after the engine's `flutter-first-frame` event, so waiting for that event is not enough either. Removing the splash at `runApp()` showed the bare page for that long. Now the page only takes it out of the accessibility tree (`aria-hidden`) and out of reach (`inert`) there. The Flutter view lies over it and is transparent until its first frame is on screen, so the splash shows through exactly until the app does. `StartupCurtain.onOpened` calls `removeSplash()` (`lib/services/splash/`) once the curtain is gone, more than a second after the app first drew. With reduced motion there is no curtain and the splash stays for good: still, unseen and unread. Measured on the home screen, idle and while a card animated, it adds no style, layout, paint or raster work.

**The way into the app is `StartupCurtain`** (`lib/views/components/`), around `AppHeaderHost` in the shell. Once everything is in, the initialization screen's logo winks, and only then does the screen leave: `InitializationScreenController._replaceAll` asks the curtain to `lift`. The curtain snapshots the window, shows the snapshot on top, has the router replace the screen under it, and then plays the way in: the snapshot zooms towards the reader, blurs and fades, while the app comes up out of a blur underneath. Things it leans on:

- **The first page brings no transition of its own.** auto_route takes none per navigation, so `AppRouter.withoutTransition` switches `defaultRouteType` while the navigation runs. A page reads it once, when its route is created, so the switch reaches the first page and nothing after it. Without it the platform's own slide (Cupertino on a Mac) played under the curtain as it opened.
- **The bar takes its place at once the first time it has something to show**, rather than sliding in. It arrives with the first page, under the curtain.
- **At rest it composites nothing.** It is a render object of its own (`_CurtainLayers`) rather than `Opacity`, `Transform` and `ImageFiltered` left at their resting values: `Opacity` keeps an opacity layer at 1, and the web engine draws every opacity layer through a `saveLayer`, which around the whole app is a window-sized buffer on every frame. And it is always in the tree and only switched, for the reason `ColorVisionFilter` gives.
- **The snapshot is `toImageSync`**, so the widget tests can run it under the fake clock. Below no curtain, which is every widget test of a screen, `lift` is not called and the router replaces the screen the old way.
- **Less motion means no curtain**: the page is swapped in one frame. The wink is skipped too.

Check a change to it in a browser: the tests draw on the CPU and say nothing about how the blur looks or whether it holds 60 frames a second.

### What a cold start downloads

A cold start is about twenty requests, all to the app's own origin: the entrypoint, CanvasKit, eight fonts and the course. Four things keep it there, and each undoes something Flutter does by default. A build that reports errors makes one more, to Sentry's CDN (see *Error reporting*).

- **The course is one file.** `assets/course.json` holds every lesson file's text by path, with every `{{#include}}` already resolved. It is written during the build by `bin/bundle_lessons.dart`, an asset transformer declared on that asset in `pubspec.yaml`; the committed file is a placeholder holding `{}`. A transformer takes one asset and gives one back, so this one ignores its input and reads `assets/lessons/` instead. It writes a depfile beside its output naming every file it read, the included ones too, which is what makes Flutter run it again when one of them changes. That depfile is read by `asset_transformer.dart` in flutter_tools and is in no documentation. It runs under `flutter build`, `flutter run` and `flutter test` alike.
- **forui's Inter is taken out of the build.** forui bundles it, `buildAppTheme()` replaces both of forui's typefaces, and the engine downloads every font in the manifest whether anything draws with it or not. Flutter has no switch for a package's font, so `tool/finish_web_build.dart` removes it from `FontManifest.json` after the build. `flutter run` still loads it.
- **CanvasKit is bundled**, by `--no-web-resources-cdn`.
- **Roboto is an alias.** See *Theming*.

`tool/finish_web_build.dart` is the step after `flutter build web`, and `just build` and both workflows run it. Besides Inter it writes the size of every file above into `index.html`, and it **fails the build** when its assumptions no longer hold: no Inter in the manifest, CanvasKit on the CDN, or a `main.dart.js` that no longer calls `window.fetch`.

**The ring on the splash and on the initialization screen is the download, counted.** Flutter reports nothing about what it downloads. A script in `web/index.html` wraps `window.fetch`, reads a copy of each response it has a size for, and shows the share that has arrived. The caller gets the original response. Things to know before touching it:

- **It leans on the loader and the engine fetching through `window.fetch`.** That is not a promise Flutter makes, which is what the check in the finish step is for.
- **`Content-Length` is no use.** GitHub Pages compresses, so the header is the compressed length while the body arrives decompressed. Hence the sizes from the build. A file weighs its gzipped size in the total, so the ring follows the transfer.
- **`main.dart.js` is fetched before the loader is started**, because the loader adds it as a script tag and a script tag reports nothing. The tag is then answered from the HTTP cache. Not a blob URL, which the loader would take: a blob has a new address every visit, so the browser could not reuse the code it compiled last time. CanvasKit therefore starts after the entrypoint and not beside it.
- **A second request for a file still on its way waits for the first.** The Lexend file is fetched once for each family it is bundled under, at the same moment, and the browser downloads it twice unless the second request is held until the first is in the cache.
- **`flutter run` has no sizes**, so nothing is wrapped there and the ring turns as a spinner.
- **After a hard reload the ring crawls and then jumps.** The browser skips its cache for what the page asks for while it loads, which includes the entrypoint, and not for what the engine asks for afterwards. The ring is showing what arrived.

`StartupProgress` (`lib/services/startup_progress/`) is the app's view of that count, a stub where no page is counting. `LoadingOverlay.progress` hands it to `ProgressRing`, which is the same ring drawn by Flutter: forui has a spinner and a determinate bar, and no ring that carries a value. Almost all of the download happens before the app exists, since the engine loads the fonts before `main()` runs, so the initialization screen only ever shows the last few percent.

To see it, `just build`, `just serve-build`, and throttle the network in the browser. `serve-build` is `tool/serve_web_build.dart`, which sends the two isolation headers itself, as the `flutter run` configurations do. A plain static server leaves isolation to the service worker, and a hard reload skips a service worker, as does DevTools' "Disable cache" some of the time, so the console would come up saying it cannot run.

### Error reporting

**Sentry, and only in a build that was given a DSN.** `--dart-define=SENTRY_DSN=...` turns it on, and only the course repository's deploy passes one, from its `SENTRY_DSN` secret. `flutter run`, the tests and the GitHub Pages copy have none, so they never load the SDK and send nothing. `kReportsErrors` (`lib/services/error_reporting.dart`) is the switch, and everything Sentry adds goes through that file: the zone around `main()`, the `SentryWidget` around the app and the router's navigator observer.

**On the web, `sentry_flutter` is a front for Sentry's JavaScript SDK.** Every event is handed to it (`JavascriptTransport`), and the package injects it as a `<script>` from `browser.sentry-cdn.com` at every start. That is the one request a cold start makes outside the app's own origin, and it was accepted knowingly:

- **It cannot be bundled.** The URL is a constant in the package. Turning the injection off (`autoInitializeNativeSdk = false`) leaves the transport in place with no SDK under it, and events are then dropped without a word.
- **It loads under `require-corp`**, because the loader asks with `crossorigin="anonymous"` and the CDN answers with `Access-Control-Allow-Origin: *`. SRI pins its contents.
- **The first frame waits for it for at most three seconds** (`_sdkWaitLimit`). The loader has no timeout, so a network that drops the request would otherwise hold the app on its splash screen. An app that started without it reports nothing until it arrives, and tracks no session for that visit: the navigator observer is built before the session integration has started.
- **Ad blockers block it**, and the ingest too, so Sentry's counts are a floor.

**The binding is created inside Sentry's zone**, which is why `main()` hands its whole body to `runReportingErrors`. Created before it, in the root zone, Flutter reports a zone mismatch on the web.

**It collects errors and sessions, and nothing else.** No tracing: a transaction per screen would send every student's route through the course. `sendDefaultPii` stays off, so the SDK attaches no user and no IP address; whether Sentry stores the address a request came from is a project setting. Breadcrumbs do carry route arguments (lesson and step ids) and the text of what was tapped, which on a lesson can be the lesson's own words. Session Replay does not exist for Flutter web.

**Readable stack traces need the source maps.** The course repository's deploy builds with `--source-maps` and runs `sentry_dart_plugin`, configured by the `sentry:` block in `pubspec.yaml`, **before** `tool/finish_web_build.dart`: the plugin writes a debug ID into `main.dart.js`, which changes its size, and the finish step measures the files. The maps are deleted from the build after the upload. The plugin needs that repository's `SENTRY_AUTH_TOKEN` secret and its `SENTRY_ORG` and `SENTRY_PROJECT` variables. Without them the deploy goes on with a warning, and it goes on when the upload fails too, because a lesson fix should not wait on Sentry.

**A panic in the Rust core arrives as two events.** The wasm is built with `panic_abort`, so a panic never reaches Dart as the `PanicException` flutter_rust_bridge documents: the instance traps, the call it was in never answers, and the JavaScript SDK reports the trap as `RuntimeError: unreachable` with nothing but wasm offsets. `rust/src/panic_report.rs` wraps the panic hook and sends the message and its location on the `core_panics` stream, from whichever thread panicked. `WebMicrobitLink` listens from the moment it loads the core, and `reportCorePanic` makes a `RustPanic` event of it, one issue per panic site, with the app's breadcrumbs. The trap event stays, because a trap that is not a panic leaves nothing else.

**The release is `i_can_code@<version>+<build>` on both sides, and nothing states it.** The SDK reads it from `version.json` and the plugin from `pubspec.yaml`. Two deploys of one version share a release; the debug ID is what ties an error to the map of the build that threw it.

### Mobile browsers

**A browser on a phone or a tablet is warned before the app opens, and can go on.** The initialization screen shows the warning once everything is loaded, with `BootstrapGuard` still shut, so no address gets past it before the reader has answered. "Toch doorgaan" is the only button: the detection can be wrong, so the screen asks and does not refuse, and a page cannot close its own tab. `MobileBrowserWarning` (`lib/services/`) remembers the choice per browser under `mobileWarning.dismissed` and swallows its failures like `TourStore`. Clearing progress does not clear it. The debug menu does.

`isMobileBrowser()` is `kIsWeb` **and** iOS or Android. The web half is there on purpose: a native build reports the same platform and has none of the trouble. An iPad counts although it asks for the desktop site, because Flutter's web engine calls a "Mac" with more than two touch points iOS.

The trouble is `re_editor`, which reads that same `defaultTargetPlatform` and takes a path written for a native app. Seen on an iPad with a hardware keyboard. Android takes the same path and was not tested.

- **The space bar types nothing.** That path builds no `_CodeShortcuts`, which is where the editor keeps space away from the app's own shortcuts. On the web `WidgetsApp` maps space to a page scroll, the scroll claims the key, and the engine calls `preventDefault()` on it. The arrow keys, Tab and undo are unbound for the same reason.
- **A tap deletes the character before the caret.** The editor hands the input field one line with a zero-width space in front, and reads a caret at offset 0 as a backspace without checking that the space is gone. On iOS the engine lays the real `<input>` over the editor and does not stop the browser from moving its caret on a tap. Upstream: [reqable/re-editor#58](https://github.com/reqable/re-editor/issues/58), open, and 0.10.0 is the latest release.

Neither is fixed here, and fixing them means patching `re_editor`. The warning exists so that nobody meets them unannounced.

`test/views/initialization_screen_test.dart` runs the bootstrap through the app's own router with a **bundle holding an empty course**, so it loads no lessons, and with the real fonts, because the test font is wide enough to overflow a phone the app fits on.

### Running a student's code

**Every runtime starts when a step needs it, and not before.** Compiling the 7 MB `python.wasm` was a bootstrap step once, so a student who only read a lesson waited for an interpreter they never ran, and the catalog came up that much later. `LessonScreenController` now warms it when a step that runs code is the one in front of the student, on arrival and on every move, which is the rule the VM behind the Tkinter page has always followed. `PythonRuntime.run()` awaits `ready()` itself, so a Run that beats the compile still runs; warming is only what keeps that press from being the one that waits. A failure surfaces as `AttemptResult.broken`, which never reads as the student's mistake.

`PythonAttemptRunner` is the only thing that should call `PythonRuntime.run()`. It wraps the student's code and the section's validator into **one** program, because the checks have to see the exact output that run produced. `AttemptResult` keeps the three outcomes apart — a crash (`programError`), a failed check (`checkMessage`) and a pass — because each needs different words on screen, and `AttemptResult.broken` is a fourth: the runtime is unavailable, which must never read as "you got it wrong".

`tool/try_lesson.dart` drives the same harness from the command line, so a lesson can be checked without the app.

**Run is also Stop.** A program that will not end on its own — `while True:`, or the `sleep(3000)` a student meant as milliseconds — is ended by terminating the worker, which is the only reason the worker exists at all. `RunButton` (`lib/views/components/`) is the one control both ways, because while a run is in flight starting it is the one thing that cannot be asked for and stopping it is the only thing that can. It keeps its size across the swap by laying both labels out and painting one, for the reason `AppButton.busy` keeps its label — and it carries no spinner, since the strip over the editor already says a run is going and a spinner would cover the word that says what pressing this now does.

**The back chevron always has somewhere to go.** From the first step it leaves the lesson for its catalog rather than being left out — that was the one place in the app with no way back, and in zen mode, where the trail is put away, it left the catalog unreachable short of the browser's own Back button. It is named for where it actually goes, so on the first step a screen reader hears "Terug naar Python" and not "Vorige stap".

**A run belongs to the step it was started on.** `LessonScreenController` stops whatever is going the moment the student moves — `goTo`, the end page, and `dispose` as the catch-all behind the trail, the browser's Back button and the settings menu — and a run token drops the answer that arrives afterwards, so a verdict cannot land on a step it was not written for. **A stop draws no verdict at all**: it is not something the student got wrong, and what the program had printed died with the worker holding it. The runtime **supersedes** a run rather than refusing one; refusing is what left a student who walked away from a long `sleep` with "a program is already running" answered to every attempt afterwards and nothing they could press to clear it.

**A result is scrolled to when it arrives.** `ScrollToOnArrival` (`lib/views/lesson_screen/components/`) wraps `OutputPanel`, `PredictionVerdict` and the line a solved `PairMatchBoard` says, and brings its top to just under the bar, as far as the page has room to scroll. It moves the nearest scroll view: the page on a step that scrolls as one, the right column on a two-column step. It compares the `AttemptResult` by identity, so a second run with the same outcome scrolls again and a rebuild does not. A stop draws no verdict, so it scrolls nothing. **A result that is there when the step opens scrolls nothing either**, which is a board solved before the student stepped away: the widget does nothing when it is mounted in the same frame as its scroll view. It finds the scroll view from its own context and not through a `GlobalKey`, for the reason `TourTarget` gives.

**A program can read and write files.** The filesystem is a tree in memory inside `web/python/wasi.js`, seeded with the stdlib zip and the student's own `/main.py`, with `/tmp` and `/dev/null` beside them, and the wrapper adds the section's own files (see below). `/dev/null` swallows writes, reads as empty, and cannot be deleted or renamed; pytest's logging plugin opens it at startup. `open(..., "w")`, `csv.writer`, `os.listdir`, `os.mkdir`, `pathlib` and `tempfile` all work, so a lesson on files is a lesson that runs rather than one that is read about. Three things bound it: **nothing persists** — the lesson worker builds a fresh instance per run, so a file written by one run is gone in the next, while the REPL worker keeps one for the session; **the stdlib is sealed** by `readOnlyPaths`, because a program that truncates the archive it imports from breaks every later import with an `EOFError` naming nothing the student did; and **growth is capped** at `FS_QUOTA_BYTES`, so a runaway write ends in `ENOSPC` instead of a dead tab. There are no links of either kind, which is what lets `normalise()` alone guarantee no path climbs out of the virtual root. See `docs/python-wasm-build.md`.

**A validator can read a file the program wrote**, because the student's code and the checks are one program in one instance — `buildProgram` puts them in the same `/main.py`. So a step that asks for a CSV to be written can check what is in it, not only what was printed.

**A step can give its program files, and the student sees what it wrote.** A section's `file` blocks (`LessonSection.files`) travel in `buildProgram`'s payload beside the code, and the wrapper writes them into the working directory before it compiles anything, the way it already writes `main.py`. Nothing in the worker, `wasi.js` or `PythonRuntime` knows about them, so the browser, the host tests and `tool/try_lesson.dart` run one implementation. After the program and **before the checks**, the wrapper collects every file in the working directory that is new or changed, leaving out what was there before the program started that was not the lesson's (`main.py`, the stdlib zip, `/tmp`). Two things it does first:

- **It flushes what the program left open**, by clearing the program's globals and collecting, as `python main.py` does on exit. Without that, an unclosed file reads back empty, to the card and to the validator.
- **It moves back to the starting directory**, so a program that called `os.chdir` changes neither what is listed nor what a validator's relative path means.

The list leaves on **a line of its own after the verdict**, behind `filesSentinel`. The verdict line is written as it always was, so the worker's 256 KB cap (`outputCap`, which MUST match `MAX_OUTPUT_BYTES`) can only ever cut the files, which then say so with `filesCut`. A verdict that parses holds the whole output, so `truncated` is false there. Files are shown as buttons in `FilesCard`, which open `showFileDialog`: a dialog, not a card on the step, so a long CSV cannot push Run off the screen. Downloading goes through `lib/services/file_download/`, a stub everywhere but the web.

**A section can script what its program reads.** A `stdin` block travels on the real file descriptor through `PythonRuntime.run(stdin:)` rather than inside the wrapper, so `buildProgram` stays the one string that is the whole experiment and `input()` behaves the way a student finds it anywhere else. The four kinds that hand a program to CPython may carry one — that set is `SectionKind.runsCode`, beside `isAssignment` (has an editor) and `usesValidator` (is checked). **The student is always shown it**, in a card beside the editor: a check that feeds numbers the prose never mentions cannot be passed by reading, and restating them in prose is one more thing that can drift from the block. **The output reads like a terminal.** The wrapper puts an `_Echo` around `sys.stdin` that writes each line read back into the output, so `input("Naam? ")` then a greeting shows `Naam? Sanne` and `Hallo Sanne` on two lines, the way PyCharm does. Without it the prompt and the next print ran together on one line, which taught a picture of `input` no student meets anywhere else. It wraps stdin rather than `input` so that a read past the end is CPython's own `EOFError` and no harness frame reaches the student's traceback. Every validator on such a step sees the prompts and the typed lines in `output`. Reading past the end raises `EOFError`, and that reaches the student as their own traceback rather than as a failed check.

**A validator can read the code as a tree, not only as a string.** `kCheckLibrary` (`lib/services/python/python_check_library.dart`) is a Python module carried into the run beside the student's source and exec'd into the validator's scope, which is how a validator gets `program.calls("print").with_args(42)` in place of `"print(" in code` — a check that passes for `s = "print(42)"` and cannot tell `print(42)` from `print("42")`. `docs/lesson-format.md` is the author-facing spec, and the names in the library's `__all__` are the contract: adding one means documenting it there.

Two things it deliberately is not:

- **Not a dependency.** It is the standard library's own `ast` and nothing else — `ast.pyc` is already inside `assets/python/python315.zip` and `_ast` is built into CPython — so there is no package to vendor, no asset to declare and no worker change behind it. It is a Dart `const` rather than a file under `assets/` so that `buildProgram` stays static and synchronous, which is what lets `try_lesson.dart` and the widget-free tests drive the real thing.
- **Not a second way to check output.** The tree sees what was *written*, so it reaches a branch that never ran and never sees a value that was computed: `x = 40 + 2` then `print(x)` is a call to `print` with a variable. Check the value in `output`, the shape in `program`. A spy on the running `print` would answer the other half and is the thing to reach for if that half is ever needed.

**A step fences off what it has not taught with `allow_only`, not `disallow`.** `program.allow_only("call")` is a whole early print step's check: calls, and nothing else. A ban has to name everything a student might reach for and misses whatever the language grows next, while an allowlist is a sentence about what the step has taught and stays true. Both take the student's message, and **without one the app says it instead, in the reader's language.** That works because the refusal reaches Dart as the construct's *name* rather than as a sentence: `NotAllowed` carries `icc_construct` out through the verdict into `AttemptResult.disallowedConstruct`, and `AppLocalizationsExtension.checkNotAllowed` phrases it. A Python keyword is the same word everywhere and is set as code, so only the handful with no keyword to quote — call, assignment, comprehension, f-string, bare expression, type alias — need a string per locale, and `test/services/python_check_library_test.dart` runs the library to hold `kPhrasedConstructs` against its own `_PHRASES`. The exception's own text stays the English sentence, because `tool/try_lesson.dart` has no localizations to reach for. Note `match` is a **soft** keyword: `keyword.iskeyword` says no about it, which is why `_is_keyword` asks `issoftkeyword` too. Depth hides nothing and costs nothing: the tree is walked iteratively, and CPython's parser refuses over-nested source before any check runs.

**A step can run pytest instead of a program.** With `run: pytest` in its metadata, the editor holds the file `file:` names, and a `file` block may give a `.py` module, which only such a step allows. Those modules are shown read-only above the editor as a `CodeSample` rather than as a button in the files card, because they are half of what the student works on. `buildProgram` then runs pytest in-process on the editor's file and every `file` block, through `kPytestLibrary` (`lib/services/python/python_pytest_library.dart`), which is kept apart from `kCheckLibrary` because that one promises never to run the student's code. pytest itself is **baked into `python315.zip`** by `tool/bake_pytest.py`, with Pygments cut to the 21 modules pytest imports; see `docs/python-wasm-build.md`. The tests are a gate: a file pytest cannot collect is a crash, no tests or a failing test is `AttemptResult.testsProblem`, and only once all pass does the validator run, with `results` and `run_tests` beside `program`. `run_tests(replace=...)` runs the tests again on a mutant, which is how a step checks that the student's tests catch a bug. Every test's outcome travels back in `AttemptResult.tests` and is listed between the verdict and the output. `program.require_aaa()` checks `# Arrange` / `# Act` / `# Assert` comments with `tokenize`, and without a message it reaches Dart as `AttemptResult.aaaTest`, the way `NotAllowed` does. Off the web, the host `python3` needs the same pytest: the tests that need it skip without it (`hasPytest`), and `try_lesson.dart` says so.

`with_args` is **exact** in its positional arguments, and that is the whole design. Every pattern language that matches one argument at a time gets this wrong — pedal's `print(__exp__)` matches `print("Hallo", naam)` twice — and an author writing "called with one thing" then gets something else. `with_any_args` is the loose one, and it says so.

### Vocabulary

These words are fixed. Drifting off them is what made the folders disagree with the code once already.

| Word | Means |
| --- | --- |
| **course** | Everything the app ships. `Course`. |
| **subject** | One directory under `assets/lessons/`, and one card on the home screen. Python is the first. `LessonEntry.subject`. |
| **lesson** | One markdown file per locale, under `assets/lessons/<subject>/`. `Lesson`. |
| **section** | One `##` block of a lesson. `LessonSection`. The student-facing word for it is **step**. |
| **exercise** | A *kind of section* — one that asks for code (`SectionKind.quickExercise`, `exercise`). **Not** a unit of content. |
| **pair** | The two halves of one item on a match-pairs board. `LessonPair`. |
| **project** | A lesson with `layout: project`: one program for a micro:bit or for the machine behind the Tkinter page, built up over its tasks. `LessonLayout.project`, `ProjectScreen`. |
| **task** | A *kind of section*, and the only one a project has beside `info`. `SectionKind.task`. |
| **contents** | A subject's `contents.<locale>.md`: which lessons it has, in what order and under which groups. `SubjectContents`. |
| **group** | A `#` heading in a contents file, over the lessons listed under it, with an id every locale shares. `LessonGroup`. |

A single run of a section is an **attempt** (`AttemptResult`, `PythonAttemptRunner`). *Assignment* survives only where it names a **block** in a lesson file (```` ```python-assignment ````) and in `SectionKind.isAssignment`; as a word for a step it has been replaced by **exercise**.

A **whole lesson** may be optional too, by saying `optional: true` in its document-level metadata. The catalog then lists it under a *Verdieping* heading of its own rather than in the numbered run, so the main sequence still reads as one path and skipping every one of them still finishes the course. Inside, it is an ordinary lesson: checked, ticked and recorded the normal way. Same word and same promise as the section flag below, one level up.

**Lessons stand under the heading of their group**, a `# Title {#id}` in their subject's contents file — this course uses it for its weeks. The catalog sets a small `CatalogGroupHeading` over each run of lessons that share a group, and `runsBy` (`lib/views/catalog_screen/`) is the whole rule: consecutive lessons with the same group id, in the order the contents file lists them. The heading is translated and the id is not, so `LessonGroup.titleFor(locale)` is what a screen shows and the id is what names the group. The words come from the course, which is what keeps week numbers — a fact about one school's schedule — out of the app. The heading is small capitals rather than another `h2`, so it names the tiles under it without competing with them. It **sticks under the bar** while its lessons pass under it: `StickyGroupHeading` is the first sliver of a `SliverMainAxisGroup` that holds its run, and the end of that group is what pushes it off for the next week. Stuck, it floats as a small label, because a band the width of the page would cut the tiles off along its edge. The catalog is a `CustomScrollView` for that reason. A run's tiles are a `TileGrid` in it, so every one of them is built (see *Anchors*), and each tile is an `Observer` of its own.

A section of any type may be **optional** — a "Verdieping". It is badged and can be skipped, and skipping records nothing: the step stays grey in the progress bar and comes back on the next visit. Optionality is a flag on a section, deliberately not a `SectionKind` of its own, so a Verdieping can still hold an exercise or a board.

**Catalog** names a listing *screen*, not content, which is why it sits outside the table. So does **console** — the interactive prompt under *Extra*, which is not a lesson, records nothing and checks nothing. The **Tkinter page** under *Extra* is the same kind of thing.

### Lessons

A subject is plain files under `assets/lessons/<subject>/`: a **contents file** per locale that lists its lessons, and **one markdown file per lesson per locale**. Metadata, prose, starter code and the hidden validators all live in the lesson's file. The full spec is in `docs/lesson-format.md`. **Read it before touching the format.**

Things that are easy to get wrong:

- **The contents file is the only structure.** `contents.<locale>.md` gives the order, the groups and which file is which lesson. Where a file sits and what it is called mean nothing, so a new subject or folder needs nothing in `pubspec.yaml` (see *What a cold start downloads*). The form is mdBook's `SUMMARY.md`, and it is strict: a line it does not know is refused, because a skipped line is a lesson that quietly left the course.
- **It is an index, and this format had none once**, because a lesson could be added and forgotten in the old `index.yaml`. `test/content/lessons_test.dart` holds that now: every markdown file under a subject is listed or included. And a subject with files and no contents file fails the load.
- **Translations are paired by position.** Every contents file of a subject lists the same lessons, by `id`, under the same group ids in the same places, and `Course.fromFiles` refuses anything else. A lesson with no translation is listed in the language it has.
- **`{{#include path}}` is resolved by the bundler, never by the app.** `resolveIncludes` (`lib/services/lessons/includes.dart`) puts the file's text in before anything is parsed, so it works inside a fenced block: a validator or a starter can be a `.py` file. `bin/bundle_lessons.dart`, `tool/try_lesson.dart` and the content test are its callers. It and `subject_contents.dart` import nothing from Flutter, because the bundler runs on a Dart VM that has no `dart:ui`.
- **`Lesson.parse` must keep `encodeHtml: false`.** The `markdown` package HTML-escapes block text by default, which would hand CPython `print(&quot;hi&quot;)` and fail at runtime rather than at parse time.

**A step says what it runs on, and one this version cannot run is left out.** `runtime:` in a lesson's or a section's metadata is `python` by default — CPython in the page — and `tkinter` is Python with Tk on the machine the Tkinter page uses. A project runs there (see *Projects*), but the step of any other lesson has to be checked, and nothing checks a window program yet. So outside a project `Lesson.parse` **drops** such a step and reads nothing else about it: its `type` and its blocks may be ones this version has never heard of. `LessonRuntime.readyIn(layout)` is the whole rule. A lesson whose every step goes that way parses to no steps at all, which is not an error, and `Course.load` leaves it out rather than list a card that opens on nothing. That is what lets the course carry window lessons before the app can run them. A `runtime` no version knows is still an author's mistake.

**The test suite never reads the course.** The lessons are headed for a private repository while the app stays open source, so no test may name a lesson or depend on one existing — the suite has to go green on a checkout with no course in it at all, and it does.

Two things keep that true:

- **A test that needs a real lesson reads `test/fixtures/lesson.md`**, which the suite owns: English, one step of every interactive kind, validators written the way an author writes them. It changes only when a test needs it to, so rewording a paragraph of the course cannot turn a renderer test red.
- **The rules every shipped lesson must keep live in `test/content/lessons_test.dart`** and run over whatever course is present — `assets/lessons/` by default, or a checkout named by `LESSONS_DIR`. With no lesson files there they **skip, with the reason**, rather than pass on nothing: a green run that checked nothing reads exactly like one that checked everything. The course repository runs `LESSONS_DIR=<its lessons> fvm flutter test test/content/` against this app to check itself.

The content test makes its bundle with the bundler's own `bundleLessons` and its lessons with `Course.entriesFrom`, so it checks the files the app would pick up, with their includes resolved, and no others.

**`CodeEditorCard.heightForLines` rounds a line up to whole pixels before multiplying**, because that is what the text is laid out at: `16 × 1.6` is 25.6, drawn as 26. Keeping the fraction left two lines 0.8px taller than the box asked for — invisible, and still enough for the editor to decide it can scroll and draw a scrollbar over the code the moment a student typed a second line. The six-line micro:bit editor was 2.4px short the same way.

**A quick exercise is capped at one line past its starter**, and the editor enforces it: `CodeEditorCard.maxLines` joins anything past the limit onto the last line it allows, because a plain Enter arrives through the text-input connection rather than through `shortcutOverrideActions`, so overriding the intent does nothing. An empty starter counts as one line, so the least is two: storing a value and then showing it is the smallest exercise worth setting and it does not fit in one line. A step that needs more says `lines:` in its metadata. `Lesson.parse` resolves both into `LessonSection.maxLines`, and the view reads the cap and `heightForLines` from that one number, so the editor cannot allow a line it is too short to show.

**The code editor always has a way out, and says so.** `re_editor` binds Tab and Shift+Tab to indent and outdent, so on its own the editor is a keyboard trap (WCAG 2.1.2): nothing after it on the page can be reached by Tab. `EscapeThenTabExit` (`lib/views/components/`) is the workaround widget, and every `CodeEditorCard` is built through it: **Escape, then Tab or Shift+Tab, moves to the next or previous control, and a Tab alone still indents**, which is the same way out the Tkinter page's display has. The card states it in its strip, beside the file name, only while the editor has the keyboard. Its class comment lists the `re_editor` and Flutter behaviour it leans on. The lesson screens keep `re_editor`'s autofocus, because writing the code is what the step is for; the Tkinter page turns it off (`CodeEditorCard.autofocus`), since a keyboard user who started in the editor had to leave it before reaching Run or the failure card's Retry.

Only the desktop editor binds Tab, and `re_editor` decides which editor it builds once per isolate: `kIsAndroid` is a top-level final, read the first time any editor is built, and `flutter test` defaults to Android. So `test/views/code_editor_keyboard_test.dart` runs every test as a desktop, and a Tab test in a file that has already built an editor under Android tests nothing.

**A step does not have to ask for code.** `SectionKind.matchPairs` is a board of tiles the student pairs up — declared `type: match-pairs`, filled from a `pairs` block, and carrying no editor and no validator, because the board itself is the check. It is why `SectionKind.isAssignment` names the two kinds it is true of rather than reading "not `info`": a match-pairs step is neither prose nor an assignment, and the older test would have had the parser demand an editor for a step that has none.

Three things hold that board together, and each is in `PairMatchBoard` (`lib/views/lesson_screen/components/`) rather than in the file format:

- **The deal is derived, never drawn.** `boardOrder()` seeds a `Random` from the section's `id` and shuffles every tile — both halves of every pair, into **one pool** — so the board survives its own rebuilds, one per pick, per hover, per resize, per change of language, instead of dealing itself a new hand each time. One pool and not a block of cues over a block of answers, because a split board tells the student which half of a pair a tile is before they have read a word of it, and that is half of every pair narrowed down for them. A tile is a `PairHalf`, a record, so a pick is findable in a set by value. The one deal it refuses is the lesson's own order, which would stand every pair side by side. Not `String.hashCode`, which Dart promises nothing about between releases.
- **A tile is a square, and the board is one grid.** `tileSizeFor()` spends the step's width on more tiles per row before it spends any on bigger ones: as many across as fit without one falling under `minTileSize`, and never past `maxTileSize`, where a square stops being a tile and becomes a poster. A square has no reading direction, which is what makes a grid possible at all — unlike a bar of text it need not be as wide as the words in it, and four pairs fit in two rows rather than four. Those words are set to the tile for the same reason: a fixed 16px is adrift in a 220px square and spilling out of a 150px one. They scroll *inside* it rather than overflowing, since the square is a box the lesson author cannot see.
- **A wrong pick has no timer behind it.** Both tiles stay showing until the next tap, which starts the pick over. A flash that clears itself would need a `Future.delayed` in the controller and a disposal guard around it, to say something the tiles already say.
- **Colour is never the only answer.** A matched tile takes a tick and a wrong one an ×, and every state's fill is a `*Surface` token, so one text colour stays legible through all four.

What is matched lives in `LessonScreenViewModel` per step, so stepping away and back finds the board as it was left. It is **not** seeded from `ProgressStore`, which remembers that a step passed and not how: a finished lesson opens on a board that can be played again, with the way on already offered. Typed code is the one thing that does come back, from `CodeDraftStore` (see *Progress*).

**A step may run code the student did not write.** `SectionKind.predictOutput` shows the lesson's own program and asks what it prints *before* it is run — declared `type: predict-output`, filled from a `<lang>-predict` block, and carrying no editor and no validator either. It is why `isAssignment` stays false here: code runs, but the student writes none of it.

**The interpreter is the answer key.** A lesson file states no expected output and has nowhere to put one — `LessonScreenController.predict` calls `PythonAttemptRunner.attempt` with the section's program and *no validator*, and `matchesPrediction` (`prediction_verdict.dart`) holds the answer against what that run printed. An expected output written into the file is one that can drift from the code beside it; this one cannot. `tool/try_lesson.dart` runs a predict step too, so an author can see what their students will be measured against.

Four things that shape it:

- **Trailing whitespace is not a wrong answer, and nothing else is forgiven.** `print` ends every line with a newline no student can deliberately type, and a keyboard leaves trailing spaces nobody can see; both come off. Case, quotes and the space `print` puts between two arguments all count — those *are* the exercise.
- **A wrong prediction still completes the step.** The output is shown either way, with the prediction read back beside it. What decides the tick is that the program ran. Hiding the answer to make the student guess again turns the moment of surprise — the whole reason the step exists — into a lock, and nothing here is graded.
- **The verdict is about a frozen prediction.** `LessonScreenViewModel.prediction` is set when the run starts and is what the banner reads; the box's own controller keeps changing. Reading the box would let a student type the output that is sitting right beside them and watch the verdict flip.
- **The program is a `CodeSample`, never a `CodeEditorCard`.** It cannot be changed, and an editor carries a caret and a text-input connection that invite typing into it. `CodeSample` is the same dark card a worked example in the prose takes — the two are one widget, because both are code that is *read*.

**The answer comes before the buttons**, the reverse of an exercise. The explanation is the point of a prediction, and a Next button above it is an invitation to skip it; with the row underneath, the way on sits after what the step has to say. An exercise and an order-lines step keep Run *above* their output because they are run again and again — putting it under the error would mean scrolling past your own mistake to try once more. A prediction is made once, and its Run button is disabled after, so nothing is lost when the row moves down under the pointer.

The optional `explanation` block is shown under the answer and to everyone, right or wrong. It is the feedback half of a practice test, and a student who guessed right has learned no more about *why* than one who did not.

**Code that is read can be taken away.** `CodeSample` carries a copy button in its corner, where the editor has its reset, and both are a `CodeStripButton`. Its text can be selected with the pointer as well. Two things about it:

- **Selecting is `SelectableCode`** (`lib/views/components/lesson/`), a `SelectableRegion` around each sample and not Material's `SelectionArea`. It is not a tab stop, and below no `Overlay` it is a pass-through, because the region asserts one. On the web the region puts an empty `<div>` under the code, which is how the browser's own menu comes to offer Copy. That view is registered as invisible, so the engine does not split the canvas around it. A touch screen gets no handles, so the button is the way there.
- **A prediction's program cannot be taken away until its answer is showing.** `CodeSample.copyable` is false until then, for the button and the selection alike: run somewhere else first, it is no longer a prediction. The button's place is kept, so nothing moves when it arrives.

**A step may be checked without being typed.** `SectionKind.orderLines` shuffles the program's own lines for the student to arrange — declared `type: order-lines`, filled from a `<lang>-order` block plus optional `<lang>-distractors`. It is the one kind where `isAssignment` and `usesValidator` come apart: it runs a program, so it needs a validator, but the student assembles that program rather than writing it, so it has no editor and no assignment block. `usesValidator` exists for exactly that one case.

**What is checked is the assembled program, never the arrangement.** The placed lines are joined and handed to the ordinary `LessonScreenController.run`, so an order that is different but correct passes — and the validator an author would write for the same task as an `exercise` works here unchanged. Comparing against the block instead would fail a right answer for being a different right answer.

Four things in `LineOrderingBoard` (`lib/views/lesson_screen/components/`):

- **The deal refuses the author's own order**, which is the answer. `bankOrder()` seeds a `Random` from the section's `id` — so the board survives its own rebuilds, one per move — and rotates a deal that came back sorted. The widget test brute-forces 200 seeds per length, because the guard only fires on the deals that would have landed sorted and a single seed is unlikely to be one of them.
- **Dragged, with a tap and a semantics action beside it.** A line is dropped into any gap, which is what ordering actually is. `ReorderableListView` is **Material**, and its widgets-layer cousin wants a viewport of its own that would fight the step's own scroll view, so the board is `LongPressDraggable` and `DragTarget` directly. Tapping an available line still appends it, and a placed line still carries the × that puts it back.
- **A plain `Draggable` loses to the page it sits in.** Its recogniser competes in the gesture arena with the scroll view every step is wrapped in, and **on touch the scroll wins** — the page slides and the line stays put. `LineOrderingBoard.dragDelay` (150ms) settles the arena first: far under `kLongPressTimeout`'s 500ms, which reads as a stall on a mouse, and far enough over zero that a finger starting to scroll is scrolling. The widget test found this, not a browser: `tester.startGesture` simulates touch, and on desktop a mouse is not in `ScrollBehavior.dragDevices` at all — so the bug was invisible to the one device the developer was using.
- **A drag reaches no keyboard and no screen reader**, so every placed line carries `customSemanticsActions` for moving it up and down. Those are the two arrow buttons that used to stand in the row, kept as actions once the buttons themselves were dropped. Removing the buttons without them would have made the step unusable without a mouse, silently.
- **Both positions of a move are counted before the move.** A drop names a gap in the program the student can *see*, not one in the program left after their line is lifted out of it, so `moveLine` corrects by one when the line travels downwards. Without it every drag down lands one place short.
- **Indentation travels with the line.** The parser keeps leading whitespace and drops blank lines, so the student arranges a program rather than also having to indent it. Choosing the indent as well is a second axis this deliberately does not have.

**The best distractor is one the output cannot catch.** `print("42")` beside `print(42)` prints the same characters, so only `program.calls("print").with_any_args("42")` tells them apart — which is what `kCheckLibrary` is for, and how the step in lesson 01 is built.

Flutter's asset globbing is **not recursive**, so every other asset directory is listed separately in `pubspec.yaml` — a new folder is silently absent at runtime until it is declared. Lessons are the exception, since they reach the app through the bundle.

### Projects

A lesson that says `layout: project` is not walked a step at a time. `ProjectScreen` shows it as one page of blocks, one per section, of which one at a time is open: the first unfinished section to begin with, and any finished one the student opens to reread. Blocks ahead show their title and do not open. Beside all of it is **one** editor and what runs it, which the lesson's `runtime` decides: on `microbit` the board's buttons and its output, on `tkinter` a Run button, the machine's card and the run's report, with the program's windows in a dialog over the whole page while it runs. The header carries the trail and no progress bar, because the blocks already say where the student is. The format is in `docs/lesson-format.md`.

Things that are easy to get wrong:

- **Nothing is checked.** The program runs on a board the app cannot watch, or shows windows the app does not judge, so the student's "Het werkt!" is the verdict. What keeps it honest is the task's `done-when` card right above the button, and the button waiting until the program was tried while that task was open (`ProjectScreenViewModel.triedHere`). On a board that is a write, which `MicrobitSessionController.onFlashed` reports. On the machine it is a run that showed a window: `VmSessionController.onWindowShown` fires once per run, the first time the run in flight sends a `VmWindows` with a mapped window. `finish` and `skip` reset it, so every task asks again.
- **The section in front is the first one after the last finished one**, not the first one unfinished. Skipping a Verdieping stores nothing, as everywhere, so on the next visit the first-unfinished rule would put it back in front of work done after it.
- **An info section is a step of its own**, finished with **Gelezen**. Only a task waits for the program to have been tried.
- **One program, kept apart from the drafts.** `CodeDraftStore.workFor` is the program every task shares, and `snapshotFor` the program as it stood when a task was said to work. A snapshot is read-only and can be put back; there is no reset to the starter, which would throw away every task's work at once. The editor belongs to whichever session the project has, and `ProjectScreenViewModel.code` reaches it.
- **A project runs on `microbit` or `tkinter`, and nothing but a project runs on a micro:bit.** The parser refuses a project on `python`, `runtime: microbit` anywhere else, and a `runtime` on any section of a project, since every task shares one program. The screen reads the runtime off the first translation (`test/content/lessons_test.dart` holds the others to it) and holds exactly one session, on its view model and its controller alike: `board` (`MicrobitSessionViewModel`, `MicrobitSessionController`) or `machine` (`VmSessionViewModel`, `VmSessionController`).
- **A project on the machine is the Tkinter page's machine on another page** (see *The Tkinter page and the VM*). The download starts as the screen opens and leaving frees the machine; Run writes the program out first, for the reason the page does; and while a run is up the program is a `VmRunDialog` over the whole page, with the page left out of the focus tree. Nothing on the page moves while a program runs, here as there. Unlike the page this one has animations of its own, so the tasks and the confetti sit under a `TickerMode` that is off while a run is up: a burst still falling, a block still folding or a scroll still easing waits for the run to end. Muted rather than taken out, because a `ConfettiBurst` built again fires again. `ProjectScreenController` takes `createRuntime` and `imageIncluded` for tests, and `ProjectScreenView` a `displayViewBuilder`.
- **Nothing in the app hides a project on the machine.** The course does: its lesson, or the group it stands under, names `feature: tkinter`, the same switch as the Tkinter page's static toggle, and `test/content/lessons_test.dart` holds that. A build without the image shows the page's "not in this version" card where the machine's card would be, with a body of its own: the page's ends on "De lessen zelf werken gewoon", which is not true of a lesson that needs the machine. So `VmMachineCard` takes both of those bodies from its screen.
- **A task's requirement may be another project on the machine**, which opens over this one and takes its machine (see *The Tkinter page and the VM*). Leaving it gives the machine back: this screen builds a new one once the other is gone.
- **An ordinary lesson may recommend lessons too**, with `requires` in its own metadata. The same `RequirementsRow` (`lib/views/components/lesson/requirements_row.dart`, shared with `requirementsFor`) stands under the title of its first step, through `LessonScreenView._buildHeading`, the one place every kind of step passes. It is advice only; a project refuses one on the whole lesson because its tasks name their own.

**The row under the editor is short of room, so its words are few.** A project's right column is 475px in a 1024px window and never more than 655px. "Naar het bordje schrijven" beside "Herstarten" took 538px, so the row wrapped below a 1150px window and the second line came out of the output. The first button now says "Draai code": the write is how, and a student wants the program to run. The two take 420px. `MicrobitDocsButton` (`lib/views/components/microbit/`) is the third, on all three micro:bit screens, and is a glyph with a tip: with it the row is 497px, and with "Documentatie" written out 635px.

**On the machine, what is under Run scrolls on its own.** Beside the tasks the machine's card and the run's report are a scroll view of their own, so the editor and Run stay where they are; stacked, they are part of the page. The micro:bit column ends in its terminal instead, which takes what is left of the column.

**Every link to the MicroPython documentation goes to its front page**, the button's and the ones in the lessons alike. A reorganised site breaks a link to one module's page, and finding the page is left to the student on purpose.

### Running Python

`lib/services/python/` picks a host through a conditional import. The web host is the only one that exists; everything else, including the Dart VM `flutter test` runs on, falls through to `python_runtime_stub.dart`, which reports `isSupported == false` rather than throwing.

`PythonRuntime` is named for what it is. A second language means a second runtime beside it and an interface above them both — not renaming this one. `PythonAttemptRunner` sits on top and is the only thing that should call `run()`: it wraps the student's code and the section's validator into **one** program, because the checks must see the exact output that run produced. A validator-less `attempt` is a plain run, which is what a `predict-output` step is.

**The interpreter names itself.** `PythonRuntime.version` is what `python -V` printed inside the loaded build — the worker asks once at startup and reports it with its `ready`, so the strip over the editor cannot claim a CPython the app is not shipping. It costs one extra instantiate (~4ms) beside a 7 MB compile. It is null wherever there is no host to ask — the stub, and so every widget test — and a caller MUST have something to show in its place: the lesson screen falls back to `subjectLabel()`, the same name without the number.

The student's source is carried into that program as **base64 of JSON**, never interpolated. Interpolation needs escaping their code can always defeat — a triple quote, a stray backslash — and base64's alphabet contains no quote, so the payload cannot terminate the literal holding it. `test/services/python_attempt_runner_test.dart` runs the wrapper through the machine's own `python3` (skipped when absent), so the capture, traceback trimming and `output` stripping are tested without a browser.

**The wrapper replaces `main.py` with the student's own source before it compiles it.** The worker runs the wrapper *as* `/main.py`, and the student's code is compiled under that same name, so CPython read every traceback line, and a `SyntaxError`'s text and caret column, back from the wrapper: each error quoted `import base64, …` and pointed at the wrong column. The script is already parsed by then, so the file can hold what was actually compiled. The host tests and `tool/try_lesson.dart` run the wrapper as `main.py` in a directory of its own for the same reason; with `-c` there was no such file, which is how this went unnoticed.

### Running Python interactively

The console under *Extra* is the **real** CPython REPL: one `python -i -u` process that lives for the whole session, parked between lines. `x = 1` on one line is still there on the next because it is the same interpreter, not because anything is replayed.

Three pieces make that work, and none of them is optional:

- **`web/python/stdin_channel.js`** — a `SharedArrayBuffer` ring. CPython's `fd_read` is synchronous, so the worker has to *block* inside it, and `Atomics.wait` is the only primitive that parks a thread without unwinding it. The page MUST be the writer and the worker the reader: `Atomics.wait` throws on the main thread, and a parked worker never reaches its event loop, so a `postMessage` to it would never be read. Same arrangement as swiftwasm/uwasi and cryptool-org/wasm-webterm.
- **`web/python/python_repl_worker.js`** — starts the interpreter and then never returns. It can be sent exactly one message, `start`, and never another. Output still leaves by `postMessage`, batched, and flushed just before each read so a prompt never sits in a buffer while the student waits.
- **`lib/services/terminal/line_editor.dart`** — the line discipline. A tty driver echoes, edits and hands over whole lines; CPython's basic REPL counts on that and does none of it. This is that half, including the `\n` -> `\r\n` translation (`cookOutput`) without which every line steps across the screen.

`-i` is what forces the interactive loop even though stdin is not a terminal — without it CPython reads stdin to the end and runs it as a script. `PYTHON_BASIC_REPL=1` keeps the 3.13+ PyREPL out of it; that wants termios and would fall back anyway, but asking outright means the behaviour does not depend on how the probe happens to fail.

**`stdioIsTerminal` is what turns the colour on, not `TERM`.** wasi-libc's `isatty()` answers no for a character device that is *seekable*, and the shim hands out every right by default — so CPython saw a redirected file and dropped its colourised tracebacks. The REPL worker withholds `FD_SEEK` and `FD_TELL`, and **`python_worker.js` deliberately does not**: the lesson screen renders its output as plain text, where the same escape codes are only noise.

**Nothing can interrupt a running program.** wasm has no signals, so Ctrl-C at a fresh prompt throws away the typed line — all a line discipline can do — and anywhere else, busy or part way through a block, restarts the interpreter and says so. No `KeyboardInterrupt` is ever printed, because Python never raised one. The controller tells the two cases apart by reading the last prompt off the screen, which is where a terminal has always got it. That same prompt is what Ctrl-C and Ctrl-L write back, because the interpreter never saw either key and prints no new one.

**The keys are readline's**, in its default emacs mode, because that is what `python3` in a terminal answers to. The reference is a real REPL in a pseudo-terminal with `PYTHON_BASIC_REPL=1`, not a guess: check a new key there before changing `LineEditor`. Three things in it are easy to get wrong:

- **Ctrl-D ends the input for one read.** It travels in the ring as a `0x04` byte, the way a tty carries VEOF: the read that reaches it returns nothing, and the next one waits as usual. So at `>>>` the interpreter exits, and in `input()` or `sys.stdin.read()` the program gets its end and the session goes on. It was the end of the stream for good once, in the ring and in `wasi.js`, which took the whole session down after any EOFError.
- **Tab inserts a tab, after a word break only.** Readline completes a name there, which needs the interpreter, and it is parked in the read. What is left is what rlcompleter does where there is no name: insert a tab.
- **Ctrl+A is the start of the line on every platform** (`ReplTerminal.passesCtrlA`). xterm makes it select all on Windows, Linux and ChromeOS, so select all moves to Ctrl+Shift+A there. The micro:bit screens keep xterm's default.

**A terminal has the code editor's way out.** xterm sends Tab and Shift+Tab to the program and reports them handled, so `ReplTerminal` is a keyboard trap without it (WCAG 2.1.2). Escape, then Tab or Shift+Tab, moves on, and the corner of the terminal says so while it has the keyboard. Unlike `EscapeThenTabExit`, the Escape is held back until the next key and sent ahead of any key but Tab: sent at once, it would reach the program as the start of a sequence and take the first key typed on return with it. Every terminal in the app has it, the micro:bit screens included.

The terminal itself is **xterm** (`TerminalView`), so the escape codes CPython emits are handled by a real emulator rather than by the subset we happened to think of. Its sixteen ANSI colours live in `lib/theme/terminal_palette.dart`, deliberately *not* in `AppSemanticColors`: those are roles a caller picks by meaning, and these are numbered slots the running program picks from. One palette covers all four schemes because every preset's code surface is dark, and `test/theme/terminal_palette_test.dart` holds that to WCAG AA.

### The Rust core

`rust/` is the app's non-Dart half: a crate compiled to WebAssembly and reached from Dart through **flutter_rust_bridge**. `docs/rust-core-build.md` is the build, the pinned toolchain and the traps; **read it before touching `rust/`, `web/pkg/` or the bridge config.** `docs/microbit-usb.md` is the hardware it talks to and what it works around.

Everything in it today serves one subject — a BBC micro:bit on the other end of a USB cable: the transport, the ARM debug stack, the flash logic. It is **not** named for that, deliberately, for the same reason the app is not named for Python. A second subject moves the micro:bit modules under a `microbit::` of their own, and nothing outside the crate changes; pre-building that layer for one occupant would be the same mistake as pre-promoting a widget.

Rust rather than Dart because `nusb` already has backends for WebUSB, usbfs/Android, WinUSB and IOKit behind one API, so Android and desktop are a transport arm rather than a second implementation of 2200 lines of debug protocol. **iOS is permanently out of scope** — Apple gives App Store apps no USB host API, and no library version changes that.

**Nothing the core generates is committed**, the crates' licence texts aside (see *Licences*). `lib/src/rust/`, `rust/src/frb_generated.rs` and `web/pkg/` are all gitignored, and one workflow builds and checks the whole thing on every PR and every deploy. A cold wasm build is about a minute, which is what `-Z build-std` costs; `Swatinem/rust-cache` keeps `rust/target` between runs. `assets/python/python.wasm` stays committed because that one is a fifteen-minute CPython cross-compile, not a minute of cargo.

Everything under `web/` is copied into the build, so `web/pkg/` needs no `pubspec.yaml` entry and `RustLib.init()` finds it at `pkg/`.

**`build-web` sets `RUSTUP_TOOLCHAIN` to the rolling `nightly`, which overrides `rust/rust-toolchain.toml`.** The pin does nothing unless `--wasm-pack-rustup-toolchain` is passed too, which `just build-rust-core` does, reading the channel out of the toolchain file so the two cannot drift.

Three rules constrain the bridge API, all three from the environment and none of them taste:

- **No `#[frb(sync)]` function, ever.** A sync call runs on the Dart main thread, `std::sync::Mutex` compiles to `memory.atomic.wait32` under `+atomics`, and browsers throw on `Atomics.wait` from the main thread.
- **A device may not be held between calls.** flutter_rust_bridge hands each call to an arbitrary worker from a pool, and the `JsValue` inside nusb's `Device` cannot be transferred between workers. Anything holding a device open lives on one long-running session function's own stack, fed by a queue.
- **`requestDevice()` exists only in `Window` scope**, while `getDevices()` also exists in a worker. So Dart asks for permission on the main thread and Rust picks the device up with `list_devices()`.

The Dart side is `lib/services/microbit/`, shaped like `lib/services/python/`: a conditional import with the **stub as the default clause**, so the Dart VM that `flutter test` runs on gets `isSupported == false` rather than an exception. `WebMicrobitLink` owns `RustLib.init()` and is the only thing that may call it — loading the core is **not** an initialization step, because a student who never plugs in a board must not wait for it or be shown its failure. It is created by the screen that uses it and is deliberately not in `setupServices()`, the same as `PythonRepl`.

### Licences

The app is under MPL 2.0, the `LICENSE` at the repository root. `LicensesScreen` (`/licenses`, reached from *Over deze app*) shows that licence and the licence of everything the app ships. `docs/licenses.md` says where each text comes from and what was checked about them going together. **Read it before adding something the app ships that is not a pub package or a crate.**

It is the app's `LicensePage`, which is Material. Everything still goes through Flutter's `LicenseRegistry`, which is not:

- **Flutter's NOTICES** covers the pub packages and the engine. The app is a package too, so the root `LICENSE` is in there under `kAppPackage` without anything being done for it.
- **`kBundledLicenses`** (`lib/services/licenses/`) is the rest: CPython and what it is linked against, the crates, the firmware, the fonts. Each is a text file shipped as an asset, beside what it is the licence of. `registerBundledLicenses()` adds them from `setupServices()`, and reads nothing until the screen is opened.
- **The VM image's `NOTICES.txt`** is not an asset. It is served beside the build in `web/vm/image/<imageId>/`, so `registerBundledLicenses()` adds it as a fetch (`loadVmNotices`), and only when `vmImageIncluded`. It is one component, `kVmImageComponent`, under *Tkinter*, whether or not the toggle is on: the build ships the image either way. The fetch is held to the size the manifest gives, because the dev server answers a missing file with `index.html`.

Things that are easy to get wrong:

- **The Rust texts are committed, and CI holds them.** Rust has no registry of its own, so `just gen-rust-licenses` collects them with cargo-about into `assets/licenses/`. That is the one thing the core generates that is in git: `flutter test` has to pass on a checkout that never built the core. `just check-rust-licenses` fails CI when they are stale, so run the first after a `cargo update` or a toolchain bump.
- **`accepted` in `rust/about.toml` is the gate.** A crate under a licence it does not name fails the run. That is what keeps copyleft out of a `cargo update`. Nothing does the same for a pub package.
- **A text is shown as its author wrote it**, line for line in the code face. `LicenseEntry.paragraphs` rejoins lines, which turns the table in a licence into one run of words.
- **`LicenseCatalog.load` does not `await for` the registry.** That cancels on the first error, in the middle of the registry's `addStream`, and under a widget test's fake clock the cancel never completes.
- **The test binding registers no licences.** `LicenseRegistry.licenses` is empty in a test until the test adds to it, so a test of the real texts reads `NOTICES.Z` out of the bundle.
- **The screen links to the source**, `kSourceUrl`. MPL 2.0 has every build say where its source is.

### About

`AboutScreen` (`/about`, *Over deze app* in the cog) says which build this is: the app's version, the source, the licences, the toolchains and the runtimes. The licences are reached from here and no longer from the cog, and their trail leads back through it. Each value comes from the build itself, never from a constant someone has to remember to bump:

- **Flutter and Dart** are `FlutterVersion`, from defines the flutter tool passes to every build.
- **Rust** is `web/pkg/rustc-version.txt`, the `rustc -V` that `just build-rust-core` writes beside the wasm. It is fetched like `version.json`, so showing it does not load the core, which only `WebMicrobitLink` may do. A `web/pkg/` built before the recipe wrote it says "Onbekend" until the core is rebuilt. The dev server answers a missing file with `index.html`, which is why the fetch only accepts text that starts with `rustc `.
- **Python in the browser** is `PythonRuntime.version`, and the screen **loads the interpreter** to ask, the way a step that runs code does on arrival.
- **Python with Tkinter** is the `interpreter` the VM image's `manifest.json` names (`loadVmManifest`), which the saved machine reported when it was built. Reading it downloads nothing of the machine. The row is there while `tkinterShown` is.
- **MicroPython** is `kMicrobitFirmwareVersion`, which names the asset as well and MUST match `just fetch-microbit-firmware`.
- **Runs as** is `kIsWasm`. No build passes `--wasm` yet (see the workflows), so it says JavaScript.

### The Tkinter page and the VM

`/learn-python/tkinter` runs a program with Tk windows on a real Linux that v86 emulates inside the page, and a project on `runtime: tkinter` runs its program on the same machine through the same session. Everything below the Dart side, the image, the agent, the protocol and `web/vm/vm_host.js`, is `docs/vm-build.md`; its *Flutter side* section is what the Dart side binds to. `vm/README.md` is the runbook for building, updating, checking and publishing the image. Like the console the page records nothing and checks nothing, and it sits under *Extra* where `subjectHasWindows` says the image can run the subject, in a build that ships the image and while the `tkinter` feature toggle is on (`tkinterShown`). The toggle hides what leads there and nothing more: the address still opens the page.

`lib/services/vm/` is shaped like `lib/services/python/`: `VmRuntime` behind a conditional import with the **stub as the default clause**, so the Dart VM `flutter test` runs on gets `isSupported == false` and a widget test can build the page's "not in this browser" state. `WebVmRuntime` reaches `web/vm/vm_host.js` and `vm_screen.js` through `importModule(absoluteUrl(...))`; `absoluteUrl` lives in `lib/services/web/` now that two services need it. `parseHostEvent` is the one place a host event becomes a `VmEvent`, and it is platform-neutral so `test/services/vm_host_event_test.dart` can hold it to the host's shapes.

**The machine half is one session, and two screens hold it**, the way `lib/views/components/microbit/` serves the micro:bit screens. `VmSessionViewModel` and `VmSessionController` (`lib/views/components/vm/`) are the editor's program, the machine, the runs and everything they report. The Tkinter page holds one as `machine` on its view model and its controller, and keeps only its sample, its draft and its navigation; a project on `runtime: tkinter` holds the other (see *Projects*). Beside them are the widgets both screens draw a session with: `VmRunDialog`, the program over the page while a run is up; `VmMachineCard`, the download and every way the machine can be missing or broken; `VmRunReport`, the notices and the output; and `vmStatusLabel`, the editor's strip. Under those sit `ProgramDialog`, `WindowFrame`, `WindowStrips`, `NoWindowPanel`, `VmDisplay`, `VmLoadPanel` and `RunNotice`. `VmSessionController.onWindowShown` is the one part the page leaves unused: it is a project's gate. The points below say "the page". One about the page's own layout or its draft is about the page alone; every other holds for a project on the machine too, and says so where the project differs.

- **A build without the image does not offer the page.** `web/vm/image/` is gitignored and fetched or built on its own, so `vmImageIncluded` (`lib/services/vm/vm_image.dart`) is `bool.fromEnvironment('ICC_VM_IMAGE')`, false unless the build passes `--dart-define=ICC_VM_IMAGE=true`. Off, the *Extra* card is gone, `createVmRuntime()` hands out the stub, and the address shows "not in this version of the app" with nothing downloaded. A build MUST pass it only when the image is there: without one every download is a 404, which the page can only word as the student's connection failing. Every `.vscode/launch.json` configuration passes it, for the image `just build-vm-image` leaves in place; without one, that page shows the download failure and the rest of the app runs as usual. `flutter test` passes nothing, so the page as it ships builds its "not in this version" state there. Such a build still lists a project on the machine whose toggle is on, since only the toggle hides it, and the project opens on the same state. `just build` passes it when `web/vm/image/manifest.json` exists, and the deploy when `vm/image.lock` pins an image, which it downloads and checks against the pin first; no pin exists yet, so the deployed site leaves the page out (docs/vm-build.md, *Publishing the image*).
- **The page's Python is Alpine's, not the lessons'.** The image runs whatever Python its Alpine release ships, 3.14 on 3.24, while the lessons run the CPython 3.15 this repository builds for `wasm32-wasi`. Nothing holds the two to one version. The page and the about screen each name the interpreter they actually have, so neither claims the other's.
- **The page creates the runtime and disposes it when the page goes**, through its `VmSessionController`. Not in `setupServices()` and not an initialization step: the first open downloads about 17 MB, and the app with a parked machine measured a 500 MiB renderer in Chrome. Parking gives none of that back; disposing does. Retry after a failure builds a new runtime instead of reloading the old one, because a host that failed after it was ready stays failed. The host keeps one machine per tab and a second page's `openVm()` destroys the first's, which fails as `replaced`. So the catalog pushes the Tkinter page only while none is on the stack or on its way. Nothing guards a project like that, because one project opens another over itself on purpose (a task's requirement), so the sessions settle it among themselves instead: the machine belongs to the newest `VmSessionController` still standing, as the bar belongs to the last screen still standing (see *The bar*), and one that goes hands it back. The session under it, if its machine was the one taken, builds a new one as Retry would. It does that in the disposing session's `dispose`, after that machine is freed, so the new one takes nothing from anyone.
- **A run ends for one of seven reasons, and four of them say nothing about the program.** `VmExit.stopped` MUST NOT read as a verdict: a stop draws no notice at all. `VmEndReason.isHarnessFailure` (`unresponsive`, `fetch`, `broken`) MUST NOT read as the student's mistake: those notices sit on a plain card, not the warning surface, and open with "Dit lag niet aan je programma". A reason the page does not know parses as `broken`.
- **Run supersedes, and Run during the download waits.** The run goes to the runtime at once and starts when the machine is ready; a second Run ends the first as stopped. The controller drops every event whose run id is not the current one, so nothing of a superseded run lands on the page.
- **Nothing on the page moves while a program runs.** v86 runs on the main thread, and the bench measured 6 ms of page work per frame leaving it 3 % of its speed at 4× CPU throttling. So no spinner and no easing (`VmLoadPanel` sets its bar per report), output reaches the card every 200 ms (`VmSessionController.outputInterval`) rather than per batch, and the card lays out only the last 20,000 characters. Run moves focus into the display, which also stops the editor's caret. `test/views/tkinter_widgets_test.dart` leaves a running page alone for three seconds and asserts no frame was asked for, and `test/views/project_screen_test.dart` does the same for a project, once with a task's confetti still falling.
- **The page is one column and the program is a dialog over it.** The editor has the page's own measure, the way the console's terminal does, because a column wide enough for an 800 × 600 window left the editor a third of the page and everything on it hard against the left edge. `VmRunDialog` is up for exactly as long as a run is — the download included, since a Run pressed then waits — so the display and its platform view exist only while there is something to show in them.
- **The cross on the dialog ends the program**, rather than asking one window to close. It is the one control that always works: a program that ignores WM_DELETE_WINDOW still goes, and there is no second cross to tell it apart from. The window's own close path is still there on the strips other windows get (`closeWindowById`). Run is Stop as well, behind the dim, for anyone who reaches it by keyboard.
- **The page behind the dialog is out of reach three ways, and the third is not manners.** The dim absorbs the pointer; `ExcludeFocus` keeps Tab travelling from the display to the cross and on into the bar; and `BlockSemantics` hides the page from the semantics tree. That last one: a semantics element is placed by its rect and the engine puts the semantics host over the platform view, so with a screen reader on the editor's own `flt-tappable` element covered the display, and v86 drops a mouse event whose target is not inside its screen box (`may_handle` in `libv86`). Every click on the program was lost, silently, and only with a screen reader on.
- **The frame is Flutter's**, because the guest runs no window manager. `WindowFrame` names the root window, or the topmost mapped one when the root is withdrawn, and it is the dialog's strip.
- **The page shows the program's windows, not the 800 × 600 screen.** `windowRegion` is the smallest rectangle around every mapped top-level of the latest WINDOW, each clipped to the screen: a dialog widens it, closing the dialog shrinks it back, and a window that moves or resizes moves it in the same frame, with no animation. The frame hugs that region at `displayScale`, never above 1, preferring a scale that lands on whole device pixels when that costs at most 15 %, and is never narrower than `WindowFrame.minWidth` so the strip holds a title, the way out and the close button. `VmDisplay` passes the region and scale to `showRegion`, and `vm_screen.js` moves v86's screen box inside a clipping box rather than cropping the canvas: v86 maps clicks through that box's bounding rect, so they land at any crop and scale. With no window the frame takes a fixed `WindowFrame.emptySize` and `NoWindowPanel` covers the display, which stays built beneath it because Run gave it the keyboard before any window existed. Run asks for that keyboard a frame before the display exists — a `FocusNode` asked while it is out of the tree takes focus as it arrives — and `VmScreen.focusElement` waits out a few animation frames for the view's element to reach the page, since DOM focus cannot go to an element the document does not hold yet. Menus and combobox lists are override-redirect and not in WINDOW, so one that reaches past the region is cut off until the agent reports them (docs/vm-build.md, *Not done*).
- **`input()` raises EOFError**, since stdin is "later" in the protocol. The page recognises that traceback and suggests an Entry instead of saying the program crashed.
- **An X `BadAlloc` is the machine's limit, not the student's error.** Xorg may grow its heap 16 MiB past its warm size, and Tk backs a Canvas with a pixmap the size of what it redraws, so a 3000 × 3000 canvas ends the program with Xlib's `X Error of failed request: BadAlloc`; a 1920 × 1080 one draws. The page recognises that line the way it does the EOFError, and says on a plain card that the window or canvas is too large for the 800 × 600 screen.
- **The failure card words the reason, never the host's message.** `VmFailure` picks the title and body in the page's language; the message is the host's English and stays folded under "Technische details" (`NoticeCard.detailLabel`), for whoever helps the student.
- **The download is one per image, resumable, and kept.** The state comes down in 2 MiB Range pieces, each kept in the Cache API as it lands, so a school Wi-Fi that drops, or a reload, resumes where it stopped; a server that answers a Range with a 200 (`flutter run`'s dev server) gets one plain GET. Every caller on the page joins the one download in flight, `openVm()` and `prefetchBundle()` alike, and hears the same progress. The byte counts MUST come from the manifest's sizes, never from `Content-Length`, which is the compressed size wherever the server compresses. `navigator.connection` is a hint the panel may word, never a figure it quotes, and `navigator.storage.persist()` is asked for only in Chromium, which does not prompt; Firefox would. What starts a download before the page opens, and the catalog tile that shows it, are a separate design and not built: nothing calls `prefetchBundle()` yet. docs/vm-build.md, *The host*, has the rest.
- **The loading panel says what the student waits for, calmly and without moving.** `VmLoadPanel` names the step (download, unpack, start), the bytes, and once measured the speed and a coarsely rounded time left, plus at most one note (a stalled connection, no room to keep the machine, a slow-looking line, a resumed download). The speed line and the note hold the room of their longest wording, so nothing jumps as they arrive; `test/views/vm_load_panel_fit_test.dart` loads the app's real fonts to hold that it fits the frame's empty 480 × 300 in both languages.
- **Only Retry leaves a failure.** `setProgress` is ignored unless the machine is loading. A byte count that trailed `failed`, from a file still downloading when the other one 404'd, put the page back on its loading panel with no card and no Retry; the host now aborts the other download and sends no `progress` after `failed`, and the view model does not count on that.
- **Retry forgets the last run's end.** `setFailed` and `resetMachine` both clear the exit and the hints, because the host ends a waiting run as `broken` before it reports the failure, and that notice would otherwise come back on the new machine.
- **Every run sends a setup beside the program.** `VmProgram.source(setup:)` puts `EditorSettings.tkinterSetup` in `vmSetupFile` (`icc_setup.py`), which the image's prelude runs first and removes; a blank one sends no file. Its default sets `turtle._CFG` for this machine: no pause between frames and a 600 × 500 window (docs/vm-build.md, *Turtle*). A cold interpreter, after a failed park, has no prelude and skips it.
- **The editor is kept as a draft** in `CodeDraftStore`, the lessons' own store, under the page key `draft.tkinter.<subject>`: a tab this heavy is the first one ChromeOS discards under memory pressure, which is why the page flushes on `onHide` as well as on Run and on leaving. The sample is not a draft, and "Voortgang wissen" clears this one with the rest.

**`VmDisplay` is the workaround widget for the platform view**, per *Workarounds get their own widget*, and its class comment lists every engine behaviour it leans on. In short: `ExcludeFocus` around the `HtmlElementView` and one `FocusNode` that stands for it; every key answered with `skipRemainingHandlers`, so the app's shortcuts never see it and v86's bubble-phase listener still does; **Escape then Tab leaves**, with the guest's keyboard switched off synchronously in that Tab's handler, and the frame states the way out while the display has focus (WCAG 2.1.2); `holdsTab` is what holds it, and it is on wherever the display is, since the display outlives no run; DOM focus and Flutter focus follow each other, and losing focus moves DOM focus to `flutter-view`, never `blur()`; a pointer down requests focus before the browser's own focus lands, and gives the keyboard back to a node that kept focus without it; the wheel is claimed. **One display per machine**: `VmRunDialog` keys it with `GlobalObjectKey(controller.display)`, so a display rebuilt elsewhere in the tree keeps its platform view instead of building a second one. A display that does replace another takes the keyboard as it binds, and the old one's unbind, which comes later, leaves a binding it no longer owns alone; in Chrome that is not enough on its own, because DOM focus leaves with the old view's element, so the global key MUST stay. **The mouse is gated by hit test**: a global pointer route turns v86's mouse on only for events this widget's `Listener` saw, so a popover or dialog drawn over the display takes its own clicks. Its `Focus` adds nothing to the semantics tree, because with semantics on the engine moves DOM focus onto a focused node's element, and that took the keyboard from the guest. `just check-vm-app` holds all of this in headless Chrome: it drives the built app with real clicks and keys, with a screen reader's semantics on and off, and the dim and the settings menu over the display included.

`flutter test` cannot build an `HtmlElementView`, so the view comes from an injectable `VmViewBuilder`, which `TkinterScreenView` and `ProjectScreenView` take too; `fakeVmView` (`test/support/fake_vm_runtime.dart`) is the one the tests pass. Two traps in the page's widget tests, and in a project's: an `Observer` invalidated in the middle of a frame waits for `endOfFrame` before it rebuilds, so a test pumps twice after the machine sends an event; and re_editor starts its caret from a 100 ms timer that nothing cancels, so a test pumps 150 ms after building the page. A third, in `tkinter_widgets_test.dart`'s own host: its `Overlay` builds the child it was *first* given, so `pumpWidget` with another child changes the `MediaQuery` above it and nothing below it. A test that swaps a widget goes through a `ValueNotifier`.

### Localization

ARB files in `lib/l10n/` (`app_en.arb`, `app_nl.arb`), generated output in `lib/l10n/generated/`. Key convention is `screenOrWidgetName_short_description`. Run `fvm flutter gen-l10n` after editing.

Reach strings through `context.localizations.myKey`, adding `import 'package:i_can_code/extensions/build_context_extension.dart';`.

**The device locale is the default**, offered in the cog as "Apparaattaal". Dutch is not the default but it *is* the fallback: `supported.first` is what `WidgetsApp` resolves to for a device speaking neither Dutch nor English, so the course's own language still has the last word.

`LocaleController` holds a **nullable** `Locale`, and null means "follow the device". It goes to `WidgetsApp.locale` as-is, so Flutter does the resolving against `supportedLocales` and lands on its **first entry** when the device has none of them. That ordering is load-bearing: `supported.first` is the fallback language, not just the first menu row.

The choice is persisted (`locale.language`) beside the theme mode, and "follow the device" is stored as the sentinel `system` rather than by clearing the key, so switching back to it is a write like any other. It resolves to the same thing an absent key does, which is what makes "never picked" and "picked the device" behave identically. Both stores are awaited by `main()` before `runApp`; the initialization screen is themed *and* localized, so reading either later makes it paint wrong and flip.

## Code style

### Class body padding

Every class, extension and mixin body has a blank line after the opening `{` and before the closing `}`:

```dart
class MyClass {

  final String myVar;

  void myMethod() {
  }

}
```

This applies everywhere: widgets, state classes, abstract classes, generated-code companions.

**`dart format` strips these**, verified on Flutter 3.47.2. The rule wins: `lib/theme/app_theme.dart` and `lib/theme/presets/thuas_palette.dart` are kept out of the formatter for this reason. Do not run `dart format` over a padded file and call it a cleanup.

### Comments

Write comments where the code needs clarification — never to narrate what it does. Keep sentences short. Use RFC 2119 keywords (MUST, SHOULD, MAY) when a comment states an obligation, such as a precondition a caller has to meet.

## Key configuration

- **Line length**: 120 (`analysis_options.yaml`), a guideline rather than enforced
- **Linting**: 50+ rules on top of `flutter_lints`; run `fvm dart analyze` before pushing
- **Git**: never `git commit` or `git push` unless explicitly asked. All other Git subcommands are fine.
