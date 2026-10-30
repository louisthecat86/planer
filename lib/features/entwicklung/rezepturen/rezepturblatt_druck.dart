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

// Das Rezepturblatt: ein Stand einer Rezeptur auf Papier — die
// Zusammensetzung mit Mengen (wie in der Rezeptur, umgerechnet auf eine
// Ansatzgröße oder ein Endgewicht), nur mit Anteilen oder ganz ohne Mengen,
// dazu Zutatenverzeichnis, Nährwerte, Allergene und Fleisch nach LMIV. Für
// die Produktion je Zutat ein Kästchen mit Feldern für Ist-Menge und
// Charge des Rohstoffs, dazu Felder für Datum, Charge und Kürzel.

/// Wie die Mengen auf dem Blatt stehen.
enum RezepturMengen {
  /// So, wie sie in der Rezeptur stehen — je Ansatz.
  rezeptur,

  /// Umgerechnet auf einen Ansatz (Einsatz aller Zutaten) in kg.
  ansatz,

  /// Umgerechnet auf ein Endgewicht in kg — der Verlust ist eingerechnet.
  endgewicht,

  /// Nur die Anteile am Einsatz in Prozent.
  anteile,

  /// Ohne Mengen — nur die Zutaten, etwa zum Weitergeben.
  ohne;

  /// Mit Mengen in kg.
  bool get mitKg =>
      this == rezeptur || this == ansatz || this == endgewicht;

  /// Mit Anteilen in Prozent.
  bool get mitAnteil => this != ohne;
}

/// Schlüssel der Wahl im Druckfenster.
abstract final class RezepturblattWahl {
  static const mengen = 'mengen';
  static const ansatzKg = 'ansatzKg';
  static const endKg = 'endKg';
  static const kennzahlen = 'kennzahlen';
  static const notizen = 'notizen';
  static const unterrezepturen = 'unterrezepturen';
  static const zutatenliste = 'zutatenliste';
  static const naehrwerte = 'naehrwerte';
  static const allergene = 'allergene';
  static const fleisch = 'fleisch';
  static const hinweise = 'hinweise';
  static const abwiegen = 'abwiegen';
  static const herstellung = 'herstellung';
}

/// Was auf das Rezepturblatt kommt — die Wahl im Druckfenster.
class RezepturblattInhalt {
  const RezepturblattInhalt({
    this.mengen = RezepturMengen.rezeptur,
    this.kg = 100,
    this.kennzahlen = true,
    this.notizen = true,
    this.unterrezepturen = true,
    this.zutatenliste = true,
    this.naehrwerte = true,
    this.allergene = true,
    this.fleisch = true,
    this.hinweise = true,
    this.abwiegen = false,
    this.herstellung = false,
  });

  final RezepturMengen mengen;

  /// Ansatzgröße oder Endgewicht in kg — je nach [mengen].
  final double kg;

  /// Einsatz, Verlust, Endgewicht, Fleischanteil, BEFFE.
  final bool kennzahlen;

  /// Beschreibung der Rezeptur und Grund für den Stand.
  final bool notizen;

  /// Unterrezepturen mit ihren Zutaten, auf die eingesetzte Menge
  /// umgerechnet.
  final bool unterrezepturen;

  final bool zutatenliste;
  final bool naehrwerte;

  /// Allergene und Verarbeitungshilfsstoffe.
  final bool allergene;

  /// Fleisch nach LMIV je Tierart.
  final bool fleisch;

  /// Hinweise der Berechnung — fehlende Nährwerte und Ähnliches.
  final bool hinweise;

  /// Je Zutat ein Kästchen und Felder für Ist-Menge und Charge.
  final bool abwiegen;

  /// Felder für Datum, Charge, Ansatz und Kürzel.
  final bool herstellung;
}

/// Was das Blatt über den Stand wissen muss.
class RezepturblattDaten {
  const RezepturblattDaten({
    required this.name,
    required this.version,
    required this.eingabe,
    this.artikelnummer,
    this.beschreibung,
    this.freigegeben = false,
  });

  /// Name der Rezeptur.
  final String name;
  final String? artikelnummer;
  final String? beschreibung;
  final RezepturVersion version;

  /// Der Stand, wie der Rechenkern ihn bekommt — abgeschlossen aus seinem
  /// eingefrorenen JSON.
  final RechenRezeptur eingabe;

  /// Der Stand ist im Projekt freigegeben.
  final bool freigegeben;
}

