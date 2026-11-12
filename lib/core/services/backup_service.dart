import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/entwicklung.dart';
import '../database/database.dart';
import '../utils/fehler_text.dart';
import '../utils/format.dart';
import 'datei_ablage.dart';
import 'entwicklung_sicherung.dart';
import 'artikel_fotos.dart';
import 'auftragsbestand_sicherung.dart';

/// Backup-Service für Export/Import der Datenbankdaten als JSON.
///
/// Speichert Backups im Ordner `backups` unter den Dokumenten — oder in
/// einem selbst gewählten Ordner (siehe [getEigenerBackupOrdner]).
///
/// Zwei Arten:
/// - **Auto-Backup** (nach Änderungen, beim Beenden, Schnell-Backup, vor
///   einem Restore): die Daten gepackt, die Fotos der Artikel und die
///   angehängten Dateien der Produktentwicklung nur als Prüfsumme. Ihr
///   Inhalt liegt einmal in der Ablage `planer_dateien` neben den Backups
///   ([DateiAblage]) — statt in jedem Backup ganz.
/// - **Komplett-Backup** (von Hand gespeichert): alles in einer Datei, auch
///   Fotos und Dateien — zum Umziehen auf einen anderen Rechner.
///
/// Geschrieben wird erst in eine Zwischendatei, dann umbenannt: Bricht das
/// Schreiben ab, bleibt keine halbe Sicherung unter dem richtigen Namen.
class BackupService {
  static const String _backupDirName = 'backups';
  static const String _komplettFilePrefix = 'planer_komplett';
  static const String _autoBackupFilePrefix = 'planer_auto_backup';

  /// Präfix der Sicherung, die unmittelbar VOR einem Restore geschrieben
  /// wird. Bewusst ein eigener Name: Diese Datei zählt nicht als
  /// Auto-Backup und wird deshalb von [cleanupOldAutoBackups] nie
  /// wegrotiert — sie ist die letzte Rückfahrkarte, wenn jemand das
  /// falsche Backup erwischt hat.
  static const String _preRestoreFilePrefix = 'planer_vor_restore';
  static const String _backupFileExtension = 'planerbackup';

  /// Endung der Zwischendatei beim Schreiben.
  static const String _zwischenEndung = '.tmp';

  /// Aktuelle Backup-Version.
  ///
  /// 1.0 → ohne Maschinen-Steckbriefe und Parameter-Grenzen
  /// 1.1 → vollständig (inkl. `machine_parameter_defs`, `parameter_grenzen`)
  /// 1.4 → inkl. `demands`, `production_history`, `week_snapshots`
  /// 1.5 → inkl. `tagesaufgaben`
  /// 1.6 → gepackt (gzip); im Auto-Backup die Dateien der
  ///       Produktentwicklung nur als Verweis auf die Ablage daneben
  /// 1.7 → inkl. der Fotos zum Artikel (`artikel_fotos`) — im Auto-Backup
  ///       als Verweis auf die Ablage
  /// 1.8 → inkl. Auftragsbestand (`auftragsbestand_…`, auch der Stand
  ///       davor); ältere Backups lassen den des Rechners unberührt
  static const String _currentVersion = '1.8';

  /// Alle Versionen, die beim Import gelesen werden können. Ältere
  /// Backups bleiben gültig — die dort fehlenden Tabellen werden beim
  /// Import einfach übersprungen (leere Liste).
  static const Set<String> _supportedVersions = {
    '1.0',
    '1.1',
    '1.2',
    '1.3',
    '1.4',
    '1.5',
    '1.6',
    '1.7',
    '1.8',
  };

  /// Nur für Tests: dieser Ordner statt des eingestellten — die Tests
  /// kommen nicht an Dokumente-Ordner und Einstellungen heran.
  @visibleForTesting
  static Directory? ordnerFuerTests;

  /// Schlüssel des selbst gewählten Backup-Ordners.
  ///
  /// Bewusst in den SharedPreferences und nicht in `app_settings`: Der Pfad
  /// muss auch dann lesbar sein, wenn die Datenbank gerade zurückgesetzt
  /// oder aus einem Backup ersetzt wird — und er ist gerätespezifisch, ein
  /// Backup soll ihn also NICHT mit auf einen anderen Rechner tragen.
  static const String _prefsKeyBackupDir = 'backup_verzeichnis';

