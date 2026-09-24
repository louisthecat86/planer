import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/utils/zeit.dart';
import '../../core/constants/parameter_namen.dart';
import '../../core/constants/product_groups.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';
import 'article_detail_providers.dart';
import 'article_info_editor_dialog.dart';
import 'article_print_service.dart';
import 'bratstrasse_schema.dart';
import 'custom_parameter_editor_dialog.dart';
import 'production_entry_dialog.dart';
import 'step_editor_dialog.dart';
import '../../core/utils/sheet_utils.dart';
import '../../core/constants/artikel_merkmale.dart';

// Die Datei war mit 4.750 Zeilen zu groß, um sich darin zurechtzufinden.
// Sie ist deshalb zerlegt: Provider und gemeinsame Helfer liegen in
// article_detail_providers.dart (echter Import, weil auch andere Screens
// sie brauchen), die Widget-Blöcke in den part-Dateien unten.
//
// `part` für die Widgets, weil deren Klassen dateiprivat sind und einander
// nur innerhalb derselben Bibliothek sehen — eine reine Textverschiebung
// ohne Umbenennungen. Alle Imports stehen weiterhin nur in dieser Datei.
part 'article_besonderheiten.dart';
part 'article_maschinen_ansicht.dart';
part 'article_parameter_liste.dart';
part 'article_production_tab.dart';
part 'article_produktionsmittel_katalog.dart';
part 'article_prozess_diagramm.dart';
class ArticleDetailScreen extends ConsumerWidget {
  const ArticleDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productAsync = ref.watch(productProvider(productId));

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: productAsync.when(
            data: (p) => Text(p?.artikelbezeichnung ?? 'Artikel'),
            loading: () => const Text('Artikel'),
            error: (_, __) => const Text('Fehler'),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.cleaning_services_outlined),
              tooltip: 'Doppelte Parameter bereinigen',
              onPressed: () => bereinigeDoppelteParameter(
                context,
                ref,
                productId,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.print),
              tooltip: 'Prozessblatt drucken',
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await ArticlePrintService.drucke(context, ref, productId);
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(content: Text('Druck-Fehler: $e')),
                  );
                }
              },
            ),
            productAsync.maybeWhen(
              data: (p) => p != null
                  ? Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Chip(
                        label: Text(p.artikelnummer),
                        avatar: const Icon(Icons.tag, size: 16),
                      ),
                    )
                  : const SizedBox.shrink(),
              orElse: () => const SizedBox.shrink(),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.info_outline), text: 'Infos'),
              Tab(icon: Icon(Icons.account_tree_outlined), text: 'Prozess'),
              Tab(icon: Icon(Icons.insights), text: 'Produktion'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _InfoTab(productId: productId),
            _ProcessTab(productId: productId),
            _ProductionTab(productId: productId),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            final gespeichert =
                await ProductionEntryDialog.show(context, productId);
            if (gespeichert) {
              ref.invalidate(productionHistoryProvider(productId));
            }
          },
          icon: const Icon(Icons.add_chart),
          label: const Text('Produktion erfassen'),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 1: Artikel-Infos
// ---------------------------------------------------------------------------

