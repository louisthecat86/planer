import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/constants/artikel_merkmale.dart';
import '../../../core/constants/parameter_namen.dart'
    show kPlattenGruppeKombi, plattenZeilenFuer;
import '../../../core/constants/product_groups.dart';
import '../../../core/database/database.dart';
import '../../../core/druck/druck_layout.dart';
import '../../../core/druck/druck_optionen.dart';
import '../../../core/druck/druck_satz.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/pdf_text.dart';
import '../../../core/utils/platten_raster_pdf.dart';
import '../daten/entwicklung_repository.dart' show VersionStatus;
import '../entwicklung_format.dart';
import '../haccp/haccp_modell.dart';
import '../haccp/prozess_kette.dart';
import '../haccp/prozess_modell.dart';
import '../projekte/entwicklungsstrang.dart';
import '../projekte/faellig.dart';
import '../projekte/projekt_checkliste.dart';
import '../projekte/projekt_modell.dart';
import '../rechenkern/naehrwert_rundung.dart';
import '../rechenkern/rechen_modell.dart';
import '../rechenkern/rechenkern.dart';
import '../spezifikation/spez_angaben.dart';
import 'projekt_bericht.dart';

// Der Projektbericht als PDF — eine Projektakte zum Nachschlagen: vorn ein
// Steckbrief mit dem Stand auf einen Blick und dem Inhalt, dahinter je ein
// Kapitel für Projekt, Rezeptur, Produkt, Herstellung, Freigabe, den
// Entwicklungsweg, den ganzen Verlauf und die Dateien. Was fehlt, steht
// als Hinweis da — so sieht man auch bei einem offenen Projekt, was noch
// aussteht.
//
// Gesetzt wird zweimal (das erledigt der Satz, druck_satz.dart): Der erste
// Durchgang findet die Seiten der Kapitel für das Inhaltsverzeichnis, der
// zweite schreibt sie hinein. Die Zahlen stehen in Feldern fester Breite —
// beide Durchgänge brechen gleich um.
//
// Was in den Bericht kommt, wählt das Druckfenster ([BerichtInhalt]).

// ── Farben und Schrift ─────────────────────────────────────────────────

const PdfColor _akzent = PdfColor.fromInt(0xFF1F4E79);
const PdfColor _akzentHell = PdfColor.fromInt(0xFFE9F0F7);
const PdfColor _schwarz = PdfColor.fromInt(0xFF1B1F23);
const PdfColor _grau = PdfColor.fromInt(0xFF5F6670);
const PdfColor _hellgrau = PdfColor.fromInt(0xFF9AA1A9);
const PdfColor _linie = PdfColor.fromInt(0xFFD5DAE0);
const PdfColor _flaeche = PdfColor.fromInt(0xFFF4F6F8);
const PdfColor _ok = PdfColor.fromInt(0xFF2E7D32);
const PdfColor _warn = PdfColor.fromInt(0xFFA35F00);
const PdfColor _fehler = PdfColor.fromInt(0xFFC62828);
const PdfColor _station = PdfColor.fromInt(0xFF6A3FA0);

/// Die Farbe einer Phase.
PdfColor _phasenFarbe(ProjektStatus s) => switch (s) {
  ProjektStatus.entwicklung => const PdfColor.fromInt(0xFF1565C0),
  ProjektStatus.validierung => _warn,
  ProjektStatus.produktion => _ok,
  ProjektStatus.archiviert => _grau,
};

/// Die Phase kurz: „Entwicklung", „Validierung" …
String _phasenName(ProjektStatus s) => switch (s) {
  ProjektStatus.entwicklung => 'Entwicklung',
  ProjektStatus.validierung => 'Validierung',
  ProjektStatus.produktion => 'Produktion',
  ProjektStatus.archiviert => 'Archiviert',
};

pw.Widget _t(
  String text, {
  double groesse = 9,
  bool fett = false,
  bool kursiv = false,
  PdfColor farbe = _schwarz,
  int? maxLines,
  pw.TextAlign? ausrichtung,
  double? sperrung,
}) => pw.Text(
  pdfText(text),
  maxLines: maxLines,
  textAlign: ausrichtung,
  style: pw.TextStyle(
    fontSize: groesse,
    color: farbe,
    fontWeight: fett ? pw.FontWeight.bold : pw.FontWeight.normal,
    fontStyle: kursiv ? pw.FontStyle.italic : pw.FontStyle.normal,
    letterSpacing: sperrung,
  ),
);

/// Ein Absatz, der über das Seitenende hinauslaufen darf — nur direkt in
/// der Seite (auch eingerückt), nicht in Zeilen, Tabellen oder Kästen.
pw.Widget _fliess(
  String text, {
  double groesse = 9,
  PdfColor farbe = _schwarz,
  double einzug = 0,
}) => pw.Padding(
  padding: pw.EdgeInsets.only(left: einzug),
  child: pw.Text(
    pdfText(text),
    overflow: pw.TextOverflow.span,
    style: pw.TextStyle(fontSize: groesse, color: farbe, lineSpacing: 1.2),
  ),
);

/// Ein Hinweis, dass etwas fehlt.
pw.Widget _leer(String text) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(vertical: 3),
  child: _t(text, kursiv: true, farbe: _grau),
);

String _zahl(double? w, {int nachkomma = 1}) =>
    w == null || !w.isFinite ? '' : Format.zahl(w, nachkomma: nachkomma);

/// Eine Vorgabe: ganze Zahlen ohne Nachkommastelle — „9", „0,97".
String _vorgabe(double w, {int nachkomma = 1}) =>
    w == w.roundToDouble() ? Format.zahl(w) : _zahl(w, nachkomma: nachkomma);

String _datum(DateTime? d) => d == null ? '' : Format.datum(d);

String? _oderNull(String? text) {
  final t = text?.trim() ?? '';
  return t.isEmpty ? null : t;
}

/// Das Produktbild für das PDF — null, wenn es fehlt oder das Format
/// unbekannt ist.
pw.ImageProvider? _bildAus(Uint8List? bytes) {
  if (bytes == null || bytes.isEmpty) return null;
  try {
    return pw.MemoryImage(bytes);
  } catch (_) {
    return null;
  }
}

// ── Bausteine ──────────────────────────────────────────────────────────

/// Ein Zustand, als kleines Zeichen gesetzt.
enum _Zeichen { erledigt, offen, trifftNichtZu, spaeter, verfehlt }

/// Ein Kästchen: grün mit Haken, leer, mit Strich (trifft nicht zu,
/// zurückgestellt) oder rot mit Kreuz.
pw.Widget _zeichen(_Zeichen z, {double groesse = 8.5}) => pw.SizedBox(
  width: groesse,
  height: groesse,
  child: pw.CustomPaint(
    size: PdfPoint(groesse, groesse),
    painter: (canvas, size) {
      final g = size.x;
      final r = g * .18;
      switch (z) {
        case _Zeichen.erledigt:
        case _Zeichen.verfehlt:
          canvas
            ..setFillColor(z == _Zeichen.erledigt ? _ok : _fehler)
            ..drawRRect(0, 0, g, g, r, r)
            ..fillPath()
            ..setStrokeColor(PdfColors.white)
            ..setLineWidth(g * .14)
            ..setLineCap(PdfLineCap.round)
            ..setLineJoin(PdfLineJoin.round);
          if (z == _Zeichen.erledigt) {
            canvas
              ..moveTo(g * .24, g * .52)
              ..lineTo(g * .43, g * .31)
              ..lineTo(g * .77, g * .72)
              ..strokePath();
          } else {
            canvas
              ..moveTo(g * .3, g * .3)
              ..lineTo(g * .7, g * .7)
              ..moveTo(g * .3, g * .7)
              ..lineTo(g * .7, g * .3)
              ..strokePath();
          }
        case _Zeichen.offen:
        case _Zeichen.trifftNichtZu:
        case _Zeichen.spaeter:
          final farbe = z == _Zeichen.spaeter ? _warn : _hellgrau;
          canvas
            ..setStrokeColor(farbe)
            ..setLineWidth(.8)
            ..drawRRect(.4, .4, g - .8, g - .8, r, r)
            ..strokePath();
          if (z != _Zeichen.offen) {
            canvas
              ..setLineWidth(g * .12)
              ..setLineCap(PdfLineCap.round)
              ..moveTo(g * .28, g * .5)
              ..lineTo(g * .72, g * .5)
              ..strokePath();
          }
      }
    },
  ),
);

/// Eine kleine Marke, etwa „CCP" oder „offen".
pw.Widget _marke(String text, PdfColor farbe, {bool voll = false}) =>
    pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
      decoration: pw.BoxDecoration(
        color: voll ? farbe : null,
        border: voll ? null : pw.Border.all(color: farbe, width: .7),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2.5)),
      ),
      child: _t(
        text,
        groesse: 6.8,
        fett: true,
        farbe: voll ? PdfColors.white : farbe,
      ),
    );

/// [_marke] in einer Tabellenzelle — so breit wie ihr Text.
pw.Widget _markeZelle(String text, PdfColor farbe, {bool voll = false}) =>
    pw.Align(
      alignment: pw.Alignment.topLeft,
      child: _marke(text, farbe, voll: voll),
    );

/// Eine Überschrift innerhalb eines Kapitels.
pw.Widget _abschnitt(String titel, {String? zusatz}) => pw.Padding(
  padding: const pw.EdgeInsets.only(top: 14, bottom: 5),
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.end,
    children: [
      _t(titel, groesse: 10.5, fett: true, farbe: _akzent),
      if (zusatz != null && zusatz.trim().isNotEmpty) ...[
        pw.SizedBox(width: 8),
        pw.Expanded(child: _t(zusatz, groesse: 8, farbe: _grau, maxLines: 1)),
      ],
    ],
  ),
);

/// Eine kleine Überschrift über einem Absatz.
pw.Widget _etikett(String text) => pw.Padding(
  padding: const pw.EdgeInsets.only(top: 6, bottom: 1.5),
  child: _t(text, groesse: 7.5, fett: true, farbe: _grau),
);

/// Ein längerer Text mit Überschrift — leer: nichts.
List<pw.Widget> _absatz(String titel, String? text) {
  final t = _oderNull(text);
  if (t == null) return const [];
  return [_etikett(titel), _fliess(t)];
}

/// Bezeichnung und Wert untereinander; leere Werte fallen weg.
pw.Widget _felder(
  List<(String, String)> paare, {
  double labelBreite = 118,
  double groesse = 8.8,
}) {
  final sichtbar = [
    for (final (l, w) in paare)
      if (w.trim().isNotEmpty) (l, w.trim()),
  ];
  return pw.Table(
    columnWidths: {
      0: pw.FixedColumnWidth(labelBreite),
      1: const pw.FlexColumnWidth(),
    },
    border: const pw.TableBorder(
      horizontalInside: pw.BorderSide(color: _linie, width: .4),
    ),
    children: [
      for (final (l, w) in sichtbar)
        pw.TableRow(
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(0, 3, 6, 3),
              child: _t(l, groesse: groesse, farbe: _grau),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: _t(w, groesse: groesse),
            ),
          ],
        ),
    ],
  );
}

/// Wie [_felder], auf zwei Spalten verteilt — für kurze Werte.
pw.Widget _felderZweispaltig(List<(String, String)> paare) {
  final sichtbar = [
    for (final (l, w) in paare)
      if (w.trim().isNotEmpty) (l, w),
  ];
  final mitte = (sichtbar.length + 1) ~/ 2;
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(child: _felder(sichtbar.sublist(0, mitte), labelBreite: 96)),
      pw.SizedBox(width: 18),
      pw.Expanded(child: _felder(sichtbar.sublist(mitte), labelBreite: 96)),
    ],
  );
}

/// Eine Tabelle mit Kopfzeile, die auf jeder Seite wiederkehrt.
pw.Widget _tabelle({
  required List<String> kopf,
  required List<List<pw.Widget>> zeilen,
  Map<int, pw.TableColumnWidth>? breiten,
  Set<int> rechts = const {},
  List<PdfColor?> hintergruende = const [],
}) => pw.Table(
  columnWidths: breiten,
  border: const pw.TableBorder(
    horizontalInside: pw.BorderSide(color: _linie, width: .4),
    bottom: pw.BorderSide(color: _linie, width: .4),
  ),
  children: [
    pw.TableRow(
      repeat: true,
      decoration: const pw.BoxDecoration(color: _akzentHell),
      children: [
        for (final (i, k) in kopf.indexed)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 3.5,
            ),
            child: _t(
              k,
              groesse: 7.3,
              fett: true,
              farbe: _akzent,
              ausrichtung: rechts.contains(i) ? pw.TextAlign.right : null,
            ),
          ),
      ],
    ),
    for (final (r, zeile) in zeilen.indexed)
      pw.TableRow(
        decoration: r < hintergruende.length && hintergruende[r] != null
            ? pw.BoxDecoration(color: hintergruende[r])
            : null,
        children: [
          for (final (i, z) in zeile.indexed)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 3,
              ),
              child: rechts.contains(i)
                  ? pw.Align(alignment: pw.Alignment.topRight, child: z)
                  : z,
            ),
        ],
      ),
  ],
);

/// Eine Zelle mit Text.
pw.Widget _zelle(
  String text, {
  bool fett = false,
  PdfColor farbe = _schwarz,
  double groesse = 8.3,
}) => _t(text, groesse: groesse, fett: fett, farbe: farbe);

/// Ein Wert mit kleiner Überschrift in einem hellen Feld.
pw.Widget _kennzahl(String titel, String wert, {String? unten}) => pw.Container(
  height: 42,
  padding: const pw.EdgeInsets.fromLTRB(7, 5, 7, 5),
  decoration: const pw.BoxDecoration(
    color: _flaeche,
    borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
  ),
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _t(titel, groesse: 6.5, fett: true, farbe: _grau, sperrung: .3),
      pw.SizedBox(height: 2),
      _t(wert, groesse: 10.5, fett: true, maxLines: 1),
      if (unten != null && unten.isNotEmpty)
        _t(unten, groesse: 7, farbe: _grau, maxLines: 1),
    ],
  ),
);

/// Mehrere Kennzahlen nebeneinander.
pw.Widget _kennzahlen(List<pw.Widget> felder) => pw.Row(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    for (final (i, f) in felder.indexed) ...[
      if (i > 0) pw.SizedBox(width: 6),
      pw.Expanded(child: f),
    ],
  ],
);

/// Ein Text mit vorangestelltem Zeichen.
pw.Widget _mitZeichen(
  _Zeichen z,
  String text, {
  String? zusatz,
  double groesse = 8.8,
}) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(vertical: 2),
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Padding(padding: const pw.EdgeInsets.only(top: 1), child: _zeichen(z)),
      pw.SizedBox(width: 6),
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _t(text, groesse: groesse),
            if (zusatz != null && zusatz.trim().isNotEmpty)
              _t(zusatz, groesse: 7.5, farbe: _grau),
          ],
        ),
      ),
    ],
  ),
);

/// Ein Aufzählungspunkt — darf umbrechen, aber nicht über die Seite.
pw.Widget _punkt(String text, {double einzug = 0, PdfColor farbe = _schwarz}) =>
    pw.Padding(
      padding: pw.EdgeInsets.only(left: einzug, top: 1, bottom: 1),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(width: 8, child: _t('-', groesse: 8.5, farbe: _grau)),
          pw.Expanded(child: _t(text, groesse: 8.5, farbe: farbe)),
        ],
      ),
    );

/// Hält [kinder] zusammen auf einer Seite.
pw.Widget _zusammen(List<pw.Widget> kinder) => pw.Inseparable(
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: kinder,
  ),
);

