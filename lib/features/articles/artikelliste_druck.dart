import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/constants/abteilungen.dart';
import '../../core/constants/product_groups.dart';
import '../../core/database/database.dart' show Product, ProductStep;
import '../../core/druck/druck_bausteine.dart';
import '../../core/druck/druck_optionen.dart';
import '../../core/druck/druck_satz.dart';
import 'artikel_luecken.dart';

// Die Artikel-Stammdaten auf Papier — wie die Liste auf dem Schirm: je
// Artikel Nummer, Bezeichnung, Gruppe, die Abteilungen des Prozesses und
// die Zahl der Schritte, dazu die Anlagen mit Namen und was der Planung
// fehlt. Wie die Liste gefiltert oder alle, nach Nummer, je Produktgruppe
// oder je Abteilung.

/// Ein Artikel, wie ihn die Liste zeigt.
class ArtikellisteEintrag {
  const ArtikellisteEintrag({
    required this.id,
    required this.nummer,
    required this.bezeichnung,
    this.produktgruppe = '',
    this.planungsgruppe = '',
    this.abteilungen = const [],
    this.schritte = 0,
    this.anlagen = const [],
    this.luecken = const {},
  });

  final String id;
  final String nummer;
  final String bezeichnung;

  /// Die Produktgruppe als Klartext — leer: keine.
  final String produktgruppe;

  /// Die frühere Freitext-Gruppe — steht da, wo keine Produktgruppe ist.
  final String planungsgruppe;

  /// Die Abteilungen des Prozesses, jede einmal, in Prozessreihenfolge.
  final List<Abteilung> abteilungen;

  /// Die Zahl der Prozessschritte.
  final int schritte;

  /// Die Anlagen der Schritte mit Namen, jede einmal.
  final List<String> anlagen;

  /// Was der Planung fehlt.
  final Set<ArtikelLuecke> luecken;
}

/// Die Abteilungen der [schritte], jede einmal, in der Reihenfolge ihres
/// ersten Auftretens im Prozess. Unbekannte Werte fallen weg.
List<Abteilung> prozessAbteilungen(List<ProductStep> schritte) {
  final sortiert = [...schritte]
    ..sort((a, b) => a.reihenfolge.compareTo(b.reihenfolge));
  final liste = <Abteilung>[];
  for (final s in sortiert) {
    for (final a in Abteilung.values) {
      if (a.dbValue == s.abteilung && !liste.contains(a)) liste.add(a);
    }
  }
  return liste;
}

/// Die Anlagen der [schritte]: je Maschinen-ID ihr Name aus [maschinen],
/// ohne ID der Freitext aus älteren Importen — jede einmal, in
/// Prozessreihenfolge. Eine ID, die der Katalog nicht kennt, zählt als
/// „Anlage ohne Namen".
List<String> prozessAnlagen(
  List<ProductStep> schritte,
  Map<String, String> maschinen,
) {
  final sortiert = [...schritte]
    ..sort((a, b) => a.reihenfolge.compareTo(b.reihenfolge));
  final liste = <String>[];
  for (final s in sortiert) {
    final id = s.maschineId;
    final name = id != null && id.isNotEmpty
        ? (maschinen[id] ?? s.maschine?.trim() ?? 'Anlage ohne Namen')
        : (s.maschine?.trim() ?? '');
    if (name.isNotEmpty && !liste.contains(name)) liste.add(name);
  }
  return liste;
}

/// Der Eintrag für [produkt] mit seinen (nicht gelöschten) [schritte]n und
/// [luecken]; [maschinen]: der Name je Maschinen-ID.
ArtikellisteEintrag artikellisteEintrag(
  Product produkt,
  List<ProductStep> schritte,
  Set<ArtikelLuecke> luecken,
  Map<String, String> maschinen,
) =>
    ArtikellisteEintrag(
      id: produkt.id,
      nummer: produkt.artikelnummer,
      bezeichnung: produkt.artikelbezeichnung,
      produktgruppe: produktgruppeLabel(produkt.produktgruppe).trim(),
      planungsgruppe: produkt.planungsgruppe?.trim() ?? '',
      abteilungen: prozessAbteilungen(schritte),
      schritte: schritte.length,
      anlagen: prozessAnlagen(schritte, maschinen),
      luecken: luecken,
    );

