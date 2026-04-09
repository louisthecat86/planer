import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
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
    builder: (_) => ProviderScope(
      parent: ProviderScope.containerOf(context),
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
  late String _status;

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
    _startZeitController =
        TextEditingController(text: t.startZeit ?? '');
    _notizenController =
        TextEditingController(text: t.notizen ?? '');
    _status = t.status;

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

    final fixZeit = step.fixZeitMinuten ?? 0.0;
    final scaledDauer =
        fixZeit + step.basisDauerMinuten * (newMenge / step.basisMengeKg);

    _dauerController.text = scaledDauer.roundToDouble().toStringAsFixed(0);
    setState(() => _isDirty = true);
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final db = ref.read(databaseProvider);
      final newMenge = double.tryParse(
            _mengeController.text.replaceAll(',', '.'),
          ) ??
          widget.wbTask.task.mengeKg;
      final newDauer = double.tryParse(_dauerController.text) ??
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
          status: Value(_status),
          updatedAt: Value(DateTime.now()),
        ),
      );

      ref.invalidate(weeklyTasksProvider);

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
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Titel
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: abt.farbe,
                    child: Text(
                      abt.kurzcode,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
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
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
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

              const SizedBox(height: 20),

              // Status-Chips
              Text(
                'Status',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final s in const [
                    ('geplant', 'Geplant'),
                    ('in_arbeit', 'In Arbeit'),
                    ('fertig', 'Fertig'),
                    ('storniert', 'Storniert'),
                  ])
                    ChoiceChip(
                      label: Text(s.$2),
                      selected: _status == s.$1,
                      onSelected: (_) => setState(() {
                        _status = s.$1;
                        _isDirty = true;
                      }),
                    ),
                ],
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
                        border: OutlineInputBorder(),
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
                        border: const OutlineInputBorder(),
                        suffixText: _step != null
                            ? '± ${(_step!.dauerStdAbweichung ?? 0).toStringAsFixed(0)}'
                            : null,
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      onChanged: (_) =>
                          setState(() => _isDirty = true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _mitarbeiterController,
                      decoration: const InputDecoration(
                        labelText: 'Mitarbeiter',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      onChanged: (_) =>
                          setState(() => _isDirty = true),
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
                  border: OutlineInputBorder(),
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
                  border: OutlineInputBorder(),
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
                  onPressed: _isSaving ? null : _save,
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
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
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
