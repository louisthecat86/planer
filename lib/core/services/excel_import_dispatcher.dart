import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../database/database.dart';
import 'excel_import_service.dart' as legacy;
import 'excel_import_service_v3.dart';

enum VorlagenVersion {
  v3,
  legacy,
  unbekannt,
}

class UnifiedImportPreview {
  const UnifiedImportPreview({
    required this.version,
    this.artikelNeu = 0,
    this.artikelAktualisiert = 0,
    this.schritte = 0,
    this.parameter = 0,
    this.maschinen = 0,
    this.rezepturen = 0,
    this.rohwaren = 0,
    this.historien = 0,
    this.warnungen = const [],
    this.fehler = const [],
  });

  final VorlagenVersion version;
  final int artikelNeu;
  final int artikelAktualisiert;
  final int schritte;
  final int parameter;
  final int maschinen;
  final int rezepturen;
  final int rohwaren;
  final int historien;
  final List<String> warnungen;
  final List<String> fehler;

  bool get hatFehler => fehler.isNotEmpty;
  bool get istLeer =>
      artikelNeu == 0 &&
      artikelAktualisiert == 0 &&
      schritte == 0 &&
      parameter == 0 &&
      maschinen == 0 &&
      rezepturen == 0 &&
      rohwaren == 0 &&
      historien == 0;
}

class UnifiedImportResult {
  const UnifiedImportResult({
    required this.version,
    this.artikelNeu = 0,
    this.artikelAktualisiert = 0,
    this.schritteImportiert = 0,
    this.parameterImportiert = 0,
    this.maschinenImportiert = 0,
    this.rezepturenImportiert = 0,
    this.rohwarenImportiert = 0,
    this.historienVerarbeitet = 0,
    this.warnungen = const [],
    this.fehler = const [],
  });

  final VorlagenVersion version;
  final int artikelNeu;
  final int artikelAktualisiert;
  final int schritteImportiert;
  final int parameterImportiert;
  final int maschinenImportiert;
  final int rezepturenImportiert;
  final int rohwarenImportiert;
  final int historienVerarbeitet;
  final List<String> warnungen;
  final List<String> fehler;

  bool get hatFehler => fehler.isNotEmpty;
  int get artikelGesamt => artikelNeu + artikelAktualisiert;
}

class ExcelImportDispatcher {
  ExcelImportDispatcher(this._db);

  final AppDatabase _db;

  Future<VorlagenVersion> erkenneVersion(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    return _erkenneVersionFromBytes(bytes);
  }

  Set<String> _collectSheetNames(Excel excel) {
    final names = <String>{};
    try {
      names.addAll(excel.tables.keys);
    } catch (_) {}
    try {
      // ignore: avoid_dynamic_calls
      final dyn = (excel as dynamic).sheets;
      if (dyn is Map) {
        names.addAll(dyn.keys.map((k) => k.toString()));
      }
    } catch (_) {}
    return names;
  }

  VorlagenVersion _erkenneVersionFromBytes(Uint8List bytes) {
    try {
      final excel = Excel.decodeBytes(bytes);
      if (ExcelImportServiceV3.istV3Format(excel)) {
        return VorlagenVersion.v3;
      }
      final sheetNames = _collectSheetNames(excel);
      if (sheetNames.contains('Übersicht') &&
          !sheetNames.contains('Anlagen-Katalog')) {
        return VorlagenVersion.legacy;
      }
      for (final sheet in excel.tables.values) {
        for (final row in sheet.rows.take(50)) {
          for (final cell in row.take(5)) {
            final v = cell?.value;
            if (v is TextCellValue) {
              final text = v.value.text ?? '';
              if (text.contains('STAMMDATEN')) return VorlagenVersion.legacy;
            }
          }
        }
      }
      return VorlagenVersion.unbekannt;
    } catch (_) {
      return VorlagenVersion.unbekannt;
    }
  }

