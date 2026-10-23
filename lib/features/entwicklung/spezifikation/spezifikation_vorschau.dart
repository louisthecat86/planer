import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_stil.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/fehler_text.dart';
import 'spezifikation_dienst.dart';
import 'spezifikation_werte.dart';

// Die Vorschau im Reiter „Produkt": was mit dem gewählten Stand in der
// Spezifikation stünde — Artikel, Zutaten, Allergene, Nährwerte,
// Hilfsstoffe, Sensorik mit Produktfoto, Lagerung. Was fehlt, steht in
// Warnfarbe da, mit dem Ort, an dem man es einträgt.

/// Was mit dem Stand [versionId] in der Spezifikation stünde.
class SpezVorschau extends ConsumerWidget {
  const SpezVorschau({
    super.key,
    required this.projektId,
    required this.versionId,
    this.produktfoto,
  });

  final String projektId;
  final String versionId;

  /// Ob es ein Produktfoto gibt — null: keine Zeile dafür.
  final bool? produktfoto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vorschau = ref.watch(
      spezVorschauProvider((projektId: projektId, versionId: versionId)),
    );
    final w = vorschau.valueOrNull;
    final stand = w?['stand'] ?? '';
    return Bereich(
      titel: 'Was in die Spezifikation kommt',
      icon: Icons.preview_outlined,
      untertitel: stand.isEmpty ? null : 'mit $stand · deutsch',
      innenAbstand: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: vorschau.when(
        skipLoadingOnReload: true,
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: LinearProgressIndicator(),
        ),
        error: (e, _) => HinweisBox(
          fehlerText(e),
          art: StatusArt.fehler,
          titel: 'Die Vorschau ließ sich nicht berechnen',
          auswaehlbar: true,
        ),
        data: (w) => w == null
            ? const LeerHinweis('Diesen Stand gibt es nicht mehr.')
            : _Inhalt(werte: w, produktfoto: produktfoto),
      ),
    );
  }
}

class _Inhalt extends StatelessWidget {
  const _Inhalt({required this.werte, this.produktfoto});

  final Map<String, String> werte;
  final bool? produktfoto;

  @override
  Widget build(BuildContext context) {
    final w = werte;
    String t(String schluessel) => w[schluessel]?.trim() ?? '';
    const beiAngaben = 'fehlt — bei „Angaben" eintragen';
    final gewicht = [
      if (t('sensorik.gewicht').isNotEmpty) t('sensorik.gewicht'),
      if (t('toleranz').isNotEmpty) 'Toleranz ${t('toleranz')}',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Zeile(
          label: 'Artikelnummer',
          wert: t('artikelnummer'),
          fehlt: 'fehlt — in der Übersicht bei den Stammdaten eintragen',
        ),
        _Zeile(label: 'Artikelbezeichnung', wert: t('bezeichnung')),
        _Zeile(label: 'Stückgewicht', wert: gewicht),
        _Zeile(
          label: 'Zutaten',
          wert: t('zutaten'),
          fehlt: 'fehlt — der Stand hat keine Zutaten',
        ),
        _Zeile(
          label: 'Fleischanteil',
          wert: t('fleischanteil'),
        ),
        _Zeile(label: 'Allergene', wert: t('allergene')),
        _Zeile(label: 'Spuren möglich', wert: vorschauSpuren(w)),
        _Zeile(label: 'Nährwerte je 100 g', wert: vorschauNaehrwerte(w)),
        _Zeile(label: 'Hilfsstoffe', wert: vorschauHilfsstoffe(w)),
        _Zeile(
          label: 'Sensorik',
          wert: vorschauSensorik(w),
          leer: 'bei „Sensorik" eintragen',
        ),
        if (produktfoto case final foto?)
          _Zeile(
            label: 'Produktfoto',
            wert: foto ? 'neben der Sensorik' : '',
            fehlt: 'fehlt — bei „Sensorik" hinterlegen',
          ),
        _Zeile(label: 'Lagerung', wert: t('lagerung'), fehlt: beiAngaben),
        _Zeile(
          label: 'Haltbarkeit',
          wert: t('haltbarkeit'),
          fehlt: beiAngaben,
        ),
      ],
    );
  }
}

/// Eine Zeile der Vorschau: Beschriftung links, Wert rechts.
class _Zeile extends StatelessWidget {
  const _Zeile({
    required this.label,
    required this.wert,
    this.fehlt,
    this.leer = '—',
  });

  final String label;
  final String wert;

  /// Was bei leerem [wert] in Warnfarbe dasteht — null: [leer] in Grau.
  final String? fehlt;
  final String leer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final f = fehlt;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: grau),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: wert.isNotEmpty
                ? SelectableText(wert, style: theme.textTheme.bodyMedium)
                : Text(
                    f ?? leer,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: f == null ? grau : AppFarben.von(context).warnung,
                      fontWeight: f == null ? null : FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
