import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/database.dart';

/// Backup-Service für Export/Import der Datenbankdaten als JSON.
///
/// Speichert Backups in:
/// - Android/iOS: `<App Documents>/backups/`
/// - Desktop: `~/.produktion_planer/backups/`
class BackupService {
  static const String _backupDirName = 'backups';
  static const String _backupFilePrefix = 'planer_backup';
  static const String _autoBackupFilePrefix = 'planer_auto_backup';

  /// Präfix der Sicherung, die unmittelbar VOR einem Restore geschrieben
  /// wird. Bewusst ein eigener Name: Diese Datei zählt nicht als
  /// Auto-Backup und wird deshalb von [cleanupOldAutoBackups] nie
  /// wegrotiert — sie ist die letzte Rückfahrkarte, wenn jemand das
  /// falsche Backup erwischt hat.
  static const String _preRestoreFilePrefix = 'planer_vor_restore';
  static const String _backupFileExtension = 'planerbackup';
  /// Aktuelle Backup-Version.
  ///
  /// 1.0 → ohne Maschinen-Steckbriefe und Parameter-Grenzen
  /// 1.1 → vollständig (inkl. `machine_parameter_defs`, `parameter_grenzen`)
  /// 1.4 → inkl. `demands`, `production_history`, `week_snapshots`
  static const String _currentVersion = '1.4';

  /// Alle Versionen, die beim Import gelesen werden können. Ältere
  /// Backups bleiben gültig — die dort fehlenden Tabellen werden beim
  /// Import einfach übersprungen (leere Liste).
  static const Set<String> _supportedVersions = {
    '1.0',
    '1.1',
    '1.2',
    '1.3',
    '1.4',
  };

  /// Schlüssel des selbst gewählten Backup-Ordners.
  ///
  /// Bewusst in den SharedPreferences und nicht in `app_settings`: Der Pfad
  /// muss auch dann lesbar sein, wenn die Datenbank gerade zurückgesetzt
  /// oder aus einem Backup ersetzt wird — und er ist gerätespezifisch, ein
  /// Backup soll ihn also NICHT mit auf einen anderen Rechner tragen.
  static const String _prefsKeyBackupDir = 'backup_verzeichnis';

