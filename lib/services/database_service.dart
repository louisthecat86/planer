import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:produktion_planer/models/department.dart';
import 'package:produktion_planer/models/product.dart';
import 'package:produktion_planer/models/raw_material.dart';
import 'package:produktion_planer/models/production_task.dart';

class DatabaseService {
  DatabaseService._privateConstructor();
  static final DatabaseService instance = DatabaseService._privateConstructor();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    await init();
    return _db!;
  }

  Future<void> init() async {
    final directory = await getApplicationDocumentsDirectory();
    final path = join(directory.path, 'produktion_planer.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: _createTables,
    );
    await _ensureDefaultDepartments();
    await _ensureSampleProducts();
    await _ensureSampleTasks();
  }

  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE departments(
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        color INTEGER NOT NULL,
        shortCode TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE products(
        id INTEGER PRIMARY KEY,
        articleNumber TEXT NOT NULL,
        name TEXT NOT NULL,
        plannedQuantity INTEGER NOT NULL,
        machineSettings TEXT,
        averageDurationPerUnit REAL DEFAULT 0,
        parameterHistory TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE raw_materials(
        id INTEGER PRIMARY KEY,
        productId INTEGER NOT NULL,
        name TEXT NOT NULL,
        quantity TEXT NOT NULL,
        ordered INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(productId) REFERENCES products(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE production_tasks(
        id INTEGER PRIMARY KEY,
        productId INTEGER NOT NULL,
        departmentId INTEGER NOT NULL,
        plannedDate TEXT NOT NULL,
        plannedQuantity INTEGER NOT NULL,
        teamSize INTEGER NOT NULL,
        estimatedDurationMinutes INTEGER NOT NULL,
        dependencyDepartmentIds TEXT,
        FOREIGN KEY(productId) REFERENCES products(id),
        FOREIGN KEY(departmentId) REFERENCES departments(id)
      )
    ''');
  }

  Future<void> _ensureDefaultDepartments() async {
    final db = await database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM departments'),
    );
    if (count == 0) {
      final departments = [
        Department(id: 1, name: 'Zerlegung', color: 0xFFB71C1C, shortCode: 'Z'),
        Department(id: 2, name: 'Wurstküche', color: 0xFF880E4F, shortCode: 'WK'),
        Department(id: 3, name: 'Verpackung', color: 0xFF1B5E20, shortCode: 'VP'),
        Department(id: 4, name: 'Verpackung Tef1', color: 0xFF006064, shortCode: 'VT'),
        Department(id: 5, name: 'Bratstraße', color: 0xFF4E342E, shortCode: 'B'),
        Department(id: 6, name: 'Schneideabteilung', color: 0xFF311B92, shortCode: 'S'),
      ];
      for (final department in departments) {
        await db.insert('departments', department.toMap());
      }
    }
  }

  Future<void> _ensureSampleProducts() async {
    final db = await database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM products'),
    );
    if (count == 0) {
      final product = Product(
        id: 1,
        articleNumber: 'F-102',
        name: 'Kräuterbratwurst',
        plannedQuantity: 450,
        machineSettings: 'Mischung 5, Temperatur 68°C, Füllgrad 90%',
        averageDurationPerUnit: 0.27,
        parameterHistory: jsonEncode([
          {'quantity': 400, 'durationMinutes': 110, 'timestamp': '2026-04-01T08:00:00Z'},
          {'quantity': 500, 'durationMinutes': 135, 'timestamp': '2026-03-25T08:00:00Z'},
        ]),
      );
      final productId = await db.insert('products', product.toMap());
      await db.insert('raw_materials', RawMaterial(
        productId: productId,
        name: 'Schweinefleisch',
        quantity: '280 kg',
        ordered: false,
      ).toMap());
      await db.insert('raw_materials', RawMaterial(
        productId: productId,
        name: 'Naturdarm',
        quantity: '40 m',
        ordered: false,
      ).toMap());
      await db.insert('raw_materials', RawMaterial(
        productId: productId,
        name: 'Gewürzpaste',
        quantity: '15 kg',
        ordered: true,
      ).toMap());
    }
  }

  Future<void> _ensureSampleTasks() async {
    final db = await database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM production_tasks'),
    );
    if (count == 0) {
      final product = (await db.query('products')).first;
      final productId = product['id'] as int;
      final tasks = [
        ProductionTask(
          id: 1,
          productId: productId,
          departmentId: 1,
          plannedDate: DateTime.now().toIso8601String(),
          plannedQuantity: 450,
          teamSize: 5,
          estimatedDurationMinutes: 120,
          dependencyDepartmentIds: '',
        ),
        ProductionTask(
          id: 2,
          productId: productId,
          departmentId: 2,
          plannedDate: DateTime.now().add(const Duration(days: 1)).toIso8601String(),
          plannedQuantity: 450,
          teamSize: 4,
          estimatedDurationMinutes: 90,
          dependencyDepartmentIds: '1',
        ),
        ProductionTask(
          id: 3,
          productId: productId,
          departmentId: 3,
          plannedDate: DateTime.now().add(const Duration(days: 2)).toIso8601String(),
          plannedQuantity: 450,
          teamSize: 3,
          estimatedDurationMinutes: 60,
          dependencyDepartmentIds: '2',
        ),
      ];
      for (final task in tasks) {
        await db.insert('production_tasks', task.toMap());
      }
    }
  }

  Future<List<Department>> fetchDepartments() async {
    final db = await database;
    final rows = await db.query('departments', orderBy: 'id');
    return rows.map((row) => Department.fromMap(row)).toList();
  }

  Future<List<Product>> fetchProducts() async {
    final db = await database;
    final rows = await db.query('products', orderBy: 'name');
    return rows.map((row) => Product.fromMap(row)).toList();
  }

  Future<List<RawMaterial>> fetchRawMaterialsForProduct(int productId) async {
    final db = await database;
    final rows = await db.query(
      'raw_materials',
      where: 'productId = ?',
      whereArgs: [productId],
    );
    return rows.map((row) => RawMaterial.fromMap(row)).toList();
  }

  Future<List<ProductionTask>> fetchTasks() async {
    final db = await database;
    final rows = await db.query('production_tasks', orderBy: 'plannedDate');
    return rows.map((row) => ProductionTask.fromMap(row)).toList();
  }

  Future<void> updateRawMaterialOrder(int id, bool ordered) async {
    final db = await database;
    await db.update('raw_materials', {'ordered': ordered ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> saveProduct(Product product) async {
    final db = await database;
    if (product.id == null) {
      await db.insert('products', product.toMap());
    } else {
      await db.update('products', product.toMap(), where: 'id = ?', whereArgs: [product.id]);
    }
  }
}
