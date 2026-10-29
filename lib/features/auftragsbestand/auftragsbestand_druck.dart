import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/druck/druck_bausteine.dart';
import '../../core/druck/druck_optionen.dart';
import '../../core/druck/druck_satz.dart';
import '../../core/services/auftragsbestand_deckung.dart';
import '../../core/utils/datum.dart';
import '../../core/utils/format.dart';
import 'auftragsbestand_ansicht.dart';
import 'planung_pruefen.dart' show PlanungsKonflikt;

// Der Auftragsbestand auf Papier: je Artikel, je Versandtag oder je Kunde,
// was bestellt ist und woher es kommt — aus dem Lager, aus Produktion,
// beim Planungsvorschlag vorgemerkt — und was fehlt. Für die Besprechung
// am Morgen, zum Abgleich mit dem Versand oder mit dem Vertrieb.
//
// Die Spaltenköpfe stehen im Kopf jeder Seite; jeder Artikel (jeder Tag,
// jeder Kunde) ist eine eigene Tabelle mit denselben Spaltenbreiten. So
// bleibt ein Artikel beisammen, und auf jeder Seite ist klar, was in
// welcher Spalte steht.

/// Wie der Ausdruck gegliedert ist.
enum BestandGliederung {
  /// Je Artikel, darunter seine Versandtage und Aufträge — wie die Liste.
  artikel,

  /// Je Versandtag die Artikel, die an dem Tag rausgehen.
  versandtag,

  /// Je Kunde seine Aufträge.
  kunde,
}

/// Was auf den Ausdruck kommt.
enum BestandUmfang {
  /// Was noch zu bündeln ist, zu spät kommt oder verschoben wurde — die
  /// Arbeit im Auftragsbestand. Was beim Planungsvorschlag vorgemerkt ist,
  /// ist hier erledigt.
  handlung,

  /// Was nicht rechtzeitig gedeckt ist — auch, was schon beim
  /// Planungsvorschlag vorgemerkt ist.
  ungedeckt,

  /// Alles.
  alle,
}

/// Wie viel je Artikel steht.
enum BestandTiefe {
  /// Eine Zeile je Artikel.
  artikel,

  /// Dazu je Versandtag eine Zeile.
  tage,

  /// Dazu je Versandtag seine Aufträge.
  auftraege,
}

/// Schlüssel der Wahl im Druckfenster.
abstract final class BestandDruckWahl {
  static const gliederung = 'gliederung';
  static const umfang = 'umfang';
  static const zeitraum = 'zeitraum';
  static const gefiltert = 'gefiltert';
  static const sortierung = 'sortierung';
  static const tiefe = 'tiefe';
  static const auftraege = 'auftraege';
  static const produktionen = 'produktionen';
  static const kennzahlen = 'kennzahlen';
}

/// Was vom Auftragsbestand gedruckt wird — die Wahl im Druckfenster.
class BestandDruckInhalt {
  const BestandDruckInhalt({
    this.gliederung = BestandGliederung.artikel,
    this.umfang = BestandUmfang.handlung,
    this.versandBis,
    this.nurArtikel,
    this.filterText,
    this.sortierung = BestandSortierung.engpass,
    this.tiefe = BestandTiefe.tage,
    this.auftraegeEinzeln = false,
    this.produktionen = true,
    this.kennzahlen = true,
  });

  final BestandGliederung gliederung;
  final BestandUmfang umfang;

  /// Nur Versandtage bis einschließlich zu diesem Tag — null: alle. Was
  /// überfällig ist, gehört so immer dazu.
  final DateTime? versandBis;

  /// Nur diese Artikel (Nummern) — wie in der Liste gefiltert. null: alle.
  final Set<String>? nurArtikel;

  /// Wie die Liste gefiltert ist — für die Zeile über dem Ausdruck.
  final String? filterText;

  /// Reihenfolge der Artikel — nur in der Gliederung nach Artikel.
  final BestandSortierung sortierung;

  /// Nur in der Gliederung nach Artikel.
  final BestandTiefe tiefe;

  /// Unter jedem Artikel eines Versandtags seine Aufträge — nur in der
  /// Gliederung nach Versandtag.
  final bool auftraegeEinzeln;

  /// Vormerkungen und Produktionen unter jedem Artikel — nur in der
  /// Gliederung nach Artikel mit Versandtagen.
  final bool produktionen;

  /// Kennzahlen über dem Ausdruck.
  final bool kennzahlen;
}

/// Unter 5 g ist Rundung, kein Bedarf.
const double _schwelle = 0.005;

// Die Farben der Punkte vor dem Stand — dieselben wie in der App. Der Text
// sagt dasselbe, auch im Schwarzweiß-Druck.
const PdfColor _rot = PdfColor.fromInt(0xFFC62828);
const PdfColor _orange = PdfColor.fromInt(0xFFEF6C00);
const PdfColor _blau = PdfColor.fromInt(0xFF1565C0);
const PdfColor _gruen = PdfColor.fromInt(0xFF2E7D32);
const PdfColor _lila = PdfColor.fromInt(0xFF7E22CE);

/// Ob ein Versandtag auf den Ausdruck kommt.
bool bestandTagZeigen(
  TagesDeckung t,
  BestandUmfang umfang, {
  Map<String, PlanungsKonflikt> verschoben = const {},
}) =>
    switch (umfang) {
      BestandUmfang.alle => true,
      BestandUmfang.ungedeckt => t.offen,
      BestandUmfang.handlung => t.offenKg >= _schwelle ||
          t.zuSpaetKg >= _schwelle ||
          t.zeilen.any((z) => verschoben.containsKey(z.schluessel)),
    };

