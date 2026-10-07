part of 'week_board_screen.dart';

// ---------------------------------------------------------------------------
// Sonstige Aufgaben je Abteilung und Tag
// ---------------------------------------------------------------------------
//
// Alles, was nicht aus der Planung eines Artikels entsteht — „Kessel
// entkalken", „Messer schleifen lassen". In der Woche hat jede Abteilung
// dafür unter ihren Anlagen eine eigene Zeile mit einem Feld je Tag; in der
// Tagesansicht stehen die Aufgaben in der Karte der Abteilung. Abhaken macht
// sie grün wie die Aufträge. Was liegen geblieben ist, ist orange umrandet
// und wandert per Ziehen auf einen anderen Tag — oder im Dialog auf den
// nächsten Arbeitstag.
//
// Die Helfer arbeiten über den ProviderContainer statt über `ref`: Nach dem
// Löschen oder Verschieben ist das Widget, das die Änderung auslöste, oft
// schon verschwunden — der Container nicht.

/// Was im Aufgaben-Dialog gewählt wurde.
enum _AufgabeAktion { speichern, loeschen, verschieben }

typedef _AufgabeErgebnis = ({_AufgabeAktion aktion, String inhalt});

/// Orange für liegen gebliebene Aufgaben.
const Color _kUeberfaelligFarbe = Color(0xFFEF6C00);

/// „Mi 7.10." — kurz genug für einen Knopf.
String _fmtTagKurz(DateTime d) =>
    '${_kWkShort[d.weekday - 1]} ${d.day}.${d.month}.';

/// Offen und ihr Tag ist vorbei.
bool _ueberfaellig(Tagesaufgabe a) =>
    !a.erledigt && tagOhneZeit(a.datum).isBefore(tagOhneZeit(DateTime.now()));

/// Wohin „Verschieben" eine liegen gebliebene Aufgabe legt: auf den
/// nächsten Arbeitstag nach ihrem Tag — liegt der schon in der
/// Vergangenheit, auf heute (am Wochenende auf den nächsten Arbeitstag).
DateTime _verschiebeZiel(DateTime tag) {
  final heute = tagOhneZeit(DateTime.now());
  final ziel = TagesaufgabenService.naechsterArbeitstag(tag);
  if (!ziel.isBefore(heute)) return ziel;
  return heute.weekday <= DateTime.friday
      ? heute
      : TagesaufgabenService.naechsterArbeitstag(heute);
}

/// Nach jeder Änderung: Backup anstoßen und die Aufgaben neu laden.
void _aufgabenGeaendert(ProviderContainer container, String grund) {
  container.read(autoBackupTriggerProvider).fireDebounced(reason: grund);
  container.invalidate(tagesaufgabenProvider);
}

Future<void> _aufgabeAnlegen(
  BuildContext context,
  Abteilung abteilung,
  DateTime tag,
) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final ergebnis = await showDialog<_AufgabeErgebnis>(
    context: context,
    builder: (_) => _AufgabeDialog(abteilung: abteilung, tag: tag),
  );
  if (ergebnis == null || ergebnis.aktion != _AufgabeAktion.speichern) return;
  await TagesaufgabenService.anlegen(
    container.read(databaseProvider),
    tag: tag,
    abteilung: abteilung.dbValue,
    inhalt: ergebnis.inhalt,
  );
  _aufgabenGeaendert(container, 'Aufgabe angelegt');
}