/// Was die Artikelliste zum Drucken braucht.
class ArtikellisteDaten {
  const ArtikellisteDaten({
    required this.alle,
    this.liste,
    this.filterText = '',
    this.sortierText = '',
  });

  /// Alle Artikel, sortiert wie die Liste.
  final List<ArtikellisteEintrag> alle;

  /// Die IDs der Artikel, die die Liste gerade zeigt, in ihrer
  /// Reihenfolge — null: kein Filter, die Liste zeigt alle.
  final List<String>? liste;

  /// Wonach die Liste gefiltert ist — „Ohne Ausbeute · Suche „wurst"".
  final String filterText;

  /// Wie die Liste sortiert ist — „nach Bezeichnung".
  final String sortierText;
}

/// Welche Artikel auf das Blatt kommen.
enum ArtikellisteUmfang {
  /// Was die Liste gerade zeigt.
  liste,

  /// Alle Artikel.
  alle,

  /// Nur Artikel, denen der Planung etwas fehlt.
  luecken,
}

/// Wie die Artikel geordnet sind.
enum ArtikellisteReihenfolge {
  /// Wie die Liste sortiert ist.
  liste,
  nummer,
  bezeichnung,

  /// Ein Abschnitt je Produktgruppe.
  gruppe,

  /// Ein Abschnitt je Abteilung — ein Artikel bei jeder seiner Abteilungen.
  abteilung,
}

/// Schlüssel der Wahl im Druckfenster.
abstract final class ArtikellisteWahl {
  static const umfang = 'umfang';
  static const reihenfolge = 'reihenfolge';
  static const abteilungen = 'abteilungen';
  static const kennzahlen = 'kennzahlen';
  static const anlagen = 'anlagen';
  static const luecken = 'luecken';
  static const notizen = 'notizen';
}

/// Was auf die Liste kommt — die Wahl im Druckfenster.
class ArtikellisteInhalt {
  const ArtikellisteInhalt({
    this.umfang = ArtikellisteUmfang.alle,
    this.reihenfolge = ArtikellisteReihenfolge.liste,
    this.abteilungen,
    this.kennzahlen = true,
    this.anlagen = true,
    this.luecken = true,
    this.notizen = false,
  });

  final ArtikellisteUmfang umfang;
  final ArtikellisteReihenfolge reihenfolge;

  /// Je Abteilung: nur diese (dbValues) — null: alle.
  final Set<String>? abteilungen;

  /// Wie viele Artikel vollständig sind und welche Lücke wie oft fehlt.
  final bool kennzahlen;

  /// Die Anlagen mit Namen.
  final bool anlagen;

  /// Was fehlt — unter der Bezeichnung.
  final bool luecken;

  /// Eine leere Spalte zum Schreiben.
  final bool notizen;
}

String _anzahl(int n) => n == 1 ? '1 Artikel' : '$n Artikel';

/// Artikelnummern wie Zahlen vergleichen, wenn beide Zahlen sind — sonst
/// als Text. So steht 999 vor 1000.
int _nachNummer(ArtikellisteEintrag a, ArtikellisteEintrag b) {
  final x = int.tryParse(a.nummer.trim());
  final y = int.tryParse(b.nummer.trim());
  final c = x != null && y != null
      ? x.compareTo(y)
      : a.nummer.toLowerCase().compareTo(b.nummer.toLowerCase());
  return c != 0 ? c : _nachBezeichnung(a, b);
}

int _nachBezeichnung(ArtikellisteEintrag a, ArtikellisteEintrag b) {
  final c = a.bezeichnung.toLowerCase().compareTo(b.bezeichnung.toLowerCase());
  return c != 0 ? c : a.nummer.compareTo(b.nummer);
}

String _umfangText(ArtikellisteUmfang u, ArtikellisteDaten d) => switch (u) {
      ArtikellisteUmfang.liste =>
        d.filterText.isEmpty ? 'Wie die Liste' : d.filterText,
      ArtikellisteUmfang.alle => 'Alle Artikel',
      ArtikellisteUmfang.luecken => 'Artikel mit Lücken',
    };

String _reihenfolgeText(ArtikellisteReihenfolge r, ArtikellisteDaten d) =>
    switch (r) {
      ArtikellisteReihenfolge.liste =>
        d.sortierText.isEmpty ? 'wie die Liste' : d.sortierText,
      ArtikellisteReihenfolge.nummer => 'nach Artikelnummer',
      ArtikellisteReihenfolge.bezeichnung => 'nach Bezeichnung',
      ArtikellisteReihenfolge.gruppe => 'je Produktgruppe',
      ArtikellisteReihenfolge.abteilung => 'je Abteilung',
    };

