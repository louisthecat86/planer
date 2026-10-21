import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/theme/app_stil.dart';
import '../../core/ui/bausteine.dart';
import '../../core/utils/fehler_text.dart';
import '../../core/utils/format.dart';
import '../../core/utils/zeit.dart';
import '../board/board_providers.dart' show CapacityStatus;
import '../whiteboard/whiteboard_provider.dart' show kLetzteProduktionen;
import 'statistik_daten.dart';
import 'statistik_diagramme.dart';

/// Statistik: was sich aus der Planung und den erfassten Produktionen
/// lernen lässt — wo es eng wird, wohin die Zeit geht, wie viel der Plan
/// erledigt wurde, wie die Ausbeute schwankt, was die Produktion schafft
/// und trägt und wo die Stammdaten Lücken haben.
///
/// Oben wählt man den Zeitraum und optional eine Abteilung; jeder Teil ist
/// ein eigener Bereich. Fehlen Daten, sagt der Bereich, was zu erfassen
/// wäre. Artikel und Lücken führen per Klick dorthin, wo man sie pflegt.
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
            fehlerText(fehler),
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
          abteilung: abteilung,
          onAbteilung: onAbteilung,
        ),
        const SizedBox(height: 12),
        _ZeitBereich(
          auswertung: werteZeitAus(daten.belegung, abteilung: abteilung),
        ),
        const SizedBox(height: 12),
        _ErfuellungBereich(
          auswertung: werteErfuellungAus(
            daten.karten,
            spanne,
            heute: daten.stand,
            abteilung: abteilung,
          ),
          abteilung: abteilung,
          onAbteilung: onAbteilung,
        ),
        const SizedBox(height: 12),
        _AusbeuteBereich(
          auswertung: werteAusbeuteAus(
            daten.produktionen,
            daten.artikel,
            spanne,
            abteilung: abteilung,
          ),
          abteilung: abteilung,
        ),
        const SizedBox(height: 12),
        _LeistungBereich(
          auswertung: werteLeistungAus(
            daten.produktionen,
            daten.artikel,
            spanne,
            abteilung: abteilung,
          ),
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
        const SizedBox(height: 12),
        _PflegeBereich(
          auswertung: wertePflegeAus(daten.artikel, daten.aktiveArtikel),
        ),
      ],
    );
  }
}

/// Öffnet die Seite [name] — und lädt die Statistik neu, wenn man
/// zurückkommt: Dort lassen sich Stammdaten pflegen, und die ändern die
/// Zahlen.
Future<void> _oeffne(
  BuildContext context,
  String name, {
  Map<String, String> pathParameters = const {},
  Map<String, dynamic> queryParameters = const {},
}) async {
  // Vor dem Warten holen, damit nach der Rückkehr kein Kontext mehr nötig
  // ist. Verlässt man die Seite über die Leiste statt zurück, endet das
  // Warten nicht — die Statistik lädt beim nächsten Öffnen ohnehin neu.
  final container = ProviderScope.containerOf(context, listen: false);
  await context.pushNamed(
    name,
    pathParameters: pathParameters,
    queryParameters: queryParameters,
  );
  container.invalidate(statistikProvider);
}

/// Öffnet die Stammdaten von [artikel].
Future<void> _oeffneArtikel(BuildContext context, StatistikArtikel artikel) =>
    _oeffne(
      context,
      'articleDetail',
      pathParameters: {'productId': artikel.id},
    );

/// „4711 · Rinderbratwurst" — Nummer und Bezeichnung, wie in den Listen.
String _artikelName(StatistikArtikel a) =>
    '${a.artikelnummer} · ${a.bezeichnung}';

/// Ein Anteil in ganzen Prozent — ohne „0 %" für etwas und ohne „100 %"
/// für nicht alles.
String _ganzeProzent(double anteil) {
  if (anteil > 0 && anteil < 0.005) return '< 1 %';
  if (anteil < 1 && anteil >= 0.995) return '> 99 %';
  return Format.prozent(anteil, nachkomma: 0);
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

/// Ab dieser Breite stehen Tabelle und Verlauf eines Bereichs nebeneinander
/// — auf breiten Bildschirmen stünden die Werte sonst weit weg vom Namen.
const double _zweiSpaltenAb = 1300;

/// Breite der Namensspalte in den einzeiligen Tabellen.
const double _namensBreite = 150;

/// Erst ab so viel Nebenzeit zeigt der Bereich „Wohin die Zeit geht" einen
/// Kreis — einer, der fast nur aus Produktion besteht, sagt nichts.
const double _kreisAbNebenzeit = 0.02;

/// Zwei Spalten nebeneinander — auf schmaleren Fenstern untereinander.
class _ZweiSpalten extends StatelessWidget {
  const _ZweiSpalten({required this.links, required this.rechts});

  final Widget links;
  final Widget rechts;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= _zweiSpaltenAb) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: links),
              const SizedBox(width: 32),
              Expanded(child: rechts),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            links,
            const SizedBox(height: 18),
            rechts,
          ],
        );
      },
    );
  }
}

