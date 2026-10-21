import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/services/backup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests für den selbst gewählten Backup-Ordner nach dem neuen
/// Programmnamen: Unter Windows lagen die Einstellungen bisher in
/// `%APPDATA%\com.example\produktion_planer`. Die Pfade sind erfunden.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory appData;

  setUp(() async {
    appData = await Directory.systemTemp.createTemp('planer_appdata_');
  });

  tearDown(() async {
    if (await appData.exists()) await appData.delete(recursive: true);
  });

  /// Die Einstellungsdatei unter dem alten Namen, so wie
  /// shared_preferences sie unter Windows schreibt.
  Future<void> alteEinstellungen(String inhalt) async {
    final ordner = Directory(
      [appData.path, 'com.example', 'produktion_planer']
          .join(Platform.pathSeparator),
    );
    await ordner.create(recursive: true);
    await File(
      [ordner.path, 'shared_preferences.json'].join(Platform.pathSeparator),
    ).writeAsString(inhalt);
  }

  Future<SharedPreferences> einstellungen([
    Map<String, Object> werte = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(werte);
    return SharedPreferences.getInstance();
  }

  group('Backup-Ordner aus der Zeit vor dem neuen Programmnamen', () {
    test('wird übernommen', () async {
      await alteEinstellungen(
        jsonEncode({
          'flutter.backup_verzeichnis': r'D:\Sicherung\Planer ',
          'flutter.anderes': 'bleibt',
        }),
      );
      final prefs = await einstellungen();
      await BackupService.alteEinstellungUebernehmen(
        prefs,
        appData: appData.path,
      );
      expect(prefs.getString('backup_verzeichnis'), r'D:\Sicherung\Planer');
      expect(prefs.getString('anderes'), isNull);
    });

    test('nur einmal — ein danach gewählter Standard bleibt', () async {
      await alteEinstellungen(
        jsonEncode({'flutter.backup_verzeichnis': r'D:\Sicherung'}),
      );
      final prefs = await einstellungen();
      await BackupService.alteEinstellungUebernehmen(
        prefs,
        appData: appData.path,
      );
      expect(prefs.getString('backup_verzeichnis'), r'D:\Sicherung');

      // Zurück auf den Standard: Der alte Pfad kommt nicht wieder.
      await prefs.remove('backup_verzeichnis');
      await BackupService.alteEinstellungUebernehmen(
        prefs,
        appData: appData.path,
      );
      expect(prefs.getString('backup_verzeichnis'), isNull);
    });

    test('ein schon gewählter Ordner bleibt', () async {
      await alteEinstellungen(
        jsonEncode({'flutter.backup_verzeichnis': r'D:\Alt'}),
      );
      final prefs = await einstellungen({'backup_verzeichnis': r'E:\Neu'});
      await BackupService.alteEinstellungUebernehmen(
        prefs,
        appData: appData.path,
      );
      expect(prefs.getString('backup_verzeichnis'), r'E:\Neu');
    });

    test('ohne alte Einstellungen bleibt es beim Standard', () async {
      final prefs = await einstellungen();
      await BackupService.alteEinstellungUebernehmen(
        prefs,
        appData: appData.path,
      );
      expect(prefs.getString('backup_verzeichnis'), isNull);
    });

    test('eine kaputte oder leere alte Datei schadet nicht', () async {
      for (final inhalt in [
        '{kaputt',
        '[]',
        jsonEncode({'flutter.backup_verzeichnis': '   '}),
        jsonEncode({'flutter.backup_verzeichnis': 42}),
      ]) {
        await alteEinstellungen(inhalt);
        final prefs = await einstellungen();
        await BackupService.alteEinstellungUebernehmen(
          prefs,
          appData: appData.path,
        );
        expect(
          prefs.getString('backup_verzeichnis'),
          isNull,
          reason: inhalt,
        );
      }
    });
  });
}
