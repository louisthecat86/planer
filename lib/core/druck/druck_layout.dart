/// Wie gedruckt wird — Papier, Ausrichtung, Größe, Ränder und Farbe. Gilt
/// für jedes Dokument gleich; was gedruckt wird, bestimmt das Dokument
/// selbst (siehe druck_optionen.dart).
///
/// Bewusst ohne Flutter-Abhängigkeit: Der Satz (druck_satz.dart) und
/// seine Tests laufen ohne Oberfläche.
library;

import 'package:pdf/pdf.dart';

/// Das Papier. Jedes Dokument ist für A4 entworfen; auf A3 wird das ganze
/// Blatt vergrößert, auf A5 verkleinert — wie am Kopierer. Die Formate
/// haben dasselbe Seitenverhältnis, es passt also immer genau.
enum DruckPapier {
  a4('A4', PdfPageFormat.a4),
  a3('A3', PdfPageFormat.a3),
  a5('A5', PdfPageFormat.a5);

  const DruckPapier(this.label, this.format);

  final String label;

  /// Das Format im Hochformat.
  final PdfPageFormat format;
}

/// Hoch- oder Querformat.
enum DruckAusrichtung {
  /// Wie das Dokument es vorsieht — die Woche quer, der Tag hoch.
  automatisch('Automatisch'),
  hoch('Hochformat'),
  quer('Querformat');

  const DruckAusrichtung(this.label);

  final String label;
}

/// Wie groß gedruckt wird.
enum DruckAnpassung {
  /// So groß, wie das Dokument entworfen ist.
  original('Originalgröße'),

  /// Auf einen festen Anteil ([DruckLayout.prozent]) — es passt mehr auf
  /// eine Seite.
  verkleinern('Verkleinern'),

  /// So weit verkleinert, dass jedes Blatt auf eine Seite passt.
  eineSeite('Alles auf eine Seite'),

  /// So weit verkleinert, dass jedes Blatt auf höchstens zwei Seiten passt.
  zweiSeiten('Auf höchstens zwei Seiten');

  const DruckAnpassung(this.label);

  final String label;

  /// Höchstens so viele Seiten je Blatt — null: so viele, wie es braucht.
  int? get hoechstens => switch (this) {
        DruckAnpassung.eineSeite => 1,
        DruckAnpassung.zweiSeiten => 2,
        DruckAnpassung.original || DruckAnpassung.verkleinern => null,
      };
}

/// Die Ränder um den Inhalt.
enum DruckRand {
  normal('Normal', 1),

  /// Halb so breit — mehr Platz für den Inhalt. Nie schmaler, als ein
  /// Drucker sicher druckt (siehe kDruckMindestrand).
  schmal('Schmal', .5);

  const DruckRand(this.label, this.faktor);

  final String label;

  /// Anteil am Rand, den das Dokument vorsieht.
  final double faktor;
}

/// Die Stufen für „Verkleinern".
const List<int> kDruckProzente = [90, 80, 70, 60, 50];

/// Einstellungen für einen Ausdruck.
class DruckLayout {
  const DruckLayout({
    this.papier = DruckPapier.a4,
    this.ausrichtung = DruckAusrichtung.automatisch,
    this.anpassung = DruckAnpassung.original,
    this.prozent = 80,
    this.rand = DruckRand.normal,
    this.graustufen = false,
  });

  final DruckPapier papier;
  final DruckAusrichtung ausrichtung;
  final DruckAnpassung anpassung;

  /// Größe in Prozent bei [DruckAnpassung.verkleinern] — eine der
  /// [kDruckProzente].
  final int prozent;

  final DruckRand rand;

  /// Alles in Grautönen — auch die Vorschau zeigt es so.
  final bool graustufen;

  DruckLayout copyWith({
    DruckPapier? papier,
    DruckAusrichtung? ausrichtung,
    DruckAnpassung? anpassung,
    int? prozent,
    DruckRand? rand,
    bool? graustufen,
  }) =>
      DruckLayout(
        papier: papier ?? this.papier,
        ausrichtung: ausrichtung ?? this.ausrichtung,
        anpassung: anpassung ?? this.anpassung,
        prozent: prozent ?? this.prozent,
        rand: rand ?? this.rand,
        graustufen: graustufen ?? this.graustufen,
      );

  Map<String, Object> toJson() => {
        'papier': papier.name,
        'ausrichtung': ausrichtung.name,
        'anpassung': anpassung.name,
        'prozent': prozent,
        'rand': rand.name,
        'graustufen': graustufen,
      };

  /// Liest gemerkte Einstellungen. Was fehlt oder nicht passt — etwa aus
  /// einer älteren Version —, kommt aus [standard].
  static DruckLayout fromJson(
    Object? json, {
    DruckLayout standard = const DruckLayout(),
  }) {
    if (json is! Map) return standard;
    T wahl<T extends Enum>(List<T> werte, Object? name, T sonst) {
      for (final w in werte) {
        if (w.name == name) return w;
      }
      return sonst;
    }

    final prozent = json['prozent'];
    final graustufen = json['graustufen'];
    return DruckLayout(
      papier: wahl(DruckPapier.values, json['papier'], standard.papier),
      ausrichtung: wahl(
        DruckAusrichtung.values,
        json['ausrichtung'],
        standard.ausrichtung,
      ),
      anpassung: wahl(
        DruckAnpassung.values,
        json['anpassung'],
        standard.anpassung,
      ),
      prozent: prozent is int && kDruckProzente.contains(prozent)
          ? prozent
          : standard.prozent,
      rand: wahl(DruckRand.values, json['rand'], standard.rand),
      graustufen: graustufen is bool ? graustufen : standard.graustufen,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DruckLayout &&
      other.papier == papier &&
      other.ausrichtung == ausrichtung &&
      other.anpassung == anpassung &&
      other.prozent == prozent &&
      other.rand == rand &&
      other.graustufen == graustufen;

  @override
  int get hashCode =>
      Object.hash(papier, ausrichtung, anpassung, prozent, rand, graustufen);

  @override
  String toString() => 'DruckLayout(${toJson()})';
}
