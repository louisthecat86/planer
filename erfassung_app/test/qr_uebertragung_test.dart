import 'dart:math';
import 'dart:typed_data';

import 'package:erfassung_format/erfassung_format.dart';
import 'package:flutter_test/flutter_test.dart';

import 'beispiel.dart';

/// Tests für die Übertragung des Pakets per QR-Code: aufteilen, in
/// beliebiger Reihenfolge einsammeln, zusammensetzen.
void main() {
  group('Base45', () {
    test('Beispiele aus RFC 9285', () {
      expect(base45Kodieren('AB'.codeUnits), 'BB8');
      expect(base45Kodieren('Hello!!'.codeUnits), '%69 VD92EX0');
      expect(base45Kodieren('base-45'.codeUnits), 'UJCLQE7W581');
      expect(String.fromCharCodes(base45Dekodieren('QED8WEX0')), 'ietf!');
    });

    test('Hin und zurück mit allen Bytewerten', () {
      final r = Random(7);
      for (final n in [0, 1, 2, 3, 255, 256, 1001]) {
        final d = Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
        expect(base45Dekodieren(base45Kodieren(d)), d, reason: '$n Bytes');
      }
      final alle = Uint8List.fromList(List.generate(256, (i) => i));
      expect(base45Dekodieren(base45Kodieren(alle)), alle);
    });

    test('fremde Zeichen und falsche Länge', () {
      expect(() => base45Dekodieren('abc'), throwsFormatException);
      expect(() => base45Dekodieren('BB8B'), throwsFormatException);
      expect(() => base45Dekodieren('GGW'), throwsFormatException);
    });
  });

  group('QR-Bilder', () {
    test('nur Zeichen, die ein alphanumerischer QR-Code kennt', () {
      final bilder = qrBilder(beispielPaket(), lauf: 'A7K2');
      final erlaubt = RegExp(r'^[0-9A-Z $%*+\-./:]+$');
      for (final b in bilder) {
        expect(erlaubt.hasMatch(b), isTrue, reason: b);
        expect(b.startsWith('PQ1/A7K2/'), isTrue);
        // Passt in einen QR-Code der Version 25 mit Stufe L.
        expect(b.length, lessThanOrEqualTo(1853));
      }
    });

    test('in beliebiger Reihenfolge und doppelt eingesammelt', () {
      final r = Random(3);
      final daten = Uint8List.fromList(
        List.generate(4321, (_) => r.nextInt(256)),
      );
      final bilder = qrBilderAus(daten, lauf: 'X1', bytesJeBild: 500);
      expect(bilder, hasLength(9));
      final s = QrSammler();
      expect(s.anzahl, 0);
      expect(s.fertig, isFalse);
      final reihe = [...bilder, ...bilder]..shuffle(r);
      var neu = 0;
      for (final b in reihe) {
        if (s.aufnehmen(b)) neu++;
      }
      expect(neu, 9);
      expect(s.vorhanden, 9);
      expect(s.anzahl, 9);
      expect(s.fertig, isTrue);
      expect(s.bytes(), daten);
    });

    test('ein ganzes Paket kommt unverändert an', () {
      final paket = beispielPaket();
      final bilder = qrBilder(paket, lauf: 'P1', bytesJeBild: 200);
      expect(bilder.length, greaterThan(1));
      final s = QrSammler();
      for (final b in bilder.reversed) {
        s.aufnehmen(b);
      }
      expect(s.paket().alsText(), paket.alsText());
    });

    test('fremde QR-Codes werden übergangen', () {
      final s = QrSammler();
      for (final t in [
        'https://example.org',
        'PQ1/A/1/2',
        'PQ1/A/3/2/BB8',
        'PQ1/A/0/2/BB8',
        'PQ1/A/X/2/BB8',
        'PQ1/A/1/2/abc',
        'PQ2/A/1/2/BB8',
      ]) {
        expect(s.aufnehmen(t), isFalse, reason: t);
      }
      expect(s.anzahl, 0);
      expect(() => s.bytes(), throwsStateError);
    });

    test('ein neues Paket fängt von vorn an', () {
      final s = QrSammler();
      final alt = qrBilderAus(Uint8List(900), lauf: 'ALT', bytesJeBild: 300);
      s
        ..aufnehmen(alt[0])
        ..aufnehmen(alt[1]);
      expect(s.vorhanden, 2);
      final neu = qrBilderAus(Uint8List(600), lauf: 'NEU', bytesJeBild: 300);
      expect(s.aufnehmen(neu[1]), isTrue);
      expect(s.vorhanden, 1);
      expect(s.anzahl, 2);
      s.leeren();
      expect(s.anzahl, 0);
    });

    test('verfälschte Daten ergeben einen FormatFehler', () {
      final s = QrSammler()
        ..aufnehmen(
          qrBilderAus(Uint8List.fromList([1, 2, 3, 4]), lauf: 'K')[0],
        );
      expect(s.fertig, isTrue);
      expect(s.paket, throwsA(isA<FormatFehler>()));
    });

    test('Lauf nur aus Ziffern und Großbuchstaben', () {
      expect(
        () => qrBilderAus(Uint8List(3), lauf: 'a/b'),
        throwsArgumentError,
      );
    });
  });
}
