# Gegevens uit een bestand

Een programma dat een CSV-bestand leest en er een schrijft.

```metadata
id: file-sample
icon: table
```

## Het gemiddelde cijfer

```metadata
type: exercise
id: read-a-csv
emoji: "📊"
```

Naast je programma staat `cijfers.csv`. Elke regel is een student met een cijfer,
en de eerste regel noemt de kolommen.

De module `csv` leest zo'n bestand regel voor regel. `csv.reader` geeft per regel
een lijst terug, met één element per kolom.

Toon het gemiddelde cijfer van alle studenten.

```file cijfers.csv
naam,cijfer
Sanne,7.5
Mohammed,8.0
Tim,4.5
Fatima,9.0
```

```python-assignment
import csv

with open("cijfers.csv") as bestand:
    regels = list(csv.reader(bestand))
```

```python-validator
import re

if not program.calls("open"):
    raise Exception('Open het bestand met `open("cijfers.csv")`.')
if program.calls("print").with_args(7.25) or program.calls("print").with_args("7.25"):
    raise Exception("Reken het gemiddelde uit met de cijfers uit het bestand, in plaats van het over te typen.")
getallen = re.findall(r"-?\d+(?:\.\d+)?", output)
if not getallen:
    raise Exception("Toon het gemiddelde met `print`.")
if float(getallen[-1]) != 7.25:
    raise Exception(
        "Tel de cijfers op en deel door het aantal studenten. De eerste regel bevat de kopjes, "
        "die tel je niet mee."
    )
```

## Wie is er geslaagd?

```metadata
type: exercise
id: write-a-csv
emoji: "✍️"
```

`csv.writer` schrijft zo'n bestand. Met `writerow` zet je er één regel in, die je
meegeeft als een lijst.

Schrijf naar `geslaagd.csv` de namen van iedereen met een 5.5 of hoger. Begin met
de kop `naam`, zoals het programma al doet. Als je programma klaar is, staat het
bestand onder de uitvoer.

```file cijfers.csv
naam,cijfer
Sanne,7.5
Mohammed,8.0
Tim,4.5
Fatima,9.0
```

```python-assignment
import csv

with open("cijfers.csv") as bestand:
    regels = list(csv.reader(bestand))

with open("geslaagd.csv", "w", newline="") as uit:
    schrijver = csv.writer(uit)
    schrijver.writerow(["naam"])
```

```python-validator
import csv

if not program.calls(".writerow"):
    raise Exception("Schrijf de regels weg met `writerow`.")
try:
    with open("geslaagd.csv", newline="") as _bestand:
        rijen = list(csv.reader(_bestand))
except FileNotFoundError:
    raise Exception("Schrijf naar `geslaagd.csv`, met precies die naam.")
if not rijen or rijen[0] != ["naam"]:
    raise Exception("Begin het bestand met de regel `naam`, de kop van de kolom.")
if rijen[1:] != [["Sanne"], ["Mohammed"], ["Fatima"]]:
    raise Exception(
        "Zet onder de kop de naam van iedereen met een 5.5 of hoger, één per regel, "
        "in de volgorde van `cijfers.csv`."
    )
```

## Twee cijfers bij elkaar

```metadata
type: predict-output
id: predict-csv-text
emoji: "🔮"
```

Dit programma leest hetzelfde bestand en telt de cijfers van Sanne en Mohammed
bij elkaar op. Wat komt er op het scherm?

```file cijfers.csv
naam,cijfer
Sanne,7.5
Mohammed,8.0
Tim,4.5
Fatima,9.0
```

```python-predict
import csv

with open("cijfers.csv") as bestand:
    regels = list(csv.reader(bestand))

print(regels[1][1] + regels[2][1])
```

```explanation
Een CSV-bestand bevat alleen tekst, en `csv.reader` geeft die tekst terug zoals hij
in het bestand staat. `"7.5" + "8.0"` plakt twee stukken tekst achter elkaar. Wil
je rekenen, zet het cijfer dan eerst om met `float`.
```
