import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_stil.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/format.dart';
import '../daten/entwicklung_repository.dart';
import 'projekt_modell.dart';
import 'projekt_repository.dart';
import 'projekt_verlauf.dart';

// Der Verlauf als Zeitstrahl — wie in der Development-Suite: eine Achse,
// die Einträge vom ältesten links zum neuesten rechts gleichmäßig
// verteilt, abwechselnd oben und unten an kurzen und langen Stielen,
// damit sich die Beschriftungen nicht überdecken. Jede Art hat ihre
// Farbe und ihr Symbol; darüberfahren zeigt das Wichtigste, antippen
// öffnet den Eintrag.

/// Die Farbe einer Eintragsart auf dem Zeitstrahl.
Color eintragFarbe(BuildContext context, EintragArt art) {
  final dunkel = Theme.of(context).brightness == Brightness.dark;
  return switch (art) {
    EintragArt.meilenstein => Theme.of(context).colorScheme.primary,
    EintragArt.rezeptur =>
      dunkel ? const Color(0xFFB794E6) : const Color(0xFF7E3FB8),
    EintragArt.email =>
      dunkel ? const Color(0xFFF0B04F) : const Color(0xFFC77700),
    EintragArt.datei =>
      dunkel ? const Color(0xFF6FA8F0) : const Color(0xFF2F6FD0),
    EintragArt.parameter =>
      dunkel ? const Color(0xFF4FC3B5) : const Color(0xFF0F7A6E),
    EintragArt.notiz =>
      dunkel ? const Color(0xFF9AA4B2) : const Color(0xFF5B6675),
  };
}

/// Schrift- und Symbolfarbe auf [hinten] — hell oder dunkel, je nachdem,
/// was sich besser abhebt.
Color _auf(Color hinten) =>
    ThemeData.estimateBrightnessForColor(hinten) == Brightness.dark
        ? Colors.white
        : const Color(0xFF1B1B1B);

/// Ältester zuerst; bei gleichem Datum der früher angelegte.
List<ProjektEintrag> zeitlichSortiert(Iterable<ProjektEintrag> eintraege) =>
    [...eintraege]..sort((a, b) {
        final d = a.datum.compareTo(b.datum);
        return d != 0 ? d : a.createdAt.compareTo(b.createdAt);
      });

/// Wo ein Eintrag am Strahl hängt: oben oder unten, kurz oder lang — im
/// Takt von vier, damit Nachbarn sich nicht in die Quere kommen.
({bool oben, bool lang}) zeitstrahlPlatz(int index) {
  final takt = index % 4;
  return (oben: takt == 0 || takt == 2, lang: takt == 2 || takt == 3);
}

/// Der Zeitstrahl eines Projekts.
class Zeitstrahl extends StatefulWidget {
  const Zeitstrahl({
    super.key,
    required this.eintraege,
    required this.onTippen,
    this.dateien = const {},
  });

  /// Die Einträge in beliebiger Reihenfolge.
  final List<ProjektEintrag> eintraege;

  /// Angehängte Dateien nach ID — für die Vorschau beim Darüberfahren.
  final Map<String, EntwicklungsDatei> dateien;

  final void Function(ProjektEintrag eintrag) onTippen;

  /// Mindestabstand zweier Einträge auf der Achse.
  static const double abstand = 120;
  static const double stielKurz = 40;
  static const double stielLang = 112;
  static const double symbol = 40;
  static const double beschriftung = 168;

  /// Platz über und unter der Achse: Stiel, Symbol, Beschriftung, Rand.
  static const double haelfte = stielLang + symbol + 6 + 76 + 8;
  static const double hoehe = 2 * haelfte;

  @override
  State<Zeitstrahl> createState() => _ZeitstrahlState();
}

