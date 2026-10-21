import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_stil.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/fehler_text.dart';
import '../../../core/utils/format.dart';
import '../daten/entwicklung_repository.dart';
import '../entwicklung_screen.dart'
    show EntwicklungsReiter, entwicklungReiterProvider;
import '../projekte/projekt_modell.dart';
import '../projekte/projekt_repository.dart';
import '../projekte/projekte_ansicht.dart' show oeffneProjekt;
import 'entwicklung_statistik.dart';

/// Öffnet die Rückrechnung.
Future<void> oeffneRueckrechnung(BuildContext context) =>
    context.pushNamed<void>('entwicklungRueckrechnung');

/// Der Reiter „Werkzeuge": Rückrechnung, Fleischanteil und die Zahlen der
/// Entwicklung.
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
                      'In jeder Rezeptur über „Fleischanteil einstellen…" '
                      'in der Leiste der Stände: Fleisch wird gemeinsam '
                      'größer oder kleiner, Wasser oder Eis gleicht aus — '
                      'bis der Anteil laut Etikett oder im Rohgemisch '
                      'stimmt.',
                      style: klein,
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () {
                        ref.read(entwicklungReiterProvider.notifier).state =
                            EntwicklungsReiter.rezepturen;
                        DefaultTabController.maybeOf(context)
                            ?.animateTo(EntwicklungsReiter.rezepturen.index);
                      },
                      icon: const Icon(Icons.menu_book_outlined, size: 18),
                      label: const Text('Zu den Rezepturen'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const EntwicklungsStatistikAnsicht(),
      ],
    );
  }
}

/// Die Produktentwicklung in Zahlen.
class EntwicklungsStatistikAnsicht extends ConsumerWidget {
  const EntwicklungsStatistikAnsicht({super.key, this.jetzt});

  /// Für Tests: der Stichtag — sonst heute.
  final DateTime? jetzt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projekte = ref.watch(projekteProvider);
    final rezepturen = ref.watch(rezepturenProvider);
    final versionen = ref.watch(alleVersionenProvider);
    final zutaten = ref.watch(zutatenProvider);
    final eintraege = ref.watch(alleEintraegeProvider);
    final alle = <AsyncValue<Object?>>[
      projekte,
      rezepturen,
      versionen,
      zutaten,
      eintraege,
    ];
    Widget inhalt;
    final fehler = alle.where((a) => a.hasError).firstOrNull;
    if (fehler != null) {
      inhalt = HinweisBox(
        fehlerText(fehler.error),
        art: StatusArt.fehler,
        titel: 'Die Zahlen ließen sich nicht laden',
        auswaehlbar: true,
      );
    } else if (alle.any((a) => !a.hasValue)) {
      inhalt = const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    } else {
      final heute = jetzt ?? DateTime.now();
      inhalt = _Zahlen(
        statistik: entwicklungsStatistik(
          projekte: projekte.requireValue,
          rezepturen: rezepturen.requireValue,
          versionen: versionen.requireValue,
          zutaten: zutaten.requireValue,
          eintraege: eintraege.requireValue,
          jetzt: heute,
        ),
        jetzt: heute,
      );
    }
    return Bereich(
      titel: 'Entwicklung in Zahlen',
      icon: Icons.query_stats,
      child: inhalt,
    );
  }
}

class _Zahlen extends StatelessWidget {
  const _Zahlen({required this.statistik, required this.jetzt});

  final EntwicklungsStatistik statistik;
  final DateTime jetzt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final farben = AppFarben.von(context);
    final s = statistik;
    final ruhend = s.ruhend(jetzt);
    final tage = s.tageBisFreigabe;
    final staende = s.staendeBisFreigabe;

