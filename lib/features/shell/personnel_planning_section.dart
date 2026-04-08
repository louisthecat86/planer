import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import '../../core/providers/personnel_provider.dart';
import '../../core/services/personnel_service.dart';

class PersonnelPlanningSection extends ConsumerWidget {
  const PersonnelPlanningSection({required this.db, required this.selectedDate, super.key});

  final AppDatabase db;
  final DateTime selectedDate;

  Future<List<ProductionTask>> _loadActiveTasks() async {
    final startOfDay = selectedDate;
    final startOfNextDay = selectedDate.add(const Duration(days: 1));

    return (db.select(db.productionTasks)
          ..where((tbl) => tbl.deletedAt.isNull())
          ..where((tbl) => tbl.datum.isBiggerOrEqualValue(startOfDay))
          ..where((tbl) => tbl.datum.isSmallerThanValue(startOfNextDay))
          ..where((tbl) => tbl.status.isNotIn(const ['storniert'])))
        .get();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planState = ref.watch(personnelPlanNotifierProvider);
    final today = selectedDate;

    return planState.when(
      data: (plan) => FutureBuilder<List<ProductionTask>>(
        future: _loadActiveTasks(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 180,
              child: Center(child: CircularProgressIndicator()),
            );
          }

          if (snapshot.hasError) {
            return Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Fehler beim Laden der Personalplanung: ${snapshot.error}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            );
          }

          final tasks = snapshot.data ?? [];
          final taskEmployeesByDept = <String, int>{};
          for (final task in tasks) {
            taskEmployeesByDept[task.abteilung] =
                (taskEmployeesByDept[task.abteilung] ?? 0) + task.geplanteMitarbeiter;
          }

          final absenceToday = plan.vacations
              .where((vacation) => vacation.overlapsDate(today))
              .toList();

          final employeesByDept = <String, List<Employee>>{};
          for (final employee in plan.employees) {
            employeesByDept.putIfAbsent(employee.department, () => []).add(employee);
          }

          final departmentStatus = Abteilung.values.map((abteilung) {
            final totalStaff = employeesByDept[abteilung.dbValue]?.length ?? 0;
            final absentStaff = absenceToday
                .where((vacation) =>
                    employeesByDept[abteilung.dbValue]
                        ?.any((employee) => employee.id == vacation.employeeId) ??
                    false)
                .length;
            final availableStaff = (totalStaff - absentStaff).clamp(0, totalStaff).toInt();
            final plannedDemand = taskEmployeesByDept[abteilung.dbValue] ?? 0;
            return _DepartmentStaffStatus(
              abteilung: abteilung,
              totalStaff: totalStaff,
              absentStaff: absentStaff,
              availableStaff: availableStaff,
              plannedDemand: plannedDemand,
            );
          }).toList();

          final upcomingVacations = plan.vacations
              .where((vacation) => !vacation.toDate.isBefore(today))
              .toList()
            ..sort((a, b) => a.fromDate.compareTo(b.fromDate));

          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Personalplanung & Urlaub',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _showAddEmployeeDialog(context, ref, plan),
                        icon: const Icon(Icons.person_add),
                        label: const Text('Mitarbeiter'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () => _showAddVacationDialog(context, ref, plan),
                        icon: const Icon(Icons.beach_access),
                        label: const Text('Urlaub'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _InfoBadge(
                        label: 'Team',
                        value: '${plan.employees.length} Mitarbeiter',
                        icon: Icons.group,
                      ),
                      _InfoBadge(
                        label: 'Heute abwesend',
                        value: '${absenceToday.length}',
                        icon: Icons.airline_seat_individual_suite,
                      ),
                      _InfoBadge(
                        label: 'Nächste Urlaube',
                        value: '${upcomingVacations.length}',
                        icon: Icons.calendar_month,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Personalübersicht nach Abteilung',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 10),
                  Column(
                    children: departmentStatus
                        .map((status) => _DepartmentStaffCard(status: status))
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Bevorstehende Urlaube',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  if (upcomingVacations.isEmpty)
                    const Text('Keine Urlaube in der nächsten Zeit geplant.')
                  else
                    Column(
                      children: upcomingVacations
                          .map((vacation) => _VacationRow(
                                vacation: vacation,
                                employees: plan.employees,
                                onDelete: () => ref
                                    .read(personnelPlanNotifierProvider.notifier)
                                  .removeVacation(vacation.id),
                              ))
                          .toList(),
                    ),
                ],
              ),
            ),
          );
        },
      ),
      loading: () => const SizedBox(
        height: 140,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Fehler beim Laden der Personalplanung: $error',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ),
    );
  }

  Future<void> _showAddEmployeeDialog(
    BuildContext context,
    WidgetRef ref,
    PersonnelPlan plan,
  ) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    String selectedDepartment = Abteilung.zerlegung.dbValue;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mitarbeiter hinzufügen'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Bitte Name eingeben';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedDepartment,
                decoration: const InputDecoration(labelText: 'Abteilung'),
                items: Abteilung.values
                    .map((abteilung) => DropdownMenuItem(
                          value: abteilung.dbValue,
                          child: Text(abteilung.anzeigeName),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) selectedDepartment = value;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(context, true);
            },
                child: const Text('Speichern'),
          ),
        ],
      ),
    );

    if (result != true) return;

    await ref.read(personnelPlanNotifierProvider.notifier).addEmployee(
          nameController.text.trim(),
          selectedDepartment,
        );
  }

  Future<void> _showAddVacationDialog(
    BuildContext context,
    WidgetRef ref,
    PersonnelPlan plan,
  ) async {
    if (plan.employees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte zuerst Mitarbeiter anlegen.'),
        ),
      );
      return;
    }

    final formKey = GlobalKey<FormState>();
    final reasonController = TextEditingController();
    String selectedEmployeeId = plan.employees.first.id;
    DateTime fromDate = DateTime.now();
    DateTime toDate = DateTime.now();

    Future<void> pickDate(BuildContext context, bool isFrom) async {
      final picked = await showDatePicker(
        context: context,
        initialDate: isFrom ? fromDate : toDate,
        firstDate: DateTime.now().subtract(const Duration(days: 365)),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      );
      if (picked == null) return;
      if (isFrom) {
        fromDate = picked;
        if (toDate.isBefore(fromDate)) {
          toDate = fromDate;
        }
      } else {
        toDate = picked;
        if (fromDate.isAfter(toDate)) {
          fromDate = toDate;
        }
      }
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Urlaub eintragen'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedEmployeeId,
                  decoration: const InputDecoration(labelText: 'Mitarbeiter'),
                  items: plan.employees
                      .map((employee) => DropdownMenuItem(
                            value: employee.id,
                            child: Text(employee.name),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        selectedEmployeeId = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          await pickDate(context, true);
                          setState(() {});
                        },
                        child: Text('Von: ${_formatDate(fromDate)}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          await pickDate(context, false);
                          setState(() {});
                        },
                        child: Text('Bis: ${_formatDate(toDate)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: reasonController,
                  decoration: const InputDecoration(
                    labelText: 'Grund (optional)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen'),
            ),
            TextButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                Navigator.pop(context, true);
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;

    await ref.read(personnelPlanNotifierProvider.notifier).addVacation(
          selectedEmployeeId,
          fromDate,
          toDate,
          reasonController.text.trim(),
        );
  }
}

