import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';

/// Singleton-Provider für die [AppDatabase].
///
/// Die Datenbank wird beim ersten Zugriff lazy geöffnet und für die Lebensdauer
/// der App offen gehalten. Wird die App beendet, wird [AppDatabase.close]
/// nicht aufgerufen — SQLite schließt den File-Handle ordnungsgemäß beim
/// Prozess-Exit.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
