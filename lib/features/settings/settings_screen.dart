import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/providers/theme_mode_provider.dart';
import '../../core/providers/ui_scale_provider.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';
import '../../core/theme/app_stil.dart';
import '../../core/ui/bausteine.dart';
import '../../core/utils/sheet_utils.dart';
import '../board/board_providers.dart';

/// Einstellungen — Sammelpunkt für alles, was nicht zum täglichen Planen
/// gehört: Anzeigegröße, Kapazitäten und Stammdaten.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: LayoutBuilder(
        builder: (context, c) {
          // Nicht über die ganze Breite: Titel und Pfeil einer Zeile lägen
          // sonst weit auseinander.
          final seite = math.max(14.0, (c.maxWidth - 900) / 2);
          return ListView(
            padding: EdgeInsets.fromLTRB(seite, 12, seite, 24),
            children: [
              // Die Einstellungen als Liste in einem Bereich — wie die
              // Einrichtung in Navision. Vorher Kacheln mit bunten,
              // runden Symbolflächen.
              Bereich(
                titel: 'Einrichtung',
                innenAbstand: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _EinstellungsZeile(
                      icon: Icons.palette_outlined,
                      titel: 'Ansicht',
                      text: 'Hell/Dunkel und Anzeigegröße der App',
                      onTap: () => _zeigeAnsichtSheet(context),
                    ),
                    _EinstellungsZeile(
                      icon: Icons.swap_vert_rounded,
                      titel: 'Import / Export',
                      text: 'Artikel, Maschinen-Katalog und Backup sichern '
                          'oder einlesen',
                      onTap: () => context.pushNamed('data'),
                    ),
                    _EinstellungsZeile(
                      icon: Icons.schedule_rounded,
                      titel: 'Abteilungskapazität',
                      text: 'Tagesstunden je Abteilung festlegen und '
                          'übersteuern',
                      onTap: () => _zeigeKapazitaetSheet(context),
                      letzte: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const _GefahrenZone(),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  'Produktions Planer · offline',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Ein Punkt der Einstellungen als Zeile: Symbol, Titel, kurze
/// Beschreibung und rechts ein Pfeil. Antippen öffnet ihn.
class _EinstellungsZeile extends StatelessWidget {
  const _EinstellungsZeile({
    required this.icon,
    required this.titel,
    required this.text,
    required this.onTap,
    this.letzte = false,
  });

  final IconData icon;
  final String titel;
  final String text;
  final VoidCallback onTap;

  /// Letzte Zeile: ohne Linie darunter, dort schließt der Rand.
  final bool letzte;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // Material statt Farbe am Container: Die Hover- und Tipp-Welle des
    // InkWell malt auf das nächste Material.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            border: letzte
                ? null
                : Border(bottom: BorderSide(color: colors.outlineVariant)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: colors.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titel,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      text,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _zeigeKapazitaetSheet(BuildContext context) {
  // Ohne Anfasser: Das Fenster hat einen eigenen Kopf mit Titel und Kreuz
  // wie jedes Fenster der App.
  showSheetOhneAnimation<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => const _AbteilungskapazitaetenSheet(),
  );
}

class _AbteilungskapazitaetenSheet extends ConsumerStatefulWidget {
  const _AbteilungskapazitaetenSheet();

  @override
  ConsumerState<_AbteilungskapazitaetenSheet> createState() =>
      _AbteilungskapazitaetenSheetState();
}

class _AbteilungskapazitaetenSheetState
    extends ConsumerState<_AbteilungskapazitaetenSheet> {
  final _stunden = <String, TextEditingController>{};
  bool _laden = true;
  bool _speichern = false;

  @override
  void initState() {
    super.initState();
    _lade();
  }

  Future<void> _lade() async {
    final werte = await ladeAbteilungskapazitaeten(
      ref.read(databaseProvider),
    );
    for (final a in Abteilung.values) {
      final minuten = werte[a.dbValue] ?? kStandardKapazitaetMinuten;
      _stunden[a.dbValue] = TextEditingController(
        text: (minuten / 60).toStringAsFixed(1).replaceAll('.0', ''),
      );
    }
    if (mounted) setState(() => _laden = false);
  }

  @override
  void dispose() {
    for (final controller in _stunden.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _speichere() async {
    final werte = <String, double>{};
    for (final a in Abteilung.values) {
      final stunden = double.tryParse(
        _stunden[a.dbValue]!.text.replaceAll(',', '.'),
      );
      if (stunden == null || stunden <= 0 || stunden > 24) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${a.anzeigeName}: 0 bis 24 Stunden')),
        );
        return;
      }
      werte[a.dbValue] = stunden * 60;
    }

    setState(() => _speichern = true);
    final db = ref.read(databaseProvider);
    for (final eintrag in werte.entries) {
      await speichereAbteilungskapazitaet(db, eintrag.key, eintrag.value);
    }
    ref.read(autoBackupTriggerProvider).fireDebounced(
          reason: 'Abteilungskapazität geändert',
        );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    const abteilungen = Abteilung.values;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          // Kopf wie bei jedem Fenster der App: Titel in Blau, rechts ein
          // Kreuz.
          Row(
            children: [
              Expanded(
                child: Text(
                  'Abteilungskapazität',
                  style: theme.dialogTheme.titleTextStyle ??
                      theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                tooltip: 'Schließen ohne Speichern',
                onPressed:
                    _speichern ? null : () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Tageskapazität in Stunden. Standard: 10 h.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          if (_laden)
            const SizedBox(
              height: 180,
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            // Je Abteilung eine Zeile mit Kürzel, Name und Stunden — eine
            // Tabelle mit Rand. Vorher ein Feld unter dem anderen.
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                border: Border.all(color: colors.outline),
                borderRadius: AppMasse.ecken,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < abteilungen.length; i++)
                    _KapazitaetsZeile(
                      abteilung: abteilungen[i],
                      controller: _stunden[abteilungen[i].dbValue]!,
                      letzte: i == abteilungen.length - 1,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Knöpfe unten rechts wie in jedem Fenster der App.
            Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed:
                      _speichern ? null : () => Navigator.of(context).pop(),
                  child: const Text('Abbrechen'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _speichern ? null : _speichere,
                  // Ohne feste Farbe: Der gesperrte Knopf ist hellgrau, ein
                  // weißer Kreisel wäre darauf unsichtbar.
                  icon: _speichern
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save, size: 18),
                  label: const Text('Kapazitäten speichern'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Eine Abteilung in der Kapazitätstabelle: Kürzel, Name und die Stunden je
/// Tag als Eingabefeld.
class _KapazitaetsZeile extends StatelessWidget {
  const _KapazitaetsZeile({
    required this.abteilung,
    required this.controller,
    required this.letzte,
  });

  final Abteilung abteilung;
  final TextEditingController controller;

  /// Letzte Zeile: ohne Linie darunter, dort schließt der Rand.
  final bool letzte;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        border: letzte
            ? null
            : Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          AbteilungsMarke(abteilung: abteilung),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              abteilung.anzeigeName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 130,
            child: TextField(
              controller: controller,
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(suffixText: 'h / Tag'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Öffnet die Ansicht-Einstellungen (Hell/Dunkel + Größe) als Fenster.
///
/// Bewusst kein eigener Screen: Es sind zwei Schalter, die man kurz
/// verstellt — dafür lohnt kein Seitenwechsel.
void _zeigeAnsichtSheet(BuildContext context) {
  final container = ProviderScope.containerOf(context);
  showSheetOhneAnimation<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return UncontrolledProviderScope(
        container: container,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            20 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Kopf wie bei jedem Fenster der App: Titel in Blau, rechts
              // ein Kreuz. Vorher saß hier der Anfasser aus der
              // Bottom-Sheet-Zeit.
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Ansicht',
                      style: theme.dialogTheme.titleTextStyle ??
                          theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Schließen',
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const _Anzeigemodus(),
              const SizedBox(height: 12),
              const _AnzeigeGroesse(),
            ],
          ),
        ),
      );
    },
  );
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
              foregroundColor: theme.colorScheme.onError,
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
      //
      // Das Wiedereinschalten MUSS in ein finally: Bricht das Löschen ab
      // (Datei gesperrt, Platte voll, Absturz mittendrin), liefe die App
      // sonst bis zum Neustart OHNE referenzielle Integrität weiter. Alles,
      // was danach geschrieben wird, könnte verwaisen — und das fällt erst
      // Wochen später auf, wenn Aufträge auf gelöschte Artikel zeigen.
      await db.customStatement('PRAGMA foreign_keys = OFF');
      try {
        await db.transaction(() async {
          for (final tabelle in db.allTables) {
            await db.delete(tabelle).go();
          }
        });
      } finally {
        // Bewusst ohne try/catch: Schlägt sogar das PRAGMA fehl, ist die
        // Verbindung ohnehin defekt — dann soll der Fehler sichtbar sein
        // und nicht durch ein stilles catch verdeckt werden.
        await db.customStatement('PRAGMA foreign_keys = ON');
      }

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          icon: Icon(Icons.check_circle, color: AppFarben.von(ctx).ok),
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
    final colors = Theme.of(context).colorScheme;
    // Ein eigener Bereich mit rotem Hinweis und dem Knopf in der
    // Fehlerfarbe. Vorher eine rötlich getönte Karte mit runden Ecken.
    return Bereich(
      titel: 'Gefahrenzone',
      child: HinweisBox(
        'Löscht alle Daten der App (SQLite). Backup-Dateien bleiben '
        'erhalten.',
        art: StatusArt.fehler,
        icon: Icons.delete_forever_outlined,
        titel: 'App zurücksetzen',
        aktion: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: colors.error,
            foregroundColor: colors.onError,
          ),
          onPressed: _busy ? null : _reset,
          // Ohne feste Farbe: Der gesperrte Knopf ist hellgrau, ein weißer
          // Kreisel wäre darauf unsichtbar.
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.delete_forever_rounded, size: 18),
          label: Text(_busy ? 'Wird gelöscht …' : 'App zurücksetzen …'),
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
            decoration: const InputDecoration(hintText: 'LÖSCHEN'),
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
            foregroundColor: theme.colorScheme.onError,
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
    final modus = ref.watch(themeModeProvider);
    final notifier = ref.read(themeModeProvider.notifier);

    return Bereich(
      titel: 'Darstellung',
      untertitel: 'Heller oder dunkler Modus — im Navision-Look',
      innenAbstand: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: SizedBox(
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

    return Bereich(
      titel: 'Anzeigegröße',
      untertitel: 'Schrift und Bedienelemente in der ganzen App',
      innenAbstand: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: scale <= 0.25 ? null : () => notifier.kleiner(),
                icon: const Icon(Icons.remove),
                tooltip: 'Kleiner',
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      '$prozent %',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
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
                onPressed: scale >= 2.0 ? null : () => notifier.groesser(),
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
    );
  }
}
