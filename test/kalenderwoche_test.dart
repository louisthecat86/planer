import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/utils/kalenderwoche.dart';

void main() {
  group('isoKalenderwoche', () {
    test('21.09.2026 ist KW 39 — hier stand vorher KW 38', () {
      expect(isoKalenderwoche(DateTime(2026, 9, 21)), 39);
    });

    test('Tage, an denen die Sommerzeit die alte Rechnung verschob', () {
      // Die Referenz stammt aus Pythons date.isocalendar().
      expect(isoKalenderwoche(DateTime(2026, 3, 30)), 14);
      expect(isoKalenderwoche(DateTime(2026, 7, 13)), 29);
      expect(isoKalenderwoche(DateTime(2026, 9, 24)), 39);
    });

    test('alle Tage einer Woche liegen in derselben KW', () {
      final montag = DateTime(2026, 9, 21);
      for (var i = 0; i < 7; i++) {
        expect(
          isoKalenderwoche(montag.add(Duration(days: i))),
          39,
          reason: 'Tag $i der Woche',
        );
      }
    });

    test('Jahreswechsel: Woche gehört zum Jahr ihres Donnerstags', () {
      expect(isoKalenderwoche(DateTime(2025, 12, 29)), 1);
      expect(isoKalenderjahr(DateTime(2025, 12, 29)), 2026);

      expect(isoKalenderwoche(DateTime(2024, 12, 30)), 1);
      expect(isoKalenderjahr(DateTime(2024, 12, 30)), 2025);

      expect(isoKalenderwoche(DateTime(2027)), 53);
      expect(isoKalenderjahr(DateTime(2027)), 2026);
    });

    test('Jahre mit 53 Wochen', () {
      expect(isoKalenderwoche(DateTime(2020, 12, 31)), 53);
      expect(isoKalenderwoche(DateTime(2021, 1, 3)), 53);
      expect(isoKalenderwoche(DateTime(2021, 1, 4)), 1);
      expect(isoKalenderwoche(DateTime(2026, 12, 31)), 53);
    });

    test('Uhrzeit spielt keine Rolle', () {
      expect(isoKalenderwoche(DateTime(2026, 9, 21, 23, 59)), 39);
      expect(isoKalenderwoche(DateTime(2026, 9, 21, 0, 1)), 39);
    });
  });
}
