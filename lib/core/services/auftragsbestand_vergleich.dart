import '../database/database.dart';
import 'auftragsbestand_deckung.dart' show auftragsZeilenSchluessel;
import 'auftragsbestand_import_service.dart' show AuftragsbestandBericht;

// Vergleich zweier Auftragsbestände: Was ist seit dem vorigen Bericht neu,
// mehr, weniger, verschoben, entfallen oder ausgeliefert?
//
// Was die App aus einem Bericht wissen kann und was nicht: Der Bericht
// zeigt offene Auftragszeilen. Fehlt eine Zeile, die vorher da war, gibt
// es drei Erklärungen — sie wurde ausgeliefert, sie wurde storniert oder
// geändert, oder sie liegt außerhalb dessen, was der neue Bericht zeigt.
//
// Ausgeliefert und storniert lassen sich am Bericht nicht unterscheiden.
// Der Versandtag gibt aber einen guten Hinweis: Ist er vorbei, ist die
// Ware vermutlich raus. Liegt er noch vorn, ist die Zeile entfallen. Für
// die Planung ist beides dasselbe — die Menge wird nicht mehr gebraucht.
//
// Das Dritte lässt sich klären, soweit es den Zeitraum betrifft: Er steht
// im Berichtskopf (Warenausgang von … bis). Eine Zeile außerhalb ist nur
// nicht abgefragt worden. Kunden-, Artikel- oder Lagerort-Filter stehen
// dagegen nicht im Bericht. Ob ein Bericht danach aussieht, prüft
// pruefeUmfang — an den Aufträgen, die noch vorn liegen und deshalb
// normalerweise nicht verschwinden.
//
// Rein rechnend, ohne Datenbank — bis auf die beiden Lader.

// ═══════════════════════════════════════════════════════════════════════════
// Stand
// ═══════════════════════════════════════════════════════════════════════════

/// Ein Artikel eines Berichts: Bezeichnung und Lager.
class BestandsArtikel {
  const BestandsArtikel({
    required this.nummer,
    this.bezeichnung = '',
    this.bezeichnung2,
    this.lagerKg = 0,
  });

  final String nummer;
  final String bezeichnung;
  final String? bezeichnung2;
  final double lagerKg;
}

/// Eine Auftragszeile eines Berichts.
class BestandsZeile {
  const BestandsZeile({
    required this.artikelnummer,
    required this.beleg,
    required this.warenausgang,
    required this.kg,
    this.debitor = '',
  });

  final String artikelnummer;
  final String beleg;
  final String debitor;

  /// Tag des Warenausgangs, 00:00.
  final DateTime warenausgang;
  final double kg;

  /// Schlüssel innerhalb des Artikels — derselbe wie bei den Zuordnungen
  /// der Planung (Beleg und Warenausgang).
  String get schluessel => auftragsZeilenSchluessel(beleg, warenausgang);
}

/// Ein Auftragsbestand als reine Daten: der gespeicherte, der vorige oder
/// ein gerade gelesener Bericht.
class BestandsStand {
  const BestandsStand({
    this.stand,
    this.von,
    this.bis,
    this.importiertAm,
    this.artikel = const {},
    this.zeilen = const [],
  });

  /// Aus einem gelesenen, noch nicht gespeicherten Bericht.
  factory BestandsStand.ausBericht(
    AuftragsbestandBericht bericht, {
    DateTime? importiertAm,
  }) {
    return BestandsStand(
      stand: bericht.stand,
      von: bericht.von,
      bis: bericht.bis,
      importiertAm: importiertAm,
      artikel: {
        for (final a in bericht.artikel)
          a.nummer: BestandsArtikel(
            nummer: a.nummer,
            bezeichnung: a.bezeichnung,
            bezeichnung2: a.bezeichnung2.isEmpty ? null : a.bezeichnung2,
            lagerKg: a.lagerKg ?? 0,
          ),
      },
      zeilen: [
        for (final a in bericht.artikel)
          for (final p in a.positionen)
            BestandsZeile(
              artikelnummer: a.nummer,
              beleg: p.beleg,
              debitor: p.debitor,
              warenausgang: _tag(p.warenausgang),
              kg: p.kg,
            ),
      ],
    );
  }

