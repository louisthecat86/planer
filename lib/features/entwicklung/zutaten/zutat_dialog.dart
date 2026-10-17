// `show Value`: drift bringt eine eigene Klasse `Column` mit, die sich sonst
// mit der von Flutter beißt.
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/artikel_merkmale.dart';
import '../../../core/database/database.dart';
import '../../../core/services/auto_backup_trigger.dart';
import '../daten/entwicklung_repository.dart';
import '../entwicklung_format.dart';
import '../rechenkern/rechen_modell.dart';

/// Die Nährwertfelder des Fensters, in der Reihenfolge der Tabelle.
enum _Feld {
  energieKj('Energie', 'kJ'),
  energieKcal('Energie', 'kcal'),
  fett('Fett', 'g'),
  gesaettigt('davon gesättigt', 'g'),
  kohlenhydrate('Kohlenhydrate', 'g'),
  zucker('davon Zucker', 'g'),
  eiweiss('Eiweiß', 'g'),
  salz('Salz', 'g'),
  wasser('Wasser', 'g'),
  asche('Asche', 'g'),
  beffe('BEFFE', '%');

  const _Feld(this.label, this.einheit);

  final String label;
  final String einheit;
}

/// Eine Zutat anlegen oder bearbeiten.
class ZutatDialog extends ConsumerStatefulWidget {
  const ZutatDialog({super.key, this.zutat});

  /// null: neue Zutat.
  final Zutat? zutat;

  @override
  ConsumerState<ZutatDialog> createState() => _ZutatDialogState();
}

class _ZutatDialogState extends ConsumerState<ZutatDialog> {
  late final TextEditingController _name;
  late final TextEditingController _etikett;
  late final TextEditingController _nummer;
  late final TextEditingController _unterzutaten;
  late final TextEditingController _hilfsstoffe;
  late final TextEditingController _bindegewebe;
  late final TextEditingController _notiz;
  late final Map<_Feld, TextEditingController> _werte;

  late bool _istFleisch;
  late bool _istWasser;
  late bool _quid;
  Tierart? _tierart;
  late Set<String> _allergene;

  String? _fehler;
  bool _speichert = false;

  @override
  void initState() {
    super.initState();
    final z = widget.zutat;
    _name = TextEditingController(text: z?.name ?? '');
    _etikett = TextEditingController(text: z?.etikettName ?? '');
    _nummer = TextEditingController(text: z?.artikelnummer ?? '');
    _unterzutaten = TextEditingController(text: z?.unterzutaten ?? '');
    _hilfsstoffe =
        TextEditingController(text: z?.verarbeitungshilfsstoffe ?? '');
    _bindegewebe = TextEditingController(text: feldText(z?.bindegewebe));
    _notiz = TextEditingController(text: z?.notiz ?? '');
    _werte = {
      _Feld.energieKj: TextEditingController(text: feldText(z?.energieKj)),
      _Feld.energieKcal:
          TextEditingController(text: feldText(z?.energieKcal)),
      _Feld.fett: TextEditingController(text: feldText(z?.fett)),
      _Feld.gesaettigt:
          TextEditingController(text: feldText(z?.gesaettigteFettsaeuren)),
      _Feld.kohlenhydrate:
          TextEditingController(text: feldText(z?.kohlenhydrate)),
      _Feld.zucker: TextEditingController(text: feldText(z?.zucker)),
      _Feld.eiweiss: TextEditingController(text: feldText(z?.eiweiss)),
      _Feld.salz: TextEditingController(text: feldText(z?.salz)),
      _Feld.wasser: TextEditingController(text: feldText(z?.wasser)),
      _Feld.asche: TextEditingController(text: feldText(z?.asche)),
      _Feld.beffe: TextEditingController(text: feldText(z?.beffe)),
    };
    _istFleisch = z?.istFleisch ?? false;
    _istWasser = z?.istWasser ?? false;
    _quid = z?.quidPflicht ?? false;
    _tierart = Tierart.aus(z?.tierart);
    _allergene = merkmaleAusText(z?.allergene);
  }

  @override
  void dispose() {
    _name.dispose();
    _etikett.dispose();
    _nummer.dispose();
    _unterzutaten.dispose();
    _hilfsstoffe.dispose();
    _bindegewebe.dispose();
    _notiz.dispose();
    for (final c in _werte.values) {
      c.dispose();
    }
    super.dispose();
  }

