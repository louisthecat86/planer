import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_stil.dart';
import '../../core/ui/bausteine.dart';
import '../../core/utils/format.dart';
import '../board/board_providers.dart' show CapacityStatus;
import 'statistik_daten.dart';
import 'statistik_diagramme.dart' show SpannenBalken, grauFarbe;
import 'statistik_ueberblick_daten.dart';

// Der Kopf der Statistik-Seite: fünf Kennzahlen mit dem Vergleich zum
// Zeitraum davor, was Aufmerksamkeit braucht und wo es in den nächsten
// Werktagen eng wird — darunter die Wahl des Themas. Dazu der Bereich
// „Plan gegen Ist" im Thema Plan & Ist.

/// Ab dieser Breite stehen Hinweise und Vorschau nebeneinander.
const double _nebeneinanderAb = 1100;

Color _ampelFarbe(BuildContext context, Ampel ampel) {
  final f = AppFarben.von(context);
  return switch (ampel) {
    Ampel.gut => f.ok,
    Ampel.warnung => f.warnung,
    Ampel.kritisch => f.fehler,
    Ampel.neutral => grauFarbe(context),
  };
}

String _prozent(double anteil, {int nachkomma = 0}) =>
    Format.prozent(anteil, nachkomma: nachkomma);

/// „▲ 6 Punkte", „▼ 1,2 Punkte", „■ gleich".
String differenzText(double d) {
  final punkte = (d * 100).abs();
  if (punkte < 0.5) return '■ gleich zum Zeitraum davor';
  final zahl = punkte < 10
      ? punkte.toStringAsFixed(1).replaceAll('.', ',')
      : punkte.round().toString();
  return '${d > 0 ? '▲' : '▼'} $zahl Punkte zum Zeitraum davor';
}

/// Überblick: Kennzahlen, Hinweise, Vorschau.
class StatistikUeberblick extends StatelessWidget {
  const StatistikUeberblick({
    super.key,
    required this.auswertung,
    required this.vorher,
    required this.onThema,
    required this.onHinweis,
    required this.onTag,
  });

  final UeberblickAuswertung auswertung;

  /// Der Zeitraum davor — null: kein Vergleich („Alles").
  final StatistikSpanne? vorher;

  final ValueChanged<StatistikThema> onThema;
  final ValueChanged<StatistikHinweis> onHinweis;
  final ValueChanged<DateTime> onTag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final v = vorher;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Text(
                'Wie läuft es?',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                v == null
                    ? 'ohne Vergleich zum Zeitraum davor'
                    : 'verglichen mit ${v.beschreibung}',
                style: theme.textTheme.bodySmall?.copyWith(color: grau),
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, c) {
            final spalten = c.maxWidth >= 1100
                ? 5
                : c.maxWidth >= 700
                    ? 3
                    : 2;
            const abstand = 12.0;
            final breite = (c.maxWidth - abstand * (spalten - 1)) / spalten;
            return Wrap(
              spacing: abstand,
              runSpacing: abstand,
              children: [
                for (final k in auswertung.kennzahlen)
                  SizedBox(
                    width: breite,
                    child: _KennzahlKachel(
                      kennzahl: k,
                      onTap: () => onThema(k.thema),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, c) {
            final hinweise = _HinweisKarte(
              hinweise: auswertung.hinweise,
              onHinweis: onHinweis,
            );
            final vorschau = _VorschauKarte(
              vorschau: auswertung.vorschau,
              onTag: onTag,
            );
            if (c.maxWidth >= _nebeneinanderAb) {
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 5, child: hinweise),
                    const SizedBox(width: 14),
                    Expanded(flex: 7, child: vorschau),
                  ],
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [hinweise, const SizedBox(height: 14), vorschau],
            );
          },
        ),
      ],
    );
  }
}

/// Eine Fläche wie die Bereiche der Seite.
class _Karte extends StatelessWidget {
  const _Karte({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final f = Theme.of(context).colorScheme;
    return Material(
      color: f.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: f.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: child,
        ),
      ),
    );
  }
}

class _KennzahlKachel extends StatelessWidget {
  const _KennzahlKachel({required this.kennzahl, required this.onTap});

