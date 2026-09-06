# Input and output

Enable user interaction through text input and output.

```metadata
id: input-and-output
emoji: "⌨️"
```

## Introduction

```metadata
type: info
id: introduction
emoji: "👋"
```

Welcome to the first module about Python!

When programmers first start exploring a new programming language, showing a short text message is often the first thing they try.

The message most commonly used for this, and one that is very well known among programmers, is 'Hello, world'. You will come across that same message in this and other tutorials.

The line of code that shows the text 'Hello, world' in Python is:

```python
print("Hello, world")
```

This calls Python's `print` function and tells it what to 'print'. The term printing dates back to the time when computers had no screens. Input was done with physical switches on the computer itself, and output went through a printer. So although the term is a leftover from the past, it is still the standard in many programming languages.

## Printing yourself

```metadata
type: quick-exercise
id: print-yourself
emoji: "✍️"
```

Now write a line of code yourself to "print" a piece of text. Choose your own message.

```python-assignment
```

```python-validator
program.allow_only("call")

if not program.calls("print"):
    raise Exception("Use the `print` function to output text.")
if not program.calls("print").with_any_args(a_string):
    raise Exception('Put your message in quotation marks, for example `print("Hello")`.')
if not output:
    raise Exception("Use the `print` function with a non-empty text.")
```

## Printing different things

```metadata
type: exercise
id: printing-values
emoji: "📦"
```

You have now seen and experienced how to use the `print` function for text. You can use that same function for other types of values too.

You will find more about the different types of values Python knows in a later chapter. For now we will limit ourselves to whole numbers and decimal numbers.

Change the code below so that it first prints the number `42` and then the number Pi to 2 decimal places (2 digits after the decimal point).

Unlike text, numbers are written without quotation marks in Python. Note as well that Python uses a dot as the decimal separator, not a comma: write `3.14`, not `3,14`.

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
    raise Exception("Python uses a dot as the decimal separator, not a comma: write 3.14.")
if not program.calls("print").times(2):
    raise Exception("Use 2 separate `print` lines for this: 42 first, then 3.14.")
if output != "42\n3.14":
    raise Exception("`print` 42 first, then 3.14.")
```

## What comes out?

```metadata
type: predict-output
id: predict-print
emoji: "🔮"
```

Before you run this program: work out for yourself what will appear on the screen. Write your prediction down — exactly as you think it will look, line by line.

Predicting first and looking afterwards works better than going straight for the button. If you are wrong, you see at once where your picture of Python did not match, and that is the part that sticks.

```python-predict
print("Hello")
print(42)
print("Hello", 42)
```

```explanation
The first two lines do what you expect. The third is the surprise: give `print` more than one thing, separated by a comma, and Python puts a **space** between them itself. That space appears nowhere in your code — `print` makes it.
```

## What belongs together?

```metadata
type: match-pairs
id: printing-pairs
emoji: "🧩"
```

You now know what `print` does with text and with numbers. Put together the parts that form one sentence that is true.

```pairs
`print("Hello")`
… shows the text Hello.

`print(42)`
… shows the number 42, with no quotation marks around it.

`print(3.14)`
… uses a dot as the decimal separator, not a comma.

Two `print` lines below one another
… produce two lines of output.
```

## Put the program together

```metadata
type: order-lines
id: order-answer
emoji: "🔀"
```

The lines of a program are jumbled below. Put them in the right order, so that this appears:

```text
The answer is:
42
Done!
```

Watch out: one line does not belong. Two of them look alike — read the quotation marks carefully.

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

if not program.calls("print"):
    raise Exception("Use the `print` function.")
if program.calls("print").with_any_args("42"):
    raise Exception("One of the lines has `\"42\"` in quotation marks. Numbers are written without them.")
if not program.calls("print").times(3):
    raise Exception("Your program is exactly 3 lines.")
if output != "The answer is:\n42\nDone!":
    raise Exception("Order them so that `The answer is:` comes first, then `42`, then `Done!`.")
```
