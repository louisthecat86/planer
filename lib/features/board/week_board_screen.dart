import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/utils/zeit.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auftragsbestand_deckung.dart'
    show AuftragsBezug, bezuegeFuerNeueProduktion;
import '../../core/services/auto_backup_trigger.dart';
import '../../core/services/erledigt_service.dart';
import '../../core/services/tagesaufgaben_service.dart';
import '../bedarf/bedarf_screen.dart';
import '../whiteboard/task_detail_sheet.dart';
import '../whiteboard/whiteboard_provider.dart';
import 'board_druck_dialog.dart';
import 'board_print_service.dart';
import '../../core/utils/sheet_utils.dart';
import '../../core/utils/datum.dart';
import '../../core/utils/kalenderwoche.dart';
import 'board_providers.dart';

part 'board_aufgaben.dart';

// Breiter als früher (148): Namen wie „Schneideabteilung" oder
// „Verpackung Tef1 / Multivac Tef1" brachen sonst mitten im Wort um.
const double _kLabelWidth = 186;
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

String _fmtTagTitel(DateTime d) =>
    '${_kWkShort[d.weekday - 1]} ${d.day}.${d.month}.${d.year}';

/// Minuten als „h:mm" ("6:30", "8:00").
///
/// Bewusst KEINE Dezimalstunden mehr: „6,5" wurde als 6 h 50 min
/// missverstanden. Der Doppelpunkt macht unmissverständlich klar, dass
/// hinten Minuten stehen.
String _fmtStunden(double minuten) => Zeit.kurzOhneEinheit(minuten);

/// Kilogramm als ganze Zahl mit Tausenderpunkt: „12.857".
String _fmtKg(double kg) => kg.round().toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );

/// „Ausbeute 56,0 % · Ø der letzten 7 Produktionen" — damit sichtbar
/// ist, mit welcher Zahl gerechnet wird und woher sie stammt.
String _ausbeuteText(Ausbeute a) {
  final prozent =
      '${(a.faktor * 100).toStringAsFixed(1).replaceAll('.', ',')} %';
  switch (a.quelle) {
    case AusbeuteQuelle.historie:
      final n = a.historieAnzahl;
      final aus = n == 1
          ? 'aus der letzten Produktion'
          : 'Ø der letzten $n Produktionen';
      return 'Ausbeute $prozent · $aus';
    case AusbeuteQuelle.eingabe:
      return 'Ausbeute $prozent · von Hand eingetragen';
    case AusbeuteQuelle.keine:
      return 'Keine Ausbeute bekannt — gerechnet ohne Verlust';
  }
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

/// Grün für Erledigtes — Karten, Tagesaufgaben, Haken.
const Color _kErledigtFarbe = Color(0xFF43A047);

/// Hintergrund einer erledigten Karte: ein Hauch Grün über der Fläche,
/// damit die Schrift in beiden Modi gut lesbar bleibt.
Color _erledigtHintergrund(ThemeData theme) => Color.alphaBlend(
      _kErledigtFarbe.withValues(alpha: 0.16),
      theme.colorScheme.surface,
    );

/// Hakt eine Karte ab oder nimmt den Haken zurück. Gebündelte Karten
/// (mehrere Aufträge desselben Artikels an einem Tag) wirken auf alle.
///
/// Ist die Produktion erfasst, gibt es nichts zu tun: Dann entscheidet die
/// Erfassung, nicht der Haken.
Future<void> _abhaken(WidgetRef ref, BoardTask task) async {
  if (task.erledigt == Erledigt.erfasst) return;
  final abhaken = task.erledigt == null;
  final db = ref.read(databaseProvider);
  await ErledigtService.abhaken(db, task.mitgliederIds, erledigt: abhaken);
  ref
      .read(autoBackupTriggerProvider)
      .fireDebounced(reason: abhaken ? 'Auftrag abgehakt' : 'Haken entfernt');
  ref
    ..invalidate(weekBoardProvider)
    ..invalidate(dayBoardProvider)
    ..invalidate(dailyTasksProvider);
}

/// Haken an einer Auftragskarte: offen, abgehakt oder — dann nicht
/// antippbar — durch die erfasste Produktion erledigt.
class _HakenKnopf extends StatelessWidget {
  const _HakenKnopf({
    required this.erledigt,
    required this.onTap,
    this.groesse = 16,
  });

  final Erledigt? erledigt;

  /// null: nur anzeigen (etwa an der Karte, die gerade gezogen wird).
  final VoidCallback? onTap;
  final double groesse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (symbol, farbe, hinweis) = switch (erledigt) {
      Erledigt.erfasst => (
          Icons.fact_check_rounded,
          _kErledigtFarbe,
          'Produktion erfasst — damit erledigt',
        ),
      Erledigt.abgehakt => (
          Icons.check_box_rounded,
          _kErledigtFarbe,
          'Erledigt — antippen, um den Haken zu entfernen',
        ),
      null => (
          Icons.check_box_outline_blank_rounded,
          theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          'Als erledigt abhaken',
        ),
    };
    // Etwas breiter als das Symbol: Mit der Maus wird aus einem
    // verwackelten Klick sonst schnell ein Ziehen der ganzen Karte.
    final icon = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Icon(symbol, size: groesse, color: farbe),
    );
    if (onTap == null) return icon;
    return Tooltip(
      message: hinweis,
      // Eigenes, durchsichtiges Material: Die Karte malt ihre Fläche über
      // das Material darunter — die Hover- und Tipp-Welle wäre sonst
      // unsichtbar.
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          // Erfasst: kein eigener Tipp — er geht an die Karte und öffnet
          // wie gewohnt die Details.
          onTap: erledigt == Erledigt.erfasst ? null : onTap,
          borderRadius: BorderRadius.circular(4),
          child: icon,
        ),
      ),
    );
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

  /// Läuft gerade ein Druck (Laden, Dialog, Vorschau)?
  bool _druckLaeuft = false;

  // ---- Navigation (je nach Modus Woche oder Tag) ----

  // Über die Tageszahl gerechnet, nicht mit `Duration`: Am Wochenende der
  // Zeitumstellung hat ein Tag 23 oder 25 Stunden. `add(Duration(days: 7))`
  // landete dann auf 23:00 des Sonntags — und „nächste Woche" zeigte
  // dieselbe Woche noch einmal.
  void _zurueck() {
    final d = ref.read(selectedDateProvider);
    final delta = _modus == _Modus.woche ? 7 : 1;
    ref.read(selectedDateProvider.notifier).state =
        DateTime(d.year, d.month, d.day - delta);
  }

  void _vor() {
    final d = ref.read(selectedDateProvider);
    final delta = _modus == _Modus.woche ? 7 : 1;
    ref.read(selectedDateProvider.notifier).state =
        DateTime(d.year, d.month, d.day + delta);
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
    // Verglichen wird die Spur, nicht die Anlage: Ein Auftrag in der
    // Sammelspur kann trotzdem eine Anlage haben (etwa eine aus einer
    // anderen Abteilung) — die behält er, solange er in der Spur bleibt.
    final anlageWechselt = zielSpur != null && zielSpur.id != task.spurId;
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

  /// Fragt, was gedruckt wird — Woche oder Tag, gesamte Übersicht oder
  /// einzelne Abteilungen — und öffnet die Druckvorschau.
  ///
  /// Board und Aufgaben sind beim Klick meist schon geladen; der Dialog
  /// zeigt damit je Abteilung, wie viel geplant ist.
  Future<void> _drucken(DateTime montag, DateTime sel) async {
    // Ein Doppelklick öffnete sonst zwei Dialoge.
    if (_druckLaeuft) return;
    _druckLaeuft = true;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final woche = await ref.read(weekBoardProvider(montag).future);
      final tag = await ref.read(dayBoardProvider(sel).future);
      final aufgaben = await ref.read(tagesaufgabenProvider(montag).future);
      if (!mounted) return;
      final auswahl = await zeigeBoardDruckDialog(
        context,
        zeitraum:
            _modus == _Modus.woche ? DruckZeitraum.woche : DruckZeitraum.tag,
        woche: 'KW ${isoKalenderwoche(montag)}',
        tag: _fmtTagKurz(tag.tag),
        umfangWoche: druckUmfangWoche(woche, aufgaben),
        umfangTag: druckUmfangTag(tag, aufgaben),
      );
      if (auswahl == null) return;
      switch (auswahl.zeitraum) {
        case DruckZeitraum.woche:
          await BoardPrintService.druckeWoche(
            woche,
            aufgaben: aufgaben,
            abteilungen: auswahl.abteilungen,
          );
        case DruckZeitraum.tag:
          await BoardPrintService.druckeTag(
            tag,
            aufgaben: aufgaben,
            abteilungen: auswahl.abteilungen,
          );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text('Der Plan ließ sich nicht drucken. ($e)'),
        ),
      );
    } finally {
      _druckLaeuft = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sel = ref.watch(selectedDateProvider);
    final montag = mondayOfWeek(sel);
    final weekAsync = ref.watch(weekBoardProvider(montag));
    final dayAsync = ref.watch(dayBoardProvider(sel));
    // Die sonstigen Aufgaben schon hier: So laden sie parallel zum Board
    // und bleiben beim Wechsel zwischen Woche und Tag geladen. Beobachtet
    // wird nur ein Fehler — die Daten selbst lesen Raster und Tagesliste,
    // sonst baute jeder Haken den ganzen Bildschirm neu.
    final aufgabenFehler =
        ref.watch(tagesaufgabenProvider(montag).select((a) => a.error));
    // Um Mitternacht neu bauen: Offene Aufgaben von gestern sind ab dann
    // liegen geblieben und werden orange.
    ref.watch(heuteProvider);

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
        title: Text(
          istWoche
              ? 'Planungsboard · KW ${isoKalenderwoche(montag)}'
              : 'Tagesplan · ${_fmtTagTitel(sel)}',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Drucken',
            onPressed: () => _drucken(montag, sel),
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
          if (aufgabenFehler != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                'Sonstige Aufgaben konnten nicht geladen werden: '
                '$aufgabenFehler',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.error,
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

    // Sonstige Aufgaben je Abteilung und Tag. Beim Neuladen bleibt der
    // alte Stand stehen, statt kurz zu leeren.
    final aufgaben =
        ref.watch(tagesaufgabenProvider(board.wochenStart)).valueOrNull ??
            const <AufgabenZelle, List<Tagesaufgabe>>{};

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
            aufgaben: aufgaben,
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
      // Unter den Anlagen: die sonstigen Aufgaben der Abteilung.
      reihen.add(
        _AufgabenZeile(
          board: board,
          abteilung: abt,
          aufgaben: aufgaben,
          kompakt: kompakt,
        ),
      );
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
                board: board,
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

class _TagesZelle extends ConsumerWidget {
  const _TagesZelle({
    required this.board,
    required this.cell,
    required this.kompakt,
    required this.onTapTask,
    required this.onMoveHere,
  });

  final WeekBoard board;
  final BoardCell cell;
  final bool kompakt;
  final void Function(BoardTask) onTapTask;
  final void Function(BoardTask) onMoveHere;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final farbe = _ampelFarbe(cell.status);
    final now = DateTime.now();
    final istHeute = cell.tag == DateTime(now.year, now.month, now.day);
    // Auch reine Nebenzeiten machen die Zelle „belegt" — sonst bliebe
    // sie flach und die erfasste Reinigungszeit unsichtbar.
    final belegt = cell.tasks.isNotEmpty || cell.zusatzzeiten.isNotEmpty;

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
        final gleicheSpur = t.spurId == cell.spur.id;
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
          // Kein Stack: Ein Stack, dessen Kinder alle positioniert sind,
          // schrumpft auf die Mindesthöhe — dadurch wurden Aufträge
          // abgeschnitten. Der Knopf sitzt deshalb im normalen Fluss.
          child: _inhalt(context, ref, highlight, farbe),
        );
      },
    );
  }

  Future<void> _zusatzzeitenVerwalten(
    BuildContext context,
    WidgetRef ref,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ZusatzzeitVerwaltung(
        spurName: cell.spur.anzeigeName,
        tag: cell.tag,
        spurId: cell.spur.id,
        eintraege: cell.zusatzzeiten,
      ),
    );
    ref.invalidate(weekBoardProvider);
    ref.invalidate(dayBoardProvider);
  }

  Widget _inhalt(
    BuildContext context,
    WidgetRef ref,
    bool highlight,
    Color farbe,
  ) {
    final belegt = cell.tasks.isNotEmpty || cell.zusatzzeiten.isNotEmpty;
    final knopf = _ZusatzKnopf(
      minuten: cell.zusatzMinuten,
      onTap: () => _zusatzzeitenVerwalten(context, ref),
    );
    return !belegt
              // -- LEERE ZELLE: bewusst ruhig. Keine Zahlen, kein Balken —
              //    freie Kapazität ist der Normalfall und muss nicht
              //    35-mal wiederholt werden. Nur beim Ziehen erscheint
              //    ein Hinweis.
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Center(
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
                      ),
                    ),
                    knopf,
                  ],
                )
              // -- BELEGTE ZELLE: Auslastung kompakt + Aufträge
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _AuslastungsPille(
                            belegt: cell.belegtMinuten,
                            kapazitaet: cell.kapazitaetMinuten,
                            auslastung: cell.auslastung,
                            farbe: farbe,
                            status: cell.status,
                            kompakt: kompakt,
                          ),
                        ),
                        knopf,
                      ],
                    ),
                    SizedBox(height: kompakt ? 3 : 6),
                    for (final task in cell.tasks)
                      Padding(
                        padding: EdgeInsets.only(bottom: kompakt ? 3 : 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _AuftragsKarte(
                              task: task,
                              kompakt: kompakt,
                              onTap: () => onTapTask(task),
                              onHaken: () => _abhaken(ref, task),
                            ),
                            if (board.nachbarnFuer(task) != null)
                              _KettenMarker(
                                nachbar: board.nachbarnFuer(task)!,
                                onSprung: (datum) => ref
                                    .read(selectedDateProvider.notifier)
                                    .state = datum,
                              ),
                          ],
                        ),
                      ),
                  ],
                );
  }
}

