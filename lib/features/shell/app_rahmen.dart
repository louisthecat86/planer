import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/backup_service.dart';
import '../../core/theme/app_stil.dart';
import '../../core/utils/vollbild.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Rahmen der App: Navigationsleiste links, die Seite rechts
// ═══════════════════════════════════════════════════════════════════════════
//
// Wie der Navigationsbereich in Navision: immer sichtbar, die aktive Seite
// hervorgehoben, jeder Bereich einen Klick entfernt. Vorher führte jeder
// Wechsel über die Startseite — zurück, Kasten aufklappen, Ziel wählen.
//
// Unten in der Leiste sitzen die Fensterknöpfe. Die App läuft im
// Vollbild, ohne Titelleiste — bisher gab es Minimieren und Beenden nur auf
// der Startseite.

/// Schlüssel für „Leiste eingeklappt" in der `app_settings`-Tabelle.
const String kNavigationEingeklapptKey = 'navigation_eingeklappt';

/// Ob die Navigationsleiste nur Symbole zeigt. Wird gespeichert und gilt
/// beim nächsten Start wieder.
class NavigationsleisteNotifier extends StateNotifier<bool> {
  /// Ohne [_db] (in Tests) wird nichts gespeichert.
  NavigationsleisteNotifier(this._db) : super(false) {
    _laden();
  }

  final AppDatabase? _db;

  Future<void> _laden() async {
    final db = _db;
    if (db == null) return;
    final row = await (db.select(db.appSettings)
          ..where((t) => t.key.equals(kNavigationEingeklapptKey))
          ..limit(1))
        .getSingleOrNull();
    if (mounted && row?.value == 'ja') state = true;
  }

  Future<void> umschalten() async {
    state = !state;
    final db = _db;
    if (db == null) return;
    // In einem Schritt anlegen oder überschreiben — zwei schnelle Klicks
    // stoßen so nicht auf denselben Schlüssel.
    await db.into(db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: kNavigationEingeklapptKey,
            value: state ? 'ja' : 'nein',
            updatedAt: Value(DateTime.now()),
          ),
        );
  }
}

final navigationEingeklapptProvider =
    StateNotifierProvider<NavigationsleisteNotifier, bool>(
  (ref) => NavigationsleisteNotifier(ref.watch(databaseProvider)),
);

/// Ein Ziel der Navigation.
class _Ziel {
  const _Ziel(this.name, this.titel, this.icon, this.pfade);

  /// Name der Route (go_router).
  final String name;
  final String titel;
  final IconData icon;

  /// Pfadanfänge, unter denen der Eintrag hervorgehoben ist — auch für
  /// Unterseiten wie die Stammdaten eines Artikels.
  final List<String> pfade;

  bool passt(String ort) =>
      pfade.any((p) => ort == p || ort.startsWith('$p/'));
}

/// Die Bereiche, nach Arbeitsschritten gruppiert. `null` als Titel: ohne
/// Überschrift (die Übersicht ganz oben).
const List<(String?, List<_Ziel>)> _gruppen = [
  (
    null,
    [
      _Ziel('home', 'Übersicht', Icons.space_dashboard_outlined, ['/home']),
    ],
  ),
  (
    'Planen',
    [
      _Ziel('bedarf', 'Bedarf', Icons.assignment_outlined, ['/bedarf']),
      _Ziel(
        'auftragsbestand',
        'Auftragsbestand',
        Icons.local_shipping_outlined,
        ['/auftragsbestand'],
      ),
      _Ziel(
        'planungsvorschlag',
        'Planungsvorschlag',
        Icons.auto_awesome_outlined,
        ['/planungsvorschlag'],
      ),
      _Ziel('board', 'Planungsboard', Icons.view_week_outlined, ['/board']),
    ],
  ),
  (
    'Auswerten',
    [
      _Ziel(
        'erfassung',
        'Produktionserfassung',
        Icons.fact_check_outlined,
        ['/erfassung'],
      ),
      _Ziel(
        'wochenHistorie',
        'Wochen-Historie',
        Icons.history_outlined,
        ['/history'],
      ),
    ],
  ),
  (
    'Stammdaten',
    [
      _Ziel(
        'articles',
        'Artikel',
        Icons.inventory_2_outlined,
        ['/articles', '/article'],
      ),
      _Ziel(
        'navisionImport',
        'Navision-Artikel',
        Icons.swap_horiz_outlined,
        ['/navision'],
      ),
      _Ziel(
        'maschinen',
        'Maschinen-Katalog',
        Icons.precision_manufacturing_outlined,
        ['/maschinen', '/grenzen'],
      ),
    ],
  ),
];

