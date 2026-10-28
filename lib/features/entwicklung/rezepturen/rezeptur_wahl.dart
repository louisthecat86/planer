import 'package:flutter/material.dart';

import '../../../core/database/database.dart';
import '../daten/entwicklung_repository.dart';

/// Je Rezeptur (ID) ihr neuester Stand — der mit der höchsten Nummer.
Map<String, RezepturVersion> neuesteStaende(
  Iterable<RezepturVersion> versionen,
) {
  final neueste = <String, RezepturVersion>{};
  for (final v in versionen) {
    final bisher = neueste[v.rezepturId];
    if (bisher == null || v.nummer > bisher.nummer) neueste[v.rezepturId] = v;
  }
  return neueste;
}

/// Wählt eine Rezeptur — mit Suche nach Name und Artikelnummer. Jede Zeile
/// zeigt ihren neuesten Stand; eine Rezeptur ohne Stand lässt sich nicht
/// wählen. Gibt die Rezeptur zurück, null ohne Wahl.
class RezepturWahlDialog extends StatefulWidget {
  const RezepturWahlDialog({
    super.key,
    required this.titel,
    required this.rezepturen,
    required this.staende,
    this.hinweis,
  });

  final String titel;

  /// Was mit der gewählten Rezeptur geschieht — über der Suche.
  final String? hinweis;
  final List<Rezeptur> rezepturen;

  /// Je Rezeptur (ID) der neueste Stand.
  final Map<String, RezepturVersion> staende;

  @override
  State<RezepturWahlDialog> createState() => _RezepturWahlDialogState();
}

class _RezepturWahlDialogState extends State<RezepturWahlDialog> {
  String _suche = '';

  bool _passt(Rezeptur r) {
    final t = _suche.trim().toLowerCase();
    return t.isEmpty ||
        r.name.toLowerCase().contains(t) ||
        (r.artikelnummer ?? '').toLowerCase().contains(t);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final treffer = widget.rezepturen.where(_passt).toList();
    final hinweis = widget.hinweis;
    return AlertDialog(
      title: Text(widget.titel),
      // Feste Breite: Die Liste darunter kann ihre Breite nicht selbst
      // nennen.
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hinweis != null) ...[
              Text(
                hinweis,
                style: theme.textTheme.bodySmall?.copyWith(color: grau),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              key: const ValueKey('rezeptur-wahl-suche'),
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Suche nach Name oder Artikelnummer …',
                prefixIcon: Icon(Icons.search, size: 18),
              ),
              onChanged: (v) => setState(() => _suche = v),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 380),
                child: treffer.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          widget.rezepturen.isEmpty
                              ? 'Noch keine Rezepturen.'
                              : 'Keine Treffer.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: grau,
                          ),
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [for (final r in treffer) _zeile(r)],
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
      ],
    );
  }

  Widget _zeile(Rezeptur r) {
    final stand = widget.staende[r.id];
    final nummer = r.artikelnummer?.trim() ?? '';
    final String unterzeile;
    if (stand == null) {
      unterzeile = 'Noch kein Stand';
    } else {
      final art = stand.status == VersionStatus.abgeschlossen
          ? 'abgeschlossen'
          : 'Entwurf';
      unterzeile = 'Stand ${stand.nummer} · $art';
    }
    return ListTile(
      key: ValueKey('rezeptur-wahl-${r.id}'),
      dense: true,
      enabled: stand != null,
      leading: const Icon(Icons.menu_book_outlined),
      title: Text(nummer.isEmpty ? r.name : '${r.name} ($nummer)'),
      subtitle: Text(unterzeile),
      onTap: stand == null ? null : () => Navigator.of(context).pop(r),
    );
  }
}