/// Die Artikelliste zum Drucken.
DruckDokument artikellisteDruck(
  ArtikellisteDaten daten, {
  ArtikellisteInhalt inhalt = const ArtikellisteInhalt(),
  DateTime? gedrucktAm,
}) {
  final gedruckt = gedrucktAm ?? DateTime.now();
  final liste = _Liste(daten, inhalt, druckGedruckt(gedruckt));
  final titel = 'Artikel ${_umfangText(inhalt.umfang, daten)}';
  return DruckDokument(
    titel: titel,
    dateiname: druckDateiname('$titel ${druckIsoDatum(gedruckt)}'),
    blaetter: [liste.blatt()],
  );
}

/// Die Artikelliste für das Druckfenster. Vorgewählt ist, was die Liste
/// zeigt — gefiltert, wenn sie gefiltert ist, sortiert wie sie.
DruckAuftrag artikellisteDruckAuftrag(
  ArtikellisteDaten daten, {
  DateTime? gedrucktAm,
}) {
  final gefiltert = daten.liste != null;
  final nListe = daten.liste?.length ?? daten.alle.length;
  final nLuecken = daten.alle.where((a) => a.luecken.isNotEmpty).length;
  final vorhanden = [
    for (final a in Abteilung.values)
      if (daten.alle.where((e) => e.abteilungen.contains(a)).length case final n
          when n > 0)
        (abteilung: a, anzahl: n),
  ];
  return DruckAuftrag(
    art: 'artikelliste',
    titel: 'Artikelliste drucken',
    untertitel: [
      if (gefiltert) _umfangText(ArtikellisteUmfang.liste, daten),
      _anzahl(nListe),
      if (daten.sortierText.isNotEmpty) daten.sortierText,
    ].join(' · '),
    optionen: [
      DruckWahlEins(
        schluessel: ArtikellisteWahl.umfang,
        titel: 'Artikel',
        werte: [
          if (gefiltert)
            DruckWert(
              'liste',
              'Wie die Liste',
              hinweis: '${_umfangText(ArtikellisteUmfang.liste, daten)} — '
                  '${_anzahl(nListe)}',
            ),
          DruckWert(
            'alle',
            'Alle Artikel',
            hinweis: _anzahl(daten.alle.length),
          ),
          DruckWert(
            'luecken',
            'Nur mit Lücken',
            hinweis: '${_anzahl(nLuecken)} — denen der Planung etwas fehlt',
          ),
        ],
        standard: gefiltert ? 'liste' : 'alle',
        merken: false,
      ),
      DruckWahlEins(
        schluessel: ArtikellisteWahl.reihenfolge,
        titel: 'Reihenfolge',
        werte: [
          DruckWert(
            'liste',
            'Wie die Liste',
            hinweis: daten.sortierText.isEmpty ? null : daten.sortierText,
          ),
          const DruckWert('nummer', 'Nach Artikelnummer'),
          const DruckWert('bezeichnung', 'Nach Bezeichnung'),
          const DruckWert(
            'gruppe',
            'Je Produktgruppe',
            hinweis: 'Ein Abschnitt je Gruppe',
          ),
          const DruckWert(
            'abteilung',
            'Je Abteilung',
            hinweis: 'Ein Artikel steht bei jeder seiner Abteilungen',
          ),
        ],
        standard: 'liste',
      ),
      if (vorhanden.length > 1)
        DruckWahlMehrere(
          schluessel: ArtikellisteWahl.abteilungen,
          titel: 'Abteilungen',
          werte: [
            for (final v in vorhanden)
              DruckWert(
                v.abteilung.dbValue,
                v.abteilung.anzeigeName,
                hinweis: _anzahl(v.anzahl),
                farbe: v.abteilung.farbwert,
                kuerzel: v.abteilung.kurzcode,
              ),
          ],
          standard: {for (final v in vorhanden) v.abteilung.dbValue},
          merken: false,
          sichtbar: (w) => w.eins(ArtikellisteWahl.reihenfolge) == 'abteilung',
        ),
      const DruckSchalter(
        schluessel: ArtikellisteWahl.kennzahlen,
        titel: 'Kennzahlen',
        hinweis: 'Wie viele vollständig sind, welche Lücke wie oft fehlt',
        gruppe: 'Auf dem Blatt',
      ),
      const DruckSchalter(
        schluessel: ArtikellisteWahl.notizen,
        titel: 'Spalte für Notizen',
        hinweis: 'Leer — zum Schreiben',
        standard: false,
        gruppe: 'Auf dem Blatt',
      ),
      const DruckSchalter(
        schluessel: ArtikellisteWahl.anlagen,
        titel: 'Anlagen',
        hinweis: 'Die Maschinen der Prozessschritte mit Namen',
        gruppe: 'Je Artikel',
      ),
      const DruckSchalter(
        schluessel: ArtikellisteWahl.luecken,
        titel: 'Was fehlt',
        hinweis: 'Die Lücken unter der Bezeichnung',
        gruppe: 'Je Artikel',
      ),
    ],
    bauen: (wahl) {
      final reihenfolge = ArtikellisteReihenfolge.values.firstWhere(
        (r) => r.name == wahl.eins(ArtikellisteWahl.reihenfolge),
        orElse: () => ArtikellisteReihenfolge.liste,
      );
      Set<String>? abteilungen;
      if (reihenfolge == ArtikellisteReihenfolge.abteilung &&
          vorhanden.length > 1) {
        abteilungen = wahl.mehrere(ArtikellisteWahl.abteilungen);
        if (abteilungen.isEmpty) {
          throw const DruckNichtsGewaehlt('Wähle mindestens eine Abteilung.');
        }
      }
      return artikellisteDruck(
        daten,
        gedrucktAm: gedrucktAm,
        inhalt: ArtikellisteInhalt(
          umfang: ArtikellisteUmfang.values.firstWhere(
            (u) => u.name == wahl.eins(ArtikellisteWahl.umfang),
            orElse: () =>
                gefiltert ? ArtikellisteUmfang.liste : ArtikellisteUmfang.alle,
          ),
          reihenfolge: reihenfolge,
          abteilungen: abteilungen,
          kennzahlen: wahl.an(ArtikellisteWahl.kennzahlen),
          anlagen: wahl.an(ArtikellisteWahl.anlagen),
          luecken: wahl.an(ArtikellisteWahl.luecken),
          notizen: wahl.an(ArtikellisteWahl.notizen),
        ),
      );
    },
  );
}

