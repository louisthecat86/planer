import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';
import 'article_info_editor_dialog.dart';
import 'article_print_service.dart';
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

/// Name der Parameterzeile für das freie Notizfeld je Maschine.
/// Ersetzt starre Einzelparameter (Takte, Volumen …) — die Einstellungen
/// sind so individuell, dass ein Freitextfeld praktischer ist.
const String kMaschinenNotizParam = 'Maschineneinstellungen';
const String kMaschinenNotizGruppe = 'MASCHINENEINSTELLUNGEN';

/// Nur diese Maschinen haben ein festes Plattenraster
/// (Bratstraße 10+10, Dampftunnel 12). „Heißluftofen" ist dieselbe
/// Anlage wie der Dampftunnel — beide Namen führen zum 12er-Raster.
/// Alle anderen bekommen das freie Notizfeld „Maschineneinstellungen".
bool istPlattenMaschine(String maschineName) {
  final n = maschineName.toLowerCase();
  return n.contains('bratstra') ||
      n.contains('dampftunnel') ||
      n.contains('heißluft') ||
      n.contains('heissluft');
}

bool istDampftunnelMaschine(String maschineName) {
  final n = maschineName.toLowerCase();
  return n.contains('dampftunnel') ||
      n.contains('heißluft') ||
      n.contains('heissluft');
}

bool _istBratstrasseMaschine(String maschineName) =>
    maschineName.toLowerCase().contains('bratstra');

final RegExp _kZonenRegExp = RegExp(r'^Platte (Oben|Unten) \d+$');

/// `true` für Parameter, die das Schema verwaltet und die deshalb NICHT in der
/// normalen Parameter-Liste auftauchen sollen.
bool istVerstecktesPlattenParam(String name) =>
    name == kPlattenSchemaParam ||
    name == kMaschinenNotizParam ||
    _kZonenRegExp.hasMatch(name);

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
/// Steckbrief-Parameter der Maschine eines Schritts (aus dem
/// Maschinen-Katalog). Bestimmt, welche Eingabefelder am Schritt erscheinen.
final _steckbriefDefsProvider =
    FutureProvider.family<List<MachineParameterDef>, String>(
        (ref, maschineId) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.machineParameterDefs)
        ..where((d) => d.maschineId.equals(maschineId))
        ..where((d) => d.deletedAt.isNull())
        ..orderBy([
          (d) => OrderingTerm.asc(d.sortierung),
          (d) => OrderingTerm.asc(d.parameterName),
        ]))
      .get();
});

/// Grenz-Definition für einen Parameter suchen: zuerst maschinenspezifisch
/// (kontext = Anlagen-Name), dann gruppenweit (kontext = Parametergruppe).
Future<ParameterGrenzenData?> _grenzeFuer(
  AppDatabase db, {
  String? maschinenName,
  required String gruppe,
  required String parameterName,
}) async {
  Future<ParameterGrenzenData?> such(String kontext) async {
    final rows = await (db.select(db.parameterGrenzen)
          ..where((g) => g.kontext.equals(kontext))
          ..where((g) => g.parameterName.equals(parameterName))
          ..where((g) => g.deletedAt.isNull())
          ..limit(1))
        .get();
    return rows.isEmpty ? null : rows.first;
  }

  if (maschinenName != null && maschinenName.trim().isNotEmpty) {
    final m = await such(maschinenName.trim());
    if (m != null) return m;
  }
  return such(gruppe);
}

/// Prüfergebnis der Grenzen-Prüfung.
enum _GrenzenStatus { ok, warnung, blockiert }

