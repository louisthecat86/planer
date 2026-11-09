import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/druck/druck_fenster.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/utils/fehler_text.dart';
import '../daten/dateien.dart';
import '../projekte/originaletikett.dart' show pdfSeitenGerastert;
import 'bericht_formblatt.dart';
import 'bericht_pdf.dart';
import 'formblatt_dialog.dart';
import 'projekt_bericht.dart';

/// Lädt den Projektbericht und öffnet das Druckfenster — dort lassen sich
/// Kapitel, Steckbrief und Verlauf wählen, Kopf- und Fußzeile einstellen,
/// und er lässt sich drucken oder als PDF speichern. Fehler erscheinen
/// unten.
Future<void> projektberichtDrucken(
  BuildContext context,
  WidgetRef ref,
  EntwicklungsProjekt projekt,
) async {
  // Vor der ersten Wartestelle holen — so hängt nichts an einem Kontext,
  // der nach dem Laden vielleicht nicht mehr lebt.
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  final dateien = ref.read(entwicklungDateienProvider);
  try {
    final bericht = await berichtLaden(
      ref.read(databaseProvider),
      dateien,
      projekt,
      // Ein Originaletikett als PDF kommt als Bild seiner Seiten hinein.
      pdfSeiten: pdfSeitenGerastert,
    );
    var formblatt = await berichtFormblattLaden(dateien);
    if (!navigator.mounted) return;
    await druckFensterOeffnen(
      navigator.context,
      berichtDruckAuftrag(bericht, formblatt: () => formblatt),
      aktionen: [_kopfUndFuss((neu) => formblatt = neu)],
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

/// Die leere Vorlage des Projektberichts im Druckfenster — zum Speichern
/// als PDF bei den Formblättern.
Future<void> projektberichtVorlage(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  try {
    var formblatt = await berichtFormblattLaden(
      ref.read(entwicklungDateienProvider),
    );
    if (!navigator.mounted) return;
    await druckFensterOeffnen(
      navigator.context,
      berichtVorlageDruckAuftrag(formblatt: () => formblatt),
      aktionen: [_kopfUndFuss((neu) => formblatt = neu)],
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(
          'Die Vorlage ließ sich nicht erstellen. (${fehlerText(e)})',
        ),
      ),
    );
  }
}

/// Der Bericht über die Produktentwicklung im Druckfenster — oben rechts
/// mit dem Logo des Projektberichts.
Future<void> entwicklungsberichtDrucken(
  BuildContext context,
  WidgetRef ref,
  EntwicklungsberichtDaten daten,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  try {
    final formblatt = await berichtFormblattLaden(
      ref.read(entwicklungDateienProvider),
    );
    if (!navigator.mounted) return;
    await druckFensterOeffnen(
      navigator.context,
      entwicklungsberichtDruckAuftrag(daten, formblatt: formblatt),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(
          'Der Bericht ließ sich nicht erstellen. (${fehlerText(e)})',
        ),
      ),
    );
  }
}

/// „Kopf- und Fußzeile …" im Druckfenster: Gespeichertes geht an
/// [uebernehmen], die Vorschau folgt.
DruckAktion _kopfUndFuss(void Function(BerichtFormblatt neu) uebernehmen) =>
    DruckAktion(
      titel: 'Kopf- und Fußzeile …',
      hinweis: 'Formblatt, Erstellt und Geprüft von, Version, Stand',
      icon: Icons.edit_note,
      ausfuehren: (context) async {
        final neu = await formblattBearbeiten(context);
        if (neu == null) return false;
        uebernehmen(neu);
        return true;
      },
    );
