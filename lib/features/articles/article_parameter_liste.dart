part of 'article_detail_screen.dart';

// ---------------------------------------------------------------------------
// Plattentemperatur-Schema-Bereich (Typ-Auswahl + Schema, speichert als
// benannte Parameter „Platte Oben/Unten N")
// ---------------------------------------------------------------------------

class _PlattenSchemaBereich extends ConsumerWidget {
  const _PlattenSchemaBereich({
    required this.step,
    required this.maschineName,
    required this.onUpdated,
  });

  final ProductStep step;
  final String maschineName;
  final VoidCallback onUpdated;

  /// Jede Maschine zeigt NUR ihr eigenes Raster: die Bratstraße die
  /// 10+10 Platten, der Dampftunnel/Heißluftofen seine 12. Nutzt bewusst
  /// dieselbe Erkennung wie [istDampftunnelMaschine] — vorher stand hier
  /// nur „dampftunnel", weshalb der Heißluftofen fälschlich das
  /// Bratstraßen-Raster (10+10) bekam.
  bool get _istDampftunnel => istDampftunnelMaschine(maschineName);

  /// Sucht einen Parameter NAME + GRUPPE — beide Gruppen enthalten Zeilen
  /// namens "Platte Unten N" (Bratstraße 1–10, Dampftunnel 1–12). Ohne die
  /// Gruppe würden die Werte des Dampftunnels mit denen der Bratstraße
  /// verwechselt.
  static ProductStepParameter? _find(
    List<ProductStepParameter> params,
    String name,
    String gruppe,
  ) {
    for (final p in params) {
      if (p.parameterName == name && p.parameterGruppe == gruppe) return p;
    }
    return null;
  }

