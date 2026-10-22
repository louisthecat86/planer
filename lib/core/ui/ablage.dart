import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_stil.dart';
import '../utils/ablage_dateien.dart';
import '../utils/fehler_text.dart';

export '../utils/ablage_dateien.dart';

// Dateien und Mails auf das Fenster ziehen: Unter Windows meldet das
// Fenster selbst (windows/runner/ablage_ziel.cpp) über den Kanal
// „planer/ablage", wo gezogen und losgelassen wird — auch Mails direkt aus
// Outlook, die es dafür in einen eigenen temporären Ordner schreibt. Hier
// landet das Losgelassene in der [AblageZone] unter dem Punkt; beim
// Darüberziehen zeigt sie, was damit geschieht. Auf anderen Systemen meldet
// das Fenster nichts — die Zonen bleiben still.

/// Nimmt ab jetzt entgegen, was auf das Fenster gezogen wird — auch dort,
/// wo keine Zone ist (dann räumt es die Kopien gleich weg) — und räumt
/// Kopien von früher weg. Einmal beim Start.
void ablageStarten() {
  _Ablage.instanz;
  unawaited(ablageAltesWegraeumen());
}

/// Was der Kanal vom Fenster bekommt.
class _Ablage {
  _Ablage._() {
    _kanal.setMethodCallHandler(_anruf);
  }

  static final _Ablage instanz = _Ablage._();

  static const MethodChannel _kanal = MethodChannel('planer/ablage');

  final List<_AblageZoneState> _zonen = [];
  _AblageZoneState? _aktiv;

  void anmelden(_AblageZoneState z) => _zonen.add(z);

  void abmelden(_AblageZoneState z) {
    _zonen.remove(z);
    if (identical(_aktiv, z)) _aktiv = null;
  }

  /// Der Punkt in logischen Pixeln — das Fenster meldet echte.
  Offset _punkt(Map<Object?, Object?> a) {
    final x = (a['x'] as num?)?.toDouble() ?? 0;
    final y = (a['y'] as num?)?.toDouble() ?? 0;
    final faktor = WidgetsBinding
            .instance.platformDispatcher.implicitView?.devicePixelRatio ??
        1.0;
    return Offset(x / faktor, y / faktor);
  }

  /// Die Zone unter [punkt] — bei mehreren die kleinste, also die
  /// innerste.
  _AblageZoneState? _zoneBei(Offset punkt) {
    _AblageZoneState? beste;
    double? flaeche;
    for (final z in _zonen) {
      final r = z.bereich();
      if (r == null || !r.contains(punkt)) continue;
      final f = r.width * r.height;
      if (flaeche == null || f < flaeche) {
        beste = z;
        flaeche = f;
      }
    }
    return beste;
  }

  void _aktivieren(_AblageZoneState? z) {
    if (identical(_aktiv, z)) return;
    _aktiv?.darueber(false);
    _aktiv = z;
    z?.darueber(true);
  }

  Future<Object?> _anruf(MethodCall anruf) async {
    final a = anruf.arguments is Map
        ? (anruf.arguments as Map).cast<Object?, Object?>()
        : const <Object?, Object?>{};
    switch (anruf.method) {
      case 'ueber':
        final z = _zoneBei(_punkt(a));
        _aktivieren(z);
        return z != null;
      case 'weg':
        _aktivieren(null);
        return null;
      case 'abgelegt':
        final z = _zoneBei(_punkt(a));
        _aktivieren(null);
        final pfade = [
          for (final x in a['pfade'] is List ? a['pfade'] as List : const [])
            if (x is String) x,
        ];
        final virtuell = a['virtuell'] == true;
        if (z == null || pfade.isEmpty) {
          if (virtuell) await ablageAufraeumen(pfade);
          return false;
        }
        unawaited(z.annehmen(pfade, virtuell: virtuell));
        return true;
    }
    return null;
  }
}

/// Ein Ziel für Dateien und Mails, die auf das Fenster gezogen werden:
/// Zieht man darüber, zeigt es [hinweis]; lässt man los, bekommt
/// [onAbgelegt] die Dateien. Liegen Zonen ineinander, gewinnt die
/// innerste; Zonen auf Seiten, die gerade nicht oben liegen, nehmen nichts
/// an.
class AblageZone extends StatefulWidget {
  const AblageZone({
    super.key,
    required this.hinweis,
    required this.onAbgelegt,
    required this.child,
    this.aktiv = true,
  });

  /// Was mit dem Losgelassenen geschieht: „Mail loslassen — neues
  /// Projekt daraus".
  final String hinweis;

  final Future<void> Function(List<AbgelegteDatei> dateien) onAbgelegt;
  final Widget child;

  /// Nimmt die Zone gerade etwas an?
  final bool aktiv;

  @override
  State<AblageZone> createState() => _AblageZoneState();
}

class _AblageZoneState extends State<AblageZone> {
  bool _darueber = false;
  bool _laeuft = false;
  ModalRoute<Object?>? _seite;
  bool _sichtbar = true;

  @override
  void initState() {
    super.initState();
    _Ablage.instanz.anmelden(this);
  }

  @override
  void dispose() {
    _Ablage.instanz.abmelden(this);
    super.dispose();
  }

  /// Wo die Zone auf dem Bildschirm liegt — null, wenn sie gerade nichts
  /// annimmt.
  Rect? bereich() {
    if (!mounted || !widget.aktiv || _laeuft || !_sichtbar) return null;
    final seite = _seite;
    if (seite != null && !seite.isCurrent) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void darueber(bool ja) {
    if (mounted && _darueber != ja) setState(() => _darueber = ja);
  }

  Future<void> annehmen(List<String> pfade, {required bool virtuell}) async {
    setState(() => _laeuft = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final gelesen = await ablageLesen(pfade);
      if (virtuell) await ablageAufraeumen(pfade);
      if (gelesen.dateien.isNotEmpty) await widget.onAbgelegt(gelesen.dateien);
      if (gelesen.fehlt.isNotEmpty) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text('Nicht abgelegt: ${gelesen.fehlt.join(', ')}'),
          ),
        );
      }
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Ablegen fehlgeschlagen: ${fehlerText(e)}')),
      );
    } finally {
      if (mounted) setState(() => _laeuft = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    _seite = ModalRoute.of(context);
    _sichtbar = TickerMode.valuesOf(context).enabled;
    final theme = Theme.of(context);
    final farbe = theme.colorScheme.primary;
    final zeigen = _darueber || _laeuft;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        if (zeigen)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                key: const ValueKey('ablage-zone-hinweis'),
                decoration: BoxDecoration(
                  color: farbe.withValues(alpha: 0.08),
                  border: Border.all(color: farbe, width: 2),
                  borderRadius: AppMasse.ecken,
                ),
                child: Center(
                  child: Material(
                    color: theme.colorScheme.surface,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppMasse.ecken,
                      side: BorderSide(color: farbe),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_laeuft)
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            Icon(Icons.move_to_inbox_outlined, color: farbe),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              _laeuft ? 'Wird abgelegt …' : widget.hinweis,
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
