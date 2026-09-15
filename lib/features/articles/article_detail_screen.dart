import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/utils/zeit.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';
import 'article_info_editor_dialog.dart';
import 'article_print_service.dart';
import 'bratstrasse_schema.dart';
import 'custom_parameter_editor_dialog.dart';
import 'production_entry_dialog.dart';
import 'step_editor_dialog.dart';

// Die Datei war mit 4.750 Zeilen zu groß, um sich darin zurechtzufinden.
// Sie ist deshalb in Teildateien zerlegt.
//
// Bewusst `part` statt eigenständiger Bibliotheken: Nahezu alle Klassen
// hier sind dateiprivat (führender Unterstrich) und sehen einander nur
// innerhalb derselben Bibliothek. Mit `part` bleibt das so — es ist eine
// reine Textverschiebung, ohne Umbenennungen und ohne neue Import-Ketten.
// Alle Imports stehen weiterhin ausschließlich in dieser Datei.
part 'article_besonderheiten.dart';
part 'article_maschinen_ansicht.dart';
part 'article_parameter_liste.dart';
part 'article_production_tab.dart';
part 'article_produktionsmittel_katalog.dart';
part 'article_prozess_diagramm.dart';

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

String _fmtDauer(double? minuten) => Zeit.lang(minuten);

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Räumt Parameter auf, die für denselben Schritt doppelt existieren —
/// einmal in der Gruppe der Anlage (aus der Excel importiert) und einmal in
/// „MASCHINENEINSTELLUNGEN" (von der App angelegt, bevor der Abgleich
/// namensbasiert wurde).
///
/// Behalten wird die Zeile in der Anlagen-Gruppe: Sie steht im Excel-Export
/// an der richtigen Stelle. Ihr Wert wird — falls sie leer ist oder die
/// andere Zeile neuer gepflegt wurde — aus der Dublette übernommen; die
/// überzählige Zeile wird anschließend soft-deleted.
Future<void> _bereinigeDoppelteParameter(
  BuildContext context,
  WidgetRef ref,
  String productId,
) async {
  final db = ref.read(databaseProvider);

  final schritte = await (db.select(db.productSteps)
        ..where((s) => s.productId.equals(productId))
        ..where((s) => s.deletedAt.isNull()))
      .get();
  if (schritte.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dieser Artikel hat keine Schritte.')),
      );
    }
    return;
  }

  // Je Schritt die Parameter nach Namen bündeln.
  final aufgaben = <({
    ProductStepParameter behalten,
    List<ProductStepParameter> entfernen,
    String? neuerWert,
  })>[];

  for (final s in schritte) {
    final params = await (db.select(db.productStepParameters)
          ..where((p) => p.stepId.equals(s.id))
          ..where((p) => p.deletedAt.isNull()))
        .get();

    final nachName = <String, List<ProductStepParameter>>{};
    for (final p in params) {
      if (p.istCustom) continue;
      nachName
          .putIfAbsent(p.parameterName.trim().toLowerCase(), () => [])
          .add(p);
    }

    for (final gruppe in nachName.values) {
      if (gruppe.length < 2) continue;

      // Behalten: bevorzugt die Zeile in der Anlagen-Gruppe.
      final behalten = gruppe.firstWhere(
        (p) => p.parameterGruppe != kMaschinenNotizGruppe,
        orElse: () => gruppe.first,
      );

      // Wert: den zuletzt gepflegten, nicht leeren nehmen.
      ProductStepParameter? bester;
      for (final p in gruppe) {
        if ((p.wert ?? '').trim().isEmpty) continue;
        if (bester == null || p.updatedAt.isAfter(bester.updatedAt)) {
          bester = p;
        }
      }

      final rest = gruppe.where((p) => p.id != behalten.id).toList();
      aufgaben.add(
        (
          behalten: behalten,
          entfernen: rest,
          neuerWert: bester?.wert,
        ),
      );
    }
  }

  if (!context.mounted) return;

  if (aufgaben.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Keine doppelten Parameter gefunden — alles sauber.'),
      ),
    );
    return;
  }

  final anzahlZeilen =
      aufgaben.fold<int>(0, (s, a) => s + a.entfernen.length);
  final beispiele = aufgaben
      .take(5)
      .map((a) => '• ${a.behalten.parameterName}')
      .join('\n');

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('$anzahlZeilen doppelte Zeile(n) bereinigen?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${aufgaben.length} Parameter kommen doppelt vor. Behalten wird '
            'jeweils die Zeile in der Anlagen-Gruppe (sie steht im '
            'Excel-Export an der richtigen Stelle), mit dem zuletzt '
            'gepflegten Wert.',
          ),
          const SizedBox(height: 12),
          Text(
            beispiele +
                (aufgaben.length > 5
                    ? '\n• … und ${aufgaben.length - 5} weitere'
                    : ''),
            style: const TextStyle(fontSize: 12.5),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Bereinigen'),
        ),
      ],
    ),
  );
  if (ok != true) return;

  final jetzt = DateTime.now();
  await db.transaction(() async {
    for (final a in aufgaben) {
      if ((a.neuerWert ?? '').trim() != (a.behalten.wert ?? '').trim()) {
        await (db.update(db.productStepParameters)
              ..where((p) => p.id.equals(a.behalten.id)))
            .write(
          ProductStepParametersCompanion(
            wert: Value(a.neuerWert),
            updatedAt: Value(jetzt),
          ),
        );
      }
      for (final weg in a.entfernen) {
        await (db.update(db.productStepParameters)
              ..where((p) => p.id.equals(weg.id)))
            .write(
          ProductStepParametersCompanion(
            deletedAt: Value(jetzt),
            updatedAt: Value(jetzt),
          ),
        );
      }
    }
  });

  ref.read(autoBackupTriggerProvider).fireDebounced(
        reason: 'Doppelte Parameter bereinigt',
      );
  for (final s in schritte) {
    ref.invalidate(stepParametersProvider(s.id));
  }
  ref.invalidate(productStepsProvider(productId));

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('$anzahlZeilen doppelte Zeile(n) entfernt.'),
    ),
  );
}

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
              onPressed: () => _bereinigeDoppelteParameter(
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
