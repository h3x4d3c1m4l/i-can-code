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
type: short-assignment
id: print-yourself
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
| First `metadata` block | Document level. Carries `id`, shared by every locale. |
| `##` heading | Starts a **section** — one step, one progress dot. |
| `metadata` under a `##` | That section's `type` and `id`. Both required. |
| `<lang>-assignment` | What the editor opens with. May be empty. |
| `<lang>-validator` | The hidden checks. Never shown. |
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
| `short-assignment` | Prose and editor stacked in **one column** — the question is a sentence or two. |
| `long-assignment` | The design's **two columns**: prose left, editor and output right. |

An `info` section must not carry an assignment or validator block; the other two
must carry both. `Lesson.parse` throws a `FormatException` naming the section
when either rule is broken.

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
