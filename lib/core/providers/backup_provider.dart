import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../database/database.dart';
import '../services/backup_service.dart';

// ============================================================================
// Datenbank-Provider (muss vorhanden sein)
// ============================================================================

// Annahme: Die Datenbank ist über einen anderen Provider verfügbar
// Falls nicht, bitte anpassen und hier referenzieren:
// final databaseProvider = Provider((ref) => AppDatabase());

// ============================================================================
// BACKUP-STATE PROVIDERS
// ============================================================================

/// Liste aller verfügbaren Backups.
final backupListProvider = FutureProvider<List<BackupInfo>>((ref) async {
  return BackupService.listBackups();
});

/// Refresh-Trigger für Backup-Liste.
final backupRefreshProvider = StateProvider<int>((ref) => 0);

/// Abhängig von backupRefreshProvider, um auf Änderungen zu reagieren.
final refreshableBackupListProvider = FutureProvider<List<BackupInfo>>((ref) {
  // trigger wird beobachtet, daher wird dieser Provider neu berechnet
  // wenn sich der Refresh-Trigger ändert
  ref.watch(backupRefreshProvider);
  return BackupService.listBackups();
});

// ============================================================================
// ASYNC OPERATIONS
// ============================================================================

/// Export-Operation mit Status.
final backupExportProvider =
    FutureProvider.family<String, AppDatabase>((ref, database) async {
  return BackupService.exportBackup(database);
});

/// Auto-Backup-Operation.
final autoBackupProvider =
    FutureProvider.family<String, AppDatabase>((ref, database) async {
  return BackupService.createAutoBackup(database);
});

/// Import-Operation.
final backupImportProvider = FutureProvider.family<void, (AppDatabase, String, bool)>((ref, params) async {
  final (database, filepath, clearExisting) = params;
  await BackupService.importBackup(filepath, database, clearExisting: clearExisting);
  
  // Refresh die Backup-Liste nach erfolgreichem Import
  ref.invalidate(refreshableBackupListProvider);
});

/// Delete-Operation.
final backupDeleteProvider = FutureProvider.family<void, String>((ref, filepath) async {
  await BackupService.deleteBackup(filepath);
  
  // Refresh die Backup-Liste
  final backupRefresh = ref.read(backupRefreshProvider.notifier);
  backupRefresh.state++;
});

// ============================================================================
// UI-STATE
// ============================================================================

/// Zeigt ob gerade ein Export läuft.
final isExportingProvider = StateProvider<bool>((ref) => false);

/// Zeigt ob gerade ein Import läuft.
final isImportingProvider = StateProvider<bool>((ref) => false);

/// Fehler-Nachricht beim Backup.
final backupErrorProvider = StateProvider<String?>((ref) => null);

/// Erfolgs-Nachricht beim Backup.
final backupSuccessProvider = StateProvider<String?>((ref) => null);

// ============================================================================
// NOTIFIERS FÜR KOMPLEXERE LOGIK
// ============================================================================

/// Notifier für Export-Aktion mit Error-Handling.
final backupExportNotifierProvider =
    StateNotifierProvider<BackupExportNotifier, AsyncValue<String>>((ref) {
  return BackupExportNotifier();
});

class BackupExportNotifier extends StateNotifier<AsyncValue<String>> {
  BackupExportNotifier() : super(const AsyncValue.data(''));

  Future<void> export(AppDatabase database) async {
    state = const AsyncValue.loading();
    try {
      final path = await BackupService.exportBackup(database);
      state = AsyncValue.data(path);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

/// Notifier für Import-Aktion mit Error-Handling.
final backupImportNotifierProvider =
    StateNotifierProvider<BackupImportNotifier, AsyncValue<void>>((ref) {
  return BackupImportNotifier();
});

class BackupImportNotifier extends StateNotifier<AsyncValue<void>> {
  BackupImportNotifier() : super(const AsyncValue.data(null));

  Future<void> import(
    AppDatabase database,
    String filepath, {
    bool clearExisting = true,
  }) async {
    state = const AsyncValue.loading();
    try {
      await BackupService.importBackup(
        filepath,
        database,
        clearExisting: clearExisting,
      );
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

/// Notifier für Backup-Löschung.
final backupDeleteNotifierProvider =
    StateNotifierProvider<BackupDeleteNotifier, AsyncValue<void>>((ref) {
  return BackupDeleteNotifier();
});

class BackupDeleteNotifier extends StateNotifier<AsyncValue<void>> {
  BackupDeleteNotifier() : super(const AsyncValue.data(null));

  Future<void> delete(String filepath) async {
    state = const AsyncValue.loading();
    try {
      await BackupService.deleteBackup(filepath);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

// ============================================================================
// HILFSFUNKTIONEN
// ============================================================================

/// File-Picker für Backup-Import.
Future<String?> pickBackupFile() async {
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['planerbackup', 'json'],
      dialogTitle: 'Backup wählen',
    );

    return result?.files.single.path;
  } catch (e) {
    return null;
  }
}
