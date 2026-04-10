import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';

// ---------------------------------------------------------------------------
// Aufträge-Übersicht: Alle offenen Aufträge nach Dringlichkeit
// ---------------------------------------------------------------------------

class TasksDetailScreen extends ConsumerStatefulWidget {
  const TasksDetailScreen({super.key});

  @override
  ConsumerState<TasksDetailScreen> createState() => _TasksDetailScreenState();
}

class _TasksDetailScreenState extends ConsumerState<TasksDetailScreen> {
  Abteilung? _filterAbt;
  String _filterStatus = 'offen'; // 'offen', 'alle', 'geplant', 'in_arbeit'
  String _search = '';

  /// Lädt alle offenen Tasks (nicht storniert, nicht fertig) und
  /// gruppiert sie nach Dringlichkeit.
  Future<_TaskOverview> _loadOverview(AppDatabase db) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endOfWeek = today.add(Duration(days: 7 - today.weekday));

    // Basis-Query: nicht gelöscht, nicht storniert
    var query = db.select(db.productionTasks)
      ..where((t) => t.deletedAt.isNull())
      ..where((t) => t.status.isNotIn(const ['storniert']));

    // Status-Filter
    if (_filterStatus == 'offen') {
      query = query..where((t) => t.status.isNotIn(const ['fertig']));
    } else if (_filterStatus == 'geplant') {
      query = query..where((t) => t.status.equals('geplant'));
    } else if (_filterStatus == 'in_arbeit') {
      query = query..where((t) => t.status.equals('in_arbeit'));
    }
    // 'alle' → keine weitere Einschränkung

    // Abteilungs-Filter
    if (_filterAbt != null) {
      query = query..where((t) => t.abteilung.equals(_filterAbt!.dbValue));
    }

    final tasks = await (query..orderBy([
          (t) => OrderingTerm.asc(t.datum),
          (t) => OrderingTerm.asc(t.startZeit),
        ])).get();

    // Produkte auflösen
    final productIds = tasks.map((t) => t.productId).toSet();
    final products = productIds.isEmpty
        ? <Product>[]
        : await (db.select(db.products)
              ..where((p) => p.id.isIn(productIds.toList())))
            .get();
    final productMap = {for (final p in products) p.id: p};

    // MHD-basiertes Abgangsdatum = Datum + haltbarkeitTage
    // Vorlaufzeit-Deadline = Datum (Task-Datum IST der geplante Produktionstag)

    final ueberfaellig = <_OrderItem>[];
    final heute = <_OrderItem>[];
    final dieseWoche = <_OrderItem>[];
    final spaeter = <_OrderItem>[];

    for (final task in tasks) {
      final product = productMap[task.productId];

      // Textsuche
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        final label = product != null
            ? '${product.artikelnummer} ${product.artikelbezeichnung}'
            : task.productId;
        final abtName = Abteilung.fromDbValue(task.abteilung).anzeigeName;
        if (!label.toLowerCase().contains(q) &&
            !abtName.toLowerCase().contains(q) &&
            !(task.notizen?.toLowerCase().contains(q) ?? false)) {
          continue;
        }
      }

      final item = _OrderItem(
        task: task,
        product: product,
        abteilung: Abteilung.fromDbValue(task.abteilung),
      );

      final taskDate = DateTime(
        task.datum.year,
        task.datum.month,
        task.datum.day,
      );

