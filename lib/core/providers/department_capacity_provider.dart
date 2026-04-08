import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/abteilungen.dart';
import '../services/department_capacity_service.dart';

final departmentCapacityNotifierProvider =
    StateNotifierProvider<DepartmentCapacityNotifier, AsyncValue<Map<String, double>>>(
  (ref) => DepartmentCapacityNotifier(),
);

class DepartmentCapacityNotifier
    extends StateNotifier<AsyncValue<Map<String, double>>> {
  DepartmentCapacityNotifier() : super(const AsyncValue.loading()) {
    _loadCapacities();
  }

  Future<void> _loadCapacities() async {
    try {
      final capacities = await DepartmentCapacityService.loadCapacities();
      state = AsyncValue.data(capacities);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> setCapacity(String abteilung, double minutes) async {
    if (state is! AsyncData<Map<String, double>>) return;

    final current = (state as AsyncData<Map<String, double>>).value;
    final updated = Map<String, double>.from(current)
      ..[abteilung] = minutes.clamp(60, 1440);

    state = AsyncValue.loading();
    try {
      await DepartmentCapacityService.saveCapacities(updated);
      state = AsyncValue.data(updated);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() async {
    await _loadCapacities();
  }
}
