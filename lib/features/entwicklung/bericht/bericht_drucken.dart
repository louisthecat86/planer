import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/druck/druck_fenster.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/utils/fehler_text.dart';
import '../daten/dateien.dart';
import 'bericht_pdf.dart';
import 'projekt_bericht.dart';

/// Lädt den Projektbericht und öffnet das Druckfenster — dort lassen sich
/// Kapitel, Steckbrief und Verlauf wählen, und er lässt sich drucken oder
/// als PDF speichern. Fehler erscheinen unten.
Future<void> projektberichtDrucken(
  BuildContext context,
  WidgetRef ref,
  EntwicklungsProjekt projekt,
) async {
  // Vor der ersten Wartestelle holen — so hängt nichts an einem Kontext,
  // der nach dem Laden vielleicht nicht mehr lebt.
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  try {
    final bericht = await berichtLaden(
      ref.read(databaseProvider),
      ref.read(entwicklungDateienProvider),
      projekt,
    );
    if (!navigator.mounted) return;
    await druckFensterOeffnen(navigator.context, berichtDruckAuftrag(bericht));
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(
          'Der Projektbericht ließ sich nicht erstellen. (${fehlerText(e)})',
        ),
      ),
    );
  }
}