  static String? _text(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  /// Rechnet die Energie aus Fett, Eiweiß und Kohlenhydraten.
  void _energieRechnen() {
    final fett = zahlAus(_werte[_Feld.fett]!.text) ?? 0;
    final eiweiss = zahlAus(_werte[_Feld.eiweiss]!.text) ?? 0;
    final kh = zahlAus(_werte[_Feld.kohlenhydrate]!.text) ?? 0;
    setState(() {
      _werte[_Feld.energieKj]!.text =
          feldText(fett * 37 + eiweiss * 17 + kh * 17);
      _werte[_Feld.energieKcal]!.text = feldText(fett * 9 + eiweiss * 4 + kh * 4);
    });
  }

  Future<void> _speichern() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _fehler = 'Bitte einen Namen eingeben.');
      return;
    }
    final zahlen = <_Feld, double?>{};
    for (final MapEntry(:key, :value) in _werte.entries) {
      final text = value.text.trim();
      final wert = zahlAus(text);
      if (text.isNotEmpty && wert == null) {
        setState(() => _fehler = '„${key.label}" ist keine Zahl.');
        return;
      }
      zahlen[key] = wert;
    }
    final bindegewebeText = _bindegewebe.text.trim();
    final bindegewebe = zahlAus(bindegewebeText);
    if (bindegewebeText.isNotEmpty && bindegewebe == null) {
      setState(() => _fehler = '„Bindegewebe" ist keine Zahl.');
      return;
    }

    final daten = EntwicklungZutatenCompanion(
      name: Value(name),
      etikettName: Value(_text(_etikett)),
      artikelnummer: Value(_text(_nummer)),
      istFleisch: Value(_istFleisch),
      istWasser: Value(_istWasser),
      tierart: Value(_istFleisch ? _tierart?.schluessel : null),
      bindegewebe: Value(_istFleisch ? bindegewebe : null),
      quidPflicht: Value(_quid),
      unterzutaten: Value(_text(_unterzutaten)),
      verarbeitungshilfsstoffe: Value(_text(_hilfsstoffe)),
      allergene: Value(merkmaleZuText(_allergene, kAllergene)),
      energieKj: Value(zahlen[_Feld.energieKj]),
      energieKcal: Value(zahlen[_Feld.energieKcal]),
      fett: Value(zahlen[_Feld.fett]),
      gesaettigteFettsaeuren: Value(zahlen[_Feld.gesaettigt]),
      kohlenhydrate: Value(zahlen[_Feld.kohlenhydrate]),
      zucker: Value(zahlen[_Feld.zucker]),
      eiweiss: Value(zahlen[_Feld.eiweiss]),
      salz: Value(zahlen[_Feld.salz]),
      wasser: Value(zahlen[_Feld.wasser]),
      asche: Value(zahlen[_Feld.asche]),
      beffe: Value(zahlen[_Feld.beffe]),
      notiz: Value(_text(_notiz)),
    );

    setState(() {
      _speichert = true;
      _fehler = null;
    });
    try {
      final repo = ref.read(entwicklungRepositoryProvider);
      final alt = widget.zutat;
      if (alt == null) {
        await repo.zutatAnlegen(daten);
      } else {
        await repo.zutatAendern(alt.id, daten);
      }
      ref
          .read(autoBackupTriggerProvider)
          .fireDebounced(reason: 'Zutat gespeichert');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _speichert = false;
        _fehler = 'Speichern fehlgeschlagen: $e';
      });
    }
  }

  Future<void> _loeschen() async {
    final z = widget.zutat;
    if (z == null) return;
    final repo = ref.read(entwicklungRepositoryProvider);
    final verwendet = await repo.zutatVerwendungen(z.id);
    if (!mounted) return;
    final ja = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zutat löschen?'),
        content: Text(
          verwendet == 0
              ? '„${z.name}" steht in keiner Rezeptur.'
              : '„${z.name}" steht in $verwendet '
                  '${verwendet == 1 ? 'Rezepturstand' : 'Rezepturständen'}. '
                  'Diese rechnen weiter mit ihr und zeigen sie als gelöscht.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ja != true) return;
    await repo.zutatLoeschen(z.id);
    ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Zutat gelöscht');
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fehler = _fehler;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.zutat == null ? 'Neue Zutat' : 'Zutat bearbeiten',
                style: theme.dialogTheme.titleTextStyle ??
                    theme.textTheme.titleMedium,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              tooltip: 'Schließen ohne Speichern',
              onPressed: _speichert ? null : () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          autofocus: widget.zutat == null,
          decoration: const InputDecoration(
            labelText: 'Name',
            helperText: 'Wie ihr die Zutat intern nennt',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _etikett,
                decoration: const InputDecoration(
                  labelText: 'Name auf dem Etikett',
                  helperText: 'Leer: wie der Name',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _nummer,
                decoration: const InputDecoration(labelText: 'Artikelnummer'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _abschnitt(context, 'Art'),
        CheckboxListTile(
          value: _istFleisch,
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Fleisch — zählt zum Fleischanteil'),
          onChanged: (v) => setState(() {
            _istFleisch = v ?? false;
            if (_istFleisch) _istWasser = false;
          }),
        ),
        if (_istFleisch)
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 0, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<Tierart?>(
                    initialValue: _tierart,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Tierart'),
                    items: [
                      const DropdownMenuItem<Tierart?>(
                        child: Text('— bitte wählen —'),
                      ),
                      for (final art in Tierart.values)
                        DropdownMenuItem<Tierart?>(
                          value: art,
                          child: Text(art.label),
                        ),
                    ],
                    onChanged: (v) => setState(() => _tierart = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _bindegewebe,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Bindegewebe',
                      suffixText: '%',
                      helperText: 'Kollagen zu Fleischeiweiß',
                    ),
                  ),
                ),
              ],
            ),
          ),
        CheckboxListTile(
          value: _istWasser,
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Zugesetztes Wasser oder Eis'),
          subtitle: const Text(
            'Zählt mit dem, was nach dem Verlust bleibt; bis 5 % steht es '
            'nicht in der Zutatenliste.',
          ),
          onChanged: (v) => setState(() {
            _istWasser = v ?? false;
            if (_istWasser) _istFleisch = false;
          }),
        ),
        CheckboxListTile(
          value: _quid,
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Menge in der Zutatenliste angeben (QUID)'),
          onChanged: (v) => setState(() => _quid = v ?? false),
        ),
        const SizedBox(height: 12),
        _abschnitt(context, 'Etikett'),
        TextField(
          controller: _unterzutaten,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Unterzutaten',
            helperText: 'Stehen in Klammern hinter dem Namen, etwa „Salz, '
                'Pfeffer, Paprika"',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _hilfsstoffe,
          decoration: const InputDecoration(
            labelText: 'Verarbeitungshilfsstoffe',
            helperText: 'Mit Komma getrennt — für die Spezifikation',
          ),
        ),
        const SizedBox(height: 18),
        _abschnitt(context, 'Allergene'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in kAllergene)
              FilterChip(
                label: Text(m.label),
                selected: _allergene.contains(m.dbValue),
                onSelected: (an) => setState(() {
                  if (!an) {
                    _allergene.remove(m.dbValue);
                  } else if (m.dbValue == kAllergenKeine) {
                    _allergene
                      ..clear()
                      ..add(kAllergenKeine);
                  } else {
                    _allergene
                      ..remove(kAllergenKeine)
                      ..add(m.dbValue);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 18),
        _abschnitt(
          context,
          'Nährwerte je 100 g',
          aktion: TextButton.icon(
            onPressed: _energieRechnen,
            icon: const Icon(Icons.calculate_outlined, size: 16),
            label: const Text('Energie berechnen'),
          ),
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final feld in _Feld.values)
              SizedBox(
                width: 150,
                child: TextField(
                  controller: _werte[feld],
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: feld.label,
                    suffixText: feld.einheit,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _notiz,
          minLines: 1,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Notiz'),
        ),
        if (fehler != null) ...[
          const SizedBox(height: 12),
          Text(
            fehler,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            if (widget.zutat != null)
              TextButton.icon(
                onPressed: _speichert ? null : _loeschen,
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Löschen'),
              ),
            const Spacer(),
            TextButton(
              onPressed: _speichert ? null : () => Navigator.of(context).pop(),
              child: const Text('Abbrechen'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _speichert ? null : _speichern,
              icon: _speichert
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save, size: 18),
              label: Text(_speichert ? 'Speichern …' : 'Speichern'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Überschrift eines Abschnitts mit dünner Linie darunter.
Widget _abschnitt(BuildContext context, String titel, {Widget? aktion}) {
  final theme = Theme.of(context);
  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.only(bottom: 4),
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            titel,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (aktion != null) aktion,
      ],
    ),
  );
}
