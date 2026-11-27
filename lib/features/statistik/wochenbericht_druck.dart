import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/druck/druck_bausteine.dart';
import '../../core/druck/druck_optionen.dart';
import '../../core/druck/druck_satz.dart';
import '../../core/utils/format.dart';
import '../../core/utils/kalenderwoche.dart';
import '../../core/utils/pdf_text.dart';
import '../../core/utils/zeit.dart';
import '../auftragsbestand/lieferfaehigkeit.dart';
import '../board/board_providers.dart' show CapacityStatus;
import 'statistik_daten.dart';
import 'statistik_ueberblick_daten.dart';

// ═══════════════════════════════════════════════════════════════════════
// Wochenbericht
//
// Eine Seite für die Geschäftsführung: Wie lief die Woche, verglichen mit
// der Woche davor? Lieferfähigkeit, Auslastung, Plan-Treue, Ausbeute,
// Planerfüllung — jeweils mit Ampel und woran sie gemessen wird. Darunter
// die Auslastung je Abteilung, die größten Abweichungen von Plan und Ist,
// gefährdete Versandtage, Hinweise und der Ausblick.
//
// Alle Zahlen kommen aus denselben Rechnungen wie Statistik und Cockpit.
// ═══════════════════════════════════════════════════════════════════════

/// Schlüssel der Wahl im Druckfenster.
abstract final class WochenberichtWahl {
  static const abteilungen = 'abteilungen';
  static const abweichungen = 'abweichungen';
  static const versand = 'versand';
  static const hinweise = 'hinweise';
  static const ausblick = 'ausblick';
  static const bemerkung = 'bemerkung';
}

/// Was auf den Bericht kommt.
class WochenberichtInhalt {
  const WochenberichtInhalt({
    this.abteilungen = true,
    this.abweichungen = true,
    this.versand = true,
    this.hinweise = true,
    this.ausblick = true,
    this.bemerkung = true,
  });

  final bool abteilungen;
  final bool abweichungen;
  final bool versand;
  final bool hinweise;
  final bool ausblick;
  final bool bemerkung;
}

/// So viele Zeilen haben die Listen — der Bericht bleibt eine Seite.
const int kBerichtZeilen = 5;

const PdfColor _gruen = PdfColor.fromInt(0xFF2E7D32);
const PdfColor _gelb = PdfColor.fromInt(0xFFE09B00);
const PdfColor _rot = PdfColor.fromInt(0xFFC62828);

PdfColor _ampelFarbe(Ampel a) => switch (a) {
      Ampel.gut => _gruen,
      Ampel.warnung => _gelb,
      Ampel.kritisch => _rot,
      Ampel.neutral => PdfColors.grey500,
    };

String _ampelWort(Ampel a) => switch (a) {
      Ampel.gut => 'gut',
      Ampel.warnung => 'beobachten',
      Ampel.kritisch => 'handeln',
      Ampel.neutral => '–',
    };

String _prozent(double? anteil, {int nachkomma = 0}) => anteil == null
    ? '–'
    : '${(anteil * 100).toStringAsFixed(nachkomma).replaceAll('.', ',')} %';

/// „KW 48 · 2026"
String wochenberichtTitel(StatistikSpanne s) =>
    'Wochenbericht KW ${isoKalenderwoche(s.von)} · '
    '${isoKalenderjahr(s.von)}';

/// Eine Zeile der Kennzahlen-Tabelle.
typedef BerichtKennzahl = ({
  String name,
  String wert,
  String vorher,
  Ampel ampel,
  String ziel,
});

/// Die Kennzahlen des Berichts: Lieferfähigkeit, dann die fünf des
/// Überblicks — in dieser Reihenfolge.
List<BerichtKennzahl> berichtKennzahlen(
  UeberblickAuswertung ueberblick,
  Lieferfaehigkeit liefer,
) =>
    [
      (
        name: 'Lieferfähigkeit',
        wert: _prozent(liefer.anteil),
        vorher: '',
        ampel: liefer.ampel,
        ziel: [
          'Versand der nächsten $kLieferTage Tage rechtzeitig gedeckt, '
              'gut ab ${_prozent(kLieferGut)}',
          if (liefer.herkunftText != null) liefer.herkunftText!,
        ].join(' · '),
      ),
      for (final k in ueberblick.kennzahlen)
        (
          name: k.name,
          wert: _prozent(k.wert, nachkomma: k.name == 'Ø Ausbeute' ? 1 : 0),
          vorher: _prozent(
            k.vorher,
            nachkomma: k.name == 'Ø Ausbeute' ? 1 : 0,
          ),
          ampel: k.ampel,
          ziel: k.ziel ?? '',
        ),
    ];

