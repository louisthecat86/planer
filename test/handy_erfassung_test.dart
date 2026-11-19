import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:erfassung_format/erfassung_format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/constants/parameter_namen.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/prozesskette_service.dart';
import 'package:produktion_planer/features/handy_erfassung/handy_erfassung_dienst.dart';

import 'helpers/test_db.dart';

/// Die Handy-Erfassung: das Austauschformat (Paket hin, Ergebnis zurück),
/// was der Planer ins Paket legt und was er aus einem Ergebnis übernimmt —
/// mit Vorschau, Konflikten und Grenzen. Alles erfunden.
void main() {
  group('Austauschformat', () {
    test('Zahlen und Uhrzeiten, wie man sie eintippt', () {
      expect(zahlAus('12,5'), 12.5);
      expect(zahlAus(' 12.5 '), 12.5);
      expect(zahlAus(''), isNull);
      expect(zahlAus('abc'), isNull);
      expect(zahlText(1250), '1.250');
      expect(zahlText(12.54), '12,5');
      expect(zahlText(1234567.25, nachkomma: 2), '1.234.567,25');
      expect(zahlText(-0.01), '0,0');
      expect(zahlText(-12.5), '-12,5');
      expect(eingabeText(1250), '1250');
      expect(eingabeText(12.5), '12,5');
      expect(eingabeText(0.25), '0,25');
      expect(zahlAus(eingabeText(1250.75)), 1250.75);
      expect(zeitAus('6'), '06:00');
      expect(zeitAus('630'), '06:30');
      expect(zeitAus('0630'), '06:30');
      expect(zeitAus('6:5'), '06:05');
      expect(zeitAus('14.30'), '14:30');
      expect(zeitAus('25:00'), isNull);
      expect(zeitAus('abc'), isNull);
      expect(dauerMinuten('06:00', '14:30'), 510);
      expect(dauerMinuten('22:00', '02:00'), 240);
      expect(dauerMinuten('06:00', null), isNull);
      expect(verlustAnteil(100, 80), closeTo(0.2, 1e-9));
      expect(kgProStunde(120, 90), closeTo(80, 1e-9));
    });

    test('Grenzen: hart blockiert, weich warnt, Text bleibt ungeprüft', () {
      const g =
          Grenze(hartMin: 100, hartMax: 260, weichMin: 180, weichMax: 240);
      expect(g.pruefe('200').status, GrenzStatus.ok);
      expect(g.pruefe('170').status, GrenzStatus.warnung);
      expect(g.pruefe('250,5').status, GrenzStatus.warnung);
      expect(g.pruefe('90').status, GrenzStatus.blockiert);
      expect(g.pruefe('300').status, GrenzStatus.blockiert);
      expect(g.pruefe('Programm 4').status, GrenzStatus.ok);
      expect(g.pruefe(null).status, GrenzStatus.ok);
      expect(g.text, 'üblich 180–240 · möglich 100–260');
      expect(const Grenze(weichMax: 5).text, 'üblich bis 5');
      expect(Grenze.ausJson(const {}), isNull);
    });

    test('was an einer Erfassung nicht stimmt', () {
      expect(produktionFehler(rohKg: null), isNotNull);
      expect(produktionFehler(rohKg: 0), isNotNull);
      expect(produktionFehler(rohKg: 100, fleischKg: 120), isNotNull);
      expect(produktionFehler(rohKg: 100, fertigKg: 101), isNotNull);
      expect(
        produktionFehler(rohKg: 100, fleischKg: 80, fertigKg: 100),
        isNull,
      );
    });

    test('Paket und Ergebnis: hin und zurück', () {
      final paket = ErfassungsPaket(
        id: 'paket-1',
        erstellt: DateTime(2026, 11, 9, 17, 45),
        von: DateTime(2026, 11, 9),
        bis: DateTime(2026, 11, 15),
        produktionen: [
          PaketProduktion(
            id: 't1',
            artikelId: 'a1',
            artikelnummer: '4711',
            artikel: 'Grillwurst',
            datum: DateTime(2026, 11, 10),
            abteilung: 'bratstrasse',
            abteilungName: 'Bratstraße',
            abteilungFarbe: 0xFF112233,
            start: '06:00',
            rohKg: 500,
            fertigKg: 400,
          ),
        ],
        artikel: const [
          PaketArtikel(
            id: 'a1',
            nummer: '4711',
            name: 'Grillwurst',
            schritte: [
              PaketSchritt(
                id: 's1',
                nummer: 1,
                abteilung: 'bratstrasse',
                abteilungName: 'Bratstraße',
                anlage: 'Bratstraße Test',
                felder: [
                  PaketFeld(
                    schluessel: 's:bandgeschwindigkeit',
                    art: FeldArt.steckbrief,
                    name: 'Bandgeschwindigkeit',
                    einheit: 'm/min',
                    wert: '2,5',
                    grenze: Grenze(hartMax: 10),
                  ),
                  PaketFeld(
                    schluessel: 'n',
                    art: FeldArt.notiz,
                    name: 'Notiz',
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      expect(paket.dateiname, 'Planer-Erfassung_2026-11-09_1745.json');
      final text = paket.alsText();
      expect(dateiArtVon(text), DateiArt.paket);
      final wieder = ErfassungsPaket.ausText(text);
      expect(wieder.alsText(), text);
      final feld = wieder.artikelMit('a1')!.schrittMit('s1')!.felder.first;
      expect(feld.istZahl, isTrue);
      expect(feld.beschriftung, 'Bandgeschwindigkeit (m/min)');
      expect(feld.grenze!.hartMax, 10);
      final notiz = wieder.artikel.single.schritte.single.felder.last;
      expect(notiz.istZahl, isFalse);
      expect(wieder.produktionen.single.datum, DateTime(2026, 11, 10));

      final ergebnis = ErfassungsErgebnis(
        paketId: paket.id,
        paketErstellt: paket.erstellt,
        erstellt: DateTime(2026, 11, 10, 18, 10),
        produktionen: [
          ErfassteProduktion(
            produktionId: 't1',
            artikelId: 'a1',
            artikel: 'Grillwurst',
            datum: DateTime(2026, 11, 10),
            rohKg: 510,
            fertigKg: 402.5,
            start: '06:05',
            ende: '13:40',
            charge: 'L123',
            kuerzel: 'AB',
            bemerkung: 'Darm gewechselt',
            erfasstAm: DateTime(2026, 11, 10, 13, 45),
          ),
        ],
        werte: [
          GeaenderterWert(
            artikelId: 'a1',
            schrittId: 's1',
            schluessel: 's:bandgeschwindigkeit',
            art: FeldArt.steckbrief,
            name: 'Bandgeschwindigkeit',
            alt: '2,5',
            neu: '2,8',
            kuerzel: 'AB',
            erfasstAm: DateTime(2026, 11, 10, 9),
          ),
        ],
      );
      expect(
        ergebnis.dateiname(kuerzel: 'A B!'),
        'Planer-Erfassung-Ergebnis_2026-11-10_1810_AB.json',
      );
      final zurueck = ErfassungsErgebnis.ausText(ergebnis.alsText());
      expect(zurueck.alsText(), ergebnis.alsText());
      expect(
        zurueck.produktionen.single.notiz,
        'Darm gewechselt · Charge L123 · erfasst von AB',
      );
      expect(zurueck.produktionen.single.dauerMin, 455);
    });

    test('falsche Dateien: ein Satz statt eines Absturzes', () {
      String meldung(void Function() f) {
        try {
          f();
        } on FormatFehler catch (e) {
          return e.meldung;
        }
        return '';
      }

      expect(
        meldung(() => ErfassungsPaket.ausText('kein json')),
        contains('keine Erfassungsdatei'),
      );
      expect(
        meldung(() => ErfassungsPaket.ausText('{"format":"anderes"}')),
        contains('keine Erfassungsdatei'),
      );
      final ergebnis = ErfassungsErgebnis(
        paketId: 'p',
        erstellt: DateTime(2026, 11, 10),
      ).alsText();
      expect(
        meldung(() => ErfassungsPaket.ausText(ergebnis)),
        contains('Ergebnis vom Handy'),
      );
      expect(
        meldung(
          () => ErfassungsErgebnis.ausText(
            ergebnis.replaceFirst('"version":1', '"version":99'),
          ),
        ),
        contains('neueren Fassung'),
      );
      expect(
        meldung(
          () => ErfassungsErgebnis.ausText(
            '{"format":"planer-erfassung","art":"ergebnis","version":1}',
          ),
        ),
        contains('beschädigt'),
      );
      expect(dateiArtVon('quatsch'), isNull);
    });
  });

  group('im Planer', () {
    late AppDatabase db;
    late HandyErfassungDienst dienst;
    final dienstag = DateTime(2026, 11, 10);

    Future<void> parameter(
      String id,
      String stepId,
      String gruppe,
      String name,
      String? wert, {
      bool custom = false,
      int reihenfolge = 10,
    }) =>
        db.into(db.productStepParameters).insert(
              ProductStepParametersCompanion.insert(
                id: id,
                stepId: stepId,
                parameterGruppe: gruppe,
                parameterName: name,
                wert: Value(wert),
                reihenfolge: Value(reihenfolge),
                istCustom: Value(custom),
              ),
            );

    Future<void> auftrag(
      String id,
      String productId,
      DateTime tag, {
      double mengeKg = 500,
      String? parent,
      String status = 'geplant',
    }) =>
        db.into(db.productionTasks).insert(
              ProductionTasksCompanion.insert(
                id: id,
                productId: productId,
                mengeKg: mengeKg,
                datum: tag,
                abteilung: 'bratstrasse',
                geplanteDauerMinuten: 120,
                geplanteMitarbeiter: 2,
                fertigMengeKg: const Value(400),
                startZeit: const Value('6:00'),
                parentTaskId: Value(parent),
                status: Value(status),
              ),
            );

    Future<List<ProductStepParameter>> zeilen(String stepId) =>
        (db.select(db.productStepParameters)
              ..where((p) => p.stepId.equals(stepId))
              ..where((p) => p.deletedAt.isNull()))
            .get();

    setUp(() async {
      db = testDatenbank();
      dienst = HandyErfassungDienst(db);
      await seedArtikel(
        db,
        id: 'a1',
        nummer: '4711',
        bezeichnung: 'Grillwurst',
      );
      await seedArtikel(
        db,
        id: 'a2',
        nummer: '4712',
        bezeichnung: 'Ohne Kette',
      );
      await seedAnlage(
        db,
        id: 'm1',
        name: 'Bratstraße Test',
        abteilung: 'bratstrasse',
      );
      await seedAnlage(
        db,
        id: 'm2',
        name: 'Füller Test',
        abteilung: 'wurstkueche',
      );
      await seedSchritt(
        db,
        id: 's1',
        productId: 'a1',
        reihenfolge: 1,
        abteilung: 'wurstkueche',
        maschineId: 'm2',
      );
      await seedSchritt(
        db,
        id: 's2',
        productId: 'a1',
        reihenfolge: 2,
        abteilung: 'bratstrasse',
        maschineId: 'm1',
      );
      for (final (i, name) in const ['Füllgewicht', 'Programm'].indexed) {
        await db.into(db.machineParameterDefs).insert(
              MachineParameterDefsCompanion.insert(
                id: 'd$i',
                maschineId: 'm2',
                parameterName: name,
                einheit: Value(i == 0 ? 'g' : null),
                sortierung: Value(i),
              ),
            );
      }
      await db.into(db.parameterGrenzen).insert(
            ParameterGrenzenCompanion.insert(
              id: 'g1',
              kontext: 'Füller Test',
              parameterName: 'Füllgewicht',
              hartMin: const Value(10),
              hartMax: const Value(500),
              weichMax: const Value(200),
            ),
          );
      await parameter('x1', 's1', 'FÜLLEN', 'Füllgewicht', '120');
      await parameter('x2', 's1', 'FÜLLEN', 'Darm', 'Kaliber 26');
      await parameter('x3', 's1', 'Eigene', 'Clip', 'A', custom: true);
      await parameter('x4', 's2', kPlattenGruppeBrat, 'Platte Oben 1', '180');
    });
    tearDown(() => db.close());

    test('das Paket: Produktionen der Tage und die Felder je Schritt',
        () async {
      await auftrag('t1', 'a1', dienstag);
      await auftrag('t1b', 'a1', dienstag, mengeKg: 250, parent: 't1');
      await auftrag('t2', 'a1', DateTime(2026, 11, 12), status: 'storniert');
      await auftrag('t3', 'a1', DateTime(2026, 11, 20));
      final paket = await dienst.paketErstellen(
        von: DateTime(2026, 11, 9),
        bis: DateTime(2026, 11, 15),
        jetzt: DateTime(2026, 11, 9, 17, 45),
      );
      final p = paket.produktionen.single;
      expect(
        (p.id, p.artikelnummer, p.artikel, p.datum, p.rohKg, p.fertigKg),
        ('t1', '4711', 'Grillwurst', dienstag, 750.0, 400.0),
      );
      expect((p.abteilungName, p.start), ('Bratstraße', '06:00'));

      // Nur Artikel mit Prozesskette.
      final a = paket.artikel.single;
      expect(a.id, 'a1');
      expect(
        [for (final s in a.schritte) s.anlage],
        ['Füller Test', 'Bratstraße Test'],
      );
      final fuellen = a.schritte.first;
      expect(
        [for (final f in fuellen.felder) (f.art, f.name, f.wert)],
        [
          (FeldArt.steckbrief, 'Füllgewicht', '120'),
          (FeldArt.steckbrief, 'Programm', null),
          (FeldArt.parameter, 'Darm', 'Kaliber 26'),
          (FeldArt.parameter, 'Clip', 'A'),
          (FeldArt.notiz, 'Maschineneinstellungen (Notiz)', null),
        ],
      );
      expect(fuellen.felder.first.grenze!.hartMax, 500);
      expect(fuellen.felder.first.einheit, 'g');
      // Die Bratstraße: 10 Platten oben, 10 unten und die Notiz.
      final braten = a.schritte.last;
      expect(braten.felder, hasLength(21));
      expect(braten.feldMit(plattenSchluessel('Platte Oben 1'))!.wert, '180');
      expect(braten.felder.first.art, FeldArt.platte);

      // Ist die Produktion erfasst, fehlt sie im nächsten Paket.
      final wieder = ErfassungsPaket.ausText(paket.alsText());
      expect(wieder.produktionen.single.id, 't1');
    });

    test(
        'das Ergebnis: Vorschau, übernehmen, und zweimal einlesen schadet '
        'nicht', () async {
      await auftrag('t1', 'a1', dienstag);
      final paket = await dienst.paketErstellen(
        von: DateTime(2026, 11, 9),
        bis: DateTime(2026, 11, 15),
      );
      final fuellen = paket.artikel.single.schritte.first;
      GeaenderterWert wert(String schluessel, String? neu, {String? schritt}) {
        final s = paket.artikel.single.schrittMit(schritt ?? 's1')!;
        final f = s.feldMit(schluessel)!;
        return GeaenderterWert(
          artikelId: 'a1',
          schrittId: s.id,
          schluessel: schluessel,
          art: f.art,
          name: f.name,
          alt: f.wert,
          neu: neu,
          kuerzel: 'AB',
          erfasstAm: DateTime(2026, 11, 10, 9),
        );
      }

      // Am PC ändert sich inzwischen der Darm.
      await (db.update(db.productStepParameters)
            ..where((p) => p.id.equals('x2')))
          .write(
        const ProductStepParametersCompanion(wert: Value('Kaliber 28')),
      );

      final ergebnis = ErfassungsErgebnis(
        paketId: paket.id,
        erstellt: DateTime(2026, 11, 10, 18),
        produktionen: [
          ErfassteProduktion(
            produktionId: 't1',
            artikelId: 'a1',
            artikel: 'Grillwurst',
            datum: dienstag,
            rohKg: 510,
            fleischKg: 450,
            fertigKg: 408,
            start: '06:00',
            ende: '14:30',
            endeVpk: '15:10',
            charge: 'L1',
            kuerzel: 'AB',
            erfasstAm: DateTime(2026, 11, 10, 14, 35),
          ),
          ErfassteProduktion(
            produktionId: 'weg',
            artikelId: 'gibt-es-nicht',
            artikel: 'Gelöscht',
            datum: dienstag,
            rohKg: 10,
            erfasstAm: DateTime(2026, 11, 10, 14, 35),
          ),
        ],
        werte: [
          wert(steckbriefSchluessel('Füllgewicht'), '250'),
          wert(steckbriefSchluessel('Programm'), 'P4'),
          wert(parameterSchluessel('x2'), 'Kaliber 30'),
          wert(parameterSchluessel('x3'), 'A'),
          wert(kNotizSchluessel, 'Band langsam anfahren'),
          wert(plattenSchluessel('Platte Oben 1'), '', schritt: 's2'),
          wert(plattenSchluessel('Platte Unten 3'), '175', schritt: 's2'),
          GeaenderterWert(
            artikelId: 'a1',
            schrittId: 'weg',
            schluessel: 'n',
            art: FeldArt.notiz,
            name: 'Notiz',
            neu: 'x',
            erfasstAm: DateTime(2026, 11, 10, 9),
          ),
        ],
      );
      expect(fuellen.feldMit(parameterSchluessel('x2'))!.wert, 'Kaliber 26');

      final v = await dienst.vorschau(ergebnis);
      expect(
        [for (final p in v.produktionen) p.stand],
        [ProduktionStand.neu, ProduktionStand.artikelFehlt],
      );
      expect(v.produktionen.first.artikel, '4711 · Grillwurst');
      expect(
        [for (final w in v.werte) w.stand],
        [
          WertStand.neu, // 250: über der weichen Grenze, geht mit Warnung
          WertStand.neu,
          WertStand.konflikt,
          WertStand.gleich,
          WertStand.neu,
          WertStand.neu,
          WertStand.neu,
          WertStand.fehlt,
        ],
      );
      expect(v.werte.first.hinweis, contains('Ungewöhnlich hoch'));
      expect(v.werte[2].amPc, 'Kaliber 28');
      expect(v.werte[2].vorgewaehlt, isFalse);

      final bericht = await dienst.uebernehmen(
        produktionen: v.produktionen.where((p) => p.vorgewaehlt),
        werte: v.werte.where((w) => w.vorgewaehlt),
      );
      expect(bericht, (produktionen: 1, werte: 5, fotos: 0, schritte: 0));

      final h = (await db.select(db.productionHistory).get()).single;
      expect(
        (
          h.productId,
          h.datum,
          h.kgRohware,
          h.kgFleischeinwaage,
          h.kgFertigware
        ),
        ('a1', dienstag, 510.0, 450.0, 408.0),
      );
      // Die Leistung zählt bis Ende Auflegen; Ende VPK steht nur da.
      expect(h.produktionszeitMinuten, 510);
      expect((h.startzeit, h.endzeit, h.endeVpk), ('06:00', '14:30', '15:10'));
      expect(h.verlustAnteil, closeTo(0.2, 1e-9));
      expect(h.notizen, 'Charge L1 · erfasst von AB');

      final s1 = {for (final p in await zeilen('s1')) p.parameterName: p};
      expect(s1['Füllgewicht']!.wert, '250');
      // Neue Steckbrief-Zeile in der Gruppe, die der Schritt benutzt.
      expect(
        (s1['Programm']!.wert, s1['Programm']!.parameterGruppe),
        ('P4', 'FÜLLEN'),
      );
      expect(s1['Darm']!.wert, 'Kaliber 28');
      expect(
        (
          s1[kMaschinenNotizParam]!.wert,
          s1[kMaschinenNotizParam]!.parameterGruppe,
        ),
        ('Band langsam anfahren', kMaschinenNotizGruppe),
      );
      final s2 = {for (final p in await zeilen('s2')) p.parameterName: p};
      expect(s2['Platte Oben 1']!.wert, isNull);
      expect(
        (s2['Platte Unten 3']!.wert, s2['Platte Unten 3']!.parameterGruppe),
        ('175', kPlattenGruppeBrat),
      );

      // Noch einmal einlesen: nichts ist mehr vorgewählt.
      final nochmal = await dienst.vorschau(ergebnis);
      expect(nochmal.produktionen.first.stand, ProduktionStand.schonErfasst);
      expect(nochmal.produktionen.where((p) => p.vorgewaehlt), isEmpty);
      expect(nochmal.werte.where((w) => w.vorgewaehlt), isEmpty);
      // Und im nächsten Paket fehlt die erfasste Produktion.
      final danach = await dienst.paketErstellen(
        von: DateTime(2026, 11, 9),
        bis: DateTime(2026, 11, 15),
      );
      expect(danach.produktionen, isEmpty);
    });

    test('harte Grenze und unstimmige Zahlen: wird nicht übernommen', () async {
      final ergebnis = ErfassungsErgebnis(
        paketId: 'p',
        erstellt: DateTime(2026, 11, 10, 18),
        produktionen: [
          ErfassteProduktion(
            produktionId: 't',
            artikelId: 'a1',
            artikel: 'Grillwurst',
            datum: dienstag,
            rohKg: 100,
            fertigKg: 120,
            erfasstAm: DateTime(2026, 11, 10, 14),
          ),
        ],
        werte: [
          GeaenderterWert(
            artikelId: 'a1',
            schrittId: 's1',
            schluessel: steckbriefSchluessel('Füllgewicht'),
            art: FeldArt.steckbrief,
            name: 'Füllgewicht',
            alt: '120',
            neu: '900',
            erfasstAm: DateTime(2026, 11, 10, 9),
          ),
        ],
      );
      final v = await dienst.vorschau(ergebnis);
      expect(v.produktionen.single.stand, ProduktionStand.fehlerhaft);
      expect(v.werte.single.stand, WertStand.blockiert);
      expect(v.werte.single.hinweis, contains('Obergrenze'));
      // Auch angehakt geht es nicht.
      final bericht = await dienst.uebernehmen(
        produktionen: v.produktionen,
        werte: v.werte,
      );
      expect(bericht, (produktionen: 0, werte: 0, fotos: 0, schritte: 0));
      expect(await db.select(db.productionHistory).get(), isEmpty);
    });

    group('Maschinen in der Kette', () {
      final am = DateTime(2026, 11, 10, 9);

      Future<List<(String, int, String?)>> kette(String productId) async => [
            for (final s in await (db.select(db.productSteps)
                  ..where((s) => s.productId.equals(productId))
                  ..where((s) => s.deletedAt.isNull())
                  ..orderBy([(s) => OrderingTerm.asc(s.reihenfolge)]))
                .get())
              (s.id, s.reihenfolge, s.maschineId),
          ];

      Future<void> kutter() async {
        await seedAnlage(
          db,
          id: 'm3',
          name: 'Kutter Test',
          abteilung: 'kutterabteilung',
        );
        await db.into(db.machineParameterDefs).insert(
              MachineParameterDefsCompanion.insert(
                id: 'd-k',
                maschineId: 'm3',
                parameterName: 'Messerdrehzahl',
                einheit: const Value('U/min'),
              ),
            );
      }

      NeuerSchritt neuer(
        String id, {
        String? nach,
        String maschineId = 'm3',
        String artikelId = 'a1',
      }) =>
          NeuerSchritt(
            id: id,
            artikelId: artikelId,
            maschineId: maschineId,
            maschine: 'Kutter Test',
            abteilung: 'kutterabteilung',
            nachSchrittId: nach,
            kuerzel: 'AB',
            erfasstAm: am,
          );

      test('die Erfahrung im Paket: wie die Planung die Dauer rechnet',
          () async {
        Future<void> erfasst(
          String id,
          String productId,
          DateTime datum, {
          double? kg,
          double? minuten,
        }) =>
            db.into(db.productionHistory).insert(
                  ProductionHistoryCompanion.insert(
                    id: id,
                    productId: productId,
                    datum: datum,
                    kgRohware: Value(kg),
                    produktionszeitMinuten: Value(minuten),
                  ),
                );
        // a1: zweimal mit Menge und Zeit — Ø 900 kg in 3 h —, einmal ohne
        // Zeit (zählt nicht). a2: nur ohne Menge.
        await erfasst('h1', 'a1', DateTime(2026, 11, 2), kg: 800, minuten: 160);
        await erfasst(
          'h2',
          'a1',
          DateTime(2026, 11, 3),
          kg: 1000,
          minuten: 200,
        );
        await erfasst('h3', 'a1', DateTime(2026, 11, 4), kg: 500);
        await erfasst('h4', 'a2', DateTime(2026, 11, 4), minuten: 60);

        final paket = ErfassungsPaket.ausText(
          (await dienst.paketErstellen(
            von: DateTime(2026, 11, 9),
            bis: DateTime(2026, 11, 15),
          ))
              .alsText(),
        );
        final e = paket.erfahrungFuer('a1')!;
        expect((e.mengeKg, e.minuten, e.anzahl), (900.0, 180.0, 2));
        expect(e.kgProStunde, closeTo(300, 1e-9));
        expect(paket.erfahrungFuer('a2'), isNull);
        expect(paket.erfahrungen, hasLength(1));
      });

      test('der Katalog im Paket: je Maschine die Felder eines neuen Schritts',
          () async {
        await kutter();
        final paket = await dienst.paketErstellen(
          von: DateTime(2026, 11, 9),
          bis: DateTime(2026, 11, 15),
        );
        final wieder = ErfassungsPaket.ausText(paket.alsText());
        expect(
          [for (final m in wieder.maschinen) (m.id, m.abteilungName)],
          [
            ('m2', 'Wurstküche'),
            ('m3', 'Kutterabteilung'),
            ('m1', 'Bratstraße'),
          ],
        );
        final k = wieder.maschineMit('m3')!;
        expect(
          [for (final f in k.felder) (f.art, f.name, f.wert)],
          [
            (FeldArt.steckbrief, 'Messerdrehzahl', null),
            (FeldArt.notiz, 'Maschineneinstellungen (Notiz)', null),
          ],
        );
        // Die Bratstraße bringt ihre Platten mit — leer.
        final brat = wieder.maschineMit('m1')!;
        expect(brat.felder, hasLength(21));
        expect(brat.felder.every((f) => f.wert == null), isTrue);
      });

      test(
          'dazu, weg und Werte am neuen Schritt — zweimal einlesen schadet '
          'nicht', () async {
        await kutter();
        // Zwischen Füller und Bratstraße ein Kutter, danach ein zweiter
        // neuer Schritt direkt hinter ihm; die Bratstraße fällt weg.
        final ergebnis = ErfassungsErgebnis(
          paketId: 'p',
          erstellt: DateTime(2026, 11, 10, 18),
          neueSchritte: [
            neuer('n1', nach: 's1'),
            neuer('n2', nach: 'n1', maschineId: 'm2'),
          ],
          entfernteSchritte: [
            EntfernterSchritt(
              artikelId: 'a1',
              schrittId: 's2',
              anlage: 'Bratstraße Test',
              erfasstAm: am,
            ),
          ],
          werte: [
            GeaenderterWert(
              artikelId: 'a1',
              schrittId: 'n1',
              schluessel: steckbriefSchluessel('Messerdrehzahl'),
              art: FeldArt.steckbrief,
              name: 'Messerdrehzahl',
              neu: '3000',
              erfasstAm: am,
            ),
          ],
        );
        final v = await dienst.vorschau(ergebnis);
        expect(
          [for (final k in v.schritte) (k.stand, k.text)],
          [
            (SchrittStand.entfernen, 'Bratstraße Test entfernen'),
            (SchrittStand.neu, 'Kutter Test dazu — nach Füller Test'),
            (SchrittStand.neu, 'Füller Test dazu — nach Kutter Test'),
          ],
        );
        expect(v.werte.single.stand, WertStand.neu);
        expect(v.werte.single.schritt, 'Kutter Test');

        final bericht = await dienst.uebernehmen(
          produktionen: v.produktionen,
          werte: v.werte,
          schritte: v.schritte,
        );
        expect(bericht, (produktionen: 0, werte: 1, fotos: 0, schritte: 3));
        expect(await kette('a1'), [
          ('s1', 1, 'm2'),
          ('n1', 2, 'm3'),
          ('n2', 3, 'm2'),
        ]);
        final n1 = await (db.select(db.productSteps)
              ..where((s) => s.id.equals('n1')))
            .getSingle();
        expect(n1.abteilung, 'kutterabteilung');
        expect(
          [for (final z in await zeilen('n1')) (z.parameterName, z.wert)],
          [('Messerdrehzahl', '3000')],
        );

        // Noch einmal dieselbe Datei: nichts mehr zu tun.
        final nochmal = await dienst.vorschau(ergebnis);
        expect(
          [for (final k in nochmal.schritte) k.stand],
          [
            SchrittStand.schonEntfernt,
            SchrittStand.schonDa,
            SchrittStand.schonDa,
          ],
        );
        expect(nochmal.werte.single.stand, WertStand.gleich);
        final zweiter = await dienst.uebernehmen(
          produktionen: nochmal.produktionen,
          werte: nochmal.werte,
          schritte: nochmal.schritte,
        );
        expect(zweiter.schritte, 0);
        expect(await kette('a1'), hasLength(3));
      });

      test('ohne den neuen Schritt kommen auch seine Werte nicht', () async {
        await kutter();
        final ergebnis = ErfassungsErgebnis(
          paketId: 'p',
          erstellt: DateTime(2026, 11, 10, 18),
          neueSchritte: [neuer('n1', nach: 's1')],
          werte: [
            GeaenderterWert(
              artikelId: 'a1',
              schrittId: 'n1',
              schluessel: kNotizSchluessel,
              art: FeldArt.notiz,
              name: 'Notiz',
              neu: 'neu',
              erfasstAm: am,
            ),
          ],
        );
        final v = await dienst.vorschau(ergebnis);
        final bericht = await dienst.uebernehmen(
          produktionen: const [],
          werte: v.werte,
        );
        expect(bericht.werte, 0);
        expect(await kette('a1'), hasLength(2));
        expect(await zeilen('n1'), isEmpty);
      });

      test('vorn, ohne Vorgänger und was nicht geht', () async {
        await kutter();
        // Die Maschine m2 ist inzwischen aus dem Katalog gelöscht.
        await (db.update(db.machines)..where((m) => m.id.equals('m2')))
            .write(MachinesCompanion(deletedAt: Value(DateTime(2026, 11))));
        final ergebnis = ErfassungsErgebnis(
          paketId: 'p',
          erstellt: DateTime(2026, 11, 10, 18),
          neueSchritte: [
            neuer('vorn'),
            // Den Vorgänger gibt es im Planer nicht: ans Ende seiner
            // Abteilung — hinter den Kutter, der eben vorn dazukam.
            neuer('weg', nach: 'gibt-es-nicht'),
            neuer('geloescht', nach: 's1', maschineId: 'm2'),
            neuer('fremd', artikelId: 'fehlt'),
          ],
        );
        final v = await dienst.vorschau(ergebnis);
        expect(
          [for (final k in v.schritte) k.stand],
          [
            SchrittStand.neu,
            SchrittStand.neu,
            SchrittStand.maschineFehlt,
            SchrittStand.artikelFehlt,
          ],
        );
        expect(v.schritte.first.text, 'Kutter Test dazu — ganz vorn');
        await dienst.uebernehmen(
          produktionen: const [],
          werte: const [],
          schritte: v.schritte,
        );
        expect(
          [for (final s in await kette('a1')) s.$1],
          ['vorn', 'weg', 's1', 's2'],
        );
      });

      test('mehr Schritte, als ein Artikel haben kann: nicht dazu', () async {
        await kutter();
        for (var i = 3; i <= ProzesskettenService.maxSchritte; i++) {
          await seedSchritt(
            db,
            id: 'x$i',
            productId: 'a1',
            reihenfolge: i,
            abteilung: 'verpackung',
          );
        }
        final v = await dienst.vorschau(
          ErfassungsErgebnis(
            paketId: 'p',
            erstellt: DateTime(2026, 11, 10, 18),
            neueSchritte: [neuer('n1', nach: 's1')],
          ),
        );
        expect(v.schritte.single.stand, SchrittStand.zuViele);
        expect(v.schritte.single.moeglich, isFalse);
      });
    });
  });
}
