import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/services/auto_backup_trigger.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/fehler_text.dart';
import '../daten/dateien.dart';
import '../rezepturen/rezeptur_screen.dart' show TextFeld;
import 'fliessdiagramm_liste.dart';
import 'projekt_repository.dart';

export 'fliessdiagramm_liste.dart' show fdText, fliessdiagrammeAusText;

// Die Liste der Fließdiagramme pflegen: einfügen, anlegen, umbenennen,
// ordnen, löschen. Ein Projekt wählt daraus sein Fließdiagramm; die
// Diagramme selbst pflegt die Qualitätssicherung.

/// Ab so vielen Fließdiagrammen gibt es ein Suchfeld.
const int _sucheAb = 8;

/// Die Liste der Fließdiagramme bearbeiten.
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
  final _suche = TextEditingController();
  bool _einfuegen = false;

  /// Was beim Einfügen oder Aufräumen herauskam.
  ({String text, StatusArt art})? _meldung;

  @override
  void dispose() {
    _id.dispose();
    _bezeichnung.dispose();
    _liste.dispose();
    _suche.dispose();
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
      _meldung = (
        text: eintraege.length == 1
            ? '1 Fließdiagramm übernommen.'
            : '${eintraege.length} Fließdiagramme übernommen.',
        art: StatusArt.ok,
      );
    });
  }

  Future<void> _altePdfsEntfernen(List<String> ids) async {
    final dateien = ref.read(entwicklungDateienProvider);
    ({String text, StatusArt art}) meldung;
    try {
      await fdAltePdfsEntfernen(dateien, ids);
      _gesichert();
      meldung = (
        text: ids.length == 1 ? '1 PDF entfernt.' : '${ids.length} PDFs entfernt.',
        art: StatusArt.ok,
      );
    } catch (e) {
      meldung = (
        text: 'Die PDFs ließen sich nicht entfernen: ${fehlerText(e)}',
        art: StatusArt.fehler,
      );
    }
    if (mounted) setState(() => _meldung = meldung);
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
    final repo = _repo;
    final verwendet = await repo.fliessdiagrammVerwendungen(f.id);
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
    await repo.fliessdiagrammLoeschen(f.id);
    if (mounted) _gesichert();
  }

  Widget _zeile(BuildContext context, List<Fliessdiagramm> alle, int i) {
    final theme = Theme.of(context);
    final f = alle[i];
    return Padding(
      key: ValueKey(f.id),
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 84,
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
          PopupMenuButton<VoidCallback>(
            tooltip: 'Mehr zu ${f.id}',
            icon: const Icon(Icons.more_vert, size: 18),
            onSelected: (aktion) => aktion(),
            itemBuilder: (_) => [
              if (i > 0)
                PopupMenuItem(
                  value: () => _verschieben(alle, i, i - 1),
                  child: const Text('Nach oben'),
                ),
              if (i < alle.length - 1)
                PopupMenuItem(
                  value: () => _verschieben(alle, i, i + 1),
                  child: const Text('Nach unten'),
                ),
              PopupMenuItem(
                value: () => _loeschen(f),
                child: const Text('Löschen'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _einfuegenFeld() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('fd-liste'),
            controller: _liste,
            autofocus: true,
            minLines: 4,
            maxLines: 10,
            decoration: const InputDecoration(
              labelText: 'Liste einfügen',
              helperText: 'Je Zeile Kennung und Bezeichnung, etwa „FD_101 '
                  'Schnitzel paniert". Vorhandene Kennungen bekommen die '
                  'neue Bezeichnung.',
              helperMaxLines: 2,
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
        ],
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final alle = ref.watch(fliessdiagrammeProvider).valueOrNull ??
        const <Fliessdiagramm>[];
    final altePdfs =
        ref.watch(fliessdiagrammAltePdfsProvider).valueOrNull ?? const [];
    final suche = _suche.text.trim().toLowerCase();
    final sichtbar = [
      for (final (i, f) in alle.indexed)
        if (suche.isEmpty ||
            f.id.toLowerCase().contains(suche) ||
            f.bezeichnung.toLowerCase().contains(suche))
          i,
    ];
    final meldung = _meldung;
    return AlertDialog(
      title: const Text('Fließdiagramme'),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Die Liste, aus der ein Projekt sein Fließdiagramm wählt. Die '
              'Diagramme selbst pflegt die Qualitätssicherung.',
              style: grau,
            ),
            if (altePdfs.isNotEmpty) ...[
              const SizedBox(height: 10),
              HinweisBox(
                'Aus einer früheren Version liegen noch '
                '${altePdfs.length == 1 ? 'ein PDF' : '${altePdfs.length} PDFs'} '
                'von Fließdiagrammen in der App. Gebraucht werden sie nicht '
                'mehr.',
                aktion: TextButton(
                  onPressed: () => _altePdfsEntfernen(altePdfs),
                  child: const Text('Entfernen'),
                ),
              ),
            ],
            if (meldung != null) ...[
              const SizedBox(height: 10),
              HinweisBox(
                meldung.text,
                art: meldung.art,
                onSchliessen: () => setState(() => _meldung = null),
              ),
            ],
            const SizedBox(height: 10),
            if (alle.length > _sucheAb) ...[
              TextField(
                key: const ValueKey('fd-suche'),
                controller: _suche,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                  hintText: 'Kennung oder Bezeichnung suchen',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 6),
            ],
            if (alle.isEmpty && !_einfuegen)
              LeerHinweis(
                'Noch keine Fließdiagramme. Am schnellsten: die Liste '
                'einfügen — je Zeile Kennung und Bezeichnung.',
                icon: Icons.account_tree_outlined,
                aktion: FilledButton.icon(
                  onPressed: () => setState(() => _einfuegen = true),
                  icon: const Icon(Icons.content_paste, size: 18),
                  label: const Text('Liste einfügen'),
                ),
              )
            else if (alle.isNotEmpty)
              Flexible(
                child: sichtbar.isEmpty
                    ? const LeerHinweis('Nichts gefunden.')
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final i in sichtbar) _zeile(context, alle, i),
                        ],
                      ),
              ),
            const Divider(height: 24),
            if (_einfuegen)
              _einfuegenFeld()
            else
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
