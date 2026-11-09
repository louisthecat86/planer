import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/database/database.dart';
import '../../../core/services/auto_backup_trigger.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/fehler_text.dart';
import '../../../core/utils/format.dart';
import '../daten/dateien.dart';
import '../daten/etikett_scan.dart';
import 'datei_aktionen.dart';
import 'projekt_dateien.dart' show DateiZeile;
import 'projekt_repository.dart';

// Das Originaletikett beim Etikett nach LMIV: der Scan des gedruckten
// Etiketts neben den Pflichtangaben — ein Bild oder ein PDF, dessen erste
// Seiten die App als Bilder zeigt. Ein neuer Scan ersetzt es, der alte
// bleibt unter „Dateien". Für den Punkt „Etikett erstellt" zählt es nicht;
// er sagt nur, ob es hinterlegt ist.
//
// Ist das Etikett im Scan zu klein, lässt es sich vergrößern: im Dialog
// auf das Etikett zoomen — was im Rahmen steht, zeigt der Bericht so groß,
// wie dort Platz ist (EtikettAusschnitt in daten/etikett_scan.dart).

/// Rastert die ersten Seiten eines PDFs mit PDFium — für die Vorschau und
/// den Projektbericht.
Future<List<Uint8List>> pdfSeitenGerastert(Uint8List pdf) async {
  final seiten = <Uint8List>[];
  await for (final seite in Printing.raster(
    pdf,
    pages: [for (var i = 0; i < kEtikettMaxSeiten; i++) i],
    dpi: 150,
  )) {
    seiten.add(await seite.toPng());
  }
  return seiten;
}

/// Eine Datei der Produktentwicklung — für Name und Datum.
final entwicklungsDateiProvider =
    FutureProvider.autoDispose.family<EntwicklungsDatei?, String>(
  (ref, id) => ref.watch(entwicklungDateienProvider).datei(id),
);

/// Das Originaletikett als Bilder — ein PDF als seine ersten Seiten.
final originaletikettBilderProvider =
    FutureProvider.autoDispose.family<List<Uint8List>, String>(
  (ref, dateiId) async {
    final dienst = ref.watch(entwicklungDateienProvider);
    final datei = await dienst.datei(dateiId);
    final inhalt = await dienst.lesen(dateiId);
    if (datei == null || inhalt == null) return const [];
    return etikettAlsBilder(datei, inhalt, pdfSeiten: pdfSeitenGerastert);
  },
);

/// Lässt den Scan wählen und legt ihn als Originaletikett ab. Ein
/// früheres bleibt unter den Dateien des Projekts.
Future<void> originaletikettEinfuegen(
  BuildContext context,
  WidgetRef ref,
  EntwicklungsProjekt projekt,
) async {
  final gewaehlt = await dateienWaehlen(
    context,
    titel: 'Originaletikett wählen — Bild oder PDF',
    endungen: kEtikettEndungen,
    mehrere: false,
  );
  if (gewaehlt.isEmpty || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final repo = ref.read(projektRepositoryProvider);
  final sicherung = ref.read(autoBackupTriggerProvider);
  try {
    final id = await dateiAblegen(ref, gewaehlt.first, projektId: projekt.id);
    await repo.originaletikettSetzen(projekt.id, id);
    sicherung.fireDebounced(reason: 'Originaletikett');
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Das Originaletikett ließ sich nicht ablegen: ${fehlerText(e)}',
        ),
      ),
    );
  }
}

/// Löst das Originaletikett vom Etikett nach LMIV — die Datei bleibt unter
/// „Dateien" und lässt sich dort löschen.
Future<void> originaletikettLoesen(
  BuildContext context,
  WidgetRef ref,
  EntwicklungsProjekt projekt,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final repo = ref.read(projektRepositoryProvider);
  final sicherung = ref.read(autoBackupTriggerProvider);
  try {
    await repo.originaletikettLoesen(projekt.id);
    sicherung.fireDebounced(reason: 'Originaletikett');
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Das Originaletikett ist gelöst — die Datei bleibt unter '
          '„Dateien".',
        ),
      ),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(fehlerText(e))),
    );
  }
}

