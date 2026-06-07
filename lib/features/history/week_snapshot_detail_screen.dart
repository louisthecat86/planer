import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';
import '../../core/services/week_snapshot_service.dart';

const _wkShort = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

/// Ausführliche Auswertung eines eingefrorenen Wochenplans:
/// Auslastung je Abteilung (gegen die eingefrorene Kapazität), Aufträge je
/// Tag und ein editierbares Erkenntnis-/Notizfeld.
class WeekSnapshotDetailScreen extends ConsumerStatefulWidget {
  const WeekSnapshotDetailScreen({super.key, required this.snapshotId});

  final String snapshotId;

  @override
  ConsumerState<WeekSnapshotDetailScreen> createState() =>
      _WeekSnapshotDetailScreenState();
}

class _WeekSnapshotDetailScreenState
    extends ConsumerState<WeekSnapshotDetailScreen> {
  final _notiz = TextEditingController();

  WeekSnapshot? _snap;
  WochenSnapshotDaten? _daten;
  bool _loading = true;
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final snap =
        await ref.read(weekSnapshotProvider(widget.snapshotId).future);
    if (!mounted) return;
    setState(() {
      _snap = snap;
      _daten = snap == null ? null : dekodiereSnapshot(snap);
      _notiz.text = snap?.notiz ?? '';
      _loading = false;
    });
  }

  Future<void> _speichereNotiz() async {
    setState(() => _saving = true);
    final db = ref.read(databaseProvider);
    await aktualisiereSnapshotNotiz(db, widget.snapshotId, _notiz.text.trim());
    ref.read(autoBackupTriggerProvider).fireDebounced(
          reason: 'Erkenntnis gespeichert',
        );
    ref.invalidate(weekSnapshotsProvider);
    ref.invalidate(weekSnapshotProvider(widget.snapshotId));
    if (mounted) {
      setState(() {
        _dirty = false;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notiz gespeichert.')),
      );
    }
  }

  @override
  void dispose() {
    _notiz.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snap;
    final daten = _daten;

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(
          snap == null ? 'Auswertung' : 'KW ${snap.kw} · ${snap.jahr}',
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (snap == null || daten == null)
              ? const Center(child: Text('Snapshot nicht gefunden.'))
              : _buildInhalt(context, snap, daten),
    );
  }

  Widget _buildInhalt(
    BuildContext context,
    WeekSnapshot snap,
    WochenSnapshotDaten daten,
  ) {
    final colors = Theme.of(context).colorScheme;
    final ende = snap.wochenStart.add(const Duration(days: 6));
    final aktiveAbteilungen = [
      for (final a in Abteilung.values)
        if ((daten.belegtMinutenJeAbteilung[a.dbValue] ?? 0) > 0) a,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text(
          '${_d(snap.wochenStart)}–${_d(ende)}${snap.jahr} · '
          '${daten.anzahlAuftraege} Aufträge · '
          '${(daten.gesamtBelegtMinuten / 60).toStringAsFixed(1)} h gesamt',
          style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 20),

        // ── Auslastung je Abteilung ──────────────────────────────────────
        Text(
          'Auslastung je Abteilung',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 10),
        if (aktiveAbteilungen.isEmpty)
          Text(
            'Keine Aufträge in dieser Woche.',
            style: TextStyle(color: colors.onSurfaceVariant),
          )
        else
          for (final abt in aktiveAbteilungen)
            _AuslastungsBalken(abteilung: abt, daten: daten),

        const SizedBox(height: 24),

        // ── Aufträge je Tag ──────────────────────────────────────────────
        Text(
          'Aufträge je Tag',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 10),
        ..._tageMitAuftraegen(snap, daten),

        const SizedBox(height: 24),

        // ── Erkenntnis/Notiz ─────────────────────────────────────────────
        Text(
          'Erkenntnisse / Notiz',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _notiz,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Was lief gut/schlecht? Engpässe, Auffälligkeiten …',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) {
            if (!_dirty) setState(() => _dirty = true);
          },
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: (!_dirty || _saving) ? null : _speichereNotiz,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save, size: 18),
            label: const Text('Notiz speichern'),
          ),
        ),
      ],
    );
  }

  /// Tasks nach Tag gruppiert (nur Tage mit Aufträgen), je Tag eine Liste.
  List<Widget> _tageMitAuftraegen(
    WeekSnapshot snap,
    WochenSnapshotDaten daten,
  ) {
    final proTag = <DateTime, List<SnapshotTask>>{};
    for (final t in daten.tasks) {
      final tag = DateTime(t.datum.year, t.datum.month, t.datum.day);
      (proTag[tag] ??= []).add(t);
    }
    if (proTag.isEmpty) {
      return [
        Text(
          '— keine —',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ];
    }

    final tage = proTag.keys.toList()..sort();
    return [
      for (final tag in tage)
        _TagesBlock(tag: tag, tasks: proTag[tag]!),
    ];
  }

  static String _d(DateTime d) => '${d.day}.${d.month}.';
}

