import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/providers/department_capacity_provider.dart';
import 'home_screen.dart';

class CapacityDetailScreen extends ConsumerWidget {
  const CapacityDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    final capacityState = ref.watch(departmentCapacityNotifierProvider);
    final selectedDate = ref.watch(selectedDateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Abteilungs-Kapazität')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _DateNavigationBar(),
          const SizedBox(height: 16),
          capacityState.when(
            data: (capacities) => _CapacityList(
              db: db,
              capacities: capacities,
              selectedDate: selectedDate,
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('Fehler: $error')),
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
              tooltip: 'Vorheriger Tag',
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
              tooltip: 'Nächster Tag',
            ),
          ],
        ),
      ),
    );
  }
}

class _CapacityList extends StatelessWidget {
  const _CapacityList({
    required this.db,
    required this.capacities,
    required this.selectedDate,
  });

  final AppDatabase db;
  final Map<String, double> capacities;
  final DateTime selectedDate;

  Future<Map<String, double>> _loadUsedMinutes() async {
    final startOfDay = selectedDate;
    final startOfNextDay = selectedDate.add(const Duration(days: 1));

    final tasks = await (db.select(db.productionTasks)
          ..where((tbl) => tbl.deletedAt.isNull())
          ..where((tbl) => tbl.datum.isBiggerOrEqualValue(startOfDay))
          ..where((tbl) => tbl.datum.isSmallerThanValue(startOfNextDay))

          ..where((tbl) => tbl.status.isNotIn(const ['storniert'])))
        .get();

    final usedByDepartment = <String, double>{};
    for (final task in tasks) {
      usedByDepartment[task.abteilung] =
          (usedByDepartment[task.abteilung] ?? 0) + task.geplanteDauerMinuten;
    }
    return usedByDepartment;
  }

  String _fmtMin(double m) {
    final h = m ~/ 60;
    final min = (m % 60).round();
    return '${h}h ${min.toString().padLeft(2, '0')}m';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, double>>(
      future: _loadUsedMinutes(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Center(child: Text('Fehler: ${snapshot.error}'));
        }

        final usedByDept = snapshot.data ?? {};

        // ── Gesamt-Zusammenfassung ──
        double totalCapacity = 0;
        double totalUsed = 0;
        int overloaded = 0;
        int idle = 0;

        for (final abt in Abteilung.values) {
          final cap = capacities[abt.dbValue] ?? 480;
          final used = usedByDept[abt.dbValue] ?? 0;
          totalCapacity += cap;
          totalUsed += used;
          if (used > cap) overloaded++;
          if (used == 0) idle++;
        }

        final totalRatio =
            totalCapacity > 0 ? totalUsed / totalCapacity : 0.0;
        final totalColor = totalRatio > 1.0
            ? Colors.red
            : totalRatio > 0.75
                ? Colors.orange
                : Colors.green;

        return Column(
          children: [
            // ── Summary-Card ──
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Tages-Übersicht',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Text(
                          '${(totalRatio * 100).clamp(0, 150).toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: totalColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (totalRatio).clamp(0, 1.0),
                        backgroundColor: Colors.grey.shade200,
                        color: totalColor,
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DefaultTextStyle(
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      child: Row(
                        children: [
                          Text('${_fmtMin(totalUsed)} / ${_fmtMin(totalCapacity)}'),
                          const Spacer(),
                          _SummaryChip(
                            icon: Icons.warning_amber_rounded,
                            label: '$overloaded überlastet',
                            color: overloaded > 0
                                ? Colors.red
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                          ),
                          const SizedBox(width: 12),
                          _SummaryChip(
                            icon: Icons.pause_circle_outline,
                            label: '$idle ohne Aufträge',
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // ── Einzelne Abteilungen ──
            ...Abteilung.values.map((abteilung) {
              final capacityMinutes =
                  capacities[abteilung.dbValue] ?? 480;
              final usedMinutes =
                  usedByDept[abteilung.dbValue] ?? 0;
              return _DepartmentCapacityCard(
                abteilung: abteilung,
                usedMinutes: usedMinutes,
                capacityMinutes: capacityMinutes,
              );
            }),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Kleiner Chip für die Tages-Übersicht
// ---------------------------------------------------------------------------

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}

class _DepartmentCapacityCard extends ConsumerWidget {
  const _DepartmentCapacityCard({
    required this.abteilung,
    required this.usedMinutes,
    required this.capacityMinutes,
  });

  final Abteilung abteilung;
  final double usedMinutes;
  final double capacityMinutes;

  double get _ratio =>
      capacityMinutes > 0 ? (usedMinutes / capacityMinutes).clamp(0, 1.5) : 0;

  Color get _barColor {
    if (_ratio > 1.0) return Colors.red;
    if (_ratio > 0.75) return Colors.orange;
    return Colors.green;
  }

  String _formatMinutes(double minutes) {
    final h = minutes ~/ 60;
    final m = (minutes % 60).round();
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remaining = (capacityMinutes - usedMinutes).clamp(0.0, double.infinity);
    final pctLabel = '${(_ratio * 100).clamp(0.0, 150.0).toStringAsFixed(0)}%';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: abteilung.farbe,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    abteilung.kurzcode,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        abteilung.anzeigeName,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_formatMinutes(usedMinutes)} / ${_formatMinutes(capacityMinutes)}  ·  Rest ${_formatMinutes(remaining)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  pctLabel,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _barColor,
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 32,
                  height: 32,
                  child: IconButton(
                    icon: const Icon(Icons.edit, size: 16),
                    padding: EdgeInsets.zero,
                    tooltip: 'Kapazität bearbeiten',
                    onPressed: () => _showEditCapacityDialog(
                      context, ref, abteilung, capacityMinutes,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _ratio > 1.0 ? 1.0 : _ratio,
                backgroundColor: Colors.grey.shade200,
                color: _barColor,
                minHeight: 6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditCapacityDialog(
    BuildContext context,
    WidgetRef ref,
    Abteilung abteilung,
    double currentCapacity,
  ) async {
    final controller = TextEditingController(
      text: currentCapacity.toStringAsFixed(0),
    );
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<double?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Abteilungskapazität ändern'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Kapazität in Minuten',
              hintText: 'z. B. 480',
            ),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Bitte eine Zahl eingeben';
              final parsed = double.tryParse(value);
              if (parsed == null || parsed < 60) return 'Ab mindestens 60 Minuten';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              final parsed = double.tryParse(controller.text);
              if (parsed != null) Navigator.pop(context, parsed);
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    );

    if (result == null) return;
    await ref
        .read(departmentCapacityNotifierProvider.notifier)
        .setCapacity(abteilung.dbValue, result);
  }
}
