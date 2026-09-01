# Introductie

Wat Python is en waarom je het zou willen leren.

```metadata
id: introduction
```

## Wat programmeren is

```metadata
type: info
id: coding
```

Programmeren is het schrijven van een computerprogramma. Je schrijft hierbij reeksen instructies welke uitgevoerd kunnen worden door een computer. De programma's voor vroege computers werden veelal geschreven in machinetaal. Machinetaal is de taal die een computer direct (zonder vertaalproces) 'begrijpt'.

Vandaag de dag wordt machinetaal nog maar weinig gebruikt. Dankzij programmeertalen is programmeren toegankelijker geworden. Programmeertalen zoals Python en C zorgen ervoor dat programmeren makkelijker is en het proces beter te begrijpen.

## Keuzes in programmeertalen

```metadata
type: info
id: different-languages
```

Er zijn intussen heel veel programmeertalen. Dat kan de vraag oproepen met welke je zou moeten beginnen. Je zou willen dat er een _heilige graal_ tussen zit. De programmeertaal die makkelijk te leren is, waarmee je vrijwel alles kunt en die een snel programma oplevert. Helaas is het niet zo simpel. Programmeertalen hebben uiteenlopende combinaties van eigenschappen, sommige gunstig en andere minder gunstig.

Op de volgende verdiepingspagina vind je een aantal indelingen. Per indeling en per type is een lijst van populaire programmeertalen te vinden. Aan het einde vind je een toelichting over Python. Je mag deze pagina eventueel overslaan.

## Indelen van programmeertalen

```metadata
type: info
id: sorting-languages
optional: true
```

We onderscheiden programmeertalen op 3 vlakken:

- **Paradigma**: Welke set bekende patronen de programmeertaal (voornamelijk) gebruikt.
- **Manier van code uitvoeren**: Of de code vertaald wordt naar machinetaal voor het uitvoeren, en op welk moment dit vervolgens gebeurt.
- **Omgang met waarden**: Op welk moment de programmeertaal waarden (tekst, getallen, datums, ...) controleert en hoe streng de programmeertaal hiermee omgaat.

Per indeling vind je een lijst van een aantal populaire programmeertalen.

Je kunt onderstaande secties zelf open en dichtklappen.

### Indeling op basis van paradigma {collapsed}

- **Imperatief**: Focus ligt op hoe een taak moet worden uitgevoerd.
  - **Procedureel**: Code wordt opgedeeld in functies/procedures (Basic, C, Go, Pascal, Rust).
  - **Objectgeoriënteerd (OOP)**: Gedrag en data wordt gecombineerd door middel van objecten (C++, C#, Dart, Java, JavaScript, PHP, **Python**, Ruby, Visual Basic).
- **Declaratief**: Focus ligt op wat het resultaat moet zijn van een taak.
  - **Functioneel**: Gebaseerd op wiskundige functies zonder veranderlijke data (Elixir, F#, Haskell).
  - **Logisch**: Gebaseerd op feiten en regels (Prolog).

### Indeling op basis van manier van code uitvoeren {collapsed}

- **Gecompileerd**: De code wordt vóór het uitvoeren in zijn geheel vertaald naar machinetaal. Dat vertalen heet _compileren_. Het resultaat is een programma dat de computer direct kan draaien: snel, maar per soort computer moet er apart gecompileerd worden (C, C++, Go, Haskell, Pascal, Rust).
- **Geïnterpreteerd**: De code wordt tijdens het uitvoeren regel voor regel vertaald door een ander programma, de _interpreter_. Dat is langzamer, maar dezelfde code draait overal waar die interpreter beschikbaar is (Bash, Basic).
- **Hybride**: De code wordt eerst gecompileerd naar een tussentaal (_bytecode_), die vervolgens door een virtuele machine wordt uitgevoerd. Zo combineer je een deel van de snelheid van compileren met de flexibiliteit van interpreteren (C#, Elixir, F#, Java, PHP, **Python**, Ruby).

### Indeling op basis van omgang met waarden {collapsed}

Een programma werkt met _waarden_: een stuk tekst, een getal, een datum. Talen verschillen in hoeveel ze van je willen weten over een gegeven waarde. Ook verschillen ze in hoe streng ze zijn als er iets niet klopt. Dat zijn **twee losse vragen** — een taal kiest bij allebei apart.

- **Wanneer wordt een waarde gecontroleerd?**
  - **Statisch**: Vooraf, tijdens het compileren. Je moet meer opschrijven, maar fouten komen aan het licht vóórdat het programma ooit draait (C, C++, Go, Java, Rust).
  - **Dynamisch**: Pas tijdens het uitvoeren. Je bent sneller aan het schrijven, maar een fout merk je pas als die regel daadwerkelijk aan de beurt is (**Python**, JavaScript, PHP, Ruby).
- **Hoe streng wordt de waarde gecontroleerd?**
  - **Sterk**: de taal weigert te gokken. Combineer je waarden die niet bij elkaar passen, dan krijg je een foutmelding (**Python**, Haskell, Java, Ruby).
  - **Zwak**: de taal past waarden stilletjes voor je aan, zodat er tóch een antwoord uitrolt (C, JavaScript, PHP).

Dat het losse vragen zijn, zie je aan C en Python: C wil alles vooraf weten maar is soepel in wat het accepteert, terwijl Python juist niets vooraf wil weten en daarna streng is.

### Waar Python staat

Python is dus een objectgeoriënteerde taal, die hybride wordt uitgevoerd, en die dynamisch maar sterk met waarden omgaat. In de praktijk betekent dat drie dingen:

- Alles waarmee je in Python werkt is een object: data met gedrag eraan vast. Een stuk tekst weet zelf hoe het zichzelf in hoofdletters schrijft, en daar vraag je met een punt om: `naam.upper()`. Zelf objecten ontwerpen komt later in de cursus; gebruiken doe je ze vanaf je eerste regel code.
- Het compileren naar bytecode gebeurt automatisch en merk je nauwelijks: je schrijft je code, je draait je programma. Het maakt Python in theorie iets langzamer dan talen waarbij de code eerst geheel naar machinetaal gecompileerd wordt.
- Je hoeft nergens expliciet een waarde-soort op te geven in je code. Dat scheelt tikwerk en maakt Python makkelijker om mee te beginnen. Tegelijk kan dit een valkuil zijn, doordat een fout hierin pas op een later moment kan opvallen.
