import 'dart:io';

import 'package:erfassung_format/erfassung_format.dart';
import 'package:flutter/material.dart';

import 'bausteine.dart';
import 'kamera.dart';
import 'modell.dart';
import 'stil.dart';

// Fotos: aus der laufenden Produktion eines Artikels und Musterfotos. Die
// Kamera-App des Handys nimmt auf, die App bekommt das Bild verkleinert
// zurück und legt es in ihren Ordner. Mit „Ergebnis speichern" gehen die
// Fotos in der Ergebnis-Datei an den Planer: Fotos aus der Produktion zum
// Artikel, Musterfotos in den Foto-Eingang der Produktentwicklung.

/// „312 KB" oder „1,4 MB".
String groesseText(int bytes) => bytes < 1024 * 1024
    ? '${(bytes / 1024).round()} KB'
    : '${zahlText(bytes / (1024 * 1024))} MB';

/// „3 Fotos · 1,2 MB".
String fotoAnzahlText(int anzahl, int bytes) =>
    '${anzahl == 1 ? '1 Foto' : '$anzahl Fotos'} · ${groesseText(bytes)}';

/// Wozu ein Foto gehört — als Zeile: „Grillwurst" oder „Musterfoto ·
/// Pfeffer grob".
String fotoTitel(ErfasstesFoto f) => switch (f.art) {
      FotoArt.produktion => f.artikel ?? 'Foto aus der Produktion',
      FotoArt.muster => (f.bezeichnung ?? '').isEmpty
          ? 'Musterfoto'
          : 'Musterfoto · ${f.bezeichnung}',
    };

/// Öffnet die Kamera für ein Foto aus der Produktion des Artikels und
/// sagt, was daraus wurde.
Future<void> produktionsfotoAufnehmen(
  BuildContext context,
  ErfassungsModell modell, {
  required String artikelId,
  required String artikel,
  String? produktionId,
}) async {
  try {
    final neu = await modell.fotoAufnehmen(
      artikelId: artikelId,
      artikel: artikel,
      produktionId: produktionId,
    );
    if (neu && context.mounted) melde(context, 'Foto gespeichert: $artikel');
  } on FotoFehler catch (e) {
    if (context.mounted) melde(context, e.meldung);
  } catch (e) {
    if (context.mounted) melde(context, 'Das Foto ging nicht: $e');
  }
}

/// Fragt, wie das Muster heißt, und öffnet dann die Kamera.
Future<void> musterfotoAufnehmen(
  BuildContext context,
  ErfassungsModell modell,
) async {
  final feld = TextEditingController();
  final bezeichnung = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Musterfoto'),
      content: TextField(
        key: const ValueKey('muster-bezeichnung'),
        controller: feld,
        autofocus: true,
        maxLength: 60,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Bezeichnung',
          hintText: 'z. B. Muster 2, grob gewolft',
          helperText: 'Im Planer ordnest du das Foto einem Projekt zu.',
          helperMaxLines: 2,
        ),
        onSubmitted: (t) => Navigator.of(ctx).pop(t),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: () => Navigator.of(ctx).pop(feld.text),
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Kamera'),
        ),
      ],
    ),
  );
  if (bezeichnung == null || !context.mounted) return;
  try {
    final neu = await modell.fotoAufnehmen(bezeichnung: bezeichnung);
    if (neu && context.mounted) melde(context, 'Musterfoto gespeichert.');
  } on FotoFehler catch (e) {
    if (context.mounted) melde(context, e.meldung);
  } catch (e) {
    if (context.mounted) melde(context, 'Das Foto ging nicht: $e');
  }
}

/// Ein Foto klein, beschnitten auf ein festes Maß.
class FotoBild extends StatelessWidget {
  const FotoBild({
    super.key,
    required this.datei,
    this.breite = 72,
    this.hoehe = 72,
  });

  final File? datei;
  final double breite;
  final double hoehe;

  @override
  Widget build(BuildContext context) {
    final f = Theme.of(context).colorScheme;
    final fehlt = Center(
      child: Icon(Icons.broken_image_outlined, color: f.onSurfaceVariant),
    );
    final d = datei;
    return ClipRRect(
      borderRadius: Masse.ecken,
      child: Container(
        width: breite,
        height: hoehe,
        color: f.surfaceContainerHighest,
        child: d == null
            ? fehlt
            : Image.file(
                d,
                fit: BoxFit.cover,
                // Nur so groß entpacken, wie die Kachel braucht.
                cacheWidth: (breite * 3).round(),
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => fehlt,
              ),
      ),
    );
  }
}

/// Die Fotos zu einem Artikel als Streifen — mit dem Knopf für ein
/// weiteres. Antippen zeigt ein Foto groß.
class FotoStreifen extends StatelessWidget {
  const FotoStreifen({
    super.key,
    required this.modell,
    required this.artikelId,
    required this.artikel,
    this.produktionId,
  });

