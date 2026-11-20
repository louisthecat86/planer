import 'package:erfassung_format/erfassung_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'artikel_seite.dart';
import 'bausteine.dart';
import 'fotos.dart';
import 'modell.dart';
import 'stand.dart';
import 'stil.dart';

/// Eine Produktion erfassen: Rohware, davon Fleisch, Fertigware, Start und
/// Ende und Bemerkung — dieselben Angaben wie in der
/// Produktionserfassung des Planers. Dazu Fotos aus der Produktion: Sie
/// gehören zum Artikel und bleiben auch, wenn die Erfassung nicht
/// gespeichert wird.
///
/// [geplant] ist die Produktion aus dem Paket; ohne Plan steht der
/// [artikel] fest. [vorhanden] ist eine frühere Erfassung zum Ändern,
/// [begonnen] eine zwischengespeicherte ohne Plan zum Weitermachen.
/// Mit [fertigMelden] kommt die Seite von „Fertig": Ist noch kein Ende
/// eingetragen, steht dort die Uhrzeit des Handys, und der Cursor steht in
/// der Fertigware.
///
/// Zwischenspeichern: Was eingetragen ist, bleibt auch ohne Erfassen —
/// über den Knopf, beim Zurückgehen und wenn die App in den Hintergrund
/// geht. So lassen sich Rohware und Startzeit schon eintragen, solange
/// die Produktion läuft, und der Rest danach.
class ErfassenSeite extends StatefulWidget {
  const ErfassenSeite({
    super.key,
    required this.modell,
    this.geplant,
    this.artikel,
    this.vorhanden,
    this.begonnen,
    this.fertigMelden = false,
  });

  final ErfassungsModell modell;
  final bool fertigMelden;
  final PaketProduktion? geplant;
  final PaketArtikel? artikel;
  final ErfassteProduktion? vorhanden;
  final ProduktionsEntwurf? begonnen;

  @override
  State<ErfassenSeite> createState() => _ErfassenSeiteState();
}

