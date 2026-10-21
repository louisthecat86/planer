import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/services/auto_backup_trigger.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/fehler_text.dart';
import '../../../core/utils/format.dart';
import '../rezepturen/rezeptur_screen.dart' show TextFeld;
import 'datei_aktionen.dart';
import 'fliessdiagramm_dateien.dart';
import 'fliessdiagramm_dienst.dart';
import 'projekt_repository.dart';

// Die Fließdiagramme pflegen: als PDFs einlesen (einzeln oder als ZIP),
// öffnen, ältere Fassungen nachsehen, von Hand anlegen und ordnen. Liste
// und PDFs gehören zu den Entwicklungsdaten (verschlüsselt im Backup) und
// stehen nicht im Code — jede Firma hat ihre eigenen.

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

/// „PDF · Stand 31.07.2026 · 2 Fassungen" — null ohne PDF.
String? fdPdfHinweis(List<FdFassung>? fassungen) {
  final neueste = fassungen?.firstOrNull;
  if (fassungen == null || neueste == null) return null;
  return [
    'PDF · Stand ${Format.datum(neueste.stand)}',
    if (fassungen.length > 1) '${fassungen.length} Fassungen',
  ].join(' · ');
}

/// Ab so vielen Fließdiagrammen gibt es ein Suchfeld.
const int _sucheAb = 8;

