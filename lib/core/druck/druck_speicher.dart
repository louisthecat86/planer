import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/database.dart';

/// Merkt sich je Art von Dokument, womit zuletzt gedruckt wurde — in den
/// Einstellungen der Datenbank, also auch in jeder Sicherung.
///
/// Gemerkt wird beim Drucken und Speichern, nicht bei jedem Klick: Wer
/// nur ausprobiert und abbricht, behält seine Einstellungen.
const String kDruckEinstellungPraefix = 'druck.';

/// Die gemerkten Einstellungen zu [art] — null: noch keine, oder sie
/// lassen sich nicht lesen.
Future<Object?> druckEinstellungLaden(AppDatabase db, String art) async {
  final zeile = await (db.select(db.appSettings)
        ..where((t) => t.key.equals('$kDruckEinstellungPraefix$art'))
        ..limit(1))
      .getSingleOrNull();
  if (zeile == null) return null;
  try {
    return jsonDecode(zeile.value);
  } on FormatException {
    return null;
  }
}

/// Merkt sich [json] für [art].
Future<void> druckEinstellungSpeichern(
  AppDatabase db,
  String art,
  Map<String, Object> json,
) async {
  await db.into(db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: '$kDruckEinstellungPraefix$art',
          value: jsonEncode(json),
          updatedAt: Value(DateTime.now()),
        ),
      );
}
