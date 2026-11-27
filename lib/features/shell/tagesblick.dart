import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import '../../core/services/erledigt_service.dart';
import '../../core/utils/datum.dart';

// ═══════════════════════════════════════════════════════════════════════
// Tagesblick
//
// Zwei kleine Rechnungen für die Übersicht, ohne Flutter:
//
// * Fortschritt des Tages — wie viele Produktionen erledigt, wie viel
//   Rohware durch, wie viele erfasst.
// * Der nächste Tag mit Planung — Rohware gesamt und je Abteilung, womit
//   sie anfängt. Zum Vorbereiten am Nachmittag: Zerlegung, Rüsten.
//
// Eine Produktion ist eine Kette im Board; gezählt wird ihr erster Schritt
// (ohne `parentTaskId`). Dort steht die Rohware.
// ═══════════════════════════════════════════════════════════════════════

/// So weit sucht die Übersicht nach dem nächsten Tag mit Planung.
const int kNaechsterTagSuche = 14;

/// Eine Produktion des Tages, wie der Fortschritt sie braucht.
typedef TagesProduktion = ({double rohKg, Erledigt? erledigt, bool erfasst});

/// Wie weit der Tag ist.
class TagesFortschritt {
  const TagesFortschritt({
    required this.produktionen,
    required this.erledigt,
    required this.erfasst,
    required this.rohKg,
    required this.rohKgErledigt,
  });

  factory TagesFortschritt.aus(Iterable<TagesProduktion> liste) {
    var n = 0, fertig = 0, erfasst = 0;
    var roh = 0.0, rohFertig = 0.0;
    for (final p in liste) {
      n++;
      roh += p.rohKg;
      if (p.erledigt != null) {
        fertig++;
        rohFertig += p.rohKg;
      }
      if (p.erfasst) erfasst++;
    }
    return TagesFortschritt(
      produktionen: n,
      erledigt: fertig,
      erfasst: erfasst,
      rohKg: roh,
      rohKgErledigt: rohFertig,
    );
  }

  final int produktionen;

  /// Abgehakt oder erfasst — wie im Board.
  final int erledigt;

  /// Davon in der Produktionserfassung.
  final int erfasst;
  final double rohKg;
  final double rohKgErledigt;

  bool get leer => produktionen == 0;

  /// Anteil erledigt, gemessen an der Rohware — ohne Rohware an der Zahl.
  double get anteil => rohKg > 0
      ? rohKgErledigt / rohKg
      : produktionen == 0
          ? 0
          : erledigt / produktionen;
}

/// Womit eine Abteilung am nächsten Tag anfängt.
class StartAbteilung {
  const StartAbteilung({
    required this.abteilung,
    required this.anzahl,
    required this.nummer,
    required this.name,
    this.startZeit,
  });

  final Abteilung abteilung;

  /// Karten der Abteilung an dem Tag.
  final int anzahl;

  /// Der erste Artikel — in der Reihenfolge des Boards.
  final String nummer;
  final String name;

  /// „06:15" — null, wenn im Board keine Startzeit steht.
  final String? startZeit;
}

/// Der nächste Tag mit Planung.
class NaechsterTag {
  const NaechsterTag({
    required this.tag,
    required this.produktionen,
    required this.rohKg,
    required this.abteilungen,
  });

  final DateTime tag;
  final int produktionen;
  final double rohKg;

  /// In der Reihenfolge der Abteilungen.
  final List<StartAbteilung> abteilungen;
}

/// Der erste Tag nach [tag] mit Karten in [tasks] — Rohware, Produktionen
/// und je Abteilung der erste Artikel. null ohne Planung. [tasks] dürfen
/// mehrere Tage umfassen; gelöschte und stornierte sind schon heraus.
NaechsterTag? naechsterTagAus(
  DateTime tag,
  List<ProductionTask> tasks,
  Map<String, Product> produkte,
) {
  final ab = tagPlus(tag, 1);
  DateTime? erster;
  for (final t in tasks) {
    final d = tagOhneZeit(t.datum);
    if (d.isBefore(ab)) continue;
    if (erster == null || d.isBefore(erster)) erster = d;
  }
  final tagN = erster;
  if (tagN == null) return null;
  final amTag = [
    for (final t in tasks)
      if (tagOhneZeit(t.datum) == tagN) t,
  ];
  final wurzeln = amTag.where((t) => t.parentTaskId == null);
  final jeAbteilung = <Abteilung, List<ProductionTask>>{};
  for (final t in amTag) {
    final a = _abteilung(t.abteilung);
    if (a == null) continue;
    (jeAbteilung[a] ??= []).add(t);
  }
  return NaechsterTag(
    tag: tagN,
    produktionen: wurzeln.length,
    rohKg: wurzeln.fold(0.0, (s, t) => s + t.mengeKg),
    abteilungen: [
      for (final a in Abteilung.values)
        if (jeAbteilung[a] case final liste?) _start(a, liste, produkte),
    ],
  );
}

StartAbteilung _start(
  Abteilung a,
  List<ProductionTask> liste,
  Map<String, Product> produkte,
) {
  final sortiert = [...liste]..sort((x, y) {
      final s = x.sortierung.compareTo(y.sortierung);
      if (s != 0) return s;
      return (x.startZeit ?? '').compareTo(y.startZeit ?? '');
    });
  final erster = sortiert.first;
  final p = produkte[erster.productId];
  final start = erster.startZeit?.trim();
  return StartAbteilung(
    abteilung: a,
    anzahl: liste.length,
    nummer: p?.artikelnummer ?? '—',
    name: p?.artikelbezeichnung ?? 'Unbekannt',
    startZeit: start == null || start.isEmpty ? null : start,
  );
}

Abteilung? _abteilung(String dbValue) {
  for (final a in Abteilung.values) {
    if (a.dbValue == dbValue) return a;
  }
  return null;
}
