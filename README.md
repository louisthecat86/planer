# Produktion Planer

Ein Offline-First-Planungstool für die Produktionsleitung im Fleischbereich. Das Ziel ist ein übersichtliches Dashboard für Wochenplanung, Abteilungsabhängigkeiten und Rohwarenbestellungen.

## Phase 1a

- Flutter-App mit lokalem SQLite-Speicher
- Dashboard für Abteilungen, Wochenplanung und Rohwarenübersicht
- Datenmodell für Artikel, Aufgaben, Abteilungen und Rohstoffe
- Supabase-Sync als spätere Erweiterung vorbereitet

## Projektstruktur

- `lib/main.dart` — Einstiegspunkt der App
- `lib/core/app.dart` — App-Konfiguration und Navigation
- `lib/core/database.dart` — Drift-Datenbankmodell und Initialdaten
- `lib/features/products/` — Produktverwaltung und Stammdaten
- `docs/supabase_schema.md` — Supabase-Schema-Plan
- `.github/workflows/flutter.yml` — CI-Workflow

## Erste Schritte

1. Flutter installieren
2. `flutter pub get`
3. `flutter pub run build_runner build --delete-conflicting-outputs`
4. `flutter run`

## Nächste Schritte

- Erweiterung um Aufgabenverwaltung und Bearbeitungsdialoge
- Anpassbares Planungskalender-Layout
- Supabase-Synchronisation und Multi-Device-Login
