# Sample: predict the output

One `predict-output` section: a program to read, and a box to say what it prints
before it runs.

```metadata
id: sample-predict-output
emoji: "🔮"
```

## What comes out?

```metadata
type: predict-output
id: predict-print
emoji: "🔮"
```

A `predict-output` step carries a `<lang>-predict` block in place of an
assignment and a validator. **The interpreter is the answer key** — the program
is run and its output is what the prediction is held against — so the file states
no expected output and cannot drift from the code in it.

Two rules the parser cannot enforce: the program MUST be deterministic (no
`random`, no clock, no input), and it MUST print something.

Check a new step with `dart run tool/try_lesson.dart <this file> 0`, which prints
exactly what the student will be measured against.

```python-predict
print("Hello")
print(42)
print("Hello", 42)
```

```explanation
The third line is the surprise: give `print` more than one thing, separated by a
comma, and Python puts a **space** between them itself. That space appears nowhere
in the code — `print` makes it.
```
