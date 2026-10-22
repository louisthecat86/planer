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

## Produktentwicklung

Ein eigener Bereich für die Entwicklung neuer Produkte. Er ist mit einem
eigenen Passwort gesperrt; seine Daten liegen in eigenen Tabellen
(`entwicklung_*`), Anhänge und Vorlagen verschlüsselt (ChaCha20-Poly1305).

- **Projekte** in fünf Reitern: **Verlauf** (mit Kommentaren),
  **Übersicht** (Stammdaten mit Artikelnummer und Fließdiagramm, Ziele für
  Fett, Eiweiß und aw, Notizen, Freigabe, Bild, Rezepturen, Checkliste),
  **Produkt** (Sensorik mit Maßen, Stückgewicht und Toleranz, Angaben und
  Verpackung für die Spezifikation, daneben was mit einem Stand in der
  Spezifikation stünde), **Herstellung** (Prozess mit Versionen und die
  HACCP-Gefahrenanalyse — breit nebeneinander, schmal zum Umschalten) und
  **Dateien**. Jede Angabe gibt es nur einmal.
  Über jedem Reiter steht der **Projektkopf**: die Phase (Entwicklung ›
  Validierung › Produktion — antippen wechselt nach einer Rückfrage, der
  Wechsel steht als Meilenstein im Verlauf), der Fortschritt der
  Checkliste, „Als Nächstes" mit dem Weg dorthin und die offenen Einträge
  im Verlauf. Spezifikation, Etikett und Projektbericht stehen oben unter
  „Erstellen", Umbenennen, Archivieren (und Wiederaufnehmen) und Löschen
  im Menü daneben. Die Projekt-Checkliste rechnet sich selbst: Rezeptur
  (ein abgeschlossener Stand), Nährwerte (alle Zutaten des Stands mit
  Werten), Spezifikation, Prozess, Sensorik (Aussehen, Geruch, Geschmack,
  Konsistenz) und Artikel (Freigabe) sieht die App dem Projekt an; „Etikett
  erstellt" klappt die zwölf Pflichtangaben nach LMIV auf und ist erledigt,
  sobald jede abgehakt ist oder „trifft nicht zu" (ein früherer Haken von
  Hand gilt weiter) — von Hand bleibt nur Navision. Liste, Übersicht,
  Zahlen und Bericht zählen gleich. Einträge im Verlauf sind offen oder erledigt
  (antippen schaltet um).
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
  Einträge lassen sich einem Stand zuordnen („Zu Stand"). Der Zeitstrahl
  zeigt die Stände als Stationen, zugeordnete Einträge mit einer Linie zu
  ihrer Station, die Phasen als Band und filtert nach Art; die Ansicht
  „Entwicklungsweg" führt von der Idee über jede Station (Grund,
  Änderungen, Kennzahlen, Rückmeldungen) bis zur Freigabe.
- **Mails im Projekt:** Eine Mail direkt aus Outlook (oder eine .msg/.eml
  aus dem Explorer) auf ein Projekt ziehen — sie steht als E-Mail im
  Verlauf (Betreff, Absender, Datum, Text, die Mail selbst zum Öffnen),
  ihre Anhänge bei den Dateien; andere Dateien kommen als Datei in den
  Verlauf. Auf die Projektliste gezogen, wird aus der Mail ein neues
  Projekt (Name, Kunde und Anfrage vorbelegt). Ohne Ziehen: „Aus Mail…" in
  der Projektliste, „Datei ablegen" im Verlauf. Die App liest .msg und
  .eml selbst; das Ziehen nimmt unter Windows das Fenster entgegen
  (`windows/runner/ablage_ziel.cpp`).
- **Etikett je Stand:** Vorschau mit Zutatenliste, Spuren, Nährwerttabelle
  und Hinweisen aus der Spezifikation, als Text kopieren oder als
  PDF-Entwurf.
- **Zutaten-Katalog** mit Nährwerten, Allergenen, Tierart, Bindegewebe und
  Unterzutaten.
- **Werkzeuge:** Rezeptur aus einem Etikett zurückrechnen, Fleischanteil auf
  ein Ziel einstellen, Entwicklung in Zahlen.
- **Freigabe als Artikel:** Ein abgeschlossener Stand wird zum Artikel der
  Planung; sein Verlust gilt dort als Vorgabe, bis Produktionen erfasst sind.
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
  Stammdaten; Kürzel und Datum fragt das Fenster. Im Reiter „Produkt"
  zeigt eine Vorschau, was mit dem gewählten Stand hineinkommt, und was
  noch fehlt — mit dem Ort, an dem man es einträgt. Dazu ein
  **Projektbericht** als PDF mit Checklisten und dem Entwicklungsweg
  (Stationen mit Grund, Änderungen, Kennzahlen und Rückmeldungen, Phasen,
  Freigabe).
- Übernahme aus der Development-Suite (ZIP oder JSON).

Firmenvorlagen, Logos und Schlüssel gehören nicht ins Repository: Sie werden
in der App hinterlegt. Die eingebaute Beispielvorlage enthält keine
Firmenangaben.

## Daten und Sicherung

- **Datenbank:** SQLite über [drift](https://drift.simonbinder.eu/), Datei
  `produktion_planer.sqlite` im Dokumente-Ordner, Schema-Version 33.
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
| Produktentwicklung | `entwicklung_zutaten`, `entwicklung_rezepturen`, `entwicklung_rezeptur_versionen`, `entwicklung_rezeptur_positionen`, `entwicklung_projekte`, `entwicklung_projekt_eintraege`, `entwicklung_dateien`, `entwicklung_datei_inhalte`, `entwicklung_fliessdiagramme` |

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
