import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/database_provider.dart';

/// Ausgewähltes Datum. Wird von anderen Screens (Board) genutzt und bleibt
/// daher als gemeinsamer Zustand erhalten, auch wenn das Home es selbst
/// nicht mehr anzeigt.
final selectedDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

/// Anzahl aktiver Artikel (für die Kennzahl im Kopfbereich).
final _artikelAnzahlProvider = FutureProvider<int>((ref) async {
  final db = ref.watch(databaseProvider);
  final rows = await (db.select(db.products)
        ..where((p) => p.deletedAt.isNull()))
      .get();
  return rows.length;
});

/// Anzahl der für heute geplanten Aufgaben (für die Kennzahl im Kopf).
final _heutigeAufgabenProvider = FutureProvider<int>((ref) async {
  final db = ref.watch(databaseProvider);
  final jetzt = DateTime.now();
  final start = DateTime(jetzt.year, jetzt.month, jetzt.day);
  final ende = start.add(const Duration(days: 1));
  final rows = await (db.select(db.productionTasks)
        ..where((t) => t.deletedAt.isNull())
        ..where((t) => t.datum.isBiggerOrEqualValue(start))
        ..where((t) => t.datum.isSmallerThanValue(ende)))
      .get();
  return rows.length;
});

/// Startbildschirm:
/// Kopf mit Datum + Kennzahlen, darunter die vier Bereichs-Kacheln.
///
/// Stammdaten (Excel-Import/-Export, Backup) und die Kapazität liegen
/// unter „Einstellungen".
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Produktion Planer')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _KopfBereich(),
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
            icon: Icons.playlist_add_check_rounded,
            label: 'Bedarf',
            subtitle: 'Was produziert werden muss — Basis der Planung',
            color: const Color(0xFF6A1B9A),
            onTap: () => context.pushNamed('bedarf'),
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
              .map(
                (tile) => SizedBox(
                  width: tileWidth,
                  height: 158,
                  child: tile,
                ),
              )
              .toList(),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Kopfbereich: Datum + Kennzahlen (ersetzt die technische Status-Karte)
// ---------------------------------------------------------------------------

const _kWochentage = [
  'Montag',
  'Dienstag',
  'Mittwoch',
  'Donnerstag',
  'Freitag',
  'Samstag',
  'Sonntag',
];

const _kMonate = [
  'Januar',
  'Februar',
  'März',
  'April',
  'Mai',
  'Juni',
  'Juli',
  'August',
  'September',
  'Oktober',
  'November',
  'Dezember',
];

class _KopfBereich extends ConsumerWidget {
  const _KopfBereich();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final artikel = ref.watch(_artikelAnzahlProvider);
    final aufgaben = ref.watch(_heutigeAufgabenProvider);

    final heute = DateTime.now();
    final datum = '${_kWochentage[heute.weekday - 1]}, '
        '${heute.day}. ${_kMonate[heute.month - 1]} ${heute.year}';

    // Datenbank-Fehler weiterhin deutlich anzeigen
    final fehler = artikel.hasError ? artikel.error : null;
    if (fehler != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, color: theme.colorScheme.error),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Datenbank-Fehler: $fehler',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final artikelAnzahl = artikel.valueOrNull;
    final aufgabenAnzahl = aufgaben.valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          datum,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _StatChip(
              icon: Icons.inventory_2_outlined,
              label: 'Artikel',
              wert: artikelAnzahl?.toString() ?? '…',
            ),
            const SizedBox(width: 8),
            _StatChip(
              icon: Icons.task_alt,
              label: 'Aufgaben heute',
              wert: aufgabenAnzahl?.toString() ?? '…',
            ),
          ],
        ),
        // Erste-Schritte-Hinweis nur, wenn noch keine Artikel da sind
        if (artikelAnzahl == 0) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Noch keine Artikel vorhanden. Importiere eine '
                      'Excel-Stammdaten-Vorlage unter Einstellungen → '
                      'Stammdaten, um die App zu füllen.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Kleine Kennzahl-Pille im Kopfbereich.
class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.wert,
  });

  final IconData icon;
  final String label;
  final String wert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            wert,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
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
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: Colors.white, size: 28),
                ),
                const SizedBox(height: 10),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                Expanded(
                  child: Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: Colors.white.withValues(alpha: 0.7),
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
