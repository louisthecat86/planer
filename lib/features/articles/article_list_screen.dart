import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/constants/machines.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';
import 'article_info_editor_dialog.dart';

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

  /// Legt einen neuen Artikel an (Artikelnummer, Bezeichnung, Gruppe)
  /// und öffnet direkt die Detailansicht zum Pflegen der Prozessdaten.
  Future<void> _neuerArtikel(BuildContext context) async {
    final res = await showDialog<({String nummer, String bez, String? gruppe})>(
      context: context,
      builder: (_) => const _NeuerArtikelDialog(),
    );
    if (res == null) return;

    final db = ref.read(databaseProvider);

    // Artikelnummer muss unter den AKTIVEN eindeutig sein — sie ist der
    // Schlüssel zur Excel. Ein früher gelöschter Artikel mit derselben
    // Nummer wird reaktiviert statt doppelt angelegt.
    final gleicheNr = await (db.select(db.products)
          ..where((p) => p.artikelnummer.equals(res.nummer)))
        .get();
    final aktiverKonflikt =
        gleicheNr.where((p) => p.deletedAt == null).toList();
    if (aktiverKonflikt.isNotEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Artikelnummer ${res.nummer} existiert bereits '
            '(${aktiverKonflikt.first.artikelbezeichnung}).',
          ),
        ),
      );
      return;
    }

    // Wurde die Nummer früher gelöscht? Dann reaktivieren (die unique-
    // Bedingung auf artikelnummer verböte sonst einen zweiten Insert).
    final geloescht =
        gleicheNr.where((p) => p.deletedAt != null).toList();
    final String id;
    if (geloescht.isNotEmpty) {
      id = geloescht.first.id;
      await (db.update(db.products)..where((x) => x.id.equals(id))).write(
        ProductsCompanion(
          artikelbezeichnung: Value(res.bez),
          produktgruppe: Value(res.gruppe),
          deletedAt: const Value(null),
          updatedAt: Value(DateTime.now()),
        ),
      );
    } else {
      id = const Uuid().v4();
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: id,
              artikelnummer: res.nummer,
              artikelbezeichnung: res.bez,
              produktgruppe: Value(res.gruppe),
            ),
          );
    }

    ref
        .read(autoBackupTriggerProvider)
        .fireDebounced(reason: 'Artikel angelegt');
    ref.invalidate(articlesProvider);

    if (!context.mounted) return;
    context.pushNamed(
      'articleDetail',
      pathParameters: {'productId': id},
    );
  }

  /// Löscht einen Artikel per Soft-Delete (deletedAt) — samt seiner
  /// Schritte und Parameter. Der Artikel verschwindet aus der App;
  /// in der Excel bleibt das Sheet bestehen (dort ggf. von Hand löschen,
  /// sonst kommt er beim nächsten Import zurück).
  Future<void> _loescheArtikel(BuildContext context, _ArticleInfo info) async {
    final p = info.product;
    final bestaetigt = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Artikel löschen'),
        content: Text(
          '„${p.artikelbezeichnung}" (Nr. ${p.artikelnummer}) wirklich '
          'löschen? Die Prozessdaten des Artikels werden entfernt.\n\n'
          'Hinweis: In einer bereits exportierten Excel bleibt das '
          'Artikel-Blatt bestehen und muss dort separat gelöscht werden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (bestaetigt != true) return;

    final db = ref.read(databaseProvider);
    final jetzt = DateTime.now();

    // Schritte des Artikels ermitteln, um deren Parameter mitzulöschen.
    final steps = await (db.select(db.productSteps)
          ..where((s) => s.productId.equals(p.id)))
        .get();
    for (final s in steps) {
      await (db.update(db.productStepParameters)
            ..where((pp) => pp.stepId.equals(s.id)))
          .write(ProductStepParametersCompanion(deletedAt: Value(jetzt)));
    }
    await (db.update(db.productSteps)
          ..where((s) => s.productId.equals(p.id)))
        .write(ProductStepsCompanion(deletedAt: Value(jetzt)));
    await (db.update(db.products)..where((x) => x.id.equals(p.id)))
        .write(ProductsCompanion(deletedAt: Value(jetzt)));

    ref
        .read(autoBackupTriggerProvider)
        .fireDebounced(reason: 'Artikel gelöscht');
    ref.invalidate(articlesProvider);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('„${p.artikelbezeichnung}" gelöscht.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final articlesAsync = ref.watch(articlesProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _neuerArtikel(context),
        icon: const Icon(Icons.add),
        label: const Text('Neuer Artikel'),
      ),
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
                  itemBuilder: (_, i) => _ArticleTile(
                    info: filtered[i],
                    onDelete: () => _loescheArtikel(context, filtered[i]),
                  ),
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
  const _ArticleTile({required this.info, required this.onDelete});

  final _ArticleInfo info;
  final VoidCallback onDelete;

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

              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                onSelected: (v) {
                  if (v == 'oeffnen') {
                    context.pushNamed(
                      'articleDetail',
                      pathParameters: {'productId': p.id},
                    );
                  } else if (v == 'loeschen') {
                    onDelete();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'oeffnen',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: 10),
                        Text('Öffnen / Bearbeiten'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'loeschen',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline,
                            size: 18, color: Colors.red),
                        SizedBox(width: 10),
                        Text('Löschen',
                            style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialog: neuen Artikel anlegen
// ---------------------------------------------------------------------------

class _NeuerArtikelDialog extends StatefulWidget {
  const _NeuerArtikelDialog();

  @override
  State<_NeuerArtikelDialog> createState() => _NeuerArtikelDialogState();
}

class _NeuerArtikelDialogState extends State<_NeuerArtikelDialog> {
  final _nummer = TextEditingController();
  final _bez = TextEditingController();
  String? _gruppe;

  @override
  void dispose() {
    _nummer.dispose();
    _bez.dispose();
    super.dispose();
  }

  void _ok() {
    final nummer = _nummer.text.trim();
    final bez = _bez.text.trim();
    if (nummer.isEmpty || bez.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte Artikelnummer und Bezeichnung angeben.'),
        ),
      );
      return;
    }
    Navigator.of(context).pop((nummer: nummer, bez: bez, gruppe: _gruppe));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Neuen Artikel anlegen'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nummer,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Artikelnummer',
                hintText: 'z.B. 12345',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bez,
              decoration: const InputDecoration(
                labelText: 'Bezeichnung',
                hintText: 'z.B. Schweinefrikadelle 60g, gebraten',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _ok(),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _gruppe,
              decoration: const InputDecoration(
                labelText: 'Produktgruppe (optional)',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final g in kProduktgruppen)
                  DropdownMenuItem(value: g.dbValue, child: Text(g.label)),
              ],
              onChanged: (v) => setState(() => _gruppe = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(onPressed: _ok, child: const Text('Anlegen')),
      ],
    );
  }
}
