import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/features/entwicklung/daten/entwicklung_repository.dart';
import 'package:produktion_planer/features/entwicklung/haccp/prozess_modell.dart';
import 'package:produktion_planer/features/entwicklung/haccp/prozess_vorlage.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_checkliste.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_modell.dart';
import 'package:produktion_planer/features/entwicklung/rechenkern/rechen_modell.dart';

/// Tests für die Projekt-Checkliste, die sich selbst rechnet (F25), und
/// den Eintragsstatus mit nur noch offen und erledigt (F24). Rein, ohne
/// Datenbank. Alles erfunden.
void main() {
  final zeit = DateTime(2026, 10, 1);

  EntwicklungsProjekt projekt({
    String id = 'p1',
    Set<String> haken = const {},
    String? artikelId,
    String? artikelnummer,
    DateTime? freigegebenAm,
    String? freigabeVersionId,
    Sensorik sensorik = const Sensorik(),
    String? prozess,
    Map<String, LmivStand> etikett = const {},
  }) =>
      EntwicklungsProjekt(
        id: id,
        name: 'Grillwurst Testart',
        status: ProjektStatus.entwicklung.schluessel,
        neuerProzess: false,
        neueZutaten: false,
        artikelId: artikelId,
        artikelnummer: artikelnummer,
        freigegebenAm: freigegebenAm,
        freigabeVersionId: freigabeVersionId,
        checkliste: checklisteZuJson(haken),
        etikettCheckliste: lmivZuJson(etikett),
        sensorik: sensorik.alsJson(),
        prozess: prozess,
        createdAt: zeit,
        updatedAt: zeit,
      );

  Rezeptur rezeptur(
    String id, {
    String? projektId = 'p1',
    String? name,
    bool geloescht = false,
  }) =>
      Rezeptur(
        id: id,
        name: name ?? 'Grillwurst',
        projektId: projektId,
        createdAt: zeit,
        updatedAt: zeit,
        deletedAt: geloescht ? zeit : null,
      );

  const fleisch = RechenZutat(
    id: 'z1',
    name: 'Schweinefleisch',
    istFleisch: true,
    tierart: Tierart.schwein,
    naehrwerte: Naehrwerte(fett: 20, eiweiss: 18),
  );
  const gewuerz = RechenZutat(id: 'z2', name: 'Gewürz Testmischung');
  const wasser = RechenZutat(id: 'z3', name: 'Trinkwasser', istWasser: true);

  /// Ein eingefrorener Stand mit diesen Zeilen.
  String eingefroren(List<RechenPosition> positionen) => jsonEncode(
        RechenRezeptur(id: 'r', name: 'Grillwurst', positionen: positionen)
            .toJson(),
      );

  RezepturVersion stand(
    String id, {
    String rezepturId = 'r1',
    int nummer = 1,
    bool abgeschlossen = true,
    DateTime? am,
    String? json,
  }) =>
      RezepturVersion(
        id: id,
        rezepturId: rezepturId,
        nummer: nummer,
        status:
            abgeschlossen ? VersionStatus.abgeschlossen : VersionStatus.entwurf,
        verlustProzent: 0,
        fettVerlustProzent: 0,
        verlustArt: 'keiner',
        stand: abgeschlossen
            ? json ??
                eingefroren(const [
                  RechenPosition.zutat(fleisch, mengeKg: 9),
                  RechenPosition.zutat(wasser, mengeKg: 1),
                ])
            : null,
        abgeschlossenAm: abgeschlossen ? (am ?? zeit) : null,
        createdAt: zeit,
        updatedAt: am ?? zeit,
      );

  group('Eintragsstatus (F24)', () {
    test('nur offen und erledigt; frühere Werte gelten als erledigt', () {
      expect(EintragStatus.values, [
        EintragStatus.offen,
        EintragStatus.erledigt,
      ]);
      const frueher = [
        'erledigt',
        'erhalten',
        'ok',
        'OK ',
        'received',
        'completed',
      ];
      for (final alt in frueher) {
        expect(EintragStatus.aus(alt), EintragStatus.erledigt, reason: alt);
      }
      for (final alt in ['offen', 'pending', '', null]) {
        expect(EintragStatus.aus(alt), EintragStatus.offen, reason: alt);
      }
      expect(EintragStatus.offen.umgekehrt, EintragStatus.erledigt);
      expect(EintragStatus.erledigt.umgekehrt, EintragStatus.offen);
    });
  });

  group('Etiketten-Checkliste (F28)', () {
    test('abgehakt, trifft nicht zu, offen — hin und zurück', () {
      final staende = {
        'zutaten': LmivStand.erledigt,
        'schutzgas': LmivStand.trifftNichtZu,
        'mhd': LmivStand.offen,
      };
      final json = lmivZuJson(staende);
      expect(json, '{"schutzgas":"trifftNichtZu","zutaten":true}');
      expect(lmivAus(json), {
        'schutzgas': LmivStand.trifftNichtZu,
        'zutaten': LmivStand.erledigt,
      });
      expect(lmivStand(lmivAus(json), 'mhd'), LmivStand.offen);
      // Alles offen: nichts zu speichern.
      expect(lmivZuJson(const {'mhd': LmivStand.offen}), isNull);
      expect(lmivZuJson(const {}), isNull);
      expect(LmivStand.trifftNichtZu.geprueft, isTrue);
      expect(LmivStand.offen.geprueft, isFalse);
    });

    test('frühere Listen und Unbekanntes', () {
      // Wie bisher (und aus der Suite): nur Haken.
      expect(lmivAus('{"zutaten":true,"mhd":false}'), {
        'zutaten': LmivStand.erledigt,
      });
      expect(lmivAus('{"zutaten":"irgendwas","mhd":1}'), isEmpty);
      expect(lmivAus('kaputt'), isEmpty);
      expect(lmivAus('[1,2]'), isEmpty);
      expect(lmivAus(null), isEmpty);
      // Wer nur Haken liest, sieht „trifft nicht zu" als offen.
      expect(
        checklisteAus(lmivZuJson(const {'quid': LmivStand.trifftNichtZu})),
        isEmpty,
      );
    });
  });

  group('Checkliste (F25)', () {
    String? text(ProjektCheckStand s, String schluessel) =>
        s.punkt(schluessel)!.text;
    bool erledigt(ProjektCheckStand s, String schluessel) =>
        s.punkt(schluessel)!.erledigt;

    test('ein neues Projekt: alles offen, mit dem Weg dorthin', () {
      final s = projektCheckStand(
        projekt: projekt(),
        rezepturen: const [],
        versionen: const [],
      );
      expect(s.text, '0 von 8');
      expect([for (final p in s.punkte) p.punkt.schluessel], [
        for (final c in kProjektCheckliste) c.schluessel,
      ]);
      expect(text(s, 'artikelAngelegt'), 'Kommt mit der Freigabe');
      expect(text(s, 'rezepturErstellt'), 'Noch keine Rezeptur');
      expect(
        text(s, 'naehrwerteErstellt'),
        'Kommt mit dem ersten abgeschlossenen Stand',
      );
      expect(
        text(s, 'spezifikationErstellt'),
        'Im Reiter „Produkt" erstellen',
      );
      expect(
        text(s, 'prozessErstellt'),
        'Im Reiter „Herstellung" eintragen und speichern',
      );
      expect(text(s, 'sensorikErstellt'), 'Im Reiter „Produkt" beschreiben');
      // Von Hand nur noch Navision; das Etikett an seinen Pflichtangaben.
      expect(
        [
          for (final p in s.punkte)
            if (p.vonHand) p.punkt.schluessel,
        ],
        ['navisionAngelegt'],
      );
      expect(text(s, 'etikettErstellt'), '0 von 12 Pflichtangaben geprüft');
    });

    test('als Nächstes: der erste offene Punkt in Arbeitsreihenfolge', () {
      final neu = projektCheckStand(
        projekt: projekt(),
        rezepturen: const [],
        versionen: const [],
      );
      // Die Reihenfolge, in der gearbeitet wird.
      expect([for (final p in neu.punkte) checkAufgabe(p)], [
        'Rezeptur erstellen',
        'Nährwerte vervollständigen',
        'Sensorik beschreiben',
        'Prozess beschreiben',
        'Spezifikation erstellen',
        'Pflichtangaben des Etiketts prüfen',
        'Als Artikel freigeben',
        'In Navision anlegen und abhaken',
      ]);
      expect(neu.naechster!.punkt.schluessel, 'rezepturErstellt');

      // Rezeptur und Nährwerte aus einem abgeschlossenen Stand: weiter
      // mit der Sensorik.
      final weiter = projektCheckStand(
        projekt: projekt(),
        rezepturen: [rezeptur('r1')],
        versionen: [stand('v1')],
      );
      expect(weiter.naechster!.punkt.schluessel, 'sensorikErstellt');

      // Ein übersprungener Punkt kommt zuerst: Navision ist abgehakt, das
      // Etikett noch nicht.
      final luecke = projektCheckStand(
        projekt: projekt(
          artikelId: 'a1',
          freigegebenAm: zeit,
          haken: {'navisionAngelegt'},
          sensorik: const Sensorik(
            aussehen: 'a',
            geruch: 'g',
            geschmack: 's',
            konsistenz: 'k',
          ),
          prozess: const Prozessparameter(
            abschnitte: [
              ProzessAbschnitt(
                id: 'garen',
                titel: 'Garen',
                felder: [
                  ProzessFeld(id: 'kern', label: 'Kerntemperatur', wert: '72'),
                ],
              ),
            ],
          ).alsJson(),
        ),
        rezepturen: [rezeptur('r1')],
        versionen: [stand('v1')],
      );
      expect(
        [
          for (final p in luecke.punkte)
            if (!p.erledigt) p.punkt.schluessel,
        ],
        ['spezifikationErstellt', 'etikettErstellt'],
      );
      expect(luecke.naechster!.punkt.schluessel, 'spezifikationErstellt');
    });

    test('Etikett: erledigt, wenn jede Pflichtangabe geprüft ist (F28)', () {
      String? etikett(Map<String, LmivStand> staende) => text(
            projektCheckStand(
              projekt: projekt(etikett: staende),
              rezepturen: const [],
              versionen: const [],
            ),
            'etikettErstellt',
          );
      final alle = {
        for (final c in kEtikettCheckliste) c.schluessel: LmivStand.erledigt,
      };
      expect(etikett(alle), 'Alle 12 Pflichtangaben geprüft');
      // „Trifft nicht zu" zählt wie abgehakt.
      expect(
        etikett({
          ...alle,
          'quid': LmivStand.trifftNichtZu,
          'schutzgas': LmivStand.trifftNichtZu,
        }),
        'Alle 12 Pflichtangaben geprüft · 2 treffen nicht zu',
      );
      expect(
        etikett({...alle, 'schutzgas': LmivStand.trifftNichtZu}),
        'Alle 12 Pflichtangaben geprüft · 1 trifft nicht zu',
      );
      // Eine offene genügt, damit das Etikett offen bleibt.
      final offen = projektCheckStand(
        projekt: projekt(etikett: {...alle, 'mhd': LmivStand.offen}),
        rezepturen: const [],
        versionen: const [],
      );
      expect(erledigt(offen, 'etikettErstellt'), isFalse);
      expect(
        text(offen, 'etikettErstellt'),
        '11 von 12 Pflichtangaben geprüft',
      );
      expect(
        checkAufgabe(offen.punkt('etikettErstellt')!),
        'Pflichtangaben des Etiketts prüfen',
      );
      expect(offen.punkt('etikettErstellt')!.vonHand, isFalse);
    });

    test('von Hand nur Navision; ein früherer Etikett-Haken gilt', () {
      final s = projektCheckStand(
        projekt: projekt(
          haken: {
            'rezepturErstellt',
            'naehrwerteErstellt',
            'prozessErstellt',
            'sensorikErstellt',
            'etikettErstellt',
            'navisionAngelegt',
            'unbekannt',
          },
        ),
        rezepturen: const [],
        versionen: const [],
      );
      expect(s.text, '2 von 8');
      // Vor F28 von Hand abgehakt: Das gilt weiter.
      expect(erledigt(s, 'etikettErstellt'), isTrue);
      expect(text(s, 'etikettErstellt'), 'Früher von Hand abgehakt');
      expect(erledigt(s, 'navisionAngelegt'), isTrue);
      expect(erledigt(s, 'rezepturErstellt'), isFalse);
      expect(erledigt(s, 'sensorikErstellt'), isFalse);
    });

    test('alles erfüllt: acht von acht, mit dem, woran es die App sieht', () {
      final s = projektCheckStand(
        projekt: projekt(
          artikelId: 'a1',
          artikelnummer: '4711',
          freigegebenAm: DateTime(2026, 10, 21),
          freigabeVersionId: 'v2',
          haken: {'spezifikationErstellt', 'etikettErstellt', 'navisionAngelegt'},
          sensorik: const Sensorik(
            aussehen: 'gleichmäßig gebräunt',
            geruch: 'würzig',
            geschmack: 'kräftig',
            konsistenz: 'saftig',
          ),
          prozess: Prozessparameter(
            version: '1.1',
            stand: DateTime(2026, 9, 30),
            abschnitte: const [
              ProzessAbschnitt(
                id: 'garen',
                titel: 'Garen',
                felder: [
                  ProzessFeld(id: 'kern', label: 'Kerntemperatur', wert: '72'),
                ],
              ),
            ],
          ).alsJson(),
        ),
        rezepturen: [rezeptur('r1')],
        versionen: [
          stand('v1', am: DateTime(2026, 9, 1)),
          stand('v2', nummer: 2, am: DateTime(2026, 9, 15)),
          // Neuer, aber nicht freigegeben: geprüft wird der freigegebene.
          stand(
            'v3',
            nummer: 3,
            am: DateTime(2026, 10, 1),
            json: eingefroren(const [
              RechenPosition.zutat(gewuerz, mengeKg: 1),
            ]),
          ),
        ],
      );
      expect(s.text, '8 von 8');
      expect(s.anteil, 1);
      expect(
        text(s, 'artikelAngelegt'),
        'Artikel 4711 · freigegeben am 21.10.2026',
      );
      expect(text(s, 'rezepturErstellt'), 'Grillwurst · Stand 2 freigegeben');
      expect(
        text(s, 'naehrwerteErstellt'),
        'Stand 2: alle Zutaten mit Nährwerten',
      );
      expect(text(s, 'prozessErstellt'), 'Version 1.1 vom 30.09.2026');
      expect(text(s, 'sensorikErstellt'), isNull);
      expect(s.punkt('rezepturErstellt')!.rezepturId, 'r1');
      expect(s.punkt('prozessErstellt')!.rezepturId, isNull);
    });

    test('Rezeptur und Nährwerte am zuletzt abgeschlossenen Stand', () {
      // Nur ein Entwurf: noch keine Rezeptur im Sinne der Liste.
      var s = projektCheckStand(
        projekt: projekt(),
        rezepturen: [rezeptur('r1')],
        versionen: [stand('v1', abgeschlossen: false)],
      );
      expect(text(s, 'rezepturErstellt'), 'Noch kein Stand abgeschlossen');
      expect(erledigt(s, 'naehrwerteErstellt'), isFalse);
      // Ohne geprüften Stand führt der Punkt in die einzige Rezeptur.
      expect(s.punkt('rezepturErstellt')!.rezepturId, 'r1');

      s = projektCheckStand(
        projekt: projekt(),
        rezepturen: [rezeptur('r1'), rezeptur('r2', name: 'Marinade')],
        versionen: [
          stand('v1', am: DateTime(2026, 9, 1)),
          stand(
            'm1',
            rezepturId: 'r2',
            am: DateTime(2026, 9, 20),
            json: eingefroren(const [
              RechenPosition.zutat(fleisch, mengeKg: 5),
              RechenPosition.zutat(gewuerz, mengeKg: 0.2),
              // Wasser hat keine Nährwerte — das fehlt nicht.
              RechenPosition.zutat(wasser, mengeKg: 1),
            ]),
          ),
          stand('m2', rezepturId: 'r2', nummer: 2, abgeschlossen: false),
        ],
      );
      expect(text(s, 'rezepturErstellt'), 'Marinade · Stand 1 abgeschlossen');
      expect(
        text(s, 'naehrwerteErstellt'),
        'Stand 1: ohne Nährwerte: Gewürz Testmischung',
      );
      expect(s.punkt('naehrwerteErstellt')!.rezepturId, 'r2');
      expect(s.text, '1 von 8');
    });

    test('Nährwerte: ohne Mengen, unlesbar, viele Lücken', () {
      ProjektCheckStand mit(String json) => projektCheckStand(
            projekt: projekt(),
            rezepturen: [rezeptur('r1')],
            versionen: [stand('v1', json: json)],
          );
      expect(
        text(mit(eingefroren(const [])), 'naehrwerteErstellt'),
        'Stand 1 hat keine Mengen',
      );
      expect(
        text(mit('{kaputt'), 'naehrwerteErstellt'),
        'Stand 1 ließ sich nicht lesen',
      );
      final viele = [
        for (final n in ['A', 'B', 'C', 'D', 'E'])
          RechenPosition.zutat(RechenZutat(id: n, name: 'Zutat $n'), mengeKg: 1),
      ];
      expect(
        text(mit(eingefroren(viele)), 'naehrwerteErstellt'),
        'Stand 1: ohne Nährwerte: Zutat A, Zutat B, Zutat C und 2 weitere',
      );
    });

    test('Sensorik und Prozess: was noch fehlt', () {
      var s = projektCheckStand(
        projekt: projekt(
          sensorik: const Sensorik(aussehen: 'hell', geschmack: 'mild'),
          prozess: kNeutraleProzessVorlage.alsJson(),
        ),
        rezepturen: const [],
        versionen: const [],
      );
      expect(text(s, 'sensorikErstellt'), 'Fehlt: Geruch und Konsistenz');
      expect(text(s, 'prozessErstellt'), 'Noch keine Werte eingetragen');

      // Maße allein beschreiben das Produkt noch nicht.
      s = projektCheckStand(
        projekt: projekt(sensorik: const Sensorik(gewicht: '120 g')),
        rezepturen: const [],
        versionen: const [],
      );
      expect(text(s, 'sensorikErstellt'), 'Im Reiter „Produkt" beschreiben');
    });

    test('Artikel: Freigabe oder früher von Hand abgehakt', () {
      var s = projektCheckStand(
        projekt: projekt(haken: {'artikelAngelegt'}),
        rezepturen: const [],
        versionen: const [],
      );
      expect(erledigt(s, 'artikelAngelegt'), isTrue);
      expect(text(s, 'artikelAngelegt'), 'Früher von Hand abgehakt');

      s = projektCheckStand(
        projekt: projekt(artikelId: 'a1'),
        rezepturen: const [],
        versionen: const [],
      );
      expect(text(s, 'artikelAngelegt'), 'Mit der Freigabe angelegt');
    });

    test('gelöschte und fremde Rezepturen zählen nicht', () {
      final s = projektCheckStand(
        projekt: projekt(),
        rezepturen: [
          rezeptur('r1', geloescht: true),
          rezeptur('r2', projektId: 'p2'),
        ],
        versionen: [stand('v1'), stand('v2', rezepturId: 'r2')],
      );
      expect(text(s, 'rezepturErstellt'), 'Noch keine Rezeptur');
      expect(s.text, '0 von 8');
    });

    test('alle Projekte auf einmal: wie einzeln gezählt', () {
      final projekte = [
        projekt(),
        projekt(id: 'p2', haken: {'navisionAngelegt'}),
        projekt(id: 'p3'),
      ];
      final rezepturen = [
        rezeptur('r1'),
        rezeptur('r2', projektId: 'p2'),
        rezeptur('r3', projektId: null),
      ];
      final versionen = [
        stand('v1'),
        stand('v2', rezepturId: 'r2'),
        stand('v3', rezepturId: 'r3'),
      ];
      final alle = projektCheckStaende(
        projekte: projekte,
        rezepturen: rezepturen,
        versionen: versionen,
      );
      expect(alle.keys, ['p1', 'p2', 'p3']);
      for (final p in projekte) {
        expect(
          alle[p.id]!.text,
          projektCheckStand(
            projekt: p,
            rezepturen: rezepturen,
            versionen: versionen,
          ).text,
          reason: p.id,
        );
      }
      expect([for (final p in projekte) alle[p.id]!.text], [
        '2 von 8',
        '3 von 8',
        '0 von 8',
      ]);
    });
  });
}
