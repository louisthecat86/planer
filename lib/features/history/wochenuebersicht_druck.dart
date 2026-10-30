import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart' show WeekSnapshot;
import '../../core/druck/druck_bausteine.dart';
import '../../core/druck/druck_optionen.dart';
import '../../core/druck/druck_satz.dart';
import '../../core/services/week_snapshot_service.dart';
import '../../core/utils/datum.dart';
import '../../core/utils/format.dart';
import '../../core/utils/pdf_text.dart';
import '../../core/utils/zeit.dart';
import 'wochenauswertung_druck.dart' show AbteilungsWoche, abteilungsWochen;

// Die archivierten Wochen im Überblick: je Woche Aufträge, Menge, belegte
// Zeit und die Auslastung je Abteilung — dazu die Erkenntnisse. Für den
// Monat im Kalender oder die letzten Wochen.

/// Schlüssel der Wahl im Druckfenster.
abstract final class WochenuebersichtWahl {
  static const wochen = 'wochen';
  static const abteilungen = 'abteilungen';
  static const erkenntnisse = 'erkenntnisse';
}

/// Was in den Überblick kommt — die Wahl im Druckfenster.
class WochenuebersichtInhalt {
  const WochenuebersichtInhalt({
    this.abteilungen = true,
    this.erkenntnisse = true,
  });

  /// Die Auslastung je Abteilung als Spalten.
  final bool abteilungen;

  /// Die Erkenntnisse der Wochen unter der Tabelle.
  final bool erkenntnisse;
}

/// Eine Woche im Überblick — aus dem Snapshot gerechnet.
class UebersichtWoche {
  UebersichtWoche(this.snap) : daten = dekodiereSnapshot(snap);

  final WeekSnapshot snap;
  final WochenSnapshotDaten daten;

  late final List<AbteilungsWoche> abteilungen = abteilungsWochen(daten);

  double get kg => daten.tasks.fold(0.0, (s, t) => s + t.mengeKg);
  double get belegtMinuten => daten.gesamtBelegtMinuten;

  /// Belegt und Kapazität der Abteilungen mit Kapazität.
  (double, double) get _mitKapazitaet {
    var belegt = 0.0;
    var kap = 0.0;
    for (final a in abteilungen) {
      if (a.kapazitaetMinuten <= 0) continue;
      belegt += a.belegtMinuten;
      kap += a.kapazitaetMinuten;
    }
    return (belegt, kap);
  }

  /// Die Auslastung aller Abteilungen zusammen — null ohne Kapazität.
  double? get auslastung {
    final (belegt, kap) = _mitKapazitaet;
    return kap > 0 ? belegt / kap : null;
  }

  /// Die Auslastung von [abteilung] — null ohne Belegung oder Kapazität.
  double? auslastungVon(Abteilung abteilung) {
    for (final a in abteilungen) {
      if (a.abteilung == abteilung && a.kapazitaetMinuten > 0) {
        return a.belegtMinuten / a.kapazitaetMinuten;
      }
    }
    return null;
  }
}

/// „KW 44 · 26.10.–01.11."
String _zeitraum(WeekSnapshot s) => '${Format.datumKurz(s.wochenStart)}–'
    '${Format.datumKurz(tagPlus(s.wochenStart, 6))}';

/// Die Wochen [snaps] im Überblick zum Drucken — älteste zuerst.
/// [titelZusatz] sagt, welche Wochen es sind: „Oktober 2026".
DruckDokument wochenuebersichtDruck(
  List<WeekSnapshot> snaps, {
  required String titelZusatz,
  WochenuebersichtInhalt inhalt = const WochenuebersichtInhalt(),
  DateTime? gedrucktAm,
}) {
  final gedruckt = gedrucktAm ?? DateTime.now();
  final wochen = [for (final s in snaps) UebersichtWoche(s)]
    ..sort((a, b) => a.snap.wochenStart.compareTo(b.snap.wochenStart));
  final blatt =
      _Uebersicht(wochen, titelZusatz, inhalt, druckGedruckt(gedruckt));
  return DruckDokument(
    titel: 'Wochen im Überblick $titelZusatz',
    dateiname: druckDateiname(
      'Wochen im Ueberblick $titelZusatz ${druckIsoDatum(gedruckt)}',
    ),
    blaetter: [blatt.blatt()],
  );
}

