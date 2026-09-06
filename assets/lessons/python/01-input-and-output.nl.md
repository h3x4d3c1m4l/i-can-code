# Invoer en uitvoer

Maak gebruikersinteractie mogelijk via tekstinvoer en -uitvoer.

```metadata
id: input-and-output
emoji: "⌨️"
```

## Introductie

```metadata
type: info
id: introduction
emoji: "👋"
```

Welkom bij de eerste module over Python!

Wanneer programmeurs voor het eerst een nieuwe programmeertaal gaan verkennen, is het tonen van een kort tekstbericht vaak het eerste dat ze uitproberen.

Het bericht dat men hiervoor vaak gebruikt, en dat onder programmeurs erg bekend is, luidt 'Hello, world'. In deze en andere tutorials zul je dan ook hetzelfde bericht tegenkomen.

De regel code om met Python de tekst 'Hello, world' te tonen luidt:

```python
print("Hello, world")
```

Hiermee roep je de `print`-functie in Python aan en vertel je deze functie wat hij moet 'printen'. De term printen stamt af van de tijd dat computers nog geen beeldscherm hadden. Invoer ging met fysieke knoppen op de computer zelf en uitvoer ging middels een printer. Hoewel deze term dus een overblijfsel uit het verleden is, is het nog steeds de standaard binnen veel programmeertalen.

## Zelf "printen"

```metadata
type: quick-exercise
id: print-yourself
emoji: "✍️"
```

Schrijf nu zelf een regel code om een stukje tekst te "printen". Kies zelf de boodschap.

```python-assignment
```

```python-validator
program.allow_only("call")

if not program.calls("print"):
    raise Exception("Gebruik de `print`-functie om tekst uit te voeren.")
if not program.calls("print").with_any_args(a_string):
    raise Exception('Zet je boodschap tussen aanhalingstekens, bijvoorbeeld `print("Hallo")`.')
if not output:
    raise Exception("Gebruik de `print`-functie met een niet-lege tekst.")
```

## Verschillende dingen printen

```metadata
type: exercise
id: printing-values
emoji: "📦"
```

Je hebt nu gezien én ervaren hoe je de `print`-functie kunt gebruiken voor tekst. Je kunt dezelfde functie ook gebruiken voor andere typen waarden.

Meer over de verschillende typen waarden die Python kent, vind je in een volgend hoofdstuk. Voor nu beperken we ons tot gehele getallen en kommagetallen.

Pas de volgende code aan om eerst het getal `42` te printen en daarna het getal Pi op 2 decimalen (2 cijfers achter de komma).

Anders dan bij tekst gebruik je bij getallen geen aanhalingstekens. Let er ook op dat Python een punt als decimaalteken gebruikt en geen komma: schrijf dus `3.14` en niet `3,14`.

```python-assignment
print(...)
print(...)
```

```python-validator
program.allow_only("call")

if not program.calls("print"):
    raise Exception("Gebruik de `print`-functie.")
if program.calls("print").with_any_args("42") or program.calls("print").with_any_args("3.14"):
    raise Exception("Getallen schrijf je zonder aanhalingstekens.")
if program.calls("print").with_args(3, 14):
    raise Exception("Python gebruikt een punt als decimaalteken, geen komma: schrijf 3.14.")
if not program.calls("print").times(2):
    raise Exception("Gebruik hiervoor 2 losse `print`-regels: eerst 42, daarna 3.14.")
if output != "42\n3.14":
    raise Exception("`print` eerst 42, daarna 3.14.")
```

## Wat hoort bij elkaar?

```metadata
type: match-pairs
id: printing-pairs
emoji: "🧩"
```

Je weet nu wat `print` met tekst en met getallen doet. Zet de stukjes bij elkaar die samen één kloppende zin vormen.

```pairs
`print("Hallo")`
… toont de tekst Hallo.

`print(42)`
… toont het getal 42, zonder aanhalingstekens eromheen.

`print(3.14)`
… gebruikt een punt als decimaalteken, geen komma.

Twee `print`-regels onder elkaar
… geven twee regels uitvoer.
```
