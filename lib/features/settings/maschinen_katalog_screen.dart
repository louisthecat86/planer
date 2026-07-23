import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';
import '../../core/utils/sheet_utils.dart';
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
    final theme = Theme.of(context);
    final katalog = ref.watch(maschinenKatalogProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Maschinen-Katalog'),
        actions: [
          IconButton(
            icon: const Icon(Icons.playlist_add),
            tooltip: 'Standard-Maschinen ergänzen',
            onPressed: () => _seedDialog(context, ref),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _oeffneEditor(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('Neue Maschine'),
      ),
      body: katalog.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (map) {
          if (map.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Noch keine Maschinen angelegt.\n\n'
                  'Lege mit „Neue Maschine" die erste Anlage an oder '
                  'importiere den Anlagen-Katalog aus der Excel.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            children: [
              for (final entry in map.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                  child: Text(
                    entry.key.anzeigeName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                for (final m in entry.value)
                  Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      dense: true,
                      title: Text(
                        m.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: _untertitel(m),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () => _oeffneEditor(context, ref, m),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget? _untertitel(Machine m) {
    final teile = <String>[
      if (m.istPlanungsressource)
        'Eigene Planungsspur · ${(m.kapazitaetMinutenProTag / 60).toStringAsFixed(1).replaceAll('.0', '')} h/Tag',
      if ((m.eignungHinweis ?? '').trim().isNotEmpty) m.eignungHinweis!.trim(),
    ];
    if (teile.isEmpty) return null;
    return Text(
      teile.join('   ·   '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// Fragt nach und ergänzt dann den Standard-Maschinenpark: legt fehlende
  /// Maschinen und deren Steckbrief-Parameter an. Bereits vorhandene
  /// Maschinen (per Name) bleiben unberührt.
  Future<void> _seedDialog(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Standard-Maschinen ergänzen'),
        content: Text(
          'Legt die ${kSeedMaschinen.length} Maschinen des Standard-'
          'Maschinenparks mit ihren Parametern an. Bereits vorhandene '
          'Maschinen werden nicht verändert und nicht doppelt angelegt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Ergänzen'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final db = ref.read(databaseProvider);
    final vorhandene = await (db.select(db.machines)
          ..where((m) => m.deletedAt.isNull()))
        .get();
    final vorhandeneNamen =
        vorhandene.map((m) => m.name.toLowerCase()).toSet();

    var neueMaschinen = 0;
    var neueParams = 0;
    for (final seed in kSeedMaschinen) {
      if (vorhandeneNamen.contains(seed.name.toLowerCase())) continue;
      final maschineId = const Uuid().v4();
      await db.into(db.machines).insert(
            MachinesCompanion.insert(
              id: maschineId,
              name: seed.name,
              abteilung: seed.abteilung,
            ),
          );
      neueMaschinen++;
      for (var i = 0; i < seed.params.length; i++) {
        final p = seed.params[i];
        await db.into(db.machineParameterDefs).insert(
              MachineParameterDefsCompanion.insert(
                id: const Uuid().v4(),
                maschineId: maschineId,
                parameterName: p.name,
                einheit: Value(p.einheit),
                sortierung: Value(i),
              ),
            );
        neueParams++;
      }
    }

    ref
        .read(autoBackupTriggerProvider)
        .fireDebounced(reason: 'Standard-Maschinen ergänzt');
    ref.invalidate(maschinenKatalogProvider);

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
    final geaendert = await showSheetOhneAnimation<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => _MaschineEditorSheet(maschine: maschine),
    );
    if (geaendert == true) {
      ref.invalidate(maschinenKatalogProvider);
    }
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
          ? '9'
          : (m.kapazitaetMinutenProTag / 60)
              .toStringAsFixed(1)
              .replaceAll('.0', ''),
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
    final stunden =
        double.tryParse(_kapazitaetStunden.text.replaceAll(',', '.'));
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
      builder: (_) => AlertDialog(
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
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
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
    // ReorderableListView meldet beim Verschieben nach unten einen um 1
    // zu hohen Zielindex.
    var ziel = neuIndex;
    if (ziel > altIndex) ziel -= 1;
    if (ziel == altIndex) return;

    final neueListe = [...defs];
    final bewegt = neueListe.removeAt(altIndex);
    neueListe.insert(ziel, bewegt);

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
    final id = _maschineId;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(
            widget.maschine == null && id == null
                ? 'Neue Maschine'
                : 'Maschine bearbeiten',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'z.B. Verbufa 3, Räucherkammer 2',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _abteilung,
            decoration: const InputDecoration(
              labelText: 'Abteilung',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final a in Abteilung.values)
                DropdownMenuItem(
                  value: a.dbValue,
                  child: Text(a.anzeigeName),
                ),
            ],
            onChanged: (v) =>
                setState(() => _abteilung = v ?? _abteilung),
          ),
          const SizedBox(height: 12),
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
            const SizedBox(height: 4),
            TextField(
              controller: _kapazitaetStunden,
              decoration: const InputDecoration(
                labelText: 'Tageskapazität',
                suffixText: 'h',
                border: OutlineInputBorder(),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _eignung,
            decoration: const InputDecoration(
              labelText: 'Eignungs-Hinweis (optional)',
              hintText: 'z.B. nur Aufschnitt / Ausweichanlage für …',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton.icon(
              onPressed: _busy ? null : _speichereStamm,
              icon: const Icon(Icons.save),
              label: Text(_busy ? 'Speichern …' : 'Maschine speichern'),
            ),
          ),

          // Löschen nur für bereits gespeicherte Maschinen anbieten.
          if (widget.maschine != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _loescheMaschine,
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text(
                  'Maschine löschen',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),
          Text(
            'PARAMETER-STECKBRIEF',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Diese Felder erscheinen in der Artikelmaske, sobald die '
            'Maschine einem Prozessschritt zugeordnet ist. Die Werte '
            'trägst du pro Artikel ein.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),

          if (id == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Zuerst die Maschine speichern — danach lassen sich hier '
                'Parameter anlegen.',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            Consumer(
              builder: (context, ref, _) {
                final defs =
                    ref.watch(maschinenParameterDefsProvider(id));
                return defs.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('Fehler: $e'),
                  data: (liste) => Column(
                    children: [
                      // Reihenfolge per Drag & Drop — die Pfeiltasten
                      // entfallen dadurch. Die Liste sitzt in einem
                      // scrollenden Sheet, daher shrinkWrap + eigene
                      // Scroll-Physik.
                      ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        buildDefaultDragHandles: false,
                        itemCount: liste.length,
                        onReorder: (alt, neu) =>
                            _parameterNeuOrdnen(liste, alt, neu),
                        itemBuilder: (context, i) {
                          final def = liste[i];
                          return Card(
                            key: ValueKey(def.id),
                            margin: const EdgeInsets.only(bottom: 6),
                            child: ListTile(
                              dense: true,
                              leading: ReorderableDragStartListener(
                                index: i,
                                child: Icon(
                                  Icons.drag_indicator,
                                  size: 20,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              title: Text(
                                def.parameterName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: (def.einheit ?? '').isEmpty
                                  ? null
                                  : Text(def.einheit!),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 18),
                                    tooltip: 'Bearbeiten',
                                    onPressed: () =>
                                        _parameterBearbeiten(def, liste),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 18,
                                      color: Colors.red,
                                    ),
                                    tooltip: 'Entfernen',
                                    onPressed: () => _parameterEntfernen(def),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _parameterHinzufuegen,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Parameter hinzufügen'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(height: 12),
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
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _ok(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _einheit,
            decoration: const InputDecoration(
              labelText: 'Einheit (optional)',
              hintText: 'z.B. °C, Takte/min, g',
              border: OutlineInputBorder(),
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
        FilledButton(onPressed: _ok, child: const Text('Hinzufügen')),
      ],
    );
  }
}