/// „Stand 3 · Weniger Salz · abgeschlossen am 12.10.2026" — oder Entwurf,
/// freigegeben.
String rezepturStandText(RezepturVersion v, {bool freigegeben = false}) {
  final bez = v.bezeichnung?.trim() ?? '';
  final am = v.abgeschlossenAm;
  return [
    'Stand ${v.nummer}',
    if (bez.isNotEmpty) bez,
    if (freigegeben) 'freigegeben',
    if (v.status != VersionStatus.abgeschlossen)
      'Entwurf, geändert am ${Format.datum(v.updatedAt)}'
    else if (am != null)
      'abgeschlossen am ${Format.datum(am)}'
    else
      'abgeschlossen',
  ].join(' · ');
}

/// Der Faktor, mit dem die Mengen der Rezeptur malgenommen werden. Ohne
/// Einsatz oder Endgewicht bleibt es bei den Mengen der Rezeptur.
double rezepturFaktor(RezepturErgebnis e, RezepturblattInhalt inhalt) =>
    switch (inhalt.mengen) {
      RezepturMengen.ansatz when e.eingesetztKg > 0 =>
        inhalt.kg / e.eingesetztKg,
      RezepturMengen.endgewicht when e.endgewichtKg > 0 =>
        inhalt.kg / e.endgewichtKg,
      _ => 1,
    };

/// Das Rezepturblatt zum Drucken.
DruckDokument rezepturblattDruck(
  RezepturblattDaten daten, {
  RezepturblattInhalt inhalt = const RezepturblattInhalt(),
  DateTime? gedrucktAm,
}) {
  final blatt = _Rezepturblatt(
    daten,
    inhalt,
    druckGedruckt(gedrucktAm ?? DateTime.now()),
  );
  final titel = 'Rezeptur ${daten.name} Stand ${daten.version.nummer}';
  return DruckDokument(
    titel: titel,
    dateiname: druckDateiname(titel),
    blaetter: [blatt.blatt()],
  );
}

