# Supabase Schema für Produktion Planer

Dieses Projekt startet mit einer Offline-First-Architektur und einer lokalen SQLite-Datenbank. Für spätere Cloud-Synchronisation kann das folgende Supabase-Schema vorbereitet werden.

## Tabellen

### departments
- id: int, Primary Key
- name: text
- color: int
- shortCode: text

### products
- id: int, Primary Key
- articleNumber: text
- name: text
- plannedQuantity: int
- machineSettings: text
- averageDurationPerUnit: double
- parameterHistory: json

### raw_materials
- id: int, Primary Key
- productId: int, Foreign Key -> products.id
- name: text
- quantity: text
- ordered: bool

### production_tasks
- id: int, Primary Key
- productId: int, Foreign Key -> products.id
- departmentId: int, Foreign Key -> departments.id
- plannedDate: timestamptz
- plannedQuantity: int
- teamSize: int
- estimatedDurationMinutes: int
- dependencyDepartmentIds: text

## Sync-Plan

- Synchronisation kann zunächst über Supabase-Realtime mit Tabellen `products`, `raw_materials`, `production_tasks` und `departments` aufgebaut werden.
- Das lokale SQLite-Modell sollte später als Cache dienen und Konflikte über Timestamp- und Versionsfelder lösen.
- Für Offline-Einsatz können Änderungen in einer lokalen Warteschlange gesammelt und erst nach Verfügbarkeit an Supabase gesendet werden.
