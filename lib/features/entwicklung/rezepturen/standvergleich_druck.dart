import 'dart:math' as math;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/constants/artikel_merkmale.dart';
import '../../../core/database/database.dart' show RezepturVersion;
import '../../../core/druck/druck_bausteine.dart';
import '../../../core/druck/druck_optionen.dart';
import '../../../core/druck/druck_satz.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/pdf_text.dart';
import '../daten/entwicklung_repository.dart' show VersionStatus;
import '../entwicklung_format.dart';
import '../rechenkern/naehrwert_rundung.dart';
import '../rechenkern/rechen_modell.dart';
import '../rechenkern/rechenkern.dart';
import 'stand_vergleich.dart';

// Die Stände einer Rezeptur nebeneinander auf Papier: Mengen je Zutat,
// Kennzahlen und Nährwerte, was sich von Stand zu Stand geändert hat — und
// warum. Was anders ist als im Stand links daneben, steht fett.

/// Ein Stand für den Vergleich.
class VergleichStand {
  const VergleichStand({required this.version, required this.eingabe});

  final RezepturVersion version;

  /// Wie der Rechenkern ihn bekommt — abgeschlossen aus dem eingefrorenen
  /// JSON.
  final RechenRezeptur eingabe;
}

/// Was der Vergleich über die Rezeptur wissen muss.
class StandvergleichDaten {
  const StandvergleichDaten({
    required this.name,
    required this.staende,
    this.artikelnummer,
    this.freigabeVersionId,
  });

  final String name;
  final String? artikelnummer;

  /// Alle Stände der Rezeptur — in welcher Reihenfolge, ist gleich.
  final List<VergleichStand> staende;

  /// Der im Projekt freigegebene Stand.
  final String? freigabeVersionId;
}

/// Schlüssel der Wahl im Druckfenster.
abstract final class StandvergleichWahl {
  static const staende = 'staende';
  static const mengen = 'mengen';
  static const notizen = 'notizen';
  static const kennzahlen = 'kennzahlen';
  static const aenderungen = 'aenderungen';
  static const zutatenliste = 'zutatenliste';
}

/// Was auf den Vergleich kommt — die Wahl im Druckfenster.
class StandvergleichInhalt {
  const StandvergleichInhalt({
    this.anteile = false,
    this.notizen = true,
    this.kennzahlen = true,
    this.aenderungen = true,
    this.zutatenliste = false,
  });

  /// Anteile am Einsatz in Prozent statt kg.
  final bool anteile;

  /// Bezeichnung, Zustand und Grund jedes Stands.
  final bool notizen;

  /// Einsatz, Verlust, Endgewicht, Fleischanteil, BEFFE, Nährwerte und
  /// Allergene.
  final bool kennzahlen;

  /// In Sätzen, was sich zum Stand davor geändert hat.
  final bool aenderungen;

  /// Das Zutatenverzeichnis jedes Stands.
  final bool zutatenliste;
}

/// So viele Stände passen nebeneinander.
const int kStaendeNebeneinander = 8;

/// „Entwurf", „abgeschlossen am 12.10.2026", „freigegeben".
String standZustand(RezepturVersion v, {bool freigegeben = false}) {
  if (freigegeben) return 'freigegeben';
  if (v.status != VersionStatus.abgeschlossen) return 'Entwurf';
  final am = v.abgeschlossenAm;
  return am == null ? 'abgeschlossen' : 'abgeschlossen am ${Format.datum(am)}';
}

/// „Stand 3 · Weniger Salz".
String _standName(RezepturVersion v) {
  final bez = v.bezeichnung?.trim() ?? '';
  return bez.isEmpty ? 'Stand ${v.nummer}' : 'Stand ${v.nummer} · $bez';
}

