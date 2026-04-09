import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/providers/database_provider.dart';
import '../../core/database/database.dart';
import 'whiteboard_provider.dart';

// ---------------------------------------------------------------------------
// Konstanten
// ---------------------------------------------------------------------------

const _kLabelWidth = 130.0;
const _kMinCellWidth = 155.0;
const _kMinCellHeight = 120.0;
const _kHeaderHeight = 44.0;
const _kCardWidth = 140.0;
const _dayLabels = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sonstiges'];

/// ISO-8601-Kalenderwoche (in Deutschland üblich).
int _isoWeekNumber(DateTime date) {
  final dayOfYear = date.difference(DateTime(date.year, 1, 1)).inDays + 1;
  final wday = date.weekday;
  final wn = ((dayOfYear - wday + 10) / 7).floor();
  if (wn < 1) return _isoWeekNumber(DateTime(date.year - 1, 12, 31));
  if (wn > 52) {
    final dec31 = DateTime(date.year, 12, 31);
    if (dec31.weekday < 4) return 1;
  }
  return wn;
}

// ---------------------------------------------------------------------------
// WhiteboardScreen
// ---------------------------------------------------------------------------

class WhiteboardScreen extends ConsumerStatefulWidget {
  const WhiteboardScreen({super.key});

  @override
  ConsumerState<WhiteboardScreen> createState() => _WhiteboardScreenState();
}

class _WhiteboardScreenState extends ConsumerState<WhiteboardScreen> {
  Future<void> _moveTask(
    WhiteboardTask wbTask,
    Abteilung targetAbt,
    int targetSpalte,
  ) async {
    // Keine DB-Schreibung wenn sich nichts ändert.
    if (wbTask.spalte == targetSpalte &&
        wbTask.abteilungEnum == targetAbt) {
      return;
    }

    final db = ref.read(databaseProvider);
    final weekStart = ref.read(selectedWeekStartProvider);
    final targetDate =
        weekStart.add(Duration(days: targetSpalte >= 5 ? 5 : targetSpalte));

    final oldDate = wbTask.task.datum;
    final dateDiff = targetDate.difference(oldDate);

    // 1. Verschobenen Task selbst aktualisieren.
    await (db.update(db.productionTasks)
          ..where((t) => t.id.equals(wbTask.task.id)))
        .write(
      ProductionTasksCompanion(
        datum: Value(targetDate),
        abteilung: Value(targetAbt.dbValue),
        updatedAt: Value(DateTime.now()),
      ),
    );

    // 2. Abhängige Vor-Tasks (Children) mitnehmen — gleicher Datums-Offset.
    if (dateDiff.inDays != 0) {
      await _moveDependentTasks(db, wbTask.task.id, dateDiff);
    }

    ref.invalidate(weeklyTasksProvider);
  }

  /// Verschiebt alle Tasks, die über [parentTaskId] direkt oder indirekt
  /// vom gegebenen Task abhängen, um denselben Datums-Offset.
  Future<void> _moveDependentTasks(
    AppDatabase db,
    String taskId,
    Duration dateDiff,
  ) async {
    // Vor-Tasks (parentTaskId zeigt auf den verschobenen Task).
    final children = await (db.select(db.productionTasks)
          ..where((t) => t.parentTaskId.equals(taskId))
          ..where((t) => t.deletedAt.isNull())
          ..where((t) => t.status.isNotIn(const ['storniert'])))
        .get();

    for (final child in children) {
      final newDate = child.datum.add(dateDiff);
      await (db.update(db.productionTasks)
            ..where((t) => t.id.equals(child.id)))
          .write(
        ProductionTasksCompanion(
          datum: Value(newDate),
          updatedAt: Value(DateTime.now()),
        ),
      );
      // Rekursiv: Kinder des Kindes ebenfalls verschieben.
      await _moveDependentTasks(db, child.id, dateDiff);
    }
  }

  void _previousWeek() {
    final current = ref.read(selectedWeekStartProvider);
    ref.read(selectedWeekStartProvider.notifier).state =
        current.subtract(const Duration(days: 7));
  }

  void _nextWeek() {
    final current = ref.read(selectedWeekStartProvider);
    ref.read(selectedWeekStartProvider.notifier).state =
        current.add(const Duration(days: 7));
  }

