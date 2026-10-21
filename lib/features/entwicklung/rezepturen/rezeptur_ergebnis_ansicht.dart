import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/artikel_merkmale.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/fehler_text.dart';
import '../../../core/utils/format.dart';
import '../daten/entwicklung_repository.dart';
import '../entwicklung_format.dart';
import '../rechenkern/naehrwert_rundung.dart';
import '../rechenkern/rechen_modell.dart';
import '../rechenkern/rechenkern.dart';

/// Das Ergebnis eines Rezepturstands — rechnet bei jeder Änderung neu.
class RezepturErgebnisAnsicht extends ConsumerWidget {
  const RezepturErgebnisAnsicht({super.key, required this.versionId});

  final String versionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ergebnis = ref.watch(rezepturErgebnisProvider(versionId));
    return ergebnis.when(
      // Beim Neurechnen bleibt das alte Ergebnis stehen, statt zu flackern.
      skipLoadingOnReload: true,
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => HinweisBox(
        fehlerText(e),
        art: StatusArt.fehler,
        titel: 'Die Rezeptur ließ sich nicht berechnen',
        auswaehlbar: true,
      ),
      data: (e) => e == null
          ? const LeerHinweis('Diesen Stand gibt es nicht mehr.')
          : ErgebnisInhalt(ergebnis: e),
    );
  }
}

/// Zeigt ein Ergebnis des Rechenkerns: Kennzahlen, Hinweise,
/// Zutatenliste, Mengen, Fleischanteil, Nährwerte und Allergene.
class ErgebnisInhalt extends StatelessWidget {
  const ErgebnisInhalt({super.key, required this.ergebnis});

  final RezepturErgebnis ergebnis;

  @override
  Widget build(BuildContext context) {
    final e = ergebnis;
    final verlust = e.eingesetztKg > 0
        ? (1 - e.endgewichtKg / e.eingesetztKg) * 100
        : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 24,
          runSpacing: 8,
          children: [
            Kennzahl(wert: '${mengeText(e.eingesetztKg)} kg', label: 'eingesetzt'),
            Kennzahl(wert: '${mengeText(e.endgewichtKg)} kg', label: 'Endgewicht'),
            if (verlust > 0)
              Kennzahl(wert: prozentText(verlust), label: 'Verlust'),
            Kennzahl(
              wert: prozentText(e.fleischanteilProzent),
              label: 'Fleischanteil',
            ),
            if (e.je100g.beffe case final beffe?)
              Kennzahl(wert: prozentText(beffe), label: 'BEFFE'),
          ],
        ),
        const SizedBox(height: 12),
        for (final w in e.warnungen) ...[
          HinweisBox(w, art: StatusArt.warnung),
          const SizedBox(height: 6),
        ],
        if (e.ohneNaehrwerte.isNotEmpty) ...[
          HinweisBox(
            'Ohne Nährwerte: ${e.ohneNaehrwerte.join(', ')} — die Tabelle '
            'ist dann zu niedrig.',
          ),
          const SizedBox(height: 6),
        ],
        if (e.ohneBeffe.isNotEmpty) ...[
          HinweisBox(
            'Ohne BEFFE-Wert: ${e.ohneBeffe.join(', ')} — das BEFFE ist dann '
            'zu niedrig.',
          ),
          const SizedBox(height: 6),
        ],
        const SizedBox(height: 6),
        _Zutatenliste(text: e.zutatenliste),
        const SizedBox(height: 12),
        _Mengen(ergebnis: e),
        if (e.tierarten.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Fleisch(tierarten: e.tierarten),
        ],
        const SizedBox(height: 12),
        NaehrwertTabelle(werte: e.je100g),
        const SizedBox(height: 12),
        _Allergene(ergebnis: e),
      ],
    );
  }
}

class _Zutatenliste extends StatelessWidget {
  const _Zutatenliste({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Bereich(
      titel: 'Zutatenliste',
      aktionen: [
        IconButton(
          tooltip: 'Kopieren',
          icon: const Icon(Icons.content_copy, size: 18),
          onPressed: text.isEmpty
              ? null
              : () async {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Zutatenliste kopiert.')),
                  );
                },
        ),
      ],
      child: text.isEmpty
          ? const LeerHinweis('Noch keine Zutaten mit Menge.')
          : SelectableText(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
    );
  }
}

class _Mengen extends StatelessWidget {
  const _Mengen({required this.ergebnis});

