import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database.dart';
import '../../../core/services/auto_backup_trigger.dart';
import '../../../core/theme/app_stil.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/fehler_text.dart';
import '../../../core/utils/format.dart';
import '../import/suite_import_dialog.dart';
import 'projekt_modell.dart';
import 'projekt_repository.dart';

/// Welche Projekte die Liste zeigt.
enum ProjektFilter {
  aktiv('Aktiv'),
  entwicklung('In Entwicklung'),
  validierung('Validierung'),
  produktion('In Produktion'),
  archiv('Archiv');

  const ProjektFilter(this.label);

  final String label;

  bool passt(ProjektStatus s) => switch (this) {
        ProjektFilter.aktiv => s != ProjektStatus.archiviert,
        ProjektFilter.entwicklung => s == ProjektStatus.entwicklung,
        ProjektFilter.validierung => s == ProjektStatus.validierung,
        ProjektFilter.produktion => s == ProjektStatus.produktion,
        ProjektFilter.archiv => s == ProjektStatus.archiviert,
      };
}

/// Die Farbe eines Status.
StatusArt projektStatusArt(ProjektStatus s) => switch (s) {
      ProjektStatus.entwicklung => StatusArt.info,
      ProjektStatus.validierung => StatusArt.warnung,
      ProjektStatus.produktion => StatusArt.ok,
      ProjektStatus.archiviert => StatusArt.neutral,
    };

/// Öffnet ein Projekt auf seiner eigenen Seite.
Future<void> oeffneProjekt(BuildContext context, String id) =>
    context.pushNamed<void>(
      'entwicklungProjekt',
      pathParameters: {'id': id},
    );

/// Die Projekte: Liste mit Suche und Filter nach Status.
class ProjekteAnsicht extends ConsumerStatefulWidget {
  const ProjekteAnsicht({super.key});

  @override
  ConsumerState<ProjekteAnsicht> createState() => _ProjekteAnsichtState();
}

class _ProjekteAnsichtState extends ConsumerState<ProjekteAnsicht> {
  final _suche = TextEditingController();
  String _text = '';
  ProjektFilter _filter = ProjektFilter.aktiv;

  @override
  void dispose() {
    _suche.dispose();
    super.dispose();
  }

  Future<void> _neu() async {
    final id = await showDialog<String>(
      context: context,
      builder: (_) => const NeuesProjektDialog(),
    );
    if (id == null || !mounted) return;
    await oeffneProjekt(context, id);
  }

