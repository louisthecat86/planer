import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/providers/personnel_provider.dart';
import '../../core/services/personnel_service.dart';

/// Vollständige Mitarbeiterliste mit Abteilung, Arbeitszeiten, Urlaub
/// und Lösch-Funktion – jetzt mit Suche und Abteilungs-Filter.
class PersonnelListSection extends ConsumerStatefulWidget {
  const PersonnelListSection({super.key});

  @override
  ConsumerState<PersonnelListSection> createState() =>
      _PersonnelListSectionState();
}

class _PersonnelListSectionState extends ConsumerState<PersonnelListSection> {
  String _search = '';
  Abteilung? _filterAbt;

  List<Employee> _filtered(List<Employee> all) {
    var list = all;

    // Abteilungs-Filter
    if (_filterAbt != null) {
      list = list.where((e) => e.department == _filterAbt!.dbValue).toList();
    }

    // Text-Suche
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list
          .where((e) =>
              e.name.toLowerCase().contains(q) ||
              e.department.toLowerCase().contains(q))
          .toList();
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final planState = ref.watch(personnelPlanNotifierProvider);

    return planState.when(
      data: (plan) => _buildList(context, plan),
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

  Widget _buildList(BuildContext context, PersonnelPlan plan) {
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

    final filtered = _filtered(plan.employees);

    // Nach Abteilung gruppieren
    final grouped = <String, List<Employee>>{};
    for (final emp in filtered) {
      grouped.putIfAbsent(emp.department, () => []).add(emp);
    }

    // Sortiert nach Abteilungs-Reihenfolge
    final sortedDepts = Abteilung.values
        .where((a) => grouped.containsKey(a.dbValue))
        .toList();

    // Abteilungen die überhaupt Mitarbeiter haben (für Filter-Chips)
    final presentDepts = Abteilung.values
        .where((a) =>
            plan.employees.any((e) => e.department == a.dbValue))
        .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Suchfeld ──
            TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: 'Name oder Abteilung suchen …',
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => setState(() => _search = ''),
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: 10),

            // ── Abteilungs-Filter-Chips ──
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('Alle'),
                    selected: _filterAbt == null,
                    onSelected: (_) => setState(() => _filterAbt = null),
                  ),
                  const SizedBox(width: 6),
                  for (final abt in presentDepts) ...[
                    FilterChip(
                      avatar: CircleAvatar(
                        backgroundColor: abt.farbe,
                        child: Text(
                          abt.kurzcode,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                          ),
                        ),
                      ),
                      label: Text(abt.anzeigeName),
                      selected: _filterAbt == abt,
                      onSelected: (_) => setState(
                        () => _filterAbt = _filterAbt == abt ? null : abt,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),

            // ── Ergebnis-Zähler ──
            Text(
              '${filtered.length} von ${plan.employees.length} Mitarbeiter',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),

            // ── Gruppierte Liste ──
            if (filtered.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: Text('Keine Treffer.')),
              )
            else
              for (final abt in sortedDepts) ...[
                _DepartmentHeader(abteilung: abt),
                const SizedBox(height: 4),
                ...grouped[abt.dbValue]!.map(
                  (emp) => _EmployeeTile(
                    employee: emp,
                    vacations: plan.vacations
                        .where((v) => v.employeeId == emp.id)
                        .toList(),
                    onDelete: () => _confirmDelete(emp),
                  ),
                ),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Employee employee) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mitarbeiter löschen?'),
        content: Text(
          '„${employee.name}" wird unwiderruflich entfernt, '
          'inklusive aller zugehörigen Urlaubseinträge.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
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
