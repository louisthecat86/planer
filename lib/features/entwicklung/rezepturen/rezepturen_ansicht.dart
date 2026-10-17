import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database.dart';
import '../../../core/services/auto_backup_trigger.dart';
import '../../../core/theme/app_stil.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/format.dart';
import '../daten/entwicklung_repository.dart';

/// Die Rezepturen: Liste mit Suche, neue Rezeptur, Klick öffnet sie.
class RezepturenAnsicht extends ConsumerStatefulWidget {
  const RezepturenAnsicht({super.key});

  @override
  ConsumerState<RezepturenAnsicht> createState() => _RezepturenAnsichtState();
}

class _RezepturenAnsichtState extends ConsumerState<RezepturenAnsicht> {
  final _suche = TextEditingController();
  String _text = '';

  @override
  void dispose() {
    _suche.dispose();
    super.dispose();
  }

  Future<void> _neu() async {
    final id = await showDialog<String>(
      context: context,
      builder: (_) => const NeueRezepturDialog(),
    );
    if (id == null || !mounted) return;
    await oeffneRezeptur(context, id);
  }

  bool _passt(Rezeptur r) {
    final t = _text.trim().toLowerCase();
    if (t.isEmpty) return true;
    return r.name.toLowerCase().contains(t) ||
        (r.artikelnummer ?? '').toLowerCase().contains(t);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rezepturen = ref.watch(rezepturenProvider);
    final versionen = ref.watch(alleVersionenProvider).valueOrNull ?? const [];
    final jeRezeptur = <String, List<RezepturVersion>>{};
    for (final v in versionen) {
      jeRezeptur.putIfAbsent(v.rezepturId, () => []).add(v);
    }

    return rezepturen.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: HinweisBox(
          '$e',
          art: StatusArt.fehler,
          titel: 'Die Rezepturen ließen sich nicht laden',
          auswaehlbar: true,
        ),
      ),
      data: (alle) {
        final treffer = alle.where(_passt).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Row(
                children: [
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: TextField(
                        controller: _suche,
                        decoration: InputDecoration(
                          hintText: 'Suche nach Name oder Artikelnummer …',
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
                      '${treffer.length} von ${alle.length} Rezepturen',
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
                    label: const Text('Neue Rezeptur'),
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
                      final breit = c.maxWidth >= 760;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Kopf(breit: breit),
                          Expanded(
                            child: treffer.isEmpty
                                ? Center(
                                    child: LeerHinweis(
                                      alle.isEmpty
                                          ? 'Noch keine Rezepturen.'
                                          : 'Keine Treffer.',
                                      icon: alle.isEmpty
                                          ? Icons.menu_book_outlined
                                          : Icons.search_off,
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: treffer.length,
                                    itemBuilder: (_, i) => _Zeile(
                                      rezeptur: treffer[i],
                                      versionen:
                                          jeRezeptur[treffer[i].id] ?? const [],
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

/// Öffnet eine Rezeptur auf ihrer eigenen Seite.
Future<void> oeffneRezeptur(BuildContext context, String id) =>
    context.pushNamed<void>(
      'entwicklungRezeptur',
      pathParameters: {'id': id},
    );

abstract final class _Spalten {
  static const double nummer = 96;
  static const double staende = 64;
  static const double stand = 170;
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
          Expanded(child: Text('Rezeptur', style: stil)),
          if (breit) ...[
            const SizedBox(width: _Spalten.luecke),
            spalte('Art.-Nr.', _Spalten.nummer),
            spalte('Stände', _Spalten.staende, rechts: true),
          ],
          const SizedBox(width: _Spalten.luecke),
          spalte('Neuester Stand', _Spalten.stand),
          if (breit) spalte('Geändert', _Spalten.datum, rechts: true),
        ],
      ),
    );
  }
}

class _Zeile extends StatelessWidget {
  const _Zeile({
    required this.rezeptur,
    required this.versionen,
    required this.breit,
  });

  final Rezeptur rezeptur;
  final List<RezepturVersion> versionen;
  final bool breit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final stil = theme.textTheme.bodyMedium;
    final r = rezeptur;
    RezepturVersion? neueste;
    for (final v in versionen) {
      if (neueste == null || v.nummer > neueste.nummer) neueste = v;
    }
    final beschreibung = r.beschreibung?.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => oeffneRezeptur(context, r.id),
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
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
                      r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: stil?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    if (beschreibung != null && beschreibung.isNotEmpty)
                      Text(
                        beschreibung,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: grau,
                        ),
                      ),
                  ],
                ),
              ),
              if (breit) ...[
                const SizedBox(width: _Spalten.luecke),
                SizedBox(
                  width: _Spalten.nummer,
                  child: Text(
                    r.artikelnummer ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: stil?.copyWith(color: grau),
                  ),
                ),
                SizedBox(
                  width: _Spalten.staende,
                  child: Text(
                    '${versionen.length}',
                    textAlign: TextAlign.right,
                    style: stil?.copyWith(color: grau),
                  ),
                ),
              ],
              const SizedBox(width: _Spalten.luecke),
              SizedBox(
                width: _Spalten.stand,
                child: Align(
                  alignment: Alignment.centerLeft,
                  heightFactor: 1,
                  // Passt die Marke nicht, wird sie verkleinert statt
                  // zu überlaufen.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: neueste == null
                        ? Text('—', style: stil?.copyWith(color: grau))
                        : StandMarke(version: neueste),
                  ),
                ),
              ),
              if (breit)
                SizedBox(
                  width: _Spalten.datum,
                  child: Text(
                    Format.datum(r.updatedAt),
                    textAlign: TextAlign.right,
                    style: stil?.copyWith(color: grau),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ein Stand als Marke: „Stand 3 · Entwurf" oder „Stand 2 · abgeschlossen".
class StandMarke extends StatelessWidget {
  const StandMarke({super.key, required this.version});

  final RezepturVersion version;

  @override
  Widget build(BuildContext context) {
    final fertig = version.status == VersionStatus.abgeschlossen;
    return StatusMarke(
      'Stand ${version.nummer} · ${fertig ? 'abgeschlossen' : 'Entwurf'}',
      art: fertig ? StatusArt.ok : StatusArt.info,
      icon: fertig ? Icons.lock_outline : Icons.edit_outlined,
    );
  }
}

/// Eine neue Rezeptur: Name, Artikelnummer, Beschreibung. Gibt die ID
/// zurück.
class NeueRezepturDialog extends ConsumerStatefulWidget {
  const NeueRezepturDialog({super.key, this.projektId, this.vorschlag});

  /// Das Projekt, zu dem die Rezeptur gehört.
  final String? projektId;

  /// Name zum Vorbelegen.
  final String? vorschlag;

  @override
  ConsumerState<NeueRezepturDialog> createState() =>
      _NeueRezepturDialogState();
}

class _NeueRezepturDialogState extends ConsumerState<NeueRezepturDialog> {
  late final TextEditingController _name;
  final _nummer = TextEditingController();
  final _beschreibung = TextEditingController();
  bool _speichert = false;
  String? _fehler;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.vorschlag ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _nummer.dispose();
    _beschreibung.dispose();
    super.dispose();
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
      final nummer = _nummer.text.trim();
      final beschreibung = _beschreibung.text.trim();
      final id = await ref.read(entwicklungRepositoryProvider).rezepturAnlegen(
            name: name,
            artikelnummer: nummer.isEmpty ? null : nummer,
            beschreibung: beschreibung.isEmpty ? null : beschreibung,
            projektId: widget.projektId,
          );
      ref
          .read(autoBackupTriggerProvider)
          .fireDebounced(reason: 'Rezeptur angelegt');
      if (mounted) Navigator.of(context).pop(id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _speichert = false;
        _fehler = 'Anlegen fehlgeschlagen: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fehler = _fehler;
    return AlertDialog(
      title: const Text('Neue Rezeptur'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
              onSubmitted: (_) => _anlegen(),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nummer,
              decoration: const InputDecoration(labelText: 'Artikelnummer'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _beschreibung,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Beschreibung'),
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
