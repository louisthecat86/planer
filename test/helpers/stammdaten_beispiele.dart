// Erfundene Stammdaten für die Tests der Ausdrucke von Artikelliste,
// Maschinen-Katalog und Maschinen-Grenzen — keine echten Artikel, Anlagen
// oder Werte.
import 'package:produktion_planer/core/constants/abteilungen.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/features/articles/artikel_luecken.dart';
import 'package:produktion_planer/features/articles/artikelliste_druck.dart';
import 'package:produktion_planer/features/settings/maschinen_druck_daten.dart';

final DateTime _stand = DateTime(2026, 10, 30, 9);

ArtikellisteEintrag _e(
  String nummer,
  String bezeichnung, {
  String gruppe = '',
  String planungsgruppe = '',
  List<Abteilung> abteilungen = const [],
  int schritte = 0,
  List<String> anlagen = const [],
  Set<ArtikelLuecke> luecken = const {},
}) =>
    ArtikellisteEintrag(
      id: 'p-$nummer',
      nummer: nummer,
      bezeichnung: bezeichnung,
      produktgruppe: gruppe,
      planungsgruppe: planungsgruppe,
      abteilungen: abteilungen,
      schritte: schritte,
      anlagen: anlagen,
      luecken: luecken,
    );

const Abteilung _z = Abteilung.zerlegung;
const Abteilung _b = Abteilung.bratstrasse;
const Abteilung _k = Abteilung.kutterabteilung;
const Abteilung _v = Abteilung.verpackung;

/// Alle Beispielartikel, nach Bezeichnung — wie die Liste sie zeigt.
List<ArtikellisteEintrag> bspArtikel() => [
      _e(
        '7101',
        'Schweineschulter zerlegt',
        planungsgruppe: 'Zerlegeware',
        abteilungen: [_z],
        schritte: 1,
        anlagen: ['Würfelanlage Süd'],
        luecken: {ArtikelLuecke.ohneProduktgruppe},
      ),
      _e(
        '7102',
        'Rinderkeule zerlegt',
        gruppe: 'Braten',
        abteilungen: [_z],
        schritte: 2,
        anlagen: ['Würfelanlage Süd'],
      ),
      _e(
        '7201',
        'Gartenwurst gebraten',
        gruppe: 'Angebratene Brühwürste',
        abteilungen: [_b, _v],
        schritte: 3,
        anlagen: ['Bratlinie Nord', 'Packanlage A'],
      ),
      _e(
        '7202',
        'Frikadellen klein',
        gruppe: 'Bratstraßenartikel Natur',
        abteilungen: [_b, _v],
        schritte: 2,
        anlagen: ['Bratlinie Nord'],
      ),
      _e(
        '7203',
        'Hackbällchen',
        gruppe: 'Bratstraßenartikel Natur',
        abteilungen: [_b],
        schritte: 2,
        anlagen: ['Formautomat Ost', 'Bratlinie Nord'],
      ),
      _e(
        '7204',
        'Bratwurst mild',
        gruppe: 'Angebratene Brühwürste',
        abteilungen: [_b],
        schritte: 1,
        anlagen: ['Bratlinie Nord'],
        luecken: {ArtikelLuecke.ohneAusbeute, ArtikelLuecke.zeitPlatzhalter},
      ),
      _e(
        '7301',
        'Gartenwurst 6er Schale',
        gruppe: 'Brühwurst',
        abteilungen: [_v],
        schritte: 1,
        anlagen: ['Packanlage A'],
      ),
      _e(
        '7302',
        'Frikadellen Beutel',
        gruppe: 'Bratstraßenartikel Natur',
        abteilungen: [_v],
        schritte: 1,
        anlagen: ['Packanlage B'],
      ),
      _e(
        '7501',
        'Leberkäse fein',
        luecken: {
          ArtikelLuecke.nichtEingepflegt,
          ArtikelLuecke.ohneProduktgruppe,
          ArtikelLuecke.ohneSchritte,
          ArtikelLuecke.ohneAusbeute,
        },
      ),
      _e(
        '7502',
        'Kochschinken Würfel',
        gruppe: 'Kochpökelware',
        luecken: {ArtikelLuecke.ohneSchritte, ArtikelLuecke.ohneAusbeute},
      ),
      _e(
        '999',
        'Grillbrät grob',
        gruppe: 'Hackprodukte roh',
        abteilungen: [_k, _b],
        schritte: 2,
        luecken: {ArtikelLuecke.zeitPlatzhalter},
      ),
    ]..sort(
        (a, b) =>
            a.bezeichnung.toLowerCase().compareTo(b.bezeichnung.toLowerCase()),
      );

/// Die Artikelliste — ohne Filter, oder gefiltert nach „Ohne Ausbeute".
ArtikellisteDaten bspArtikelliste({bool gefiltert = false}) {
  final alle = bspArtikel();
  return ArtikellisteDaten(
    alle: alle,
    liste: gefiltert
        ? [
            for (final a in alle)
              if (a.luecken.contains(ArtikelLuecke.ohneAusbeute)) a.id,
          ]
        : null,
    filterText: gefiltert ? 'Ohne Ausbeute' : '',
    sortierText: 'nach Bezeichnung',
  );
}

