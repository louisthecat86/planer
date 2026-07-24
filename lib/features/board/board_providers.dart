import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';

/// Standard-Kapazität pro Abteilung und Tag in Minuten (9 h), wenn für die
/// Abteilung kein abweichender Wert gepflegt ist. Die Abteilungen arbeiten
/// regulär 9 Stunden; abweichende Zeiten lassen sich je Abteilung unter
/// „Einstellungen → Kapazität" pflegen.
const double kStandardKapazitaetMinuten = 540;

/// Auslastungs-Status einer Abteilung an einem Tag — steuert die Ampelfarbe
/// auf dem Board.
///
/// - [frei]: unter 75 % belegt ? es passt noch was rein (grau).
/// - [gut]: 75–100 % belegt ? gut gefüllt (grün).
/// - [ueberbucht]: über 100 % ? mehr geplant als Kapazität (rot).
enum CapacityStatus { frei, gut, ueberbucht }

/// Gemeinsame Auslastungs-Rechnung für Wochenzelle und Tages-Spur.
mixin _Auslastung {
  List<BoardTask> get tasks;
  double get kapazitaetMinuten;

  /// Rüst-, Reinigungs- und sonstige Nebenzeiten dieser Spur an diesem Tag.
  /// Sie blockieren dieselbe Anlage wie die Produktion und zählen deshalb
  /// voll in die Belegung.
  List<Zusatzzeit> get zusatzzeiten => const [];

  /// Reine Produktionszeit der Aufträge.
  double get produktionsMinuten =>
      tasks.fold(0, (summe, t) => summe + t.dauerMinuten);

  /// Summe der Nebenzeiten (Rüsten, Reinigen, Sonstiges).
  double get zusatzMinuten =>
      zusatzzeiten.fold(0, (summe, z) => summe + z.minuten);

  double get belegtMinuten => produktionsMinuten + zusatzMinuten;

  /// Verbleibende freie Minuten (negativ bei Überbuchung).
  double get freiMinuten => kapazitaetMinuten - belegtMinuten;

  /// Belegungsgrad 0..n (1.0 = voll).
  double get auslastung =>
      kapazitaetMinuten > 0 ? belegtMinuten / kapazitaetMinuten : 0;

  CapacityStatus get status {
    if (belegtMinuten > kapazitaetMinuten) return CapacityStatus.ueberbucht;
    if (kapazitaetMinuten > 0 && auslastung >= 0.75) {
      return CapacityStatus.gut;
    }
    return CapacityStatus.frei;
  }
}

/// Eine Auftragskarte auf dem Board (eine Zeile aus `production_tasks`,
/// angereichert um den Produktnamen für die Anzeige).
class BoardTask {
  const BoardTask({
    required this.id,
    required this.productId,
    required this.productName,
    required this.abteilung,
    required this.datum,
    required this.startZeit,
    required this.dauerMinuten,
    required this.mengeKg,
    required this.sortierung,
    required this.status,
    required this.mitgliederIds,
    this.parentTaskId,
    this.maschineId,
  });

  final String id;
  final String productId;
  final String productName;
  final Abteilung abteilung;

  /// Tag des Auftrags, normalisiert auf 00:00 Uhr.
  final DateTime datum;

  /// Geplante Startzeit als "HH:MM" oder null (Tag ohne feste Uhrzeit).
  final String? startZeit;

  final double dauerMinuten;
  final double mengeKg;

  /// Anlage, auf der der Auftrag läuft (null = keine/unbekannt).
  final String? maschineId;

  /// Verkettung: Aufträge derselben Produktion (die durch mehrere
  /// Abteilungen läuft) teilen sich eine Wurzel. `null` = dieser Auftrag
  /// IST die Wurzel.
  final String? parentTaskId;

  /// Stabile Kennung der Auftragskette — alle Karten einer Produktion
  /// liefern denselben Wert und bekommen dadurch dieselbe Akzentfarbe.
  String get kettenId => parentTaskId ?? id;