/// Kleiner Knopf an der Tageszelle für Rüst-/Reinigungszeiten.
///
/// Zeigt die bereits erfasste Nebenzeit an, damit man sie im Wochenraster
/// auf einen Blick sieht, ohne die Zelle zu öffnen.
class _ZusatzKnopf extends StatelessWidget {
  const _ZusatzKnopf({required this.minuten, required this.onTap});

  final double minuten;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hat = minuten > 0;
    return Tooltip(
      message: hat
          ? 'Nebenzeiten: ${Zeit.kurz(minuten)} — zum Bearbeiten tippen'
          : 'Rüst-/Reinigungszeit erfassen',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.more_time,
                size: 14,
                color: hat
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.45),
              ),
              if (hat) ...[
                const SizedBox(width: 2),
                Text(
                  Zeit.kurzOhneEinheit(minuten),
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Verwaltet die Nebenzeiten einer Spur an einem Tag: anlegen und löschen
/// in einem Dialog, damit es auch im engen Wochenraster bedienbar bleibt.
class _ZusatzzeitVerwaltung extends ConsumerStatefulWidget {
  const _ZusatzzeitVerwaltung({
    required this.spurName,
    required this.tag,
    required this.spurId,
    required this.eintraege,
  });

  final String spurName;
  final DateTime tag;
  final String spurId;
  final List<Zusatzzeit> eintraege;

  @override
  ConsumerState<_ZusatzzeitVerwaltung> createState() =>
      _ZusatzzeitVerwaltungState();
}

class _ZusatzzeitVerwaltungState
    extends ConsumerState<_ZusatzzeitVerwaltung> {
  late List<Zusatzzeit> _liste = [...widget.eintraege];

  Future<void> _anlegen() async {
    final res = await showDialog<({String art, double minuten, String? notiz})>(
      context: context,
      builder: (_) => _ZusatzzeitDialog(spurName: widget.spurName),
    );
    if (res == null) return;
    final db = ref.read(databaseProvider);
    final id = const Uuid().v4();
    await db.into(db.zusatzzeiten).insert(
          ZusatzzeitenCompanion.insert(
            id: id,
            datum: DateTime(widget.tag.year, widget.tag.month, widget.tag.day),
            spurId: widget.spurId,
            art: res.art,
            minuten: res.minuten,
            notiz: Value(res.notiz),
          ),
        );
    ref
        .read(autoBackupTriggerProvider)
        .fireDebounced(reason: 'Nebenzeit angelegt');
    final neu = await (db.select(db.zusatzzeiten)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (neu != null && mounted) setState(() => _liste = [..._liste, neu]);
  }

  Future<void> _loeschen(Zusatzzeit z) async {
    final db = ref.read(databaseProvider);
    await (db.update(db.zusatzzeiten)..where((t) => t.id.equals(z.id)))
        .write(ZusatzzeitenCompanion(deletedAt: Value(DateTime.now())));
    ref
        .read(autoBackupTriggerProvider)
        .fireDebounced(reason: 'Nebenzeit gelöscht');
    if (mounted) {
      setState(() => _liste = _liste.where((e) => e.id != z.id).toList());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summe = _liste.fold<double>(0, (a, z) => a + z.minuten);
    return AlertDialog(
      title: const Text('Rüst- und Reinigungszeiten'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.spurName} · ${_fmtTagTitel(widget.tag)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (_liste.isEmpty)
              Text(
                'Noch keine Nebenzeiten erfasst.',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final z in _liste)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    z.art == 'reinigen'
                        ? Icons.cleaning_services
                        : (z.art == 'ruesten'
                            ? Icons.build_outlined
                            : Icons.schedule),
                    size: 18,
                  ),
                  title: Text(
                    '${_artName(z.art)} · ${Zeit.kurz(z.minuten)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: (z.notiz ?? '').trim().isEmpty
                      ? null
                      : Text(z.notiz!.trim()),
                  trailing: IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: Colors.red,
                    ),
                    tooltip: 'Entfernen',
                    onPressed: () => _loeschen(z),
                  ),
                ),
            if (_liste.isNotEmpty) ...[
              const Divider(),
              Text(
                'Summe: ${Zeit.kurz(summe)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _anlegen,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Zeit hinzufügen'),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fertig'),
        ),
      ],
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
    required this.onHaken,
    this.kompakt = false,
  });

  final BoardTask task;
  final VoidCallback onTap;
  final VoidCallback onHaken;
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
        child: _KartenInhalt(task: task, kompakt: kompakt, onHaken: onHaken),
      ),
    );
  }
}

