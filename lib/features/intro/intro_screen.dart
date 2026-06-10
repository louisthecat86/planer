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
          // Abgestufter Dunkelverlauf — dieselben Flächen wie das Theme.
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF121417), Color(0xFF1C2025)],
            ),
          ),
          child: Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    _buildGlow(),
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

  Widget _buildGlow() {
    final intensity = _glow.value;
    return IgnorePointer(
      child: Container(
        width: 640,
        height: 460,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [
              const Color(0xFF607D8B).withValues(alpha: 0.22 * intensity),
              const Color(0xFF607D8B).withValues(alpha: 0),
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

/// Logo-Kachel + Schriftzug in der dunklen Designsprache der App.
class _IntroInhalt extends StatelessWidget {
  const _IntroInhalt();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Logo-Kachel — gleiche Formensprache wie die Home-Kacheln
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF546E7A), Color(0xFF37474F)],
            ),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(
            Icons.precision_manufacturing_rounded,
            size: 56,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 28),
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            children: [
              const TextSpan(
                text: 'Produktion ',
                style: TextStyle(
                  fontSize: 46,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 1.2,
                  height: 1.0,
                ),
              ),
              TextSpan(
                text: 'Planer',
                style: TextStyle(
                  fontSize: 46,
                  fontWeight: FontWeight.w300,
                  color: Colors.white.withValues(alpha: 0.75),
                  letterSpacing: 1.2,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Feine Trennlinie mit Verlauf
        Container(
          width: 140,
          height: 2,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0),
                Colors.white.withValues(alpha: 0.45),
                Colors.white.withValues(alpha: 0),
              ],
            ),
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Planung · Prozesse · Produktion',
          style: TextStyle(
            fontSize: 14,
            letterSpacing: 2.5,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}