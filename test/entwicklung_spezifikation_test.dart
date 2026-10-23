import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
// `show Value`: drift bringt eine eigene Klasse `Column` mit.
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/constants/parameter_namen.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/theme/app_theme.dart';
import 'package:produktion_planer/core/ui/bausteine.dart';
import 'package:produktion_planer/features/entwicklung/bericht/projekt_bericht.dart';
import 'package:produktion_planer/features/entwicklung/daten/dateien.dart';
import 'package:produktion_planer/features/entwicklung/daten/entwicklung_repository.dart';
import 'package:produktion_planer/features/entwicklung/entwicklung_zugang.dart';
import 'package:produktion_planer/features/entwicklung/freigabe/freigabe.dart';
import 'package:produktion_planer/features/entwicklung/haccp/haccp_modell.dart';
import 'package:produktion_planer/features/entwicklung/haccp/prozess_modell.dart';
import 'package:produktion_planer/features/entwicklung/projekte/datei_aktionen.dart'
    show dateiInhaltProvider;
import 'package:produktion_planer/features/entwicklung/projekte/produkt_reiter.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_modell.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_repository.dart';
import 'package:produktion_planer/features/entwicklung/rechenkern/rechen_modell.dart';
import 'package:produktion_planer/features/entwicklung/rechenkern/rechenkern.dart';
import 'package:produktion_planer/features/entwicklung/spezifikation/beispielvorlage.dart';
import 'package:produktion_planer/features/entwicklung/spezifikation/deepl.dart';
import 'package:produktion_planer/features/entwicklung/spezifikation/spez_angaben.dart';
import 'package:produktion_planer/features/entwicklung/spezifikation/spezifikation_dialog.dart';
import 'package:produktion_planer/features/entwicklung/spezifikation/spezifikation_dienst.dart';
import 'package:produktion_planer/features/entwicklung/spezifikation/spezifikation_vorschau.dart';
import 'package:produktion_planer/features/entwicklung/spezifikation/spezifikation_werte.dart';
import 'package:produktion_planer/features/entwicklung/spezifikation/xlsx_vorlage.dart';

import 'helpers/test_db.dart';

