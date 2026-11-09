import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/features/entwicklung/bericht/bericht_pdf.dart';
import 'package:produktion_planer/features/entwicklung/bericht/projekt_bericht.dart';
import 'package:produktion_planer/features/entwicklung/daten/dateien.dart';
import 'package:produktion_planer/features/entwicklung/entwicklung_zugang.dart';
import 'package:produktion_planer/features/entwicklung/haccp/haccp_ansicht.dart';
import 'package:produktion_planer/features/entwicklung/haccp/haccp_modell.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_repository.dart';

import 'helpers/pdf_lesen.dart';
import 'helpers/test_db.dart';

/// „Nichts Neues" bei HACCP: Bringt ein Projekt keinen neuen Prozess mit,
/// gilt das bestehende HACCP-Konzept — Gefahrenanalyse und Lenkungspunkte
/// entfallen. In der App ausgegraut, im Projektbericht auf Seite 1 bei
/// HACCP genannt und im Kapitel Herstellung ausgegraut. Alles erfunden.
void main() {
  const erfasst = Haccp(
    gefahren: [
      Gefahr(
        id: 'g1',
        gefahr: 'Metallteile',
        schwere: 3,
        wahrscheinlichkeit: 2,
        massnahmen: 'Metalldetektor',
      ),
    ],
    lenkungspunkte: [
      Lenkungspunkt(
        id: 'l1',
        schritt: 'Metalldetektion',
        antworten: {'f1': true, 'f2': true},
        ergebnis: Lenkungsart.ccp,
        lenkung: 'Prüfkörper je Schicht',
      ),
    ],
  );

  group('Modell', () {
    test('gespeichert und gelesen — auch ohne Einträge', () {
      // Nichts erfasst, nichts abgehakt: nichts zu speichern.
      expect(const Haccp().alsJson(), isNull);

      final nurHaken = const Haccp(nichtsNeues: true).alsJson();
      expect(nurHaken, isNotNull);
      final gelesen = Haccp.aus(nurHaken);
      expect(gelesen.nichtsNeues, isTrue);
      expect(gelesen.leer, isTrue);

      // Erfasstes bleibt mit dem Haken erhalten.
      final mit = Haccp.aus(erfasst.kopie(nichtsNeues: true).alsJson());
      expect(mit.nichtsNeues, isTrue);
      expect(mit.gefahren.single.gefahr, 'Metallteile');
      expect(mit.lenkungspunkte.single.ergebnis, Lenkungsart.ccp);

      // Zurückgenommen steht der Haken nicht mehr im JSON.
      final ohne = mit.kopie(nichtsNeues: false).alsJson()!;
      expect(jsonDecode(ohne), isNot(contains('nichtsNeues')));
      expect(Haccp.aus(ohne).gefahren, hasLength(1));
      expect(const Haccp(nichtsNeues: true).kopie().nichtsNeues, isTrue);
    });

    test('ältere Daten ohne den Haken — und Unlesbares — gelten als offen', () {
      expect(Haccp.aus(erfasst.alsJson()).nichtsNeues, isFalse);
      expect(Haccp.aus('{"nichtsNeues": "ja"}').nichtsNeues, isFalse);
      expect(Haccp.aus('{"nichtsNeues": 1}').nichtsNeues, isFalse);
      expect(Haccp.aus('kein JSON').nichtsNeues, isFalse);
      expect(Haccp.aus(null).nichtsNeues, isFalse);
    });
  });

  group('mit „Neuer Prozess" in der Übersicht', () {
    final zeit = DateTime(2026, 11, 9);
    EntwicklungsProjekt projekt({
      required bool neuerProzess,
      required Haccp haccp,
    }) =>
        EntwicklungsProjekt(
          id: 'p1',
          name: 'Testart',
          status: 'entwicklung',
          neuerProzess: neuerProzess,
          neueZutaten: false,
          haccp: haccp.alsJson(),
          createdAt: zeit,
          updatedAt: zeit,
        );

    test('„Nichts Neues" anhaken nimmt „Neuer Prozess" zurück', () {
      final d = nichtsNeuesSetzen(
        projekt(neuerProzess: true, haccp: erfasst),
        true,
      );
      expect(d.neuerProzess, const Value(false));
      final h = Haccp.aus(d.haccp.value);
      expect(h.nichtsNeues, isTrue);
      expect(h.gefahren, hasLength(1));

      // Ohne „Neuer Prozess" bleibt der unberührt.
      final ohne = nichtsNeuesSetzen(
        projekt(neuerProzess: false, haccp: const Haccp()),
        true,
      );
      expect(ohne.neuerProzess.present, isFalse);
      expect(Haccp.aus(ohne.haccp.value).nichtsNeues, isTrue);

      // Zurücknehmen setzt „Neuer Prozess" nicht wieder.
      final zurueck = nichtsNeuesSetzen(
        projekt(
          neuerProzess: false,
          haccp: erfasst.kopie(nichtsNeues: true),
        ),
        false,
      );
      expect(zurueck.neuerProzess.present, isFalse);
      expect(Haccp.aus(zurueck.haccp.value).nichtsNeues, isFalse);
      expect(Haccp.aus(zurueck.haccp.value).gefahren, hasLength(1));
    });

    test('„Neuer Prozess" anhaken nimmt „Nichts Neues" zurück', () {
      final d = neuerProzessSetzen(
        projekt(
          neuerProzess: false,
          haccp: erfasst.kopie(nichtsNeues: true),
        ),
        true,
      );
      expect(d.neuerProzess, const Value(true));
      final h = Haccp.aus(d.haccp.value);
      expect(h.nichtsNeues, isFalse);
      expect(h.lenkungspunkte, hasLength(1));

      // Sonst bleibt HACCP unberührt.
      for (final (neu, haccp) in [
        (true, erfasst),
        (false, erfasst.kopie(nichtsNeues: true)),
      ]) {
        final x = neuerProzessSetzen(
          projekt(neuerProzess: !neu, haccp: haccp),
          neu,
        );
        expect(x.neuerProzess, Value(neu));
        expect(x.haccp.present, isFalse, reason: 'neuer Prozess: $neu');
      }
    });
  });

  group('im Projektbericht', () {
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

    /// Die Seiten des Berichts zu Projekt [id], unkomprimiert als Text.
    Future<List<String>> seiten(String id) async {
      final b = await berichtLaden(db, dateien, (await projekte.projekt(id))!);
      return pdfSeiten(
        latin1.decode(
          await baueProjektPdf(
            b,
            gedrucktAm: DateTime(2026, 11, 9),
            komprimiert: false,
          ),
        ),
      );
    }

    /// Die Seite mit HACCP im Kapitel Herstellung.
    String herstellung(List<String> s) =>
        s.singleWhere((x) => seitenText(x).contains('HACCP-Gefahrenanalyse'));

    /// In welcher Farbe [wort] auf [seite] steht — „r g b" wie im PDF.
    String? farbe(String seite, String wort) => RegExp(
          r'([\d.]+ [\d.]+ [\d.]+) rg BT [^\[]*\[\(' +
              RegExp.escape(wort) +
              r'\)\]TJ',
        ).firstMatch(seite)?[1];
    const hellgrau = '0.60392 0.63137 0.66275'; // #9AA1A9
    const akzent = '0.12157 0.30588 0.47451'; // #1F4E79

    test('angehakt: Seite 1 sagt es bei HACCP, das Kapitel ist ausgegraut',
        () async {
      final id = await projekte.projektAnlegen(name: 'Haken Testart');
      // Erfasstes bleibt in der App — im Bericht steht es nicht.
      await projekte.projektAendern(
        id,
        EntwicklungProjekteCompanion(
          haccp: Value(erfasst.kopie(nichtsNeues: true).alsJson()),
        ),
      );
      final s = await seiten(id);
      expect(
        seitenText(s.first),
        contains(
          'HACCP Nichts Neues Keine neuen Prozesse Es gilt das bestehende '
          'HACCP-Konzept',
        ),
      );

      final kapitel = herstellung(s);
      final text = seitenText(kapitel);
      expect(text, contains('HACCP-Gefahrenanalyse entfällt'));
      expect(text, contains('Lenkungspunkte entfällt'));
      expect(
        text,
        contains(
          'Nichts Neues: keine neuen Prozesse - es gilt das bestehende '
          'HACCP-Konzept. Gefahrenanalyse und Lenkungspunkte sind nicht '
          'auszufüllen.',
        ),
      );
      // Die Spalten stehen da, aber grau — und ohne Einträge.
      for (final wort in [
        'HACCP-Gefahrenanalyse',
        'Lenkungspunkte',
        'Gefahr',
        'Maßnahmen',
        'Entscheidungsbaum',
      ]) {
        expect(farbe(kapitel, wort), hellgrau, reason: wort);
      }
      final alles = s.map(seitenText).join(' ');
      expect(alles, isNot(contains('Metallteile')));
      expect(alles, isNot(contains('Metalldetektion')));
      expect(alles, isNot(contains('Noch keine Gefahren bewertet')));
    });

    test('ohne Haken wie bisher: Einträge in Farbe, nichts entfällt', () async {
      final id = await projekte.projektAnlegen(name: 'Offen Testart');
      await projekte.projektAendern(
        id,
        EntwicklungProjekteCompanion(haccp: Value(erfasst.alsJson())),
      );
      final s = await seiten(id);
      expect(
        seitenText(s.first),
        contains('HACCP 1 Gefahr 1 Lenkungspunkte, davon 1 CCP'),
      );
      final kapitel = herstellung(s);
      final text = seitenText(kapitel);
      expect(text, contains('Metallteile'));
      expect(text, contains('Metalldetektion'));
      expect(text, isNot(contains('entfällt')));
      expect(text, isNot(contains('Nichts Neues')));
      expect(farbe(kapitel, 'HACCP-Gefahrenanalyse'), akzent);
      expect(farbe(kapitel, 'Lenkungspunkte'), akzent);
    });

    test('der Haken in der Datenbank — hin und zurück', () async {
      final id = await projekte.projektAnlegen(name: 'Hin Testart');
      await projekte.projektAendern(
        id,
        EntwicklungProjekteCompanion(
          neuerProzess: const Value(true),
          haccp: Value(erfasst.alsJson()),
        ),
      );
      var p = (await projekte.projekt(id))!;
      await projekte.projektAendern(id, nichtsNeuesSetzen(p, true));
      p = (await projekte.projekt(id))!;
      expect(p.neuerProzess, isFalse);
      expect(Haccp.aus(p.haccp).nichtsNeues, isTrue);
      expect(Haccp.aus(p.haccp).gefahren, hasLength(1));

      await projekte.projektAendern(id, neuerProzessSetzen(p, true));
      p = (await projekte.projekt(id))!;
      expect(p.neuerProzess, isTrue);
      expect(Haccp.aus(p.haccp).nichtsNeues, isFalse);
      expect(Haccp.aus(p.haccp).gefahren, hasLength(1));
    });
  });

  test('die Vorlage sagt, wie es mit dem Haken aussieht', () async {
    final text = pdfSeiten(
      latin1.decode(
        await baueVorlagePdf(
          gedrucktAm: DateTime(2026, 11, 9),
          komprimiert: false,
        ),
      ),
    ).map(seitenText).join(' ');
    expect(text, contains('oder "Nichts Neues", wenn angehakt'));
    expect(
      text,
      contains(
        'stehen Gefahrenanalyse und Lenkungspunkte ausgegraut da, ohne '
        'Einträge.',
      ),
    );
  });
}
