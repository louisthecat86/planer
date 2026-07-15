import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';
import 'database_provider.dart';

/// Schlüssel für die Skalierung in der `app_settings`-Tabelle.
const String kUiScaleSettingKey = 'ui_scale';

/// Standard-Skalierung (100 %). Vorher war die App fest auf 115 % — der
/// Grund, warum Schrift und Kacheln groß wirkten. Jetzt ist 100 % der
/// Ausgangspunkt, und jeder stellt sich seine Größe selbst ein.
const double kUiScaleDefault = 1.0;

/// Wählbare Stufen — vom Nutzer gewünschte Spanne 25 %…200 %.
const List<double> kUiScaleStufen = [
  0.25,
  0.5,
  0.75,
  1.0,
  1.25,
  1.5,
  1.75,
  2.0,
];

/// Hält die app-weite UI-Skalierung und schreibt Änderungen dauerhaft in
/// die Datenbank. Wird in `app.dart` an `MediaQuery.textScaler` gehängt und
/// wirkt damit auf die gesamte Schrift der App.
class UiScaleNotifier extends StateNotifier<double> {
  UiScaleNotifier(this._db) : super(kUiScaleDefault) {
    _laden();
  }

  final AppDatabase _db;

  Future<void> _laden() async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(kUiScaleSettingKey))
          ..limit(1))
        .getSingleOrNull();
    final gespeichert = double.tryParse(row?.value ?? '');
    if (gespeichert != null && _gueltig(gespeichert)) {
      state = gespeichert;
    }
  }

  bool _gueltig(double v) => v >= 0.25 && v <= 2.0;

  /// Setzt eine neue Skalierung (auf die erlaubte Spanne begrenzt) und
  /// speichert sie.
  Future<void> setzen(double wert) async {
    final geklemmt = wert.clamp(0.25, 2.0).toDouble();
    if (geklemmt == state) return;
    state = geklemmt;
    await _speichern(geklemmt);
  }

  /// Eine Stufe größer (für den +-Knopf).
  Future<void> groesser() => _stufe(1);

  /// Eine Stufe kleiner (für den −-Knopf).
  Future<void> kleiner() => _stufe(-1);

  Future<void> _stufe(int richtung) async {
    // Nächstgelegene Stufe zum aktuellen Wert finden, dann verschieben.
    var idx = 0;
    var beste = double.infinity;
    for (var i = 0; i < kUiScaleStufen.length; i++) {
      final d = (kUiScaleStufen[i] - state).abs();
      if (d < beste) {
        beste = d;
        idx = i;
      }
    }
    final ziel = (idx + richtung).clamp(0, kUiScaleStufen.length - 1);
    await setzen(kUiScaleStufen[ziel]);
  }

  Future<void> zuruecksetzen() => setzen(kUiScaleDefault);

  Future<void> _speichern(double wert) async {
    final txt = wert.toString();
    final vorhanden = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(kUiScaleSettingKey))
          ..limit(1))
        .getSingleOrNull();
    if (vorhanden == null) {
      await _db.into(_db.appSettings).insert(
            AppSettingsCompanion(
              key: Value(kUiScaleSettingKey),
              value: Value(txt),
            ),
          );
    } else {
      await (_db.update(_db.appSettings)
            ..where((t) => t.key.equals(kUiScaleSettingKey)))
          .write(
        AppSettingsCompanion(
          value: Value(txt),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }
}

final uiScaleProvider =
    StateNotifierProvider<UiScaleNotifier, double>((ref) {
  final db = ref.watch(databaseProvider);
  return UiScaleNotifier(db);
});
