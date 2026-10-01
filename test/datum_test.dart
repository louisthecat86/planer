import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/utils/datum.dart';

/// Tests für das Rechnen mit Kalendertagen.
///
/// Am Wochenende der Zeitumstellung hat ein Tag 23 oder 25 Stunden. Wer
/// dort mit `Duration(days: 1)` rechnet, landet auf 23:00 des Vortags oder
/// 01:00 — auf den Tag gekürzt bleibt man stehen oder springt. Richtig
/// aussagekräftig sind die Tests deshalb auf einem Rechner mit deutscher
/// Zeitzone; in UTC (CI) prüfen sie die Kalenderrechnung.
void main() {
  group('tagPlus', () {
    test('über das Ende der Sommerzeit am 25.10.2026', () {
      final samstag = DateTime(2026, 10, 24);
      final sonntag = tagPlus(samstag, 1);
      final montag = tagPlus(sonntag, 1);

      expect(sonntag, DateTime(2026, 10, 25));
      expect(montag, DateTime(2026, 10, 26));
      expect(montag.hour, 0);
      expect(montag.weekday, DateTime.monday);
    });

    test('über den Beginn der Sommerzeit am 29.03.2026', () {
      final samstag = DateTime(2026, 3, 28);
      expect(tagPlus(samstag, 1), DateTime(2026, 3, 29));
      expect(tagPlus(samstag, 2), DateTime(2026, 3, 30));
      expect(tagPlus(samstag, 2).hour, 0);
    });

    test('eine Woche weiter über die Umstellung bleibt Montag', () {
      final montag = DateTime(2026, 10, 19);
      expect(tagPlus(montag, 7), DateTime(2026, 10, 26));
      expect(tagPlus(montag, 7).weekday, DateTime.monday);
      expect(tagPlus(DateTime(2026, 10, 26), -7), montag);
    });

    test('rückwärts und über Monats- und Jahresgrenzen', () {
      expect(tagPlus(DateTime(2026, 3, 1), -1), DateTime(2026, 2, 28));
      expect(tagPlus(DateTime(2026, 12, 31), 1), DateTime(2027, 1, 1));
      expect(tagPlus(DateTime(2027, 1, 1), -1), DateTime(2026, 12, 31));
      expect(tagPlus(DateTime(2028, 2, 28), 1), DateTime(2028, 2, 29));
    });

    test('schneidet die Uhrzeit ab', () {
      expect(tagPlus(DateTime(2026, 10, 25, 23, 30), 0), DateTime(2026, 10, 25));
      expect(tagPlus(DateTime(2026, 10, 24, 23), 1), DateTime(2026, 10, 25));
    });

    test('ein ganzes Jahr Tag für Tag: jeder Kalendertag genau einmal', () {
      var tag = DateTime(2026, 1, 1);
      final gesehen = <String>{};
      for (var i = 0; i < 365; i++) {
        expect(tag.hour, 0, reason: 'Tag $i');
        expect(
          gesehen.add('${tag.year}-${tag.month}-${tag.day}'),
          isTrue,
          reason: 'Tag $i doppelt: $tag',
        );
        final naechster = tagPlus(tag, 1);
        expect(naechster.weekday, tag.weekday % 7 + 1, reason: 'nach $tag');
        tag = naechster;
      }
      expect(tag, DateTime(2027, 1, 1));
    });
  });

  group('tagOhneZeit', () {
    test('liefert 00:00 desselben Kalendertags', () {
      expect(tagOhneZeit(DateTime(2026, 10, 25, 2, 30)), DateTime(2026, 10, 25));
      expect(tagOhneZeit(DateTime(2026, 10, 25)), DateTime(2026, 10, 25));
    });
  });
}