/// Einstellungen stehen unten, getrennt von der Arbeit.
const _Ziel _einstellungen = _Ziel(
  'settings',
  'Einstellungen',
  Icons.settings_outlined,
  ['/settings', '/data', '/backup'],
);

/// Der Rahmen um jede Seite der App.
class AppRahmen extends ConsumerWidget {
  const AppRahmen({super.key, required this.ort, required this.child});

  /// Aktueller Pfad, etwa „/board" — bestimmt den hervorgehobenen Eintrag.
  final String ort;

  /// Die Seite.
  final Widget child;

  /// Unter dieser Breite zeigt die Leiste nur Symbole, damit der Seite
  /// genug Platz bleibt.
  static const double _schmalUnter = 1000;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gewaehlt = ref.watch(navigationEingeklapptProvider);
    return LayoutBuilder(
      builder: (context, c) {
        final schmal = c.maxWidth < _schmalUnter;
        return Material(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Navigationsleiste(
                ort: ort,
                eingeklappt: gewaehlt || schmal,
                umschaltbar: !schmal,
              ),
              Expanded(child: child),
            ],
          ),
        );
      },
    );
  }
}

class _Navigationsleiste extends StatelessWidget {
  const _Navigationsleiste({
    required this.ort,
    required this.eingeklappt,
    required this.umschaltbar,
  });

  final String ort;
  final bool eingeklappt;

  /// false, wenn das Fenster zu schmal für die offene Leiste ist.
  final bool umschaltbar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = AppFarben.von(context);

    return Container(
      width: eingeklappt ? AppMasse.leisteSchmal : AppMasse.leisteBreit,
      decoration: BoxDecoration(
        color: f.leiste,
        border: Border(right: BorderSide(color: theme.colorScheme.outline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Kopf(eingeklappt: eingeklappt),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final (titel, ziele) in _gruppen) ...[
                  if (titel != null)
                    _Gruppentitel(titel: titel, eingeklappt: eingeklappt),
                  for (final z in ziele)
                    _Eintrag(
                      ziel: z,
                      aktiv: z.passt(ort),
                      eingeklappt: eingeklappt,
                    ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outline),
          const SizedBox(height: 4),
          _Eintrag(
            ziel: _einstellungen,
            aktiv: _einstellungen.passt(ort),
            eingeklappt: eingeklappt,
          ),
          const SizedBox(height: 4),
          _Fensterknoepfe(
            eingeklappt: eingeklappt,
            umschaltbar: umschaltbar,
          ),
        ],
      ),
    );
  }
}

/// Name der App oben in der Leiste — so hoch wie die Kopfzeile der Seiten,
/// damit beide Linien durchlaufen.
class _Kopf extends StatelessWidget {
  const _Kopf({required this.eingeklappt});

