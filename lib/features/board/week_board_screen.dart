import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';
import '../bedarf/bedarf_screen.dart';
import '../whiteboard/task_detail_sheet.dart';
import '../whiteboard/whiteboard_provider.dart';
import 'board_print_service.dart';
import '../../core/utils/sheet_utils.dart';
import 'board_providers.dart';

const double _kLabelWidth = 148;
const _kDayLabels = ['Mo', 'Di', 'Mi', 'Do', 'Fr'];
const _kWkShort = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

/// Kompakte Wochenansicht: Karten schrumpfen auf eine Zeile, sodass ein
/// ganzer Tag ohne Scrollen sichtbar bleibt (bewährtes „Density"-Muster
/// aus Planungstools). Bleibt über die Sitzung erhalten.
/// Zugeklappte Abteilungen (dbValues). Zugeklappt erscheint statt der
/// einzelnen Anlagen-Spuren EINE Summenzeile — so bleibt die Übersicht
/// auch bei vielen Anlagen erhalten.
final boardZugeklapptProvider =
    StateProvider<Set<String>>((ref) => <String>{});

/// „Passend"-Modus: skaliert das Board so weit herunter, dass ALLE Spuren
/// ohne Scrollen sichtbar sind — die Methode, die auch Gantt- und
/// Projektplanungstools für die Gesamtübersicht nutzen („fit to page").
/// Aus = Originalgröße mit Scrollbalken.
final boardPassendProvider = StateProvider<bool>((ref) => true);

