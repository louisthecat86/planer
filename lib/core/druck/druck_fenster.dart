import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../database/database.dart';
import '../providers/database_provider.dart';
import '../theme/app_stil.dart';
import '../ui/bausteine.dart';
import '../utils/fehler_text.dart';
import '../utils/format.dart';
import 'druck_layout.dart';
import 'druck_optionen.dart';
import 'druck_satz.dart';
import 'druck_speicher.dart';

/// Das Druckfenster: links, was und wie gedruckt wird, rechts die
/// Vorschau, die jeder Änderung folgt. Gedruckt wird über den
/// Druckdialog des Systems — oder als PDF gespeichert.
///
/// Liefert true, wenn gedruckt oder gespeichert wurde.
Future<bool> druckFensterOeffnen(
  BuildContext context,
  DruckAuftrag auftrag,
) async {
  final ergebnis = await showDialog<bool>(
    context: context,
    builder: (_) => DruckFenster(auftrag: auftrag),
  );
  return ergebnis ?? false;
}

/// Was das Druckfenster vom System braucht: gemerkte Einstellungen, die
/// Vorschau, den Druckdialog und das Speichern. In Tests ersetzbar —
/// Vorschau und Druckdialog gibt es dort nicht.
class DruckSystem {
  const DruckSystem(this._db);

  /// null: nichts merken.
  final AppDatabase? _db;

  Future<Object?> laden(String art) async {
    final db = _db;
    return db == null ? null : druckEinstellungLaden(db, art);
  }

  Future<void> merken(String art, Map<String, Object> json) async {
    final db = _db;
    if (db != null) await druckEinstellungSpeichern(db, art, json);
  }

  /// Die Seiten zum Ansehen.
  Widget vorschau(
    BuildContext context,
    DruckErgebnis ergebnis,
    LayoutCallback bauen,
    String dateiname,
  ) {
    return PdfPreview(
      build: bauen,
      useActions: false,
      canChangePageFormat: false,
      canChangeOrientation: false,
      canDebug: false,
      allowPrinting: false,
      allowSharing: false,
      pdfFileName: '$dateiname.pdf',
      maxPageWidth: 780,
      padding: const EdgeInsets.all(16),
      scrollViewDecoration: const BoxDecoration(color: Colors.transparent),
      loadingWidget: const Center(child: CircularProgressIndicator()),
    );
  }

  /// Öffnet den Druckdialog. true: gedruckt.
  Future<bool> drucken(DruckErgebnis ergebnis, String dateiname) =>
      Printing.layoutPdf(
        onLayout: (_) async => ergebnis.bytes,
        name: dateiname,
        format: ergebnis.format,
      );

  /// Fragt nach Ort und Namen und speichert. Liefert den Pfad — null:
  /// abgebrochen.
  Future<String?> speichern(DruckErgebnis ergebnis, String dateiname) async {
    final pfad = await FilePicker.saveFile(
      dialogTitle: 'Als PDF speichern',
      fileName: '$dateiname.pdf',
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (pfad == null) return null;
    final ziel = pfad.toLowerCase().endsWith('.pdf') ? pfad : '$pfad.pdf';
    await File(ziel).writeAsBytes(ergebnis.bytes, flush: true);
    return ziel;
  }
}

/// Das Feld einer [DruckZahl]: Was gilt, geht sofort an das Fenster. Was
/// nicht gilt, steht rot darunter — gesetzt bleibt der letzte gültige
/// Wert.
class _ZahlFeld extends StatefulWidget {
  const _ZahlFeld({
    super.key,
    required this.option,
    required this.wert,
    required this.onWert,
  });

  final DruckZahl option;
  final double wert;
  final ValueChanged<double> onWert;

  @override
  State<_ZahlFeld> createState() => _ZahlFeldState();
}

class _ZahlFeldState extends State<_ZahlFeld> {
  late final TextEditingController _text =
      TextEditingController(text: Format.eingabe(widget.wert));
  String? _fehler;

