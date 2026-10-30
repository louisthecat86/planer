// Erfundene Statistik-Daten für die Tests des Ausdrucks — keine echten
// Artikel, Kunden oder Mengen. Geplant und erfasst ist ab KW 36/2026;
// „heute" ist Freitag in KW 44/2026.
import 'package:produktion_planer/core/constants/abteilungen.dart';
import 'package:produktion_planer/core/services/erledigt_service.dart';
import 'package:produktion_planer/features/articles/artikel_luecken.dart';
import 'package:produktion_planer/features/board/board_providers.dart';
import 'package:produktion_planer/features/statistik/statistik_daten.dart';

/// Wann die Beispiel-Statistik geladen wurde.
final DateTime bspStatistikStand = DateTime(2026, 10, 30, 15, 20);

/// Der erste Tag mit Planung: Montag in KW 36/2026.
final DateTime bspStatistikBeginn = DateTime(2026, 8, 31);

const BoardSpur _zerlegung = BoardSpur(
  abteilung: Abteilung.zerlegung,
  kapazitaetMinuten: 600,
);
const BoardSpur _brat = BoardSpur(
  abteilung: Abteilung.bratstrasse,
  maschineId: 'm-brat',
  maschineName: 'Bratlinie Nord',
  kapazitaetMinuten: 480,
);
const BoardSpur _packA = BoardSpur(
  abteilung: Abteilung.verpackung,
  maschineId: 'm-va',
  maschineName: 'Packanlage A',
  kapazitaetMinuten: 480,
);
const BoardSpur _packB = BoardSpur(
  abteilung: Abteilung.verpackung,
  maschineId: 'm-vb',
  maschineName: 'Packanlage B',
  kapazitaetMinuten: 480,
);

/// Die Spuren in der Reihenfolge des Boards.
const List<BoardSpur> bspStatistikSpuren = [_zerlegung, _brat, _packA, _packB];

StatistikArtikel _artikel(
  String nummer,
  String bezeichnung, {
  String? gruppe,
  Set<String> abteilungen = const {},
  Set<ArtikelLuecke> luecken = const {},
  double? leistung,
}) =>
    StatistikArtikel(
      id: 'p-$nummer',
      artikelnummer: nummer,
      bezeichnung: bezeichnung,
      produktgruppe: gruppe,
      abteilungen: abteilungen,
      luecken: luecken,
      leistungKgH: leistung,
    );

/// Alle Artikel — die letzten beiden sind nie geplant.
final Map<String, StatistikArtikel> bspStatistikArtikel = {
  for (final a in [
    _artikel(
      '7101',
      'Schweineschulter zerlegt',
      abteilungen: {'zerlegung'},
      luecken: {ArtikelLuecke.ohneProduktgruppe},
    ),
    _artikel(
      '7102',
      'Rinderkeule zerlegt',
      gruppe: 'braten',
      abteilungen: {'zerlegung'},
    ),
    _artikel(
      '7201',
      'Gartenwurst gebraten',
      gruppe: 'angebratene_bruehwurst',
      abteilungen: {'bratstrasse', 'verpackung'},
      leistung: 300,
    ),
    _artikel(
      '7202',
      'Frikadellen klein',
      gruppe: 'bratstrasse_natur',
      abteilungen: {'bratstrasse', 'verpackung'},
      leistung: 220,
    ),
    _artikel(
      '7203',
      'Hackbällchen',
      gruppe: 'bratstrasse_natur',
      abteilungen: {'bratstrasse'},
      leistung: 180,
    ),
    _artikel(
      '7204',
      'Bratwurst mild',
      gruppe: 'angebratene_bruehwurst',
      abteilungen: {'bratstrasse'},
      luecken: {ArtikelLuecke.ohneAusbeute, ArtikelLuecke.zeitPlatzhalter},
    ),
    _artikel(
      '7301',
      'Gartenwurst 6er Schale',
      gruppe: 'bruehwurst',
      abteilungen: {'verpackung'},
    ),
    _artikel(
      '7302',
      'Frikadellen Beutel',
      gruppe: 'bratstrasse_natur',
      abteilungen: {'verpackung'},
    ),
    _artikel(
      '7501',
      'Leberkäse fein',
      luecken: {ArtikelLuecke.nichtEingepflegt},
    ),
    _artikel(
      '7502',
      'Kochschinken Würfel',
      gruppe: 'kochpoekelware',
      luecken: {ArtikelLuecke.ohneSchritte, ArtikelLuecke.ohneAusbeute},
    ),
  ])
    a.id: a,
};

/// Ausbeute je Artikel im Mittel.
const Map<String, double> _ausbeute = {
  'p-7101': 0.92,
  'p-7102': 0.88,
  'p-7201': 0.86,
  'p-7202': 0.82,
  'p-7203': 0.80,
};

/// Wie schnell ein Artikel gegenüber seinen Leistungsdaten läuft.
const Map<String, double> _tempo = {
  'p-7201': 0.74,
  'p-7202': 1.03,
  'p-7203': 1.32,
};

/// Die Artikel der Bratstraße im Wechsel.
const List<String> _bratArtikel = ['p-7201', 'p-7202', 'p-7203', 'p-7204'];

/// Tage seit dem Beginn der Planung (Montag, KW 36).
int _tag(DateTime tag) => DateTime.utc(tag.year, tag.month, tag.day)
    .difference(DateTime.utc(2026, 8, 31))
    .inDays;

