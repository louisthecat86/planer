import 'dart:io';

import 'package:erfassung_format/erfassung_format.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/database_provider.dart';
import '../../core/utils/fehler_text.dart';
import '../../core/utils/format.dart';
import '../entwicklung/daten/datei_typen.dart' show groesseText;
import 'handy_erfassung_dienst.dart';
import 'qr_senden.dart';

// ═══════════════════════════════════════════════════════════════════════
// Aufs Handy
//
// Der Plan geht vom Planungsboard aufs Handy — für die App „Planer
// Erfassung" an der Anlage: die geplanten Produktionen der gezeigten Woche
// (oder des gezeigten Tages) und die Maschineneinstellungen. Per QR-Code
// zum Abfotografieren oder als Datei. Zurück kommt das Ergebnis in der
// Produktionserfassung („Vom Handy einlesen").
// ═══════════════════════════════════════════════════════════════════════

/// Öffnet das Fenster „Aufs Handy" für die Produktionen von [von] bis
/// [bis] (beide einschließlich). [zeitraum] steht im Titel: „KW 48" oder
/// „Mi 25.11.".
Future<void> aufsHandyZeigen(
  BuildContext context, {
  required DateTime von,
  required DateTime bis,
  required String zeitraum,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => AufsHandyDialog(von: von, bis: bis, zeitraum: zeitraum),
    );

class AufsHandyDialog extends ConsumerStatefulWidget {
  const AufsHandyDialog({
    super.key,
    required this.von,
    required this.bis,
    required this.zeitraum,
  });

  final DateTime von;
  final DateTime bis;
  final String zeitraum;

  @override
  ConsumerState<AufsHandyDialog> createState() => _AufsHandyDialogState();
}

class _AufsHandyDialogState extends ConsumerState<AufsHandyDialog> {
  bool _arbeitet = false;

  /// Per QR-Code auch die Artikel ohne geplante Produktion mitschicken —
  /// dann lassen sich am Handy alle Einstellungen ändern, es dauert aber.
  bool _alleArtikel = false;

  String? _fehler;

  HandyErfassungDienst get _dienst =>
      HandyErfassungDienst(ref.read(databaseProvider));

  /// Das Paket als wechselnde QR-Codes zum Abfotografieren.
  Future<void> _qr() async {
    setState(() {
      _arbeitet = true;
      _fehler = null;
    });
    try {
      final paket = await _dienst.paketErstellen(
        von: widget.von,
        bis: widget.bis,
        nurGeplante: !_alleArtikel,
      );
      final daten = qrPacken(paket);
      if (!mounted) return;
      setState(() => _arbeitet = false);
      final n = paket.produktionen.length;
      await qrSendenZeigen(
        context,
        daten: daten,
        info: '${n == 1 ? '1 Produktion' : '$n Produktionen'}, die '
            'Maschineneinstellungen von ${paket.artikel.length} Artikeln '
            '· ${groesseText(daten.length)}',
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _arbeitet = false;
        _fehler = 'Die QR-Codes ließen sich nicht erstellen: ${fehlerText(e)}';
      });
    }
  }

  /// Das Paket als Datei — mit allen Artikeln.
  Future<void> _datei() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _arbeitet = true;
      _fehler = null;
    });
    try {
      final paket =
          await _dienst.paketErstellen(von: widget.von, bis: widget.bis);
      final ziel = await FilePicker.saveFile(
        dialogTitle: 'Datei fürs Handy speichern',
        fileName: paket.dateiname,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (ziel == null) {
        if (mounted) setState(() => _arbeitet = false);
        return;
      }
      await File(ziel).writeAsString(paket.alsText());
      if (!mounted) return;
      Navigator.of(context).pop();
      final n = paket.produktionen.length;
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
            'Datei gespeichert: ${n == 1 ? '1 Produktion' : '$n '
                'Produktionen'} und die Maschineneinstellungen von '
            '${paket.artikel.length} Artikeln. Jetzt aufs Handy bringen und '
            'dort mit „Planer Erfassung" öffnen.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _arbeitet = false;
        _fehler = 'Die Datei ließ sich nicht erstellen: ${fehlerText(e)}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final frei = !_arbeitet;
    final eintaegig = widget.von.year == widget.bis.year &&
        widget.von.month == widget.bis.month &&
        widget.von.day == widget.bis.day;
    return AlertDialog(
      title: Text('Aufs Handy · ${widget.zeitraum}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              eintaegig
                  ? 'Die geplanten Produktionen vom '
                      '${Format.datum(widget.von)} und die '
                      'Maschineneinstellungen — für die App „Planer '
                      'Erfassung" an der Anlage.'
                  : 'Die geplanten Produktionen vom '
                      '${Format.datum(widget.von)} bis '
                      '${Format.datum(widget.bis)} und die '
                      'Maschineneinstellungen — für die App „Planer '
                      'Erfassung" an der Anlage.',
              style: theme.textTheme.bodyMedium?.copyWith(color: grau),
            ),
            const SizedBox(height: 14),
            _Weg(
              key: const ValueKey('aufs-handy-qr'),
              icon: Icons.qr_code_2,
              titel: 'Per QR-Code',
              text: 'Das Handy auf den Bildschirm halten — in der App „Per '
                  'QR-Code empfangen".',
              onTap: frei ? _qr : null,
            ),
            InkWell(
              key: const ValueKey('aufs-handy-alle'),
              borderRadius: BorderRadius.circular(6),
              onTap: () => setState(() => _alleArtikel = !_alleArtikel),
              child: Row(
                children: [
                  Checkbox(
                    value: _alleArtikel,
                    onChanged: (v) => setState(() => _alleArtikel = v ?? false),
                  ),
                  Expanded(
                    child: Text(
                      'Auch Artikel ohne Produktion mitschicken (dauert per '
                      'QR-Code gut eine Minute)',
                      style: theme.textTheme.bodySmall?.copyWith(color: grau),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            _Weg(
              key: const ValueKey('aufs-handy-datei'),
              icon: Icons.save_alt,
              titel: 'Als Datei',
              text: 'Speichern und per Kabel oder Freigabe aufs Handy '
                  'bringen — immer mit allen Artikeln.',
              onTap: frei ? _datei : null,
            ),
            if (_arbeitet) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_fehler case final f?) ...[
              const SizedBox(height: 12),
              Text(
                f,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'Das Ergebnis vom Handy liest du in der Produktionserfassung '
              'ein: „Vom Handy einlesen".',
              style: theme.textTheme.bodySmall?.copyWith(color: grau),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Schließen'),
        ),
      ],
    );
  }
}

/// Ein Weg aufs Handy als Zeile: Symbol, Titel, ein Satz.
class _Weg extends StatelessWidget {
  const _Weg({
    super.key,
    required this.icon,
    required this.titel,
    required this.text,
    required this.onTap,
  });

  final IconData icon;
  final String titel;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = theme.colorScheme;
    return Material(
      color: f.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: f.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: f.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 24, color: f.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titel,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: onTap == null ? f.onSurfaceVariant : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      text,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: f.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: f.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