/// Das Rezepturblatt für das Druckfenster.
DruckAuftrag rezepturblattDruckAuftrag(
  RezepturblattDaten daten, {
  DateTime? gedrucktAm,
}) {
  final e = berechne(daten.eingabe);
  final mitUnter = daten.eingabe.positionen.any((p) => p.unterrezeptur != null);
  final mitNotizen = (daten.beschreibung?.trim() ?? '').isNotEmpty ||
      (daten.version.notiz?.trim() ?? '').isNotEmpty;
  final mitHinweisen = e.warnungen.isNotEmpty ||
      e.ohneNaehrwerte.isNotEmpty ||
      e.ohneBeffe.isNotEmpty;
  bool ist(DruckWahl w, RezepturMengen m) =>
      w.eins(RezepturblattWahl.mengen) == m.name;
  const blatt = 'Auf dem Blatt';

  return DruckAuftrag(
    art: 'rezepturblatt',
    titel: 'Rezepturblatt drucken',
    untertitel: '${daten.name} · '
        '${rezepturStandText(daten.version, freigegeben: daten.freigegeben)}',
    optionen: [
      DruckWahlEins(
        schluessel: RezepturblattWahl.mengen,
        titel: 'Mengen',
        werte: [
          DruckWert(
            RezepturMengen.rezeptur.name,
            'Wie in der Rezeptur',
            hinweis: 'Je Ansatz von ${mengeText(e.eingesetztKg)} kg',
          ),
          const DruckWert(
            'ansatz',
            'Auf eine Ansatzgröße umgerechnet',
            hinweis: 'Die Menge aller Zutaten zusammen',
          ),
          const DruckWert(
            'endgewicht',
            'Auf ein Endgewicht umgerechnet',
            hinweis: 'Was fertig herauskommen soll — der Verlust ist '
                'eingerechnet',
          ),
          const DruckWert('anteile', 'Nur Anteile in Prozent'),
          const DruckWert(
            'ohne',
            'Ohne Mengen',
            hinweis: 'Nur die Zutaten — etwa zum Weitergeben',
          ),
        ],
        standard: RezepturMengen.rezeptur.name,
      ),
      DruckZahl(
        schluessel: RezepturblattWahl.ansatzKg,
        titel: 'Ansatzgröße',
        hinweis: 'Alle Zutaten zusammen',
        standard: 100,
        einheit: 'kg',
        min: 0.01,
        max: 100000,
        sichtbar: (w) => ist(w, RezepturMengen.ansatz),
      ),
      DruckZahl(
        schluessel: RezepturblattWahl.endKg,
        titel: 'Endgewicht',
        hinweis: 'Fertige Menge nach dem Verlust',
        standard: 100,
        einheit: 'kg',
        min: 0.01,
        max: 100000,
        sichtbar: (w) => ist(w, RezepturMengen.endgewicht),
      ),
      const DruckSchalter(
        schluessel: RezepturblattWahl.kennzahlen,
        titel: 'Kennzahlen',
        hinweis: 'Einsatz, Verlust, Endgewicht, Fleischanteil, BEFFE',
        gruppe: blatt,
      ),
      if (mitNotizen)
        const DruckSchalter(
          schluessel: RezepturblattWahl.notizen,
          titel: 'Beschreibung und Grund des Stands',
          gruppe: blatt,
        ),
      if (mitUnter)
        const DruckSchalter(
          schluessel: RezepturblattWahl.unterrezepturen,
          titel: 'Unterrezepturen mit ihren Zutaten',
          hinweis: 'Auf die eingesetzte Menge umgerechnet',
          gruppe: blatt,
        ),
      const DruckSchalter(
        schluessel: RezepturblattWahl.zutatenliste,
        titel: 'Zutatenverzeichnis',
        hinweis: 'Wie auf dem Etikett',
        gruppe: blatt,
      ),
      const DruckSchalter(
        schluessel: RezepturblattWahl.naehrwerte,
        titel: 'Nährwerte je 100 g',
        gruppe: blatt,
      ),
      const DruckSchalter(
        schluessel: RezepturblattWahl.allergene,
        titel: 'Allergene und Verarbeitungshilfsstoffe',
        gruppe: blatt,
      ),
      if (e.tierarten.isNotEmpty)
        const DruckSchalter(
          schluessel: RezepturblattWahl.fleisch,
          titel: 'Fleisch nach LMIV',
          hinweis: 'Fett und Bindegewebe je Tierart',
          gruppe: blatt,
        ),
      if (mitHinweisen)
        const DruckSchalter(
          schluessel: RezepturblattWahl.hinweise,
          titel: 'Hinweise der Berechnung',
          gruppe: blatt,
        ),
      const DruckSchalter(
        schluessel: RezepturblattWahl.abwiegen,
        titel: 'Zum Abwiegen',
        hinweis: 'Je Zutat ein Kästchen, Ist-Menge und Charge',
        standard: false,
        gruppe: 'Für die Produktion',
      ),
      const DruckSchalter(
        schluessel: RezepturblattWahl.herstellung,
        titel: 'Felder für die Herstellung',
        hinweis: 'Datum, Charge, Ansatz und Kürzel von Hand',
        standard: false,
        gruppe: 'Für die Produktion',
      ),
    ],
    bauen: (wahl) {
      final mengen = RezepturMengen.values.firstWhere(
        (m) => ist(wahl, m),
        orElse: () => RezepturMengen.rezeptur,
      );
      return rezepturblattDruck(
        daten,
        gedrucktAm: gedrucktAm,
        inhalt: RezepturblattInhalt(
          mengen: mengen,
          kg: switch (mengen) {
            RezepturMengen.ansatz => wahl.zahl(RezepturblattWahl.ansatzKg),
            RezepturMengen.endgewicht => wahl.zahl(RezepturblattWahl.endKg),
            _ => 0,
          },
          kennzahlen: wahl.an(RezepturblattWahl.kennzahlen),
          notizen: mitNotizen && wahl.an(RezepturblattWahl.notizen),
          unterrezepturen:
              mitUnter && wahl.an(RezepturblattWahl.unterrezepturen),
          zutatenliste: wahl.an(RezepturblattWahl.zutatenliste),
          naehrwerte: wahl.an(RezepturblattWahl.naehrwerte),
          allergene: wahl.an(RezepturblattWahl.allergene),
          fleisch: e.tierarten.isNotEmpty && wahl.an(RezepturblattWahl.fleisch),
          hinweise: mitHinweisen && wahl.an(RezepturblattWahl.hinweise),
          abwiegen: wahl.an(RezepturblattWahl.abwiegen),
          herstellung: wahl.an(RezepturblattWahl.herstellung),
        ),
      );
    },
  );
}

/// Der Name einer Zeile der Rezeptur.
String _positionsName(RechenPosition p) =>
    p.zutat?.name ?? p.unterrezeptur?.name ?? '-';

/// Was an einer Zeile auffällt: Fleisch, Wasser, Allergene, Unterrezeptur.
String _merkmale(RechenPosition p) {
  final z = p.zutat;
  if (z == null) return 'Unterrezeptur';
  return [
    if (z.istFleisch)
      z.tierart == null ? 'Fleisch' : 'Fleisch (${z.tierart!.label})',
    if (z.istWasser) 'Wasser',
    if (z.allergene.isNotEmpty)
      merkmaleLabel(z.allergene.join(','), kAllergene),
  ].where((t) => t.isNotEmpty).join(' · ');
}

