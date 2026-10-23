// `show Value`: drift bringt eine eigene Klasse `Column` mit.
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/constants/artikel_merkmale.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/entwicklung_vorgabe.dart';
import 'package:produktion_planer/core/theme/app_theme.dart';
import 'package:produktion_planer/features/entwicklung/daten/entwicklung_repository.dart';
import 'package:produktion_planer/features/entwicklung/freigabe/freigabe.dart';
import 'package:produktion_planer/features/entwicklung/freigabe/freigabe_ansicht.dart';
import 'package:produktion_planer/features/entwicklung/projekte/entwicklungsstrang.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_modell.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_repository.dart';
import 'package:produktion_planer/features/entwicklung/rechenkern/rechen_modell.dart';
import 'package:produktion_planer/features/entwicklung/rechenkern/rechenkern.dart';
import 'package:produktion_planer/features/entwicklung/spezifikation/spez_angaben.dart';

import 'helpers/test_db.dart';

/// Tests für die Freigabe eines Projekts als Artikel und den Abgleich des
/// Verlusts mit den erfassten Produktionen. Artikel, Projekte und
/// Rezepturen sind erfunden.
void main() {
  group('Allergene für den Artikel', () {
    RechenZutat zutat(String id, Set<String> allergene) =>
        RechenZutat(id: id, name: id, allergene: allergene);

    RezepturErgebnis rechne(RechenRezeptur r) => berechne(r);

    test('genannte Allergene als Kommaliste', () {
      final r = RechenRezeptur(
        id: 'r',
        name: 'r',
        positionen: [
          RechenPosition.zutat(zutat('Weizenmehl', {'gluten'}), mengeKg: 1),
          RechenPosition.zutat(zutat('Senf', {'senf'}), mengeKg: 1),
        ],
      );
      expect(
        merkmaleAusText(allergeneFuerArtikel(r, rechne(r))),
        {'gluten', 'senf'},
      );
    });

    test('„keine" nur, wenn alle Zutaten gepflegt sind', () {
      final gepflegt = RechenRezeptur(
        id: 'r',
        name: 'r',
        positionen: [
          RechenPosition.zutat(zutat('Salz', {kAllergenKeine}), mengeKg: 1),
          RechenPosition.unterrezeptur(
            RechenRezeptur(
              id: 'u',
              name: 'u',
              positionen: [
                RechenPosition.zutat(
                  zutat('Pfeffer', {kAllergenKeine}),
                  mengeKg: 1,
                ),
              ],
            ),
            mengeKg: 1,
          ),
        ],
      );
      expect(
        allergeneFuerArtikel(gepflegt, rechne(gepflegt)),
        kAllergenKeine,
      );

      final ungepflegt = RechenRezeptur(
        id: 'r',
        name: 'r',
        positionen: [
          RechenPosition.zutat(zutat('Salz', {kAllergenKeine}), mengeKg: 1),
          RechenPosition.zutat(zutat('Unbekannt', const {}), mengeKg: 1),
        ],
      );
      expect(allergeneFuerArtikel(ungepflegt, rechne(ungepflegt)), isNull);
    });
  });

  group('Freigabe', () {
    late AppDatabase db;
    late EntwicklungRepository rezepte;
    late ProjektRepository projekte;
    late FreigabeDienst dienst;

    setUp(() {
      db = testDatenbank();
      rezepte = EntwicklungRepository(db);
      projekte = ProjektRepository(db);
      dienst = FreigabeDienst(db);
    });
    tearDown(() => db.close());

    /// Ein Projekt mit einer Rezeptur: 50 kg Schweinefleisch, 30 kg
    /// Wasser, 20 kg Paniermehl mit Gluten, 10 % Garverlust — Stand 1
    /// abgeschlossen.
    Future<({EntwicklungsProjekt projekt, String versionId})> anlegen({
      String? artikelnummer = 'A-100',
      String verlustArt = 'garen',
    }) async {
      final id = await projekte.projektAnlegen(
        name: 'Schnitzel Wiener Art',
        artikelnummer: artikelnummer,
      );
      await projekte.projektAendern(
        id,
        const EntwicklungProjekteCompanion(grenzeAw: Value(0.97)),
      );
      final rezeptur = await rezepte.rezepturAnlegen(
        name: 'Schnitzel Wiener Art',
        projektId: id,
      );
      Future<String> zutat(
        String name, {
        bool fleisch = false,
        bool wasser = false,
        String? allergene,
      }) =>
          rezepte.zutatAnlegen(
            EntwicklungZutatenCompanion(
              name: Value(name),
              istFleisch: Value(fleisch),
              istWasser: Value(wasser),
              tierart: Value(fleisch ? 'schwein' : null),
              fett: Value(fleisch ? 20 : null),
              eiweiss: Value(fleisch ? 18 : null),
              allergene: Value(allergene),
            ),
          );
      final schwein = await zutat(
        'Schweineoberschale',
        fleisch: true,
        allergene: kAllergenKeine,
      );
      final wasser =
          await zutat('Trinkwasser', wasser: true, allergene: kAllergenKeine);
      final mehl = await zutat('Paniermehl', allergene: 'gluten');
      final v = (await rezepte.neuesteVersion(rezeptur))!;
      await rezepte.positionHinzufuegen(v.id, zutatId: schwein, mengeKg: 50);
      await rezepte.positionHinzufuegen(v.id, zutatId: wasser, mengeKg: 30);
      await rezepte.positionHinzufuegen(v.id, zutatId: mehl, mengeKg: 20);
      await rezepte.versionAendern(
        v.id,
        EntwicklungRezepturVersionenCompanion(
          verlustProzent: const Value(10),
          verlustArt: Value(verlustArt),
        ),
      );
      await rezepte.versionAbschliessen(v.id);
      return (projekt: (await projekte.projekt(id))!, versionId: v.id);
    }

    test('der Vorschlag kommt aus Projekt und Rezeptur', () async {
      final a = await anlegen();
      final w = await dienst.vorschlag(a.projekt, a.versionId);
      expect(w.artikelnummer, 'A-100');
      expect(w.bezeichnung, 'Schnitzel Wiener Art');
      expect(merkmaleAusText(w.allergene), {'gluten'});
      expect(w.verlustProzent, 10);
      expect(w.aw, 0.97);
      final staende = await dienst.staende(a.projekt.id);
      expect(staende.single.version.id, a.versionId);
    });

    test('was im Projekt steht, fragt die Freigabe nicht noch einmal',
        () async {
      final a = await anlegen();
      await projekte.projektAendern(
        a.projekt.id,
        EntwicklungProjekteCompanion(
          spezifikation: Value(
            const SpezAngaben(
              bezeichnung: 'Schnitzel Wiener Art, paniert',
              haltbarkeit: '21 Tage',
            ).alsJson(),
          ),
        ),
      );
      final p = (await projekte.projekt(a.projekt.id))!;
      final w = await dienst.vorschlag(p, a.versionId);
      expect(w.bezeichnung, 'Schnitzel Wiener Art, paniert');
      expect(w.haltbarkeitTage, 21);
    });

    test('die Freigabe lässt ein zurückgestelltes Foto zurückgestellt',
        () async {
      final a = await anlegen();
      await projekte.checklisteZurueckstellen(
        a.projekt.id,
        schluessel: 'produktfotoHinterlegt',
        zurueck: true,
      );
      final p = (await projekte.projekt(a.projekt.id))!;
      final w = (await dienst.vorschlag(p, a.versionId))
          .kopie(produktgruppe: 'bratstrasse_paniert');
      await dienst.freigeben(projekt: p, versionId: a.versionId, werte: w);
      final nach = (await projekte.projekt(a.projekt.id))!;
      expect(checklisteAus(nach.checkliste), {'artikelAngelegt'});
      expect(
        checklisteZurueckgestellt(nach.checkliste),
        {'produktfotoHinterlegt'},
      );
    });

    test('Haltbarkeit in Tagen aus den Angaben', () {
      expect(haltbarkeitInTagen('21'), 21);
      expect(haltbarkeitInTagen(' 21 Tage '), 21);
      expect(haltbarkeitInTagen('1 Tag'), 1);
      expect(haltbarkeitInTagen('3 Wochen'), 21);
      expect(haltbarkeitInTagen('12 Monate'), 365);
      expect(haltbarkeitInTagen('6 Mon.'), 183);
      // Was sich nicht in Tage fassen lässt, bleibt offen.
      expect(haltbarkeitInTagen('12 Monate bei -18 °C'), isNull);
      expect(haltbarkeitInTagen(''), isNull);
      expect(haltbarkeitInTagen('ca. 3 Wochen'), isNull);
    });

    test('ein neuer Artikel entsteht, das Projekt geht in Produktion',
        () async {
      final a = await anlegen();
      final w = (await dienst.vorschlag(a.projekt, a.versionId)).kopie(
        produktgruppe: 'bratstrasse_paniert',
        haltbarkeitTage: 14,
      );
      final artikelId = await dienst.freigeben(
        projekt: a.projekt,
        versionId: a.versionId,
        werte: w,
      );

      final p = await (db.select(db.products)
            ..where((p) => p.id.equals(artikelId)))
          .getSingle();
      expect(p.artikelnummer, 'A-100');
      expect(p.artikelbezeichnung, 'Schnitzel Wiener Art');
      expect(p.produktgruppe, 'bratstrasse_paniert');
      expect(p.haltbarkeitTage, 14);
      expect(merkmaleAusText(p.allergene), {'gluten'});
      // Den Verlust liest die Planung aus der Freigabe, nicht aus der
      // alten Spalte des Artikels.
      expect(p.gesamtAusbeuteFaktor, isNull);
      expect(await verlustVorgabeAusEntwicklung(db, artikelId), 10);
      expect(p.zielAw, 0.97);
      expect(p.istEingepflegt, isTrue);

      final projekt = (await projekte.projekt(a.projekt.id))!;
      expect(projekt.artikelId, artikelId);
      expect(projekt.freigabeVersionId, a.versionId);
      expect(projekt.freigegebenAm, isNotNull);
      expect(projekt.status, ProjektStatus.produktion.schluessel);
      expect(checklisteAus(projekt.checkliste), contains('artikelAngelegt'));

      final verlauf = await projekte.eintraegeBeobachten(a.projekt.id).first;
      final e = verlauf.firstWhere(
        (e) => e.titel.startsWith('Freigegeben als neuer Artikel'),
      );
      expect(e.versionId, a.versionId);
      expect(texteAus(e.aenderungen).single, contains('Allergene'));
      // Der Schritt in die Produktion steht als Phase im Verlauf.
      expect(
        statusWechsel(e),
        (alt: ProjektStatus.entwicklung, neu: ProjektStatus.produktion),
      );

      // Noch einmal freigegeben: schon in Produktion — kein Wechsel.
      await dienst.freigeben(
        projekt: projekt,
        versionId: a.versionId,
        werte: w,
      );
      final nochmal = (await projekte.eintraegeBeobachten(a.projekt.id).first)
          .where((e) => e.titel == 'Freigegeben für Artikel A-100');
      expect(nochmal, hasLength(1));
      expect(statusWechsel(nochmal.single), isNull);
    });

    test('ein vorhandener Artikel bekommt nur die gewählten Felder',
        () async {
      final a = await anlegen();
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'p-alt',
              artikelnummer: 'A-100',
              artikelbezeichnung: 'Schnitzel (Planer)',
              produktgruppe: const Value('bratstrasse_natur'),
              haltbarkeitTage: const Value(10),
              allergene: const Value('eier'),
            ),
          );
      final w = (await dienst.vorschlag(a.projekt, a.versionId)).kopie(
        produktgruppe: 'bratstrasse_paniert',
        haltbarkeitTage: 14,
      );
      // Was sich ändern würde.
      final alt = (await dienst.artikelZuNummer('A-100'))!;
      expect(
        [
          for (final f in FreigabeFeld.values)
            if (aendertFeld(alt, w, f)) f,
        ],
        [
          FreigabeFeld.bezeichnung,
          FreigabeFeld.produktgruppe,
          FreigabeFeld.haltbarkeit,
          FreigabeFeld.allergene,
          FreigabeFeld.aw,
        ],
      );

      final id = await dienst.freigeben(
        projekt: a.projekt,
        versionId: a.versionId,
        werte: w,
        felder: {FreigabeFeld.allergene, FreigabeFeld.aw},
      );
      expect(id, 'p-alt');
      final p = await (db.select(db.products)
            ..where((p) => p.id.equals('p-alt')))
          .getSingle();
      // Gewählt: geschrieben.
      expect(merkmaleAusText(p.allergene), {'gluten'});
      expect(p.zielAw, 0.97);
      // Nicht gewählt: wie vorher.
      expect(p.artikelbezeichnung, 'Schnitzel (Planer)');
      expect(p.produktgruppe, 'bratstrasse_natur');
      expect(p.haltbarkeitTage, 10);
    });

    test('ein gelöschter Artikel mit der Nummer wird wieder aktiviert',
        () async {
      final a = await anlegen();
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'p-weg',
              artikelnummer: 'A-100',
              artikelbezeichnung: 'Alt',
              deletedAt: Value(DateTime(2025)),
            ),
          );
      final id = await dienst.freigeben(
        projekt: a.projekt,
        versionId: a.versionId,
        werte: await dienst.vorschlag(a.projekt, a.versionId),
      );
      expect(id, 'p-weg');
      final p = await (db.select(db.products)
            ..where((p) => p.id.equals('p-weg')))
          .getSingle();
      expect(p.deletedAt, isNull);
      expect(p.istEingepflegt, isFalse);
    });

    test('„kein Verlust" im Stand: auch keiner für die Planung', () async {
      // Die 10 % bleiben eingetragen, zählen bei „kein Verlust" aber nicht.
      final a = await anlegen(verlustArt: 'keiner');
      final w = await dienst.vorschlag(a.projekt, a.versionId);
      expect(w.verlustProzent, isNull);
      final artikelId = await dienst.freigeben(
        projekt: a.projekt,
        versionId: a.versionId,
        werte: w,
      );
      expect(await verlustVorgabeAusEntwicklung(db, artikelId), isNull);
    });

    test('ohne Artikelnummer keine Freigabe', () async {
      final a = await anlegen(artikelnummer: null);
      final w = await dienst.vorschlag(a.projekt, a.versionId);
      expect(w.artikelnummer, isEmpty);
      await expectLater(
        dienst.freigeben(
          projekt: a.projekt,
          versionId: a.versionId,
          werte: w,
        ),
        throwsArgumentError,
      );
    });

    group('Abgleich mit den Produktionen', () {
      Future<void> produktion(String artikelId, double roh, double fertig) =>
          db.into(db.productionHistory).insert(
                ProductionHistoryCompanion.insert(
                  id: 'h-$roh-$fertig-${DateTime.now().microsecond}',
                  productId: artikelId,
                  datum: DateTime(2026, 10, 1),
                  kgRohware: Value(roh),
                  kgFertigware: Value(fertig),
                ),
              );

      Future<FreigabeUebersicht> freigegeben(
        List<(double, double)> produktionen, {
        String verlustArt = 'garen',
      }) async {
        final a = await anlegen(verlustArt: verlustArt);
        final artikelId = await dienst.freigeben(
          projekt: a.projekt,
          versionId: a.versionId,
          werte: await dienst.vorschlag(a.projekt, a.versionId),
        );
        for (final (roh, fertig) in produktionen) {
          await produktion(artikelId, roh, fertig);
        }
        return dienst.uebersicht((await projekte.projekt(a.projekt.id))!);
      }

      test('ohne Produktionen kein Abgleich', () async {
        final u = await freigegeben(const []);
        expect(u.artikel, isNotNull);
        expect(u.stand?.version.nummer, 1);
        expect(u.abgleich, isNull);
      });

      test('weniger Verlust als gerechnet: Fleisch zu hoch angegeben',
          () async {
        final u = await freigegeben(const [(100, 95), (200, 190)]);
        final a = u.abgleich!;
        expect(a.produktionen, 2);
        expect(a.gemessenProzent, closeTo(5, 1e-9));
        expect(a.rezepturProzent, 10);
        // 50 kg Fleisch in 90 kg bzw. 95 kg Enderzeugnis.
        expect(a.fleischRezeptur, closeTo(50 / 90 * 100, 1e-6));
        expect(a.fleischGemessen, closeTo(50 / 95 * 100, 1e-6));
        expect(a.verlustWeichtAb, isTrue);
        expect(a.fleischZuHoch, isTrue);
        expect(a.fleischZuNiedrig, isFalse);
      });

      test('mehr Verlust als gerechnet: vorsichtig angegeben', () async {
        final u = await freigegeben(const [(100, 85)]);
        final a = u.abgleich!;
        expect(a.gemessenProzent, closeTo(15, 1e-9));
        expect(a.fleischZuNiedrig, isTrue);
        expect(a.fleischZuHoch, isFalse);
      });

      test('„kein Verlust" gerechnet, aber einer gemessen', () async {
        final u = await freigegeben(
          const [(100, 95)],
          verlustArt: 'keiner',
        );
        final a = u.abgleich!;
        expect(a.rezepturProzent, 0);
        expect(a.gemessenProzent, closeTo(5, 1e-9));
        // 50 kg Fleisch in 100 kg bzw. 95 kg Enderzeugnis.
        expect(a.fleischRezeptur, closeTo(50, 1e-6));
        expect(a.fleischGemessen, closeTo(50 / 95 * 100, 1e-6));
        expect(a.verlustWeichtAb, isTrue);
        expect(a.fleischZuNiedrig, isTrue);
      });

      test('passend: keine Hinweise', () async {
        final u = await freigegeben(const [(100, 90.5)]);
        final a = u.abgleich!;
        expect(a.verlustWeichtAb, isFalse);
        expect(a.fleischZuHoch, isFalse);
        expect(a.fleischZuNiedrig, isFalse);
      });
    });
  });

  group('Anzeige', () {
    Future<void> zeige(WidgetTester tester, VerlustAbgleich a) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: VerlustAbgleichAnzeige(abgleich: a),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('warnt, wenn das Etikett zu viel Fleisch nennt',
        (tester) async {
      await zeige(
        tester,
        const VerlustAbgleich(
          produktionen: 3,
          gemessenProzent: 5,
          rezepturProzent: 10,
          fleischRezeptur: 55.6,
          fleischGemessen: 52.6,
          zutatenlisteRezeptur: 'Schweinefleisch (55,6 %)',
          zutatenlisteGemessen: 'Schweinefleisch (52,6 %)',
        ),
      );
      expect(find.text('Fleischanteil zu hoch angegeben'), findsOneWidget);
      expect(find.textContaining('Ø der letzten 3 Produktionen'), findsOneWidget);
      expect(find.text('Schweinefleisch (52,6 %)'), findsOneWidget);
    });

    testWidgets('passend: ein grünes Häkchen', (tester) async {
      await zeige(
        tester,
        const VerlustAbgleich(
          produktionen: 1,
          gemessenProzent: 10.2,
          rezepturProzent: 10,
        ),
      );
      expect(
        find.text('Rezeptur und Produktion passen zusammen.'),
        findsOneWidget,
      );
      expect(find.textContaining('der letzten Produktion'), findsOneWidget);
    });
  });
}
