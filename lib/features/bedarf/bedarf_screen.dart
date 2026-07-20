import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/utils/sheet_utils.dart';
import '../../core/services/auto_backup_trigger.dart';

// ---------------------------------------------------------------------------
// Modell
// ---------------------------------------------------------------------------

/// Ein Bedarf samt berechnetem Fortschritt.
///
/// Die geplante Menge wird NICHT als Zähler geführt, sondern aus den
/// verknüpften Aufträgen summiert. Dadurch kann sie nicht aus dem Tritt
/// geraten: Löscht man eine geplante Produktion, ist der Bedarf sofort
/// wieder offen.
class BedarfInfo {
  const BedarfInfo({
    required this.bedarf,
    required this.artikelName,
    required this.artikelNummer,
    required this.geplantKg,
    required this.produziertKg,
  });

  final Demand bedarf;
  final String artikelName;
  final String artikelNummer;

  /// Insgesamt eingeplante Fertigware-Menge (alle verknüpften Aufträge).
  final double geplantKg;

  /// Davon bereits PRODUZIERT: Aufträge, deren Tag in der Vergangenheit
  /// liegt. Eine Produktion, die auf einen vergangenen Tag geplant war und
  /// nicht mehr verschoben wurde, gilt als gelaufen — der Bedarf ist dann
  /// automatisch gedeckt, ohne dass man ihn von Hand abhaken muss.
  final double produziertKg;

  /// Noch nicht eingeplante Menge (für die Planung relevant).
  double get offenKg =>
      (bedarf.mengeKgFertig - geplantKg).clamp(0, double.infinity);

  /// Eingeplant, aber der Produktionstag steht noch aus.
  double get inPlanungKg =>
      (geplantKg - produziertKg).clamp(0, double.infinity);

  /// Erledigt, wenn manuell abgehakt ODER die produzierte Menge den Bedarf
  /// deckt (Produktionstag liegt in der Vergangenheit).
  bool get erledigt =>
      bedarf.manuellErledigt ||
      produziertKg >= bedarf.mengeKgFertig - 0.5;

  /// Fortschritt am eingeplanten Anteil (zeigt auch die noch offene Planung).
  double get fortschritt => bedarf.mengeKgFertig > 0
      ? (geplantKg / bedarf.mengeKgFertig).clamp(0.0, 1.0)
      : 0.0;

  /// Anteil, der bereits produziert ist (für die zweifarbige Leiste).
  double get produziertAnteil => bedarf.mengeKgFertig > 0
      ? (produziertKg / bedarf.mengeKgFertig).clamp(0.0, 1.0)
      : 0.0;

  /// Termin überschritten und noch nicht gedeckt?
  bool get ueberfaellig {
    final t = bedarf.termin;
    if (t == null || erledigt) return false;
    final heute = DateTime.now();
    return t.isBefore(DateTime(heute.year, heute.month, heute.day));
  }
}

/// Alle offenen und erledigten Bedarfe, sortiert: überfällig → Termin →
/// Priorität.
final bedarfProvider = FutureProvider<List<BedarfInfo>>((ref) async {
  final db = ref.watch(databaseProvider);

  final bedarfe = await (db.select(db.demands)
        ..where((b) => b.deletedAt.isNull()))
      .get();
  if (bedarfe.isEmpty) return [];

  final produkte = await (db.select(db.products)
        ..where((p) => p.deletedAt.isNull()))
      .get();
  final nameById = {for (final p in produkte) p.id: p};

  // Geplante Fertigmengen je Bedarf (nur Ketten-Wurzeln tragen den Wert).
  // Zusätzlich getrennt: was davon schon PRODUZIERT ist (Tag vorbei).
  final tasks = await (db.select(db.productionTasks)
        ..where((t) => t.deletedAt.isNull())
        ..where((t) => t.bedarfId.isNotNull()))
      .get();
  final heute = DateTime.now();
  final heuteNorm = DateTime(heute.year, heute.month, heute.day);
  final geplantJeBedarf = <String, double>{};
  final produziertJeBedarf = <String, double>{};
  for (final t in tasks) {
    final bid = t.bedarfId;
    final menge = t.fertigMengeKg;
    if (bid == null || menge == null) continue;
    geplantJeBedarf[bid] = (geplantJeBedarf[bid] ?? 0) + menge;
    // Produktionstag liegt echt VOR heute → gilt als gelaufen.
    final tag = DateTime(t.datum.year, t.datum.month, t.datum.day);
    if (tag.isBefore(heuteNorm)) {
      produziertJeBedarf[bid] = (produziertJeBedarf[bid] ?? 0) + menge;
    }
  }

  final result = [
    for (final b in bedarfe)
      BedarfInfo(
        bedarf: b,
        artikelName: nameById[b.productId]?.artikelbezeichnung ?? 'Unbekannt',
        artikelNummer: nameById[b.productId]?.artikelnummer ?? '—',
        geplantKg: geplantJeBedarf[b.id] ?? 0,
        produziertKg: produziertJeBedarf[b.id] ?? 0,
      ),
  ];

  result.sort((a, b) {
    // Erledigte immer ans Ende
    if (a.erledigt != b.erledigt) return a.erledigt ? 1 : -1;
    // Überfällige nach oben
    if (a.ueberfaellig != b.ueberfaellig) return a.ueberfaellig ? -1 : 1;
    // Dann nach Termin (ohne Termin zuletzt)
    final ta = a.bedarf.termin;
    final tb = b.bedarf.termin;
    if (ta != null && tb != null && ta != tb) return ta.compareTo(tb);
    if (ta == null && tb != null) return 1;
    if (ta != null && tb == null) return -1;
    // Dann Priorität
    return b.bedarf.prioritaet.compareTo(a.bedarf.prioritaet);
  });
  return result;
});

