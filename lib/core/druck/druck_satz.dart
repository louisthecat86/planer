/// Der Satz eines Ausdrucks: Er legt die Blätter eines Dokuments auf das
/// Papier, wie es ein [DruckLayout] verlangt — vergrößert, verkleinert,
/// quer, mit schmalem Rand, in Graustufen.
///
/// So funktioniert es: Jedes Blatt ist für A4 entworfen. Soll es auf
/// einen Anteil s verkleinert werden, setzt der Satz es auf eine größere,
/// gedachte Seite (A4 geteilt durch s) — es passt also mehr darauf, und
/// der Text bricht über die volle Breite um. Beim Zeichnen schrumpft jede
/// Seite dann um s (und für A3 oder A5 um deren Verhältnis zu A4) auf das
/// echte Papier. Weil das am Anfang jeder Seite geschieht, stimmen auch
/// Sprungziele und Links im PDF.
///
/// „Alles auf eine Seite" sucht das größte s, bei dem jedes Blatt auf
/// eine Seite passt.
///
/// Bewusst ohne Flutter-Abhängigkeit — der Satz lässt sich so ohne
/// Oberfläche prüfen.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'druck_layout.dart';

/// Schmaler als so (in Punkt, rund 5 mm) wird kein Rand — weniger druckt
/// mancher Drucker nicht mehr.
const double kDruckMindestrand = 14;

/// Kleiner wird nicht verkleinert: Bei 30 % ist 8-Punkt-Schrift kaum
/// noch 2,5 Punkt hoch. Passt ein Blatt auch so nicht, sagt das
/// [DruckErgebnis.passtNicht].
const double kDruckKleinsterMassstab = .3;

/// Was ein Blatt zum Setzen erfährt.
class DruckRahmen {
  DruckRahmen._({
    required this.breite,
    required this.hoehe,
    required this.massstab,
    required this.quer,
    required this.anpassung,
    required this.bekannt,
  });

  /// Breite für den Inhalt, ohne die Ränder — auf der gedachten Seite:
  /// verkleinert wird mehr Platz. Was sich nach der Breite richtet (ein
  /// Zeitstrahl, ein Raster), nimmt diese statt einer festen Zahl.
  final double breite;

  /// Höhe für den Inhalt, ohne die Ränder (Kopf- und Fußzeile gehen noch
  /// davon ab).
  final double hoehe;

  /// Der Anteil, auf den verkleinert wird — 1: Originalgröße.
  final double massstab;

  /// Querformat.
  final bool quer;

  final DruckAnpassung anpassung;

  /// Seitenumbrüche von Hand (pw.NewPage) sind erlaubt. Soll ein Blatt
  /// auf eine oder zwei Seiten passen, nicht: Ein erzwungener Umbruch
  /// ließe es nie passen, und das PDF bricht ohnehin selbst um.
  bool get umbrueche => anpassung.hoechstens == null;

  /// Die Seiten der Sprungmarken aus dem vorigen Durchgang — für ein
  /// Inhaltsverzeichnis. Leer im ersten.
  final Map<String, int> bekannt;

  /// Hier trägt das Blatt beim Zeichnen die Seiten seiner Sprungmarken
  /// ein (siehe [merke]). Findet der Satz welche, setzt er das Dokument
  /// ein zweites Mal — dann mit diesen Seiten in [bekannt].
  final Map<String, int> gefunden = {};

  /// Merkt sich die Seite einer Sprungmarke — beim Zeichnen aufrufen,
  /// wenn die endgültige Seite feststeht.
  void merke(String name, int seite) => gefunden.putIfAbsent(name, () => seite);

  final List<PdfPage> _seiten = [];

  /// Wie viele Seiten das Dokument vor diesem Blatt hat.
  int _davor = 0;