/// Der Vergleich der Stände [ids] von [daten] zum Drucken — in der
/// Reihenfolge der Nummern.
DruckDokument standvergleichDruck(
  StandvergleichDaten daten,
  Set<String> ids, {
  StandvergleichInhalt inhalt = const StandvergleichInhalt(),
  DateTime? gedrucktAm,
}) {
  final staende = [
    for (final s in daten.staende)
      if (ids.contains(s.version.id)) s,
  ]..sort((a, b) => a.version.nummer.compareTo(b.version.nummer));
  if (staende.length < 2) {
    throw const DruckNichtsGewaehlt('Wähle mindestens zwei Stände.');
  }
  if (staende.length > kStaendeNebeneinander) {
    throw const DruckNichtsGewaehlt(
      'Höchstens $kStaendeNebeneinander Stände passen nebeneinander.',
    );
  }
  final blatt = _Vergleich(
    daten,
    staende,
    inhalt,
    druckGedruckt(gedrucktAm ?? DateTime.now()),
  );
  final titel = 'Rezeptur ${daten.name} Staende '
      '${[for (final s in staende) s.version.nummer].join('-')}';
  return DruckDokument(
    titel: 'Stände im Vergleich ${daten.name}',
    dateiname: druckDateiname(titel),
    blaetter: [blatt.blatt()],
  );
}

/// Der Vergleich für das Druckfenster. Vorgewählt sind [vorwahl] — ohne
/// (oder mit weniger als zwei davon) die beiden neuesten Stände.
DruckAuftrag standvergleichDruckAuftrag(
  StandvergleichDaten daten, {
  Set<String> vorwahl = const {},
  DateTime? gedrucktAm,
}) {
  final staende = [...daten.staende]
    ..sort((a, b) => a.version.nummer.compareTo(b.version.nummer));
  final ids = {for (final s in staende) s.version.id};
  var standard = vorwahl.intersection(ids);
  if (standard.length < 2) {
    standard = {
      for (final s in staende.reversed.take(2)) s.version.id,
    };
  }
  return DruckAuftrag(
    art: 'standvergleich',
    titel: 'Stände vergleichen und drucken',
    untertitel: daten.name,
    optionen: [
      DruckWahlMehrere(
        schluessel: StandvergleichWahl.staende,
        titel: 'Stände',
        hinweis: 'Zwei bis $kStaendeNebeneinander nebeneinander',
        werte: [
          for (final s in staende)
            DruckWert(
              s.version.id,
              _standName(s.version),
              hinweis: standZustand(
                s.version,
                freigegeben: s.version.id == daten.freigabeVersionId,
              ),
            ),
        ],
        standard: standard,
        merken: false,
      ),
      const DruckWahlEins(
        schluessel: StandvergleichWahl.mengen,
        titel: 'Mengen',
        werte: [
          DruckWert('kg', 'In kg je Ansatz'),
          DruckWert(
            'anteile',
            'Anteile in Prozent',
            hinweis: 'Gut zu vergleichen, wenn sich die Ansatzgröße ändert',
          ),
        ],
        standard: 'kg',
      ),
      const DruckSchalter(
        schluessel: StandvergleichWahl.notizen,
        titel: 'Die Stände',
        hinweis: 'Bezeichnung, Zustand und Grund für jeden Stand',
        gruppe: 'Auf dem Blatt',
      ),
      const DruckSchalter(
        schluessel: StandvergleichWahl.kennzahlen,
        titel: 'Kennzahlen und Nährwerte',
        hinweis: 'Verlust, Endgewicht, Fleischanteil, Nährwerte, Allergene',
        gruppe: 'Auf dem Blatt',
      ),
      const DruckSchalter(
        schluessel: StandvergleichWahl.aenderungen,
        titel: 'Änderungen zum Stand davor',
        hinweis: 'In Sätzen — wie im Verlauf des Projekts',
        gruppe: 'Auf dem Blatt',
      ),
      const DruckSchalter(
        schluessel: StandvergleichWahl.zutatenliste,
        titel: 'Zutatenverzeichnis je Stand',
        standard: false,
        gruppe: 'Auf dem Blatt',
      ),
    ],
    bauen: (wahl) => standvergleichDruck(
      daten,
      wahl.mehrere(StandvergleichWahl.staende),
      gedrucktAm: gedrucktAm,
      inhalt: StandvergleichInhalt(
        anteile: wahl.eins(StandvergleichWahl.mengen) == 'anteile',
        notizen: wahl.an(StandvergleichWahl.notizen),
        kennzahlen: wahl.an(StandvergleichWahl.kennzahlen),
        aenderungen: wahl.an(StandvergleichWahl.aenderungen),
        zutatenliste: wahl.an(StandvergleichWahl.zutatenliste),
      ),
    ),
  );
}