/// Ob ein Auftrag auf den Ausdruck kommt.
bool bestandZeileZeigen(
  ZeilenDeckung z,
  BestandUmfang umfang, {
  Map<String, PlanungsKonflikt> verschoben = const {},
}) =>
    switch (umfang) {
      BestandUmfang.alle => true,
      BestandUmfang.ungedeckt => z.offen,
      BestandUmfang.handlung => z.offenKg >= _schwelle ||
          z.zuSpaetKg >= _schwelle ||
          verschoben.containsKey(z.schluessel),
    };

/// Die Deckung eines Artikels, nur mit den Versandtagen bis [bis] — null:
/// alle. Das Lager geht an die frühesten Tage, die Rechnung bleibt also
/// gültig, wenn hinten Tage wegfallen.
ArtikelDeckung bestandImZeitraum(ArtikelDeckung d, DateTime? bis) {
  if (bis == null) return d;
  final ende = tagOhneZeit(bis);
  return ArtikelDeckung(
    lagerKg: d.lagerKg,
    zugangKg: d.zugangKg,
    ueberschussKg: d.ueberschussKg,
    tage: [
      for (final t in d.tage)
        if (!t.tag.isAfter(ende)) t,
    ],
  );
}

/// Der Auftragsbestand zum Drucken.
DruckDokument bestandDruck(
  AuftragsbestandAnsicht ansicht, {
  required DateTime heute,
  BestandDruckInhalt inhalt = const BestandDruckInhalt(),
  DateTime? gedrucktAm,
}) {
  final druck = _BestandDruck(
    ansicht,
    inhalt: inhalt,
    heute: tagOhneZeit(heute),
    gedruckt: druckGedruckt(gedrucktAm ?? DateTime.now()),
  );
  final stand = ansicht.stand ?? ansicht.importiertAm ?? heute;
  final art = switch (inhalt.gliederung) {
    BestandGliederung.artikel => '',
    BestandGliederung.versandtag => ' nach Versandtag',
    BestandGliederung.kunde => ' nach Kunde',
  };
  return DruckDokument(
    titel: 'Auftragsbestand$art ${Format.datum(stand)}',
    dateiname: druckDateiname(
      'Auftragsbestand$art ${druckIsoDatum(stand)}',
    ),
    blaetter: [druck.blatt()],
  );
}