/// Welche Wochen der Überblick zeigen kann: der Monat im Kalender
/// ([monat], 1. des Monats) — wenn darin Wochen archiviert sind — und die
/// letzten archivierten Wochen.
typedef _Auswahl = ({String wert, String titel, List<WeekSnapshot> snaps});

List<_Auswahl> _auswahl(List<WeekSnapshot> snaps, DateTime? monat) {
  final neueste = [...snaps]
    ..sort((a, b) => b.wochenStart.compareTo(a.wochenStart));
  final liste = <_Auswahl>[];
  if (monat != null) {
    // Eine Woche gehört zum Monat, wenn einer ihrer Werktage darin liegt —
    // wie im Kalender.
    bool imMonat(WeekSnapshot s) => [
          for (var i = 0; i < 5; i++) tagPlus(s.wochenStart, i),
        ].any((t) => t.year == monat.year && t.month == monat.month);
    final imKalender = [
      for (final s in neueste)
        if (imMonat(s)) s,
    ];
    if (imKalender.isNotEmpty) {
      liste.add(
        (
          wert: 'monat',
          titel: '${Format.monate[monat.month - 1]} ${monat.year}',
          snaps: imKalender,
        ),
      );
    }
  }
  // Die letzten Wochen nur, wenn es mehr gibt — sonst wäre es „alle".
  for (final n in const [4, 13, 52]) {
    if (neueste.length <= n) break;
    liste.add(
      (
        wert: '$n',
        titel: 'Die letzten $n Wochen',
        snaps: neueste.take(n).toList(),
      ),
    );
  }
  liste.add((wert: 'alle', titel: 'Alle Wochen', snaps: neueste));
  return liste;
}

/// Vorgewählt: der Monat im Kalender, sonst ein Quartal, sonst alle.
String _standard(List<_Auswahl> auswahl) {
  for (final wert in const ['monat', '13']) {
    if (auswahl.any((a) => a.wert == wert)) return wert;
  }
  return 'alle';
}

/// Der Überblick für das Druckfenster. [monat]: der Monat, den der
/// Kalender zeigt — vorgewählt, wenn darin Wochen archiviert sind.
DruckAuftrag wochenuebersichtDruckAuftrag(
  List<WeekSnapshot> snaps, {
  DateTime? monat,
  DateTime? gedrucktAm,
}) {
  final auswahl = _auswahl(snaps, monat);
  final mitErkenntnissen = snaps.any((s) => (s.notiz?.trim() ?? '').isNotEmpty);
  String anzahl(int n) => n == 1 ? '1 Woche' : '$n Wochen';
  return DruckAuftrag(
    art: 'wochenuebersicht',
    titel: 'Wochen im Überblick drucken',
    untertitel: '${anzahl(snaps.length)} archiviert',
    optionen: [
      DruckWahlEins(
        schluessel: WochenuebersichtWahl.wochen,
        titel: 'Wochen',
        werte: [
          for (final a in auswahl)
            DruckWert(a.wert, a.titel, hinweis: anzahl(a.snaps.length)),
        ],
        standard: _standard(auswahl),
        merken: false,
      ),
      const DruckSchalter(
        schluessel: WochenuebersichtWahl.abteilungen,
        titel: 'Auslastung je Abteilung',
        gruppe: 'Auf dem Blatt',
      ),
      if (mitErkenntnissen)
        const DruckSchalter(
          schluessel: WochenuebersichtWahl.erkenntnisse,
          titel: 'Erkenntnisse der Wochen',
          gruppe: 'Auf dem Blatt',
        ),
    ],
    bauen: (wahl) {
      final gewaehlt = auswahl.firstWhere(
        (a) => a.wert == wahl.eins(WochenuebersichtWahl.wochen),
        orElse: () => auswahl.first,
      );
      if (gewaehlt.snaps.isEmpty) {
        throw const DruckNichtsGewaehlt('Es ist noch keine Woche archiviert.');
      }
      return wochenuebersichtDruck(
        gewaehlt.snaps,
        titelZusatz: gewaehlt.titel,
        gedrucktAm: gedrucktAm,
        inhalt: WochenuebersichtInhalt(
          abteilungen: wahl.an(WochenuebersichtWahl.abteilungen),
          erkenntnisse:
              mitErkenntnissen && wahl.an(WochenuebersichtWahl.erkenntnisse),
        ),
      );
    },
  );
}