/// Eine Überschrift mit ihrem Inhalt — bei bis zu [maxZeilen] Zeilen
/// zusammen auf einer Seite, sonst darf der Inhalt umbrechen.
List<pw.Widget> _mitTitel(
  pw.Widget titel,
  List<pw.Widget> inhalt, {
  required int zeilen,
  int maxZeilen = 22,
}) => zeilen <= maxZeilen
    ? [
        _zusammen([titel, ...inhalt]),
      ]
    : [titel, ...inhalt];

// ── Inhaltsverzeichnis und Lesezeichen ─────────────────────────────────

/// Ein Sprungziel am Anfang eines Kapitels: Es merkt sich, auf welcher
/// Seite es gezeichnet wird, und legt ein Lesezeichen an — erst beim
/// Zeichnen, also an seiner endgültigen Stelle.
class _Marke extends pw.Anchor {
  _Marke({
    required pw.Widget child,
    required super.name,
    required this.titel,
    required this.rahmen,
  }) : super(child: child, setX: true);

  final String titel;
  final DruckRahmen rahmen;

  @override
  void paint(pw.Context context) {
    super.paint(context);
    if (rahmen.gefunden.containsKey(name)) return;
    rahmen.merke(name, context.pageNumber);
    context.document.outline.add(
      PdfOutline(
        context.document,
        title: pdfText(titel),
        anchor: name,
        page: context.page,
      )..effectiveLevel = 0,
    );
  }
}

/// Ein Kapitel des Berichts.
class _Kapitel {
  _Kapitel(this.schluessel, this.titel, this.bauen, {this.neueSeite = true});

  /// Unter diesem Wert steht es in der Wahl ([BerichtWahl.kapitel]).
  final String schluessel;
  final String titel;
  final List<pw.Widget> Function(_Satz s, _Kapitel k) bauen;

  /// Beginnt auf einer neuen Seite.
  final bool neueSeite;

  int nr = 0;

  String get anker => 'kapitel-$nr';
}

/// Was beim Setzen mitläuft.
class _Satz {
  _Satz(this.b, this.jetzt, this.rahmen, this.inhalt);

  final ProjektBericht b;
  final DateTime jetzt;

  /// Breite, Maßstab und die Seiten der Kapitel aus dem ersten Durchgang
  /// ([DruckRahmen.bekannt]).
  final DruckRahmen rahmen;

  final BerichtInhalt inhalt;

  EntwicklungsProjekt get p => b.projekt;

  /// Die Seiten der Kapitel aus dem ersten Durchgang.
  Map<String, int> get bekannt => rahmen.bekannt;

  /// Kapitel mit Inhalt beginnen auf einer neuen Seite — nicht, wenn es
  /// abgewählt ist oder der Bericht auf feste Seiten passen soll.
  bool get neueSeiten => inhalt.neueSeiten && rahmen.umbrueche;

  /// Wie viele Einträge eine Zeile des Zeitstrahls trägt: auf A4 hoch
  /// sechs, quer oder verkleinert mehr.
  int get jeZeile => math.max(3, (rahmen.breite / 85).floor());
}

/// Der Kopf eines Kapitels: Nummer und Titel, darunter [untertitel].
List<pw.Widget> _kapitelKopf(_Satz s, _Kapitel k, {String? untertitel}) => [
  if (k.neueSeite && s.neueSeiten) pw.NewPage(),
  _Marke(
    name: k.anker,
    titel: '${k.nr}  ${k.titel}',
    rahmen: s.rahmen,
    child: pw.Container(
      margin: pw.EdgeInsets.only(
        top: k.neueSeite && s.neueSeiten ? 0 : 22,
        bottom: 6,
      ),
      padding: const pw.EdgeInsets.only(bottom: 5),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _akzent, width: 1.2)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          _t('${k.nr}', groesse: 20, fett: true, farbe: _akzent),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: _t(k.titel, groesse: 16, fett: true, farbe: _akzent),
          ),
        ],
      ),
    ),
  ),
  if (untertitel != null && untertitel.trim().isNotEmpty)
    pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: _t(untertitel, groesse: 8.5, farbe: _grau),
    ),
];

// ── Bericht ────────────────────────────────────────────────────────────

/// Was in den Bericht kommt — die Wahl im Druckfenster.
class BerichtInhalt {
  const BerichtInhalt({
    this.kapitel,
    this.steckbrief = true,
    this.inhaltsverzeichnis = true,
    this.zeitstrahl = true,
    this.verlaufEinzeln = true,
    this.neueSeiten = true,
  });

  /// Diese Kapitel ([BerichtKapitel]) — null: alle.
  final Set<String>? kapitel;

  /// Auf Seite 1 der Stand auf einen Blick: Phase, Idee, Bild, Kacheln.
  final bool steckbrief;

  /// Das Inhaltsverzeichnis auf Seite 1.
  final bool inhaltsverzeichnis;

  /// Im Kapitel Verlauf: der Zeitstrahl …
  final bool zeitstrahl;

  /// … und die Einträge im Einzelnen.
  final bool verlaufEinzeln;

  /// Kapitel mit Inhalt beginnen auf einer neuen Seite.
  final bool neueSeiten;
}

/// Die Kapitel des Berichts — Schlüssel für [BerichtInhalt.kapitel].
abstract final class BerichtKapitel {
  static const projekt = 'projekt';
  static const rezeptur = 'rezeptur';
  static const produkt = 'produkt';
  static const herstellung = 'herstellung';
  static const freigabe = 'freigabe';
  static const weg = 'weg';
  static const verlauf = 'verlauf';
  static const dateien = 'dateien';
}

/// Schlüssel der Wahl im Druckfenster.
abstract final class BerichtWahl {
  static const kapitel = 'kapitel';
  static const steckbrief = 'steckbrief';
  static const inhaltsverzeichnis = 'inhaltsverzeichnis';
  static const zeitstrahl = 'zeitstrahl';
  static const verlaufEinzeln = 'verlaufEinzeln';
  static const neueSeiten = 'neueSeiten';
}

/// Die Kapitel, die es für [b] gibt — mit Titel, in ihrer Reihenfolge.
List<(String, String)> berichtKapitelVon(ProjektBericht b) => [
  for (final k in _alleKapitel(b)) (k.schluessel, k.titel),
];

/// Der Druck des Berichts für das Druckfenster.
DruckAuftrag berichtDruckAuftrag(ProjektBericht b, {DateTime? gedrucktAm}) {
  final kapitel = berichtKapitelVon(b);
  const gruppe = 'Im Bericht';
  return DruckAuftrag(
    art: 'projektbericht',
    titel: 'Projektbericht drucken',
    untertitel: b.projekt.name,
    optionen: [
      DruckWahlMehrere(
        schluessel: BerichtWahl.kapitel,
        titel: 'Kapitel',
        werte: [
          for (final (i, (schluessel, titel)) in kapitel.indexed)
            DruckWert(schluessel, '${i + 1}  $titel'),
        ],
        standard: {for (final (schluessel, _) in kapitel) schluessel},
      ),
      const DruckSchalter(
        schluessel: BerichtWahl.steckbrief,
        titel: 'Steckbrief',
        hinweis: 'Seite 1: Phase, Idee, Bild und der Stand auf einen Blick',
        gruppe: gruppe,
      ),
      const DruckSchalter(
        schluessel: BerichtWahl.inhaltsverzeichnis,
        titel: 'Inhaltsverzeichnis',
        gruppe: gruppe,
      ),
      if (b.verlauf.isNotEmpty) ...[
        DruckSchalter(
          schluessel: BerichtWahl.zeitstrahl,
          titel: 'Verlauf als Zeitstrahl',
          gruppe: gruppe,
          sichtbar: (w) =>
              w.mehrere(BerichtWahl.kapitel).contains(BerichtKapitel.verlauf),
        ),
        DruckSchalter(
          schluessel: BerichtWahl.verlaufEinzeln,
          titel: 'Verlauf im Einzelnen',
          hinweis: 'Jeder Eintrag mit seinem Text',
          gruppe: gruppe,
          sichtbar: (w) =>
              w.mehrere(BerichtWahl.kapitel).contains(BerichtKapitel.verlauf),
        ),
      ],
      const DruckSchalter(
        schluessel: BerichtWahl.neueSeiten,
        titel: 'Kapitel auf neuen Seiten',
        hinweis: 'Ohne: alles fortlaufend — spart Papier',
        gruppe: gruppe,
      ),
    ],
    bauen: (wahl) {
      final gewaehlt = wahl.mehrere(BerichtWahl.kapitel);
      final inhalt = BerichtInhalt(
        kapitel: gewaehlt,
        steckbrief: wahl.an(BerichtWahl.steckbrief),
        inhaltsverzeichnis: wahl.an(BerichtWahl.inhaltsverzeichnis),
        zeitstrahl: wahl.an(BerichtWahl.zeitstrahl),
        verlaufEinzeln: wahl.an(BerichtWahl.verlaufEinzeln),
        neueSeiten: wahl.an(BerichtWahl.neueSeiten),
      );
      if (_kapitelFuer(b, inhalt).isEmpty &&
          !inhalt.steckbrief &&
          !inhalt.inhaltsverzeichnis) {
        throw const DruckNichtsGewaehlt(
          'Wähle mindestens ein Kapitel oder den Steckbrief.',
        );
      }
      return berichtDruck(b, inhalt: inhalt, gedrucktAm: gedrucktAm);
    },
  );
}

/// Baut den ganzen Bericht als PDF in Originalgröße — [komprimiert] nur
/// für Tests abgeschaltet, die den Text lesen.
Future<Uint8List> baueProjektPdf(
  ProjektBericht b, {
  DateTime? gedrucktAm,
  bool komprimiert = true,
}) async {
  final ergebnis = await druckSetzen(
    berichtDruck(b, gedrucktAm: gedrucktAm),
    const DruckLayout(),
    komprimiert: komprimiert,
  );
  return ergebnis.bytes;
}

/// Alle Kapitel, die es für [b] gibt. Eins mit Inhalt beginnt auf einer
/// neuen Seite; eins, das nur sagt, was noch fehlt, folgt dem davor — so
/// bleibt der Bericht eines jungen Projekts kurz.
List<_Kapitel> _alleKapitel(ProjektBericht b) {
  final p = b.projekt;
  final mitProzess = !Prozessparameter.aus(p.prozess).leer ||
      b.artikelSchritte.isNotEmpty ||
      !Haccp.aus(p.haccp).leer;
  return [
    _Kapitel(BerichtKapitel.projekt, 'Projekt', _kapitelProjekt),
    _Kapitel(
      BerichtKapitel.rezeptur,
      'Rezeptur',
      _kapitelRezeptur,
      neueSeite: b.version != null,
    ),
    _Kapitel(
      BerichtKapitel.produkt,
      'Produkt und Spezifikation',
      _kapitelProdukt,
      neueSeite: false,
    ),
    _Kapitel(
      BerichtKapitel.herstellung,
      'Herstellung und HACCP',
      _kapitelHerstellung,
      neueSeite: mitProzess,
    ),
    _Kapitel(
      BerichtKapitel.freigabe,
      'Freigabe und Checkliste',
      _kapitelFreigabe,
      neueSeite: false,
    ),
    if (b.verlauf.isNotEmpty || b.versionen.isNotEmpty)
      _Kapitel(
        BerichtKapitel.weg,
        'Entwicklungsweg',
        _kapitelWeg,
        neueSeite: b.versionen.isNotEmpty,
      ),
    if (b.verlauf.isNotEmpty)
      _Kapitel(
        BerichtKapitel.verlauf,
        'Verlauf',
        _kapitelVerlauf,
        neueSeite: b.verlauf.length > 3,
      ),
    if (b.dateien.isNotEmpty)
      _Kapitel(
        BerichtKapitel.dateien,
        'Dateien',
        _kapitelDateien,
        neueSeite: false,
      ),
  ];
}

/// Die gewählten Kapitel, neu durchgezählt. Der Verlauf fällt weg, wenn
/// weder Zeitstrahl noch Einträge gewählt sind.
List<_Kapitel> _kapitelFuer(ProjektBericht b, BerichtInhalt inhalt) {
  final kapitel = [
    for (final k in _alleKapitel(b))
      if ((inhalt.kapitel?.contains(k.schluessel) ?? true) &&
          (k.schluessel != BerichtKapitel.verlauf ||
              inhalt.zeitstrahl ||
              inhalt.verlaufEinzeln))
        k,
  ];
  for (final (i, k) in kapitel.indexed) {
    k.nr = i + 1;
  }
  return kapitel;
}

/// Der Bericht zum Drucken: ein Blatt, das über viele Seiten läuft — mit
/// Lesezeichen für jedes Kapitel.
DruckDokument berichtDruck(
  ProjektBericht b, {
  BerichtInhalt inhalt = const BerichtInhalt(),
  DateTime? gedrucktAm,
}) {
  final jetzt = gedrucktAm ?? DateTime.now();
  final p = b.projekt;
  final kunde = _oderNull(p.kunde);
  final nummer = _oderNull(b.artikel?.artikelnummer ?? p.artikelnummer);
  return DruckDokument(
    titel: pdfText('Projektbericht ${p.name}'),
    dateiname: druckDateiname('Projektbericht ${p.name}'),
    lesezeichen: true,
    theme: pw.ThemeData.withFont(
      base: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
      italic: pw.Font.helveticaOblique(),
      boldItalic: pw.Font.helveticaBoldOblique(),
    ),
    blaetter: [
      DruckBlatt(
        rand: const pw.EdgeInsets.fromLTRB(42, 38, 42, 34),
        bauen: (r) {
          final s = _Satz(b, jetzt, r, inhalt);
          final kapitel = _kapitelFuer(b, inhalt);
          return DruckSeiten(
            maxSeiten: 500,
            kopf: (ctx) => r.seiteImBlatt(ctx) == 1
                ? pw.SizedBox()
                : pw.Container(
                    margin: const pw.EdgeInsets.only(bottom: 12),
                    padding: const pw.EdgeInsets.only(bottom: 4),
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(color: _linie, width: .5),
                      ),
                    ),
                    child: pw.Row(
                      children: [
                        pw.Expanded(
                          child: _t(
                            'Projektbericht · ${p.name}',
                            groesse: 7.5,
                            farbe: _grau,
                            maxLines: 1,
                          ),
                        ),
                        _t(
                          [
                            if (kunde != null) kunde,
                            if (nummer != null) 'Art.-Nr. $nummer',
                          ].join(' · '),
                          groesse: 7.5,
                          farbe: _grau,
                        ),
                      ],
                    ),
                  ),
            fuss: (ctx) => pw.Container(
              margin: const pw.EdgeInsets.only(top: 10),
              child: pw.Row(
                children: [
                  _t(
                    'Stand ${_datum(jetzt)} · Produktions Planer',
                    groesse: 7,
                    farbe: _hellgrau,
                  ),
                  pw.Spacer(),
                  _t(r.seitenText(ctx), groesse: 7, farbe: _hellgrau),
                ],
              ),
            ),
            inhalt: (ctx) => [
              ..._deckblatt(s, kapitel),
              for (final k in kapitel) ...k.bauen(s, k),
            ],
          );
        },
      ),
    ],
  );
}

// ── Steckbrief (Seite 1) ───────────────────────────────────────────────

/// Seit wann das Projekt in [status] ist — nach dem letzten Wechsel
/// dorthin im Verlauf; in der Entwicklung ohne Wechsel seit dem Anlegen.
DateTime? _seit(_Satz s, ProjektStatus status) {
  for (final e in s.b.verlauf) {
    if (statusWechsel(e)?.neu == status) return e.datum;
  }
  return status == ProjektStatus.entwicklung ? s.p.createdAt : null;
}