  /// Die Seite im Blatt, auf der [ctx] steht — ab 1. Das gilt schon beim
  /// Setzen, nicht erst beim Zeichnen: Kopf- und Fußzeilen, die sich danach
  /// richten (etwa ohne Kopf auf Seite 1), haben so beim Setzen dieselbe
  /// Höhe wie beim Zeichnen. Sonst rutschte der Inhalt in die Fußzeile.
  int seiteImBlatt(pw.Context ctx) => math.max(1, ctx.pageNumber - _davor);

  /// Wie viele Seiten das Blatt hat.
  int get seitenImBlatt => math.max(1, _seiten.length);

  /// „Seite 2 von 3" — gezählt im Blatt: Bei mehreren Blättern (je
  /// Abteilung eins) fängt jedes bei 1 an.
  String seitenText(pw.Context ctx) =>
      'Seite ${seiteImBlatt(ctx)} von $seitenImBlatt';
}

/// Was ein Blatt liefert: den Inhalt, dazu Kopf- und Fußzeile, die auf
/// jeder Seite stehen.
class DruckSeiten {
  const DruckSeiten({
    required this.inhalt,
    this.kopf,
    this.fuss,
    this.maxSeiten = 300,
  });

  final pw.BuildListCallback inhalt;
  final pw.BuildCallback? kopf;
  final pw.BuildCallback? fuss;

  /// Mehr Seiten legt das PDF nicht an — schützt vor einem Inhalt, der
  /// endlos umbricht.
  final int maxSeiten;
}

/// Ein Blatt: ein Teil des Dokuments, der auf einer neuen Seite beginnt —
/// der ganze Bericht, ein Datenblatt, der Plan einer Abteilung. „Alles auf
/// eine Seite" gilt je Blatt.
class DruckBlatt {
  const DruckBlatt({
    required this.bauen,
    this.rand = const pw.EdgeInsets.all(28),
    this.quer = false,
  });

  /// Setzt das Blatt in [DruckRahmen] — wird für jeden Versuch neu
  /// aufgerufen, darf also nichts von einem Aufruf zum nächsten behalten.
  final DruckSeiten Function(DruckRahmen rahmen) bauen;

  /// Die Ränder auf A4 in Originalgröße.
  final pw.EdgeInsets rand;

  /// Im Querformat entworfen — gilt bei [DruckAusrichtung.automatisch].
  final bool quer;
}

/// Ein Dokument aus einem oder mehreren Blättern.
class DruckDokument {
  const DruckDokument({
    required this.blaetter,
    this.titel,
    this.dateiname = 'Druck',
    this.lesezeichen = false,
    this.theme,
  });

  final List<DruckBlatt> blaetter;

  /// Titel in den Eigenschaften des PDF.
  final String? titel;

  /// Name zum Speichern und für die Druckerwarteschlange — ohne Endung,
  /// am besten aus druckDateiname (druck_optionen.dart).
  final String dateiname;

  /// Der PDF-Betrachter zeigt beim Öffnen die Lesezeichen.
  final bool lesezeichen;

  /// Schriften — ohne: Helvetica.
  final pw.ThemeData? theme;
}

/// Ein gesetztes Dokument.
class DruckErgebnis {
  const DruckErgebnis({
    required this.bytes,
    required this.layout,
    required this.blattSeiten,
    required this.massstaebe,
    required this.formate,
    required this.passtNicht,
  });

  final Uint8List bytes;
  final DruckLayout layout;

  /// Seiten je Blatt.
  final List<int> blattSeiten;

  /// Der Anteil je Blatt, auf den verkleinert wurde — 1: Originalgröße.
  final List<double> massstaebe;

  /// Das Papier je Blatt, hoch oder quer.
  final List<PdfPageFormat> formate;

  /// Ein Blatt passte auch beim kleinsten Maßstab nicht auf so wenige
  /// Seiten, wie [DruckLayout.anpassung] verlangt.
  final bool passtNicht;

  int get seiten => blattSeiten.fold(0, (a, b) => a + b);

