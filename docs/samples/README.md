# Sample lessons

One file per section type, each a **complete, parseable lesson** rather than a
fragment — so every one of them can be run through the real harness:

```bash
fvm dart run tool/try_lesson.dart docs/samples/exercise.md           # list its sections
fvm dart run tool/try_lesson.dart docs/samples/exercise.md 0 --code 'print(42)'
fvm dart run tool/try_lesson.dart docs/samples/predict-output.md 0   # see the answer key
```

| File | `type` | What it shows |
| --- | --- | --- |
| [info.md](info.md) | `info` | Prose only, a worked example, and `###` foldable subheadings including `{collapsed}` |
| [quick-exercise.md](quick-exercise.md) | `quick-exercise` | One-line answer: assignment and validator, stacked in one column |
| [exercise.md](exercise.md) | `exercise` | The two-column form, with a fuller validator |
| [match-pairs.md](match-pairs.md) | `match-pairs` | A `pairs` block — the board is the check |
| [predict-output.md](predict-output.md) | `predict-output` | A `<lang>-predict` block and its optional `explanation` |

**These are documentation, not content.** They live here rather than under
`assets/lessons/`, which is the only directory the app discovers, so nothing here
ever reaches a student. `test/services/lesson_test.dart` parses them all, so a
sample cannot rot into something the format no longer accepts.

Three things every section carries, whatever its type, and which are therefore
not demonstrated separately:

- **`id`** — required, stable, unique within its lesson. Saved progress keys on
  it.
- **`emoji`** — one, shown beside the step's title.
- **`optional: true`** — any type may be a "Verdieping": badged, skippable, and
  skipping it records nothing.

The full specification is in [../lesson-format.md](../lesson-format.md).
