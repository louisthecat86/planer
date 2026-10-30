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

// Die Auswertung einer archivierten Woche auf Papier — wie auf dem
// Schirm: Kennzahlen, Auslastung je Abteilung gegen die Kapazität beim
// Archivieren, die Aufträge Tag für Tag, Nebenzeiten und die Erkenntnisse.

/// Schlüssel der Wahl im Druckfenster.
abstract final class WochenauswertungWahl {
  static const abteilungen = 'abteilungen';
  static const tage = 'tage';
  static const auftragsnotizen = 'auftragsnotizen';
  static const nebenzeiten = 'nebenzeiten';
  static const erkenntnisse = 'erkenntnisse';
}

/// Was auf die Auswertung kommt — die Wahl im Druckfenster.
class WochenauswertungInhalt {
  const WochenauswertungInhalt({
    this.abteilungen,
    this.tage = true,
    this.auftragsnotizen = false,
    this.nebenzeiten = true,
    this.erkenntnisse = true,
  });

  /// Nur diese Abteilungen (dbValues) — null: alle.
  final Set<String>? abteilungen;

  /// Die Aufträge Tag für Tag.
  final bool tage;

  /// Die Notizen der Aufträge in den Tagen.
  final bool auftragsnotizen;

  /// Rüst-, Reinigungs- und sonstige Zeiten einzeln.
  final bool nebenzeiten;

  /// Die Erkenntnisse zur Woche.
  final bool erkenntnisse;
}

/// „Rüsten", „Reinigen", „Sonstiges".
String nebenzeitArt(String art) => switch (art) {
      'ruesten' => 'Rüsten',
      'reinigen' => 'Reinigen',
      _ => 'Sonstiges',
    };

/// Die Abteilung zu [dbValue] — null, wenn es sie nicht mehr gibt.
Abteilung? _abteilung(String dbValue) {
  for (final a in Abteilung.values) {
    if (a.dbValue == dbValue) return a;
  }
  return null;
}

/// Die Auslastung einer Abteilung: belegt gegen die Kapazität Mo–Fr.
typedef AbteilungsWoche = ({
  Abteilung abteilung,
  double belegtMinuten,
  double nebenMinuten,
  double kapazitaetMinuten,
  double kg,
  int auftraege,
});

/// Je Abteilung mit Belegung ihre Woche — in der Reihenfolge der App.
List<AbteilungsWoche> abteilungsWochen(WochenSnapshotDaten daten) {
  final belegt = daten.belegtMinutenJeAbteilung;
  final neben = daten.zusatzMinutenJeAbteilung;
  final kg = daten.kgJeAbteilung;
  final auftraege = daten.auftraegeJeAbteilung;
  return [
    for (final a in Abteilung.values)
      if ((belegt[a.dbValue] ?? 0) > 0)
        (
          abteilung: a,
          belegtMinuten: belegt[a.dbValue] ?? 0,
          nebenMinuten: neben[a.dbValue] ?? 0,
          // Die Wochenkapazität: Tageskapazität mal fünf Werktage — wie auf
          // dem Schirm.
          kapazitaetMinuten: (daten.kapazitaeten[a.dbValue] ?? 0) * 5,
          kg: kg[a.dbValue] ?? 0,
          auftraege: auftraege[a.dbValue] ?? 0,
        ),
  ];
}

const PdfColor _gruen = PdfColor.fromInt(0xFF2E7D32);
const PdfColor _rot = PdfColor.fromInt(0xFFC62828);

/// Farbe der Auslastung wie auf dem Schirm: überbucht rot, gut gefüllt
/// grün, sonst grau.
PdfColor _auslastungsFarbe(double anteil) => anteil > 1
    ? _rot
    : anteil >= 0.75
        ? _gruen
        : PdfColors.grey500;

/// „Mo 26.10. – So 01.11.2026"
String _zeitraum(DateTime montag) {
  final sonntag = tagPlus(montag, 6);
  return '${Format.tagKurz(montag)} – ${Format.tagKurz(sonntag)}'
      '${sonntag.year}';
}

/// Die Auswertung der archivierten Woche [snap] zum Drucken. [notiz]
/// statt der gespeicherten Erkenntnisse — etwa, was gerade im Feld steht.
DruckDokument wochenauswertungDruck(
  WeekSnapshot snap, {
  WochenauswertungInhalt inhalt = const WochenauswertungInhalt(),
  String? notiz,
  DateTime? gedrucktAm,
}) {
  final auswertung = _Auswertung(
    snap,
    dekodiereSnapshot(snap),
    inhalt,
    druckGedruckt(gedrucktAm ?? DateTime.now()),
    notiz: notiz ?? snap.notiz,
  );
  final titel = 'Auswertung KW ${snap.kw} ${snap.jahr}';
  return DruckDokument(
    titel: titel,
    dateiname: druckDateiname(titel),
    blaetter: [auswertung.blatt()],
  );
}

