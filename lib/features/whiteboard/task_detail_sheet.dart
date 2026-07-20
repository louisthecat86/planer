import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';
import '../../core/services/produktion_erfassen_service.dart';
import '../board/board_providers.dart';
import 'whiteboard_provider.dart';

/// Öffnet einen Bottom-Sheet-Dialog mit allen Details zum Task.
///
/// Gibt `true` zurück, wenn der Task geändert wurde (→ Board refreshen).
Future<bool> showTaskDetailSheet(
  BuildContext context,
  WidgetRef ref,
  WhiteboardTask wbTask,
) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => UncontrolledProviderScope(
      container: ProviderScope.containerOf(context),
      child: _TaskDetailSheet(wbTask: wbTask),
    ),
  );
  return result ?? false;
}

// ---------------------------------------------------------------------------
// Sheet-Inhalt
// ---------------------------------------------------------------------------

class _TaskDetailSheet extends ConsumerStatefulWidget {
  const _TaskDetailSheet({required this.wbTask});

  final WhiteboardTask wbTask;

  @override
  ConsumerState<_TaskDetailSheet> createState() => _TaskDetailSheetState();
}

class _TaskDetailSheetState extends ConsumerState<_TaskDetailSheet> {
  late final TextEditingController _mengeController;
  late final TextEditingController _dauerController;
  late final TextEditingController _mitarbeiterController;
  late final TextEditingController _startZeitController;
  late final TextEditingController _notizenController;

  ProductStep? _step; // Zugehöriger ProductStep für Skalierung.
  bool _isDirty = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final t = widget.wbTask.task;
    _mengeController =
        TextEditingController(text: t.mengeKg.toStringAsFixed(1));
    _dauerController =
        TextEditingController(text: t.geplanteDauerMinuten.toStringAsFixed(0));
    _mitarbeiterController =
        TextEditingController(text: t.geplanteMitarbeiter.toString());
    _startZeitController = TextEditingController(text: t.startZeit ?? '');
    _notizenController = TextEditingController(text: t.notizen ?? '');