/// Ampelfarbe wie im Board.
Color _ampel(BuildContext context, CapacityStatus status) {
  final f = AppFarben.von(context);
  return switch (status) {
    CapacityStatus.frei => grauFarbe(context),
    CapacityStatus.gut => f.ok,
    CapacityStatus.ueberbucht => f.fehler,
  };
}

/// Auslastung in ganzen Prozent — „< 1 %" statt „0 %", wenn doch etwas
/// geplant ist.
String _auslastungText(double anteil) => anteil > 0 && anteil < 0.005
    ? '< 1 %'
    : Format.prozent(anteil, nachkomma: 0);

String _tage(int n) => n == 1 ? '1 Tag' : '$n Tage';

/// „Wochen" bzw. „Monaten" — für den Hinweis ohne Verlauf.
String _abschnitteText(StatistikSpanne spanne) =>
    spanne.raster == StatistikRaster.woche ? 'Wochen' : 'Monaten';

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
    required this.abteilung,
    required this.onAbteilung,
  });

  final AuslastungsAuswertung auswertung;
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
    final vs = a.verlaufSpanne;
    // Gemeinsamer Maßstab aller Zeilen — mindestens bis 120 %, damit die
    // 100-%-Marke nicht am Rand klebt.
    final skala = a.zeilen.fold(1.2, (m, z) => math.max(m, z.auslastung));
    // Die Spalte mit den überbuchten Tagen nur, wenn es welche gibt.
    final mitUeberbucht = a.zeilen.any((z) => z.ueberbuchteTage > 0);

    final tabelle = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
            mitUeberbucht: mitUeberbucht,
            letzte: i == a.zeilen.length - 1,
            // Ohne Filter führt eine Abteilung zu ihren Anlagen.
            onTap: gewaehlt == null
                ? () => onAbteilung(a.zeilen[i].abteilung)
                : null,
          ),
        const SizedBox(height: 8),
        FarbLegende(
          eintraege: [
            (grauFarbe(context), 'unter 75 %'),
            (f.ok, 'gut gefüllt'),
            (f.fehler, 'überbucht'),
          ],
          linie: '100 %',
        ),
      ],
    );

    final verlauf = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Zwischentitel(
          'Ø Auslastung ${vs.rasterText} · '
          '${gewaehlt?.anzeigeName ?? 'alle Abteilungen zusammen'}',
        ),
        if (a.verlaufPunkte >= 2)
          StatistikSaeulen(
            saeulen: [
              for (final p in a.verlauf)
                Saeule(
                  label: vs.kurzname(p.abschnitt),
                  wert: p.hatDaten ? p.auslastung * 100 : null,
                  farbe: _ampel(context, p.status),
                  hinweis: '${vs.langname(p.abschnitt)}\n'
                      'Ø Auslastung ${_auslastungText(p.auslastung)}\n'
                      '${Zeit.kurz(p.belegtMinuten)} von '
                      '${Zeit.kurz(p.kapazitaetMinuten)}\n'
                      '${p.ueberbuchteTage} von ${p.tage} '
                      '${p.tage == 1 ? 'Tag' : 'Tagen'} überbucht',
                ),
            ],
            achsenText: (wert) => '${Format.zahl(wert)} %',
            linie: 100,
            linienFarbe: f.fehler,
          )
        else
          _Fussnote(
            'Ein Verlauf braucht Planung in mindestens zwei '
            '${_abschnitteText(vs)}.',
          ),
      ],
    );

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
                wert: _auslastungText(a.auslastung),
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
                  label: 'Engpass · Ø ${_auslastungText(engpass.auslastung)}',
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
          _ZweiSpalten(links: tabelle, rechts: verlauf),
          const SizedBox(height: 12),
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
    required this.mitUeberbucht,
    required this.letzte,
    this.onTap,
  });

  final AuslastungsZeile zeile;
  final int wochen;
  final int planungstage;
  final double skala;

  /// Ob die Spalte mit den überbuchten Tagen steht.
  final bool mitUeberbucht;
  final bool letzte;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final f = AppFarben.von(context);
    final status = zeile.status;
    final farbe = _ampel(context, status);
    final jeWoche = wochen > 0 ? zeile.belegtMinuten / wochen : 0.0;
    final kapazitaet = wochen > 0 ? zeile.kapazitaetMinuten / wochen : 0.0;
    final prozent = _auslastungText(zeile.auslastung);
    final ueberbucht = zeile.ueberbuchteTage;

    return BalkenZeile(
      vorne: AbteilungsMarke(abteilung: zeile.abteilung),
      name: zeile.name,
      namensBreite: _namensBreite,
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
          breite: 112,
        ),
        ZeilenWert(
          prozent,
          breite: 52,
          // Grau ist als Schrift zu blass — die Ampel zeigt der Balken.
          farbe: status == CapacityStatus.frei
              ? Theme.of(context).colorScheme.onSurface
              : farbe,
          fett: true,
        ),
        if (mitUeberbucht)
          ZeilenWert(
            ueberbucht > 0 ? _tage(ueberbucht) : '',
            breite: 64,
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

    final anteilNeben = g.neben / g.summe;
    final Widget gesamt;
    if (anteilNeben >= _kreisAbNebenzeit) {
      gesamt = StatistikKreis(
        stuecke: [
          for (var i = 0; i < _zeitArten.length; i++)
            if (_zeitWert(g, _zeitArten[i].$1) > 0)
              KreisStueck(
                name: _zeitArten[i].$2,
                wert: _zeitWert(g, _zeitArten[i].$1),
                farbe: reihenFarbe(context, i),
                wertText: Zeit.kurz(_zeitWert(g, _zeitArten[i].$1)),
              ),
        ],
        summeText: Zeit.kurz(g.summe),
        summeLabel: 'belegt',
      );
    } else if (g.neben <= 0) {
      gesamt = const HinweisBox(
        'Im Zeitraum sind keine Rüst-, Reinigungs- oder sonstigen '
        'Nebenzeiten eingetragen. Trägst du sie im Wochenboard über das '
        'Uhr-Symbol in der Tageszelle ein, zeigt hier ein Kreis, wie viel '
        'Kapazität sie kosten.',
        titel: 'Noch keine Nebenzeiten',
      );
    } else {
      gesamt = HinweisBox(
        'Nebenzeiten sind kaum eingetragen: ${Zeit.kurz(g.neben)}, '
        '${Format.prozent(anteilNeben)} der belegten Zeit. Trägst du '
        'Rüst- und Reinigungszeiten im Wochenboard über das Uhr-Symbol in '
        'der Tageszelle ein, zeigt hier ein Kreis, wie viel Kapazität sie '
        'kosten.',
        titel: 'Kaum Nebenzeiten',
      );
    }

    final links = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Zwischentitel('Gesamt'),
        gesamt,
      ],
    );
    final tabelle = _ZeitTabelle(zeilen: auswertung.jeSpur);

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
                wert: Format.prozent(anteilNeben),
                label: 'Anteil Nebenzeiten',
                gross: true,
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, c) {
              if (c.maxWidth >= 900) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 420, child: links),
                    const SizedBox(width: 32),
                    Expanded(child: tabelle),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  links,
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
      namensBreite: _namensBreite,
      letzte: letzte,
      hinweis: [
        '${zeile.spur.abteilung.anzeigeName} · ${zeile.name}',
        for (final (art, name) in _zeitArten)
          if (_zeitWert(a, art) > 0) '$name: ${Zeit.kurz(_zeitWert(a, art))}',
      ].join('\n'),
      werte: [
        ZeilenWert(Zeit.kurz(a.summe), breite: 76),
        ZeilenWert(
          a.neben > 0 ? '${Format.prozent(anteilNeben)} Neben' : '',
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
// Teil 6: Planerfüllung
// ---------------------------------------------------------------------------

/// Die Teile der Planerfüllung in fester Folge: das Grün von „erledigt" im
/// Board, blasser für nur abgehakt, der offene Rest fast wie die leere
/// Spur. Die Abstufung über die Helligkeit bleibt auch bei
/// Farbsehschwäche lesbar.
List<(Color, String)> _erfuellungsFarben(BuildContext context) {
  final ok = AppFarben.von(context).ok;
  return [
    (ok, 'erfasst'),
    (blasseFarbe(context, ok, deckkraft: 0.6), 'nur abgehakt'),
    (restFarbe(context), 'offen'),
  ];
}

/// Die Teile als Segmente, zusammen [ganz] — leer ohne Karten.
List<(double, Color)> _erfuellungsSegmente(
  ErfuellungsZahlen z,
  List<(Color, String)> farben, {
  double ganz = 1,
}) {
  if (z.karten == 0) return const [];
  return [
    (z.erfasst / z.karten * ganz, farben[0].$1),
    (z.abgehakt / z.karten * ganz, farben[1].$1),
    (z.offen / z.karten * ganz, farben[2].$1),
  ];
}

/// „Erledigt 92 %: 46 von 50 Karten" und darunter die Teile.
String _erfuellungsText(ErfuellungsZahlen z) =>
    'Erledigt ${_ganzeProzent(z.anteilErledigt)}: ${z.erledigt} von '
    '${z.karten} ${z.karten == 1 ? 'Karte' : 'Karten'}\n'
    'erfasst ${z.erfasst} · nur abgehakt ${z.abgehakt} · offen ${z.offen}';

class _ErfuellungBereich extends StatelessWidget {
  const _ErfuellungBereich({
    required this.auswertung,
    required this.abteilung,
    required this.onAbteilung,
  });

  final ErfuellungsAuswertung auswertung;
  final Abteilung? abteilung;
  final ValueChanged<Abteilung?> onAbteilung;

  @override
  Widget build(BuildContext context) {
    final f = AppFarben.von(context);
    final e = auswertung;
    final g = e.gesamt;
    final gewaehlt = abteilung;
    final untertitel = gewaehlt == null
        ? 'Karten im Board bis gestern'
        : 'Karten im Board bis gestern · ${gewaehlt.anzeigeName}';

    if (e.leer) {
      return Bereich(
        titel: 'Planerfüllung',
        untertitel: untertitel,
        child: const LeerHinweis(
          'Im Zeitraum war bis gestern nichts geplant.',
          icon: Icons.event_busy_outlined,
        ),
      );
    }

    final farben = _erfuellungsFarben(context);
    final vs = e.verlaufSpanne;

    final tabelle = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Zwischentitel('Je Abteilung'),
        for (var i = 0; i < e.jeAbteilung.length; i++)
          _ErfuellungsZeile(
            zeile: e.jeAbteilung[i],
            farben: farben,
            letzte: i == e.jeAbteilung.length - 1,
            // Ohne Filter führt eine Abteilung zu ihren Zahlen.
            onTap: gewaehlt == null
                ? () => onAbteilung(e.jeAbteilung[i].abteilung)
                : null,
          ),
        const SizedBox(height: 8),
        FarbLegende(eintraege: farben),
      ],
    );

    final verlauf = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Zwischentitel(
          'Erledigt ${vs.rasterText} · '
          '${gewaehlt?.anzeigeName ?? 'alle Abteilungen zusammen'}',
        ),
        if (e.verlaufPunkte >= 2)
          StatistikSaeulen(
            saeulen: [
              for (final p in e.verlauf)
                Saeule(
                  label: vs.kurzname(p.abschnitt),
                  wert: p.hatDaten ? 100 : null,
                  farbe: farben.last.$1,
                  segmente: _erfuellungsSegmente(p.zahlen, farben, ganz: 100),
                  hinweis: '${vs.langname(p.abschnitt)}\n'
                      '${_erfuellungsText(p.zahlen)}',
                ),
            ],
            achsenText: (wert) => '${Format.zahl(wert)} %',
            festesMax: 100,
          )
        else
          _Fussnote(
            'Ein Verlauf braucht Karten in mindestens zwei '
            '${_abschnitteText(vs)}.',
          ),
      ],
    );

    return Bereich(
      titel: 'Planerfüllung',
      untertitel: untertitel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 32,
            runSpacing: 10,
            children: [
              Kennzahl(
                wert: _ganzeProzent(g.anteilErledigt),
                label: 'erledigt · ${g.erledigt} von ${g.karten} '
                    '${g.karten == 1 ? 'Karte' : 'Karten'}',
                gross: true,
              ),
              Kennzahl(
                wert: _ganzeProzent(g.anteilErfasst),
                label: 'mit erfasster Produktion',
                gross: true,
              ),
              Kennzahl(
                wert: '${g.offen}',
                label: g.offen == 1 ? 'Karte offen' : 'Karten offen',
                farbe: g.offen > 0 ? f.warnung : null,
                gross: true,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _ZweiSpalten(links: tabelle, rechts: verlauf),
          const SizedBox(height: 12),
          const _Fussnote(
            'Gezählt werden die Karten im Board bis gestern — heute läuft '
            'noch. Erfasst: Die Produktion ist in der Produktionserfassung '
            'eingetragen; das macht ihre ganze Kette erledigt. Nur '
            'abgehakt: im Board von Hand erledigt — dann fehlen der '
            'Statistik Ausbeute und Zeit. Offen: weder noch, vielleicht '
            'produziert und nicht eingetragen.',
          ),
        ],
      ),
    );
  }
}

