# Phase 1a: Sauberes Datenfundament

Ersetzt die konkurrierenden Datenschichten (drift + sqflite parallel) durch
eine einzelne, sync-vorbereitete drift-Datenbank. Löscht toten UI-Code und
etabliert die Projektstruktur für die folgenden Phasen.

## Was neu ist

- **Ein** Datenbank-Layer (drift) mit 9 Tabellen:
  `products`, `product_steps`, `raw_materials`, `product_raw_materials`,
  `raw_material_batches` (HACCP), `production_tasks`, `production_runs`
  (Ist-Erfassung für Lernlogik), `task_dependencies`, `order_list_items`
- Alle Tabellen mit UUID-IDs, `created_at`/`updated_at`/`deleted_at` für
  späteren Supabase-Sync
- Indizes für die häufigsten Query-Patterns
- Paralleles Postgres-Schema unter `supabase/schema.sql`
- `Abteilung`-Enum mit Farbe + Kurzcode (statt DB-Tabelle, weil die Menge
  fix ist)
- Riverpod-basierter Database-Provider
- Platzhalter-`HomeScreen`, der die DB-Anbindung verifiziert und die
  Abteilungen-Darstellung visuell prüft
- CI erweitert um `build_runner`-Schritt und Android-Debug-APK-Build

## Was gelöscht wird

Siehe `DELETION_LIST.md` für den vollständigen Katalog mit Begründungen.
Kurzfassung:
- `lib/core/database.dart` — kompilierte nicht (`Constant`/`Value`-Fehler,
  invalides SQL, zeitkonstantes `DateTime.now()`)
- `lib/services/database_service.dart` — zweite, konkurrierende DB-Schicht
  mit schemainkompatiblem Ansatz, Package `sqflite` fehlt sogar in pubspec
- `lib/models/*` — dupliziert, was drift auto-generiert
- `lib/screens/`, `lib/widgets/`, `lib/features/products/` — toter Code,
  wird in Phase 1b/2 frisch und verdrahtet mit der echten DB aufgebaut

## Was aus dem alten Code übernommen wurde

- Farbwerte der Abteilungen → jetzt im `Abteilung`-Enum
- Kurzcodes der Abteilungen → jetzt im `Abteilung`-Enum
- Layout-Idee des Dashboards → als Blueprint für Phase 2 notiert

## Entscheidungen und Begründungen

1. **UUIDs statt Auto-Increment-IDs**
   Pflicht für Multi-Device-Sync. Kollisionen zwischen Geräten sonst
   unvermeidlich.

2. **Soft-Delete statt Hard-Delete**
   Harte Löschungen sind mit asynchronem Sync nicht sauber abbildbar
   (Gerät A löscht, Gerät B kennt die Löschung nicht, pusht den alten
   Datensatz wieder hoch). Alle Queries filtern `deleted_at IS NULL`.

3. **`updated_at` manuell in der Repo-Schicht, nicht per Trigger**
   Trigger würden zwischen SQLite und Postgres divergieren. Disziplin in
   der Repository-Schicht ist portabler und testbarer.

4. **`stock` in `raw_material_batches.menge_aktuell` zusammengeführt**
   Ursprünglich zwei getrennte Tabellen geplant. Da Bestand immer
   chargen-gebunden ist (HACCP), wäre `stock` reine Duplikation. Der
   Gesamtbestand einer Rohware ergibt sich als `SUM(menge_aktuell)`
   über alle nicht-gelöschten Chargen.

5. **`REAL`/`double` für Mengen und Zeiten statt `INTEGER`**
   Der alte Code hatte `INTEGER` — das verhindert korrekte Skalierung
   ("500 kg / 180 kg = 2.78"). Für Zeitkorridore und Mengenberechnungen
   ist `double` zwingend.

6. **Rohwaren produkt-unabhängig (Join-Tabelle `product_raw_materials`)**
   Der alte Code koppelte Rohwaren direkt an Produkte, d.h. "Schweinebauch"
   existierte pro Produkt mehrfach. Die neue Struktur erlaubt Aggregation
   für die wöchentliche Bestellliste.

7. **`Abteilung` als Dart-Enum statt DB-Tabelle**
   Die Menge ist fix (6 Abteilungen), und der Code muss sich sowieso
   konkret auf sie beziehen (Sortier-Reihenfolge, Farben). Enum ist
   typsicher und erspart JOINs.

## Manueller Test nach dem Merge

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze   # muss sauber durchlaufen
flutter test      # muss grün sein
flutter run       # HomeScreen muss "Datenbank verbunden — 0 Produkte" zeigen
```

## Nicht in diesem PR

- Stammdaten-Verwaltungs-UI (Phase 1b)
- Ist-Erfassung und Mittelwert-Berechnung (Phase 1c)
- Whiteboard, MRP, Sync (Phase 2+)
