import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/auto_backup_trigger.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/fehler_text.dart';
import '../../../core/utils/format.dart';
import '../daten/dateien.dart';
import '../spezifikation/xlsx_kopflogo.dart';
import 'bericht_formblatt.dart';

/// Lässt Kopf- und Fußzeile des Projektberichts bearbeiten. Liefert die
/// gespeicherten Angaben samt Logo — null, wenn abgebrochen.
Future<BerichtFormblatt?> formblattBearbeiten(BuildContext context) =>
    showDialog<BerichtFormblatt>(
      context: context,
      builder: (_) => const FormblattDialog(),
    );

/// Kopf- und Fußzeile des Projektberichts: oben die Nummer des Formblatts
/// und das Logo aus der Spezifikationsvorlage, unten Erstellt von, Geprüft
/// von, Version, Stand und welchen Stand er ersetzt.
class FormblattDialog extends ConsumerStatefulWidget {
  const FormblattDialog({super.key});

  @override
  ConsumerState<FormblattDialog> createState() => _FormblattDialogState();
}

class _FormblattDialogState extends ConsumerState<FormblattDialog> {
  final _nummer = TextEditingController();
  final _erstelltVon = TextEditingController();
  final _geprueftVon = TextEditingController();
  final _version = TextEditingController();
  final _stand = TextEditingController();
  final _ersetzt = TextEditingController();
  final _versionFokus = FocusNode();
  bool _logoZeigen = true;

  /// Das Logo der Spezifikationsvorlage — auch, wenn es gerade nicht
  /// gezeigt wird.
  KopfLogo? _logo;
  bool _geladen = false;
  bool _speichert = false;
  Object? _fehler;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  @override
  void dispose() {
    for (final c in [
      _nummer,
      _erstelltVon,
      _geprueftVon,
      _version,
      _stand,
      _ersetzt,
    ]) {
      c.dispose();
    }
    _versionFokus.dispose();
    super.dispose();
  }

  Future<void> _laden() async {
    final dateien = ref.read(entwicklungDateienProvider);
    final formblatt = await berichtFormblattLaden(dateien, mitLogo: false);
    final logo = await spezifikationsLogo(dateien);
    if (!mounted) return;
    setState(() {
      _setze(formblatt);
      _logo = logo;
      _geladen = true;
    });
  }

  void _setze(BerichtFormblatt f) {
    _nummer.text = f.nummer;
    _erstelltVon.text = f.erstelltVon;
    _geprueftVon.text = f.geprueftVon;
    _version.text = f.version;
    _stand.text = f.stand;
    _ersetzt.text = f.ersetzt;
    _logoZeigen = f.logoZeigen;
  }

  BerichtFormblatt get _eingabe => BerichtFormblatt(
        nummer: _nummer.text,
        erstelltVon: _erstelltVon.text,
        geprueftVon: _geprueftVon.text,
        version: _version.text,
        stand: _stand.text,
        ersetzt: _ersetzt.text,
        logoZeigen: _logoZeigen,
      );

  /// Version weiter, Stand heute, der bisherige wird ersetzt — was sich
  /// geändert hat, schreibt man hinter die neue Nummer.
  void _neueVersion() {
    setState(() => _setze(_eingabe.neueVersion(DateTime.now())));
    _versionFokus.requestFocus();
    _version.selection = TextSelection.collapsed(offset: _version.text.length);
  }

  Future<void> _datumWaehlen(TextEditingController feld) async {
    final heute = DateTime.now();
    final gewaehlt = await showDatePicker(
      context: context,
      initialDate: _datumAus(feld.text) ?? heute,
      firstDate: DateTime(2000),
      lastDate: DateTime(heute.year + 5, 12, 31),
    );
    if (gewaehlt != null) feld.text = Format.datum(gewaehlt);
  }