  /// Erzeugungszeitpunkt laut Berichtskopf.
  final DateTime? stand;

  /// Filterzeitraum (Warenausgang) laut Berichtskopf.
  final DateTime? von;
  final DateTime? bis;

  /// Wann der Bericht in die App kam.
  final DateTime? importiertAm;

  final Map<String, BestandsArtikel> artikel;
  final List<BestandsZeile> zeilen;

  bool get leer => artikel.isEmpty && zeilen.isEmpty;

  /// Der Tag, an dem der Bericht entstand — ersatzweise der des Einlesens.
  DateTime? get tag {
    final s = stand ?? importiertAm;
    return s == null ? null : _tag(s);
  }

  /// Liegt [tag] im Zeitraum des Berichts? Ohne Zeitraum: ja.
  bool imZeitraum(DateTime tag) {
    final t = _tag(tag);
    final v = von;
    final b = bis;
    if (v != null && t.isBefore(_tag(v))) return false;
    if (b != null && t.isAfter(_tag(b))) return false;
    return true;
  }
}

/// Der gespeicherte Auftragsbestand aus den Zeilen seiner Tabellen.
BestandsStand bestandAusTabellen(
  List<AuftragsArtikel> artikel,
  List<AuftragsPosition> positionen,
) {
  final kopf = artikel.isEmpty ? null : artikel.first;
  return BestandsStand(
    stand: kopf?.berichtStand,
    von: kopf?.zeitraumVon,
    bis: kopf?.zeitraumBis,
    importiertAm: kopf?.importiertAm,
    artikel: {
      for (final a in artikel)
        a.artikelnummer: BestandsArtikel(
          nummer: a.artikelnummer,
          bezeichnung: a.bezeichnung,
          bezeichnung2: a.bezeichnung2,
          lagerKg: a.lagerKg,
        ),
    },
    zeilen: [
      for (final p in positionen)
        BestandsZeile(
          artikelnummer: p.artikelnummer,
          beleg: p.beleg,
          debitor: p.debitor,
          warenausgang: _tag(p.warenausgang),
          kg: p.kg,
        ),
    ],
  );
}

/// Der gespeicherte Auftragsbestand.
Future<BestandsStand> ladeBestand(AppDatabase db) async {
  final artikel = await db.select(db.auftragsbestandArtikel).get();
  final positionen = await db.select(db.auftragsbestandPositionen).get();
  return bestandAusTabellen(artikel, positionen);
}

/// Der Auftragsbestand vor dem letzten Einlesen. Leer, solange erst ein
/// Bericht eingelesen wurde.
Future<BestandsStand> ladeVorherigenBestand(AppDatabase db) async {
  final artikel = await db.select(db.auftragsbestandArtikelVorher).get();
  final zeilen = await db.select(db.auftragsbestandPositionenVorher).get();
  final kopf = artikel.isEmpty ? null : artikel.first;
  return BestandsStand(
    stand: kopf?.berichtStand,
    von: kopf?.zeitraumVon,
    bis: kopf?.zeitraumBis,
    importiertAm: kopf?.importiertAm,
    artikel: {
      for (final a in artikel)
        a.artikelnummer: BestandsArtikel(
          nummer: a.artikelnummer,
          bezeichnung: a.bezeichnung,
          bezeichnung2: a.bezeichnung2,
          lagerKg: a.lagerKg,
        ),
    },
    zeilen: [
      for (final p in zeilen)
        BestandsZeile(
          artikelnummer: p.artikelnummer,
          beleg: p.beleg,
          debitor: p.debitor,
          warenausgang: _tag(p.warenausgang),
          kg: p.kg,
        ),
    ],
  );
}