const PdfColor _orange = PdfColor.fromInt(0xFFEF6C00);

/// Ein Abschnitt der Liste: mit Titel (Gruppe, Abteilung) oder ohne.
typedef _Abschnitt = ({
  String? titel,
  int? farbe,
  List<ArtikellisteEintrag> eintraege,
});

class _Liste {
  _Liste(this.daten, this.inhalt, this.gedruckt);

  final ArtikellisteDaten daten;
  final ArtikellisteInhalt inhalt;
  final String gedruckt;

  /// Die Artikel auf dem Blatt — ohne Abschnitte, in der Reihenfolge der
  /// Wahl.
  late final List<ArtikellisteEintrag> eintraege = () {
    final List<ArtikellisteEintrag> auswahl;
    switch (inhalt.umfang) {
      case ArtikellisteUmfang.liste:
        final ids = daten.liste;
        if (ids == null) {
          auswahl = [...daten.alle];
        } else {
          final jeId = {for (final a in daten.alle) a.id: a};
          auswahl = [
            for (final id in ids)
              if (jeId[id] case final a?) a,
          ];
        }
      case ArtikellisteUmfang.alle:
        auswahl = [...daten.alle];
      case ArtikellisteUmfang.luecken:
        auswahl = [
          for (final a in daten.alle)
            if (a.luecken.isNotEmpty) a,
        ];
    }
    switch (inhalt.reihenfolge) {
      case ArtikellisteReihenfolge.liste:
        break;
      case ArtikellisteReihenfolge.nummer:
        auswahl.sort(_nachNummer);
      case ArtikellisteReihenfolge.bezeichnung ||
            ArtikellisteReihenfolge.gruppe ||
            ArtikellisteReihenfolge.abteilung:
        auswahl.sort(_nachBezeichnung);
    }
    return auswahl;
  }();

