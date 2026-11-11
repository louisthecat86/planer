import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/services/auto_backup_trigger.dart';
import '../../../core/theme/app_stil.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/fehler_text.dart';
import '../daten/dateien.dart';
import '../freigabe/produktfoto_artikel.dart';
import 'datei_aktionen.dart';
import 'projekt_modell.dart';
import 'projekt_repository.dart';
import 'projekt_screen.dart' show ProjektReiter, projektReiterZeigen;

// Das Produktfoto eines Projekts (F38): gepflegt im Reiter „Produkt" neben
// der Sensorik — so, wie es in der Spezifikation steht —, in der Übersicht
// klein oder als Hinweis, dass es noch fehlt.
//
// Es ist ein Punkt der Checkliste. Solange es keins gibt, lässt er sich mit
// „Später" zurückstellen (F37): Er bleibt offen, „Als Nächstes" geht aber
// weiter, und der Projektkopf zeigt dezent „Produktfoto fehlt noch".
//
// Liegen beim Projekt schon Bilder — etwa Musterfotos vom Handy —, stehen
// sie beim Wählen zur Wahl. Ist das Projekt als Artikel freigegeben, kommt
// das Produktfoto auch zu den Fotos des Artikels (produktfoto_artikel.dart).

/// Der Punkt der Checkliste, um den es geht.
const String kProduktfotoPunkt = 'produktfotoHinterlegt';

/// Ist das Produktfoto von [projekt] zurückgestellt?
bool produktfotoZurueckgestellt(EntwicklungsProjekt projekt) =>
    projekt.bildDateiId == null &&
    checklisteZurueckgestellt(projekt.checkliste).contains(kProduktfotoPunkt);

/// Ist das Projekt [projektId] schon als Artikel freigegeben, kommt sein
/// Produktfoto auch zu den Fotos des Artikels. Gibt den Satz dazu zurück —
/// null, wenn dort nichts dazugekommen ist.
Future<String?> produktfotoZumArtikel(
  ProduktfotoUebernahme uebernahme,
  String projektId,
) async {
  try {
    final artikel = await uebernahme.uebernehmen(projektId);
    return artikel == null
        ? null
        : 'Es liegt jetzt auch bei den Fotos des Artikels '
            '${artikel.artikelnummer}.';
  } catch (_) {
    // Das Produktfoto im Projekt steht — der Artikel bekommt es mit der
    // nächsten Freigabe.
    return null;
  }
}

/// Nimmt die Datei [datei] des Projekts als Produktfoto. Ein früheres
/// bleibt als Datei beim Projekt.
Future<void> produktfotoAusDatei(
  BuildContext context,
  WidgetRef ref,
  String projektId,
  EntwicklungsDatei datei,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final repo = ref.read(projektRepositoryProvider);
  final sicherung = ref.read(autoBackupTriggerProvider);
  final uebernahme = ref.read(produktfotoUebernahmeProvider);
  try {
    await repo.produktfotoSetzen(projektId, datei.id);
    final dazu = await produktfotoZumArtikel(uebernahme, projektId);
    sicherung.fireDebounced(reason: 'Produktfoto');
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ['„${datei.name}" ist jetzt das Produktfoto.', if (dazu != null) dazu]
              .join(' '),
        ),
      ),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('Das ließ sich nicht speichern: ${fehlerText(e)}'),
      ),
    );
  }
}

/// Lässt ein Bild wählen und nimmt es als Produktfoto. Liegen beim Projekt
/// schon Bilder, stehen sie zuerst zur Wahl — sonst geht es gleich zum
/// Bild vom Rechner; dabei wird ein früheres Produktfoto gelöscht.
Future<void> produktfotoWaehlen(
  BuildContext context,
  WidgetRef ref,
  EntwicklungsProjekt projekt,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final dateien = ref.read(entwicklungDateienProvider);
  final repo = ref.read(projektRepositoryProvider);
  final sicherung = ref.read(autoBackupTriggerProvider);
  final uebernahme = ref.read(produktfotoUebernahmeProvider);

  var bilder = const <EntwicklungsDatei>[];
  try {
    bilder = [
      for (final d in await repo.dateienBeobachten(projekt.id).first)
        if (istBild(d) &&
            d.id != projekt.bildDateiId &&
            d.id != projekt.etikettDateiId)
          d,
    ];
  } catch (_) {
    // Dann eben nur vom Rechner.
  }
  if (!context.mounted) return;
  if (bilder.isNotEmpty) {
    final wahl = await showDialog<_FotoWahl>(
      context: context,
      builder: (_) => _FotoWahlDialog(bilder: bilder),
    );
    if (wahl == null || !context.mounted) return;
    final vorhanden = wahl.datei;
    if (vorhanden != null) {
      await produktfotoAusDatei(context, ref, projekt.id, vorhanden);
      return;
    }
  }

  final datei = await dateiWaehlen(context, nurBilder: true);
  if (datei == null) return;
  try {
    final alt = projekt.bildDateiId;
    final id = await dateien.speichern(
      name: datei.name,
      inhalt: datei.inhalt,
      projektId: projekt.id,
      mimeTyp: mimeTypAus(datei.name),
    );
    await repo.produktfotoSetzen(projekt.id, id);
    if (alt != null) await dateien.loeschen(alt);
    final dazu = await produktfotoZumArtikel(uebernahme, projekt.id);
    sicherung.fireDebounced(reason: 'Produktfoto');
    if (dazu != null) {
      messenger.showSnackBar(
        SnackBar(content: Text('Das Produktfoto ist gesetzt. $dazu')),
      );
    }
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('Das Foto ließ sich nicht ablegen: ${fehlerText(e)}'),
      ),
    );
  }
}

