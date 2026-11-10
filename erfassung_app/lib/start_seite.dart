import 'dart:convert';
import 'dart:typed_data';

import 'package:erfassung_format/erfassung_format.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'artikel_seite.dart';
import 'bausteine.dart';
import 'modell.dart';
import 'produktionen_seite.dart';
import 'stil.dart';

/// Die Startseite: das geöffnete Paket, die beiden Bereiche als große
/// Kacheln, das Ergebnis und das Kürzel.
class StartSeite extends StatefulWidget {
  const StartSeite({super.key, required this.modell});

  final ErfassungsModell modell;

  @override
  State<StartSeite> createState() => _StartSeiteState();
}

class _StartSeiteState extends State<StartSeite> {
  ErfassungsModell get _modell => widget.modell;

  @override
  void initState() {
    super.initState();
    // Über „Öffnen mit" gestartet — oder bei laufender App geöffnet.
    GeoeffneteDatei.lauschen(_geoeffneteDateiHolen);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _geoeffneteDateiHolen(),
    );
  }

  Future<void> _geoeffneteDateiHolen() async {
    final text = await GeoeffneteDatei.holen();
    if (text == null || !mounted) return;
    await _paketUebernehmen(() => ErfassungsPaket.ausText(text));
  }

  Future<void> _paketWaehlen() async {
    final FilePickerResult? gewaehlt;
    try {
      gewaehlt = await FilePicker.pickFiles(withData: true);
    } catch (e) {
      if (mounted) melde(context, 'Die Datei ließ sich nicht öffnen: $e');
      return;
    }
    final bytes = gewaehlt?.files.firstOrNull?.bytes;
    if (bytes == null || !mounted) return;
    await _paketUebernehmen(() => paketAusBytes(bytes));
  }

  /// Öffnet das Paket aus [lesen] — fragt vorher, wenn dabei Erfasstes
  /// verloren ginge.
  Future<void> _paketUebernehmen(ErfassungsPaket Function() lesen) async {
    final ErfassungsPaket paket;
    try {
      paket = lesen();
    } on FormatFehler catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Die Datei passt nicht'),
          content: Text(e.meldung),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Schließen'),
            ),
          ],
        ),
      );
      return;
    }
    if (!mounted) return;
    if (_modell.istGeoeffnet(paket)) {
      melde(context, 'Dieses Paket ist schon geöffnet.');
      return;
    }
    final stand = _modell.stand;
    if (stand.hatErfasstes) {
      final ok = await nachfragen(
        context,
        titel: 'Neues Paket öffnen?',
        text: stand.ungesichert
            ? 'Es gibt Erfasstes, das noch in keiner Ergebnis-Datei steht. '
                'Mit dem neuen Paket geht es verloren — besser erst das '
                'Ergebnis speichern.'
            : 'Das Erfasste zum alten Paket wird vom Handy gelöscht. Das '
                'Ergebnis ist als Datei gespeichert.',
        ja: 'Neues Paket öffnen',
        gefaehrlich: stand.ungesichert,
      );
      if (!ok || !mounted) return;
    }
    await _modell.paketOeffnen(paket);
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    final n = paket.produktionen.length;
    melde(
      context,
      'Paket geöffnet: ${n == 1 ? '1 Produktion' : '$n Produktionen'}, '
      '${paket.artikel.length} Artikel.',
    );
  }

  Future<void> _ergebnisSpeichern() async {
    final jetzt = DateTime.now();
    final ergebnis = _modell.stand.ergebnis(jetzt);
    if (ergebnis == null) return;
    if (ergebnis.leer) {
      melde(context, 'Es ist noch nichts erfasst.');
      return;
    }
    try {
      final ziel = await FilePicker.saveFile(
        dialogTitle: 'Ergebnis speichern',
        fileName: ergebnis.dateiname(kuerzel: _modell.stand.kuerzel),
        bytes: Uint8List.fromList(utf8.encode(ergebnis.alsText())),
      );
      if (ziel == null || !mounted) return;
      await _modell.ergebnisGespeichert(jetzt);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ergebnis gespeichert'),
          content: const Text(
            'Jetzt die Datei an den PC bringen und im Planer unter '
            'Einstellungen → Handy-Erfassung einlesen.\n\n'
            'Das Erfasste bleibt auf dem Handy, bis du ein neues Paket '
            'öffnest.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Fertig'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) melde(context, 'Das Ergebnis ließ sich nicht speichern: $e');
    }
  }

  Future<void> _kuerzelAendern() async {
    final feld = TextEditingController(text: _modell.stand.kuerzel);
    final neu = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dein Kürzel'),
        content: TextField(
          controller: feld,
          autofocus: true,
          maxLength: 12,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            hintText: 'z. B. AB',
            helperText: 'Steht bei allem, was du erfasst.',
          ),
          onSubmitted: (t) => Navigator.of(ctx).pop(t),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
            onPressed: () => Navigator.of(ctx).pop(feld.text),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (neu != null) await _modell.kuerzelSetzen(neu);
  }

  void _oeffne(Widget seite) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => seite),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _modell,
      builder: (context, _) {
        final theme = Theme.of(context);
        final f = theme.colorScheme;
        final farben = Farben.von(context);
        final stand = _modell.stand;
        final paket = stand.paket;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Planer Erfassung'),
            actions: [
              TextButton.icon(
                onPressed: _kuerzelAendern,
                style: TextButton.styleFrom(
                  foregroundColor: theme.appBarTheme.foregroundColor,
                ),
                icon: const Icon(Icons.person_outline, size: 20),
                label: Text(stand.kuerzel.isEmpty ? 'Kürzel' : stand.kuerzel),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                if (_modell.speicherFehler case final fehler?) ...[
                  Hinweis(
                    fehler,
                    farbe: f.error,
                    icon: Icons.error_outline,
                  ),
                  const SizedBox(height: 12),
                ],
                if (paket == null)
                  _OhnePaket(onOeffnen: _paketWaehlen)
                else ...[
                  Flaeche(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                      child: Row(
                        children: [
                          Icon(Icons.inventory_2_outlined, color: f.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Paket vom ${datumText(paket.erstellt)}, '
                                  '${uhrzeit(paket.erstellt)} Uhr',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  'Produktionen ${tagKurz(paket.von)} bis '
                                  '${tagKurz(paket.bis)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: f.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: _paketWaehlen,
                            child: const Text('Anderes'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _Kachel(
                    icon: Icons.fact_check_outlined,
                    titel: 'Produktionen',
                    text: stand.offen.isEmpty
                        ? 'Alle geplanten sind erfasst'
                        : stand.offen.length == 1
                            ? '1 geplante ist noch offen'
                            : '${stand.offen.length} geplante sind noch offen',
                    marke: stand.produktionen.isEmpty
                        ? null
                        : '${stand.produktionen.length} erfasst',
                    onTap: () => _oeffne(ProduktionenSeite(modell: _modell)),
                  ),
                  const SizedBox(height: 12),
                  _Kachel(
                    icon: Icons.tune,
                    titel: 'Maschineneinstellungen',
                    text: '${paket.artikel.length} Artikel mit ihren '
                        'Schritten und Anlagen',
                    marke: stand.werte.isEmpty
                        ? null
                        : '${stand.werte.length} geändert',
                    onTap: () => _oeffne(ArtikelSeite(modell: _modell)),
                  ),
                  const Abschnitt('Zurück an den PC'),
                  if (stand.ungesichert) ...[
                    Hinweis(
                      'Es gibt Erfasstes, das noch in keiner Ergebnis-Datei '
                      'steht.',
                      farbe: farben.warnung,
                    ),
                    const SizedBox(height: 8),
                  ] else if (stand.gespeichertAm case final am?) ...[
                    Hinweis(
                      'Ergebnis gespeichert am ${datumText(am)} um '
                      '${uhrzeit(am)} Uhr.',
                      farbe: farben.ok,
                      icon: Icons.check_circle_outline,
                    ),
                    const SizedBox(height: 8),
                  ],
                  FilledButton.icon(
                    onPressed: stand.hatErfasstes ? _ergebnisSpeichern : null,
                    icon: const Icon(Icons.save_alt),
                    label: const Text('Ergebnis speichern'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Noch kein Paket: was zu tun ist.
class _OhnePaket extends StatelessWidget {
  const _OhnePaket({required this.onOeffnen});

  final VoidCallback onOeffnen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = theme.colorScheme;
    return Flaeche(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.inventory_2_outlined, size: 44, color: f.primary),
            const SizedBox(height: 12),
            Text(
              'Noch kein Paket geöffnet',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Im Produktions Planer unter Einstellungen → Handy-Erfassung '
              'die Datei erstellen, aufs Handy ziehen und hier öffnen.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: f.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onOeffnen,
              icon: const Icon(Icons.folder_open),
              label: const Text('Paket öffnen'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Eine große Kachel der Startseite.
class _Kachel extends StatelessWidget {
  const _Kachel({
    required this.icon,
    required this.titel,
    required this.text,
    required this.onTap,
    this.marke,
  });

  final IconData icon;
  final String titel;
  final String text;
  final String? marke;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = theme.colorScheme;
    return Flaeche(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 8, 16),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: f.primary.withValues(alpha: 0.12),
                borderRadius: Masse.ecken,
              ),
              child: Icon(icon, size: 28, color: f.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titel,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: f.onSurfaceVariant,
                    ),
                  ),
                  if (marke != null) ...[
                    const SizedBox(height: 6),
                    Marke(marke!, farbe: Farben.von(context).ok),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: f.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