  /// Merker: Der Ordner aus der Zeit vor dem neuen Programmnamen wurde
  /// schon gesucht (siehe [alteEinstellungUebernehmen]).
  static const String _prefsKeyOrdnerUebernommen =
      'backup_verzeichnis_uebernommen';

  /// Der selbst gewählte Backup-Ordner, oder null = Standard.
  static Future<String?> getEigenerBackupOrdner() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (Platform.isWindows) await alteEinstellungUebernehmen(prefs);
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

  /// Holt den Backup-Ordner aus den Einstellungen unter dem alten
  /// Programmnamen.
  ///
  /// Unter Windows hieß das Programm „produktion_planer" der Firma
  /// „com.example", jetzt „Produktions Planer". Windows legt die
  /// Einstellungen in einem Ordner nach diesen Namen ab — vorher
  /// `%APPDATA%\com.example\produktion_planer`, jetzt
  /// `%APPDATA%\Produktions Planer`. Ohne die Übernahme wäre ein selbst
  /// gewählter Backup-Ordner nach dem Update vergessen, und die Backups
  /// landeten still wieder im Standardordner. Die Daten selbst liegen in
  /// den Dokumenten und bleiben vom Namen unberührt.
  ///
  /// Einmalig: Wer danach wieder den Standard wählt, bekommt den alten
  /// Pfad nicht zurück. [appData] ist nur für Tests.
  @visibleForTesting
  static Future<void> alteEinstellungUebernehmen(
    SharedPreferences prefs, {
    String? appData,
  }) async {
    if (prefs.getBool(_prefsKeyOrdnerUebernommen) ?? false) return;
    if (prefs.getString(_prefsKeyBackupDir) == null) {
      final alt = await _alterBackupOrdner(
        appData ?? Platform.environment['APPDATA'],
      );
      if (alt != null) await prefs.setString(_prefsKeyBackupDir, alt);
    }
    await prefs.setBool(_prefsKeyOrdnerUebernommen, true);
  }

