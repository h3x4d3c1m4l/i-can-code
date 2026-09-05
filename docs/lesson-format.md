# Lesson format

A lesson is **one markdown file per locale**. Its metadata, its prose, the code
the editor opens with and the hidden checks all live in that one file — there is
no sidecar YAML and no index.

```text
assets/lessons/
  python/
    01-input-and-output.nl.md
    01-input-and-output.en.md
```

## The filename carries three things

```text
assets/lessons/<language>/<order>-<slug>.<locale>.md
```

- **`<language>`** — the programming language the lesson teaches, as a directory.
  Python is the first; a second language is a second directory, not a rewrite.
- **`<order>`** — a zero-padded number. **This is the only source of course
  order.** Reordering the course is a rename.
- **`<slug>`** — what the file is about, in kebab case.
- **`<locale>`** — `nl`, `en`, … One file per translation.

`Course.entriesFrom` ignores anything that does not match this pattern, so a
`README.md` or an editor backup in the folder is harmless.

### There is no index file

Flutter's `AssetManifest` already lists everything bundled, so the directory *is*
the index. A lesson therefore cannot be added to the app and then forgotten in an
index — the failure mode the old `index.yaml` had.

**Flutter's asset globbing is not recursive.** Every directory is listed
separately in `pubspec.yaml`; a new language directory is silently absent at
runtime until it is declared there.

## The shape of a file

````markdown
# Invoer en uitvoer

Data invoeren

```metadata
id: input-and-output
emoji: "⌨️"
```

## Introductie

```metadata
type: info
```

Welkom bij de eerste module over Python!

```python
print("Hello, world")
```

## Zelf "printen"

```metadata
type: quick-exercise
id: print-yourself
emoji: "✍️"
```

Schrijf nu zelf een regel code om een stukje tekst te "printen".

```python-assignment
```

```python-validator
if "print(" not in code:
    raise Exception("Gebruik de `print`-functie om tekst uit te voeren.")
```
````

| Piece | Meaning |
| --- | --- |
| `#` heading | The lesson title, shown on its catalog card. |
| The paragraph under it | The lesson subtitle. Optional. |
| First `metadata` block | Document level. Carries `id` and `emoji`, both shared by every locale. |
| `##` heading | Starts a **section** — one step, one progress dot. |
| `metadata` under a `##` | That section's `type` and `id`. Both required. Plus its `emoji`. |
| `<lang>-assignment` | What the editor opens with. May be empty. |
| `<lang>-validator` | The hidden checks. Never shown. |
| `pairs` | What a `match-pairs` step's board holds. See below. |
| Any other fenced block | A worked example, rendered as part of the prose. |

### Every section needs an `id`

Saved progress keys on it, so it has to be stable: a student's tick must survive
the section being reordered, retitled or having another inserted before it, and
a position survives none of that.

- **Unique within its lesson**, and the same in every translation — a tick earned
  in Dutch counts in English.
- **Never reused for different content.** Changing what a section asks means a
  new id, or students will see work they have not done marked as finished.
- Removing a section simply stops it counting. There is no migration.

`test/services/lesson_test.dart` holds all three rules for the lessons that ship.

### Section types

| `type` | Layout |
| --- | --- |
| `info` | Prose only. No editor, nothing to run. |
| `quick-exercise` | Prose and editor stacked in **one column** — the question is a sentence or two. |
| `exercise` | The design's **two columns**: prose left, editor and output right. |
| `match-pairs` | Prose, then a board of tiles to pair up. No editor, nothing to run — see below. |

Which blocks a section may carry follows from its type:

| `type` | Assignment and validator | `pairs` |
| --- | --- | --- |
| `info` | Must not | Must not |
| `quick-exercise`, `exercise` | Must carry both | Must not |
| `match-pairs` | Must not | Must carry one |

`Lesson.parse` throws a `FormatException` naming the section when any of those
is broken.

### `optional: true` — a "Verdieping"