    Widget ueberschrift(String text) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 6),
          child: Text(
            text,
            style: theme.textTheme.labelMedium?.copyWith(
              color: grau,
              fontWeight: FontWeight.w700,
            ),
          ),
        );

    Widget namen(List<String> liste) => Text(
          liste.length <= 8
              ? liste.join(', ')
              : '${liste.take(8).join(', ')} und ${liste.length - 8} weitere',
          style: theme.textTheme.bodySmall?.copyWith(color: grau),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 32,
          runSpacing: 12,
          children: [
            Kennzahl(wert: '${s.projekte}', label: 'Projekte'),
            for (final st in ProjektStatus.values)
              Kennzahl(
                wert: '${s.projekteJeStatus[st] ?? 0}',
                label: st.label,
              ),
            Kennzahl(
              wert: tage == null ? '—' : Format.zahl(tage),
              label: 'Ø Tage bis zur Freigabe',
            ),
            Kennzahl(
              wert: staende == null ? '—' : Format.zahl(staende, nachkomma: 1),
              label: 'Ø Stände bis zur Freigabe',
            ),
            Kennzahl(wert: '${s.rezepturen}', label: 'Rezepturen'),
            Kennzahl(
              wert: '${s.abgeschlosseneStaende} von ${s.staende}',
              label: 'Stände abgeschlossen',
            ),
            Kennzahl(wert: '${s.zutaten}', label: 'Zutaten im Katalog'),
          ],
        ),
        ueberschrift('VERLAUF DER LETZTEN ZWÖLF MONATE'),
        _MonatsBalken(verlauf: s.verlauf),
        ueberschrift('AKTIVE PROJEKTE'),
        if (s.aktive.isEmpty)
          Text(
            'Kein Projekt in Entwicklung oder Validierung.',
            style: theme.textTheme.bodySmall?.copyWith(color: grau),
          ),
        for (final p in s.aktive.take(12))
          _ProjektZeile(
            fortschritt: p,
            ruhend: ruhend.contains(p),
            jetzt: jetzt,
          ),
        if (s.aktive.length > 12)
          Text(
            'und ${s.aktive.length - 12} weitere',
            style: theme.textTheme.bodySmall?.copyWith(color: grau),
          ),
        if (ruhend.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: HinweisBox(
              '${ruhend.length == 1 ? 'Ein aktives Projekt ruht' : '${ruhend.length} aktive Projekte ruhen'} '
              'seit mindestens $kRuhendNachTagen Tagen: '
              '${ruhend.map((p) => p.projekt.name).join(', ')}.',
              art: StatusArt.warnung,
            ),
          ),
        ueberschrift('LÜCKEN IM ZUTATEN-KATALOG'),
        if (s.zutatenOhneNaehrwerte.isEmpty && s.zutatenOhneAllergene.isEmpty)
          Row(
            children: [
              Icon(Icons.check_circle_outline, size: 18, color: farben.ok),
              const SizedBox(width: 6),
              const Text('Alle Zutaten haben Nährwerte und Allergene.'),
            ],
          ),
        if (s.zutatenOhneNaehrwerte.isNotEmpty) ...[
          Text(
            '${s.zutatenOhneNaehrwerte.length} ohne Nährwerte — sie zählen in '
            'jeder Rezeptur als 0:',
          ),
          namen(s.zutatenOhneNaehrwerte),
          const SizedBox(height: 6),
        ],
        if (s.zutatenOhneAllergene.isNotEmpty) ...[
          Text(
            '${s.zutatenOhneAllergene.length} ohne Angabe zu Allergenen — '
            'ein Artikel aus ihnen bekommt kein „keine":',
          ),
          namen(s.zutatenOhneAllergene),
        ],
        if (s.rezepturenOhneProjekt > 0) ...[
          const SizedBox(height: 6),
          Text(
            '${s.rezepturenOhneProjekt} '
            '${s.rezepturenOhneProjekt == 1 ? 'Rezeptur steht' : 'Rezepturen stehen'} '
            'ohne Projekt in der Liste.',
            style: theme.textTheme.bodySmall?.copyWith(color: grau),
          ),
        ],
      ],
    );
  }
}

class _ProjektZeile extends StatelessWidget {
  const _ProjektZeile({
    required this.fortschritt,
    required this.ruhend,
    required this.jetzt,
  });

  final ProjektFortschritt fortschritt;
  final bool ruhend;
  final DateTime jetzt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final farben = AppFarben.von(context);
    final p = fortschritt;
    final tage = jetzt.difference(p.letzteAktivitaet).inDays;
    return InkWell(
      onTap: () => oeffneProjekt(context, p.projekt.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Text(
                p.projekt.name,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                ProjektStatus.aus(p.projekt.status).label,
                style: theme.textTheme.bodySmall?.copyWith(color: grau),
              ),
            ),
            SizedBox(
              width: 140,
              child: Tooltip(
                message: 'Checkliste: ${p.erledigt} von ${p.punkte} erledigt',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: p.anteil,
                    minHeight: 6,
                    color: farben.ok,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 70,
              child: Text(
                '${p.erledigt}/${p.punkte}',
                textAlign: TextAlign.right,
                style: theme.textTheme.bodySmall?.copyWith(color: grau),
              ),
            ),
            SizedBox(
              width: 80,
              child: Text(
                p.staende == 1 ? '1 Stand' : '${p.staende} Stände',
                textAlign: TextAlign.right,
                style: theme.textTheme.bodySmall?.copyWith(color: grau),
              ),
            ),
            SizedBox(
              width: 120,
              child: Text(
                tage <= 0
                    ? 'heute'
                    : tage == 1
                        ? 'gestern'
                        : 'vor $tage Tagen',
                textAlign: TextAlign.right,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ruhend ? farben.warnung : grau,
                  fontWeight: ruhend ? FontWeight.w700 : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Einträge im Verlauf je Monat als schmale Balken; Freigaben als Punkt
/// darüber.
class _MonatsBalken extends StatelessWidget {
  const _MonatsBalken({required this.verlauf});

  final List<MonatsAktivitaet> verlauf;

  static const List<String> _monate = [
    'Jan',
    'Feb',
    'Mär',
    'Apr',
    'Mai',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Okt',
    'Nov',
    'Dez',
  ];

  static String _text(MonatsAktivitaet v) {
    final teile = [
      '${v.eintraege} ${v.eintraege == 1 ? 'Eintrag' : 'Einträge'}',
      if (v.freigaben > 0)
        '${v.freigaben} ${v.freigaben == 1 ? 'Freigabe' : 'Freigaben'}',
    ];
    return '${_monate[v.monat.month - 1]} ${v.monat.year}: '
        '${teile.join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final farben = AppFarben.von(context);
    final hoechster = verlauf.fold<int>(
      0,
      (m, v) => v.eintraege > m ? v.eintraege : m,
    );
    const hoehe = 72.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: hoehe + 34,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final v in verlauf)
                Expanded(
                  child: Tooltip(
                    message: _text(v),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (v.freigaben > 0)
                          Icon(Icons.verified, size: 14, color: farben.ok),
                        Text(
                          v.eintraege == 0 ? '' : '${v.eintraege}',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: grau),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          width: 18,
                          height: hoechster == 0
                              ? 0
                              : hoehe * v.eintraege / hoechster,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
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
        Container(height: 1, color: theme.colorScheme.outline),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final v in verlauf)
              Expanded(
                child: Text(
                  _monate[v.monat.month - 1],
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(color: grau),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Einträge im Verlauf aller Projekte je Monat; ein Haken über dem '
          'Balken zeigt Freigaben als Artikel.',
          style: theme.textTheme.bodySmall?.copyWith(color: grau),
        ),
      ],
    );
  }
}