      if (taskDate.isBefore(today) && task.status != 'fertig') {
        ueberfaellig.add(item);
      } else if (taskDate == today) {
        heute.add(item);
      } else if (taskDate.isBefore(endOfWeek) || taskDate == endOfWeek) {
        dieseWoche.add(item);
      } else {
        spaeter.add(item);
      }
    }

    return _TaskOverview(
      ueberfaellig: ueberfaellig,
      heute: heute,
      dieseWoche: dieseWoche,
      spaeter: spaeter,
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Aufträge')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Suchfeld
          TextField(
            decoration: InputDecoration(
              hintText: 'Suche nach Artikel, Abteilung, Notiz…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _search = ''),
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              filled: true,
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
          const SizedBox(height: 12),

          // Status-Tabs
          _StatusFilterRow(
            selected: _filterStatus,
            onChanged: (v) => setState(() => _filterStatus = v),
          ),
          const SizedBox(height: 8),

          // Abteilungs-Chips
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              ChoiceChip(
                label: const Text('Alle Abt.'),
                selected: _filterAbt == null,
                onSelected: (_) => setState(() => _filterAbt = null),
              ),
              ...Abteilung.values.map(
                (a) => ChoiceChip(
                  label: Text(a.kurzcode),
                  selected: _filterAbt == a,
                  selectedColor: a.farbe.withValues(alpha: 0.15),
                  onSelected: (_) => setState(() => _filterAbt = a),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          FutureBuilder<_TaskOverview>(
            future: _loadOverview(db),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox(
                  height: 120,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return Center(child: Text('Fehler: ${snapshot.error}'));
              }

              final data = snapshot.data!;
              final total = data.ueberfaellig.length +
                  data.heute.length +
                  data.dieseWoche.length +
                  data.spaeter.length;
              final hasAny = total > 0;

              if (!hasAny) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 48,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Keine Aufträge für diese Filter.',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Zusammenfassungs-Leiste
                  Card(
                    color: theme.colorScheme.surfaceContainerLow,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _SummaryBadge(
                            label: 'Überfällig',
                            count: data.ueberfaellig.length,
                            color: Colors.red,
                          ),
                          _SummaryBadge(
                            label: 'Heute',
                            count: data.heute.length,
                            color: const Color(0xFFFB8C00),
                          ),
                          _SummaryBadge(
                            label: 'Woche',
                            count: data.dieseWoche.length,
                            color: const Color(0xFFFDD835),
                          ),
                          _SummaryBadge(
                            label: 'Später',
                            count: data.spaeter.length,
                            color: Colors.green,
                          ),
                          _SummaryBadge(
                            label: 'Gesamt',
                            count: total,
                            color: theme.colorScheme.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (data.ueberfaellig.isNotEmpty)
                    _DringlichkeitsSection(
                      titel: '🔴 Überfällig',
                      farbe: Colors.red,
                      items: data.ueberfaellig,
                    ),
                  if (data.heute.isNotEmpty)
                    _DringlichkeitsSection(
                      titel: '🟠 Heute',
                      farbe: const Color(0xFFFB8C00),
                      items: data.heute,
                    ),
                  if (data.dieseWoche.isNotEmpty)
                    _DringlichkeitsSection(
                      titel: '🟡 Diese Woche',
                      farbe: const Color(0xFFFDD835),
                      items: data.dieseWoche,
                    ),
                  if (data.spaeter.isNotEmpty)
                    _DringlichkeitsSection(
                      titel: '🟢 Später',
                      farbe: Colors.green,
                      items: data.spaeter,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Zusammenfassungs-Badge
// ---------------------------------------------------------------------------

class _SummaryBadge extends StatelessWidget {
  const _SummaryBadge({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$count',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: count > 0 ? color : Colors.grey,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Status-Filter-Leiste
// ---------------------------------------------------------------------------

class _StatusFilterRow extends StatelessWidget {
  const _StatusFilterRow({required this.selected, required this.onChanged});

  final String selected;
  final ValueChanged<String> onChanged;

  static const _options = [
    ('offen', 'Offen'),
    ('geplant', 'Geplant'),
    ('in_arbeit', 'In Arbeit'),
    ('alle', 'Alle'),
  ];

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: _options
          .map((o) => ButtonSegment(value: o.$1, label: Text(o.$2)))
          .toList(),
      selected: {selected},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

// ---------------------------------------------------------------------------
// Dringlichkeits-Sektion
// ---------------------------------------------------------------------------

class _DringlichkeitsSection extends StatelessWidget {
  const _DringlichkeitsSection({
    required this.titel,
    required this.farbe,
    required this.items,
  });

  final String titel;
  final Color farbe;
  final List<_OrderItem> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: farbe.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$titel (${items.length})',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: farbe.computeLuminance() > 0.5
                        ? Colors.black87
                        : farbe,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ...items.map((item) => _OrderCard(item: item)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Einzelne Auftrags-Karte
// ---------------------------------------------------------------------------

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.item});

  final _OrderItem item;

  static const _dayNames = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
  static const _monthNames = [
    'Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun',
    'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez',
  ];

  String _formatDate(DateTime d) =>
      '${_dayNames[d.weekday - 1]}, ${d.day}. ${_monthNames[d.month - 1]}';

  String _formatDuration(double minutes) {
    final h = minutes ~/ 60;
    final m = (minutes % 60).round();
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final produktLabel = item.product != null
        ? '${item.product!.artikelnummer} · ${item.product!.artikelbezeichnung}'
        : item.task.productId;

    // Abgangsdatum: Task-Datum + MHD-Tage (wenn vorhanden)
    String? abgangLabel;
    if (item.product?.haltbarkeitTage != null) {
      final abgang = item.task.datum.add(
        Duration(days: item.product!.haltbarkeitTage!),
      );
      abgangLabel = 'MHD ${_formatDate(abgang)}';
    }

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => context.pushNamed(
        'taskDetail',
        pathParameters: {'taskId': item.task.id},
      ),
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Zeile 1: Abteilung + Produkt + Status
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: item.abteilung.farbe,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      item.abteilung.kurzcode,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      produktLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _StatusDot(status: item.task.status),
                ],
              ),
              const SizedBox(height: 8),

              // Zeile 2: Kompakte Detail-Zeile
              DefaultTextStyle(
                style: TextStyle(
                  fontSize: 12,
                  color: colors.onSurfaceVariant,
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, size: 13, color: colors.onSurfaceVariant),
                    const SizedBox(width: 3),
                    Text(_formatDate(item.task.datum)),
                    const SizedBox(width: 12),
                    Icon(Icons.scale, size: 13, color: colors.onSurfaceVariant),
                    const SizedBox(width: 3),
                    Text('${item.task.mengeKg.toStringAsFixed(0)} kg'),
                    const SizedBox(width: 12),
                    Icon(Icons.schedule, size: 13, color: colors.onSurfaceVariant),
                    const SizedBox(width: 3),
                    Text(_formatDuration(item.task.geplanteDauerMinuten)),
                    const SizedBox(width: 12),
                    Icon(Icons.people, size: 13, color: colors.onSurfaceVariant),
                    const SizedBox(width: 3),
                    Text('${item.task.geplanteMitarbeiter}'),
                    if (item.task.startZeit != null) ...[
                      const SizedBox(width: 12),
                      Icon(Icons.access_time, size: 13, color: colors.onSurfaceVariant),
                      const SizedBox(width: 3),
                      Text(item.task.startZeit!),
                    ],
                  ],
                ),
              ),

              // MHD-Zeile (falls vorhanden)
              if (abgangLabel != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Icon(Icons.event_available, size: 13, color: colors.onSurfaceVariant),
                      const SizedBox(width: 3),
                      Text(
                        abgangLabel,
                        style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),

              // Notizen
              if (item.task.notizen != null &&
                  item.task.notizen!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    item.task.notizen!,
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: colors.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status-Chip
// ---------------------------------------------------------------------------

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final String status;

  String get _label {
    switch (status) {
      case 'in_arbeit':
        return 'In Arbeit';
      case 'fertig':
        return 'Fertig';
      case 'storniert':
        return 'Storniert';
      default:
        return 'Geplant';
    }
  }

  Color get _color {
    switch (status) {
      case 'in_arbeit':
        return const Color(0xFF0288D1);
      case 'fertig':
        return const Color(0xFF2E7D32);
      case 'storniert':
        return Colors.red;
      default:
        return const Color(0xFFFB8C00);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _label,
        style: TextStyle(color: _color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Datenklassen
// ---------------------------------------------------------------------------

class _OrderItem {
  _OrderItem({
    required this.task,
    required this.product,
    required this.abteilung,
  });

  final ProductionTask task;
  final Product? product;
  final Abteilung abteilung;
}

class _TaskOverview {
  const _TaskOverview({
    required this.ueberfaellig,
    required this.heute,
    required this.dieseWoche,
    required this.spaeter,
  });

  final List<_OrderItem> ueberfaellig;
  final List<_OrderItem> heute;
  final List<_OrderItem> dieseWoche;
  final List<_OrderItem> spaeter;
}