  /// Die Abschnitte: je Gruppe oder Abteilung einer — sonst einer ohne
  /// Titel. Ohne Artikel keiner.
  List<_Abschnitt> abschnitte() {
    final liste = eintraege;
    if (liste.isEmpty) return const [];
    switch (inhalt.reihenfolge) {
      case ArtikellisteReihenfolge.gruppe:
        final jeGruppe = <String, List<ArtikellisteEintrag>>{};
        for (final a in liste) {
          (jeGruppe[a.produktgruppe] ??= []).add(a);
        }
        // Alphabetisch, ohne Gruppe zuletzt.
        final gruppen = jeGruppe.keys.toList()
          ..sort((a, b) {
            if (a.isEmpty != b.isEmpty) return a.isEmpty ? 1 : -1;
            return a.toLowerCase().compareTo(b.toLowerCase());
          });
        return [
          for (final g in gruppen)
            (
              titel: g.isEmpty ? 'Ohne Produktgruppe' : g,
              farbe: null,
              eintraege: jeGruppe[g]!,
            ),
        ];
      case ArtikellisteReihenfolge.abteilung:
        final gewaehlt = inhalt.abteilungen;
        return [
          for (final a in Abteilung.values)
            if (gewaehlt == null || gewaehlt.contains(a.dbValue))
              if ([
                for (final e in liste)
                  if (e.abteilungen.contains(a)) e,
              ]
                  case final teil when teil.isNotEmpty)
                (titel: a.anzeigeName, farbe: a.farbwert, eintraege: teil),
          // Artikel ohne Schritte haben keine Abteilung — sie stehen am
          // Ende, wenn alle Abteilungen gewählt sind.
          if (gewaehlt == null)
            if ([
              for (final e in liste)
                if (e.abteilungen.isEmpty) e,
            ]
                case final ohne when ohne.isNotEmpty)
              (titel: 'Ohne Prozessschritte', farbe: null, eintraege: ohne),
        ];
      case ArtikellisteReihenfolge.liste ||
            ArtikellisteReihenfolge.nummer ||
            ArtikellisteReihenfolge.bezeichnung:
        return [(titel: null, farbe: null, eintraege: liste)];
    }
  }

  /// Nach Produktgruppe steht die Gruppe über dem Abschnitt.
  bool get mitGruppe => inhalt.reihenfolge != ArtikellisteReihenfolge.gruppe;

  DruckBlatt blatt() {
    final teile = abschnitte();
    // Gezählt wird jeder Artikel einmal, auch wenn er je Abteilung
    // mehrfach dasteht.
    final gezeigt = <String, ArtikellisteEintrag>{
      for (final a in teile)
        for (final e in a.eintraege) e.id: e,
    };
    final zeile = [
      _umfangText(inhalt.umfang, daten),
      _reihenfolgeText(inhalt.reihenfolge, daten),
      _anzahl(gezeigt.length),
    ].join(' · ');
    return DruckBlatt(
      quer: true,
      bauen: (r) {
        final inhaltTeile = <pw.Widget>[
          if (inhalt.kennzahlen) ...kennzahlen(gezeigt.values.toList()),
          if (teile.isEmpty)
            druckHinweis(
              daten.alle.isEmpty
                  ? 'Noch keine Artikel angelegt.'
                  : 'Keine Artikel.',
            ),
          for (final a in teile)
            if (a.titel case final titel?)
              ...druckGruppe(
                [
                  pw.SizedBox(height: 8),
                  druckLeiste(
                    titel,
                    rechts: _anzahl(a.eintraege.length),
                    farbe: a.farbe,
                  ),
                  tabelle(a.eintraege),
                ],
                zusammen: false,
                rahmen: r,
                frei: 90,
              )
            else
              tabelle(a.eintraege),
          ...legende(gezeigt.values),
        ];
        return DruckSeiten(
          kopf: (ctx) => druckKopf(
            titel: 'Artikel',
            zeile: zeile,
            gedruckt: gedruckt,
          ),
          fuss: (ctx) => druckFuss(
            'Artikelliste · ${_umfangText(inhalt.umfang, daten)}',
            r.seitenText(ctx),
          ),
          inhalt: (ctx) => inhaltTeile,
        );
      },
    );
  }

