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

/// Startbildschirm:
/// Kopf mit Datum + Kennzahlen, darunter zwei Ebenen — oben der tägliche
/// Arbeitsablauf (Bedarf → Planung → Erfassung → Historie) als große
/// farbige Kacheln, darunter „Stammdaten und Verwaltung" (Artikel,
/// Einstellungen) als kleinere, ruhigere Kacheln.
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
        final gesamt = constraints.maxWidth;
        const spacing = 12.0;

        // Umbruch NICHT an einer festen Pixelgrenze festmachen (das bricht
        // beim Skalieren), sondern über eine Mindestbreite je Kachel: passen
        // vier nebeneinander, gibt es vier Spalten — sonst zwei, sonst eine.
        // So klappt der Umbruch bei jeder Zoomstufe sauber.
        const minAblauf = 200.0;
        int ablaufSpalten = (gesamt / (minAblauf + spacing)).floor();
        ablaufSpalten = ablaufSpalten.clamp(1, 4);
        final ablaufBreite =
            (gesamt - spacing * (ablaufSpalten - 1)) / ablaufSpalten;
        final breit = ablaufSpalten >= 3;

        // ── Arbeitsablauf: die täglich benutzten Bereiche, in der
        //    Reihenfolge des Arbeitstages. Groß und farbig. ──
        final ablauf = [
          _NavigationTile(
            icon: Icons.playlist_add_check_rounded,
            label: 'Bedarf',
            subtitle: 'Was produziert werden muss',
            onTap: () => context.pushNamed('bedarf'),
          ),
          _NavigationTile(
            icon: Icons.calendar_view_week_rounded,
            label: 'Planung',
            subtitle: 'Woche im Board einplanen',
            onTap: () => context.pushNamed('board'),
          ),
          _NavigationTile(
            icon: Icons.fact_check_rounded,
            label: 'Produktionserfassung',
            subtitle: 'Ist-Daten der Woche',
            onTap: () => context.pushNamed('erfassung'),
          ),
          _NavigationTile(
            icon: Icons.history_rounded,
            label: 'Wochen-Historie',
            subtitle: 'Rückblick und Kennzahlen',
            onTap: () => context.pushNamed('wochenHistorie'),
          ),
          // Artikel gehört zum täglichen Arbeiten, nicht in die Verwaltung —
          // die Stammdaten sind die Grundlage jeder Planung.
          _NavigationTile(
            icon: Icons.inventory_2_rounded,
            label: 'Artikel',
            subtitle: 'Abläufe, Maschinen, Zeiten',
            onTap: () => context.pushNamed('articles'),
          ),
        ];

        // ── Verwaltung: seltener gebraucht, bewusst kleiner und ruhiger. ──
        final verwaltung = [
          _KompakteKachel(
            icon: Icons.settings_rounded,
            label: 'Einstellungen',
            subtitle: 'Excel, Backup, Darstellung',
            onTap: () => context.pushNamed('settings'),
          ),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _AbschnittTitel('Arbeitsablauf'),
            const SizedBox(height: 10),
            Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: ablauf
                  .map(
                    (tile) => SizedBox(
                      width: ablaufBreite,
                      height: 158,
                      child: tile,
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 24),
            const _AbschnittTitel('Stammdaten und Verwaltung'),
            const SizedBox(height: 10),
            // Verwaltung schmaler halten, damit der Unterschied zum Ablauf
            // sichtbar ist: auf breiten Schirmen nur gut halbe Breite.
            SizedBox(
              width: breit ? gesamt * 0.6 : gesamt,
              child: Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: verwaltung
                    .map(
                      (tile) => SizedBox(
                        width: (((breit ? gesamt * 0.6 : gesamt) - spacing) / 2)
                            .clamp(150.0, double.infinity),
                        child: tile,
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          datum,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
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

// ---------------------------------------------------------------------------
// Navigation tile
// ---------------------------------------------------------------------------

/// Große Kachel im Navision-Stil: kantig, flach, eine Akzentfarbe.
///
/// Vorher waren es bunte Farbverläufe mit runden Ecken. NAV arbeitet
/// stattdessen mit ruhigen Flächen, dünnen Kanten und einem einzigen Blau —
/// die Unterscheidung leisten Symbol und Beschriftung, nicht die Farbe.
class _NavigationTile extends StatelessWidget {
  const _NavigationTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final akzent = theme.colorScheme.primary;
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(3),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: theme.dividerColor),
            // Schmale Akzentkante links — das NAV-Muster für aktive Bereiche.
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [akzent, akzent, Colors.transparent],
              stops: const [0, 0.012, 0.012],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: akzent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Icon(icon, color: akzent, size: 24),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: akzent,
                ),
              ),
              const SizedBox(height: 2),
              Expanded(
                child: Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomRight,
                child: Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kleine Abschnitts-Überschrift, die die Kachel-Ebenen sichtbar trennt.
class _AbschnittTitel extends StatelessWidget {
  const _AbschnittTitel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}

/// Kompakte, ruhige Kachel für die Verwaltung — bewusst kleiner und
/// dezenter als die farbigen Ablauf-Kacheln: dunkle Fläche, Icon links,
/// eine Zeile Text daneben. So entsteht die Hierarchie zwischen „hier wird
/// gearbeitet" und „hier wird eingerichtet".
class _KompakteKachel extends StatelessWidget {
  const _KompakteKachel({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.25),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Icon(
                icon,
                color: theme.colorScheme.onSurfaceVariant,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant
                    .withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
