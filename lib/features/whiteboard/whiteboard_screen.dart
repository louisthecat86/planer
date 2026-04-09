import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/providers/database_provider.dart';
import '../../core/database/database.dart';
import 'task_detail_sheet.dart';
import 'whiteboard_provider.dart';

// ---------------------------------------------------------------------------
// Konstanten
// ---------------------------------------------------------------------------

const _kLabelWidth = 110.0;
const _kMinTimelineWidth = 780.0; // Mindestbreite für 04–17 Uhr (1 px/min)
const _kLaneHeight = 54.0; // Höhe einer Kartenzeile
const _kRowPadding = 6.0; // Padding oben/unten pro Abteilung
const _kHeaderHeight = 32.0;
const _kDaySelectorHeight = 44.0;
const _kWorkStartHour = 4;
const _kWorkEndHour = 17;
const _kWorkMinutes = (_kWorkEndHour - _kWorkStartHour) * 60; // 780 min
const _kSnapMinutes = 5; // Auf 5-Minuten-Raster einrasten
const _kDayLabels = ['Mo', 'Di', 'Mi', 'Do', 'Fr'];

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

/// Erzeugt HH:MM-String aus Gesamtminuten.
String _minutesToHHMM(int minutes) {
  final h = (minutes ~/ 60).toString().padLeft(2, '0');
  final m = (minutes % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

// ---------------------------------------------------------------------------
// Lane-Berechnung (überlappende Tasks stapeln)
// ---------------------------------------------------------------------------

/// Weist jeder Task eine Lane (Zeile) zu, damit sich überlappende Tasks
/// nicht überlagern.
List<(WhiteboardTask task, int lane)> _assignLanes(List<WhiteboardTask> tasks) {
  final sorted = [...tasks]..sort((a, b) {
      final aS = a.startMinutes ?? (_kWorkStartHour * 60);
      final bS = b.startMinutes ?? (_kWorkStartHour * 60);
      return aS.compareTo(bS);
    });

  // laneEnds[i] = der früheste Zeitpunkt, ab dem Lane i wieder frei ist.
  final laneEnds = <int>[];
  final result = <(WhiteboardTask, int)>[];

  for (final task in sorted) {
    final start = task.startMinutes ?? (_kWorkStartHour * 60);
    final end = start + task.task.geplanteDauerMinuten.toInt();

    int lane = -1;
    for (int i = 0; i < laneEnds.length; i++) {
      if (laneEnds[i] <= start) {
        lane = i;
        laneEnds[i] = end;
        break;
      }
    }
    if (lane == -1) {
      lane = laneEnds.length;
      laneEnds.add(end);
    }
    result.add((task, lane));
  }

  return result;
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
  // ---- Navigation ----

  void _previousDay() {
    final current = ref.read(selectedDateProvider);
    ref.read(selectedDateProvider.notifier).state =
        current.subtract(const Duration(days: 1));
  }

  void _nextDay() {
    final current = ref.read(selectedDateProvider);
    ref.read(selectedDateProvider.notifier).state =
        current.add(const Duration(days: 1));
  }

  void _goToToday() {
    final now = DateTime.now();
    ref.read(selectedDateProvider.notifier).state =
        DateTime(now.year, now.month, now.day);
  }

  void _selectDay(int weekday) {
    // weekday: 1=Mo … 5=Fr
    final current = ref.read(selectedDateProvider);
    final monday = mondayOfWeek(current);
    ref.read(selectedDateProvider.notifier).state =
        monday.add(Duration(days: weekday - 1));
  }

  // ---- Task verschieben (Zeitänderung) ----

  Future<void> _updateTaskTime(WhiteboardTask wbTask, String newStart) async {
    final db = ref.read(databaseProvider);
    await (db.update(db.productionTasks)
          ..where((t) => t.id.equals(wbTask.task.id)))
        .write(ProductionTasksCompanion(
      startZeit: Value(newStart),
      updatedAt: Value(DateTime.now()),
    ),);
    ref.invalidate(dailyTasksProvider);
  }

  // ---- Produkt planen ----

  Future<void> _openPlanDialog() async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: const _PlanProductSheet(),
      ),
    );
    if (changed == true) ref.invalidate(dailyTasksProvider);
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    final date = ref.watch(selectedDateProvider);
    final tasksAsync = ref.watch(dailyTasksProvider);
    final kw = _isoWeekNumber(date);
    final weekdayName = [
      'Montag',
      'Dienstag',
      'Mittwoch',
      'Donnerstag',
      'Freitag',
      'Samstag',
      'Sonntag',
    ][date.weekday - 1];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Vorheriger Tag',
          onPressed: _previousDay,
        ),
        title: Text(
          'KW $kw · $weekdayName ${date.day}.${date.month}.${date.year}',
          style: const TextStyle(fontSize: 15),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.today),
            tooltip: 'Heute',
            onPressed: _goToToday,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Nächster Tag',
            onPressed: _nextDay,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openPlanDialog,
        icon: const Icon(Icons.add),
        label: const Text('Produkt planen'),
      ),
      body: Column(
        children: [
          // Wochentags-Tabs
          _DaySelector(
            selectedDate: date,
            onSelect: _selectDay,
          ),
          // Timeline-Board
          Expanded(
            child: tasksAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Fehler: $e')),
              data: (tasks) => _TimelineBoard(
                tasks: tasks,
                onUpdateTime: _updateTaskTime,
                onTapTask: (wbTask) async {
                  final changed =
                      await showTaskDetailSheet(context, ref, wbTask);
                  if (changed) ref.invalidate(dailyTasksProvider);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Wochentags-Auswahl (Mo–Fr Tabs)
// ---------------------------------------------------------------------------

class _DaySelector extends StatelessWidget {
  const _DaySelector({
    required this.selectedDate,
    required this.onSelect,
  });

  final DateTime selectedDate;
  final void Function(int weekday) onSelect;

  @override
  Widget build(BuildContext context) {
    final monday = mondayOfWeek(selectedDate);
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final colors = Theme.of(context).colorScheme;

    return Container(
      height: _kDaySelectorHeight,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < 5; i++) ...[
            Expanded(
              child: _dayTab(
                context,
                monday.add(Duration(days: i)),
                todayDate,
                colors,
                i,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dayTab(
    BuildContext context,
    DateTime date,
    DateTime todayDate,
    ColorScheme colors,
    int index,
  ) {
    final isSelected = date == selectedDate;
    final isToday = date == todayDate;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onSelect(index + 1),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? colors.primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _kDayLabels[index],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? colors.primary
                      : isToday
                          ? Colors.blue.shade700
                          : null,
                ),
              ),
              Text(
                '${date.day}.${date.month}.',
                style: TextStyle(
                  fontSize: 11,
                  color: isSelected
                      ? colors.primary
                      : colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Timeline-Board (Labels links + scrollbarer Timeline-Bereich)
// ---------------------------------------------------------------------------

class _TimelineBoard extends StatelessWidget {
  const _TimelineBoard({
    required this.tasks,
    required this.onUpdateTime,
    required this.onTapTask,
  });

  final List<WhiteboardTask> tasks;
  final Future<void> Function(WhiteboardTask, String) onUpdateTime;
  final void Function(WhiteboardTask) onTapTask;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - _kLabelWidth;
        final timelineWidth = availableWidth < _kMinTimelineWidth
            ? _kMinTimelineWidth
            : availableWidth;

        // Zeilenhöhen pro Abteilung berechnen (abhängig von Lanes)
        final rowHeights = <Abteilung, double>{};
        final rowLanes = <Abteilung, List<(WhiteboardTask, int)>>{};
        for (final abt in Abteilung.values) {
          final deptTasks =
              tasks.where((t) => t.abteilungEnum == abt).toList();
          final lanes = _assignLanes(deptTasks);
          rowLanes[abt] = lanes;
          final maxLane = lanes.isEmpty
              ? 0
              : lanes.map((e) => e.$2).reduce((a, b) => a > b ? a : b);
          rowHeights[abt] =
              (maxLane + 1) * _kLaneHeight + _kRowPadding * 2;
          if (rowHeights[abt]! < _kLaneHeight + _kRowPadding * 2) {
            rowHeights[abt] = _kLaneHeight + _kRowPadding * 2;
          }
        }

        return Row(
          children: [
            // Fixierte Labels links
            SizedBox(
              width: _kLabelWidth,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // Spacer für die Zeitachsen-Kopfzeile
                    const SizedBox(height: _kHeaderHeight),
                    for (final abt in Abteilung.values)
                      _DeptLabel(
                        abt: abt,
                        height: rowHeights[abt]!,
                        tasks: tasks
                            .where((t) => t.abteilungEnum == abt)
                            .toList(),
                      ),
                  ],
                ),
              ),
            ),
            // Scrollbarer Timeline-Bereich
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: SizedBox(
                  width: timelineWidth,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _TimelineHeader(
                          width: timelineWidth,
                        ),
                        for (final abt in Abteilung.values)
                          _DepartmentTimelineRow(
                            abt: abt,
                            height: rowHeights[abt]!,
                            timelineWidth: timelineWidth,
                            lanes: rowLanes[abt]!,
                            onUpdateTime: onUpdateTime,
                            onTapTask: onTapTask,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Abteilungs-Label (links)
// ---------------------------------------------------------------------------

class _DeptLabel extends StatelessWidget {
  const _DeptLabel({
    required this.abt,
    required this.height,
    required this.tasks,
  });

  final Abteilung abt;
  final double height;
  final List<WhiteboardTask> tasks;

  @override
  Widget build(BuildContext context) {
    // Kapazitätsberechnung
    final totalMin = tasks.fold<double>(
      0,
      (sum, t) => sum + t.task.geplanteDauerMinuten,
    );
    final ratio = _kWorkMinutes > 0
        ? (totalMin / _kWorkMinutes).clamp(0.0, 1.5)
        : 0.0;
    final capColor = ratio > 1.0
        ? Colors.red
        : ratio > 0.75
            ? Colors.orange
            : Colors.green;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: abt.farbe.withValues(alpha: 0.06),
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
          right: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: abt.farbe,
                child: Text(
                  abt.kurzcode,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
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
          const SizedBox(height: 6),
          // Kapazitätsbalken
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: ratio > 1.0 ? 1.0 : ratio,
              backgroundColor: Colors.grey.shade200,
              color: capColor,
              minHeight: 5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${(ratio * 100).toStringAsFixed(0)}% · ${totalMin.toStringAsFixed(0)} min',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: capColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Timeline-Kopfzeile (Stundenmarker)
// ---------------------------------------------------------------------------

class _TimelineHeader extends StatelessWidget {
  const _TimelineHeader({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: _kHeaderHeight,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: CustomPaint(
        size: Size(width, _kHeaderHeight),
        painter: _HeaderPainter(),
      ),
    );
  }
}

class _HeaderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 0.5;
    final textStyle = TextStyle(fontSize: 10, color: Colors.grey.shade700);

    for (var h = _kWorkStartHour; h <= _kWorkEndHour; h++) {
      final x = _hourToX(h.toDouble(), size.width);
      canvas.drawLine(
          Offset(x, size.height - 8), Offset(x, size.height), linePaint,);

      final tp = TextPainter(
        text: TextSpan(
          text: '${h.toString().padLeft(2, '0')}:00',
          style: textStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, 4));
    }
  }

  double _hourToX(double hour, double width) {
    return ((hour - _kWorkStartHour) / (_kWorkEndHour - _kWorkStartHour)) *
        width;
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ---------------------------------------------------------------------------
// Abteilungs-Zeile (Timeline mit positionierten Karten)
// ---------------------------------------------------------------------------

class _DepartmentTimelineRow extends StatefulWidget {
  const _DepartmentTimelineRow({
    required this.abt,
    required this.height,
    required this.timelineWidth,
    required this.lanes,
    required this.onUpdateTime,
    required this.onTapTask,
  });

  final Abteilung abt;
  final double height;
  final double timelineWidth;
  final List<(WhiteboardTask, int)> lanes;
  final Future<void> Function(WhiteboardTask, String) onUpdateTime;
  final void Function(WhiteboardTask) onTapTask;

  @override
  State<_DepartmentTimelineRow> createState() =>
      _DepartmentTimelineRowState();
}

class _DepartmentTimelineRowState extends State<_DepartmentTimelineRow> {
  String? _draggingTaskId;
  double _dragDeltaX = 0;

  double _minutesToPx(double minutes) =>
      (minutes / _kWorkMinutes) * widget.timelineWidth;

  double _pxToMinutes(double px) =>
      (px / widget.timelineWidth) * _kWorkMinutes;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.timelineWidth,
      height: widget.height,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // Hintergrund-Raster
          Positioned.fill(
            child: CustomPaint(
              painter: _GridPainter(abtFarbe: widget.abt.farbe),
            ),
          ),
          // Aktuelle-Uhrzeit-Linie
          _NowLine(timelineWidth: widget.timelineWidth),
          // Karten
          for (final (task, lane) in widget.lanes)
            _buildCard(task, lane),
        ],
      ),
    );
  }

  Widget _buildCard(WhiteboardTask task, int lane) {
    final startMin =
        (task.startMinutes ?? (_kWorkStartHour * 60)) - _kWorkStartHour * 60;
    final durationMin = task.task.geplanteDauerMinuten;

    double left = _minutesToPx(startMin.toDouble());
    final cardWidth = _minutesToPx(durationMin).clamp(30.0, double.infinity);

    if (task.task.id == _draggingTaskId) {
      left += _dragDeltaX;
    }

    final top = _kRowPadding + lane * _kLaneHeight;
    final isDragging = task.task.id == _draggingTaskId;

    return Positioned(
      left: left,
      top: top,
      width: cardWidth,
      height: _kLaneHeight - 4,
      child: GestureDetector(
        onTap: () => widget.onTapTask(task),
        onHorizontalDragStart: (_) {
          setState(() {
            _draggingTaskId = task.task.id;
            _dragDeltaX = 0;
          });
        },
        onHorizontalDragUpdate: (d) {
          setState(() => _dragDeltaX += d.delta.dx);
        },
        onHorizontalDragEnd: (_) => _finishDrag(task, startMin),
        onHorizontalDragCancel: () {
          setState(() {
            _draggingTaskId = null;
            _dragDeltaX = 0;
          });
        },
        child: _TimelineCard(
          task: task,
          isDragging: isDragging,
        ),
      ),
    );
  }

  void _finishDrag(WhiteboardTask task, int originalStartMin) {
    final deltaMinutes = _pxToMinutes(_dragDeltaX).round();
    final rawNewStart =
        _kWorkStartHour * 60 + originalStartMin + deltaMinutes;
    // Auf Raster snappen
    final snapped = ((rawNewStart / _kSnapMinutes).round() * _kSnapMinutes)
        .clamp(
      _kWorkStartHour * 60,
      _kWorkEndHour * 60 - task.task.geplanteDauerMinuten.toInt(),
    );
    final newStartStr = _minutesToHHMM(snapped);

    setState(() {
      _draggingTaskId = null;
      _dragDeltaX = 0;
    });

    widget.onUpdateTime(task, newStartStr);
  }
}

// ---------------------------------------------------------------------------
// Hintergrund-Raster (Stundenlinien)
// ---------------------------------------------------------------------------

class _GridPainter extends CustomPainter {
  _GridPainter({required this.abtFarbe});
  final Color abtFarbe;

  @override
  void paint(Canvas canvas, Size size) {
    // Leichter Abteilungs-Farbhintergrund
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = abtFarbe.withValues(alpha: 0.03),
    );

    final linePaint = Paint()
      ..color = Colors.grey.shade200
      ..strokeWidth = 0.5;
    final halfHourPaint = Paint()
      ..color = Colors.grey.shade100
      ..strokeWidth = 0.5;

    for (var h = _kWorkStartHour; h <= _kWorkEndHour; h++) {
      final x = ((h - _kWorkStartHour) / (_kWorkEndHour - _kWorkStartHour)) *
          size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);

      // Halbe-Stunde-Linien
      if (h < _kWorkEndHour) {
        final x30 =
            ((h + 0.5 - _kWorkStartHour) / (_kWorkEndHour - _kWorkStartHour)) *
                size.width;
        canvas.drawLine(
            Offset(x30, 0), Offset(x30, size.height), halfHourPaint,);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ---------------------------------------------------------------------------
// Aktuelle-Uhrzeit-Linie
// ---------------------------------------------------------------------------

class _NowLine extends StatelessWidget {
  const _NowLine({required this.timelineWidth});
  final double timelineWidth;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    if (nowMinutes < _kWorkStartHour * 60 ||
        nowMinutes > _kWorkEndHour * 60) {
      return const SizedBox.shrink();
    }

    final x = ((nowMinutes - _kWorkStartHour * 60) / _kWorkMinutes) *
        timelineWidth;

    return Positioned(
      left: x,
      top: 0,
      bottom: 0,
      child: Container(
        width: 2,
        color: Colors.red.withValues(alpha: 0.7),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Timeline-Karte
// ---------------------------------------------------------------------------

Color _statusColor(String status) {
  switch (status) {
    case 'in_arbeit':
      return Colors.orange;
    case 'fertig':
      return Colors.green;
    default:
      return Colors.blue;
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'in_arbeit':
      return 'Läuft';
    case 'fertig':
      return '✓';
    case 'storniert':
      return '✗';
    default:
      return '';
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.task, this.isDragging = false});

  final WhiteboardTask task;
  final bool isDragging;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(task.task.status);
    final abtColor = task.abteilungEnum.farbe;
    final startMin = task.startMinutes;
    final endMin = startMin != null
        ? startMin + task.task.geplanteDauerMinuten.toInt()
        : null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      decoration: BoxDecoration(
        color: abtColor.withValues(alpha: isDragging ? 0.25 : 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDragging ? abtColor : abtColor.withValues(alpha: 0.4),
          width: isDragging ? 2 : 1,
        ),
        boxShadow: isDragging
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Row(
        children: [
          // Status-Streifen
          Container(
            width: 3,
            margin: const EdgeInsets.only(right: 5),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Inhalt
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  task.produktName,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Text(
                      '${task.task.mengeKg.toStringAsFixed(0)} kg',
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    if (startMin != null && endMin != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '${_minutesToHHMM(startMin)}–${_minutesToHHMM(endMin)}',
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                    if (_statusLabel(task.task.status).isNotEmpty) ...[
                      const Spacer(),
                      Text(
                        _statusLabel(task.task.status),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Produkt-Planen-Dialog
// ---------------------------------------------------------------------------

class _PlanProductSheet extends ConsumerStatefulWidget {
  const _PlanProductSheet();

  @override
  ConsumerState<_PlanProductSheet> createState() => _PlanProductSheetState();
}

class _PlanProductSheetState extends ConsumerState<_PlanProductSheet> {
  final _searchController = TextEditingController();
  final _mengeController = TextEditingController(text: '100');
  List<Product> _products = [];
  Product? _selectedProduct;
  List<ProductStep> _steps = [];
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final db = ref.read(databaseProvider);
    final products = await (db.select(db.products)
          ..where((p) => p.deletedAt.isNull())
          ..orderBy([(p) => OrderingTerm.asc(p.artikelbezeichnung)]))
        .get();
    if (mounted) setState(() => _products = products);
  }

  Future<void> _selectProduct(Product product) async {
    final db = ref.read(databaseProvider);
    final steps = await (db.select(db.productSteps)
          ..where((s) => s.productId.equals(product.id))
          ..where((s) => s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm.asc(s.reihenfolge)]))
        .get();
    setState(() {
      _selectedProduct = product;
      _steps = steps;
    });
  }

  Future<void> _create() async {
    final product = _selectedProduct;
    if (product == null) return;
    final menge = double.tryParse(_mengeController.text.replaceAll(',', '.'));
    if (menge == null || menge <= 0) return;

    setState(() => _isCreating = true);

    final db = ref.read(databaseProvider);
    final date = ref.read(selectedDateProvider);

    final rohwareBedarf = await createTasksFromProduct(
      db: db,
      productId: product.id,
      mengeKg: menge,
      datum: date,
    );

    if (mounted) {
      if (rohwareBedarf > menge) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Rohwaren-Bedarf: ${rohwareBedarf.toStringAsFixed(1)} kg '
              'für ${menge.toStringAsFixed(1)} kg Fertigware',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
      Navigator.of(context).pop(true);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _mengeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final query = _searchController.text.toLowerCase();
    final filtered = query.isEmpty
        ? _products
        : _products
            .where((p) =>
                p.artikelbezeichnung.toLowerCase().contains(query) ||
                p.artikelnummer.toLowerCase().contains(query),)
            .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              // Drag-Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              const Text(
                'Produkt planen',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Wähle ein Produkt — alle Abteilungsschritte werden als '
                'Tasks auf der Zeitleiste angelegt.',
                style: TextStyle(
                  fontSize: 13,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),

              // Produktsuche
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: 'Produkt suchen',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),

              // Produktliste
              if (_selectedProduct == null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final p = filtered[index];
                      return ListTile(
                        dense: true,
                        title: Text(p.artikelbezeichnung),
                        subtitle: Text(p.artikelnummer),
                        onTap: () => _selectProduct(p),
                      );
                    },
                  ),
                ),

              // Gewähltes Produkt
              if (_selectedProduct != null) ...[
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.inventory_2),
                    title: Text(_selectedProduct!.artikelbezeichnung),
                    subtitle: Text(_selectedProduct!.artikelnummer),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        _selectedProduct = null;
                        _steps = [];
                      }),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Schritte anzeigen
                if (_steps.isNotEmpty) ...[
                  Text(
                    'Produktions-Schritte',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final step in _steps)
                    _StepPreviewTile(step: step),
                  const SizedBox(height: 16),
                ],

                if (_steps.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Keine Produktions-Schritte hinterlegt.\n'
                      'Lege zuerst Schritte im Produkt an.',
                      style: TextStyle(
                        color: colors.error,
                        fontSize: 13,
                      ),
                    ),
                  ),

                // Menge
                TextField(
                  controller: _mengeController,
                  decoration: const InputDecoration(
                    labelText: 'Menge (kg)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 20),

                // Erstellen-Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed:
                        _isCreating || _steps.isEmpty ? null : _create,
                    icon: _isCreating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text(
                      _isCreating
                          ? 'Wird erstellt …'
                          : '${_steps.length} Tasks anlegen',
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Vorschau-Kachel für einen Produktions-Schritt im Planungs-Dialog.
class _StepPreviewTile extends StatelessWidget {
  const _StepPreviewTile({required this.step});

  final ProductStep step;

  @override
  Widget build(BuildContext context) {
    final abt = Abteilung.fromDbValue(step.abteilung);
    final ausbeute = step.ausbeuteFaktor;
    final wartezeit = step.wartezeitMinuten;
    final maxCharge = step.maxChargenKg;

    // Detail-Info zusammenbauen
    final details = <String>[
      '${step.basisDauerMinuten.toStringAsFixed(0)} min',
      '${step.basisMitarbeiter} MA',
    ];
    if (ausbeute != null && ausbeute < 1.0) {
      details.add('${(ausbeute * 100).toStringAsFixed(0)}% Ausbeute');
    }
    if (wartezeit != null && wartezeit > 0) {
      details.add('+${wartezeit.toStringAsFixed(0)} min Wartezeit');
    }
    if (maxCharge != null && maxCharge > 0) {
      details.add('max ${maxCharge.toStringAsFixed(0)} kg/Charge');
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: abt.farbe,
            child: Text(
              abt.kurzcode,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${step.reihenfolge}. ${abt.anzeigeName}',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  details.join(' · '),
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          if (step.maschine != null)
            Text(
              step.maschine!,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
        ],
      ),
    );
  }
}
