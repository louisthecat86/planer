import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/constants/parameter_namen.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/prozesskette_service.dart';
import 'package:produktion_planer/features/entwicklung/haccp/anlagen_katalog.dart';
import 'package:produktion_planer/features/entwicklung/haccp/prozess_kette.dart';
import 'package:produktion_planer/features/entwicklung/haccp/prozess_modell.dart';

import 'helpers/test_db.dart';

/// Tests für die Prozesskette eines Projekts (F32–F34): Modell, Stationen,
/// Umbauen durch Ziehen, Werte je Schritt, Übernehmen aus dem Artikel, das
/// Umsetzen der früheren Abschnitte, Vergleich und Versionen. Alle Anlagen
/// und Werte sind erfunden.
void main() {
  const wolf = KatalogAnlage(
    id: 'm-wolf',
    name: 'Testwolf',
    abteilung: 'zerlegung',
    steckbrief: [
      SteckbriefFeld('Lochscheibe', einheit: 'mm'),
      SteckbriefFeld('Drehzahl', einheit: 'U/min'),
    ],
  );
  const brat = KatalogAnlage(
    id: 'm-brat',
    name: 'Testbratstraße',
    abteilung: 'bratstrasse',
    steckbrief: [SteckbriefFeld('Bandgeschwindigkeit', einheit: 'm/min')],
  );
  const froster = KatalogAnlage(
    id: 'm-frost',
    name: 'Testfroster',
    abteilung: 'bratstrasse',
  );
  const packer = KatalogAnlage(
    id: 'm-pack',
    name: 'Testpacker',
    abteilung: 'verpackung',
  );
  const katalog = [wolf, brat, froster, packer];

  ProzessSchritt schritt(
    String id,
    String abteilung, {
    String maschine = '',
    List<ProzessWert> werte = const [],
  }) =>
      ProzessSchritt(
        id: id,
        abteilung: abteilung,
        maschine: maschine,
        werte: werte,
      );

  // Zwei in der Zerlegung, zwei an der Bratstraße, einer in der Verpackung.
  final kette = [
    schritt('a', 'zerlegung'),
    schritt('b', 'zerlegung'),
    schritt('c', 'bratstrasse'),
    schritt('d', 'bratstrasse'),
    schritt('e', 'verpackung'),
  ];
  List<String> ids(List<ProzessSchritt>? l) => [for (final s in l!) s.id];

  group('Modell', () {
    test('als JSON hin und zurück', () {
      final p = Prozessparameter(
        version: '1.2',
        stand: DateTime(2026, 10, 20),
        schritte: const [
          ProzessSchritt(
            id: 's1',
            abteilung: 'zerlegung',
            maschineId: 'm-wolf',
            maschine: 'Testwolf',
            prozessschritt: 'Wolfen',
            notiz: 'Messer frisch geschliffen',
            werte: [
              ProzessWert(
                name: 'Lochscheibe',
                wert: '3',
                einheit: 'mm',
                gruppe: kMaschinenNotizGruppe,
              ),
              ProzessWert(
                name: 'Kerntemperatur',
                gruppe: kEigeneWerteGruppe,
                eigen: true,
              ),
            ],
          ),
          ProzessSchritt(id: 's2', prozessschritt: 'Abkühlen'),
        ],
      );
      final zurueck = Prozessparameter.aus(p.alsJson());
      expect(zurueck.version, '1.2');
      expect(zurueck.stand, DateTime(2026, 10, 20));
      expect(gleicheParameter(p, zurueck), isTrue);
      final s = zurueck.schritte.first;
      expect(
        (s.maschineId, s.maschine, s.prozessschritt, s.notiz),
        ('m-wolf', 'Testwolf', 'Wolfen', 'Messer frisch geschliffen'),
      );
      expect(s.werte.first.label, 'Lochscheibe (mm)');
      expect(s.werte.last.eigen, isTrue);
      // Ohne Anlage heißt der Schritt wie sein Prozessschritt.
      final ohne = zurueck.schritte.last;
      expect((ohne.maschineId, ohne.name), (null, 'Abkühlen'));
      expect(const ProzessSchritt(id: 'x').bezeichnung(4), 'Schritt 4');
    });

    test('leer gibt es kein JSON; frühere Abschnitte bleiben lesbar', () {
      expect(const Prozessparameter().alsJson(), isNull);
      final alt = Prozessparameter.aus(
        '{"version":"1.1","abschnitte":[{"id":"garen","titel":"Garen",'
        '"felder":[{"id":"t","label":"Temperatur","wert":"180",'
        '"typ":"text"}]}]}',
      );
      expect(alt.schritte, isEmpty);
      expect(alt.abschnitte.single.felder.single.wert, '180');
      expect((alt.leer, alt.beschrieben), (false, true));
      expect(Prozessparameter.aus('kein JSON').leer, isTrue);
      // Ein Gerüst ohne Werte ist noch nichts.
      const geruest = Prozessparameter(
        abschnitte: [
          ProzessAbschnitt(
            id: 'g',
            titel: 'Garen',
            felder: [ProzessFeld(id: 't', label: 'Temperatur')],
          ),
        ],
      );
      expect(geruest.beschrieben, isFalse);
      expect(
        const Prozessparameter(schritte: [ProzessSchritt(id: 'x')]).beschrieben,
        isTrue,
      );
    });
  });

  group('Stationen und Umbau', () {
    test('Stationen: Schritte derselben Abteilung hintereinander', () {
      expect(
        [for (final b in stationenAus(kette)) ids(b)],
        [
          ['a', 'b'],
          ['c', 'd'],
          ['e'],
        ],
      );
      // Getrennt ist dieselbe Abteilung zwei Stationen.
      expect(
        stationenAus([
          schritt('a', 'zerlegung'),
          schritt('c', 'bratstrasse'),
          schritt('b', 'zerlegung'),
        ]).length,
        3,
      );
      final k = ProjektKette(kette);
      expect((k.indexVon('d'), k.stationVon('d'), k.grenzeVor(2)), (3, 1, 4));
      expect((k.indexVon('x'), k.stationVon('x'), k.grenzeVor(9)), (-1, -1, 5));
    });

    test('in der eigenen Station: wie beim Umsortieren einer Liste', () {
      final k = ProjektKette(kette);
      // Nach rechts gezogen landet er dahinter, nach links davor.
      expect(
        ids(
          k.umbau(
            const ProzessSchrittZug('a'),
            const ProzessZielSchritt('b', 0),
          ),
        ),
        ['b', 'a', 'c', 'd', 'e'],
      );
      expect(
        ids(
          k.umbau(
            const ProzessSchrittZug('b'),
            const ProzessZielSchritt('a', 0),
          ),
        ),
        ['b', 'a', 'c', 'd', 'e'],
      );
    });

    test('in eine andere Station: arbeitet dort für deren Abteilung', () {
      final k = ProjektKette(kette);
      final neu = k.umbau(
        const ProzessSchrittZug('e'),
        const ProzessZielSchritt('c', 1),
      );
      expect(ids(neu), ['a', 'b', 'e', 'c', 'd']);
      expect(neu![2].abteilung, 'bratstrasse');
      // Auf die Station: an ihr Ende.
      final ende = k.umbau(
        const ProzessSchrittZug('a'),
        const ProzessZielStation(1),
      );
      expect(ids(ende), ['b', 'c', 'd', 'a', 'e']);
      expect(ende![3].abteilung, 'bratstrasse');
    });

    test('in eine Lücke: bleibt in seiner Abteilung, eine eigene Station', () {
      final k = ProjektKette(kette);
      final vorn = k.umbau(
        const ProzessSchrittZug('c'),
        const ProzessZielLuecke(0),
      );
      expect(ids(vorn), ['c', 'a', 'b', 'd', 'e']);
      expect(vorn!.first.abteilung, 'bratstrasse');
      expect(stationenAus(vorn).length, 4);
      expect(
        ids(k.umbau(const ProzessSchrittZug('c'), const ProzessZielLuecke(3))),
        ['a', 'b', 'd', 'e', 'c'],
      );
    });

    test('eine ganze Station verschieben', () {
      final k = ProjektKette(kette);
      expect(
        ids(k.umbau(const ProzessStationsZug(0), const ProzessZielLuecke(3))),
        ['c', 'd', 'e', 'a', 'b'],
      );
      expect(
        ids(k.umbau(const ProzessStationsZug(2), const ProzessZielStation(0))),
        ['e', 'a', 'b', 'c', 'd'],
      );
    });

    test('nichts zu ändern oder ein Ziel, das nicht passt: null', () {
      final k = ProjektKette(kette);
      expect(
        k.umbau(const ProzessSchrittZug('a'), const ProzessZielSchritt('a', 0)),
        isNull,
      );
      expect(
        k.umbau(const ProzessSchrittZug('a'), const ProzessZielLuecke(0)),
        isNull,
      );
      // Allein in der eigenen Station: Da ist nichts zu tun.
      expect(
        k.umbau(const ProzessSchrittZug('e'), const ProzessZielStation(2)),
        isNull,
      );
      expect(
        k.umbau(const ProzessStationsZug(1), const ProzessZielStation(1)),
        isNull,
      );
      expect(
        k.umbau(const ProzessSchrittZug('a'), const ProzessZielStation(7)),
        isNull,
      );
      expect(
        k.umbau(const ProzessSchrittZug('a'), const ProzessZielSchritt('c', 0)),
        isNull,
      );
      expect(
        k.umbau(const ProzessSchrittZug('x'), const ProzessZielLuecke(0)),
        isNull,
      );
      expect(
        k.umbau(const ProzessStationsZug(5), const ProzessZielLuecke(0)),
        isNull,
      );
    });

    test('einfügen, ersetzen, entfernen — höchstens 20 Schritte', () {
      // So viele wie im Artikel (die Spalten der Excel-Vorlage).
      expect(kProzessMaxSchritte, ProzesskettenService.maxSchritte);
      final k = ProjektKette(kette);
      expect(
        ids(k.einfuegen(2, schritt('n', 'zerlegung'))),
        ['a', 'b', 'n', 'c', 'd', 'e'],
      );
      expect(ids(k.einfuegen(99, schritt('n', ''))).last, 'n');
      expect(
        k.ersetzen(kette[1].kopie(prozessschritt: 'Wolfen'))[1].prozessschritt,
        'Wolfen',
      );
      expect(ids(k.entfernen('c')), ['a', 'b', 'd', 'e']);
      final voll = ProjektKette([
        for (var i = 0; i < 20; i++) schritt('s$i', 'zerlegung'),
      ]);
      expect(voll.voll, isTrue);
      expect(voll.einfuegen(0, schritt('n', 'zerlegung')), isNull);
    });

    test('eine Station bekommt ihre Abteilung', () {
      final k = ProjektKette([
        schritt('a', ''),
        schritt('b', ''),
        schritt('c', 'verpackung'),
      ]);
      final neu = k.stationAbteilung(0, 'bratstrasse');
      expect(
        [for (final s in neu) '${s.id}:${s.abteilung}'],
        ['a:bratstrasse', 'b:bratstrasse', 'c:verpackung'],
      );
      expect(identical(k.stationAbteilung(5, 'zerlegung'), k.schritte), isTrue);
    });

    test('Kurztext: Schritte und Stationen, sonst Abschnitte', () {
      expect(
        prozessKurztext(Prozessparameter(schritte: kette)),
        '5 Schritte · 3 Stationen',
      );
      expect(
        prozessKurztext(
          const Prozessparameter(schritte: [ProzessSchritt(id: 'x')]),
        ),
        '1 Schritt · 1 Station',
      );
      expect(
        prozessKurztext(
          const Prozessparameter(
            abschnitte: [ProzessAbschnitt(id: 'g', titel: 'Garen')],
          ),
        ),
        '1 Abschnitt',
      );
      expect(prozessKurztext(const Prozessparameter()), '');
    });
  });

  group('Werte eines Schritts', () {
    test('Steckbrief: setzen, ändern, leeren', () {
      final s = schritt('s', 'zerlegung', maschine: 'Testwolf');
      final f = wolf.steckbrief.first;
      final s1 = mitSteckbriefWert(s, f, ' 3 ');
      final w = s1.werte.single;
      expect(
        (w.name, w.wert, w.einheit, w.gruppe, w.eigen),
        ('Lochscheibe', '3', 'mm', kMaschinenNotizGruppe, false),
      );
      final s2 = mitSteckbriefWert(s1, f, '4,5');
      expect(s2.werte.single.wert, '4,5');
      expect(mitSteckbriefWert(s2, f, '').werte, isEmpty);
      expect(identical(mitSteckbriefWert(s, f, '  '), s), isTrue);
    });

    test('wie im Artikel: über den Namen, die Maschinengruppe zuerst', () {
      final s = schritt(
        's',
        'zerlegung',
        werte: const [
          ProzessWert(
            name: 'lochscheibe',
            wert: '2',
            gruppe: kMaschinenNotizGruppe,
          ),
          ProzessWert(name: 'Lochscheibe', wert: '5', gruppe: 'WOLF'),
        ],
      );
      expect(steckbriefWert(s, 'Lochscheibe')!.wert, '5');
      expect(steckbriefGruppe(s), 'WOLF');
      // Neue Werte kommen in die Gruppe, die der Schritt schon benutzt.
      final mit = mitSteckbriefWert(s, wolf.steckbrief.last, '1500');
      expect(mit.werte.last.gruppe, 'WOLF');
      expect(steckbriefGruppe(schritt('t', '')), kMaschinenNotizGruppe);
      expect(
        steckbriefGruppe(
          schritt(
            't',
            '',
            werte: const [
              ProzessWert(name: 'X', gruppe: kEigeneWerteGruppe, eigen: true),
            ],
          ),
        ),
        kMaschinenNotizGruppe,
      );
    });

    test('Platten: je Name und Gruppe der Anlage', () {
      expect(plattenGruppe('Testbratstraße'), kPlattenGruppeBrat);
      expect(plattenGruppe('Testkombiofen'), kPlattenGruppeKombi);
      expect(plattenGruppe('Testwolf'), isNull);
      final s = schritt('p', 'bratstrasse', maschine: 'Testbratstraße');
      final s1 = mitPlatten(s, kPlattenGruppeBrat, {
        'Platte Oben 1': ' 180 ',
        'Platte Unten 1': '',
      });
      expect(plattenWert(s1, 'Platte Oben 1', kPlattenGruppeBrat), '180');
      expect(plattenWert(s1, 'Platte Unten 1', kPlattenGruppeBrat), '');
      expect(plattenWert(s1, 'Platte Oben 1', kPlattenGruppeKombi), '');
      expect(istPlattenWert(s1.werte.single), isTrue);
      expect(
        mitPlatten(s1, kPlattenGruppeBrat, {'Platte Oben 1': ''}).werte,
        isEmpty,
      );
    });

    test('weitere und eigene Werte', () {
      const fuellhoehe = ProzessWert(
        name: 'Füllhöhe',
        wert: '10',
        gruppe: 'FÜLLMASCHINE',
      );
      const kern = ProzessWert(
        name: 'Kerntemperatur',
        gruppe: kEigeneWerteGruppe,
        eigen: true,
      );
      final s = schritt(
        's',
        'zerlegung',
        maschine: 'Testwolf',
        werte: const [
          ProzessWert(
            name: 'Lochscheibe',
            wert: '3',
            gruppe: kMaschinenNotizGruppe,
          ),
          fuellhoehe,
          kern,
          ProzessWert(
            name: 'Platte Oben 1',
            wert: '180',
            gruppe: kPlattenGruppeBrat,
          ),
        ],
      );
      expect(
        [for (final w in weitereWerte(s, wolf.steckbrief)) w.name],
        ['Füllhöhe'],
      );
      expect([for (final w in eigeneWerte(s)) w.name], ['Kerntemperatur']);
      expect(mitEigenemWert(s, 'kerntemperatur'), isNull);
      expect(mitEigenemWert(s, '  '), isNull);
      final neu = mitEigenemWert(s, ' Garzeit ')!.werte.last;
      expect(
        (neu.name, neu.gruppe, neu.eigen),
        ('Garzeit', kEigeneWerteGruppe, true),
      );
      final geaendert =
          wertSetzen(s, alt: fuellhoehe, neu: fuellhoehe.kopie(wert: '12'));
      expect(geaendert.werte[1].wert, '12');
      expect(eigeneWerte(wertSetzen(s, alt: kern)), isEmpty);
      expect(wertSetzen(s, neu: kern).werte.length, 5);
    });

    test('wie viele Werte eingetragen sind — die Platten zählen als einer', () {
      final w = schritt(
        'w',
        'zerlegung',
        maschine: 'Testwolf',
        werte: const [
          ProzessWert(
            name: 'Lochscheibe',
            wert: '3',
            gruppe: kMaschinenNotizGruppe,
          ),
          ProzessWert(
            name: 'Kerntemperatur',
            gruppe: kEigeneWerteGruppe,
            eigen: true,
          ),
        ],
      );
      expect(werteStand(w, wolf), (eingetragen: 1, gesamt: 3));
      final b = schritt('b', 'bratstrasse', maschine: 'Testbratstraße');
      expect(werteStand(b, brat), (eingetragen: 0, gesamt: 2));
      expect(
        werteStand(
          mitPlatten(b, kPlattenGruppeBrat, {'Platte Unten 4': '170'}),
          brat,
        ),
        (eingetragen: 1, gesamt: 2),
      );
      expect(
        werteStand(schritt('x', 'verpackung'), null),
        (eingetragen: 0, gesamt: 0),
      );
    });

    test('eine andere Anlage: Platten, die nicht passen, entfallen', () {
      final s = mitPlatten(
        schritt(
          's',
          'bratstrasse',
          maschine: 'Testbratstraße',
          werte: const [
            ProzessWert(name: 'Bandgeschwindigkeit', wert: '4'),
          ],
        ).mitAnlage('m-brat', 'Testbratstraße'),
        kPlattenGruppeBrat,
        {'Platte Oben 1': '180'},
      );
      final froster = anlageSetzen(
        s,
        const KatalogAnlage(
          id: 'm-frost',
          name: 'Testfroster',
          abteilung: 'bratstrasse',
        ),
      );
      expect(
        (froster.maschineId, froster.maschine),
        ('m-frost', 'Testfroster'),
      );
      expect([for (final w in froster.werte) w.name], ['Bandgeschwindigkeit']);
      // Eine zweite Bratstraße behält die Platten.
      final zweite = anlageSetzen(
        s,
        const KatalogAnlage(
          id: 'm-brat2',
          name: 'Testbratstraße 2',
          abteilung: 'bratstrasse',
        ),
      );
      expect(zweite.werte, hasLength(2));
      // Ohne Katalog bleibt der Name als Text, ganz ohne ist er leer.
      expect(anlageSetzen(s, null, name: ' Altanlage ').maschine, 'Altanlage');
      final ohne = anlageSetzen(s, null);
      expect((ohne.maschineId, ohne.maschine, ohne.name), (null, '', ''));
      expect(ohne.prozessschritt, s.prozessschritt);
    });

    test('für den Bericht: Einstellungen, Werte, Platten je Reihe', () {
      final s = mitPlatten(
        const ProzessSchritt(
          id: 'b',
          abteilung: 'bratstrasse',
          maschine: 'Testbratstraße',
          notiz: ' Band mittig ',
          werte: [
            ProzessWert(
              name: 'Bandgeschwindigkeit',
              wert: '4',
              einheit: 'm/min',
            ),
            ProzessWert(name: 'Ölmenge'),
          ],
        ),
        kPlattenGruppeBrat,
        {'Platte Oben 1': '180', 'Platte Oben 3': '175'},
      );
      expect(schrittZeilen(s), [
        ('Maschineneinstellungen', 'Band mittig'),
        ('Bandgeschwindigkeit (m/min)', '4'),
        ('Platten oben (°C)', '180 · – · 175 · – · – · – · – · – · – · –'),
      ]);
      // Ohne Plattenraster und ohne Werte: nichts.
      expect(schrittZeilen(schritt('x', 'verpackung')), isEmpty);
    });
  });

  group('Grenzen der Werte', () {
    const grenze = ParameterGrenze(
      hartMin: 0,
      hartMax: 250,
      weichMin: 150,
      weichMax: 220,
    );

    test('hart sperrt, weich warnt — wie im Artikel', () {
      expect(grenzePruefen(grenze, '180'), (blockiert: false, meldung: null));
      expect(
        grenzePruefen(grenze, '260'),
        (blockiert: true, meldung: 'Über der technischen Obergrenze (250).'),
      );
      expect(
        grenzePruefen(grenze, '-1'),
        (blockiert: true, meldung: 'Unter der technischen Untergrenze (0).'),
      );
      expect(
        grenzePruefen(grenze, '230,5'),
        (blockiert: false, meldung: 'Ungewöhnlich hoch — üblich ist bis 220.'),
      );
      expect(
        grenzePruefen(grenze, '120'),
        (
          blockiert: false,
          meldung: 'Ungewöhnlich niedrig — üblich ist ab 150.',
        ),
      );
      // Was keine Zahl ist, und ohne Grenze: ungeprüft.
      expect(grenzePruefen(grenze, 'heiß'), (blockiert: false, meldung: null));
      expect(grenzePruefen(null, '999'), (blockiert: false, meldung: null));
    });

    test('zuerst die Grenze der Anlage, dann die der Gruppe', () {
      final k = GrenzenKatalog({
        GrenzenKatalog.schluessel('Testbratstraße', 'Bandgeschwindigkeit'):
            const ParameterGrenze(hartMax: 8),
        GrenzenKatalog.schluessel(kMaschinenNotizGruppe, 'Bandgeschwindigkeit'):
            const ParameterGrenze(hartMax: 5),
      });
      expect(
        k
            .fuer(
              name: 'Bandgeschwindigkeit',
              maschine: 'Testbratstraße',
              gruppe: kMaschinenNotizGruppe,
            )
            ?.hartMax,
        8,
      );
      expect(
        k
            .fuer(
              name: 'Bandgeschwindigkeit',
              maschine: 'Testwolf',
              gruppe: kMaschinenNotizGruppe,
            )
            ?.hartMax,
        5,
      );
      expect(k.fuer(name: 'Ölmenge', maschine: 'Testbratstraße'), isNull);
      expect(const GrenzenKatalog().fuer(name: 'X'), isNull);
    });
  });

  group('Aus dem Artikel', () {
    test('Notiz, Werte mit Einheit, ohne Marker und leere Zeilen', () {
      final s = schrittAusArtikel(
        id: 'n1',
        abteilung: 'bratstrasse',
        maschineId: 'm-brat',
        maschine: 'alter Text',
        prozessschritt: ' Braten ',
        anlage: brat,
        parameter: const [
          (
            gruppe: 'BRATSTRASSE',
            name: 'Plattenschema',
            wert: 'x',
            eigen: false
          ),
          (
            gruppe: kMaschinenNotizGruppe,
            name: kMaschinenNotizParam,
            wert: 'Band mittig',
            eigen: false,
          ),
          (
            gruppe: 'BRATSTRASSE',
            name: 'bandgeschwindigkeit',
            wert: '3,5',
            eigen: false,
          ),
          (
            gruppe: kPlattenGruppeBrat,
            name: 'Platte Oben 1',
            wert: '180',
            eigen: false,
          ),
          (gruppe: 'BRATSTRASSE', name: 'Ölmenge', wert: null, eigen: false),
          (gruppe: 'CUSTOM', name: 'Garzeit', wert: '', eigen: true),
        ],
      );
      expect(
        (s.id, s.maschineId, s.maschine, s.prozessschritt, s.notiz),
        ('n1', 'm-brat', 'Testbratstraße', 'Braten', 'Band mittig'),
      );
      expect(
        [for (final w in s.werte) '${w.gruppe}/${w.label}=${w.wert}'],
        [
          'BRATSTRASSE/bandgeschwindigkeit (m/min)=3,5',
          'BRATSTRASSE/Platte Oben 1=180',
          'CUSTOM/Garzeit=',
        ],
      );
      // Ohne Anlage im Katalog bleibt der Text.
      final alt = schrittAusArtikel(
        id: 'n2',
        abteilung: 'verpackung',
        maschine: ' Altanlage ',
      );
      expect((alt.maschineId, alt.maschine), (null, 'Altanlage'));
      var n = 0;
      expect(
        ids(mitNeuenIds([alt, s], () => 'k${++n}')),
        ['k1', 'k2'],
      );
    });
  });

  group('Frühere Abschnitte werden zur Kette (F34)', () {
    final am = DateTime(2026, 9, 30);
    final frueher = Prozessparameter(
      version: '1.1',
      stand: am,
      abschnitte: const [
        ProzessAbschnitt(
          id: 'wolf',
          titel: 'Testwolf',
          felder: [
            ProzessFeld(id: 'l', label: 'Lochscheibe (mm)', wert: '3'),
            ProzessFeld(id: 'h', label: 'Hinweis', wert: 'kalt wolfen'),
          ],
        ),
        ProzessAbschnitt(
          id: 'garen',
          titel: 'Garen und Braten',
          felder: [
            ProzessFeld(id: 'anlage', label: 'Anlage', wert: 'testbratstraße'),
            ProzessFeld(id: 'b', label: 'Bandgeschwindigkeit', wert: '4'),
            ProzessFeld(id: 't', label: 'Temperaturen (°C)', wert: '180'),
          ],
        ),
        ProzessAbschnitt(
          id: 'kuehlen',
          titel: 'Kühlen und Frosten',
          felder: [
            ProzessFeld(id: 'anlage', label: 'Anlage', wert: 'Spiralfroster'),
            ProzessFeld(
              id: 'e',
              label: 'Maschine und Einstellungen',
              wert: '-30 °C, 40 min',
            ),
          ],
        ),
        ProzessAbschnitt(
          id: 'verpackung',
          titel: 'Verpackung',
          felder: [
            ProzessFeld(
              id: 'art',
              label: 'Verpackungsart',
              typ: FeldTyp.auswahl,
              optionen: ['Vakuum', 'offen'],
              wert: 'Vakuum',
            ),
          ],
        ),
        // Das Gerüst der früheren Vorlage, nie ausgefüllt.
        ProzessAbschnitt(
          id: 'formen',
          titel: 'Formen und Füllen',
          felder: [ProzessFeld(id: 'huelle', label: 'Hülle oder Form')],
        ),
      ],
    );

    test('je Abschnitt ein Schritt, mit Anlage und Werten', () {
      final r = prozessUmsetzen(frueher, katalog);
      expect((r.schritte, r.entfallen), (4, 1));
      final p = r.prozess;
      expect((p.version, p.stand), ('1.1', am));
      expect(p.abschnitte, isEmpty);
      final [w, b, k, v] = p.schritte;

      // Der Abschnitt hieß wie die Anlage: kein eigener Prozessschritt.
      expect(
        (w.id, w.maschineId, w.abteilung, w.prozessschritt),
        ('s-wolf', 'm-wolf', 'zerlegung', ''),
      );
      expect(
        [for (final x in w.werte) '${x.label}=${x.wert}${x.eigen ? '*' : ''}'],
        ['Lochscheibe (mm)=3', 'Hinweis=kalt wolfen*'],
      );

      // Die Anlage aus dem Feld „Anlage", der Titel wird der Schritt.
      expect(
        (b.maschineId, b.maschine, b.abteilung, b.prozessschritt),
        ('m-brat', 'Testbratstraße', 'bratstrasse', 'Garen und Braten'),
      );
      expect(
        [for (final x in b.werte) '${x.label}=${x.wert}${x.eigen ? '*' : ''}'],
        ['Bandgeschwindigkeit (m/min)=4', 'Temperaturen (°C)=180*'],
      );

      // Nicht im Katalog: Der Name bleibt, die Einstellungen werden Notiz.
      expect(
        (k.maschineId, k.maschine, k.abteilung, k.notiz),
        (null, 'Spiralfroster', '', '-30 °C, 40 min'),
      );
      expect(k.werte, isEmpty);

      // Ohne Anlage, aber so benannt wie eine Abteilung.
      expect(
        (v.maschine, v.abteilung, v.prozessschritt),
        ('', 'verpackung', 'Verpackung'),
      );
      expect(v.werte.single.eigen, isTrue);
    });

    test('dieselben Abschnitte geben dieselbe Kette — auch die Versionen', () {
      final a = prozessUmsetzen(frueher, katalog).prozess;
      final b = prozessUmsetzen(frueher.kopie(version: '1.0'), katalog);
      expect(gleicheParameter(a, b.prozess), isTrue);
      // Ohne Abschnitte bleibt alles, wie es ist.
      final r = prozessUmsetzen(a, katalog);
      expect((identical(r.prozess, a), r.schritte, r.entfallen), (true, 0, 0));
    });

    test('eine Anlage über ihren Namen finden', () {
      expect(anlageZu('TESTWOLF', katalog), wolf);
      expect(anlageZu('testbrat', katalog), brat);
      // Mehrdeutig oder leer: keine.
      expect(anlageZu('Test', katalog), isNull);
      expect(anlageZu(' ', katalog), isNull);
    });
  });

  group('Vergleich', () {
    test('Schritte über ihre IDs: Werte, Notiz, neu, weg, Reihenfolge', () {
      final alt = [
        schritt(
          'a',
          'zerlegung',
          maschine: 'Testwolf',
          werte: const [
            ProzessWert(name: 'Lochscheibe', wert: '3', einheit: 'mm'),
          ],
        ),
        schritt(
          'b',
          'bratstrasse',
          maschine: 'Testbratstraße',
          werte: const [
            ProzessWert(name: 'Bandgeschwindigkeit', wert: '4'),
            ProzessWert(name: 'Ölmenge', wert: '2'),
          ],
        ),
        schritt('c', 'verpackung', maschine: 'Testpacker'),
      ];
      final neu = [
        schritt(
          'b',
          'bratstrasse',
          maschine: 'Testbratstraße',
          werte: const [ProzessWert(name: 'Bandgeschwindigkeit', wert: '5')],
        ),
        alt.first.kopie(notiz: 'kalt wolfen'),
        schritt('d', 'bratstrasse', maschine: 'Testfroster'),
      ];
      final a = vergleicheParameter(
        Prozessparameter(schritte: alt),
        Prozessparameter(schritte: neu),
      );
      expect(
        [for (final x in a) '${x.abschnitt} · ${x.feld}: ${x.alt} → ${x.neu}'],
        [
          'Testbratstraße · Bandgeschwindigkeit: 4 → 5',
          'Testbratstraße · Ölmenge: 2 → null',
          'Testwolf · Maschineneinstellungen:  → kalt wolfen',
          'Testfroster · In der Kette: null → Schritt 3 · Bratstraße',
          'Testpacker · In der Kette: Schritt 3 · Verpackung → null',
          'Prozesskette · Reihenfolge: Testwolf → Testbratstraße → '
              'Testbratstraße → Testwolf',
        ],
      );
      expect(
        vergleicheParameter(
          Prozessparameter(schritte: neu),
          Prozessparameter(schritte: neu),
        ),
        isEmpty,
      );
    });

    test('frühere Abschnitte: geänderte, neue und entfallene Felder', () {
      ProzessFeld feld(String id, String wert) =>
          ProzessFeld(id: id, label: 'Feld $id', wert: wert);
      final alt = Prozessparameter(
        abschnitte: [
          ProzessAbschnitt(
            id: 'garen',
            titel: 'Garen',
            felder: [feld('t', '180'), feld('z', '12 min'), feld('weg', 'x')],
          ),
        ],
      );
      final neu = Prozessparameter(
        abschnitte: [
          ProzessAbschnitt(
            id: 'garen',
            titel: 'Garen',
            felder: [feld('t', '175'), feld('z', '12 min'), feld('neu', 'y')],
          ),
        ],
      );
      final a = vergleicheParameter(alt, neu);
      expect(a, hasLength(3));
      final temperatur = a.firstWhere((x) => x.feld == 'Feld t');
      expect((temperatur.alt, temperatur.neu), ('180', '175'));
      expect(a.firstWhere((x) => x.feld == 'Feld neu').alt, isNull);
      expect(a.firstWhere((x) => x.feld == 'Feld weg').neu, isNull);
    });
  });

  group('Versionen (F29)', () {
    test('Nummern zählen in Zehnteln weiter', () {
      expect(naechsteVersion('1.0'), '1.1');
      expect(naechsteVersion('1.9'), '2.0');
      expect(naechsteVersion('2,4'), '2.5');
      expect(naechsteVersion('0.9'), '1.0');
      expect(naechsteVersion(null), '1.0');
      expect(naechsteVersion('neu'), '1.0');
    });

    test('Arbeitsstand und festgehaltene Versionen', () {
      final v10 = Prozessparameter(
        schritte: [
          schritt(
            'b',
            'bratstrasse',
            maschine: 'Testbratstraße',
            werte: const [ProzessWert(name: 'Bandgeschwindigkeit', wert: '4')],
          ),
        ],
      );
      final geaendert = v10.kopie(
        schritte: [
          v10.schritte.single.kopie(
            werte: const [ProzessWert(name: 'Bandgeschwindigkeit', wert: '5')],
          ),
        ],
      );
      final am = DateTime(2026, 10, 1);
      final historie = [
        ProzessStand(version: '1.0', datum: am, parameter: v10),
      ];

      // Noch nichts festgehalten.
      var f = prozessFassung(v10, const []);
      expect((f.version, f.geaendert), (null, true));
      expect(f.text, 'Noch keine Version festgehalten');
      expect(naechsteProzessVersion(v10, const []), '1.0');
      expect(
        prozessFassung(const Prozessparameter(), const []).geaendert,
        isFalse,
      );

      // Festgehalten und unverändert — Nummer und Datum zählen dabei nicht.
      f = prozessFassung(v10.kopie(version: '1.0', stand: am), historie);
      expect(f.geaendert, isFalse);
      expect(f.text, 'Version 1.0 vom 01.10.2026');
      expect(gleicheParameter(v10, v10.kopie(version: '9.9')), isTrue);

      // Seitdem geändert: die nächste Nummer.
      f = prozessFassung(geaendert, historie);
      expect(f.text, 'Version 1.0 vom 01.10.2026, seitdem geändert');
      expect(naechsteProzessVersion(geaendert, historie), '1.1');
      expect(gleicheParameter(v10, geaendert), isFalse);

      // Eine Nummer aus der Suite ohne festgehaltene Versionen.
      final suite = geaendert.kopie(version: '2.3', stand: am);
      expect(
        prozessFassung(suite, const []).text,
        'Version 2.3 vom 01.10.2026',
      );
      expect(naechsteProzessVersion(suite, const []), '2.4');

      // Ein Stand mit neuen Parametern — etwa nach dem Umsetzen.
      final umgesetzt = historie.single.mitParameter(geaendert);
      expect((umgesetzt.version, umgesetzt.datum), ('1.0', am));
      expect(gleicheParameter(umgesetzt.parameter, geaendert), isTrue);
    });
  });

  group('Mit der Datenbank', () {
    late AppDatabase db;
    setUp(() => db = testDatenbank());
    tearDown(() => db.close());

    Future<void> feld(
      String id,
      String maschineId,
      String name, {
      String? einheit,
      int sortierung = 0,
    }) =>
        db.into(db.machineParameterDefs).insert(
              MachineParameterDefsCompanion.insert(
                id: id,
                maschineId: maschineId,
                parameterName: name,
                einheit: Value(einheit),
                sortierung: Value(sortierung),
              ),
            );

    Future<void> anlagen() async {
      await seedAnlage(
        db,
        id: 'm-wolf',
        name: 'Testwolf',
        abteilung: 'zerlegung',
      );
      await seedAnlage(
        db,
        id: 'm-brat',
        name: 'Testbratstraße',
        abteilung: 'bratstrasse',
      );
      await seedAnlage(
        db,
        id: 'm-weg',
        name: 'Altanlage',
        abteilung: 'zerlegung',
      );
      await (db.update(db.machines)..where((m) => m.id.equals('m-weg')))
          .write(MachinesCompanion(deletedAt: Value(DateTime(2026))));
      await feld(
        'd1',
        'm-brat',
        'Bandgeschwindigkeit',
        einheit: 'm/min',
        sortierung: 2,
      );
      await feld('d2', 'm-brat', 'Platte Oben 1', sortierung: 1);
      await feld('d3', 'm-brat', 'Ölmenge', einheit: 'l', sortierung: 1);
    }

    test('der Katalog: Anlagen mit Steckbrief, ohne Platten', () async {
      await anlagen();
      final k = await anlagenLaden(db);
      expect([for (final a in k) a.name], ['Testbratstraße', 'Testwolf']);
      expect(
        [for (final f in k.first.steckbrief) f.label],
        ['Ölmenge (l)', 'Bandgeschwindigkeit (m/min)'],
      );
      expect(k.last.steckbrief, isEmpty);
    });

    test('die Grenzen aus den Einstellungen', () async {
      await db.into(db.parameterGrenzen).insert(
            ParameterGrenzenCompanion.insert(
              id: 'g1',
              kontext: 'Testbratstraße',
              parameterName: 'Bandgeschwindigkeit',
              hartMax: const Value(8),
              weichMin: const Value(2),
            ),
          );
      await db.into(db.parameterGrenzen).insert(
            ParameterGrenzenCompanion.insert(
              id: 'g2',
              kontext: 'BRATSTRASSE',
              parameterName: 'Ölmenge',
              hartMax: const Value(3),
            ),
          );
      await (db.update(db.parameterGrenzen)..where((g) => g.id.equals('g2')))
          .write(ParameterGrenzenCompanion(deletedAt: Value(DateTime(2026))));
      final k = await grenzenLaden(db);
      final g = k.fuer(
        name: 'Bandgeschwindigkeit',
        maschine: 'Testbratstraße',
      )!;
      expect(
        (g.hartMin, g.hartMax, g.weichMin, g.weichMax),
        (null, 8, 2, null),
      );
      expect(k.fuer(name: 'Ölmenge', gruppe: 'BRATSTRASSE'), isNull);
    });

    test('Artikel mit Kette — und ihre Kette als Schritte', () async {
      await anlagen();
      await seedArtikel(db, id: 'p1', nummer: '1001', bezeichnung: 'Testware');
      await seedArtikel(db, id: 'p2', nummer: '1002');
      await seedSchritt(
        db,
        id: 'st2',
        productId: 'p1',
        reihenfolge: 2,
        abteilung: 'bratstrasse',
        maschineId: 'm-brat',
        prozessschritt: 'Braten',
      );
      await seedSchritt(
        db,
        id: 'st1',
        productId: 'p1',
        reihenfolge: 1,
        abteilung: 'zerlegung',
        prozessschritt: 'Abkühlen',
      );
      await seedSchritt(
        db,
        id: 'st3',
        productId: 'p1',
        reihenfolge: 3,
        abteilung: 'verpackung',
      );
      await (db.update(db.productSteps)..where((s) => s.id.equals('st3')))
          .write(ProductStepsCompanion(deletedAt: Value(DateTime(2026))));
      Future<void> parameter(
        String id,
        String gruppe,
        String name,
        String? wert, {
        bool eigen = false,
      }) =>
          db.into(db.productStepParameters).insert(
                ProductStepParametersCompanion.insert(
                  id: id,
                  stepId: 'st2',
                  parameterGruppe: gruppe,
                  parameterName: name,
                  wert: Value(wert),
                  istCustom: Value(eigen),
                ),
              );
      await parameter(
        'q1',
        kMaschinenNotizGruppe,
        kMaschinenNotizParam,
        'mittig',
      );
      await parameter('q2', 'BRATSTRASSE', 'Bandgeschwindigkeit', '3,5');
      await parameter('q3', 'CUSTOM', 'Garzeit', '8 min', eigen: true);

      final liste = await artikelMitKetteLaden(db);
      expect(
        [for (final a in liste) '${a.nummer} ${a.bezeichnung} ${a.schritte}'],
        ['1001 Testware 2'],
      );

      var n = 0;
      final kette = await ketteAusArtikel(
        db,
        'p1',
        katalog: await anlagenLaden(db),
        neueId: () => 'neu${++n}',
      );
      expect(ids(kette), ['neu1', 'neu2']);
      final [abkuehlen, braten] = kette;
      expect(
        (abkuehlen.abteilung, abkuehlen.maschineId, abkuehlen.name),
        ('zerlegung', null, 'Abkühlen'),
      );
      expect(
        (braten.maschine, braten.prozessschritt, braten.notiz),
        ('Testbratstraße', 'Braten', 'mittig'),
      );
      expect(
        [for (final w in braten.werte) '${w.label}=${w.wert}'],
        ['Bandgeschwindigkeit (m/min)=3,5', 'Garzeit=8 min'],
      );
      expect(
        await ketteAusArtikel(
          db,
          'p2',
          katalog: const [],
          neueId: () => 'x',
        ),
        isEmpty,
      );
    });
  });
}