class _ErfuellungsZeile extends StatelessWidget {
  const _ErfuellungsZeile({
    required this.zeile,
    required this.farben,
    required this.letzte,
    this.onTap,
  });

  final ErfuellungsZeile zeile;
  final List<(Color, String)> farben;
  final bool letzte;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final z = zeile.zahlen;
    final name = zeile.abteilung.anzeigeName;
    return BalkenZeile(
      vorne: AbteilungsMarke(abteilung: zeile.abteilung),
      name: name,
      namensBreite: _namensBreite,
      letzte: letzte,
      onTap: onTap,
      hinweis: '$name\n${_erfuellungsText(z)}'
          '${onTap != null ? '\nAntippen: nur diese Abteilung' : ''}',
      werte: [
        ZeilenWert('${z.erledigt} von ${z.karten}', breite: 92),
        ZeilenWert(
          _ganzeProzent(z.anteilErledigt),
          breite: 52,
          farbe: Theme.of(context).colorScheme.onSurface,
          fett: true,
        ),
      ],
      balken: SegmentBalken(
        segmente: _erfuellungsSegmente(z, farben),
        max: 1,
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
    required this.abteilung,
  });

  final AusbeuteAuswertung auswertung;
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
    final vs = a.verlaufSpanne;

    final verlauf = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Zwischentitel('Ø Verlust ${vs.rasterText}'),
        if (a.verlaufPunkte >= 2)
          StatistikSaeulen(
            saeulen: [
              for (final p in a.verlauf)
                Saeule(
                  label: vs.kurzname(p.abschnitt),
                  wert: switch (p.mittlererVerlust) {
                    final v? => v * 100,
                    _ => null,
                  },
                  farbe: theme.colorScheme.primary,
                  hinweis: '${vs.langname(p.abschnitt)}\n'
                      'Ø Verlust '
                      '${Format.prozent(p.mittlererVerlust ?? 0.0)}\n'
                      '${Format.kg(p.verlustKg)} Verlust aus '
                      '${p.anzahl} '
                      '${p.anzahl == 1 ? 'Produktion' : 'Produktionen'}',
                ),
            ],
            achsenText: (wert) => '${Format.zahl(wert)} %',
          )
        else
          _Fussnote(
            'Ein Verlauf braucht Produktionen mit Ausbeute in mindestens '
            'zwei ${_abschnitteText(vs)}.',
          ),
      ],
    );

    final spannen = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Zwischentitel('Größte Schwankung je Artikel'),
        if (a.spannen.isEmpty)
          const _Fussnote(
            'Ab $kSpanneAbProduktionen Produktionen eines Artikels im '
            'Zeitraum zeigt sich hier, wie weit seine Ausbeute schwankt.',
          )
        else
          _SpannenTabelle(spannen: a.spannen),
      ],
    );

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
          const SizedBox(height: 16),
          _ZweiSpalten(links: verlauf, rechts: spannen),
          const SizedBox(height: 12),
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
    final farben = Theme.of(context).colorScheme;
    final grau = farben.onSurfaceVariant;
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
            name: _artikelName(spannen[i].artikel),
            letzte: i == spannen.length - 1,
            onTap: () => _oeffneArtikel(context, spannen[i].artikel),
            hinweis: '${_artikelName(spannen[i].artikel)}\n'
                'Ausbeute: schlechteste ${prozent(spannen[i].min)} %, '
                'Ø ${prozent(spannen[i].mittel)} %, '
                'beste ${prozent(spannen[i].max)} %\n'
                'Spanne ${prozent(spannen[i].spanne)} Prozentpunkte aus '
                '${spannen[i].anzahl} Produktionen\n'
                'Antippen: Artikel öffnen',
            werte: [
              ZeilenWert(
                'Ø ${prozent(spannen[i].mittel)} %',
                breite: 76,
                fett: true,
                farbe: farben.onSurface,
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
// Teil 4: Leistung
// ---------------------------------------------------------------------------

/// „1.240 kg/h"
String _kgh(double kgProStunde) => '${Format.zahl(kgProStunde)} kg/h';

/// „+38 %" bzw. „−12 %" — immer mit Vorzeichen.
String _abweichungText(double anteil) {
  final text = Format.prozent(anteil.abs(), nachkomma: 0);
  return anteil < 0 ? '−$text' : '+$text';
}

class _LeistungBereich extends StatelessWidget {
  const _LeistungBereich({required this.auswertung, required this.abteilung});

  final LeistungsAuswertung auswertung;
  final Abteilung? abteilung;

  @override
  Widget build(BuildContext context) {
    final l = auswertung;
    final gewaehlt = abteilung;
    final untertitel = gewaehlt == null
        ? 'erfasste Produktionen mit Zeit'
        : 'erfasste Produktionen · Artikel mit Schritt in '
            '${gewaehlt.anzeigeName}';
    final kgh = l.kgProStunde;

    if (l.produktionen == 0) {
      return Bereich(
        titel: 'Leistung',
        untertitel: untertitel,
        child: const LeerHinweis(
          'Im Zeitraum ist keine Produktion mit Rohware erfasst. Mit Start '
          'und Ende eingetragen, zeigt sich hier, wie viel je Stunde '
          'geschafft wird.',
          icon: Icons.speed,
        ),
      );
    }
    if (kgh == null) {
      final welche = l.produktionen == 1
          ? 'der erfassten Produktion'
          : 'den ${l.produktionen} erfassten Produktionen';
      return Bereich(
        titel: 'Leistung',
        untertitel: untertitel,
        child: HinweisBox(
          'Bei $welche fehlt die Produktionszeit — ohne sie lässt sich '
          'keine Leistung rechnen. Trag Start und Ende in der '
          'Produktionserfassung ein.',
          titel: 'Keine Produktionszeit',
        ),
      );
    }

    final zeit = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Zwischentitel('Die meiste Produktionszeit'),
        _ZeitverbraucherTabelle(artikel: l.zeitverbraucher),
      ],
    );

    final abweichung = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Zwischentitel(
          l.verglichen == 0
              ? 'Abweichung von den Leistungsdaten'
              : 'Abweichung von den Leistungsdaten · ${l.abweichend} von '
                  '${l.verglichen} Artikeln',
        ),
        if (l.abweichungen.isNotEmpty) ...[
          _AbweichungsTabelle(artikel: l.abweichungen),
          if (l.abweichend > l.abweichungen.length) ...[
            const SizedBox(height: 6),
            _Fussnote(
              'Gezeigt sind die ${l.abweichungen.length} Artikel mit der '
              'größten Abweichung.',
            ),
          ],
        ] else if (l.verglichen == 0)
          const _Fussnote(
            'Ab $kLeistungVergleichAb Produktionen mit Zeit vergleicht die '
            'Statistik einen Artikel mit den Leistungsdaten seiner '
            'Bratstraße. Im Zeitraum hat das noch kein Artikel.',
          )
        else
          _Fussnote(
            l.verglichen == 1
                ? 'Der vergleichbare Artikel liegt weniger als '
                    '${Format.prozent(kLeistungAbweichungAb, nachkomma: 0)} '
                    'neben seinen Leistungsdaten.'
                : 'Alle ${l.verglichen} vergleichbaren Artikel liegen '
                    'weniger als '
                    '${Format.prozent(kLeistungAbweichungAb, nachkomma: 0)} '
                    'neben ihren Leistungsdaten.',
          ),
      ],
    );

    return Bereich(
      titel: 'Leistung',
      untertitel: untertitel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 32,
            runSpacing: 10,
            children: [
              Kennzahl(
                wert: _kgh(kgh),
                label: 'Ø Rohware je Stunde',
                gross: true,
              ),
              Kennzahl(
                wert: Zeit.kurz(l.minuten),
                label: 'Produktionszeit',
                gross: true,
              ),
              Kennzahl(
                wert: '${l.mitZeit}',
                label: l.mitZeit == 1
                    ? 'Produktion mit Zeit'
                    : 'Produktionen mit Zeit',
                gross: true,
              ),
            ],
          ),
          if (l.ohneZeit > 0) ...[
            const SizedBox(height: 8),
            _Fussnote(
              'Von ${l.produktionen} Produktionen nicht gezählt: '
              '${l.ohneZeit} ohne Produktionszeit.',
            ),
          ],
          const SizedBox(height: 16),
          _ZweiSpalten(links: zeit, rechts: abweichung),
          const SizedBox(height: 12),
          const _Fussnote(
            'Leistung heißt hier: Rohware je Stunde Produktionszeit, wie '
            'sie bei der Erfassung eingetragen wird. An der Bratstraße '
            'rechnet die Planung mit dem Ø der letzten '
            '$kLetzteProduktionen Produktionen — hinterlegte '
            'Leistungsdaten gelten dort nur, solange keine erfasst sind. '
            'Weichen sie stark ab, lohnt es, sie im Artikel nachzuziehen.',
          ),
        ],
      ),
    );
  }
}

