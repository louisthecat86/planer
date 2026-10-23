import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/services/auto_backup_trigger.dart';
import '../../../core/theme/app_stil.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/fehler_text.dart';
import '../../../core/utils/format.dart';
import '../daten/entwicklung_repository.dart';
import '../entwicklung_format.dart';
import '../haccp/eingabe_dialoge.dart' show TextEingabeDialog;
import '../rechenkern/naehrwert_rundung.dart';
import '../rechenkern/rechen_modell.dart';
import '../rechenkern/rueckrechnung.dart';
import '../rezepturen/rezepturen_ansicht.dart' show oeffneRezeptur;
import '../rezepturen/zutat_auswahl_dialog.dart';

/// Die Nährstoffe, die das Etikett nennt und die Rückrechnung abfragt.
const List<Naehrstoff> kRueckZiele = [
  Naehrstoff.fett,
  Naehrstoff.gesaettigteFettsaeuren,
  Naehrstoff.kohlenhydrate,
  Naehrstoff.zucker,
  Naehrstoff.eiweiss,
  Naehrstoff.salz,
];

/// Eine Zeile der Liste: die Zutat aus dem Katalog und die Mengenangabe.
class _Zeile {
  _Zeile(this.zutatId);

  final String zutatId;
  final quid = TextEditingController();

  void dispose() => quid.dispose();
}

/// Rezeptur rückrechnen: aus Zutatenliste und Nährwerttabelle eines
/// Etiketts die Mengen schätzen.
class RueckrechnungScreen extends ConsumerStatefulWidget {
  const RueckrechnungScreen({super.key});

  @override
  ConsumerState<RueckrechnungScreen> createState() =>
      _RueckrechnungScreenState();
}

class _RueckrechnungScreenState extends ConsumerState<RueckrechnungScreen> {
  final _zeilen = <_Zeile>[];
  final _ziel = {
    for (final s in kRueckZiele) s: TextEditingController(),
  };
  Verlustart _verlustart = Verlustart.keiner;
  final _verlust = TextEditingController();
  final _fettVerlust = TextEditingController();
  bool _reihenfolge = true;
  RueckrechnungsErgebnis? _ergebnis;

  /// Die Zutat-IDs zum Ergebnis — in derselben Reihenfolge wie seine
  /// Mengen.
  List<String> _ergebnisIds = const [];
  String? _fehler;

  @override
  void dispose() {
    for (final z in _zeilen) {
      z.dispose();
    }
    for (final c in _ziel.values) {
      c.dispose();
    }
    _verlust.dispose();
    _fettVerlust.dispose();
    super.dispose();
  }

  void _geaendert(VoidCallback tun) => setState(() {
        tun();
        _ergebnis = null;
        _fehler = null;
      });

  Future<void> _hinzufuegen() async {
    final wahl = await showDialog<ZutatAuswahl>(
      context: context,
      builder: (_) => const ZutatAuswahlDialog(
        ohneRezepturId: '',
        nurZutaten: true,
      ),
    );
    if (wahl == null || wahl.istRezeptur || !mounted) return;
    _geaendert(() => _zeilen.add(_Zeile(wahl.id)));
  }

  void _verschieben(int i, int j) {
    if (j < 0 || j >= _zeilen.length) return;
    _geaendert(() {
      final z = _zeilen.removeAt(i);
      _zeilen.insert(j, z);
    });
  }

  void _entfernen(int i) => _geaendert(() => _zeilen.removeAt(i).dispose());

