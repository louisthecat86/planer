import 'package:erfassung_format/erfassung_format.dart';

/// Ein erfundenes Paket für die Tests: zwei geplante Produktionen und
/// zwei Artikel, einer mit Füller und Bratstraße.
ErfassungsPaket beispielPaket({String id = 'paket-1'}) => ErfassungsPaket(
      id: id,
      erstellt: DateTime(2026, 11, 9, 17, 45),
      von: DateTime(2026, 11, 9),
      bis: DateTime(2026, 11, 15),
      produktionen: [
        PaketProduktion(
          id: 't1',
          artikelId: 'a1',
          artikelnummer: '4711',
          artikel: 'Grillwurst fein mit einem recht langen Namen 5 x 100 g',
          datum: DateTime(2026, 11, 10),
          abteilung: 'bratstrasse',
          abteilungName: 'Bratstraße',
          abteilungFarbe: 0xFF6A1B9A,
          start: '06:00',
          rohKg: 1250,
          fleischKg: 1000,
          fertigKg: 1000,
        ),
        PaketProduktion(
          id: 't2',
          artikelId: 'a2',
          artikelnummer: '4712',
          artikel: 'Kochschinken',
          datum: DateTime(2026, 11, 11),
          abteilung: 'wurstkueche',
          abteilungName: 'Wurstküche',
          rohKg: 300,
        ),
      ],
      artikel: [
        PaketArtikel(
          id: 'a1',
          nummer: '4711',
          name: 'Grillwurst fein mit einem recht langen Namen 5 x 100 g',
          schritte: [
            const PaketSchritt(
              id: 's1',
              nummer: 1,
              abteilung: 'wurstkueche',
              abteilungName: 'Wurstküche',
              abteilungFarbe: 0xFF880E4F,
              anlage: 'Füller Test',
              prozessschritt: 'Füllen',
              felder: [
                PaketFeld(
                  schluessel: 's:füllgewicht',
                  art: FeldArt.steckbrief,
                  name: 'Füllgewicht',
                  einheit: 'g',
                  wert: '120',
                  grenze: Grenze(hartMin: 10, hartMax: 500, weichMax: 200),
                ),
                PaketFeld(
                  schluessel: 's:programm',
                  art: FeldArt.steckbrief,
                  name: 'Programm',
                ),
                PaketFeld(
                  schluessel: 'n',
                  art: FeldArt.notiz,
                  name: 'Maschineneinstellungen (Notiz)',
                  wert: 'Band langsam anfahren, nach dem Darmwechsel die '
                      'ersten Würste aussortieren.',
                ),
              ],
            ),
            PaketSchritt(
              id: 's2',
              nummer: 2,
              abteilung: 'bratstrasse',
              abteilungName: 'Bratstraße',
              abteilungFarbe: 0xFF6A1B9A,
              anlage: 'Bratstraße Test',
              felder: [
                for (final reihe in const ['Oben', 'Unten'])
                  for (var i = 1; i <= 10; i++)
                    PaketFeld(
                      schluessel: 't:Platte $reihe $i',
                      art: FeldArt.platte,
                      name: 'Platte $reihe $i',
                      einheit: '°C',
                      wert: i.isEven ? '180' : null,
                    ),
                const PaketFeld(
                  schluessel: 'n',
                  art: FeldArt.notiz,
                  name: 'Maschineneinstellungen (Notiz)',
                ),
              ],
            ),
          ],
        ),
        const PaketArtikel(
          id: 'a2',
          nummer: '4712',
          name: 'Kochschinken',
          schritte: [
            PaketSchritt(
              id: 's3',
              nummer: 1,
              abteilung: 'wurstkueche',
              abteilungName: 'Wurstküche',
              anlage: 'Ohne Anlage',
            ),
          ],
        ),
      ],
    );
