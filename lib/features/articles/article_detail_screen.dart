import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';
import 'article_info_editor_dialog.dart';
import 'bratstrasse_schema.dart';
import 'custom_parameter_editor_dialog.dart';
import 'production_entry_dialog.dart';
import 'step_editor_dialog.dart';

// ---------------------------------------------------------------------------
// Plattentemperatur-Schema: Konstanten + Helfer
// ---------------------------------------------------------------------------

/// dbValue der Abteilung Bratstraße (Schema nur dort anbieten).
const String kAbteilungBratstrasseDb = 'bratstrasse';

/// Marker-Parameter: welcher Schema-Typ am Schritt aktiv ist
/// ('bratstrasse' | 'kombiofen' | leer).
const String kPlattenSchemaParam = 'Plattenschema';

/// Excel-Gruppen, in die die Zonen-Parameter geschrieben werden.
const String kPlattenGruppeBrat = 'BRATSTRASSE';
const String kPlattenGruppeKombi = 'DAMPFTUNNEL';

final RegExp _kZonenRegExp = RegExp(r'^Platte (Oben|Unten) \d+$');

/// `true` für Parameter, die das Schema verwaltet und die deshalb NICHT in der
/// normalen Parameter-Liste auftauchen sollen.
bool istVerstecktesPlattenParam(String name) =>
    name == kPlattenSchemaParam || _kZonenRegExp.hasMatch(name);

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Lädt ein Produkt per ID.
final productProvider =
    FutureProvider.family<Product?, String>((ref, productId) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.products)
        ..where((p) => p.id.equals(productId))
        ..where((p) => p.deletedAt.isNull()))
      .getSingleOrNull();
});

/// Lädt alle Schritte eines Produkts, sortiert nach Reihenfolge.
final productStepsProvider =
    FutureProvider.family<List<ProductStep>, String>((ref, productId) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.productSteps)
        ..where((s) => s.productId.equals(productId))
        ..where((s) => s.deletedAt.isNull())
        ..orderBy([(s) => OrderingTerm.asc(s.reihenfolge)]))
      .get();
});

/// Lädt alle Parameter eines Schritts, sortiert nach Reihenfolge.
final stepParametersProvider =
    FutureProvider.family<List<ProductStepParameter>, String>(
        (ref, stepId) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.productStepParameters)
        ..where((p) => p.stepId.equals(stepId))
        ..where((p) => p.deletedAt.isNull())
        ..orderBy([(p) => OrderingTerm.asc(p.reihenfolge)]))
      .get();
});

/// Lädt eine Maschine per ID.
final machineProvider =
    FutureProvider.family<Machine?, String>((ref, machineId) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.machines)
        ..where((m) => m.id.equals(machineId))
        ..where((m) => m.deletedAt.isNull()))
      .getSingleOrNull();
});

/// Lädt alle angelegten Maschinen (Produktionsmittel-Katalog), nach Name
/// sortiert. Basis für die Produktionsmittel-Sidebar.
final alleMaschinenProvider = FutureProvider<List<Machine>>((ref) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.machines)
        ..where((m) => m.deletedAt.isNull())
        ..orderBy([(m) => OrderingTerm.asc(m.name)]))
      .get();
});

/// Lädt die historischen Produktionen eines Artikels (neueste zuerst).
final productionHistoryProvider =
    FutureProvider.family<List<ProductionHistoryData>, String>(
        (ref, productId) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.productionHistory)
        ..where((h) => h.productId.equals(productId))
        ..where((h) => h.deletedAt.isNull())
        ..orderBy([(h) => OrderingTerm.desc(h.datum)]))
      .get();
});

// ---------------------------------------------------------------------------
// Anzeige-Helfer
// ---------------------------------------------------------------------------

const _produktgruppeLabels = <String, String>{
  'bruehwurst': 'Brühwurst',
  'rohwurst': 'Rohwurst',
  'kochpoekelware': 'Kochpökelware',
  'rohpoekelware': 'Rohpökelware',
  'aufschnitt': 'Aufschnitt',
  'bratstrasse_natur': 'Bratstraßenartikel Natur',
  'bratstrasse_paniert': 'Bratstraßenartikel paniert',
  'hackprodukt_gegart': 'Hackprodukte gegart',
  'hackprodukt_roh': 'Hackprodukte roh',
  'braten': 'Braten',
  'sous_vide': 'Sous Vide gegarte Produkte',
  'angebratene_bruehwurst': 'Angebratene Brühwürste',
};

String _pad(int n) => n.toString().padLeft(2, '0');

String _fmtDatum(DateTime d) => '${_pad(d.day)}.${_pad(d.month)}.${d.year}';

