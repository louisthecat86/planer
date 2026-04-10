import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/personnel_service.dart';

final personnelPlanNotifierProvider =
    StateNotifierProvider<PersonnelPlanNotifier, AsyncValue<PersonnelPlan>>(
  (ref) => PersonnelPlanNotifier(),
);

class PersonnelPlanNotifier extends StateNotifier<AsyncValue<PersonnelPlan>> {
  PersonnelPlanNotifier() : super(const AsyncValue.loading()) {
    _loadPlan();
  }

  Future<void> _loadPlan() async {
    try {
      final plan = await PersonnelService.loadPlan();
      state = AsyncValue.data(plan);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> addEmployee(
    String name,
    String department, {
    String arbeitsBeginn = '06:00',
    String arbeitsEnde = '14:00',
    List<int> wochentage = const [1, 2, 3, 4, 5],
  }) async {
    if (state is! AsyncData<PersonnelPlan>) return;
    final currentPlan = (state as AsyncData<PersonnelPlan>).value;
    final updated = PersonnelPlan(
      employees: [
        ...currentPlan.employees,
        Employee(
          id: PersonnelService.createId(),
          name: name,
          department: department,
          arbeitsBeginn: arbeitsBeginn,
          arbeitsEnde: arbeitsEnde,
          wochentage: wochentage,
        ),
      ],
      vacations: currentPlan.vacations,
    );

    await _savePlan(updated);
  }

  Future<void> removeEmployee(String employeeId) async {
    if (state is! AsyncData<PersonnelPlan>) return;
    final currentPlan = (state as AsyncData<PersonnelPlan>).value;
    final updated = PersonnelPlan(
      employees: currentPlan.employees
          .where((employee) => employee.id != employeeId)
          .toList(),
      vacations: currentPlan.vacations
          .where((vacation) => vacation.employeeId != employeeId)
          .toList(),
    );

    await _savePlan(updated);
  }

  Future<void> addVacation(
    String employeeId,
    DateTime fromDate,
    DateTime toDate,
    String reason,
  ) async {
    if (state is! AsyncData<PersonnelPlan>) return;
    final currentPlan = (state as AsyncData<PersonnelPlan>).value;
    final newVacation = VacationEntry(
      id: PersonnelService.createId(),
      employeeId: employeeId,
      fromDate: fromDate,
      toDate: toDate,
      reason: reason,
    );

    final updated = PersonnelPlan(
      employees: currentPlan.employees,
      vacations: [...currentPlan.vacations, newVacation],
    );

    await _savePlan(updated);
  }

  Future<void> removeVacation(String vacationId) async {
    if (state is! AsyncData<PersonnelPlan>) return;
    final currentPlan = (state as AsyncData<PersonnelPlan>).value;
    final updated = PersonnelPlan(
      employees: currentPlan.employees,
      vacations: currentPlan.vacations
          .where((vacation) => vacation.id != vacationId)
          .toList(),
    );

    await _savePlan(updated);
  }

  Future<void> _savePlan(PersonnelPlan plan) async {
    state = const AsyncValue.loading();
    try {
      await PersonnelService.savePlan(plan);
      state = AsyncValue.data(plan);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() async {
    await _loadPlan();
  }
}
