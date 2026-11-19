import 'dart:async';

import 'package:erfassung_format/erfassung_format.dart';
import 'package:flutter/material.dart';

import 'bausteine.dart';
import 'erfassen_seite.dart';
import 'modell.dart';
import 'stand.dart';
import 'stil.dart';

/// Der Bereich „Heute": die Arbeitsliste an der Anlage.
///
/// Oben, was läuft — mit der Zeit seit dem Start und „Fertig". Darunter,
/// was bis heute offen ist — mit „Start", das die Uhrzeit des Handys als
/// Start festhält. Dann das Erfasste, und eingeklappt, was morgen und
/// später in der Woche geplant ist.
class HeuteAnsicht extends StatefulWidget {
  const HeuteAnsicht({
    super.key,
    required this.modell,
    required this.onOhnePlan,
    this.jetzt,
  });

  final ErfassungsModell modell;
  final VoidCallback onOhnePlan;

  /// Für Tests: die Uhrzeit, mit der die Seite rechnet.
  final DateTime Function()? jetzt;

  @override
  State<HeuteAnsicht> createState() => _HeuteAnsichtState();
}

class _HeuteAnsichtState extends State<HeuteAnsicht> {
  /// Hält „seit 06:10 · 3:06 h" aktuell.
  Timer? _uhr;

  /// Welche Abschnitte aufgeklappt sind — sonst gilt die Vorgabe.
  final _offen = <String, bool>{};

  ErfassungsModell get _modell => widget.modell;

  DateTime _jetzt() => (widget.jetzt ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _uhr = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _uhr?.cancel();
    super.dispose();
  }

  Future<void> _erfassen(HeuteEintrag e, {bool fertig = false}) {
    final paket = _modell.stand.paket;
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ErfassenSeite(
          modell: _modell,
          geplant: e.plan,
          artikel: e.plan == null ? paket?.artikelMit(e.artikelId) : null,
          vorhanden: e.erfasst,
          begonnen: e.plan == null ? e.entwurf : null,
          fertigMelden: fertig,
        ),
      ),
    );
  }

  Future<void> _starten(HeuteEintrag e) async {
    await _modell.produktionStarten(
      produktionId: e.id,
      artikelId: e.artikelId,
      artikel: e.artikel,
    );
    if (!mounted) return;
    // Wie lange es nach der Erfahrung dauert — oder warum sich das nicht
    // sagen lässt.
    final start = _modell.stand.entwuerfe[e.id]?.start;
    final p = _modell.stand.prognose(
      artikelId: e.artikelId,
      kg: e.rohKg,
      start: start,
    );
    await prognoseZeigen(
      context,
      titel: 'Gestartet um ${zeitAus(start) ?? uhrzeit(_jetzt())}',
      text: p.text,
      ermittelt: p.minuten != null,
      ende: p.ende,
    );
  }

  bool _aufgeklappt(String abschnitt, {required bool vorgabe}) =>
      _offen[abschnitt] ?? vorgabe;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _modell,
      builder: (context, _) {
        final theme = Theme.of(context);
        final f = theme.colorScheme;
        final farben = Farben.von(context);
        final jetzt = _jetzt();
        final u = _modell.stand.uebersicht(jetzt);

        Widget klappe(
          String schluessel,
          String titel,
          List<HeuteEintrag> liste, {
          required bool vorgabe,
          required Widget Function(HeuteEintrag) zeile,
        }) {
          if (liste.isEmpty) return const SizedBox.shrink();
          final auf = _aufgeklappt(schluessel, vorgabe: vorgabe);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                key: ValueKey('klappe-$schluessel'),
                borderRadius: Masse.eckenKlein,
                onTap: () => setState(() => _offen[schluessel] = !auf),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 18, 6, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${titel.toUpperCase()} · ${liste.length}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: f.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Icon(
                        auf ? Icons.expand_less : Icons.expand_more,
                        color: f.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
              if (auf)
                for (final e in liste)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: zeile(e),
                  ),
            ],
          );
        }

        Widget karte(HeuteEintrag e) => _ProduktionsKarte(
              eintrag: e,
              jetzt: jetzt,
              prognose: e.status == ProduktionsStatus.laeuft
                  ? _modell.stand.prognose(
                      artikelId: e.artikelId,
                      kg: e.rohKg,
                      start: e.start,
                    )
                  : null,
              onTap: () => _erfassen(e),
              onStart: () => _starten(e),
              onFertig: () => _erfassen(e, fertig: true),
            );

        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 32),
          children: [
            Row(
              children: [
                _Zaehler(
                  zahl: u.laeuft.length,
                  text: 'läuft',
                  farbe: u.laeuft.isEmpty ? null : farben.warnung,
                ),
                const SizedBox(width: 8),
                _Zaehler(zahl: u.offen.length, text: 'offen'),
                const SizedBox(width: 8),
                _Zaehler(
                  zahl: u.erfasst.length,
                  text: 'erfasst',
                  farbe: u.erfasst.isEmpty ? null : farben.ok,
                ),
              ],
            ),
            if (u.laeuft.isNotEmpty) ...[
              const Abschnitt('Läuft'),
              for (final e in u.laeuft)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: karte(e),
                ),
            ],
            if (u.offen.isNotEmpty) ...[
              const Abschnitt('Offen'),
              for (final e in u.offen)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: karte(e),
                ),
            ],
            if (u.laeuft.isEmpty && u.offen.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: Flaeche(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 40,
                          color: farben.ok,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Für heute ist nichts mehr offen.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            klappe(
              'erfasst',
              'Erfasst',
              u.erfasst,
              vorgabe: u.erfasst.length <= 3,
              zeile: (e) => TippZeile(
                key: ValueKey('erfasst-${e.id}'),
                titel: e.artikel,
                unter: [
                  tagKurz(e.datum),
                  if (e.rohKg case final kg?) '${zahlText(kg)} kg Rohware',
                  if (e.erfasst?.fertigKg case final kg?)
                    '${zahlText(kg)} kg Fertigware',
                ].join(' · '),
                rechts: Icon(Icons.check_circle, color: farben.ok),
                onTap: () => _erfassen(e),
              ),
            ),
            klappe('morgen', 'Morgen', u.morgen, vorgabe: false, zeile: karte),
            klappe(
              'spaeter',
              'Später in der Woche',
              u.spaeter,
              vorgabe: false,
              zeile: karte,
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              key: const ValueKey('ohne-plan'),
              onPressed: widget.onOhnePlan,
              icon: const Icon(Icons.add),
              label: const Text('Ohne Plan erfassen'),
            ),
          ],
        );
      },
    );
  }
}

