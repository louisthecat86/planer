import 'package:flutter/material.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart' show Tagesaufgabe;
import '../../core/services/tagesaufgaben_service.dart' show AufgabenZelle;
import '../../core/ui/bausteine.dart' show AbteilungsMarke;
import 'board_providers.dart';

// Druck-Auswahl im Planungsboard: Woche oder Tag, gesamte Übersicht oder
// je Abteilung ein eigenes Blatt — damit sich der Plan gezielt an die
// Abteilungen verteilen lässt.

/// Was gedruckt wird.
enum DruckZeitraum { woche, tag }

/// Wie viel eine Abteilung im Zeitraum zu tun hat — Aufträge (Karten im
/// Board) und sonstige Aufgaben.
typedef DruckUmfang = ({int auftraege, int aufgaben});

/// Die Wahl im Druck-Dialog.
class BoardDruckAuswahl {
  const BoardDruckAuswahl({required this.zeitraum, this.abteilungen});

  final DruckZeitraum zeitraum;

  /// null: die gesamte Übersicht, alle Abteilungen auf einem Plan. Sonst
  /// diese Abteilungen, jede auf einem eigenen Blatt — in der Reihenfolge
  /// des Boards.
  final List<Abteilung>? abteilungen;
}

/// Aufträge und sonstige Aufgaben je Abteilung in der Woche (Mo–Fr).
Map<Abteilung, DruckUmfang> druckUmfangWoche(
  WeekBoard board,
  Map<AufgabenZelle, List<Tagesaufgabe>> aufgaben,
) {
  final auftraege = <Abteilung, int>{};
  for (final spur in board.spuren) {
    for (final tag in board.tage) {
      auftraege[spur.abteilung] = (auftraege[spur.abteilung] ?? 0) +
          board.cellFor(spur, tag).tasks.length;
    }
  }
  return {
    for (final abt in Abteilung.values)
      abt: (
        auftraege: auftraege[abt] ?? 0,
        aufgaben: board.tage.fold<int>(
          0,
          (n, tag) => n + (aufgaben[(abt.dbValue, tag)]?.length ?? 0),
        ),
      ),
  };
}

/// Aufträge und sonstige Aufgaben je Abteilung an einem Tag.
Map<Abteilung, DruckUmfang> druckUmfangTag(
  DayBoard board,
  Map<AufgabenZelle, List<Tagesaufgabe>> aufgaben,
) {
  final auftraege = <Abteilung, int>{};
  for (final lane in board.lanes) {
    auftraege[lane.abteilung] =
        (auftraege[lane.abteilung] ?? 0) + lane.tasks.length;
  }
  return {
    for (final abt in Abteilung.values)
      abt: (
        auftraege: auftraege[abt] ?? 0,
        aufgaben: aufgaben[(abt.dbValue, board.tag)]?.length ?? 0,
      ),
  };
}

/// Fragt, was gedruckt wird. null: abgebrochen.
///
/// [zeitraum] ist vorgewählt — der, den das Board gerade zeigt. [woche]
/// und [tag] beschriften die Wahl („KW 41", „Do 08.10.").
Future<BoardDruckAuswahl?> zeigeBoardDruckDialog(
  BuildContext context, {
  required DruckZeitraum zeitraum,
  required String woche,
  required String tag,
  required Map<Abteilung, DruckUmfang> umfangWoche,
  required Map<Abteilung, DruckUmfang> umfangTag,
}) {
  return showDialog<BoardDruckAuswahl>(
    context: context,
    builder: (_) => BoardDruckDialog(
      zeitraum: zeitraum,
      woche: woche,
      tag: tag,
      umfangWoche: umfangWoche,
      umfangTag: umfangTag,
    ),
  );
}

/// Der Dialog zu [zeigeBoardDruckDialog].
class BoardDruckDialog extends StatefulWidget {
  const BoardDruckDialog({
    super.key,
    required this.zeitraum,
    required this.woche,
    required this.tag,
    required this.umfangWoche,
    required this.umfangTag,
  });

  final DruckZeitraum zeitraum;
  final String woche;
  final String tag;
  final Map<Abteilung, DruckUmfang> umfangWoche;
  final Map<Abteilung, DruckUmfang> umfangTag;

  @override
  State<BoardDruckDialog> createState() => _BoardDruckDialogState();
}

class _BoardDruckDialogState extends State<BoardDruckDialog> {
  late DruckZeitraum _zeitraum = widget.zeitraum;

  /// Je Abteilung ein eigenes Blatt statt der gesamten Übersicht.
  bool _einzeln = false;

