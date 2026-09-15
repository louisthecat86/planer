part of 'article_detail_screen.dart';

// ---------------------------------------------------------------------------
// Abteilungs-Karte (bündelt alle Maschinen einer Abteilung)
// ---------------------------------------------------------------------------

/// Karten-Ansicht des Prozesses.
///
/// Früher lagen alle Maschinen vollständig ausgeklappt untereinander —
/// bei sieben Schritten hieß das minutenlanges Scrollen, und wo eine
/// Abteilung endete war kaum zu erkennen. Jetzt ist jede Abteilung ein
/// einklappbares Panel, die Maschinen darin sind kompakte Kacheln
/// nebeneinander. Details öffnen sich auf Tippen im selben Sheet, das
/// auch das Diagramm benutzt.
class _KartenAnsicht extends StatefulWidget {
  const _KartenAnsicht({
    required this.productId,
    required this.gruppen,
    required this.onMoveTo,
    required this.onUpdated,
  });

  final String productId;
  final List<List<({ProductStep step, int nummer})>> gruppen;
  final void Function(int von, int nach) onMoveTo;
  final VoidCallback onUpdated;

  @override
  State<_KartenAnsicht> createState() => _KartenAnsichtState();
}

class _KartenAnsichtState extends State<_KartenAnsicht> {
  /// Offene Abteilungen — als Abteilungs-Schlüssel, nicht als Index:
  /// beim Umsortieren soll der Zustand am Inhalt kleben, nicht an der
  /// Position.
  late Set<String> _offen;

  String _schluessel(List<({ProductStep step, int nummer})> g) =>
      g.first.step.abteilung;

  @override
  void initState() {
    super.initState();
    // Wenige Abteilungen ? gleich offen, viele ? zugeklappt starten.
    _offen = widget.gruppen.length <= 3
        ? widget.gruppen.map(_schluessel).toSet()
        : <String>{};
  }

