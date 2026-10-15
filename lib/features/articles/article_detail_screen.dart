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
import '../../core/theme/app_stil.dart';
import '../../core/ui/bausteine.dart';
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
    final nummer = productAsync.valueOrNull?.artikelnummer;
    // Schmale Fenster: „Produktion erfassen" nur als Symbol, sonst bliebe
    // für den Artikelnamen kein Platz.
    final schmal = MediaQuery.sizeOf(context).width < 720;

    Future<void> produktionErfassen() async {
      final gespeichert = await ProductionEntryDialog.show(context, productId);
      if (gespeichert) {
        ref.invalidate(productionHistoryProvider(productId));
      }
    }

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
              icon: const Icon(Icons.print_outlined),
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
            if (nummer != null) ...[
              const SizedBox(width: 6),
              _NummernFeld(nummer: nummer),
            ],
            const SizedBox(width: 8),
            // Wie „Produkt planen" im Board: die Aktion oben rechts in der
            // Kopfleiste statt als schwebender Knopf, der unten rechts die
            // Prozesskette und die letzte Produktion verdeckte.
            if (schmal)
              IconButton(
                icon: const Icon(Icons.add_chart),
                tooltip: 'Produktion erfassen',
                onPressed: produktionErfassen,
              )
            else
              FilledButton.icon(
                onPressed: produktionErfassen,
                icon: const Icon(Icons.add_chart, size: 18),
                label: const Text('Produktion erfassen'),
              ),
            const SizedBox(width: 12),
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
      ),
    );
  }
}

/// Die Artikelnummer als festes Feld in der Kopfleiste — sie ist der
/// Schlüssel zur Excel-Vorlage und lässt sich nicht ändern.
class _NummernFeld extends StatelessWidget {
  const _NummernFeld({required this.nummer});

  final String nummer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: 'Artikelnummer — Schlüssel zur Excel-Vorlage',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: AppMasse.ecken,
          border: Border.all(color: theme.colorScheme.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tag,
              size: 15,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              nummer,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
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
          return const Center(
            child: LeerHinweis(
              'Artikel nicht gefunden.',
              icon: Icons.search_off,
            ),
          );
        }

        Future<void> bearbeiten() async {
          final geaendert = await ArticleInfoEditorDialog.show(context, p);
          if (geaendert) ref.invalidate(productProvider(productId));
        }

        final eintraege = <_Eintrag>[
          (label: 'Artikelnummer', wert: p.artikelnummer, fehlt: false),
          (label: 'Bezeichnung', wert: p.artikelbezeichnung, fehlt: false),
        ];
        if (p.produktgruppe != null && p.produktgruppe!.isNotEmpty) {
          eintraege.add((
            label: 'Produktgruppe',
            wert: produktgruppeLabels[p.produktgruppe] ?? p.produktgruppe!,
            fehlt: false,
          ),);
        }
        if (p.notizen != null && p.notizen!.isNotEmpty) {
          eintraege.add((label: 'Notizen', wert: p.notizen!, fehlt: false));
        }

        final besonderheiten = p.beschreibung?.trim() ?? '';

        // Merkmale als eigener Bereich: Sie entscheiden später über die
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

        final allergeneOk = allergeneGepflegt(p.allergene);
        final merkmalZeilen = <_Eintrag>[
          (
            label: 'Allergene',
            wert: allergeneOk
                ? merkmaleLabel(p.allergene, kAllergene)
                : 'nicht gepflegt',
            fehlt: !allergeneOk,
          ),
          if (merkmalLabel(p.qualitaetsstufe, kQualitaetsstufen) != null)
            (
              label: 'Qualitätsstufe',
              wert: merkmalLabel(p.qualitaetsstufe, kQualitaetsstufen)!,
              fehlt: false,
            ),
          if (merkmaleLabel(p.verarbeitungsstufe, kVerarbeitungsstufen)
              .isNotEmpty)
            (
              label: 'Verarbeitungsstufe',
              wert: merkmaleLabel(p.verarbeitungsstufe, kVerarbeitungsstufen),
              fehlt: false,
            ),
          if (verpackung.isNotEmpty)
            (label: 'Verpackung', wert: verpackung, fehlt: false),
        ];

