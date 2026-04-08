import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../constants/abteilungen.dart';

class DepartmentCapacityService {
  static const String _fileName = 'department_capacities.json';
  static const double defaultCapacityMinutes = 480;

  static Future<File> _getCapacityFile() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final file = File('${appDocDir.path}/$_fileName');
    if (!await file.exists()) {
      await file.create(recursive: true);
      await file.writeAsString(jsonEncode(_defaultCapacities()));
    }
    return file;
  }

  static Map<String, double> _defaultCapacities() {
    return Map.fromEntries(
      Abteilung.values.map(
        (abteilung) => MapEntry(abteilung.dbValue, defaultCapacityMinutes),
      ),
    );
  }

  static Future<Map<String, double>> loadCapacities() async {
    try {
      final file = await _getCapacityFile();
      final contents = await file.readAsString();
      final jsonMap = jsonDecode(contents) as Map<String, dynamic>;
      final result = <String, double>{};

      for (final abteilung in Abteilung.values) {
        final raw = jsonMap[abteilung.dbValue];
        result[abteilung.dbValue] = (raw is num) ? raw.toDouble() : defaultCapacityMinutes;
      }

      return result;
    } catch (_) {
      return _defaultCapacities();
    }
  }

  static Future<void> saveCapacities(Map<String, double> capacities) async {
    final file = await _getCapacityFile();
    final jsonMap = capacities.map((key, value) => MapEntry(key, value));
    await file.writeAsString(jsonEncode(jsonMap), flush: true);
  }
}
