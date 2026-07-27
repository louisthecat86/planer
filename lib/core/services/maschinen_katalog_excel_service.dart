import 'dart:io';

import 'package:drift/drift.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../constants/abteilungen.dart';
import '../database/database.dart';

/// Ergebnis eines Katalog-Imports.
class KatalogImportErgebnis {
  const KatalogImportErgebnis({
    required this.anlagenNeu,
    required this.anlagenAktualisiert,
    required this.parameterNeu,
    required this.parameterAktualisiert,
    required this.warnungen,
  });

  final int anlagenNeu;
  final int anlagenAktualisiert;
  final int parameterNeu;
  final int parameterAktualisiert;
  final List<String> warnungen;

  int get anlagenGesamt => anlagenNeu + anlagenAktualisiert;
  int get parameterGesamt => parameterNeu + parameterAktualisiert;
}

/// Exportiert und importiert den Maschinen-Katalog als eigenständige
/// Excel-Datei.
///
/// Bewusst getrennt vom JSON-Gesamtbackup: Der Katalog ist der Teil der
/// Stammdaten, den man auch mal außerhalb der App bearbeiten, weitergeben
/// oder auf einem zweiten Rechner einspielen möchte. Excel ist dafür das
/// Format, mit dem im Betrieb ohnehin gearbeitet wird.
///
/// Aufbau der Datei — zwei Blätter:
///   * **Anlagen**   — je Zeile eine Maschine (Name ist der Schlüssel)
///   * **Parameter** — je Zeile ein Steckbrief-Feld, zugeordnet über den
///     Anlagen-Namen
class MaschinenKatalogExcelService {
  MaschinenKatalogExcelService._();

  static const String _sheetAnlagen = 'Anlagen';
  static const String _sheetParameter = 'Parameter';

  static const List<String> _kopfAnlagen = [
    'Name',
    'Abteilung',
    'Typische Parameter',
    'Eigene Planungsspur',
    'Kapazität (Minuten/Tag)',
    'Eignungshinweis',
  ];

  static const List<String> _kopfParameter = [
    'Anlage',
    'Parameter',
    'Einheit',
    'Sortierung',
  ];

  // ══════════════════════════════════════════════════════════════════
  // Export
  // ══════════════════════════════════════════════════════════════════

  /// Schreibt den kompletten Katalog in eine .xlsx und lässt den Nutzer
  /// den Speicherort wählen. Gibt den Pfad zurück (null = abgebrochen).
  static Future<String?> exportiere(AppDatabase db) async {
    final anlagen = await (db.select(db.machines)
          ..where((m) => m.deletedAt.isNull())
          ..orderBy([
            (m) => OrderingTerm.asc(m.abteilung),
            (m) => OrderingTerm.asc(m.name),
          ]))
        .get();
    final defs = await (db.select(db.machineParameterDefs)
          ..where((d) => d.deletedAt.isNull())
          ..orderBy([
            (d) => OrderingTerm.asc(d.sortierung),
            (d) => OrderingTerm.asc(d.parameterName),
          ]))
        .get();
    final nameVonId = {for (final m in anlagen) m.id: m.name};

    final excel = Excel.createExcel();

    // -- Blatt „Anlagen" ------------------------------------------------
    final sa = excel[_sheetAnlagen];
    sa.appendRow([for (final t in _kopfAnlagen) TextCellValue(t)]);
    for (final m in anlagen) {
      sa.appendRow([
        TextCellValue(m.name),
        TextCellValue(_abteilungsName(m.abteilung)),
        TextCellValue(m.typischeParameter ?? ''),
        TextCellValue(m.istPlanungsressource ? 'ja' : 'nein'),
        DoubleCellValue(m.kapazitaetMinutenProTag),
        TextCellValue(m.eignungHinweis ?? ''),
      ]);
    }

    // -- Blatt „Parameter" ----------------------------------------------
    final sp = excel[_sheetParameter];
    sp.appendRow([for (final t in _kopfParameter) TextCellValue(t)]);
    for (final d in defs) {
      final anlage = nameVonId[d.maschineId];
      if (anlage == null) continue; // verwaiste Zeile
      sp.appendRow([
        TextCellValue(anlage),
        TextCellValue(d.parameterName),
        TextCellValue(d.einheit ?? ''),
        IntCellValue(d.sortierung),
      ]);
    }

    // Standard-Blatt entfernen, falls die Bibliothek eines angelegt hat.
    try {
      excel.delete('Sheet1');
    } catch (_) {
      // Nicht kritisch.
    }

    final bytes = excel.encode();
    if (bytes == null) return null;

    final ziel = await FilePicker.saveFile(
      dialogTitle: 'Maschinen-Katalog speichern …',
      fileName: 'maschinen_katalog.xlsx',
      type: FileType.any,
    );
    if (ziel == null) return null;

    final pfad = ziel.endsWith('.xlsx') ? ziel : '$ziel.xlsx';
    File(pfad).writeAsBytesSync(bytes);
    debugPrint(
      '[KATALOG] exportiert: ${anlagen.length} Anlagen, '
      '${defs.length} Parameter → $pfad',
    );
    return pfad;
  }

