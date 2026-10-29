import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/services/auto_backup_trigger.dart';
import '../../../core/utils/ablage_dateien.dart';
import '../../../core/utils/fehler_text.dart';
import '../mail/mail.dart';
import 'gesamtprojekt_modell.dart';
import 'projekt_modell.dart';
import 'projekt_repository.dart';

// Die Fenster rund um Gesamtprojekte: wohin etwas verschoben wird, wohin
// eine Mail auf einem Muster gehört (F46), ein neues Muster, ein Projekt
// in ein Gesamtprojekt aufnehmen.

/// „Ins Gesamtprojekt „Grill" verschoben." / „Zum Muster „A" verschoben."
String verschobenText(VerschiebeZiel z) => z.gesamtprojekt
    ? 'Ins Gesamtprojekt „${z.name}" verschoben.'
    : 'Zum Muster „${z.name}" verschoben.';

/// Fragt, wohin etwas verschoben werden soll: ins Gesamtprojekt oder zu
/// einem der Muster. Null bei „Abbrechen".
Future<VerschiebeZiel?> zielWaehlen(
  BuildContext context,
  List<VerschiebeZiel> ziele, {
  required String titel,
  String? hinweis,
}) =>
    showDialog<VerschiebeZiel>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SimpleDialog(
          title: Text(titel),
          children: [
            if (hinweis != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  hinweis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (final z in ziele)
              SimpleDialogOption(
                key: ValueKey('ziel-${z.id}'),
                onPressed: () => Navigator.of(ctx).pop(z),
                child: Row(
                  children: [
                    Icon(
                      z.gesamtprojekt
                          ? Icons.folder_outlined
                          : Icons.science_outlined,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        z.gesamtprojekt
                            ? 'Ins Gesamtprojekt „${z.name}"'
                            : 'Zum Muster „${z.name}"',
                      ),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 16, 0),
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Abbrechen'),
                ),
              ),
            ),
          ],
        );
      },
    );

/// Fragt, wohin Gezogenes auf der Seite eines Musters gehört: ins
/// Gesamtprojekt — dann sehen es alle Muster — oder nur zu diesem Muster.
/// Ist eine Mail dabei, ist das Gesamtprojekt vorgewählt (F46), sonst das
/// Muster. Gibt die ID des Ziels zurück, bei „Abbrechen" null.
Future<String?> ablageZielFragen(
  BuildContext context, {
  required Gesamtprojekt gesamtprojekt,
  required EntwicklungsProjekt muster,
  required List<AbgelegteDatei> dateien,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _AblageZielDialog(
        gesamtprojekt: gesamtprojekt,
        muster: muster,
        dateien: dateien,
      ),
    );

class _AblageZielDialog extends StatefulWidget {
  const _AblageZielDialog({
    required this.gesamtprojekt,
    required this.muster,
    required this.dateien,
  });

  final Gesamtprojekt gesamtprojekt;
  final EntwicklungsProjekt muster;
  final List<AbgelegteDatei> dateien;

  @override
  State<_AblageZielDialog> createState() => _AblageZielDialogState();
}

class _AblageZielDialogState extends State<_AblageZielDialog> {
  late final int _mails = [
    for (final d in widget.dateien)
      if (alsMail(d.name, d.inhalt) != null) d,
  ].length;
  late String _ziel =
      _mails > 0 ? widget.gesamtprojekt.id : widget.muster.id;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final andere = widget.dateien.length - _mails;
    final was = [
      if (_mails > 0) _mails == 1 ? '1 Mail' : '$_mails Mails',
      if (andere > 0) andere == 1 ? '1 Datei' : '$andere Dateien',
    ].join(' und ');
    return AlertDialog(
      title: Text('Wohin mit $was?'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, minWidth: 340),
        child: RadioGroup<String>(
          groupValue: _ziel,
          onChanged: (z) {
            if (z != null) setState(() => _ziel = z);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RadioListTile<String>(
                key: const ValueKey('ablage-gesamtprojekt'),
                value: widget.gesamtprojekt.id,
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.folder_outlined),
                title: Text(
                  'Ins Gesamtprojekt „${widget.gesamtprojekt.name}"',
                ),
                subtitle: Text(
                  'Betrifft alle Muster — steht in jedem Verlauf mit drin.',
                  style: theme.textTheme.bodySmall?.copyWith(color: grau),
                ),
              ),
              RadioListTile<String>(
                key: const ValueKey('ablage-muster'),
                value: widget.muster.id,
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.science_outlined),
                title: Text('Nur zum Muster „${widget.muster.name}"'),
                subtitle: Text(
                  'Betrifft nur dieses Muster.',
                  style: theme.textTheme.bodySmall?.copyWith(color: grau),
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
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_ziel),
          child: const Text('Ablegen'),
        ),
      ],
    );
  }
}