class _ZeitverbraucherTabelle extends StatelessWidget {
  const _ZeitverbraucherTabelle({required this.artikel});

  final List<ArtikelLeistung> artikel;

  @override
  Widget build(BuildContext context) {
    final farbe = Theme.of(context).colorScheme.primary;
    final groesste = artikel.isEmpty ? 0.0 : artikel.first.minuten;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < artikel.length; i++)
          BalkenZeile(
            name: _artikelName(artikel[i].artikel),
            letzte: i == artikel.length - 1,
            onTap: () => _oeffneArtikel(context, artikel[i].artikel),
            hinweis: _hinweis(artikel[i]),
            werte: [
              ZeilenWert(Zeit.kurz(artikel[i].minuten), breite: 80),
              ZeilenWert('Ø ${_kgh(artikel[i].kgProStunde)}', breite: 104),
              ZeilenWert('${artikel[i].anzahl}×', breite: 40),
            ],
            balken: SegmentBalken(
              segmente: [(artikel[i].minuten, farbe)],
              max: groesste,
            ),
          ),
      ],
    );
  }

  String _hinweis(ArtikelLeistung a) {
    final hinterlegt = a.hinterlegt;
    return [
      _artikelName(a.artikel),
      '${Zeit.kurz(a.minuten)} für ${Format.kg(a.kg)} Rohware aus '
          '${a.anzahl} ${a.anzahl == 1 ? 'Produktion' : 'Produktionen'}',
      if (a.anzahl > 1)
        'Ø ${_kgh(a.kgProStunde)} · langsamste ${_kgh(a.langsamste)}, '
            'schnellste ${_kgh(a.schnellste)}'
      else
        'Ø ${_kgh(a.kgProStunde)}',
      if (hinterlegt != null)
        'Hinterlegt für die Bratstraße: ${_kgh(hinterlegt)}',
      'Antippen: Artikel öffnen',
    ].join('\n');
  }
}

