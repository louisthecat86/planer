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