/// Fragt nach einem Namen — etwa beim Umbenennen. Null bei „Abbrechen".
Future<String?> nameFragen(
  BuildContext context, {
  required String titel,
  required String label,
  String name = '',
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(titel: titel, label: label, name: name),
    );

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.titel,
    required this.label,
    required this.name,
  });

  final String titel;
  final String label;
  final String name;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _fertig() {
    final t = _name.text.trim();
    if (t.isEmpty) return;
    Navigator.of(context).pop(t);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titel),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, minWidth: 320),
        child: TextField(
          controller: _name,
          autofocus: true,
          decoration: InputDecoration(labelText: widget.label),
          onSubmitted: (_) => _fertig(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(onPressed: _fertig, child: const Text('Speichern')),
      ],
    );
  }
}

/// Ein neues Muster im Gesamtprojekt: Name, Produktidee, Artikelnummer.
/// Gibt die ID des Musters zurück.
class NeuesMusterDialog extends ConsumerStatefulWidget {
  const NeuesMusterDialog({super.key, required this.gesamtprojekt, this.nr});

  final Gesamtprojekt gesamtprojekt;

  /// Das wievielte Muster — für den Vorschlag „Muster 3".
  final int? nr;

  @override
  ConsumerState<NeuesMusterDialog> createState() => _NeuesMusterDialogState();
}

class _NeuesMusterDialogState extends ConsumerState<NeuesMusterDialog> {
  late final _name = TextEditingController(
    text: widget.nr == null ? '' : 'Muster ${widget.nr}',
  );
  final _idee = TextEditingController();
  final _nummer = TextEditingController();
  bool _speichert = false;
  String? _fehler;

