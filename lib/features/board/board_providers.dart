import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/providers/department_capacity_provider.dart';

/// Standard-Kapazität pro Abteilung und Tag in Minuten (8 h), wenn für die
/// Abteilung kein abweichender Wert gepflegt ist.
const double kStandardKapazitaetMinuten = 480;

/// Auslastungs-Status einer Abteilung an einem Tag — steuert die Ampelfarbe
/// auf dem Board.
///
/// - [frei]: unter 75 % belegt → es passt noch was rein (grau).
/// - [gut]: 75–100 % belegt → gut gefüllt (grün).
/// - [ueberbucht]: über 100 % → mehr geplant als Kapazität (rot).
enum CapacityStatus { frei, gut, ueberbucht }

/// Gemeinsame Auslastungs-Rechnung für Wochenzelle und Tages-Spur.
mixin _Auslastung {
  List<BoardTask> get tasks;
  double get kapazitaetMinuten;

  double get belegtMinuten =>
      tasks.fold(0, (summe, t) => summe + t.dauerMinuten);

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

  /// Manuelle Reihenfolge innerhalb der Abteilung an einem Tag.
  final int sortierung;

  /// 'geplant' | 'in_arbeit' | 'fertig' (storniert wird gar nicht geladen).
  final String status;
}

/// Eine Zelle im Wochenboard: eine Abteilung an einem Tag.
class BoardCell with _Auslastung {
  BoardCell({
    required this.abteilung,
    required this.tag,
    required this.tasks,
    required this.kapazitaetMinuten,
  });

  final Abteilung abteilung;
  final DateTime tag;
  @override
  final List<BoardTask> tasks;
  @override
  final double kapazitaetMinuten;
}

/// Das komplette Wochenboard (Abteilungen × Mo–Fr).
class WeekBoard {
  WeekBoard({
    required this.wochenStart,
    required this.tage,
    required this.abteilungen,
    required this.cells,
  });

  /// Montag der Woche, 00:00 Uhr.
  final DateTime wochenStart;

  /// Die angezeigten Tage (Mo–Fr).
  final List<DateTime> tage;

  /// Alle Abteilungen als Zeilen.
  final List<Abteilung> abteilungen;

  /// Zellen, indiziert über [_cellKey].
  final Map<String, BoardCell> cells;

  /// Zelle für eine Abteilung an einem Tag. Liefert eine leere Zelle, falls
  /// die Kombination nicht existiert (sollte bei Mo–Fr nicht vorkommen).
  BoardCell cellFor(Abteilung abteilung, DateTime tag) {
    final tagNorm = DateTime(tag.year, tag.month, tag.day);
    return cells[_cellKey(abteilung, tagNorm)] ??
        BoardCell(
          abteilung: abteilung,
          tag: tagNorm,
          tasks: const [],
          kapazitaetMinuten: kStandardKapazitaetMinuten,
        );
  }
}

/// Eine Abteilungs-Spur in der Tagesübersicht.
class DayLane with _Auslastung {
  DayLane({
    required this.abteilung,
    required this.tasks,
    required this.kapazitaetMinuten,
  });

  final Abteilung abteilung;
  @override
  final List<BoardTask> tasks;
  @override
  final double kapazitaetMinuten;
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

/// Wochenboard für die Woche, in die [anyDayInWeek] fällt.
///
/// Reagiert automatisch auf Kapazitäts-Änderungen (watch auf den Capacity-
/// Provider). Nach Task-Mutationen (verschieben, anlegen, löschen) muss der
/// Provider invalidiert werden:
/// `ref.invalidate(weekBoardProvider(anyDayInWeek))`.
final weekBoardProvider =
    FutureProvider.family<WeekBoard, DateTime>((ref, anyDayInWeek) async {
  final db = ref.watch(databaseProvider);
  final caps =
      ref.watch(departmentCapacityNotifierProvider).valueOrNull ??
          const <String, double>{};

  final wochenStart = _montag(anyDayInWeek);
  final tage = List.generate(
    5,
    (i) => wochenStart.add(Duration(days: i)),
  );
  final wochenEndeExkl = wochenStart.add(const Duration(days: 7));

  final alleTasks = await _ladeBoardTasks(db, wochenStart, wochenEndeExkl);

  // Tasks in Zell-Eimer einsortieren.
  final tasksProZelle = <String, List<BoardTask>>{};
  for (final task in alleTasks) {
    final key = _cellKey(task.abteilung, task.datum);
    (tasksProZelle[key] ??= []).add(task);
  }
  for (final liste in tasksProZelle.values) {
    _sortiereTasks(liste);
  }

  final cells = <String, BoardCell>{};
  for (final abteilung in Abteilung.values) {
    for (final tag in tage) {
      final key = _cellKey(abteilung, tag);
      cells[key] = BoardCell(
        abteilung: abteilung,
        tag: tag,
        tasks: tasksProZelle[key] ?? const [],
        kapazitaetMinuten:
            caps[abteilung.dbValue] ?? kStandardKapazitaetMinuten,
      );
    }
  }

  return WeekBoard(
    wochenStart: wochenStart,
    tage: tage,
    abteilungen: Abteilung.values,
    cells: cells,
  );
});

/// Tagesübersicht für [datum] — eine Spur pro Abteilung, Tasks nach Startzeit
/// sortiert. Funktioniert für jeden Wochentag (nicht auf Mo–Fr beschränkt).
final dayBoardProvider =
    FutureProvider.family<DayBoard, DateTime>((ref, datum) async {
  final db = ref.watch(databaseProvider);
  final caps =
      ref.watch(departmentCapacityNotifierProvider).valueOrNull ??
          const <String, double>{};

  final tag = DateTime(datum.year, datum.month, datum.day);
  final naechsterTag = tag.add(const Duration(days: 1));

  final alleTasks = await _ladeBoardTasks(db, tag, naechsterTag);

  final tasksProAbteilung = <String, List<BoardTask>>{};
  for (final task in alleTasks) {
    (tasksProAbteilung[task.abteilung.dbValue] ??= []).add(task);
  }

  final lanes = <DayLane>[];
  for (final abteilung in Abteilung.values) {
    final liste = tasksProAbteilung[abteilung.dbValue] ?? <BoardTask>[];
    _sortiereTasks(liste);
    lanes.add(
      DayLane(
        abteilung: abteilung,
        tasks: liste,
        kapazitaetMinuten:
            caps[abteilung.dbValue] ?? kStandardKapazitaetMinuten,
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

  final result = <BoardTask>[];
  for (final t in rows) {
    final abteilung = _abteilungOf(t.abteilung);
    if (abteilung == null) continue; // unbekannte Abteilung überspringen
    result.add(
      BoardTask(
        id: t.id,
        productId: t.productId,
        productName: nameById[t.productId] ?? 'Unbekannt',
        abteilung: abteilung,
        datum: DateTime(t.datum.year, t.datum.month, t.datum.day),
        startZeit: t.startZeit,
        dauerMinuten: t.geplanteDauerMinuten,
        mengeKg: t.mengeKg,
        sortierung: t.sortierung,
        status: t.status,
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
String _cellKey(Abteilung abteilung, DateTime tag) {
  final tagNorm = DateTime(tag.year, tag.month, tag.day);
  return '${abteilung.dbValue}|${tagNorm.toIso8601String()}';
}