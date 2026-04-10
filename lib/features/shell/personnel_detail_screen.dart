import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/database_provider.dart';
import 'home_screen.dart';
import 'personnel_list_section.dart';
import 'personnel_planning_section.dart';

class PersonnelDetailScreen extends ConsumerWidget {
  const PersonnelDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    final selectedDate = ref.watch(selectedDateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Personalplanung')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PersonnelPlanningSection(db: db, selectedDate: selectedDate),
          const SizedBox(height: 16),
          const PersonnelListSection(),
        ],
      ),
    );
  }
}
