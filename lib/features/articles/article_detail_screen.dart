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
import '../../core/services/prozesskette_service.dart';
import '../whiteboard/whiteboard_provider.dart'
    show
        HistorienLeistung,
        Leistungsdaten,
        ausbeuteAusProduktionen,
        historienLeistung,
        kLetzteProduktionen,
        leistungAusProduktionen,
        leistungsdatenVon;
import 'article_detail_providers.dart';
import 'article_info_editor_dialog.dart';
import 'article_print_service.dart';
import 'bratstrasse_schema.dart';
import 'custom_parameter_editor_dialog.dart';
import 'production_entry_dialog.dart';
import 'prozesskette_umbau.dart';
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
part 'article_prozesskette.dart';

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

/// Der Prozess-Tab: die Prozesskette, daneben (breit) der Katalog der
/// Produktionsmittel, aus dem sich Anlagen in die Kette ziehen lassen.
class _StepsList extends ConsumerWidget {
  const _StepsList({required this.productId, required this.steps});

  final String productId;
  final List<ProductStep> steps;

  /// Öffnet die Leistungsdaten-Maske für die Stationen [stationen] (Index
  /// in `bau.stationen`): je Station Menge und Zeit, gespeichert am ersten
  /// Schritt der Station.
  ///
  /// Personen werden dort NICHT gepflegt — die Zahl hängt am einzelnen
  /// Schritt und wird im Step-Editor gesetzt. Die Station wird trotzdem
  /// komplett übergeben, damit der Dialog die Summe anzeigen kann.
  Future<void> _leistungsdatenErfassen(
    BuildContext context,
    Kettenbau bau,
    Iterable<int> stationen,
  ) async {
    final eintraege = [
      for (final k in stationen)
        if (_abteilungAus(bau.stationen[k].first.abteilung)
            case final abteilung?)
          (
            nummer: k + 1,
            abteilung: abteilung,
            erster: bau.stationen[k].first,
            schritte: bau.stationen[k],
          ),
    ];
    if (eintraege.isEmpty) return;
    // Vor dem await holen: Nach dem Speichern steht die Ansicht neu.
    final container = ProviderScope.containerOf(context, listen: false);
    final geaendert = await showDialog<bool>(
      context: context,
      builder: (_) => _LeistungsdatenDialog(eintraege: eintraege),
    );
    if (geaendert == true) {
      container.invalidate(productStepsProvider(productId));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final bau = Kettenbau(productId: productId, steps: steps);
    final maschinen = {
      for (final m in ref.watch(alleMaschinenProvider).valueOrNull ??
          const <Machine>[])
        m.id: m,
    };
    // Dieselben Produktionen, mit denen die Planung rechnet.
    final historie = leistungAusProduktionen(
      ref.watch(productionHistoryProvider(productId)).valueOrNull ??
          const <ProductionHistoryData>[],
    );

    final kette = _Prozesskette(
      bau: bau,
      maschinen: maschinen,
      historie: historie,
      onUpdated: () => ref.invalidate(productStepsProvider(productId)),
      onLeistungsdaten: (station) =>
          _leistungsdatenErfassen(context, bau, [station]),
    );

    // Alle Stationen in einer Maske — für die erste Pflege eines Artikels.
    // Einzelne Stationen öffnen sich über ihren Leistungs-Chip.
    final leistungsdaten = OutlinedButton.icon(
      onPressed: bau.stationen.isEmpty
          ? null
          : () => _leistungsdatenErfassen(
                context,
                bau,
                [for (var k = 0; k < bau.stationen.length; k++) k],
              ),
      icon: const Icon(Icons.speed, size: 16),
      label: const Text(
        'Leistungsdaten',
        style: TextStyle(fontSize: 12),
      ),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Ab ~900px: feste Produktionsmittel-Sidebar links — aus ihr lassen
        // sich Anlagen direkt an ihre Stelle in der Kette ziehen.
        if (constraints.maxWidth >= 900) {
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
                    child: _ProduktionsmittelKatalog(
                      productId: productId,
                      ziehbar: true,
                    ),
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
                        child: leistungsdaten,
                      ),
                    ),
                    _BesonderheitBanner(productId: productId),
                    Expanded(child: kette),
                  ],
                ),
              ),
            ],
          );
        }

        // Schmaler: „+ Produktionsmittel"-Button oben, der Katalog öffnet
        // sich als Sheet.
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  _ProduktionsmittelButton(productId: productId),
                  const Spacer(),
                  leistungsdaten,
                ],
              ),
            ),
            _BesonderheitBanner(productId: productId),
            Expanded(child: kette),
          ],
        );
      },
    );
  }
}
