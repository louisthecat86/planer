import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';
import '../whiteboard/task_detail_sheet.dart';
import '../whiteboard/whiteboard_provider.dart';
import 'board_print_service.dart';
import 'board_providers.dart';

const double _kLabelWidth = 116;
const _kDayLabels = ['Mo', 'Di', 'Mi', 'Do', 'Fr'];
const _kWkShort = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

enum _Modus { woche, tag }

/// ISO-8601-Kalenderwoche.
int _isoKw(DateTime date) {
  final d = DateTime(date.year, date.month, date.day);
  final dayOfYear = d.difference(DateTime(d.year, 1, 1)).inDays + 1;
  final wday = d.weekday;
  final wn = ((dayOfYear - wday + 10) / 7).floor();
  if (wn < 1) return _isoKw(DateTime(d.year - 1, 12, 31));
  if (wn > 52) {
    final dec31 = DateTime(d.year, 12, 31);
    if (dec31.weekday < 4) return 1;
  }
  return wn;
}

String _fmtTagTitel(DateTime d) =>
    '${_kWkShort[d.weekday - 1]} ${d.day}.${d.month}.${d.year}';

/// Minuten als Stunden mit max. einer Nachkommastelle ("6.5", "8").
String _fmtStunden(double minuten) {
  final s = (minuten / 60).toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

Color _ampelFarbe(CapacityStatus status) {
  switch (status) {
    case CapacityStatus.frei:
      return const Color(0xFF9E9E9E);
    case CapacityStatus.gut:
      return const Color(0xFF2E7D32);
    case CapacityStatus.ueberbucht:
      return const Color(0xFFC62828);
  }
}

String _ampelWort(CapacityStatus status) {
  switch (status) {
    case CapacityStatus.frei:
      return 'Platz frei';
    case CapacityStatus.gut:
      return 'gut gefüllt';
    case CapacityStatus.ueberbucht:
      return 'überbucht';
  }
}

// ---------------------------------------------------------------------------
// WeekBoardScreen
// ---------------------------------------------------------------------------

/// Das Planungsboard mit zwei Ansichten:
/// - **Woche**: Abteilungen als Zeilen, Mo–Fr als Spalten, Ampelbalken,
///   Karten per Drag auf einen anderen Tag verschiebbar.
/// - **Tag**: schlanke Liste pro Abteilung (Auslastung + Aufträge) für den
///   gewählten Tag.
///
/// [oeffnePlanenDirekt] = true öffnet beim Aufruf sofort den
/// „Produkt planen"-Dialog (für die „Planen"-Kachel auf dem Home-Screen).
class WeekBoardScreen extends ConsumerStatefulWidget {
  const WeekBoardScreen({super.key, this.oeffnePlanenDirekt = false});

  final bool oeffnePlanenDirekt;

  @override
  ConsumerState<WeekBoardScreen> createState() => _WeekBoardScreenState();
}

class _WeekBoardScreenState extends ConsumerState<WeekBoardScreen> {
  _Modus _modus = _Modus.woche;
  bool _planenGeoeffnet = false;

  // ---- Navigation (je nach Modus Woche oder Tag) ----

  void _zurueck() {
    final d = ref.read(selectedDateProvider);
    final delta = _modus == _Modus.woche ? 7 : 1;
    ref.read(selectedDateProvider.notifier).state =
        d.subtract(Duration(days: delta));
  }

  void _vor() {
    final d = ref.read(selectedDateProvider);
    final delta = _modus == _Modus.woche ? 7 : 1;
    ref.read(selectedDateProvider.notifier).state =
        d.add(Duration(days: delta));
  }

  void _heute() {
    final now = DateTime.now();
    ref.read(selectedDateProvider.notifier).state =
        DateTime(now.year, now.month, now.day);
  }

  // ---- Aktionen ----

  Future<void> _verschiebe(BoardTask task, DateTime zielTag) async {
    final ziel = DateTime(zielTag.year, zielTag.month, zielTag.day);
    if (task.datum == ziel) return;

    final db = ref.read(databaseProvider);
    await (db.update(db.productionTasks)..where((t) => t.id.equals(task.id)))
        .write(
      ProductionTasksCompanion(
        datum: Value(ziel),
        updatedAt: Value(DateTime.now()),
      ),
    );
    ref
        .read(autoBackupTriggerProvider)
        .fireDebounced(reason: 'Auftrag verschoben');
    ref.invalidate(weekBoardProvider);
    ref.invalidate(dayBoardProvider);
    ref.invalidate(dailyTasksProvider);
  }

  Future<void> _bearbeite(BoardTask bt) async {
    final db = ref.read(databaseProvider);
    final task = await (db.select(db.productionTasks)
          ..where((t) => t.id.equals(bt.id)))
        .getSingleOrNull();
    if (task == null) return;
    final product = await (db.select(db.products)
          ..where((p) => p.id.equals(task.productId)))
        .getSingleOrNull();
    if (!mounted) return;

    final wb = WhiteboardTask(
      task: task,
      produktName: product?.artikelbezeichnung ?? bt.productName,
      artikelnummer: product?.artikelnummer ?? '',
    );
    final changed = await showTaskDetailSheet(context, ref, wb);
    if (changed) {
      ref.invalidate(weekBoardProvider);
      ref.invalidate(dayBoardProvider);
      ref.invalidate(dailyTasksProvider);
    }
  }

  Future<void> _planen(WeekBoard board) async {
    final sel = ref.read(selectedDateProvider);
    final selTag = DateTime(sel.year, sel.month, sel.day);
    final initial = board.tage.contains(selTag) ? selTag : board.tage.first;

    final geaendert = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: _ProduktPlanenSheet(tage: board.tage, initialTag: initial),
      ),
    );
    if (geaendert == true) {
      ref.invalidate(weekBoardProvider);
      ref.invalidate(dayBoardProvider);
      ref.invalidate(dailyTasksProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sel = ref.watch(selectedDateProvider);
    final montag = mondayOfWeek(sel);
    final weekAsync = ref.watch(weekBoardProvider(montag));
    final dayAsync = ref.watch(dayBoardProvider(sel));

    // „Planen"-Direkteinstieg: einmalig den Dialog öffnen, sobald die
    // Wochendaten geladen sind.
    if (widget.oeffnePlanenDirekt && !_planenGeoeffnet) {
      final board = weekAsync.valueOrNull;
      if (board != null) {
        _planenGeoeffnet = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _planen(board);
        });
      }
    }

    final istWoche = _modus == _Modus.woche;

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(
          istWoche
              ? 'Planungsboard · KW ${_isoKw(montag)}'
              : 'Tagesplan · ${_fmtTagTitel(sel)}',
        ),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.print),
            tooltip: 'Drucken',
            onSelected: (wahl) async {
              if (wahl == 'woche') {
                final b = ref.read(weekBoardProvider(montag)).valueOrNull;
                if (b != null) await BoardPrintService.druckeWoche(b);
              } else {
                final day = await ref.read(dayBoardProvider(sel).future);
                await BoardPrintService.druckeTag(day);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'woche', child: Text('Woche drucken')),
              PopupMenuItem(value: 'tag', child: Text('Tag drucken')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: istWoche ? 'Vorherige Woche' : 'Vorheriger Tag',
            onPressed: _zurueck,
          ),
          IconButton(
            icon: const Icon(Icons.today),
            tooltip: 'Heute',
            onPressed: _heute,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: istWoche ? 'Nächste Woche' : 'Nächster Tag',
            onPressed: _vor,
          ),
        ],
      ),
      floatingActionButton: weekAsync.maybeWhen(
        data: (board) => FloatingActionButton.extended(
          onPressed: () => _planen(board),
          icon: const Icon(Icons.add),
          label: const Text('Produkt planen'),
        ),
        orElse: () => null,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<_Modus>(
                segments: const [
                  ButtonSegment(
                    value: _Modus.woche,
                    label: Text('Woche'),
                    icon: Icon(Icons.calendar_view_week),
                  ),
                  ButtonSegment(
                    value: _Modus.tag,
                    label: Text('Tag'),
                    icon: Icon(Icons.calendar_view_day),
                  ),
                ],
                selected: {_modus},
                onSelectionChanged: (s) =>
                    setState(() => _modus = s.first),
              ),
            ),
          ),
          Expanded(
            child: istWoche
                ? weekAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Fehler: $e')),
                    data: (board) => _BoardGrid(
                      board: board,
                      onTapTask: _bearbeite,
                      onMoveTask: _verschiebe,
                    ),
                  )
                : dayAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Fehler: $e')),
                    data: (day) => _DayList(day: day, onTapTask: _bearbeite),
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Wochen-Grid
// ---------------------------------------------------------------------------

