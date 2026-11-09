import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/druck/druck_optionen.dart';
import 'package:produktion_planer/core/services/entwicklung_daten.dart';
import 'package:produktion_planer/features/entwicklung/bericht/bericht_formblatt.dart';
import 'package:produktion_planer/features/entwicklung/bericht/bericht_pdf.dart';
import 'package:produktion_planer/features/entwicklung/bericht/projekt_bericht.dart';
import 'package:produktion_planer/features/entwicklung/daten/dateien.dart';
import 'package:produktion_planer/features/entwicklung/entwicklung_zugang.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_repository.dart';
import 'package:produktion_planer/features/entwicklung/spezifikation/spezifikation_dienst.dart'
    show spezVorlageId;
import 'package:produktion_planer/features/entwicklung/spezifikation/spezifikation_werte.dart'
    show SpezSprache;
import 'package:produktion_planer/features/entwicklung/spezifikation/xlsx_kopflogo.dart';

import 'helpers/pdf_lesen.dart';
import 'helpers/test_db.dart';

/// Kopf- und Fußzeile des Projektberichts wie auf einem Formblatt — und
/// die leere Vorlage, die zeigt, was wo im Bericht steht. Die PDFs
/// entstehen unkomprimiert, ihr Text lässt sich so lesen. Alle Daten sind
/// erfunden.
void main() {
  // Ein Bild mit einem Bildpunkt (PNG).
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAj'
    'CB0C8AAAAASUVORK5CYII=',
  );
  final datum = DateTime(2026, 11, 6);
  const angaben = BerichtFormblatt(
    nummer: 'FB_XY_042',
    erstelltVon: 'A. Beispiel',
    geprueftVon: 'B. Muster',
    version: '03 neue Kapitel',
    stand: '01.02.2026',
    ersetzt: '01.01.2025',
  );

  /// Eine kleine Excel-Mappe mit einem Bild in der Kopfzeile an [stelle]
  /// („RH" rechts oben) — so, wie Excel es ablegt: über die VML-Zeichnung
  /// des Blatts.
  Uint8List mappe({
    String stelle = 'RH',
    String stil = 'position:absolute;margin-left:0;width:120pt;height:30pt',
    List<int>? bild,
    bool mitZeichnung = true,
  }) {
    final archiv = Archive();
    void datei(String name, String text) {
      final bytes = utf8.encode(text);
      archiv.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    const rels =
        'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
    datei(
      'xl/workbook.xml',
      '<workbook xmlns:r="$rels"><sheets>'
          '<sheet name="Blatt" sheetId="1" r:id="rId1"/></sheets></workbook>',
    );
    datei(
      'xl/_rels/workbook.xml.rels',
      '<Relationships><Relationship Id="rId1" '
          'Target="worksheets/sheet1.xml"/></Relationships>',
    );
    datei(
      'xl/worksheets/sheet1.xml',
      '<worksheet xmlns:r="$rels"><sheetData/><headerFooter>'
          '<oddHeader>&amp;L&amp;"Arial"Kopf&amp;R&amp;G</oddHeader>'
          '</headerFooter>'
          '${mitZeichnung ? '<legacyDrawingHF r:id="rId3"/>' : ''}'
          '</worksheet>',
    );
    datei(
      'xl/worksheets/_rels/sheet1.xml.rels',
      '<Relationships><Relationship Id="rId3" '
          'Target="../drawings/vmlDrawing1.vml"/></Relationships>',
    );
    // Excel schreibt den Stil in einfachen Anführungszeichen.
    datei(
      'xl/drawings/vmlDrawing1.vml',
      '<xml xmlns:v="urn:schemas-microsoft-com:vml" '
          'xmlns:o="urn:schemas-microsoft-com:office:office">'
          '<v:shape id="$stelle" o:spid="_x0000_s1025" type="#_x0000_t75" '
          "style='$stil'>"
          '<v:imagedata o:relid="rId1" o:title="Logo"/>'
          '</v:shape></xml>',
    );
    datei(
      'xl/drawings/_rels/vmlDrawing1.vml.rels',
      '<Relationships><Relationship Id="rId1" '
          'Target="../media/image1.png"/></Relationships>',
    );
    final b = bild ?? png;
    archiv.addFile(ArchiveFile('xl/media/image1.png', b.length, b));
    return Uint8List.fromList(ZipEncoder().encode(archiv)!);
  }

  group('Angaben', () {
    test('gespeichert und gelesen — Unlesbares bleibt leer', () {
      final json = jsonDecode(
        jsonEncode(
          angaben.kopie(nummer: ' FB_XY_042 ', logoZeigen: false).toJson(),
        ),
      );
      final f = BerichtFormblatt.ausJson(json);
      expect(f.nummer, 'FB_XY_042');
      expect(f.erstelltVon, 'A. Beispiel');
      expect(f.version, '03 neue Kapitel');
      expect(f.ersetzt, '01.01.2025');
      expect(f.logoZeigen, isFalse);
      expect(f.leer, isFalse);

      expect(BerichtFormblatt.ausJson('kaputt').leer, isTrue);
      expect(BerichtFormblatt.ausJson({'nummer': 42}).nummer, '');
      expect(BerichtFormblatt.ausJson(<String, dynamic>{}).logoZeigen, isTrue);
      expect(const BerichtFormblatt().toJson(), {'logoZeigen': true});
    });

    test('der Fuß: links wer und welche Version, rechts der Stand', () {
      expect(angaben.fussLinks, [
        'Erstellt von: A. Beispiel',
        'Geprüft von: B. Muster',
        'Version: 03 neue Kapitel',
      ]);
      expect(angaben.fussRechts, [
        'Stand: 01.02.2026',
        'ersetzt den Stand: 01.01.2025',
      ]);
      // Was fehlt, steht nicht da.
      const nurStand = BerichtFormblatt(stand: '01.02.2026');
      expect(nurStand.fussLinks, isEmpty);
      expect(nurStand.fussRechts, ['Stand: 01.02.2026']);
    });

    test('neue Version: weitergezählt, Stand heute, der alte wird ersetzt', () {
      final neu = const BerichtFormblatt(
        version: '09 alte Struktur',
        stand: '01.02.2026',
        ersetzt: '01.01.2025',
      ).neueVersion(datum);
      expect(neu.version, '10 ');
      expect(neu.stand, '06.11.2026');
      expect(neu.ersetzt, '01.02.2026');
      expect(
        const BerichtFormblatt(version: '007 x').neueVersion(datum).version,
        '008 ',
      );
      // Ohne Nummer bleibt die Version, ohne Stand das, was er ersetzt.
      final ohne = const BerichtFormblatt(
        version: 'Erstausgabe',
        ersetzt: '01.01.2025',
      ).neueVersion(datum);
      expect(ohne.version, 'Erstausgabe');
      expect(ohne.stand, '06.11.2026');
      expect(ohne.ersetzt, '01.01.2025');
    });
  });

  group('Logo aus der Kopfzeile der Vorlage', () {
    test('rechts oben — so groß, wie die Vorlage es druckt', () {
      final logo = kopfzeilenLogo(mappe())!;
      expect(logo.bytes, png);
      expect(logo.breite, 120);
      expect(logo.hoehe, 30);
      // Andere Einheiten in Punkt.
      final zoll = kopfzeilenLogo(mappe(stil: 'width:2in;height:0.5in'))!;
      expect(zoll.breite, 144);
      expect(zoll.hoehe, 36);
      final pixel = kopfzeilenLogo(mappe(stil: 'width:160px;height:40'))!;
      expect(pixel.breite, 120);
      expect(pixel.hoehe, 30);
      expect(kopfzeilenLogo(mappe(stil: ''))!.breite, 0);
    });

    test('auch links oben — unten und ohne Zeichnung keins', () {
      expect(kopfzeilenLogo(mappe(stelle: 'LH')), isNotNull);
      expect(kopfzeilenLogo(mappe(stelle: 'RF')), isNull);
      expect(kopfzeilenLogo(mappe(mitZeichnung: false)), isNull);
    });

    test('nur JPEG oder PNG — keine Mappe wirft', () {
      // EMF kann das PDF nicht zeigen.
      expect(kopfzeilenLogo(mappe(bild: [1, 0, 0, 0, 108, 0, 0, 0])), isNull);
      expect(
        kopfzeilenLogo(mappe(bild: [0xFF, 0xD8, 0xFF, 0xE0, 0, 0]))?.bytes,
        [0xFF, 0xD8, 0xFF, 0xE0, 0, 0],
      );
      expect(
        () => kopfzeilenLogo(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
    });
  });

  group('im Bericht', () {
    late AppDatabase db;
    late ProjektRepository projekte;
    late EntwicklungDateienDienst dateien;

    setUp(() async {
      db = testDatenbank();
      projekte = ProjektRepository(db);
      dateien = EntwicklungDateienDienst(db);
      // Der Datenschlüssel entsteht mit dem Passwort.
      await EntwicklungZugang(
        DbEntwicklungsSpeicher(db),
        iterationen: 1000,
        imHintergrund: false,
      ).festlegen('geheim123');
    });
    tearDown(() => db.close());

    Future<String> bericht(BerichtFormblatt formblatt) async {
      final id = await projekte.projektAnlegen(name: 'Kopf Testart');
      await projekte.projektAendern(
        id,
        const EntwicklungProjekteCompanion(
          kunde: Value('Beispiel Feinkost'),
          artikelnummer: Value('90001'),
        ),
      );
      final b = await berichtLaden(db, dateien, (await projekte.projekt(id))!);
      return latin1.decode(
        await baueProjektPdf(
          b,
          gedrucktAm: datum,
          formblatt: formblatt,
          komprimiert: false,
        ),
      );
    }

    test('Kopf und Fuß auf jeder Seite — das Logo nur einmal im PDF', () async {
      final roh = await bericht(
        angaben.mitLogo(KopfLogo(bytes: png, breite: 120, hoehe: 30)),
      );
      final seiten = pdfSeiten(roh);
      expect(seiten.length, greaterThan(2));
      for (final (i, seite) in seiten.indexed) {
        final text = seitenText(seite);
        final grund = 'Seite ${i + 1}';
        // Oben links die Nummer, gleich daneben der Bericht — die Seite
        // steht unten rechts, unter den Ständen.
        expect(text, contains('FB_XY_042 Projektbericht'), reason: grund);
        expect(
          text,
          contains(
            'ersetzt den Stand: 01.01.2025 Seite ${i + 1} von '
            '${seiten.length}',
          ),
          reason: grund,
        );
        expect(
          text,
          contains('Kopf Testart · Beispiel Feinkost · Art.-Nr. 90001'),
          reason: grund,
        );
        for (final zeile in [
          'Erstellt von: A. Beispiel',
          'Geprüft von: B. Muster',
          'Version: 03 neue Kapitel',
          'Stand: 01.02.2026',
          'ersetzt den Stand: 01.01.2025',
        ]) {
          expect(text, contains(zeile), reason: '$grund: $zeile');
        }
        expect(seite, contains(_logo), reason: '$grund: das Logo');
      }
      // Wann gedruckt wurde, steht vorn — „Stand" ist der des Formblatts.
      expect(seitenText(seiten.first), contains('Gedruckt am 06.11.2026'));
      expect(roh, isNot(contains('(Planer)')));
      // Jede Seite zeichnet dasselbe Bild.
      expect(_logos(roh), hasLength(1));
    });

    test(
        'ohne Angaben: unten links wann gedruckt, rechts die Seite — kein '
        'Bild', () async {
      final roh = await bericht(const BerichtFormblatt());
      final seiten = pdfSeiten(roh);
      for (final (i, seite) in seiten.indexed) {
        final text = seitenText(seite);
        expect(
          text,
          contains(
            'Gedruckt am 06.11.2026 · Produktions Planer Seite ${i + 1} von '
            '${seiten.length}',
          ),
        );
        expect(text, isNot(contains('Erstellt von')));
      }
      expect(roh, isNot(contains('/Subtype/Image')));

      // Ausgeschaltet bleibt das Logo weg.
      final aus = await bericht(
        angaben
            .kopie(logoZeigen: false)
            .mitLogo(KopfLogo(bytes: png, breite: 120, hoehe: 30)),
      );
      expect(aus, isNot(contains('/Subtype/Image')));
    });

    test('Seite 1 trägt rechts unter dem Foto das Feld „Freigabe QS:"',
        () async {
      final seiten = pdfSeiten(await bericht(angaben));
      // Im Satz nach Titel und Phase, vor „Auf einen Blick" — in der
      // rechten Spalte oben auf der Seite, nicht mehr über dem Fuß.
      final eins = seitenText(seiten.first);
      expect(eins, contains('Freigabe QS: Auf einen Blick'));
      expect(eins, isNot(contains('Freigabe QS: Erstellt')));
      for (final seite in seiten.skip(1)) {
        expect(seitenText(seite), isNot(contains('Freigabe QS:')));
      }
    });

    test(
        'verschlüsselt gespeichert, mit dem Logo der Spezifikationsvorlage '
        'geladen — und im Backup', () async {
      expect((await berichtFormblattLaden(dateien)).leer, isTrue);

      await dateien.speichern(
        id: spezVorlageId(SpezSprache.de),
        name: 'Vorlage.xlsx',
        inhalt: mappe(),
      );
      await berichtFormblattSpeichern(dateien, angaben);
      final f = await berichtFormblattLaden(dateien);
      expect(f.nummer, 'FB_XY_042');
      expect(f.stand, '01.02.2026');
      expect(f.logo?.bytes, png);
      expect(f.logo?.breite, 120);
      // In der Datenbank steht nichts davon lesbar.
      final zeile = await (db.select(db.entwicklungDateiInhalte)
            ..where((d) => d.dateiId.equals(kBerichtFormblattId)))
          .getSingle();
      expect(latin1.decode(zeile.inhalt), isNot(contains('FB_XY_042')));

      // Ohne die deutsche Vorlage die englische.
      await dateien.loeschen(spezVorlageId(SpezSprache.de));
      expect((await berichtFormblattLaden(dateien)).logo, isNull);
      await dateien.speichern(
        id: spezVorlageId(SpezSprache.en),
        name: 'Template.xlsx',
        inhalt: mappe(stelle: 'LH'),
      );
      expect((await berichtFormblattLaden(dateien)).logo, isNotNull);

      // Ausgeschaltet wird es gar nicht erst gelesen.
      await berichtFormblattSpeichern(
        dateien,
        angaben.kopie(logoZeigen: false),
      );
      expect((await berichtFormblattLaden(dateien)).logo, isNull);
      expect(
        (await berichtFormblattLaden(dateien, mitLogo: false)).nummer,
        'FB_XY_042',
      );

      // Mit den Entwicklungsdaten im Backup.
      final daten = jsonDecode(jsonEncode(await EntwicklungDaten.lesen(db)))
          as Map<String, dynamic>;
      final inhalte = await EntwicklungDaten.dateiInhalte(db);
      await EntwicklungDaten.leeren(db);
      expect((await berichtFormblattLaden(dateien)).leer, isTrue);
      await EntwicklungDaten.schreiben(db, daten, inhalte);
      final zurueck = await berichtFormblattLaden(dateien);
      expect(zurueck.nummer, 'FB_XY_042');
      expect(zurueck.logoZeigen, isFalse);
    });
  });

  group('Vorlage', () {
    late String roh;
    late List<String> seiten;
    late String text;

    setUpAll(() async {
      roh = latin1.decode(
        await baueVorlagePdf(
          formblatt: angaben.mitLogo(
            KopfLogo(bytes: png, breite: 120, hoehe: 30),
          ),
          gedrucktAm: datum,
          komprimiert: false,
        ),
      );
      seiten = pdfSeiten(roh);
      text = seiten.map(seitenText).join(' ');
    });

    test('jede Überschrift und Spalte des Berichts steht auch hier', () {
      // Aus dem Bericht selbst gelesen: Kommt dort ein Abschnitt dazu,
      // fehlt er hier, bis die Vorlage ihn auch zeigt. Verglichen wird je
      // Art in ihrer Schrift — eine Überschrift zählt nur als Überschrift.
      final quelle = File(
        'lib/features/entwicklung/bericht/bericht_pdf.dart',
      ).readAsStringSync();
      Set<String> aufrufe(String namen, {bool mitSatz = false}) => {
            for (final m in RegExp(
              '(?:$namen)\\(\\s*${mitSatz ? 's,\\s*' : ''}\'([^\'\$]+)\'',
            ).allMatches(quelle))
              m[1]!,
          };
      // Größe der fetten Schrift → was der Bericht darin setzt.
      final titel = <double, Set<String>>{
        10.5: {
          ...aufrufe('_abschnitt'),
          ...aufrufe('_textAbschnitt', mitSatz: true),
        },
        7.5: {...aufrufe('_etikett'), ...aufrufe('_absatz', mitSatz: true)},
        6.5: aufrufe('_kachel|_kennzahl'),
        7: aufrufe('_wegKopf'),
        7.3: {
          for (final kopf in RegExp(
            r'kopf: const \[([^\]]*)\]',
          ).allMatches(quelle))
            // Auch leere Spalten ('') sind Texte — sonst verrutschen die
            // Anführungszeichen.
            for (final m in RegExp(r"'([^']*)'").allMatches(kopf[1]!))
              if (m[1]!.isNotEmpty && !m[1]!.contains(r'$')) m[1]!,
        },
      };
      // Der Bericht ist wirklich gelesen.
      expect(
        titel.values.expand((t) => t),
        containsAll([
          'Zusammensetzung',
          'Nährwerte',
          'Produktidee',
          'Grund für diesen Stand',
          'Originaletikett',
          'HACCP-Gefahrenanalyse',
          'Projekt-Checkliste',
          'Im Einzelnen',
          'FREIGABE',
          'BEFFE',
          'START',
          'Maßnahmen',
        ]),
      );
      final fett = fetteSchrift(roh);
      for (final MapEntry(key: groesse, value: liste) in titel.entries) {
        final gesetzt = [
          for (final s in seiten)
            seitenText(s, groesse: groesse, schrift: fett),
        ].join(' | ');
        for (final t in liste) {
          expect(gesetzt, contains(t), reason: '$t ($groesse pt)');
        }
      }
    });

    test('alle Kapitel, je auf einer Seite oben — im Inhalt mit Seite', () {
      final anfaenge = kapitelAnfaenge(roh);
      expect(anfaenge, hasLength(8));
      expect(anfaenge.first.seite, 2);
      for (var i = 1; i < anfaenge.length; i++) {
        expect(anfaenge[i].seite, greaterThan(anfaenge[i - 1].seite));
        expect(anfaenge[i].hoehe, anfaenge.first.hoehe);
      }
      for (final (i, k) in const [
        'Projekt',
        'Rezeptur',
        'Produkt und Spezifikation',
        'Herstellung und HACCP',
        'Freigabe und Checkliste',
        'Entwicklungsweg',
        'Verlauf',
        'Dateien',
      ].indexed) {
        expect(roh, contains('(${i + 1}  $k)'), reason: 'Lesezeichen $k');
        expect(
          seitenText(seiten.first),
          contains('${i + 1} $k ${anfaenge[i].seite}'),
          reason: 'Inhalt $k',
        );
      }
    });

    test('Kopf und Fuß wie im Bericht — statt Angaben, was dort steht', () {
      for (final (i, seite) in seiten.indexed) {
        final t = seitenText(seite);
        expect(t, contains('FB_XY_042 Projektbericht'));
        expect(t, contains('«Projektname» · «Kunde» · Art.-Nr.'));
        expect(t, contains('Erstellt von: A. Beispiel'));
        expect(
          t,
          contains(
            'ersetzt den Stand: 01.01.2025 Seite ${i + 1} von '
            '${seiten.length}',
          ),
        );
      }
      expect(_logos(roh), hasLength(1));
      expect(seitenText(seiten.first), contains('Gedruckt am «Datum»'));
      for (final platzhalter in [
        '«Kunde»',
        '«Zutatenverzeichnis aus der Rezeptur»',
        '«Scan des gedruckten Etiketts»',
        '«Gefahr»',
        '«Text des Eintrags»',
        '«Dateiname»',
      ]) {
        expect(text, contains(platzhalter));
      }
      // Kein Datum außer denen des Formblatts — auch nicht am Zeitstrahl.
      expect(roh, isNot(contains('06.11.2026')));
      expect(roh, isNot(contains('07.11.2026')));
    });

    test('auf Seite 1 das Feld „Freigabe QS:" — wie im Bericht', () {
      expect(
        seitenText(seiten.first),
        contains('«Produktfoto» Freigabe QS: Auf einen Blick'),
      );
      for (final seite in seiten.skip(1)) {
        expect(seitenText(seite), isNot(contains('Freigabe QS:')));
      }
    });

    test('ohne Angaben „Leere Vorlage" unten — der Dateiname nennt den Stand',
        () async {
      final leer = latin1.decode(
        await baueVorlagePdf(gedrucktAm: datum, komprimiert: false),
      );
      final leerSeiten = pdfSeiten(leer);
      expect(
        seitenText(leerSeiten.first),
        contains(
          'Leere Vorlage · Produktions Planer Seite 1 von '
          '${leerSeiten.length}',
        ),
      );
      expect(leer, isNot(contains('/Subtype/Image')));

      final auftrag = berichtVorlageDruckAuftrag(formblatt: () => angaben);
      final dokument = await auftrag.bauen(DruckWahl.standard(const []));
      expect(
        dokument.dateiname,
        'Projektbericht_Vorlage_FB_XY_042_Stand_01_02_2026',
      );
      expect(
        berichtVorlageDruck().dateiname,
        'Projektbericht_Vorlage',
      );
    });
  });
}

/// Wo eine Seite ein Bild zeichnet: „/I12 Do".
final RegExp _logo = RegExp(r'/I\d+ Do');

/// Die Bilder, die die Seiten zeichnen.
Set<String> _logos(String roh) => {
      for (final m in RegExp(r'/(I\d+) Do').allMatches(roh)) m[1]!,
    };