class _AbweichungsTabelle extends StatelessWidget {
  const _AbweichungsTabelle({required this.artikel});

  /// Nur Artikel mit Leistungsdaten — ohne sie gibt es keine Abweichung.
  final List<ArtikelLeistung> artikel;

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    final grau = farben.onSurfaceVariant;
    final langsamer = reihenFarbe(context, 1);
    final schneller = reihenFarbe(context, 0);
    // Gemeinsame Achse, auf 25 % gerundet: mindestens ±50 %, höchstens
    // ±100 % — was darüber liegt, endet am Rand.
    var groesste = 0.0;
    for (final a in artikel) {
      groesste = math.max(groesste, (a.abweichung ?? 0.0).abs());
    }
    final grenze = math.min(math.max((groesste * 4).ceil() / 4, 0.5), 1.0);
    final grenzeText = Format.prozent(grenze, nachkomma: 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < artikel.length; i++)
          _zeile(
            context,
            artikel[i],
            grenze: grenze,
            langsamer: langsamer,
            schneller: schneller,
            letzte: i == artikel.length - 1,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
          child: Row(
            children: [
              Text(
                '−$grenzeText',
                style: TextStyle(fontSize: 11, color: grau),
              ),
              Expanded(
                child: Text(
                  'Strich: hinterlegte Leistung',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: grau),
                ),
              ),
              Text(
                '+$grenzeText',
                style: TextStyle(fontSize: 11, color: grau),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        FarbLegende(
          eintraege: [
            (langsamer, 'langsamer als hinterlegt'),
            (schneller, 'schneller als hinterlegt'),
          ],
        ),
      ],
    );
  }