        final stammdaten = Bereich(
          titel: 'Stammdaten',
          aktionen: [
            // Noch ein Stub aus Navision: Erst mit Produktgruppe gilt der
            // Artikel als eingepflegt.
            if (!p.istEingepflegt) ...[
              const StatusMarke(
                'nicht eingepflegt',
                art: StatusArt.warnung,
              ),
              const SizedBox(width: 6),
            ],
            TextButton.icon(
              onPressed: bearbeiten,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Bearbeiten'),
            ),
          ],
          innenAbstand: const EdgeInsets.fromLTRB(12, 0, 12, 2),
          child: _InfoTabelle(zeilen: eintraege),
        );
        final merkmale = Bereich(
          titel: 'Merkmale',
          aktionen: [
            TextButton.icon(
              onPressed: bearbeiten,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Bearbeiten'),
            ),
          ],
          innenAbstand: const EdgeInsets.fromLTRB(12, 0, 12, 2),
          child: _InfoTabelle(zeilen: merkmalZeilen),
        );

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                // Breit: Stammdaten und Merkmale nebeneinander, gleich
                // hoch. Schmal: untereinander.
                if (constraints.maxWidth >= 980) {
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: stammdaten),
                        const SizedBox(width: 12),
                        Expanded(child: merkmale),
                      ],
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    stammdaten,
                    const SizedBox(height: 12),
                    merkmale,
                  ],
                );
              },
            ),
            const SizedBox(height: 12),

            // Besonderheiten — eigener Bereich, damit sie auffallen.
            _BesonderheitenKarte(text: besonderheiten, onEdit: bearbeiten),
          ],
        );
      },
    );
  }
}

/// Eine Zeile der Infos: Beschriftung, Wert und ob der Wert fehlt — dann
/// steht er als Warnmarke da.
typedef _Eintrag = ({String label, String wert, bool fehlt});

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

/// Beschriftung links, Wert rechts, dünne Linie dazwischen — wie ein
/// Infofenster in Navision.
class _InfoTabelle extends StatelessWidget {
  const _InfoTabelle({required this.zeilen});

  final List<_Eintrag> zeilen;

  @override
  Widget build(BuildContext context) {
    final linie = Theme.of(context).colorScheme.outlineVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < zeilen.length; i++)
          Container(
            decoration: BoxDecoration(
              border: i == zeilen.length - 1
                  ? null
                  : Border(bottom: BorderSide(color: linie)),
            ),
            child: _InfoZeile(
              label: zeilen[i].label,
              wert: zeilen[i].wert,
              fehlt: zeilen[i].fehlt,
            ),
          ),
      ],
    );
  }
}

class _InfoZeile extends StatelessWidget {
  const _InfoZeile({
    required this.label,
    required this.wert,
    this.fehlt = false,
  });

  final String label;
  final String wert;

  /// Der Wert fehlt — als Warnmarke statt als Text.
  final bool fehlt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: fehlt
                ? Align(
                    alignment: Alignment.centerLeft,
                    heightFactor: 1,
                    child: StatusMarke(wert, art: StatusArt.warnung),
                  )
                : Text(
                    wert,
                    style: theme.textTheme.bodyMedium?.copyWith(
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
      label: const Text('Leistungsdaten'),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Ab ~900px: feste Produktionsmittel-Leiste links — aus ihr lassen
        // sich Anlagen direkt an ihre Stelle in der Kette ziehen.
        if (constraints.maxWidth >= 900) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 212,
                // Dieselbe ruhige Fläche wie die Navigationsleiste: Hier
                // liegt Werkzeug, rechts wird gearbeitet.
                child: ColoredBox(
                  color: AppFarben.von(context).leiste,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: _ProduktionsmittelKatalog(
                      productId: productId,
                      ziehbar: true,
                    ),
                  ),
                ),
              ),
              VerticalDivider(width: 1, color: theme.colorScheme.outline),
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
        // sich als Fenster.
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
