import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/utils/sheet_utils.dart';
import '../whiteboard/produktion_erfassen_sheet.dart';

// ---------------------------------------------------------------------------
// Modell + Provider
// ---------------------------------------------------------------------------

/// Eine geplante Produktion (Ketten-Wurzel) für die Erfassungs-Übersicht.
class GeplanteProduktion {
  const GeplanteProduktion({
    required this.task,
    required this.artikelName,
    required this.artikelNummer,
  });

  final ProductionTask task;
  final String artikelName;
  final String artikelNummer;

  double get mengeKg => task.fertigMengeKg ?? task.mengeKg;
}

/// Die zu erfassende Woche (Montag). Standard: aktuelle Woche.
final erfassungWocheProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  final montag = now.subtract(Duration(days: now.weekday - 1));
  return DateTime(montag.year, montag.month, montag.day);
});

/// Alle geplanten Produktionen (Ketten-Wurzeln) der gewählten Woche,
/// gruppiert nach Wochentag (Mo–Fr). Nur die WURZEL jeder Kette zählt —
/// eine Produktion wird einmal erfasst, nicht je Abteilungsschritt.
final erfassungWocheDatenProvider = FutureProvider<
    Map<DateTime, List<GeplanteProduktion>>>((ref) async {
  final db = ref.watch(databaseProvider);
  final montag = ref.watch(erfassungWocheProvider);
  final freitagEnde = montag.add(const Duration(days: 5));

  // Nur Ketten-Wurzeln: sie tragen die Fertigmenge und stehen für die
  // gesamte Produktion.
  final tasks = await (db.select(db.productionTasks)
        ..where((t) => t.deletedAt.isNull())
        ..where((t) => t.parentTaskId.isNull())
        ..where((t) => t.datum.isBiggerOrEqualValue(montag))
        ..where((t) => t.datum.isSmallerThanValue(freitagEnde))
        ..where((t) => t.status.isNotIn(const ['storniert'])))
      .get();

  if (tasks.isEmpty) return {};

  final produkte = await (db.select(db.products)
        ..where((p) => p.deletedAt.isNull()))
      .get();
  final byId = {for (final p in produkte) p.id: p};

  // Für den „erfasst"-Hinweis: welche (Artikel, Tag)-Kombinationen haben
  // bereits eine Historienzeile?
  final historie = await (db.select(db.productionHistory)
        ..where((h) => h.deletedAt.isNull())
        ..where((h) => h.datum.isBiggerOrEqualValue(montag))
        ..where((h) => h.datum.isSmallerThanValue(freitagEnde)))
      .get();
  String schluessel(String productId, DateTime d) =>
      '$productId|${d.year}-${d.month}-${d.day}';
  final erfassteKeys = {
    for (final h in historie) schluessel(h.productId, h.datum),
  };

  final gruppen = <DateTime, List<GeplanteProduktion>>{};
  for (final t in tasks) {
    final tag = DateTime(t.datum.year, t.datum.month, t.datum.day);
    // Sobald für diesen Artikel an diesem Tag eine Historie erfasst wurde,
    // gilt die Produktion als erledigt und verschwindet aus der Liste.
    if (erfassteKeys.contains(schluessel(t.productId, tag))) continue;
    final p = byId[t.productId];
    gruppen.putIfAbsent(tag, () => []).add(
          GeplanteProduktion(
            task: t,
            artikelName: p?.artikelbezeichnung ?? 'Unbekannt',
            artikelNummer: p?.artikelnummer ?? '—',
          ),
        );
  }

  // Innerhalb eines Tages nach Artikelname sortieren.
  for (final liste in gruppen.values) {
    liste.sort((a, b) => a.artikelName.compareTo(b.artikelName));
  }
  return gruppen;
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

const _wochentage = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag'];

class ProduktionErfassungScreen extends ConsumerWidget {
  const ProduktionErfassungScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final montag = ref.watch(erfassungWocheProvider);
    final async = ref.watch(erfassungWocheDatenProvider);
    final kw = _kalenderwoche(montag);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Produktionserfassung'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'Vorige Woche',
                  onPressed: () => ref
                      .read(erfassungWocheProvider.notifier)
                      .state = montag.subtract(const Duration(days: 7)),
                ),
                Expanded(
                  child: Text(
                    'KW $kw · ab ${montag.day}.${montag.month}.${montag.year}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'Nächste Woche',
                  onPressed: () => ref
                      .read(erfassungWocheProvider.notifier)
                      .state = montag.add(const Duration(days: 7)),
                ),
              ],
            ),
          ),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (gruppen) {
          if (gruppen.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.fact_check_outlined,
                      size: 48,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.35),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Für diese Woche ist nichts geplant.\n\n'
                      'Sobald im Wochenplan Produktionen stehen, erscheinen '
                      'sie hier zum Erfassen der Ist-Daten.',
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
            padding: const EdgeInsets.all(12),
            children: [
              for (var i = 0; i < 5; i++)
                ..._tagAbschnitt(
                  context,
                  ref,
                  montag.add(Duration(days: i)),
                  _wochentage[i],
                  gruppen[montag.add(Duration(days: i))] ?? const [],
                ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _tagAbschnitt(
    BuildContext context,
    WidgetRef ref,
    DateTime tag,
    String name,
    List<GeplanteProduktion> produktionen,
  ) {
    final theme = Theme.of(context);
    if (produktionen.isEmpty) return const [];

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
        child: Text(
          '$name · ${tag.day}.${tag.month}.',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
      for (final prod in produktionen)
        _ProduktionKarte(
          prod: prod,
          onErfassen: () => _erfassen(context, ref, prod),
        ),
    ];
  }

  Future<void> _erfassen(
    BuildContext context,
    WidgetRef ref,
    GeplanteProduktion prod,
  ) async {
    final erfasst = await showSheetOhneAnimation<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => ProduktionErfassenSheet(
        productId: prod.task.productId,
        vorschlagMengeKg: prod.mengeKg,
        vorschlagDatum: prod.task.datum,
        vorschlagStart: prod.task.startZeit,
      ),
    );
    if (erfasst == true) {
      ref.invalidate(erfassungWocheDatenProvider);
    }
  }

  int _kalenderwoche(DateTime d) {
    // ISO-8601-Kalenderwoche.
    final donnerstag = d.add(Duration(days: 3 - ((d.weekday + 6) % 7)));
    final ersterJan = DateTime(donnerstag.year, 1, 1);
    return 1 + (donnerstag.difference(ersterJan).inDays ~/ 7);
  }
}

class _ProduktionKarte extends StatelessWidget {
  const _ProduktionKarte({required this.prod, required this.onErfassen});

  final GeplanteProduktion prod;
  final VoidCallback onErfassen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onErfassen,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      prod.artikelName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${prod.artikelNummer} · '
                      '${prod.mengeKg.toStringAsFixed(0)} kg geplant',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.tonalIcon(
                onPressed: onErfassen,
                icon: const Icon(Icons.edit_note, size: 18),
                label: const Text('Erfassen'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
