import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/ui/bausteine.dart';
import '../daten/dateien.dart';
import 'suite_import.dart';

/// Lesen und Schreiben für die Übernahme — im Test ersetzbar.
abstract class SuiteImportDienst {
  /// Liest das Backup und plant die Übernahme. [frueher]: Es gibt schon
  /// Übernommenes, das ein neuer Import überschreibt.
  Future<({SuiteImportPlan plan, bool frueher})> vorbereiten(Uint8List bytes);

  Future<void> ausfuehren(SuiteImportPlan plan);
}

/// Die Übernahme in die Datenbank der App.
class DbSuiteImportDienst implements SuiteImportDienst {
  DbSuiteImportDienst(this._db, this._dateien);

  final AppDatabase _db;
  final EntwicklungDateienDienst _dateien;

  @override
  Future<({SuiteImportPlan plan, bool frueher})> vorbereiten(
    Uint8List bytes,
  ) async {
    final zutaten = await _db.select(_db.entwicklungZutaten).get();
    final projekte = await _db.select(_db.entwicklungProjekte).get();
    final vorhanden = {
      for (final z in zutaten)
        if (!z.id.startsWith(kSuitePraefix) && z.deletedAt == null)
          z.name.trim().toLowerCase(),
    };
    final frueher = zutaten.any((z) => z.id.startsWith(kSuitePraefix)) ||
        projekte.any((p) => p.id.startsWith(kSuitePraefix));
    final plan =
        await suiteImportVorbereiten(bytes, vorhandeneZutaten: vorhanden);
    return (plan: plan, frueher: frueher);
  }

  @override
  Future<void> ausfuehren(SuiteImportPlan plan) =>
      suiteImportAusfuehren(_db, plan, _dateien);
}

final suiteImportDienstProvider = Provider<SuiteImportDienst>(
  (ref) => DbSuiteImportDienst(
    ref.watch(databaseProvider),
    ref.watch(entwicklungDateienProvider),
  ),
);

/// Wählt ein Backup der Suite und öffnet das Fenster zur Übernahme.
Future<void> suiteImportStarten(BuildContext context) async {
  final gewaehlt = await FilePicker.pickFiles(
    dialogTitle: 'Backup der Development-Suite wählen',
    type: FileType.custom,
    allowedExtensions: ['zip', 'json'],
    withData: true,
  );
  if (gewaehlt == null || gewaehlt.files.isEmpty || !context.mounted) return;
  final datei = gewaehlt.files.first;
  var bytes = datei.bytes;
  final pfad = datei.path;
  // Füllt eine Plattform die Bytes trotz withData nicht, wird die Datei
  // selbst gelesen.
  if (bytes == null && pfad != null) {
    try {
      bytes = await File(pfad).readAsBytes();
    } on FileSystemException {
      bytes = null;
    }
    if (!context.mounted) return;
  }
  final inhalt = bytes;
  if (inhalt == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Die gewählte Datei ließ sich nicht lesen.')),
    );
    return;
  }
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => SuiteImportDialog(bytes: inhalt, dateiname: datei.name),
  );
}

enum _Phase { lesen, vorschau, schreiben, fertig, fehler }

/// Zeigt, was aus dem Backup übernommen würde, und übernimmt es nach
/// Bestätigung.
class SuiteImportDialog extends ConsumerStatefulWidget {
  const SuiteImportDialog({
    super.key,
    required this.bytes,
    required this.dateiname,
  });

  final Uint8List bytes;
  final String dateiname;

  @override
  ConsumerState<SuiteImportDialog> createState() => _SuiteImportDialogState();
}

class _SuiteImportDialogState extends ConsumerState<SuiteImportDialog> {
  _Phase _phase = _Phase.lesen;
  SuiteImportPlan? _plan;
  bool _frueher = false;
  String _fehler = '';

  @override
  void initState() {
    super.initState();
    _vorbereiten();
  }

