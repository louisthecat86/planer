import 'dart:convert';

// `show Value`: drift bringt eine eigene Klasse `Column` mit.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/providers/database_provider.dart';
import 'package:produktion_planer/features/entwicklung/daten/entwicklung_repository.dart';
import 'package:produktion_planer/features/entwicklung/etikett/etikett.dart';
import 'package:produktion_planer/features/entwicklung/etikett/etikett_dienst.dart';
import 'package:produktion_planer/features/entwicklung/etikett/etikett_pdf.dart';
import 'package:produktion_planer/features/entwicklung/projekte/entwicklungsstrang.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_modell.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_repository.dart';
import 'package:produktion_planer/features/entwicklung/rechenkern/rechen_modell.dart';
import 'package:produktion_planer/features/entwicklung/rechenkern/rechenkern.dart';
import 'package:produktion_planer/features/entwicklung/rezepturen/stand_vergleich.dart';
import 'package:produktion_planer/features/entwicklung/spezifikation/spez_angaben.dart';

import 'helpers/test_db.dart';

/// Tests für den Entwicklungsstrang: was sich von Stand zu Stand ändert,
/// Phasen aus Statuswechseln, Stationen und was zu ihnen gehört, das
/// Etikett je Stand — rein und mit der Datenbank. Alles erfunden.
void main() {
  RechenZutat zutat(
    String name, {
    bool fleisch = false,
    Set<String> allergene = const {},
    Naehrwerte naehrwerte = Naehrwerte.leer,
  }) =>
      RechenZutat(
        id: name,
        name: name,
        istFleisch: fleisch,
        tierart: fleisch ? Tierart.schwein : null,
        allergene: allergene,
        naehrwerte: naehrwerte,
      );

  final schwein = zutat(
    'Schweinefleisch',
    fleisch: true,
    naehrwerte: const Naehrwerte(fett: 20, eiweiss: 18),
  );
  final salz = zutat('Speisesalz', naehrwerte: const Naehrwerte(salz: 100));
  final senf = zutat(
    'Senf',
    allergene: {'senf'},
    naehrwerte: const Naehrwerte(fett: 10, eiweiss: 6, kohlenhydrate: 6),
  );
  final paprika = zutat('Paprika');
  final mehl = zutat(
    'Weizenmehl',
    allergene: {'gluten'},
    naehrwerte: const Naehrwerte(kohlenhydrate: 70, eiweiss: 10),
  );

  RechenRezeptur rezeptur(
    List<(RechenZutat, double)> zeilen, {
    double verlust = 10,
    Verlustart art = Verlustart.garen,
  }) =>
      RechenRezeptur(
        id: 'r',
        name: 'Testware',
        verlustProzent: verlust,
        verlustart: art,
        positionen: [
          for (final (z, kg) in zeilen) RechenPosition.zutat(z, mengeKg: kg),
        ],
      );

  group('Was sich von Stand zu Stand ändert', () {
    test('der erste Stand: Endgewicht, Zeilen, Fleischanteil', () {
      final a = standAenderungen(
        null,
        rezeptur([(schwein, 9), (salz, 1)]),
      );
      expect(a[0], 'Endgewicht 9 kg aus 10 kg');
      expect(a[1], '2 Zeilen');
      expect(a[2], startsWith('Fleischanteil '));
      expect(
        standAenderungen(null, rezeptur([(salz, 1)])),
        ['Endgewicht 0,9 kg aus 1 kg', '1 Zeile'],
      );
    });

    test('Zeilen, Verlust, Nährwerte, Allergene, Mengenangabe', () {
      final vorher = rezeptur([(schwein, 9), (salz, 0.2), (paprika, 0.3)]);
      final nachher = rezeptur(
        [(schwein, 8), (salz, 0.2), (senf, 0.5)],
        verlust: 12,
      );
      final a = standAenderungen(vorher, nachher, vorherNummer: 1);
      expect(
        a,
        containsAll([
          'Schweinefleisch: 9 → 8 kg',
          'Entfernt: Paprika',
          'Neu: Senf (0,5 kg)',
          'Verlust: 10,0 % → 12,0 %',
          'Allergen neu: Senf',
          'Zutatenliste geändert',
        ]),
      );
      // Unverändertes wird nicht genannt.
      expect(a.any((s) => s.startsWith('Speisesalz')), isFalse);
      // Die Nährwerte, wie sie auf dem Etikett stehen.
      final ea = berechne(vorher);
      final eb = berechne(nachher);
      expect(ea.je100g.fett, isNot(eb.je100g.fett));
      expect(a.any((s) => s.startsWith('Fett je 100 g: ')), isTrue);
      // Die Mengenangabe des Fleischs.
      expect(a.any((s) => s.startsWith('QUID Schweinefleisch: ')), isTrue);

      // Rückwärts: das Allergen fällt weg.
      expect(
        standAenderungen(nachher, vorher),
        contains('Allergen entfällt: Senf'),
      );
    });

    test('Verlustart und Fleischanteil', () {
      final a = standAenderungen(
        rezeptur([(schwein, 5), (mehl, 5)], art: Verlustart.trocknung),
        rezeptur([(schwein, 6), (mehl, 4)]),
      );
      expect(a, contains('Verlustart: Trocknung → Garen'));
      expect(a.any((s) => s.startsWith('Fleischanteil: ')), isTrue);
    });

    test('nichts geändert', () {
      final r = rezeptur([(schwein, 9), (salz, 1)]);
      expect(
        standAenderungen(r, r, vorherNummer: 3),
        ['Keine Änderung zu Stand 3'],
      );
      expect(standAenderungen(r, r), ['Keine Änderung zum vorigen Stand']);
    });

    test('viele Zeilen: einzeln genannt bis zur Grenze', () {
      final neu = [
        for (var i = 1; i <= kStandZeilenEinzeln + 3; i++)
          (zutat('Gewürz $i'), 0.1),
      ];
      final a = standAenderungen(
        rezeptur([(schwein, 9)]),
        rezeptur([(schwein, 9), ...neu]),
      );
      expect(a.where((s) => s.startsWith('Neu: ')), hasLength(8));
      expect(a, contains('und 3 weitere Zeilen geändert'));
    });
  });

  // ── Einträge von Hand ───────────────────────────────────────────────

  final zeit = DateTime(2026, 3, 1);
  var zaehler = 0;
  ProjektEintrag eintrag(
    String id,
    EintragArt art, {
    required int tag,
    String? versionId,
    String? wert,
    String? titel,
  }) =>
      ProjektEintrag(
        id: id,
        projektId: 'p1',
        art: art.schluessel,
        titel: titel ?? id,
        datum: zeit.add(Duration(days: tag)),
        status: EintragStatus.erledigt.schluessel,
        versionId: versionId,
        wert: wert,
        createdAt: zeit.add(Duration(minutes: zaehler++)),
        updatedAt: zeit,
      );

  group('Phasen', () {
    test('wieder aufnehmen: in der Phase vor dem Archiv', () {
      // Ohne Statuswechsel im Verlauf: die Entwicklung.
      expect(phaseVorDemArchiv(const []), ProjektStatus.entwicklung);
      expect(
        phaseVorDemArchiv([eintrag('n', EintragArt.notiz, tag: 1)]),
        ProjektStatus.entwicklung,
      );
      final verlauf = [
        eintrag(
          'a',
          EintragArt.meilenstein,
          tag: 1,
          wert: 'status:entwicklung>validierung',
        ),
        eintrag(
          'c',
          EintragArt.meilenstein,
          tag: 5,
          wert: 'status:produktion>archiviert',
        ),
        eintrag(
          'b',
          EintragArt.meilenstein,
          tag: 3,
          wert: 'status:validierung>produktion',
        ),
      ];
      // Der letzte Wechsel ins Archiv zählt — egal, in welcher Reihenfolge
      // die Einträge kommen.
      expect(phaseVorDemArchiv(verlauf), ProjektStatus.produktion);
      expect(
        phaseVorDemArchiv([
          ...verlauf,
          eintrag(
            'd',
            EintragArt.meilenstein,
            tag: 6,
            wert: 'status:archiviert>validierung',
          ),
          eintrag(
            'e',
            EintragArt.meilenstein,
            tag: 8,
            wert: 'status:validierung>archiviert',
          ),
        ]),
        ProjektStatus.validierung,
      );
      // Ein Wechsel ohne alten Status: die Entwicklung.
      expect(
        phaseVorDemArchiv([
          eintrag('x', EintragArt.meilenstein, tag: 1, wert: 'status:archiviert'),
        ]),
        ProjektStatus.entwicklung,
      );
    });

    test('Statuswechsel festhalten und lesen', () {
      expect(
        statusWert(ProjektStatus.entwicklung, ProjektStatus.validierung),
        'status:entwicklung>validierung',
      );
      final e = eintrag(
        'w',
        EintragArt.meilenstein,
        tag: 1,
        wert: 'status:entwicklung>validierung',
      );
      expect(
        statusWechsel(e),
        (alt: ProjektStatus.entwicklung, neu: ProjektStatus.validierung),
      );
      // Ein Wert ohne den alten Status.
      expect(
        statusWechsel(
          eintrag('x', EintragArt.meilenstein, tag: 1, wert: 'status:produktion'),
        ),
        (alt: null, neu: ProjektStatus.produktion),
      );
      // Andere Einträge sind kein Wechsel.
      expect(statusWechsel(eintrag('n', EintragArt.notiz, tag: 1)), isNull);
      expect(
        statusWechsel(
          eintrag('p', EintragArt.notiz, tag: 1, wert: 'status:produktion'),
        ),
        isNull,
      );
      expect(
        statusMeilensteinTitel(ProjektStatus.validierung),
        'Validierung begonnen',
      );
    });

    test('der Status je Eintrag und die Abschnitte des Bands', () {
      final liste = [
        eintrag('a', EintragArt.meilenstein, tag: 0),
        eintrag('b', EintragArt.notiz, tag: 2),
        eintrag(
          'c',
          EintragArt.meilenstein,
          tag: 3,
          wert: 'status:entwicklung>validierung',
        ),
        eintrag('d', EintragArt.email, tag: 4),
        eintrag(
          'e',
          EintragArt.meilenstein,
          tag: 6,
          wert: 'status:validierung>produktion',
        ),
      ];
      final phasen = statusJeEintrag(liste.reversed, ProjektStatus.produktion);
      expect(phasen, {
        'a': ProjektStatus.entwicklung,
        'b': ProjektStatus.entwicklung,
        'c': ProjektStatus.validierung,
        'd': ProjektStatus.validierung,
        'e': ProjektStatus.produktion,
      });
      expect(phasenAbschnitte(liste, phasen), [
        (von: 0, bis: 1, status: ProjektStatus.entwicklung),
        (von: 2, bis: 3, status: ProjektStatus.validierung),
        (von: 4, bis: 4, status: ProjektStatus.produktion),
      ]);
      // Gefiltert (ohne Meilensteine): die Phasen bleiben, wo sie waren.
      final ohne = [liste[1], liste[3]];
      expect(phasenAbschnitte(ohne, phasen), [
        (von: 0, bis: 0, status: ProjektStatus.entwicklung),
        (von: 1, bis: 1, status: ProjektStatus.validierung),
      ]);
      // Ohne Wechsel: in der Entwicklung durchweg sie …
      expect(
        statusJeEintrag(liste.take(2), ProjektStatus.entwicklung)
            .values
            .toSet(),
        {ProjektStatus.entwicklung},
      );
      // … sonst ist unbekannt, seit wann das Projekt so steht: kein Band.
      final ohneWechsel = statusJeEintrag(
        liste.take(2),
        ProjektStatus.validierung,
      );
      expect(ohneWechsel, isEmpty);
      expect(phasenAbschnitte(liste.take(2).toList(), ohneWechsel), isEmpty);
      // Geht der erste Wechsel nicht von der Entwicklung aus, fehlt die
      // Phase der Einträge davor.
      final spaet = liste.skip(3).toList();
      final teil = statusJeEintrag(spaet, ProjektStatus.produktion);
      expect(teil, {'e': ProjektStatus.produktion});
      expect(phasenAbschnitte(spaet, teil), [
        (von: 1, bis: 1, status: ProjektStatus.produktion),
      ]);
    });
  });

  group('Stationen', () {
    test('der Weg: Anfang, Stationen mit Rückmeldungen, Phasenwechsel', () {
      final liste = [
        eintrag('angelegt', EintragArt.meilenstein, tag: 0),
        eintrag('anfrage', EintragArt.email, tag: 1),
        eintrag('s1', EintragArt.rezeptur, tag: 5, versionId: 'v1'),
        eintrag('rueck1', EintragArt.email, tag: 7),
        eintrag(
          'validierung',
          EintragArt.meilenstein,
          tag: 8,
          wert: 'status:entwicklung>validierung',
        ),
        eintrag('s2', EintragArt.rezeptur, tag: 10, versionId: 'v2'),
        // Später, aber ausdrücklich zu Stand 1.
        eintrag('zu1', EintragArt.notiz, tag: 11, versionId: 'v1'),
        eintrag('spez', EintragArt.datei, tag: 12, versionId: 'v2'),
        // Zu einem Entwurf — der noch keine Station ist.
        eintrag('entwurf', EintragArt.notiz, tag: 13, versionId: 'v3'),
      ];
      final weg = entwicklungsweg(liste.reversed);
      expect(weg, hasLength(4));
      final anfang = weg[0] as WegAnfang;
      expect([for (final e in anfang.eintraege) e.id], ['angelegt', 'anfrage']);
      final s1 = weg[1] as WegStation;
      expect(s1.nummer, 1);
      expect(s1.versionId, 'v1');
      expect([for (final e in s1.rueckmeldungen) e.id], ['rueck1', 'zu1']);
      final phase = weg[2] as WegPhase;
      expect(phase.status, ProjektStatus.validierung);
      final s2 = weg[3] as WegStation;
      expect(s2.nummer, 2);
      expect([for (final e in s2.rueckmeldungen) e.id], ['spez', 'entwurf']);
    });

    test('ohne Stand: alles am Anfang', () {
      final weg = entwicklungsweg([
        eintrag('angelegt', EintragArt.meilenstein, tag: 0),
        eintrag('notiz', EintragArt.notiz, tag: 1, versionId: 'v9'),
      ]);
      expect(weg, hasLength(1));
      expect((weg.single as WegAnfang).eintraege, hasLength(2));
    });

    test('Stände zur Auswahl', () {
      Rezeptur r(String id, String name) => Rezeptur(
            id: id,
            name: name,
            createdAt: zeit,
            updatedAt: zeit,
          );
      RezepturVersion v(
        String id,
        String rezepturId,
        int nummer, {
        String status = VersionStatus.abgeschlossen,
        String? bezeichnung,
      }) =>
          RezepturVersion(
            id: id,
            rezepturId: rezepturId,
            nummer: nummer,
            bezeichnung: bezeichnung,
            status: status,
            verlustProzent: 0,
            fettVerlustProzent: 0,
            verlustArt: 'garen',
            createdAt: zeit,
            updatedAt: zeit,
          );
      final wahl = standWahlen(
        [r('r2', 'Marinade'), r('r1', 'Frikadelle')],
        [
          v('a', 'r1', 1),
          v('b', 'r1', 2, bezeichnung: 'Muster für den Kunden'),
          v('c', 'r1', 3, status: VersionStatus.entwurf),
          v('d', 'r2', 1),
          v('x', 'r9', 1),
        ],
      );
      expect([for (final w in wahl) w.label], [
        'Frikadelle · Stand 3 (Entwurf)',
        'Frikadelle · Stand 2 · Muster für den Kunden',
        'Frikadelle · Stand 1',
        'Marinade · Stand 1',
      ]);
      expect(wahl.first.versionId, 'c');
    });

    test('Kennzahlen mit ihrer Veränderung', () {
      final alt = berechne(rezeptur([(schwein, 9), (salz, 0.2)]));
      final neu = berechne(rezeptur([(schwein, 8), (salz, 0.2), (senf, 1)]));
      final k = wegKennzahlen(neu, vorher: alt);
      expect([for (final x in k) x.label], [
        'Fleischanteil',
        'Energie',
        'Fett',
        'Eiweiß',
        'Salz',
      ]);
      expect(k.first.aenderung, startsWith('−'));
      expect(k[2].wert, endsWith(' g'));
      // Ohne vorigen Stand keine Veränderung.
      expect(wegKennzahlen(neu).every((x) => x.aenderung == null), isTrue);
      // Gleich gerundet: keine Veränderung.
      expect(
        wegKennzahlen(alt, vorher: alt).every((x) => x.aenderung == null),
        isTrue,
      );
    });
  });

  group('Etikett', () {
    test('aus Ergebnis, Spezifikation und Sensorik', () {
      final ergebnis = berechne(
        rezeptur([(schwein, 8), (mehl, 1), (salz, 0.2)]),
      );
      final e = etikettAus(
        bezeichnung: ' Frikadelle Testart ',
        ergebnis: ergebnis,
        angaben: const SpezAngaben(
          lagerung: 'gekühlt bei +2 °C bis +7 °C',
          hinweise: 'Vor dem Verzehr vollständig durcherhitzen.',
          spuren: {'senf', 'sellerie', 'gluten'},
          verpackung: Verpackung(atmosphaere: 'schutzgas', einzelNetto: '500 g'),
        ),
        sensorik: const Sensorik(zubereitung: 'In der Pfanne braten.'),
        stand: 'Frikadelle · Stand 2',
      );
      expect(e.bezeichnung, 'Frikadelle Testart');
      expect(e.zutatenliste, ergebnis.zutatenliste);
      expect(e.zutatenliste, contains('WEIZENmehl'));
      expect(e.allergene, ['Gluten']);
      // Gluten ist enthalten — dann keine Spur. Reihenfolge der Planung.
      expect(e.spuren, ['Sellerie', 'Senf']);
      expect(e.spurenSatz, 'Kann Spuren von Sellerie und Senf enthalten.');
      expect(e.naehrwerte.first.label, 'Energie');
      expect(e.naehrwerte.first.wert, matches(RegExp(r'^\d+ kJ / \d+ kcal$')));
      expect([for (final n in e.naehrwerte) n.davon], [
        false,
        false,
        true,
        false,
        true,
        false,
        false,
      ]);
      expect(e.schutzgas, isTrue);
      expect(e.nettofuellmenge, '500 g');
      expect(e.fehlt, isEmpty);

      final text = etikettText(e);
      expect(text, startsWith('Frikadelle Testart\n\nZutaten: '));
      expect(text, contains('Kann Spuren von Sellerie und Senf enthalten.'));
      expect(text, contains('Durchschnittliche Nährwerte je 100 g:\nEnergie '));
      expect(text, contains('\n- davon Zucker '));
      expect(text, contains('Lagerung: gekühlt bei +2 °C bis +7 °C'));
      expect(text, contains('Zubereitung: In der Pfanne braten.'));
      expect(text, contains('Vor dem Verzehr vollständig durcherhitzen.'));
      expect(text, contains('Unter Schutzatmosphäre verpackt.'));
      expect(text, endsWith('Nettofüllmenge: 500 g'));
    });

    test('was noch fehlt', () {
      final e = etikettAus(
        bezeichnung: 'Testware',
        ergebnis: berechne(rezeptur([(schwein, 9), (paprika, 1)])),
      );
      expect(e.spurenSatz, isEmpty);
      expect(e.fehlt, [
        'Lagerbedingungen (Reiter „Spezifikation")',
        'Nettofüllmenge (Reiter „Spezifikation", Verpackung)',
        'Nährwerte für Paprika — die Tabelle ist sonst zu niedrig',
      ]);
      expect(etikettText(e), isNot(contains('Nettofüllmenge')));
      expect(aufzaehlung(const []), '');
      expect(aufzaehlung(const ['A']), 'A');
      expect(aufzaehlung(const ['A', 'B', 'C']), 'A, B und C');
    });

    test('der PDF-Entwurf', () async {
      final e = etikettAus(
        bezeichnung: 'Testware „mild"',
        ergebnis: berechne(rezeptur([(schwein, 9), (salz, 0.2)])),
      );
      final pdf = await baueEtikettPdf(e, erstellt: DateTime(2026, 3, 5));
      expect(ascii.decode(pdf.sublist(0, 5)), '%PDF-');
      expect(pdf.length, greaterThan(1000));
    });
  });

  group('Mit der Datenbank', () {
    late AppDatabase db;
    late EntwicklungRepository rezepte;
    late ProjektRepository projekte;

    setUp(() {
      db = testDatenbank();
      rezepte = EntwicklungRepository(db);
      projekte = ProjektRepository(db);
    });
    tearDown(() => db.close());

    Future<({String projekt, String rezeptur, String fleisch, String senf})>
        anlegen() async {
      final projekt = await projekte.projektAnlegen(
        name: 'Frikadelle Testart',
        jetzt: DateTime(2026, 3, 1, 9),
      );
      final rezeptur = await rezepte.rezepturAnlegen(
        name: 'Frikadelle',
        projektId: projekt,
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
      final senf = await rezepte.zutatAnlegen(
        const EntwicklungZutatenCompanion(
          name: Value('Senf'),
          allergene: Value('senf'),
          fett: Value(10),
        ),
      );
      return (
        projekt: projekt,
        rezeptur: rezeptur,
        fleisch: fleisch,
        senf: senf,
      );
    }

    test('abschließen: Name, Grund und Änderungen im Verlauf', () async {
      final a = await anlegen();
      final v1 = (await rezepte.neuesteVersion(a.rezeptur))!;
      await rezepte.versionAendern(
        v1.id,
        const EntwicklungRezepturVersionenCompanion(
          bezeichnung: Value('Erstes Muster'),
        ),
      );
      await rezepte.positionHinzufuegen(v1.id, zutatId: a.fleisch, mengeKg: 10);
      expect(await rezepte.vorigerStand(v1), isNull);
      await rezepte.versionAbschliessen(v1.id, grund: ' Für die Verkostung ');

      var verlauf = await projekte.eintraegeBeobachten(a.projekt).first;
      var stand = verlauf.firstWhere(
        (e) => e.art == EintragArt.rezeptur.schluessel,
      );
      expect(stand.titel, 'Frikadelle · Stand 1');
      expect(stand.beschreibung, 'Erstes Muster\nFür die Verkostung');
      expect(stand.versionId, v1.id);
      expect(texteAus(stand.aenderungen), contains('1 Zeile'));
      expect((await rezepte.version(v1.id))!.notiz, 'Für die Verkostung');

      // Der zweite Stand: verglichen mit dem ersten.
      final v2id = await rezepte.versionAnlegen(a.rezeptur, vorlageId: v1.id);
      await rezepte.positionHinzufuegen(v2id, zutatId: a.senf, mengeKg: 0.5);
      final v2 = (await rezepte.version(v2id))!;
      expect((await rezepte.vorigerStand(v2))?.id, v1.id);
      final vorschau = await rezepte.standAenderungenVon(v2id);
      expect(vorschau, containsAll(['Neu: Senf (0,5 kg)', 'Allergen neu: Senf']));
      // Die Notiz des Entwurfs steht im Fenster vorbelegt — geleert ist
      // sie danach weg.
      await rezepte.versionAendern(
        v2id,
        const EntwicklungRezepturVersionenCompanion(
          notiz: Value('Zwischenstand'),
        ),
      );
      await rezepte.versionAbschliessen(v2id, grund: '  ');

      verlauf = await projekte.eintraegeBeobachten(a.projekt).first;
      stand = verlauf.firstWhere((e) => e.versionId == v2id);
      expect(stand.titel, 'Frikadelle · Stand 2');
      // Ohne Grund und ohne Bezeichnung keine Beschreibung.
      expect(stand.beschreibung, isNull);
      expect(texteAus(stand.aenderungen), vorschau);
      expect((await rezepte.version(v2id))!.notiz, isNull);

      // Ohne Fenster (kein Grund übergeben) bleibt die Notiz.
      final v3id = await rezepte.versionAnlegen(a.rezeptur, vorlageId: v2id);
      await rezepte.versionAendern(
        v3id,
        const EntwicklungRezepturVersionenCompanion(notiz: Value('bleibt')),
      );
      await rezepte.versionAbschliessen(v3id);
      expect((await rezepte.version(v3id))!.notiz, 'bleibt');
      // Nichts geändert — auch das steht da.
      stand = (await projekte.eintraegeBeobachten(a.projekt).first)
          .firstWhere((e) => e.versionId == v3id);
      expect(texteAus(stand.aenderungen), ['Keine Änderung zu Stand 2']);
    });

    test('Statuswechsel als Meilenstein', () async {
      final a = await anlegen();
      await projekte.statusAendern(
        a.projekt,
        ProjektStatus.validierung,
        jetzt: DateTime(2026, 4, 2, 10),
      );
      // Derselbe Status noch einmal: nichts Neues.
      await projekte.statusAendern(a.projekt, ProjektStatus.validierung);
      final p = (await projekte.projekt(a.projekt))!;
      expect(p.status, ProjektStatus.validierung.schluessel);
      final verlauf = await projekte.eintraegeBeobachten(a.projekt).first;
      final wechsel = verlauf.where((e) => statusWechsel(e) != null).toList();
      expect(wechsel, hasLength(1));
      expect(wechsel.single.titel, 'Validierung begonnen');
      expect(wechsel.single.datum, DateTime(2026, 4, 2));
      expect(wechsel.single.wert, 'status:entwicklung>validierung');
      expect(wechsel.single.beschreibung, 'Status vorher: In Entwicklung');

      final phasen = statusJeEintrag(verlauf, ProjektStatus.validierung);
      final angelegt =
          verlauf.firstWhere((e) => e.titel == 'Projekt angelegt');
      expect(phasen[angelegt.id], ProjektStatus.entwicklung);
      expect(phasen[wechsel.single.id], ProjektStatus.validierung);
    });

    test('das Etikett eines Stands aus der Datenbank', () async {
      final a = await anlegen();
      await projekte.projektAendern(
        a.projekt,
        EntwicklungProjekteCompanion(
          spezifikation: Value(
            const SpezAngaben(
              lagerung: 'gekühlt',
              spuren: {'sellerie'},
            ).alsJson(),
          ),
        ),
      );
      final v1 = (await rezepte.neuesteVersion(a.rezeptur))!;
      await rezepte.positionHinzufuegen(v1.id, zutatId: a.fleisch, mengeKg: 9);
      await rezepte.positionHinzufuegen(v1.id, zutatId: a.senf, mengeKg: 1);

      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      // Am Leben halten, solange gelesen wird.
      final abo = container.listen(etikettProvider(v1.id), (_, __) {});
      addTearDown(abo.close);
      var e = (await container.read(etikettProvider(v1.id).future))!;
      expect(e.bezeichnung, 'Frikadelle');
      expect(e.stand, 'Frikadelle · Stand 1 · Entwurf');
      expect(e.zutatenliste, contains('SENF'));
      expect(e.allergene, ['Senf']);
      expect(e.spuren, ['Sellerie']);
      expect(e.lagerung, 'gekühlt');

      await rezepte.versionAbschliessen(v1.id);
      container.invalidate(etikettProvider(v1.id));
      e = (await container.read(etikettProvider(v1.id).future))!;
      expect(e.stand, startsWith('Frikadelle · Stand 1 · abgeschlossen am '));

      expect(
        await container.read(etikettProvider('gibt-es-nicht').future),
        isNull,
      );
    });
  });
}
