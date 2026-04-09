import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/constants/bratstrasse_machines.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Alle aktiven Produkte mit Schritt-Anzahl.
final articlesProvider = FutureProvider<List<_ArticleInfo>>((ref) async {
  final db = ref.watch(databaseProvider);

  final products = await (db.select(db.products)
        ..where((p) => p.deletedAt.isNull())
        ..orderBy([(p) => OrderingTerm.asc(p.artikelbezeichnung)]))
      .get();

  final result = <_ArticleInfo>[];
  for (final p in products) {
    final steps = await (db.select(db.productSteps)
          ..where((s) => s.productId.equals(p.id))
          ..where((s) => s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm.asc(s.reihenfolge)]))
        .get();
    result.add(_ArticleInfo(product: p, steps: steps));
  }
  return result;
});

class _ArticleInfo {
  const _ArticleInfo({required this.product, required this.steps});
  final Product product;
  final List<ProductStep> steps;
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class ArticleListScreen extends ConsumerWidget {
  const ArticleListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final articlesAsync = ref.watch(articlesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Artikel-Stammdaten'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(articlesProvider),
            tooltip: 'Aktualisieren',
          ),
        ],
      ),
      body: articlesAsync.when(
        data: (articles) => articles.isEmpty
            ? const _EmptyState()
            : _ArticlesList(articles: articles),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Noch keine Artikel vorhanden',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Importiere Stammdaten über den Excel-Import',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[500],
                ),
          ),
        ],
      ),
    );
  }
}

class _ArticlesList extends StatelessWidget {
  const _ArticlesList({required this.articles});

  final List<_ArticleInfo> articles;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: articles.length,
      itemBuilder: (context, index) =>
          _ArticleTile(info: articles[index]),
    );
  }
}

// ---------------------------------------------------------------------------
// Einzelne Artikel-Kachel
// ---------------------------------------------------------------------------

class _ArticleTile extends StatelessWidget {
  const _ArticleTile({required this.info});

  final _ArticleInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = info.product;
    final steps = info.steps;

    // Abteilungen als farbige Dots
    final abteilungen = steps
        .map((s) {
          try {
            return Abteilung.fromDbValue(s.abteilung);
          } catch (_) {
            return null;
          }
        })
        .whereType<Abteilung>()
        .toList();

    // Maschinen-Zähler
    final machineCount = steps.fold<int>(
      0,
      (sum, s) => sum + enabledMachines(s.maschinenEinstellungenJson).length,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.pushNamed(
          'articleDetail',
          pathParameters: {'productId': p.id},
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Artikel-Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name + Artikelnummer
                    Text(
                      p.artikelbezeichnung,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Art.-Nr.: ${p.artikelnummer}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),

                    // Abteilungs-Dots + Schritt-Anzahl
                    Row(
                      children: [
                        ...abteilungen.map((a) => Container(
                              width: 24,
                              height: 24,
                              margin: const EdgeInsets.only(right: 4),
                              decoration: BoxDecoration(
                                color: Color(a.farbwert),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                a.kurzcode,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )),
                        const SizedBox(width: 8),
                        Text(
                          '${steps.length} Schritte',
                          style: theme.textTheme.bodySmall,
                        ),
                        if (machineCount > 0) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.settings, size: 14, color: theme.colorScheme.onSurfaceVariant,),
                          const SizedBox(width: 2),
                          Text(
                            '$machineCount Maschinen',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
