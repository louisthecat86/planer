import 'package:flutter/material.dart';

class ProductListScreen extends StatelessWidget {
  const ProductListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Produkte'),
      ),
      body: const Center(
        child: Text(
          'Phase 1a: Datenmodell und lokale Datenbank sind vorbereitet.\n'
          'In Phase 1b bauen wir hier die Produkt- und Planungsverwaltung auf.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
