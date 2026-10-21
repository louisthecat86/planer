import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';
import '../../core/theme/app_stil.dart';
import '../../core/ui/bausteine.dart';
import '../../core/utils/fehler_text.dart';
import '../../core/utils/format.dart';
import '../../core/utils/sheet_utils.dart';
import '../../core/utils/zeit.dart';
import 'maschinen_seed.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Alle Maschinen, gruppiert nach Abteilung (in Abteilungs-Reihenfolge).
final maschinenKatalogProvider =
    FutureProvider<Map<Abteilung, List<Machine>>>((ref) async {
  final db = ref.watch(databaseProvider);
  final rows = await (db.select(db.machines)
        ..where((m) => m.deletedAt.isNull())
        ..orderBy([(m) => OrderingTerm.asc(m.name)]))
      .get();
  final map = <Abteilung, List<Machine>>{};
  for (final a in Abteilung.values) {
    final liste = rows.where((m) => m.abteilung == a.dbValue).toList();
    if (liste.isNotEmpty) map[a] = liste;
  }
  return map;
});

/// Steckbrief-Parameter einer Maschine, sortiert.
final maschinenParameterDefsProvider =
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

// ---------------------------------------------------------------------------
// Katalog-Screen
// ---------------------------------------------------------------------------

/// Maschinen-Katalog: Anlagen anlegen, bearbeiten und je Maschine den
/// Steckbrief (welche Parameter sie hat) pflegen. Die Werte selbst werden
/// weiterhin pro Artikel erfasst — hier entsteht nur die Maske.
class MaschinenKatalogScreen extends ConsumerWidget {
  const MaschinenKatalogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final katalog = ref.watch(maschinenKatalogProvider);
    // Schmale Fenster: der Knopf der Kopfleiste nur als Symbol.
    final schmal = MediaQuery.sizeOf(context).width < 720;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Maschinen-Katalog'),
        actions: [
          // Die Grenzwerte gehören sachlich zum Katalog — sie beschreiben,
          // welche Werte an einer Anlage plausibel sind. Deshalb hier statt
          // als eigener Punkt in den Einstellungen.
          IconButton(
            icon: const Icon(Icons.rule_rounded),
            tooltip: 'Grenzwerte je Anlage',
            onPressed: () => context.pushNamed('grenzen'),
          ),
          IconButton(
            icon: const Icon(Icons.playlist_add),
            tooltip: 'Standard-Maschinen ergänzen',
            onPressed: () => _seedDialog(context, ref),
          ),
          const SizedBox(width: 4),
          // Die Hauptaktion oben rechts wie auf den übrigen Seiten — vorher
          // ein schwebender Knopf, der unten die letzte Maschine verdeckte.
          if (schmal)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Neue Maschine',
              onPressed: () => _oeffneEditor(context, ref, null),
            )
          else
            FilledButton.icon(
              onPressed: () => _oeffneEditor(context, ref, null),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Neue Maschine'),
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: katalog.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(
          padding: const EdgeInsets.all(14),
          children: [
            HinweisBox(
              'Fehler: ${fehlerText(e)}',
              art: StatusArt.fehler,
              auswaehlbar: true,
            ),
          ],
        ),
        data: (map) {
          if (map.isEmpty) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: LeerHinweis(
                  'Noch keine Maschinen angelegt. Lege mit „Neue Maschine" '
                  'oben rechts die erste Anlage an, ergänze den '
                  'Standard-Maschinenpark oder importiere den '
                  'Anlagen-Katalog aus der Excel.',
                  icon: Icons.precision_manufacturing_outlined,
                  aktion: OutlinedButton.icon(
                    onPressed: () => _seedDialog(context, ref),
                    icon: const Icon(Icons.playlist_add, size: 18),
                    label: const Text('Standard-Maschinen ergänzen …'),
                  ),
                ),
              ),
            );
          }
          final anzahl = map.values.fold<int>(0, (s, l) => s + l.length);
          final letzte = map.values.last.last;
          // Alle Anlagen in einer Tabelle, je Abteilung eine Zwischenzeile
          // — vorher eine Karte je Maschine unter blauen Überschriften.
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
            children: [
              Bereich(
                titel: 'Maschinen',
                untertitel: anzahl == 1 ? '1 Maschine' : '$anzahl Maschinen',
                innenAbstand: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final entry in map.entries) ...[
                      _AbteilungsZwischenzeile(
                        abteilung: entry.key,
                        anzahl: entry.value.length,
                      ),
                      for (final m in entry.value)
                        _MaschinenZeile(
                          maschine: m,
                          letzte: identical(m, letzte),
                          onTap: () => _oeffneEditor(context, ref, m),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Fragt nach und ergänzt dann den Standard-Maschinenpark: legt fehlende
  /// Maschinen und deren Steckbrief-Parameter an. Bereits vorhandene
  /// Maschinen (per Name) bleiben unberührt.
  Future<void> _seedDialog(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Standard-Maschinen ergänzen'),
        content: Text(
          'Legt die ${kSeedMaschinen.length} Maschinen des Standard-'
          'Maschinenparks mit ihren Parametern an. Bereits vorhandene '
          'Maschinen werden nicht verändert und nicht doppelt angelegt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Ergänzen'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final db = ref.read(databaseProvider);
    // Soft-gelöschte bewusst mitprüfen: Die Unique-Bedingung auf dem Namen
    // gilt auch für sie, ein erneutes Anlegen liefe sonst auf einen Fehler.
    final vorhandene = await db.select(db.machines).get();
    final vorhandeneNamen =
        vorhandene.map((m) => m.name.toLowerCase()).toSet();

    // Erst sammeln, dann in EINER Transaktion schreiben.
    //
    // Vorher entstanden Anlage und Steckbrief-Parameter nacheinander direkt
    // in der Datenbank. Brach das dazwischen ab, stand eine Maschine ohne
    // ihre Parameterfelder da — in der Liste unauffällig, aber unbrauchbar.
    // Und weil der Abgleich über den Namen läuft, hätte ein zweiter Klick
    // auf „Ergänzen" sie übersprungen: Der Fehler wäre dauerhaft geblieben.
    final neueAnlagen = <MachinesCompanion>[];
    final neueDefs = <MachineParameterDefsCompanion>[];

    for (final seed in kSeedMaschinen) {
      if (vorhandeneNamen.contains(seed.name.toLowerCase())) continue;
      final maschineId = const Uuid().v4();
      neueAnlagen.add(
        MachinesCompanion.insert(
          id: maschineId,
          name: seed.name,
          abteilung: seed.abteilung,
          kapazitaetMinutenProTag: const Value(600),
        ),
      );
      // Sofort vormerken, falls derselbe Name im Seed doppelt vorkommt.
      vorhandeneNamen.add(seed.name.toLowerCase());

      for (var i = 0; i < seed.params.length; i++) {
        final p = seed.params[i];
        neueDefs.add(
          MachineParameterDefsCompanion.insert(
            id: const Uuid().v4(),
            maschineId: maschineId,
            parameterName: p.name,
            einheit: Value(p.einheit),
            sortierung: Value(i),
          ),
        );
      }
    }

    final neueMaschinen = neueAnlagen.length;
    final neueParams = neueDefs.length;

    if (neueMaschinen > 0) {
      try {
        await db.transaction(() async {
          // Anlagen zuerst: Die Steckbriefe verweisen per Fremdschlüssel
          // auf sie.
          await db.batch((b) => b.insertAll(db.machines, neueAnlagen));
          if (neueDefs.isNotEmpty) {
            await db.batch(
              (b) => b.insertAll(db.machineParameterDefs, neueDefs),
            );
          }
        });
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 8),
            content: Text(
              'Ergänzen fehlgeschlagen — es wurde nichts angelegt. '
              'Du kannst es erneut versuchen. (${fehlerText(e)})',
            ),
          ),
        );
        return;
      }

      ref
          .read(autoBackupTriggerProvider)
          .fireDebounced(reason: 'Standard-Maschinen ergänzt');
      ref.invalidate(maschinenKatalogProvider);
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          neueMaschinen == 0
              ? 'Alle Standard-Maschinen sind bereits vorhanden.'
              : '$neueMaschinen Maschinen und $neueParams Parameter ergänzt.',
        ),
      ),
    );
  }

  Future<void> _oeffneEditor(
    BuildContext context,
    WidgetRef ref,
    Machine? maschine,
  ) async {
    // Ohne Anfasser: Das Fenster hat einen eigenen Kopf mit Titel und
    // Kreuz wie jedes Fenster der App.
    final geaendert = await showSheetOhneAnimation<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => _MaschineEditorSheet(maschine: maschine),
    );
    if (geaendert == true) {
      ref.invalidate(maschinenKatalogProvider);
    }
  }
}