/// Die Zeilen je Artikelnummer und Schlüssel. Zeilen mit demselben
/// Schlüssel — derselbe Beleg am selben Tag — werden zu einer summiert.
Map<String, Map<String, BestandsZeile>> zeilenJeArtikel(
  Iterable<BestandsZeile> zeilen,
) {
  final ergebnis = <String, Map<String, BestandsZeile>>{};
  for (final z in zeilen) {
    final jeSchluessel = ergebnis.putIfAbsent(z.artikelnummer, () => {});
    final bisher = jeSchluessel[z.schluessel];
    jeSchluessel[z.schluessel] = BestandsZeile(
      artikelnummer: z.artikelnummer,
      beleg: (bisher ?? z).beleg.trim(),
      debitor: (bisher ?? z).debitor,
      warenausgang: z.warenausgang,
      kg: (bisher?.kg ?? 0) + z.kg,
    );
  }
  return ergebnis;
}

// ═══════════════════════════════════════════════════════════════════════════
// Änderungen
// ═══════════════════════════════════════════════════════════════════════════

/// Wie sich eine Auftragszeile seit dem vorigen Bericht geändert hat.
enum AenderungsArt {
  /// Zum ersten Mal im Bericht, an einem Tag, den schon der vorige zeigte:
  /// neu bestellt oder neu angelegt.
  neu('neu'),

  /// Zum ersten Mal im Bericht, an einem Tag, den der vorige gar nicht
  /// zeigte — etwa weil der Zeitraum jetzt weiter reicht. Ob die Zeile neu
  /// bestellt wurde, lässt sich daran nicht sagen.
  erstmals('erstmals im Zeitraum'),

  /// Dieselbe Zeile, mehr Menge.
  mehr('mehr'),

  /// Dieselbe Zeile, weniger Menge.
  weniger('weniger'),

  /// Derselbe Beleg an einem anderen Versandtag.
  verschoben('verschoben'),

  /// Nicht mehr im Bericht, obwohl der Versandtag noch kommt: storniert
  /// oder geändert.
  entfallen('entfallen'),

  /// Nicht mehr im Bericht, der Versandtag ist vorbei oder heute:
  /// vermutlich ausgeliefert.
  ausgeliefert('ausgeliefert'),

  /// Außerhalb des Zeitraums des neuen Berichts — darüber sagt er nichts.
  ausserhalb('außerhalb des Zeitraums');

  const AenderungsArt(this.label);
  final String label;

  /// Eine Änderung an den Aufträgen selbst — nicht nur, was der Zeitraum
  /// mitbringt oder was planmäßig das Haus verlassen hat. Nur die zählen
  /// in der Kurzfassung nach dem Einlesen.
  bool get wesentlich =>
      this != erstmals && this != ausgeliefert && this != ausserhalb;
}

/// Eine geänderte Auftragszeile.
class ZeilenAenderung {
  const ZeilenAenderung({
    required this.art,
    required this.artikelnummer,
    required this.beleg,
    this.debitor = '',
    this.warenausgangVorher,
    this.warenausgang,
    this.kgVorher = 0,
    this.kg = 0,
  });

  final AenderungsArt art;
  final String artikelnummer;
  final String beleg;
  final String debitor;

  /// Versandtag im vorigen Bericht. null bei einer neuen Zeile.
  final DateTime? warenausgangVorher;

  /// Versandtag im neuen Bericht. null, wenn die Zeile fehlt.
  final DateTime? warenausgang;

  final double kgVorher;
  final double kg;

  /// Der Tag, nach dem die Zeile einsortiert wird.
  DateTime get tag => warenausgang ?? warenausgangVorher!;

  double get differenzKg => kg - kgVorher;
}

/// Ein Artikel mit geänderten Auftragszeilen.
class ArtikelAenderung {
  const ArtikelAenderung({
    required this.artikelnummer,
    this.bezeichnung = '',
    this.bezeichnung2,
    this.lagerVorherKg,
    this.lagerKg,
    this.zeilen = const [],
  });

  final String artikelnummer;
  final String bezeichnung;
  final String? bezeichnung2;

  /// Lager im vorigen Bericht — null, wenn der Artikel dort fehlte.
  final double? lagerVorherKg;

  /// Lager im neuen Bericht — null, wenn der Artikel dort fehlt.
  final double? lagerKg;

  /// Nach Versandtag sortiert.
  final List<ZeilenAenderung> zeilen;

  bool get neuImBericht => lagerVorherKg == null;
  bool get nichtMehrImBericht => lagerKg == null;

