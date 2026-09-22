part of 'article_detail_screen.dart';

// ---------------------------------------------------------------------------
// Produktionsmittel-Katalog (Sidebar / Sheet)
// ---------------------------------------------------------------------------

/// Listet alle angelegten Maschinen, nach Abteilung gruppiert. Tippen legt
/// einen Prozess-Schritt mit dieser Maschine an (Editor öffnet vorausgewählt).
/// Häkchen = bereits im Prozess, Plus = noch nicht.
class _ProduktionsmittelKatalog extends ConsumerWidget {
  const _ProduktionsmittelKatalog({required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
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
            Icon(
              Icons.precision_manufacturing,
              size: 16,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 6),
            Text(
              'Produktionsmittel',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Tippen, um es dem Prozess hinzuzufügen.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
          ),
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
                  onTapMaschine: (m) =>
                      _hinzufuegen(context, ref, m, steps.length),
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
                  onTapMaschine: (m) =>
                      _hinzufuegen(context, ref, m, steps.length),
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
            style: const TextStyle(color: Colors.red, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Future<void> _hinzufuegen(
    BuildContext context,
    WidgetRef ref,
    Machine m,
    int anzahlSchritte,
  ) async {
    final ok = await StepEditorDialog.show(
      context,
      productId: productId,
      startMaschine: m,
      stepNumber: anzahlSchritte + 1,
    );
    if (ok) ref.invalidate(productStepsProvider(productId));
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
/// so bleibt die Sidebar kurz und das Diagramm bekommt die Bühne.
class _KatalogAbteilung extends StatefulWidget {
  const _KatalogAbteilung({
    required this.abt,
    required this.maschinen,
    required this.imProzess,
    required this.onTapMaschine,
    required this.onNeueAnlage,
  });

  /// null = Gruppe „Weitere" (unbekannte Abteilung).
  final Abteilung? abt;
  final List<Machine> maschinen;
  final Set<String> imProzess;
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
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: _offen ? 0.25 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(
                    Icons.chevron_right,
                    size: 17,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(width: 2),
                Container(
                  width: 9,
                  height: 9,
                  decoration:
                      BoxDecoration(color: farbe, shape: BoxShape.circle),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    name,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Anzahl (grün, wenn welche im Prozess sind)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: anzahlImProzess > 0
                        ? const Color(0xFF2E7D32).withValues(alpha: 0.25)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    anzahlImProzess > 0
                        ? '$anzahlImProzess/${widget.maschinen.length}'
                        : '${widget.maschinen.length}',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: anzahlImProzess > 0
                          ? (theme.brightness == Brightness.dark
                              ? const Color(0xFF9CCC65)
                              : const Color(0xFF2E7D32))
                          : theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_offen)
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final m in widget.maschinen)
                  _KatalogZeile(
                    farbe: farbe,
                    name: m.name,
                    imProzess: widget.imProzess.contains(m.id),
                    onTap: () => widget.onTapMaschine(m),
                  ),
                if (widget.onNeueAnlage != null)
                  InkWell(
                    onTap: widget.onNeueAnlage,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 7,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.add_circle_outline,
                            size: 15,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
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

/// Eine Maschinen-Zeile im Katalog — tippen fügt sie dem Prozess hinzu.
class _KatalogZeile extends StatelessWidget {
  const _KatalogZeile({
    required this.farbe,
    required this.name,
    required this.imProzess,
    required this.onTap,
  });

  final Color farbe;
  final String name;
  final bool imProzess;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: farbe, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              imProzess ? Icons.check_circle : Icons.add_circle_outline,
              size: 16,
              color: imProzess
                  ? Colors.green.shade600
                  : theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}

/// Button (schmale Screens) — öffnet den Katalog als Bottom-Sheet.
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
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => UncontrolledProviderScope(
            container: container,
            child: _ProduktionsmittelSheet(productId: productId),
          ),
        );
      },
      icon: const Icon(Icons.add, size: 18),
      label: const Text('Produktionsmittel'),
    );
  }
}

/// Inhalt des Produktionsmittel-Bottom-Sheets.
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
