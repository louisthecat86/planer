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
        wochenStart: picked,
        kapazitaeten: kapazitaeten,
      );
      ref.read(autoBackupTriggerProvider).fireDebounced(
            reason: 'Woche archiviert',
          );
      ref.invalidate(weekSnapshotsProvider);

      if (mounted) {
        final kw = isoKalenderwoche(montagDerWoche(picked));
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
          if (snaps.isEmpty) {
            return const _LeerHinweis();
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            itemCount: snaps.length,
            itemBuilder: (context, i) => _SnapshotKarte(
              snap: snaps[i],
              onDelete: () => _loeschen(snaps[i]),
            ),
          );
        },
      ),
    );
  }
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
