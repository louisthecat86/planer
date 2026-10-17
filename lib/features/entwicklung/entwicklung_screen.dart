import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/bausteine.dart';
import 'entwicklung_zugang.dart';
import 'import/suite_import_dialog.dart';
import 'rezepturen/rezepturen_ansicht.dart';
import 'zutaten/zutaten_ansicht.dart';

/// Produktentwicklung: Projekte, Rezepturen und Zutaten — hinter einem
/// eigenen Passwort.
///
/// Gesperrt zeigt die Seite nur die Passwortabfrage — beim ersten Mal das
/// Festlegen. Offen bleibt sie, bis jemand sperrt oder die App schließt.
class EntwicklungScreen extends ConsumerWidget {
  const EntwicklungScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offen = ref.watch(entwicklungEntsperrtProvider);
    if (!offen) {
      return Scaffold(
        appBar: AppBar(title: const Text('Produktentwicklung')),
        body: const _Sperre(),
      );
    }
    return DefaultTabController(
      length: EntwicklungsReiter.values.length,
      initialIndex: ref.read(entwicklungReiterProvider).index,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Produktentwicklung'),
          actions: [
            IconButton(
              tooltip: 'Aus der Development-Suite übernehmen',
              icon: const Icon(Icons.move_to_inbox_outlined),
              onPressed: () => suiteImportStarten(context),
            ),
            IconButton(
              tooltip: 'Passwort ändern',
              icon: const Icon(Icons.password_outlined),
              onPressed: () => _passwortAendern(context, ref),
            ),
            IconButton(
              tooltip: 'Sperren',
              icon: const Icon(Icons.lock_outline),
              onPressed: () {
                ref.read(entwicklungEntsperrtProvider.notifier).state = false;
              },
            ),
            const SizedBox(width: 8),
          ],
          bottom: TabBar(
            onTap: (i) => ref.read(entwicklungReiterProvider.notifier).state =
                EntwicklungsReiter.values[i],
            tabs: [
              for (final r in EntwicklungsReiter.values)
                Tab(icon: Icon(r.icon), text: r.label),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _Folgt(
              icon: Icons.folder_open_outlined,
              titel: 'Projekte',
              text: 'Entwicklungen je Kunde mit Verlauf, Checklisten, '
                  'Dateien, Sensorik und HACCP — und der Freigabe als '
                  'Artikel im Planer.',
            ),
            RezepturenAnsicht(),
            ZutatenAnsicht(),
            _Folgt(
              icon: Icons.calculate_outlined,
              titel: 'Werkzeuge',
              text: 'Reverser und Fleischanteil-Optimierer.',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _passwortAendern(BuildContext context, WidgetRef ref) async {
    final geaendert = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _PasswortAendernDialog(zugang: ref.read(entwicklungZugangProvider)),
    );
    if (geaendert != true || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Passwort geändert.')),
    );
  }
}

/// Zeigt [child] nur, wenn die Produktentwicklung offen ist — sonst die
/// Sperre. Für die Unterseiten: Wer nach dem Sperren dorthin zurückkommt,
/// sieht erst die Passwortabfrage.
class EntwicklungGeschuetzt extends ConsumerWidget {
  const EntwicklungGeschuetzt({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(entwicklungEntsperrtProvider)
          ? child
          : const EntwicklungScreen();
}

// ---------------------------------------------------------------------------
// Gesperrt
// ---------------------------------------------------------------------------

/// Passwort festlegen (beim ersten Mal) oder eingeben.
class _Sperre extends ConsumerStatefulWidget {
  const _Sperre();

  @override
  ConsumerState<_Sperre> createState() => _SperreState();
}

class _SperreState extends ConsumerState<_Sperre> {
  final _passwort = TextEditingController();
  final _wiederholung = TextEditingController();

  /// Was gerade nicht passt — unter den Feldern angezeigt.
  String? _fehler;

  /// Die Ableitung läuft — einige Zehntelsekunden.
  bool _rechnet = false;

  @override
  void dispose() {
    _passwort.dispose();
    _wiederholung.dispose();
    super.dispose();
  }

  void _oeffne() {
    ref.read(entwicklungEntsperrtProvider.notifier).state = true;
  }

  Future<void> _entsperren() async {
    if (_rechnet) return;
    setState(() {
      _rechnet = true;
      _fehler = null;
    });
    // Öffnen heißt auch: Datenschlüssel bereitstellen und ein Backup von
    // einem anderen Rechner einspielen, das auf das Passwort gewartet hat.
    final bool stimmt;
    try {
      stimmt =
          await ref.read(entwicklungZugangProvider).oeffnen(_passwort.text);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rechnet = false;
        _fehler = 'Die Produktentwicklung ließ sich nicht öffnen: $e';
      });
      return;
    }
    if (!mounted) return;
    if (stimmt) {
      // Ein wartendes Backup ist jetzt eingespielt.
      ref.invalidate(entwicklungBackupWartetProvider);
      // Danach baut die Seite den offenen Bereich — diese Abfrage
      // verschwindet.
      _oeffne();
      return;
    }
    setState(() {
      _rechnet = false;
      _fehler = 'Das Passwort stimmt nicht.';
    });
    _passwort.clear();
  }

  Future<void> _festlegen() async {
    if (_rechnet) return;
    final fehler = passwortFehler(_passwort.text) ??
        (_passwort.text != _wiederholung.text
            ? 'Die beiden Eingaben unterscheiden sich.'
            : null);
    if (fehler != null) {
      setState(() => _fehler = fehler);
      return;
    }
    setState(() {
      _rechnet = true;
      _fehler = null;
    });
    try {
      await ref.read(entwicklungZugangProvider).festlegen(_passwort.text);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rechnet = false;
        _fehler = 'Das Passwort konnte nicht gespeichert werden: $e';
      });
      return;
    }
    if (!mounted) return;
    ref.invalidate(entwicklungPasswortGesetztProvider);
    _oeffne();
  }

  Future<void> _vergessen() async {
    final zuruecksetzen = await showDialog<bool>(
      context: context,
      builder: (_) => const _ZuruecksetzenDialog(),
    );
    if (zuruecksetzen != true || !mounted) return;
    await ref.read(entwicklungZugangProvider).zuruecksetzen();
    if (!mounted) return;
    ref.invalidate(entwicklungPasswortGesetztProvider);
    ref.invalidate(entwicklungBackupWartetProvider);
    setState(() {
      _fehler = null;
      _passwort.clear();
      _wiederholung.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final gesetzt = ref.watch(entwicklungPasswortGesetztProvider);
    return gesetzt.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: HinweisBox(
            '$e',
            art: StatusArt.fehler,
            titel: 'Der Zugang konnte nicht geprüft werden',
            auswaehlbar: true,
          ),
        ),
      ),
      data: (ja) => _abfrage(context, neu: !ja),
    );
  }

