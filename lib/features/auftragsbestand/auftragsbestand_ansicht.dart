import '../../core/database/database.dart';
import '../../core/services/auftragsbestand_deckung.dart';
import '../../core/utils/format.dart';
import 'planung_pruefen.dart' show PlanungsKonflikt;

// Der Auftragsbestand, wie die Liste und der Ausdruck ihn zeigen: je
// Artikel die Aufträge samt Deckung, die Reihenfolge und wie es um einen
// Artikel steht — in Worten.
//
// Bewusst ohne Flutter-Abhängigkeit: Der Ausdruck entsteht daraus ohne
// Oberfläche, und die Regeln lassen sich so prüfen.

/// Ein Artikel des Auftragsbestands samt Deckung aus Lager und Produktion.
class AuftragsbestandZeile {
  const AuftragsbestandZeile({
    required this.artikel,
    required this.positionen,
    required this.zugaenge,
    required this.deckung,
    this.vormerkungen = const [],
    this.verschoben = const {},
  });

  final AuftragsArtikel artikel;
  final List<AuftragsPosition> positionen;

  /// Produktionen der App für diesen Artikel — auch die, die nicht
  /// mitzählen (vor dem Bericht fertig, Menge unbekannt).
  final List<ProduktionsZugang> zugaenge;

  final ArtikelDeckung deckung;

  /// Offene Planungsaufträge für diesen Artikel: an den Planungsvorschlag
  /// übergeben, noch nicht (ganz) eingeplant.
  final List<Vormerkung> vormerkungen;

  /// Verschobene Aufträge, deren Planung noch am alten Tag hängt:
  /// Schlüssel der Zeile am neuen Tag → Konflikt. Diese Zeilen sind
  /// gesperrt, bis die Verschiebung geklärt ist.
  final Map<String, PlanungsKonflikt> verschoben;

  Set<String> get belege => {for (final p in positionen) p.beleg};
  Set<String> get kunden => {for (final p in positionen) p.debitor};

  /// Hier ist etwas zu tun: noch zu bündeln, zu spät eingeplant — oder
  /// ein verschobener Auftrag zu klären.
  bool get handlungsbedarf => !deckung.erledigt || verschoben.isNotEmpty;

  /// Eingeplante Produktionen ohne Fertigmenge — sie zählen nicht mit.
  int get ohneMenge => zugaenge
      .where((z) => z.kg == null && z.art != ZugangsArt.imLager)
      .length;
}

/// Der zuletzt eingelesene Auftragsbestand.
class AuftragsbestandAnsicht {
  const AuftragsbestandAnsicht({
    required this.zeilen,
    this.stand,
    this.von,
    this.bis,
    this.importiertAm,
    this.berichtTag,
    this.konflikte = const [],
  });

  final List<AuftragsbestandZeile> zeilen;
  final DateTime? stand;
  final DateTime? von;
  final DateTime? bis;
  final DateTime? importiertAm;

  /// Tag, gegen den die Produktionen eingeordnet wurden: der Tag des
  /// Berichts, ersatzweise der Tag des Einlesens.
  final DateTime? berichtTag;

  /// Planung, die nicht mehr zum Bericht passt — Planungsaufträge und
  /// Produktionen an verschobenen, verringerten oder entfallenen
  /// Aufträgen. Anzupassen in der Änderungsansicht.
  final List<PlanungsKonflikt> konflikte;

  bool get leer => zeilen.isEmpty;

