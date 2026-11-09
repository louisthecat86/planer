import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database.dart' show Rezeptur;
import '../../../core/ui/bausteine.dart';
import '../bericht/bericht_drucken.dart';
import '../bericht/formblatt_dialog.dart';
import '../daten/entwicklung_repository.dart';
import '../rezepturen/fleischanteil_dialog.dart';
import '../rezepturen/rezeptur_wahl.dart';
import '../rezepturen/rezepturen_ansicht.dart' show oeffneRezeptur;

/// Öffnet die Rückrechnung.
Future<void> oeffneRueckrechnung(BuildContext context) =>
    context.pushNamed<void>('entwicklungRueckrechnung');

/// „Fleischanteil einstellen" aus den Werkzeugen: erst die Rezeptur
/// wählen, dann ihren neuesten Stand einstellen — danach öffnet sich die
/// Rezeptur mit dem Ergebnis. Ist der Stand abgeschlossen, entsteht im
/// Fenster ein neuer.
Future<void> fleischanteilMitWahl(BuildContext context, WidgetRef ref) async {
  final rezepturen = await ref.read(rezepturenProvider.future);
  final versionen = await ref.read(alleVersionenProvider.future);
  if (!context.mounted) return;
  final staende = neuesteStaende(versionen);
  final rezeptur = await showDialog<Rezeptur>(
    context: context,
    builder: (_) => RezepturWahlDialog(
      titel: 'Fleischanteil einstellen',
      hinweis: 'Für welche Rezeptur? Eingestellt wird ihr neuester Stand — '
          'ist er abgeschlossen, entsteht daraus ein neuer.',
      rezepturen: rezepturen,
      staende: staende,
    ),
  );
  final stand = rezeptur == null ? null : staende[rezeptur.id];
  if (rezeptur == null || stand == null || !context.mounted) return;
  final id = await fleischanteilOeffnen(
    context,
    rezepturId: rezeptur.id,
    version: stand,
  );
  if (id == null || !context.mounted) return;
  await oeffneRezeptur(context, rezeptur.id);
}

/// Der Reiter „Werkzeuge": Rückrechnung, Fleischanteil, Kopf- und Fußzeile
/// und Vorlage des Projektberichts. Die Zahlen der Entwicklung stehen im
/// Reiter „Statistik".
class WerkzeugeAnsicht extends ConsumerWidget {
  const WerkzeugeAnsicht({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final klein = theme.textTheme.bodyMedium?.copyWith(color: grau);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: 460,
              child: Bereich(
                titel: 'Rezeptur rückrechnen',
                icon: Icons.manage_search,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aus Zutatenliste und Nährwerttabelle eines Etiketts '
                      'die Mengen schätzen — etwa für ein Muster vom Kunden. '
                      'Mengenangaben wie „Schweinefleisch 65 %" stehen fest, '
                      'die Reihenfolge der Liste bleibt.',
                      style: klein,
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: () => oeffneRueckrechnung(context),
                      icon: const Icon(Icons.manage_search, size: 18),
                      label: const Text('Rückrechnen'),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 460,
              child: Bereich(
                titel: 'Fleischanteil einstellen',
                icon: Icons.tune,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fleisch wird gemeinsam größer oder kleiner, Wasser '
                      'oder Eis gleicht aus — bis der Anteil laut Etikett '
                      'oder im Rohgemisch stimmt. Eingestellt wird der '
                      'neueste Stand der Rezeptur; in der Rezeptur selbst '
                      'steht es in der Leiste der Stände.',
                      style: klein,
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      key: const ValueKey('werkzeug-fleischanteil'),
                      onPressed: () => fleischanteilMitWahl(context, ref),
                      icon: const Icon(Icons.tune, size: 18),
                      label: const Text('Rezeptur wählen…'),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 460,
              child: Bereich(
                titel: 'Projektbericht',
                icon: Icons.picture_as_pdf_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kopf- und Fußzeile wie auf den Formblättern: Nummer, '
                      'Logo, Erstellt und Geprüft von, Version und Stand. Die '
                      'leere Vorlage zeigt, was wo im Bericht steht — zum '
                      'Ablegen bei den Formblättern.',
                      style: klein,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          key: const ValueKey('werkzeug-kopf-fuss'),
                          onPressed: () => formblattBearbeiten(context),
                          icon: const Icon(Icons.edit_note, size: 18),
                          label: const Text('Kopf- und Fußzeile…'),
                        ),
                        FilledButton.icon(
                          key: const ValueKey('werkzeug-berichtvorlage'),
                          onPressed: () => projektberichtVorlage(context, ref),
                          icon: const Icon(Icons.save_alt, size: 18),
                          label: const Text('Vorlage speichern…'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
