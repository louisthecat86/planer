import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/app_stil.dart';

// Fotos zeigen: als kleine Kachel in einer Liste oder Leiste und groß zum
// Hineinzoomen.

/// Ein Foto als Kachel fester Größe — beschnitten, damit eine Leiste aus
/// Hoch- und Querformaten ruhig aussieht. [bild] null: Es lädt noch.
class FotoKachel extends StatelessWidget {
  const FotoKachel({
    super.key,
    required this.bild,
    this.breite = 96,
    this.hoehe = 72,
    this.fehlt = false,
    this.hervorgehoben = false,
    this.onTap,
  });

  final Uint8List? bild;
  final double breite;
  final double hoehe;

  /// Das Bild gibt es nicht (mehr).
  final bool fehlt;

  /// Mit farbigem Rand — etwa das Referenzbild.
  final bool hervorgehoben;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    final kaputt = Center(
      child: Icon(
        Icons.broken_image_outlined,
        size: 20,
        color: farben.onSurfaceVariant,
      ),
    );
    final daten = bild;
    final Widget inhalt;
    if (fehlt) {
      inhalt = kaputt;
    } else if (daten == null) {
      inhalt = const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else {
      inhalt = Image.memory(
        daten,
        fit: BoxFit.cover,
        // Nur so groß entpacken, wie die Kachel braucht.
        cacheWidth: (breite * 2).round(),
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => kaputt,
      );
    }
    return SizedBox(
      width: breite,
      height: hoehe,
      child: Material(
        color: farben.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: AppMasse.ecken,
          side: BorderSide(
            color: hervorgehoben ? farben.primary : farben.outline,
            width: hervorgehoben ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            inhalt,
            // Darüber, damit die Tipp-Welle auf dem Bild zu sehen ist.
            if (onTap != null)
              Material(
                type: MaterialType.transparency,
                child: InkWell(onTap: onTap),
              ),
          ],
        ),
      ),
    );
  }
}

/// Zeigt [bild] groß in einem Dialog — mit dem Mausrad oder zwei Fingern
/// lässt sich hineinzoomen. [aktionen] stehen unten links neben
/// „Schließen".
Future<void> fotoGrossZeigen(
  BuildContext context, {
  required Uint8List bild,
  required String titel,
  String? untertitel,
  List<Widget> Function(BuildContext dialog)? aktionen,
}) =>
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final groesse = MediaQuery.sizeOf(ctx);
        return AlertDialog(
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titel),
              if (untertitel != null && untertitel.isNotEmpty)
                Text(
                  untertitel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          content: SizedBox(
            width: (groesse.width - 160).clamp(280.0, 1100.0),
            height: (groesse.height - 280).clamp(200.0, 800.0),
            child: ClipRect(
              child: InteractiveViewer(
                maxScale: 6,
                child: Center(
                  child: Image.memory(
                    bild,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      size: 40,
                    ),
                  ),
                ),
              ),
            ),
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: aktionen?.call(ctx) ?? const [],
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Schließen'),
            ),
          ],
        );
      },
    );
