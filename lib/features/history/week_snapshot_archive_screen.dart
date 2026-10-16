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
import '../board/board_providers.dart';
// Dasselbe Datum wie im Board: Die Auswahl zum Archivieren beginnt bei der
// Woche, die dort gerade zu sehen ist. Vorher hatte die Startseite eine
// eigene Kopie dieses Providers, die nie jemand setzte.
import '../whiteboard/whiteboard_provider.dart' show selectedDateProvider;

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
      // Kapazität je Abteilung aus den tatsächlichen Anlagen-Spuren der
      // Woche — dieselbe Rechnung wie im Wochenboard.
      //
      // Vorher stand hier für JEDE Abteilung die Regelarbeitszeit von 9 h.
      // Das stammt aus der Zeit vor Migration v9, als die Abteilung die
      // planbare Einheit war. Seither sind es die Anlagen: In der
      // Verpackung laufen mehrere echt parallel, die Tageskapazität ist
      // also ein Vielfaches von 540 Minuten. Mit dem alten Wert meldete
      // die Auswertung dort dauerhaft Überbuchung, obwohl der Plan
      // problemlos aufging.
      final kapazitaeten = await tageskapazitaetJeAbteilung(
        db,
        wochenStart: tagDerWoche,
      );

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
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
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
    // Schmale Fenster: der Knopf der Kopfleiste nur als Symbol.
    final schmal = MediaQuery.sizeOf(context).width < 720;
    // Ohne feste Farbe: Der gesperrte Knopf ist hellgrau, ein weißer
    // Kreisel wäre darauf unsichtbar.
    const kreisel = SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wochen-Historie'),
        actions: [
          // Die Hauptaktion oben rechts wie auf den übrigen Seiten —
          // vorher ein schwebender Knopf, der unten die letzte Woche
          // verdeckte.
          if (schmal)
            IconButton(
              onPressed: _busy ? null : _archiviere,
              icon: _busy ? kreisel : const Icon(Icons.archive_outlined),
              tooltip: 'Woche archivieren',
            )
          else
            FilledButton.icon(
              onPressed: _busy ? null : _archiviere,
              icon: _busy
                  ? kreisel
                  : const Icon(Icons.archive_outlined, size: 18),
              label: const Text('Woche archivieren …'),
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: snapsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(
          padding: const EdgeInsets.all(14),
          children: [
            HinweisBox(
              'Fehler: $e',
              art: StatusArt.fehler,
              auswaehlbar: true,
            ),
          ],
        ),
        data: (snaps) {
          return Column(
            children: [
              // Umschalter: Kalender oder Liste
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 2),
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
                        ? const Center(
                            child: LeerHinweis(
                              'Noch keine archivierten Wochen. Mit „Woche '
                              'archivieren" oben rechts frierst du den '
                              'aktuellen Plan einer Woche ein.',
                              icon: Icons.history,
                            ),
                          )
                        : ListView.builder(
                            padding:
                                const EdgeInsets.fromLTRB(14, 10, 14, 24),
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
    final farben = theme.colorScheme;
    final snapVonMontag = <String, WeekSnapshot>{
      for (final s in snaps) _tagKey(s.wochenStart): s,
    };

    final ersterDesMonats = DateTime(_monat.year, _monat.month, 1);
    final letzterDesMonats = DateTime(_monat.year, _monat.month + 1, 0);
    var montag = montagDerWoche(ersterDesMonats);
    final wochen = <DateTime>[];
    while (!montag.isAfter(letzterDesMonats)) {
      wochen.add(montag);
      // Über die Tageszahl: Mit Duration landete die Woche nach der
      // Zeitumstellung auf Sonntag 23:00, und der Kalender zeigte eine
      // Woche doppelt und die folgende gar nicht.
      montag = tagPlus(montag, 7);
    }

    // Der Monat als eine Fläche mit Rand: oben der Monat zum Blättern auf
    // der Fläche der Leisten, darunter die Wochen als Zeilen — wie eine
    // Tabelle in Navision. Vorher stand jede Woche auf einer eigenen,
    // runden Kachel.
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
      children: [
        Material(
          color: farben.surface,
          shape: RoundedRectangleBorder(
            borderRadius: AppMasse.ecken,
            side: BorderSide(color: farben.outline),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: AppFarben.von(context).leiste,
                  border: Border(bottom: BorderSide(color: farben.outline)),
                ),
                child: Column(
                  children: [
                    // Monats-Navigation: < Monat Jahr >
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Vorheriger Monat',
                          onPressed: () => setState(
                            () => _monat =
                                DateTime(_monat.year, _monat.month - 1),
                          ),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Expanded(
                          child: Text(
                            '${_monatsName(_monat.month)} ${_monat.year}',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Nächster Monat',
                          onPressed: () => setState(
                            () => _monat =
                                DateTime(_monat.year, _monat.month + 1),
                          ),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                    // Wochentagskopf
                    Padding(
                      // Bündig mit den Tagen der Wochen: Rand, KW-Marke
                      // und Abstand der Zeilen abzüglich des Rands hier.
                      padding: const EdgeInsets.fromLTRB(48, 0, 4, 6),
                      child: Row(
                        children: [
                          for (final t in const [
                            'Mo',
                            'Di',
                            'Mi',
                            'Do',
                            'Fr',
                            'Sa',
                            'So',
                          ])
                            Expanded(
                              child: Text(
                                t,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: farben.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              for (final (i, w) in wochen.indexed)
                _KalenderWoche(
                  montag: w,
                  anzeigeMonat: _monat.month,
                  snapshot: snapVonMontag[_tagKey(w)],
                  letzte: i == wochen.length - 1,
                  onOeffnen: (s) => context.pushNamed(
                    'wochenHistorieDetail',
                    pathParameters: {'snapshotId': s.id},
                  ),
                  onArchivieren:
                      _busy ? null : () => _archiviereWocheMitFrage(w),
                ),
            ],
          ),
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
    final ende = tagPlus(snap.wochenStart, 6);
    final stunden = Zeit.kurzOhneEinheit(daten.gesamtBelegtMinuten);
    final notiz = snap.notiz?.trim() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        // Aufgeklappt ohne eigene Linien — den Rand zieht die Karte.
        shape: const Border(),
        collapsedShape: const Border(),
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
          if (notiz.isNotEmpty) ...[
            const SizedBox(height: 8),
            HinweisBox(notiz, art: StatusArt.neutral, icon: Icons.notes),
          ],
          const SizedBox(height: 8),
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
                style: TextButton.styleFrom(foregroundColor: colors.error),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Löschen …'),
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
    final f = AppFarben.von(context);
    final belegt = daten.belegtMinutenJeAbteilung[abteilung.dbValue] ?? 0;
    final kg = daten.kgJeAbteilung[abteilung.dbValue] ?? 0;
    final anzahl = daten.auftraegeJeAbteilung[abteilung.dbValue] ?? 0;

    // Wochen-Kapazität = Tageskapazität × 5 Arbeitstage (Mo–Fr).
    final tagesKap = daten.kapazitaeten[abteilung.dbValue] ?? 0;
    final wochenKap = tagesKap * 5;
    final auslastung = wochenKap > 0 ? belegt / wochenKap : 0.0;
    final prozent = (auslastung * 100).round();
    // Rot überbucht, grün gut gefüllt, sonst grau — wie die Auslastung auf
    // der Übersicht.
    final farbe = auslastung > 1.0
        ? f.fehler
        : (auslastung >= 0.75 ? f.ok : colors.onSurfaceVariant);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          AbteilungsMarke(abteilung: abteilung),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              abteilung.anzeigeName,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Text(
            '${Zeit.kurz(belegt)} · '
            '${kg.toStringAsFixed(0)} kg · $anzahl Aufträge',
            style: TextStyle(
              fontSize: 12,
              color: colors.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 48,
            child: Text(
              '$prozent %',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: farbe,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Eine Wochenzeile im Kalender: KW-Marke, sieben Tageszellen und eine
/// Statuszeile. Archiviert = blau hinterlegt und öffnet die Auswertung;
/// leer = antippen archiviert die Woche.
class _KalenderWoche extends StatelessWidget {
  const _KalenderWoche({
    required this.montag,
    required this.anzeigeMonat,
    required this.snapshot,
    required this.letzte,
    required this.onOeffnen,
    required this.onArchivieren,
  });

  final DateTime montag;
  final int anzeigeMonat;
  final WeekSnapshot? snapshot;

  /// Letzte Woche des Monats: ohne Linie darunter — dort schließt der Rand.
  final bool letzte;
  final void Function(WeekSnapshot) onOeffnen;
  final VoidCallback? onArchivieren;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final f = AppFarben.von(context);
    final kw = isoKalenderwoche(montag);
    final snap = snapshot;
    final hatSnap = snap != null;
    final heute = DateTime.now();
    final daten = hatSnap ? dekodiereSnapshot(snap) : null;
    final tage = [for (var i = 0; i < 7; i++) tagPlus(montag, i)];

    // Material statt Farbe am Container: Die Hover- und Tipp-Welle des
    // InkWell malt auf das nächste Material.
    return Material(
      color: hatSnap ? f.infoFlaeche : Colors.transparent,
      child: InkWell(
        onTap: hatSnap ? () => onOeffnen(snap) : onArchivieren,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          decoration: BoxDecoration(
            border: letzte
                ? null
                : Border(bottom: BorderSide(color: colors.outlineVariant)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                padding: const EdgeInsets.symmetric(vertical: 5),
                decoration: BoxDecoration(
                  color: hatSnap ? colors.primary : f.leiste,
                  borderRadius: AppMasse.eckenKlein,
                  border: hatSnap ? null : Border.all(color: colors.outline),
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
                        fontWeight: FontWeight.w700,
                        color: hatSnap ? colors.onPrimary : colors.onSurface,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
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
    );
  }
}

/// Eine einzelne Tageszelle im Kalender. Heute trägt einen blauen Rahmen —
/// der ist auf weißen wie auf blau hinterlegten Wochen zu sehen.
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: istHeute
          ? BoxDecoration(
              border: Border.all(color: theme.colorScheme.primary),
              borderRadius: AppMasse.eckenKlein,
            )
          : null,
      child: Text(
        '${tag.day}',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: istHeute ? FontWeight.w700 : FontWeight.w500,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: imMonat
              ? theme.colorScheme.onSurface
              : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
        ),
      ),
    );
  }
}