  static String _zahlText(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  String _gruppeVon(BratschemaTyp typ) =>
      typ == BratschemaTyp.kombiofen ? kPlattenGruppeKombi : kPlattenGruppeBrat;

  PlattenTemperaturen _leseWerte(
    List<ProductStepParameter> params,
    BratschemaTyp typ,
  ) {
    final gruppe = _gruppeVon(typ);
    final leer = PlattenTemperaturen.leer(typ);
    double? wertVon(String name) {
      final w = _find(params, name, gruppe)?.wert;
      if (w == null || w.trim().isEmpty) return null;
      return double.tryParse(w.replaceAll(',', '.'));
    }

    return PlattenTemperaturen(
      oben: [
        for (var i = 0; i < leer.oben.length; i++) wertVon('Platte Oben ${i + 1}'),
      ],
      unten: [
        for (var i = 0; i < leer.unten.length; i++)
          wertVon('Platte Unten ${i + 1}'),
      ],
    );
  }

  Future<void> _upsert(
    WidgetRef ref,
    List<ProductStepParameter> params,
    String name,
    String gruppe,
    String? wert,
  ) async {
    final db = ref.read(databaseProvider);
    final vorhanden = _find(params, name, gruppe);
    if (vorhanden != null) {
      await (db.update(db.productStepParameters)
            ..where((p) => p.id.equals(vorhanden.id)))
          .write(
        ProductStepParametersCompanion(
          wert: Value(wert),
          updatedAt: Value(DateTime.now()),
        ),
      );
    } else {
      await db.into(db.productStepParameters).insert(
            ProductStepParametersCompanion(
              id: Value(const Uuid().v4()),
              stepId: Value(step.id),
              parameterGruppe: Value(gruppe),
              parameterName: Value(name),
              wert: Value(wert),
              reihenfolge: const Value(100),
              istCustom: const Value(false),
            ),
          );
    }
  }

  Future<void> _speichereWerte(
    WidgetRef ref,
    List<ProductStepParameter> params,
    BratschemaTyp typ,
    PlattenTemperaturen neu,
  ) async {
    final gruppe = _gruppeVon(typ);
    final alt = _leseWerte(params, typ);
    for (var i = 0; i < neu.oben.length; i++) {
      if (neu.oben[i] != alt.oben[i]) {
        await _upsert(
          ref,
          params,
          'Platte Oben ${i + 1}',
          gruppe,
          neu.oben[i] == null ? null : _zahlText(neu.oben[i]!),
        );
      }
    }
    for (var i = 0; i < neu.unten.length; i++) {
      if (neu.unten[i] != alt.unten[i]) {
        await _upsert(
          ref,
          params,
          'Platte Unten ${i + 1}',
          gruppe,
          neu.unten[i] == null ? null : _zahlText(neu.unten[i]!),
        );
      }
    }
    ref.read(autoBackupTriggerProvider).fireDebounced(
          reason: 'Plattentemperatur geändert',
        );
    ref.invalidate(stepParametersProvider(step.id));
    onUpdated();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final paramsAsync = ref.watch(stepParametersProvider(step.id));

    return paramsAsync.when(
      data: (params) {
        // Nur das Raster der EIGENEN Maschine anzeigen.
        final typ = _istDampftunnel
            ? BratschemaTyp.kombiofen
            : BratschemaTyp.bratstrasse;
        final titel = _istDampftunnel
            ? 'PLATTEN DAMPFTUNNEL (12)'
            : 'PLATTEN BRATSTRASSE (10+10)';

        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color:
                theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titel,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 6),
              BratstrasseSchema(
                typ: typ,
                werte: _leseWerte(params, typ),
                onChanged: (neu) => _speichereWerte(ref, params, typ, neu),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox(
        height: 24,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (e, _) => Text(
        'Schema-Fehler: $e',
        style: const TextStyle(color: Colors.red, fontSize: 12),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Werte-Feld (Label oben, Wert unten — antippbar zum Bearbeiten)
// ---------------------------------------------------------------------------

class _WertFeld extends StatelessWidget {
  const _WertFeld({
    required this.label,
    required this.wert,
    required this.onTap,
  });

  final String label;
  final String wert;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final hatWert = wert.trim().isNotEmpty && wert.trim() != '–';
    final accent = dark ? const Color(0xFF66BB6A) : const Color(0xFF2E7D32);
    final bg = hatWert
        ? accent.withValues(alpha: dark ? 0.22 : 0.12)
        : theme.colorScheme.onSurface.withValues(alpha: 0.05);
    final border = hatWert
        ? accent.withValues(alpha: 0.5)
        : theme.colorScheme.onSurface.withValues(alpha: 0.10);
    final wertColor = hatWert
        ? (dark ? const Color(0xFF9CCC65) : accent)
        : theme.colorScheme.onSurface.withValues(alpha: 0.4);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.edit,
                  size: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              wert,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: wertColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

String _fmtZahl(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

// ---------------------------------------------------------------------------
// Parameter-Liste
// ---------------------------------------------------------------------------

class _ParameterListe extends ConsumerWidget {
  const _ParameterListe({
    required this.stepId,
    this.maschineId,
    this.maschinenName,
  });

  final String stepId;

  /// Maschine des Schritts — bestimmt die Steckbrief-Felder.
  final String? maschineId;
  final String? maschinenName;

  Future<void> _customLoeschen(
    BuildContext context,
    WidgetRef ref,
    ProductStepParameter param,
  ) async {
    final bestaetigt = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Parameter löschen?'),
        content: Text('Parameter „${param.parameterName}" wird gelöscht.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (bestaetigt != true) return;

    final db = ref.read(databaseProvider);
    await (db.update(db.productStepParameters)
          ..where((p) => p.id.equals(param.id)))
        .write(
      ProductStepParametersCompanion(
        deletedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );

    ref.read(autoBackupTriggerProvider).fireDebounced(
          reason: 'Custom-Parameter gelöscht',
        );
    ref.invalidate(stepParametersProvider(stepId));
  }

  Future<void> _standardBearbeiten(
    BuildContext context,
    WidgetRef ref,
    ProductStepParameter param,
  ) async {
    final db = ref.read(databaseProvider);
    final neuerWert = await _wertDialogMitPruefung(
      context,
      db: db,
      titel: param.parameterName,
      initial: param.wert ?? '',
      gruppe: param.parameterGruppe,
      parameterName: param.parameterName,
      maschinenName: maschinenName,
    );
    if (neuerWert == null) return;

    await (db.update(db.productStepParameters)
          ..where((p) => p.id.equals(param.id)))
        .write(
      ProductStepParametersCompanion(
        wert: Value(neuerWert.isEmpty ? null : neuerWert),
        updatedAt: Value(DateTime.now()),
      ),
    );

    ref.read(autoBackupTriggerProvider).fireDebounced(
          reason: 'Parameter geändert',
        );
    ref.invalidate(stepParametersProvider(stepId));
  }

  /// Bearbeitet ein Steckbrief-Feld: Wert-Dialog mit Grenzen-Prüfung,
  /// dann Upsert in die Parametergruppe MASCHINENEINSTELLUNGEN.
  Future<void> _steckbriefBearbeiten(
    BuildContext context,
    WidgetRef ref,
    MachineParameterDef def,
    ProductStepParameter? vorhanden,
  ) async {
    final db = ref.read(databaseProvider);
    final neuerWert = await _wertDialogMitPruefung(
      context,
      db: db,
      titel: def.parameterName,
      initial: vorhanden?.wert ?? '',
      gruppe: kMaschinenNotizGruppe,
      parameterName: def.parameterName,
      maschinenName: maschinenName,
      einheit: def.einheit,
    );
    if (neuerWert == null) return;

    final jetzt = DateTime.now();
    if (vorhanden != null) {
      await (db.update(db.productStepParameters)
            ..where((p) => p.id.equals(vorhanden.id)))
          .write(
        ProductStepParametersCompanion(
          wert: Value(neuerWert.isEmpty ? null : neuerWert),
          updatedAt: Value(jetzt),
        ),
      );
    } else {
      // Neue Zeile in die Gruppe legen, die dieser Schritt bereits für
      // Maschinenwerte benutzt (z.B. „BRATSTRASSE" oder „FÜLLMASCHINE /
      // VERBUFA"). Nur wenn es noch keine gibt, greift die Standardgruppe.
      // So landet der Wert im Excel-Export im richtigen Block.
      final alle = ref.read(stepParametersProvider(stepId)).valueOrNull ??
          const <ProductStepParameter>[];
      var zielGruppe = kMaschinenNotizGruppe;
      for (final p in alle) {
        if (p.istCustom) continue;
        if (p.parameterGruppe == kMaschinenNotizGruppe) continue;
        zielGruppe = p.parameterGruppe;
        break;
      }

      await db.into(db.productStepParameters).insert(
            ProductStepParametersCompanion(
              id: Value(const Uuid().v4()),
              stepId: Value(stepId),
              parameterGruppe: Value(zielGruppe),
              parameterName: Value(def.parameterName),
              wert: Value(neuerWert.isEmpty ? null : neuerWert),
              reihenfolge: Value(50 + def.sortierung),
              istCustom: const Value(false),
            ),
          );
    }

    ref.read(autoBackupTriggerProvider).fireDebounced(
          reason: 'Maschinen-Parameter geändert',
        );
    ref.invalidate(stepParametersProvider(stepId));
  }

  Future<void> _customNeu(BuildContext context, WidgetRef ref) async {
    final geaendert = await CustomParameterEditorDialog.show(
      context,
      stepId: stepId,
    );
    if (geaendert) {
      ref.invalidate(stepParametersProvider(stepId));
    }
  }

  Future<void> _customBearbeiten(
    BuildContext context,
    WidgetRef ref,
    ProductStepParameter param,
  ) async {
    final geaendert = await CustomParameterEditorDialog.show(
      context,
      stepId: stepId,
      existingParameter: param,
    );
    if (geaendert) {
      ref.invalidate(stepParametersProvider(stepId));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final paramsAsync = ref.watch(stepParametersProvider(stepId));

    return paramsAsync.when(
      data: (alleParams) {
        final params = alleParams
            .where((p) => !istVerstecktesPlattenParam(p.parameterName))
            .toList();
        final standardParams = params.where((p) => !p.istCustom).toList();
        final customParams = params.where((p) => p.istCustom).toList();

        // Steckbrief-Felder der Maschine (falls eine zugeordnet ist).
        final defsAsync = maschineId == null
            ? const AsyncValue<List<MachineParameterDef>>.data([])
            : ref.watch(_steckbriefDefsProvider(maschineId!));
        final defs = defsAsync.valueOrNull ?? const <MachineParameterDef>[];
        final defNamen =
            defs.map((d) => d.parameterName.trim().toLowerCase()).toSet();

        // Standard-Parameter nach Gruppen aufteilen. Zeilen, die zu einem
        // Steckbrief-Feld gehören, erscheinen im Steckbrief-Block und
        // werden hier ausgefiltert (sonst doppelt sichtbar).
        final standardByGruppe = <String, List<ProductStepParameter>>{};
        for (final p in standardParams) {
          // Alles, was der Steckbrief-Block oben schon zeigt, hier
          // ausblenden — unabhängig von der Gruppe. Sonst stünde derselbe
          // Wert zweimal in der Maske (einmal aus der Excel-Gruppe, einmal
          // im Steckbrief).
          if (defNamen.contains(p.parameterName.trim().toLowerCase())) {
            continue;
          }
          standardByGruppe.putIfAbsent(p.parameterGruppe, () => []).add(p);
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
              ],
            ),
            const SizedBox(height: 8),

            // Steckbrief-Felder der zugeordneten Maschine
            if (defs.isNotEmpty) ...[
              _SteckbriefBlock(
                stepId: stepId,
                maschinenName: maschinenName,
                defs: defs,
                params: alleParams,
                onEdit: (def, vorhanden) =>
                    _steckbriefBearbeiten(context, ref, def, vorhanden),
              ),
              const SizedBox(height: 8),
            ],

            // Standard-Parameter (readonly)
            if (standardByGruppe.isNotEmpty) ...[
              for (final entry in standardByGruppe.entries) ...[
                _StandardGruppenBlock(
                  gruppenName: entry.key,
                  parameter: entry.value,
                  onEdit: (p) => _standardBearbeiten(context, ref, p),
                ),
                const SizedBox(height: 8),
              ],
            ],

            // Custom-Parameter (editierbar)
            _CustomGruppenBlock(
              parameter: customParams,
              onAdd: () => _customNeu(context, ref),
              onEdit: (p) => _customBearbeiten(context, ref, p),
              onDelete: (p) => _customLoeschen(context, ref, p),
            ),
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

/// Block für Standard-Parameter aus der Excel-Vorlage. Editierbar
/// (Werte werden beim Export wieder in die Excel zurückgeschrieben).
/// Block für die Steckbrief-Felder der zugeordneten Maschine: zeigt alle
/// im Maschinen-Katalog definierten Parameter — mit Wert, wenn am Artikel
/// gepflegt, sonst als leere Zeile zum Ausfüllen.
class _SteckbriefBlock extends StatelessWidget {
  const _SteckbriefBlock({
    required this.stepId,
    required this.maschinenName,
    required this.defs,
    required this.params,
    required this.onEdit,
  });

  final String stepId;
  final String? maschinenName;
  final List<MachineParameterDef> defs;
  final List<ProductStepParameter> params;
  final void Function(MachineParameterDef, ProductStepParameter?) onEdit;

  /// Sucht die Wertzeile zu einem Steckbrief-Feld — bewusst NUR über den
  /// Parameternamen, unabhängig von der Parametergruppe.
  ///
  /// Grund: Aus der alten Excel importierte Werte liegen in der Gruppe der
  /// jeweiligen Anlage (z.B. „FÜLLMASCHINE / VERBUFA"), während die App
  /// früher ausschließlich in „MASCHINENEINSTELLUNGEN" gesucht hat. Dadurch
  /// wirkte ein gepflegter Wert leer, und beim Speichern entstand eine
  /// zweite Zeile in einer anderen Gruppe — im Excel-Export tauchte der Wert
  /// dann außerhalb des Maschinenblocks auf.
  ProductStepParameter? _wertZeile(MachineParameterDef def) {
    final gesucht = def.parameterName.trim().toLowerCase();
    ProductStepParameter? treffer;
    for (final p in params) {
      if (p.parameterName.trim().toLowerCase() != gesucht) continue;
      // Die Zeile in der Maschinengruppe hat Vorrang — sie steht im Export
      // an der richtigen Stelle.
      if (p.parameterGruppe != kMaschinenNotizGruppe) return p;
      treffer ??= p;
    }
    return treffer;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.precision_manufacturing,
                size: 14,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                (maschinenName ?? 'MASCHINE').toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final def in defs)
            Builder(
              builder: (context) {
                final zeile = _wertZeile(def);
                final wert = zeile?.wert?.trim();
                final hatWert = wert != null && wert.isNotEmpty;
                return InkWell(
                  onTap: () => onEdit(def, zeile),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 5,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            (def.einheit ?? '').isEmpty
                                ? def.parameterName
                                : '${def.parameterName} (${def.einheit})',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        hatWert
                            ? _ParamWert(wert: wert)
                            : Text(
                                'eintragen …',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontStyle: FontStyle.italic,
                                  color: theme.colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.7),
                                ),
                              ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _StandardGruppenBlock extends StatelessWidget {
  const _StandardGruppenBlock({
    required this.gruppenName,
    required this.parameter,
    required this.onEdit,
  });

  final String gruppenName;
  final List<ProductStepParameter> parameter;
  final void Function(ProductStepParameter) onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                gruppenName,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...parameter.map(
            (p) => _ParameterZeileStandard(
              param: p,
              onEdit: () => onEdit(p),
            ),
          ),
        ],
      ),
    );
  }
}

/// Block für Custom-Parameter (vom Nutzer angelegt). Editierbar.
class _CustomGruppenBlock extends StatelessWidget {
  const _CustomGruppenBlock({
    required this.parameter,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final List<ProductStepParameter> parameter;
  final VoidCallback onAdd;
  final void Function(ProductStepParameter) onEdit;
  final void Function(ProductStepParameter) onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Zusätzliche Parameter',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 16),
                label: const Text(
                  'Neu',
                  style: TextStyle(fontSize: 12),
                ),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          if (parameter.isNotEmpty)
            ...parameter.map(
              (p) => _ParameterZeileEditierbar(
                param: p,
                onEdit: () => onEdit(p),
                onDelete: () => onDelete(p),
              ),
            ),
        ],
      ),
    );
  }
}

/// Eine Standard-Parameter-Zeile — tippen zum Bearbeiten des Werts.
class _ParameterZeileStandard extends StatelessWidget {
  const _ParameterZeileStandard({
    required this.param,
    required this.onEdit,
  });

  final ProductStepParameter param;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 2,
              child: Text(
                param.parameterName,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 1,
              child: _ParamWert(wert: param.wert),
            ),
            Icon(
              Icons.edit,
              size: 15,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wert-Anzeige für Parameter: gefüllt = grüne Pille, leer = gedämpftes „—".
class _ParamWert extends StatelessWidget {
  const _ParamWert({required this.wert});

  final String? wert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final hat = wert != null && wert!.trim().isNotEmpty;
    if (!hat) {
      return Text(
        '—',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
        ),
      );
    }
    final accent = dark ? const Color(0xFF9CCC65) : const Color(0xFF2E7D32);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: dark ? 0.20 : 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          wert!,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: accent,
          ),
        ),
      ),
    );
  }
}

/// Eine Parameter-Zeile mit Bearbeiten/Löschen (für Custom-Parameter).
class _ParameterZeileEditierbar extends StatelessWidget {
  const _ParameterZeileEditierbar({
    required this.param,
    required this.onEdit,
    required this.onDelete,
  });

  final ProductStepParameter param;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              param.parameterName,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 1,
            child: _ParamWert(wert: param.wert),
          ),
          IconButton(
            icon: const Icon(Icons.edit, size: 16),
            tooltip: 'Bearbeiten',
            onPressed: onEdit,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 16),
            tooltip: 'Löschen',
            onPressed: onDelete,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}
