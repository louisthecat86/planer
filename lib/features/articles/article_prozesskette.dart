part of 'article_detail_screen.dart';

// ---------------------------------------------------------------------------
// Prozesskette — der ganze Ablauf eines Artikels in einer Ansicht
// ---------------------------------------------------------------------------
//
// Früher gab es zwei Ansichten: ein Fließdiagramm (ziehbar, aber karg) und
// Karten (übersichtlich, aber starr). Jetzt eine: Die Stationen stehen
// untereinander an einer nummerierten Leiste, in jeder Station laufen die
// Anlagen von links nach rechts — so liest sich die Kette wie der Weg der
// Ware durch den Betrieb.
//
// Alles lässt sich ziehen:
// - eine Anlage an eine andere Stelle, auch in eine andere Station — dann
//   arbeitet sie bei diesem Artikel für deren Abteilung (der
//   Rollenschneider der Zerlegung an der Bratstraße). Im Katalog bleibt sie
//   in ihrer Stammabteilung.
// - eine Anlage zwischen zwei Stationen — dort wird sie zur eigenen Station
//   (neben einer Station derselben Abteilung gehört sie zu dieser).
// - eine ganze Station am Griff im Kopf.
// - eine Anlage aus dem Katalog an jede dieser Stellen.
//
// Was ein Zug auf einem Ziel bewirkt, rechnet prozesskette_umbau.dart aus;
// geschrieben wird über den ProzesskettenService. Er nummeriert die Schritte
// für die Excel-Spalten lückenlos und hält die Leistungsdaten bei ihrer
// Station.

/// Abteilung aus dem dbValue — null bei unbekanntem Wert, statt zu werfen.
Abteilung? _abteilungAus(String dbValue) {
  for (final a in Abteilung.values) {
    if (a.dbValue == dbValue) return a;
  }
  return null;
}

/// „1.250" — ganze Kilogramm mit Tausenderpunkt.
String _kgh(double kg) => kg.round().toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );

/// Führt einen Umbau aus der Ansicht heraus aus: Hinweise (Kette voll,
/// inzwischen geändert) kommen als Meldung, danach wird die Kette neu
/// geladen.
extension _UmbauAusfuehren on Kettenbau {
  Future<void> ausfuehren(BuildContext context, KettenUmbau? umbau) async {
    if (umbau == null) return;
    // Container und Messenger vor dem ersten await holen: Nach dem
    // Umbau steht die Ansicht neu — das auslösende Widget gibt es dann
    // womöglich nicht mehr.
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await schreibe(container.read(databaseProvider), umbau);
    } on StateError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    } on ArgumentError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('${e.message}')));
      container.invalidate(productStepsProvider(productId));
      return;
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Umbau fehlgeschlagen: $e')),
      );
      container.invalidate(productStepsProvider(productId));
      return;
    }
    container.read(autoBackupTriggerProvider).fireDebounced(
          reason: switch (umbau) {
            NeueAbfolge() => 'Prozesskette umgebaut',
            AnlageEinfuegen() => 'Anlage in den Prozess eingefügt',
          },
        );
    container.invalidate(productStepsProvider(productId));
  }
}

/// Die Prozesskette: Stationen untereinander, dazwischen Lücken zum
/// Ablegen.
class _Prozesskette extends StatelessWidget {
  const _Prozesskette({
    required this.bau,
    required this.maschinen,
    required this.historie,
    required this.onUpdated,
    required this.onLeistungsdaten,
  });

  final Kettenbau bau;

  /// Alle Anlagen des Katalogs nach ID — für Namen und Stammabteilung.
  final Map<String, Machine> maschinen;

  /// Ø der letzten Produktionen — Grundlage der Leistung ohne
  /// Leistungsdaten (und an der Bratstraße immer).
  final HistorienLeistung? historie;
  final VoidCallback onUpdated;

  /// Öffnet die Leistungsdaten der Station mit diesem Index.
  final void Function(int station) onLeistungsdaten;

  @override
  Widget build(BuildContext context) {
    final stationen = bau.stationen;
    if (stationen.isEmpty) return _LeereKette(bau: bau);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _Luecke(bau: bau, vorStation: 0),
        for (var k = 0; k < stationen.length; k++) ...[
          _Station(
            bau: bau,
            index: k,
            maschinen: maschinen,
            historie: historie,
            onUpdated: onUpdated,
            onLeistungsdaten: () => onLeistungsdaten(k),
          ),
          _Luecke(
            bau: bau,
            vorStation: k + 1,
            // Zwischen zwei Stationen läuft die Leiste weiter.
            leistenFarbe: k + 1 < stationen.length
                ? (_abteilungAus(stationen[k].first.abteilung)?.farbe ??
                    Colors.grey)
                : null,
          ),
        ],
      ],
    );
  }
}

