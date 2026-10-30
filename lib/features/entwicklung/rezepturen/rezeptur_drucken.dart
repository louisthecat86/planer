import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/druck/druck_fenster.dart';
import '../../../core/druck/druck_optionen.dart';
import '../../../core/utils/fehler_text.dart';
import '../daten/entwicklung_repository.dart';
import '../projekte/projekt_repository.dart';
import 'rezeptur_druck_daten.dart';
import 'rezepturblatt_druck.dart';
import 'standvergleich_druck.dart';

// Rezepturblatt und Vergleich der Stände drucken: die Daten laden
// (rezeptur_druck_daten.dart) und das Druckfenster öffnen.

/// Öffnet das Druckfenster für das Rezepturblatt des Stands [versionId].
/// Fehler erscheinen unten.
Future<void> rezepturblattDrucken(
  BuildContext context,
  WidgetRef ref,
  String versionId,
) =>
    _drucken(
      context,
      fehler: 'Das Rezepturblatt ließ sich nicht erstellen.',
      laden: () async {
        final daten = await rezepturblattLaden(
          ref.read(entwicklungRepositoryProvider),
          ref.read(projektRepositoryProvider),
          versionId,
        );
        return daten == null ? null : rezepturblattDruckAuftrag(daten);
      },
    );

/// Öffnet das Druckfenster für den Vergleich der Stände der Rezeptur
/// [rezepturId] — vorgewählt [vorwahl], ohne die beiden neuesten.
Future<void> standvergleichDrucken(
  BuildContext context,
  WidgetRef ref,
  String rezepturId, {
  Set<String> vorwahl = const {},
}) =>
    _drucken(
      context,
      fehler: 'Der Vergleich der Stände ließ sich nicht erstellen.',
      laden: () async {
        final daten = await standvergleichLaden(
          ref.read(entwicklungRepositoryProvider),
          ref.read(projektRepositoryProvider),
          rezepturId,
        );
        return daten == null
            ? null
            : standvergleichDruckAuftrag(daten, vorwahl: vorwahl);
      },
    );

/// Ein Druckfenster nach dem anderen — ein Doppelklick öffnete sonst
/// zwei.
bool _laeuft = false;

Future<void> _drucken(
  BuildContext context, {
  required String fehler,
  required Future<DruckAuftrag?> Function() laden,
}) async {
  if (_laeuft) return;
  _laeuft = true;
  // Vor der ersten Wartestelle holen — so hängt nichts an einem Kontext,
  // der nach dem Laden vielleicht nicht mehr lebt.
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  try {
    final auftrag = await laden();
    if (!navigator.mounted) return;
    if (auftrag == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Diesen Stand gibt es nicht mehr.')),
      );
      return;
    }
    await druckFensterOeffnen(navigator.context, auftrag);
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text('$fehler (${fehlerText(e)})'),
      ),
    );
  } finally {
    _laeuft = false;
  }
}
