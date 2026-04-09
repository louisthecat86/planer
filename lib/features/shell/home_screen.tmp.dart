import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/providers/department_capacity_provider.dart';
import '../../core/providers/personnel_provider.dart';
import '../../core/services/demo_data_service.dart';
import '../../core/services/personnel_service.dart';

const _dayNames = [
  'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag',
  'Freitag', 'Samstag', 'Sonntag',
];
const _monthNames = [
  'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
  'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
];

/// Ausgewähltes Datum für die Tagesansicht.
final selectedDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

/// Dashboard-Startbildschirm mit Kacheln.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Produktion Planer'),
        actions: [
          IconButton(
            onPressed: () => context.pushNamed('backup'),
            icon: const Icon(Icons.backup),
            tooltip: 'Backup-Verwaltung',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _DatabaseStatusCard(db: db),
          const SizedBox(height: 12),
          const _DateNavigationBar(),
          const SizedBox(height: 20),
          _DailyOverviewTile(db: db),
          const SizedBox(height: 20),
          Text(
            'Bereiche',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          _buildTileGrid(context),
        ],
      ),
    );
  }

  Widget _buildTileGrid(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 600 ? 3 : 2;
        const spacing = 12.0;
        final tileWidth =
            (constraints.maxWidth - spacing * (crossAxisCount - 1)) /
                crossAxisCount;

        final tiles = [
          _NavigationTile(
            icon: Icons.bar_chart_rounded,
            label: 'Kapazität',
            subtitle: 'Auslastung je Abteilung',
            color: const Color(0xFF1565C0),
            onTap: () => context.pushNamed('capacity'),
          ),
          _NavigationTile(
            icon: Icons.assignment_rounded,
            label: 'Aufträge',
            subtitle: 'Tagesaufträge & Status',
            color: const Color(0xFFFB8C00),
            onTap: () => context.pushNamed('tasks'),
          ),
          _NavigationTile(
            icon: Icons.people_rounded,
            label: 'Personal',
            subtitle: 'Planung & Urlaub',
            color: const Color(0xFF2E7D32),
            onTap: () => context.pushNamed('personnel'),
          ),
          _NavigationTile(
            icon: Icons.backup_rounded,
            label: 'Backup',
            subtitle: 'Sicherung & Wiederherstellung',
            color: const Color(0xFF6A1B9A),
            onTap: () => context.pushNamed('backup'),
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
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(height: 14),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
// Daily overview tile – bundles the day's key numbers
// ---------------------------------------------------------------------------

class _DailyOverviewTile extends ConsumerWidget {
  const _DailyOverviewTile({required this.db});

  final AppDatabase db;

  Future<_DailySummary> _loadSummary(
    DateTime date,
    Map<String, double> capacities,
    PersonnelPlan plan,
  ) async {
    final startOfDay = date;
    final startOfNextDay = date.add(const Duration(days: 1));

    final tasks = await (db.select(db.productionTasks)
          ..where((tbl) => tbl.deletedAt.isNull())
          ..where((tbl) => tbl.datum.isBiggerOrEqualValue(startOfDay))
          ..where((tbl) => tbl.datum.isSmallerThanValue(startOfNextDay))
          ..where((tbl) => tbl.status.isNotIn(const ['storniert'])))
        .get();

    // Capacity usage
    double totalUsed = 0;
    double totalCapacity = 0;
    for (final abteilung in Abteilung.values) {
      final cap = capacities[abteilung.dbValue] ?? 480;
      totalCapacity += cap;
      for (final task in tasks) {
        if (task.abteilung == abteilung.dbValue) {
          totalUsed += task.geplanteDauerMinuten;
        }
      }
    }

    // Critical departments
    final usedByDept = <String, double>{};
    for (final task in tasks) {
      usedByDept[task.abteilung] =
          (usedByDept[task.abteilung] ?? 0) + task.geplanteDauerMinuten;
    }
    int criticalDepts = 0;
    for (final abteilung in Abteilung.values) {
      final cap = capacities[abteilung.dbValue] ?? 480;
      final used = usedByDept[abteilung.dbValue] ?? 0;
      if (cap > 0 && used / cap > 0.9) criticalDepts++;
    }

    // Personnel
    final absenceToday = plan.vacations
        .where((VacationEntry v) => v.overlapsDate(date))
        .length;

    return _DailySummary(
      taskCount: tasks.length,
      totalUsedMinutes: totalUsed,
      totalCapacityMinutes: totalCapacity,
      criticalDepartments: criticalDepts,
      totalEmployees: plan.employees.length,
      absentToday: absenceToday,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(selectedDateProvider);
    final capacityState = ref.watch(departmentCapacityNotifierProvider);
    final personnelState = ref.watch(personnelPlanNotifierProvider);

    // Wait for both providers
    final capacities = capacityState.valueOrNull ?? {};
    final plan = personnelState.valueOrNull;

    if (plan == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return FutureBuilder<_DailySummary>(
      future: _loadSummary(selectedDate, capacities, plan),
      builder: (context, snapshot) {
        final summary = snapshot.data;

        return Card(
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF37474F),
                  Color(0xFF455A64),
                ],
              ),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.today_rounded, color: Colors.white, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'Tagesübersicht',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (summary == null)
                  const Center(
                    child: CircularProgressIndicator(color: Colors.white70),
                  )
                else
                  _buildMetrics(context, summary),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMetrics(BuildContext context, _DailySummary summary) {
    final avgUtil = summary.totalCapacityMinutes > 0
        ? (summary.totalUsedMinutes / summary.totalCapacityMinutes * 100)
        : 0.0;

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _MetricItem(
          icon: Icons.assignment_rounded,
          value: '${summary.taskCount}',
          label: 'Aufträge',
        ),
        _MetricItem(
          icon: Icons.speed_rounded,
          value: '${avgUtil.toStringAsFixed(0)}%',
          label: 'Ø Auslastung',
        ),
        if (summary.criticalDepartments > 0)
          _MetricItem(
            icon: Icons.warning_amber_rounded,
            value: '${summary.criticalDepartments}',
            label: 'Abt. kritisch',
            valueColor: const Color(0xFFFF8A65),
          ),
        _MetricItem(
          icon: Icons.people_rounded,
          value: '${summary.totalEmployees - summary.absentToday}',
          label: 'Verfügbar',
        ),
        if (summary.absentToday > 0)
          _MetricItem(
            icon: Icons.airline_seat_individual_suite_rounded,
            value: '${summary.absentToday}',
            label: 'Abwesend',
            valueColor: const Color(0xFFFF8A65),
          ),
      ],
    );
  }
}

class _MetricItem extends StatelessWidget {
  const _MetricItem({
    required this.icon,
    required this.value,
    required this.label,
    this.valueColor,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                color: valueColor ?? Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }
}

class _DailySummary {
  _DailySummary({
    required this.taskCount,
    required this.totalUsedMinutes,
    required this.totalCapacityMinutes,
    required this.criticalDepartments,
    required this.totalEmployees,
    required this.absentToday,
  });

  final int taskCount;
  final double totalUsedMinutes;
  final double totalCapacityMinutes;
  final int criticalDepartments;
  final int totalEmployees;
  final int absentToday;
}

// ---------------------------------------------------------------------------
// Date navigation bar
// ---------------------------------------------------------------------------

class _DateNavigationBar extends ConsumerWidget {
  const _DateNavigationBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(selectedDateProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isToday = selectedDate == today;

    final dayName = _dayNames[selectedDate.weekday - 1];
    final label =
        '$dayName, ${selectedDate.day}. ${_monthNames[selectedDate.month - 1]} ${selectedDate.year}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () {
                ref.read(selectedDateProvider.notifier).state =
                    selectedDate.subtract(const Duration(days: 1));
              },
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
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            if (!isToday)
              TextButton(
                onPressed: () {
                  ref.read(selectedDateProvider.notifier).state = today;
                },
                child: const Text('Heute'),
              ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () {
                ref.read(selectedDateProvider.notifier).state =
                    selectedDate.add(const Duration(days: 1));
              },
              tooltip: 'Nächster Tag',
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Database status card
// ---------------------------------------------------------------------------

class _DatabaseStatusCard extends ConsumerStatefulWidget {
  const _DatabaseStatusCard({required this.db});

  final AppDatabase db;

  @override
  ConsumerState<_DatabaseStatusCard> createState() =>
      _DatabaseStatusCardState();
}

class _DatabaseStatusCardState extends ConsumerState<_DatabaseStatusCard> {
  bool _isSeeding = false;
  int _rebuildKey = 0;

  Future<void> _seedDemoData() async {
    setState(() => _isSeeding = true);
    try {
      await DemoDataService.seedDemoData(widget.db);
      ref.invalidate(departmentCapacityNotifierProvider);
      ref.invalidate(personnelPlanNotifierProvider);
      if (mounted) {
        setState(() {
          _isSeeding = false;
          _rebuildKey++;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Testdaten erfolgreich geladen!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSeeding = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler beim Laden der Testdaten: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<int>(
          key: ValueKey(_rebuildKey),
          future: widget.db
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
                    'Lade Testdaten, um alle Funktionen sofort auszuprobieren.',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isSeeding ? null : _seedDemoData,
                      icon: _isSeeding
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.science),
                      label: Text(
                        _isSeeding ? 'Wird geladen …' : 'Testdaten laden',
                      ),
                    ),
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
