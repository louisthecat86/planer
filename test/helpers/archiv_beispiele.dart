// Erfundene archivierte Wochen für die Tests der Ausdrucke von Archiv und
// Auswertung — keine echten Artikel, Kunden oder Mengen.
import 'dart:convert';

import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/erledigt_service.dart';
import 'package:produktion_planer/core/services/week_snapshot_service.dart';
import 'package:produktion_planer/core/utils/datum.dart';

/// Montag der Beispielwoche (KW 44/2026).
final DateTime bspMontag = DateTime(2026, 10, 26);

/// Wann die Beispielwoche archiviert wurde.
final DateTime bspArchiviert = DateTime(2026, 10, 30, 14, 3);

const String _zerlegung = 'zerlegung';
const String _brat = 'bratstrasse';
const String _verpackung = 'verpackung';

/// Die Spuren des Boards: Zerlegung ohne Anlagen, eine Bratstraße und
/// zwei Anlagen der Verpackung.
const List<ArchivSpur> bspSpuren = [
  ArchivSpur(abteilung: _zerlegung, kapazitaetMinuten: 600),
  ArchivSpur(
    abteilung: _brat,
    maschineId: 'm-brat',
    maschineName: 'Bratlinie Nord',
    kapazitaetMinuten: 480,
  ),
  ArchivSpur(
    abteilung: _verpackung,
    maschineId: 'm-va',
    maschineName: 'Packanlage A',
    kapazitaetMinuten: 480,
  ),
  ArchivSpur(
    abteilung: _verpackung,
    maschineId: 'm-vb',
    maschineName: 'Packanlage B',
    kapazitaetMinuten: 480,
  ),
];

/// Ein Auftrag der Woche: Abteilung, Spur, Tag (0 = Montag), Artikel.
typedef _Auftrag = ({
  String abteilung,
  String spur,
  int tag,
  String nummer,
  String name,
  double kg,
  double minuten,
  String start,
  bool erledigt,
  String? notiz,
});

/// Die Anlage, auf der eine Abteilung ohne Angabe plant.
const Map<String, String> _anlage = {_brat: 'm-brat', _verpackung: 'm-va'};

_Auftrag _a(
  String abteilung,
  int tag,
  String nummer,
  String name,
  double kg,
  double minuten, {
  String? anlage,
  String start = '06:00',
  bool erledigt = false,
  String? notiz,
}) =>
    (
      abteilung: abteilung,
      spur: '$abteilung|${anlage ?? _anlage[abteilung] ?? ''}',
      tag: tag,
      nummer: nummer,
      name: name,
      kg: kg,
      minuten: minuten,
      start: start,
      erledigt: erledigt,
      notiz: notiz,
    );

final List<_Auftrag> _auftraege = [
  _a(
    _zerlegung,
    0,
    '7101',
    'Schweineschulter zerlegt',
    1800,
    420,
    erledigt: true,
  ),
  _a(_zerlegung, 1, '7102', 'Rinderkeule zerlegt', 950, 300, erledigt: true),
  _a(
    _zerlegung,
    3,
    '7101',
    'Schweineschulter zerlegt',
    2100,
    540,
    start: '05:30',
    notiz: 'Lieferung kam später',
  ),
  _a(_brat, 0, '7201', 'Gartenwurst gebraten', 1200, 360, erledigt: true),
  _a(_brat, 1, '7202', 'Frikadellen klein', 800, 300, erledigt: true),
  _a(
    _brat,
    1,
    '7203',
    'Hackbällchen',
    400,
    240,
    start: '12:00',
    erledigt: true,
  ),
  _a(_brat, 2, '7201', 'Gartenwurst gebraten', 1500, 420),
  _a(_brat, 3, '7204', 'Bratwurst mild', 1100, 330),
  _a(
    _verpackung,
    0,
    '7301',
    'Gartenwurst 6er Schale',
    900,
    240,
    erledigt: true,
  ),
  _a(_verpackung, 2, '7302', 'Frikadellen Beutel', 700, 300, anlage: 'm-vb'),
  _a(_verpackung, 4, '7301', 'Gartenwurst 6er Schale', 1300, 360),
];

/// Der Plan, wie er beim Archivieren im Board stand.
ArchivPlan bspArchivPlan() => ArchivPlan(
      tage: [for (var i = 0; i < 5; i++) tagPlus(bspMontag, i)],
      spuren: bspSpuren,
      karten: [
        for (final (i, a) in _auftraege.indexed)
          ArchivKarte(
            spurId: a.spur,
            abteilung: a.abteilung,
            datum: tagPlus(bspMontag, a.tag),
            productId: 'p-${a.nummer}',
            productName: a.name,
            artikelnummer: a.nummer,
            startZeit: a.start,
            dauerMinuten: a.minuten,
            mengeKg: a.kg,
            sortierung: i,
            kettenId: 'kette-$i',
            erledigt: a.erledigt ? Erledigt.abgehakt : null,
          ),
      ],
      aufgaben: [
        ArchivAufgabe(
          abteilung: _verpackung,
          datum: tagPlus(bspMontag, 1),
          inhalt: 'Etiketten nachbestellen',
          erledigt: true,
        ),
        ArchivAufgabe(
          abteilung: _zerlegung,
          datum: tagPlus(bspMontag, 3),
          inhalt: 'Messer schleifen lassen',
        ),
      ],
    );

/// Die eingefrorenen Daten der Beispielwoche — mit Plan, wenn [mitPlan].
WochenSnapshotDaten bspWochenDaten({bool mitPlan = true}) =>
    WochenSnapshotDaten(
      tasks: [
        for (final a in _auftraege)
          SnapshotTask(
            abteilung: a.abteilung,
            productId: 'p-${a.nummer}',
            productName: a.name,
            datum: tagPlus(bspMontag, a.tag),
            dauerMinuten: a.minuten,
            mitarbeiter: a.abteilung == _zerlegung ? 4 : 2,
            mengeKg: a.kg,
            startZeit: a.start,
            notizen: a.notiz,
          ),
      ],
      kapazitaeten: const {
        _zerlegung: 600,
        _brat: 480,
        _verpackung: 960,
      },
      zusatzzeiten: [
        SnapshotZusatzzeit(
          datum: tagPlus(bspMontag, 1),
          spurId: 'bratstrasse|m-brat',
          art: 'reinigen',
          minuten: 45,
          notiz: 'Allergenwechsel',
        ),
        SnapshotZusatzzeit(
          datum: tagPlus(bspMontag, 2),
          spurId: 'verpackung|m-vb',
          art: 'ruesten',
          minuten: 30,
        ),
      ],
      plan: mitPlan ? bspArchivPlan() : null,
    );

/// Eine archivierte Woche wie in der Datenbank — [wochen] Wochen vor der
/// Beispielwoche, mit [notiz].
WeekSnapshot bspSnapshot({
  int wochen = 0,
  String? notiz,
  bool mitPlan = true,
}) {
  final montag = tagPlus(bspMontag, -7 * wochen);
  return WeekSnapshot(
    id: 'snap-$wochen',
    wochenStart: montag,
    kw: 44 - wochen,
    jahr: 2026,
    notiz: notiz,
    datenJson: jsonEncode(bspWochenDaten(mitPlan: mitPlan).toJson()),
    createdAt: wochen == 0 ? bspArchiviert : tagPlus(montag, 4),
    updatedAt: wochen == 0 ? bspArchiviert : tagPlus(montag, 4),
  );
}