/// Lässt im Scan auf das Etikett zoomen: Was im Rahmen steht, zeigt der
/// Projektbericht vergrößert. Speichert den Ausschnitt — oder keinen, dann
/// steht wieder das ganze Etikett im Bericht.
Future<void> originaletikettVergroessern(
  BuildContext context,
  WidgetRef ref,
  EntwicklungsProjekt projekt,
  List<Uint8List> seiten,
) async {
  final datei = projekt.etikettDateiId;
  if (datei == null || seiten.isEmpty) return;
  final messenger = ScaffoldMessenger.of(context);
  final repo = ref.read(projektRepositoryProvider);
  final sicherung = ref.read(autoBackupTriggerProvider);
  final wahl = await showDialog<_AusschnittWahl>(
    context: context,
    builder: (_) => _AusschnittDialog(
      datei: datei,
      seite: seiten.first,
      seitenAnzahl: seiten.length,
      bisher: etikettAusschnitt(projekt),
    ),
  );
  if (wahl == null) return;
  try {
    await repo.originaletikettAusschnitt(projekt.id, wahl.ausschnitt);
    sicherung.fireDebounced(reason: 'Originaletikett');
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Der Ausschnitt ließ sich nicht speichern: ${fehlerText(e)}',
        ),
      ),
    );
  }
}

/// Was der Dialog liefert: ein Ausschnitt — oder keiner, das ganze
/// Etikett.
class _AusschnittWahl {
  const _AusschnittWahl(this.ausschnitt);

  final EtikettAusschnitt? ausschnitt;
}

/// Der Scan in einem Rahmen von der Form seines Platzes im Bericht — zum
/// Heranzoomen und Verschieben.
class _AusschnittDialog extends StatefulWidget {
  const _AusschnittDialog({
    required this.datei,
    required this.seite,
    required this.seitenAnzahl,
    this.bisher,
  });

  final String datei;

  /// Die erste Seite des Scans.
  final Uint8List seite;
  final int seitenAnzahl;
  final EtikettAusschnitt? bisher;

  @override
  State<_AusschnittDialog> createState() => _AusschnittDialogState();
}

class _AusschnittDialogState extends State<_AusschnittDialog> {
  final _ansicht = TransformationController();

  /// Der Scan in Bildpunkten, wie er angezeigt wird.
  Size? _bild;

  /// Der Rahmen auf dem Bildschirm.
  Size? _rahmen;
  bool _eingestellt = false;
  Object? _fehler;

  @override
  void initState() {
    super.initState();
    _ansicht.addListener(_neuZeichnen);
    _bildGroesse();
  }

  @override
  void dispose() {
    _ansicht.removeListener(_neuZeichnen);
    _ansicht.dispose();
    super.dispose();
  }

  void _neuZeichnen() => setState(() {});

