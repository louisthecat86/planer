import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'entwicklung_zugang.dart';
import 'projekte/datei_aktionen.dart';

// Die Produktentwicklung sperrt sich selbst, wenn eine Weile niemand die
// App bedient (F20): kein Klick, keine Mausbewegung, keine Taste. Wer
// gerade in der Planung arbeitet, sitzt am Rechner — dann bleibt sie
// offen. Liegt die App unbeachtet im Hintergrund, schließt sich die Tür.

/// Nach so langer Zeit ohne Eingabe sperrt sich die Produktentwicklung.
const Duration kEntwicklungSperreNach = Duration(minutes: 15);

/// Ob die Produktentwicklung zuletzt von selbst gesperrt wurde — die
/// Passwortabfrage sagt es dann dazu.
final entwicklungAutoGesperrtProvider = StateProvider<bool>((ref) => false);

/// Beobachtet die Eingaben in [child] und sperrt die Produktentwicklung
/// nach [nach] ohne Eingabe. Offene Fenster darüber schließt
/// [fensterSchliessen], entschlüsselte Dateien zum Öffnen werden
/// weggeräumt.
class EntwicklungAutoSperre extends ConsumerStatefulWidget {
  const EntwicklungAutoSperre({
    super.key,
    required this.child,
    this.nach = kEntwicklungSperreNach,
    this.takt = const Duration(seconds: 20),
    this.jetzt = DateTime.now,
    this.fensterSchliessen,
  });

  final Widget child;
  final Duration nach;

  /// Wie oft nachgesehen wird.
  final Duration takt;

  /// Die Uhr — Tests geben eine eigene vor.
  final DateTime Function() jetzt;

  /// Schließt Fenster (Dialoge), die über der Produktentwicklung offen
  /// sind — sonst blieben ihre Daten über der Sperre stehen.
  final VoidCallback? fensterSchliessen;

  @override
  ConsumerState<EntwicklungAutoSperre> createState() =>
      _EntwicklungAutoSperreState();
}

class _EntwicklungAutoSperreState extends ConsumerState<EntwicklungAutoSperre> {
  late DateTime _letzteEingabe = widget.jetzt();
  Timer? _uhr;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_taste);
    _uhr = Timer.periodic(widget.takt, (_) => _pruefen());
  }

  @override
  void dispose() {
    _uhr?.cancel();
    HardwareKeyboard.instance.removeHandler(_taste);
    super.dispose();
  }

  void _eingabe([Object? _]) => _letzteEingabe = widget.jetzt();

  /// Jede Taste zählt als Eingabe — verarbeitet wird sie woanders.
  bool _taste(KeyEvent ereignis) {
    _eingabe();
    return false;
  }

  void _pruefen() {
    if (!mounted || !ref.read(entwicklungEntsperrtProvider)) return;
    if (widget.jetzt().difference(_letzteEingabe) < widget.nach) return;
    widget.fensterSchliessen?.call();
    ref.read(entwicklungEntsperrtProvider.notifier).state = false;
    ref.read(entwicklungAutoGesperrtProvider.notifier).state = true;
    entwicklungTempLeeren();
  }

  @override
  Widget build(BuildContext context) {
    // Nach dem Entsperren zählt die Zeit von vorn.
    ref.listen<bool>(entwicklungEntsperrtProvider, (vorher, offen) {
      if (!offen) return;
      _eingabe();
      ref.read(entwicklungAutoGesperrtProvider.notifier).state = false;
    });
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _eingabe,
      onPointerMove: _eingabe,
      onPointerHover: _eingabe,
      onPointerSignal: _eingabe,
      child: widget.child,
    );
  }
}
