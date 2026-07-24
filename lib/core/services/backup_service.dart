import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

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
  static const String _backupFileExtension = 'planerbackup';
  /// Aktuelle Backup-Version.
  ///
  /// 1.0 → ohne Maschinen-Steckbriefe und Parameter-Grenzen
  /// 1.1 → vollständig (inkl. `machine_parameter_defs`, `parameter_grenzen`)
  static const String _currentVersion = '1.2';

  /// Alle Versionen, die beim Import gelesen werden können. Ältere
  /// Backups bleiben gültig — die dort fehlenden Tabellen werden beim
  /// Import einfach übersprungen (leere Liste).
  static const Set<String> _supportedVersions = {'1.0', '1.1', '1.2'};

  /// Erstellt alle notwendigen Verzeichnisse.
  static Future<Directory> _getBackupDir() async {
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
        jsonEncode(backupData),
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
      await file.writeAsString(jsonEncode(backupData), flush: true);

      return filepath;
    } catch (e) {
      throw Exception('Auto-Backup fehlgeschlagen: $e');
    }
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
  }) async {
    try {
      final file = File(filepath);
      if (!await file.exists()) {
        throw Exception('Backup-Datei nicht gefunden: $filepath');
      }

      final contents = await file.readAsString();
      final backupJson = jsonDecode(contents) as Map<String, dynamic>;

      // Version prüfen
      // Version prüfen — ältere Backups bleiben lesbar.
      final version = backupJson['version'] as String?;
      if (version == null || !_supportedVersions.contains(version)) {
        throw Exception(
          'Inkompatible Backup-Version: $version '
          '(unterstützt: ${_supportedVersions.join(", ")})',
        );
      }

      // In Datenbank-Transaktion importieren
      await database.transaction(() async {
        if (clearExisting) {
          await _clearDatabase(database);
        }

        final data = backupJson['data'] as Map<String, dynamic>;

        // Reihenfolge wichtig wegen Foreign-Key-Constraints!
        await _importProducts(database, data);
        await _importRawMaterials(database, data);
        // Machines vor ProductSteps importieren (FK)
        await _importMachines(database, data);
        // Steckbriefe hängen an den Maschinen → direkt danach.
        await _importMachineParameterDefs(database, data);
        await _importParameterGrenzen(database, data);
        await _importZusatzzeiten(database, data);
        await _importProductSteps(database, data);
        await _importProductStepParameters(database, data);
        await _importProductRawMaterials(database, data);
        await _importRawMaterialBatches(database, data);
        await _importProductionTasks(database, data);
        await _importProductionRuns(database, data);
        await _importTaskDependencies(database, data);
        await _importOrderListItems(database, data);
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
      final files = backupDir
          .listSync()
          .whereType<File>()
          .where(
            (f) =>
                f.path.endsWith('.$_backupFileExtension') ||
                f.path.endsWith('.json'),
          )
          .toList()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

      final backups = <BackupInfo>[];
      for (final file in files) {
        try {
          final info = await _readBackupInfo(file);
          backups.add(info);
        } catch (_) {
          // Ungültige Backup-Datei überspringen
        }
      }

      return backups;
    } catch (e) {
      throw Exception('Backup-List auslesen fehlgeschlagen: $e');
    }
  }

  /// Liest Metainformationen einer Backup-Datei.
  static Future<BackupInfo> _readBackupInfo(File file) async {
    final contents = await file.readAsString();
    final json = jsonDecode(contents) as Map<String, dynamic>;

    return BackupInfo(
      filename: file.path.split(Platform.pathSeparator).last,
      filepath: file.path,
      timestamp: DateTime.parse(json['timestamp'] as String),
      version: json['version'] as String,
      sizeBytes: file.lengthSync(),
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

  /// Rüst-/Reinigungszeiten je Tag und Planungsspur.
  static Future<List<Map<String, dynamic>>> _exportZusatzzeiten(
    AppDatabase db,
  ) async =>
      (await db.select(db.zusatzzeiten).get())
          .map((z) => z.toJson())
          .toList();

  // ============================================================================
  // PRIVATE IMPORT-METHODEN
  // ============================================================================

  static Future<void> _importProducts(
    AppDatabase db,
    Map<String, dynamic> data,
  ) async {
    final products =
        (data['products'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final p in products) {
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
    final materials =
        (data['raw_materials'] as List?)?.cast<Map<String, dynamic>>() ?? [];
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
    final steps =
        (data['product_steps'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final s in steps) {
      final step = ProductStep.fromJson(s);
      await db.into(db.productSteps).insertOnConflictUpdate(
            step.toCompanion(true),
          );
    }
  }

  static Future<void> _importProductRawMaterials(
    AppDatabase db,
    Map<String, dynamic> data,
  ) async {
    final list =
        (data['product_raw_materials'] as List?)?.cast<Map<String, dynamic>>() ??
            [];
    for (final p in list) {
      final entry = ProductRawMaterial.fromJson(p);
      await db.into(db.productRawMaterials).insertOnConflictUpdate(
            entry.toCompanion(true),
          );
    }
  }

  static Future<void> _importRawMaterialBatches(
    AppDatabase db,
    Map<String, dynamic> data,
  ) async {
    final list =
        (data['raw_material_batches'] as List?)?.cast<Map<String, dynamic>>() ??
            [];
    for (final b in list) {
      // DataClass von RawMaterialBatches heißt automatisch RawMaterialBatche
      final batch = RawMaterialBatche.fromJson(b);
      await db.into(db.rawMaterialBatches).insertOnConflictUpdate(
            batch.toCompanion(true),
          );
    }
  }

  static Future<void> _importProductionTasks(
    AppDatabase db,
    Map<String, dynamic> data,
  ) async {
    final list =
        (data['production_tasks'] as List?)?.cast<Map<String, dynamic>>() ??
            [];
    for (final t in list) {
      final task = ProductionTask.fromJson(t);
      await db.into(db.productionTasks).insertOnConflictUpdate(
            task.toCompanion(true),
          );
    }
  }

  static Future<void> _importProductionRuns(
    AppDatabase db,
    Map<String, dynamic> data,
  ) async {
    final list =
        (data['production_runs'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final r in list) {
      final run = ProductionRun.fromJson(r);
      await db.into(db.productionRuns).insertOnConflictUpdate(
            run.toCompanion(true),
          );
    }
  }

  static Future<void> _importTaskDependencies(
    AppDatabase db,
    Map<String, dynamic> data,
  ) async {
    final list =
        (data['task_dependencies'] as List?)?.cast<Map<String, dynamic>>() ??
            [];
    for (final d in list) {
      final dep = TaskDependency.fromJson(d);
      await db.into(db.taskDependencies).insertOnConflictUpdate(
            dep.toCompanion(true),
          );
    }
  }

  static Future<void> _importOrderListItems(
    AppDatabase db,
    Map<String, dynamic> data,
  ) async {
    final list =
        (data['order_list_items'] as List?)?.cast<Map<String, dynamic>>() ??
            [];
    for (final o in list) {
      final item = OrderListItem.fromJson(o);
      await db.into(db.orderListItems).insertOnConflictUpdate(
            item.toCompanion(true),
          );
    }
  }

  // ── v3-Tabellen ────────────────────────────────────────────────────

  static Future<void> _importMachines(
    AppDatabase db,
    Map<String, dynamic> data,
  ) async {
    final list =
        (data['machines'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final m in list) {
      final machine = Machine.fromJson(m);
      await db.into(db.machines).insertOnConflictUpdate(
            machine.toCompanion(true),
          );
    }
  }

  static Future<void> _importProductStepParameters(
    AppDatabase db,
    Map<String, dynamic> data,
  ) async {
    final list =
        (data['product_step_parameters'] as List?)
                ?.cast<Map<String, dynamic>>() ??
            [];
    for (final p in list) {
      final param = ProductStepParameter.fromJson(p);
      await db.into(db.productStepParameters).insertOnConflictUpdate(
            param.toCompanion(true),
          );
    }
  }

  static Future<void> _importAppSettings(
    AppDatabase db,
    Map<String, dynamic> data,
  ) async {
    final list =
        (data['app_settings'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final s in list) {
      final setting = AppSetting.fromJson(s);
      await db.into(db.appSettings).insertOnConflictUpdate(
            setting.toCompanion(true),
          );
    }
  }

  // ── Backup-Version 1.1: Steckbriefe + Grenzen ──────────────────────
  // Ältere Backups (1.0) haben diese Schlüssel nicht — dann bleibt die
  // Liste leer und es wird nichts importiert.

  static Future<void> _importMachineParameterDefs(
    AppDatabase db,
    Map<String, dynamic> data,
  ) async {
    final list = (data['machine_parameter_defs'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    for (final d in list) {
      final def = MachineParameterDef.fromJson(d);
      await db.into(db.machineParameterDefs).insertOnConflictUpdate(
            def.toCompanion(true),
          );
    }
  }

  static Future<void> _importZusatzzeiten(
    AppDatabase db,
    Map<String, dynamic> data,
  ) async {
    final list =
        (data['zusatzzeiten'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final z in list) {
      final eintrag = Zusatzzeit.fromJson(z);
      await db.into(db.zusatzzeiten).insertOnConflictUpdate(
            eintrag.toCompanion(true),
          );
    }
  }

  static Future<void> _importParameterGrenzen(
    AppDatabase db,
    Map<String, dynamic> data,
  ) async {
    final list =
        (data['parameter_grenzen'] as List?)?.cast<Map<String, dynamic>>() ??
            [];
    for (final g in list) {
      final grenze = ParameterGrenzenData.fromJson(g);
      await db.into(db.parameterGrenzen).insertOnConflictUpdate(
            grenze.toCompanion(true),
          );
    }
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
    await db.delete(db.products).go();
    await db.delete(db.rawMaterials).go();
    // Steckbriefe hängen an den Maschinen → vor dem Katalog löschen.
    await db.delete(db.zusatzzeiten).go();
    await db.delete(db.machineParameterDefs).go();
    await db.delete(db.parameterGrenzen).go();
    // Anlagen-Katalog
    await db.delete(db.machines).go();
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
}
