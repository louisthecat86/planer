import 'dart:io';

import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/navision_import_service.dart';

Future<void> main() async {
  final db = AppDatabase();
  try {
    final bytes = await File('Artikel11.xlsx').readAsBytes();
    print('bytes ${bytes.length}');
    final service = NavisionImportService(db);
    final res = await service.importiere(bytes);
    print('RESULT: gelesen=${res.gelesen} uebernommen=${res.uebernommen} mitAuftrag=${res.mitAuftrag} warnungen=${res.warnungen.length}');
    final rows = await db.select(db.navisionArtikelKatalog).get();
    print('DB rows ${rows.length}');
    if (rows.isNotEmpty) {
      final first = rows.first;
      print('first: ${first.nummer} | ${first.beschreibung} | bestand=${first.lagerbestand} | auftrag=${first.mengeInAuftrag}');
    }
  } catch (e, st) {
    print('ERROR: $e');
    print(st);
  } finally {
    await db.close();
  }
}
