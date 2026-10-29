import 'package:flutter/material.dart';

import '../../core/druck/druck_fenster.dart';
import '../../core/utils/fehler_text.dart';
import 'datenblatt.dart';

/// Lädt die Blätter über [laden] und öffnet das Druckfenster. Fehlt die
/// Planung inzwischen oder scheitert etwas, steht es als Meldung da.
///
/// Meldungen und Fenster hängen an der App, nicht an [context]: Beides
/// wird vor der ersten Wartestelle geholt — so stört es nicht, wenn der
/// Bildschirm während des Ladens geschlossen wird. Auch der Kontext des
/// Navigators selbst taugt (etwa aus einer Meldung heraus).
Future<void> druckeDatenblaetterMitMeldung(
  BuildContext context,
  Future<List<Datenblatt>> Function() laden,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  try {
    final blaetter = await laden();
    if (blaetter.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Kein Datenblatt — diese Planung gibt es nicht mehr. Bitte die '
            'Ansicht neu laden.',
          ),
        ),
      );
      return;
    }
    if (!navigator.mounted) return;
    await druckFensterOeffnen(
      navigator.context,
      datenblattDruckAuftrag(blaetter),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(
          'Das Datenblatt ließ sich nicht erstellen. (${fehlerText(e)})',
        ),
      ),
    );
  }
}