/// Noch keine Schritte: eine große Fläche zum Ablegen aus dem Katalog.
class _LeereKette extends StatelessWidget {
  const _LeereKette({required this.bau});

  final Kettenbau bau;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const ziel = ZielLuecke(0);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: DragTarget<KettenZug>(
        onWillAcceptWithDetails: (d) => bau.umbau(d.data, ziel) != null,
        onAcceptWithDetails: (d) =>
            bau.ausfuehren(context, bau.umbau(d.data, ziel)),
        builder: (context, kandidaten, abgelehnt) {
          final aktiv = kandidaten.isNotEmpty;
          return Container(
            padding: const EdgeInsets.all(32),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: aktiv
                  ? theme.colorScheme.primary.withValues(alpha: 0.06)
                  : null,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: aktiv
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
                width: aktiv ? 2 : 1,
              ),
            ),
            child: Text(
              'Noch keine Produktionsschritte.\n\n'
              'Zieh ein Produktionsmittel aus dem Katalog hierher, tippe es '
              'an — oder importiere eine Excel-Vorlage.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          );
        },
      ),
    );
  }
}

/// Lücke vor einer Station (oder hinter der letzten). Unauffällig, solange
/// nichts gezogen wird; beim Darüberziehen öffnet sie sich.
class _Luecke extends StatelessWidget {
  const _Luecke({
    required this.bau,
    required this.vorStation,
    this.leistenFarbe,
  });

  final Kettenbau bau;
  final int vorStation;

