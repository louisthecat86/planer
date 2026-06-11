import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/providers/database_provider.dart';
import 'core/services/backup_service.dart';
import 'core/theme/app_theme.dart';
import 'features/articles/article_detail_screen.dart';
import 'features/articles/article_list_screen.dart';
import 'features/backup/backup_management_screen.dart';
import 'features/board/week_board_screen.dart';
import 'features/data_management/data_management_screen.dart';
import 'features/history/week_snapshot_archive_screen.dart';
import 'features/history/week_snapshot_detail_screen.dart';
import 'features/import/excel_import_screen.dart';
import 'features/intro/intro_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shell/capacity_detail_screen.dart';
import 'features/shell/home_screen.dart';

/// GoRouter-Provider.
///
/// Der Router wird einmalig erzeugt und über die gesamte App-Lebensdauer
/// wiederverwendet. Erstellt man ihn in build(), geht bei jedem Rebuild
/// der Navigations-Zustand verloren.
///
/// Die App startet auf `/intro` (Intro-Animation). Nach der Animation
/// geht es zum Home (`/home`): Artikel · Planung · Wochen-Historie ·
/// Einstellungen. Stammdaten/Excel/Backup und die Kapazität sitzen
/// unter `/settings`.
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
      // Artikel-Stammdaten (Abläufe, Zeiten, Mengen, Maschinen).
      GoRoute(
        path: '/articles',
        name: 'articles',
        builder: (context, state) => const ArticleListScreen(),
      ),
      GoRoute(
        path: '/article/:productId',
        name: 'articleDetail',
        builder: (context, state) {
          final productId = state.pathParameters['productId']!;
          return ArticleDetailScreen(productId: productId);
        },
      ),
      // Planung ansehen: das Board (Woche/Tag).
      GoRoute(
        path: '/board',
        name: 'board',
        builder: (context, state) => const WeekBoardScreen(),
      ),
      // Planen: dasselbe Board, öffnet direkt den Produkt-planen-Dialog.
      GoRoute(
        path: '/board/planen',
        name: 'boardPlanen',
        builder: (context, state) =>
            const WeekBoardScreen(oeffnePlanenDirekt: true),
      ),
      GoRoute(
        path: '/history',
        name: 'wochenHistorie',
        builder: (context, state) => const WeekSnapshotArchiveScreen(),
      ),
      GoRoute(
        path: '/history/:snapshotId',
        name: 'wochenHistorieDetail',
        builder: (context, state) => WeekSnapshotDetailScreen(
          snapshotId: state.pathParameters['snapshotId']!,
        ),
      ),
      // Einstellungen: Sammelpunkt für Stammdaten/Excel/Backup + Kapazität.
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      // Daten-Screen (Excel-Import/-Export, Backup, Restore) — von den
      // Einstellungen aus verlinkt.
      GoRoute(
        path: '/data',
        name: 'data',
        builder: (context, state) => const DataManagementScreen(),
      ),
      GoRoute(
        path: '/capacity',
        name: 'capacity',
        builder: (context, state) => const CapacityDetailScreen(),
      ),
      // Einzel-Screens, erreichbar aus dem Daten-Screen heraus.
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
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// Root-Widget der App.
class ProduktionPlanerApp extends ConsumerStatefulWidget {
  const ProduktionPlanerApp({super.key});

  @override
  ConsumerState<ProduktionPlanerApp> createState() =>
      _ProduktionPlanerAppState();
}

class _ProduktionPlanerAppState extends ConsumerState<ProduktionPlanerApp> {
  AppLifecycleListener? _lifecycle;
  bool _exitBackupGestartet = false;

  @override
  void initState() {
    super.initState();
    // Beim Schließen der App (Fenster-X, Alt+F4, App beenden) wird
    // automatisch ein Backup erstellt — so ist der letzte Stand immer
    // gesichert, ohne dass man daran denken muss.
    _lifecycle = AppLifecycleListener(
      onExitRequested: _backupBeimBeenden,
    );
  }

  Future<AppExitResponse> _backupBeimBeenden() async {
    if (_exitBackupGestartet) return AppExitResponse.exit;
    _exitBackupGestartet = true;
    try {
      final db = ref.read(databaseProvider);
      await BackupService.createAutoBackup(db)
          .timeout(const Duration(seconds: 10));
      await BackupService.cleanupOldAutoBackups()
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Das Beenden darf nie blockieren — im Zweifel ohne frisches
      // Backup schließen (die Debounce-Backups existieren weiterhin).
    }
    return AppExitResponse.exit;
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    // Windows-Build fest im Dunkelmodus; andere Plattformen folgen dem System.
    final themeMode = Platform.isWindows ? ThemeMode.dark : ThemeMode.system;
    return MaterialApp.router(
      title: 'Produktion Planer',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      // App-weit etwas größere Schrift (bessere Lesbarkeit am Desktop).
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: const TextScaler.linear(1.15)),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}