const PdfColor _gruen = PdfColor.fromInt(0xFF2E7D32);
const PdfColor _rot = PdfColor.fromInt(0xFFC62828);

class _Uebersicht {
  _Uebersicht(this.wochen, this.titelZusatz, this.inhalt, this.gedruckt);

  final List<UebersichtWoche> wochen;
  final String titelZusatz;
  final WochenuebersichtInhalt inhalt;
  final String gedruckt;

  /// Die Abteilungen, die in einer der Wochen etwas zu tun hatten.
  List<Abteilung> get abteilungen => [
        for (final a in Abteilung.values)
          if (wochen.any((w) => w.abteilungen.any((x) => x.abteilung == a))) a,
      ];

  DruckBlatt blatt() {
    final n = wochen.length;
    final zeile = [
      if (wochen.isNotEmpty)
        'KW ${wochen.first.snap.kw}/${wochen.first.snap.jahr} bis '
            'KW ${wochen.last.snap.kw}/${wochen.last.snap.jahr}',
      n == 1 ? '1 archivierte Woche' : '$n archivierte Wochen',
    ].join(' · ');
    return DruckBlatt(
      quer: true,
      bauen: (r) {
        final teile = <pw.Widget>[
          ...kennzahlen(),
          tabelle(),
          if (inhalt.abteilungen && abteilungen.isNotEmpty) legende(),
          if (inhalt.erkenntnisse) ...erkenntnisse(),
        ];
        return DruckSeiten(
          kopf: (ctx) => druckKopf(
            titel: 'Wochen im Überblick · $titelZusatz',
            zeile: zeile,
            gedruckt: gedruckt,
          ),
          fuss: (ctx) => druckFuss(
            'Wochen-Historie · $titelZusatz',
            r.seitenText(ctx),
          ),
          inhalt: (ctx) => teile,
        );
      },
    );
  }

  List<pw.Widget> kennzahlen() {
    final auftraege =
        wochen.fold<int>(0, (s, w) => s + w.daten.anzahlAuftraege);
    final kg = wochen.fold<double>(0, (s, w) => s + w.kg);
    final belegt = wochen.fold<double>(0, (s, w) => s + w.belegtMinuten);
    var belegtMitKap = 0.0;
    var kap = 0.0;
    for (final w in wochen) {
      final (b, k) = w._mitKapazitaet;
      belegtMitKap += b;
      kap += k;
    }
    return [
      druckKennzahlen([
        DruckKennzahl('${wochen.length}', 'Wochen', betont: true),
        DruckKennzahl('$auftraege', 'Aufträge', betont: true),
        DruckKennzahl(Format.kg(kg), 'Menge'),
        DruckKennzahl(Zeit.kurz(belegt), 'belegt'),
        if (kap > 0)
          DruckKennzahl(
            Format.prozent(belegtMitKap / kap, nachkomma: 0),
            'Ø Auslastung',
          ),
      ]),
    ];
  }