/// Der Auftragsbestand für das Druckfenster.
///
/// Vorgewählt ist, was die Liste zeigt: [nurHandlung] wie der Filter
/// „Nur mit Handlungsbedarf", [sortierung] wie dort eingestellt. Ist die
/// Liste nach Abteilung oder Suche gefiltert ([gefiltert] mit den Nummern,
/// [filterText] mit der Beschreibung), lässt sich der Ausdruck darauf
/// beschränken. Das hängt an der Liste und wird nicht gemerkt; alles andere
/// schon.
DruckAuftrag bestandDruckAuftrag(
  AuftragsbestandAnsicht ansicht, {
  required DateTime heute,
  bool nurHandlung = true,
  BestandSortierung sortierung = BestandSortierung.engpass,
  Set<String>? gefiltert,
  String? filterText,
  DateTime? gedrucktAm,
}) {
  final tag = tagOhneZeit(heute);
  final sonntag = tagPlus(tag, DateTime.daysPerWeek - tag.weekday);
  final naechsterSonntag = tagPlus(sonntag, 7);
  bool nachArtikel(DruckWahl w) =>
      w.eins(BestandDruckWahl.gliederung) == BestandGliederung.artikel.name;
  final stand = ansicht.stand;

  return DruckAuftrag(
    art: 'auftragsbestand',
    titel: 'Auftragsbestand drucken',
    untertitel: stand == null
        ? 'Auftragsbestand'
        : 'Auftragsbestand · Stand ${Format.datum(stand)}',
    optionen: [
      DruckWahlEins(
        schluessel: BestandDruckWahl.gliederung,
        titel: 'Gliederung',
        werte: [
          DruckWert(
            BestandGliederung.artikel.name,
            'Nach Artikel',
            hinweis: 'Wie die Liste — mit Versandtagen und Aufträgen',
          ),
          DruckWert(
            BestandGliederung.versandtag.name,
            'Nach Versandtag',
            hinweis: 'Was an welchem Tag rausgeht',
          ),
          DruckWert(
            BestandGliederung.kunde.name,
            'Nach Kunde',
            hinweis: 'Je Kunde seine Aufträge',
          ),
        ],
        standard: BestandGliederung.artikel.name,
      ),
      DruckWahlEins(
        schluessel: BestandDruckWahl.umfang,
        titel: 'Was',
        werte: [
          DruckWert(
            BestandUmfang.handlung.name,
            'Nur mit Handlungsbedarf',
            hinweis: 'Noch zu bündeln, zu spät oder verschoben',
          ),
          DruckWert(
            BestandUmfang.ungedeckt.name,
            'Alles nicht Gedeckte',
            hinweis: 'Auch, was beim Planungsvorschlag vorgemerkt ist',
          ),
          DruckWert(
            BestandUmfang.alle.name,
            'Alles',
            hinweis: 'Auch, was aus Lager und Produktion gedeckt ist',
          ),
        ],
        standard: nurHandlung
            ? BestandUmfang.handlung.name
            : BestandUmfang.alle.name,
        merken: false,
      ),
      DruckWahlEins(
        schluessel: BestandDruckWahl.zeitraum,
        titel: 'Versandtage',
        hinweis: 'Was überfällig ist, steht immer dabei.',
        werte: [
          const DruckWert('alle', 'Alle'),
          DruckWert(
            'woche',
            'Bis Ende dieser Woche',
            hinweis: 'bis ${Format.tagKurz(sonntag)}',
          ),
          DruckWert(
            'naechste',
            'Bis Ende nächster Woche',
            hinweis: 'bis ${Format.tagKurz(naechsterSonntag)}',
          ),
        ],
        standard: 'alle',
      ),
      if (gefiltert != null)
        DruckSchalter(
          schluessel: BestandDruckWahl.gefiltert,
          titel: 'Nur die gefilterte Liste',
          hinweis: filterText,
          merken: false,
        ),
      DruckWahlEins(
        schluessel: BestandDruckWahl.sortierung,
        titel: 'Reihenfolge',
        werte: [
          for (final s in BestandSortierung.values)
            DruckWert(s.name, s.label),
        ],
        standard: sortierung.name,
        merken: false,
        sichtbar: nachArtikel,
      ),
      DruckWahlEins(
        schluessel: BestandDruckWahl.tiefe,
        titel: 'Je Artikel',
        werte: const [
          DruckWert('artikel', 'Eine Zeile'),
          DruckWert('tage', 'Mit Versandtagen'),
          DruckWert('auftraege', 'Mit Versandtagen und Aufträgen'),
        ],
        standard: BestandTiefe.tage.name,
        sichtbar: nachArtikel,
      ),
      DruckSchalter(
        schluessel: BestandDruckWahl.produktionen,
        titel: 'Vormerkungen und Produktionen',
        hinweis: 'Unter dem Artikel, woher die Ware kommt',
        gruppe: 'Außerdem',
        sichtbar: (w) =>
            nachArtikel(w) &&
            w.eins(BestandDruckWahl.tiefe) != BestandTiefe.artikel.name,
      ),
      DruckSchalter(
        schluessel: BestandDruckWahl.auftraege,
        titel: 'Aufträge einzeln',
        hinweis: 'Unter jedem Artikel die Aufträge des Tages',
        standard: false,
        gruppe: 'Außerdem',
        sichtbar: (w) =>
            w.eins(BestandDruckWahl.gliederung) ==
            BestandGliederung.versandtag.name,
      ),
      const DruckSchalter(
        schluessel: BestandDruckWahl.kennzahlen,
        titel: 'Kennzahlen',
        hinweis: 'Bestellt, aus Lager, aus Produktion, was fehlt',
        gruppe: 'Außerdem',
      ),
    ],
    bauen: (wahl) {
      T nach<T extends Enum>(List<T> werte, String schluessel, T sonst) {
        final name = wahl.eins(schluessel);
        for (final w in werte) {
          if (w.name == name) return w;
        }
        return sonst;
      }

      final versandBis = switch (wahl.eins(BestandDruckWahl.zeitraum)) {
        'woche' => sonntag,
        'naechste' => naechsterSonntag,
        _ => null,
      };
      final nurGefiltert =
          gefiltert != null && wahl.an(BestandDruckWahl.gefiltert);
      return bestandDruck(
        ansicht,
        heute: tag,
        gedrucktAm: gedrucktAm,
        inhalt: BestandDruckInhalt(
          gliederung: nach(
            BestandGliederung.values,
            BestandDruckWahl.gliederung,
            BestandGliederung.artikel,
          ),
          umfang: nach(
            BestandUmfang.values,
            BestandDruckWahl.umfang,
            BestandUmfang.handlung,
          ),
          versandBis: versandBis,
          nurArtikel: nurGefiltert ? gefiltert : null,
          filterText: nurGefiltert ? filterText : null,
          sortierung: nach(
            BestandSortierung.values,
            BestandDruckWahl.sortierung,
            sortierung,
          ),
          tiefe: nach(
            BestandTiefe.values,
            BestandDruckWahl.tiefe,
            BestandTiefe.tage,
          ),
          auftraegeEinzeln: wahl.an(BestandDruckWahl.auftraege),
          produktionen: wahl.an(BestandDruckWahl.produktionen),
          kennzahlen: wahl.an(BestandDruckWahl.kennzahlen),
        ),
      );
    },
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Satz
// ═══════════════════════════════════════════════════════════════════════════

/// Eine Spalte der Tabellen.
class _Spalte {
  const _Spalte(this.titel, this.breite, {this.rechts = false});

  final String titel;
  final double? breite;
  final bool rechts;

  pw.TableColumnWidth get weite => breite == null
      ? const pw.FlexColumnWidth()
      : pw.FixedColumnWidth(breite!);
}

/// Ein Artikel mit dem, was von ihm auf den Ausdruck kommt.
class _Artikel {
  _Artikel(this.zeile, this.deckung);

  final AuftragsbestandZeile zeile;

  /// Die Deckung im gewählten Zeitraum.
  final ArtikelDeckung deckung;
}

/// Bis zu so vielen Zeilen bleibt ein Abschnitt — ein Artikel, ein Kunde,
/// ein Versandtag — auf einer Seite. Eine Zeile ist höchstens rund 30 Punkt
/// hoch, die Seite im Querformat bietet über 400.
const int _zusammenBis = 12;

class _BestandDruck {
  _BestandDruck(
    this.ansicht, {
    required this.inhalt,
    required this.heute,
    required this.gedruckt,
  }) : artikel = _waehle(ansicht, inhalt);

  final AuftragsbestandAnsicht ansicht;
  final BestandDruckInhalt inhalt;
  final DateTime heute;
  final String gedruckt;

  /// Die Artikel im gewählten Zeitraum, gefiltert — noch ohne Rücksicht auf
  /// den Umfang. Mit Versandtagen im Zeitraum.
  final List<_Artikel> artikel;

  static List<_Artikel> _waehle(
    AuftragsbestandAnsicht ansicht,
    BestandDruckInhalt inhalt,
  ) {
    final nur = inhalt.nurArtikel;
    return [
      for (final z in ansicht.zeilen)
        if (nur == null || nur.contains(z.artikel.artikelnummer))
          if (bestandImZeitraum(z.deckung, inhalt.versandBis) case final d
              when d.tage.isNotEmpty)
            _Artikel(z, d),
    ];
  }

  bool tagZeigen(_Artikel a, TagesDeckung t) =>
      bestandTagZeigen(t, inhalt.umfang, verschoben: a.zeile.verschoben);

  bool zeileZeigen(_Artikel a, ZeilenDeckung z) =>
      bestandZeileZeigen(z, inhalt.umfang, verschoben: a.zeile.verschoben);

  // ── Blatt ─────────────────────────────────────────────────────────────

  DruckBlatt blatt() {
    final stand = ansicht.stand ?? ansicht.importiertAm;
    final titel = switch (inhalt.gliederung) {
      BestandGliederung.artikel => 'Auftragsbestand',
      BestandGliederung.versandtag => 'Auftragsbestand nach Versandtag',
      BestandGliederung.kunde => 'Auftragsbestand nach Kunde',
    };
    final herkunft = ansicht.herkunft;
    final spalten = this.spalten();
    return DruckBlatt(
      quer: true,
      rand: const pw.EdgeInsets.fromLTRB(24, 20, 24, 16),
      bauen: (r) {
        final teile = switch (inhalt.gliederung) {
          BestandGliederung.artikel => nachArtikel(spalten, r),
          BestandGliederung.versandtag => nachVersandtag(spalten, r),
          BestandGliederung.kunde => nachKunde(spalten, r),
        };
        return DruckSeiten(
          kopf: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              druckKopf(
                titel: titel,
                zeile: herkunft.isEmpty ? 'Ohne Stand' : herkunft,
                gedruckt: gedruckt,
              ),
              // Auswahl und Kennzahlen nur auf der ersten Seite.
              if (r.seiteImBlatt(ctx) == 1) ...vorspann(),
              if (teile.isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: kopfTabelle(spalten),
                ),
            ],
          ),
          fuss: (ctx) => druckFuss(
            stand == null
                ? 'Auftragsbestand'
                : 'Auftragsbestand · Stand ${Format.datum(stand)}',
            r.seitenText(ctx),
          ),
          inhalt: (ctx) => teile.isEmpty ? [druckHinweis(leerText)] : teile,
        );
      },
    );
  }

  /// Was gewählt ist, ob der Bericht veraltet ist, und die Kennzahlen.
  List<pw.Widget> vorspann() {
    final berichtTag = ansicht.berichtTag;
    final bis = inhalt.versandBis;
    final auswahl = [
      switch (inhalt.umfang) {
        BestandUmfang.handlung => 'Nur mit Handlungsbedarf',
        BestandUmfang.ungedeckt => 'Alles nicht rechtzeitig Gedeckte',
        BestandUmfang.alle => 'Alle Aufträge',
      },
      if (bis != null) 'Versand bis ${Format.tagKurz(bis)}${bis.year}',
      if (inhalt.filterText case final f? when f.trim().isNotEmpty)
        'gefiltert: ${f.trim()}',
    ].join(' · ');
    return [
      if (berichtTag != null && berichtTag.isBefore(heute))
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: druckZelleMitPunkt(
            'Der Bericht ist vom ${Format.datum(berichtTag)} — nicht von '
            'heute. Für einen aktuellen Stand frisch einlesen.',
            _orange,
            fett: true,
            groesse: 9,
          ),
        ),
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: druckHinweis(auswahl, zeilen: 2),
      ),
      if (inhalt.kennzahlen) druckKennzahlen(kennzahlen()),
    ];
  }

  /// Kennzahlen über alle Artikel im Zeitraum (und im Filter) — ohne
  /// Rücksicht darauf, was davon auf den Ausdruck kommt.
  List<DruckKennzahl> kennzahlen() {
    final belege = <String>{};
    final kunden = <String>{};
    var bestellt = 0.0;
    var lager = 0.0;
    var produktion = 0.0;
    var offen = 0.0;
    var vorgemerkt = 0.0;
    var zuSpaet = 0.0;
    var handlung = 0;
    for (final a in artikel) {
      final d = a.deckung;
      for (final t in d.tage) {
        for (final z in t.zeilen) {
          belege.add(z.position.beleg);
          kunden.add(z.position.debitor);
        }
      }
      bestellt += d.auftragKg;
      lager += d.ausLagerKg;
      produktion += d.ausPlanungKg + d.zuSpaetKg;
      offen += d.offenKg;
      vorgemerkt += d.vorgemerktKg;
      zuSpaet += d.zuSpaetKg;
      bool arbeit(TagesDeckung t) => bestandTagZeigen(
            t,
            BestandUmfang.handlung,
            verschoben: a.zeile.verschoben,
          );
      if (d.tage.any(arbeit)) handlung++;
    }
    return [
      DruckKennzahl('${artikel.length}', 'Artikel'),
      DruckKennzahl('${belege.length}', 'Aufträge'),
      DruckKennzahl('${kunden.length}', 'Kunden'),
      DruckKennzahl(Format.kg(bestellt), 'bestellt'),
      DruckKennzahl(Format.kg(lager), 'aus dem Lager'),
      DruckKennzahl(Format.kg(produktion), 'aus Produktion'),
      DruckKennzahl(
        Format.kg(offen),
        'noch einzuplanen',
        betont: offen >= _schwelle,
      ),
      if (vorgemerkt >= _schwelle)
        DruckKennzahl(Format.kg(vorgemerkt), 'beim Planungsvorschlag'),
      if (zuSpaet >= _schwelle)
        DruckKennzahl(Format.kg(zuSpaet), 'zu spät eingeplant'),
      DruckKennzahl(
        '$handlung',
        'Artikel mit Handlungsbedarf',
        betont: handlung > 0,
      ),
    ];
  }

  String get leerText => switch (inhalt.umfang) {
        BestandUmfang.handlung => artikel.isEmpty
            ? 'Keine Aufträge im gewählten Zeitraum.'
            : 'Nichts zu tun — kein Artikel mit Handlungsbedarf.',
        BestandUmfang.ungedeckt => artikel.isEmpty
            ? 'Keine Aufträge im gewählten Zeitraum.'
            : 'Alles rechtzeitig gedeckt.',
        BestandUmfang.alle => 'Keine Aufträge im gewählten Zeitraum.',
      };

  // ── Spalten ───────────────────────────────────────────────────────────

  /// Produktion und vorgemerkt nur, wenn dort irgendwo etwas steht — wie
  /// in der Liste.
  List<_Spalte> spalten() {
    final produktion = artikel.any(
      (a) => a.deckung.ausPlanungKg + a.deckung.zuSpaetKg >= _schwelle,
    );
    final vorgemerkt =
        artikel.any((a) => a.deckung.vorgemerktKg >= _schwelle);
    final mengen = [
      const _Spalte('bestellt', 60, rechts: true),
      const _Spalte('aus Lager', 60, rechts: true),
      if (produktion) const _Spalte('Produktion', 64, rechts: true),
      if (vorgemerkt) const _Spalte('vorgemerkt', 64, rechts: true),
      const _Spalte('fehlt', 60, rechts: true),
    ];
    return switch (inhalt.gliederung) {
      BestandGliederung.kunde => [
          const _Spalte('Versand', 52),
          const _Spalte('Auftrag', 60),
          const _Spalte('Art.-Nr.', 50),
          const _Spalte('Artikel', null),
          ...mengen,
          const _Spalte('Stand', 132),
        ],
      _ => [
          const _Spalte('Art.-Nr.', 52),
          _Spalte(
            inhalt.gliederung == BestandGliederung.artikel
                ? 'Artikel · Versandtag · Auftrag'
                : 'Artikel · Kunden',
            null,
          ),
          ...mengen,
          const _Spalte('Stand', 150),
        ],
    };
  }

  Map<int, pw.TableColumnWidth> breiten(List<_Spalte> spalten) => {
        for (final (i, s) in spalten.indexed) i: s.weite,
      };

  pw.Widget kopfTabelle(List<_Spalte> spalten) => pw.Table(
        border: kDruckGitter,
        columnWidths: breiten(spalten),
        children: [
          druckKopfzeile([
            for (final s in spalten) druckKopfZelle(s.titel, rechts: s.rechts),
          ]),
        ],
      );

  pw.Widget tabelle(List<_Spalte> spalten, List<pw.TableRow> zeilen) =>
      pw.Table(
        border: kDruckGitter,
        columnWidths: breiten(spalten),
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
        children: zeilen,
      );

  /// Die Mengen einer Zeile in den Spalten zwischen Text und Stand.
  List<pw.Widget> mengen(
    List<_Spalte> spalten, {
    required double bestellt,
    required double lager,
    required double produktion,
    required double vorgemerkt,
    required double offen,
    required double zuSpaet,
    bool fett = false,
    bool blass = false,
  }) {
    final farbe = blass ? kDruckGrau : PdfColors.black;
    pw.Widget menge(double kg) => kg < _schwelle
        ? druckZelle('–', rechts: true, farbe: kDruckGrau, groesse: 8.5)
        : druckZelle(
            Format.kg(kg),
            rechts: true,
            fett: fett,
            farbe: farbe,
            groesse: 8.5,
          );
    final hat = {for (final s in spalten) s.titel};
    return [
      menge(bestellt),
      menge(lager),
      if (hat.contains('Produktion')) menge(produktion),
      if (hat.contains('vorgemerkt')) menge(vorgemerkt),
      if (offen >= _schwelle)
        druckZelle(
          Format.kg(offen),
          rechts: true,
          fett: true,
          farbe: blass ? kDruckGrau : _rot,
          groesse: 8.5,
        )
      else if (zuSpaet >= _schwelle)
        druckZelle(
          'zu spät',
          rechts: true,
          fett: true,
          farbe: blass ? kDruckGrau : _orange,
          groesse: 8.5,
        )
      else
        druckZelle('–', rechts: true, farbe: kDruckGrau, groesse: 8.5),
    ];
  }

  // ── Stand in Worten ───────────────────────────────────────────────────

  static PdfColor lageFarbe(DeckungsLage lage) => switch (lage) {
        DeckungsLage.fehlt => _rot,
        DeckungsLage.zuSpaet => _orange,
        DeckungsLage.vorgemerkt => _blau,
        DeckungsLage.lagerReicht || DeckungsLage.gedeckt => _gruen,
      };

  /// Wie ein Versandtag gedeckt ist.
  static (String, PdfColor) tagStand(TagesDeckung t) {
    if (t.offenKg >= _schwelle) {
      return t.gesperrtKg >= _schwelle
          ? ('verschoben — erst in „Änderungen" klären', _lila)
          : ('noch einzuplanen', _rot);
    }
    final bis = t.zuSpaetBis;
    if (t.zuSpaetKg >= _schwelle) {
      return (
        bis == null ? 'zu spät eingeplant' : 'zu spät — fertig '
            '${Format.tagKurz(bis)}',
        _orange,
      );
    }
    if (t.vorgemerktKg >= _schwelle) {
      return ('vorgemerkt${terminText(t.vorgemerktIn)}', _blau);
    }
    if (t.knappKg >= _schwelle) {
      return ('knapp — erst am Versandtag fertig', _orange);
    }
    if (t.ausPlanungKg >= _schwelle) {
      final geplant = t.eingeplantIn;
      return (
        geplant.isEmpty
            ? 'aus Produktion'
            : 'aus Produktion · ${geplantText(geplant)}',
        _gruen,
      );
    }
    return ('aus Lager', _gruen);
  }

  /// Wie ein einzelner Auftrag gedeckt ist.
  static (String, PdfColor) zeilenStand(ZeilenDeckung z) {
    if (z.offenKg >= _schwelle) {
      return z.gesperrt
          ? ('verschoben — erst klären', _lila)
          : ('noch einzuplanen', _rot);
    }
    if (z.zuSpaetKg >= _schwelle) {
      final bis = z.zuSpaetBis;
      return (
        bis == null ? 'zu spät' : 'zu spät — fertig ${Format.tagKurz(bis)}',
        _orange,
      );
    }
    if (z.vorgemerktKg >= _schwelle) {
      return ('vorgemerkt${terminText(z.vorgemerktIn)}', _blau);
    }
    if (z.geplant) {
      return ('geplant ${geplantText(z.eingeplantIn)}', _gruen);
    }
    if (z.knappKg >= _schwelle) {
      return ('knapp — am Versandtag fertig', _orange);
    }
    return (z.ausPlanungKg >= _schwelle ? 'aus Produktion' : 'aus Lager',
        _gruen);
  }

  pw.Widget standZelle(String text, PdfColor farbe, {bool fett = false}) =>
      druckZelleMitPunkt(text, farbe, fett: fett);

  /// „Mo 02.11. · 3 Aufträge · überfällig · 1 verschoben"
  String tagText(_Artikel a, TagesDeckung t) {
    final n = t.zeilen.length;
    final verschoben = t.zeilen
        .where((z) => a.zeile.verschoben.containsKey(z.schluessel))
        .length;
    return [
      Format.tagKurz(t.tag),
      '$n ${n == 1 ? 'Auftrag' : 'Aufträge'}',
      if (t.tag.isBefore(heute)) 'überfällig',
      if (verschoben > 0) '$verschoben verschoben',
    ].join(' · ');
  }

  /// „4711 · Kunde · verschoben vom Mo 26.10. · 24 KRT"
  String auftragText(_Artikel a, ZeilenDeckung z, {bool mitBeleg = true}) {
    final p = z.position;
    final umzug = a.zeile.verschoben[z.schluessel];
    final einheit = (p.einheit ?? '').trim();
    final mitEinheit = einheit.isNotEmpty && einheit.toUpperCase() != 'KG';
    final kunde = p.debitor.trim();
    return [
      if (mitBeleg) p.beleg,
      kunde.isEmpty ? 'ohne Kunde' : kunde,
      if (umzug != null)
        'verschoben vom ${Format.tagKurz(umzug.warenausgang)}',
      if (mitEinheit) '${Format.menge(p.menge)} $einheit',
    ].join(' · ');
  }

  // ── Nach Artikel ──────────────────────────────────────────────────────

  List<pw.Widget> nachArtikel(List<_Spalte> spalten, DruckRahmen r) {
    final nummern = {
      for (final a in artikel) a.zeile.artikel.artikelnummer: a,
    };
    final reihenfolge = sortiereBestand(
      [for (final a in artikel) a.zeile],
      inhalt.sortierung,
    );
    final ergebnis = <pw.Widget>[];
    for (final z in reihenfolge) {
      final a = nummern[z.artikel.artikelnummer]!;
      final gezeigt = [
        for (final t in a.deckung.tage)
          if (tagZeigen(a, t)) t,
      ];
      if (gezeigt.isEmpty) continue;
      final zeilen = artikelZeilen(spalten, a, gezeigt);
      ergebnis.addAll(
        druckGruppe(
          [tabelle(spalten, zeilen), pw.SizedBox(height: 4)],
          zusammen: zeilen.length <= _zusammenBis,
          rahmen: r,
          frei: 80,
        ),
      );
    }
    return ergebnis;
  }

  /// Die Zeilen eines Artikels: er selbst, je nach Tiefe seine Versandtage
  /// ([gezeigt]) und Aufträge, dann Vormerkungen und Produktionen.
  List<pw.TableRow> artikelZeilen(
    List<_Spalte> spalten,
    _Artikel a,
    List<TagesDeckung> gezeigt,
  ) {
    final d = a.deckung;
    final art = a.zeile.artikel;
    final (:lage, :text) = artikelLage(d);
    final zweite = (art.bezeichnung2 ?? '').trim();
    final verschoben = a.zeile.verschoben.length;
    final unten = [
      if (zweite.isNotEmpty) zweite,
      lagerSatz(d),
      if (verschoben > 0)
        verschoben == 1
            ? '1 Auftrag verschoben'
            : '$verschoben Aufträge verschoben',
    ].join(' · ');
    final zeilen = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: kDruckZeilenFlaeche),
        children: [
          druckZelle(art.artikelnummer, fett: true),
          druckZelleMitZeile(art.bezeichnung, unten, fett: true),
          ...mengen(
            spalten,
            bestellt: d.auftragKg,
            lager: d.ausLagerKg,
            produktion: d.ausPlanungKg + d.zuSpaetKg,
            vorgemerkt: d.vorgemerktKg,
            offen: d.offenKg,
            zuSpaet: d.zuSpaetKg,
            fett: true,
          ),
          standZelle(text, lageFarbe(lage), fett: lage == DeckungsLage.fehlt),
        ],
      ),
    ];
    if (inhalt.tiefe == BestandTiefe.artikel) return zeilen;

    for (final t in gezeigt) {
      final (stand, farbe) = tagStand(t);
      zeilen.add(
        pw.TableRow(
          children: [
            pw.SizedBox(),
            druckZelleMitZeile(tagText(a, t), null, einzug: 8, groesse: 8.5),
            ...mengen(
              spalten,
              bestellt: t.kg,
              lager: t.ausLagerKg,
              produktion: t.ausPlanungKg + t.zuSpaetKg,
              vorgemerkt: t.vorgemerktKg,
              offen: t.offenKg,
              zuSpaet: t.zuSpaetKg,
            ),
            standZelle(stand, farbe),
          ],
        ),
      );
      if (inhalt.tiefe == BestandTiefe.auftraege) {
        for (final z in t.zeilen) {
          final (stand, farbe) = zeilenStand(z);
          zeilen.add(
            pw.TableRow(
              children: [
                pw.SizedBox(),
                druckZelleMitZeile(
                  auftragText(a, z),
                  null,
                  einzug: 18,
                  groesse: 8,
                  farbe: PdfColors.grey800,
                  zeilenOben: 1,
                ),
                ...mengen(
                  spalten,
                  bestellt: z.kg,
                  lager: z.ausLagerKg,
                  produktion: z.ausPlanungKg + z.zuSpaetKg,
                  vorgemerkt: z.vorgemerktKg,
                  offen: z.offenKg,
                  zuSpaet: z.zuSpaetKg,
                  blass: true,
                ),
                standZelle(stand, farbe),
              ],
            ),
          );
        }
      }
    }

    // Was nicht auf dem Ausdruck steht, wenigstens zählen.
    final weg = d.tage.length - gezeigt.length;
    if (weg > 0) {
      final kg = d.tage
          .where((t) => !gezeigt.contains(t))
          .fold<double>(0, (s, t) => s + t.kg);
      final was = inhalt.umfang == BestandUmfang.handlung
          ? 'ohne Handlungsbedarf'
          : 'rechtzeitig gedeckt';
      zeilen.add(
        leereZeile(
          spalten,
          '+ $weg ${weg == 1 ? 'Versandtag' : 'Versandtage'} $was '
          '(${Format.kg(kg)})',
        ),
      );
    }

    if (inhalt.produktionen) {
      for (final v in a.zeile.vormerkungen) {
        final termin = v.termin;
        zeilen.add(
          quellenZeile(
            spalten,
            'Vorgemerkt${termin == null ? '' : ', spätestens '
                '${Format.tagKurz(termin)}'}: ${beschreibeBezuege(v.bezuege)}',
            spalte: 'vorgemerkt',
            kg: v.offenKg,
          ),
        );
      }
      for (final z in a.zeile.zugaenge) {
        final kg = z.kg;
        final art = kg == null
            ? 'ohne Fertigmenge geplant — zählt nicht mit'
            : switch (z.art) {
                ZugangsArt.eingeplant =>
                  z.erfasst ? 'eingeplant, schon erfasst' : 'eingeplant',
                ZugangsArt.nachBericht => 'produziert nach dem Bericht',
                ZugangsArt.imLager =>
                  'vor dem Bericht produziert — steckt im Lager',
              };
        final n = z.bezuege.length;
        final fuer = switch (n) {
          0 => '',
          1 => ' · für 1 Auftrag',
          _ => ' · für $n Aufträge',
        };
        zeilen.add(
          quellenZeile(
            spalten,
            'Produktion fertig ${Format.tagKurz(z.fertigAm)}: $art$fuer',
            spalte: 'Produktion',
            kg: z.zaehlt ? kg : null,
          ),
        );
      }
    }
    return zeilen;
  }

  /// Eine Zeile nur mit grauem Text.
  pw.TableRow leereZeile(List<_Spalte> spalten, String text) => pw.TableRow(
        children: [
          pw.SizedBox(),
          druckZelleMitZeile(
            text,
            null,
            einzug: 8,
            groesse: 8,
            farbe: kDruckGrau,
            zeilenOben: 1,
          ),
          for (var i = 2; i < spalten.length; i++) pw.SizedBox(),
        ],
      );

  /// Woher die Ware kommt — eine Vormerkung oder Produktion, grau, die
  /// Menge in ihrer Spalte (gibt es die Spalte nicht, im Text).
  pw.TableRow quellenZeile(
    List<_Spalte> spalten,
    String text, {
    required String spalte,
    required double? kg,
  }) {
    final hatSpalte = spalten.any((s) => s.titel == spalte);
    final mitMenge =
        !hatSpalte && kg != null ? '$text · ${Format.kg(kg)}' : text;
    return pw.TableRow(
      children: [
        pw.SizedBox(),
        druckZelleMitZeile(
          mitMenge,
          null,
          einzug: 8,
          groesse: 8,
          farbe: kDruckGrau,
        ),
        for (final s in spalten.skip(2))
          if (s.titel == spalte && kg != null)
            druckZelle(
              Format.kg(kg),
              rechts: true,
              farbe: kDruckGrau,
              groesse: 8,
            )
          else
            pw.SizedBox(),
      ],
    );
  }

  // ── Nach Versandtag ───────────────────────────────────────────────────

  List<pw.Widget> nachVersandtag(List<_Spalte> spalten, DruckRahmen r) {
    final jeTag = <DateTime, List<(_Artikel, TagesDeckung)>>{};
    for (final a in artikel) {
      for (final t in a.deckung.tage) {
        if (tagZeigen(a, t)) (jeTag[t.tag] ??= []).add((a, t));
      }
    }
    final tage = jeTag.keys.toList()..sort();
    final ergebnis = <pw.Widget>[];
    for (final tag in tage) {
      final liste = jeTag[tag]!
        ..sort(
          (x, y) => x.$1.zeile.artikel.artikelnummer
              .compareTo(y.$1.zeile.artikel.artikelnummer),
        );
      final zeilen = <pw.TableRow>[];
      var offen = 0.0;
      for (final (a, t) in liste) {
        offen += t.offenKg;
        final (stand, farbe) = tagStand(t);
        final kunden = <String>[];
        for (final z in t.zeilen) {
          final k = z.position.debitor.trim();
          if (k.isNotEmpty && !kunden.contains(k)) kunden.add(k);
        }
        zeilen.add(
          pw.TableRow(
            children: [
              druckZelle(a.zeile.artikel.artikelnummer, fett: true),
              druckZelleMitZeile(
                a.zeile.artikel.bezeichnung,
                kunden.join(', '),
                zeilenUnten: 1,
              ),
              ...mengen(
                spalten,
                bestellt: t.kg,
                lager: t.ausLagerKg,
                produktion: t.ausPlanungKg + t.zuSpaetKg,
                vorgemerkt: t.vorgemerktKg,
                offen: t.offenKg,
                zuSpaet: t.zuSpaetKg,
              ),
              standZelle(stand, farbe),
            ],
          ),
        );
        if (inhalt.auftraegeEinzeln) {
          for (final z in t.zeilen) {
            final (stand, farbe) = zeilenStand(z);
            zeilen.add(
              pw.TableRow(
                children: [
                  pw.SizedBox(),
                  druckZelleMitZeile(
                    auftragText(a, z),
                    null,
                    einzug: 10,
                    groesse: 8,
                    farbe: PdfColors.grey800,
                    zeilenOben: 1,
                  ),
                  ...mengen(
                    spalten,
                    bestellt: z.kg,
                    lager: z.ausLagerKg,
                    produktion: z.ausPlanungKg + z.zuSpaetKg,
                    vorgemerkt: z.vorgemerktKg,
                    offen: z.offenKg,
                    zuSpaet: z.zuSpaetKg,
                    blass: true,
                  ),
                  standZelle(stand, farbe),
                ],
              ),
            );
          }
        }
      }
      final n = liste.length;
      ergebnis.addAll(
        druckGruppe(
          [
            druckLeiste(
              '${Format.wochentage[tag.weekday - 1]}, ${Format.datum(tag)}',
              rechts: [
                '$n Artikel',
                if (offen >= _schwelle) 'fehlt ${Format.kg(offen)}',
                if (tag.isBefore(heute)) 'überfällig',
              ].join(' · '),
            ),
            tabelle(spalten, zeilen),
            pw.SizedBox(height: 8),
          ],
          zusammen: zeilen.length <= _zusammenBis,
          rahmen: r,
        ),
      );
    }
    return ergebnis;
  }

  // ── Nach Kunde ────────────────────────────────────────────────────────

  List<pw.Widget> nachKunde(List<_Spalte> spalten, DruckRahmen r) {
    final jeKunde = <String, List<(_Artikel, ZeilenDeckung)>>{};
    for (final a in artikel) {
      for (final t in a.deckung.tage) {
        for (final z in t.zeilen) {
          if (!zeileZeigen(a, z)) continue;
          final k = z.position.debitor.trim();
          (jeKunde[k] ??= []).add((a, z));
        }
      }
    }
    final kunden = jeKunde.keys.toList()
      ..sort((x, y) {
        // Ohne Kunde zuletzt.
        if (x.isEmpty != y.isEmpty) return x.isEmpty ? 1 : -1;
        return x.toLowerCase().compareTo(y.toLowerCase());
      });
    final ergebnis = <pw.Widget>[];
    for (final kunde in kunden) {
      final liste = jeKunde[kunde]!
        ..sort((x, y) {
          final t = x.$2.position.warenausgang
              .compareTo(y.$2.position.warenausgang);
          if (t != 0) return t;
          final b = x.$2.position.beleg.compareTo(y.$2.position.beleg);
          if (b != 0) return b;
          return x.$1.zeile.artikel.artikelnummer
              .compareTo(y.$1.zeile.artikel.artikelnummer);
        });
      var offen = 0.0;
      final belege = <String>{};
      final zeilen = <pw.TableRow>[];
      for (final (a, z) in liste) {
        offen += z.offenKg;
        belege.add(z.position.beleg);
        final (stand, farbe) = zeilenStand(z);
        final tag = tagOhneZeit(z.position.warenausgang);
        final umzug = a.zeile.verschoben[z.schluessel];
        zeilen.add(
          pw.TableRow(
            children: [
              druckZelle(
                Format.tagKurz(tag),
                fett: tag.isBefore(heute),
                groesse: 8.5,
              ),
              druckZelle(z.position.beleg, groesse: 8.5),
              druckZelle(a.zeile.artikel.artikelnummer, fett: true),
              druckZelleMitZeile(
                a.zeile.artikel.bezeichnung,
                [
                  if (tag.isBefore(heute)) 'überfällig',
                  if (umzug != null)
                    'verschoben vom ${Format.tagKurz(umzug.warenausgang)}',
                ].join(' · '),
                zeilenUnten: 1,
              ),
              ...mengen(
                spalten,
                bestellt: z.kg,
                lager: z.ausLagerKg,
                produktion: z.ausPlanungKg + z.zuSpaetKg,
                vorgemerkt: z.vorgemerktKg,
                offen: z.offenKg,
                zuSpaet: z.zuSpaetKg,
              ),
              standZelle(stand, farbe),
            ],
          ),
        );
      }
      final n = belege.length;
      ergebnis.addAll(
        druckGruppe(
          [
            druckLeiste(
              kunde.isEmpty ? 'Ohne Kunde' : kunde,
              rechts: [
                '$n ${n == 1 ? 'Auftrag' : 'Aufträge'}',
                if (offen >= _schwelle) 'fehlt ${Format.kg(offen)}',
              ].join(' · '),
            ),
            tabelle(spalten, zeilen),
            pw.SizedBox(height: 8),
          ],
          zusammen: zeilen.length <= _zusammenBis,
          rahmen: r,
        ),
      );
    }
    return ergebnis;
  }
}
