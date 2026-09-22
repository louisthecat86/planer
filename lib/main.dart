import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/utils/vollbild.dart';

Future<void> main() async {
  // Nötig, bevor das Fenster-Plugin angesprochen wird.
  WidgetsFlutterBinding.ensureInitialized();
  await Vollbild.starten();

  runApp(
    const ProviderScope(
      child: ProduktionPlanerApp(),
    ),
  );
}
