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

### State management

MobX for all reactive state. `@readonly` generates a private field plus a public getter; mutations go in `@action` methods. Wrap anything that should rebuild in `Observer` from `flutter_mobx`.

**An `Observer` only tracks what is read during its own build.** A `LayoutBuilder`, `Builder` with a deferred callback, or anything else whose closure runs at *layout* time reads observables outside that window, so the `Observer` never re-runs and the screen silently stops updating — no error, just a button that appears to do nothing. Prefer `MediaQuery.sizeOf(context)` for responsive decisions: it answers during build and rebuilds on change. If a `LayoutBuilder` is genuinely needed, put an `Observer` *inside* it.

App-wide state is a plain MobX store registered in GetIt from `setupServices()` in `main.dart` — `LocaleController` is the example. **`setupServices()` does no I/O**: work that can fail or take time belongs to `InitializationScreen`, which can show progress and offer a retry.

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
lib/theme/presets/thuas_palette.dart      # De Haagse Hogeschool's house style, transcribed
```

**A preset changes colour and nothing else.** The type scale, the two font families and the radii belong to the app and are shared by every preset. `AppColorPreset.neutral` is the default and is what the app looks like unbranded; `AppColorPreset.thuas` is a skin. Adding a preset means adding a case to `AppColorPreset.resolve()` and nothing else.

**Every rounded corner is a squircle.** Draw one with `squircle(radius)` from `shape_metrics.dart` and a `ShapeDecoration` — never `BoxDecoration.borderRadius`, which can only make a plain rounded rectangle. `kSquircleScale` converts the design's CSS radii to `ContinuousRectangleBorder`'s tighter curve; it is the one number to turn if corners look wrong. A continuous rectangle does **not** clamp an over-large radius — past half the shortest side it bows inward — so a small square tile uses `squircleOf(radius, size:)` instead.

`AppButton` exists rather than forui's `FButton` because the design's padding is `38 × 19` against forui's `10 × 11`, and forui fills a button with a `BoxDecoration` that cannot carry a squircle. It is built on forui's `FTappable`, so hover, focus and button semantics still come from the framework.

**A button must not resize when it starts working.** `AppButton.busy` keeps the label laid out (`Visibility.maintain`) and puts the spinner in a `Positioned.fill`, so neither the label swap nor the spinner's own height can change the button's size. Swapping the label for a shorter "Bezig…" makes the button jump the moment it is pressed, which reads as the layout breaking.

**forui defaults every tappable's cursor to `MouseCursor.defer`**, which on the web leaves the ordinary arrow over buttons, breadcrumb crumbs and the settings cog. `buildAppTheme()` sets it once on `FStyle.tappableStyle`; every widget style inherits from that one, so nothing needs a `MouseRegion` of its own.

Responsive layout goes through **`context.theme.breakpoints`**, which are Tailwind's. The lesson's two-column step stacks below `lg` (1024). Note that `Expanded(flex:)` is an *integer* ratio against a default of 1 — `flex: 11` is an 11:1 split, not 1:1.1, which is how the prose column once came out one word wide.

`AppSemanticColors` names the roles forui has no slot for — `warning`, `success`, the code editor's surface, the progress bar. **Write a colour there, not inline in a widget**, and read it through `context.appTheme.colors`. Each `*Foreground` is stated next to its fill on purpose: the THUAS corporate green reaches only 2.63:1 against white, so picking a foreground at the call site is exactly how a screen ends up illegible. `test/theme/theme_test.dart` asserts every pairing clears WCAG AA in every preset — **add a pair there when you add a colour.**

`context.appTheme` falls back to the neutral preset when the ambient theme carries no extension (a widget test that builds its own `FTheme`), so it never null-checks.

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

### Three loading states

They cover three different windows and are not interchangeable:

1. **`web/index.html`** — before Flutter exists at all. Cannot reach the theme, so it restates the neutral preset's colours in CSS by hand; changing the preset means changing that block too.
2. **`InitializationScreen`** — work the app does once it is running (reading the course index, compiling `python.wasm`). Shows which step is in flight, retries a bounded number of times, then offers a retry button. The bound matters: everything it waits on is a bundled asset, so a failure means a broken build rather than a server that might come back.
3. **`LoadingOverlay`** — anything a screen waits on afterwards.

### Running a student's code

`PythonAttemptRunner` is the only thing that should call `PythonRuntime.run()`. It wraps the student's code and the section's validator into **one** program, because the checks have to see the exact output that run produced. `AttemptResult` keeps the three outcomes apart — a crash (`programError`), a failed check (`checkMessage`) and a pass — because each needs different words on screen, and `AttemptResult.broken` is a fourth: the runtime is unavailable, which must never read as "you got it wrong".

`tool/try_lesson.dart` drives the same harness from the command line, so a lesson can be checked without the app.

### Vocabulary

Four words, fixed. Drifting off them is what made the folders disagree with the code once already.

| Word | Means |
| --- | --- |
| **course** | Everything the app ships. `Course`. |
| **lesson** | One markdown file per locale, under `assets/lessons/<language>/`. `Lesson`. |
| **section** | One `##` block of a lesson. `LessonSection`. The student-facing word for it is **step**. |
| **assignment** | A *kind of section* — one that asks for code (`SectionKind.shortAssignment`, `longAssignment`). **Not** a unit of content. |

