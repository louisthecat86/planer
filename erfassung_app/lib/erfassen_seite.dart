import 'package:erfassung_format/erfassung_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'artikel_seite.dart';
import 'bausteine.dart';
import 'modell.dart';
import 'stil.dart';

/// Eine Produktion erfassen: Rohware, davon Fleisch, Fertigware, Start und
/// Ende und Bemerkung — dieselben Angaben wie in der
/// Produktionserfassung des Planers.
///
/// [geplant] ist die Produktion aus dem Paket; ohne Plan steht der
/// [artikel] fest. [vorhanden] ist eine frühere Erfassung zum Ändern.
class ErfassenSeite extends StatefulWidget {
  const ErfassenSeite({
    super.key,
    required this.modell,
    this.geplant,
    this.artikel,
    this.vorhanden,
  });

  final ErfassungsModell modell;
  final PaketProduktion? geplant;
  final PaketArtikel? artikel;
  final ErfassteProduktion? vorhanden;

  @override
  State<ErfassenSeite> createState() => _ErfassenSeiteState();
}

class _ErfassenSeiteState extends State<ErfassenSeite> {
  late final ErfassteProduktion? _alt = widget.vorhanden;
  late final PaketProduktion? _plan = widget.geplant;

  String _zahl(double? v) => v == null ? '' : eingabeText(v);

  late final _roh = TextEditingController(text: _zahl(_alt?.rohKg));
  late final _fleisch = TextEditingController(text: _zahl(_alt?.fleischKg));
  late final _fertig = TextEditingController(text: _zahl(_alt?.fertigKg));
  late final _start = TextEditingController(text: _alt?.start ?? '');
  late final _ende = TextEditingController(text: _alt?.ende ?? '');
  late final _bemerkung = TextEditingController(text: _alt?.bemerkung ?? '');
  late final _kuerzel = TextEditingController(
    text: _alt?.kuerzel ?? widget.modell.stand.kuerzel,
  );

  late DateTime _datum = _alt?.datum ?? _plan?.datum ?? _heute;

  /// Was beim Speichern nicht stimmte.
  String? _fehler;