  final ErfassungsModell modell;
  final String artikelId;
  final String artikel;
  final String? produktionId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: modell,
      builder: (context, _) {
        final fotos = modell.stand.fotosVon(artikelId);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (fotos.isNotEmpty) ...[
              SizedBox(
                height: 84,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: fotos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => InkWell(
                    key: ValueKey('foto-${fotos[i].id}'),
                    onTap: () => fotoZeigen(context, modell, fotos[i]),
                    child: FotoBild(
                      datei: modell.fotoDatei(fotos[i].id),
                      breite: 112,
                      hoehe: 84,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            OutlinedButton.icon(
              key: const ValueKey('foto-produktion'),
              onPressed: () => produktionsfotoAufnehmen(
                context,
                modell,
                artikelId: artikelId,
                artikel: artikel,
                produktionId: produktionId,
              ),
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(
                fotos.isEmpty ? 'Foto aufnehmen' : 'Weiteres Foto aufnehmen',
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Zeigt ein Foto groß.
Future<void> fotoZeigen(
  BuildContext context,
  ErfassungsModell modell,
  ErfasstesFoto foto,
) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FotoSeite(modell: modell, foto: foto),
      ),
    );

/// Ein Foto groß — zum Hineinzoomen, mit Löschen.
class _FotoSeite extends StatelessWidget {
  const _FotoSeite({required this.modell, required this.foto});

  final ErfassungsModell modell;
  final ErfasstesFoto foto;

  Future<void> _loeschen(BuildContext context) async {
    final ok = await nachfragen(
      context,
      titel: 'Foto löschen?',
      text: 'Das Foto wird vom Handy gelöscht.',
      ja: 'Löschen',
      gefaehrlich: true,
    );
    if (!ok) return;
    await modell.fotoLoeschen(foto.id);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = theme.colorScheme;
    final datei = modell.fotoDatei(foto.id);
    return Scaffold(
      appBar: AppBar(
        title: Text(fotoTitel(foto)),
        actions: [
          IconButton(
            key: const ValueKey('foto-loeschen'),
            tooltip: 'Foto löschen',
            onPressed: () => _loeschen(context),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: datei == null
                  ? const Icon(Icons.broken_image_outlined, size: 48)
                  : InteractiveViewer(
                      maxScale: 6,
                      child: Image.file(
                        datei,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.broken_image_outlined,
                          size: 48,
                        ),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                [
                  '${datumText(foto.aufgenommenAm)}, '
                      '${uhrzeit(foto.aufgenommenAm)} Uhr',
                  if ((foto.kuerzel ?? '').isNotEmpty) foto.kuerzel!,
                  groesseText(foto.groesse),
                ].join(' · '),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: f.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Alle Fotos auf dem Handy: oben der Knopf fürs Musterfoto, darunter die
/// Musterfotos und die Fotos aus der Produktion — das neueste zuerst.
class FotosSeite extends StatelessWidget {
  const FotosSeite({super.key, required this.modell});

  final ErfassungsModell modell;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: modell,
      builder: (context, _) {
        final theme = Theme.of(context);
        final f = theme.colorScheme;
        final stand = modell.stand;
        final muster = stand.musterfotos;
        final produktion = [
          for (final x in stand.fotoListe)
            if (x.art == FotoArt.produktion) x,
        ];
        return Scaffold(
          appBar: AppBar(title: const Text('Fotos')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                FilledButton.icon(
                  key: const ValueKey('foto-muster'),
                  onPressed: () => musterfotoAufnehmen(context, modell),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Musterfoto aufnehmen'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Fotos aus der Produktion nimmst du beim Erfassen einer '
                  'Produktion oder bei den Maschineneinstellungen des '
                  'Artikels auf.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: f.onSurfaceVariant,
                  ),
                ),
                if (muster.isNotEmpty)
                  Abschnitt('Musterfotos', zusatz: '${muster.length}'),
                for (final x in muster) _FotoZeile(modell: modell, foto: x),
                if (produktion.isNotEmpty)
                  Abschnitt(
                    'Aus der Produktion',
                    zusatz: '${produktion.length}',
                  ),
                for (final x in produktion) _FotoZeile(modell: modell, foto: x),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FotoZeile extends StatelessWidget {
  const _FotoZeile({required this.modell, required this.foto});

  final ErfassungsModell modell;
  final ErfasstesFoto foto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Flaeche(
        key: ValueKey('fotozeile-${foto.id}'),
        onTap: () => fotoZeigen(context, modell, foto),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              FotoBild(datei: modell.fotoDatei(foto.id)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fotoTitel(foto),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${tagKurz(foto.aufgenommenAm)} '
                      '${uhrzeit(foto.aufgenommenAm)} Uhr · '
                      '${groesseText(foto.groesse)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: f.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: f.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