  @override
  void didUpdateWidget(_ZahlFeld alt) {
    super.didUpdateWidget(alt);
    // Von außen geändert — etwa über „Zurücksetzen": Das Feld zeigt den
    // neuen Wert, wenn es nicht schon ihn zeigt.
    if (alt.wert == widget.wert) return;
    final gezeigt = Format.lies(_text.text);
    if (gezeigt == null || (gezeigt - widget.wert).abs() > 1e-9) {
      _text.text = Format.eingabe(widget.wert);
      _fehler = null;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _geaendert(String text) {
    final o = widget.option;
    final einheit = o.einheit == null ? '' : ' ${o.einheit}';
    final w = Format.lies(text);
    final fehler = w == null
        ? 'Bitte eine Zahl eingeben.'
        : w < o.min
            ? 'Mindestens ${Format.eingabe(o.min)}$einheit.'
            : w > o.max
                ? 'Höchstens ${Format.eingabe(o.max)}$einheit.'
                : null;
    setState(() => _fehler = fehler);
    if (fehler == null && w != null) widget.onWert(w);
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _text,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          isDense: true,
          suffixText: widget.option.einheit,
          errorText: _fehler,
        ),
        onChanged: _geaendert,
      );
}

final druckSystemProvider = Provider<DruckSystem>(
  (ref) => DruckSystem(ref.watch(databaseProvider)),
);

/// Das Fenster zu [druckFensterOeffnen].
class DruckFenster extends ConsumerStatefulWidget {
  const DruckFenster({super.key, required this.auftrag});

  final DruckAuftrag auftrag;

  @override
  ConsumerState<DruckFenster> createState() => _DruckFensterState();
}

class _DruckFensterState extends ConsumerState<DruckFenster> {
  late final DruckSystem _system = ref.read(druckSystemProvider);

  /// null, solange die gemerkten Einstellungen laden.
  DruckWahl? _wahl;

  /// Das zuletzt gesetzte Dokument — null vor dem ersten Satz.
  DruckErgebnis? _ergebnis;
  String _dateiname = 'Druck';

  /// Für die Vorschau: dieselbe Funktion, bis ein neues Ergebnis kommt —
  /// eine neue setzt die Vorschau neu.
  LayoutCallback? _vorschauBauen;

  /// Die Wahl hat sich geändert, das Ergebnis passt noch nicht dazu.
  bool _veraltet = true;

  /// Gerade gedruckt oder gespeichert.
  bool _beschaeftigt = false;

  /// Nichts gewählt, was sich drucken ließe — was fehlt.
  String? _nichtsGewaehlt;
  Object? _fehler;

  /// Zählt die Sätze: Ein langsamer alter überschreibt keinen neueren.
  int _stand = 0;
  Timer? _verzoegerung;

  DruckAuftrag get _auftrag => widget.auftrag;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  @override
  void dispose() {
    _verzoegerung?.cancel();
    super.dispose();
  }

  Future<void> _laden() async {
    Object? gemerkt;
    try {
      gemerkt = await _system.laden(_auftrag.art);
    } catch (_) {
      // Ohne gemerkte Einstellungen geht es mit dem Standard weiter.
    }
    if (!mounted) return;
    setState(() {
      _wahl = DruckWahl.fromJson(
        gemerkt,
        _auftrag.optionen,
        layout: _auftrag.standardLayout,
      );
    });
    await _setzen();
  }

  /// Übernimmt [neu] und setzt das Dokument kurz danach neu — wer schnell
  /// mehrere Häkchen setzt, wartet nicht nach jedem.
  void _aendern(DruckWahl neu) {
    // Ein Satz, der noch läuft, gilt für die alte Wahl — sein Ergebnis
    // käme zu spät und darf nicht mehr gedruckt werden.
    _stand++;
    setState(() {
      _wahl = neu;
      _veraltet = true;
    });
    _verzoegerung?.cancel();
    _verzoegerung = Timer(const Duration(milliseconds: 250), _setzen);
  }

  void _setze(String schluessel, Object wert) {
    final wahl = _wahl;
    if (wahl != null) _aendern(wahl.mit(schluessel, wert));
  }

  void _layout(DruckLayout neu) {
    final wahl = _wahl;
    if (wahl != null) _aendern(wahl.mitLayout(neu));
  }

  Future<void> _setzen() async {
    final wahl = _wahl;
    if (wahl == null) return;
    final stand = ++_stand;
    setState(() => _veraltet = true);
    // Einen Frame Luft, damit der Fortschrittsbalken erscheint, bevor
    // das Setzen rechnet.
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted || stand != _stand) return;
    try {
      final dokument = await _auftrag.bauen(wahl);
      if (dokument.blaetter.isEmpty) {
        throw const DruckNichtsGewaehlt(
          'Nichts zu drucken — wähle links, was auf das Papier soll.',
        );
      }
      final ergebnis = await druckSetzen(dokument, wahl.layout);
      if (!mounted || stand != _stand) return;
      setState(() {
        _ergebnis = ergebnis;
        _dateiname = dokument.dateiname;
        _vorschauBauen = (_) async => ergebnis.bytes;
        _nichtsGewaehlt = null;
        _fehler = null;
        _veraltet = false;
      });
    } on DruckNichtsGewaehlt catch (e) {
      if (!mounted || stand != _stand) return;
      setState(() {
        _nichtsGewaehlt = e.text;
        _fehler = null;
        _veraltet = false;
      });
    } catch (e) {
      if (!mounted || stand != _stand) return;
      setState(() {
        _fehler = e;
        _nichtsGewaehlt = null;
        _veraltet = false;
      });
    }
  }