class _InfoBadge extends StatelessWidget {
  const _InfoBadge({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
      label: Text('$label: $value'),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    );
  }
}

class _DepartmentStaffStatus {
  _DepartmentStaffStatus({
    required this.abteilung,
    required this.totalStaff,
    required this.absentStaff,
    required this.availableStaff,
    required this.plannedDemand,
  });

  final Abteilung abteilung;
  final int totalStaff;
  final int absentStaff;
  final int availableStaff;
  final int plannedDemand;

  Color get statusColor {
    if (plannedDemand > availableStaff) return Colors.red;
    if (plannedDemand > availableStaff * 0.8) return Colors.orange;
    return Colors.green;
  }

  String get statusText {
    if (plannedDemand > availableStaff) return 'kritisch';
    if (plannedDemand > availableStaff * 0.8) return 'eng';
    return 'im Rahmen';
  }
}

class _DepartmentStaffCard extends StatelessWidget {
  const _DepartmentStaffCard({required this.status});

  final _DepartmentStaffStatus status;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: status.abteilung.farbe,
                  child: Text(
                    status.abteilung.kurzcode,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    status.abteilung.anzeigeName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  status.statusText,
                  style: TextStyle(
                    color: status.statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MiniStatChip(label: 'Team', value: '${status.totalStaff}'),
                _MiniStatChip(label: 'Abwesend', value: '${status.absentStaff}'),
                _MiniStatChip(label: 'Verfügbar', value: '${status.availableStaff}'),
                _MiniStatChip(label: 'Bedarf', value: '${status.plannedDemand}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStatChip extends StatelessWidget {
  const _MiniStatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: $value'),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    );
  }
}

class _VacationRow extends StatelessWidget {
  const _VacationRow({
    required this.vacation,
    required this.employees,
    required this.onDelete,
  });

  final VacationEntry vacation;
  final List<Employee> employees;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final employee = employees.firstWhere(
      (employee) => employee.id == vacation.employeeId,
      orElse: () => Employee(id: vacation.employeeId, name: 'Unbekannt', department: ''),
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        title: Text(employee.name),
        subtitle: Text(
          '${_formatDate(vacation.fromDate)} – ${_formatDate(vacation.toDate)}${vacation.reason.isNotEmpty ? ' • ${vacation.reason}' : ''}',
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: onDelete,
          tooltip: 'Urlaub entfernen',
        ),
      ),
    );
  }
}

String _formatDate(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
