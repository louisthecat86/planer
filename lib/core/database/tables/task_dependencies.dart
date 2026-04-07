import 'package:drift/drift.dart';
import 'production_tasks.dart';

/// Explizite Abhängigkeiten zwischen Produktions-Tasks.
///
/// Wird zusätzlich zu [ProductionTasks.parentTaskId] verwendet, wenn
/// **auftragsübergreifende** Abhängigkeiten bestehen (z.B. "Task A in
/// der Wurstküche muss erst fertig sein, bevor Task B in der Bratstraße
/// startet, obwohl sie zu unterschiedlichen Produkten gehören").
///
/// Wenn die Abhängigkeit rein produkt-intern ist (vorgelagerter Schritt
/// desselben Produkts), reicht [ProductionTasks.parentTaskId] und hier
/// muss nichts eingetragen werden.
class TaskDependencies extends Table {
  TextColumn get id => text()();

  /// Der Task, der wartet.
  TextColumn get fromTaskId => text().references(ProductionTasks, #id)();

  /// Der Task, auf den gewartet wird.
  TextColumn get toTaskId => text().references(ProductionTasks, #id)();

  /// Typ der Abhängigkeit. Erlaubte Werte: 'finish_to_start' (Standard),
  /// 'start_to_start', 'finish_to_finish'. Im Fleischbereich reicht
  /// typischerweise 'finish_to_start'.
  TextColumn get typ =>
      text().withDefault(const Constant('finish_to_start'))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
