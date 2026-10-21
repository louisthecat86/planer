import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/services/auto_backup_trigger.dart';
import '../../../core/ui/bausteine.dart';
import '../rezepturen/rezeptur_screen.dart' show TextFeld;
import 'projekt_repository.dart';

// Die Liste der Fließdiagramme pflegen. Sie gehört zu den
// Entwicklungsdaten (verschlüsselt im Backup) und steht nicht im Code —
// jede Firma hat ihre eigenen Nummern und Bezeichnungen.

/// Liest eine eingefügte Liste: je Zeile Kennung und Bezeichnung, getrennt
/// durch Tabulator, Semikolon oder Leerzeichen — etwa
/// „FD_001 Fließdiagramm Gewürze". Leere Zeilen fallen weg; ohne
/// Bezeichnung gilt die Kennung.
List<({String id, String bezeichnung})> fliessdiagrammeAusText(String text) {
  final ergebnis = <({String id, String bezeichnung})>[];
  final gesehen = <String>{};
  for (final roh in text.split(RegExp(r'\r?\n'))) {
    final zeile = roh.trim();
    if (zeile.isEmpty) continue;
    final trenner = RegExp(r'\t|;').firstMatch(zeile);
    final teile = zeile.split(RegExp(r'\s+'));
    final id = trenner == null
        ? teile.first
        : zeile.substring(0, trenner.start).trim();
    // „FD_001 – Gewürze" oder „FD_001: Gewürze".
    final rest = (trenner == null
            ? teile.skip(1).join(' ')
            : zeile.substring(trenner.end))
        .trim()
        .replaceFirst(RegExp(r'^[-–:]\s*'), '')
        .trim();
    if (id.isEmpty || !gesehen.add(id)) continue;
    ergebnis.add((id: id, bezeichnung: rest.isEmpty ? id : rest));
  }
  return ergebnis;
}

/// Fließdiagramme anlegen, umbenennen, ordnen, löschen und als Liste
/// einfügen.
class FliessdiagrammeDialog extends ConsumerStatefulWidget {
  const FliessdiagrammeDialog({super.key});

  @override
  ConsumerState<FliessdiagrammeDialog> createState() =>
      _FliessdiagrammeDialogState();
}

class _FliessdiagrammeDialogState
    extends ConsumerState<FliessdiagrammeDialog> {
  final _id = TextEditingController();
  final _bezeichnung = TextEditingController();
  final _liste = TextEditingController();
  bool _einfuegen = false;

  @override
  void dispose() {
    _id.dispose();
    _bezeichnung.dispose();
    _liste.dispose();
    super.dispose();
  }

  ProjektRepository get _repo => ref.read(projektRepositoryProvider);

  void _gesichert() => ref
      .read(autoBackupTriggerProvider)
      .fireDebounced(reason: 'Fließdiagramme');

  Future<void> _hinzufuegen() async {
    final id = _id.text.trim();
    if (id.isEmpty) return;
    final bezeichnung = _bezeichnung.text.trim();
    await _repo.fliessdiagrammSpeichern(
      id: id,
      bezeichnung: bezeichnung.isEmpty ? id : bezeichnung,
    );
    _gesichert();
    _id.clear();
    _bezeichnung.clear();
  }

  Future<void> _listeUebernehmen() async {
    final eintraege = fliessdiagrammeAusText(_liste.text);
    for (final e in eintraege) {
      await _repo.fliessdiagrammSpeichern(id: e.id, bezeichnung: e.bezeichnung);
    }
    _gesichert();
    if (!mounted) return;
    setState(() {
      _einfuegen = false;
      _liste.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${eintraege.length} Fließdiagramme übernommen.')),
    );
  }

  Future<void> _verschieben(List<Fliessdiagramm> alle, int i, int j) async {
    if (j < 0 || j >= alle.length) return;
    final ids = [for (final f in alle) f.id];
    final x = ids.removeAt(i);
    ids.insert(j, x);
    await _repo.fliessdiagrammeOrdnen(ids);
    _gesichert();
  }

  Future<void> _loeschen(Fliessdiagramm f) async {
    final verwendet = await _repo.fliessdiagrammVerwendungen(f.id);
    if (!mounted) return;
    final ja = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${f.id} löschen?'),
        content: Text(
          verwendet == 0
              ? 'Kein Projekt nennt dieses Fließdiagramm.'
              : '$verwendet ${verwendet == 1 ? 'Projekt nennt' : 'Projekte nennen'} '
                  'es weiter — dort steht dann nur noch die Kennung.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ja != true) return;
    await _repo.fliessdiagrammLoeschen(f.id);
    _gesichert();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final alle = ref.watch(fliessdiagrammeProvider).valueOrNull ??
        const <Fliessdiagramm>[];
    return AlertDialog(
      title: const Text('Fließdiagramme'),
      content: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Die Liste steht nur in den Entwicklungsdaten dieses Rechners '
              'und im verschlüsselten Backup.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: alle.isEmpty
                  ? const LeerHinweis(
                      'Noch keine Fließdiagramme.',
                      icon: Icons.account_tree_outlined,
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final (i, f) in alle.indexed)
                          Padding(
                            key: ValueKey(f.id),
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 96,
                                  child: Text(
                                    f.id,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: TextFeld(
                                    wert: f.bezeichnung,
                                    label: 'Bezeichnung',
                                    onFertig: (t) async {
                                      await _repo.fliessdiagrammSpeichern(
                                        id: f.id,
                                        bezeichnung: t.isEmpty ? f.id : t,
                                      );
                                      _gesichert();
                                    },
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Nach oben',
                                  icon: const Icon(Icons.arrow_upward, size: 16),
                                  onPressed: i == 0
                                      ? null
                                      : () => _verschieben(alle, i, i - 1),
                                ),
                                IconButton(
                                  tooltip: 'Nach unten',
                                  icon: const Icon(
                                    Icons.arrow_downward,
                                    size: 16,
                                  ),
                                  onPressed: i == alle.length - 1
                                      ? null
                                      : () => _verschieben(alle, i, i + 1),
                                ),
                                IconButton(
                                  tooltip: 'Löschen',
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 16,
                                  ),
                                  onPressed: () => _loeschen(f),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
            const Divider(height: 24),
            if (_einfuegen) ...[
              TextField(
                controller: _liste,
                minLines: 4,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: 'Liste einfügen',
                  helperText:
                      'Je Zeile Kennung und Bezeichnung, etwa „FD_001 Gewürze"',
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => setState(() => _einfuegen = false),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _listeUebernehmen,
                    child: const Text('Übernehmen'),
                  ),
                ],
              ),
            ] else
              Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _id,
                      decoration: const InputDecoration(labelText: 'Kennung'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _bezeichnung,
                      decoration:
                          const InputDecoration(labelText: 'Bezeichnung'),
                      onSubmitted: (_) => _hinzufuegen(),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Hinzufügen',
                    icon: const Icon(Icons.add),
                    onPressed: _hinzufuegen,
                  ),
                  IconButton(
                    tooltip: 'Liste einfügen',
                    icon: const Icon(Icons.content_paste),
                    onPressed: () => setState(() => _einfuegen = true),
                  ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Schließen'),
        ),
      ],
    );
  }
}
