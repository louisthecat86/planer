import 'dart:convert';
import 'dart:math' show max;
import 'dart:typed_data';

import 'package:archive/archive.dart';
// `show Value`: drift bringt eine eigene Klasse `Column` mit.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/utils/xlsx_leser.dart';
import 'package:produktion_planer/core/utils/xlsx_schreiber.dart';
import 'package:produktion_planer/features/entwicklung/daten/entwicklung_repository.dart';
import 'package:produktion_planer/features/entwicklung/zutaten/zutaten_excel.dart';

import 'helpers/test_db.dart';

/// Der Zutatenkatalog als Excel-Mappe: Export, Einlesen, Abgleich mit der
/// App und Übernehmen. Alle Zutaten sind erfunden.
void main() {
  late AppDatabase db;
  late EntwicklungRepository repo;

  setUp(() {
    db = testDatenbank();
    repo = EntwicklungRepository(db);
  });
  tearDown(() => db.close());

  final stand = DateTime(2026, 11, 4, 9, 30);

  Future<String> zutat(
    String name, {
    String? nummer,
    bool fleisch = false,
    String? tierart,
    double? bindegewebe,
    bool wasser = false,
    double? fett,
    double? salz,
    String? allergene,
    String? notiz,
  }) =>
      repo.zutatAnlegen(
        EntwicklungZutatenCompanion(
          name: Value(name),
          artikelnummer: Value(nummer),
          istFleisch: Value(fleisch),
          tierart: Value(tierart),
          bindegewebe: Value(bindegewebe),
          istWasser: Value(wasser),
          fett: Value(fett),
          salz: Value(salz),
          allergene: Value(allergene),
          notiz: Value(notiz),
        ),
      );

  Future<List<Zutat>> alle() => db.select(db.entwicklungZutaten).get();

  Future<Zutat> lies(String id) async => (await repo.zutat(id))!;

  Future<Uint8List> exportieren() async =>
      zutatenMappe(await alle(), stand: stand);

  Future<ZutatenAbgleich> abgleichen(Uint8List bytes) async =>
      zutatenAbgleichen(zutatenDateiLesen(bytes), await alle());

  /// Drei Zutaten, wie sie oft vorkommen.
  Future<({String bauch, String salz, String pfeffer})> katalog() async => (
        bauch: await zutat(
          'Schweinebauch',
          nummer: '10010',
          fleisch: true,
          tierart: 'schwein',
          bindegewebe: 18,
          fett: 30.5,
          allergene: 'keine',
        ),
        salz: await zutat(
          'Speisesalz',
          nummer: '20020',
          salz: 99.1,
          allergene: 'keine',
          notiz: 'grob',
        ),
        pfeffer: await zutat(
          'Pfeffer schwarz',
          fett: 3.3,
          allergene: 'sellerie,senf',
        ),
      );

  group('Export', () {
    test('je Zutat eine Zeile, nach Namen, mit ID und Stand', () async {
      final k = await katalog();
      await repo.zutatLoeschen(await zutat('Alte Zutat'));
      final t = _Tabelle.aus(await exportieren());

      expect(t.kopf.first, 'Name');
      expect(t.kopf.sublist(t.kopf.length - 2), ['ID', 'Stand']);
      expect(
        t.zeilen.map((z) => z.first),
        ['Pfeffer schwarz', 'Schweinebauch', 'Speisesalz'],
        reason: 'gelöschte Zutaten bleiben draußen',
      );
      expect(t.wert('Schweinebauch', 'Fleisch'), 'ja');
      expect(t.wert('Schweinebauch', 'Tierart'), 'Schwein');
      expect(t.wert('Schweinebauch', 'Bindegewebe %'), 18);
      expect(t.wert('Schweinebauch', 'Fett g'), 30.5);
      expect(t.wert('Schweinebauch', 'Artikelnummer'), '10010');
      expect(t.wert('Schweinebauch', 'Keine Allergene'), 'x');
      expect(t.wert('Speisesalz', 'Fleisch'), 'nein');
      expect(t.wert('Speisesalz', 'Notiz'), 'grob');
      expect(t.wert('Pfeffer schwarz', 'Senf'), 'x');
      expect(t.wert('Pfeffer schwarz', 'Sellerie'), 'x');
      expect(t.wert('Pfeffer schwarz', 'Gluten'), isNull);
      expect(t.wert('Schweinebauch', 'ID'), k.bauch);
      expect(
        t.wert('Schweinebauch', 'Stand'),
        ZutatWerte.aus(await lies(k.bauch)).stand,
      );
    });

    test('ohne Zutaten eine leere Vorlage mit Auswahllisten', () async {
      final bytes = zutatenMappe(const [], stand: stand);
      final blaetter = xlsxLesen(bytes);
      expect(blaetter.map((b) => b.name), ['Zutaten', 'Hinweise']);
      expect(blaetter.first.letzteZeile, 1);
      expect(
        blaetter.last.zelle(2, 1)?.wert,
        contains('0 Zutaten'),
      );

      final datei = zutatenDateiLesen(bytes);
      expect(datei.zeilen, isEmpty);
      expect(datei.vollstaendig, isTrue);
      expect(datei.hinweise, isEmpty);

      final blatt = utf8.decode(
        ZipDecoder()
            .decodeBytes(bytes)
            .findFile('xl/worksheets/sheet1.xml')!
            .content as List<int>,
      );
      expect(blatt, contains('&quot;ja,nein&quot;'));
      expect(blatt, contains('Schwein,Rind'));
      expect(blatt, contains('<pane '), reason: 'Kopfzeile fixiert');
    });

    test('Export und Import ohne Änderung ändern nichts', () async {
      await katalog();
      final a = await abgleichen(await exportieren());
      expect(a.hatAenderungen, isFalse);
      expect(a.unveraendert, 3);
      expect(a.fehler, isEmpty);
      expect(a.hinweise, isEmpty);
    });

    test('der Dateiname trägt das Datum', () {
      expect(zutatenDateiname(stand), 'Zutaten_2026-11-04.xlsx');
    });
  });

  group('Import', () {
    test('in der Datei Geändertes wird übernommen, der Rest bleibt', () async {
      final k = await katalog();
      final t = _Tabelle.aus(await exportieren())
        ..setze('Schweinebauch', 'Fett g', 28)
        ..setze('Speisesalz', 'Notiz', 'fein');
      final a = await abgleichen(t.mappe());

      expect(a.geaendert.map((v) => v.name), ['Schweinebauch', 'Speisesalz']);
      expect(a.geaendert.first.felder, {ZutatFeld.fett});
      expect(a.geaendert.last.felder, {ZutatFeld.notiz});
      expect(a.unveraendert, 1);
      expect(a.konflikte, isEmpty);

      expect(await zutatenUebernehmen(db, a), (neu: 0, geaendert: 2));
      final bauch = await lies(k.bauch);
      expect(bauch.fett, 28);
      expect(bauch.bindegewebe, 18);
      expect(bauch.tierart, 'schwein');
      expect((await lies(k.salz)).notiz, 'fein');
      expect((await lies(k.pfeffer)).fett, 3.3);
    });

    test('eine leere Zelle leert, eine fehlende Spalte lässt', () async {
      final k = await katalog();
      final t = _Tabelle.aus(await exportieren())
        ..setze('Schweinebauch', 'Fett g', null)
        ..setze('Speisesalz', 'Salz g', 98)
        ..spalteLoeschen('Notiz');
      final datei = zutatenDateiLesen(t.mappe());
      expect(datei.vollstaendig, isFalse);
      expect(datei.hinweise.single, contains('„Notiz"'));

      final a = zutatenAbgleichen(datei, await alle());
      expect(a.geaendert.map((v) => v.felder), [
        {ZutatFeld.fett},
        {ZutatFeld.salz},
      ]);
      await zutatenUebernehmen(db, a);
      expect((await lies(k.bauch)).fett, isNull);
      final salz = await lies(k.salz);
      expect(salz.salz, 98);
      expect(salz.notiz, 'grob', reason: 'Spalte fehlt — Notiz bleibt');
    });

    test('neue Zeilen werden angelegt, ein zweiter Import doppelt nichts',
        () async {
      await katalog();
      final t = _Tabelle.aus(await exportieren())
        ..anfuegen({
          'Name': 'Paprika edelsüß',
          'Fett g': '12,5',
          'Sellerie': 'x',
          'QUID': 'ja',
        })
        ..anfuegen({'Name': 'Kartoffelstärke', 'Artikelnummer': 30030});
      final bytes = t.mappe();
      final a = await abgleichen(bytes);
      expect(a.neu.map((v) => v.name), ['Paprika edelsüß', 'Kartoffelstärke']);
      expect(await zutatenUebernehmen(db, a), (neu: 2, geaendert: 0));

      final paprika =
          (await alle()).singleWhere((z) => z.name == 'Paprika edelsüß');
      expect(paprika.fett, 12.5);
      expect(paprika.allergene, 'sellerie');
      expect(paprika.quidPflicht, isTrue);
      final staerke =
          (await alle()).singleWhere((z) => z.name == 'Kartoffelstärke');
      expect(staerke.artikelnummer, '30030');

      final zweiter = await abgleichen(bytes);
      expect(zweiter.hatAenderungen, isFalse);
      expect(zweiter.unveraendert, 5);
    });

    test('ohne ID: erst die Artikelnummer, dann der Name', () async {
      final k = await katalog();
      final t = _Tabelle.aus(await exportieren());
      for (final z in t.zeilen) {
        z[t.spalte('ID')] = null;
        z[t.spalte('Stand')] = null;
      }
      // Umbenannt — die Nummer findet die Zutat trotzdem.
      t.setze('Schweinebauch', 'Name', 'Schweinebauch S3');
      // Ohne Nummer in der App: über den Namen, die Nummer kommt dazu.
      t.setze('Pfeffer schwarz', 'Artikelnummer', '40040');
      final a = await abgleichen(t.mappe());

      expect(a.neu, isEmpty);
      expect(a.konflikte.map((v) => v.zutat!.id), [k.pfeffer, k.bauch]);
      final pfeffer = a.konflikte.first;
      expect(pfeffer.felder, {ZutatFeld.artikelnummer});
      expect(pfeffer.hinweis, 'über den Namen gefunden');
      expect(pfeffer.grund, contains('keinen Stand'));
      expect(a.konflikte.last.felder, {ZutatFeld.name});

      await zutatenUebernehmen(
        db,
        a,
        dateiGewinnt: {for (final v in a.konflikte) v.zeile},
      );
      expect((await lies(k.bauch)).name, 'Schweinebauch S3');
      expect((await lies(k.pfeffer)).artikelnummer, '40040');
    });

    test('nur in der App geändert: die App bleibt, ohne Rückfrage', () async {
      final k = await katalog();
      final bytes = await exportieren();
      await repo.zutatAendern(
        k.salz,
        const EntwicklungZutatenCompanion(salz: Value(97)),
      );
      final a = await abgleichen(bytes);
      expect(a.hatAenderungen, isFalse);
      expect(a.inAppNeuer, 1);
      expect(a.unveraendert, 2);
    });

    test(
        'auf beiden Seiten geändert: Konflikt — die App bleibt, bis die '
        'Datei gewinnen soll', () async {
      final k = await katalog();
      final t = _Tabelle.aus(await exportieren())
        ..setze('Speisesalz', 'Salz g', 96);
      await repo.zutatAendern(
        k.salz,
        const EntwicklungZutatenCompanion(salz: Value(97)),
      );
      final a = await abgleichen(t.mappe());
      expect(a.geaendert, isEmpty);
      final konflikt = a.konflikte.single;
      expect(konflikt.felder, {ZutatFeld.salz});
      expect(konflikt.grund, contains('App und in der Datei'));
      expect(konflikt.vorher!.anzeige(ZutatFeld.salz), '97');
      expect(konflikt.werte.anzeige(ZutatFeld.salz), '96');

      await zutatenUebernehmen(db, a);
      expect((await lies(k.salz)).salz, 97);
      await zutatenUebernehmen(db, a, dateiGewinnt: {konflikt.zeile});
      expect((await lies(k.salz)).salz, 96);
    });

    test('ohne Spalte „Stand" ist jede Abweichung ein Konflikt', () async {
      await katalog();
      final t = _Tabelle.aus(await exportieren())
        ..setze('Speisesalz', 'Salz g', 96)
        ..spalteLoeschen('Stand');
      final a = await abgleichen(t.mappe());
      expect(a.konflikte.single.name, 'Speisesalz');
      expect(a.unveraendert, 2);
    });

    test('Allergene je Spalte; „Keine" schließt die übrigen aus', () async {
      final k = await katalog();
      await repo.zutatAendern(
        k.pfeffer,
        const EntwicklungZutatenCompanion(allergene: Value('senf,sesam')),
      );
      final t = _Tabelle.aus(await exportieren())
        // Allergenfrei war falsch: Senf statt „Keine".
        ..setze('Schweinebauch', 'Keine Allergene', null)
        ..setze('Schweinebauch', 'Senf', 'X')
        // Beides angekreuzt geht nicht.
        ..setze('Speisesalz', 'Sellerie', 'x')
        // Ohne Spalte „Sesam" bleibt Sesam, wie es ist.
        ..setze('Pfeffer schwarz', 'Senf', null)
        ..setze('Pfeffer schwarz', 'Gluten', 'ja')
        ..spalteLoeschen('Sesam');
      final a = await abgleichen(t.mappe());
      expect(a.fehler.single.text, contains('„Keine Allergene" und'));
      expect(a.fehler.single.zeile, 4);

      await zutatenUebernehmen(db, a);
      expect((await lies(k.bauch)).allergene, 'senf');
      expect((await lies(k.salz)).allergene, 'keine');
      expect((await lies(k.pfeffer)).allergene, 'gluten,sesam');
    });

    test(
        'ohne Fleisch keine Tierart; Fleisch und Wasser zugleich ist ein '
        'Fehler', () async {
      final k = await katalog();
      final t = _Tabelle.aus(await exportieren())
        ..setze('Schweinebauch', 'Fleisch', 'nein')
        ..setze('Speisesalz', 'Fleisch', 'ja')
        ..setze('Speisesalz', 'Wasser/Eis', 'ja');
      final a = await abgleichen(t.mappe());
      expect(a.fehler.single.zeile, 4);
      expect(a.fehler.single.text, contains('Fleisch und Wasser/Eis'));
      expect(a.geaendert.single.felder, {
        ZutatFeld.istFleisch,
        ZutatFeld.tierart,
        ZutatFeld.bindegewebe,
      });
      await zutatenUebernehmen(db, a);
      final bauch = await lies(k.bauch);
      expect(bauch.istFleisch, isFalse);
      expect(bauch.tierart, isNull);
      expect(bauch.bindegewebe, isNull);
    });

    test('Zahlen mit Komma, Striche, Unlesbares und Datumszellen', () async {
      final k = await katalog();
      final t = _Tabelle.aus(await exportieren())
        ..setze('Schweinebauch', 'Fett g', '29,5')
        ..setze('Speisesalz', 'Salz g', '-')
        ..setze('Pfeffer schwarz', 'Fett g', 'etwa 3');
      final a = await abgleichen(t.mappe(datum: {('Speisesalz', 'Eiweiß g')}));
      expect(
        a.fehler.map((f) => f.text),
        [
          contains('„Fett g" ist keine Zahl: „etwa 3"'),
          contains('„Eiweiß g" steht als Datum'),
        ],
      );
      expect(a.geaendert.single.felder, {ZutatFeld.fett});
      await zutatenUebernehmen(db, a);
      expect((await lies(k.bauch)).fett, 29.5);
      expect((await lies(k.salz)).salz, 99.1, reason: 'Zeile mit Fehler');
    });

    test('eine kopierte Zeile mit neuem Namen wird eine neue Zutat', () async {
      final k = await katalog();
      final t = _Tabelle.aus(await exportieren());
      final kopie = [...t.zeile('Speisesalz')];
      kopie[t.spalte('Name')] = 'Speisesalz jodiert';
      kopie[t.spalte('Artikelnummer')] = '20021';
      t.zeilen.insert(0, kopie);
      final a = await abgleichen(t.mappe());
      expect(a.neu.single.name, 'Speisesalz jodiert');
      expect(a.neu.single.hinweis, 'Kopie von Zeile 5');
      expect(a.unveraendert, 3);

      await zutatenUebernehmen(db, a);
      expect((await lies(k.salz)).name, 'Speisesalz');
      final jod = (await alle()).singleWhere((z) => z.name.endsWith('jodiert'));
      expect(jod.notiz, 'grob');
      expect(jod.id, isNot(k.salz));
    });

    test('dieselbe Zeile zweimal ist ein Fehler', () async {
      await katalog();
      final t = _Tabelle.aus(await exportieren());
      t.zeilen.add([...t.zeile('Speisesalz')]);
      final a = await abgleichen(t.mappe());
      expect(a.fehler.map((f) => f.zeile), [4, 5]);
      expect(a.fehler.first.text, contains('Zeilen 4, 5'));
    });

    test('unbekannte und gelöschte IDs bleiben außen vor', () async {
      await katalog();
      final bytes = await exportieren();
      final weg = await zutat('Alte Zutat');
      await repo.zutatLoeschen(weg);
      final t = _Tabelle.aus(bytes)
        ..anfuegen({'Name': 'Irgendwas', 'ID': 'gibt-es-nicht'})
        ..anfuegen({'Name': 'Alte Zutat', 'ID': weg});
      final a = await abgleichen(t.mappe());
      expect(a.fehler.map((f) => f.text), [
        contains('Die ID kennt die App nicht'),
        contains('in der App gelöscht'),
      ]);
      expect(a.hatAenderungen, isFalse);
    });

    test('ohne Namen ein Fehler, leere Zeilen zählen nicht', () async {
      await katalog();
      final t = _Tabelle.aus(await exportieren())
        ..anfuegen({'Fett g': 5})
        ..anfuegen({'Name': '   '});
      final a = await abgleichen(t.mappe());
      expect(a.fehler.single.text, 'Der Name fehlt.');
      expect(a.fehler.single.zeile, 5);
    });

    test('neue Zeilen: doppelte Namen und Nummern', () async {
      await katalog();
      final t = _Tabelle.aus(await exportieren())
        ..anfuegen({'Name': 'Majoran'})
        ..anfuegen({'Name': 'majoran '})
        ..anfuegen({'Name': 'Thymian', 'Artikelnummer': '50050'})
        ..anfuegen({'Name': 'Thymian gerebelt', 'Artikelnummer': '50050'});
      final a = await abgleichen(t.mappe());
      expect(a.neu.map((v) => v.name), ['Majoran', 'Thymian']);
      expect(a.fehler.map((f) => f.zeile), [6, 8]);
    });

    test('was das Fenster so nicht anlegt, stört unveränderte Zeilen nicht',
        () async {
      // „Keine" neben einem Allergen und Fleisch, das zugleich Wasser ist —
      // etwa aus einer alten Übernahme.
      final id = await zutat(
        'Mischfleisch',
        fleisch: true,
        tierart: 'rind',
        wasser: true,
        fett: 10,
        allergene: 'keine,senf',
      );
      final t = _Tabelle.aus(await exportieren());
      expect(t.wert('Mischfleisch', 'Keine Allergene'), isNull);
      expect(t.wert('Mischfleisch', 'Senf'), 'x');

      final unveraendert = await abgleichen(t.mappe());
      expect(unveraendert.fehler, isEmpty);
      expect(unveraendert.hatAenderungen, isFalse);

      t.setze('Mischfleisch', 'Fett g', 11);
      final geaendert = await abgleichen(t.mappe());
      expect(geaendert.fehler.single.text, contains('Fleisch und Wasser'));
      expect((await lies(id)).allergene, 'keine,senf');
    });

    test('ein Name, den es in der App zweimal gibt, braucht die ID', () async {
      await zutat('Muskat');
      await zutat('Muskat');
      final t = _Tabelle.aus(await exportieren());
      for (final z in t.zeilen) {
        z[t.spalte('ID')] = null;
      }
      final a = await abgleichen(t.mappe());
      expect(a.fehler, hasLength(2));
      expect(a.fehler.first.text, contains('mehrmals'));
    });
  });

  group('Datei', () {
    test('andere Überschriften, Titel darüber, fremde Spalten', () async {
      final m = XlsxSchreiber();
      final b = m.blatt('Tabelle1')
        ..text(1, 1, 'Meine Rohstoffliste', 0)
        ..text(2, 1, 'Zutat', 0)
        ..text(2, 2, 'Art.-Nr.', 0)
        ..text(2, 3, 'Fett (g/100 g)', 0)
        ..text(2, 4, 'Eiweiß', 0)
        ..text(2, 5, 'Lieferant', 0)
        ..text(2, 6, 'Fleisch', 0)
        ..text(3, 1, 'Rinderhack', 0)
        ..zahl(3, 2, 60060, 0)
        ..zahl(3, 3, 15, 0)
        ..text(3, 4, '20,1', 0)
        ..text(3, 5, 'Erfunden GmbH', 0)
        ..text(3, 6, 'WAHR', 0);
      expect(b.name, 'Tabelle1');
      final datei = zutatenDateiLesen(m.packe());
      expect(datei.vollstaendig, isFalse);
      expect(datei.hinweise.last, contains('„Lieferant"'));
      final zeile = datei.zeilen.single;
      expect(zeile.nummer, 3);
      expect(zeile.werte[ZutatFeld.name], 'Rinderhack');
      expect(zeile.werte[ZutatFeld.artikelnummer], '60060');
      expect(zeile.werte[ZutatFeld.fett], 15);
      expect(zeile.werte[ZutatFeld.eiweiss], 20.1);
      expect(zeile.werte[ZutatFeld.istFleisch], isTrue);

      final a = zutatenAbgleichen(datei, const []);
      final neu = a.neu.single.werte;
      expect(neu[ZutatFeld.notiz], isNull);
      expect(neu.istWasser, isFalse);
    });

    test('eine Kopfzeile mit „Name" genügt', () {
      final m = XlsxSchreiber();
      m.blatt('Zutaten')
        ..text(1, 1, 'Name', 0)
        ..text(2, 1, 'Koriander', 0)
        ..text(3, 1, 'Kreuzkümmel', 0);
      final datei = zutatenDateiLesen(m.packe());
      final a = zutatenAbgleichen(datei, const []);
      expect(a.neu.map((v) => v.name), ['Koriander', 'Kreuzkümmel']);
      expect(a.neu.first.felder, {ZutatFeld.name});
    });

    test('eine Spalte zweimal ist ein Fehler', () {
      final m = XlsxSchreiber();
      m.blatt('Zutaten')
        ..text(1, 1, 'Name', 0)
        ..text(1, 2, 'Fett g', 0)
        ..text(1, 3, 'Fett', 0);
      expect(
        () => zutatenDateiLesen(m.packe()),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('zweimal'),
          ),
        ),
      );
    });

    test('keine Excel-Datei, keine Zutatenliste', () {
      expect(
        () => zutatenDateiLesen(Uint8List.fromList(utf8.encode('Name;Fett'))),
        throwsFormatException,
      );
      final m = XlsxSchreiber();
      m.blatt('Liste').text(1, 1, 'Artikel', 0);
      expect(
        () => zutatenDateiLesen(m.packe()),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('„Name"'),
          ),
        ),
      );
    });
  });

  group('Stand', () {
    test('Rundungsrauschen und Leerraum ändern ihn nicht', () async {
      final a = await zutat(' Kümmel ', fett: 1.1, notiz: 'ganz\r\n');
      final b = await zutat('Kümmel', fett: 1.1 + 1e-9, notiz: 'ganz');
      final c = await zutat('Kümmel', fett: 1.2, notiz: 'ganz');
      final sa = ZutatWerte.aus(await lies(a)).stand;
      expect(sa, startsWith(ZutatWerte.standVorsilbe));
      expect(ZutatWerte.aus(await lies(b)).stand, sa);
      expect(ZutatWerte.aus(await lies(c)).stand, isNot(sa));
    });

    test('Tierart und Bindegewebe zählen nur bei Fleisch', () async {
      final a = await zutat('Wasser', wasser: true, tierart: 'rind');
      final b = await zutat('Wasser', wasser: true);
      expect(
        ZutatWerte.aus(await lies(a)).stand,
        ZutatWerte.aus(await lies(b)).stand,
      );
    });
  });
}