/// „Verlust 10,0 %" — oder „ohne Verlust".
String _verlustText(double prozent) =>
    prozent <= 0 ? 'ohne Verlust' : 'Verlust ${prozentText(prozent)}';

/// Eine Unterrezeptur, wie sie auf dem Blatt steht: wo sie eingesetzt ist
/// und wie viel davon fertig gebraucht wird.
typedef _Unter = ({RechenRezeptur rezeptur, String wo, double fertigKg});

/// Tiefer werden Unterrezepturen nicht aufgelöst — schützt vor einer, die
/// sich selbst enthält.
const int _tiefsteUnter = 6;

/// Alle Unterrezepturen von [r] samt ihren eigenen, in der Reihenfolge der
/// Zeilen — jede Verwendung für sich. [faktor]: so viel mal die Mengen von
/// [r]; [darin]: der Name von [r], wenn sie selbst eine Unterrezeptur ist.
List<_Unter> _unterrezepturen(
  RechenRezeptur r,
  double faktor, {
  String? darin,
  int tiefe = 0,
}) {
  if (tiefe >= _tiefsteUnter) return const [];
  final liste = <_Unter>[];
  for (final (i, p) in r.positionen.indexed) {
    final u = p.unterrezeptur;
    if (u == null || u.positionen.isEmpty) continue;
    final fertig = p.mengeKg * faktor;
    liste.add(
      (
        rezeptur: u,
        wo: darin == null ? 'Zeile ${i + 1}' : 'in $darin, Zeile ${i + 1}',
        fertigKg: fertig,
      ),
    );
    liste.addAll(
      _unterrezepturen(
        u,
        _unterFaktor(u, fertig),
        darin: u.name,
        tiefe: tiefe + 1,
      ),
    );
  }
  return liste;
}

/// So viel einsetzen, dass nach dem Verlust [fertigKg] herauskommen.
double _unterEinsatz(RechenRezeptur u, double fertigKg) {
  final verlust = u.wirksamerVerlust;
  return verlust >= 100 ? 0 : fertigKg / (1 - verlust / 100);
}

/// Der Faktor für die Mengen von [u], damit [fertigKg] herauskommen.
double _unterFaktor(RechenRezeptur u, double fertigKg) {
  final summe = u.positionen.fold<double>(0, (s, x) => s + x.mengeKg);
  return summe > 0 ? _unterEinsatz(u, fertigKg) / summe : 0;
}

const PdfColor _orange = PdfColor.fromInt(0xFFEF6C00);
const PdfColor _rot = PdfColor.fromInt(0xFFC62828);

/// Abstand vor jedem Abschnitt — davor, nicht danach: Ein Abstand am Ende
/// des Inhalts, der nicht mehr auf die Seite passt, gäbe eine leere Seite.
const double _abstand = 6;

/// Bis zu so vielen Zeichen steht das Zutatenverzeichnis im Kasten — der
/// passt dann sicher auf eine Seite, auch quer.
const int _zutatenlisteImKasten = 2500;

/// Höchstens so hoch wird eine Zeile der Zusammensetzung: eine Zeile Name,
/// eine Zeile Merkmale.
const double _zeileHoechstens = 30;

/// Was außer den Zeilen mit auf die Seite muss: Kopf und Fuß des Blatts,
/// Überschrift, Hinweis, Kopf- und Summenzeile der Tabelle — großzügig.
const double _drumherum = 170;

class _Rezepturblatt {
  _Rezepturblatt(this.daten, this.inhalt, this.gedruckt)
      : ergebnis = berechne(daten.eingabe);

  final RezepturblattDaten daten;
  final RezepturblattInhalt inhalt;
  final String gedruckt;
  final RezepturErgebnis ergebnis;

  double get faktor => rezepturFaktor(ergebnis, inhalt);

  /// Eine Tabelle mit [zeilen] Zeilen passt samt Überschrift auf eine
  /// Seite — dann bleibt sie zusammen.
  bool zusammen(DruckRahmen r, int zeilen) =>
      _drumherum + zeilen * _zeileHoechstens <= r.hoehe;

