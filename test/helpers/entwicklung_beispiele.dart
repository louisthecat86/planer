// Erfundene Zutaten und Rezepturen für die Tests der Ausdrucke der
// Produktentwicklung — keine echten Rezepturen, Kunden oder Artikel.
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/features/entwicklung/daten/entwicklung_repository.dart'
    show VersionStatus;
import 'package:produktion_planer/features/entwicklung/rechenkern/rechen_modell.dart';

final DateTime beispielZeit = DateTime(2026, 10, 12, 9, 30);

const RechenZutat bspSchwein = RechenZutat(
  id: 'z-schwein',
  name: 'Schweinefleisch S III',
  istFleisch: true,
  tierart: Tierart.schwein,
  bindegewebe: 18,
  quidPflicht: true,
  naehrwerte: Naehrwerte(
    fett: 22,
    gesaettigteFettsaeuren: 8.5,
    kohlenhydrate: 0,
    zucker: 0,
    eiweiss: 17,
    salz: 0.1,
    wasser: 60,
    beffe: 14.5,
  ),
);

const RechenZutat bspRind = RechenZutat(
  id: 'z-rind',
  name: 'Rindfleisch R II',
  istFleisch: true,
  tierart: Tierart.rind,
  bindegewebe: 12,
  quidPflicht: true,
  naehrwerte: Naehrwerte(
    fett: 12,
    gesaettigteFettsaeuren: 5,
    kohlenhydrate: 0,
    zucker: 0,
    eiweiss: 19.5,
    salz: 0.1,
    wasser: 67.5,
    beffe: 17,
  ),
);

const RechenZutat bspSpeck = RechenZutat(
  id: 'z-speck',
  name: 'Rückenspeck',
  istFleisch: true,
  tierart: Tierart.schwein,
  naehrwerte: Naehrwerte(
    fett: 80,
    gesaettigteFettsaeuren: 30,
    kohlenhydrate: 0,
    zucker: 0,
    eiweiss: 4,
    salz: 0,
    wasser: 15,
    beffe: 2,
  ),
);

const RechenZutat bspEis = RechenZutat(
  id: 'z-eis',
  name: 'Scherbeneis',
  etikettName: 'Wasser',
  istWasser: true,
);

const RechenZutat bspSalz = RechenZutat(
  id: 'z-nps',
  name: 'Nitritpökelsalz',
  etikettName:
      'Nitritpökelsalz (Speisesalz, Konservierungsstoff Natriumnitrit)',
  naehrwerte: Naehrwerte(
    fett: 0,
    kohlenhydrate: 0,
    zucker: 0,
    eiweiss: 0,
    salz: 99.5,
    wasser: 0,
  ),
);

const RechenZutat bspGewuerz = RechenZutat(
  id: 'z-gewuerz',
  name: 'Würzmischung Garten',
  etikettName: 'Gewürze',
  unterzutaten: 'Senfsaat, Selleriesaat, Pfeffer',
  allergene: {'senf', 'sellerie'},
  verarbeitungshilfsstoffe: ['Trennmittel Siliciumdioxid'],
  naehrwerte: Naehrwerte(
    fett: 5,
    gesaettigteFettsaeuren: 0.5,
    kohlenhydrate: 60,
    zucker: 30,
    eiweiss: 10,
    salz: 2,
    wasser: 8,
  ),
);

const RechenZutat bspZwiebeln = RechenZutat(
  id: 'z-zwiebel',
  name: 'Zwiebeln, frisch',
  etikettName: 'Zwiebeln',
  naehrwerte: Naehrwerte(
    fett: 0.2,
    gesaettigteFettsaeuren: 0,
    kohlenhydrate: 7,
    zucker: 5,
    eiweiss: 1.2,
    salz: 0,
    wasser: 89,
  ),
);

const RechenZutat bspMilch = RechenZutat(
  id: 'z-milch',
  name: 'Magermilchpulver',
  allergene: {'milch'},
  naehrwerte: Naehrwerte(
    fett: 1,
    gesaettigteFettsaeuren: 0.6,
    kohlenhydrate: 52,
    zucker: 52,
    eiweiss: 35,
    salz: 1.3,
    wasser: 4,
  ),
);

/// Ohne Nährwerte — die Berechnung weist darauf hin.
const RechenZutat bspKraeuter = RechenZutat(
  id: 'z-kraeuter',
  name: 'Petersilie, gehackt',
  etikettName: 'Petersilie',
);

const RechenZutat bspOel = RechenZutat(
  id: 'z-oel',
  name: 'Rapsöl',
  naehrwerte: Naehrwerte(
    fett: 100,
    gesaettigteFettsaeuren: 7,
    kohlenhydrate: 0,
    zucker: 0,
    eiweiss: 0,
    salz: 0,
    wasser: 0,
  ),
);

