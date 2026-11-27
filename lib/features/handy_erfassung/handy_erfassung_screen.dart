import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:erfassung_format/erfassung_format.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';
import '../../core/ui/ablage.dart';
import '../../core/ui/bausteine.dart';
import '../../core/ui/foto_kachel.dart';
import '../../core/utils/datei_wahl.dart';
import '../../core/utils/datum.dart';
import '../../core/utils/fehler_text.dart';
import '../../core/utils/format.dart';
import '../articles/article_detail_providers.dart'
    show
        productStepsProvider,
        productionHistoryProvider,
        stepParametersProvider;
import '../entwicklung/daten/datei_typen.dart' show groesseText;
import '../erfassung/produktion_erfassung_screen.dart'
    show erfassungWocheDatenProvider;
import 'ergebnis_suche.dart';
import 'handy_erfassung_dienst.dart';
import 'qr_senden.dart';

// Produktionserfassung → „Vom Handy einlesen": die Datei fürs Handy
// erstellen und das Ergebnis vom Handy einlesen — samt der Fotos, die an der Anlage
// aufgenommen wurden. Der Weg ist eine Datei wie beim Backup — per Kabel,
// Freigabe oder wie es passt.

/// Wie weit das Paket nach vorn reicht.
enum _Zeitraum {
  dieseWoche('Diese Woche'),
  zweiWochen('Diese und nächste Woche'),
  frei('Eigener Zeitraum');

  const _Zeitraum(this.label);

  final String label;
}

class HandyErfassungScreen extends ConsumerStatefulWidget {
  const HandyErfassungScreen({super.key});

  @override
  ConsumerState<HandyErfassungScreen> createState() =>
      _HandyErfassungScreenState();
}

class _HandyErfassungScreenState extends ConsumerState<HandyErfassungScreen> {
  _Zeitraum _zeitraum = _Zeitraum.dieseWoche;
  late DateTime _von = _montag;
  late DateTime _bis = tagPlus(_montag, 6);

  bool _arbeitet = false;

  /// Per QR-Code auch die Artikel ohne geplante Produktion mitschicken —
  /// dann lassen sich am Handy alle Einstellungen ändern, es dauert aber.
  bool _qrAlleArtikel = false;

  /// Was zuletzt geschah — oder schiefging.
  String? _meldung;
  bool _fehler = false;

  ErgebnisVorschau? _vorschau;
  final _produktionen = <ProduktionVorschau>{};
  final _werte = <WertVorschau>{};
  final _fotos = <FotoVorschau>{};
  final _schritte = <SchrittVorschau>{};

  /// Ein neues Ergebnis im Download-Ordner — etwa der gespeicherte Anhang
  /// der E-Mail vom Handy.
  GefundenesErgebnis? _gefunden;

  @override
  void initState() {
    super.initState();
    unawaited(_suchen());
  }

  Future<void> _suchen() async {
    final gefunden = await ergebnisInDownloads();
    if (mounted) setState(() => _gefunden = gefunden);
  }

  Future<void> _gefundenesLesen(GefundenesErgebnis g) async {
    setState(() {
      _arbeitet = true;
      _meldung = null;
    });
    final Uint8List bytes;
    try {
      bytes = await File(g.pfad).readAsBytes();
    } catch (e) {
      _melde(
        'Die Datei ließ sich nicht lesen: ${fehlerText(e)}',
        fehler: true,
      );
      unawaited(_suchen());
      return;
    }
    await _ergebnisLesen(bytes);
  }

  static DateTime get _montag {
    final heute = tagOhneZeit(DateTime.now());
    return tagPlus(heute, -(heute.weekday - 1));
  }

  (DateTime, DateTime) get _tage => switch (_zeitraum) {
        _Zeitraum.dieseWoche => (_montag, tagPlus(_montag, 6)),
        _Zeitraum.zweiWochen => (_montag, tagPlus(_montag, 13)),
        _Zeitraum.frei => _von.isAfter(_bis) ? (_bis, _von) : (_von, _bis),
      };

  void _melde(String text, {bool fehler = false}) {
    if (!mounted) return;
    setState(() {
      _arbeitet = false;
      _meldung = text;
      _fehler = fehler;
    });
  }