  void _rechnen(Map<String, Zutat> katalog) {
    final ids = <String>[];
    final zutaten = <RueckZutat>[];
    for (final z in _zeilen) {
      final zutat = katalog[z.zutatId];
      if (zutat == null) continue;
      ids.add(z.zutatId);
      zutaten.add(
        RueckZutat(rechenZutatAus(zutat), quidProzent: zahlAus(z.quid.text)),
      );
    }
    double? wert(Naehrstoff s) => zahlAus(_ziel[s]!.text);
    try {
      final e = rueckrechnen(
        zutaten: zutaten,
        ziel: Naehrwerte(
          fett: wert(Naehrstoff.fett),
          gesaettigteFettsaeuren: wert(Naehrstoff.gesaettigteFettsaeuren),
          kohlenhydrate: wert(Naehrstoff.kohlenhydrate),
          zucker: wert(Naehrstoff.zucker),
          eiweiss: wert(Naehrstoff.eiweiss),
          salz: wert(Naehrstoff.salz),
        ),
        verlustart: _verlustart,
        verlustProzent: zahlAus(_verlust.text) ?? 0,
        fettVerlustProzent: zahlAus(_fettVerlust.text) ?? 0,
        reihenfolge: _reihenfolge,
      );
      setState(() {
        _ergebnis = e;
        _ergebnisIds = ids;
        _fehler = null;
      });
    } on ArgumentError catch (e) {
      setState(() {
        _ergebnis = null;
        _fehler = '${e.message}';
      });
    }
  }

  Future<void> _speichern(RueckrechnungsErgebnis e) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const TextEingabeDialog(
        titel: 'Als Rezeptur speichern',
        label: 'Name der Rezeptur',
        bestaetigen: 'Anlegen',
      ),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = e.rezeptur;
      final id = await ref.read(entwicklungRepositoryProvider).rezepturMitZeilen(
            name: name.trim(),
            beschreibung: 'Aus der Rückrechnung vom '
                '${Format.datum(DateTime.now())} — Mengen je 100 kg Rohmasse.',
            zeilen: [
              for (var i = 0; i < _ergebnisIds.length; i++)
                (
                  zutatId: _ergebnisIds[i],
                  mengeKg: double.parse(e.mengenKg[i].toStringAsFixed(3)),
                ),
            ],
            verlustProzent: r.verlustProzent,
            fettVerlustProzent: r.fettVerlustProzent,
            verlustArt: r.verlustart.schluessel,
          );
      ref
          .read(autoBackupTriggerProvider)
          .fireDebounced(reason: 'Rezeptur aus der Rückrechnung');
      if (mounted) await oeffneRezeptur(context, id);
    } catch (err) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Die Rezeptur ließ sich nicht anlegen: ${fehlerText(err)}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final katalog = ref.watch(alleZutatenProvider).valueOrNull ??
        const <String, Zutat>{};
    final ergebnis = _ergebnis;
    final fehler = _fehler;

    final eingabe = [
      _ZutatenBereich(
        zeilen: _zeilen,
        katalog: katalog,
        onHinzufuegen: _hinzufuegen,
        onVerschieben: _verschieben,
        onEntfernen: _entfernen,
        onQuid: () => _geaendert(() {}),
      ),
      const SizedBox(height: 16),
      Bereich(
        titel: 'Nährwerte je 100 g',
        icon: Icons.table_rows_outlined,
        untertitel: 'wie auf dem Etikett — leere Felder zählen nicht',
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final s in kRueckZiele)
              SizedBox(
                width: 170,
                child: TextField(
                  controller: _ziel[s],
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: s.label,
                    suffixText: s.einheit,
                  ),
                  onChanged: (_) => _geaendert(() {}),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Bereich(
        titel: 'Verlust',
        icon: Icons.local_fire_department_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<Verlustart>(
                    initialValue: _verlustart,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Verlustart'),
                    items: [
                      for (final a in Verlustart.values)
                        DropdownMenuItem(
                          value: a,
                          child: Text(a.label, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (a) {
                      if (a != null) _geaendert(() => _verlustart = a);
                    },
                  ),
                ),
                if (_verlustart != Verlustart.keiner) ...[
                  SizedBox(
                    width: 140,
                    child: TextField(
                      controller: _verlust,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Verlust',
                        suffixText: '%',
                      ),
                      onChanged: (_) => _geaendert(() {}),
                    ),
                  ),
                  SizedBox(
                    width: 140,
                    child: TextField(
                      controller: _fettVerlust,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'davon Fett',
                        suffixText: '%',
                      ),
                      onChanged: (_) => _geaendert(() {}),
                    ),
                  ),
                ],
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _reihenfolge,
              onChanged: (v) => _geaendert(() => _reihenfolge = v),
              title: const Text('Reihenfolge der Liste einhalten'),
              subtitle: const Text(
                'Jede Zeile wiegt mindestens so viel wie die nächste — wie '
                'die Zutatenliste es verlangt.',
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: _zeilen.isEmpty ? null : () => _rechnen(katalog),
          icon: const Icon(Icons.calculate_outlined, size: 18),
          label: const Text('Rückrechnen'),
        ),
      ),
      if (fehler != null) ...[
        const SizedBox(height: 12),
        HinweisBox(fehler, art: StatusArt.fehler),
      ],
    ];

    final ausgabe = ergebnis == null
        ? const Bereich(
            titel: 'Ergebnis',
            icon: Icons.insights_outlined,
            child: Text(
              'Zutaten in der Reihenfolge des Etiketts eintragen, '
              'Mengenangaben und Nährwerte dazu, dann „Rückrechnen". Die '
              'Rechnung schätzt die Mengen, mit denen die Rezeptur die '
              'Nährwerte am besten trifft — ohne Zufall: Gleiche Eingabe, '
              'gleiches Ergebnis.',
            ),
          )
        : _ErgebnisBereich(
            ergebnis: ergebnis,
            namen: [
              for (final id in _ergebnisIds) katalog[id]?.name ?? '—',
            ],
            onSpeichern: () => _speichern(ergebnis),
          );

    return Scaffold(
      appBar: AppBar(title: const Text('Rezeptur rückrechnen')),
      body: LayoutBuilder(
        builder: (context, c) {
          if (c.maxWidth >= 1100) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 8, 24),
                    children: eingabe,
                  ),
                ),
                Expanded(
                  flex: 6,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(8, 16, 16, 24),
                    children: [ausgabe],
                  ),
                ),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [...eingabe, const SizedBox(height: 16), ausgabe],
          );
        },
      ),
    );
  }
}

