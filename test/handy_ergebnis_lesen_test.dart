import 'dart:convert';
import 'dart:typed_data';

import 'package:erfassung_format/erfassung_format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/features/handy_erfassung/handy_erfassung_dienst.dart';

/// Tests fürs Lesen der Ergebnis-Datei vom Handy: Kleine Dateien liest die
/// App gleich, große im Hintergrund — beides muss dasselbe ergeben. Das
/// Lesen im Hintergrund schlug früher bei jeder großen Datei fehl.
void main() {
  final ergebnis = ErfassungsErgebnis(
    paketId: 'paket-1',
    erstellt: DateTime(2026, 11, 10, 18, 10),
    produktionen: [
      ErfassteProduktion(
        produktionId: 't1',
        artikelId: 'a1',
        artikel: 'Grillwurst',
        datum: DateTime(2026, 11, 10),
        rohKg: 510,
        fertigKg: 402.5,
        erfasstAm: DateTime(2026, 11, 10, 14),
      ),
    ],
  );

  Uint8List datei({int mindestens = 0}) {
    final text = ergebnis.alsText();
    // Leerraum am Ende ändert am Inhalt nichts, macht die Datei aber so
    // groß wie eine mit Fotos.
    final fuellung = mindestens - text.length;
    return Uint8List.fromList(
      utf8.encode(fuellung > 0 ? '$text${' ' * fuellung}' : text),
    );
  }

  test('eine kleine Datei', () async {
    final bytes = datei();
    expect(bytes.length, lessThan(kErgebnisImHintergrundAb));

    final gelesen = await ergebnisLesen(bytes);

    expect(gelesen.paketId, 'paket-1');
    expect(gelesen.produktionen.single.fertigKg, 402.5);
  });

  test('eine große Datei — im Hintergrund gelesen, derselbe Inhalt', () async {
    final bytes = datei(mindestens: kErgebnisImHintergrundAb + 1000);
    expect(bytes.length, greaterThan(kErgebnisImHintergrundAb));

    final gelesen = await ergebnisLesen(bytes);

    expect(gelesen.paketId, 'paket-1');
    expect(gelesen.erstellt, DateTime(2026, 11, 10, 18, 10));
    expect(gelesen.produktionen.single.produktionId, 't1');
    expect(gelesen.produktionen.single.rohKg, 510);
  });

  test('eine kaputte große Datei meldet, was nicht stimmt', () async {
    final bytes = Uint8List.fromList(
      utf8.encode('{"das": "ist kein Ergebnis"}${' ' * 600000}'),
    );

    await expectLater(ergebnisLesen(bytes), throwsA(isA<Object>()));
  });
}
