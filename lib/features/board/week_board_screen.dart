import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';
import '../whiteboard/task_detail_sheet.dart';
import '../whiteboard/whiteboard_provider.dart';
import 'board_providers.dart';

const double _kLabelWidth = 116;
const _kDayLabels = ['Mo', 'Di', 'Mi', 'Do', 'Fr'];

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

/// Das Wochenboard: Abteilungen als Zeilen, Mo–Fr als Spalten, Ampelbalken
/// pro Tag. Karten lassen sich innerhalb ihrer Abteilungs-Zeile auf einen
/// anderen Tag ziehen (ändert das Datum des Auftrags).
class WeekBoardScreen extends ConsumerWidget {
  const WeekBoardScreen({super.key});

  void _vorWoche(WidgetRef ref) {
    final d = ref.read(selectedDateProvider);
    ref.read(selectedDateProvider.notifier).state =
        d.subtract(const Duration(days: 7));
  }

  void _naechsteWoche(WidgetRef ref) {
    final d = ref.read(selectedDateProvider);
    ref.read(selectedDateProvider.notifier).state =
        d.add(const Duration(days: 7));
  }

  void _heute(WidgetRef ref) {
    final now = DateTime.now();
    ref.read(selectedDateProvider.notifier).state =
        DateTime(now.year, now.month, now.day);
  }

  /// Verschiebt einen Auftrag auf einen anderen Tag (gleiche Abteilung).
  Future<void> _verschiebe(
    WidgetRef ref,
    BoardTask task,
    DateTime zielTag,
  ) async {
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
    ref.invalidate(dailyTasksProvider);
  }

  /// Öffnet den Bearbeiten-Sheet (wiederverwendet aus dem Whiteboard).
  Future<void> _bearbeite(
    BuildContext context,
    WidgetRef ref,
    BoardTask bt,
  ) async {
    final db = ref.read(databaseProvider);
    final task = await (db.select(db.productionTasks)
          ..where((t) => t.id.equals(bt.id)))
        .getSingleOrNull();
    if (task == null) return;
    final product = await (db.select(db.products)
          ..where((p) => p.id.equals(task.productId)))
        .getSingleOrNull();
    if (!context.mounted) return;

    final wb = WhiteboardTask(
      task: task,
      produktName: product?.artikelbezeichnung ?? bt.productName,
      artikelnummer: product?.artikelnummer ?? '',
    );
    final changed = await showTaskDetailSheet(context, ref, wb);
    if (changed) {
      ref.invalidate(weekBoardProvider);
      // dailyTasksProvider wird vom Sheet selbst invalidiert.
    }
  }

  /// Öffnet den „Produkt planen"-Sheet.
  Future<void> _planen(
    BuildContext context,
    WidgetRef ref,
    WeekBoard board,
  ) async {
    final sel = ref.read(selectedDateProvider);
    final selTag = DateTime(sel.year, sel.month, sel.day);
    final initial =
        board.tage.contains(selTag) ? selTag : board.tage.first;

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
      ref.invalidate(dailyTasksProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sel = ref.watch(selectedDateProvider);
    final montag = mondayOfWeek(sel);
    final boardAsync = ref.watch(weekBoardProvider(montag));
    final kw = _isoKw(montag);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text('Planungsboard · KW $kw'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Vorherige Woche',
            onPressed: () => _vorWoche(ref),
          ),
          IconButton(
            icon: const Icon(Icons.today),
            tooltip: 'Diese Woche',
            onPressed: () => _heute(ref),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Nächste Woche',
            onPressed: () => _naechsteWoche(ref),
          ),
        ],
      ),
      floatingActionButton: boardAsync.maybeWhen(
        data: (board) => FloatingActionButton.extended(
          onPressed: () => _planen(context, ref, board),
          icon: const Icon(Icons.add),
          label: const Text('Produkt planen'),
        ),
        orElse: () => null,
      ),
      body: boardAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (board) => _BoardGrid(
          board: board,
          onTapTask: (bt) => _bearbeite(context, ref, bt),
          onMoveTask: (bt, tag) => _verschiebe(ref, bt, tag),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Grid
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
// Produkt-planen-Sheet
// ---------------------------------------------------------------------------

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
  late DateTime _tag;
  bool _erstellt = false;

  @override
  void initState() {
    super.initState();
    _tag = widget.initialTag;
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

  Future<void> _erstelle() async {
    final produkt = _gewaehlt;
    if (produkt == null) return;
    final menge = double.tryParse(_menge.text.replaceAll(',', '.'));
    if (menge == null || menge <= 0) return;

    setState(() => _erstellt = true);
    final db = ref.read(databaseProvider);

    // Vorab prüfen: hat das Produkt überhaupt Schritte?
    final schritte = await (db.select(db.productSteps)
          ..where((s) => s.productId.equals(produkt.id))
          ..where((s) => s.deletedAt.isNull()))
        .get();
    if (schritte.isEmpty) {
      if (mounted) {
        setState(() => _erstellt = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Dieses Produkt hat keine Schritte. Lege zuerst Schritte '
              'im Artikel an.',
            ),
          ),
        );
      }
      return;
    }

    final rohware = await createTasksFromProduct(
      db: db,
      productId: produkt.id,
      mengeKg: menge,
      datum: _tag,
    );
    ref
        .read(autoBackupTriggerProvider)
        .fireDebounced(reason: 'Produkt geplant');

    if (!mounted) return;
    if (rohware > menge) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Rohwaren-Bedarf: ${rohware.toStringAsFixed(1)} kg '
            'für ${menge.toStringAsFixed(1)} kg Fertigware',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
    Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _suche.dispose();
    _menge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                'Wähle ein Produkt und einen Tag — alle Abteilungsschritte '
                'werden als Tasks angelegt.',
                style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 16),

              Text(
                'Tag',
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
                      selected: _tag == widget.tage[i],
                      onSelected: (_) =>
                          setState(() => _tag = widget.tage[i]),
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
                            'Keine Produkte. Importiere zuerst eine '
                            'Excel-Vorlage.',
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
                    labelText: 'Menge (kg)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _erstellt ? null : _erstelle,
                    icon: _erstellt
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text(_erstellt ? 'Wird angelegt …' : 'Tasks anlegen'),
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