/// Zwischenzeile einer Abteilung in der Maschinentabelle: Kürzel, Name und
/// Anzahl auf der Fläche der Leisten.
class _AbteilungsZwischenzeile extends StatelessWidget {
  const _AbteilungsZwischenzeile({
    required this.abteilung,
    required this.anzahl,
  });

  final Abteilung abteilung;
  final int anzahl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
      decoration: BoxDecoration(
        color: AppFarben.von(context).leiste,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
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
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            anzahl == 1 ? '1 Maschine' : '$anzahl Maschinen',
            style: TextStyle(fontSize: 11.5, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Eine Maschine als Tabellenzeile: Name, Hinweis zur Eignung und rechts
/// die eigene Planungsspur als Marke. Antippen öffnet den Editor.
class _MaschinenZeile extends StatelessWidget {
  const _MaschinenZeile({
    required this.maschine,
    required this.letzte,
    required this.onTap,
  });

  final Machine maschine;

  /// Letzte Zeile der Tabelle: ohne Linie darunter, dort schließt der Rand.
  final bool letzte;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final m = maschine;
    final eignung = (m.eignungHinweis ?? '').trim();

    // Material statt Farbe am Container: Die Hover- und Tipp-Welle des
    // InkWell malt auf das nächste Material.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
          decoration: BoxDecoration(
            border: letzte
                ? null
                : Border(bottom: BorderSide(color: colors.outlineVariant)),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Text(
                  m.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Text(
                  eignung,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              if (m.istPlanungsressource) ...[
                const SizedBox(width: 8),
                StatusMarke(
                  'Planungsspur · '
                  '${Zeit.kurz(m.kapazitaetMinutenProTag.toDouble())}/Tag',
                  art: StatusArt.info,
                  hinweis: 'Erscheint mit eigener Kapazität im Wochenplan',
                ),
              ],
              const SizedBox(width: 4),
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

// ---------------------------------------------------------------------------
// Editor-Sheet: Stammfelder + Steckbrief-Parameter
// ---------------------------------------------------------------------------

class _MaschineEditorSheet extends ConsumerStatefulWidget {
  const _MaschineEditorSheet({this.maschine});

  final Machine? maschine;

  @override
  ConsumerState<_MaschineEditorSheet> createState() =>
      _MaschineEditorSheetState();
}

class _MaschineEditorSheetState extends ConsumerState<_MaschineEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _kapazitaetStunden;
  late final TextEditingController _eignung;
  String _abteilung = Abteilung.values.first.dbValue;
  bool _planungsressource = false;
  bool _busy = false;

  /// Nach dem ersten Speichern einer NEUEN Maschine: ihre id, damit die
  /// Parameter-Pflege im selben Sheet weitergehen kann.
  String? _maschineId;

  @override
  void initState() {
    super.initState();
    final m = widget.maschine;
    _maschineId = m?.id;
    _name = TextEditingController(text: m?.name ?? '');
    _abteilung = m?.abteilung ?? Abteilung.values.first.dbValue;
    _planungsressource = m?.istPlanungsressource ?? false;
    _kapazitaetStunden = TextEditingController(
      text: m == null
          ? '10'
          : Format.eingabe(m.kapazitaetMinutenProTag / 60),
    );
    _eignung = TextEditingController(text: m?.eignungHinweis ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _kapazitaetStunden.dispose();
    _eignung.dispose();
    super.dispose();
  }

  Future<void> _speichereStamm() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte einen Maschinennamen angeben.')),
      );
      return;
    }
    final stunden = Format.lies(_kapazitaetStunden.text);
    if (stunden == null || stunden <= 0 || stunden > 24) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte eine Kapazität zwischen 0 und 24 h angeben.'),
        ),
      );
      return;
    }

    setState(() => _busy = true);
    final db = ref.read(databaseProvider);
    final jetzt = DateTime.now();

    if (_maschineId != null) {
      await (db.update(db.machines)
            ..where((m) => m.id.equals(_maschineId!)))
          .write(
        MachinesCompanion(
          name: Value(name),
          abteilung: Value(_abteilung),
          istPlanungsressource: Value(_planungsressource),
          kapazitaetMinutenProTag: Value(stunden * 60),
          eignungHinweis: Value(
            _eignung.text.trim().isEmpty ? null : _eignung.text.trim(),
          ),
          updatedAt: Value(jetzt),
        ),
      );
    } else {
      final id = const Uuid().v4();
      await db.into(db.machines).insert(
            MachinesCompanion.insert(
              id: id,
              name: name,
              abteilung: _abteilung,
              istPlanungsressource: Value(_planungsressource),
              kapazitaetMinutenProTag: Value(stunden * 60),
              eignungHinweis: Value(
                _eignung.text.trim().isEmpty ? null : _eignung.text.trim(),
              ),
            ),
          );
      setState(() => _maschineId = id);
    }

    ref
        .read(autoBackupTriggerProvider)
        .fireDebounced(reason: 'Maschine gespeichert');
    // Die Liste hinter dem Fenster gleich auffrischen. Vorher kam eine neue
    // oder umbenannte Maschine erst nach einem Neustart in die Liste: Das
    // Fenster meldete eine Änderung nur beim Löschen zurück.
    ref.invalidate(maschinenKatalogProvider);
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maschine gespeichert.')),
      );
    }
  }

  /// Löscht die Maschine (Soft-Delete) samt ihrer Steckbrief-Parameter.
  /// Warnt vorher, falls die Maschine noch Prozessschritten zugeordnet ist —
  /// diese Schritte behalten dann ihren gespeicherten Maschinen-Text,
  /// verlieren aber die Verknüpfung zum Katalog.
  Future<void> _loescheMaschine() async {
    final id = _maschineId;
    final maschine = widget.maschine;
    if (id == null || maschine == null) return;

    final db = ref.read(databaseProvider);

    // Verwendung prüfen: aktive Schritte mit dieser Maschine.
    final nutzendeSchritte = await (db.select(db.productSteps)
          ..where((s) => s.maschineId.equals(id))
          ..where((s) => s.deletedAt.isNull()))
        .get();

    if (!mounted) return;
    final bestaetigt = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Maschine löschen'),
        content: Text(
          nutzendeSchritte.isEmpty
              ? '„${maschine.name}" wirklich löschen? Der Steckbrief '
                  'dieser Maschine wird mit entfernt.'
              : '„${maschine.name}" wird aktuell in '
                  '${nutzendeSchritte.length} Prozessschritt(en) verwendet. '
                  'Beim Löschen verlieren diese Schritte die Verknüpfung '
                  'zur Maschine (der Name bleibt als Text erhalten). '
                  'Trotzdem löschen?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (bestaetigt != true) return;

    setState(() => _busy = true);
    final jetzt = DateTime.now();

    // Steckbrief-Parameter der Maschine mitlöschen.
    await (db.update(db.machineParameterDefs)
          ..where((d) => d.maschineId.equals(id)))
        .write(MachineParameterDefsCompanion(deletedAt: Value(jetzt)));
    // Maschine selbst.
    await (db.update(db.machines)..where((m) => m.id.equals(id)))
        .write(MachinesCompanion(deletedAt: Value(jetzt)));

    ref
        .read(autoBackupTriggerProvider)
        .fireDebounced(reason: 'Maschine gelöscht');
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _parameterHinzufuegen() async {
    final id = _maschineId;
    if (id == null) return;
    final res = await showDialog<(String, String?)>(
      context: context,
      builder: (_) => const _ParameterDialog(),
    );
    if (res == null) return;

    final db = ref.read(databaseProvider);
    final vorhandene = await ref.read(maschinenParameterDefsProvider(id).future);
    // Duplikate freundlich abfangen (uniqueKey würde sonst hart knallen).
    if (vorhandene
        .any((d) => d.parameterName.toLowerCase() == res.$1.toLowerCase())) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('„${res.$1}" existiert bereits.')),
        );
      }
      return;
    }
    await db.into(db.machineParameterDefs).insert(
          MachineParameterDefsCompanion.insert(
            id: const Uuid().v4(),
            maschineId: id,
            parameterName: res.$1,
            einheit: Value(res.$2),
            sortierung: Value(vorhandene.length),
          ),
        );
    ref.invalidate(maschinenParameterDefsProvider(id));
    ref
        .read(autoBackupTriggerProvider)
        .fireDebounced(reason: 'Maschinen-Parameter angelegt');
  }

  Future<void> _parameterEntfernen(MachineParameterDef def) async {
    final db = ref.read(databaseProvider);
    await (db.update(db.machineParameterDefs)
          ..where((d) => d.id.equals(def.id)))
        .write(
      MachineParameterDefsCompanion(deletedAt: Value(DateTime.now())),
    );
    ref.invalidate(maschinenParameterDefsProvider(def.maschineId));
    ref
        .read(autoBackupTriggerProvider)
        .fireDebounced(reason: 'Maschinen-Parameter entfernt');
  }

  /// Neue Reihenfolge nach Drag & Drop speichern. Es wird die komplette
  /// Sortierung neu durchnummeriert — robuster als Nachbarn zu tauschen,
  /// weil ein Element über beliebig viele Positionen wandern kann.
  Future<void> _parameterNeuOrdnen(
    List<MachineParameterDef> defs,
    int altIndex,
    int neuIndex,
  ) async {
    if (defs.isEmpty) return;
    // Konvention wie im Prozess-Diagramm: Das gezogene Element wird
    // entnommen und an der Position des Ablageziels wieder eingesetzt.
    if (neuIndex == altIndex) return;

    final neueListe = [...defs];
    final bewegt = neueListe.removeAt(altIndex);
    neueListe.insert(neuIndex.clamp(0, neueListe.length), bewegt);

    final db = ref.read(databaseProvider);
    final jetzt = DateTime.now();
    for (var i = 0; i < neueListe.length; i++) {
      await (db.update(db.machineParameterDefs)
            ..where((x) => x.id.equals(neueListe[i].id)))
          .write(
        MachineParameterDefsCompanion(
          sortierung: Value(i),
          updatedAt: Value(jetzt),
        ),
      );
    }
    ref.invalidate(maschinenParameterDefsProvider(bewegt.maschineId));
    ref
        .read(autoBackupTriggerProvider)
        .fireDebounced(reason: 'Parameter-Reihenfolge geändert');
  }

  /// Bearbeitet Name und Einheit eines vorhandenen Steckbrief-Parameters.
  Future<void> _parameterBearbeiten(
    MachineParameterDef def,
    List<MachineParameterDef> alle,
  ) async {
    final res = await showDialog<(String, String?)>(
      context: context,
      builder: (_) => _ParameterDialog(
        name: def.parameterName,
        einheit: def.einheit,
      ),
    );
    if (res == null) return;

    // Namensdubletten abfangen (unique auf maschineId+parameterName).
    final neuerName = res.$1.trim();
    final kollision = alle.any(
      (d) =>
          d.id != def.id &&
          d.parameterName.toLowerCase() == neuerName.toLowerCase(),
    );
    if (kollision) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('„$neuerName" existiert bereits.')),
        );
      }
      return;
    }

    final db = ref.read(databaseProvider);
    await (db.update(db.machineParameterDefs)
          ..where((x) => x.id.equals(def.id)))
        .write(
      MachineParameterDefsCompanion(
        parameterName: Value(neuerName),
        einheit: Value(res.$2),
        updatedAt: Value(DateTime.now()),
      ),
    );
    ref.invalidate(maschinenParameterDefsProvider(def.maschineId));
    ref
        .read(autoBackupTriggerProvider)
        .fireDebounced(reason: 'Maschinen-Parameter bearbeitet');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final id = _maschineId;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          // Kopf wie bei jedem Fenster der App: Titel in Blau, rechts ein
          // Kreuz. Vorher saß hier der Anfasser aus der Bottom-Sheet-Zeit.
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.maschine == null && id == null
                      ? 'Neue Maschine'
                      : 'Maschine bearbeiten',
                  style: theme.dialogTheme.titleTextStyle ??
                      theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                tooltip: 'Schließen',
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Name und Abteilung nebeneinander — das Fenster ist breit genug.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'z.B. Verbufa 3, Räucherkammer 2',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  initialValue: _abteilung,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Abteilung'),
                  items: [
                    for (final a in Abteilung.values)
                      DropdownMenuItem(
                        value: a.dbValue,
                        child: Text(
                          a.anzeigeName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) =>
                      setState(() => _abteilung = v ?? _abteilung),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Eigene Planungsspur'),
            subtitle: const Text(
              'Anlage erscheint mit eigener Kapazität im Wochenplan',
            ),
            value: _planungsressource,
            onChanged: (v) => setState(() => _planungsressource = v),
          ),
          if (_planungsressource) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 200,
                child: TextField(
                  controller: _kapazitaetStunden,
                  decoration: const InputDecoration(
                    labelText: 'Tageskapazität',
                    suffixText: 'h',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _eignung,
            decoration: const InputDecoration(
              labelText: 'Eignungs-Hinweis (optional)',
              hintText: 'z.B. nur Aufschnitt / Ausweichanlage für …',
            ),
          ),
          const SizedBox(height: 16),

          // Knöpfe der Stammdaten wie in jedem Fenster der App: rechts
          // Speichern, links das Löschen — abgesetzt, damit man es nicht
          // aus Versehen trifft. Nach dem Speichern bleibt das Fenster
          // offen, damit es mit dem Steckbrief weitergehen kann.
          Row(
            children: [
              // Löschen nur für bereits gespeicherte Maschinen anbieten.
              if (widget.maschine != null)
                TextButton.icon(
                  onPressed: _busy ? null : _loescheMaschine,
                  style: TextButton.styleFrom(foregroundColor: colors.error),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Maschine löschen …'),
                ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _busy ? null : _speichereStamm,
                // Ohne feste Farbe: Der gesperrte Knopf ist hellgrau, ein
                // weißer Kreisel wäre darauf unsichtbar.
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save, size: 18),
                label: Text(_busy ? 'Speichern …' : 'Maschine speichern'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _steckbrief(context, id),
        ],
      ),
    );
  }

  /// Der Parameter-Steckbrief als Tabelle mit Kopfzeile: je Parameter eine
  /// Zeile mit Anfasser zum Umsortieren, Name, Einheit und Knöpfen.
  /// Vorher eine Karte je Parameter unter einer Überschrift in Großbuchstaben.
  Widget _steckbrief(BuildContext context, String? id) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    Widget rahmen({String? untertitel, required List<Widget> inhalt}) {
      return Bereich(
        titel: 'Parameter-Steckbrief',
        untertitel: untertitel,
        aktionen: [
          TextButton.icon(
            onPressed: id == null ? null : _parameterHinzufuegen,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Parameter hinzufügen'),
          ),
        ],
        innenAbstand: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: colors.outlineVariant),
                ),
              ),
              child: Text(
                'Diese Felder erscheinen in der Artikelmaske, sobald die '
                'Maschine einem Prozessschritt zugeordnet ist. Die Werte '
                'trägst du pro Artikel ein.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            ...inhalt,
          ],
        ),
      );
    }

    if (id == null) {
      return rahmen(
        inhalt: const [
          Padding(
            padding: EdgeInsets.all(12),
            child: HinweisBox(
              'Zuerst die Maschine speichern — danach lassen sich hier '
              'Parameter anlegen.',
            ),
          ),
        ],
      );
    }

    return Consumer(
      builder: (context, ref, _) {
        final defs = ref.watch(maschinenParameterDefsProvider(id));
        return defs.when(
          loading: () => rahmen(inhalt: const [LinearProgressIndicator()]),
          error: (e, _) => rahmen(
            inhalt: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: HinweisBox(
                  'Fehler: ${fehlerText(e)}',
                  art: StatusArt.fehler,
                  auswaehlbar: true,
                ),
              ),
            ],
          ),
          data: (liste) => rahmen(
            untertitel: '${liste.length}',
            inhalt: [
              if (liste.isEmpty)
                const LeerHinweis('Noch keine Parameter angelegt.')
              else
                // Reihenfolge per Drag & Drop — die Pfeiltasten entfallen
                // dadurch. Bewusst mit Draggable/DragTarget statt
                // ReorderableListView: dasselbe Muster wie im
                // Prozess-Diagramm, und unabhängig davon, wie die
                // Flutter-Version die Reorder-Callbacks gerade nennt.
                for (var i = 0; i < liste.length; i++)
                  DragTarget<int>(
                    onWillAcceptWithDetails: (d) => d.data != i,
                    onAcceptWithDetails: (d) =>
                        _parameterNeuOrdnen(liste, d.data, i),
                    builder: (context, kandidaten, abgelehnt) =>
                        _ParameterZeile(
                      def: liste[i],
                      index: i,
                      letzte: i == liste.length - 1,
                      istZiel: kandidaten.isNotEmpty,
                      onBearbeiten: () =>
                          _parameterBearbeiten(liste[i], liste),
                      onEntfernen: () => _parameterEntfernen(liste[i]),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

/// Ein Parameter des Steckbriefs als Tabellenzeile: Anfasser zum
/// Umsortieren, Name, Einheit, Bearbeiten und Entfernen.
class _ParameterZeile extends StatelessWidget {
  const _ParameterZeile({
    required this.def,
    required this.index,
    required this.letzte,
    required this.istZiel,
    required this.onBearbeiten,
    required this.onEntfernen,
  });

  final MachineParameterDef def;

  /// Position in der Liste — die Daten beim Ziehen.
  final int index;

  /// Letzte Zeile: ohne Linie darunter, dort schließt der Rand.
  final bool letzte;

  /// Gerade Ablageziel beim Ziehen: blau hinterlegt und umrandet.
  final bool istZiel;
  final VoidCallback onBearbeiten;
  final VoidCallback onEntfernen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final einheit = (def.einheit ?? '').trim();

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 1, 4, 1),
      decoration: istZiel
          ? BoxDecoration(
              color: AppFarben.von(context).infoFlaeche,
              border: Border.all(color: colors.primary, width: 1.5),
            )
          : BoxDecoration(
              border: letzte
                  ? null
                  : Border(bottom: BorderSide(color: colors.outlineVariant)),
            ),
      child: Row(
        children: [
          Draggable<int>(
            data: index,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: Material(
              color: Colors.transparent,
              child: Chip(label: Text(def.parameterName)),
            ),
            child: Tooltip(
              message: 'Ziehen zum Umsortieren',
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.drag_indicator,
                    size: 20,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              def.parameterName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (einheit.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              einheit,
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
          ],
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: 'Bearbeiten',
            visualDensity: VisualDensity.compact,
            onPressed: onBearbeiten,
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 18, color: colors.error),
            tooltip: 'Entfernen',
            visualDensity: VisualDensity.compact,
            onPressed: onEntfernen,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialog: neuen Parameter anlegen
// ---------------------------------------------------------------------------

class _ParameterDialog extends StatefulWidget {
  const _ParameterDialog({this.name, this.einheit});

  /// Vorbelegung beim Bearbeiten eines bestehenden Parameters.
  final String? name;
  final String? einheit;

  @override
  State<_ParameterDialog> createState() => _ParameterDialogState();
}

class _ParameterDialogState extends State<_ParameterDialog> {
  late final _name = TextEditingController(text: widget.name ?? '');
  late final _einheit = TextEditingController(text: widget.einheit ?? '');

  @override
  void dispose() {
    _name.dispose();
    _einheit.dispose();
    super.dispose();
  }

  void _ok() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final einheit = _einheit.text.trim();
    Navigator.of(context).pop((name, einheit.isEmpty ? null : einheit));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.name == null ? 'Parameter hinzufügen' : 'Parameter bearbeiten',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'z.B. Takte, Temperatur, Portionsgröße',
            ),
            onSubmitted: (_) => _ok(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _einheit,
            decoration: const InputDecoration(
              labelText: 'Einheit (optional)',
              hintText: 'z.B. °C, Takte/min, g',
            ),
            onSubmitted: (_) => _ok(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _ok,
          child: Text(widget.name == null ? 'Hinzufügen' : 'Übernehmen'),
        ),
      ],
    );
  }
}
