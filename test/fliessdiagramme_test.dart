import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
// `show Value`: drift bringt eine eigene Klasse `Column` mit.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/features/entwicklung/bericht/projekt_bericht.dart';
import 'package:produktion_planer/features/entwicklung/daten/dateien.dart';
import 'package:produktion_planer/features/entwicklung/entwicklung_zugang.dart';
import 'package:produktion_planer/features/entwicklung/projekte/fliessdiagramm_dateien.dart';
import 'package:produktion_planer/features/entwicklung/projekte/fliessdiagramm_dienst.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_repository.dart';

import 'helpers/test_db.dart';

/// Tests für die Fließdiagramme als PDF: Dateinamen, ZIP aus Windows,
/// Einlesen und Ablegen. Alle Namen und Inhalte erfunden.

/// Bytes eines kurzen Text-PDFs — der Inhalt zählt hier nicht.
Uint8List pdf(String text) =>
    Uint8List.fromList(utf8.encode('%PDF-1.4 $text'));

FdDatei datei(String name, String text) => (name: name, inhalt: pdf(text));

List<int> ascii(String text) => text.codeUnits;

/// Ein ZIP ohne Kompression. Ohne [utf8] steht der Name so im ZIP, wie er
/// gegeben ist — etwa in der DOS-Codepage, wie Windows ihn packt.
Uint8List zipAus(
  List<({List<int> name, List<int> inhalt, bool utf8})> eintraege,
) {
  final daten = BytesBuilder();
  final verzeichnis = BytesBuilder();
  void zahl(BytesBuilder b, int wert, int bytes) {
    for (var i = 0; i < bytes; i++) {
      b.addByte((wert >> (8 * i)) & 0xFF);
    }
  }

  for (final e in eintraege) {
    final start = daten.length;
    final crc = getCrc32(e.inhalt);
    final kennzeichen = e.utf8 ? 0x0800 : 0;
    // Kopf vor den Daten.
    zahl(daten, 0x04034b50, 4);
    zahl(daten, 20, 2);
    zahl(daten, kennzeichen, 2);
    zahl(daten, 0, 2); // gespeichert, nicht gepackt
    zahl(daten, 0, 2);
    zahl(daten, 0x5C21, 2);
    zahl(daten, crc, 4);
    zahl(daten, e.inhalt.length, 4);
    zahl(daten, e.inhalt.length, 4);
    zahl(daten, e.name.length, 2);
    zahl(daten, 0, 2);
    daten
      ..add(e.name)
      ..add(e.inhalt);
    // Eintrag im Verzeichnis.
    zahl(verzeichnis, 0x02014b50, 4);
    zahl(verzeichnis, 20, 2);
    zahl(verzeichnis, 20, 2);
    zahl(verzeichnis, kennzeichen, 2);
    zahl(verzeichnis, 0, 2);
    zahl(verzeichnis, 0, 2);
    zahl(verzeichnis, 0x5C21, 2);
    zahl(verzeichnis, crc, 4);
    zahl(verzeichnis, e.inhalt.length, 4);
    zahl(verzeichnis, e.inhalt.length, 4);
    zahl(verzeichnis, e.name.length, 2);
    zahl(verzeichnis, 0, 2);
    zahl(verzeichnis, 0, 2);
    zahl(verzeichnis, 0, 2);
    zahl(verzeichnis, 0, 2);
    zahl(verzeichnis, 0, 4);
    zahl(verzeichnis, start, 4);
    verzeichnis.add(e.name);
  }
  final anfang = daten.length;
  final v = verzeichnis.toBytes();
  daten.add(v);
  zahl(daten, 0x06054b50, 4);
  zahl(daten, 0, 2);
  zahl(daten, 0, 2);
  zahl(daten, eintraege.length, 2);
  zahl(daten, eintraege.length, 2);
  zahl(daten, v.length, 4);
  zahl(daten, anfang, 4);
  zahl(daten, 0, 2);
  return daten.toBytes();
}