/// Eine Zahl mit Wort in einer kleinen Kachel: „2 läuft".
class _Zaehler extends StatelessWidget {
  const _Zaehler({required this.zahl, required this.text, this.farbe});

  final int zahl;
  final String text;
  final Color? farbe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = theme.colorScheme;
    return Expanded(
      child: Flaeche(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$zahl',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: farbe ?? f.onSurface,
                ),
              ),
              Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: f.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Eine Produktion als Karte: die Menge groß, der Artikel darunter, unten
/// die Abteilung oder die Zeit seit dem Start und der eine Knopf, der
/// jetzt dran ist.
class _ProduktionsKarte extends StatelessWidget {
  const _ProduktionsKarte({
    required this.eintrag,
    required this.jetzt,
    required this.onTap,
    required this.onStart,
    required this.onFertig,
    this.prognose,
  });

  final HeuteEintrag eintrag;

  /// Bei einer laufenden: wann sie nach der Erfahrung fertig ist.
  final Prognose? prognose;
  final DateTime jetzt;
  final VoidCallback onTap;
  final VoidCallback onStart;
  final VoidCallback onFertig;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = theme.colorScheme;
    final farben = Farben.von(context);
    final e = eintrag;
    final laeuft = e.status == ProduktionsStatus.laeuft;
    final plan = e.plan;
    final heute = DateTime(jetzt.year, jetzt.month, jetzt.day);
    final tag = DateTime(e.datum.year, e.datum.month, e.datum.day);

    final Widget links;
    if (laeuft) {
      final start = e.start!;
      final seit = dauerMinuten(start, uhrzeit(jetzt)) ?? 0;
      final bis = prognose?.ende;
      final seitZeile = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: farben.warnung,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: farben.warnung.withValues(alpha: 0.35),
                  spreadRadius: 4,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'seit $start · ${dauerText(seit)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: farben.warnung,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      );
      links = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          seitZeile,
          Padding(
            padding: const EdgeInsets.only(left: 20, top: 3),
            child: Text(
              bis == null
                  ? 'Dauer unbekannt'
                  : 'fertig gegen $bis · '
                      '${dauerText(prognose!.minuten!)}',
              key: ValueKey('prognose-${e.id}'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: f.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    } else {
      final zusatz = [
        if (tag != heute) tagLang(tag, jetzt).split(',').first,
        if (plan?.start case final s?) 'ab $s',
      ].join(' · ');
      links = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (plan != null && plan.abteilungName.isNotEmpty)
            AbteilungsMarke(
              name: plan.abteilungName,
              farbe: plan.abteilungFarbe,
            )
          else if (plan == null)
            Text(
              'ohne Plan',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: f.onSurfaceVariant,
              ),
            ),
          if (zusatz.isNotEmpty)
            Text(
              zusatz,
              style: theme.textTheme.bodySmall?.copyWith(
                color: f.onSurfaceVariant,
              ),
            ),
        ],
      );
    }

    return Flaeche(
      key: ValueKey('karte-${e.id}'),
      farbe: laeuft ? farben.warnung.withValues(alpha: 0.7) : null,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  e.rohKg == null ? '–' : zahlText(e.rohKg!),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'kg Rohware',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: f.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (e.begonnen) Marke('begonnen', farbe: f.primary),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              e.artikel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(height: 1.3),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: links),
                const SizedBox(width: 10),
                if (laeuft)
                  FilledButton(
                    key: ValueKey('fertig-${e.id}'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(104, 48),
                      backgroundColor: farben.warnung,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: onFertig,
                    child: const Text('Fertig'),
                  )
                else
                  FilledButton.icon(
                    key: ValueKey('start-${e.id}'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(104, 48),
                    ),
                    onPressed: onStart,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Start'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