class _ZutatenBereich extends StatelessWidget {
  const _ZutatenBereich({
    required this.zeilen,
    required this.katalog,
    required this.onHinzufuegen,
    required this.onVerschieben,
    required this.onEntfernen,
    required this.onQuid,
  });

  final List<_Zeile> zeilen;
  final Map<String, Zutat> katalog;
  final VoidCallback onHinzufuegen;
  final void Function(int von, int nach) onVerschieben;
  final ValueChanged<int> onEntfernen;
  final VoidCallback onQuid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    return Bereich(
      titel: 'Zutatenliste des Etiketts',
      icon: Icons.format_list_numbered,
      untertitel: 'in der Reihenfolge des Etiketts',
      aktionen: [
        TextButton.icon(
          onPressed: onHinzufuegen,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Zutat hinzufügen'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (zeilen.isEmpty)
            const LeerHinweis(
              'Noch keine Zutat — aus dem Katalog hinzufügen.',
              icon: Icons.egg_outlined,
            ),
          for (var i = 0; i < zeilen.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${i + 1}.',
                      style: theme.textTheme.bodySmall?.copyWith(color: grau),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      katalog[zeilen[i].zutatId]?.name ??
                          'Zutat nicht mehr im Katalog',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: 96,
                    child: TextField(
                      controller: zeilen[i].quid,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Menge',
                        suffixText: '%',
                      ),
                      onChanged: (_) => onQuid(),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Nach oben',
                    icon: const Icon(Icons.arrow_upward, size: 18),
                    onPressed: i == 0 ? null : () => onVerschieben(i, i - 1),
                  ),
                  IconButton(
                    tooltip: 'Nach unten',
                    icon: const Icon(Icons.arrow_downward, size: 18),
                    onPressed: i == zeilen.length - 1
                        ? null
                        : () => onVerschieben(i, i + 1),
                  ),
                  IconButton(
                    tooltip: 'Entfernen',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => onEntfernen(i),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Mengenangaben in % wie auf dem Etikett — die Zeile steht dann '
            'fest. Fleisch derselben Tierart hintereinander zählt als eine '
            'Zeile (Schulter und Bauch → Schweinefleisch); ihre Angabe gilt '
            'für alle Stücke zusammen. Zugesetztes Wasser steht mit dem, was '
            'nach dem Verlust bleibt.',
            style: theme.textTheme.bodySmall?.copyWith(color: grau),
          ),
        ],
      ),
    );
  }
}

class _ErgebnisBereich extends StatelessWidget {
  const _ErgebnisBereich({
    required this.ergebnis,
    required this.namen,
    required this.onSpeichern,
  });

