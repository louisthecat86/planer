import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/services/artikel_fotos.dart';
import '../../core/services/auto_backup_trigger.dart';
import '../../core/ui/bausteine.dart';
import '../../core/ui/foto_kachel.dart';
import '../../core/utils/fehler_text.dart';
import '../../core/utils/format.dart';

// Die Fotoleiste eines Artikels: die Fotos aus der Produktion — mit der
// App „Planer Erfassung" an der Anlage aufgenommen oder hier hinzugefügt.
// Das Referenzbild steht vorn, dahinter die neuesten zuerst. Antippen
// zeigt ein Foto groß; dort wird es zum Referenzbild, bekommt eine
// Bemerkung oder wird gelöscht.

/// „09.11.2026 · AB".
String _unterzeile(ArtikelFoto f) => [
      Format.datum(f.aufgenommenAm),
      if ((f.kuerzel ?? '').isNotEmpty) f.kuerzel!,
    ].join(' · ');

class ArtikelFotoleiste extends ConsumerStatefulWidget {
  const ArtikelFotoleiste({super.key, required this.productId});

  final String productId;

  @override
  ConsumerState<ArtikelFotoleiste> createState() => _ArtikelFotoleisteState();
}

class _ArtikelFotoleisteState extends ConsumerState<ArtikelFotoleiste> {
  bool _arbeitet = false;

