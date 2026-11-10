import 'package:flutter/material.dart';

import 'modell.dart';
import 'start_seite.dart';
import 'stil.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ErfassungApp(modell: await ErfassungsModell.laden()));
}

/// Planer Erfassung — die Android-App zum Produktions Planer.
class ErfassungApp extends StatelessWidget {
  const ErfassungApp({super.key, required this.modell});

  final ErfassungsModell modell;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Planer Erfassung',
      debugShowCheckedModeBanner: false,
      theme: AppStil.hell(),
      darkTheme: AppStil.dunkel(),
      home: StartSeite(modell: modell),
    );
  }
}