  bool _passt(EntwicklungsProjekt p) {
    if (!_filter.passt(ProjektStatus.aus(p.status))) return false;
    final t = _text.trim().toLowerCase();
    if (t.isEmpty) return true;
    return p.name.toLowerCase().contains(t) ||
        (p.kunde ?? '').toLowerCase().contains(t) ||
        (p.artikelnummer ?? '').toLowerCase().contains(t);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final projekte = ref.watch(projekteProvider);
    return projekte.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: HinweisBox(
          fehlerText(e),
          art: StatusArt.fehler,
          titel: 'Die Projekte ließen sich nicht laden',
          auswaehlbar: true,
        ),
      ),
      data: (alle) {
        final treffer = alle.where(_passt).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Row(
                children: [
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: TextField(
                        controller: _suche,
                        decoration: InputDecoration(
                          hintText: 'Suche nach Projekt, Kunde oder '
                              'Artikelnummer …',
                          prefixIcon: const Icon(Icons.search, size: 18),
                          suffixIcon: _text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  tooltip: 'Suche leeren',
                                  onPressed: () {
                                    _suche.clear();
                                    setState(() => _text = '');
                                  },
                                ),
                        ),
                        onChanged: (v) => setState(() => _text = v),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${treffer.length} von ${alle.length} Projekten',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _neu,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Neues Projekt'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final f in ProjektFilter.values)
                    ChoiceChip(
                      label: Text(
                        '${f.label} '
                        '(${alle.where((p) => f.passt(ProjektStatus.aus(p.status))).length})',
                      ),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Material(
                  color: theme.colorScheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppMasse.ecken,
                    side: BorderSide(color: theme.colorScheme.outline),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final breit = c.maxWidth >= 860;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Kopf(breit: breit),
                          Expanded(
                            child: treffer.isEmpty
                                ? Center(
                                    child: LeerHinweis(
                                      alle.isEmpty
                                          ? 'Noch keine Projekte. Lege das '
                                              'erste an — oder übernimm die '
                                              'Projekte der alten Suite.'
                                          : 'Keine Treffer.',
                                      icon: alle.isEmpty
                                          ? Icons.folder_open_outlined
                                          : Icons.search_off,
                                      aktion: alle.isEmpty
                                          ? TextButton.icon(
                                              onPressed: () =>
                                                  suiteImportStarten(context),
                                              icon: const Icon(
                                                Icons.move_to_inbox_outlined,
                                                size: 18,
                                              ),
                                              label: const Text(
                                                'Aus der Suite übernehmen',
                                              ),
                                            )
                                          : null,
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: treffer.length,
                                    itemBuilder: (_, i) => _Zeile(
                                      projekt: treffer[i],
                                      breit: breit,
                                    ),
                                  ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

abstract final class _Spalten {
  static const double kunde = 170;
  static const double nummer = 96;
  static const double status = 130;
  static const double checkliste = 80;
  static const double datum = 90;
  static const double luecke = 12;
}

class _Kopf extends StatelessWidget {
  const _Kopf({required this.breit});

  final bool breit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stil = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurfaceVariant,
    );
    Widget spalte(String text, double breite, {bool rechts = false}) =>
        SizedBox(
          width: breite,
          child: Text(
            text,
            maxLines: 1,
            textAlign: rechts ? TextAlign.right : TextAlign.left,
            style: stil,
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: AppFarben.von(context).leiste,
        border: Border(bottom: BorderSide(color: theme.colorScheme.outline)),
      ),
      child: Row(
        children: [
          Expanded(child: Text('Projekt', style: stil)),
          const SizedBox(width: _Spalten.luecke),
          if (breit) ...[
            spalte('Kunde', _Spalten.kunde),
            const SizedBox(width: _Spalten.luecke),
            spalte('Art.-Nr.', _Spalten.nummer),
            const SizedBox(width: _Spalten.luecke),
          ],
          spalte('Status', _Spalten.status),
          if (breit) ...[
            spalte('Checkliste', _Spalten.checkliste, rechts: true),
            spalte('Geändert', _Spalten.datum, rechts: true),
          ],
        ],
      ),
    );
  }
}

class _Zeile extends StatelessWidget {
  const _Zeile({required this.projekt, required this.breit});

  final EntwicklungsProjekt projekt;
  final bool breit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final stil = theme.textTheme.bodyMedium;
    final p = projekt;
    final status = ProjektStatus.aus(p.status);
    final erledigt = checklisteAus(p.checkliste)
        .where((s) => kProjektCheckliste.any((c) => c.schluessel == s))
        .length;
    final idee = p.produktidee?.trim();
    final unterzeile = [
      if (!breit && (p.kunde ?? '').trim().isNotEmpty) p.kunde!.trim(),
      if (idee != null && idee.isNotEmpty) idee,
    ].join(' · ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => oeffneProjekt(context, p.id),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: stil?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    if (unterzeile.isNotEmpty)
                      Text(
                        unterzeile,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: grau,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: _Spalten.luecke),
              if (breit) ...[
                SizedBox(
                  width: _Spalten.kunde,
                  child: Text(
                    p.kunde ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: stil?.copyWith(color: p.kunde == null ? grau : null),
                  ),
                ),
                const SizedBox(width: _Spalten.luecke),
                SizedBox(
                  width: _Spalten.nummer,
                  child: Text(
                    p.artikelnummer ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: stil?.copyWith(color: grau),
                  ),
                ),
                const SizedBox(width: _Spalten.luecke),
              ],
              SizedBox(
                width: _Spalten.status,
                child: Align(
                  alignment: Alignment.centerLeft,
                  heightFactor: 1,
                  child: StatusMarke(
                    status.label,
                    art: projektStatusArt(status),
                  ),
                ),
              ),
              if (breit) ...[
                SizedBox(
                  width: _Spalten.checkliste,
                  child: Text(
                    '$erledigt / ${kProjektCheckliste.length}',
                    textAlign: TextAlign.right,
                    style: stil?.copyWith(color: grau),
                  ),
                ),
                SizedBox(
                  width: _Spalten.datum,
                  child: Text(
                    Format.datum(p.updatedAt),
                    textAlign: TextAlign.right,
                    style: stil?.copyWith(color: grau),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Ein neues Projekt: Name, Kunde, Artikelnummer, Idee. Gibt die ID
/// zurück.
class NeuesProjektDialog extends ConsumerStatefulWidget {
  const NeuesProjektDialog({super.key});

  @override
  ConsumerState<NeuesProjektDialog> createState() =>
      _NeuesProjektDialogState();
}

class _NeuesProjektDialogState extends ConsumerState<NeuesProjektDialog> {
  final _name = TextEditingController();
  final _kunde = TextEditingController();
  final _nummer = TextEditingController();
  final _idee = TextEditingController();
  bool _speichert = false;
  String? _fehler;

  @override
  void dispose() {
    _name.dispose();
    _kunde.dispose();
    _nummer.dispose();
    _idee.dispose();
    super.dispose();
  }

  String? _oderNull(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _anlegen() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _fehler = 'Bitte einen Namen eingeben.');
      return;
    }
    setState(() {
      _speichert = true;
      _fehler = null;
    });
    try {
      final id = await ref.read(projektRepositoryProvider).projektAnlegen(
            name: name,
            kunde: _oderNull(_kunde),
            artikelnummer: _oderNull(_nummer),
            produktidee: _oderNull(_idee),
          );
      ref
          .read(autoBackupTriggerProvider)
          .fireDebounced(reason: 'Projekt angelegt');
      if (mounted) Navigator.of(context).pop(id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _speichert = false;
        _fehler = 'Anlegen fehlgeschlagen: ${fehlerText(e)}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fehler = _fehler;
    // Kunden aus anderen Projekten zum Antippen — passend zur Eingabe.
    final eingabe = _kunde.text.trim().toLowerCase();
    final vorschlaege = ({
      for (final p in ref.watch(projekteProvider).valueOrNull ??
          const <EntwicklungsProjekt>[])
        if ((p.kunde ?? '').trim().isNotEmpty) p.kunde!.trim(),
    }.where(
      (k) => k.toLowerCase().contains(eingabe) && k.toLowerCase() != eingabe,
    ).toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())))
        .take(6)
        .toList();
    return AlertDialog(
      title: const Text('Neues Projekt'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Projektname'),
              onSubmitted: (_) => _anlegen(),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _kunde,
              decoration: const InputDecoration(labelText: 'Kunde'),
              onChanged: (_) => setState(() {}),
            ),
            if (vorschlaege.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final k in vorschlaege)
                    ActionChip(
                      label: Text(k),
                      onPressed: () => setState(() => _kunde.text = k),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _nummer,
              decoration: const InputDecoration(labelText: 'Artikelnummer'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _idee,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Produktidee'),
            ),
            if (fehler != null) ...[
              const SizedBox(height: 10),
              Text(
                fehler,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _speichert ? null : () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _speichert ? null : _anlegen,
          child: const Text('Anlegen'),
        ),
      ],
    );
  }
}