  /// Hat sich das Lager geändert?
  bool get lagerGeaendert {
    final a = lagerVorherKg;
    final n = lagerKg;
    return a != null && n != null && (n - a).abs() >= _schwelle;
  }
}

/// Ein Hinweis, dass der neue Bericht nicht zum bisherigen passt.
class UmfangsHinweis {
  const UmfangsHinweis(this.text, {this.ernst = false});

  final String text;

  /// Spricht dafür, dass der Bericht gefiltert, veraltet oder verrutscht
  /// ist — vor dem Übernehmen nachfragen.
  final bool ernst;
}

/// Ergebnis von [vergleicheBestand].
class BestandsVergleich {
  const BestandsVergleich({
    required this.vorher,
    required this.neu,
    this.artikel = const [],
    this.hinweise = const [],
  });

  final BestandsStand vorher;
  final BestandsStand neu;

  /// Artikel mit geänderten Zeilen, nach Artikelnummer.
  final List<ArtikelAenderung> artikel;

  final List<UmfangsHinweis> hinweise;

  /// Es gab noch keinen vorigen Bericht.
  bool get ohneVorher => vorher.leer;

  /// Mindestens ein Hinweis spricht für einen gefilterten oder
  /// verrutschten Bericht.
  bool get zweifelhaft => hinweise.any((h) => h.ernst);

  Iterable<ZeilenAenderung> get zeilen => artikel.expand((a) => a.zeilen);

  int anzahl(AenderungsArt art) => zeilen.where((z) => z.art == art).length;

  /// Kurzfassung für eine Meldung, z.B. „12 neu · 3 mehr · 2 weniger" —
  /// nur die wesentlichen Änderungen ([AenderungsArt.wesentlich]). Leer
  /// ohne vorigen Bericht oder ohne solche Änderungen.
  String get kurzfassung {
    if (ohneVorher) return '';
    return [
      for (final art in AenderungsArt.values)
        if (art.wesentlich && anzahl(art) > 0) '${anzahl(art)} ${art.label}',
    ].join(' · ');
  }
}