  final bool eingeklappt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final marke = Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: AppMasse.ecken,
      ),
      child: Text(
        'PP',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: theme.colorScheme.onPrimary,
          letterSpacing: 0.5,
        ),
      ),
    );

    return Container(
      height: kToolbarHeight,
      padding: EdgeInsets.symmetric(horizontal: eingeklappt ? 0 : 14),
      alignment: eingeklappt ? Alignment.center : Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outline),
        ),
      ),
      child: eingeklappt
          ? Tooltip(message: 'Produktion Planer', child: marke)
          : Row(
              children: [
                marke,
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Produktion Planer',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Gruppentitel extends StatelessWidget {
  const _Gruppentitel({required this.titel, required this.eingeklappt});

  final String titel;
  final bool eingeklappt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Eingeklappt trennt eine Linie die Gruppen — für Text ist kein Platz.
    if (eingeklappt) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Divider(height: 1, color: theme.colorScheme.outline),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
      child: Text(
        titel.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Ein Eintrag: Symbol und Name. Der aktive hat links einen Balken in der
/// Akzentfarbe und einen hellblauen Grund — wie die Auswahl in Navision.
class _Eintrag extends StatelessWidget {
  const _Eintrag({
    required this.ziel,
    required this.aktiv,
    required this.eingeklappt,
  });

  final _Ziel ziel;
  final bool aktiv;
  final bool eingeklappt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final farben = theme.colorScheme;
    final symbol = Icon(
      ziel.icon,
      size: 19,
      color: aktiv ? farben.primary : farben.onSurfaceVariant,
    );

    final kachel = Material(
      color: aktiv ? farben.primaryContainer : Colors.transparent,
      borderRadius: AppMasse.ecken,
      child: InkWell(
        onTap: () => context.goNamed(ziel.name),
        borderRadius: AppMasse.ecken,
        child: SizedBox(
          height: 36,
          child: eingeklappt
              ? Center(child: symbol)
              : Row(
                  children: [
                    const SizedBox(width: 10),
                    symbol,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        ziel.titel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight:
                              aktiv ? FontWeight.w600 : FontWeight.w400,
                          color: aktiv
                              ? farben.onPrimaryContainer
                              : farben.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );

    final zeile = Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          // Balken am Rand der Leiste für den aktiven Eintrag.
          Container(
            width: 3,
            height: 36,
            color: aktiv ? farben.primary : Colors.transparent,
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                left: eingeklappt ? 4 : 6,
                right: eingeklappt ? 7 : 9,
              ),
              child: kachel,
            ),
          ),
        ],
      ),
    );

    // Eingeklappt steht der Name im Tooltip.
    return eingeklappt
        ? Tooltip(
            message: ziel.titel,
            waitDuration: const Duration(milliseconds: 300),
            child: zeile,
          )
        : zeile;
  }
}

/// Fensterknöpfe und Einklappen — unten in der Leiste, auf jeder Seite.
class _Fensterknoepfe extends ConsumerWidget {
  const _Fensterknoepfe({
    required this.eingeklappt,
    required this.umschaltbar,
  });

  final bool eingeklappt;
  final bool umschaltbar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;

    Widget knopf({
      required IconData icon,
      required String tooltip,
      required VoidCallback onPressed,
    }) =>
        IconButton(
          onPressed: onPressed,
          tooltip: tooltip,
          icon: Icon(icon, size: 19, color: grau),
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        );

    final einklappen = umschaltbar
        ? knopf(
            icon: eingeklappt
                ? Icons.keyboard_double_arrow_right
                : Icons.keyboard_double_arrow_left,
            tooltip: eingeklappt ? 'Leiste ausklappen' : 'Leiste einklappen',
            onPressed: () =>
                ref.read(navigationEingeklapptProvider.notifier).umschalten(),
          )
        : null;
    final fenster = [
      knopf(
        icon: Icons.minimize,
        tooltip: 'Minimieren',
        onPressed: Vollbild.minimieren,
      ),
      ValueListenableBuilder<bool>(
        valueListenable: Vollbild.aktiv,
        builder: (context, vollbild, _) => knopf(
          icon: vollbild ? Icons.fullscreen_exit : Icons.fullscreen,
          tooltip: vollbild ? 'Vollbild beenden (F11)' : 'Vollbild (F11)',
          onPressed: Vollbild.umschalten,
        ),
      ),
      knopf(
        icon: Icons.power_settings_new,
        tooltip: 'App beenden',
        onPressed: () => beendenFragen(context, ref),
      ),
    ];

    if (eingeklappt) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...fenster,
            if (einklappen != null) einklappen,
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
      child: Row(
        children: [
          if (einklappen != null) einklappen,
          const Spacer(),
          ...fenster,
        ],
      ),
    );
  }
}

/// Nachfrage vor dem Beenden — ein versehentlicher Klick soll nicht die
/// App schließen. Beim Beenden wird ein Backup geschrieben.
Future<void> beendenFragen(BuildContext context, WidgetRef ref) async {
  // Vor dem Warten holen: Die Datenbank gehört dem Container, nicht dieser
  // Leiste.
  final db = ref.read(databaseProvider);
  final ja = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('App beenden?'),
      content: const Text(
        'Beim Beenden wird automatisch ein Backup geschrieben.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Beenden'),
        ),
      ],
    ),
  );
  if (ja != true) return;
  // Backup hier — vor dem Exit — schreiben, statt über den Lebenszyklus
  // des Fensters: So läuft nur ein einziger, klar begrenzter Ausstiegsweg
  // (siehe Vollbild.beenden).
  try {
    await BackupService.createAutoBackup(db)
        .timeout(const Duration(seconds: 10));
    await BackupService.cleanupOldAutoBackups()
        .timeout(const Duration(seconds: 5));
  } catch (_) {
    // Das Beenden darf nie blockieren — im Zweifel ohne frisches Backup.
  }
  // Die native SQLite-Verbindung läuft auf einem eigenen Isolate
  // (drift_flutter). Ohne sauberes Schließen kann das Beenden mitten in
  // einer offenen Verbindung erwischen — das hat auf Windows zum Absturz
  // beim Beenden geführt.
  try {
    await db.close().timeout(const Duration(seconds: 5));
  } catch (_) {
    // Auch hier: das Beenden darf nicht hängen bleiben.
  }
  await Vollbild.beenden();
}
