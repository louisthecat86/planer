import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:produktion_planer/models/department.dart';
import 'package:produktion_planer/models/product.dart';
import 'package:produktion_planer/models/raw_material.dart';
import 'package:produktion_planer/models/production_task.dart';
import 'package:produktion_planer/services/database_service.dart';
import 'package:produktion_planer/widgets/department_card.dart';
import 'package:produktion_planer/widgets/raw_material_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<List<Department>> _departmentsFuture;
  late Future<List<ProductionTask>> _tasksFuture;
  late Future<List<Product>> _productsFuture;

  @override
  void initState() {
    super.initState();
    _departmentsFuture = DatabaseService.instance.fetchDepartments();
    _tasksFuture = DatabaseService.instance.fetchTasks();
    _productsFuture = DatabaseService.instance.fetchProducts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Produktion Planer'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: FutureBuilder<List<dynamic>>(
          future: Future.wait([_departmentsFuture, _tasksFuture, _productsFuture]),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Fehler: \\${snapshot.error}'));
            }

            final departments = snapshot.data![0] as List<Department>;
            final tasks = snapshot.data![1] as List<ProductionTask>;
            final products = snapshot.data![2] as List<Product>;
            final today = DateTime.now();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Wochenübersicht',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: ListView(
                          children: departments.map((department) {
                            final departmentTasks = tasks.where((task) => task.departmentId == department.id).toList();
                            return DepartmentCard(
                              department: department,
                              tasks: departmentTasks,
                              departments: departments,
                              products: products,
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FutureBuilder<List<RawMaterial>>(
                          future: _loadCriticalMaterials(products),
                          builder: (context, materialSnapshot) {
                            if (materialSnapshot.connectionState != ConnectionState.done) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            final materials = materialSnapshot.data!;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Rohwaren-Check', style: Theme.of(context).textTheme.headlineSmall,),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: materials.isEmpty
                                      ? const Center(child: Text('Alle wichtigen Rohwaren sind gecheckt.'))
                                      : ListView.builder(
                                          itemCount: materials.length,
                                          itemBuilder: (context, index) {
                                            return RawMaterialCard(rawMaterial: materials[index]);
                                          },
                                        ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Nächster Planungstermin: ${DateFormat.yMMMMd('de_DE').format(today.add(const Duration(days: 1)))}',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<List<RawMaterial>> _loadCriticalMaterials(List<Product> products) async {
    final materials = <RawMaterial>[];
    for (final product in products) {
      final productMaterials = await DatabaseService.instance.fetchRawMaterialsForProduct(product.id!);
      materials.addAll(productMaterials.where((material) => !material.ordered));
    }
    return materials;
  }
}