/// Was im Dialog gewählt wurde: ein Bild des Projekts — oder, ohne
/// [datei], eins vom Rechner.
typedef _FotoWahl = ({EntwicklungsDatei? datei});

/// Die Bilder, die schon beim Projekt liegen, zur Wahl als Produktfoto —
/// und der Weg zu einem Bild vom Rechner.
class _FotoWahlDialog extends StatelessWidget {
  const _FotoWahlDialog({required this.bilder});

  final List<EntwicklungsDatei> bilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    return AlertDialog(
      title: const Text('Produktfoto wählen'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Bilder, die schon bei diesem Projekt liegen:',
                style: theme.textTheme.bodySmall?.copyWith(color: grau),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final d in bilder)
                    SizedBox(
                      width: 128,
                      child: InkWell(
                        key: ValueKey('fotowahl-${d.id}'),
                        borderRadius: AppMasse.ecken,
                        onTap: () =>
                            Navigator.of(context).pop<_FotoWahl>((datei: d)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              height: 96,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerLow,
                                borderRadius: AppMasse.ecken,
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: FotoAnsicht(dateiId: d.id, klein: true),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              d.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton.tonalIcon(
          key: const ValueKey('fotowahl-rechner'),
          onPressed: () => Navigator.of(context).pop<_FotoWahl>((datei: null)),
          icon: const Icon(Icons.folder_open, size: 18),
          label: const Text('Vom Rechner wählen …'),
        ),
      ],
    );
  }
}

/// Löscht das Produktfoto nach Rückfrage.
Future<void> produktfotoEntfernen(
  BuildContext context,
  WidgetRef ref,
  EntwicklungsProjekt projekt,
) async {
  final alt = projekt.bildDateiId;
  if (alt == null) return;
  final ja = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Produktfoto entfernen?'),
      content: const Text(
        'Das Foto wird gelöscht. In der Checkliste ist „Produktfoto" danach '
        'wieder offen.',
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
          child: const Text('Entfernen'),
        ),
      ],
    ),
  );
  if (ja != true || !context.mounted) return;
  final dateien = ref.read(entwicklungDateienProvider);
  final repo = ref.read(projektRepositoryProvider);
  final sicherung = ref.read(autoBackupTriggerProvider);
  await dateien.loeschen(alt);
  await repo.dateiVerweiseEntfernen(alt);
  sicherung.fireDebounced(reason: 'Produktfoto');
}

/// Stellt das Produktfoto zurück (F37) oder nimmt das zurück.
Future<void> produktfotoZurueckstellen(
  WidgetRef ref,
  String projektId, {
  required bool zurueck,
}) async {
  final repo = ref.read(projektRepositoryProvider);
  final sicherung = ref.read(autoBackupTriggerProvider);
  await repo.checklisteZurueckstellen(
    projektId,
    schluessel: kProduktfotoPunkt,
    zurueck: zurueck,
  );
  sicherung.fireDebounced(reason: 'Checkliste');
}

/// Das Produktfoto zum Pflegen — im Reiter „Produkt" neben der Sensorik.
class ProduktFoto extends ConsumerWidget {
  const ProduktFoto({super.key, required this.projekt});

  final EntwicklungsProjekt projekt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final bildId = projekt.bildDateiId;
    final zurueck = produktfotoZurueckgestellt(projekt);

