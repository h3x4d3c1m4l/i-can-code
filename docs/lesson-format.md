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

## Worked examples of every type

`docs/samples/` holds one complete, parseable lesson per section type — see
[samples/README.md](samples/README.md). Each can be run through the real harness
with `tool/try_lesson.dart`, and `test/services/lesson_test.dart` parses them all
so they cannot drift from this document.

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
| `<lang>-predict` | The program a `predict-output` step asks about. See below. |
| `<lang>-order` | The lines an `order-lines` step is assembled from, in the right order. |
| `<lang>-distractors` | Lines that belong to no correct program. Optional. |
| `explanation` | Why that program's output is what it is. Shown after the answer. |
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
| `predict-output` | Prose, a program, and a box to say what it prints before it runs. No editor — see below. |
| `order-lines` | Prose, then the program's own lines shuffled, to be put in order. No editor — see below. |

Which blocks a section may carry follows from its type:

| `type` | Assignment | Validator | `pairs` | `<lang>-predict` | `explanation` | `<lang>-order` |
| --- | --- | --- | --- | --- | --- | --- |
| `info` | Must not | Must not | Must not | Must not | Must not | Must not |
| `quick-exercise`, `exercise` | Must carry one | Must carry one | Must not | Must not | Must not | Must not |
| `match-pairs` | Must not | Must not | Must carry one | Must not | Must not | Must not |
| `predict-output` | Must not | Must not | Must not | Must carry one | May carry one | Must not |
| `order-lines` | Must not | **Must carry one** | Must not | Must not | Must not | Must carry one |

`order-lines` is the one type that is checked without being typed: it runs a
program, so it needs a validator, but the student assembles that program rather
than writing it, so it has no editor and no assignment block. That split is
`SectionKind.isAssignment` (has an editor) against `SectionKind.usesValidator`
(is checked).

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

## `<lang>-predict` — predict the output

A `predict-output` section carries one `<lang>-predict` block in place of an
assignment and a validator. The student reads the program, writes what they
think it prints, and only then is it run.

````markdown
## Wat komt eruit?

```metadata
type: predict-output
id: predict-print
emoji: "🔮"
```

Denk eerst zelf na over wat er op het scherm verschijnt.

```python-predict
print("Hallo")
print(42)
print("Hallo", 42)
```

```explanation
De derde regel is de verrassing: geef je `print` méér dan één ding, dan zet
Python er zelf een **spatie** tussen.
```
````

### The interpreter is the answer key

**A lesson file states no expected output**, and there is nowhere to put one.
The program is run and what it printed is what the prediction is held against,
so the answer cannot drift from the code beside it the way a hand-written one
can. `tool/try_lesson.dart <lesson.md> <n>` runs the block and prints what a
student will be measured against — check a new step with it.

Two rules follow, and neither is enforced by the parser:

- **The program MUST be deterministic.** No `random`, no clock, no input. The
  same program has to print the same thing for every student, on every visit.
- **It MUST print something.** A program with no output has nothing to predict.
  The parser refuses an *empty block*, but it cannot see that `x = 1` prints
  nothing — that is the author's to catch, and `try_lesson.dart` will show it.

### How a prediction is compared

Line by line, with trailing whitespace and surrounding blank lines removed from
both sides — `print` ends every line with a newline that no student can type on
purpose, and a keyboard leaves trailing spaces nobody can see.

**Everything else counts**: case, quotes, and the spaces `print` puts between
arguments. `Hallo42` is not `Hallo 42`, and `42` is not `"42"`. That is the
whole exercise — write a step whose surprise is one of those differences.

### A wrong prediction still completes the step

The output is shown either way, the prediction is read back beside it, and the
step is ticked. Getting it wrong is not a failure state: the surprise is the
lesson, and hiding the answer to make the student guess again turns it into a
lock. What decides the tick is that the program ran.

### `explanation` — the feedback half

Optional, and only on this type. Inline markdown, rendered the way prose is,
shown **under** the answer and to everyone — the student who guessed right has
learned no more about *why* than the one who did not.

It is refused on every other type: it is shown with the answer to a prediction,
and no other kind has an answer to show it with. An empty one is a
`FormatException`, the same as an empty program.

## `<lang>-order` — put the lines in order

An `order-lines` section carries the program's own lines, which the student
arranges into a working one. The rung between reading a worked example and
writing code from nothing: the syntax is given, so what is being practised is the
shape of the program.

````markdown
## Zet het programma in elkaar

```metadata
type: order-lines
id: order-answer
emoji: "🔀"
```

Zet de regels in de goede volgorde.

```python-order
print("Het antwoord is:")
print(42)
print("Klaar!")
```

```python-distractors
print("42")
```

```python-validator
program.allow_only("call")

if program.calls("print").with_any_args("42"):
    raise Exception("Getallen schrijf je zonder aanhalingstekens.")
if output != "Het antwoord is:\n42\nKlaar!":
    raise Exception("Eerst `Het antwoord is:`, dan `42`, dan `Klaar!`.")
```
````

