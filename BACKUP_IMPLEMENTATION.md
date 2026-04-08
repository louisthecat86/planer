# Backup-Verwaltung des Produktions-Planers

## Übersicht

Das Programm verfügt jetzt über eine vollständige, **standalone Backup-Funktionalität** — ähnlich wie in deinem Development-Suite-Projekt.

## Features

✅ **Export (Backup erstellen)**
- Komplette Datenbank als Standalone-Backup-Paket speichern
- Zeitstempel im Dateinamen: `planer_backup_YYYY-MM-DD_HHMMSS.planerbackup`
- Alle 9 Tabellen werden mitgesichert

✅ **Import (Backup laden)**
- `.planerbackup`-Paket zurück in die Datenbank importieren
- Optional: Bestehende Daten vorher löschen
- Transaktional (alles-oder-nichts)

✅ **Auto-Backup**
- Automatische Backups mit Präfix `auto_backup_`
- Kann periodisch aufgerufen werden

✅ **Backup-Verwaltung UI**
- Liste aller Backups mit Zeitstempel und Größe
- Buttons: Erstellen, Laden, Löschen
- Bestätigungsdialoge für kritische Aktionen

## Speicherorte

Die Backups werden **plattformunabhängig** gespeichert:

| Platform | Pfad |
|----------|------|
| **Android** | `/data/data/<app>/files/backups/` |
| **iOS** | `<App Documents>/backups/` |
| **Windows/Linux/macOS** | `~/.produktion_planer/backups/` |

Du kannst die Backups also **separat vom Programm sichern**! Sie liegen in einem normalen Dateisystem-Ordner.

## Verwendung

### 1. Backup erstellen
```dart
// Im Code:
final path = await BackupService.exportBackup(database);
// → Neue Datei erstellt: planer_backup_2024-04-08_143000.planerbackup
```

**Via UI:**
- MainScreen → Backup-Button (oben rechts)
- "Backup erstellen" drücken

### 2. Backup laden
```dart
// Im Code:
await BackupService.importBackup(filepath, database, clearExisting: true);
// → Datenbank wird mit Backup-Daten gefüllt
```

**Via UI:**
- MainScreen → Backup-Button
- Auf Backup klicken → Menu → "Laden"
- Oder "Backup laden" Button zum Datei-Wähler

### 3. Backup löschen
```dart
await BackupService.deleteBackup(filepath);
// → Datei gelöscht
```

**Via UI:**
- MainScreen → Backup-Button
- Auf Backup klicken → Menu → "Löschen"

## Technische Details

### Datenstruktur (JSON-Format)
```json
{
  "version": "1.0",
  "timestamp": "2024-04-08T14:30:00Z",
  "data": {
    "products": [...],
    "product_steps": [...],
    "raw_materials": [...],
    "product_raw_materials": [...],
    "raw_material_batches": [...],
    "production_tasks": [...],
    "production_runs": [...],
    "task_dependencies": [...],
    "order_list_items": [...]
  }
}
```

### Implementierung

**BackupService** (`lib/core/services/backup_service.dart`)
- Statische Methoden für Export/Import
- Datei-Management über `path_provider`
- JSON-Serialisierung
- Error-Handling

**Riverpod Provider** (`lib/core/providers/backup_provider.dart`)
- FutureProvider für Backup-Liste
- StateNotifier für async Operationen
- UI-State-Management (Laden, Fehler, Erfolg)

**UI Screen** (`lib/features/backup/backup_management_screen.dart`)
- List View mit Backup-Dateien
- Material Design
- Bestätigungsdialoge
- SnackBars für Feedback

### Navigation

Die Backup-Verwaltung ist verfügbar unter:
- **Route:** `/backup`
- **Button:** Haus-Screen → Backup-Icon (oben rechts)

## Installation & Setup

### 1. Dependencies installieren
```bash
cd /workspaces/planer
flutter pub get
```

Neue Dependency:
- `file_picker: ^8.1.0` — für `.planerbackup`-Datei-Auswahl beim Import

### 2. Code generieren
```bash
dart run build_runner build --delete-conflicting-outputs
```

(Falls nötig — die meisten Dateien sind bereits fertig)

### 3. Testen
```bash
flutter run
```

Dann:
- App starten
- "Backup-Button" oben rechts klicken
- "Backup erstellen" drücken
- Erfolgs-Nachricht mit Dateipfad sollte erscheinen

### Desktop Build via GitHub Actions
Die App kann als Desktop-Standalone mit GitHub Actions gebaut werden.
Eine neue Workflow-Datei wurde hinzugefügt: `.github/workflows/desktop_build.yml`

- Linux: `build/linux/x64/release/bundle`
- Windows: `build/windows/runner/Release`
- macOS: `build/macos/Build/Products/Release`

Diese Artefakte enthalten die fertigen Desktop-Bundles, die nach dem Download direkt gestartet werden können.

## Backup-Sicherung

Weil die Backups in einem normalen Ordner liegen, kannst du sie wie folgt extern sichern:

### Android
```bash
adb pull /data/data/com.example.produktion_planer/files/backups ~/meine_backups/
```

### Desktop (Linux/Windows/macOS)
```bash
# Manuell kopieren oder:
cp ~/.produktion_planer/backups/* ~/external_backup_drive/
```

### Automatische externe Sicherung (Future Idea)
- Cloud-Sync (Google Drive, Dropbox, etc.)
- FTP-Upload
- Email-Versand

## Error-Handling

**Häufige Fehler:**

| Fehler | Cause | Lösung |
|--------|-------|--------|
| "Backup-Datei nicht gefunden" | Falscher Pfad | Datei prüfen |
| "Inkompatible Backup-Version" | Zu alte Version | DB-Schema prüfen |
| "Foreign-Key-Fehler beim Import" | Reihenfolge falsch | BackupService-Import überprüfen |
| "Berechtigungsfehler" | Systemrechte | File-System-Rechte prüfen |

## Zukünftige Verbesserungen

💡 Ideen zum Erweitern:

1. **Verschlüsselung**
   - AES-256 für sensitive Daten
   - Passwort-Protection

2. **Cloud-Sync (Future Optional)**
   - Optionales Konzept; aktueller Fokus liegt auf lokalem Backup-Paketmodell
   - Automatische Remote-Backups als späterer Ausbau

3. **Inkrementelle Backups**
   - Nur Änderungen seit letztem Backup
   - Weniger Speicher

4. **Zeitgesteuerte Auto-Backups**
   - Täglich/wöchentlich automatisch
   - Mit Aufbewahrungsrichtlinien

5. **Backup-Merge**
   - Mehrere Backups kombinieren
   - Conflictresolution

## Dateien

**Neue/geänderte Dateien:**

```
lib/
├── core/
│   ├── services/
│   │   └── backup_service.dart          (NEU - Main-Service)
│   └── providers/
│       └── backup_provider.dart         (NEU - Riverpod)
├── features/
│   └── backup/
│       └── backup_management_screen.dart (NEU - UI)
├── app.dart                             (GEÄNDERT - Route hinzugefügt)
└── features/shell/home_screen.dart      (GEÄNDERT - Backup-Button)

pubspec.yaml                             (GEÄNDERT - file_picker dependency)
```

## Support

Bei Fragen oder Problemen:
- Logs anschauen: `flutter logs`
- File-System-Berechtigungen prüfen
- Path-Provider-Dokumentation: https://pub.dev/packages/path_provider
