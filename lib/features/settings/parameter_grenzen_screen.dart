import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';
import '../../core/theme/app_stil.dart';
import '../../core/ui/bausteine.dart';
import '../../core/utils/fehler_text.dart';
import '../../core/utils/sheet_utils.dart';

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

/// Ziffern gleich breit, damit Zahlen untereinander ruhig stehen.
const List<FontFeature> _ziffern = [FontFeature.tabularFigures()];

/// Ein Grenzbereich als Text: „10–20", „≥ 10", „≤ 20" — oder „—".
String _bereich(double? min, double? max) {
  if (min != null && max != null) return '${_z(min)}–${_z(max)}';
  if (min != null) return '≥ ${_z(min)}';
  if (max != null) return '≤ ${_z(max)}';
  return '—';
}

/// Eine Zahl ohne „.0" bei ganzen Werten.
String _z(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toString();

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
    final grenzen = ref.watch(grenzenProvider);
    // Schmale Fenster: der Knopf der Kopfleiste nur als Symbol.
    final schmal = MediaQuery.sizeOf(context).width < 720;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Maschinen-Grenzen'),
        actions: [
          // Die Hauptaktion oben rechts wie auf den übrigen Seiten —
          // vorher ein schwebender Knopf, der unten die letzte Grenze
          // verdeckte.
          if (schmal)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Grenze anlegen',
              onPressed: () => _bearbeiten(context, ref, null),
            )
          else
            FilledButton.icon(
              onPressed: () => _bearbeiten(context, ref, null),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Grenze anlegen'),
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: grenzen.when(
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
                child: const LeerHinweis(
                  'Noch keine Grenzen gepflegt. Grenzen verhindern '
                  'Tippfehler bei Maschinen­parametern: Harte Grenzen '
                  'blockieren das Speichern, weiche Grenzen zeigen eine '
                  'Warnung.',
                  icon: Icons.rule,
                ),
              ),
            );
          }
          // Je Anlage oder Gruppe eine Tabelle mit Spaltenkopf — vorher
          // eine Karte je Grenze unter einer blauen Überschrift.
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
            children: [
              for (final entry in map.entries) ...[
                Bereich(
                  titel: entry.key,
                  untertitel: entry.value.length == 1
                      ? '1 Grenze'
                      : '${entry.value.length} Grenzen',
                  innenAbstand: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _GrenzenKopf(),
                      for (var i = 0; i < entry.value.length; i++)
                        _GrenzenZeile(
                          grenze: entry.value[i],
                          letzte: i == entry.value.length - 1,
                          onTap: () =>
                              _bearbeiten(context, ref, entry.value[i]),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _bearbeiten(
    BuildContext context,
    WidgetRef ref,
    ParameterGrenzenData? bestehend,
  ) async {
    // Ein Fenster wie die übrigen der App: Kopf mit Kreuz, Knöpfe unten.
    final geaendert = await showSheetOhneAnimation<bool>(
      context: context,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (_) => _GrenzeEditorDialog(bestehend: bestehend),
    );
    if (geaendert == true) {
      ref.invalidate(grenzenProvider);
    }
  }
}

// ---------------------------------------------------------------------------
// Tabelle
// ---------------------------------------------------------------------------

/// Spaltenbreiten der Grenzen-Tabelle — für Kopf und Zeilen dieselben.
abstract final class _Spalten {
  static const double grenze = 130;
  static const double pfeil = 24;
}

/// Spaltenköpfe auf der Fläche der Leisten.
class _GrenzenKopf extends StatelessWidget {
  const _GrenzenKopf();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final stil = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: colors.onSurfaceVariant,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 5, 6, 5),
      decoration: BoxDecoration(
        color: AppFarben.von(context).leiste,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(child: Text('Parameter', style: stil)),
          SizedBox(
            width: _Spalten.grenze,
            child: Text('Hart (sperrt)', style: stil),
          ),
          SizedBox(
            width: _Spalten.grenze,
            child: Text('Warnung', style: stil),
          ),
          const SizedBox(width: _Spalten.pfeil),
        ],
      ),
    );
  }
}