  /// Wie viele Artikel vollständig sind und welche Lücke wie oft fehlt.
  List<pw.Widget> kennzahlen(List<ArtikellisteEintrag> liste) {
    if (liste.isEmpty) return const [];
    final vollstaendig = liste.where((a) => a.luecken.isEmpty).length;
    return [
      druckKennzahlen([
        DruckKennzahl(_anzahl(liste.length), 'auf dem Blatt', betont: true),
        DruckKennzahl('$vollstaendig', 'vollständig gepflegt'),
        for (final l in ArtikelLuecke.values)
          if (liste.where((a) => a.luecken.contains(l)).length case final n
              when n > 0)
            DruckKennzahl('$n', l.titel),
      ]),
    ];
  }

  /// Welche Abteilung hinter welchem Kürzel steckt — nur die gezeigten.
  List<pw.Widget> legende(Iterable<ArtikellisteEintrag> liste) {
    final abteilungen = [
      for (final a in Abteilung.values)
        if (liste.any((e) => e.abteilungen.contains(a))) a,
    ];
    if (abteilungen.isEmpty) return const [];
    return [
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 4),
        child: druckHinweis(
          'Prozess: ${[
            for (final a in abteilungen) '${a.kurzcode} ${a.anzeigeName}',
          ].join(' · ')} — in der Reihenfolge der Schritte.',
          zeilen: 2,
        ),
      ),
    ];
  }

  pw.Widget tabelle(List<ArtikellisteEintrag> liste) => pw.Table(
        border: kDruckGitter,
        columnWidths: <pw.TableColumnWidth>[
          const pw.FixedColumnWidth(58),
          const pw.FlexColumnWidth(),
          if (mitGruppe) const pw.FixedColumnWidth(118),
          const pw.FixedColumnWidth(92),
          const pw.FixedColumnWidth(36),
          if (inhalt.anlagen) const pw.FixedColumnWidth(170),
          if (inhalt.notizen) const pw.FixedColumnWidth(150),
        ].asMap(),
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
        children: [
          druckKopfzeile([
            druckKopfZelle('Art.-Nr.'),
            druckKopfZelle('Bezeichnung'),
            if (mitGruppe) druckKopfZelle('Gruppe'),
            druckKopfZelle('Prozess'),
            druckKopfZelle('Schr.', rechts: true),
            if (inhalt.anlagen) druckKopfZelle('Anlagen'),
            if (inhalt.notizen) druckKopfZelle('Notiz'),
          ]),
          for (final a in liste) zeile(a),
        ],
      );

  pw.TableRow zeile(ArtikellisteEintrag a) {
    final luecken = inhalt.luecken
        ? [
            for (final l in ArtikelLuecke.values)
              if (a.luecken.contains(l)) l.titel,
          ].join(' · ')
        : '';
    return pw.TableRow(
      children: [
        druckZelle(a.nummer, groesse: 8.5),
        druckZelleMitZeile(
          a.bezeichnung,
          luecken,
          fett: true,
          zeilenOben: 2,
          zeilenUnten: 2,
          farbeUnten: _orange,
          groesse: 9,
        ),
        if (mitGruppe)
          a.produktgruppe.isNotEmpty
              ? druckZelle(a.produktgruppe, zeilen: 2, groesse: 8.5)
              : druckZelle(
                  a.planungsgruppe.isEmpty ? '-' : a.planungsgruppe,
                  zeilen: 2,
                  groesse: 8.5,
                  farbe: kDruckGrau,
                ),
        prozess(a.abteilungen),
        druckZelle(
          a.schritte == 0 ? '-' : '${a.schritte}',
          rechts: true,
          groesse: 8.5,
          farbe: a.schritte == 0 ? kDruckGrau : PdfColors.black,
        ),
        if (inhalt.anlagen)
          druckZelle(
            a.anlagen.isEmpty ? '-' : a.anlagen.join(', '),
            zeilen: 3,
            groesse: 8,
            farbe: a.anlagen.isEmpty ? kDruckGrau : PdfColors.black,
          ),
        if (inhalt.notizen) pw.SizedBox(height: 22),
      ],
    );
  }

  /// Die Abteilungen als farbige Kürzel — in jeder Zeile eigene Widgets.
  pw.Widget prozess(List<Abteilung> abteilungen) {
    if (abteilungen.isEmpty) {
      return druckZelle('-', groesse: 8.5, farbe: kDruckGrau);
    }
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Wrap(
        spacing: 2,
        runSpacing: 2,
        children: [
          for (final a in abteilungen) druckMarke(a.kurzcode, a.farbwert),
        ],
      ),
    );
  }
}
