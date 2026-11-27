import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/auftragsbestand_deckung.dart';
import 'package:produktion_planer/features/auftragsbestand/auftragsbestand_ansicht.dart';
import 'package:produktion_planer/features/auftragsbestand/lieferfaehigkeit.dart';
import 'package:produktion_planer/features/statistik/statistik_ueberblick_daten.dart'
    show Ampel;

/// Tests für die Lieferfähigkeit im Cockpit und im Wochenbericht: wie viel
/// der Auftragsmenge der nächsten Tage rechtzeitig gedeckt ist. Alle
/// Artikel, Belege und Kunden sind erfunden.
void main() {
  final heute = DateTime(2026, 11, 25); // Mittwoch
  final stand = DateTime(2026, 11, 25, 6);
  var naechsteId = 1;

  AuftragsPosition pos(String nummer, DateTime tag, double kg) =>
      AuftragsPosition(
        id: naechsteId++,
        artikelnummer: nummer,
        beleg: 'VA$naechsteId',
        debitor: 'Kunde ${naechsteId % 3}',
        warenausgang: tag,
        menge: kg,
        kg: kg,
      );

  AuftragsbestandZeile zeile(
    String nummer, {
    required double lager,
    required List<AuftragsPosition> positionen,
    List<ProduktionsZugang> zugaenge = const [],
  }) {
    final artikel = AuftragsArtikel(
      artikelnummer: nummer,
      bezeichnung: 'Testartikel $nummer',
      lagerKg: lager,
      auftragKg: positionen.fold(0.0, (s, p) => s + p.kg),
      berichtStand: stand,
      importiertAm: stand,
    );
    return AuftragsbestandZeile(
      artikel: artikel,
      positionen: positionen,
      zugaenge: zugaenge,
      deckung: berechneDeckung(
        lagerKg: lager,
        positionen: positionen,
        zugaenge: zugaenge,
      ),
    );
  }

  ProduktionsZugang produktion(DateTime fertig, double kg) => ProduktionsZugang(
        kettenId: 'k${fertig.day}',
        productId: 'p',
        fertigAm: fertig,
        art: ZugangsArt.eingeplant,
        kg: kg,
      );

  AuftragsbestandAnsicht ansicht(List<AuftragsbestandZeile> zeilen) =>
      AuftragsbestandAnsicht(
        zeilen: zeilen,
        stand: stand,
        berichtTag: DateTime(2026, 11, 25),
      );

  test('ohne Auftragsbestand: keine Zahl, graue Ampel', () {
    final l = werteLieferfaehigkeitAus(
      const AuftragsbestandAnsicht(zeilen: []),
      heute: heute,
    );
    expect(l.anteil, isNull);
    expect(l.ampel, Ampel.neutral);
    expect(l.unterText, 'kein Auftragsbestand eingelesen');
    expect(l.herkunftText, isNull);
  });

  test('Lager, rechtzeitige und zu späte Produktion', () {
    final l = werteLieferfaehigkeitAus(
      ansicht([
        // Ganz aus dem Lager.
        zeile(
          '9001',
          lager: 500,
          positionen: [pos('9001', DateTime(2026, 11, 26), 300)],
        ),
        // 200 kg rechtzeitig produziert, 100 kg kommen zu spät.
        zeile(
          '9002',
          lager: 0,
          positionen: [
            pos('9002', DateTime(2026, 11, 27), 200),
            pos('9002', DateTime(2026, 11, 30), 100),
          ],
          zugaenge: [
            produktion(DateTime(2026, 11, 26), 200),
            produktion(DateTime(2026, 12, 2), 100),
          ],
        ),
        // Nichts da, nichts geplant.
        zeile(
          '9003',
          lager: 0,
          positionen: [pos('9003', DateTime(2026, 11, 28), 400)],
        ),
        // Gestern und nach dem Zeitraum: zählt nicht.
        zeile(
          '9004',
          lager: 0,
          positionen: [
            pos('9004', DateTime(2026, 11, 24), 999),
            pos('9004', DateTime(2026, 12, 2), 999),
          ],
        ),
      ]),
      heute: heute,
    );
    expect(l.auftragKg, 1000);
    expect(l.gedecktKg, 500);
    expect(l.fehltKg, 400);
    expect(l.zuSpaetKg, 100);
    expect(l.anteil, 0.5);
    expect(l.ampel, Ampel.kritisch);
    expect(l.versandtage, 4);
    expect(
      [for (final g in l.gefaehrdet) (g.artikelnummer, g.tag.day)],
      [('9003', 28), ('9002', 30)],
    );
    expect(l.unterText, '2 von 4 Versandtagen gefährdet');
    expect(l.herkunftText, contains('Versand bis 01.12.'));
  });

  test('Ampel: grün ab 98 %, gelb ab 90 %, alter Bericht grau', () {
    Lieferfaehigkeit mit(double lager) => werteLieferfaehigkeitAus(
          ansicht([
            zeile(
              '9010',
              lager: lager,
              positionen: [pos('9010', DateTime(2026, 11, 26), 100)],
            ),
          ]),
          heute: heute,
        );
    expect(mit(100).ampel, Ampel.gut);
    expect(mit(100).unterText, 'alle 1 Versandtage gedeckt');
    expect(mit(95).ampel, Ampel.warnung);
    expect(mit(80).ampel, Ampel.kritisch);

    // Vier Tage nach dem Bericht: bitte neu einlesen.
    final spaeter = werteLieferfaehigkeitAus(
      ansicht([
        zeile(
          '9010',
          lager: 100,
          positionen: [pos('9010', DateTime(2026, 11, 30), 100)],
        ),
      ]),
      heute: DateTime(2026, 11, 29),
    );
    expect(spaeter.berichtAlterTage, 4);
    expect(spaeter.berichtAlt, isTrue);
    expect(spaeter.ampel, Ampel.neutral);
    expect(spaeter.herkunftText, contains('bitte neu einlesen'));
  });
}