  /// Der selbst gewählte Backup-Ordner, oder null = Standard.
  static Future<String?> getEigenerBackupOrdner() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final p = prefs.getString(_prefsKeyBackupDir);
      return (p != null && p.trim().isNotEmpty) ? p.trim() : null;
    } catch (_) {
      return null;
    }
  }

  /// Legt den Backup-Ordner fest. null oder leer stellt den Standard
  /// wieder her.
  static Future<void> setzeEigenenBackupOrdner(String? pfad) async {
    final prefs = await SharedPreferences.getInstance();
    if (pfad == null || pfad.trim().isEmpty) {
      await prefs.remove(_prefsKeyBackupDir);
    } else {
      await prefs.setString(_prefsKeyBackupDir, pfad.trim());
    }
  }

  /// Der Standard-Ordner (unabhängig von einer eigenen Wahl).
  static Future<String> getStandardBackupOrdner() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    return '${appDocDir.path}/$_backupDirName';
  }

  /// Erstellt alle notwendigen Verzeichnisse.
  ///
  /// Ist ein eigener Ordner hinterlegt und erreichbar, wird dieser genutzt —
  /// sonst fällt der Service still auf den Standard zurück. Damit gehen
  /// Backups nie verloren, nur weil ein Netzlaufwerk gerade nicht da ist.
  static Future<Directory> _getBackupDir() async {
    final eigener = await getEigenerBackupOrdner();
    if (eigener != null) {
      try {
        final dir = Directory(eigener);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        return dir;
      } catch (_) {
        // Nicht erreichbar (Netzlaufwerk getrennt, keine Rechte) →
        // Standard nutzen.
      }
    }

    final appDocDir = await getApplicationDocumentsDirectory();
    final backupDir = Directory('${appDocDir.path}/$_backupDirName');

    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }

    return backupDir;
  }

  /// Pfad des Backup-Verzeichnisses (für UI: „Speicherort anzeigen").
  static Future<String> getBackupDirectoryPath() async {
    final dir = await _getBackupDir();
    return dir.path;
  }

  /// Pfad des App-Documents-Verzeichnisses (übergeordnet, hier liegt
  /// auch die SQLite-Datei).
  static Future<String> getDatabaseDirectoryPath() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    return appDocDir.path;
  }

  /// Liefert das jüngste Auto-Backup zurück, oder null falls keines
  /// vorhanden. Wird vom Restore-Banner beim App-Start verwendet.
  static Future<BackupInfo?> getLatestAutoBackup() async {
    try {
      final backups = await listBackups();
      final autos = backups.where((b) => b.isAuto).toList();
      if (autos.isEmpty) return null;
      return autos.first; // sortiert nach Datum, neuestes zuerst
    } catch (_) {
      return null;
    }
  }

  /// Liefert das jüngste Backup beliebigen Typs (manuell oder auto).
  static Future<BackupInfo?> getLatestBackup() async {
    try {
      final backups = await listBackups();
      return backups.isEmpty ? null : backups.first;
    } catch (_) {
      return null;
    }
  }

  /// Exportiert die gesamte Datenbank als JSON-Backup.
  ///
  /// Zeigt einen "Speichern unter"-Dialog, damit der Nutzer den Speicherort
  /// selbst wählen kann. Returns: Pfad zur erstellten Backup-Datei oder null,
  /// wenn der Dialog abgebrochen wurde.
  static Future<String?> exportBackup(AppDatabase database) async {
    try {
      final now = DateTime.now();
      final timeStamp = DateFormat('yyyy-MM-dd_HHmmss').format(now);
      final defaultFilename =
          '${_backupFilePrefix}_$timeStamp.$_backupFileExtension';

      // "Speichern unter"-Dialog anzeigen.
      final outputPath = await FilePicker.saveFile(
        dialogTitle: 'Backup speichern unter…',
        fileName: defaultFilename,
        type: FileType.any,
      );

      if (outputPath == null) return null; // Nutzer hat abgebrochen.

      final backupData = await _buildBackupPayload(database, isAuto: false);

      // JSON in vom Nutzer gewählte Datei schreiben
      final file = File(outputPath);
      await file.writeAsString(
        await _kodiereJson(backupData),
        flush: true,
      );

      return outputPath;
    } catch (e) {
      throw Exception('Backup-Export fehlgeschlagen: $e');
    }
  }

  /// Erstellt ein automatisches Backup (mit Timestamp-Präfix) im
  /// vorgegebenen Backup-Verzeichnis. Keine User-Interaktion.
  static Future<String> createAutoBackup(AppDatabase database) async {
    try {
      final backupDir = await _getBackupDir();

      final now = DateTime.now();
      final timeStamp = DateFormat('yyyy-MM-dd_HHmmss').format(now);
      final filename =
          '${_autoBackupFilePrefix}_$timeStamp.$_backupFileExtension';
      final filepath = '${backupDir.path}/$filename';

      final backupData = await _buildBackupPayload(database, isAuto: true);

      final file = File(filepath);
      await file.writeAsString(await _kodiereJson(backupData), flush: true);

      return filepath;
    } catch (e) {
      throw Exception('Auto-Backup fehlgeschlagen: $e');
    }
  }

  /// Wandelt das Backup-Payload in JSON — auf einem eigenen Isolate.
  ///
  /// Bei vollen Stammdaten sind das mehrere Megabyte. `jsonEncode` ist reine
  /// CPU-Arbeit und blockiert den UI-Thread, solange es läuft: Das Fenster
  /// friert ein, beim Beenden hakt die App sichtbar. Auf einem eigenen
  /// Isolate merkt der Nutzer davon nichts.
  ///
  /// Der Fallback ist Absicht: Sollte `Isolate.run` auf einer Plattform
  /// nicht verfügbar sein oder das Payload wider Erwarten etwas
  /// Nicht-Sendbares enthalten, wird ganz normal im Hauptisolate kodiert.
  /// Lieber kurz ruckeln als gar kein Backup.
  static Future<String> _kodiereJson(Map<String, dynamic> daten) async {
    try {
      return await Isolate.run(() => jsonEncode(daten));
    } catch (_) {
      return jsonEncode(daten);
    }
  }

  /// Schreibt den aktuellen Stand als Sicherung vor einem Restore.
  static Future<String> _schreibeSicherungVorRestore(
    AppDatabase database,
  ) async {
    final backupDir = await _getBackupDir();
    final timeStamp = DateFormat('yyyy-MM-dd_HHmmss').format(DateTime.now());
    final filepath = '${backupDir.path}/'
        '${_preRestoreFilePrefix}_$timeStamp.$_backupFileExtension';
    // isAuto: false — die Datei soll die Rotation überleben.
    final daten = await _buildBackupPayload(database, isAuto: false);
    await File(filepath).writeAsString(
      await _kodiereJson(daten),
      flush: true,
    );
    return filepath;
  }

  /// Baut das Backup-Payload zusammen. Zentrale Stelle damit
  /// `exportBackup` und `createAutoBackup` immer das gleiche Schema
  /// liefern.
  static Future<Map<String, dynamic>> _buildBackupPayload(
    AppDatabase database, {
    required bool isAuto,
  }) async {
    final now = DateTime.now();
    return {
      'version': _currentVersion,
      'timestamp': now.toIso8601String(),
      if (isAuto) 'type': 'auto',
      'data': {
        'products': await _exportProducts(database),
        'product_steps': await _exportProductSteps(database),
        'raw_materials': await _exportRawMaterials(database),
        'product_raw_materials': await _exportProductRawMaterials(database),
        'raw_material_batches': await _exportRawMaterialBatches(database),
        'production_tasks': await _exportProductionTasks(database),
        'production_runs': await _exportProductionRuns(database),
        'task_dependencies': await _exportTaskDependencies(database),
        'order_list_items': await _exportOrderListItems(database),
        // ── v3-Erweiterungen ─────────────────────────────────────────
        'machines': await _exportMachines(database),
        'product_step_parameters': await _exportProductStepParameters(database),
        'app_settings': await _exportAppSettings(database),
        // ── ab Backup-Version 1.1 ────────────────────────────────────
        // Ohne diese beiden Tabellen kam der Maschinen-Katalog auf einem
        // zweiten Rechner unvollständig an (Steckbriefe fehlten komplett).
        'machine_parameter_defs': await _exportMachineParameterDefs(database),
        'parameter_grenzen': await _exportParameterGrenzen(database),
        // ── ab Backup-Version 1.2 ────────────────────────────────────
        'zusatzzeiten': await _exportZusatzzeiten(database),
        // ── ab Backup-Version 1.3 ────────────────────────────────────
        'navision_umrechnungen': await _exportNavisionUmrechnungen(database),
        'demands': await _exportDemands(database),
        'production_history': await _exportProductionHistory(database),
        'week_snapshots': await _exportWeekSnapshots(database),
      },
    };
  }

  /// Importiert ein Backup aus einer Datei.
  ///
  /// Parameters:
  ///   - filepath: Pfad zur Backup-JSON-Datei
  ///   - database: Datenbankinstanz
  ///   - clearExisting: Wenn true, werden bestehende Daten vorher gelöscht
  static Future<void> importBackup(
    String filepath,
    AppDatabase database, {
    bool clearExisting = true,
    bool sicherungAnlegen = true,
  }) async {
    // ── Schritt 1: Datei lesen und prüfen (noch nichts angefasst) ─────
    final Map<String, dynamic> data;
    try {
      final file = File(filepath);
      if (!await file.exists()) {
        throw Exception('Backup-Datei nicht gefunden: $filepath');
      }

      final contents = await file.readAsString();
      final dekodiert = jsonDecode(contents);
      if (dekodiert is! Map<String, dynamic>) {
        throw Exception(
          'Die Datei ist kein gültiges Backup (erwartet wird ein '
          'JSON-Objekt).',
        );
      }
      final backupJson = dekodiert;

      // Version prüfen — ältere Backups bleiben lesbar.
      final version = backupJson['version'] as String?;
      if (version == null || !_supportedVersions.contains(version)) {
        throw Exception(
          'Inkompatible Backup-Version: $version '
          '(unterstützt: ${_supportedVersions.join(", ")})',
        );
      }

      // Früher ein harter Cast: Bei einer abgeschnittenen Datei — etwa
      // nach einem abgebrochenen USB-Transfer — kam ein unverständlicher
      // TypeError statt einer Ansage. Backups wandern zwischen zwei
      // Rechnern, das ist ein realistischer Fall.
      final rohDaten = backupJson['data'];
      if (rohDaten is! Map<String, dynamic>) {
        throw Exception(
          'Die Backup-Datei ist unvollständig oder beschädigt — der '
          'Datenteil fehlt. Bitte eine andere Sicherung wählen.',
        );
      }
      data = rohDaten;
    } catch (e) {
      throw Exception('Backup-Import fehlgeschlagen: $e');
    }

    // ── Schritt 2: Aktuellen Stand sichern ────────────────────────────
    //
    // Erst ab hier wird geschrieben. Die Transaktion unten schützt gegen
    // Abbrüche — aber nicht gegen die falsch ausgewählte Datei. Genau das
    // ist der häufigere Fehler, und ohne diese Kopie wäre er endgültig.
    if (sicherungAnlegen) {
      try {
        await _schreibeSicherungVorRestore(database);
      } catch (e) {
        throw Exception(
          'Der aktuelle Stand konnte nicht gesichert werden ($e). '
          'Das Wiederherstellen wurde NICHT ausgeführt — deine Daten sind '
          'unverändert. Bitte zuerst den Backup-Ordner prüfen.',
        );
      }
    }

    // ── Schritt 3: Transaktional einspielen ───────────────────────────
    try {
      await database.transaction(() async {
        if (clearExisting) {
          await _clearDatabase(database);
        }

        // Reihenfolge wichtig wegen Foreign-Key-Constraints!
        await _importProducts(database, data);
        await _importRawMaterials(database, data);
        // Machines vor ProductSteps importieren (FK)
        await _importMachines(database, data);
        // Steckbriefe hängen an den Maschinen → direkt danach.
        await _importMachineParameterDefs(database, data);
        await _importParameterGrenzen(database, data);
        await _importZusatzzeiten(database, data);
        await _importNavisionUmrechnungen(database, data);
        await _importProductSteps(database, data);
        await _importProductStepParameters(database, data);
        await _importProductRawMaterials(database, data);
        await _importRawMaterialBatches(database, data);
        await _importProductionTasks(database, data);
        await _importProductionRuns(database, data);
        await _importTaskDependencies(database, data);
        await _importOrderListItems(database, data);
        // Bedarf, Produktionshistorie und Wochen-Snapshots — kommen nach
        // products (production_history hat einen FK darauf).
        await _importDemands(database, data);
        await _importProductionHistory(database, data);
        await _importWeekSnapshots(database, data);
        await _importAppSettings(database, data);
      });
    } catch (e) {
      throw Exception('Backup-Import fehlgeschlagen: $e');
    }
  }

  /// Listet alle verfügbaren Backup-Dateien auf, sortiert mit dem
  /// neuesten zuerst.
  static Future<List<BackupInfo>> listBackups() async {
    try {
      final backupDir = await _getBackupDir();
      final dateien = await backupDir
          .list()
          .where((e) => e is File)
          .cast<File>()
          .where(
            (f) =>
                f.path.endsWith('.$_backupFileExtension') ||
                f.path.endsWith('.json'),
          )
          .toList();

      final backups = <BackupInfo>[];
      for (final file in dateien) {
        try {
          backups.add(await _readBackupInfo(file));
        } catch (_) {
          // Ungültige Backup-Datei überspringen
        }
      }

      // Nach dem Backup-Zeitpunkt sortieren, neuestes zuerst. Früher lief
      // das über die Datei-Änderungszeit — die verschiebt sich aber beim
      // Kopieren auf einen anderen Rechner und hätte die Reihenfolge dort
      // durcheinandergebracht.
      backups.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return backups;
    } catch (e) {
      throw Exception('Backup-List auslesen fehlgeschlagen: $e');
    }
  }

  /// Zeitstempel im Dateinamen: `..._2026-09-15_143022.planerbackup`
  static final RegExp _zeitstempelMuster =
      RegExp(r'(\d{4})-(\d{2})-(\d{2})_(\d{2})(\d{2})(\d{2})');

  /// Version im JSON-Kopf — steht als erster Schlüssel in der Datei.
  static final RegExp _versionMuster =
      RegExp(r'"version"\s*:\s*"([^"]{1,16})"');

  static DateTime? _zeitAusDateiname(String filename) {
    final m = _zeitstempelMuster.firstMatch(filename);
    if (m == null) return null;
    try {
      return DateTime(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
        int.parse(m.group(4)!),
        int.parse(m.group(5)!),
        int.parse(m.group(6)!),
      );
    } catch (_) {
      return null;
    }
  }

  /// Liest nur die ersten Bytes der Datei und zieht die Version heraus.
  static Future<String?> _versionAusKopf(File file, int laenge) async {
    try {
      final ende = laenge < 2048 ? laenge : 2048;
      if (ende <= 0) return null;
      final bytes =
          await file.openRead(0, ende).expand((teil) => teil).toList();
      final kopf = utf8.decode(bytes, allowMalformed: true);
      return _versionMuster.firstMatch(kopf)?.group(1);
    } catch (_) {
      return null;
    }
  }

  /// Liest Metainformationen einer Backup-Datei.
  ///
  /// Der schnelle Weg kommt ohne vollständiges Parsen aus: Zeitpunkt und
  /// Typ stecken im Dateinamen, die Version in den ersten 2 KB. Das ist
  /// der entscheidende Unterschied — [listBackups] läuft nach JEDEM
  /// Auto-Backup (über [cleanupOldAutoBackups]), und bei fünf Sicherungen
  /// à mehreren Megabyte wurde vorher jedes Mal der komplette Bestand
  /// eingelesen und durch `jsonDecode` geschickt, nur um Datum und
  /// Version zu erfahren.
  ///
  /// Für Dateien mit abweichendem Namen — etwa ein manueller Export, den
  /// jemand umbenannt hat — greift weiterhin der vollständige Weg.
  static Future<BackupInfo> _readBackupInfo(File file) async {
    final filename = file.path.split(Platform.pathSeparator).last;
    final zeit = _zeitAusDateiname(filename);

    if (zeit != null) {
      final groesse = await file.length();
      return BackupInfo(
        filename: filename,
        filepath: file.path,
        timestamp: zeit,
        version: (await _versionAusKopf(file, groesse)) ?? _currentVersion,
        sizeBytes: groesse,
        isAuto: filename.startsWith(_autoBackupFilePrefix),
      );
    }

    return _readBackupInfoVollstaendig(file);
  }

  /// Fallback: Datei komplett lesen und parsen.
  static Future<BackupInfo> _readBackupInfoVollstaendig(File file) async {
    final contents = await file.readAsString();
    final json = jsonDecode(contents) as Map<String, dynamic>;

    return BackupInfo(
      filename: file.path.split(Platform.pathSeparator).last,
      filepath: file.path,
      timestamp: DateTime.parse(json['timestamp'] as String),
      version: json['version'] as String,
      sizeBytes: await file.length(),
      isAuto: (json['type'] as String?) == 'auto',
    );
  }

  /// Löscht eine Backup-Datei.
  static Future<void> deleteBackup(String filepath) async {
    try {
      final file = File(filepath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      throw Exception('Backup-Löschung fehlgeschlagen: $e');
    }
  }

  /// Räumt alte Auto-Backups auf — behält die [maxKeep] neuesten,
  /// löscht den Rest. Wird beim Schreiben neuer Auto-Backups
  /// aufgerufen damit der Ordner nicht wuchert.
  /// Standard-Anzahl automatischer Backups, die aufbewahrt werden.
  ///
  /// Bewusst klein: Automatische Backups entstehen bei jeder Änderung, und
  /// ein einzelner Stand ist wertlos — ein versehentlich gespeicherter
  /// Fehler läge dann sofort im einzigen Backup. Fünf Stände geben ein bis
  /// zwei Arbeitstage Rückweg, um einen Fehler zu bemerken, bevor der letzte
  /// gute Stand herausrotiert. Manuelle Exporte sind davon NICHT betroffen
  /// (Filter auf `isAuto`).
  static const int standardMaxBackups = 5;

  static Future<void> cleanupOldAutoBackups({
    int maxKeep = standardMaxBackups,
  }) async {
    try {
      final all = await listBackups();
      // Nur automatische Backups rotieren — manuell exportierte Sicherungen
      // sind bewusste Momentaufnahmen und bleiben erhalten.
      final autos = all.where((b) => b.isAuto).toList();
      if (autos.length <= maxKeep) return;
      final zuLoeschen = autos.skip(maxKeep);
      for (final b in zuLoeschen) {
        await deleteBackup(b.filepath);
      }
    } catch (_) {
      // Cleanup ist Best-Effort, nicht kritisch
    }
  }

  /// Prüft ob die DB im Wesentlichen leer ist (keine Produkte).
  /// Wird vom Restore-Banner-Mechanismus verwendet, um zu entscheiden
  /// ob der Banner gezeigt werden soll.
  static Future<bool> isDatabaseEmpty(AppDatabase database) async {
    final products = await database.select(database.products).get();
    return products.isEmpty;
  }

  // ============================================================================
  // PRIVATE EXPORT-METHODEN
  // ============================================================================

  static Future<List<Map<String, dynamic>>> _exportProducts(
    AppDatabase db,
  ) async =>
      (await db.select(db.products).get()).map((p) => p.toJson()).toList();

  static Future<List<Map<String, dynamic>>> _exportProductSteps(
    AppDatabase db,
  ) async =>
      (await db.select(db.productSteps).get())
          .map((s) => s.toJson())
          .toList();

  static Future<List<Map<String, dynamic>>> _exportRawMaterials(
    AppDatabase db,
  ) async =>
      (await db.select(db.rawMaterials).get())
          .map((m) => m.toJson())
          .toList();

  static Future<List<Map<String, dynamic>>> _exportProductRawMaterials(
    AppDatabase db,
  ) async =>
      (await db.select(db.productRawMaterials).get())
          .map((p) => p.toJson())
          .toList();

  static Future<List<Map<String, dynamic>>> _exportRawMaterialBatches(
    AppDatabase db,
  ) async =>
      (await db.select(db.rawMaterialBatches).get())
          .map((b) => b.toJson())
          .toList();

  static Future<List<Map<String, dynamic>>> _exportProductionTasks(
    AppDatabase db,
  ) async =>
      (await db.select(db.productionTasks).get())
          .map((t) => t.toJson())
          .toList();

  static Future<List<Map<String, dynamic>>> _exportProductionRuns(
    AppDatabase db,
  ) async =>
      (await db.select(db.productionRuns).get())
          .map((r) => r.toJson())
          .toList();

  static Future<List<Map<String, dynamic>>> _exportTaskDependencies(
    AppDatabase db,
  ) async =>
      (await db.select(db.taskDependencies).get())
          .map((d) => d.toJson())
          .toList();

  static Future<List<Map<String, dynamic>>> _exportOrderListItems(
    AppDatabase db,
  ) async =>
      (await db.select(db.orderListItems).get())
          .map((o) => o.toJson())
          .toList();

  // ── v3-Tabellen ────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> _exportMachines(
    AppDatabase db,
  ) async =>
      (await db.select(db.machines).get()).map((m) => m.toJson()).toList();

  static Future<List<Map<String, dynamic>>> _exportProductStepParameters(
    AppDatabase db,
  ) async =>
      (await db.select(db.productStepParameters).get())
          .map((p) => p.toJson())
          .toList();

  static Future<List<Map<String, dynamic>>> _exportAppSettings(
    AppDatabase db,
  ) async =>
      (await db.select(db.appSettings).get()).map((s) => s.toJson()).toList();

  // ── Backup-Version 1.1: Steckbriefe + Grenzen ──────────────────────

  /// Maschinen-Steckbriefe (Parameterdefinitionen je Anlage). Ohne diese
  /// Tabelle wäre der Maschinen-Katalog nach einem Restore leer.
  static Future<List<Map<String, dynamic>>> _exportMachineParameterDefs(
    AppDatabase db,
  ) async =>
      (await db.select(db.machineParameterDefs).get())
          .map((d) => d.toJson())
          .toList();

  /// Parameter-Grenzen (Poka-Yoke: harte/weiche Min-/Max-Werte).
  static Future<List<Map<String, dynamic>>> _exportParameterGrenzen(
    AppDatabase db,
  ) async =>
      (await db.select(db.parameterGrenzen).get())
          .map((g) => g.toJson())
          .toList();

  /// Einheiten-Umrechnung für Navision-Artikel (BTL/PACK → kg).
  /// Der Artikelkatalog selbst wird NICHT gesichert — er ist eine Kopie
  /// aus Navision und jederzeit neu einlesbar. Die Faktoren dagegen sind
  /// Handarbeit und wären sonst verloren.
  static Future<List<Map<String, dynamic>>> _exportNavisionUmrechnungen(
    AppDatabase db,
  ) async =>
      (await db.select(db.navisionUmrechnungen).get())
          .map((u) => u.toJson())
          .toList();

  /// Rüst-/Reinigungszeiten je Tag und Planungsspur.
  static Future<List<Map<String, dynamic>>> _exportZusatzzeiten(
    AppDatabase db,
  ) async =>
      (await db.select(db.zusatzzeiten).get())
          .map((z) => z.toJson())
          .toList();

  // ── Backup-Version 1.4: Bedarf, Historie, Wochen-Snapshots ─────────

  /// Offener Bedarf (u.a. aus dem Navision-Import). Wurde früher NICHT
  /// gesichert — ein Restore hat ihn stillschweigend verloren.
  static Future<List<Map<String, dynamic>>> _exportDemands(
    AppDatabase db,
  ) async =>
      (await db.select(db.demands).get()).map((d) => d.toJson()).toList();

  /// Artikelweite Produktionshistorie (Rohware rein → Fertigware raus).
  static Future<List<Map<String, dynamic>>> _exportProductionHistory(
    AppDatabase db,
  ) async =>
      (await db.select(db.productionHistory).get())
          .map((h) => h.toJson())
          .toList();

  /// Eingefrorene Wochen-Planstände (Snapshots).
  static Future<List<Map<String, dynamic>>> _exportWeekSnapshots(
    AppDatabase db,
  ) async =>
      (await db.select(db.weekSnapshots).get())
          .map((s) => s.toJson())
          .toList();

  // ============================================================================
  // PRIVATE IMPORT-METHODEN
  // ============================================================================

  /// Holt eine Tabellen-Liste aus dem Backup-Payload. Fehlt der Schlüssel
  /// (ältere Backup-Version), ist das Ergebnis leer — es wird dann nichts
  /// importiert, statt den ganzen Restore scheitern zu lassen.
  static List<Map<String, dynamic>> _zeilen(
    Map<String, dynamic> data,
    String key,
  ) =>
      (data[key] as List?)?.cast<Map<String, dynamic>>() ?? const [];

  static Future<void> _importProducts(
    AppDatabase db,
    Map<String, dynamic> data,
  ) async {
    final products = _zeilen(data, 'products');
    // Bewusst Zeile für Zeile statt Batch: Diese Tabelle braucht beim
    // Zusammenführen (clearExisting == false) eine eigene Konflikt-Regel,
    // die nur Bezeichnung, Beschreibung und Notizen auffrischt und die
    // mühsam gepflegten Prozessdaten in Ruhe lässt. Bei einem vollen
    // Restore ist die Tabelle ohnehin leer, und mit ein paar hundert
    // Artikeln fällt der Unterschied nicht ins Gewicht.
    for (final p in products) {
      // Abwärtskompatibel: Backups, die vor der Spalte istEingepflegt
      // erstellt wurden, kennen den Schlüssel nicht. Fehlt er (oder ist
      // null), gilt der Artikel als eingepflegt (Default true) — sonst
      // scheitert Product.fromJson mit „Null is not a subtype of bool".
      if (p['istEingepflegt'] == null) p['istEingepflegt'] = true;
      final product = Product.fromJson(p);
      await db.into(db.products).insert(
            product.toCompanion(true),
            onConflict: DoUpdate(
              (old) => ProductsCompanion(
                artikelbezeichnung: Value(product.artikelbezeichnung),
                beschreibung: Value(product.beschreibung),
                notizen: Value(product.notizen),
                updatedAt: Value(DateTime.now()),
              ),
            ),
          );
    }
  }

  static Future<void> _importRawMaterials(
    AppDatabase db,
    Map<String, dynamic> data,
  ) async {
    final materials = _zeilen(data, 'raw_materials');
    // Gleiche Begründung wie bei _importProducts: eigene Konflikt-Regel.
    for (final m in materials) {
      final material = RawMaterial.fromJson(m);
      await db.into(db.rawMaterials).insert(
            material.toCompanion(true),
            onConflict: DoUpdate(
              (old) => RawMaterialsCompanion(
                name: Value(material.name),
                updatedAt: Value(DateTime.now()),
              ),
            ),
          );
    }
  }

  static Future<void> _importProductSteps(
    AppDatabase db,
    Map<String, dynamic> data,
  ) async {
    final zeilen = _zeilen(data, 'product_steps');
    if (zeilen.isEmpty) return;
    final eintraege = zeilen
        .map((z) => ProductStep.fromJson(z).toCompanion(true))
        .toList();
    await db.batch(
      (b) => b.insertAllOnConflictUpdate(db.productSteps, eintraege),
    );
  }

  static Future<void> _importProductRawMaterials(
    AppDatabase db,
    Map<String, dynamic> data,
  ) async {
    final zeilen = _zeilen(data, 'product_raw_materials');
    if (zeilen.isEmpty) return;
    final eintraege = zeilen
        .map((z) => ProductRawMaterial.fromJson(z).toCompanion(true))
        .toList();
    await db.batch(
      (b) => b.insertAllOnConflictUpdate(db.productRawMaterials, eintraege),
    );
  }

  /// DataClass von RawMaterialBatches heißt automatisch RawMaterialBatche.
  static Future<void> _importRawMaterialBatches(
    AppDatabase db,
    Map<String, dynamic> data,
  ) async {
    final zeilen = _zeilen(data, 'raw_material_batches');
    if (zeilen.isEmpty) return;
    final eintraege = zeilen
        .map((z) => RawMaterialBatche.fromJson(z).toCompanion(true))
        .toList();
    await db.batch(
      (b) => b.insertAllOnConflictUpdate(db.rawMaterialBatches, eintraege),
    );
  }

  static Future<void> _importProductionTasks(
    AppDatabase db,
    Map<String, dynamic> data,
  ) async {
    final zeilen = _zeilen(data, 'production_tasks');
    if (zeilen.isEmpty) return;
    final eintraege = zeilen
        .map((z) => ProductionTask.fromJson(z).toCompanion(true))
        .toList();
    await db.batch(
      (b) => b.insertAllOnConflictUpdate(db.productionTasks, eintraege),
    );
  }

  static Future<void> _importProductionRuns(
    AppDatabase db,
    Map<String, dynamic> data,
  ) async {
    final zeilen = _zeilen(data, 'production_runs');
    if (zeilen.isEmpty) return;
    final eintraege = zeilen
        .map((z) => ProductionRun.fromJson(z).toCompanion(true))
        .toList();
    await db.batch(
      (b) => b.insertAllOnConflictUpdate(db.productionRuns, eintraege),
    );
  }

  static Future<void> _importTaskDependencies(
    AppDatabase db,
    Map<String, dynamic> data,
  ) async {
    final zeilen = _zeilen(data, 'task_dependencies');
    if (zeilen.isEmpty) return;
    final eintraege = zeilen
        .map((z) => TaskDependency.fromJson(z).toCompanion(true))
        .toList();
    await db.batch(
      (b) => b.insertAllOnConflictUpdate(db.taskDependencies, eintraege),
    );
  }

  static Future<void> _importOrderListItems(
    AppDatabase db,
    Map<String, dynamic> data,
  ) async {
    final zeilen = _zeilen(data, 'order_list_items');
    if (zeilen.isEmpty) return;
    final eintraege = zeilen
        .map((z) => OrderListItem.fromJson(z).toCompanion(true))
        .toList();
    await db.batch(
      (b) => b.insertAllOnConflictUpdate(db.orderListItems, eintraege),
    );
  }

  // ── v3-Tabellen ────────────────────────────────────────────────────

  static Future<void> _importMachines(
    AppDatabase db,
    Map<String, dynamic> data,
  ) async {
    final zeilen = _zeilen(data, 'machines');
    if (zeilen.isEmpty) return;
    final eintraege = zeilen
        .map((z) => Machine.fromJson(z).toCompanion(true))
        .toList();
    await db.batch(
      (b) => b.insertAllOnConflictUpdate(db.machines, eintraege),
    );
  }

  static Future<void> _importProductStepParameters(
    AppDatabase db,
    Map<String, dynamic> data,
  ) async {
    final zeilen = _zeilen(data, 'product_step_parameters');
    if (zeilen.isEmpty) return;
    final eintraege = zeilen
        .map((z) => ProductStepParameter.fromJson(z).toCompanion(true))
        .toList();
    await db.batch(
      (b) => b.insertAllOnConflictUpdate(db.productStepParameters, eintraege),
    );
  }

  static Future<void> _importAppSettings(
    AppDatabase db,
    Map<String, dynamic> data,
  ) async {
    final zeilen = _zeilen(data, 'app_settings');
    if (zeilen.isEmpty) return;
    final eintraege = zeilen
        .map((z) => AppSetting.fromJson(z).toCompanion(true))
        .toList();
    await db.batch(
      (b) => b.insertAllOnConflictUpdate(db.appSettings, eintraege),
    );
  }

  // ── Backup-Version 1.1: Steckbriefe + Grenzen ──────────────────────
  // Ältere Backups (1.0) haben diese Schlüssel nicht — dann bleibt die
  // Liste leer und es wird nichts importiert.

  static Future<void> _importMachineParameterDefs(
    AppDatabase db,
    Map<String, dynamic> data,
  ) async {
    final zeilen = _zeilen(data, 'machine_parameter_defs');
    if (zeilen.isEmpty) return;
    final eintraege = zeilen
        .map((z) => MachineParameterDef.fromJson(z).toCompanion(true))
        .toList();
    await db.batch(
      (b) => b.insertAllOnConflictUpdate(db.machineParameterDefs, eintraege),
    );
  }

  static Future<void> _importNavisionUmrechnungen(
    AppDatabase db,
    Map<String, dynamic> data,
  ) async {
    final zeilen = _zeilen(data, 'navision_umrechnungen');
    if (zeilen.isEmpty) return;
    final eintraege = zeilen
        .map((z) => NavisionUmrechnung.fromJson(z).toCompanion(true))
        .toList();
    await db.batch(
      (b) => b.insertAllOnConflictUpdate(db.navisionUmrechnungen, eintraege),
    );
  }

  static Future<void> _importZusatzzeiten(
    AppDatabase db,
    Map<String, dynamic> data,
  ) async {
    final zeilen = _zeilen(data, 'zusatzzeiten');
    if (zeilen.isEmpty) return;
    final eintraege = zeilen
        .map((z) => Zusatzzeit.fromJson(z).toCompanion(true))
        .toList();
    await db.batch(
      (b) => b.insertAllOnConflictUpdate(db.zusatzzeiten, eintraege),
    );
  }

  static Future<void> _importParameterGrenzen(
    AppDatabase db,
    Map<String, dynamic> data,
  ) async {
    final zeilen = _zeilen(data, 'parameter_grenzen');
    if (zeilen.isEmpty) return;
    final eintraege = zeilen
        .map((z) => ParameterGrenzenData.fromJson(z).toCompanion(true))
        .toList();
    await db.batch(
      (b) => b.insertAllOnConflictUpdate(db.parameterGrenzen, eintraege),
    );
  }

  // ── Backup-Version 1.4: Bedarf, Historie, Wochen-Snapshots ─────────

  static Future<void> _importDemands(
    AppDatabase db,
    Map<String, dynamic> data,
  ) async {
    final zeilen = _zeilen(data, 'demands');
    if (zeilen.isEmpty) return;
    final eintraege = zeilen
        .map((z) => Demand.fromJson(z).toCompanion(true))
        .toList();
    await db.batch(
      (b) => b.insertAllOnConflictUpdate(db.demands, eintraege),
    );
  }

  static Future<void> _importProductionHistory(
    AppDatabase db,
    Map<String, dynamic> data,
  ) async {
    final zeilen = _zeilen(data, 'production_history');
    if (zeilen.isEmpty) return;
    final eintraege = zeilen
        .map((z) => ProductionHistoryData.fromJson(z).toCompanion(true))
        .toList();
    await db.batch(
      (b) => b.insertAllOnConflictUpdate(db.productionHistory, eintraege),
    );
  }

  static Future<void> _importWeekSnapshots(
    AppDatabase db,
    Map<String, dynamic> data,
  ) async {
    final zeilen = _zeilen(data, 'week_snapshots');
    if (zeilen.isEmpty) return;
    final eintraege = zeilen
        .map((z) => WeekSnapshot.fromJson(z).toCompanion(true))
        .toList();
    await db.batch(
      (b) => b.insertAllOnConflictUpdate(db.weekSnapshots, eintraege),
    );
  }

  // ============================================================================
  // CLEAR DATABASE
  // ============================================================================

  /// Löscht alle Daten aus den DB-Tabellen vor dem Restore.
  /// Reihenfolge wegen Foreign-Key-Constraints (Kinder zuerst).
  static Future<void> _clearDatabase(AppDatabase db) async {
    // Tasks und abhängige Tabellen zuerst
    await db.delete(db.productionRuns).go();
    await db.delete(db.taskDependencies).go();
    await db.delete(db.productionTasks).go();
    await db.delete(db.orderListItems).go();
    // Schritt-Parameter vor Schritten
    await db.delete(db.productStepParameters).go();
    await db.delete(db.productSteps).go();
    // Produkte und ihre Material-Verknüpfungen
    await db.delete(db.productRawMaterials).go();
    await db.delete(db.rawMaterialBatches).go();
    // Historie & Bedarf verweisen auf products (production_history per FK) —
    // vor dem Löschen der Produkte leeren, sonst FOREIGN KEY constraint failed.
    await db.delete(db.productionHistory).go();
    await db.delete(db.demands).go();
    await db.delete(db.products).go();
    await db.delete(db.rawMaterials).go();
    // Steckbriefe hängen an den Maschinen → vor dem Katalog löschen.
    await db.delete(db.navisionUmrechnungen).go();
    await db.delete(db.zusatzzeiten).go();
    await db.delete(db.machineParameterDefs).go();
    await db.delete(db.parameterGrenzen).go();
    // Anlagen-Katalog
    await db.delete(db.machines).go();
    // Wochen-Snapshots (eigenständig, keine FK).
    await db.delete(db.weekSnapshots).go();
    // App-Settings (importierte Excel-Datei wird mit-restauriert)
    await db.delete(db.appSettings).go();
  }
}