class _KartenInhalt extends StatelessWidget {
  const _KartenInhalt({
    required this.task,
    this.dragging = false,
    this.kompakt = false,
    this.onHaken,
  });

  final BoardTask task;
  final bool dragging;
  final bool kompakt;

  /// Haken setzen oder entfernen. null: Der Haken wird nur angezeigt —
  /// an der Karte, die gerade gezogen wird, und an ihrem Platzhalter.
  final VoidCallback? onHaken;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final abtColor = task.abteilung.farbe;
    final kette = _kettenFarbe(task.kettenId, theme.brightness);
    // Erledigt: grün hinterlegt und grün umrandet — so sieht man in der
    // ganzen Woche auf einen Blick, was schon durch ist.
    final erledigt = task.erledigt != null;
    final hintergrund =
        erledigt ? _erledigtHintergrund(theme) : theme.colorScheme.surface;
    final rahmen = erledigt
        ? _kErledigtFarbe.withValues(alpha: 0.75)
        : theme.dividerColor;

    // Kompaktvariante: alles in EINER Zeile — Ketten-Kante, Kurzcode-Chip,
    // Produktname (einzeilig), rechts die Kennzahl und der Haken. So passt
    // ein ganzer Tag ohne Scrollen ins Bild.
    if (kompakt) {
      return Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: hintergrund,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: rahmen),
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
                // Artikelnummer voran: Bezeichnungen ähneln sich stark,
                // die Nummer ist im Raster das schnellere Erkennungsmerkmal.
                child: Text.rich(
                  TextSpan(
                    children: [
                      if (task.artikelnummer.isNotEmpty)
                        TextSpan(
                          text: '${task.artikelnummer}  ',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      TextSpan(text: task.productName),
                    ],
                  ),
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
              Text(
                '${task.mengeKg.toStringAsFixed(0)}kg·'
                '${_fmtStunden(task.dauerMinuten)} h',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 2),
              _HakenKnopf(
                erledigt: task.erledigt,
                onTap: onHaken,
                groesse: 15,
              ),
              const SizedBox(width: 2),
            ],
          ),
        ),
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: hintergrund,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: rahmen),
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
                    padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text.rich(
                                TextSpan(
                                  children: [
                                    if (task.artikelnummer.isNotEmpty)
                                      TextSpan(
                                        text: '${task.artikelnummer}  ',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                    TextSpan(text: task.productName),
                                  ],
                                ),
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
                        const SizedBox(width: 2),
                        _HakenKnopf(
                          erledigt: task.erledigt,
                          onTap: onHaken,
                          groesse: 18,
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

/// Markiert an einer Auftragskarte, dass dieselbe Produktionskette Schritte
/// in einer anderen Woche hat (wochenübergreifende Produktion). Antippen
/// springt in die betreffende Woche.
class _KettenMarker extends StatelessWidget {
  const _KettenMarker({required this.nachbar, required this.onSprung});

  final KettenNachbar nachbar;
  final void Function(DateTime) onSprung;

  @override
  Widget build(BuildContext context) {
    final v = nachbar.vorher;
    final n = nachbar.nachher;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Wrap(
        spacing: 4,
        runSpacing: 2,
        children: [
          if (v != null)
            _chip(
              context,
              '← Vorstufe · KW${v.kw}',
              'Vorstufe: ${v.abteilung.anzeigeName} in KW${v.kw} '
                  '(${v.datum.day}.${v.datum.month}.) — antippen zum Springen',
              () => onSprung(v.datum),
            ),
          if (n != null)
            _chip(
              context,
              'Folgestufe · KW${n.kw} →',
              'Folgestufe: ${n.abteilung.anzeigeName} in KW${n.kw} '
                  '(${n.datum.day}.${n.datum.month}.) — antippen zum Springen',
              () => onSprung(n.datum),
            ),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    String text,
    String tooltip,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
        ),
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

class _DayList extends ConsumerWidget {
  const _DayList({
    required this.day,
    required this.onTapTask,
    required this.onReorder,
  });

  final DayBoard day;
  final void Function(BoardTask) onTapTask;
  final void Function(List<BoardTask>, int, int) onReorder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Derselbe Schlüssel wie in der Woche (Montag) — beide Ansichten teilen
    // sich einen Ladevorgang.
    final aufgaben =
        ref.watch(tagesaufgabenProvider(mondayOfWeek(day.tag))).valueOrNull ??
            const <AufgabenZelle, List<Tagesaufgabe>>{};

    // Die sonstigen Aufgaben gehören der Abteilung, nicht der Anlage: Sie
    // stehen in der ersten Karte jeder Abteilung.
    final gesehen = <Abteilung>{};
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final lane in day.lanes)
          _DayDeptCard(
            lane: lane,
            tag: day.tag,
            onTapTask: onTapTask,
            onReorder: onReorder,
            aufgaben: gesehen.add(lane.abteilung)
                ? aufgaben[(lane.abteilung.dbValue, day.tag)] ??
                    const <Tagesaufgabe>[]
                : null,
          ),
      ],
    );
  }
}

class _DayDeptCard extends ConsumerWidget {
  const _DayDeptCard({
    required this.lane,
    required this.tag,
    required this.onTapTask,
    required this.onReorder,
    this.aufgaben,
  });

  final DayLane lane;
  final DateTime tag;
  final void Function(BoardTask) onTapTask;
  final void Function(List<BoardTask>, int, int) onReorder;

  /// Sonstige Aufgaben der Abteilung an diesem Tag. Nur an der ersten
  /// Karte einer Abteilung gesetzt, sonst null.
  final List<Tagesaufgabe>? aufgaben;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final farbe = _ampelFarbe(lane.status);
    final aufgaben = this.aufgaben;
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
                IconButton(
                  icon: const Icon(Icons.more_time, size: 18),
                  tooltip: 'Rüst-/Reinigungszeit hinzufügen',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _zusatzzeitAnlegen(context, ref),
                ),
                if (aufgaben != null)
                  IconButton(
                    icon: const Icon(Icons.add_task, size: 18),
                    tooltip: 'Sonstige Aufgabe für '
                        '${lane.abteilung.anzeigeName} eintragen',
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        _aufgabeAnlegen(context, lane.abteilung, tag),
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
            // Nebenzeiten sichtbar machen — sie stecken in der Belegung
            // oben, sollen aber nachvollziehbar bleiben.
            if (lane.zusatzzeiten.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final z in lane.zusatzzeiten)
                    InputChip(
                      avatar: Icon(
                        z.art == 'reinigen'
                            ? Icons.cleaning_services
                            : (z.art == 'ruesten'
                                ? Icons.build_outlined
                                : Icons.schedule),
                        size: 15,
                      ),
                      label: Text(
                        '${_artName(z.art)} ${Zeit.kurz(z.minuten)}'
                        '${(z.notiz ?? '').trim().isEmpty
                            ? ''
                            : ' · ${z.notiz!.trim()}'}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      onDeleted: () => _zusatzzeitLoeschen(ref, z),
                      deleteIcon: const Icon(Icons.close, size: 15),
                    ),
                ],
              ),
            ],
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
                  onHaken: () => _abhaken(ref, lane.tasks[i]),
                  onUp: i > 0 ? () => onReorder(lane.tasks, i, i - 1) : null,
                  onDown: i < lane.tasks.length - 1
                      ? () => onReorder(lane.tasks, i, i + 1)
                      : null,
                ),
            if (aufgaben != null && aufgaben.isNotEmpty) ...[
              const Divider(height: 20),
              _AufgabenAbschnitt(
                abteilung: lane.abteilung,
                aufgaben: aufgaben,
                // Heißt die Karte nach einer Anlage, gehört der Name der
                // Abteilung in die Überschrift.
                mitAbteilung: lane.spur.istAnlage,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Legt eine Rüst-/Reinigungszeit für diese Spur an diesem Tag an.
  Future<void> _zusatzzeitAnlegen(BuildContext context, WidgetRef ref) async {
    final res = await showDialog<({String art, double minuten, String? notiz})>(
      context: context,
      builder: (_) => _ZusatzzeitDialog(spurName: lane.spur.anzeigeName),
    );
    if (res == null) return;
    final db = ref.read(databaseProvider);
    await db.into(db.zusatzzeiten).insert(
          ZusatzzeitenCompanion.insert(
            id: const Uuid().v4(),
            datum: DateTime(tag.year, tag.month, tag.day),
            spurId: lane.spur.id,
            art: res.art,
            minuten: res.minuten,
            notiz: Value(res.notiz),
          ),
        );
    ref
        .read(autoBackupTriggerProvider)
        .fireDebounced(reason: 'Nebenzeit angelegt');
    ref.invalidate(dayBoardProvider);
    ref.invalidate(weekBoardProvider);
  }

  Future<void> _zusatzzeitLoeschen(WidgetRef ref, Zusatzzeit z) async {
    final db = ref.read(databaseProvider);
    await (db.update(db.zusatzzeiten)..where((t) => t.id.equals(z.id)))
        .write(ZusatzzeitenCompanion(deletedAt: Value(DateTime.now())));
    ref
        .read(autoBackupTriggerProvider)
        .fireDebounced(reason: 'Nebenzeit gelöscht');
    ref.invalidate(dayBoardProvider);
    ref.invalidate(weekBoardProvider);
  }
}

/// Dialog zum Erfassen einer Rüst-/Reinigungszeit.
class _ZusatzzeitDialog extends StatefulWidget {
  const _ZusatzzeitDialog({required this.spurName});

  final String spurName;

  @override
  State<_ZusatzzeitDialog> createState() => _ZusatzzeitDialogState();
}

class _ZusatzzeitDialogState extends State<_ZusatzzeitDialog> {
  String _art = 'ruesten';
  double? _minuten;
  final _notiz = TextEditingController();

  @override
  void dispose() {
    _notiz.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rüst-/Reinigungszeit'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.spurName,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'ruesten', label: Text('Rüsten')),
                ButtonSegment(value: 'reinigen', label: Text('Reinigen')),
                ButtonSegment(value: 'sonstiges', label: Text('Sonstiges')),
              ],
              selected: {_art},
              onSelectionChanged: (s) => setState(() => _art = s.first),
              showSelectedIcon: false,
            ),
            const SizedBox(height: 14),
            ZeitEingabe(
              label: 'Dauer',
              minuten: _minuten,
              onChanged: (m) => setState(() => _minuten = m),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _notiz,
              decoration: const InputDecoration(
                labelText: 'Notiz (optional)',
                hintText: 'z.B. Wechsel hell → dunkel',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: (_minuten ?? 0) <= 0
              ? null
              : () {
                  Navigator.of(context).pop((
                    art: _art,
                    minuten: _minuten!,
                    notiz: _notiz.text.trim().isEmpty
                        ? null
                        : _notiz.text.trim(),
                  ),);
                },
          child: const Text('Übernehmen'),
        ),
      ],
    );
  }
}

