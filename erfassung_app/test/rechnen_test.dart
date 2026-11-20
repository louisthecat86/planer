import 'package:erfassung_format/erfassung_format.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests fürs Rechnen in den Mengenfeldern: „270*10" wird 2700 — nur das
/// Ergebnis zählt.
void main() {
  group('rechneAus', () {
    test('Kutterwagen mal Anzahl', () {
      expect(rechneAus('270*10'), 2700);
      expect(rechneAus('270x10'), 2700);
      expect(rechneAus('270 × 10'), 2700);
      expect(rechneAus('10 X 270'), 2700);
    });

    test('plus, minus, geteilt — Punkt vor Strich', () {
      expect(rechneAus('270*10+35,5'), 2735.5);
      expect(rechneAus('35.5+270*10'), 2735.5);
      expect(rechneAus('2700-12,5'), 2687.5);
      expect(rechneAus('2700−12,5'), 2687.5);
      expect(rechneAus('2700/4'), 675);
      expect(rechneAus('2700:4'), 675);
      expect(rechneAus('(270+250)*4'), 2080);
      expect(rechneAus('3*-2'), -6);
    });

    test('ohne Rechenzeichen wie eine Zahl', () {
      expect(rechneAus('512,5'), 512.5);
      expect(rechneAus(' 1250 '), 1250);
      expect(rechneAus('-5'), -5);
      expect(rechneAus(''), isNull);
      expect(rechneAus(null), isNull);
    });

    test('unvollständig oder unsinnig: null', () {
      for (final t in [
        '270*',
        '*10',
        '270**10',
        '270*10)',
        '(270*10',
        '27,0,5*2',
        '270*abc',
        '10/0',
        '()',
      ]) {
        expect(rechneAus(t), isNull, reason: t);
      }
    });

    test('was als Rechnung zählt', () {
      expect(istRechnung('270*10'), isTrue);
      expect(istRechnung('2700-12'), isTrue);
      expect(istRechnung('270'), isFalse);
      expect(istRechnung('-270'), isFalse);
      expect(istRechnung('12,5'), isFalse);
      expect(istRechnung(''), isFalse);
    });
  });
}
