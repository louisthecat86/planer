import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/prozess_vorlagen.dart';
import '../../core/ui/bausteine.dart';
import 'vorlage_anzeige.dart';

/// Lässt eine Vorlage für den Artikel [bezeichnung] wählen — die passenden
/// stehen oben. [anhaengen]: Der Artikel hat schon Schritte, die neuen
/// kommen dahinter. Gibt die gewählte Vorlage zurück.
Future<ProzessVorlage?> vorlageWaehlen(
  BuildContext context, {
  required String bezeichnung,
  bool anhaengen = false,
}) =>
    showDialog<ProzessVorlage>(
      context: context,
      builder: (_) => VorlageWaehlenDialog(
        bezeichnung: bezeichnung,
        anhaengen: anhaengen,
      ),
    );

class VorlageWaehlenDialog extends ConsumerStatefulWidget {
  const VorlageWaehlenDialog({
    super.key,
    required this.bezeichnung,
    this.anhaengen = false,
  });

  final String bezeichnung;
  final bool anhaengen;

  @override
  ConsumerState<VorlageWaehlenDialog> createState() =>
      _VorlageWaehlenDialogState();
}

class _VorlageWaehlenDialogState extends ConsumerState<VorlageWaehlenDialog> {
  String? _gewaehlt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final vorlagen = ref.watch(prozessVorlagenProvider).valueOrNull;
    final vorschlag = vorlagen == null
        ? null
        : vorlageVorschlagen(vorlagen, widget.bezeichnung);
    // Die passenden zuerst, dann die übrigen in ihrer Reihenfolge.
    final passend = vorschlag?.passend ?? const <ProzessVorlage>[];
    final sortiert = [
      ...passend,
      for (final v in vorlagen ?? const <ProzessVorlage>[])
        if (!passend.contains(v)) v,
    ];
    final gewaehlt = _gewaehlt ?? vorschlag?.vorlage?.id;
    final auswahl = sortiert.where((v) => v.id == gewaehlt).firstOrNull;

    return AlertDialog(
      title: const Text('Vorlage wählen'),
      content: SizedBox(
        width: 620,
        height: 460,
        child: vorlagen == null
            ? const Center(child: CircularProgressIndicator())
            : vorlagen.isEmpty
                ? const Center(
                    child: LeerHinweis(
                      'Noch keine Prozessvorlagen.\nAnlegen unter '
                      'Einstellungen → Prozessvorlagen.',
                      icon: Icons.account_tree_outlined,
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 240,
                        child: ListView(
                          children: [
                            for (final v in sortiert)
                              ListTile(
                                key: ValueKey('vorlage-wahl-${v.id}'),
                                dense: true,
                                selected: v.id == gewaehlt,
                                title: Text(v.name),
                                subtitle: passend.contains(v)
                                    ? const Text('passt zur Bezeichnung')
                                    : null,
                                onTap: () => setState(() => _gewaehlt = v.id),
                              ),
                          ],
                        ),
                      ),
                      const VerticalDivider(width: 24),
                      Expanded(
                        child: auswahl == null
                            ? Center(
                                child: Text(
                                  'Links eine Vorlage wählen.',
                                  style: grau,
                                ),
                              )
                            : SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      auswahl.name,
                                      style: theme.textTheme.titleSmall,
                                    ),
                                    const SizedBox(height: 8),
                                    VorlagenSchritte(vorlage: auswahl),
                                    const SizedBox(height: 12),
                                    Text(
                                      widget.anhaengen
                                          ? 'Der Artikel hat schon Schritte '
                                              '— diese kommen dahinter. '
                                              'Werte tragen sie keine.'
                                          : 'Die Schritte werden ohne '
                                              'Werte angelegt — gepflegt '
                                              'wird danach am Artikel.',
                                      style: grau,
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          key: const ValueKey('vorlage-anwenden'),
          onPressed: auswahl == null || auswahl.schritte.isEmpty
              ? null
              : () => Navigator.of(context).pop(auswahl),
          child: Text(widget.anhaengen ? 'Anhängen' : 'Anwenden'),
        ),
      ],
    );
  }
}
