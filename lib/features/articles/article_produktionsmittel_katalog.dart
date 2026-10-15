part of 'article_detail_screen.dart';

// ---------------------------------------------------------------------------
// Produktionsmittel-Katalog (Leiste / Fenster)
// ---------------------------------------------------------------------------

/// Listet alle angelegten Maschinen, nach Abteilung gruppiert. Tippen legt
/// einen Prozess-Schritt mit dieser Maschine an (Editor öffnet vorausgewählt,
/// der Schritt kommt ans Ende seiner Abteilung). Neben der Kette lassen sich
/// die Anlagen auch direkt an eine Stelle der Kette ziehen.
/// Grüner Haken = bereits im Prozess, Plus = noch nicht.
class _ProduktionsmittelKatalog extends ConsumerWidget {
  const _ProduktionsmittelKatalog({
    required this.productId,
    this.ziehbar = false,
  });

  final String productId;

  /// Anlagen lassen sich in die Kette ziehen — nur in der Leiste neben
  /// der Kette, nicht im Fenster, das über ihr liegt.
  final bool ziehbar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final maschinenAsync = ref.watch(alleMaschinenProvider);
    final steps = ref.watch(productStepsProvider(productId)).valueOrNull ??
        const <ProductStep>[];
    final imProzess =
        steps.map((s) => s.maschineId).whereType<String>().toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.precision_manufacturing, size: 16, color: grau),
            const SizedBox(width: 6),
            Text(
              'Produktionsmittel',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          ziehbar
              ? 'In die Kette ziehen oder antippen.'
              : 'Tippen, um es dem Prozess hinzuzufügen.',
          style: theme.textTheme.bodySmall?.copyWith(color: grau),
        ),
        const SizedBox(height: 10),
        maschinenAsync.when(
          data: (maschinen) {
            final byAbt = <String, List<Machine>>{};
            for (final m in maschinen) {
              byAbt.putIfAbsent(m.abteilung, () => []).add(m);
            }

            final gruppen = <Widget>[];
            final bekannt = <String>{};
            for (final abt in Abteilung.values) {
              final liste = byAbt[abt.dbValue] ?? const <Machine>[];
              bekannt.add(abt.dbValue);
              gruppen.add(
                _KatalogAbteilung(
                  abt: abt,
                  maschinen: liste,
                  imProzess: imProzess,
                  ziehbar: ziehbar,
                  onTapMaschine: (m) => _hinzufuegen(context, m),
                  onNeueAnlage: () => _neueAnlage(context, ref, abt),
                ),
              );
            }

            // Maschinen mit unbekannter Abteilung ans Ende.
            final rest =
                maschinen.where((m) => !bekannt.contains(m.abteilung)).toList();
            if (rest.isNotEmpty) {
              gruppen.add(
                _KatalogAbteilung(
                  abt: null,
                  maschinen: rest,
                  imProzess: imProzess,
                  ziehbar: ziehbar,
                  onTapMaschine: (m) => _hinzufuegen(context, m),
                  onNeueAnlage: null,
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: gruppen,
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (e, _) => Text(
            'Fehler: $e',
            style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
          ),
        ),
      ],
    );
  }

  /// Legt einen Schritt mit [m] an — am Ende seiner Abteilung, gibt es
  /// sie noch nicht, am Ende der Kette.
  Future<void> _hinzufuegen(BuildContext context, Machine m) async {
    // Vor dem await holen: Das Fenster mit dem Katalog kann inzwischen zu
    // sein.
    final container = ProviderScope.containerOf(context, listen: false);
    final ok = await StepEditorDialog.show(
      context,
      productId: productId,
      startMaschine: m,
    );
    if (ok) container.invalidate(productStepsProvider(productId));
  }

  /// Legt eine neue Anlage in der gewählten Abteilung an.
  ///
  /// Sie steht danach sofort im Katalog und wird beim nächsten
  /// Excel-Export automatisch in den Anlagen-Katalog der Vorlage
  /// eingetragen (inkl. Abteilung).
  Future<void> _neueAnlage(
    BuildContext context,
    WidgetRef ref,
    Abteilung abt,
  ) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Neue Anlage · ${abt.anzeigeName}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Name der Anlage',
            hintText: 'z.B. Kochkammer 5',
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
            child: const Text('Anlegen'),
          ),
        ],
      ),
    ).whenComplete(ctrl.dispose);
    if (name == null || name.isEmpty) return;

    final db = ref.read(databaseProvider);

    // Doppelte Namen vermeiden (Katalog + Excel sind namensbasiert).
    final vorhandene =
        ref.read(alleMaschinenProvider).valueOrNull ?? const <Machine>[];
    if (vorhandene.any(
      (m) => m.name.trim().toLowerCase() == name.toLowerCase(),
    )) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Anlage "$name" existiert bereits.')),
        );
      }
      return;
    }

    await db.into(db.machines).insert(
          MachinesCompanion(
            id: Value(const Uuid().v4()),
            name: Value(name),
            abteilung: Value(abt.dbValue),
          ),
        );

    ref.read(autoBackupTriggerProvider).fireDebounced(
          reason: 'Neue Anlage angelegt',
        );
    ref.invalidate(alleMaschinenProvider);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Anlage "$name" in ${abt.anzeigeName} angelegt — wird beim '
            'nächsten Excel-Export in den Anlagen-Katalog übernommen.',
          ),
        ),
      );
    }
  }
}