RechenPosition bspZeile(RechenZutat z, double kg) =>
    RechenPosition.zutat(z, mengeKg: kg);

/// Eine Kräuterpaste — steckt im Kräuterbrät.
RechenRezeptur bspKraeuterpaste() => RechenRezeptur(
      id: 'r-paste',
      name: 'Kräuterpaste',
      verlustart: Verlustart.keiner,
      positionen: [
        bspZeile(bspKraeuter, 6),
        bspZeile(bspOel, 4),
      ],
    );

/// Ein Brät mit Kräutern — mit eigener Unterrezeptur und 5 % Verlust.
RechenRezeptur bspKraeuterbraet() => RechenRezeptur(
      id: 'r-braet',
      name: 'Kräuterbrät',
      verlustProzent: 5,
      positionen: [
        bspZeile(bspSchwein, 60),
        bspZeile(bspEis, 25),
        bspZeile(bspSalz, 1.8),
        RechenPosition.unterrezeptur(bspKraeuterpaste(), mengeKg: 13.2),
      ],
    );

/// Eine Gartenwurst — Stand [stand] von 1 bis 3: 2 mit weniger Salz und
/// mehr Speck, 3 mit Milchpulver und ohne Zwiebeln.
RechenRezeptur bspGartenwurst({int stand = 2, bool mitBraet = true}) =>
    RechenRezeptur(
      id: 'r-garten',
      name: 'Gartenwurst',
      verlustProzent: stand == 1 ? 12 : 10,
      positionen: [
        bspZeile(bspSchwein, 40),
        bspZeile(bspRind, 20),
        bspZeile(bspSpeck, stand == 1 ? 12 : 15),
        bspZeile(bspEis, 15),
        bspZeile(bspSalz, stand == 1 ? 2 : 1.8),
        bspZeile(bspGewuerz, 0.8),
        if (stand < 3) bspZeile(bspZwiebeln, 3),
        if (stand == 3) bspZeile(bspMilch, 1.5),
        if (mitBraet)
          RechenPosition.unterrezeptur(bspKraeuterbraet(), mengeKg: 8),
      ],
    );

/// Ein Stand der Gartenwurst, wie er in der Datenbank steht.
RezepturVersion bspVersion({
  int nummer = 2,
  bool abgeschlossen = true,
  String? bezeichnung,
  String? notiz,
}) {
  final eingabe = bspGartenwurst(stand: nummer);
  return RezepturVersion(
    id: 'v$nummer',
    rezepturId: 'r-garten',
    nummer: nummer,
    bezeichnung: bezeichnung,
    status: abgeschlossen ? VersionStatus.abgeschlossen : VersionStatus.entwurf,
    verlustProzent: eingabe.verlustProzent,
    fettVerlustProzent: 0,
    verlustArt: eingabe.verlustart.schluessel,
    notiz: notiz,
    abgeschlossenAm:
        abgeschlossen ? beispielZeit.add(Duration(days: nummer)) : null,
    createdAt: beispielZeit,
    updatedAt: beispielZeit.add(Duration(days: nummer, hours: 2)),
  );
}

/// Eine Rezeptur mit [n] Zeilen — läuft über die Seite.
RechenRezeptur bspLangeRezeptur(int n) => RechenRezeptur(
      id: 'r-lang',
      name: 'Lange Rezeptur',
      positionen: [
        for (var i = 1; i <= n; i++)
          bspZeile(
            RechenZutat(
              id: 'z-lang-$i',
              name: 'Zutat Nummer $i mit einem recht langen Namen, damit '
                  'die Zeile ganz sicher nicht in eine Spalte passt',
              allergene: i.isEven ? const {'gluten', 'eier'} : const {},
              naehrwerte: const Naehrwerte(
                fett: 10,
                gesaettigteFettsaeuren: 3,
                kohlenhydrate: 5,
                zucker: 1,
                eiweiss: 15,
                salz: 1,
                wasser: 68,
              ),
            ),
            1 + i / 10,
          ),
      ],
    );

