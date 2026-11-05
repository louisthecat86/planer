import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/database/database.dart';
import '../../../core/services/auto_backup_trigger.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/fehler_text.dart';
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
                              child: Image.memory(
                                seite,
                                fit: BoxFit.contain,
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
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Image.memory(
                            seite,
                            height: 180,
                            // Als Vorschau klein entpackt — ein Scan mit
                            // 150 dpi wäre sonst Megabytes im Speicher.
                            cacheHeight: 360,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => SizedBox(
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
              if (seiten.isNotEmpty)
                TextButton.icon(
                  key: const ValueKey('originaletikett-ansehen'),
                  onPressed: ansehen,
                  icon: const Icon(Icons.zoom_in, size: 18),
                  label: const Text('Groß ansehen'),
                ),
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