List<pw.Widget> _deckblatt(_Satz s, List<_Kapitel> kapitel) {
  final b = s.b;
  final p = s.p;
  final bild = _bildAus(b.bild);
  final status = ProjektStatus.aus(p.status);
  final unterzeile = [
    if (_oderNull(p.kunde) case final k?) k,
    if (_oderNull(b.artikel?.artikelnummer ?? p.artikelnummer) case final n?)
      'Art.-Nr. $n',
    if (_oderNull(b.fliessdiagramm ?? p.fliessdiagramm) case final f?) f,
  ].join('   ·   ');
  final seit = _seit(s, status);
  final phase = [
    '${status.label}${seit == null ? '' : ' seit ${_datum(seit)}'}',
    'angelegt am ${_datum(p.createdAt)}',
  ].join(' · ');
  final steckbrief = s.inhalt.steckbrief;
  return [
    pw.Row(
      children: [
        _t(
          'PROJEKTBERICHT',
          groesse: 8,
          fett: true,
          farbe: _akzent,
          sperrung: 1,
        ),
        pw.Spacer(),
        _t('Stand ${_datum(s.jetzt)}', groesse: 8, farbe: _grau),
      ],
    ),
    pw.SizedBox(height: 14),
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _t(p.name, groesse: 22, fett: true),
              if (unterzeile.isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 4),
                  child: _t(unterzeile, groesse: 10, farbe: _grau),
                ),
              if (steckbrief) ...[
                pw.SizedBox(height: 14),
                _phasenLeiste(status),
                pw.SizedBox(height: 5),
                _t(phase, groesse: 8, farbe: _grau),
                if (_oderNull(p.produktidee) case final idee?) ...[
                  pw.SizedBox(height: 10),
                  _t(idee, groesse: 9, maxLines: 4),
                ],
              ],
            ],
          ),
        ),
        if (steckbrief && bild != null)
          pw.Container(
            width: 168,
            height: 126,
            margin: const pw.EdgeInsets.only(left: 16),
            padding: const pw.EdgeInsets.all(3),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _linie, width: .6),
            ),
            child: pw.Image(bild, fit: pw.BoxFit.contain),
          ),
      ],
    ),
    if (steckbrief) ...[
      _abschnitt('Auf einen Blick'),
      ..._kacheln(s),
      if (_zielPruefungen(s).isNotEmpty) ...[
        pw.SizedBox(height: 8),
        _zieleZeile(s),
      ],
    ],
    if (s.inhalt.inhaltsverzeichnis && kapitel.isNotEmpty) ...[
      _abschnitt('Inhalt'),
      for (final k in kapitel) _inhaltZeile(s, k),
    ],
  ];
}

/// Entwicklung » Validierung » Produktion — erledigte mit Haken, die
/// jetzige farbig.
pw.Widget _phasenLeiste(ProjektStatus status) {
  const folge = [
    ProjektStatus.entwicklung,
    ProjektStatus.validierung,
    ProjektStatus.produktion,
  ];
  final archiviert = status == ProjektStatus.archiviert;
  final jetzt = folge.indexOf(status);
  return pw.Row(
    children: [
      for (final (i, ph) in folge.indexed) ...[
        if (i > 0)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 5),
            child: _t('»', farbe: _hellgrau),
          ),
        if (i == jetzt)
          _marke(_phasenName(ph).toUpperCase(), _phasenFarbe(ph), voll: true)
        else
          pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              if (i < jetzt || archiviert) ...[
                _zeichen(_Zeichen.erledigt, groesse: 7.5),
                pw.SizedBox(width: 3),
              ],
              _t(
                _phasenName(ph),
                groesse: 8,
                farbe: i < jetzt || archiviert ? _grau : _hellgrau,
              ),
            ],
          ),
      ],
      if (archiviert) ...[
        pw.SizedBox(width: 10),
        _marke('ARCHIVIERT', _grau, voll: true),
      ],
    ],
  );
}

/// Ein Feld im Steckbrief.
pw.Widget _kachel(
  String titel,
  String haupt,
  List<String> details, {
  PdfColor farbe = _akzent,
  pw.Widget? zusatz,
}) => pw.Container(
  height: 70,
  padding: const pw.EdgeInsets.fromLTRB(8, 6, 6, 5),
  decoration: pw.BoxDecoration(
    color: _flaeche,
    border: pw.Border(left: pw.BorderSide(color: farbe, width: 2.5)),
  ),
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _t(titel, groesse: 6.5, fett: true, farbe: _grau, sperrung: .4),
      pw.SizedBox(height: 3),
      _t(haupt, groesse: 10, fett: true, maxLines: 1),
      if (zusatz != null) ...[pw.SizedBox(height: 3), zusatz],
      for (final d in details.take(zusatz == null ? 3 : 2))
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 1.5),
          child: _t(d, groesse: 7.3, farbe: _grau, maxLines: 1),
        ),
    ],
  ),
);

/// Ein Fortschrittsbalken.
pw.Widget _balken(double anteil, {double breite = 120}) {
  final a = anteil.clamp(0.0, 1.0);
  return pw.Row(
    children: [
      pw.Container(width: breite * a, height: 4, color: _ok),
      pw.Container(width: breite * (1 - a), height: 4, color: _linie),
    ],
  );
}

List<pw.Widget> _kacheln(_Satz s) {
  final b = s.b;
  final p = s.p;
  // Freigabe
  final artikel = b.artikel;
  final pw.Widget freigabe;
  if (artikel != null) {
    freigabe = _kachel(
      'FREIGABE',
      'Artikel ${artikel.artikelnummer}',
      [
        artikel.artikelbezeichnung,
        [
          if (b.version case final v? when v.id == p.freigabeVersionId)
            'Stand ${v.nummer}',
          if (p.freigegebenAm case final d?) 'am ${_datum(d)}',
          if (artikel.deletedAt != null) 'im Planer gelöscht',
        ].join(' · '),
      ],
      farbe: artikel.deletedAt == null ? _ok : _fehler,
    );
  } else {
    freigabe = _kachel(
      'FREIGABE',
      'Noch nicht freigegeben',
      [
        if (_oderNull(p.artikelnummer) case final n?) 'Art.-Nr. $n vorgesehen',
      ],
      farbe: _hellgrau,
    );
  }
  // Rezeptur
  final v = b.version;
  final e = b.ergebnis;
  final staende = b.versionen.values
      .where((x) => b.rezepturen.any((r) => r.id == x.rezepturId))
      .toList();
  final entwuerfe = staende
      .where((x) => x.status != VersionStatus.abgeschlossen)
      .length;
  final rezeptur = v == null
      ? _kachel('REZEPTUR', 'Noch keine', const [], farbe: _hellgrau)
      : _kachel(
          'REZEPTUR',
          'Stand ${v.nummer} · ${_standStatus(s, v)}',
          [
            b.rezepturName ?? '',
            if (e != null)
              'Fleisch ${prozentText(e.fleischanteilProzent)} · '
                  'Verlust ${prozentText(v.verlustProzent)}',
            '${staende.length} ${staende.length == 1 ? 'Stand' : 'Stände'}'
                '${entwuerfe == 0 ? '' : ', davon $entwuerfe in Arbeit'}',
          ],
          farbe: v.status == VersionStatus.abgeschlossen ? _ok : _warn,
        );
  // Checkliste
  final check = _check(s);
  final naechster = check.naechster;
  final checkliste = _kachel(
    'CHECKLISTE',
    '${check.text} erledigt',
    [
      if (check.fertig)
        'Alles erledigt'
      else if (naechster != null)
        'Als Nächstes: ${checkAufgabe(naechster)}',
      if (check.zurueckgestellt.isNotEmpty)
        'Zurückgestellt: '
            '${[for (final z in check.zurueckgestellt) z.punkt.label].join(', ')}',
    ],
    farbe: check.fertig ? _ok : _akzent,
    zusatz: _balken(check.anteil),
  );
  // Prozess
  final prozess = Prozessparameter.aus(p.prozess);
  final historie = ProzessStand.listeAus(p.prozessHistorie);
  final fassung = prozessFassung(prozess, historie);
  final prozessKachel = prozess.leer && b.artikelSchritte.isEmpty
      ? _kachel('PROZESS', 'Noch nicht beschrieben', const [], farbe: _hellgrau)
      : _kachel(
          'PROZESS',
          prozess.leer
              ? 'Im Artikel hinterlegt'
              : fassung.version == null
              ? 'Ohne Version'
              : 'Version ${fassung.version}',
          [
            if (!prozess.leer) prozessKurztext(prozess),
            if (!prozess.leer && fassung.datum != null)
              'vom ${_datum(fassung.datum)}'
                  '${fassung.geaendert ? ', seitdem geändert' : ''}',
            if (prozess.leer) '${b.artikelSchritte.length} Schritte im Artikel',
          ],
          farbe: fassung.geaendert ? _warn : _ok,
        );
  // HACCP
  final haccp = Haccp.aus(p.haccp);
  final ccp = haccp.lenkungspunkte
      .where((l) => l.ergebnis == Lenkungsart.ccp)
      .length;
  final hoechstes = haccp.gefahren.fold<int>(
    0,
    (m, g) => g.risiko > m ? g.risiko : m,
  );
  final haccpKachel = haccp.leer
      ? _kachel('HACCP', 'Noch keine Analyse', const [], farbe: _hellgrau)
      : _kachel(
          'HACCP',
          '${haccp.gefahren.length} '
              '${haccp.gefahren.length == 1 ? 'Gefahr' : 'Gefahren'}',
          [
            '${haccp.lenkungspunkte.length} Lenkungspunkte, davon $ccp CCP',
            if (haccp.gefahren.isNotEmpty) 'höchstes Risiko $hoechstes',
          ],
          farbe: hoechstes >= 6 ? _fehler : (hoechstes >= 3 ? _warn : _ok),
        );
  // Offene Punkte im Verlauf — überfällige am Tag des Berichts in Rot.
  final offen = [
    for (final x in b.verlauf.reversed)
      if (EintragStatus.aus(x.status) == EintragStatus.offen) x,
  ];
  bool vorbei(ProjektEintrag x) => eintragUeberfaellig(x, heute: s.jetzt);
  final ueberfaellig = offen.where(vorbei).length;
  final offenKachel = _kachel(
    'OFFENE PUNKTE',
    offen.isEmpty
        ? 'Keine'
        : '${offen.length} ${offen.length == 1 ? 'Eintrag' : 'Einträge'} offen'
            '${ueberfaellig == 0 ? '' : ', $ueberfaellig überfällig'}',
    [
      for (final x in offen)
        if (_oderNull(x.ziel) case final f?)
          '$f${vorbei(x) ? ' (überfällig)' : ''}: ${x.titel}'
        else
          x.titel,
    ],
    farbe: offen.isEmpty ? _ok : (ueberfaellig > 0 ? _fehler : _warn),
  );
  pw.Widget reihe(List<pw.Widget> felder) => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      for (final (i, f) in felder.indexed) ...[
        if (i > 0) pw.SizedBox(width: 8),
        pw.Expanded(child: f),
      ],
    ],
  );
  return [
    reihe([freigabe, rezeptur, checkliste]),
    pw.SizedBox(height: 8),
    reihe([prozessKachel, haccpKachel, offenKachel]),
  ];
}

/// Die Checkliste, wie sie steht.
ProjektCheckStand _check(_Satz s) =>
    s.b.checkliste ??
    projektCheckStand(projekt: s.p, rezepturen: const [], versionen: const []);

/// Die Ziele des Projekts gegen die Rezeptur: Bezeichnung, Vorgabe,
/// erreichter Wert und ob er passt (null: nicht zu prüfen).
List<({String ziel, String vorgabe, String ist, bool? passt})> _zielPruefungen(
  _Satz s,
) {
  final p = s.p;
  final e = s.b.ergebnis;
  final fett = e?.je100g.fett;
  final eiweiss = e?.je100g.eiweiss;
  return [
    if (p.zielFett case final z?)
      (
        ziel: 'Fett',
        vorgabe: 'max. ${_vorgabe(z)} %',
        ist: fett == null ? '' : '${_zahl(fett)} g',
        passt: fett == null ? null : fett <= z,
      ),
    if (p.zielEiweiss case final z?)
      (
        ziel: 'Eiweiß',
        vorgabe: 'min. ${_vorgabe(z)} %',
        ist: eiweiss == null ? '' : '${_zahl(eiweiss)} g',
        passt: eiweiss == null ? null : eiweiss >= z,
      ),
    if (p.grenzeAw case final z?)
      (
        ziel: 'aw-Wert',
        vorgabe: 'max. ${_vorgabe(z, nachkomma: 2)}',
        ist: '',
        passt: null,
      ),
  ];
}

pw.Widget _zieleZeile(_Satz s) => pw.Wrap(
  spacing: 16,
  runSpacing: 4,
  crossAxisAlignment: pw.WrapCrossAlignment.center,
  children: [
    _t('ZIELE JE 100 G', groesse: 6.5, fett: true, farbe: _grau, sperrung: .4),
    for (final z in _zielPruefungen(s))
      pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          if (z.passt case final ok?) ...[
            _zeichen(ok ? _Zeichen.erledigt : _Zeichen.verfehlt),
            pw.SizedBox(width: 4),
          ],
          _t(
            '${z.ziel} ${z.vorgabe}'
            '${z.ist.isEmpty ? '' : ' · Rezeptur ${z.ist}'}',
            groesse: 8.5,
          ),
        ],
      ),
  ],
);

/// Eine Zeile im Inhaltsverzeichnis — ein Sprung zum Kapitel.
pw.Widget _inhaltZeile(_Satz s, _Kapitel k) => pw.Link(
  destination: k.anker,
  child: pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.SizedBox(
          width: 18,
          child: _t('${k.nr}', groesse: 10, fett: true, farbe: _akzent),
        ),
        _t(k.titel, groesse: 10),
        pw.SizedBox(width: 6),
        pw.Expanded(
          child: pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2.5),
            child: pw.Divider(
              height: 1,
              thickness: .6,
              color: _hellgrau,
              borderStyle: pw.BorderStyle.dotted,
            ),
          ),
        ),
        pw.SizedBox(width: 6),
        pw.SizedBox(
          width: 22,
          child: _t(
            '${s.bekannt[k.anker] ?? ''}',
            groesse: 10,
            ausrichtung: pw.TextAlign.right,
          ),
        ),
      ],
    ),
  ),
);

// ── 1 Projekt ──────────────────────────────────────────────────────────

