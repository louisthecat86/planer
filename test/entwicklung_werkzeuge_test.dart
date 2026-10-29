// `show Value`: drift bringt eine eigene Klasse `Column` mit.
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/constants/artikel_merkmale.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/theme/app_theme.dart';
import 'package:produktion_planer/features/entwicklung/daten/entwicklung_repository.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_modell.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_repository.dart';
import 'package:produktion_planer/features/entwicklung/rechenkern/fleisch_optimierung.dart';
import 'package:produktion_planer/features/entwicklung/rechenkern/naehrwert_rundung.dart';
import 'package:produktion_planer/features/entwicklung/rechenkern/rechen_modell.dart';
import 'package:produktion_planer/features/entwicklung/rechenkern/rechenkern.dart';
import 'package:produktion_planer/features/entwicklung/rechenkern/rueckrechnung.dart';
import 'package:produktion_planer/features/entwicklung/rezepturen/fleischanteil_dialog.dart';
import 'package:produktion_planer/features/entwicklung/rezepturen/rezeptur_wahl.dart';
import 'package:produktion_planer/features/entwicklung/werkzeuge/entwicklung_statistik.dart';
import 'package:produktion_planer/features/entwicklung/werkzeuge/rueckrechnung_screen.dart';
import 'package:produktion_planer/features/entwicklung/werkzeuge/werkzeuge_ansicht.dart';

import 'helpers/test_db.dart';