String _fmtKg(double? v) {
  if (v == null) return '—';
  return v == v.roundToDouble()
      ? v.toInt().toString()
      : v.toStringAsFixed(1);
}

String _fmtProzent(double anteil) => '${(anteil * 100).toStringAsFixed(1)} %';

String _fmtDauer(double? minuten) {
  if (minuten == null) return '—';
  final h = (minuten / 60).floor();
  final m = (minuten % 60).round();
  if (h == 0) return '$m min';
  if (m == 0) return '$h h';
  return '$h h $m min';
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

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
            wert: _produktgruppeLabels[p.produktgruppe] ?? p.produktgruppe!,
          ),);
        }
        if (p.beschreibung != null && p.beschreibung!.isNotEmpty) {
          eintraege.add((label: 'Beschreibung', wert: p.beschreibung!));
        }
        if (p.notizen != null && p.notizen!.isNotEmpty) {
          eintraege.add((label: 'Notizen', wert: p.notizen!));
        }

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

class _StepsList extends ConsumerWidget {
  const _StepsList({required this.productId, required this.steps});

  final String productId;
  final List<ProductStep> steps;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // Aufeinanderfolgende Schritte derselben Abteilung zu EINER Karte bündeln
    // (z.B. Bratstraße = Verbufa + Bratstraße + Dampftunnel → eine Karte).
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

