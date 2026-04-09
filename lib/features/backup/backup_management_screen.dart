import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/database.dart';
import '../../core/providers/backup_provider.dart';
import '../../core/services/backup_service.dart';

class BackupManagementScreen extends ConsumerWidget {
  final AppDatabase database;

  const BackupManagementScreen({
    super.key,
    required this.database,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backupListAsync = ref.watch(refreshableBackupListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup-Verwaltung'),
        centerTitle: true,
      ),
      body: backupListAsync.when(
        data: (backups) => _buildContent(context, ref, backups),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _buildErrorWidget(error),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    List<BackupInfo> backups,
  ) {
    final isExporting = ref.watch(isExportingProvider);
    final isImporting = ref.watch(isImportingProvider);

    return Column(
      children: [
        // Header mit Aktions-Buttons
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Backup erstellen
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: isExporting ? null : () => _handleExport(context, ref),
                  icon: isExporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.backup),
                  label: const Text('Backup erstellen'),
                ),
              ),
              const SizedBox(height: 12),
              // Backup laden
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: isImporting ? null : () => _handleImport(context, ref),
                  icon: isImporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.restore),
                  label: const Text('Backup laden'),
                ),
              ),
            ],
          ),
        ),
        // Trennlinie
        const Divider(height: 0),
        // Backup-Liste
        Expanded(
          child: backups.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.backup_outlined, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('Keine Backups vorhanden'),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: backups.length,
                  itemBuilder: (context, index) => _buildBackupListItem(
                    context,
                    ref,
                    backups[index],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildBackupListItem(
    BuildContext context,
    WidgetRef ref,
    BackupInfo backup,
  ) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: Icon(
          backup.isAuto ? Icons.schedule : Icons.backup,
          color: backup.isAuto ? Colors.orange : Colors.blue,
        ),
        title: Text(backup.filename),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('${backup.formattedTimestamp} • ${backup.formattedSize}'),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'load') {
              _handleLoadBackup(context, ref, backup.filepath);
            } else if (value == 'delete') {
              _handleDeleteBackup(context, ref, backup.filepath);
            }
          },
          itemBuilder: (BuildContext context) => [
            const PopupMenuItem<String>(
              value: 'load',
              child: Row(
                children: [
                  Icon(Icons.restore, color: Colors.green),
                  SizedBox(width: 8),
                  Text('Laden'),
                ],
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem<String>(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Löschen'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget(Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Fehler beim Laden der Backups',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  void _handleExport(BuildContext context, WidgetRef ref) async {
    final isExporting = ref.read(isExportingProvider);
    if (isExporting) return;

    ref.read(isExportingProvider.notifier).state = true;

    try {
      final path = await BackupService.exportBackup(database);

      // Refresh die Backup-Liste
      ref.invalidate(refreshableBackupListProvider);

      if (context.mounted) {
        _showSuccessSnackbar(
          context,
          '✓ Backup erfolgreich erstellt in:\n$path',
        );
      }
    } catch (e) {
      if (context.mounted) {
        _showErrorSnackbar(context, 'Fehler beim Export: $e');
      }
    } finally {
      ref.read(isExportingProvider.notifier).state = false;
    }
  }

  void _handleImport(BuildContext context, WidgetRef ref) async {
    final isImporting = ref.read(isImportingProvider);
    if (isImporting) return;

    try {
      final filepath = await pickBackupFile();
      if (filepath == null) return; // User cancelled

      if (context.mounted) {
        // Bestätigung vor dem Import
        final shouldImport = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Backup laden'),
            content: const Text(
              'Dies wird die aktuellen Daten ersetzen. '
              'Möchtest du fortfahren?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Abbrechen'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Laden'),
              ),
            ],
          ),
        );

        if (shouldImport != true) return;
      }

      ref.read(isImportingProvider.notifier).state = true;

      await BackupService.importBackup(filepath, database, clearExisting: true);

      // Refresh die Backup-Liste
      ref.invalidate(refreshableBackupListProvider);

      if (context.mounted) {
        _showSuccessSnackbar(context, '✓ Backup erfolgreich geladen');
      }
    } catch (e) {
      if (context.mounted) {
        _showErrorSnackbar(context, 'Fehler beim Import: $e');
      }
    } finally {
      ref.read(isImportingProvider.notifier).state = false;
    }
  }

  void _handleLoadBackup(
    BuildContext context,
    WidgetRef ref,
    String filepath,
  ) async {
    final confirmation = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Backup laden'),
        content: const Text(
          'Dies wird die aktuellen Daten ersetzen. '
          'Möchtest du fortfahren?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Laden'),
          ),
        ],
      ),
    );

    if (confirmation != true) return;

    try {
      await BackupService.importBackup(filepath, database, clearExisting: true);
      ref.invalidate(refreshableBackupListProvider);

      if (context.mounted) {
        _showSuccessSnackbar(context, '✓ Backup erfolgreich geladen');
      }
    } catch (e) {
      if (context.mounted) {
        _showErrorSnackbar(context, 'Fehler beim Laden: $e');
      }
    }
  }

  void _handleDeleteBackup(
    BuildContext context,
    WidgetRef ref,
    String filepath,
  ) async {
    final confirmation = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Backup löschen'),
        content: const Text('Möchtest du dieses Backup wirklich löschen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmation != true) return;

    try {
      await BackupService.deleteBackup(filepath);
      
      // Trigger die Backup-Liste zum Refresh
      ref.read(backupRefreshProvider.notifier).state++;

      if (context.mounted) {
        _showSuccessSnackbar(context, '✓ Backup gelöscht');
      }
    } catch (e) {
      if (context.mounted) {
        _showErrorSnackbar(context, 'Fehler beim Löschen: $e');
      }
    }
  }

  void _showSuccessSnackbar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackbar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