/// Die Auswertung für das Druckfenster — mit [notiz] statt der
/// gespeicherten Erkenntnisse.
DruckAuftrag wochenauswertungDruckAuftrag(
  WeekSnapshot snap, {
  String? notiz,
  DateTime? gedrucktAm,
}) {
  final daten = dekodiereSnapshot(snap);
  final wochen = abteilungsWochen(daten);
  final mitNotizen =
      daten.tasks.any((t) => (t.notizen?.trim() ?? '').isNotEmpty);
  final erkenntnis = notiz ?? snap.notiz;
  final mitErkenntnis = (erkenntnis?.trim() ?? '').isNotEmpty;
  return DruckAuftrag(
    art: 'wochenauswertung',
    titel: 'Auswertung drucken',
    untertitel: 'KW ${snap.kw} · ${_zeitraum(snap.wochenStart)}',
    optionen: [
      if (wochen.length > 1)
        DruckWahlMehrere(
          schluessel: WochenauswertungWahl.abteilungen,
          titel: 'Abteilungen',
          werte: [
            for (final w in wochen)
              DruckWert(
                w.abteilung.dbValue,
                w.abteilung.anzeigeName,
                hinweis: '${w.auftraege} '
                    '${w.auftraege == 1 ? 'Auftrag' : 'Aufträge'} · '
                    '${Zeit.kurz(w.belegtMinuten)}',
                farbe: w.abteilung.farbwert,
                kuerzel: w.abteilung.kurzcode,
              ),
          ],
          standard: {for (final w in wochen) w.abteilung.dbValue},
          merken: false,
        ),
      if (daten.tasks.isNotEmpty)
        const DruckSchalter(
          schluessel: WochenauswertungWahl.tage,
          titel: 'Aufträge je Tag',
          gruppe: 'Auf dem Blatt',
        ),
      if (mitNotizen)
        DruckSchalter(
          schluessel: WochenauswertungWahl.auftragsnotizen,
          titel: 'Notizen der Aufträge',
          standard: false,
          gruppe: 'Auf dem Blatt',
          sichtbar: (w) => w.an(WochenauswertungWahl.tage),
        ),
      if (daten.zusatzzeiten.isNotEmpty)
        const DruckSchalter(
          schluessel: WochenauswertungWahl.nebenzeiten,
          titel: 'Nebenzeiten einzeln',
          hinweis: 'Rüsten, Reinigen, Sonstiges',
          gruppe: 'Auf dem Blatt',
        ),
      if (mitErkenntnis)
        const DruckSchalter(
          schluessel: WochenauswertungWahl.erkenntnisse,
          titel: 'Erkenntnisse / Notiz',
          gruppe: 'Auf dem Blatt',
        ),
    ],
    bauen: (wahl) {
      final gewaehlt = wochen.length > 1
          ? wahl.mehrere(WochenauswertungWahl.abteilungen)
          : null;
      if (gewaehlt != null && gewaehlt.isEmpty) {
        throw const DruckNichtsGewaehlt('Wähle mindestens eine Abteilung.');
      }
      return wochenauswertungDruck(
        snap,
        notiz: erkenntnis,
        gedrucktAm: gedrucktAm,
        inhalt: WochenauswertungInhalt(
          abteilungen: gewaehlt,
          tage: daten.tasks.isNotEmpty && wahl.an(WochenauswertungWahl.tage),
          auftragsnotizen:
              mitNotizen && wahl.an(WochenauswertungWahl.auftragsnotizen),
          nebenzeiten: daten.zusatzzeiten.isNotEmpty &&
              wahl.an(WochenauswertungWahl.nebenzeiten),
          erkenntnisse:
              mitErkenntnis && wahl.an(WochenauswertungWahl.erkenntnisse),
        ),
      );
    },
  );
}

/// Höchstens so hoch wird eine Zeile der Tabellen — eine Zeile Text, mit
/// Notiz zwei.
const double _zeileHoechstens = 28;

class _Auswertung {
  _Auswertung(
    this.snap,
    this.daten,
    this.inhalt,
    this.gedruckt, {
    this.notiz,
  });