  static Future<String?> _alterBackupOrdner(String? appData) async {
    if (appData == null || appData.trim().isEmpty) return null;
    try {
      final datei = File(
        [
          appData,
          'com.example',
          'produktion_planer',
          'shared_preferences.json',
        ].join(Platform.pathSeparator),
      );
      if (!await datei.exists()) return null;
      final inhalt = jsonDecode(await datei.readAsString());
      if (inhalt is! Map) return null;
      final wert = inhalt['flutter.$_prefsKeyBackupDir'];
      return wert is String && wert.trim().isNotEmpty ? wert.trim() : null;
    } catch (_) {
      return null;
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
    final test = ordnerFuerTests;
    if (test != null) {
      await test.create(recursive: true);
      return test;
    }
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

  /// Speichert ein Komplett-Backup: alles in einer Datei, auch die
  /// angehängten Dateien der Produktentwicklung — zum Umziehen auf einen
  /// anderen Rechner.
  ///
  /// Zeigt einen "Speichern unter"-Dialog, damit der Nutzer den Speicherort
  /// selbst wählen kann. Returns: Pfad zur erstellten Backup-Datei oder null,
  /// wenn der Dialog abgebrochen wurde.
  static Future<String?> exportBackup(AppDatabase database) async {
    try {
      final now = DateTime.now();
      final timeStamp = DateFormat('yyyy-MM-dd_HHmmss').format(now);
      final defaultFilename =
          '${_komplettFilePrefix}_$timeStamp.$_backupFileExtension';

      // "Speichern unter"-Dialog anzeigen.
      final outputPath = await FilePicker.saveFile(
        dialogTitle: 'Komplett-Backup speichern unter…',
        fileName: defaultFilename,
        type: FileType.any,
      );

      if (outputPath == null) return null; // Nutzer hat abgebrochen.

      final backupData = await _buildBackupPayload(database, isAuto: false);
      await _schreibeGepackt(File(outputPath), backupData);
      return outputPath;
    } catch (e) {
      throw Exception('Backup-Export fehlgeschlagen: ${fehlerText(e)}');
    }
  }

  /// Erstellt ein automatisches Backup (mit Timestamp-Präfix) im
  /// vorgegebenen Backup-Verzeichnis. Keine User-Interaktion.
  static Future<String> createAutoBackup(AppDatabase database) async {
    try {
      final backupDir = await _getBackupDir();
      // Vor dem Lesen: Was danach noch geändert wird, gilt als nicht
      // gesichert.
      final stand = await _aenderungenBisher(database);

      final now = DateTime.now();
      final timeStamp = DateFormat('yyyy-MM-dd_HHmmss').format(now);
      final filename =
          '${_autoBackupFilePrefix}_$timeStamp.$_backupFileExtension';
      final filepath = '${backupDir.path}/$filename';

      final backupData = await _buildBackupPayload(
        database,
        isAuto: true,
        ablage: DateiAblage.neben(backupDir),
      );
      await _schreibeGepackt(File(filepath), backupData);
      if (stand != null) _standBeimBackup[database] = stand;

      return filepath;
    } catch (e) {
      throw Exception('Auto-Backup fehlgeschlagen: ${fehlerText(e)}');
    }
  }

  // ── Was seit dem letzten Backup geändert wurde ───────────────────────

  /// Je Datenbank: die Zahl der Änderungen, als ihr letztes Auto-Backup in
  /// diesem Programmlauf begann.
  static final Expando<int> _standBeimBackup =
      Expando<int>('Änderungen beim letzten Backup');

  /// Wie viele Zeilen diese Verbindung seit dem Öffnen geändert hat —
  /// null, wenn sich das nicht ermitteln lässt.
  static Future<int?> _aenderungenBisher(AppDatabase db) async {
    try {
      final zeile = await db
          .customSelect('SELECT total_changes() AS anzahl')
          .getSingle();
      return zeile.read<int>('anzahl');
    } catch (_) {
      return null;
    }
  }

  /// Wurde seit dem letzten Auto-Backup dieses Programmlaufs etwas
  /// geändert? Ohne ein solches Backup: ja — dann sichert das Beenden in
  /// jedem Fall, wie bisher.
  static Future<bool> hatAenderungenSeitLetztemBackup(AppDatabase db) async {
    final stand = _standBeimBackup[db];
    if (stand == null) return true;
    final jetzt = await _aenderungenBisher(db);
    return jetzt == null || jetzt != stand;
  }

  // ── Packen und sicher schreiben ──────────────────────────────────────

  /// Packt [daten] und schreibt sie sicher nach [ziel].
  static Future<void> _schreibeGepackt(
    File ziel,
    Map<String, dynamic> daten,
  ) async =>
      _schreibeSicher(ziel, await _packe(daten));

  /// Wandelt das Backup in gepacktes JSON — auf einem eigenen Isolate.
  ///
  /// Bei vollen Stammdaten sind das mehrere Megabyte. `jsonEncode` und das
  /// Packen sind reine Rechenarbeit und blockierten sonst den UI-Thread:
  /// Das Fenster fröre ein, beim Beenden hakte die App sichtbar.
  ///
  /// Der Fallback ist Absicht: Sollte `Isolate.run` auf einer Plattform
  /// nicht verfügbar sein oder das Payload wider Erwarten etwas
  /// Nicht-Sendbares enthalten, wird ganz normal im Hauptisolate gepackt.
  /// Lieber kurz ruckeln als gar kein Backup.
  static Future<List<int>> _packe(Map<String, dynamic> daten) async {
    try {
      return await Isolate.run(() => _packeHier(daten));
    } catch (_) {
      return _packeHier(daten);
    }
  }

  static List<int> _packeHier(Map<String, dynamic> daten) =>
      gzip.encode(utf8.encode(jsonEncode(daten)));

  /// Schreibt [bytes] erst in eine Zwischendatei und benennt sie dann um
  /// — bricht das Schreiben ab (etwa weil die App beim Beenden nicht mehr
  /// wartet), liegt keine halbe Sicherung unter dem richtigen Namen.
  static Future<void> _schreibeSicher(File ziel, List<int> bytes) async {
    final zwischen = File('${ziel.path}$_zwischenEndung');
    await zwischen.writeAsBytes(bytes, flush: true);
    try {
      await zwischen.rename(ziel.path);
    } on FileSystemException {
      // Unter Windows scheitert das Umbenennen auf eine vorhandene Datei —
      // etwa, wenn ein Export eine ältere überschreiben soll.
      if (!await ziel.exists()) rethrow;
      await ziel.delete();
      await zwischen.rename(ziel.path);
    }
  }

  /// Ist [bytes] gepackt (gzip)? Ältere Backups sind reines JSON.
  static bool _istGepackt(List<int> bytes) =>
      bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;

  /// Liest ein Backup — gepackt oder nicht — auf einem eigenen Isolate:
  /// Auch große Dateien lassen das Fenster nicht stehen.
  static Future<Map<String, dynamic>> _leseBackup(File datei) async {
    final bytes = await datei.readAsBytes();
    return Isolate.run(() => _entpacke(bytes));
  }

  static Map<String, dynamic> _entpacke(Uint8List bytes) {
    final roh = _istGepackt(bytes) ? gzip.decode(bytes) : bytes;
    final json = jsonDecode(utf8.decode(roh));
    if (json is! Map<String, dynamic>) {
      throw const FormatException(
        'Die Datei ist kein gültiges Backup (erwartet wird ein '
        'JSON-Objekt).',
      );
    }
    return json;
  }

  /// Schreibt den aktuellen Stand als Sicherung vor einem Restore.
  static Future<String> _schreibeSicherungVorRestore(
    AppDatabase database,
  ) async {
    final backupDir = await _getBackupDir();
    final timeStamp = DateFormat('yyyy-MM-dd_HHmmss').format(DateTime.now());
    final filepath = '${backupDir.path}/'
        '${_preRestoreFilePrefix}_$timeStamp.$_backupFileExtension';
    // isAuto: false — die Datei soll die Rotation überleben. Die Dateien
    // der Produktentwicklung liegen in der Ablage daneben.
    final daten = await _buildBackupPayload(
      database,
      isAuto: false,
      ablage: DateiAblage.neben(backupDir),
    );
    await _schreibeGepackt(File(filepath), daten);
    return filepath;
  }

  /// Der Inhalt eines Backups — für Tests, die ihn prüfen, ohne eine
  /// Datei zu schreiben. Ohne [ablage] wie ein Komplett-Backup.
  @visibleForTesting
  static Future<Map<String, dynamic>> backupInhalt(
    AppDatabase database, {
    DateiAblage? ablage,
  }) =>
      _buildBackupPayload(database, isAuto: false, ablage: ablage);

  /// Baut das Backup-Payload zusammen. Zentrale Stelle damit
  /// `exportBackup` und `createAutoBackup` immer das gleiche Schema
  /// liefern. Mit [ablage] stehen die Dateien der Produktentwicklung dort
  /// statt im Backup.
  static Future<Map<String, dynamic>> _buildBackupPayload(
    AppDatabase database, {
    required bool isAuto,
    DateiAblage? ablage,
  }) async {
    final now = DateTime.now();
    final entwicklung =
        await EntwicklungSicherung.exportieren(database, ablage: ablage);
    final fotos = await FotoSicherung.exportieren(database, ablage: ablage);
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
        // (Die Navision-Umrechnungsfaktoren gibt es nicht mehr; ältere
        // Backups mit „navision_umrechnungen" lassen sich weiter einspielen,
        // der Abschnitt wird übergangen.)
        'demands': await _exportDemands(database),
        'production_history': await _exportProductionHistory(database),
        'week_snapshots': await _exportWeekSnapshots(database),
        // ── ab Backup-Version 1.5 ────────────────────────────────────
        'tagesaufgaben': await _exportTagesaufgaben(database),
        // ── ab Backup-Version 1.7 ────────────────────────────────────
        // Die Fotos zum Artikel — nur, wenn es welche gibt. Mit Ablage
        // stehen die Bilder dort (FotoSicherung).
        ...fotos,
        // ── ab Backup-Version 1.8 ────────────────────────────────────
        // Der eingelesene Auftragsbestand samt dem Stand davor — damit er
        // nach dem Wiederherstellen zu Board und Bedarf passt.
        ...await AuftragsbestandSicherung.exportieren(database),
        // ── Produktentwicklung ───────────────────────────────────────
        // Ein eigener, verschlüsselter Teil — nur, wenn auf diesem
        // Rechner etwas dafür eingerichtet ist. Ältere App-Stände
        // übergehen ihn (EntwicklungSicherung).
        if (entwicklung != null) 'entwicklung': entwicklung,
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
    final EntwicklungsTeil entwicklung;
    final FotoTeil fotos;
    try {
      final file = File(filepath);
      if (!await file.exists()) {
        throw Exception('Backup-Datei nicht gefunden: $filepath');
      }

      // Gepackt oder nicht, auf einem eigenen Isolate gelesen.
      final backupJson = await _leseBackup(file);

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

      // Die Produktentwicklung: prüfen und, wenn der Schlüssel dieses
      // Rechners passt, schon entschlüsseln. Ist ihr Teil beschädigt oder
      // fehlen Dateien, bricht das Einspielen hier ab — bevor etwas
      // gelöscht ist. Die Dateien eines Auto-Backups kommen vorher aus der
      // Ablage zurück.
      try {
        var teil = data['entwicklung'];
        if (teil is Map<String, dynamic> &&
            teil.containsKey('dateiVerweise')) {
          teil = await _dateienZurueckholen(teil, file, database);
        }
        entwicklung = await EntwicklungSicherung.vorbereiten(database, teil);
      } on FormatException catch (e) {
        throw Exception(
          'Der Teil der Produktentwicklung ist beschädigt (${e.message}).',
        );
      }

      // Die Fotos der Artikel: Die Bilder eines Auto-Backups kommen aus
      // der Ablage zurück. Fehlt eins, bricht das Einspielen hier ab.
      try {
        fotos = await FotoSicherung.vorbereiten(
          data,
          ablagen: await _ablagenZu(file),
          db: database,
        );
      } on FormatException catch (e) {
        throw Exception(e.message);
      }
    } catch (e) {
      throw Exception('Backup-Import fehlgeschlagen: ${fehlerText(e)}');
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
          'Der aktuelle Stand konnte nicht gesichert werden '
          '(${fehlerText(e)}). '
          'Das Wiederherstellen wurde NICHT ausgeführt — deine Daten sind '
          'unverändert. Bitte zuerst den Backup-Ordner prüfen.',
        );
      }
    }

    // ── Schritt 3: Transaktional einspielen ───────────────────────────
    //
    // Die Produktentwicklung hat einen eigenen Teil. Fehlt er — etwa im
    // Backup eines Kollegen oder in einem älteren —, bleibt der Stand
    // dieses Rechners erhalten: Ihre Tabellen leert [_clearDatabase] nicht,
    // und ihre Einstellungen kommen nach dem Leeren zurück.
    final entwicklungBisher = await EntwicklungSicherung.einstellungen(
      database,
    );
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
        await _importTagesaufgaben(database, data);
        await FotoSicherung.einspielen(
          database,
          fotos,
          ersetzen: clearExisting,
        );
        await AuftragsbestandSicherung.einspielen(
          database,
          data,
          ersetzen: clearExisting,
        );
        await _importAppSettings(database, data);
        await EntwicklungSicherung.einspielen(
          database,
          entwicklung,
          entwicklungBisher,
        );
      });
    } catch (e) {
      throw Exception('Backup-Import fehlgeschlagen: ${fehlerText(e)}');
    }
  }

  /// Holt die Dateien zum Entwicklungsteil [teil] eines Auto-Backups
  /// zurück und gibt den Teil so zurück, wie ein Komplett-Backup ihn trägt.
  ///
  /// Gesucht wird in der Ablage neben [backupDatei], dann in der neben dem
  /// eingestellten Backup-Ordner, zuletzt in der Datenbank dieses Rechners
  /// (derselbe Inhalt unter derselben ID). Fehlt etwas, wird nichts
  /// eingespielt — sonst stünden die Dateien danach ohne Inhalt da.
  static Future<Map<String, dynamic>> _dateienZurueckholen(
    Map<String, dynamic> teil,
    File backupDatei,
    AppDatabase db,
  ) async {
    final roh = teil['dateiVerweise'];
    if (roh is! Map<String, dynamic>) {
      throw const FormatException('Die Verweise auf die Dateien fehlen.');
    }
    final verweise = <String, String>{
      for (final MapEntry(:key, :value) in roh.entries)
        if (value is String) key: value,
    };
    final aufgeloest = await DateiAblage.aufloesen(
      verweise,
      ablagen: await _ablagenZu(backupDatei),
      db: db,
    );
    final fehlen = aufgeloest.fehlen.length;
    if (fehlen > 0) {
      throw Exception(
        'Dem Backup fehlen $fehlen '
        '${fehlen == 1 ? 'angehängte Datei' : 'angehängte Dateien'} der '
        'Produktentwicklung — sie liegen im Ordner '
        '„${DateiAblage.ordnerName}" neben den Backups. Für einen anderen '
        'Rechner das Komplett-Backup nehmen oder den Ordner mitkopieren. '
        'Es wurde nichts verändert.',
      );
    }
    return {
      for (final MapEntry(:key, :value) in teil.entries)
        if (key != 'dateiVerweise') key: value,
      'dateien': {
        for (final MapEntry(:key, :value) in aufgeloest.dateien.entries)
          key: base64Encode(value),
      },
    };
  }

  /// Wo die Inhalte zu [backupDatei] liegen können: in der Ablage neben
  /// ihr, dann in der neben dem eingestellten Backup-Ordner.
  static Future<List<DateiAblage>> _ablagenZu(File backupDatei) async {
    final ordner = <String>{backupDatei.absolute.parent.path};
    try {
      ordner.add((await _getBackupDir()).absolute.path);
    } catch (_) {
      // Ohne eingestellten Ordner bleibt die Ablage neben der Datei.
    }
    return [for (final o in ordner) DateiAblage.neben(Directory(o))];
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
      throw Exception(
        'Die Backups ließen sich nicht auflisten: ${fehlerText(e)}',
      );
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

  /// Liest nur die ersten Bytes der Datei und zieht die Version heraus —
  /// bei einer gepackten Datei aus ihrem entpackten Anfang.
  static Future<String?> _versionAusKopf(File file, int laenge) async {
    try {
      final ende = laenge < 2048 ? laenge : 2048;
      if (ende <= 0) return null;
      final bytes =
          await file.openRead(0, ende).expand((teil) => teil).toList();
      final kopf = utf8.decode(
        _istGepackt(bytes) ? _anfangEntpackt(bytes) : bytes,
        allowMalformed: true,
      );
      return _versionMuster.firstMatch(kopf)?.group(1);
    } catch (_) {
      return null;
    }
  }

  /// Entpackt den Anfang einer gepackten Datei, so weit [anfang] reicht —
  /// ohne den Rest zu lesen.
  static List<int> _anfangEntpackt(List<int> anfang) {
    final sammler = _Sammler();
    gzip.decoder.startChunkedConversion(sammler).add(anfang);
    return sammler.bytes;
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
    final json = await _leseBackup(file);

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
      throw Exception('Das Backup ließ sich nicht löschen: ${fehlerText(e)}');
    }
  }

  // ── Aufbewahren ──────────────────────────────────────────────────────
  //
  // Gestaffelt: die letzten zehn Auto-Backups, dazu für die letzten sieben
  // Tage je Tag das letzte und für die letzten vier Wochen je Woche das
  // letzte. Höchstens 21 Dateien — und doch ein Rückweg von vier Wochen,
  // um einen Fehler zu bemerken, bevor der letzte gute Stand herausfällt.
  // Manuelle Exporte und die Sicherung vor einem Restore bleiben immer.

  /// So viele der neuesten Auto-Backups bleiben immer.
  static const int _letzteBehalten = 10;

  /// Für so viele Tage bleibt je Tag das letzte Auto-Backup.
  static const int _tageBehalten = 7;

  /// Für so viele Wochen bleibt je Woche das letzte.
  static const int _wochenBehalten = 4;

  /// Die Pfade der Auto-Backups aus [autos], die bleiben — Stand [jetzt].
  @visibleForTesting
  static Set<String> behalteneBackups(List<BackupInfo> autos, DateTime jetzt) {
    final sortiert = [...autos]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final behalten = {
      for (final b in sortiert.take(_letzteBehalten)) b.filepath,
    };
    // Das letzte Backup im Zeitraum [von, bis).
    void letztesIn(DateTime von, DateTime bis) {
      for (final b in sortiert) {
        if (b.timestamp.isBefore(bis) && !b.timestamp.isBefore(von)) {
          behalten.add(b.filepath);
          return;
        }
      }
    }

    final heute = DateTime(jetzt.year, jetzt.month, jetzt.day);
    for (var i = 0; i < _tageBehalten; i++) {
      letztesIn(
        DateTime(heute.year, heute.month, heute.day - i),
        DateTime(heute.year, heute.month, heute.day - i + 1),
      );
    }
    final montag =
        DateTime(heute.year, heute.month, heute.day - (heute.weekday - 1));
    for (var i = 0; i < _wochenBehalten; i++) {
      letztesIn(
        DateTime(montag.year, montag.month, montag.day - 7 * i),
        DateTime(montag.year, montag.month, montag.day - 7 * i + 7),
      );
    }
    return behalten;
  }

  /// Räumt alte Auto-Backups auf (siehe [behalteneBackups]) und löscht
  /// Zwischendateien, die ein abgebrochenes Schreiben hinterlassen hat.
  /// Läuft nach jedem Auto-Backup und beim Beenden.
  static Future<void> cleanupOldAutoBackups({DateTime? jetzt}) async {
    final zeit = jetzt ?? DateTime.now();
    try {
      final all = await listBackups();
      // Nur automatische Backups rotieren — manuell exportierte Sicherungen
      // sind bewusste Momentaufnahmen und bleiben erhalten.
      final autos = all.where((b) => b.isAuto).toList();
      final behalten = behalteneBackups(autos, zeit);
      for (final b in autos) {
        if (!behalten.contains(b.filepath)) await deleteBackup(b.filepath);
      }
    } catch (_) {
      // Cleanup ist Best-Effort, nicht kritisch
    }
    try {
      final ordner = await _getBackupDir();
      await for (final e in ordner.list()) {
        if (e is! File ||
            !e.path.endsWith('.$_backupFileExtension$_zwischenEndung')) {
          continue;
        }
        if (zeit.difference(await e.lastModified()) > const Duration(days: 1)) {
          await e.delete();
        }
      }
    } catch (_) {
      // Beim nächsten Mal.
    }
  }

  /// Räumt die Ablage der Dateien auf — höchstens einmal am Tag: Was kein
  /// Backup im Ordner mehr nennt, fällt weg (siehe [DateiAblage.aufraeumen]).
  /// Lässt sich ein Backup nicht lesen, bleibt alles liegen — lieber eine
  /// Datei zu viel als eine, die einem Backup fehlt.
  static Future<void> dateienAufraeumen({DateTime? jetzt}) async {
    final zeit = jetzt ?? DateTime.now();
    try {
      final ordner = await _getBackupDir();
      final ablage = DateiAblage.neben(ordner);
      if (!await ablage.ordner.exists()) return;
      final merker = File(
        '${ablage.ordner.path}${Platform.pathSeparator}.aufgeraeumt',
      );
      final tag = DateFormat('yyyy-MM-dd').format(zeit);
      if (await merker.exists() && (await merker.readAsString()) == tag) {
        return;
      }
      final gebraucht = <String>{};
      await for (final e in ordner.list()) {
        if (e is! File || !e.path.endsWith('.$_backupFileExtension')) {
          continue;
        }
        // Erst ab 1.6 stehen Verweise in einem Backup.
        final version = await _versionAusKopf(e, await e.length());
        if (version != null && vergleicheVersion(version, '1.6') < 0) {
          continue;
        }
        final bytes = await e.readAsBytes();
        gebraucht.addAll(await Isolate.run(() => _verweiseIn(bytes)));
      }
      await ablage.aufraeumen(gebraucht, jetzt: zeit);
      await merker.writeAsString(tag);
    } catch (_) {
      // Aufräumen ist Best-Effort — beim nächsten Mal.
    }
  }

  /// Die Prüfsummen, die das Backup [bytes] nennt.
  static Set<String> _verweiseIn(Uint8List bytes) {
    final json = _entpacke(bytes);
    final daten = json['data'];
    if (daten is! Map<String, dynamic>) return const {};
    final teil = daten['entwicklung'];
    final verweise =
        teil is Map<String, dynamic> ? teil['dateiVerweise'] : null;
    return {
      ...FotoSicherung.verweiseIn(daten),
      if (verweise is Map<String, dynamic>)
        for (final v in verweise.values)
          if (v is String) v,
    };
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

  /// Die Einstellungen ohne die der Produktentwicklung — die stehen in
  /// ihrem eigenen Teil (EntwicklungSicherung).
  static Future<List<Map<String, dynamic>>> _exportAppSettings(
    AppDatabase db,
  ) async =>
      (await db.select(db.appSettings).get())
          .where((s) => !istEntwicklungsSchluessel(s.key))
          .map((s) => s.toJson())
          .toList();

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

  // ── Backup-Version 1.4: Bedarf, Historie, Wochen-Snapshots ─────────

  /// Offener Bedarf (u.a. Planungsaufträge aus dem Auftragsbestand).
  /// Wurde früher NICHT gesichert — ein Restore hat ihn stillschweigend
  /// verloren.
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

  // ── Backup-Version 1.5: Tagesaufgaben ──────────────────────────────

  /// Sonstige Aufgaben je Abteilung und Tag (Wochenboard).
  static Future<List<Map<String, dynamic>>> _exportTagesaufgaben(
    AppDatabase db,
  ) async =>
      (await db.select(db.tagesaufgaben).get())
          .map((a) => a.toJson())
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
    // Die Produktentwicklung kommt nur über ihren eigenen Teil herein
    // (EntwicklungSicherung) — nie über die allgemeinen Einstellungen.
    final eintraege = zeilen
        .map(AppSetting.fromJson)
        .where((s) => !istEntwicklungsSchluessel(s.key))
        .map((s) => s.toCompanion(true))
        .toList();
    if (eintraege.isEmpty) return;
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

  // ── Backup-Version 1.5: Tagesaufgaben ──────────────────────────────
  // Ältere Backups kennen den Schlüssel nicht — dann bleibt die Liste
  // leer.

  static Future<void> _importTagesaufgaben(
    AppDatabase db,
    Map<String, dynamic> data,
  ) async {
    final zeilen = _zeilen(data, 'tagesaufgaben');
    if (zeilen.isEmpty) return;
    final eintraege = zeilen
        .map((z) => Tagesaufgabe.fromJson(z).toCompanion(true))
        .toList();
    await db.batch(
      (b) => b.insertAllOnConflictUpdate(db.tagesaufgaben, eintraege),
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
    await db.delete(db.zusatzzeiten).go();
    await db.delete(db.machineParameterDefs).go();
    await db.delete(db.parameterGrenzen).go();
    // Anlagen-Katalog
    await db.delete(db.machines).go();
    // Wochen-Snapshots und Tagesaufgaben (eigenständig, keine FK).
    await db.delete(db.weekSnapshots).go();
    await db.delete(db.tagesaufgaben).go();
    // Die Fotos der Artikel leert FotoSicherung.einspielen — dort bleiben
    // die Bilder stehen, die das Backup genau so wieder mitbringt.
    // Den Auftragsbestand leert AuftragsbestandSicherung.einspielen — aber
    // nur, wenn das Backup ihn enthält (ab 1.8).
    // App-Settings (importierte Excel-Datei wird mit-restauriert)
    await db.delete(db.appSettings).go();
  }
}

/// Vergleicht zwei Backup-Versionen wie „1.4" und „1.10" Stelle für
/// Stelle: negativ, wenn [a] älter ist, 0 bei gleicher, sonst positiv.
/// Was keine Zahl ist, zählt als 0.
int vergleicheVersion(String a, String b) {
  final x = a.split('.');
  final y = b.split('.');
  for (var i = 0; i < x.length || i < y.length; i++) {
    final m = i < x.length ? int.tryParse(x[i]) ?? 0 : 0;
    final n = i < y.length ? int.tryParse(y[i]) ?? 0 : 0;
    if (m != n) return m.compareTo(n);
  }
  return 0;
}

/// Nimmt auf, was ein entpackter Anfang hergibt — für den Kopf eines
/// gepackten Backups.
class _Sammler implements Sink<List<int>> {
  final List<int> bytes = [];

  @override
  void add(List<int> data) => bytes.addAll(data);

  @override
  void close() {}
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
      return '${Format.zahl(sizeBytes / 1024, nachkomma: 1)} KB';
    }
    return '${Format.zahl(sizeBytes / (1024 * 1024), nachkomma: 1)} MB';
  }

  /// Zeitstempel im deutschen Format.
  String get formattedTimestamp =>
      DateFormat('dd.MM.yyyy HH:mm').format(timestamp);

  /// Stammt das Backup aus einer Version VOR 1.4?
  ///
  /// Solche Sicherungen enthalten weder Bedarfsliste noch Produktions-
  /// historie noch Wochen-Snapshots — diese Tabellen wurden damals nicht
  /// mitgeschrieben. Beim Wiederherstellen sind sie danach leer, ohne dass
  /// irgendetwas kaputt wäre. Genau das sollte man vorher wissen.
  bool get istAeltereVersion => vergleicheVersion(version, '1.4') < 0;

  /// Was in einem älteren Backup fehlt — null bei aktueller Version.
  String? get versionsHinweis => istAeltereVersion
      ? 'Älteres Format: Bedarf, Historie und Wochen-Snapshots fehlen '
          'möglicherweise.'
      : null;
}




