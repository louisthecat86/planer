import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Intro-Screen im dunklen App-Design.
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
        // Lebensmittel statt Maschine: ein Comic-Steak in derselben Farbe
        // wie der Schriftzug — die App plant Fleischverarbeitung, kein
        // Roboterwerk.
        SizedBox(
          width: 132,
          height: 96,
          child: CustomPaint(painter: _SteakPainter(farbe)),
        ),
        const SizedBox(height: 26),
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

/// Zeichnet ein stilisiertes T-Bone-Steak in einer einzigen Farbe.
///
/// Bewusst als Zeichnung und nicht als Icon: Material bietet kein Steak,
/// und so lässt sich die Form exakt an die Schriftfarbe koppeln.
class _SteakPainter extends CustomPainter {
  _SteakPainter(this.farbe);

  final Color farbe;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final fuellung = Paint()
      ..color = farbe.withValues(alpha: 0.16)
      ..style = PaintingStyle.fill;
    final kante = Paint()
      ..color = farbe
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeJoin = StrokeJoin.round;

    // Umriss: unregelmäßige, „fleischige" Rundung.
    final fleisch = Path()
      ..moveTo(w * 0.30, h * 0.12)
      ..cubicTo(w * 0.62, h * 0.02, w * 0.98, h * 0.20, w * 0.94, h * 0.50)
      ..cubicTo(w * 0.90, h * 0.80, w * 0.62, h * 0.97, w * 0.38, h * 0.90)
      ..cubicTo(w * 0.18, h * 0.84, w * 0.10, h * 0.62, w * 0.14, h * 0.42)
      ..cubicTo(w * 0.17, h * 0.26, w * 0.22, h * 0.16, w * 0.30, h * 0.12)
      ..close();
    canvas.drawPath(fleisch, fuellung);
    canvas.drawPath(fleisch, kante);

    // Knochen: der klassische T-Bone am linken Rand.
    final knochen = Paint()
      ..color = farbe
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(w * 0.30, h * 0.30),
      Offset(w * 0.30, h * 0.74),
      knochen,
    );
    canvas.drawLine(
      Offset(w * 0.30, h * 0.52),
      Offset(w * 0.52, h * 0.52),
      knochen,
    );

    // Zwei kurze Striche als Grill-/Maserungsandeutung.
    final maserung = Paint()
      ..color = farbe.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(w * 0.62, h * 0.30),
      Offset(w * 0.78, h * 0.38),
      maserung,
    );
    canvas.drawLine(
      Offset(w * 0.58, h * 0.66),
      Offset(w * 0.76, h * 0.72),
      maserung,
    );
  }

  @override
  bool shouldRepaint(covariant _SteakPainter old) => old.farbe != farbe;
}
