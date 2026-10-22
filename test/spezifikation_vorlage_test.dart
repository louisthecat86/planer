import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
// `show Value`: drift bringt eine eigene Klasse `Column` mit.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/features/entwicklung/daten/dateien.dart';
import 'package:produktion_planer/features/entwicklung/daten/entwicklung_repository.dart';
import 'package:produktion_planer/features/entwicklung/entwicklung_zugang.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_repository.dart';
import 'package:produktion_planer/features/entwicklung/spezifikation/spez_angaben.dart';
import 'package:produktion_planer/features/entwicklung/spezifikation/spezifikation_dienst.dart';
import 'package:produktion_planer/features/entwicklung/spezifikation/spezifikation_werte.dart';
import 'package:produktion_planer/features/entwicklung/spezifikation/vorlage_einrichten.dart';
import 'package:produktion_planer/features/entwicklung/spezifikation/xlsx_blatt.dart';
import 'package:produktion_planer/features/entwicklung/spezifikation/xlsx_vorlage.dart';

import 'helpers/test_db.dart';

/// Tests für das Einrichten und Füllen einer Spezifikationsvorlage: ein
/// erfundenes Formblatt auf Deutsch und Englisch — Beschriftungen,
/// verbundene Zellen, Kontrollkästchen, Kopfzeile —, dazu die Angaben des
/// Projekts, und der Dienst mit der Datenbank. Keine echten
/// Firmenangaben.
void main() {
  group('Formblatt einrichten', () {
    test('deutsch: Felder neben den Beschriftungen, Kästchen, Kopfzeile', () {
      final e = vorlageEinrichten(formblatt());
      expect(e.schonEingerichtet, isFalse);
      expect(e.fehlend, [
        'naehrwert.energie_kcal',
        'naehrwert.kohlenhydrate',
        'naehrwert.zucker',
        'naehrwert.eiweiss',
      ]);
      expect(e.felder, {
        'gueltig_ab': 'J1',
        'kuerzel': 'J1',
        'artikelnummer': 'C5',
        'bezeichnung': 'C6',
        'sensorik.gewicht': 'C7',
        'toleranz': 'I7',
        'zutaten': 'C8',
        'hilfsstoff.1.name': 'C13',
        'hilfsstoff.1.quelle': 'H13',
        'hilfsstoff.2.name': 'C14',
        'hilfsstoff.2.quelle': 'H14',
        'sensorik.aussehen': 'C16',
        'sensorik.geschmack': 'C17',
        'naehrwert.energie_kj': 'H19',
        'naehrwert.fett': 'H20',
        'naehrwert.gesaettigte_fettsaeuren': 'H21',
        'naehrwert.salz': 'H22',
        'lagerung': 'D24',
        'haltbarkeit': 'D25',
        'allergen.gluten.ja': 'F28 (Kästchen)',
        'allergen.gluten.nein': 'G28 (Kästchen)',
        'allergen.gluten.spuren': 'H28 (Kästchen)',
        'allergen.gluten.quelle': 'I28',
        'allergen.eier.ja': 'F29 (Kästchen)',
        'allergen.eier.nein': 'G29 (Kästchen)',
        'allergen.eier.spuren': 'H29 (Kästchen)',
        'allergen.eier.quelle': 'I29',
        'allergen.senf.ja': 'F30 (Kästchen)',
        'allergen.senf.nein': 'G30 (Kästchen)',
        'allergen.senf.spuren': 'H30 (Kästchen)',
        'allergen.senf.quelle': 'I30',
        'hinweis.1': 'D32',
        'hinweis.2': 'D33',
        'verpackung.um.e2_kiste': 'B37 (Kästchen)',
        'verpackung.um.neutral': 'B38 (Kästchen)',
        'verpackung.um.bedruckt': 'E38 (Kästchen)',
        'verpackung.um.tara': 'B39',
        'verpackung.einzel.beutel': 'B42 (Kästchen)',
        'verpackung.einzel.anzahl': 'F42',
        'verpackung.einzel.schutzgas': 'B43 (Kästchen)',
        'verpackung.einzel.vakuum': 'D43 (Kästchen)',
        'verpackung.einzel.tara': 'B44',
        'artikelnummer (Kopfzeile)': 'Kopfzeile',
      });
      expect(e.kaestchen, 15);

      final blatt = XlsxBlatt(XlsxMappe.lesen(e.bytes), 'xl/worksheets/sheet1.xml');
      String text(String ref) {
        final o = zellortAus(ref)!;
        return blatt.zelle(o.zeile, o.spalte)?.text ?? '';
      }

      expect(text('C5'), '{{artikelnummer}}');
      expect(text('F28'), '{{allergen.gluten.ja}}');
      expect(
        text('J1'),
        'Spezifikation gültig ab {{gueltig_ab}}\nKürzel {{kuerzel}}\n',
      );
      // Feste Texte bleiben: der Satz über die übrigen Allergene, die
      // Bemerkung.
      expect(text('A31'), startsWith('Die Allergene Krebstiere'));
      expect(text('D34'), 'gewisse Abweichungen möglich');
      expect(platzhalterIn(e.bytes), contains('artikelnummer'));
      // Die übrigen Teile der Mappe bleiben, wie sie waren.
      expect(datei(e.bytes, 'xl/styles.xml'), datei(formblatt(), 'xl/styles.xml'));
      expect(
        datei(e.bytes, 'xl/drawings/vmlDrawing1.vml'),
        datei(formblatt(), 'xl/drawings/vmlDrawing1.vml'),
      );
    });

    test('englisch: dieselben Felder, „xx" wird das Kürzel', () {
      final e = vorlageEinrichten(formblatt(englisch: true));
      expect(e.felder['artikelnummer'], 'C5');
      expect(e.felder['bezeichnung'], 'C6');
      expect(e.felder['toleranz'], 'I7');
      expect(e.felder['zutaten'], 'C8');
      expect(e.felder['hilfsstoff.2.quelle'], 'H14');
      expect(e.felder['sensorik.aussehen'], 'C16');
      expect(e.felder['naehrwert.gesaettigte_fettsaeuren'], 'H21');
      expect(e.felder['lagerung'], 'D24');
      expect(e.felder['haltbarkeit'], 'D25');
      expect(e.felder['allergen.gluten.ja'], 'F28 (Kästchen)');
      expect(e.felder['allergen.eier.spuren'], 'H29 (Kästchen)');
      expect(e.felder['allergen.senf.quelle'], 'I30');
      expect(e.felder['hinweis.1'], 'D32');
      expect(e.felder['hinweis.2'], 'D33');
      expect(e.felder['verpackung.um.bedruckt'], 'E38 (Kästchen)');
      expect(e.felder['verpackung.einzel.anzahl'], 'F42');
      expect(e.felder['verpackung.einzel.vakuum'], 'D43 (Kästchen)');
      expect(e.kaestchen, 15);
      final blatt = XlsxBlatt(XlsxMappe.lesen(e.bytes), 'xl/worksheets/sheet1.xml');
      expect(
        blatt.zelle(0, 9)!.text,
        'specification valid from {{gueltig_ab}}\n{{kuerzel}}\n',
      );
      // Beispielwerte in den Feldern werden ersetzt.
      expect(blatt.zelle(23, 3)!.text, '{{lagerung}}');
    });

    test('eine Vorlage mit Platzhaltern bleibt, wie sie ist', () {
      final schon = vorlageEinrichten(formblatt()).bytes;
      final e = vorlageEinrichten(schon);
      expect(e.schonEingerichtet, isTrue);
      expect(e.ergaenzt, isFalse);
      expect(e.felder, isEmpty);
      expect(e.bytes, same(schon));
    });

    test('eine teils eingerichtete Vorlage wird ergänzt', () {
      // Von Hand: der Fettgehalt an seinem Platz, neben der Bezeichnung
      // bewusst der Projektname.
      final teils = mitZellen(formblatt(), {
        'H20': '{{naehrwert.fett}}',
        'C6': '{{projekt}}',
      });
      final e = vorlageEinrichten(teils);
      expect(e.vorhanden, {'naehrwert.fett', 'projekt'});
      expect(e.ergaenzt, isTrue);
      expect(e.schonEingerichtet, isFalse);
      // Was fehlte, kommt dazu …
      expect(e.felder['artikelnummer'], 'C5');
      expect(e.felder['zutaten'], 'C8');
      expect(e.felder['lagerung'], 'D24');
      // … was schon da war, bleibt, wo es ist.
      expect(e.felder.containsKey('naehrwert.fett'), isFalse);
      expect(e.felder.containsKey('bezeichnung'), isFalse);
      expect(e.fehlend, contains('bezeichnung'));
      expect(e.fehlend, isNot(contains('naehrwert.fett')));
      final blatt =
          XlsxBlatt(XlsxMappe.lesen(e.bytes), 'xl/worksheets/sheet1.xml');
      expect(blatt.zelle(5, 2)!.text, '{{projekt}}');
      expect(blatt.zelle(19, 7)!.text, '{{naehrwert.fett}}');
      expect(blatt.zelle(4, 2)!.text, '{{artikelnummer}}');
      // Ein zweites Mal: nichts mehr zu tun.
      expect(vorlageEinrichten(e.bytes).schonEingerichtet, isTrue);
    });

    test('keine Excel-Mappe: ein verständlicher Fehler', () {
      expect(
        () => vorlageEinrichten(Uint8List.fromList(utf8.encode('kein zip'))),
        throwsFormatException,
      );
    });

    test('Beschriftungen vereinfacht', () {
      expect(beschriftungNorm('Stückgewicht [g]:'), 'stückgewicht');
      expect(beschriftungNorm('    davon Zucker in g'), 'zucker');
      expect(
        beschriftungNorm('Verarbeitungshilfsstoffe: (deklarationsfrei)'),
        'verarbeitungshilfsstoffe',
      );
      expect(beschriftungNorm('Salz in g '), 'salz');
      expect(beschriftungNorm('Brennwert kJ'), 'brennwert kj');
      expect(beschriftungNorm('Tolerance [g]:'), 'tolerance');
    });
  });

  group('Eingerichtetes Formblatt füllen', () {
    test('Werte, Haken, leere Zellen unter den Kästchen, Kopfzeile', () {
      final vorlage = vorlageEinrichten(formblatt()).bytes;
      final werte = {
        for (final n in platzhalterIn(vorlage)) n: '',
        'artikelnummer': '4711',
        'gueltig_ab': '05.03.2026',
        'kuerzel': 'TE',
        'zutaten': 'Schweinefleisch (80 %), WEIZENmehl',
        'allergen.gluten.ja': 'X',
        'allergen.gluten.quelle': 'Weizenmehl',
        'allergen.eier.nein': 'X',
        'allergen.senf.spuren': 'X',
        'verpackung.um.e2_kiste': 'X',
        'verpackung.einzel.vakuum': 'X',
        'hinweis.1': 'Vor dem Verzehr durcherhitzen.',
      };
      final e = vorlageFuellen(vorlage, werte);
      expect(e.unbekannt, isEmpty);
      expect(platzhalterIn(e.bytes), isEmpty);
      // Angekreuzt: drei bei den Allergenen, zwei bei der Verpackung.
      expect(e.kaestchen, 5);

      final mappe = XlsxMappe.lesen(e.bytes);
      final blatt = XlsxBlatt(mappe, 'xl/worksheets/sheet1.xml');
      String text(String ref) {
        final o = zellortAus(ref)!;
        return blatt.zelle(o.zeile, o.spalte)?.text ?? '';
      }

      expect(text('C5'), '4711');
      expect(text('C8'), 'Schweinefleisch (80 %), WEIZENmehl');
      expect(text('I28'), 'Weizenmehl');
      expect(text('J1'), 'Spezifikation gültig ab 05.03.2026\nKürzel TE\n');
      // Unter den Kästchen steht nichts mehr.
      expect(text('F28'), '');
      expect(text('G28'), '');
      expect(text('B37'), '');

      final an = {
        for (final k in blatt.kaestchen)
          if (k.angehakt) zellName(k.zeile, k.spalte),
      };
      expect(an, {'F28', 'G29', 'H30', 'B37', 'D43'});
      // Die neueren Eigenschaften der Kästchen sagen dasselbe.
      for (final k in blatt.kaestchen) {
        final prop = mappe.text(k.ctrlPropPfad!)!;
        expect(prop.contains('checked="Checked"'), k.angehakt, reason: '$k');
      }

      final kopf = RegExp('<oddHeader>(.*?)</oddHeader>', dotAll: true)
          .firstMatch(mappe.text('xl/worksheets/sheet1.xml')!)![1]!;
      expect(xmlUnescape(kopf), contains('&K0020604711&R'));
    });

    test('ein zweites Füllen nimmt alte Haken weg', () {
      final vorlage = vorlageEinrichten(formblatt()).bytes;
      final alle = {for (final n in platzhalterIn(vorlage)) n: 'X'};
      final voll = vorlageFuellen(vorlage, alle);
      expect(
        XlsxBlatt(XlsxMappe.lesen(voll.bytes), 'xl/worksheets/sheet1.xml')
            .kaestchen
            .every((k) => k.angehakt),
        isTrue,
      );
      // Dieselbe eingerichtete Vorlage mit leeren Werten: kein Haken.
      final leer = vorlageFuellen(
        vorlage,
        {for (final n in platzhalterIn(vorlage)) n: ''},
      );
      expect(
        XlsxBlatt(XlsxMappe.lesen(leer.bytes), 'xl/worksheets/sheet1.xml')
            .kaestchen
            .any((k) => k.angehakt),
        isFalse,
      );
    });

    test('ein Platzhalter ohne Kästchen bekommt das „X" als Text', () {
      final vorlage = kleineMappe(
        '<si><t>{{allergen.gluten.ja}}</t></si>',
      );
      final e = vorlageFuellen(vorlage, {'allergen.gluten.ja': 'X'});
      expect(e.kaestchen, 0);
      expect(datei(e.bytes, 'xl/sharedStrings.xml'), contains('>X</t>'));
    });

    test('Format eines Textstücks bleibt, wenn der Platzhalter darin liegt',
        () {
      final vorlage = kleineMappe(
        '<si><r><rPr><b/></rPr><t>Nr. </t></r>'
        '<r><rPr><i/></rPr><t>{{artikelnummer}}</t></r></si>',
      );
      final e = vorlageFuellen(vorlage, {'artikelnummer': '4711'});
      expect(
        datei(e.bytes, 'xl/sharedStrings.xml'),
        contains(
          '<si><r><rPr><b/></rPr><t>Nr. </t></r><r><rPr><i/></rPr>'
          '<t xml:space="preserve">4711</t></r></si>',
        ),
      );
    });
  });

  group('Kopf- und Fußzeile', () {
    test('„&" wird verdoppelt, eine Ziffer hinter der Schriftgröße abgesetzt',
        () {
      String? wert(String name) => switch (name) {
            'kunde' => 'Müller & Söhne',
            'artikelnummer' => '4711',
            _ => null,
          };
      expect(
        kopfFussErsetzen('&C{{kunde}}&R&P', wert),
        '&CMüller && Söhne&R&P',
      );
      expect(kopfFussErsetzen('&8{{artikelnummer}}', wert), '&8 4711');
      expect(kopfFussErsetzen('&&8{{artikelnummer}}', wert), '&&84711');
      expect(kopfFussErsetzen('&K002060{{artikelnummer}}', wert), '&K0020604711');
      expect(kopfFussErsetzen('Nr. {{tippfehler}}', wert), 'Nr. {{tippfehler}}');
    });

    test('Platzhalter in der Kopfzeile werden gefunden und ersetzt', () {
      final vorlage = kleineMappe(
        '<si><t>leer</t></si>',
        kopf: '<headerFooter><oddHeader>&amp;LFormblatt&amp;C{{artikelnummer}}'
            '</oddHeader><oddFooter>&amp;R{{kunde}}</oddFooter></headerFooter>',
      );
      expect(platzhalterIn(vorlage), {'artikelnummer', 'kunde'});
      final e = vorlageFuellen(vorlage, {
        'artikelnummer': 'A&B',
        'kunde': 'Muster <GmbH>',
      });
      final blatt = datei(e.bytes, 'xl/worksheets/sheet1.xml');
      expect(blatt, contains('<oddHeader>&amp;LFormblatt&amp;CA&amp;&amp;B</oddHeader>'));
      expect(blatt, contains('<oddFooter>&amp;RMuster &lt;GmbH&gt;</oddFooter>'));
    });
  });

  group('Zellen und Bezüge', () {
    test('Bezüge in beide Richtungen', () {
      expect(zellortAus('C5'), (zeile: 4, spalte: 2));
      expect(zellortAus(r'$AA$10'), (zeile: 9, spalte: 26));
      expect(zellortAus('5C'), isNull);
      expect(zellName(4, 2), 'C5');
      expect(zellName(9, 26), 'AA10');
      expect(Bereich.aus('A1:D2').toString(), 'A1:D2');
      expect(Bereich.aus('B3')!.enthaelt(2, 1), isTrue);
    });

    test('eine fehlende Zelle und eine fehlende Zeile entstehen in Ordnung',
        () {
      const xml = '<worksheet><sheetData><row r="2"><c r="A2" s="1"/>'
          '<c r="D2" s="1"/></row><row r="5"><c r="A5"/></row></sheetData>'
          '</worksheet>';
      final a = zelleSetzen(xml, 'B2', 'x');
      expect(
        a,
        contains('<c r="A2" s="1"/><c r="B2" t="inlineStr"><is>'
            '<t xml:space="preserve">x</t></is></c><c r="D2" s="1"/>'),
      );
      final b = zelleSetzen(xml, 'C3', 'y');
      expect(b, contains('</row><row r="3"><c r="C3" t="inlineStr">'));
      expect(b.indexOf('r="3"'), lessThan(b.indexOf('r="5"')));
      final c = zelleSetzen(xml, 'D2', 'z & a');
      expect(
        c,
        contains('<c r="D2" s="1" t="inlineStr"><is>'
            '<t xml:space="preserve">z &amp; a</t></is></c>'),
      );
      expect(zelleLeeren(c, 'D2'), contains('<c r="D2" s="1"/>'));
    });
  });

  group('Angaben des Projekts', () {
    test('JSON hin und zurück, leer ergibt null', () {
      const a = SpezAngaben(
        bezeichnung: 'Frikadelle fein, gebraten',
        toleranz: '± 5',
        lagerung: 'gekühlt',
        haltbarkeit: '21',
        hinweise: 'Erst durcherhitzen.\n\nNicht wieder einfrieren.',
        spuren: {'sellerie', 'senf'},
        verpackung: Verpackung(
          um: {'e2_kiste'},
          karton: 'neutral',
          umFuellung: 'gewogen',
          umTara: '850',
          einzel: {'beutel'},
          anzahl: '4',
          atmosphaere: 'schutzgas',
          einzelFuellung: 'gezaehlt',
          einzelMaterial: 'PA/PE',
        ),
      );
      final zurueck = SpezAngaben.aus(a.alsJson());
      expect(zurueck.toJson(), a.toJson());
      expect(zurueck.bezeichnung, 'Frikadelle fein, gebraten');
      expect(
        const SpezAngaben(bezeichnung: ' Nur sie ').alsJson(),
        '{"bezeichnung":"Nur sie"}',
      );
      expect(zurueck.hinweisZeilen, [
        'Erst durcherhitzen.',
        'Nicht wieder einfrieren.',
      ]);
      expect(const SpezAngaben().alsJson(), isNull);
      expect(SpezAngaben.aus(null).leer, isTrue);
      expect(SpezAngaben.aus('kaputt').leer, isTrue);
      expect(SpezAngaben.aus('[1, 2]').leer, isTrue);
      // Eine Auswahl zurücknehmen.
      expect(
        a.verpackung.kopie(karton: '').toJson().containsKey('karton'),
        isFalse,
      );
    });
  });

  group('Lücken und Vorschau', () {
    test('kein Platz, leer geblieben, Stand ohne Zutaten', () {
      expect(
        spezLuecken(
          platzhalter: {
            'artikelnummer',
            'bezeichnung',
            'zutaten',
            'lagerung',
            'haltbarkeit',
          },
          werte: {
            'artikelnummer': 'T-1',
            'bezeichnung': 'Testware',
            'zutaten': 'Schweinefleisch',
            'lagerung': 'kühl',
            'haltbarkeit': '21 Tage',
          },
        ),
        isEmpty,
      );
      expect(
        spezLuecken(
          platzhalter: {'artikelnummer', 'zutaten'},
          werte: {'artikelnummer': ' ', 'zutaten': ''},
        ),
        [
          'Die Vorlage hat keinen Platz für Artikelbezeichnung, '
              'Lagerbedingungen und Haltbarkeit — trag dort Platzhalter wie '
              '{{artikelnummer}} ein oder wähl die Vorlage noch einmal '
              '(„Ersetzen…").',
          // Die Artikelnummer steht in den Stammdaten.
          'Leer geblieben: Artikelnummer — einzutragen in der Übersicht bei '
              'den Stammdaten.',
          'Der Rezepturstand hat keine Zutaten — die Zutatenliste bleibt '
              'leer.',
        ],
      );
    });

    test('Texte der Vorschau', () {
      const w = {
        'naehrwert.energie': '1050 kJ / 251 kcal',
        'naehrwert.fett': '13',
        'naehrwert.gesaettigte_fettsaeuren': '2,1',
        'naehrwert.kohlenhydrate': '14',
        'naehrwert.zucker': '0,8',
        'naehrwert.eiweiss': '19',
        'naehrwert.salz': '1,3',
        'hilfsstoff.1.name': 'Siliziumdioxid',
        'hilfsstoff.1.quelle': 'Gewürzmischung',
        'hilfsstoff.2.name': 'Trennmittel',
        'hilfsstoff.2.quelle': '',
        'hilfsstoff.3.name': '',
        'sensorik.aussehen': 'goldbraun',
        'sensorik.geruch': ' ',
        'sensorik.geschmack': 'würzig',
        'allergen.senf.spuren': 'X',
        'allergen.sellerie.spuren': '',
      };
      expect(
        vorschauNaehrwerte(w),
        'Energie 1050 kJ / 251 kcal · Fett 13 g · davon gesättigte '
        'Fettsäuren 2,1 g · Kohlenhydrate 14 g · davon Zucker 0,8 g · '
        'Eiweiß 19 g · Salz 1,3 g',
      );
      expect(
        vorschauHilfsstoffe(w),
        'Siliziumdioxid (aus Gewürzmischung), Trennmittel',
      );
      expect(
        vorschauHilfsstoffe(
          const {'hilfsstoff.1.name': 'Keine', 'hilfsstoff.1.quelle': '-'},
        ),
        'Keine',
      );
      expect(vorschauSensorik(w), 'Optik: goldbraun\nGeschmack: würzig');
      expect(vorschauSensorik(const {}), isEmpty);
      expect(vorschauSpuren(w), 'Senf');
    });
  });

  group('Mit der Datenbank', () {
    late AppDatabase db;
    late EntwicklungRepository rezepte;
    late ProjektRepository projekte;
    late SpezifikationDienst dienst;

    setUp(() async {
      db = testDatenbank();
      rezepte = EntwicklungRepository(db);
      projekte = ProjektRepository(db);
      dienst = SpezifikationDienst(
        db,
        EntwicklungDateienDienst(db),
        uebersetzer: (texte, schluessel) async => [
          for (final t in texte) 'EN[$t]',
        ],
      );
      // Der Datenschlüssel entsteht mit dem Passwort.
      await EntwicklungZugang(
        DbEntwicklungsSpeicher(db),
        iterationen: 1000,
        imHintergrund: false,
      ).festlegen('geheim123');
    });
    tearDown(() => db.close());

    test('ein Formblatt ohne Platzhalter wird beim Speichern eingerichtet',
        () async {
      final g = await dienst.vorlageSpeichern(
        SpezSprache.de,
        'Formblatt.xlsx',
        formblatt(),
      );
      final e = g.einrichtung!;
      expect(e.kaestchen, 15);
      expect(
        g.platzhalter,
        containsAll([
          'artikelnummer',
          'kuerzel',
          'allergen.senf.spuren',
          'verpackung.einzel.vakuum',
        ]),
      );
      // Gespeichert ist die eingerichtete Mappe.
      expect(await dienst.vorlageInhalt(SpezSprache.de), e.bytes);
      expect((await dienst.vorlage(SpezSprache.de))!.name, 'Formblatt.xlsx');

      // Noch einmal gewählt: schon eingerichtet, nichts zu tun.
      final noch = await dienst.vorlageSpeichern(
        SpezSprache.de,
        'Formblatt.xlsx',
        e.bytes,
      );
      expect(noch.einrichtung, isNull);
      expect(noch.platzhalter, g.platzhalter);
    });

    test('erstellen: eine Vorlage von früher wird ergänzt, Lücken gemeldet',
        () async {
      // Eine Vorlage aus einer früheren Fassung: gespeichert, wie sie war —
      // ohne Platzhalter.
      await EntwicklungDateienDienst(db).speichern(
        id: spezVorlageId(SpezSprache.de),
        name: 'Formblatt.xlsx',
        inhalt: formblatt(),
        mimeTyp: kXlsxMime,
      );
      expect(
        platzhalterIn((await dienst.vorlageInhalt(SpezSprache.de))!),
        isEmpty,
      );
      final id = await projekte.projektAnlegen(name: 'Frikadelle Testart');
      await projekte.projektAendern(
        id,
        EntwicklungProjekteCompanion(
          spezifikation: Value(
            const SpezAngaben(bezeichnung: 'Frikadelle fein, gebraten')
                .alsJson(),
          ),
        ),
      );
      final rezeptur = await rezepte.rezepturAnlegen(
        name: 'Frikadelle',
        projektId: id,
      );
      final fleisch = await rezepte.zutatAnlegen(
        const EntwicklungZutatenCompanion(
          name: Value('Schweinefleisch'),
          istFleisch: Value(true),
          tierart: Value('schwein'),
          fett: Value(20),
          eiweiss: Value(18),
        ),
      );
      final v = (await rezepte.neuesteVersion(rezeptur))!;
      await rezepte.positionHinzufuegen(v.id, zutatId: fleisch, mengeKg: 10);

      Future<SpezifikationErgebnis> erstellen() async => dienst.erstellen(
            projekt: (await projekte.projekt(id))!,
            versionId: v.id,
            sprache: SpezSprache.de,
            datum: DateTime(2026, 3, 5),
          );

      final e = await erstellen();
      expect(
        e.hinweise.first,
        startsWith(
          'Die Vorlage war noch nicht ganz eingerichtet — die App hat ',
        ),
      );
      expect(
        e.hinweise,
        containsAll([
          'Leer geblieben: Artikelnummer — einzutragen in der Übersicht bei '
              'den Stammdaten.',
          'Leer geblieben: Lagerbedingungen und Haltbarkeit — einzutragen im '
              'Reiter „Produkt" bei „Angaben".',
        ]),
      );
      // Die eigene Bezeichnung — auch im Dateinamen.
      expect(e.dateiname, 'Frikadelle fein_ gebraten_Spezifikation.xlsx');
      final blatt =
          XlsxBlatt(XlsxMappe.lesen(e.bytes), 'xl/worksheets/sheet1.xml');
      expect(blatt.zelle(5, 2)!.text, 'Frikadelle fein, gebraten');
      expect(blatt.zelle(7, 2)!.text, contains('Schweinefleisch'));
      // Gemerkt: Die gespeicherte Vorlage hat jetzt ihre Platzhalter.
      expect(
        platzhalterIn((await dienst.vorlageInhalt(SpezSprache.de))!),
        containsAll(['artikelnummer', 'bezeichnung', 'zutaten']),
      );
      expect((await dienst.vorlage(SpezSprache.de))!.name, 'Formblatt.xlsx');

      // Beim nächsten Mal gibt es nichts mehr zu ergänzen.
      final noch = await erstellen();
      expect(
        noch.hinweise.where((h) => h.startsWith('Die Vorlage war')),
        isEmpty,
      );
    });

    test('erstellen: Angaben, Kreuze, Kürzel und Hinweise', () async {
      final id = await projekte.projektAnlegen(
        name: 'Frikadelle Testart',
        artikelnummer: 'T-200',
      );
      await projekte.projektAendern(
        id,
        EntwicklungProjekteCompanion(
          spezifikation: Value(
            const SpezAngaben(
              toleranz: '± 5',
              lagerung: 'gekühlt bei +2 °C bis +7 °C',
              haltbarkeit: '21',
              hinweise: 'Vor dem Verzehr durcherhitzen.\n'
                  'Nicht wieder einfrieren.\nKühl lagern.',
              spuren: {'senf'},
              verpackung: Verpackung(
                um: {'e2_kiste'},
                karton: 'neutral',
                umTara: '850',
                einzel: {'beutel'},
                anzahl: '4',
                atmosphaere: 'vakuum',
              ),
            ).alsJson(),
          ),
        ),
      );
      final rezeptur = await rezepte.rezepturAnlegen(
        name: 'Frikadelle Testart',
        projektId: id,
      );
      final fleisch = await rezepte.zutatAnlegen(
        const EntwicklungZutatenCompanion(
          name: Value('Schweinefleisch'),
          istFleisch: Value(true),
          tierart: Value('schwein'),
          fett: Value(20),
          eiweiss: Value(18),
        ),
      );
      final mehl = await rezepte.zutatAnlegen(
        const EntwicklungZutatenCompanion(
          name: Value('Weizenmehl'),
          allergene: Value('gluten'),
          kohlenhydrate: Value(70),
        ),
      );
      final milch = await rezepte.zutatAnlegen(
        const EntwicklungZutatenCompanion(
          name: Value('Milchpulver'),
          allergene: Value('milch'),
          eiweiss: Value(30),
        ),
      );
      final v = (await rezepte.neuesteVersion(rezeptur))!;
      await rezepte.positionHinzufuegen(v.id, zutatId: fleisch, mengeKg: 80);
      await rezepte.positionHinzufuegen(v.id, zutatId: mehl, mengeKg: 15);
      await rezepte.positionHinzufuegen(v.id, zutatId: milch, mengeKg: 5);
      await rezepte.versionAbschliessen(v.id);
      await dienst.vorlageSpeichern(
        SpezSprache.de,
        'Formblatt.xlsx',
        formblatt(),
      );
      await dienst.kuerzelSpeichern(' TE ');
      expect(await dienst.kuerzel(), 'TE');

      final e = await dienst.erstellen(
        projekt: (await projekte.projekt(id))!,
        versionId: v.id,
        sprache: SpezSprache.de,
        datum: DateTime(2026, 3, 5),
        kuerzel: await dienst.kuerzel(),
      );
      expect(e.unbekannt, isEmpty);
      // Gluten ja, Eier nein, Senf Spuren; E2-Kiste, neutral, Beutel,
      // Vakuum.
      expect(e.kaestchen, 7);
      expect(e.hinweise, [
        'Die Rezeptur enthält Milch — die Vorlage hat dafür keine Zeile in '
            'der Allergentabelle.',
        'Es gibt 3 Produkthinweise, die Vorlage hat Platz für 2 — die '
            'übrigen fehlen.',
      ]);

      final mappe = XlsxMappe.lesen(e.bytes);
      final blatt = XlsxBlatt(mappe, 'xl/worksheets/sheet1.xml');
      String text(String ref) {
        final o = zellortAus(ref)!;
        return blatt.zelle(o.zeile, o.spalte)?.text ?? '';
      }

      expect(text('C5'), 'T-200');
      expect(text('J1'), 'Spezifikation gültig ab 05.03.2026\nKürzel TE\n');
      expect(text('I7'), '± 5');
      expect(text('D24'), 'gekühlt bei +2 °C bis +7 °C');
      expect(text('D25'), '21 Tage');
      expect(text('I28'), 'Weizenmehl');
      expect(text('D32'), 'Vor dem Verzehr durcherhitzen.');
      expect(text('D33'), 'Nicht wieder einfrieren.');
      expect(text('B39'), '850');
      expect(text('F42'), '4');
      expect(
        {
          for (final k in blatt.kaestchen)
            if (k.angehakt) zellName(k.zeile, k.spalte),
        },
        {'F28', 'G29', 'H30', 'B37', 'B38', 'B42', 'D43'},
      );
      expect(
        xmlUnescape(
          RegExp('<oddHeader>(.*?)</oddHeader>', dotAll: true)
              .firstMatch(mappe.text('xl/worksheets/sheet1.xml')!)![1]!,
        ),
        contains('&K002060T-200&R'),
      );

      // Leer gespeichert ist das Kürzel weg.
      await dienst.kuerzelSpeichern('');
      expect(await dienst.kuerzel(), isNull);
    });
  });
}

