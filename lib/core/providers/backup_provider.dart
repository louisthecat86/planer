import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/backup_service.dart';

// ============================================================================
// BACKUP-STATE
// ============================================================================

/// Liste aller verfügbaren Backups.
///
/// Hängt am [backupRefreshProvider]: Wer die Liste neu laden will, erhöht
/// dessen Zähler oder ruft `ref.invalidate(refreshableBackupListProvider)`.
final refreshableBackupListProvider =
    FutureProvider<List<BackupInfo>>((ref) async {
  ref.watch(backupRefreshProvider);
  return BackupService.listBackups();
});

/// Refresh-Trigger für die Backup-Liste.
final backupRefreshProvider = StateProvider<int>((ref) => 0);

// ============================================================================
// UI-STATE
// ============================================================================

/// Zeigt an, ob gerade ein Export läuft.
final isExportingProvider = StateProvider<bool>((ref) => false);

/// Zeigt an, ob gerade ein Import läuft.
final isImportingProvider = StateProvider<bool>((ref) => false);

// ============================================================================
// HILFSFUNKTIONEN
// ============================================================================

/// File-Picker für den Backup-Import. Gibt den Pfad zurück, oder null bei
/// Abbruch beziehungsweise wenn die Plattform keinen Pfad liefert.
Future<String?> pickBackupFile() async {
  try {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['planerbackup', 'json'],
      dialogTitle: 'Backup wählen',
    );

    return result?.files.single.path;
  } catch (_) {
    return null;
  }
}
