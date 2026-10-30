import 'package:pdf/widgets.dart' as pw;

import '../../../core/constants/artikel_merkmale.dart';
import '../../../core/database/database.dart' show Zutat;
import '../../../core/druck/druck_bausteine.dart';
import '../../../core/druck/druck_optionen.dart';
import '../../../core/druck/druck_satz.dart';
import '../../../core/utils/format.dart';
import '../daten/entwicklung_repository.dart' show nachName, rechenZutatAus;
import '../rechenkern/rechen_modell.dart';

// Der Zutatenkatalog auf Papier: je Zutat Artikelnummer, Art, Allergene
// und die Nährwerte je 100 g, darunter Etikett und Unterzutaten. Alle
// Zutaten oder nur Fleisch, nur mit Allergenen, nur die ohne Nährwerte —
// nach Name oder nach Art geordnet.

/// Welche Zutaten auf die Liste kommen.
enum ZutatenUmfang {
  alle,

  /// Nur Fleisch.
  fleisch,

  /// Nur Zutaten mit Allergenen.
  allergene,

  /// Nur Zutaten, denen Nährwerte fehlen — was noch zu tun ist.
  ohneNaehrwerte,
}

/// Schlüssel der Wahl im Druckfenster.
abstract final class ZutatenkatalogWahl {
  static const suche = 'suche';
  static const umfang = 'umfang';
  static const gliederung = 'gliederung';
  static const naehrwerte = 'naehrwerte';
  static const etikett = 'etikett';
}

/// Was auf die Liste kommt — die Wahl im Druckfenster.
class ZutatenkatalogInhalt {
  const ZutatenkatalogInhalt({
    this.suche = '',
    this.umfang = ZutatenUmfang.alle,
    this.nachArt = false,
    this.naehrwerte = true,
    this.etikett = true,
  });

  /// Nur, was diese Suche trifft — leer: alles.
  final String suche;

  final ZutatenUmfang umfang;

  /// Abschnitte je Art: Fleisch je Tierart, Wasser, übrige Zutaten.
  final bool nachArt;

  /// Die Nährwerte je 100 g als Spalten — sonst nur, ob sie da sind.
  final bool naehrwerte;

  /// Etikett, Unterzutaten und Hilfsstoffe unter dem Namen.
  final bool etikett;
}

/// Ob [z] die Suche [q] trifft — wie die Liste auf dem Schirm: Name,
/// Etikett, Artikelnummer.
bool zutatTrifft(Zutat z, String q) {
  final t = q.trim().toLowerCase();
  if (t.isEmpty) return true;
  return z.name.toLowerCase().contains(t) ||
      (z.etikettName ?? '').toLowerCase().contains(t) ||
      (z.artikelnummer ?? '').toLowerCase().contains(t);
}

/// Ob die Nährwerte von [z] da sind — Wasser braucht keine.
bool zutatMitNaehrwerten(Zutat z) =>
    z.istWasser || rechenZutatAus(z).naehrwerte.bekannt;

/// Ob [z] zum [umfang] gehört.
bool zutatImUmfang(Zutat z, ZutatenUmfang umfang) => switch (umfang) {
      ZutatenUmfang.alle => true,
      ZutatenUmfang.fleisch => z.istFleisch,
      ZutatenUmfang.allergene =>
        merkmaleAusText(z.allergene).any((a) => a != kAllergenKeine),
      ZutatenUmfang.ohneNaehrwerte => !zutatMitNaehrwerten(z),
    };

/// „Fleisch (Schwein)", „Wasser" — leer für eine übrige Zutat.
String zutatArt(Zutat z) {
  if (z.istWasser) return 'Wasser';
  if (!z.istFleisch) return '';
  final t = Tierart.aus(z.tierart);
  return t == null ? 'Fleisch' : 'Fleisch (${t.label})';
}

