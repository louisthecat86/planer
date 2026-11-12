import 'package:flutter/material.dart';

import 'fehler_anzeige.dart';

/// So lange steht das „Rückgängig" nach dem Löschen unten.
const Duration kRueckgaengigDauer = Duration(seconds: 8);

/// Meldet unten, dass etwas gelöscht wurde, und bietet an, es
/// zurückzuholen.
///
/// Statt einer Rückfrage vor dem Löschen: Wer löschen will, ist mit einem
/// Klick fertig, und wer sich verklickt hat, holt es mit einem Klick
/// zurück. Geht nur, wo das Löschen nichts endgültig entfernt.
///
/// [messenger] vorher holen — das Fenster, aus dem gelöscht wurde, ist
/// dann meist schon zu.
void geloeschtMelden(
  ScaffoldMessengerState messenger, {
  required String text,
  required Future<void> Function() zurueck,
}) {
  // Die vorige Meldung weg, damit das Rückgängig zur letzten Löschung
  // sofort sichtbar ist.
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(text),
      duration: kRueckgaengigDauer,
      // Mit Aktion bliebe die Meldung sonst stehen, bis jemand klickt —
      // und sperrte jede weitere Meldung der App.
      persist: false,
      action: SnackBarAction(
        label: 'Rückgängig',
        onPressed: () async {
          try {
            await zurueck();
          } catch (e) {
            fehlerMelden(e, wobei: 'Rückgängig fehlgeschlagen');
          }
        },
      ),
    ),
  );
}