List<pw.Widget> _kapitelProjekt(_Satz s, _Kapitel k) {
  final b = s.b;
  final p = s.p;
  final status = ProjektStatus.aus(p.status);
  final seit = _seit(s, status);
  final neueZutaten = !p.neueZutaten
      ? 'nein'
      : 'ja${_oderNull(p.neueZutatenDetails) == null ? '' : ': ${p.neueZutatenDetails!.trim()}'}';
  final felder = [
    ('Kunde', p.kunde ?? ''),
    ('Artikelnummer', b.artikel?.artikelnummer ?? p.artikelnummer ?? ''),
    ('Fließdiagramm', b.fliessdiagramm ?? p.fliessdiagramm ?? ''),
    ('Phase', '${status.label}${seit == null ? '' : ' seit ${_datum(seit)}'}'),
    ('Angelegt', _datum(p.createdAt)),
    ('Zuletzt geändert', _datum(p.updatedAt)),
    ('Freigegeben', p.freigegebenAm == null ? 'nein' : _datum(p.freigegebenAm)),
    ('Neuer Prozess', p.neuerProzess ? 'ja' : 'nein'),
    ('Neue Zutaten', neueZutaten),
    (
      'Rezepturen',
      b.rezepturen.isEmpty
          ? 'keine'
          : [for (final r in b.rezepturen) r.name].join(', '),
    ),
  ];

  // Die Phasen mit ihrem Beginn.
  final phasen = <({DateTime datum, String phase, String anlass})>[];
  final wechsel = [
    for (final e in zeitlichSortiert(b.verlauf))
      if (statusWechsel(e) case final w?) (e: e, w: w),
  ];
  final anfang = wechsel.isEmpty ? status : wechsel.first.w.alt;
  if (anfang == null || anfang == ProjektStatus.entwicklung) {
    phasen.add(
      (
        datum: p.createdAt,
        phase: _phasenName(ProjektStatus.entwicklung),
        anlass: 'Projekt angelegt',
      ),
    );
  }
  for (final x in wechsel) {
    phasen.add(
      (datum: x.e.datum, phase: _phasenName(x.w.neu), anlass: x.e.titel),
    );
  }

  final ziele = _zielPruefungen(s);
  return [
    ..._kapitelKopf(s, k),
    _felderZweispaltig(felder),
    if (phasen.length > 1)
      ..._mitTitel(_abschnitt('Phasen'), zeilen: phasen.length, [
        _tabelle(
          kopf: const ['Seit', 'Phase', 'Anlass'],
          breiten: const {
            0: pw.FixedColumnWidth(62),
            1: pw.FixedColumnWidth(80),
            2: pw.FlexColumnWidth(),
          },
          zeilen: [
            for (final ph in phasen)
              [_zelle(_datum(ph.datum)), _zelle(ph.phase), _zelle(ph.anlass)],
          ],
        ),
      ]),
    if (ziele.isNotEmpty)
      ..._mitTitel(
        _abschnitt(
          'Ziele',
          zusatz: b.version == null
              ? null
              : 'je 100 g, verglichen mit Stand ${b.version!.nummer}',
        ),
        zeilen: ziele.length,
        [
          _tabelle(
            kopf: const ['Ziel', 'Vorgabe', 'Rezeptur', 'Ergebnis'],
            breiten: const {
              0: pw.FixedColumnWidth(80),
              1: pw.FixedColumnWidth(80),
              2: pw.FixedColumnWidth(80),
              3: pw.FlexColumnWidth(),
            },
            zeilen: [
              for (final z in ziele)
                [
                  _zelle(z.ziel),
                  _zelle(z.vorgabe),
                  _zelle(z.ist.isEmpty ? '-' : z.ist),
                  switch (z.passt) {
                    true => _mitZeichen(_Zeichen.erledigt, 'erreicht'),
                    false => _mitZeichen(_Zeichen.verfehlt, 'nicht erreicht'),
                    null => _zelle('nicht berechnet', farbe: _grau),
                  },
                ],
            ],
          ),
        ],
      ),
    if (_oderNull(p.produktidee) != null) ...[
      _abschnitt('Produktidee'),
      _fliess(p.produktidee!.trim()),
    ],
    if (_oderNull(p.kundenvereinbarungen) != null) ...[
      _abschnitt('Anfrage und Vereinbarungen'),
      _fliess(p.kundenvereinbarungen!.trim()),
    ],
    if (_oderNull(p.notizen) != null) ...[
      _abschnitt('Notizen'),
      _fliess(p.notizen!.trim()),
    ],
  ];
}

// ── 2 Rezeptur ─────────────────────────────────────────────────────────

/// Der Name einer Position in der Rezeptur.
String _positionsName(RechenPosition pos) =>
    pos.zutat?.name ?? pos.unterrezeptur?.name ?? '-';

/// Was an einer Position auffällt: Fleisch, Wasser, Unterrezeptur,
/// Allergene.
String _merkmale(RechenPosition pos) {
  final z = pos.zutat;
  if (z == null) return 'Unterrezeptur';
  return [
    if (z.istFleisch)
      z.tierart == null ? 'Fleisch' : 'Fleisch (${z.tierart!.label})',
    if (z.istWasser) 'Wasser',
    if (z.allergene.isNotEmpty)
      merkmaleLabel(z.allergene.join(','), kAllergene),
  ].where((t) => t.isNotEmpty).join(' · ');
}

String _standStatus(_Satz s, RezepturVersion v) {
  if (v.id == s.p.freigabeVersionId) return 'freigegeben';
  return v.status == VersionStatus.abgeschlossen ? 'abgeschlossen' : 'Entwurf';
}

List<pw.Widget> _kapitelRezeptur(_Satz s, _Kapitel k) {
  final b = s.b;
  final v = b.version;
  final e = b.ergebnis;
  final eingabe = b.eingabe;
  if (v == null || e == null) {
    return [
      ..._kapitelKopf(s, k),
      _leer('Noch keine Rezeptur mit einem Stand im Projekt.'),
    ];
  }
  final status = _standStatus(s, v);
  final untertitel = [
    b.rezepturName ?? 'Rezeptur',
    'Stand ${v.nummer}',
    if (status != 'abgeschlossen') status,
    if (v.abgeschlossenAm case final d?)
      'abgeschlossen am ${_datum(d)}'
    else
      'zuletzt geändert am ${_datum(v.updatedAt)}',
  ].join(' · ');
  final summe = eingabe == null
      ? 0.0
      : eingabe.positionen.fold<double>(0, (a, x) => a + x.mengeKg);
  final beffe = e.je100g.beffe;
  final spuren = SpezAngaben.aus(s.p.spezifikation).spuren;
  final verlustArt = Verlustart.aus(v.verlustArt);

  return [
    ..._kapitelKopf(s, k, untertitel: untertitel),
    ..._absatz('Grund für diesen Stand', v.notiz),
    if (_oderNull(v.bezeichnung) case final bez?)
      ..._absatz('Bezeichnung des Stands', bez),
    pw.SizedBox(height: 8),
    _kennzahlen([
      _kennzahl('EINSATZ', '${mengeText(e.eingesetztKg)} kg'),
      _kennzahl(
        'VERLUST',
        verlustArt == Verlustart.keiner
            ? 'keiner'
            : prozentText(v.verlustProzent),
        unten: verlustArt == Verlustart.keiner ? null : verlustArt.label,
      ),
      _kennzahl('ENDGEWICHT', '${mengeText(e.endgewichtKg)} kg'),
      _kennzahl('FLEISCHANTEIL', prozentText(e.fleischanteilProzent)),
      _kennzahl(
        'BEFFE',
        beffe == null ? '-' : prozentText(beffe),
        unten: e.ohneBeffe.isEmpty ? null : 'unvollständig',
      ),
    ]),
    if (eingabe != null && eingabe.positionen.isNotEmpty) ...[
      _abschnitt('Zusammensetzung', zusatz: 'je Ansatz'),
      _tabelle(
        kopf: const ['Nr.', 'Zutat', 'Menge', 'Anteil', 'Merkmale'],
        rechts: const {2, 3},
        breiten: const {
          0: pw.FixedColumnWidth(24),
          1: pw.FlexColumnWidth(3),
          2: pw.FixedColumnWidth(62),
          3: pw.FixedColumnWidth(50),
          4: pw.FlexColumnWidth(2.2),
        },
        zeilen: [
          for (final (i, pos) in eingabe.positionen.indexed)
            [
              _zelle('${i + 1}', farbe: _grau),
              _zelle(_positionsName(pos)),
              _zelle('${mengeText(pos.mengeKg)} kg'),
              _zelle(summe <= 0 ? '' : prozentText(pos.mengeKg / summe * 100)),
              _zelle(_merkmale(pos), farbe: _grau, groesse: 7.5),
            ],
          [
            _zelle(''),
            _zelle('Summe', fett: true),
            _zelle('${mengeText(summe)} kg', fett: true),
            _zelle(summe <= 0 ? '' : '100 %', fett: true),
            _zelle(''),
          ],
        ],
        hintergruende: [for (final _ in eingabe.positionen) null, _flaeche],
      ),
    ],
    _abschnitt('Zutatenverzeichnis', zusatz: 'wie auf dem Etikett'),
    if (e.zutatenliste.trim().isEmpty)
      _leer('Ohne Zutaten.')
    else if (e.zutatenliste.length < 2500)
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _linie, width: .6),
        ),
        child: _t(e.zutatenliste, groesse: 9),
      )
    else
      _fliess(e.zutatenliste),
    pw.SizedBox(height: 6),
    _felder([
      (
        'Allergene',
        e.allergene.isEmpty
            ? 'keine'
            : [
                for (final MapEntry(:key, :value) in e.allergene.entries)
                  '${merkmalLabel(key, kAllergene) ?? key} '
                      '(${value.join(', ')})',
              ].join('; '),
      ),
      (
        'Spuren möglich',
        spuren.isEmpty ? '' : merkmaleLabel(spuren.join(','), kAllergene),
      ),
      (
        'Verarbeitungshilfsstoffe',
        [
          for (final MapEntry(:key, :value)
              in e.verarbeitungshilfsstoffe.entries)
            '$key (${value.join(', ')})',
        ].join('; '),
      ),
    ]),
    ..._mitTitel(
      _abschnitt('Nährwerte', zusatz: 'je 100 g, gerundet wie auf dem Etikett'),
      zeilen: 7,
      [_naehrwertTabelle(s, e)],
    ),
    if (e.tierarten.isNotEmpty)
      ..._mitTitel(
        _abschnitt(
          'Fleisch nach LMIV',
          zusatz: 'Grenzwerte für Fett und Bindegewebe',
        ),
        zeilen: e.tierarten.length,
        [
          _tabelle(
            kopf: const [
              'Tierart',
              'Masse',
              'Fett',
              'Bindegewebe',
              'als Fleisch',
            ],
            rechts: const {1, 4},
            breiten: const {
              0: pw.FlexColumnWidth(1.4),
              1: pw.FixedColumnWidth(58),
              2: pw.FlexColumnWidth(1.3),
              3: pw.FlexColumnWidth(1.5),
              4: pw.FixedColumnWidth(70),
            },
            zeilen: [
              for (final t in e.tierarten)
                [
                  _zelle(t.tierart.label),
                  _zelle('${mengeText(t.masseKg)} kg'),
                  _zelle(
                    '${prozentText(t.fettProzent)} '
                    '(Grenze ${_zahl(t.tierart.fettGrenze, nachkomma: 0)} %)',
                    farbe: t.fettUeberGrenze ? _fehler : _schwarz,
                  ),
                  _zelle(
                    t.kollagenVerhaeltnis == null
                        ? 'nicht geprüft'
                        : '${prozentText(t.kollagenVerhaeltnis!)} '
                              '(Grenze ${_zahl(t.tierart.bindegewebeGrenze, nachkomma: 0)} %)',
                    farbe: t.bindegewebeUeberGrenze ? _fehler : _schwarz,
                  ),
                  _zelle('${mengeText(t.fleischKg)} kg'),
                ],
            ],
          ),
        ],
      ),
    if (e.warnungen.isNotEmpty ||
        e.ohneNaehrwerte.isNotEmpty ||
        e.ohneBeffe.isNotEmpty) ...[
      _abschnitt('Hinweise der Berechnung'),
      for (final w in e.warnungen) _punkt(w, farbe: _warn),
      if (e.ohneNaehrwerte.isNotEmpty)
        _punkt(
          'Ohne Nährwerte: ${e.ohneNaehrwerte.join(', ')} — die Tabelle ist '
          'zu niedrig.',
          farbe: _warn,
        ),
      if (e.ohneBeffe.isNotEmpty)
        _punkt('Ohne BEFFE-Wert: ${e.ohneBeffe.join(', ')}', farbe: _warn),
    ],
    ..._staendeVergleich(s, v),
    if (b.rezepturen.length > 1) ...[
      _abschnitt('Alle Rezepturen des Projekts'),
      _tabelle(
        kopf: const ['Rezeptur', 'Neuester Stand', 'Status', 'Datum'],
        breiten: const {
          0: pw.FlexColumnWidth(),
          1: pw.FixedColumnWidth(80),
          2: pw.FixedColumnWidth(80),
          3: pw.FixedColumnWidth(62),
        },
        zeilen: [
          for (final r in b.rezepturen)
            () {
              final staende =
                  b.versionen.values.where((x) => x.rezepturId == r.id).toList()
                    ..sort((a, c) => c.nummer.compareTo(a.nummer));
              final neu = staende.firstOrNull;
              return [
                _zelle(r.name),
                _zelle(neu == null ? '-' : 'Stand ${neu.nummer}'),
                _zelle(neu == null ? '' : _standStatus(s, neu)),
                _zelle(
                  neu == null
                      ? ''
                      : _datum(neu.abgeschlossenAm ?? neu.updatedAt),
                ),
              ];
            }(),
        ],
      ),
    ],
  ];
}

pw.Widget _naehrwertTabelle(_Satz s, RezepturErgebnis e) {
  final n = e.je100g;
  String wert(Naehrstoff st) {
    final w = naehrwertGerundet(st, naehrstoffWert(n, st));
    return w == '—' ? '-' : '$w ${st.einheit}';
  }

  final zielFett = s.p.zielFett;
  final zielEiweiss = s.p.zielEiweiss;
  final mitZiel = zielFett != null || zielEiweiss != null;
  pw.Widget ziel(double? z, String art, double? ist, {required bool max}) {
    if (z == null) return _zelle('');
    final passt = ist == null ? null : (max ? ist <= z : ist >= z);
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        if (passt != null) ...[
          _zeichen(passt ? _Zeichen.erledigt : _Zeichen.verfehlt),
          pw.SizedBox(width: 4),
        ],
        _zelle('$art ${_vorgabe(z)} g'),
      ],
    );
  }

  final zeilen = <List<pw.Widget>>[
    [
      _zelle('Energie'),
      _zelle('${wert(Naehrstoff.energieKj)} / ${wert(Naehrstoff.energieKcal)}'),
      if (mitZiel) _zelle(''),
    ],
    [
      _zelle('Fett'),
      _zelle(wert(Naehrstoff.fett)),
      if (mitZiel) ziel(zielFett, 'max.', n.fett, max: true),
    ],
    [
      _zelle('   davon gesättigte Fettsäuren'),
      _zelle(wert(Naehrstoff.gesaettigteFettsaeuren)),
      if (mitZiel) _zelle(''),
    ],
    [
      _zelle('Kohlenhydrate'),
      _zelle(wert(Naehrstoff.kohlenhydrate)),
      if (mitZiel) _zelle(''),
    ],
    [
      _zelle('   davon Zucker'),
      _zelle(wert(Naehrstoff.zucker)),
      if (mitZiel) _zelle(''),
    ],
    [
      _zelle('Eiweiß'),
      _zelle(wert(Naehrstoff.eiweiss)),
      if (mitZiel) ziel(zielEiweiss, 'min.', n.eiweiss, max: false),
    ],
    [_zelle('Salz'), _zelle(wert(Naehrstoff.salz)), if (mitZiel) _zelle('')],
  ];
  return pw.SizedBox(
    width: mitZiel ? 380 : 280,
    child: _tabelle(
      kopf: ['Nährwert', 'je 100 g', if (mitZiel) 'Ziel'],
      breiten: {
        0: const pw.FlexColumnWidth(),
        1: const pw.FixedColumnWidth(96),
        if (mitZiel) 2: const pw.FixedColumnWidth(100),
      },
      zeilen: zeilen,
    ),
  );
}