  static DateTime get _heute {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  String get _artikelId =>
      _plan?.artikelId ?? widget.artikel?.id ?? _alt?.artikelId ?? '';

  String get _artikelName =>
      _plan?.artikel ?? widget.artikel?.name ?? _alt?.artikel ?? '';

  String get _artikelNummer =>
      _plan?.artikelnummer ?? widget.artikel?.nummer ?? '';

  @override
  void dispose() {
    for (final c in [
      _roh,
      _fleisch,
      _fertig,
      _start,
      _ende,
      _bemerkung,
      _kuerzel,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Die Zahl im Feld — null bei leer; [ungueltig] meldet Text, der
  /// keine Zahl ist.
  double? _lies(TextEditingController c, void Function() ungueltig) {
    if (c.text.trim().isEmpty) return null;
    final z = zahlAus(c.text);
    if (z == null || z < 0) ungueltig();
    return z;
  }

  String? _liesZeit(TextEditingController c, void Function() ungueltig) {
    if (c.text.trim().isEmpty) return null;
    final z = zeitAus(c.text);
    if (z == null) ungueltig();
    return z;
  }

  String? _leerZuNull(String s) => s.trim().isEmpty ? null : s.trim();

  Future<void> _speichern() async {
    var zahlFalsch = false;
    var zeitFalsch = false;
    final roh = _lies(_roh, () => zahlFalsch = true);
    final fleisch = _lies(_fleisch, () => zahlFalsch = true);
    final fertig = _lies(_fertig, () => zahlFalsch = true);
    final start = _liesZeit(_start, () => zeitFalsch = true);
    final ende = _liesZeit(_ende, () => zeitFalsch = true);
    final fehler = zahlFalsch
        ? 'Bitte die Mengen als Zahl eintragen, etwa 512,5.'
        : zeitFalsch
            ? 'Bitte die Uhrzeit wie 6:30 oder 0630 eintragen.'
            : produktionFehler(
                rohKg: roh,
                fleischKg: fleisch,
                fertigKg: fertig,
              );
    if (fehler != null) {
      setState(() => _fehler = fehler);
      return;
    }
    final kuerzel = _leerZuNull(_kuerzel.text);
    if (kuerzel != null && kuerzel != widget.modell.stand.kuerzel) {
      await widget.modell.kuerzelSetzen(kuerzel);
    }
    final jetzt = DateTime.now();
    await widget.modell.produktionErfassen(
      ErfassteProduktion(
        produktionId: _plan?.id ??
            _alt?.produktionId ??
            'frei-${jetzt.microsecondsSinceEpoch}',
        artikelId: _artikelId,
        artikel: _artikelName,
        datum: _datum,
        rohKg: roh!,
        fleischKg: fleisch,
        fertigKg: fertig,
        start: start,
        ende: ende,
        kuerzel: kuerzel,
        bemerkung: _leerZuNull(_bemerkung.text),
        erfasstAm: jetzt,
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    melde(context, 'Erfasst: $_artikelName');
  }

  Future<void> _loeschen() async {
    final alt = _alt;
    if (alt == null) return;
    final ok = await nachfragen(
      context,
      titel: 'Erfassung löschen?',
      text: 'Die Erfassung von „${alt.artikel}" wird vom Handy gelöscht.',
      ja: 'Löschen',
      gefaehrlich: true,
    );
    if (!ok) return;
    await widget.modell.produktionLoeschen(alt.produktionId);
    if (mounted) Navigator.of(context).pop();
  }

  void _tag(int tage) => setState(
        () => _datum = DateTime(_datum.year, _datum.month, _datum.day + tage),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = theme.colorScheme;
    final plan = _plan;
    final artikel = widget.modell.stand.paket?.artikelMit(_artikelId);

    // Was sich aus den Eingaben schon ablesen lässt.
    final roh = _lies(_roh, () {});
    final fertig = _lies(_fertig, () {});
    final dauer = dauerMinuten(_start.text, _ende.text);
    final verlust = verlustAnteil(roh, fertig);
    final leistung = kgProStunde(fertig ?? roh, dauer);
    final kennzahlen = [
      if (verlust != null && verlust >= 0)
        'Verlust ${zahlText(verlust * 100)} %',
      if (dauer != null)
        'Dauer ${dauer ~/ 60}:'
            '${(dauer % 60).round().toString().padLeft(2, '0')} h',
      if (leistung != null) '${zahlText(leistung, nachkomma: 0)} kg/h',
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_alt == null ? 'Erfassen' : 'Erfassung ändern'),
        actions: [
          if (_alt != null)
            IconButton(
              tooltip: 'Erfassung löschen',
              onPressed: _loeschen,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            Text(
              _artikelName,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (_artikelNummer.isNotEmpty || plan != null)
              Text(
                [
                  if (_artikelNummer.isNotEmpty) _artikelNummer,
                  if (plan != null && plan.abteilungName.isNotEmpty)
                    plan.abteilungName,
                  if (plan == null) 'ohne Plan',
                ].join(' · '),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: f.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 12),
            Flaeche(
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Tag davor',
                    onPressed: () => _tag(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      tagLang(_datum, DateTime.now()),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Tag danach',
                    onPressed: () => _tag(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
            const Abschnitt('Mengen'),
            _MengenFeld(
              controller: _roh,
              label: 'Rohware (kg) *',
              plan: plan?.rohKg,
              onChanged: () => setState(() => _fehler = null),
            ),
            const SizedBox(height: 10),
            _MengenFeld(
              controller: _fleisch,
              label: 'davon Fleisch (kg)',
              plan: plan?.fleischKg,
              onChanged: () => setState(() => _fehler = null),
            ),
            const SizedBox(height: 10),
            _MengenFeld(
              controller: _fertig,
              label: 'Fertigware (kg)',
              plan: plan?.fertigKg,
              onChanged: () => setState(() => _fehler = null),
            ),
            const Abschnitt('Zeit'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _ZeitFeld(
                    controller: _start,
                    label: 'Start',
                    plan: plan?.start,
                    onChanged: () => setState(() => _fehler = null),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ZeitFeld(
                    controller: _ende,
                    label: 'Ende',
                    onChanged: () => setState(() => _fehler = null),
                  ),
                ),
              ],
            ),
            if (kennzahlen.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                kennzahlen.join(' · '),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: f.primary,
                ),
              ),
            ],
            const Abschnitt('Dazu'),
            TextField(
              controller: _bemerkung,
              decoration: const InputDecoration(labelText: 'Bemerkung'),
              minLines: 1,
              maxLines: 4,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _kuerzel,
              decoration: const InputDecoration(labelText: 'Kürzel'),
              maxLength: 12,
              textCapitalization: TextCapitalization.characters,
            ),
            if (_fehler case final fehler?) ...[
              Hinweis(fehler, farbe: f.error, icon: Icons.error_outline),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              onPressed: _speichern,
              icon: const Icon(Icons.check),
              label: const Text('Speichern'),
            ),
            if (artikel != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SchritteSeite(
                      modell: widget.modell,
                      artikel: artikel,
                    ),
                  ),
                ),
                icon: const Icon(Icons.tune),
                label: const Text('Maschineneinstellungen'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Ein Mengenfeld mit Zahlentastatur — der Plan steht darunter und lässt
/// sich mit einem Tipp übernehmen.
class _MengenFeld extends StatelessWidget {
  const _MengenFeld({
    required this.controller,
    required this.label,
    required this.onChanged,
    this.plan,
  });

  final TextEditingController controller;
  final String label;
  final double? plan;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final p = plan;
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9.,]'))],
      textInputAction: TextInputAction.next,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        helperText: p == null ? null : 'geplant ${zahlText(p)} kg',
        suffixIcon: p == null
            ? null
            : TextButton(
                onPressed: () {
                  controller.text = eingabeText(p);
                  onChanged();
                },
                child: const Text('Plan'),
              ),
      ),
      onChanged: (_) => onChanged(),
    );
  }
}

/// Eine Uhrzeit: eintippen (6:30, 0630) oder „Jetzt".
class _ZeitFeld extends StatelessWidget {
  const _ZeitFeld({
    required this.controller,
    required this.label,
    required this.onChanged,
    this.plan,
  });

  final TextEditingController controller;
  final String label;
  final String? plan;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          keyboardType: TextInputType.datetime,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[0-9:.]')),
            LengthLimitingTextInputFormatter(5),
          ],
          textInputAction: TextInputAction.next,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            labelText: label,
            hintText: '00:00',
            helperText: plan == null ? null : 'geplant $plan',
          ),
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 6),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(64, Masse.tippHoehe - 12),
          ),
          onPressed: () {
            controller.text = uhrzeit(DateTime.now());
            onChanged();
          },
          child: const Text('Jetzt'),
        ),
      ],
    );
  }
}
