import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';
import 'database_provider.dart';

/// Schlüssel für den Anzeigemodus in der `app_settings`-Tabelle.
const String kThemeModeSettingKey = 'theme_mode';

/// Hält den Hell-/Dunkelmodus und speichert ihn dauerhaft.
///
/// Vorher war der Windows-Build fest auf Dunkel verdrahtet. Jetzt wählt
/// jeder selbst — die Einstellung gilt pro Installation (sie liegt in der
/// lokalen Datenbank und wandert damit auch ins Backup).
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(this._db) : super(_standard()) {
    _laden();
  }

  final AppDatabase _db;

  /// Ohne gespeicherte Wahl: Windows startet dunkel (so kannte es das
  /// Team bisher), alle anderen folgen dem Betriebssystem.
  static ThemeMode _standard() =>
      Platform.isWindows ? ThemeMode.dark : ThemeMode.system;

  Future<void> _laden() async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(kThemeModeSettingKey))
          ..limit(1))
        .getSingleOrNull();
    final gespeichert = _ausText(row?.value);
    if (gespeichert != null) state = gespeichert;
  }

  static ThemeMode? _ausText(String? wert) {
    switch (wert) {
      case 'hell':
        return ThemeMode.light;
      case 'dunkel':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return null;
    }
  }

  static String _zuText(ThemeMode modus) {
    switch (modus) {
      case ThemeMode.light:
        return 'hell';
      case ThemeMode.dark:
        return 'dunkel';
      case ThemeMode.system:
        return 'system';
    }
  }

  Future<void> setzen(ThemeMode modus) async {
    if (modus == state) return;
    state = modus;
    await _speichern(modus);
  }

  Future<void> _speichern(ThemeMode modus) async {
    final txt = _zuText(modus);
    final vorhanden = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(kThemeModeSettingKey))
          ..limit(1))
        .getSingleOrNull();
    if (vorhanden == null) {
      await _db.into(_db.appSettings).insert(
            AppSettingsCompanion(
              key: const Value(kThemeModeSettingKey),
              value: Value(txt),
            ),
          );
    } else {
      await (_db.update(_db.appSettings)
            ..where((t) => t.key.equals(kThemeModeSettingKey)))
          .write(
        AppSettingsCompanion(
          value: Value(txt),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  final db = ref.watch(databaseProvider);
  return ThemeModeNotifier(db);
});
