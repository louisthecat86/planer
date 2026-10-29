import 'package:flutter/widgets.dart' show BuildContext;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/druck/druck_fenster.dart';
import 'article_detail_providers.dart';
import 'prozessblatt_druck.dart';

/// Druckt das Prozessblatt eines Artikels (Aufbau: prozessblatt_druck.dart).
///
/// Das Druckfenster fragt, welche Abteilungen und Schritte aufs Blatt
/// sollen, ob jede Abteilung eine eigene Seite bekommt und was je Anlage
/// darauf steht — mit Vorschau.
class ArticlePrintService {
  ArticlePrintService._();

  /// Lädt alle Daten des Artikels und öffnet das Druckfenster.
  static Future<void> drucke(
    BuildContext context,
    WidgetRef ref,
    String productId,
  ) async {
    final produkt = await ref.read(productProvider(productId).future);
    if (produkt == null) return;

    final steps = await ref.read(productStepsProvider(productId).future);
    if (steps.isEmpty) return;

    // Parameter und Anlage je Schritt vorab laden.
    final parameter = <String, List<ProductStepParameter>>{};
    final maschinen = <String, Machine?>{};
    for (final s in steps) {
      parameter[s.id] = await ref.read(stepParametersProvider(s.id).future);
      final mid = s.maschineId;
      maschinen[s.id] =
          mid == null ? null : await ref.read(machineProvider(mid).future);
    }

    if (!context.mounted) return;
    await druckFensterOeffnen(
      context,
      prozessblattDruckAuftrag(
        ProzessblattDaten(
          produkt: produkt,
          schritte: steps,
          parameter: parameter,
          maschinen: maschinen,
        ),
      ),
    );
  }
}
