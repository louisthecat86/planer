import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/theme/app_stil.dart';
import '../../core/ui/bausteine.dart';
import '../../core/utils/format.dart';
import '../../core/utils/zeit.dart';
import '../board/board_providers.dart' show CapacityStatus;
import 'statistik_daten.dart';
import 'statistik_diagramme.dart';

/// Statistik: was sich aus der Planung und den erfassten Produktionen
/// lernen lässt — wo es eng wird, wohin die Zeit geht, wie die Ausbeute
/// schwankt und was die Produktion trägt.
///
/// Oben wählt man den Zeitraum und optional eine Abteilung; jeder Teil ist
/// ein eigener Bereich. Fehlen Daten, sagt der Bereich, was zu erfassen
/// wäre.
class StatistikScreen extends ConsumerStatefulWidget {
  const StatistikScreen({super.key});

  @override
  ConsumerState<StatistikScreen> createState() => _StatistikScreenState();
}

class _StatistikScreenState extends ConsumerState<StatistikScreen> {
  StatistikZeitraum _zeitraum = StatistikZeitraum.quartal;
  Abteilung? _abteilung;

  /// Die zuletzt geladenen Daten. Beim Wechsel des Zeitraums bleiben sie
  /// blass stehen, bis die neuen da sind — statt dass die Seite springt.
  StatistikDaten? _zuletzt;

  void _waehleAbteilung(Abteilung? abteilung) =>
      setState(() => _abteilung = abteilung);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(statistikProvider(_zeitraum));
    final neu = async.valueOrNull;
    if (neu != null) _zuletzt = neu;
    final daten = neu ?? (async.isLoading ? _zuletzt : null);
    final fehler = async.hasError && !async.isLoading ? async.error : null;