/// Tests für die Werkzeuge der Produktentwicklung: Rückrechnung aus einem
/// Etikett, Fleischanteil einstellen, die Zahlen der Entwicklung und die
/// Fenster dazu. Zutaten, Rezepturen und Projekte sind erfunden.
void main() {
  RechenZutat zutat(
    String name, {
    bool fleisch = false,
    bool wasser = false,
    Tierart? tierart,
    double? fett,
    double? kh,
    double? zucker,
    double? eiweiss,
    double? salz,
  }) =>
      RechenZutat(
        id: name,
        name: name,
        istFleisch: fleisch,
        istWasser: wasser,
        tierart: tierart ?? (fleisch ? Tierart.schwein : null),
        naehrwerte: Naehrwerte(
          fett: fett,
          kohlenhydrate: kh,
          zucker: zucker,
          eiweiss: eiweiss,
          salz: salz,
        ),
      );

  final schwein = zutat('Schweinefleisch', fleisch: true, fett: 25, eiweiss: 17);
  final paniermehl = zutat(
    'Paniermehl',
    kh: 72,
    eiweiss: 11,
    fett: 2,
    zucker: 4,
    salz: 1.2,
  );
  final zwiebeln = zutat('Zwiebeln', kh: 6, zucker: 5, eiweiss: 1.2);
  final wasser = zutat('Trinkwasser', wasser: true);
  final ei = zutat('Vollei', fett: 10, eiweiss: 13);
  final salz = zutat('Speisesalz', salz: 100);
  final gewuerz = zutat('Gewürze', kh: 40, eiweiss: 10, fett: 8);

  /// Gerundet wie auf einem Etikett.
  double etikett(Naehrstoff s, double wert) {
    if (s == Naehrstoff.salz) {
      return double.parse(wert.toStringAsFixed(wert < 1 ? 2 : 1));
    }
    return wert >= 10
        ? wert.roundToDouble()
        : double.parse(wert.toStringAsFixed(1));
  }

  /// Die Nährwerte, die das Etikett einer Rezeptur nennt.
  Naehrwerte etikettVon(RechenRezeptur r) {
    final n = berechne(r).je100g;
    double w(Naehrstoff s) => etikett(s, naehrstoffWert(n, s)!);
    return Naehrwerte(
      fett: w(Naehrstoff.fett),
      kohlenhydrate: w(Naehrstoff.kohlenhydrate),
      zucker: w(Naehrstoff.zucker),
      eiweiss: w(Naehrstoff.eiweiss),
      salz: w(Naehrstoff.salz),
    );
  }

  group('Nichtnegative kleinste Quadrate', () {
    test('wie scipy.optimize.nnls', () {
      final x = nnls(
        const [
          [1, 2, 0.5],
          [0, 1, 1],
          [2, -1, 1],
          [1, 1, 1],
        ],
        const [1, -2, 3, 0.5],
      );
      expect(x[0], closeTo(1.25, 1e-9));
      expect(x[1], closeTo(0, 1e-9));
      expect(x[2], closeTo(0, 1e-9));
    });

    test('negative Lösung wird null, positive bleibt', () {
      expect(
        nnls(
          const [
            [1, 0],
            [0, 1],
          ],
          const [1, -1],
        ),
        [closeTo(1, 1e-12), closeTo(0, 1e-12)],
      );
      expect(
        nnls(
          const [
            [1, 1],
            [1, -1],
            [1, 0],
          ],
          const [2, 0, 1],
        ),
        [closeTo(1, 1e-9), closeTo(1, 1e-9)],
      );
    });
  });

  group('Toleranzen für Nährwertangaben', () {
    test('nach dem Leitfaden der EU-Kommission', () {
      expect(naehrwertToleranz(Naehrstoff.fett, 5), 1.5);
      expect(naehrwertToleranz(Naehrstoff.fett, 20), closeTo(4, 1e-9));
      expect(naehrwertToleranz(Naehrstoff.fett, 50), 8);
      expect(naehrwertToleranz(Naehrstoff.eiweiss, 5), 2);
      expect(naehrwertToleranz(Naehrstoff.zucker, 30), closeTo(6, 1e-9));
      expect(naehrwertToleranz(Naehrstoff.gesaettigteFettsaeuren, 3), 0.8);
      expect(
        naehrwertToleranz(Naehrstoff.gesaettigteFettsaeuren, 10),
        closeTo(2, 1e-9),
      );
      expect(naehrwertToleranz(Naehrstoff.salz, 1), 0.375);
      expect(naehrwertToleranz(Naehrstoff.salz, 2), closeTo(0.4, 1e-9));
    });
  });

  group('Rückrechnung', () {
    // Frikadellen: 12 % Garverlust, davon 2 % Fett. Das Wasser steht mit
    // 20 − 12 = 8 kg auf dem Etikett — gleichauf mit den Zwiebeln.
    final wahr = [55.0, 10.0, 8.0, 20.0, 4.0, 1.6, 1.4];
    final liste = [schwein, paniermehl, zwiebeln, wasser, ei, salz, gewuerz];
    final original = RechenRezeptur(
      id: 'o',
      name: 'Frikadelle',
      verlustProzent: 12,
      fettVerlustProzent: 2,
      verlustart: Verlustart.garen,
      positionen: [
        for (var i = 0; i < liste.length; i++)
          RechenPosition.zutat(liste[i], mengeKg: wahr[i]),
      ],
    );
    final ziel = etikettVon(original);

    RueckrechnungsErgebnis rechne({
      double? quidFleisch,
      bool reihenfolge = true,
    }) =>
        rueckrechnen(
          zutaten: [
            for (final z in liste)
              RueckZutat(z, quidProzent: z == schwein ? quidFleisch : null),
          ],
          ziel: ziel,
          verlustart: Verlustart.garen,
          verlustProzent: 12,
          fettVerlustProzent: 2,
          reihenfolge: reihenfolge,
        );

    test('trifft das Etikett und findet die Rezeptur ungefähr wieder', () {
      // „Schweinefleisch (62,5 %)": 55 kg aus 88 kg Enderzeugnis.
      final e = rechne(quidFleisch: 62.5);
      expect(e.passt, isTrue, reason: '${e.vergleich.map((v) => v.abweichung)}');
      expect(e.mengenKg.fold<double>(0, (s, w) => s + w), closeTo(100, 1e-6));
      expect(e.mengenKg[0], closeTo(55, 1e-6));
      for (var i = 0; i < wahr.length; i++) {
        expect(e.mengenKg[i], closeTo(wahr[i], 1.5), reason: liste[i].name);
      }
      expect(e.ergebnis.zutatenliste, startsWith('Schweinefleisch (62,5 %)'));
    });

    test('gleiche Eingabe, gleiches Ergebnis', () {
      expect(rechne(quidFleisch: 62.5).mengenKg, rechne(quidFleisch: 62.5).mengenKg);
      expect(rechne().mengenKg, rechne().mengenKg);
    });

    test('ohne Mengenangabe und ohne Reihenfolge trifft es auch', () {
      expect(rechne().passt, isTrue);
      expect(rechne(reihenfolge: false).passt, isTrue);
    });

    test('die Reihenfolge der Liste bleibt, auch wenn sie stört', () {
      // Laut Liste mehr Paniermehl als Fleisch — die Nährwerte sagen das
      // Gegenteil. Die Liste gewinnt, die Abweichung wird gemeldet.
      final e = rueckrechnen(
        zutaten: [RueckZutat(paniermehl), RueckZutat(schwein), RueckZutat(salz)],
        ziel: const Naehrwerte(fett: 20, eiweiss: 15, kohlenhydrate: 7),
      );
      expect(e.mengenKg[0], greaterThanOrEqualTo(e.mengenKg[1] - 1e-6));
      expect(e.mengenKg[1], greaterThanOrEqualTo(e.mengenKg[2] - 1e-6));
      expect(e.passt, isFalse);
      expect(e.hinweise.join('\n'), contains('zu wenig'));
    });

    test('Stücke derselben Tierart sind eine Zeile', () {
      final schulter = zutat(
        'Schweineschulter',
        fleisch: true,
        fett: 20,
        eiweiss: 18,
      );
      final bauch = zutat('Schweinebauch', fleisch: true, fett: 35, eiweiss: 14);
      final e = rueckrechnen(
        zutaten: [
          RueckZutat(schulter, quidProzent: 80),
          RueckZutat(bauch),
          RueckZutat(wasser),
          RueckZutat(salz),
        ],
        // Aus 50 kg Schulter, 30 kg Bauch, 18,2 kg Wasser, 1,8 kg Salz.
        ziel: const Naehrwerte(fett: 20.5, eiweiss: 13.2, salz: 1.8),
      );
      // Die Mengenangabe gilt für Schulter und Bauch zusammen.
      expect(e.mengenKg[0] + e.mengenKg[1], closeTo(80, 1e-6));
      expect(e.mengenKg.fold<double>(0, (s, w) => s + w), closeTo(100, 1e-6));
      expect(e.passt, isTrue);
      expect(e.ergebnis.zutatenliste, startsWith('Schweinefleisch (80,0 %)'));
    });

    test('Mengenangabe bei Fett über dem Grenzwert: gemeint ist das Fleisch',
        () {
      // Schweinebauch mit 40 % Fett: Von 70 kg zählen nur 60 kg als
      // Fleisch, 10 kg stehen als „Speck" da. „Schweinefleisch (60 %)"
      // verlangt also 70 kg Bauch.
      final bauch = zutat('Schweinebauch', fleisch: true, fett: 40, eiweiss: 14);
      final e = rueckrechnen(
        zutaten: [
          RueckZutat(bauch, quidProzent: 60),
          RueckZutat(wasser),
          RueckZutat(salz),
        ],
        ziel: const Naehrwerte(salz: 2),
      );
      expect(e.mengenKg[0], closeTo(70, 1e-3));
      expect(e.ergebnis.zutatenliste, startsWith('Schweinefleisch (60,0 %)'));
      expect(e.hinweise.any((h) => h.contains('auf dem Etikett')), isFalse);
    });

    test('Fehler und Hinweise', () {
      expect(
        () => rueckrechnen(zutaten: const [], ziel: const Naehrwerte()),
        throwsArgumentError,
      );
      expect(
        () => rueckrechnen(
          zutaten: [
            RueckZutat(schwein, quidProzent: 70),
            RueckZutat(paniermehl, quidProzent: 40),
          ],
          ziel: const Naehrwerte(),
        ),
        throwsArgumentError,
      );
      final ohneZiel = rueckrechnen(
        zutaten: [RueckZutat(schwein), RueckZutat(salz)],
        ziel: const Naehrwerte(),
      );
      expect(ohneZiel.hinweise.first, contains('nur aus der Reihenfolge'));
      expect(ohneZiel.mengenKg[0], greaterThan(ohneZiel.mengenKg[1]));

      final unbekannt = rueckrechnen(
        zutaten: [RueckZutat(schwein), RueckZutat(zutat('Geheimgewürz'))],
        ziel: const Naehrwerte(fett: 20),
      );
      expect(
        unbekannt.hinweise.join('\n'),
        contains('Ohne Nährwerte im Katalog — zählen als 0: Geheimgewürz.'),
      );
    });
  });

  group('Fleischanteil einstellen', () {
    final r = RechenRezeptur(
      id: 'b',
      name: 'Brühwurst',
      verlustProzent: 10,
      verlustart: Verlustart.garen,
      positionen: [
        RechenPosition.zutat(schwein, mengeKg: 60),
        RechenPosition.zutat(zutat('Scherbeneis', kh: 0), mengeKg: 30),
        RechenPosition.zutat(salz, mengeKg: 2),
        RechenPosition.zutat(gewuerz, mengeKg: 8),
      ],
    );
    final rollen = [for (final p in r.positionen) standardRolle(p)];

    double summe(RechenRezeptur x) =>
        x.positionen.fold<double>(0, (s, p) => s + p.mengeKg);

    test('Rollen nach Art der Zeile', () {
      expect(rollen, [
        OptimierRolle.ziel,
        OptimierRolle.ausgleich,
        OptimierRolle.fest,
        OptimierRolle.fest,
      ]);
      expect(
        standardRolle(RechenPosition.zutat(wasser, mengeKg: 1)),
        OptimierRolle.ausgleich,
      );
      expect(
        standardRolle(RechenPosition.zutat(zutat('Reis'), mengeKg: 1)),
        OptimierRolle.fest,
      );
      expect(
        standardRolle(RechenPosition.zutat(zutat('Eiweißpulver'), mengeKg: 1)),
        OptimierRolle.fest,
      );
    });

    test('im Rohgemisch: genau, Rohmasse bleibt', () {
      final e = fleischanteilEinstellen(r, rollen, 70, mass: FleischMass.roh);
      expect(e.vorherProzent, closeTo(60, 1e-9));
      expect(e.erreicht, isTrue);
      expect(e.mengenKg[0], closeTo(70, 1e-6));
      expect(e.mengenKg[1], closeTo(20, 1e-6));
      expect(e.mengenKg[2], 2);
      expect(e.mengenKg[3], 8);
      expect(summe(e.rezeptur), closeTo(100, 1e-9));
      expect(e.hinweis, isNull);
    });

    test('laut Etikett: der Rechenkern bestätigt den Zielwert', () {
      final vorher = berechne(r).fleischanteilProzent;
      final ziel = vorher + 5;
      final e = fleischanteilEinstellen(r, rollen, ziel);
      expect(e.erreicht, isTrue);
      expect(berechne(e.rezeptur).fleischanteilProzent, closeTo(ziel, 0.01));
      expect(summe(e.rezeptur), closeTo(100, 1e-6));
      expect(e.mengenKg[2], 2);
    });

    test('nicht erreichbar: so weit es geht, mit Hinweis', () {
      final e = fleischanteilEinstellen(r, rollen, 99, mass: FleischMass.roh);
      expect(e.erreicht, isFalse);
      expect(e.mengenKg[1], closeTo(0, 1e-9));
      expect(e.erreichtProzent, closeTo(90, 1e-6));
      expect(e.hinweis, contains('90,0 %'));
    });

    test('ohne Ausgleich oder ohne Fleisch geht nichts', () {
      final ohneAusgleich = fleischanteilEinstellen(
        r,
        [
          OptimierRolle.ziel,
          OptimierRolle.fest,
          OptimierRolle.fest,
          OptimierRolle.fest,
        ],
        70,
      );
      expect(ohneAusgleich.hinweis, contains('Ausgleichen'));
      expect(ohneAusgleich.mengenKg, [60, 30, 2, 8]);
      final ohneFleisch = fleischanteilEinstellen(
        r,
        List.filled(4, OptimierRolle.fest),
        70,
      );
      expect(ohneFleisch.hinweis, contains('Fleisch'));
      expect(
        () => fleischanteilEinstellen(r, const [OptimierRolle.ziel], 70),
        throwsArgumentError,
      );
    });
  });

  group('Zahlen der Entwicklung', () {
    final jetzt = DateTime.utc(2026, 10, 20);
    EntwicklungsProjekt projekt(
      String id,
      ProjektStatus status, {
      required DateTime angelegt,
      required DateTime geaendert,
      DateTime? freigegeben,
      Set<String> erledigt = const {},
    }) =>
        EntwicklungsProjekt(
          id: id,
          name: 'Projekt $id',
          status: status.schluessel,
          neuerProzess: false,
          neueZutaten: false,
          checkliste: checklisteZuJson(erledigt),
          freigegebenAm: freigegeben,
          createdAt: angelegt,
          updatedAt: geaendert,
        );
    Rezeptur rezeptur(String id, String? projektId) => Rezeptur(
          id: id,
          name: 'Rezeptur $id',
          projektId: projektId,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        );
    RezepturVersion stand(String id, String rezepturId, String status) =>
        RezepturVersion(
          id: id,
          rezepturId: rezepturId,
          nummer: 1,
          status: status,
          verlustProzent: 0,
          fettVerlustProzent: 0,
          verlustArt: 'keiner',
          createdAt: DateTime.utc(2026, 2),
          updatedAt: DateTime.utc(2026, 2),
        );
    Zutat katalogZutat(
      String name, {
      bool wasser = false,
      double? fett,
      String? allergene,
    }) =>
        Zutat(
          id: name,
          name: name,
          istFleisch: false,
          istWasser: wasser,
          quidPflicht: false,
          fett: fett,
          allergene: allergene,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        );
    ProjektEintrag eintrag(String id, String projektId, DateTime datum) =>
        ProjektEintrag(
          id: id,
          projektId: projektId,
          art: EintragArt.notiz.schluessel,
          titel: 'Notiz',
          datum: datum,
          status: EintragStatus.offen.schluessel,
          createdAt: datum,
          updatedAt: datum,
        );

    final projekte = [
      projekt(
        'p1',
        ProjektStatus.entwicklung,
        angelegt: DateTime.utc(2026, 1, 10),
        geaendert: DateTime.utc(2026, 9, 1),
        // Rezeptur und Nährwerte rechnet die App selbst (F25) — ein alter
        // Haken zählt dort nicht, das Etikett schon.
        erledigt: {'naehrwerteErstellt', 'etikettErstellt', 'unbekannt'},
      ),
      projekt(
        'p2',
        ProjektStatus.validierung,
        angelegt: DateTime.utc(2026, 3, 1),
        geaendert: DateTime.utc(2026, 8, 1),
      ),
      projekt(
        'p3',
        ProjektStatus.produktion,
        angelegt: DateTime.utc(2026, 1, 1),
        geaendert: DateTime.utc(2026, 6, 10),
        freigegeben: DateTime.utc(2026, 6, 10),
      ),
      projekt(
        'p4',
        ProjektStatus.archiviert,
        angelegt: DateTime.utc(2025, 1, 1),
        geaendert: DateTime.utc(2025, 2, 1),
      ),
    ];
    final s = entwicklungsStatistik(
      projekte: projekte,
      rezepturen: [
        rezeptur('r1', 'p1'),
        rezeptur('r2', 'p3'),
        rezeptur('r3', null),
      ],
      versionen: [
        stand('v1', 'r1', VersionStatus.abgeschlossen),
        stand('v2', 'r1', VersionStatus.entwurf),
        stand('v3', 'r2', VersionStatus.abgeschlossen),
        stand('v4', 'r2', VersionStatus.abgeschlossen),
        stand('v5', 'r2', VersionStatus.entwurf),
        // Von einer gelöschten Rezeptur — zählt nicht.
        stand('v6', 'weg', VersionStatus.abgeschlossen),
      ],
      zutaten: [
        katalogZutat('Pfeffer', fett: 3, allergene: kAllergenKeine),
        katalogZutat('Geheimgewürz'),
        katalogZutat('Trinkwasser', wasser: true, allergene: kAllergenKeine),
      ],
      eintraege: [
        eintrag('e1', 'p2', DateTime.utc(2026, 10, 15)),
        eintrag('e2', 'p2', DateTime.utc(2026, 5, 5)),
        eintrag('e3', 'p4', DateTime.utc(2024, 1, 1)),
      ],
      jetzt: jetzt,
    );

    test('Projekte je Stand und Freigaben', () {
      expect(s.projekte, 4);
      expect(s.projekteJeStatus, {
        ProjektStatus.entwicklung: 1,
        ProjektStatus.validierung: 1,
        ProjektStatus.produktion: 1,
        ProjektStatus.eingestellt: 0,
        ProjektStatus.archiviert: 1,
      });
      expect(s.freigaben, 1);
      expect(s.tageBisFreigabe, 160);
      expect(s.staendeBisFreigabe, 3);
    });

    test('aktive Projekte: zuletzt bewegt zuerst, ruhend markiert', () {
      // p2 hat einen Eintrag vom 15.10., p1 ruht seit dem 1.9.
      expect([for (final p in s.aktive) p.projekt.id], ['p2', 'p1']);
      final p1 = s.aktive.last;
      // Rezeptur (Stand 1 abgeschlossen) und Etikett — die Nährwerte nicht:
      // Der Stand hat kein eingefrorenes JSON.
      expect(p1.erledigt, 2);
      expect(p1.punkte, kProjektCheckliste.length);
      expect(p1.checkliste.text, '2 von ${kProjektCheckliste.length}');
      expect(p1.checkliste.punkt('rezepturErstellt')!.erledigt, isTrue);
      expect(p1.checkliste.punkt('naehrwerteErstellt')!.erledigt, isFalse);
      expect(p1.staende, 2);
      expect([for (final p in s.ruhend(jetzt)) p.projekt.id], ['p1']);
    });

    test('Rezepturen, Stände und Lücken im Katalog', () {
      expect(s.rezepturen, 3);
      expect(s.staende, 5);
      expect(s.abgeschlosseneStaende, 3);
      expect(s.rezepturenOhneProjekt, 1);
      expect(s.zutaten, 3);
      expect(s.zutatenOhneNaehrwerte, ['Geheimgewürz']);
      expect(s.zutatenOhneAllergene, ['Geheimgewürz']);
    });

    test('Verlauf der letzten zwölf Monate', () {
      expect(s.verlauf, hasLength(12));
      expect(s.verlauf.first.monat, DateTime(2025, 11));
      expect(s.verlauf.last.monat, DateTime(2026, 10));
      expect(s.verlauf.last.eintraege, 1);
      expect(s.verlauf[6].monat, DateTime(2026, 5));
      expect(s.verlauf[6].eintraege, 1);
      expect(s.verlauf[7].freigaben, 1);
      expect(
        s.verlauf.fold<int>(0, (n, m) => n + m.eintraege),
        2,
      );
    });
  });

  group('Mengen in der Datenbank', () {
    late AppDatabase db;
    late EntwicklungRepository repo;

    setUp(() {
      db = testDatenbank();
      repo = EntwicklungRepository(db);
    });
    tearDown(() => db.close());

    Future<List<String>> zutaten() async => [
          await repo.zutatAnlegen(
            const EntwicklungZutatenCompanion(
              name: Value('Schweinefleisch'),
              istFleisch: Value(true),
              tierart: Value('schwein'),
              fett: Value(25),
              eiweiss: Value(17),
            ),
          ),
          await repo.zutatAnlegen(
            const EntwicklungZutatenCompanion(
              name: Value('Trinkwasser'),
              istWasser: Value(true),
            ),
          ),
        ];

    test('eine Rezeptur aus der Rückrechnung', () async {
      final ids = await zutaten();
      final id = await repo.rezepturMitZeilen(
        name: 'Frikadelle geschätzt',
        beschreibung: 'Aus der Rückrechnung',
        zeilen: [
          (zutatId: ids[0], mengeKg: 70),
          (zutatId: ids[1], mengeKg: 30),
        ],
        verlustProzent: 12,
        fettVerlustProzent: 2,
        verlustArt: 'garen',
      );
      final v = (await repo.neuesteVersion(id))!;
      expect(v.status, VersionStatus.entwurf);
      expect(v.verlustProzent, 12);
      expect(v.verlustArt, 'garen');
      final r = (await repo.rechenRezeptur(v.id))!;
      expect([for (final p in r.positionen) p.mengeKg], [70, 30]);
      expect((await repo.rezeptur(id))!.beschreibung, 'Aus der Rückrechnung');
    });

    test('Mengen setzen: Entwurf ja, abgeschlossen als neuer Stand', () async {
      final ids = await zutaten();
      final id = await repo.rezepturMitZeilen(
        name: 'Brühwurst',
        zeilen: [
          (zutatId: ids[0], mengeKg: 60),
          (zutatId: ids[1], mengeKg: 40),
        ],
      );
      final v1 = (await repo.neuesteVersion(id))!;
      await repo.mengenSetzen(v1.id, [65, 35]);
      expect(
        [for (final p in (await repo.rechenRezeptur(v1.id))!.positionen) p.mengeKg],
        [65, 35],
      );
      await expectLater(repo.mengenSetzen(v1.id, [1]), throwsStateError);

      await repo.versionAbschliessen(v1.id);
      await expectLater(repo.mengenSetzen(v1.id, [70, 30]), throwsStateError);
      final v2 = await repo.standMitMengen(
        id,
        v1.id,
        [70, 30],
        bezeichnung: 'Fleischanteil 70,0 %',
      );
      final neu = (await repo.version(v2))!;
      expect(neu.nummer, 2);
      expect(neu.bezeichnung, 'Fleischanteil 70,0 %');
      expect(
        [for (final p in (await repo.rechenRezeptur(v2))!.positionen) p.mengeKg],
        [70, 30],
      );
      // Der abgeschlossene Stand bleibt.
      expect(
        [for (final p in (await repo.rechenRezeptur(v1.id))!.positionen) p.mengeKg],
        [65, 35],
      );

      // Passen die Zeilen nicht, entsteht gar kein neuer Stand.
      await expectLater(
        repo.standMitMengen(id, v1.id, [1, 2, 3]),
        throwsStateError,
      );
      expect((await repo.neuesteVersion(id))!.nummer, 2);
    });
  });

  group('Fenster', () {
    final zeit = DateTime(2026, 10, 20);

    Future<void> zeige(
      WidgetTester tester,
      Widget seite, {
      List<Override> overrides = const [],
    }) async {
      tester.view.physicalSize = const Size(1500, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(body: seite),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('Werkzeuge mit den Zahlen der Entwicklung', (tester) async {
      await zeige(
        tester,
        const WerkzeugeAnsicht(),
        overrides: [
          projekteProvider.overrideWith(
            (ref) => Stream.value([
              EntwicklungsProjekt(
                id: 'p1',
                name: 'Schnitzel Wiener Art',
                status: ProjektStatus.entwicklung.schluessel,
                neuerProzess: false,
                neueZutaten: false,
                createdAt: zeit,
                updatedAt: zeit,
              ),
            ]),
          ),
          rezepturenProvider.overrideWith((ref) => Stream.value(const [])),
          alleVersionenProvider.overrideWith((ref) => Stream.value(const [])),
          zutatenProvider.overrideWith((ref) => Stream.value(const [])),
          alleEintraegeProvider.overrideWith((ref) => Stream.value(const [])),
        ],
      );
      expect(find.text('Rezeptur rückrechnen'), findsOneWidget);
      expect(find.text('Fleischanteil einstellen'), findsOneWidget);
      expect(find.text('Entwicklung in Zahlen'), findsOneWidget);
      expect(find.text('Schnitzel Wiener Art'), findsOneWidget);
      expect(
        find.text('0 von ${kProjektCheckliste.length}'),
        findsOneWidget,
      );
      expect(
        find.text('Alle Zutaten haben Nährwerte und Allergene.'),
        findsOneWidget,
      );
    });

    testWidgets('Werkzeuge: Fleischanteil — erst die Rezeptur wählen',
        (tester) async {
      RezepturVersion stand(String id, int nummer, String status) =>
          RezepturVersion(
            id: id,
            rezepturId: 'r1',
            nummer: nummer,
            status: status,
            verlustProzent: 10,
            fettVerlustProzent: 0,
            verlustArt: 'garen',
            createdAt: zeit,
            updatedAt: zeit,
          );
      await zeige(
        tester,
        const WerkzeugeAnsicht(),
        overrides: [
          projekteProvider.overrideWith((ref) => Stream.value(const [])),
          rezepturenProvider.overrideWith(
            (ref) => Stream.value([
              Rezeptur(
                id: 'r1',
                name: 'Brühwurst',
                createdAt: zeit,
                updatedAt: zeit,
              ),
              Rezeptur(
                id: 'r2',
                name: 'Leberkäse',
                artikelnummer: '0815',
                createdAt: zeit,
                updatedAt: zeit,
              ),
            ]),
          ),
          alleVersionenProvider.overrideWith(
            (ref) => Stream.value([
              stand('v1', 1, VersionStatus.abgeschlossen),
              stand('v2', 2, VersionStatus.entwurf),
            ]),
          ),
          zutatenProvider.overrideWith((ref) => Stream.value(const [])),
          alleEintraegeProvider.overrideWith((ref) => Stream.value(const [])),
          rechenRezepturProvider.overrideWith(
            (ref, id) async => RechenRezeptur(
              id: 'r1',
              name: 'Brühwurst',
              verlustProzent: 10,
              verlustart: Verlustart.garen,
              positionen: [
                RechenPosition.zutat(schwein, mengeKg: 60),
                RechenPosition.zutat(wasser, mengeKg: 30),
                RechenPosition.zutat(salz, mengeKg: 2),
                RechenPosition.zutat(gewuerz, mengeKg: 8),
              ],
            ),
          ),
        ],
      );
      Future<void> bilder() async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }

      await tester.tap(find.byKey(const ValueKey('werkzeug-fleischanteil')));
      await bilder();
      final wahl = find.byType(RezepturWahlDialog);
      expect(wahl, findsOneWidget);
      // Jede Rezeptur mit ihrem neuesten Stand — ohne Stand nicht wählbar.
      expect(
        find.descendant(of: wahl, matching: find.text('Stand 2 · Entwurf')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: wahl, matching: find.text('Noch kein Stand')),
        findsOneWidget,
      );
      ListTile zeile(String id) => tester.widget<ListTile>(
            find.byKey(ValueKey('rezeptur-wahl-$id')),
          );
      expect(zeile('r1').enabled, isTrue);
      expect(zeile('r2').enabled, isFalse);

      // Gesucht wird nach Name und Artikelnummer.
      final suche = find.byKey(const ValueKey('rezeptur-wahl-suche'));
      await tester.enterText(suche, '0815');
      await tester.pump();
      expect(find.byKey(const ValueKey('rezeptur-wahl-r1')), findsNothing);
      expect(find.byKey(const ValueKey('rezeptur-wahl-r2')), findsOneWidget);
      await tester.enterText(suche, 'brüh');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('rezeptur-wahl-r1')));
      await bilder();

      // Weiter geht es im Fenster zum Einstellen.
      expect(wahl, findsNothing);
      expect(find.byType(FleischanteilDialog), findsOneWidget);
      await tester.tap(find.text('Abbrechen'));
      await bilder();
      expect(find.byType(FleischanteilDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Fleischanteil einstellen: Vorschau und Übernehmen',
        (tester) async {
      final version = RezepturVersion(
        id: 'v1',
        rezepturId: 'r1',
        nummer: 1,
        status: VersionStatus.entwurf,
        verlustProzent: 10,
        fettVerlustProzent: 0,
        verlustArt: 'garen',
        createdAt: zeit,
        updatedAt: zeit,
      );
      await zeige(
        tester,
        FleischanteilDialog(rezepturId: 'r1', version: version),
        overrides: [
          rechenRezepturProvider.overrideWith(
            (ref, id) async => RechenRezeptur(
              id: 'r1',
              name: 'Brühwurst',
              verlustProzent: 10,
              verlustart: Verlustart.garen,
              positionen: [
                RechenPosition.zutat(schwein, mengeKg: 60),
                RechenPosition.zutat(wasser, mengeKg: 30),
                RechenPosition.zutat(salz, mengeKg: 2),
                RechenPosition.zutat(gewuerz, mengeKg: 8),
              ],
            ),
          ),
        ],
      );
      expect(find.text('Fleischanteil einstellen'), findsOneWidget);
      expect(find.text('Schweinefleisch'), findsWidgets);
      FilledButton knopf() => tester.widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Übernehmen'),
          );
      // Ohne Ziel ändert sich nichts.
      expect(knopf().onPressed, isNull);

      await tester.tap(find.text('Fleisch im Rohgemisch'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '70');
      await tester.pump();
      expect(find.text('Fleisch im Rohgemisch: 60,0 % → 70,0 %'), findsOneWidget);
      expect(find.text('70'), findsWidgets);
      expect(knopf().onPressed, isNotNull);
    });

    testWidgets('Rückrechnung: Zutaten wählen, rechnen, Ergebnis',
        (tester) async {
      Zutat katalogZutat(
        String id,
        String name, {
        bool fleisch = false,
        double? fett,
        double? eiweiss,
        double? salz,
      }) =>
          Zutat(
            id: id,
            name: name,
            istFleisch: fleisch,
            istWasser: false,
            quidPflicht: false,
            tierart: fleisch ? 'schwein' : null,
            fett: fett,
            eiweiss: eiweiss,
            salz: salz,
            createdAt: zeit,
            updatedAt: zeit,
          );
      final katalog = [
        katalogZutat('z1', 'Schweinefleisch', fleisch: true, fett: 25, eiweiss: 17),
        katalogZutat('z2', 'Speisesalz', salz: 100),
      ];
      await zeige(
        tester,
        const RueckrechnungScreen(),
        overrides: [
          zutatenProvider.overrideWith((ref) => Stream.value(katalog)),
          alleZutatenProvider.overrideWith(
            (ref) => Stream.value({for (final z in katalog) z.id: z}),
          ),
          rezepturenProvider.overrideWith((ref) => Stream.value(const [])),
        ],
      );
      expect(find.text('Noch keine Zutat — aus dem Katalog hinzufügen.'), findsOneWidget);

      for (final name in ['Schweinefleisch', 'Speisesalz']) {
        await tester.tap(find.text('Zutat hinzufügen'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Zutat wählen'), findsOneWidget);
        // Rezepturen stehen hier nicht zur Wahl.
        expect(find.textContaining('REZEPTUREN'), findsNothing);
        await tester.tap(find.widgetWithText(ListTile, name));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Fett'), '24,5');
      await tester.enterText(find.widgetWithText(TextField, 'Salz'), '2');
      await tester.pump();
      await tester.tap(find.text('Rückrechnen').last);
      await tester.pump();

      expect(find.text('Als Rezeptur speichern…'), findsOneWidget);
      expect(find.textContaining('Mengen je 100 kg Rohmasse'), findsOneWidget);
      expect(
        find.text('Alle Nährwerte liegen innerhalb der Toleranzen für '
            'Nährwertangaben.'),
        findsOneWidget,
      );
      // Rund 98 kg Fleisch und 2 kg Salz.
      expect(find.textContaining(RegExp(r'^9[78](,\d+)?$')), findsOneWidget);
    });
  });
}