class _BoardGrid extends StatelessWidget {
  const _BoardGrid({
    required this.board,
    required this.onTapTask,
    required this.onMoveTask,
  });

  final WeekBoard board;
  final void Function(BoardTask) onTapTask;
  final void Function(BoardTask, DateTime) onMoveTask;

  @override
  Widget build(BuildContext context) {
    final hatTasks = board.cells.values.any((c) => c.tasks.isNotEmpty);

    return Column(
      children: [
        _HeaderRow(tage: board.tage),
        if (!hatTasks) const _LeerHinweis(),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final abt in board.abteilungen)
                  _AbteilungsZeile(
                    board: board,
                    abteilung: abt,
                    onTapTask: onTapTask,
                    onMoveTask: onMoveTask,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.tage});

  final List<DateTime> tage;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final heute = DateTime(now.year, now.month, now.day);

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          const SizedBox(width: _kLabelWidth),
          for (var i = 0; i < tage.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _kDayLabels[i],
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: tage[i] == heute ? colors.primary : null,
                      ),
                    ),
                    Text(
                      '${tage[i].day}.${tage[i].month}.',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AbteilungsZeile extends StatelessWidget {
  const _AbteilungsZeile({
    required this.board,
    required this.abteilung,
    required this.onTapTask,
    required this.onMoveTask,
  });

  final WeekBoard board;
  final Abteilung abteilung;
  final void Function(BoardTask) onTapTask;
  final void Function(BoardTask, DateTime) onMoveTask;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AbteilungsLabel(abteilung: abteilung),
          for (final tag in board.tage)
            Expanded(
              child: _TagesZelle(
                cell: board.cellFor(abteilung, tag),
                onTapTask: onTapTask,
                onMoveHere: (bt) => onMoveTask(bt, tag),
              ),
            ),
        ],
      ),
    );
  }
}

