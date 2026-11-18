import 'package:erfassung_format/erfassung_format.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'bausteine.dart';
import 'fotos.dart';
import 'modell.dart';
import 'stil.dart';

// „An PC": was in die Ergebnis-Datei geht, auf einen Blick — und der eine
// Knopf, der sie speichert.

/// Zeigt von unten, was an den PC geht, und speichert auf Wunsch die
/// Ergebnis-Datei. [onPaket] öffnet ein anderes Paket.
Future<void> ergebnisBlattZeigen(
  BuildContext context,
  ErfassungsModell modell, {
  required VoidCallback onPaket,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SendenBlatt(modell: modell, onPaket: onPaket),
    );

/// Speichert die Ergebnis-Datei — der Nutzer wählt, wohin — und sagt,
/// wie es weitergeht.
Future<void> ergebnisSpeichern(
  BuildContext context,
  ErfassungsModell modell,
) async {
  final jetzt = DateTime.now();
  try {
    // Mit den Bildern der Fotos — die liegen als Dateien im Ordner der
    // App.
    final datei = await modell.ergebnisDatei(jetzt);
    if (datei == null || !context.mounted) return;
    final ergebnis = datei.ergebnis;
    if (ergebnis.leer) {
      melde(context, 'Es ist noch nichts erfasst.');
      return;
    }
    final ziel = await FilePicker.saveFile(
      dialogTitle: 'Ergebnis speichern',
      fileName: ergebnis.dateiname(kuerzel: modell.stand.kuerzel),
      bytes: datei.bytes,
    );
    if (ziel == null || !context.mounted) return;
    await modell.ergebnisGespeichert(jetzt);
    if (!context.mounted) return;
    final fotos = ergebnis.fotos.length;
    final fehlen = datei.fotosFehlen;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ergebnis gespeichert'),
        content: Text(
          [
            'Jetzt die Datei an den PC bringen und im Planer unter '
                'Einstellungen → Handy-Erfassung einlesen.',
            if (fotos > 0)
              '${fotos == 1 ? 'Das Foto steht' : 'Die $fotos Fotos '
                      'stehen'} mit in der Datei '
                  '(${groesseText(datei.bytes.length)}).',
            if (fehlen > 0)
              '${fehlen == 1 ? 'Ein Foto fehlt' : '$fehlen Fotos '
                  'fehlen'} — das Bild liegt nicht mehr auf dem Handy.',
            'Das Erfasste bleibt auf dem Handy, bis du ein neues Paket '
                'öffnest.',
          ].join('\n\n'),
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
    if (context.mounted) {
      melde(context, 'Das Ergebnis ließ sich nicht speichern: $e');
    }
  }
}

class _SendenBlatt extends StatelessWidget {
  const _SendenBlatt({required this.modell, required this.onPaket});

  final ErfassungsModell modell;
  final VoidCallback onPaket;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: modell,
      builder: (context, _) {
        final theme = Theme.of(context);
        final f = theme.colorScheme;
        final farben = Farben.von(context);
        final stand = modell.stand;
        final paket = stand.paket;
        final u = stand.uebersicht(DateTime.now());
        final werteArtikel = {for (final w in stand.werte.values) w.artikelId};
        final ketten =
            stand.neueSchritte.length + stand.entfernteSchritte.length;
        final begonnen = u.offen.where((e) => e.begonnen).length +
            u.morgen.where((e) => e.begonnen).length +
            u.spaeter.where((e) => e.begonnen).length;
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'An den PC senden',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (paket != null)
                Text(
                  'Paket vom ${datumText(paket.erstellt)}, '
                  '${uhrzeit(paket.erstellt)} · ${tagKurz(paket.von)} bis '
                  '${tagKurz(paket.bis)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: f.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: 14),
              Flaeche(
                hintergrund: farben.flaeche2,
                child: Column(
                  children: [
                    _Posten(
                      icon: Icons.task_alt,
                      titel: 'Produktionen',
                      text: 'erfasst',
                      zahl: stand.produktionen.length,
                    ),
                    _Posten(
                      icon: Icons.tune,
                      titel: 'Maschinenwerte',
                      text: werteArtikel.isEmpty
                          ? 'geändert'
                          : 'geändert an ${werteArtikel.length == 1 ? '1 '
                              'Artikel' : '${werteArtikel.length} Artikeln'}',
                      zahl: stand.werte.length,
                    ),
                    if (ketten > 0)
                      _Posten(
                        icon: Icons.account_tree_outlined,
                        titel: 'Prozessketten',
                        text: [
                          if (stand.neueSchritte.isNotEmpty)
                            '${stand.neueSchritte.length} dazu',
                          if (stand.entfernteSchritte.isNotEmpty)
                            '${stand.entfernteSchritte.length} weg',
                        ].join(' · '),
                        zahl: ketten,
                      ),
                    _Posten(
                      icon: Icons.photo_library_outlined,
                      titel: 'Fotos',
                      text: stand.fotos.isEmpty
                          ? 'keine'
                          : groesseText(stand.fotoBytes),
                      zahl: stand.fotos.length,
                      letzter: true,
                    ),
                  ],
                ),
              ),
              if (u.laeuft.isNotEmpty || begonnen > 0) ...[
                const SizedBox(height: 12),
                Hinweis(
                  '${[
                    if (u.laeuft.isNotEmpty)
                      u.laeuft.length == 1
                          ? '1 Produktion läuft noch'
                          : '${u.laeuft.length} Produktionen laufen noch',
                    if (begonnen > 0)
                      begonnen == 1
                          ? '1 ist begonnen'
                          : '$begonnen sind '
                              'begonnen',
                  ].join(', ')} — sie gehen erst mit, wenn sie erfasst '
                  'sind.',
                  farbe: farben.warnung,
                  icon: Icons.timelapse,
                ),
              ],
              if (!stand.ungesichert && stand.gespeichertAm != null) ...[
                const SizedBox(height: 12),
                Hinweis(
                  'Alles gespeichert am ${datumText(stand.gespeichertAm!)} '
                  'um ${uhrzeit(stand.gespeichertAm!)} Uhr.',
                  farbe: farben.ok,
                  icon: Icons.cloud_done_outlined,
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const ValueKey('ergebnis-speichern'),
                onPressed: stand.hatErfasstes
                    ? () => ergebnisSpeichern(context, modell)
                    : null,
                icon: const Icon(Icons.save_alt),
                label: const Text('Ergebnis-Datei speichern'),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onPaket();
                },
                child: const Text('Anderes Paket öffnen'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Posten extends StatelessWidget {
  const _Posten({
    required this.icon,
    required this.titel,
    required this.text,
    required this.zahl,
    this.letzter = false,
  });

  final IconData icon;
  final String titel;
  final String text;
  final int zahl;
  final bool letzter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: letzter
            ? null
            : Border(bottom: BorderSide(color: f.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: f.surface,
              borderRadius: Masse.eckenKlein,
            ),
            child: Icon(icon, size: 21, color: f.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titel,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  text,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: f.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '$zahl',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: zahl == 0 ? f.onSurfaceVariant : f.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
