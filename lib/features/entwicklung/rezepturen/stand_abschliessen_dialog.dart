import 'package:flutter/material.dart';

import '../../../core/database/database.dart';

// Einen Stand abschließen: Was ändert sich gegenüber dem vorigen Stand —
// das rechnet die App selbst —, und was ist neu und warum? Das steht
// danach am Stand und im Verlauf des Projekts.

/// Fragt, ob [version] abgeschlossen werden soll. Gibt den Grund zurück
/// („" ohne Grund) — null bei Abbruch.
Future<String?> standAbschliessenFragen(
  BuildContext context, {
  required RezepturVersion version,
  required List<String> aenderungen,
  int? vorherNummer,
  bool imProjekt = false,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => StandAbschliessenDialog(
        version: version,
        aenderungen: aenderungen,
        vorherNummer: vorherNummer,
        imProjekt: imProjekt,
      ),
    );

/// Das Fenster zum Abschließen eines Stands.
class StandAbschliessenDialog extends StatefulWidget {
  const StandAbschliessenDialog({
    super.key,
    required this.version,
    required this.aenderungen,
    this.vorherNummer,
    this.imProjekt = false,
  });

  final RezepturVersion version;

  /// Was sich gegenüber dem vorigen Stand ändert.
  final List<String> aenderungen;

  /// Der verglichene Stand — null beim ersten.
  final int? vorherNummer;

  /// Ob die Rezeptur zu einem Projekt gehört — dann steht der Stand auch
  /// in dessen Verlauf.
  final bool imProjekt;

  @override
  State<StandAbschliessenDialog> createState() =>
      _StandAbschliessenDialogState();
}

class _StandAbschliessenDialogState extends State<StandAbschliessenDialog> {
  late final TextEditingController _grund =
      TextEditingController(text: widget.version.notiz ?? '');

  @override
  void dispose() {
    _grund.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final v = widget.version;
    final vorher = widget.vorherNummer;
    return AlertDialog(
      icon: const Icon(Icons.lock_outline),
      title: Text('Stand ${v.nummer} abschließen?'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Der Stand wird mit allen Zutatendaten eingefroren: Spätere '
                'Änderungen am Katalog oder an Unterrezepturen verschieben ihn '
                'nicht mehr. Für Änderungen legst du danach einen neuen Stand '
                'an.',
                style: theme.textTheme.bodySmall?.copyWith(color: grau),
              ),
              const SizedBox(height: 14),
              Text(
                vorher == null
                    ? 'Der erste Stand'
                    : 'Was sich gegenüber Stand $vorher ändert',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              for (final a in widget.aenderungen)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('• $a', style: theme.textTheme.bodyMedium),
                ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('stand-grund'),
                controller: _grund,
                autofocus: true,
                minLines: 2,
                maxLines: 6,
                decoration: InputDecoration(
                  labelText: 'Was ist neu und warum?',
                  hintText: 'etwa „Salz gesenkt — der Kunde wünscht es milder"',
                  helperText: widget.imProjekt
                      ? 'Steht am Stand und im Verlauf des Projekts.'
                      : 'Steht als Notiz am Stand.',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(_grund.text.trim()),
          icon: const Icon(Icons.lock_outline, size: 18),
          label: const Text('Abschließen'),
        ),
      ],
    );
  }
}