  /// Farbe der Leiste, die hier zur nächsten Station weiterläuft — null:
  /// keine Leiste (vor der ersten und hinter der letzten Station).
  final Color? leistenFarbe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ziel = ZielLuecke(vorStation);
    final farbe = leistenFarbe;
    return DragTarget<KettenZug>(
      onWillAcceptWithDetails: (d) => bau.umbau(d.data, ziel) != null,
      onAcceptWithDetails: (d) =>
          bau.ausfuehren(context, bau.umbau(d.data, ziel)),
      builder: (context, kandidaten, abgelehnt) {
        final zug = kandidaten.firstOrNull;
        final aktiv = zug != null;
        // Groß genug, um sie beim Ziehen zu treffen; beim Darüberziehen
        // öffnet sie sich.
        final hoehe = aktiv ? 46.0 : (farbe == null ? 14.0 : 22.0);
        return SizedBox(
          height: hoehe,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 46,
                child: farbe == null
                    ? null
                    : Column(
                        children: [
                          Expanded(
                            child: Container(
                              width: 2.5,
                              color: farbe.withValues(alpha: 0.45),
                            ),
                          ),
                          Icon(
                            Icons.arrow_drop_down,
                            size: 18,
                            color: farbe.withValues(alpha: 0.8),
                          ),
                        ],
                      ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: aktiv
                    ? Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary
                              .withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: theme.colorScheme.primary,
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          zug is StationsZug
                              ? 'Station hierher verschieben'
                              : 'Hier einfügen',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Eine Station: Nummer an der Leiste, Kopf mit Personen und Leistung,
/// darunter die Anlagen von links nach rechts.
class _Station extends StatelessWidget {
  const _Station({
    required this.bau,
    required this.index,
    required this.maschinen,
    required this.historie,
    required this.onUpdated,
    required this.onLeistungsdaten,
  });

  final Kettenbau bau;
  final int index;
  final Map<String, Machine> maschinen;
  final HistorienLeistung? historie;
  final VoidCallback onUpdated;
  final VoidCallback onLeistungsdaten;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final station = bau.stationen[index];
    final abt = _abteilungAus(station.first.abteilung);
    final farbe = abt?.farbe ?? Colors.grey;
    final ziel = ZielStation(index);
    final istLetzte = index == bau.stationen.length - 1;

    return DragTarget<KettenZug>(
      onWillAcceptWithDetails: (d) => bau.umbau(d.data, ziel) != null,
      onAcceptWithDetails: (d) =>
          bau.ausfuehren(context, bau.umbau(d.data, ziel)),
      builder: (context, kandidaten, abgelehnt) {
        final istZiel = kandidaten.isNotEmpty;
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Leiste: Nummer der Station, darunter die Linie zur nächsten.
              SizedBox(
                width: 46,
                child: Column(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: farbe,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color:
                              Colors.white.withValues(alpha: dark ? 0.25 : 0.6),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: farbe.withValues(alpha: 0.45),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (!istLetzte)
                      Expanded(
                        child: Container(
                          width: 2.5,
                          color: farbe.withValues(alpha: 0.45),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: const EdgeInsets.fromLTRB(12, 10, 10, 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        farbe.withValues(alpha: dark ? 0.14 : 0.08),
                        farbe.withValues(alpha: dark ? 0.04 : 0.02),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: istZiel
                          ? theme.colorScheme.primary
                          : farbe.withValues(alpha: 0.5),
                      width: istZiel ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _StationsKopf(
                        index: index,
                        station: station,
                        abteilung: abt,
                        farbe: farbe,
                        historie: historie,
                        onLeistungsdaten: onLeistungsdaten,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 4,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (var i = 0; i < station.length; i++) ...[
                            _AnlagenKachel(
                              bau: bau,
                              step: station[i],
                              station: index,
                              farbe: farbe,
                              maschine: maschinen[station[i].maschineId],
                              onUpdated: onUpdated,
                            ),
                            Icon(
                              i < station.length - 1
                                  ? Icons.arrow_forward_rounded
                                  : Icons.more_horiz_rounded,
                              size: 18,
                              color: farbe.withValues(
                                alpha: i < station.length - 1 ? 0.75 : 0.35,
                              ),
                            ),
                          ],
                          _PlusAnlage(
                            bau: bau,
                            station: index,
                            abteilung: abt,
                            farbe: farbe,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Kopf einer Station: Abteilung, Griff zum Verschieben, darunter Personen
/// und Leistung.
class _StationsKopf extends StatelessWidget {
  const _StationsKopf({
    required this.index,
    required this.station,
    required this.abteilung,
    required this.farbe,
    required this.historie,
    required this.onLeistungsdaten,
  });

  final int index;
  final List<ProductStep> station;
  final Abteilung? abteilung;
  final Color farbe;
  final HistorienLeistung? historie;
  final VoidCallback onLeistungsdaten;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = abteilung?.anzeigeName ?? station.first.abteilung;
    // Personalbedarf der Station = Summe über ihre Anlagen. Gepflegt wird
    // die Zahl je Anlage; hier steht nur das Ergebnis.
    final personen =
        station.fold<int>(0, (summe, s) => summe + s.basisMitarbeiter);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: farbe,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                abteilung?.kurzcode ?? '?',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            // Griff zum Verschieben der ganzen Station — ein eigener Griff
            // statt der ganzen Fläche, damit das Ziehen einzelner Anlagen
            // nicht kollidiert.
            Draggable<KettenZug>(
              data: StationsZug(index),
              dragAnchorStrategy: pointerDragAnchorStrategy,
              feedback: Material(
                color: Colors.transparent,
                child: Chip(
                  backgroundColor: farbe,
                  label: Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              child: Tooltip(
                message: 'Station ziehen, um sie zu verschieben',
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.drag_indicator,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (personen > 0)
              _Pille(
                text: personen == 1 ? '1 Person' : '$personen Personen',
                farbe: farbe,
              ),
            _LeistungChip(
              station: station,
              abteilung: abteilung,
              historie: historie,
              onTap: onLeistungsdaten,
            ),
          ],
        ),
      ],
    );
  }
}

/// Womit die Station ihre Dauer rechnet — nach denselben Regeln wie die
/// Planung: an der Bratstraße die erfassten Produktionen, sonst die
/// hinterlegten Leistungsdaten, ersatzweise die Produktionen. Antippen
/// öffnet die Leistungsdaten der Station.
class _LeistungChip extends StatelessWidget {
  const _LeistungChip({
    required this.station,
    required this.abteilung,
    required this.historie,
    required this.onTap,
  });

  final List<ProductStep> station;
  final Abteilung? abteilung;
  final HistorienLeistung? historie;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final l = leistungsdatenVon(station);
    final h = historie;
    final bratstrasse = abteilung == Abteilung.bratstrasse;

    const gruen = Color(0xFF2E7D32);
    const blau = Color(0xFF1565C0);
    const orange = Color(0xFFEF6C00);

    final (text, farbe, hinweis) = switch ((l, h)) {
      (_, final h?) when bratstrasse => (
          'Ø ${_kgh(h.kgProStunde)} kg/h · '
              '${h.anzahl == 1 ? '1 Produktion' : '${h.anzahl} Produktionen'}',
          blau,
          'Die Bratstraße rechnet mit den erfassten Produktionen: '
              '${h.kennzahlen}.',
        ),
      (final l?, _) => (
          '${_kgh(l.kgProStunde)} kg/h · hinterlegt',
          gruen,
          'Hinterlegt: ${_kgh(l.mengeKg)} kg in ${Zeit.kurz(l.minuten)}. '
              'Antippen zum Ändern.',
        ),
      (null, final h?) => (
          'Ø ${_kgh(h.kgProStunde)} kg/h · aus '
              '${h.anzahl == 1 ? '1 Produktion' : '${h.anzahl} Produktionen'}',
          blau,
          'Keine Leistungsdaten hinterlegt — gerechnet wird mit dem '
              '${h.herkunft}: ${h.kennzahlen}. Antippen zum Hinterlegen.',
        ),
      (null, null) => (
          'Leistung fehlt',
          orange,
          'Weder Leistungsdaten noch eine Produktion mit Zeit — die Dauer '
              'ist ein Platzhalter. Antippen zum Hinterlegen.',
        ),
    };
    final schrift = dark ? Color.lerp(farbe, Colors.white, 0.45)! : farbe;

    return Tooltip(
      message: hinweis,
      child: Material(
        color: farbe.withValues(alpha: 0.14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: farbe.withValues(alpha: 0.5)),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.speed, size: 13, color: schrift),
                const SizedBox(width: 4),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: schrift,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Eine Anlage in ihrer Station: zieh- und ablegbar, Antippen öffnet die
/// Details.
class _AnlagenKachel extends StatelessWidget {
  const _AnlagenKachel({
    required this.bau,
    required this.step,
    required this.station,
    required this.farbe,
    required this.maschine,
    required this.onUpdated,
  });

  final Kettenbau bau;
  final ProductStep step;
  final int station;
  final Color farbe;

  /// Die Anlage aus dem Katalog — null ohne Anlage oder wenn sie fehlt.
  final Machine? maschine;
  final VoidCallback onUpdated;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nummer = bau.indexVon(step.id) + 1;
    final ziel = ZielAnlage(step, station);
    final inhalt = _KachelInhalt(
      step: step,
      nummer: nummer,
      farbe: farbe,
      maschine: maschine,
      onTap: () => _zeigeSchrittDetail(
        context,
        productId: step.productId,
        stepId: step.id,
        fallback: step,
        nummer: nummer,
        onUpdated: onUpdated,
      ),
    );

    // Die gezogene Anlage über ihrem eigenen Platz: annehmen und nichts
    // tun. Sonst fiele der Zug auf die Station durch und schöbe die Anlage
    // ans Ende der Station.
    bool selbst(KettenZug zug) => zug is SchrittZug && zug.step.id == step.id;

    return DragTarget<KettenZug>(
      // Eine ganze Station nimmt die Station an, nicht die Kachel — sonst
      // zeigte die Kachel eine Einfügemarke für etwas, das gar nicht vor
      // ihr landet.
      onWillAcceptWithDetails: (d) =>
          d.data is! StationsZug &&
          (selbst(d.data) || bau.umbau(d.data, ziel) != null),
      onAcceptWithDetails: (d) =>
          bau.ausfuehren(context, bau.umbau(d.data, ziel)),
      builder: (context, kandidaten, abgelehnt) {
        // Einfügemarke links (davor) — rechts, wenn eine Anlage derselben
        // Station von links kommt: Sie landet dahinter.
        final zug = kandidaten.firstOrNull;
        final Border? marke;
        if (zug == null || selbst(zug)) {
          marke = null;
        } else {
          final dahinter = zug is SchrittZug &&
              bau.stationVon(zug.step.id) == station &&
              bau.indexVon(zug.step.id) < bau.indexVon(step.id);
          final linie =
              BorderSide(color: theme.colorScheme.primary, width: 4);
          marke = dahinter ? Border(right: linie) : Border(left: linie);
        }
        return Draggable<KettenZug>(
          data: SchrittZug(step),
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(opacity: 0.9, child: inhalt),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: inhalt),
          child: Container(
            foregroundDecoration:
                marke == null ? null : BoxDecoration(border: marke),
            child: inhalt,
          ),
        );
      },
    );
  }
}

/// Das Aussehen einer Anlagen-Kachel.
class _KachelInhalt extends ConsumerWidget {
  const _KachelInhalt({
    required this.step,
    required this.nummer,
    required this.farbe,
    required this.maschine,
    required this.onTap,
  });

  final ProductStep step;
  final int nummer;
  final Color farbe;
  final Machine? maschine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // Name: Katalog > Legacy-Text > Prozessschritt.
    final prozess = (step.prozessschritt ?? '').trim();
    final name = maschine?.name ??
        ((step.maschine ?? '').trim().isNotEmpty
            ? step.maschine!
            : (prozess.isNotEmpty ? prozess : 'Schritt $nummer'));

    // Arbeitet die Anlage bei diesem Artikel für eine andere Abteilung als
    // ihre Stammabteilung, steht diese an der Kachel.
    final stamm = maschine == null || maschine!.abteilung == step.abteilung
        ? null
        : _abteilungAus(maschine!.abteilung);

    // Pflegestand der Parameter als Ampel — auf einen Blick sichtbar, wo
    // noch Werte fehlen.
    final params = ref.watch(stepParametersProvider(step.id));
    final (gepflegt, gesamt) = params.maybeWhen(
      data: (liste) => (
        liste.where((p) => (p.wert ?? '').trim().isNotEmpty).length,
        liste.length,
      ),
      orElse: () => (0, 0),
    );

    return SizedBox(
      width: 210,
      child: Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: farbe.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$nummer',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                    ),
                    if (stamm != null)
                      Tooltip(
                        message: 'Anlage aus ${stamm.anzeigeName} — arbeitet '
                            'bei diesem Artikel hier mit',
                        child: Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: stamm.farbe.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: stamm.farbe.withValues(alpha: 0.6),
                            ),
                          ),
                          child: Text(
                            'aus ${stamm.kurzcode}',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (prozess.isNotEmpty && prozess != name) ...[
                  const SizedBox(height: 4),
                  Text(
                    prozess,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 7),
                Row(
                  children: [
                    if (step.basisMitarbeiter > 0) ...[
                      Icon(
                        Icons.groups_outlined,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${step.basisMitarbeiter}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (gesamt > 0)
                      _Pille(
                        text: '$gepflegt/$gesamt Werte',
                        farbe: gepflegt == gesamt
                            ? Colors.green
                            : (gepflegt == 0
                                ? Colors.redAccent
                                : Colors.orange),
                      ),
                    const Spacer(),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// „+ Anlage" am Ende einer Station: wählt eine Anlage aus dem Katalog —
/// auch aus einer anderen Abteilung — und hängt sie an die Station an.
class _PlusAnlage extends StatelessWidget {
  const _PlusAnlage({
    required this.bau,
    required this.station,
    required this.abteilung,
    required this.farbe,
  });

  final Kettenbau bau;
  final int station;
  final Abteilung? abteilung;
  final Color farbe;

  Future<void> _waehlen(BuildContext context) async {
    final dbValue = bau.stationen[station].first.abteilung;
    final container = ProviderScope.containerOf(context, listen: false);
    final wahl = await showDialog<({Machine? maschine})>(
      context: context,
      builder: (_) => UncontrolledProviderScope(
        container: container,
        child: _AnlagenWahl(abteilung: dbValue),
      ),
    );
    if (wahl == null || !context.mounted) return;
    final index = bau.grenzeVor(station + 1);
    final maschine = wahl.maschine;
    if (maschine != null) {
      await bau.ausfuehren(
        context,
        AnlageEinfuegen(index: index, abteilung: dbValue, maschine: maschine),
      );
      return;
    }
    // Ein Schritt ohne Anlage — nur mit Prozessschritt, etwa „Abkühlen".
    final ok = await StepEditorDialog.show(
      context,
      productId: bau.productId,
      startAbteilung: dbValue,
      einfuegenAn: index,
      stepNumber: index + 1,
    );
    if (ok) container.invalidate(productStepsProvider(bau.productId));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: 'Anlage an ${abteilung?.anzeigeName ?? 'diese Station'} '
          'anhängen',
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: BorderSide(color: farbe.withValues(alpha: 0.45)),
        ),
        child: InkWell(
          onTap: () => _waehlen(context),
          borderRadius: BorderRadius.circular(11),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Text(
                  'Anlage',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Auswahl einer Anlage für eine Station: zuerst die der eigenen
/// Abteilung, darunter alle anderen — eine Anlage darf bei einem Artikel
/// auch für eine fremde Abteilung arbeiten. Ganz unten ein Schritt ohne
/// Anlage. Liefert null bei Abbruch, sonst die Wahl (Anlage oder keine).
class _AnlagenWahl extends ConsumerStatefulWidget {
  const _AnlagenWahl({required this.abteilung});

  /// dbValue der Station.
  final String abteilung;

  @override
  ConsumerState<_AnlagenWahl> createState() => _AnlagenWahlState();
}

class _AnlagenWahlState extends ConsumerState<_AnlagenWahl> {
  bool _andere = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eigene = _abteilungAus(widget.abteilung);
    final maschinen =
        ref.watch(alleMaschinenProvider).valueOrNull ?? const <Machine>[];
    final passend =
        maschinen.where((m) => m.abteilung == widget.abteilung).toList();
    final fremde =
        maschinen.where((m) => m.abteilung != widget.abteilung).toList()
          ..sort((a, b) {
            final ia = _abteilungAus(a.abteilung)?.index ?? 99;
            final ib = _abteilungAus(b.abteilung)?.index ?? 99;
            if (ia != ib) return ia.compareTo(ib);
            return a.name.compareTo(b.name);
          });

    Widget zeile(Machine m) {
      final abt = _abteilungAus(m.abteilung);
      return ListTile(
        dense: true,
        leading: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: abt?.farbe ?? theme.colorScheme.outline,
            shape: BoxShape.circle,
          ),
        ),
        title: Text(m.name),
        subtitle: m.abteilung == widget.abteilung
            ? null
            : Text(abt?.anzeigeName ?? m.abteilung),
        onTap: () =>
            Navigator.of(context).pop<({Machine? maschine})>((maschine: m)),
      );
    }

    return AlertDialog(
      title: Text('Anlage für ${eigene?.anzeigeName ?? widget.abteilung}'),
      contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      content: SizedBox(
        width: 420,
        height: 440,
        child: ListView(
          children: [
            if (passend.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Für diese Abteilung sind keine Anlagen angelegt.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            for (final m in passend) zeile(m),
            const Divider(),
            ListTile(
              dense: true,
              leading: Icon(
                _andere ? Icons.expand_less : Icons.expand_more,
              ),
              title: const Text('Anlage aus einer anderen Abteilung'),
              subtitle: const Text(
                'Sie bleibt im Katalog ihrer Abteilung und arbeitet bei '
                'diesem Artikel hier mit.',
              ),
              onTap: () => setState(() => _andere = !_andere),
            ),
            if (_andere) for (final m in fremde) zeile(m),
            const Divider(),
            ListTile(
              dense: true,
              leading: const Icon(Icons.edit_note),
              title: const Text('Schritt ohne Anlage …'),
              subtitle: const Text('Nur ein Prozessschritt, etwa „Abkühlen"'),
              onTap: () => Navigator.of(context)
                  .pop<({Machine? maschine})>((maschine: null)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
      ],
    );
  }
}

/// Öffnet die volle Detailansicht eines Prozessschritts als Bottom-Sheet.
void _zeigeSchrittDetail(
  BuildContext context, {
  required String productId,
  required String stepId,
  required ProductStep fallback,
  required int nummer,
  required VoidCallback onUpdated,
}) {
  final container = ProviderScope.containerOf(context);
  showSheetOhneAnimation<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 820),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => UncontrolledProviderScope(
      container: container,
      child: _SchrittDetailSheet(
        productId: productId,
        stepId: stepId,
        fallback: fallback,
        nummer: nummer,
        onUpdated: onUpdated,
      ),
    ),
  );
}

/// Inhalt des Schritt-Detail-Sheets — zeigt den Maschinen-Block
/// (Personen, Plattenschema, Parameter) und bleibt durch das Watching des
/// Steps-Providers auch nach Bearbeitungen aktuell.
class _SchrittDetailSheet extends ConsumerWidget {
  const _SchrittDetailSheet({
    required this.productId,
    required this.stepId,
    required this.fallback,
    required this.nummer,
    required this.onUpdated,
  });

  final String productId;
  final String stepId;
  final ProductStep fallback;
  final int nummer;
  final VoidCallback onUpdated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final steps = ref.watch(productStepsProvider(productId)).valueOrNull;
    final aktuell =
        steps?.where((s) => s.id == stepId).firstOrNull ?? fallback;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: _MaschinenBlock(
          step: aktuell,
          stepNumber: nummer,
          onUpdated: onUpdated,
        ),
      ),
    );
  }
}
