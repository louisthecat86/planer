import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart' show Tagesaufgabe;
import '../../core/druck/druck_optionen.dart';
import '../../core/services/tagesaufgaben_service.dart' show AufgabenZelle;
import '../../core/utils/format.dart';
import '../../core/utils/kalenderwoche.dart';
import 'board_print_service.dart';
import 'board_providers.dart';

// Druck des Planungsboards: Woche oder Tag, gesamte Übersicht oder je
// Abteilung ein eigenes Blatt — dazu, welche Abteilungen, welche Tage und
// was auf dem Plan stehen soll. Das Druckfenster zeigt die Wahl gleich in
// der Vorschau.

/// Was gedruckt wird.
enum DruckZeitraum { woche, tag }

/// Wie viel eine Abteilung im Zeitraum zu tun hat — Aufträge (Karten im
/// Board) und sonstige Aufgaben.
typedef DruckUmfang = ({int auftraege, int aufgaben});

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

/// „3 Aufträge · 1 Aufgabe" — oder „nichts geplant".
String druckUmfangText(DruckUmfang? u) {
  if (u == null || u.auftraege + u.aufgaben == 0) return 'nichts geplant';
  return [
    if (u.auftraege > 0)
      '${u.auftraege} ${u.auftraege == 1 ? 'Auftrag' : 'Aufträge'}',
    if (u.aufgaben > 0)
      '${u.aufgaben} ${u.aufgaben == 1 ? 'Aufgabe' : 'Aufgaben'}',
  ].join(' · ');
}

/// Schlüssel der Wahl im Druckfenster.
abstract final class PlanDruckWahl {
  static const zeitraum = 'zeitraum';
  static const umfang = 'umfang';
  static const abteilungenWoche = 'abteilungenWoche';
  static const abteilungenTag = 'abteilungenTag';
  static const tage = 'tage';
  static const aufgaben = 'aufgaben';
  static const erledigte = 'erledigte';
  static const kaestchen = 'kaestchen';
  static const leere = 'leere';
  static const belegung = 'belegung';
}

