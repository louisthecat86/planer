import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/database/database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/utils/fehler_text.dart';
import '../daten/dateien.dart';
import '../projekte/datei_aktionen.dart' show sichererDateiname;
import 'projekt_bericht.dart';

/// Baut den Projektbericht und öffnet die Druckvorschau — dort lässt er
/// sich drucken oder als PDF speichern. Fehler erscheinen unten.
Future<void> projektberichtDrucken(
  BuildContext context,
  WidgetRef ref,
  EntwicklungsProjekt projekt,
) async {
  // Vor der ersten Wartestelle holen — so hängt nichts an einem Kontext,
  // der nach dem Laden vielleicht nicht mehr lebt.
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bericht = await berichtLaden(
      ref.read(databaseProvider),
      ref.read(entwicklungDateienProvider),
      projekt,
    );
    final bytes = await baueProjektPdf(bericht);
    await Printing.layoutPdf(
      name: 'Projektbericht_${sichererDateiname(projekt.name)}',
      onLayout: (_) async => bytes,
    );
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
