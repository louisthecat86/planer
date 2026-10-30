part of 'week_board_screen.dart';

// ---------------------------------------------------------------------------
// Archivierter Wochenplan
// ---------------------------------------------------------------------------

/// Ein archivierter Wochenplan — so, wie er beim Archivieren im Wochenboard
/// stand: dieselben Spuren, Karten, Ketten und Haken, dazu die sonstigen
/// Aufgaben.
///
/// Nur zum Ansehen: Nichts lässt sich verschieben, abhaken oder öffnen.
/// „Kompakt" und „Passend" gelten wie im Board — wer das Board kompakt
/// liest, sieht auch das Archiv so.
///
/// Wochen, die archiviert wurden, bevor das Archiv den Plan mitgespeichert
/// hat, haben keinen Wochenplan — dafür steht hier ein Hinweis.
class ArchivWochenplanScreen extends ConsumerWidget {
  const ArchivWochenplanScreen({super.key, required this.snapshotId});

  final String snapshotId;

  /// Öffnet das Druckfenster für den Plan von [snap].
  Future<void> _drucken(BuildContext context, WeekSnapshot snap) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final daten = dekodiereSnapshot(snap);
      final plan = daten.plan;
      if (plan == null) return;
      await druckFensterOeffnen(
        context,
        archivPlanDruckAuftrag(
          woche: wochenboardAusArchiv(
            plan,
            stand: snap.createdAt,
            zusatzzeiten: daten.zusatzzeiten,
          ),
          aufgaben: aufgabenAusArchiv(plan, stand: snap.createdAt),
          stand: snap.createdAt,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
            'Der Wochenplan ließ sich nicht drucken. (${fehlerText(e)})',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapAsync = ref.watch(weekSnapshotProvider(snapshotId));
    final geladen = snapAsync.valueOrNull;
    // Drucken lässt sich nur, wo es einen Plan gibt.
    final druckbar =
        geladen != null && dekodiereSnapshot(geladen).plan != null
            ? geladen
            : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          geladen == null
              ? 'Wochenplan'
              : 'Wochenplan KW ${geladen.kw} · ${geladen.jahr}',
        ),
        actions: [
          if (druckbar != null)
            IconButton(
              key: const ValueKey('archivplan-drucken'),
              onPressed: () => _drucken(context, druckbar),
              icon: const Icon(Icons.print),
              tooltip: 'Wochenplan drucken',
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: snapAsync.when(
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
        data: (snap) {
          if (snap == null) {
            return const Center(
              child: LeerHinweis(
                'Diese archivierte Woche gibt es nicht mehr – vielleicht '
                'wurde sie inzwischen gelöscht.',
                icon: Icons.history,
              ),
            );
          }
          final daten = dekodiereSnapshot(snap);
          final plan = daten.plan;
          if (plan == null) {
            return const Center(
              child: LeerHinweis(
                'Zu dieser Woche gibt es keinen Wochenplan: Sie wurde '
                'archiviert, bevor das Archiv den Plan mitgespeichert hat.',
                icon: Icons.calendar_view_week,
              ),
            );
          }
          final board = wochenboardAusArchiv(
            plan,
            stand: snap.createdAt,
            zusatzzeiten: daten.zusatzzeiten,
          );
          final aufgaben = <String, List<ArchivAufgabe>>{};
          for (final a in plan.aufgaben) {
            (aufgaben[_aufgabenSchluessel(a.abteilung, a.datum)] ??= [])
                .add(a);
          }
          return Column(
            children: [
              _ArchivLeiste(stand: snap.createdAt),
              Expanded(
                child: _ArchivRaster(board: board, aufgaben: aufgaben),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Schlüssel der sonstigen Aufgaben einer Zelle: Abteilung (dbValue) und
/// Tag.
String _aufgabenSchluessel(String abteilung, DateTime tag) =>
    '$abteilung|${tagOhneZeit(tag).toIso8601String()}';

/// „Mo 12.10.2026, 14:03 Uhr".
String _archivStandText(DateTime d) =>
    '${_fmtTagTitel(d)}, ${d.hour}:${d.minute.toString().padLeft(2, '0')} Uhr';

/// Eine Zeile Nebenzeit für den Hinweis beim Darüberfahren:
/// „Reinigen: 0:45 h · Allergenwechsel".
String _archivNebenzeitZeile(Zusatzzeit z) {
  final notiz = (z.notiz ?? '').trim();
  return '${_artName(z.art)}: ${Zeit.kurz(z.minuten)}'
      '${notiz.isEmpty ? '' : ' · $notiz'}';
}

/// Leiste über dem Raster: wann archiviert wurde, und die Schalter für
/// Größe und Dichte wie im Board.
class _ArchivLeiste extends ConsumerWidget {
  const _ArchivLeiste({required this.stand});

  final DateTime stand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final passend = ref.watch(boardPassendProvider);
    final kompakt = ref.watch(boardKompaktProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 16, color: grau),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Stand beim Archivieren: ${_archivStandText(stand)} — nur '
              'zum Ansehen',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: grau),
            ),
          ),
          IconButton(
            icon: Icon(passend ? Icons.zoom_out_map : Icons.fit_screen),
            tooltip: passend
                ? 'Originalgröße (scrollen)'
                : 'Passend skalieren (alles auf eine Seite)',
            onPressed: () =>
                ref.read(boardPassendProvider.notifier).state = !passend,
          ),
          IconButton(
            icon: Icon(kompakt ? Icons.unfold_more : Icons.unfold_less),
            tooltip: kompakt
                ? 'Komfort-Ansicht (mehr Details)'
                : 'Kompakt-Ansicht (ganzer Tag ohne Scrollen)',
            onPressed: () =>
                ref.read(boardKompaktProvider.notifier).state = !kompakt,
          ),
          const SizedBox(width: 4),
          const _Legende(),
        ],
      ),
    );
  }
}

/// Das Raster des archivierten Wochenplans: Kopfzeile mit den Tagen, je
/// Abteilung ihre Spuren und — falls es welche gab — die sonstigen
/// Aufgaben. Aufbau wie [_BoardGrid], ohne Ziehen und Abhaken.
class _ArchivRaster extends ConsumerWidget {
  const _ArchivRaster({required this.board, required this.aufgaben});

  final WeekBoard board;

  /// Sonstige Aufgaben je Zelle ([_aufgabenSchluessel]).
  final Map<String, List<ArchivAufgabe>> aufgaben;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kompakt = ref.watch(boardKompaktProvider);
    final passend = ref.watch(boardPassendProvider);
    final hatKarten = board.cells.values.any((c) => c.tasks.isNotEmpty);
    // Eine Aufgaben-Zeile nur für Abteilungen, die Aufgaben hatten — leer
    // bliebe sie im Archiv bloß eine Lücke.
    final mitAufgaben = {
      for (final liste in aufgaben.values)
        for (final a in liste) a.abteilung,
    };

    // Spuren nach Abteilung gruppieren (sie liegen bereits sortiert vor).
    final gruppen = <List<BoardSpur>>[];
    for (final spur in board.spuren) {
      if (gruppen.isEmpty ||
          gruppen.last.first.abteilung != spur.abteilung) {
        gruppen.add([spur]);
      } else {
        gruppen.last.add(spur);
      }
    }

    final reihen = <Widget>[];
    for (final gruppe in gruppen) {
      final abt = gruppe.first.abteilung;
      for (var i = 0; i < gruppe.length; i++) {
        reihen.add(
          _ArchivSpurZeile(
            board: board,
            spur: gruppe[i],
            ersteDerAbteilung: i == 0,
            kompakt: kompakt,
          ),
        );
      }
      if (mitAufgaben.contains(abt.dbValue)) {
        reihen.add(
          _ArchivAufgabenZeile(
            board: board,
            abteilung: abt,
            aufgaben: aufgaben,
            kompakt: kompakt,
          ),
        );
      }
    }

    final zeilen = Column(
      mainAxisSize: MainAxisSize.min,
      children: reihen,
    );

    if (!passend) {
      return Column(
        children: [
          _HeaderRow(tage: board.tage),
          if (!hatKarten) const _ArchivLeer(),
          Expanded(child: SingleChildScrollView(child: zeilen)),
        ],
      );
    }

    // „Passend" wie im Board: Kopfzeile und Spuren gemeinsam skalieren,
    // damit die Tage unter ihren Überschriften bleiben. scaleDown
    // vergrößert nie.
    return LayoutBuilder(
      builder: (context, c) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: c.maxWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _HeaderRow(tage: board.tage),
              if (!hatKarten) const _ArchivLeer(),
              zeilen,
            ],
          ),
        ),
      ),
    );
  }
}

