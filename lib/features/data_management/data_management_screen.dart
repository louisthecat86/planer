import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';
import '../../core/services/backup_service.dart';
import '../../core/services/excel_export_service_v3.dart';
import '../../core/services/excel_import_dispatcher.dart';
import '../articles/article_detail_screen.dart';
import '../articles/article_list_screen.dart';

/// Zentraler „Daten verwalten"-Screen.
///
/// Vereint alle Daten-Operationen:
/// - Excel-Import (v3-Vorlage einlesen)
/// - Excel-Export (aktualisierte Excel speichern)
/// - Backup erstellen / wiederherstellen
/// - Speicherort der DB / Backups anzeigen
///
/// Wird über das Datei-Icon in der AppBar aufgerufen.
class DataManagementScreen extends ConsumerStatefulWidget {
  const DataManagementScreen({super.key});

  @override
  ConsumerState<DataManagementScreen> createState() =>
      _DataManagementScreenState();
}

class _DataManagementScreenState
    extends ConsumerState<DataManagementScreen> {
  // ── Allgemeine Status ──────────────────────────────────────────────
  bool _busy = false;
  String? _statusMessage;
  Color _statusColor = Colors.green;

  // ── Import-Detailmeldungen (Fehler + Hinweise des letzten Imports) ──
  List<String> _importFehler = [];
  List<String> _importWarnungen = [];

  // ── Speicherort-Pfade (nur Anzeige) ────────────────────────────────
  String? _datenbankPfad;
  String? _backupPfad;

  // ── Backup-Liste ───────────────────────────────────────────────────
  List<BackupInfo> _backups = [];
  bool _backupsGeladen = false;

  @override
  void initState() {
    super.initState();
    _ladeUebersicht();
  }

  Future<void> _ladeUebersicht() async {
    try {
      final dbDir = await BackupService.getDatabaseDirectoryPath();
      final bDir = await BackupService.getBackupDirectoryPath();
      final backups = await BackupService.listBackups();
      if (mounted) {
        setState(() {
          _datenbankPfad = dbDir;
          _backupPfad = bDir;
          _backups = backups;
          _backupsGeladen = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Fehler beim Laden: $e';
          _statusColor = Colors.red;
        });
      }
    }
  }

  void _setBusy(bool busy, {String? msg, Color color = Colors.green}) {
    if (!mounted) return;
    setState(() {
      _busy = busy;
      _statusMessage = msg;
      _statusColor = color;
      // Beim Start einer neuen Aktion alte Import-Details ausblenden.
      if (busy) {
        _importFehler = [];
        _importWarnungen = [];
      }
    });
  }

  /// Lädt alle Daten-Provider neu, deren Inhalt sich durch Import oder
  /// Backup-Restore geändert haben kann. Ohne dies zeigen Artikelkarte,
  /// Schritte und Historie weiterhin den alten (gecachten) Stand.
  void _invalidiereDatenProvider() {
    ref.invalidate(articlesProvider);
    ref.invalidate(productProvider);
    ref.invalidate(productStepsProvider);
    ref.invalidate(stepParametersProvider);
    ref.invalidate(machineProvider);
    ref.invalidate(productionHistoryProvider);
  }

  // ──────────────────────────────────────────────────────────────────────
  // EXCEL-IMPORT
  // ──────────────────────────────────────────────────────────────────────

  Future<void> _excelImport() async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );
      if (picked == null || picked.files.isEmpty) return;
      final filePath = picked.files.first.path;
      if (filePath == null) return;

      _setBusy(true, msg: 'Excel wird eingelesen …');

      final dispatcher = ExcelImportDispatcher(ref.read(databaseProvider));
      final result = await dispatcher.importFile(filePath);

      _invalidiereDatenProvider();

      // Auto-Backup nach Import — die Excel hat einen großen Datenstand
      // gebracht, der Schutzwert eines Backups ist hier am höchsten.
      ref.read(autoBackupTriggerProvider).fireDebounced(
            reason: 'Excel-Import',
          );

      final fehler = result.fehler;
      final warnungen = result.warnungen;

      _setBusy(
        false,
        msg: result.hatFehler
            ? 'Import mit Fehlern: ${fehler.length} Problem(e) '
                '— Details unten'
            : warnungen.isEmpty
                ? 'Import erfolgreich: ${result.artikelGesamt} Artikel'
                : 'Import: ${result.artikelGesamt} Artikel, '
                    '${warnungen.length} Hinweis(e) — Details unten',
        color: result.hatFehler ? Colors.red : Colors.green,
      );

      // Detailmeldungen anzeigen (auch reine Hinweise ohne Fehler).
      if (mounted) {
        setState(() {
          _importFehler = fehler;
          _importWarnungen = warnungen;
        });
      }

      // Backup-Liste aktualisieren (das frisch erstellte Auto-Backup
      // erscheint nach dem Debounce; wir laden mit kleiner Verzögerung)
      Future.delayed(const Duration(seconds: 5), _ladeUebersicht);
    } catch (e) {
      _setBusy(false, msg: 'Import-Fehler: $e', color: Colors.red);
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // EXCEL-EXPORT
  // ──────────────────────────────────────────────────────────────────────

  Future<void> _excelExport() async {
    try {
      _setBusy(true, msg: 'Excel wird erstellt …');

      final svc = ExcelExportServiceV3(ref.read(databaseProvider));
      final result = await svc.export();

      if (result.hatFehler) {
        _setBusy(
          false,
          msg: 'Export-Fehler: ${result.fehler.first}',
          color: Colors.red,
        );
        return;
      }

      final zielPfad = await FilePicker.saveFile(
        dialogTitle: 'Excel-Export speichern',
        fileName: result.vorschlagDateiname,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (zielPfad == null) {
        _setBusy(false);
        return;
      }

      await File(zielPfad).writeAsBytes(result.bytes);

      final extras = <String>[];
      if (result.artikelSheetsAngelegt > 0) {
        extras.add(
          '${result.artikelSheetsAngelegt} neue Artikel-Sheets angelegt',
        );
      }
      if (result.maschinenInKatalog > 0) {
        extras.add(
          '${result.maschinenInKatalog} Anlagen in den Katalog übernommen',
        );
      }

      _setBusy(
        false,
        msg: 'Excel exportiert: ${result.artikelAktualisiert} Artikel '
            'aktualisiert'
            '${extras.isEmpty ? '' : ' · ${extras.join(' · ')}'}',
      );

      // Export-Hinweise (z.B. Katalog voll) ebenfalls anzeigen.
      if (mounted && result.warnungen.isNotEmpty) {
        setState(() => _importWarnungen = result.warnungen);
      }
    } catch (e) {
      _setBusy(false, msg: 'Export-Fehler: $e', color: Colors.red);
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // BACKUP ERSTELLEN
  // ──────────────────────────────────────────────────────────────────────

  Future<void> _backupErstellenAuto() async {
    try {
      _setBusy(true, msg: 'Backup wird erstellt …');
      final db = ref.read(databaseProvider);
      final pfad = await BackupService.createAutoBackup(db);
      await BackupService.cleanupOldAutoBackups();
      await _ladeUebersicht();
      _setBusy(
        false,
        msg: 'Backup gespeichert: ${pfad.split(Platform.pathSeparator).last}',
      );
    } catch (e) {
      _setBusy(false, msg: 'Backup-Fehler: $e', color: Colors.red);
    }
  }

  Future<void> _backupErstellenManuell() async {
    try {
      _setBusy(true, msg: 'Backup-Datei wird vorbereitet …');
      final db = ref.read(databaseProvider);
      final pfad = await BackupService.exportBackup(db);
      if (pfad == null) {
        _setBusy(false);
        return;
      }
      await _ladeUebersicht();
      _setBusy(
        false,
        msg: 'Backup gespeichert: ${pfad.split(Platform.pathSeparator).last}',
      );
    } catch (e) {
      _setBusy(false, msg: 'Backup-Fehler: $e', color: Colors.red);
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // BACKUP WIEDERHERSTELLEN
  // ──────────────────────────────────────────────────────────────────────

  Future<void> _backupWiederherstellen(BackupInfo info) async {
    final bestaetigt = await _frageBestaetigung(
      titel: 'Backup wiederherstellen?',
      text:
          'Alle aktuellen Daten in der App werden ersetzt durch das Backup '
          'vom ${info.formattedTimestamp}. '
          'Diese Aktion kann nicht rückgängig gemacht werden.',
      confirmText: 'Wiederherstellen',
      destructive: true,
    );
    if (!bestaetigt) return;

    try {
      _setBusy(true, msg: 'Backup wird eingelesen …');
      final db = ref.read(databaseProvider);
      await BackupService.importBackup(info.filepath, db, clearExisting: true);

      _invalidiereDatenProvider();

      // Bewusst KEIN Auto-Backup nach Restore — wir haben gerade von
      // einem Backup wiederhergestellt, ein neues Backup wäre redundant
      // und würde den Restore-Stand nur verdoppeln.

      _setBusy(
        false,
        msg: 'Backup vom ${info.formattedTimestamp} wiederhergestellt',
      );
    } catch (e) {
      _setBusy(false, msg: 'Restore-Fehler: $e', color: Colors.red);
    }
  }

  Future<void> _backupAusDateiWaehlen() async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['planerbackup', 'json'],
      );
      if (picked == null || picked.files.isEmpty) return;
      final filePath = picked.files.first.path;
      if (filePath == null) return;

      final bestaetigt = await _frageBestaetigung(
        titel: 'Backup wiederherstellen?',
        text:
            'Alle aktuellen Daten werden ersetzt durch das Backup aus '
            'der gewählten Datei. Fortfahren?',
        confirmText: 'Wiederherstellen',
        destructive: true,
      );
      if (!bestaetigt) return;

      _setBusy(true, msg: 'Backup wird eingelesen …');
      final db = ref.read(databaseProvider);
      await BackupService.importBackup(filePath, db, clearExisting: true);

      _invalidiereDatenProvider();

      _setBusy(false, msg: 'Backup wiederhergestellt');
    } catch (e) {
      _setBusy(false, msg: 'Restore-Fehler: $e', color: Colors.red);
    }
  }

  Future<void> _backupLoeschen(BackupInfo info) async {
    final bestaetigt = await _frageBestaetigung(
      titel: 'Backup löschen?',
      text:
          'Backup vom ${info.formattedTimestamp} wird unwiderruflich gelöscht.',
      confirmText: 'Löschen',
      destructive: true,
    );
    if (!bestaetigt) return;

    try {
      await BackupService.deleteBackup(info.filepath);
      await _ladeUebersicht();
      _setBusy(false, msg: 'Backup gelöscht');
    } catch (e) {
      _setBusy(false, msg: 'Lösch-Fehler: $e', color: Colors.red);
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // HELPER
  // ──────────────────────────────────────────────────────────────────────

  Future<bool> _frageBestaetigung({
    required String titel,
    required String text,
    required String confirmText,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titel),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: Colors.red)
                : null,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _kopiereInZwischenablage(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pfad kopiert'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // BUILD
  // ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daten verwalten'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Status-Banner ────────────────────────────────────────────
          if (_busy || _statusMessage != null)
            _StatusBanner(
              busy: _busy,
              message: _statusMessage,
              color: _statusColor,
            ),
          if (_busy || _statusMessage != null) const SizedBox(height: 20),

          // ── Import-Detailmeldungen (aufklappbar) ─────────────────────
          if (_importFehler.isNotEmpty || _importWarnungen.isNotEmpty) ...[
            _ImportDetails(
              fehler: _importFehler,
              warnungen: _importWarnungen,
            ),
            const SizedBox(height: 20),
          ],

          // ── Sektion: Excel ───────────────────────────────────────────
          _Sektion(
            icon: Icons.table_chart,
            titel: 'Excel-Vorlage',
            beschreibung:
                'Importiere eine v3-Excel-Vorlage oder exportiere die '
                'aktuellen Daten in deine Vorlage.',
            children: [
              _ActionButton(
                icon: Icons.upload_file,
                label: 'Excel-Datei importieren',
                onPressed: _busy ? null : _excelImport,
              ),
              const SizedBox(height: 8),
              _ActionButton(
                icon: Icons.save_alt,
                label: 'Excel exportieren',
                onPressed: _busy ? null : _excelExport,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Sektion: Backup erstellen ────────────────────────────────
          _Sektion(
            icon: Icons.backup,
            titel: 'Backup',
            beschreibung:
                'Sichere die kompletten App-Daten (Artikel, Schritte, '
                'Anlagen, Pläne) als JSON-Datei. Ein Backup enthält den '
                'gesamten Datenstand und kann jederzeit wiederhergestellt '
                'werden.',
            children: [
              _ActionButton(
                icon: Icons.bolt,
                label: 'Schnell-Backup im App-Ordner',
                onPressed: _busy ? null : _backupErstellenAuto,
              ),
              const SizedBox(height: 8),
              _ActionButton(
                icon: Icons.save_as,
                label: 'Backup an gewähltem Ort speichern',
                onPressed: _busy ? null : _backupErstellenManuell,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Sektion: Backup wiederherstellen ─────────────────────────
          _Sektion(
            icon: Icons.restore,
            titel: 'Backup wiederherstellen',
            beschreibung:
                'Stelle einen früheren Datenstand wieder her. Achtung: '
                'Alle aktuellen Daten werden überschrieben.',
            children: [
              _ActionButton(
                icon: Icons.folder_open,
                label: 'Backup-Datei auswählen …',
                onPressed: _busy ? null : _backupAusDateiWaehlen,
              ),
              const SizedBox(height: 12),
              if (!_backupsGeladen)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_backups.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Keine Backups vorhanden.',
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: Colors.grey,
                    ),
                  ),
                )
              else ...[
                Text(
                  'Backups in deinem App-Ordner (${_backups.length}):',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                ..._backups.map(
                  (b) => _BackupListenEintrag(
                    info: b,
                    onRestore:
                        _busy ? null : () => _backupWiederherstellen(b),
                    onDelete: _busy ? null : () => _backupLoeschen(b),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),

          // ── Sektion: Speicherort ─────────────────────────────────────
          _Sektion(
            icon: Icons.folder,
            titel: 'Speicherort',
            beschreibung:
                'Hier liegen deine SQLite-Datenbank und alle automatischen '
                'Backups. Die Pfade kannst du in den Datei-Explorer kopieren.',
            children: [
              _PfadZeile(
                label: 'Datenbank-Ordner',
                pfad: _datenbankPfad,
                onCopy: _datenbankPfad != null
                    ? () => _kopiereInZwischenablage(_datenbankPfad!)
                    : null,
              ),
              const SizedBox(height: 8),
              _PfadZeile(
                label: 'Backup-Ordner',
                pfad: _backupPfad,
                onCopy: _backupPfad != null
                    ? () => _kopiereInZwischenablage(_backupPfad!)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Import-Detailmeldungen (aufklappbare Liste der Fehler + Hinweise)
// ──────────────────────────────────────────────────────────────────────────

class _ImportDetails extends StatelessWidget {
  const _ImportDetails({
    required this.fehler,
    required this.warnungen,
  });

  final List<String> fehler;
  final List<String> warnungen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hatFehler = fehler.isNotEmpty;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: hatFehler
              ? Colors.red.withValues(alpha: 0.4)
              : Colors.orange.withValues(alpha: 0.4),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: Icon(
          hatFehler ? Icons.error_outline : Icons.info_outline,
          color: hatFehler ? Colors.red : Colors.orange.shade800,
        ),
        title: Text(
          'Import-Details',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          '${fehler.length} Fehler · ${warnungen.length} Hinweise',
          style: theme.textTheme.bodySmall,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (hatFehler) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Fehler',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: Colors.red,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 4),
            ...fehler.map(
              (m) => _MeldungsZeile(text: m, farbe: Colors.red),
            ),
            const SizedBox(height: 12),
          ],
          if (warnungen.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Hinweise',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: Colors.orange.shade800,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 4),
            ...warnungen.map(
              (m) => _MeldungsZeile(text: m, farbe: Colors.orange.shade800),
            ),
          ],
        ],
      ),
    );
  }
}

/// Einzelne Melde-Zeile mit Aufzählungspunkt; Text ist markier-/kopierbar.
class _MeldungsZeile extends StatelessWidget {
  const _MeldungsZeile({
    required this.text,
    required this.farbe,
  });

  final String text;
  final Color farbe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 8),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: farbe,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              text,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Sektions-Karte
// ──────────────────────────────────────────────────────────────────────────

class _Sektion extends StatelessWidget {
  const _Sektion({
    required this.icon,
    required this.titel,
    required this.beschreibung,
    required this.children,
  });

  final IconData icon;
  final String titel;
  final String beschreibung;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  titel,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              beschreibung,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Aktion-Button
// ──────────────────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: FilledButton.tonalIcon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Pfad-Zeile mit Kopier-Button
// ──────────────────────────────────────────────────────────────────────────

class _PfadZeile extends StatelessWidget {
  const _PfadZeile({
    required this.label,
    required this.pfad,
    required this.onCopy,
  });

  final String label;
  final String? pfad;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 16),
                tooltip: 'Pfad kopieren',
                onPressed: onCopy,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            pfad ?? '…',
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Einzelner Backup-Listen-Eintrag
// ──────────────────────────────────────────────────────────────────────────

class _BackupListenEintrag extends StatelessWidget {
  const _BackupListenEintrag({
    required this.info,
    required this.onRestore,
    required this.onDelete,
  });

  final BackupInfo info;
  final VoidCallback? onRestore;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final relativeZeit = _formatRelativeTime(info.timestamp);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            info.isAuto ? Icons.auto_awesome : Icons.save,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.formattedTimestamp,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '$relativeZeit · ${info.formattedSize} · '
                  '${info.isAuto ? "Auto" : "Manuell"}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.restore, size: 20),
            tooltip: 'Wiederherstellen',
            onPressed: onRestore,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: 'Löschen',
            onPressed: onDelete,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  String _formatRelativeTime(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return 'gerade eben';
    if (diff.inHours < 1) return 'vor ${diff.inMinutes} min';
    if (diff.inDays < 1) return 'vor ${diff.inHours} Std';
    if (diff.inDays < 7) return 'vor ${diff.inDays} Tag(en)';
    return DateFormat('dd.MM.yyyy').format(when);
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Status-Banner (oben auf dem Screen während Aktionen)
// ──────────────────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.busy,
    required this.message,
    required this.color,
  });

  final bool busy;
  final String? message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          if (busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              color == Colors.red ? Icons.error_outline : Icons.check_circle,
              color: color,
              size: 20,
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message ?? '',
              style: TextStyle(
                color: color == Colors.red
                    ? Colors.red.shade800
                    : Colors.green.shade800,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}