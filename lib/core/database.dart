import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

class Departments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 128)();
  TextColumn get code => text().withLength(min: 1, max: 16)();
  IntColumn get color => integer().withDefault(Constant(0xFF000000))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Products extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get articleNumber => text().withLength(min: 1, max: 64)();
  TextColumn get name => text().withLength(min: 1, max: 128)();
  TextColumn get description => text().nullable()();
  IntColumn get defaultQuantity => integer().withDefault(Constant(0))();
  TextColumn get machineSettings => text().nullable()();
  TextColumn get parameterHistory => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

class ProductSteps extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().customConstraint('REFERENCES products(id)')();
  IntColumn get departmentId => integer().customConstraint('REFERENCES departments(id)')();
  IntColumn get stepOrder => integer().withDefault(Constant(0))();
  IntColumn get baseQuantity => integer().withDefault(Constant(0))();
  IntColumn get baseDurationMinutes => integer().withDefault(Constant(0))();
  IntColumn get baseTeamSize => integer().withDefault(Constant(1))();
  TextColumn get machineSettings => text().nullable()();
  IntColumn get setupDurationMinutes => integer().withDefault(Constant(0))();
}

class RawMaterials extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 128)();
  TextColumn get unit => text().withLength(min: 1, max: 32)();
  TextColumn get supplier => text().nullable()();
  IntColumn get leadTimeDays => integer().withDefault(Constant(0))();
}

class ProductRawMaterials extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().customConstraint('REFERENCES products(id)')();
  IntColumn get rawMaterialId => integer().customConstraint('REFERENCES raw_materials(id)')();
  RealColumn get quantityPerUnit => real().withDefault(Constant(0.0))();
  BoolColumn get batchRequired => boolean().withDefault(Constant(false))();
  TextColumn get notes => text().nullable()();
}

class ProductionTasks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().customConstraint('REFERENCES products(id)')();
  IntColumn get departmentId => integer().customConstraint('REFERENCES departments(id)')();
  IntColumn get plannedQuantity => integer().withDefault(Constant(0))();
  DateTimeColumn get plannedDate => dateTime()();
  TextColumn get plannedStartTime => text().nullable()();
  IntColumn get plannedDurationMinutes => integer().withDefault(Constant(0))();
  IntColumn get plannedTeamSize => integer().withDefault(Constant(1))();
  TextColumn get status => text().withDefault(Constant('planned'))();
  IntColumn get parentTaskId => integer().nullable().customConstraint('NULL REFERENCES production_tasks(id)')();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

class TaskDependencies extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get taskId => integer().customConstraint('REFERENCES production_tasks(id)')();
  IntColumn get dependsOnTaskId => integer().customConstraint('REFERENCES production_tasks(id)')();
  TextColumn get dependencyType => text().withDefault(Constant('finish_to_start'))();
}

class ProductionRuns extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get taskId => integer().customConstraint('REFERENCES production_tasks(id)')();
  IntColumn get actualQuantity => integer().withDefault(Constant(0))();
  IntColumn get actualDurationMinutes => integer().withDefault(Constant(0))();
  IntColumn get actualTeamSize => integer().withDefault(Constant(0))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get recordedAt => dateTime().withDefault(Constant(DateTime.now()))();
}

class OrderListItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get rawMaterialId => integer().customConstraint('REFERENCES raw_materials(id)')();
  DateTimeColumn get weekStart => dateTime()();
  RealColumn get requiredQuantity => real().withDefault(Constant(0.0))();
  BoolColumn get ordered => boolean().withDefault(Constant(false))();
  BoolColumn get delivered => boolean().withDefault(Constant(false))();
  TextColumn get notes => text().nullable()();
}

@DriftDatabase(
  tables: [
    Departments,
    Products,
    ProductSteps,
    RawMaterials,
    ProductRawMaterials,
    ProductionTasks,
    TaskDependencies,
    ProductionRuns,
    OrderListItems,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  Future<void> ensureDefaultDepartments() async {
    final existing = await select(departments).get();
    if (existing.isNotEmpty) return;

    final defaultDepartments = [
      DepartmentsCompanion.insert(name: 'Zerlegung', code: 'Z', color: const Constant(0xFFB71C1C)),
      DepartmentsCompanion.insert(name: 'Wurstküche', code: 'WK', color: const Constant(0xFF880E4F)),
      DepartmentsCompanion.insert(name: 'Verpackung', code: 'VP', color: const Constant(0xFF1B5E20)),
      DepartmentsCompanion.insert(name: 'Verpackung Tef1', code: 'VT', color: const Constant(0xFF006064)),
      DepartmentsCompanion.insert(name: 'Bratstraße', code: 'B', color: const Constant(0xFF4E342E)),
      DepartmentsCompanion.insert(name: 'Schneideabteilung', code: 'S', color: const Constant(0xFF311B92)),
    ];

    await batch((batch) {
      batch.insertAll(departments, defaultDepartments);
    });
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'produktion_planer.sqlite'));
    return NativeDatabase(file);
  });
}