void main() {
  group('Dateinamen', () {
    test('Kennung, Bezeichnung und Stand', () {
      expect(
        fdAusDateiname('FD_007 Schnitzel paniert 260731.pdf'),
        (id: 'FD_007', bezeichnung: 'Schnitzel paniert', stand: DateTime(2026, 7, 31)),
      );
      // „_" in der Bezeichnung steht für „/"; Datum lang oder mit Strichen.
      expect(
        fdAusDateiname('FD-12 Brühwurst_Kochwurst 20260102.PDF'),
        (
          id: 'FD_12',
          bezeichnung: 'Brühwurst/Kochwurst',
          stand: DateTime(2026, 1, 2),
        ),
      );
      expect(
        fdAusDateiname('FD 3 – Gewürze 2026-03-04.pdf'),
        (id: 'FD_3', bezeichnung: 'Gewürze', stand: DateTime(2026, 3, 4)),
      );
      // Ordner fallen weg.
      expect(
        fdAusDateiname('Ordner/FD_008 Testware frisch_TK 260101.pdf'),
        (
          id: 'FD_008',
          bezeichnung: 'Testware frisch/TK',
          stand: DateTime(2026, 1, 1),
        ),
      );
      expect(
        fdAusDateiname(r'C:\Daten\FD_009 Testware.pdf'),
        (id: 'FD_009', bezeichnung: 'Testware', stand: null),
      );
      expect(
        fdAusDateiname('FD_004.pdf'),
        (id: 'FD_004', bezeichnung: 'FD_004', stand: null),
      );
    });

    test('was kein Datum ist, bleibt in der Bezeichnung', () {
      expect(fdAusDateiname('FD_005 Testware 261399.pdf')!.stand, isNull);
      expect(
        fdAusDateiname('FD_005 Testware 261399.pdf')!.bezeichnung,
        'Testware 261399',
      );
      // Den 31. Februar gibt es nicht.
      expect(fdAusDateiname('FD_006 Testware 260231.pdf')!.stand, isNull);
    });

    test('ohne Kennung oder ohne PDF: nichts', () {
      expect(fdAusDateiname('Notiz.pdf'), isNull);
      expect(fdAusDateiname('Scan 2026 Testware.pdf'), isNull);
      expect(fdAusDateiname('FD_001 Testware.docx'), isNull);
      expect(fdAusDateiname('FD_1.5 Testware.pdf'), isNull);
      expect(fdAusDateiname('Fließdiagramm 2026.pdf'), isNull);
    });

    test('Datei-ID, Text und Reihenfolge', () {
      final id = fdDateiId('FD_011', DateTime(2026, 7, 31, 14, 30));
      expect(id, 'fliessdiagramm:FD_011:2026-07-31');
      expect(fdAusDateiId(id), (fdId: 'FD_011', stand: DateTime(2026, 7, 31)));
      expect(fdAusDateiId('spezifikation:de'), isNull);
      expect(fdAusDateiId('fliessdiagramm:FD_011'), isNull);

      expect(
        fdText('FD_011', bezeichnung: 'Testware', stand: DateTime(2026, 7, 31)),
        'FD_011 · Testware · Stand 31.07.2026',
      );
      expect(fdText('FD_011', bezeichnung: 'FD_011'), 'FD_011');
      expect(fdText('FD_011', bezeichnung: ''), 'FD_011');

      expect(
        ['FD_10', 'FD_2', 'AB_3', 'FD_1', 'FD_02']..sort(fdNachKennung),
        ['AB_3', 'FD_1', 'FD_02', 'FD_2', 'FD_10'],
      );
    });
  });

  group('ZIP', () {
    test('DOS-Codepage', () {
      expect(cp850Text([0x47, 0x65, 0x77, 0x81, 0x72, 0x7A, 0x65]), 'Gewürze');
      expect(cp850Text([0x53, 0x74, 0x72, 0x61, 0xE1, 0x65]), 'Straße');
      expect(cp850Text([0x8E, 0x99, 0x9A, 0x84, 0x94]), 'ÄÖÜäö');

      final dos = [0x47, 0x72, 0x81, 0xE1, 0x65];
      expect(zipDateiname(dos, utf8Kennzeichen: false), 'Grüße');
      expect(zipDateiname(utf8.encode('Grüße'), utf8Kennzeichen: true), 'Grüße');
      // Gültiges UTF-8 auch ohne Kennzeichen.
      expect(
        zipDateiname(utf8.encode('Grüße'), utf8Kennzeichen: false),
        'Grüße',
      );
      expect(zipDateiname(ascii('Liste.pdf'), utf8Kennzeichen: false), 'Liste.pdf');
    });

    test('PDFs aus einem ZIP von Windows', () {
      final zip = zipAus([
        (
          name: [
            ...ascii('FD_102 Pr'),
            0x81,
            ...ascii('fmuster_B'),
            0x84,
            ...ascii('llchen 260102.pdf'),
          ],
          inhalt: pdf('a'),
          utf8: false,
        ),
        (
          name: utf8.encode('FD_103 Straße 260103.pdf'),
          inhalt: pdf('b'),
          utf8: true,
        ),
        (name: ascii('Unterordner/'), inhalt: const [], utf8: false),
        (
          name: ascii('Unterordner/FD_104 Testware 260104.pdf'),
          inhalt: pdf('c'),
          utf8: false,
        ),
        (
          name: ascii('__MACOSX/Unterordner/._FD_104 Testware 260104.pdf'),
          inhalt: const [1, 2, 3],
          utf8: false,
        ),
        (name: ascii('Liste.txt'), inhalt: ascii('x'), utf8: false),
      ]);
      expect(zipDateinamen(zip), [
        'FD_102 Prüfmuster_Bällchen 260102.pdf',
        'FD_103 Straße 260103.pdf',
        'Unterordner/',
        'Unterordner/FD_104 Testware 260104.pdf',
        '__MACOSX/Unterordner/._FD_104 Testware 260104.pdf',
        'Liste.txt',
      ]);
      final pdfs = pdfsAusZip(zip);
      expect([for (final p in pdfs) p.name], [
        'FD_102 Prüfmuster_Bällchen 260102.pdf',
        'FD_103 Straße 260103.pdf',
        'FD_104 Testware 260104.pdf',
      ]);
      expect([for (final p in pdfs) p.inhalt], [pdf('a'), pdf('b'), pdf('c')]);
      expect(
        fdAusDateiname(pdfs.first.name)!.bezeichnung,
        'Prüfmuster/Bällchen',
      );
    });

    test('kein ZIP', () {
      expect(
        () => pdfsAusZip(Uint8List.fromList(utf8.encode('kein zip'))),
        throwsFormatException,
      );
      expect(zipDateinamen(Uint8List(0)), isEmpty);
      expect(zipDateinamen(Uint8List(40)), isEmpty);
    });
  });

  group('Einlesen planen', () {
    final heute = DateTime(2026, 10, 1, 9, 30);

    test('alles neu: anlegen nach Kennung, jede Fassung speichern', () {
      final plan = fdEinlesePlan(
        dateien: [
          datei('FD_102 Testware alt 260101.pdf', 'a'),
          datei('FD_102 Testware neu 260301.pdf', 'b'),
          datei('FD_101 Erstes.pdf', 'c'),
          datei('Notiz.pdf', 'd'),
        ],
        bezeichnungen: const {},
        gespeichert: const [],
        heute: heute,
      );
      expect(plan.anlegen, [
        (id: 'FD_101', bezeichnung: 'Erstes'),
        (id: 'FD_102', bezeichnung: 'Testware neu'),
      ]);
      expect(plan.umbenennen, isEmpty);
      expect(plan.neuerStand, isEmpty);
      // Ohne Datum im Namen: der Stand von heute.
      expect([for (final s in plan.speichern) s.dateiId], [
        'fliessdiagramm:FD_101:2026-10-01',
        'fliessdiagramm:FD_102:2026-01-01',
        'fliessdiagramm:FD_102:2026-03-01',
      ]);
      expect(plan.uebersprungen, ['Notiz.pdf']);
      expect(
        plan.text,
        '2 Fließdiagramme neu, 3 PDFs gespeichert.\n'
        'Ohne Kennung wie „FD_001" am Anfang des Namens übersprungen: '
        'Notiz.pdf',
      );
    });

    List<FdGespeichert> gespeichert(List<FdDatei> dateien) => [
          for (final d in dateien)
            (
              dateiId: fdDateiId(
                fdAusDateiname(d.name)!.id,
                fdAusDateiname(d.name)!.stand ?? heute,
              ),
              name: d.name,
              groesse: d.inhalt.length,
            ),
        ];

    test('noch einmal dasselbe: nichts doppelt', () {
      final dateien = [
        datei('FD_101 Testware 260615.pdf', 'a'),
        datei('FD_102 Ohne Datum.pdf', 'b'),
      ];
      final plan = fdEinlesePlan(
        dateien: dateien,
        bezeichnungen: const {'FD_101': 'Testware', 'FD_102': 'Ohne Datum'},
        // Das PDF ohne Datum kam an einem anderen Tag.
        gespeichert: [
          gespeichert(dateien).first,
          (
            dateiId: 'fliessdiagramm:FD_102:2026-09-01',
            name: 'FD_102 Ohne Datum.pdf',
            groesse: pdf('b').length,
          ),
        ],
        heute: heute,
      );
      expect(plan.speichern, isEmpty);
      expect(plan.vorhanden, 2);
      expect(plan.anlegen, isEmpty);
      expect(plan.neuerStand, isEmpty);
      expect(plan.text, '2 waren schon da.');
    });

    test('ein neuer Stand bringt seine Bezeichnung mit', () {
      final alt = datei('FD_101 Testware 260615.pdf', 'a');
      final plan = fdEinlesePlan(
        dateien: [datei('FD_101 Testware natur 260901.pdf', 'b')],
        bezeichnungen: const {'FD_101': 'Eigener Name'},
        gespeichert: gespeichert([alt]),
        heute: heute,
      );
      expect(plan.neuerStand, ['FD_101']);
      expect(plan.umbenennen, [(id: 'FD_101', bezeichnung: 'Testware natur')]);
      expect(plan.text, '1 mit neuem Stand, 1 PDF gespeichert.');
    });

    test('eine ältere Fassung ändert die Bezeichnung nicht', () {
      final neu = datei('FD_101 Testware 260901.pdf', 'a');
      final plan = fdEinlesePlan(
        dateien: [datei('FD_101 Testware früher 260101.pdf', 'b')],
        bezeichnungen: const {'FD_101': 'Eigener Name'},
        gespeichert: gespeichert([neu]),
        heute: heute,
      );
      expect(plan.neuerStand, isEmpty);
      expect(plan.umbenennen, isEmpty);
      expect(plan.speichern.single.dateiId, 'fliessdiagramm:FD_101:2026-01-01');
    });

    test('von Hand angelegt, nun mit PDF', () {
      final plan = fdEinlesePlan(
        dateien: [datei('FD_101 Testware 260615.pdf', 'a')],
        bezeichnungen: const {'FD_101': 'Testware'},
        gespeichert: const [],
        heute: heute,
      );
      expect(plan.anlegen, isEmpty);
      expect(plan.neuerStand, ['FD_101']);
      // Gleicher Name: nichts umzubenennen.
      expect(plan.umbenennen, isEmpty);
    });

    test('zwei Dateien mit gleichem Stand: die zuletzt genannte gilt', () {
      final plan = fdEinlesePlan(
        dateien: [
          datei('FD_101 Testware 260615.pdf', 'a'),
          datei('FD_101 Testware korrigiert 260615.pdf', 'b'),
        ],
        bezeichnungen: const {},
        gespeichert: const [],
        heute: heute,
      );
      expect(plan.anlegen.single.bezeichnung, 'Testware korrigiert');
      expect(
        plan.speichern.single.datei.name,
        'FD_101 Testware korrigiert 260615.pdf',
      );
    });

    test('Meldungen', () {
      expect(const FdEinlesePlan().text, 'Keine Fließdiagramme gefunden.');
      final plan = fdEinlesePlan(
        dateien: [for (var i = 1; i <= 7; i++) datei('Scan $i.pdf', '$i')],
        bezeichnungen: const {},
        gespeichert: const [],
        heute: heute,
      );
      expect(
        plan.text,
        'Keine Fließdiagramme gefunden.\n'
        'Ohne Kennung wie „FD_001" am Anfang des Namens übersprungen: '
        'Scan 1.pdf, Scan 2.pdf, Scan 3.pdf, Scan 4.pdf, Scan 5.pdf '
        'und 2 weitere',
      );
    });
  });

  group('Mit der Datenbank', () {
    late AppDatabase db;
    late ProjektRepository repo;
    late EntwicklungDateienDienst dateien;
    late FliessdiagrammDienst dienst;
    final heute = DateTime(2026, 10, 1);

    setUp(() async {
      db = testDatenbank();
      repo = ProjektRepository(db);
      dateien = EntwicklungDateienDienst(db);
      dienst = FliessdiagrammDienst(db, dateien);
      // Der Datenschlüssel entsteht mit dem Passwort.
      await EntwicklungZugang(
        DbEntwicklungsSpeicher(db),
        iterationen: 1000,
        imHintergrund: false,
      ).festlegen('geheim123');
    });
    tearDown(() => db.close());

    Future<List<(String, String)>> liste() async => [
          for (final f in await repo.fliessdiagrammeBeobachten().first)
            (f.id, f.bezeichnung),
        ];

    test('einlesen, noch einmal, neuer Stand, löschen', () async {
      final schritte = <(int, int)>[];
      var plan = await dienst.einlesen(
        [
          datei('FD_102 Testware 260615.pdf', 'a'),
          datei('FD_101 Testware paniert 260731.pdf', 'b'),
          datei('FD_101 Testware 260615.pdf', 'c'),
          datei('Notiz.pdf', 'd'),
        ],
        heute: heute,
        fortschritt: (fertig, gesamt) => schritte.add((fertig, gesamt)),
      );
      expect(plan.anlegen, hasLength(2));
      expect(schritte, [(0, 3), (1, 3), (2, 3), (3, 3)]);
      expect(await liste(), [
        ('FD_101', 'Testware paniert'),
        ('FD_102', 'Testware'),
      ]);
      var fassungen = await dienst.fassungenBeobachten().first;
      expect(
        [for (final f in fassungen['FD_101']!) f.stand],
        [DateTime(2026, 7, 31), DateTime(2026, 6, 15)],
      );
      final neueste = fassungen['FD_101']!.first.datei;
      expect(await dateien.lesen(neueste.id), pdf('b'));
      expect(neueste.projektId, isNull);
      expect(neueste.mimeTyp, 'application/pdf');
      expect(neueste.name, 'FD_101 Testware paniert 260731.pdf');

      // Noch einmal dasselbe: nichts doppelt.
      plan = await dienst.einlesen(
        [datei('FD_101 Testware paniert 260731.pdf', 'b')],
        heute: heute,
      );
      expect(plan.vorhanden, 1);
      expect(plan.speichern, isEmpty);

      // Eine eigene Bezeichnung bleibt beim erneuten Einlesen ...
      await repo.fliessdiagrammSpeichern(id: 'FD_101', bezeichnung: 'Eigen');
      await dienst.einlesen(
        [datei('FD_101 Testware paniert 260731.pdf', 'b')],
        heute: heute,
      );
      expect((await liste()).first, ('FD_101', 'Eigen'));
      // ... bis ein neuer Stand kommt.
      plan = await dienst.einlesen(
        [datei('FD_101 Testware natur 260901.pdf', 'e')],
        heute: heute,
      );
      expect(plan.neuerStand, ['FD_101']);
      expect(await liste(), [
        ('FD_101', 'Testware natur'),
        ('FD_102', 'Testware'),
      ]);
      fassungen = await dienst.fassungenBeobachten().first;
      expect(fassungen['FD_101'], hasLength(3));

      // Löschen nimmt die PDFs des einen mit.
      await dienst.pdfsLoeschen('FD_101');
      fassungen = await dienst.fassungenBeobachten().first;
      expect(fassungen.keys, ['FD_102']);
      expect(await db.select(db.entwicklungDateiInhalte).get(), hasLength(1));
    });

    test('ein PDF von Hand anhängen', () async {
      await repo.fliessdiagrammSpeichern(id: 'FD_1', bezeichnung: 'Testware');
      await dienst.pdfHinzufuegen(
        'FD_1',
        'Scan.pdf',
        pdf('x'),
        heute: DateTime(2026, 10, 2, 15, 30),
      );
      await dienst.pdfHinzufuegen('FD_1', 'FD_1 Testware 20260105.pdf', pdf('y'));
      // Eine ähnliche Kennung bleibt beim Löschen unberührt.
      await dienst.pdfHinzufuegen('FDX1', 'Scan.pdf', pdf('z'), heute: heute);
      final f = (await dienst.fassungenBeobachten().first)['FD_1']!;
      expect(
        [for (final x in f) x.stand],
        [DateTime(2026, 10, 2), DateTime(2026, 1, 5)],
      );
      expect(await dateien.lesen(f.first.datei.id), pdf('x'));

      await dienst.pdfsLoeschen('FD_1');
      final rest = await dienst.fassungenBeobachten().first;
      expect(rest.keys, ['FDX1']);
    });

    test('der Projektbericht nennt Bezeichnung und Stand', () async {
      await dienst.einlesen(
        [datei('FD_101 Testware paniert 260731.pdf', 'b')],
        heute: heute,
      );
      final id = await repo.projektAnlegen(name: 'Testprodukt');
      await repo.projektAendern(
        id,
        const EntwicklungProjekteCompanion(fliessdiagramm: Value('FD_101')),
      );
      var b = await berichtLaden(db, dateien, (await repo.projekt(id))!);
      expect(b.fliessdiagramm, 'FD_101 · Testware paniert · Stand 31.07.2026');

      // Ohne Eintrag in der Liste und ohne PDF: nur die Kennung.
      await repo.projektAendern(
        id,
        const EntwicklungProjekteCompanion(fliessdiagramm: Value('FD_999')),
      );
      b = await berichtLaden(db, dateien, (await repo.projekt(id))!);
      expect(b.fliessdiagramm, 'FD_999');

      await repo.projektAendern(
        id,
        const EntwicklungProjekteCompanion(fliessdiagramm: Value(null)),
      );
      b = await berichtLaden(db, dateien, (await repo.projekt(id))!);
      expect(b.fliessdiagramm, isNull);
    });
  });
}
