import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/constants/machines.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import 'machine_settings_editor.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Lädt ein Produkt per ID.
final productProvider =
    FutureProvider.family<Product?, String>((ref, productId) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.products)
        ..where((p) => p.id.equals(productId))
        ..where((p) => p.deletedAt.isNull()))
      .getSingleOrNull();
});

/// Lädt alle Schritte eines Produkts, sortiert nach Reihenfolge.
final productStepsProvider =
    FutureProvider.family<List<ProductStep>, String>((ref, productId) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.productSteps)
        ..where((s) => s.productId.equals(productId))
        ..where((s) => s.deletedAt.isNull())
        ..orderBy([(s) => OrderingTerm.asc(s.reihenfolge)]))
      .get();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class ArticleDetailScreen extends ConsumerWidget {
  const ArticleDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productAsync = ref.watch(productProvider(productId));
    final stepsAsync = ref.watch(productStepsProvider(productId));

    return Scaffold(
      appBar: AppBar(
        title: productAsync.when(
          data: (p) => Text(p?.artikelbezeichnung ?? 'Artikel'),
          loading: () => const Text('Artikel'),
          error: (_, __) => const Text('Fehler'),
        ),
        actions: [
          productAsync.maybeWhen(
            data: (p) => p != null
                ? Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Chip(
                      label: Text(p.artikelnummer),
                      avatar: const Icon(Icons.tag, size: 16),
                    ),
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: stepsAsync.when(
        data: (steps) => _StepsList(
          productId: productId,
          steps: steps,
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Schritte-Liste
// ---------------------------------------------------------------------------

class _StepsList extends ConsumerWidget {
  const _StepsList({required this.productId, required this.steps});

  final String productId;
  final List<ProductStep> steps;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (steps.isEmpty) {
      return const Center(
        child: Text('Keine Produktionsschritte vorhanden.'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: steps.length,
      itemBuilder: (context, index) {
        final step = steps[index];
        return _StepCard(
          step: step,
          stepNumber: index + 1,
          onUpdated: () => ref.invalidate(productStepsProvider(productId)),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Einzelne Schritt-Karte
// ---------------------------------------------------------------------------

class _StepCard extends ConsumerStatefulWidget {
  const _StepCard({
    required this.step,
    required this.stepNumber,
    required this.onUpdated,
  });

  final ProductStep step;
  final int stepNumber;
  final VoidCallback onUpdated;

  @override
  ConsumerState<_StepCard> createState() => _StepCardState();
}

class _StepCardState extends ConsumerState<_StepCard> {
  bool _expanded = false;

  Abteilung? get _abteilung {
    try {
      return Abteilung.fromDbValue(widget.step.abteilung);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveMachineSettings(String json) async {
    final db = ref.read(databaseProvider);
    await (db.update(db.productSteps)
          ..where((s) => s.id.equals(widget.step.id)))
        .write(ProductStepsCompanion(
      maschinenEinstellungenJson: Value(json),
      updatedAt: Value(DateTime.now()),
    ),);
    widget.onUpdated();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final abt = _abteilung;
    final color = abt != null ? Color(abt.farbwert) : Colors.grey;
    final enabledCount = enabledMachines(widget.step.maschinenEinstellungenJson).length;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _expanded ? color : color.withValues(alpha: 0.3),
          width: _expanded ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Schrittnummer
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${widget.stepNumber}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Abteilungsname + Infos
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          abt?.anzeigeName ?? widget.step.abteilung,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        _StepInfoRow(step: widget.step),
                      ],
                    ),
                  ),

                  // Maschinen-Badge
                  if (enabledCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Chip(
                        label: Text('$enabledCount'),
                        avatar: const Icon(Icons.settings, size: 16),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),

                  // Expand Arrow
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                  ),
                ],
              ),
            ),
          ),

          // Expanded Content
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Basis-Daten
                  _DetailGrid(step: widget.step),
                  const SizedBox(height: 16),

                  // Maschinen-Editor
                  Text(
                    'Maschinen & Einstellungen',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  MachineSettingsEditor(
                    abteilungDbValue: widget.step.abteilung,
                    initialJson: widget.step.maschinenEinstellungenJson,
                    onChanged: _saveMachineSettings,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Info-Zeile unter dem Schrittnamen
// ---------------------------------------------------------------------------

class _StepInfoRow extends StatelessWidget {
  const _StepInfoRow({required this.step});

  final ProductStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = <String>[];

    parts.add('${step.basisDauerMinuten.round()} min / ${step.basisMengeKg.round()} kg');

    if (step.ausbeuteFaktor != null) {
      final verlust = ((1 - step.ausbeuteFaktor!) * 100).round();
      parts.add('−$verlust% Verlust');
    }
    if (step.maxChargenKg != null) {
      parts.add('max ${step.maxChargenKg!.round()} kg/Charge');
    }
    if (step.wartezeitMinuten != null && step.wartezeitMinuten! > 0) {
      parts.add('${step.wartezeitMinuten!.round()} min Wartezeit');
    }

    final machines = enabledMachines(step.maschinenEinstellungenJson);
    if (machines.isNotEmpty) {
      parts.add(machines.map((m) => m.label).join(', '));
    }

    return Text(
      parts.join('  ·  '),
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

// ---------------------------------------------------------------------------
// Detail-Grid: Basis-Daten des Schritts
// ---------------------------------------------------------------------------

class _DetailGrid extends StatelessWidget {
  const _DetailGrid({required this.step});

  final ProductStep step;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 24,
      runSpacing: 8,
      children: [
        _InfoChip(label: 'Basismenge', value: '${step.basisMengeKg} kg'),
        _InfoChip(label: 'Basisdauer', value: '${step.basisDauerMinuten} min'),
        if (step.fixZeitMinuten != null && step.fixZeitMinuten! > 0)
          _InfoChip(label: 'Fixzeit', value: '${step.fixZeitMinuten} min'),
        _InfoChip(
          label: 'Mitarbeiter',
          value: '${step.basisMitarbeiter}',
        ),
        if (step.ausbeuteFaktor != null)
          _InfoChip(
            label: 'Ausbeute',
            value: '${(step.ausbeuteFaktor! * 100).round()}%',
          ),
        if (step.maxChargenKg != null)
          _InfoChip(
            label: 'Max. Charge',
            value: '${step.maxChargenKg} kg',
          ),
        if (step.minChargenKg != null)
          _InfoChip(
            label: 'Min. Charge',
            value: '${step.minChargenKg} kg',
          ),
        if (step.wartezeitMinuten != null && step.wartezeitMinuten! > 0)
          _InfoChip(
            label: 'Wartezeit',
            value: '${step.wartezeitMinuten} min',
          ),
        if (step.kerntemperaturZiel != null)
          _InfoChip(
            label: 'Kerntemp.',
            value: '${step.kerntemperaturZiel}°C',
          ),
        if (step.raumtemperaturMax != null)
          _InfoChip(
            label: 'Max. Raumtemp.',
            value: '${step.raumtemperaturMax}°C',
          ),
        if (step.maschine != null && step.maschine!.isNotEmpty)
          _InfoChip(label: 'Maschine', value: step.maschine!),
        _InfoChip(
          label: 'Messungen',
          value: '${step.basisAnzahlMessungen}',
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
