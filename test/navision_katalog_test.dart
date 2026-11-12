import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/navision_import_service.dart';
import 'package:produktion_planer/core/services/navision_katalog.dart';
import 'package:produktion_planer/features/articles/artikel_luecken.dart';

import 'helpers/test_db.dart';

/// Tests für den Stand der Navision-Artikelübersicht in der App und für
/// die Muster: Was Navision in „Nummer 2" als Muster führt, zählt nicht
/// als „nicht eingepflegt". Alle Artikel sind erfunden.
void main() {
  late AppDatabase db;

  setUp(() => db = testDatenbank());
  tearDown(() => db.close());

  NavisionKatalog katalog(
    List<NavisionZeile> zeilen, {
    bool mitNummer2 = true,
  }) =>
      NavisionKatalog(
        zeilen: zeilen,
        warnungen: const [],
        gelesen: zeilen.length,
        mitNummer2: mitNummer2,
      );

  Future<NavisionArtikelZeile> zeile(String nummer) =>
      (db.select(db.navisionArtikel)
            ..where((a) => a.artikelnummer.equals(nummer)))
          .getSingle();

  group('Muster-Kennung', () {
    test('das Wort zählt, egal wie geschrieben und was dabeisteht', () {
      expect(istMusterKennung('MUSTER'), isTrue);
      expect(istMusterKennung('Muster neu'), isTrue);
      expect(istMusterKennung('Testwürze, muster'), isTrue);
      expect(istMusterKennung('MUSTER  900010'), isTrue);
    });

    test('alles andere nicht', () {
      expect(istMusterKennung(null), isFalse);
      expect(istMusterKennung(''), isFalse);
      expect(istMusterKennung('900010'), isFalse);
      expect(istMusterKennung('TESTCODE'), isFalse);
    });
  });

  group('Stand merken', () {
    test('je Artikelnummer eine Zeile mit dem, was Navision sagt', () async {
      final wann = DateTime(2026, 11, 2, 9);
      final n = await NavisionKatalogSpeicher.merken(
        db,
        katalog(const [
          NavisionZeile(
            nummer: '900010',
            nummer2: 'MUSTER',
            beschreibung: 'Testschinken',
            beschreibung2: 'am Stück',
            suchbegriff: 'EI',
            basiseinheit: 'KG',
            produktbuchungsgruppe: 'TESTFERTIG',
            artikelkategorie: 'TESTKAT',
            produktgruppe: 'TESTGRUPPE',
          ),
          NavisionZeile(nummer: '900020', beschreibung: 'Testsalz'),
        ]),
        jetzt: wann,
      );

      expect(n, 2);
      final z = await zeile('900010');
      expect(z.nummer2, 'MUSTER');
      expect(z.beschreibung, 'Testschinken');
      expect(z.beschreibung2, 'am Stück');
      expect(z.suchbegriff, 'EI');
      expect(z.basiseinheit, 'KG');
      expect(z.produktbuchungsgruppe, 'TESTFERTIG');
      expect(z.artikelkategorie, 'TESTKAT');
      expect(z.produktgruppe, 'TESTGRUPPE');
      expect(z.eingelesenAm, wann);
      expect((await zeile('900020')).nummer2, isNull);
    });

    test('aus dem Muster wird ein Bestandsartikel', () async {
      await NavisionKatalogSpeicher.merken(
        db,
        katalog(const [NavisionZeile(nummer: '900010', nummer2: 'MUSTER')]),
      );
      expect(await NavisionKatalogSpeicher.musterNummern(db), {'900010'});

      // Beim nächsten Einlesen steht in „Nummer 2" nichts mehr.
      await NavisionKatalogSpeicher.merken(
        db,
        katalog(const [NavisionZeile(nummer: '900010')]),
      );
      expect(await NavisionKatalogSpeicher.musterNummern(db), isEmpty);
    });

    test('eine Übersicht mit weniger Artikeln löscht nichts', () async {
      await NavisionKatalogSpeicher.merken(
        db,
        katalog(const [
          NavisionZeile(nummer: '900010', nummer2: 'MUSTER'),
          NavisionZeile(nummer: '900020', nummer2: 'Muster'),
        ]),
      );
      await NavisionKatalogSpeicher.merken(
        db,
        katalog(const [NavisionZeile(nummer: '900020', nummer2: 'MUSTER')]),
      );

      expect(
        await NavisionKatalogSpeicher.musterNummern(db),
        {'900010', '900020'},
      );
    });

    test('ohne die Spalte „Nummer 2" bleibt die Kennzeichnung stehen',
        () async {
      await NavisionKatalogSpeicher.merken(
        db,
        katalog(const [
          NavisionZeile(
            nummer: '900010',
            nummer2: 'MUSTER',
            beschreibung: 'Alt',
          ),
        ]),
      );
      await NavisionKatalogSpeicher.merken(
        db,
        katalog(
          const [
            NavisionZeile(nummer: '900010', beschreibung: 'Neu'),
            NavisionZeile(nummer: '900030', beschreibung: 'Dazu'),
          ],
          mitNummer2: false,
        ),
      );

      final z = await zeile('900010');
      // Der Rest kommt aus der neuen Übersicht.
      expect(z.beschreibung, 'Neu');
      expect(z.nummer2, 'MUSTER');
      expect((await zeile('900030')).nummer2, isNull);
      expect(await NavisionKatalogSpeicher.musterNummern(db), {'900010'});
    });
  });

  group('Lücken', () {
    Future<Product> artikel({required bool eingepflegt}) async {
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'p1',
              artikelnummer: '900010',
              artikelbezeichnung: 'Testschinken',
              istEingepflegt: Value(eingepflegt),
            ),
          );
      return db.select(db.products).getSingle();
    }

    test('ein Muster ohne Artikelmaske hat keine', () async {
      final p = await artikel(eingepflegt: false);

      expect(
        artikelLuecken(p, const [], null),
        contains(ArtikelLuecke.nichtEingepflegt),
      );
      expect(artikelLuecken(p, const [], null, istMuster: true), isEmpty);
    });

    test('ein eingepflegtes Muster zählt wie jeder Artikel', () async {
      final p = await artikel(eingepflegt: true);

      expect(
        artikelLuecken(p, const [], null, istMuster: true),
        artikelLuecken(p, const [], null),
      );
      expect(
        artikelLuecken(p, const [], null, istMuster: true),
        contains(ArtikelLuecke.ohneSchritte),
      );
    });
  });
}