  bool get _bereit =>
      _ergebnis != null &&
      !_veraltet &&
      !_beschaeftigt &&
      _nichtsGewaehlt == null &&
      _fehler == null;

  Future<void> _merken() async {
    final wahl = _wahl;
    if (wahl == null) return;
    try {
      await _system.merken(_auftrag.art, wahl.toJson(_auftrag.optionen));
    } catch (_) {
      // Nur eine Bequemlichkeit — gedruckt ist trotzdem.
    }
  }

  Future<void> _drucken() async {
    final ergebnis = _ergebnis;
    if (!_bereit || ergebnis == null) return;
    setState(() => _beschaeftigt = true);
    try {
      final gedruckt = await _system.drucken(ergebnis, _dateiname);
      if (!gedruckt) return;
      await _merken();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _melde('Drucken ging nicht: ${fehlerText(e)}');
    } finally {
      if (mounted) setState(() => _beschaeftigt = false);
    }
  }

  Future<void> _speichern() async {
    final ergebnis = _ergebnis;
    if (!_bereit || ergebnis == null) return;
    setState(() => _beschaeftigt = true);
    try {
      final pfad = await _system.speichern(ergebnis, _dateiname);
      if (pfad == null) return;
      await _merken();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop(true);
      messenger?.showSnackBar(SnackBar(content: Text('Gespeichert: $pfad')));
    } catch (e) {
      _melde('Speichern ging nicht: ${fehlerText(e)}');
    } finally {
      if (mounted) setState(() => _beschaeftigt = false);
    }
  }