/// Ein Blatt zum Bearbeiten wie in Excel: Kopfzeile und Zeilen mit Texten
/// und Zahlen. [mappe] schreibt es wieder als Datei.
class _Tabelle {
  _Tabelle(this.kopf, this.zeilen);

  /// Das Blatt „Zutaten" der Mappe [bytes].
  factory _Tabelle.aus(Uint8List bytes) {
    final t = xlsxLesen(bytes).firstWhere((t) => t.name == 'Zutaten');
    final breite = t.zellen[1]!.keys.reduce(max);
    Object? wert(XlsxZelle? z) => switch (z) {
          null => null,
          XlsxZelle(art: XlsxArt.zahl, :final zahl) => zahl,
          XlsxZelle(:final wert) => wert,
        };
    return _Tabelle(
      [for (var c = 1; c <= breite; c++) t.zelle(1, c)!.wert],
      [
        for (var r = 2; r <= t.letzteZeile; r++)
          [for (var c = 1; c <= breite; c++) wert(t.zelle(r, c))],
      ],
    );
  }

  final List<String> kopf;
  final List<List<Object?>> zeilen;

  int spalte(String name) {
    final i = kopf.indexOf(name);
    if (i < 0) throw ArgumentError('Keine Spalte „$name"');
    return i;
  }