({_GrenzenStatus status, String? meldung}) _pruefeWert(
  ParameterGrenzenData? grenze,
  String wert,
) {
  if (grenze == null) return (status: _GrenzenStatus.ok, meldung: null);
  final zahl = double.tryParse(wert.replaceAll(',', '.'));
  // Nicht-numerische Werte werden nicht geprüft.
  if (zahl == null) return (status: _GrenzenStatus.ok, meldung: null);

  String z(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  if (grenze.hartMin != null && zahl < grenze.hartMin!) {
    return (
      status: _GrenzenStatus.blockiert,
      meldung: 'Unter der technischen Untergrenze (${z(grenze.hartMin!)}).',
    );
  }
  if (grenze.hartMax != null && zahl > grenze.hartMax!) {
    return (
      status: _GrenzenStatus.blockiert,
      meldung: 'Über der technischen Obergrenze (${z(grenze.hartMax!)}).',
    );
  }
  if (grenze.weichMin != null && zahl < grenze.weichMin!) {
    return (
      status: _GrenzenStatus.warnung,
      meldung: 'Ungewöhnlich niedrig — üblich ist ab ${z(grenze.weichMin!)}.',
    );
  }
  if (grenze.weichMax != null && zahl > grenze.weichMax!) {
    return (
      status: _GrenzenStatus.warnung,
      meldung: 'Ungewöhnlich hoch — üblich ist bis ${z(grenze.weichMax!)}.',
    );
  }
  return (status: _GrenzenStatus.ok, meldung: null);
}

/// Wert-Dialog mit Grenzen-Prüfung: harte Verstöße blockieren das
/// Speichern, weiche zeigen eine Warnung (Speichern trotzdem möglich).
Future<String?> _wertDialogMitPruefung(
  BuildContext context, {
  required AppDatabase db,
  required String titel,
  required String initial,
  required String gruppe,
  required String parameterName,
  String? maschinenName,
  String? einheit,
}) async {
  final grenze = await _grenzeFuer(
    db,
    maschinenName: maschinenName,
    gruppe: gruppe,
    parameterName: parameterName,
  );
  if (!context.mounted) return null;

  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      String? fehlerText;
      String? warnText;
      return StatefulBuilder(
        builder: (ctx, setState) {
          void pruefen(String v) {
            final r = _pruefeWert(grenze, v.trim());
            setState(() {
              fehlerText =
                  r.status == _GrenzenStatus.blockiert ? r.meldung : null;
              warnText =
                  r.status == _GrenzenStatus.warnung ? r.meldung : null;
            });
          }

          void speichern() {
            final v = ctrl.text.trim();
            final r = _pruefeWert(grenze, v);
            if (r.status == _GrenzenStatus.blockiert) {
              setState(() => fehlerText = r.meldung);
              return;
            }
            Navigator.of(ctx).pop(v);
          }

          return AlertDialog(
            title: Text(titel),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Wert',
                    suffixText: einheit,
                    border: const OutlineInputBorder(),
                    errorText: fehlerText,
                  ),
                  onChanged: pruefen,
                  onSubmitted: (_) => speichern(),
                ),
                if (warnText != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          warnText!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.orange,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: speichern,
                child: const Text('Speichern'),
              ),
            ],
          );
        },
      );
    },
  ).whenComplete(ctrl.dispose);
}

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
            wert: _produktgruppeLabels[p.produktgruppe] ?? p.produktgruppe!,
          ),);
        }
        if (p.notizen != null && p.notizen!.isNotEmpty) {
          eintraege.add((label: 'Notizen', wert: p.notizen!));
        }

        final besonderheiten = p.beschreibung?.trim() ?? '';

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
  /// Prozesses Menge/Zeit/Personen ab und schreibt die Werte auf den
  /// jeweils ersten Schritt der Abteilungsgruppe (Excel-Konvention).
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
      for (var g = 0; g < gruppen.length; g++)
        _AbteilungsKarte(
          gruppe: gruppen[g],
          position: g + 1,
          onMoveUp: g == 0
              ? null
              : () => _verschiebeGruppe(ref, gruppen, g, -1),
          onMoveDown: g == gruppen.length - 1
              ? null
              : () => _verschiebeGruppe(ref, gruppen, g, 1),
          onUpdated: () => ref.invalidate(productStepsProvider(productId)),
        ),
    ];

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
        : _kartenBereich(zweiSpaltig, karten);

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
            final byAbt = <String, List<Machine>>{};
            for (final m in maschinen) {
              byAbt.putIfAbsent(m.abteilung, () => []).add(m);
            }

            final gruppen = <Widget>[];
            final bekannt = <String>{};
            for (final abt in Abteilung.values) {
              final liste = byAbt[abt.dbValue] ?? const <Machine>[];
              bekannt.add(abt.dbValue);
              gruppen.add(
                _KatalogAbteilung(
                  abt: abt,
                  maschinen: liste,
                  imProzess: imProzess,
                  onTapMaschine: (m) =>
                      _hinzufuegen(context, ref, m, steps.length),
                  onNeueAnlage: () => _neueAnlage(context, ref, abt),
                ),
              );
            }

            // Maschinen mit unbekannter Abteilung ans Ende.
            final rest =
                maschinen.where((m) => !bekannt.contains(m.abteilung)).toList();
            if (rest.isNotEmpty) {
              gruppen.add(
                _KatalogAbteilung(
                  abt: null,
                  maschinen: rest,
                  imProzess: imProzess,
                  onTapMaschine: (m) =>
                      _hinzufuegen(context, ref, m, steps.length),
                  onNeueAnlage: null,
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: gruppen,
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

  /// Legt eine neue Anlage in der gewählten Abteilung an.
  ///
  /// Sie steht danach sofort im Katalog und wird beim nächsten
  /// Excel-Export automatisch in den Anlagen-Katalog der Vorlage
  /// eingetragen (inkl. Abteilung).
  Future<void> _neueAnlage(
    BuildContext context,
    WidgetRef ref,
    Abteilung abt,
  ) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Neue Anlage · ${abt.anzeigeName}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Name der Anlage',
            hintText: 'z.B. Kochkammer 5',
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
            child: const Text('Anlegen'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    final db = ref.read(databaseProvider);

    // Doppelte Namen vermeiden (Katalog + Excel sind namensbasiert).
    final vorhandene =
        ref.read(alleMaschinenProvider).valueOrNull ?? const <Machine>[];
    if (vorhandene.any(
      (m) => m.name.trim().toLowerCase() == name.toLowerCase(),
    )) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Anlage "$name" existiert bereits.')),
        );
      }
      return;
    }

    await db.into(db.machines).insert(
          MachinesCompanion(
            id: Value(const Uuid().v4()),
            name: Value(name),
            abteilung: Value(abt.dbValue),
          ),
        );

    ref.read(autoBackupTriggerProvider).fireDebounced(
          reason: 'Neue Anlage angelegt',
        );
    ref.invalidate(alleMaschinenProvider);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Anlage "$name" in ${abt.anzeigeName} angelegt — wird beim '
            'nächsten Excel-Export in den Anlagen-Katalog übernommen.',
          ),
        ),
      );
    }
  }
}

/// Aufklappbare Abteilungs-Gruppe im Katalog. Standard: zugeklappt —
/// so bleibt die Sidebar kurz und das Diagramm bekommt die Bühne.
class _KatalogAbteilung extends StatefulWidget {
  const _KatalogAbteilung({
    required this.abt,
    required this.maschinen,
    required this.imProzess,
    required this.onTapMaschine,
    required this.onNeueAnlage,
  });

  /// null = Gruppe „Weitere" (unbekannte Abteilung).
  final Abteilung? abt;
  final List<Machine> maschinen;
  final Set<String> imProzess;
  final void Function(Machine) onTapMaschine;
  final VoidCallback? onNeueAnlage;

  @override
  State<_KatalogAbteilung> createState() => _KatalogAbteilungState();
}