/// Eine Zeile der Zusammensetzung über alle Stände: dieselbe Zutat oder
/// Unterrezeptur, je Stand die Menge — null: nicht enthalten.
typedef _Zeile = ({String name, bool unter, List<double?> mengen});

/// Die Zeilen der Stände: in der Reihenfolge des neuesten, dann was es
/// nur früher gab. Kommt eine Zutat mehrmals vor, zählt die Summe.
List<_Zeile> _zeilen(List<RechenRezeptur> staende) {
  String schluessel(RechenPosition p) =>
      p.zutat?.id ?? 'rezeptur:${p.unterrezeptur?.id}';
  final reihenfolge = <String>[];
  final namen = <String, String>{};
  final unter = <String>{};
  for (final r in staende.reversed) {
    for (final p in r.positionen) {
      final k = schluessel(p);
      if (namen.containsKey(k)) continue;
      reihenfolge.add(k);
      namen[k] = p.zutat?.name ?? p.unterrezeptur?.name ?? '?';
      if (p.unterrezeptur != null) unter.add(k);
    }
  }
  final mengen = [for (final r in staende) _summen(r, schluessel)];
  return [
    for (final k in reihenfolge)
      (
        name: namen[k]!,
        unter: unter.contains(k),
        mengen: [for (final m in mengen) m[k]],
      ),
  ];
}

Map<String, double> _summen(
  RechenRezeptur r,
  String Function(RechenPosition p) schluessel,
) {
  final summen = <String, double>{};
  for (final p in r.positionen) {
    final k = schluessel(p);
    summen[k] = (summen[k] ?? 0) + p.mengeKg;
  }
  return summen;
}

/// Ein Wert je Stand — aus seinem Ergebnis oder seiner Eingabe.
typedef _Wert = String Function(RezepturErgebnis e, RechenRezeptur x);

/// Was anders ist als links daneben.
const PdfColor _anders = PdfColor.fromInt(0xFF1565C0);

/// Höchstens so hoch wird eine Tabellenzeile mit [zeilen] Zeilen Text.
double _zeile(int zeilen) => 8 + zeilen * 10.5;

/// Wie viele Zeilen [text] bei 8,5 Punkt in der Breite [breite] braucht
/// — grob geschätzt, höchstens [hoechstens].
int _zeilenFuer(String text, double breite, {int hoechstens = 2}) {
  final jeZeile = math.max(20, (breite - 24) / (8.5 * .55));
  return (text.length / jeZeile).ceil().clamp(1, hoechstens);
}

/// Abstand vor jedem Abschnitt — davor, nicht danach: Ein Abstand am Ende
/// des Inhalts, der nicht mehr auf die Seite passt, gäbe eine leere Seite.
const double _abstand = 6;

/// Überschrift und Kopfzeile einer Tabelle, Abstand davor.
const double _umTabelle = 60;

/// Kopf und Fuß des Blatts.
const double _kopfUndFuss = 80;

/// So breit wird die Spalte eines Stands höchstens und mindestens.
const double _standBreit = 110;
const double _standSchmal = 50;

/// So viel Platz bleibt mindestens für den Namen der Zutat.
const double _namenBreite = 180;

class _Vergleich {
  _Vergleich(this.daten, this.staende, this.inhalt, this.gedruckt)
      : ergebnisse = [for (final s in staende) berechne(s.eingabe)];

  final StandvergleichDaten daten;
  final List<VergleichStand> staende;
  final StandvergleichInhalt inhalt;
  final String gedruckt;
  final List<RezepturErgebnis> ergebnisse;

  /// Was [hoehe] hoch ist, passt auf eine Seite — dann bleibt es
  /// zusammen.
  bool zusammen(DruckRahmen r, double hoehe) =>
      _kopfUndFuss + hoehe <= r.hoehe;

