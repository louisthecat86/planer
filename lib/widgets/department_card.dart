import 'package:flutter/material.dart';
import 'package:produktion_planer/models/department.dart';
import 'package:produktion_planer/models/product.dart';
import 'package:produktion_planer/models/production_task.dart';

class DepartmentCard extends StatelessWidget {
  final Department department;
  final List<ProductionTask> tasks;
  final List<Department> departments;
  final List<Product> products;

  const DepartmentCard({
    super.key,
    required this.department,
    required this.tasks,
    required this.departments,
    required this.products,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Color(department.color),
                  child: Text(department.shortCode),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    department.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (tasks.isEmpty)
              const Text('Keine Planungen für diese Abteilung im aktuellen Zeitraum.')
            else
              Column(
                children: tasks.map((task) {
                  final product = products.firstWhere((p) => p.id == task.productId, orElse: () => Product(articleNumber: 'n/a', name: 'Unbekannt', plannedQuantity: task.plannedQuantity, averageDurationPerUnit: 0, machineSettings: '', parameterHistory: '' ));
                  return _TaskTile(task: task, product: product, departments: departments);
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  final ProductionTask task;
  final Product product;
  final List<Department> departments;

  const _TaskTile({required this.task, required this.product, required this.departments});

  @override
  Widget build(BuildContext context) {
    final dependencyNames = task.dependencyDepartmentIds
        .split(',')
        .where((id) => id.isNotEmpty)
        .map((id) => departments.firstWhere((dept) => dept.id == int.tryParse(id), orElse: () => Department(id: 0, name: 'Unbekannt', color: 0xFF9E9E9E, shortCode: '?')).name)
        .join(', ');
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        title: Text('${product.name} • ${task.plannedQuantity} Stk.'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Team: ${task.teamSize} | Dauer: ${task.estimatedDurationMinutes} min'),
            if (dependencyNames.isNotEmpty) Text('Abhängigkeiten: $dependencyNames'),
          ],
        ),
      ),
    );
  }
}
