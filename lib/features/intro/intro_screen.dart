import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Intro-Screen im Navision-Design.
///
/// Eine Logo-Kachel (Zahnrad auf Primär-Verlauf, wie die Home-Kacheln)
/// und der Schriftzug "Produktion Planer" entwickeln sich aus einem
/// unscharfen Schatten zu einem scharfen, hellen Erscheinungsbild:
///   - Start: klein (scale 0.4), stark unscharf (blur 20), fast unsichtbar
///   - Ende: voll skaliert (leichter Overshoot), scharf, voll sichtbar
///
/// Hintergrund: derselbe abgestufte Dunkelverlauf wie die App-Flächen
/// (0xFF121417 → 0xFF1C2025), dazu ein dezenter Glow in Primärfarbe.
///
/// Tipp/Klick bricht die Animation ab und navigiert direkt zum Home.
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _gesamtDauer = Duration(milliseconds: 2400);
  static const Duration _haltzeitAmEnde = Duration(milliseconds: 450);

  late final AnimationController _controller;
  late final Animation<double> _blur;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;
  late final Animation<double> _glow;

  bool _alreadyNavigating = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _gesamtDauer,
    );

    _blur = Tween<double>(begin: 20, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.75, curve: Curves.easeOutCubic),
      ),
    );

    _scale = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.85, curve: Curves.easeOutBack),
      ),
    );

    _opacity = Tween<double>(begin: 0.1, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeIn),
      ),
    );

    _glow = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 0.9, curve: Curves.easeInOut),
      ),
    );

    _controller.forward().whenComplete(() async {
      await Future<void>.delayed(_haltzeitAmEnde);
      if (mounted) _finish();
    });
  }

  void _finish() {
    if (_alreadyNavigating) return;
    _alreadyNavigating = true;
    context.go('/home');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _finish,
        child: DecoratedBox(
          // Ruhige, einfarbige Fläche im Navision-Stil — kein Verlauf.
          // Folgt dem Theme, damit Hell- und Dunkelmodus zusammenpassen.
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
          ),
          child: Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    _buildGlow(context),
                    _buildInhalt(),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlow(BuildContext context) {
    final intensity = _glow.value;
    return IgnorePointer(
      child: Container(
        width: 640,
        height: 460,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [
              Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.10 * intensity),
              Theme.of(context).colorScheme.primary.withValues(alpha: 0),
            ],
            stops: const [0.0, 1.0],
          ),
        ),
      ),
    );
  }

  Widget _buildInhalt() {
    final blurValue = _blur.value;
    final scaleValue = _scale.value;
    final opacityValue = _opacity.value.clamp(0.0, 1.0);

    Widget inhalt = const _IntroInhalt();

    // ImageFiltered erwartet einen echten ImageFilter — bei sigma ≈ 0
    // den Filter auslassen, weil GaussianBlur mit 0 unnötig teuer ist.
    if (blurValue > 0.01) {
      inhalt = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: blurValue,
          sigmaY: blurValue,
        ),
        child: inhalt,
      );
    }

    return Transform.scale(
      scale: scaleValue,
      child: Opacity(
        opacity: opacityValue,
        child: inhalt,
      ),
    );
  }
}

/// Schriftzug mit gezeichnetem Steak — bewusst reduziert im Stil von
/// Microsoft Dynamics NAV: eine Akzentfarbe, kantige Formen, kein Verlauf,
/// kein Untertitel.
class _IntroInhalt extends StatelessWidget {
  const _IntroInhalt();

  @override
  Widget build(BuildContext context) {
    final farbe = Theme.of(context).colorScheme.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Nutze das saubere Steak-PNG mit transparentem Hintergrund statt der
        // selbst gezeichneten Platzhalter-Version. Das Bild passt farblich zum
        // blauen Navision-Theme der App.
        SizedBox(
          width: 200,
          height: 120,
          child: Image.asset(
            'assets/intro/steak_blue.png',
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Produktions Planer',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 42,
            fontWeight: FontWeight.w700,
            color: farbe,
            letterSpacing: 0.5,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 16),
        // Schlichte Linie statt Verlauf — NAV trennt mit dünnen Kanten.
        Container(width: 190, height: 2, color: farbe.withValues(alpha: 0.5)),
      ],
    );
  }
}