/// Der Wochenbericht zum Drucken — [daten] für eine Woche
/// ([StatistikZeitraum.woche]) samt der Woche davor.
DruckDokument wochenberichtDruck(
  StatistikDaten daten,
  Lieferfaehigkeit liefer, {
  WochenberichtInhalt inhalt = const WochenberichtInhalt(),
  DateTime? gedrucktAm,
}) {
  final titel = wochenberichtTitel(daten.spanne);
  final bericht = _Bericht(
    daten,
    werteUeberblickAus(daten),
    liefer,
    inhalt,
    druckGedruckt(gedrucktAm ?? DateTime.now()),
  );
  return DruckDokument(
    titel: titel,
    dateiname: druckDateiname(titel),
    blaetter: [bericht.blatt()],
  );
}

/// Der Wochenbericht für das Druckfenster.
DruckAuftrag wochenberichtDruckAuftrag(
  StatistikDaten daten,
  Lieferfaehigkeit liefer, {
  DateTime? gedrucktAm,
}) {
  const gruppe = 'Auf dem Blatt';
  return DruckAuftrag(
    art: 'wochenbericht',
    titel: 'Wochenbericht drucken',
    untertitel: '${wochenberichtTitel(daten.spanne)} · '
        '${daten.spanne.beschreibung}',
    optionen: const [
      DruckSchalter(
        schluessel: WochenberichtWahl.abteilungen,
        titel: 'Auslastung je Abteilung',
        gruppe: gruppe,
      ),
      DruckSchalter(
        schluessel: WochenberichtWahl.abweichungen,
        titel: 'Größte Abweichungen Plan/Ist',
        gruppe: gruppe,
      ),
      DruckSchalter(
        schluessel: WochenberichtWahl.versand,
        titel: 'Gefährdete Versandtage',
        gruppe: gruppe,
      ),
      DruckSchalter(
        schluessel: WochenberichtWahl.hinweise,
        titel: 'Hinweise',
        gruppe: gruppe,
      ),
      DruckSchalter(
        schluessel: WochenberichtWahl.ausblick,
        titel: 'Ausblick nächste Werktage',
        gruppe: gruppe,
      ),
      DruckSchalter(
        schluessel: WochenberichtWahl.bemerkung,
        titel: 'Feld für Bemerkungen',
        gruppe: gruppe,
      ),
    ],
    bauen: (wahl) => wochenberichtDruck(
      daten,
      liefer,
      gedrucktAm: gedrucktAm,
      inhalt: WochenberichtInhalt(
        abteilungen: wahl.an(WochenberichtWahl.abteilungen),
        abweichungen: wahl.an(WochenberichtWahl.abweichungen),
        versand: wahl.an(WochenberichtWahl.versand),
        hinweise: wahl.an(WochenberichtWahl.hinweise),
        ausblick: wahl.an(WochenberichtWahl.ausblick),
        bemerkung: wahl.an(WochenberichtWahl.bemerkung),
      ),
    ),
  );
}

class _Bericht {
  _Bericht(
    this.daten,
    this.ueberblick,
    this.liefer,
    this.inhalt,
    this.gedruckt,
  );

  final StatistikDaten daten;
  final UeberblickAuswertung ueberblick;
  final Lieferfaehigkeit liefer;
  final WochenberichtInhalt inhalt;
  final String gedruckt;

  StatistikSpanne get spanne => daten.spanne;