  /// Von Hand gewählte Abteilungen. null, solange niemand etwas
  /// angeklickt hat oder der Zeitraum gewechselt wurde — dann gilt der
  /// Vorschlag: alle Abteilungen, die im Zeitraum etwas zu tun haben.
  Set<Abteilung>? _auswahl;

  Map<Abteilung, DruckUmfang> get _umfang =>
      _zeitraum == DruckZeitraum.woche ? widget.umfangWoche : widget.umfangTag;

  bool _hatPlan(Abteilung abt) {
    final u = _umfang[abt];
    return u != null && u.auftraege + u.aufgaben > 0;
  }

  Set<Abteilung> get _gewaehlt =>
      _auswahl ??
      {
        for (final abt in Abteilung.values)
          if (_hatPlan(abt)) abt,
      };

  void _waehle(Set<Abteilung> neu) => setState(() => _auswahl = neu);

  void _drucken() {
    final gewaehlt = _gewaehlt;
    Navigator.of(context).pop(
      BoardDruckAuswahl(
        zeitraum: _zeitraum,
        abteilungen: _einzeln
            ? [
                for (final abt in Abteilung.values)
                  if (gewaehlt.contains(abt)) abt,
              ]
            : null,
      ),
    );
  }

  static String _umfangText(DruckUmfang? u) {
    if (u == null || u.auftraege + u.aufgaben == 0) return 'nichts geplant';
    return [
      if (u.auftraege > 0)
        '${u.auftraege} ${u.auftraege == 1 ? 'Auftrag' : 'Aufträge'}',
      if (u.aufgaben > 0)
        '${u.aufgaben} ${u.aufgaben == 1 ? 'Aufgabe' : 'Aufgaben'}',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gewaehlt = _gewaehlt;
    final anzahl = gewaehlt.length;

    return AlertDialog(
      title: const Text('Plan drucken'),
      // Bei kleinem Fenster lässt sich die Liste der Abteilungen scrollen.
      scrollable: true,
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<DruckZeitraum>(
              segments: [
                ButtonSegment(
                  value: DruckZeitraum.woche,
                  icon: const Icon(Icons.calendar_view_week),
                  label: Text('Woche · ${widget.woche}'),
                ),
                ButtonSegment(
                  value: DruckZeitraum.tag,
                  icon: const Icon(Icons.calendar_view_day),
                  label: Text('Tag · ${widget.tag}'),
                ),
              ],
              selected: {_zeitraum},
              // Woche und Tag haben verschiedene Vorschläge — eine von Hand
              // getroffene Auswahl gilt nur für den Zeitraum, in dem sie
              // entstand.
              onSelectionChanged: (s) => setState(() {
                _zeitraum = s.first;
                _auswahl = null;
              }),
            ),
            const SizedBox(height: 8),
            RadioGroup<bool>(
              groupValue: _einzeln,
              onChanged: (v) => setState(() => _einzeln = v ?? false),
              child: const Column(
                children: [
                  RadioListTile<bool>(
                    value: false,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Gesamte Übersicht'),
                    subtitle: Text('Alle Abteilungen auf einem Plan'),
                  ),
                  RadioListTile<bool>(
                    value: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Einzelne Abteilungen'),
                    subtitle: Text(
                      'Jede Abteilung auf einem eigenen Blatt — zum Verteilen',
                    ),
                  ),
                ],
              ),
            ),
            if (_einzeln) ...[
              const Divider(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Welche Abteilungen?',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () => _waehle(Abteilung.values.toSet()),
                    child: const Text('Alle'),
                  ),
                  TextButton(
                    onPressed: () => _waehle(<Abteilung>{}),
                    child: const Text('Keine'),
                  ),
                ],
              ),
              for (final abt in Abteilung.values)
                CheckboxListTile(
                  value: gewaehlt.contains(abt),
                  onChanged: (an) {
                    final neu = {...gewaehlt};
                    if (an ?? false) {
                      neu.add(abt);
                    } else {
                      neu.remove(abt);
                    }
                    _waehle(neu);
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  secondary: AbteilungsMarke(abteilung: abt),
                  title: Text(abt.anzeigeName),
                  subtitle: Text(_umfangText(_umfang[abt])),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton.icon(
          onPressed: _einzeln && anzahl == 0 ? null : _drucken,
          icon: const Icon(Icons.print),
          label: Text(
            !_einzeln
                ? 'Drucken'
                : anzahl == 1
                    ? 'Drucken · 1 Abteilung'
                    : 'Drucken · $anzahl Abteilungen',
          ),
        ),
      ],
    );
  }
}
