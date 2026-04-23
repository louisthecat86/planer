import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import 'step_editor_dialog.dart';

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

/// Lädt alle Parameter eines Schritts, sortiert nach Reihenfolge.
/// Wird beim Expand eines Schritts gelazy ausgewertet.
final stepParametersProvider =
    FutureProvider.family<List<ProductStepParameter>, String>(
        (ref, stepId) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.productStepParameters)
        ..where((p) => p.stepId.equals(stepId))
        ..where((p) => p.deletedAt.isNull())
        ..orderBy([(p) => OrderingTerm.asc(p.reihenfolge)]))
      .get();
});

/// Lädt eine Maschine per ID. Für die Anzeige des Anlagen-Namens
/// in der Schritt-Karte.
final machineProvider =
    FutureProvider.family<Machine?, String>((ref, machineId) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.machines)
        ..where((m) => m.id.equals(machineId))
        ..where((m) => m.deletedAt.isNull()))
      .getSingleOrNull();
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
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Keine Produktionsschritte vorhanden.\n\n'
            'Importiere eine Excel-Vorlage oder füge Schritte '
            'manuell hinzu (kommt in Phase C).',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
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

  Future<void> _openEditor() async {
    final geaendert = await StepEditorDialog.show(
      context,
      step: widget.step,
      stepNumber: widget.stepNumber,
    );
    if (geaendert) {
      widget.onUpdated();
      // Parameter-Provider ist pro step.id scoped — der Schritt selbst
      // bleibt, Parameter ändern wir in Phase A nicht → kein Invalidate nötig.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final abt = _abteilung;
    final color = abt != null ? abt.farbe : Colors.grey;

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
                        if (widget.step.prozessschritt != null &&
                            widget.step.prozessschritt!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.step.prozessschritt!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        _StepInfoRow(step: widget.step),
                      ],
                    ),
                  ),

                  // Bearbeiten-Button
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    tooltip: 'Schritt bearbeiten',
                    onPressed: _openEditor,
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
                  // Anlagen-Info
                  _MaschineInfoRow(step: widget.step),
                  const SizedBox(height: 12),

                  // Parameter (readonly in Phase A)
                  _ParameterListe(stepId: widget.step.id),
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
// Info-Zeile: Personen, Menge, Dauer
// ---------------------------------------------------------------------------

class _StepInfoRow extends StatelessWidget {
  const _StepInfoRow({required this.step});

  final ProductStep step;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];

    if (step.basisMitarbeiter > 0) {
      items.add(_Chip(
        icon: Icons.person,
        label: '${step.basisMitarbeiter}',
      ));
    }
    if (step.basisMengeKg > 0) {
      items.add(_Chip(
        icon: Icons.scale,
        label: '${_formatZahl(step.basisMengeKg)} kg',
      ));
    }
    if (step.basisDauerMinuten > 0) {
      items.add(_Chip(
        icon: Icons.schedule,
        label: _formatDauer(step.basisDauerMinuten),
      ));
    }

    if (items.isEmpty) {
      return Text(
        'Zeiten nicht gepflegt — auf Bearbeiten tippen',
        style: TextStyle(
          fontSize: 12,
          color: Colors.orange.shade700,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: items,
    );
  }

  static String _formatZahl(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  static String _formatDauer(double minuten) {
    if (minuten < 60) return '${minuten.toInt()} min';
    final h = (minuten / 60).floor();
    final m = (minuten % 60).round();
    if (m == 0) return '${h}h';
    return '${h}h ${m}min';
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Anlagen-Info im Expanded-Bereich
// ---------------------------------------------------------------------------

class _MaschineInfoRow extends ConsumerWidget {
  const _MaschineInfoRow({required this.step});

  final ProductStep step;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // Neue v3-Referenz zuerst
    if (step.maschineId != null) {
      final maschineAsync = ref.watch(machineProvider(step.maschineId!));
      return maschineAsync.when(
        data: (m) => Row(
          children: [
            Icon(Icons.factory, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'Anlage: ',
              style: theme.textTheme.bodySmall,
            ),
            Text(
              m?.name ?? step.maschine ?? '—',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        loading: () => const SizedBox(height: 18),
        error: (_, __) => const SizedBox.shrink(),
      );
    }

    // Legacy-Feld als Fallback
    if (step.maschine != null && step.maschine!.isNotEmpty) {
      return Row(
        children: [
          Icon(Icons.factory, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text('Anlage: ', style: theme.textTheme.bodySmall),
          Text(
            step.maschine!,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    return Text(
      'Keine Anlage zugeordnet',
      style: theme.textTheme.bodySmall?.copyWith(
        fontStyle: FontStyle.italic,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Parameter-Liste (readonly in Phase A)
// ---------------------------------------------------------------------------

class _ParameterListe extends ConsumerWidget {
  const _ParameterListe({required this.stepId});

  final String stepId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final paramsAsync = ref.watch(stepParametersProvider(stepId));

    return paramsAsync.when(
      data: (params) {
        if (params.isEmpty) {
          return Text(
            'Keine Parameter hinterlegt.',
            style: theme.textTheme.bodySmall?.copyWith(
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          );
        }

        // Nach Gruppen sortieren
        final byGruppe = <String, List<ProductStepParameter>>{};
        for (final p in params) {
          byGruppe.putIfAbsent(p.parameterGruppe, () => []).add(p);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.tune,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Parameter',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '(Bearbeiten: Phase B)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final entry in byGruppe.entries) ...[
              _GruppenBlock(
                gruppenName: entry.key,
                parameter: entry.value,
              ),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
      loading: () => const SizedBox(
        height: 30,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => Text(
        'Parameter-Fehler: $e',
        style: const TextStyle(color: Colors.red, fontSize: 12),
      ),
    );
  }
}

class _GruppenBlock extends StatelessWidget {
  const _GruppenBlock({
    required this.gruppenName,
    required this.parameter,
  });

  final String gruppenName;
  final List<ProductStepParameter> parameter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final istCustom = gruppenName == 'CUSTOM';
    final anzeigename = istCustom ? 'Zusätzliche Parameter' : gruppenName;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: istCustom
            ? Colors.amber.withValues(alpha: 0.08)
            : theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            anzeigename,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 6),
          ...parameter.map((p) => _ParameterZeile(param: p)),
        ],
      ),
    );
  }
}

class _ParameterZeile extends StatelessWidget {
  const _ParameterZeile({required this.param});

  final ProductStepParameter param;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              param.parameterName,
              style: theme.textTheme.bodySmall,
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              param.wert ?? '—',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}