class _InfoTab extends ConsumerWidget {
  const _InfoTab({required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productAsync = ref.watch(productProvider(productId));

    return productAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (p) {
        if (p == null) {
          return const Center(child: Text('Artikel nicht gefunden.'));
        }

        final eintraege = <({String label, String wert})>[
          (label: 'Artikelnummer', wert: p.artikelnummer),
          (label: 'Bezeichnung', wert: p.artikelbezeichnung),
        ];
        if (p.produktgruppe != null && p.produktgruppe!.isNotEmpty) {
          eintraege.add((
            label: 'Produktgruppe',
            wert: produktgruppeLabels[p.produktgruppe] ?? p.produktgruppe!,
          ),);
        }
        if (p.notizen != null && p.notizen!.isNotEmpty) {
          eintraege.add((label: 'Notizen', wert: p.notizen!));
        }

        final besonderheiten = p.beschreibung?.trim() ?? '';

        // Merkmale als eigene Karte: Sie entscheiden später über die
        // Reihenfolge in der Planung und sollen deshalb auf einen Blick
        // erkennbar sein — auch dann, wenn sie fehlen.
        final verpackung = <String>[
          if (merkmaleLabel(p.verpackungsformen, kVerpackungsformen)
              .isNotEmpty)
            merkmaleLabel(p.verpackungsformen, kVerpackungsformen),
          if (merkmalLabel(p.kartonGroesse, kKartonGroessen) != null)
            merkmalLabel(p.kartonGroesse, kKartonGroessen)!,
          if (merkmalLabel(p.kartonBedruckung, kKartonBedruckungen) != null)
            merkmalLabel(p.kartonBedruckung, kKartonBedruckungen)!,
          if (p.packungenProKarton != null)
            '${p.packungenProKarton} Pack./Kt.',
          if (p.fuellmengeNettoG != null)
            '${_gramm(p.fuellmengeNettoG!)} netto',
          if (merkmalLabel(p.abgabeart, kAbgabearten) != null)
            merkmalLabel(p.abgabeart, kAbgabearten)!,
        ].join(' · ');

        final merkmalZeilen = <({String label, String wert})>[
          (
            label: 'Allergene',
            wert: allergeneGepflegt(p.allergene)
                ? merkmaleLabel(p.allergene, kAllergene)
                : 'nicht gepflegt',
          ),
          if (merkmalLabel(p.qualitaetsstufe, kQualitaetsstufen) != null)
            (
              label: 'Qualitätsstufe',
              wert: merkmalLabel(p.qualitaetsstufe, kQualitaetsstufen)!,
            ),
          if (merkmaleLabel(p.verarbeitungsstufe, kVerarbeitungsstufen)
              .isNotEmpty)
            (
              label: 'Verarbeitungsstufe',
              wert: merkmaleLabel(p.verarbeitungsstufe, kVerarbeitungsstufen),
            ),
          if (verpackung.isNotEmpty)
            (label: 'Verpackung', wert: verpackung),
        ];

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < eintraege.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _InfoZeile(
                        label: eintraege[i].label,
                        wert: eintraege[i].wert,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Merkmale
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < merkmalZeilen.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _InfoZeile(
                        label: merkmalZeilen[i].label,
                        wert: merkmalZeilen[i].wert,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Besonderheiten — eigene Karte, damit sie auffällt
            _BesonderheitenKarte(
              text: besonderheiten,
              onEdit: () async {
                final geaendert =
                    await ArticleInfoEditorDialog.show(context, p);
                if (geaendert) ref.invalidate(productProvider(productId));
              },
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final geaendert =
                    await ArticleInfoEditorDialog.show(context, p);
                if (geaendert) {
                  ref.invalidate(productProvider(productId));
                }
              },
              icon: const Icon(Icons.edit),
              label: const Text('Stammdaten bearbeiten'),
            ),
          ],
        );
      },
    );
  }
}

/// Füllmenge lesbar: unter 1000 g in Gramm, darüber in Kilo.
String _gramm(double g) {
  if (g >= 1000) {
    final kg = g / 1000;
    final text = kg == kg.roundToDouble()
        ? kg.round().toString()
        : kg.toStringAsFixed(2).replaceAll('.', ',');
    return '$text kg';
  }
  return '${g == g.roundToDouble() ? g.round() : g} g';
}

class _InfoZeile extends StatelessWidget {
  const _InfoZeile({required this.label, required this.wert});