/// Vergleicht den Auftragsbestand [vorher] mit [neu], Zeile für Zeile.
///
/// Eine Zeile ist Beleg + Artikel + Versandtag. Je Zeile:
/// * in beiden, andere Menge → **mehr** oder **weniger**;
/// * nur im neuen → **neu**, oder **erstmals im Zeitraum**, wenn der
///   vorige Bericht diesen Tag gar nicht zeigte;
/// * nur im alten, aber derselbe Beleg steht jetzt an einem anderen Tag →
///   **verschoben** — nur, wenn der alte Tag noch nicht vorbei ist (eine
///   vorbeigegangene Zeile ist ausgeliefert, auch wenn derselbe Beleg
///   weitere Liefertage hat) und sich die Tage eindeutig zuordnen lassen;
/// * nur im alten, im Zeitraum des neuen Berichts → **entfallen**, wenn
///   der Versandtag noch kommt, sonst **ausgeliefert**;
/// * nur im alten, außerhalb des neuen Zeitraums → **außerhalb** — darüber
///   sagt der neue Bericht nichts.
BestandsVergleich vergleicheBestand(BestandsStand vorher, BestandsStand neu) {
  final hinweise = pruefeUmfang(vorher, neu);
  if (vorher.leer) {
    return BestandsVergleich(vorher: vorher, neu: neu, hinweise: hinweise);
  }

  final alt = zeilenJeArtikel(vorher.zeilen);
  final jetzt = zeilenJeArtikel(neu.zeilen);
  final standTag = neu.tag;
  final nummern = {...alt.keys, ...jetzt.keys}.toList()..sort();

  final artikel = <ArtikelAenderung>[];
  for (final nr in nummern) {
    final a = alt[nr] ?? const <String, BestandsZeile>{};
    final j = jetzt[nr] ?? const <String, BestandsZeile>{};
    final zeilen = <ZeilenAenderung>[];

    // In beiden: Menge vergleichen.
    for (final e in j.entries) {
      final v = a[e.key];
      if (v == null) continue;
      final differenz = e.value.kg - v.kg;
      if (differenz.abs() < _schwelle) continue;
      zeilen.add(
        ZeilenAenderung(
          art: differenz > 0 ? AenderungsArt.mehr : AenderungsArt.weniger,
          artikelnummer: nr,
          beleg: e.value.beleg,
          debitor: e.value.debitor,
          warenausgangVorher: v.warenausgang,
          warenausgang: e.value.warenausgang,
          kgVorher: v.kg,
          kg: e.value.kg,
        ),
      );
    }

    final nurAlt = [
      for (final e in a.entries)
        if (!j.containsKey(e.key)) e.value,
    ];
    final nurNeu = [
      for (final e in j.entries)
        if (!a.containsKey(e.key)) e.value,
    ];

    // Verschoben: derselbe Beleg, ein anderer Tag. Als Ziel taugen nur
    // Tage, die schon der vorige Bericht zeigte — sonst war die Zeile
    // vielleicht schon immer da, nur außerhalb seines Zeitraums.
    final paare = _verschobene(
      nurAlt,
      [
        for (final n in nurNeu)
          if (vorher.imZeitraum(n.warenausgang)) n,
      ],
      standTag,
    );
    final gepaartAlt = <BestandsZeile>{for (final p in paare) p.alt};
    final gepaartNeu = <BestandsZeile>{for (final p in paare) p.neu};
    for (final p in paare) {
      zeilen.add(
        ZeilenAenderung(
          art: AenderungsArt.verschoben,
          artikelnummer: nr,
          beleg: p.neu.beleg,
          debitor: p.neu.debitor,
          warenausgangVorher: p.alt.warenausgang,
          warenausgang: p.neu.warenausgang,
          kgVorher: p.alt.kg,
          kg: p.neu.kg,
        ),
      );
    }

    for (final n in nurNeu) {
      if (gepaartNeu.contains(n)) continue;
      zeilen.add(
        ZeilenAenderung(
          art: vorher.imZeitraum(n.warenausgang)
              ? AenderungsArt.neu
              : AenderungsArt.erstmals,
          artikelnummer: nr,
          beleg: n.beleg,
          debitor: n.debitor,
          warenausgang: n.warenausgang,
          kg: n.kg,
        ),
      );
    }

    for (final o in nurAlt) {
      if (gepaartAlt.contains(o)) continue;
      final AenderungsArt art;
      if (!neu.imZeitraum(o.warenausgang)) {
        art = AenderungsArt.ausserhalb;
      } else if (standTag == null || o.warenausgang.isAfter(standTag)) {
        art = AenderungsArt.entfallen;
      } else {
        art = AenderungsArt.ausgeliefert;
      }
      zeilen.add(
        ZeilenAenderung(
          art: art,
          artikelnummer: nr,
          beleg: o.beleg,
          debitor: o.debitor,
          warenausgangVorher: o.warenausgang,
          kgVorher: o.kg,
        ),
      );
    }

    if (zeilen.isEmpty) continue;
    zeilen.sort((x, y) {
      final t = x.tag.compareTo(y.tag);
      return t != 0 ? t : x.beleg.compareTo(y.beleg);
    });
    final av = vorher.artikel[nr];
    final an = neu.artikel[nr];
    artikel.add(
      ArtikelAenderung(
        artikelnummer: nr,
        bezeichnung: an?.bezeichnung ?? av?.bezeichnung ?? '',
        bezeichnung2: an?.bezeichnung2 ?? av?.bezeichnung2,
        lagerVorherKg: av?.lagerKg,
        lagerKg: an?.lagerKg,
        zeilen: zeilen,
      ),
    );
  }

  return BestandsVergleich(
    vorher: vorher,
    neu: neu,
    artikel: artikel,
    hinweise: hinweise,
  );
}

