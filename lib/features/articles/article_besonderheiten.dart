part of 'article_detail_screen.dart';

// ---------------------------------------------------------------------------
// Besonderheiten (Infos-Tab und Prozess-Tab)
//
// Zeigt den Freitext aus dem Excel-Block „Sonstige Informationen".
// Wird beim Import gelesen und beim Export zurückgeschrieben.
// ---------------------------------------------------------------------------

class _BesonderheitenKarte extends StatelessWidget {
  const _BesonderheitenKarte({required this.text, required this.onEdit});

  final String text;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final leer = text.isEmpty;

    return Bereich(
      titel: 'Besonderheiten',
      // Die Stecknadel steht gefüllt an der Hinweisfläche darunter.
      icon: Icons.info_outline,
      aktionen: [
        TextButton.icon(
          onPressed: onEdit,
          icon: Icon(leer ? Icons.add : Icons.edit_outlined, size: 16),
          label: Text(leer ? 'Eintragen' : 'Bearbeiten'),
        ),
      ],
      innenAbstand: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: leer
          ? Text(
              'Keine Besonderheiten hinterlegt.',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          // Gefüllt in der Warnfarbe — dieselbe Hinweisfläche wie im
          // Prozess-Tab, damit man sie dort sofort wiedererkennt.
          : HinweisBox(
              text,
              art: StatusArt.warnung,
              icon: Icons.push_pin_outlined,
              auswaehlbar: true,
              gross: true,
            ),
    );
  }
}

/// Zeigt die Besonderheiten des Artikels (Freitext aus "Sonstige
/// Informationen") direkt im Prozess-Tab - dort, wo damit gearbeitet wird.
/// Ist nichts hinterlegt, erscheint nichts.
class _BesonderheitBanner extends ConsumerWidget {
  const _BesonderheitBanner({required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text =
        ref.watch(productProvider(productId)).valueOrNull?.beschreibung;
    if (text == null || text.trim().isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: HinweisBox(
        text.trim(),
        art: StatusArt.warnung,
        icon: Icons.push_pin_outlined,
        titel: 'Besonderheit',
        auswaehlbar: true,
        gross: true,
      ),
    );
  }
}

/// Freies Notizfeld „Maschineneinstellungen" für einen Schritt.
///
/// Speichert den Text als Parameterzeile [kMaschinenNotizParam] in der
/// Gruppe [kMaschinenNotizGruppe] — dadurch fließt er ohne Sonderbehandlung
/// durch Import und Export (eigener Block in der Excel).
class _MaschinenNotizFeld extends ConsumerWidget {
  const _MaschinenNotizFeld({required this.step, required this.onUpdated});

  final ProductStep step;
  final VoidCallback onUpdated;

  Future<void> _bearbeiten(
    BuildContext context,
    WidgetRef ref,
    String? aktuell,
  ) async {
    final ctrl = TextEditingController(text: aktuell ?? '');
    final neu = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Maschineneinstellungen'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            minLines: 4,
            maxLines: 12,
            decoration: const InputDecoration(
              hintText: 'Individuelle Einstellungen dieser Maschine …\n'
                  'z.B. Programm, Geschwindigkeit, Temperatur, '
                  'Sonderhinweise',
              alignLabelWithHint: true,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: const Text('Speichern'),
          ),
        ],
      ),
    ).whenComplete(ctrl.dispose);
    if (neu == null) return;

    final db = ref.read(databaseProvider);
    final paramsAsync = ref.read(stepParametersProvider(step.id));
    final vorhanden = paramsAsync.valueOrNull
        ?.where((p) => p.parameterName == kMaschinenNotizParam)
        .firstOrNull;
    final wert = neu.trim().isEmpty ? null : neu.trim();

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
              parameterGruppe: const Value(kMaschinenNotizGruppe),
              parameterName: const Value(kMaschinenNotizParam),
              wert: Value(wert),
              reihenfolge: const Value(50),
              istCustom: const Value(false),
            ),
          );
    }
    ref.read(autoBackupTriggerProvider).fireDebounced(
          reason: 'Maschineneinstellungen geändert',
        );
    ref.invalidate(stepParametersProvider(step.id));
    onUpdated();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final paramsAsync = ref.watch(stepParametersProvider(step.id));

    return paramsAsync.when(
      data: (params) {
        final notiz = params
            .where((p) => p.parameterName == kMaschinenNotizParam)
            .firstOrNull
            ?.wert;
        final text = notiz?.trim() ?? '';
        final hatText = text.isNotEmpty;

        // Material statt bemalter Box: Die Tipp-Welle malt auf das
        // nächste Material und wäre unter einer weißen Box unsichtbar.
        return Material(
          color: theme.colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: AppMasse.ecken,
            side: BorderSide(color: theme.colorScheme.outline),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _bearbeiten(context, ref, notiz),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.settings_outlined, size: 16, color: grau),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Maschineneinstellungen',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(
                        hatText ? Icons.edit_outlined : Icons.add,
                        size: 16,
                        color: grau,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    hatText ? text : 'Tippen, um Einstellungen zu erfassen …',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.35,
                      color: hatText ? theme.colorScheme.onSurface : grau,
                      fontStyle:
                          hatText ? FontStyle.normal : FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
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
      error: (e, _) => const SizedBox.shrink(),
    );
  }
}

/// Hinweis am Dampftunnel-Schritt.
///
/// Läuft der Artikel über die Bratstraße, passiert er den Dampftunnel
/// automatisch inline: Menge und Produktionszeit sind dieselben, und es
/// wird dort kein eigenes Personal gebunden. Fehlt die Bratstraße
/// (das Produkt startet erst am Dampftunnel), ist das Personal hier
/// eigenständig zu pflegen. Zeiten gibt es an der Anlage keine — sie
/// kommen aus den Leistungsdaten der Abteilung.
class _InlineHinweis extends ConsumerWidget {
  const _InlineHinweis({required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final steps = ref.watch(productStepsProvider(productId)).valueOrNull;
    if (steps == null) return const SizedBox.shrink();

    // Hat der Artikel einen Bratstraßen-Schritt?
    var hatBratstrasse = false;
    for (final st in steps) {
      final m = st.maschine ?? '';
      if (istBratstrasseMaschine(m)) {
        hatBratstrasse = true;
        break;
      }
    }

    // Blau: alles geregelt, nur zur Info. Orange: hier ist etwas zu tun.
    final text = hatBratstrasse
        ? 'Läuft inline hinter der Bratstraße: Menge und Produktionszeit '
            'entsprechen der Bratstraße, eigenes Personal ist hier nicht '
            'nötig.'
        : 'Produktion startet am Dampftunnel (keine Bratstraße im Prozess) — '
            'Personal hier eigenständig pflegen.';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: HinweisBox(
        text,
        art: hatBratstrasse ? StatusArt.info : StatusArt.warnung,
        icon: hatBratstrasse ? Icons.link : Icons.play_circle_outline,
      ),
    );
  }
}
