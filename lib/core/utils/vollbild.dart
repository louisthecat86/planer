import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
// AppExitType liegt in dart:ui und wird von services.dart nicht
// weitergereicht — app.dart holt sich AppExitResponse genauso.
import 'dart:ui' show AppExitType;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

// Windows-API-Signatur für den harten Prozessabbruch, siehe [Vollbild.beenden].
typedef _TerminateProcessNative = ffi.Int32 Function(
    ffi.IntPtr hProcess, ffi.Uint32 uExitCode,);
typedef _TerminateProcessDart = int Function(int hProcess, int uExitCode);

/// Vollbild für die Desktop-App — ohne Titelleiste und ohne Taskleiste.
///
/// Die App läuft an festen Arbeitsplätzen in der Produktion. Dort stört die
/// Taskleiste nur und lädt zum Wegklicken ein. Deshalb startet die App im
/// Vollbild.
///
/// **Ohne Titelleiste fehlen ✕, □ und Minimieren.** Dafür gibt es F11 und
/// eigene Knöpfe auf der Startseite.
///
/// ## Warum jeder Wechsel durch [_nacheinander] läuft
///
/// Ein Fenster im Vollbild direkt zu minimieren, verträgt Windows mit
/// diesem Paket schlecht. Beim Zurückholen verschickt es außerdem mehrere
/// Meldungen kurz hintereinander. In einer früheren Fassung löste jede
/// dieser Meldungen einen eigenen Wechsel aus, während der vorige noch
/// lief. Das Fenster blieb dann zwischen Vollbild und Normalfenster
/// stecken: schwarzer Bildschirm, Knöpfe ohne Wirkung, kein Eintrag in der
/// Taskleiste — beenden ging nur noch über den Taskmanager.
///
/// Deshalb:
///   * Ein Vollbildfenster wird nie direkt minimiert. [minimieren] verlässt
///     erst das Vollbild und minimiert danach.
///   * Alle Wechsel laufen nacheinander. Meldungen, die während eines
///     Wechsels eintreffen, bleiben unbeachtet.
///
/// Alles hier ist abgesichert: Auf Plattformen ohne Fenster (Tests, Web)
/// oder wenn das Plugin nicht antwortet, läuft die App normal weiter.
abstract final class Vollbild {
  /// Ob Vollbild gewünscht ist — für das passende Symbol im Knopf.
  ///
  /// Das ist der Wunsch, nicht unbedingt der aktuelle Fensterzustand: Beim
  /// Minimieren verlässt die App das Vollbild bewusst und kehrt beim
  /// Zurückholen dorthin zurück.
  static final ValueNotifier<bool> aktiv = ValueNotifier(false);

  /// Pause nach jedem Wechsel. Das Fenster meldet seine Änderungen
  /// verzögert. Erst danach ist der Zustand verlässlich, und erst danach
  /// darf der nächste Wechsel beginnen.
  static const Duration _beruhigen = Duration(milliseconds: 350);

  /// Läuft gerade ein Wechsel? Dann ignoriert der Beobachter Meldungen.
  static bool _imWechsel = false;

  /// Warteschlange: Jeder Wechsel hängt sich an den vorigen an.
  static Future<void> _schlange = Future<void>.value();

  static bool get _desktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  static Future<void> _nacheinander(Future<void> Function() schritt) {
    final naechster = _schlange.then((_) async {
      _imWechsel = true;
      try {
        await schritt();
      } catch (_) {
        // Fenster nicht erreichbar — der nächste Wechsel darf trotzdem.
      } finally {
        await Future<void>.delayed(_beruhigen);
        _imWechsel = false;
      }
    });
    _schlange = naechster;
    return naechster;
  }