  final RueckrechnungsErgebnis ergebnis;
  final List<String> namen;
  final VoidCallback onSpeichern;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final klein = theme.textTheme.bodySmall;
    final farben = AppFarben.von(context);
    final e = ergebnis;

    TableRow zeile(List<Widget> zellen, {bool istKopf = false}) => TableRow(
          decoration: istKopf
              ? BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: theme.colorScheme.outline),
                  ),
                )
              : null,
          children: [
            for (final z in zellen)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                child: z,
              ),
          ],
        );
    Text kopf(String t, {TextAlign? ausrichtung}) => Text(
          t,
          textAlign: ausrichtung,
          style: klein?.copyWith(color: grau, fontWeight: FontWeight.w600),
        );
    Text rechts(String t) => Text(t, textAlign: TextAlign.right);

    return Bereich(
      titel: 'Ergebnis',
      icon: Icons.insights_outlined,
      untertitel: 'Mengen je 100 kg Rohmasse',
      aktionen: [
        FilledButton.icon(
          onPressed: onSpeichern,
          icon: const Icon(Icons.save_outlined, size: 18),
          label: const Text('Als Rezeptur speichern…'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HinweisBox(
            e.passt
                ? 'Alle Nährwerte liegen innerhalb der Toleranzen für '
                    'Nährwertangaben.'
                : 'Nicht alle Nährwerte lassen sich mit diesen Zutaten '
                    'treffen — siehe Hinweise.',
            art: e.passt ? StatusArt.ok : StatusArt.warnung,
          ),
          const SizedBox(height: 12),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(),
              1: FixedColumnWidth(110),
            },
            children: [
              zeile(
                [kopf('Zutat'), kopf('kg', ausrichtung: TextAlign.right)],
                istKopf: true,
              ),
              for (var i = 0; i < namen.length; i++)
                zeile([
                  Text(namen[i], overflow: TextOverflow.ellipsis),
                  rechts(mengeText(e.mengenKg[i])),
                ]),
            ],
          ),
          const SizedBox(height: 16),
          if (e.vergleich.isNotEmpty)
            Table(
              columnWidths: const {
                0: FlexColumnWidth(),
                1: FixedColumnWidth(80),
                2: FixedColumnWidth(80),
                3: FixedColumnWidth(90),
                4: FixedColumnWidth(36),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                zeile(
                  [
                    kopf('je 100 g'),
                    kopf('Etikett', ausrichtung: TextAlign.right),
                    kopf('Rezeptur', ausrichtung: TextAlign.right),
                    kopf('Toleranz', ausrichtung: TextAlign.right),
                    const SizedBox.shrink(),
                  ],
                  istKopf: true,
                ),
                for (final v in e.vergleich)
                  zeile([
                    Text('${v.stoff.label} (${v.stoff.einheit})'),
                    rechts(Format.zahl(v.ziel, nachkomma: 2)),
                    rechts(Format.zahl(v.wert, nachkomma: 2)),
                    rechts('± ${Format.zahl(v.toleranz, nachkomma: 2)}'),
                    Icon(
                      v.passt
                          ? Icons.check_circle_outline
                          : Icons.warning_amber_rounded,
                      size: 18,
                      color: v.passt ? farben.ok : farben.warnung,
                    ),
                  ]),
              ],
            ),
          const SizedBox(height: 16),
          Text('Zutatenliste der Rezeptur', style: klein?.copyWith(color: grau)),
          const SizedBox(height: 2),
          SelectableText(e.ergebnis.zutatenliste),
          if (e.hinweise.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Hinweise', style: klein?.copyWith(color: grau)),
            const SizedBox(height: 4),
            for (final h in e.hinweise)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $h', style: klein),
              ),
          ],
          const SizedBox(height: 8),
          Text(
            'Eine Schätzung: Sie trifft die Nährwerte des Etiketts so gut, '
            'wie die Werte der Zutaten im Katalog es erlauben. Gespeichert '
            'wird sie als neue Rezeptur mit einem Entwurf — zum '
            'Weiterarbeiten.',
            style: klein?.copyWith(color: grau),
          ),
        ],
      ),
    );
  }
}
