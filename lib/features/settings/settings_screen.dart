import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/theme_mode_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/ui_scale_provider.dart';
import '../../core/providers/database_provider.dart';

/// Einstellungen — Sammelpunkt für alles, was nicht zum täglichen Planen
/// gehört: Anzeigegröße und Stammdaten (Excel-Import/-Export, Backup,
/// Wiederherstellung). Die Arbeitszeit ist fix 9 h je Abteilung und wird
/// nicht mehr einzeln gepflegt.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _KachelGrid(
            kacheln: [
              _Kachel(
                icon: Icons.palette_rounded,
                color: const Color(0xFF5E35B1),
                title: 'Ansicht',
                subtitle: 'Hell/Dunkel und Anzeigegröße der App',
                onTap: () => _zeigeAnsichtSheet(context),
              ),
              _Kachel(
                icon: Icons.swap_vert_rounded,
                color: const Color(0xFF00838F),
                title: 'Import / Export',
                subtitle: 'Artikel, Maschinen-Katalog und Backup sichern '
                    'oder einlesen',
                onTap: () => context.pushNamed('data'),
              ),
              _Kachel(
                icon: Icons.precision_manufacturing_rounded,
                color: const Color(0xFF00695C),
                title: 'Maschinen-Katalog',
                subtitle: 'Anlagen, Parameter-Steckbriefe und Grenzwerte',
                onTap: () => context.pushNamed('maschinen'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const _Abschnitt('Gefahrenzone'),
          const SizedBox(height: 6),
          const _GefahrenZone(),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Produktion Planer · offline',
              style: TextStyle(
                fontSize: 12,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Öffnet die Ansicht-Einstellungen (Hell/Dunkel + Größe) als Sheet.
///
/// Bewusst kein eigener Screen: Es sind zwei Schalter, die man kurz
/// verstellt — dafür lohnt kein Seitenwechsel.
void _zeigeAnsichtSheet(BuildContext context) {
  final container = ProviderScope.containerOf(context);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => UncontrolledProviderScope(
      container: container,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          24 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Ansicht',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            const _Anzeigemodus(),
            const SizedBox(height: 8),
            const _AnzeigeGroesse(),
          ],
        ),
      ),
    ),
  );
}

/// Kleiner Abschnitts-Titel zwischen den Karten-Gruppen.
class _Abschnitt extends StatelessWidget {
  const _Abschnitt(this.titel);

  final String titel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Text(
        titel.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Responsives Kachel-Raster (1–3 Spalten je nach Breite).
class _KachelGrid extends StatelessWidget {
  const _KachelGrid({required this.kacheln});

  final List<Widget> kacheln;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final spalten = c.maxWidth >= 720 ? 3 : (c.maxWidth >= 460 ? 2 : 1);
        const spacing = 10.0;
        final breite = (c.maxWidth - spacing * (spalten - 1)) / spalten;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final k in kacheln) SizedBox(width: breite, child: k),
          ],
        );
      },
    );
  }
}

