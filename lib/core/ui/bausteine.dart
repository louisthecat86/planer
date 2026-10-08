import 'package:flutter/material.dart';

import '../constants/abteilungen.dart';
import '../theme/app_stil.dart';

// Gemeinsame Bausteine der Oberfläche.
//
// Jede Ansicht baute bisher ihre eigenen Karten, Marken und Leerhinweise —
// mit eigenen Radien, Farben und Schriftgrößen. Hier stehen sie einmal,
// im Navision-Stil: weiße Flächen mit dünnem Rand, eine Kopfzeile mit
// Linie darunter, Farbe nur als Signal.

/// Ein Bereich einer Seite — wie ein Infofenster in Navision: weiße
/// Fläche, dünner Rand, Kopfzeile mit Titel und Aktionen, darunter der
/// Inhalt.
class Bereich extends StatelessWidget {
  const Bereich({
    super.key,
    required this.titel,
    required this.child,
    this.icon,
    this.untertitel,
    this.aktionen = const <Widget>[],
    this.innenAbstand = const EdgeInsets.fromLTRB(12, 6, 12, 10),
  });

  final String titel;

  /// Kleines Symbol vor dem Titel — sparsam einsetzen.
  final IconData? icon;

  /// Grauer Zusatz hinter dem Titel, etwa eine Anzahl.
  final String? untertitel;

  /// Knöpfe rechts in der Kopfzeile.
  final List<Widget> aktionen;

  final EdgeInsetsGeometry innenAbstand;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final farben = theme.colorScheme;
    final zusatz = untertitel;
    // Material statt einer bemalten Box: Hover und Tipp-Welle von Zeilen
    // im Bereich malen auf das nächste Material — unter einer weißen
    // Box wären sie unsichtbar.
    return Material(
      color: farben.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppMasse.ecken,
        side: BorderSide(color: farben.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: AppMasse.kopfHoehe),
            padding: const EdgeInsets.only(left: 12, right: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: farben.outline)),
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: farben.onSurfaceVariant),
                  const SizedBox(width: 8),
                ],
                // Titel und Zusatz teilen sich den Platz bis zu den
                // Aktionen; ein langer Titel wird gekürzt.
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          titel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: farben.onSurface,
                          ),
                        ),
                      ),
                      if (zusatz != null) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            zusatz,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: farben.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ...aktionen,
              ],
            ),
          ),
          Padding(padding: innenAbstand, child: child),
        ],
      ),
    );
  }
}

/// Das Kürzel einer Abteilung als kleine farbige Marke („Z", „WK", „B").
///
/// Die Abteilungsfarbe trägt hier die Information — gefüllt, damit auch
/// das dunkle Braun der Bratstraße im Dunkelmodus erkennbar bleibt.
class AbteilungsMarke extends StatelessWidget {
  const AbteilungsMarke({
    super.key,
    required this.abteilung,
    this.skala = 1,
  });

  /// null: unbekannte Abteilung — grau mit „?".
  final Abteilung? abteilung;

  /// Vergrößerung, wenn die Liste daneben gezoomt wird.
  final double skala;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final abt = abteilung;
    return Container(
      width: 30 * skala,
      padding: EdgeInsets.symmetric(vertical: 2 * skala),
      decoration: BoxDecoration(
        color: abt?.farbe ?? theme.colorScheme.outline,
        borderRadius: AppMasse.eckenKlein,
      ),
      alignment: Alignment.center,
      child: Text(
        abt?.kurzcode ?? '?',
        maxLines: 1,
        style: TextStyle(
          fontSize: 10.5 * skala,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Bedeutung einer [StatusMarke] — bestimmt ihre Farbe.
enum StatusArt { ok, warnung, fehler, info, neutral }

/// Kurzer Status als Marke: „erledigt", „überbucht", „fehlt 94,2 kg".
///
/// Blasse Fläche, Schrift in der Statusfarbe, kein Rand — gut lesbar,
/// ohne laut zu sein.
class StatusMarke extends StatelessWidget {
  const StatusMarke(
    this.text, {
    super.key,
    this.art = StatusArt.neutral,
    this.icon,
  });

  final String text;
  final StatusArt art;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = AppFarben.von(context);
    final (vorne, hinten) = switch (art) {
      StatusArt.ok => (f.ok, f.okFlaeche),
      StatusArt.warnung => (f.warnung, f.warnungFlaeche),
      StatusArt.fehler => (f.fehler, f.fehlerFlaeche),
      StatusArt.info => (f.info, f.infoFlaeche),
      StatusArt.neutral => (
          theme.colorScheme.onSurfaceVariant,
          theme.colorScheme.surfaceContainerHighest,
        ),
    };
    final symbol = icon;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: hinten,
        borderRadius: AppMasse.eckenKlein,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (symbol != null) ...[
            Icon(symbol, size: 13, color: vorne),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            maxLines: 1,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: vorne,
            ),
          ),
        ],
      ),
    );
  }
}

/// Grauer Hinweis, wenn eine Liste leer ist: „Für diesen Tag ist nichts
/// geplant." — optional mit Symbol und einer Aktion darunter.
class LeerHinweis extends StatelessWidget {
  const LeerHinweis(
    this.text, {
    super.key,
    this.icon,
    this.aktion,
  });

  final String text;
  final IconData? icon;
  final Widget? aktion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final symbol = icon;
    final knopf = aktion;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (symbol != null) ...[
            Icon(symbol, size: 22, color: grau),
            const SizedBox(height: 6),
          ],
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: grau),
          ),
          if (knopf != null) ...[
            const SizedBox(height: 8),
            knopf,
          ],
        ],
      ),
    );
  }
}
