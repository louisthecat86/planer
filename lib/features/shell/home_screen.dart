import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';

/// Ausgewähltes Datum. Wird von anderen Screens (Board) genutzt und bleibt
/// daher als gemeinsamer Zustand erhalten, auch wenn das Home es selbst
/// nicht mehr anzeigt.
final selectedDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

/// Drei-Kachel-Startbildschirm:
/// Artikel · Planung · Einstellungen.
///
/// Stammdaten (Excel-Import/-Export, Backup) und die Kapazität liegen
/// unter „Einstellungen".
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Produktion Planer')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _DatabaseStatusCard(db: db),
          const SizedBox(height: 20),
          _buildTileGrid(context),
        ],
      ),
    );
  }

  Widget _buildTileGrid(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 600 ? 4 : 2;
        const spacing = 12.0;
        final tileWidth =
            (constraints.maxWidth - spacing * (crossAxisCount - 1)) /
                crossAxisCount;

        final tiles = [
          _NavigationTile(
            icon: Icons.inventory_2_rounded,
            label: 'Artikel',
            subtitle: 'Abläufe, Maschinen, Zeiten & Historie pflegen',
            color: const Color(0xFF1565C0),
            onTap: () => context.pushNamed('articles'),
          ),
          _NavigationTile(
            icon: Icons.calendar_view_week_rounded,
            label: 'Planung',
            subtitle: 'Produktion einplanen & Woche/Tag im Board',
            color: const Color(0xFF2E7D32),
            onTap: () => context.pushNamed('board'),
          ),
          _NavigationTile(
            icon: Icons.history_rounded,
            label: 'Wochen-Historie',
            subtitle: 'Archivierte Wochenpläne & Kennzahlen',
            color: const Color(0xFF00897B),
            onTap: () => context.pushNamed('wochenHistorie'),
          ),
          _NavigationTile(
            icon: Icons.settings_rounded,
            label: 'Einstellungen',
            subtitle: 'Stammdaten, Excel, Backup & Kapazität',
            color: const Color(0xFF455A64),
            onTap: () => context.pushNamed('settings'),
          ),
        ];

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: tiles
              .map((tile) => SizedBox(width: tileWidth, child: tile))
              .toList(),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Navigation tile
// ---------------------------------------------------------------------------

class _NavigationTile extends StatelessWidget {
  const _NavigationTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color,
                Color.alphaBlend(Colors.black.withValues(alpha: 0.20), color),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: Colors.white, size: 30),
                ),
                const SizedBox(height: 14),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Database status card
// ---------------------------------------------------------------------------

class _DatabaseStatusCard extends StatelessWidget {
  const _DatabaseStatusCard({required this.db});

  final AppDatabase db;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

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
                  Icon(Icons.error_outline, color: colors.error),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Datenbank-Fehler: ${snapshot.error}',
                      style: TextStyle(color: colors.error),
                    ),
                  ),
                ],
              );
            }

            final count = snapshot.data ?? 0;

            if (count == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Datenbank verbunden — noch keine Produkte',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Importiere eine Excel-Stammdaten-Vorlage unter '
                    'Einstellungen → Stammdaten, um die App zu füllen.',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ],
              );
            }

            return Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 12),
                Text(
                  'Datenbank verbunden — $count Produkte gespeichert',
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