/// Die Stände der Rezeptur von [v] nebeneinander: Mengen je Zutat,
/// Verlust und die wichtigsten Kennzahlen. Fett, was sich zum Stand davor
/// geändert hat.
List<pw.Widget> _staendeVergleich(_Satz s, RezepturVersion v) {
  final b = s.b;
  final staende =
      b.versionen.values
          .where(
            (x) => x.rezepturId == v.rezepturId && b.eingaben[x.id] != null,
          )
          .toList()
        ..sort((a, c) => a.nummer.compareTo(c.nummer));
  if (staende.length < 2) return const [];
  final gezeigt = staende.length > 5
      ? staende.sublist(staende.length - 5)
      : staende;
  // Die Zutaten in der Reihenfolge des neuesten Stands, dann die, die es
  // nur früher gab.
  final namen = <String>[];
  for (final x in gezeigt.reversed) {
    for (final pos in b.eingaben[x.id]!.positionen) {
      final n = _positionsName(pos);
      if (!namen.contains(n)) namen.add(n);
    }
  }
  double? menge(RezepturVersion x, String name) {
    double? summe;
    for (final pos in b.eingaben[x.id]!.positionen) {
      if (_positionsName(pos) == name) summe = (summe ?? 0) + pos.mengeKg;
    }
    return summe;
  }

  List<pw.Widget> reihe(String titel, String Function(RezepturVersion x) wert) {
    final zellen = <pw.Widget>[_zelle(titel)];
    String? davor;
    for (final x in gezeigt) {
      final w = wert(x);
      final anders = davor != null && w != davor;
      zellen.add(
        _zelle(
          w.isEmpty ? '-' : w,
          fett: anders,
          farbe: anders ? _akzent : _schwarz,
        ),
      );
      davor = w;
    }
    return zellen;
  }

  String kennzahl(
    RezepturVersion x,
    double? Function(RezepturErgebnis e) f, {
    String einheit = ' g',
  }) {
    final e = b.ergebnisse[x.id];
    final w = e == null ? null : f(e);
    return w == null ? '' : '${_zahl(w)}$einheit';
  }

  final spalten = gezeigt.length + 1;
  return _mitTitel(
    _abschnitt(
      'Stände im Vergleich',
      zusatz:
          'Menge je Ansatz in kg · geändert gegenüber dem Stand davor: '
          'fett${staende.length > gezeigt.length ? ' · die letzten ${gezeigt.length} Stände' : ''}',
    ),
    zeilen: namen.length + 5,
    [
      _tabelle(
        kopf: [
          'Zutat',
          for (final x in gezeigt)
            'Stand ${x.nummer}${x.status == VersionStatus.abgeschlossen ? '' : ' (E)'}'
                '${x.id == v.id ? ' *' : ''}',
        ],
        rechts: {for (var i = 1; i < spalten; i++) i},
        breiten: {
          0: const pw.FlexColumnWidth(2.4),
          for (var i = 1; i < spalten; i++) i: const pw.FlexColumnWidth(),
        },
        zeilen: [
          for (final n in namen)
            reihe(n, (x) {
              final m = menge(x, n);
              return m == null ? '' : mengeText(m);
            }),
          reihe(
            'Verlust',
            (x) => Verlustart.aus(x.verlustArt) == Verlustart.keiner
                ? 'keiner'
                : prozentText(x.verlustProzent),
          ),
          reihe(
            'Fleischanteil',
            (x) => kennzahl(x, (e) => e.fleischanteilProzent, einheit: ' %'),
          ),
          reihe('Fett je 100 g', (x) => kennzahl(x, (e) => e.je100g.fett)),
          reihe('Eiweiß je 100 g', (x) => kennzahl(x, (e) => e.je100g.eiweiss)),
          reihe('Salz je 100 g', (x) {
            final e = b.ergebnisse[x.id];
            final w = e?.je100g.salz;
            return w == null ? '' : '${_zahl(w, nachkomma: 2)} g';
          }),
        ],
        hintergruende: [
          for (final _ in namen) null,
          for (var i = 0; i < 5; i++) _flaeche,
        ],
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 3),
        child: _t(
          '* der Stand dieses Berichts · (E) Entwurf',
          groesse: 7,
          farbe: _grau,
        ),
      ),
    ],
  );
}

// ── 3 Produkt und Spezifikation ────────────────────────────────────────

String _wahl(String schluessel, List<SpezWahl> liste) {
  if (schluessel.trim().isEmpty) return '';
  for (final w in liste) {
    if (w.schluessel == schluessel) return w.label;
  }
  return schluessel;
}

String _auswahl(Set<String> werte, List<SpezWahl> liste) => [
  for (final w in liste)
    if (werte.contains(w.schluessel)) w.label,
].join(', ');

List<pw.Widget> _kapitelProdukt(_Satz s, _Kapitel k) {
  final p = s.p;
  final sensorik = Sensorik.aus(p.sensorik);
  final spez = SpezAngaben.aus(p.spezifikation);
  final bild = _bildAus(s.b.bild);
  final gewicht = [
    sensorik.gewicht.trim(),
    if (spez.toleranz.trim().isNotEmpty) spez.toleranz.trim(),
  ].where((t) => t.isNotEmpty).join(' ');
  final sensorikFelder = [
    ('Aussehen', sensorik.aussehen),
    ('Geruch', sensorik.geruch),
    ('Geschmack', sensorik.geschmack),
    ('Konsistenz', sensorik.konsistenz),
    ('Länge', sensorik.laenge),
    ('Durchmesser', sensorik.durchmesser),
    ('Stückgewicht', gewicht),
    ('Zubereitung', sensorik.zubereitung),
  ];
  final hinweise = [
    for (final z in spez.hinweise.split(RegExp(r'\r?\n')))
      if (z.trim().isNotEmpty) z.trim(),
  ];
  final vp = spez.verpackung;
  final verpackung = <(String, String, String)>[
    (
      'Verpackung',
      _auswahl(vp.einzel, kEinzelverpackungen),
      _auswahl(vp.um, kUmverpackungen),
    ),
    (
      'Füllart',
      _wahl(vp.einzelFuellung, kEinzelFuellungen),
      _wahl(vp.umFuellung, kUmFuellungen),
    ),
    (
      'Inhalt',
      _oderNull(vp.stueckzahl) == null ? '' : '${vp.stueckzahl.trim()} Stück',
      _oderNull(vp.anzahl) == null
          ? ''
          : '${vp.anzahl.trim()} Einzelverpackungen',
    ),
    ('Nettogewicht', vp.einzelNetto, vp.umNetto),
    ('Tara', vp.einzelTara, vp.umTara),
    ('Material', vp.einzelMaterial, vp.umMaterial),
    ('Atmosphäre', _wahl(vp.atmosphaere, kAtmosphaeren), ''),
    ('Karton', '', _wahl(vp.karton, kKartonAufmachungen)),
  ].where((r) => r.$2.trim().isNotEmpty || r.$3.trim().isNotEmpty).toList();

  final etikett = lmivAus(p.etikettCheckliste);
  final geprueft = kEtikettCheckliste
      .where((c) => lmivStand(etikett, c.schluessel).geprueft)
      .length;
  final mitte = (kEtikettCheckliste.length + 1) ~/ 2;
  pw.Widget lmivSpalte(List<CheckPunkt> punkte) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      for (final c in punkte)
        switch (lmivStand(etikett, c.schluessel)) {
          LmivStand.erledigt => _mitZeichen(_Zeichen.erledigt, c.label),
          LmivStand.trifftNichtZu => _mitZeichen(
            _Zeichen.trifftNichtZu,
            c.label,
            zusatz: 'trifft nicht zu',
          ),
          LmivStand.offen => _mitZeichen(_Zeichen.offen, c.label),
        },
    ],
  );

  return [
    ..._kapitelKopf(s, k),
    _abschnitt('Sensorik'),
    if (sensorik.leer && bild == null)
      _leer('Noch keine Sensorik beschrieben.')
    else
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: sensorik.leer
                ? _leer('Noch keine Sensorik beschrieben.')
                : _felder(sensorikFelder, labelBreite: 92),
          ),
          if (bild != null)
            pw.Container(
              width: 190,
              height: 142,
              margin: const pw.EdgeInsets.only(left: 14),
              padding: const pw.EdgeInsets.all(3),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _linie, width: .6),
              ),
              child: pw.Image(bild, fit: pw.BoxFit.contain),
            ),
        ],
      ),
    _abschnitt('Spezifikation'),
    if (spez.leer)
      _leer('Noch keine Angaben für die Spezifikation.')
    else ...[
      _felder([
        ('Bezeichnung', spez.bezeichnung),
        ('Lagerung', spez.lagerung),
        ('Haltbarkeit', spez.haltbarkeit),
        ('Gewichtstoleranz', spez.toleranz),
        (
          'Spuren möglich',
          spez.spuren.isEmpty
              ? ''
              : merkmaleLabel(spez.spuren.join(','), kAllergene),
        ),
      ]),
      if (hinweise.isNotEmpty) ...[
        _etikett('Produkthinweise'),
        for (final h in hinweise) _punkt(h),
      ],
    ],
    if (verpackung.isNotEmpty)
      ..._mitTitel(_abschnitt('Verpackung'), zeilen: verpackung.length, [
        _tabelle(
          kopf: const ['', 'Einzelverpackung', 'Umverpackung'],
          breiten: const {
            0: pw.FixedColumnWidth(96),
            1: pw.FlexColumnWidth(),
            2: pw.FlexColumnWidth(),
          },
          zeilen: [
            for (final (l, einzel, um) in verpackung)
              [
                _zelle(l, farbe: _grau),
                _zelle(einzel.trim().isEmpty ? '-' : einzel),
                _zelle(um.trim().isEmpty ? '-' : um),
              ],
          ],
        ),
      ]),
    _zusammen([
      _abschnitt(
        'Etikett nach LMIV',
        zusatz:
            '$geprueft von ${kEtikettCheckliste.length} Pflichtangaben '
            'geprüft',
      ),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: lmivSpalte(kEtikettCheckliste.sublist(0, mitte))),
          pw.SizedBox(width: 16),
          pw.Expanded(child: lmivSpalte(kEtikettCheckliste.sublist(mitte))),
        ],
      ),
    ]),
  ];
}

// ── 4 Herstellung und HACCP ────────────────────────────────────────────

/// Die Farbe einer Abteilung.
PdfColor _abteilungsFarbe(String wert) {
  final a = abteilungAus(wert);
  return a == null ? _grau : PdfColor.fromInt(a.farbwert);
}

/// Das Band über einer Station.
pw.Widget _stationsBand(int nr, String abteilung, {String? zusatz}) =>
    pw.Container(
      margin: const pw.EdgeInsets.only(top: 8, bottom: 2),
      padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: pw.BoxDecoration(color: _abteilungsFarbe(abteilung)),
      child: pw.Row(
        children: [
          _t('STATION $nr', groesse: 7.5, fett: true, farbe: PdfColors.white),
          pw.SizedBox(width: 8),
          _t(abteilungsName(abteilung), groesse: 8.5, farbe: PdfColors.white),
          if (zusatz != null) ...[
            pw.Spacer(),
            _t(zusatz, groesse: 7.5, farbe: PdfColors.white),
          ],
        ],
      ),
    );

/// Was von einem Schritt im Bericht steht: die Maschineneinstellungen und
/// die eingetragenen Werte — die Platten zeigt [_plattenRaster].
List<(String, String)> _schrittWerte(ProzessSchritt s) => [
  if (s.notiz.trim().isNotEmpty) ('Maschineneinstellungen', s.notiz.trim()),
  for (final w in s.werte)
    if (!istPlattenWert(w) && !w.leer) (w.label, w.wert.trim()),
];

/// Die Platten eines Schritts an Bratstraße oder Kombiofen als Raster —
/// wie im Prozessblatt, etwas kleiner. Null ohne Raster oder ohne eine
/// gesetzte Platte.
pw.Widget? _plattenRaster(ProzessSchritt s) {
  final gruppe = plattenGruppe(s.maschine);
  if (gruppe == null) return null;
  final namen = plattenZeilenFuer(s.maschine);
  if (!namen.any((n) => plattenWert(s, n, gruppe).trim().isNotEmpty)) {
    return null;
  }
  return plattenRasterPdf(
    kombiofen: gruppe == kPlattenGruppeKombi,
    zonen: namen.where((n) => n.startsWith('Platte Unten ')).length,
    wert: (name) {
      final w = plattenWert(s, name, gruppe).trim();
      return w.isEmpty ? null : double.tryParse(w.replaceAll(',', '.'));
    },
    massstab: .82,
  );
}

/// Woran zwei Schritte gleich sind: Abteilung, Anlage, Prozessschritt,
/// Einstellungen und Werte — ohne Einheiten und Gruppen, die der Artikel
/// anders führt.
String _signatur(ProzessSchritt s, [List<(String, String)> mehr = const []]) =>
    [
      s.abteilung,
      s.maschine.trim().toLowerCase(),
      s.prozessschritt.trim().toLowerCase(),
      s.notiz.trim(),
      ...([
        for (final w in s.werte)
          if (!w.leer) '${w.name.trim().toLowerCase()}=${w.wert.trim()}',
        for (final (l, w) in mehr) '${l.trim().toLowerCase()}=${w.trim()}',
      ]..sort()),
    ].join('|');

/// Ein Schritt mit seinen Werten.
pw.Widget _schrittBlock(
  int nr,
  ProzessSchritt s, {
  List<(String, String)> mehr = const [],
  String? zusatz,
}) {
  final prozess = s.prozessschritt.trim();
  final titel = s.maschine.trim().isNotEmpty && prozess.isNotEmpty
      ? '${s.bezeichnung(nr)} - $prozess'
      : s.bezeichnung(nr);
  final zeilen = [..._schrittWerte(s), ...mehr];
  final raster = _plattenRaster(s);
  return pw.Padding(
    padding: const pw.EdgeInsets.only(left: 4, top: 5, bottom: 2),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: 15,
              height: 15,
              alignment: pw.Alignment.center,
              decoration: const pw.BoxDecoration(
                color: _akzentHell,
                shape: pw.BoxShape.circle,
              ),
              child: _t('$nr', groesse: 7.5, fett: true, farbe: _akzent),
            ),
            pw.SizedBox(width: 6),
            pw.Expanded(
              child: pw.Padding(
                padding: const pw.EdgeInsets.only(top: 2),
                child: _t(titel, groesse: 9.5, fett: true),
              ),
            ),
            if (zusatz != null)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 2, left: 8),
                child: _t(zusatz, groesse: 7.5, farbe: _grau),
              ),
          ],
        ),
        if (zeilen.isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 21, top: 2),
            child: _felder(zeilen, labelBreite: 130, groesse: 8.3),
          ),
        if (raster != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 21, top: 5, bottom: 2),
            child: raster,
          ),
      ],
    ),
  );
}

/// Die Kette nach Stationen.
List<pw.Widget> _kette(
  List<ProzessSchritt> schritte, {
  Map<String, List<(String, String)>> mehr = const {},
  Map<String, String> zusatz = const {},
}) {
  final widgets = <pw.Widget>[];
  var nr = 0;
  for (final (i, station) in stationenAus(schritte).indexed) {
    final schrittBloecke = <pw.Widget>[];
    for (final schritt in station) {
      nr++;
      schrittBloecke.add(
        _schrittBlock(
          nr,
          schritt,
          mehr: mehr[schritt.id] ?? const [],
          zusatz: zusatz[schritt.id],
        ),
      );
    }
    // Das Band bleibt bei seinem ersten Schritt.
    widgets
      ..add(
        _zusammen([
          _stationsBand(i + 1, station.first.abteilung),
          schrittBloecke.first,
        ]),
      )
      ..addAll(schrittBloecke.skip(1));
  }
  return widgets;
}

