# Bestanden

Een CSV-bestand lezen, en er een schrijven.

```metadata
id: files
icon: table
```

## Het gemiddelde cijfer

```metadata
type: exercise
id: average-grade
emoji: "📊"
```

Naast je programma staat een bestand dat `grades.csv` heet. Elke regel is een
student met een cijfer, en de eerste regel noemt de kolommen. Met de knop van het
bestand zie je wat erin staat.

De module `csv` leest zo'n bestand regel voor regel. `csv.reader` geeft per regel
een lijst terug, met één element per kolom.

Toon het gemiddelde cijfer van alle studenten.

```file grades.csv
{{#include data/grades.csv}}
```

```python-assignment
import csv

with open("grades.csv") as file:
    rows = list(csv.reader(file))
```

```python-validator
import re

if not program.calls("open"):
    raise Exception('Open het bestand met `open("grades.csv")`.')
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
id: who-passed
emoji: "✍️"
```

`csv.writer` schrijft zo'n bestand. Met `writerow` zet je er één regel in, die je
meegeeft als een lijst.

Schrijf naar `passed.csv` de naam van iedereen met een 5.5 of hoger. Begin met de
kop `name`, zoals het programma al doet. Als je programma klaar is, staat het
bestand onder de uitvoer.

```file grades.csv
{{#include data/grades.csv}}
```

```python-assignment
import csv

with open("grades.csv") as file:
    rows = list(csv.reader(file))

with open("passed.csv", "w", newline="") as out:
    writer = csv.writer(out)
    writer.writerow(["name"])
```

```python-validator
import csv

if not program.calls(".writerow"):
    raise Exception("Schrijf de regels weg met `writerow`.")
try:
    with open("passed.csv", newline="") as _bestand:
        rijen = list(csv.reader(_bestand))
except FileNotFoundError:
    raise Exception("Schrijf naar `passed.csv`, met precies die naam.")
if not rijen or rijen[0] != ["name"]:
    raise Exception("Begin het bestand met de regel `name`, de kop van de kolom.")
if rijen[1:] != [["Sanne"], ["Mohammed"], ["Fatima"]]:
    raise Exception(
        "Zet onder de kop de naam van iedereen met een 5.5 of hoger, één per regel, "
        "in de volgorde van `grades.csv`."
    )
```

## Twee cijfers bij elkaar

```metadata
type: predict-output
id: two-grades
emoji: "🔮"
```

Dit programma leest hetzelfde bestand en telt de cijfers van Sanne en Mohammed
bij elkaar op. Wat komt er op het scherm?

```file grades.csv
{{#include data/grades.csv}}
```

```python-predict
import csv

with open("grades.csv") as file:
    rows = list(csv.reader(file))

print(rows[1][1] + rows[2][1])
```

```explanation
Een CSV-bestand bevat alleen tekst, en `csv.reader` geeft die tekst terug zoals hij
in het bestand staat. `"7.5" + "8.0"` plakt twee stukken tekst achter elkaar. Wil
je rekenen, zet het cijfer dan eerst om met `float`.
```
