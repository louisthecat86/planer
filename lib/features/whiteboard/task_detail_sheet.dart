import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';
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

              // Dauer + Mitarbeiter
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _dauerController,
                      decoration: InputDecoration(
                        labelText: 'Dauer (min)',
                        suffixText: _step != null
                            ? '± ${(_step!.dauerStdAbweichung ?? 0).toStringAsFixed(0)}'
                            : null,
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      onChanged: (_) => setState(() => _isDirty = true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _mitarbeiterController,
                      decoration: const InputDecoration(
                        labelText: 'Mitarbeiter',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      onChanged: (_) => setState(() => _isDirty = true),
                    ),
                  ),
                ],
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

              const SizedBox(height: 24),

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