  DruckBlatt blatt() {
    final vorher = daten.vorher?.spanne;
    final zeile = [
      spanne.beschreibung,
      if (vorher != null) 'Vergleich: KW ${isoKalenderwoche(vorher.von)}',
    ].join(' · ');
    return DruckBlatt(
      bauen: (r) {
        final teile = <pw.Widget>[
          ...kopfzahlen(),
          ...kennzahlen(),
          if (inhalt.abteilungen) ...abteilungen(),
          if (inhalt.abweichungen) ...abweichungen(),
          if (inhalt.versand) ...versand(),
          if (inhalt.hinweise) ...hinweise(),
          if (inhalt.ausblick) ...ausblick(),
          if (inhalt.bemerkung) ...[
            pw.SizedBox(height: 6),
            druckSchreibfeld('Bemerkungen', hoehe: 48),
          ],
        ];
        return DruckSeiten(
          kopf: (ctx) => druckKopf(
            titel: wochenberichtTitel(spanne),
            zeile: zeile,
            gedruckt: gedruckt,
          ),
          fuss: (ctx) => druckFuss(
            wochenberichtTitel(spanne),
            r.seitenText(ctx),
          ),
          inhalt: (ctx) => teile,
        );
      },
    );
  }

  /// Aufträge, erledigt, Menge, erfasste Produktionen.
  List<pw.Widget> kopfzahlen() {
    final wurzeln = [
      for (final k in daten.karten)
        if (k.wurzel) k,
    ];
    final erledigt = wurzeln.where((k) => k.erledigt != null).length;
    final kg = wurzeln.fold<double>(0, (s, k) => s + (k.mengeKg ?? 0));
    final roh =
        daten.produktionen.fold<double>(0, (s, p) => s + (p.kgRohware ?? 0));
    return [
      druckKennzahlen([
        DruckKennzahl(
          '${wurzeln.length}',
          'Produktionen geplant',
          betont: true,
        ),
        DruckKennzahl('$erledigt', 'davon erledigt'),
        if (kg > 0)
          DruckKennzahl(Format.kg(kg), 'Rohware geplant', betont: true),
        DruckKennzahl('${daten.produktionen.length}', 'erfasst'),
        if (roh > 0) DruckKennzahl(Format.kg(roh), 'Rohware erfasst'),
      ]),
    ];
  }

  /// Die Kennzahlen mit Vorwoche, Ampel und Maßstab.
  List<pw.Widget> kennzahlen() {
    final zeilen = berichtKennzahlen(ueberblick, liefer);
    return [
      druckZwischentitel('Kennzahlen'),
      pw.Table(
        border: kDruckGitter,
        columnWidths: const {
          0: pw.FixedColumnWidth(96),
          1: pw.FixedColumnWidth(54),
          2: pw.FixedColumnWidth(54),
          3: pw.FixedColumnWidth(70),
          4: pw.FlexColumnWidth(),
        },
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
        children: [
          druckKopfzeile([
            druckKopfZelle('Kennzahl'),
            druckKopfZelle('Woche', rechts: true),
            druckKopfZelle('Vorwoche', rechts: true),
            druckKopfZelle('Bewertung'),
            druckKopfZelle('Gemessen an'),
          ]),
          for (final k in zeilen)
            pw.TableRow(
              children: [
                druckZelle(k.name, fett: true),
                druckZelle(k.wert, rechts: true, fett: true),
                druckZelle(
                  k.vorher,
                  rechts: true,
                  farbe: PdfColors.grey700,
                ),
                druckZelleMitPunkt(
                  _ampelWort(k.ampel),
                  _ampelFarbe(k.ampel),
                  zeilen: 1,
                  groesse: 8.5,
                ),
                druckZelle(k.ziel, zeilen: 2, groesse: 7.5),
              ],
            ),
        ],
      ),
    ];
  }