  final String label;
  final String wert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              wert,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 2: Prozessspezifisch (Schrittliste)
// ---------------------------------------------------------------------------

class _ProcessTab extends ConsumerWidget {
  const _ProcessTab({required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stepsAsync = ref.watch(productStepsProvider(productId));
    return stepsAsync.when(
      data: (steps) => _StepsList(productId: productId, steps: steps),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
    );
  }
}

// ---------------------------------------------------------------------------
// Schritte-Liste
// ---------------------------------------------------------------------------

/// Ansichtsmodus des Prozess-Tabs: Fließdiagramm (Standard) oder Karten.
final prozessDiagrammProvider = StateProvider<bool>((ref) => true);

class _StepsList extends ConsumerWidget {
  const _StepsList({required this.productId, required this.steps});

  final String productId;
  final List<ProductStep> steps;

  /// Schreibt die `reihenfolge` aller Schritte gemäß der übergebenen
  /// Gruppen-Anordnung neu durch (1..n) und lädt die Ansicht neu.
  ///
  /// Der Excel-Export schreibt die Schritte nach `reihenfolge` in die
  /// Spalten B..K — jede neue Abfolge landet also automatisch im Export.
  Future<void> _schreibeReihenfolge(
    WidgetRef ref,
    List<List<({ProductStep step, int nummer})>> neu, {
    required String grund,
  }) async {
    final db = ref.read(databaseProvider);
    var lauf = 1;
    for (final gruppe in neu) {
      for (final eintrag in gruppe) {
        await (db.update(db.productSteps)
              ..where((s) => s.id.equals(eintrag.step.id)))
            .write(
          ProductStepsCompanion(
            reihenfolge: Value(lauf),
            updatedAt: Value(DateTime.now()),
          ),
        );
        lauf++;
      }
    }

    ref.read(autoBackupTriggerProvider).fireDebounced(reason: grund);
    ref.invalidate(productStepsProvider(productId));
  }

  /// Verschiebt einen Abteilungs-Block (alle konsekutiven Schritte einer
  /// Abteilung) um eine Position nach oben/unten.
  Future<void> _verschiebeGruppe(
    WidgetRef ref,
    List<List<({ProductStep step, int nummer})>> gruppen,
    int index,
    int richtung,
  ) async {
    final ziel = index + richtung;
    if (ziel < 0 || ziel >= gruppen.length) return;

    final neu = [...gruppen];
    final block = neu.removeAt(index);
    neu.insert(ziel, block);

    await _schreibeReihenfolge(
      ref,
      neu,
      grund: 'Abteilungs-Reihenfolge geändert',
    );
  }

  /// Verschiebt einen Schritt INNERHALB seiner Abteilungs-Gruppe.
  ///
  /// Drop-Konvention wie bei ReorderableListView: nach rechts gezogen
  /// landet der Schritt HINTER dem Ziel, nach links gezogen DAVOR.
  Future<void> _verschiebeSchrittInGruppe(
    WidgetRef ref,
    List<List<({ProductStep step, int nummer})>> gruppen,
    int gruppenIndex,
    int von,
    int nach,
  ) async {
    if (von == nach) return;
    final gruppe = [...gruppen[gruppenIndex]];
    final item = gruppe.removeAt(von);
    gruppe.insert(nach.clamp(0, gruppe.length), item);

    final neu = [...gruppen];
    neu[gruppenIndex] = gruppe;

    await _schreibeReihenfolge(
      ref,
      neu,
      grund: 'Schritt-Reihenfolge geändert',
    );
  }