  Future<void> _tagWaehlen({required bool von}) async {
    final gewaehlt = await showDatePicker(
      context: context,
      initialDate: von ? _von : _bis,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (gewaehlt == null) return;
    setState(() => von ? _von = gewaehlt : _bis = gewaehlt);
  }

  Future<void> _paketErstellen() async {
    setState(() {
      _arbeitet = true;
      _meldung = null;
    });
    try {
      final (von, bis) = _tage;
      final paket = await HandyErfassungDienst(ref.read(databaseProvider))
          .paketErstellen(von: von, bis: bis);
      final ziel = await FilePicker.saveFile(
        dialogTitle: 'Datei fürs Handy speichern',
        fileName: paket.dateiname,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (ziel == null) {
        if (mounted) setState(() => _arbeitet = false);
        return;
      }
      await File(ziel).writeAsString(paket.alsText());
      final n = paket.produktionen.length;
      _melde(
        'Datei gespeichert: ${n == 1 ? '1 Produktion' : '$n Produktionen'} '
        'und die Maschineneinstellungen von ${paket.artikel.length} '
        'Artikeln. Jetzt aufs Handy ziehen und dort mit „Planer Erfassung" '
        'öffnen.\n$ziel',
      );
    } catch (e) {
      _melde(
        'Die Datei ließ sich nicht erstellen: ${fehlerText(e)}',
        fehler: true,
      );
    }
  }

  /// Dasselbe Paket als wechselnde QR-Codes zum Abfotografieren.
  Future<void> _qrSenden() async {
    setState(() {
      _arbeitet = true;
      _meldung = null;
    });
    try {
      final (von, bis) = _tage;
      final paket = await HandyErfassungDienst(ref.read(databaseProvider))
          .paketErstellen(von: von, bis: bis, nurGeplante: !_qrAlleArtikel);
      final daten = qrPacken(paket);
      if (!mounted) return;
      setState(() => _arbeitet = false);
      final n = paket.produktionen.length;
      await qrSendenZeigen(
        context,
        daten: daten,
        info: '${n == 1 ? '1 Produktion' : '$n Produktionen'}, die '
            'Maschineneinstellungen von ${paket.artikel.length} Artikeln '
            '· ${groesseText(daten.length)}',
      );
    } catch (e) {
      _melde(
        'Die QR-Codes ließen sich nicht erstellen: ${fehlerText(e)}',
        fehler: true,
      );
    }
  }

  /// Die Endungen, die sich hier einlesen lassen.
  static const List<String> _endungen = ['json'];

  /// Über den Dateidialog — er öffnet dort, wo das Ergebnis zuletzt lag.
  Future<void> _ergebnisWaehlen() async {
    setState(() {
      _arbeitet = true;
      _meldung = null;
    });
    try {
      final datei = await dateiWaehlen(
        art: EinleseArt.handyErgebnis,
        endungen: _endungen,
        titel: 'Ergebnis vom Handy wählen',
      );
      if (datei == null) {
        if (mounted) setState(() => _arbeitet = false);
        return;
      }
      final bytes = datei.inhalt;
      if (bytes == null) {
        _melde('Die Datei ließ sich nicht lesen.', fehler: true);
        return;
      }
      await _ergebnisLesen(bytes);
    } catch (e) {
      _melde(
        'Das Ergebnis ließ sich nicht einlesen: ${fehlerText(e)}',
        fehler: true,
      );
    }
  }

  /// Aufs Fenster gezogen: derselbe Weg wie über den Dateidialog.
  Future<void> _abgelegt(List<AbgelegteDatei> dateien) async {
    if (!mounted || _arbeitet || _vorschau != null) return;
    final datei = ersteMitEndung(dateien, _endungen);
    if (datei == null) {
      _melde(falscheDateiText(_endungen), fehler: true);
      return;
    }
    setState(() {
      _arbeitet = true;
      _meldung = null;
    });
    await _ergebnisLesen(datei.inhalt);
  }

  /// Liest das Ergebnis aus [bytes] und zeigt, was sich ändern würde.
  /// Meldet selbst, wenn das nicht geht.
  Future<void> _ergebnisLesen(Uint8List bytes) async {
    try {
      final dienst = HandyErfassungDienst(ref.read(databaseProvider));
      final ergebnis = await ergebnisLesen(
        bytes,
        schluesselFuer: dienst.ergebnisSchluessel,
      );
      final vorschau = await dienst.vorschau(ergebnis);
      if (!mounted) return;
      setState(() {
        _arbeitet = false;
        _vorschau = vorschau;
        _produktionen
          ..clear()
          ..addAll(vorschau.produktionen.where((p) => p.vorgewaehlt));
        _werte
          ..clear()
          ..addAll(vorschau.werte.where((w) => w.vorgewaehlt));
        _fotos
          ..clear()
          ..addAll(vorschau.fotos.where((f) => f.vorgewaehlt));
        _schritte
          ..clear()
          ..addAll(vorschau.schritte.where((s) => s.vorgewaehlt));
      });
    } on FormatFehler catch (e) {
      _melde(e.meldung, fehler: true);
    } catch (e) {
      _melde(
        'Das Ergebnis ließ sich nicht einlesen: ${fehlerText(e)}',
        fehler: true,
      );
    }
  }

  Future<void> _uebernehmen() async {
    final vorschau = _vorschau;
    if (vorschau == null) return;
    setState(() => _arbeitet = true);
    try {
      final bericht =
          await HandyErfassungDienst(ref.read(databaseProvider)).uebernehmen(
        produktionen: _produktionen,
        werte: _werte,
        fotos: _fotos,
        schritte: _schritte,
      );
      ref.read(autoBackupTriggerProvider).fireDebounced(
            reason: 'Handy-Erfassung eingelesen',
          );
      ref
        ..invalidate(productionHistoryProvider)
        ..invalidate(stepParametersProvider)
        ..invalidate(productStepsProvider)
        ..invalidate(erfassungWocheDatenProvider);
      await ergebnisUebernommen(vorschau.ergebnis.erstellt);
      unawaited(_suchen());
      if (!mounted) return;
      final muster = _fotos
          .where((f) => f.moeglich && f.foto.art == FotoArt.muster)
          .length;
      setState(() => _vorschau = null);
      final p = bericht.produktionen;
      final w = bericht.werte;
      final f = bericht.fotos;
      final k = bericht.schritte;
      _melde(
        [
          'Übernommen: ${p == 1 ? '1 Produktion' : '$p Produktionen'}, '
              '${w == 1 ? '1 Maschineneinstellung' : '$w '
                  'Maschineneinstellungen'}'
              '${k == 0 ? '' : ', ${k == 1 ? '1 Änderung' : '$k '
                  'Änderungen'} an Prozessketten'}'
              ' und ${f == 1 ? '1 Foto' : '$f Fotos'}.',
          if (f > 0 && muster > 0)
            '${muster == 1 ? 'Das Musterfoto liegt' : 'Die Musterfotos '
                    'liegen'} im Foto-Eingang der Produktentwicklung — dort '
                'einem Projekt zuordnen.',
        ].join('\n'),
      );
    } catch (e) {
      _melde(
        'Das Ergebnis ließ sich nicht übernehmen — es wurde nichts '
        'geändert: ${fehlerText(e)}',
        fehler: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vorschau = _vorschau;
    return Scaffold(
      appBar: AppBar(title: const Text('Handy-Erfassung')),
      // Das Ergebnis kann man auch aufs Fenster ziehen — solange noch
      // keines zum Übernehmen offen ist. Die Zone wartet nicht auf das
      // Einlesen; die Seite zeigt selbst, dass sie arbeitet.
      body: AblageZone(
        hinweis: 'Ergebnis loslassen — vom Handy einlesen',
        aktiv: !_arbeitet && vorschau == null,
        onAbgelegt: (dateien) async => unawaited(_abgelegt(dateien)),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_meldung case final m?) ...[
                      HinweisBox(
                        m,
                        art: _fehler ? StatusArt.fehler : StatusArt.ok,
                        auswaehlbar: true,
                        onSchliessen: () => setState(() => _meldung = null),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (vorschau == null) ...[
                      _zeitraumBereich(context),
                      const SizedBox(height: 12),
                      _kacheln(context),
                      const SizedBox(height: 12),
                      const _Anleitung(),
                    ] else
                      _vorschauBereich(context, vorschau),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _zeitraumBereich(BuildContext context) {
    final theme = Theme.of(context);
    final (von, bis) = _tage;
    return Bereich(
      titel: 'Welche Produktionen aufs Handy?',
      icon: Icons.date_range_outlined,
      untertitel: 'für QR-Code und Datei',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final z in _Zeitraum.values)
            ChoiceChip(
              label: Text(z.label),
              selected: _zeitraum == z,
              onSelected: (_) => setState(() => _zeitraum = z),
            ),
          const SizedBox(width: 8),
          if (_zeitraum == _Zeitraum.frei) ...[
            OutlinedButton(
              onPressed: () => _tagWaehlen(von: true),
              child: Text('von ${Format.datum(_von)}'),
            ),
            OutlinedButton(
              onPressed: () => _tagWaehlen(von: false),
              child: Text('bis ${Format.datum(_bis)}'),
            ),
          ] else
            Text(
              '${Format.datum(von)} bis ${Format.datum(bis)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  /// Die drei Wege: per QR-Code aufs Handy, als Datei aufs Handy, das
  /// Ergebnis zurück. Nebeneinander, auf schmalen Fenstern untereinander.
  Widget _kacheln(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final frei = !_arbeitet;
    final gefunden = _gefunden;
    final kacheln = [
      _Kachel(
        key: const ValueKey('handy-qr'),
        icon: Icons.qr_code_2,
        titel: 'Per QR-Code aufs Handy',
        text: 'Das Handy auf den Bildschirm halten — ohne Kabel, in '
            'Sekunden.',
        onTap: frei ? _qrSenden : null,
        unten: InkWell(
          key: const ValueKey('handy-qr-alle'),
          borderRadius: BorderRadius.circular(6),
          onTap: () => setState(() => _qrAlleArtikel = !_qrAlleArtikel),
          child: Row(
            children: [
              Checkbox(
                value: _qrAlleArtikel,
                onChanged: (v) => setState(() => _qrAlleArtikel = v ?? false),
              ),
              Expanded(
                child: Text(
                  'Alle Artikel mitschicken (dauert gut eine Minute)',
                  style: theme.textTheme.bodySmall?.copyWith(color: grau),
                ),
              ),
            ],
          ),
        ),
      ),
      _Kachel(
        key: const ValueKey('handy-paket'),
        icon: Icons.save_alt,
        titel: 'Als Datei aufs Handy',
        text: 'Speichern und per Kabel oder Freigabe aufs Handy bringen. '
            'Mit allen Artikeln.',
        onTap: frei ? _paketErstellen : null,
      ),
      _Kachel(
        key: const ValueKey('handy-ergebnis'),
        icon: Icons.move_to_inbox_outlined,
        titel: 'Ergebnis vom Handy einlesen',
        text: 'Den Anhang der E-Mail vom Handy wählen — oder die Datei '
            'aufs Fenster ziehen. Vor dem Übernehmen siehst du, was sich '
            'ändert.',
        hervorgehoben: gefunden != null,
        onTap: frei ? _ergebnisWaehlen : null,
        unten: gefunden == null
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Neu im Download-Ordner — vom '
                    '${_zeitstempelLesbar(gefunden)}:',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  FilledButton.icon(
                    key: const ValueKey('handy-gefunden'),
                    onPressed: frei ? () => _gefundenesLesen(gefunden) : null,
                    icon: const Icon(Icons.download_done, size: 18),
                    label: const Text('Jetzt einlesen'),
                  ),
                ],
              ),
      ),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, k) in kacheln.indexed) ...[
                if (i > 0) const SizedBox(height: 12),
                k,
              ],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, k) in kacheln.indexed) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: k),
              ],
            ],
          ),
        );
      },
    );
  }

  /// „2026-11-23_1410" als „23.11., 14:10 Uhr".
  static String _zeitstempelLesbar(GefundenesErgebnis g) {
    final z = g.zeitstempel;
    return '${z.substring(8, 10)}.${z.substring(5, 7)}., '
        '${z.substring(11, 13)}:${z.substring(13, 15)} Uhr';
  }

  Widget _vorschauBereich(BuildContext context, ErgebnisVorschau v) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final anzahl =
        _produktionen.length + _werte.length + _fotos.length + _schritte.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Bereich(
          titel: 'Ergebnis vom ${Format.datum(v.ergebnis.erstellt)}, '
              '${Format.uhrzeit(v.ergebnis.erstellt)} Uhr',
          icon: Icons.fact_check_outlined,
          untertitel: 'angehakt wird übernommen',
          aktionen: [
            TextButton(
              onPressed:
                  _arbeitet ? null : () => setState(() => _vorschau = null),
              child: const Text('Verwerfen'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const ValueKey('handy-uebernehmen'),
              onPressed: _arbeitet || anzahl == 0 ? null : _uebernehmen,
              child: Text(anzahl == 0 ? 'Übernehmen' : 'Übernehmen ($anzahl)'),
            ),
          ],
          innenAbstand: const EdgeInsets.symmetric(vertical: 4),
          child: v.ergebnis.leer
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: LeerHinweis(
                    'In der Datei steht nichts — auf dem Handy wurde nichts '
                    'erfasst.',
                    icon: Icons.inbox_outlined,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (v.produktionen.isNotEmpty)
                      _Zwischentitel('PRODUKTIONEN (${v.produktionen.length})'),
                    for (final p in v.produktionen)
                      CheckboxListTile(
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _produktionen.contains(p),
                        onChanged: !p.moeglich || _arbeitet
                            ? null
                            : (an) => setState(
                                  () => an ?? false
                                      ? _produktionen.add(p)
                                      : _produktionen.remove(p),
                                ),
                        title: Text(
                          '${Format.tagKurz(p.erfasst.datum)} · ${p.artikel}',
                        ),
                        subtitle: Text(
                          [
                            _produktionText(p.erfasst),
                            if (p.hinweis != null) p.hinweis!,
                          ].join('\n'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: p.stand == ProduktionStand.neu
                                ? grau
                                : theme.colorScheme.error,
                          ),
                        ),
                      ),
                    if (v.schritte.isNotEmpty)
                      _Zwischentitel('PROZESSKETTEN (${v.schritte.length})'),
                    for (final k in v.schritte)
                      CheckboxListTile(
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _schritte.contains(k),
                        onChanged: !k.moeglich || _arbeitet
                            ? null
                            : (an) => setState(() {
                                  if (an ?? false) {
                                    _schritte.add(k);
                                    return;
                                  }
                                  _schritte.remove(k);
                                  // Ohne den neuen Schritt haben seine
                                  // Werte keinen Platz.
                                  if (k.neu case final n?) {
                                    _werte.removeWhere(
                                      (w) => w.wert.schrittId == n.id,
                                    );
                                  }
                                }),
                        secondary: Icon(
                          k.istNeu
                              ? Icons.add_circle_outline
                              : Icons.remove_circle_outline,
                          color: k.moeglich ? null : grau,
                        ),
                        title: Text(k.text),
                        subtitle: Text(
                          [
                            [
                              if (k.artikel.isNotEmpty) k.artikel,
                              if ((k.neu?.kuerzel ?? k.entfernt?.kuerzel ?? '')
                                  .isNotEmpty)
                                'von ${k.neu?.kuerzel ?? k.entfernt?.kuerzel}',
                            ].join(' · '),
                            if (k.hinweis != null) k.hinweis!,
                          ].join('\n'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: k.moeglich ||
                                    k.stand == SchrittStand.schonDa ||
                                    k.stand == SchrittStand.schonEntfernt
                                ? grau
                                : theme.colorScheme.error,
                          ),
                        ),
                      ),
                    if (v.werte.isNotEmpty)
                      _Zwischentitel(
                        'MASCHINENEINSTELLUNGEN (${v.werte.length})',
                      ),
                    for (final w in v.werte)
                      CheckboxListTile(
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _werte.contains(w),
                        onChanged:
                            !w.moeglich || _arbeitet || _ohneSeinenSchritt(v, w)
                                ? null
                                : (an) => setState(
                                      () => an ?? false
                                          ? _werte.add(w)
                                          : _werte.remove(w),
                                    ),
                        title: Text(
                          '${w.wert.name}: ${w.amPc ?? '—'} → '
                          '${_oderStrich(w.wert.neu)}',
                        ),
                        subtitle: Text(
                          [
                            [
                              if (w.artikel.isNotEmpty) w.artikel,
                              if (w.schritt.isNotEmpty) w.schritt,
                              if ((w.wert.kuerzel ?? '').isNotEmpty)
                                'erfasst von ${w.wert.kuerzel}',
                            ].join(' · '),
                            if (w.stand == WertStand.gleich)
                              'Steht am PC schon so.',
                            if (w.hinweis != null) w.hinweis!,
                          ].join('\n'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: w.stand == WertStand.neu && w.hinweis == null
                                ? grau
                                : w.stand == WertStand.gleich
                                    ? grau
                                    : theme.colorScheme.error,
                          ),
                        ),
                      ),
                    if (v.fotos.isNotEmpty)
                      _Zwischentitel('FOTOS (${v.fotos.length})'),
                    for (final f in v.fotos)
                      CheckboxListTile(
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _fotos.contains(f),
                        onChanged: !f.moeglich || _arbeitet
                            ? null
                            : (an) => setState(
                                  () => an ?? false
                                      ? _fotos.add(f)
                                      : _fotos.remove(f),
                                ),
                        title: Text(
                          [
                            f.foto.art == FotoArt.muster
                                ? 'Musterfoto'
                                : 'Foto aus der Produktion',
                            if ((f.foto.bezeichnung ?? '').isNotEmpty)
                              f.foto.bezeichnung!,
                          ].join(' · '),
                        ),
                        subtitle: Text(
                          [
                            [
                              if (f.ziel.isNotEmpty) f.ziel,
                              '${Format.datum(f.foto.aufgenommenAm)}, '
                                  '${Format.uhrzeit(f.foto.aufgenommenAm)} '
                                  'Uhr',
                              if ((f.foto.kuerzel ?? '').isNotEmpty)
                                'von ${f.foto.kuerzel}',
                              groesseText(f.foto.groesse),
                            ].join(' · '),
                            if (f.hinweis != null) f.hinweis!,
                          ].join('\n'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: f.stand == FotoStand.neu ||
                                    f.stand == FotoStand.schonDa
                                ? grau
                                : theme.colorScheme.error,
                          ),
                        ),
                        // Nicht höher als die Zeile — sonst staucht sie
                        // das Bild.
                        secondary: FotoKachel(
                          breite: 64,
                          hoehe: 48,
                          bild: f.foto.daten,
                          fehlt: !istJpeg(f.foto.daten),
                          onTap: !istJpeg(f.foto.daten)
                              ? null
                              : () => fotoGrossZeigen(
                                    context,
                                    bild: f.foto.daten!,
                                    titel: f.foto.art == FotoArt.muster
                                        ? 'Musterfoto'
                                        : 'Foto aus der Produktion',
                                    untertitel: f.ziel,
                                  ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  /// Ob [w] an einer Maschine hängt, die erst mit diesem Ergebnis in die
  /// Kette käme — und die gerade nicht angehakt ist.
  bool _ohneSeinenSchritt(ErgebnisVorschau v, WertVorschau w) {
    for (final k in v.schritte) {
      if (k.neu?.id == w.wert.schrittId) return !_schritte.contains(k);
    }
    return false;
  }

  static String _oderStrich(String? wert) {
    final t = wert?.trim() ?? '';
    return t.isEmpty ? '—' : t;
  }

  static String _produktionText(ErfassteProduktion e) => [
        'Rohware ${Format.kg(e.rohKg)}',
        if (e.fleischKg != null) 'davon Fleisch ${Format.kg(e.fleischKg!)}',
        if (e.fertigKg != null) 'Fertigware ${Format.kg(e.fertigKg!)}',
        if (e.start != null || e.ende != null)
          '${e.start ?? '?'}–${e.ende ?? '?'} Uhr',
        if (e.endeVpk != null) 'VPK ${e.endeVpk} Uhr',
        if (e.notiz != null) e.notiz!,
      ].join(' · ');
}

class _Zwischentitel extends StatelessWidget {
  const _Zwischentitel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// So geht's — in vier Schritten.
class _Anleitung extends StatelessWidget {
  const _Anleitung();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const schritte = [
      'Aufs Handy: „Per QR-Code" und in der App „Per QR-Code empfangen" '
          '— oder die Datei aufs Handy bringen und dort öffnen.',
      'An der Anlage erfassen: Produktionen, Maschineneinstellungen und '
          'Fotos — ohne Netz, alles bleibt auf dem Handy.',
      'In der App „An PC" → „Per E-Mail an den PC": Die E-Mail-App öffnet '
          'sich mit dem Ergebnis als Anhang, nur noch absenden.',
      'Am PC den Anhang speichern — liegt er im Download-Ordner, bietet '
          'ihn diese Seite von selbst an — und einlesen.',
    ];
    return Bereich(
      titel: 'So geht’s',
      icon: Icons.help_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, s) in schritte.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      '${i + 1}.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(child: Text(s, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Eine große Kachel zum Anklicken: Symbol, Titel, ein Satz — darunter,
/// was noch dazugehört.
class _Kachel extends StatelessWidget {
  const _Kachel({
    super.key,
    required this.icon,
    required this.titel,
    required this.text,
    required this.onTap,
    this.unten,
    this.hervorgehoben = false,
  });

  final IconData icon;
  final String titel;
  final String text;
  final VoidCallback? onTap;
  final Widget? unten;

  /// Mit farbigem Rand — es wartet etwas.
  final bool hervorgehoben;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = theme.colorScheme;
    return Material(
      color: f.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: hervorgehoben ? f.primary : f.outline,
          width: hervorgehoben ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: f.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 28, color: f.onPrimaryContainer),
              ),
              const SizedBox(height: 14),
              Text(
                titel,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: onTap == null ? f.onSurfaceVariant : null,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: f.onSurfaceVariant,
                ),
              ),
              if (unten != null) ...[
                const SizedBox(height: 12),
                unten!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
