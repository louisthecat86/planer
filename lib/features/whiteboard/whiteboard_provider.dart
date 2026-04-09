import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';

// ---------------------------------------------------------------------------
// Wochen-Auswahl
// ---------------------------------------------------------------------------

/// Montag der aktuell ausgewählten Woche (00:00 Uhr lokal).
final selectedWeekStartProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  final monday = now.subtract(Duration(days: now.weekday - 1));
  return DateTime(monday.year, monday.month, monday.day);
});

// ---------------------------------------------------------------------------
// Whiteboard-Task-Modell
// ---------------------------------------------------------------------------

/// Ein [ProductionTask] angereichert mit Produktname fürs Whiteboard.
class WhiteboardTask {
  WhiteboardTask({
    required this.task,
    required this.produktName,
    required this.artikelnummer,
  });

  final ProductionTask task;
  final String produktName;
  final String artikelnummer;

  /// Spaltenindex: 0=Mo, 1=Di, 2=Mi, 3=Do, 4=Fr, 5=Sonstiges (Sa/So).
  int get spalte {
    final wd = task.datum.weekday; // 1=Mo … 7=So
    return (wd >= 1 && wd <= 5) ? wd - 1 : 5;
  }

  Abteilung get abteilungEnum => Abteilung.fromDbValue(task.abteilung);
}

// ---------------------------------------------------------------------------
// Daten laden
// ---------------------------------------------------------------------------

/// Alle nicht-stornierten Tasks der gewählten Woche mit Produktinfos.
final weeklyTasksProvider = FutureProvider<List<WhiteboardTask>>((ref) async {
  final db = ref.watch(databaseProvider);
  final weekStart = ref.watch(selectedWeekStartProvider);
  final weekEnd = weekStart.add(const Duration(days: 7));

  final query = db.select(db.productionTasks).join([
    innerJoin(
      db.products,
      db.products.id.equalsExp(db.productionTasks.productId),
    ),
  ])
    ..where(db.productionTasks.deletedAt.isNull())
    ..where(db.productionTasks.datum.isBiggerOrEqualValue(weekStart))
    ..where(db.productionTasks.datum.isSmallerThanValue(weekEnd))
    ..where(db.productionTasks.status.isNotIn(const ['storniert']));

  final rows = await query.get();

  return rows.map((row) {
    final task = row.readTable(db.productionTasks);
    final product = row.readTable(db.products);
    return WhiteboardTask(
      task: task,
      produktName: product.artikelbezeichnung,
      artikelnummer: product.artikelnummer,
    );
  }).toList();
});
