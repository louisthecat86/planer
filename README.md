# Produktion Planer

Offline-first Planungs-Tool für die Produktionsleitung im Fleischbereich.
Läuft als Android-APK (Tablet) und als Desktop-App (Windows/Linux/macOS)
aus einer einzigen Flutter-Codebase.

## Status

**Phase 1a — Datenfundament abgeschlossen.**

- Lokale SQLite-Datenbank via [drift](https://drift.simonbinder.eu/)
- Komplettes Datenmodell für Produkte, Rezepturen, Rohwaren, Chargen (HACCP),
  Produktions-Aufträge, Ist-Erfassung und Bestellliste
- Alle Tabellen sync-vorbereitet (UUID-IDs, `updated_at`, Soft-Delete)
- Paralleles Supabase-Schema unter `supabase/schema.sql` für Phase 6
- GitHub-Actions-CI mit Analyse, Codegen und Android-APK-Build

Phase 1a hat **noch keine** Stammdaten-UI — das folgt in Phase 1b.

## Phasenplan

| Phase | Inhalt | Status |
|---|---|---|
| 1a | Datenmodell, DB-Schema, CI | ✅ |
| 1b | Stammdaten-UI (Produkte, Rezepturen, Rohwaren, Chargen) | offen |
| 1c | Ist-Erfassung + Mittelwert-Lernlogik | offen |
| 2  | Whiteboard-Dashboard (Wochenplanung) | offen |
| 3  | Abhängigkeits-Visualisierung zwischen Abteilungen | offen |
| 4  | Rohwaren-Bedarfsrechnung (MRP) + Bestellliste | offen |
| 5  | Quality of life, Export, Drucken | offen |
| 6  | Supabase-Sync für Multi-Device-Betrieb | offen |

## Projektstruktur

```
lib/
├── main.dart                      App-Einstiegspunkt
├── app.dart                       MaterialApp, Router, Theme
│
├── core/
│   ├── constants/
│   │   └── abteilungen.dart       Abteilungen-Enum (Name, Kurzcode, Farbe)
│   ├── theme/
│   │   └── app_theme.dart         Material 3 Theme
│   ├── database/
│   │   ├── database.dart          AppDatabase (drift)
│   │   └── tables/                Eine Datei pro Tabelle
│   └── providers/
│       └── database_provider.dart Riverpod-Provider für die DB
│
├── features/                      Pro Fachbereich: data/ domain/ presentation/
│   └── shell/
│       └── home_screen.dart       Platzhalter für Phase 1a
│
└── shared/                        Wiederverwendbare Widgets und Utils

supabase/
└── schema.sql                     Postgres-Schema parallel zum drift-Schema

.github/workflows/
└── flutter.yml                    CI: Analyse + APK-Build
```

## Entwicklungs-Setup

```bash
# Dependencies ziehen
flutter pub get

# drift & riverpod Code-Generierung (PFLICHT vor erstem Build)
dart run build_runner build --delete-conflicting-outputs

# Starten
flutter run                         # Default-Plattform
flutter run -d linux                # Linux Desktop
flutter run -d windows              # Windows Desktop
flutter run -d <device-id>          # Android Tablet (vorher via adb verbunden)

# Tests & Analyse
flutter analyze
flutter test
```

Nach Änderungen an den Tabellen-Dateien unter `lib/core/database/tables/`
**immer** erneut `dart run build_runner build --delete-conflicting-outputs`
laufen lassen, sonst ist `database.g.dart` veraltet.

## Architektur-Prinzipien

- **Offline-first**: Die App ist ohne Internet voll funktionsfähig. Sync ist
  ein additives Feature für Phase 6, kein Fundament.
- **UUIDs statt Auto-Increment**: Vermeidet ID-Kollisionen beim späteren
  Sync zwischen Geräten.
- **Soft-Delete überall**: `deleted_at IS NULL`-Filter in jeder Query.
  Harte Löschungen sind mit Multi-Device-Sync nicht sauber abbildbar.
- **updated_at diszipliniert pflegen**: In jedem Repository-Write manuell
  neu setzen. Ist die Grundlage für last-write-wins beim Sync.
- **Clean Architecture pro Feature**: `data/` (Drift-Queries), `domain/`
  (reine Dart-Logik, testbar), `presentation/` (Flutter-Widgets).
- **Lernlogik ist Statistik, keine KI**: Mittelwerte und Standardabweichung
  aus historischen `ProductionRuns`. Ehrlich, nachvollziehbar, debuggbar.