  Widget _zeile(
    BuildContext context,
    ArtikelLeistung a, {
    required double grenze,
    required Color langsamer,
    required Color schneller,
    required bool letzte,
  }) {
    final d = a.abweichung ?? 0.0;
    final hinterlegt = a.hinterlegt ?? 0.0;
    return BalkenZeile(
      name: _artikelName(a.artikel),
      letzte: letzte,
      onTap: () => _oeffneArtikel(context, a.artikel),
      hinweis: '${_artikelName(a.artikel)}\n'
          'Gemessen Ø ${_kgh(a.kgProStunde)} aus ${a.anzahl} Produktionen\n'
          'Hinterlegt für die Bratstraße: ${_kgh(hinterlegt)}\n'
          '${d < 0 ? 'Langsamer' : 'Schneller'} als hinterlegt: '
          '${_abweichungText(d)}\n'
          'Antippen: Artikel öffnen',
      werte: [
        ZeilenWert(
          '${Format.zahl(a.kgProStunde)} statt '
          '${Format.zahl(hinterlegt)} kg/h',
          breite: 150,
        ),
        ZeilenWert(
          _abweichungText(d),
          breite: 52,
          farbe: Theme.of(context).colorScheme.onSurface,
          fett: true,
        ),
      ],
      balken: AbweichungsBalken(
        wert: d,
        grenze: grenze,
        farbeWeniger: langsamer,
        farbeMehr: schneller,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Teil 5: Produktmix
// ---------------------------------------------------------------------------

/// Ab diesem Anteil ohne Produktgruppe erklärt der Bereich, was fehlt.
const double _ohneGruppeHinweisAb = 0.2;

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

    // Echte Gruppen in den Reihenfarben, „Übrige" hellgrau und Artikel
    // ohne Gruppe grau — sie sind eine Lücke, keine Gruppe.
    var farbIndex = 0;
    final stuecke = [
      for (final g in m.gruppen)
        KreisStueck(
          name: g.name,
          wert: g.kg,
          farbe: g.ohneGruppe
              ? grauFarbe(context)
              : (g.uebrige
                  ? hellgrauFarbe(context)
                  : reihenFarbe(context, farbIndex++)),
          wertText: Format.kg(g.kg),
        ),
    ];
    final anteilOhne = m.kgOhneGruppe / m.kgGesamt;

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
        if (anteilOhne >= _ohneGruppeHinweisAb) ...[
          const SizedBox(height: 10),
          _Fussnote(
            '${Format.prozent(anteilOhne, nachkomma: 0)} der Rohware '
            'stammen von Artikeln ohne Produktgruppe. Die Gruppe wird in '
            'den Stammdaten des Artikels gepflegt — dann zeigt der Kreis, '
            'was die Produktion trägt.',
          ),
        ],
      ],
    );
    final artikel = _TopArtikel(artikel: m.topArtikel, kgGesamt: m.kgGesamt);

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
              if (c.maxWidth >= 900) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 420, child: gruppen),
                    const SizedBox(width: 32),
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
            name: _artikelName(artikel[i].artikel),
            letzte: i == artikel.length - 1,
            onTap: () => _oeffneArtikel(context, artikel[i].artikel),
            hinweis: '${_artikelName(artikel[i].artikel)}\n'
                '${Format.kg(artikel[i].kg)} Rohware aus '
                '${artikel[i].produktionen} '
                '${artikel[i].produktionen == 1 ? 'Produktion' : 'Produktionen'}\n'
                'Antippen: Artikel öffnen',
            werte: [
              ZeilenWert(Format.kg(artikel[i].kg), breite: 92),
              ZeilenWert(
                kgGesamt > 0 ? Format.prozent(artikel[i].kg / kgGesamt) : '',
                breite: 56,
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

// ---------------------------------------------------------------------------
// Teil 7: Stammdaten-Pflege
// ---------------------------------------------------------------------------

/// Breite der Namensspalte der Lücken — „Ohne Prozessschritte" passt.
const double _lueckenNamensBreite = 170;

class _PflegeBereich extends StatelessWidget {
  const _PflegeBereich({required this.auswertung});

  final PflegeAuswertung auswertung;

  static const String _titel = 'Stammdaten-Pflege';
  static const String _untertitel = 'alle Artikel · gleich welche Abteilung';

  @override
  Widget build(BuildContext context) {
    final p = auswertung;
    if (p.artikel == 0) {
      return const Bereich(
        titel: _titel,
        untertitel: _untertitel,
        child: LeerHinweis(
          'Es sind noch keine Artikel angelegt.',
          icon: Icons.inventory_2_outlined,
        ),
      );
    }

    final farbe = Theme.of(context).colorScheme.primary;
    final blass = blasseFarbe(context, farbe);

    final Widget tabelle;
    if (p.vollstaendig == p.artikel) {
      tabelle = HinweisBox(
        p.artikel == 1
            ? 'Dem Artikel fehlt nichts, womit die Planung rechnet.'
            : 'Allen ${p.artikel} Artikeln fehlt nichts, womit die Planung '
                'rechnet.',
        art: StatusArt.ok,
        titel: 'Vollständig gepflegt',
      );
    } else {
      tabelle = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Zwischentitel('Artikel mit Lücken'),
          for (var i = 0; i < p.zeilen.length; i++)
            _PflegeZeile(
              zeile: p.zeilen[i],
              artikel: p.artikel,
              farbe: farbe,
              blass: blass,
              letzte: i == p.zeilen.length - 1,
            ),
          const SizedBox(height: 8),
          FarbLegende(
            eintraege: [
              (farbe, 'aktiv: im Zeitraum produziert oder geplant'),
              (blass, 'übrige'),
            ],
          ),
        ],
      );
    }

    final bedeutung = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Zwischentitel('Was fehlt — und was daraus folgt'),
        for (final z in p.zeilen) _Bedeutung(zeile: z),
      ],
    );