  int get blaetter => blattSeiten.length;

  /// Das Papier der ersten Seite — für den Druckdialog.
  PdfPageFormat get format => formate.first;

  bool _quer(PdfPageFormat f) => f.width > f.height;

  /// „3 Seiten · A4 quer · 100 %".
  String get beschreibung {
    final teile = <String>[
      if (blaetter > 1) '$blaetter Blätter',
      seiten == 1 ? '1 Seite' : '$seiten Seiten',
    ];
    final quer = formate.where(_quer).length;
    final lage = quer == 0
        ? 'hoch'
        : quer == formate.length
            ? 'quer'
            : 'hoch und quer';
    teile.add('${layout.papier.label} $lage');
    final kleinster = massstaebe.reduce(math.min);
    final groesster = massstaebe.reduce(math.max);
    final von = (kleinster * 100).round();
    final bis = (groesster * 100).round();
    teile.add(von == bis ? '$von %' : '$von–$bis %');
    if (layout.graustufen) teile.add('Graustufen');
    return teile.join(' · ');
  }
}

/// Setzt [dokument] nach [layout]. [komprimiert]: false lässt den Text im
/// PDF lesbar — für Tests.
Future<DruckErgebnis> druckSetzen(
  DruckDokument dokument,
  DruckLayout layout, {
  bool komprimiert = true,
}) async {
  if (dokument.blaetter.isEmpty) {
    throw ArgumentError('Nichts zu drucken.');
  }
  final theme = dokument.theme ?? _helvetica();
  final plaene = [for (final b in dokument.blaetter) _Plan(b, layout)];

  final massstaebe = <double>[];
  var passtNicht = false;
  for (final p in plaene) {
    final (s, passt) = _massstab(p, layout, theme);
    massstaebe.add(s);
    if (!passt) passtNicht = true;
  }

  // Meist ein Durchgang. Trägt ein Blatt beim Zeichnen Sprungmarken ein
  // (ein Inhaltsverzeichnis), ein zweiter mit deren Seiten.
  var bekannt = [for (final _ in plaene) const <String, int>{}];
  for (var durchgang = 1;; durchgang++) {
    final doc = pw.Document(
      title: dokument.titel,
      creator: 'Produktions Planer',
      pageMode:
          dokument.lesezeichen ? PdfPageMode.outlines : PdfPageMode.none,
      compress: komprimiert,
      theme: theme,
    );
    final rahmen = <DruckRahmen>[];
    final blattSeiten = <int>[];
    for (final (i, p) in plaene.indexed) {
      final r = p.rahmen(massstaebe[i], bekannt[i]);
      rahmen.add(r);
      blattSeiten.add(_anlegen(doc, p, r, graustufen: layout.graustufen));
    }
    final bytes = await doc.save();
    final gefunden = [for (final r in rahmen) Map.of(r.gefunden)];
    final nochmal = durchgang == 1 &&
        gefunden.any((g) => g.isNotEmpty) &&
        !_gleich(gefunden, bekannt);
    if (nochmal) {
      bekannt = gefunden;
      continue;
    }
    return DruckErgebnis(
      bytes: bytes,
      layout: layout,
      blattSeiten: blattSeiten,
      massstaebe: List.unmodifiable(massstaebe),
      formate: [for (final p in plaene) p.ziel],
      passtNicht: passtNicht,
    );
  }
}

pw.ThemeData _helvetica() => pw.ThemeData.withFont(
      base: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
      italic: pw.Font.helveticaOblique(),
      boldItalic: pw.Font.helveticaBoldOblique(),
    );

bool _gleich(List<Map<String, int>> a, List<Map<String, int>> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].length != b[i].length) return false;
    for (final e in a[i].entries) {
      if (b[i][e.key] != e.value) return false;
    }
  }
  return true;
}

