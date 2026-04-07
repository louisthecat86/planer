import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';
import 'features/shell/home_screen.dart';

/// Root-Widget der App.
///
/// Aktuell gibt es nur eine Route. Der [GoRouter] ist trotzdem schon hier,
/// damit die Router-Struktur in Phase 1b ohne Umbau erweitert werden kann.
class ProduktionPlanerApp extends StatelessWidget {
  ProduktionPlanerApp({super.key});

  final _router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Produktion Planer',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