  Widget _abfrage(BuildContext context, {required bool neu}) {
    final theme = Theme.of(context);
    final fehler = _fehler;
    final backupWartet =
        !neu && (ref.watch(entwicklungBackupWartetProvider).valueOrNull ?? false);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Bereich(
            titel: neu ? 'Passwort festlegen' : 'Gesperrt',
            icon: neu ? Icons.key_outlined : Icons.lock_outline,
            innenAbstand: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  neu
                      ? 'Hier entstehen Rezepturen und Entwicklungsprojekte. '
                          'Lege ein eigenes Passwort fest — mindestens '
                          '$kPasswortMindestlaenge Zeichen.'
                      : 'Mit deinem Passwort öffnest du die '
                          'Produktentwicklung. Sie bleibt offen, bis du sie '
                          'sperrst oder die App schließt.',
                  style: theme.textTheme.bodyMedium,
                ),
                if (backupWartet) ...[
                  const SizedBox(height: 12),
                  const HinweisBox(
                    'Ein Backup von einem anderen Rechner wartet. Öffne mit '
                    'dem Passwort, das dort galt — dann werden seine '
                    'Entwicklungsdaten übernommen.',
                    titel: 'Backup wartet',
                  ),
                ],
                const SizedBox(height: 14),
                TextField(
                  controller: _passwort,
                  autofocus: true,
                  obscureText: true,
                  enabled: !_rechnet,
                  decoration: InputDecoration(
                    labelText: neu ? 'Neues Passwort' : 'Passwort',
                  ),
                  // Beim Festlegen springt Enter ins zweite Feld.
                  textInputAction:
                      neu ? TextInputAction.next : TextInputAction.done,
                  onSubmitted: neu ? null : (_) => _entsperren(),
                ),
                if (neu) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _wiederholung,
                    obscureText: true,
                    enabled: !_rechnet,
                    decoration: const InputDecoration(
                      labelText: 'Passwort wiederholen',
                    ),
                    onSubmitted: (_) => _festlegen(),
                  ),
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
                if (neu) ...[
                  const SizedBox(height: 12),
                  const HinweisBox(
                    'Ein vergessenes Passwort lässt sich nicht '
                    'wiederherstellen — sonst schützte es nichts. Bewahre es '
                    'an einem sicheren Ort auf.',
                    art: StatusArt.warnung,
                  ),
                ],
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed:
                      _rechnet ? null : (neu ? _festlegen : _entsperren),
                  // Ohne feste Farbe: Der gesperrte Knopf ist hellgrau, ein
                  // weißer Kreisel wäre darauf unsichtbar.
                  icon: _rechnet
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          neu ? Icons.check : Icons.lock_open_outlined,
                          size: 18,
                        ),
                  label: Text(neu ? 'Festlegen und öffnen' : 'Öffnen'),
                ),
                if (!neu) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _rechnet ? null : _vergessen,
                      child: const Text('Passwort vergessen?'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Passwort vergessen: zurücksetzen nur nach getippter Bestätigung.
class _ZuruecksetzenDialog extends StatefulWidget {
  const _ZuruecksetzenDialog();

  @override
  State<_ZuruecksetzenDialog> createState() => _ZuruecksetzenDialogState();
}

class _ZuruecksetzenDialogState extends State<_ZuruecksetzenDialog> {
  static const String _wort = 'ZURÜCKSETZEN';
  final _eingabe = TextEditingController();

  @override
  void dispose() {
    _eingabe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final passt = _eingabe.text.trim().toUpperCase() == _wort;
    return AlertDialog(
      icon: Icon(Icons.lock_reset, color: theme.colorScheme.error),
      title: const Text('Produktentwicklung zurücksetzen?'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Das Passwort lässt sich nicht wiederherstellen. Du kannst die '
              'Produktentwicklung zurücksetzen und ein neues festlegen — '
              'dabei gehen alle Entwicklungsdaten auf diesem Rechner '
              'verloren. Ein Backup mit Entwicklungsteil lässt sich danach '
              'nur mit dem alten Passwort lesen.',
            ),
            const SizedBox(height: 12),
            const Text('Tippe zur Bestätigung „ZURÜCKSETZEN" ein.'),
            const SizedBox(height: 8),
            TextField(
              controller: _eingabe,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: _wort),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (passt) Navigator.of(context).pop(true);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: passt ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Zurücksetzen'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Offen
// ---------------------------------------------------------------------------

/// Die Reiter der offenen Produktentwicklung.
enum EntwicklungsReiter {
  projekte('Projekte', Icons.folder_open_outlined),
  rezepturen('Rezepturen', Icons.menu_book_outlined),
  zutaten('Zutaten', Icons.egg_outlined),
  werkzeuge('Werkzeuge', Icons.calculate_outlined);

  const EntwicklungsReiter(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Der zuletzt gewählte Reiter — nach dem Zurückkommen steht man wieder
/// dort.
final entwicklungReiterProvider =
    StateProvider<EntwicklungsReiter>((ref) => EntwicklungsReiter.projekte);

/// Ein Teil, der mit einer der nächsten Lieferungen kommt.
class _Folgt extends StatelessWidget {
  const _Folgt({required this.icon, required this.titel, required this.text});

  final IconData icon;
  final String titel;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Bereich(
            titel: titel,
            icon: icon,
            aktionen: const [StatusMarke('folgt')],
            child: Text(text),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Passwort ändern
// ---------------------------------------------------------------------------

class _PasswortAendernDialog extends StatefulWidget {
  const _PasswortAendernDialog({required this.zugang});

  final EntwicklungZugang zugang;

  @override
  State<_PasswortAendernDialog> createState() => _PasswortAendernDialogState();
}

class _PasswortAendernDialogState extends State<_PasswortAendernDialog> {
  final _alt = TextEditingController();
  final _neu = TextEditingController();
  final _wiederholung = TextEditingController();
  String? _fehler;
  bool _rechnet = false;

  @override
  void dispose() {
    _alt.dispose();
    _neu.dispose();
    _wiederholung.dispose();
    super.dispose();
  }

  Future<void> _speichern() async {
    if (_rechnet) return;
    final fehler = passwortFehler(_neu.text) ??
        (_neu.text != _wiederholung.text
            ? 'Die beiden neuen Eingaben unterscheiden sich.'
            : null);
    if (fehler != null) {
      setState(() => _fehler = fehler);
      return;
    }
    setState(() {
      _rechnet = true;
      _fehler = null;
    });
    final bool geaendert;
    try {
      geaendert = await widget.zugang.aendern(_alt.text, _neu.text);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rechnet = false;
        _fehler = 'Das Passwort konnte nicht geändert werden: $e';
      });
      return;
    }
    if (!mounted) return;
    if (geaendert) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _rechnet = false;
      _fehler = 'Das bisherige Passwort stimmt nicht.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fehler = _fehler;
    return AlertDialog(
      title: const Text('Passwort ändern'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _alt,
              autofocus: true,
              obscureText: true,
              enabled: !_rechnet,
              decoration: const InputDecoration(
                labelText: 'Bisheriges Passwort',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _neu,
              obscureText: true,
              enabled: !_rechnet,
              decoration: const InputDecoration(
                labelText: 'Neues Passwort',
                helperText: 'Mindestens $kPasswortMindestlaenge Zeichen',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _wiederholung,
              obscureText: true,
              enabled: !_rechnet,
              decoration: const InputDecoration(
                labelText: 'Neues Passwort wiederholen',
              ),
              onSubmitted: (_) => _speichern(),
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
          onPressed: _rechnet ? null : () => Navigator.of(context).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _rechnet ? null : _speichern,
          child: Text(_rechnet ? 'Wird geändert …' : 'Ändern'),
        ),
      ],
    );
  }
}
