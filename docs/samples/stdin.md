# Vragen aan de gebruiker

Een programma dat iets aan de gebruiker vraagt.

```metadata
id: stdin-sample
emoji: "⌨️"
```

## Vraag een naam

```metadata
type: exercise
id: ask-a-name
emoji: "🙋"
```

`input` toont een vraag en wacht tot de gebruiker antwoordt. Wat er getypt wordt,
komt terug als tekst.

Vraag om een naam en groet die daarna.

De invoer staat hieronder al klaar, zodat je programma iedere keer hetzelfde te
lezen krijgt.

```stdin
Sanne
```

```python-assignment
naam = input(...)
```

```python-validator
program.allow_only("call", "assignment")

if not program.calls("input").with_args(a_string):
    raise Exception("Geef `input` een vraag mee, zodat de gebruiker weet wat te doen.")
# De uitvoer ziet eruit als een terminal: de vraag, wat er getypt is, en dan de
# groet op een eigen regel. Een check op `output` moet die eerste regel meerekenen.
if not output.endswith("Hallo Sanne"):
    raise Exception("Groet de naam die is ingevoerd, met `Hallo` ervoor.")
```

## Wat komt eruit?

```metadata
type: predict-output
id: predict-a-sum
emoji: "🔮"
```

De gebruiker typt twee getallen in. Voorspel wat er dan op het scherm komt.

```stdin
7
3
```

```python-predict
a = input("Eerste getal: ")
b = input("Tweede getal: ")
print(a + b)
```

```explanation
`input` geeft altijd **tekst** terug, ook als er een getal is ingetypt. `+` plakt
twee stukken tekst dus achter elkaar in plaats van ze op te tellen. Wil je
rekenen, zet de invoer dan eerst om met `int`.

De twee vragen en wat er getypt is staan ook in de uitvoer, net als in een
terminal. Pas de laatste regel is wat `print` ervan maakt.
```
