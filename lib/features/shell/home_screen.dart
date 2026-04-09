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
import 'personnel_planning_section.dart';

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

/// Startbildschirm für den Produktionsplaner.
///
/// Zeigt den Datenbankstatus, Abteilungs-Kapazitätsbalken und eine schnelle
/// Übersicht über die Abteilungen. Die Kapazitäten können direkt bearbeitet
/// und dauerhaft gespeichert werden.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    final capacityState = ref.watch(departmentCapacityNotifierProvider);
    final selectedDate = ref.watch(selectedDateProvider);

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
          const SizedBox(height: 16),
          const _DateNavigationBar(),
          const SizedBox(height: 16),
          capacityState.when(
            data: (capacities) => _DepartmentCapacitySection(
              db: db,
              capacities: capacities,
              selectedDate: selectedDate,
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Fehler beim Laden der Kapazitäten: $error',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          PersonnelPlanningSection(db: db, selectedDate: selectedDate),
          const SizedBox(height: 24),
          _TaskPlannerSection(db: db),
          const SizedBox(height: 24),
          Text(
            'Abteilungen',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          ...Abteilung.values.map(_AbteilungTile.new),
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

class _DepartmentCapacitySection extends StatelessWidget {
  const _DepartmentCapacitySection({
    required this.db,
    required this.capacities,
    required this.selectedDate,
  });

  final AppDatabase db;
  final Map<String, double> capacities;
  final DateTime selectedDate;

  Future<List<_DepartmentCapacity>> _loadDepartments() async {
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

    return Abteilung.values.map((abteilung) {
      final capacityMinutes = capacities[abteilung.dbValue] ?? 480;
      final usedMinutes = usedByDepartment[abteilung.dbValue] ?? 0;
      return _DepartmentCapacity(
        abteilung: abteilung,
        usedMinutes: usedMinutes,
        capacityMinutes: capacityMinutes,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_DepartmentCapacity>>(
      future: _loadDepartments(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Fehler beim Laden der Abteilungsdaten: ${snapshot.error}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          );
        }

        final departments = snapshot.data ?? [];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Abteilungs-Kapazität',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Gebuchte Produktionszeit pro Abteilung und verbleibende Tageskapazität.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                ...departments
                    .map((department) => _DepartmentCard(department: department)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DepartmentCapacity {
  _DepartmentCapacity({
    required this.abteilung,
    required this.usedMinutes,
    required this.capacityMinutes,
  });

  final Abteilung abteilung;
  final double usedMinutes;
  final double capacityMinutes;

  double get ratio =>
      capacityMinutes > 0 ? (usedMinutes / capacityMinutes).clamp(0, 1.5) : 0;

  String get formattedUsed {
    final hours = usedMinutes ~/ 60;
    final minutes = (usedMinutes % 60).round();
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }

  String get formattedRemaining {
    final remaining = (capacityMinutes - usedMinutes).clamp(0, double.infinity);
    final hours = remaining ~/ 60;
    final minutes = (remaining % 60).round();
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }

  String get capacityLabel {
    final hours = capacityMinutes ~/ 60;
    final minutes = (capacityMinutes % 60).round();
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }

  Color get barColor {
    if (ratio > 1.0) return Colors.red;
    if (ratio > 0.75) return Colors.orange;
    return Colors.green;
  }
}

class _DepartmentCard extends ConsumerWidget {
  const _DepartmentCard({required this.department});

  final _DepartmentCapacity department;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: department.abteilung.farbe,
                  child: Text(
                    department.abteilung.kurzcode,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    department.abteilung.anzeigeName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: 'Kapazität bearbeiten',
                  onPressed: () => _showEditCapacityDialog(
                    context,
                    ref,
                    department.abteilung,
                    department.capacityMinutes,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: department.ratio > 1 ? 1 : department.ratio,
                backgroundColor: Colors.grey.shade200,
                color: department.barColor,
                minHeight: 12,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(department.ratio * 100).clamp(0, 150).toStringAsFixed(0)} % Auslastung',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: department.barColor,
                  ),
                ),
                Text(
                  'Kapazität: ${department.capacityLabel}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Gebucht: ${department.formattedUsed} · Rest: ${department.formattedRemaining}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
              if (value == null || value.isEmpty) {
                return 'Bitte eine Zahl eingeben';
              }
              final parsed = double.tryParse(value);
              if (parsed == null || parsed < 60) {
                return 'Ab mindestens 60 Minuten';
              }
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
              if (parsed != null) {
                Navigator.pop(context, parsed);
              }
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    );

    if (result == null) return;
    await ref.read(departmentCapacityNotifierProvider.notifier).setCapacity(
          abteilung.dbValue,
          result,
        );
  }
}

class _TaskPlannerSection extends ConsumerStatefulWidget {
  const _TaskPlannerSection({required this.db});

  final AppDatabase db;

  @override
  ConsumerState<_TaskPlannerSection> createState() => _TaskPlannerSectionState();
}

class _TaskPlannerSectionState extends ConsumerState<_TaskPlannerSection> {
  Abteilung? _selectedAbteilung;

  Future<List<_TaskPlannerItem>> _loadTasks(DateTime selectedDate) async {
    final startOfDay = selectedDate;
    final startOfNextDay = selectedDate.add(const Duration(days: 1));

    final query = widget.db.select(widget.db.productionTasks)
      ..where((tbl) => tbl.deletedAt.isNull())
      ..where((tbl) => tbl.datum.isBiggerOrEqualValue(startOfDay))
      ..where((tbl) => tbl.datum.isSmallerThanValue(startOfNextDay))
      ..where((tbl) => tbl.status.isNotIn(const ['storniert']));

    final tasks = await query.get();
    final productIds = tasks.map((task) => task.productId).toSet();
    final products = await (widget.db.select(widget.db.products)
          ..where((tbl) => tbl.id.isIn(productIds.toList())))
        .get();
    final productMap = {for (final product in products) product.id: product};

    return tasks.map((task) {
      final product = productMap[task.productId];
      return _TaskPlannerItem(
        task: task,
        productLabel: product != null
            ? '${product.artikelnummer} · ${product.artikelbezeichnung}'
            : task.productId,
        abteilung: Abteilung.fromDbValue(task.abteilung),
      );
    }).toList();
  }

  void _selectAbteilung(Abteilung? abteilung) {
    setState(() {
      _selectedAbteilung = abteilung;
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedDate = ref.watch(selectedDateProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Aufträge',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Produktionsaufträge für den gewählten Tag. '
              'Filtere nach Abteilung, um Überlastungen schneller zu erkennen.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Alle Abteilungen'),
                  selected: _selectedAbteilung == null,
                  onSelected: (_) => _selectAbteilung(null),
                ),
                ...Abteilung.values.map(
                  (abteilung) => ChoiceChip(
                    label: Text(abteilung.kurzcode),
                    selected: _selectedAbteilung == abteilung,
                    selectedColor: abteilung.farbe.withValues(alpha: 0.15),
                    onSelected: (_) => _selectAbteilung(abteilung),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<_TaskPlannerItem>>(
              future: _loadTasks(selectedDate),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (snapshot.hasError) {
                  return Text(
                    'Fehler beim Laden der Aufgaben: ${snapshot.error}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  );
                }

                final tasks = snapshot.data
                        ?.where((item) =>
                            _selectedAbteilung == null ||
                            item.abteilung == _selectedAbteilung,)
                        .toList() ??
                    [];

                if (tasks.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
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
                  children: tasks
                      .map((item) => _TaskPlannerCard(item: item))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskPlannerItem {
  _TaskPlannerItem({
    required this.task,
    required this.productLabel,
    required this.abteilung,
  });

  final ProductionTask task;
  final String productLabel;
  final Abteilung abteilung;

  String get durationLabel {
    final hours = task.geplanteDauerMinuten ~/ 60;
    final minutes = (task.geplanteDauerMinuten % 60).round();
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
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

class _TaskPlannerCard extends StatelessWidget {
  const _TaskPlannerCard({required this.item});

  final _TaskPlannerItem item;

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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
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
                  _TaskDetailChip(
                    icon: Icons.schedule,
                    label: item.durationLabel,
                  ),
                  _TaskDetailChip(
                    icon: Icons.people,
                    label: '${item.task.geplanteMitarbeiter} MA',
                  ),
                  _TaskDetailChip(
                    icon: Icons.scale,
                    label: '${item.task.mengeKg.toStringAsFixed(0)} kg',
                  ),
                  if (item.task.startZeit != null)
                    _TaskDetailChip(
                      icon: Icons.access_time,
                      label: item.task.startZeit!,
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

class _TaskDetailChip extends StatelessWidget {
  const _TaskDetailChip({required this.icon, required this.label});

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

class _AbteilungTile extends StatelessWidget {
  const _AbteilungTile(this.abteilung);

  final Abteilung abteilung;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: abteilung.farbe,
          foregroundColor: Colors.white,
          child: Text(abteilung.kurzcode),
        ),
        title: Text(abteilung.anzeigeName),
        subtitle: Text(
          'Kurzcode: ${abteilung.kurzcode}',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
