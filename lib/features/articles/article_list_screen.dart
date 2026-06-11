import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/constants/machines.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Alle aktiven Produkte mit Schritt-Anzahl.
///
/// Bewusst nur ZWEI Abfragen (Produkte + alle Schritte, im Speicher
/// gruppiert) statt einer Abfrage pro Artikel — bei ~60 Artikeln macht
/// das den Aufbau der Liste spürbar flüssiger.
final articlesProvider = FutureProvider<List<_ArticleInfo>>((ref) async {
  final db = ref.watch(databaseProvider);

  final products = await (db.select(db.products)
        ..where((p) => p.deletedAt.isNull())
        ..orderBy([(p) => OrderingTerm.asc(p.artikelbezeichnung)]))
      .get();

  final steps = await (db.select(db.productSteps)
        ..where((s) => s.deletedAt.isNull())
        ..orderBy([(s) => OrderingTerm.asc(s.reihenfolge)]))
      .get();

  final byProduct = <String, List<ProductStep>>{};
  for (final s in steps) {
    byProduct.putIfAbsent(s.productId, () => []).add(s);
  }

  return [
    for (final p in products)
      _ArticleInfo(product: p, steps: byProduct[p.id] ?? const []),
  ];
});

class _ArticleInfo {
  const _ArticleInfo({required this.product, required this.steps});
  final Product product;
  final List<ProductStep> steps;
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class ArticleListScreen extends ConsumerStatefulWidget {
  const ArticleListScreen({super.key});

  @override
  ConsumerState<ArticleListScreen> createState() => _ArticleListScreenState();
}

class _ArticleListScreenState extends ConsumerState<ArticleListScreen> {
  String _search = '';
  _SortField _sortField = _SortField.bezeichnung;
  bool _sortAsc = true;

  List<_ArticleInfo> _filtered(List<_ArticleInfo> all) {
    var list = all;

    // Suche
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((a) {
        final p = a.product;
        return p.artikelbezeichnung.toLowerCase().contains(q) ||
            p.artikelnummer.toLowerCase().contains(q) ||
            (p.beschreibung?.toLowerCase().contains(q) ?? false) ||
            (p.planungsgruppe?.toLowerCase().contains(q) ?? false);
      }).toList();
    }

    // Sortierung
    list.sort((a, b) {
      int cmp;
      switch (_sortField) {
        case _SortField.bezeichnung:
          cmp = a.product.artikelbezeichnung
              .compareTo(b.product.artikelbezeichnung);
        case _SortField.artikelnr:
          cmp = a.product.artikelnummer.compareTo(b.product.artikelnummer);
        case _SortField.schritte:
          cmp = a.steps.length.compareTo(b.steps.length);
      }
      return _sortAsc ? cmp : -cmp;
    });

    return list;
  }

  void _toggleSort(_SortField field) {
    setState(() {
      if (_sortField == field) {
        _sortAsc = !_sortAsc;
      } else {
        _sortField = field;
        _sortAsc = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
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
        data: (articles) =>
            articles.isEmpty ? const _EmptyState() : _buildBody(articles),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
      ),
    );
  }

  Widget _buildBody(List<_ArticleInfo> all) {
    final filtered = _filtered(all);

    return Column(
      children: [
        // --- Suchleiste (Stil kommt zentral aus dem Theme) ---
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Suche nach Name, Artikelnr, Planungsgruppe…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _search = ''),
                    )
                  : null,
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),

        // --- Filter-Chips + Sortierung ---
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              // Ergebnis-Zähler links, Sortierung rechts
              Expanded(
                child: Text(
                  '${filtered.length} von ${all.length} Artikel',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),

              // Sortier-Menü
              PopupMenuButton<_SortField>(
                icon: const Icon(Icons.sort),
                tooltip: 'Sortierung',
                onSelected: _toggleSort,
                itemBuilder: (_) => _SortField.values
                    .map(
                      (f) => PopupMenuItem(
                        value: f,
                        child: Row(
                          children: [
                            if (_sortField == f)
                              Icon(
                                _sortAsc
                                    ? Icons.arrow_upward
                                    : Icons.arrow_downward,
                                size: 16,
                              )
                            else
                              const SizedBox(width: 16),
                            const SizedBox(width: 8),
                            Text(f.label),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        // --- Artikel-Liste ---
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 8),
                      Text(
                        'Keine Treffer',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _ArticleTile(info: filtered[i]),
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sort-Optionen
// ---------------------------------------------------------------------------

enum _SortField {
  bezeichnung('Bezeichnung'),
  artikelnr('Artikelnr'),
  schritte('Schritte');

  const _SortField(this.label);
  final String label;
}

// ---------------------------------------------------------------------------
// Empty State
// ---------------------------------------------------------------------------

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

    // Abteilungen als farbige Kürzel — jede Abteilung nur einmal,
    // in Reihenfolge ihres ersten Auftretens im Prozess.
    final abteilungen = <Abteilung>[];
    for (final s in steps) {
      final a = Abteilung.fromDbValue(s.abteilung);
      if (!abteilungen.contains(a)) abteilungen.add(a);
    }

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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              // Planungsgruppe-Badge
              if (p.planungsgruppe != null)
                Container(
                  width: 56,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    p.planungsgruppe!.length > 6
                        ? p.planungsgruppe!.substring(0, 6)
                        : p.planungsgruppe!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              if (p.planungsgruppe != null) const SizedBox(width: 12),

              // Artikel-Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.artikelbezeichnung,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Art.-Nr.: ${p.artikelnummer}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Abteilungs-Kürzel + Metadaten
                    Row(
                      children: [
                        ...abteilungen.map(
                          (a) => Container(
                            width: 22,
                            height: 22,
                            margin: const EdgeInsets.only(right: 3),
                            decoration: BoxDecoration(
                              color: Color(a.farbwert),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              a.kurzcode,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${steps.length} Schritte',
                          style: theme.textTheme.bodySmall,
                        ),
                        if (machineCount > 0) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.settings,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '$machineCount',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                        if (p.gebindeGroesseKg != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            '${p.gebindeGroesseKg!.toStringAsFixed(1)} kg',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              Icon(
                Icons.chevron_right,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}