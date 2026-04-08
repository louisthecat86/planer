import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/providers/department_capacity_provider.dart';
import 'personnel_planning_section.dart';

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
          const SizedBox(height: 20),
          const _HeroInfoCard(),
          const SizedBox(height: 20),
          capacityState.when(
            data: (capacities) => _DepartmentCapacitySection(
              db: db,
              capacities: capacities,
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Fehler beim Laden der Kapazitäten: $error',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          PersonnelPlanningSection(db: db),
          const SizedBox(height: 24),
          _TaskPlannerSection(db: db),
          const SizedBox(height: 24),
          Text(
            'Abteilungen',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          ...Abteilung.values.map(_AbteilungTile.new),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Phase 1a abgeschlossen',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Datenmodell und lokale Datenbank sind eingerichtet. '
                    'Als Nächstes folgt Phase 1b: Stammdaten-Verwaltung '
                    '(Produkte, Rezepturen, Rohwaren, Chargen).',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroInfoCard extends StatelessWidget {
  const _HeroInfoCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Abteilungsplanung auf einen Blick',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text(
              'Jede Abteilung erhält eine Tageskapazität. '
              'Die Aufgaben werden als Volumenbalken dargestellt. '
              'Grün bedeutet Luft, Gelb bedeutet Nähe zur Kapazitätsgrenze, '
              'Rot bedeutet Überlastung.',
            ),
            SizedBox(height: 12),
            Text(
              'Tippe auf das Bearbeiten-Symbol einer Abteilung, um die Kapazität anzupassen.',
              style: TextStyle(fontWeight: FontWeight.w600),
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
    super.key,
  });

  final AppDatabase db;
  final Map<String, double> capacities;

  Future<List<_DepartmentCapacity>> _loadDepartments() async {
    final tasks = await (db.select(db.productionTasks)
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
            color: Colors.red.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Fehler beim Laden der Abteilungsdaten: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
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
                const Text(
                  'Zeigt die gebuchte Produktionszeit pro Abteilung und die verbleibende Tageskapazität.',
                ),
                const SizedBox(height: 16),
                ...departments
                    .map((department) => _DepartmentCard(department: department))
                    .toList(),
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
  const _DepartmentCard({required this.department, super.key});

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
            LinearProgressIndicator(
              value: department.ratio > 1 ? 1 : department.ratio,
              backgroundColor: Colors.grey.shade200,
              color: department.barColor,
              minHeight: 12,
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
              style: const TextStyle(fontSize: 12, color: Colors.black54),
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
  const _TaskPlannerSection({required this.db, super.key});

  final AppDatabase db;

  @override
  ConsumerState<_TaskPlannerSection> createState() => _TaskPlannerSectionState();
}

class _TaskPlannerSectionState extends ConsumerState<_TaskPlannerSection> {
  Abteilung? _selectedAbteilung;

  Future<List<_TaskPlannerItem>> _loadTasks() async {
    final query = db.select(db.productionTasks)
      ..where((tbl) => tbl.deletedAt.isNull())
      ..where((tbl) => tbl.status.isNotIn(const ['storniert']));

    final tasks = await query.get();
    final productIds = tasks.map((task) => task.productId).toSet();
    final products = await (db.select(db.products)
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

  AppDatabase get db => widget.db;

  void _selectAbteilung(Abteilung? abteilung) {
    setState(() {
      _selectedAbteilung = abteilung;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tagesplanung',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Hier siehst du alle aktiven Produktionsaufträge. '
              'Filtere nach Abteilung, um Überlastungen schneller zu erkennen.',
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
                    selectedColor: abteilung.farbe.withOpacity(0.15),
                    onSelected: (_) => _selectAbteilung(abteilung),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<_TaskPlannerItem>>(
              future: _loadTasks(),
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
                    style: const TextStyle(color: Colors.red),
                  );
                }

                final tasks = snapshot.data
                        ?.where((item) => _selectedAbteilung == null ||
                            item.abteilung == _selectedAbteilung)
                        .toList() ??
                    [];

                if (tasks.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      children: const [
                        SizedBox(height: 40),
                        Text('Keine aktiven Produktionsaufträge gefunden.'),
                      ],
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
  const _TaskPlannerCard({required this.item, super.key});

  final _TaskPlannerItem item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => context.pushNamed('taskDetail', params: {'taskId': item.task.id}),
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
                    backgroundColor: item.statusColor.withOpacity(0.14),
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
                    label: '${item.task.geplanteMitarbeiter} Mitarbeiter',
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
                    style: const TextStyle(color: Colors.black54),
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
  const _TaskDetailChip({required this.icon, required this.label, super.key});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16, color: Colors.grey.shade700),
      label: Text(label),
      backgroundColor: Colors.grey.shade100,
    );
  }
}

class _DatabaseStatusCard extends StatelessWidget {
  const _DatabaseStatusCard({required this.db});

  final AppDatabase db;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<int>(
          future: db
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
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Datenbank-Fehler: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red),
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
                  'Datenbank verbunden — ${snapshot.data} Produkte gespeichert',
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
        subtitle: Text('dbValue: ${abteilung.dbValue}'),
      ),
    );
  }
}
