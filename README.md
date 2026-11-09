# Produktions Planer

Desktop-App für die **Produktionsplanung in der Fleischverarbeitung** —
für Windows, Linux und macOS aus einer Flutter-Codebasis. Alles liegt in
einer lokalen SQLite-Datenbank: kein Server, kein Konto, keine Cloud.

Das Ziel: Jede Abteilung ist an jedem Arbeitstag gut ausgelastet, und jeder
Auftrag hat eine realistische Dauer. Die Dauer kommt aus hinterlegten
Leistungsdaten oder aus den erfassten Produktionen — mit jeder Erfassung wird
die Planung genauer. Das ist Statistik, keine KI: Mittelwerte, die sich
nachrechnen lassen.

```
Navision (Excel)                      Stammdaten (Artikel, Prozessketten,
 ├─ Auftragsbestand ──▶ Bedarf         Anlagen, Parameter, Leistungsdaten)
 └─ Artikelübersicht ─▶ Artikel                     │
                           │                        │
                           ▼                        ▼
                  Planungsvorschlag ──▶ Planungsboard (Abteilungen × Tage)
                                                    │
                                                    ▼
                                      Produktionserfassung (Ist)
                                                    │
                     Wochen-Historie · Statistik ◀──┴──▶ genauere Dauer
```

## Bereiche

| Gruppe      | Bereich               | Wofür                                                                                       |
| ----------- | --------------------- | ------------------------------------------------------------------------------------------- |
|             | Übersicht             | Der heutige Tag: Aufträge und Auslastung aller Abteilungen, „Artikel planen"                 |
| Planen      | Bedarf                | Offene Bedarfe; geplant ist, was an verknüpften Aufträgen im Board steht                     |
|             | Auftragsbestand       | Navision-Bericht „Auftragsbestand" einlesen, Deckung aus Lager und Produktion, Änderungen    |
|             | Planungsvorschlag     | Entwurf für die nächsten Tage samt Rüst- und Reinigungszeiten, tageweise ins Board           |
|             | Planungsboard         | Woche (Abteilungen × Tage mit Kapazitätsbalken) und Tag (Zeitbalken), Ziehen, Drucken        |
| Auswerten   | Produktionserfassung  | Ist-Mengen samt Fleischeinwaage und -Zeiten: Verlust, kg/h; die Kette im Board wird erledigt |
|             | Wochen-Historie       | Eingefrorene Wochenpläne mit Kennzahlen je Abteilung                                         |
|             | Statistik             | Engpässe, Zeitverteilung, Planerfüllung, Ausbeute, Leistung, Lücken in den Stammdaten        |
| Stammdaten  | Artikel               | Prozesskette (Stationen und Anlagen), Parameter, Leistungsdaten, Produktionen, Datenblatt    |
|             | Navision-Artikel      | Artikelübersicht aus Navision abgleichen: neue Artikel und Allergene übernehmen              |
|             | Maschinen-Katalog     | Anlagen, Steckbriefe ihrer Parameter, Plausibilitätsgrenzen                                  |
| Entwickeln  | Produktentwicklung    | Projekte, Rezepturen und Zutaten — hinter einem eigenen Passwort (siehe unten)               |
|             | Einstellungen         | Kapazität je Abteilung, Darstellung, Stammdaten-Mappe, Backups, Zurücksetzen                 |

Im Board zeigt jede Abteilung je Tag einen Balken bis zu ihrer Kapazität
(grau = frei, grün = gut gefüllt, rot = überbucht). Erledigtes wird grün:
Karten lassen sich abhaken, und sobald eine Produktion erfasst ist, wird ihre
ganze Kette grün. Unter den Anlagen hat jede Abteilung eine Zeile „Sonstige
Aufgaben" für alles, was nicht aus einem Artikel kommt.

Ein Auftrag im Board öffnet sein Fenster mit den Mengen der ganzen
Produktion untereinander: **Rohware, Fertigware und Fleischeinwaage**,
darunter Verlust und Fleischanteil mit ihrer Herkunft (wie geplant, Ø der
letzten Produktionen oder aus der Rezeptur). Jedes Feld lässt sich ändern,
die anderen rechnen mit. Bis einschließlich Bratstraße arbeiten die
Aufträge einer Produktion mit der Rohware, danach mit der Fertigware —
das Fenster sagt, womit der geöffnete arbeitet. Beim Speichern ziehen alle
Aufträge der Produktion mit (auf Tage verteilte Teile im selben
Verhältnis) und bekommen eine neu gerechnete Dauer; die Fertigware zählt
für den Bedarf. Die geplante Fleischeinwaage steht auf dem Datenblatt und
ist in der Produktionserfassung schon eingetragen.

Die acht Abteilungen sind ein Dart-Enum in
`lib/core/constants/abteilungen.dart`: Zerlegung, Wurstküche,
Kutterabteilung, Bratstraße, Schneideabteilung, Verpackung, Verpackung Tef1,
Verpackung Tef2.

## Drucken

Jeder Druck öffnet dasselbe **Druckfenster**: links, was und wie gedruckt
wird, rechts die Vorschau, die jeder Änderung folgt. Dann „Drucken …" (der
Druckdialog von Windows) oder „Als PDF speichern …". Das Fenster merkt sich
je Dokument, womit zuletzt gedruckt wurde; „Zurücksetzen" holt den
Standard. Strg+P druckt.

