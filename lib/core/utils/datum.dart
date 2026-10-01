/// Rechnen mit Kalendertagen — immer über die Tageszahl, nie mit
/// `Duration(days: …)`.
///
/// Am Wochenende der Zeitumstellung hat ein Tag 23 oder 25 Stunden.
/// `DateTime(2026, 10, 25).add(Duration(days: 1))` ergibt deshalb
/// 25.10. 23:00 statt 26.10. 00:00 — auf den Tag gekürzt bleibt man auf
/// dem Sonntag stehen. So lief der Planungsvorschlag in eine Endlosschleife,
/// und das Board zeigte nach „nächste Woche" dieselbe Woche noch einmal.
///
/// `DateTime(jahr, monat, tag + n)` rechnet dagegen im Kalender und rollt
/// Monats- und Jahresgrenzen selbst weiter.
///
/// Bewusst ohne Flutter-Abhängigkeit, damit auch Dienste und Isolates sie
/// benutzen können.
library;

/// Der Kalendertag von [d], 00:00 Uhr.
DateTime tagOhneZeit(DateTime d) => DateTime(d.year, d.month, d.day);

/// Der Kalendertag [tage] Tage nach [d] (negativ: davor), 00:00 Uhr.
DateTime tagPlus(DateTime d, int tage) =>
    DateTime(d.year, d.month, d.day + tage);