/// Fließdiagramme einlesen, öffnen, anlegen, umbenennen, ordnen und
/// löschen.
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

  /// Beim Einlesen: gespeicherte und alle PDFs.
  (int, int)? _fortschritt;

  /// Was beim Einlesen oder Hinzufügen herauskam.
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

  Future<void> _einlesen() async {
    final dienst = ref.read(fliessdiagrammDienstProvider);
    final backup = ref.read(autoBackupTriggerProvider);
    final gewaehlt = await dateienWaehlen(
      context,
      titel: 'Fließdiagramme einlesen (PDF oder ZIP)',
      endungen: const ['pdf', 'zip'],
    );
    if (gewaehlt.isEmpty || !mounted) return;
    final pdfs = <FdDatei>[];
    final fehler = <String>[];
    for (final d in gewaehlt) {
      if (d.name.toLowerCase().endsWith('.zip')) {
        try {
          pdfs.addAll(pdfsAusZip(d.inhalt));
        } on FormatException catch (e) {
          fehler.add('${d.name}: ${e.message}');
        }
      } else {
        pdfs.add((name: d.name, inhalt: d.inhalt));
      }
    }
    setState(() {
      _meldung = null;
      _fortschritt = (0, pdfs.length);
    });
    ({String text, StatusArt art}) meldung;
    try {
      final plan = await dienst.einlesen(
        pdfs,
        fortschritt: (fertig, gesamt) {
          if (mounted) setState(() => _fortschritt = (fertig, gesamt));
        },
      );
      backup.fireDebounced(reason: 'Fließdiagramme');
      final etwas = plan.anlegen.isNotEmpty ||
          plan.speichern.isNotEmpty ||
          plan.vorhanden > 0;
      meldung = (
        text: [...fehler, plan.text].join('\n'),
        art: etwas && fehler.isEmpty && plan.uebersprungen.isEmpty
            ? StatusArt.ok
            : StatusArt.warnung,
      );
    } catch (e) {
      meldung = (
        text: 'Die PDFs ließen sich nicht einlesen: ${fehlerText(e)}',
        art: StatusArt.fehler,
      );
    }
    if (!mounted) return;
    setState(() {
      _fortschritt = null;
      _meldung = meldung;
    });
  }

  Future<void> _pdfHinzufuegen(String fdId) async {
    final dienst = ref.read(fliessdiagrammDienstProvider);
    final backup = ref.read(autoBackupTriggerProvider);
    final gewaehlt = await dateienWaehlen(
      context,
      titel: 'PDF zu $fdId wählen',
      endungen: const ['pdf'],
      mehrere: false,
    );
    final d = gewaehlt.firstOrNull;
    if (d == null) return;
    ({String text, StatusArt art}) meldung;
    try {
      await dienst.pdfHinzufuegen(fdId, d.name, d.inhalt);
      backup.fireDebounced(reason: 'Fließdiagramme');
      meldung = (text: '${d.name} liegt bei $fdId.', art: StatusArt.ok);
    } catch (e) {
      meldung = (
        text: 'Das PDF ließ sich nicht ablegen: ${fehlerText(e)}',
        art: StatusArt.fehler,
      );
    }
    if (mounted) setState(() => _meldung = meldung);
  }

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
        text: '${eintraege.length} Fließdiagramme übernommen.',
        art: StatusArt.ok,
      );
    });
  }

  Future<void> _verschieben(List<Fliessdiagramm> alle, int i, int j) async {
    if (j < 0 || j >= alle.length) return;
    final ids = [for (final f in alle) f.id];
    final x = ids.removeAt(i);
    ids.insert(j, x);
    await _repo.fliessdiagrammeOrdnen(ids);
    _gesichert();
  }

  Future<void> _loeschen(Fliessdiagramm f, int pdfs) async {
    final repo = _repo;
    final dienst = ref.read(fliessdiagrammDienstProvider);
    final verwendet = await repo.fliessdiagrammVerwendungen(f.id);
    if (!mounted) return;
    final ja = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${f.id} löschen?'),
        content: Text(
          [
            verwendet == 0
                ? 'Kein Projekt nennt dieses Fließdiagramm.'
                : '$verwendet ${verwendet == 1 ? 'Projekt nennt' : 'Projekte nennen'} '
                    'es weiter — dort steht dann nur noch die Kennung.',
            if (pdfs > 0)
              pdfs == 1
                  ? 'Sein PDF wird mitgelöscht.'
                  : 'Seine $pdfs PDFs werden mitgelöscht.',
          ].join('\n'),
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
    await dienst.pdfsLoeschen(f.id);
    if (mounted) _gesichert();
  }

  Widget _zeile(
    BuildContext context,
    List<Fliessdiagramm> alle,
    int i,
    List<FdFassung> fassungen,
  ) {
    final theme = Theme.of(context);
    final f = alle[i];
    final neueste = fassungen.firstOrNull;
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
              hinweis: fdPdfHinweis(fassungen),
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
            tooltip: neueste == null ? 'Noch kein PDF' : 'PDF öffnen',
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            onPressed: neueste == null
                ? null
                : () => dateiOeffnen(context, ref, neueste.datei),
          ),
          PopupMenuButton<VoidCallback>(
            tooltip: 'Mehr zu ${f.id}',
            icon: const Icon(Icons.more_vert, size: 18),
            onSelected: (aktion) => aktion(),
            itemBuilder: (_) => [
              for (final a in fassungen.skip(1))
                PopupMenuItem(
                  value: () => dateiOeffnen(context, ref, a.datei),
                  child: Text('Fassung vom ${Format.datum(a.stand)} öffnen'),
                ),
              if (fassungen.length > 1) const PopupMenuDivider(),
              PopupMenuItem(
                value: () => _pdfHinzufuegen(f.id),
                child: const Text('PDF hinzufügen…'),
              ),
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
                value: () => _loeschen(f, fassungen.length),
                child: const Text('Löschen'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final alle = ref.watch(fliessdiagrammeProvider).valueOrNull ??
        const <Fliessdiagramm>[];
    final fassungen = ref.watch(fliessdiagrammFassungenProvider).valueOrNull ??
        const <String, List<FdFassung>>{};
    final suche = _suche.text.trim().toLowerCase();
    final sichtbar = [
      for (final (i, f) in alle.indexed)
        if (suche.isEmpty ||
            f.id.toLowerCase().contains(suche) ||
            f.bezeichnung.toLowerCase().contains(suche))
          i,
    ];
    final fortschritt = _fortschritt;
    final meldung = _meldung;
    return AlertDialog(
      title: const Text('Fließdiagramme'),
      content: SizedBox(
        width: 680,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Liste und PDFs stehen nur in den Entwicklungsdaten dieses '
              'Rechners und im verschlüsselten Backup.',
              style: grau,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: fortschritt == null ? _einlesen : null,
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: const Text('PDFs einlesen…'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Einzeln oder als ZIP. Der Dateiname gibt Kennung, '
                    'Bezeichnung und Stand, etwa „FD_001 Gewürze 260615.pdf".',
                    style: grau,
                  ),
                ),
              ],
            ),
            if (fortschritt != null) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: fortschritt.$2 == 0
                    ? null
                    : fortschritt.$1 / fortschritt.$2,
              ),
              const SizedBox(height: 4),
              Text(
                fortschritt.$2 == 0
                    ? 'Lese …'
                    : 'Speichere PDF ${fortschritt.$1} von ${fortschritt.$2} …',
                style: grau,
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
            Flexible(
              child: alle.isEmpty
                  ? const LeerHinweis(
                      'Noch keine Fließdiagramme — PDFs einlesen oder unten '
                      'von Hand anlegen.',
                      icon: Icons.account_tree_outlined,
                    )
                  : sichtbar.isEmpty
                      ? const LeerHinweis('Nichts gefunden.')
                      : ListView(
                          shrinkWrap: true,
                          children: [
                            for (final i in sichtbar)
                              _zeile(
                                context,
                                alle,
                                i,
                                fassungen[alle[i].id] ?? const [],
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