  bool freigegeben(VergleichStand s) =>
      s.version.id == daten.freigabeVersionId;

  DruckBlatt blatt() {
    final nummer = daten.artikelnummer?.trim() ?? '';
    final nummern = [for (final s in staende) s.version.nummer];
    final zeile = [
      if (nummer.isNotEmpty) 'Art.-Nr. $nummer',
      'Stände ${nummern.take(nummern.length - 1).join(', ')} und '
          '${nummern.last} im Vergleich',
    ].join(' · ');
    return DruckBlatt(
      quer: true,
      bauen: (r) {
        final teile = <pw.Widget>[
          druckHinweis(
            inhalt.anteile
                ? 'Mengen als Anteil am Einsatz in Prozent. Fett: anders als '
                    'im Stand links daneben.'
                : 'Mengen in kg je Ansatz. Fett: anders als im Stand links '
                    'daneben.',
            zeilen: 2,
          ),
          pw.SizedBox(height: 4),
          if (inhalt.notizen) ...dieStaende(r),
          ...zusammensetzung(r),
          if (inhalt.kennzahlen) ...kennzahlen(r),
          if (inhalt.aenderungen) ...aenderungen(r),
          if (inhalt.zutatenliste) ...zutatenlisten(),
        ];
        return DruckSeiten(
          kopf: (ctx) => druckKopf(
            titel: daten.name,
            zeile: zeile,
            gedruckt: gedruckt,
          ),
          fuss: (ctx) => druckFuss(
            'Stände im Vergleich · ${daten.name}',
            r.seitenText(ctx),
          ),
          inhalt: (ctx) => teile,
        );
      },
    );
  }

  // ── Bausteine ─────────────────────────────────────────────────────────

  /// Spaltenbreiten: vorn der Name, je Stand eine gleich breite Spalte —
  /// bei wenigen Ständen nicht breiter als nötig.
  Map<int, pw.TableColumnWidth> breiten(DruckRahmen r) {
    final je = ((r.breite - _namenBreite) / staende.length)
        .clamp(_standSchmal, _standBreit)
        .toDouble();
    return {
      0: const pw.FlexColumnWidth(),
      for (var i = 1; i <= staende.length; i++) i: pw.FixedColumnWidth(je),
    };
  }