/// Eine Datei der Mappe als Text.
String datei(Uint8List xlsx, String pfad) => utf8.decode(
      ZipDecoder().decodeBytes(xlsx).findFile(pfad)!.content as List<int>,
    );

/// Eine kleine Mappe von Hand: ein geteilter Text in A1, auf Wunsch mit
/// Kopf- und Fußzeile.
Uint8List kleineMappe(String geteilt, {String kopf = ''}) {
  final archiv = Archive();
  void neu(String pfad, String inhalt) {
    final bytes = utf8.encode(inhalt);
    archiv.addFile(ArchiveFile(pfad, bytes.length, bytes));
  }

  neu('xl/workbook.xml', '<workbook><sheets/></workbook>');
  neu('xl/sharedStrings.xml', '<sst count="1">$geteilt</sst>');
  neu(
    'xl/worksheets/sheet1.xml',
    '<worksheet><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c></row>'
        '</sheetData>$kopf</worksheet>',
  );
  return Uint8List.fromList(ZipEncoder().encode(archiv)!);
}

/// Ein erfundenes Formblatt einer Spezifikation: Beschriftungen links,
/// verbundene Wertfelder rechts, eine Allergentabelle und eine Verpackung
/// mit Kontrollkästchen, ein Datumsfeld oben rechts und die Artikelnummer
/// in der Kopfzeile.
Uint8List formblatt({bool englisch = false}) {
  final en = englisch;
  final geteilt = <String>[];
  final zellen = <int, List<(int, String)>>{};
  final verbunden = <String>[];

  void zelle(String ref, {String? text, String? bis}) {
    final o = zellortAus(ref)!;
    final String xml;
    if (text == null) {
      xml = '<c r="$ref" s="1"/>';
    } else {
      geteilt.add(text);
      xml = '<c r="$ref" s="1" t="s"><v>${geteilt.length - 1}</v></c>';
    }
    zellen.putIfAbsent(o.zeile + 1, () => []).add((o.spalte, xml));
    if (bis != null) verbunden.add('$ref:$bis');
  }

  // Beschriftung und Feld daneben.
  void paar(
    String ref,
    String bis,
    String text,
    String wert,
    String wertBis, {
    String? beispiel,
  }) {
    zelle(ref, text: text, bis: bis == ref ? null : bis);
    zelle(wert, text: beispiel, bis: wertBis == wert ? null : wertBis);
  }

  zelle(
    'J1',
    text: en
        ? 'specification valid from xx.xx.xxxx\nxx\n'
        : 'Spezifikation gültig ab xx.xx.xxxx\nKürzel\n',
    bis: 'K1',
  );
  paar('A5', 'B5', en ? 'Article number:' : 'Artikelnummer:', 'C5', 'K5');
  paar('A6', 'B6', en ? 'Article:' : 'Artikelbezeichnung:', 'C6', 'K6');
  paar('A7', 'B7', en ? 'Unit weight [g]:' : 'Stückgewicht [g]:', 'C7', 'E7');
  paar('F7', 'H7', en ? 'Tolerance [g]:' : 'Toleranz [g]:', 'I7', 'K7');
  paar('A8', 'B8', en ? 'Ingredients:' : 'Zutaten:', 'C8', 'K10');
  zelle('C12', text: en ? 'excipient' : 'Hilfsstoff', bis: 'G12');
  zelle('H12', text: en ? 'source' : 'Ursprungszutat', bis: 'J12');
  zelle(
    'A13',
    text: en
        ? 'Technical excipients: (declaration-free)'
        : 'Verarbeitungshilfsstoffe: (deklarationsfrei)',
    bis: 'B14',
  );
  for (final z in [13, 14]) {
    zelle('C$z', bis: 'G$z');
    zelle('H$z', bis: 'J$z');
  }
  paar('A16', 'A16', en ? 'Visual appearance' : 'Optik', 'C16', 'G16');
  paar('A17', 'A17', en ? 'Taste' : 'Geschmack', 'C17', 'G17');
  paar('C19', 'G19', en ? 'Energy kJ' : 'Brennwert kJ', 'H19', 'I19');
  paar('C20', 'G20', en ? 'Fat in g' : 'Fett in g', 'H20', 'I20');
  paar(
    'C21',
    'G21',
    en ? '    Saturated fat in g' : '    davon gesättigte Fettsäuren in g',
    'H21',
    'I21',
  );
  paar('C22', 'G22', en ? 'Salt in g ' : 'Salz in g ', 'H22', 'I22');
  paar(
    'A24',
    'C24',
    en ? 'Transport and storage conditions:' : 'Transport- und Lagerbedingungen:',
    'D24',
    'K24',
    beispiel: en ? '< -18°C' : null,
  );
  paar(
    'A25',
    'C25',
    en ? 'Best before date:' : 'Mindesthaltbarkeitsdatum:',
    'D25',
    'K25',
  );
  zelle('A27', text: en ? '' : 'Allergene gemäß 1169/2011', bis: 'E27');
  zelle('F27', text: en ? 'yes' : 'ja');
  zelle('G27', text: en ? 'no' : 'nein');
  zelle('H27', text: en ? 'traces' : 'Spuren');
  zelle('I27', text: en ? 'source' : 'Allergenursprung', bis: 'K27');
  final allergene = en
      ? [
          'Cereals containing gluten and products thereof',
          'Eggs and products thereof',
          'Mustard and products thereof',
        ]
      : [
          'Glutenhaltiges Getreide und Getreideerzeugnisse',
          'Eier und Eiererzeugnisse',
          'Senf- und Senferzeugnisse',
        ];
  for (var i = 0; i < allergene.length; i++) {
    final z = 28 + i;
    zelle('A$z', text: allergene[i], bis: 'E$z');
    zelle('F$z');
    zelle('G$z');
    zelle('H$z');
    zelle('I$z', bis: 'K$z');
  }
  zelle(
    'A31',
    text: en
        ? 'The allergens crustaceans, fish and peanuts have not been included.'
        : 'Die Allergene Krebstiere und Krebstiererzeugnisse, Fisch und '
            'Erdnüsse sind nicht Rezepturbestandteil.',
    bis: 'K31',
  );
  paar(
    'A32',
    'C32',
    en ? 'Product comments:' : 'Produkthinweise:',
    'D32',
    'K32',
    beispiel: en ? 'Heat thoroughly!' : null,
  );
  zelle('A33', bis: 'C33');
  zelle('D33', bis: 'K33');
  paar(
    'A34',
    'C34',
    en ? 'Note:' : 'Bemerkung:',
    'D34',
    'K34',
    beispiel: en ? 'Certain deviations possible' : 'gewisse Abweichungen möglich',
  );
  zelle('A36', text: en ? 'Secondary packaging' : 'Umverpackung');
  zelle('A37', text: en ? 'E2 Euro box' : 'E2 Kiste');
  zelle('B37');
  zelle('A38', text: en ? 'neutral cardboard box' : 'Neutraler Karton');
  zelle('B38');
  zelle('C38', text: en ? 'Muster brand' : 'Muster Karton', bis: 'D38');
  zelle('E38');
  paar(
    'A39',
    'A39',
    en ? 'tare weight [kg]' : 'Taragewicht [g]',
    'B39',
    'E39',
    beispiel: en ? '1.15' : null,
  );
  zelle('A41', text: en ? 'Primary packaging' : 'Einzelverpackung');
  zelle('A42', text: en ? 'bag' : 'Beutel');
  zelle('B42');
  paar(
    'C42',
    'E42',
    en ? 'number of bags per box' : 'Anzahl Beutel je Karton',
    'F42',
    'G42',
  );
  zelle('A43', text: en ? 'modified atmosphere' : 'Schutzgasatmosphäre');
  zelle('B43');
  zelle('C43', text: en ? 'vacuum' : 'Vakuum');
  zelle('D43');
  paar('A44', 'A44', en ? 'tare weight [g]' : 'Taragewicht [g]', 'B44', 'D44');

  // Die Kontrollkästchen: drei je Allergen, sechs bei der Verpackung.
  final kaestchen = [
    for (final z in [28, 29, 30]) ...['F$z', 'G$z', 'H$z'],
    'B37',
    'B38',
    'E38',
    'B42',
    'B43',
    'D43',
  ];
  final vml = StringBuffer(
    '<xml xmlns:v="urn:schemas-microsoft-com:vml" '
    'xmlns:o="urn:schemas-microsoft-com:office:office" '
    'xmlns:x="urn:schemas-microsoft-com:office:excel">'
    '<v:shapetype id="_x0000_t201" coordsize="21600,21600"/>',
  );
  final controls = StringBuffer();
  final rels = StringBuffer(
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
    'relationships"><Relationship Id="rId1" Type="http://schemas.'
    'openxmlformats.org/officeDocument/2006/relationships/vmlDrawing" '
    'Target="../drawings/vmlDrawing1.vml"/>',
  );
  final archiv = Archive();
  void neu(String pfad, String inhalt) {
    final bytes = utf8.encode(inhalt);
    archiv.addFile(ArchiveFile(pfad, bytes.length, bytes));
  }

  for (var i = 0; i < kaestchen.length; i++) {
    final o = zellortAus(kaestchen[i])!;
    final nr = 1025 + i;
    vml.write(
      '<v:shape id="_x0000_s$nr" type="#_x0000_t201" style=\'position:'
      'absolute\'><x:ClientData ObjectType="Checkbox"><x:Anchor>'
      '${o.spalte}, 10, ${o.zeile}, 2, ${o.spalte}, 30, ${o.zeile}, 18'
      '</x:Anchor><x:NoThreeD/></x:ClientData></v:shape>',
    );
    controls.write(
      '<control shapeId="$nr" r:id="rId${i + 2}" name="Check Box $i"/>',
    );
    rels.write(
      '<Relationship Id="rId${i + 2}" Type="http://schemas.microsoft.com/'
      'office/2007/relationships/ctrlProp" '
      'Target="../ctrlProps/ctrlProp${i + 1}.xml"/>',
    );
    neu(
      'xl/ctrlProps/ctrlProp${i + 1}.xml',
      '<formControlPr xmlns="http://schemas.microsoft.com/office/'
      'spreadsheetml/2009/9/main" objectType="CheckBox" lockText="1" '
      'noThreeD="1"/>',
    );
  }
  vml.write('</xml>');
  rels.write('</Relationships>');

  final blatt = StringBuffer(
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/'
    '2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/'
    '2006/relationships"><sheetData>',
  );
  for (final z in zellen.keys.toList()..sort()) {
    final liste = zellen[z]!..sort((a, b) => a.$1.compareTo(b.$1));
    blatt.write('<row r="$z">${liste.map((c) => c.$2).join()}</row>');
  }
  blatt
    ..write('</sheetData><mergeCells count="${verbunden.length}">')
    ..write(verbunden.map((v) => '<mergeCell ref="$v"/>').join())
    ..write('</mergeCells><headerFooter><oddHeader>')
    ..write(
      en
          ? '&amp;C&amp;14Product-Specification\n&amp;10 &amp;"Arial,Standard"'
              'number&amp;R&amp;P'
          : '&amp;C&amp;14Produkt-Spezifikation\n&amp;8&amp;K002060'
              'Artikelnummer&amp;R&amp;P',
    )
    ..write('</oddHeader></headerFooter><legacyDrawing r:id="rId1"/>')
    ..write('<controls>$controls</controls></worksheet>');

  String esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  neu(
    'xl/workbook.xml',
    '<workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/'
        '2006/relationships"><sheets><sheet name="Tabelle1" sheetId="1" '
        'r:id="rId1"/></sheets></workbook>',
  );
  neu(
    'xl/_rels/workbook.xml.rels',
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
        'relationships"><Relationship Id="rId1" Type="http://schemas.'
        'openxmlformats.org/officeDocument/2006/relationships/worksheet" '
        'Target="worksheets/sheet1.xml"/></Relationships>',
  );
  neu(
    'xl/sharedStrings.xml',
    '<sst count="${geteilt.length}" uniqueCount="${geteilt.length}">'
        '${geteilt.map((t) => '<si><t xml:space="preserve">${esc(t)}</t></si>').join()}'
        '</sst>',
  );
  neu('xl/worksheets/sheet1.xml', blatt.toString());
  neu('xl/worksheets/_rels/sheet1.xml.rels', rels.toString());
  neu('xl/drawings/vmlDrawing1.vml', vml.toString());
  neu('xl/styles.xml', '<styleSheet>unverändert</styleSheet>');
  return Uint8List.fromList(ZipEncoder().encode(archiv)!);
}

/// [xlsx] mit neuen Texten in einzelnen Zellen des ersten Blatts — etwa
/// Platzhalter, die jemand von Hand eingetragen hat.
Uint8List mitZellen(Uint8List xlsx, Map<String, String> zellen) {
  final mappe = XlsxMappe.lesen(xlsx);
  const pfad = 'xl/worksheets/sheet1.xml';
  var xml = mappe.text(pfad)!;
  for (final MapEntry(:key, :value) in zellen.entries) {
    xml = zelleSetzen(xml, key, value);
  }
  mappe.schreibe(pfad, xml);
  return mappe.packen();
}
