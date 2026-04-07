import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:produktion_planer/features/products/product_list_screen.dart';

final _router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      name: 'home',
      builder: (context, state) => const ProductListScreen(),
    ),
  ],
);

class ProduktionPlanerApp extends StatelessWidget {
  const ProduktionPlanerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Produktion Planer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red.shade700),
        useMaterial3: true,
      ),
      routerConfig: _router,
    );
  }
}
