import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Feste Gruppen-Kontexte, für die Grenzen gepflegt werden können —
/// zusätzlich zu den Anlagen aus dem Maschinen-Katalog.
const kGrenzenGruppen = <String>['BRATSTRASSE', 'DAMPFTUNNEL'];

/// Alle wählbaren Kontexte: Gruppen + Anlagen-Namen aus dem Katalog.
final grenzenKontexteProvider = FutureProvider<List<String>>((ref) async {
  final db = ref.watch(databaseProvider);
  final maschinen = await (db.select(db.machines)
        ..where((m) => m.deletedAt.isNull())
        ..orderBy([(m) => OrderingTerm.asc(m.name)]))
      .get();
  return [...kGrenzenGruppen, ...maschinen.map((m) => m.name)];
});

/// Alle gepflegten Grenzen, gruppiert nach Kontext.
final grenzenProvider =
    FutureProvider<Map<String, List<ParameterGrenzenData>>>((ref) async {
  final db = ref.watch(databaseProvider);
  final rows = await (db.select(db.parameterGrenzen)
        ..where((g) => g.deletedAt.isNull())
        ..orderBy([
          (g) => OrderingTerm.asc(g.kontext),
          (g) => OrderingTerm.asc(g.parameterName),
        ]))
      .get();
  final map = <String, List<ParameterGrenzenData>>{};
  for (final r in rows) {
    map.putIfAbsent(r.kontext, () => []).add(r);
  }
  return map;
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Pflege der Plausibilitätsgrenzen (Poka-Yoke) für Maschinen- und
/// Prozessparameter: je Kontext (Anlage oder Gruppe) und Parametername
/// harte Grenzen (blockieren) und weiche Grenzen (warnen).
class ParameterGrenzenScreen extends ConsumerWidget {
  const ParameterGrenzenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final grenzen = ref.watch(grenzenProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Maschinen-Grenzen')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _bearbeiten(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('Grenze anlegen'),
      ),
      body: grenzen.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (map) {
          if (map.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.rule,
                      size: 48,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.35),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Noch keine Grenzen gepflegt.\n\n'
                      'Grenzen verhindern Tippfehler bei Maschinen­parametern: '
                      'Harte Grenzen blockieren das Speichern, weiche Grenzen '
                      'zeigen eine Warnung.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
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
                    entry.key,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                for (final g in entry.value)
                  Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      dense: true,
                      title: Text(
                        g.parameterName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(_beschreibung(g)),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () => _bearbeiten(context, ref, g),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  String _beschreibung(ParameterGrenzenData g) {
    String bereich(double? min, double? max) {
      if (min != null && max != null) return '${_z(min)}–${_z(max)}';
      if (min != null) return '≥ ${_z(min)}';
      if (max != null) return '≤ ${_z(max)}';
      return '—';
    }

    final teile = <String>[];
    if (g.hartMin != null || g.hartMax != null) {
      teile.add('Hart: ${bereich(g.hartMin, g.hartMax)}');
    }
    if (g.weichMin != null || g.weichMax != null) {
      teile.add('Warnung: ${bereich(g.weichMin, g.weichMax)}');
    }
    return teile.isEmpty ? 'Keine Grenzen gesetzt' : teile.join('   ·   ');
  }

  static String _z(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  Future<void> _bearbeiten(
    BuildContext context,
    WidgetRef ref,
    ParameterGrenzenData? bestehend,
  ) async {
    final geaendert = await showDialog<bool>(
      context: context,
      builder: (_) => _GrenzeEditorDialog(bestehend: bestehend),
    );
    if (geaendert == true) {
      ref.invalidate(grenzenProvider);
    }
  }
}

// ---------------------------------------------------------------------------
// Editor-Dialog
// ---------------------------------------------------------------------------

class _GrenzeEditorDialog extends ConsumerStatefulWidget {
  const _GrenzeEditorDialog({this.bestehend});

  final ParameterGrenzenData? bestehend;

  @override
  ConsumerState<_GrenzeEditorDialog> createState() =>
      _GrenzeEditorDialogState();
}

class _GrenzeEditorDialogState extends ConsumerState<_GrenzeEditorDialog> {
  String? _kontext;
  late final TextEditingController _name;
  late final TextEditingController _hartMin;
  late final TextEditingController _hartMax;
  late final TextEditingController _weichMin;
  late final TextEditingController _weichMax;
  late final TextEditingController _notizen;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final b = widget.bestehend;
    _kontext = b?.kontext;
    _name = TextEditingController(text: b?.parameterName ?? '');
    _hartMin = TextEditingController(text: _t(b?.hartMin));
    _hartMax = TextEditingController(text: _t(b?.hartMax));
    _weichMin = TextEditingController(text: _t(b?.weichMin));
    _weichMax = TextEditingController(text: _t(b?.weichMax));
    _notizen = TextEditingController(text: b?.notizen ?? '');
  }

  static String _t(double? v) => v == null
      ? ''
      : (v == v.roundToDouble() ? v.round().toString() : v.toString());

  @override
  void dispose() {
    _name.dispose();
    _hartMin.dispose();
    _hartMax.dispose();
    _weichMin.dispose();
    _weichMax.dispose();
    _notizen.dispose();
    super.dispose();
  }

  double? _d(TextEditingController c) {
    final t = c.text.trim().replaceAll(',', '.');
    return t.isEmpty ? null : double.tryParse(t);
  }

  Future<void> _speichern() async {
    final kontext = _kontext;
    final name = _name.text.trim();
    if (kontext == null || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte Kontext und Parameternamen angeben.'),
        ),
      );
      return;
    }

    final hMin = _d(_hartMin);
    final hMax = _d(_hartMax);
    final wMin = _d(_weichMin);
    final wMax = _d(_weichMax);

    // Plausibilität der Grenzen selbst: min <= max, weich innerhalb hart.
    String? fehler;
    if (hMin != null && hMax != null && hMin > hMax) {
      fehler = 'Harte Untergrenze liegt über der harten Obergrenze.';
    } else if (wMin != null && wMax != null && wMin > wMax) {
      fehler = 'Weiche Untergrenze liegt über der weichen Obergrenze.';
    } else if (hMin != null && wMin != null && wMin < hMin) {
      fehler = 'Weiche Untergrenze liegt unter der harten Untergrenze.';
    } else if (hMax != null && wMax != null && wMax > hMax) {
      fehler = 'Weiche Obergrenze liegt über der harten Obergrenze.';
    }
    if (fehler != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(fehler)),
      );
      return;
    }

    setState(() => _busy = true);
    final db = ref.read(databaseProvider);
    final jetzt = DateTime.now();

    if (widget.bestehend != null) {
      await (db.update(db.parameterGrenzen)
            ..where((g) => g.id.equals(widget.bestehend!.id)))
          .write(
        ParameterGrenzenCompanion(
          kontext: Value(kontext),
          parameterName: Value(name),
          hartMin: Value(hMin),
          hartMax: Value(hMax),
          weichMin: Value(wMin),
          weichMax: Value(wMax),
          notizen: Value(
            _notizen.text.trim().isEmpty ? null : _notizen.text.trim(),
          ),
          updatedAt: Value(jetzt),
        ),
      );
    } else {
      await db.into(db.parameterGrenzen).insert(
            ParameterGrenzenCompanion.insert(
              id: const Uuid().v4(),
              kontext: kontext,
              parameterName: name,
              hartMin: Value(hMin),
              hartMax: Value(hMax),
              weichMin: Value(wMin),
              weichMax: Value(wMax),
              notizen: Value(
                _notizen.text.trim().isEmpty ? null : _notizen.text.trim(),
              ),
            ),
          );
    }

    ref
        .read(autoBackupTriggerProvider)
        .fireDebounced(reason: 'Parameter-Grenze gepflegt');
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _loeschen() async {
    final b = widget.bestehend;
    if (b == null) return;
    setState(() => _busy = true);
    final db = ref.read(databaseProvider);
    await (db.update(db.parameterGrenzen)..where((g) => g.id.equals(b.id)))
        .write(
      ParameterGrenzenCompanion(deletedAt: Value(DateTime.now())),
    );
    ref
        .read(autoBackupTriggerProvider)
        .fireDebounced(reason: 'Parameter-Grenze gelöscht');
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final kontexte = ref.watch(grenzenKontexteProvider);

    return AlertDialog(
      title: Text(
        widget.bestehend == null ? 'Grenze anlegen' : 'Grenze bearbeiten',
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              kontexte.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Fehler: $e'),
                data: (liste) => DropdownButtonFormField<String>(
                  initialValue:
                      liste.contains(_kontext) ? _kontext : null,
                  decoration: const InputDecoration(
                    labelText: 'Anlage / Gruppe',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final k in liste)
                      DropdownMenuItem(value: k, child: Text(k)),
                  ],
                  onChanged: (v) => setState(() => _kontext = v),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Parametername (wie im Artikel)',
                  hintText: 'z.B. Bratzeit, Temperatur, Takte',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _hartMin,
                      decoration: const InputDecoration(
                        labelText: 'Hart min',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _hartMax,
                      decoration: const InputDecoration(
                        labelText: 'Hart max',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _weichMin,
                      decoration: const InputDecoration(
                        labelText: 'Warnung min',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _weichMax,
                      decoration: const InputDecoration(
                        labelText: 'Warnung max',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notizen,
                decoration: const InputDecoration(
                  labelText: 'Notiz (optional)',
                  hintText: 'z.B. Herstellerangabe Typenschild',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.bestehend != null)
          TextButton(
            onPressed: _busy ? null : _loeschen,
            child: const Text('Löschen', style: TextStyle(color: Colors.red)),
          ),
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