  final WeekSnapshot snap;

  /// Die Erkenntnisse zur Woche.
  final String? notiz;
  final WochenSnapshotDaten daten;
  final WochenauswertungInhalt inhalt;
  final String gedruckt;

  bool gewaehlt(String abteilung) =>
      inhalt.abteilungen?.contains(abteilung) ?? true;

  List<SnapshotTask> get tasks => [
        for (final t in daten.tasks)
          if (gewaehlt(t.abteilung)) t,
      ];

  List<SnapshotZusatzzeit> get nebenzeiten => [
        for (final z in daten.zusatzzeiten)
          if (gewaehlt(z.spurId.split('|').first)) z,
      ];

  /// Der Name der Spur einer Nebenzeit: die Anlage aus dem Plan, sonst die
  /// Abteilung.
  String spurName(String spurId) {
    final plan = daten.plan;
    if (plan != null) {
      for (final s in plan.spuren) {
        if (s.id == spurId) {
          final abt = _abteilung(s.abteilung)?.anzeigeName ?? s.abteilung;
          final anlage = s.maschineName;
          return anlage == null ? abt : '$abt · $anlage';
        }
      }
    }
    final abteilung = spurId.split('|').first;
    return _abteilung(abteilung)?.anzeigeName ?? abteilung;
  }

  DruckBlatt blatt() {
    final am = snap.createdAt;
    final zeile = [
      _zeitraum(snap.wochenStart),
      'archiviert ${Format.datum(am)}, ${Format.uhrzeit(am)}',
      if (inhalt.abteilungen != null)
        [
          for (final a in Abteilung.values)
            if (inhalt.abteilungen!.contains(a.dbValue)) a.anzeigeName,
        ].join(', '),
    ].join(' · ');
    return DruckBlatt(
      bauen: (r) {
        final teile = <pw.Widget>[
          ...kennzahlen(),
          ...auslastung(r),
          if (inhalt.tage) ...tageMitAuftraegen(r),
          if (inhalt.nebenzeiten) ...nebenzeitTabelle(r),
          if (inhalt.erkenntnisse) ...erkenntnisse(),
        ];
        return DruckSeiten(
          kopf: (ctx) => druckKopf(
            titel: 'Auswertung KW ${snap.kw} · ${snap.jahr}',
            zeile: zeile,
            gedruckt: gedruckt,
          ),
          fuss: (ctx) => druckFuss(
            'Wochenauswertung KW ${snap.kw}/${snap.jahr}',
            r.seitenText(ctx),
          ),
          inhalt: (ctx) => teile,
        );
      },
    );
  }

  List<pw.Widget> kennzahlen() {
    final t = tasks;
    final kg = t.fold<double>(0, (s, x) => s + x.mengeKg);
    final neben = nebenzeiten.fold<double>(0, (s, z) => s + z.minuten);
    final belegt = t.fold<double>(0, (s, x) => s + x.dauerMinuten) + neben;
    return [
      druckKennzahlen([
        DruckKennzahl('${t.length}', 'Aufträge', betont: true),
        DruckKennzahl(Format.kg(kg), 'Menge', betont: true),
        DruckKennzahl(Zeit.kurz(belegt), 'belegt gesamt'),
        if (neben > 0) DruckKennzahl(Zeit.kurz(neben), 'davon Nebenzeiten'),
      ]),
    ];
  }

