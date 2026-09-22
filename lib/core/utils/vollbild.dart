import 'dart:async';
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
  ///
  /// Das ist der Zustand, den der Nutzer **will**, nicht unbedingt der, in
  /// dem das Fenster gerade steht. Beim Minimieren verlässt Windows das
  /// Vollbild von sich aus. Beim Zurückholen stellt [_FensterBeobachter] es
  /// anhand dieses Werts wieder her.
  static final ValueNotifier<bool> aktiv = ValueNotifier(false);

  /// Solange wir selbst umschalten, lösen die Fensterereignisse dabei
  /// keine weitere Umschaltung aus — sonst entstünde eine Schleife.
  static bool _schaltetGerade = false;

  static Future<void> _setze(bool vollbild) async {
    _schaltetGerade = true;
    try {
      await windowManager.setFullScreen(vollbild);
      aktiv.value = vollbild;
    } finally {
      // Das Fenster meldet seine Änderungen verzögert. Kurz warten, damit
      // diese Meldungen noch als „selbst ausgelöst“ gelten.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      _schaltetGerade = false;
    }
  }

  static bool get _desktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// Beim App-Start aufrufen, vor `runApp`.
  static Future<void> starten() async {
    if (!_desktop) return;
    try {
      await windowManager.ensureInitialized();
      windowManager.addListener(_FensterBeobachter());
      await windowManager.waitUntilReadyToShow(null, () async {
        await _setze(true);
        await windowManager.show();
        await windowManager.focus();
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
      await _setze(!aktiv.value);
    } catch (_) {
      // Fenster nicht erreichbar — nichts zu tun.
    }
  }

  /// Minimiert die App. Nötig, weil im Vollbild die Titelleiste mit ihrem
  /// Minimieren-Knopf fehlt.
  static Future<void> minimieren() async {
    if (!_desktop) return;
    try {
      await windowManager.minimize();
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

/// Hält das Vollbild bei den Knöpfen der Titelleiste und beim Minimieren.
///
/// Ohne diesen Beobachter gab es zwei Lücken:
///   * Der Maximieren-Knopf □ der Titelleiste machte das Fenster nur
///     maximiert — Titelleiste und Taskleiste blieben sichtbar.
///   * Wer im Vollbild minimierte und die App über die Taskleiste
///     zurückholte, bekam ein normales Fenster. Windows verlässt beim
///     Minimieren das Vollbild von sich aus.
class _FensterBeobachter with WindowListener {
  @override
  void onWindowMaximize() {
    if (Vollbild._schaltetGerade) return;
    // □ bedeutet hier: so groß wie möglich — also Vollbild.
    unawaited(Vollbild._setze(true));
  }

  @override
  void onWindowRestore() {
    if (Vollbild._schaltetGerade) return;
    if (Vollbild.aktiv.value) unawaited(Vollbild._setze(true));
  }

  @override
  void onWindowLeaveFullScreen() {
    if (Vollbild._schaltetGerade) return;
    // Nicht selbst ausgelöst, etwa per Tastenkombination des Systems. Dann
    // gilt das als Wunsch des Nutzers, und das Symbol soll ihn zeigen.
    // Beim Minimieren kommt diese Meldung ebenfalls — dort darf sie den
    // Wunsch nicht löschen, sonst käme das Vollbild nicht zurück.
    unawaited(
      windowManager.isMinimized().then((minimiert) {
        if (!minimiert) Vollbild.aktiv.value = false;
      }),
    );
  }
}