/// Der Druck des Plans für das Druckfenster.
///
/// [zeitraum] ist vorgewählt — der, den das Board gerade zeigt. Die
/// Abteilungen sind je Zeitraum vorgeschlagen: die, die dort etwas zu
/// tun haben. Sie hängen an den Daten und werden deshalb nicht gemerkt;
/// alles andere schon.
DruckAuftrag planDruckAuftrag({
  required WeekBoard woche,
  required DayBoard tag,
  required Map<AufgabenZelle, List<Tagesaufgabe>> aufgaben,
  required DruckZeitraum zeitraum,
  DateTime? gedrucktAm,
}) {
  final kw = isoKalenderwoche(woche.wochenStart);
  final umfangWoche = druckUmfangWoche(woche, aufgaben);
  final umfangTag = druckUmfangTag(tag, aufgaben);

  List<DruckWert> abteilungen(Map<Abteilung, DruckUmfang> umfang) => [
        for (final abt in Abteilung.values)
          DruckWert(
            abt.dbValue,
            abt.anzeigeName,
            hinweis: druckUmfangText(umfang[abt]),
            farbe: abt.farbwert,
            kuerzel: abt.kurzcode,
          ),
      ];

  // Vorgeschlagen: alle mit Plan — ist nirgends etwas geplant, alle.
  Set<String> vorschlag(Map<Abteilung, DruckUmfang> umfang) {
    final mitPlan = {
      for (final abt in Abteilung.values)
        if (druckUmfangText(umfang[abt]) != 'nichts geplant') abt.dbValue,
    };
    return mitPlan.isNotEmpty
        ? mitPlan
        : {for (final abt in Abteilung.values) abt.dbValue};
  }

  bool istWoche(DruckWahl w) =>
      w.eins(PlanDruckWahl.zeitraum) != DruckZeitraum.tag.name;

  return DruckAuftrag(
    art: 'plan',
    titel: 'Plan drucken',
    untertitel: 'Planungsboard · KW $kw',
    optionen: [
      DruckWahlEins(
        schluessel: PlanDruckWahl.zeitraum,
        titel: 'Zeitraum',
        werte: [
          DruckWert(
            DruckZeitraum.woche.name,
            'Woche · KW $kw',
            hinweis: '${Format.tagKurz(woche.tage.first)} bis '
                '${Format.tagKurz(woche.tage.last)} — im Querformat',
          ),
          DruckWert(
            DruckZeitraum.tag.name,
            'Tag · ${Format.tagKurz(tag.tag)}',
            hinweis: 'Mit Tabelle je Anlage — im Hochformat',
          ),
        ],
        standard: zeitraum.name,
        merken: false,
      ),
      const DruckWahlEins(
        schluessel: PlanDruckWahl.umfang,
        titel: 'Aufteilung',
        werte: [
          DruckWert(
            'uebersicht',
            'Gesamte Übersicht',
            hinweis: 'Alle gewählten Abteilungen auf einem Plan',
          ),
          DruckWert(
            'einzeln',
            'Einzelne Abteilungen',
            hinweis: 'Jede auf einem eigenen Blatt — zum Verteilen',
          ),
        ],
        standard: 'uebersicht',
      ),
      DruckWahlMehrere(
        schluessel: PlanDruckWahl.abteilungenWoche,
        titel: 'Abteilungen',
        werte: abteilungen(umfangWoche),
        standard: vorschlag(umfangWoche),
        merken: false,
        sichtbar: istWoche,
      ),
      DruckWahlMehrere(
        schluessel: PlanDruckWahl.abteilungenTag,
        titel: 'Abteilungen',
        werte: abteilungen(umfangTag),
        standard: vorschlag(umfangTag),
        merken: false,
        sichtbar: (w) => !istWoche(w),
      ),
      DruckWahlMehrere(
        schluessel: PlanDruckWahl.tage,
        titel: 'Tage',
        werte: [
          for (final t in woche.tage)
            DruckWert('${t.weekday}', Format.tagKurz(t)),
        ],
        standard: {for (final t in woche.tage) '${t.weekday}'},
        sichtbar: istWoche,
      ),
      const DruckSchalter(
        schluessel: PlanDruckWahl.aufgaben,
        titel: 'Sonstige Aufgaben',
        gruppe: 'Auf dem Plan',
      ),
      const DruckSchalter(
        schluessel: PlanDruckWahl.erledigte,
        titel: 'Erledigtes',
        hinweis: 'Grau, mit Haken',
        gruppe: 'Auf dem Plan',
      ),
      const DruckSchalter(
        schluessel: PlanDruckWahl.kaestchen,
        titel: 'Kästchen zum Abhaken',
        gruppe: 'Auf dem Plan',
      ),
      const DruckSchalter(
        schluessel: PlanDruckWahl.leere,
        titel: 'Anlagen ohne Aufträge',
        hinweis: 'Als leere Zeilen — zum Nachtragen von Hand',
        gruppe: 'Auf dem Plan',
      ),
      DruckSchalter(
        schluessel: PlanDruckWahl.belegung,
        titel: 'Dauer und Belegung',
        gruppe: 'Auf dem Plan',
        sichtbar: (w) => !istWoche(w),
      ),
    ],
    bauen: (wahl) {
      final alsWoche = istWoche(wahl);
      final gewaehlt = wahl.mehrere(
        alsWoche
            ? PlanDruckWahl.abteilungenWoche
            : PlanDruckWahl.abteilungenTag,
      );
      if (gewaehlt.isEmpty) {
        throw const DruckNichtsGewaehlt('Wähle mindestens eine Abteilung.');
      }
      final wochentage = {
        for (final t in wahl.mehrere(PlanDruckWahl.tage))
          if (int.tryParse(t) case final nr?) nr,
      };
      if (alsWoche && wochentage.isEmpty) {
        throw const DruckNichtsGewaehlt('Wähle mindestens einen Tag.');
      }
      final inhalt = PlanDruckInhalt(
        abteilungen: {
          for (final abt in Abteilung.values)
            if (gewaehlt.contains(abt.dbValue)) abt,
        },
        einzeln: wahl.eins(PlanDruckWahl.umfang) == 'einzeln',
        wochentage: alsWoche ? wochentage : null,
        aufgaben: wahl.an(PlanDruckWahl.aufgaben),
        erledigte: wahl.an(PlanDruckWahl.erledigte),
        kaestchen: wahl.an(PlanDruckWahl.kaestchen),
        leereSpuren: wahl.an(PlanDruckWahl.leere),
        belegung: wahl.an(PlanDruckWahl.belegung),
      );
      return alsWoche
          ? BoardPrintService.wochenDruck(
              woche,
              aufgaben: aufgaben,
              inhalt: inhalt,
              gedrucktAm: gedrucktAm,
            )
          : BoardPrintService.tagesDruck(
              tag,
              aufgaben: aufgaben,
              inhalt: inhalt,
              gedrucktAm: gedrucktAm,
            );
    },
  );
}
