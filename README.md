# Produktion Planer

Offline-first **Produktionsplaner für den Fleischbereich**. Läuft als Desktop-App
(Windows/Linux/macOS) und als Android-APK (Tablet) aus einer einzigen
Flutter-Codebase.

Das Ziel: Die Abteilungen sollen jeden Arbeitstag möglichst gut ausgelastet
sein (Richtwert 8 h pro Abteilung). Aus den hinterlegten Produktions-Schritten
und ihren Zeiten erzeugt die App einen übersichtlichen, per Drag & Drop
bedienbaren Wochen- und Tagesplan.

## Das Konzept in einer Schleife

```
Excel-Vorlage (v3)  ──Import──▶  Stammdaten (Produkte, Schritte, Anlagen, Parameter)
                                        │
                                  Schritte werden zu Tasks
                                        ▼
                          Planungsboard (Abteilungen × Tage, je 8 h, Drag & Drop)
                                        │
                                   Ausführung
                                        ▼
                          Ist-Erfassung ──▶ Mittelwerte neu ──┐
                                        │                      │
                                   Lernschleife ◀──────────────┘
                                        ▼
                          Ausgabe: Excel-Export · Backup · Drucken
```

Die Zeit-Schätzungen sind **Statistik, keine KI**: `basis_*`-Werte sind
gleitende Mittelwerte aus echten `production_runs`. Mit jedem erfassten
Auftrag wird die Planung genauer.

## Bedien-Bereiche (Screens)

| Bereich            | Zweck                                                            |
| ------------------ | ---------------------------------------------------------------- |
| Heute              | Tagesübersicht, Auslastung aller Abteilungen auf einen Blick     |
| Planungsboard      | Herzstück — Wochenboard (Abteilungen × Tage) und Tagesübersicht  |
| Artikel            | Produkte und Prozessschritte verwalten                           |
| Daten              | Excel-Import/-Export, Backup/Restore, Speicherort                |
| Einstellungen      | Kapazität pro Abteilung, Personalplanung                         |

Das Wochenboard zeigt pro Abteilung und Tag einen Kapazitätsbalken bis 8 h
(grau = Platz frei, grün = gut gefüllt, rot = überbucht). Die Tagesübersicht
stellt jede Aufgabe als Zeitbalken dar — je länger die Dauer, desto höher die
Karte, der leere Platz unten zeigt die freie Zeit. Beide Ansichten lassen sich
als A4-PDF drucken (Artikel, Menge, Dauer je Abteilung).

## Excel-Vorlage (v3) — das Datenfundament

Die Stammdaten werden in der **v3-Vorlage** gesammelt und importiert. Aufbau:

- `Übersicht` — Artikelnummer + Bezeichnung aller Produkte
- `Anlagen-Katalog` — Referenz für die Anlagen-Dropdowns (Name, Abteilung, Hilfetext)
- 12 Produktgruppen-Blaupausen (Brühwurst, Rohwurst, …) als Vorlagen
- Ein Sheet pro Artikel (benannt nach Artikelnummer). Spalte A = Zeilen-Labels,
  Spalten B..K = bis zu **10 Prozessschritte**. Pro Schritt: Abteilung,
  Prozessschritt, Anlage, Personen, Menge, Zeit, danach anlagenspezifische
  Parameter-Blöcke sowie ein Block `ZUSÄTZLICHE PARAMETER` und `HISTORISCHE DATEN`.

Beim Import wird die Original-Datei **byte-genau in `app_settings` gespeichert**.
Der Export schreibt die aktuellen DB-Werte zurück in genau diese Datei, sodass
Formatierung, Farben, Dropdowns und der Anlagen-Katalog vollständig erhalten
bleiben (ZIP/XML-Manipulation, kein Neu-Erzeugen). **Diese Vorlage ist die
verbindliche Basis und darf nicht durch ein neu generiertes Format ersetzt werden.**

## Datenmodell

Lokale SQLite-Datenbank via [drift](https://drift.simonbinder.eu/), aktuell
**Schema v5**. Kern-Tabellen:

- `products` — Produkt-Stammdaten inkl. gruppenspezifischer Felder
- `product_steps` — Prozessschritte (Abteilung, Reihenfolge 1..10, Anlage,
  Zeit/Personen, lernende `basis_*`-Werte)
- `product_step_parameters` — flexible Parameter pro Schritt (Standard + Custom)
- `machines` — Anlagen-Katalog
- `raw_materials`, `product_raw_materials`, `raw_material_batches` — Rohwaren + HACCP-Chargen
- `production_tasks` — geplante Aufträge auf dem Board
- `production_runs` — Ist-Erfassung (Futter für die Lernlogik)
- `task_dependencies` — Abhängigkeiten zwischen Tasks
- `app_settings` — u. a. die zuletzt importierte Excel-Datei
- `order_list_items` — Wochen-Bestellliste (MRP, spätere Phase)

Die 7 Abteilungen sind ein Dart-Enum (`lib/core/constants/abteilungen.dart`):
Zerlegung, Wurstküche, Kutterabteilung, Bratstraße, Schneideabteilung,
Verpackung, Verpackung Tef1.

## Roadmap

| Stufe | Inhalt                                                              | Status     |
| ----- | ------------------------------------------------------------------- | ---------- |
| 0     | Repo aufräumen (Altlasten, Dubletten), README ehrlich               | in Arbeit  |
| 1     | Stammdaten fertig — Schritte verwalten (hinzufügen/löschen/sortieren) | offen      |
| 2     | Boards bauen — Wochenboard + Tagesübersicht + Drucken               | offen      |
| 3     | Lernschleife schließen — Ist-Erfassung verdrahten                   | offen      |

## Architektur-Prinzipien

- **Offline-first**: ohne Internet voll funktionsfähig; Backup ist das zentrale Sicherungsmodell.
- **UUIDs statt Auto-Increment**: vermeidet Kollisionen bei späterem Sync/Import.
- **Soft-Delete überall**: `deleted_at IS NULL`-Filter in jeder Query.
- **`updated_at` diszipliniert** in der Repository-Schicht manuell setzen (kein DB-Trigger, bleibt portabel/testbar).
- **Format-bewahrender Excel-Export**: in die importierte Originaldatei zurückschreiben, nicht neu erzeugen.
- **Lernlogik = Statistik**: Mittelwerte/Standardabweichung aus `production_runs`, nachvollziehbar.
- **drift + Riverpod**: lokale DB + State-Management.

## Entwicklungs-Setup

```bash
flutter pub get

# Code-Generierung (drift, riverpod) — PFLICHT vor dem ersten Build
dart run build_runner build --delete-conflicting-outputs

# Starten
flutter run -d linux        # Desktop Linux
flutter run -d windows      # Desktop Windows
flutter run -d <device-id>  # Android Tablet

# Qualität
flutter analyze             # muss sauber durchlaufen (strikte Lints)
flutter test
```

Nach Änderungen an den Tabellen-Dateien unter `lib/core/database/tables/`
**immer** erneut `dart run build_runner build --delete-conflicting-outputs`
ausführen, sonst ist `database.g.dart` veraltet.

Die CI (`.github/workflows/`) führt Analyse, Codegen, Tests sowie Android- und
Desktop-Builds aus. Lints sind streng (u. a. `require_trailing_commas`,
`prefer_const_constructors`).