/// Zeichnet ein Steak in Draufsicht — angelehnt an die Comic-Vorlage:
/// heller Fettrand außen, dunklere Fleischfläche innen, die von Y-förmigen
/// Fettadern in Segmente geteilt wird, und ein runder Knochen in der Mitte.
///
/// Alles entsteht aus EINER Farbe (der Schriftfarbe) in verschiedenen
/// Deckkraft-Stufen, damit Logo und Schriftzug zusammengehören und die
/// Zeichnung in Hell- wie Dunkelmodus funktioniert.
class _SteakPainter extends CustomPainter {
  _SteakPainter(this.farbe);

  final Color farbe;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ── Umriss: liegendes Oval mit leichter Delle rechts unten ──────
    // Bewusst ohne Matrix-Transformation aufgebaut: Die Innenform entsteht
    // aus denselben relativen Punkten, nur zur Mitte hin gestaucht. Das
    // spart eine Abhängigkeit von Matrix4 (dort ist `translate` inzwischen
    // veraltet) und bleibt gut lesbar.
    Path formMit(double faktorX, double faktorY) {
      Offset p(double fx, double fy) => Offset(
            w * (0.5 + (fx - 0.5) * faktorX),
            h * (0.5 + (fy - 0.5) * faktorY),
          );
      final pfad = Path()..moveTo(p(0.30, 0.08).dx, p(0.30, 0.08).dy);
      void kurve(
        double x1,
        double y1,
        double x2,
        double y2,
        double x3,
        double y3,
      ) {
        final a = p(x1, y1);
        final b = p(x2, y2);
        final c = p(x3, y3);
        pfad.cubicTo(a.dx, a.dy, b.dx, b.dy, c.dx, c.dy);
      }

      kurve(0.62, 0.00, 0.95, 0.10, 0.97, 0.40);
      kurve(0.99, 0.62, 0.86, 0.74, 0.72, 0.86);
      kurve(0.58, 0.98, 0.32, 1.00, 0.17, 0.86);
      kurve(0.02, 0.72, 0.01, 0.36, 0.10, 0.22);
      kurve(0.16, 0.13, 0.22, 0.10, 0.30, 0.08);
      return pfad..close();
    }

    final umriss = formMit(1, 1);

    // Fettrand (hell) — die gesamte Fläche.
    canvas.drawPath(umriss, Paint()..color = farbe.withValues(alpha: 0.20));

    // ── Fleisch: dieselbe Form, zur Mitte hin gestaucht ─────────────
    final fleisch = formMit(0.80, 0.76);
    canvas.drawPath(fleisch, Paint()..color = farbe.withValues(alpha: 0.55));

    // ── Fettadern: drei Striche vom Knochen nach außen (Y-Form) ─────
    // Sie werden auf die Fleischfläche beschnitten, damit sie nicht in
    // den Fettrand laufen.
    canvas.save();
    canvas.clipPath(fleisch);
    final ader = Paint()
      ..color = farbe.withValues(alpha: 0.20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.075
      ..strokeCap = StrokeCap.round;
    final mitte = Offset(w * 0.42, h * 0.48);
    for (final winkel in [-1.9, 0.35, 1.85]) {
      canvas.drawLine(
        mitte,
        mitte + Offset(w * 0.9 * math.cos(winkel), h * 0.9 * math.sin(winkel)),
        ader,
      );
    }
    canvas.restore();

    // ── Knochen: heller Kreis in der Mitte ──────────────────────────
    canvas.drawCircle(
      mitte,
      w * 0.085,
      Paint()..color = farbe.withValues(alpha: 0.22),
    );
    canvas.drawCircle(
      mitte,
      w * 0.085,
      Paint()
        ..color = farbe.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // ── Außenkante zuletzt, damit sie sauber obenauf liegt ──────────
    canvas.drawPath(
      umriss,
      Paint()
        ..color = farbe
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SteakPainter old) => old.farbe != farbe;
}