  // ══════════════════════════════════════════════════════════════════
  // Import
  // ══════════════════════════════════════════════════════════════════

  /// Liest einen Katalog aus den Bytes einer .xlsx.
  ///
  /// Bewusst NICHT löschend: Anlagen werden über ihren Namen abgeglichen,
  /// Parameter über Anlage + Parametername. Vorhandenes wird aktualisiert,
  /// Unbekanntes angelegt — nichts, was nur in der App existiert, geht
  /// dabei verloren.
  static Future<KatalogImportErgebnis> importiere(
    AppDatabase db,
    Uint8List bytes,
  ) async {
    if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
      throw Exception(
        'Das ist keine echte Excel-Datei (.xlsx). Bitte die vom Katalog-'
        'Export erzeugte Datei wählen.',
      );
    }

    final Excel excel;
    try {
      excel = Excel.decodeBytes(bytes);
    } catch (e) {
      throw Exception('Die Datei ließ sich nicht als Excel öffnen: $e');
    }

    final warnungen = <String>[];
    final blattAnlagen = _findeBlatt(excel, _sheetAnlagen);
    if (blattAnlagen == null) {
      throw Exception(
        'Kein Blatt „$_sheetAnlagen" gefunden. Erwartet wird eine Datei, '
        'wie sie der Katalog-Export erzeugt.',
      );
    }

    var anlagenNeu = 0;
    var anlagenAktualisiert = 0;
    var parameterNeu = 0;
    var parameterAktualisiert = 0;

    // Bestehende Anlagen (auch soft-deleted: der Name ist unique und
    // bliebe sonst blockiert).
    final vorhandene = await db.select(db.machines).get();
    final idVonName = <String, String>{
      for (final m in vorhandene) m.name.trim().toLowerCase(): m.id,
    };

    final jetzt = DateTime.now();

