# Sample: a quick exercise

One `quick-exercise` section: prose and a one-line editor, stacked.

```metadata
id: sample-quick-exercise
emoji: "✍️"
```

## Print something yourself

```metadata
type: quick-exercise
id: print-yourself
emoji: "✍️"
```

A `quick-exercise` is a question of a sentence or two whose answer is one line,
so the prose and the editor stack in a single column and the editor is sized to
exactly one line.

Write a line of code that prints a piece of text.

```python-assignment
```

```python-validator
program.allow_only("call")

if not program.calls("print"):
    raise Exception("Use the `print` function to show a piece of text.")
if not program.calls("print").with_args(a_string):
    raise Exception("Put your text between quotation marks.")
```