  /// „Stand 29.10.2026, 06:12 · Warenausgang 26.10.–13.11.2026 ·
  /// eingelesen 29.10., 07:41" — leer, wenn nichts davon bekannt ist.
  String get herkunft {
    final s = stand;
    final v = von;
    final b = bis;
    final i = importiertAm;
    return [
      if (s != null) 'Stand ${Format.datum(s)}, ${Format.uhrzeit(s)}',
      if (v != null && b != null)
        'Warenausgang ${Format.datumKurz(v)}–${Format.datum(b)}',
      if (i != null)
        'eingelesen ${Format.datumKurz(i)}, ${Format.uhrzeit(i)}',
    ].join(' · ');
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Reihenfolge
// ═══════════════════════════════════════════════════════════════════════════

/// Wie die Artikel des Auftragsbestands sortiert werden.
enum BestandSortierung {
  engpass('Frühester Engpass'),
  fehlmenge('Noch zu bündeln ↓'),
  auftrag('Auftragsmenge ↓'),
  nummer('Artikelnummer');

  const BestandSortierung(this.label);
  final String label;
}

/// Erster Warenausgang, an dem bei einem Artikel etwas zu tun ist: noch zu
/// bündeln oder zu spät eingeplant.
DateTime? handlungstag(ArtikelDeckung d) {
  final offen = d.ersterOffenTag;
  final spaet = d.ersterZuSpaet;
  if (offen == null) return spaet;
  if (spaet == null) return offen;
  return offen.isBefore(spaet) ? offen : spaet;
}

/// [zeilen] in der Reihenfolge [sortierung] — eine neue Liste.
List<AuftragsbestandZeile> sortiereBestand(
  Iterable<AuftragsbestandZeile> zeilen,
  BestandSortierung sortierung,
) {
  final liste = [...zeilen];
  int nachNummer(AuftragsbestandZeile a, AuftragsbestandZeile b) =>
      a.artikel.artikelnummer.compareTo(b.artikel.artikelnummer);

  switch (sortierung) {
    case BestandSortierung.engpass:
      // Erst, was Arbeit macht — nach dem frühesten Tag, an dem etwas zu
      // bündeln ist oder zu spät kommt. Danach, was beim
      // Planungsvorschlag liegt oder gedeckt ist.
      liste.sort((a, b) {
        if (a.handlungsbedarf != b.handlungsbedarf) {
          return a.handlungsbedarf ? -1 : 1;
        }
        final x = a.deckung;
        final y = b.deckung;
        if (x.erledigt != y.erledigt) return x.erledigt ? 1 : -1;
        final ea = x.erledigt ? x.ersterEngpass : handlungstag(x);
        final eb = y.erledigt ? y.ersterEngpass : handlungstag(y);
        if (ea != null && eb != null) {
          final t = ea.compareTo(eb);
          if (t != 0) return t;
          return y.offenKg.compareTo(x.offenKg);
        }
        if (ea != null) return -1;
        if (eb != null) return 1;
        return nachNummer(a, b);
      });
    case BestandSortierung.fehlmenge:
      liste.sort((a, b) {
        final f = b.deckung.offenKg.compareTo(a.deckung.offenKg);
        return f != 0 ? f : nachNummer(a, b);
      });
    case BestandSortierung.auftrag:
      liste.sort((a, b) {
        final f = b.deckung.auftragKg.compareTo(a.deckung.auftragKg);
        return f != 0 ? f : nachNummer(a, b);
      });
    case BestandSortierung.nummer:
      liste.sort(nachNummer);
  }
  return liste;
}

// ═══════════════════════════════════════════════════════════════════════════
// In Worten
// ═══════════════════════════════════════════════════════════════════════════

/// Wie es um einen Artikel steht — das Dringendste zählt.
enum DeckungsLage {
  /// Es fehlt etwas, das weder eingeplant noch vorgemerkt ist.
  fehlt,

  /// Eingeplant, aber die Ware wird erst nach dem Versandtag fertig.
  zuSpaet,

  /// An den Planungsvorschlag übergeben, noch nicht im Board.
  vorgemerkt,

  /// Das Lager trägt alle Aufträge.
  lagerReicht,

  /// Rechtzeitig gedeckt, mit Produktion.
  gedeckt,
}

/// Die Lage eines Artikels und der Text dazu: „fehlt 120 kg ab Mo 02.11.",
/// „zu spät eingeplant · Di 03.11.", „vorgemerkt · spätestens Mi 04.11.",
/// „Lager reicht", „gedeckt mit Produktion".
({DeckungsLage lage, String text}) artikelLage(ArtikelDeckung d) {
  final offenAb = d.ersterOffenTag;
  if (offenAb != null) {
    return (
      lage: DeckungsLage.fehlt,
      text: 'fehlt ${Format.kg(d.offenKg)} ab ${Format.tagKurz(offenAb)}',
    );
  }
  final zuSpaetAb = d.ersterZuSpaet;
  if (zuSpaetAb != null) {
    return (
      lage: DeckungsLage.zuSpaet,
      text: 'zu spät eingeplant · ${Format.tagKurz(zuSpaetAb)}',
    );
  }
  if (d.vorgemerktKg >= 0.005) {
    final termin = d.fruehesterVormerkTermin;
    return (
      lage: DeckungsLage.vorgemerkt,
      text: termin == null
          ? 'vorgemerkt'
          : 'vorgemerkt · spätestens ${Format.tagKurz(termin)}',
    );
  }
  if (d.lagerReicht) {
    return (lage: DeckungsLage.lagerReicht, text: 'Lager reicht');
  }
  return (lage: DeckungsLage.gedeckt, text: 'gedeckt mit Produktion');
}

/// Wie weit der Lagerbestand reicht. Das Lager geht in Versandreihenfolge
/// an die Aufträge: Es deckt die ersten Tage ganz, höchstens einen Tag zum
/// Teil und danach nichts mehr.
String lagerSatz(ArtikelDeckung d) {
  final bestand = d.lagerKg;
  if (bestand < 0.005) return 'Kein Lagerbestand.';
  if (d.tage.isEmpty) return 'Lagerbestand ${Format.kg(bestand)}.';

  TagesDeckung? letzterGanz;
  TagesDeckung? teilweise;
  for (final t in d.tage) {
    if (t.ausLagerKg >= t.kg - 0.005) {
      letzterGanz = t;
      continue;
    }
    if (t.ausLagerKg >= 0.005) teilweise = t;
    break;
  }

  final bestandText = 'Der Lagerbestand von ${Format.kg(bestand)}';
  if (teilweise == null && identical(letzterGanz, d.tage.last)) {
    final rest = bestand - d.ausLagerKg;
    return '$bestandText deckt alle Aufträge'
        '${rest >= 0.005 ? ' — ${Format.kg(rest)} bleiben übrig' : ''}.';
  }
  final teil = teilweise == null
      ? ''
      : 'am ${Format.tagKurz(teilweise.tag)} '
          '${Format.menge(teilweise.ausLagerKg)} von '
          '${Format.kg(teilweise.kg)}';
  if (letzterGanz == null) {
    return teil.isEmpty
        ? 'Lagerbestand ${Format.kg(bestand)}.'
        : '$bestandText deckt $teil.';
  }
  return '$bestandText reicht bis ${Format.tagKurz(letzterGanz.tag)}'
      '${teil.isEmpty ? '' : ' und deckt $teil'}.';
}

/// „ · spätestens Mi 01.10." — der früheste Termin der Planungsaufträge,
/// leer ohne Termin.
String terminText(List<Vormerkung> vormerkungen) {
  DateTime? frueh;
  for (final v in vormerkungen) {
    final t = v.termin;
    if (t != null && (frueh == null || t.isBefore(frueh))) frueh = t;
  }
  return frueh == null ? '' : ' · spätestens ${Format.tagKurz(frueh)}';
}

/// „Mi 01.10." oder „Mi 01.10.–Do 02.10." je Produktion, durch Komma
/// getrennt.
String geplantText(List<ProduktionsZugang> produktionen) {
  return produktionen.map((p) {
    final von = p.beginn;
    final bis = p.fertigAm;
    return von.isAtSameMomentAs(bis)
        ? Format.tagKurz(von)
        : '${Format.tagKurz(von)}–${Format.tagKurz(bis)}';
  }).join(', ');
}