    final Widget inhalt;
    if (daten != null) {
      inhalt = Opacity(
        opacity: neu == null ? 0.45 : 1,
        child: _Inhalt(
          daten: daten,
          abteilung: _abteilung,
          onAbteilung: _waehleAbteilung,
        ),
      );
    } else if (fehler != null) {
      inhalt = ListView(
        padding: const EdgeInsets.all(14),
        children: [
          HinweisBox(
            '$fehler',
            art: StatusArt.fehler,
            titel: 'Statistik konnte nicht geladen werden',
            auswaehlbar: true,
            aktion: TextButton(
              onPressed: () => ref.invalidate(statistikProvider(_zeitraum)),
              child: const Text('Erneut versuchen'),
            ),
          ),
        ],
      );
    } else {
      inhalt = const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistik'),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(statistikProvider(_zeitraum)),
            icon: const Icon(Icons.refresh),
            tooltip: 'Neu laden',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Filterleiste(
            zeitraum: _zeitraum,
            abteilung: _abteilung,
            spanne: daten?.spanne,
            onZeitraum: (z) => setState(() => _zeitraum = z),
            onAbteilung: _waehleAbteilung,
          ),
          SizedBox(
            height: 2,
            child: async.isLoading && daten != null
                ? const LinearProgressIndicator(minHeight: 2)
                : null,
          ),
          Expanded(child: inhalt),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter
// ---------------------------------------------------------------------------

class _Filterleiste extends StatelessWidget {
  const _Filterleiste({
    required this.zeitraum,
    required this.abteilung,
    required this.spanne,
    required this.onZeitraum,
    required this.onAbteilung,
  });

  final StatistikZeitraum zeitraum;
  final Abteilung? abteilung;
  final StatistikSpanne? spanne;
  final ValueChanged<StatistikZeitraum> onZeitraum;
  final ValueChanged<Abteilung?> onAbteilung;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final zeit = spanne;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<StatistikZeitraum>(
            segments: [
              for (final z in StatistikZeitraum.values)
                ButtonSegment(value: z, label: Text(z.label)),
            ],
            selected: {zeitraum},
            showSelectedIcon: false,
            onSelectionChanged: (auswahl) => onZeitraum(auswahl.first),
          ),
          SizedBox(
            width: 230,
            child: DropdownButtonFormField<String>(
              // Neu aufbauen, wenn die Abteilung von außen wechselt (Zeile
              // in der Auslastung angetippt) — sonst zeigte das Feld den
              // alten Wert.
              key: ValueKey(abteilung),
              initialValue: abteilung?.dbValue ?? '',
              isExpanded: true,
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'Abteilung',
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text(
                    'Alle Abteilungen',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                for (final a in Abteilung.values)
                  DropdownMenuItem(
                    value: a.dbValue,
                    child: Text(
                      a.anzeigeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (wert) => onAbteilung(
                wert == null || wert.isEmpty
                    ? null
                    : Abteilung.fromDbValue(wert),
              ),
            ),
          ),
          if (zeit != null)
            Text(
              '${zeit.beschreibung} · ${zeit.wochen} '
              '${zeit.wochen == 1 ? 'Woche' : 'Wochen'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Inhalt
// ---------------------------------------------------------------------------

class _Inhalt extends StatelessWidget {
  const _Inhalt({
    required this.daten,
    required this.abteilung,
    required this.onAbteilung,
  });

  final StatistikDaten daten;
  final Abteilung? abteilung;
  final ValueChanged<Abteilung?> onAbteilung;

  @override
  Widget build(BuildContext context) {
    final spanne = daten.spanne;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
      children: [
        _AuslastungBereich(
          auswertung: werteAuslastungAus(
            daten.belegung,
            spanne,
            abteilung: abteilung,
          ),
          spanne: spanne,
          abteilung: abteilung,
          onAbteilung: onAbteilung,
        ),
        const SizedBox(height: 12),
        _ZeitBereich(
          auswertung: werteZeitAus(daten.belegung, abteilung: abteilung),
        ),
        const SizedBox(height: 12),
        _AusbeuteBereich(
          auswertung: werteAusbeuteAus(
            daten.produktionen,
            daten.artikel,
            spanne,
            abteilung: abteilung,
          ),
          spanne: spanne,
          abteilung: abteilung,
        ),
        const SizedBox(height: 12),
        _MixBereich(
          auswertung: werteProduktmixAus(
            daten.produktionen,
            daten.artikel,
            spanne,
            abteilung: abteilung,
          ),
          abteilung: abteilung,
        ),
      ],
    );
  }
}

/// Kleine Überschrift innerhalb eines Bereichs.
class _Zwischentitel extends StatelessWidget {
  const _Zwischentitel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Grauer Erklärtext unter einem Diagramm.
class _Fussnote extends StatelessWidget {
  const _Fussnote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.35,
      ),
    );
  }
}

/// Ampelfarbe wie im Board.
Color _ampel(BuildContext context, CapacityStatus status) {
  final f = AppFarben.von(context);
  return switch (status) {
    CapacityStatus.frei => restFarbe,
    CapacityStatus.gut => f.ok,
    CapacityStatus.ueberbucht => f.fehler,
  };
}

String _tage(int n) => n == 1 ? '1 Tag' : '$n Tage';

/// Die feste Folge der Zeitarten — Farbe gehört zur Art, nicht zum Rang.
const List<(String, String)> _zeitArten = [
  ('produktion', 'Produktion'),
  ('ruesten', 'Rüsten'),
  ('reinigen', 'Reinigen'),
  ('sonstiges', 'Sonstiges'),
];

double _zeitWert(ZeitAnteile a, String art) => switch (art) {
      'produktion' => a.produktion,
      'ruesten' => a.ruesten,
      'reinigen' => a.reinigen,
      _ => a.sonstiges,
    };

// ---------------------------------------------------------------------------
// Teil 1: Auslastung und Engpässe
// ---------------------------------------------------------------------------

class _AuslastungBereich extends StatelessWidget {
  const _AuslastungBereich({
    required this.auswertung,
    required this.spanne,
    required this.abteilung,
    required this.onAbteilung,
  });

  final AuslastungsAuswertung auswertung;
  final StatistikSpanne spanne;
  final Abteilung? abteilung;
  final ValueChanged<Abteilung?> onAbteilung;

  @override
  Widget build(BuildContext context) {
    final f = AppFarben.von(context);
    final a = auswertung;
    final gewaehlt = abteilung;

    if (a.leer) {
      return const Bereich(
        titel: 'Auslastung und Engpässe',
        untertitel: 'Planung',
        child: LeerHinweis(
          'Im Zeitraum ist nichts geplant.',
          icon: Icons.event_busy_outlined,
        ),
      );
    }

    final engpass = a.engpass;
    final wochen = a.geplanteWochen;
    // Gemeinsamer Maßstab aller Zeilen — mindestens bis 120 %, damit die
    // 100-%-Marke nicht am Rand klebt.
    final skala = a.zeilen.fold(1.2, (m, z) => math.max(m, z.auslastung));

    return Bereich(
      titel: 'Auslastung und Engpässe',
      untertitel: 'Planung · Kapazität von heute',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 32,
            runSpacing: 10,
            children: [
              Kennzahl(
                wert: Format.prozent(a.auslastung, nachkomma: 0),
                label: 'Ø Auslastung',
                gross: true,
              ),
              Kennzahl(
                wert: '${a.ueberbuchteTage}',
                label: 'überbuchte Tage von ${a.planungstage}',
                farbe: a.ueberbuchteTage > 0 ? f.fehler : null,
                gross: true,
              ),
              if (engpass != null)
                Kennzahl(
                  wert: engpass.name,
                  label: 'Engpass · Ø '
                      '${Format.prozent(engpass.auslastung, nachkomma: 0)}',
                  gross: true,
                ),
              Kennzahl(
                wert: '$wochen',
                label: wochen == 1 ? 'geplante Woche' : 'geplante Wochen',
                gross: true,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Zwischentitel(
            gewaehlt == null
                ? 'Je Abteilung · Ø pro Woche'
                : '${gewaehlt.anzeigeName} je Anlage · Ø pro Woche',
          ),
          for (var i = 0; i < a.zeilen.length; i++)
            _AuslastungsZeile(
              zeile: a.zeilen[i],
              wochen: wochen,
              planungstage: a.planungstage,
              skala: skala,
              letzte: i == a.zeilen.length - 1,
              // Ohne Filter führt eine Abteilung zu ihren Anlagen.
              onTap: gewaehlt == null
                  ? () => onAbteilung(a.zeilen[i].abteilung)
                  : null,
            ),
          const SizedBox(height: 8),
          FarbLegende(
            eintraege: [
              (restFarbe, 'unter 75 %'),
              (f.ok, 'gut gefüllt'),
              (f.fehler, 'überbucht'),
            ],
            linie: '100 %',
          ),
          if (a.verlauf.isNotEmpty) ...[
            const SizedBox(height: 18),
            _Zwischentitel(
              'Ø Auslastung ${spanne.rasterText} · '
              '${gewaehlt?.anzeigeName ?? 'alle Abteilungen zusammen'}',
            ),
            StatistikSaeulen(
              saeulen: [
                for (final p in a.verlauf)
                  Saeule(
                    label: spanne.kurzname(p.abschnitt),
                    wert: p.hatDaten ? p.auslastung * 100 : null,
                    farbe: _ampel(context, p.status),
                    hinweis: '${spanne.langname(p.abschnitt)}\n'
                        'Ø Auslastung '
                        '${Format.prozent(p.auslastung, nachkomma: 0)}\n'
                        '${Zeit.kurz(p.belegtMinuten)} von '
                        '${Zeit.kurz(p.kapazitaetMinuten)}\n'
                        '${p.ueberbuchteTage} von ${p.tage} '
                        '${p.tage == 1 ? 'Tag' : 'Tagen'} überbucht',
                  ),
              ],
              achsenText: (wert) => '${Format.zahl(wert)} %',
              linie: 100,
              linienFarbe: f.fehler,
            ),
          ],
          const SizedBox(height: 10),
          const _Fussnote(
            'Gezählt werden Werktage, an denen im Board etwas geplant war — '
            'Feiertage und Wochen ohne Planung bleiben außen vor. Frühere '
            'Wochen rechnet die Statistik mit der heutigen Kapazität. Wo '
            'es regelmäßig über 100 % geht, fehlt Kapazität oder eine '
            'Schicht.',
          ),
        ],
      ),
    );
  }
}

class _AuslastungsZeile extends StatelessWidget {
  const _AuslastungsZeile({
    required this.zeile,
    required this.wochen,
    required this.planungstage,
    required this.skala,
    required this.letzte,
    this.onTap,
  });

  final AuslastungsZeile zeile;
  final int wochen;
  final int planungstage;
  final double skala;
  final bool letzte;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final f = AppFarben.von(context);
    final farbe = _ampel(context, zeile.status);
    final jeWoche = wochen > 0 ? zeile.belegtMinuten / wochen : 0.0;
    final kapazitaet = wochen > 0 ? zeile.kapazitaetMinuten / wochen : 0.0;
    final prozent = Format.prozent(zeile.auslastung, nachkomma: 0);
    final ueberbucht = zeile.ueberbuchteTage;

    return BalkenZeile(
      vorne: AbteilungsMarke(abteilung: zeile.abteilung),
      name: zeile.name,
      letzte: letzte,
      onTap: onTap,
      hinweis: '${zeile.name}\n'
          'Ø je Woche ${Zeit.kurz(jeWoche)} geplant, Kapazität '
          '${Zeit.kurz(kapazitaet)}\n'
          'Auslastung $prozent · an $ueberbucht von $planungstage '
          'Planungstagen überbucht'
          '${onTap != null ? '\nAntippen: die Anlagen dieser Abteilung' : ''}',
      werte: [
        ZeilenWert(
          '${Zeit.kurzOhneEinheit(jeWoche)} / ${Zeit.kurz(kapazitaet)}',
          breite: 120,
        ),
        ZeilenWert(prozent, breite: 52, farbe: farbe, fett: true),
        ZeilenWert(
          ueberbucht > 0 ? '${_tage(ueberbucht)} überbucht' : '',
          breite: 128,
          farbe: f.fehler,
        ),
      ],
      balken: SegmentBalken(
        segmente: [(zeile.auslastung, farbe)],
        max: skala,
        marke: 1,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Teil 2: Wohin die Zeit geht
// ---------------------------------------------------------------------------

class _ZeitBereich extends StatelessWidget {
  const _ZeitBereich({required this.auswertung});

  final ZeitAuswertung auswertung;

  @override
  Widget build(BuildContext context) {
    final g = auswertung.gesamt;
    if (g.summe <= 0) {
      return const Bereich(
        titel: 'Wohin die Zeit geht',
        untertitel: 'Planung',
        child: LeerHinweis(
          'Im Zeitraum ist nichts geplant.',
          icon: Icons.event_busy_outlined,
        ),
      );
    }

    final stuecke = [
      for (var i = 0; i < _zeitArten.length; i++)
        if (_zeitWert(g, _zeitArten[i].$1) > 0)
          KreisStueck(
            name: _zeitArten[i].$2,
            wert: _zeitWert(g, _zeitArten[i].$1),
            farbe: reihenFarbe(context, i),
            wertText: Zeit.kurz(_zeitWert(g, _zeitArten[i].$1)),
          ),
    ];

    return Bereich(
      titel: 'Wohin die Zeit geht',
      untertitel: 'Planung',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 32,
            runSpacing: 10,
            children: [
              Kennzahl(
                wert: Zeit.kurz(g.produktion),
                label: 'Produktion',
                gross: true,
              ),
              Kennzahl(
                wert: Zeit.kurz(g.neben),
                label: 'Rüsten, Reinigen, Sonstiges',
                gross: true,
              ),
              Kennzahl(
                wert: Format.prozent(g.neben / g.summe),
                label: 'Anteil Nebenzeiten',
                gross: true,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (g.neben <= 0)
            const HinweisBox(
              'Im Zeitraum sind keine Rüst-, Reinigungs- oder sonstigen '
              'Nebenzeiten eingetragen. Trägst du sie im Wochenboard über '
              'das Uhr-Symbol in der Tageszelle ein, zeigt dieser Bereich, '
              'wie viel Kapazität sie kosten — je Anlage.',
              titel: 'Noch keine Nebenzeiten',
            )
          else
            LayoutBuilder(
              builder: (context, c) {
                final kreis = StatistikKreis(
                  stuecke: stuecke,
                  summeText: Zeit.kurz(g.summe),
                  summeLabel: 'belegt',
                );
                final tabelle = _ZeitTabelle(zeilen: auswertung.jeSpur);
                if (c.maxWidth >= 900) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 420,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _Zwischentitel('Gesamt'),
                            kreis,
                          ],
                        ),
                      ),
                      const SizedBox(width: 28),
                      Expanded(child: tabelle),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Zwischentitel('Gesamt'),
                    kreis,
                    const SizedBox(height: 16),
                    tabelle,
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _ZeitTabelle extends StatelessWidget {
  const _ZeitTabelle({required this.zeilen});

  final List<ZeitZeile> zeilen;

  @override
  Widget build(BuildContext context) {
    final groesste =
        zeilen.fold(0.0, (m, z) => math.max(m, z.anteile.summe));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Zwischentitel('Je Anlage'),
        for (var i = 0; i < zeilen.length; i++)
          _zeile(context, zeilen[i], groesste, letzte: i == zeilen.length - 1),
        const SizedBox(height: 8),
        FarbLegende(
          eintraege: [
            for (var i = 0; i < _zeitArten.length; i++)
              (reihenFarbe(context, i), _zeitArten[i].$2),
          ],
        ),
        const SizedBox(height: 10),
        const _Fussnote(
          'Viel Rüst- und Reinigungszeit an einer Anlage? Ähnliche Artikel '
          'hintereinander zu planen — etwa mit gleichen Allergenen — '
          'spart Wechsel.',
        ),
      ],
    );
  }

  Widget _zeile(
    BuildContext context,
    ZeitZeile zeile,
    double groesste, {
    required bool letzte,
  }) {
    final a = zeile.anteile;
    final anteilNeben = a.summe > 0 ? a.neben / a.summe : 0.0;
    return BalkenZeile(
      vorne: AbteilungsMarke(abteilung: zeile.spur.abteilung),
      name: zeile.name,
      letzte: letzte,
      hinweis: [
        '${zeile.spur.abteilung.anzeigeName} · ${zeile.name}',
        for (final (art, name) in _zeitArten)
          if (_zeitWert(a, art) > 0) '$name: ${Zeit.kurz(_zeitWert(a, art))}',
      ].join('\n'),
      werte: [
        ZeilenWert(Zeit.kurz(a.summe), breite: 84),
        ZeilenWert(
          a.neben > 0
              ? '${Format.prozent(anteilNeben, nachkomma: 0)} Neben'
              : '',
          breite: 92,
        ),
      ],
      balken: SegmentBalken(
        segmente: [
          for (var i = 0; i < _zeitArten.length; i++)
            (_zeitWert(a, _zeitArten[i].$1), reihenFarbe(context, i)),
        ],
        max: groesste,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Teil 3: Ausbeute und Verlust
// ---------------------------------------------------------------------------

class _AusbeuteBereich extends StatelessWidget {
  const _AusbeuteBereich({
    required this.auswertung,
    required this.spanne,
    required this.abteilung,
  });

  final AusbeuteAuswertung auswertung;
  final StatistikSpanne spanne;
  final Abteilung? abteilung;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = auswertung;
    final gewaehlt = abteilung;
    final untertitel = gewaehlt == null
        ? 'erfasste Produktionen'
        : 'erfasste Produktionen · Artikel mit Schritt in '
            '${gewaehlt.anzeigeName}';
    final ausbeute = a.mittlereAusbeute;

    if (a.produktionen == 0) {
      return Bereich(
        titel: 'Ausbeute und Verlust',
        untertitel: untertitel,
        child: const LeerHinweis(
          'Im Zeitraum sind keine Produktionen erfasst. Erfasst werden sie '
          'in der Produktionserfassung.',
          icon: Icons.fact_check_outlined,
        ),
      );
    }
    if (ausbeute == null) {
      final welche = a.produktionen == 1
          ? 'der erfassten Produktion'
          : 'den ${a.produktionen} erfassten Produktionen';
      return Bereich(
        titel: 'Ausbeute und Verlust',
        untertitel: untertitel,
        child: HinweisBox(
          'Bei $welche fehlt eine plausible Fertigware — ohne sie lässt '
          'sich keine Ausbeute rechnen. Trag sie in der '
          'Produktionserfassung nach.',
          titel: 'Keine Ausbeute',
        ),
      );
    }

    // Wie in der Planung: Ausbeuten ab 100 % oder von 0 % gelten als
    // Erfassungsfehler.
    final nichtGezaehlt = [
      if (a.unplausibel > 0)
        '${a.unplausibel} mit einer Ausbeute ab 100 % oder von 0 %',
      if (a.ohneAusbeute > 0) '${a.ohneAusbeute} ohne Fertigware',
    ];

    return Bereich(
      titel: 'Ausbeute und Verlust',
      untertitel: untertitel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 32,
            runSpacing: 10,
            children: [
              Kennzahl(
                wert: Format.prozent(ausbeute),
                label: 'Ø Ausbeute je Produktion',
                gross: true,
              ),
              Kennzahl(
                wert: Format.kg(a.verlustKg),
                label: 'Verlust (Rohware − Fertigware)',
                gross: true,
              ),
              Kennzahl(
                wert: '${a.gueltig}',
                label: a.gueltig == 1
                    ? 'Produktion mit Ausbeute'
                    : 'Produktionen mit Ausbeute',
                gross: true,
              ),
            ],
          ),
          if (nichtGezaehlt.isNotEmpty) ...[
            const SizedBox(height: 8),
            _Fussnote(
              'Von ${a.produktionen} Produktionen nicht gezählt: '
              '${nichtGezaehlt.join(', ')} — wie in der Planung.',
            ),
          ],
          if (a.verlauf.isNotEmpty) ...[
            const SizedBox(height: 18),
            _Zwischentitel('Ø Verlust ${spanne.rasterText}'),
            StatistikSaeulen(
              saeulen: [
                for (final p in a.verlauf)
                  Saeule(
                    label: spanne.kurzname(p.abschnitt),
                    wert: switch (p.mittlererVerlust) {
                      final v? => v * 100,
                      _ => null,
                    },
                    farbe: theme.colorScheme.primary,
                    hinweis: '${spanne.langname(p.abschnitt)}\n'
                        'Ø Verlust '
                        '${Format.prozent(p.mittlererVerlust ?? 0.0)}\n'
                        '${Format.kg(p.verlustKg)} Verlust aus '
                        '${p.anzahl} '
                        '${p.anzahl == 1 ? 'Produktion' : 'Produktionen'}',
                  ),
              ],
              achsenText: (wert) => '${Format.zahl(wert)} %',
            ),
          ],
          const SizedBox(height: 18),
          const _Zwischentitel('Größte Schwankung je Artikel'),
          if (a.spannen.isEmpty)
            const _Fussnote(
              'Ab $kSpanneAbProduktionen Produktionen eines Artikels im '
              'Zeitraum zeigt sich hier, wie weit seine Ausbeute schwankt.',
            )
          else
            _SpannenTabelle(spannen: a.spannen),
          const SizedBox(height: 10),
          const _Fussnote(
            'Die Planung rechnet je Artikel mit dem Ø der letzten '
            'Produktionen. Wo die Ausbeute stark schwankt, liegt sie damit '
            'leicht daneben — dort lohnt Puffer oder die Suche nach der '
            'Ursache.',
          ),
        ],
      ),
    );
  }
}

class _SpannenTabelle extends StatelessWidget {
  const _SpannenTabelle({required this.spannen});

  final List<AusbeuteSpanne> spannen;

  @override
  Widget build(BuildContext context) {
    final grau = Theme.of(context).colorScheme.onSurfaceVariant;
    // Gemeinsame Achse aller Zeilen, auf 5 % gerundet.
    var unten = spannen.first.min;
    var oben = spannen.first.max;
    for (final s in spannen) {
      unten = math.min(unten, s.min);
      oben = math.max(oben, s.max);
    }
    final achseVon = (unten * 20).floor() / 20;
    var achseBis = (oben * 20).ceil() / 20;
    if (achseBis <= achseVon) achseBis = achseVon + 0.05;

    String prozent(double anteil) => Format.zahl(anteil * 100, nachkomma: 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < spannen.length; i++)
          BalkenZeile(
            name: '${spannen[i].artikel.artikelnummer} · '
                '${spannen[i].artikel.bezeichnung}',
            letzte: i == spannen.length - 1,
            hinweis: '${spannen[i].artikel.artikelnummer} · '
                '${spannen[i].artikel.bezeichnung}\n'
                'Ausbeute: schlechteste ${prozent(spannen[i].min)} %, '
                'Ø ${prozent(spannen[i].mittel)} %, '
                'beste ${prozent(spannen[i].max)} %\n'
                'Spanne ${prozent(spannen[i].spanne)} Prozentpunkte aus '
                '${spannen[i].anzahl} Produktionen',
            werte: [
              ZeilenWert(
                'Ø ${prozent(spannen[i].mittel)} %',
                breite: 76,
                fett: true,
                farbe: Theme.of(context).colorScheme.onSurface,
              ),
              ZeilenWert(
                '${prozent(spannen[i].min)}–${prozent(spannen[i].max)} %',
                breite: 108,
              ),
              ZeilenWert('${spannen[i].anzahl}×', breite: 40),
            ],
            balken: SpannenBalken(
              von: spannen[i].min,
              bis: spannen[i].max,
              mitte: spannen[i].mittel,
              achseVon: achseVon,
              achseBis: achseBis,
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
          child: Row(
            children: [
              Text(
                '${Format.zahl(achseVon * 100)} %',
                style: TextStyle(fontSize: 11, color: grau),
              ),
              Expanded(
                child: Text(
                  'Balken: schlechteste bis beste Ausbeute · Punkt: Ø',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: grau),
                ),
              ),
              Text(
                '${Format.zahl(achseBis * 100)} %',
                style: TextStyle(fontSize: 11, color: grau),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Teil 5: Produktmix
// ---------------------------------------------------------------------------

class _MixBereich extends StatelessWidget {
  const _MixBereich({required this.auswertung, required this.abteilung});

  final ProduktmixAuswertung auswertung;
  final Abteilung? abteilung;

  @override
  Widget build(BuildContext context) {
    final m = auswertung;
    final gewaehlt = abteilung;
    final untertitel = gewaehlt == null
        ? 'Rohware aus den erfassten Produktionen'
        : 'Rohware · Artikel mit Schritt in ${gewaehlt.anzeigeName}';

    if (m.kgGesamt <= 0) {
      return Bereich(
        titel: 'Produktmix',
        untertitel: untertitel,
        child: const LeerHinweis(
          'Im Zeitraum sind keine Produktionen mit Rohware erfasst.',
          icon: Icons.inventory_2_outlined,
        ),
      );
    }

    var farbIndex = 0;
    final stuecke = [
      for (final g in m.gruppen)
        KreisStueck(
          name: g.name,
          wert: g.kg,
          farbe: g.uebrige ? restFarbe : reihenFarbe(context, farbIndex++),
          wertText: Format.kg(g.kg),
        ),
    ];

    return Bereich(
      titel: 'Produktmix',
      untertitel: untertitel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 32,
            runSpacing: 10,
            children: [
              Kennzahl(
                wert: Format.kg(m.kgGesamt),
                label: 'Rohware',
                gross: true,
              ),
              Kennzahl(
                wert: '${m.produktionen}',
                label: m.produktionen == 1 ? 'Produktion' : 'Produktionen',
                gross: true,
              ),
              Kennzahl(
                wert: '${m.artikelAnzahl}',
                label: 'Artikel',
                gross: true,
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, c) {
              final gruppen = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Zwischentitel('Nach Produktgruppe'),
                  if (stuecke.length >= 2)
                    StatistikKreis(
                      stuecke: stuecke,
                      summeText: Format.kg(m.kgGesamt),
                      summeLabel: 'Rohware',
                    )
                  else
                    _Fussnote('Alles in einer Gruppe: ${stuecke.first.name}.'),
                ],
              );
              final artikel = _TopArtikel(
                artikel: m.topArtikel,
                kgGesamt: m.kgGesamt,
              );
              if (c.maxWidth >= 900) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 420, child: gruppen),
                    const SizedBox(width: 28),
                    Expanded(child: artikel),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  gruppen,
                  const SizedBox(height: 16),
                  artikel,
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TopArtikel extends StatelessWidget {
  const _TopArtikel({required this.artikel, required this.kgGesamt});

  final List<MixArtikel> artikel;
  final double kgGesamt;

  @override
  Widget build(BuildContext context) {
    final farbe = Theme.of(context).colorScheme.primary;
    final groesste = artikel.isEmpty ? 0.0 : artikel.first.kg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Zwischentitel(
          artikel.length == 1
              ? 'Der größte Artikel'
              : 'Die ${artikel.length} größten Artikel',
        ),
        for (var i = 0; i < artikel.length; i++)
          BalkenZeile(
            name: '${artikel[i].artikel.artikelnummer} · '
                '${artikel[i].artikel.bezeichnung}',
            letzte: i == artikel.length - 1,
            hinweis: '${artikel[i].artikel.artikelnummer} · '
                '${artikel[i].artikel.bezeichnung}\n'
                '${Format.kg(artikel[i].kg)} Rohware aus '
                '${artikel[i].produktionen} '
                '${artikel[i].produktionen == 1 ? 'Produktion' : 'Produktionen'}',
            werte: [
              ZeilenWert(Format.kg(artikel[i].kg), breite: 92),
              ZeilenWert(
                kgGesamt > 0
                    ? Format.prozent(artikel[i].kg / kgGesamt, nachkomma: 0)
                    : '',
                breite: 48,
              ),
            ],
            balken: SegmentBalken(
              segmente: [(artikel[i].kg, farbe)],
              max: groesste,
            ),
          ),
      ],
    );
  }
}
