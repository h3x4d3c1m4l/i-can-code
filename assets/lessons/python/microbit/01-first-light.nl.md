# Eerste licht

Zet je eerste programma op een micro:bit en laat hem hallo zeggen.

```metadata
id: first-light
emoji: "💡"
layout: project
runtime: microbit
group: "Projecten · micro:bit"
```

## Wat je gaat bouwen

```metadata
type: info
id: what-you-build
emoji: "💡"
```

Een programma dat op een echte micro:bit draait. Sluit het bordje aan met een USB-kabel, verbind het rechts, en zet je code erop met **Naar het bordje schrijven**.

## Zeg hallo

```metadata
type: task
id: say-hello
emoji: "👋"
requires: [introduction]
```

In de editor staat al een programma dat `Hello` over het display laat lopen. Zet het op het bordje.

```done-when
`Hello` loopt over het display van de micro:bit.
```

### 💡 Hint {collapsed}

Gebeurt er niets? Controleer of de kabel data doorgeeft, en druk op **Herstarten**.

```python-assignment
from microbit import *

display.scroll("Hello")
```

## Je eigen naam

```metadata
type: task
id: your-name
emoji: "🏷️"
```

Bewaar je naam in een variabele, en laat die over het display lopen.

```done-when
Je eigen naam loopt over het display.
```
