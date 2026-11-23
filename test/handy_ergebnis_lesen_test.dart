import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:erfassung_format/erfassung_format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/features/handy_erfassung/handy_erfassung_dienst.dart';

import 'helpers/test_db.dart';

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

  group('verschlüsselt', () {
    test('der Planer öffnet, was mit dem Schlüssel aus seinem Paket kam',
        () async {
      final db = testDatenbank();
      addTearDown(db.close);
      final dienst = HandyErfassungDienst(db);
      final paket = await dienst.paketErstellen(
        von: DateTime(2026, 11, 9),
        bis: DateTime(2026, 11, 15),
      );
      final schluessel = paket.ergebnisSchluesselBytes!;
      // Derselbe Schlüssel lässt sich zur Paket-ID wieder ableiten — er
      // muss nirgends gespeichert sein.
      expect(await dienst.ergebnisSchluessel(paket.id), schluessel);
      // Jedes Paket hat seinen eigenen.
      expect(await dienst.ergebnisSchluessel('anderes'), isNot(schluessel));

      final vomHandy = ErfassungsErgebnis(
        paketId: paket.id,
        erstellt: ergebnis.erstellt,
        produktionen: ergebnis.produktionen,
      );
      final bytes = utf8.encode(ergebnisGeschuetzt(vomHandy, schluessel));
      final gelesen = await ergebnisLesen(
        bytes,
        schluesselFuer: dienst.ergebnisSchluessel,
      );
      expect(gelesen.paketId, paket.id);
      expect(gelesen.produktionen.single.fertigKg, 402.5);

      // Ohne Rückruf zum Schlüssel geht es nicht.
      await expectLater(
        ergebnisLesen(bytes),
        throwsA(isA<FormatFehler>()),
      );
    });

    test('groß — im Hintergrund entschlüsselt', () async {
      final db = testDatenbank();
      addTearDown(db.close);
      final dienst = HandyErfassungDienst(db);
      final schluessel = (await dienst.ergebnisSchluessel('p', anlegen: true))!;
      // Ein „Foto" aus Zufall lässt sich nicht packen — so wird die Datei
      // wirklich groß.
      final zufall = Random(1);
      final bild = Uint8List.fromList([
        0xFF,
        0xD8,
        0xFF,
        for (var i = 0; i < 700000; i++) zufall.nextInt(256),
      ]);
      final gross = ErfassungsErgebnis(
        paketId: 'p',
        erstellt: ergebnis.erstellt,
        fotos: [
          ErfasstesFoto(
            id: 'f1',
            art: FotoArt.muster,
            aufgenommenAm: ergebnis.erstellt,
            bezeichnung: 'Muster',
            groesse: bild.length,
            daten: bild,
          ),
        ],
      );
      final bytes = utf8.encode(ergebnisGeschuetzt(gross, schluessel));
      expect(bytes.length, greaterThan(kErgebnisImHintergrundAb));
      final gelesen = await ergebnisLesen(
        bytes,
        schluesselFuer: dienst.ergebnisSchluessel,
      );
      expect(gelesen.fotos.single.daten, bild);
    });

    test('von einem anderen Planer: verständlicher Fehler', () async {
      final hier = testDatenbank();
      final dort = testDatenbank();
      addTearDown(hier.close);
      addTearDown(dort.close);
      final fremd = (await HandyErfassungDienst(dort)
          .ergebnisSchluessel('p', anlegen: true))!;
      final bytes = utf8.encode(
        ergebnisGeschuetzt(
          ErfassungsErgebnis(paketId: 'p', erstellt: ergebnis.erstellt),
          fremd,
        ),
      );
      final dienst = HandyErfassungDienst(hier);
      // Noch ganz ohne Geheimnis.
      await expectLater(
        ergebnisLesen(bytes, schluesselFuer: dienst.ergebnisSchluessel),
        throwsA(isA<FormatFehler>()),
      );
      // Mit eigenem, aber anderem.
      await dienst.ergebnisSchluessel('x', anlegen: true);
      await expectLater(
        ergebnisLesen(bytes, schluesselFuer: dienst.ergebnisSchluessel),
        throwsA(
          isA<FormatFehler>().having(
            (f) => f.meldung,
            'meldung',
            contains('anderen Planers'),
          ),
        ),
      );
    });
  });
}