    // -- Anlagen ---------------------------------------------------------
    final aSpalten = _spaltenIndex(blattAnlagen, _kopfAnlagen);
    for (var r = 1; r < blattAnlagen.rows.length; r++) {
      final zeile = blattAnlagen.rows[r];
      final name = _text(zeile, aSpalten['Name']);
      if (name == null || name.isEmpty) continue;

      final abteilungText = _text(zeile, aSpalten['Abteilung']);
      final abteilung = _abteilungDbValue(abteilungText);
      if (abteilung == null) {
        warnungen.add(
          'Anlage „$name": Abteilung „${abteilungText ?? ''}" ist unbekannt '
          '— Zeile übersprungen.',
        );
        continue;
      }

      final typisch = _text(zeile, aSpalten['Typische Parameter']);
      final hinweis = _text(zeile, aSpalten['Eignungshinweis']);
      final spur = _jaNein(_text(zeile, aSpalten['Eigene Planungsspur']));
      final kapazitaet =
          _zahl(_text(zeile, aSpalten['Kapazität (Minuten/Tag)']));

      final vorhandenId = idVonName[name.trim().toLowerCase()];
      if (vorhandenId != null) {
        await (db.update(db.machines)..where((m) => m.id.equals(vorhandenId)))
            .write(
          MachinesCompanion(
            abteilung: Value(abteilung),
            typischeParameter: Value(typisch),
            eignungHinweis: Value(hinweis),
            istPlanungsressource:
                spur == null ? const Value.absent() : Value(spur),
            kapazitaetMinutenProTag: (kapazitaet != null && kapazitaet > 0)
                ? Value(kapazitaet)
                : const Value.absent(),
            // Ein Katalog-Import holt versehentlich gelöschte Anlagen
            // bewusst zurück.
            deletedAt: const Value(null),
            updatedAt: Value(jetzt),
          ),
        );
        anlagenAktualisiert++;
      } else {
        final id = const Uuid().v4();
        await db.into(db.machines).insert(
              MachinesCompanion.insert(
                id: id,
                name: name,
                abteilung: abteilung,
                typischeParameter: Value(typisch),
                eignungHinweis: Value(hinweis),
                istPlanungsressource:
                    spur == null ? const Value.absent() : Value(spur),
                kapazitaetMinutenProTag:
                    (kapazitaet != null && kapazitaet > 0)
                        ? Value(kapazitaet)
                        : const Value.absent(),
              ),
            );
        idVonName[name.trim().toLowerCase()] = id;
        anlagenNeu++;
      }
    }

    // -- Parameter -------------------------------------------------------
    final blattParameter = _findeBlatt(excel, _sheetParameter);
    if (blattParameter == null) {
      warnungen.add(
        'Kein Blatt „$_sheetParameter" — es wurden nur die Anlagen '
        'eingelesen.',
      );
    } else {
      final pSpalten = _spaltenIndex(blattParameter, _kopfParameter);
      final defs = await db.select(db.machineParameterDefs).get();
      String schluessel(String mid, String pname) =>
          '$mid|${pname.trim().toLowerCase()}';
      final defVonSchluessel = {
        for (final d in defs) schluessel(d.maschineId, d.parameterName): d.id,
      };

      for (var r = 1; r < blattParameter.rows.length; r++) {
        final zeile = blattParameter.rows[r];
        final anlage = _text(zeile, pSpalten['Anlage']);
        final pname = _text(zeile, pSpalten['Parameter']);
        if (anlage == null || anlage.isEmpty) continue;
        if (pname == null || pname.isEmpty) continue;

        final mid = idVonName[anlage.trim().toLowerCase()];
        if (mid == null) {
          warnungen.add(
            'Parameter „$pname": Anlage „$anlage" gibt es nicht — '
            'Zeile übersprungen.',
          );
          continue;
        }

        final einheit = _text(zeile, pSpalten['Einheit']);
        final sortierung =
            _zahl(_text(zeile, pSpalten['Sortierung']))?.round() ?? 0;

        final vorhandenId = defVonSchluessel[schluessel(mid, pname)];
        if (vorhandenId != null) {
          await (db.update(db.machineParameterDefs)
                ..where((d) => d.id.equals(vorhandenId)))
              .write(
            MachineParameterDefsCompanion(
              einheit: Value(einheit),
              sortierung: Value(sortierung),
              deletedAt: const Value(null),
              updatedAt: Value(jetzt),
            ),
          );
          parameterAktualisiert++;
        } else {
          final id = const Uuid().v4();
          await db.into(db.machineParameterDefs).insert(
                MachineParameterDefsCompanion.insert(
                  id: id,
                  maschineId: mid,
                  parameterName: pname,
                  einheit: Value(einheit),
                  sortierung: Value(sortierung),
                ),
              );
          defVonSchluessel[schluessel(mid, pname)] = id;
          parameterNeu++;
        }
      }
    }