A single run of a section is an **attempt** (`AttemptResult`, `PythonAttemptRunner`). *Exercise* is not a word this codebase uses.

**Catalog** and **languages** name listing *screens*, not content, which is why they sit outside the table.

### Lessons

A lesson is **one markdown file per locale**, at `assets/lessons/<language>/<order>-<slug>.<locale>.md`. Metadata, prose, starter code and the hidden validators all live in that one file. The full spec is in `docs/lesson-format.md`. **Read it before touching the format.**

Two things that are easy to get wrong:

- **There is no index file.** Order comes from the `NN-` filename prefix and discovery from Flutter's `AssetManifest`, so the directory *is* the index. Reordering the course is a rename.
- **`Lesson.parse` must keep `encodeHtml: false`.** The `markdown` package HTML-escapes block text by default, which would hand CPython `print(&quot;hi&quot;)` and fail at runtime rather than at parse time.

`test/services/lesson_test.dart` parses every file that ships, so an authoring mistake fails the test run instead of the initialization screen.

Flutter's asset globbing is **not recursive**, so every asset directory is listed separately in `pubspec.yaml` — a new folder is silently absent at runtime until it is declared.

### Running Python

`lib/services/python/` picks a host through a conditional import. The web host is the only one that exists; everything else, including the Dart VM `flutter test` runs on, falls through to `python_runtime_stub.dart`, which reports `isSupported == false` rather than throwing.

`PythonRuntime` is named for what it is. A second language means a second runtime beside it and an interface above them both — not renaming this one. `PythonAttemptRunner` sits on top and is the only thing that should call `run()`: it wraps the student's code and the section's validator into **one** program, because the checks must see the exact output that run produced.

The student's source is carried into that program as **base64 of JSON**, never interpolated. Interpolation needs escaping their code can always defeat — a triple quote, a stray backslash — and base64's alphabet contains no quote, so the payload cannot terminate the literal holding it. `test/services/python_attempt_runner_test.dart` runs the wrapper through the machine's own `python3` (skipped when absent), so the capture, traceback trimming and `output` stripping are tested without a browser.

### Localization

ARB files in `lib/l10n/` (`app_en.arb`, `app_nl.arb`), generated output in `lib/l10n/generated/`. Key convention is `screenOrWidgetName_short_description`. Run `fvm flutter gen-l10n` after editing.

Reach strings through `context.localizations.myKey`, adding `import 'package:i_can_code/extensions/build_context_extension.dart';`.

Dutch is the default rather than the device locale: the course is taught in Dutch, so following the device would put most students in the wrong language.

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