  void _goToCurrentWeek() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    ref.read(selectedWeekStartProvider.notifier).state =
        DateTime(monday.year, monday.month, monday.day);
  }

  @override
  Widget build(BuildContext context) {
    final weekStart = ref.watch(selectedWeekStartProvider);
    final tasksAsync = ref.watch(weeklyTasksProvider);
    final friday = weekStart.add(const Duration(days: 4));
    final kw = _isoWeekNumber(weekStart);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Vorherige Woche',
          onPressed: _previousWeek,
        ),
        title: Text(
          'KW $kw: ${weekStart.day}.${weekStart.month}. – '
          '${friday.day}.${friday.month}.${friday.year}',
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.today),
            tooltip: 'Aktuelle Woche',
            onPressed: _goToCurrentWeek,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Nächste Woche',
            onPressed: _nextWeek,
          ),
        ],
      ),
      body: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (tasks) => _WhiteboardGrid(
          tasks: tasks,
          weekStart: weekStart,
          onMoveTask: _moveTask,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// WhiteboardGrid – das eigentliche Board
// ---------------------------------------------------------------------------

class _WhiteboardGrid extends StatelessWidget {
  const _WhiteboardGrid({
    required this.tasks,
    required this.weekStart,
    required this.onMoveTask,
  });

  final List<WhiteboardTask> tasks;
  final DateTime weekStart;
  final Future<void> Function(WhiteboardTask, Abteilung, int) onMoveTask;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - _kLabelWidth;
        final cellWidth =
            (availableWidth / 6).clamp(_kMinCellWidth, double.infinity);
        final totalWidth = _kLabelWidth + cellWidth * 6;
        final needsHorizontalScroll = totalWidth > constraints.maxWidth;

        Widget grid = SizedBox(
          width: totalWidth,
          height: constraints.maxHeight,
          child: Column(
            children: [
              _buildHeader(context, cellWidth, todayDate),
              Expanded(
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    children: [
                      for (final abt in Abteilung.values)
                        _buildDepartmentRow(
                            context, abt, cellWidth, todayDate,),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );

        if (needsHorizontalScroll) {
          grid = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: grid,
          );
        }

        return grid;
      },
    );
  }

  // ---- Header-Zeile ----

  Widget _buildHeader(
      BuildContext context, double cellWidth, DateTime todayDate,) {
    return Container(
      height: _kHeaderHeight,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Row(
        children: [
          // Leere Ecke oben-links.
          SizedBox(
            width: _kLabelWidth,
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                'Abteilung',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
          ),
          for (var i = 0; i < 6; i++)
            SizedBox(
              width: cellWidth,
              child: _headerCell(context, i, todayDate),
            ),
        ],
      ),
    );
  }

  Widget _headerCell(BuildContext context, int col, DateTime todayDate) {
    final date = weekStart.add(Duration(days: col >= 5 ? 5 : col));
    final isToday = date == todayDate && col < 5;
    final label =
        col < 5 ? '${_dayLabels[col]} ${date.day}.${date.month}.' : 'Sonstiges';

    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: Colors.grey.shade300, width: 0.5),
        ),
        color: isToday ? Colors.blue.withValues(alpha: 0.08) : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: isToday ? Colors.blue.shade700 : null,
        ),
      ),
    );
  }

  // ---- Abteilungs-Zeile ----

  Widget _buildDepartmentRow(
    BuildContext context,
    Abteilung abt,
    double cellWidth,
    DateTime todayDate,
  ) {
    return IntrinsicHeight(
      child: Container(
        constraints: const BoxConstraints(minHeight: _kMinCellHeight),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Label links
            SizedBox(
              width: _kLabelWidth,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                decoration: BoxDecoration(
                  border: Border(
                    right: BorderSide(color: Colors.grey.shade300),
                  ),
                  color: abt.farbe.withValues(alpha: 0.06),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: abt.farbe,
                      child: Text(
                        abt.kurzcode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        abt.anzeigeName,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Tages-Zellen
            for (var col = 0; col < 6; col++)
              SizedBox(
                width: cellWidth,
                child: _WhiteboardCell(
                  abteilung: abt,
                  spalte: col,
                  isToday: col < 5 &&
                      weekStart.add(Duration(days: col)) == todayDate,
                  tasks: tasks
                      .where(
                          (t) => t.abteilungEnum == abt && t.spalte == col,)
                      .toList(),
                  onMoveTask: onMoveTask,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Einzelne Zelle (DragTarget)
// ---------------------------------------------------------------------------

class _WhiteboardCell extends StatelessWidget {
  const _WhiteboardCell({
    required this.abteilung,
    required this.spalte,
    required this.isToday,
    required this.tasks,
    required this.onMoveTask,
  });

  final Abteilung abteilung;
  final int spalte;
  final bool isToday;
  final List<WhiteboardTask> tasks;
  final Future<void> Function(WhiteboardTask, Abteilung, int) onMoveTask;

  @override
  Widget build(BuildContext context) {
    return DragTarget<WhiteboardTask>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) {
        onMoveTask(details.data, abteilung, spalte);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;

        return Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: Colors.grey.shade200, width: 0.5),
            ),
            color: isHovering
                ? Colors.blue.withValues(alpha: 0.12)
                : isToday
                    ? Colors.blue.withValues(alpha: 0.04)
                    : null,
          ),
          child: tasks.isEmpty
              ? const SizedBox.expand()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final task in tasks)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Draggable<WhiteboardTask>(
                          data: task,
                          feedback: Material(
                            elevation: 8,
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: _kCardWidth,
                              child: _TaskCard(task: task, isDragging: true),
                            ),
                          ),
                          childWhenDragging: Opacity(
                            opacity: 0.30,
                            child: _TaskCard(task: task),
                          ),
                          child: _TaskCard(task: task),
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Auftrags-Karte
// ---------------------------------------------------------------------------

Color _statusColor(String status) {
  switch (status) {
    case 'in_arbeit':
      return Colors.orange;
    case 'fertig':
      return Colors.green;
    default:
      return Colors.blue; // 'geplant'
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'in_arbeit':
      return 'In Arbeit';
    case 'fertig':
      return 'Fertig';
    case 'storniert':
      return 'Storniert';
    default:
      return 'Geplant';
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, this.isDragging = false});

  final WhiteboardTask task;
  final bool isDragging;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(task.task.status);

    return Card(
      elevation: isDragging ? 8 : 1,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: color, width: 3),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              task.produktName,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Text(
                  '${task.task.mengeKg.toStringAsFixed(0)} kg',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _statusLabel(task.task.status),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
            if (task.task.startZeit != null) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(Icons.schedule, size: 11, color: Colors.grey.shade500),
                  const SizedBox(width: 3),
                  Text(
                    task.task.startZeit!,
                    style:
                        TextStyle(fontSize: 10, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 10, color: Colors.grey.shade500),
                const SizedBox(width: 3),
                Text(
                  '${task.task.datum.day}.${task.task.datum.month}.',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