/// Ordnet weggefallene Zeilen ([alt]) neuen Zeilen ([neu]) desselben
/// Belegs zu — als verschobenen Versandtag.
///
/// Nur alte Zeilen, deren Tag nach [standTag] liegt: Eine Zeile, deren
/// Versandtag vorbei ist, gilt als ausgeliefert, auch wenn derselbe Beleg
/// einen neuen Liefertag bekommen hat. Und nur, wenn je Beleg gleich viele
/// alte wie neue Tage übrig sind — dann paarweise in Tagesfolge. Sonst
/// lässt sich nicht sagen, welcher Tag wohin gewandert ist.
List<({BestandsZeile alt, BestandsZeile neu})> _verschobene(
  List<BestandsZeile> alt,
  List<BestandsZeile> neu,
  DateTime? standTag,
) {
  final altJeBeleg = <String, List<BestandsZeile>>{};
  for (final o in alt) {
    if (standTag != null && !o.warenausgang.isAfter(standTag)) continue;
    altJeBeleg.putIfAbsent(o.beleg, () => []).add(o);
  }
  final neuJeBeleg = <String, List<BestandsZeile>>{};
  for (final n in neu) {
    neuJeBeleg.putIfAbsent(n.beleg, () => []).add(n);
  }
  final paare = <({BestandsZeile alt, BestandsZeile neu})>[];
  for (final e in altJeBeleg.entries) {
    final neue = neuJeBeleg[e.key];
    if (neue == null || neue.length != e.value.length) continue;
    final alte = [...e.value]
      ..sort((a, b) => a.warenausgang.compareTo(b.warenausgang));
    final sortiert = [...neue]
      ..sort((a, b) => a.warenausgang.compareTo(b.warenausgang));
    for (var i = 0; i < alte.length; i++) {
      paare.add((alt: alte[i], neu: sortiert[i]));
    }
  }
  return paare;
}

// ═══════════════════════════════════════════════════════════════════════════
// Umfang: Passt der neue Bericht zum bisherigen?
// ═══════════════════════════════════════════════════════════════════════════