    final karten = [
      for (final gruppe in gruppen)
        _AbteilungsKarte(
          gruppe: gruppe,
          onUpdated: () => ref.invalidate(productStepsProvider(productId)),
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Ab ~900px: feste Produktionsmittel-Sidebar links.
        final mitSidebar = constraints.maxWidth >= 900;

        if (mitSidebar) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 236,
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
              Expanded(child: _kartenBereich(false, karten)),
            ],
          );
        }

        // Schmaler: „+ Produktionsmittel"-Button oben, dann die Karten.
        final zweiSpaltig = constraints.maxWidth >= 700;
        return Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _ProduktionsmittelButton(productId: productId),
              ),
            ),
            Expanded(child: _kartenBereich(zweiSpaltig, karten)),
          ],
        );
      },
    );
  }

  /// Karten-Bereich: leerer Hinweis, einspaltig oder zweispaltig verteilt.
  Widget _kartenBereich(bool zweiSpaltig, List<Widget> karten) {
    if (karten.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Noch keine Produktionsschritte.\n\n'
            'Füge ein Produktionsmittel hinzu oder importiere eine '
            'Excel-Vorlage.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    if (!zweiSpaltig) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: karten,
      );
    }

    // Zwei Spalten — jede Karte behält ihre natürliche Höhe.
    final links = <Widget>[];
    final rechts = <Widget>[];
    for (var i = 0; i < karten.length; i++) {
      (i.isEven ? links : rechts).add(karten[i]);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: links,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rechts,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Produktionsmittel-Katalog (Sidebar / Sheet)
// ---------------------------------------------------------------------------

/// Listet alle angelegten Maschinen, nach Abteilung gruppiert. Tippen legt
/// einen Prozess-Schritt mit dieser Maschine an (Editor öffnet vorausgewählt).
/// Häkchen = bereits im Prozess, Plus = noch nicht.
class _ProduktionsmittelKatalog extends ConsumerWidget {
  const _ProduktionsmittelKatalog({required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final maschinenAsync = ref.watch(alleMaschinenProvider);
    final steps = ref.watch(productStepsProvider(productId)).valueOrNull ??
        const <ProductStep>[];
    final imProzess =
        steps.map((s) => s.maschineId).whereType<String>().toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(
              Icons.precision_manufacturing,
              size: 16,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 6),
            Text(
              'Produktionsmittel',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Tippen, um es dem Prozess hinzuzufügen.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 10),
        maschinenAsync.when(
          data: (maschinen) {
            if (maschinen.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Noch keine Maschinen angelegt.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              );
            }

            final byAbt = <String, List<Machine>>{};
            for (final m in maschinen) {
              byAbt.putIfAbsent(m.abteilung, () => []).add(m);
            }

            final zeilen = <Widget>[];
            final bekannt = <String>{};
            for (final abt in Abteilung.values) {
              final liste = byAbt[abt.dbValue];
              if (liste == null || liste.isEmpty) continue;
              bekannt.add(abt.dbValue);
              zeilen.add(_KatalogGruppe(abt: abt));
              for (final m in liste) {
                zeilen.add(
                  _KatalogZeile(
                    farbe: abt.farbe,
                    name: m.name,
                    imProzess: imProzess.contains(m.id),
                    onTap: () => _hinzufuegen(context, ref, m, steps.length),
                  ),
                );
              }
            }

            // Maschinen mit unbekannter Abteilung ans Ende.
            final rest =
                maschinen.where((m) => !bekannt.contains(m.abteilung)).toList();
            if (rest.isNotEmpty) {
              zeilen.add(const _KatalogGruppe());
              for (final m in rest) {
                zeilen.add(
                  _KatalogZeile(
                    farbe: theme.colorScheme.outline,
                    name: m.name,
                    imProzess: imProzess.contains(m.id),
                    onTap: () => _hinzufuegen(context, ref, m, steps.length),
                  ),
                );
              }
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: zeilen,
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (e, _) => Text(
            'Fehler: $e',
            style: const TextStyle(color: Colors.red, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Future<void> _hinzufuegen(
    BuildContext context,
    WidgetRef ref,
    Machine m,
    int anzahlSchritte,
  ) async {
    final ok = await StepEditorDialog.show(
      context,
      productId: productId,
      startMaschine: m,
      stepNumber: anzahlSchritte + 1,
    );
    if (ok) ref.invalidate(productStepsProvider(productId));
  }
}

/// Gruppen-Überschrift im Katalog (Abteilung oder „Weitere" bei abt == null).
class _KatalogGruppe extends StatelessWidget {
  const _KatalogGruppe({this.abt});

  final Abteilung? abt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final farbe = abt?.farbe ?? theme.colorScheme.outline;
    final name = abt?.anzeigeName ?? 'Weitere';
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: farbe, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            name,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// Eine Maschinen-Zeile im Katalog — tippen fügt sie dem Prozess hinzu.
class _KatalogZeile extends StatelessWidget {
  const _KatalogZeile({
    required this.farbe,
    required this.name,
    required this.imProzess,
    required this.onTap,
  });

  final Color farbe;
  final String name;
  final bool imProzess;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: farbe, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              imProzess ? Icons.check_circle : Icons.add_circle_outline,
              size: 16,
              color: imProzess
                  ? Colors.green.shade600
                  : theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}

/// Button (schmale Screens) — öffnet den Katalog als Bottom-Sheet.
class _ProduktionsmittelButton extends StatelessWidget {
  const _ProduktionsmittelButton({required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () {
        final container = ProviderScope.containerOf(context);
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => UncontrolledProviderScope(
            container: container,
            child: _ProduktionsmittelSheet(productId: productId),
          ),
        );
      },
      icon: const Icon(Icons.add, size: 18),
      label: const Text('Produktionsmittel'),
    );
  }
}

/// Inhalt des Produktionsmittel-Bottom-Sheets.
class _ProduktionsmittelSheet extends StatelessWidget {
  const _ProduktionsmittelSheet({required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: _ProduktionsmittelKatalog(productId: productId),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Abteilungs-Karte (bündelt alle Maschinen einer Abteilung)
// ---------------------------------------------------------------------------

class _AbteilungsKarte extends StatelessWidget {
  const _AbteilungsKarte({required this.gruppe, required this.onUpdated});

  final List<({ProductStep step, int nummer})> gruppe;
  final VoidCallback onUpdated;

  Abteilung? get _abteilung {
    try {
      return Abteilung.fromDbValue(gruppe.first.step.abteilung);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final abt = _abteilung;
    final color = abt != null ? abt.farbe : Colors.grey;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Column(
        children: [
          // Abteilungs-Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    abt?.anzeigeName ?? gruppe.first.step.abteilung,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (abt != null) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      abt.kurzcode,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Text(
                  gruppe.length == 1
                      ? '1 Maschine'
                      : '${gruppe.length} Maschinen',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),

          // Maschinen-Blöcke (alle ausgeklappt untereinander)
          for (var i = 0; i < gruppe.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _MaschinenBlock(
              step: gruppe[i].step,
              stepNumber: gruppe[i].nummer,
              onUpdated: onUpdated,
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Maschinen-Block (eine Maschine innerhalb der Abteilungs-Karte)
// ---------------------------------------------------------------------------

class _MaschinenBlock extends ConsumerStatefulWidget {
  const _MaschinenBlock({
    required this.step,
    required this.stepNumber,
    required this.onUpdated,
  });

  final ProductStep step;
  final int stepNumber;
  final VoidCallback onUpdated;

  @override
  ConsumerState<_MaschinenBlock> createState() => _MaschinenBlockState();
}

class _MaschinenBlockState extends ConsumerState<_MaschinenBlock> {
  Future<void> _openEditor() async {
    final geaendert = await StepEditorDialog.show(
      context,
      step: widget.step,
      stepNumber: widget.stepNumber,
    );
    if (geaendert) widget.onUpdated();
  }

  Future<void> _loescheSchritt() async {
    final name = (widget.step.maschine != null &&
            widget.step.maschine!.isNotEmpty)
        ? widget.step.maschine!
        : 'Dieser Schritt';
    final bestaetigt = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aus Prozess entfernen?'),
        content: Text(
          '„$name" wird aus dem Prozess dieses Artikels entfernt. '
          'Die Maschine selbst bleibt erhalten und kann jederzeit wieder '
          'hinzugefügt werden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Entfernen'),
          ),
        ],
      ),
    );
    if (bestaetigt != true) return;
    final db = ref.read(databaseProvider);
    await (db.update(db.productSteps)
          ..where((s) => s.id.equals(widget.step.id)))
        .write(
      ProductStepsCompanion(
        deletedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
    ref.read(autoBackupTriggerProvider).fireDebounced(
          reason: 'Schritt aus Prozess entfernt',
        );
    widget.onUpdated();
  }

  Future<void> _editNumber({
    required String titel,
    required double? aktuell,
    String? suffix,
    required ProductStepsCompanion Function(double) bauen,
  }) async {
    final ctrl = TextEditingController(
      text: (aktuell != null && aktuell > 0) ? _fmtZahl(aktuell) : '',
    );
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titel),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Wert',
            suffixText: suffix,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (res == null) return;
    final zahl = double.tryParse(res.replaceAll(',', '.')) ?? 0.0;
    final db = ref.read(databaseProvider);
    await (db.update(db.productSteps)
          ..where((s) => s.id.equals(widget.step.id)))
        .write(bauen(zahl));
    ref.read(autoBackupTriggerProvider).fireDebounced(
          reason: 'Schritt-Wert geändert',
        );
    widget.onUpdated();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.step;
    final maschineName = (s.maschine != null && s.maschine!.isNotEmpty)
        ? s.maschine!
        : ((s.prozessschritt != null && s.prozessschritt!.isNotEmpty)
            ? s.prozessschritt!
            : 'Maschine ${widget.stepNumber}');
    final zeigeProzess = s.prozessschritt != null &&
        s.prozessschritt!.isNotEmpty &&
        s.maschine != null &&
        s.maschine!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Maschinen-Kopf
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.factory, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      maschineName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (zeigeProzess) ...[
                      const SizedBox(height: 2),
                      Text(
                        s.prozessschritt!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit, size: 18),
                tooltip: 'Maschine/Schritt bearbeiten',
                visualDensity: VisualDensity.compact,
                onPressed: _openEditor,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: 'Aus Prozess entfernen',
                visualDensity: VisualDensity.compact,
                color: theme.colorScheme.error,
                onPressed: _loescheSchritt,
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Editierbare Werte als ruhige, gleichmäßige Leiste
          Row(
            children: [
              Expanded(
                child: _WertFeld(
                  label: 'Personen',
                  wert: s.basisMitarbeiter > 0 ? '${s.basisMitarbeiter}' : '–',
                  onTap: () => _editNumber(
                    titel: 'Personen',
                    aktuell: s.basisMitarbeiter.toDouble(),
                    bauen: (v) => ProductStepsCompanion(
                      basisMitarbeiter: Value(v.round() < 1 ? 1 : v.round()),
                      updatedAt: Value(DateTime.now()),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _WertFeld(
                  label: 'Menge',
                  wert: s.basisMengeKg > 0 ? '${_fmtZahl(s.basisMengeKg)} kg' : '–',
                  onTap: () => _editNumber(
                    titel: 'Menge (kg)',
                    aktuell: s.basisMengeKg,
                    suffix: 'kg',
                    bauen: (v) => ProductStepsCompanion(
                      basisMengeKg: Value(v),
                      mengeKg: Value(v > 0 ? v : null),
                      updatedAt: Value(DateTime.now()),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _WertFeld(
                  label: 'Dauer',
                  wert: s.basisDauerMinuten > 0
                      ? _fmtDauer(s.basisDauerMinuten)
                      : '–',
                  onTap: () => _editNumber(
                    titel: 'Dauer (min)',
                    aktuell: s.basisDauerMinuten,
                    suffix: 'min',
                    bauen: (v) => ProductStepsCompanion(
                      basisDauerMinuten: Value(v),
                      updatedAt: Value(DateTime.now()),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _WertFeld(
                  label: 'Fixe Zeit',
                  wert: (s.fixZeitMinuten ?? 0) > 0
                      ? _fmtDauer(s.fixZeitMinuten!)
                      : '–',
                  onTap: () => _editNumber(
                    titel: 'Fixe Zeit / Durchlauf (min)',
                    aktuell: s.fixZeitMinuten,
                    suffix: 'min',
                    bauen: (v) => ProductStepsCompanion(
                      fixZeitMinuten: Value(v > 0 ? v : null),
                      updatedAt: Value(DateTime.now()),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Plattentemperatur-Schema (nur in der Abteilung Bratstraße)
          if (s.abteilung == kAbteilungBratstrasseDb) ...[
            _PlattenSchemaBereich(step: s, onUpdated: widget.onUpdated),
            const SizedBox(height: 12),
          ],

          // Parameter (Standard + Custom, beide editierbar)
          _ParameterListe(stepId: s.id),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Plattentemperatur-Schema-Bereich (Typ-Auswahl + Schema, speichert als
// benannte Parameter „Platte Oben/Unten N")
// ---------------------------------------------------------------------------

class _PlattenSchemaBereich extends ConsumerWidget {
  const _PlattenSchemaBereich({required this.step, required this.onUpdated});

  final ProductStep step;
  final VoidCallback onUpdated;

  static ProductStepParameter? _find(
    List<ProductStepParameter> params,
    String name,
  ) {
    for (final p in params) {
      if (p.parameterName == name) return p;
    }
    return null;
  }

  static String _zahlText(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  BratschemaTyp? _typVon(String? wert) {
    switch (wert) {
      case 'bratstrasse':
        return BratschemaTyp.bratstrasse;
      case 'kombiofen':
        return BratschemaTyp.kombiofen;
      default:
        return null;
    }
  }

  String _gruppeVon(BratschemaTyp typ) =>
      typ == BratschemaTyp.kombiofen ? kPlattenGruppeKombi : kPlattenGruppeBrat;

  PlattenTemperaturen _leseWerte(
    List<ProductStepParameter> params,
    BratschemaTyp typ,
  ) {
    final leer = PlattenTemperaturen.leer(typ);
    double? wertVon(String name) {
      final w = _find(params, name)?.wert;
      if (w == null || w.trim().isEmpty) return null;
      return double.tryParse(w.replaceAll(',', '.'));
    }

    final oben = [
      for (var i = 0; i < leer.oben.length; i++) wertVon('Platte Oben ${i + 1}'),
    ];
    final unten = [
      for (var i = 0; i < leer.unten.length; i++)
        wertVon('Platte Unten ${i + 1}'),
    ];
    return PlattenTemperaturen(oben: oben, unten: unten);
  }

  Future<void> _upsert(
    WidgetRef ref,
    List<ProductStepParameter> params,
    String name,
    String gruppe,
    String? wert,
  ) async {
    final db = ref.read(databaseProvider);
    final vorhanden = _find(params, name);
    if (vorhanden != null) {
      await (db.update(db.productStepParameters)
            ..where((p) => p.id.equals(vorhanden.id)))
          .write(
        ProductStepParametersCompanion(
          wert: Value(wert),
          updatedAt: Value(DateTime.now()),
        ),
      );
    } else {
      await db.into(db.productStepParameters).insert(
            ProductStepParametersCompanion(
              id: Value(const Uuid().v4()),
              stepId: Value(step.id),
              parameterGruppe: Value(gruppe),
              parameterName: Value(name),
              wert: Value(wert),
              reihenfolge: const Value(100),
              istCustom: const Value(false),
            ),
          );
    }
  }

  Future<void> _setzeTyp(
    WidgetRef ref,
    List<ProductStepParameter> params,
    String? v,
  ) async {
    final wert = (v == null || v == 'keine') ? null : v;
    await _upsert(
      ref,
      params,
      kPlattenSchemaParam,
      kPlattenGruppeBrat,
      wert,
    );
    ref.read(autoBackupTriggerProvider).fireDebounced(
          reason: 'Plattenschema geändert',
        );
    ref.invalidate(stepParametersProvider(step.id));
    onUpdated();
  }

  Future<void> _speichereWerte(
    WidgetRef ref,
    List<ProductStepParameter> params,
    BratschemaTyp typ,
    PlattenTemperaturen neu,
  ) async {
    final gruppe = _gruppeVon(typ);
    final alt = _leseWerte(params, typ);
    for (var i = 0; i < neu.oben.length; i++) {
      if (neu.oben[i] != alt.oben[i]) {
        await _upsert(
          ref,
          params,
          'Platte Oben ${i + 1}',
          gruppe,
          neu.oben[i] == null ? null : _zahlText(neu.oben[i]!),
        );
      }
    }
    for (var i = 0; i < neu.unten.length; i++) {
      if (neu.unten[i] != alt.unten[i]) {
        await _upsert(
          ref,
          params,
          'Platte Unten ${i + 1}',
          gruppe,
          neu.unten[i] == null ? null : _zahlText(neu.unten[i]!),
        );
      }
    }
    ref.read(autoBackupTriggerProvider).fireDebounced(
          reason: 'Plattentemperatur geändert',
        );
    ref.invalidate(stepParametersProvider(step.id));
    onUpdated();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final paramsAsync = ref.watch(stepParametersProvider(step.id));

    return paramsAsync.when(
      data: (params) {
        final typ = _typVon(_find(params, kPlattenSchemaParam)?.wert);
        final auswahl = typ == null
            ? 'keine'
            : (typ == BratschemaTyp.kombiofen ? 'kombiofen' : 'bratstrasse');

        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Plattentemperaturen',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const Spacer(),
                  DropdownButton<String>(
                    value: auswahl,
                    isDense: true,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 'keine', child: Text('Keine')),
                      DropdownMenuItem(
                        value: 'bratstrasse',
                        child: Text('Bratstraße (10+10)'),
                      ),
                      DropdownMenuItem(
                        value: 'kombiofen',
                        child: Text('Kombiofen (12 unten)'),
                      ),
                    ],
                    onChanged: (v) => _setzeTyp(ref, params, v),
                  ),
                ],
              ),
              if (typ != null) ...[
                const SizedBox(height: 8),
                BratstrasseSchema(
                  typ: typ,
                  werte: _leseWerte(params, typ),
                  onChanged: (neu) =>
                      _speichereWerte(ref, params, typ, neu),
                ),
              ],
            ],
          ),
        );
      },
      loading: () => const SizedBox(
        height: 24,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (e, _) => Text(
        'Schema-Fehler: $e',
        style: const TextStyle(color: Colors.red, fontSize: 12),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Werte-Feld (Label oben, Wert unten — antippbar zum Bearbeiten)
// ---------------------------------------------------------------------------

class _WertFeld extends StatelessWidget {
  const _WertFeld({
    required this.label,
    required this.wert,
    required this.onTap,
  });

  final String label;
  final String wert;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.edit,
                  size: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              wert,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

String _fmtZahl(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

// ---------------------------------------------------------------------------
// Parameter-Liste
// ---------------------------------------------------------------------------

class _ParameterListe extends ConsumerWidget {
  const _ParameterListe({required this.stepId});

  final String stepId;

  Future<void> _customLoeschen(
    BuildContext context,
    WidgetRef ref,
    ProductStepParameter param,
  ) async {
    final bestaetigt = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Parameter löschen?'),
        content: Text('Parameter „${param.parameterName}" wird gelöscht.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (bestaetigt != true) return;

    final db = ref.read(databaseProvider);
    await (db.update(db.productStepParameters)
          ..where((p) => p.id.equals(param.id)))
        .write(
      ProductStepParametersCompanion(
        deletedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );

    ref.read(autoBackupTriggerProvider).fireDebounced(
          reason: 'Custom-Parameter gelöscht',
        );
    ref.invalidate(stepParametersProvider(stepId));
  }

  Future<void> _standardBearbeiten(
    BuildContext context,
    WidgetRef ref,
    ProductStepParameter param,
  ) async {
    final ctrl = TextEditingController(text: param.wert ?? '');
    final neuerWert = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(param.parameterName),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Wert',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (neuerWert == null) return;

    final db = ref.read(databaseProvider);
    await (db.update(db.productStepParameters)
          ..where((p) => p.id.equals(param.id)))
        .write(
      ProductStepParametersCompanion(
        wert: Value(neuerWert.isEmpty ? null : neuerWert),
        updatedAt: Value(DateTime.now()),
      ),
    );

    ref.read(autoBackupTriggerProvider).fireDebounced(
          reason: 'Parameter geändert',
        );
    ref.invalidate(stepParametersProvider(stepId));
  }

  Future<void> _customNeu(BuildContext context, WidgetRef ref) async {
    final geaendert = await CustomParameterEditorDialog.show(
      context,
      stepId: stepId,
    );
    if (geaendert) {
      ref.invalidate(stepParametersProvider(stepId));
    }
  }

  Future<void> _customBearbeiten(
    BuildContext context,
    WidgetRef ref,
    ProductStepParameter param,
  ) async {
    final geaendert = await CustomParameterEditorDialog.show(
      context,
      stepId: stepId,
      existingParameter: param,
    );
    if (geaendert) {
      ref.invalidate(stepParametersProvider(stepId));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final paramsAsync = ref.watch(stepParametersProvider(stepId));

    return paramsAsync.when(
      data: (alleParams) {
        final params = alleParams
            .where((p) => !istVerstecktesPlattenParam(p.parameterName))
            .toList();
        final standardParams = params.where((p) => !p.istCustom).toList();
        final customParams = params.where((p) => p.istCustom).toList();

        // Standard-Parameter nach Gruppen aufteilen
        final standardByGruppe = <String, List<ProductStepParameter>>{};
        for (final p in standardParams) {
          standardByGruppe.putIfAbsent(p.parameterGruppe, () => []).add(p);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.tune,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Parameter',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Standard-Parameter (readonly)
            if (standardByGruppe.isNotEmpty) ...[
              for (final entry in standardByGruppe.entries) ...[
                _StandardGruppenBlock(
                  gruppenName: entry.key,
                  parameter: entry.value,
                  onEdit: (p) => _standardBearbeiten(context, ref, p),
                ),
                const SizedBox(height: 8),
              ],
            ],

            // Custom-Parameter (editierbar)
            _CustomGruppenBlock(
              parameter: customParams,
              onAdd: () => _customNeu(context, ref),
              onEdit: (p) => _customBearbeiten(context, ref, p),
              onDelete: (p) => _customLoeschen(context, ref, p),
            ),

            if (standardByGruppe.isEmpty && customParams.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Keine Parameter hinterlegt.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
          ],
        );
      },
      loading: () => const SizedBox(
        height: 30,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => Text(
        'Parameter-Fehler: $e',
        style: const TextStyle(color: Colors.red, fontSize: 12),
      ),
    );
  }
}

/// Block für Standard-Parameter aus der Excel-Vorlage. Editierbar
/// (Werte werden beim Export wieder in die Excel zurückgeschrieben).
class _StandardGruppenBlock extends StatelessWidget {
  const _StandardGruppenBlock({
    required this.gruppenName,
    required this.parameter,
    required this.onEdit,
  });

  final String gruppenName;
  final List<ProductStepParameter> parameter;
  final void Function(ProductStepParameter) onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                gruppenName,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...parameter.map(
            (p) => _ParameterZeileStandard(
              param: p,
              onEdit: () => onEdit(p),
            ),
          ),
        ],
      ),
    );
  }
}

/// Block für Custom-Parameter (vom Nutzer angelegt). Editierbar.
class _CustomGruppenBlock extends StatelessWidget {
  const _CustomGruppenBlock({
    required this.parameter,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final List<ProductStepParameter> parameter;
  final VoidCallback onAdd;
  final void Function(ProductStepParameter) onEdit;
  final void Function(ProductStepParameter) onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Zusätzliche Parameter',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 16),
                label: const Text(
                  'Neu',
                  style: TextStyle(fontSize: 12),
                ),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          if (parameter.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'Noch keine zusätzlichen Parameter angelegt.',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            )
          else
            ...parameter.map(
              (p) => _ParameterZeileEditierbar(
                param: p,
                onEdit: () => onEdit(p),
                onDelete: () => onDelete(p),
              ),
            ),
        ],
      ),
    );
  }
}

/// Eine Standard-Parameter-Zeile — tippen zum Bearbeiten des Werts.
class _ParameterZeileStandard extends StatelessWidget {
  const _ParameterZeileStandard({
    required this.param,
    required this.onEdit,
  });

  final ProductStepParameter param;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 2,
              child: Text(
                param.parameterName,
                style: theme.textTheme.bodySmall,
              ),
            ),
            Expanded(
              flex: 1,
              child: Text(
                param.wert ?? '—',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            Icon(
              Icons.edit,
              size: 14,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}

/// Eine Parameter-Zeile mit Bearbeiten/Löschen (für Custom-Parameter).
class _ParameterZeileEditierbar extends StatelessWidget {
  const _ParameterZeileEditierbar({
    required this.param,
    required this.onEdit,
    required this.onDelete,
  });

  final ProductStepParameter param;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              param.parameterName,
              style: theme.textTheme.bodySmall,
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              param.wert ?? '—',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit, size: 16),
            tooltip: 'Bearbeiten',
            onPressed: onEdit,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 16),
            tooltip: 'Löschen',
            onPressed: onDelete,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 3: Produktionsdaten
// ---------------------------------------------------------------------------

class _ProductionTab extends ConsumerWidget {
  const _ProductionTab({required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final histAsync = ref.watch(productionHistoryProvider(productId));

    return histAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Noch keine Produktionsdaten.\n\n'
                'Importiere eine Excel-Vorlage mit ausgefülltem Block '
                '„HISTORISCHE DATEN", dann erscheinen hier alle '
                'vergangenen Produktionen samt Ausbeute und kg/h.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _KennzahlenCard(rows: rows),
            const SizedBox(height: 16),
            Text(
              'Vergangene Produktionen (${rows.length})',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            for (final r in rows)
              _HistorieCard(
                eintrag: r,
                onTap: () async {
                  final geaendert = await ProductionEntryDialog.show(
                    context,
                    productId,
                    existing: r,
                  );
                  if (geaendert) {
                    ref.invalidate(productionHistoryProvider(productId));
                  }
                },
              ),
          ],
        );
      },
    );
  }
}

/// Aggregierte Kennzahlen über alle historischen Produktionen.
class _KennzahlenCard extends StatelessWidget {
  const _KennzahlenCard({required this.rows});

  final List<ProductionHistoryData> rows;

  @override
  Widget build(BuildContext context) {
    double summeRoh = 0;
    double summeFertig = 0;
    var hatMengen = false;

    final kgHWerte = <double>[];
    for (final r in rows) {
      if (r.kgRohware != null) {
        summeRoh += r.kgRohware!;
        hatMengen = true;
      }
      if (r.kgFertigware != null) summeFertig += r.kgFertigware!;
      if (r.kgProStundeRoh != null) kgHWerte.add(r.kgProStundeRoh!);
    }

    final double? ausbeute =
        (hatMengen && summeRoh > 0) ? summeFertig / summeRoh : null;
    final double? garverlust = ausbeute != null ? 1 - ausbeute : null;
    final double? avgKgH = kgHWerte.isNotEmpty
        ? kgHWerte.reduce((a, b) => a + b) / kgHWerte.length
        : null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF37474F), Color(0xFF455A64)],
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.insights, color: Colors.white, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Kennzahlen',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 20,
              runSpacing: 16,
              children: [
                _Kennzahl(
                  value: '${rows.length}',
                  label: 'Produktionen',
                ),
                if (ausbeute != null)
                  _Kennzahl(
                    value: _fmtProzent(ausbeute),
                    label: 'Ø Ausbeute',
                  ),
                if (garverlust != null)
                  _Kennzahl(
                    value: _fmtProzent(garverlust),
                    label: 'Ø Garverlust',
                    valueColor: const Color(0xFFFF8A65),
                  ),
                if (avgKgH != null)
                  _Kennzahl(
                    value: '${_fmtKg(avgKgH)} kg/h',
                    label: 'Ø Durchsatz roh',
                  ),
              ],
            ),
            if (hatMengen) ...[
              const SizedBox(height: 14),
              Text(
                'Gesamt: ${_fmtKg(summeRoh)} kg Rohware → '
                '${_fmtKg(summeFertig)} kg Fertigware',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Kennzahl extends StatelessWidget {
  const _Kennzahl({
    required this.value,
    required this.label,
    this.valueColor,
  });

  final String value;
  final String label;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 11),
        ),
      ],
    );
  }
}

/// Eine vergangene Produktion als Karte.
class _HistorieCard extends StatelessWidget {
  const _HistorieCard({required this.eintrag, this.onTap});

  final ProductionHistoryData eintrag;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Garverlust: gespeicherten Anteil bevorzugen, sonst aus Roh/Fertig.
    double? verlust = eintrag.verlustAnteil;
    if (verlust == null &&
        eintrag.kgRohware != null &&
        eintrag.kgFertigware != null &&
        eintrag.kgRohware! > 0) {
      verlust = 1 - (eintrag.kgFertigware! / eintrag.kgRohware!);
    }

    final zeitText = (eintrag.startzeit != null && eintrag.endzeit != null)
        ? '${eintrag.startzeit} – ${eintrag.endzeit}'
        : (eintrag.startzeit ?? '');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.event,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  _fmtDatum(eintrag.datum),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (eintrag.quelle == 'app')
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'in App erfasst',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFF2E7D32),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 18,
              runSpacing: 10,
              children: [
                _HistWert(
                  label: 'Rohware',
                  value: '${_fmtKg(eintrag.kgRohware)} kg',
                ),
                _HistWert(
                  label: 'Fertigware',
                  value: '${_fmtKg(eintrag.kgFertigware)} kg',
                ),
                if (verlust != null)
                  _HistWert(
                    label: 'Garverlust',
                    value: _fmtProzent(verlust),
                  ),
                if (eintrag.produktionszeitMinuten != null)
                  _HistWert(
                    label: 'Dauer',
                    value: _fmtDauer(eintrag.produktionszeitMinuten),
                  ),
                if (eintrag.kgProStundeRoh != null)
                  _HistWert(
                    label: 'kg/h roh',
                    value: _fmtKg(eintrag.kgProStundeRoh),
                  ),
              ],
            ),
            if (zeitText.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.schedule,
                    size: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    zeitText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
            if (eintrag.notizen != null && eintrag.notizen!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                eintrag.notizen!,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
          ),
        ),
      ),
    );
  }
}

class _HistWert extends StatelessWidget {
  const _HistWert({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}