final boardKompaktProvider = StateProvider<bool>((ref) => true);

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

  /// Verschiebt einen Auftrag auf einen anderen Tag UND/ODER eine andere
  /// Spur (= Anlage).
  ///
  /// Das Umbelegen ist der Kern der betrieblichen Flexibilität: Ist die
  /// Multivac voll, wandert der Auftrag auf die Tef1; die Tef2 kann bei
  /// Bedarf ebenfalls auf die Tef1 ausweichen. Weil die Ausweichanlage in
  /// einer ANDEREN Abteilung stehen kann, wird die Abteilung des Auftrags
  /// dabei mitgeführt.
  Future<void> _verschiebe(
    BoardTask task,
    DateTime zielTag, {
    BoardSpur? zielSpur,
  }) async {
    final ziel = DateTime(zielTag.year, zielTag.month, zielTag.day);
    final anlageWechselt =
        zielSpur != null && zielSpur.maschineId != task.maschineId;
    final abteilungWechselt =
        zielSpur != null && zielSpur.abteilung != task.abteilung;
    if (task.datum == ziel && !anlageWechselt && !abteilungWechselt) return;

    final db = ref.read(databaseProvider);
    await (db.update(db.productionTasks)
          ..where((t) => t.id.isIn(task.mitgliederIds)))
        .write(
      ProductionTasksCompanion(
        datum: Value(ziel),
        maschineId: anlageWechselt
            ? Value(zielSpur.maschineId)
            : const Value.absent(),
        abteilung: abteilungWechselt
            ? Value(zielSpur.abteilung.dbValue)
            : const Value.absent(),
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

    final geaendert = await showSheetOhneAnimation<bool>(
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

  /// Setzt die manuelle Reihenfolge innerhalb einer Abteilung an einem Tag
  /// neu (Hoch/Runter im Tagesplan) und speichert sie als `sortierung`.
  Future<void> _sortiere(
    List<BoardTask> laneTasks,
    int von,
    int nach,
  ) async {
    if (nach < 0 || nach >= laneTasks.length || von == nach) return;
    final neu = [...laneTasks];
    final item = neu.removeAt(von);
    neu.insert(nach, item);

    final db = ref.read(databaseProvider);
    final jetzt = DateTime.now();
    await db.transaction(() async {
      for (var i = 0; i < neu.length; i++) {
        await (db.update(db.productionTasks)
              ..where((t) => t.id.isIn(neu[i].mitgliederIds)))
            .write(
          ProductionTasksCompanion(
            sortierung: Value(i),
            updatedAt: Value(jetzt),
          ),
        );
      }
    });

    ref
        .read(autoBackupTriggerProvider)
        .fireDebounced(reason: 'Reihenfolge geändert');
    ref.invalidate(weekBoardProvider);
    ref.invalidate(dayBoardProvider);
    ref.invalidate(dailyTasksProvider);
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
            child: Row(
              children: [
                SegmentedButton<_Modus>(
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
                const Spacer(),
                // Dichte- und Skalierungs-Umschalter: nur in der Wochenansicht.
                if (_modus == _Modus.woche) ...[
                  Consumer(
                    builder: (context, ref, _) {
                      final passend = ref.watch(boardPassendProvider);
                      return IconButton(
                        icon: Icon(
                          passend ? Icons.zoom_out_map : Icons.fit_screen,
                        ),
                        tooltip: passend
                            ? 'Originalgröße (scrollen)'
                            : 'Passend skalieren (alles auf eine Seite)',
                        onPressed: () => ref
                            .read(boardPassendProvider.notifier)
                            .state = !passend,
                      );
                    },
                  ),
                  Consumer(
                    builder: (context, ref, _) {
                      final kompakt = ref.watch(boardKompaktProvider);
                      return IconButton(
                        icon: Icon(
                          kompakt
                              ? Icons.unfold_more
                              : Icons.unfold_less,
                        ),
                        tooltip: kompakt
                            ? 'Komfort-Ansicht (mehr Details)'
                            : 'Kompakt-Ansicht (ganzer Tag ohne Scrollen)',
                        onPressed: () => ref
                            .read(boardKompaktProvider.notifier)
                            .state = !kompakt,
                      );
                    },
                  ),
                  const SizedBox(width: 4),
                ],
                // Legende: erklärt die Balkenfarben ohne Vorwissen
                const _Legende(),
              ],
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
                      onMoveTask: (task, tag, spur) =>
                          _verschiebe(task, tag, zielSpur: spur),
                    ),
                  )
                : dayAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Fehler: $e')),
                    data: (day) => _DayList(
                      day: day,
                      onTapTask: _bearbeite,
                      onReorder: _sortiere,
                    ),
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

class _BoardGrid extends ConsumerWidget {
  const _BoardGrid({
    required this.board,
    required this.onTapTask,
    required this.onMoveTask,
  });

  final WeekBoard board;
  final void Function(BoardTask) onTapTask;
  final void Function(BoardTask, DateTime, BoardSpur) onMoveTask;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kompakt = ref.watch(boardKompaktProvider);
    final passend = ref.watch(boardPassendProvider);
    final hatTasks = board.cells.values.any((c) => c.tasks.isNotEmpty);

    final zugeklappt = ref.watch(boardZugeklapptProvider);

    void umschalten(Abteilung abt) {
      final neu = {...zugeklappt};
      if (!neu.remove(abt.dbValue)) neu.add(abt.dbValue);
      ref.read(boardZugeklapptProvider.notifier).state = neu;
    }

    // Spuren nach Abteilung gruppieren (sie liegen bereits sortiert vor).
    final gruppen = <List<BoardSpur>>[];
    for (final spur in board.spuren) {
      if (gruppen.isEmpty ||
          gruppen.last.first.abteilung != spur.abteilung) {
        gruppen.add([spur]);
      } else {
        gruppen.last.add(spur);
      }
    }

    final reihen = <Widget>[];
    for (final gruppe in gruppen) {
      final abt = gruppe.first.abteilung;
      final zu = zugeklappt.contains(abt.dbValue);

      if (zu) {
        // Zugeklappt: EINE Summenzeile für die ganze Abteilung.
        reihen.add(
          _ZugeklappteZeile(
            board: board,
            abteilung: abt,
            spuren: gruppe,
            kompakt: kompakt,
            onAufklappen: () => umschalten(abt),
          ),
        );
        continue;
      }

      for (var i = 0; i < gruppe.length; i++) {
        reihen.add(
          _SpurZeile(
            board: board,
            spur: gruppe[i],
            // Abteilungs-Kopf nur bei der ERSTEN Spur einer Abteilung —
            // die folgenden Anlagen-Spuren werden darunter eingerückt.
            ersteDerAbteilung: i == 0,
            kompakt: kompakt,
            onZuklappen: i == 0 ? () => umschalten(abt) : null,
            onTapTask: onTapTask,
            onMoveTask: onMoveTask,
          ),
        );
      }
    }

    final zeilen = Column(
      mainAxisSize: MainAxisSize.min,
      children: reihen,
    );

    if (!passend) {
      return Column(
        children: [
          _HeaderRow(tage: board.tage),
          if (!hatTasks) const _LeerHinweis(),
          Expanded(child: SingleChildScrollView(child: zeilen)),
        ],
      );
    }

    // „Fit to page": Kopfzeile UND Spuren werden GEMEINSAM skaliert —
    // sonst würden die Tagesspalten nicht mehr unter ihren Überschriften
    // liegen. scaleDown vergrößert nie: passt alles ohnehin, bleibt die
    // Ansicht in Originalgröße.
    return LayoutBuilder(
      builder: (context, c) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: c.maxWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _HeaderRow(tage: board.tage),
              if (!hatTasks) const _LeerHinweis(),
              zeilen,
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.tage});

  final List<DateTime> tage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final now = DateTime.now();
    final heute = DateTime(now.year, now.month, now.day);

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          const SizedBox(width: _kLabelWidth),
          for (var i = 0; i < tage.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: tage[i] == heute
                    ? Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: colors.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _kDayLabels[i],
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: colors.onPrimary,
                                ),
                              ),
                              Text(
                                '${tage[i].day}.${tage[i].month}.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color:
                                      colors.onPrimary.withValues(alpha: 0.85),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 3),
                          Text(
                            _kDayLabels[i],
                            style:
                                const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${tage[i].day}.${tage[i].month}.',
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 3),
                        ],
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SpurZeile extends StatelessWidget {
  const _SpurZeile({
    required this.board,
    required this.spur,
    required this.ersteDerAbteilung,
    required this.kompakt,
    required this.onTapTask,
    required this.onMoveTask,
    this.onZuklappen,
  });

  final WeekBoard board;
  final BoardSpur spur;
  final bool ersteDerAbteilung;
  final bool kompakt;

  /// Nur bei der ersten Spur einer Abteilung gesetzt: klappt die Gruppe zu.
  final VoidCallback? onZuklappen;
  final void Function(BoardTask) onTapTask;
  final void Function(BoardTask, DateTime, BoardSpur) onMoveTask;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SpurLabel(
            spur: spur,
            ersteDerAbteilung: ersteDerAbteilung,
            onZuklappen: onZuklappen,
          ),
          for (final tag in board.tage)
            Expanded(
              child: _TagesZelle(
                cell: board.cellFor(spur, tag),
                kompakt: kompakt,
                onTapTask: onTapTask,
                onMoveHere: (bt) => onMoveTask(bt, tag, spur),
              ),
            ),
        ],
      ),
    );
  }
}

class _SpurLabel extends StatelessWidget {
  const _SpurLabel({
    required this.spur,
    required this.ersteDerAbteilung,
    this.onZuklappen,
  });

  final BoardSpur spur;
  final bool ersteDerAbteilung;
  final VoidCallback? onZuklappen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final farbe = spur.abteilung.farbe;