/// Maschineneinstellungen, die ein Artikel noch im alten Feld trägt.
List<(String, String)> _alteEinstellungen(String? json) {
  final roh = json?.trim() ?? '';
  if (roh.isEmpty) return const [];
  try {
    final daten = jsonDecode(roh);
    if (daten is Map<String, dynamic>) {
      return [
        for (final MapEntry(:key, :value) in daten.entries)
          if (value != null && '$value'.trim().isNotEmpty) (key, '$value'),
      ];
    }
    if (daten is List) {
      return [
        for (final (i, w) in daten.indexed)
          if (w != null && '$w'.trim().isNotEmpty)
            ('Einstellung ${i + 1}', '$w'),
      ];
    }
  } on FormatException {
    // Freier Text von früher.
  }
  return [('Maschineneinstellungen', roh)];
}

/// Personen und Leistung eines Artikelschritts.
String? _leistung(ProductStep s) {
  final teile = <String>[
    if (s.basisMitarbeiter > 0)
      '${s.basisMitarbeiter} ${s.basisMitarbeiter == 1 ? 'Person' : 'Personen'}',
    if (s.basisMengeKg > 0 && s.basisDauerMinuten > 0)
      '${mengeText(s.basisMengeKg)} kg in ${_zahl(s.basisDauerMinuten, nachkomma: 0)} min',
  ];
  return teile.isEmpty ? null : teile.join(' · ');
}

List<pw.Widget> _kapitelHerstellung(_Satz s, _Kapitel k) {
  final b = s.b;
  final p = s.p;
  final prozess = Prozessparameter.aus(p.prozess);
  final historie = ProzessStand.listeAus(p.prozessHistorie);
  final fassung = prozessFassung(prozess, historie);
  final artikel = b.artikel;
  final haccp = Haccp.aus(p.haccp);

  // Die Schritte des Artikels wie die des Projekts.
  final artikelKette = [
    for (final a in b.artikelSchritte)
      schrittAusArtikel(
        id: a.schritt.id,
        abteilung: a.schritt.abteilung,
        maschineId: a.schritt.maschineId,
        maschine: a.schritt.maschine ?? a.maschine?.name,
        prozessschritt: a.schritt.prozessschritt,
        parameter: [
          for (final x in a.parameter)
            (
              gruppe: x.parameterGruppe,
              name: x.parameterName,
              wert: x.wert,
              eigen: x.istCustom,
            ),
        ],
      ),
  ];

  final alteWerte = {
    for (final a in b.artikelSchritte)
      a.schritt.id: _alteEinstellungen(a.schritt.maschinenEinstellungenJson),
  };
  final leistung = {
    for (final a in b.artikelSchritte)
      if (_leistung(a.schritt) case final l?) a.schritt.id: l,
  };
  // Hat der Artikel die Kette des Projekts — so, wie die Freigabe sie
  // übernommen hat —, steht sie nur einmal da, mit Personen und Leistung
  // aus dem Artikel.
  final wieImProjekt =
      artikelKette.isNotEmpty &&
      artikelKette.length == prozess.schritte.length &&
      [
        for (final (i, a) in artikelKette.indexed)
          _signatur(a, alteWerte[a.id] ?? const []) ==
              _signatur(prozess.schritte[i]),
      ].every((gleich) => gleich);
  final nummer = artikel?.artikelnummer ?? '';
  return [
    ..._kapitelKopf(s, k),
    _abschnitt(
      'Prozess',
      zusatz: prozess.leer
          ? null
          : '${fassung.text} · ${prozessKurztext(prozess)}',
    ),
    if (prozess.leer && artikelKette.isEmpty)
      _leer('Noch kein Prozess beschrieben.'),
    if (wieImProjekt)
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 2),
        child: _t(
          'So auch im Artikel $nummer hinterlegt — Personen und Leistung je '
          'Schritt aus der Planung.',
          groesse: 8,
          farbe: _grau,
        ),
      ),
    if (prozess.schritte.isNotEmpty)
      ..._kette(
        prozess.schritte,
        zusatz: wieImProjekt
            ? {
                for (final (i, a) in artikelKette.indexed)
                  if (leistung[a.id] case final l?) prozess.schritte[i].id: l,
              }
            : const {},
      ),
    for (final a in prozess.abschnitte)
      _zusammen([
        _etikett(a.titel),
        _felder([for (final f in a.felder) (f.label, f.wert)]),
      ]),
    if (artikelKette.isNotEmpty && !wieImProjekt) ...[
      _abschnitt(
        'Prozess im Artikel $nummer',
        zusatz: prozess.schritte.isEmpty
            ? 'aus der Planung, mit Personen und Leistung'
            : 'weicht vom Projekt ab · aus der Planung, mit Personen und '
                  'Leistung',
      ),
      ..._kette(artikelKette, mehr: alteWerte, zusatz: leistung),
    ],
    if (historie.isNotEmpty)
      ..._mitTitel(
        _abschnitt('Festgehaltene Versionen'),
        zeilen: historie.length,
        [
          _tabelle(
            kopf: const ['Version', 'Datum', 'Was sich geändert hat', 'Kette'],
            breiten: const {
              0: pw.FixedColumnWidth(46),
              1: pw.FixedColumnWidth(62),
              2: pw.FlexColumnWidth(),
              3: pw.FixedColumnWidth(110),
            },
            zeilen: [
              for (final st in historie.reversed)
                [
                  _zelle(st.version, fett: true),
                  _zelle(_datum(st.datum)),
                  _zelle(st.notiz.trim().isEmpty ? '-' : st.notiz.trim()),
                  _zelle(prozessKurztext(st.parameter), farbe: _grau),
                ],
            ],
          ),
        ],
      ),
    if (haccp.gefahren.isEmpty) ...[
      _abschnitt('HACCP-Gefahrenanalyse'),
      _leer('Noch keine Gefahren bewertet.'),
    ] else
      ..._mitTitel(
        _abschnitt('HACCP-Gefahrenanalyse'),
        zeilen: haccp.gefahren.length,
        [
          _tabelle(
            kopf: const ['Gefahr', 'Art', 'S x W', 'Risiko', 'Maßnahmen'],
            breiten: const {
              0: pw.FlexColumnWidth(2),
              1: pw.FixedColumnWidth(72),
              2: pw.FixedColumnWidth(34),
              3: pw.FixedColumnWidth(54),
              4: pw.FlexColumnWidth(2.4),
            },
            zeilen: [
              for (final g in haccp.gefahren)
                [
                  _zelle(g.gefahr),
                  _zelle(g.art.label, farbe: _grau),
                  _zelle('${g.schwere} x ${g.wahrscheinlichkeit}'),
                  _markeZelle(
                    '${g.risiko} ${g.risiko >= 6 ? 'HOCH' : (g.risiko >= 3 ? 'MITTEL' : 'GERING')}',
                    g.risiko >= 6 ? _fehler : (g.risiko >= 3 ? _warn : _ok),
                    voll: true,
                  ),
                  _zelle(g.massnahmen),
                ],
            ],
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 3),
            child: _t(
              'S Schwere, W Wahrscheinlichkeit (je 1 bis 3) · Risiko = S x W: '
              '1-2 gering, 3-4 mittel, 6-9 hoch',
              groesse: 7,
              farbe: _grau,
            ),
          ),
        ],
      ),
    if (haccp.lenkungspunkte.isNotEmpty)
      ..._mitTitel(
        _abschnitt('Lenkungspunkte'),
        zeilen: haccp.lenkungspunkte.length,
        [
          _tabelle(
            kopf: const [
              'Einstufung',
              'Prozessschritt',
              'Lenkung',
              'Entscheidungsbaum',
            ],
            breiten: const {
              0: pw.FixedColumnWidth(58),
              1: pw.FlexColumnWidth(1.4),
              2: pw.FlexColumnWidth(2.4),
              3: pw.FlexColumnWidth(1.4),
            },
            zeilen: [
              for (final l in haccp.lenkungspunkte)
                [
                  _markeZelle(
                    l.ergebnis.kuerzel,
                    switch (l.ergebnis) {
                      Lenkungsart.ccp => _fehler,
                      Lenkungsart.cp => _warn,
                      Lenkungsart.kp => _grau,
                    },
                    voll: true,
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _zelle(l.schritt),
                      if (l.beschreibung.trim().isNotEmpty)
                        _zelle(
                          l.beschreibung.trim(),
                          farbe: _grau,
                          groesse: 7.5,
                        ),
                    ],
                  ),
                  _zelle(l.lenkung),
                  _zelle(
                    [
                      for (final a in l.antworten.entries)
                        '${kEntscheidungsbaum[a.key]?.kurz ?? a.key}: '
                            '${a.value ? 'ja' : 'nein'}',
                    ].join(' · '),
                    farbe: _grau,
                    groesse: 7.5,
                  ),
                ],
            ],
          ),
        ],
      ),
  ];
}

// ── 5 Freigabe und Checkliste ──────────────────────────────────────────

List<pw.Widget> _kapitelFreigabe(_Satz s, _Kapitel k) {
  final b = s.b;
  final p = s.p;
  final artikel = b.artikel;
  final check = _check(s);
  final freigabeStand = b.versionen[p.freigabeVersionId];
  final a = b.abgleich;
  return [
    ..._kapitelKopf(s, k),
    _abschnitt('Freigabe als Artikel'),
    if (artikel == null)
      _leer(
        p.artikelId == null
            ? 'Noch nicht als Artikel freigegeben.'
            : 'Der freigegebene Artikel ist nicht mehr da.',
      )
    else ...[
      _felder([
        (
          'Artikel',
          '${artikel.artikelnummer} · ${artikel.artikelbezeichnung}'
              '${artikel.deletedAt == null ? '' : ' (im Planer gelöscht)'}',
        ),
        ('Freigegeben am', _datum(p.freigegebenAm)),
        (
          'Rezepturstand',
          freigabeStand == null
              ? ''
              : 'Stand ${freigabeStand.nummer}'
                    '${b.rezepturName == null ? '' : ' · ${b.rezepturName}'}',
        ),
        ('Produktgruppe', produktgruppeLabel(artikel.produktgruppe)),
        (
          'Haltbarkeit',
          artikel.haltbarkeitTage == null
              ? ''
              : '${artikel.haltbarkeitTage} Tage',
        ),
        ('Allergene', merkmaleLabel(artikel.allergene, kAllergene)),
        (
          'aw-Wert (Ziel)',
          artikel.zielAw == null ? '' : _zahl(artikel.zielAw, nachkomma: 2),
        ),
      ]),
      if (a != null) ...[
        _etikett('Verlust in der Produktion'),
        _fliess(
          'Verlust ${a.produktionen == 1 ? 'der letzten Produktion' : 'im Mittel der letzten ${a.produktionen} Produktionen'}: '
          '${prozentText(a.gemessenProzent)} — die Rezeptur rechnet mit '
          '${prozentText(a.rezepturProzent)}.',
        ),
        if (a.fleischZuHoch &&
            a.fleischRezeptur != null &&
            a.fleischGemessen != null)
          _punkt(
            'Mit dem gemessenen Verlust enthält das Produkt '
            '${prozentText(a.fleischGemessen!)} Fleisch — die Rezeptur und '
            'das Etikett nennen ${prozentText(a.fleischRezeptur!)}. '
            'Verlust in der Rezeptur anpassen und die Mengenangaben prüfen.',
            farbe: _fehler,
          )
        else if (a.verlustWeichtAb)
          _punkt(
            'Der gemessene Verlust weicht um '
            '${_zahl(a.differenz.abs())} Prozentpunkte ab.',
            farbe: _warn,
          )
        else
          _punkt('Rezeptur und Produktion passen zusammen.', farbe: _ok),
      ],
    ],
    _abschnitt('Projekt-Checkliste', zusatz: '${check.text} erledigt'),
    for (final c in check.punkte)
      _mitZeichen(
        c.erledigt
            ? _Zeichen.erledigt
            : (c.zurueckgestellt ? _Zeichen.spaeter : _Zeichen.offen),
        c.punkt.label,
        zusatz: [
          if (c.zurueckgestellt && !c.erledigt) 'zurückgestellt',
          if (c.vonHand) 'von Hand',
          if (_oderNull(c.text) case final t?) t,
        ].join(' · '),
      ),
  ];
}

// ── 6 Entwicklungsweg ──────────────────────────────────────────────────

List<pw.Widget> _kapitelWeg(_Satz s, _Kapitel k) {
  final b = s.b;
  final weg = entwicklungsweg(b.verlauf);
  final projektStaende =
      b.versionen.values
          .where((v) => b.rezepturen.any((r) => r.id == v.rezepturId))
          .toList()
        ..sort((a, c) {
          final r = a.rezepturId.compareTo(c.rezepturId);
          return r != 0 ? r : a.nummer.compareTo(c.nummer);
        });
  final namen = {for (final r in b.rezepturen) r.id: r.name};
  final mehrereRezepturen = b.rezepturen.length > 1;

  final widgets = <pw.Widget>[
    ..._kapitelKopf(
      s,
      k,
      untertitel:
          'Von der Idee über die Rezepturstände bis zur Freigabe — '
          'der älteste Schritt zuerst.',
    ),
  ];
  if (projektStaende.isNotEmpty) {
    widgets.addAll([
      _abschnitt('Die Stände im Überblick'),
      _tabelle(
        kopf: [
          if (mehrereRezepturen) 'Rezeptur',
          'Stand',
          'Status',
          'Datum',
          'Grund',
          'Fleisch',
          'Fett',
          'Salz',
        ],
        rechts: {for (var i = 0; i < 3; i++) (mehrereRezepturen ? 5 : 4) + i},
        breiten: {
          if (mehrereRezepturen) 0: const pw.FlexColumnWidth(1.4),
          (mehrereRezepturen ? 1 : 0): const pw.FixedColumnWidth(34),
          (mehrereRezepturen ? 2 : 1): const pw.FixedColumnWidth(72),
          (mehrereRezepturen ? 3 : 2): const pw.FixedColumnWidth(54),
          (mehrereRezepturen ? 4 : 3): const pw.FlexColumnWidth(2.6),
          (mehrereRezepturen ? 5 : 4): const pw.FixedColumnWidth(42),
          (mehrereRezepturen ? 6 : 5): const pw.FixedColumnWidth(36),
          (mehrereRezepturen ? 7 : 6): const pw.FixedColumnWidth(38),
        },
        zeilen: [
          for (final v in projektStaende)
            () {
              final e = b.ergebnisse[v.id];
              final status = _standStatus(s, v);
              return [
                if (mehrereRezepturen) _zelle(namen[v.rezepturId] ?? ''),
                _zelle('${v.nummer}', fett: true),
                _zelle(
                  status,
                  farbe: switch (status) {
                    'freigegeben' => _ok,
                    'Entwurf' => _warn,
                    _ => _schwarz,
                  },
                ),
                _zelle(_datum(v.abgeschlossenAm ?? v.updatedAt)),
                _zelle(_oderNull(v.notiz) ?? '-', groesse: 7.8),
                _zelle(e == null ? '' : prozentText(e.fleischanteilProzent)),
                _zelle(
                  e?.je100g.fett == null ? '' : '${_zahl(e!.je100g.fett)} g',
                ),
                _zelle(
                  e?.je100g.salz == null
                      ? ''
                      : '${_zahl(e!.je100g.salz, nachkomma: 2)} g',
                ),
              ];
            }(),
        ],
      ),
    ]);
  }

  widgets.add(_abschnitt('Der Weg'));
  for (final punkt in weg) {
    switch (punkt) {
      case WegAnfang(:final eintraege):
        widgets.add(
          _wegKopf(
            'START',
            'Idee und Anfrage · ${_datum(s.p.createdAt)}',
            _akzent,
          ),
        );
        for (final e in eintraege) {
          widgets.add(_wegEintrag(s, e));
        }
      case WegStation():
        widgets.addAll(_wegStation(s, punkt));
      case WegPhase():
        final e = punkt.eintrag;
        final w = statusWechsel(e);
        widgets.add(
          _wegKopf(
            'PHASE',
            [
              if (w == null)
                _phasenName(punkt.status)
              else
                '${w.alt == null ? '' : '${_phasenName(w.alt!)} » '}'
                    '${_phasenName(w.neu)}',
              _datum(e.datum),
              e.titel,
            ].join(' · '),
            _phasenFarbe(punkt.status),
          ),
        );
        for (final a in texteAus(e.aenderungen)) {
          widgets.add(_punkt(a, einzug: 12, farbe: _grau));
        }
    }
  }
  if (!weg.any((w) => w is WegStation)) {
    widgets.add(_leer('Noch kein abgeschlossener Rezepturstand.'));
  }
  for (final a in b.inArbeit) {
    final e = b.ergebnisse[a.version.id];
    widgets.add(
      _zusammen([
        _wegKopf(
          'IN ARBEIT',
          [
            if (a.rezeptur.isNotEmpty) a.rezeptur,
            'Stand ${a.version.nummer} · Entwurf',
            'zuletzt geändert ${_datum(a.version.updatedAt)}',
          ].join(' · '),
          _warn,
        ),
        if (e != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 12, top: 2),
            child: _t(
              'Fleisch ${prozentText(e.fleischanteilProzent)} · '
              'Fett ${_zahl(e.je100g.fett)} g · '
              'Salz ${_zahl(e.je100g.salz, nachkomma: 2)} g je 100 g',
              groesse: 8,
              farbe: _grau,
            ),
          ),
      ]),
    );
  }
  return widgets;
}