class _ErfassenSeiteState extends State<ErfassenSeite>
    with WidgetsBindingObserver {
  late final ErfassteProduktion? _alt = widget.vorhanden;
  late final PaketProduktion? _plan = widget.geplant;

  /// Die ID der Produktion — aus dem Plan, aus der früheren Erfassung
  /// oder, ohne Plan, eine eigene. Sie steht von Anfang an fest, damit
  /// das Zwischengespeicherte und die Erfassung dieselbe tragen.
  late final String _id = _plan?.id ??
      _alt?.produktionId ??
      widget.begonnen?.produktionId ??
      'frei-${DateTime.now().microsecondsSinceEpoch}';

  /// Was zu dieser Produktion zwischengespeichert ist. Eine fertige
  /// Erfassung geht vor: Wer sie ändert, sieht ihre Werte.
  late final ProduktionsEntwurf? _entwurf =
      _alt != null ? null : widget.modell.stand.entwuerfe[_id];

  String _zahl(double? v) => v == null ? '' : eingabeText(v);

  late final _roh = TextEditingController(
    text: _entwurf?.roh ?? _zahl(_alt?.rohKg),
  );
  late final _fleisch = TextEditingController(
    text: _entwurf?.fleisch ?? _zahl(_alt?.fleischKg),
  );
  late final _fertig = TextEditingController(
    text: _entwurf?.fertig ?? _zahl(_alt?.fertigKg),
  );
  late final _start = TextEditingController(
    text: _entwurf?.start ?? _alt?.start ?? '',
  );
  late final _ende = TextEditingController(
    text: _entwurf?.ende ?? _alt?.ende ?? '',
  );
  late final _endeVpk = TextEditingController(
    text: _entwurf?.endeVpk ?? _alt?.endeVpk ?? '',
  );
  late final _bemerkung = TextEditingController(
    text: _entwurf?.bemerkung ?? _alt?.bemerkung ?? '',
  );
  late final _kuerzel = TextEditingController(
    text: _alt?.kuerzel ?? widget.modell.stand.kuerzel,
  );

  late DateTime _datum =
      _entwurf?.datum ?? _alt?.datum ?? _plan?.datum ?? _heute;

  /// Erfasst oder gelöscht: Danach wird nichts mehr zwischengespeichert.
  bool _erledigt = false;

  /// Was beim Speichern nicht stimmte.
  String? _fehler;

  static DateTime get _heute {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  String get _artikelId =>
      _plan?.artikelId ??
      widget.artikel?.id ??
      _alt?.artikelId ??
      _entwurf?.artikelId ??
      '';

  String get _artikelName =>
      _plan?.artikel ??
      widget.artikel?.name ??
      _alt?.artikel ??
      _entwurf?.artikel ??
      '';

  String get _artikelNummer =>
      _plan?.artikelnummer ?? widget.artikel?.nummer ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // „Fertig": die Uhrzeit ins erste Ende, das noch leer ist — erst
    // Auflegen, dann Verpackung.
    if (widget.fertigMelden && _alt == null) {
      if (_ende.text.trim().isEmpty) {
        _ende.text = uhrzeit(DateTime.now());
      } else if (_endeVpk.text.trim().isEmpty) {
        _endeVpk.text = uhrzeit(DateTime.now());
      }
    }
  }

  /// Geht die App in den Hintergrund, kann Android sie jederzeit
  /// schließen — vorher festhalten, was eingetragen ist.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _zwischenspeichern();
    }
  }

  /// Hält fest, was eingetragen ist, ohne die Produktion zu erfassen.
  /// Beim Ändern einer fertigen Erfassung geschieht nichts: Die gilt, bis
  /// sie neu erfasst wird.
  Future<void> _zwischenspeichern() async {
    if (_erledigt || _alt != null) return;
    await widget.modell.entwurfMerken(
      ProduktionsEntwurf(
        produktionId: _id,
        artikelId: _artikelId,
        artikel: _artikelName,
        datum: _datum,
        geaendertAm: DateTime.now(),
        roh: _mengeText(_roh),
        fleisch: _mengeText(_fleisch),
        fertig: _mengeText(_fertig),
        start: _start.text.trim(),
        ende: _ende.text.trim(),
        endeVpk: _endeVpk.text.trim(),
        bemerkung: _bemerkung.text.trim(),
      ),
    );
  }

  /// Der Knopf: festhalten und zurück zur Liste.
  Future<void> _zwischenspeichernUndZurueck() async {
    await _zwischenspeichern();
    _erledigt = true;
    if (!mounted) return;
    Navigator.of(context).pop();
    melde(context, 'Zwischengespeichert: $_artikelName');
  }

  /// Verwirft, was zwischengespeichert ist.
  Future<void> _entwurfVerwerfen() async {
    final ok = await nachfragen(
      context,
      titel: 'Begonnene Erfassung verwerfen?',
      text: 'Was zu „$_artikelName" eingetragen ist, wird vom Handy '
          'gelöscht.',
      ja: 'Verwerfen',
      gefaehrlich: true,
    );
    if (!ok) return;
    _erledigt = true;
    await widget.modell.entwurfLoeschen(_id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final c in [
      _roh,
      _fleisch,
      _fertig,
      _start,
      _ende,
      _endeVpk,
      _bemerkung,
      _kuerzel,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Die Zahl im Feld — null bei leer; [ungueltig] meldet Text, der
  /// keine Zahl ist.
  /// Was von einem Mengenfeld gemerkt wird: bei einer Rechnung ihr
  /// Ergebnis, sonst der Text.
  static String _mengeText(TextEditingController c) {
    final t = c.text.trim();
    if (!istRechnung(t)) return t;
    final wert = rechneAus(t);
    return wert == null ? t : eingabeText(wert);
  }

  double? _lies(TextEditingController c, void Function() ungueltig) {
    if (c.text.trim().isEmpty) return null;
    // Auch eine Rechnung, die noch nicht ersetzt ist — gespeichert wird
    // ihr Ergebnis.
    final z = rechneAus(c.text);
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

  /// Was die Erfahrung über die Dauer sagt — mit der eingetragenen
  /// Rohware, sonst der geplanten.
  Prognose _prognose(PaketProduktion? plan) => widget.modell.stand.prognose(
        artikelId: _artikelId,
        kg: rechneAus(_roh.text) ?? plan?.rohKg,
        start: _start.text,
      );

  /// Nach „Jetzt" am Start: wie lange es dauert, oder warum sich das nicht
  /// sagen lässt.
  Future<void> _prognoseZeigen(PaketProduktion? plan) async {
    final p = _prognose(plan);
    await prognoseZeigen(
      context,
      titel: 'Gestartet um ${zeitAus(_start.text) ?? _start.text}',
      text: p.text,
      ermittelt: p.minuten != null,
      ende: p.ende,
    );
  }

  Future<void> _speichern() async {
    var zahlFalsch = false;
    var zeitFalsch = false;
    final roh = _lies(_roh, () => zahlFalsch = true);
    final fleisch = _lies(_fleisch, () => zahlFalsch = true);
    final fertig = _lies(_fertig, () => zahlFalsch = true);
    final start = _liesZeit(_start, () => zeitFalsch = true);
    final ende = _liesZeit(_ende, () => zeitFalsch = true);
    final endeVpk = _liesZeit(_endeVpk, () => zeitFalsch = true);
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
    // Ab hier nichts mehr zwischenspeichern — die Erfassung ersetzt es.
    _erledigt = true;
    await widget.modell.produktionErfassen(
      ErfassteProduktion(
        produktionId: _id,
        artikelId: _artikelId,
        artikel: _artikelName,
        datum: _datum,
        rohKg: roh!,
        fleischKg: fleisch,
        fertigKg: fertig,
        start: start,
        ende: ende,
        endeVpk: endeVpk,
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
    _erledigt = true;
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
    final farben = Farben.von(context);
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
        ('Ausbeute', '${zahlText((1 - verlust) * 100)} %'),
      if (verlust != null && verlust >= 0)
        ('Verlust', '${zahlText(verlust * 100)} %'),
      if (dauer != null) ('Dauer', dauerText(dauer)),
      if (dauerMinuten(_start.text, _endeVpk.text) case final d?)
        ('Bis VPK', dauerText(d)),
      if (leistung != null)
        (
          'Leistung',
          '${zahlText(leistung, nachkomma: 0)} '
              'kg/h'
        ),
    ];

    final begonnen = _alt == null && widget.modell.stand.entwuerfe[_id] != null;

    // Zurück hält fest, was eingetragen ist — nichts geht verloren, nur
    // weil die Produktion noch nicht fertig ist.
    return PopScope(
      onPopInvokedWithResult: (weg, _) {
        if (weg) _zwischenspeichern();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_alt == null ? 'Erfassen' : 'Erfassung ändern'),
          actions: [
            if (_alt != null)
              IconButton(
                tooltip: 'Erfassung löschen',
                onPressed: _loeschen,
                icon: const Icon(Icons.delete_outline),
              )
            else if (begonnen)
              IconButton(
                tooltip: 'Begonnene Erfassung verwerfen',
                onPressed: _entwurfVerwerfen,
                icon: const Icon(Icons.delete_outline),
              ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            children: [
              Text(
                _artikelName,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (plan != null && plan.abteilungName.isNotEmpty) ...[
                    Flexible(
                      child: AbteilungsMarke(
                        name: plan.abteilungName,
                        farbe: plan.abteilungFarbe,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Text(
                    [
                      if (_artikelNummer.isNotEmpty) _artikelNummer,
                      if (plan == null) 'ohne Plan',
                    ].join(' · '),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: f.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (_entwurf case final e?) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Marke(
                      zeitAus(e.start) != null ? 'läuft' : 'begonnen',
                      farbe:
                          zeitAus(e.start) != null ? farben.warnung : f.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Begonnen — zwischengespeichert '
                        '${tagKurz(e.geaendertAm)} um '
                        '${uhrzeit(e.geaendertAm)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: f.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
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
                          fontWeight: FontWeight.w700,
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
              Flaeche(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _MengenFeld(
                        controller: _roh,
                        label: 'Rohware (kg) *',
                        kennung: 'roh',
                        plan: plan?.rohKg,
                        onChanged: () => setState(() => _fehler = null),
                      ),
                      const SizedBox(height: 10),
                      _MengenFeld(
                        controller: _fleisch,
                        label: 'davon Fleisch (kg)',
                        kennung: 'fleisch',
                        plan: plan?.fleischKg,
                        onChanged: () => setState(() => _fehler = null),
                      ),
                      const SizedBox(height: 10),
                      _MengenFeld(
                        controller: _fertig,
                        label: 'Fertigware (kg)',
                        kennung: 'fertig',
                        plan: plan?.fertigKg,
                        autofocus: widget.fertigMelden,
                        hervorheben: widget.fertigMelden,
                        onChanged: () => setState(() => _fehler = null),
                      ),
                    ],
                  ),
                ),
              ),
              const Abschnitt('Zeit'),
              Flaeche(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _ZeitFeld(
                              controller: _start,
                              label: 'Start',
                              kennung: 'Start',
                              plan: plan?.start,
                              onChanged: () => setState(() => _fehler = null),
                              onJetzt: () => _prognoseZeigen(plan),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _ZeitFeld(
                              controller: _ende,
                              label: 'Ende Auflegen',
                              kennung: 'Ende',
                              onChanged: () => setState(() => _fehler = null),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _ZeitFeld(
                              controller: _endeVpk,
                              label: 'Ende VPK',
                              kennung: 'EndeVpk',
                              onChanged: () => setState(() => _fehler = null),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                'Wann das Letzte verpackt ist. Die Leistung '
                                'zählt von Start bis Ende Auflegen.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: f.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (zeitAus(_start.text) != null &&
                  zeitAus(_ende.text) == null) ...[
                const SizedBox(height: 10),
                Builder(
                  builder: (context) {
                    final p = _prognose(plan);
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          p.minuten == null
                              ? Icons.help_outline
                              : Icons.timer_outlined,
                          size: 20,
                          color: p.minuten == null
                              ? f.onSurfaceVariant
                              : farben.warnung,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            p.text,
                            key: const ValueKey('prognose-text'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: f.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
              if (kennzahlen.isNotEmpty) ...[
                const SizedBox(height: 10),
                // Drei Kacheln je Reihe.
                LayoutBuilder(
                  builder: (context, c) => Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (name, wert) in kennzahlen)
                        SizedBox(
                          width: (c.maxWidth - 16) / 3,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                            decoration: BoxDecoration(
                              color: f.surface,
                              borderRadius: Masse.eckenKlein,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: f.onSurfaceVariant,
                                  ),
                                ),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    wert,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: farben.ok,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const Abschnitt('Dazu'),
              Flaeche(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      TextField(
                        controller: _bemerkung,
                        decoration:
                            const InputDecoration(labelText: 'Bemerkung'),
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
                    ],
                  ),
                ),
              ),
              if (_artikelId.isNotEmpty) ...[
                const Abschnitt('Fotos aus der Produktion'),
                FotoStreifen(
                  modell: widget.modell,
                  artikelId: _artikelId,
                  artikel: _artikelName,
                  produktionId: _id,
                ),
              ],
              const SizedBox(height: 20),
              if (_fehler case final fehler?) ...[
                Hinweis(fehler, farbe: f.error, icon: Icons.error_outline),
                const SizedBox(height: 12),
              ],
              FilledButton.icon(
                key: const ValueKey('produktion-erfassen'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(60),
                  backgroundColor: farben.ok,
                  foregroundColor: Colors.black,
                  textStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onPressed: _speichern,
                icon: const Icon(Icons.check),
                label: Text(
                  _alt == null ? 'Produktion erfassen' : 'Änderung speichern',
                ),
              ),
              if (_alt == null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('zwischenspeichern'),
                  onPressed: _zwischenspeichernUndZurueck,
                  icon: const Icon(Icons.pending_actions),
                  label: const Text('Zwischenspeichern'),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Hält fest, was eingetragen ist — die Produktion bleibt '
                    'offen, bis sie erfasst wird.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: f.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
              if (artikel != null) ...[
                const SizedBox(height: 8),
                TextButton.icon(
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
      ),
    );
  }
}

/// Ein Mengenfeld mit Zahlentastatur — der Plan steht darunter und lässt
/// sich mit einem Tipp übernehmen.
class _MengenFeld extends StatefulWidget {
  const _MengenFeld({
    required this.controller,
    required this.label,
    required this.kennung,
    required this.onChanged,
    this.plan,
    this.autofocus = false,
    this.hervorheben = false,
  });

  final TextEditingController controller;
  final String label;

  /// Für die Schlüssel der Rechentasten: `rechnen-<kennung>-…`.
  final String kennung;
  final double? plan;
  final VoidCallback onChanged;
  final bool autofocus;

  /// Das Feld, um das es gerade geht — mit Rand in der Farbe der Aktion.
  final bool hervorheben;

  @override
  State<_MengenFeld> createState() => _MengenFeldState();
}

/// Rechnen im Feld: „270*10" zeigt darunter „= 2.700 kg". Beim Verlassen
/// des Feldes oder mit „=" steht nur noch das Ergebnis da — gespeichert
/// wird nie die Rechnung.
class _MengenFeldState extends State<_MengenFeld> {
  final _fokus = FocusNode();

  TextEditingController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _fokus.addListener(_fokusGeaendert);
  }

  @override
  void dispose() {
    _fokus
      ..removeListener(_fokusGeaendert)
      ..dispose();
    super.dispose();
  }

  void _fokusGeaendert() {
    if (!_fokus.hasFocus) _ausrechnen();
    if (mounted) setState(() {});
  }

  /// Ersetzt eine Rechnung durch ihr Ergebnis. Eine unvollständige bleibt
  /// stehen — das Speichern sagt dann, dass es keine Zahl ist.
  void _ausrechnen() {
    if (!istRechnung(_c.text)) return;
    final wert = rechneAus(_c.text);
    if (wert == null) return;
    _c.value = TextEditingValue(
      text: eingabeText(wert),
      selection: TextSelection.collapsed(offset: eingabeText(wert).length),
    );
    widget.onChanged();
  }

  /// Setzt [zeichen] an die Stelle des Cursors.
  void _einfuegen(String zeichen) {
    final v = _c.value;
    final sel = v.selection.isValid
        ? v.selection
        : TextSelection.collapsed(offset: v.text.length);
    final text = v.text.replaceRange(sel.start, sel.end, zeichen);
    _c.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: sel.start + zeichen.length),
    );
    widget.onChanged();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.plan;
    final theme = Theme.of(context);
    final f = theme.colorScheme;
    final farben = Farben.von(context);
    final rechnung = istRechnung(_c.text);
    final ergebnis = rechnung ? rechneAus(_c.text) : null;
    final String? hilfe;
    final Color? hilfeFarbe;
    if (rechnung && ergebnis != null) {
      hilfe = '= ${zahlText(ergebnis, nachkomma: 2)} kg';
      hilfeFarbe = farben.ok;
    } else if (rechnung) {
      hilfe = 'Rechnung noch nicht vollständig';
      hilfeFarbe = farben.warnung;
    } else {
      hilfe = p == null ? null : 'geplant ${zahlText(p)} kg';
      hilfeFarbe = null;
    }

    Widget taste(String zeichen, String name, {String? anzeige}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: FilledButton.tonal(
              key: ValueKey('rechnen-${widget.kennung}-$name'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 46),
                padding: EdgeInsets.zero,
                textStyle: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onPressed: zeichen == '='
                  ? () {
                      _ausrechnen();
                      setState(() {});
                    }
                  : () => _einfuegen(zeichen),
              child: Text(anzeige ?? zeichen),
            ),
          ),
        );

    // Die Tasten zählen als Teil des Feldes: Antippen nimmt ihm den Cursor
    // nicht.
    return TextFieldTapRegion(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _c,
            focusNode: _fokus,
            autofocus: widget.autofocus,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                RegExp(r'[0-9.,+\-−*x×X/:÷() ]'),
              ),
            ],
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              labelText: widget.label,
              enabledBorder: widget.hervorheben
                  ? OutlineInputBorder(
                      borderRadius: Masse.eckenKlein,
                      borderSide: BorderSide(color: f.primary, width: 1.5),
                    )
                  : null,
              helperText: hilfe,
              helperStyle: hilfeFarbe == null
                  ? null
                  : theme.textTheme.bodyMedium?.copyWith(
                      color: hilfeFarbe,
                      fontWeight: FontWeight.w700,
                    ),
              suffixIcon: p == null
                  ? null
                  : TextButton(
                      onPressed: () {
                        _c.text = eingabeText(p);
                        widget.onChanged();
                      },
                      child: const Text('Plan'),
                    ),
            ),
            onChanged: (_) {
              widget.onChanged();
              setState(() {});
            },
            onSubmitted: (_) => _ausrechnen(),
          ),
          if (_fokus.hasFocus)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  taste('×', 'mal'),
                  taste('+', 'plus'),
                  taste('−', 'minus'),
                  taste('/', 'geteilt', anzeige: '÷'),
                  taste('=', 'gleich'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Eine Uhrzeit: eintippen (6:30, 0630) oder „Jetzt".
class _ZeitFeld extends StatelessWidget {
  const _ZeitFeld({
    required this.controller,
    required this.label,
    required this.onChanged,
    required this.kennung,
    this.plan,
    this.onJetzt,
  });

  /// Für den Schlüssel von „Jetzt": `jetzt-<kennung>`.
  final String kennung;

  final TextEditingController controller;
  final String label;
  final String? plan;
  final VoidCallback onChanged;

  /// Nach „Jetzt" — etwa um beim Start die Dauer zu zeigen.
  final VoidCallback? onJetzt;

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
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            labelText: label,
            hintText: '00:00',
            helperText: plan == null ? null : 'geplant $plan',
          ),
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 6),
        // „Jetzt" übernimmt die Uhrzeit des Handys — bleibt, wie es ist.
        FilledButton.tonalIcon(
          key: ValueKey('jetzt-$kennung'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(64, Masse.tippHoehe - 8),
          ),
          onPressed: () {
            controller.text = uhrzeit(DateTime.now());
            onChanged();
            onJetzt?.call();
          },
          icon: const Icon(Icons.schedule, size: 20),
          label: const Text('Jetzt'),
        ),
      ],
    );
  }
}
