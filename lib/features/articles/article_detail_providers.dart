import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/parameter_namen.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';
import '../../core/utils/zeit.dart';

// Provider, Konstanten und gemeinsame Helfer der Artikel-Detailansicht.
//
// Bewusst eine ECHTE Datei, kein `part`: Diese Symbole werden auch
// außerhalb des Screens gebraucht — `article_print_service.dart` und
// `data_management_screen.dart` greifen darauf zu. Ein `part` würde nur
// so tun, als wäre hier eine Grenze; ein eigener Import ist die ehrliche
// Variante. Deshalb sind neun vormals dateiprivate Helfer hier öffentlich
// geworden.

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

bool istBratstrasseMaschine(String maschineName) =>
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
final steckbriefDefsProvider =
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
Future<String?> wertDialogMitPruefung(
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

String _pad(int n) => n.toString().padLeft(2, '0');

String fmtDatum(DateTime d) => '${_pad(d.day)}.${_pad(d.month)}.${d.year}';

String fmtKg(double? v) {
  if (v == null) return '—';
  return v == v.roundToDouble()
      ? v.toInt().toString()
      : v.toStringAsFixed(1);
}

String fmtProzent(double anteil) => '${(anteil * 100).toStringAsFixed(1)} %';

String fmtDauer(double? minuten) => Zeit.lang(minuten);

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
Future<void> bereinigeDoppelteParameter(
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