/// Wie ein Blatt aufs Papier kommt.
class _Plan {
  factory _Plan(DruckBlatt blatt, DruckLayout layout) {
    final quer = switch (layout.ausrichtung) {
      DruckAusrichtung.automatisch => blatt.quer,
      DruckAusrichtung.hoch => false,
      DruckAusrichtung.quer => true,
    };
    final basis = quer ? PdfPageFormat.a4.landscape : PdfPageFormat.a4.portrait;
    final ziel =
        quer ? layout.papier.format.landscape : layout.papier.format.portrait;
    // A3 und A5 haben das Seitenverhältnis von A4 — bis auf Rundung.
    final faktor =
        math.min(ziel.width / basis.width, ziel.height / basis.height);
    // Der Rand auf dem Papier ist der entworfene mal [faktor].
    final mindest = kDruckMindestrand / faktor;
    double rand(double r) => math.max(r * layout.rand.faktor, mindest);
    return _Plan._(
      blatt,
      layout,
      quer: quer,
      basis: basis,
      ziel: ziel,
      faktor: faktor,
      rand: pw.EdgeInsets.fromLTRB(
        rand(blatt.rand.left),
        rand(blatt.rand.top),
        rand(blatt.rand.right),
        rand(blatt.rand.bottom),
      ),
    );
  }

  _Plan._(
    this.blatt,
    this.layout, {
    required this.quer,
    required this.basis,
    required this.ziel,
    required this.faktor,
    required this.rand,
  });

  final DruckBlatt blatt;
  final DruckLayout layout;
  final bool quer;

  /// A4 hoch oder quer — wofür das Blatt entworfen ist.
  final PdfPageFormat basis;

  /// Das echte Papier.
  final PdfPageFormat ziel;

  /// [ziel] im Verhältnis zu [basis] — 1 für A4.
  final double faktor;

  /// Die Ränder auf A4.
  final pw.EdgeInsets rand;

  DruckRahmen rahmen(double s, Map<String, int> bekannt) => DruckRahmen._(
        breite: (basis.width - rand.horizontal) / s,
        hoehe: (basis.height - rand.vertical) / s,
        massstab: s,
        quer: quer,
        anpassung: layout.anpassung,
        bekannt: bekannt,
      );

  /// Das Blatt als Seiten auf der gedachten Seite (A4 geteilt durch s).
  pw.MultiPage seiten(DruckRahmen r, {required bool graustufen}) {
    final s = r.massstab;
    final gedacht = PdfPageFormat(basis.width / s, basis.height / s);
    final inhalt = blatt.bauen(r);
    return pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: gedacht,
        margin: pw.EdgeInsets.fromLTRB(
          rand.left / s,
          rand.top / s,
          rand.right / s,
          rand.bottom / s,
        ),
        buildBackground: (_) => _Massstab(s * faktor, ziel),
        buildForeground: graustufen ? (_) => _Graustufen(gedacht) : null,
      ),
      header: inhalt.kopf,
      footer: inhalt.fuss,
      maxPages: inhalt.maxSeiten,
      build: (ctx) {
        final liste = inhalt.inhalt(ctx);
        // Ohne Inhalt legte das PDF keine Seite an.
        return liste.isEmpty ? [pw.SizedBox()] : liste;
      },
    );
  }
}

/// Legt das Blatt in [doc] an und gibt [r] seine Seiten. Liefert, wie
/// viele es sind.
int _anlegen(
  pw.Document doc,
  _Plan p,
  DruckRahmen r, {
  required bool graustufen,
}) {
  final liste = doc.document.pdfPageList.pages;
  final vorher = liste.length;
  r._davor = vorher;
  doc.addPage(p.seiten(r, graustufen: graustufen));
  r._seiten.addAll(liste.sublist(vorher));
  return liste.length - vorher;
}

/// Mehr Seiten, als es geben darf — der Inhalt passt so nicht.
const int _zuViele = 1 << 30;

