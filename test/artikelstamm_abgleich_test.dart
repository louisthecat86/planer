import 'dart:typed_data';

// `show Value` statt eines vollen drift-Imports: drift bringt eine eigene
// Klasse `Column` mit, die sich sonst mit der von Flutter beißen kann.
import 'package:drift/drift.dart' show Value;
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/artikel_anlage_service.dart';
import 'package:produktion_planer/core/services/artikelstamm_abgleich.dart';
import 'package:produktion_planer/core/services/navision_import_service.dart';
import 'package:produktion_planer/features/bedarf/bedarf_screen.dart'
    show ausAltemNavisionImport;

import 'helpers/test_db.dart';

/// Tests für den Abgleich der Navision-Artikelübersicht mit dem
/// Artikelstamm: Allergene aus dem Suchbegriff, neue Artikel, Übernahme.
///
/// Alle Daten sind erfunden. Eine echte Artikelübersicht gehört nicht ins
/// Repository.
void main() {
  group('Allergene aus dem Suchbegriff', () {
    test('die Kürzel aus Navision', () {
      expect(allergeneAusSuchbegriff('EI'), {'eier'});
      expect(allergeneAusSuchbegriff('LAKTOSE'), {'milch'});
      expect(allergeneAusSuchbegriff('SENFSAAT'), {'senf'});
      expect(allergeneAusSuchbegriff('PISTAZIEN'), {'schalenfruechte'});
      expect(allergeneAusSuchbegriff('EI LAKTOSE'), {'eier', 'milch'});
    });

    test('Groß- und Kleinschreibung, Satzzeichen und Umlaute', () {
      expect(allergeneAusSuchbegriff('Ei, Laktose'), {'eier', 'milch'});
      expect(allergeneAusSuchbegriff('senfsaat/ei'), {'senf', 'eier'});
      expect(allergeneAusSuchbegriff('HASELNÜSSE'), {'schalenfruechte'});
      expect(
        allergeneAusSuchbegriff('WEIZEN SOJA SELLERIE SESAM SO2'),
        {'gluten', 'soja', 'sellerie', 'sesam', 'sulfit'},
      );
    });

    test('nur ganze Wörter zählen', () {
      expect(allergeneAusSuchbegriff('SCHWEINEFLEISCH'), isEmpty);
      expect(allergeneAusSuchbegriff('MILCHKALB'), isEmpty);
      expect(allergeneAusSuchbegriff('LEBERKAESE'), isEmpty);
    });

    test('die Nuss als Teilstück ist kein Allergen', () {
      expect(allergeneAusSuchbegriff('KALBSNUSS'), isEmpty);
      expect(allergeneAusSuchbegriff('NUSS SCHINKEN'), isEmpty);
    });

    test('„OHNE" davor und „FREI" danach heben auf', () {
      expect(allergeneAusSuchbegriff('OHNE EI'), isEmpty);
      expect(allergeneAusSuchbegriff('GLUTEN FREI'), isEmpty);
      expect(allergeneAusSuchbegriff('OHNE EI SENF'), {'senf'});
    });

    test('nichts erkannt heißt leer — nie „keine"', () {
      expect(allergeneAusSuchbegriff(null), isEmpty);
      expect(allergeneAusSuchbegriff(''), isEmpty);
      expect(allergeneAusSuchbegriff('KOCHSCHINKEN'), isEmpty);
    });
  });

  group('Abgleich mit der App', () {
    Product produkt(
      String id,
      String nummer, {
      String? allergene,
      bool geloescht = false,
    }) =>
        Product(
          id: id,
          artikelnummer: nummer,
          artikelbezeichnung: 'App $nummer',
          istEingepflegt: true,
          allergene: allergene,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          deletedAt: geloescht ? DateTime(2026, 5) : null,
        );

    NavisionZeile zeile(String nummer, [String? suchbegriff]) => NavisionZeile(
          nummer: nummer,
          beschreibung: 'Navision $nummer',
          suchbegriff: suchbegriff,
        );

    final katalog = NavisionKatalog(
      gelesen: 9,
      warnungen: const ['Hinweis'],
      zeilen: [
        zeile('900020', 'EI'), // neu, nicht im Auftragsbestand
        zeile('900010', 'LAKTOSE'), // neu, im Auftragsbestand
        zeile('900030'), // früher gelöscht
        zeile('100001', 'EI LAKTOSE'), // App ohne Allergene
        zeile('100002', 'EI'), // App: gluten
        zeile('100003', 'SENFSAAT'), // App: keine
        zeile('100004', 'EI'), // App: eier, milch — passt
        zeile('100005', 'KOCHSCHINKEN'), // nichts erkannt
        zeile('100006', 'EI'), // App: eier — passt
      ],
    );

    final abgleich = gleicheArtikelstammAb(
      katalog: katalog,
      produkte: [
        produkt('a1', '100001'),
        produkt('a2', '100002', allergene: 'gluten'),
        produkt('a3', '100003', allergene: 'keine'),
        produkt('a4', '100004', allergene: 'eier,milch'),
        produkt('a5', '100005'),
        produkt('a6', '100006', allergene: 'eier'),
        produkt('a7', '900030', geloescht: true),
      ],
      imAuftragsbestand: {'900010', '100001'},
    );

    test('neue Artikel: die aus dem Auftragsbestand zuerst', () {
      expect(abgleich.neu.map((n) => n.nummer), ['900010', '900020', '900030']);
      expect(abgleich.neu.first.imAuftragsbestand, isTrue);
      expect(abgleich.neu.first.allergene, {'milch'});
      expect(abgleich.neu[1].imAuftragsbestand, isFalse);
      expect(abgleich.neu.last.geloescht, isTrue);
      expect(abgleich.neu.last.allergene, isEmpty);
    });

    test('Allergene ergänzen, wo die App keine hat', () {
      expect(abgleich.ergaenzen.map((v) => v.produkt.id), ['a1']);
      final v = abgleich.ergaenzen.single;
      expect(v.bisher, isEmpty);
      expect(v.neu, {'eier', 'milch'});
      expect(v.ergebnis, 'eier,milch');
      expect(v.widerspruch, isFalse);
    });

    test('Abweichungen: Navision nennt mehr, oder die App sagt „keine"', () {
      expect(abgleich.abweichend.map((v) => v.produkt.id), ['a2', 'a3']);
      final gluten = abgleich.abweichend.first;
      expect(gluten.neu, {'eier'});
      expect(
        gluten.ergebnis,
        'gluten,eier',
        reason: 'Was die App mehr weiß, bleibt — Reihenfolge wie die Liste',
      );
      final keine = abgleich.abweichend.last;
      expect(keine.widerspruch, isTrue);
      expect(keine.ergebnis, 'senf', reason: '„keine" fällt weg');
    });

    test('der Rest ist unverändert', () {
      // a4 und a6 passen, a5 hat nichts im Suchbegriff.
      expect(abgleich.unveraendert, 3);
      expect(abgleich.gelesen, 9);
      expect(abgleich.warnungen, ['Hinweis']);
    });
  });

  group('Übernehmen', () {
    late AppDatabase db;

    setUp(() => db = testDatenbank());
    tearDown(() => db.close());

    Future<Product> laden(String nummer) => (db.select(db.products)
          ..where((p) => p.artikelnummer.equals(nummer)))
        .getSingle();

    test('neue Artikel bekommen ihre Allergene', () async {
      final e = await ArtikelAnlageService(db).legeAn([
        const FehlenderArtikel(
          nummer: '900010',
          bezeichnung: 'Testschinken',
          bezeichnung2: 'gekocht',
          allergene: 'eier,milch',
        ),
        const FehlenderArtikel(nummer: '900020', bezeichnung: 'Testwurst'),
      ]);

      expect(e.angelegt, 2);
      expect(e.geaendert, isTrue);
      final schinken = await laden('900010');
      expect(schinken.allergene, 'eier,milch');
      expect(schinken.beschreibung, 'gekocht');
      expect(schinken.istEingepflegt, isFalse);
      expect((await laden('900020')).allergene, isNull);
    });

    test('wieder aktiviert: gepflegte Allergene bleiben', () async {
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'alt1',
              artikelnummer: '900030',
              artikelbezeichnung: 'Alt ohne',
              deletedAt: Value(DateTime(2026, 5)),
            ),
          );
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'alt2',
              artikelnummer: '900040',
              artikelbezeichnung: 'Alt mit',
              allergene: const Value('gluten'),
              deletedAt: Value(DateTime(2026, 5)),
            ),
          );

      final e = await ArtikelAnlageService(db).legeAn([
        const FehlenderArtikel(
          nummer: '900030',
          bezeichnung: 'x',
          allergene: 'senf',
        ),
        const FehlenderArtikel(
          nummer: '900040',
          bezeichnung: 'x',
          allergene: 'eier',
        ),
      ]);

      expect(e.reaktiviert, 2);
      final ohne = await laden('900030');
      expect(ohne.deletedAt, isNull);
      expect(ohne.allergene, 'senf');
      expect((await laden('900040')).allergene, 'gluten');
    });

    test('Allergene bestehender Artikel setzen — gelöschte nicht', () async {
      await seedArtikel(db, id: 'a1', nummer: '100001');
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'weg',
              artikelnummer: '100009',
              artikelbezeichnung: 'Gelöscht',
              deletedAt: Value(DateTime(2026, 5)),
            ),
          );

      final e = await ArtikelAnlageService(db).legeAn(
        const [],
        allergeneJeId: {'a1': 'eier,milch', 'weg': 'senf', 'fehlt': 'soja'},
      );

      expect(e.allergeneGesetzt, 1);
      expect(e.gesamt, 0);
      expect(e.geaendert, isTrue);
      expect((await laden('100001')).allergene, 'eier,milch');
      expect((await laden('100009')).allergene, isNull);
    });
  });

  group('Artikelübersicht lesen', () {
    Uint8List mappe(List<List<CellValue?>> zeilen) {
      final excel = Excel.createExcel();
      final blatt = excel['Sheet1'];
      for (final z in zeilen) {
        blatt.appendRow(z);
      }
      return Uint8List.fromList(excel.encode()!);
    }

    List<CellValue?> texte(List<String> werte) => [
          for (final w in werte) TextCellValue(w),
        ];

    test('liest die Spalten über die Kopfzeile, nicht über die Position',
        () async {
      final katalog = await NavisionImportService.lese(
        mappe([
          texte(['Testserver']),
          texte(['Artikelübersicht']),
          texte([
            'Suchbegriff',
            'Nr.',
            'Beschreibung',
            'Beschreibung 2',
            'Basiseinheitencode',
            'Produktgruppencode',
          ]),
          texte([
            'EI LAKTOSE',
            '900010',
            'Testschinken',
            'gekocht, am Stück',
            'KG',
            'SCHINKEN',
          ]),
          [
            TextCellValue('SENFSAAT'),
            const IntCellValue(900020),
            TextCellValue('Testwurst'),
          ],
          // Doppelte Nummer: die erste gewinnt.
          texte(['', '900010', 'Doppelt']),
          // Zeile ohne Nummer zählt nicht.
          texte(['EI', '', 'Ohne Nummer']),
        ]),
      );

      expect(katalog.zeilen.map((z) => z.nummer), ['900010', '900020']);
      expect(katalog.gelesen, 3, reason: 'drei Zeilen mit Nummer');
      expect(katalog.warnungen, isEmpty);

      final schinken = katalog.zeilen.first;
      expect(schinken.beschreibung, 'Testschinken');
      expect(schinken.beschreibung2, 'gekocht, am Stück');
      expect(schinken.suchbegriff, 'EI LAKTOSE');
      expect(schinken.basiseinheit, 'KG');
      expect(schinken.produktgruppe, 'SCHINKEN');
      expect(katalog.zeilen.last.suchbegriff, 'SENFSAAT');
    });

    test('ohne Suchbegriff-Spalte gibt es einen Hinweis', () async {
      final katalog = await NavisionImportService.lese(
        mappe([
          texte(['Nr.', 'Beschreibung']),
          texte(['900010', 'Testschinken']),
        ]),
      );

      expect(katalog.zeilen, hasLength(1));
      expect(katalog.zeilen.single.suchbegriff, isNull);
      expect(katalog.warnungen.single, contains('Suchbegriff'));
    });

    test('keine Excel-Datei: klare Meldung', () async {
      await expectLater(
        NavisionImportService.lese(Uint8List.fromList([1, 2, 3, 4, 5])),
        throwsFormatException,
      );
    });
  });

  group('Alte Navision-Bedarfe', () {
    Demand bedarf({String quelle = 'bestellung', String? notizen}) => Demand(
          id: 'b1',
          productId: 'p1',
          mengeKgFertig: 100,
          quelle: quelle,
          prioritaet: 0,
          notizen: notizen,
          manuellErledigt: false,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );

    test('erkennt die Einträge aus dem früheren Import', () {
      expect(
        ausAltemNavisionImport(
          bedarf(notizen: 'Aus Navision · Auftrag 500 kg · Lager 0 kg'),
        ),
        isTrue,
      );
      expect(ausAltemNavisionImport(bedarf(notizen: 'Kunde X')), isFalse);
      expect(ausAltemNavisionImport(bedarf()), isFalse);
      expect(
        ausAltemNavisionImport(
          bedarf(quelle: 'auftragsbestand', notizen: 'Aus Navision'),
        ),
        isFalse,
      );
    });
  });
}