  Future<void> _bildGroesse() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.seite);
      final bild = (await codec.getNextFrame()).image;
      final groesse = Size(bild.width.toDouble(), bild.height.toDouble());
      bild.dispose();
      codec.dispose();
      if (mounted) setState(() => _bild = groesse);
    } catch (e) {
      if (mounted) setState(() => _fehler = e);
    }
  }

  /// Die Ansicht als Matrix: vergrößert um [v], verschoben um [dx], [dy].
  static Matrix4 _matrix(double v, double dx, double dy) =>
      Matrix4(v, 0, 0, 0, 0, v, 0, 0, 0, 0, 1, 0, dx, dy, 0, 1);

  double get _vergroesserung => _ansicht.value.getMaxScaleOnAxis();

  /// Zoomt auf [v] — die Mitte des Rahmens bleibt, wo sie ist.
  void _zoomAuf(double v) {
    final r = _rahmen;
    if (r == null) return;
    final neu = v.clamp(1.0, kEtikettMaxVergroesserung);
    final alt = _vergroesserung;
    final m = _ansicht.value.storage;
    final mitteX = (r.width / 2 - m[12]) / alt;
    final mitteY = (r.height / 2 - m[13]) / alt;
    _ansicht.value = _matrix(
      neu,
      (r.width / 2 - mitteX * neu).clamp(r.width - r.width * neu, 0.0),
      (r.height / 2 - mitteY * neu).clamp(r.height - r.height * neu, 0.0),
    );
  }

  /// Stellt die Ansicht auf den bisherigen Ausschnitt.
  void _einstellen() {
    final a = widget.bisher;
    final bild = _bild;
    final r = _rahmen;
    if (a == null || bild == null || r == null) return;
    final ansicht = ansichtFuer(
      a,
      bildBreite: bild.width,
      bildHoehe: bild.height,
      rahmenBreite: r.width,
      rahmenHoehe: r.height,
    );
    _ansicht.value = _matrix(ansicht.vergroesserung, ansicht.dx, ansicht.dy);
  }

  void _uebernehmen() {
    final bild = _bild;
    final r = _rahmen;
    if (bild == null || r == null) return;
    final m = _ansicht.value.storage;
    Navigator.of(context).pop(
      _AusschnittWahl(
        ausschnittDerAnsicht(
          datei: widget.datei,
          bildBreite: bild.width,
          bildHoehe: bild.height,
          rahmenBreite: r.width,
          rahmenHoehe: r.height,
          vergroesserung: _vergroesserung,
          dx: m[12],
          dy: m[13],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final klein = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final v = _vergroesserung;
    final mehrere = widget.seitenAnzahl > 1
        ? ' Der Ausschnitt gilt für alle ${widget.seitenAnzahl} Seiten.'
        : '';

    final Widget inhalt;
    if (_fehler case final fehler?) {
      inhalt = Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Der Scan lässt sich hier nicht zeigen: ${fehlerText(fehler)}',
            textAlign: TextAlign.center,
            style: klein,
          ),
        ),
      );
    } else if (_bild == null) {
      inhalt = const Center(child: CircularProgressIndicator());
    } else {
      inhalt = LayoutBuilder(
        builder: (context, c) {
          _rahmen = c.biggest;
          if (!_eingestellt) {
            _eingestellt = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _einstellen();
            });
          }
          return InteractiveViewer(
            key: const ValueKey('originaletikett-ausschnitt'),
            transformationController: _ansicht,
            minScale: 1,
            maxScale: kEtikettMaxVergroesserung,
            child: Image.memory(
              widget.seite,
              fit: BoxFit.contain,
              gaplessPlayback: true,
            ),
          );
        },
      );
    }

    return AlertDialog(
      title: const Text('Originaletikett vergrößern'),
      content: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Mit dem Mausrad oder dem Regler auf das Etikett zoomen und '
              'es mit der Maus zurechtschieben. Was im Rahmen steht, zeigt '
              'der Projektbericht — so groß, wie dort Platz ist.$mehrere',
              style: klein,
            ),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: kEtikettRahmenForm,
              child: DecoratedBox(
                // Der Rahmen über dem Scan; dahinter Weiß wie das Papier.
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  border:
                      Border.all(color: theme.colorScheme.primary, width: 2),
                ),
                child: ColoredBox(
                  color: Colors.white,
                  child: ClipRect(child: inhalt),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  tooltip: 'Kleiner',
                  icon: const Icon(Icons.zoom_out),
                  onPressed: v > 1 ? () => _zoomAuf(v / 1.25) : null,
                ),
                Expanded(
                  child: Slider(
                    key: const ValueKey('originaletikett-zoom'),
                    // Logarithmisch: 1× links, 10× rechts.
                    value: (math.log(v) / math.log(kEtikettMaxVergroesserung))
                        .clamp(0.0, 1.0),
                    onChanged: _bild == null
                        ? null
                        : (s) => _zoomAuf(
                              math.pow(kEtikettMaxVergroesserung, s).toDouble(),
                            ),
                  ),
                ),
                IconButton(
                  tooltip: 'Größer',
                  icon: const Icon(Icons.zoom_in),
                  onPressed: v < kEtikettMaxVergroesserung
                      ? () => _zoomAuf(v * 1.25)
                      : null,
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    '${Format.zahl(v, nachkomma: 1)}×',
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('originaletikett-ganz'),
          onPressed: () => _ansicht.value = Matrix4.identity(),
          child: const Text('Ganzes Etikett'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          key: const ValueKey('originaletikett-uebernehmen'),
          onPressed: _bild == null ? null : _uebernehmen,
          child: const Text('Übernehmen'),
        ),
      ],
    );
  }
}