### What is checked is the program, never the order

The assembled lines are run through the section's ordinary validator, exactly the
way a typed answer is. **The arrangement is never compared against the block.**
An order that is different but correct passes, which is the whole reason it is
checked this way — and the validator you would write for the same task as an
`exercise` works here unchanged.

Write the block **in the right order**. That order is the one the board never
deals: the shuffle is derived from the section's `id`, and a deal that came back
sorted is rotated, so a student cannot read the answer off the board.

The student drags a line into any gap, taps an available one to append it, or
uses the move-up and move-down semantics actions a screen reader offers. None of
that changes what you write here.

- **At least two lines.** One line is already in order.
- **Blank lines are dropped** — a blank line is a gap in the source, not a tile.
- **Leading whitespace is kept.** The indentation belongs to the line and travels
  with it, so the student arranges a program rather than also having to indent
  it. Write the block exactly as the finished program looks.

### `<lang>-distractors` — lines that belong to no answer

Optional, and only on this type. They sit among the available lines to be left
there, and they need nothing of the board: a distractor that is used makes the
assembled program wrong, and the validator says so the way it would about any
other mistake.

The best distractor is one the **output cannot catch**. `print("42")` beside
`print(42)` prints the same characters, so only a check on the tree —
`program.calls("print").with_any_args("42")` — can tell them apart. That is the
kind of distinction a lesson is trying to teach, and `docs/samples/order-lines.md`
plus the step shipped in lesson 01 are both built this way.

### Checking a step you have written

`tool/try_lesson.dart` runs an `order-lines` step with **the author's own order**
when given no `--code`, which is what proves the intended answer actually passes
the validator beside it:

```bash
fvm dart run tool/try_lesson.dart <lesson.md> <n>
fvm dart run tool/try_lesson.dart <lesson.md> <n> --code 'print(2)\nprint(1)'
```

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
| `program` | `Program` | The same source, read as a tree. See *Reading the code* below |

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

### Reading the code, not just the output

`code` is a string, so the obvious check is `"print(" in code` — and that check
passes for `s = "print(42)"`, fails for `print ( 42 )`, and cannot tell `print(42)`
from `print("42")`. `program` reads the same source as a **tree**, so it answers
about the code the student actually wrote.

```python
if not program.calls("print"):
    raise Exception("Gebruik de `print`-functie.")
if not program.calls("print").with_args(42):
    raise Exception("Print het getal 42, zonder aanhalingstekens.")
if not program.calls("print").times(2):
    raise Exception("Gebruik twee losse `print`-regels.")
if not program.uses("for"):
    raise Exception("Gebruik een `for`-lus.")
```

Nothing here runs the student's code — the run already happened, and `output` is
what it produced. So the tree **sees a branch that never executed** and **never
sees a value that was computed**: in `x = 40 + 2` then `print(x)`, `program` sees
a call to `print` with a variable, not with `42`. Check the value in `output`;
check the shape in `program`.

#### What you can ask

| Question | Answers |
| --- | --- |
| `program.calls(name)` | Every call to `name`, anywhere — inside a loop or a function body included |
| `program.assigns(name)` | Every assignment with `=`, or with `name` omitted, every assignment at all |
| `program.uses(construct)` | `True`/`False` for one construct, or one group, of the table below |
| `program.allow_only(*constructs)` | Raises when anything **else** was written. See *Fencing off what a step has not taught* |
| `program.disallow(*constructs)` | Raises when any of these **was** written |

A name is matched **whole**. `calls("math.sqrt")` finds `math.sqrt(x)` and
`calls("sqrt")` finds the bare `sqrt(x)` that `from math import sqrt` leaves —
neither finds the other. A **leading dot** is the method on any receiver, so
`calls(".upper")` finds `naam.upper()` and `"hallo".upper()` alike.

All three **raise** on a construct they do not know rather than answering
`False`, so a typo is a loud failure in `try_lesson.dart` instead of a step no
student can pass.

#### Narrowing what came back

`calls()` and `assigns()` return a **query**, which is truthy while anything still
matches and can be narrowed further:

| Narrowed by | Means |
| --- | --- |
| `.with_args(*args, **keywords)` | **Exactly** these positional arguments, and at least these keywords |
| `.with_any_args(*args)` | These arguments, in this order, among however many others |
| `.to(value)` | *(assignments)* Assigned this value |
| `.times(n)`, `.at_least(n)`, `.at_most(n)` | How many are left. These answer `True`/`False`, so they end a chain |

`with_args` is exact on purpose: `with_args(anything)` reads as "called with one
thing", not "called with that among others" — which is `with_any_args(anything)`.
That distinction is the one every pattern language gets wrong, and getting it
wrong makes `print("Hallo", naam)` count as a call with one argument.

#### Fencing off what a step has not taught

A step one page into `print` wants calls and nothing else — no `if`, no `def`, no
loop. `allow_only` says exactly that, and keeps saying it as Python grows:

```python
program.allow_only("call")
```