/// Nur die noch offenen Bedarfe — für die Auswahl beim Planen.
final offeneBedarfeProvider = FutureProvider<List<BedarfInfo>>((ref) async {
  final alle = await ref.watch(bedarfProvider.future);
  return alle.where((b) => !b.erledigt).toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class BedarfScreen extends ConsumerWidget {
  const BedarfScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(bedarfProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bedarfsliste'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Bedarf hinzufügen',
            onPressed: () => _bearbeiten(context, ref, null),
          ),
        ],
      ),
      body: async.when(
        data: (liste) {
          if (liste.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.playlist_add,
                      size: 48,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.35),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Noch kein Bedarf erfasst.\n\n'
                      'Trage hier ein, was produziert werden muss — '
                      'Bestellungen oder Bestandsauffüllung. Beim Planen '
                      'wählst du dann direkt daraus aus.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () => _bearbeiten(context, ref, null),
                      icon: const Icon(Icons.add),
                      label: const Text('Ersten Bedarf anlegen'),
                    ),
                  ],
                ),
              ),
            );
          }

          final offen = liste.where((b) => !b.erledigt).toList();
          final offenSumme =
              offen.fold<double>(0, (s, b) => s + b.offenKg);
          final ueberfaellig = offen.where((b) => b.ueberfaellig).length;

          return Column(
            children: [
              // Kopfzeile mit den Kennzahlen
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.4),
                child: Row(
                  children: [
                    _Kennzahl(
                      wert: '${offen.length}',
                      label: 'offen',
                    ),
                    const SizedBox(width: 24),
                    _Kennzahl(
                      wert: '${offenSumme.round()} kg',
                      label: 'noch einzuplanen',
                    ),
                    if (ueberfaellig > 0) ...[
                      const SizedBox(width: 24),
                      _Kennzahl(
                        wert: '$ueberfaellig',
                        label: 'überfällig',
                        farbe: theme.colorScheme.error,
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: liste.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _BedarfKarte(
                    info: liste[i],
                    onTap: () => _bearbeiten(context, ref, liste[i].bedarf),
                    onErledigt: () => _erledigtUmschalten(ref, liste[i]),
                    onLoeschen: () =>
                        _loeschen(context, ref, liste[i]),
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
      ),
    );
  }

  Future<void> _erledigtUmschalten(WidgetRef ref, BedarfInfo info) async {
    final db = ref.read(databaseProvider);
    await (db.update(db.demands)..where((b) => b.id.equals(info.bedarf.id)))
        .write(
      DemandsCompanion(
        manuellErledigt: Value(!info.bedarf.manuellErledigt),
        updatedAt: Value(DateTime.now()),
      ),
    );
    ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Bedarf geändert');
    ref.invalidate(bedarfProvider);
  }

  Future<void> _loeschen(
    BuildContext context,
    WidgetRef ref,
    BedarfInfo info,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bedarf löschen?'),
        content: Text(
          '${info.artikelName}\n${info.bedarf.mengeKgFertig.round()} kg\n\n'
          'Bereits geplante Aufträge bleiben bestehen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final db = ref.read(databaseProvider);
    await (db.update(db.demands)..where((b) => b.id.equals(info.bedarf.id)))
        .write(DemandsCompanion(deletedAt: Value(DateTime.now())));
    ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Bedarf gelöscht');
    ref.invalidate(bedarfProvider);
  }

  Future<void> _bearbeiten(
    BuildContext context,
    WidgetRef ref,
    Demand? vorhanden,
  ) async {
    final geaendert = await showSheetOhneAnimation<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => _BedarfEditor(bedarf: vorhanden),
    );
    if (geaendert == true) ref.invalidate(bedarfProvider);
  }
}

class _Kennzahl extends StatelessWidget {
  const _Kennzahl({required this.wert, required this.label, this.farbe});

  final String wert;
  final String label;
  final Color? farbe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          wert,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: farbe,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _BedarfKarte extends StatelessWidget {
  const _BedarfKarte({
    required this.info,
    required this.onTap,
    required this.onErledigt,
    required this.onLoeschen,
  });

  final BedarfInfo info;
  final VoidCallback onTap;
  final VoidCallback onErledigt;
  final VoidCallback onLoeschen;

  static const _quellen = {
    'bestellung': 'Bestellung',
    'bestand': 'Bestand',
    'sonstiges': 'Sonstiges',
  };

  String _fortschrittText(BedarfInfo info) {
    final b = info.bedarf;
    if (info.produziertKg >= 0.5 && info.produziertKg < b.mengeKgFertig - 0.5) {
      return '${info.produziertKg.round()} kg produziert · '
          '${info.geplantKg.round()} von ${b.mengeKgFertig.round()} kg geplant';
    }
    return '${info.geplantKg.round()} von '
        '${b.mengeKgFertig.round()} kg eingeplant';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = info.bedarf;
    final akzent = info.erledigt
        ? theme.colorScheme.onSurface.withValues(alpha: 0.3)
        : info.ueberfaellig
            ? theme.colorScheme.error
            : theme.colorScheme.primary;

    String terminText() {
      final t = b.termin;
      if (t == null) return 'ohne Termin';
      return '${t.day.toString().padLeft(2, '0')}.'
          '${t.month.toString().padLeft(2, '0')}.${t.year}';
    }

    return Opacity(
      opacity: info.erledigt ? 0.55 : 1,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(width: 4, height: 34, color: akzent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            info.artikelName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${info.artikelNummer} · '
                            '${_quellen[b.quelle] ?? b.quelle} · '
                            '${terminText()}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: info.ueberfaellig
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight: info.ueberfaellig
                                  ? FontWeight.w700
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (b.prioritaet > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(
                          Icons.priority_high,
                          size: 18,
                          color: theme.colorScheme.error,
                        ),
                      ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 18),
                      onSelected: (v) {
                        if (v == 'erledigt') onErledigt();
                        if (v == 'loeschen') onLoeschen();
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'erledigt',
                          child: Text(
                            b.manuellErledigt
                                ? 'Wieder öffnen'
                                : 'Als erledigt markieren',
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'loeschen',
                          child: Text('Löschen'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Fortschritt: geplant von benötigt
                Row(
                  children: [
                    Expanded(
                      // Zweistufige Leiste: kräftig = bereits produziert
                      // (Tag vorbei), blasser = eingeplant aber noch offen.
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: Stack(
                          children: [
                            LinearProgressIndicator(
                              value: info.fortschritt,
                              minHeight: 6,
                              backgroundColor: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.10),
                              color: akzent.withValues(alpha: 0.35),
                            ),
                            LinearProgressIndicator(
                              value: info.produziertAnteil,
                              minHeight: 6,
                              backgroundColor: Colors.transparent,
                              color: akzent,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      info.erledigt
                          ? 'gedeckt'
                          : info.inPlanungKg > 0.5
                              ? '${info.inPlanungKg.round()} kg geplant'
                              : '${info.offenKg.round()} kg offen',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: akzent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  _fortschrittText(info),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (b.notizen != null && b.notizen!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    b.notizen!.trim(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Editor
// ---------------------------------------------------------------------------

class _BedarfEditor extends ConsumerStatefulWidget {
  const _BedarfEditor({required this.bedarf});

  final Demand? bedarf;

  @override
  ConsumerState<_BedarfEditor> createState() => _BedarfEditorState();
}

class _BedarfEditorState extends ConsumerState<_BedarfEditor> {
  final _suche = TextEditingController();
  final _menge = TextEditingController();
  final _notizen = TextEditingController();

  String? _productId;
  String _quelle = 'bestellung';
  int _prioritaet = 0;
  DateTime? _termin;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final b = widget.bedarf;
    if (b != null) {
      _productId = b.productId;
      _menge.text = b.mengeKgFertig.toStringAsFixed(0);
      _notizen.text = b.notizen ?? '';
      _quelle = b.quelle;
      _prioritaet = b.prioritaet;
      _termin = b.termin;
    }
  }

  @override
  void dispose() {
    _suche.dispose();
    _menge.dispose();
    _notizen.dispose();
    super.dispose();
  }

  Future<void> _speichern() async {
    final pid = _productId;
    final menge = double.tryParse(_menge.text.replaceAll(',', '.'));
    if (pid == null || menge == null || menge <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte Artikel wählen und eine Menge > 0 eingeben.'),
        ),
      );
      return;
    }

    setState(() => _busy = true);
    final db = ref.read(databaseProvider);
    final jetzt = DateTime.now();
    final notiz = _notizen.text.trim().isEmpty ? null : _notizen.text.trim();

    if (widget.bedarf == null) {
      await db.into(db.demands).insert(
            DemandsCompanion.insert(
              id: const Uuid().v4(),
              productId: pid,
              mengeKgFertig: menge,
              termin: Value(_termin),
              quelle: Value(_quelle),
              prioritaet: Value(_prioritaet),
              notizen: Value(notiz),
            ),
          );
    } else {
      await (db.update(db.demands)
            ..where((b) => b.id.equals(widget.bedarf!.id)))
          .write(
        DemandsCompanion(
          productId: Value(pid),
          mengeKgFertig: Value(menge),
          termin: Value(_termin),
          quelle: Value(_quelle),
          prioritaet: Value(_prioritaet),
          notizen: Value(notiz),
          updatedAt: Value(jetzt),
        ),
      );
    }

    ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Bedarf erfasst');
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final produkteAsync = ref.watch(_produkteProvider);

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
            widget.bedarf == null ? 'Bedarf hinzufügen' : 'Bedarf bearbeiten',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Menge in Fertigware — die benötigte Rohware rechnet die '
            'Planung daraus zurück.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),

          // Artikelauswahl
          produkteAsync.when(
            data: (produkte) {
              final gewaehlt = _productId == null
                  ? null
                  : produkte.where((p) => p.id == _productId).firstOrNull;
              if (gewaehlt != null) {
                return Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(Icons.inventory_2),
                    title: Text(gewaehlt.artikelbezeichnung),
                    subtitle: Text(gewaehlt.artikelnummer),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _productId = null),
                    ),
                  ),
                );
              }
              final q = _suche.text.trim().toLowerCase();
              final gefiltert = q.isEmpty
                  ? produkte
                  : produkte
                      .where(
                        (p) =>
                            p.artikelbezeichnung
                                .toLowerCase()
                                .contains(q) ||
                            p.artikelnummer.toLowerCase().contains(q),
                      )
                      .toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _suche,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Artikel suchen',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.3,
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: gefiltert.length,
                      itemBuilder: (context, i) {
                        final p = gefiltert[i];
                        return ListTile(
                          dense: true,
                          title: Text(p.artikelbezeichnung),
                          subtitle: Text(p.artikelnummer),
                          onTap: () => setState(() => _productId = p.id),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Fehler: $e'),
          ),

          const SizedBox(height: 16),
          TextField(
            controller: _menge,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Benötigte Menge (kg Fertigware)',
              suffixText: 'kg',
            ),
          ),
          const SizedBox(height: 16),

          // Termin
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final jetzt = DateTime.now();
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _termin ?? jetzt,
                      firstDate: jetzt.subtract(const Duration(days: 30)),
                      lastDate: jetzt.add(const Duration(days: 365)),
                    );
                    if (d != null) setState(() => _termin = d);
                  },
                  icon: const Icon(Icons.event, size: 18),
                  label: Text(
                    _termin == null
                        ? 'Termin wählen'
                        : '${_termin!.day.toString().padLeft(2, '0')}.'
                            '${_termin!.month.toString().padLeft(2, '0')}.'
                            '${_termin!.year}',
                  ),
                ),
              ),
              if (_termin != null)
                IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Termin entfernen',
                  onPressed: () => setState(() => _termin = null),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Quelle
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'bestellung', label: Text('Bestellung')),
              ButtonSegment(value: 'bestand', label: Text('Bestand')),
              ButtonSegment(value: 'sonstiges', label: Text('Sonstiges')),
            ],
            selected: {_quelle},
            onSelectionChanged: (s) => setState(() => _quelle = s.first),
            showSelectedIcon: false,
          ),
          const SizedBox(height: 12),

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Hohe Priorität'),
            subtitle: const Text('Wird in der Liste oben einsortiert'),
            value: _prioritaet > 0,
            onChanged: (v) => setState(() => _prioritaet = v ? 1 : 0),
          ),

          TextField(
            controller: _notizen,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Notizen (Kunde, Auftragsnummer …)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _speichern,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Speichern'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Alle aktiven Artikel (für die Auswahl im Editor).
final _produkteProvider = FutureProvider<List<Product>>((ref) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.products)
        ..where((p) => p.deletedAt.isNull())
        ..orderBy([(p) => OrderingTerm.asc(p.artikelbezeichnung)]))
      .get();
});
