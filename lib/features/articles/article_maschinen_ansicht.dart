part of 'article_detail_screen.dart';

// ---------------------------------------------------------------------------
// Maschinen-Block: die Details einer Anlage im Prozess eines Artikels
// ---------------------------------------------------------------------------
//
// Die Übersicht der Kette steht in article_prozesskette.dart. Hier liegt,
// was sich beim Antippen einer Anlage öffnet: Personen, Plattenschema oder
// Notizen und die Parameter.

/// Kleine farbige Pille für Kennzahlen.
class _Pille extends StatelessWidget {
  const _Pille({required this.text, required this.farbe});

  final String text;
  final Color farbe;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: farbe.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: farbe.withValues(alpha: 0.45)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: farbe,
        ),
      ),
    );
  }
}

/// Details einer Anlage — Inhalt des Sheets, das sich beim Antippen einer
/// Anlage in der Prozesskette öffnet.
class _MaschinenBlock extends ConsumerStatefulWidget {
  const _MaschinenBlock({
    required this.step,
    required this.stepNumber,
    required this.onUpdated,
  });

  final ProductStep step;
  final int stepNumber;
  final VoidCallback onUpdated;

  @override
  ConsumerState<_MaschinenBlock> createState() => _MaschinenBlockState();
}

class _MaschinenBlockState extends ConsumerState<_MaschinenBlock> {
  Future<void> _openEditor() async {
    final geaendert = await StepEditorDialog.show(
      context,
      step: widget.step,
      stepNumber: widget.stepNumber,
    );
    if (geaendert) widget.onUpdated();
  }

  Future<void> _loescheSchritt() async {
    final name = (widget.step.maschine != null &&
            widget.step.maschine!.isNotEmpty)
        ? widget.step.maschine!
        : 'Dieser Schritt';
    final bestaetigt = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aus Prozess entfernen?'),
        content: Text(
          '„$name" wird aus dem Prozess dieses Artikels entfernt. '
          'Die Maschine selbst bleibt erhalten und kann jederzeit wieder '
          'hinzugefügt werden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Entfernen'),
          ),
        ],
      ),
    );
    if (bestaetigt != true) return;
    // Nummeriert den Rest lückenlos neu (Excel-Spalten) und gibt die
    // Leistungsdaten der Abteilung weiter, falls dieser Schritt sie trug.
    await ProzesskettenService.entferneSchritt(
      ref.read(databaseProvider),
      widget.step.id,
    );

    ref.read(autoBackupTriggerProvider).fireDebounced(
          reason: 'Schritt aus Prozess entfernt',
        );
    widget.onUpdated();
    // Den Schritt gibt es nicht mehr — das Sheet mit seinen Details
    // schließen, statt ihn weiter bearbeitbar zu zeigen.
    if (mounted) await Navigator.of(context).maybePop();
  }

  Future<void> _editNumber({
    required String titel,
    required double? aktuell,
    String? suffix,
    required ProductStepsCompanion Function(double) bauen,
  }) async {
    final ctrl = TextEditingController(
      text: (aktuell != null && aktuell > 0) ? _fmtZahl(aktuell) : '',
    );
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titel),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Wert',
            suffixText: suffix,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Speichern'),
          ),
        ],
      ),
    ).whenComplete(ctrl.dispose);
    if (res == null) return;
    final zahl = double.tryParse(res.replaceAll(',', '.')) ?? 0.0;
    final db = ref.read(databaseProvider);
    await (db.update(db.productSteps)
          ..where((s) => s.id.equals(widget.step.id)))
        .write(bauen(zahl));
    ref.read(autoBackupTriggerProvider).fireDebounced(
          reason: 'Schritt-Wert geändert',
        );
    widget.onUpdated();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.step;
    final maschineName = (s.maschine != null && s.maschine!.isNotEmpty)
        ? s.maschine!
        : ((s.prozessschritt != null && s.prozessschritt!.isNotEmpty)
            ? s.prozessschritt!
            : 'Maschine ${widget.stepNumber}');
    final zeigeProzess = s.prozessschritt != null &&
        s.prozessschritt!.isNotEmpty &&
        s.maschine != null &&
        s.maschine!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Maschinen-Kopf
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.factory, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      maschineName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (zeigeProzess) ...[
                      const SizedBox(height: 2),
                      Text(
                        s.prozessschritt!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit, size: 18),
                tooltip: 'Maschine/Schritt bearbeiten',
                visualDensity: VisualDensity.compact,
                onPressed: _openEditor,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: 'Aus Prozess entfernen',
                visualDensity: VisualDensity.compact,
                color: theme.colorScheme.error,
                onPressed: _loescheSchritt,
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Personen hängen am einzelnen Schritt: Dieselbe Anlage kann
          // bei Artikel A mit zwei und bei Artikel B mit drei Personen
          // besetzt sein. Die Abteilungszahl im Kopf der Station ist die
          // Summe darüber und aktualisiert sich über `onUpdated()` sofort.
          //
          // Zeiten gibt es an der Anlage keine: Die Dauer kommt aus den
          // Leistungsdaten der Abteilung oder aus den erfassten
          // Produktionen.
          SizedBox(
            width: 220,
            child: _WertFeld(
              label: 'Personen',
              wert: s.basisMitarbeiter > 0 ? '${s.basisMitarbeiter}' : '–',
              onTap: () => _editNumber(
                titel: 'Personen an diesem Schritt',
                aktuell: s.basisMitarbeiter.toDouble(),
                suffix: 'Pers.',
                bauen: (v) => ProductStepsCompanion(
                  basisMitarbeiter: Value(v > 0 ? v.round() : 0),
                  updatedAt: Value(DateTime.now()),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Plattenschema NUR bei den Maschinen Bratstraße/Dampftunnel —
          // sie haben ein festes Zonenraster. Alle anderen Maschinen
          // (Schockfroster, Heißluftofen, Füllmaschine, Verpackung …)
          // bekommen stattdessen das freie Notizfeld, weil ihre
          // Einstellungen zu individuell für starre Felder sind.
          //
          // Bewusst an der MASCHINE festgemacht, nicht an der Abteilung:
          // der Schockfroster steht in der Abteilung Bratstraße, braucht
          // aber ein Notizfeld statt eines Plattenrasters.
          if (istPlattenMaschine(maschineName)) ...[
            if (istDampftunnelMaschine(maschineName))
              _InlineHinweis(productId: s.productId),
            _PlattenSchemaBereich(
              step: s,
              maschineName: maschineName,
              onUpdated: widget.onUpdated,
            ),
            const SizedBox(height: 12),
          ] else ...[
            _MaschinenNotizFeld(step: s, onUpdated: widget.onUpdated),
            const SizedBox(height: 12),
          ],

          // Parameter (Standard + Custom, beide editierbar) — inklusive
          // Steckbrief-Feldern der zugeordneten Maschine.
          _ParameterListe(
            stepId: s.id,
            maschineId: s.maschineId,
            maschinenName: maschineName,
          ),
        ],
      ),
    );
  }
}