// ============================================================================
// BackupInfo
// ============================================================================

/// Metadaten einer Backup-Datei. Wird von `listBackups` und der UI benutzt.
class BackupInfo {
  const BackupInfo({
    required this.filename,
    required this.filepath,
    required this.timestamp,
    required this.version,
    required this.sizeBytes,
    required this.isAuto,
  });

  final String filename;
  final String filepath;
  final DateTime timestamp;
  final String version;
  final int sizeBytes;
  final bool isAuto;

  /// Größe in lesbarem Format (KB/MB).
  String get sizeFormatted {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Alias zu [sizeFormatted] — der bestehende BackupManagementScreen
  /// verwendet diesen Namen.
  String get formattedSize => sizeFormatted;

  /// Zeitstempel im deutschen Format.
  String get formattedTimestamp =>
      DateFormat('dd.MM.yyyy HH:mm').format(timestamp);

  /// Stammt das Backup aus einer Version VOR 1.4?
  ///
  /// Solche Sicherungen enthalten weder Bedarfsliste noch Produktions-
  /// historie noch Wochen-Snapshots — diese Tabellen wurden damals nicht
  /// mitgeschrieben. Beim Wiederherstellen sind sie danach leer, ohne dass
  /// irgendetwas kaputt wäre. Genau das sollte man vorher wissen.
  bool get istAeltereVersion => version != BackupService._currentVersion;

  /// Was in einem älteren Backup fehlt — null bei aktueller Version.
  String? get versionsHinweis => istAeltereVersion
      ? 'Älteres Format: Bedarf, Historie und Wochen-Snapshots fehlen '
          'möglicherweise.'
      : null;
}




