import 'dart:convert';
import 'dart:io';

import 'package:erfassung_format/erfassung_format.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';
import '../../core/ui/bausteine.dart';
import '../../core/utils/datum.dart';
import '../../core/utils/fehler_text.dart';
import '../../core/utils/format.dart';
import '../articles/article_detail_providers.dart'
    show productionHistoryProvider, stepParametersProvider;
import '../erfassung/produktion_erfassung_screen.dart'
    show erfassungWocheDatenProvider;
import 'handy_erfassung_dienst.dart';

// Einstellungen → Handy-Erfassung: die Datei fürs Handy erstellen und das
// Ergebnis vom Handy einlesen. Der Weg ist eine Datei wie beim Backup —
// per Kabel, Freigabe oder wie es passt.

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

  /// Was zuletzt geschah — oder schiefging.
  String? _meldung;
  bool _fehler = false;

  ErgebnisVorschau? _vorschau;
  final _produktionen = <ProduktionVorschau>{};
  final _werte = <WertVorschau>{};

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

  Future<void> _ergebnisWaehlen() async {
    setState(() {
      _arbeitet = true;
      _meldung = null;
    });
    try {
      final gewaehlt = await FilePicker.pickFiles(
        dialogTitle: 'Ergebnis vom Handy wählen',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      final datei = gewaehlt?.files.firstOrNull;
      if (datei == null) {
        if (mounted) setState(() => _arbeitet = false);
        return;
      }
      final bytes = datei.bytes ??
          (datei.path == null ? null : await File(datei.path!).readAsBytes());
      if (bytes == null) {
        _melde('Die Datei ließ sich nicht lesen.', fehler: true);
        return;
      }
      final ergebnis = ErfassungsErgebnis.ausText(
        utf8.decode(bytes, allowMalformed: true),
      );
      final vorschau = await HandyErfassungDienst(ref.read(databaseProvider))
          .vorschau(ergebnis);
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
      final bericht = await HandyErfassungDienst(ref.read(databaseProvider))
          .uebernehmen(produktionen: _produktionen, werte: _werte);
      ref.read(autoBackupTriggerProvider).fireDebounced(
            reason: 'Handy-Erfassung eingelesen',
          );
      ref
        ..invalidate(productionHistoryProvider)
        ..invalidate(stepParametersProvider)
        ..invalidate(erfassungWocheDatenProvider);
      if (!mounted) return;
      setState(() => _vorschau = null);
      final p = bericht.produktionen;
      final w = bericht.werte;
      _melde(
        'Übernommen: ${p == 1 ? '1 Produktion' : '$p Produktionen'} und '
        '${w == 1 ? '1 Maschineneinstellung' : '$w Maschineneinstellungen'}.',
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
      body: ListView(
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
                    _paketBereich(context),
                    const SizedBox(height: 12),
                    Bereich(
                      titel: '2 · Ergebnis vom Handy einlesen',
                      icon: Icons.download_outlined,
                      untertitel: 'vor dem Übernehmen siehst du, was sich '
                          'ändert',
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.tonalIcon(
                          key: const ValueKey('handy-ergebnis'),
                          onPressed: _arbeitet ? null : _ergebnisWaehlen,
                          icon: const Icon(Icons.folder_open, size: 18),
                          label: const Text('Ergebnis-Datei wählen …'),
                        ),
                      ),
                    ),
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
    );
  }

  Widget _paketBereich(BuildContext context) {
    final theme = Theme.of(context);
    final (von, bis) = _tage;
    return Bereich(
      titel: '1 · Datei fürs Handy erstellen',
      icon: Icons.phone_android,
      untertitel: 'geplante Produktionen und die Maschineneinstellungen '
          'aller Artikel',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final z in _Zeitraum.values)
                ChoiceChip(
                  label: Text(z.label),
                  selected: _zeitraum == z,
                  onSelected: (_) => setState(() => _zeitraum = z),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_zeitraum == _Zeitraum.frei)
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () => _tagWaehlen(von: true),
                  child: Text('von ${Format.datum(_von)}'),
                ),
                OutlinedButton(
                  onPressed: () => _tagWaehlen(von: false),
                  child: Text('bis ${Format.datum(_bis)}'),
                ),
              ],
            )
          else
            Text(
              'Produktionen vom ${Format.datum(von)} bis ${Format.datum(bis)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('handy-paket'),
            onPressed: _arbeitet ? null : _paketErstellen,
            icon: const Icon(Icons.save_alt, size: 18),
            label: const Text('Datei erstellen …'),
          ),
        ],
      ),
    );
  }

  Widget _vorschauBereich(BuildContext context, ErgebnisVorschau v) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final anzahl = _produktionen.length + _werte.length;
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
                    if (v.werte.isNotEmpty)
                      _Zwischentitel(
                        'MASCHINENEINSTELLUNGEN (${v.werte.length})',
                      ),
                    for (final w in v.werte)
                      CheckboxListTile(
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _werte.contains(w),
                        onChanged: !w.moeglich || _arbeitet
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
                  ],
                ),
        ),
      ],
    );
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
      'Datei erstellen und aufs Handy ziehen — per Kabel, Freigabe oder wie '
          'es passt.',
      'Auf dem Handy die Datei antippen und mit „Planer Erfassung" öffnen '
          '(oder in der App „Paket öffnen").',
      'An der Anlage erfassen: Produktionen und Maschineneinstellungen — '
          'ohne Netz, alles bleibt auf dem Handy.',
      'In der App „Ergebnis speichern", die Datei zurück an den PC und hier '
          'einlesen.',
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
