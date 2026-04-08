import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/shell/home_screen.dart';
import 'features/shell/landing_screen.dart';
import 'features/shell/task_detail_screen.dart';
import 'features/backup/backup_management_screen.dart';
import 'core/database/database.dart';
import 'core/providers/database_provider.dart';

/// Root-Widget der App.
///
/// Aktuell gibt es drei Routes: Landing, Home und Backup-Management.
/// Man kann in Phase 1b mehr Routes hinzufügen.
class ProduktionPlanerApp extends ConsumerWidget {
  ProduktionPlanerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);

    final _router = GoRouter(
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
          path: '/backup',
          name: 'backup',
          builder: (context, state) => BackupManagementScreen(database: db),
        ),
        GoRoute(
          path: '/task/:taskId',
          name: 'taskDetail',
          builder: (context, state) {
            final taskId = state.params['taskId'];
            return TaskDetailScreen(
              database: db,
              taskId: taskId ?? '',
            );
          },
        ),
      ],
    );

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