/// Lesbarer Name der Nebenzeit-Art.
String _artName(String art) {
  switch (art) {
    case 'ruesten':
      return 'Rüsten';
    case 'reinigen':
      return 'Reinigen';
    default:
      return 'Sonstiges';
  }
}

class _DayTaskRow extends StatelessWidget {
  const _DayTaskRow({
    required this.task,
    required this.onTap,
    required this.onHaken,
    this.onUp,
    this.onDown,
  });

  final BoardTask task;
  final VoidCallback onTap;
  final VoidCallback onHaken;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final erledigt = task.erledigt != null;

    final zeile = Row(
      children: [
        _HakenKnopf(
          erledigt: task.erledigt,
          onTap: onHaken,
          groesse: 20,
        ),
        const SizedBox(width: 6),
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
                task.artikelnummer.isEmpty
                    ? task.productName
                    : '${task.artikelnummer}  ${task.productName}',
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
    );

    // Material statt Container: Auf einer eingefärbten Fläche wäre die
    // Tipp-Welle des InkWell sonst unsichtbar.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: erledigt ? _erledigtHintergrund(theme) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: erledigt
              ? BorderSide(color: _kErledigtFarbe.withValues(alpha: 0.6))
              : BorderSide.none,
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: zeile,
          ),
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

/// Zeitmodell einer Abteilung: Minuten = fix + proKg × Fertigmenge — samt
/// Herkunft der Zahlen, damit die Ansicht sagen kann, worauf die Menge zur
/// eingegebenen Zeit beruht.
typedef _Zeitmodell = ({
  String abteilung,
  double fix,
  double proKg,
  DauerQuelle quelle,
  HistorienLeistung? historie,
});

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

  /// Von Hand eingetragener Verlust in %. Wird nur gefragt, solange für
  /// den Artikel keine Produktion mit Roh- und Fertigware erfasst ist.
  final _verlustProzent = TextEditingController();

  List<Product> _produkte = [];
  Product? _gewaehlt;

  /// Womit geplant wird: Rohware (Standard), Fertigware oder Zeit. Wer aus
  /// einem Bedarf plant, landet bei Fertigware — Bedarfe sind Fertigware.
  _MengenEinheit _einheit = _MengenEinheit.rohware;

  /// Ausbeute des gewählten Artikels — dieselbe Zahl, mit der der Plan
  /// rechnet. null, solange sie noch geladen wird.
  Ausbeute? _ausbeute;

  /// Bedarf, aus dem geplant wird (optional). Ist einer gewählt, wird die
  /// geplante Menge gegen ihn gerechnet — die Bedarfsliste zeigt dann
  /// automatisch, was noch offen ist.
  BedarfInfo? _bedarf;

  late DateTime _startTag;

  _PlanStufe _stufe = _PlanStufe.auswahl;
  List<GeplanterSchritt> _plan = [];

  /// Abteilungen des Plans, die diesmal nicht ins Board kommen — etwa die
  /// Zerlegung, wenn das Fleisch schon zerlegt angeliefert wird. Als
  /// [GeplanterSchritt.stepId]; gilt nur für diese Planung und bleibt beim
  /// Zurückblättern erhalten, solange der Artikel derselbe ist.
  final Set<String> _abgewaehlt = <String>{};

  /// Rohware und Fertigware des berechneten Plans.
  double _planRohKg = 0;
  double _planFertigKg = 0;

  /// Ist [_planFertigKg] eine echte Fertigmenge? Bei Rohware- oder
  /// Zeit-Eingabe ohne bekannte Ausbeute nicht — dann wird nichts gegen
  /// den Bedarf gerechnet.
  bool _planFertigBekannt = false;

  bool _busy = false;

  /// Zählt die Ladevorgänge der Artikeldaten. Eine ältere Rechnung, die
  /// erst nach einer neueren fertig wird, darf deren Ergebnis nicht
  /// überschreiben.
  int _ladeNr = 0;

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

  /// Artikel gewählt: Ausbeute und Zeitmodell laden.
  void _waehleProdukt(Product p) {
    setState(() {
      _gewaehlt = p;
      _abgewaehlt.clear();
      _ausbeute = null;
      _dauerModelle = [];
      _zeitAbteilung = null;
    });
    _ladeArtikeldaten(p.id);
  }

  void _produktAbwaehlen() {
    _ladeNr++; // laufende Rechnungen verwerfen
    setState(() {
      _gewaehlt = null;
      _abgewaehlt.clear();
      _ausbeute = null;
      _dauerModelle = [];
      _zeitAbteilung = null;
    });
  }