/// Aufklappbare Abteilungs-Gruppe im Katalog. Standard: zugeklappt —
/// so bleibt die Leiste kurz und die Kette bekommt die Bühne.
class _KatalogAbteilung extends StatefulWidget {
  const _KatalogAbteilung({
    required this.abt,
    required this.maschinen,
    required this.imProzess,
    required this.ziehbar,
    required this.onTapMaschine,
    required this.onNeueAnlage,
  });

  /// null = Gruppe „Weitere" (unbekannte Abteilung).
  final Abteilung? abt;
  final List<Machine> maschinen;
  final Set<String> imProzess;
  final bool ziehbar;
  final void Function(Machine) onTapMaschine;
  final VoidCallback? onNeueAnlage;

  @override
  State<_KatalogAbteilung> createState() => _KatalogAbteilungState();
}

class _KatalogAbteilungState extends State<_KatalogAbteilung> {
  bool _offen = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final farbe = widget.abt?.farbe ?? theme.colorScheme.outline;
    final name = widget.abt?.anzeigeName ?? 'Weitere';
    final anzahlImProzess = widget.maschinen
        .where((m) => widget.imProzess.contains(m.id))
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _offen = !_offen),
          borderRadius: AppMasse.ecken,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: _offen ? 0.25 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(Icons.chevron_right, size: 17, color: grau),
                ),
                const SizedBox(width: 4),
                AbteilungsMarke(abteilung: widget.abt, skala: 0.9),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Anzahl — grün, wenn welche davon im Prozess sind.
                StatusMarke(
                  anzahlImProzess > 0
                      ? '$anzahlImProzess/${widget.maschinen.length}'
                      : '${widget.maschinen.length}',
                  art: anzahlImProzess > 0 ? StatusArt.ok : StatusArt.neutral,
                ),
              ],
            ),
          ),
        ),
        if (_offen)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 0, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final m in widget.maschinen)
                  _KatalogZeile(
                    farbe: farbe,
                    maschine: m,
                    imProzess: widget.imProzess.contains(m.id),
                    ziehbar: widget.ziehbar,
                    onTap: () => widget.onTapMaschine(m),
                  ),
                if (widget.onNeueAnlage != null)
                  InkWell(
                    onTap: widget.onNeueAnlage,
                    borderRadius: AppMasse.ecken,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 7,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.add,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Neue Anlage …',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Eine Maschinen-Zeile im Katalog — tippen fügt sie dem Prozess hinzu,
/// [ziehbar] lässt sie sich an eine Stelle der Kette ziehen.
class _KatalogZeile extends StatelessWidget {
  const _KatalogZeile({
    required this.farbe,
    required this.maschine,
    required this.imProzess,
    required this.ziehbar,
    required this.onTap,
  });

  final Color farbe;
  final Machine maschine;
  final bool imProzess;
  final bool ziehbar;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zeile = _inhalt(context);
    if (!ziehbar) return zeile;
    return Draggable<KettenZug>(
      data: AnlagenZug(maschine),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _ZiehSchild(
        text: maschine.name,
        farbe: farbe,
        icon: Icons.precision_manufacturing,
      ),
      child: MouseRegion(cursor: SystemMouseCursors.grab, child: zeile),
    );
  }

  Widget _inhalt(BuildContext context) {
    final theme = Theme.of(context);
    final f = AppFarben.von(context);
    // Weiße Zeile auf der grauen Leiste — wie ein Teil, das man nehmen
    // kann.
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppMasse.ecken,
          side: BorderSide(color: theme.colorScheme.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    maschine.name,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Tooltip(
                  message:
                      imProzess ? 'Schon im Prozess' : 'Noch nicht im Prozess',
                  child: Icon(
                    imProzess ? Icons.check_circle : Icons.add_circle_outline,
                    size: 16,
                    color: imProzess ? f.ok : theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Knopf (schmale Fenster) — öffnet den Katalog als Fenster.
class _ProduktionsmittelButton extends StatelessWidget {
  const _ProduktionsmittelButton({required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () {
        final container = ProviderScope.containerOf(context);
        showSheetOhneAnimation<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: true,
          builder: (_) => UncontrolledProviderScope(
            container: container,
            child: _ProduktionsmittelSheet(productId: productId),
          ),
        );
      },
      icon: const Icon(Icons.add, size: 18),
      label: const Text('Produktionsmittel'),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// Inhalt des Produktionsmittel-Fensters.
class _ProduktionsmittelSheet extends StatelessWidget {
  const _ProduktionsmittelSheet({required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: _ProduktionsmittelKatalog(productId: productId),
        ),
      ),
    );
  }
}