    final Widget inhalt;
    if (bildId != null) {
      inhalt = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 180, child: FotoAnsicht(dateiId: bildId)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  key: const ValueKey('foto-anderes'),
                  onPressed: () => produktfotoWaehlen(context, ref, projekt),
                  icon: const Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 18,
                  ),
                  label: const Text('Anderes Foto…'),
                ),
              ),
              IconButton(
                key: const ValueKey('foto-entfernen'),
                tooltip: 'Foto entfernen',
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () => produktfotoEntfernen(context, ref, projekt),
              ),
            ],
          ),
        ],
      );
    } else {
      inhalt = Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              zurueck ? Icons.schedule : Icons.add_a_photo_outlined,
              size: 30,
              color: grau,
            ),
            const SizedBox(height: 6),
            Text(
              zurueck
                  ? 'Zurückgestellt, bis es ein Foto gibt'
                  : 'Noch kein Produktfoto',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: grau),
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              key: const ValueKey('foto-waehlen'),
              onPressed: () => produktfotoWaehlen(context, ref, projekt),
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: const Text('Foto wählen…'),
            ),
            const SizedBox(height: 2),
            if (zurueck)
              TextButton(
                key: const ValueKey('foto-wieder'),
                onPressed: () =>
                    produktfotoZurueckstellen(ref, projekt.id, zurueck: false),
                child: const Text('Nicht mehr zurückstellen'),
              )
            else
              Tooltip(
                message: 'Gibt es noch kein Foto? Dann geht „Als Nächstes" '
                    'weiter; der Kopf erinnert dezent daran.',
                child: TextButton(
                  key: const ValueKey('foto-spaeter'),
                  onPressed: () =>
                      produktfotoZurueckstellen(ref, projekt.id, zurueck: true),
                  child: const Text('Später'),
                ),
              ),
          ],
        ),
      );
    }

    return Container(
      key: const ValueKey('produktfoto'),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppMasse.ecken,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Produktfoto',
            style: theme.textTheme.labelMedium?.copyWith(color: grau),
          ),
          const SizedBox(height: 6),
          inhalt,
        ],
      ),
    );
  }
}

/// Das Produktfoto in der Übersicht: klein, antippen führt in den Reiter
/// „Produkt" — ohne Foto nur ein dezenter Hinweis.
class ProduktFotoUebersicht extends StatelessWidget {
  const ProduktFotoUebersicht({super.key, required this.projekt});

  final EntwicklungsProjekt projekt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final bildId = projekt.bildDateiId;
    void zumProdukt() => projektReiterZeigen(context, ProjektReiter.produkt);
    return Bereich(
      titel: 'Produktfoto',
      icon: Icons.image_outlined,
      child: bildId == null
          ? Row(
              children: [
                Icon(
                  produktfotoZurueckgestellt(projekt)
                      ? Icons.schedule
                      : Icons.no_photography_outlined,
                  size: 18,
                  color: grau,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    produktfotoZurueckgestellt(projekt)
                        ? 'Fehlt noch — zurückgestellt'
                        : 'Fehlt noch',
                    style: theme.textTheme.bodyMedium?.copyWith(color: grau),
                  ),
                ),
                TextButton(
                  key: const ValueKey('uebersicht-foto'),
                  onPressed: zumProdukt,
                  child: const Text('Im Reiter „Produkt"'),
                ),
              ],
            )
          : Tooltip(
              message: 'Im Reiter „Produkt" ändern',
              child: InkWell(
                key: const ValueKey('uebersicht-foto'),
                onTap: zumProdukt,
                borderRadius: AppMasse.ecken,
                child: SizedBox(
                  height: 140,
                  child: FotoAnsicht(dateiId: bildId),
                ),
              ),
            ),
    );
  }
}

/// Ein Foto aus den Dateien der Entwicklung, eingepasst.
class FotoAnsicht extends ConsumerWidget {
  const FotoAnsicht({super.key, required this.dateiId, this.klein = false});

  final String dateiId;

  /// Als Vorschaubild: statt erklärender Texte nur ein Symbol.
  final bool klein;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget fehlt(String text) => klein
        ? Center(
            child: Tooltip(
              message: text,
              child: Icon(
                Icons.broken_image_outlined,
                size: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          )
        : LeerHinweis(text, icon: Icons.broken_image_outlined);
    return ref.watch(dateiInhaltProvider(dateiId)).when(
          skipLoadingOnReload: true,
          loading: () => Center(
            child: klein
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const CircularProgressIndicator(),
          ),
          error: (e, _) => klein
              ? fehlt('Das Foto ließ sich nicht lesen: ${fehlerText(e)}')
              : HinweisBox(
                  'Das Foto ließ sich nicht lesen: ${fehlerText(e)}',
                  art: StatusArt.fehler,
                ),
          data: (bytes) => bytes == null
              ? fehlt('Der Inhalt des Fotos fehlt.')
              : Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      fehlt('Dieses Bildformat lässt sich hier nicht zeigen.'),
                ),
        );
  }
}
