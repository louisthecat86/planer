import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/features/entwicklung/projekte/entwicklungsstrang.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_modell.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_repository.dart';
import 'package:produktion_planer/features/entwicklung/statistik/entwicklung_auswertung.dart';

import 'helpers/test_db.dart';

/// Die Produktentwicklung über einen Zeitraum: Muster, Listungen, was
/// nicht weiter verfolgt wurde, Durchlaufzeiten, Kunden und Gründe — mit
/// dem Vorjahr zum Vergleich. Alles erfunden.
void main() {
  group('Zeitraum', () {
    test('Jahr, Quartal, Monat und frei — mit Namen', () {
      final jahr = Zeitraum.jahr(2026);
      expect(jahr.von, DateTime(2026));
      expect(jahr.bis, DateTime(2026, 12, 31));
      expect(jahr.tage, 365);
      expect(jahr.name, '2026');
      expect(jahr.enthaelt(DateTime(2026, 12, 31, 23, 59)), isTrue);
      expect(jahr.enthaelt(DateTime(2027)), isFalse);

      final q = Zeitraum.quartal(2026, 3);
      expect(q.von, DateTime(2026, 7));
      expect(q.bis, DateTime(2026, 9, 30));
      expect(q.name, '3. Quartal 2026');
      expect(q.kurz, 'Q3 2026');

      final m = Zeitraum.monat(2026, 2);
      expect(m.bis, DateTime(2026, 2, 28));
      expect(m.name, 'Februar 2026');
      expect(m.kurz, 'Feb 2026');

      // Frei: vertauscht wird richtig herum.
      final f = Zeitraum.frei(DateTime(2026, 9, 15), DateTime(2026, 3, 1));
      expect(f.von, DateTime(2026, 3));
      expect(f.bis, DateTime(2026, 9, 15));
      expect(f.name, '01.03.2026 – 15.09.2026');
      expect(f.kurz, '01.03.26–15.09.26');
    });

    test('davor, danach und das Vorjahr — über den Jahreswechsel', () {
      expect(Zeitraum.quartal(2026, 1).davor, Zeitraum.quartal(2025, 4));
      expect(Zeitraum.quartal(2026, 4).danach, Zeitraum.quartal(2027, 1));
      expect(Zeitraum.monat(2026, 1).davor, Zeitraum.monat(2025, 12));
      expect(Zeitraum.monat(2026, 12).danach, Zeitraum.monat(2027, 1));
      expect(Zeitraum.jahr(2026).vorjahr, Zeitraum.jahr(2025));
      expect(Zeitraum.quartal(2026, 2).vorjahr, Zeitraum.quartal(2025, 2));

      // Frei um die eigene Länge — zehn Tage.
      final f = Zeitraum.frei(DateTime(2026, 3, 11), DateTime(2026, 3, 20));
      expect(f.tage, 10);
      expect(f.davor, Zeitraum.frei(DateTime(2026, 3), DateTime(2026, 3, 10)));
      expect(
        f.danach,
        Zeitraum.frei(DateTime(2026, 3, 21), DateTime(2026, 3, 30)),
      );
      expect(
        f.vorjahr,
        Zeitraum.frei(DateTime(2025, 3, 11), DateTime(2025, 3, 20)),
      );
    });

    test('der Zeitraum um einen Tag', () {
      final tag = DateTime(2026, 11, 9);
      expect(Zeitraum.um(ZeitraumArt.jahr, tag), Zeitraum.jahr(2026));
      expect(Zeitraum.um(ZeitraumArt.quartal, tag), Zeitraum.quartal(2026, 4));
      expect(Zeitraum.um(ZeitraumArt.monat, tag), Zeitraum.monat(2026, 11));
      // Frei: die zwölf Monate bis heute.
      expect(
        Zeitraum.um(ZeitraumArt.frei, tag),
        Zeitraum.frei(DateTime(2025, 11, 10), tag),
      );
    });

    test('Tage über die Umstellung auf Sommerzeit', () {
      expect(tageZwischen(DateTime(2026, 3, 28), DateTime(2026, 3, 30)), 2);
      expect(Zeitraum.monat(2026, 3).tage, 31);
      expect(Zeitraum.monat(2026, 10).tage, 31);
    });

    test('Abschnitte: Monate, Quartale oder Jahre — der Rand angeschnitten',
        () {
      final jahr = Zeitraum.jahr(2026).abschnitte;
      expect(jahr, hasLength(12));
      expect(jahr.first.label, 'Jan');
      expect(jahr.first.name, 'Januar 2026');
      expect(jahr.last.label, 'Dez');

      final frei = Zeitraum.frei(DateTime(2025, 11, 10), DateTime(2026, 11, 9))
          .abschnitte;
      expect(frei, hasLength(13));
      expect(frei.first.von, DateTime(2025, 11, 10));
      expect(frei.first.bisExkl, DateTime(2025, 12));
      expect(frei.last.von, DateTime(2026, 11));
      expect(frei.last.bisExkl, DateTime(2026, 11, 10));

      final drei =
          Zeitraum.frei(DateTime(2024, 2), DateTime(2026, 12, 31)).abschnitte;
      expect(drei.first.label, 'Q1 24');
      expect(drei.first.von, DateTime(2024, 2));
      expect(drei, hasLength(12));

      final lang =
          Zeitraum.frei(DateTime(2015), DateTime(2026, 12, 31)).abschnitte;
      expect([for (final a in lang) a.label].take(2), ['2015', '2016']);
      expect(lang, hasLength(12));
    });
  });

  group('Auswertung', () {
    final heute = DateTime(2026, 11, 9);

    EntwicklungsProjekt projekt(
      String id,
      DateTime angelegt, {
      String status = 'entwicklung',
      String? kunde,
      String? gesamtprojektId,
      DateTime? freigegebenAm,
      bool neuerProzess = false,
    }) =>
        EntwicklungsProjekt(
          id: id,
          name: 'Test $id',
          status: status,
          kunde: kunde,
          gesamtprojektId: gesamtprojektId,
          freigegebenAm: freigegebenAm,
          neuerProzess: neuerProzess,
          neueZutaten: false,
          createdAt: angelegt,
          updatedAt: angelegt,
        );

    var nr = 0;
    ProjektEintrag wechsel(
      String projektId,
      DateTime datum,
      ProjektStatus alt,
      ProjektStatus neu, {
      String? grund,
    }) =>
        ProjektEintrag(
          id: 'e${nr++}',
          projektId: projektId,
          art: EintragArt.meilenstein.schluessel,
          titel: statusMeilensteinTitel(neu),
          datum: datum,
          beschreibung: [
            if (grund != null) 'Grund: $grund',
            'Status vorher: ${alt.label}',
          ].join('\n'),
          status: EintragStatus.erledigt.schluessel,
          wert: statusWert(alt, neu),
          createdAt: datum,
          updatedAt: datum,
        );

    ProjektEintrag freigabe(String projektId, DateTime datum) => ProjektEintrag(
          id: 'e${nr++}',
          projektId: projektId,
          art: EintragArt.meilenstein.schluessel,
          titel: 'Freigegeben als neuer Artikel 90001',
          datum: datum,
          status: EintragStatus.erledigt.schluessel,
          createdAt: datum,
          updatedAt: datum,
        );

    RezepturVersion stand(
      String id,
      DateTime angelegt, {
      DateTime? abgeschlossenAm,
    }) =>
        RezepturVersion(
          id: id,
          rezepturId: 'r1',
          nummer: 1,
          status: abgeschlossenAm == null ? 'entwurf' : 'abgeschlossen',
          verlustProzent: 0,
          fettVerlustProzent: 0,
          verlustArt: 'garen',
          abgeschlossenAm: abgeschlossenAm,
          createdAt: angelegt,
          updatedAt: angelegt,
        );

    const eingestellt = ProjektStatus.eingestellt;
    final projekte = [
      // Zwei Muster einer Anfrage: A gelistet, B nicht weiter verfolgt.
      projekt(
        'p1',
        DateTime(2026, 1, 15, 9),
        status: 'produktion',
        kunde: 'Beispiel Feinkost',
        gesamtprojektId: 'g1',
        freigegebenAm: DateTime(2026, 3, 20, 14),
      ),
      projekt(
        'p2',
        DateTime(2026, 1, 15, 9),
        status: 'eingestellt',
        kunde: 'Beispiel Feinkost',
        gesamtprojektId: 'g1',
      ),
      projekt(
        'p3',
        DateTime(2026, 6, 1),
        kunde: 'Muster Markt',
        neuerProzess: true,
      ),
      // Aus dem Vorjahr, in diesem Jahr gelistet.
      projekt(
        'p4',
        DateTime(2025, 5, 10),
        status: 'produktion',
        kunde: 'Beispiel Feinkost',
      ),
      // Nicht weiter verfolgt, dann archiviert — ohne Kunden.
      projekt('p5', DateTime(2025, 3, 1), status: 'archiviert'),
      // Aus der Suite: in Produktion, ohne Wechsel im Verlauf.
      projekt(
        'p6',
        DateTime(2025, 2, 1),
        status: 'produktion',
        kunde: 'muster markt',
      ),
      // Nicht weiter verfolgt — und wieder aufgenommen.
      projekt('p7', DateTime(2026, 9, 1), kunde: 'Muster Markt'),
    ];
    final eintraege = [
      wechsel(
        'p1',
        DateTime(2026, 2, 10),
        ProjektStatus.entwicklung,
        ProjektStatus.validierung,
      ),
      wechsel(
        'p1',
        DateTime(2026, 3, 20),
        ProjektStatus.validierung,
        ProjektStatus.produktion,
      ),
      freigabe('p1', DateTime(2026, 3, 20)),
      wechsel(
        'p2',
        DateTime(2026, 3, 20),
        ProjektStatus.entwicklung,
        eingestellt,
        grund: 'Kunde hat Muster A gewählt',
      ),
      wechsel(
        'p4',
        DateTime(2025, 9, 1),
        ProjektStatus.entwicklung,
        ProjektStatus.validierung,
      ),
      wechsel(
        'p4',
        DateTime(2026, 2, 1),
        ProjektStatus.validierung,
        ProjektStatus.produktion,
      ),
      wechsel(
        'p5',
        DateTime(2025, 4, 1),
        ProjektStatus.entwicklung,
        eingestellt,
        grund: 'Zu teuer',
      ),
      wechsel(
        'p5',
        DateTime(2025, 6, 1),
        eingestellt,
        ProjektStatus.archiviert,
      ),
      wechsel(
        'p7',
        DateTime(2026, 10, 1),
        ProjektStatus.entwicklung,
        eingestellt,
      ),
      wechsel(
        'p7',
        DateTime(2026, 10, 15),
        eingestellt,
        ProjektStatus.entwicklung,
      ),
      // Ein Eintrag zu einem gelöschten Projekt zählt nicht.
      wechsel(
        'weg',
        DateTime(2026, 5, 1),
        ProjektStatus.entwicklung,
        ProjektStatus.produktion,
      ),
    ];
    final gesamtprojekte = [
      Gesamtprojekt(
        id: 'g1',
        name: 'Anfrage Grillsortiment',
        kunde: 'Beispiel Feinkost',
        createdAt: DateTime(2026, 1, 15, 9),
        updatedAt: DateTime(2026, 1, 15, 9),
      ),
      Gesamtprojekt(
        id: 'g2',
        name: 'Anfrage Aufschnitt',
        kunde: 'Muster Markt',
        createdAt: DateTime(2025, 11, 2),
        updatedAt: DateTime(2025, 11, 2),
      ),
    ];
    final rezepturen = [
      Rezeptur(
        id: 'r1',
        name: 'Testwurst',
        projektId: 'p1',
        createdAt: DateTime(2026, 1, 20),
        updatedAt: DateTime(2026, 1, 20),
      ),
    ];
    final versionen = [
      stand('v1', DateTime(2026, 1, 20)),
      stand(
        'v2',
        DateTime(2026, 2, 5),
        abgeschlossenAm: DateTime(2026, 2, 5, 16),
      ),
      stand('v3', DateTime(2026, 4, 1)),
    ];
    final laeufe = musterLaeufe(
      projekte: projekte,
      gesamtprojekte: gesamtprojekte,
      eintraege: eintraege,
      rezepturen: rezepturen,
      versionen: versionen,
    );
    MusterLauf lauf(String id) => laeufe.singleWhere((l) => l.id == id);

    EntwicklungsAuswertung auswerten(Zeitraum z, {String? kunde}) =>
        entwicklungAuswerten(
          laeufe: laeufe,
          zeitraum: z,
          heute: heute,
          gesamtprojekte: gesamtprojekte,
          rezepturen: rezepturen,
          versionen: versionen,
          kunde: kunde,
        );

    test('ein Muster im Lauf der Zeit: Phase, Listung und Stände', () {
      final p4 = lauf('p4');
      expect(p4.statusAm(DateTime(2025, 5, 9)), isNull);
      expect(p4.statusAm(DateTime(2025, 12, 31)), ProjektStatus.validierung);
      // Am Tag des Wechsels gilt schon die neue Phase.
      expect(p4.statusAm(DateTime(2026, 2, 1)), ProjektStatus.produktion);
      expect(p4.gelistetAm, DateTime(2026, 2, 1));
      expect(p4.tageBisListung, 267);

      final p1 = lauf('p1');
      expect(p1.gesamtprojekt, 'Anfrage Grillsortiment');
      expect(p1.gelistetAm, DateTime(2026, 3, 20));
      expect(p1.tageBisListung, 64);
      expect(p1.neuerArtikel, isTrue);
      // Nur die Stände bis zur Listung.
      expect(p1.staende, hasLength(3));
      expect(p1.staendeBisListung, 2);

      // Aus der Suite: gelistet, aber ohne Tag.
      final p6 = lauf('p6');
      expect(p6.gelistetAm, isNull);
      expect(p6.ergebnisAm(heute), MusterErgebnis.gelistet);
      expect(p6.statusAm(DateTime(2025, 6, 1)), ProjektStatus.produktion);

      // Nicht weiter verfolgt, dann archiviert: nicht weiter verfolgt.
      expect(lauf('p5').ergebnisAm(heute), MusterErgebnis.nichtWeiter);
      expect(lauf('p5').eingestellt.single.grund, 'Zu teuer');

      // Wieder aufgenommen: dazwischen nicht weiter verfolgt.
      final p7 = lauf('p7');
      expect(p7.ergebnisAm(DateTime(2026, 10, 5)), MusterErgebnis.nichtWeiter);
      expect(p7.ergebnisAm(heute), MusterErgebnis.offen);

      expect(laeufe.map((l) => l.id), isNot(contains('weg')));
    });

    test('das Jahr: Muster, Anfragen, Listungen, Durchlaufzeit', () {
      final a = auswerten(Zeitraum.jahr(2026));
      final z = a.zahlen;
      expect(z.neueMuster, 4);
      expect(z.neueMusterImGesamtprojekt, 2);
      expect(z.neueAnfragen, 1);
      // Gelistet in 2026: p1 und p4 (aus dem Vorjahr).
      expect(z.gelistet, 2);
      expect([for (final l in a.gelistet) l.id], ['p4', 'p1']);
      expect(z.freigegeben, 1);
      expect(z.neueArtikel, 1);
      // p7 wird wieder verfolgt — es zählt nicht.
      expect(z.nichtWeiter, 1);
      expect([for (final l in a.nichtWeiter) l.id], ['p2']);
      expect(z.tageBisListung, (64 + 267) / 2);
      expect(z.tageBisListungMedian, (64 + 267) / 2);
      expect(z.staendeBisListung, 1);
      // Das Jahr läuft noch: in Arbeit heute — p3 und p7.
      expect(a.laeuftNoch, isTrue);
      expect(a.stichtag, heute);
      expect(z.inArbeitAmEnde, 2);
      expect(z.neueProzesse, 1);
      expect(z.staendeAngelegt, 3);
      expect(z.staendeAbgeschlossen, 1);

      // Was aus den neuen Mustern wurde.
      expect(z.kohorte[MusterErgebnis.gelistet], 1);
      expect(z.kohorte[MusterErgebnis.nichtWeiter], 1);
      expect(z.kohorte[MusterErgebnis.offen], 2);
      expect(z.listungsquote, .25);
      expect(z.trefferquote, .5);
      expect([for (final l in a.neu) l.id], ['p1', 'p2', 'p3', 'p7']);
    });

    test('das Vorjahr zum Vergleich — „in Arbeit" an seinem Ende', () {
      final v = auswerten(Zeitraum.jahr(2026)).vorjahr;
      expect(v.neueMuster, 3);
      expect(v.neueAnfragen, 1);
      expect(v.gelistet, 0);
      expect(v.nichtWeiter, 1);
      // Am 31.12.2025 war p4 in Validierung.
      expect(v.inArbeitAmEnde, 1);
      // p4 gelistet, p6 aus der Suite gelistet, p5 nicht weiter verfolgt.
      expect(v.listungsquote, closeTo(2 / 3, 1e-9));
      expect(auswerten(Zeitraum.jahr(2025)).ohneDatumGelistet, 1);
    });

    test('Verlauf je Monat', () {
      final v = auswerten(Zeitraum.jahr(2026)).verlauf;
      expect(v, hasLength(12));
      expect(v[0].neu[MusterErgebnis.gelistet], 1);
      expect(v[0].neu[MusterErgebnis.nichtWeiter], 1);
      expect(v[0].neuGesamt, 2);
      expect(v[0].staende, 1);
      expect([for (final l in v[1].gelistet) l.id], ['p4']);
      expect([for (final l in v[2].gelistet) l.id], ['p1']);
      expect([for (final l in v[2].nichtWeiter) l.id], ['p2']);
      expect(v[5].neu[MusterErgebnis.offen], 1);
      expect(v[8].neu[MusterErgebnis.offen], 1);
      // Im Oktober wurde p7 nicht weiter verfolgt — und wieder aufgenommen.
      expect(v[9].nichtWeiter, isEmpty);
    });

    test('Kunden: Schreibweise wie zuerst, die meisten Muster zuerst', () {
      expect(kundenListe(laeufe, gesamtprojekte), [
        'Beispiel Feinkost',
        'Muster Markt',
      ]);
      final k = auswerten(Zeitraum.jahr(2026)).kunden;
      expect(
        [for (final x in k) x.kunde],
        ['Beispiel Feinkost', 'Muster Markt'],
      );
      expect(k.first.anzahl(MusterErgebnis.gelistet), 1);
      expect(k.first.quote, .5);
      expect(k.last.anzahl(MusterErgebnis.offen), 2);

      // Der Filter achtet nicht auf Groß- und Kleinschreibung.
      final mm = auswerten(Zeitraum.jahr(2026), kunde: 'MUSTER MARKT');
      expect(mm.zahlen.neueMuster, 2);
      expect(mm.zahlen.neueAnfragen, 0);
      expect(mm.vorjahr.neueMuster, 1);
      expect(mm.vorjahr.neueAnfragen, 1);
      // Stände nur von den Mustern des Kunden.
      expect(mm.zahlen.staendeAngelegt, 0);

      final ohne = auswerten(Zeitraum.jahr(2025), kunde: kOhneKunde);
      expect([for (final l in ohne.neu) l.id], ['p5']);
      expect(ohne.kunden.single.kunde, isNull);
    });

    test('Gründe: der genannte — sonst ohne Angabe', () {
      expect(
        [
          for (final g in auswerten(Zeitraum.jahr(2025)).gruende)
            (g.grund, g.anzahl),
        ],
        [('Zu teuer', 1)],
      );
      final a = auswerten(Zeitraum.jahr(2026));
      expect(a.gruende.single.grund, 'Kunde hat Muster A gewählt');
      expect(a.grund(lauf('p2')), 'Kunde hat Muster A gewählt');
      expect(a.eingestelltAm(lauf('p2')), DateTime(2026, 3, 20));
    });

    test('ein vergangenes Quartal: in Arbeit an seinem Ende', () {
      final a = auswerten(Zeitraum.quartal(2026, 1));
      expect(a.laeuftNoch, isFalse);
      expect(a.stichtag, DateTime(2026, 3, 31));
      expect(a.zahlen.neueMuster, 2);
      expect(a.zahlen.gelistet, 2);
      // Am 31.03.: keines mehr in Arbeit (p1, p4 gelistet, p2 nicht weiter).
      expect(a.zahlen.inArbeitAmEnde, 0);
      expect(a.verlauf, hasLength(3));
    });

    test('ohne Muster: keine Quote, keine Durchlaufzeit', () {
      final a = auswerten(Zeitraum.jahr(2020));
      expect(a.zahlen.neueMuster, 0);
      expect(a.zahlen.listungsquote, isNull);
      expect(a.zahlen.trefferquote, isNull);
      expect(a.zahlen.tageBisListung, isNull);
      expect(quoteText(null), '—');
      expect(tageText(null), '—');
      expect(tageText(1), '1 Tag');
      expect(tageText(84.4), '84 Tage');
      expect(veraenderungText(5, 3), '+2');
      expect(veraenderungText(3, 5), '−2');
      expect(veraenderungText(3, 3), '±0');
    });
  });

  group('mit der Datenbank', () {
    late AppDatabase db;
    late ProjektRepository projekte;

    setUp(() {
      db = testDatenbank();
      projekte = ProjektRepository(db);
    });
    tearDown(() => db.close());

    test('Wechsel und Gründe so, wie die App sie festhält', () async {
      final g = await projekte.gesamtprojektAnlegen(
        name: 'Anfrage Testsortiment',
        kunde: 'Beispiel Feinkost',
        muster: ['Variante 1', 'Variante 2'],
        jetzt: DateTime(2026, 2, 3, 10),
      );
      final muster = await projekte.muster(g);
      await projekte.statusAendern(
        muster[0].id,
        ProjektStatus.validierung,
        jetzt: DateTime(2026, 3, 2, 8),
      );
      await projekte.statusAendern(
        muster[0].id,
        ProjektStatus.produktion,
        jetzt: DateTime(2026, 4, 14, 8),
      );
      await projekte.statusAendern(
        muster[1].id,
        ProjektStatus.eingestellt,
        grund: 'Kunde hat Variante 1 gewählt',
        jetzt: DateTime(2026, 3, 2, 9),
      );
      final einzeln = await projekte.projektAnlegen(
        name: 'Eigene Idee',
        jetzt: DateTime(2026, 5, 6),
      );
      await projekte.projektAendern(
        einzeln,
        const EntwicklungProjekteCompanion(neueZutaten: Value(true)),
      );

      final laeufe = musterLaeufe(
        projekte: await projekte.projekteBeobachten().first,
        gesamtprojekte: await projekte.gesamtprojekteBeobachten().first,
        eintraege: await projekte.alleEintraegeBeobachten().first,
      );
      final a = entwicklungAuswerten(
        laeufe: laeufe,
        zeitraum: Zeitraum.jahr(2026),
        heute: DateTime(2026, 11, 9),
        gesamtprojekte: await projekte.gesamtprojekteBeobachten().first,
      );
      expect(a.zahlen.neueMuster, 3);
      expect(a.zahlen.neueMusterImGesamtprojekt, 2);
      expect(a.zahlen.neueAnfragen, 1);
      expect(a.zahlen.gelistet, 1);
      expect(a.gelistet.single.name, 'Variante 1');
      expect(a.gelistet.single.gesamtprojekt, 'Anfrage Testsortiment');
      expect(a.gelistet.single.tageBisListung, 70);
      expect(a.zahlen.nichtWeiter, 1);
      expect(a.gruende.single.grund, 'Kunde hat Variante 1 gewählt');
      expect(a.zahlen.neueZutaten, 1);
      expect(a.zahlen.inArbeitAmEnde, 1);
      expect(a.kunden.first.kunde, 'Beispiel Feinkost');
      expect(a.kunden.last.kunde, isNull);
    });
  });
}