    return Container(
      width: _kLabelWidth,
      decoration: BoxDecoration(
        color: farbe.withValues(alpha: spur.istAnlage ? 0.04 : 0.09),
        border: Border(
          right: BorderSide(color: theme.dividerColor),
          // Kräftige Linie am Beginn einer neuen Abteilung — trennt die
          // Anlagen-Gruppen optisch klar voneinander.
          top: ersteDerAbteilung
              ? BorderSide(color: farbe.withValues(alpha: 0.55), width: 2)
              : BorderSide.none,
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Row(
        children: [
          Container(width: 4, color: farbe),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                spur.istAnlage ? 14 : 10,
                8,
                8,
                8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Abteilungsname nur bei der ersten Spur der Abteilung —
                  // zugleich der Griff zum Zuklappen der ganzen Gruppe.
                  if (ersteDerAbteilung)
                    InkWell(
                      onTap: onZuklappen,
                      child: Row(
                        children: [
                          if (onZuklappen != null) ...[
                            Icon(
                              Icons.expand_more,
                              size: 15,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.5),
                            ),
                            const SizedBox(width: 2),
                          ],
                          Flexible(
                            child: Text(
                              spur.abteilung.anzeigeName,
                              style: TextStyle(
                                fontSize: spur.istAnlage ? 10.5 : 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: spur.istAnlage ? 0.4 : 0,
                                height: 1.2,
                                color: spur.istAnlage
                                    ? theme.colorScheme.onSurface
                                        .withValues(alpha: 0.55)
                                    : null,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Sammelspur INNERHALB einer Abteilung, die Anlagen-Spuren
                  // hat: sie ist nicht die erste Zeile und keine Anlage —
                  // ohne eigenen Text bliebe die Zeile sonst unbeschriftet.
                  if (!spur.istAnlage && !ersteDerAbteilung) ...[
                    Text(
                      'Ohne Anlage',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        fontStyle: FontStyle.italic,
                        height: 1.2,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ],
                  // Anlagen-Name (eingerückt unter der Abteilung)
                  if (spur.istAnlage) ...[
                    if (ersteDerAbteilung) const SizedBox(height: 2),
                    Text(
                      spur.anzeigeName,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                    if (spur.eignungHinweis != null &&
                        spur.eignungHinweis!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        spur.eignungHinweis!,
                        style: TextStyle(
                          fontSize: 9.5,
                          height: 1.2,
                          fontStyle: FontStyle.italic,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5),
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ],
                  ],
                ],
              ),
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
    required this.kompakt,
    required this.onTapTask,
    required this.onMoveHere,
  });

  final BoardCell cell;
  final bool kompakt;
  final void Function(BoardTask) onTapTask;
  final void Function(BoardTask) onMoveHere;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final farbe = _ampelFarbe(cell.status);
    final now = DateTime.now();
    final istHeute = cell.tag == DateTime(now.year, now.month, now.day);
    final belegt = cell.tasks.isNotEmpty;

    return DragTarget<BoardTask>(
      onWillAcceptWithDetails: (details) {
        final t = details.data;
        // Normalfall: nur innerhalb derselben Abteilung verschieben.
        // Ausnahme Verpackung: dort darf ABTEILUNGSÜBERGREIFEND umbelegt
        // werden (Multivac -> Tef1 als Ausweichanlage, Tef2 -> Tef1),
        // weil genau das der betriebliche Alltag ist.
        final gleicheGruppe = t.abteilung == cell.abteilung ||
            (t.abteilung.istVerpackung && cell.abteilung.istVerpackung);
        if (!gleicheGruppe) return false;
        // Nichts tun, wenn Tag UND Spur identisch sind.
        final gleicheSpur = t.maschineId == cell.spur.maschineId &&
            t.abteilung == cell.abteilung;
        return !(gleicheSpur && t.datum == cell.tag);
      },
      onAcceptWithDetails: (details) => onMoveHere(details.data),
      builder: (context, candidate, rejected) {
        final highlight = candidate.isNotEmpty;
        return Container(
          constraints: BoxConstraints(
            minHeight: belegt ? (kompakt ? 48 : 92) : (kompakt ? 30 : 56),
          ),
          padding: EdgeInsets.all(kompakt ? 4 : 6),
          decoration: BoxDecoration(
            color: highlight
                ? cell.abteilung.farbe.withValues(alpha: 0.12)
                : istHeute
                    ? theme.colorScheme.primary.withValues(alpha: 0.04)
                    : null,
            border: Border(
              right: BorderSide(color: theme.dividerColor),
              bottom: BorderSide(color: theme.dividerColor),
            ),
          ),
          child: !belegt
              // -- LEERE ZELLE: bewusst ruhig. Keine Zahlen, kein Balken —
              //    freie Kapazität ist der Normalfall und muss nicht
              //    35-mal wiederholt werden. Nur beim Ziehen erscheint
              //    ein Hinweis.
              ? Center(
                  child: highlight
                      ? Text(
                          'Hier ablegen',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: cell.abteilung.farbe,
                          ),
                        )
                      : const SizedBox.shrink(),
                )
              // -- BELEGTE ZELLE: Auslastung kompakt + Aufträge
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AuslastungsPille(
                      belegt: cell.belegtMinuten,
                      kapazitaet: cell.kapazitaetMinuten,
                      auslastung: cell.auslastung,
                      farbe: farbe,
                      status: cell.status,
                      kompakt: kompakt,
                    ),
                    SizedBox(height: kompakt ? 3 : 6),
                    for (final task in cell.tasks)
                      Padding(
                        padding: EdgeInsets.only(bottom: kompakt ? 3 : 4),
                        child: _AuftragsKarte(
                          task: task,
                          kompakt: kompakt,
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

/// Kompakte Auslastungsanzeige — erscheint nur in belegten Zellen.
/// Stunden, Mini-Balken und (nur bei Engpass) ein Warnwort.
class _AuslastungsPille extends StatelessWidget {
  const _AuslastungsPille({
    required this.belegt,
    required this.kapazitaet,
    required this.auslastung,
    required this.farbe,
    required this.status,
    this.kompakt = false,
  });

  final double belegt;
  final double kapazitaet;
  final double auslastung;
  final Color farbe;
  final CapacityStatus status;
  final bool kompakt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // „Platz frei" ist der Normalfall und braucht kein Wort — nur
    // Engpässe werden benannt.
    final warnung = status == CapacityStatus.frei ? null : _ampelWort(status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '${_fmtStunden(belegt)} / ${_fmtStunden(kapazitaet)} h',
              style: TextStyle(
                fontSize: kompakt ? 10 : 11.5,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
            const Spacer(),
            if (warnung != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: farbe.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  warnung,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: farbe,
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: kompakt ? 2 : 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: auslastung.clamp(0.0, 1.0).toDouble(),
            minHeight: kompakt ? 3 : 4,
            backgroundColor:
                theme.colorScheme.onSurface.withValues(alpha: 0.10),
            color: farbe,
          ),
        ),
      ],
    );
  }
}

class _AuftragsKarte extends StatelessWidget {
  const _AuftragsKarte({
    required this.task,
    required this.onTap,
    this.kompakt = false,
  });

  final BoardTask task;
  final VoidCallback onTap;
  final bool kompakt;

  @override
  Widget build(BuildContext context) {
    return Draggable<BoardTask>(
      data: task,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 180,
          child: _KartenInhalt(task: task, dragging: true),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _KartenInhalt(task: task, kompakt: kompakt),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: _KartenInhalt(task: task, kompakt: kompakt),
      ),
    );
  }
}

class _KartenInhalt extends StatelessWidget {
  const _KartenInhalt({
    required this.task,
    this.dragging = false,
    this.kompakt = false,
  });

  final BoardTask task;
  final bool dragging;
  final bool kompakt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final abtColor = task.abteilung.farbe;
    final kette = _kettenFarbe(task.kettenId, theme.brightness);

    // Kompaktvariante: alles in EINER Zeile — Ketten-Kante, Kurzcode-Chip,
    // Produktname (einzeilig), rechts die Kennzahl. So passt ein ganzer
    // Tag ohne Scrollen ins Bild.
    if (kompakt) {
      return Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: theme.dividerColor),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(width: 4, color: kette),
              Container(
                color: abtColor,
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                alignment: Alignment.center,
                child: Text(
                  task.abteilung.kurzcode,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  task.productName,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(right: 7),
                child: Text(
                  '${task.mengeKg.toStringAsFixed(0)}kg·'
                  '${_fmtStunden(task.dauerMinuten)}h',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
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
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Ketten-Akzent: alle Karten EINER Produktion (die durch
            // mehrere Abteilungen läuft) tragen dieselbe Farbe an der
            // linken Kante — so ist auf einen Blick erkennbar, dass sie
            // zusammengehören.
            Container(width: 5, color: kette),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Farbkopf mit Abteilungs-Kurzcode
                  Container(
                    color: abtColor,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    child: Text(
                      task.abteilung.kurzcode,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          task.productName,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${task.mengeKg.toStringAsFixed(0)} kg · '
                          '${_fmtStunden(task.dauerMinuten)} h',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stabile Akzentfarbe je Auftragskette.
///
/// Alle Karten einer Produktion (Kutterabteilung ? Bratstraße ? Verpackung)
/// teilen sich dieselbe `kettenId` und damit dieselbe Farbe. Die Farbe wird
/// deterministisch aus der ID abgeleitet — sie bleibt über App-Neustarts
/// hinweg gleich und ist bewusst von den Abteilungsfarben unterscheidbar.
Color _kettenFarbe(String kettenId, Brightness helligkeit) {
  const palette = [
    Color(0xFF42A5F5), // Blau
    Color(0xFFAB47BC), // Violett
    Color(0xFF26A69A), // Türkis
    Color(0xFFFFA726), // Orange
    Color(0xFFEC407A), // Pink
    Color(0xFF9CCC65), // Limette
    Color(0xFF7E57C2), // Indigo
    Color(0xFF29B6F6), // Hellblau
  ];
  var hash = 0;
  for (final einheit in kettenId.codeUnits) {
    hash = (hash * 31 + einheit) & 0x7fffffff;
  }
  final farbe = palette[hash % palette.length];
  // Im hellen Modus etwas kräftiger, damit die Kante nicht verblasst.
  return helligkeit == Brightness.dark
      ? farbe
      : Color.alphaBlend(Colors.black.withValues(alpha: 0.15), farbe);
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
  const _DayList({
    required this.day,
    required this.onTapTask,
    required this.onReorder,
  });

  final DayBoard day;
  final void Function(BoardTask) onTapTask;
  final void Function(List<BoardTask>, int, int) onReorder;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final lane in day.lanes)
          _DayDeptCard(
            lane: lane,
            onTapTask: onTapTask,
            onReorder: onReorder,
          ),
      ],
    );
  }
}

class _DayDeptCard extends StatelessWidget {
  const _DayDeptCard({
    required this.lane,
    required this.onTapTask,
    required this.onReorder,
  });

  final DayLane lane;
  final void Function(BoardTask) onTapTask;
  final void Function(List<BoardTask>, int, int) onReorder;

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
                    lane.spur.anzeigeName,
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
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
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
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.45),
                  ),
                ),
              )
            else
              for (var i = 0; i < lane.tasks.length; i++)
                _DayTaskRow(
                  task: lane.tasks[i],
                  onTap: () => onTapTask(lane.tasks[i]),
                  onUp: i > 0 ? () => onReorder(lane.tasks, i, i - 1) : null,
                  onDown: i < lane.tasks.length - 1
                      ? () => onReorder(lane.tasks, i, i + 1)
                      : null,
                ),
          ],
        ),
      ),
    );
  }
}

class _DayTaskRow extends StatelessWidget {
  const _DayTaskRow({
    required this.task,
    required this.onTap,
    this.onUp,
    this.onDown,
  });

  final BoardTask task;
  final VoidCallback onTap;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

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
              width: 36,
              padding: const EdgeInsets.symmetric(vertical: 5),
              decoration: BoxDecoration(
                color: task.abteilung.farbe,
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Text(
                task.abteilung.kurzcode,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
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
            if (onUp != null || onDown != null) ...[
              const SizedBox(width: 4),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: onUp,
                    borderRadius: BorderRadius.circular(4),
                    child: Icon(
                      Icons.keyboard_arrow_up,
                      size: 22,
                      color: onUp == null
                          ? colors.onSurface.withValues(alpha: 0.25)
                          : colors.onSurfaceVariant,
                    ),
                  ),
                  InkWell(
                    onTap: onDown,
                    borderRadius: BorderRadius.circular(4),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      size: 22,
                      color: onDown == null
                          ? colors.onSurface.withValues(alpha: 0.25)
                          : colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Produkt-planen-Sheet (zwei Stufen: Auswahl ? Tageszuweisung)
// ---------------------------------------------------------------------------

enum _PlanStufe { auswahl, tage }

/// Einheit der Mengeneingabe im Planen-Dialog.
/// Womit der Nutzer die Planung anstößt: mit der Rohwarenmenge, der
/// gewünschten Fertigmenge oder mit der verfügbaren Produktionszeit.
enum _MengenEinheit { rohware, fertigware, stunden }

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

  /// Manuell eingegebener Verlust in % (nur relevant, wenn Einheit =
  /// Fertigware und keine Historie vorliegt).
  final _verlustProzent = TextEditingController();

  List<Product> _produkte = [];
  Product? _gewaehlt;

  /// Einheit der eingegebenen Menge: rohware (Standard) oder fertigware.
  /// Bei fertigware rechnet die App über den Verlust auf Rohware hoch, mit
  /// der dann geplant wird — im Board steht immer Rohgewicht.
  _MengenEinheit _einheit = _MengenEinheit.rohware;

  /// Durchschnittlicher Verlust des gewählten Artikels aus der Historie
  /// (0…1), oder null wenn keine Daten. Wird beim Artikelwechsel geladen.
  double? _histVerlust;

  /// Bedarf, aus dem geplant wird (optional). Ist einer gewählt, wird die
  /// geplante Menge gegen ihn gerechnet — die Bedarfsliste zeigt dann
  /// automatisch, was noch offen ist.
  BedarfInfo? _bedarf;

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

  /// Lädt den historischen Durchschnittsverlust für den gewählten Artikel.
  Future<void> _ladeVerlust(String productId) async {
    final db = ref.read(databaseProvider);
    final v = await durchschnittsVerlust(db, productId);
    if (mounted) setState(() => _histVerlust = v);
  }

  // ── Zeitmodell: Minuten = Fixanteil + Faktor × Menge ─────────────────
  // Die Schrittdauer ist „Fixzeit + Zeit × (Menge / Referenzmenge)", also
  // linear in der Menge — die Rechnung lässt sich damit umkehren.
  //
  // WICHTIG: Es wird JE ABTEILUNG gerechnet, nicht über die Summe. Im
  // Wochenplan bekommt jede Abteilung ihren eigenen Tag mit 9 Stunden;
  // „2 Stunden produzieren" heißt also 2 Stunden AN DER LINIE, nicht
  // 2 Stunden über alle Abteilungen zusammengezählt. Maßgeblich ist die
  // engste Abteilung — sie begrenzt, was in der Zeit zu schaffen ist.
  List<({String abteilung, double fix, double proKg})> _dauerModelle = [];

  Future<void> _ladeZeitmodell(String productId) async {
    final db = ref.read(databaseProvider);
    try {
      final klein = await berechneSchrittPlan(
        db: db,
        productId: productId,
        mengeKg: 100,
        startTag: _startTag,
      );
      final gross = await berechneSchrittPlan(
        db: db,
        productId: productId,
        mengeKg: 1000,
        startTag: _startTag,
      );
      final modelle = <({String abteilung, double fix, double proKg})>[];
      final anzahl = klein.schritte.length < gross.schritte.length
          ? klein.schritte.length
          : gross.schritte.length;
      for (var i = 0; i < anzahl; i++) {
        final t1 = klein.schritte[i].dauerMinuten;
        final t2 = gross.schritte[i].dauerMinuten;
        final steigung = (t2 - t1) / 900.0;
        if (steigung <= 0) continue; // reine Fixzeit — begrenzt nicht
        modelle.add((
          abteilung: klein.schritte[i].abteilungDbValue,
          fix: t1 - steigung * 100,
          proKg: steigung,
        ),);
      }
      if (!mounted) return;
      setState(() => _dauerModelle = modelle);
    } catch (_) {
      if (mounted) setState(() => _dauerModelle = []);
    }
  }

  /// Aus der eingegebenen Stundenzahl die planbare ROHWARENMENGE.
  ///
  /// Es gewinnt die kleinste Menge über alle Abteilungen: Sobald EINE
  /// Abteilung die Zeit überschreiten würde, ist Schluss.
  double? get _mengeAusStunden {
    if (_einheit != _MengenEinheit.stunden) return null;
    final stunden = double.tryParse(_menge.text.replaceAll(',', '.'));
    if (stunden == null || stunden <= 0 || _dauerModelle.isEmpty) return null;
    double? kleinste;
    for (final m in _dauerModelle) {
      final menge = (stunden * 60 - m.fix) / m.proKg;
      if (menge <= 0) return null; // Zeit reicht nicht mal für die Fixzeit
      if (kleinste == null || menge < kleinste) kleinste = menge;
    }
    return kleinste;
  }

  /// Name der Abteilung, die die Menge begrenzt (für den Hinweistext).
  String? get _engpassAbteilung {
    final stunden = double.tryParse(_menge.text.replaceAll(',', '.'));
    if (stunden == null || stunden <= 0 || _dauerModelle.isEmpty) return null;
    double? kleinste;
    String? engpass;
    for (final m in _dauerModelle) {
      final menge = (stunden * 60 - m.fix) / m.proKg;
      if (kleinste == null || menge < kleinste) {
        kleinste = menge;
        engpass = m.abteilung;
      }
    }
    if (engpass == null) return null;
    try {
      return Abteilung.fromDbValue(engpass).anzeigeName;
    } catch (_) {
      return engpass;
    }
  }

  /// Fertigmenge, die in der eingegebenen Zeit herauskommt.
  double? get _fertigAusStunden {
    final roh = _mengeAusStunden;
    final v = _effektiverVerlust;
    if (roh == null) return null;
    return v == null ? null : roh * (1 - v);
  }

  /// Die Menge, mit der tatsächlich geplant wird — in ROHWARE.
  ///
  /// Bei Fertigware-Eingabe wird die zuvor nur informativ angezeigte
  /// Rohwarenmenge jetzt auch wirklich verplant: Die Anlagen verarbeiten
  /// die Rohware, nicht das Fertiggewicht.
  double? get _planMenge {
    switch (_einheit) {
      case _MengenEinheit.rohware:
        final v = double.tryParse(_menge.text.replaceAll(',', '.'));
        return (v != null && v > 0) ? v : null;
      case _MengenEinheit.fertigware:
        final eingabe = double.tryParse(_menge.text.replaceAll(',', '.'));
        if (eingabe == null || eingabe <= 0) return null;
        // Ohne bekannten Verlust bleibt es bei der Eingabe.
        return _rohwareVorschau ?? eingabe;
      case _MengenEinheit.stunden:
        return _mengeAusStunden;
    }
  }

  /// Effektiver Verlust (0…1): Historie bevorzugt, sonst der manuell
  /// eingegebene Prozentwert. null, wenn beides fehlt.
  double? get _effektiverVerlust {
    if (_histVerlust != null) return _histVerlust;
    final p = double.tryParse(_verlustProzent.text.replaceAll(',', '.'));
    if (p != null && p > 0 && p < 100) return p / 100;
    return null;
  }

  /// Informative Rohwaren-Vorschau bei Fertigware-Eingabe:
  /// Rohware ≈ Fertig / (1 − Verlust). null, wenn kein Verlust bekannt ist.
  /// Beeinflusst die eigentliche Planung NICHT — die läuft über die
  /// Ausbeute-Faktoren.
  double? get _rohwareVorschau {
    if (_einheit != _MengenEinheit.fertigware) return null;
    final eingabe = double.tryParse(_menge.text.replaceAll(',', '.'));
    final v = _effektiverVerlust;
    if (eingabe == null || eingabe <= 0 || v == null || v >= 1) return null;
    return eingabe / (1 - v);
  }

  @override
  void dispose() {
    _suche.dispose();
    _menge.dispose();
    _verlustProzent.dispose();
    super.dispose();
  }

  // -- Stufe 1 ? 2: Plan berechnen ---------------------------------------
  Future<void> _weiter() async {
    final produkt = _gewaehlt;
    if (produkt == null) return;
    final menge = _planMenge;
    if (menge == null || menge <= 0) {
      final hinweis = _einheit == _MengenEinheit.stunden
          ? (_dauerModelle.isEmpty
              ? 'Für dieses Produkt lässt sich aus der Zeit keine Menge '
                  'ableiten — es fehlen Leistungsdaten.'
              : 'Bitte eine gültige Stundenzahl eingeben.')
          : 'Bitte eine gültige Menge (kg) eingeben.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(hinweis)),
      );
      return;
    }

    // [menge] ist immer die ROHWARENMENGE, mit der die Anlagen laufen.
    // Bei Fertigware-Eingabe wurde sie über den Verlust hochgerechnet,
    // bei Stunden-Eingabe über das Zeitmodell — siehe [_planMenge].
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

  // -- Stufe 2: Tasks anlegen --------------------------------------------
  Future<void> _anlegen() async {
    final produkt = _gewaehlt;
    if (produkt == null) return;

    setState(() => _busy = true);
    final db = ref.read(databaseProvider);
    final eingabe =
        double.tryParse(_menge.text.replaceAll(',', '.')) ?? 0;
    // Der Bedarf ist in Fertigware definiert. Bei Fertigware-Eingabe ist
    // das direkt die Eingabe; bei Stunden-Eingabe die errechnete
    // Fertigmenge (sofern der Verlust bekannt ist). Bei Rohware-Eingabe
    // bleibt sie unbekannt (0) — dann wird nichts vom Bedarf abgezogen.
    final fertigMenge = switch (_einheit) {
      _MengenEinheit.fertigware => eingabe,
      _MengenEinheit.stunden => _fertigAusStunden ?? 0.0,
      _MengenEinheit.rohware => 0.0,
    };
    await erstelleTasksAusPlan(
      db: db,
      productId: produkt.id,
      schritte: _plan,
      bedarfId: _bedarf?.bedarf.id,
      fertigMengeKg: fertigMenge,
    );
    ref
        .read(autoBackupTriggerProvider)
        .fireDebounced(reason: 'Produkt geplant');
    ref.invalidate(bedarfProvider);

    if (!mounted) return;
    // Hinweis auf die berechnete Rohwaren-Menge des Plans.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Eingeplant · Rohwaren-Bedarf: '
          '${_rohware.toStringAsFixed(0)} kg',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
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

  Widget _griff() => Builder(
        builder: (context) => Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(2),
            ),
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

  // -- Stufe 1: Produkt + Starttag + Menge -------------------------------
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

        // Offene Bedarfe: der eigentliche Auslöser der Produktion.
        // Ein Tipp übernimmt Artikel UND offene Menge — genau der Weg,
        // den ihr sonst im Kopf geht.
        _BedarfVorschlaege(
          gewaehlt: _bedarf,
          onWaehlen: (info) {
            setState(() {
              if (_bedarf?.bedarf.id == info?.bedarf.id) {
                _bedarf = null;
                return;
              }
              _bedarf = info;
              if (info != null) {
                final p = _produkte
                    .where((x) => x.id == info.bedarf.productId)
                    .firstOrNull;
                if (p != null) {
                  _gewaehlt = p;
                  _ladeVerlust(p.id);
                  _ladeZeitmodell(p.id);
                }
                _menge.text = info.offenKg.round().toString();
              }
            });
          },
        ),

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
            // Vorher hart auf 240px begrenzt — dadurch war die Liste
            // abgeschnitten und der Rest des Sheets blieb leer.
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.45,
            ),
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
                        onTap: () {
                          setState(() => _gewaehlt = p);
                          _ladeVerlust(p.id);
                          _ladeZeitmodell(p.id);
                        },
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
          // Womit geplant wird: Rohware, Fertigware oder verfügbare Zeit.
          SegmentedButton<_MengenEinheit>(
            segments: const [
              ButtonSegment(
                value: _MengenEinheit.rohware,
                label: Text('Rohware'),
              ),
              ButtonSegment(
                value: _MengenEinheit.fertigware,
                label: Text('Fertigware'),
              ),
              ButtonSegment(
                value: _MengenEinheit.stunden,
                label: Text('Zeit'),
              ),
            ],
            selected: {_einheit},
            onSelectionChanged: (s) => setState(() => _einheit = s.first),
            showSelectedIcon: false,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _menge,
            decoration: InputDecoration(
              labelText: switch (_einheit) {
                _MengenEinheit.rohware => 'Menge Rohware (kg)',
                _MengenEinheit.fertigware => 'Menge Fertigware (kg)',
                _MengenEinheit.stunden => 'Produktionszeit (Stunden)',
              },
              suffixText:
                  _einheit == _MengenEinheit.stunden ? 'h' : 'kg',
              border: const OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),

          // Zeit-Eingabe: zeigt, was in dieser Zeit zu schaffen ist.
          if (_einheit == _MengenEinheit.stunden) ...[
            const SizedBox(height: 10),
            if (_dauerModelle.isEmpty)
              const _RohwareHinweis(
                text: 'Für dieses Produkt fehlen Leistungsdaten — aus der '
                    'Zeit lässt sich noch keine Menge ableiten.',
              )
            else if (_mengeAusStunden != null) ...[
              _RohwareHinweis(
                text: 'Schaffbar: ≈ ${_mengeAusStunden!.round()} kg Rohware'
                    '${_fertigAusStunden != null ? '  →  ergibt ≈ '
                        '${_fertigAusStunden!.round()} kg Fertigware' : ''}'
                    '${_engpassAbteilung != null
                        ? '\nBegrenzt durch: ${_engpassAbteilung!}'
                        : ''}',
              ),
              if (_fertigAusStunden == null && _histVerlust == null) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _verlustProzent,
                  decoration: const InputDecoration(
                    labelText: 'Verlust (%) — für die Fertigmenge',
                    suffixText: '%',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ],
          ],

          // Bei Fertigware: Verlust-Anzeige bzw. -Eingabe + Rohwaren-Vorschau.
          if (_einheit == _MengenEinheit.fertigware) ...[
            const SizedBox(height: 10),
            if (_histVerlust != null)
              _RohwareHinweis(
                text: 'Ø Verlust aus Historie: '
                    '${(_histVerlust! * 100).toStringAsFixed(1)} %'
                    '${_rohwareVorschau != null ? '  →  es werden ≈ '
                        '${_rohwareVorschau!.round()} kg Rohware verplant'
                        : ''}',
              )
            else ...[
              TextField(
                controller: _verlustProzent,
                decoration: const InputDecoration(
                  labelText: 'Verlust (%) — keine Historie vorhanden',
                  suffixText: '%',
                  border: OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              ),
              if (_rohwareVorschau != null) ...[
                const SizedBox(height: 8),
                _RohwareHinweis(
                  text: 'Es werden ≈ ${_rohwareVorschau!.round()} kg '
                      'Rohware verplant',
                ),
              ],
            ],
          ],
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

  // -- Stufe 2: Tag je Schritt zuweisen ----------------------------------
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

/// Kleine Farb-Legende in der Toolbar — macht die Auslastungsbalken
/// ohne Vorwissen verständlich („für einen Laien sofort ersichtlich").
class _Legende extends StatelessWidget {
  const _Legende();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget punkt(Color c, String text) => Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                text,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Auslastung:',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        punkt(_ampelFarbe(CapacityStatus.gut), 'gut gefüllt'),
        punkt(_ampelFarbe(CapacityStatus.ueberbucht), 'überbucht'),
      ],
    );
  }
}

/// Summenzeile einer ZUGEKLAPPTEN Abteilung.
///
/// Statt jeder Anlage eine eigene Spur zu zeigen, wird hier je Tag die
/// Gesamtauslastung aller Anlagen der Abteilung dargestellt (belegte
/// Stunden gegen die Summe der Kapazitäten) plus die Anzahl der Aufträge.
/// So bleibt die Woche auf einen Blick lesbar, auch wenn eine Abteilung
/// viele Anlagen hat.
///
/// Bewusst KEIN Drop-Ziel: In welche Anlage ein Auftrag soll, muss die
/// Planung entscheiden — dafür klappt man die Gruppe auf.
class _ZugeklappteZeile extends StatelessWidget {
  const _ZugeklappteZeile({
    required this.board,
    required this.abteilung,
    required this.spuren,
    required this.kompakt,
    required this.onAufklappen,
  });

  final WeekBoard board;
  final Abteilung abteilung;
  final List<BoardSpur> spuren;
  final bool kompakt;
  final VoidCallback onAufklappen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final farbe = abteilung.farbe;
    final anlagen = spuren.where((s) => s.istAnlage).length;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Label mit Aufklapp-Pfeil
          Container(
            width: _kLabelWidth,
            decoration: BoxDecoration(
              color: farbe.withValues(alpha: 0.09),
              border: Border(
                right: BorderSide(color: theme.dividerColor),
                top: BorderSide(
                  color: farbe.withValues(alpha: 0.55),
                  width: 2,
                ),
                bottom: BorderSide(color: theme.dividerColor),
              ),
            ),
            child: Row(
              children: [
                Container(width: 4, color: farbe),
                Expanded(
                  child: InkWell(
                    onTap: onAufklappen,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: kompakt ? 6 : 10,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.chevron_right,
                            size: 15,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  abteilung.anzeigeName,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    height: 1.2,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 2,
                                ),
                                if (anlagen > 0)
                                  Text(
                                    '$anlagen Anlagen',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontStyle: FontStyle.italic,
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.5),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Je Tag: Summe über alle Spuren der Abteilung
          for (final tag in board.tage)
            Expanded(
              child: _SummenZelle(
                tag: tag,
                belegt: spuren.fold<double>(
                  0,
                  (s, spur) => s + board.cellFor(spur, tag).belegtMinuten,
                ),
                kapazitaet: spuren.fold<double>(
                  0,
                  (s, spur) => s + board.cellFor(spur, tag).kapazitaetMinuten,
                ),
                auftraege: spuren.fold<int>(
                  0,
                  (s, spur) => s + board.cellFor(spur, tag).tasks.length,
                ),
                farbe: farbe,
                kompakt: kompakt,
              ),
            ),
        ],
      ),
    );
  }
}

/// Eine Tageszelle in der Summenzeile einer zugeklappten Abteilung.
class _SummenZelle extends StatelessWidget {
  const _SummenZelle({
    required this.tag,
    required this.belegt,
    required this.kapazitaet,
    required this.auftraege,
    required this.farbe,
    required this.kompakt,
  });

  final DateTime tag;
  final double belegt;
  final double kapazitaet;
  final int auftraege;
  final Color farbe;
  final bool kompakt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final istHeute = tag == DateTime(now.year, now.month, now.day);
    final quote = kapazitaet > 0 ? (belegt / kapazitaet) : 0.0;
    final ampel = quote > 1.0
        ? _ampelFarbe(CapacityStatus.ueberbucht)
        : (auftraege > 0
            ? _ampelFarbe(CapacityStatus.gut)
            : _ampelFarbe(CapacityStatus.frei));

    return Container(
      constraints: BoxConstraints(minHeight: kompakt ? 34 : 44),
      padding: EdgeInsets.all(kompakt ? 4 : 6),
      decoration: BoxDecoration(
        color: istHeute
            ? theme.colorScheme.primary.withValues(alpha: 0.04)
            : null,
        border: Border(
          right: BorderSide(color: theme.dividerColor),
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: auftraege == 0
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Text(
                      '${_fmtStunden(belegt)} / ${_fmtStunden(kapazitaet)} h',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.75),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: farbe.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        '$auftraege',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: quote.clamp(0.0, 1.0).toDouble(),
                    minHeight: 4,
                    backgroundColor:
                        theme.colorScheme.onSurface.withValues(alpha: 0.10),
                    color: ampel,
                  ),
                ),
              ],
            ),
    );
  }
}

/// Zeigt die offenen Bedarfe im Planen-Dialog.
///
/// Damit beginnt die Planung dort, wo sie im Betrieb wirklich beginnt:
/// bei dem, was gebraucht wird. Ein Tipp übernimmt Artikel und offene
/// Menge in den Dialog; die Verknüpfung sorgt dafür, dass die
/// Bedarfsliste anschließend automatisch weiß, was noch fehlt.
///
/// Ist kein Bedarf erfasst, erscheint hier nichts — freies Planen bleibt
/// jederzeit möglich.
class _BedarfVorschlaege extends ConsumerWidget {
  const _BedarfVorschlaege({required this.gewaehlt, required this.onWaehlen});

  final BedarfInfo? gewaehlt;
  final void Function(BedarfInfo?) onWaehlen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final offen = ref.watch(offeneBedarfeProvider).valueOrNull;
    if (offen == null || offen.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.playlist_add_check,
              size: 15,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Text(
              'Offener Bedarf',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 62,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: offen.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final info = offen[i];
              final aktiv = gewaehlt?.bedarf.id == info.bedarf.id;
              final farbe = info.ueberfaellig
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary;

              return InkWell(
                onTap: () => onWaehlen(aktiv ? null : info),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 210,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: aktiv
                        ? farbe.withValues(alpha: 0.14)
                        : theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: aktiv
                          ? farbe
                          : theme.dividerColor,
                      width: aktiv ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        info.artikelName,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            '${info.offenKg.round()} kg offen',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: farbe,
                            ),
                          ),
                          if (info.bedarf.termin != null) ...[
                            Text(
                              '  ·  ',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              '${info.bedarf.termin!.day.toString().padLeft(2, '0')}.'
                              '${info.bedarf.termin!.month.toString().padLeft(2, '0')}.',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: info.ueberfaellig
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                                color: info.ueberfaellig
                                    ? theme.colorScheme.error
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}

/// Kleiner Hinweis-Streifen unter dem Mengenfeld — zeigt bei Fertigware-
/// Eingabe informativ die umgerechnete Rohwaren-Menge.
class _RohwareHinweis extends StatelessWidget {
  const _RohwareHinweis({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.sync_alt,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
