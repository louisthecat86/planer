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
              final hasAny = data.ueberfaellig.isNotEmpty ||
                  data.heute.isNotEmpty ||
                  data.dieseWoche.isNotEmpty ||
                  data.spaeter.isNotEmpty;

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
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Zeile 1: Abteilung + Produkt + Status
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: item.abteilung.farbe,
                    child: Text(
                      item.abteilung.kurzcode,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      produktLabel,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _StatusChip(status: item.task.status),
                ],
              ),
              const SizedBox(height: 8),

              // Zeile 2: Details
              Wrap(
                spacing: 10,
                runSpacing: 6,
                children: [
                  _DetailChip(
                    icon: Icons.calendar_today,
                    label: _formatDate(item.task.datum),
                  ),
                  _DetailChip(
                    icon: Icons.scale,
                    label: '${item.task.mengeKg.toStringAsFixed(0)} kg',
                  ),
                  _DetailChip(
                    icon: Icons.schedule,
                    label: _formatDuration(item.task.geplanteDauerMinuten),
                  ),
                  _DetailChip(
                    icon: Icons.people,
                    label: '${item.task.geplanteMitarbeiter} MA',
                  ),
                  if (item.task.startZeit != null)
                    _DetailChip(
                      icon: Icons.access_time,
                      label: item.task.startZeit!,
                    ),
                  if (abgangLabel != null)
                    _DetailChip(
                      icon: Icons.event_available,
                      label: abgangLabel,
                    ),
                ],
              ),

              // Notizen
              if (item.task.notizen != null &&
                  item.task.notizen!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    item.task.notizen!,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                    maxLines: 2,
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

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
    return Chip(
      label: Text(_label, style: TextStyle(color: _color, fontSize: 12)),
      backgroundColor: _color.withValues(alpha: 0.12),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}

// ---------------------------------------------------------------------------
// Detail-Chip
// ---------------------------------------------------------------------------

class _DetailChip extends StatelessWidget {
  const _DetailChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(icon, size: 16, color: colors.onSurfaceVariant),
      label: Text(label),
      backgroundColor: colors.surfaceContainerLow,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
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