  void _alleAufZu(bool auf) {
    setState(() {
      _offen = auf ? widget.gruppen.map(_schluessel).toSet() : <String>{};
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.gruppen.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Noch keine Produktionsschritte.\n\n'
            'Füge ein Produktionsmittel hinzu oder importiere eine '
            'Excel-Vorlage.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    final alleOffen = _offen.length == widget.gruppen.length;
    final schritteGesamt =
        widget.gruppen.fold<int>(0, (s, g) => s + g.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Kopfleiste: Überblick + Alles auf/zu
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
          child: Row(
            children: [
              Text(
                '${widget.gruppen.length} Abteilungen · '
                '$schritteGesamt Schritte',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _alleAufZu(!alleOffen),
                icon: Icon(
                  alleOffen ? Icons.unfold_less : Icons.unfold_more,
                  size: 18,
                ),
                label: Text(alleOffen ? 'Alle einklappen' : 'Alle ausklappen'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: widget.gruppen.length,
            itemBuilder: (context, g) {
              final gruppe = widget.gruppen[g];
              final key = _schluessel(gruppe);
              return _AbteilungsPanel(
                productId: widget.productId,
                gruppe: gruppe,
                position: g + 1,
                gruppenIndex: g,
                offen: _offen.contains(key),
                onToggle: () => setState(
                  () => _offen.contains(key)
                      ? _offen.remove(key)
                      : _offen.add(key),
                ),
                onMoveTo: widget.onMoveTo,
                onUpdated: widget.onUpdated,
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Eine Abteilung als einklappbares Panel mit farbiger Kante.
class _AbteilungsPanel extends StatelessWidget {
  const _AbteilungsPanel({
    required this.productId,
    required this.gruppe,
    required this.position,
    required this.gruppenIndex,
    required this.offen,
    required this.onToggle,
    required this.onMoveTo,
    required this.onUpdated,
  });

  final String productId;
  final List<({ProductStep step, int nummer})> gruppe;
  final int position;
  final int gruppenIndex;
  final bool offen;
  final VoidCallback onToggle;
  final void Function(int von, int nach) onMoveTo;
  final VoidCallback onUpdated;

  Abteilung? get _abteilung {
    try {
      return Abteilung.fromDbValue(gruppe.first.step.abteilung);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final abt = _abteilung;
    final farbe = abt?.farbe ?? Colors.grey;
    final name = abt?.anzeigeName ?? gruppe.first.step.abteilung;

    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != gruppenIndex,
      onAcceptWithDetails: (d) => onMoveTo(d.data, gruppenIndex),
      builder: (context, candidate, rejected) {
        final istZiel = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: istZiel ? theme.colorScheme.primary : farbe.withValues(alpha: 0.45),
              width: istZiel ? 2 : 1.2,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // -- Kopf: klickbar zum Auf-/Zuklappen ------------------
              InkWell(
                onTap: onToggle,
                child: Container(
                  decoration: BoxDecoration(
                    color: farbe.withValues(alpha: 0.13),
                    border: Border(
                      left: BorderSide(color: farbe, width: 5),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(11, 10, 6, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration:
                            BoxDecoration(color: farbe, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: Text(
                          '$position',
                          style: const TextStyle(
                            fontSize: 13,
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
                              name,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              // Zugeklappt zeigt die Zeile, was drinsteckt —
                              // so muss man zum Suchen nicht aufklappen.
                              gruppe
                                  .map(
                                    (e) =>
                                        e.step.maschine ??
                                        e.step.prozessschritt ??
                                        'Schritt ${e.nummer}',
                                  )
                                  .join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _Pille(
                        text: gruppe.length == 1
                            ? '1 Maschine'
                            : '${gruppe.length} Maschinen',
                        farbe: farbe,
                      ),
                      const SizedBox(width: 4),
                      // Griff zum Umsortieren der Abteilung
                      Draggable<int>(
                        data: gruppenIndex,
                        dragAnchorStrategy: pointerDragAnchorStrategy,
                        feedback: Material(
                          color: Colors.transparent,
                          child: Chip(
                            backgroundColor: farbe,
                            label: Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        child: Tooltip(
                          message: 'Abteilung ziehen zum Umsortieren',
                          child: Icon(
                            Icons.drag_indicator,
                            size: 20,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      AnimatedRotation(
                        turns: offen ? 0.5 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: Icon(
                          Icons.expand_more,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // -- Inhalt: Maschinen als Kacheln nebeneinander --------
              if (offen)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final e in gruppe)
                        _MaschinenKachel(
                          productId: productId,
                          step: e.step,
                          nummer: e.nummer,
                          farbe: farbe,
                          onUpdated: onUpdated,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Kompakte Kachel für eine Maschine. Tippen öffnet die Detailansicht
/// (dasselbe Sheet wie im Diagramm) — dadurch bleibt die Übersicht
/// schlank statt alle Parameter inline auszubreiten.
class _MaschinenKachel extends ConsumerWidget {
  const _MaschinenKachel({
    required this.productId,
    required this.step,
    required this.nummer,
    required this.farbe,
    required this.onUpdated,
  });

  final String productId;
  final ProductStep step;
  final int nummer;
  final Color farbe;
  final VoidCallback onUpdated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // Maschinenname: Katalog > Legacy-Text > Prozessschritt
    String name;
    final mid = step.maschineId;
    if (mid != null) {
      name = ref.watch(machineProvider(mid)).valueOrNull?.name ??
          'Schritt $nummer';
    } else if ((step.maschine ?? '').trim().isNotEmpty) {
      name = step.maschine!;
    } else if ((step.prozessschritt ?? '').trim().isNotEmpty) {
      name = step.prozessschritt!;
    } else {
      name = 'Schritt $nummer';
    }

    // Pflegestand der Parameter als Ampel — auf einen Blick sichtbar,
    // wo noch Werte fehlen.
    final params = ref.watch(stepParametersProvider(step.id));
    final (gepflegt, gesamt) = params.maybeWhen(
      data: (liste) => (
        liste.where((p) => (p.wert ?? '').trim().isNotEmpty).length,
        liste.length,
      ),
      orElse: () => (0, 0),
    );

    return SizedBox(
      width: 250,
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(11),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _zeigeSchrittDetail(
            context,
            productId: productId,
            stepId: step.id,
            fallback: step,
            nummer: nummer,
            onUpdated: onUpdated,
          ),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
              ),
              borderRadius: BorderRadius.circular(11),
            ),
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: farbe.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$nummer',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if ((step.prozessschritt ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    step.prozessschritt!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (gesamt > 0)
                      _Pille(
                        text: '$gepflegt/$gesamt Werte',
                        farbe: gepflegt == gesamt
                            ? Colors.green
                            : (gepflegt == 0 ? Colors.redAccent : Colors.orange),
                      ),
                    if ((step.fixZeitMinuten ?? 0) > 0) ...[
                      const SizedBox(width: 6),
                      _Pille(
                        text: '${step.fixZeitMinuten!.round()} min fix',
                        farbe: theme.colorScheme.primary,
                      ),
                    ],
                    const Spacer(),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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

// ---------------------------------------------------------------------------
// Maschinen-Block (eine Maschine innerhalb der Abteilungs-Karte)
// ---------------------------------------------------------------------------

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
    final db = ref.read(databaseProvider);
    final jetzt = DateTime.now();

    await db.transaction(() async {
      await (db.update(db.productSteps)
            ..where((s) => s.id.equals(widget.step.id)))
          .write(
        ProductStepsCompanion(
          deletedAt: Value(jetzt),
          updatedAt: Value(jetzt),
        ),
      );

      // Übrige Schritte lückenlos neu durchnummerieren (1..n).
      //
      // Ohne das behält der Rest seine alte `reihenfolge` — löscht man
      // Schritt 1, bleiben 2,3,4 stehen. Die App sortiert das zwar weg,
      // der Excel-Export nimmt die Nummer aber als Spalte: „Schritt 1"
      // bliebe leer und alles stünde eine Spalte zu weit rechts.
      final rest = await (db.select(db.productSteps)
            ..where((s) => s.productId.equals(widget.step.productId))
            ..where((s) => s.deletedAt.isNull())
            ..orderBy([(s) => OrderingTerm.asc(s.reihenfolge)]))
          .get();
      for (var i = 0; i < rest.length; i++) {
        if (rest[i].reihenfolge == i + 1) continue;
        await (db.update(db.productSteps)
              ..where((s) => s.id.equals(rest[i].id)))
            .write(
          ProductStepsCompanion(
            reihenfolge: Value(i + 1),
            updatedAt: Value(jetzt),
          ),
        );
      }
    });

    ref.read(autoBackupTriggerProvider).fireDebounced(
          reason: 'Schritt aus Prozess entfernt',
        );
    widget.onUpdated();
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

          // Nur mengenunabhängige „Fixe Zeit" bleibt am Schritt.
          // Personen/Menge/Dauer werden zentral über den Leistungsdaten-
          // Block je Abteilung gepflegt — nicht mehr pro Schritt.
          Row(
            children: [
              Expanded(
                child: _WertFeld(
                  label: 'Fixe Zeit',
                  wert: (s.fixZeitMinuten ?? 0) > 0
                      ? fmtDauer(s.fixZeitMinuten!)
                      : '–',
                  onTap: () => _editNumber(
                    titel: 'Fixe Zeit / Durchlauf (min)',
                    aktuell: s.fixZeitMinuten,
                    suffix: 'min',
                    bauen: (v) => ProductStepsCompanion(
                      fixZeitMinuten: Value(v > 0 ? v : null),
                      updatedAt: Value(DateTime.now()),
                    ),
                  ),
                ),
              ),
            ],
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
