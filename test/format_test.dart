import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/utils/format.dart';

/// Tests für die gemeinsame Formatierung von Zahlen und Daten.
void main() {
  group('Zahlen', () {
    test('Tausenderpunkt und Komma', () {
      expect(Format.zahl(17195.7, nachkomma: 1), '17.195,7');
      expect(Format.zahl(1234567), '1.234.567');
      expect(Format.zahl(999), '999');
      expect(Format.zahl(1000), '1.000');
      expect(Format.zahl(0.25, nachkomma: 2), '0,25');
    });

    test('kein „-0" nach dem Runden', () {
      expect(Format.zahl(-0.04, nachkomma: 1), '0,0');
      expect(Format.zahl(-12.34, nachkomma: 1), '-12,3');
      expect(Format.zahl(-2500), '-2.500');
    });

    test('Mengen: ab 100 kg ganz, darunter eine Stelle, wenn es eine gibt',
        () {
      expect(Format.menge(2156.4), '2.156');
      expect(Format.menge(68.34), '68,3');
      expect(Format.menge(4), '4');
      expect(Format.menge(99.96), '100');
      expect(Format.kg(12500), '12.500 kg');
      expect(Format.kg(94.2), '94,2 kg');
    });

    test('Prozent aus einem Anteil', () {
      expect(Format.prozent(0.897), '89,7 %');
      expect(Format.prozent(0.1), '10,0 %');
      expect(Format.prozent(0.7, nachkomma: 0), '70 %');
    });

    test('Ungültige Werte werden zum Strich', () {
      expect(Format.zahl(double.nan), '—');
      expect(Format.menge(double.infinity), '—');
    });
  });

  group('Daten', () {
    final donnerstag = DateTime(2026, 10, 8, 7, 4);

    test('kurz und lang', () {
      expect(Format.datum(donnerstag), '08.10.2026');
      expect(Format.datumKurz(donnerstag), '08.10.');
      expect(Format.tagKurz(donnerstag), 'Do 08.10.');
      expect(Format.datumLang(donnerstag), 'Donnerstag, 8. Oktober 2026');
      expect(Format.uhrzeit(donnerstag), '07:04');
    });
  });
}