class _ZeitstrahlState extends State<Zeitstrahl> {
  final _scroll = ScrollController();
  bool _ansEnde = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Einmal ans rechte Ende — das Neueste interessiert zuerst.
  void _zumNeuesten() {
    if (_ansEnde) return;
    _ansEnde = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  /// Das Mausrad scrollt hier waagrecht statt die Seite.
  void _rad(PointerSignalEvent ereignis) {
    if (ereignis is! PointerScrollEvent || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.maxScrollExtent <= 0) return;
    GestureBinding.instance.pointerSignalResolver.register(ereignis, (e) {
      final s = e as PointerScrollEvent;
      final weg = s.scrollDelta.dx != 0 ? s.scrollDelta.dx : s.scrollDelta.dy;
      _scroll.jumpTo(
        (position.pixels + weg).clamp(0, position.maxScrollExtent).toDouble(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final sortiert = zeitlichSortiert(widget.eintraege);
    if (sortiert.isEmpty) {
      return const LeerHinweis('Noch keine Einträge.', icon: Icons.timeline);
    }
    return LayoutBuilder(
      builder: (context, c) {
        final breite = math.max(
          c.maxWidth.isFinite ? c.maxWidth : 0.0,
          (sortiert.length + 1) * Zeitstrahl.abstand,
        );
        if (c.maxWidth.isFinite && breite > c.maxWidth) _zumNeuesten();
        return Listener(
          onPointerSignal: _rad,
          child: ScrollConfiguration(
            // Auch mit gedrückter Maustaste ziehen lässt sich der Strahl.
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
                PointerDeviceKind.stylus,
              },
            ),
            child: Scrollbar(
              controller: _scroll,
              thumbVisibility: breite > c.maxWidth,
              child: SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: breite,
                  height: Zeitstrahl.hoehe,
                  child: _Strahl(
                    eintraege: sortiert,
                    breite: breite,
                    dateien: widget.dateien,
                    onTippen: widget.onTippen,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Strahl extends StatelessWidget {
  const _Strahl({
    required this.eintraege,
    required this.breite,
    required this.dateien,
    required this.onTippen,
  });

  final List<ProjektEintrag> eintraege;
  final double breite;
  final Map<String, EntwicklungsDatei> dateien;
  final void Function(ProjektEintrag eintrag) onTippen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const mitte = Zeitstrahl.haelfte;
    final linie = theme.colorScheme.outlineVariant;
    final n = eintraege.length;
    final kinder = <Widget>[
      // Die Achse.
      Positioned(
        left: 0,
        right: 0,
        top: mitte - 3,
        height: 6,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: linie,
            borderRadius: AppMasse.ecken,
          ),
        ),
      ),
    ];
    for (var i = 0; i < n; i++) {
      final e = eintraege[i];
      final art = EintragArt.aus(e.art);
      final farbe = eintragFarbe(context, art);
      final platz = zeitstrahlPlatz(i);
      final stiel = platz.lang ? Zeitstrahl.stielLang : Zeitstrahl.stielKurz;
      final x = breite * (i + 1) / (n + 1);
      final meilenstein = art == EintragArt.meilenstein;
      kinder.addAll([
        // Der Stiel von der Achse zum Symbol.
        Positioned(
          left: x - 1,
          width: 2,
          top: platz.oben ? mitte - stiel : mitte,
          height: stiel,
          child: ColoredBox(color: linie),
        ),
        // Der Punkt auf der Achse.
        Positioned(
          left: x - 8,
          top: mitte - 8,
          width: 16,
          height: 16,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: meilenstein ? farbe : theme.colorScheme.outline,
              border: Border.all(color: theme.colorScheme.surface, width: 2),
            ),
          ),
        ),
        // Das Symbol am Ende des Stiels.
        Positioned(
          left: x - Zeitstrahl.symbol / 2,
          top: platz.oben
              ? mitte - stiel - Zeitstrahl.symbol
              : mitte + stiel,
          width: Zeitstrahl.symbol,
          height: Zeitstrahl.symbol,
          child: _Symbol(
            eintrag: e,
            art: art,
            farbe: farbe,
            datei: dateien[e.dateiId],
            onTippen: () => onTippen(e),
          ),
        ),
        // Titel und Datum — über dem Symbol oder darunter.
        Positioned(
          left: x - Zeitstrahl.beschriftung / 2,
          width: Zeitstrahl.beschriftung,
          top: platz.oben ? null : mitte + stiel + Zeitstrahl.symbol + 6,
          bottom: platz.oben
              ? Zeitstrahl.hoehe - (mitte - stiel - Zeitstrahl.symbol - 6)
              : null,
          child: Center(
            child: _Beschriftung(
              eintrag: e,
              meilenstein: meilenstein,
              onTippen: () => onTippen(e),
            ),
          ),
        ),
      ]);
    }
    return Stack(clipBehavior: Clip.none, children: kinder);
  }
}

class _Symbol extends StatelessWidget {
  const _Symbol({
    required this.eintrag,
    required this.art,
    required this.farbe,
    required this.datei,
    required this.onTippen,
  });

  final ProjektEintrag eintrag;
  final EintragArt art;
  final Color farbe;
  final EntwicklungsDatei? datei;
  final VoidCallback onTippen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = eintrag;
    final status = EintragStatus.aus(e.status);
    final beschreibung = (e.beschreibung ?? '').trim();
    final kurz = beschreibung.length > 240
        ? '${beschreibung.substring(0, 239)}…'
        : beschreibung;
    final kommentare = Kommentar.listeAus(e.kommentare).length;
    final d = datei;
    final kopf = [
      Format.datum(e.datum),
      if ((e.benutzer ?? '').trim().isNotEmpty) e.benutzer!.trim(),
      art.label,
      status.label,
    ].join(' · ');
    return Tooltip(
      waitDuration: const Duration(milliseconds: 300),
      richMessage: TextSpan(
        children: [
          TextSpan(
            text: e.titel,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: '\n$kopf'),
          if (kurz.isNotEmpty) TextSpan(text: '\n\n$kurz'),
          if (d != null) TextSpan(text: '\n\nDatei: ${d.name}'),
          if (kommentare > 0)
            TextSpan(
              text: '\n$kommentare '
                  '${kommentare == 1 ? 'Kommentar' : 'Kommentare'}',
            ),
          const TextSpan(
            text: '\n\nAntippen für alles Weitere',
            style: TextStyle(fontStyle: FontStyle.italic),
          ),
        ],
      ),
      child: Semantics(
        button: true,
        label: '${art.label}: ${e.titel}',
        child: Material(
          color: farbe,
          shape: CircleBorder(
            side: BorderSide(color: theme.colorScheme.surface, width: 3),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTippen,
            child: Center(child: Icon(art.icon, size: 20, color: _auf(farbe))),
          ),
        ),
      ),
    );
  }
}

class _Beschriftung extends StatelessWidget {
  const _Beschriftung({
    required this.eintrag,
    required this.meilenstein,
    required this.onTippen,
  });

  final ProjektEintrag eintrag;
  final bool meilenstein;
  final VoidCallback onTippen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = AppFarben.von(context);
    final e = eintrag;
    final hinten =
        meilenstein ? theme.colorScheme.primary : theme.colorScheme.surface;
    final schrift =
        meilenstein ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;
    final grau = meilenstein
        ? theme.colorScheme.onPrimary.withValues(alpha: 0.85)
        : theme.colorScheme.onSurfaceVariant;
    final offen = EintragStatus.aus(e.status) == EintragStatus.offen;
    return Material(
      color: hinten,
      shape: RoundedRectangleBorder(
        borderRadius: AppMasse.ecken,
        side: BorderSide(
          color: meilenstein ? hinten : theme.colorScheme.outlineVariant,
        ),
      ),
      child: InkWell(
        onTap: onTippen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                e.titel,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: schrift,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                Format.datum(e.datum),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: grau,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (offen)
                Text(
                  'offen',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: meilenstein ? schrift : f.warnung,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Öffnet einen Eintrag als Fenster — mit allem, was die Karte im
/// Verlauf kann: kommentieren, bearbeiten, löschen, Rezeptur oder Datei
/// öffnen. Das Fenster bleibt auf dem neuesten Stand.
Future<void> eintragZeigen(
  BuildContext context, {
  required String projektId,
  required String eintragId,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) =>
          _EintragFenster(projektId: projektId, eintragId: eintragId),
    );

class _EintragFenster extends ConsumerWidget {
  const _EintragFenster({required this.projektId, required this.eintragId});

  final String projektId;
  final String eintragId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liste =
        ref.watch(projektEintraegeProvider(projektId)).valueOrNull ?? const [];
    final e = liste.where((x) => x.id == eintragId).firstOrNull;
    final dateien = {
      for (final d in ref.watch(projektDateienProvider(projektId)).valueOrNull ??
          const <EntwicklungsDatei>[])
        d.id: d,
    };
    final versionen = {
      for (final v in ref.watch(alleVersionenProvider).valueOrNull ??
          const <RezepturVersion>[])
        v.id: v,
    };
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (e == null)
                const LeerHinweis(
                  'Dieser Eintrag ist nicht mehr da.',
                  icon: Icons.history,
                )
              else
                EintragKarte(
                  eintrag: e,
                  datei: dateien[e.dateiId],
                  version: versionen[e.versionId],
                ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Schließen'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
