# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**I Can Code** — a **web-only** Flutter app that teaches programming. Assignments are plain files under `assets/lessons/`; the student's code runs in the browser. No backend, no login, no persistence.

Two things it is deliberately **not** scoped to:

- **It is not a Python app.** Python is the first language it teaches and the only runtime that exists so far (CPython built for `wasm32-wasi`), but the app is meant to teach others. Keep Python out of names, copy and marks that are not specifically about running Python — the app mark is `</>`, not `py`.
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
fvm flutter build web                   # build

fvm dart run tool/try_lesson.dart <lesson.md>                       # list its sections
fvm dart run tool/try_lesson.dart <lesson.md> <n> --code 'print(1)' # run one, see the verdict
```

`try_lesson.dart` runs a section through the **real** `PythonAttemptRunner`, so a lesson can be written and checked without the app. It uses the machine's own `python3` rather than the `wasm32-wasi` build the app ships, so check `python3 --version` before trusting a result that turns on a language feature.

After touching any `@observable` / `@readonly` / `@action`, `@freezed`, `@RoutePage()` or `@TailorMixin` annotated code, re-run `build_runner`.

### `sdk:` in pubspec.yaml is the *language version*, not the SDK

It is what the compiler allows this package's own source — generated code included — to use, and it is why the generator versions are pinned exactly.

It sat at `^3.12.0` for a long time: Dart 3.13 dropped `final` on constructor parameters, which `freezed 3.2.5` still emitted, so declaring 3.12 kept that syntax legal. `freezed 4.0.1` no longer emits it, and both `freezed 4.x` and `theme_tailor 4.x` declare `sdk: >=3.13.0`, so it is now `^3.13.0`.

Watch the same trap if a generator ever has to be held back again: `dart analyze` accepts code the compiler rejects, so **lint stays green while every build and test fails**. Verify a version bump with `fvm flutter test` and `fvm flutter build web`, never with `dart analyze` alone.

`mobx_codegen` is the package that gates the analyzer version for everything else — it capped `analyzer <13` until 2.7.8 widened it to `<15`, which is what unblocked freezed 4.x. Check it first when a generator refuses to resolve.

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
- **The bar belongs to the last screen still standing**, not to whoever spoke last. More than one screen is mounted at a time: a pushed screen leaves the one under it standing, and a replaced one is disposed only *after* its successor is built. So the host keeps a claim per screen in arrival order — bottom to top of the page stack — and a screen that leaves hands the bar back to the one underneath instead of emptying it. Emptying on release is what left the language picker with no bar at all once the catalog above it was closed: auto_route keeps the page it already has, so nothing publishes on the way back down.

**Zen mode.** A lesson is read, so its bar starts out of the way: on a screen whose header says `offersZen` — only the lesson screen — the bar is gone when the lesson opens. It is **one thing the reader turns on and off, by a button each way**: the host floats one in the band the bar left behind to bring it back, and the bar carries one to put it away again. The answer is scoped to the lesson being read — **every lesson opens without the bar**, because asking for it back was about the lesson in front of the reader and not about every lesson after it — and it is not persisted either, since reading one lesson without the chrome is not a setting about the app.

Three rules behind that shape:

- **Nothing reveals the bar by itself.** It was a band along the top edge that the pointer reached into once, and a bar that came and went with the pointer moved the page under the reader's hands. With a button each way the bar only ever appears because the reader asked.
- **The page keeps its box.** It has the whole window whether the bar is showing or not, and the bar is drawn *over* it. Insetting the page instead reflowed the lesson on every press of either button, and cut what was scrolled past against an invisible edge with empty space above it.
- **A hidden bar must leave a way back.** The floating button waits in the band the bar left behind, in the cog's own column and at the cog's own height, so pressing it puts the cog under the pointer without either of them having moved — and it is a real focusable button, reachable by pointer, touch and tab alike. Meanwhile the bar itself is taken out of the focus *and* semantics trees, because off screen is not gone: it would otherwise still be read out and still take the tab meant for the page.

**The page runs under the bar and pads for it itself.** The host gives every screen the whole window; what keeps a first screenful clear of the bar is `AppHeader.height`, added to the screen's own scroll padding — which is why that constant appears in three views. Everything scrolled past then passes under the bar instead of being cut off above it.

**The bar's contents stop at `breakpoints.xl`**, centred, while its surface stays full width — it is the top of the window, not a card in it. `xl` (1280) is the first Tailwind step that clears the widest column the app lays out, a lesson's two-column step at `1120 + 26`, so on a wide monitor the cog sits at the edge of the widest page instead of out in a corner. `AppHeader.chromeInset()` is that same measurement, and the host stands the button that brings a hidden bar back on it, which is what keeps the two in one column at every width.

**The version is named once, on the home screen**, beside the mark and not inside the app crumb — the crumb is the app's *name*, and a version tacked onto it would be read out as part of it on every screen. The two are set at different sizes on one line, so the trail aligns them on their **baseline**; centring their boxes leaves the smaller one sitting low. `appVersion` (`lib/app_info.dart`) reads it back out of the running build through `package_info_plus`, so it cannot drift from `pubspec.yaml` — on the web that is a fetch of the `version.json` the build writes beside `index.html`, same origin and so untouched by cross-origin isolation. `main()` awaits `loadPackageInfo()`, which registers the `PackageInfo` in GetIt; it is **not** an initialization step, because that screen's failures are fatal and a version string is not worth failing a start over. It is null when there is nothing to show — the plugin answers empty strings rather than throwing when `version.json` is missing, and a widget test registers nothing at all — and the bar then omits it.

`HeaderIconButton` is the icon button all three are — the cog, and the two that hide and show the bar. Not `AppButton.icon`, which is padded `19 × 19` to stand beside a line of text and is far too big for a 76px bar.

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

**Every preset has both brightnesses.** `resolve({brightness})` returns the scheme; `buildAppTheme({preset, brightness})` builds it. The mode itself is `ThemeModeController` (`lib/services/`) — system/light/dark, persisted in `shared_preferences` like progress, and swallowing its failures the same way. It is the one thing `main()` awaits before `runApp`, because the initialization screen is itself themed and would otherwise paint light and flip.

`AppThemeMode.brightnessFor(platform)` is the whole decision, so it can be tested without a widget tree. The shell reads it in `_ThemedBody`, which exists as a widget rather than a closure so its `Observer` runs in a real build and so it can see the `MediaQuery` that `WidgetsApp` installs below the state above it.

**A fill token is not a text token.** `primary` is a fill: the neutral accent is 1.2:1 on the page and the THUAS green 2.63:1 on white, so neither can carry text. That is why `link` is a role of its own in `AppSemanticColors` rather than reusing `primary` — and why prose links are underlined as well as coloured. The THUAS house style has *no* colour that works as link text on white; it uses the mid grey, and the underline is what makes it a link.

`test/theme/theme_test.dart` asserts every pairing across **all four** schemes (2 presets × 2 brightnesses). `test/theme/palette_test.dart` renders a real card and asserts that more than 1% of its pixels carry colour — the tripwire for a preset silently coming out greyscale, which is what shipped when the app was pinned to forui's neutral scheme and measured 0.00%.

**Every rounded corner is a squircle.** Draw one with `squircle(radius)` from `shape_metrics.dart` and a `ShapeDecoration` — never `BoxDecoration.borderRadius`, which can only make a plain rounded rectangle. `kSquircleScale` converts the design's CSS radii to `ContinuousRectangleBorder`'s tighter curve; it is the one number to turn if corners look wrong. A continuous rectangle does **not** clamp an over-large radius — past half the shortest side it bows inward — so a small square tile uses `squircleOf(radius, size:)` instead.

The **one** exception is the tick on a finished catalog row (`CompletedBadge`), which is a `CircleBorder`. The rule is about corners, and that badge is a lamp: a flat disc lit by three stacked shadows — a tight core, a halo and a wide bloom, all at zero offset — because one shadow cannot make a glow. A small blur draws a ring around the badge and a large one thins the colour to nothing, most visibly on the dark card, where a translucent green barely lifts the surface under it. It carries no outline: one was tried and read as a second shape rather than as a crisper edge. It is not the neobrutalist hard offset shadow the preset leaves out either — that is a device of the whole style and would live in the shared metrics.

Every number that badge draws with — its size, the tick and each layer of the glow — is a constant at the top of `CompletedBadge`, because the look is a matter of taste and nothing else reads them. The widget tests hold the *shape* of the thing (a circle, no outline, a glow that spreads and fades outward) and pin none of the values, so tuning one does not turn the suite red.

`progressComplete` is that lamp's colour, and no longer an alias of `success`: "your check passed" and "this is done" are different things, and a deeper green went muddy under a glow. The neutral preset lights it with `NeobrutalismPalette.complete`; THUAS keeps its corporate green, because its house style has no vivid one and a preset may not invent colours it does not own.

`AppButton` exists rather than forui's `FButton` because the design's padding is `38 × 19` against forui's `10 × 11`, and forui fills a button with a `BoxDecoration` that cannot carry a squircle. It is built on forui's `FTappable`, so hover, focus and button semantics still come from the framework.

Its three tones are a rank: `primary` carries the reader forward, `neutral` is the quieter one beside it, `outline` is quieter still and is what a step *back* takes. An outlined button has no fill to fade, so its hover and press tint the page with `neutralButton` instead. Its edge and its label are drawn in that same colour — the one `neutral` is *filled* with, so the two read as one button with and without its fill — rather than in the quiet `border` a card takes, which is too faint against the cream page to say "this is a control". `AppButtonTone.outline` is one button's own edge and **not** the neobrutalist outline the preset leaves out, which goes round everything and would live in the shared metrics.

**A button is a slab, and the body ink is a line.** `neutral` used to be filled with the page's `foreground`; on the light neutral preset that is the near-black `inkLight`, which at 38 × 19 read as a hole punched in the cream rather than as a control. It is now `AppSemanticColors.neutralButton`, a role of its own, so a preset can want its buttons softer than its prose without softening the prose with them. The neutral preset does — `NeobrutalismPalette.controlLight`, the darkest step of the warm grey `inkMutedLight` belongs to — and it is a *light*-scheme answer only: an off-white slab on a dark page is quiet already, so the dark scheme still fills with `inkDark`, and THUAS with a `corporateGrey` that was never black to begin with. The token is a text colour as well as a fill, because the outlined tone has no fill to carry a label, so `theme_test` holds it against the page and a card on top of its own foreground. `AppButton.icon` is the icon-only form; it **requires** a `semanticsLabel`, because there is no text in it to fall back on.

**A button is the same height whatever is in it** — a 20px glyph, a line of text whose height is the font's, or both. `AppButton` settles that in itself: its content is a `Stack` over two invisible, zero-wide children, an empty `Text` in the label's own style and a `SizedBox(height: _iconSize)`, so every button comes out `max(line height, glyph)` tall. Neither is a number stated there — the first is asked of the font through the ambient `DefaultTextStyle`, the second is the app's own icon size — which is the whole point: padding the glyph to match would be guessing at Inter's metrics and would drift the moment the type scale moved.

That is what lets `AppButtonRow` be a **`Wrap`**, so a row of buttons breaks into lines instead of overflowing. It was an `IntrinsicHeight` around a `Row`, which equalised the heights but could only ever do it for one line — and a lesson's three controls (back, Run, Volgende) want ~490px against the 462px the narrower of its two columns has at `lg`, which is the yellow overflow bars over the last button.

**A button must not resize when it starts working.** `AppButton.busy` keeps the label laid out (`Visibility.maintain`) and puts the spinner in a `Positioned.fill`, so neither the label swap nor the spinner's own height can change the button's size. Swapping the label for a shorter "Bezig…" makes the button jump the moment it is pressed, which reads as the layout breaking.

**forui defaults every tappable's cursor to `MouseCursor.defer`**, which on the web leaves the ordinary arrow over buttons, breadcrumb crumbs and the settings cog. `buildAppTheme()` sets it once on `FStyle.tappableStyle`; every widget style inherits from that one, so nothing needs a `MouseRegion` of its own.

Responsive layout goes through **`context.theme.breakpoints`**, which are Tailwind's. The lesson's two-column step stacks below `lg` (1024) and scrolls as one page there; side by side each column scrolls on its own, so reading down the prose leaves the editor and its output where they are. Note that `Expanded(flex:)` is an *integer* ratio against a default of 1 — `flex: 11` is an 11:1 split, not 1:1.1, which is how the prose column once came out one word wide.

`AppSemanticColors` names the roles forui has no slot for — `warning`, `success`, the code editor's surface, the progress bar. **Write a colour there, not inline in a widget**, and read it through `context.appTheme.colors`. Each `*Foreground` is stated next to its fill on purpose: the THUAS corporate green reaches only 2.63:1 against white, so picking a foreground at the call site is exactly how a screen ends up illegible. `test/theme/theme_test.dart` asserts every pairing clears WCAG AA in every preset — **add a pair there when you add a colour.**

`context.appTheme` falls back to the neutral preset when the ambient theme carries no extension (a widget test that builds its own `FTheme`), so it never null-checks.

**Emoji are Noto Color Emoji, bundled, and never the platform's.** `kEmojiFontFamily` is the last entry of `fontFamilyFallback` on every style in `AppTextStyles` and on both of forui's typefaces, so it is reached only for a glyph Figtree, Inter and JetBrains Mono cannot draw. It is a fallback and never a `fontFamily`. Left to the platform the same lesson would show Apple's emoji on a Mac, Google's on Android and Microsoft's on Windows; on the web the engine downloads Noto from `fonts.gstatic.com` per student, on demand, which is the request the other three fonts were bundled to avoid. The COLRv1 build ships rather than the CBDT one — vector, and half the size. Every lesson step carries an `emoji` in its metadata, and so does every lesson — the lesson's fills the tile on its catalog card in place of the order number. A programming language has no file, so its emoji is a case in `languageEmoji()` beside `languageLabel()`; a language the table does not name keeps the initial on its card. See `docs/lesson-format.md`.

Fonts are **bundled** under `assets/fonts/`, not fetched by `google_fonts` at runtime — a font request per student to a third party is both a privacy question and a flash of unstyled text on every cold load. `google_fonts` is still in `pubspec.yaml` but unused.

### Running it

`.vscode/launch.json` holds the run configurations; the app is web-only, so they all are.

Every one of them serves `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp` via `--web-header`, which is what makes the page **cross-origin isolated** and so gives it `SharedArrayBuffer`, WebAssembly threads and `Atomics.wait`. `flutter run` has no dedicated switch for this.

Two things follow:

- `require-corp` makes the browser refuse any cross-origin subresource that does not opt in with its own CORP/CORS header. Everything the app loads is bundled — the fonts included, which is part of why they were bundled — so nothing is at risk today. **Add a CDN script or a remote font and it will fail to load under these configurations only.** The "no isolation" configuration exists to rule the headers in or out when something stops loading.
- `flutter build web` serves nothing, so a **deployed** build is only isolated if its host sets the same two headers. Isolation is a property of the response, not of the bundle. Anything that comes to depend on `SharedArrayBuffer` needs a fallback for when it is absent.

### Addresses

```text
/                                              the language picker
/learn-python                                  that language's lessons
/learn-python/input-and-output                 resume: wherever you left off
/learn-python/input-and-output/print-yourself  one step, named by its section id
```

The step is a **`LessonSection.id`, never a position** — the same reason progress keys on it. A pasted or bookmarked link still opens the step it named after the author reorders the lesson, and an id the lesson no longer has resolves like the bare form rather than showing nothing.

**A page may appear in the route table only once.** auto_route matches on an exact segment count, so the bare lesson address cannot be an optional segment on the route below — and a second `AutoRoute` for the same page throws `Route name must be unique` **when the router is first built**, which is after codegen and after `flutter build web` have both passed. It therefore redirects to the reserved section id `resume`, which no lesson may use; the screen already treats an unknown id as "resume" and rewrites the address to the section it lands on.

`test/routing/app_router_test.dart` builds the router, which is the only place that validation happens. Add to it when you touch the table — a green analyze and a green build prove nothing here.

`/:languageSlug` is a catch-all, so `/initialization` must stay declared above it.

### Progress

`ProgressStore` (`lib/services/progress/`) remembers which sections a student has finished, in `shared_preferences` — which on web is `localStorage`. It is a MobX store, so a tick appears on the catalog the moment a step passes rather than on the next visit.

Two things it is deliberately not:

- **Not per person.** There is no login, so this is per browser. A student who switches machine starts again.
- **Not a record.** Every read and write swallows its own failure — a browser that refuses storage (private mode, storage disabled) must not keep the app from starting. Nothing may depend on progress being correct.

Keyed on `LessonSection.id`, never on a step's position, so a tick survives the author reordering a lesson. See `docs/lesson-format.md`.

### The end of a lesson

The last step does not lead out of the lesson. It leads to the lesson's **end
page** — `LessonCompletePanel`, drawn by the lesson screen in place of a step —
which names what was finished and offers the two ways on: the next lesson, or
the catalog. It is what the "Volgende les" jump hangs off, and the app had no
onward path at all before it.

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
2. **`InitializationScreen`** — work the app does once it is running (reading the course index, compiling `python.wasm`). Shows which step is in flight, retries a bounded number of times, then offers a retry button. The bound matters: everything it waits on is a bundled asset, so a failure means a broken build rather than a server that might come back.
3. **`LoadingOverlay`** — anything a screen waits on afterwards.

### Running a student's code

`PythonAttemptRunner` is the only thing that should call `PythonRuntime.run()`. It wraps the student's code and the section's validator into **one** program, because the checks have to see the exact output that run produced. `AttemptResult` keeps the three outcomes apart — a crash (`programError`), a failed check (`checkMessage`) and a pass — because each needs different words on screen, and `AttemptResult.broken` is a fourth: the runtime is unavailable, which must never read as "you got it wrong".

`tool/try_lesson.dart` drives the same harness from the command line, so a lesson can be checked without the app.

**Run is also Stop.** A program that will not end on its own — `while True:`, or the `sleep(3000)` a student meant as milliseconds — is ended by terminating the worker, which is the only reason the worker exists at all. `RunButton` (`lib/views/lesson_screen/components/`) is the one control both ways, because while a run is in flight starting it is the one thing that cannot be asked for and stopping it is the only thing that can. It keeps its size across the swap by laying both labels out and painting one, for the reason `AppButton.busy` keeps its label — and it carries no spinner, since the strip over the editor already says a run is going and a spinner would cover the word that says what pressing this now does.

**The back chevron always has somewhere to go.** From the first step it leaves the lesson for its catalog rather than being left out — that was the one place in the app with no way back, and in zen mode, where the trail is put away, it left the catalog unreachable short of the browser's own Back button. It is named for where it actually goes, so on the first step a screen reader hears "Terug naar Python" and not "Vorige stap".

**A run belongs to the step it was started on.** `LessonScreenController` stops whatever is going the moment the student moves — `goTo`, the end page, and `dispose` as the catch-all behind the trail, the browser's Back button and the settings menu — and a run token drops the answer that arrives afterwards, so a verdict cannot land on a step it was not written for. **A stop draws no verdict at all**: it is not something the student got wrong, and what the program had printed died with the worker holding it. The runtime **supersedes** a run rather than refusing one; refusing is what left a student who walked away from a long `sleep` with "a program is already running" answered to every attempt afterwards and nothing they could press to clear it.

**A validator can read the code as a tree, not only as a string.** `kCheckLibrary` (`lib/services/python/python_check_library.dart`) is a Python module carried into the run beside the student's source and exec'd into the validator's scope, which is how a validator gets `program.calls("print").with_args(42)` in place of `"print(" in code` — a check that passes for `s = "print(42)"` and cannot tell `print(42)` from `print("42")`. `docs/lesson-format.md` is the author-facing spec, and the names in the library's `__all__` are the contract: adding one means documenting it there.

Two things it deliberately is not:

- **Not a dependency.** It is the standard library's own `ast` and nothing else — `ast.pyc` is already inside `assets/python/python314.zip` and `_ast` is built into CPython — so there is no package to vendor, no asset to declare and no worker change behind it. It is a Dart `const` rather than a file under `assets/` so that `buildProgram` stays static and synchronous, which is what lets `try_lesson.dart` and the widget-free tests drive the real thing.
- **Not a second way to check output.** The tree sees what was *written*, so it reaches a branch that never ran and never sees a value that was computed: `x = 40 + 2` then `print(x)` is a call to `print` with a variable. Check the value in `output`, the shape in `program`. A spy on the running `print` would answer the other half and is the thing to reach for if that half is ever needed.

**A step fences off what it has not taught with `allow_only`, not `disallow`.** `program.allow_only("call")` is a whole early print step's check: calls, and nothing else. A ban has to name everything a student might reach for and misses whatever the language grows next, while an allowlist is a sentence about what the step has taught and stays true. Both take the student's message, and **without one the app says it instead, in the reader's language.** That works because the refusal reaches Dart as the construct's *name* rather than as a sentence: `NotAllowed` carries `icc_construct` out through the verdict into `AttemptResult.disallowedConstruct`, and `AppLocalizationsExtension.checkNotAllowed` phrases it. A Python keyword is the same word everywhere and is set as code, so only the handful with no keyword to quote — call, assignment, comprehension, f-string, bare expression, type alias — need a string per locale, and `test/services/python_check_library_test.dart` runs the library to hold `kPhrasedConstructs` against its own `_PHRASES`. The exception's own text stays the English sentence, because `tool/try_lesson.dart` has no localizations to reach for. Note `match` is a **soft** keyword: `keyword.iskeyword` says no about it, which is why `_is_keyword` asks `issoftkeyword` too. Depth hides nothing and costs nothing: the tree is walked iteratively, and CPython's parser refuses over-nested source before any check runs.

`with_args` is **exact** in its positional arguments, and that is the whole design. Every pattern language that matches one argument at a time gets this wrong — pedal's `print(__exp__)` matches `print("Hallo", naam)` twice — and an author writing "called with one thing" then gets something else. `with_any_args` is the loose one, and it says so.

### Vocabulary

Four words, fixed. Drifting off them is what made the folders disagree with the code once already.

| Word | Means |
| --- | --- |
| **course** | Everything the app ships. `Course`. |
| **lesson** | One markdown file per locale, under `assets/lessons/<language>/`. `Lesson`. |
| **section** | One `##` block of a lesson. `LessonSection`. The student-facing word for it is **step**. |
| **exercise** | A *kind of section* — one that asks for code (`SectionKind.quickExercise`, `exercise`). **Not** a unit of content. |
| **pair** | The two halves of one item on a match-pairs board. `LessonPair`. |