String _umfangText(ZutatenUmfang u) => switch (u) {
      ZutatenUmfang.alle => 'Alle Zutaten',
      ZutatenUmfang.fleisch => 'Nur Fleisch',
      ZutatenUmfang.allergene => 'Nur mit Allergenen',
      ZutatenUmfang.ohneNaehrwerte => 'Nur ohne Nährwerte',
    };

/// Der Zutatenkatalog zum Drucken.
DruckDokument zutatenkatalogDruck(
  List<Zutat> zutaten, {
  ZutatenkatalogInhalt inhalt = const ZutatenkatalogInhalt(),
  DateTime? gedrucktAm,
}) {
  final gedruckt = gedrucktAm ?? DateTime.now();
  final katalog = _Katalog(zutaten, inhalt, druckGedruckt(gedruckt));
  return DruckDokument(
    titel: 'Zutaten',
    dateiname: druckDateiname('Zutaten ${druckIsoDatum(gedruckt)}'),
    blaetter: [katalog.blatt()],
  );
}

/// Der Zutatenkatalog für das Druckfenster — mit [suche], wenn die Liste
/// gerade sucht.
DruckAuftrag zutatenkatalogDruckAuftrag(
  List<Zutat> zutaten, {
  String suche = '',
  DateTime? gedrucktAm,
}) {
  final q = suche.trim();
  final aktiv = [
    for (final z in zutaten)
      if (z.deletedAt == null) z,
  ];
  String anzahl(ZutatenUmfang u) {
    final n = aktiv.where((z) => zutatImUmfang(z, u)).length;
    return n == 1 ? '1 Zutat' : '$n Zutaten';
  }

  return DruckAuftrag(
    art: 'zutatenkatalog',
    titel: 'Zutaten drucken',
    untertitel: q.isEmpty ? null : 'Suche „$q“',
    optionen: [
      if (q.isNotEmpty)
        DruckSchalter(
          schluessel: ZutatenkatalogWahl.suche,
          titel: 'Nur Treffer der Suche „$q“',
          merken: false,
        ),
      DruckWahlEins(
        schluessel: ZutatenkatalogWahl.umfang,
        titel: 'Zutaten',
        werte: [
          for (final u in ZutatenUmfang.values)
            DruckWert(u.name, _umfangText(u), hinweis: anzahl(u)),
        ],
        standard: ZutatenUmfang.alle.name,
      ),
      const DruckWahlEins(
        schluessel: ZutatenkatalogWahl.gliederung,
        titel: 'Reihenfolge',
        werte: [
          DruckWert('name', 'Nach Name'),
          DruckWert(
            'art',
            'Nach Art',
            hinweis: 'Fleisch je Tierart, Wasser, übrige Zutaten',
          ),
        ],
        standard: 'name',
      ),
      const DruckSchalter(
        schluessel: ZutatenkatalogWahl.naehrwerte,
        titel: 'Nährwerte je 100 g',
        hinweis: 'Sonst nur, ob sie da sind',
        gruppe: 'Je Zutat',
      ),
      const DruckSchalter(
        schluessel: ZutatenkatalogWahl.etikett,
        titel: 'Etikett und Unterzutaten',
        gruppe: 'Je Zutat',
      ),
    ],
    bauen: (wahl) => zutatenkatalogDruck(
      zutaten,
      gedrucktAm: gedrucktAm,
      inhalt: ZutatenkatalogInhalt(
        suche: q.isNotEmpty && wahl.an(ZutatenkatalogWahl.suche) ? q : '',
        umfang: ZutatenUmfang.values.firstWhere(
          (u) => u.name == wahl.eins(ZutatenkatalogWahl.umfang),
          orElse: () => ZutatenUmfang.alle,
        ),
        nachArt: wahl.eins(ZutatenkatalogWahl.gliederung) == 'art',
        naehrwerte: wahl.an(ZutatenkatalogWahl.naehrwerte),
        etikett: wahl.an(ZutatenkatalogWahl.etikett),
      ),
    ),
  );
}

