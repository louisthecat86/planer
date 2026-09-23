part of 'article_detail_screen.dart';

// ---------------------------------------------------------------------------
// Prozess-Fließdiagramm
//
// Kompakte Darstellung der gesamten Prozesskette auf einen Blick:
// nummerierte Abteilungs-Stationen, verbunden durch eine Flusslinie,
// Maschinen als anklickbare Knoten (grün = Daten hinterlegt).
// Klick auf einen Knoten öffnet die volle Detailansicht des Schritts.
// ---------------------------------------------------------------------------

class _ProzessDiagramm extends StatelessWidget {
  const _ProzessDiagramm({
    required this.productId,
    required this.gruppen,
    required this.onMove,
    required this.onReorderSchritt,
    required this.onUpdated,
  });

  final String productId;
  final List<List<({ProductStep step, int nummer})>> gruppen;
  final void Function(int index, int richtung) onMove;
  final void Function(int gruppenIndex, int von, int nach) onReorderSchritt;
  final VoidCallback onUpdated;

  @override
  Widget build(BuildContext context) {
    if (gruppen.isEmpty) {
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        for (var g = 0; g < gruppen.length; g++)
          _DiagrammStation(
            productId: productId,
            gruppenIndex: g,
            gruppe: gruppen[g],
            position: g + 1,
            istLetzte: g == gruppen.length - 1,
            onMoveTo: (von, nach) => onMove(von, nach - von),
            onReorderSchritt: (von, nach) => onReorderSchritt(g, von, nach),
            onUpdated: onUpdated,
          ),
      ],
    );
  }
}

/// Eine Station im Fließdiagramm: Nummern-Kreis + Flusslinie links,
/// rechts die Abteilungs-Box mit den Maschinen-Knoten.
/// Knoten lassen sich per Drag & Drop innerhalb der Station umsortieren.
class _DiagrammStation extends StatelessWidget {
  const _DiagrammStation({
    required this.productId,
    required this.gruppenIndex,
    required this.gruppe,
    required this.position,
    required this.istLetzte,
    required this.onMoveTo,
    required this.onReorderSchritt,
    required this.onUpdated,
  });

  final String productId;
  final int gruppenIndex;
  final List<({ProductStep step, int nummer})> gruppe;
  final int position;
  final bool istLetzte;

  /// Verschiebt die Abteilung von Position [von] auf Position [nach]
  /// (Drag & Drop des ganzen Blocks — ersetzt die Pfeiltasten).
  final void Function(int von, int nach) onMoveTo;
  final void Function(int von, int nach) onReorderSchritt;
  final VoidCallback onUpdated;