/// Eine Navigations-Kachel (Icon oben, Titel, kurze Beschreibung).
class _Kachel extends StatelessWidget {
  const _Kachel({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// „Gefahrenzone": kompletter App-Reset. Löscht ALLE Daten aus der lokalen
/// SQLite-Datenbank. Backup-Dateien auf der Platte bleiben unberührt.
class _GefahrenZone extends ConsumerStatefulWidget {
  const _GefahrenZone();

  @override
  ConsumerState<_GefahrenZone> createState() => _GefahrenZoneState();
}

class _GefahrenZoneState extends ConsumerState<_GefahrenZone> {
  bool _busy = false;

  Future<void> _reset() async {
    final theme = Theme.of(context);
    // 1. Warnung
    final weiter = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          color: theme.colorScheme.error,
        ),
        title: const Text('App komplett zurücksetzen?'),
        content: const Text(
          'Dabei werden ALLE Daten unwiderruflich gelöscht: Artikel, '
          'Schritte, Anlagen, Bedarf, Planung, Historie und Einstellungen.\n\n'
          'Bereits erstellte Backup-Dateien bleiben erhalten — daraus '
          'könntest du später wiederherstellen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Weiter'),
          ),
        ],
      ),
    );
    if (weiter != true) return;

    // 2. Tippen zum Bestätigen
    if (!mounted) return;
    final bestaetigt = await showDialog<bool>(
      context: context,
      builder: (_) => const _ResetBestaetigungDialog(),
    );
    if (bestaetigt != true) return;

    // 3. Datenbank leeren
    setState(() => _busy = true);
    try {
      final db = ref.read(databaseProvider);
      // Foreign Keys AUSSERHALB der Transaktion abschalten, damit die
      // Löschreihenfolge egal ist (sonst FOREIGN KEY constraint failed).
      await db.customStatement('PRAGMA foreign_keys = OFF');
      await db.transaction(() async {
        for (final tabelle in db.allTables) {
          await db.delete(tabelle).go();
        }
      });
      await db.customStatement('PRAGMA foreign_keys = ON');

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Color(0xFF2E7D32)),
          title: const Text('Zurückgesetzt'),
          content: const Text(
            'Alle Daten wurden gelöscht. Bitte starte die App einmal neu, '
            'damit überall der leere Stand angezeigt wird.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Verstanden'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Zurücksetzen fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = theme.colorScheme.error;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: error.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: error.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.delete_forever_rounded, color: error),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'App zurücksetzen',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Löscht alle Daten der App (SQLite). Backup-Dateien '
                        'bleiben erhalten.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: error),
                onPressed: _busy ? null : _reset,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.delete_forever_rounded),
                label: Text(_busy ? 'Wird gelöscht …' : 'App zurücksetzen'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Zweite Sicherheitsstufe: der Nutzer muss „LÖSCHEN" eintippen.
class _ResetBestaetigungDialog extends StatefulWidget {
  const _ResetBestaetigungDialog();

  @override
  State<_ResetBestaetigungDialog> createState() =>
      _ResetBestaetigungDialogState();
}

class _ResetBestaetigungDialogState extends State<_ResetBestaetigungDialog> {
  final _ctrl = TextEditingController();
  static const _wort = 'LÖSCHEN';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final passt = _ctrl.text.trim().toUpperCase() == _wort;
    return AlertDialog(
      title: const Text('Wirklich löschen?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Tippe zur Bestätigung das Wort „LÖSCHEN" ein.'),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              hintText: 'LÖSCHEN',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (passt) Navigator.of(context).pop(true);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
          ),
          onPressed: passt ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Endgültig löschen'),
        ),
      ],
    );
  }
}

/// Umschalter für Hell-/Dunkelmodus.
///
/// Vorher lief der Windows-Build fest im Dunkelmodus. Jetzt entscheidet
/// jeder selbst; die Wahl wird dauerhaft gespeichert und gilt sofort.
class _Anzeigemodus extends ConsumerWidget {
  const _Anzeigemodus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final modus = ref.watch(themeModeProvider);
    final notifier = ref.read(themeModeProvider.notifier);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.navBlau.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    Icons.contrast,
                    color: AppTheme.navBlau,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Darstellung',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Heller oder dunkler Modus — im Navision-Look',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode_outlined, size: 18),
                    label: Text('Hell'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode_outlined, size: 18),
                    label: Text('Dunkel'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.desktop_windows_outlined, size: 18),
                    label: Text('System'),
                  ),
                ],
                selected: {modus},
                onSelectionChanged: (s) => notifier.setzen(s.first),
                showSelectedIcon: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Regler für die app-weite Anzeigegröße.
///
/// Skaliert die gesamte Schrift über `MediaQuery.textScaler`. Die Auswahl
/// wird dauerhaft gespeichert und gilt sofort in der ganzen App.
class _AnzeigeGroesse extends ConsumerWidget {
  const _AnzeigeGroesse();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scale = ref.watch(uiScaleProvider);
    final notifier = ref.read(uiScaleProvider.notifier);
    final prozent = (scale * 100).round();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6A1B9A).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.format_size_rounded,
                    color: Color(0xFF6A1B9A),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Anzeigegröße',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Schrift und Bedienelemente in der ganzen App',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                IconButton.filledTonal(
                  onPressed:
                      scale <= 0.25 ? null : () => notifier.kleiner(),
                  icon: const Icon(Icons.remove),
                  tooltip: 'Kleiner',
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        '$prozent %',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (prozent == 100)
                        Text(
                          'Normal',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  onPressed:
                      scale >= 2.0 ? null : () => notifier.groesser(),
                  icon: const Icon(Icons.add),
                  tooltip: 'Größer',
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Direkte Stufenauswahl — schneller als mehrfaches Tippen.
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final stufe in kUiScaleStufen)
                  ChoiceChip(
                    label: Text('${(stufe * 100).round()} %'),
                    selected: (scale - stufe).abs() < 0.001,
                    onSelected: (_) => notifier.setzen(stufe),
                  ),
              ],
            ),
            if (prozent != 100) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => notifier.zuruecksetzen(),
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: const Text('Auf 100 % zurücksetzen'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
