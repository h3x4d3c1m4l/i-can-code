# First light

Put your first program on a micro:bit and make it say hello.

```metadata
id: first-light
emoji: "💡"
layout: project
runtime: microbit
group: "Projects · micro:bit"
```

## What you will build

```metadata
type: info
id: what-you-build
emoji: "💡"
```

A program that runs on a real micro:bit. Plug the board in with a USB cable, connect it on the right, and write your code to it with **Write to the board**.

## Say hello

```metadata
type: task
id: say-hello
emoji: "👋"
requires: [introduction]
```

The editor already holds a program that scrolls `Hello` across the display. Write it to the board.

```done-when
`Hello` scrolls across the micro:bit's display.
```

### 💡 Hint {collapsed}

Nothing happens? Check that the cable carries data, and press **Restart**.

```python-assignment
from microbit import *

display.scroll("Hello")
```

## Your own name

```metadata
type: task
id: your-name
emoji: "🏷️"
```

Store your name in a variable, and scroll that instead.

```done-when
Your own name scrolls across the display.
```
