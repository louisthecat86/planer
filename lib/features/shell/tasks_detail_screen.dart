import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import 'home_screen.dart';

class TasksDetailScreen extends ConsumerStatefulWidget {
  const TasksDetailScreen({super.key});

  @override
  ConsumerState<TasksDetailScreen> createState() => _TasksDetailScreenState();
}

class _TasksDetailScreenState extends ConsumerState<TasksDetailScreen> {
  Abteilung? _selectedAbteilung;

  Future<List<_TaskItem>> _loadTasks(AppDatabase db, DateTime selectedDate) async {
    final startOfDay = selectedDate;
    final startOfNextDay = selectedDate.add(const Duration(days: 1));

    final query = db.select(db.productionTasks)
      ..where((tbl) => tbl.deletedAt.isNull())
      ..where((tbl) => tbl.datum.isBiggerOrEqualValue(startOfDay))
      ..where((tbl) => tbl.datum.isSmallerThanValue(startOfNextDay))
      ..where((tbl) => tbl.status.isNotIn(const ['storniert']));

    final tasks = await query.get();
    final productIds = tasks.map((task) => task.productId).toSet();
    final products = await (db.select(db.products)
          ..where((tbl) => tbl.id.isIn(productIds.toList())))
        .get();
    final productMap = {for (final product in products) product.id: product};

    return tasks.map((task) {
      final product = productMap[task.productId];
      return _TaskItem(
        task: task,
        productLabel: product != null
            ? '${product.artikelnummer} · ${product.artikelbezeichnung}'
            : task.productId,
        abteilung: Abteilung.fromDbValue(task.abteilung),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    final selectedDate = ref.watch(selectedDateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Aufträge')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _DateNavigationBar(),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Alle'),
                selected: _selectedAbteilung == null,
                onSelected: (_) => setState(() => _selectedAbteilung = null),
              ),
              ...Abteilung.values.map(
                (a) => ChoiceChip(
                  label: Text(a.kurzcode),
                  selected: _selectedAbteilung == a,
                  selectedColor: a.farbe.withValues(alpha: 0.15),
                  onSelected: (_) => setState(() => _selectedAbteilung = a),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<_TaskItem>>(
            future: _loadTasks(db, selectedDate),
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

              final tasks = snapshot.data
                      ?.where((item) =>
                          _selectedAbteilung == null ||
                          item.abteilung == _selectedAbteilung,)
                      .toList() ??
                  [];

              if (tasks.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                            Icons.event_busy,
                            size: 48,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                            'Keine Aufträge für diesen Tag.',
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return Column(
                children: tasks.map((item) => _TaskCard(item: item)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DateNavigationBar extends ConsumerWidget {
  const _DateNavigationBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(selectedDateProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isToday = selectedDate == today;

    const dayNames = [
      'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag',
      'Freitag', 'Samstag', 'Sonntag',
    ];
    const monthNames = [
      'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
      'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
    ];

    final dayName = dayNames[selectedDate.weekday - 1];
    final label =
        '$dayName, ${selectedDate.day}. ${monthNames[selectedDate.month - 1]} ${selectedDate.year}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => ref.read(selectedDateProvider.notifier).state =
                  selectedDate.subtract(const Duration(days: 1)),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2024),
                    lastDate: DateTime(2030),
                  );
                  if (picked != null) {
                    ref.read(selectedDateProvider.notifier).state =
                        DateTime(picked.year, picked.month, picked.day);
                  }
                },
                child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            if (!isToday)
              TextButton(
                onPressed: () =>
                    ref.read(selectedDateProvider.notifier).state = today,
                child: const Text('Heute'),
              ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => ref.read(selectedDateProvider.notifier).state =
                  selectedDate.add(const Duration(days: 1)),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskItem {
  _TaskItem({
    required this.task,
    required this.productLabel,
    required this.abteilung,
  });

  final ProductionTask task;
  final String productLabel;
  final Abteilung abteilung;

  String get durationLabel {
    final h = task.geplanteDauerMinuten ~/ 60;
    final m = (task.geplanteDauerMinuten % 60).round();
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }

  String get statusLabel {
    switch (task.status) {
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

  Color get statusColor {
    switch (task.status) {
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
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.item});

  final _TaskItem item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => context.pushNamed(
        'taskDetail',
        pathParameters: {'taskId': item.task.id},
      ),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: item.abteilung.farbe,
                    child: Text(
                        item.abteilung.kurzcode,
                        style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                        item.productLabel,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Chip(
                    label: Text(item.statusLabel),
                    backgroundColor: item.statusColor.withValues(alpha: 0.14),
                    labelStyle: TextStyle(color: item.statusColor),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  _DetailChip(icon: Icons.schedule, label: item.durationLabel),
                  _DetailChip(
                      icon: Icons.people,
                      label: '${item.task.geplanteMitarbeiter} MA',
                  ),
                  _DetailChip(
                      icon: Icons.scale,
                      label: '${item.task.mengeKg.toStringAsFixed(0)} kg',
                  ),
                  if (item.task.startZeit != null)
                    _DetailChip(
                        icon: Icons.access_time, label: item.task.startZeit!,
                    ),
                ],
              ),
              if (item.task.notizen != null && item.task.notizen!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                      item.task.notizen!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

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
    );
  }
}