    return Bereich(
      titel: _titel,
      untertitel: _untertitel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 32,
            runSpacing: 10,
            children: [
              Kennzahl(
                wert: '${p.artikel}',
                label: 'Artikel',
                gross: true,
              ),
              Kennzahl(
                wert: '${p.vollstaendig}',
                label: 'vollständig gepflegt · '
                    '${_ganzeProzent(p.anteilVollstaendig)}',
                gross: true,
              ),
              Kennzahl(
                wert: '${p.aktiv}',
                label: 'aktiv: im Zeitraum produziert oder geplant',
                gross: true,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _ZweiSpalten(links: tabelle, rechts: bedeutung),
          const SizedBox(height: 12),
          const _Fussnote(
            'Gezählt wie in der Artikelliste: Antippen öffnet sie mit genau '
            'diesen Artikeln. Am meisten bringt die Pflege bei den aktiven '
            '— mit ihnen rechnet die Planung gerade.',
          ),
        ],
      ),
    );
  }
}

class _PflegeZeile extends StatelessWidget {
  const _PflegeZeile({
    required this.zeile,
    required this.artikel,
    required this.farbe,
    required this.blass,
    required this.letzte,
  });

  final PflegeZeile zeile;

  /// Alle Artikel — die volle Länge des Balkens.
  final int artikel;
  final Color farbe;
  final Color blass;
  final bool letzte;