Any type may add `optional: true`. The step then carries a **Verdieping** badge
above its title and an **Overslaan** link beside it.

```metadata
type: info
id: how-print-got-its-name
optional: true
```

Skipping stores **nothing**. The step's progress segment stays grey and the step
is offered again on the next visit — it is skipped for this reading, not marked
done and not marked refused. A student who does the work still earns the tick the
normal way, so the badge changes what is *asked*, never what is *recorded*.

`optional` MUST be `true` or `false`; anything else is a `FormatException`.
Omitted, it is `false`.

### `emoji:` — the step's own mark

Every step carries one emoji, shown before its title and nowhere else. A
breadcrumb and the progress bar stay text.

The **lesson** carries one too, in its document-level `metadata`. That one fills
the tile on the lesson's catalog card, in place of the order number. The two are
independent: a lesson's emoji is not its first step's.

```metadata
type: info
id: coding
emoji: "💡"
```

- **The same in every translation.** It marks the step, not the language the
  step is written in, so `test/services/lesson_test.dart` holds the two locales
  to the same emoji the way it holds them to the same ids.
- **One emoji, not a sentence.** Nothing enforces the count — the field is text
  and a long one simply looks wrong — but a title is not the place for a row of
  them.
- **Quoting it is optional.** YAML reads a bare emoji as a plain string. The
  quotes above are a courtesy to editors that would otherwise mangle it.
- An `emoji` that is empty, or that YAML reads as something other than text
  (`emoji: 3`), is a `FormatException`.

Both fields are **optional in the parser** — a lesson missing one still opens,
with a plain title or a numbered tile — but **required of every lesson that
ships**, which is a rule the test holds rather than the format.

A programming **language** has no file of its own, so its emoji is a case in
`languageEmoji()` in `lib/services/lessons/course.dart`. A language the table
does not name falls back to the initial on its card, so adding a language
directory does not require touching it.

It renders in **Noto Color Emoji**, bundled under `assets/fonts/`. That is what
makes a step look the same on every platform instead of borrowing Apple's emoji
on a Mac and Google's on the web; see *Theming* in `CLAUDE.md`.

## `###` inside a section — foldable subheadings

Within a section's prose, every `###` heading becomes a block the student can
fold away by pressing it. The prose before the first `###` stays put, and a
section with no `###` renders exactly as it always did.

End a heading with **`{collapsed}`** to have that one arrive folded:

```markdown
### Sorted by paradigm

Always open, because it is the point of the section.

### The full list of languages {collapsed}

Folded on arrival — reference material, not something to read straight through.
```

The marker is stripped from the title and only counts at the very end of the
line, so a heading may still mention `{collapsed}` in its own text.

Three things to know:

- **Folding is not remembered.** Leave the step and come back and every group is
  back in the state its heading asked for. It is a reading convenience, not
  progress — see the note on `ProgressStore` in `CLAUDE.md`.
- **A `###` inside a fenced block is code**, not a heading, so a Python sample
  containing one will not cut the prose in half.
- **`####` and deeper are left alone.** They render as ordinary headings inside
  whichever group they fall in.

## Why the role rides in the fence language

` ```python-assignment ` parses with the stock `markdown` package —
the language becomes `class="language-python-assignment"` on the `code` element,
so no custom block syntax and no fork is needed. The loader strips the
`-assignment` / `-validator` suffix before handing `python` to the syntax
highlighter, which would not recognise the full name.

The parser is constructed with **`encodeHtml: false`**. By default it
HTML-escapes block text, which would hand CPython `print(&quot;hi&quot;)` and
fail at runtime instead of here. `test/services/lesson_test.dart` asserts no
`&quot;` survives into any block.

## `pairs` — a match-the-pairs board

A `match-pairs` section carries one `pairs` block in place of an assignment and
a validator. The board **is** the check: the step passes the moment its last
pair lands, and there is nothing to run.

````markdown
## Wat hoort bij elkaar?

```metadata
type: match-pairs
id: printing-pairs
emoji: "🧩"
```

Zet de stukjes bij elkaar die samen één kloppende zin vormen.

```pairs
`print("Hallo")`
… toont de tekst Hallo.

