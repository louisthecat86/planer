import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/providers/database_provider.dart';
import 'core/theme/app_theme.dart';
import 'features/articles/article_detail_screen.dart';
import 'features/articles/article_list_screen.dart';
import 'features/backup/backup_management_screen.dart';
import 'features/board/week_board_screen.dart';
import 'features/data_management/data_management_screen.dart';
import 'features/import/excel_import_screen.dart';
import 'features/intro/intro_screen.dart';
import 'features/shell/capacity_detail_screen.dart';
import 'features/shell/home_screen.dart';
import 'features/shell/task_detail_screen.dart';
import 'features/shell/tasks_detail_screen.dart';

/// GoRouter-Provider.
///
/// Der Router wird einmalig erzeugt und über die gesamte App-Lebensdauer
/// wiederverwendet. Erstellt man ihn in build(), geht bei jedem Rebuild
/// der Navigations-Zustand verloren.
///
/// Die App startet auf `/intro` (Intro-Animation). Nach der Animation
/// geht es direkt zum Dashboard (`/home`). Datenoperationen laufen über
/// das Datei-Icon in der AppBar (führt zu `/data`).
final routerProvider = Provider<GoRouter>((ref) {
  final db = ref.watch(databaseProvider);
  final router = GoRouter(
    initialLocation: '/intro',
    routes: [
      GoRoute(
        path: '/intro',
        name: 'intro',
        builder: (context, state) => const IntroScreen(),
      ),
      GoRoute(
        path: '/home',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      // Zentraler Daten-Screen (Excel-Import/-Export, Backup, Restore).
      GoRoute(
        path: '/data',
        name: 'data',
        builder: (context, state) => const DataManagementScreen(),
      ),
      // Planungsboard (Wochenboard + Tagesübersicht).
      GoRoute(
        path: '/board',
        name: 'board',
        builder: (context, state) => const WeekBoardScreen(),
      ),
      // Alte Routen — bleiben erst mal als Notausgang erreichbar,
      // werden aber von der UI nicht mehr direkt verlinkt. Können später
      // entfernt werden.
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
        path: '/capacity',
        name: 'capacity',
        builder: (context, state) => const CapacityDetailScreen(),
      ),
      GoRoute(
        path: '/tasks',
        name: 'tasks',
        builder: (context, state) => const TasksDetailScreen(),
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