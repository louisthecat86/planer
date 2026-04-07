# DELETION LIST

Dieses Dokument listet alle Dateien aus dem aktuellen `main`-Branch
(Copilot-Stand), die beim Mergen dieses Phase-1a-PRs **gelöscht** werden
müssen. Der Grund ist in der jeweiligen Zeile dokumentiert.

Nach dem Auschecken des neuen Branches einfach ausführen:

```bash
# Alte Struktur entfernen
rm lib/core/app.dart
rm lib/core/database.dart
rm lib/services/database_service.dart
rm -rf lib/features/products
rm -rf lib/models
rm -rf lib/screens
rm -rf lib/widgets
rm docs/supabase_schema.md
rmdir docs 2>/dev/null || true

git add -A
git commit -m "Phase 1a: Entferne alte Daten- und UI-Schicht"
```

## Zu löschende Dateien im Detail

| Datei | Grund |
|---|---|
| `lib/core/app.dart` | Ersetzt durch neue `lib/app.dart` (Theme, Router, ohne den toten `ProductListScreen`-Import). |
| `lib/core/database.dart` | Kompiliert nicht (`Constant(0xFFB71C1C)` statt `Value(...)`, `Constant(DateTime.now())` friert Zeit zur Buildzeit ein, invalides SQL in `customConstraint('NULL REFERENCES …')`). Außerdem `int autoIncrement`-IDs statt UUIDs — sync-unfähig. Ersetzt durch `lib/core/database/database.dart` und Tabellen unter `lib/core/database/tables/`. |
| `lib/services/database_service.dart` | **Zweite, konkurrierende Datenbank-Schicht** auf Basis von `sqflite`. Package ist nicht in `pubspec.yaml` — würde nicht mal kompilieren. Schema widerspricht zudem Anforderungen (keine Chargen, keine UUIDs, keine Sync-Felder, Rohwaren direkt an Produkt gekoppelt statt über Join-Tabelle). |
| `lib/models/department.dart` | Dupliziert, was drift aus `Departments`-Tabelle auto-generiert. In der neuen Struktur sind Abteilungen ein Enum in `lib/core/constants/abteilungen.dart`, keine DB-Tabelle. |
| `lib/models/product.dart` | Dupliziert drift-generierte `Product`-Klasse. Zudem inkompatibles Schema (`int` IDs, kein `updated_at`). |
| `lib/models/production_task.dart` | Wie oben — drift generiert das automatisch, außerdem schemainkompatibel. |
| `lib/models/raw_material.dart` | Wie oben. Zusätzlich falsches Modell: Rohware hängt an einzelnem Produkt, nicht am Katalog. |
| `lib/screens/dashboard_screen.dart` | Wird von `main.dart` nicht geroutet, also toter Code. Die UI-Idee (zweispaltiges Layout) wird in Phase 1b / Phase 2 frisch umgesetzt, dann mit der echten Datenschicht verdrahtet. |
| `lib/widgets/department_card.dart` | Toter Code (nur vom nicht-gerouteten DashboardScreen verwendet). UI-Idee (Farbe + Kurzcode pro Abteilung) ist in `Abteilung`-Enum übernommen. Die Card wird in Phase 2 neu gebaut. |
| `lib/widgets/raw_material_card.dart` | Toter Code. Die Abhak-Logik wandert in Phase 4 in ein sauberes `OrderListItemCard`, das auf `order_list_items` statt direkt auf `raw_materials` arbeitet. |
| `lib/features/products/product_list_screen.dart` | Statischer Platzhaltertext. Ersetzt durch `lib/features/shell/home_screen.dart`, das tatsächlich die DB anspricht und die Abteilungen rendert. |
| `docs/supabase_schema.md` | Ersetzt durch ausführbares `supabase/schema.sql`, das 1:1 zum drift-Schema passt. Doku-Only-Dateien veralten sofort. |

## Was erhalten bleibt

- `pubspec.yaml` — ist identisch mit dem, was Copilot übernommen hatte
- `analysis_options.yaml` — wird mit strikteren Lints überschrieben
- `.github/workflows/flutter.yml` — wird um Codegen-Schritt und APK-Build erweitert
- `README.md` — wird überschrieben mit aktuellem Phasen-Stand

## Nicht übernommene, aber dokumentierte Ideen aus dem Copilot-Code

Drei Sachen aus dem alten Code sind gut und wurden in die neue Architektur
übernommen:

1. **Farbwerte für Abteilungen** (`0xFFB71C1C` etc.) — sind jetzt in
   `lib/core/constants/abteilungen.dart` hinterlegt, als `farbwert`-Field
   im `Abteilung`-Enum.
2. **Kurzcodes** (`Z`, `WK`, `B`, …) — dito, als `kurzcode`-Field.
3. **Zweispaltiges Dashboard-Layout** (links Abteilungen, rechts Rohwaren) —
   wird als UI-Blueprint für Phase 2 (Whiteboard) notiert.