  /// Manuelle Reihenfolge innerhalb der Abteilung an einem Tag.
  final int sortierung;

  /// 'geplant' | 'in_arbeit' | 'fertig' (storniert wird gar nicht geladen).
  final String status;

  /// IDs aller zusammengefassten Tasks (gleiches Produkt + Abteilung + Tag).
  /// Bei einem einzelnen Task = [id]. Verschieben/Sortieren wirkt auf alle.
  final List<String> mitgliederIds;
}

/// Eine Kapazitäts-SPUR im Board.
///
/// Bisher war jede Abteilung genau eine Zeile mit 8 h Kapazität. Das ist
/// falsch, sobald in einer Abteilung mehrere Anlagen ECHT PARALLEL laufen:
/// In der Verpackung arbeiten Multivac, Tiefzieher und Kleinbeutel-Anlage
/// gleichzeitig — mit einer gemeinsamen 8-h-Spur wäre der Tag rechnerisch
/// dreifach überbucht, obwohl real alles passt.
///
/// Deshalb ist die planbare Ressource jetzt die ANLAGE (sofern sie als
/// [Machine.istPlanungsressource] markiert ist). Abteilungen ohne solche
/// Anlagen behalten ihre gemeinsame Spur (maschineId == null).
class BoardSpur {
  const BoardSpur({
    required this.abteilung,
    required this.kapazitaetMinuten,
    this.maschineId,
    this.maschineName,
    this.eignungHinweis,
  });

  final Abteilung abteilung;

  /// null = Sammelspur der Abteilung (keine Anlagen-Auftrennung).
  final String? maschineId;
  final String? maschineName;

  /// Informativer Hinweis („nur Aufschnitt / Weberslicer") — kein Verbot.
  final String? eignungHinweis;

  final double kapazitaetMinuten;

  /// Eindeutige Kennung der Spur.
  String get id => '${abteilung.dbValue}|${maschineId ?? ''}';

  /// Beschriftung der Zeile.
  String get anzeigeName => maschineName ?? abteilung.anzeigeName;

  /// Ist dies eine Anlagen-Spur (statt einer Abteilungs-Sammelspur)?
  bool get istAnlage => maschineId != null;
}

/// Eine Zelle im Wochenboard: eine Spur an einem Tag.
class BoardCell with _Auslastung {
  BoardCell({
    required this.spur,
    required this.tag,
    required this.tasks,
    required this.kapazitaetMinuten,
    this.zusatzzeiten = const [],
  });

  final BoardSpur spur;
  final DateTime tag;

  Abteilung get abteilung => spur.abteilung;

  @override
  final List<BoardTask> tasks;
  @override
  final double kapazitaetMinuten;
  @override
  final List<Zusatzzeit> zusatzzeiten;
}

/// Das komplette Wochenboard (Abteilungen × Mo–Fr).
class WeekBoard {
  WeekBoard({
    required this.wochenStart,
    required this.tage,
    required this.spuren,
    required this.cells,
  });

  /// Montag der Woche, 00:00 Uhr.
  final DateTime wochenStart;

  /// Die angezeigten Tage (Mo–Fr).
  final List<DateTime> tage;

  /// Alle Spuren als Zeilen (Anlagen-Spuren bzw. Abteilungs-Sammelspuren).
  final List<BoardSpur> spuren;

  /// Zellen, indiziert über [_cellKey].
  final Map<String, BoardCell> cells;

  /// Zelle für eine Spur an einem Tag.
  BoardCell cellFor(BoardSpur spur, DateTime tag) {
    final tagNorm = DateTime(tag.year, tag.month, tag.day);
    return cells[_cellKey(spur, tagNorm)] ??
        BoardCell(
          spur: spur,
          tag: tagNorm,
          tasks: const [],
          kapazitaetMinuten: spur.kapazitaetMinuten,
        );
  }
}