class _KatalogAbteilungState extends State<_KatalogAbteilung> {
  bool _offen = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final farbe = widget.abt?.farbe ?? theme.colorScheme.outline;
    final name = widget.abt?.anzeigeName ?? 'Weitere';
    final anzahlImProzess = widget.maschinen
        .where((m) => widget.imProzess.contains(m.id))
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _offen = !_offen),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: _offen ? 0.25 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(
                    Icons.chevron_right,
                    size: 17,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(width: 2),
                Container(
                  width: 9,
                  height: 9,
                  decoration:
                      BoxDecoration(color: farbe, shape: BoxShape.circle),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    name,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Anzahl (grün, wenn welche im Prozess sind)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: anzahlImProzess > 0
                        ? const Color(0xFF2E7D32).withValues(alpha: 0.25)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    anzahlImProzess > 0
                        ? '$anzahlImProzess/${widget.maschinen.length}'
                        : '${widget.maschinen.length}',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: anzahlImProzess > 0
                          ? (theme.brightness == Brightness.dark
                              ? const Color(0xFF9CCC65)
                              : const Color(0xFF2E7D32))
                          : theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_offen)
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final m in widget.maschinen)
                  _KatalogZeile(
                    farbe: farbe,
                    name: m.name,
                    imProzess: widget.imProzess.contains(m.id),
                    onTap: () => widget.onTapMaschine(m),
                  ),
                if (widget.onNeueAnlage != null)
                  InkWell(
                    onTap: widget.onNeueAnlage,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 7,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.add_circle_outline,
                            size: 15,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Neue Anlage …',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
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
  const _AbteilungsKarte({
    required this.gruppe,
    required this.position,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onUpdated,
  });

  final int position;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

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
                // Position in der Produktionsabfolge — groß und eindeutig
                Container(
                  width: 28,
                  height: 28,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Text(
                    '$position',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
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
                const SizedBox(width: 6),
                // Abteilung in der Abfolge verschieben
                IconButton(
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  tooltip: 'Abteilung nach oben',
                  onPressed: onMoveUp,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_downward, size: 18),
                  tooltip: 'Abteilung nach unten',
                  onPressed: onMoveDown,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),

          // Maschinen-Blöcke (alle ausgeklappt untereinander)
          for (var i = 0; i < gruppe.length; i++) ...[
            if (i > 0) const Divider(height: 28, thickness: 0.5, indent: 8, endIndent: 8),
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
          const SizedBox(height: 14),

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

          // Plattenschema NUR bei den Maschinen Bratstraße/Dampftunnel —
          // sie haben ein festes Zonenraster. Alle anderen Maschinen
          // (Schockfroster, Heißluftofen, Füllmaschine, Verpackung …)
          // bekommen stattdessen das freie Notizfeld, weil ihre
          // Einstellungen zu individuell für starre Felder sind.
          //
          // Bewusst an der MASCHINE festgemacht, nicht an der Abteilung:
          // der Schockfroster steht in der Abteilung Bratstraße, braucht
          // aber ein Notizfeld statt eines Plattenrasters.
          if (istPlattenMaschine(maschineName)) ...[
            if (istDampftunnelMaschine(maschineName))
              _InlineHinweis(productId: s.productId),
            _PlattenSchemaBereich(
              step: s,
              maschineName: maschineName,
              onUpdated: widget.onUpdated,
            ),
            const SizedBox(height: 12),
          ] else ...[
            _MaschinenNotizFeld(step: s, onUpdated: widget.onUpdated),
            const SizedBox(height: 12),
          ],

          // Parameter (Standard + Custom, beide editierbar) — inklusive
          // Steckbrief-Feldern der zugeordneten Maschine.
          _ParameterListe(
            stepId: s.id,
            maschineId: s.maschineId,
            maschinenName: maschineName,
          ),
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
  const _PlattenSchemaBereich({
    required this.step,
    required this.maschineName,
    required this.onUpdated,
  });

  final ProductStep step;
  final String maschineName;
  final VoidCallback onUpdated;

  /// Jede Maschine zeigt NUR ihr eigenes Raster: die Bratstraße die
  /// 10+10 Platten, der Dampftunnel seine 12. Vorher erschienen beide
  /// Schieber bei beiden Maschinen — verwirrend und fehleranfällig.
  bool get _istDampftunnel =>
      maschineName.toLowerCase().contains('dampftunnel');

  /// Sucht einen Parameter NAME + GRUPPE — beide Gruppen enthalten Zeilen
  /// namens "Platte Unten N" (Bratstraße 1–10, Dampftunnel 1–12). Ohne die
  /// Gruppe würden die Werte des Dampftunnels mit denen der Bratstraße
  /// verwechselt.
  static ProductStepParameter? _find(
    List<ProductStepParameter> params,
    String name,
    String gruppe,
  ) {
    for (final p in params) {
      if (p.parameterName == name && p.parameterGruppe == gruppe) return p;
    }
    return null;
  }

  static String _zahlText(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  String _gruppeVon(BratschemaTyp typ) =>
      typ == BratschemaTyp.kombiofen ? kPlattenGruppeKombi : kPlattenGruppeBrat;

  PlattenTemperaturen _leseWerte(
    List<ProductStepParameter> params,
    BratschemaTyp typ,
  ) {
    final gruppe = _gruppeVon(typ);
    final leer = PlattenTemperaturen.leer(typ);
    double? wertVon(String name) {
      final w = _find(params, name, gruppe)?.wert;
      if (w == null || w.trim().isEmpty) return null;
      return double.tryParse(w.replaceAll(',', '.'));
    }

    return PlattenTemperaturen(
      oben: [
        for (var i = 0; i < leer.oben.length; i++) wertVon('Platte Oben ${i + 1}'),
      ],
      unten: [
        for (var i = 0; i < leer.unten.length; i++)
          wertVon('Platte Unten ${i + 1}'),
      ],
    );
  }

  Future<void> _upsert(
    WidgetRef ref,
    List<ProductStepParameter> params,
    String name,
    String gruppe,
    String? wert,
  ) async {
    final db = ref.read(databaseProvider);
    final vorhanden = _find(params, name, gruppe);
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
        // Nur das Raster der EIGENEN Maschine anzeigen.
        final typ = _istDampftunnel
            ? BratschemaTyp.kombiofen
            : BratschemaTyp.bratstrasse;
        final titel = _istDampftunnel
            ? 'PLATTEN DAMPFTUNNEL (12)'
            : 'PLATTEN BRATSTRASSE (10+10)';

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
              Text(
                titel,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 6),
              BratstrasseSchema(
                typ: typ,
                werte: _leseWerte(params, typ),
                onChanged: (neu) => _speichereWerte(ref, params, typ, neu),
              ),
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
    final dark = theme.brightness == Brightness.dark;
    final hatWert = wert.trim().isNotEmpty && wert.trim() != '–';
    final accent = dark ? const Color(0xFF66BB6A) : const Color(0xFF2E7D32);
    final bg = hatWert
        ? accent.withValues(alpha: dark ? 0.22 : 0.12)
        : theme.colorScheme.onSurface.withValues(alpha: 0.05);
    final border = hatWert
        ? accent.withValues(alpha: 0.5)
        : theme.colorScheme.onSurface.withValues(alpha: 0.10);
    final wertColor = hatWert
        ? (dark ? const Color(0xFF9CCC65) : accent)
        : theme.colorScheme.onSurface.withValues(alpha: 0.4);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
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
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.edit,
                  size: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              wert,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: wertColor,
              ),
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
  const _ParameterListe({
    required this.stepId,
    this.maschineId,
    this.maschinenName,
  });

  final String stepId;

  /// Maschine des Schritts — bestimmt die Steckbrief-Felder.
  final String? maschineId;
  final String? maschinenName;

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
    final db = ref.read(databaseProvider);
    final neuerWert = await _wertDialogMitPruefung(
      context,
      db: db,
      titel: param.parameterName,
      initial: param.wert ?? '',
      gruppe: param.parameterGruppe,
      parameterName: param.parameterName,
      maschinenName: maschinenName,
    );
    if (neuerWert == null) return;

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

  /// Bearbeitet ein Steckbrief-Feld: Wert-Dialog mit Grenzen-Prüfung,
  /// dann Upsert in die Parametergruppe MASCHINENEINSTELLUNGEN.
  Future<void> _steckbriefBearbeiten(
    BuildContext context,
    WidgetRef ref,
    MachineParameterDef def,
    ProductStepParameter? vorhanden,
  ) async {
    final db = ref.read(databaseProvider);
    final neuerWert = await _wertDialogMitPruefung(
      context,
      db: db,
      titel: def.parameterName,
      initial: vorhanden?.wert ?? '',
      gruppe: kMaschinenNotizGruppe,
      parameterName: def.parameterName,
      maschinenName: maschinenName,
      einheit: def.einheit,
    );
    if (neuerWert == null) return;

    final jetzt = DateTime.now();
    if (vorhanden != null) {
      await (db.update(db.productStepParameters)
            ..where((p) => p.id.equals(vorhanden.id)))
          .write(
        ProductStepParametersCompanion(
          wert: Value(neuerWert.isEmpty ? null : neuerWert),
          updatedAt: Value(jetzt),
        ),
      );
    } else {
      await db.into(db.productStepParameters).insert(
            ProductStepParametersCompanion(
              id: Value(const Uuid().v4()),
              stepId: Value(stepId),
              parameterGruppe: const Value(kMaschinenNotizGruppe),
              parameterName: Value(def.parameterName),
              wert: Value(neuerWert.isEmpty ? null : neuerWert),
              reihenfolge: Value(50 + def.sortierung),
              istCustom: const Value(false),
            ),
          );
    }

    ref.read(autoBackupTriggerProvider).fireDebounced(
          reason: 'Maschinen-Parameter geändert',
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

        // Steckbrief-Felder der Maschine (falls eine zugeordnet ist).
        final defsAsync = maschineId == null
            ? const AsyncValue<List<MachineParameterDef>>.data([])
            : ref.watch(_steckbriefDefsProvider(maschineId!));
        final defs = defsAsync.valueOrNull ?? const <MachineParameterDef>[];
        final defNamen =
            defs.map((d) => d.parameterName.toLowerCase()).toSet();

        // Standard-Parameter nach Gruppen aufteilen. Zeilen, die zu einem
        // Steckbrief-Feld gehören, erscheinen im Steckbrief-Block und
        // werden hier ausgefiltert (sonst doppelt sichtbar).
        final standardByGruppe = <String, List<ProductStepParameter>>{};
        for (final p in standardParams) {
          if (p.parameterGruppe == kMaschinenNotizGruppe &&
              defNamen.contains(p.parameterName.toLowerCase())) {
            continue;
          }
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

            // Steckbrief-Felder der zugeordneten Maschine
            if (defs.isNotEmpty) ...[
              _SteckbriefBlock(
                stepId: stepId,
                maschinenName: maschinenName,
                defs: defs,
                params: alleParams,
                onEdit: (def, vorhanden) =>
                    _steckbriefBearbeiten(context, ref, def, vorhanden),
              ),
              const SizedBox(height: 8),
            ],

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
/// Block für die Steckbrief-Felder der zugeordneten Maschine: zeigt alle
/// im Maschinen-Katalog definierten Parameter — mit Wert, wenn am Artikel
/// gepflegt, sonst als leere Zeile zum Ausfüllen.
class _SteckbriefBlock extends StatelessWidget {
  const _SteckbriefBlock({
    required this.stepId,
    required this.maschinenName,
    required this.defs,
    required this.params,
    required this.onEdit,
  });

  final String stepId;
  final String? maschinenName;
  final List<MachineParameterDef> defs;
  final List<ProductStepParameter> params;
  final void Function(MachineParameterDef, ProductStepParameter?) onEdit;

  ProductStepParameter? _wertZeile(MachineParameterDef def) {
    for (final p in params) {
      if (p.parameterGruppe == kMaschinenNotizGruppe &&
          p.parameterName.toLowerCase() == def.parameterName.toLowerCase()) {
        return p;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.precision_manufacturing,
                size: 14,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                (maschinenName ?? 'MASCHINE').toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final def in defs)
            Builder(
              builder: (context) {
                final zeile = _wertZeile(def);
                final wert = zeile?.wert?.trim();
                final hatWert = wert != null && wert.isNotEmpty;
                return InkWell(
                  onTap: () => onEdit(def, zeile),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 5,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            (def.einheit ?? '').isEmpty
                                ? def.parameterName
                                : '${def.parameterName} (${def.einheit})',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        hatWert
                            ? _ParamWert(wert: wert)
                            : Text(
                                'eintragen …',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontStyle: FontStyle.italic,
                                  color: theme.colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.7),
                                ),
                              ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

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
          if (parameter.isNotEmpty)
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
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 2,
              child: Text(
                param.parameterName,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 1,
              child: _ParamWert(wert: param.wert),
            ),
            Icon(
              Icons.edit,
              size: 15,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wert-Anzeige für Parameter: gefüllt = grüne Pille, leer = gedämpftes „—".
class _ParamWert extends StatelessWidget {
  const _ParamWert({required this.wert});

  final String? wert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final hat = wert != null && wert!.trim().isNotEmpty;
    if (!hat) {
      return Text(
        '—',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
        ),
      );
    }
    final accent = dark ? const Color(0xFF9CCC65) : const Color(0xFF2E7D32);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: dark ? 0.20 : 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          wert!,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: accent,
          ),
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              param.parameterName,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 1,
            child: _ParamWert(wert: param.wert),
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

// ---------------------------------------------------------------------------
// Prozess-Fließdiagramm
//
// Kompakte Darstellung der gesamten Prozesskette auf einen Blick:
// nummerierte Abteilungs-Stationen, verbunden durch eine Flusslinie,
// Maschinen als anklickbare Knoten (grün = Daten hinterlegt).
// Klick auf einen Knoten öffnet die volle Detailansicht des Schritts.
// ---------------------------------------------------------------------------

class _ProzessDiagramm extends StatelessWidget {
  const _ProzessDiagramm({
    required this.productId,
    required this.gruppen,
    required this.onMove,
    required this.onReorderSchritt,
    required this.onUpdated,
  });

  final String productId;
  final List<List<({ProductStep step, int nummer})>> gruppen;
  final void Function(int index, int richtung) onMove;
  final void Function(int gruppenIndex, int von, int nach) onReorderSchritt;
  final VoidCallback onUpdated;

  @override
  Widget build(BuildContext context) {
    if (gruppen.isEmpty) {
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        for (var g = 0; g < gruppen.length; g++)
          _DiagrammStation(
            productId: productId,
            gruppenIndex: g,
            gruppe: gruppen[g],
            position: g + 1,
            istLetzte: g == gruppen.length - 1,
            onMoveUp: g == 0 ? null : () => onMove(g, -1),
            onMoveDown:
                g == gruppen.length - 1 ? null : () => onMove(g, 1),
            onReorderSchritt: (von, nach) => onReorderSchritt(g, von, nach),
            onUpdated: onUpdated,
          ),
      ],
    );
  }
}

/// Eine Station im Fließdiagramm: Nummern-Kreis + Flusslinie links,
/// rechts die Abteilungs-Box mit den Maschinen-Knoten.
/// Knoten lassen sich per Drag & Drop innerhalb der Station umsortieren.
class _DiagrammStation extends StatelessWidget {
  const _DiagrammStation({
    required this.productId,
    required this.gruppenIndex,
    required this.gruppe,
    required this.position,
    required this.istLetzte,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onReorderSchritt,
    required this.onUpdated,
  });

  final String productId;
  final int gruppenIndex;
  final List<({ProductStep step, int nummer})> gruppe;
  final int position;
  final bool istLetzte;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final void Function(int von, int nach) onReorderSchritt;
  final VoidCallback onUpdated;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final abt = Abteilung.fromDbValue(gruppe.first.step.abteilung);
    final farbe = abt.farbe;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Fluss-Spalte: Nummern-Kreis mit Ring + Verbindungslinie + Pfeil
          SizedBox(
            width: 46,
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: farbe,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: dark ? 0.25 : 0.6),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: farbe.withValues(alpha: 0.45),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$position',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (!istLetzte) ...[
                  Expanded(
                    child: Container(
                      width: 2.5,
                      decoration: BoxDecoration(
                        color: farbe.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 22,
                    color: farbe.withValues(alpha: 0.8),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),

          // Stations-Box mit dezentem Farbverlauf
          Expanded(
            child: Container(
              margin: EdgeInsets.only(bottom: istLetzte ? 0 : 16),
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    farbe.withValues(alpha: dark ? 0.14 : 0.09),
                    farbe.withValues(alpha: dark ? 0.04 : 0.02),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: farbe.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          abt.anzeigeName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: farbe,
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
                      const SizedBox(width: 2),
                      IconButton(
                        icon: const Icon(Icons.arrow_upward, size: 17),
                        tooltip: 'Abteilung nach oben',
                        onPressed: onMoveUp,
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        icon: const Icon(Icons.arrow_downward, size: 17),
                        tooltip: 'Abteilung nach unten',
                        onPressed: onMoveDown,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (var i = 0; i < gruppe.length; i++)
                        _DraggableKnoten(
                          gruppenIndex: gruppenIndex,
                          index: i,
                          onReorder: onReorderSchritt,
                          knoten: _ProzessKnoten(
                            productId: productId,
                            step: gruppe[i].step,
                            nummer: gruppe[i].nummer,
                            farbe: farbe,
                            onUpdated: onUpdated,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Macht einen Prozess-Knoten zieh- und ablegbar (nur innerhalb der
/// eigenen Station). Beim Drop landet der gezogene Schritt an der
/// Position des Ziels — nach rechts gezogen dahinter, nach links davor.
class _DraggableKnoten extends StatelessWidget {
  const _DraggableKnoten({
    required this.gruppenIndex,
    required this.index,
    required this.onReorder,
    required this.knoten,
  });

  final int gruppenIndex;
  final int index;
  final void Function(int von, int nach) onReorder;
  final Widget knoten;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DragTarget<({int gruppe, int index})>(
      onWillAcceptWithDetails: (d) =>
          d.data.gruppe == gruppenIndex && d.data.index != index,
      onAcceptWithDetails: (d) => onReorder(d.data.index, index),
      builder: (context, candidate, rejected) {
        final ziel = candidate.isNotEmpty;
        return Draggable<({int gruppe, int index})>(
          data: (gruppe: gruppenIndex, index: index),
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(opacity: 0.9, child: knoten),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: knoten),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: ziel
                    ? theme.colorScheme.primary
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: knoten,
          ),
        );
      },
    );
  }
}

/// Ein Maschinen-Knoten im Fließdiagramm — tippen öffnet die Details.
class _ProzessKnoten extends ConsumerWidget {
  const _ProzessKnoten({
    required this.productId,
    required this.step,
    required this.nummer,
    required this.farbe,
    required this.onUpdated,
  });

  final String productId;
  final ProductStep step;
  final int nummer;
  final Color farbe;
  final VoidCallback onUpdated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    // Maschinenname auflösen: Maschine > Legacy-Text > Prozessschritt
    String name;
    final mid = step.maschineId;
    if (mid != null) {
      name = ref.watch(machineProvider(mid)).valueOrNull?.name ??
          'Schritt $nummer';
    } else if (step.maschine != null && step.maschine!.trim().isNotEmpty) {
      name = step.maschine!;
    } else if (step.prozessschritt != null &&
        step.prozessschritt!.trim().isNotEmpty) {
      name = step.prozessschritt!;
    } else {
      name = 'Schritt $nummer';
    }

    final hatDaten = step.basisMitarbeiter > 0 ||
        step.basisMengeKg > 0 ||
        step.basisDauerMinuten > 0 ||
        (step.fixZeitMinuten ?? 0) > 0;
    final accent = dark ? const Color(0xFF66BB6A) : const Color(0xFF2E7D32);

    return InkWell(
      onTap: () => _zeigeSchrittDetail(
        context,
        productId: productId,
        stepId: step.id,
        fallback: step,
        nummer: nummer,
        onUpdated: onUpdated,
      ),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: hatDaten
              ? accent.withValues(alpha: dark ? 0.20 : 0.10)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hatDaten
                ? accent.withValues(alpha: 0.55)
                : theme.dividerColor,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.25 : 0.06),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.drag_indicator,
                  size: 14,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                ),
                const SizedBox(width: 3),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: farbe.withValues(alpha: dark ? 0.30 : 0.15),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    '$nummer',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: dark ? Colors.white : farbe,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (hatDaten) ...[
                  const SizedBox(width: 5),
                  Icon(Icons.check_circle, size: 14, color: accent),
                ],
              ],
            ),
            if (step.prozessschritt != null &&
                step.prozessschritt!.trim().isNotEmpty &&
                step.prozessschritt != name)
              Padding(
                padding: const EdgeInsets.only(left: 17, top: 1),
                child: Text(
                  step.prozessschritt!,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Öffnet die volle Detailansicht eines Prozessschritts als Bottom-Sheet.
void _zeigeSchrittDetail(
  BuildContext context, {
  required String productId,
  required String stepId,
  required ProductStep fallback,
  required int nummer,
  required VoidCallback onUpdated,
}) {
  final container = ProviderScope.containerOf(context);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 820),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => UncontrolledProviderScope(
      container: container,
      child: _SchrittDetailSheet(
        productId: productId,
        stepId: stepId,
        fallback: fallback,
        nummer: nummer,
        onUpdated: onUpdated,
      ),
    ),
  );
}

/// Inhalt des Schritt-Detail-Sheets — zeigt den bestehenden Maschinen-Block
/// (Kennwerte, Plattenschema, Parameter) und bleibt durch das Watching des
/// Steps-Providers auch nach Bearbeitungen aktuell.
class _SchrittDetailSheet extends ConsumerWidget {
  const _SchrittDetailSheet({
    required this.productId,
    required this.stepId,
    required this.fallback,
    required this.nummer,
    required this.onUpdated,
  });

  final String productId;
  final String stepId;
  final ProductStep fallback;
  final int nummer;
  final VoidCallback onUpdated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stepsAsync = ref.watch(productStepsProvider(productId));
    final steps = stepsAsync.valueOrNull;
    ProductStep aktuell = fallback;
    if (steps != null) {
      for (final s in steps) {
        if (s.id == stepId) {
          aktuell = s;
          break;
        }
      }
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: _MaschinenBlock(
          step: aktuell,
          stepNumber: nummer,
          onUpdated: onUpdated,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Besonderheiten-Karte (Infos-Tab)
//
// Zeigt den Freitext aus dem Excel-Block „Sonstige Informationen".
// Wird beim Import gelesen und beim Export zurückgeschrieben.
// ---------------------------------------------------------------------------

class _BesonderheitenKarte extends StatelessWidget {
  const _BesonderheitenKarte({required this.text, required this.onEdit});

  final String text;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final leer = text.isEmpty;
    final akzent =
        dark ? const Color(0xFFFFB74D) : const Color(0xFFEF6C00);

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: leer
              ? theme.dividerColor
              : akzent.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                leer ? Icons.info_outline : Icons.priority_high_rounded,
                size: 20,
                color: leer
                    ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
                    : akzent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Besonderheiten',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: leer
                            ? theme.colorScheme.onSurface
                                .withValues(alpha: 0.6)
                            : akzent,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      leer
                          ? 'Keine Besonderheiten hinterlegt — tippen zum '
                              'Eintragen.'
                          : text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontStyle: leer ? FontStyle.italic : null,
                        color: leer
                            ? theme.colorScheme.onSurface
                                .withValues(alpha: 0.5)
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.edit,
                size: 16,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Zeigt die Besonderheiten des Artikels (Freitext aus "Sonstige
/// Informationen") direkt im Prozess-Tab - dort, wo damit gearbeitet wird.
/// Ist nichts hinterlegt, erscheint nichts.
class _BesonderheitBanner extends ConsumerWidget {
  const _BesonderheitBanner({required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final text =
        ref.watch(productProvider(productId)).valueOrNull?.beschreibung;
    if (text == null || text.trim().isEmpty) return const SizedBox.shrink();

    final akzent = theme.brightness == Brightness.dark
        ? const Color(0xFFFFB74D)
        : const Color(0xFFE65100);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: akzent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: akzent.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.push_pin_outlined, size: 18, color: akzent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Besonderheit',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: akzent,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  text.trim(),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Freies Notizfeld „Maschineneinstellungen" für einen Schritt.
///
/// Speichert den Text als Parameterzeile [kMaschinenNotizParam] in der
/// Gruppe [kMaschinenNotizGruppe] — dadurch fließt er ohne Sonderbehandlung
/// durch Import und Export (eigener Block in der Excel).
class _MaschinenNotizFeld extends ConsumerWidget {
  const _MaschinenNotizFeld({required this.step, required this.onUpdated});

  final ProductStep step;
  final VoidCallback onUpdated;

  Future<void> _bearbeiten(
    BuildContext context,
    WidgetRef ref,
    String? aktuell,
  ) async {
    final ctrl = TextEditingController(text: aktuell ?? '');
    final neu = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Maschineneinstellungen'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 4,
          maxLines: 12,
          decoration: const InputDecoration(
            hintText: 'Individuelle Einstellungen dieser Maschine …\n'
                'z.B. Programm, Geschwindigkeit, Temperatur, Sonderhinweise',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (neu == null) return;

    final db = ref.read(databaseProvider);
    final paramsAsync = ref.read(stepParametersProvider(step.id));
    final vorhanden = paramsAsync.valueOrNull
        ?.where((p) => p.parameterName == kMaschinenNotizParam)
        .firstOrNull;
    final wert = neu.trim().isEmpty ? null : neu.trim();

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
              parameterGruppe: const Value(kMaschinenNotizGruppe),
              parameterName: const Value(kMaschinenNotizParam),
              wert: Value(wert),
              reihenfolge: const Value(50),
              istCustom: const Value(false),
            ),
          );
    }
    ref.read(autoBackupTriggerProvider).fireDebounced(
          reason: 'Maschineneinstellungen geändert',
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
        final notiz = params
            .where((p) => p.parameterName == kMaschinenNotizParam)
            .firstOrNull
            ?.wert;
        final hatText = notiz != null && notiz.trim().isNotEmpty;

        return InkWell(
          onTap: () => _bearbeiten(context, ref, notiz),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.settings_outlined,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Maschineneinstellungen',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      hatText ? Icons.edit_outlined : Icons.add,
                      size: 15,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  hatText ? notiz.trim() : 'Tippen, um Einstellungen zu erfassen …',
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.35,
                    color: hatText
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurface.withValues(alpha: 0.45),
                    fontStyle: hatText ? FontStyle.normal : FontStyle.italic,
                  ),
                ),
              ],
            ),
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
      error: (e, _) => const SizedBox.shrink(),
    );
  }
}


/// Hinweis am Dampftunnel-Schritt.
///
/// Läuft der Artikel über die Bratstraße, passiert er den Dampftunnel
/// automatisch inline: Menge und Produktionszeit sind dieselben, und es
/// wird dort kein eigenes Personal gebunden. Fehlt die Bratstraße
/// (das Produkt startet erst am Dampftunnel), gilt das Gegenteil — dann
/// sind Menge, Zeit und Personal hier eigenständig zu pflegen.
class _InlineHinweis extends ConsumerWidget {
  const _InlineHinweis({required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final steps = ref.watch(productStepsProvider(productId)).valueOrNull;
    if (steps == null) return const SizedBox.shrink();

    // Hat der Artikel einen Bratstraßen-Schritt?
    var hatBratstrasse = false;
    for (final st in steps) {
      final m = st.maschine ?? '';
      if (_istBratstrasseMaschine(m)) {
        hatBratstrasse = true;
        break;
      }
    }

    final farbe = hatBratstrasse
        ? theme.colorScheme.primary
        : (theme.brightness == Brightness.dark
            ? const Color(0xFFFFB74D)
            : const Color(0xFFE65100));
    final text = hatBratstrasse
        ? 'Läuft inline hinter der Bratstraße: Menge und Produktionszeit '
            'entsprechen der Bratstraße, eigenes Personal ist hier nicht '
            'nötig.'
        : 'Produktion startet am Dampftunnel (keine Bratstraße im Prozess) — '
            'Menge, Zeit und Personal hier eigenständig pflegen.';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: farbe.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: farbe.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            hatBratstrasse ? Icons.link : Icons.play_circle_outline,
            size: 16,
            color: farbe,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Leistungsdaten-Dialog: Referenzleistung je Abteilung erfassen
// ---------------------------------------------------------------------------

/// Geführte Maske: fragt für jede Abteilung des Prozesses die
/// Referenzleistung ab — „Menge X kg in Zeit Y mit Z Personen". Daraus
/// zeigt sie live die Kennzahl kg/h und schreibt die Werte beim Speichern
/// auf den ersten Schritt jeder Abteilungsgruppe. Mit diesen Basiswerten
/// skaliert die App die Dauer jeder Planmenge
/// (Dauer = Fixzeit + Zeit × Planmenge ÷ Referenzmenge).
class _LeistungsdatenDialog extends ConsumerStatefulWidget {
  const _LeistungsdatenDialog({required this.eintraege});

  final List<({Abteilung abteilung, ProductStep erster})> eintraege;

  @override
  ConsumerState<_LeistungsdatenDialog> createState() =>
      _LeistungsdatenDialogState();
}

class _LeistungsdatenDialogState
    extends ConsumerState<_LeistungsdatenDialog> {
  late final List<TextEditingController> _menge;
  late final List<TextEditingController> _zeit;
  late final List<TextEditingController> _personen;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    String zeitText(double min) {
      if (min <= 0) return '';
      final h = min ~/ 60;
      final m = (min % 60).round();
      return '$h:${m.toString().padLeft(2, '0')}';
    }

    _menge = [
      for (final e in widget.eintraege)
        TextEditingController(
          text: e.erster.basisMengeKg > 0
              ? e.erster.basisMengeKg.round().toString()
              : '',
        ),
    ];
    _zeit = [
      for (final e in widget.eintraege)
        TextEditingController(text: zeitText(e.erster.basisDauerMinuten)),
    ];
    _personen = [
      for (final e in widget.eintraege)
        TextEditingController(
          text: e.erster.basisMitarbeiter > 0
              ? e.erster.basisMitarbeiter.toString()
              : '',
        ),
    ];
  }

  @override
  void dispose() {
    for (final c in [..._menge, ..._zeit, ..._personen]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Parst „h:mm" oder eine reine Minutenzahl zu Minuten.
  static double? _minuten(String eingabe) {
    final t = eingabe.trim();
    if (t.isEmpty) return null;
    if (t.contains(':')) {
      final teile = t.split(':');
      if (teile.length != 2) return null;
      final h = int.tryParse(teile[0]);
      final m = int.tryParse(teile[1]);
      if (h == null || m == null || m < 0 || m > 59) return null;
      return (h * 60 + m).toDouble();
    }
    return double.tryParse(t.replaceAll(',', '.'));
  }

  String _kgProStunde(int i) {
    final kg = double.tryParse(_menge[i].text.replaceAll(',', '.'));
    final min = _minuten(_zeit[i].text);
    if (kg == null || kg <= 0 || min == null || min <= 0) return '—';
    final kgh = kg / (min / 60);
    return '${kgh.toStringAsFixed(0)} kg/h';
  }

  Future<void> _speichern() async {
    setState(() => _busy = true);
    final db = ref.read(databaseProvider);
    final jetzt = DateTime.now();
    var geschrieben = 0;

    for (var i = 0; i < widget.eintraege.length; i++) {
      final kg = double.tryParse(_menge[i].text.replaceAll(',', '.'));
      final min = _minuten(_zeit[i].text);
      final pers = int.tryParse(_personen[i].text.trim());
      // Nur vollständig ausgefüllte Abteilungen schreiben — leere Zeilen
      // lassen den bestehenden Stand unangetastet.
      if (kg == null || kg <= 0 || min == null || min <= 0) continue;

      await (db.update(db.productSteps)
            ..where((st) => st.id.equals(widget.eintraege[i].erster.id)))
          .write(
        ProductStepsCompanion(
          mengeKg: Value(kg),
          basisMengeKg: Value(kg),
          basisDauerMinuten: Value(min),
          basisMitarbeiter:
              pers != null && pers > 0 ? Value(pers) : const Value.absent(),
          updatedAt: Value(jetzt),
        ),
      );
      geschrieben++;
    }

    if (geschrieben > 0) {
      ref.read(autoBackupTriggerProvider).fireDebounced(
            reason: 'Leistungsdaten erfasst',
          );
    }
    if (mounted) Navigator.of(context).pop(geschrieben > 0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Leistungsdaten je Abteilung'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Referenz: Welche Menge schafft die Abteilung bei diesem '
                'Artikel in welcher Zeit mit wie vielen Personen? Daraus '
                'skaliert die App die Dauer jeder Planmenge.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              for (var i = 0; i < widget.eintraege.length; i++) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.eintraege[i].abteilung.anzeigeName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      _kgProStunde(i),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _menge[i],
                        decoration: const InputDecoration(
                          labelText: 'Menge',
                          suffixText: 'kg',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _zeit[i],
                        decoration: const InputDecoration(
                          labelText: 'Zeit',
                          hintText: 'h:mm',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 92,
                      child: TextField(
                        controller: _personen[i],
                        decoration: const InputDecoration(
                          labelText: 'Personen',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _busy ? null : _speichern,
          child: Text(_busy ? 'Speichern …' : 'Speichern'),
        ),
      ],
    );
  }
}