/// Tests für Spezifikation und Projektbericht: Werte der Platzhalter auf
/// Deutsch und Englisch, das Füllen einer Excel-Vorlage, DeepL, der Dienst
/// mit der Datenbank, das Fenster und das PDF. Rezepturen, Projekte und
/// Vorlagen sind erfunden.
void main() {
  /// Alle Texte einer Mappe: geteilte Texte und Blätter hintereinander.
  String mappenText(Uint8List xlsx) {
    final archiv = ZipDecoder().decodeBytes(xlsx);
    return [
      for (final d in archiv.files)
        if (d.isFile &&
            (d.name == 'xl/sharedStrings.xml' ||
                d.name.startsWith('xl/worksheets/')))
          utf8.decode(d.content as List<int>),
    ].join('\n');
  }

  /// Eine kleine Mappe von Hand: ein geteilter Text, in zwei
  /// Formatierungsstücke zerlegt, und ein Text direkt in der Zelle.
  Uint8List kleineMappe(String geteilt, String direkt) {
    final archiv = Archive();
    void datei(String pfad, String inhalt) {
      final bytes = utf8.encode(inhalt);
      archiv.addFile(ArchiveFile(pfad, bytes.length, bytes));
    }

    datei('xl/workbook.xml', '<workbook><sheets/></workbook>');
    datei('xl/sharedStrings.xml', '<sst count="1">$geteilt</sst>');
    datei(
      'xl/worksheets/sheet1.xml',
      '<worksheet><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c>'
          '<c r="B1" t="inlineStr">$direkt</c></row></sheetData>'
          '</worksheet>',
    );
    datei('xl/styles.xml', '<styleSheet>unverändert</styleSheet>');
    return Uint8List.fromList(ZipEncoder().encode(archiv)!);
  }

  RechenZutat zutat(
    String id, {
    bool fleisch = false,
    bool wasser = false,
    Set<String> allergene = const {},
    List<String> hilfsstoffe = const [],
    Naehrwerte naehrwerte = Naehrwerte.leer,
  }) =>
      RechenZutat(
        id: id,
        name: id,
        istFleisch: fleisch,
        istWasser: wasser,
        tierart: fleisch ? Tierart.schwein : null,
        allergene: allergene,
        verarbeitungshilfsstoffe: hilfsstoffe,
        naehrwerte: naehrwerte,
      );

  /// Frikadellen aus Schweinefleisch, Wasser, Weizenmehl und Gewürz mit
  /// Trennmittel — 10 % Garverlust.
  RechenRezeptur frikadelle({bool mitHilfsstoff = true}) => RechenRezeptur(
        id: 'r',
        name: 'Frikadelle',
        verlustProzent: 10,
        verlustart: Verlustart.garen,
        positionen: [
          RechenPosition.zutat(
            zutat(
              'Schweinefleisch',
              fleisch: true,
              naehrwerte: const Naehrwerte(fett: 20, eiweiss: 18),
            ),
            mengeKg: 60,
          ),
          RechenPosition.zutat(zutat('Trinkwasser', wasser: true), mengeKg: 20),
          RechenPosition.zutat(
            zutat(
              'Weizenmehl',
              allergene: {'gluten'},
              naehrwerte: const Naehrwerte(kohlenhydrate: 70, eiweiss: 10),
            ),
            mengeKg: 15,
          ),
          RechenPosition.zutat(
            zutat(
              'Gewürzmischung',
              hilfsstoffe: mitHilfsstoff ? const ['Siliziumdioxid'] : const [],
              naehrwerte: const Naehrwerte(salz: 40),
            ),
            mengeKg: 5,
          ),
        ],
      );

  SpezifikationsQuelle quelle({
    bool mitHilfsstoff = true,
    SpezAngaben angaben = const SpezAngaben(),
    String? kuerzel,
  }) =>
      SpezifikationsQuelle(
        projektName: 'Frikadelle Testart',
        ergebnis: berechne(frikadelle(mitHilfsstoff: mitHilfsstoff)),
        verlustProzent: 10,
        artikelnummer: 'T-200',
        kunde: 'Muster GmbH',
        standNummer: 2,
        haltbarkeitTage: 14,
        aw: 0.97,
        sensorik: const Sensorik(
          geschmack: 'würzig, leicht pfeffrig',
          gewicht: '80 g',
        ),
        angaben: angaben,
        kuerzel: kuerzel,
      );

  final datum = DateTime(2026, 3, 5);

  group('Werte der Platzhalter', () {
    test('jeder Platzhalter hat einen Wert und umgekehrt', () {
      final werte = spezifikationsWerte(
        quelle(),
        sprache: SpezSprache.de,
        datum: datum,
      );
      expect(
        werte.keys.toSet(),
        {for (final p in kSpezifikationPlatzhalter) p.name},
      );
      // Keine Namen doppelt.
      expect(
        kSpezifikationPlatzhalter.map((p) => p.name).toSet().length,
        kSpezifikationPlatzhalter.length,
      );
    });

    test('deutsch: Komma, Datum mit Punkten, Stand, Tage', () {
      final w = spezifikationsWerte(
        quelle(),
        sprache: SpezSprache.de,
        datum: datum,
      );
      expect(w['gueltig_ab'], '05.03.2026');
      expect(w['artikelnummer'], 'T-200');
      // Ohne Artikel heißt die Spezifikation wie das Projekt.
      expect(w['bezeichnung'], 'Frikadelle Testart');
      expect(w['kunde'], 'Muster GmbH');
      expect(w['stand'], 'Stand 2');
      expect(w['verlust'], '10,0 %');
      expect(w['haltbarkeit'], '14 Tage');
      expect(w['aw'], '0,97');
      expect(w['zutaten'], contains('WEIZENmehl'));
      expect(w['fleischanteil'], endsWith(' %'));
      expect(w['naehrwert.energie'], matches(RegExp(r'^\d+ kJ / \d+ kcal$')));
      expect(w['naehrwert.salz'], contains(','));
      expect(w['sensorik.geschmack'], 'würzig, leicht pfeffrig');
      expect(w['allergene'], allergenName('gluten', SpezSprache.de));
      expect(w['allergen.gluten.ja'], 'X');
      expect(w['allergen.gluten.nein'], '');
      expect(w['allergen.gluten.quelle'], 'Weizenmehl');
      expect(w['allergen.milch.ja'], '');
      expect(w['allergen.milch.nein'], 'X');
      expect(w['hilfsstoff.1.name'], 'Siliziumdioxid');
      expect(w['hilfsstoff.1.quelle'], 'Gewürzmischung');
      expect(w['hilfsstoff.2.name'], '');
    });

    test('englisch: Punkt, Datum mit Schrägstrichen, Version, days', () {
      final w = spezifikationsWerte(
        quelle(mitHilfsstoff: false),
        sprache: SpezSprache.en,
        datum: datum,
      );
      expect(w['gueltig_ab'], '05/03/2026');
      expect(w['stand'], 'Version 2');
      expect(w['verlust'], '10.0 %');
      expect(w['haltbarkeit'], '14 days');
      expect(w['aw'], '0.97');
      expect(w['naehrwert.salz'], isNot(contains(',')));
      expect(w['allergene'], 'Cereals containing gluten');
      // Ohne Hilfsstoffe sagt der erste Platz „keine".
      expect(w['hilfsstoff.1.name'], 'None');
      expect(w['hilfsstoff.1.quelle'], '-');
      expect(w['hilfsstoff.2.name'], '');
    });

    test('übersetzt werden nur Texte, nicht Zahlen und nicht „None"', () {
      final w = spezifikationsWerte(
        quelle(mitHilfsstoff: false),
        sprache: SpezSprache.en,
        datum: datum,
      );
      final texte = uebersetzbareTexte(w);
      expect(
        texte.keys,
        containsAll([
          'bezeichnung',
          'zutaten',
          'sensorik.geschmack',
          'sensorik.gewicht',
          'allergen.gluten.quelle',
        ]),
      );
      for (final k in [
        'verlust',
        'aw',
        'gueltig_ab',
        'naehrwert.fett',
        'allergen.gluten.ja',
        'hilfsstoff.1.name',
        'hilfsstoff.1.quelle',
        'sensorik.aussehen',
      ]) {
        expect(texte.containsKey(k), isFalse, reason: k);
      }
    });

    const angaben = SpezAngaben(
      toleranz: '± 2,5',
      lagerung: 'gekühlt',
      haltbarkeit: '21',
      hinweise: 'Erst durcherhitzen.\n\nNicht wieder einfrieren.',
      spuren: {'senf', 'gluten'},
      verpackung: Verpackung(
        um: {'e2_kiste', 'karton_klein'},
        karton: 'bedruckt',
        umFuellung: 'gewogen',
        umNetto: '5,0',
        einzel: {'seitenfaltenbeutel'},
        atmosphaere: 'schutzgas',
        einzelFuellung: 'gezaehlt',
        stueckzahl: '10',
        einzelMaterial: 'PA/PE',
      ),
    );

    test('die Angaben des Projekts: Kürzel, Haltbarkeit, Hinweise, Spuren', () {
      final w = spezifikationsWerte(
        quelle(angaben: angaben, kuerzel: ' TE '),
        sprache: SpezSprache.de,
        datum: datum,
      );
      expect(w['kuerzel'], 'TE');
      // Die Angabe im Projekt geht vor die des Artikels; eine Zahl sind Tage.
      expect(w['haltbarkeit'], '21 Tage');
      expect(w['toleranz'], '± 2,5');
      expect(w['lagerung'], 'gekühlt');
      expect(w['hinweise'], 'Erst durcherhitzen.\nNicht wieder einfrieren.');
      expect(w['hinweis.1'], 'Erst durcherhitzen.');
      expect(w['hinweis.2'], 'Nicht wieder einfrieren.');
      expect(w['hinweis.3'], '');
      // Enthaltenes zählt nicht als Spur.
      expect(w['allergen.gluten.ja'], 'X');
      expect(w['allergen.gluten.spuren'], '');
      expect(w['allergen.gluten.nein'], '');
      expect(w['allergen.senf.ja'], '');
      expect(w['allergen.senf.spuren'], 'X');
      expect(w['allergen.senf.nein'], '');
      expect(w['allergen.eier.nein'], 'X');
      expect(w['allergen.eier.spuren'], '');

      final text = spezifikationsWerte(
        quelle(angaben: angaben.kopie(haltbarkeit: '12 Monate bei -18 °C')),
        sprache: SpezSprache.de,
        datum: datum,
      );
      expect(text['haltbarkeit'], '12 Monate bei -18 °C');
      expect(text['kuerzel'], '');
    });

    test('die Verpackung: Kreuze und Werte, englisch mit Dezimalpunkt', () {
      final w = spezifikationsWerte(
        quelle(angaben: angaben),
        sprache: SpezSprache.de,
        datum: datum,
      );
      expect(w['verpackung.um.e2_kiste'], 'X');
      expect(w['verpackung.um.karton_klein'], 'X');
      expect(w['verpackung.um.karton_gross'], '');
      expect(w['verpackung.um.bedruckt'], 'X');
      expect(w['verpackung.um.neutral'], '');
      expect(w['verpackung.um.gewogen'], 'X');
      expect(w['verpackung.um.egalisiert'], '');
      expect(w['verpackung.um.netto'], '5,0');
      expect(w['verpackung.um.tara'], '');
      expect(w['verpackung.einzel.seitenfaltenbeutel'], 'X');
      expect(w['verpackung.einzel.beutel'], '');
      expect(w['verpackung.einzel.schutzgas'], 'X');
      expect(w['verpackung.einzel.vakuum'], '');
      expect(w['verpackung.einzel.gezaehlt'], 'X');
      expect(w['verpackung.einzel.stueckzahl'], '10');
      expect(w['verpackung.einzel.material'], 'PA/PE');

      final en = spezifikationsWerte(
        quelle(angaben: angaben),
        sprache: SpezSprache.en,
        datum: datum,
      );
      expect(en['haltbarkeit'], '21 days');
      expect(en['toleranz'], '± 2.5');
      expect(en['verpackung.um.netto'], '5.0');
      expect(en['sensorik.gewicht'], '80 g');
    });

    test('Kreuze und was übersetzt wird', () {
      expect(istKreuzPlatzhalter('allergen.senf.spuren'), isTrue);
      expect(istKreuzPlatzhalter('allergen.senf.nein'), isTrue);
      expect(istKreuzPlatzhalter('allergen.senf.quelle'), isFalse);
      expect(istKreuzPlatzhalter('verpackung.einzel.vakuum'), isTrue);
      expect(istKreuzPlatzhalter('verpackung.einzel.material'), isFalse);
      expect(istKreuzPlatzhalter('kuerzel'), isFalse);
      final texte = uebersetzbareTexte({
        'lagerung': 'gekühlt',
        'haltbarkeit': '21 Tage',
        'toleranz': '± 5',
        'hinweis.1': 'Erst durcherhitzen.',
        'hinweise': 'Erst durcherhitzen.',
        'verpackung.einzel.material': 'Folie',
        'verpackung.einzel.vakuum': 'X',
        'verpackung.um.tara': '850',
        'kuerzel': 'TE',
      });
      expect(texte.keys.toSet(), {
        'lagerung',
        'hinweis.1',
        'hinweise',
        'verpackung.einzel.material',
      });
    });
  });

  group('Excel-Vorlage füllen', () {
    test('die Beispielvorlage enthält jeden Platzhalter', () {
      expect(
        platzhalterIn(beispielvorlage()),
        {for (final p in kSpezifikationPlatzhalter) p.name},
      );
    });

    test('gefüllt bleibt kein Platzhalter, die Formatierung unberührt', () {
      final vorlage = beispielvorlage();
      final werte = spezifikationsWerte(
        quelle(),
        sprache: SpezSprache.de,
        datum: datum,
      );
      final e = vorlageFuellen(vorlage, werte);
      expect(e.unbekannt, isEmpty);
      expect(e.ersetzt, werte.keys.toSet());
      expect(platzhalterIn(e.bytes), isEmpty);

      final text = mappenText(e.bytes);
      expect(text, contains('T-200'));
      expect(text, contains('Stand 2'));
      expect(text, contains('WEIZENmehl'));
      // Die Liste der Platzhalter im zweiten Blatt steht ohne Klammern da
      // und bleibt.
      expect(text, contains('allergen.gluten.ja'));

      String styles(Uint8List b) => utf8.decode(
            ZipDecoder().decodeBytes(b).findFile('xl/styles.xml')!.content
                as List<int>,
          );
      expect(styles(e.bytes), styles(vorlage));
    });

    test('zerlegte Platzhalter, Sonderzeichen und unbekannte Namen', () {
      final mappe = kleineMappe(
        '<si><r><rPr><b/></rPr><t>Nr. {{arti</t></r>'
            '<r><t xml:space="preserve">kelnummer}} und {{ tippfehler }}</t>'
            '</r></si>',
        '<is><t>{{kunde}}</t></is>',
      );
      expect(platzhalterIn(mappe), {'artikelnummer', 'tippfehler', 'kunde'});

      final e = vorlageFuellen(mappe, {
        'artikelnummer': 'A&B <1>',
        'kunde': 'Müller & Söhne',
      });
      expect(e.ersetzt, {'artikelnummer', 'kunde'});
      expect(e.unbekannt, {'tippfehler'});
      final text = mappenText(e.bytes);
      expect(
        text,
        contains(
          '<si><t xml:space="preserve">Nr. A&amp;B &lt;1&gt; und '
          '{{ tippfehler }}</t></si>',
        ),
      );
      expect(
        text,
        contains('<is><t xml:space="preserve">Müller &amp; Söhne</t></is>'),
      );
      // Die übrigen Teile der Mappe bleiben, wie sie waren.
      final styles = ZipDecoder()
          .decodeBytes(e.bytes)
          .findFile('xl/styles.xml')!
          .content as List<int>;
      expect(utf8.decode(styles), '<styleSheet>unverändert</styleSheet>');
    });

    test('keine Excel-Mappe: ein verständlicher Fehler', () {
      expect(
        () => platzhalterIn(Uint8List.fromList(utf8.encode('kein zip'))),
        throwsFormatException,
      );
      final archiv = Archive()
        ..addFile(ArchiveFile('irgendwas.txt', 3, utf8.encode('abc')));
      final zip = Uint8List.fromList(ZipEncoder().encode(archiv)!);
      expect(() => vorlageFuellen(zip, const {}), throwsFormatException);
    });
  });

  group('DeepL', () {
    test('Adresse nach Art des Schlüssels', () {
      expect(deeplAdresse('abc:fx').host, 'api-free.deepl.com');
      expect(deeplAdresse(' abc:fx ').host, 'api-free.deepl.com');
      expect(deeplAdresse('abc').host, 'api.deepl.com');
    });

    test('die Anfrage trägt alle Texte, kodiert', () {
      expect(
        deeplAnfrage(['Rind & Schwein', 'Größe']),
        'text=Rind+%26+Schwein&text=Gr%C3%B6%C3%9Fe'
        '&source_lang=DE&target_lang=EN-GB',
      );
    });

    test('die Antwort in derselben Reihenfolge, sonst ein Fehler', () {
      expect(
        deeplAntwort(
          '{"translations":[{"text":"Beef"},{"text":"Size"}]}',
          2,
        ),
        ['Beef', 'Size'],
      );
      expect(
        () => deeplAntwort('{"translations":[{"text":"Beef"}]}', 2),
        throwsA(isA<DeepLFehler>()),
      );
      expect(
        () => deeplAntwort('<html>', 1),
        throwsA(isA<DeepLFehler>()),
      );
      expect(
        () => deeplAntwort('{"translations":[{"x":1}]}', 1),
        throwsA(isA<DeepLFehler>()),
      );
    });
  });

  group('Dienst mit der Datenbank', () {
    late AppDatabase db;
    late EntwicklungRepository rezepte;
    late ProjektRepository projekte;
    late EntwicklungDateienDienst dateien;
    late List<List<String>> aufrufe;

    setUp(() async {
      db = testDatenbank();
      rezepte = EntwicklungRepository(db);
      projekte = ProjektRepository(db);
      dateien = EntwicklungDateienDienst(db);
      aufrufe = [];
      // Der Datenschlüssel entsteht mit dem Passwort.
      await EntwicklungZugang(
        DbEntwicklungsSpeicher(db),
        iterationen: 1000,
        imHintergrund: false,
      ).festlegen('geheim123');
    });
    tearDown(() => db.close());

    SpezifikationDienst dienst({Uebersetzer? uebersetzer}) =>
        SpezifikationDienst(
          db,
          dateien,
          uebersetzer: uebersetzer ??
              (List<String> texte, String schluessel) async {
                aufrufe.add(texte);
                return [for (final t in texte) 'EN[$t]'];
              },
        );

    /// Ein Projekt mit einer Rezeptur: Stand 1 abgeschlossen, Stand 2 als
    /// Entwurf.
    Future<({EntwicklungsProjekt projekt, String v1, String v2})>
        anlegen() async {
      final id = await projekte.projektAnlegen(
        name: 'Frikadelle Testart',
        kunde: 'Muster GmbH',
        artikelnummer: 'T-200',
      );
      await projekte.projektAendern(
        id,
        EntwicklungProjekteCompanion(
          grenzeAw: const Value(0.97),
          sensorik: Value(
            const Sensorik(geschmack: 'würzig', gewicht: '80 g').alsJson(),
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
      final v1 = (await rezepte.neuesteVersion(rezeptur))!;
      await rezepte.positionHinzufuegen(v1.id, zutatId: fleisch, mengeKg: 80);
      await rezepte.positionHinzufuegen(v1.id, zutatId: mehl, mengeKg: 20);
      await rezepte.versionAendern(
        v1.id,
        const EntwicklungRezepturVersionenCompanion(
          verlustProzent: Value(10),
          verlustArt: Value('garen'),
        ),
      );
      await rezepte.versionAbschliessen(v1.id);
      final v2 = await rezepte.versionAnlegen(rezeptur, vorlageId: v1.id);
      return (projekt: (await projekte.projekt(id))!, v1: v1.id, v2: v2);
    }

    test('Stände: abgeschlossene vor Entwürfen', () async {
      final a = await anlegen();
      final staende = await dienst().staende(a.projekt.id);
      expect([for (final s in staende) s.version.id], [a.v1, a.v2]);
      expect(
        spezStandLabel(staende.last),
        'Frikadelle Testart · Stand 2 · Entwurf',
      );
      expect(
        spezStandLabel(staende.first, freigegebeneVersionId: a.v1),
        'Frikadelle Testart · Stand 1 · freigegeben',
      );
      expect(spezStandVorschlag(staende, null), a.v1);
      expect(spezStandVorschlag(staende, a.v2), a.v2);
      expect(spezStandVorschlag(staende, 'gibt-es-nicht'), a.v1);
      expect(spezStandVorschlag(const [], null), isNull);
    });

    test('ohne Vorlage ein verständlicher Fehler', () async {
      final a = await anlegen();
      await expectLater(
        dienst().erstellen(
          projekt: a.projekt,
          versionId: a.v1,
          sprache: SpezSprache.de,
        ),
        throwsStateError,
      );
    });

    test('eine Vorlage, die keine Excel-Mappe ist, wird nicht gespeichert',
        () async {
      final d = dienst();
      await expectLater(
        d.vorlageSpeichern(
          SpezSprache.de,
          'notiz.xlsx',
          Uint8List.fromList(utf8.encode('kein zip')),
        ),
        throwsFormatException,
      );
      expect(await d.vorlage(SpezSprache.de), isNull);
    });

    test('deutsch: Vorlage speichern, füllen, ablegen, abhaken', () async {
      final a = await anlegen();
      final d = dienst();
      final gespeichert = await d.vorlageSpeichern(
        SpezSprache.de,
        'Unsere Spezifikation.xlsx',
        beispielvorlage(),
      );
      expect(gespeichert.platzhalter.length, kSpezifikationPlatzhalter.length);
      // Mit Platzhaltern wird nichts eingerichtet.
      expect(gespeichert.einrichtung, isNull);
      final vorlage = (await d.vorlage(SpezSprache.de))!;
      expect(vorlage.name, 'Unsere Spezifikation.xlsx');
      // Eine Vorlage gehört zu keinem Projekt.
      expect(vorlage.projektId, isNull);

      final e = await d.erstellen(
        projekt: a.projekt,
        versionId: a.v1,
        sprache: SpezSprache.de,
        datum: datum,
      );
      expect(e.dateiname, 'Frikadelle Testart_Spezifikation.xlsx');
      expect(e.ersetzt, kSpezifikationPlatzhalter.length);
      expect(e.unbekannt, isEmpty);
      expect(e.uebersetzt, isFalse);
      expect(e.uebersetzungsFehler, isNull);
      final text = mappenText(e.bytes);
      expect(text, contains('T-200'));
      expect(text, contains('Stand 1'));
      expect(text, contains('05.03.2026'));
      expect(text, contains('10,0 %'));
      expect(text, contains('0,97'));
      expect(text, contains('WEIZENmehl'));
      expect(text, contains('würzig'));
      // Deutsch wird nie übersetzt.
      expect(aufrufe, isEmpty);

      final dateiId = await d.ablegen(
        projekt: a.projekt,
        versionId: a.v1,
        sprache: SpezSprache.de,
        ergebnis: e,
        jetzt: DateTime(2026, 3, 5, 14, 30),
      );
      expect(await dateien.lesen(dateiId), e.bytes);
      final datei = (await dateien.datei(dateiId))!;
      expect(datei.projektId, a.projekt.id);
      expect(datei.mimeTyp, kXlsxMime);
      final verlauf = await projekte.eintraegeBeobachten(a.projekt.id).first;
      final eintrag = verlauf.firstWhere((v) => v.dateiId == dateiId);
      expect(eintrag.titel, 'Spezifikation (Deutsch)');
      expect(eintrag.art, EintragArt.datei.schluessel);
      expect(eintrag.status, EintragStatus.erledigt.schluessel);
      expect(eintrag.versionId, a.v1);
      expect(eintrag.datum, DateTime(2026, 3, 5));
      expect(eintrag.beschreibung, 'Erstellt aus Rezepturstand 1.');

      await d.abhaken(a.projekt.id);
      final p = (await projekte.projekt(a.projekt.id))!;
      expect(checklisteAus(p.checkliste), contains('spezifikationErstellt'));
    });

    test('englisch: ohne Schlüssel deutsch, mit Schlüssel übersetzt', () async {
      final a = await anlegen();
      final d = dienst();
      await d.vorlageSpeichern(SpezSprache.en, 'Spec.xlsx', beispielvorlage());

      final ohne = await d.erstellen(
        projekt: a.projekt,
        versionId: a.v1,
        sprache: SpezSprache.en,
        datum: datum,
      );
      expect(ohne.dateiname, 'Frikadelle Testart_Specification.xlsx');
      expect(ohne.uebersetzt, isFalse);
      expect(ohne.uebersetzungsFehler, contains('Kein DeepL-Schlüssel'));
      expect(aufrufe, isEmpty);
      // Zahlen und Daten trotzdem englisch.
      final textOhne = mappenText(ohne.bytes);
      expect(textOhne, contains('Version 1'));
      expect(textOhne, contains('05/03/2026'));
      expect(textOhne, contains('10.0 %'));

      await d.deeplSpeichern(' test-schluessel:fx ');
      expect(await d.deeplSchluessel(), 'test-schluessel:fx');
      final mit = await d.erstellen(
        projekt: a.projekt,
        versionId: a.v1,
        sprache: SpezSprache.en,
        datum: datum,
      );
      expect(mit.uebersetzt, isTrue);
      expect(mit.uebersetzungsFehler, isNull);
      // Ein Aufruf, jeder Text nur einmal.
      expect(aufrufe, hasLength(1));
      expect(aufrufe.single.toSet().length, aufrufe.single.length);
      expect(aufrufe.single, contains('Frikadelle Testart'));
      expect(aufrufe.single, isNot(contains('None')));
      final text = mappenText(mit.bytes);
      expect(text, contains('EN[Frikadelle Testart]'));
      expect(text, contains('EN[würzig]'));
      expect(text, contains('Version 1'));
      expect(text, contains('Cereals containing gluten'));

      await d.deeplSpeichern('');
      expect(await d.deeplSchluessel(), isNull);
    });

    test('ein Fehler von DeepL: deutsch mit Hinweis', () async {
      final a = await anlegen();
      final d = dienst(
        uebersetzer: (List<String> texte, String schluessel) async =>
            throw const DeepLFehler(
          'Das Kontingent des DeepL-Schlüssels ist aufgebraucht.',
        ),
      );
      await d.vorlageSpeichern(SpezSprache.en, 'Spec.xlsx', beispielvorlage());
      await d.deeplSpeichern('test-schluessel:fx');
      final e = await d.erstellen(
        projekt: a.projekt,
        versionId: a.v1,
        sprache: SpezSprache.en,
        datum: datum,
      );
      expect(e.uebersetzt, isFalse);
      expect(
        e.uebersetzungsFehler,
        'Das Kontingent des DeepL-Schlüssels ist aufgebraucht. '
        'Die Texte sind deutsch.',
      );
      expect(mappenText(e.bytes), contains('Frikadelle Testart'));
    });

    test('ohne Übersetzen-Wunsch kein Aufruf', () async {
      final a = await anlegen();
      final d = dienst();
      await d.vorlageSpeichern(SpezSprache.en, 'Spec.xlsx', beispielvorlage());
      await d.deeplSpeichern('test-schluessel:fx');
      final e = await d.erstellen(
        projekt: a.projekt,
        versionId: a.v1,
        sprache: SpezSprache.en,
        uebersetzen: false,
        datum: datum,
      );
      expect(e.uebersetzt, isFalse);
      expect(e.uebersetzungsFehler, isNull);
      expect(aufrufe, isEmpty);
    });

    test('Vorlage entfernen', () async {
      final d = dienst();
      await d.vorlageSpeichern(SpezSprache.de, 'V.xlsx', beispielvorlage());
      expect(await d.vorlage(SpezSprache.de), isNotNull);
      expect(await d.vorlage(SpezSprache.en), isNull);
      await d.vorlageLoeschen(SpezSprache.de);
      expect(await d.vorlage(SpezSprache.de), isNull);
    });

    group('Projektbericht', () {
      // Ein Bild mit einem Bildpunkt (PNG).
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAj'
        'CB0C8AAAAASUVORK5CYII=',
      );

      test('mit allem: Stand, Bild, Prozess, HACCP, Verlauf', () async {
        final a = await anlegen();
        final bildId = await dateien.speichern(
          name: 'Produkt.png',
          inhalt: png,
          projektId: a.projekt.id,
          mimeTyp: 'image/png',
        );
        await projekte.projektAendern(
          a.projekt.id,
          EntwicklungProjekteCompanion(
            bildDateiId: Value(bildId),
            notizen: const Value('Kunde wünscht weniger Salz.'),
            // Abschnitte von früher, nie ausgefüllt.
            prozess: Value(
              const Prozessparameter(
                abschnitte: [
                  ProzessAbschnitt(
                    id: 'garen',
                    titel: 'Garen',
                    felder: [ProzessFeld(id: 't', label: 'Temperatur')],
                  ),
                ],
              ).alsJson(),
            ),
            haccp: Value(
              const Haccp(
                gefahren: [
                  Gefahr(
                    id: 'g1',
                    gefahr: 'Fremdkörper',
                    schwere: 3,
                    wahrscheinlichkeit: 2,
                    massnahmen: 'Metalldetektor',
                  ),
                ],
              ).alsJson(),
            ),
          ),
        );
        for (var i = 0; i < 3; i++) {
          await projekte.eintragAnlegen(
            projektId: a.projekt.id,
            art: EintragArt.notiz,
            titel: 'Verkostung $i',
            datum: DateTime(2026, 3, i + 1),
            beschreibung: 'Probe $i — „gut"',
          );
        }
        final projekt = (await projekte.projekt(a.projekt.id))!;

        final b = await berichtLaden(db, dateien, projekt);
        // Ohne Freigabe: der neueste abgeschlossene Stand.
        expect(b.version?.id, a.v1);
        expect(b.rezepturName, 'Frikadelle Testart');
        expect(b.ergebnis, isNotNull);
        expect(b.bild, png);
        // Der neueste Eintrag zuerst.
        final titel = [for (final v in b.verlauf) v.titel];
        expect(
          titel.indexOf('Verkostung 2'),
          lessThan(titel.indexOf('Verkostung 0')),
        );
        expect(Haccp.aus(projekt.haccp).gefahren.single.risiko, 6);
        // Die Checkliste rechnet sich selbst — wie in der Übersicht:
        // Rezeptur und Nährwerte aus Stand 1, das Produktfoto ist da, der
        // Prozess hat noch keine Werte, der Sensorik fehlt das meiste.
        final check = b.checkliste!;
        expect(check.text, '3 von 9');
        expect(check.punkt('produktfotoHinterlegt')!.erledigt, isTrue);
        expect(
          check.punkt('prozessErstellt')!.text,
          'Noch keine Werte eingetragen',
        );
        expect(
          check.punkt('sensorikErstellt')!.text,
          'Fehlt: Aussehen, Geruch und Konsistenz',
        );
        // Stand 2 ist in Arbeit, Stand 1 eine Station mit Kennzahlen.
        expect([for (final x in b.inArbeit) x.version.id], [a.v2]);
        expect(b.kennzahlen.keys, [a.v1]);

        final pdf = await baueProjektPdf(b, gedrucktAm: datum);
        expect(utf8.decode(pdf.sublist(0, 5), allowMalformed: true), '%PDF-');
      });

      test('Entwicklungsweg: Stationen, Kennzahlen, Phasen, in Arbeit',
          () async {
        final a = await anlegen();
        final rezepturId = (await rezepte.version(a.v1))!.rezepturId;
        // Stand 2 mit weniger Mehl, dann ein dritter Entwurf.
        await rezepte.mengenSetzen(a.v2, [90, 10]);
        await rezepte.versionAbschliessen(a.v2, grund: 'Weniger Mehl');
        final v3 = await rezepte.versionAnlegen(rezepturId, vorlageId: a.v2);
        // Eine offene Rückmeldung zu Stand 1, dann die Validierung.
        await projekte.eintragAnlegen(
          projektId: a.projekt.id,
          art: EintragArt.email,
          titel: 'Rückmeldung Kunde',
          datum: DateTime.now(),
          versionId: a.v1,
          beschreibung: 'Zu mehlig. ' * 600,
        );
        await projekte.statusAendern(a.projekt.id, ProjektStatus.validierung);
        final projekt = (await projekte.projekt(a.projekt.id))!;

        final b = await berichtLaden(db, dateien, projekt);
        expect(b.kennzahlen.keys, unorderedEquals([a.v1, a.v2]));
        // Die erste Station ohne Änderung, die zweite gegen die erste.
        expect(b.kennzahlen[a.v1]!.every((k) => k.aenderung == null), isTrue);
        final fett = b.kennzahlen[a.v2]!.firstWhere((k) => k.label == 'Fett');
        expect(fett.aenderung, startsWith('+'));
        expect(b.ergebnisse.keys, containsAll([a.v1, a.v2, v3]));
        expect(
          b.ergebnisse[a.v1]!.zutatenliste,
          isNot(b.ergebnisse[a.v2]!.zutatenliste),
        );
        expect(
          b.ergebnisse[a.v1]!.je100g.fett,
          isNot(b.ergebnisse[a.v2]!.je100g.fett),
        );
        expect(b.inArbeit.single.version.id, v3);
        expect(b.inArbeit.single.rezeptur, 'Frikadelle Testart');
        expect(b.versionen.keys, containsAll([a.v1, a.v2, v3]));
        expect(
          b.checkliste!.punkt('rezepturErstellt')!.text,
          'Frikadelle Testart · Stand 2 abgeschlossen',
        );

        // Die lange Rückmeldung läuft eingerückt über die Seite hinaus.
        final pdf = await baueProjektPdf(b, gedrucktAm: datum);
        expect(utf8.decode(pdf.sublist(0, 5), allowMalformed: true), '%PDF-');
      });

      test('der freigegebene Stand geht vor', () async {
        final a = await anlegen();
        await projekte.projektAendern(
          a.projekt.id,
          EntwicklungProjekteCompanion(freigabeVersionId: Value(a.v2)),
        );
        final projekt = (await projekte.projekt(a.projekt.id))!;
        final b = await berichtLaden(db, dateien, projekt);
        expect(b.version?.id, a.v2);
      });

      test('ohne Rezeptur, mit kaputtem Bild und sehr langem Text', () async {
        final id = await projekte.projektAnlegen(name: 'Leeres Projekt');
        await projekte.projektAendern(
          id,
          EntwicklungProjekteCompanion(
            notizen: Value('Eine lange Notiz. ' * 4000),
          ),
        );
        for (var i = 0; i < 120; i++) {
          await projekte.eintragAnlegen(
            projektId: id,
            art: EintragArt.notiz,
            titel: 'Eintrag $i',
            datum: DateTime(2026, 1, 1).add(Duration(days: i)),
            beschreibung: 'Beschreibung $i ' * 20,
          );
        }
        final projekt = (await projekte.projekt(id))!;
        final b = await berichtLaden(db, dateien, projekt);
        expect(b.version, isNull);
        expect(b.ergebnis, isNull);

        final pdf = await baueProjektPdf(
          ProjektBericht(
            projekt: projekt,
            verlauf: b.verlauf,
            bild: Uint8List.fromList([1, 2, 3]),
          ),
        );
        expect(utf8.decode(pdf.sublist(0, 5), allowMalformed: true), '%PDF-');
      });

      test('mit Prozesskette: nach Stationen, je Schritt seine Werte',
          () async {
        final id = await projekte.projektAnlegen(name: 'Kette Testart');
        const kette = Prozessparameter(
          schritte: [
            ProzessSchritt(
              id: 's1',
              abteilung: 'zerlegung',
              maschine: 'Testwolf',
              prozessschritt: 'Wolfen',
              werte: [
                ProzessWert(name: 'Lochscheibe', wert: '3', einheit: 'mm'),
              ],
            ),
            ProzessSchritt(
              id: 's2',
              abteilung: 'bratstrasse',
              maschine: 'Testbratstraße',
              notiz: 'Band mittig',
              werte: [
                ProzessWert(
                  name: 'Platte Oben 1',
                  wert: '180',
                  gruppe: 'BRATSTRASSE',
                ),
              ],
            ),
            // Ohne Abteilung und ohne Anlage — etwa aus früheren
            // Abschnitten.
            ProzessSchritt(id: 's3', prozessschritt: 'Abkühlen'),
          ],
        );
        await projekte.projektAendern(
          id,
          EntwicklungProjekteCompanion(prozess: Value(kette.alsJson())),
        );
        final projekt = (await projekte.projekt(id))!;
        final b = await berichtLaden(db, dateien, projekt);
        expect(
          b.checkliste!.punkt('prozessErstellt')!.text,
          'Noch keine Version festgehalten',
        );
        final pdf = await baueProjektPdf(b, gedrucktAm: datum);
        expect(utf8.decode(pdf.sublist(0, 5), allowMalformed: true), '%PDF-');
      });

      test('Bericht übernimmt Maschineneinstellungen aus dem Artikel',
          () async {
        final id = await projekte.projektAnlegen(name: 'Artikel mit Kette');
        await db.into(db.products).insert(
              ProductsCompanion.insert(
                id: 'artikel-1',
                artikelnummer: 'A-123',
                artikelbezeichnung: 'Testprodukt',
                produktgruppe: const Value('bratstrasse_natur'),
                haltbarkeitTage: const Value(14),
              ),
            );
        await db.into(db.productSteps).insert(
              ProductStepsCompanion.insert(
                id: 'schritt-1',
                productId: 'artikel-1',
                reihenfolge: 1,
                abteilung: 'bratstrasse',
                basisMengeKg: 100,
                basisDauerMinuten: 12,
                basisMitarbeiter: 2,
                maschine: const Value('Testbratstraße'),
                maschinenEinstellungenJson: const Value(
                  '{"Band": "mittig"}',
                ),
              ),
            );
        await db.into(db.productStepParameters).insert(
              ProductStepParametersCompanion.insert(
                id: 'parameter-1',
                stepId: 'schritt-1',
                parameterGruppe: 'MASCHINENEINSTELLUNGEN',
                parameterName: 'Drehzahl',
                wert: const Value('3000 U/min'),
              ),
            );
        await db.into(db.productStepParameters).insert(
              ProductStepParametersCompanion.insert(
                id: 'parameter-2',
                stepId: 'schritt-1',
                parameterGruppe: kPlattenGruppeBrat,
                parameterName: 'Platte Oben 1',
                wert: const Value('180'),
              ),
            );
        await db.into(db.productStepParameters).insert(
              ProductStepParametersCompanion.insert(
                id: 'parameter-schema',
                stepId: 'schritt-1',
                parameterGruppe: kPlattenGruppeBrat,
                parameterName: kPlattenSchemaParam,
                wert: const Value('bratstrasse'),
              ),
            );
        await projekte.projektAendern(
          id,
          const EntwicklungProjekteCompanion(artikelId: Value('artikel-1')),
        );

        final projekt = (await projekte.projekt(id))!;
        final bericht = await berichtLaden(db, dateien, projekt);
        expect(bericht.artikelSchritte, hasLength(1));
        expect(
          bericht.artikelSchritte.single.schritt.maschine,
          'Testbratstraße',
        );
        expect(
          bericht.artikelSchritte.single.parameter
              .singleWhere((p) => p.parameterName == 'Drehzahl')
              .wert,
          '3000 U/min',
        );

        final pdf = await baueProjektPdf(bericht, gedrucktAm: datum);
        expect(utf8.decode(pdf.sublist(0, 5), allowMalformed: true), '%PDF-');
      });
    });
  });

  group('Fenster', () {
    final zeit = DateTime(2026, 10, 20);
    final projekt = EntwicklungsProjekt(
      id: 'p1',
      name: 'Frikadelle Testart',
      status: ProjektStatus.entwicklung.schluessel,
      neuerProzess: false,
      neueZutaten: false,
      freigabeVersionId: 'v1',
      createdAt: zeit,
      updatedAt: zeit,
    );
    final rezeptur = Rezeptur(
      id: 'r1',
      name: 'Frikadelle Testart',
      projektId: 'p1',
      createdAt: zeit,
      updatedAt: zeit,
    );
    RezepturVersion version(String id, int nummer, String status) =>
        RezepturVersion(
          id: id,
          rezepturId: 'r1',
          nummer: nummer,
          status: status,
          verlustProzent: 10,
          fettVerlustProzent: 0,
          verlustArt: 'garen',
          createdAt: zeit,
          updatedAt: zeit,
        );
    final staende = [
      FreigabeStand(
        rezeptur: rezeptur,
        version: version('v1', 1, VersionStatus.abgeschlossen),
      ),
      FreigabeStand(
        rezeptur: rezeptur,
        version: version('v2', 2, VersionStatus.entwurf),
      ),
    ];
    final vorlage = EntwicklungsDatei(
      id: spezVorlageId(SpezSprache.de),
      name: 'Unsere Spezifikation.xlsx',
      mimeTyp: kXlsxMime,
      groesse: 2048,
      createdAt: zeit,
    );

    Future<void> zeige(
      WidgetTester tester, {
      List<FreigabeStand>? liste,
      bool mitVorlage = false,
      bool schluessel = false,
      String? versionId,
      String? bild,
    }) async {
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final p = projekt.copyWith(bildDateiId: Value(bild));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // Das Fenster liest das Projekt neu — ein eben gewähltes Foto.
            projektProvider.overrideWith((ref, id) => Stream.value(p)),
            dateiInhaltProvider.overrideWith((ref, id) async => null),
            spezStaendeProvider.overrideWith(
              (ref, id) async => liste ?? staende,
            ),
            spezVorlageProvider.overrideWith(
              (ref, s) async =>
                  mitVorlage && s == SpezSprache.de ? vorlage : null,
            ),
            spezVorlagePlatzhalterProvider.overrideWith(
              (ref, s) async => const <String>{},
            ),
            spezKuerzelProvider.overrideWith((ref) async => null),
            deeplHinterlegtProvider.overrideWith((ref) async => schluessel),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: SpezifikationDialog(projekt: p, versionId: versionId),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    ButtonStyleButton knopf(WidgetTester tester, String text) =>
        tester.widget<ButtonStyleButton>(
          find.ancestor(
            of: find.text(text),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          ),
        );

    testWidgets('ohne Vorlage: Hinweis, Erstellen gesperrt', (tester) async {
      await zeige(tester);
      expect(find.text('Spezifikation erstellen'), findsOneWidget);
      // Vorgeschlagen ist der freigegebene Stand.
      expect(
        find.text('Frikadelle Testart · Stand 1 · freigegeben'),
        findsOneWidget,
      );
      expect(
        find.text('Noch keine Vorlage für Deutsch gewählt.'),
        findsOneWidget,
      );
      expect(find.text('Vorlage wählen…'), findsOneWidget);
      expect(knopf(tester, 'Erstellen…').enabled, isFalse);
      // DeepL gibt es nur für Englisch.
      expect(find.text('Texte mit DeepL übersetzen'), findsNothing);
    });

    String? gewaehlterStand(WidgetTester tester) => tester
        .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
        .value;

    testWidgets('mit dem Stand aus dem Reiter „Produkt"', (tester) async {
      await zeige(tester, versionId: 'v2');
      expect(gewaehlterStand(tester), 'v2');
    });

    testWidgets('einen Stand, den es nicht gibt, ersetzt der Vorschlag',
        (tester) async {
      await zeige(tester, versionId: 'gibt-es-nicht');
      expect(gewaehlterStand(tester), 'v1');
      expect(tester.takeException(), isNull);
    });

    testWidgets('mit Vorlage: Name und Größe, Erstellen frei', (tester) async {
      await zeige(tester, mitVorlage: true);
      expect(find.text('Unsere Spezifikation.xlsx · 2 KB'), findsOneWidget);
      expect(find.text('Ersetzen…'), findsOneWidget);
      expect(find.byTooltip('Vorlage entfernen'), findsOneWidget);
      expect(knopf(tester, 'Erstellen…').enabled, isTrue);
    });

    testWidgets('Englisch: eigene Vorlage und DeepL', (tester) async {
      await zeige(tester, mitVorlage: true);
      await tester.tap(find.text('Englisch'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text('Noch keine Vorlage für Englisch gewählt.'),
        findsOneWidget,
      );
      expect(knopf(tester, 'Erstellen…').enabled, isFalse);
      expect(find.text('Texte mit DeepL übersetzen'), findsOneWidget);
      expect(find.text('Schlüssel eingeben…'), findsOneWidget);
      // Ohne Schlüssel lässt sich nicht übersetzen.
      final schalter =
          tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(schalter.onChanged, isNull);
      expect(schalter.value, isFalse);
    });

    testWidgets('Englisch mit Schlüssel: Übersetzen an', (tester) async {
      await zeige(tester, schluessel: true);
      await tester.tap(find.text('Englisch'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Schlüssel ändern…'), findsOneWidget);
      final schalter =
          tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(schalter.value, isTrue);
      expect(schalter.onChanged, isNotNull);
    });

    testWidgets('das Produktfoto: fehlt es, lässt es sich gleich wählen',
        (tester) async {
      await zeige(tester, mitVorlage: true);
      expect(find.textContaining('Noch kein Produktfoto'), findsOneWidget);
      // Was sonst leer bliebe — der Assistent fragt es ab (F39).
      expect(
        find.text(
          'Noch offen: Artikelnummer, Sensorik, Lagerung, Haltbarkeit und '
          'Verpackung — sie blieben in der Spezifikation leer.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('spez-angaben')), findsOneWidget);
      expect(find.byKey(const ValueKey('spez-foto-waehlen')), findsOneWidget);
      // Erstellen geht trotzdem — das Feld bleibt dann leer.
      expect(knopf(tester, 'Erstellen…').enabled, isTrue);
    });

    // Ein eigener Test: Ein zweites zeige() im selben Test behielte den
    // ProviderScope samt dem Projekt ohne Foto.
    testWidgets('das Produktfoto: ist es da, steht es neben der Sensorik',
        (tester) async {
      await zeige(tester, mitVorlage: true, bild: 'f1');
      expect(
        find.text('Produktfoto — kommt ins Feld neben der Sensorik'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('spez-foto-anderes')), findsOneWidget);
      expect(find.textContaining('Noch kein Produktfoto'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ohne Rezeptur ein Hinweis', (tester) async {
      await zeige(tester, liste: const [], mitVorlage: true);
      expect(find.textContaining('noch keine Rezeptur'), findsOneWidget);
      expect(knopf(tester, 'Erstellen…').enabled, isFalse);
    });

    testWidgets('die Platzhalter zum Nachschlagen', (tester) async {
      await zeige(tester);
      expect(find.text('{{artikelnummer}}'), findsNothing);
      await tester.ensureVisible(find.text('Alle Platzhalter'));
      await tester.pump();
      await tester.tap(find.text('Alle Platzhalter'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('{{artikelnummer}}'), findsOneWidget);
      expect(find.text('{{allergen.gluten.ja}}'), findsOneWidget);
    });
  });

  group('Reiter Produkt', () {
    final zeit = DateTime(2026, 10, 20);
    final rezeptur = Rezeptur(
      id: 'r1',
      name: 'Frikadelle Testart',
      projektId: 'p1',
      createdAt: zeit,
      updatedAt: zeit,
    );
    final staende = [
      FreigabeStand(
        rezeptur: rezeptur,
        version: RezepturVersion(
          id: 'v1',
          rezepturId: 'r1',
          nummer: 1,
          status: VersionStatus.abgeschlossen,
          verlustProzent: 10,
          fettVerlustProzent: 0,
          verlustArt: 'garen',
          createdAt: zeit,
          updatedAt: zeit,
        ),
      ),
    ];
    final vorlage = EntwicklungsDatei(
      id: spezVorlageId(SpezSprache.de),
      name: 'Formblatt.xlsx',
      mimeTyp: kXlsxMime,
      groesse: 2048,
      createdAt: zeit,
    );
    EntwicklungsProjekt projekt({String? spezifikation}) => EntwicklungsProjekt(
          id: 'p1',
          name: 'Frikadelle Testart',
          status: ProjektStatus.entwicklung.schluessel,
          neuerProzess: false,
          neueZutaten: false,
          freigabeVersionId: 'v1',
          sensorik: const Sensorik(gewicht: '80 g').alsJson(),
          spezifikation: spezifikation,
          createdAt: zeit,
          updatedAt: zeit,
        );

    /// Was die Vorschau zeigt: ohne Artikelnummer und Lagerung.
    const vorschau = {
      'stand': 'Stand 1',
      'artikelnummer': '',
      'bezeichnung': 'Frikadelle Testart',
      'sensorik.gewicht': '80 g',
      'toleranz': '± 5',
      'zutaten': 'Schweinefleisch (80 %), Wasser, SENF, Speisesalz',
      'fleischanteil': '80,0 %',
      'allergene': 'Senf',
      'allergen.sellerie.spuren': 'X',
      'naehrwert.energie': '900 kJ / 215 kcal',
      'naehrwert.fett': '16',
      'naehrwert.gesaettigte_fettsaeuren': '6,0',
      'naehrwert.kohlenhydrate': '1,0',
      'naehrwert.zucker': '0,5',
      'naehrwert.eiweiss': '15',
      'naehrwert.salz': '1,8',
      'hilfsstoff.1.name': 'Keine',
      'hilfsstoff.1.quelle': '-',
      'sensorik.aussehen': 'goldbraun',
      'lagerung': '',
      'haltbarkeit': '21 Tage',
    };

    Future<void> zeige(
      WidgetTester tester,
      EntwicklungsProjekt p, {
      Size groesse = const Size(1400, 1000),
      ThemeData? theme,
    }) async {
      tester.view.physicalSize = groesse;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            projektProvider.overrideWith((ref, id) => Stream.value(p)),
            spezVorschauProvider.overrideWith((ref, a) async => vorschau),
            spezStaendeProvider.overrideWith((ref, id) async => staende),
            spezVorlageProvider.overrideWith(
              (ref, s) async => s == SpezSprache.de ? vorlage : null,
            ),
            spezVorlagePlatzhalterProvider.overrideWith(
              (ref, s) async => s == SpezSprache.de
                  ? const {'artikelnummer', 'kuerzel', 'zutaten'}
                  : const <String>{},
            ),
            spezKuerzelProvider.overrideWith((ref) async => 'TE'),
            deeplHinterlegtProvider.overrideWith((ref) async => false),
          ],
          child: MaterialApp(
            theme: theme ?? AppTheme.light(),
            home: Scaffold(body: ProjektProdukt(projekt: p)),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    ButtonStyleButton knopf(WidgetTester tester, String text) =>
        tester.widget<ButtonStyleButton>(
          find.ancestor(
            of: find.text(text),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          ),
        );

    Finder bereich(String titel) => find.byWidgetPredicate(
          (w) => w is BereichKopf && w.titel == titel,
        );

    testWidgets('breit: links die Eingaben, rechts die Spezifikation',
        (tester) async {
      const angaben = SpezAngaben(
        toleranz: '± 5',
        spuren: {'senf'},
        verpackung: Verpackung(um: {'e2_kiste'}, atmosphaere: 'vakuum'),
      );
      await zeige(tester, projekt(spezifikation: angaben.alsJson()));
      expect(bereich('Sensorik'), findsOneWidget);
      expect(bereich('Spezifikation'), findsOneWidget);
      expect(
        find.text('Frikadelle Testart · Stand 1 · freigegeben'),
        findsOneWidget,
      );
      // Ein Weg zum Erstellen: das Fenster mit Sprache, Vorlage, Kürzel und
      // Datum — keine eigenen Knöpfe je Sprache mehr.
      expect(knopf(tester, 'Spezifikation erstellen…').enabled, isTrue);
      expect(find.text('Deutsch erstellen…'), findsNothing);
      expect(find.textContaining('Vorlage Deutsch'), findsNothing);
      expect(find.widgetWithText(TextField, 'TE'), findsNothing);

      // Stückgewicht und Toleranz stehen einmal — bei der Sensorik.
      expect(find.text('± 5'), findsOneWidget);
      expect(find.text('80 g'), findsOneWidget);
      final gewicht =
          tester.getTopLeft(find.byKey(const ValueKey('spez-gewicht'))).dy;
      expect(gewicht, greaterThan(tester.getTopLeft(bereich('Sensorik')).dy));
      expect(gewicht, lessThan(tester.getTopLeft(bereich('Angaben')).dy));
      // Die Artikelnummer steht in den Stammdaten.
      expect(find.byKey(const ValueKey('spez-artikelnummer')), findsNothing);

      bool gewaehlt(String label) => tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, label))
          .selected;
      expect(gewaehlt('Senf'), isTrue);
      expect(gewaehlt('Gluten'), isFalse);
      expect(gewaehlt('E2-Kiste'), isTrue);
      expect(gewaehlt('Karton groß'), isFalse);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Vakuum'))
            .selected,
        isTrue,
      );
      // Rechts neben den Eingaben; links Sensorik, Angaben, Verpackung
      // untereinander.
      expect(
        tester.getTopLeft(bereich('Spezifikation')).dx,
        greaterThan(tester.getTopLeft(bereich('Angaben')).dx + 300),
      );
      expect(
        tester.getTopLeft(bereich('Verpackung')).dx,
        tester.getTopLeft(bereich('Angaben')).dx,
      );
      expect(
        tester.getTopLeft(bereich('Verpackung')).dy,
        greaterThan(tester.getTopLeft(bereich('Angaben')).dy),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Erstellen öffnet das Fenster mit dem gewählten Stand',
        (tester) async {
      await zeige(tester, projekt());
      await tester.tap(find.byKey(const ValueKey('spez-erstellen')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final fenster = find.byType(SpezifikationDialog);
      expect(fenster, findsOneWidget);
      expect(tester.widget<SpezifikationDialog>(fenster).versionId, 'v1');
      expect(find.text('Spezifikation erstellen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('die Vorschau: was hineinkommt, was fehlt', (tester) async {
      await zeige(tester, projekt());
      expect(bereich('Was in die Spezifikation kommt'), findsOneWidget);
      expect(find.textContaining('mit Stand 1 · deutsch'), findsOneWidget);
      Finder inVorschau(Finder f) =>
          find.descendant(of: find.byType(SpezVorschau), matching: f);
      expect(
        inVorschau(
          find.text('Schweinefleisch (80 %), Wasser, SENF, Speisesalz'),
        ),
        findsOneWidget,
      );
      expect(inVorschau(find.text('80 g · Toleranz ± 5')), findsOneWidget);
      expect(
        inVorschau(
          find.textContaining('Energie 900 kJ / 215 kcal · Fett 16 g'),
        ),
        findsOneWidget,
      );
      expect(inVorschau(find.text('Keine')), findsOneWidget);
      expect(inVorschau(find.text('Sellerie')), findsOneWidget);
      expect(inVorschau(find.text('Optik: goldbraun')), findsOneWidget);
      // Artikelnummer und Lagerung fehlen — mit dem Ort zum Eintragen.
      expect(
        inVorschau(
          find.text('fehlt — in der Übersicht bei den Stammdaten eintragen'),
        ),
        findsOneWidget,
      );
      expect(
        inVorschau(find.text('fehlt — bei „Angaben" eintragen')),
        findsOneWidget,
      );
      // Das Produktfoto kommt neben die Sensorik — hier fehlt es noch.
      expect(
        inVorschau(find.text('fehlt — bei „Sensorik" hinterlegen')),
        findsOneWidget,
      );
      // Und hier stehen die Felder dafür.
      expect(find.byKey(const ValueKey('spez-lagerung')), findsOneWidget);
      expect(find.byKey(const ValueKey('spez-bezeichnung')), findsOneWidget);
      expect(
        find.text('leer: „Frikadelle Testart"'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('schmal und dunkel: untereinander, ohne Überlauf',
        (tester) async {
      await zeige(
        tester,
        projekt(),
        groesse: const Size(700, 1200),
        theme: AppTheme.dark(),
      );
      expect(tester.takeException(), isNull);
      expect(bereich('Sensorik'), findsOneWidget);
      final liste = find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('Einzelverpackung'),
        300,
        scrollable: liste,
      );
      await tester.pump();
      expect(find.text('Einzelverpackung'), findsOneWidget);
      // Untereinander: die Spezifikation am Ende, so breit wie alles.
      await tester.scrollUntilVisible(
        bereich('Spezifikation'),
        300,
        scrollable: liste,
      );
      await tester.pump();
      expect(tester.getTopLeft(bereich('Spezifikation')).dx, lessThan(60));
      expect(tester.takeException(), isNull);
    });
  });
}