  /// Lädt Ausbeute und Zeitmodell des Artikels.
  ///
  /// Beides hängt vom von Hand eingetragenen Verlust ab, solange keine
  /// Produktion mit Fertigware erfasst ist — deshalb wird bei jeder
  /// Änderung dieses Felds neu geladen.
  Future<void> _ladeArtikeldaten(String productId) async {
    final nr = ++_ladeNr;
    final db = ref.read(databaseProvider);
    final ersatz = _ersatzAusbeute;
    try {
      final ausbeute = await ermittleAusbeute(db, productId, ersatz: ersatz);
      final modelle = await _berechneZeitmodell(db, productId, ersatz);
      if (!mounted || nr != _ladeNr) return;
      setState(() {
        _ausbeute = ausbeute;
        _dauerModelle = modelle;
        _zeitAbteilung = _passendeZeitAbteilung(modelle);
      });
    } catch (_) {
      if (!mounted || nr != _ladeNr) return;
      setState(() {
        _ausbeute = Ausbeute.unbekannt;
        _dauerModelle = [];
        _zeitAbteilung = null;
      });
    }
  }

  // -- Zeitmodell: Minuten = Fixanteil + Faktor × FERTIGmenge -------------
  // Die Dauer einer Abteilung ist „Zeit × (Menge / Referenzmenge)", also
  // linear in der Menge — die Rechnung lässt sich damit umkehren. Der
  // Fixanteil bleibt im Modell, ist heute aber praktisch null.
  //
  // Die Menge ist die FERTIGmenge, weil [berechneSchrittPlan] mit ihr
  // gerechnet wird. Die Bratstraße läuft dabei mit der zugehörigen Rohware
  // (Fertigmenge ÷ Ausbeute) gegen den Ø der letzten Produktionen. Fehlen
  // einer anderen Abteilung die Leistungsdaten, rechnet auch sie damit —
  // sonst ließe sich für sie aus der Zeit keine Menge ableiten.
  //
  // WICHTIG: Es wird JE ABTEILUNG gerechnet, nicht über die Summe. Im
  // Wochenplan bekommt jede Abteilung ihren eigenen Tag mit 9 Stunden;
  // „2 Stunden produzieren" heißt also 2 Stunden AN DER LINIE, nicht
  // 2 Stunden über alle Abteilungen zusammengezählt. Maßgeblich ist die
  // engste Abteilung — sie begrenzt, was in der Zeit zu schaffen ist.
  List<_Zeitmodell> _dauerModelle = [];

