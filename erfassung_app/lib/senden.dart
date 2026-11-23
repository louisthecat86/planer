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

/// Ab dieser Größe nehmen manche Postfächer den Anhang nicht mehr an.
const int _mailGrenzeBytes = 15 * 1024 * 1024;

/// Fragt nach der E-Mail-Adresse, an die das Ergebnis geht — liefert die
/// neue Adresse oder null, wenn abgebrochen.
Future<String?> mailAdresseFragen(
  BuildContext context,
  ErfassungsModell modell,
) async {
  final feld = TextEditingController(text: modell.stand.mailAn);
  String? fehler;
  final neu = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setze) {
        void fertig() {
          final t = feld.text.trim();
          if (!istMailAdresse(t)) {
            setze(() => fehler = 'Das ist keine E-Mail-Adresse.');
            return;
          }
          Navigator.of(ctx).pop(t);
        }

        return AlertDialog(
          title: const Text('E-Mail an den PC'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'An welche Adresse soll das Ergebnis gehen? Am besten die, '
                'die du am PC im Planer abrufst. Die App merkt sie sich.',
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('mail-adresse'),
                controller: feld,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => fertig(),
                decoration: InputDecoration(
                  labelText: 'E-Mail-Adresse',
                  errorText: fehler,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
              onPressed: fertig,
              child: const Text('Übernehmen'),
            ),
          ],
        );
      },
    ),
  );
  if (neu == null) return null;
  await modell.mailAnSetzen(neu);
  return neu;
}

/// Öffnet die E-Mail-App mit dem Ergebnis als Anhang — an die gemerkte
/// Adresse, beim ersten Mal wird gefragt. Danach fragt die App, ob die
/// E-Mail raus ist; erst dann gilt das Erfasste als gesichert.
Future<void> ergebnisMailen(
  BuildContext context,
  ErfassungsModell modell,
) async {
  final jetzt = DateTime.now();
  try {
    var an = modell.stand.mailAn;
    if (!istMailAdresse(an)) {
      final neu = await mailAdresseFragen(context, modell);
      if (neu == null || !context.mounted) return;
      an = neu;
    }
    // Mit Fotos dauert das Packen und Verschlüsseln ein paar Sekunden.
    if (modell.stand.fotos.isNotEmpty) {
      melde(context, 'Ergebnis wird vorbereitet …');
    }
    final datei = await modell.ergebnisDatei(jetzt);
    if (datei == null || !context.mounted) return;
    final ergebnis = datei.ergebnis;
    if (ergebnis.leer) {
      melde(context, 'Es ist noch nichts erfasst.');
      return;
    }
    if (datei.bytes.length > _mailGrenzeBytes) {
      final trotzdem = await nachfragen(
        context,
        titel: 'Großer Anhang',
        text: 'Mit den Fotos ist die Datei '
            '${groesseText(datei.bytes.length)} groß. Manche Postfächer '
            'nehmen so große Anhänge nicht an. Trotzdem per E-Mail senden '
            '— oder lieber als Datei speichern?',
        ja: 'Trotzdem senden',
      );
      if (!trotzdem || !context.mounted) return;
    }
    final kuerzel = modell.stand.kuerzel;
    final wann = '${datumText(jetzt)}, ${uhrzeit(jetzt)} Uhr';
    final aus = await MailVersand.senden(
      an: an,
      betreff: 'Planer Erfassung: Ergebnis vom $wann'
          '${kuerzel.isEmpty ? '' : ' ($kuerzel)'}',
      text: 'Ergebnis der Planer Erfassung vom $wann.\n\n'
          'Im Planer unter Einstellungen → Handy-Erfassung den Anhang '
          'einlesen: speichern und „Ergebnis einlesen" wählen oder die '
          'Datei aufs Fenster ziehen.',
      dateiname: ergebnis.dateiname(kuerzel: kuerzel),
      bytes: datei.bytes,
    );
    if (!context.mounted) return;
    switch (aus) {
      case MailErgebnis.keineApp:
        melde(
          context,
          'Auf dem Handy ist keine E-Mail-App eingerichtet. Das Ergebnis '
          'lässt sich als Datei speichern.',
        );
        return;
      case MailErgebnis.fehler:
        melde(
          context,
          'Die E-Mail-App ließ sich nicht öffnen. Das Ergebnis lässt sich '
          'als Datei speichern.',
        );
        return;
      case MailErgebnis.geoeffnet:
        break;
    }
    // Die E-Mail-App ist jetzt vorn. Kommt man zurück, steht hier die
    // Frage, ob die Nachricht raus ist.
    final gesendet = await nachfragen(
      context,
      titel: 'E-Mail gesendet?',
      text: 'Ist die E-Mail mit dem Ergebnis an $an raus? Dann gilt das '
          'Erfasste als gesichert. Es bleibt auf dem Handy, bis du ein '
          'neues Paket öffnest.',
      ja: 'Ja, gesendet',
    );
    if (!gesendet) return;
    await modell.ergebnisGespeichert(jetzt);
    if (context.mounted) melde(context, 'Ergebnis an $an gesendet.');
  } catch (e) {
    if (context.mounted) {
      melde(context, 'Das Ergebnis ließ sich nicht senden: $e');
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
              const SizedBox(height: 12),
              _SchutzZeile(
                geschuetzt: stand.paket?.ergebnisSchluesselBytes != null,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const ValueKey('ergebnis-mailen'),
                onPressed: stand.hatErfasstes
                    ? () => ergebnisMailen(context, modell)
                    : null,
                icon: const Icon(Icons.forward_to_inbox),
                label: const Text('Per E-Mail an den PC'),
              ),
              const SizedBox(height: 2),
              TextButton.icon(
                key: const ValueKey('mail-adresse-aendern'),
                onPressed: () => mailAdresseFragen(context, modell),
                icon: const Icon(Icons.alternate_email, size: 18),
                label: Text(
                  stand.mailAn.isEmpty
                      ? 'E-Mail-Adresse eintragen'
                      : 'an ${stand.mailAn} · ändern',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                key: const ValueKey('ergebnis-speichern'),
                onPressed: stand.hatErfasstes
                    ? () => ergebnisSpeichern(context, modell)
                    : null,
                icon: const Icon(Icons.save_alt),
                label: const Text('Als Datei speichern'),
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

/// Sagt, ob das Ergebnis verschlüsselt zurückgeht.
class _SchutzZeile extends StatelessWidget {
  const _SchutzZeile({required this.geschuetzt});

  final bool geschuetzt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final farben = Farben.von(context);
    final farbe = geschuetzt ? farben.ok : farben.warnung;
    return Row(
      key: ValueKey(geschuetzt ? 'ergebnis-geschuetzt' : 'ergebnis-offen'),
      children: [
        Icon(
          geschuetzt ? Icons.lock_outline : Icons.lock_open,
          size: 18,
          color: farbe,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            geschuetzt
                ? 'Verschlüsselt — nur dein Planer kann das Ergebnis öffnen.'
                : 'Unverschlüsselt — das Paket stammt von einem älteren '
                    'Planer. Für ein verschlüsseltes Ergebnis ein neues '
                    'Paket holen.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
