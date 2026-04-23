import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/database_provider.dart';
import '../../core/services/excel_export_service_v3.dart';
import '../../core/services/excel_import_dispatcher.dart';
import '../articles/article_list_screen.dart';

// ---------------------------------------------------------------------------
// Excel-Import / Export Screen (v3-fähig, via Dispatcher)
// ---------------------------------------------------------------------------

class ExcelImportScreen extends ConsumerStatefulWidget {
  const ExcelImportScreen({super.key});

  @override
  ConsumerState<ExcelImportScreen> createState() => _ExcelImportScreenState();
}

class _ExcelImportScreenState extends ConsumerState<ExcelImportScreen> {
  // ── Import-State ────────────────────────────────────────────────────
  String? _filePath;
  String? _fileName;
  UnifiedImportPreview? _preview;
  UnifiedImportResult? _result;
  bool _isLoading = false;
  String? _error;

  // ── Export-State ────────────────────────────────────────────────────
  bool _isExporting = false;
  ExportResultV3? _exportResult;
  String? _exportError;
  bool _hasImportedFile = false;

  @override
  void initState() {
    super.initState();
    _pruefeObImportVorhanden();
  }

  Future<void> _pruefeObImportVorhanden() async {
    final svc = ExcelExportServiceV3(ref.read(databaseProvider));
    final vorhanden = await svc.hasImportedFile();
    if (mounted) {
      setState(() => _hasImportedFile = vorhanden);
    }
  }

  // ---- Datei wählen ----