/// Prüft, ob [neu] denselben Ausschnitt zeigt wie [vorher] — oder ob er
/// älter, verrutscht oder gefiltert aussieht.
///
/// Der Zeitraum steht im Berichtskopf und wird direkt verglichen. Kunden-,
/// Artikel- oder Lagerort-Filter stehen nicht im Bericht; sie verraten
/// sich an den künftigen Aufträgen: Zeilen, deren Versandtag noch kommt,
/// verschwinden normalerweise nicht — höchstens einzelne werden storniert.
/// Fehlt im gemeinsamen Zeitraum die Hälfte der Kunden oder Artikel, die
/// vorher künftige Aufträge hatten, ist der Bericht sehr wahrscheinlich
/// gefiltert.
///
/// [UmfangsHinweis.ernst] heißt: vor dem Übernehmen nachfragen. Ein
/// gefilterter Bericht ließe die fehlenden Aufträge als erledigt
/// erscheinen — und das Lager gehört allen Kunden, nicht nur den
/// gezeigten.
List<UmfangsHinweis> pruefeUmfang(BestandsStand vorher, BestandsStand neu) {
  if (vorher.leer) return const [];
  final hinweise = <UmfangsHinweis>[];

  final standAlt = vorher.stand;
  final standNeu = neu.stand;
  if (standAlt != null && standNeu != null) {
    if (standNeu.isBefore(standAlt)) {
      hinweise.add(
        UmfangsHinweis(
          'Der Bericht ist älter als der bisherige: Stand '
          '${_zeitpunkt(standNeu)} statt ${_zeitpunkt(standAlt)}.',
          ernst: true,
        ),
      );
    } else if (standNeu.isAtSameMomentAs(standAlt)) {
      hinweise.add(
        const UmfangsHinweis(
          'Derselbe Bericht wie der bisherige (gleicher Stand).',
        ),
      );
    }
  }

  final vonAlt = vorher.von;
  final bisAlt = vorher.bis;
  final vonNeu = neu.von;
  final bisNeu = neu.bis;
  final standTag = neu.tag;
  if (vonAlt != null && bisAlt != null && vonNeu != null && bisNeu != null) {
    if (bisNeu.isBefore(vonAlt) || vonNeu.isAfter(bisAlt)) {
      hinweise.add(
        UmfangsHinweis(
          'Der Zeitraum ${_zeitraum(vonNeu, bisNeu)} überschneidet sich '
          'nicht mit dem bisherigen ${_zeitraum(vonAlt, bisAlt)}.',
          ernst: true,
        ),
      );
    } else if (bisNeu.isBefore(bisAlt)) {
      hinweise.add(
        UmfangsHinweis(
          'Der Bericht reicht nur bis ${_datum(bisNeu)}, der bisherige bis '
          '${_datum(bisAlt)}. Aufträge danach stehen nicht mehr drin.',
        ),
      );
    }
  }
  if (vonNeu != null && standTag != null && _tag(vonNeu).isAfter(standTag)) {
    hinweise.add(
      UmfangsHinweis(
        'Der Bericht beginnt erst am ${_datum(vonNeu)}, erstellt wurde er '
        'am ${_datum(standTag)}. Aufträge dazwischen fehlen.',
        ernst: true,
      ),
    );
  }

  // Künftige Zeilen des bisherigen Berichts, die der neue abdecken müsste.
  final kuenftig = [
    for (final z in vorher.zeilen)
      if ((standTag == null || z.warenausgang.isAfter(standTag)) &&
          neu.imZeitraum(z.warenausgang))
        z,
  ];
  if (kuenftig.isEmpty) return hinweise;

  final kundenNeu = {for (final z in neu.zeilen) z.debitor};
  final artikelNeu = {for (final z in neu.zeilen) z.artikelnummer};
  final kundenAlt = {for (final z in kuenftig) z.debitor};
  final artikelAlt = {for (final z in kuenftig) z.artikelnummer};
  final kundenWeg = kundenAlt.difference(kundenNeu);
  final artikelWeg = artikelAlt.difference(artikelNeu);

  var gefiltert = false;
  if (kundenAlt.length >= 4 && kundenWeg.length * 2 >= kundenAlt.length) {
    gefiltert = true;
    hinweise.add(
      UmfangsHinweis(
        'Von ${kundenAlt.length} Kunden mit künftigen Aufträgen fehlen '
        '${kundenWeg.length} ganz. Ist der Bericht nach Kunden gefiltert?',
        ernst: true,
      ),
    );
  }
  if (artikelAlt.length >= 4 && artikelWeg.length * 2 >= artikelAlt.length) {
    gefiltert = true;
    hinweise.add(
      UmfangsHinweis(
        'Von ${artikelAlt.length} Artikeln mit künftigen Aufträgen fehlen '
        '${artikelWeg.length} ganz. Ist der Bericht nach Artikeln oder '
        'Lagerorten gefiltert?',
        ernst: true,
      ),
    );
  }
  if (!gefiltert && kuenftig.length >= 10) {
    // Belege, die es noch gibt — auch an einem anderen Tag.
    final belegeNeu = {
      for (final z in neu.zeilen) '${z.artikelnummer}|${z.beleg.trim()}',
    };
    final weg = kuenftig
        .where(
          (z) => !belegeNeu.contains('${z.artikelnummer}|${z.beleg.trim()}'),
        )
        .length;
    if (weg * 2 >= kuenftig.length) {
      hinweise.add(
        UmfangsHinweis(
          'Von ${kuenftig.length} künftigen Auftragszeilen im gemeinsamen '
          'Zeitraum fehlen $weg. So viele Stornierungen auf einmal sind '
          'ungewöhnlich — ist der Bericht gefiltert?',
          ernst: true,
        ),
      );
    }
  }
  return hinweise;
}

// ═══════════════════════════════════════════════════════════════════════════
// Hilfen
// ═══════════════════════════════════════════════════════════════════════════

/// Unter 5 g ist Rundung, keine Änderung.
const double _schwelle = 0.005;

DateTime _tag(DateTime d) => DateTime(d.year, d.month, d.day);

String _zwei(int n) => n.toString().padLeft(2, '0');

String _datum(DateTime d) => '${_zwei(d.day)}.${_zwei(d.month)}.${d.year}';

String _zeitpunkt(DateTime d) =>
    '${_datum(d)} ${_zwei(d.hour)}:${_zwei(d.minute)}';

String _zeitraum(DateTime von, DateTime bis) =>
    '${_datum(von)}–${_datum(bis)}';
