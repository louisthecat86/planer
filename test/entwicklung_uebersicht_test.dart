import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/constants/entwicklung.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/features/entwicklung/daten/entwicklung_repository.dart';
import 'package:produktion_planer/features/entwicklung/entwicklung_bereiche.dart';
import 'package:produktion_planer/features/entwicklung/kunden/kunden_modell.dart';
import 'package:produktion_planer/features/entwicklung/projekte/entwicklungsstrang.dart';
import 'package:produktion_planer/features/entwicklung/projekte/gesamtprojekt_modell.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_checkliste.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_modell.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_repository.dart';
import 'package:produktion_planer/features/entwicklung/uebersicht/angeheftet.dart';
import 'package:produktion_planer/features/entwicklung/uebersicht/uebersicht_modell.dart';

import 'helpers/test_db.dart';

/// Die Übersicht der Produktentwicklung ohne Oberfläche: wann sich an
/// einem Projekt zuletzt etwas getan hat, welche oben stehen, was ein
/// Projekt kurz über sich sagt, was ansteht, die Kacheln, die Suche, die
/// Kundenordner, die Bereiche der Leiste — und was dafür in der Datenbank
/// steht. Alles erfunden.
void main() {
  final heute = DateTime(2026, 11, 9);

  EntwicklungsProjekt projekt(
    String id,
    String name,
    DateTime geaendert, {
    String status = 'entwicklung',
    String? kunde,
    String? gesamtprojektId,
    String? artikelnummer,
  }) =>
      EntwicklungsProjekt(
        id: id,
        name: name,
        status: status,
        kunde: kunde,
        gesamtprojektId: gesamtprojektId,
        artikelnummer: artikelnummer,
        neuerProzess: false,
        neueZutaten: false,
        createdAt: geaendert,
        updatedAt: geaendert,
      );

  ProjektEintrag eintrag(
    String id,
    String projektId,
    DateTime datum, {
    String status = 'offen',
    String? ziel,
    String titel = 'Aufgabe',
  }) =>
      ProjektEintrag(
        id: id,
        projektId: projektId,
        art: EintragArt.notiz.schluessel,
        titel: titel,
        datum: datum,
        status: status,
        ziel: ziel,
        createdAt: datum,
        updatedAt: datum,
      );

  Rezeptur rezeptur(String id, String projektId, DateTime geaendert) =>
      Rezeptur(
        id: id,
        name: 'Rezeptur $id',
        projektId: projektId,
        createdAt: geaendert,
        updatedAt: geaendert,
      );

  RezepturVersion stand(
    String id,
    String rezepturId,
    int nummer,
    DateTime geaendert, {
    String status = VersionStatus.entwurf,
  }) =>
      RezepturVersion(
        id: id,
        rezepturId: rezepturId,
        nummer: nummer,
        status: status,
        verlustProzent: 0,
        fettVerlustProzent: 0,
        verlustArt: 'garen',
        createdAt: geaendert,
        updatedAt: geaendert,
      );

  Gesamtprojekt gesamt(String id, String name, {String? kunde}) =>
      Gesamtprojekt(
        id: id,
        name: name,
        kunde: kunde,
        createdAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 1),
      );

  List<String> ids(Iterable<EntwicklungsProjekt> liste) => [
        for (final p in liste) p.id,
      ];

  group('Zuletzt bearbeitet', () {
    test('die letzte Aktivität: Projekt, Verlauf, Rezeptur, Stand, Zeilen', () {
      final p = [
        projekt('a', 'A', DateTime(2026, 10, 1)),
        projekt('b', 'B', DateTime(2026, 9, 1)),
        projekt('c', 'C', DateTime(2026, 8, 1)),
        projekt('d', 'D', DateTime(2026, 7, 1)),
      ];
      final a = projektAktivitaet(
        projekte: p,
        eintraege: [
          eintrag('e1', 'b', DateTime(2026, 11, 2)),
          eintrag('e2', 'unbekannt', DateTime(2026, 11, 8)),
        ],
        rezepturen: [rezeptur('r1', 'c', DateTime(2026, 8, 1))],
        versionen: [stand('v1', 'r1', 1, DateTime(2026, 11, 5))],
        zeilen: {
          'd': DateTime(2026, 11, 7),
          'unbekannt': DateTime(2026, 11, 9),
        },
      );
      expect(a, {
        'a': DateTime(2026, 10, 1),
        'b': DateTime(2026, 11, 2),
        'c': DateTime(2026, 11, 5),
        'd': DateTime(2026, 11, 7),
      });
    });

    test('angeheftete zuerst, dann die in Arbeit — bis es fünf sind', () {
      final p = [
        for (var i = 1; i <= 7; i++)
          projekt('p$i', 'Projekt $i', DateTime(2026, 10, i)),
        projekt(
          'prod',
          'In Produktion',
          DateTime(2026, 11, 8),
          status: 'produktion',
        ),
        projekt('ruht', 'Ruht', DateTime(2026, 11, 7), status: 'eingestellt'),
      ];
      final a = projektAktivitaet(projekte: p);
      // Ohne Anheften: die fünf zuletzt bewegten in Arbeit.
      expect(
        ids(zuletztBearbeitet(projekte: p, aktivitaet: a)),
        ['p7', 'p6', 'p5', 'p4', 'p3'],
      );
      // Angeheftet — auch ein ruhendes — steht oben, der Rest füllt auf.
      expect(
        ids(
          zuletztBearbeitet(
            projekte: p,
            aktivitaet: a,
            angeheftet: ['p1', 'ruht'],
          ),
        ),
        ['ruht', 'p1', 'p7', 'p6', 'p5'],
      );
      // Mehr angeheftete als Plätze: alle angehefteten.
      expect(
        zuletztBearbeitet(
          projekte: p,
          aktivitaet: a,
          angeheftet: [for (var i = 1; i <= 7; i++) 'p$i'],
        ),
        hasLength(7),
      );
      // Ein unbekanntes angeheftetes fehlt einfach.
      expect(
        ids(
          zuletztBearbeitet(
            projekte: p,
            aktivitaet: a,
            angeheftet: ['weg'],
            anzahl: 2,
          ),
        ),
        ['p7', 'p6'],
      );
    });
  });

  group('Was ein Projekt kurz über sich sagt', () {
    test('überfällig, ruht, als Nächstes, bald fällig, ein Entwurf', () {
      final h = projektHinweise(
        projekt: projekt('a', 'A', DateTime(2026, 9, 1)),
        zuletzt: DateTime(2026, 9, 1),
        heute: heute,
        checkliste: ProjektCheckStand([
          CheckStand(punkt: kProjektCheckliste.first, erledigt: false),
        ]),
        eintraege: [
          eintrag(
            'e1',
            'a',
            DateTime(2026, 10, 20),
            ziel: 'KW 44',
            titel: 'Verkostung',
          ),
          eintrag(
            'e2',
            'a',
            DateTime(2026, 11, 1),
            ziel: '30.11.2026',
            titel: 'Muster an Kunden',
          ),
          eintrag(
            'e3',
            'a',
            DateTime(2026, 11, 1),
            ziel: '12.11.',
            titel: 'Laborbefund',
          ),
          eintrag(
            'e4',
            'a',
            DateTime(2026, 10, 1),
            ziel: '01.10.2026',
            titel: 'Längst erledigt',
            status: 'erledigt',
          ),
        ],
        entwuerfe: [
          stand('v2', 'r1', 2, DateTime(2026, 9, 1)),
          stand('v3', 'r1', 3, DateTime(2026, 9, 1)),
          stand(
            'v1',
            'r1',
            1,
            DateTime(2026, 8, 1),
            status: VersionStatus.abgeschlossen,
          ),
        ],
      );
      expect(
        [for (final x in h) x.text],
        [
          'Überfällig seit 01.11.: Verkostung',
          'Seit 69 Tagen nichts getan',
          'Als Nächstes: Rezeptur erstellen',
          'Fällig Do 12.11.: Laborbefund',
          'Stand 3 in Arbeit',
        ],
      );
      expect(
        [for (final x in h) x.art],
        [
          HinweisArt.ueberfaellig,
          HinweisArt.ruht,
          HinweisArt.naechster,
          HinweisArt.faellig,
          HinweisArt.entwurf,
        ],
      );
    });

    test('mehrere überfällig; ein ruhendes schweigt; alles erledigt', () {
      final h = projektHinweise(
        projekt: projekt('a', 'A', heute),
        zuletzt: heute,
        heute: heute,
        eintraege: [
          eintrag('e1', 'a', DateTime(2026, 10, 1), ziel: '05.10.', titel: 'X'),
          eintrag('e2', 'a', DateTime(2026, 10, 1), ziel: '02.10.', titel: 'Y'),
        ],
      );
      expect(h.single.text, '2 Einträge überfällig, zuerst: Y');

      expect(
        projektHinweise(
          projekt: projekt('b', 'B', heute, status: 'archiviert'),
          zuletzt: DateTime(2026, 1, 1),
          heute: heute,
          eintraege: [
            eintrag('e3', 'b', DateTime(2026, 1, 1), ziel: '02.01.2026'),
          ],
        ),
        isEmpty,
      );

      expect(
        projektHinweise(
          projekt: projekt('c', 'C', heute, status: 'produktion'),
          zuletzt: heute,
          heute: heute,
          checkliste: ProjektCheckStand([
            CheckStand(punkt: kProjektCheckliste.first, erledigt: true),
          ]),
        ),
        [(text: 'Checkliste erledigt', art: HinweisArt.erledigt)],
      );
    });
  });

  group('Was ansteht', () {
    test('überfällig zuerst, dann die nächsten zwei Wochen', () {
      final f = faelligeEintraege(
        eintraege: [
          eintrag(
            'e1',
            'a',
            DateTime(2026, 11, 1),
            ziel: '20.11.',
            titel: 'Muster',
          ),
          eintrag(
            'e2',
            'g',
            DateTime(2026, 10, 1),
            ziel: '15.10.',
            titel: 'Angebot',
          ),
          eintrag(
            'e3',
            'a',
            DateTime(2026, 11, 1),
            ziel: '30.12.',
            titel: 'Zu weit',
          ),
          eintrag(
            'e4',
            'alt',
            DateTime(2026, 10, 1),
            ziel: '02.10.',
            titel: 'Ruht',
          ),
          eintrag(
            'e5',
            'a',
            DateTime(2026, 11, 1),
            ziel: 'nach der Verkostung',
            titel: 'Ohne Tag',
          ),
          eintrag(
            'e6',
            'a',
            DateTime(2026, 11, 1),
            ziel: '10.11.',
            titel: 'Erledigt',
            status: 'erledigt',
          ),
        ],
        projekte: [
          projekt('a', 'Grillwurst', heute),
          projekt('alt', 'Alt', heute, status: 'eingestellt'),
        ],
        gesamtprojekte: [gesamt('g', 'Anfrage Sommer')],
        heute: heute,
      );
      expect(
        [
          for (final x in f)
            (x.eintrag.titel, x.zielName, x.ueberfaellig, x.gesamtprojekt),
        ],
        [
          ('Angebot', 'Anfrage Sommer', true, true),
          ('Muster', 'Grillwurst', false, false),
        ],
      );
    });

    test('ruhende Projekte: in Arbeit und seit 30 Tagen nichts getan', () {
      final r = ruhendeProjekte(
        projekte: [
          projekt('a', 'A', DateTime(2026, 10, 10)),
          projekt('b', 'B', DateTime(2026, 8, 1)),
          projekt('c', 'C', DateTime(2026, 9, 1), status: 'produktion'),
          projekt('d', 'D', DateTime(2026, 9, 20)),
        ],
        aktivitaet: {'d': DateTime(2026, 11, 1)},
        heute: heute,
      );
      expect(
        [for (final x in r) (x.projekt.id, x.tage)],
        [('b', 100), ('a', 30)],
      );
      // Über die Umstellung auf Sommerzeit hinweg zählen ganze Tage.
      expect(
        ruhendeProjekte(
          projekte: [projekt('s', 'S', DateTime(2026, 3, 1))],
          aktivitaet: const {},
          heute: DateTime(2026, 3, 31),
        ).single.tage,
        30,
      );
    });

    test('die Kacheln — gelistet gezählt wie in der Statistik', () {
      final p = [
        projekt('a', 'A', DateTime(2026, 11, 1)),
        projekt('b', 'B', DateTime(2026, 11, 1), status: 'validierung'),
        projekt('c', 'C', DateTime(2026, 8, 1)),
        projekt('d', 'D', DateTime(2026, 3, 1), status: 'produktion'),
        projekt('e', 'E', DateTime(2025, 3, 1), status: 'eingestellt'),
      ];
      final e = [
        eintrag('e1', 'a', DateTime(2026, 10, 1), ziel: '15.10.'),
        eintrag('e2', 'b', DateTime(2026, 11, 1)),
        // Im ruhenden Projekt zählt nichts mehr.
        eintrag('e3', 'e', DateTime(2025, 3, 1), ziel: '02.03.2025'),
        ProjektEintrag(
          id: 'w',
          projektId: 'd',
          art: EintragArt.meilenstein.schluessel,
          titel: statusMeilensteinTitel(ProjektStatus.produktion),
          datum: DateTime(2026, 3, 20),
          status: EintragStatus.erledigt.schluessel,
          wert: statusWert(ProjektStatus.entwicklung, ProjektStatus.produktion),
          createdAt: DateTime(2026, 3, 20),
          updatedAt: DateTime(2026, 3, 20),
        ),
      ];
      final z = uebersichtZahlen(
        projekte: p,
        gesamtprojekte: const [],
        eintraege: e,
        aktivitaet: projektAktivitaet(projekte: p, eintraege: e),
        heute: heute,
      );
      expect(
        (
          z.inArbeit,
          z.inValidierung,
          z.ueberfaellig,
          z.offen,
          z.ruhend,
          z.gelistet,
          z.jahr,
        ),
        (3, 1, 1, 2, 1, 1, 2026),
      );
    });
  });

  test('Zeiten in Worten', () {
    expect(vorWieLange(DateTime(2026, 11, 9, 7), heute), 'heute');
    expect(vorWieLange(DateTime(2026, 11, 8, 23), heute), 'gestern');
    expect(vorWieLange(DateTime(2026, 11, 1), heute), 'vor 8 Tagen');
    expect(vorWieLange(DateTime(2026, 10, 1), heute), '01.10.2026');
    expect(faelligText(DateTime(2026, 11, 9), heute), 'heute');
    expect(faelligText(DateTime(2026, 11, 10), heute), 'morgen');
    expect(faelligText(DateTime(2026, 11, 12), heute), 'Do 12.11.');
  });

  test('die Suche: Projekte, Gesamtprojekte und Rezepturen', () {
    final p = [
      projekt(
        'a',
        'Grillwurst fein',
        DateTime(2026, 11, 1),
        kunde: 'Beispiel Feinkost',
      ),
      projekt(
        'b',
        'Kochschinken',
        DateTime(2026, 11, 2),
        artikelnummer: '4711',
      ),
    ];
    final g = [gesamt('g', 'Grillsortiment')];
    final r = [
      Rezeptur(
        id: 'r',
        name: 'Grillbrät',
        artikelnummer: '815',
        createdAt: heute,
        updatedAt: heute,
      ),
    ];
    final t = uebersichtSuchen(
      'grill',
      projekte: p,
      gesamtprojekte: g,
      rezepturen: r,
    );
    expect(ids(t.projekte), ['a']);
    expect([for (final x in t.gesamtprojekte) x.id], ['g']);
    expect([for (final x in t.rezepturen) x.id], ['r']);
    expect(ids(uebersichtSuchen('4711', projekte: p).projekte), ['b']);
    expect(ids(uebersichtSuchen('FEINKOST', projekte: p).projekte), ['a']);
    expect(uebersichtSuchen('815', projekte: p, rezepturen: r).rezepturen, r);
    expect(uebersichtSuchen('  ', projekte: p).projekte, isEmpty);
  });

  test('Kundenordner: je Kunde einer, in Arbeit zuerst, ohne Kunden zuletzt',
      () {
    final g = [gesamt('g', 'Anfrage Grill', kunde: 'Beispiel Feinkost')];
    final p = [
      projekt(
        'm1',
        'Muster 1',
        DateTime(2026, 9, 2),
        kunde: 'Beispiel Feinkost',
        gesamtprojektId: 'g',
        status: 'eingestellt',
      ),
      projekt(
        'm2',
        'Muster 2',
        DateTime(2026, 9, 3),
        kunde: 'Beispiel Feinkost',
        gesamtprojektId: 'g',
        status: 'produktion',
      ),
      projekt(
        'a',
        'Bratwurst',
        DateTime(2026, 10, 1),
        kunde: 'beispiel feinkost ',
      ),
      projekt(
        'b',
        'Salami',
        DateTime(2026, 11, 1),
        kunde: 'Beispiel Feinkost',
        status: 'archiviert',
      ),
      projekt('c', 'Kochschinken', DateTime(2026, 8, 1), kunde: 'Muster Markt'),
      projekt('d', 'Leberkäse', DateTime(2026, 7, 1)),
    ];
    final o = kundenOrdner(projekte: p, gesamtprojekte: g);
    expect(
      [for (final x in o) x.name],
      ['Beispiel Feinkost', 'Muster Markt', null],
    );
    expect(o.last.id, '');

    final feinkost = o.first;
    String punkt(ListenPunkt x) => switch (x) {
          EinzelProjekt(:final projekt) => projekt.id,
          GesamtGruppe(:final gesamtprojekt) => gesamtprojekt.id,
        };
    // In Arbeit zuerst, dann das Gesamtprojekt mit seinem gelisteten
    // Muster, zuletzt das ruhende.
    expect([for (final x in feinkost.punkte) punkt(x)], ['a', 'g', 'b']);
    expect(feinkost.projekte, hasLength(4));
    expect(feinkost.inArbeit, 1);
    expect(feinkost.gelistet, 1);
    expect(
      feinkost.zusammenfassung,
      '1 in Arbeit · 4 Projekte · 1 Gesamtprojekt · 1 gelistet',
    );
    expect(feinkost.zuletzt, DateTime(2026, 11, 1));
    expect(o[1].zusammenfassung, '1 in Arbeit · 1 Projekt');

    // Mit Aktivität ordnet die jüngste — auch ruhend bleibt hinten.
    final mitAktivitaet = kundenOrdner(
      projekte: p,
      gesamtprojekte: g,
      aktivitaet: {'m2': DateTime(2026, 11, 8)},
    );
    expect(mitAktivitaet.first.zuletzt, DateTime(2026, 11, 8));

    // Die Suche: nur, was trifft — beim Gesamtprojekt nur die Muster.
    final s = kundenOrdner(projekte: p, gesamtprojekte: g, suche: 'muster 2');
    final gruppe = s.single.punkte.single as GesamtGruppe;
    expect(ids(gruppe.muster), ['m2']);
    final markt = kundenOrdner(projekte: p, gesamtprojekte: g, suche: 'markt');
    expect([for (final x in markt) x.name], ['Muster Markt']);
  });

  test('die Bereiche der Leiste: Unterseiten gehören zu ihrem Bereich', () {
    expect(EntwicklungsBereich.uebersicht.passt('/entwicklung'), isTrue);
    expect(
      EntwicklungsBereich.uebersicht.passt('/entwicklung/projekte'),
      isFalse,
    );
    for (final (bereich, ort) in const [
      (EntwicklungsBereich.projekte, '/entwicklung/projekte'),
      (EntwicklungsBereich.projekte, '/entwicklung/projekt/p1'),
      (EntwicklungsBereich.projekte, '/entwicklung/gesamtprojekt/g1'),
      (EntwicklungsBereich.kunden, '/entwicklung/kunden'),
      (EntwicklungsBereich.rezepturen, '/entwicklung/rezeptur/r1'),
      (EntwicklungsBereich.werkzeuge, '/entwicklung/rueckrechnung'),
      (EntwicklungsBereich.statistik, '/entwicklung/statistik'),
    ]) {
      expect(
        [
          for (final b in EntwicklungsBereich.values)
            if (b.passt(ort)) b,
        ],
        [bereich],
        reason: ort,
      );
    }
    expect(
      EntwicklungsBereich.projekte.passt('/entwicklung/projektexyz'),
      isFalse,
    );
    expect(istEntwicklungsOrt('/entwicklung'), isTrue);
    expect(istEntwicklungsOrt('/entwicklung/kunden'), isTrue);
    expect(istEntwicklungsOrt('/entwicklungen'), isFalse);
    expect(istEntwicklungsOrt('/home'), isFalse);
    final n = EntwicklungsBereich.values.length;
    expect({for (final b in EntwicklungsBereich.values) b.pfad}, hasLength(n));
    expect({for (final b in EntwicklungsBereich.values) b.route}, hasLength(n));
  });

  group('mit Datenbank', () {
    late AppDatabase db;
    setUp(() => db = testDatenbank());
    tearDown(() => db.close());

    test('Angeheftetes bleibt gemerkt — nur auf diesem Rechner', () async {
      final n = AngeheftetNotifier(db);
      await n.umschalten('p1');
      await n.umschalten('p2');
      await n.umschalten('p1');
      expect(n.state, ['p2']);

      final wieder = AngeheftetNotifier(db);
      for (var i = 0; i < 50 && wieder.state.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(wieder.state, ['p2']);
      expect(kEntwicklungNurLokal, contains(kEntwicklungAngeheftet));
      expect(AngeheftetNotifier.idsAus('kaputt'), isEmpty);
      expect(AngeheftetNotifier.idsAus('["a", 3, ""]'), ['a']);
      n.dispose();
      wieder.dispose();
    });

    test('die letzte Änderung an Rezepturzeilen je Projekt', () async {
      final projekte = ProjektRepository(db);
      final rezepte = EntwicklungRepository(db);
      final id = await projekte.projektAnlegen(name: 'Bratwurst');
      final r = await rezepte.rezepturAnlegen(name: 'Bratwurst', projektId: id);
      final ohne = await rezepte.rezepturAnlegen(name: 'Ohne Projekt');
      final salz = await rezepte.zutatAnlegen(
        const EntwicklungZutatenCompanion(name: Value('Salz')),
      );
      expect(await rezepte.zeilenAenderungenBeobachten().first, isEmpty);

      final v = (await rezepte.neuesteVersion(r))!;
      await rezepte.positionHinzufuegen(v.id, zutatId: salz, mengeKg: 2);
      final w = (await rezepte.neuesteVersion(ohne))!;
      await rezepte.positionHinzufuegen(w.id, zutatId: salz, mengeKg: 1);
      final aenderungen = await rezepte.zeilenAenderungenBeobachten().first;
      expect(aenderungen.keys, [id]);
      expect(
        DateTime.now().difference(aenderungen[id]!).inMinutes.abs(),
        lessThan(5),
      );
    });
  });
}
