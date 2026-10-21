import 'package:flutter/material.dart';

import '../utils/fehler_text.dart';

// Fehler, die niemand abfängt, sichtbar machen.
//
// Ohne das landete ein Fehler in einer Hintergrundaufgabe nur in der
// Konsole — am Arbeitsplatz sah man nichts, und eine Seite mit einem
// Fehler beim Aufbau blieb in der fertigen App einfach grau. Jetzt
// erscheint der Fehler unten als Meldung, und ein Bereich, der sich nicht
// aufbauen lässt, sagt das in Worten.

/// Für Meldungen von überall — auch ohne BuildContext.
final GlobalKey<ScaffoldMessengerState> appMessengerKey =
    GlobalKey<ScaffoldMessengerState>(debugLabel: 'appMessenger');

/// Die zuletzt gezeigte Meldung und wann — dieselbe kommt nicht im
/// Sekundentakt wieder.
String? _letzte;
DateTime? _letzteZeit;

/// Zeigt [fehler] unten als Meldung. Dieselbe Meldung erscheint
/// höchstens alle fünf Sekunden.
void fehlerMelden(Object fehler, {String? wobei, DateTime? jetzt}) {
  final text = wobei == null
      ? 'Unerwarteter Fehler: ${fehlerText(fehler)}'
      : '$wobei: ${fehlerText(fehler)}';
  final zeit = jetzt ?? DateTime.now();
  final vorher = _letzteZeit;
  if (text == _letzte &&
      vorher != null &&
      zeit.difference(vorher) < const Duration(seconds: 5)) {
    return;
  }
  _letzte = text;
  _letzteZeit = zeit;
  // Nicht mitten im Aufbau eines Bildes: erst danach anzeigen.
  final binding = WidgetsBinding.instance;
  binding.addPostFrameCallback((_) {
    final messenger = appMessengerKey.currentState;
    if (messenger == null) return;
    // Scheitert schon das Anzeigen, bleibt es bei der Konsole — sonst
    // meldete sich der Fehler beim Melden immer wieder selbst.
    try {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 8),
            showCloseIcon: true,
            content: Text(text),
          ),
        );
    } catch (anzeige) {
      debugPrint('Meldung ließ sich nicht anzeigen: $anzeige');
    }
  });
  binding.ensureVisualUpdate();
}

/// Richtet das ein: Fehler aus dem Rahmenwerk und aus Hintergrund-
/// aufgaben erscheinen als Meldung, ein Bereich mit Fehler beim Aufbau als
/// [FehlerKachel]. In der Konsole stehen sie weiter vollständig.
void fehlerAnzeigeEinrichten() {
  final bisher = FlutterError.onError;
  FlutterError.onError = (details) {
    if (bisher != null) {
      bisher(details);
    } else {
      FlutterError.presentError(details);
    }
    if (_nurHinweis(details)) return;
    fehlerMelden(details.exception);
  };
  WidgetsBinding.instance.platformDispatcher.onError = (fehler, stapel) {
    debugPrint('Unbehandelter Fehler: $fehler\n$stapel');
    fehlerMelden(fehler);
    return true;
  };
  ErrorWidget.builder = (details) => FehlerKachel(fehler: details.exception);
}

/// Meldungen, die nur Entwickler angehen — etwa ein Layout, das um ein
/// paar Pixel überläuft. Sie stehen in der Konsole, nicht als Meldung.
bool _nurHinweis(FlutterErrorDetails details) {
  if (details.silent) return true;
  final text = details.exceptionAsString();
  return details.library == 'rendering library' &&
      (text.contains('overflowed') || text.contains('RenderFlex'));
}

/// Steht dort, wo sich ein Bereich nicht aufbauen ließ.
class FehlerKachel extends StatelessWidget {
  const FehlerKachel({super.key, required this.fehler});

  final Object fehler;

  @override
  Widget build(BuildContext context) {
    // Ohne Theme und Textrichtung lauffähig — der Fehler kann überall
    // stecken, auch ganz oben im Baum.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        color: const Color(0xFFFFF3E0),
        padding: const EdgeInsets.all(12),
        alignment: Alignment.topLeft,
        child: Text(
          'Dieser Bereich ließ sich nicht anzeigen.\n${fehlerText(fehler)}',
          style: const TextStyle(color: Color(0xFF8A3A00), fontSize: 13),
        ),
      ),
    );
  }
}
