// Zahlen und Uhrzeiten, wie man sie an der Anlage eintippt — und was
// sich daraus ableitet. Gerechnet und gespeichert wird am Ende im Planer
// (ProduktionErfassenService); die App zeigt mit denselben Formeln vorab,
// was dabei herauskommt.

/// Liest eine Zahl: „12,5" wie „12.5" — wie die Grenzen-Prüfung im
/// Planer. null, wenn es keine ist.
double? zahlAus(String? text) {
  final t = text?.trim().replaceAll(',', '.');
  if (t == null || t.isEmpty) return null;
  return double.tryParse(t);
}

/// „1.250", „12,5" — ganze Zahlen ohne Nachkommastellen, sonst mit
/// [nachkomma] Stellen.
String zahlText(double wert, {int nachkomma = 1}) {
  final stellen = wert == wert.roundToDouble() ? 0 : nachkomma;
  final roh = wert.toStringAsFixed(stellen);
  final negativ = roh.startsWith('-');
  final teile = (negativ ? roh.substring(1) : roh).split('.');
  final ganz = teile.first;
  final text = StringBuffer();
  for (var i = 0; i < ganz.length; i++) {
    if (i > 0 && (ganz.length - i) % 3 == 0) text.write('.');
    text.write(ganz[i]);
  }
  if (teile.length > 1) text.write(',${teile[1]}');
  final ergebnis = text.toString();
  // Kein „-0,0".
  return negativ && RegExp('[1-9]').hasMatch(ergebnis)
      ? '-$ergebnis'
      : ergebnis;
}

/// Eine Zahl zum Weitertippen in einem Eingabefeld: „1250", „12,5" —
/// ohne Tausenderpunkte, die [zahlAus] als Komma läse.
String eingabeText(double wert, {int nachkomma = 2}) {
  var t = wert.toStringAsFixed(nachkomma);
  if (t.contains('.')) {
    t = t.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return t.replaceAll('.', ',');
}

/// Eine Uhrzeit als „HH:MM": „6", „630", „0630", „6:30", „6.30" werden
/// zu „06:30". null, wenn es keine Uhrzeit ist.
String? zeitAus(String? text) {
  final t = text?.trim();
  if (t == null || t.isEmpty) return null;
  int? h;
  int? m;
  final teile = t.split(RegExp('[:.,h ]'));
  if (teile.length == 2 && teile[1].isNotEmpty) {
    h = int.tryParse(teile[0]);
    m = int.tryParse(teile[1]);
  } else if (RegExp(r'^\d{1,2}$').hasMatch(t)) {
    h = int.parse(t);
    m = 0;
  } else if (RegExp(r'^\d{3,4}$').hasMatch(t)) {
    h = int.parse(t.substring(0, t.length - 2));
    m = int.parse(t.substring(t.length - 2));
  }
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
    return null;
  }
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// Die Uhrzeit von [d] als „HH:MM".
String uhrzeit(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:'
    '${d.minute.toString().padLeft(2, '0')}';

/// Minuten von [start] bis [ende] („HH:MM") — über Mitternacht richtig.
double? dauerMinuten(String? start, String? ende) {
  int? minuten(String? t) {
    final z = zeitAus(t);
    if (z == null) return null;
    return int.parse(z.substring(0, 2)) * 60 + int.parse(z.substring(3));
  }

  final s = minuten(start);
  final e = minuten(ende);
  if (s == null || e == null) return null;
  var diff = e - s;
  if (diff < 0) diff += 24 * 60;
  return diff.toDouble();
}

/// Verlust als Anteil: 1 − Fertig / Roh.
double? verlustAnteil(double? rohKg, double? fertigKg) {
  if (rohKg == null || rohKg <= 0 || fertigKg == null) return null;
  return 1 - fertigKg / rohKg;
}

/// Kilo je Stunde.
double? kgProStunde(double? kg, double? minuten) {
  if (kg == null || minuten == null || minuten <= 0) return null;
  return kg / (minuten / 60);
}
