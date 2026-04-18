import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Intro-Screen: Schatten in der Mitte, der sich zu einem scharfen,
/// lesbaren "Produktions-Planer"-Schriftzug entwickelt.
///
/// Der Schriftzug startet:
///   - klein (scale 0.4) und stark unscharf (blur sigma 20)
///   - mit niedriger Opacity (0.15) — wie ein Schatten
///
/// Und endet:
///   - voll skaliert (scale 1.0) mit leichtem Overshoot
///   - scharf (blur 0)
///   - voll sichtbar (opacity 1.0)
///
/// Farben bewusst dunkel gehalten: tiefes Marineblau für "Produktions-"
/// und nahezu-schwarz für "Planer".
///
/// Tipp/Klick bricht die Animation ab und navigiert zur Landing-Page.
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _gesamtDauer = Duration(milliseconds: 2600);
  static const Duration _haltzeitAmEnde = Duration(milliseconds: 500);

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

    _opacity = Tween<double>(begin: 0.15, end: 1.0).animate(
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
    context.go('/');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _finish,
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  _buildGlow(),
                  _buildSchriftzug(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildGlow() {
    final intensity = _glow.value;
    return IgnorePointer(
      child: Container(
        width: 600,
        height: 400,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [
              const Color(0xFF1A237E).withValues(alpha: 0.18 * intensity),
              const Color(0xFF1A237E).withValues(alpha: 0),
            ],
            stops: const [0.0, 1.0],
          ),
        ),
      ),
    );
  }

  Widget _buildSchriftzug() {
    final blurValue = _blur.value;
    final scaleValue = _scale.value;
    final opacityValue = _opacity.value.clamp(0.0, 1.0);

    Widget text = const _SchriftzugText();

    // ImageFiltered erwartet einen echten ImageFilter — bei sigma ≈ 0
    // den Filter auslassen, weil GaussianBlur mit 0 unnötig teuer ist.
    if (blurValue > 0.01) {
      text = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: blurValue,
          sigmaY: blurValue,
        ),
        child: text,
      );
    }

    return Transform.scale(
      scale: scaleValue,
      child: Opacity(
        opacity: opacityValue,
        child: text,
      ),
    );
  }
}

/// Der eigentliche Schriftzug "Produktions-Planer" in Corporate-Farben.
class _SchriftzugText extends StatelessWidget {
  const _SchriftzugText();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RichText(
          textAlign: TextAlign.center,
          text: const TextSpan(
            children: [
              TextSpan(
                text: 'Produktions',
                style: TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A237E),
                  letterSpacing: 1.5,
                  height: 1.0,
                ),
              ),
              TextSpan(
                text: '-',
                style: TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.w300,
                  color: Color(0xFF455A64),
                  letterSpacing: 1.5,
                  height: 1.0,
                ),
              ),
              TextSpan(
                text: 'Planer',
                style: TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0D1117),
                  letterSpacing: 1.5,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: 120,
          height: 2,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF1A237E).withValues(alpha: 0),
                const Color(0xFF1A237E).withValues(alpha: 0.6),
                const Color(0xFF0D1117).withValues(alpha: 0.6),
                const Color(0xFF0D1117).withValues(alpha: 0),
              ],
              stops: const [0.0, 0.3, 0.7, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}