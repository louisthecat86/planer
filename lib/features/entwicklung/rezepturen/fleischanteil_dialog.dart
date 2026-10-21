import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/services/auto_backup_trigger.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/fehler_text.dart';
import '../daten/entwicklung_repository.dart';
import '../entwicklung_format.dart';
import '../rechenkern/fleisch_optimierung.dart';
import '../rechenkern/rechen_modell.dart';
import '../rechenkern/rechenkern.dart';

/// Öffnet das Fenster „Fleischanteil einstellen" für [version]. Gibt die
/// ID des Stands zurück, der danach zu sehen sein soll — bei einem
/// abgeschlossenen der neue —, sonst null.
Future<String?> fleischanteilOeffnen(
  BuildContext context, {
  required String rezepturId,
  required RezepturVersion version,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => FleischanteilDialog(
        rezepturId: rezepturId,
        version: version,
      ),
    );

/// Der Name einer Zeile für die Tabelle.
String zeilenName(RechenPosition p) =>
    p.etikettName?.trim().isNotEmpty ?? false
        ? p.etikettName!.trim()
        : p.zutat?.anzeigeName ?? p.unterrezeptur?.name ?? '—';

/// Bringt den Fleischanteil eines Stands auf einen Zielwert. Fleisch wird
/// gemeinsam größer oder kleiner, der Ausgleich trägt die Differenz, die
/// Rohmasse bleibt gleich.
class FleischanteilDialog extends ConsumerStatefulWidget {
  const FleischanteilDialog({
    super.key,
    required this.rezepturId,
    required this.version,
  });

  final String rezepturId;
  final RezepturVersion version;

  @override
  ConsumerState<FleischanteilDialog> createState() =>
      _FleischanteilDialogState();
}

class _FleischanteilDialogState extends ConsumerState<FleischanteilDialog> {
  List<OptimierRolle>? _rollen;
  FleischMass _mass = FleischMass.etikett;
  final _ziel = TextEditingController();
  bool _speichert = false;
  String? _fehler;

  bool get _entwurf => widget.version.status == VersionStatus.entwurf;

  @override
  void dispose() {
    _ziel.dispose();
    super.dispose();
  }

  Future<void> _uebernehmen(FleischEinstellung e) async {
    setState(() {
      _speichert = true;
      _fehler = null;
    });
    final repo = ref.read(entwicklungRepositoryProvider);
    try {
      final String id;
      if (_entwurf) {
        await repo.mengenSetzen(widget.version.id, e.mengenKg);
        id = widget.version.id;
      } else {
        id = await repo.standMitMengen(
          widget.rezepturId,
          widget.version.id,
          e.mengenKg,
          bezeichnung: 'Fleischanteil ${prozentText(e.erreichtProzent)}',
        );
      }
      ref
          .read(autoBackupTriggerProvider)
          .fireDebounced(reason: 'Fleischanteil eingestellt');
      if (mounted) Navigator.of(context).pop(id);
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _speichert = false;
        _fehler = 'Übernehmen fehlgeschlagen: ${fehlerText(err)}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final eingabe = ref.watch(rechenRezepturProvider(widget.version.id));
    final r = eingabe.valueOrNull;
    FleischEinstellung? einstellung;
    Widget inhalt;
    if (r == null) {
      inhalt = eingabe.hasError
          ? HinweisBox(
              fehlerText(eingabe.error),
              art: StatusArt.fehler,
              auswaehlbar: true,
            )
          : eingabe.isLoading
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              : const HinweisBox(
                  'Diesen Stand gibt es nicht mehr.',
                  art: StatusArt.fehler,
                );
    } else {
      final List<OptimierRolle> rollen;
      final bisher = _rollen;
      if (bisher != null && bisher.length == r.positionen.length) {
        rollen = bisher;
      } else {
        rollen = [for (final p in r.positionen) standardRolle(p)];
        _rollen = rollen;
      }
      final vorher = fleischWert(r, _mass);
      final ziel = zahlAus(_ziel.text) ?? vorher;
      final e = fleischanteilEinstellen(r, rollen, ziel, mass: _mass);
      einstellung = e;
      inhalt = _Inhalt(
        rezeptur: r,
        rollen: rollen,
        einstellung: e,
        mass: _mass,
        ziel: _ziel,
        entwurf: _entwurf,
        nummer: widget.version.nummer,
        aktiv: !_speichert,
        onMass: (m) => setState(() {
          _mass = m;
          _ziel.clear();
        }),
        onRolle: (i, rolle) => setState(() => rollen[i] = rolle),
        onZiel: () => setState(() {}),
      );
    }

    final e = einstellung;
    final geaendert = e != null &&
        [
          for (var i = 0; i < e.rezeptur.positionen.length; i++)
            (e.rezeptur.positionen[i].mengeKg - r!.positionen[i].mengeKg)
                .abs(),
        ].any((d) => d > 1e-6);
    final fehler = _fehler;

    return AlertDialog(
      icon: const Icon(Icons.tune),
      title: const Text('Fleischanteil einstellen'),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              inhalt,
              if (fehler != null) ...[
                const SizedBox(height: 12),
                HinweisBox(fehler, art: StatusArt.fehler, auswaehlbar: true),
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
          onPressed: e != null && geaendert && !_speichert
              ? () => _uebernehmen(e)
              : null,
          child: Text(_entwurf ? 'Übernehmen' : 'Als neuen Stand anlegen'),
        ),
      ],
    );
  }
}

class _Inhalt extends StatelessWidget {
  const _Inhalt({
    required this.rezeptur,
    required this.rollen,
    required this.einstellung,
    required this.mass,
    required this.ziel,
    required this.entwurf,
    required this.nummer,
    required this.aktiv,
    required this.onMass,
    required this.onRolle,
    required this.onZiel,
  });

  final RechenRezeptur rezeptur;
  final List<OptimierRolle> rollen;
  final FleischEinstellung einstellung;
  final FleischMass mass;
  final TextEditingController ziel;
  final bool entwurf;
  final int nummer;
  final bool aktiv;
  final ValueChanged<FleischMass> onMass;
  final void Function(int index, OptimierRolle rolle) onRolle;
  final VoidCallback onZiel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final e = einstellung;
    final klein = theme.textTheme.bodySmall;
    final hinweis = e.hinweis;
    final neu = e.rezeptur.positionen;
    final summeVorher =
        rezeptur.positionen.fold<double>(0, (s, p) => s + p.mengeKg);
    final summeNachher = neu.fold<double>(0, (s, p) => s + p.mengeKg);

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!entwurf)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: HinweisBox(
              'Stand $nummer ist abgeschlossen und bleibt, wie er ist — '
              'übernommen wird als neuer Stand.',
            ),
          ),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<FleischMass>(
              segments: [
                for (final m in FleischMass.values)
                  ButtonSegment(value: m, label: Text(m.label)),
              ],
              selected: {mass},
              showSelectedIcon: false,
              onSelectionChanged: aktiv ? (a) => onMass(a.first) : null,
            ),
            SizedBox(
              width: 130,
              child: TextField(
                controller: ziel,
                enabled: aktiv,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Ziel',
                  suffixText: '%',
                  hintText: feldText(
                    double.parse(e.vorherProzent.toStringAsFixed(1)),
                  ),
                ),
                onChanged: (_) => onZiel(),
              ),
            ),
            Text(
              'jetzt ${prozentText(e.vorherProzent)}',
              style: theme.textTheme.bodyMedium?.copyWith(color: grau),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Table(
          columnWidths: const {
            0: FlexColumnWidth(),
            1: FixedColumnWidth(150),
            2: FixedColumnWidth(90),
            3: FixedColumnWidth(90),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            zeile(
              [
                kopf('Zeile'),
                kopf('Rolle'),
                kopf('vorher kg', ausrichtung: TextAlign.right),
                kopf('nachher kg', ausrichtung: TextAlign.right),
              ],
              istKopf: true,
            ),
            for (var i = 0; i < rezeptur.positionen.length; i++)
              zeile([
                Text(
                  zeilenName(rezeptur.positionen[i]),
                  overflow: TextOverflow.ellipsis,
                ),
                DropdownButton<OptimierRolle>(
                  value: rollen[i],
                  isDense: true,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final rolle in OptimierRolle.values)
                      DropdownMenuItem(value: rolle, child: Text(rolle.label)),
                  ],
                  onChanged: aktiv
                      ? (rolle) {
                          if (rolle != null) onRolle(i, rolle);
                        }
                      : null,
                ),
                Text(
                  mengeText(rezeptur.positionen[i].mengeKg),
                  textAlign: TextAlign.right,
                ),
                Text(
                  mengeText(neu[i].mengeKg),
                  textAlign: TextAlign.right,
                  style: (neu[i].mengeKg - rezeptur.positionen[i].mengeKg)
                              .abs() >
                          1e-6
                      ? const TextStyle(fontWeight: FontWeight.w700)
                      : null,
                ),
              ]),
            zeile([
              kopf('Summe'),
              const SizedBox.shrink(),
              Text(mengeText(summeVorher), textAlign: TextAlign.right),
              Text(mengeText(summeNachher), textAlign: TextAlign.right),
            ]),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '${mass.label}: ${prozentText(e.vorherProzent)} → '
          '${prozentText(e.erreichtProzent)}',
          style: theme.textTheme.titleSmall,
        ),
        if (hinweis != null) ...[
          const SizedBox(height: 8),
          HinweisBox(hinweis, art: StatusArt.warnung),
        ],
        const SizedBox(height: 8),
        Text('Zutatenliste danach', style: klein?.copyWith(color: grau)),
        const SizedBox(height: 2),
        SelectableText(berechne(e.rezeptur).zutatenliste, style: klein),
        const SizedBox(height: 8),
        Text(
          'Die Zeilen mit „Fleisch" werden gemeinsam größer oder kleiner, '
          'die mit „Ausgleich" tragen die Differenz, „fest" bleibt. Die '
          'Rohmasse bleibt gleich.',
          style: klein?.copyWith(color: grau),
        ),
      ],
    );
  }
}