/// Hinweis, wenn in der archivierten Woche nichts geplant war.
class _ArchivLeer extends StatelessWidget {
  const _ArchivLeer();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surface,
      child: const LeerHinweis(
        'In dieser Woche stand nichts im Plan.',
        icon: Icons.view_week_outlined,
      ),
    );
  }
}

/// Eine Spur des archivierten Plans: Beschriftung wie im Board, je Tag eine
/// Zelle.
class _ArchivSpurZeile extends StatelessWidget {
  const _ArchivSpurZeile({
    required this.board,
    required this.spur,
    required this.ersteDerAbteilung,
    required this.kompakt,
  });

  final WeekBoard board;
  final BoardSpur spur;
  final bool ersteDerAbteilung;
  final bool kompakt;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Beginn einer Abteilung: eine kräftigere Linie über die ganze
      // Breite — wie im Board.
      decoration: ersteDerAbteilung
          ? BoxDecoration(
              border: Border(
                top: BorderSide(color: _abteilungsTrenner(context)),
              ),
            )
          : null,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SpurLabel(spur: spur, ersteDerAbteilung: ersteDerAbteilung),
            for (final tag in board.tage)
              Expanded(
                child: _ArchivZelle(
                  board: board,
                  cell: board.cellFor(spur, tag),
                  kompakt: kompakt,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Eine Zelle des archivierten Plans: Auslastung, Nebenzeiten und die
/// Karten — dieselben Bausteine wie im Board, nur ohne Ziehen, Abhaken und
/// Öffnen.
class _ArchivZelle extends StatelessWidget {
  const _ArchivZelle({
    required this.board,
    required this.cell,
    required this.kompakt,
  });

  final WeekBoard board;
  final BoardCell cell;
  final bool kompakt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final belegt = cell.tasks.isNotEmpty || cell.zusatzzeiten.isNotEmpty;

    return Container(
      constraints: BoxConstraints(
        minHeight: belegt ? (kompakt ? 48 : 92) : (kompakt ? 30 : 56),
      ),
      padding: EdgeInsets.all(kompakt ? 4 : 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          right: BorderSide(color: theme.dividerColor),
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: !belegt
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _AuslastungsPille(
                        belegt: cell.belegtMinuten,
                        kapazitaet: cell.kapazitaetMinuten,
                        auslastung: cell.auslastung,
                        farbe: _ampelFarbe(context, cell.status),
                        status: cell.status,
                        kompakt: kompakt,
                      ),
                    ),
                    if (cell.zusatzzeiten.isNotEmpty)
                      _ArchivNebenzeit(eintraege: cell.zusatzzeiten),
                  ],
                ),
                SizedBox(height: kompakt ? 3 : 6),
                for (final task in cell.tasks)
                  Padding(
                    padding: EdgeInsets.only(bottom: kompakt ? 3 : 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Ohne Haken-Aktion: Der Haken zeigt nur, ob die
                        // Karte beim Archivieren erledigt war.
                        _KartenInhalt(task: task, kompakt: kompakt),
                        if (board.nachbarnFuer(task) != null)
                          _KettenMarker(nachbar: board.nachbarnFuer(task)!),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Die Nebenzeiten einer Zelle — wie der Knopf im Board, aber nur zum
/// Ansehen. Welche es waren, steht beim Darüberfahren.
class _ArchivNebenzeit extends StatelessWidget {
  const _ArchivNebenzeit({required this.eintraege});

  final List<Zusatzzeit> eintraege;

  @override
  Widget build(BuildContext context) {
    final farbe = Theme.of(context).colorScheme.primary;
    final minuten = eintraege.fold<double>(0, (s, z) => s + z.minuten);
    return Tooltip(
      message: [for (final z in eintraege) _archivNebenzeitZeile(z)]
          .join('\n'),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.more_time, size: 14, color: farbe),
            const SizedBox(width: 2),
            Text(
              Zeit.kurzOhneEinheit(minuten),
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: farbe,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Die sonstigen Aufgaben einer Abteilung im archivierten Plan —
/// Beschriftung wie im Board, je Tag eine Zelle.
class _ArchivAufgabenZeile extends StatelessWidget {
  const _ArchivAufgabenZeile({
    required this.board,
    required this.abteilung,
    required this.aufgaben,
    required this.kompakt,
  });

  final WeekBoard board;
  final Abteilung abteilung;
  final Map<String, List<ArchivAufgabe>> aufgaben;
  final bool kompakt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: _kLabelWidth,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                right: BorderSide(color: theme.dividerColor),
                bottom: BorderSide(color: theme.dividerColor),
              ),
            ),
            child: Row(
              children: [
                Container(width: 3, color: abteilung.farbe),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      14,
                      kompakt ? 2 : 5,
                      8,
                      kompakt ? 2 : 5,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.checklist_rounded, size: 14, color: grau),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            'Sonstige Aufgaben',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              fontStyle: FontStyle.italic,
                              height: 1.2,
                              color: grau,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final tag in board.tage)
            Expanded(
              child: _ArchivAufgabenZelle(
                eintraege:
                    aufgaben[_aufgabenSchluessel(abteilung.dbValue, tag)] ??
                        const [],
                kompakt: kompakt,
              ),
            ),
        ],
      ),
    );
  }
}

/// Die sonstigen Aufgaben einer Abteilung an einem Tag.
class _ArchivAufgabenZelle extends StatelessWidget {
  const _ArchivAufgabenZelle({required this.eintraege, required this.kompakt});

  final List<ArchivAufgabe> eintraege;
  final bool kompakt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: BoxConstraints(minHeight: kompakt ? 20 : 32),
      padding: kompakt
          ? const EdgeInsets.symmetric(horizontal: 3, vertical: 1)
          : const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          right: BorderSide(color: theme.dividerColor),
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < eintraege.length; i++)
            Padding(
              padding: EdgeInsets.only(
                top: i == 0 ? 0 : (kompakt ? 2 : 4),
              ),
              child: _ArchivAufgabe(aufgabe: eintraege[i], kompakt: kompakt),
            ),
        ],
      ),
    );
  }
}

/// Eine sonstige Aufgabe im archivierten Plan — erledigt grün wie die
/// Karten, offen weiß.
class _ArchivAufgabe extends StatelessWidget {
  const _ArchivAufgabe({required this.aufgabe, required this.kompakt});

  final ArchivAufgabe aufgabe;
  final bool kompakt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final erledigt = aufgabe.erledigt;
    return Container(
      padding: EdgeInsets.fromLTRB(0, kompakt ? 0 : 2, 6, kompakt ? 0 : 2),
      decoration: BoxDecoration(
        color: erledigt ? _erledigtFlaeche(context) : theme.colorScheme.surface,
        borderRadius: AppMasse.ecken,
        border: Border.all(
          color: erledigt ? _erledigtRahmen(context) : theme.dividerColor,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HakenKnopf(
            erledigt: erledigt ? Erledigt.abgehakt : null,
            onTap: null,
            groesse: kompakt ? 15 : 18,
          ),
          const SizedBox(width: 1),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: kompakt ? 3 : 4),
              child: Tooltip(
                message: aufgabe.inhalt,
                waitDuration: const Duration(milliseconds: 600),
                child: Text(
                  aufgabe.inhalt,
                  maxLines: kompakt ? 2 : 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: kompakt ? 11 : 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
