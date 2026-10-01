import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/services/auftragsbestand_vergleich.dart';

/// Tests für die Änderungsansicht: Vergleich zweier Auftragsbestände und
/// die Prüfung, ob ein neuer Bericht zum bisherigen passt.
///
/// Reine Rechnung, ohne Datenbank — mit erfundenen Aufträgen. Ein echter
/// Bericht gehört nicht ins Repository: Er enthält Kunden und Mengen.
void main() {
  // Vorher: erstellt Mi 30.09., Warenausgang 28.09.–30.10.
  // Jetzt:  erstellt Do 01.10., Warenausgang 28.09.–31.10.
  final vorherStand = DateTime(2026, 9, 30, 6);
  final jetztStand = DateTime(2026, 10, 1, 6);
  final montag = DateTime(2026, 10, 5);
  final dienstag = DateTime(2026, 10, 6);
  final mittwoch = DateTime(2026, 10, 7);
  final donnerstag = DateTime(2026, 10, 8);
  final freitag = DateTime(2026, 10, 9);

  BestandsZeile zeile(
    String beleg,
    DateTime tag,
    double kg, {
    String artikel = '100',
    String kunde = 'Kunde A',
  }) =>
      BestandsZeile(
        artikelnummer: artikel,
        beleg: beleg,
        warenausgang: tag,
        kg: kg,
        debitor: kunde,
      );

  BestandsStand bericht(
    DateTime erstellt,
    List<BestandsZeile> zeilen, {
    DateTime? von,
    DateTime? bis,
    Map<String, double> lager = const {},
  }) {
    final nummern = {...zeilen.map((z) => z.artikelnummer), ...lager.keys};
    return BestandsStand(
      stand: erstellt,
      von: von ?? DateTime(2026, 9, 28),
      bis: bis ?? DateTime(2026, 10, 31),
      importiertAm: erstellt,
      artikel: {
        for (final nr in nummern)
          nr: BestandsArtikel(
            nummer: nr,
            bezeichnung: 'Artikel $nr',
            lagerKg: lager[nr] ?? 0,
          ),
      },
      zeilen: zeilen,
    );
  }

  BestandsStand vorher(
    List<BestandsZeile> zeilen, {
    Map<String, double> lager = const {},
  }) =>
      bericht(
        vorherStand,
        zeilen,
        bis: DateTime(2026, 10, 30),
        lager: lager,
      );

  BestandsStand jetzt(
    List<BestandsZeile> zeilen, {
    Map<String, double> lager = const {},
  }) =>
      bericht(jetztStand, zeilen, lager: lager);

  group('vergleicheBestand', () {
    test('erkennt neu, mehr, weniger und entfallen', () {
      final v = vergleicheBestand(
        vorher([
          zeile('VA1', montag, 100),
          zeile('VA2', dienstag, 50),
          zeile('VA3', mittwoch, 30),
        ]),
        jetzt([
          zeile('VA1', montag, 120),
          zeile('VA2', dienstag, 40),
          zeile('VA4', donnerstag, 20),
        ]),
      );

      expect(v.ohneVorher, isFalse);
      expect(v.anzahl(AenderungsArt.mehr), 1);
      expect(v.anzahl(AenderungsArt.weniger), 1);
      expect(v.anzahl(AenderungsArt.entfallen), 1);
      expect(v.anzahl(AenderungsArt.neu), 1);
      expect(v.kurzfassung, '1 neu · 1 mehr · 1 weniger · 1 entfallen');

      final weniger =
          v.zeilen.singleWhere((z) => z.art == AenderungsArt.weniger);
      expect(weniger.beleg, 'VA2');
      expect(weniger.kgVorher, 50);
      expect(weniger.kg, 40);
      expect(weniger.differenzKg, -10);

      // Nach Versandtag sortiert.
      expect(
        v.artikel.single.zeilen.map((z) => z.beleg),
        ['VA1', 'VA2', 'VA3', 'VA4'],
      );
    });

    test('fehlt und der Versandtag ist vorbei: ausgeliefert', () {
      final v = vergleicheBestand(
        vorher([
          zeile('VA1', DateTime(2026, 9, 30), 10),
          // Versand am Tag des neuen Berichts: auch ausgeliefert.
          zeile('VA2', DateTime(2026, 10, 1), 20),
          zeile('VA3', montag, 30),
        ]),
        jetzt([zeile('VA3', montag, 30)]),
      );

      expect(v.anzahl(AenderungsArt.ausgeliefert), 2);
      expect(v.anzahl(AenderungsArt.entfallen), 0);
      // Planmäßig rausgegangen ist keine wesentliche Änderung.
      expect(v.kurzfassung, '');
    });

    test('derselbe Beleg an einem anderen Tag ist verschoben', () {
      final v = vergleicheBestand(
        vorher([zeile('VA1', montag, 100)]),
        jetzt([zeile('VA1', freitag, 100)]),
      );

      final z = v.zeilen.single;
      expect(z.art, AenderungsArt.verschoben);
      expect(z.warenausgangVorher, montag);
      expect(z.warenausgang, freitag);
      expect(v.kurzfassung, '1 verschoben');
    });

    test('ist der alte Tag vorbei, ist nichts verschoben', () {
      // Die Zeile vom 30.09. ist raus; die neue am Montag ist eine weitere
      // Lieferung desselben Auftrags.
      final v = vergleicheBestand(
        vorher([zeile('VA1', DateTime(2026, 9, 30), 100)]),
        jetzt([zeile('VA1', montag, 100)]),
      );

      expect(v.anzahl(AenderungsArt.verschoben), 0);
      expect(v.anzahl(AenderungsArt.ausgeliefert), 1);
      expect(v.anzahl(AenderungsArt.neu), 1);
    });

    test('lassen sich die Tage nicht zuordnen, ist nichts verschoben', () {
      final v = vergleicheBestand(
        vorher([zeile('VA1', montag, 50), zeile('VA1', dienstag, 50)]),
        jetzt([zeile('VA1', freitag, 100)]),
      );

      expect(v.anzahl(AenderungsArt.verschoben), 0);
      expect(v.anzahl(AenderungsArt.entfallen), 2);
      expect(v.anzahl(AenderungsArt.neu), 1);
    });

    test('außerhalb des Zeitraums und erstmals im Zeitraum', () {
      // Der neue Bericht beginnt einen Tag später und reicht einen Tag
      // weiter als der vorige.
      final v = vergleicheBestand(
        vorher([zeile('VA1', DateTime(2026, 9, 28), 10)]),
        bericht(
          jetztStand,
          [zeile('VA2', DateTime(2026, 10, 31), 20)],
          von: DateTime(2026, 9, 29),
        ),
      );

      expect(
        v.zeilen.singleWhere((z) => z.beleg == 'VA1').art,
        AenderungsArt.ausserhalb,
      );
      expect(
        v.zeilen.singleWhere((z) => z.beleg == 'VA2').art,
        AenderungsArt.erstmals,
      );
      // Beides bringt nur der Zeitraum mit.
      expect(v.kurzfassung, '');
    });

    test('Zeilen desselben Belegs am selben Tag werden summiert', () {
      final v = vergleicheBestand(
        vorher([zeile('VA1', montag, 30), zeile('VA1', montag, 20)]),
        jetzt([zeile('VA1', montag, 50)]),
      );

      expect(v.artikel, isEmpty);
    });

    test('zeigt das Lager vorher und jetzt', () {
      final v = vergleicheBestand(
        vorher([zeile('VA1', montag, 100)], lager: {'100': 10}),
        jetzt([zeile('VA1', montag, 120)], lager: {'100': 25}),
      );

      final a = v.artikel.single;
      expect(a.lagerVorherKg, 10);
      expect(a.lagerKg, 25);
      expect(a.lagerGeaendert, isTrue);
      expect(a.neuImBericht, isFalse);
    });

    test('ohne vorigen Bericht gibt es keinen Vergleich', () {
      final v = vergleicheBestand(
        const BestandsStand(),
        jetzt([zeile('VA1', montag, 100)]),
      );

      expect(v.ohneVorher, isTrue);
      expect(v.artikel, isEmpty);
      expect(v.hinweise, isEmpty);
      expect(v.kurzfassung, '');
    });
  });

  group('pruefeUmfang', () {
    // Fünf Kunden mit künftigen Aufträgen für denselben Artikel.
    List<BestandsZeile> fuenfKunden() => [
          for (var i = 0; i < 5; i++)
            zeile(
              'VA${i + 1}',
              DateTime(2026, 10, 5 + i),
              10,
              kunde: 'Kunde ${String.fromCharCode(65 + i)}',
            ),
        ];

    test('ein normaler nächster Bericht ist unauffällig', () {
      // Ein Auftrag storniert, einer neu — Alltag.
      final hinweise = pruefeUmfang(
        vorher(fuenfKunden()),
        jetzt([
          ...fuenfKunden().take(4),
          zeile('VA9', freitag, 15, kunde: 'Kunde F'),
        ]),
      );

      expect(hinweise, isEmpty);
    });

    test('ohne vorigen Bericht gibt es nichts zu prüfen', () {
      expect(
        pruefeUmfang(const BestandsStand(), jetzt(fuenfKunden())),
        isEmpty,
      );
    });

    test('ein älterer Bericht ist ernst', () {
      final hinweise = pruefeUmfang(
        jetzt(fuenfKunden()),
        vorher(fuenfKunden()),
      );

      expect(hinweise.where((h) => h.ernst), isNotEmpty);
      expect(hinweise.first.text, contains('älter'));
    });

    test('derselbe Bericht noch einmal ist nur ein Hinweis', () {
      final hinweise = pruefeUmfang(
        jetzt(fuenfKunden()),
        jetzt(fuenfKunden()),
      );

      expect(hinweise, hasLength(1));
      expect(hinweise.single.ernst, isFalse);
      expect(hinweise.single.text, contains('Derselbe Bericht'));
    });

    test('nach Kunden gefiltert: ernst', () {
      final hinweise = pruefeUmfang(
        vorher(fuenfKunden()),
        jetzt([fuenfKunden().first]),
      );

      expect(
        hinweise.where((h) => h.ernst && h.text.contains('Kunden')),
        hasLength(1),
      );
    });

    test('nach Artikeln gefiltert: ernst', () {
      final vierArtikel = [
        for (var i = 0; i < 4; i++)
          zeile('VA${i + 1}', montag, 10, artikel: '${100 + i}'),
      ];
      final hinweise = pruefeUmfang(
        vorher(vierArtikel),
        jetzt([vierArtikel.first]),
      );

      expect(
        hinweise.where((h) => h.ernst && h.text.contains('Artikeln')),
        hasLength(1),
      );
    });

    test('auffällig viele fehlende künftige Zeilen: ernst', () {
      // Zwei Kunden, ein Artikel — die Kunden- und Artikelprüfung greift
      // nicht. Von zwölf künftigen Zeilen fehlen sieben.
      final zwoelf = [
        for (var i = 0; i < 12; i++)
          zeile(
            'VA${i + 1}',
            DateTime(2026, 10, 5 + i % 5),
            10,
            kunde: i.isEven ? 'Kunde A' : 'Kunde B',
          ),
      ];
      final hinweise = pruefeUmfang(
        vorher(zwoelf),
        jetzt(zwoelf.take(5).toList()),
      );

      expect(
        hinweise.where((h) => h.ernst && h.text.contains('Auftragszeilen')),
        hasLength(1),
      );
    });

    test('Zeitraum ohne Überschneidung: ernst', () {
      final hinweise = pruefeUmfang(
        vorher(fuenfKunden()),
        bericht(
          jetztStand,
          [zeile('VA1', DateTime(2026, 11, 10), 10)],
          von: DateTime(2026, 11, 2),
          bis: DateTime(2026, 11, 30),
        ),
      );

      expect(
        hinweise.where((h) => h.ernst && h.text.contains('überschneidet')),
        hasLength(1),
      );
    });

    test('Bericht beginnt erst nach dem Erstellungstag: ernst', () {
      final hinweise = pruefeUmfang(
        vorher(fuenfKunden()),
        bericht(jetztStand, fuenfKunden(), von: DateTime(2026, 10, 5)),
      );

      expect(
        hinweise.where((h) => h.ernst && h.text.contains('beginnt erst')),
        hasLength(1),
      );
    });

    test('kürzerer Zeitraum: Hinweis, nicht ernst', () {
      final hinweise = pruefeUmfang(
        vorher(fuenfKunden()),
        bericht(jetztStand, fuenfKunden(), bis: DateTime(2026, 10, 20)),
      );

      expect(hinweise, hasLength(1));
      expect(hinweise.single.ernst, isFalse);
      expect(hinweise.single.text, contains('reicht nur bis'));
    });
  });
}