/// Wie viele Seiten das Blatt beim Anteil [s] braucht. Gesetzt wird nur,
/// gezeichnet nicht — das geht schnell.
int _zaehle(_Plan p, double s, pw.ThemeData theme) {
  final doc = pw.Document(theme: theme, compress: false);
  try {
    return _anlegen(doc, p, p.rahmen(s, const {}), graustufen: false);
  } catch (_) {
    // Zu viele Seiten oder ein Teil, der auf keine Seite passt: Bei
    // diesem Anteil geht es nicht. Ein echter Fehler zeigt sich beim
    // endgültigen Satz.
    return _zuViele;
  }
}

/// Der Anteil für ein Blatt — und ob es damit so wenige Seiten hat, wie
/// [layout] verlangt.
(double, bool) _massstab(_Plan p, DruckLayout layout, pw.ThemeData theme) {
  final hoechstens = layout.anpassung.hoechstens;
  if (hoechstens == null) {
    final s = layout.anpassung == DruckAnpassung.verkleinern
        ? layout.prozent / 100
        : 1.0;
    return (s, true);
  }
  if (_zaehle(p, 1, theme) <= hoechstens) return (1, true);
  var passt = kDruckKleinsterMassstab;
  if (_zaehle(p, passt, theme) > hoechstens) return (passt, false);
  // Halbieren: Mit kleinerem Anteil werden es nie mehr Seiten.
  var zuGross = 1.0;
  for (var i = 0; i < 8; i++) {
    final mitte = (passt + zuGross) / 2;
    if (_zaehle(p, mitte, theme) <= hoechstens) {
      passt = mitte;
    } else {
      zuGross = mitte;
    }
  }
  return (passt, true);
}

/// Zeichnet nichts, sondern stellt am Anfang jeder Seite den Maßstab ein:
/// Alles, was die Seite danach zeichnet, wird um [faktor] kleiner oder
/// größer — Kopf, Inhalt und Fuß, auch die Lage von Links und Sprungzielen.
/// Und die Seite bekommt das Format des echten Papiers.
class _Massstab extends pw.Widget {
  _Massstab(this.faktor, this.papier);

  final double faktor;
  final PdfPageFormat papier;

  @override
  void layout(
    pw.Context context,
    pw.BoxConstraints constraints, {
    bool parentUsesSize = false,
  }) {
    box = PdfRect.zero;
  }

  @override
  void paint(pw.Context context) {
    super.paint(context);
    // Der Hintergrund ist das Erste auf der Seite — und bewusst ohne
    // saveContext: Der Maßstab soll für den Rest der Seite gelten.
    if (faktor != 1) {
      final skala = context.canvas.getTransform()
        ..setIdentity()
        ..scaleByDouble(faktor, faktor, 1, 1);
      context.canvas.setTransform(skala);
    }
    context.page.pageFormat = papier;
  }
}

/// Färbt die Seite grau: Eine Fläche im Mischmodus „Sättigung" nimmt
/// allem darunter die Farbe und lässt die Helligkeit — auch Bildern. Weiß,
/// weil sie dort, wo nichts darunter liegt, selbst zu sehen ist — und
/// Weiß hat wie jedes Grau keine Sättigung.
class _Graustufen extends pw.Widget {
  _Graustufen(this.seite);

  /// Die gedachte Seite — der Maßstab gilt schon.
  final PdfPageFormat seite;

  @override
  void layout(
    pw.Context context,
    pw.BoxConstraints constraints, {
    bool parentUsesSize = false,
  }) {
    box = PdfRect.zero;
  }

  @override
  void paint(pw.Context context) {
    super.paint(context);
    context.canvas
      ..saveContext()
      ..setGraphicState(
        const PdfGraphicState(blendMode: PdfBlendMode.saturation),
      )
      ..setFillColor(PdfColors.white)
      ..drawRect(0, 0, seite.width, seite.height)
      ..fillPath()
      ..restoreContext();
  }
}
