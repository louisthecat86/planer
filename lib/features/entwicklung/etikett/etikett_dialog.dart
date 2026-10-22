import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/theme/app_stil.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/fehler_text.dart';
import '../projekte/datei_aktionen.dart' show sichererDateiname;
import 'etikett.dart';
import 'etikett_dienst.dart';
import 'etikett_pdf.dart';

// Das Etikett eines Stands ansehen, als Text kopieren oder als
// PDF-Entwurf öffnen — ein abgeschlossener Stand aus seinen eingefrorenen
// Daten, ein Entwurf so, wie er gerade ist.

/// Öffnet das Etikett des Stands [versionId].
Future<void> etikettZeigen(BuildContext context, String versionId) =>
    showDialog<void>(
      context: context,
      builder: (_) => EtikettDialog(versionId: versionId),
    );

/// Öffnet den PDF-Entwurf in der Druckvorschau — dort lässt er sich
/// drucken oder speichern.
Future<void> etikettPdfOeffnen(BuildContext context, EtikettInhalt e) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = await baueEtikettPdf(e);
    await Printing.layoutPdf(
      name: 'Etikett_${sichererDateiname(e.stand.isEmpty ? e.bezeichnung : e.stand)}',
      onLayout: (_) async => bytes,
    );
  } catch (fehler) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Der PDF-Entwurf ließ sich nicht erstellen. (${fehlerText(fehler)})',
        ),
      ),
    );
  }
}

/// Das Etikett eines Stands: Vorschau, Text kopieren, PDF-Entwurf.
class EtikettDialog extends ConsumerWidget {
  const EtikettDialog({super.key, required this.versionId});

  final String versionId;

  Future<void> _kopieren(BuildContext context, EtikettInhalt e) async {
    await Clipboard.setData(ClipboardData(text: etikettText(e)));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Etikett als Text kopiert.')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final inhalt = ref.watch(etikettProvider(versionId));
    final e = inhalt.valueOrNull;
    return AlertDialog(
      icon: const Icon(Icons.label_outline),
      title: const Text('Etikett'),
      content: SizedBox(
        width: 560,
        child: inhalt.when(
          skipLoadingOnReload: true,
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (f, _) => HinweisBox(
            fehlerText(f),
            art: StatusArt.fehler,
            titel: 'Das Etikett ließ sich nicht berechnen',
            auswaehlbar: true,
          ),
          data: (e) => e == null
              ? const LeerHinweis('Diesen Stand gibt es nicht mehr.')
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (e.stand.isNotEmpty)
                        Text(
                          e.stand,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: grau,
                          ),
                        ),
                      const SizedBox(height: 10),
                      EtikettVorschau(inhalt: e),
                      if (e.allergene.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Enthaltene Allergene: ${aufzaehlung(e.allergene)} '
                          '— in der Zutatenliste in Großbuchstaben.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: grau,
                          ),
                        ),
                      ],
                      if (e.fehlt.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        HinweisBox(
                          e.fehlt.map((f) => '• $f').join('\n'),
                          art: StatusArt.warnung,
                          titel: 'Für das fertige Etikett fehlt noch',
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: e == null ? null : () => _kopieren(context, e),
          icon: const Icon(Icons.content_copy, size: 18),
          label: const Text('Text kopieren'),
        ),
        OutlinedButton.icon(
          onPressed: e == null ? null : () => etikettPdfOeffnen(context, e),
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: const Text('PDF-Entwurf…'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Schließen'),
        ),
      ],
    );
  }
}

/// Das Etikett als Vorschau — wie ein Aufkleber auf hellem Grund. Was
/// erst beim Verpacken feststeht, steht grau und kursiv darin.
class EtikettVorschau extends StatelessWidget {
  const EtikettVorschau({super.key, required this.inhalt});

  final EtikettInhalt inhalt;

  @override
  Widget build(BuildContext context) {
    final e = inhalt;
    // Ein Etikett ist hell — auch im dunklen Erscheinungsbild.
    const papier = Color(0xFFFFFFFF);
    const schrift = Color(0xFF1B1B1B);
    const leise = Color(0xFF6B6B6B);
    const linie = Color(0xFFBDBDBD);
    const klein = TextStyle(fontSize: 12.5, height: 1.35, color: schrift);
    final platzhalter = klein.copyWith(color: leise, fontStyle: FontStyle.italic);
    Widget zeile(String text, {TextStyle? stil}) => Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(text, style: stil ?? klein),
        );
    return Center(
      child: Container(
        key: const ValueKey('etikett-vorschau'),
        constraints: const BoxConstraints(maxWidth: 440),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: papier,
          borderRadius: AppMasse.ecken,
          border: Border.all(color: const Color(0xFF424242)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              e.bezeichnung,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: schrift,
              ),
            ),
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                style: klein,
                children: [
                  const TextSpan(
                    text: 'Zutaten: ',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: e.zutatenliste),
                ],
              ),
            ),
            if (e.spurenSatz.isNotEmpty) zeile(e.spurenSatz),
            const SizedBox(height: 10),
            const Text(
              'Durchschnittliche Nährwerte je 100 g',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: schrift,
              ),
            ),
            const SizedBox(height: 2),
            for (final n in e.naehrwerte)
              Container(
                padding: EdgeInsets.fromLTRB(n.davon ? 14 : 0, 2, 0, 2),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: linie)),
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(n.label, style: klein)),
                    Text(
                      n.wert,
                      style: klein.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            if (e.lagerung.isNotEmpty) zeile('Lagerung: ${e.lagerung}'),
            if (e.zubereitung.isNotEmpty)
              zeile('Zubereitung: ${e.zubereitung}'),
            for (final h in e.hinweise) zeile(h),
            if (e.schutzgas) zeile('Unter Schutzatmosphäre verpackt.'),
            zeile(
              e.nettofuellmenge.isEmpty
                  ? 'Nettofüllmenge: …'
                  : 'Nettofüllmenge: ${e.nettofuellmenge}',
              stil: e.nettofuellmenge.isEmpty ? platzhalter : null,
            ),
            zeile(
              'Zu verbrauchen bis / mindestens haltbar bis: beim Verpacken',
              stil: platzhalter,
            ),
            zeile('Name und Anschrift des Herstellers', stil: platzhalter),
          ],
        ),
      ),
    );
  }
}