Future<void> _aufgabeBearbeiten(
  BuildContext context,
  Abteilung abteilung,
  Tagesaufgabe aufgabe,
) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.of(context);
  final ziel = _verschiebeZiel(aufgabe.datum);
  final ergebnis = await showDialog<_AufgabeErgebnis>(
    context: context,
    builder: (_) => _AufgabeDialog(
      abteilung: abteilung,
      tag: aufgabe.datum,
      vorhanden: aufgabe,
      verschiebeZiel: ziel,
    ),
  );
  if (ergebnis == null) return;
  final db = container.read(databaseProvider);

  if (ergebnis.aktion == _AufgabeAktion.loeschen) {
    await TagesaufgabenService.loeschen(db, aufgabe.id);
    _aufgabenGeaendert(container, 'Aufgabe gelöscht');
    // Die vorige Meldung weg, damit das Rückgängig zur letzten Löschung
    // sofort sichtbar ist.
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Aufgabe gelöscht'),
        duration: const Duration(seconds: 6),
        // Mit Aktion bliebe die Meldung sonst stehen, bis jemand klickt —
        // und sperrte jede weitere Meldung der App.
        persist: false,
        action: SnackBarAction(
          label: 'Rückgängig',
          onPressed: () async {
            await TagesaufgabenService.wiederherstellen(db, aufgabe.id);
            _aufgabenGeaendert(container, 'Aufgabe wiederhergestellt');
          },
        ),
      ),
    );
    return;
  }
  final textGeaendert = ergebnis.inhalt != aufgabe.inhalt;
  if (textGeaendert) {
    await TagesaufgabenService.aendern(db, aufgabe.id, inhalt: ergebnis.inhalt);
  }
  if (ergebnis.aktion == _AufgabeAktion.verschieben) {
    await TagesaufgabenService.verschieben(db, aufgabe.id, tag: ziel);
    _aufgabenGeaendert(container, 'Aufgabe verschoben');
    messenger.showSnackBar(
      SnackBar(content: Text('Aufgabe verschoben auf ${_fmtTagTitel(ziel)}')),
    );
    return;
  }
  if (textGeaendert) _aufgabenGeaendert(container, 'Aufgabe geändert');
}

Future<void> _aufgabeAbhaken(BuildContext context, Tagesaufgabe aufgabe) async {
  final container = ProviderScope.containerOf(context, listen: false);
  await TagesaufgabenService.abhaken(
    container.read(databaseProvider),
    aufgabe.id,
    erledigt: !aufgabe.erledigt,
  );
  _aufgabenGeaendert(
    container,
    aufgabe.erledigt ? 'Haken entfernt' : 'Aufgabe abgehakt',
  );
}

Future<void> _aufgabeVerschieben(
  BuildContext context,
  Tagesaufgabe aufgabe, {
  required DateTime tag,
  required Abteilung abteilung,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  await TagesaufgabenService.verschieben(
    container.read(databaseProvider),
    aufgabe.id,
    tag: tag,
    abteilung: abteilung.dbValue,
  );
  _aufgabenGeaendert(container, 'Aufgabe verschoben');
}

/// Die Zeile „Sonstige Aufgaben" einer Abteilung im Wochenboard — unter
/// ihren Anlagen, mit einem Feld je Tag. Bewusst flach, solange sie leer
/// ist: Im Modus „Passend" kostet jede Zeile Platz für das ganze Board.
class _AufgabenZeile extends StatelessWidget {
  const _AufgabenZeile({
    required this.board,
    required this.abteilung,
    required this.aufgaben,
    required this.kompakt,
  });

  final WeekBoard board;
  final Abteilung abteilung;
  final Map<AufgabenZelle, List<Tagesaufgabe>> aufgaben;
  final bool kompakt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final farbe = abteilung.farbe;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: _kLabelWidth,
            decoration: BoxDecoration(
              color: farbe.withValues(alpha: 0.04),
              border: Border(
                right: BorderSide(color: theme.dividerColor),
                bottom: BorderSide(color: theme.dividerColor),
              ),
            ),
            child: Row(
              children: [
                Container(width: 4, color: farbe),
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
                        Icon(
                          Icons.checklist_rounded,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            'Sonstige Aufgaben',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              fontStyle: FontStyle.italic,
                              height: 1.2,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.7),
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
              child: _AufgabenZelle(
                abteilung: abteilung,
                tag: tag,
                aufgaben: aufgaben[(abteilung.dbValue, tag)] ??
                    const <Tagesaufgabe>[],
                kompakt: kompakt,
              ),
            ),
        ],
      ),
    );
  }
}

/// Ein Feld der Aufgaben-Zeile: die Aufgaben einer Abteilung an einem Tag
/// und das + zum Eintragen. Nimmt per Ziehen Aufgaben anderer Tage an —
/// auch aus einer anderen Abteilung, falls eine falsch gelandet ist.
class _AufgabenZelle extends StatelessWidget {
  const _AufgabenZelle({
    required this.abteilung,
    required this.tag,
    required this.aufgaben,
    required this.kompakt,
  });

  final Abteilung abteilung;
  final DateTime tag;
  final List<Tagesaufgabe> aufgaben;
  final bool kompakt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final istHeute = tag == DateTime(now.year, now.month, now.day);

