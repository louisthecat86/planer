import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';

/// Platzhalter-Startbildschirm für Phase 1a.
///
/// Zweck:
///   1. Beweist, dass die Datenbank sich öffnen lässt (zeigt Produkt-Anzahl).
///   2. Zeigt alle Abteilungen mit Farbe + Kurzcode — visuelle Vorschau für
///      das Whiteboard-Dashboard der späteren Phasen.
///
/// Wird in Phase 1b durch das eigentliche Stammdaten-Verwaltungs-UI ersetzt.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Produktion Planer'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _DatabaseStatusCard(db: db),
          const SizedBox(height: 24),
          Text(
            'Abteilungen',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          ...Abteilung.values.map(_AbteilungTile.new),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Phase 1a abgeschlossen',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Datenmodell und lokale Datenbank sind eingerichtet. '
                    'Als Nächstes folgt Phase 1b: Stammdaten-Verwaltung '
                    '(Produkte, Rezepturen, Rohwaren, Chargen).',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DatabaseStatusCard extends StatelessWidget {
  const _DatabaseStatusCard({required this.db});

  final AppDatabase db;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<int>(
          future: db
              .customSelect(
                'SELECT COUNT(*) AS c FROM products '
                'WHERE deleted_at IS NULL',
              )
              .getSingle()
              .then((row) => row.read<int>('c')),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Datenbank wird geöffnet …'),
                ],
              );
            }
            if (snapshot.hasError) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Datenbank-Fehler: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              );
            }
            return Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 12),
                Text(
                  'Datenbank verbunden — ${snapshot.data} Produkte gespeichert',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AbteilungTile extends StatelessWidget {
  const _AbteilungTile(this.abteilung);

  final Abteilung abteilung;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: abteilung.farbe,
          foregroundColor: Colors.white,
          child: Text(abteilung.kurzcode),
        ),
        title: Text(abteilung.anzeigeName),
        subtitle: Text('dbValue: ${abteilung.dbValue}'),
      ),
    );
  }
}