`print(42)`
… toont het getal 42, zonder aanhalingstekens eromheen.
```
````

**One pair per paragraph, two lines each.** The two lines are the pair's two
halves and a blank line ends the pair. Which of them is written first changes
nothing the student sees — the board deals both halves of every pair into one
pool — so write them in the order the pair reads.

That shape rather than YAML or a `left | right` separator, because a tile is
arbitrary text: `print("a: b")` is not a plain YAML scalar, and any separator
character turns up inside a tile sooner or later. A blank line cannot.

- **Every tile is dealt into one pool**, by a shuffle derived from the section's
  `id` — so the board comes back the same way after a step away and stands the
  same in both translations, and the order the file lists pairs in is never the
  order the student sees. One pool, and not a block of first halves over a block
  of second ones: split, the board says which half of a pair a tile is before
  the student has read a word of it, which is half of every pair narrowed down
  for them.
- **At least two pairs.** One pair is not a game.
- **Both halves are inline markdown**, rendered the way prose is, so a tile may
  name a function in `code` spans.
- **A tile is a square**, so keep a half short enough to sit in one. Longer text
  is not lost — the tile scrolls rather than overflowing — but a tile that has to
  be scrolled cannot be read at a glance, which is all the time a matching game
  gives it.
- A paragraph of anything but two lines is a `FormatException`, and so is a
  `pairs` block on a section of another type, or a `match-pairs` section
  without one.

### The `…` is the lesson's, not the format's

The second halves above open with an ellipsis because those particular pairs are
sentences cut in two, and it tells the reader which end of one they are holding.
**Nothing parses it**, and nothing needs it: a pair may just as well be a
function and what it does, or a word and its translation, where neither half has
to announce itself.

It is worth knowing that the board is where the ellipsis earns its keep, though.
Every tile is dealt into one pool, so the words on a tile are the **only** thing
that can say which end of a pair it is. A pair whose halves need telling apart
has to say so in its own text, the way the ellipsis does.

Progress works as it does everywhere else: solving the board records the
section's `id`, and a `match-pairs` step marked `optional: true` can be skipped
without recording anything.

## `<lang>-validator` — the hidden checks

The validator is a **script**, not a function. It runs in the same in-browser
CPython as the student's own code, after their program has finished, with two
names already bound:

| Name | Type | Meaning |
| --- | --- | --- |
| `code` | `str` | Exactly what the student typed |
| `output` | `str` | Their program's standard output, **with trailing whitespace stripped** |

It reports a failure by raising, and the exception message is what the student
sees:

```python
if "print(" not in code:
    raise Exception("Gebruik de `print`-functie om tekst uit te voeren.")
if output != "42\n3.14":
    raise Exception("`print` eerst 42, daarna 3.14.")
```

Falling off the end without raising means the step passed.

**`output` is stripped on purpose.** `print(42)` emits a trailing newline, so a
check written as `output == "42"` would otherwise never pass — the trap every
author would hit on their first validator. Interior newlines are untouched, so
`"42\n3.14"` still tests two lines.

### "Hidden" means hidden from the UI, not secret

Every asset ships to the browser, so a determined student can read a validator in
devtools. That is fine for coursework — it is a teaching aid, not an exam gate.
If lessons ever need to be tamper-proof, validation has to move server-side, and
that is a different feature. **Don't write anything in a validator you would not
want a student to read.**

## Adding a lesson

1. Create `assets/lessons/<language>/<order>-<slug>.<locale>.md`.
2. Add translations as further `.<locale>.md` files beside it.
3. If the language directory is new, add it to `pubspec.yaml`.

No code change and no regeneration. `test/services/lesson_test.dart` parses
every file that ships, so an authoring mistake fails the test run rather than the
initialization screen.