  /// Beim App-Start aufrufen, vor `runApp`.
  static Future<void> starten() async {
    if (!_desktop) return;
    try {
      await windowManager.ensureInitialized();
      windowManager.addListener(_FensterBeobachter());
      await windowManager.waitUntilReadyToShow(null, () async {
        await windowManager.show();
        await windowManager.focus();
      });
      aktiv.value = true;
      await _nacheinander(() => windowManager.setFullScreen(true));
    } catch (_) {
      // Ohne Fenstersteuerung startet die App im normalen Fenster.
      return;
    }

    // Direkt an der Tastatur statt an einem Fokusbereich: So greift F11
    // auch dann, wenn gerade kein Eingabefeld aktiv ist.
    HardwareKeyboard.instance.addHandler((event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.f11) {
        unawaited(umschalten());
        return true;
      }
      return false;
    });
  }

  /// Vollbild ein oder aus.
  static Future<void> umschalten() {
    if (!_desktop) return Future<void>.value();
    final neu = !aktiv.value;
    aktiv.value = neu;
    return _nacheinander(() => windowManager.setFullScreen(neu));
  }

  /// Minimiert die App — im Vollbild erst nach dem Verlassen des Vollbilds.
  static Future<void> minimieren() {
    if (!_desktop) return Future<void>.value();
    return _nacheinander(() async {
      if (await windowManager.isFullScreen()) {
        await windowManager.setFullScreen(false);
        // Erst warten, bis das Fenster wirklich wieder normal steht.
        await Future<void>.delayed(_beruhigen);
      }
      await windowManager.minimize();
    });
  }

  /// Nach dem Zurückholen: ins Vollbild, falls gewünscht.
  static Future<void> _nachWiederherstellen() {
    return _nacheinander(() async {
      // Das Fenster erst vollständig zurückkommen lassen.
      await Future<void>.delayed(_beruhigen);
      if (!aktiv.value) return;
      if (await windowManager.isMinimized()) return;
      if (await windowManager.isFullScreen()) return;
      await windowManager.setFullScreen(true);
    });
  }

  /// Maximieren-Knopf der Titelleiste: statt nur maximiert → Vollbild.
  static Future<void> _nachMaximieren() {
    return _nacheinander(() async {
      await Future<void>.delayed(_beruhigen);
      if (await windowManager.isFullScreen()) return;
      aktiv.value = true;
      await windowManager.setFullScreen(true);
    });
  }

  /// Beendet die App.
  ///
  /// Aufrufer müssen vorher selbst aufräumen (Backup, `db.close()`) — hier
  /// kommt danach kein Dart-Code mehr zur Ausführung.
  ///
  /// Auf Windows crasht der reguläre Engine-Shutdown
  /// (`ServicesBinding.exitApplication`, egal ob `required` oder
  /// `cancelable`) auf manchen Rechnern mit einer Zugriffsverletzung in
  /// `flutter_windows.dll` (beobachtet auf einem Remote-Desktop-Server,
  /// vermutlich ein Grafik-Teardown-Problem unter RDP). `TerminateProcess`
  /// beendet den Prozess sofort und umgeht diesen kaputten Pfad komplett.
  static Future<void> beenden() async {
    if (Platform.isWindows) {
      final kernel32 = ffi.DynamicLibrary.open('kernel32.dll');
      final terminateProcess = kernel32.lookupFunction<
          _TerminateProcessNative, _TerminateProcessDart>('TerminateProcess');
      terminateProcess(-1, 0);
      return;
    }
    await ServicesBinding.instance.exitApplication(AppExitType.required);
  }
}

/// Reagiert auf die Knöpfe der Titelleiste und auf das Zurückholen aus der
/// Taskleiste. Während eines eigenen Wechsels bleibt er stumm.
class _FensterBeobachter with WindowListener {
  @override
  void onWindowRestore() {
    if (Vollbild._imWechsel) return;
    unawaited(Vollbild._nachWiederherstellen());
  }

  @override
  void onWindowMaximize() {
    if (Vollbild._imWechsel) return;
    unawaited(Vollbild._nachMaximieren());
  }
}