  void _melde(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _gesichert(String grund) =>
      ref.read(autoBackupTriggerProvider).fireDebounced(reason: grund);

  /// Bilder vom PC als Fotos — verkleinert wie die vom Handy.
  Future<void> _hinzufuegen() async {
    final gewaehlt = await FilePicker.pickFiles(
      dialogTitle: 'Fotos zum Artikel hinzufügen',
      type: FileType.image,
      allowMultiple: true,
    );
    if (gewaehlt == null || gewaehlt.files.isEmpty || !mounted) return;
    setState(() => _arbeitet = true);
    final dienst = ref.read(artikelFotoDienstProvider);
    var neu = 0;
    final unlesbar = <String>[];
    try {
      for (final datei in gewaehlt.files) {
        final roh = datei.bytes ??
            (datei.path == null ? null : await File(datei.path!).readAsBytes());
        final bild = roh == null ? null : await fotoAufbereiten(roh);
        if (bild == null) {
          unlesbar.add(datei.name);
          continue;
        }
        await dienst.speichern(
          productId: widget.productId,
          bild: bild,
          aufgenommenAm: DateTime.now(),
        );
        neu++;
      }
      if (neu > 0) _gesichert('Foto zum Artikel');
      if (unlesbar.isNotEmpty) {
        _melde(
          'Kein Bild, das sich lesen lässt: ${unlesbar.join(', ')}',
        );
      }
    } catch (e) {
      _melde('Das Foto ließ sich nicht hinzufügen: ${fehlerText(e)}');
    } finally {
      if (mounted) setState(() => _arbeitet = false);
    }
  }

  Future<void> _referenz(ArtikelFoto f, {required bool an}) async {
    try {
      await ref
          .read(artikelFotoDienstProvider)
          .referenzSetzen(widget.productId, an ? f.id : null);
      _gesichert('Referenzbild');
    } catch (e) {
      _melde('Das ließ sich nicht speichern: ${fehlerText(e)}');
    }
  }

  Future<void> _bemerkung(ArtikelFoto f) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _BemerkungDialog(bisher: f.bezeichnung ?? ''),
    );
    if (text == null) return;
    try {
      await ref.read(artikelFotoDienstProvider).bezeichnungSetzen(f.id, text);
      _gesichert('Foto: Bemerkung');
    } catch (e) {
      _melde('Das ließ sich nicht speichern: ${fehlerText(e)}');
    }
  }

  Future<void> _loeschen(ArtikelFoto f) async {
    final ja = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Foto löschen?'),
        content: Text(
          'Das Foto vom ${Format.datum(f.aufgenommenAm)} wird gelöscht'
          '${f.istReferenz ? ' — es ist das Referenzbild' : ''}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ja != true) return;
    try {
      await ref.read(artikelFotoDienstProvider).loeschen(f.id);
      _gesichert('Foto gelöscht');
    } catch (e) {
      _melde('Löschen fehlgeschlagen: ${fehlerText(e)}');
    }
  }

  void _zeigen(ArtikelFoto f, Uint8List bild) {
    // Erst den Dialog schließen, dann handeln — die Leiste zeigt danach
    // den neuen Stand.
    void Function() dann(BuildContext dialog, Future<void> Function() tun) =>
        () {
          Navigator.of(dialog).pop();
          tun();
        };
    fotoGrossZeigen(
      context,
      bild: bild,
      titel: f.istReferenz ? 'Referenzbild' : 'Foto aus der Produktion',
      untertitel: [
        _unterzeile(f),
        if ((f.bezeichnung ?? '').isNotEmpty) f.bezeichnung!,
      ].join(' · '),
      aktionen: (dialog) => [
        OutlinedButton.icon(
          key: const ValueKey('foto-referenz'),
          onPressed: dann(dialog, () => _referenz(f, an: !f.istReferenz)),
          icon: Icon(
            f.istReferenz ? Icons.star : Icons.star_border,
            size: 18,
          ),
          label: Text(
            f.istReferenz ? 'Kein Referenzbild mehr' : 'Als Referenzbild',
          ),
        ),
        OutlinedButton.icon(
          key: const ValueKey('foto-bemerkung'),
          onPressed: dann(dialog, () => _bemerkung(f)),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Bemerkung …'),
        ),
        OutlinedButton.icon(
          key: const ValueKey('foto-loeschen'),
          onPressed: dann(dialog, () => _loeschen(f)),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('Löschen'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final fotos = ref.watch(artikelFotosProvider(widget.productId));
    final liste = fotos.valueOrNull ?? const <ArtikelFoto>[];
    return Bereich(
      key: const ValueKey('artikel-fotos'),
      titel: 'Fotos',
      icon: Icons.photo_camera_outlined,
      untertitel: liste.isEmpty
          ? null
          : liste.length == 1
              ? '1 Foto'
              : '${liste.length} Fotos',
      aktionen: [
        if (_arbeitet)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        TextButton.icon(
          // Nicht „artikel-foto-…" — so heißen die Kacheln der Fotos.
          key: const ValueKey('fotoleiste-hinzufuegen'),
          onPressed: _arbeitet ? null : _hinzufuegen,
          icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
          label: const Text('Foto hinzufügen'),
        ),
      ],
      child: fotos.hasError
          ? HinweisBox(
              'Die Fotos ließen sich nicht laden: '
              '${fehlerText(fotos.error!)}',
              art: StatusArt.fehler,
            )
          : liste.isEmpty
              ? const LeerHinweis(
                  'Noch keine Fotos — an der Anlage mit der App „Planer '
                  'Erfassung" aufnehmen oder hier hinzufügen.',
                  icon: Icons.photo_camera_outlined,
                )
              : SizedBox(
                  height: _Kachel.hoehe,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: liste.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) => _Kachel(
                      key: ValueKey('artikel-foto-${liste[i].id}'),
                      foto: liste[i],
                      onZeigen: (bild) => _zeigen(liste[i], bild),
                    ),
                  ),
                ),
    );
  }
}

/// Ein Foto der Leiste: das Bild, darunter Datum und Kürzel.
class _Kachel extends ConsumerWidget {
  const _Kachel({super.key, required this.foto, required this.onZeigen});

  static const double breite = 168;
  static const double bildHoehe = 126;
  // Bild, Abstand und zwei Zeilen Text — mit etwas Luft.
  static const double hoehe = bildHoehe + 44;

  final ArtikelFoto foto;
  final void Function(Uint8List bild) onZeigen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final inhalt = ref.watch(artikelFotoBildProvider(foto.id));
    final bild = inhalt.valueOrNull;
    final bemerkung = foto.bezeichnung ?? '';
    return SizedBox(
      width: breite,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              FotoKachel(
                bild: bild,
                breite: breite,
                hoehe: bildHoehe,
                fehlt: inhalt.hasError || (inhalt.hasValue && bild == null),
                hervorgehoben: foto.istReferenz,
                onTap: bild == null ? null : () => onZeigen(bild),
              ),
              if (foto.istReferenz)
                Positioned(
                  left: 6,
                  top: 6,
                  child: IgnorePointer(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: breite - 12),
                      child: const StatusMarke(
                        'Referenzbild',
                        art: StatusArt.info,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _unterzeile(foto),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          Text(
            bemerkung,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _BemerkungDialog extends StatefulWidget {
  const _BemerkungDialog({required this.bisher});

  final String bisher;

  @override
  State<_BemerkungDialog> createState() => _BemerkungDialogState();
}

class _BemerkungDialogState extends State<_BemerkungDialog> {
  late final _text = TextEditingController(text: widget.bisher);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Bemerkung zum Foto'),
        content: SizedBox(
          width: 420,
          child: TextField(
            key: const ValueKey('foto-bemerkung-text'),
            controller: _text,
            autofocus: true,
            maxLength: 120,
            decoration: const InputDecoration(
              hintText: 'etwa „Anschnitt" oder „nach dem Braten"',
            ),
            onSubmitted: (t) => Navigator.of(context).pop(t),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_text.text),
            child: const Text('Speichern'),
          ),
        ],
      );
}