That is the whole check. It raises on the first thing the student wrote that is
not a call, and falls through when there is nothing.

Widen it by naming more:

```python
program.allow_only("call", "assignment")           # calls, and storing a result
program.allow_only("call", "assignment", "if")     # ... and a branch
```

`disallow` is the other direction, for a step that has taught most things and is
banning one:

```python
program.disallow("loops")
program.disallow("import", "class")
```

**Prefer `allow_only` in an early lesson.** A ban has to name everything a student
might reach for, and misses whatever the language grows next; an allowlist is a
sentence about what the step has taught, and stays true.

##### What may be named

| Construct | Written as |
| --- | --- |
| `call` | A line that is a call — `print(42)`. A call *inside* something else is part of that thing, not this |
| `assignment` | `x = 1`, `x: int = 1`, `x += 1` |
| `if` | `if`, `elif`, and the `a if b else c` form |
| `for`, `while`, `comprehension` | The three ways to repeat |
| `break`, `continue`, `return`, `pass` | |
| `def`, `lambda`, `class`, `yield` | |
| `import` | `import x` and `from x import y` |
| `try`, `raise`, `assert` | |
| `with`, `global`, `nonlocal`, `del`, `await`, `match` | |
| `f-string` | `f"Hallo {naam}"` |
| `type-alias` | `type Punt = tuple[int, int]` |

And these **groups**, each standing for the constructs under it:

| Group | Stands for |
| --- | --- |
| `loops` | `for`, `while`, `comprehension` |
| `branches` | `if`, `match` |
| `jumps` | `break`, `continue`, `return` |
| `functions` | `def`, `lambda`, `return` |
| `control-flow` | `branches` + `loops` + `jumps` without `return`, plus `try` |

A **bare expression** — a stray `42`, a module docstring — is always allowed and
can never be named. It is not something a lesson teaches, and tripping over a
docstring would read to a student as the checker being broken.

**Depth is not a hiding place.** The whole tree is read, so a banned construct is
found however deep it sits — inside a function that is never called, in a branch
that never runs, at the bottom of a stack of `with` blocks. Nothing here recurses
either, so there is no depth at which the check itself gives out: CPython's own
parser refuses first, at 100 levels of indentation and around 200 nested
parentheses, and that arrives as a program error before any check runs.

##### The message the student reads

Both take a `message`, and it is used exactly as written — it is authored in the
lesson's own language, alongside the prose:

```python
program.allow_only("call", message="Gebruik in deze opdracht alleen `print`.")
program.disallow("loops", message="Los dit nog even zonder lus op.")
```

**Leave it out and the app says it instead**, in the reader's language rather than
the file's:

> In deze opdracht mag je geen `if` gebruiken.
>
> You may not use `if` in this exercise.

That works because the refusal travels to Dart as the construct's **name** and
not as a sentence. A Python keyword is the same word in every language, so it is
set as code; the handful of constructs with no keyword to quote — a call, an
assignment, a comprehension, an f-string, a bare expression, a type alias — have
a string per locale. The strings are `lessonScreen_checkNotAllowed` and
`lessonScreen_construct*` in `lib/l10n/`, and
`test/services/python_check_library_test.dart` holds them against the library's
own list so a new construct cannot reach a student as a bare English word.

A fallback is not a translation, though: it says *that* something is not allowed
and never *why*, or what to do instead. **Write the message on any step a student
is likely to trip over** — the fallback is there so a step is never wordless, not
so a step can go unwritten.

When several things are wrong, the student reads about the **first one they
wrote**, not whichever the checker happened to reach first.

#### Matchers

An argument is compared as a literal unless it is one of these:

| Matcher | Matches |
| --- | --- |
| `anything` | Any argument at all |
| `a_string` | Text, f-string or not — `"hoi"` and `f"Hallo {naam}"` both |
| `a_number` | A whole number or a decimal. `True` is not a number |
| `a_variable` / `a_variable("naam")` | Any name being read, or that one |
| `a_call("round")` | A call used as an argument — the `round(...)` in `print(round(x, 2))` |

A literal is compared by **type as well as value**, so `with_args(42)` rejects
`print("42")` and `print(42.0)`. A negative literal reads as the number:
`with_args(-1)` matches `print(-1)`.

```python
if not program.calls("input").with_args(a_string):
    raise Exception("Geef `input` een vraag mee, zodat de gebruiker weet wat te doen.")
if not program.calls("print").with_args(a_string, a_variable("naam")):
    raise Exception("Print een groet met daarachter de naam.")
if not program.assigns("naam").to(a_call("input")):
    raise Exception("Bewaar het antwoord van `input` in `naam`.")
```

#### It is the standard library and nothing more

`program` is built on Python's own `ast`, which ships inside
`assets/python/python314.zip`. There is no third-party package behind it and
nothing to add to `pubspec.yaml`. The source is `kCheckLibrary` in
`lib/services/python/python_check_library.dart`; the names it binds are the ones
in its `__all__`, and `ast` itself is **not** among them.

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
