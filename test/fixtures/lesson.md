# Output

A lesson the test suite owns. It is not course material, and it changes only when a test needs it to.

```metadata
id: fixture-output
emoji: "🖨️"
```

## Showing text

```metadata
type: info
id: showing-text
emoji: "👋"
```

Welcome to the first lesson of this fixture. The line below is a worked example, set as a code block.

```python
print("Hello, world")
```

## Print it yourself

```metadata
type: quick-exercise
id: print-yourself
emoji: "✍️"
```

Write a line of code that prints some text.

```python-assignment
```

```python-validator
program.allow_only("call")

if not program.calls("print"):
    raise Exception("Use the `print` function to show text.")
if not program.calls("print").with_any_args(a_string):
    raise Exception('Put your message in quotes, for example `print("Hello")`.')
if not output:
    raise Exception("Use the `print` function with non-empty text.")
```

## Printing different values

```metadata
type: exercise
id: printing-values
emoji: "📦"
```

Print the number `42`, then pi to two decimals.

```python-assignment
print(...)
print(...)
```

```python-validator
program.allow_only("call")

if not program.calls("print"):
    raise Exception("Use the `print` function.")
if program.calls("print").with_any_args("42") or program.calls("print").with_any_args("3.14"):
    raise Exception("Numbers are written without quotes.")
if program.calls("print").with_args(3, 14):
    raise Exception("Python uses a point as the decimal separator, not a comma: write 3.14.")
if not program.calls("print").times(2):
    raise Exception("Use 2 separate `print` lines: first 42, then 3.14.")
if output != "42\n3.14":
    raise Exception("`print` 42 first, then 3.14.")
```

## What comes out?

```metadata
type: predict-output
id: predict-print
emoji: "🔮"
```

Say what this prints before it runs.

```python-predict
print("Hello")
print(42)
print("Hello", 42)
```

```explanation
Give `print` more than one thing and it puts a **space** between them.
```

## What belongs together?

```metadata
type: match-pairs
id: printing-pairs
emoji: "🧩"
```

Match each call to what it shows.

```pairs
`print("Hi")`
… shows the text Hi.

`print(42)`
… shows the number 42.
```

## Put the program together

```metadata
type: order-lines
id: order-answer
emoji: "🔀"
```

Put the lines in order.

```python-order
print("The answer is:")
print(42)
print("Done!")
```

```python-distractors
print("42")
```

```python-validator
program.allow_only("call")

if program.calls("print").with_any_args("42"):
    raise Exception("One line has `\"42\"` in quotes. Numbers are written without.")
if output != "The answer is:\n42\nDone!":
    raise Exception("First `The answer is:`, then `42`, then `Done!`.")
```