A single run of a section is an **attempt** (`AttemptResult`, `PythonAttemptRunner`). *Assignment* survives only where it names a **block** in a lesson file (```` ```python-assignment ````) and in `SectionKind.isAssignment`; as a word for a step it has been replaced by **exercise**.

A section of any type may be **optional** — a "Verdieping". It is badged and can be skipped, and skipping records nothing: the step stays grey in the progress bar and comes back on the next visit. Optionality is a flag on a section, deliberately not a `SectionKind` of its own, so a Verdieping can still hold an exercise or a board.

**Catalog** and **languages** name listing *screens*, not content, which is why they sit outside the table.

### Lessons

A lesson is **one markdown file per locale**, at `assets/lessons/<language>/<order>-<slug>.<locale>.md`. Metadata, prose, starter code and the hidden validators all live in that one file. The full spec is in `docs/lesson-format.md`. **Read it before touching the format.**

Two things that are easy to get wrong:

- **There is no index file.** Order comes from the `NN-` filename prefix and discovery from Flutter's `AssetManifest`, so the directory *is* the index. Reordering the course is a rename.
- **`Lesson.parse` must keep `encodeHtml: false`.** The `markdown` package HTML-escapes block text by default, which would hand CPython `print(&quot;hi&quot;)` and fail at runtime rather than at parse time.

`test/services/lesson_test.dart` parses every file that ships, so an authoring mistake fails the test run instead of the initialization screen.

**A step does not have to ask for code.** `SectionKind.matchPairs` is a board of tiles the student pairs up — declared `type: match-pairs`, filled from a `pairs` block, and carrying no editor and no validator, because the board itself is the check. It is why `SectionKind.isAssignment` names the two kinds it is true of rather than reading "not `info`": a match-pairs step is neither prose nor an assignment, and the older test would have had the parser demand an editor for a step that has none.

Three things hold that board together, and each is in `PairMatchBoard` (`lib/views/lesson_screen/components/`) rather than in the file format:

- **The deal is derived, never drawn.** `boardOrder()` seeds a `Random` from the section's `id` and shuffles every tile — both halves of every pair, into **one pool** — so the board survives its own rebuilds, one per pick, per hover, per resize, per change of language, instead of dealing itself a new hand each time. One pool and not a block of cues over a block of answers, because a split board tells the student which half of a pair a tile is before they have read a word of it, and that is half of every pair narrowed down for them. A tile is a `PairHalf`, a record, so a pick is findable in a set by value. The one deal it refuses is the lesson's own order, which would stand every pair side by side. Not `String.hashCode`, which Dart promises nothing about between releases.
- **A tile is a square, and the board is one grid.** `tileSizeFor()` spends the step's width on more tiles per row before it spends any on bigger ones: as many across as fit without one falling under `minTileSize`, and never past `maxTileSize`, where a square stops being a tile and becomes a poster. A square has no reading direction, which is what makes a grid possible at all — unlike a bar of text it need not be as wide as the words in it, and four pairs fit in two rows rather than four. Those words are set to the tile for the same reason: a fixed 16px is adrift in a 220px square and spilling out of a 150px one. They scroll *inside* it rather than overflowing, since the square is a box the lesson author cannot see.
- **A wrong pick has no timer behind it.** Both tiles stay showing until the next tap, which starts the pick over. A flash that clears itself would need a `Future.delayed` in the controller and a disposal guard around it, to say something the tiles already say.
- **Colour is never the only answer.** A matched tile takes a tick and a wrong one an ×, and every state's fill is a `*Surface` token, so one text colour stays legible through all four.

What is matched lives in `LessonScreenViewModel` per step, the way typed code does, so stepping away and back finds the board as it was left. It is **not** seeded from `ProgressStore`, which remembers that a step passed and not how: a finished lesson opens on a board that can be played again, with the way on already offered — the same thing an exercise does with its starter code.

**A step may run code the student did not write.** `SectionKind.predictOutput` shows the lesson's own program and asks what it prints *before* it is run — declared `type: predict-output`, filled from a `<lang>-predict` block, and carrying no editor and no validator either. It is why `isAssignment` stays false here: code runs, but the student writes none of it.

**The interpreter is the answer key.** A lesson file states no expected output and has nowhere to put one — `LessonScreenController.predict` calls `PythonAttemptRunner.attempt` with the section's program and *no validator*, and `matchesPrediction` (`prediction_verdict.dart`) holds the answer against what that run printed. An expected output written into the file is one that can drift from the code beside it; this one cannot. `tool/try_lesson.dart` runs a predict step too, so an author can see what their students will be measured against.

Four things that shape it:

- **Trailing whitespace is not a wrong answer, and nothing else is forgiven.** `print` ends every line with a newline no student can deliberately type, and a keyboard leaves trailing spaces nobody can see; both come off. Case, quotes and the space `print` puts between two arguments all count — those *are* the exercise.
- **A wrong prediction still completes the step.** The output is shown either way, with the prediction read back beside it. What decides the tick is that the program ran. Hiding the answer to make the student guess again turns the moment of surprise — the whole reason the step exists — into a lock, and nothing here is graded.
- **The verdict is about a frozen prediction.** `LessonScreenViewModel.prediction` is set when the run starts and is what the banner reads; the box's own controller keeps changing. Reading the box would let a student type the output that is sitting right beside them and watch the verdict flip.
- **The program is a `CodeSample`, never a `CodeEditorCard`.** It cannot be changed, and an editor carries a caret and a text-input connection that invite typing into it. `CodeSample` is the same dark card a worked example in the prose takes — the two are one widget, because both are code that is *read*.

The optional `explanation` block is shown under the answer and to everyone, right or wrong. It is the feedback half of a practice test, and a student who guessed right has learned no more about *why* than one who did not.

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

Flutter's asset globbing is **not recursive**, so every asset directory is listed separately in `pubspec.yaml` — a new folder is silently absent at runtime until it is declared.

### Running Python

`lib/services/python/` picks a host through a conditional import. The web host is the only one that exists; everything else, including the Dart VM `flutter test` runs on, falls through to `python_runtime_stub.dart`, which reports `isSupported == false` rather than throwing.

`PythonRuntime` is named for what it is. A second language means a second runtime beside it and an interface above them both — not renaming this one. `PythonAttemptRunner` sits on top and is the only thing that should call `run()`: it wraps the student's code and the section's validator into **one** program, because the checks must see the exact output that run produced. A validator-less `attempt` is a plain run, which is what a `predict-output` step is.

**The interpreter names itself.** `PythonRuntime.version` is what `python -V` printed inside the loaded build — the worker asks once at startup and reports it with its `ready`, so the strip over the editor cannot claim a CPython the app is not shipping. It costs one extra instantiate (~4ms) beside a 7 MB compile. It is null wherever there is no host to ask — the stub, and so every widget test — and a caller MUST have something to show in its place: the lesson screen falls back to `languageLabel()`, the same name without the number.

The student's source is carried into that program as **base64 of JSON**, never interpolated. Interpolation needs escaping their code can always defeat — a triple quote, a stray backslash — and base64's alphabet contains no quote, so the payload cannot terminate the literal holding it. `test/services/python_attempt_runner_test.dart` runs the wrapper through the machine's own `python3` (skipped when absent), so the capture, traceback trimming and `output` stripping are tested without a browser.

### Localization

ARB files in `lib/l10n/` (`app_en.arb`, `app_nl.arb`), generated output in `lib/l10n/generated/`. Key convention is `screenOrWidgetName_short_description`. Run `fvm flutter gen-l10n` after editing.

Reach strings through `context.localizations.myKey`, adding `import 'package:i_can_code/extensions/build_context_extension.dart';`.

**The device locale is the default**, offered in the cog as "Apparaattaal". Dutch is not the default but it *is* the fallback: `supported.first` is what `WidgetsApp` resolves to for a device speaking neither Dutch nor English, so the course's own language still has the last word.

`LocaleController` holds a **nullable** `Locale`, and null means "follow the device". It goes to `WidgetsApp.locale` as-is, so Flutter does the resolving against `supportedLocales` and lands on its **first entry** when the device has none of them. That ordering is load-bearing: `supported.first` is the fallback language, not just the first menu row.

The choice is persisted (`locale.language`) beside the theme mode, and "follow the device" is stored as the sentinel `system` rather than by clearing the key, so switching back to it is a write like any other. It resolves to the same thing an absent key does, which is what makes "never picked" and "picked the device" behave identically. Both stores are what `main()` awaits before `runApp`; the initialization screen is themed *and* localized, so reading either later makes it paint wrong and flip.

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