  List<Object?> zeile(String name) => zeilen.firstWhere((z) => z[0] == name);

  Object? wert(String zutat, String spalte) =>
      zeile(zutat)[this.spalte(spalte)];

  void setze(String zutat, String spalte, Object? wert) =>
      zeile(zutat)[this.spalte(spalte)] = wert;

  void spalteLoeschen(String name) {
    final i = spalte(name);
    kopf.removeAt(i);
    for (final z in zeilen) {
      z.removeAt(i);
    }
  }

  void anfuegen(Map<String, Object?> werte) =>
      zeilen.add([for (final k in kopf) werte[k]]);

  /// Die Datei — die Zellen in [datum] (Zutat, Spalte) als Datum
  /// formatiert, wie eine deutsche Tabelle „1.5" ablegt.
  Uint8List mappe({Set<(String, String)> datum = const {}}) {
    final m = XlsxSchreiber();
    final b = m.blatt('Zutaten');
    for (var i = 0; i < kopf.length; i++) {
      b.text(1, i + 1, kopf[i], XlsxStil.kopf);
    }
    final datumsZellen = {
      for (final (zutat, s) in datum) (zeilen.indexOf(zeile(zutat)), spalte(s)),
    };
    for (var r = 0; r < zeilen.length; r++) {
      for (var c = 0; c < zeilen[r].length; c++) {
        if (datumsZellen.contains((r, c))) {
          b.zahl(r + 2, c + 1, 46146, XlsxStil.datum);
          continue;
        }
        switch (zeilen[r][c]) {
          case final num n:
            b.zahl(r + 2, c + 1, n, XlsxStil.wert);
          case final String s:
            b.text(r + 2, c + 1, s, XlsxStil.wert);
        }
      }
    }
    return m.packe();
  }
}