    return DragTarget<Tagesaufgabe>(
      onWillAcceptWithDetails: (details) {
        final a = details.data;
        return a.abteilung != abteilung.dbValue ||
            tagOhneZeit(a.datum) != tag;
      },
      onAcceptWithDetails: (details) => _aufgabeVerschieben(
        context,
        details.data,
        tag: tag,
        abteilung: abteilung,
      ),
      builder: (context, kandidaten, abgelehnt) {
        final highlight = kandidaten.isNotEmpty;
        return Container(
          constraints: BoxConstraints(minHeight: kompakt ? 20 : 32),
          padding: kompakt
              ? const EdgeInsets.symmetric(horizontal: 3, vertical: 1)
              : const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: highlight
                ? abteilung.farbe.withValues(alpha: 0.12)
                : istHeute
                    ? theme.colorScheme.primary.withValues(alpha: 0.04)
                    : null,
            border: Border(
              right: BorderSide(color: theme.dividerColor),
              bottom: BorderSide(color: theme.dividerColor),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < aufgaben.length; i++)
                      Padding(
                        padding: EdgeInsets.only(
                          top: i == 0 ? 0 : (kompakt ? 2 : 4),
                        ),
                        child: _AufgabeEintrag(
                          aufgabe: aufgaben[i],
                          abteilung: abteilung,
                          kompakt: kompakt,
                          ziehbar: true,
                        ),
                      ),
                    if (aufgaben.isEmpty && highlight)
                      Center(
                        child: Text(
                          'Hier ablegen',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: abteilung.farbe,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Tooltip(
                message: 'Aufgabe für ${abteilung.anzeigeName} eintragen',
                child: InkWell(
                  onTap: () => _aufgabeAnlegen(context, abteilung, tag),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      Icons.add_rounded,
                      size: 15,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Eine Aufgabe: Haken und Text. Antippen des Texts öffnet sie zum
/// Bearbeiten; in der Woche lässt sie sich auf einen anderen Tag ziehen.
class _AufgabeEintrag extends StatelessWidget {
  const _AufgabeEintrag({
    required this.aufgabe,
    required this.abteilung,
    required this.kompakt,
    this.ziehbar = false,
  });

  final Tagesaufgabe aufgabe;
  final Abteilung abteilung;
  final bool kompakt;
  final bool ziehbar;

  @override
  Widget build(BuildContext context) {
    final eintrag = _AufgabeInhalt(
      aufgabe: aufgabe,
      kompakt: kompakt,
      ziehbar: ziehbar,
      onHaken: () => _aufgabeAbhaken(context, aufgabe),
      onTap: () => _aufgabeBearbeiten(context, abteilung, aufgabe),
    );
    if (!ziehbar) return eintrag;
    return Draggable<Tagesaufgabe>(
      data: aufgabe,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 180,
          child: _AufgabeInhalt(aufgabe: aufgabe, kompakt: kompakt),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _AufgabeInhalt(aufgabe: aufgabe, kompakt: kompakt),
      ),
      child: eintrag,
    );
  }
}

/// Das Aussehen einer Aufgabe — offen weiß, erledigt grün wie die Karten,
/// liegen geblieben orange umrandet.
class _AufgabeInhalt extends StatelessWidget {
  const _AufgabeInhalt({
    required this.aufgabe,
    required this.kompakt,
    this.ziehbar = true,
    this.onHaken,
    this.onTap,
  });

  final Tagesaufgabe aufgabe;
  final bool kompakt;

  /// Lässt sich auf einen anderen Tag ziehen (nur in der Woche) — steuert
  /// den Hinweis bei Liegengebliebenem.
  final bool ziehbar;

  /// null: nur anzeigen (beim Ziehen).
  final VoidCallback? onHaken;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final erledigt = aufgabe.erledigt;
    final ueberfaellig = _ueberfaellig(aufgabe);
    final rahmen = erledigt
        ? _kErledigtFarbe.withValues(alpha: 0.75)
        : ueberfaellig
            ? _kUeberfaelligFarbe
            : theme.dividerColor;
    // Der ganze Text beim Darüberfahren — im Raster wird er gekürzt. Bei
    // Liegengebliebenem steht dabei, seit wann.
    final hinweis = !ueberfaellig
        ? aufgabe.inhalt
        : '${aufgabe.inhalt}\n'
            'Seit ${_fmtTagTitel(aufgabe.datum)} offen — '
            '${ziehbar ? 'auf einen anderen Tag ziehen oder ' : ''}'
            'öffnen und verschieben';

    // Material statt Container: Auf der eingefärbten Fläche wäre die
    // Tipp-Welle sonst unsichtbar.
    return Material(
      color:
          erledigt ? _erledigtHintergrund(theme) : theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: rahmen, width: ueberfaellig ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(0, kompakt ? 0 : 2, 6, kompakt ? 0 : 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HakenKnopf(
                erledigt: erledigt ? Erledigt.abgehakt : null,
                onTap: onHaken,
                groesse: kompakt ? 15 : 18,
              ),
              const SizedBox(width: 1),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: kompakt ? 3 : 4),
                  child: Tooltip(
                    message: hinweis,
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
        ),
      ),
    );
  }
}

/// Die sonstigen Aufgaben einer Abteilung in ihrer Karte der
/// Tagesansicht.
class _AufgabenAbschnitt extends StatelessWidget {
  const _AufgabenAbschnitt({
    required this.abteilung,
    required this.aufgaben,
    required this.mitAbteilung,
  });

  final Abteilung abteilung;
  final List<Tagesaufgabe> aufgaben;

  /// Abteilungsname in der Überschrift — wenn die Karte nach einer Anlage
  /// heißt, sonst wäre unklar, wem die Aufgaben gehören.
  final bool mitAbteilung;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final offen = aufgaben.where((a) => !a.erledigt).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.checklist_rounded,
              size: 15,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                mitAbteilung
                    ? 'Sonstige Aufgaben · ${abteilung.anzeigeName}'
                    : 'Sonstige Aufgaben',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              offen == 0 ? 'alles erledigt' : '$offen offen',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: offen == 0
                    ? _kErledigtFarbe
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        for (final a in aufgaben)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: _AufgabeEintrag(
              aufgabe: a,
              abteilung: abteilung,
              kompakt: false,
            ),
          ),
      ],
    );
  }
}

/// Eintragen oder Bearbeiten einer Aufgabe. Beim Bearbeiten sitzt das
/// Löschen oben rechts, und eine liegen gebliebene Aufgabe lässt sich auf
/// den nächsten Arbeitstag schieben.
class _AufgabeDialog extends StatefulWidget {
  const _AufgabeDialog({
    required this.abteilung,
    required this.tag,
    this.vorhanden,
    this.verschiebeZiel,
  });