  Future<void> _pickFile() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
    );
    if (picked == null || picked.files.isEmpty) return;

    final file = picked.files.first;
    final path = file.path;
    if (path == null) return;

    setState(() {
      _filePath = path;
      _fileName = file.name;
      _preview = null;
      _result = null;
      _error = null;
      _exportResult = null;
      _exportError = null;
    });

    await _loadPreview();
  }

  // ---- Vorschau laden ----

  Future<void> _loadPreview() async {
    if (_filePath == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final dispatcher = ExcelImportDispatcher(ref.read(databaseProvider));
      final preview = await dispatcher.preview(_filePath!);
      if (mounted) {
        setState(() {
          _preview = preview;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Fehler beim Lesen: $e';
          _isLoading = false;
        });
      }
    }
  }

  // ---- Import ausführen ----

  Future<void> _runImport() async {
    if (_filePath == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _result = null;
    });

    try {
      final dispatcher = ExcelImportDispatcher(ref.read(databaseProvider));
      final result = await dispatcher.importFile(_filePath!);
      if (mounted) {
        ref.invalidate(articlesProvider);
        setState(() {
          _result = result;
          _isLoading = false;
          _hasImportedFile = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Fehler beim Import: $e';
          _isLoading = false;
        });
      }
    }
  }

  // ---- Export ausführen ----

  Future<void> _runExport() async {
    setState(() {
      _isExporting = true;
      _exportError = null;
      _exportResult = null;
    });

    try {
      final svc = ExcelExportServiceV3(ref.read(databaseProvider));
      final result = await svc.export();

      if (result.hatFehler) {
        if (mounted) {
          setState(() {
            _exportError = result.fehler.join('\n');
            _isExporting = false;
          });
        }
        return;
      }

      // Speichern-Dialog
      final zielPfad = await FilePicker.saveFile(
        dialogTitle: 'Excel-Export speichern',
        fileName: result.vorschlagDateiname,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (zielPfad == null) {
        // Nutzer hat abgebrochen
        if (mounted) {
          setState(() => _isExporting = false);
        }
        return;
      }

      // Datei schreiben
      final zielDatei = File(zielPfad);
      await zielDatei.writeAsBytes(result.bytes);

      if (mounted) {
        setState(() {
          _exportResult = result;
          _isExporting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _exportError = 'Fehler beim Export: $e';
          _isExporting = false;
        });
      }
    }
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Excel Import / Export'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ═════ Info-Text ═══════════════════════════════════════════════
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: colors.onPrimaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Arbeitsweise: Morgens aktuelle Excel importieren → '
                    'tagsüber in der App oder Excel arbeiten (nicht beides '
                    'parallel) → abends aktualisierte Excel exportieren.',
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ═════ Sektion: Import ═════════════════════════════════════════
          const _SectionHeader(
            icon: Icons.upload_file,
            title: 'Import',
            subtitle: 'Excel-Datei in die App laden',
          ),
          const SizedBox(height: 12),

          FilledButton.tonalIcon(
            onPressed: _isLoading || _isExporting ? null : _pickFile,
            icon: const Icon(Icons.upload_file),
            label: Text(
              _fileName ?? 'Excel-Datei auswählen (.xlsx)',
            ),
          ),
          const SizedBox(height: 16),

          if (_isLoading) ...[
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 16),
          ],

          if (_error != null) ...[
            _MessageCard(
              icon: Icons.error,
              color: colors.error,
              title: 'Fehler',
              message: _error!,
            ),
            const SizedBox(height: 16),
          ],

          if (_preview != null && _result == null) ...[
            _PreviewCard(preview: _preview!),
            const SizedBox(height: 16),

            if (!_preview!.hatFehler && !_preview!.istLeer)
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: _isLoading ? null : _runImport,
                  icon: const Icon(Icons.download),
                  label: const Text('Jetzt importieren'),
                ),
              ),

            if (_preview!.istLeer)
              const _MessageCard(
                icon: Icons.warning_amber,
                color: Colors.orange,
                title: 'Leere Datei',
                message: 'Keine importierbaren Daten gefunden.',
              ),
          ],

          if (_result != null) ...[
            _ResultCard(result: _result!),
            const SizedBox(height: 16),
          ],

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 24),

          // ═════ Sektion: Export ═════════════════════════════════════════
          const _SectionHeader(
            icon: Icons.download,
            title: 'Export',
            subtitle: 'Aktualisierte Excel-Datei speichern',
          ),
          const SizedBox(height: 12),

          if (!_hasImportedFile) ...[
            _MessageCard(
              icon: Icons.info_outline,
              color: colors.outline,
              title: 'Noch kein Import erfolgt',
              message: 'Importiere zuerst eine Excel-Vorlage, dann kannst '
                  'du sie mit den aktuellen Daten aus der App als neue '
                  'Excel exportieren.',
            ),
          ] else ...[
            Text(
              'Der Export nimmt deine zuletzt importierte Excel als Basis, '
              'aktualisiert alle Schritte, Anlagen-Zuordnungen und '
              'Parameter auf den aktuellen Stand in der App, und lässt '
              'Formatierung, Dropdowns und Anlagen-Katalog 1:1 erhalten.',
              style: TextStyle(
                fontSize: 13,
                color: colors.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _isExporting || _isLoading ? null : _runExport,
                icon: _isExporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_alt),
                label: Text(
                  _isExporting ? 'Wird erstellt …' : 'Excel exportieren',
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),

          if (_exportError != null) ...[
            _MessageCard(
              icon: Icons.error,
              color: colors.error,
              title: 'Export-Fehler',
              message: _exportError!,
            ),
            const SizedBox(height: 16),
          ],

          if (_exportResult != null) ...[
            _ExportResultCard(result: _exportResult!),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sektion-Header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, color: colors.primary, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: colors.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Preview-Karte (Import)
// ---------------------------------------------------------------------------

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.preview});

  final UnifiedImportPreview preview;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isV3 = preview.version == VorlagenVersion.v3;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.preview, color: colors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Vorschau',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isV3
                        ? Colors.green.withValues(alpha: 0.15)
                        : Colors.blueGrey.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isV3 ? 'Format: v3' : 'Format: Legacy',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isV3
                          ? Colors.green.shade700
                          : Colors.blueGrey.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _countRow('Neue Artikel', preview.artikelNeu),
            _countRow('Aktualisierte Artikel', preview.artikelAktualisiert),
            _countRow('Produktions-Schritte', preview.schritte),
            if (isV3) ...[
              _countRow('Anlagen (Katalog)', preview.maschinen),
              _countRow('Schritt-Parameter', preview.parameter),
            ] else ...[
              _countRow('Rezeptur-Einträge', preview.rezepturen),
              _countRow('Rohwaren', preview.rohwaren),
            ],
            _countRow('Historische Messwerte', preview.historien),

            if (preview.warnungen.isNotEmpty) ...[
              const Divider(),
              for (final w in preview.warnungen)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.warning_amber,
                        size: 16,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          w,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
            ],

            if (preview.fehler.isNotEmpty) ...[
              const Divider(),
              for (final f in preview.fehler)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error, size: 16, color: Colors.red),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          f,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.red,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _countRow(String label, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: count > 0 ? Colors.green.shade700 : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ergebnis-Karte (Import)
// ---------------------------------------------------------------------------

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final UnifiedImportResult result;

  @override
  Widget build(BuildContext context) {
    final success = !result.hatFehler;
    final isV3 = result.version == VorlagenVersion.v3;

    return Card(
      color: success ? Colors.green.shade50 : Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  success ? Icons.check_circle : Icons.error,
                  color: success ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  success ? 'Import erfolgreich' : 'Import mit Fehlern',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: success
                        ? Colors.green.shade800
                        : Colors.red.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _countRow('Neue Artikel', result.artikelNeu),
            _countRow('Aktualisierte Artikel', result.artikelAktualisiert),
            _countRow('Schritte', result.schritteImportiert),
            if (isV3) ...[
              _countRow('Anlagen importiert', result.maschinenImportiert),
              _countRow('Schritt-Parameter', result.parameterImportiert),
            ] else ...[
              _countRow('Rezepturen', result.rezepturenImportiert),
              _countRow('Rohwaren', result.rohwarenImportiert),
            ],
            _countRow('Historische Messwerte', result.historienVerarbeitet),

            if (result.warnungen.isNotEmpty) ...[
              const Divider(),
              const Text(
                'Warnungen:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              for (final w in result.warnungen)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    '• $w',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
            ],

            if (result.fehler.isNotEmpty) ...[
              const Divider(),
              const Text(
                'Fehler:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 4),
              for (final f in result.fehler)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    '• $f',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.red,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _countRow(String label, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: count > 0 ? Colors.green.shade700 : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ergebnis-Karte (Export)
// ---------------------------------------------------------------------------

class _ExportResultCard extends StatelessWidget {
  const _ExportResultCard({required this.result});

  final ExportResultV3 result;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  'Export erfolgreich',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.green.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _countRow('Artikel aktualisiert', result.artikelAktualisiert),
            _countRow('Schritte geschrieben', result.schritteGeschrieben),
            _countRow('Parameter geschrieben', result.parameterGeschrieben),

            if (result.artikelNichtInVorlage.isNotEmpty) ...[
              const Divider(),
              const Text(
                'Hinweis: Artikel die in der App angelegt wurden, aber '
                'nicht in der Excel-Vorlage sind, wurden nicht exportiert. '
                'Füge sie direkt in der Excel als neues Sheet hinzu:',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                result.artikelNichtInVorlage.take(20).join(', ') +
                    (result.artikelNichtInVorlage.length > 20
                        ? ', … (${result.artikelNichtInVorlage.length - 20} weitere)'
                        : ''),
                style: const TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],

            if (result.warnungen.isNotEmpty) ...[
              const Divider(),
              const Text(
                'Warnungen:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              for (final w in result.warnungen.take(10))
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    '• $w',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              if (result.warnungen.length > 10)
                Text(
                  '… und ${result.warnungen.length - 10} weitere',
                  style: const TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _countRow(String label, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: count > 0 ? Colors.green.shade700 : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Generische Nachricht
// ---------------------------------------------------------------------------

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}