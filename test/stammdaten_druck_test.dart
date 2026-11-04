import 'dart:convert' show latin1;

// `show Value`: drift bringt eine eigene Klasse `Column` mit.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/constants/abteilungen.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/druck/druck_layout.dart';
import 'package:produktion_planer/core/druck/druck_optionen.dart';
import 'package:produktion_planer/core/druck/druck_satz.dart';
import 'package:produktion_planer/features/articles/artikel_luecken.dart';
import 'package:produktion_planer/features/articles/artikelliste_druck.dart';
import 'package:produktion_planer/features/settings/grenzen_druck.dart';
import 'package:produktion_planer/features/settings/maschinen_druck_daten.dart';
import 'package:produktion_planer/features/settings/maschinenkatalog_druck.dart';

import 'helpers/stammdaten_beispiele.dart';
import 'helpers/test_db.dart';

/// Tests für die Ausdrucke der Stammdaten: die Artikelliste (wie die Liste,
/// alle oder mit Lücken; nach Nummer, je Produktgruppe, je Abteilung), den
/// Maschinen-Katalog (Übersicht und Steckbriefe) und die Maschinen-Grenzen
/// — dazu die Wahl im Druckfenster und das Laden aus der Datenbank.
///
/// Die PDFs entstehen unkomprimiert — so steht jedes gedruckte Wort als
/// „(Wort)" im Dokument und lässt sich suchen. Alle Daten sind erfunden.
void main() {
  final gedruckt = DateTime(2026, 10, 30, 8, 52);

  Future<(DruckErgebnis, String)> setze(DruckDokument d) async {
    final e = await druckSetzen(d, const DruckLayout(), komprimiert: false);
    return (e, latin1.decode(e.bytes));
  }

  Future<String> text(DruckDokument d) async => (await setze(d)).$2;

  /// Wie oft [wort] gedruckt ist.
  int wieOft(String t, String wort) =>
      RegExp(RegExp.escape(wort)).allMatches(t).length;

  DruckOption option(DruckAuftrag a, String schluessel) =>
      a.optionen.firstWhere((o) => o.schluessel == schluessel);

  List<String> werteVon(DruckAuftrag a, String schluessel) =>
      switch (option(a, schluessel)) {
        final DruckWahlEins o => [for (final w in o.werte) w.wert],
        final DruckWahlMehrere o => [for (final w in o.werte) w.wert],
        _ => const [],
      };

  // ── Artikelliste ────────────────────────────────────────────────────────

  group('Artikelliste', () {
    Future<String> liste(
      ArtikellisteInhalt inhalt, {
      bool gefiltert = false,
    }) =>
        text(
          artikellisteDruck(
            bspArtikelliste(gefiltert: gefiltert),
            inhalt: inhalt,
            gedrucktAm: gedruckt,
          ),
        );

    test('alle Artikel, sortiert wie die Liste, mit Kennzahlen', () async {
      final dokument = artikellisteDruck(
        bspArtikelliste(),
        gedrucktAm: gedruckt,
      );
      expect(dokument.titel, 'Artikel Alle Artikel');
      final (e, t) = await setze(dokument);
      expect(e.seiten, 1);
      // Nach Bezeichnung — wie die Liste.
      final bratwurst = t.indexOf('(Bratwurst)');
      final hack = t.indexOf('(Hackbällchen)');
      final schulter = t.indexOf('(Schweineschulter)');
      expect(bratwurst, greaterThan(-1));
      expect(bratwurst, lessThan(hack));
      expect(hack, lessThan(schulter));
      // Kennzahlen, die Lücken unter der Bezeichnung, Anlagen mit Namen.
      expect(t, contains('(vollständig)'));
      expect(t, contains('(Platzhalter)'));
      expect(t, contains('(Würfelanlage)'));
      // Die Abteilungen als Kürzel, erklärt am Ende.
      expect(t, contains('(KA)'));
      expect(t, contains('(Kutterabteilung)'));
      // Ohne Produktgruppe steht die frühere Planungsgruppe da.
      expect(t, contains('(Zerlegeware)'));
    });

    test('nach Artikelnummer: Zahlen wie Zahlen', () async {
      final t = await liste(
        const ArtikellisteInhalt(reihenfolge: ArtikellisteReihenfolge.nummer),
      );
      final n999 = t.indexOf('(999)');
      final n7101 = t.indexOf('(7101)');
      final n7502 = t.indexOf('(7502)');
      expect(n999, greaterThan(-1));
      expect(n999, lessThan(n7101), reason: '999 vor 7101');
      expect(n7101, lessThan(n7502));
    });

    test('wie die Liste gefiltert — oder nur mit Lücken', () async {
      final gefiltert = await liste(
        const ArtikellisteInhalt(umfang: ArtikellisteUmfang.liste),
        gefiltert: true,
      );
      expect(gefiltert, contains('(Bratwurst)'));
      expect(gefiltert, contains('(Leberkäse)'));
      expect(gefiltert, isNot(contains('(Hackbällchen)')));
      expect(gefiltert, contains('(Ausbeute)'), reason: 'Filter im Kopf');

      final luecken = await liste(
        const ArtikellisteInhalt(umfang: ArtikellisteUmfang.luecken),
      );
      expect(luecken, contains('(Schweineschulter)'));
      expect(luecken, contains('(Grillbrät)'));
      expect(luecken, isNot(contains('(Rinderkeule)')));
      expect(luecken, isNot(contains('(Hackbällchen)')));
    });

    test('je Produktgruppe — ohne Gruppe zuletzt, keine Gruppen-Spalte',
        () async {
      // Auf eine Seite verkleinert: So steht der Text im PDF in der
      // Reihenfolge des Blatts.
      final e = await druckSetzen(
        artikellisteDruck(
          bspArtikelliste(),
          inhalt: const ArtikellisteInhalt(
            reihenfolge: ArtikellisteReihenfolge.gruppe,
          ),
          gedrucktAm: gedruckt,
        ),
        const DruckLayout(anpassung: DruckAnpassung.eineSeite),
        komprimiert: false,
      );
      expect(e.seiten, 1);
      final t = latin1.decode(e.bytes);
      final braten = t.indexOf('(Braten)');
      final kochpoekel = t.indexOf('(Kochpökelware)');
      // Das erste „Produktgruppe" steht im Kopf (je Produktgruppe), das
      // letzte im Abschnitt ohne Gruppe.
      final ohne = t.lastIndexOf('(Produktgruppe)');
      expect(braten, greaterThan(-1));
      expect(braten, lessThan(kochpoekel));
      expect(kochpoekel, lessThan(ohne));
      expect(t, isNot(contains('(Gruppe)')));
    });

    test('je Abteilung: ein Artikel bei jeder seiner Abteilungen', () async {
      final alle = await liste(const ArtikellisteInhalt());
      expect(wieOft(alle, '(Gartenwurst)'), 2);

      final t = await liste(
        const ArtikellisteInhalt(
          reihenfolge: ArtikellisteReihenfolge.abteilung,
        ),
      );
      // Gartenwurst gebraten bei Bratstraße und Verpackung, dazu die Schale.
      expect(wieOft(t, '(Gartenwurst)'), 3);
      expect(t, contains('(Prozessschritte)'), reason: 'ohne Schritte am Ende');

      final nurZerlegung = await liste(
        const ArtikellisteInhalt(
          reihenfolge: ArtikellisteReihenfolge.abteilung,
          abteilungen: {'zerlegung'},
        ),
      );
      expect(nurZerlegung, contains('(Rinderkeule)'));
      expect(nurZerlegung, isNot(contains('(Gartenwurst)')));
      expect(nurZerlegung, isNot(contains('(Leberkäse)')));
    });

    test('Spalte für Notizen, ohne Anlagen, Lücken und Kennzahlen', () async {
      final t = await liste(
        const ArtikellisteInhalt(
          notizen: true,
          anlagen: false,
          luecken: false,
          kennzahlen: false,
        ),
      );
      expect(t, contains('(Notiz)'));
      expect(t, isNot(contains('(Anlagen)')));
      expect(t, isNot(contains('(Nord)')));
      expect(t, isNot(contains('(Platzhalter)')));
      expect(t, isNot(contains('(vollständig)')));
    });

    test('Druckfenster: vorgewählt, was die Liste zeigt', () async {
      final gefiltert = artikellisteDruckAuftrag(
        bspArtikelliste(gefiltert: true),
        gedrucktAm: gedruckt,
      );
      expect(gefiltert.art, 'artikelliste');
      expect(
        werteVon(gefiltert, ArtikellisteWahl.umfang),
        ['liste', 'alle', 'luecken'],
      );
      final wahl = DruckWahl.standard(gefiltert.optionen);
      expect(wahl.eins(ArtikellisteWahl.umfang), 'liste');
      expect(wahl.eins(ArtikellisteWahl.reihenfolge), 'liste');
      expect(wahl.an(ArtikellisteWahl.notizen), isFalse);
      expect(
        (await text(await gefiltert.bauen(wahl))),
        isNot(contains('(Hackbällchen)')),
      );

      // Die Abteilungen zur Wahl, nur je Abteilung sichtbar.
      final abteilungen = option(gefiltert, ArtikellisteWahl.abteilungen);
      expect(
        werteVon(gefiltert, ArtikellisteWahl.abteilungen),
        ['zerlegung', 'kutterabteilung', 'bratstrasse', 'verpackung'],
      );
      expect(abteilungen.sichtbar!(wahl), isFalse);
      final jeAbteilung = wahl.mit(ArtikellisteWahl.reihenfolge, 'abteilung');
      expect(abteilungen.sichtbar!(jeAbteilung), isTrue);
      expect(
        () => gefiltert.bauen(
          jeAbteilung.mit(ArtikellisteWahl.abteilungen, <String>{}),
        ),
        throwsA(isA<DruckNichtsGewaehlt>()),
      );

      // Ohne Filter gibt es „Wie die Liste" nicht.
      final alle = artikellisteDruckAuftrag(bspArtikelliste());
      expect(werteVon(alle, ArtikellisteWahl.umfang), ['alle', 'luecken']);
      expect(
        DruckWahl.standard(alle.optionen).eins(ArtikellisteWahl.umfang),
        'alle',
      );
    });

    test('Anlagen mit Namen, in Prozessreihenfolge', () async {
      final db = testDatenbank();
      addTearDown(db.close);
      await seedArtikel(db, id: 'p1', nummer: '4711', bezeichnung: 'Probe');
      await seedAnlage(
        db,
        id: 'm1',
        name: 'Packanlage Ost',
        abteilung: 'verpackung',
      );
      await seedAnlage(
        db,
        id: 'm2',
        name: 'Bratlinie Süd',
        abteilung: 'bratstrasse',
      );
      await seedSchritt(
        db,
        id: 's1',
        productId: 'p1',
        reihenfolge: 2,
        abteilung: 'verpackung',
        maschineId: 'm1',
      );
      await seedSchritt(
        db,
        id: 's2',
        productId: 'p1',
        reihenfolge: 1,
        abteilung: 'bratstrasse',
        maschineId: 'm2',
      );
      await seedSchritt(
        db,
        id: 's3',
        productId: 'p1',
        reihenfolge: 3,
        abteilung: 'verpackung',
        maschineId: 'm1',
      );
      final produkt = await db.select(db.products).getSingle();
      final schritte = await db.select(db.productSteps).get();
      final namen = {
        for (final m in await db.select(db.machines).get()) m.id: m.name,
      };

      final e = artikellisteEintrag(
        produkt,
        schritte,
        {ArtikelLuecke.ohneAusbeute},
        namen,
      );
      expect(e.nummer, '4711');
      expect(e.schritte, 3);
      expect(e.abteilungen, [Abteilung.bratstrasse, Abteilung.verpackung]);
      expect(e.anlagen, ['Bratlinie Süd', 'Packanlage Ost']);
      expect(e.luecken, {ArtikelLuecke.ohneAusbeute});
      // Eine Anlage, die der Katalog nicht kennt, bleibt sichtbar.
      expect(
        prozessAnlagen(schritte, const {'m1': 'Packanlage Ost'}),
        ['Anlage ohne Namen', 'Packanlage Ost'],
      );
    });
  });

  // ── Maschinen-Katalog ───────────────────────────────────────────────────

  group('Maschinen-Katalog', () {
    test('Übersicht: je Abteilung die Anlagen in einer Zeile', () async {
      final dokument = maschinenkatalogDruck(
        bspMaschinen(),
        gedrucktAm: gedruckt,
      );
      expect(dokument.titel, 'Maschinen-Katalog');
      final (e, t) = await setze(dokument);
      expect(e.seiten, 1);
      final zerlegung = t.indexOf('(Zerlegung)');
      final brat = t.indexOf('(Bratstraße)');
      final verpackung = t.indexOf('(Verpackung)');
      expect(zerlegung, greaterThan(-1));
      expect(zerlegung, lessThan(brat));
      expect(brat, lessThan(verpackung));
      for (final wort in [
        '(Bratlinie)',
        '(8:00)',
        '(Gatter)',
        '(Knochenware)',
        '(Planungsspur)',
      ]) {
        expect(t, contains(wort), reason: wort);
      }
      // Steckbriefe gibt es hier nur als Liste — ohne Grenzwerte.
      expect(t, isNot(contains('(Herstellerangabe)')));
    });

    test('Steckbriefe: Parameter mit Einheit, Grenzen und Artikeln', () async {
      final dokument = maschinenkatalogDruck(
        bspMaschinen(),
        gedrucktAm: gedruckt,
        inhalt: const KatalogInhalt(
          darstellung: KatalogDarstellung.steckbriefe,
        ),
      );
      expect(dokument.titel, 'Maschinen-Steckbriefe');
      final t = await text(dokument);
      for (final wort in [
        '(Herstellerangabe)',
        '(72,5)',
        '(260)',
        '(max.)',
        '(Steckbrief)',
        '(Genutzt)',
        '(7201)',
        '(Typisch:)',
      ]) {
        expect(t, contains(wort), reason: wort);
      }
      expect(t, contains('(keinem)'), reason: 'Bandsäge: kein Artikel');
    });

    test('nur gewählte Abteilungen, jede Anlage auf einer neuen Seite',
        () async {
      final (e, t) = await setze(
        maschinenkatalogDruck(
          bspMaschinen(),
          gedrucktAm: gedruckt,
          inhalt: const KatalogInhalt(
            darstellung: KatalogDarstellung.steckbriefe,
            abteilungen: {'verpackung'},
            neueSeite: true,
            artikel: false,
          ),
        ),
      );
      expect(e.seiten, 2, reason: 'Packanlage A und B');
      expect(t, contains('(Packanlage)'));
      expect(t, isNot(contains('(Bratlinie)')));
      expect(t, isNot(contains('(Genutzt)')));
      expect(t, isNot(contains('(Steckbriefen)')), reason: 'ohne Kennzahlen');
    });

    test('Druckfenster: Darstellung, Abteilungen, Seitenumbruch', () {
      final a = maschinenkatalogDruckAuftrag(bspMaschinen());
      expect(a.art, 'maschinenkatalog');
      expect(
        werteVon(a, KatalogWahl.abteilungen),
        ['zerlegung', 'bratstrasse', 'verpackung'],
      );
      final wahl = DruckWahl.standard(a.optionen);
      expect(wahl.eins(KatalogWahl.darstellung), 'uebersicht');
      expect(option(a, KatalogWahl.abteilungSeite).sichtbar!(wahl), isTrue);
      expect(option(a, KatalogWahl.anlageSeite).sichtbar!(wahl), isFalse);
      final steckbriefe = wahl.mit(KatalogWahl.darstellung, 'steckbriefe');
      expect(
        option(a, KatalogWahl.anlageSeite).sichtbar!(steckbriefe),
        isTrue,
      );
      expect(
        () => a.bauen(wahl.mit(KatalogWahl.abteilungen, <String>{})),
        throwsA(isA<DruckNichtsGewaehlt>()),
      );
    });

    test('aus der Datenbank: Steckbrief, Grenzen, Artikel ohne Gelöschtes',
        () async {
      final db = testDatenbank();
      addTearDown(db.close);
      await seedAnlage(
        db,
        id: 'm1',
        name: 'Packanlage Ost',
        abteilung: 'verpackung',
      );
      await seedAnlage(
        db,
        id: 'm2',
        name: 'Alte Anlage',
        abteilung: 'verpackung',
      );
      await (db.update(db.machines)..where((m) => m.id.equals('m2')))
          .write(MachinesCompanion(deletedAt: Value(gedruckt)));
      for (final (i, name) in ['Siegelzeit', 'Programm', 'Alt'].indexed) {
        await db.into(db.machineParameterDefs).insert(
              MachineParameterDefsCompanion.insert(
                id: 'd$i',
                maschineId: 'm1',
                parameterName: name,
                // „Programm" steht in der Maske oben.
                sortierung: Value(name == 'Programm' ? 0 : 1),
                deletedAt: Value(name == 'Alt' ? gedruckt : null),
              ),
            );
      }
      await db.into(db.parameterGrenzen).insert(
            ParameterGrenzenCompanion.insert(
              id: 'g1',
              kontext: 'Packanlage Ost',
              parameterName: 'Siegelzeit',
              hartMax: const Value(5),
            ),
          );
      await db.into(db.parameterGrenzen).insert(
            ParameterGrenzenCompanion.insert(
              id: 'g2',
              kontext: 'Packanlage Ost',
              parameterName: 'Alt',
              hartMax: const Value(1),
              deletedAt: Value(gedruckt),
            ),
          );
      await seedArtikel(db, id: 'p1', nummer: '1200', bezeichnung: 'Zweiter');
      await seedArtikel(db, id: 'p2', nummer: '120', bezeichnung: 'Erster');
      await seedArtikel(db, id: 'p3', nummer: '130', bezeichnung: 'Gelöscht');
      for (final (i, p) in ['p1', 'p2', 'p2', 'p3'].indexed) {
        await seedSchritt(
          db,
          id: 's$i',
          productId: p,
          reihenfolge: i,
          abteilung: 'verpackung',
          maschineId: 'm1',
        );
      }
      await (db.update(db.products)..where((p) => p.id.equals('p3')))
          .write(ProductsCompanion(deletedAt: Value(gedruckt)));

      final daten = await maschinenDruckLaden(db);
      expect([for (final m in daten.maschinen) m.name], ['Packanlage Ost']);
      expect(
        [for (final d in daten.steckbriefe['m1']!) d.parameterName],
        ['Programm', 'Siegelzeit'],
      );
      expect([for (final g in daten.grenzen) g.parameterName], ['Siegelzeit']);
      expect(
        daten.artikel['m1'],
        [
          (nummer: '120', bezeichnung: 'Erster'),
          (nummer: '1200', bezeichnung: 'Zweiter'),
        ],
        reason: 'jeder einmal, nach Nummer, ohne gelöschte',
      );
      expect(daten.maschineNamens('Packanlage Ost')?.id, 'm1');
      expect(daten.maschineNamens('BRATSTRASSE'), isNull);
    });
  });

  // ── Maschinen-Grenzen ───────────────────────────────────────────────────

  group('Maschinen-Grenzen', () {
    test('Bereiche als Text', () {
      expect(grenzText(10, 20), '10 bis 20');
      expect(grenzText(72.5, null), 'min. 72,5');
      expect(grenzText(null, 5), 'max. 5');
      expect(grenzText(null, null), '-');
    });

    test('je Anlage oder Gruppe, alphabetisch wie die Seite', () async {
      final (e, t) = await setze(
        grenzenDruck(bspMaschinen(), gedrucktAm: gedruckt),
      );
      expect(e.seiten, 1);
      final gruppe = t.indexOf('(BRATSTRASSE)');
      final linie = t.indexOf('(Bratlinie)');
      final pack = t.indexOf('(Packanlage)');
      expect(gruppe, greaterThan(-1));
      expect(gruppe, lessThan(linie));
      expect(linie, lessThan(pack));
      for (final wort in [
        '(260)',
        '(min.)',
        '(72,5)',
        '(max.)',
        '(Parametergruppe)',
        '(Herstellerangabe)',
        '(gemeldet,)',
      ]) {
        expect(t, contains(wort), reason: wort);
      }
      // Parameter ohne Grenze nur auf Wunsch.
      expect(t, isNot(contains('(Bandzeit)')));
    });

    test('mit Parametern ohne Grenze, ohne Notizen', () async {
      final t = await text(
        grenzenDruck(
          bspMaschinen(),
          gedrucktAm: gedruckt,
          inhalt: const GrenzenInhalt(ohne: true, notizen: false),
        ),
      );
      expect(t, contains('(Bandzeit)'));
      expect(t, contains('(Programm)'));
      expect(t, isNot(contains('(Herstellerangabe)')));
    });

    test('zum Aushängen: jede Anlage auf einer Seite mit Erklärung', () async {
      final (e, t) = await setze(
        grenzenDruck(
          bspMaschinen(),
          gedrucktAm: gedruckt,
          inhalt: const GrenzenInhalt(
            kontexte: {'Bratlinie Nord', 'Packanlage A'},
            einzeln: true,
          ),
        ),
      );
      expect(e.seiten, 2);
      expect(t, isNot(contains('(BRATSTRASSE)')));
      expect(wieOft(t, '(gemeldet,)'), 2, reason: 'je Seite die Erklärung');
      expect(t, isNot(contains('(gepflegt)')), reason: 'ohne Kennzahlen');
    });

    test('Druckfenster: Anlagen und Gruppen zur Wahl', () {
      final a = grenzenDruckAuftrag(bspMaschinen());
      expect(a.art, 'grenzen');
      expect(
        werteVon(a, GrenzenWahl.kontexte),
        ['BRATSTRASSE', 'Bratlinie Nord', 'Packanlage A'],
      );
      final kontexte = option(a, GrenzenWahl.kontexte) as DruckWahlMehrere;
      expect(kontexte.werte[1].hinweis, 'Anlage · Bratstraße · 3 Grenzen');
      expect(kontexte.werte.first.hinweis, 'Parametergruppe · 2 Grenzen');
      final wahl = DruckWahl.standard(a.optionen);
      expect(wahl.an(GrenzenWahl.ohne), isFalse);
      expect(wahl.an(GrenzenWahl.einzeln), isFalse);
      expect(
        () => a.bauen(wahl.mit(GrenzenWahl.kontexte, <String>{})),
        throwsA(isA<DruckNichtsGewaehlt>()),
      );
    });
  });
}
