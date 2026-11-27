import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/artikel_merkmale.dart';
import '../../../core/constants/entwicklung.dart';
import '../../../core/database/database.dart';
import '../../../core/providers/database_provider.dart';

export 'spez_angaben.dart' show kNieAlsSpur, wirksameSpuren;

// ═══════════════════════════════════════════════════════════════════════
// Spuren aus dem Betrieb
//
// Welche Allergene als Spuren in der Spezifikation stehen, hängt nicht am
// einzelnen Produkt, sondern am Betrieb: Was dort verarbeitet wird, kann
// in jedem Produkt als Spur vorkommen. Deshalb gibt es EINE Liste für
// alle Produkte. Die Regel der Allergentabelle:
//
// * enthalten (aus der Rezeptur) → „ja", keine Spur;
// * nicht enthalten → „nein" — und „Spuren", wenn der Betrieb das
//   Allergen verarbeitet;
// * Sulfit ist nie eine Spur.
//
// Was ein Produkt enthält, kommt aus den Zutaten seiner Rezeptur — dort
// wird das wirklich enthaltene Allergen gewählt, nie die Spur. Mit der
// Freigabe bekommt der Artikel genau diese Allergene.
// ═══════════════════════════════════════════════════════════════════════

/// Unter diesem Schlüssel steht in `app_settings`, welche Allergene der
/// Betrieb verarbeitet (JSON-Liste der dbValues). Geht mit ins Backup.
const String kBetriebsSpurenSchluessel = '${kEntwicklungPraefix}betrieb_spuren';

/// Die Allergene, die der Betrieb verarbeitet.
///
/// Solange nichts gespeichert ist, gilt [kBetriebsSpurenStandard] — man
/// muss nichts anhaken.
Future<Set<String>> ladeBetriebsSpuren(AppDatabase db) async {
  final zeile = await (db.select(db.appSettings)
        ..where((s) => s.key.equals(kBetriebsSpurenSchluessel)))
      .getSingleOrNull();
  return betriebsSpurenAusText(zeile?.value);
}

/// Ab Werk: die Allergene, die üblicherweise im Betrieb verarbeitet werden
/// — alle Allergene der Tabelle außer Sulfit. Krebstiere, Fisch,
/// Erdnüsse, Lupinen und Weichtiere werden nicht verarbeitet.
const Set<String> kBetriebsSpurenStandard = {
  'gluten',
  'eier',
  'soja',
  'milch',
  'schalenfruechte',
  'sellerie',
  'senf',
  'sesam',
};

/// Liest die gespeicherte Liste — Unbekanntes fällt weg. Nichts
/// gespeichert: [kBetriebsSpurenStandard]. Eine gespeicherte leere Liste
/// bleibt leer.
Set<String> betriebsSpurenAusText(String? text) {
  if (text == null || text.trim().isEmpty) return kBetriebsSpurenStandard;
  try {
    final liste = jsonDecode(text);
    if (liste is! List) return {};
    final bekannt = {for (final m in kAllergene) m.dbValue};
    return {
      for (final x in liste)
        if (x is String && bekannt.contains(x) && x != kAllergenKeine) x,
    };
  } on FormatException {
    return {};
  }
}

/// Speichert die Liste — auch leer: Dann gibt es keine Spuren.
Future<void> speichereBetriebsSpuren(AppDatabase db, Set<String> spuren) async {
  final sortiert = [
    for (final m in kAllergene)
      if (spuren.contains(m.dbValue)) m.dbValue,
  ];
  await db.into(db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: kBetriebsSpurenSchluessel,
          value: jsonEncode(sortiert),
          updatedAt: Value(DateTime.now()),
        ),
      );
}

/// Die Allergene, die der Betrieb verarbeitet — für Reiter und Etikett.
final betriebsSpurenProvider = FutureProvider<Set<String>>(
  (ref) => ladeBetriebsSpuren(ref.watch(databaseProvider)),
);