  /// Öffnet die geführte Leistungsdaten-Maske: fragt je Abteilung des
  /// Prozesses Menge und Zeit ab und schreibt die Werte auf den jeweils
  /// ersten Schritt der Abteilungsgruppe (Excel-Konvention).
  ///
  /// Personen werden dort NICHT gepflegt — die Zahl hängt am einzelnen
  /// Schritt und wird im Step-Editor gesetzt. Die Gruppe wird trotzdem
  /// komplett übergeben, damit der Dialog die Summe je Abteilung anzeigen
  /// kann.
  Future<void> _leistungsdatenErfassen(
    BuildContext context,
    WidgetRef ref,
    List<List<({ProductStep step, int nummer})>> gruppen,
  ) async {
    if (gruppen.isEmpty) return;
    final geaendert = await showDialog<bool>(
      context: context,
      builder: (_) => _LeistungsdatenDialog(
        eintraege: [
          for (final g in gruppen)
            (
              abteilung: Abteilung.fromDbValue(g.first.step.abteilung),
              erster: g.first.step,
              schritte: [for (final e in g) e.step],
            ),
        ],
      ),
    );
    if (geaendert == true) {
      ref.invalidate(productStepsProvider(productId));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // Aufeinanderfolgende Schritte derselben Abteilung zu EINER Karte bündeln
    // (z.B. Bratstraße = Verbufa + Bratstraße + Dampftunnel ? eine Karte).
    final gruppen = <List<({ProductStep step, int nummer})>>[];
    for (var i = 0; i < steps.length; i++) {
      final eintrag = (step: steps[i], nummer: i + 1);
      if (gruppen.isNotEmpty &&
          gruppen.last.first.step.abteilung == steps[i].abteilung) {
        gruppen.last.add(eintrag);
      } else {
        gruppen.add([eintrag]);
      }
    }

    final diagramm = ref.watch(prozessDiagrammProvider);

    Widget inhalt(bool zweiSpaltig) => diagramm
        ? _ProzessDiagramm(
            productId: productId,
            gruppen: gruppen,
            onMove: (index, richtung) =>
                _verschiebeGruppe(ref, gruppen, index, richtung),
            onReorderSchritt: (gruppenIndex, von, nach) =>
                _verschiebeSchrittInGruppe(
              ref,
              gruppen,
              gruppenIndex,
              von,
              nach,
            ),
            onUpdated: () => ref.invalidate(productStepsProvider(productId)),
          )
        : _KartenAnsicht(
            productId: productId,
            gruppen: gruppen,
            onMoveTo: (von, nach) =>
                _verschiebeGruppe(ref, gruppen, von, nach - von),
            onUpdated: () => ref.invalidate(productStepsProvider(productId)),
          );

    Widget umschalter() => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.account_tree_outlined, size: 16),
                  label: Text('Diagramm', style: TextStyle(fontSize: 12)),
                ),
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.view_agenda_outlined, size: 16),
                  label: Text('Karten', style: TextStyle(fontSize: 12)),
                ),
              ],
              selected: {diagramm},
              onSelectionChanged: (sel) =>
                  ref.read(prozessDiagrammProvider.notifier).state = sel.first,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
              showSelectedIcon: false,
            ),
            const SizedBox(width: 8),
            // Geführte Erfassung der Referenzleistung je Abteilung
            // (Menge/Zeit/Personen) — daraus rechnet die App kg/h und
            // skaliert die Dauer jeder Planmenge.
            OutlinedButton.icon(
              onPressed: () => _leistungsdatenErfassen(context, ref, gruppen),
              icon: const Icon(Icons.speed, size: 16),
              label: const Text(
                'Leistungsdaten',
                style: TextStyle(fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Ab ~900px: feste Produktionsmittel-Sidebar links.
        final mitSidebar = constraints.maxWidth >= 900;

        if (mitSidebar) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 212,
                child: ColoredBox(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.35),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: _ProduktionsmittelKatalog(productId: productId),
                  ),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: umschalter(),
                      ),
                    ),
                    _BesonderheitBanner(productId: productId),
                    Expanded(child: inhalt(false)),
                  ],
                ),
              ),
            ],
          );
        }

        // Schmaler: „+ Produktionsmittel"-Button + Umschalter oben.
        final zweiSpaltig = constraints.maxWidth >= 700;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  _ProduktionsmittelButton(productId: productId),
                  const Spacer(),
                  umschalter(),
                ],
              ),
            ),
            _BesonderheitBanner(productId: productId),
            Expanded(child: inhalt(zweiSpaltig)),
          ],
        );
      },
    );
  }

  /// Karten-Bereich: leerer Hinweis, einspaltig oder zweispaltig verteilt.
}


