import 'dart:convert';
import 'dart:typed_data';

import 'package:erfassung_format/erfassung_format.dart';
import 'package:flutter_test/flutter_test.dart';

import 'beispiel.dart';

/// Tests fürs verschlüsselte Ergebnis: Nur mit dem Schlüssel aus dem
/// Paket lässt es sich öffnen, und jede Veränderung fällt auf.
void main() {
  final schluessel = Uint8List.fromList(List.generate(32, (i) => i * 7));
  final anderer = Uint8List.fromList(List.generate(32, (i) => 255 - i));
  final ergebnis = ErfassungsErgebnis(
    paketId: 'paket-1',
    erstellt: DateTime(2026, 11, 23, 14, 10),
    produktionen: [
      ErfassteProduktion(
        produktionId: 't1',
        artikelId: 'a1',
        artikel: 'Grillwurst',
        datum: DateTime(2026, 11, 23),
        rohKg: 510,
        fertigKg: 402.5,
        erfasstAm: DateTime(2026, 11, 23, 14),
      ),
    ],
  );

  test('hin und zurück — derselbe Inhalt', () {
    final text = ergebnisGeschuetzt(ergebnis, schluessel);
    // Unterwegs ist vom Inhalt nichts zu lesen.
    expect(text.contains('Grillwurst'), isFalse);
    expect(text.contains('402.5'), isFalse);

    final g = geschuetztesErgebnis(text)!;
    expect(g.paketId, 'paket-1');
    final offen = ergebnisEntschluesseln(g, schluessel);
    expect(offen.alsText(), ergebnis.alsText());
  });

  test('zweimal verschlüsselt sieht jedes Mal anders aus', () {
    expect(
      ergebnisGeschuetzt(ergebnis, schluessel),
      isNot(ergebnisGeschuetzt(ergebnis, schluessel)),
    );
  });

  test('falscher Schlüssel: FormatFehler', () {
    final g = geschuetztesErgebnis(ergebnisGeschuetzt(ergebnis, schluessel))!;
    expect(
      () => ergebnisEntschluesseln(g, anderer),
      throwsA(isA<FormatFehler>()),
    );
  });

  test('ein verändertes Byte: FormatFehler', () {
    final g = geschuetztesErgebnis(ergebnisGeschuetzt(ergebnis, schluessel))!;
    for (final stelle in [0, 20, g.daten.length - 1]) {
      final kaputt = Uint8List.fromList(g.daten);
      kaputt[stelle] ^= 1;
      expect(
        () => ergebnisEntschluesseln(
          (paketId: g.paketId, daten: kaputt),
          schluessel,
        ),
        throwsA(isA<FormatFehler>()),
        reason: 'Byte $stelle',
      );
    }
  });

  test('eine ausgetauschte Paket-ID: FormatFehler', () {
    final g = geschuetztesErgebnis(ergebnisGeschuetzt(ergebnis, schluessel))!;
    expect(
      () => ergebnisEntschluesseln(
        (paketId: 'paket-2', daten: g.daten),
        schluessel,
      ),
      throwsA(isA<FormatFehler>()),
    );
  });

  test('ein offenes Ergebnis ist kein geschütztes', () {
    expect(geschuetztesErgebnis(ergebnis.alsText()), isNull);
    expect(geschuetztesErgebnis('kein JSON'), isNull);
    expect(geschuetztesErgebnis(beispielPaket().alsText()), isNull);
  });

  test('ein geschütztes Ergebnis ist kein Paket und kein offenes', () {
    final text = ergebnisGeschuetzt(ergebnis, schluessel);
    expect(
      () => ErfassungsPaket.ausText(text),
      throwsA(
        isA<FormatFehler>().having(
          (f) => f.meldung,
          'meldung',
          contains('Ergebnis vom Handy'),
        ),
      ),
    );
    expect(dateiArtVon(text), DateiArt.ergebnisGeschuetzt);
  });

  test('aus einer neueren Fassung: FormatFehler', () {
    final j = jsonDecode(ergebnisGeschuetzt(ergebnis, schluessel))
        as Map<String, Object?>;
    j['version'] = 2;
    expect(
      () => geschuetztesErgebnis(jsonEncode(j)),
      throwsA(isA<FormatFehler>()),
    );
  });

  test('der Schlüssel reist im Paket mit', () {
    final mit = ErfassungsPaket(
      id: 'p',
      erstellt: DateTime(2026, 11, 23),
      von: DateTime(2026, 11, 23),
      bis: DateTime(2026, 11, 29),
      ergebnisSchluessel: base64Encode(schluessel),
    );
    final wieder = ErfassungsPaket.ausText(mit.alsText());
    expect(wieder.ergebnisSchluesselBytes, schluessel);

    // Ein Paket aus einem älteren Planer hat keinen.
    expect(beispielPaket().ergebnisSchluesselBytes, isNull);
    // Einer in falscher Länge zählt nicht.
    final kurz = ErfassungsPaket(
      id: 'p',
      erstellt: DateTime(2026, 11, 23),
      von: DateTime(2026, 11, 23),
      bis: DateTime(2026, 11, 29),
      ergebnisSchluessel: base64Encode([1, 2, 3]),
    );
    expect(kurz.ergebnisSchluesselBytes, isNull);
  });
}