    _loadProductStep();
  }

  Future<void> _loadProductStep() async {
    final db = ref.read(databaseProvider);
    final steps = await (db.select(db.productSteps)
          ..where((s) => s.productId.equals(widget.wbTask.task.productId))
          ..where((s) => s.abteilung.equals(widget.wbTask.task.abteilung))
          ..where((s) => s.deletedAt.isNull()))
        .get();

    if (steps.isNotEmpty && mounted) {
      setState(() => _step = steps.first);
    }
  }

  /// Berechnet die Dauer basierend auf Menge und historischem ProductStep.
  ///
  /// Formel: fix_zeit + basis_dauer * (neue_menge / basis_menge)
  void _recalcDuration() {
    final step = _step;
    if (step == null) return;

    final newMenge = double.tryParse(
      _mengeController.text.replaceAll(',', '.'),
    );
    if (newMenge == null || newMenge <= 0) return;

    // Ohne Basismenge ist keine Hochrechnung möglich (Division durch 0
    // würde NaN erzeugen). Dauer bleibt dann unverändert; der Nutzer
    // bekommt einen kurzen Hinweis.
    if (step.basisMengeKg <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Hochrechnen nicht möglich: Der Artikel hat keine Basismenge '
            'im ersten Prozessschritt hinterlegt.',
          ),
        ),
      );
      return;
    }

    final fixZeit = step.fixZeitMinuten ?? 0.0;
    final scaledDauer =
        fixZeit + step.basisDauerMinuten * (newMenge / step.basisMengeKg);
    if (!scaledDauer.isFinite) return;

    _dauerController.text = scaledDauer.roundToDouble().toStringAsFixed(0);
    setState(() => _isDirty = true);
  }

  /// Dialog: Auftrag auf 2–5 aufeinanderfolgende Tage verteilen.
  ///
  /// Die Gesamtmenge wird gleichmäßig aufgeteilt; die Dauer je Tag wird —
  /// wenn Basisdaten vorhanden sind — pro Teilmenge hochgerechnet
  /// (fixe Zeit fällt dann an jedem Tag an), sonst schlicht geteilt.
  Future<void> _verteileAufTageDialog() async {
    final task = widget.wbTask.task;
    final gesamtMenge = double.tryParse(
          _mengeController.text.replaceAll(',', '.'),
        ) ??
        task.mengeKg;
    final gesamtDauer =
        double.tryParse(_dauerController.text) ?? task.geplanteDauerMinuten;

    double dauerJeTag(int tage) {
      final teilMenge = gesamtMenge / tage;
      final step = _step;
      if (step != null && step.basisMengeKg > 0) {
        final fix = step.fixZeitMinuten ?? 0.0;
        final d =
            fix + step.basisDauerMinuten * (teilMenge / step.basisMengeKg);
        if (d.isFinite && d > 0) return d;
      }
      return gesamtDauer / tage;
    }

    String fmtTag(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.';

    final tage = await showDialog<int>(
      context: context,
      builder: (ctx) {
        var auswahl = 2;
        return StatefulBuilder(
          builder: (ctx, setState) {
            final teilMenge = gesamtMenge / auswahl;
            final dauer = dauerJeTag(auswahl);
            final tagesliste = List.generate(
              auswahl,
              (i) => fmtTag(task.datum.add(Duration(days: i))),
            ).join(' · ');
            return AlertDialog(
              title: const Text('Auf mehrere Tage verteilen'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Der Auftrag wird in gleich große Teil-Aufträge an '
                    'aufeinanderfolgenden Tagen aufgeteilt.',
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 2, label: Text('2 Tage')),
                      ButtonSegment(value: 3, label: Text('3 Tage')),
                      ButtonSegment(value: 4, label: Text('4 Tage')),
                      ButtonSegment(value: 5, label: Text('5 Tage')),
                    ],
                    selected: {auswahl},
                    onSelectionChanged: (s) =>
                        setState(() => auswahl = s.first),
                    showSelectedIcon: false,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Je Tag: ${teilMenge.toStringAsFixed(0)} kg · '
                    '${dauer.toStringAsFixed(0)} min\n'
                    'Tage: $tagesliste',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(auswahl),
                  child: const Text('Verteilen'),
                ),
              ],
            );
          },
        );
      },
    );

    if (tage == null || tage < 2) return;
    await _verteileAufTage(tage, gesamtMenge, dauerJeTag(tage));
  }

  Future<void> _verteileAufTage(
    int tage,
    double gesamtMenge,
    double dauerJeTag,
  ) async {
    setState(() => _isSaving = true);
    try {
      final db = ref.read(databaseProvider);
      final task = widget.wbTask.task;
      final teilMenge = gesamtMenge / tage;
      final jetzt = DateTime.now();

      // Tag 1: bestehenden Auftrag auf Teilmenge reduzieren
      await (db.update(db.productionTasks)
            ..where((t) => t.id.equals(task.id)))
          .write(
        ProductionTasksCompanion(
          mengeKg: Value(teilMenge),
          geplanteDauerMinuten: Value(dauerJeTag),
          updatedAt: Value(jetzt),
        ),
      );

      // Tag 2..n: neue Teil-Aufträge an den Folgetagen
      for (var i = 1; i < tage; i++) {
        await db.into(db.productionTasks).insert(
              ProductionTasksCompanion(
                id: Value('${task.id}-t${i + 1}-${jetzt.millisecondsSinceEpoch}'),
                productId: Value(task.productId),
                mengeKg: Value(teilMenge),
                datum: Value(task.datum.add(Duration(days: i))),
                abteilung: Value(task.abteilung),
                startZeit: Value(task.startZeit),
                geplanteDauerMinuten: Value(dauerJeTag),
                geplanteMitarbeiter: Value(task.geplanteMitarbeiter),
                sortierung: Value(task.sortierung),
                parentTaskId: Value(task.parentTaskId),
                notizen: Value(task.notizen),
              ),
            );
      }

      ref.read(autoBackupTriggerProvider).fireDebounced(
            reason: 'Auftrag auf $tage Tage verteilt',
          );
      ref.invalidate(dailyTasksProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Auftrag auf $tage Tage verteilt '
              '(je ${(gesamtMenge / tage).toStringAsFixed(0)} kg).',
            ),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Verteilen: $e')),
        );
      }
    }
  }

  /// Hinweistext unter dem Dauerfeld: woher der Wert stammt.
  String? _dauerHinweis() {
    final step = _step;
    if (step == null) return null;
    if (step.basisAnzahlMessungen > 0) {
      return 'Aus ${step.basisAnzahlMessungen} Messungen berechnet';
    }
    if (step.basisMengeKg > 0 && step.basisDauerMinuten > 0) {
      return 'Schätzwert aus Stammdaten — noch keine Messungen erfasst';
    }
    return 'Platzhalter — Stammdaten noch nicht gepflegt';
  }

  /// Öffnet den Dialog zum Abschließen einer Produktion und schreibt die
  /// Ist-Werte in die Excel-Historie (einzige Datenquelle).
  Future<void> _produktionErfassen() async {
    final task = widget.wbTask.task;
    final erfasst = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => _ProduktionErfassenSheet(
        productId: task.productId,
        vorschlagMengeKg: double.tryParse(
              _mengeController.text.replaceAll(',', '.'),
            ) ??
            task.mengeKg,
        vorschlagDatum: task.datum,
        vorschlagStart: _startZeitController.text.trim().isEmpty
            ? null
            : _startZeitController.text.trim(),
      ),
    );
    if (erfasst == true && mounted) {
      // Erfassung floss in die Historie — Board/Schätzungen neu laden.
      ref.invalidate(weekBoardProvider);
      Navigator.of(context).pop();
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final db = ref.read(databaseProvider);
      // double.tryParse akzeptiert auch 'NaN'/'Infinity' — solche Werte
      // dürfen nie in die Datenbank (NOT-NULL-Constraint schlägt fehl,
      // weil NaN als NULL gebunden wird).
      double? sicher(String text) {
        final v = double.tryParse(text.replaceAll(',', '.'));
        return (v != null && v.isFinite && v >= 0) ? v : null;
      }

      final newMenge = sicher(_mengeController.text) ??
          widget.wbTask.task.mengeKg;
      final newDauer = sicher(_dauerController.text) ??
          widget.wbTask.task.geplanteDauerMinuten;
      final newMa = int.tryParse(_mitarbeiterController.text) ??
          widget.wbTask.task.geplanteMitarbeiter;
      final startZeit = _startZeitController.text.trim();
      final notizen = _notizenController.text.trim();

      await (db.update(db.productionTasks)
            ..where((t) => t.id.equals(widget.wbTask.task.id)))
          .write(
        ProductionTasksCompanion(
          mengeKg: Value(newMenge),
          geplanteDauerMinuten: Value(newDauer),
          geplanteMitarbeiter: Value(newMa),
          startZeit: Value(startZeit.isEmpty ? null : startZeit),
          notizen: Value(notizen.isEmpty ? null : notizen),
          updatedAt: Value(DateTime.now()),
        ),
      );

      ref.invalidate(dailyTasksProvider);

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Löscht den Task (Soft-Delete). Fragt, ob nur dieser Schritt oder die
  /// gesamte verkettete Produktion (alle Abteilungs-Schritte) entfernt wird.
  Future<void> _loeschen() async {
    final wahl = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aus der Planung löschen?'),
        content: const Text(
          'Nur diesen einen Schritt (diese Abteilung) entfernen oder die '
          'gesamte Produktion dieses Artikels — also alle verketteten '
          'Abteilungs-Schritte?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('abbrechen'),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('einzel'),
            child: const Text('Nur dieser Schritt'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop('ganze'),
            child: const Text('Ganze Produktion'),
          ),
        ],
      ),
    );
    if (wahl == null || wahl == 'abbrechen') return;

    setState(() => _isSaving = true);
    try {
      final db = ref.read(databaseProvider);
      final jetzt = DateTime.now();
      final ids = wahl == 'ganze'
          ? await _produktionsKettenIds(db, widget.wbTask.task)
          : [widget.wbTask.task.id];

      await (db.update(db.productionTasks)..where((t) => t.id.isIn(ids)))
          .write(
        ProductionTasksCompanion(
          deletedAt: Value(jetzt),
          updatedAt: Value(jetzt),
        ),
      );

      ref
          .read(autoBackupTriggerProvider)
          .fireDebounced(reason: 'Produktion aus Planung gelöscht');
      ref.invalidate(dailyTasksProvider);

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  /// Sammelt alle Task-IDs der verketteten Produktion (über
  /// [ProductionTask.parentTaskId]) zu der [start] gehört. Geht zur Wurzel
  /// hoch und von dort über alle Nachfahren — getrennte Planungen desselben
  /// Produkts bleiben unberührt, weil sie eigene Ketten bilden.
  Future<List<String>> _produktionsKettenIds(
    AppDatabase db,
    ProductionTask start,
  ) async {
    final alle = await (db.select(db.productionTasks)
          ..where((t) => t.productId.equals(start.productId))
          ..where((t) => t.deletedAt.isNull()))
        .get();
    final byId = {for (final t in alle) t.id: t};

    // Zur Wurzel hochlaufen.
    var root = start;
    final besucht = <String>{root.id};
    while (root.parentTaskId != null &&
        byId.containsKey(root.parentTaskId)) {
      final parent = byId[root.parentTaskId]!;
      if (!besucht.add(parent.id)) break; // Zyklus-Schutz
      root = parent;
    }

    // Von der Wurzel alle Nachfahren einsammeln.
    final kette = <String>{root.id};
    var geaendert = true;
    while (geaendert) {
      geaendert = false;
      for (final t in alle) {
        final p = t.parentTaskId;
        if (p != null && kette.contains(p) && kette.add(t.id)) {
          geaendert = true;
        }
      }
    }
    return kette.toList();
  }

  @override
  void dispose() {
    _mengeController.dispose();
    _dauerController.dispose();
    _mitarbeiterController.dispose();
    _startZeitController.dispose();
    _notizenController.dispose();
    super.dispose();
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    final abt = widget.wbTask.abteilungEnum;
    final colors = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
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
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Kopf — Abteilungs-Farbband mit Kurzcode (einheitliche Kartensprache)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: abt.farbe.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: abt.farbe,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        abt.kurzcode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.wbTask.produktName,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${widget.wbTask.artikelnummer} · ${abt.anzeigeName}',
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Menge + automatische Neuberechnung
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _mengeController,
                      decoration: const InputDecoration(
                        labelText: 'Menge (kg)',
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[\d.,]'),
                        ),
                      ],
                      onChanged: (_) {
                        _recalcDuration();
                      },
                    ),
                  ),
                  if (_step != null) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Dauer wird aus ${_step!.basisAnzahlMessungen} '
                          'historischen Messungen berechnet',
                      child: Icon(
                        Icons.auto_fix_high,
                        color: colors.primary,
                        size: 20,
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 14),

              // Dauer — vom System aus der Menge und der Historie berechnet.
              // Mitarbeiter spielen bei der Planung keine Rolle mehr und
              // werden hier nicht mehr abgefragt.
              TextField(
                controller: _dauerController,
                decoration: InputDecoration(
                  labelText: 'Geschätzte Dauer (min)',
                  helperText: _dauerHinweis(),
                  suffixText: _step != null &&
                          (_step!.dauerStdAbweichung ?? 0) > 0
                      ? '± ${(_step!.dauerStdAbweichung ?? 0).toStringAsFixed(0)}'
                      : null,
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                onChanged: (_) => setState(() => _isDirty = true),
              ),

              const SizedBox(height: 14),

              // Startzeit
              TextField(
                controller: _startZeitController,
                decoration: const InputDecoration(
                  labelText: 'Startzeit (HH:MM)',
                  hintText: '08:30',
                ),
                onChanged: (_) => setState(() => _isDirty = true),
              ),

              const SizedBox(height: 14),

              // Notizen
              TextField(
                controller: _notizenController,
                decoration: const InputDecoration(
                  labelText: 'Notizen',
                ),
                maxLines: 3,
                onChanged: (_) => setState(() => _isDirty = true),
              ),

              // Historische Basisdaten (Info-Box)
              if (_step != null) ...[
                const SizedBox(height: 20),
                _HistoryInfoBox(step: _step!),
              ],

              const SizedBox(height: 16),

              // Mehrtägige Prozesse (z.B. Spießen): Auftrag auf
              // aufeinanderfolgende Tage aufteilen.
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isSaving ? null : _verteileAufTageDialog,
                  icon: const Icon(Icons.date_range, size: 18),
                  label: const Text('Auf mehrere Tage verteilen'),
                ),
              ),

              const SizedBox(height: 16),

              // Speichern-Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: _isSaving || !_isDirty ? null : _save,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: Text(_isSaving ? 'Speichern …' : 'Speichern'),
                ),
              ),

              const SizedBox(height: 8),

              // Produktion abschließen: erfasst die Ist-Werte in die
              // Excel-Historie und verbessert damit künftige Schätzungen.
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _isSaving ? null : _produktionErfassen,
                  icon: const Icon(Icons.fact_check_outlined, size: 20),
                  label: const Text('Produktion abschließen & erfassen'),
                ),
              ),

              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: _isSaving ? null : _loeschen,
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  label: const Text(
                    'Aus Planung löschen',
                    style: TextStyle(color: Colors.red),
                  ),
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
// Info-Box: Historische Basisdaten
// ---------------------------------------------------------------------------