  final RezepturErgebnis ergebnis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final stil = theme.textTheme.bodyMedium;
    final zahlen = stil?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Bereich(
      titel: 'Anteile im Enderzeugnis',
      innenAbstand: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final z in ergebnis.zeilen)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      z.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: stil?.copyWith(
                        color: z.ausgelassen ? grau : null,
                        fontWeight: z.istFleisch ? FontWeight.w600 : null,
                      ),
                    ),
                  ),
                  if (z.ausgelassen)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: StatusMarke('nicht in der Liste'),
                    )
                  else if (z.quid)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: StatusMarke('QUID', art: StatusArt.info),
                    ),
                  SizedBox(
                    width: 84,
                    child: Text(
                      '${mengeText(z.masseKg)} kg',
                      textAlign: TextAlign.right,
                      style: zahlen?.copyWith(color: grau),
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    child: Text(
                      prozentText(z.anteilProzent),
                      textAlign: TextAlign.right,
                      style: zahlen,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Fleisch extends StatelessWidget {
  const _Fleisch({required this.tierarten});

  final List<TierartPruefung> tierarten;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    return Bereich(
      titel: 'Fleischanteil je Tierart',
      untertitel: 'LMIV Anhang VII Teil B',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final p in tierarten)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Wrap(
                spacing: 16,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      p.tierart.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${mengeText(p.masseKg)} kg · Fett '
                    '${prozentText(p.fettProzent)} · Eiweiß '
                    '${prozentText(p.eiweissProzent)}'
                    '${p.kollagenVerhaeltnis == null ? '' : ' · Kollagen/FE ${prozentText(p.kollagenVerhaeltnis!)}'}',
                    style: theme.textTheme.bodySmall?.copyWith(color: grau),
                  ),
                  if (p.fettUeberGrenze)
                    StatusMarke(
                      'Fett über ${Format.zahl(p.tierart.fettGrenze)} %',
                      art: StatusArt.warnung,
                    ),
                  if (p.bindegewebeUeberGrenze)
                    StatusMarke(
                      'Bindegewebe über '
                      '${Format.zahl(p.tierart.bindegewebeGrenze)} %',
                      art: StatusArt.warnung,
                    ),
                  if (!p.fettUeberGrenze && !p.bindegewebeUeberGrenze)
                    const StatusMarke('in den Grenzen', art: StatusArt.ok),
                  Text(
                    'Fleisch ${mengeText(p.fleischKg)} kg',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Die Nährwerttabelle je 100 g — gerundet wie auf dem Etikett, der
/// genaue Wert klein daneben.
class NaehrwertTabelle extends StatelessWidget {
  const NaehrwertTabelle({super.key, required this.werte});

  final Naehrwerte werte;

  static double? wert(Naehrwerte n, Naehrstoff s) => switch (s) {
        Naehrstoff.energieKj => n.energieKj,
        Naehrstoff.energieKcal => n.energieKcal,
        Naehrstoff.fett => n.fett,
        Naehrstoff.gesaettigteFettsaeuren => n.gesaettigteFettsaeuren,
        Naehrstoff.kohlenhydrate => n.kohlenhydrate,
        Naehrstoff.zucker => n.zucker,
        Naehrstoff.eiweiss => n.eiweiss,
        Naehrstoff.salz => n.salz,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final zahlen = theme.textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Bereich(
      titel: 'Nährwerte je 100 g',
      untertitel: 'gerundet nach EU-Leitfaden',
      innenAbstand: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final s in Naehrstoff.values)
            Container(
              padding: EdgeInsets.fromLTRB(
                s.label.startsWith('davon') ? 28 : 12,
                5,
                12,
                5,
              ),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      s.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: s.label.startsWith('davon') ? grau : null,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 70,
                    child: Text(
                      wert(werte, s) == null
                          ? ''
                          : Format.zahl(wert(werte, s)!, nachkomma: 2),
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodySmall?.copyWith(color: grau),
                    ),
                  ),
                  SizedBox(
                    width: 96,
                    child: Text(
                      '${naehrwertGerundet(s, wert(werte, s))} ${s.einheit}',
                      textAlign: TextAlign.right,
                      style: zahlen?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Allergene extends StatelessWidget {
  const _Allergene({required this.ergebnis});

  final RezepturErgebnis ergebnis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final allergene = ergebnis.allergene;
    final hilfsstoffe = ergebnis.verarbeitungshilfsstoffe;
    return Bereich(
      titel: 'Allergene und Hilfsstoffe',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (allergene.isEmpty)
            Text(
              'Keine Allergene aus den Zutaten.',
              style: theme.textTheme.bodyMedium?.copyWith(color: grau),
            ),
          for (final MapEntry(:key, :value) in allergene.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 130,
                    child: StatusMarke(
                      merkmalLabel(key, kAllergene) ?? key,
                      art: StatusArt.warnung,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'aus ${value.join(', ')}',
                      style: theme.textTheme.bodySmall?.copyWith(color: grau),
                    ),
                  ),
                ],
              ),
            ),
          if (hilfsstoffe.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Verarbeitungshilfsstoffe',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            for (final MapEntry(:key, :value) in hilfsstoffe.entries)
              Text(
                '$key — aus ${value.join(', ')}',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ],
      ),
    );
  }
}