class _AbteilungsLabel extends StatelessWidget {
  const _AbteilungsLabel({required this.abteilung});

  final Abteilung abteilung;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _kLabelWidth,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: abteilung.farbe.withValues(alpha: 0.06),
        border: Border(
          right: BorderSide(color: Colors.grey.shade300),
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: abteilung.farbe,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              abteilung.anzeigeName,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}

class _TagesZelle extends StatelessWidget {
  const _TagesZelle({
    required this.cell,
    required this.onTapTask,
    required this.onMoveHere,
  });

  final BoardCell cell;
  final void Function(BoardTask) onTapTask;
  final void Function(BoardTask) onMoveHere;

  @override
  Widget build(BuildContext context) {
    final farbe = _ampelFarbe(cell.status);

    return DragTarget<BoardTask>(
      onWillAcceptWithDetails: (details) {
        final t = details.data;
        return t.abteilung == cell.abteilung && t.datum != cell.tag;
      },
      onAcceptWithDetails: (details) => onMoveHere(details.data),
      builder: (context, candidate, rejected) {
        final highlight = candidate.isNotEmpty;
        return Container(
          constraints: const BoxConstraints(minHeight: 96),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: highlight
                ? cell.abteilung.farbe.withValues(alpha: 0.10)
                : null,
            border: Border(
              right: BorderSide(color: Colors.grey.shade200),
              bottom: BorderSide(color: Colors.grey.shade200),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    '${_fmtStunden(cell.belegtMinuten)} / '
                    '${_fmtStunden(cell.kapazitaetMinuten)} h',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: farbe,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _ampelWort(cell.status),
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: cell.auslastung.clamp(0.0, 1.0).toDouble(),
                  minHeight: 5,
                  backgroundColor: Colors.grey.shade200,
                  color: farbe,
                ),
              ),
              const SizedBox(height: 6),
              for (final task in cell.tasks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _AuftragsKarte(
                    task: task,
                    onTap: () => onTapTask(task),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _AuftragsKarte extends StatelessWidget {
  const _AuftragsKarte({required this.task, required this.onTap});

  final BoardTask task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Draggable<BoardTask>(
      data: task,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 160,
          child: _KartenInhalt(task: task, dragging: true),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _KartenInhalt(task: task),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: _KartenInhalt(task: task),
      ),
    );
  }
}

class _KartenInhalt extends StatelessWidget {
  const _KartenInhalt({required this.task, this.dragging = false});

  final BoardTask task;
  final bool dragging;

  @override
  Widget build(BuildContext context) {
    final abtColor = task.abteilung.farbe;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(7),
        border: Border(
          left: BorderSide(color: abtColor, width: 3),
          top: BorderSide(color: Colors.grey.shade300),
          right: BorderSide(color: Colors.grey.shade300),
          bottom: BorderSide(color: Colors.grey.shade300),
        ),
        boxShadow: dragging
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            task.productName,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 1),
          Text(
            '${task.mengeKg.toStringAsFixed(0)} kg · '
            '${_fmtStunden(task.dauerMinuten)} h',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _LeerHinweis extends StatelessWidget {
  const _LeerHinweis();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: colors.surfaceContainerHighest,
      child: Text(
        'Noch keine Aufträge in dieser Woche. Tippe unten auf '
        '„Produkt planen", um aus einem Artikel die Abteilungs-Tasks '
        'anzulegen.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tagesansicht (abgespeckt)
// ---------------------------------------------------------------------------

class _DayList extends StatelessWidget {
  const _DayList({required this.day, required this.onTapTask});

  final DayBoard day;
  final void Function(BoardTask) onTapTask;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final lane in day.lanes)
          _DayDeptCard(lane: lane, onTapTask: onTapTask),
      ],
    );
  }
}

class _DayDeptCard extends StatelessWidget {
  const _DayDeptCard({required this.lane, required this.onTapTask});

  final DayLane lane;
  final void Function(BoardTask) onTapTask;

  @override
  Widget build(BuildContext context) {
    final farbe = _ampelFarbe(lane.status);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: lane.abteilung.farbe,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    lane.abteilung.anzeigeName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${_fmtStunden(lane.belegtMinuten)} / '
                  '${_fmtStunden(lane.kapazitaetMinuten)} h',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: farbe,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: lane.auslastung.clamp(0.0, 1.0).toDouble(),
                minHeight: 6,
                backgroundColor: Colors.grey.shade200,
                color: farbe,
              ),
            ),
            const SizedBox(height: 8),
            if (lane.tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '— keine Aufträge —',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey.shade500,
                  ),
                ),
              )
            else
              for (final task in lane.tasks)
                _DayTaskRow(task: task, onTap: () => onTapTask(task)),
          ],
        ),
      ),
    );
  }
}

