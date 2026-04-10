import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/providers/personnel_provider.dart';
import '../../core/services/personnel_service.dart';

/// Vollständige Mitarbeiterliste mit Abteilung, Arbeitszeiten, Urlaub
/// und Lösch-Funktion.
class PersonnelListSection extends ConsumerWidget {
  const PersonnelListSection({super.key});

  static const _dayLabels = {
    1: 'Mo',
    2: 'Di',
    3: 'Mi',
    4: 'Do',
    5: 'Fr',
    6: 'Sa',
    7: 'So',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planState = ref.watch(personnelPlanNotifierProvider);

    return planState.when(
      data: (plan) => _buildList(context, ref, plan),
      loading: () => const SizedBox(
        height: 140,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Fehler: $error',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, WidgetRef ref, PersonnelPlan plan) {
    if (plan.employees.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text('Noch keine Mitarbeiter angelegt.'),
          ),
        ),
      );
    }

    // Nach Abteilung gruppieren
    final grouped = <String, List<Employee>>{};
    for (final emp in plan.employees) {
      grouped.putIfAbsent(emp.department, () => []).add(emp);
    }

    // Sortiert nach Abteilungs-Reihenfolge
    final sortedDepts = Abteilung.values
        .where((a) => grouped.containsKey(a.dbValue))
        .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Alle Mitarbeiter (${plan.employees.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            for (final abt in sortedDepts) ...[
              _DepartmentHeader(abteilung: abt),
              const SizedBox(height: 4),
              ...grouped[abt.dbValue]!.map(
                (emp) => _EmployeeTile(
                  employee: emp,
                  vacations: plan.vacations
                      .where((v) => v.employeeId == emp.id)
                      .toList(),
                  onDelete: () =>
                      _confirmDelete(context, ref, emp),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Employee employee,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mitarbeiter löschen?'),
        content: Text(
          '„${employee.name}" wird unwiderruflich entfernt, '
          'inklusive aller zugehörigen Urlaubseinträge.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Löschen',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await ref
        .read(personnelPlanNotifierProvider.notifier)
        .removeEmployee(employee.id);
  }
}

// ---------------------------------------------------------------------------
// Abteilungs-Header
// ---------------------------------------------------------------------------

class _DepartmentHeader extends StatelessWidget {
  const _DepartmentHeader({required this.abteilung});

  final Abteilung abteilung;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: abteilung.farbe,
          child: Text(
            abteilung.kurzcode,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          abteilung.anzeigeName,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Einzelner Mitarbeiter
// ---------------------------------------------------------------------------

class _EmployeeTile extends StatelessWidget {
  const _EmployeeTile({
    required this.employee,
    required this.vacations,
    required this.onDelete,
  });

  final Employee employee;
  final List<VacationEntry> vacations;
  final VoidCallback onDelete;

  static const _dayLabels = {
    1: 'Mo',
    2: 'Di',
    3: 'Mi',
    4: 'Do',
    5: 'Fr',
    6: 'Sa',
    7: 'So',
  };

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Nächster Urlaub ab heute
    final upcoming = vacations
        .where((v) => !v.toDate.isBefore(today))
        .toList()
      ..sort((a, b) => a.fromDate.compareTo(b.fromDate));

    final tage = employee.wochentage
        .map((d) => _dayLabels[d] ?? '?')
        .join(', ');

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // Infos
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    employee.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      _IconLabel(
                        icon: Icons.schedule,
                        text:
                            '${employee.arbeitsBeginn} – ${employee.arbeitsEnde}',
                      ),
                      _IconLabel(
                        icon: Icons.calendar_view_week,
                        text: tage,
                      ),
                    ],
                  ),
                  if (upcoming.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    ...upcoming.take(2).map(
                          (v) => _IconLabel(
                            icon: Icons.beach_access,
                            text:
                                '${_fmt(v.fromDate)} – ${_fmt(v.toDate)}'
                                '${v.reason.isNotEmpty ? '  (${v.reason})' : ''}',
                          ),
                        ),
                    if (upcoming.length > 2)
                      _IconLabel(
                        icon: Icons.more_horiz,
                        text: '+${upcoming.length - 2} weitere',
                      ),
                  ],
                ],
              ),
            ),
            // Löschen-Button
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              tooltip: 'Mitarbeiter löschen',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}

// ---------------------------------------------------------------------------
// Hilfs-Widget
// ---------------------------------------------------------------------------

class _IconLabel extends StatelessWidget {
  const _IconLabel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