  /// Personalbedarf der Abteilung bei diesem Artikel = Summe über die
  /// Schritte der Station. Gepflegt wird die Zahl je Schritt im
  /// Detail-Sheet; hier steht nur das Ergebnis.
  int get _personen =>
      gruppe.fold<int>(0, (sum, e) => sum + e.step.basisMitarbeiter);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final abt = Abteilung.fromDbValue(gruppe.first.step.abteilung);
    final farbe = abt.farbe;

    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != gruppenIndex,
      onAcceptWithDetails: (d) => onMoveTo(d.data, gruppenIndex),
      builder: (context, candidate, rejected) {
        final istZiel = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(bottom: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: istZiel ? theme.colorScheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: _inhalt(context, theme, dark, abt, farbe),
        );
      },
    );
  }

  Widget _inhalt(
    BuildContext context,
    ThemeData theme,
    bool dark,
    Abteilung abt,
    Color farbe,
  ) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Fluss-Spalte: Nummern-Kreis mit Ring + Verbindungslinie + Pfeil
          SizedBox(
            width: 46,
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: farbe,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: dark ? 0.25 : 0.6),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: farbe.withValues(alpha: 0.45),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$position',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (!istLetzte) ...[
                  Expanded(
                    child: Container(
                      width: 2.5,
                      decoration: BoxDecoration(
                        color: farbe.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 22,
                    color: farbe.withValues(alpha: 0.8),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),

          // Stations-Box mit dezentem Farbverlauf
          Expanded(
            child: Container(
              margin: EdgeInsets.only(bottom: istLetzte ? 0 : 16),
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    farbe.withValues(alpha: dark ? 0.14 : 0.09),
                    farbe.withValues(alpha: dark ? 0.04 : 0.02),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: farbe.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          abt.anzeigeName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      if (_personen > 0) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: farbe.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: farbe.withValues(alpha: 0.55),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.groups_outlined, size: 14, color: farbe),
                              const SizedBox(width: 4),
                              Text(
                                _personen == 1
                                    ? '1 Person'
                                    : '$_personen Personen',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: farbe,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: farbe,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          abt.kurzcode,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Griff zum Verschieben der ganzen Abteilung. Ein
                      // eigener Griff statt der ganzen Box, damit das
                      // Ziehen einzelner Maschinen-Knoten nicht kollidiert.
                      Draggable<int>(
                        data: gruppenIndex,
                        dragAnchorStrategy: pointerDragAnchorStrategy,
                        feedback: Material(
                          color: Colors.transparent,
                          child: Chip(
                            backgroundColor: farbe,
                            label: Text(
                              abt.anzeigeName,
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
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (var i = 0; i < gruppe.length; i++)
                        _DraggableKnoten(
                          gruppenIndex: gruppenIndex,
                          index: i,
                          onReorder: onReorderSchritt,
                          knoten: _ProzessKnoten(
                            productId: productId,
                            step: gruppe[i].step,
                            nummer: gruppe[i].nummer,
                            farbe: farbe,
                            onUpdated: onUpdated,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Macht einen Prozess-Knoten zieh- und ablegbar (nur innerhalb der
/// eigenen Station). Beim Drop landet der gezogene Schritt an der
/// Position des Ziels — nach rechts gezogen dahinter, nach links davor.
class _DraggableKnoten extends StatelessWidget {
  const _DraggableKnoten({
    required this.gruppenIndex,
    required this.index,
    required this.onReorder,
    required this.knoten,
  });

  final int gruppenIndex;
  final int index;
  final void Function(int von, int nach) onReorder;
  final Widget knoten;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DragTarget<({int gruppe, int index})>(
      onWillAcceptWithDetails: (d) =>
          d.data.gruppe == gruppenIndex && d.data.index != index,
      onAcceptWithDetails: (d) => onReorder(d.data.index, index),
      builder: (context, candidate, rejected) {
        final ziel = candidate.isNotEmpty;
        return Draggable<({int gruppe, int index})>(
          data: (gruppe: gruppenIndex, index: index),
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(opacity: 0.9, child: knoten),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: knoten),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: ziel
                    ? theme.colorScheme.primary
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: knoten,
          ),
        );
      },
    );
  }
}

/// Ein Maschinen-Knoten im Fließdiagramm — tippen öffnet die Details.
class _ProzessKnoten extends ConsumerWidget {
  const _ProzessKnoten({
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
    final dark = theme.brightness == Brightness.dark;

    // Maschinenname auflösen: Maschine > Legacy-Text > Prozessschritt
    String name;
    final mid = step.maschineId;
    if (mid != null) {
      name = ref.watch(machineProvider(mid)).valueOrNull?.name ??
          'Schritt $nummer';
    } else if (step.maschine != null && step.maschine!.trim().isNotEmpty) {
      name = step.maschine!;
    } else if (step.prozessschritt != null &&
        step.prozessschritt!.trim().isNotEmpty) {
      name = step.prozessschritt!;
    } else {
      name = 'Schritt $nummer';
    }

    final hatDaten = step.basisMitarbeiter > 0 ||
        step.basisMengeKg > 0 ||
        step.basisDauerMinuten > 0 ||
        (step.fixZeitMinuten ?? 0) > 0;
    final accent = dark ? const Color(0xFF66BB6A) : const Color(0xFF2E7D32);

    return InkWell(
      onTap: () => _zeigeSchrittDetail(
        context,
        productId: productId,
        stepId: step.id,
        fallback: step,
        nummer: nummer,
        onUpdated: onUpdated,
      ),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: hatDaten
              ? accent.withValues(alpha: dark ? 0.20 : 0.10)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hatDaten
                ? accent.withValues(alpha: 0.55)
                : theme.dividerColor,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.25 : 0.06),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.drag_indicator,
                  size: 14,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                ),
                const SizedBox(width: 3),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: farbe.withValues(alpha: dark ? 0.30 : 0.15),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    '$nummer',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: dark ? Colors.white : farbe,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (hatDaten) ...[
                  const SizedBox(width: 5),
                  Icon(Icons.check_circle, size: 14, color: accent),
                ],
              ],
            ),
            if (step.prozessschritt != null &&
                step.prozessschritt!.trim().isNotEmpty &&
                step.prozessschritt != name)
              Padding(
                padding: const EdgeInsets.only(left: 17, top: 1),
                child: Text(
                  step.prozessschritt!,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Öffnet die volle Detailansicht eines Prozessschritts als Bottom-Sheet.
void _zeigeSchrittDetail(
  BuildContext context, {
  required String productId,
  required String stepId,
  required ProductStep fallback,
  required int nummer,
  required VoidCallback onUpdated,
}) {
  final container = ProviderScope.containerOf(context);
  showSheetOhneAnimation<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 820),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => UncontrolledProviderScope(
      container: container,
      child: _SchrittDetailSheet(
        productId: productId,
        stepId: stepId,
        fallback: fallback,
        nummer: nummer,
        onUpdated: onUpdated,
      ),
    ),
  );
}

/// Inhalt des Schritt-Detail-Sheets — zeigt den bestehenden Maschinen-Block
/// (Kennwerte, Plattenschema, Parameter) und bleibt durch das Watching des
/// Steps-Providers auch nach Bearbeitungen aktuell.
class _SchrittDetailSheet extends ConsumerWidget {
  const _SchrittDetailSheet({
    required this.productId,
    required this.stepId,
    required this.fallback,
    required this.nummer,
    required this.onUpdated,
  });

  final String productId;
  final String stepId;
  final ProductStep fallback;
  final int nummer;
  final VoidCallback onUpdated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stepsAsync = ref.watch(productStepsProvider(productId));
    final steps = stepsAsync.valueOrNull;
    ProductStep aktuell = fallback;
    if (steps != null) {
      for (final s in steps) {
        if (s.id == stepId) {
          aktuell = s;
          break;
        }
      }
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: _MaschinenBlock(
          step: aktuell,
          stepNumber: nummer,
          onUpdated: onUpdated,
        ),
      ),
    );
  }
}


