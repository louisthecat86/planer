import 'dart:convert' show latin1;

// `show Value`: drift bringt eine eigene Klasse `Column` mit.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/druck/druck_layout.dart';
import 'package:produktion_planer/core/druck/druck_optionen.dart';
import 'package:produktion_planer/core/druck/druck_satz.dart';
import 'package:produktion_planer/features/entwicklung/daten/entwicklung_repository.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_checkliste.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_modell.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_repository.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projektliste_druck.dart';
import 'package:produktion_planer/features/entwicklung/rechenkern/rechen_modell.dart';
import 'package:produktion_planer/features/entwicklung/rechenkern/rechenkern.dart';
import 'package:produktion_planer/features/entwicklung/rezepturen/rezeptur_druck_daten.dart';
import 'package:produktion_planer/features/entwicklung/rezepturen/rezepturblatt_druck.dart';
import 'package:produktion_planer/features/entwicklung/rezepturen/standvergleich_druck.dart';
import 'package:produktion_planer/features/entwicklung/zutaten/zutatenkatalog_druck.dart';

import 'helpers/entwicklung_beispiele.dart';
import 'helpers/test_db.dart';

/// Tests für die Ausdrucke der Produktentwicklung: Rezepturblatt (mit und
/// ohne Mengen, umgerechnet, zum Abwiegen), Stände im Vergleich,
/// Projektliste und Zutatenkatalog — dazu die Wahl im Druckfenster und das
/// Laden aus der Datenbank.
///
/// Die PDFs entstehen unkomprimiert — so steht jedes gedruckte Wort als
/// „(Wort)" im Dokument und lässt sich suchen. Alle Daten sind erfunden.
void main() {
  final gedruckt = DateTime(2026, 10, 29, 7, 41);

  Future<(DruckErgebnis, String)> setze(
    DruckDokument d, {
    DruckLayout layout = const DruckLayout(),
  }) async {
    final e = await druckSetzen(d, layout, komprimiert: false);
    return (e, latin1.decode(e.bytes));
  }

  Future<String> text(DruckDokument d) async => (await setze(d)).$2;

  /// Die Seitenangaben aller Fußzeilen: („Seite 2 von 3" → (2, 3)).
  List<(int, int)> seitenAngaben(String t) => [
        for (final m in RegExp(
          r'\(Seite\)\]TJ.*?\((\d+)\)\]TJ.*?\(von\)\]TJ.*?\((\d+)\)\]TJ',
          dotAll: true,
        ).allMatches(t))
          (int.parse(m.group(1)!), int.parse(m.group(2)!)),
      ];

  // ── Rezepturblatt ───────────────────────────────────────────────────────

  group('Rezepturblatt', () {
    RezepturblattDaten gartenwurst({
      int stand = 2,
      bool abgeschlossen = true,
      bool freigegeben = false,
    }) =>
        RezepturblattDaten(
          name: 'Gartenwurst',
          artikelnummer: '40711',
          beschreibung: 'Grobe Brühwurst mit Kräuterbrät.',
          version: bspVersion(
            nummer: stand,
            abgeschlossen: abgeschlossen,
            bezeichnung: stand == 2 ? 'Weniger Salz' : null,
            notiz: stand == 2 ? 'Salz gesenkt, Speck erhöht.' : null,
          ),
          eingabe: bspGartenwurst(stand: stand),
          freigegeben: freigegeben,
        );

    Future<String> blatt(
      RezepturblattDaten daten, [
      RezepturblattInhalt inhalt = const RezepturblattInhalt(),
    ]) =>
        text(rezepturblattDruck(daten, inhalt: inhalt, gedrucktAm: gedruckt));

    test('der Stand in Worten: Bezeichnung, Entwurf, abgeschlossen, frei',
        () {
      expect(
        rezepturStandText(bspVersion(bezeichnung: 'Weniger Salz')),
        'Stand 2 · Weniger Salz · abgeschlossen am 14.10.2026',
      );
      expect(
        rezepturStandText(bspVersion(), freigegeben: true),
        'Stand 2 · freigegeben · abgeschlossen am 14.10.2026',
      );
      expect(
        rezepturStandText(bspVersion(nummer: 3, abgeschlossen: false)),
        'Stand 3 · Entwurf, geändert am 15.10.2026',
      );
    });

    test('umgerechnet: auf den Ansatz, auf das Endgewicht, sonst nicht', () {
      final e = berechne(bspGartenwurst());
      expect(e.eingesetztKg, closeTo(103.6, 1e-9));
      expect(e.endgewichtKg, closeTo(93.24, 1e-9));
      expect(rezepturFaktor(e, const RezepturblattInhalt()), 1);
      expect(
        rezepturFaktor(
          e,
          const RezepturblattInhalt(mengen: RezepturMengen.ansatz, kg: 250),
        ),
        closeTo(250 / 103.6, 1e-12),
      );
      expect(
        rezepturFaktor(
          e,
          const RezepturblattInhalt(mengen: RezepturMengen.endgewicht, kg: 80),
        ),
        closeTo(80 / 93.24, 1e-12),
      );
      // Ohne Mengen gibt es nichts umzurechnen.
      expect(
        rezepturFaktor(
          berechne(const RechenRezeptur(id: 'r', name: 'Leer', positionen: [])),
          const RezepturblattInhalt(mengen: RezepturMengen.ansatz, kg: 250),
        ),
        1,
      );
    });

    test('Standard: Mengen wie in der Rezeptur, alles, was es zu sagen gibt',
        () async {
      final t = await blatt(gartenwurst(freigegeben: true));
      for (final wort in [
        '(Gartenwurst)',
        '(40711)',
        '(Weniger)',
        '(freigegeben)',
        '(14.10.2026)',
        // Kennzahlen: Einsatz, Verlust, Endgewicht.
        '(103,6)',
        '(10,0)',
        '(93,24)',
        // Die Zusammensetzung mit Menge und Anteil.
        '(Zusammensetzung)',
        '(Menge)',
        '(Anteil)',
        '(38,6)',
        '(Summe)',
        // Beschreibung und Grund des Stands.
        '(Grobe)',
        '(gesenkt,)',
        // Die Unterrezepturen — auch die im Brät.
        '(Unterrezeptur:)',
        '(Kräuterbrät)',
        '(8,421)',
        '(5,053)',
        '(Kräuterpaste)',
        '(1,112)',
        '(0,667)',
        // Das Ergebnis.
        '(Zutatenverzeichnis)',
        '(Nährwerte)',
        '(Sellerie)',
        '(Senf)',
        '(Verarbeitungshilfsstoff:)',
        '(LMIV)',
        '(Bindegewebe)',
        '(Hinweise)',
      ]) {
        expect(t, contains(wort), reason: wort);
      }
      // Ohne Wahl nichts für die Produktion.
      expect(t, isNot(contains('(Soll)')));
      expect(t, isNot(contains('(Hergestellt)')));
      expect(t, isNot(contains('(Entwurf)')));
      expect(seitenAngaben(t), isNotEmpty);
    });

    test('auf eine Ansatzgröße umgerechnet — auch die Unterrezepturen',
        () async {
      final t = await blatt(
        gartenwurst(),
        const RezepturblattInhalt(mengen: RezepturMengen.ansatz, kg: 250),
      );
      expect(t, contains('(Umgerechnet)'));
      expect(t, contains('(250)'));
      expect(t, contains('(225)'));
      // 40 kg von 103,6 kg sind auf 250 kg 96,525 kg.
      expect(t, contains('(96,525)'));
      // Das Brät: 8 kg von 103,6 kg, auf 250 kg 19,305 kg fertig.
      expect(t, contains('(19,305)'));
      // Die Anteile bleiben.
      expect(t, contains('(38,6)'));
    });

    test('auf ein Endgewicht umgerechnet — der Verlust ist eingerechnet',
        () async {
      final t = await blatt(
        gartenwurst(),
        const RezepturblattInhalt(mengen: RezepturMengen.endgewicht, kg: 80),
      );
      // 80 kg fertig brauchen 88,889 kg Einsatz — davon 34,32 kg Schwein.
      expect(t, contains('(80)'));
      expect(t, contains('(88,889)'));
      expect(t, contains('(34,32)'));
    });

    test('nur Anteile: keine Mengen in kg', () async {
      final t = await blatt(
        gartenwurst(),
        const RezepturblattInhalt(
          mengen: RezepturMengen.anteile,
          hinweise: false,
        ),
      );
      expect(t, contains('(Anteil)'));
      expect(t, contains('(38,6)'));
      expect(t, isNot(contains('(Menge)')));
      expect(t, isNot(contains('(kg)')));
    });

    test('ohne Mengen: nur die Zutaten — zum Weitergeben', () async {
      final t = await blatt(
        gartenwurst(),
        const RezepturblattInhalt(mengen: RezepturMengen.ohne, hinweise: false),
      );
      expect(t, contains('(Schweinefleisch)'));
      expect(t, contains('(Kräuterbrät)'));
      for (final wort in ['(Menge)', '(Anteil)', '(Summe)', '(kg)']) {
        expect(t, isNot(contains(wort)), reason: wort);
      }
    });

    test('für die Produktion: abwiegen und Felder für die Herstellung',
        () async {
      final t = await blatt(
        gartenwurst(),
        const RezepturblattInhalt(
          mengen: RezepturMengen.ansatz,
          kg: 250,
          abwiegen: true,
          herstellung: true,
        ),
      );
      for (final wort in [
        '(Soll)',
        '(Ist)',
        '(Rohstoff-Charge)',
        '(Hergestellt)',
        '(Charge)',
        '(Kürzel)',
        '(Bemerkung)',
      ]) {
        expect(t, contains(wort), reason: wort);
      }
      expect(t, isNot(contains('(Menge)')));
    });

    test('Teile abwählen', () async {
      final t = await blatt(
        gartenwurst(),
        const RezepturblattInhalt(
          kennzahlen: false,
          notizen: false,
          unterrezepturen: false,
          zutatenliste: false,
          naehrwerte: false,
          allergene: false,
          fleisch: false,
          hinweise: false,
        ),
      );
      expect(t, contains('(Zusammensetzung)'));
      for (final wort in [
        '(Endgewicht)',
        '(Grobe)',
        '(Unterrezeptur:)',
        '(Zutatenverzeichnis)',
        '(Nährwerte)',
        '(Sellerie)',
        '(LMIV)',
        '(Hinweise)',
      ]) {
        expect(t, isNot(contains(wort)), reason: wort);
      }
    });

    test('ein Entwurf ist als Entwurf zu erkennen', () async {
      final t = await blatt(gartenwurst(stand: 3, abgeschlossen: false));
      expect(t, contains('(Entwurf)'));
      expect(t, contains('(geändert)'));
      expect(t, contains('(Magermilchpulver)'));
      expect(t, isNot(contains('(Zwiebeln,)')));
    });

    test('eine lange Rezeptur läuft über die Seite — mit Kopfzeile',
        () async {
      final (e, t) = await setze(
        rezepturblattDruck(
          RezepturblattDaten(
            name: 'Lange Rezeptur',
            version: bspVersion(nummer: 1),
            eingabe: bspLangeRezeptur(60),
          ),
          gedrucktAm: gedruckt,
          inhalt: const RezepturblattInhalt(abwiegen: true),
        ),
      );
      expect(e.seiten, greaterThan(2));
      expect(seitenAngaben(t).last, (e.seiten, e.seiten));
      expect(t, contains('(60)'));
      // Die Kopfzeile der Tabelle steht auf jeder Seite der Zeilen.
      expect('(Rohstoff-Charge)'.allMatchesIn(t), greaterThan(1));
      // Auch quer — dort passen weniger Zeilen zusammen auf eine Seite.
      final (quer, _) = await setze(
        rezepturblattDruck(
          RezepturblattDaten(
            name: 'Lange Rezeptur',
            version: bspVersion(nummer: 1),
            eingabe: bspLangeRezeptur(14),
          ),
          gedrucktAm: gedruckt,
        ),
        layout: const DruckLayout(ausrichtung: DruckAusrichtung.quer),
      );
      expect(quer.seiten, greaterThanOrEqualTo(2));
    });

    test('Druckfenster: nur, was es gibt — Zahlen nur für ihre Wahl',
        () async {
      final auftrag = rezepturblattDruckAuftrag(
        gartenwurst(),
        gedrucktAm: gedruckt,
      );
      final schluessel = [for (final o in auftrag.optionen) o.schluessel];
      expect(schluessel, [
        RezepturblattWahl.mengen,
        RezepturblattWahl.ansatzKg,
        RezepturblattWahl.endKg,
        RezepturblattWahl.kennzahlen,
        RezepturblattWahl.notizen,
        RezepturblattWahl.unterrezepturen,
        RezepturblattWahl.zutatenliste,
        RezepturblattWahl.naehrwerte,
        RezepturblattWahl.allergene,
        RezepturblattWahl.fleisch,
        RezepturblattWahl.hinweise,
        RezepturblattWahl.abwiegen,
        RezepturblattWahl.herstellung,
      ]);
      // Die Werte der Auswahl sind die der Mengen.
      final mengen = auftrag.optionen.first as DruckWahlEins;
      expect(
        [for (final w in mengen.werte) w.wert],
        [for (final m in RezepturMengen.values) m.name],
      );

      DruckOption option(String s) =>
          auftrag.optionen.firstWhere((o) => o.schluessel == s);
      final standard = DruckWahl.standard(auftrag.optionen);
      expect(option(RezepturblattWahl.ansatzKg).istSichtbar(standard), isFalse);
      final ansatz = standard.mit(RezepturblattWahl.mengen, 'ansatz');
      expect(option(RezepturblattWahl.ansatzKg).istSichtbar(ansatz), isTrue);
      expect(option(RezepturblattWahl.endKg).istSichtbar(ansatz), isFalse);
      // Abwiegen und Herstellung sind aus, die Ansatzgröße 100 kg.
      expect(standard.an(RezepturblattWahl.abwiegen), isFalse);
      expect(standard.an(RezepturblattWahl.herstellung), isFalse);
      expect(standard.zahl(RezepturblattWahl.ansatzKg), 100);

      final t = await text(
        await auftrag.bauen(ansatz.mit(RezepturblattWahl.ansatzKg, 250.0)),
      );
      expect(t, contains('(96,525)'));

      // Eine einfache Rezeptur: ohne Unterrezeptur, Fleisch, Hinweise und
      // Notizen — dann fehlen diese Schalter.
      final einfach = rezepturblattDruckAuftrag(
        RezepturblattDaten(
          name: 'Kräuteröl',
          version: bspVersion(nummer: 1),
          eingabe: RechenRezeptur(
            id: 'r-oel',
            name: 'Kräuteröl',
            positionen: [bspZeile(bspOel, 10), bspZeile(bspSalz, 0.2)],
          ),
        ),
      );
      final einfacheSchluessel = {
        for (final o in einfach.optionen) o.schluessel,
      };
      for (final s in [
        RezepturblattWahl.notizen,
        RezepturblattWahl.unterrezepturen,
        RezepturblattWahl.fleisch,
        RezepturblattWahl.hinweise,
      ]) {
        expect(einfacheSchluessel, isNot(contains(s)), reason: s);
      }
    });
  });

  // ── Stände im Vergleich ─────────────────────────────────────────────────

  group('Stände im Vergleich', () {
    StandvergleichDaten daten() => StandvergleichDaten(
          name: 'Gartenwurst',
          artikelnummer: '40711',
          freigabeVersionId: 'v2',
          staende: [
            // Absichtlich nicht nach Nummer.
            VergleichStand(
              version: bspVersion(nummer: 3, abgeschlossen: false),
              eingabe: bspGartenwurst(stand: 3),
            ),
            VergleichStand(
              version: bspVersion(nummer: 1, notiz: 'Erster Stand.'),
              eingabe: bspGartenwurst(stand: 1),
            ),
            VergleichStand(
              version: bspVersion(nummer: 2, bezeichnung: 'Weniger Salz'),
              eingabe: bspGartenwurst(),
            ),
          ],
        );

    test('alle drei: Zusammensetzung, Kennzahlen, Änderungen', () async {
      final t = await text(
        standvergleichDruck(daten(), {'v1', 'v2', 'v3'}, gedrucktAm: gedruckt),
      );
      for (final wort in [
        '(Die)',
        '(Erster)',
        '(freigegeben)',
        '(Entwurf)',
        '(Magermilchpulver)',
        '(Zwiebeln,)',
        // Der Einsatz je Stand.
        '(100,8)',
        '(103,6)',
        '(102,1)',
        '(Fleischanteil)',
        '(Allergene)',
        '(Milch,)',
        // In Sätzen, was sich geändert hat.
        '(gegenüber)',
        '(Entfernt:)',
        '(Neu:)',
      ]) {
        expect(t, contains(wort), reason: wort);
      }
      // Die Stände in der Reihenfolge der Nummern.
      final s1 = t.indexOf('(100,8)');
      final s2 = t.indexOf('(103,6)');
      final s3 = t.indexOf('(102,1)');
      expect(s1, lessThan(s2));
      expect(s2, lessThan(s3));
      // Ohne Wahl kein Zutatenverzeichnis.
      expect(t, isNot(contains('(Zutatenverzeichnis)')));
    });

    test('Anteile statt kg — ohne Endgewicht', () async {
      final t = await text(
        standvergleichDruck(
          daten(),
          {'v1', 'v3'},
          gedrucktAm: gedruckt,
          inhalt: const StandvergleichInhalt(anteile: true, zutatenliste: true),
        ),
      );
      // 40 kg von 100,8 kg.
      expect(t, contains('(39,7)'));
      expect(t, isNot(contains('(Endgewicht)')));
      expect(t, contains('(Zutatenverzeichnis)'));
      // Stand 2 ist nicht gewählt — die Änderungen gelten 1 gegen 3.
      expect(t, isNot(contains('(Weniger)')));
    });

    test('zwei bis acht Stände', () {
      expect(
        () => standvergleichDruck(daten(), {'v2'}),
        throwsA(isA<DruckNichtsGewaehlt>()),
      );
      final viele = StandvergleichDaten(
        name: 'Gartenwurst',
        staende: [
          for (var i = 1; i <= 9; i++)
            VergleichStand(
              version: bspVersion(nummer: i),
              eingabe: bspGartenwurst(stand: i > 3 ? 3 : i),
            ),
        ],
      );
      expect(
        () => standvergleichDruck(viele, {for (var i = 1; i <= 9; i++) 'v$i'}),
        throwsA(isA<DruckNichtsGewaehlt>()),
      );
      expect(
        standvergleichDruck(viele, {for (var i = 1; i <= 8; i++) 'v$i'}),
        isA<DruckDokument>(),
      );
    });

    test('Druckfenster: vorgewählt, was verglichen wurde — sonst die neuesten',
        () {
      Set<String> vorgewaehlt(Set<String> vorwahl) {
        final a = standvergleichDruckAuftrag(daten(), vorwahl: vorwahl);
        final o = a.optionen.first as DruckWahlMehrere;
        expect(o.schluessel, StandvergleichWahl.staende);
        expect(o.merken, isFalse);
        expect([for (final w in o.werte) w.wert], ['v1', 'v2', 'v3']);
        return o.standard;
      }

      expect(vorgewaehlt({'v1', 'v3'}), {'v1', 'v3'});
      expect(vorgewaehlt(const {}), {'v2', 'v3'});
      // Einer allein ist kein Vergleich — dann die beiden neuesten.
      expect(vorgewaehlt({'v1'}), {'v2', 'v3'});
      expect(vorgewaehlt({'v1', 'weg'}), {'v2', 'v3'});
    });
  });

  // ── Projektliste ────────────────────────────────────────────────────────

  group('Projektliste', () {
    ProjektlisteDaten daten({bool mitGesamt = true}) {
      final projekte = [
        for (final p in bspProjekte())
          if (mitGesamt || p.gesamtprojektId == null) p,
      ];
      return ProjektlisteDaten(
        projekte: projekte,
        gesamtprojekte: mitGesamt ? bspGesamtprojekte() : const [],
        checklisten: projektCheckStaende(
          projekte: projekte,
          rezepturen: const [],
          versionen: const [],
        ),
        offen: const {'p1': (offen: 2, ueberfaellig: 1)},
      );
    }

    Future<String> liste(ProjektlisteInhalt inhalt) => text(
          projektlisteDruck(daten(), inhalt: inhalt, gedrucktAm: gedruckt),
        );

    test('die aktiven: Gesamtprojekt mit Mustern, was als Nächstes kommt',
        () async {
      final t = await liste(const ProjektlisteInhalt());
      for (final wort in [
        '(Gartenwurst)',
        '(Bratwurst)',
        '(Leberkäse)',
        '(Grillsaison)',
        '(Kräuter)',
        '(Knoblauch)',
        '(Nächstes:)',
        '(überfällig)',
        '(Kantine)',
        '(Validierung)',
      ]) {
        expect(t, contains(wort), reason: wort);
      }
      // Ruhende fehlen — beim Gesamtprojekt steht, dass eins fehlt.
      for (final wort in ['(Sülze)', '(vegetarisch)', '(Chili)']) {
        expect(t, isNot(contains(wort)), reason: wort);
      }
      expect(t, contains('(gezeigt)'));
      // Die Produktidee nur auf Wunsch.
      expect(t, isNot(contains('(Feine)')));
    });

    test('alle, nach Kunde — ohne Kunde zuletzt, mit Produktidee', () async {
      final t = await liste(
        const ProjektlisteInhalt(
          filter: null,
          reihenfolge: ProjektReihenfolge.kunde,
          idee: true,
        ),
      );
      expect(t, contains('(Sülze)'));
      expect(t, contains('(Chili)'));
      expect(t, contains('(Feine)'));
      final reihe = [
        t.indexOf('(Beispiel-Feinkost)'),
        t.indexOf('(Hofladen)'),
        t.indexOf('(Kantine)'),
        t.indexOf('(Ohne)'),
      ];
      expect(reihe.every((i) => i >= 0), isTrue, reason: '$reihe');
      expect([...reihe]..sort(), reihe);
    });

    test('nach Name und mit Suche', () async {
      final t = await liste(
        const ProjektlisteInhalt(
          filter: null,
          suche: 'wurst',
          reihenfolge: ProjektReihenfolge.name,
        ),
      );
      expect(t, contains('(Bratwurst)'));
      expect(t, contains('(Gartenwurst)'));
      expect(t, isNot(contains('(Leberkäse)')));
      expect(t.indexOf('(Bratwurst)'), lessThan(t.indexOf('(Gartenwurst)')));
      // Die Suche steht im Kopf.
      expect(t, contains('("wurst")'));
    });

    test('nichts gefunden: ein Hinweis statt einer leeren Tabelle', () async {
      final t = await liste(const ProjektlisteInhalt(suche: 'gibt es nicht'));
      expect(t, contains('(Treffer.)'));
      expect(t, isNot(contains('(Checkliste)')));
    });

    test('Druckfenster: Filter und Suche wie die Liste', () {
      final a = projektlisteDruckAuftrag(
        daten(),
        filter: ProjektFilter.validierung,
        suche: 'Kn',
      );
      final filter = a.optionen.first as DruckWahlEins;
      expect(filter.standard, ProjektFilter.validierung.name);
      expect(filter.merken, isFalse);
      expect(
        [for (final w in filter.werte) w.wert],
        [...ProjektFilter.values.map((f) => f.name), ProjektlisteWahl.alle],
      );
      // Aktiv: zwei in Entwicklung, zwei in Validierung, eins in Produktion.
      expect(filter.werte.first.hinweis, '5 Projekte');
      final schluessel = {for (final o in a.optionen) o.schluessel};
      expect(schluessel, contains(ProjektlisteWahl.suche));
      expect(schluessel, contains(ProjektlisteWahl.muster));

      final ohne = projektlisteDruckAuftrag(daten(mitGesamt: false));
      final ohneSchluessel = {for (final o in ohne.optionen) o.schluessel};
      expect(ohneSchluessel, isNot(contains(ProjektlisteWahl.suche)));
      expect(ohneSchluessel, isNot(contains(ProjektlisteWahl.muster)));
      expect(
        (ohne.optionen.first as DruckWahlEins).standard,
        ProjektFilter.aktiv.name,
      );
    });
  });

  // ── Zutatenkatalog ──────────────────────────────────────────────────────

  group('Zutatenkatalog', () {
    Future<String> katalog(ZutatenkatalogInhalt inhalt) => text(
          zutatenkatalogDruck(
            bspKatalog(),
            inhalt: inhalt,
            gedrucktAm: gedruckt,
          ),
        );

    test('Art, Nährwerte und Umfang je Zutat', () {
      final z = {for (final x in bspKatalog()) x.id: x};
      expect(zutatArt(z['z-schwein']!), 'Fleisch (Schwein)');
      expect(zutatArt(z['z-wild']!), 'Fleisch');
      expect(zutatArt(z['z-eis']!), 'Wasser');
      expect(zutatArt(z['z-oel']!), '');
      // Wasser braucht keine Nährwerte.
      expect(zutatMitNaehrwerten(z['z-eis']!), isTrue);
      expect(zutatMitNaehrwerten(z['z-kraeuter']!), isFalse);
      expect(zutatImUmfang(z['z-milch']!, ZutatenUmfang.allergene), isTrue);
      expect(zutatImUmfang(z['z-oel']!, ZutatenUmfang.allergene), isFalse);
      expect(zutatImUmfang(z['z-wild']!, ZutatenUmfang.fleisch), isTrue);
      expect(zutatTrifft(z['z-eis']!, 'wasser'), isTrue);
      expect(zutatTrifft(z['z-nps']!, '9201'), isTrue);
      expect(zutatTrifft(z['z-nps']!, 'zucker'), isFalse);
    });

    test('alle mit Nährwerten — nach Name', () async {
      final t = await katalog(const ZutatenkatalogInhalt());
      for (final wort in [
        '(kcal)',
        '(BEFFE)',
        '(99,5)',
        '(14,5)',
        '(Etikett:)',
        '(Unterzutaten:)',
        '(Hilfsstoffe:)',
        '(Sellerie,)',
      ]) {
        expect(t, contains(wort), reason: wort);
      }
      expect(t.indexOf('(Magermilchpulver)'), lessThan(t.indexOf('(Rapsöl)')));
    });

    test('nur Fleisch, nur ohne Nährwerte, nur mit Allergenen', () async {
      final fleisch = await katalog(
        const ZutatenkatalogInhalt(umfang: ZutatenUmfang.fleisch),
      );
      expect(fleisch, contains('(Rückenspeck)'));
      expect(fleisch, contains('(Wildfleisch)'));
      expect(fleisch, isNot(contains('(Rapsöl)')));

      final ohne = await katalog(
        const ZutatenkatalogInhalt(umfang: ZutatenUmfang.ohneNaehrwerte),
      );
      expect(ohne, contains('(Petersilie,)'));
      expect(ohne, contains('(Wildfleisch)'));
      expect(ohne, isNot(contains('(Scherbeneis)')));
      expect(ohne, isNot(contains('(Rapsöl)')));

      final allergene = await katalog(
        const ZutatenkatalogInhalt(umfang: ZutatenUmfang.allergene),
      );
      expect(allergene, contains('(Magermilchpulver)'));
      expect(allergene, contains('(Würzmischung)'));
      expect(allergene, isNot(contains('(Rapsöl)')));
    });

    test('nach Art: Fleisch je Tierart, Wasser, die übrigen', () async {
      final t = await katalog(
        const ZutatenkatalogInhalt(nachArt: true, naehrwerte: false),
      );
      final reihe = [
        t.indexOf('(Fleisch:)'),
        t.indexOf('(Tierart)'),
        t.indexOf('(Wasser)'),
        t.indexOf('(Übrige)'),
      ];
      expect(reihe.every((i) => i >= 0), isTrue, reason: '$reihe');
      expect([...reihe]..sort(), reihe);
      // Ohne Nährwerte als Spalten steht da, ob sie fehlen.
      expect(t, contains('(fehlen)'));
      expect(t, isNot(contains('(kcal)')));
    });

    test('mit Suche — und ein Hinweis, wenn nichts passt', () async {
      final t = await katalog(const ZutatenkatalogInhalt(suche: 'fleisch'));
      expect(t, contains('(Schweinefleisch)'));
      expect(t, contains('(Wildfleisch)'));
      expect(t, isNot(contains('(Rapsöl)')));
      expect(t, contains('("fleisch")'));

      final leer = await katalog(const ZutatenkatalogInhalt(suche: 'xyz'));
      expect(leer, contains('(Treffer.)'));
    });

    test('Druckfenster: Suche nur, wenn gesucht wird — Anzahl je Umfang', () {
      final a = zutatenkatalogDruckAuftrag(bspKatalog(), suche: 'fleisch');
      final schluessel = [for (final o in a.optionen) o.schluessel];
      expect(schluessel.first, ZutatenkatalogWahl.suche);
      final umfang = a.optionen.firstWhere(
        (o) => o.schluessel == ZutatenkatalogWahl.umfang,
      ) as DruckWahlEins;
      expect(
        [for (final w in umfang.werte) w.hinweis],
        ['11 Zutaten', '4 Zutaten', '2 Zutaten', '2 Zutaten'],
      );
      final ohne = zutatenkatalogDruckAuftrag(bspKatalog());
      expect(
        [for (final o in ohne.optionen) o.schluessel],
        isNot(contains(ZutatenkatalogWahl.suche)),
      );
    });
  });

  // ── Laden aus der Datenbank ─────────────────────────────────────────────

  group('Laden', () {
    late AppDatabase db;
    late EntwicklungRepository repo;
    late ProjektRepository projekte;

    setUp(() {
      db = testDatenbank();
      repo = EntwicklungRepository(db);
      projekte = ProjektRepository(db);
    });
    tearDown(() => db.close());

    test('Rezepturblatt und Vergleich aus der Datenbank', () async {
      final projektId = await projekte.projektAnlegen(name: 'Gartenwurst');
      final schwein = await repo.zutatAnlegen(
        const EntwicklungZutatenCompanion(
          name: Value('Schweinefleisch S III'),
          istFleisch: Value(true),
          tierart: Value('schwein'),
          fett: Value(22),
          eiweiss: Value(17),
        ),
      );
      final salz = await repo.zutatAnlegen(
        const EntwicklungZutatenCompanion(
          name: Value('Speisesalz'),
          salz: Value(100),
        ),
      );
      final rezepturId = await repo.rezepturAnlegen(
        name: 'Gartenwurst',
        artikelnummer: '40711',
        projektId: projektId,
      );
      final v1 = (await repo.neuesteVersion(rezepturId))!;
      await repo.positionHinzufuegen(v1.id, zutatId: schwein, mengeKg: 98);
      await repo.positionHinzufuegen(v1.id, zutatId: salz, mengeKg: 2);
      await repo.versionAbschliessen(v1.id, grund: 'Erster Stand');
      final v2 = await repo.versionAnlegen(rezepturId, vorlageId: v1.id);
      await (db.update(db.entwicklungProjekte)
            ..where((p) => p.id.equals(projektId)))
          .write(EntwicklungProjekteCompanion(freigabeVersionId: Value(v1.id)));

      final blatt = (await rezepturblattLaden(repo, projekte, v1.id))!;
      expect(blatt.name, 'Gartenwurst');
      expect(blatt.artikelnummer, '40711');
      expect(blatt.version.nummer, 1);
      expect(blatt.freigegeben, isTrue);
      expect(blatt.eingabe.positionen, hasLength(2));
      // Der Entwurf ist nicht freigegeben.
      final entwurf = (await rezepturblattLaden(repo, projekte, v2))!;
      expect(entwurf.freigegeben, isFalse);
      expect(entwurf.version.status, VersionStatus.entwurf);
      expect(await rezepturblattLaden(repo, projekte, 'weg'), isNull);

      final vergleich =
          (await standvergleichLaden(repo, projekte, rezepturId))!;
      expect(vergleich.freigabeVersionId, v1.id);
      expect(
        [for (final s in vergleich.staende) s.version.nummer],
        [2, 1],
      );
      expect(await standvergleichLaden(repo, projekte, 'weg'), isNull);
    });
  });
}

extension on String {
  /// Wie oft dieser Text in [t] vorkommt.
  int allMatchesIn(String t) =>
      RegExp(RegExp.escape(this)).allMatches(t).length;
}