class _DayTaskRow extends StatelessWidget {
  const _DayTaskRow({required this.task, required this.onTap});

  final BoardTask task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 30,
              decoration: BoxDecoration(
                color: task.abteilung.farbe,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.productName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${task.mengeKg.toStringAsFixed(0)} kg · '
                    '${_fmtStunden(task.dauerMinuten)} h',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (task.startZeit != null)
              Text(
                task.startZeit!,
                style: TextStyle(
                  fontSize: 12,
                  color: colors.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Produkt-planen-Sheet (zwei Stufen: Auswahl → Tageszuweisung)
// ---------------------------------------------------------------------------

enum _PlanStufe { auswahl, tage }

class _ProduktPlanenSheet extends ConsumerStatefulWidget {
  const _ProduktPlanenSheet({required this.tage, required this.initialTag});

  final List<DateTime> tage;
  final DateTime initialTag;

  @override
  ConsumerState<_ProduktPlanenSheet> createState() =>
      _ProduktPlanenSheetState();
}

class _ProduktPlanenSheetState extends ConsumerState<_ProduktPlanenSheet> {
  final _suche = TextEditingController();
  final _menge = TextEditingController(text: '100');
  List<Product> _produkte = [];
  Product? _gewaehlt;
  late DateTime _startTag;

  _PlanStufe _stufe = _PlanStufe.auswahl;
  List<GeplanterSchritt> _plan = [];
  double _rohware = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _startTag = widget.initialTag;
    _ladeProdukte();
  }

  Future<void> _ladeProdukte() async {
    final db = ref.read(databaseProvider);
    final list = await (db.select(db.products)
          ..where((p) => p.deletedAt.isNull())
          ..orderBy([(p) => OrderingTerm.asc(p.artikelbezeichnung)]))
        .get();
    if (mounted) setState(() => _produkte = list);
  }

  @override
  void dispose() {
    _suche.dispose();
    _menge.dispose();
    super.dispose();
  }

  // ── Stufe 1 → 2: Plan berechnen ───────────────────────────────────────
  Future<void> _weiter() async {
    final produkt = _gewaehlt;
    if (produkt == null) return;
    final menge = double.tryParse(_menge.text.replaceAll(',', '.'));
    if (menge == null || menge <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte eine gültige Menge (kg) eingeben.'),
        ),
      );
      return;
    }

    setState(() => _busy = true);
    final db = ref.read(databaseProvider);
    final plan = await berechneSchrittPlan(
      db: db,
      productId: produkt.id,
      mengeKg: menge,
      startTag: _startTag,
    );
    if (!mounted) return;
    if (plan.schritte.isEmpty) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Dieses Produkt hat keine Schritte. Lege zuerst Schritte im '
            'Artikel an.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _plan = plan.schritte;
      _rohware = plan.rohwareKg;
      _stufe = _PlanStufe.tage;
      _busy = false;
    });
  }

  // ── Stufe 2: Tasks anlegen ────────────────────────────────────────────
  Future<void> _anlegen() async {
    final produkt = _gewaehlt;
    if (produkt == null) return;

    setState(() => _busy = true);
    final db = ref.read(databaseProvider);
    await erstelleTasksAusPlan(
      db: db,
      productId: produkt.id,
      schritte: _plan,
    );
    ref
        .read(autoBackupTriggerProvider)
        .fireDebounced(reason: 'Produkt geplant');

    if (!mounted) return;
    final menge = double.tryParse(_menge.text.replaceAll(',', '.')) ?? 0;
    if (_rohware > menge) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Rohwaren-Bedarf: ${_rohware.toStringAsFixed(1)} kg '
            'für ${menge.toStringAsFixed(1)} kg Fertigware',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
    Navigator.of(context).pop(true);
  }

  void _schiebeTag(GeplanterSchritt s, int deltaTage) {
    setState(() => s.tag = s.tag.add(Duration(days: deltaTage)));
  }

  Future<void> _waehleTag(GeplanterSchritt s) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: s.tag,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() => s.tag = DateTime(picked.year, picked.month, picked.day));
    }
  }

  String _fmtTag(DateTime d) =>
      '${_kWkShort[d.weekday - 1]} ${d.day}.${d.month}.';

  Widget _griff() => Center(
        child: Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: _stufe == _PlanStufe.auswahl
              ? _buildAuswahl(scrollController)
              : _buildTage(scrollController),
        );
      },
    );
  }

  // ── Stufe 1: Produkt + Starttag + Menge ───────────────────────────────
  Widget _buildAuswahl(ScrollController sc) {
    final colors = Theme.of(context).colorScheme;
    final q = _suche.text.toLowerCase();
    final gefiltert = q.isEmpty
        ? _produkte
        : _produkte
            .where(
              (p) =>
                  p.artikelbezeichnung.toLowerCase().contains(q) ||
                  p.artikelnummer.toLowerCase().contains(q),
            )
            .toList();

    return ListView(
      controller: sc,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        _griff(),
        const Text(
          'Produkt planen',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Wähle Produkt, Starttag und Menge — danach weist du jeder '
          'Abteilung ihren Tag zu.',
          style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Text(
          'Starttag',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (var i = 0; i < widget.tage.length; i++)
              ChoiceChip(
                label: Text(
                  '${_kDayLabels[i]} '
                  '${widget.tage[i].day}.${widget.tage[i].month}.',
                ),
                selected: _startTag == widget.tage[i],
                onSelected: (_) => setState(() => _startTag = widget.tage[i]),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (_gewaehlt == null) ...[
          TextField(
            controller: _suche,
            decoration: const InputDecoration(
              labelText: 'Produkt suchen',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: gefiltert.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Keine Produkte. Importiere zuerst eine Excel-Vorlage.',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: gefiltert.length,
                    itemBuilder: (context, index) {
                      final p = gefiltert[index];
                      return ListTile(
                        dense: true,
                        title: Text(p.artikelbezeichnung),
                        subtitle: Text(p.artikelnummer),
                        onTap: () => setState(() => _gewaehlt = p),
                      );
                    },
                  ),
          ),
        ],
        if (_gewaehlt != null) ...[
          Card(
            child: ListTile(
              leading: const Icon(Icons.inventory_2),
              title: Text(_gewaehlt!.artikelbezeichnung),
              subtitle: Text(_gewaehlt!.artikelnummer),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _gewaehlt = null),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _menge,
            decoration: const InputDecoration(
              labelText: 'Menge Fertigware (kg)',
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _busy ? null : _weiter,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.arrow_forward),
              label: Text(_busy ? 'Berechne …' : 'Weiter: Tage zuweisen'),
            ),
          ),
        ],
      ],
    );
  }

  // ── Stufe 2: Tag je Schritt zuweisen ──────────────────────────────────
  Widget _buildTage(ScrollController sc) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      controller: sc,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        _griff(),
        Text(
          _gewaehlt?.artikelbezeichnung ?? 'Tage zuweisen',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Jede Abteilung kann auf einen eigenen Tag. Standard: alle auf dem '
          'Starttag — schieb einzelne Schritte nach Bedarf.',
          style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
        ),
        if (_rohware > 0) ...[
          const SizedBox(height: 8),
          Text(
            'Rohwaren-Bedarf: ${_rohware.toStringAsFixed(1)} kg',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 12),
        for (final s in _plan)
          _SchrittTagKarte(
            schritt: s,
            tagLabel: _fmtTag(s.tag),
            dauerLabel: _fmtStunden(s.dauerMinuten),
            onMinus: () => _schiebeTag(s, -1),
            onPlus: () => _schiebeTag(s, 1),
            onPick: () => _waehleTag(s),
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => setState(() => _stufe = _PlanStufe.auswahl),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Zurück'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _anlegen,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(_busy ? 'Wird angelegt …' : 'Tasks anlegen'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Schritt-Karte in der Tageszuweisung
// ---------------------------------------------------------------------------

class _SchrittTagKarte extends StatelessWidget {
  const _SchrittTagKarte({
    required this.schritt,
    required this.tagLabel,
    required this.dauerLabel,
    required this.onMinus,
    required this.onPlus,
    required this.onPick,
  });

  final GeplanterSchritt schritt;
  final String tagLabel;
  final String dauerLabel;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final abt = schritt.abteilung;
    final farbe = abt?.farbe ?? Colors.grey;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: farbe,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        abt?.anzeigeName ?? schritt.abteilungDbValue,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      if (schritt.prozessschritt != null &&
                          schritt.prozessschritt!.isNotEmpty)
                        Text(
                          schritt.prozessschritt!,
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  '$dauerLabel h · ${schritt.mitarbeiter} P',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: farbe,
                  ),
                ),
              ],
            ),
            if (schritt.ausHistorie || schritt.platzhalter) ...[
              const SizedBox(height: 4),
              Text(
                schritt.ausHistorie
                    ? 'Dauer aus Historie'
                    : 'Zeit ist Platzhalter — im Artikel pflegen',
                style: TextStyle(
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                  color: schritt.ausHistorie
                      ? const Color(0xFF2E7D32)
                      : Colors.orange.shade700,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  onPressed: onMinus,
                  icon: const Icon(Icons.chevron_left),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Einen Tag früher',
                ),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPick,
                    icon: const Icon(Icons.event, size: 16),
                    label: Text(tagLabel),
                  ),
                ),
                IconButton(
                  onPressed: onPlus,
                  icon: const Icon(Icons.chevron_right),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Einen Tag später',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}