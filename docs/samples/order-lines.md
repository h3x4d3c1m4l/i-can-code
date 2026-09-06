# Sample: put the lines in order

One `order-lines` section: the program's own lines, shuffled, for the student to
arrange.

```metadata
id: sample-order-lines
emoji: "🔀"
```

## Build the countdown

```metadata
type: order-lines
id: order-countdown
emoji: "🔀"
```

An `order-lines` step carries a `<lang>-order` block — the lines **in the order
the author wrote them**, which is the one order the board never deals. There is
no editor: the syntax is given, so what is being practised is the shape of the
program.

**The check is the assembled program**, run through the section's ordinary
validator, never the arrangement compared against the file. An order that is
different but correct still passes, which is the whole reason it is checked this
way.

Each line keeps its own leading whitespace, so indentation travels with the line
and the student arranges a program rather than also having to indent it.

The optional `<lang>-distractors` block adds lines that belong to no correct
program. They need nothing of the board: used, they make the assembled program
wrong, and the validator says so the way it would about any other mistake.

```python-order
for count in range(3, 0, -1):
    print(count)
print("Go!")
```

```python-distractors
print("Ready?")
    print(count + 1)
```

```python-validator
if output != "3\n2\n1\nGo!":
    raise Exception("Count down 3, 2, 1 and then print Go!")
```
