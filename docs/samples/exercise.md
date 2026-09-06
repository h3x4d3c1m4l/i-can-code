# Sample: a full exercise

One `exercise` section: the design's two columns, prose left, editor and output
right.

```metadata
id: sample-exercise
emoji: "📦"
```

## Printing numbers

```metadata
type: exercise
id: printing-values
emoji: "📦"
```

An `exercise` is the fuller form of a `quick-exercise`: same blocks, wider
layout. Below `lg` (1024) the two columns stack and the step scrolls as one page;
side by side each column scrolls on its own, so reading the prose leaves the
editor where it is.

Change the code below so that it prints the number `42` first and then `3.14`.

Numbers are written without quotation marks, and Python uses a dot as the decimal
separator.

```python-assignment
print(...)
print(...)
```

```python-validator
program.allow_only("call")

if not program.calls("print"):
    raise Exception("Use the `print` function.")
if program.calls("print").with_any_args("42") or program.calls("print").with_any_args("3.14"):
    raise Exception("Numbers are written without quotation marks.")
if program.calls("print").with_args(3, 14):
    raise Exception("Python uses a dot as the decimal separator: write 3.14.")
if not program.calls("print").times(2):
    raise Exception("Use 2 separate `print` lines: 42 first, then 3.14.")
if output != "42\n3.14":
    raise Exception("`print` 42 first, then 3.14.")
```