  /// „TT.MM.JJJJ" als Datum — null, wenn es keins ist.
  static DateTime? _datumAus(String text) {
    final m = RegExp(r'^\s*(\d{1,2})\.(\d{1,2})\.(\d{4})\s*$').firstMatch(text);
    if (m == null) return null;
    final d = DateTime(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
    return d.day == int.parse(m[1]!) && d.month == int.parse(m[2]!) ? d : null;
  }

  Future<void> _speichern() async {
    final formblatt = _eingabe;
    final dateien = ref.read(entwicklungDateienProvider);
    final sicherung = ref.read(autoBackupTriggerProvider);
    setState(() {
      _speichert = true;
      _fehler = null;
    });
    try {
      await berichtFormblattSpeichern(dateien, formblatt);
      sicherung.fireDebounced(reason: 'Projektbericht Kopf- und Fußzeile');
      if (!mounted) return;
      Navigator.of(context).pop(
        formblatt.mitLogo(formblatt.logoZeigen ? _logo : null),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _speichert = false;
          _fehler = e;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final klein = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    Widget ueberschrift(String text) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(text, style: theme.textTheme.titleSmall),
        );
    Widget datumFeld(
      TextEditingController feld,
      String label,
      String schluessel,
    ) =>
        TextField(
          key: ValueKey(schluessel),
          controller: feld,
          decoration: InputDecoration(
            labelText: label,
            hintText: 'TT.MM.JJJJ',
            suffixIcon: IconButton(
              tooltip: 'Datum wählen',
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              onPressed: () => _datumWaehlen(feld),
            ),
          ),
        );
    final logo = _logo;

    return AlertDialog(
      title: const Text('Kopf- und Fußzeile des Projektberichts'),
      content: SizedBox(
        width: 560,
        child: !_geladen
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Wie auf den Formblättern — auf jeder Seite des '
                      'Berichts und in der leeren Vorlage. Leere Felder '
                      'bleiben weg.',
                      style: klein,
                    ),
                    ueberschrift('Kopfzeile'),
                    TextField(
                      key: const ValueKey('formblatt-nummer'),
                      controller: _nummer,
                      decoration: const InputDecoration(
                        labelText: 'Nummer des Formblatts',
                        hintText: 'etwa FB_XY_001',
                        helperText: 'Oben links — die Seite steht unten '
                            'rechts',
                      ),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      key: const ValueKey('formblatt-logo'),
                      value: _logoZeigen,
                      onChanged: (an) =>
                          setState(() => _logoZeigen = an ?? true),
                      title: const Text('Logo oben rechts'),
                      subtitle: const Text(
                        'Aus der Kopfzeile der Spezifikationsvorlage — '
                        'eine neue Vorlage bringt ihr Logo mit.',
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (logo == null)
                      Text(
                        'In der Spezifikationsvorlage steht kein Logo in '
                        'der Kopfzeile (JPEG oder PNG) — oben rechts bleibt '
                        'frei.',
                        style: klein,
                      )
                    else if (_logoZeigen)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: DecoratedBox(
                          // Weiß wie das Papier — auch im dunklen Design.
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Image.memory(
                              logo.bytes,
                              height: 36,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Text(
                                'Das Logo lässt sich hier nicht zeigen.',
                                style: klein,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ueberschrift('Fußzeile'),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const ValueKey('formblatt-erstellt'),
                            controller: _erstelltVon,
                            decoration: const InputDecoration(
                              labelText: 'Erstellt von',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            key: const ValueKey('formblatt-geprueft'),
                            controller: _geprueftVon,
                            decoration: const InputDecoration(
                              labelText: 'Geprüft von',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('formblatt-version'),
                      controller: _version,
                      focusNode: _versionFokus,
                      decoration: const InputDecoration(
                        labelText: 'Version',
                        hintText: 'etwa „02 neue Kapitel"',
                        helperText: 'Nummer und was sich geändert hat',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: datumFeld(_stand, 'Stand', 'formblatt-stand'),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: datumFeld(
                            _ersetzt,
                            'ersetzt den Stand',
                            'formblatt-ersetzt',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Tooltip(
                        message: 'Zählt die Version weiter, setzt den Stand '
                            'auf heute und trägt den bisherigen bei '
                            '„ersetzt den Stand" ein',
                        child: TextButton.icon(
                          key: const ValueKey('formblatt-neue-version'),
                          onPressed: _neueVersion,
                          icon: const Icon(Icons.update, size: 18),
                          label: const Text('Neue Version ab heute'),
                        ),
                      ),
                    ),
                    if (_fehler case final fehler?) ...[
                      const SizedBox(height: 8),
                      HinweisBox(
                        'Das ließ sich nicht speichern: ${fehlerText(fehler)}',
                        art: StatusArt.fehler,
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
          key: const ValueKey('formblatt-speichern'),
          onPressed: !_geladen || _speichert ? null : _speichern,
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}