  pw.Widget prozentZelle(double? anteil, {bool fett = false}) {
    if (anteil == null) return druckZelle('', groesse: 8);
    return druckZelle(
      Format.prozent(anteil, nachkomma: 0),
      rechts: true,
      groesse: 8,
      fett: fett || anteil > 1,
      farbe: anteil > 1
          ? _rot
          : anteil >= 0.75
              ? _gruen
              : PdfColors.black,
    );
  }

  pw.Widget tabelle() {
    final spalten = inhalt.abteilungen ? abteilungen : const <Abteilung>[];
    final breiten = <pw.TableColumnWidth>[
      const pw.FixedColumnWidth(58),
      const pw.FixedColumnWidth(78),
      const pw.FixedColumnWidth(50),
      const pw.FixedColumnWidth(66),
      const pw.FixedColumnWidth(56),
      const pw.FixedColumnWidth(44),
      for (final _ in spalten) const pw.FixedColumnWidth(38),
      const pw.FlexColumnWidth(),
    ];
    return pw.Table(
      border: kDruckGitter,
      columnWidths: breiten.asMap(),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        druckKopfzeile([
          druckKopfZelle('KW'),
          druckKopfZelle('Zeitraum'),
          druckKopfZelle('Aufträge', rechts: true),
          druckKopfZelle('Menge', rechts: true),
          druckKopfZelle('Belegt', rechts: true),
          druckKopfZelle('Ausl.', rechts: true),
          for (final a in spalten) druckKopfZelle(a.kurzcode, rechts: true),
          druckKopfZelle(''),
        ]),
        for (final w in wochen)
          pw.TableRow(
            children: [
              druckZelle(
                'KW ${w.snap.kw}/${w.snap.jahr % 100}',
                fett: true,
                groesse: 8.5,
              ),
              druckZelle(_zeitraum(w.snap), groesse: 8.5),
              druckZelle(
                '${w.daten.anzahlAuftraege}',
                rechts: true,
                groesse: 8.5,
              ),
              druckZelle(Format.kg(w.kg), rechts: true, groesse: 8.5),
              druckZelle(
                Zeit.kurz(w.belegtMinuten),
                rechts: true,
                groesse: 8.5,
              ),
              prozentZelle(w.auslastung, fett: true),
              for (final a in spalten) prozentZelle(w.auslastungVon(a)),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 4),
                child: switch (w.auslastung) {
                  null => pw.SizedBox(),
                  final double anteil => druckBalken(
                      [
                        (
                          anteil,
                          anteil > 1
                              ? _rot
                              : anteil >= 0.75
                                  ? _gruen
                                  : PdfColors.grey500,
                        ),
                      ],
                      max: 1.5,
                      marke: 1,
                      breite: 120,
                    ),
                },
              ),
            ],
          ),
      ],
    );
  }

  /// Welche Abteilung hinter welchem Kürzel steckt.
  pw.Widget legende() => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 3),
        child: druckHinweis(
          '${[
            for (final a in abteilungen) '${a.kurzcode} ${a.anzeigeName}',
          ].join(' · ')} — Auslastung Mo–Fr gegen die Kapazität beim '
          'Archivieren; Balken bis 150 %, Strich bei 100 %.',
          zeilen: 2,
        ),
      );

  List<pw.Widget> erkenntnisse() {
    final mit = [
      for (final w in wochen)
        if ((w.snap.notiz?.trim() ?? '').isNotEmpty) w,
    ];
    if (mit.isEmpty) return const [];
    return [
      pw.SizedBox(height: 10),
      druckZwischentitel('Erkenntnisse'),
      for (final w in mit)
        pw.Padding(
          padding: const pw.EdgeInsets.fromLTRB(4, 2, 4, 4),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 64,
                child: pw.Text(
                  pdfText('KW ${w.snap.kw}/${w.snap.jahr % 100}'),
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Expanded(
                child: pw.Text(
                  pdfText(w.snap.notiz!.trim()),
                  maxLines: 6,
                  style: const pw.TextStyle(fontSize: 8.5, lineSpacing: 1.3),
                ),
              ),
            ],
          ),
        ),
    ];
  }
}