  /// Belegt gegen Kapazität je Abteilung.
  List<pw.Widget> abteilungen() {
    final a = werteAuslastungAus(daten.belegung, spanne);
    // Nur Abteilungen, in denen die Woche etwas geplant war.
    final zeilen = [
      for (final z in a.zeilen)
        if (z.belegtMinuten > 0) z,
    ];
    if (a.leer || zeilen.isEmpty) return const [];
    return [
      druckZwischentitel('Auslastung je Abteilung'),
      pw.Table(
        border: kDruckGitter,
        columnWidths: const {
          0: pw.FlexColumnWidth(),
          1: pw.FixedColumnWidth(96),
          2: pw.FixedColumnWidth(48),
          3: pw.FixedColumnWidth(110),
          4: pw.FixedColumnWidth(70),
        },
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
        children: [
          druckKopfzeile([
            druckKopfZelle('Abteilung'),
            druckKopfZelle('Belegt / Kap.', rechts: true),
            druckKopfZelle('Ausl.', rechts: true),
            druckKopfZelle(''),
            druckKopfZelle('Überbucht', rechts: true),
          ]),
          for (final z in zeilen)
            pw.TableRow(
              children: [
                druckZelleMitPunkt(
                  z.name,
                  druckFarbe(z.abteilung.farbwert),
                  zeilen: 1,
                  groesse: 9,
                ),
                druckZelle(
                  '${Zeit.kurzOhneEinheit(z.belegtMinuten)} / '
                  '${Zeit.kurz(z.kapazitaetMinuten)}',
                  rechts: true,
                  groesse: 8.5,
                ),
                druckZelle(
                  _prozent(z.kapazitaetMinuten > 0 ? z.auslastung : null),
                  rechts: true,
                  groesse: 8.5,
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 4),
                  child: druckBalken(
                    [
                      (
                        z.auslastung,
                        switch (z.status) {
                          CapacityStatus.ueberbucht => _rot,
                          CapacityStatus.gut => _gruen,
                          CapacityStatus.frei => PdfColors.grey500,
                        },
                      ),
                    ],
                    breite: 100,
                    max: 1.2,
                    marke: 1,
                  ),
                ),
                druckZelle(
                  z.ueberbuchteTage == 0
                      ? '–'
                      : z.ueberbuchteTage == 1
                          ? '1 Tag'
                          : '${z.ueberbuchteTage} Tage',
                  rechts: true,
                  groesse: 8.5,
                ),
              ],
            ),
        ],
      ),
    ];
  }

  /// Die größten Abweichungen von Plan und Ist.
  List<pw.Widget> abweichungen() {
    final liste = ueberblick.planIst.abweichungen.take(kBerichtZeilen);
    if (liste.isEmpty) {
      return [
        druckZwischentitel('Größte Abweichungen Plan/Ist'),
        druckHinweis(
          ueberblick.planIst.leer
              ? 'Keine erfassten Produktionen mit Plan in dieser Woche.'
              : 'Alle erfassten Produktionen lagen im Rahmen.',
        ),
      ];
    }
    String plusMinus(double? a) =>
        a == null ? '' : ' (${a >= 0 ? '+' : '−'}${(a.abs() * 100).round()} %)';
    return [
      druckZwischentitel('Größte Abweichungen Plan/Ist'),
      pw.Table(
        border: kDruckGitter,
        columnWidths: const {
          0: pw.FlexColumnWidth(),
          1: pw.FixedColumnWidth(54),
          2: pw.FixedColumnWidth(128),
          3: pw.FixedColumnWidth(128),
        },
        children: [
          druckKopfzeile([
            druckKopfZelle('Artikel'),
            druckKopfZelle('Tag'),
            druckKopfZelle('Rohware Plan → Ist'),
            druckKopfZelle('Dauer Plan → Ist'),
          ]),
          for (final p in liste)
            pw.TableRow(
              children: [
                druckZelle(
                  '${p.artikel.artikelnummer} ${p.artikel.bezeichnung}',
                  groesse: 8.5,
                ),
                druckZelle(tagText(p.datum), groesse: 8.5),
                druckZelle(
                  p.planKg == null || p.istKg == null
                      ? '–'
                      : '${Format.kg(p.planKg!)} → ${Format.kg(p.istKg!)}'
                          '${plusMinus(p.mengeAbweichung)}',
                  groesse: 8.5,
                  farbe: p.mengeImBand ? PdfColors.black : _rot,
                ),
                druckZelle(
                  p.planMinuten == null || p.istMinuten == null
                      ? '–'
                      : '${Zeit.kurzOhneEinheit(p.planMinuten!)} → '
                          '${Zeit.kurz(p.istMinuten!)}'
                          '${plusMinus(p.zeitAbweichung)}',
                  groesse: 8.5,
                  farbe: p.zeitImBand ? PdfColors.black : _rot,
                ),
              ],
            ),
        ],
      ),
    ];
  }

  /// Versandtage der nächsten Tage, die nicht rechtzeitig gedeckt sind.
  List<pw.Widget> versand() {
    if (liefer.berichtTag == null) return const [];
    const titel = 'Gefährdete Versandtage — nächste $kLieferTage Tage';
    if (liefer.gefaehrdet.isEmpty) {
      return [
        druckZwischentitel(titel),
        druckHinweis(
          liefer.anteil == null
              ? 'Kein Versand im Auftragsbestand.'
              : 'Alle Versandtage sind rechtzeitig gedeckt.',
        ),
      ];
    }
    final mehr = liefer.gefaehrdet.length - kBerichtZeilen;
    return [
      druckZwischentitel(titel),
      pw.Table(
        border: kDruckGitter,
        columnWidths: const {
          0: pw.FlexColumnWidth(),
          1: pw.FixedColumnWidth(54),
          2: pw.FixedColumnWidth(80),
          3: pw.FixedColumnWidth(80),
        },
        children: [
          druckKopfzeile([
            druckKopfZelle('Artikel'),
            druckKopfZelle('Versand'),
            druckKopfZelle('Fehlt', rechts: true),
            druckKopfZelle('Zu spät', rechts: true),
          ]),
          for (final g in liefer.gefaehrdet.take(kBerichtZeilen))
            pw.TableRow(
              children: [
                druckZelle('${g.artikelnummer} ${g.bezeichnung}', groesse: 8.5),
                druckZelle(tagText(g.tag), groesse: 8.5),
                druckZelle(
                  g.fehltKg < 0.5 ? '–' : Format.kg(g.fehltKg),
                  rechts: true,
                  groesse: 8.5,
                ),
                druckZelle(
                  g.zuSpaetKg < 0.5 ? '–' : Format.kg(g.zuSpaetKg),
                  rechts: true,
                  groesse: 8.5,
                ),
              ],
            ),
        ],
      ),
      if (mehr > 0) druckHinweis('… und $mehr weitere.'),
    ];
  }

  List<pw.Widget> hinweise() {
    final liste = ueberblick.hinweise;
    if (liste.isEmpty) return const [];
    return [
      druckZwischentitel('Hinweise'),
      for (final h in liste)
        pw.Padding(
          padding: const pw.EdgeInsets.fromLTRB(4, 1, 2, 1),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 3, right: 5),
                child: druckPunkt(
                  switch (h.schwere) {
                    HinweisSchwere.kritisch => _rot,
                    HinweisSchwere.warnung => _gelb,
                    HinweisSchwere.info => PdfColors.grey500,
                  },
                ),
              ),
              pw.Expanded(
                child: pw.Text(
                  pdfText(h.text),
                  style: const pw.TextStyle(fontSize: 8.5),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  /// Wo es in den nächsten Werktagen eng wird.
  List<pw.Widget> ausblick() {
    final v = ueberblick.vorschau;
    final eng = v.ueberbucht;
    final tage = v.tage;
    final bis = tage.isEmpty ? null : tage.last;
    return [
      druckZwischentitel(
        bis == null ? 'Ausblick' : 'Ausblick bis ${Format.tagKurz(bis)}',
      ),
      if (v.leer)
        druckHinweis('In den nächsten Werktagen ist noch nichts geplant.')
      else if (eng.isEmpty)
        druckHinweis('Keine Abteilung ist überbucht.')
      else
        for (final (zeile, zelle) in eng.take(kBerichtZeilen))
          druckHinweis(
            '${tagText(zelle.tag)}: ${zeile.name} '
            '${zelle.auslastung >= 9.99 ? 'ohne Kapazität belegt' : '${_prozent(zelle.auslastung)} belegt'}',
            zeilen: 1,
          ),
    ];
  }
}
