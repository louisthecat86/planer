import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/database_provider.dart';
import '../../core/services/excel_import_dispatcher.dart';
import '../articles/article_list_screen.dart';

// ---------------------------------------------------------------------------
// Excel-Import Screen (v3-fähig, via Dispatcher)
// ---------------------------------------------------------------------------

class ExcelImportScreen extends ConsumerStatefulWidget {
  const ExcelImportScreen({super.key});

  @override
  ConsumerState<ExcelImportScreen> createState() => _ExcelImportScreenState();
}

class _ExcelImportScreenState extends ConsumerState<ExcelImportScreen> {
  String? _filePath;
  String? _fileName;
  UnifiedImportPreview? _preview;
  UnifiedImportResult? _result;
  bool _isLoading = false;
  String? _error;

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

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Excel-Import'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Info-Text
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
                    'Importiere Artikel-Stammdaten aus einer Excel-Datei. '
                    'Unterstützt werden: v3-Vorlage (mit Anlagen-Katalog und '
                    'Kategorie-Blaupausen) sowie die alte Phase-B-Vorlage.',
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Datei-Auswahl
          FilledButton.tonalIcon(
            onPressed: _isLoading ? null : _pickFile,
            icon: const Icon(Icons.upload_file),
            label: Text(
              _fileName ?? 'Excel-Datei auswählen (.xlsx)',
            ),
          ),
          const SizedBox(height: 20),

          if (_isLoading) ...[
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 20),
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
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Preview-Karte
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
// Ergebnis-Karte
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