  void _melde(String text) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(duration: const Duration(seconds: 8), content: Text(text)),
    );
  }

  void _zuruecksetzen() => _aendern(
        DruckWahl.standard(
          _auftrag.optionen,
          layout: _auftrag.standardLayout,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groesse = MediaQuery.sizeOf(context);
    final breite = (groesse.width - 48).clamp(640.0, 1440.0);
    final hoehe = (groesse.height - 48).clamp(420.0, 1000.0);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): () {
          if (_bereit) _drucken();
        },
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          insetPadding: const EdgeInsets.all(24),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: breite,
            height: hoehe,
            child: Column(
              children: [
                _kopf(theme),
                const Divider(height: 1),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 360, child: _seitenleiste(theme)),
                      const VerticalDivider(width: 1),
                      Expanded(child: _vorschauBereich(theme)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                _fuss(theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _kopf(ThemeData theme) {
    final untertitel = _auftrag.untertitel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 10),
      child: Row(
        children: [
          Icon(Icons.print_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_auftrag.titel, style: theme.textTheme.titleLarge),
                if (untertitel != null)
                  Text(
                    untertitel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Schließen',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }

  // ── Links: was und wie ───────────────────────────────────────────────

  Widget _seitenleiste(ThemeData theme) {
    final wahl = _wahl;
    if (wahl == null) return const SizedBox.shrink();
    final optionen = [
      for (final o in _auftrag.optionen)
        if (o.istSichtbar(wahl)) o,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 16),
      children: [
        if (optionen.isNotEmpty) ...[
          _abschnitt(theme, 'Was wird gedruckt?'),
          ..._optionen(theme, wahl, optionen),
          const SizedBox(height: 8),
        ],
        _abschnitt(theme, 'Wie wird gedruckt?'),
        ..._wie(theme, wahl.layout),
      ],
    );
  }

  Widget _abschnitt(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 2),
        child: Text(
          text.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: theme.colorScheme.primary,
          ),
        ),
      );

  Widget _titel(ThemeData theme, String text, [String? hinweis]) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: theme.textTheme.titleSmall),
            if (hinweis != null)
              Text(
                hinweis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      );

  List<Widget> _optionen(
    ThemeData theme,
    DruckWahl wahl,
    List<DruckOption> optionen,
  ) {
    final kinder = <Widget>[];
    String? gruppe;
    for (final o in optionen) {
      final neueGruppe = o.gruppe;
      if (neueGruppe != null && neueGruppe != gruppe) {
        kinder.add(_titel(theme, neueGruppe));
      }
      gruppe = neueGruppe;
      kinder.add(
        switch (o) {
          DruckSchalter() => _schalter(o, wahl),
          DruckWahlEins() => _wahlEins(theme, o, wahl),
          DruckWahlMehrere() => _wahlMehrere(theme, o, wahl),
          DruckZahl() => _zahl(theme, o, wahl),
        },
      );
    }
    return kinder;
  }

  Widget? _unterzeile(String? text) => text == null ? null : Text(text);

  Widget _schalter(DruckSchalter o, DruckWahl wahl) => CheckboxListTile(
        value: wahl.an(o.schluessel),
        onChanged: (an) => _setze(o.schluessel, an ?? false),
        title: Text(o.titel),
        subtitle: _unterzeile(o.hinweis),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        dense: true,
      );

  Widget _wahlEins(ThemeData theme, DruckWahlEins o, DruckWahl wahl) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titel(theme, o.titel, o.hinweis),
          RadioGroup<String>(
            groupValue: wahl.eins(o.schluessel),
            onChanged: (w) {
              if (w != null) _setze(o.schluessel, w);
            },
            child: Column(
              children: [
                for (final w in o.werte)
                  RadioListTile<String>(
                    value: w.wert,
                    title: Text(w.titel),
                    subtitle: _unterzeile(w.hinweis),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
              ],
            ),
          ),
        ],
      );

  Widget _wahlMehrere(ThemeData theme, DruckWahlMehrere o, DruckWahl wahl) {
    final gewaehlt = wahl.mehrere(o.schluessel);
    void umschalten(String wert, bool an) {
      final jetzt = _wahl?.mehrere(o.schluessel) ?? gewaehlt;
      _setze(
        o.schluessel,
        an ? {...jetzt, wert} : ({...jetzt}..remove(wert)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: _titel(theme, o.titel, o.hinweis)),
            TextButton(
              onPressed: () => _setze(
                o.schluessel,
                {for (final w in o.werte) w.wert},
              ),
              child: const Text('Alle'),
            ),
            TextButton(
              onPressed: () => _setze(o.schluessel, <String>{}),
              child: const Text('Keine'),
            ),
          ],
        ),
        for (final w in o.werte)
          CheckboxListTile(
            value: gewaehlt.contains(w.wert),
            onChanged: (an) => umschalten(w.wert, an ?? false),
            title: Text(w.titel),
            subtitle: _unterzeile(w.hinweis),
            secondary: w.farbe == null ? null : _marke(w),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
      ],
    );
  }

  Widget _zahl(ThemeData theme, DruckZahl o, DruckWahl wahl) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titel(theme, o.titel, o.hinweis),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 4),
            child: _ZahlFeld(
              key: ValueKey('druck-zahl-${o.schluessel}'),
              option: o,
              wert: wahl.zahl(o.schluessel),
              onWert: (w) => _setze(o.schluessel, w),
            ),
          ),
        ],
      );

  /// Eine farbige Marke wie die der Abteilungen.
  Widget _marke(DruckWert w) => Container(
        width: 30,
        padding: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: Color(w.farbe ?? 0xFF9E9E9E),
          borderRadius: AppMasse.eckenKlein,
        ),
        alignment: Alignment.center,
        child: Text(
          w.kuerzel ?? '',
          maxLines: 1,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 0.3,
          ),
        ),
      );

  List<Widget> _wie(ThemeData theme, DruckLayout l) {
    final klein = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return [
      _titel(theme, 'Papier'),
      SegmentedButton<DruckPapier>(
        segments: [
          for (final p in DruckPapier.values)
            ButtonSegment(value: p, label: Text(p.label)),
        ],
        selected: {l.papier},
        showSelectedIcon: false,
        onSelectionChanged: (s) => _layout(l.copyWith(papier: s.first)),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'A3 vergrößert das ganze Blatt, A5 verkleinert es — wie am '
          'Kopierer.',
          style: klein,
        ),
      ),
      _titel(theme, 'Ausrichtung'),
      SegmentedButton<DruckAusrichtung>(
        segments: const [
          ButtonSegment(
            value: DruckAusrichtung.automatisch,
            label: Text('Automatisch'),
            tooltip: 'Wie das Dokument es vorsieht',
          ),
          ButtonSegment(
            value: DruckAusrichtung.hoch,
            label: Text('Hoch'),
            tooltip: 'Hochformat',
          ),
          ButtonSegment(
            value: DruckAusrichtung.quer,
            label: Text('Quer'),
            tooltip: 'Querformat',
          ),
        ],
        selected: {l.ausrichtung},
        showSelectedIcon: false,
        onSelectionChanged: (s) => _layout(l.copyWith(ausrichtung: s.first)),
      ),
      _titel(theme, 'Größe'),
      RadioGroup<DruckAnpassung>(
        groupValue: l.anpassung,
        onChanged: (a) {
          if (a != null) _layout(l.copyWith(anpassung: a));
        },
        child: Column(
          children: [
            const RadioListTile<DruckAnpassung>(
              value: DruckAnpassung.original,
              title: Text('Originalgröße'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            RadioListTile<DruckAnpassung>(
              value: DruckAnpassung.verkleinern,
              title: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                children: [
                  const Text('Verkleinern auf'),
                  DropdownButton<int>(
                    value: l.prozent,
                    isDense: true,
                    items: [
                      for (final p in kDruckProzente)
                        DropdownMenuItem(value: p, child: Text('$p %')),
                    ],
                    onChanged: (p) {
                      if (p == null) return;
                      _layout(
                        l.copyWith(
                          anpassung: DruckAnpassung.verkleinern,
                          prozent: p,
                        ),
                      );
                    },
                  ),
                ],
              ),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            const RadioListTile<DruckAnpassung>(
              value: DruckAnpassung.eineSeite,
              title: Text('Alles auf eine Seite'),
              subtitle: Text('So weit verkleinert, wie nötig — je Blatt'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            const RadioListTile<DruckAnpassung>(
              value: DruckAnpassung.zweiSeiten,
              title: Text('Auf höchstens zwei Seiten'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ],
        ),
      ),
      _titel(theme, 'Ränder'),
      SegmentedButton<DruckRand>(
        segments: [
          for (final r in DruckRand.values)
            ButtonSegment(value: r, label: Text(r.label)),
        ],
        selected: {l.rand},
        showSelectedIcon: false,
        onSelectionChanged: (s) => _layout(l.copyWith(rand: s.first)),
      ),
      const SizedBox(height: 6),
      CheckboxListTile(
        value: l.graustufen,
        onChanged: (an) => _layout(l.copyWith(graustufen: an ?? false)),
        title: const Text('In Graustufen'),
        subtitle: const Text('Ohne Farbe — auch in der Vorschau'),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        dense: true,
      ),
    ];
  }

  // ── Rechts: die Vorschau ─────────────────────────────────────────────

  Widget _vorschauBereich(ThemeData theme) {
    final ergebnis = _ergebnis;
    final bauen = _vorschauBauen;
    final nichts = _nichtsGewaehlt;
    final fehler = _fehler;
    final Widget inhalt;
    if (nichts != null) {
      inhalt = Center(child: LeerHinweis(nichts, icon: Icons.checklist));
    } else if (fehler != null) {
      inhalt = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: HinweisBox(
            'Das Dokument ließ sich nicht setzen: ${fehlerText(fehler)}',
            art: StatusArt.fehler,
            auswaehlbar: true,
          ),
        ),
      );
    } else if (ergebnis == null || bauen == null) {
      inhalt = const Center(child: CircularProgressIndicator());
    } else {
      inhalt = _system.vorschau(context, ergebnis, bauen, _dateiname);
    }
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Stack(
        children: [
          Positioned.fill(child: inhalt),
          if (_veraltet && ergebnis != null)
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      ),
    );
  }

  // ── Unten: was herauskommt, und die Knöpfe ───────────────────────────

  Widget _fuss(ThemeData theme) {
    final bereit = _bereit;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 16, 12),
      child: Row(
        children: [
          Expanded(child: _info(theme)),
          TextButton.icon(
            onPressed: _wahl == null ? null : _zuruecksetzen,
            icon: const Icon(Icons.restart_alt),
            label: const Text('Zurücksetzen'),
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: bereit ? _speichern : null,
            icon: const Icon(Icons.save_alt),
            label: const Text('Als PDF speichern …'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: bereit ? _drucken : null,
            icon: const Icon(Icons.print),
            label: const Text('Drucken …'),
          ),
        ],
      ),
    );
  }

  Widget _info(ThemeData theme) {
    final ergebnis = _ergebnis;
    if (ergebnis == null || _nichtsGewaehlt != null || _fehler != null) {
      return const SizedBox.shrink();
    }
    final farben = AppFarben.von(context);
    final hoechstens = ergebnis.layout.anpassung.hoechstens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          ergebnis.beschreibung,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium,
        ),
        if (ergebnis.passtNicht && hoechstens != null)
          Text(
            'Passt auch bei '
            '${(kDruckKleinsterMassstab * 100).round()} % nicht auf '
            '${hoechstens == 1 ? 'eine Seite' : '$hoechstens Seiten'}.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: farben.warnung),
          ),
      ],
    );
  }
}
