import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/features/entwicklung/bericht/bericht_formblatt.dart';
import 'package:produktion_planer/features/entwicklung/bericht/bericht_pdf.dart';
import 'package:produktion_planer/features/entwicklung/projekte/entwicklungsstrang.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_modell.dart';
import 'package:produktion_planer/features/entwicklung/spezifikation/xlsx_kopflogo.dart';
import 'package:produktion_planer/features/entwicklung/statistik/entwicklung_auswertung.dart';
import 'package:produktion_planer/features/entwicklung/werkzeuge/entwicklung_statistik.dart';

import 'helpers/pdf_lesen.dart';

/// Der Bericht über die Produktentwicklung eines Zeitraums: Seite 1 mit
/// den Zahlen auf einen Blick und dem Inhalt, die Kapitel nach Wahl, wie
/// gezählt wird, der Kundenfilter, ein leerer Zeitraum — und vom Formblatt
/// des Projektberichts nur das Logo. Alles erfunden.
void main() {
  final heute = DateTime(2026, 11, 9);

  EntwicklungsProjekt projekt(
    String id,
    String name,
    DateTime angelegt, {
    String status = 'entwicklung',
    String? kunde,
    String? gesamtprojektId,
  }) =>
      EntwicklungsProjekt(
        id: id,
        name: name,
        status: status,
        kunde: kunde,
        gesamtprojektId: gesamtprojektId,
        neuerProzess: false,
        neueZutaten: false,
        createdAt: angelegt,
        updatedAt: angelegt,
      );

  var nr = 0;
  ProjektEintrag wechsel(
    String projektId,
    DateTime datum,
    ProjektStatus neu, {
    String? grund,
  }) =>
      ProjektEintrag(
        id: 'e${nr++}',
        projektId: projektId,
        art: EintragArt.meilenstein.schluessel,
        titel: statusMeilensteinTitel(neu),
        datum: datum,
        beschreibung: grund == null ? null : 'Grund: $grund',
        status: EintragStatus.erledigt.schluessel,
        wert: statusWert(ProjektStatus.entwicklung, neu),
        createdAt: datum,
        updatedAt: datum,
      );

  final projekte = [
    projekt(
      'p1',
      'Grillwurst Probe',
      DateTime(2026, 1, 15),
      status: 'produktion',
      kunde: 'Beispiel Feinkost',
      gesamtprojektId: 'g1',
    ),
    projekt(
      'p2',
      'Grillwurst Variante',
      DateTime(2026, 1, 15),
      status: 'eingestellt',
      kunde: 'Beispiel Feinkost',
      gesamtprojektId: 'g1',
    ),
    projekt(
      'p3',
      'Kochschinken Test',
      DateTime(2026, 6, 1),
      kunde: 'Muster Markt',
    ),
    projekt(
      'p4',
      'Salami Probe',
      DateTime(2025, 5, 10),
      status: 'produktion',
      kunde: 'Muster Markt',
    ),
  ];
  final eintraege = [
    wechsel('p1', DateTime(2026, 3, 20), ProjektStatus.produktion),
    wechsel(
      'p2',
      DateTime(2026, 3, 20),
      ProjektStatus.eingestellt,
      grund: 'Kunde hat die andere Variante gewählt',
    ),
    wechsel('p4', DateTime(2026, 2, 1), ProjektStatus.produktion),
  ];
  final gesamtprojekte = [
    Gesamtprojekt(
      id: 'g1',
      name: 'Anfrage Grillsortiment',
      kunde: 'Beispiel Feinkost',
      createdAt: DateTime(2026, 1, 15),
      updatedAt: DateTime(2026, 1, 15),
    ),
  ];
  final laeufe = musterLaeufe(
    projekte: projekte,
    gesamtprojekte: gesamtprojekte,
    eintraege: eintraege,
  );

  EntwicklungsberichtDaten daten(Zeitraum z, {String? kunde}) =>
      EntwicklungsberichtDaten(
        auswertung: entwicklungAuswerten(
          laeufe: laeufe,
          zeitraum: z,
          heute: heute,
          gesamtprojekte: gesamtprojekte,
          kunde: kunde,
        ),
        stand: entwicklungsStatistik(
          projekte: [
            for (final p in projekte)
              if (kundePasst(p.kunde, kunde)) p,
          ],
          rezepturen: const [],
          versionen: const [],
          zutaten: const [],
          eintraege: eintraege,
          jetzt: heute,
        ),
      );

  Future<List<String>> seiten(
    EntwicklungsberichtDaten d, {
    EntwicklungsberichtInhalt inhalt = const EntwicklungsberichtInhalt(),
    BerichtFormblatt formblatt = const BerichtFormblatt(),
  }) async =>
      pdfSeiten(
        latin1.decode(
          await baueEntwicklungsberichtPdf(
            d,
            inhalt: inhalt,
            formblatt: formblatt,
            gedrucktAm: heute,
            komprimiert: false,
          ),
        ),
      );

  test('Seite 1: auf einen Blick, mit dem Vorjahr, und der Inhalt', () async {
    final s = await seiten(daten(Zeitraum.jahr(2026)));
    final eins = seitenText(s.first);
    expect(eins, contains('BERICHT PRODUKTENTWICKLUNG'));
    expect(eins, contains('Produktentwicklung 2026'));
    expect(
      eins,
      contains('01.01.2026 - 31.12.2026 · alle Kunden · verglichen mit 2025'),
    );
    expect(eins, contains('Der Zeitraum läuft noch - Stand 09.11.2026.'));
    expect(
      eins,
      contains(
        'NEUE MUSTER 3 davon 2 in Gesamtprojekten 1 neue Anfrage 2025: 1 (+2)',
      ),
    );
    expect(
      eins,
      contains('GELISTET 2 davon 0 als Artikel freigegeben 2025: 0 (+2)'),
    );
    expect(
      eins,
      contains(
        'NICHT WEITER VERFOLGT 1 meist: Kunde hat die andere Variante '
        'gewählt 2025: 0 (+1)',
      ),
    );
    expect(eins, contains('LISTUNGSQUOTE 33 % 1 von 3 neuen Mustern gelistet'));
    for (final k in [
      '1 Kennzahlen',
      '2 Verlauf',
      '3 Was aus den Mustern wurde',
      '4 Nicht weiter verfolgt',
      '5 Muster im Einzelnen',
      '6 Stand heute',
    ]) {
      expect(eins, contains(k), reason: k);
    }
  });

  test('Kennzahlen mit dem Vorjahr und wie gezählt wird', () async {
    final s = await seiten(daten(Zeitraum.jahr(2026)));
    final alles = s.map(seitenText).join(' ');
    expect(alles, contains('Kennzahl 2026 2025 Veränderung'));
    expect(alles, contains('Neue Muster 3 1 +2'));
    expect(alles, contains('Gelistet (in Produktion gegangen) 2 0 +2'));
    expect(
      alles,
      contains('Listungsquote der neuen Muster 33 % 100 % -67 Pkt.'),
    );
    expect(alles, contains('Wie gezählt wird'));
    expect(alles, contains('Kunde hat die andere Variante gewählt'));
    // Die Muster im Einzelnen — die Salami aus dem Vorjahr, 2026 gelistet.
    expect(alles, contains('Im Zeitraum gelistet'));
    expect(
      alles,
      contains('Salami Probe Muster Markt 10.05.2025 01.02.2026 267'),
    );
    // Der Stand heute: der Kochschinken ist in Arbeit.
    expect(alles, contains('Kochschinken Test'));

    // Ohne Erklärungen und nur mit den Kennzahlen.
    final knapp = await seiten(
      daten(Zeitraum.jahr(2026)),
      inhalt: const EntwicklungsberichtInhalt(
        kapitel: {EntwicklungsberichtKapitel.kennzahlen},
        erklaerungen: false,
      ),
    );
    final text = knapp.map(seitenText).join(' ');
    expect(text, isNot(contains('Wie gezählt wird')));
    expect(text, isNot(contains('2 Verlauf')));
    expect(text, isNot(contains('Stand heute')));
    expect(knapp, hasLength(2));
  });

  test('der Kundenfilter steht oben — und filtert', () async {
    final s = await seiten(
      daten(Zeitraum.jahr(2026), kunde: 'muster markt'),
    );
    final eins = seitenText(s.first);
    expect(eins, contains('Kunde muster markt'));
    expect(eins, contains('NEUE MUSTER 1'));
    final alles = s.map(seitenText).join(' ');
    expect(alles, isNot(contains('Grillwurst')));
  });

  test('ein leerer Zeitraum: nur, was es zu sagen gibt', () async {
    final d = daten(Zeitraum.jahr(2019));
    expect(
      [for (final (k, _) in entwicklungsberichtKapitelVon(d)) k],
      [
        EntwicklungsberichtKapitel.kennzahlen,
        EntwicklungsberichtKapitel.ergebnis,
        EntwicklungsberichtKapitel.stand,
      ],
    );
    final alles = (await seiten(d)).map(seitenText).join(' ');
    expect(alles, contains('Im Zeitraum wurde kein Muster angelegt.'));
    expect(alles, isNot(contains('Der Zeitraum läuft noch')));
  });

  test('vom Formblatt nur das Logo — ohne seine Nummer', () async {
    final bild = img.Image(width: 300, height: 60);
    img.fill(bild, color: img.ColorRgb8(31, 78, 121));
    final formblatt = const BerichtFormblatt(nummer: 'FB_XY_042').mitLogo(
      KopfLogo(
        bytes: Uint8List.fromList(img.encodePng(bild)),
        breite: 100,
        hoehe: 20,
      ),
    );
    final mit = await seiten(daten(Zeitraum.jahr(2026)), formblatt: formblatt);
    expect(mit.join(), isNot(contains('FB_XY_042')));
    expect(seitenText(mit[1]), contains('Bericht Produktentwicklung'));
    expect(RegExp(r'/I\d+ Do').hasMatch(mit.first), isTrue);

    final ohne = await seiten(
      daten(Zeitraum.jahr(2026)),
      formblatt: formblatt.kopie(logoZeigen: false),
    );
    expect(RegExp(r'/I\d+ Do').hasMatch(ohne.first), isFalse);
  });
}