- **Wie:** Papier A4, A3 oder A5 (das ganze Blatt wird vergrößert oder
  verkleinert, wie am Kopierer), Hoch- oder Querformat (oder wie das
  Dokument es vorsieht), Originalgröße, verkleinert auf 90–50 %, **alles
  auf eine Seite** oder auf höchstens zwei Seiten — je Blatt so groß wie
  möglich —, schmale Ränder, Graustufen. Passt ein Blatt selbst bei 30 %
  nicht, sagt es das Fenster.
- **Was**, je Dokument:
  - **Plan** (Planungsboard): Woche oder Tag, gesamte Übersicht oder je
    Abteilung ein Blatt, welche Abteilungen und Tage, sonstige Aufgaben,
    Erledigtes, Kästchen zum Abhaken, Anlagen ohne Aufträge, Dauer und
    Belegung.
  - **Erfassungsliste** (Produktionserfassung): die noch nicht erfassten
    Produktionen der Woche mit leeren Spalten für die Ist-Werte —
    Rohware, davon Fleisch, Fertigware, Start und Ende, dazu Charge,
    Kürzel und Bemerkung —, welche Tage und Abteilungen, die Tage
    untereinander oder jeder auf eigenem Blatt zum Aushängen, was geplant
    ist, leere Zeilen zum Nachtragen.
  - **Archivierter Wochenplan** (Wochen-Historie, Wochenplan einer
    archivierten Woche): der Plan, wie er beim Archivieren stand — mit
    „Archiv" und dem Stand in Kopf und Fuß, damit er nicht für den
    aktuellen gehalten wird; Übersicht oder je Abteilung ein Blatt, welche
    Abteilungen und Tage, sonstige Aufgaben, Erledigtes.
  - **Wochenauswertung** (Auswertung einer archivierten Woche):
    Kennzahlen, Auslastung je Abteilung gegen die Kapazität beim
    Archivieren, die Aufträge Tag für Tag (auf Wunsch mit ihren Notizen),
    Rüst-, Reinigungs- und sonstige Zeiten einzeln, die Erkenntnisse — so,
    wie sie gerade im Feld stehen —, welche Abteilungen.
  - **Wochen im Überblick** (Wochen-Historie): je archivierte Woche eine
    Zeile mit Aufträgen, Menge, Belegung und Auslastung, auf Wunsch je
    Abteilung, dazu die Erkenntnisse; der Monat im Kalender, die letzten
    4, 13 oder 52 Wochen oder alle.
  - **Statistik**: der Zeitraum der Seite, welche Teile, alle Abteilungen
    oder eine (vorgewählt: die der Seite), die Verläufe je Woche oder Monat
    als Tabellen, die Erklärungen, jeder Teil auf einer neuen Seite. Statt
    der Diagramme stehen Tabellen mit Balken auf dem Blatt.
  - **Auftragsbestand**: nach Artikel (mit Versandtagen, Aufträgen,
    Vormerkungen und Produktionen), nach Versandtag oder nach Kunde; nur
    mit Handlungsbedarf, alles nicht Gedeckte oder alles; Versandtage bis
    Ende dieser oder nächster Woche; auf die gefilterte Liste beschränkt;
    Kennzahlen. Vorgewählt ist, was die Liste zeigt.
  - **Bedarfsliste**: offene oder auch erledigte Bedarfe, nach Termin
    (Überfälliges zuerst, dann je Kalenderwoche) oder nach Artikelnummer,
    welche Herkunft, Herkunft und Notiz.
  - **Planungsvorschlag**: so, wie er in der Ansicht steht — auch von Hand
    angepasst —, welche Tage, untereinander oder je Tag ein Blatt,
    Hinweise und Regelbrüche, Aufträge aus dem Auftragsbestand, was nicht
    eingeplant werden konnte. Bis ein Tag ins Board übernommen ist, steht
    er als Entwurf auf dem Blatt.
  - **Prozessblatt** (Artikel): Abteilungen und Schritte, jede Abteilung
    auf eigener Seite, Leistungsdaten, Kennwerte, Plattenraster,
    Maschineneinstellungen, Parameter, Notizen, Linien für Notizen von
    Hand.
  - **Artikelliste** (Artikel-Stammdaten): wie die Liste gefiltert, alle
    oder nur die mit Lücken; sortiert wie die Liste, nach Artikelnummer,
    nach Bezeichnung, je Produktgruppe oder je Abteilung (ein Artikel bei
    jeder seiner Abteilungen); je Artikel Gruppe, die Abteilungen des
    Prozesses als Kürzel, Schritte, die Anlagen mit Namen und was der
    Planung fehlt; Kennzahlen, eine leere Spalte für Notizen.
  - **Maschinen-Katalog**: als Übersicht eine Zeile je Anlage (Eignung,
    Planungsspur, Steckbrief, Zahl der Grenzen und Artikel) oder als
    Steckbriefe — je Anlage ihre Parameter mit Einheit und Grenzwerten und
    die Artikel, die sie nutzen; welche Abteilungen, jede Abteilung oder
    jede Anlage auf einer neuen Seite (zum Aushängen).
  - **Maschinen-Grenzen**: je Anlage oder Parametergruppe die harte Grenze
    und die Warnung, Notizen, auf Wunsch die Parameter des Steckbriefs
    ohne Grenze, jede Anlage auf einer eigenen Seite zum Aushängen.
  - **Datenblatt** (Board, Bedarf, Auftragsbestand, Planungsvorschlag):
    welche Blätter, Mengen und Tag (Fertigware, Rohware, Fleischeinwaage —
    ohne geplante über den Fleischanteil geschätzt), Stand, Merkmale,
    Notiz, Ablauf, Aufträge — auch ohne Kundennamen zum Aushängen —, Feld
    für die Rückmeldung.
  - **Etikett-Entwurf**: Breite des Etiketts (80, 110 oder 150 mm), Kopf,
    Nährwerttabelle, Platzhalter, was noch offen ist.
  - **Projektbericht**: Kapitel, Steckbrief, Inhaltsverzeichnis, Verlauf als
    Zeitstrahl und im Einzelnen, Kapitel auf neuen Seiten oder fortlaufend;
    links unten „Kopf- und Fußzeile …" — die Vorschau folgt gleich.
  - **Rezepturblatt** (Rezeptur, Knopf neben „Mehr"): ein Stand mit Mengen
    wie in der Rezeptur, **umgerechnet auf eine Ansatzgröße oder ein
    Endgewicht** (in kg einzugeben; der Verlust ist eingerechnet), nur mit
    Anteilen oder ganz ohne Mengen — etwa zum Weitergeben. Vor jeder Zutat
    ihre Artikelnummer aus dem Katalog (abwählbar). Dazu Kennzahlen,
    Beschreibung und Grund des Stands, die Unterrezepturen mit ihren
    Zutaten (auf die eingesetzte Menge umgerechnet, auch verschachtelt),
    Zutatenverzeichnis, Nährwerte wie auf dem Etikett, Allergene und
    Hilfsstoffe, Fleisch nach LMIV, Hinweise der Berechnung. Für die
    Produktion: je Zutat ein Kästchen mit Soll, Ist und Rohstoff-Charge,
    Felder für Datum, Charge, Ansatz und Kürzel. Ein Entwurf ist als
    Entwurf gekennzeichnet.
  - **Stände im Vergleich** (Rezeptur, „Mehr" oder im Vergleich zweier
    Stände): zwei bis acht Stände nebeneinander — Mengen in kg oder als
    Anteil, Kennzahlen und Nährwerte, was anders ist als im Stand davor
    fett, in Sätzen, was sich geändert hat, Bezeichnung und Grund jedes
    Stands, auf Wunsch das Zutatenverzeichnis.
  - **Projektliste** (Projekte): Status wie die Liste oder alle, die Suche
    der Liste, zuletzt bewegt zuerst, nach Name oder je Kunde, Muster der
    Gesamtprojekte einzeln, was als Nächstes kommt und was im Verlauf offen
    (rot: überfällig) ist, die Produktidee.
  - **Zutaten** (Katalog): alle, nur Fleisch, nur mit Allergenen oder nur
    die ohne Nährwerte, nach Name oder nach Art (Fleisch je Tierart,
    Wasser, übrige), Nährwerte je 100 g als Spalten, Etikett und
    Unterzutaten; mit der Suche der Liste.

Der Satz (`lib/core/druck/`) legt jedes Blatt auf eine gedachte, größere
Seite und verkleinert beim Zeichnen — so bricht der Text über die volle
Breite um, und Links und Lesezeichen im PDF stimmen auch verkleinert. Die
Listen teilen sich Kopf, Fuß, Tabellen und Leisten
(`druck_bausteine.dart`): schwarz und grau, Farbe nur als Kante oder Punkt
neben dem Text.

## Produktentwicklung

Ein eigener Bereich für die Entwicklung neuer Produkte. Er ist mit einem
eigenen Passwort gesperrt; seine Daten liegen in eigenen Tabellen
(`entwicklung_*`), Anhänge und Vorlagen verschlüsselt (ChaCha20-Poly1305).

- **Projekte** in sechs Reitern: **Verlauf** (mit Kommentaren),
  **Übersicht** (Stammdaten mit Artikelnummer und Fließdiagramm, Ziele für
  Fett, Eiweiß und aw, Notizen, Freigabe, Produktfoto klein, Rezepturen,
  Checkliste), **Rezeptur** (die Rezeptur gleich im Projekt, mit Ständen,
  Zusammensetzung und Ergebnis wie auf ihrer eigenen Seite — bei mehreren
  oben zur Wahl; Rezepturen aus Übersicht, Checkliste und Verlauf öffnen
  sich hier), **Produkt** (Sensorik mit Produktfoto, Maßen, Stückgewicht
  und Toleranz, Angaben und Verpackung für die Spezifikation, daneben was
  mit einem Stand in der Spezifikation stünde), **Herstellung** (Prozess
  und die HACCP-Gefahrenanalyse — breit nebeneinander, schmal zum
  Umschalten) und
  **Dateien**. Jede Angabe gibt es nur einmal. Der **Prozess** ist eine
  Kette wie im Artikel: Stationen nach Abteilung an einer nummerierten
  Leiste, darin die Anlagen aus dem Katalog der Planung („+ Anlage", auch
  aus einer anderen Abteilung, oder ein Schritt ohne Anlage wie
  „Abkühlen"); Anlagen und ganze Stationen lassen sich ziehen. Antippen
  öffnet einen Schritt mit seinen Werten: Plattenschema an Bratstraße und
  Kombiofen, sonst die Maschineneinstellungen, dazu der Steckbrief der
  Anlage (mit den Grenzen aus den Einstellungen) und eigene Werte — ohne
  Personen und Leistungsdaten, die bekommt der Artikel. Die Kette lässt
  sich aus einem Artikel oder einem anderen Projekt übernehmen; frühere
  Abschnitte werden beim ersten Öffnen zur Kette. Der Prozess speichert
  sich selbst; „Version festhalten" legt den Stand mit Nummer und Notiz ab
  und trägt ihn in den Verlauf ein, „seitdem geändert" zeigt, wenn der
  Arbeitsstand davon abweicht (zurück zur Version und Vergleichen unter
  „Mehr").
  Über jedem Reiter steht der **Projektkopf**: die Phase (Entwicklung ›
  Validierung › Produktion — antippen wechselt nach einer Rückfrage, der
  Wechsel steht als Meilenstein im Verlauf), der Fortschritt der
  Checkliste, „Als Nächstes" mit dem Weg dorthin, dezent was
  zurückgestellt ist und noch fehlt, wie viele Angaben fehlen, und die
  offenen Einträge im Verlauf. „3 Angaben fehlen — ergänzen…" startet einen
  **Assistenten**, der nur fragt, was fehlt (Artikelnummer, Sensorik,
  Produktfoto, Lagerung, Haltbarkeit, Verpackung) — eine Angabe nach der
  anderen, mit „Weiter" und „Später"; das Fenster der Spezifikation bietet
  ihn an, wenn dort etwas leer bliebe.
  Spezifikation, Etikett und Projektbericht stehen oben unter „Erstellen",
  Umbenennen, Nicht weiter verfolgen, Archivieren (und Wiederaufnehmen),
  Gesamtprojekt und Löschen im Menü daneben; ist das Projekt freigegeben, führt „Artikel …" davor mit einem
  Klick zum Artikel der Planung. In der Projektliste steht die
  Artikelnummer vorn — bei freigegebenen Projekten ein Verweis auf den
  Artikel —, unter dem Namen, was als Nächstes zu tun ist und wie viele
  Einträge im Verlauf offen sind. Die Projekt-Checkliste rechnet sich
  selbst: Rezeptur (ein abgeschlossener Stand), Nährwerte (alle Zutaten des
  Stands mit Werten), Sensorik (Aussehen, Geruch, Geschmack, Konsistenz),
  Produktfoto, Prozess, Spezifikation und Artikel (Freigabe) sieht die App
  dem Projekt an. Das Produktfoto lässt sich mit „Später" zurückstellen,
  solange es keins gibt: Es bleibt offen, „Als Nächstes" geht aber weiter,
  und der Kopf zeigt „Produktfoto fehlt noch". „Etikett erstellt" klappt
  die zwölf Pflichtangaben nach LMIV auf und ist erledigt,
  sobald jede abgehakt ist oder „trifft nicht zu" (ein früherer Haken von
  Hand gilt weiter) — von Hand bleibt nur Navision. Darunter liegt das
  **Originaletikett**: der Scan des gedruckten Etiketts, ein Bild oder ein
  PDF (die App zeigt dessen erste Seiten als Bilder), mit Vorschau, groß
  ansehen, ersetzen und lösen. Ist das Etikett im Scan zu klein (etwa ein
  kleines Etikett auf einem A4-Scan), zoomt man mit „Vergrößern …" in einem
  Rahmen von der Form seines Platzes im Bericht darauf (Mausrad, Regler,
  verschieben mit der Maus, bis zehnfach); der Bericht zeigt dann nur
  diesen Ausschnitt, so groß, wie Platz ist, mit dem Vermerk
  „vergrößerter Ausschnitt" — bei einem PDF auf jeder Seite. „Ganzes
  Etikett" nimmt ihn zurück. Ein neuer Scan ersetzt den alten, der unter
  „Dateien" bleibt, und zeigt wieder das ganze Etikett; dort ist das
  Originaletikett gekennzeichnet. Für den
  Punkt zählt es nicht — er sagt nur „Originaletikett hinterlegt" oder
  „… fehlt noch". Liste, Übersicht,
  Zahlen und Bericht zählen gleich. Einträge im Verlauf sind offen oder erledigt
  (antippen schaltet um). „Fällig bis" nimmt ein Datum, eine Kalenderwoche
  oder einen Satz; ist der Tag vorbei und der Eintrag noch offen, steht er
  als überfällig da — in der Karte, auf dem Zeitstrahl, im Kopf, in der
  Projektliste und im Bericht.
- **Gesamtprojekte mit Mustern:** Geht es in einer Anfrage um mehrere
  Produkte, wird sie ein Gesamtprojekt („Neues Projekt" → „Mehrere
  Muster", mit den Namen der Muster). Das Gesamtprojekt sammelt, was alle
  betrifft — Kunde, Anfrage, Notizen, Mails und Unterlagen — in drei
  Reitern: **Übersicht** (die Muster als Karten mit Phase, „Als Nächstes",
  Checkliste und — bei einem, das nicht weiter verfolgt wird — dem
  Grund; „Neues Muster"), **Verlauf** (Korrespondenz und Dateien, dazu die
  Meilensteine der Muster mit deren Namen, abschaltbar) und **Dateien**.
  Jedes Muster ist ein Projekt mit eigenen Rezepturen, eigener Herstellung
  und eigener Freigabe; der Kunde kommt vom Gesamtprojekt. Oben steht der
  Weg zurück zum Gesamtprojekt, in der Übersicht die anderen Muster. Sein
  Verlauf zeigt die Einträge des Gesamtprojekts mit, gekennzeichnet und
  abschaltbar („Aus dem Gesamtprojekt"). Eine Mail auf ein Muster gezogen:
  Die App fragt, ob sie ins Gesamtprojekt gehört (vorgewählt) oder nur zum
  Muster. Einträge und Dateien lassen sich zwischen Gesamtprojekt und
  Mustern verschieben (eine Mail mit ihren Anhängen). Ein bestehendes
  Projekt kommt über das Menü in ein Gesamtprojekt — in ein bestehendes
  oder in ein neues, dann auf Wunsch mit seinen Mails. Ein Muster, das
  nicht weiter verfolgt wird, ruht mit Grund (er steht im Verlauf) und
  lässt sich wieder aufnehmen. In der Projektliste steht ein
  Gesamtprojekt mit seinen Mustern darunter (zuklappbar) und „5 Muster:
  1 in Produktion, …"; der Filter „Nicht weiter verfolgt" zeigt die
  ruhenden. Der Projektbericht eines Musters nennt das Gesamtprojekt mit
  allen Mustern und nimmt auf Wunsch dessen Mails in den Verlauf.
- **HACCP-Entscheidungsbaum** wie im HACCP-Konzept: Frage 1 (Kontroll-
  maßnahmen vorhanden?) mit Zusatzfrage (Kontrolle hier aus
  Sicherheitsgründen nötig? ja → Schritt, Verfahren oder Produkt
  modifizieren und neu prüfen, nein → CP), Frage 2 (eliminiert oder
  reduziert dieser Schritt die Gefahr? ja → CCP), Frage 3 (Kontamination
  oder Anstieg möglich? nein → CP), Frage 4 (ein späterer Schritt? ja →
  CP, nein → CCP).
- **HACCP „Nichts Neues"**: Bewertet wird nur ein Prozess, den das
  bestehende HACCP-Konzept noch nicht abdeckt. Bringt ein Projekt nichts
  Neues, hakt man oben bei HACCP „Nichts Neues — keine neuen Prozesse"
  an: Gefahrenanalyse und Lenkungspunkte sind dann ausgegraut und
  gesperrt (schon Erfasstes bleibt erhalten, steht aber nicht im
  Bericht). Im Projektbericht steht auf Seite 1 bei HACCP „Nichts Neues",
  im Kapitel Herstellung und HACCP stehen beide Abschnitte ausgegraut, ohne
  Einträge. Der Haken nimmt „Neuer Prozess" in der Übersicht zurück — und
  „Neuer Prozess" den Haken.
- **Fließdiagramme** als Auswahlliste: Kennung und Bezeichnung (etwa
  „FD_101 · Testware paniert"), einmal als Liste eingefügt
  (je Zeile Kennung und Bezeichnung, getrennt durch Tabulator, Semikolon
  oder Leerzeichen). Im Projekt wird das passende ausgewählt; die
  Diagramme selbst pflegt die Qualitätssicherung, PDFs liegen nicht in der
  App. Die Liste gehört zu den Entwicklungsdaten und steht nicht im Code.
- **Rezepturen** in Ständen (Entwurf oder abgeschlossen): Zutatenliste
  nach LMIV mit hervorgehobenen Allergenen, Fleischanteil (QUID), Verlust,
  Nährwerte je 100 g gerundet, Vergleich zweier Stände. Über den Ständen
  steht in Worten, was mit dem gewählten ist, und ein Hauptknopf je nach
  Lage: „Stand abschließen…" beim Entwurf, „Weiterentwickeln" beim
  abgeschlossenen — oder „Zum Entwurf", wenn schon einer in Arbeit ist.
  Vergleichen, Etikett, Fleischanteil, Kopie und Löschen stehen unter
  „Mehr". In der Zusammensetzung steht vor jeder Zutat ihre Artikelnummer.
  Im Entwurf lassen sich die Zeilen am Griff links an eine neue Stelle
  ziehen, und „Austauschen …" im Menü der Zeile setzt eine andere Zutat
  oder Unterrezeptur ein: Menge, Platz und Notiz bleiben, Etikettname und
  QUID gelten wieder wie bei der neuen.
- **Entwicklungsstrang:** Beim Abschließen eines Stands fragt die App „Was
  ist neu und warum?" und vergleicht selbst mit dem vorigen Stand (Zeilen,
  Verlust, Fleischanteil, Nährwerte wie auf dem Etikett, Allergene,
  Mengenangaben) — beides steht mit dem Namen der Rezeptur im Verlauf.
  Statuswechsel (auch durch die Freigabe) werden zu Meilensteinen,
  Einträge lassen sich einem Stand zuordnen („Zu Stand"). Der Verlauf hat
  drei beschriftete Ansichten: Zeitstrahl, Entwicklungsweg und Liste. Der
  Zeitstrahl zeigt die Stände als Stationen, zugeordnete Einträge mit einer Linie zu
  ihrer Station, die Phasen als Band und filtert nach Art; die Ansicht
  „Entwicklungsweg" führt von der Idee über jede Station (Grund,
  Änderungen, Kennzahlen, Rückmeldungen) bis zur Freigabe.
- **Mails im Projekt:** Eine Mail direkt aus Outlook (oder eine .msg/.eml
  aus dem Explorer) auf ein Projekt ziehen — sie steht als E-Mail im
  Verlauf (Betreff, Absender, Datum, Text, die Mail selbst zum Öffnen),
  ihre Anhänge bei den Dateien; andere Dateien kommen als Datei in den
  Verlauf. Auf die Projektliste gezogen, wird aus der Mail ein neues
  Projekt oder Gesamtprojekt (Name, Kunde und Anfrage vorbelegt) — oder
  sie kommt in ein bestehendes Gesamtprojekt. Ohne Ziehen: „Aus Mail…" in
  der Projektliste, „Datei ablegen" im Verlauf. Die App liest .msg und
  .eml selbst; das Ziehen nimmt unter Windows das Fenster entgegen
  (`windows/runner/ablage_ziel.cpp`).
- **Etikett je Stand:** Vorschau mit Zutatenliste, Spuren, Nährwerttabelle
  und Hinweisen aus der Spezifikation, als Text kopieren oder als
  PDF-Entwurf.
- **Zutaten-Katalog** mit Nährwerten, Allergenen, Tierart, Bindegewebe und
  Unterzutaten. Über „Excel" lässt er sich als Mappe speichern, dort pflegen
  und wieder einlesen — je Zutat eine Zeile, Ja/Nein und Tierart als
  Auswahlliste, je Allergen eine Spalte zum Ankreuzen. Eine Zeile findet ihre
  Zutat über die ID, ohne ID über die Artikelnummer, sonst über den Namen;
  ohne Treffer ist sie neu. Eine leere Zelle leert den Wert, eine fehlende
  Spalte lässt ihn, gelöscht wird über die Mappe nichts. Jede Zeile trägt
  ihren Stand beim Export: Hat sich eine Zutat seither nur in der App
  geändert, bleibt die App; hat sie sich auf beiden Seiten geändert, fragt
  die Vorschau je Zutat, welche Seite gilt. Geschrieben wird erst nach der
  Vorschau, alles oder nichts. Die Mappe selbst ist nicht verschlüsselt.
- **Werkzeuge:** Rezeptur aus einem Etikett zurückrechnen, Fleischanteil
  einer Rezeptur (nach Wahl, ihr neuester Stand) auf ein Ziel einstellen,
  Kopf- und Fußzeile und leere Vorlage des Projektberichts.
- **Statistik** (eigener Reiter, etwa für die Managementbewertung am
  Jahresende): Zeitraum nach Jahr, Quartal, Monat oder frei (nicht in die
  Zukunft), dazu ein Kundenfilter. Kennzahlen mit dem Vorjahr: neue Muster
  (davon in Gesamtprojekten), neue Anfragen (Gesamtprojekte), gelistet
  (davon als Artikel freigegeben), nicht weiter verfolgt, Listungsquote
  (Anteil der im Zeitraum angelegten Muster, die heute gelistet sind; unter
  den entschiedenen), Tage bis zur Listung (Mittel und Median), in Arbeit am
  Ende, neue Prozesse und Zutaten, Rezepturstände. Dazu der Verlauf je
  Monat (Quartal, Jahr), was aus den Mustern wurde, je Kunde (antippen
  filtert), die Gründe für „nicht weiter verfolgt", die Muster im Einzelnen
  und der Stand heute (Phasen, Projekte in Arbeit, ruhende, Lücken im
  Zutaten-Katalog). Gezählt wird so: Ein Muster ist jedes Projekt, auch in
  einem Gesamtprojekt. Gelistet heißt in Produktion gegangen (Freigabe als
  Artikel oder von Hand), am Tag des Wechsels im Verlauf. Nicht weiter
  verfolgt zählt, wer im Zeitraum dazu kam und an dessen Ende noch so steht.
  **Bericht …** erstellt daraus ein PDF: Seite 1 auf einen Blick mit
  Vorjahr und Inhalt, dann Kennzahlen (mit „Wie gezählt wird"), Verlauf,
  was aus den Mustern wurde (auch je Kunde), Gründe, die Muster im
  Einzelnen und der Stand heute — Kapitel wählbar, Lesezeichen je Kapitel,
  oben rechts das Logo des Projektberichts (dessen Formblatt-Angaben nicht).
- **Freigabe als Artikel:** Ein abgeschlossener Stand wird zum Artikel der
  Planung; sein Verlust gilt dort als Vorgabe, bis Produktionen erfasst sind.
  Die Prozesskette des Projekts wird die des Artikels: Schritte derselben
  Anlage (ohne Anlage: desselben Namens) bleiben derselbe Schritt mit
  Personen und Leistungsdaten, neue kommen mit einer Person dazu, die Werte
  ändern sich an ihrer Stelle (leere Zeilen der Excel-Vorlage bleiben). Was
  das Projekt nicht mehr hat, entfällt nur mit Haken — das Fenster nennt
  es und zeigt alle Änderungen am Artikel. Weicht der Prozess von der
  zuletzt festgehaltenen Version ab, wird er dabei als neue Version
  festgehalten.
- **Spezifikation** (Excel) auf Deutsch oder Englisch (Texte auf Wunsch
  über DeepL) — ein Fenster für alles, oben unter „Erstellen" oder im
  Reiter „Produkt": Das eigene Formblatt wird in der App
  gewählt und dabei selbst eingerichtet — die App erkennt die Beschriftungen
  (Artikelnummer, Zutaten, Nährwerte, Allergene mit ja/nein/Spuren,
  Verpackung …), setzt Platzhalter wie `{{zutaten}}` und hakt
  Kontrollkästchen an; einer Vorlage, der Platzhalter fehlen, ergänzt sie
  sie beim Erstellen. Was nicht aus Rezeptur oder Sensorik kommt
  (Artikelbezeichnung, Lagerung, Haltbarkeit, Produkthinweise, Spuren,
  Verpackung), steht im Reiter „Produkt", die Artikelnummer in den
  Stammdaten; Kürzel und Datum fragt das Fenster. Das **Produktfoto**
  kommt ins freie Feld neben der Sensorik (`{{produktbild}}`, beim
  Einrichten erkannt): gedreht, wie die Kamera es vermerkt, auf 1200 Pixel
  verkleinert, ohne EXIF-Daten; fehlt es, fragt das Fenster danach. Im
  Reiter „Produkt" zeigt eine Vorschau, was mit dem gewählten Stand
  hineinkommt, und was noch fehlt — mit dem Ort, an dem man es einträgt.
- **Projektbericht** (PDF, oben unter „Erstellen"): die Projektakte zum
  Nachschlagen — für ein laufendes wie für ein abgeschlossenes Projekt.
  Vorn ein Steckbrief mit Phase, Produktfoto, dem Stand auf einen Blick
  (Freigabe, Rezeptur, Checkliste, Prozess, HACCP, offene Punkte, Ziele)
  und dem Inhalt mit Seitenzahlen; die Kapitel stehen auch als Lesezeichen
  im PDF. Dahinter: Projekt (Stammdaten, Phasen, Ziele gegen die Rezeptur,
  Anfrage und Notizen), Rezeptur (der neueste Stand, wie die Rezeptur ihn
  beim Öffnen zeigt — ist ein anderer freigegeben, steht das dabei —:
  Zusammensetzung mit Mengen und Anteilen, Zutatenverzeichnis, Allergene,
  Nährwerte mit dem Stand der Zutatendaten — ein Entwurf rechnet mit denen
  von heute, ein abgeschlossener Stand mit denen seines Abschlusses —,
  Fleisch nach LMIV, die Stände im Vergleich), Produkt und Spezifikation
  (Sensorik, Angaben, Verpackung, Etikett nach LMIV mit dem
  Originaletikett), Herstellung und HACCP (Prozesskette nach Stationen mit
  Werten, die Platten von Bratstraße und Kombiofen als Raster wie im
  Prozessblatt, festgehaltene Versionen, — wenn der Artikel davon
  abweicht — der Prozess im Artikel, Gefahrenanalyse und Lenkungspunkte),
  Freigabe und Checkliste (Artikel, Verlust der Produktion gegen die
  Rezeptur), der Entwicklungsweg (die Stände im Überblick, jede Station mit
  Grund, Kennzahlen, Änderungen und Rückmeldungen), der Verlauf als
  Zeitstrahl wie in der App (Phasen, Stationen, Bezüge zu den Ständen, in
  Zeilen zu sechs Einträgen) mit jedem Eintrag im Einzelnen und die
  Dateien. Was fehlt, steht als Hinweis da. Jedes Kapitel beginnt auf
  einer neuen Seite (im Druckfenster abwählbar: dann fortlaufend). Blöcke
  brechen nicht, sondern beginnen auf der nächsten Seite: ein Schritt mit
  seinen Einstellungen (das Band einer Station bei ihrem ersten Schritt,
  die Überschrift bei der ersten Station), eine Überschrift mit ihrer
  Tabelle, eine Station auf dem Entwicklungsweg, ein Eintrag im Verlauf.
  Nur was länger ist als eine Seite — lange Texte und Tabellen —, läuft
  weiter, beginnt aber nicht ganz unten auf einer Seite; Tabellen
  wiederholen dann ihre Kopfzeile.
- **Kopf- und Fußzeile des Projektberichts** wie auf einem Formblatt, auf
  jeder Seite: oben links die Nummer des Formblatts, in der Mitte der
  Bericht und sein Projekt, rechts das Logo aus der Kopfzeile der
  Spezifikationsvorlage (die deutsche, sonst die englische; JPEG oder PNG,
  so groß, wie die Vorlage es druckt, abschaltbar); unten links „Erstellt
  von", „Geprüft von" und „Version", rechts „Stand", „ersetzt den Stand"
  und darunter die Seite. Die Angaben trägt man unter Werkzeuge »
  Projektbericht oder im Druckfenster des Berichts ein („Kopf- und
  Fußzeile …"); „Neue Version ab heute" zählt die Version weiter, setzt
  den Stand auf heute und trägt den bisherigen bei „ersetzt den Stand" ein.
  Leere Angaben fallen weg; ohne jede steht unten links, wann gedruckt
  wurde. Die Angaben liegen verschlüsselt bei den Dateien der
  Produktentwicklung und wandern mit ihr ins Backup. Wann gedruckt wurde,
  steht auf Seite 1; dort rechts unter dem Produktfoto ein leeres,
  umrahmtes Feld „Freigabe QS:" für den Stempel der Qualitätssicherung —
  auch in der leeren Vorlage.
- **Projektbericht-Vorlage** (Werkzeuge » Projektbericht » „Vorlage
  speichern…" oder unter „Erstellen"): der Bericht leer zum Ablegen bei den
  Formblättern — mit Kopf und Fuß, jedem Kapitel und jedem Abschnitt, den
  ein Bericht haben kann. Statt der Angaben eines Projekts steht in «»,
  was dort erscheint; was nur unter Umständen erscheint, sagt die graue
  Zeile neben der Überschrift. Ein Test hält sie beim Bericht: Jede
  Überschrift und jede Spalte des Berichts muss auch in der Vorlage stehen.

Firmenvorlagen, Logos und Schlüssel gehören nicht ins Repository: Sie werden
in der App hinterlegt. Die eingebaute Beispielvorlage enthält keine
Firmenangaben. Auch Formblattnummer, Namen und Stand für Kopf und Fuß des
Projektberichts trägt jeder selbst ein.

## Daten und Sicherung

- **Datenbank:** SQLite über [drift](https://drift.simonbinder.eu/), Datei
  `produktion_planer.sqlite` im Dokumente-Ordner, Schema-Version 39.
- **Backups** (`.planerbackup`, gepackt) liegen im Ordner `backups` unter den
  Dokumenten oder in einem selbst gewählten Ordner. Nach Änderungen sichert die
  App automatisch (höchstens einmal je Minute) und beim Beenden, wenn sich seit
  dem letzten Backup etwas geändert hat. Aufbewahrt werden die letzten zehn
  Auto-Backups, dazu für sieben Tage je Tag und für vier Wochen je Woche das
  letzte. Geschrieben wird über eine Zwischendatei — ein abgebrochenes Backup
  hinterlässt keine halbe Datei. Vor jedem Wiederherstellen schreibt die App
  den aktuellen Stand weg. Ältere Backup-Versionen (ab 1.0) lassen sich weiter
  einspielen.
- **Angehängte Dateien** der Produktentwicklung (PDFs, Mails,
  Spezifikationen) stehen nicht in jedem Auto-Backup, sondern einmal im Ordner
  `planer_dateien` neben den Backups, benannt nach der Prüfsumme ihres
  verschlüsselten Inhalts; das Backup nennt nur die Prüfsummen. Was kein
  Backup mehr nennt, räumt die App einmal am Tag weg. Zum Umziehen auf einen
  anderen Rechner das **Komplett-Backup** nehmen (Daten → Komplett-Backup):
  eine Datei mit allem, auch den Dateien. Fehlen einem Auto-Backup beim
  Wiederherstellen Dateien, spielt die App nichts ein.
- **Produktentwicklung im Backup:** verschlüsselt. Ein Backup ohne diesen Teil
  lässt die lokalen Entwicklungsdaten unberührt, ebenso „App zurücksetzen".
  Auf demselben Rechner eingespielt, bleibt das aktuelle Passwort; ein Backup
  von einem anderen Rechner öffnet das Passwort, das dort galt. Der
  DeepL-Schlüssel bleibt auf dem Rechner und geht nie ins Backup.
- **Stammdaten-Mappe** (Excel): wird bei jedem Export frisch aus der
  Datenbank gebaut — Blätter „Anlagen", „Steckbriefe" und je Artikel eines.
  In Excel bearbeitet, lässt sie sich wieder einlesen. Im Block
  „HISTORISCHE DATEN" stehen die erfassten Produktionen, ganz rechts die
  Fleischeinwaage — ältere Mappen ohne diese Spalte lassen sich weiter
  einlesen. Den Maschinen-Katalog gibt es zusätzlich als eigene Mappe.

### Tabellen

| Bereich            | Tabellen                                                                                                     |
| ------------------ | ------------------------------------------------------------------------------------------------------------ |
| Stammdaten         | `products`, `product_steps`, `product_step_parameters`, `machines`, `machine_parameter_defs`, `parameter_grenzen`, `zusatzzeiten`, `raw_materials`, `product_raw_materials`, `raw_material_batches` |
| Planung            | `production_tasks`, `task_dependencies`, `demands`, `tagesaufgaben`, `auftragsbestand_artikel`, `auftragsbestand_positionen` (dazu je `…_vorher` für den Vergleich) |
| Ist und Archiv     | `production_runs`, `production_history`, `week_snapshots`                                                    |
| Sonstiges          | `app_settings`, `order_list_items`                                                                           |
| Produktentwicklung | `entwicklung_zutaten`, `entwicklung_rezepturen`, `entwicklung_rezeptur_versionen`, `entwicklung_rezeptur_positionen`, `entwicklung_gesamtprojekte`, `entwicklung_projekte`, `entwicklung_projekt_eintraege`, `entwicklung_dateien`, `entwicklung_datei_inhalte`, `entwicklung_fliessdiagramme` |

## Entwickeln

```bash
flutter pub get

# drift-Code erzeugen — vor dem ersten Build und nach jeder Änderung
# an den Tabellen unter lib/core/database/tables/
dart run build_runner build --delete-conflicting-outputs

flutter run -d windows      # oder: -d linux, -d macos

flutter analyze             # muss ohne Befund durchlaufen
flutter test
```

`lib/core` enthält Datenbank, Dienste, Konstanten und gemeinsame Bausteine,
`lib/features/<bereich>` je Bereich die Oberfläche. Die Lints sind streng
(u. a. `require_trailing_commas`, `prefer_const_constructors`,
`strict-casts`).

Die CI (`.github/workflows/desktop_build.yml`) läuft bei jedem Push und Pull
Request auf `main`: Codegen, Analyse und Tests mit Flutter 3.41.6, danach
Release-Builds für Linux, Windows und macOS als herunterladbare ZIPs.

## Grundsätze

- **Offline:** Die App funktioniert ohne Netz; Backups sind das
  Sicherungsmodell.
- **UUIDs statt fortlaufender Nummern**, **Soft-Delete** (`deleted_at`) und
  `updated_at`, gesetzt in der Repository-Schicht.
- **Nachvollziehbare Zahlen:** Dauer, Verlust und Leistung sind Mittelwerte
  aus erfassten Produktionen oder hinterlegte Werte — nie geschätzt.
- **Öffentliches Repository:** keine echten Kunden-, Auftrags- oder
  Rezepturdaten und keine Firmenvorlagen. Tests arbeiten ausschließlich mit
  erfundenen Daten.