/// Eine Grenze als Tabellenzeile: Parameter (darunter die Notiz), harte
/// und weiche Grenze. Antippen öffnet das Bearbeiten.
class _GrenzenZeile extends StatelessWidget {
  const _GrenzenZeile({
    required this.grenze,
    required this.letzte,
    required this.onTap,
  });

  final ParameterGrenzenData grenze;

  /// Letzte Zeile: ohne Linie darunter, dort schließt der Rand.
  final bool letzte;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final g = grenze;
    final notiz = (g.notizen ?? '').trim();
    const zahl = TextStyle(fontSize: 12.5, fontFeatures: _ziffern);

    // Material statt Farbe am Container: Die Hover- und Tipp-Welle des
    // InkWell malt auf das nächste Material.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
          decoration: BoxDecoration(
            border: letzte
                ? null
                : Border(bottom: BorderSide(color: colors.outlineVariant)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      g.parameterName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (notiz.isNotEmpty)
                      Text(
                        notiz,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                width: _Spalten.grenze,
                child: Text(_bereich(g.hartMin, g.hartMax), style: zahl),
              ),
              SizedBox(
                width: _Spalten.grenze,
                child: Text(_bereich(g.weichMin, g.weichMax), style: zahl),
              ),
              SizedBox(
                width: _Spalten.pfeil,
                child: Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final kontexte = ref.watch(grenzenKontexteProvider);
    const zahlTastatur = TextInputType.numberWithOptions(decimal: true);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          // Kopf wie bei jedem Fenster der App: Titel in Blau, rechts ein
          // Kreuz.
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.bestehend == null
                      ? 'Grenze anlegen'
                      : 'Grenze bearbeiten',
                  style: theme.dialogTheme.titleTextStyle ??
                      theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                tooltip: 'Schließen ohne Speichern',
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Harte Grenzen sperren das Speichern eines Werts, weiche '
            'Grenzen zeigen nur eine Warnung.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          kontexte.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => HinweisBox(
              'Anlagen konnten nicht geladen werden: ${fehlerText(e)}',
              art: StatusArt.fehler,
              auswaehlbar: true,
            ),
            data: (liste) => DropdownButtonFormField<String>(
              initialValue: liste.contains(_kontext) ? _kontext : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Anlage / Gruppe',
              ),
              items: [
                for (final k in liste)
                  DropdownMenuItem(
                    value: k,
                    child: Text(k, overflow: TextOverflow.ellipsis),
                  ),
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
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _hartMin,
                  decoration: const InputDecoration(labelText: 'Hart min'),
                  keyboardType: zahlTastatur,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _hartMax,
                  decoration: const InputDecoration(labelText: 'Hart max'),
                  keyboardType: zahlTastatur,
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
                  ),
                  keyboardType: zahlTastatur,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _weichMax,
                  decoration: const InputDecoration(
                    labelText: 'Warnung max',
                  ),
                  keyboardType: zahlTastatur,
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
            ),
          ),
          const SizedBox(height: 20),

          // Knöpfe unten wie in jedem Fenster der App: rechts Abbrechen
          // und Speichern, links das Löschen — abgesetzt, damit man es
          // nicht aus Versehen trifft.
          Row(
            children: [
              if (widget.bestehend != null)
                TextButton.icon(
                  onPressed: _busy ? null : _loeschen,
                  style: TextButton.styleFrom(foregroundColor: colors.error),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Löschen'),
                ),
              const Spacer(),
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: const Text('Abbrechen'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _busy ? null : _speichern,
                // Ohne feste Farbe: Der gesperrte Knopf ist hellgrau, ein
                // weißer Kreisel wäre darauf unsichtbar.
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save, size: 18),
                label: Text(_busy ? 'Speichern …' : 'Speichern'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