/// Eine Seite des Scans in der Vorschau, [hoehe] hoch — mit einem
/// Ausschnitt nur der, wie im Bericht.
Widget _vorschauSeite(
  Uint8List seite,
  EtikettAusschnitt? a, {
  required double hoehe,
  required Widget Function() fehler,
}) {
  if (a == null) {
    return Image.memory(
      seite,
      height: hoehe,
      // Als Vorschau klein entpackt — ein Scan mit 150 dpi wäre sonst
      // Megabytes im Speicher.
      cacheHeight: (hoehe * 2).round(),
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => fehler(),
    );
  }
  // Align mit Breiten- und Höhenanteil zeigt genau den Ausschnitt:
  // Bei x = 0 steht er links, bei x = 1 − Breite rechts.
  double lage(double von, double anteil) =>
      anteil < 1 ? von / (1 - anteil) * 2 - 1 : 0;
  return ConstrainedBox(
    constraints: BoxConstraints(maxWidth: hoehe * 3),
    child: SizedBox(
      height: hoehe,
      child: FittedBox(
        child: ClipRect(
          child: Align(
            alignment: Alignment(lage(a.x, a.breite), lage(a.y, a.hoehe)),
            widthFactor: a.breite,
            heightFactor: a.hoehe,
            child: Image.memory(
              seite,
              // Genug Bildpunkte für den vergrößerten Ausschnitt.
              cacheHeight: (hoehe * 2 / a.hoehe).round().clamp(360, 2400),
              errorBuilder: (_, __, ___) => fehler(),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Zeigt das Originaletikett groß — mit dem Mausrad oder zwei Fingern
/// vergrößern, ziehen zum Verschieben.
Future<void> originaletikettAnsehen(
  BuildContext context,
  List<Uint8List> seiten, {
  required String titel,
}) =>
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final groesse = MediaQuery.sizeOf(ctx);
        return Dialog(
          insetPadding: const EdgeInsets.all(24),
          child: SizedBox(
            width: groesse.width * .9,
            height: groesse.height * .9,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          titel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(ctx).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Schließen',
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: InteractiveViewer(
                    maxScale: 8,
                    child: Row(
                      children: [
                        for (final seite in seiten)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: ColoredBox(
                                color: Colors.white,
                                child: Image.memory(
                                  seite,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

/// Das Originaletikett im Punkt „Etikett erstellt": einfügen, ansehen,
/// ersetzen, lösen.
class OriginaletikettFeld extends ConsumerWidget {
  const OriginaletikettFeld({super.key, required this.projekt});

  final EntwicklungsProjekt projekt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final klein = theme.textTheme.bodySmall?.copyWith(color: grau);
    final kopf = Text('Originaletikett', style: theme.textTheme.titleSmall);
    final id = projekt.etikettDateiId;

    if (id == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 14, 8, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            kopf,
            const SizedBox(height: 2),
            Text(
              'Den Scan des gedruckten Etiketts hier ablegen — ein Bild oder '
              'ein PDF. So liegen die Prüfung und das Etikett beisammen, auch '
              'im Projektbericht.',
              style: klein,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('originaletikett-einfuegen'),
              onPressed: () => originaletikettEinfuegen(context, ref, projekt),
              icon: const Icon(Icons.document_scanner_outlined, size: 18),
              label: const Text('Scan einfügen …'),
            ),
          ],
        ),
      );
    }

    final datei = ref.watch(entwicklungsDateiProvider(id)).valueOrNull;
    final bilder = ref.watch(originaletikettBilderProvider(id));
    final seiten = bilder.valueOrNull ?? const <Uint8List>[];
    final titel = datei?.name ?? 'Originaletikett';
    final ausschnitt = etikettAusschnitt(projekt);
    void ansehen() => originaletikettAnsehen(context, seiten, titel: titel);

    final Widget vorschau = bilder.when(
      skipLoadingOnReload: true,
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => HinweisBox(
        'Das Originaletikett ließ sich nicht lesen: ${fehlerText(e)}',
        art: StatusArt.fehler,
      ),
      data: (liste) => liste.isEmpty
          ? Text(
              'Keine Vorschau — „Öffnen" zeigt die Datei.',
              style: klein,
            )
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (i, seite) in liste.indexed)
                  Tooltip(
                    message: 'Groß ansehen',
                    child: InkWell(
                      key: ValueKey('originaletikett-seite-$i'),
                      onTap: ansehen,
                      child: DecoratedBox(
                        // Weiß wie das Papier — auch im dunklen Design.
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: _vorschauSeite(
                            seite,
                            ausschnitt,
                            hoehe: 180,
                            fehler: () => SizedBox(
                              height: 180,
                              width: 140,
                              child: Center(
                                child: Text(
                                  'Dieses Bildformat lässt sich hier nicht '
                                  'zeigen.',
                                  textAlign: TextAlign.center,
                                  style: klein,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          kopf,
          const SizedBox(height: 6),
          vorschau,
          if (ausschnitt != null && seiten.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Im Bericht steht der vergrößerte Ausschnitt.',
                style: klein,
              ),
            ),
          const SizedBox(height: 4),
          if (datei != null)
            DateiZeile(
              datei: datei,
              zusatz: 'Originaletikett',
              loeschbar: false,
            ),
          Wrap(
            spacing: 4,
            children: [
              if (seiten.isNotEmpty) ...[
                TextButton.icon(
                  key: const ValueKey('originaletikett-ansehen'),
                  onPressed: ansehen,
                  icon: const Icon(Icons.zoom_in, size: 18),
                  label: const Text('Groß ansehen'),
                ),
                Tooltip(
                  message: 'Auf das Etikett zoomen — der Bericht zeigt den '
                      'Ausschnitt so groß, wie Platz ist',
                  child: TextButton.icon(
                    key: const ValueKey('originaletikett-vergroessern'),
                    onPressed: () => originaletikettVergroessern(
                      context,
                      ref,
                      projekt,
                      seiten,
                    ),
                    icon: const Icon(Icons.crop, size: 18),
                    label: Text(
                      ausschnitt == null
                          ? 'Vergrößern …'
                          : 'Ausschnitt ändern …',
                    ),
                  ),
                ),
              ],
              TextButton.icon(
                key: const ValueKey('originaletikett-ersetzen'),
                onPressed: () =>
                    originaletikettEinfuegen(context, ref, projekt),
                icon: const Icon(Icons.document_scanner_outlined, size: 18),
                label: const Text('Ersetzen …'),
              ),
              Tooltip(
                message: 'Die Datei bleibt unter „Dateien"',
                child: TextButton.icon(
                  key: const ValueKey('originaletikett-loesen'),
                  onPressed: () => originaletikettLoesen(context, ref, projekt),
                  icon: const Icon(Icons.link_off, size: 18),
                  label: const Text('Lösen'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
