import 'dart:io';

import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/navision_import_service.dart';

Future<void> main() async {
  final db = AppDatabase();
  try {
    final bytes = await File('Artikel11.xlsx').readAsBytes();
    stdout.writeln('bytes ${bytes.length}');
    final service = NavisionImportService(db);
    final res = await service.importiere(bytes);
    stdout.writeln(
      'RESULT: gelesen=${res.gelesen} uebernommen=${res.uebernommen} '
      'mitAuftrag=${res.mitAuftrag} warnungen=${res.warnungen.length}',
    );
    final rows = await db.select(db.navisionArtikelKatalog).get();
    stdout.writeln('DB rows ${rows.length}');
    if (rows.isNotEmpty) {
      final first = rows.first;
      stdout.writeln(
        'first: ${first.nummer} | ${first.beschreibung} | '
        'bestand=${first.lagerbestand} | auftrag=${first.mengeInAuftrag}',
      );
    }
  } catch (e, st) {
    stdout.writeln('ERROR: $e');
    stdout.writeln(st);
  } finally {
    await db.close();
  }
}
