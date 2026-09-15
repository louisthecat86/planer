part of 'article_detail_screen.dart';

// ---------------------------------------------------------------------------
// Besonderheiten-Karte (Infos-Tab)
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
    final dark = theme.brightness == Brightness.dark;
    final leer = text.isEmpty;
    final akzent =
        dark ? const Color(0xFFFFB74D) : const Color(0xFFEF6C00);

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: leer
              ? theme.dividerColor
              : akzent.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                leer ? Icons.info_outline : Icons.priority_high_rounded,
                size: 20,
                color: leer
                    ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
                    : akzent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Besonderheiten',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: leer
                            ? theme.colorScheme.onSurface
                                .withValues(alpha: 0.6)
                            : akzent,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      leer
                          ? 'Keine Besonderheiten hinterlegt — tippen zum '
                              'Eintragen.'
                          : text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontStyle: leer ? FontStyle.italic : null,
                        color: leer
                            ? theme.colorScheme.onSurface
                                .withValues(alpha: 0.5)
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.edit,
                size: 16,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
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
    final theme = Theme.of(context);
    final text =
        ref.watch(productProvider(productId)).valueOrNull?.beschreibung;
    if (text == null || text.trim().isEmpty) return const SizedBox.shrink();

    final akzent = theme.brightness == Brightness.dark
        ? const Color(0xFFFFB74D)
        : const Color(0xFFE65100);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: akzent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: akzent.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.push_pin_outlined, size: 18, color: akzent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Besonderheit',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: akzent,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  text.trim(),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
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
        content: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 4,
          maxLines: 12,
          decoration: const InputDecoration(
            hintText: 'Individuelle Einstellungen dieser Maschine …\n'
                'z.B. Programm, Geschwindigkeit, Temperatur, Sonderhinweise',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
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
    final paramsAsync = ref.watch(stepParametersProvider(step.id));

    return paramsAsync.when(
      data: (params) {
        final notiz = params
            .where((p) => p.parameterName == kMaschinenNotizParam)
            .firstOrNull
            ?.wert;
        final hatText = notiz != null && notiz.trim().isNotEmpty;

        return InkWell(
          onTap: () => _bearbeiten(context, ref, notiz),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.settings_outlined,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Maschineneinstellungen',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      hatText ? Icons.edit_outlined : Icons.add,
                      size: 15,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  hatText ? notiz.trim() : 'Tippen, um Einstellungen zu erfassen …',
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.35,
                    color: hatText
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurface.withValues(alpha: 0.45),
                    fontStyle: hatText ? FontStyle.normal : FontStyle.italic,
                  ),
                ),
              ],
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
/// (das Produkt startet erst am Dampftunnel), gilt das Gegenteil — dann
/// sind Menge, Zeit und Personal hier eigenständig zu pflegen.
class _InlineHinweis extends ConsumerWidget {
  const _InlineHinweis({required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final steps = ref.watch(productStepsProvider(productId)).valueOrNull;
    if (steps == null) return const SizedBox.shrink();

    // Hat der Artikel einen Bratstraßen-Schritt?
    var hatBratstrasse = false;
    for (final st in steps) {
      final m = st.maschine ?? '';
      if (_istBratstrasseMaschine(m)) {
        hatBratstrasse = true;
        break;
      }
    }

    final farbe = hatBratstrasse
        ? theme.colorScheme.primary
        : (theme.brightness == Brightness.dark
            ? const Color(0xFFFFB74D)
            : const Color(0xFFE65100));
    final text = hatBratstrasse
        ? 'Läuft inline hinter der Bratstraße: Menge und Produktionszeit '
            'entsprechen der Bratstraße, eigenes Personal ist hier nicht '
            'nötig.'
        : 'Produktion startet am Dampftunnel (keine Bratstraße im Prozess) — '
            'Menge, Zeit und Personal hier eigenständig pflegen.';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: farbe.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: farbe.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            hatBratstrasse ? Icons.link : Icons.play_circle_outline,
            size: 16,
            color: farbe,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}
