import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/providers/theme_mode_provider.dart';
import 'core/providers/ui_scale_provider.dart';
import 'core/providers/database_provider.dart';
import 'core/services/backup_service.dart';
import 'core/theme/app_theme.dart';
import 'features/articles/article_detail_screen.dart';
import 'features/articles/article_list_screen.dart';
import 'features/backup/backup_management_screen.dart';
import 'features/bedarf/bedarf_screen.dart';
import 'features/erfassung/produktion_erfassung_screen.dart';
import 'features/board/week_board_screen.dart';
import 'features/data_management/data_management_screen.dart';
import 'features/history/week_snapshot_archive_screen.dart';
import 'features/history/week_snapshot_detail_screen.dart';
import 'features/import/excel_import_screen.dart';
import 'features/intro/intro_screen.dart';
import 'features/settings/maschinen_katalog_screen.dart';
import 'features/settings/parameter_grenzen_screen.dart';
import 'features/settings/settings_screen.dart';
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
        pageBuilder: (context, state) => const NoTransitionPage(
          child: IntroScreen(),
        ),
      ),
      GoRoute(
        path: '/home',
        name: 'home',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: HomeScreen(),
        ),
      ),
      // Artikel-Stammdaten (Abläufe, Zeiten, Mengen, Maschinen).
      GoRoute(
        path: '/articles',
        name: 'articles',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: ArticleListScreen(),
        ),
      ),
      GoRoute(
        path: '/article/:productId',
        name: 'articleDetail',
        pageBuilder: (context, state) {
          final productId = state.pathParameters['productId']!;
          return NoTransitionPage(
            child: ArticleDetailScreen(productId: productId),
          );
        },
      ),
      // Bedarfsliste: WAS muss produziert werden (Auslöser der Planung).
      GoRoute(
        path: '/bedarf',
        name: 'bedarf',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: BedarfScreen(),
        ),
      ),
      // Produktionserfassung: geplante Woche als Liste, Ist-Daten erfassen.
      GoRoute(
        path: '/erfassung',
        name: 'erfassung',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: ProduktionErfassungScreen(),
        ),
      ),
      // Planung ansehen: das Board (Woche/Tag).
      GoRoute(
        path: '/board',
        name: 'board',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: WeekBoardScreen(),
        ),
      ),
      // Planen: dasselbe Board, öffnet direkt den Produkt-planen-Dialog.
      GoRoute(
        path: '/board/planen',
        name: 'boardPlanen',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: WeekBoardScreen(oeffnePlanenDirekt: true),
        ),
      ),
      GoRoute(
        path: '/history',
        name: 'wochenHistorie',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: WeekSnapshotArchiveScreen(),
        ),
      ),
      GoRoute(
        path: '/history/:snapshotId',
        name: 'wochenHistorieDetail',
        pageBuilder: (context, state) => NoTransitionPage(
          child: WeekSnapshotDetailScreen(
            snapshotId: state.pathParameters['snapshotId']!,
          ),
        ),
      ),
      // Einstellungen: Sammelpunkt für Stammdaten/Excel/Backup + Kapazität.
      // Maschinen-Katalog: Anlagen + Parameter-Steckbriefe pflegen.
      GoRoute(
        path: '/maschinen',
        name: 'maschinen',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: MaschinenKatalogScreen(),
        ),
      ),
      // Plausibilitätsgrenzen für Maschinen-/Prozessparameter.
      GoRoute(
        path: '/grenzen',
        name: 'grenzen',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: ParameterGrenzenScreen(),
        ),
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: SettingsScreen(),
        ),
      ),
      // Daten-Screen (Excel-Import/-Export, Backup, Restore) — von den
      // Einstellungen aus verlinkt.
      GoRoute(
        path: '/data',
        name: 'data',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: DataManagementScreen(),
        ),
      ),
      // Einzel-Screens, erreichbar aus dem Daten-Screen heraus.
      GoRoute(
        path: '/backup',
        name: 'backup',
        pageBuilder: (context, state) => NoTransitionPage(
          child: BackupManagementScreen(database: db),
        ),
      ),
      GoRoute(
        path: '/import',
        name: 'import',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: ExcelImportScreen(),
        ),
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
    // Anzeigemodus kommt jetzt aus den Einstellungen (dauerhaft gespeichert).
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'Produktion Planer',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      // App-weite Skalierung: in den Einstellungen frei wählbar (25 %…200 %).
      //
      // Ziel: größer darstellen, aber der Inhalt bricht UM statt rechts aus
      // dem Bild zu laufen. Zwei Schritte, die zusammengehören:
      //  1. Wir zwingen den Inhalt in eine um den Faktor SCHMALERE Fläche
      //     (SizedBox width = Bildschirm / scale). Dadurch bekommt jeder
      //     LayoutBuilder darin weniger Breite gemeldet und bricht seine
      //     Kacheln/Reihen korrekt um — das ist der entscheidende Punkt.
      //  2. Diese schmalere Fläche skalieren wir per Transform wieder auf
      //     die volle Bildschirmbreite hoch. Ergebnis: alles größer, aber
      //     nichts ragt über den Rand.
      // Die MediaQuery-Größe wird passend mitgesetzt, damit auch Widgets,
      // die sich auf MediaQuery.size stützen, dieselbe kleinere Fläche sehen.
      builder: (context, child) {
        final safe = child ?? const SizedBox.shrink();
        final scale = ref.watch(uiScaleProvider);
        if (scale == 1.0) return safe;
        final mq = MediaQuery.of(context);
        final logischeGroesse = mq.size / scale;
        return MediaQuery(
          data: mq.copyWith(size: logischeGroesse),
          child: FittedBox(
            fit: BoxFit.fill,
            child: SizedBox(
              width: logischeGroesse.width,
              height: logischeGroesse.height,
              child: safe,
            ),
          ),
        );
      },
    );
  }
}