    debugPrint(
      '[KATALOG] Import fertig — Anlagen: +$anlagenNeu / '
      '~$anlagenAktualisiert · Parameter: +$parameterNeu / '
      '~$parameterAktualisiert · Warnungen: ${warnungen.length}',
    );

    return KatalogImportErgebnis(
      anlagenNeu: anlagenNeu,
      anlagenAktualisiert: anlagenAktualisiert,
      parameterNeu: parameterNeu,
      parameterAktualisiert: parameterAktualisiert,
      warnungen: warnungen,
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // Helfer
  // ══════════════════════════════════════════════════════════════════

  static Sheet? _findeBlatt(Excel excel, String name) {
    for (final key in excel.tables.keys) {
      if (key.trim().toLowerCase() == name.toLowerCase()) {
        return excel.tables[key];
      }
    }
    return null;
  }

  /// Spaltenüberschrift → Index. Dadurch darf der Nutzer Spalten in Excel
  /// verschieben oder zusätzliche einfügen, ohne den Import zu brechen.
  static Map<String, int> _spaltenIndex(Sheet blatt, List<String> erwartet) {
    final index = <String, int>{};
    if (blatt.rows.isEmpty) return index;
    final kopf = blatt.rows.first;
    for (var c = 0; c < kopf.length; c++) {
      final t = _zellText(kopf[c])?.trim().toLowerCase();
      if (t == null || t.isEmpty) continue;
      for (final e in erwartet) {
        if (e.toLowerCase() == t && !index.containsKey(e)) index[e] = c;
      }
    }
    // Fallback: fehlt die Kopfzeile, nach Position zuordnen.
    if (index.isEmpty) {
      for (var i = 0; i < erwartet.length; i++) {
        index[erwartet[i]] = i;
      }
    }
    return index;
  }

  static String? _zellText(Data? zelle) {
    final v = zelle?.value;
    if (v == null) return null;
    if (v is TextCellValue) return v.value.text?.trim();
    if (v is IntCellValue) return v.value.toString();
    if (v is DoubleCellValue) {
      final d = v.value;
      return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
    }
    if (v is BoolCellValue) return v.value ? 'ja' : 'nein';
    return v.toString().trim();
  }

  static String? _text(List<Data?> zeile, int? spalte) {
    if (spalte == null || spalte >= zeile.length) return null;
    final t = _zellText(zeile[spalte]);
    return (t == null || t.isEmpty) ? null : t;
  }

  static double? _zahl(String? text) {
    if (text == null || text.isEmpty) return null;
    var s = text.replaceAll(' ', '');
    if (s.contains(',') && s.contains('.')) {
      s = s.replaceAll('.', '').replaceAll(',', '.');
    } else {
      s = s.replaceAll(',', '.');
    }
    return double.tryParse(s);
  }

  static bool? _jaNein(String? text) {
    if (text == null || text.isEmpty) return null;
    final t = text.trim().toLowerCase();
    if (t == 'ja' || t == 'x' || t == 'true' || t == '1') return true;
    if (t == 'nein' || t == 'false' || t == '0') return false;
    return null;
  }

  static String _abteilungsName(String dbValue) {
    try {
      return Abteilung.fromDbValue(dbValue).anzeigeName;
    } catch (_) {
      return dbValue;
    }
  }

  /// Nimmt Klartext („Bratstraße") ebenso wie den dbValue („bratstrasse").
  static String? _abteilungDbValue(String? text) {
    if (text == null || text.isEmpty) return null;
    final t = text.trim().toLowerCase();
    for (final a in Abteilung.values) {
      if (a.anzeigeName.toLowerCase() == t || a.dbValue.toLowerCase() == t) {
        return a.dbValue;
      }
    }
    return null;
  }
}
