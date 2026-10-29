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
| Auswerten   | Produktionserfassung  | Ist-Mengen und -Zeiten je Produktion: Verlust, kg/h; die Kette im Board wird erledigt        |
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
  - **Prozessblatt** (Artikel): Abteilungen und Schritte, jede Abteilung
    auf eigener Seite, Leistungsdaten, Kennwerte, Plattenraster,
    Maschineneinstellungen, Parameter, Notizen, Linien für Notizen von
    Hand.
  - **Datenblatt** (Board, Bedarf, Auftragsbestand, Planungsvorschlag):
    welche Blätter, Mengen und Tag, Stand, Merkmale, Notiz, Ablauf,
    Aufträge — auch ohne Kundennamen zum Aushängen —, Feld für die
    Rückmeldung.
  - **Etikett-Entwurf**: Breite des Etiketts (80, 110 oder 150 mm), Kopf,
    Nährwerttabelle, Platzhalter, was noch offen ist.
  - **Projektbericht**: Kapitel, Steckbrief, Inhaltsverzeichnis, Verlauf als
    Zeitstrahl und im Einzelnen, Kapitel auf neuen Seiten oder fortlaufend.

Der Satz (`lib/core/druck/`) legt jedes Blatt auf eine gedachte, größere
Seite und verkleinert beim Zeichnen — so bricht der Text über die volle
Breite um, und Links und Lesezeichen im PDF stimmen auch verkleinert.

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
  Hand gilt weiter) — von Hand bleibt nur Navision. Liste, Übersicht,
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
  „Mehr".
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
  Unterzutaten.
- **Werkzeuge:** Rezeptur aus einem Etikett zurückrechnen, Fleischanteil
  einer Rezeptur (nach Wahl, ihr neuester Stand) auf ein Ziel einstellen,
  Entwicklung in Zahlen.
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
  Anfrage und Notizen), Rezeptur (Zusammensetzung mit Mengen und Anteilen,
  Zutatenverzeichnis, Allergene, Nährwerte, Fleisch nach LMIV, die Stände im
  Vergleich), Produkt und Spezifikation (Sensorik, Angaben, Verpackung,
  Etikett nach LMIV), Herstellung und HACCP (Prozesskette nach Stationen mit
  Werten, die Platten von Bratstraße und Kombiofen als Raster wie im
  Prozessblatt, festgehaltene Versionen, — wenn der Artikel davon
  abweicht — der Prozess im Artikel, Gefahrenanalyse und Lenkungspunkte),
  Freigabe und Checkliste (Artikel, Verlust der Produktion gegen die
  Rezeptur), der Entwicklungsweg (die Stände im Überblick, jede Station mit
  Grund, Kennzahlen, Änderungen und Rückmeldungen), der Verlauf als
  Zeitstrahl wie in der App (Phasen, Stationen, Bezüge zu den Ständen, in
  Zeilen zu sechs Einträgen) mit jedem Eintrag im Einzelnen und die
  Dateien. Was fehlt, steht als Hinweis da; Kapitel ohne Inhalt beginnen
  keine eigene Seite.
- Übernahme aus der Development-Suite (ZIP oder JSON) — im Menü oben neben
  „Sperren", wo auch „Passwort ändern" steht.

Firmenvorlagen, Logos und Schlüssel gehören nicht ins Repository: Sie werden
in der App hinterlegt. Die eingebaute Beispielvorlage enthält keine
Firmenangaben.

## Daten und Sicherung

- **Datenbank:** SQLite über [drift](https://drift.simonbinder.eu/), Datei
  `produktion_planer.sqlite` im Dokumente-Ordner, Schema-Version 34.
- **Backups** (`.planerbackup`) liegen im Ordner `backups` unter den
  Dokumenten oder in einem selbst gewählten Ordner. Nach Änderungen sichert die
  App automatisch (höchstens einmal je Minute, die letzten 30 bleiben) und beim
  Beenden. Vor jedem Wiederherstellen schreibt sie den aktuellen Stand weg.
  Ältere Backup-Versionen (ab 1.0) lassen sich weiter einspielen.
- **Produktentwicklung im Backup:** verschlüsselt. Ein Backup ohne diesen Teil
  lässt die lokalen Entwicklungsdaten unberührt, ebenso „App zurücksetzen".
  Auf demselben Rechner eingespielt, bleibt das aktuelle Passwort; ein Backup
  von einem anderen Rechner öffnet das Passwort, das dort galt. Der
  DeepL-Schlüssel bleibt auf dem Rechner und geht nie ins Backup.
- **Stammdaten-Mappe** (Excel): wird bei jedem Export frisch aus der
  Datenbank gebaut — Blätter „Anlagen", „Steckbriefe" und je Artikel eines.
  In Excel bearbeitet, lässt sie sich wieder einlesen. Den Maschinen-Katalog
  gibt es zusätzlich als eigene Mappe.

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
