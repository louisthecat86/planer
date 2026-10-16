import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/database.dart';
import '../../core/providers/backup_provider.dart';
import '../../core/services/backup_service.dart';
import '../../core/theme/app_stil.dart';
import '../../core/ui/bausteine.dart';

class BackupManagementScreen extends ConsumerWidget {
  final AppDatabase database;

  const BackupManagementScreen({
    super.key,
    required this.database,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backupListAsync = ref.watch(refreshableBackupListProvider);
    final isExporting = ref.watch(isExportingProvider);
    final isImporting = ref.watch(isImportingProvider);
    // Schmale Fenster: die Knöpfe der Kopfleiste nur als Symbol.
    final schmal = MediaQuery.sizeOf(context).width < 720;
    // Ohne feste Farbe: Der gesperrte Knopf ist hellgrau, ein weißer
    // Kreisel wäre darauf unsichtbar.
    const kreisel = SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup-Verwaltung'),
        actions: [
          // Die Aktionen oben rechts wie auf den übrigen Seiten — vorher
          // zwei bildschirmbreite Knöpfe über der Liste.
          if (schmal) ...[
            IconButton(
              onPressed:
                  isImporting ? null : () => _handleImport(context, ref),
              icon: isImporting ? kreisel : const Icon(Icons.restore),
              tooltip: 'Backup laden',
            ),
            IconButton(
              onPressed:
                  isExporting ? null : () => _handleExport(context, ref),
              icon: isExporting ? kreisel : const Icon(Icons.backup_outlined),
              tooltip: 'Backup erstellen',
            ),
          ] else ...[
            OutlinedButton.icon(
              onPressed:
                  isImporting ? null : () => _handleImport(context, ref),
              icon: isImporting
                  ? kreisel
                  : const Icon(Icons.restore, size: 18),
              label: const Text('Backup laden …'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed:
                  isExporting ? null : () => _handleExport(context, ref),
              icon: isExporting
                  ? kreisel
                  : const Icon(Icons.backup_outlined, size: 18),
              label: const Text('Backup erstellen'),
            ),
          ],
          const SizedBox(width: 12),
        ],
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
    if (backups.isEmpty) {
      return const Center(
        child: LeerHinweis(
          'Keine Backups vorhanden.',
          icon: Icons.backup_outlined,
        ),
      );
    }
    // Die Backups als Tabelle in einem Bereich — vorher eine Karte je
    // Backup mit bunten Symbolen.
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: [
        Bereich(
          titel: 'Backups',
          untertitel: '${backups.length}',
          innenAbstand: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < backups.length; i++)
                _buildBackupListItem(
                  context,
                  ref,
                  backups[i],
                  letzte: i == backups.length - 1,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBackupListItem(
    BuildContext context,
    WidgetRef ref,
    BackupInfo backup, {
    required bool letzte,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hinweis = backup.versionsHinweis;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        border: letzte
            ? null
            : Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          Tooltip(
            message: backup.isAuto
                ? 'Automatisch gesichert'
                : 'Von Hand gesichert',
            child: Icon(
              backup.isAuto ? Icons.schedule : Icons.backup_outlined,
              size: 18,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  backup.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${backup.formattedTimestamp} • ${backup.formattedSize} • '
                  'Version ${backup.version}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (hinweis != null)
                  Text(
                    hinweis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: AppFarben.von(context).warnung,
                    ),
                  ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Aktionen',
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
                    Icon(Icons.restore, size: 18),
                    SizedBox(width: 8),
                    Text('Laden …'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 18),
                    SizedBox(width: 8),
                    Text('Löschen …'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget(Object error) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        HinweisBox(
          error.toString(),
          art: StatusArt.fehler,
          titel: 'Fehler beim Laden der Backups',
          auswaehlbar: true,
        ),
      ],
    );
  }

  void _handleExport(BuildContext context, WidgetRef ref) async {
    final isExporting = ref.read(isExportingProvider);
    if (isExporting) return;

    ref.read(isExportingProvider.notifier).state = true;

    try {
      final path = await BackupService.exportBackup(database);

      if (path == null) {
        // Nutzer hat den Dialog abgebrochen.
        ref.read(isExportingProvider.notifier).state = false;
        return;
      }

      // Refresh die Backup-Liste
      ref.invalidate(refreshableBackupListProvider);

      if (context.mounted) {
        _showSuccessSnackbar(
          context,
          '✓ Backup erfolgreich gespeichert in:\n$path',
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
        final shouldImport = await _frageLaden(context);
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
    final confirmation = await _frageLaden(context);

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

  /// Fragt vor dem Laden eines Backups nach — es ersetzt alle Daten.
  Future<bool?> _frageLaden(BuildContext context) {
    return showDialog<bool>(
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
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Laden'),
          ),
        ],
      ),
    );
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
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen'),
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
    // Erfolg in der normalen Farbe der Meldungen — vorher knallgrün.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackbar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppFarben.von(context).fehler,
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
