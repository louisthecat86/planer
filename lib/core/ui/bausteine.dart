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
                // Titel und Zusatz in einem Text: Sie teilen sich den Platz
                // bis zu den Aktionen und stehen auf einer Grundlinie.
                // Gekürzt wird am Ende — erst der Zusatz, dann der Titel.
                // (Als zwei Texte in einer Zeile bekäme der Zusatz nur die
                // Hälfte des Platzes, auch wenn der Titel kurz ist.)
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: titel,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: farben.onSurface,
                      ),
                      children: [
                        if (zusatz != null)
                          TextSpan(
                            text: '   $zusatz',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: farben.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

/// Bedeutung einer [StatusMarke] oder [HinweisBox] — bestimmt ihre Farbe.
enum StatusArt { ok, warnung, fehler, info, neutral }

/// Schrift- und Flächenfarbe zu einer [StatusArt] im aktuellen Theme.
(Color vorne, Color hinten) _statusFarben(BuildContext context, StatusArt art) {
  final theme = Theme.of(context);
  final f = AppFarben.von(context);
  return switch (art) {
    StatusArt.ok => (f.ok, f.okFlaeche),
    StatusArt.warnung => (f.warnung, f.warnungFlaeche),
    StatusArt.fehler => (f.fehler, f.fehlerFlaeche),
    StatusArt.info => (f.info, f.infoFlaeche),
    StatusArt.neutral => (
        theme.colorScheme.onSurfaceVariant,
        theme.colorScheme.surfaceContainerHighest,
      ),
  };
}

/// Kurzer Status als Marke: „erledigt", „überbucht", „fehlt 94,2 kg".
///
/// Blasse Fläche, Schrift in der Statusfarbe, kein Rand — gut lesbar,
/// ohne laut zu sein. Mit [onTap] wird sie antippbar, etwa um den Wert
/// dahinter zu ändern; [hinweis] erklärt sie beim Darüberfahren.
class StatusMarke extends StatelessWidget {
  const StatusMarke(
    this.text, {
    super.key,
    this.art = StatusArt.neutral,
    this.icon,
    this.onTap,
    this.hinweis,
  });

  final String text;
  final StatusArt art;
  final IconData? icon;

  /// Antippen — null: reine Anzeige.
  final VoidCallback? onTap;

  /// Erklärung beim Darüberfahren — null: keine.
  final String? hinweis;

  @override
  Widget build(BuildContext context) {
    final (vorne, hinten) = _statusFarben(context, art);
    final symbol = icon;
    final zeile = Row(
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
    );
    const abstand = EdgeInsets.symmetric(horizontal: 6, vertical: 2);

    final tippen = onTap;
    final Widget marke = tippen == null
        ? Container(
            padding: abstand,
            decoration: BoxDecoration(
              color: hinten,
              borderRadius: AppMasse.eckenKlein,
            ),
            child: zeile,
          )
        // Antippbar: Material statt bemalter Box — die Tipp-Welle malt auf
        // das nächste Material und wäre unter der Fläche unsichtbar.
        : Material(
            color: hinten,
            borderRadius: AppMasse.eckenKlein,
            child: InkWell(
              onTap: tippen,
              borderRadius: AppMasse.eckenKlein,
              child: Padding(padding: abstand, child: zeile),
            ),
          );

    final erklaerung = hinweis;
    return erklaerung == null
        ? marke
        : Tooltip(message: erklaerung, child: marke);
  }
}

/// Ein Hinweis mitten im Inhalt: blasse Statusfläche, kräftige Kante links,
/// davor ein Symbol. Für Erklärungen in Fenstern („Zeiten gibt es an der
/// Anlage keine …"), für Fehler, die stehen bleiben sollen, bis man sie
/// behebt — und als Leiste über einer Liste, mit [aktion] rechts („Prüfen
/// …") oder einem Kreuz zum Wegklicken ([onSchliessen]).
///
/// Bewusst ohne Rundung: Eine Kante auf nur einer Seite lässt sich nicht
/// runden.
class HinweisBox extends StatelessWidget {
  const HinweisBox(
    this.text, {
    super.key,
    this.art = StatusArt.info,
    this.icon,
    this.aktion,
    this.onSchliessen,
    this.auswaehlbar = false,
  });

  final String text;
  final StatusArt art;

  /// Eigenes Symbol — sonst das passende zur [art].
  final IconData? icon;

  /// Knopf rechts neben dem Text — null: keiner.
  final Widget? aktion;

  /// Kreuz zum Wegklicken — null: keins.
  final VoidCallback? onSchliessen;

  /// Text markier- und kopierbar, etwa für Fehlermeldungen.
  final bool auswaehlbar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (vorne, hinten) = _statusFarben(context, art);
    final symbol = icon ??
        switch (art) {
          StatusArt.ok => Icons.check_circle_outline,
          StatusArt.warnung => Icons.warning_amber_rounded,
          StatusArt.fehler => Icons.error_outline,
          StatusArt.info || StatusArt.neutral => Icons.info_outline,
        };
    final stil = theme.textTheme.bodySmall?.copyWith(
      height: 1.35,
      color: theme.colorScheme.onSurface,
    );
    final knopf = aktion;
    final schliessen = onSchliessen;
    final mitKnopf = knopf != null || schliessen != null;
    return Container(
      padding: mitKnopf
          ? const EdgeInsets.fromLTRB(10, 6, 6, 6)
          : const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: hinten,
        border: Border(left: BorderSide(color: vorne, width: 3)),
      ),
      child: Row(
        // Mit Knopf mittig, damit Text und Knopf auf einer Höhe stehen.
        crossAxisAlignment:
            mitKnopf ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Icon(symbol, size: 16, color: vorne),
          const SizedBox(width: 8),
          Expanded(
            child: auswaehlbar
                ? SelectableText(text, style: stil)
                : Text(text, style: stil),
          ),
          if (knopf != null) ...[
            const SizedBox(width: 8),
            knopf,
          ],
          if (schliessen != null)
            IconButton(
              onPressed: schliessen,
              icon: const Icon(Icons.close, size: 16),
              tooltip: 'Schließen',
              visualDensity: VisualDensity.compact,
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