  @override
  Widget build(BuildContext context) {
    final z = zeile;
    final l = z.luecke;
    final leer = z.anzahl == 0;
    return BalkenZeile(
      name: l.titel,
      namensBreite: _lueckenNamensBreite,
      letzte: letzte,
      // Eine leere Liste zu öffnen, hilft niemandem.
      onTap: leer
          ? null
          : () => _oeffne(
                context,
                'articles',
                queryParameters: {'luecke': l.name},
              ),
      hinweis: '${l.titel}: ${z.anzahl} von $artikel '
          '${artikel == 1 ? 'Artikel' : 'Artikeln'}, davon ${z.aktiv} im '
          'Zeitraum produziert oder geplant\n'
          '${l.folge}'
          '${leer ? '' : '\nAntippen: diese Artikel in der Artikelliste'}',
      werte: [
        ZeilenWert(
          '${z.anzahl}',
          breite: 48,
          farbe: Theme.of(context).colorScheme.onSurface,
          fett: true,
        ),
        ZeilenWert(z.aktiv > 0 ? '${z.aktiv} aktiv' : '', breite: 72),
      ],
      balken: SegmentBalken(
        segmente: [
          (z.aktiv.toDouble(), farbe),
          ((z.anzahl - z.aktiv).toDouble(), blass),
        ],
        max: artikel.toDouble(),
      ),
    );
  }
}

/// Eine Lücke, ausgeschrieben: was fehlt und was die Planung dann tut.
class _Bedeutung extends StatelessWidget {
  const _Bedeutung({required this.zeile});

  final PflegeZeile zeile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = zeile.luecke;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${l.titel}: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: l.folge),
          ],
        ),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.35,
        ),
      ),
    );
  }
}
