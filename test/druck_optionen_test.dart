import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/druck/druck_layout.dart';
import 'package:produktion_planer/core/druck/druck_optionen.dart';
import 'package:produktion_planer/core/druck/druck_speicher.dart';

import 'helpers/test_db.dart';

/// Tests für die Wahl im Druckfenster: Standard, Merken und Wiederlesen,
/// was nicht gemerkt wird, das Ablegen in den Einstellungen und
/// Dateinamen.
void main() {
  const zeitraum = DruckWahlEins(
    schluessel: 'zeitraum',
    titel: 'Zeitraum',
    werte: [DruckWert('woche', 'Woche'), DruckWert('tag', 'Tag')],
    standard: 'woche',
  );
  const kaestchen = DruckSchalter(
    schluessel: 'kaestchen',
    titel: 'Kästchen zum Abhaken',
  );
  const erledigte = DruckSchalter(
    schluessel: 'erledigte',
    titel: 'Erledigtes',
    standard: false,
  );
  const abteilungen = DruckWahlMehrere(
    schluessel: 'abteilungen',
    titel: 'Abteilungen',
    werte: [
      DruckWert('a', 'A'),
      DruckWert('b', 'B'),
      DruckWert('c', 'C'),
    ],
    standard: {'a', 'b'},
    merken: false,
  );
  const tage = DruckWahlMehrere(
    schluessel: 'tage',
    titel: 'Tage',
    werte: [DruckWert('mo', 'Mo'), DruckWert('di', 'Di')],
    standard: {'mo', 'di'},
  );
  const optionen = <DruckOption>[
    zeitraum,
    kaestchen,
    erledigte,
    abteilungen,
    tage,
  ];

  test('Standard: was jede Möglichkeit vorsieht', () {
    final wahl = DruckWahl.standard(
      optionen,
      layout: const DruckLayout(papier: DruckPapier.a3),
    );
    expect(wahl.eins('zeitraum'), 'woche');
    expect(wahl.an('kaestchen'), isTrue);
    expect(wahl.an('erledigte'), isFalse);
    expect(wahl.mehrere('abteilungen'), {'a', 'b'});
    expect(wahl.layout.papier, DruckPapier.a3);
    // Unbekanntes: Schalter an, sonst leer.
    expect(wahl.an('gibtEsNicht'), isTrue);
    expect(wahl.mehrere('gibtEsNicht'), isEmpty);
  });

  test('Merken und wieder lesen — ohne, was nicht gemerkt wird', () {
    final wahl = DruckWahl.standard(optionen)
        .mit('zeitraum', 'tag')
        .mit('erledigte', true)
        .mit('abteilungen', {'c'})
        .mit('tage', {'di'})
        .mitLayout(
          const DruckLayout(anpassung: DruckAnpassung.eineSeite),
        );
    final json = jsonDecode(jsonEncode(wahl.toJson(optionen)));
    expect((json as Map)['werte'], isNot(contains('abteilungen')));

    final gelesen = DruckWahl.fromJson(json, optionen);
    expect(gelesen.eins('zeitraum'), 'tag');
    expect(gelesen.an('erledigte'), isTrue);
    expect(gelesen.mehrere('tage'), {'di'});
    // Die Abteilungen hängen an den Daten: wieder der Vorschlag.
    expect(gelesen.mehrere('abteilungen'), {'a', 'b'});
    expect(gelesen.layout.anpassung, DruckAnpassung.eineSeite);
  });

  test('Was nicht mehr passt, kommt aus dem Standard', () {
    final gelesen = DruckWahl.fromJson(
      {
        'layout': {'papier': 'a5'},
        'werte': {
          'zeitraum': 'monat',
          'kaestchen': 'ja',
          'tage': ['di', 'so'],
        },
      },
      optionen,
      layout: const DruckLayout(rand: DruckRand.schmal),
    );
    expect(gelesen.eins('zeitraum'), 'woche');
    expect(gelesen.an('kaestchen'), isTrue);
    // Den Sonntag gibt es nicht mehr — der Dienstag bleibt.
    expect(gelesen.mehrere('tage'), {'di'});
    expect(gelesen.layout.papier, DruckPapier.a5);
    expect(gelesen.layout.rand, DruckRand.schmal);

    final nichts = DruckWahl.fromJson('kaputt', optionen);
    expect(nichts.eins('zeitraum'), 'woche');
  });

  test('Sichtbar nur, wenn es zur Wahl passt', () {
    final nurWoche = DruckWahlMehrere(
      schluessel: 'tage',
      titel: 'Tage',
      werte: const [DruckWert('mo', 'Mo')],
      standard: const {'mo'},
      sichtbar: (w) => w.eins('zeitraum') == 'woche',
    );
    final wahl = DruckWahl.standard([zeitraum, nurWoche]);
    expect(nurWoche.istSichtbar(wahl), isTrue);
    expect(nurWoche.istSichtbar(wahl.mit('zeitraum', 'tag')), isFalse);
    expect(kaestchen.istSichtbar(wahl), isTrue);
  });

  test('In den Einstellungen: je Art des Dokuments', () async {
    final db = testDatenbank();
    addTearDown(db.close);
    expect(await druckEinstellungLaden(db, 'plan'), isNull);

    final wahl = DruckWahl.standard(optionen).mit('zeitraum', 'tag');
    await druckEinstellungSpeichern(db, 'plan', wahl.toJson(optionen));
    await druckEinstellungSpeichern(
      db,
      'plan',
      wahl.mit('erledigte', true).toJson(optionen),
    );
    final gelesen = DruckWahl.fromJson(
      await druckEinstellungLaden(db, 'plan'),
      optionen,
    );
    expect(gelesen.eins('zeitraum'), 'tag');
    expect(gelesen.an('erledigte'), isTrue);
    expect(await druckEinstellungLaden(db, 'datenblatt'), isNull);
  });

  test('Dateinamen ohne Umlaute und Sonderzeichen', () {
    expect(
      druckDateiname('Wochenplan KW 44 Wurstküche'),
      'Wochenplan_KW_44_Wurstkueche',
    );
    expect(druckDateiname('Tagesplan 2026-10-29'), 'Tagesplan_2026-10-29');
    expect(druckDateiname(' Größe: 5 % / Maß '), 'Groesse_5_Mass');
    expect(druckDateiname('…'), 'Druck');
  });
}