  @override
  void dispose() {
    _name.dispose();
    _idee.dispose();
    _nummer.dispose();
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
            produktidee: _oderNull(_idee),
            artikelnummer: _oderNull(_nummer),
            gesamtprojektId: widget.gesamtprojekt.id,
          );
      ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Muster');
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
    final kunde = widget.gesamtprojekt.kunde?.trim() ?? '';
    return AlertDialog(
      title: const Text('Neues Muster'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Im Gesamtprojekt „${widget.gesamtprojekt.name}"'
              '${kunde.isEmpty ? '' : ' für $kunde'} — mit eigenen '
              'Rezepturen, eigener Herstellung und eigener Freigabe.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('muster-name'),
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name des Musters'),
              onSubmitted: (_) => _anlegen(),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _idee,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Produktidee'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nummer,
              decoration: const InputDecoration(labelText: 'Artikelnummer'),
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

/// Nimmt ein Projekt als Muster in ein Gesamtprojekt auf: in ein
/// bestehendes oder in ein neues, das um das Projekt entsteht — dann auf
/// Wunsch mit seinen Mails, die danach alle Muster betreffen. Gibt die ID
/// des Gesamtprojekts zurück.
class InGesamtprojektDialog extends ConsumerStatefulWidget {
  const InGesamtprojektDialog({super.key, required this.projekt});

  final EntwicklungsProjekt projekt;

  @override
  ConsumerState<InGesamtprojektDialog> createState() =>
      _InGesamtprojektDialogState();
}

class _InGesamtprojektDialogState
    extends ConsumerState<InGesamtprojektDialog> {
  /// Das gewählte Gesamtprojekt — '' für ein neues.
  String? _wahl;
  late final _name = TextEditingController(text: widget.projekt.name);
  bool _mails = true;
  bool _speichert = false;
  String? _fehler;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _los(int mails) async {
    final wahl = _wahl ?? '';
    final name = _name.text.trim();
    if (wahl.isEmpty && name.isEmpty) {
      setState(() => _fehler = 'Bitte einen Namen eingeben.');
      return;
    }
    setState(() {
      _speichert = true;
      _fehler = null;
    });
    final repo = ref.read(projektRepositoryProvider);
    try {
      final String id;
      if (wahl.isEmpty) {
        id = await repo.gesamtprojektUmProjekt(
          widget.projekt.id,
          name: name,
          mailsMitnehmen: _mails && mails > 0,
        );
      } else {
        await repo.inGesamtprojektVerschieben(widget.projekt.id, wahl);
        id = wahl;
      }
      ref
          .read(autoBackupTriggerProvider)
          .fireDebounced(reason: 'Gesamtprojekt');
      if (mounted) Navigator.of(context).pop(id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _speichert = false;
        _fehler = 'Das ging nicht: ${fehlerText(e)}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final p = widget.projekt;
    final alle = [
      for (final g in ref.watch(gesamtprojekteProvider).valueOrNull ??
          const <Gesamtprojekt>[])
        if (g.id != p.gesamtprojektId) g,
    ];
    // Vorgeschlagen: ein Gesamtprojekt desselben Kunden, sonst ein neues.
    final kunde = p.kunde?.trim().toLowerCase() ?? '';
    final wahl = _wahl ??
        (kunde.isEmpty
                ? null
                : alle
                    .where((g) => (g.kunde ?? '').trim().toLowerCase() == kunde)
                    .firstOrNull
                    ?.id) ??
        '';
    final mails = (ref.watch(projektEintraegeProvider(p.id)).valueOrNull ??
            const <ProjektEintrag>[])
        .where((e) => EintragArt.aus(e.art) == EintragArt.email)
        .length;
    final fehler = _fehler;
    return AlertDialog(
      title: Text(
        p.gesamtprojektId == null
            ? 'In ein Gesamtprojekt aufnehmen'
            : 'In ein anderes Gesamtprojekt',
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, minWidth: 360),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '„${p.name}" wird ein Muster des Gesamtprojekts — mit allem, '
                'was es hat. Mails und Unterlagen des Gesamtprojekts stehen '
                'danach auch in seinem Verlauf.',
                style: theme.textTheme.bodySmall?.copyWith(color: grau),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                // Neu, sobald die Liste da ist — mit dem Vorschlag.
                key: ValueKey('gesamtprojekt-wahl-${alle.length}'),
                initialValue: wahl,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Gesamtprojekt'),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Neues Gesamtprojekt …'),
                  ),
                  for (final g in alle)
                    DropdownMenuItem(
                      value: g.id,
                      child: Text(
                        (g.kunde ?? '').trim().isEmpty
                            ? g.name
                            : '${g.name} · ${g.kunde!.trim()}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (w) => setState(() => _wahl = w ?? ''),
              ),
              if (wahl.isEmpty) ...[
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('gesamtprojekt-name'),
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Name des Gesamtprojekts',
                    helperText: 'Etwa die Anfrage: „Grillsortiment 2027"',
                  ),
                ),
                if (mails > 0) ...[
                  const SizedBox(height: 6),
                  CheckboxListTile(
                    key: const ValueKey('gesamtprojekt-mails'),
                    value: _mails,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      mails == 1
                          ? 'Die Mail ins Gesamtprojekt verschieben'
                          : 'Die $mails Mails ins Gesamtprojekt verschieben',
                    ),
                    subtitle: const Text(
                      'Mit ihren Anhängen — sie betreffen dann alle Muster.',
                    ),
                    onChanged: (v) => setState(() => _mails = v ?? false),
                  ),
                ],
              ],
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
      ),
      actions: [
        TextButton(
          onPressed: _speichert ? null : () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _speichert
              ? null
              : () {
                  _wahl = wahl;
                  _los(mails);
                },
          child: Text(wahl.isEmpty ? 'Anlegen und aufnehmen' : 'Aufnehmen'),
        ),
      ],
    );
  }
}