/// Die Werktage der Spanne.
Iterable<DateTime> _werktage(StatistikSpanne spanne) sync* {
  for (var t = spanne.von;
      t.isBefore(spanne.bisExkl);
      t = DateTime(t.year, t.month, t.day + 1)) {
    if (t.weekday <= DateTime.friday) yield t;
  }
}

/// Produktionszeit und Nebenzeiten einer Spur an einem Tag — null: nichts
/// geplant.
(double, Map<String, double>)? _plan(int s, int t) {
  if (t < 0) return null;
  final w = t ~/ 7;
  final d = t % 7;
  return switch (s) {
    0 => (420.0 + ((w * 3 + d * 2) % 5) * 45, const {'reinigen': 30.0}),
    1 => (
        300.0 + ((w * 5 + d * 3) % 4) * 50,
        {'ruesten': 20.0, if (d.isEven) 'reinigen': 45.0},
      ),
    2 => (240.0 + ((w + d * 2) % 3) * 60, const {'ruesten': 15.0}),
    _ => (
        d.isEven ? 210.0 : 90.0,
        {if (d == 4) 'sonstiges': 15.0},
      ),
  };
}

/// Die Artikel einer Spur an einem Tag.
List<String> _kartenArtikel(int s, int t) => switch (s) {
      0 => [t.isEven ? 'p-7101' : 'p-7102'],
      1 => [_bratArtikel[t % 4], _bratArtikel[(t + 1) % 4]],
      2 => const ['p-7301'],
      _ => const ['p-7302'],
    };

/// Erledigt-Stand einer Karte vor heute: meist erfasst, manche nur
/// abgehakt, wenige offen.
Erledigt? _erledigt(int s, int t, int k) => switch ((t * 7 + s * 3 + k) % 10) {
      0 => null,
      1 || 2 => Erledigt.abgehakt,
      _ => Erledigt.erfasst,
    };

/// Eine erfasste Produktion zur Karte [k] der Spur [s] am Tag [t].
ErfassteProduktion? _produktion(
  String id,
  DateTime datum,
  int s,
  int t,
  int k,
) {
  if (s > 1) return null;
  final roh = s == 0
      ? 1200.0 + ((t * 13) % 7) * 150
      : 500.0 + ((t * 11 + k * 5) % 6) * 80;
  final mittel = _ausbeute[id];
  double? fertig;
  if (mittel != null) {
    fertig = roh * (mittel + (((t * 7 + k * 3) % 9) - 4) * 0.008);
  }
  // Ein Tippfehler: mehr Fertigware als Rohware.
  if (s == 0 && t == 10) fertig = roh * 1.05;
  final verlust = fertig == null || fertig >= roh ? null : 1 - fertig / roh;
  final leistung = bspStatistikArtikel[id]?.leistungKgH;
  final kgh = s == 0
      ? 260.0
      : leistung == null
          ? 240.0
          : leistung * (_tempo[id] ?? 1) * (1 + ((t % 5) - 2) * 0.02);
  return ErfassteProduktion(
    productId: id,
    datum: datum,
    kgRohware: roh,
    kgFertigware: fertig,
    verlust: verlust,
    ausbeuteAngegeben: fertig != null,
    // Manchmal fehlt die Zeit.
    minuten: t % 9 == 4 ? null : roh / kgh * 60,
  );
}

/// Die Statistik des Beispielbetriebs für [zeitraum].
StatistikDaten bspStatistikDaten({
  StatistikZeitraum zeitraum = StatistikZeitraum.quartal,
}) {
  final heute = DateTime(2026, 10, 30);
  final spanne = StatistikSpanne.fuer(
    zeitraum,
    bspStatistikStand,
    fruehestes: bspStatistikBeginn,
  );
  final belegung = <SpurTagBelegung>[];
  final karten = <PlanKarte>[];
  final produktionen = <ErfassteProduktion>[];
  for (final datum in _werktage(spanne)) {
    final t = _tag(datum);
    for (final (s, spur) in bspStatistikSpuren.indexed) {
      final plan = _plan(s, t);
      belegung.add(
        SpurTagBelegung(
          spur: spur,
          tag: datum,
          produktionsMinuten: plan?.$1 ?? 0,
          zusatzMinuten: plan?.$2 ?? const {},
        ),
      );
      if (plan == null) continue;
      for (final (k, id) in _kartenArtikel(s, t).indexed) {
        final erledigt = datum.isBefore(heute) ? _erledigt(s, t, k) : null;
        karten.add(
          PlanKarte(
            productId: id,
            abteilung: spur.abteilung,
            datum: datum,
            erledigt: erledigt,
          ),
        );
        if (erledigt != Erledigt.erfasst) continue;
        final p = _produktion(id, datum, s, t, k);
        if (p != null) produktionen.add(p);
      }
    }
  }
  return StatistikDaten(
    spanne: spanne,
    stand: bspStatistikStand,
    belegung: belegung,
    karten: karten,
    produktionen: produktionen,
    artikel: bspStatistikArtikel,
  );
}

/// Eine Statistik ohne Planung und ohne Produktionen — nur die Artikel.
StatistikDaten bspStatistikLeer() => StatistikDaten(
      spanne: StatistikSpanne.fuer(
        StatistikZeitraum.vierWochen,
        bspStatistikStand,
      ),
      stand: bspStatistikStand,
      belegung: const [],
      karten: const [],
      produktionen: const [],
      artikel: bspStatistikArtikel,
    );
