/// Ein unkomprimiertes PDF lesen, wie es die Berichte für Tests setzen:
/// die Seiten der Reihe nach, ihr Text und wo Kapitel beginnen.
library;

/// Der Inhalt jeder Seite, der Reihe nach — [roh] latin1-gelesen.
List<String> pdfSeiten(String roh) {
  String objekt(String nr) {
    final anfang = RegExp('(^|\\n)$nr 0 obj\\b').firstMatch(roh)!.end;
    return roh.substring(anfang, roh.indexOf('endobj', anfang));
  }

  final kinder =
      RegExp(r'/Type/Pages/Kids\[([^\]]*)\]').firstMatch(roh)!.group(1)!;
  return [
    for (final k in RegExp(r'(\d+) 0 R').allMatches(kinder))
      objekt(
        RegExp(r'/Contents (\d+) 0 R')
            .firstMatch(objekt(k.group(1)!))!
            .group(1)!,
      ),
  ];
}

/// Der Text einer Seite: Das PDF setzt Wort für Wort, hier stehen sie mit
/// Leerzeichen dazwischen hintereinander — eine Zeile liest sich so wie
/// gedruckt. Mit [groesse] und [schrift] („/F6", siehe [fetteSchrift])
/// nur die Wörter in dieser Größe und Schrift — etwa die Überschriften.
String seitenText(String seite, {double? groesse, String? schrift}) => [
      for (final m in RegExp(
        r'BT (/F\d+) ([\d.]+) Tf [^\[]*\[\(((?:\\.|[^\\)])*)\)\]TJ',
      ).allMatches(seite))
        if ((groesse == null || double.parse(m[2]!) == groesse) &&
            (schrift == null || m[1] == schrift))
          m[3]!.replaceAllMapped(RegExp(r'\\(.)'), (e) => e[1]!),
    ].join(' ');

/// Wie die fette Schrift im PDF heißt — „/F6".
String fetteSchrift(String roh) {
  final nr = RegExp(
    r'(\d+) 0 obj\s*<<[^>]*/BaseFont/Helvetica-Bold\b',
  ).firstMatch(roh)![1];
  return '/F$nr';
}

/// Wo die Kapitel beginnen: je Kapitel die Seite (ab 1) und die Höhe auf
/// ihr — aus den Sprungzielen der Lesezeichen.
List<({int seite, double hoehe})> kapitelAnfaenge(String roh) {
  final kinder = [
    for (final k in RegExp(r'(\d+) 0 R').allMatches(
      RegExp(r'/Type/Pages/Kids\[([^\]]*)\]').firstMatch(roh)!.group(1)!,
    ))
      k.group(1)!,
  ];
  return [
    for (final m in RegExp(
      r'\(kapitel-\d+\)<</D\[(\d+) 0 R/XYZ [\d.]+ ([\d.]+)',
    ).allMatches(roh))
      (
        seite: kinder.indexOf(m.group(1)!) + 1,
        hoehe: double.parse(m.group(2)!),
      ),
  ];
}
