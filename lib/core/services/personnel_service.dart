import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../constants/abteilungen.dart';

class PersonnelService {
  static const String _fileName = 'personnel_plan.json';
  static const _uuid = Uuid();

  static Future<File> _getPlanFile() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final file = File('${appDocDir.path}/$_fileName');
    if (!await file.exists()) {
      await file.create(recursive: true);
      await file.writeAsString(jsonEncode(PersonnelPlan.defaultPlan().toJson()));
    }
    return file;
  }

  static Future<PersonnelPlan> loadPlan() async {
    try {
      final file = await _getPlanFile();
      final contents = await file.readAsString();
      final jsonMap = jsonDecode(contents) as Map<String, dynamic>;
      return PersonnelPlan.fromJson(jsonMap);
    } catch (_) {
      return PersonnelPlan.defaultPlan();
    }
  }

  static Future<void> savePlan(PersonnelPlan plan) async {
    final file = await _getPlanFile();
    await file.writeAsString(jsonEncode(plan.toJson()), flush: true);
  }

  static String createId() => _uuid.v4();
}

class PersonnelPlan {
  PersonnelPlan({required this.employees, required this.vacations});

  final List<Employee> employees;
  final List<VacationEntry> vacations;

  Map<String, dynamic> toJson() {
    return {
      'employees': employees.map((e) => e.toJson()).toList(),
      'vacations': vacations.map((v) => v.toJson()).toList(),
    };
  }

  factory PersonnelPlan.fromJson(Map<String, dynamic> json) {
    final employees = (json['employees'] as List?)
            ?.cast<Map<String, dynamic>>()
            .map(Employee.fromJson)
            .toList() ??
        [];
    final vacations = (json['vacations'] as List?)
            ?.cast<Map<String, dynamic>>()
            .map(VacationEntry.fromJson)
            .toList() ??
        [];

    return PersonnelPlan(employees: employees, vacations: vacations);
  }

  factory PersonnelPlan.defaultPlan() {
    return PersonnelPlan(
      employees: [
        Employee(
          id: PersonnelService.createId(),
          name: 'Anna',
          department: Abteilung.zerlegung.dbValue,
        ),
        Employee(
          id: PersonnelService.createId(),
          name: 'Ben',
          department: Abteilung.wurstkueche.dbValue,
        ),
        Employee(
          id: PersonnelService.createId(),
          name: 'Carla',
          department: Abteilung.bratstrasse.dbValue,
        ),
        Employee(
          id: PersonnelService.createId(),
          name: 'Daniel',
          department: Abteilung.schneideabteilung.dbValue,
        ),
        Employee(
          id: PersonnelService.createId(),
          name: 'Eva',
          department: Abteilung.verpackung.dbValue,
        ),
        Employee(
          id: PersonnelService.createId(),
          name: 'Frank',
          department: Abteilung.verpackungTef1.dbValue,
        ),
      ],
      vacations: [],
    );
  }
}

class Employee {
  Employee({
    required this.id,
    required this.name,
    required this.department,
    this.arbeitsBeginn = '06:00',
    this.arbeitsEnde = '14:00',
    this.wochentage = const [1, 2, 3, 4, 5],
  });

  final String id;
  final String name;
  final String department;

  /// Arbeitsbeginn im Format 'HH:mm'.
  final String arbeitsBeginn;

  /// Arbeitsende im Format 'HH:mm'.
  final String arbeitsEnde;

  /// Arbeitstage (1 = Mo, 2 = Di, ..., 7 = So).
  final List<int> wochentage;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'department': department,
        'arbeitsBeginn': arbeitsBeginn,
        'arbeitsEnde': arbeitsEnde,
        'wochentage': wochentage,
      };

  factory Employee.fromJson(Map<String, dynamic> json) {
    return Employee(
      id: json['id'] as String,
      name: json['name'] as String,
      department: json['department'] as String,
      arbeitsBeginn: json['arbeitsBeginn'] as String? ?? '06:00',
      arbeitsEnde: json['arbeitsEnde'] as String? ?? '14:00',
      wochentage: (json['wochentage'] as List?)?.cast<int>() ?? [1, 2, 3, 4, 5],
    );
  }
}

class VacationEntry {
  VacationEntry({
    required this.id,
    required this.employeeId,
    required this.fromDate,
    required this.toDate,
    required this.reason,
  });

  final String id;
  final String employeeId;
  final DateTime fromDate;
  final DateTime toDate;
  final String reason;

  bool overlapsDate(DateTime date) {
    final target = DateTime(date.year, date.month, date.day);
    return !target.isBefore(_stripTime(fromDate)) &&
        !target.isAfter(_stripTime(toDate));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'employeeId': employeeId,
        'fromDate': fromDate.toIso8601String(),
        'toDate': toDate.toIso8601String(),
        'reason': reason,
      };

  factory VacationEntry.fromJson(Map<String, dynamic> json) {
    return VacationEntry(
      id: json['id'] as String,
      employeeId: json['employeeId'] as String,
      fromDate: DateTime.parse(json['fromDate'] as String),
      toDate: DateTime.parse(json['toDate'] as String),
      reason: json['reason'] as String,
    );
  }
}

DateTime _stripTime(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}