  final UeberblickKennzahl kennzahl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = AppFarben.von(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final k = kennzahl;
    final w = k.wert;
    final d = k.differenz;
    // Schlechter geworden: in der Farbe der Warnung. Bei der Auslastung
    // gibt es kein besser oder schlechter.
    final schlechter = d != null && k.hoeherIstBesser && d * 100 <= -0.5;
    return _Karte(
      key: ValueKey('kennzahl-${k.name}'),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  k.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(color: grau),
                ),
              ),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _ampelFarbe(context, k.ampel),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            w == null
                ? '–'
                : _prozent(w, nachkomma: k.name == 'Ø Ausbeute' ? 1 : 0),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            w == null
                ? 'keine Daten im Zeitraum'
                : d == null
                    ? 'kein Vergleich'
                    : differenzText(d),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: schlechter ? f.warnung : grau,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 26,
            width: double.infinity,
            child: CustomPaint(
              painter: _Verlaufslinie(
                werte: k.verlauf,
                farbe: theme.colorScheme.primary,
              ),
            ),
          ),
          if (k.ziel != null) ...[
            const SizedBox(height: 4),
            Text(
              k.ziel!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: grau),
            ),
          ],
        ],
      ),
    );
  }
}

/// Eine kleine Linie über die Abschnitte — Lücken bleiben Lücken.
class _Verlaufslinie extends CustomPainter {
  _Verlaufslinie({required this.werte, required this.farbe});

  final List<double?> werte;
  final Color farbe;

  @override
  void paint(Canvas canvas, Size size) {
    final da = [
      for (final w in werte)
        if (w != null) w,
    ];
    if (da.length < 2 || werte.length < 2) return;
    var lo = da.reduce(math.min);
    var hi = da.reduce(math.max);
    if (hi - lo < 0.02) {
      lo -= 0.01;
      hi += 0.01;
    }
    final stift = Paint()
      ..color = farbe
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final pfad = Path();
    var offen = false;
    for (var i = 0; i < werte.length; i++) {
      final w = werte[i];
      if (w == null) {
        offen = false;
        continue;
      }
      final x = size.width * i / (werte.length - 1);
      final y = size.height - 2 - (w - lo) / (hi - lo) * (size.height - 4);
      if (offen) {
        pfad.lineTo(x, y);
      } else {
        pfad.moveTo(x, y);
        offen = true;
      }
    }
    canvas.drawPath(pfad, stift);
  }

  @override
  bool shouldRepaint(_Verlaufslinie alt) =>
      alt.farbe != farbe || !_gleich(alt.werte, werte);

