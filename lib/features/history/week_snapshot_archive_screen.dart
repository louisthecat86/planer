import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';
import '../../core/services/week_snapshot_service.dart';
import '../../core/utils/zeit.dart';
import '../board/board_providers.dart';
import '../shell/home_screen.dart';

/// Archiv der eingefrorenen Wochenpläne.
///
/// Zeigt alle Snapshots (neueste zuerst), erlaubt das manuelle Einfrieren
/// einer Woche („Woche archivieren") und das Löschen. Jeder Eintrag lässt
/// sich aufklappen und zeigt die Kennzahlen je Abteilung (geplante Stunden,
/// Auslastung gegen die eingefrorene Kapazität, kg, Anzahl Aufträge).
class WeekSnapshotArchiveScreen extends ConsumerStatefulWidget {
  const WeekSnapshotArchiveScreen({super.key});

  @override
  ConsumerState<WeekSnapshotArchiveScreen> createState() =>
      _WeekSnapshotArchiveScreenState();
}

class _WeekSnapshotArchiveScreenState
    extends ConsumerState<WeekSnapshotArchiveScreen> {
  bool _busy = false;
  bool _kalender = true;
  DateTime _monat = DateTime(DateTime.now().year, DateTime.now().month);

  Future<void> _archiviere() async {
    final sel = ref.read(selectedDateProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: sel,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: 'Woche zum Archivieren wählen (beliebiger Tag der Woche)',
    );
    if (picked == null) return;
    await _archiviereWoche(picked);
  }

  /// Klick auf eine leere Woche im Kalender: kurz nachfragen, dann archivieren.
  Future<void> _archiviereWocheMitFrage(DateTime tagDerWoche) async {
    final kw = isoKalenderwoche(montagDerWoche(tagDerWoche));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('KW $kw archivieren?'),
        content: const Text(
          'Der aktuelle Plan dieser Woche wird als Momentaufnahme '
          'eingefroren und erscheint danach in der Historie.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Archivieren'),
          ),
        ],
      ),
    );
    if (ok == true) await _archiviereWoche(tagDerWoche);
  }

  Future<void> _archiviereWoche(DateTime tagDerWoche) async {
    setState(() => _busy = true);
    try {
      final db = ref.read(databaseProvider);
      // Einheitliche Regelarbeitszeit: alle Abteilungen 9 h.
      final kapazitaeten = {
        for (final a in Abteilung.values)
          a.dbValue: kStandardKapazitaetMinuten,
      };

      await erstelleWochenSnapshot(
        db: db,
        wochenStart: tagDerWoche,
        kapazitaeten: kapazitaeten,
      );
      ref.read(autoBackupTriggerProvider).fireDebounced(
            reason: 'Woche archiviert',
          );
      ref.invalidate(weekSnapshotsProvider);

      if (mounted) {
        final kw = isoKalenderwoche(montagDerWoche(tagDerWoche));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('KW $kw archiviert.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loeschen(WeekSnapshot snap) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('KW ${snap.kw} löschen?'),
        content: const Text(
          'Dieser archivierte Wochenplan wird entfernt. Das kann nicht '
          'rückgängig gemacht werden.',
        ),
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
    if (ok != true) return;

    final db = ref.read(databaseProvider);
    await loescheWochenSnapshot(db, snap.id);
    ref.read(autoBackupTriggerProvider).fireDebounced(
          reason: 'Snapshot gelöscht',
        );
    ref.invalidate(weekSnapshotsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final snapsAsync = ref.watch(weekSnapshotsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Wochen-Historie'),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _archiviere,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.archive_outlined),
        label: const Text('Woche archivieren'),
      ),
      body: snapsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (snaps) {
          return Column(
            children: [
              // Umschalter: Kalender oder Liste
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.calendar_month, size: 16),
                        label: Text('Kalender'),
                      ),
                      ButtonSegment(
                        value: false,
                        icon: Icon(Icons.view_list, size: 16),
                        label: Text('Liste'),
                      ),
                    ],
                    selected: {_kalender},
                    onSelectionChanged: (s) =>
                        setState(() => _kalender = s.first),
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _kalender
                    ? _buildKalender(context, snaps)
                    : (snaps.isEmpty
                        ? const _LeerHinweis()
                        : ListView.builder(
                            padding:
                                const EdgeInsets.fromLTRB(12, 8, 12, 96),
                            itemCount: snaps.length,
                            itemBuilder: (context, i) => _SnapshotKarte(
                              snap: snaps[i],
                              onDelete: () => _loeschen(snaps[i]),
                            ),
                          )),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Kalender-Ansicht: Monat mit Wochenzeilen. Archivierte Wochen sind
  /// hervorgehoben und öffnen per Klick ihre Auswertung; leere Wochen lassen
  /// sich per Klick archivieren.
  Widget _buildKalender(BuildContext context, List<WeekSnapshot> snaps) {
    final theme = Theme.of(context);
    final snapVonMontag = <String, WeekSnapshot>{
      for (final s in snaps) _tagKey(s.wochenStart): s,
    };

    final ersterDesMonats = DateTime(_monat.year, _monat.month, 1);
    final letzterDesMonats = DateTime(_monat.year, _monat.month + 1, 0);
    var montag = montagDerWoche(ersterDesMonats);
    final wochen = <DateTime>[];
    while (!montag.isAfter(letzterDesMonats)) {
      wochen.add(montag);
      montag = montag.add(const Duration(days: 7));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
      children: [
        // Monats-Navigation: < Monat Jahr >
        Row(
          children: [
            IconButton(
              tooltip: 'Vorheriger Monat',
              onPressed: () => setState(
                () => _monat = DateTime(_monat.year, _monat.month - 1),
              ),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                '${_monatsName(_monat.month)} ${_monat.year}',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Nächster Monat',
              onPressed: () => setState(
                () => _monat = DateTime(_monat.year, _monat.month + 1),
              ),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        // Wochentagskopf
        Padding(
          padding: const EdgeInsets.only(left: 46, top: 2, bottom: 4),
          child: Row(
            children: [
              for (final t in const ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'])
                Expanded(
                  child: Text(
                    t,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
        for (final w in wochen)
          _KalenderWoche(
            montag: w,
            anzeigeMonat: _monat.month,
            snapshot: snapVonMontag[_tagKey(w)],
            onOeffnen: (s) => context.pushNamed(
              'wochenHistorieDetail',
              pathParameters: {'snapshotId': s.id},
            ),
            onArchivieren:
                _busy ? null : () => _archiviereWocheMitFrage(w),
          ),
      ],
    );
  }

  static String _tagKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  static String _monatsName(int m) => const [
        'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli',
        'August', 'September', 'Oktober', 'November', 'Dezember',
      ][m - 1];
}

// ---------------------------------------------------------------------------
// Einzelner Snapshot
// ---------------------------------------------------------------------------

class _SnapshotKarte extends StatelessWidget {
  const _SnapshotKarte({required this.snap, required this.onDelete});

  final WeekSnapshot snap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final daten = dekodiereSnapshot(snap);
    final ende = snap.wochenStart.add(const Duration(days: 6));
    final stunden = Zeit.kurzOhneEinheit(daten.gesamtBelegtMinuten);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        title: Text(
          'KW ${snap.kw} · ${snap.jahr}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${_d(snap.wochenStart)}–${_d(ende)} · '
          '${daten.anzahlAuftraege} Aufträge · $stunden h',
          style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
        ),
        children: [
          for (final abt in Abteilung.values)
            if ((daten.belegtMinutenJeAbteilung[abt.dbValue] ?? 0) > 0)
              _AbteilungsZeile(abteilung: abt, daten: daten),
          if (snap.notiz != null && snap.notiz!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                snap.notiz!,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: () => context.pushNamed(
                  'wochenHistorieDetail',
                  pathParameters: {'snapshotId': snap.id},
                ),
                icon: const Icon(Icons.insights, size: 18),
                label: const Text('Auswertung öffnen'),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onDelete,
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.red,
                  size: 18,
                ),
                label: const Text(
                  'Löschen',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _d(DateTime d) => '${d.day}.${d.month}.';
}

class _AbteilungsZeile extends StatelessWidget {
  const _AbteilungsZeile({required this.abteilung, required this.daten});

  final Abteilung abteilung;
  final WochenSnapshotDaten daten;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final belegt = daten.belegtMinutenJeAbteilung[abteilung.dbValue] ?? 0;
    final kg = daten.kgJeAbteilung[abteilung.dbValue] ?? 0;
    final anzahl = daten.auftraegeJeAbteilung[abteilung.dbValue] ?? 0;

    // Wochen-Kapazität = Tageskapazität × 5 Arbeitstage (Mo–Fr).
    final tagesKap = daten.kapazitaeten[abteilung.dbValue] ?? 0;
    final wochenKap = tagesKap * 5;
    final auslastung = wochenKap > 0 ? belegt / wochenKap : 0.0;
    final prozent = (auslastung * 100).round();
    final farbe = auslastung > 1.0
        ? const Color(0xFFC62828)
        : (auslastung >= 0.75
            ? const Color(0xFF2E7D32)
            : colors.onSurfaceVariant);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: abteilung.farbe,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              abteilung.anzeigeName,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Text(
            '${Zeit.kurz(belegt)} · '
            '${kg.toStringAsFixed(0)} kg · $anzahl Aufträge',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            child: Text(
              '$prozent%',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: farbe,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Eine Wochenzeile im Kalender: KW-Badge, sieben Tageszellen und eine
/// Statuszeile. Archiviert = hervorgehoben und öffnet die Auswertung; leer =
/// antippen archiviert die Woche.
class _KalenderWoche extends StatelessWidget {
  const _KalenderWoche({
    required this.montag,
    required this.anzeigeMonat,
    required this.snapshot,
    required this.onOeffnen,
    required this.onArchivieren,
  });

  final DateTime montag;
  final int anzeigeMonat;
  final WeekSnapshot? snapshot;
  final void Function(WeekSnapshot) onOeffnen;
  final VoidCallback? onArchivieren;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final kw = isoKalenderwoche(montag);
    final snap = snapshot;
    final hatSnap = snap != null;
    final heute = DateTime.now();
    final daten = hatSnap ? dekodiereSnapshot(snap) : null;
    final tage = [for (var i = 0; i < 7; i++) montag.add(Duration(days: i))];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: hatSnap
            ? colors.primaryContainer.withValues(alpha: 0.35)
            : colors.surfaceContainerHighest.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: hatSnap ? () => onOeffnen(snap) : onArchivieren,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: hatSnap
                        ? colors.primary
                        : colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'KW',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: hatSnap
                              ? colors.onPrimary
                              : colors.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '$kw',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color:
                              hatSnap ? colors.onPrimary : colors.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          for (final tag in tage)
                            Expanded(
                              child: _KalenderTag(
                                tag: tag,
                                imMonat: tag.month == anzeigeMonat,
                                istHeute: tag.year == heute.year &&
                                    tag.month == heute.month &&
                                    tag.day == heute.day,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (hatSnap)
                        Row(
                          children: [
                            Icon(
                              Icons.check_circle,
                              size: 13,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'archiviert · ${daten!.anzahlAuftraege} '
                                'Aufträge · '
                                '${Zeit.kurzOhneEinheit(daten.gesamtBelegtMinuten)} h '
                                '· antippen zum Öffnen',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        )
                      else if (onArchivieren != null)
                        Text(
                          'antippen, um diese Woche zu archivieren',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Eine einzelne Tageszelle im Kalender.
class _KalenderTag extends StatelessWidget {
  const _KalenderTag({
    required this.tag,
    required this.imMonat,
    required this.istHeute,
  });

  final DateTime tag;
  final bool imMonat;
  final bool istHeute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 1),
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: istHeute
          ? BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(6),
            )
          : null,
      child: Text(
        '${tag.day}',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: istHeute ? FontWeight.w800 : FontWeight.w500,
          color: imMonat
              ? theme.colorScheme.onSurface
              : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
        ),
      ),
    );
  }
}

class _LeerHinweis extends StatelessWidget {
  const _LeerHinweis();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 48, color: colors.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'Noch keine archivierten Wochen.\n\n'
              'Tippe unten auf „Woche archivieren", um den aktuellen '
              'Plan einer Woche einzufrieren.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
