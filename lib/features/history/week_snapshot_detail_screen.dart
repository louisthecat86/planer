import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';
import '../../core/services/week_snapshot_service.dart';
import '../../core/theme/app_stil.dart';
import '../../core/ui/bausteine.dart';
import '../../core/utils/datum.dart';
import '../../core/utils/zeit.dart';

const _wkShort = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

/// Ziffern gleich breit, damit Zahlen untereinander ruhig stehen.
const List<FontFeature> _ziffern = [FontFeature.tabularFigures()];

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

    // Den Wochenplan gibt es nur für Wochen, die archiviert wurden, seit
    // das Archiv ihn mitspeichert — sonst ist der Knopf gesperrt und sagt
    // beim Darüberfahren, warum.
    final hatPlan = daten?.plan != null;
    final schmal = MediaQuery.sizeOf(context).width < 720;
    void zeigePlan() => context.pushNamed(
          'wochenHistoriePlan',
          pathParameters: {'snapshotId': widget.snapshotId},
        );
    const ohnePlan = 'Diese Woche wurde archiviert, bevor das Archiv den '
        'Wochenplan mitgespeichert hat.';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          snap == null
              ? 'Auswertung'
              : 'Auswertung KW ${snap.kw} · ${snap.jahr}',
        ),
        actions: [
          if (snap != null && daten != null) ...[
            if (schmal)
              IconButton(
                onPressed: hatPlan ? zeigePlan : null,
                icon: const Icon(Icons.calendar_view_week),
                tooltip: hatPlan ? 'Wochenplan' : ohnePlan,
              )
            else
              Tooltip(
                message: hatPlan
                    ? 'Die Woche so ansehen, wie sie im Wochenboard stand'
                    : ohnePlan,
                child: FilledButton.icon(
                  onPressed: hatPlan ? zeigePlan : null,
                  icon: const Icon(Icons.calendar_view_week, size: 18),
                  label: const Text('Wochenplan'),
                ),
              ),
            const SizedBox(width: 12),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (snap == null || daten == null)
              ? const Center(
                  child: LeerHinweis(
                    'Diese archivierte Woche gibt es nicht mehr – '
                    'vielleicht wurde sie inzwischen gelöscht.',
                    icon: Icons.history,
                  ),
                )
              : _buildInhalt(context, snap, daten),
    );
  }

  Widget _buildInhalt(
    BuildContext context,
    WeekSnapshot snap,
    WochenSnapshotDaten daten,
  ) {
    final ende = tagPlus(snap.wochenStart, 6);
    final aktiveAbteilungen = [
      for (final a in Abteilung.values)
        if ((daten.belegtMinutenJeAbteilung[a.dbValue] ?? 0) > 0) a,
    ];
    final kgGesamt = daten.tasks.fold<double>(0, (s, t) => s + t.mengeKg);

    // Die Auswertung als Bereiche untereinander, wie eine Infoseite in
    // Navision — vorher standen fette Überschriften frei auf der Fläche.
    return LayoutBuilder(
      builder: (context, c) {
        // Auf breiten Bildschirmen nicht über die ganze Breite: Name und
        // Zahlen einer Zeile lägen sonst weit auseinander.
        final seite = math.max(14.0, (c.maxWidth - 1100) / 2);
        return ListView(
          padding: EdgeInsets.fromLTRB(seite, 12, seite, 24),
          children: [
            Bereich(
              titel: 'Woche',
              child: Wrap(
                spacing: 32,
                runSpacing: 10,
                children: [
                  Kennzahl(
                    wert: '${_d(snap.wochenStart)}–${_d(ende)}${snap.jahr}',
                    label: 'Zeitraum',
                  ),
                  Kennzahl(
                    wert: '${daten.anzahlAuftraege}',
                    label: 'Aufträge',
                  ),
                  Kennzahl(
                    wert: '${kgGesamt.toStringAsFixed(0)} kg',
                    label: 'Menge',
                  ),
                  Kennzahl(
                    wert: Zeit.kurz(daten.gesamtBelegtMinuten),
                    label: 'belegt gesamt',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Bereich(
              titel: 'Auslastung je Abteilung',
              untertitel: 'Mo–Fr, gemessen an der Kapazität beim Archivieren',
              child: aktiveAbteilungen.isEmpty
                  ? const LeerHinweis('Keine Aufträge in dieser Woche.')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final abt in aktiveAbteilungen)
                          _AuslastungsBalken(abteilung: abt, daten: daten),
                      ],
                    ),
            ),
            const SizedBox(height: 12),
            Bereich(
              titel: 'Aufträge je Tag',
              innenAbstand: EdgeInsets.zero,
              child: _tageMitAuftraegen(daten),
            ),
            const SizedBox(height: 12),
            Bereich(
              titel: 'Erkenntnisse / Notiz',
              innenAbstand: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _notiz,
                    minLines: 3,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      hintText: 'Was lief gut, was schlecht? Engpässe, '
                          'Auffälligkeiten …',
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
                      // Ohne feste Farbe: Der gesperrte Knopf ist hellgrau,
                      // ein weißer Kreisel wäre darauf unsichtbar.
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save, size: 18),
                      label: const Text('Notiz speichern'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Aufträge nach Tag gruppiert (nur Tage mit Aufträgen): je Tag eine
  /// Kopfzeile, darunter die Aufträge als Zeilen.
  Widget _tageMitAuftraegen(WochenSnapshotDaten daten) {
    final proTag = <DateTime, List<SnapshotTask>>{};
    for (final t in daten.tasks) {
      final tag = DateTime(t.datum.year, t.datum.month, t.datum.day);
      (proTag[tag] ??= []).add(t);
    }
    if (proTag.isEmpty) {
      return const LeerHinweis('Keine Aufträge in dieser Woche.');
    }

    final tage = proTag.keys.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < tage.length; i++)
          _TagesBlock(
            tag: tage[i],
            tasks: proTag[tage[i]]!,
            letzter: i == tage.length - 1,
          ),
      ],
    );
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
    final f = AppFarben.von(context);
    final belegt = daten.belegtMinutenJeAbteilung[abteilung.dbValue] ?? 0;
    final zusatz = daten.zusatzMinutenJeAbteilung[abteilung.dbValue] ?? 0;
    final kg = daten.kgJeAbteilung[abteilung.dbValue] ?? 0;
    final anzahl = daten.auftraegeJeAbteilung[abteilung.dbValue] ?? 0;
    final tagesKap = daten.kapazitaeten[abteilung.dbValue] ?? 0;
    final wochenKap = tagesKap * 5; // Mo–Fr
    final auslastung = wochenKap > 0 ? belegt / wochenKap : 0.0;
    final prozent = (auslastung * 100).round();
    final zusatzText =
        zusatz > 0 ? ' · davon ${Zeit.kurz(zusatz)} Zusatzzeit' : '';
    // Rot überbucht, grün gut gefüllt, sonst grau — wie in der Liste der
    // Wochen-Historie.
    final farbe = auslastung > 1.0
        ? f.fehler
        : (auslastung >= 0.75 ? f.ok : colors.onSurfaceVariant);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AbteilungsMarke(abteilung: abteilung),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        abteilung.anzeigeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      wochenKap > 0
                          ? '${Zeit.kurzOhneEinheit(belegt)} / '
                              '${Zeit.kurz(wochenKap)}'
                          : Zeit.kurz(belegt),
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                        fontFeatures: _ziffern,
                      ),
                    ),
                    if (wochenKap > 0)
                      SizedBox(
                        width: 52,
                        child: Text(
                          '$prozent %',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: farbe,
                            fontFeatures: _ziffern,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: AppMasse.eckenKlein,
                  child: LinearProgressIndicator(
                    value: auslastung.clamp(0.0, 1.0).toDouble(),
                    minHeight: 6,
                    backgroundColor: colors.outlineVariant,
                    color: farbe,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${kg.toStringAsFixed(0)} kg · $anzahl Aufträge$zusatzText',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceVariant,
                    fontFeatures: _ziffern,
                  ),
                ),
              ],
            ),
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
  const _TagesBlock({
    required this.tag,
    required this.tasks,
    required this.letzter,
  });

  final DateTime tag;
  final List<SnapshotTask> tasks;

  /// Letzter Tag: ohne Linie unter der letzten Zeile — dort schließt der
  /// Rand des Bereichs.
  final bool letzter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final wd = _wkShort[(tag.weekday - 1).clamp(0, 6)];
    final minuten = tasks.fold<double>(0, (s, t) => s + t.dauerMinuten);
    final kg = tasks.fold<double>(0, (s, t) => s + t.mengeKg);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Der Tag als Zwischenzeile auf der Fläche der Leisten, rechts die
        // Summe des Tages.
        Container(
          padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
          decoration: BoxDecoration(
            color: AppFarben.von(context).leiste,
            border: Border(bottom: BorderSide(color: colors.outlineVariant)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$wd ${tag.day}.${tag.month}.',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${tasks.length} '
                '${tasks.length == 1 ? 'Auftrag' : 'Aufträge'} · '
                '${kg.toStringAsFixed(0)} kg · ${Zeit.kurz(minuten)}',
                style: TextStyle(
                  fontSize: 11.5,
                  color: colors.onSurfaceVariant,
                  fontFeatures: _ziffern,
                ),
              ),
            ],
          ),
        ),
        for (var i = 0; i < tasks.length; i++)
          _TaskZeile(
            task: tasks[i],
            letzte: letzter && i == tasks.length - 1,
          ),
      ],
    );
  }
}

class _TaskZeile extends StatelessWidget {
  const _TaskZeile({required this.task, required this.letzte});

  final SnapshotTask task;

  /// Letzte Zeile des Bereichs: ohne Linie darunter.
  final bool letzte;

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
    final zahl = TextStyle(
      fontSize: 12,
      color: colors.onSurfaceVariant,
      fontFeatures: _ziffern,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
      decoration: BoxDecoration(
        border: letzte
            ? null
            : Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          AbteilungsMarke(abteilung: _abt),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              task.productName,
              style: const TextStyle(fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 72,
            child: Text(
              '${task.mengeKg.toStringAsFixed(0)} kg',
              textAlign: TextAlign.right,
              style: zahl,
            ),
          ),
          SizedBox(
            width: 68,
            child: Text(
              Zeit.kurz(task.dauerMinuten),
              textAlign: TextAlign.right,
              style: zahl,
            ),
          ),
        ],
      ),
    );
  }
}