  static bool _gleich(List<double?> a, List<double?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _KartenTitel extends StatelessWidget {
  const _KartenTitel(this.text, {this.zusatz});

  final String text;
  final String? zusatz;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stil = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(text.toUpperCase(), style: stil)),
          if (zusatz != null)
            Flexible(
              child: Text(
                zusatz!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HinweisKarte extends StatelessWidget {
  const _HinweisKarte({required this.hinweise, required this.onHinweis});

  final List<StatistikHinweis> hinweise;
  final ValueChanged<StatistikHinweis> onHinweis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = AppFarben.von(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    return _Karte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _KartenTitel('Braucht Aufmerksamkeit'),
          if (hinweise.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, color: f.ok, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Gerade nichts Auffälliges.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          for (final h in hinweise)
            InkWell(
              key: ValueKey('hinweis-${h.text}'),
              borderRadius: BorderRadius.circular(8),
              onTap: () => onHinweis(h),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: switch (h.schwere) {
                              HinweisSchwere.kritisch => f.fehler,
                              HinweisSchwere.warnung => f.warnung,
                              HinweisSchwere.info => f.info,
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              h.text,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              h.unter,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: grau),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: grau, size: 20),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _VorschauKarte extends StatelessWidget {
  const _VorschauKarte({required this.vorschau, required this.onTag});

  final VorschauAuswertung vorschau;
  final ValueChanged<DateTime> onTag;

  static const double _name = 140;
  static const double _zelle = 46;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = AppFarben.von(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final v = vorschau;

    Color farbe(VorschauZelle c) => switch (c.status) {
          CapacityStatus.ueberbucht => f.warnung,
          CapacityStatus.gut => f.ok,
          CapacityStatus.frei => c.leer
              ? theme.colorScheme.surfaceContainerHighest
              : grauFarbe(context).withValues(alpha: 0.45),
        };

    Widget legende(Color c, String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: c,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 6),
            Text(text, style: theme.textTheme.bodySmall),
          ],
        );

    return _Karte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _KartenTitel(
            'Wo wird es eng?',
            zusatz: 'die nächsten 10 Werktage',
          ),
          if (v.leer)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Für die nächsten Werktage ist noch nichts geplant.',
                style: theme.textTheme.bodyMedium?.copyWith(color: grau),
              ),
            )
          else ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const SizedBox(width: _name),
                      for (final t in v.tage)
                        SizedBox(
                          width: _zelle,
                          child: Text(
                            '${tagText(t).substring(0, 2)}\n'
                            '${t.day}.${t.month}.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: grau, height: 1.2),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  for (final z in v.zeilen)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: _name,
                            child: Text(
                              z.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          for (final c in z.zellen)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              child: Tooltip(
                                message: c.leer
                                    ? '${tagText(c.tag)}: nichts geplant'
                                    : '${tagText(c.tag)}: '
                                        '${_prozent(c.auslastung)} belegt',
                                child: InkWell(
                                  onTap: () => onTag(c.tag),
                                  borderRadius: BorderRadius.circular(4),
                                  child: Container(
                                    width: _zelle - 4,
                                    height: 28,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: farbe(c),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: c.status == CapacityStatus.ueberbucht
                                        ? Text(
                                            c.auslastung >= 9.99
                                                ? '!'
                                                : '${(c.auslastung * 100).round()}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.black,
                                            ),
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                legende(
                  grauFarbe(context).withValues(alpha: 0.45),
                  'unter 75 %',
                ),
                legende(f.ok, '75–100 %'),
                legende(f.warnung, 'über 100 % (Zahl = Belegung)'),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Die vollste Anlage einer Abteilung zählt. Ein Klick öffnet '
              'das Board an diesem Tag.',
              style: theme.textTheme.bodySmall?.copyWith(color: grau),
            ),
          ],
        ],
      ),
    );
  }
}

/// Die Wahl des Themas unter dem Überblick.
class ThemenWahl extends StatelessWidget {
  const ThemenWahl({
    super.key,
    required this.thema,
    required this.onThema,
  });

  final StatistikThema thema;
  final ValueChanged<StatistikThema> onThema;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Themen',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<StatistikThema>(
            segments: [
              for (final t in StatistikThema.values)
                ButtonSegment(
                  value: t,
                  label: Text(t.label, key: ValueKey('thema-${t.name}')),
                ),
            ],
            selected: {thema},
            showSelectedIcon: false,
            onSelectionChanged: (auswahl) => onThema(auswahl.first),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Plan gegen Ist
// ---------------------------------------------------------------------------

/// Wie gut der Plan gestimmt hat: Rohware und Dauer der erfassten
/// Produktionen gegen ihre Karten im Board.
class PlanIstBereich extends StatelessWidget {
  const PlanIstBereich({
    super.key,
    required this.auswertung,
    required this.onArtikel,
  });

  final PlanIstAuswertung auswertung;
  final ValueChanged<StatistikArtikel> onArtikel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = AppFarben.von(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final a = auswertung;
    const titel = 'Plan gegen Ist';
    const untertitel = 'Planung und erfasste Produktionen';

    if (a.leer) {
      return Bereich(
        titel: titel,
        untertitel: untertitel,
        child: LeerHinweis(
          a.produktionen == 0
              ? 'Im Zeitraum gibt es keine erfasste Produktion für einen '
                  'Vergleich mit dem Plan.'
              : 'Keine erfasste Produktion ließ sich einer Karte mit Menge '
                  'oder Dauer zuordnen.',
          icon: Icons.compare_arrows,
        ),
      );
    }

    String band(int imBand, int von) => '$imBand von $von im Band';

    Widget abweichung(double? d, double grenze) {
      if (d == null) {
        return Text('–', style: theme.textTheme.bodyMedium);
      }
      final aus = d.abs() > grenze;
      return Text(
        '${d > 0 ? '+' : d < 0 ? '−' : ''}${_prozent(d.abs())}',
        textAlign: TextAlign.right,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: aus ? FontWeight.w700 : null,
          color: aus ? f.warnung : null,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
    }

    final liste = a.abweichungen;
    return Bereich(
      titel: titel,
      untertitel: untertitel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 32,
            runSpacing: 12,
            children: [
              Kennzahl(
                wert: a.mengentreue == null ? '–' : _prozent(a.mengentreue!),
                label: 'Mengentreue · ${band(a.mengeImBand, a.mengePaare)} '
                    '(±${_prozent(kMengenBand)})',
              ),
              Kennzahl(
                wert: a.zeittreue == null ? '–' : _prozent(a.zeittreue!),
                label: 'Zeittreue Bratstraße · '
                    '${band(a.zeitImBand, a.zeitPaare)} '
                    '(±${_prozent(kZeitBand)})',
              ),
              Kennzahl(
                wert: '${a.ungeplant}',
                label: a.ungeplant == 1
                    ? 'Produktion ohne Karte am selben Tag'
                    : 'Produktionen ohne Karte am selben Tag',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            liste.isEmpty
                ? 'Alle zugeordneten Produktionen liegen im Band.'
                : 'Größte Abweichungen',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: grau,
            ),
          ),
          if (liste.isNotEmpty) ...[
            const SizedBox(height: 6),
            // Schmaler als 640: seitlich scrollen. Eine feste Breite, damit
            // die Artikelspalte (Expanded) eine Grenze hat.
            LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: math.max(box.maxWidth, 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _PlanIstZeile(
                        kopf: true,
                        tag: 'Tag',
                        artikel: 'Artikel',
                        menge: Text(
                          'Rohware Ist / Plan',
                          textAlign: TextAlign.right,
                          style:
                              theme.textTheme.bodySmall?.copyWith(color: grau),
                        ),
                        zeit: Text(
                          'Dauer Ist / Plan',
                          textAlign: TextAlign.right,
                          style:
                              theme.textTheme.bodySmall?.copyWith(color: grau),
                        ),
                      ),
                      for (final p in liste)
                        _PlanIstZeile(
                          tag: tagText(p.datum),
                          artikel: '${p.artikel.artikelnummer} · '
                              '${p.artikel.bezeichnung}',
                          onTap: () => onArtikel(p.artikel),
                          menge: abweichung(p.mengeAbweichung, kMengenBand),
                          zeit: abweichung(p.zeitAbweichung, kZeitBand),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'Zugeordnet über Artikel und Tag wie die Planerfüllung. Rohware '
            'gegen die erste Karte der Kette, Dauer gegen die Karte der '
            'Bratstraße — dort wird die Zeit gemessen.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: grau,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanIstZeile extends StatelessWidget {
  const _PlanIstZeile({
    required this.tag,
    required this.artikel,
    required this.menge,
    required this.zeit,
    this.onTap,
    this.kopf = false,
  });

  final String tag;
  final String artikel;
  final Widget menge;
  final Widget zeit;
  final VoidCallback? onTap;
  final bool kopf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stil = kopf
        ? theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant)
        : theme.textTheme.bodyMedium;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            SizedBox(width: 90, child: Text(tag, style: stil)),
            Expanded(
              child: Text(
                artikel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: stil,
              ),
            ),
            SizedBox(width: 150, child: menge),
            SizedBox(width: 150, child: zeit),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Nachlauf bis zur Verpackung
// ---------------------------------------------------------------------------

/// „35 min", „1:20 h".
String _minutenText(double m) {
  final g = m.round();
  if (g < 60) return '$g min';
  return '${g ~/ 60}:${(g % 60).toString().padLeft(2, '0')} h';
}

/// Wie lange die Ware nach dem Auflegen bis zum Ende der Verpackung
/// braucht — je Artikel. Beim letzten Artikel des Tages ist das die Zeit,
/// in der die Anlage steht, bevor gereinigt werden kann.
class NachlaufBereich extends StatelessWidget {
  const NachlaufBereich({
    super.key,
    required this.auswertung,
    required this.onArtikel,
  });

  final NachlaufAuswertung auswertung;
  final ValueChanged<StatistikArtikel> onArtikel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final a = auswertung;
    const titel = 'Nachlauf bis Verpackung';
    const untertitel = 'Ende Auflegen bis Ende VPK · erfasste Produktionen';

    if (a.leer) {
      return const Bereich(
        titel: titel,
        untertitel: untertitel,
        child: LeerHinweis(
          'Noch keine Produktion mit „Ende Auflegen" und „Ende VPK" '
          'erfasst. Die Handy-App erfasst beides — mit der Zeit steht hier, '
          'wie lange jeder Artikel nachläuft.',
          icon: Icons.hourglass_empty,
        ),
      );
    }

    final skala = a.artikel.fold(
      a.median ?? 1,
      (m, x) => math.max(m, x.max),
    );
    return Bereich(
      titel: titel,
      untertitel: untertitel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 32,
            runSpacing: 12,
            children: [
              Kennzahl(
                wert: _minutenText(a.median!),
                label: 'typischer Nachlauf (Median)',
              ),
              Kennzahl(
                wert: '${a.mitNachlauf} von ${a.produktionen}',
                label: 'Produktionen mit beiden Uhrzeiten',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            a.artikel.isEmpty
                ? 'Je Artikel ab $kNachlaufAbProduktionen Produktionen mit '
                    'Nachlauf — noch keiner.'
                : 'Je Artikel · längster zuerst',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: grau,
            ),
          ),
          const SizedBox(height: 6),
          for (final n in a.artikel)
            InkWell(
              onTap: () => onArtikel(n.artikel),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Text(
                        '${n.artikel.artikelnummer} · '
                        '${n.artikel.bezeichnung}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 4,
                      child: SpannenBalken(
                        von: n.min,
                        mitte: n.median,
                        bis: n.max,
                        achseVon: 0,
                        achseBis: skala,
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 140,
                      child: Text(
                        '${_minutenText(n.median)} · ${n.anzahl}×',
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),
          Text(
            'Punkt = typischer Wert, Balken = kürzester bis längster. '
            'Beim letzten Artikel des Tages steht die Anlage so lange, bevor '
            'gereinigt werden kann. Mitten am Tag kann der Wert länger sein, '
            'wenn sich die Verpackung staut.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: grau,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