Machine _m(
  String id,
  String name,
  Abteilung abteilung, {
  double? planung,
  String? eignung,
  String? typisch,
}) =>
    Machine(
      id: id,
      name: name,
      abteilung: abteilung.dbValue,
      typischeParameter: typisch,
      istPlanungsressource: planung != null,
      kapazitaetMinutenProTag: planung ?? 600,
      eignungHinweis: eignung,
      createdAt: _stand,
      updatedAt: _stand,
    );

MachineParameterDef _p(String maschine, int i, String name, String? einheit) =>
    MachineParameterDef(
      id: '$maschine-p$i',
      maschineId: maschine,
      parameterName: name,
      einheit: einheit,
      sortierung: i,
      createdAt: _stand,
      updatedAt: _stand,
    );

ParameterGrenzenData _g(
  String kontext,
  String parameter, {
  double? hartMin,
  double? hartMax,
  double? weichMin,
  double? weichMax,
  String? notiz,
}) =>
    ParameterGrenzenData(
      id: 'g-$kontext-$parameter',
      kontext: kontext,
      parameterName: parameter,
      hartMin: hartMin,
      hartMax: hartMax,
      weichMin: weichMin,
      weichMax: weichMax,
      notizen: notiz,
      createdAt: _stand,
      updatedAt: _stand,
    );

/// Der Beispiel-Maschinenpark: zwei Anlagen der Zerlegung, zwei der
/// Bratstraße, zwei der Verpackung — mit Steckbriefen, Grenzen (auch einer
/// Parametergruppe) und den Artikeln, die sie nutzen.
MaschinenDruckDaten bspMaschinen() => MaschinenDruckDaten(
      maschinen: [
        _m('m-saege', 'Bandsäge West', _z, eignung: 'nur Knochenware'),
        _m('m-brat', 'Bratlinie Nord', _b, planung: 480),
        _m(
          'm-form',
          'Formautomat Ost',
          _b,
          eignung: 'Ausweichanlage für Bällchen',
          typisch: 'Form, Taktung, Messergröße',
        ),
        _m('m-pa', 'Packanlage A', _v, planung: 480),
        _m('m-pb', 'Packanlage B', _v, planung: 360, eignung: 'nur Beutel'),
        _m('m-wuerfel', 'Würfelanlage Süd', _z),
      ],
      steckbriefe: {
        'm-brat': [
          _p('m-brat', 0, 'Plattentemperatur oben', '°C'),
          _p('m-brat', 1, 'Plattentemperatur unten', '°C'),
          _p('m-brat', 2, 'Bandzeit', 'Min Sek.'),
          _p('m-brat', 3, 'Höhe', 'mm'),
        ],
        'm-form': [
          _p('m-form', 0, 'Taktung', 'Takte/min'),
          _p('m-form', 1, 'Form', 'Bällchen/ Sticks'),
        ],
        'm-pa': [
          _p('m-pa', 0, 'Programm', 'Gas/ Vakuum'),
          _p('m-pa', 1, 'Gasschaltpunkt', 'mbar'),
          _p('m-pa', 2, 'Siegelzeit', 's'),
        ],
        'm-pb': [_p('m-pb', 0, 'Programm', 'Gas/ Vakuum')],
        'm-wuerfel': [
          _p('m-wuerfel', 0, 'Gatter', 'mm'),
          _p('m-wuerfel', 1, 'Vorschub', 'mm'),
        ],
      },
      grenzen: [
        _g(
          'Bratlinie Nord',
          'Plattentemperatur oben',
          hartMin: 0,
          hartMax: 260,
          weichMin: 150,
          weichMax: 230,
          notiz: 'Herstellerangabe Typenschild',
        ),
        _g('Bratlinie Nord', 'Höhe', hartMin: 5, hartMax: 60),
        _g('Bratlinie Nord', 'Kerntemperatur', weichMin: 72.5),
        _g('Packanlage A', 'Gasschaltpunkt', weichMin: 400, weichMax: 700),
        _g('Packanlage A', 'Siegelzeit', hartMax: 5),
        _g(
          'BRATSTRASSE',
          'Platte Oben 1',
          hartMin: 0,
          hartMax: 260,
          weichMin: 160,
          weichMax: 220,
        ),
        _g('BRATSTRASSE', 'Platte Unten 1', hartMin: 0, hartMax: 260),
      ],
      artikel: {
        'm-wuerfel': [
          (nummer: '7101', bezeichnung: 'Schweineschulter zerlegt'),
          (nummer: '7102', bezeichnung: 'Rinderkeule zerlegt'),
        ],
        'm-brat': [
          (nummer: '7201', bezeichnung: 'Gartenwurst gebraten'),
          (nummer: '7202', bezeichnung: 'Frikadellen klein'),
          (nummer: '7203', bezeichnung: 'Hackbällchen'),
          (nummer: '7204', bezeichnung: 'Bratwurst mild'),
        ],
        'm-form': [(nummer: '7203', bezeichnung: 'Hackbällchen')],
        'm-pa': [
          (nummer: '7201', bezeichnung: 'Gartenwurst gebraten'),
          (nummer: '7301', bezeichnung: 'Gartenwurst 6er Schale'),
        ],
        'm-pb': [(nummer: '7302', bezeichnung: 'Frikadellen Beutel')],
      },
    );
