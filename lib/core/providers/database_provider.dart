import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';

/// Singleton-Provider für die [AppDatabase].
///
/// Die Datenbank wird beim ersten Zugriff lazy geöffnet und für die Lebensdauer
/// der App offen gehalten. Vor dem App-Beenden wird [AppDatabase.close]
/// explizit aufgerufen (siehe `home_screen.dart`/`app.dart`) — ohne das
/// saubere Schließen der auf einem eigenen Isolate laufenden
/// SQLite-Verbindung stürzte die App auf Windows beim Beenden ab.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