  /// Diagnose: Versucht die Datei zu öffnen und liefert detaillierte
  /// Informationen zurück — Dateigröße, ob decode funktioniert, welche
  /// Fehlermeldung kommt, wie viele Sheets gefunden werden.
  List<String> _diagnose(Uint8List bytes, String filePath) {
    final out = <String>[];
    out.add('DIAGNOSE: Datei-Pfad: $filePath');
    out.add('DIAGNOSE: Dateigröße: ${bytes.length} Bytes '
        '(${(bytes.length / 1024).toStringAsFixed(1)} KB)');

    // Magic bytes prüfen — .xlsx muss mit PK (ZIP-Header) starten
    if (bytes.length >= 2) {
      final b0 = bytes[0];
      final b1 = bytes[1];
      if (b0 == 0x50 && b1 == 0x4B) {
        out.add('DIAGNOSE: ZIP-Header OK (PK-Signatur gefunden)');
      } else {
        out.add('DIAGNOSE: ⚠ KEINE ZIP-Signatur — Datei ist evtl. '
            'nicht .xlsx, sondern .xls oder beschädigt. '
            'Erste Bytes: ${b0.toRadixString(16)} ${b1.toRadixString(16)}');
        return out;
      }
    }

    Excel? excel;
    try {
      excel = Excel.decodeBytes(bytes);
      out.add('DIAGNOSE: Excel.decodeBytes erfolgreich');
    } catch (e, st) {
      out.add('DIAGNOSE: ❌ Excel.decodeBytes wirft: $e');
      out.add('DIAGNOSE: Stack (erste 500 Zeichen): '
          '${st.toString().substring(0, st.toString().length > 500 ? 500 : st.toString().length)}');
      return out;
    }

    final tablesKeys = <String>[];
    try {
      tablesKeys.addAll(excel.tables.keys);
      out.add('DIAGNOSE: excel.tables.keys hat ${tablesKeys.length} Einträge: '
          '${tablesKeys.map((s) => '"$s"').join(", ")}');
    } catch (e) {
      out.add('DIAGNOSE: ❌ excel.tables wirft: $e');
    }

    try {
      // ignore: avoid_dynamic_calls
      final dyn = (excel as dynamic).sheets;
      if (dyn is Map) {
        final names = dyn.keys.map((k) => k.toString()).toList();
        out.add('DIAGNOSE: excel.sheets hat ${names.length} Einträge: '
            '${names.map((s) => '"$s"').join(", ")}');
      } else {
        out.add('DIAGNOSE: excel.sheets ist keine Map (Typ: ${dyn.runtimeType})');
      }
    } catch (e) {
      out.add('DIAGNOSE: excel.sheets nicht verfügbar: $e');
    }

    return out;
  }

  Future<UnifiedImportPreview> preview(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final version = _erkenneVersionFromBytes(bytes);

    if (version == VorlagenVersion.unbekannt) {
      return UnifiedImportPreview(
        version: VorlagenVersion.unbekannt,
        fehler: [
          'Das Format der Datei konnte nicht erkannt werden. '
              'Erwartet wird entweder die v3-Vorlage (mit Sheet "Anlagen-Katalog") '
              'oder die alte Phase-B-Vorlage (mit "== STAMMDATEN ==" Markern).',
          ..._diagnose(bytes, filePath),
        ],
      );
    }

    if (version == VorlagenVersion.v3) {
      final svc = ExcelImportServiceV3(_db);
      final p = await svc.preview(File(filePath));
      return UnifiedImportPreview(
        version: VorlagenVersion.v3,
        artikelNeu: p.artikelNeu,
        artikelAktualisiert: p.artikelAktualisiert,
        schritte: p.schritte,
        parameter: p.parameter,
        maschinen: p.maschinen,
        historien: p.historien,
        warnungen: p.warnungen,
        fehler: p.fehler,
      );
    }

    // Legacy
    final svc = legacy.ExcelImportService(_db);
    final p = await svc.preview(filePath);
    final fehler = List<String>.from(p.fehler);
    if (p.artikelNeu == 0 && p.artikelAktualisiert == 0) {
      fehler.addAll(_diagnose(bytes, filePath));
      fehler.add(
        'HINWEIS: Falls dies eine v3-Vorlage sein soll, prüfe ob das Sheet '
        '"Anlagen-Katalog" in der Diagnose oben auftaucht.',
      );
    }
    return UnifiedImportPreview(
      version: VorlagenVersion.legacy,
      artikelNeu: p.artikelNeu,
      artikelAktualisiert: p.artikelAktualisiert,
      schritte: p.schritte,
      rezepturen: p.rezepturen,
      rohwaren: p.rohwaren,
      historien: p.historien,
      warnungen: p.warnungen,
      fehler: fehler,
    );
  }

  Future<UnifiedImportResult> importFile(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final version = _erkenneVersionFromBytes(bytes);

    if (version == VorlagenVersion.unbekannt) {
      return const UnifiedImportResult(
        version: VorlagenVersion.unbekannt,
        fehler: ['Dateiformat nicht erkannt.'],
      );
    }

    if (version == VorlagenVersion.v3) {
      final svc = ExcelImportServiceV3(_db);
      final r = await svc.import(File(filePath));
      return UnifiedImportResult(
        version: VorlagenVersion.v3,
        artikelNeu: r.artikelNeu,
        artikelAktualisiert: r.artikelAktualisiert,
        schritteImportiert: r.schritteImportiert,
        parameterImportiert: r.parameterImportiert,
        maschinenImportiert: r.maschinenImportiert,
        historienVerarbeitet: r.historienVerarbeitet,
        warnungen: r.warnungen,
        fehler: r.fehler,
      );
    }

    final svc = legacy.ExcelImportService(_db);
    final r = await svc.importFile(filePath);
    return UnifiedImportResult(
      version: VorlagenVersion.legacy,
      artikelNeu: r.artikelNeu,
      artikelAktualisiert: r.artikelAktualisiert,
      schritteImportiert: r.schritteImportiert,
      rezepturenImportiert: r.rezepturenImportiert,
      rohwarenImportiert: r.rohwarenImportiert,
      historienVerarbeitet: r.historienVerarbeitet,
      warnungen: r.warnungen,
      fehler: r.fehler,
    );
  }
}