  final Abteilung abteilung;
  final DateTime tag;

  /// null: neue Aufgabe.
  final Tagesaufgabe? vorhanden;

  /// Tag für „Verschieben" — nur beim Bearbeiten.
  final DateTime? verschiebeZiel;

  @override
  State<_AufgabeDialog> createState() => _AufgabeDialogState();
}

class _AufgabeDialogState extends State<_AufgabeDialog> {
  late final TextEditingController _text =
      TextEditingController(text: widget.vorhanden?.inhalt ?? '');

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _gueltig => _text.text.trim().isNotEmpty;

  void _schliesse(_AufgabeAktion aktion) {
    if (aktion != _AufgabeAktion.loeschen && !_gueltig) return;
    Navigator.of(context).pop<_AufgabeErgebnis>(
      (aktion: aktion, inhalt: _text.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vorhanden = widget.vorhanden;
    final ziel = widget.verschiebeZiel;
    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(
              vorhanden == null ? 'Sonstige Aufgabe' : 'Aufgabe bearbeiten',
            ),
          ),
          if (vorhanden != null)
            IconButton(
              tooltip: 'Löschen',
              icon: Icon(
                Icons.delete_outline,
                color: theme.colorScheme.error,
              ),
              onPressed: () => _schliesse(_AufgabeAktion.loeschen),
            ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.abteilung.anzeigeName} · '
              '${_fmtTagTitel(widget.tag)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'z.B. Kessel entkalken, Messer schleifen lassen',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _schliesse(_AufgabeAktion.speichern),
            ),
          ],
        ),
      ),
      actions: [
        // Liegen geblieben: ein Klick auf den nächsten Arbeitstag.
        if (vorhanden != null && !vorhanden.erledigt && ziel != null)
          TextButton.icon(
            onPressed: _gueltig
                ? () => _schliesse(_AufgabeAktion.verschieben)
                : null,
            icon: const Icon(Icons.redo_rounded, size: 18),
            label: Text('Auf ${_fmtTagKurz(ziel)} verschieben'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed:
              _gueltig ? () => _schliesse(_AufgabeAktion.speichern) : null,
          child: Text(vorhanden == null ? 'Eintragen' : 'Speichern'),
        ),
      ],
    );
  }
}
