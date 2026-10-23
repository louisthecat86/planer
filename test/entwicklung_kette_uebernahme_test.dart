import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/constants/parameter_namen.dart';
import 'package:produktion_planer/features/entwicklung/freigabe/kette_uebernahme.dart';
import 'package:produktion_planer/features/entwicklung/haccp/prozess_kette.dart';
import 'package:produktion_planer/features/entwicklung/haccp/prozess_modell.dart';

/// Tests für die Übernahme der Prozesskette eines Projekts in einen
/// Artikel bei der Freigabe — die Zuordnung der Schritte, die Kette danach,
/// die Vorschau und was mit den Werten geschieht. Anlagen und Werte sind
/// erfunden.
void main() {
  ProzessWert wert(
    String name,
    String w, {
    String gruppe = kMaschinenNotizGruppe,
    bool eigen = false,
  }) => ProzessWert(name: name, wert: w, gruppe: gruppe, eigen: eigen);

  // Der Artikel: Kutter, Bratstraße, Kartonieren.
  const kutter = ProzessSchritt(
    id: 'a-kutter',
    abteilung: 'kutterabteilung',
    maschineId: 'm-kutter',
    maschine: 'Testkutter',
    werte: [
      ProzessWert(
        name: 'Drehzahl',
        wert: '3000',
        gruppe: kMaschinenNotizGruppe,
      ),
    ],
  );
  const brat = ProzessSchritt(
    id: 'a-brat',
    abteilung: 'bratstrasse',
    maschineId: 'm-brat',
    maschine: 'Bratstraße Test',
    werte: [ProzessWert(name: 'Kerntemperatur', wert: '72', gruppe: 'BRATEN')],
  );
  const karton = ProzessSchritt(
    id: 'a-karton',
    abteilung: 'verpackung',
    prozessschritt: 'Kartonieren',
  );
  const artikel = [kutter, brat, karton];

  group('Zuordnung der Schritte', () {
    test('dieselbe Anlage — ohne Anlage aus dem Katalog derselbe Name', () {
      final projekt = [
        const ProzessSchritt(
          id: 'p1',
          abteilung: 'kutterabteilung',
          maschineId: 'm-kutter',
          maschine: 'Testkutter',
        ),
        // Nur der Name, anders geschrieben.
        const ProzessSchritt(
          id: 'p2',
          abteilung: 'bratstrasse',
          maschine: ' bratstraße test',
        ),
        const ProzessSchritt(
          id: 'p3',
          abteilung: 'verpackung',
          prozessschritt: 'Etikettieren',
        ),
      ];
      expect(schritteZuordnen(artikel, projekt), ['a-kutter', 'a-brat', null]);
      // Eine andere Anlage gleichen Namens zählt nicht.
      expect(
        schritteEntsprechen(
          kutter,
          const ProzessSchritt(
            id: 'x',
            maschineId: 'm-anderer',
            maschine: 'Testkutter',
          ),
        ),
        isFalse,
      );
      // Ohne Namen entspricht nichts.
      expect(
        schritteEntsprechen(
          const ProzessSchritt(id: 'a'),
          const ProzessSchritt(id: 'b'),
        ),
        isFalse,
      );
    });

    test('jeder Schritt des Artikels einmal — zuerst derselben Abteilung', () {
      const wolf1 = ProzessSchritt(
        id: 'a-wolf-z',
        abteilung: 'zerlegung',
        maschineId: 'm-wolf',
        maschine: 'Testwolf',
      );
      const wolf2 = ProzessSchritt(
        id: 'a-wolf-wk',
        abteilung: 'wurstkueche',
        maschineId: 'm-wolf',
        maschine: 'Testwolf',
      );
      ProzessSchritt p(String id, String abteilung) => ProzessSchritt(
        id: id,
        abteilung: abteilung,
        maschineId: 'm-wolf',
        maschine: 'Testwolf',
      );
      expect(
        schritteZuordnen(
          [wolf1, wolf2],
          [p('p1', 'wurstkueche'), p('p2', 'zerlegung'), p('p3', 'zerlegung')],
        ),
        ['a-wolf-wk', 'a-wolf-z', null],
      );
    });
  });

  group('Die Kette danach', () {
    final projekt = [
      const ProzessSchritt(
        id: 'p-brat',
        abteilung: 'bratstrasse',
        maschine: 'Bratstraße Test',
        werte: [
          ProzessWert(
            name: 'Kerntemperatur',
            wert: '75',
            gruppe: kMaschinenNotizGruppe,
          ),
        ],
      ),
      const ProzessSchritt(
        id: 'p-kutter',
        abteilung: 'kutterabteilung',
        maschineId: 'm-kutter',
        maschine: 'Testkutter',
      ),
      const ProzessSchritt(
        id: 'p-etikett',
        abteilung: 'verpackung',
        prozessschritt: 'Etikettieren',
      ),
    ];

    test('mit Entfernen: genau die Kette des Projekts', () {
      final ziel = zielKette(artikel, projekt, entfernen: true);
      expect([for (final z in ziel) z.artikelId], ['a-brat', 'a-kutter', null]);
      final b = ziel.first.schritt;
      // Der Wert steht unter der Gruppe, unter der der Artikel ihn führt —
      // und die Anlage aus dem Katalog bleibt.
      expect(b.werte.single.gruppe, 'BRATEN');
      expect(b.werte.single.wert, '75');
      expect(b.maschineId, 'm-brat');
      // Was das Projekt nicht hat, fällt weg.
      expect(ziel[1].schritt.werte, isEmpty);
    });

    test('ohne Entfernen bleiben Schritte und Werte des Artikels', () {
      const abkuehlen = ProzessSchritt(
        id: 'p-abkuehlen',
        abteilung: 'bratstrasse',
        prozessschritt: 'Abkühlen',
      );
      final ziel = zielKette(
        artikel,
        [projekt.first, abkuehlen],
        entfernen: false,
      );
      // Der Kutter bleibt vorn, das Kartonieren hinter der Bratstraße —
      // und hinter dem Abkühlen, das das Projekt dort einfügt.
      expect(
        [for (final z in ziel) z.artikelId ?? z.schritt.id],
        ['a-kutter', 'a-brat', 'p-abkuehlen', 'a-karton'],
      );
      // Ein Wert, den nur der Artikel hat, bleibt an seinem Schritt.
      final k = zielKette(
        artikel,
        projekt,
        entfernen: false,
      ).firstWhere((z) => z.artikelId == 'a-kutter');
      expect(
        [for (final w in k.schritt.werte) '${w.name}=${w.wert}'],
        ['Drehzahl=3000'],
      );
    });

    test('die Vorschau zählt, was bleibt, neu kommt und entfallen kann', () {
      final v = uebernahmeVorschau(artikel, projekt, entfernen: true);
      expect((v.bleiben, v.neu), (2, 1));
      expect([for (final s in v.nurImArtikel) s.id], ['a-karton']);
      // Die Drehzahl am Kutter.
      expect(v.werteNurImArtikel, 1);
      expect(v.etwasEntfaellt, isTrue);
      expect(
        [for (final s in v.nachher.schritte) s.id],
        ['a-brat', 'a-kutter', '\u0000neu2'],
      );
      String text(ParameterAenderung a) =>
          '${a.abschnitt}|${a.feld}|${a.alt}|${a.neu}';
      final aenderungen = [for (final a in v.aenderungen) text(a)];
      expect(aenderungen, contains('Bratstraße Test|Kerntemperatur|72|75'));
      expect(aenderungen, contains('Testkutter|Drehzahl|3000|null'));
      expect(
        aenderungen,
        contains('Etikettieren|In der Kette|null|Schritt 3 · Verpackung'),
      );
      expect(
        aenderungen,
        contains('Kartonieren|In der Kette|Schritt 3 · Verpackung|null'),
      );
      expect(v.aenderungen.where((a) => a.feld == 'Reihenfolge'), hasLength(1));

      // Ohne Entfernen: nur, was sich ändert oder dazukommt.
      final ohne = uebernahmeVorschau(artikel, projekt, entfernen: false);
      expect(ohne.etwasEntfaellt, isTrue);
      expect([for (final a in ohne.aenderungen) a.neu], isNot(contains(null)));

      // Dieselbe Kette: nichts zu ändern, nichts entfällt.
      final gleich = uebernahmeVorschau(artikel, artikel, entfernen: true);
      expect(gleich.aenderungen, isEmpty);
      expect(gleich.etwasEntfaellt, isFalse);
      expect((gleich.bleiben, gleich.neu), (3, 0));
    });

    test('Stationen ohne Abteilung werden genannt', () {
      expect(stationenOhneAbteilung(artikel), isEmpty);
      expect(
        stationenOhneAbteilung([
          kutter,
          const ProzessSchritt(id: 'x', maschine: 'Testwaage'),
          karton,
          const ProzessSchritt(id: 'y', abteilung: 'unbekannt'),
        ]),
        [2, 4],
      );
    });
  });

  group('Werte eines Schritts', () {
    ArtikelWert zeile(
      String id,
      String gruppe,
      String name,
      String? w, {
      bool eigen = false,
      int reihenfolge = 0,
    }) => (
      id: id,
      gruppe: gruppe,
      name: name,
      wert: w,
      eigen: eigen,
      reihenfolge: reihenfolge,
    );

    final vorhanden = [
      zeile('w-kern', 'BRATEN', 'Kerntemperatur', '72', reihenfolge: 1),
      zeile(
        'w-band',
        kMaschinenNotizGruppe,
        'Bandgeschwindigkeit',
        '4',
        reihenfolge: 2,
      ),
      zeile(
        'w-eigen',
        kEigeneWerteGruppe,
        'Schichtnotiz',
        'früh',
        eigen: true,
        reihenfolge: 3,
      ),
      // Eine leere Zeile der Excel-Vorlage.
      zeile(
        'w-oel',
        kMaschinenNotizGruppe,
        'Öltemperatur',
        null,
        reihenfolge: 4,
      ),
      zeile(
        'w-notiz',
        kMaschinenNotizGruppe,
        kMaschinenNotizParam,
        'alt',
        reihenfolge: 5,
      ),
    ];
    final soll = ProzessSchritt(
      id: 's',
      abteilung: 'bratstrasse',
      maschine: 'Testofen',
      werte: [
        wert('Kerntemperatur', '75'),
        wert('Garzeit', '12'),
        wert('Prüfer', 'QS', gruppe: kEigeneWerteGruppe, eigen: true),
      ],
    );

    String text(WertAktion a) => switch (a) {
      WertSetzen(:final id, :final wert) => 'setzen $id=$wert',
      WertAnlegen() =>
        'anlegen ${a.gruppe}/${a.name}=${a.wert}'
            '${a.eigen ? ' eigen' : ''} #${a.reihenfolge}',
      WertLoeschen(:final id) => 'löschen $id',
    };

    test('vorhandene ändern sich an ihrer Stelle, fehlende kommen dazu', () {
      expect(
        [
          for (final a in werteAbgleichen(vorhanden, soll, entfernen: false))
            text(a),
        ],
        [
          'setzen w-kern=75',
          'anlegen $kMaschinenNotizGruppe/Garzeit=12 #6',
          'anlegen $kEigeneWerteGruppe/Prüfer=QS eigen #7',
        ],
      );
    });

    test(
      'mit Entfernen: eigene fallen weg, Zeilen der Vorlage bleiben leer',
      () {
        expect(
          [
            for (final a in werteAbgleichen(vorhanden, soll, entfernen: true))
              text(a),
          ],
          [
            'setzen w-kern=75',
            'anlegen $kMaschinenNotizGruppe/Garzeit=12 #6',
            'anlegen $kEigeneWerteGruppe/Prüfer=QS eigen #7',
            'setzen w-band=null',
            'löschen w-eigen',
            'setzen w-notiz=null',
          ],
        );
      },
    );

    test('Maschineneinstellungen und Platten mit ihrem Raster', () {
      final mitPlatten = ProzessSchritt(
        id: 's',
        abteilung: 'bratstrasse',
        maschine: 'Bratstraße Test',
        notiz: 'Band mittig',
        werte: [
          wert('Platte Oben 1', '180', gruppe: kPlattenGruppeBrat),
          wert('Platte Unten 1', '', gruppe: kPlattenGruppeBrat),
        ],
      );
      expect(
        [
          for (final a in werteAbgleichen(
            [vorhanden.last],
            mitPlatten,
            entfernen: true,
          ))
            text(a),
        ],
        [
          'setzen w-notiz=Band mittig',
          'anlegen $kPlattenGruppeBrat/Platte Oben 1=180 #6',
          'anlegen $kPlattenGruppeBrat/$kPlattenSchemaParam=bratstrasse #0',
        ],
      );
      // Steht das Raster schon am Schritt, bleibt es, wie es ist.
      expect(
        [
          for (final a in werteAbgleichen(
            [
              zeile(
                'w-raster',
                kPlattenGruppeBrat,
                kPlattenSchemaParam,
                'bratstrasse',
              ),
              zeile('w-p1', kPlattenGruppeBrat, 'Platte Oben 1', '170'),
            ],
            mitPlatten,
            entfernen: true,
          ))
            text(a),
        ],
        [
          'anlegen $kMaschinenNotizGruppe/$kMaschinenNotizParam=Band mittig #1',
          'setzen w-p1=180',
        ],
      );
    });
  });
}