// ---------------------------------------------------------------------------
// Auslastungs-Balken je Abteilung
// ---------------------------------------------------------------------------

class _AuslastungsBalken extends StatelessWidget {
  const _AuslastungsBalken({required this.abteilung, required this.daten});

  final Abteilung abteilung;
  final WochenSnapshotDaten daten;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final belegt = daten.belegtMinutenJeAbteilung[abteilung.dbValue] ?? 0;
    final kg = daten.kgJeAbteilung[abteilung.dbValue] ?? 0;
    final anzahl = daten.auftraegeJeAbteilung[abteilung.dbValue] ?? 0;
    final tagesKap = daten.kapazitaeten[abteilung.dbValue] ?? 0;
    final wochenKap = tagesKap * 5; // Mo–Fr
    final auslastung = wochenKap > 0 ? belegt / wochenKap : 0.0;
    final prozent = (auslastung * 100).round();
    final farbe = auslastung > 1.0
        ? const Color(0xFFC62828)
        : (auslastung >= 0.75
            ? const Color(0xFF2E7D32)
            : const Color(0xFF9E9E9E));

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: abteilung.farbe,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  abteilung.anzeigeName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                wochenKap > 0
                    ? '${(belegt / 60).toStringAsFixed(1)} / '
                        '${(wochenKap / 60).toStringAsFixed(1)} h · $prozent%'
                    : '${(belegt / 60).toStringAsFixed(1)} h',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: farbe,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: auslastung.clamp(0.0, 1.0).toDouble(),
              minHeight: 6,
              backgroundColor: Colors.grey.shade200,
              color: farbe,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${kg.toStringAsFixed(0)} kg · $anzahl Aufträge',
            style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tages-Block (Aufträge eines Tages)
// ---------------------------------------------------------------------------

class _TagesBlock extends StatelessWidget {
  const _TagesBlock({required this.tag, required this.tasks});

  final DateTime tag;
  final List<SnapshotTask> tasks;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final wd = _wkShort[(tag.weekday - 1).clamp(0, 6)];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$wd ${tag.day}.${tag.month}.',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          for (final t in tasks) _TaskZeile(task: t),
        ],
      ),
    );
  }
}

class _TaskZeile extends StatelessWidget {
  const _TaskZeile({required this.task});

  final SnapshotTask task;

  Abteilung? get _abt {
    try {
      return Abteilung.fromDbValue(task.abteilung);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final abt = _abt;
    final farbe = abt?.farbe ?? Colors.grey;
    final code = abt?.kurzcode ?? '–';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 34,
            padding: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              color: farbe,
              borderRadius: BorderRadius.circular(5),
            ),
            alignment: Alignment.center,
            child: Text(
              code,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              task.productName,
              style: const TextStyle(fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${task.mengeKg.toStringAsFixed(0)} kg · '
            '${(task.dauerMinuten / 60).toStringAsFixed(1)} h',
            style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}