  List<pw.Widget> auslastung(DruckRahmen r) {
    final wochen = [
      for (final w in abteilungsWochen(daten))
        if (gewaehlt(w.abteilung.dbValue)) w,
    ];
    if (wochen.isEmpty) {
      return [
        druckZwischentitel('Auslastung je Abteilung'),
        druckHinweis('Keine Aufträge in dieser Woche.'),
      ];
    }
    final skala = wochen.fold<double>(1.2, (m, w) {
      final a =
          w.kapazitaetMinuten > 0 ? w.belegtMinuten / w.kapazitaetMinuten : 0.0;
      return a > m ? a : m;
    });
    return [
      pw.Inseparable(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            druckZwischentitel(
              'Auslastung je Abteilung — Mo–Fr, gemessen an der Kapazität '
              'beim Archivieren',
            ),
            pw.Table(
              border: kDruckGitter,
              columnWidths: const {
                0: pw.FlexColumnWidth(),
                1: pw.FixedColumnWidth(84),
                2: pw.FixedColumnWidth(44),
                3: pw.FixedColumnWidth(98),
                4: pw.FixedColumnWidth(62),
                5: pw.FixedColumnWidth(48),
                6: pw.FixedColumnWidth(56),
              },
              defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
              children: [
                druckKopfzeile([
                  druckKopfZelle('Abteilung'),
                  druckKopfZelle('Belegt / Kap.', rechts: true),
                  druckKopfZelle('Ausl.', rechts: true),
                  druckKopfZelle(''),
                  druckKopfZelle('Menge', rechts: true),
                  druckKopfZelle('Aufträge', rechts: true),
                  druckKopfZelle('Neben', rechts: true),
                ]),
                for (final w in wochen) auslastungsZeile(w, skala),
              ],
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 3),
              child: druckHinweis(
                'Balken: belegt gegen die Kapazität, Strich bei 100 % — rot '
                'überbucht, grün ab 75 % gut gefüllt.',
                zeilen: 2,
              ),
            ),
          ],
        ),
      ),
    ];
  }

  pw.TableRow auslastungsZeile(AbteilungsWoche w, double skala) {
    final kap = w.kapazitaetMinuten;
    final anteil = kap > 0 ? w.belegtMinuten / kap : 0.0;
    final farbe = _auslastungsFarbe(anteil);
    return pw.TableRow(
      children: [
        druckZelleMitPunkt(
          w.abteilung.anzeigeName,
          druckFarbe(w.abteilung.farbwert),
          zeilen: 1,
          groesse: 9,
        ),
        druckZelle(
          kap > 0
              ? '${Zeit.kurzOhneEinheit(w.belegtMinuten)} / '
                  '${Zeit.kurz(kap)}'
              : Zeit.kurz(w.belegtMinuten),
          rechts: true,
          groesse: 8.5,
        ),
        druckZelle(
          kap > 0 ? Format.prozent(anteil, nachkomma: 0) : '',
          rechts: true,
          fett: true,
          farbe: anteil > 1 ? _rot : PdfColors.black,
          groesse: 8.5,
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4),
          child: kap > 0
              ? druckBalken(
                  [(anteil, farbe)],
                  max: skala,
                  marke: 1,
                  breite: 90,
                )
              : pw.SizedBox(),
        ),
        druckZelle(Format.kg(w.kg), rechts: true, groesse: 8.5),
        druckZelle('${w.auftraege}', rechts: true, groesse: 8.5),
        druckZelle(
          w.nebenMinuten > 0 ? Zeit.kurz(w.nebenMinuten) : '',
          rechts: true,
          groesse: 8.5,
        ),
      ],
    );
  }

  /// Die Aufträge Tag für Tag — je Tag eine Leiste mit der Summe.
  List<pw.Widget> tageMitAuftraegen(DruckRahmen r) {
    final jeTag = <DateTime, List<SnapshotTask>>{};
    for (final t in tasks) {
      (jeTag[tagOhneZeit(t.datum)] ??= []).add(t);
    }
    if (jeTag.isEmpty) return const [];
    final tage = jeTag.keys.toList()..sort();
    final notizen = inhalt.auftragsnotizen;
    final teile = <pw.Widget>[
      pw.SizedBox(height: 8),
      druckZwischentitel('Aufträge je Tag'),
    ];
    for (final tag in tage) {
      final liste = [...jeTag[tag]!]..sort(_reihenfolge);
      final kg = liste.fold<double>(0, (s, t) => s + t.mengeKg);
      final minuten = liste.fold<double>(0, (s, t) => s + t.dauerMinuten);
      teile.addAll(
        druckGruppe(
          [
            pw.SizedBox(height: 4),
            druckLeiste(
              Format.tagKurz(tag),
              rechts: '${liste.length} '
                  '${liste.length == 1 ? 'Auftrag' : 'Aufträge'} · '
                  '${Format.kg(kg)} · ${Zeit.kurz(minuten)}',
            ),
            tagesTabelle(liste, notizen: notizen),
          ],
          zusammen: 120 + liste.length * _zeileHoechstens <= r.hoehe,
          rahmen: r,
          frei: 90,
        ),
      );
    }
    return teile;
  }

  /// Wie auf dem Schirm: nach Abteilung, dann Startzeit, dann Artikel.
  static int _reihenfolge(SnapshotTask a, SnapshotTask b) {
    final abt = (_abteilung(a.abteilung)?.index ?? 99)
        .compareTo(_abteilung(b.abteilung)?.index ?? 99);
    if (abt != 0) return abt;
    final start = (a.startZeit ?? '99:99').compareTo(b.startZeit ?? '99:99');
    if (start != 0) return start;
    return a.productName.compareTo(b.productName);
  }

  pw.Widget tagesTabelle(List<SnapshotTask> liste, {required bool notizen}) {
    return pw.Table(
      border: kDruckGitter,
      columnWidths: const {
        0: pw.FixedColumnWidth(96),
        1: pw.FlexColumnWidth(),
        2: pw.FixedColumnWidth(40),
        3: pw.FixedColumnWidth(62),
        4: pw.FixedColumnWidth(52),
        5: pw.FixedColumnWidth(30),
      },
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        druckKopfzeile([
          druckKopfZelle('Abteilung'),
          druckKopfZelle('Artikel'),
          druckKopfZelle('Start'),
          druckKopfZelle('Menge', rechts: true),
          druckKopfZelle('Dauer', rechts: true),
          druckKopfZelle('MA', rechts: true),
        ]),
        for (final t in liste)
          pw.TableRow(
            children: [
              druckZelleMitPunkt(
                _abteilung(t.abteilung)?.anzeigeName ?? t.abteilung,
                switch (_abteilung(t.abteilung)) {
                  final Abteilung a => druckFarbe(a.farbwert),
                  null => PdfColors.grey500,
                },
                zeilen: 1,
                groesse: 8,
              ),
              druckZelleMitZeile(
                t.productName,
                notizen ? t.notizen : null,
                zeilenOben: 1,
                zeilenUnten: 1,
                groesse: 8.5,
              ),
              druckZelle(t.startZeit ?? '', groesse: 8.5),
              druckZelle(Format.kg(t.mengeKg), rechts: true, groesse: 8.5),
              druckZelle(Zeit.kurz(t.dauerMinuten), rechts: true, groesse: 8.5),
              druckZelle('${t.mitarbeiter}', rechts: true, groesse: 8.5),
            ],
          ),
      ],
    );
  }

  /// Die Nebenzeiten einzeln: Tag, Anlage, Art, Dauer, Notiz.
  List<pw.Widget> nebenzeitTabelle(DruckRahmen r) {
    final liste = [...nebenzeiten]..sort((a, b) {
        final t = a.datum.compareTo(b.datum);
        return t != 0 ? t : a.spurId.compareTo(b.spurId);
      });
    if (liste.isEmpty) return const [];
    return druckGruppe(
      [
        pw.SizedBox(height: 8),
        druckZwischentitel('Nebenzeiten'),
        pw.Table(
          border: kDruckGitter,
          columnWidths: const {
            0: pw.FixedColumnWidth(62),
            1: pw.FlexColumnWidth(1.4),
            2: pw.FixedColumnWidth(64),
            3: pw.FixedColumnWidth(52),
            4: pw.FlexColumnWidth(),
          },
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
          children: [
            druckKopfzeile([
              druckKopfZelle('Tag'),
              druckKopfZelle('Anlage'),
              druckKopfZelle('Art'),
              druckKopfZelle('Dauer', rechts: true),
              druckKopfZelle('Notiz'),
            ]),
            for (final z in liste)
              pw.TableRow(
                children: [
                  druckZelle(Format.tagKurz(z.datum), groesse: 8.5),
                  druckZelle(spurName(z.spurId), groesse: 8.5),
                  druckZelle(nebenzeitArt(z.art), groesse: 8.5),
                  druckZelle(Zeit.kurz(z.minuten), rechts: true, groesse: 8.5),
                  druckZelle(z.notiz ?? '', groesse: 8.5, zeilen: 2),
                ],
              ),
          ],
        ),
      ],
      zusammen: 90 + liste.length * _zeileHoechstens <= r.hoehe,
      rahmen: r,
      frei: 90,
    );
  }

  List<pw.Widget> erkenntnisse() {
    final text = notiz?.trim() ?? '';
    if (text.isEmpty) return const [];
    return [
      pw.SizedBox(height: 8),
      druckZwischentitel('Erkenntnisse / Notiz'),
      pw.Container(
        padding: const pw.EdgeInsets.all(7),
        decoration: const pw.BoxDecoration(
          border: pw.Border.fromBorderSide(kDruckLinie),
        ),
        child: pw.Text(
          // Lange Notizen auf eine Seite begrenzt — dann schließt der Kasten
          // sicher.
          pdfText(
            text.length > 3000 ? '${text.substring(0, 3000)} …' : text,
          ),
          style: const pw.TextStyle(fontSize: 9, lineSpacing: 1.5),
        ),
      ),
    ];
  }
}