/// Ein Nährwert je 100 g: bis zu zwei Nachkommastellen, ohne Nullen am
/// Ende — „22", „8,5", „0,12". Leer: unbekannt.
String _wert(double? w) {
  if (w == null || !w.isFinite) return '';
  return Format.zahl(w, nachkomma: 2).replaceFirst(RegExp(r',?0+$'), '');
}

/// Die Spalten der Nährwerte: Überschrift, Breite und Wert.
final List<(String, double, double? Function(Zutat z))> _naehrstoffe = [
  ('kcal', 34, (z) => z.energieKcal),
  ('Fett', 34, (z) => z.fett),
  ('ges. FS', 42, (z) => z.gesaettigteFettsaeuren),
  ('KH', 32, (z) => z.kohlenhydrate),
  ('Zucker', 38, (z) => z.zucker),
  ('Eiweiß', 38, (z) => z.eiweiss),
  ('Salz', 34, (z) => z.salz),
  ('BEFFE', 38, (z) => z.beffe),
];

class _Katalog {
  _Katalog(List<Zutat> alle, this.inhalt, this.gedruckt)
      : zutaten = [
          for (final z in alle)
            if (z.deletedAt == null &&
                zutatTrifft(z, inhalt.suche) &&
                zutatImUmfang(z, inhalt.umfang))
              z,
        ]..sort((a, b) => nachName(a.name, b.name)),
        gesamt = alle.where((z) => z.deletedAt == null).length;

  final ZutatenkatalogInhalt inhalt;
  final String gedruckt;
  final List<Zutat> zutaten;

  /// Wie viele Zutaten der Katalog hat.
  final int gesamt;

  /// Die Abschnitte: nach Art einer je Tierart, Fleisch ohne Tierart,
  /// Wasser und die übrigen — sonst einer ohne Titel.
  List<({String? titel, List<Zutat> zutaten})> abschnitte() {
    if (zutaten.isEmpty) return const [];
    if (!inhalt.nachArt) return [(titel: null, zutaten: zutaten)];
    final teile = <({String? titel, List<Zutat> zutaten})>[
      for (final t in Tierart.values)
        (
          titel: 'Fleisch: ${t.label}',
          zutaten: [
            for (final z in zutaten)
              if (z.istFleisch && Tierart.aus(z.tierart) == t) z,
          ],
        ),
      (
        titel: 'Fleisch ohne Tierart',
        zutaten: [
          for (final z in zutaten)
            if (z.istFleisch && Tierart.aus(z.tierart) == null) z,
        ],
      ),
      (
        titel: 'Wasser',
        zutaten: [
          for (final z in zutaten)
            if (z.istWasser && !z.istFleisch) z,
        ],
      ),
      (
        titel: 'Übrige Zutaten',
        zutaten: [
          for (final z in zutaten)
            if (!z.istFleisch && !z.istWasser) z,
        ],
      ),
    ];
    return [
      for (final t in teile)
        if (t.zutaten.isNotEmpty) t,
    ];
  }

