import 'package:flutter/material.dart';

import '../../../core/constants/abteilungen.dart';
import '../../../core/theme/app_stil.dart';
import '../../../core/ui/bausteine.dart';
import 'kette_bausteine.dart';
import 'prozess_kette.dart';
import 'prozess_modell.dart';

// Die Prozesskette eines Projekts — so, wie der Artikel seine zeigt
// (articles/article_prozesskette.dart): Die Stationen stehen untereinander
// an einer nummerierten Leiste, in jeder laufen die Anlagen von links nach
// rechts. Ohne Personen und Leistungsdaten — die bekommt der Artikel (F33).
//
// Alles lässt sich ziehen: eine Anlage an eine andere Stelle, auch in eine
// andere Station (dann arbeitet sie dort für deren Abteilung) oder in eine
// Lücke zwischen zwei Stationen (dort wird sie zur eigenen Station); eine
// ganze Station am Griff im Kopf. Was ein Zug bewirkt, rechnet ProjektKette
// aus; die Ansicht meldet nur die neue Kette.

/// Breite der Leiste links mit den Nummern der Stationen — wie im Artikel.
const double _leisteBreite = 46;

/// Die Kette eines Projekts mit allem, was sich an ihr ändern lässt.
class ProzessKetteAnsicht extends StatelessWidget {
  const ProzessKetteAnsicht({
    super.key,
    required this.schritte,
    required this.katalog,
    required this.onKette,
    required this.onOeffnen,
    this.katalogGeladen = true,
  });

  final List<ProzessSchritt> schritte;

  /// Die Anlagen der Planung — für Namen, Stammabteilung und Steckbrief.
  final List<KatalogAnlage> katalog;

  /// Ist der Katalog schon da? Vorher zeigen die Kacheln weder, wie viele
  /// Werte eingetragen sind, noch dass eine Anlage im Katalog fehlt.
  final bool katalogGeladen;

  /// Meldet die neue Kette — nach Ziehen, Hinzufügen oder einer neuen
  /// Abteilung einer Station.
  final ValueChanged<List<ProzessSchritt>> onKette;

  /// Öffnet einen Schritt mit seinen Werten.
  final ValueChanged<ProzessSchritt> onOeffnen;

  @override
  Widget build(BuildContext context) {
    final kette = ProjektKette(schritte);
    final anlagen = {for (final a in katalog) a.id: a};
    final stationen = kette.stationen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Luecke(kette: kette, vorStation: 0, onKette: onKette),
        for (var k = 0; k < stationen.length; k++) ...[
          _Station(
            kette: kette,
            index: k,
            anlagen: anlagen,
            katalog: katalog,
            katalogGeladen: katalogGeladen,
            onKette: onKette,
            onOeffnen: onOeffnen,
          ),
          _Luecke(
            kette: kette,
            vorStation: k + 1,
            onKette: onKette,
            // Zwischen zwei Stationen läuft die Leiste weiter.
            leistenFarbe: k + 1 < stationen.length
                ? abteilungsFarbe(context, stationen[k].first.abteilung)
                : null,
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(left: _leisteBreite + 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _NeueStation(
              kette: kette,
              katalog: katalog,
              onKette: onKette,
            ),
          ),
        ),
      ],
    );
  }
}

/// Lücke vor einer Station (oder hinter der letzten). Unauffällig, solange
/// nichts gezogen wird; beim Darüberziehen öffnet sie sich.
class _Luecke extends StatelessWidget {
  const _Luecke({
    required this.kette,
    required this.vorStation,
    required this.onKette,
    this.leistenFarbe,
  });

  final ProjektKette kette;
  final int vorStation;
  final ValueChanged<List<ProzessSchritt>> onKette;

  /// Farbe der Leiste, die hier zur nächsten Station weiterläuft — null:
  /// keine Leiste.
  final Color? leistenFarbe;

