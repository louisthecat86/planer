import 'dart:io';
// AppExitType liegt in dart:ui und wird von services.dart nicht
// weitergereicht — app.dart holt sich AppExitResponse genauso.
import 'dart:ui' show AppExitType;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// Vollbild für die Desktop-App — ohne Titelleiste und ohne Taskleiste.
///
/// Die App läuft an festen Arbeitsplätzen in der Produktion. Dort stört die
/// Taskleiste nur und lädt zum Wegklicken ein. Deshalb startet die App im
/// Vollbild.
///
/// **Ohne Titelleiste fehlen ✕ und Minimieren.** Deshalb gibt es:
///   * F11 zum Ein- und Ausschalten, überall in der App,
///   * einen Knopf auf der Startseite,
///   * [beenden] für einen eigenen Beenden-Knopf.
///
/// Alles hier ist abgesichert: Auf Plattformen ohne Fenster (Tests, Web)
/// oder wenn das Plugin nicht antwortet, läuft die App normal weiter statt
/// beim Start abzustürzen.
abstract final class Vollbild {
  /// Ob gerade Vollbild aktiv ist — für das passende Symbol im Knopf.
  static final ValueNotifier<bool> aktiv = ValueNotifier(false);

  static bool get _desktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// Beim App-Start aufrufen, vor `runApp`.
  static Future<void> starten() async {
    if (!_desktop) return;
    try {
      await windowManager.ensureInitialized();
      await windowManager.waitUntilReadyToShow(null, () async {
        await windowManager.setFullScreen(true);
        await windowManager.show();
        await windowManager.focus();
        aktiv.value = true;
      });
    } catch (_) {
      // Ohne Fenstersteuerung startet die App im normalen Fenster.
      return;
    }

    // Direkt an der Tastatur statt an einem Fokusbereich: So greift F11
    // auch dann, wenn gerade kein Eingabefeld aktiv ist.
    HardwareKeyboard.instance.addHandler((event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.f11) {
        umschalten();
        return true;
      }
      return false;
    });
  }

  /// Vollbild ein oder aus.
  static Future<void> umschalten() async {
    if (!_desktop) return;
    try {
      final neu = !await windowManager.isFullScreen();
      await windowManager.setFullScreen(neu);
      aktiv.value = neu;
    } catch (_) {
      // Fenster nicht erreichbar — nichts zu tun.
    }
  }

  /// Beendet die App auf demselben Weg wie das ✕ der Titelleiste.
  ///
  /// Wichtig, weil `app.dart` beim Beenden noch ein Backup schreibt. Über
  /// `exitApplication` läuft die Anfrage durch denselben Lebenszyklus wie
  /// das Schließen des Fensters, das Backup findet also statt.
  static Future<void> beenden() async {
    await ServicesBinding.instance.exitApplication(AppExitType.cancelable);
  }
}
