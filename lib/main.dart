import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/ui/fehler_anzeige.dart';
import 'core/utils/vollbild.dart';

Future<void> main() async {
  // Nötig, bevor das Fenster-Plugin angesprochen wird.
  WidgetsFlutterBinding.ensureInitialized();
  // Fehler, die niemand abfängt, als Meldung statt nur in der Konsole.
  fehlerAnzeigeEinrichten();
  await Vollbild.starten();

  runApp(
    const ProviderScope(
      child: ProduktionPlanerApp(),
    ),
  );
}