  @override
  Widget build(BuildContext context) {
    final f = AppFarben.von(context);
    final ziel = ProzessZielLuecke(vorStation);
    final farbe = leistenFarbe;
    return DragTarget<ProzessZug>(
      onWillAcceptWithDetails: (d) => kette.umbau(d.data, ziel) != null,
      onAcceptWithDetails: (d) {
        final neu = kette.umbau(d.data, ziel);
        if (neu != null) onKette(neu);
      },
      builder: (context, kandidaten, abgelehnt) {
        final zug = kandidaten.firstOrNull;
        final aktiv = zug != null;
        final hoehe = aktiv ? 46.0 : (farbe == null ? 14.0 : 22.0);
        return SizedBox(
          height: hoehe,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: _leisteBreite,
                child: farbe == null
                    ? null
                    : Column(
                        children: [
                          Expanded(
                            child: Container(
                              width: 2,
                              color: farbe.withValues(alpha: 0.4),
                            ),
                          ),
                          Icon(
                            Icons.arrow_drop_down,
                            size: 18,
                            color: farbe.withValues(alpha: 0.7),
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
                          color: f.infoFlaeche,
                          borderRadius: AppMasse.ecken,
                          border: Border.all(color: f.info, width: 1.5),
                        ),
                        child: Text(
                          zug is ProzessStationsZug
                              ? 'Station hierher verschieben'
                              : 'Hier als eigene Station einfügen',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: f.info,
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

/// Eine Station: Nummer an der Leiste, Kopf mit Abteilung und Griff,
/// darunter die Anlagen von links nach rechts.
class _Station extends StatelessWidget {
  const _Station({
    required this.kette,
    required this.index,
    required this.anlagen,
    required this.katalog,
    required this.katalogGeladen,
    required this.onKette,
    required this.onOeffnen,
  });

  final ProjektKette kette;
  final int index;
  final Map<String, KatalogAnlage> anlagen;
  final List<KatalogAnlage> katalog;
  final bool katalogGeladen;
  final ValueChanged<List<ProzessSchritt>> onKette;
  final ValueChanged<ProzessSchritt> onOeffnen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = AppFarben.von(context);
    final station = kette.stationen[index];
    final farbe = abteilungsFarbe(context, station.first.abteilung);
    final ziel = ProzessZielStation(index);
    final istLetzte = index == kette.stationen.length - 1;

    return DragTarget<ProzessZug>(
      key: ValueKey('prozess-station-$index'),
      onWillAcceptWithDetails: (d) => kette.umbau(d.data, ziel) != null,
      onAcceptWithDetails: (d) {
        final neu = kette.umbau(d.data, ziel);
        if (neu != null) onKette(neu);
      },
      builder: (context, kandidaten, abgelehnt) {
        final istZiel = kandidaten.isNotEmpty;
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Leiste: Nummer der Station, darunter die Linie zur nächsten.
              SizedBox(
                width: _leisteBreite,
                child: Column(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: farbe,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (!istLetzte)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: farbe.withValues(alpha: 0.4),
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
                    color: istZiel ? f.infoFlaeche : theme.colorScheme.surface,
                    borderRadius: AppMasse.ecken,
                    border: Border.all(
                      color: istZiel ? f.info : farbe.withValues(alpha: 0.45),
                      width: istZiel ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _StationsKopf(
                        kette: kette,
                        index: index,
                        farbe: farbe,
                        onKette: onKette,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 4,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (var i = 0; i < station.length; i++) ...[
                            _Kachel(
                              kette: kette,
                              schritt: station[i],
                              station: index,
                              farbe: farbe,
                              anlage: anlagen[station[i].maschineId],
                              katalogGeladen: katalogGeladen,
                              onKette: onKette,
                              onOeffnen: onOeffnen,
                            ),
                            Icon(
                              i < station.length - 1
                                  ? Icons.arrow_forward_rounded
                                  : Icons.more_horiz_rounded,
                              size: 18,
                              color: farbe.withValues(
                                alpha: i < station.length - 1 ? 0.7 : 0.35,
                              ),
                            ),
                          ],
                          _PlusAnlage(
                            kette: kette,
                            station: index,
                            farbe: farbe,
                            katalog: katalog,
                            onKette: onKette,
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

/// Kopf einer Station: Abteilung und Griff zum Verschieben. Ohne Abteilung
/// (etwa aus früheren Abschnitten) ein Hinweis, der sie festlegen lässt.
class _StationsKopf extends StatelessWidget {
  const _StationsKopf({
    required this.kette,
    required this.index,
    required this.farbe,
    required this.onKette,
  });

  final ProjektKette kette;
  final int index;
  final Color farbe;
  final ValueChanged<List<ProzessSchritt>> onKette;

  Future<void> _abteilungWaehlen(BuildContext context) async {
    final wahl = await showDialog<Abteilung>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Für welche Abteilung arbeitet die Station?'),
        children: [
          for (final a in Abteilung.values)
            SimpleDialogOption(
              key: ValueKey('station-abteilung-${a.dbValue}'),
              onPressed: () => Navigator.of(ctx).pop(a),
              child: Row(
                children: [
                  AbteilungsMarke(abteilung: a),
                  const SizedBox(width: 10),
                  Text(a.anzeigeName),
                ],
              ),
            ),
        ],
      ),
    );
    if (wahl == null) return;
    onKette(kette.stationAbteilung(index, wahl.dbValue));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wert = kette.stationen[index].first.abteilung;
    final abteilung = abteilungAus(wert);
    final name = abteilungsName(wert);
    return Row(
      children: [
        AbteilungsMarke(abteilung: abteilung, skala: 1.15),
        const SizedBox(width: 8),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (abteilung == null) ...[
                const SizedBox(width: 8),
                StatusMarke(
                  'Abteilung festlegen',
                  key: ValueKey('station-ohne-abteilung-$index'),
                  art: StatusArt.warnung,
                  icon: Icons.edit_outlined,
                  hinweis:
                      'Für die Freigabe braucht jede Station ihre Abteilung',
                  onTap: () => _abteilungWaehlen(context),
                ),
              ],
            ],
          ),
        ),
        // Griff zum Verschieben der ganzen Station — ein eigener Griff statt
        // der ganzen Fläche, damit das Ziehen einzelner Anlagen nicht
        // kollidiert.
        Draggable<ProzessZug>(
          data: ProzessStationsZug(index),
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: _ZiehSchild(text: name, farbe: farbe),
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
    );
  }
}

/// Was beim Ziehen am Mauszeiger hängt: der Name in der Abteilungsfarbe.
class _ZiehSchild extends StatelessWidget {
  const _ZiehSchild({required this.text, required this.farbe});

  final String text;
  final Color farbe;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: farbe,
      elevation: 3,
      borderRadius: AppMasse.ecken,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

/// Eine Anlage in ihrer Station: zieh- und ablegbar, Antippen öffnet sie
/// mit ihren Werten.
class _Kachel extends StatelessWidget {
  const _Kachel({
    required this.kette,
    required this.schritt,
    required this.station,
    required this.farbe,
    required this.anlage,
    required this.katalogGeladen,
    required this.onKette,
    required this.onOeffnen,
  });

  final ProjektKette kette;
  final ProzessSchritt schritt;
  final int station;
  final Color farbe;

  /// Die Anlage aus dem Katalog — null ohne Anlage oder wenn sie fehlt.
  final KatalogAnlage? anlage;
  final bool katalogGeladen;
  final ValueChanged<List<ProzessSchritt>> onKette;
  final ValueChanged<ProzessSchritt> onOeffnen;

  @override
  Widget build(BuildContext context) {
    final f = AppFarben.von(context);
    final s = schritt;
    final ziel = ProzessZielSchritt(s.id, station);
    final inhalt = _KachelInhalt(
      schritt: s,
      nummer: kette.indexVon(s.id) + 1,
      farbe: farbe,
      anlage: anlage,
      katalogGeladen: katalogGeladen,
      onTap: () => onOeffnen(s),
    );

    // Der gezogene Schritt über seinem eigenen Platz: annehmen und nichts
    // tun — sonst fiele der Zug auf die Station durch und schöbe ihn ans
    // Ende der Station.
    bool selbst(ProzessZug zug) => zug is ProzessSchrittZug && zug.id == s.id;

    return DragTarget<ProzessZug>(
      // Eine ganze Station nimmt die Station an, nicht die Kachel.
      onWillAcceptWithDetails: (d) =>
          d.data is! ProzessStationsZug &&
          (selbst(d.data) || kette.umbau(d.data, ziel) != null),
      onAcceptWithDetails: (d) {
        final neu = kette.umbau(d.data, ziel);
        if (neu != null) onKette(neu);
      },
      builder: (context, kandidaten, abgelehnt) {
        // Einfügemarke links (davor) — rechts, wenn ein Schritt derselben
        // Station von links kommt: Er landet dahinter.
        final zug = kandidaten.firstOrNull;
        final Border? marke;
        if (zug == null || selbst(zug)) {
          marke = null;
        } else {
          final dahinter = zug is ProzessSchrittZug &&
              kette.stationVon(zug.id) == station &&
              kette.indexVon(zug.id) < kette.indexVon(s.id);
          final linie = BorderSide(color: f.info, width: 4);
          marke = dahinter ? Border(right: linie) : Border(left: linie);
        }
        return Draggable<ProzessZug>(
          data: ProzessSchrittZug(s.id),
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

/// Das Aussehen einer Kachel: Nummer, Name, Prozessschritt und wie viele
/// Werte eingetragen sind.
class _KachelInhalt extends StatelessWidget {
  const _KachelInhalt({
    required this.schritt,
    required this.nummer,
    required this.farbe,
    required this.anlage,
    required this.katalogGeladen,
    required this.onTap,
  });

  final ProzessSchritt schritt;
  final int nummer;
  final Color farbe;
  final KatalogAnlage? anlage;
  final bool katalogGeladen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final s = schritt;
    final a = anlage;
    final name = s.bezeichnung(nummer);
    final prozess = s.prozessschritt.trim();

    // Arbeitet die Anlage hier für eine andere Abteilung als ihre
    // Stammabteilung, steht diese an der Kachel.
    final stamm = a == null || a.abteilung == s.abteilung
        ? null
        : abteilungAus(a.abteilung);
    // Ein Name ohne Anlage im Katalog — etwa aus früheren Abschnitten.
    final fremd =
        katalogGeladen && a == null && s.maschine.trim().isNotEmpty;
    final stand = werteStand(s, a);

    return SizedBox(
      width: 210,
      child: Material(
        key: ValueKey('prozess-schritt-${s.id}'),
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppMasse.ecken,
          side: BorderSide(color: theme.colorScheme.outline),
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
                    NummernMarke(nummer: nummer, farbe: farbe),
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
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: StatusMarke(
                          'aus ${stamm.kurzcode}',
                          hinweis: 'Anlage aus ${stamm.anzeigeName} — '
                              'arbeitet in diesem Projekt hier mit',
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
                    style: theme.textTheme.bodySmall?.copyWith(color: grau),
                  ),
                ],
                const SizedBox(height: 7),
                Row(
                  children: [
                    if (fremd)
                      const StatusMarke(
                        'nicht im Katalog',
                        art: StatusArt.warnung,
                        hinweis: 'Antippen und unter „Bearbeiten" eine Anlage '
                            'zuordnen',
                      )
                    else if (katalogGeladen && stand.gesamt > 0)
                      StatusMarke(
                        '${stand.eingetragen}/${stand.gesamt} Werte',
                        art: stand.eingetragen == stand.gesamt
                            ? StatusArt.ok
                            : (stand.eingetragen == 0
                                ? StatusArt.fehler
                                : StatusArt.warnung),
                      ),
                    const Spacer(),
                    Icon(Icons.chevron_right, size: 18, color: grau),
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
    required this.kette,
    required this.station,
    required this.farbe,
    required this.katalog,
    required this.onKette,
  });

  final ProjektKette kette;
  final int station;
  final Color farbe;
  final List<KatalogAnlage> katalog;
  final ValueChanged<List<ProzessSchritt>> onKette;

  Future<void> _waehlen(BuildContext context) async {
    if (kette.voll) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(kKetteVollText)),
      );
      return;
    }
    final neu = await neuerSchritt(
      context,
      katalog: katalog,
      abteilung: kette.stationen[station].first.abteilung,
    );
    if (neu == null) return;
    final liste = kette.einfuegen(kette.grenzeVor(station + 1), neu);
    if (liste != null) onKette(liste);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final abteilung = kette.stationen[station].first.abteilung;
    return Tooltip(
      message: 'Anlage an ${abteilungsName(abteilung)} anhängen',
      child: Material(
        key: ValueKey('prozess-plus-$station'),
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppMasse.ecken,
          side: BorderSide(color: farbe.withValues(alpha: 0.45)),
        ),
        child: InkWell(
          onTap: () => _waehlen(context),
          borderRadius: AppMasse.ecken,
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

/// Eine neue Station am Ende der Kette — mit einer Anlage beliebiger
/// Abteilung oder einem Schritt ohne Anlage.
class _NeueStation extends StatelessWidget {
  const _NeueStation({
    required this.kette,
    required this.katalog,
    required this.onKette,
  });

  final ProjektKette kette;
  final List<KatalogAnlage> katalog;
  final ValueChanged<List<ProzessSchritt>> onKette;

  Future<void> _hinzufuegen(BuildContext context) async {
    if (kette.voll) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(kKetteVollText)),
      );
      return;
    }
    final neu = await neuerSchritt(context, katalog: katalog);
    if (neu == null) return;
    final liste = kette.einfuegen(kette.schritte.length, neu);
    if (liste != null) onKette(liste);
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: const ValueKey('prozess-neue-station'),
      onPressed: () => _hinzufuegen(context),
      icon: const Icon(Icons.add, size: 18),
      label: const Text('Station hinzufügen…'),
    );
  }
}
