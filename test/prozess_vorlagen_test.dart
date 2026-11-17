import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/navision_import_service.dart';
import 'package:produktion_planer/core/services/navision_katalog.dart';
import 'package:produktion_planer/core/services/prozess_vorlagen.dart';
import 'package:produktion_planer/core/services/prozesskette_service.dart';

import 'helpers/test_db.dart';

/// Tests für die Prozessvorlagen: Vorschlagen über Stichworte, Datei,
/// Anlagen zuordnen, am Artikel anwenden, für viele Artikel auf einmal und
/// zurücknehmen. Alle Vorlagen, Anlagen und Artikel sind erfunden.
void main() {
  const formen = VorlagenSchritt(
    abteilung: 'kutterabteilung',
    maschineId: 'm-form',
    maschine: 'Testformer',
  );
  const braten = VorlagenSchritt(
    abteilung: 'bratstrasse',
    maschineId: 'm-brat',
    maschine: 'Testbratlinie',
    prozessschritt: 'braten',
  );
  const hand = VorlagenSchritt(
    abteilung: 'verpackung',
    prozessschritt: 'von Hand verpacken',
  );

  const hackGebraten = ProzessVorlage(
    id: 'v-hack-g',
    name: 'Hackprodukt gebraten',
    muss: ['frikadell|hacksteak', 'gebrat|gegart'],
    schritte: [formen, braten, hand],
  );
  const hackRoh = ProzessVorlage(
    id: 'v-hack-r',
    name: 'Hackprodukt roh',
    muss: ['frikadell|hacksteak', '=roh'],
    schritte: [formen, hand],
  );
  const spiess = ProzessVorlage(
    id: 'v-spiess',
    name: 'Spieß',
    muss: ['spiess'],
    nicht: ['=roh'],
    schritte: [braten],
  );
  const vorlagen = [hackGebraten, hackRoh, spiess];

  group('Vorschlagen', () {
    String? name(String bezeichnung) =>
        vorlageVorschlagen(vorlagen, bezeichnung).vorlage?.name;

    test('alle Stichworte müssen stehen', () {
      expect(name('Testfrikadelle gebraten, ca. 80g'), 'Hackprodukt gebraten');
      expect(name('Testhacksteak roh, 120g'), 'Hackprodukt roh');
      expect(name('Testfrikadelle, 80g'), isNull);
    });

    test('Groß und klein und Umlaute sind egal', () {
      expect(name('TESTSPIESS'), 'Spieß');
      expect(name('Testspieß mit Zwiebeln'), 'Spieß');
      expect(name('Test-Hacksteak GEGART'), 'Hackprodukt gebraten');
    });

    test('„=" zählt nur ganze Worte', () {
      // „roh" steckt in „Rohware", ist aber kein eigenes Wort.
      expect(name('Testfrikadelle aus Rohware'), isNull);
      expect(name('Testfrikadelle (roh)'), 'Hackprodukt roh');
    });

    test('ausgeschlossene Stichworte verhindern den Vorschlag', () {
      expect(name('Testspieß roh'), isNull);
      expect(name('Testspieß gebraten'), 'Spieß');
    });

    test('die genaueste Vorlage gewinnt, gleich gute sind unsicher', () {
      const allgemein = ProzessVorlage(
        id: 'v-allg',
        name: 'Frikadelle allgemein',
        muss: ['frikadell'],
      );
      final v = vorlageVorschlagen(
        [allgemein, hackGebraten],
        'Testfrikadelle gebraten',
      );
      expect(v.vorlage?.name, 'Hackprodukt gebraten');
      expect(v.passend.map((p) => p.id), ['v-hack-g', 'v-allg']);

      const doppelt = ProzessVorlage(
        id: 'v-dop',
        name: 'Doppelt',
        muss: ['frikadell', 'gebrat'],
      );
      final zwei = vorlageVorschlagen(
        [hackGebraten, doppelt],
        'Testfrikadelle gebraten',
      );
      expect(zwei.mehrdeutig, isTrue);
      expect(zwei.sicher, isFalse);
      expect(zwei.vorlage, isNull);
      expect(zwei.passend, hasLength(2));
    });

    test('eine Vorlage ohne Stichworte wird nie vorgeschlagen', () {
      const ohne = ProzessVorlage(id: 'v-ohne', name: 'Ohne');
      expect(vorlagePasst(ohne, 'egal was'), isNull);
    });
  });

  group('Datei', () {
    test('hin und zurück', () {
      final wieder = vorlagenAusText(vorlagenAlsText(vorlagen));

      expect(wieder, hasLength(3));
      expect(wieder.first.name, 'Hackprodukt gebraten');
      expect(wieder.first.muss, ['frikadell|hacksteak', 'gebrat|gegart']);
      expect(wieder.first.schritte, [formen, braten, hand]);
      expect(wieder.last.nicht, ['=roh']);
    });

    test('was keine Vorlagen-Datei ist, wird abgelehnt', () {
      expect(() => vorlagenAusText('kein json'), throwsFormatException);
      expect(() => vorlagenAusText('{"a": 1}'), throwsFormatException);
      expect(
        () => vorlagenAusText(
          '{"format": "planer-prozessvorlagen", "version": 9}',
        ),
        throwsFormatException,
      );
    });

    test('zusammenführen: gleiche ID ersetzt, Neues kommt hinten dazu', () {
      final neu = vorlagenZusammenfuehren(
        vorlagen,
        [
          hackRoh.kopie(name: 'Hackprodukt roh, neu'),
          const ProzessVorlage(id: 'v-neu', name: 'Neu'),
        ],
      );
      expect(
        neu.map((v) => v.name),
        ['Hackprodukt gebraten', 'Hackprodukt roh, neu', 'Spieß', 'Neu'],
      );
    });
  });

  group('Mit der Datenbank', () {
    late AppDatabase db;

    setUp(() async {
      db = testDatenbank();
      await seedAnlage(
        db,
        id: 'm-form',
        name: 'Testformer',
        abteilung: 'kutterabteilung',
      );
      await seedAnlage(
        db,
        id: 'm-brat',
        name: 'Testbratlinie',
        abteilung: 'bratstrasse',
      );
      await seedArtikel(db, id: 'p1', nummer: '900010');
      await seedArtikel(db, id: 'p2', nummer: '900020');
    });
    tearDown(() => db.close());

    Future<List<ProductStep>> kette(String productId) =>
        ProzesskettenService.schritte(db, productId);

    test('speichern und laden', () async {
      expect(await ProzessVorlagenSpeicher.laden(db), isEmpty);
      await ProzessVorlagenSpeicher.speichern(db, vorlagen);
      final geladen = await ProzessVorlagenSpeicher.laden(db);
      expect(geladen.map((v) => v.id), ['v-hack-g', 'v-hack-r', 'v-spiess']);
    });

    test('Anlagen finden sich über ID oder Namen', () async {
      final fremd = [
        const ProzessVorlage(
          id: 'v',
          name: 'Von woanders',
          schritte: [
            VorlagenSchritt(
              abteilung: 'kutterabteilung',
              maschineId: 'andere-id',
              maschine: 'TESTFORMER',
            ),
            VorlagenSchritt(
              abteilung: 'zerlegung',
              maschineId: 'gibt-es-nicht',
              maschine: 'Unbekannte Anlage',
            ),
          ],
        ),
      ];

      final zugeordnet =
          anlagenZuordnen(fremd, await db.select(db.machines).get());

      final s = zugeordnet.single.schritte;
      expect((s[0].maschineId, s[0].maschine), ('m-form', 'Testformer'));
      expect((s[1].maschineId, s[1].maschine), (null, 'Unbekannte Anlage'));
    });

    test('am leeren Artikel: die Kette der Vorlage ohne Werte', () async {
      final ids = await vorlageAnwenden(db, 'p1', hackGebraten);

      final k = await kette('p1');
      expect(k.map((s) => s.id), ids);
      expect(
        k.map((s) => (s.abteilung, s.maschineId, s.prozessschritt)),
        [
          ('kutterabteilung', 'm-form', null),
          ('bratstrasse', 'm-brat', 'braten'),
          ('verpackung', null, 'von Hand verpacken'),
        ],
      );
      expect(k.map((s) => s.reihenfolge), [1, 2, 3]);
      expect(k.every((s) => s.basisMengeKg == 0), isTrue);
    });

    test('an einem gepflegten Artikel: hinten angehängt, Altes bleibt',
        () async {
      await seedSchritt(
        db,
        id: 's-alt',
        productId: 'p1',
        reihenfolge: 1,
        abteilung: 'zerlegung',
        basisMengeKg: 300,
        basisDauerMinuten: 45,
      );

      await vorlageAnwenden(db, 'p1', spiess);

      final k = await kette('p1');
      expect(k.map((s) => s.abteilung), ['zerlegung', 'bratstrasse']);
      expect(k.first.id, 's-alt');
      expect((k.first.basisMengeKg, k.first.basisDauerMinuten), (300, 45));
    });

    test('eine Anlage, die es nicht mehr gibt, bleibt nur als Name', () async {
      await vorlageAnwenden(
        db,
        'p1',
        const ProzessVorlage(
          id: 'v',
          name: 'Alt',
          schritte: [
            VorlagenSchritt(
              abteilung: 'zerlegung',
              maschineId: 'weg',
              maschine: 'Alte Säge',
            ),
          ],
        ),
      );
      final s = (await kette('p1')).single;
      expect((s.maschineId, s.maschine), (null, 'Alte Säge'));
    });

    test('mehr als 20 Schritte gehen nicht', () async {
      final lang = ProzessVorlage(
        id: 'v-lang',
        name: 'Zu lang',
        schritte: List.filled(ProzesskettenService.maxSchritte + 1, hand),
      );
      await expectLater(vorlageAnwenden(db, 'p1', lang), throwsStateError);
      expect(await kette('p1'), isEmpty);
    });

    test('viele auf einmal — gepflegte Artikel bleiben unberührt', () async {
      await seedSchritt(
        db,
        id: 's-alt',
        productId: 'p2',
        reihenfolge: 1,
        abteilung: 'zerlegung',
      );

      final neu = await vorlagenZuordnen(db, {
        'p1': hackGebraten,
        'p2': hackRoh,
      });

      expect(neu, hasLength(3));
      expect(await kette('p1'), hasLength(3));
      expect((await kette('p2')).map((s) => s.id), ['s-alt']);
    });

    test('zurücknehmen: die Artikel sind wieder leer', () async {
      final neu = await vorlagenZuordnen(db, {
        'p1': hackGebraten,
        'p2': spiess,
      });

      await vorlagenZuruecknehmen(db, neu);

      expect(await kette('p1'), isEmpty);
      expect(await kette('p2'), isEmpty);
      // Danach lässt sich wieder zuordnen.
      expect(await vorlagenZuordnen(db, {'p1': hackRoh}), hasLength(2));
    });

    test('gesucht wird auch in „Beschreibung 2" aus Navision', () async {
      await NavisionKatalogSpeicher.merken(
        db,
        const NavisionKatalog(
          warnungen: [],
          gelesen: 1,
          zeilen: [
            NavisionZeile(
              nummer: '900010',
              beschreibung: 'Testlyoner',
              beschreibung2: 'geschnitten, egal. 500g Pack, TK',
            ),
          ],
        ),
      );
      final artikel = await db.select(db.products).get();

      final texte = await vorschlagsTexte(db, artikel);

      expect(texte['p1'], endsWith('geschnitten, egal. 500g Pack, TK'));
      // Ohne Navision-Zeile nur die Bezeichnung.
      final p2 = artikel.singleWhere((a) => a.id == 'p2');
      expect(texte['p2'], p2.artikelbezeichnung);

      const geschnittenTk = ProzessVorlage(
        id: 'v-g',
        name: 'geschnitten, TK',
        muss: ['geschnitten|scheiben|500g', '=tk'],
      );
      expect(vorlageVorschlagen([geschnittenTk], texte['p1']!).sicher, isTrue);
    });

    test('die Vorlagen fahren mit im Backup — sie stehen in app_settings',
        () async {
      await ProzessVorlagenSpeicher.speichern(db, vorlagen);
      final zeile = await (db.select(db.appSettings)
            ..where((s) => s.key.equals(kProzessVorlagenSchluessel)))
          .getSingle();
      expect(zeile.value, contains('Hackprodukt roh'));
      await db.into(db.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: kProzessVorlagenSchluessel,
              value: 'kaputt',
              updatedAt: Value(DateTime(2026)),
            ),
          );
      // Ein kaputter Eintrag ergibt keine Vorlagen statt eines Fehlers.
      expect(await ProzessVorlagenSpeicher.laden(db), isEmpty);
    });
  });
}