  DruckBlatt blatt() {
    final n = zutaten.length;
    final zeile = [
      _umfangText(inhalt.umfang),
      if (inhalt.suche.trim().isNotEmpty) 'Suche „${inhalt.suche.trim()}“',
      n == gesamt ? '$n Zutaten' : '$n von $gesamt Zutaten',
    ].join(' · ');
    return DruckBlatt(
      quer: true,
      bauen: (r) {
        final teile = <pw.Widget>[
          if (inhalt.naehrwerte && zutaten.isNotEmpty)
            druckHinweis(
              'Nährwerte je 100 g, wie im Katalog hinterlegt: Energie in '
              'kcal, sonst in Gramm — ges. FS: gesättigte Fettsäuren, KH: '
              'Kohlenhydrate. BEFFE in Prozent.',
              zeilen: 2,
            ),
          if (zutaten.isEmpty)
            druckHinweis(
              gesamt == 0 ? 'Noch keine Zutaten.' : 'Keine Treffer.',
            ),
          for (final a in abschnitte())
            if (a.titel case final titel?)
              ...druckGruppe(
                [
                  pw.SizedBox(height: 8),
                  druckLeiste(
                    titel,
                    rechts: a.zutaten.length == 1
                        ? '1 Zutat'
                        : '${a.zutaten.length} Zutaten',
                  ),
                  tabelle(a.zutaten),
                ],
                zusammen: false,
                rahmen: r,
                frei: 90,
              )
            else
              tabelle(a.zutaten),
        ];
        return DruckSeiten(
          kopf: (ctx) => druckKopf(
            titel: 'Zutaten',
            zeile: zeile,
            gedruckt: gedruckt,
          ),
          fuss: (ctx) => druckFuss(
            'Zutatenkatalog · ${_umfangText(inhalt.umfang)}',
            r.seitenText(ctx),
          ),
          inhalt: (ctx) => teile,
        );
      },
    );
  }

  pw.Widget tabelle(List<Zutat> liste) {
    final mitWerten = inhalt.naehrwerte;
    final breiten = <pw.TableColumnWidth>[
      const pw.FlexColumnWidth(),
      const pw.FixedColumnWidth(62),
      const pw.FixedColumnWidth(86),
      const pw.FixedColumnWidth(130),
      if (mitWerten)
        for (final (_, breite, _) in _naehrstoffe) pw.FixedColumnWidth(breite)
      else
        const pw.FixedColumnWidth(70),
    ];
    return pw.Table(
      border: kDruckGitter,
      columnWidths: breiten.asMap(),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        druckKopfzeile([
          druckKopfZelle('Zutat'),
          druckKopfZelle('Art.-Nr.'),
          druckKopfZelle('Art'),
          druckKopfZelle('Allergene'),
          if (mitWerten)
            for (final (titel, _, _) in _naehrstoffe)
              druckKopfZelle(titel, rechts: true)
          else
            druckKopfZelle('Nährwerte'),
        ]),
        for (final z in liste) zeile(z),
      ],
    );
  }

  pw.TableRow zeile(Zutat z) {
    final etikett = z.etikettName?.trim() ?? '';
    final unter = z.unterzutaten?.trim() ?? '';
    final hilfs = z.verarbeitungshilfsstoffe?.trim() ?? '';
    final unten = inhalt.etikett
        ? [
            if (etikett.isNotEmpty) 'Etikett: $etikett',
            if (unter.isNotEmpty) 'Unterzutaten: $unter',
            if (hilfs.isNotEmpty) 'Hilfsstoffe: $hilfs',
          ].join(' · ')
        : null;
    final allergene = merkmaleLabel(z.allergene, kAllergene);
    final nummer = z.artikelnummer?.trim() ?? '';
    final art = zutatArt(z);
    return pw.TableRow(
      children: [
        druckZelleMitZeile(
          z.name,
          unten,
          fett: true,
          zeilenOben: 1,
          zeilenUnten: 2,
        ),
        druckZelle(nummer.isEmpty ? '-' : nummer, groesse: 8.5),
        druckZelle(art.isEmpty ? '-' : art, groesse: 8.5),
        druckZelle(
          allergene.isEmpty ? '-' : allergene,
          groesse: 8.5,
          zeilen: 2,
        ),
        if (inhalt.naehrwerte)
          for (final (_, _, wert) in _naehrstoffe)
            druckZelle(
              switch (wert(z)) {
                null => z.istWasser ? '' : '-',
                final double w => _wert(w),
              },
              rechts: true,
              groesse: 8,
            )
        else
          druckZelle(
            zutatMitNaehrwerten(z) ? 'da' : 'fehlen',
            groesse: 8.5,
            fett: !zutatMitNaehrwerten(z),
          ),
      ],
    );
  }
}
