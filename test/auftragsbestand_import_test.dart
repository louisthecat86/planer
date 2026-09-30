import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/auftragsbestand_import_service.dart';

import 'helpers/test_db.dart';

/// Tests für das Einlesen des Navision-Berichts „Auftragsbestand".
///
/// Die Testdatei wird hier im Speicher gebaut — genau so, wie Navision sie
/// schreibt: Texte direkt in der Zelle, keine `sharedStrings.xml`,
/// absolute Verweise im Paket. Ein echter Bericht gehört nicht ins
/// Repository: Er enthält Kunden und Mengen.
void main() {
  group('Bericht lesen', () {
    test('liest Kopf, Artikel und Aufträge im Navision-Format', () {
      final bericht = AuftragsbestandImportService.leseBericht(
        _mappe(_standardZeilen()),
      );

      expect(bericht.stand, DateTime(2026, 9, 30, 12, 9, 14));
      expect(bericht.von, DateTime(2026, 9, 30));
      expect(bericht.bis, DateTime(2026, 10, 30));
      expect(bericht.artikel.map((a) => a.nummer), ['12981', '13977']);

      final pute = bericht.artikel.first;
      expect(pute.bezeichnung, 'Putenfleisch in Aspik');
      expect(pute.bezeichnung2, 'geschnitten, egal. 500g Pack');
      expect(pute.lagerKg, 5);
      expect(pute.gesamtKg, 8);
      expect(pute.gesamtMenge, 16);
      expect(pute.gesamtEinheit, 'PACK');
      expect(pute.positionen, hasLength(3));

      final erste = pute.positionen.first;
      expect(erste.beleg, 'VA1');
      expect(erste.debitor, 'Kunde A', reason: 'Leerzeichen am Ende weg');
      expect(erste.warenausgang, DateTime(2026, 9, 30));
      expect(erste.lieferdatum, isNull);
      expect(erste.menge, 2);
      expect(erste.einheit, 'PACK');
      expect(erste.kg, 1);
      expect(pute.positionen[2].debitor, 'Kunde & Co');
    });

    test('liest auch eine in Excel neu gespeicherte Datei', () {
      // Excel legt beim Speichern eine sharedStrings.xml an und schreibt
      // relative Verweise. Das Ergebnis muss dasselbe sein.
      final bericht = AuftragsbestandImportService.leseBericht(
        _mappe(_standardZeilen(), wieExcel: true),
      );

      expect(bericht.artikel.map((a) => a.nummer), ['12981', '13977']);
      expect(bericht.anzahlPositionen, 4);
      expect(bericht.artikel.first.positionen[2].debitor, 'Kunde & Co');
      expect(bericht.stand, DateTime(2026, 9, 30, 12, 9, 14));
    });

    test('lässt Verpackung und Paletten aus', () {
      final bericht = AuftragsbestandImportService.leseBericht(
        _mappe(_standardZeilen()),
      );

      expect(bericht.uebersprungen, ['KT']);
      expect(bericht.anzahlKunden, 4, reason: 'Kunde C bestellt nur Kartons');
    });

    test('lehnt ab, wenn die Zeilen nicht die Gesamtsumme ergeben', () {
      // Selbstprüfung: Ein halb gelesener Bericht sähe nach vollständigen
      // Zahlen aus. Lieber gar nichts als falsche Mengen.
      final zeilen = _standardZeilen();
      zeilen[26] = {
        'B': 'Artikelnr.: ',
        'F': '12981',
        'J': 'Gesamt',
        'K': 16,
        'M': 'PACK',
        'P': 9,
      };

      expect(
        () => AuftragsbestandImportService.leseBericht(_mappe(zeilen)),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('12981'),
          ),
        ),
      );
    });

    test('lehnt eine Datei ohne die Spalten des Berichts ab', () {
      expect(
        () => AuftragsbestandImportService.leseBericht(
          _mappe({
            1: {'A': 'Irgendeine Liste'},
            2: {'A': 'Nr.', 'B': 'Beschreibung'},
          }),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('Import in die Datenbank', () {
    late AppDatabase db;
    late AuftragsbestandImportService service;

    setUp(() {
      db = testDatenbank();
      service = AuftragsbestandImportService(db);
    });
    tearDown(() => db.close());

    test('lehnt eine Datei ab, die keine Excel-Datei ist', () async {
      await expectLater(
        service.importiere(Uint8List.fromList([1, 2, 3, 4, 5])),
        throwsA(isA<FormatException>()),
      );
    });

    test('speichert Artikel, Aufträge, Stand und Zeitraum', () async {
      final ergebnis = await service.importiere(_mappe(_standardZeilen()));

      expect(ergebnis.artikel, 2);
      expect(ergebnis.positionen, 4);
      expect(ergebnis.uebersprungen, ['KT']);

      final artikel = await db.select(db.auftragsbestandArtikel).get();
      expect(artikel.map((a) => a.artikelnummer).toSet(), {'12981', '13977'});
      final pute = artikel.firstWhere((a) => a.artikelnummer == '12981');
      expect(pute.lagerKg, 5);
      expect(pute.auftragKg, 8);
      expect(pute.berichtStand, DateTime(2026, 9, 30, 12, 9, 14));
      expect(pute.zeitraumVon, DateTime(2026, 9, 30));
      expect(pute.zeitraumBis, DateTime(2026, 10, 30));

      final positionen = await db.select(db.auftragsbestandPositionen).get();
      expect(positionen, hasLength(4));
    });

    test('ein neuer Import ersetzt den alten vollständig', () async {
      await service.importiere(_mappe(_standardZeilen()));

      // Zweiter Bericht: nur noch die Köttbullar.
      final nurKoettbullar = <int, Map<String, Object>>{
        for (final e in _standardZeilen().entries)
          if (e.key < 19 || e.key >= 35) e.key: e.value,
      };
      await service.importiere(_mappe(nurKoettbullar));

      final artikel = await db.select(db.auftragsbestandArtikel).get();
      expect(artikel.map((a) => a.artikelnummer), ['13977']);
      final positionen = await db.select(db.auftragsbestandPositionen).get();
      expect(positionen.map((p) => p.beleg), ['VA5']);
    });

    test('ein abgelehnter Bericht lässt den alten Stand stehen', () async {
      await service.importiere(_mappe(_standardZeilen()));

      final kaputt = _standardZeilen();
      kaputt[38] = {
        'B': 'Artikelnr.: ',
        'F': '13977',
        'J': 'Gesamt',
        'K': 40,
        'M': 'BTL',
        'P': 999,
      };
      await expectLater(
        service.importiere(_mappe(kaputt)),
        throwsA(isA<FormatException>()),
      );

      final artikel = await db.select(db.auftragsbestandArtikel).get();
      expect(artikel, hasLength(2));
    });
  });

  group('Deckung aus dem Lager', () {
    late AppDatabase db;

    setUp(() => db = testDatenbank());
    tearDown(() => db.close());

    Future<ArtikelDeckung> deckungVon(String nummer) async {
      await AuftragsbestandImportService(db)
          .importiere(_mappe(_standardZeilen()));
      final artikel = await (db.select(db.auftragsbestandArtikel)
            ..where((a) => a.artikelnummer.equals(nummer)))
          .getSingle();
      final positionen = await (db.select(db.auftragsbestandPositionen)
            ..where((p) => p.artikelnummer.equals(nummer)))
          .get();
      return berechneDeckung(lagerKg: artikel.lagerKg, positionen: positionen);
    }

    test('der früheste Auftrag bekommt das Lager zuerst', () async {
      // Lager 5 kg. 30.09.: 1 kg, 02.10.: 7 kg → am 02.10. fehlen 3 kg.
      final d = await deckungVon('12981');

      expect(d.tage, hasLength(2));
      expect(d.tage[0].tag, DateTime(2026, 9, 30));
      expect(d.tage[0].ausLagerKg, 1);
      expect(d.tage[0].fehltKg, 0);
      expect(d.tage[1].tag, DateTime(2026, 10, 2));
      expect(d.tage[1].kg, 7);
      expect(d.tage[1].ausLagerKg, 4);
      expect(d.tage[1].fehltKg, 3);
      expect(d.fehltKg, 3);
      expect(d.ersterEngpass, DateTime(2026, 10, 2));
      expect(d.gedeckt, isFalse);
    });

    test('ohne Lager fehlt alles ab dem ersten Warenausgang', () async {
      final d = await deckungVon('13977');

      expect(d.fehltKg, 480);
      expect(d.ersterEngpass, DateTime(2026, 10, 9));
    });

    test('reicht das Lager, ist nichts offen', () {
      final d = berechneDeckung(lagerKg: 100, positionen: const []);

      expect(d.gedeckt, isTrue);
      expect(d.ersterEngpass, isNull);
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Testdatei im Aufbau des Navision-Berichts
// ═══════════════════════════════════════════════════════════════════════════

/// Zeilennummer → (Spalte → Wert). Strings werden Textzellen, Zahlen
/// Zahlenzellen — wie in der Ausgabe von Navision.
Map<int, Map<String, Object>> _standardZeilen() => {
      1: {'A': 'Auftragsbestand', 'N': '30. September 2026'},
      2: {'A': 'Testfirma GmbH', 'O': '12:09:14'},
      4: {'A': 'Filter', 'Q': 'Seite', 'R': 1},
      6: {'A': '30.09.26', 'C': 'bis', 'E': '30.10.26', 'L': 'BENUTZER'},
      16: {
        'B': 'Belegnr.',
        'F': 'Debitor',
        'H': 'Warenausg.',
        'J': 'Lieferdatum',
        'K': 'Menge',
        'M': 'Einheit',
        'P': 'Nettogewicht',
      },
      // ── Artikel mit zwei Warenausgangstagen ───────────────────────────
      19: {'B': 'Artikelnr.: ', 'F': '12981'},
      20: {'F': 'Putenfleisch in Aspik', 'J': 'geschnitten, egal. 500g Pack'},
      21: {
        'B': 'VA1',
        'F': 'Kunde A ',
        'H': '30.09.26',
        'K': 2,
        'M': 'PACK',
        'P': 1,
      },
      22: {'F': 'Zwischensumme', 'H': '30.09.26', 'K': 2, 'M': 'PACK', 'P': 1},
      23: {
        'B': 'VA2',
        'F': 'Kunde B',
        'H': '02.10.26',
        'K': 8,
        'M': 'PACK',
        'P': 4,
      },
      24: {
        'B': 'VA3',
        'F': 'Kunde & Co',
        'H': '02.10.26',
        'K': 6,
        'M': 'PACK',
        'P': 3,
      },
      25: {'F': 'Zwischensumme', 'H': '02.10.26', 'K': 14, 'M': 'PACK', 'P': 7},
      26: {
        'B': 'Artikelnr.: ',
        'F': '12981',
        'J': 'Gesamt',
        'K': 16,
        'M': 'PACK',
        'P': 8,
      },
      27: {'J': 'Nettogewicht Auf Lager:', 'P': 5},
      // ── Verpackung: steht im Bericht, wird nicht produziert ───────────
      29: {'B': 'Artikelnr.: ', 'F': 'KT'},
      30: {'F': 'Karton Handelsware', 'J': 'Versandkarton'},
      31: {
        'B': 'VA4',
        'F': 'Kunde C',
        'H': '01.10.26',
        'K': 6,
        'M': 'STCK',
        'P': 0,
      },
      32: {
        'B': 'Artikelnr.: ',
        'F': 'KT',
        'J': 'Gesamt',
        'K': 6,
        'M': 'STCK',
        'P': 0,
      },
      33: {'J': 'Nettogewicht Auf Lager:', 'P': 0},
      // ── Artikel ohne Lager ────────────────────────────────────────────
      35: {'B': 'Artikelnr.: ', 'F': '13977'},
      36: {'F': 'Wildköttbullar', 'J': 'egal. 3kg Btl., TK'},
      37: {
        'B': 'VA5',
        'F': 'Kunde D',
        'H': '09.10.26',
        'K': 40,
        'M': 'KT',
        'P': 480,
      },
      38: {
        'B': 'Artikelnr.: ',
        'F': '13977',
        'J': 'Gesamt',
        'K': 40,
        'M': 'BTL',
        'P': 480,
      },
      39: {'J': 'Nettogewicht Auf Lager:', 'P': 0},
    };

/// Baut eine .xlsx aus [zeilen].
///
/// Standard wie Navision: Texte als `inlineStr`, keine sharedStrings,
/// absolute Verweise. Mit [wieExcel] wie nach dem Speichern in Excel:
/// sharedStrings und relative Verweise.
Uint8List _mappe(
  Map<int, Map<String, Object>> zeilen, {
  bool wieExcel = false,
}) {
  String maskiert(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  final geteilt = <String>[];
  final blatt = StringBuffer(
    '<?xml version="1.0" encoding="utf-8"?>'
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/'
    '2006/main"><sheetData>',
  );
  for (final nr in zeilen.keys.toList()..sort()) {
    blatt.write('<row r="$nr">');
    for (final zelle in zeilen[nr]!.entries) {
      final bezug = '${zelle.key}$nr';
      final wert = zelle.value;
      if (wert is num) {
        blatt.write('<c r="$bezug" s="8"><v>$wert</v></c>');
      } else if (wieExcel) {
        geteilt.add(wert.toString());
        blatt.write('<c r="$bezug" t="s"><v>${geteilt.length - 1}</v></c>');
      } else {
        blatt.write(
          '<c s="1" t="inlineStr" r="$bezug"><is><t xml:space="preserve">'
          '${maskiert(wert.toString())}</t></is></c>',
        );
      }
    }
    blatt.write('</row>');
  }
  blatt.write('</sheetData></worksheet>');

  final ziel =
      wieExcel ? 'worksheets/sheet1.xml' : '/xl/worksheets/sheet1.xml';
  final dateien = <String, String>{
    '[Content_Types].xml': '<?xml version="1.0" encoding="utf-8"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/'
        'content-types"/>',
    'xl/workbook.xml': '﻿<?xml version="1.0" encoding="utf-8"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/'
        '2006/main" xmlns:r="http://schemas.openxmlformats.org/'
        'officeDocument/2006/relationships"><sheets>'
        '<sheet name="Tabellenblatt1" sheetId="1" r:id="rId6"></sheet>'
        '</sheets></workbook>',
    'xl/_rels/workbook.xml.rels': '<?xml version="1.0" encoding="utf-8"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/'
        '2006/relationships"><Relationship Type="http://schemas.'
        'openxmlformats.org/officeDocument/2006/relationships/worksheet" '
        'Target="$ziel" Id="rId6" /></Relationships>',
    'xl/worksheets/sheet1.xml': blatt.toString(),
    if (wieExcel)
      'xl/sharedStrings.xml': '<?xml version="1.0" encoding="UTF-8"?>'
          '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/'
          '2006/main">'
          '${geteilt.map((t) => '<si><t>${maskiert(t)}</t></si>').join()}'
          '</sst>',
  };

  final archiv = Archive();
  for (final e in dateien.entries) {
    final bytes = utf8.encode(e.value);
    archiv.addFile(ArchiveFile(e.key, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archiv)!);
}