/// Eine Abteilungs-Spur in der Tagesübersicht.
class DayLane with _Auslastung {
  DayLane({
    required this.spur,
    required this.tasks,
    required this.kapazitaetMinuten,
    this.zusatzzeiten = const [],
  });

  final BoardSpur spur;

  Abteilung get abteilung => spur.abteilung;

  @override
  final List<BoardTask> tasks;
  @override
  final double kapazitaetMinuten;
  @override
  final List<Zusatzzeit> zusatzzeiten;
}

/// Die komplette Tagesübersicht (alle Abteilungen für einen Tag).
class DayBoard {
  DayBoard({required this.tag, required this.lanes});

  /// Der Tag, 00:00 Uhr.
  final DateTime tag;

  /// Eine Spur pro Abteilung.
  final List<DayLane> lanes;
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Tagesschlüssel für die Zuordnung von Nebenzeiten (ohne Uhrzeit).
String _tagKey(DateTime d) => DateTime(d.year, d.month, d.day)
    .toIso8601String();

/// Lädt Rüst-/Reinigungszeiten im Zeitraum und gruppiert sie nach
/// „<spurId>|<tag>". Gelöschte Einträge bleiben außen vor.
Future<Map<String, List<Zusatzzeit>>> _ladeZusatzzeiten(
  AppDatabase db, {
  required DateTime vonTag,
  required DateTime bisTag,
}) async {
  final von = DateTime(vonTag.year, vonTag.month, vonTag.day);
  final bis = DateTime(bisTag.year, bisTag.month, bisTag.day, 23, 59, 59);
  final zeilen = await (db.select(db.zusatzzeiten)
        ..where((z) => z.deletedAt.isNull())
        ..where((z) => z.datum.isBetweenValues(von, bis)))
      .get();
  final map = <String, List<Zusatzzeit>>{};
  for (final z in zeilen) {
    (map['${z.spurId}|${_tagKey(z.datum)}'] ??= []).add(z);
  }
  return map;
}

/// Wochenboard für die Woche, in die [anyDayInWeek] fällt.
///
/// Reagiert automatisch auf Kapazitäts-Änderungen (watch auf den Capacity-
/// Provider). Nach Task-Mutationen (verschieben, anlegen, löschen) muss der
/// Provider invalidiert werden:
/// `ref.invalidate(weekBoardProvider(anyDayInWeek))`.
final weekBoardProvider =
    FutureProvider.family<WeekBoard, DateTime>((ref, anyDayInWeek) async {
  final db = ref.watch(databaseProvider);

  final wochenStart = _montag(anyDayInWeek);
  final tage = List.generate(
    5,
    (i) => wochenStart.add(Duration(days: i)),
  );
  final wochenEndeExkl = wochenStart.add(const Duration(days: 7));

  final alleTasks = await _ladeBoardTasks(db, wochenStart, wochenEndeExkl);
  final planungsAnlagen = await _ladePlanungsAnlagen(db);
  final anlagenIds = planungsAnlagen.map((m) => m.id).toSet();

  // Abteilungen, in denen Aufträge OHNE gültige Anlagen-Spur liegen —
  // nur für die wird zusätzlich eine Sammelspur gezeigt.
  final ohneAnlage = <String>{};
  for (final t in alleTasks) {
    final mid = t.maschineId;
    if (mid == null || !anlagenIds.contains(mid)) {
      ohneAnlage.add(t.abteilung.dbValue);
    }
  }

  final spuren = _baueSpuren(planungsAnlagen, ohneAnlage);

  // Tasks den Spuren zuordnen.
  final tasksProZelle = <String, List<BoardTask>>{};
  for (final task in alleTasks) {
    final spurKey = _spurKeyFuerTask(task, anlagenIds);
    final key = '$spurKey|${task.datum.toIso8601String()}';
    (tasksProZelle[key] ??= []).add(task);
  }
  for (final liste in tasksProZelle.values) {
    _sortiereTasks(liste);
  }

  // Nebenzeiten (Rüsten/Reinigen) der Woche laden und den Zellen zuordnen.
  final zusatzProZelle = await _ladeZusatzzeiten(
    db,
    vonTag: tage.first,
    bisTag: tage.last,
  );

  final cells = <String, BoardCell>{};
  for (final spur in spuren) {
    for (final tag in tage) {
      final key = _cellKey(spur, tag);
      cells[key] = BoardCell(
        spur: spur,
        tag: tag,
        tasks: tasksProZelle[key] ?? const [],
        zusatzzeiten: zusatzProZelle['${spur.id}|${_tagKey(tag)}'] ?? const [],
        kapazitaetMinuten: spur.kapazitaetMinuten,
      );
    }
  }

  return WeekBoard(
    wochenStart: wochenStart,
    tage: tage,
    spuren: spuren,
    cells: cells,
  );
});

/// Tagesübersicht für [datum] — eine Spur pro Abteilung, Tasks nach Startzeit
/// sortiert. Funktioniert für jeden Wochentag (nicht auf Mo–Fr beschränkt).
final dayBoardProvider =
    FutureProvider.family<DayBoard, DateTime>((ref, datum) async {
  final db = ref.watch(databaseProvider);

  final tag = DateTime(datum.year, datum.month, datum.day);
  final naechsterTag = tag.add(const Duration(days: 1));

  final alleTasks = await _ladeBoardTasks(db, tag, naechsterTag);
  final planungsAnlagen = await _ladePlanungsAnlagen(db);
  final anlagenIds = planungsAnlagen.map((m) => m.id).toSet();

  final ohneAnlage = <String>{};
  for (final t in alleTasks) {
    final mid = t.maschineId;
    if (mid == null || !anlagenIds.contains(mid)) {
      ohneAnlage.add(t.abteilung.dbValue);
    }
  }

  final spuren = _baueSpuren(planungsAnlagen, ohneAnlage);

  final tasksProSpur = <String, List<BoardTask>>{};
  for (final task in alleTasks) {
    (tasksProSpur[_spurKeyFuerTask(task, anlagenIds)] ??= []).add(task);
  }

  final zusatzProSpur = await _ladeZusatzzeiten(db, vonTag: tag, bisTag: tag);

  final lanes = <DayLane>[];
  for (final spur in spuren) {
    final liste = tasksProSpur[spur.id] ?? <BoardTask>[];
    _sortiereTasks(liste);
    lanes.add(
      DayLane(
        spur: spur,
        tasks: liste,
        zusatzzeiten:
            zusatzProSpur['${spur.id}|${_tagKey(tag)}'] ?? const [],
        kapazitaetMinuten: spur.kapazitaetMinuten,
      ),
    );
  }

  return DayBoard(tag: tag, lanes: lanes);
});

// ---------------------------------------------------------------------------
// Interne Helfer
// ---------------------------------------------------------------------------

/// Lädt alle nicht-stornierten, nicht gelöschten Tasks im Zeitraum
/// [startInkl] (inklusive) bis [endeExkl] (exklusive) und reichert sie mit
/// dem Produktnamen an.
Future<List<BoardTask>> _ladeBoardTasks(
  AppDatabase db,
  DateTime startInkl,
  DateTime endeExkl,
) async {
  final rows = await (db.select(db.productionTasks)
        ..where((t) => t.deletedAt.isNull())
        ..where((t) => t.datum.isBiggerOrEqualValue(startInkl))
        ..where((t) => t.datum.isSmallerThanValue(endeExkl))
        ..where((t) => t.status.isNotIn(const ['storniert'])))
      .get();
  if (rows.isEmpty) return const [];

  final productIds = rows.map((t) => t.productId).toSet().toList();
  final produkte = await (db.select(db.products)
        ..where((p) => p.id.isIn(productIds)))
      .get();
  final nameById = {
    for (final p in produkte) p.id: p.artikelbezeichnung,
  };

  final perRow = <BoardTask>[];
  for (final t in rows) {
    final abteilung = _abteilungOf(t.abteilung);
    if (abteilung == null) continue; // unbekannte Abteilung überspringen
    perRow.add(
      BoardTask(
        id: t.id,
        parentTaskId: t.parentTaskId,
        maschineId: t.maschineId,
        productId: t.productId,
        productName: nameById[t.productId] ?? 'Unbekannt',
        abteilung: abteilung,
        datum: DateTime(t.datum.year, t.datum.month, t.datum.day),
        startZeit: t.startZeit,
        dauerMinuten: t.geplanteDauerMinuten,
        mengeKg: t.mengeKg,
        sortierung: t.sortierung,
        status: t.status,
        mitgliederIds: [t.id],
      ),
    );
  }

  // Tasks mit gleichem Produkt + Abteilung + Tag zu EINEM Feld bündeln
  // (Dauer summiert, Menge repräsentativ). So erscheint eine Abteilung je
  // Artikel/Tag nur einmal — egal ob aus alter oder neuer Planung.
  final gruppen = <String, List<BoardTask>>{};
  for (final bt in perRow) {
    final key = '${bt.productId}|${bt.abteilung.dbValue}'
        '|${bt.datum.toIso8601String()}';
    (gruppen[key] ??= []).add(bt);
  }

  final result = <BoardTask>[];
  for (final g in gruppen.values) {
    if (g.length == 1) {
      result.add(g.first);
      continue;
    }
    var dauer = 0.0;
    var menge = 0.0;
    var sortierung = g.first.sortierung;
    String? start;
    for (final t in g) {
      dauer += t.dauerMinuten;
      if (t.mengeKg > menge) menge = t.mengeKg; // repräsentativ, nicht addieren
      if (t.sortierung < sortierung) sortierung = t.sortierung;
      if (t.startZeit != null &&
          (start == null || t.startZeit!.compareTo(start) < 0)) {
        start = t.startZeit;
      }
    }
    result.add(
      BoardTask(
        id: g.first.id,
        parentTaskId: g.first.parentTaskId,
        maschineId: g.first.maschineId,
        productId: g.first.productId,
        productName: g.first.productName,
        abteilung: g.first.abteilung,
        datum: g.first.datum,
        startZeit: start,
        dauerMinuten: dauer,
        mengeKg: menge,
        sortierung: sortierung,
        status: g.first.status,
        mitgliederIds: [for (final t in g) t.id],
      ),
    );
  }
  return result;
}

/// Sortiert Tasks innerhalb einer Zelle/Spur: zuerst nach der manuellen
/// [BoardTask.sortierung], dann nach Startzeit (Tasks ohne Startzeit hinten),
/// zuletzt nach Dauer absteigend.
void _sortiereTasks(List<BoardTask> tasks) {
  tasks.sort((a, b) {
    final sort = a.sortierung.compareTo(b.sortierung);
    if (sort != 0) return sort;

    final sa = a.startZeit;
    final sb = b.startZeit;
    if (sa != null && sb != null) {
      final cmp = sa.compareTo(sb);
      if (cmp != 0) return cmp;
    } else if (sa != null) {
      return -1;
    } else if (sb != null) {
      return 1;
    }
    return b.dauerMinuten.compareTo(a.dauerMinuten);
  });
}

/// Abteilung aus dem dbValue, oder null bei unbekanntem Wert.
Abteilung? _abteilungOf(String dbValue) {
  try {
    return Abteilung.fromDbValue(dbValue);
  } catch (_) {
    return null;
  }
}

/// Montag der Woche von [d], normalisiert auf 00:00 Uhr.
DateTime _montag(DateTime d) {
  final tag = DateTime(d.year, d.month, d.day);
  return tag.subtract(Duration(days: tag.weekday - 1));
}

/// Eindeutiger Schlüssel einer Wochenboard-Zelle.
String _cellKey(BoardSpur spur, DateTime tag) {
  final tagNorm = DateTime(tag.year, tag.month, tag.day);
  return '${spur.id}|${tagNorm.toIso8601String()}';
}

/// Ordnet einen Auftrag seiner Spur zu.
///
/// Läuft der Auftrag auf einer Anlage, die eine eigene Kapazitätsspur hat,
/// zählt er dort. Sonst fällt er in die Sammelspur seiner Abteilung — so
/// geht kein Auftrag verloren, auch wenn die Anlage fehlt oder gelöscht wurde.
String _spurKeyFuerTask(BoardTask task, Set<String> anlagenSpuren) {
  final mid = task.maschineId;
  if (mid != null && anlagenSpuren.contains(mid)) {
    return '${task.abteilung.dbValue}|$mid';
  }
  return '${task.abteilung.dbValue}|';
}

/// Baut die Spuren-Liste: je Abteilung entweder Anlagen-Spuren (wenn dort
/// Anlagen als Planungsressource markiert sind) oder eine Sammelspur.
List<BoardSpur> _baueSpuren(
  List<Machine> planungsAnlagen,
  Set<String> abteilungenMitTasksOhneAnlage,
) {
  final anlagenJeAbteilung = <String, List<Machine>>{};
  for (final m in planungsAnlagen) {
    (anlagenJeAbteilung[m.abteilung] ??= []).add(m);
  }

  final spuren = <BoardSpur>[];
  for (final abteilung in Abteilung.values) {
    final anlagen = anlagenJeAbteilung[abteilung.dbValue] ?? const <Machine>[];

    if (anlagen.isEmpty) {
      // Klassisch: eine Spur für die ganze Abteilung.
      spuren.add(
        BoardSpur(
          abteilung: abteilung,
          // Einheitliche Regelarbeitszeit: alle Abteilungen 9 h. Eine
          // Pflege je Abteilung gibt es bewusst nicht mehr — bei euch ist
          // die Arbeitszeit überall gleich, nur das Personal variiert.
          kapazitaetMinuten: kStandardKapazitaetMinuten,
        ),
      );
      continue;
    }

    // Eine Spur je Anlage — mit EIGENER Tageskapazität.
    for (final m in anlagen..sort((a, b) => a.name.compareTo(b.name))) {
      spuren.add(
        BoardSpur(
          abteilung: abteilung,
          maschineId: m.id,
          maschineName: m.name,
          eignungHinweis: m.eignungHinweis,
          kapazitaetMinuten: m.kapazitaetMinutenProTag,
        ),
      );
    }

    // Zusätzlich eine Sammelspur — aber nur, wenn dort wirklich Aufträge
    // ohne (gültige) Anlage liegen. Sonst bliebe eine leere Zeile stehen.
    if (abteilungenMitTasksOhneAnlage.contains(abteilung.dbValue)) {
      spuren.add(
        BoardSpur(
          abteilung: abteilung,
          // Einheitliche Regelarbeitszeit: alle Abteilungen 9 h. Eine
          // Pflege je Abteilung gibt es bewusst nicht mehr — bei euch ist
          // die Arbeitszeit überall gleich, nur das Personal variiert.
          kapazitaetMinuten: kStandardKapazitaetMinuten,
        ),
      );
    }
  }
  return spuren;
}

/// Lädt alle Anlagen, die eine eigene Kapazitätsspur bekommen.
Future<List<Machine>> _ladePlanungsAnlagen(AppDatabase db) async {
  return (db.select(db.machines)
        ..where((m) => m.deletedAt.isNull())
        ..where((m) => m.istPlanungsressource.equals(true)))
      .get();
}