/// Die Kopfzeile eines Schritts auf dem Weg.
pw.Widget _wegKopf(String art, String text, PdfColor farbe) => pw.Container(
  margin: const pw.EdgeInsets.only(top: 9, bottom: 2),
  padding: const pw.EdgeInsets.fromLTRB(7, 4, 7, 4),
  decoration: pw.BoxDecoration(
    color: _flaeche,
    border: pw.Border(left: pw.BorderSide(color: farbe, width: 3)),
  ),
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(
        width: 62,
        child: _t(art, groesse: 7, fett: true, farbe: farbe, sperrung: .4),
      ),
      pw.Expanded(child: _t(text, groesse: 8.8, fett: true)),
    ],
  ),
);

/// Ein Eintrag knapp: Datum, Art und Titel — mit Beschreibung.
pw.Widget _wegEintrag(_Satz s, ProjektEintrag e) {
  final offen = EintragStatus.aus(e.status) == EintragStatus.offen;
  final vorbei = eintragUeberfaellig(e, heute: s.jetzt);
  final beschreibung = _oderNull(e.beschreibung);
  return pw.Padding(
    padding: const pw.EdgeInsets.only(left: 12, top: 3),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 54,
              child: _t(_datum(e.datum), groesse: 8, farbe: _grau),
            ),
            pw.SizedBox(
              width: 58,
              child: _t(EintragArt.aus(e.art).label, groesse: 8, farbe: _grau),
            ),
            pw.Expanded(child: _t(e.titel, groesse: 8.5)),
            if (offen) ...[
              pw.SizedBox(width: 6),
              vorbei ? _marke('ÜBERFÄLLIG', _fehler) : _marke('OFFEN', _warn),
            ],
          ],
        ),
        if (beschreibung != null && beschreibung.length <= 400)
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 112, top: 1),
            child: _t(beschreibung, groesse: 7.8, farbe: _grau),
          )
        else if (beschreibung != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 112, top: 1),
            child: _t(
              '${beschreibung.substring(0, 400)} ... (vollständig im Verlauf)',
              groesse: 7.8,
              farbe: _grau,
            ),
          ),
      ],
    ),
  );
}

List<pw.Widget> _wegStation(_Satz s, WegStation punkt) {
  final b = s.b;
  final e = punkt.eintrag;
  final v = b.versionen[punkt.versionId];
  final nummer = v?.nummer ?? punkt.nummer;
  final kennzahlen = b.kennzahlen[punkt.versionId] ?? const <WegKennzahl>[];
  final aenderungen = texteAus(e.aenderungen);
  final grund = _oderNull(v?.notiz);
  // Ein kurzer Grund steht neben „Warum", ein langer darf umbrechen.
  final kurz = grund != null && grund.length <= 500;
  final freigegeben = s.p.freigabeVersionId == punkt.versionId;
  final rezeptur = b.rezepturen
      .where((r) => r.id == v?.rezepturId)
      .firstOrNull
      ?.name;
  return [
    _zusammen([
      _wegKopf(
        'STAND $nummer',
        [
          if (rezeptur != null && b.rezepturen.length > 1) rezeptur,
          'abgeschlossen ${_datum(v?.abgeschlossenAm ?? e.datum)}',
          if (freigegeben) 'freigegeben',
        ].join(' · '),
        freigegeben ? _ok : _station,
      ),
      if (grund != null && kurz)
        pw.Padding(
          padding: const pw.EdgeInsets.only(left: 12, top: 3),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 60,
                child: _t('Warum', groesse: 8, farbe: _grau),
              ),
              pw.Expanded(child: _t(grund, groesse: 8.5)),
            ],
          ),
        ),
      if (kennzahlen.isNotEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.only(left: 12, top: 4),
          child: pw.Wrap(
            spacing: 5,
            runSpacing: 3,
            children: [
              for (final kz in kennzahlen)
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: _linie, width: .6),
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(2.5),
                    ),
                  ),
                  child: pw.RichText(
                    text: pw.TextSpan(
                      style: const pw.TextStyle(fontSize: 7.6, color: _grau),
                      children: [
                        pw.TextSpan(text: pdfText('${kz.label} ')),
                        pw.TextSpan(
                          text: pdfText(kz.wert),
                          style: pw.TextStyle(
                            color: _schwarz,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        if (kz.aenderung case final d?)
                          pw.TextSpan(
                            text: pdfText(' ($d)'),
                            style: const pw.TextStyle(color: _akzent),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
    ]),
    if (grund != null && !kurz) ...[
      pw.Padding(
        padding: const pw.EdgeInsets.only(left: 12, top: 4),
        child: _t('Warum', groesse: 8, farbe: _grau),
      ),
      _fliess(grund, groesse: 8.5, einzug: 12),
    ],
    if (aenderungen.isNotEmpty) ...[
      pw.Padding(
        padding: const pw.EdgeInsets.only(left: 12, top: 4),
        child: _t('Was sich geändert hat', groesse: 8, farbe: _grau),
      ),
      for (final a in aenderungen) _punkt(a, einzug: 12),
    ],
    if (punkt.rueckmeldungen.isNotEmpty) ...[
      pw.Padding(
        padding: const pw.EdgeInsets.only(left: 12, top: 4),
        child: _t('Rückmeldungen dazu', groesse: 8, farbe: _grau),
      ),
      for (final r in punkt.rueckmeldungen) _wegEintrag(s, r),
    ],
  ];
}

// ── 7 Verlauf ──────────────────────────────────────────────────────────

// Der Verlauf als Zeitstrahl — wie in der App: eine Achse in der Farbe der
// Phase, die Einträge vom ältesten links zum neuesten rechts gleichmäßig
// verteilt, abwechselnd oben und unten an kurzen und langen Stielen, jede
// Art mit ihrer Farbe und ihrem Zeichen. Die Rezepturstände sind
// nummerierte Stationen auf der Achse; ein Eintrag zu einem Stand hängt
// mit einer gestrichelten Linie an seiner Station. Auf dem Papier läuft
// der Strahl in Zeilen zu sechs Einträgen — darunter steht jeder Eintrag
// im Einzelnen, nach Monaten.

/// Die Farbe einer Eintragsart — wie auf dem Zeitstrahl der App.
PdfColor _artFarbe(EintragArt a) => switch (a) {
  EintragArt.meilenstein => _akzent,
  EintragArt.rezeptur => _station,
  EintragArt.email => const PdfColor.fromInt(0xFFC77700),
  EintragArt.datei => const PdfColor.fromInt(0xFF2F6FD0),
  EintragArt.parameter => const PdfColor.fromInt(0xFF0F7A6E),
  EintragArt.notiz => const PdfColor.fromInt(0xFF5B6675),
};

/// [farbe], um [anteil] zum Weiß hin aufgehellt.
PdfColor _hell(PdfColor farbe, double anteil) => PdfColor(
  farbe.red + (1 - farbe.red) * anteil,
  farbe.green + (1 - farbe.green) * anteil,
  farbe.blue + (1 - farbe.blue) * anteil,
);

/// Malt das Symbol einer Eintragsart: einen Kreis mit dem Radius [r] um
/// ([x], [y]) in der Farbe der Art, darin weiß ihr Zeichen — eine Fahne,
/// ein offenes Buch, ein Brief, Regler, ein Blatt, Notizzeilen.
void _symbolMalen(
  PdfGraphics c,
  EintragArt art,
  double x,
  double y,
  double r,
) {
  c
    ..setFillColor(_artFarbe(art))
    ..drawEllipse(x, y, r, r)
    ..fillPath()
    ..setStrokeColor(PdfColors.white)
    ..setFillColor(PdfColors.white)
    ..setLineWidth(r * .14)
    ..setLineCap(PdfLineCap.round)
    ..setLineJoin(PdfLineJoin.round);
  final s = r * .52;
  switch (art) {
    case EintragArt.meilenstein:
      c
        ..moveTo(x - s * .55, y - s * .95)
        ..lineTo(x - s * .55, y + s * .95)
        ..strokePath()
        ..moveTo(x - s * .55, y + s * .95)
        ..lineTo(x + s * .85, y + s * .5)
        ..lineTo(x - s * .55, y + s * .02)
        ..closePath()
        ..fillPath();
    case EintragArt.rezeptur:
      for (final seite in [-1.0, 1.0]) {
        c
          ..moveTo(x, y + s * .55)
          ..lineTo(x + seite * s, y + s * .8)
          ..lineTo(x + seite * s, y - s * .55)
          ..lineTo(x, y - s * .8)
          ..closePath()
          ..strokePath();
      }
    case EintragArt.email:
      c
        ..drawRect(x - s, y - s * .68, 2 * s, 1.36 * s)
        ..strokePath()
        ..moveTo(x - s, y + s * .68)
        ..lineTo(x, y - s * .05)
        ..lineTo(x + s, y + s * .68)
        ..strokePath();
    case EintragArt.parameter:
      for (final (hoehe, knopf) in [(.55, .35), (0.0, -.4), (-.55, .1)]) {
        c
          ..moveTo(x - s, y + s * hoehe)
          ..lineTo(x + s, y + s * hoehe)
          ..strokePath()
          ..drawEllipse(x + s * knopf, y + s * hoehe, s * .24, s * .24)
          ..fillPath();
      }
    case EintragArt.datei:
      c
        ..moveTo(x - s * .7, y - s)
        ..lineTo(x - s * .7, y + s)
        ..lineTo(x + s * .25, y + s)
        ..lineTo(x + s * .7, y + s * .55)
        ..lineTo(x + s * .7, y - s)
        ..closePath()
        ..strokePath()
        ..moveTo(x + s * .25, y + s)
        ..lineTo(x + s * .25, y + s * .55)
        ..lineTo(x + s * .7, y + s * .55)
        ..strokePath();
    case EintragArt.notiz:
      for (final (hoehe, ende) in [(.5, .8), (0.0, .8), (-.5, .3)]) {
        c
          ..moveTo(x - s * .8, y + s * hoehe)
          ..lineTo(x + s * ende, y + s * hoehe)
          ..strokePath();
      }
  }
}

/// Das Symbol einer Eintragsart als eigenes Bild — für Legende und Liste.
pw.Widget _symbol(EintragArt art, {double groesse = 11}) => pw.SizedBox(
  width: groesse,
  height: groesse,
  child: pw.CustomPaint(
    size: PdfPoint(groesse, groesse),
    painter: (c, size) =>
        _symbolMalen(c, art, size.x / 2, size.y / 2, size.x / 2),
  ),
);

/// [text] auf höchstens [zeichen] Zeichen gekürzt — am Wortende, mit „…".
String _gekuerzt(String text, int zeichen) {
  final t = text.trim();
  if (t.length <= zeichen) return t;
  final schnitt = t.lastIndexOf(' ', zeichen - 1);
  return '${t.substring(0, schnitt > zeichen ~/ 2 ? schnitt : zeichen - 1)}…';
}

// Maße einer Zeile: Symbol, kurzer und langer Stiel, Platz der
// Beschriftung — oben und unten gleich.
const double _zsSymbol = 14;
const double _zsKurz = 10;
const double _zsLang = 30;
const double _zsKarte = 40;
const double _zsHaelfte = _zsLang + _zsSymbol + 3 + _zsKarte;

/// Wo ein Eintrag am Strahl hängt: oben oder unten, kurz oder lang — im
/// Takt von vier wie in der App, damit Nachbarn sich nicht in die Quere
/// kommen.
({bool oben, bool lang}) _platz(int index) {
  final takt = index % 4;
  return (oben: takt == 0 || takt == 2, lang: takt == 2 || takt == 3);
}

List<pw.Widget> _kapitelVerlauf(_Satz s, _Kapitel k) {
  final b = s.b;
  final eintraege = zeitlichSortiert(b.verlauf);
  final zahl = offeneZaehlen(eintraege, heute: s.jetzt);
  final offen = zahl.ueberfaellig == 0
      ? ' · ${zahl.offen} offen'
      : ' · ${zahl.offen} offen, ${zahl.ueberfaellig} überfällig';
  final phasen = statusJeEintrag(eintraege, ProjektStatus.aus(s.p.status));
  final erster = eintraege.first.datum;
  final letzter = eintraege.last.datum;
  return [
    ..._kapitelKopf(
      s,
      k,
      untertitel: eintraege.length == 1
          ? 'Ein Eintrag vom ${_datum(erster)}'
                '${zahl.offen == 0 ? '' : offen}.'
          : '${eintraege.length} Einträge vom ${_datum(erster)} bis '
                '${_datum(letzter)}${zahl.offen == 0 ? '' : offen}.',
    ),
    if (s.inhalt.zeitstrahl) ...[
      _zeitstrahlLegende(eintraege, phasen),
      ..._zeitstrahl(s, eintraege, phasen),
    ],
    if (s.inhalt.verlaufEinzeln) ...[
      if (s.inhalt.zeitstrahl)
        _abschnitt('Im Einzelnen', zusatz: 'der älteste Eintrag zuerst'),
      ..._verlaufImEinzelnen(s, eintraege),
    ],
  ];
}

/// Was die Farben und Zeichen bedeuten — nur, was vorkommt: die Arten
/// und Stationen, darunter die Phasen.
pw.Widget _zeitstrahlLegende(
  List<ProjektEintrag> eintraege,
  Map<String, ProjektStatus> phasen,
) {
  final arten = {for (final e in eintraege) EintragArt.aus(e.art)};
  final folge = [
    for (final p in ProjektStatus.values)
      if (phasen.values.contains(p)) p,
  ];
  pw.Widget eintrag(pw.Widget zeichen, String text) => pw.Row(
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      zeichen,
      pw.SizedBox(width: 3),
      _t(text, groesse: 7, farbe: _grau),
    ],
  );
  pw.Widget zeile(List<pw.Widget> kinder) => pw.Wrap(
    spacing: 10,
    runSpacing: 4,
    crossAxisAlignment: pw.WrapCrossAlignment.center,
    children: kinder,
  );
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 4, bottom: 6),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        zeile([
          for (final a in EintragArt.values)
            if (arten.contains(a)) eintrag(_symbol(a, groesse: 10), a.label),
          if (eintraege.any(istStation))
            eintrag(
              pw.Container(
                width: 10,
                height: 10,
                alignment: pw.Alignment.center,
                decoration: const pw.BoxDecoration(
                  color: _station,
                  shape: pw.BoxShape.circle,
                ),
                child: _t('1', groesse: 6, fett: true, farbe: PdfColors.white),
              ),
              'Station (Rezepturstand)',
            ),
        ]),
        if (folge.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          zeile([
            _t('Phase', groesse: 7, fett: true, farbe: _grau),
            for (final p in folge)
              eintrag(
                pw.Container(
                  width: 16,
                  height: 4,
                  color: _hell(_phasenFarbe(p), .25),
                ),
                _phasenName(p),
              ),
          ]),
        ],
      ],
    ),
  );
}