class _HistoryInfoBox extends StatelessWidget {
  const _HistoryInfoBox({required this.step});

  final ProductStep step;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final messungen = step.basisAnzahlMessungen;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights, size: 16, color: colors.primary),
              const SizedBox(width: 6),
              Text(
                'Historische Basisdaten',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _infoRow(
            'Basismenge',
            '${step.basisMengeKg.toStringAsFixed(1)} kg',
          ),
          _infoRow(
            'Basisdauer',
            '${step.basisDauerMinuten.toStringAsFixed(0)} min',
          ),
          if (step.fixZeitMinuten != null && step.fixZeitMinuten! > 0)
            _infoRow(
              'Fixe Rüstzeit',
              '${step.fixZeitMinuten!.toStringAsFixed(0)} min',
            ),
          _infoRow(
            'Basismitarbeiter',
            '${step.basisMitarbeiter}',
          ),
          _infoRow(
            'Messungen',
            messungen == 0 ? 'Keine (Schätzwerte)' : '$messungen',
          ),
          if (step.dauerStdAbweichung != null)
            _infoRow(
              'Standardabweichung',
              '± ${step.dauerStdAbweichung!.toStringAsFixed(1)} min',
            ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Dialog zum Abschließen einer Produktion. Erfasst Datum, Roh-/Fertigmenge
/// und Zeiten und schreibt daraus eine Zeile in die Excel-Historie. Die
/// abgeleiteten Kennzahlen (Verlust, kg/h, Produktionszeit) werden live
/// vorgerechnet, damit man vor dem Speichern sieht, was gespeichert wird.
class _ProduktionErfassenSheet extends ConsumerStatefulWidget {
  const _ProduktionErfassenSheet({
    required this.productId,
    required this.vorschlagMengeKg,
    required this.vorschlagDatum,
    this.vorschlagStart,
  });

  final String productId;
  final double vorschlagMengeKg;
  final DateTime vorschlagDatum;
  final String? vorschlagStart;

  @override
  ConsumerState<_ProduktionErfassenSheet> createState() =>
      _ProduktionErfassenSheetState();
}

class _ProduktionErfassenSheetState
    extends ConsumerState<_ProduktionErfassenSheet> {
  late final TextEditingController _roh;
  late final TextEditingController _fertig;
  late final TextEditingController _start;
  late final TextEditingController _ende;
  late final TextEditingController _notizen;
  late DateTime _datum;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Rohmenge als Vorschlag; Fertigmenge trägt der Nutzer nach dem Wiegen ein.
    _roh = TextEditingController(
      text: widget.vorschlagMengeKg.toStringAsFixed(0),
    );
    _fertig = TextEditingController();
    _start = TextEditingController(text: widget.vorschlagStart ?? '');
    _ende = TextEditingController();
    _notizen = TextEditingController();
    _datum = widget.vorschlagDatum;
  }

  @override
  void dispose() {
    _roh.dispose();
    _fertig.dispose();
    _start.dispose();
    _ende.dispose();
    _notizen.dispose();
    super.dispose();
  }

  double? get _rohKg => double.tryParse(_roh.text.replaceAll(',', '.'));
  double? get _fertigKg => double.tryParse(_fertig.text.replaceAll(',', '.'));

  Future<void> _speichern() async {
    final roh = _rohKg;
    final fertig = _fertigKg;
    if (roh == null || roh <= 0 || fertig == null || fertig <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte Roh- und Fertigmenge (kg) eingeben.'),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    final db = ref.read(databaseProvider);
    await ProduktionErfassenService.erfasse(
      db: db,
      productId: widget.productId,
      datum: _datum,
      kgRohware: roh,
      kgFertigware: fertig,
      startzeit: _start.text.trim().isEmpty ? null : _start.text.trim(),
      endzeit: _ende.text.trim().isEmpty ? null : _ende.text.trim(),
      notizen: _notizen.text.trim().isEmpty ? null : _notizen.text.trim(),
    );
    ref
        .read(autoBackupTriggerProvider)
        .fireDebounced(reason: 'Produktion erfasst');
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Live-Kennzahlen
    final roh = _rohKg;
    final fertig = _fertigKg;
    final dauerMin = ProduktionErfassenService.produktionszeitMinuten(
      _start.text.trim(),
      _ende.text.trim(),
    );
    final verlust = (roh != null && roh > 0 && fertig != null)
        ? (1 - fertig / roh)
        : null;
    final std = (dauerMin != null && dauerMin > 0) ? dauerMin / 60 : null;
    final kghRoh = (roh != null && std != null) ? roh / std : null;
    final kghGegart = (fertig != null && std != null) ? fertig / std : null;

    String fmt(double? v, {int dez = 0, String einheit = ''}) =>
        v == null ? '—' : '${v.toStringAsFixed(dez)}$einheit';
    String fmtDauer(double? m) {
      if (m == null) return '—';
      final h = m ~/ 60;
      final r = (m % 60).round();
      return h > 0 ? '$h:${r.toString().padLeft(2, '0')} h' : '$r min';
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(
            'Produktion abschließen',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Die Werte werden in die Historie geschrieben und verbessern '
            'künftige Zeitschätzungen.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),

          // Datum
          OutlinedButton.icon(
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _datum,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 1)),
              );
              if (d != null) setState(() => _datum = d);
            },
            icon: const Icon(Icons.event, size: 18),
            label: Text(
              '${_datum.day.toString().padLeft(2, '0')}.'
              '${_datum.month.toString().padLeft(2, '0')}.${_datum.year}',
            ),
          ),
          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _roh,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Rohware',
                    suffixText: 'kg',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _fertig,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Fertigware',
                    suffixText: 'kg',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _start,
                  decoration: const InputDecoration(
                    labelText: 'Startzeit (HH:MM)',
                    hintText: '08:30',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _ende,
                  decoration: const InputDecoration(
                    labelText: 'Endzeit (HH:MM)',
                    hintText: '12:15',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Live berechnete Kennzahlen
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                _KennzahlZeile(
                  label: 'Produktionszeit',
                  wert: fmtDauer(dauerMin),
                ),
                _KennzahlZeile(
                  label: 'Verlust',
                  wert: verlust == null
                      ? '—'
                      : '${(verlust * 100).toStringAsFixed(1)} %',
                ),
                _KennzahlZeile(
                  label: 'kg/h roh',
                  wert: fmt(kghRoh, einheit: ' kg/h'),
                ),
                _KennzahlZeile(
                  label: 'kg/h gegart',
                  wert: fmt(kghGegart, einheit: ' kg/h'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          TextField(
            controller: _notizen,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Notizen (optional)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _busy ? null : _speichern,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(_busy ? 'Speichern …' : 'In Historie speichern'),
            ),
          ),
        ],
      ),
    );
  }
}

class _KennzahlZeile extends StatelessWidget {
  const _KennzahlZeile({required this.label, required this.wert});

  final String label;
  final String wert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            wert,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
