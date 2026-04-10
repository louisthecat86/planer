import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/shell/home_screen.dart';
import 'features/shell/landing_screen.dart';
import 'features/shell/task_detail_screen.dart';
import 'features/backup/backup_management_screen.dart';
import 'features/whiteboard/whiteboard_screen.dart';
import 'features/import/excel_import_screen.dart';
import 'features/articles/article_list_screen.dart';
import 'features/articles/article_detail_screen.dart';
import 'features/shell/personnel_detail_screen.dart';
import 'core/providers/database_provider.dart';

/// GoRouter-Provider.
///
/// Der Router wird einmalig erzeugt und über die gesamte App-Lebensdauer
/// wiederverwendet. Erstellt man ihn in build(), geht bei jedem Rebuild
/// der Navigations-Zustand verloren.
final routerProvider = Provider<GoRouter>((ref) {
  final db = ref.watch(databaseProvider);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        name: 'landing',
        builder: (context, state) => LandingScreen(database: db),
      ),
      GoRoute(
        path: '/home',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/whiteboard',
        name: 'whiteboard',
        builder: (context, state) => const WhiteboardScreen(),
      ),
      GoRoute(
        path: '/backup',
        name: 'backup',
        builder: (context, state) => BackupManagementScreen(database: db),
      ),
      GoRoute(
        path: '/import',
        name: 'import',
        builder: (context, state) => const ExcelImportScreen(),
      ),
      GoRoute(
        path: '/articles',
        name: 'articles',
        builder: (context, state) => const ArticleListScreen(),
      ),
      GoRoute(
        path: '/personnel',
        name: 'personnel',
        builder: (context, state) => const PersonnelDetailScreen(),
      ),
      GoRoute(
        path: '/article/:productId',
        name: 'articleDetail',
        builder: (context, state) {
          final productId = state.pathParameters['productId']!;
          return ArticleDetailScreen(productId: productId);
        },
      ),
      GoRoute(
        path: '/task/:taskId',
        name: 'taskDetail',
        builder: (context, state) {
          final taskId = state.pathParameters['taskId'];
          return TaskDetailScreen(
            database: db,
            taskId: taskId ?? '',
          );
        },
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// Root-Widget der App.
class ProduktionPlanerApp extends ConsumerWidget {
  const ProduktionPlanerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Produktion Planer',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