  /// Die Kopfzeile: je Stand Nummer und Zustand.
  pw.TableRow kopfzeile(String titel) => druckKopfzeile([
        druckKopfZelle(titel),
        for (final s in staende)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  pdfText('Stand ${s.version.nummer}'),
                  maxLines: 1,
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  pdfText(
                    freigegeben(s)
                        ? 'freigegeben'
                        : s.version.status == VersionStatus.abgeschlossen
                            ? 'abgeschlossen'
                            : 'Entwurf',
                  ),
                  maxLines: 1,
                  style: const pw.TextStyle(fontSize: 7, color: kDruckGrau),
                ),
              ],
            ),
          ),
      ]);

  /// Eine Zeile: vorn [titel], je Stand [werte] — fett, was anders ist als
  /// links daneben.
  pw.TableRow reihe(
    String titel,
    List<String> werte, {
    String? unten,
    bool betont = false,
    int zeilen = 1,
  }) {
    return pw.TableRow(
      decoration: betont
          ? const pw.BoxDecoration(color: kDruckZeilenFlaeche)
          : null,
      children: [
        if (unten == null)
          druckZelle(titel, fett: betont, groesse: 8.5)
        else
          druckZelleMitZeile(
            titel,
            unten,
            zeilenOben: 1,
            zeilenUnten: 1,
            groesse: 8.5,
          ),
        for (final (i, w) in werte.indexed)
          () {
            final anders = i > 0 && w != werte[i - 1];
            return druckZelle(
              w.isEmpty ? '-' : w,
              rechts: zeilen == 1,
              fett: anders || betont,
              farbe: anders ? _anders : PdfColors.black,
              groesse: 8.5,
              zeilen: zeilen,
            );
          }(),
      ],
    );
  }

  // ── Abschnitte ────────────────────────────────────────────────────────

  /// Bezeichnung, Zustand und Grund jedes Stands.
  List<pw.Widget> dieStaende(DruckRahmen r) {
    // Der Grund hat bis zu drei Zeilen, die Bezeichnung bis zu zwei.
    final hoehe = staende.fold<double>(0, (h, s) {
      final grund = (s.version.notiz?.trim() ?? '').isNotEmpty;
      final bez = (s.version.bezeichnung?.trim() ?? '').isNotEmpty;
      return h + _zeile(grund ? 3 : (bez ? 2 : 1));
    });
    return druckGruppe(
      [
        pw.SizedBox(height: _abstand),
        druckZwischentitel('Die Stände'),
        pw.Table(
          border: kDruckGitter,
          columnWidths: const {
            0: pw.FixedColumnWidth(48),
            1: pw.FlexColumnWidth(1.4),
            2: pw.FixedColumnWidth(150),
            3: pw.FlexColumnWidth(3),
          },
          children: [
            druckKopfzeile([
              druckKopfZelle('Stand'),
              druckKopfZelle('Bezeichnung'),
              druckKopfZelle('Zustand'),
              druckKopfZelle('Grund für den Stand'),
            ]),
            for (final s in staende)
              pw.TableRow(
                children: [
                  druckZelle('${s.version.nummer}', fett: true, groesse: 8.5),
                  druckZelle(
                    s.version.bezeichnung?.trim() ?? '',
                    groesse: 8.5,
                    zeilen: 2,
                  ),
                  druckZelle(
                    standZustand(s.version, freigegeben: freigegeben(s)),
                    groesse: 8.5,
                  ),
                  druckZelle(
                    s.version.notiz?.trim() ?? '',
                    groesse: 8.5,
                    zeilen: 3,
                  ),
                ],
              ),
          ],
        ),
      ],
      zusammen: zusammen(r, _umTabelle + hoehe),
      rahmen: r,
    );
  }

  List<pw.Widget> zusammensetzung(DruckRahmen r) {
    final eingaben = [for (final s in staende) s.eingabe];
    final zeilen = _zeilen(eingaben);
    final summen = [
      for (final e in eingaben)
        e.positionen.fold<double>(0, (s, p) => s + p.mengeKg),
    ];
    String menge(double? kg, int i) {
      if (kg == null) return '';
      if (!inhalt.anteile) return mengeText(kg);
      return summen[i] <= 0 ? '' : prozentText(kg / summen[i] * 100);
    }

    return druckGruppe(
      [
        pw.SizedBox(height: _abstand),
        druckZwischentitel('Zusammensetzung'),
        pw.Table(
          border: kDruckGitter,
          columnWidths: breiten(r),
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
          children: [
            kopfzeile('Zutat'),
            for (final z in zeilen)
              reihe(
                z.name,
                [for (final (i, m) in z.mengen.indexed) menge(m, i)],
                unten: z.unter ? 'Unterrezeptur' : null,
              ),
            reihe(
              inhalt.anteile ? 'Summe' : 'Einsatz',
              [
                for (final (i, s) in summen.indexed)
                  inhalt.anteile ? (s <= 0 ? '' : '100 %') : menge(s, i),
              ],
              betont: true,
            ),
          ],
        ),
      ],
      zusammen: zusammen(
        r,
        _umTabelle +
            _zeile(1) +
            zeilen.fold<double>(0, (h, z) => h + _zeile(z.unter ? 2 : 1)),
      ),
      rahmen: r,
    );
  }

  List<pw.Widget> kennzahlen(DruckRahmen r) {
    List<String> alle(_Wert f) => [
          for (var i = 0; i < staende.length; i++)
            f(ergebnisse[i], staende[i].eingabe),
        ];
    String naehrwert(RezepturErgebnis e, Naehrstoff s) {
      final w = naehrwertGerundet(s, naehrstoffWert(e.je100g, s));
      return w == '—' ? '' : '$w ${s.einheit}';
    }

    final zeilen = <pw.TableRow>[
      reihe(
        'Verlust',
        alle(
          (e, x) => x.verlustart == Verlustart.keiner
              ? 'keiner'
              : prozentText(x.wirksamerVerlust),
        ),
      ),
      reihe('Verlustart', alle((e, x) => x.verlustart.label)),
      if (!inhalt.anteile)
        reihe('Endgewicht', alle((e, x) => '${mengeText(e.endgewichtKg)} kg')),
      reihe(
        'Fleischanteil',
        alle((e, x) => prozentText(e.fleischanteilProzent)),
      ),
      reihe(
        'BEFFE',
        alle(
          (e, x) => switch (e.je100g.beffe) {
            null => '',
            final double b => prozentText(b),
          },
        ),
      ),
      for (final s in Naehrstoff.values)
        reihe(
          switch (s) {
            Naehrstoff.energieKj || Naehrstoff.energieKcal =>
              '${s.label} (${s.einheit})',
            _ => s.label,
          },
          alle((e, x) => naehrwert(e, s)),
        ),
      reihe(
        'Allergene',
        alle(
          (e, x) => e.allergene.isEmpty
              ? 'keine'
              : [
                  for (final a in e.allergene.keys)
                    merkmalLabel(a, kAllergene) ?? a,
                ].join(', '),
        ),
        zeilen: 3,
      ),
    ];
    return druckGruppe(
      [
        pw.SizedBox(height: _abstand),
        druckZwischentitel(
          'Kennzahlen und Nährwerte — je 100 g gerundet wie auf dem Etikett',
        ),
        pw.Table(
          border: kDruckGitter,
          columnWidths: breiten(r),
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
          children: [kopfzeile('Kennzahl'), ...zeilen],
        ),
      ],
      // Eine Zeile je Kennzahl, die Allergene mit bis zu drei.
      zusammen: zusammen(
        r,
        _umTabelle + (zeilen.length - 1) * _zeile(1) + _zeile(3),
      ),
      rahmen: r,
    );
  }

  /// Je Stand in Sätzen, was sich zum Stand links daneben geändert hat.
  List<pw.Widget> aenderungen(DruckRahmen r) {
    final teile = <pw.Widget>[];
    for (var i = 1; i < staende.length; i++) {
      final vorher = staende[i - 1];
      final s = staende[i];
      final saetze = standAenderungen(
        vorher.eingabe,
        s.eingabe,
        vorherNummer: vorher.version.nummer,
      );
      final hoehe = saetze.fold<double>(
        i == 1 ? 50 : 26,
        (h, satz) => h + _zeile(_zeilenFuer(satz, r.breite)),
      );
      teile.addAll(
        druckGruppe(
          [
            // Die Überschrift bleibt beim ersten Paar.
            if (i == 1) ...[
              pw.SizedBox(height: _abstand),
              druckZwischentitel('Änderungen zum Stand davor'),
            ],
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(4, 4, 4, 2),
              child: pw.Text(
                pdfText(
                  'Stand ${s.version.nummer} gegenüber Stand '
                  '${vorher.version.nummer}',
                ),
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            for (final satz in saetze) druckZelleMitPunkt(satz, kDruckGrau),
          ],
          zusammen: zusammen(r, hoehe),
          rahmen: r,
          frei: 80,
        ),
      );
    }
    return teile;
  }

  /// Das Zutatenverzeichnis jedes Stands — als Text, der über die Seite
  /// laufen darf.
  List<pw.Widget> zutatenlisten() {
    return [
      pw.SizedBox(height: _abstand),
      druckZwischentitel('Zutatenverzeichnis je Stand'),
      for (final (i, s) in staende.indexed) ...[
        pw.Padding(
          padding: const pw.EdgeInsets.fromLTRB(4, 8, 4, 2),
          child: pw.Text(
            pdfText(_standName(s.version)),
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.Text(
          pdfText(
            ergebnisse[i].zutatenliste.trim().isEmpty
                ? 'Ohne Zutaten.'
                : ergebnisse[i].zutatenliste.trim(),
          ),
          overflow: pw.TextOverflow.span,
          style: const pw.TextStyle(fontSize: 8.5, lineSpacing: 1.4),
        ),
      ],
    ];
  }
}
