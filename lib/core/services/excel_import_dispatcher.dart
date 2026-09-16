import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../database/database.dart';
import 'excel_import_service_v3.dart';

/// Erkanntes Format einer Import-Datei.
///
/// Historisch gab es hier noch `legacy` für Vorlagen aus der Zeit vor dem
/// Anlagen-Katalog. Diese Vorlagen hat nie jemand produktiv genutzt, der
/// zugehörige Importer ist entfallen.
enum VorlagenVersion {
  v3,
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

  /// Sammelt die Blattnamen der Mappe.
  ///
  /// Zwei Wege, weil je nach Version des excel-Pakets mal `tables`, mal
  /// `sheets` gefüllt ist. Fehlt einer davon, liefert er einfach nichts.
  Set<String> _collectSheetNames(Excel excel) {
    final names = <String>{};
    try {
      names.addAll(excel.tables.keys);
    } catch (_) {
      // Kein Zugriff auf tables — dann bleibt der zweite Weg.
    }
    try {
      // ignore: avoid_dynamic_calls
      final dyn = (excel as dynamic).sheets;
      if (dyn is Map) {
        names.addAll(dyn.keys.map((k) => k.toString()));
      }
    } catch (_) {
      // sheets nicht verfügbar — tables hat dann hoffentlich gereicht.
    }
    return names;
  }

  /// Öffnet die Arbeitsmappe. null, wenn die Datei kein lesbares xlsx ist.
  ///
  /// Bewusst getrennt von der Formaterkennung: `Excel.decodeBytes` baut das
  /// komplette Zellmodell auf und ist die teuerste Operation des gesamten
  /// Imports. Vorher wurde es je Durchgang zweimal aufgerufen — einmal hier
  /// zur Formaterkennung, einmal gleich darauf im Import-Service. Ein
  /// Vorschau-plus-Import-Zyklus las die Datei also viermal ein und baute
  /// viermal dasselbe Modell auf, alles im UI-Isolate.
  Excel? _oeffne(Uint8List bytes) {
    try {
      return Excel.decodeBytes(bytes);
    } catch (_) {
      return null;
    }
  }

  VorlagenVersion _erkenneVersionFromBytes(Uint8List bytes) {
    final excel = _oeffne(bytes);
    if (excel == null) return VorlagenVersion.unbekannt;
    return ExcelImportServiceV3.istV3Format(excel)
        ? VorlagenVersion.v3
        : VorlagenVersion.unbekannt;
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
    } catch (e) {
      out.add('DIAGNOSE: ❌ Excel.decodeBytes wirft: $e');
      return out;
    }

    try {
      final namen = _collectSheetNames(excel);
      out.add('DIAGNOSE: ${namen.length} Blätter gefunden: '
          '${namen.map((s) => '"$s"').join(", ")}');
      final hatKatalog = namen.any(
        (s) => s.trim().toLowerCase() == 'anlagen-katalog',
      );
      out.add('DIAGNOSE: Blatt "Anlagen-Katalog" vorhanden: $hatKatalog');
      out.add('DIAGNOSE: istV3Format() => '
          '${ExcelImportServiceV3.istV3Format(excel)}');
    } catch (e) {
      out.add('DIAGNOSE: Blätter nicht auslesbar: $e');
    }

    return out;
  }

  /// Fehlermeldung, wenn das Format nicht erkannt wurde.
  List<String> _unbekanntFehler(Uint8List bytes, String filePath) => [
        'Das Format der Datei konnte nicht erkannt werden. Erwartet wird '
            'eine Vorlage mit den Blättern "Übersicht" und '
            '"Anlagen-Katalog" — genau das erzeugt der Excel-Export der '
            'App. Bitte dort eine frische Vorlage ziehen.',
        ..._diagnose(bytes, filePath),
      ];

  Future<UnifiedImportPreview> preview(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final mappe = _oeffne(bytes);

    if (mappe == null || !ExcelImportServiceV3.istV3Format(mappe)) {
      return UnifiedImportPreview(
        version: VorlagenVersion.unbekannt,
        fehler: _unbekanntFehler(bytes, filePath),
      );
    }

    // Die geöffnete Mappe weiterreichen statt sie erneut aufzubauen.
    final svc = ExcelImportServiceV3(_db);
    final p = await svc.preview(File(filePath), mappe: mappe);
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

  Future<UnifiedImportResult> importFile(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final mappe = _oeffne(bytes);

    if (mappe == null || !ExcelImportServiceV3.istV3Format(mappe)) {
      return UnifiedImportResult(
        version: VorlagenVersion.unbekannt,
        fehler: _unbekanntFehler(bytes, filePath),
      );
    }

    // Mappe UND Bytes weiterreichen: Die Bytes braucht der Service, um die
    // Originaldatei für den späteren Excel-Export abzulegen.
    final svc = ExcelImportServiceV3(_db);
    final r = await svc.import(File(filePath), mappe: mappe, rohBytes: bytes);
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
}



