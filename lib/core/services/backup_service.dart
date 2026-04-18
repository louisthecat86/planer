import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../database/database.dart';
import 'personnel_service.dart';

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
  static const String _currentVersion = '1.0';

  /// Erstellt alle notwendigen Verzeichnisse.
  static Future<Directory> _getBackupDir() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final backupDir = Directory('${appDocDir.path}/$_backupDirName');
    
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    
    return backupDir;
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

      // Alle Daten aus den Tabellen auslesen
      final backupData = {
        'version': _currentVersion,
        'timestamp': now.toIso8601String(),
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
          'personnel_planning': (await PersonnelService.loadPlan()).toJson(),
        },
      };

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

  /// Erstellt ein automatisches Backup (mit Timestamp-Präfix).
  static Future<String> createAutoBackup(AppDatabase database) async {
    try {
      final backupDir = await _getBackupDir();
      
      final now = DateTime.now();
      final timeStamp = DateFormat('yyyy-MM-dd_HHmmss').format(now);
      final filename = '${_autoBackupFilePrefix}_$timeStamp.$_backupFileExtension';
      final filepath = '${backupDir.path}/$filename';

      final backupData = {
        'version': _currentVersion,
        'timestamp': now.toIso8601String(),
        'type': 'auto',
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
          'personnel_planning': (await PersonnelService.loadPlan()).toJson(),
        },
      };

      final file = File(filepath);
      await file.writeAsString(jsonEncode(backupData), flush: true);

      return filepath;
    } catch (e) {
      throw Exception('Auto-Backup fehlgeschlagen: $e');
    }
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
      final version = backupJson['version'] as String?;
      if (version != _currentVersion) {
        throw Exception('Inkompatible Backup-Version: $version (erwartet: $_currentVersion)');
      }

      // In Datenbank-Transaktion importieren
      await database.transaction(() async {
        // Optional: Bestehende Daten löschen
        if (clearExisting) {
          await _clearDatabase(database);
        }

        final data = backupJson['data'] as Map<String, dynamic>;

        // Alle Tabellen der Reihe nach importieren
        // (Reihenfolge wichtig wegen Foreign-Key-Constraints!)
        await _importProducts(database, data);
        await _importRawMaterials(database, data);
        await _importProductSteps(database, data);
        await _importProductRawMaterials(database, data);
        await _importRawMaterialBatches(database, data);
        await _importProductionTasks(database, data);
        await _importProductionRuns(database, data);
        await _importTaskDependencies(database, data);
        await _importOrderListItems(database, data);
      });

      if (backupJson['data'] is Map<String, dynamic>) {
        final data = backupJson['data'] as Map<String, dynamic>;
        if (data['personnel_planning'] is Map<String, dynamic>) {
          final personnelJson = data['personnel_planning'] as Map<String, dynamic>;
          await PersonnelService.savePlan(PersonnelPlan.fromJson(personnelJson));
        }
      }
    } catch (e) {
      throw Exception('Backup-Import fehlgeschlagen: $e');
    }
  }

  /// Listet alle verfügbaren Backup-Dateien auf.
  static Future<List<BackupInfo>> listBackups() async {
    try {
      final backupDir = await _getBackupDir();
      final files = backupDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.$_backupFileExtension') || f.path.endsWith('.json'))
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
      filename: file.path.split('/').last,
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

  // ============================================================================
  // PRIVATE EXPORT-METHODEN
  // ============================================================================

  static Future<List<Map<String, dynamic>>> _exportProducts(AppDatabase db) async =>
      (await db.select(db.products).get()).map((p) => p.toJson()).toList();

  static Future<List<Map<String, dynamic>>> _exportProductSteps(AppDatabase db) async =>
      (await db.select(db.productSteps).get()).map((s) => s.toJson()).toList();

  static Future<List<Map<String, dynamic>>> _exportRawMaterials(AppDatabase db) async =>
      (await db.select(db.rawMaterials).get()).map((m) => m.toJson()).toList();

  static Future<List<Map<String, dynamic>>> _exportProductRawMaterials(AppDatabase db) async =>
      (await db.select(db.productRawMaterials).get()).map((p) => p.toJson()).toList();

  static Future<List<Map<String, dynamic>>> _exportRawMaterialBatches(AppDatabase db) async =>
      (await db.select(db.rawMaterialBatches).get()).map((b) => b.toJson()).toList();

  static Future<List<Map<String, dynamic>>> _exportProductionTasks(AppDatabase db) async =>
      (await db.select(db.productionTasks).get()).map((t) => t.toJson()).toList();

  static Future<List<Map<String, dynamic>>> _exportProductionRuns(AppDatabase db) async =>
      (await db.select(db.productionRuns).get()).map((r) => r.toJson()).toList();

  static Future<List<Map<String, dynamic>>> _exportTaskDependencies(AppDatabase db) async =>
      (await db.select(db.taskDependencies).get()).map((d) => d.toJson()).toList();

  static Future<List<Map<String, dynamic>>> _exportOrderListItems(AppDatabase db) async =>
      (await db.select(db.orderListItems).get()).map((o) => o.toJson()).toList();

  // ============================================================================
  // PRIVATE IMPORT-METHODEN
  // ============================================================================

  static Future<void> _importProducts(AppDatabase db, Map<String, dynamic> data) async {
    final products = (data['products'] as List?)?.cast<Map<String, dynamic>>() ?? [];
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

  static Future<void> _importRawMaterials(AppDatabase db, Map<String, dynamic> data) async {
    final materials = (data['raw_materials'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final m in materials) {
      final material = RawMaterial.fromJson(m);
      await db.into(db.rawMaterials).insert(
            material.toCompanion(true),
            onConflict: DoUpdate(
              (old) => RawMaterialsCompanion(
                name: Value(material.name),
                artikelnummer: Value(material.artikelnummer),
                einheit: Value(material.einheit),
                lieferant: Value(material.lieferant),
                leadTimeTage: Value(material.leadTimeTage),
                chargenPflicht: Value(material.chargenPflicht),
                notizen: Value(material.notizen),
                updatedAt: Value(DateTime.now()),
              ),
            ),
          );
    }
  }

  static Future<void> _importProductSteps(AppDatabase db, Map<String, dynamic> data) async {
    final steps = (data['product_steps'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final s in steps) {
      final step = ProductStep.fromJson(s);
      await db.into(db.productSteps).insert(
            step.toCompanion(true),
            onConflict: DoUpdate(
              (old) => ProductStepsCompanion(
                productId: Value(step.productId),
                reihenfolge: Value(step.reihenfolge),
                abteilung: Value(step.abteilung),
                basisMengeKg: Value(step.basisMengeKg),
                basisDauerMinuten: Value(step.basisDauerMinuten),
                fixZeitMinuten: Value(step.fixZeitMinuten),
                dauerStdAbweichung: Value(step.dauerStdAbweichung),
                basisMitarbeiter: Value(step.basisMitarbeiter),
                basisAnzahlMessungen: Value(step.basisAnzahlMessungen),
                maschinenEinstellungenJson: Value(step.maschinenEinstellungenJson),
                notizen: Value(step.notizen),
                updatedAt: Value(DateTime.now()),
              ),
            ),
          );
    }
  }

  static Future<void> _importProductRawMaterials(AppDatabase db, Map<String, dynamic> data) async {
    final prm = (data['product_raw_materials'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final item in prm) {
      final productRawMaterial = ProductRawMaterial.fromJson(item);
      await db.into(db.productRawMaterials).insert(
            productRawMaterial.toCompanion(true),
            onConflict: DoUpdate(
              (old) => ProductRawMaterialsCompanion(
                productId: Value(productRawMaterial.productId),
                rawMaterialId: Value(productRawMaterial.rawMaterialId),
                mengeProKgProdukt: Value(productRawMaterial.mengeProKgProdukt),
                toleranzProzent: Value(productRawMaterial.toleranzProzent),
                notizen: Value(productRawMaterial.notizen),
                updatedAt: Value(DateTime.now()),
              ),
            ),
          );
    }
  }

  static Future<void> _importRawMaterialBatches(AppDatabase db, Map<String, dynamic> data) async {
    final batches = (data['raw_material_batches'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final b in batches) {
      final batch = RawMaterialBatche.fromJson(b);
      await db.into(db.rawMaterialBatches).insert(
            batch.toCompanion(true),
            onConflict: DoUpdate(
              (old) => RawMaterialBatchesCompanion(
                rawMaterialId: Value(batch.rawMaterialId),
                chargennummer: Value(batch.chargennummer),
                mhd: Value(batch.mhd),
                eingangsDatum: Value(batch.eingangsDatum),
                mengeInitial: Value(batch.mengeInitial),
                mengeAktuell: Value(batch.mengeAktuell),
                einheit: Value(batch.einheit),
                lieferant: Value(batch.lieferant),
                notizen: Value(batch.notizen),
                updatedAt: Value(DateTime.now()),
              ),
            ),
          );
    }
  }

  static Future<void> _importProductionTasks(AppDatabase db, Map<String, dynamic> data) async {
    final tasks = (data['production_tasks'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final taskObjects = tasks.map(ProductionTask.fromJson).toList();

    for (final task in taskObjects) {
      await db.into(db.productionTasks).insert(
            ProductionTasksCompanion(
              id: Value(task.id),
              productId: Value(task.productId),
              mengeKg: Value(task.mengeKg),
              datum: Value(task.datum),
              abteilung: Value(task.abteilung),
              startZeit: Value(task.startZeit),
              geplanteDauerMinuten: Value(task.geplanteDauerMinuten),
              geplanteMitarbeiter: Value(task.geplanteMitarbeiter),
              status: Value(task.status),
              parentTaskId: const Value.absent(),
              notizen: Value(task.notizen),
              createdAt: Value(task.createdAt),
              updatedAt: Value(task.updatedAt),
              deletedAt: task.deletedAt == null ? const Value.absent() : Value(task.deletedAt),
            ),
            onConflict: DoUpdate(
              (old) => ProductionTasksCompanion(
                productId: Value(task.productId),
                mengeKg: Value(task.mengeKg),
                datum: Value(task.datum),
                abteilung: Value(task.abteilung),
                startZeit: Value(task.startZeit),
                geplanteDauerMinuten: Value(task.geplanteDauerMinuten),
                geplanteMitarbeiter: Value(task.geplanteMitarbeiter),
                status: Value(task.status),
                notizen: Value(task.notizen),
                updatedAt: Value(DateTime.now()),
              ),
            ),
          );
    }

    for (final task in taskObjects.where((task) => task.parentTaskId != null)) {
      await (db.update(db.productionTasks)..where((tbl) => tbl.id.equals(task.id))).write(
            ProductionTasksCompanion(
              parentTaskId: Value(task.parentTaskId),
              updatedAt: Value(DateTime.now()),
            ),
          );
    }
  }

  static Future<void> _importProductionRuns(AppDatabase db, Map<String, dynamic> data) async {
    final runs = (data['production_runs'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final r in runs) {
      final run = ProductionRun.fromJson(r);
      await db.into(db.productionRuns).insert(
            run.toCompanion(true),
            onConflict: DoUpdate(
              (old) => ProductionRunsCompanion(
                taskId: Value(run.taskId),
                tatsaechlicheDauerMinuten: Value(run.tatsaechlicheDauerMinuten),
                tatsaechlicheMitarbeiter: Value(run.tatsaechlicheMitarbeiter),
                tatsaechlicheMengeKg: Value(run.tatsaechlicheMengeKg),
                verwendeteChargenJson: Value(run.verwendeteChargenJson),
                notizen: Value(run.notizen),
                erfasstVon: Value(run.erfasstVon),
                erfasstAm: Value(run.erfasstAm),
                updatedAt: Value(DateTime.now()),
              ),
            ),
          );
    }
  }

  static Future<void> _importTaskDependencies(AppDatabase db, Map<String, dynamic> data) async {
    final deps = (data['task_dependencies'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final d in deps) {
      final dep = TaskDependency.fromJson(d);
      await db.into(db.taskDependencies).insert(
            dep.toCompanion(true),
            onConflict: DoUpdate(
              (old) => TaskDependenciesCompanion(
                fromTaskId: Value(dep.fromTaskId),
                toTaskId: Value(dep.toTaskId),
                typ: Value(dep.typ),
                updatedAt: Value(DateTime.now()),
              ),
            ),
          );
    }
  }

  static Future<void> _importOrderListItems(AppDatabase db, Map<String, dynamic> data) async {
    final items = (data['order_list_items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final item in items) {
      final orderItem = OrderListItem.fromJson(item);
      await db.into(db.orderListItems).insert(
            orderItem.toCompanion(true),
            onConflict: DoUpdate(
              (old) => OrderListItemsCompanion(
                rawMaterialId: Value(orderItem.rawMaterialId),
                wocheStartDatum: Value(orderItem.wocheStartDatum),
                benoetigteMenge: Value(orderItem.benoetigteMenge),
                einheit: Value(orderItem.einheit),
                bestellt: Value(orderItem.bestellt),
                bestelltAm: Value(orderItem.bestelltAm),
                geliefert: Value(orderItem.geliefert),
                geliefertAm: Value(orderItem.geliefertAm),
                notizen: Value(orderItem.notizen),
                updatedAt: Value(DateTime.now()),
              ),
            ),
          );
    }
  }

  // ============================================================================
  // HILFSMETHODEN
  // ============================================================================

  static Future<void> _clearDatabase(AppDatabase db) async {
    await db.delete(db.taskDependencies).go();
    await db.delete(db.productionRuns).go();
    await db.delete(db.productionTasks).go();
    await db.delete(db.rawMaterialBatches).go();
    await db.delete(db.productRawMaterials).go();
    await db.delete(db.productSteps).go();
    await db.delete(db.orderListItems).go();
    await db.delete(db.products).go();
    await db.delete(db.rawMaterials).go();
  }
}

/// Metainformation über eine Backup-Datei.
class BackupInfo {
  final String filename;
  final String filepath;
  final DateTime timestamp;
  final String version;
  final int sizeBytes;
  final bool isAuto;

  BackupInfo({
    required this.filename,
    required this.filepath,
    required this.timestamp,
    required this.version,
    required this.sizeBytes,
    required this.isAuto,
  });

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(2)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String get formattedTimestamp {
    final dateFormatted = DateFormat('dd.MM.yyyy, HH:mm').format(timestamp);
    return dateFormatted;
  }
}