/// [r] als Zeile des Zutatenkatalogs.
Zutat bspKatalogZutat(RechenZutat r, {String? artikelnummer}) {
  final n = r.naehrwerte;
  return Zutat(
    id: r.id,
    name: r.name,
    artikelnummer: artikelnummer,
    etikettName: r.etikettName,
    istFleisch: r.istFleisch,
    istWasser: r.istWasser,
    tierart: r.tierart?.schluessel,
    bindegewebe: r.bindegewebe,
    quidPflicht: r.quidPflicht,
    unterzutaten: r.unterzutaten,
    verarbeitungshilfsstoffe: r.verarbeitungshilfsstoffe.isEmpty
        ? null
        : r.verarbeitungshilfsstoffe.join(', '),
    allergene: r.allergene.isEmpty ? null : r.allergene.join(','),
    energieKcal: n.fett == null
        ? null
        : (n.fett ?? 0) * 9 + (n.eiweiss ?? 0) * 4 + (n.kohlenhydrate ?? 0) * 4,
    fett: n.fett,
    gesaettigteFettsaeuren: n.gesaettigteFettsaeuren,
    kohlenhydrate: n.kohlenhydrate,
    zucker: n.zucker,
    eiweiss: n.eiweiss,
    salz: n.salz,
    wasser: n.wasser,
    beffe: n.beffe,
    createdAt: beispielZeit,
    updatedAt: beispielZeit,
  );
}

/// Der erfundene Zutatenkatalog.
List<Zutat> bspKatalog() => [
      bspKatalogZutat(bspSchwein, artikelnummer: '9101'),
      bspKatalogZutat(bspRind, artikelnummer: '9102'),
      bspKatalogZutat(bspSpeck, artikelnummer: '9103'),
      bspKatalogZutat(bspEis),
      bspKatalogZutat(bspSalz, artikelnummer: '9201'),
      bspKatalogZutat(bspGewuerz, artikelnummer: '9301'),
      bspKatalogZutat(bspZwiebeln, artikelnummer: '9401'),
      bspKatalogZutat(bspMilch, artikelnummer: '9501'),
      bspKatalogZutat(bspKraeuter),
      bspKatalogZutat(bspOel, artikelnummer: '9601'),
      bspKatalogZutat(
        const RechenZutat(
          id: 'z-wild',
          name: 'Wildfleisch gemischt',
          istFleisch: true,
        ),
      ),
    ];

/// Ein erfundenes Projekt.
EntwicklungsProjekt bspProjekt(
  String id,
  String name, {
  String status = 'entwicklung',
  String? kunde,
  String? artikelnummer,
  String? produktidee,
  String? gesamtprojektId,
  int tage = 0,
}) =>
    EntwicklungsProjekt(
      id: id,
      name: name,
      kunde: kunde,
      artikelnummer: artikelnummer,
      status: status,
      produktidee: produktidee,
      neuerProzess: false,
      neueZutaten: false,
      gesamtprojektId: gesamtprojektId,
      createdAt: beispielZeit.add(Duration(days: tage)),
      updatedAt: beispielZeit.add(Duration(days: tage, hours: 3)),
    );

/// Erfundene Projekte — eins für sich in jedem Status, dazu ein
/// Gesamtprojekt mit drei Mustern.
List<EntwicklungsProjekt> bspProjekte() => [
      bspProjekt(
        'p1',
        'Gartenwurst fein',
        kunde: 'Kantine Nord',
        artikelnummer: '40711',
        produktidee: 'Feine Brühwurst mit Kräutern für die Kantine.',
        tage: 9,
      ),
      bspProjekt(
        'p2',
        'Bratwurst mild',
        status: 'validierung',
        kunde: 'Hofladen Sonnenhang',
        artikelnummer: '40712',
        tage: 7,
      ),
      bspProjekt(
        'p3',
        'Leberkäse grob',
        status: 'produktion',
        kunde: 'Kantine Nord',
        artikelnummer: '40713',
        tage: 3,
      ),
      bspProjekt('p4', 'Fleischkäse vegetarisch', status: 'eingestellt'),
      bspProjekt('p5', 'Sülze klassisch', status: 'archiviert', tage: 1),
      bspProjekt(
        'm1',
        'Muster Kräuter',
        gesamtprojektId: 'g1',
        tage: 4,
      ),
      bspProjekt(
        'm2',
        'Muster Chili',
        status: 'eingestellt',
        gesamtprojektId: 'g1',
        tage: 5,
      ),
      bspProjekt(
        'm3',
        'Muster Knoblauch',
        status: 'validierung',
        gesamtprojektId: 'g1',
        tage: 6,
      ),
    ];

/// Ein erfundenes Gesamtprojekt — die Muster in [bspProjekte].
List<Gesamtprojekt> bspGesamtprojekte() => [
      Gesamtprojekt(
        id: 'g1',
        name: 'Grillsaison',
        kunde: 'Beispiel-Feinkost',
        createdAt: beispielZeit,
        updatedAt: beispielZeit.add(const Duration(days: 2)),
      ),
    ];
