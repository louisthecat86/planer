import 'package:drift/drift.dart';

import '../../core/database/database.dart';

/// Eine geplante Produktion (Ketten-Wurzel) für die Erfassung — in der
/// Übersicht der Woche und auf der Erfassungsliste zum Drucken.
///
/// Bewusst ohne Flutter-Abhängigkeit: Die Liste zum Drucken entsteht
/// daraus ohne Oberfläche.
class GeplanteProduktion {
  const GeplanteProduktion({
    required this.task,
    required this.artikelName,
    required this.artikelNummer,
    this.rohwareKg,
  });

  final ProductionTask task;
  final String artikelName;
  final String artikelNummer;

  /// Die Rohware der Produktion mit allen Teilen, wenn ihr erster Schritt
  /// auf Tage verteilt ist — null: die Menge der Wurzel.
  final double? rohwareKg;

  /// Die geplante Rohware.
  double get rohKg => rohwareKg ?? task.mengeKg;

  /// Die geplante Fertigware — null, wenn die Produktion ohne sie geplant
  /// wurde (dann steht dort 0).
  double? get fertigKg {
    final f = task.fertigMengeKg;
    return f != null && f > 0 ? f : null;
  }

  /// Die geplante Fleischeinwaage — null, wenn keine geplant ist.
  double? get fleischKg {
    final f = task.fleischMengeKg;
    return f != null && f > 0 ? f : null;
  }

  /// Die Menge, die die Übersicht zeigt: die geplante Fertigware, ohne sie
  /// die Rohware.
  double get mengeKg => fertigKg ?? rohKg;
}

/// Die geplanten Produktionen (Ketten-Wurzeln) von [von] bis vor
/// [bisExkl], die noch nicht erfasst sind — je Tag, nach Artikelname.
/// Nur die WURZEL jeder Kette zählt: Eine Produktion wird einmal erfasst,
/// nicht je Abteilungsschritt.
///
/// Dieselbe Liste zeigt die Produktionserfassung und nimmt das Paket für
/// die Handy-Erfassung mit.
Future<Map<DateTime, List<GeplanteProduktion>>> geplanteProduktionenLaden(
  AppDatabase db,
  DateTime von,
  DateTime bisExkl,
) async {
  // Nur Ketten-Wurzeln: sie tragen die Fertigmenge und stehen für die
  // gesamte Produktion.
  final tasks = await (db.select(db.productionTasks)
        ..where((t) => t.deletedAt.isNull())
        ..where((t) => t.parentTaskId.isNull())
        ..where((t) => t.datum.isBiggerOrEqualValue(von))
        ..where((t) => t.datum.isSmallerThanValue(bisExkl))
        ..where((t) => t.status.isNotIn(const ['storniert'])))
      .get();

  if (tasks.isEmpty) return {};

  // Ist der erste Schritt auf Tage verteilt, hängen die übrigen Teile als
  // Kinder derselben Abteilung an der Wurzel — die Rohware ist ihre Summe.
  final rohware = {for (final t in tasks) t.id: t.mengeKg};
  final abteilung = {for (final t in tasks) t.id: t.abteilung};
  final teile = await (db.select(db.productionTasks)
        ..where((t) => t.parentTaskId.isIn(rohware.keys))
        ..where((t) => t.deletedAt.isNull())
        ..where((t) => t.status.isNotIn(const ['storniert'])))
      .get();
  for (final teil in teile) {
    final wurzel = teil.parentTaskId!;
    if (teil.abteilung == abteilung[wurzel]) {
      rohware[wurzel] = rohware[wurzel]! + teil.mengeKg;
    }
  }

  final produkte =
      await (db.select(db.products)..where((p) => p.deletedAt.isNull())).get();
  final byId = {for (final p in produkte) p.id: p};

  // Für den „erfasst"-Hinweis: welche (Artikel, Tag)-Kombinationen haben
  // bereits eine Historienzeile?
  final historie = await (db.select(db.productionHistory)
        ..where((h) => h.deletedAt.isNull())
        ..where((h) => h.datum.isBiggerOrEqualValue(von))
        ..where((h) => h.datum.isSmallerThanValue(bisExkl)))
      .get();
  String schluessel(String productId, DateTime d) =>
      '$productId|${d.year}-${d.month}-${d.day}';
  final erfassteKeys = {
    for (final h in historie) schluessel(h.productId, h.datum),
  };

  final gruppen = <DateTime, List<GeplanteProduktion>>{};
  for (final t in tasks) {
    final tag = DateTime(t.datum.year, t.datum.month, t.datum.day);
    // Sobald für diesen Artikel an diesem Tag eine Historie erfasst wurde,
    // gilt die Produktion als erledigt und verschwindet aus der Liste.
    if (erfassteKeys.contains(schluessel(t.productId, tag))) continue;
    final p = byId[t.productId];
    gruppen.putIfAbsent(tag, () => []).add(
          GeplanteProduktion(
            task: t,
            artikelName: p?.artikelbezeichnung ?? 'Unbekannt',
            artikelNummer: p?.artikelnummer ?? '—',
            rohwareKg: rohware[t.id],
          ),
        );
  }

  // Innerhalb eines Tages nach Artikelname sortieren.
  for (final liste in gruppen.values) {
    liste.sort((a, b) => a.artikelName.compareTo(b.artikelName));
  }
  return gruppen;
}