  DruckBlatt blatt() {
    final v = daten.version;
    final nummer = daten.artikelnummer?.trim() ?? '';
    final zeile = [
      if (nummer.isNotEmpty) 'Art.-Nr. $nummer',
      rezepturStandText(v, freigegeben: daten.freigegeben),
    ].join(' · ');
    return DruckBlatt(
      rand: const pw.EdgeInsets.fromLTRB(32, 28, 32, 22),
      bauen: (r) {
        final teile = <pw.Widget>[
          ...vorspann(),
          if (inhalt.herstellung) ...herstellungKopf(),
          ...zusammensetzung(r),
          if (inhalt.unterrezepturen) ...unterrezepturen(r),
          if (inhalt.zutatenliste) ...zutatenliste(),
          if (inhalt.naehrwerte) ...naehrwerte(),
          if (inhalt.allergene) ...allergene(r),
          if (inhalt.fleisch) ...fleisch(),
          if (inhalt.hinweise) ...hinweise(r),
          if (inhalt.herstellung) ...herstellungFuss(),
        ];
        return DruckSeiten(
          kopf: (ctx) => druckKopf(
            titel: daten.name,
            zeile: zeile,
            gedruckt: gedruckt,
          ),
          fuss: (ctx) => druckFuss(
            'Rezepturblatt · ${daten.name} · Stand ${v.nummer}',
            r.seitenText(ctx),
          ),
          inhalt: (ctx) => teile,
        );
      },
    );
  }

  // ── Vorspann ──────────────────────────────────────────────────────────