  Future<List<_Zeitmodell>> _berechneZeitmodell(
    AppDatabase db,
    String productId,
    double? ersatz,
  ) async {
    final klein = await berechneSchrittPlan(
      db: db,
      productId: productId,
      mengeKg: 100,
      startTag: _startTag,
      ausbeuteErsatz: ersatz,
    );
    final gross = await berechneSchrittPlan(
      db: db,
      productId: productId,
      mengeKg: 1000,
      startTag: _startTag,
      ausbeuteErsatz: ersatz,
    );
    final modelle = <_Zeitmodell>[];
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
        quelle: klein.schritte[i].dauerQuelle,
        historie: klein.schritte[i].historie,
      ),);
    }
    return modelle;
  }

  /// Bezug der Zeiteingabe: die bisher gewählte Abteilung, wenn es sie
  /// noch gibt, sonst die Bratstraße — die durchlaufende Linie und damit
  /// der übliche Taktgeber —, sonst die erste Abteilung des Prozesses.
  String? _passendeZeitAbteilung(
    List<_Zeitmodell> modelle,
  ) {
    if (modelle.isEmpty) return null;
    final bisher = _zeitAbteilung;
    if (bisher != null && modelle.any((m) => m.abteilung == bisher)) {
      return bisher;
    }
    for (final m in modelle) {
      if (m.abteilung.contains('bratstra')) return m.abteilung;
    }
    return modelle.first.abteilung;
  }

  /// Auf welche Abteilung sich die eingegebene Stundenzahl bezieht.
  String? _zeitAbteilung;

  _Zeitmodell? get _bezugsModell {
    final a = _zeitAbteilung;
    if (a == null) return null;
    for (final m in _dauerModelle) {
      if (m.abteilung == a) return m;
    }
    return null;
  }

  /// Worauf die Menge zur eingegebenen Zeit beruht, wenn es die letzten
  /// Produktionen sind — mit deren Zahlen, damit nachvollziehbar ist, woher
  /// „schaffbar" kommt. null bei gepflegten Leistungsdaten.
  String? get _grundlageHinweis {
    final m = _bezugsModell;
    final h = m?.historie;
    if (m == null || h == null) return null;
    final basis = '${h.herkunft}: ${h.kennzahlen}';
    if (m.quelle == DauerQuelle.historieErsatz) {
      return 'Keine Leistungsdaten für ${_abteilungsName(m.abteilung)} — '
          'gerechnet mit $basis';
    }
    return 'Gerechnet mit $basis';
  }

  /// Abteilungen, die für die gewählte Menge über die 9-Stunden-Kapazität
  /// laufen würden — als ehrlicher Hinweis unter der Vorschau.
  List<({String name, double stunden})> get _ueberlaufAbteilungen {
    final menge = _fertigAusZeit;
    if (menge == null) return const [];
    final treffer = <({String name, double stunden})>[];
    for (final m in _dauerModelle) {
      if (m.abteilung == _zeitAbteilung) continue;
      final minuten = m.fix + m.proKg * menge;
      if (minuten > kStandardKapazitaetMinuten) {
        treffer.add((name: _abteilungsName(m.abteilung), stunden: minuten / 60));
      }
    }
    return treffer;
  }

  static String _abteilungsName(String dbValue) {
    try {
      return Abteilung.fromDbValue(dbValue).anzeigeName;
    } catch (_) {
      return dbValue;
    }
  }

  /// Gewünschte Produktionsdauer in MINUTEN (aus der Stunden/Minuten-
  /// Eingabe). Bewusst getrennt vom Mengenfeld — Zeit ist keine Menge.
  double? _zeitMinuten;

  // -- Mengen ---------------------------------------------------------------
  // Geplant wird IMMER mit der Fertigmenge: [berechneSchrittPlan] rechnet
  // daraus über die Ausbeute die Rohware zurück. Rohware- und Zeiteingabe
  // werden deshalb erst in Fertigware umgerechnet — mit derselben Ausbeute,
  // die auch der Plan nimmt. Früher ging die Rohware direkt in den Plan
  // und wurde dort als Fertigware behandelt: Der Verlust kam ein zweites
  // Mal obendrauf, und der Plan war um genau diesen Faktor zu groß.

  /// Von Hand eingetragener Verlust als Ausbeute (0…1), oder null.
  double? get _ersatzAusbeute {
    final p = double.tryParse(
      _verlustProzent.text.trim().replaceAll(',', '.'),
    );
    if (p == null || p <= 0 || p >= 100) return null;
    return 1 - p / 100;
  }

  /// Muss der Verlust von Hand eingetragen werden? Nur, solange die
  /// erfassten Produktionen keine Ausbeute liefern.
  bool get _verlustAbfragen {
    final q = _ausbeute?.quelle;
    return q == AusbeuteQuelle.keine || q == AusbeuteQuelle.eingabe;
  }

  /// Die Ausbeute, mit der gerechnet wird. Liefern die erfassten
  /// Produktionen keine, gilt sofort der von Hand eingetragene Verlust —
  /// ohne auf das Nachladen zu warten.
  Ausbeute get _effektiveAusbeute {
    final a = _ausbeute ?? Ausbeute.unbekannt;
    if (!_verlustAbfragen) return a;
    final e = _ersatzAusbeute;
    return e == null
        ? Ausbeute.unbekannt
        : Ausbeute(faktor: e, quelle: AusbeuteQuelle.eingabe);
  }

  /// Eingegebene Menge in kg (Rohware oder Fertigware, je nach Einheit).
  double? get _eingabeKg {
    final v = double.tryParse(_menge.text.trim().replaceAll(',', '.'));
    return (v != null && v.isFinite && v > 0) ? v : null;
  }

  /// Aus der eingegebenen Dauer die FERTIGMENGE, die in dieser Zeit an der
  /// gewählten Abteilung entsteht.
  double? get _fertigAusZeit {
    if (_einheit != _MengenEinheit.stunden) return null;
    final dauer = _zeitMinuten;
    final modell = _bezugsModell;
    if (dauer == null || dauer <= 0 || modell == null) return null;
    final menge = (dauer - modell.fix) / modell.proKg;
    // Zeit reicht nicht einmal für die Rüst-/Fixzeit der Abteilung.
    return menge > 0 ? menge : null;
  }

  /// Die Fertigmenge, mit der geplant wird.
  double? get _planFertig {
    switch (_einheit) {
      case _MengenEinheit.fertigware:
        return _eingabeKg;
      case _MengenEinheit.rohware:
        final roh = _eingabeKg;
        return roh == null ? null : _effektiveAusbeute.fertigAusRoh(roh);
      case _MengenEinheit.stunden:
        return _fertigAusZeit;
    }
  }

  /// Die Rohware dazu — dieselbe Zahl, die der Plan ergibt.
  double? get _planRoh {
    final fertig = _planFertig;
    return fertig == null ? null : _effektiveAusbeute.rohAusFertig(fertig);
  }

  /// Ist die Fertigmenge wirklich bekannt? Bei Rohware- und Zeiteingabe
  /// nur mit einer Ausbeute; ohne sie rechnet die App ohne Verlust, und
  /// die Fertigmenge wäre geraten.
  bool get _fertigBekannt =>
      _einheit == _MengenEinheit.fertigware || _effektiveAusbeute.bekannt;

  @override
  void dispose() {
    _suche.dispose();
    _menge.dispose();
    _verlustProzent.dispose();
    super.dispose();
  }

  // -- Stufe 1 → 2: Plan berechnen ----------------------------------------
  Future<void> _weiter() async {
    final produkt = _gewaehlt;
    if (produkt == null) return;
    final fertig = _planFertig;
    if (fertig == null || fertig <= 0) {
      final hinweis = _einheit == _MengenEinheit.stunden
          ? (_dauerModelle.isEmpty
              ? 'Für dieses Produkt lässt sich aus der Zeit keine Menge '
                  'ableiten — es gibt weder mengenabhängige Leistungsdaten '
                  'noch erfasste Produktionen mit Zeit.'
              : 'Bitte eine gültige Produktionszeit eingeben.')
          : 'Bitte eine gültige Menge (kg) eingeben.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(hinweis)),
      );
      return;
    }

    setState(() => _busy = true);
    final db = ref.read(databaseProvider);
    final fertigBekannt = _fertigBekannt;

    final GeplanterPlan plan;
    try {
      plan = await berechneSchrittPlan(
        db: db,
        productId: produkt.id,
        mengeKg: fertig,
        startTag: _startTag,
        ausbeuteErsatz: _ersatzAusbeute,
      );
    } catch (e) {
      // Ohne diesen Zweig bliebe _busy auf true stehen: Das Sheet hinge
      // im Spinner fest, ohne dass der Nutzer erfährt, was schiefging.
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Plan konnte nicht berechnet werden: $e'),
          duration: const Duration(seconds: 6),
        ),
      );
      return;
    }

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
      _planRohKg = plan.rohwareKg;
      _planFertigKg = plan.fertigwareKg;
      _planFertigBekannt = fertigBekannt;
      _stufe = _PlanStufe.tage;
      _busy = false;
    });
  }

  // -- Stufe 2: Tasks anlegen --------------------------------------------
  /// Die Schritte, die angelegt werden — ohne die abgewählten.
  List<GeplanterSchritt> get _ausgewaehlt => [
        for (final s in _plan)
          if (!_abgewaehlt.contains(s.stepId)) s,
      ];

  Future<void> _anlegen() async {
    final produkt = _gewaehlt;
    if (produkt == null) return;
    // Abgewählte Abteilungen fehlen in der Kette: Der erste ausgewählte
    // Schritt wird ihre Wurzel und trägt Bedarf, Fertigmenge und
    // Auftragszeilen, die übrigen hängen sich in Prozessreihenfolge an.
    final schritte = _ausgewaehlt;
    if (schritte.isEmpty) return;
    final ohne = [
      for (final s in _plan)
        if (_abgewaehlt.contains(s.stepId))
          s.abteilung?.anzeigeName ?? s.abteilungDbValue,
    ];

    setState(() => _busy = true);
    final db = ref.read(databaseProvider);
    // Gegen den Bedarf zählt die Fertigmenge — aber nur, wenn sie bekannt
    // ist. Bei Rohware- oder Zeiteingabe ohne Ausbeute bleibt sie 0, dann
    // wird nichts vom Bedarf abgezogen.
    final fertigMenge = _planFertigBekannt ? _planFertigKg : 0.0;
    final bedarf = _bedarf?.bedarf;
    try {
      // Ein Planungsauftrag aus dem Auftragsbestand gibt seine Zeilen an
      // die Kette weiter — dort stehen sie dann als „geplant am …".
      final bezuege = bedarf == null
          ? const <AuftragsBezug>[]
          : await bezuegeFuerNeueProduktion(db, bedarf, fertigMenge);
      await erstelleTasksAusPlan(
        db: db,
        productId: produkt.id,
        schritte: schritte,
        bedarfId: bedarf?.id,
        fertigMengeKg: fertigMenge,
        auftragsBezuege: bezuege,
      );
    } catch (e) {
      // Die Kette wird transaktional angelegt — ein Fehler bedeutet also,
      // dass NICHTS geschrieben wurde. Genau das muss der Nutzer erfahren,
      // sonst glaubt er, die Planung stünde, und sie fehlt still.
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Einplanen fehlgeschlagen — es wurde nichts gespeichert. '
            'Bitte erneut versuchen. ($e)',
          ),
          duration: const Duration(seconds: 8),
        ),
      );
      return;
    }

    ref
        .read(autoBackupTriggerProvider)
        .fireDebounced(reason: 'Produkt geplant');
    ref.invalidate(bedarfProvider);

    if (!mounted) return;
    final mengen = _planFertigBekannt
        ? 'Rohware ${_fmtKg(_planRohKg)} kg → '
            'Fertigware ${_fmtKg(_planFertigKg)} kg'
        : 'Rohware ${_fmtKg(_planRohKg)} kg';
    final zusatz = ohne.isEmpty ? '' : ' · ohne ${ohne.join(', ')}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Eingeplant · $mengen$zusatz'),
        duration: const Duration(seconds: 3),
      ),
    );
    Navigator.of(context).pop(true);
  }

  void _schiebeTag(GeplanterSchritt s, int deltaTage) {
    // Über die Tageszahl, nicht per Duration — sonst bleibt ein Schritt am
    // Wochenende der Zeitumstellung auf dem Sonntag hängen.
    setState(
      () => s.tag = DateTime(s.tag.year, s.tag.month, s.tag.day + deltaTage),
    );
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
    final grundlage = _grundlageHinweis;
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
            if (info == null || _bedarf?.bedarf.id == info.bedarf.id) {
              setState(() => _bedarf = null);
              return;
            }
            final p = _produkte
                .where((x) => x.id == info.bedarf.productId)
                .firstOrNull;
            setState(() {
              _bedarf = info;
              // Ein Bedarf ist Fertigware. Bliebe die Einheit auf Rohware,
              // würde die Bedarfsmenge als Rohware verplant — es käme um
              // den Verlust zu wenig heraus, und gegen den Bedarf zählte
              // nichts.
              _einheit = _MengenEinheit.fertigware;
              _menge.text = info.offenKg.round().toString();
            });
            if (p != null && p.id != _gewaehlt?.id) _waehleProdukt(p);
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
                        onTap: () => _waehleProdukt(p),
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
                onPressed: _produktAbwaehlen,
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
          if (_einheit == _MengenEinheit.stunden)
            ZeitEingabe(
              label: 'Produktionszeit',
              minuten: _zeitMinuten,
              onChanged: (m) => setState(() => _zeitMinuten = m),
            )
          else
            TextField(
              controller: _menge,
              decoration: InputDecoration(
                labelText: _einheit == _MengenEinheit.rohware
                    ? 'Menge Rohware (kg)'
                    : 'Menge Fertigware (kg)',
                suffixText: 'kg',
                border: const OutlineInputBorder(),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
            ),

          // Zeit-Eingabe: Worauf sich die Zeit bezieht. Ohne diese Wahl wäre
          // unklar, welche Abteilung gemeint ist — die übrigen werden aus
          // der Menge hochgerechnet.
          if (_einheit == _MengenEinheit.stunden) ...[
            if (_ausbeute != null && _dauerModelle.isEmpty) ...[
              const SizedBox(height: 10),
              const _RohwareHinweis(
                text: 'Für dieses Produkt gibt es weder mengenabhängige '
                    'Leistungsdaten noch erfasste Produktionen mit Zeit — aus '
                    'der Zeit lässt sich noch keine Menge ableiten.',
              ),
            ] else if (_dauerModelle.isNotEmpty) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                // Der Schlüssel baut das Feld neu, wenn die App die
                // Abteilung selbst setzt — `initialValue` allein zöge nur
                // beim ersten Aufbau.
                key: ValueKey(_zeitAbteilung),
                initialValue: _zeitAbteilung,
                decoration: const InputDecoration(
                  labelText: 'Zeit gilt für',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final m in _dauerModelle)
                    DropdownMenuItem(
                      value: m.abteilung,
                      child: Text(_abteilungsName(m.abteilung)),
                    ),
                ],
                onChanged: (v) => setState(() => _zeitAbteilung = v),
              ),
              // Ohne gepflegte Leistungsdaten: sagen, womit gerechnet wird.
              if (grundlage != null) ...[
                const SizedBox(height: 8),
                _RohwareHinweis(text: grundlage),
              ],
            ],
          ],

          // Rohware ↔ Fertigware — mit derselben Ausbeute, mit der gleich
          // auch der Plan rechnet.
          ..._umrechnungsHinweise(),
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

  /// Was aus der Eingabe wird — Rohware, Fertigware und die Ausbeute
  /// dazwischen samt Herkunft. Kennt der Artikel keine Ausbeute, wird hier
  /// der Verlust abgefragt.
  List<Widget> _umrechnungsHinweise() {
    // Solange die Ausbeute lädt, lieber nichts als eine falsche Zahl.
    if (_ausbeute == null) return const [];
    final a = _effektiveAusbeute;
    final mengen = _mengenHinweis(a);

    return [
      if (mengen != null) ...[
        const SizedBox(height: 10),
        _RohwareHinweis(text: mengen),
      ],
      // Ehrlicher Hinweis, wenn eine andere Abteilung für die Menge über
      // ihre 9 Stunden laufen müsste.
      for (final u in _ueberlaufAbteilungen) ...[
        const SizedBox(height: 6),
        _RohwareHinweis(
          text: 'Achtung: ${u.name} bräuchte dafür '
              '${Zeit.kurz(u.stunden * 60)} — mehr als die '
              '9 Stunden eines Tages.',
        ),
      ],
      const SizedBox(height: 8),
      if (_verlustAbfragen)
        TextField(
          controller: _verlustProzent,
          decoration: const InputDecoration(
            labelText: 'Verlust (%) — noch keine Produktion mit '
                'Fertigware erfasst',
            suffixText: '%',
            border: OutlineInputBorder(),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) {
            setState(() {});
            // Das Zeitmodell hängt an der Ausbeute — neu rechnen.
            final p = _gewaehlt;
            if (p != null) _ladeArtikeldaten(p.id);
          },
        )
      else
        Text(
          _ausbeuteText(a),
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
    ];
  }

  /// Die umgerechnete Menge zur Eingabe, oder null ohne gültige Eingabe.
  String? _mengenHinweis(Ausbeute a) {
    final roh = _planRoh;
    final fertig = _planFertig;
    if (roh == null || fertig == null) return null;
    if (!a.bekannt) {
      switch (_einheit) {
        case _MengenEinheit.rohware:
          return 'Fertigmenge unbekannt — ohne Ausbeute rechnet die App '
              'ohne Verlust';
        case _MengenEinheit.fertigware:
          return 'Ohne Ausbeute rechnet die App ohne Verlust: Rohware = '
              'Fertigware';
        case _MengenEinheit.stunden:
          return 'Schaffbar: ≈ ${_fmtKg(roh)} kg — Fertigmenge unbekannt, '
              'ohne Ausbeute rechnet die App ohne Verlust';
      }
    }
    switch (_einheit) {
      case _MengenEinheit.rohware:
        return 'Ergibt ≈ ${_fmtKg(fertig)} kg Fertigware';
      case _MengenEinheit.fertigware:
        return 'Braucht ≈ ${_fmtKg(roh)} kg Rohware';
      case _MengenEinheit.stunden:
        return 'Schaffbar: ≈ ${_fmtKg(roh)} kg Rohware → '
            '≈ ${_fmtKg(fertig)} kg Fertigware';
    }
  }

  // -- Stufe 2: Tag je Schritt zuweisen ----------------------------------
  Widget _buildTage(ScrollController sc) {
    final colors = Theme.of(context).colorScheme;
    final anzahl = _ausgewaehlt.length;
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
          'Starttag — schieb einzelne Schritte nach Bedarf. Ohne Haken kommt '
          'eine Abteilung diesmal nicht ins Board.',
          style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
        ),
        if (_planRohKg > 0) ...[
          const SizedBox(height: 8),
          Text(
            _planFertigBekannt
                ? 'Rohware ${_fmtKg(_planRohKg)} kg → Fertigware '
                    '${_fmtKg(_planFertigKg)} kg'
                : 'Rohware ${_fmtKg(_planRohKg)} kg · Fertigmenge unbekannt '
                    '(keine Ausbeute)',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 12),
        for (final s in _plan)
          _SchrittTagKarte(
            schritt: s,
            tagLabel: _fmtTag(s.tag),
            dauerLabel: _fmtStunden(s.dauerMinuten),
            ausgewaehlt: !_abgewaehlt.contains(s.stepId),
            onAuswahl: (an) => setState(() {
              if (an) {
                _abgewaehlt.remove(s.stepId);
              } else {
                _abgewaehlt.add(s.stepId);
              }
            }),
            onMinus: () => _schiebeTag(s, -1),
            onPlus: () => _schiebeTag(s, 1),
            onPick: () => _waehleTag(s),
          ),
        if (anzahl == 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Mindestens eine Abteilung auswählen.',
              style: TextStyle(fontSize: 12, color: colors.error),
            ),
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
                onPressed: _busy || anzahl == 0 ? null : _anlegen,
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
                label: Text(
                  _busy
                      ? 'Wird angelegt …'
                      : anzahl < _plan.length
                          ? 'Tasks anlegen ($anzahl von ${_plan.length})'
                          : 'Tasks anlegen',
                ),
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
    required this.ausgewaehlt,
    required this.onAuswahl,
    required this.onMinus,
    required this.onPlus,
    required this.onPick,
  });

  final GeplanterSchritt schritt;
  final String tagLabel;
  final String dauerLabel;

  /// Ob die Abteilung diesmal ins Board kommt.
  final bool ausgewaehlt;
  final ValueChanged<bool> onAuswahl;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onPick;

  /// Woher die Dauer stammt — als Hinweis unter der Zeile. null bei
  /// gepflegten Leistungsdaten, da gibt es nichts zu erklären.
  ({String text, Color farbe})? _herkunft() {
    final h = schritt.historie;
    switch (schritt.dauerQuelle) {
      case DauerQuelle.historie:
        if (h == null) return null;
        return (
          text: 'Dauer aus ${h.herkunft} '
              '(≈ ${_fmtKg(h.kgProStunde)} kg/h)',
          farbe: const Color(0xFF2E7D32),
        );
      case DauerQuelle.historieErsatz:
        if (h == null) return null;
        return (
          text: 'Keine Leistungsdaten — Dauer aus ${h.herkunft} '
              '(≈ ${_fmtKg(h.kgProStunde)} kg/h)',
          farbe: const Color(0xFF2E7D32),
        );
      case DauerQuelle.platzhalter:
        return (
          text: 'Zeit ist Platzhalter — im Artikel pflegen',
          farbe: Colors.orange.shade700,
        );
      case DauerQuelle.leistungsdaten:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final abt = schritt.abteilung;
    final farbe = abt?.farbe ?? Colors.grey;
    final herkunft = _herkunft();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Tooltip(
                  message: ausgewaehlt
                      ? 'Diesmal nicht einplanen'
                      : 'Doch einplanen',
                  child: Checkbox(
                    value: ausgewaehlt,
                    onChanged: (v) => onAuswahl(v ?? true),
                  ),
                ),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: ausgewaehlt ? farbe : colors.outline,
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
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: ausgewaehlt ? null : colors.onSurfaceVariant,
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
                  '${_fmtKg(schritt.mengeKg)} kg · $dauerLabel h · '
                  '${schritt.mitarbeiter} P',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: ausgewaehlt ? farbe : colors.onSurfaceVariant,
                    decoration:
                        ausgewaehlt ? null : TextDecoration.lineThrough,
                  ),
                ),
              ],
            ),
            // Abgewählt: kein Tag zu wählen, nur der Hinweis.
            if (!ausgewaehlt)
              Padding(
                padding: const EdgeInsets.only(left: 44, top: 4),
                child: Text(
                  'Kommt diesmal nicht ins Board.',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            if (ausgewaehlt && herkunft != null) ...[
              const SizedBox(height: 4),
              Text(
                herkunft.text,
                style: TextStyle(
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                  color: herkunft.farbe,
                ),
              ),
            ],
            if (ausgewaehlt) ...[
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
        const SizedBox(width: 14),
        const Icon(
          Icons.check_box_rounded,
          size: 13,
          color: _kErledigtFarbe,
        ),
        const SizedBox(width: 4),
        Text(
          'erledigt',
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
          ),
        ),
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
    required this.aufgaben,
    required this.kompakt,
    required this.onAufklappen,
  });

  final WeekBoard board;
  final Abteilung abteilung;
  final List<BoardSpur> spuren;

  /// Sonstige Aufgaben der Woche — zugeklappt nur als Zahl.
  final Map<AufgabenZelle, List<Tagesaufgabe>> aufgaben;
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
                erledigt: spuren.fold<int>(
                  0,
                  (s, spur) =>
                      s +
                      board
                          .cellFor(spur, tag)
                          .tasks
                          .where((t) => t.erledigt != null)
                          .length,
                ),
                aufgaben:
                    aufgaben[(abteilung.dbValue, tag)]?.length ?? 0,
                aufgabenErledigt: aufgaben[(abteilung.dbValue, tag)]
                        ?.where((a) => a.erledigt)
                        .length ??
                    0,
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
    required this.erledigt,
    required this.aufgaben,
    required this.aufgabenErledigt,
    required this.farbe,
    required this.kompakt,
  });

  final DateTime tag;
  final double belegt;
  final double kapazitaet;
  final int auftraege;

  /// Davon erledigt — abgehakt oder Produktion erfasst.
  final int erledigt;

  /// Sonstige Aufgaben der Abteilung an diesem Tag, davon erledigt.
  final int aufgaben;
  final int aufgabenErledigt;
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
    final offeneAufgaben = aufgaben - aufgabenErledigt;
    final aufgabenFarbe = offeneAufgaben == 0
        ? _kErledigtFarbe
        : theme.colorScheme.onSurfaceVariant;

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
      child: auftraege == 0 && aufgaben == 0
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (auftraege > 0) ...[
                  Row(
                    children: [
                      Text(
                        '${_fmtStunden(belegt)} / '
                        '${_fmtStunden(kapazitaet)} h',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.75),
                        ),
                      ),
                      const Spacer(),
                      // Aufträge, davon erledigt: „2/5". Alles erledigt —
                      // dann grün wie die Karten.
                      Tooltip(
                        message: erledigt == 0
                            ? (auftraege == 1
                                ? '1 Auftrag'
                                : '$auftraege Aufträge')
                            : '$erledigt von $auftraege erledigt',
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: erledigt == auftraege
                                ? _kErledigtFarbe.withValues(alpha: 0.28)
                                : farbe.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            erledigt == 0
                                ? '$auftraege'
                                : '$erledigt/$auftraege',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
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
                // Zugeklappt verschwinden die sonstigen Aufgaben nicht
                // spurlos: Ihre Zahl steht in der Summenzeile.
                if (aufgaben > 0) ...[
                  if (auftraege > 0) const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(
                        Icons.checklist_rounded,
                        size: 12,
                        color: aufgabenFarbe,
                      ),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          switch (offeneAufgaben) {
                            0 => 'Aufgaben erledigt',
                            1 => '1 Aufgabe offen',
                            _ => '$offeneAufgaben Aufgaben offen',
                          },
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: aufgabenFarbe,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}

/// Zeigt die offenen Bedarfe im Planen-Dialog — als suchbare Liste.
///
/// Früher war das eine waagerechte Kartenleiste. Das trug, solange eine
/// Handvoll Positionen erfasst war; sobald der Bedarf aus Navision kommt,
/// sind es schnell dreistellige Zahlen — und man scrollt sich zu Tode.
///
/// Deshalb jetzt: dringendste zuerst (überfällig, dann nach Termin), eine
/// Suchzeile darüber und eine kompakte, senkrechte Liste mit fester Höhe.
/// So bleibt der Dialog gleich groß, egal ob zehn oder dreihundert
/// Positionen offen sind.
class _BedarfVorschlaege extends ConsumerStatefulWidget {
  const _BedarfVorschlaege({required this.gewaehlt, required this.onWaehlen});

  final BedarfInfo? gewaehlt;
  final void Function(BedarfInfo?) onWaehlen;

  @override
  ConsumerState<_BedarfVorschlaege> createState() =>
      _BedarfVorschlaegeState();
}

class _BedarfVorschlaegeState extends ConsumerState<_BedarfVorschlaege> {
  final _suche = TextEditingController();

  @override
  void dispose() {
    _suche.dispose();
    super.dispose();
  }

  /// Reihenfolge: überfällig zuerst, dann nach Termin, dann Priorität,
  /// zuletzt alphabetisch. Das ist die Reihenfolge, in der man in der
  /// Produktion tatsächlich abarbeitet.
  List<BedarfInfo> _sortiert(List<BedarfInfo> liste) {
    final kopie = [...liste];
    kopie.sort((a, b) {
      if (a.ueberfaellig != b.ueberfaellig) return a.ueberfaellig ? -1 : 1;
      final ta = a.bedarf.termin;
      final tb = b.bedarf.termin;
      if (ta != null && tb != null && ta != tb) return ta.compareTo(tb);
      if (ta == null && tb != null) return 1;
      if (ta != null && tb == null) return -1;
      if (a.bedarf.prioritaet != b.bedarf.prioritaet) {
        return b.bedarf.prioritaet.compareTo(a.bedarf.prioritaet);
      }
      return a.artikelName.compareTo(b.artikelName);
    });
    return kopie;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final offen = ref.watch(offeneBedarfeProvider).valueOrNull;
    if (offen == null || offen.isEmpty) return const SizedBox.shrink();

    final suchText = _suche.text.trim().toLowerCase();
    final gefiltert = _sortiert(offen).where((i) {
      if (suchText.isEmpty) return true;
      return i.artikelName.toLowerCase().contains(suchText) ||
          i.artikelNummer.toLowerCase().contains(suchText);
    }).toList();

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
              'Offener Bedarf (${offen.length})',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            // Suche erst ab einer Menge einblenden, bei der sie nützt.
            if (offen.length > 6)
              SizedBox(
                width: 210,
                height: 34,
                child: TextField(
                  controller: _suche,
                  style: const TextStyle(fontSize: 12.5),
                  decoration: InputDecoration(
                    hintText: 'Artikel suchen …',
                    prefixIcon: const Icon(Icons.search, size: 16),
                    suffixIcon: _suche.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 15),
                            onPressed: () => setState(_suche.clear),
                          ),
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          constraints: const BoxConstraints(maxHeight: 168),
          decoration: BoxDecoration(
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(3),
          ),
          child: gefiltert.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    'Kein offener Bedarf passt zur Suche.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: gefiltert.length,
                  itemBuilder: (context, i) {
                    final info = gefiltert[i];
                    final aktiv =
                        widget.gewaehlt?.bedarf.id == info.bedarf.id;
                    final farbe = info.ueberfaellig
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary;
                    return InkWell(
                      onTap: () =>
                          widget.onWaehlen(aktiv ? null : info),
                      child: Container(
                        decoration: BoxDecoration(
                          color: aktiv
                              ? farbe.withValues(alpha: 0.12)
                              : null,
                          border: Border(
                            bottom: BorderSide(color: theme.dividerColor),
                            left: BorderSide(
                              color: aktiv ? farbe : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 6,
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 66,
                              child: Text(
                                info.artikelNummer,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                info.artikelName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12.5),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${info.offenKg.round()} kg',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: farbe,
                              ),
                            ),
                            if (info.bedarf.termin != null) ...[
                              const SizedBox(width: 10),
                              SizedBox(
                                width: 52,
                                child: Text(
                                  '${info.bedarf.termin!.day.toString().padLeft(2, '0')}.'
                                  '${info.bedarf.termin!.month.toString().padLeft(2, '0')}.',
                                  textAlign: TextAlign.end,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: info.ueberfaellig
                                        ? FontWeight.w800
                                        : FontWeight.normal,
                                    color: info.ueberfaellig
                                        ? theme.colorScheme.error
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ] else
                              const SizedBox(width: 62),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (gefiltert.length > 5)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${gefiltert.length} Positionen · dringendste zuerst',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
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