  void _scheitern(Object e) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.fehler;
      _fehler = e is FormatException ? e.message : '$e';
    });
  }

  Future<void> _vorbereiten() async {
    try {
      final v = await ref.read(suiteImportDienstProvider).vorbereiten(
            widget.bytes,
          );
      if (!mounted) return;
      setState(() {
        _plan = v.plan;
        _frueher = v.frueher;
        _phase = _Phase.vorschau;
      });
    } catch (e) {
      _scheitern(e);
    }
  }

  Future<void> _uebernehmen() async {
    final plan = _plan;
    if (plan == null) return;
    setState(() => _phase = _Phase.schreiben);
    try {
      await ref.read(suiteImportDienstProvider).ausfuehren(plan);
      if (!mounted) return;
      setState(() => _phase = _Phase.fertig);
    } catch (e) {
      _scheitern(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    return AlertDialog(
      icon: const Icon(Icons.move_to_inbox_outlined),
      title: const Text('Aus der Development-Suite übernehmen'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, minWidth: 380),
        child: switch (_phase) {
          _Phase.lesen => _Laeuft('„${widget.dateiname}" wird gelesen …'),
          _Phase.schreiben => const _Laeuft(
              'Wird übernommen — Dateien werden dabei verschlüsselt …',
            ),
          _Phase.fehler => HinweisBox(
              _fehler,
              art: StatusArt.fehler,
              titel: 'Das Backup ließ sich nicht übernehmen',
              auswaehlbar: true,
            ),
          _Phase.vorschau || _Phase.fertig => plan == null
              ? const SizedBox.shrink()
              : _Inhalt(
                  plan: plan,
                  dateiname: widget.dateiname,
                  fertig: _phase == _Phase.fertig,
                  frueher: _frueher,
                ),
        },
      ),
      actions: switch (_phase) {
        _Phase.lesen || _Phase.schreiben => const [],
        _Phase.fehler || _Phase.fertig => [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Schließen'),
            ),
          ],
        _Phase.vorschau => [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Abbrechen'),
            ),
            FilledButton.icon(
              onPressed: plan == null || plan.leer ? null : _uebernehmen,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Übernehmen'),
            ),
          ],
      },
    );
  }
}

class _Laeuft extends StatelessWidget {
  const _Laeuft(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _Inhalt extends StatelessWidget {
  const _Inhalt({
    required this.plan,
    required this.dateiname,
    required this.fertig,
    required this.frueher,
  });

  final SuiteImportPlan plan;
  final String dateiname;
  final bool fertig;
  final bool frueher;

  @override
  Widget build(BuildContext context) {
    if (plan.leer) {
      return LeerHinweis(
        '„$dateiname" enthält keine Zutaten, Rezepturen oder Projekte.',
        icon: Icons.inbox_outlined,
      );
    }
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (fertig)
            const HinweisBox(
              'Projekte, Rezepturen und Zutaten stehen jetzt in ihren '
              'Reitern. Übernommene Rezepturstände sind abgeschlossen, der '
              'letzte Stand der Suite ist ein Entwurf.',
              art: StatusArt.ok,
              titel: 'Übernommen',
            )
          else
            Text('„$dateiname" enthält:'),
          const SizedBox(height: 10),
          SuiteImportZahlen(plan: plan),
          if (!fertig) ...[
            for (final h in plan.hinweise) ...[
              const SizedBox(height: 8),
              HinweisBox(h, art: StatusArt.warnung),
            ],
            const SizedBox(height: 8),
            HinweisBox(
              frueher
                  ? 'Es gibt schon Übernommenes aus der Suite. Es wird mit '
                      'dem Stand dieses Backups überschrieben — was du hier '
                      'daran geändert hast, geht verloren. Von Hand '
                      'Angelegtes bleibt.'
                  : 'Ein späterer Import eines neueren Backups überschreibt '
                      'das Übernommene mit dem Stand der Suite; von Hand '
                      'Angelegtes bleibt.',
              art: frueher ? StatusArt.warnung : StatusArt.info,
            ),
          ],
        ],
      ),
    );
  }
}

/// Die Kennzahlen eines Plans als kleine Tabelle.
class SuiteImportZahlen extends StatelessWidget {
  const SuiteImportZahlen({super.key, required this.plan});

  final SuiteImportPlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    Widget zelle(Widget kind) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
          child: kind,
        );
    return Table(
      columnWidths: const {
        0: IntrinsicColumnWidth(),
        1: IntrinsicColumnWidth(),
        2: FlexColumnWidth(),
      },
      children: [
        for (final z in plan.zahlen)
          TableRow(
            children: [
              zelle(Text(z.label)),
              zelle(
                Text(
                  '${z.anzahl}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              zelle(
                Text(
                  z.davon ?? '',
                  style: theme.textTheme.bodySmall?.copyWith(color: grau),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