  /// Ob es ein Entwurf ist, wie die Mengen gemeint sind, die Kennzahlen.
  List<pw.Widget> vorspann() {
    final e = ergebnis;
    final f = faktor;
    final eingabe = daten.eingabe;
    final v = daten.version;
    final String? mengenText = switch (inhalt.mengen) {
      RezepturMengen.rezeptur =>
        'Mengen je Ansatz von ${mengeText(e.eingesetztKg)} kg — wie in der '
            'Rezeptur.',
      RezepturMengen.ansatz =>
        'Umgerechnet auf einen Ansatz von ${mengeText(e.eingesetztKg * f)} kg '
            '(Rezeptur: ${mengeText(e.eingesetztKg)} kg).',
      RezepturMengen.endgewicht when e.endgewichtKg <= 0 =>
        'Ohne Endgewicht lässt sich nicht umrechnen — Mengen wie in der '
            'Rezeptur.',
      RezepturMengen.endgewicht =>
        'Umgerechnet auf ${mengeText(e.endgewichtKg * f)} kg Endgewicht — '
            'dafür ${mengeText(e.eingesetztKg * f)} kg Einsatz.',
      RezepturMengen.anteile => 'Anteile am Einsatz in Prozent.',
      RezepturMengen.ohne => null,
    };
    final keiner = eingabe.verlustart == Verlustart.keiner;
    final beschreibung = daten.beschreibung?.trim() ?? '';
    final grund = v.notiz?.trim() ?? '';
    final beffe = e.je100g.beffe;
    final mitKg = inhalt.mengen.mitKg;
    return [
      if (v.status != VersionStatus.abgeschlossen)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: druckZelleMitPunkt(
            'Entwurf — noch nicht abgeschlossen. Die Mengen können sich '
            'noch ändern.',
            _orange,
            fett: true,
            groesse: 9,
          ),
        ),
      if (mengenText != null)
        pw.Padding(
          padding: const pw.EdgeInsets.fromLTRB(4, 0, 4, 2),
          child: pw.Text(
            pdfText(mengenText),
            style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold),
          ),
        ),
      if (inhalt.notizen && beschreibung.isNotEmpty)
        druckHinweis(beschreibung, zeilen: 3),
      if (inhalt.notizen && grund.isNotEmpty)
        druckHinweis('Grund für diesen Stand: $grund', zeilen: 3),
      pw.SizedBox(height: 6),
      if (inhalt.kennzahlen)
        druckKennzahlen([
          if (mitKg)
            DruckKennzahl(
              '${mengeText(e.eingesetztKg * f)} kg',
              'Einsatz',
              betont: true,
            ),
          DruckKennzahl(
            keiner ? 'keiner' : prozentText(eingabe.wirksamerVerlust),
            keiner ? 'Verlust' : 'Verlust (${eingabe.verlustart.label})',
          ),
          if (mitKg)
            DruckKennzahl(
              '${mengeText(e.endgewichtKg * f)} kg',
              'Endgewicht',
              betont: true,
            ),
          DruckKennzahl(prozentText(e.fleischanteilProzent), 'Fleischanteil'),
          if (beffe != null)
            DruckKennzahl(
              prozentText(beffe),
              e.ohneBeffe.isEmpty ? 'BEFFE' : 'BEFFE (unvollständig)',
            ),
        ]),
    ];
  }

  // ── Zusammensetzung ───────────────────────────────────────────────────

  /// Eine Tabelle der Zeilen [positionen] — Mengen mal [f], Anteile an
  /// ihrer Summe.
  pw.Widget tabelle(List<RechenPosition> positionen, {required double f}) {
    final mitKg = inhalt.mengen.mitKg;
    final mitAnteil = inhalt.mengen.mitAnteil;
    final abwiegen = inhalt.abwiegen;
    final summe = positionen.fold<double>(0, (s, p) => s + p.mengeKg);
    final breiten = <pw.TableColumnWidth>[
      if (abwiegen) const pw.FixedColumnWidth(18),
      const pw.FixedColumnWidth(22),
      const pw.FlexColumnWidth(),
      if (mitKg) const pw.FixedColumnWidth(68),
      if (mitAnteil) const pw.FixedColumnWidth(50),
      if (abwiegen) ...const [
        pw.FixedColumnWidth(56),
        pw.FixedColumnWidth(84),
      ],
    ];
    // Ist-Menge und Charge — leer, zum Schreiben. Jede Zeile eigene
    // Widgets: Das PDF merkt sich in ihnen, wo sie stehen.
    List<pw.Widget> leer() => [
          if (abwiegen) ...[pw.SizedBox(), pw.SizedBox()],
        ];
    return pw.Table(
      border: kDruckGitter,
      columnWidths: breiten.asMap(),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        druckKopfzeile([
          if (abwiegen) pw.SizedBox(),
          druckKopfZelle('Nr.', rechts: true),
          druckKopfZelle('Zutat'),
          if (mitKg) druckKopfZelle(abwiegen ? 'Soll' : 'Menge', rechts: true),
          if (mitAnteil) druckKopfZelle('Anteil', rechts: true),
          if (abwiegen) ...[
            druckKopfZelle('Ist'),
            druckKopfZelle('Rohstoff-Charge'),
          ],
        ]),
        for (final (i, p) in positionen.indexed)
          pw.TableRow(
            children: [
              if (abwiegen)
                pw.Padding(
                  padding: const pw.EdgeInsets.fromLTRB(5, 3, 3, 3),
                  child: druckKaestchen(),
                ),
              druckZelle(
                '${i + 1}',
                rechts: true,
                farbe: kDruckGrau,
                groesse: 8.5,
              ),
              pw.Container(
                constraints: pw.BoxConstraints(minHeight: abwiegen ? 22 : 0),
                alignment: pw.Alignment.centerLeft,
                child: druckZelleMitZeile(
                  _positionsName(p),
                  _merkmale(p),
                  zeilenOben: 1,
                  zeilenUnten: 1,
                ),
              ),
              if (mitKg)
                druckZelle(
                  '${mengeText(p.mengeKg * f)} kg',
                  rechts: true,
                  fett: true,
                ),
              if (mitAnteil)
                druckZelle(
                  summe <= 0 ? '' : prozentText(p.mengeKg / summe * 100),
                  rechts: true,
                  groesse: 8.5,
                ),
              ...leer(),
            ],
          ),
        if (mitKg || mitAnteil)
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: kDruckZeilenFlaeche),
            children: [
              if (abwiegen) pw.SizedBox(),
              pw.SizedBox(),
              druckZelle('Summe', fett: true),
              if (mitKg)
                druckZelle(
                  '${mengeText(summe * f)} kg',
                  rechts: true,
                  fett: true,
                ),
              if (mitAnteil)
                druckZelle(
                  summe <= 0 ? '' : '100 %',
                  rechts: true,
                  fett: true,
                  groesse: 8.5,
                ),
              ...leer(),
            ],
          ),
      ],
    );
  }

  List<pw.Widget> zusammensetzung(DruckRahmen r) {
    final positionen = daten.eingabe.positionen;
    if (positionen.isEmpty) {
      return [
        pw.SizedBox(height: _abstand),
        druckZwischentitel('Zusammensetzung'),
        druckHinweis('Noch keine Zeilen.'),
      ];
    }
    return druckGruppe(
      [
        pw.SizedBox(height: _abstand),
        druckZwischentitel('Zusammensetzung'),
        tabelle(positionen, f: faktor),
      ],
      zusammen: zusammen(r, positionen.length),
      rahmen: r,
    );
  }

  /// Je Unterrezeptur ihre Zutaten — so viel, wie für die eingesetzte
  /// fertige Menge nötig ist; auch die Unterrezepturen darin.
  List<pw.Widget> unterrezepturen(DruckRahmen r) {
    final mitKg = inhalt.mengen.mitKg;
    return [
      for (final u in _unterrezepturen(daten.eingabe, faktor))
        ...druckGruppe(
          [
            pw.SizedBox(height: _abstand),
            druckZwischentitel('Unterrezeptur: ${u.rezeptur.name}'),
            druckHinweis(
              [
                u.wo,
                if (mitKg) 'für ${mengeText(u.fertigKg)} kg fertig',
                _verlustText(u.rezeptur.wirksamerVerlust),
                if (mitKg)
                  'Einsatz ${mengeText(_unterEinsatz(u.rezeptur, u.fertigKg))}'
                      ' kg',
              ].join(' · '),
              zeilen: 2,
            ),
            tabelle(
              u.rezeptur.positionen,
              f: _unterFaktor(u.rezeptur, u.fertigKg),
            ),
          ],
          zusammen: zusammen(r, u.rezeptur.positionen.length),
          rahmen: r,
        ),
    ];
  }

  // ── Ergebnis ──────────────────────────────────────────────────────────

  /// Im Kasten mit der Überschrift zusammen — ist das Verzeichnis zu lang
  /// für eine Seite, als Text, der über die Seite läuft.
  List<pw.Widget> zutatenliste() {
    final text = ergebnis.zutatenliste.trim();
    const titel = 'Zutatenverzeichnis';
    const stil = pw.TextStyle(fontSize: 9, lineSpacing: 1.5);
    if (text.isEmpty) {
      return [
        pw.SizedBox(height: _abstand),
        druckZwischentitel(titel),
        druckHinweis('Ohne Zutaten.'),
      ];
    }
    if (text.length > _zutatenlisteImKasten) {
      return [
        pw.SizedBox(height: _abstand),
        druckZwischentitel(titel),
        pw.Text(pdfText(text), style: stil, overflow: pw.TextOverflow.span),
      ];
    }
    return [
      pw.Inseparable(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.SizedBox(height: _abstand),
            druckZwischentitel(titel),
            pw.Container(
              padding: const pw.EdgeInsets.all(7),
              decoration: const pw.BoxDecoration(
                border: pw.Border.fromBorderSide(kDruckLinie),
              ),
              child: pw.Text(pdfText(text), style: stil),
            ),
          ],
        ),
      ),
    ];
  }

  List<pw.Widget> naehrwerte() {
    final n = ergebnis.je100g;
    String wert(Naehrstoff s) {
      final w = naehrwertGerundet(s, naehrstoffWert(n, s));
      return w == '—' ? '-' : '$w ${s.einheit}';
    }

    final zeilen = <(String, String, bool)>[
      (
        'Energie',
        '${wert(Naehrstoff.energieKj)} / ${wert(Naehrstoff.energieKcal)}',
        false,
      ),
      ('Fett', wert(Naehrstoff.fett), false),
      (
        'davon gesättigte Fettsäuren',
        wert(Naehrstoff.gesaettigteFettsaeuren),
        true,
      ),
      ('Kohlenhydrate', wert(Naehrstoff.kohlenhydrate), false),
      ('davon Zucker', wert(Naehrstoff.zucker), true),
      ('Eiweiß', wert(Naehrstoff.eiweiss), false),
      ('Salz', wert(Naehrstoff.salz), false),
    ];
    return [
      pw.Inseparable(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(height: _abstand),
            druckZwischentitel(
              'Nährwerte je 100 g — gerundet wie auf dem Etikett',
            ),
            pw.SizedBox(
              width: 300,
              child: pw.Table(
                border: kDruckGitter,
                columnWidths: const {
                  0: pw.FlexColumnWidth(),
                  1: pw.FixedColumnWidth(110),
                },
                children: [
                  for (final (label, w, davon) in zeilen)
                    pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: pw.EdgeInsets.only(left: davon ? 10 : 0),
                          child: druckZelle(
                            label,
                            groesse: 8.5,
                            farbe: davon ? kDruckGrau : PdfColors.black,
                          ),
                        ),
                        druckZelle(w, rechts: true, groesse: 8.5),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<pw.Widget> allergene(DruckRahmen r) {
    final a = ergebnis.allergene;
    final h = ergebnis.verarbeitungshilfsstoffe;
    return druckGruppe(
      [
        pw.SizedBox(height: _abstand),
        druckZwischentitel('Allergene und Verarbeitungshilfsstoffe'),
        if (a.isEmpty)
          druckHinweis('Keine Allergene aus den Zutaten.')
        else
          for (final MapEntry(:key, :value) in a.entries)
            druckZelleMitPunkt(
              '${merkmalLabel(key, kAllergene) ?? key} (${value.join(', ')})',
              _orange,
              zeilen: 3,
            ),
        for (final MapEntry(:key, :value) in h.entries)
          druckHinweis(
            'Verarbeitungshilfsstoff: $key (${value.join(', ')})',
            zeilen: 2,
          ),
      ],
      zusammen: a.length + h.length <= 8,
      rahmen: r,
    );
  }

  List<pw.Widget> fleisch() {
    final t = ergebnis.tierarten;
    if (t.isEmpty) return const [];
    final mitKg = inhalt.mengen.mitKg;
    final f = faktor;
    final breiten = <pw.TableColumnWidth>[
      const pw.FlexColumnWidth(1.2),
      if (mitKg) const pw.FixedColumnWidth(64),
      const pw.FlexColumnWidth(1.3),
      const pw.FlexColumnWidth(1.5),
      if (mitKg) const pw.FixedColumnWidth(70),
    ];
    return [
      pw.Inseparable(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.SizedBox(height: _abstand),
            druckZwischentitel(
              'Fleisch nach LMIV — Grenzwerte für Fett und Bindegewebe',
            ),
            pw.Table(
              border: kDruckGitter,
              columnWidths: breiten.asMap(),
              defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
              children: [
                druckKopfzeile([
                  druckKopfZelle('Tierart'),
                  if (mitKg) druckKopfZelle('Masse', rechts: true),
                  druckKopfZelle('Fett'),
                  druckKopfZelle('Bindegewebe'),
                  if (mitKg) druckKopfZelle('als Fleisch', rechts: true),
                ]),
                for (final x in t)
                  pw.TableRow(
                    children: [
                      druckZelle(x.tierart.label, groesse: 8.5),
                      if (mitKg)
                        druckZelle(
                          '${mengeText(x.masseKg * f)} kg',
                          rechts: true,
                          groesse: 8.5,
                        ),
                      druckZelle(
                        '${prozentText(x.fettProzent)} (Grenze '
                        '${Format.zahl(x.tierart.fettGrenze)} %)',
                        groesse: 8.5,
                        fett: x.fettUeberGrenze,
                        farbe: x.fettUeberGrenze ? _rot : PdfColors.black,
                      ),
                      druckZelle(
                        switch (x.kollagenVerhaeltnis) {
                          null => 'nicht geprüft',
                          final double k => '${prozentText(k)} (Grenze '
                              '${Format.zahl(x.tierart.bindegewebeGrenze)} %)',
                        },
                        groesse: 8.5,
                        fett: x.bindegewebeUeberGrenze,
                        farbe:
                            x.bindegewebeUeberGrenze ? _rot : PdfColors.black,
                      ),
                      if (mitKg)
                        druckZelle(
                          '${mengeText(x.fleischKg * f)} kg',
                          rechts: true,
                          groesse: 8.5,
                        ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  List<pw.Widget> hinweise(DruckRahmen r) {
    final e = ergebnis;
    final punkte = [
      ...e.warnungen,
      if (e.ohneNaehrwerte.isNotEmpty)
        'Ohne Nährwerte: ${e.ohneNaehrwerte.join(', ')} — die Tabelle ist '
            'zu niedrig.',
      if (e.ohneBeffe.isNotEmpty)
        'Ohne BEFFE-Wert: ${e.ohneBeffe.join(', ')} — das BEFFE ist zu '
            'niedrig.',
    ];
    return druckGruppe(
      [
        pw.SizedBox(height: _abstand),
        druckZwischentitel('Hinweise der Berechnung'),
        for (final p in punkte) druckZelleMitPunkt(p, _orange),
      ],
      zusammen: punkte.length <= 10,
      rahmen: r,
    );
  }

  /// Felder, in die bei der Herstellung von Hand geschrieben wird — vor
  /// der Zusammensetzung.
  List<pw.Widget> herstellungKopf() {
    pw.Widget feld(String titel) => pw.Expanded(child: druckSchreibfeld(titel));
    return [
      pw.Inseparable(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            druckZwischentitel('Herstellung'),
            pw.Row(
              children: [
                feld('Hergestellt am'),
                pw.SizedBox(width: 6),
                feld('Charge'),
                pw.SizedBox(width: 6),
                feld('Ansatz in kg'),
                pw.SizedBox(width: 6),
                feld('Kürzel'),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  /// Platz für eine Bemerkung — am Ende des Blatts.
  List<pw.Widget> herstellungFuss() => [
        pw.Inseparable(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.SizedBox(height: _abstand + 6),
              druckSchreibfeld('Bemerkung zur Herstellung', hoehe: 52),
            ],
          ),
        ),
      ];
}