/// Der Zeitstrahl in Zeilen zu je [_Satz.jeZeile] Einträgen.
List<pw.Widget> _zeitstrahl(
  _Satz s,
  List<ProjektEintrag> eintraege,
  Map<String, ProjektStatus> phasen,
) {
  final n = eintraege.length;
  // Die Phase bei jedem Eintrag — ohne Angabe die davor.
  final phase = <ProjektStatus?>[];
  for (final e in eintraege) {
    phase.add(phasen[e.id] ?? phase.lastOrNull);
  }
  // Je Stand die Station: der erste Rezepturstand mit diesem Bezug.
  final station = <String, int>{};
  for (var i = 0; i < n; i++) {
    final e = eintraege[i];
    if (istStation(e)) station.putIfAbsent(e.versionId!, () => i);
  }
  final jeZeile = s.jeZeile;
  return [
    for (var von = 0; von < n; von += jeZeile)
      _zeitstrahlZeile(
        s,
        eintraege: eintraege,
        phase: phase,
        station: station,
        von: von,
        bis: math.min(von + jeZeile, n),
      ),
  ];
}

/// Eine Zeile des Zeitstrahls mit den Einträgen [von] bis vor [bis].
pw.Widget _zeitstrahlZeile(
  _Satz s, {
  required List<ProjektEintrag> eintraege,
  required List<ProjektStatus?> phase,
  required Map<String, int> station,
  required int von,
  required int bis,
}) {
  final n = eintraege.length;
  // Die volle Breite — quer oder verkleinert ist mehr Platz.
  final breite = s.rahmen.breite;
  final jeZeile = s.jeZeile;
  const hoehe = 2 * _zsHaelfte;
  const achse = _zsHaelfte;
  // Passt alles in eine Zeile, verteilt sich der Strahl über die Breite;
  // sonst hat jeder Eintrag denselben Platz, auch in der letzten Zeile.
  final abstand = breite / (n <= jeZeile ? n : jeZeile);
  double xVon(int i) => abstand * (i - von + .5);
  final letzte = bis == n;
  final ende = letzte ? xVon(bis - 1) + abstand / 2 : breite;
  final karte = math.min(2 * abstand - 12, 140.0);
  double stiel(int i) => _platz(i).lang ? _zsLang : _zsKurz;
  // Die Mitte eines Symbols, von oben gemessen.
  double symbolY(int i) => _platz(i).oben
      ? achse - stiel(i) - _zsSymbol / 2
      : achse + stiel(i) + _zsSymbol / 2;
  bool istStand(int i) =>
      istStation(eintraege[i]) && station[eintraege[i].versionId] == i;

  final kinder = <pw.Widget>[
    pw.CustomPaint(
      size: PdfPoint(breite, hoehe),
      painter: (c, size) {
        // Von oben gemessen — das PDF zählt von unten.
        double y(double vonOben) => size.y - vonOben;
        // Die Achse, grau, und darauf das Band der Phasen.
        c
          ..setFillColor(_linie)
          ..drawRRect(0, y(achse) - 1.5, ende, 3, 1.5, 1.5)
          ..fillPath();
        var start = von;
        while (start < bis) {
          final p = phase[start];
          var stop = start;
          while (stop + 1 < bis && phase[stop + 1] == p) {
            stop++;
          }
          if (p != null) {
            final links = start == von
                ? 0.0
                : (xVon(start - 1) + xVon(start)) / 2;
            final rechts = stop == bis - 1
                ? ende
                : (xVon(stop) + xVon(stop + 1)) / 2;
            c
              ..setFillColor(_hell(_phasenFarbe(p), .25))
              ..drawRect(links, y(achse) - 2.5, rechts - links, 5)
              ..fillPath();
          }
          start = stop + 1;
        }
        // Geht es in der nächsten Zeile weiter, zeigt ein Pfeil dorthin.
        if (!letzte) {
          c
            ..setFillColor(_hellgrau)
            ..moveTo(breite, y(achse))
            ..lineTo(breite - 6, y(achse) + 4)
            ..lineTo(breite - 6, y(achse) - 4)
            ..closePath()
            ..fillPath();
        }
        // Die Linien von Einträgen zu ihrer Station in dieser Zeile.
        c
          ..saveContext()
          ..setStrokeColor(_hell(_station, .45))
          ..setLineWidth(.9)
          ..setLineDashPattern([3, 2]);
        for (var i = von; i < bis; i++) {
          final ziel = station[eintraege[i].versionId];
          if (ziel == null || ziel == i || ziel < von || ziel >= bis) {
            continue;
          }
          c
            ..moveTo(xVon(i), y(symbolY(i)))
            ..lineTo(xVon(ziel), y(achse))
            ..strokePath();
        }
        c.restoreContext();
        // Stiele, Punkte auf der Achse und die Symbole.
        for (var i = von; i < bis; i++) {
          final art = EintragArt.aus(eintraege[i].art);
          final x = xVon(i);
          final oben = _platz(i).oben;
          c
            ..setStrokeColor(const PdfColor.fromInt(0xFFC2C8CF))
            ..setLineWidth(.9)
            ..setLineCap(PdfLineCap.butt)
            ..moveTo(x, y(achse))
            ..lineTo(x, y(oben ? achse - stiel(i) : achse + stiel(i)))
            ..strokePath();
          final (radius, farbe) = istStand(i)
              ? (6.5, _station)
              : art == EintragArt.meilenstein
              ? (3.6, _akzent)
              : (3.0, _hellgrau);
          c
            ..setFillColor(farbe)
            ..drawEllipse(x, y(achse), radius, radius)
            ..fillPath()
            ..setStrokeColor(PdfColors.white)
            ..setLineWidth(1.1)
            ..drawEllipse(x, y(achse), radius, radius)
            ..strokePath();
          _symbolMalen(c, art, x, y(symbolY(i)), _zsSymbol / 2);
        }
      },
    ),
  ];
  for (var i = von; i < bis; i++) {
    final e = eintraege[i];
    final x = xVon(i);
    final platz = _platz(i);
    final links = (x - karte / 2).clamp(0.0, breite - karte);
    final beschriftung = pw.SizedBox(
      width: karte,
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: [_zeitstrahlKarte(s, e, karte)],
      ),
    );
    final abstandZurAchse = stiel(i) + _zsSymbol + 3;
    kinder.add(
      platz.oben
          ? pw.Positioned(
              left: links,
              bottom: achse + abstandZurAchse,
              child: beschriftung,
            )
          : pw.Positioned(
              left: links,
              top: achse + abstandZurAchse,
              child: beschriftung,
            ),
    );
    if (istStand(i)) {
      kinder.add(
        pw.Positioned(
          left: x - 6.5,
          top: achse - 6.5,
          child: pw.SizedBox(
            width: 13,
            height: 13,
            child: pw.Center(
              child: _t(
                '${s.b.versionen[e.versionId]?.nummer ?? ''}',
                groesse: 6.8,
                fett: true,
                farbe: PdfColors.white,
              ),
            ),
          ),
        ),
      );
    }
  }
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 6),
    child: pw.Stack(children: kinder),
  );
}

/// Die Beschriftung eines Eintrags am Strahl: Titel, Datum (mit dem Stand,
/// zu dem er gehört) und — ist er offen — „offen" oder „überfällig".
/// Meilensteine stehen farbig da.
pw.Widget _zeitstrahlKarte(_Satz s, ProjektEintrag e, double breite) {
  final meilenstein = EintragArt.aus(e.art) == EintragArt.meilenstein;
  final offen = EintragStatus.aus(e.status) == EintragStatus.offen;
  final stand = istStation(e) ? null : s.b.versionen[e.versionId];
  final vorbei = eintragUeberfaellig(e, heute: s.jetzt);
  final schrift = meilenstein ? PdfColors.white : _schwarz;
  final grau = meilenstein ? _hell(_akzent, .7) : _grau;
  return pw.Container(
    constraints: pw.BoxConstraints(maxWidth: breite),
    padding: const pw.EdgeInsets.fromLTRB(5, 2.5, 5, 3),
    decoration: pw.BoxDecoration(
      color: meilenstein ? _akzent : PdfColors.white,
      border: meilenstein ? null : pw.Border.all(color: _linie, width: .6),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
    ),
    child: pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        _t(
          _gekuerzt(e.titel, 62),
          groesse: 7,
          fett: true,
          farbe: schrift,
          maxLines: 2,
          ausrichtung: pw.TextAlign.center,
        ),
        pw.SizedBox(height: .5),
        _t(
          [
            _datum(e.datum),
            if (stand != null) 'zu Stand ${stand.nummer}',
          ].join(' · '),
          groesse: 6.2,
          farbe: grau,
        ),
        if (offen)
          _t(
            vorbei ? 'überfällig' : 'offen',
            groesse: 6.2,
            fett: true,
            farbe: meilenstein ? schrift : (vorbei ? _fehler : _warn),
          ),
      ],
    ),
  );
}

/// Jeder Eintrag im Einzelnen — nach Monaten, mit Beschreibung,
/// Änderungen und Kommentaren.
List<pw.Widget> _verlaufImEinzelnen(_Satz s, List<ProjektEintrag> eintraege) {
  final b = s.b;
  final dateien = {for (final d in b.dateien) d.id: d};
  const einzug = 74.0;
  final widgets = <pw.Widget>[];
  String? monat;
  for (final e in eintraege) {
    final art = EintragArt.aus(e.art);
    final offen = EintragStatus.aus(e.status) == EintragStatus.offen;
    final vorbei = eintragUeberfaellig(e, heute: s.jetzt);
    final v = b.versionen[e.versionId];
    final datei = dateien[e.dateiId];
    final meta = [
      art.label,
      if (_oderNull(e.benutzer) case final von?) 'von $von',
      if (v != null && !istStation(e)) 'zu Stand ${v.nummer}',
      if (datei != null)
        art == EintragArt.datei ? datei.name : 'Datei: ${datei.name}',
      if (_oderNull(e.ziel) case final z?) 'fällig bis $z',
    ];
    final kopf = pw.Container(
      margin: const pw.EdgeInsets.only(top: 5),
      padding: const pw.EdgeInsets.only(top: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _linie, width: .4)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: .5),
            child: _symbol(art),
          ),
          pw.SizedBox(width: 6),
          pw.SizedBox(
            width: einzug - 17,
            child: _t(_datum(e.datum), groesse: 8, fett: true),
          ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _t(e.titel, groesse: 8.8, fett: true),
                _t(meta.join(' · '), groesse: 7.3, farbe: _grau),
              ],
            ),
          ),
          if (offen) ...[
            pw.SizedBox(width: 6),
            vorbei
                ? _marke('ÜBERFÄLLIG', _fehler)
                : _marke('OFFEN', _warn),
          ],
        ],
      ),
    );
    final beschreibung = _oderNull(e.beschreibung);
    final text = beschreibung == null
        ? null
        : pw.Padding(
            padding: const pw.EdgeInsets.only(top: 2),
            child: _fliess(beschreibung, groesse: 8.3, einzug: einzug),
          );
    // Eine kurze Beschreibung bleibt bei ihrem Eintrag, der Monat bei
    // seinem ersten Eintrag; eine lange darf über die Seite laufen.
    final kurz = beschreibung == null || beschreibung.length <= 600;
    final m = '${Format.monate[e.datum.month - 1]} ${e.datum.year}';
    widgets.add(
      _zusammen([
        if (m != monat)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 8, bottom: 1),
            child: _t(m, groesse: 8.5, fett: true, farbe: _akzent),
          ),
        kopf,
        if (kurz && text != null) text,
      ]),
    );
    monat = m;
    if (!kurz && text != null) widgets.add(text);
    final aenderungen = texteAus(e.aenderungen);
    if (aenderungen.isNotEmpty) {
      widgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 2),
          child: _fliess(
            'Änderungen: ${aenderungen.join(' · ')}',
            groesse: 7.6,
            farbe: _grau,
            einzug: einzug,
          ),
        ),
      );
    }
    for (final kom in Kommentar.listeAus(e.kommentare)) {
      widgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 2),
          child: _fliess(
            '${kom.name.isEmpty ? 'Kommentar' : kom.name} '
            '(${_datum(kom.datum)}): ${kom.text}',
            groesse: 7.6,
            farbe: _grau,
            einzug: einzug,
          ),
        ),
      );
    }
  }
  return widgets;
}

// ── 8 Dateien ──────────────────────────────────────────────────────────

String _dateiArt(EntwicklungsDatei d) {
  final mime = d.mimeTyp?.toLowerCase() ?? '';
  final name = d.name.toLowerCase();
  if (mime.startsWith('image/')) return 'Bild';
  if (mime == 'application/pdf' || name.endsWith('.pdf')) return 'PDF';
  if (name.endsWith('.msg') || name.endsWith('.eml')) return 'E-Mail';
  if (name.endsWith('.xlsx') || name.endsWith('.xls')) return 'Excel';
  if (name.endsWith('.docx') || name.endsWith('.doc')) return 'Word';
  return 'Datei';
}

String _groesse(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${Format.zahl(bytes / 1024 / 1024, nachkomma: 1)} MB';
}

List<pw.Widget> _kapitelDateien(_Satz s, _Kapitel k) => [
  ..._kapitelKopf(
    s,
    k,
    untertitel:
        'Die Dateien liegen verschlüsselt in der App — hier, was '
        'es gibt.',
  ),
  _tabelle(
    kopf: const ['Datei', 'Art', 'Größe', 'Abgelegt'],
    rechts: const {2},
    breiten: const {
      0: pw.FlexColumnWidth(),
      1: pw.FixedColumnWidth(54),
      2: pw.FixedColumnWidth(50),
      3: pw.FixedColumnWidth(62),
    },
    zeilen: [
      for (final d in s.b.dateien)
        [
          _zelle(d.id == s.p.bildDateiId ? '${d.name} (Produktfoto)' : d.name),
          _zelle(_dateiArt(d), farbe: _grau),
          _zelle(_groesse(d.groesse)),
          _zelle(_datum(d.createdAt)),
        ],
    ],
  ),
];
