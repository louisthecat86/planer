import 'package:drift/drift.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/constants/artikel_merkmale.dart';
import '../../core/database/database.dart';
import '../../core/services/auftragsbestand_deckung.dart'
    show
        AuftragsBezug,
        kQuelleAuftragsbestand,
        ladeBedarfsPlanung,
        restBezuege,
        teileBezuegeZu;
import '../../core/utils/zeit.dart';
import '../board/board_providers.dart';
import '../whiteboard/whiteboard_provider.dart';

// ═══════════════════════════════════════════════════════════════════════
// Einstellungen
// ═══════════════════════════════════════════════════════════════════════

/// Stellschrauben des Vorschlags. Alles, was der Anwender in der Ansicht
/// drehen kann, steht hier — der Service selbst kennt keine Vorgaben
/// außer diesen Werten.
class VorschlagEinstellungen {
  const VorschlagEinstellungen({
    this.ruestenMinuten = 20,
    this.zwischenreinigungMinuten = 45,
    this.endreinigungMinuten = 45,
    this.maxArbeitstage = 15,
    this.planeSamstag = false,
    this.gesperrteTage = const <DateTime>{},
    this.ausgeschlosseneArtikel = const <String>{},
    this.startTag,
    this.bedarfIds,
    this.moeglichstSpaet = true,
  });

  /// Umstellen zwischen zwei Artikeln ohne Regelbruch.
  final double ruestenMinuten;

  /// Reinigung, wenn eine Regel einen Wechsel erzwingt — Allergen-
  /// Rücksprung, Bio nach konventionell, gegart nach roh.
  final double zwischenreinigungMinuten;

  /// Endreinigung je Tag, an dem überhaupt etwas läuft.
  final double endreinigungMinuten;

  /// Wie weit der Vorschlag in die Zukunft reicht.
  final int maxArbeitstage;

  /// Samstag mitplanen. Sonntag bleibt außen vor.
  final bool planeSamstag;

  /// Tage, die übersprungen werden — Feiertag, fehlende Rohware,
  /// Wartung. Auf Mitternacht normalisiert.
  final Set<DateTime> gesperrteTage;

  /// Artikel (productId), die diesmal nicht eingeplant werden sollen,
  /// etwa weil die Rohware fehlt.
  final Set<String> ausgeschlosseneArtikel;

  /// Erster Tag des Vorschlags. Ohne Angabe: morgen.
  final DateTime? startTag;

  /// Die Bedarfe, die der Vorschlag einplanen soll — die Auswahl vor dem
  /// Rechnen. null heißt: alle offenen.
  final Set<String>? bedarfIds;

  /// So spät wie möglich planen, also möglichst nah an den Termin: Die
  /// Ware ist frisch, wenn sie rausgeht, und liegt nicht tagelang im
  /// Lager. Aus: so früh wie möglich — dann bleibt hinten Luft.
  final bool moeglichstSpaet;

  VorschlagEinstellungen kopieMit({
    double? ruestenMinuten,
    double? zwischenreinigungMinuten,
    double? endreinigungMinuten,
    int? maxArbeitstage,
    bool? planeSamstag,
    Set<DateTime>? gesperrteTage,
    Set<String>? ausgeschlosseneArtikel,
    DateTime? startTag,
    Set<String>? bedarfIds,
    bool? moeglichstSpaet,
  }) {
    return VorschlagEinstellungen(
      ruestenMinuten: ruestenMinuten ?? this.ruestenMinuten,
      zwischenreinigungMinuten:
          zwischenreinigungMinuten ?? this.zwischenreinigungMinuten,
      endreinigungMinuten: endreinigungMinuten ?? this.endreinigungMinuten,
      maxArbeitstage: maxArbeitstage ?? this.maxArbeitstage,
      planeSamstag: planeSamstag ?? this.planeSamstag,
      gesperrteTage: gesperrteTage ?? this.gesperrteTage,
      ausgeschlosseneArtikel:
          ausgeschlosseneArtikel ?? this.ausgeschlosseneArtikel,
      startTag: startTag ?? this.startTag,
      bedarfIds: bedarfIds ?? this.bedarfIds,
      moeglichstSpaet: moeglichstSpaet ?? this.moeglichstSpaet,
    );
  }
}

/// Die Arbeitstage eines Vorschlags: ab [VorschlagEinstellungen.startTag]
/// (ohne Angabe morgen) die nächsten
/// [VorschlagEinstellungen.maxArbeitstage] Tage, an denen gearbeitet wird.
///
/// Gerechnet wird über die Tageszahl, nie mit `Duration(days: 1)`: Am Tag
/// der Zeitumstellung hat ein Tag 25 Stunden. `add` landete dann auf
/// 23:00 desselben Tages, auf Mitternacht gekürzt wieder auf dem Tag
/// selbst — und die Schleife käme nie über den 25.10. hinaus.
List<DateTime> vorschlagsTage(VorschlagEinstellungen e, {DateTime? heute}) {
  final jetzt = heute ?? DateTime.now();
  final start = e.startTag;
  var tag = start == null
      ? DateTime(jetzt.year, jetzt.month, jetzt.day + 1)
      : DateTime(start.year, start.month, start.day);
  final tage = <DateTime>[];
  // Sicherung, falls fast alles gesperrt ist: Nach so vielen Kalendertagen
  // ist auch mit Wochenenden und Sperren jeder Zeitraum voll.
  final grenze = e.maxArbeitstage * 7 + e.gesperrteTage.length + 7;
  for (var n = 0; tage.length < e.maxArbeitstage && n < grenze; n++) {
    if (_istArbeitstag(tag, e)) tage.add(tag);
    tag = DateTime(tag.year, tag.month, tag.day + 1);
  }
  return tage;
}

bool _istArbeitstag(DateTime d, VorschlagEinstellungen e) {
  for (final g in e.gesperrteTage) {
    if (g.year == d.year && g.month == d.month && g.day == d.day) {
      return false;
    }
  }
  if (d.weekday == DateTime.sunday) return false;
  if (d.weekday == DateTime.saturday && !e.planeSamstag) return false;
  return true;
}

// ═══════════════════════════════════════════════════════════════════════
// Auswahl vor dem Rechnen
// ═══════════════════════════════════════════════════════════════════════

/// Ein offener Bedarf, wie ihn die Auswahl vor dem Rechnen zeigt.
class OffenerBedarf {
  const OffenerBedarf({
    required this.bedarfId,
    required this.productId,
    required this.artikelnummer,
    required this.bezeichnung,
    required this.offenKg,
    required this.quelle,
    required this.prioritaet,
    this.termin,
    this.notizen,
    this.auftragsBezuege = const [],
  });

  final String bedarfId;
  final String productId;
  final String artikelnummer;
  final String bezeichnung;

  /// Noch nicht eingeplante Fertigmenge in kg.
  final double offenKg;

  /// Spätester Produktionstag.
  final DateTime? termin;

  final String quelle;
  final int prioritaet;
  final String? notizen;

  /// Bei einem Planungsauftrag aus dem Auftragsbestand: die Auftragszeilen,
  /// die noch keine Produktion trägt.
  final List<AuftragsBezug> auftragsBezuege;

  bool get ausAuftragsbestand => quelle == kQuelleAuftragsbestand;
}

/// Ist [b] bis [letzterTag] fällig? Ohne Termin: ja — was keinen Termin
/// hat, kann jederzeit in eine Lücke.
bool faelligBis(OffenerBedarf b, DateTime letzterTag) {
  final t = b.termin;
  if (t == null) return true;
  return !DateTime(t.year, t.month, t.day).isAfter(letzterTag);
}

/// Die Vorauswahl: alles, was bis zum letzten Tag des Vorschlags fällig
/// ist — Überfälliges eingeschlossen —, und alles ohne Termin.
///
/// Was erst danach fällig ist, bleibt draußen, bis es jemand anhakt: Es
/// ist noch nicht dran, und wer es jetzt einplant, legt Ware auf Lager.
Set<String> vorauswahl(List<OffenerBedarf> bedarfe, List<DateTime> tage) {
  return {
    for (final b in bedarfe)
      if (b.termin == null || (tage.isNotEmpty && faelligBis(b, tage.last)))
        b.bedarfId,
  };
}

// ═══════════════════════════════════════════════════════════════════════
// Ergebnis
// ═══════════════════════════════════════════════════════════════════════

/// Warum ein Wechsel Zeit kostet — steuert die Nebenzeit und erklärt sie.
enum WechselGrund {
  /// Erster Artikel des Tages: nichts umzustellen.
  tagesstart,

  /// Gleiche Bratstraßen-Einstellung, nur anderer Artikel.
  ohneUmstellung,

  /// Andere Temperatur oder Höhe.
  umstellen,

  /// Regelbruch: Allergen-Rücksprung, Bio nach konventionell oder
  /// gegart nach roh. Kostet die volle Reinigung.
  reinigen,
}

/// Ein eingeplanter Artikel innerhalb eines Vorschlagstags.
class VorschlagPosten {
  const VorschlagPosten({
    required this.bedarfId,
    required this.productId,
    required this.artikelnummer,
    required this.bezeichnung,
    required this.mengeKg,
    required this.rohwareKg,
    required this.dauerMinuten,
    required this.ausHistorie,
    required this.nebenzeitMinuten,
    required this.wechselGrund,
    required this.begruendung,
    required this.allergenRang,
    required this.bioRang,
    required this.rohRang,
    required this.plattenTemp,
    required this.hoehe,
    required this.ausgangsMengeKg,
    this.termin,
    this.auftragsBezuege = const [],
  });

  final String? bedarfId;
  final String productId;
  final String artikelnummer;
  final String bezeichnung;

  /// Fertigmenge in kg.
  final double mengeKg;

  /// Benötigte Rohware in kg, über die Ausbeute zurückgerechnet.
  final double rohwareKg;

  /// Reine Produktionszeit in der Bratstraße.
  final double dauerMinuten;

  /// Dauer aus der Historie (Ø kg/h) statt aus gepflegten Leistungsdaten.
  final bool ausHistorie;

  /// Rüsten oder Reinigen VOR diesem Posten.
  final double nebenzeitMinuten;

  final WechselGrund wechselGrund;

  /// Klartext für die Ansicht, z.B. „Gluten, Eier · gegart · Bio".
  final String begruendung;

  // Sortierschlüssel — die Ansicht braucht sie, um nach einer Änderung
  // die Nebenzeiten und die Regelreihenfolge selbst neu zu rechnen,
  // ohne den ganzen Vorschlag neu aus der Datenbank zu holen.
  final int allergenRang;
  final int bioRang;
  final int rohRang;
  final double plattenTemp;
  final double hoehe;

  /// Menge, mit der Dauer und Rohware ursprünglich gerechnet wurden.
  /// Ändert der Anwender die Menge, werden beide daran skaliert.
  final double ausgangsMengeKg;

  /// Spätester Produktionstag des Bedarfs.
  final DateTime? termin;

  /// Auftragszeilen aus dem Auftragsbestand, für die produziert wird.
  /// Beim Übernehmen bekommt die Produktion davon so viele, wie ihre Menge
  /// bedient — der früheste Versand zuerst.
  final List<AuftragsBezug> auftragsBezuege;

  double get gesamtMinuten => dauerMinuten + nebenzeitMinuten;

  /// Liegt [tag] nach dem Termin?
  bool zuSpaetAm(DateTime tag) {
    final t = termin;
    if (t == null) return false;
    return DateTime(t.year, t.month, t.day)
        .isBefore(DateTime(tag.year, tag.month, tag.day));
  }

  VorschlagPosten kopieMit({
    double? mengeKg,
    double? rohwareKg,
    double? dauerMinuten,
    double? nebenzeitMinuten,
    WechselGrund? wechselGrund,
  }) {
    return VorschlagPosten(
      bedarfId: bedarfId,
      productId: productId,
      artikelnummer: artikelnummer,
      bezeichnung: bezeichnung,
      mengeKg: mengeKg ?? this.mengeKg,
      rohwareKg: rohwareKg ?? this.rohwareKg,
      dauerMinuten: dauerMinuten ?? this.dauerMinuten,
      ausHistorie: ausHistorie,
      nebenzeitMinuten: nebenzeitMinuten ?? this.nebenzeitMinuten,
      wechselGrund: wechselGrund ?? this.wechselGrund,
      begruendung: begruendung,
      allergenRang: allergenRang,
      bioRang: bioRang,
      rohRang: rohRang,
      plattenTemp: plattenTemp,
      hoehe: hoehe,
      ausgangsMengeKg: ausgangsMengeKg,
      termin: termin,
      auftragsBezuege: auftragsBezuege,
    );
  }

  /// Menge ändern: Dauer und Rohware skalieren linear mit.
  ///
  /// Die fixen Durchlaufzeiten der Anlagen skalieren streng genommen
  /// nicht mit — bei großen Änderungen lohnt deshalb ein „Neu berechnen",
  /// das wieder sauber über die Historie rechnet.
  VorschlagPosten mitMenge(double neueMenge) {
    // Basis ist die AUSGANGSmenge, nicht die zuletzt eingestellte: So
    // driftet der Wert nicht, wenn jemand mehrfach nachjustiert.
    final basis = ausgangsMengeKg > 0 ? ausgangsMengeKg : mengeKg;
    if (basis <= 0) return kopieMit(mengeKg: neueMenge);
    final faktor = neueMenge / basis;
    return kopieMit(
      mengeKg: neueMenge,
      rohwareKg: rohwareKg / (mengeKg > 0 ? mengeKg / basis : 1) * faktor,
      dauerMinuten:
          dauerMinuten / (mengeKg > 0 ? mengeKg / basis : 1) * faktor,
    );
  }
}

/// Ein Tag des Vorschlags.
class VorschlagTag {
  const VorschlagTag({
    required this.tag,
    required this.posten,
    required this.kapazitaetMinuten,
    required this.belegtVorherMinuten,
    required this.endreinigungMinuten,
    required this.warnungen,
  });

  final DateTime tag;
  final List<VorschlagPosten> posten;

  /// Tageskapazität der führenden Spur.
  final double kapazitaetMinuten;

  /// Was an diesem Tag schon im Board steht — bleibt unangetastet.
  final double belegtVorherMinuten;

  /// Endreinigung, sobald an diesem Tag etwas Neues läuft. 0, wenn sie
  /// aus einem früher übernommenen Vorschlag schon im Board steht.
  final double endreinigungMinuten;

  /// Hinweise, die den Tag nicht verhindern: nachgelagerte Abteilung
  /// läuft über, Merkmale fehlen, Termin überschritten.
  final List<String> warnungen;

  double get neuMinuten =>
      posten.fold<double>(0, (s, p) => s + p.gesamtMinuten) +
      (posten.isEmpty ? 0 : endreinigungMinuten);

  double get gesamtMinuten => belegtVorherMinuten + neuMinuten;

  double get auslastung =>
      kapazitaetMinuten > 0 ? gesamtMinuten / kapazitaetMinuten : 0;

  double get rohwareKg =>
      posten.fold<double>(0, (s, p) => s + p.rohwareKg);

  VorschlagTag kopieMit({
    List<VorschlagPosten>? posten,
    List<String>? warnungen,
  }) {
    return VorschlagTag(
      tag: tag,
      posten: posten ?? this.posten,
      kapazitaetMinuten: kapazitaetMinuten,
      belegtVorherMinuten: belegtVorherMinuten,
      endreinigungMinuten: endreinigungMinuten,
      warnungen: warnungen ?? this.warnungen,
    );
  }
}

/// Ein Bedarf, den der Vorschlag nicht unterbringen konnte.
class NichtPlanbar {
  const NichtPlanbar({
    required this.artikelnummer,
    required this.bezeichnung,
    required this.mengeKg,
    required this.grund,
  });

  final String artikelnummer;
  final String bezeichnung;
  final double mengeKg;
  final String grund;
}

class Planungsvorschlag {
  const Planungsvorschlag({
    required this.tage,
    required this.nichtPlanbar,
    required this.einstellungen,
  });

  /// Alle Arbeitstage des Zeitraums, auch die ohne neue Posten — so
  /// lässt sich ein Posten auf jeden Nachbartag schieben.
  final List<VorschlagTag> tage;
  final List<NichtPlanbar> nichtPlanbar;
  final VorschlagEinstellungen einstellungen;

  bool get istLeer => tage.every((t) => t.posten.isEmpty);
}

/// Rechnet Nebenzeiten und Regelreihenfolge für eine beliebige Liste von
/// Posten — auch für eine, die der Anwender selbst umsortiert hat.
///
/// Bewusst außerhalb des Service: Die Ansicht soll eine Umstellung sofort
/// durchrechnen können, ohne erneut in die Datenbank zu gehen.
class Planungsrechner {
  const Planungsrechner._();

  /// Reihenfolge nach den Produktionsregeln: Allergene aufsteigend, Bio
  /// vor konventionell, gegart vor roh, dann Temperatur und Höhe.
  static List<VorschlagPosten> nachRegeln(List<VorschlagPosten> posten) {
    return [...posten]..sort((a, b) {
        final al = a.allergenRang.compareTo(b.allergenRang);
        if (al != 0) return al;
        final bio = a.bioRang.compareTo(b.bioRang);
        if (bio != 0) return bio;
        final roh = a.rohRang.compareTo(b.rohRang);
        if (roh != 0) return roh;
        final t = a.plattenTemp.compareTo(b.plattenTemp);
        if (t != 0) return t;
        final h = a.hoehe.compareTo(b.hoehe);
        if (h != 0) return h;
        return a.artikelnummer.compareTo(b.artikelnummer);
      });
  }

  /// Nebenzeit und Wechselgrund für jeden Posten in der GEGEBENEN
  /// Reihenfolge neu bestimmen. Sortiert nicht um — wer von Hand
  /// umstellt, sieht sofort, was ihn das kostet.
  static List<VorschlagPosten> mitNebenzeiten(
    List<VorschlagPosten> posten,
    VorschlagEinstellungen e,
  ) {
    final neu = <VorschlagPosten>[];
    VorschlagPosten? vorher;
    for (final p in posten) {
      double zeit;
      WechselGrund grund;
      if (vorher == null) {
        zeit = 0;
        grund = WechselGrund.tagesstart;
      } else if (p.allergenRang < vorher.allergenRang ||
          p.bioRang < vorher.bioRang ||
          p.rohRang < vorher.rohRang) {
        zeit = e.zwischenreinigungMinuten;
        grund = WechselGrund.reinigen;
      } else if (p.plattenTemp == vorher.plattenTemp &&
          p.hoehe == vorher.hoehe) {
        zeit = 0;
        grund = WechselGrund.ohneUmstellung;
      } else {
        zeit = e.ruestenMinuten;
        grund = WechselGrund.umstellen;
      }
      final aktualisiert =
          p.kopieMit(nebenzeitMinuten: zeit, wechselGrund: grund);
      neu.add(aktualisiert);
      vorher = aktualisiert;
    }
    return neu;
  }

  /// Verstößt die gegebene Reihenfolge gegen eine Regel? Liefert die
  /// Klartexte für die Ansicht.
  static List<String> regelbrueche(List<VorschlagPosten> posten) {
    final brueche = <String>[];
    for (var i = 1; i < posten.length; i++) {
      final a = posten[i - 1], b = posten[i];
      if (b.allergenRang < a.allergenRang) {
        brueche.add('${b.artikelnummer} hat weniger Allergene als '
            '${a.artikelnummer} — Reinigung nötig');
      }
      if (b.bioRang < a.bioRang) {
        brueche.add('${b.artikelnummer} ist Bio und läuft nach '
            'konventionell — Reinigung nötig');
      }
      if (b.rohRang < a.rohRang) {
        brueche.add('${b.artikelnummer} ist gegart und läuft nach roh — '
            'Reinigung nötig');
      }
    }
    return brueche;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Kandidat (intern)
// ═══════════════════════════════════════════════════════════════════════

/// Ein planbarer Bedarf mit allem, was für Sortierung und Dauer nötig ist.
class _Kandidat {
  _Kandidat({
    required this.bedarfId,
    required this.productId,
    required this.artikelnummer,
    required this.bezeichnung,
    required this.mengeKg,
    required this.rohwareKg,
    required this.dauerMinuten,
    required this.ausHistorie,
    required this.termin,
    required this.prioritaet,
    required this.allergenRang,
    required this.bioRang,
    required this.rohRang,
    required this.plattenTemp,
    required this.hoehe,
    required this.begruendung,
    required this.fehlendeMerkmale,
    required this.bezuege,
  });

  final String? bedarfId;
  final String productId;
  final String artikelnummer;
  final String bezeichnung;
  final double mengeKg;

  /// Benötigte Rohware laut Ausbeute — die Zahl, die für die Bestellung
  /// und die Rohwarenverfügbarkeit zählt.
  final double rohwareKg;

  final double dauerMinuten;

  /// Dauer stammt aus dem Ø kg/h der Historie statt aus den gepflegten
  /// Leistungsdaten. Wird in der Ansicht ausgewiesen.
  final bool ausHistorie;

  /// Spätester Produktionstag.
  final DateTime? termin;
  final int prioritaet;

  /// 0 = allergenfrei, sonst Position in [kAllergene].
  final int allergenRang;

  /// 0 = Bio, 1 = konventionell oder unbekannt.
  final int bioRang;

  /// 0 = gegart oder unbekannt, 1 = roh.
  final int rohRang;

  /// Höchste Plattentemperatur der Bratstraße, für die Feinsortierung.
  final double plattenTemp;

  /// Höhe in mm, ebenfalls Feinsortierung.
  final double hoehe;

  final String begruendung;

  /// Nicht gepflegte Merkmale — werden als Warnung am Tag gemeldet.
  final List<String> fehlendeMerkmale;

  /// Auftragszeilen aus dem Auftragsbestand, die noch keine Produktion
  /// trägt.
  final List<AuftragsBezug> bezuege;

  /// Braucht der Wechsel von [vorher] auf diesen Posten eine Reinigung?
  bool brauchtReinigungNach(_Kandidat vorher) =>
      allergenRang < vorher.allergenRang ||
      (bioRang < vorher.bioRang) ||
      (rohRang < vorher.rohRang);

  /// Gleiche Bratstraßen-Einstellung = kein Umstellen nötig.
  bool gleicheEinstellungWie(_Kandidat vorher) =>
      plattenTemp == vorher.plattenTemp && hoehe == vorher.hoehe;
}

/// Ein offener Bedarf samt Artikel, bevor er geprüft wird.
typedef _Offen = ({
  Demand bedarf,
  Product produkt,
  double offenKg,
  List<AuftragsBezug> bezuege,
});

// ═══════════════════════════════════════════════════════════════════════
// Service
// ═══════════════════════════════════════════════════════════════════════

/// Rechnet aus dem offenen Bedarf einen Vorschlag, wie die nächsten Tage
/// aussehen könnten — ohne irgendetwas zu speichern.
///
/// **Wann** etwas läuft, entscheidet der Termin: Mit „möglichst spät"
/// (Standard) landet jeder Bedarf am letzten Arbeitstag vor seinem
/// Termin, auf dem noch Platz ist — nie danach. Ist vor dem Termin alles
/// voll, kommt er in die Restliste, statt still zu spät geplant zu
/// werden. Überfälliges und Bedarf ohne Termin kommen so früh wie möglich
/// in die Lücken.
///
/// **In welcher Reihenfolge** es innerhalb eines Tages läuft, folgt den
/// Regeln aus der Produktion, nicht einer Zielfunktion:
///
/// 1. **Allergene aufsteigend.** Ein Tag beginnt allergenfrei und
///    arbeitet sich hoch. Ein Rücksprung kostet die volle Reinigung.
/// 2. **Bio vor konventionell** — innerhalb derselben Allergenstufe.
/// 3. **Roh nach gegart**, damit rohe Ware den Tag nicht kontaminiert.
/// 4. **Ähnliche Bratstraßen-Einstellungen bündeln** — erst hier zählen
///    Plattentemperatur und Höhe, als Feinsortierung innerhalb dessen,
///    was die Regeln darüber erlauben.
///
/// Führend ist die Bratstraße: Sie ist der Engpass und die Abteilung mit
/// den verlässlichsten Daten. Was dort schon im Board steht — auch fest
/// eingeplante Produktionen aus dem Auftragsbestand —, bleibt stehen und
/// verkleinert die freie Zeit.
///
/// Der Vorschlag ist eine Rechnung, kein Plan. Geschrieben wird erst,
/// wenn der Anwender einen Tag übernimmt — dafür ist [uebernehmeTag] da.
class PlanungsvorschlagService {
  PlanungsvorschlagService(this._db);

  final AppDatabase _db;

  /// Die führende Abteilung. Sie ist der Engpass und hat die besten Daten.
  static const _fuehrend = Abteilung.bratstrasse;

  /// Minuten sind gerundet — ein Tag mit 600,0000001 von 600 Minuten ist
  /// voll, nicht übervoll.
  static const double _toleranz = 1e-6;

  /// Die offenen Bedarfe für die Auswahl vor dem Rechnen: der früheste
  /// Termin zuerst, ohne Termin am Ende.
  Future<List<OffenerBedarf>> ladeOffeneBedarfe() async {
    final offen = await _offeneBedarfe();
    final liste = [
      for (final o in offen)
        OffenerBedarf(
          bedarfId: o.bedarf.id,
          productId: o.produkt.id,
          artikelnummer: o.produkt.artikelnummer,
          bezeichnung: o.produkt.artikelbezeichnung,
          offenKg: o.offenKg,
          termin: o.bedarf.termin,
          quelle: o.bedarf.quelle,
          prioritaet: o.bedarf.prioritaet,
          notizen: o.bedarf.notizen,
          auftragsBezuege: o.bezuege,
        ),
    ];
    liste.sort((a, b) {
      final at = a.termin, bt = b.termin;
      if (at != null && bt != null) {
        final t = at.compareTo(bt);
        if (t != 0) return t;
      } else if (at != null) {
        return -1;
      } else if (bt != null) {
        return 1;
      }
      final p = b.prioritaet.compareTo(a.prioritaet);
      if (p != 0) return p;
      return a.artikelnummer.compareTo(b.artikelnummer);
    });
    return liste;
  }

  Future<Planungsvorschlag> berechne(VorschlagEinstellungen e) async {
    final tage = vorschlagsTage(e);
    final nichtPlanbar = <NichtPlanbar>[];
    final kandidaten = await _sammleKandidaten(e, nichtPlanbar);

    final kapazitaet = await _kapazitaetFuehrend();
    final belegung = await _belegungJeTag();
    final schonGereinigt = await _endreinigungImBoard(tage);

    final belegt = [for (final t in tage) belegung[_schluessel(t)] ?? 0.0];
    final endreinigung = [
      for (final t in tage)
        schonGereinigt.contains(_schluessel(t)) ? 0.0 : e.endreinigungMinuten,
    ];
    final gewaehlt =
        List<List<_Kandidat>>.generate(tage.length, (_) => <_Kandidat>[]);

    // Legt k an Tag i, wenn er dort noch Platz hat. Der Tag wird dabei
    // nach den Regeln neu sortiert, die Nebenzeiten neu gerechnet — ein
    // kleiner Artikel kann eine Lücke füllen, die ein großer sprengt.
    bool lege(int i, _Kandidat k) {
      final probe = _sortiere([...gewaehlt[i], k]);
      final summe = _summeMitNebenzeiten(probe, e, endreinigung[i]);
      if (belegt[i] + summe > kapazitaet + _toleranz) return false;
      gewaehlt[i] = probe;
      return true;
    }

    bool vorwaerts(_Kandidat k, int bis) {
      for (var i = 0; i <= bis; i++) {
        if (lege(i, k)) return true;
      }
      return false;
    }

    bool rueckwaerts(_Kandidat k, int bis) {
      for (var i = bis; i >= 0; i--) {
        if (lege(i, k)) return true;
      }
      return false;
    }

    void zurueck(_Kandidat k, String grund) => nichtPlanbar.add(
          NichtPlanbar(
            artikelnummer: k.artikelnummer,
            bezeichnung: k.bezeichnung,
            mengeKg: k.mengeKg,
            grund: grund,
          ),
        );

    final zeitraum = 'Passt nicht mehr in den Zeitraum von '
        '${e.maxArbeitstage} Arbeitstagen';
    String vorTermin(DateTime termin) =>
        'Vor dem Termin (${_datum(termin)}) ist kein Platz mehr frei — '
        'Termin prüfen oder von Hand im Board einplanen';

    // Was allein schon mehr als einen ganzen Tag braucht, passt nirgends.
    final planbar = <_Kandidat>[];
    for (final k in kandidaten) {
      final allein = _summeMitNebenzeiten([k], e, e.endreinigungMinuten);
      if (allein > kapazitaet + _toleranz) {
        zurueck(
          k,
          'Braucht allein ${Zeit.lang(allein)} — mehr als ein ganzer Tag '
          '(${Zeit.lang(kapazitaet)}). Weniger bündeln oder auf mehrere '
          'Bedarfe aufteilen',
        );
      } else if (tage.isEmpty) {
        zurueck(k, zeitraum);
      } else {
        planbar.add(k);
      }
    }

    if (tage.isNotEmpty) {
      final erster = tage.first;
      final letzter = tage.last;

      // Letzter Tag des Zeitraums, der nicht nach dem Termin liegt; -1,
      // wenn der Termin vor dem ersten Tag liegt.
      int bisTermin(DateTime termin) {
        final t = _tag(termin);
        for (var i = tage.length - 1; i >= 0; i--) {
          if (!tage[i].isAfter(t)) return i;
        }
        return -1;
      }

      bool ueberfaellig(_Kandidat k) {
        final t = k.termin;
        return t != null && _tag(t).isBefore(erster);
      }

      // Kein Platz: Liegt der Termin im Zeitraum, ist er der Grund.
      String grund(_Kandidat k) {
        final t = k.termin;
        if (t == null || ueberfaellig(k) || _tag(t).isAfter(letzter)) {
          return zeitraum;
        }
        return vorTermin(t);
      }

      if (e.moeglichstSpaet) {
        // 1. Mit Termin: vom Termin aus rückwärts, der späteste Termin
        //    zuerst. So bekommt jeder den spätesten Tag, der für ihn noch
        //    frei ist, und nimmt den früheren Terminen nichts weg, solange
        //    hinten Platz ist.
        final mitTermin = [
          for (final k in planbar)
            if (k.termin != null && !ueberfaellig(k)) k,
        ]..sort((a, b) {
            final t = b.termin!.compareTo(a.termin!);
            if (t != 0) return t;
            final p = b.prioritaet.compareTo(a.prioritaet);
            if (p != 0) return p;
            return a.artikelnummer.compareTo(b.artikelnummer);
          });
        for (final k in mitTermin) {
          if (!rueckwaerts(k, bisTermin(k.termin!))) zurueck(k, grund(k));
        }

        // 2. Überfälliges und Bedarf ohne Termin: so früh wie möglich, in
        //    die Lücken, die jetzt noch bleiben.
        final rest = [
          for (final k in planbar)
            if (k.termin == null || ueberfaellig(k)) k,
        ]..sort(_nachDringlichkeit);
        for (final k in rest) {
          if (!vorwaerts(k, tage.length - 1)) zurueck(k, grund(k));
        }
      } else {
        // So früh wie möglich — aber auch hier nie nach dem Termin.
        final alle = [...planbar]..sort(_nachDringlichkeit);
        for (final k in alle) {
          final t = k.termin;
          final bis = t == null || ueberfaellig(k)
              ? tage.length - 1
              : bisTermin(t);
          if (!vorwaerts(k, bis)) zurueck(k, grund(k));
        }
      }
    }

    return Planungsvorschlag(
      tage: [
        for (var i = 0; i < tage.length; i++)
          _baueTag(
            tag: tage[i],
            gewaehlt: gewaehlt[i],
            kapazitaet: kapazitaet,
            belegtVorher: belegt[i],
            endreinigung: endreinigung[i],
            e: e,
          ),
      ],
      nichtPlanbar: nichtPlanbar,
      einstellungen: e,
    );
  }

  /// Priorität zuerst, dann der früheste Termin, ohne Termin zuletzt.
  static int _nachDringlichkeit(_Kandidat a, _Kandidat b) {
    final p = b.prioritaet.compareTo(a.prioritaet);
    if (p != 0) return p;
    final at = a.termin, bt = b.termin;
    if (at != null && bt != null) {
      final t = at.compareTo(bt);
      if (t != 0) return t;
    } else if (at != null) {
      return -1;
    } else if (bt != null) {
      return 1;
    }
    return a.artikelnummer.compareTo(b.artikelnummer);
  }

  // ── Kandidaten ───────────────────────────────────────────────────────

  /// Alle offenen Bedarfe mit Artikel: nicht gelöscht, nicht von Hand
  /// erledigt, und die eingeplante Menge reicht noch nicht. Ein Bedarf,
  /// der zur Hälfte im Board steht, braucht nur noch den Rest — und bei
  /// einem Planungsauftrag nur noch die Zeilen, die keine Kette trägt.
  Future<List<_Offen>> _offeneBedarfe() async {
    final bedarfe = await (_db.select(_db.demands)
          ..where((d) => d.deletedAt.isNull())
          ..where((d) => d.manuellErledigt.equals(false)))
        .get();
    if (bedarfe.isEmpty) return const [];

    final produkte = {
      for (final p in await _db.select(_db.products).get()) p.id: p,
    };
    final planung = await ladeBedarfsPlanung(_db);

    final liste = <_Offen>[];
    for (final d in bedarfe) {
      final p = produkte[d.productId];
      if (p == null) continue;
      final geplant = planung[d.id];
      final offen = d.mengeKgFertig - (geplant?.kg ?? 0);
      if (offen <= 0.5) continue; // gedeckt
      liste.add(
        (
          bedarf: d,
          produkt: p,
          offenKg: offen,
          bezuege: restBezuege(
            AuftragsBezug.dekodiere(d.auftragsZeilen),
            geplant?.bezuege ?? const [],
          ),
        ),
      );
    }
    return liste;
  }

  Future<List<_Kandidat>> _sammleKandidaten(
    VorschlagEinstellungen e,
    List<NichtPlanbar> nichtPlanbar,
  ) async {
    final auswahl = e.bedarfIds;
    final kandidaten = <_Kandidat>[];
    for (final o in await _offeneBedarfe()) {
      final d = o.bedarf;
      final p = o.produkt;
      final offen = o.offenKg;
      // Nicht ausgewählt: bleibt außen vor, auch nicht in der Restliste —
      // genau das war der Sinn der Auswahl.
      if (auswahl != null && !auswahl.contains(d.id)) continue;

      final nummer = p.artikelnummer;
      final bez = p.artikelbezeichnung;

      void raus(String grund) => nichtPlanbar.add(
            NichtPlanbar(
              artikelnummer: nummer,
              bezeichnung: bez,
              mengeKg: offen,
              grund: grund,
            ),
          );

      if (e.ausgeschlosseneArtikel.contains(p.id)) {
        raus('Von Hand ausgeschlossen');
        continue;
      }
      if (!allergeneGepflegt(p.allergene)) {
        // Ohne Allergenangabe ist die Reihenfolge nicht zu verantworten.
        raus('Allergene nicht gepflegt');
        continue;
      }

      final schritte = await (_db.select(_db.productSteps)
            ..where((s) => s.productId.equals(p.id))
            ..where((s) => s.deletedAt.isNull()))
          .get();
      final fuehrendeSchritte =
          schritte.where((s) => s.abteilung == _fuehrend.dbValue).toList();
      if (fuehrendeSchritte.isEmpty) {
        raus('Kein Schritt in der ${_fuehrend.anzeigeName}');
        continue;
      }
      // Nicht vorschnell aussortieren: Die Dauer der Bratstraße kommt in
      // erster Linie aus dem Ø kg/h der Produktionshistorie, erst danach
      // aus den gepflegten Leistungsdaten. Ein Artikel ohne gepflegte
      // Referenz, aber mit erfassten Produktionen, ist also planbar.
      final plan = await berechneSchrittPlan(
        db: _db,
        productId: p.id,
        mengeKg: offen,
        startTag: DateTime.now(),
      );
      final fuehrendeBloecke = plan.schritte
          .where((s) => s.abteilungDbValue == _fuehrend.dbValue)
          .toList();
      final dauer =
          fuehrendeBloecke.fold<double>(0, (s, x) => s + x.dauerMinuten);
      final ausHistorie = fuehrendeBloecke.any((s) => s.ausHistorie);
      final platzhalter = fuehrendeBloecke.any((s) => s.platzhalter);

      if (dauer <= 0) {
        raus('Dauer in der ${_fuehrend.anzeigeName} nicht berechenbar');
        continue;
      }
      // Platzhalter heißt: weder Historie noch Leistungsdaten. Damit wäre
      // die Tagesauslastung geraten, und das ist schlimmer als ein Artikel
      // in der Restliste.
      if (platzhalter && !ausHistorie) {
        raus('Weder Produktionshistorie noch Leistungsdaten in der '
            '${_fuehrend.anzeigeName}');
        continue;
      }

      final fehlt = <String>[
        if (p.qualitaetsstufe == null) 'Qualitätsstufe',
        if (merkmaleAusText(p.verarbeitungsstufe).isEmpty)
          'Verarbeitungsstufe',
      ];
      final verarbeitung = merkmaleAusText(p.verarbeitungsstufe);
      final temp = await _hoechstePlattenTemperatur(fuehrendeSchritte);
      final hoehe = await _bratHoehe(fuehrendeSchritte);

      kandidaten.add(
        _Kandidat(
          bedarfId: d.id,
          productId: p.id,
          artikelnummer: nummer,
          bezeichnung: bez,
          mengeKg: offen,
          rohwareKg: plan.rohwareKg,
          dauerMinuten: dauer,
          ausHistorie: ausHistorie,
          termin: d.termin == null ? null : _tag(d.termin!),
          prioritaet: d.prioritaet,
          allergenRang: allergenRang(p.allergene),
          // Unbekannte Qualitätsstufe wird wie konventionell behandelt —
          // die Mehrheit ist es, und ein Bio-Artikel fiele in der Ansicht
          // über die Warnung auf.
          bioRang: p.qualitaetsstufe == 'bio' ? 0 : 1,
          rohRang: verarbeitung.contains('roh') ? 1 : 0,
          plattenTemp: temp,
          hoehe: hoehe,
          begruendung: [
            merkmaleLabel(p.allergene, kAllergene),
            if (p.qualitaetsstufe != null)
              merkmalLabel(p.qualitaetsstufe, kQualitaetsstufen)!,
            if (verarbeitung.isNotEmpty)
              merkmaleLabel(p.verarbeitungsstufe, kVerarbeitungsstufen),
            if (temp > 0) '${temp.round()}°C',
          ].where((s) => s.isNotEmpty).join(' · '),
          fehlendeMerkmale: fehlt,
          bezuege: o.bezuege,
        ),
      );
    }
    return kandidaten;
  }

  /// Höchste Plattentemperatur der Bratstraßen-Schritte. Die Werte liegen
  /// als Parametertext vor („230°C" oder „230"), deshalb wird die Zahl
  /// herausgelesen statt gecastet.
  Future<double> _hoechstePlattenTemperatur(List<ProductStep> schritte) async {
    var max = 0.0;
    for (final s in schritte) {
      final params = await (_db.select(_db.productStepParameters)
            ..where((p) => p.stepId.equals(s.id))
            ..where((p) => p.deletedAt.isNull()))
          .get();
      for (final p in params) {
        if (!p.parameterName.startsWith('Platte ')) continue;
        final v = _zahl(p.wert);
        if (v != null && v > max) max = v;
      }
    }
    return max;
  }

  Future<double> _bratHoehe(List<ProductStep> schritte) async {
    for (final s in schritte) {
      final params = await (_db.select(_db.productStepParameters)
            ..where((p) => p.stepId.equals(s.id))
            ..where((p) => p.deletedAt.isNull()))
          .get();
      for (final p in params) {
        if (!p.parameterName.startsWith('Höhe')) continue;
        final v = _zahl(p.wert);
        if (v != null) return v;
      }
    }
    return 0;
  }

  static double? _zahl(String? text) {
    if (text == null) return null;
    final m = RegExp(r'-?\d+([.,]\d+)?').firstMatch(text);
    if (m == null) return null;
    return double.tryParse(m.group(0)!.replaceAll(',', '.'));
  }

  // ── Kapazität und Belegung ───────────────────────────────────────────

  /// Tageskapazität der führenden Abteilung, inklusive gepflegter
  /// Abweichungen aus den Einstellungen.
  Future<double> _kapazitaetFuehrend() async {
    final kapazitaeten = await ladeAbteilungskapazitaeten(_db);
    final gepflegt = kapazitaeten[_fuehrend.dbValue];
    if (gepflegt != null) return gepflegt;

    final anlagen = await (_db.select(_db.machines)
          ..where((m) => m.deletedAt.isNull())
          ..where((m) => m.abteilung.equals(_fuehrend.dbValue))
          ..where((m) => m.istPlanungsressource.equals(true)))
        .get();
    if (anlagen.isEmpty) return kStandardKapazitaetMinuten;
    return anlagen.fold<double>(0, (s, m) => s + m.kapazitaetMinutenProTag);
  }

  /// Was in der führenden Abteilung je Tag schon belegt ist: bestehende
  /// Aufträge plus bereits eingetragene Rüst- und Reinigungsblöcke.
  /// Stornierte Aufträge belegen nichts.
  Future<Map<String, double>> _belegungJeTag() async {
    final belegung = <String, double>{};

    final tasks = await (_db.select(_db.productionTasks)
          ..where((t) => t.deletedAt.isNull())
          ..where((t) => t.abteilung.equals(_fuehrend.dbValue))
          ..where((t) => t.status.isNotIn(const ['storniert'])))
        .get();
    for (final t in tasks) {
      final k = _schluessel(t.datum);
      belegung[k] = (belegung[k] ?? 0) + t.geplanteDauerMinuten;
    }

    final zusatz = await (_db.select(_db.zusatzzeiten)
          ..where((z) => z.deletedAt.isNull()))
        .get();
    for (final z in zusatz) {
      if (!z.spurId.startsWith('${_fuehrend.dbValue}|')) continue;
      final k = _schluessel(z.datum);
      belegung[k] = (belegung[k] ?? 0) + z.minuten;
    }
    return belegung;
  }

  /// Tage, an denen die Endreinigung aus einem früher übernommenen
  /// Vorschlag schon im Board steht. Sie steckt dann bereits in der
  /// Belegung und darf nicht ein zweites Mal dazukommen.
  Future<Set<String>> _endreinigungImBoard(List<DateTime> tage) async {
    if (tage.isEmpty) return const <String>{};
    final ids = {
      for (final t in tage) _zusatzzeitId('reinigen', t): _schluessel(t),
    };
    final zeilen = await (_db.select(_db.zusatzzeiten)
          ..where((z) => z.id.isIn(ids.keys))
          ..where((z) => z.deletedAt.isNull()))
        .get();
    return {
      for (final z in zeilen)
        if (ids[z.id] != null) ids[z.id]!,
    };
  }

  // ── Sortierung und Nebenzeiten ───────────────────────────────────────

  /// Die Regeln aus dem Klassenkopf, in genau dieser Rangfolge.
  static List<_Kandidat> _sortiere(List<_Kandidat> liste) {
    final sortiert = [...liste]..sort((a, b) {
        final al = a.allergenRang.compareTo(b.allergenRang);
        if (al != 0) return al;
        final bio = a.bioRang.compareTo(b.bioRang);
        if (bio != 0) return bio;
        final roh = a.rohRang.compareTo(b.rohRang);
        if (roh != 0) return roh;
        final temp = a.plattenTemp.compareTo(b.plattenTemp);
        if (temp != 0) return temp;
        final h = a.hoehe.compareTo(b.hoehe);
        if (h != 0) return h;
        return a.artikelnummer.compareTo(b.artikelnummer);
      });
    return sortiert;
  }

  static double _nebenzeit(
    _Kandidat aktuell,
    _Kandidat? vorher,
    VorschlagEinstellungen e,
  ) {
    if (vorher == null) return 0;
    if (aktuell.brauchtReinigungNach(vorher)) {
      return e.zwischenreinigungMinuten;
    }
    if (aktuell.gleicheEinstellungWie(vorher)) return 0;
    return e.ruestenMinuten;
  }

  /// Produktion und Nebenzeiten eines sortierten Tages plus
  /// [endreinigung] — genau einmal je Tag.
  static double _summeMitNebenzeiten(
    List<_Kandidat> sortiert,
    VorschlagEinstellungen e,
    double endreinigung,
  ) {
    var summe = 0.0;
    _Kandidat? vorher;
    for (final k in sortiert) {
      summe += k.dauerMinuten + _nebenzeit(k, vorher, e);
      vorher = k;
    }
    return summe + endreinigung;
  }

  static VorschlagTag _baueTag({
    required DateTime tag,
    required List<_Kandidat> gewaehlt,
    required double kapazitaet,
    required double belegtVorher,
    required double endreinigung,
    required VorschlagEinstellungen e,
  }) {
    final posten = <VorschlagPosten>[];
    final warnungen = <String>{};
    _Kandidat? vorher;

    for (final k in gewaehlt) {
      final zeit = _nebenzeit(k, vorher, e);
      final grund = vorher == null
          ? WechselGrund.tagesstart
          : (zeit == e.zwischenreinigungMinuten && zeit > 0
              ? WechselGrund.reinigen
              : (zeit == 0
                  ? WechselGrund.ohneUmstellung
                  : WechselGrund.umstellen));

      posten.add(
        VorschlagPosten(
          bedarfId: k.bedarfId,
          productId: k.productId,
          artikelnummer: k.artikelnummer,
          bezeichnung: k.bezeichnung,
          mengeKg: k.mengeKg,
          rohwareKg: k.rohwareKg,
          dauerMinuten: k.dauerMinuten,
          ausHistorie: k.ausHistorie,
          nebenzeitMinuten: zeit,
          wechselGrund: grund,
          begruendung: k.begruendung,
          allergenRang: k.allergenRang,
          bioRang: k.bioRang,
          rohRang: k.rohRang,
          plattenTemp: k.plattenTemp,
          hoehe: k.hoehe,
          ausgangsMengeKg: k.mengeKg,
          termin: k.termin,
          auftragsBezuege: k.bezuege,
        ),
      );

      for (final f in k.fehlendeMerkmale) {
        warnungen.add('$f fehlt bei ${k.artikelnummer}');
      }
      final termin = k.termin;
      if (termin != null && _tag(termin).isBefore(tag)) {
        warnungen.add('Termin von ${k.artikelnummer} war am '
            '${_datum(termin)} — schon überschritten');
      }
      vorher = k;
    }

    return VorschlagTag(
      tag: tag,
      posten: posten,
      kapazitaetMinuten: kapazitaet,
      belegtVorherMinuten: belegtVorher,
      endreinigungMinuten: endreinigung,
      warnungen: warnungen.toList()..sort(),
    );
  }

  // ── Übernahme ────────────────────────────────────────────────────────

  /// Schreibt die Posten eines Vorschlagstags ins Board: je Artikel die
  /// komplette Auftragskette über alle Abteilungen, plus die Rüst- und
  /// Reinigungsblöcke als Zusatzzeit auf der führenden Spur.
  ///
  /// Die Kette trägt den Bedarf und — bei einem Planungsauftrag aus dem
  /// Auftragsbestand — die Auftragszeilen, die ihre Menge bedient. Im
  /// Auftragsbestand wechseln diese Zeilen damit von „vorgemerkt" auf
  /// „geplant". Wird die Kette im Board gelöscht, ist der Planungsauftrag
  /// wieder offen und die Zeilen wieder vorgemerkt.
  ///
  /// Wird pro Tag aufgerufen, nicht für den ganzen Vorschlag: Der
  /// Anwender entscheidet Tag für Tag.
  Future<int> uebernehmeTag(VorschlagTag t) async {
    var angelegt = 0;
    for (final p in t.posten) {
      final plan = await berechneSchrittPlan(
        db: _db,
        productId: p.productId,
        mengeKg: p.mengeKg,
        startTag: t.tag,
      );
      if (plan.schritte.isEmpty) continue;
      await erstelleTasksAusPlan(
        db: _db,
        productId: p.productId,
        schritte: plan.schritte,
        bedarfId: p.bedarfId,
        fertigMengeKg: p.mengeKg,
        auftragsBezuege: teileBezuegeZu(p.auftragsBezuege, p.mengeKg),
      );
      angelegt++;
    }

    final neben = t.posten.fold<double>(0, (s, p) => s + p.nebenzeitMinuten);
    if (neben > 0) await _ruestenDazu(t.tag, neben);
    if (t.posten.isNotEmpty && t.endreinigungMinuten > 0) {
      await _endreinigung(t.tag, t.endreinigungMinuten);
    }
    return angelegt;
  }

  /// Rüst- und Reinigungszeit zwischen den Posten. Stand von einer
  /// früheren Übernahme schon ein Block an diesem Tag, kommt die neue Zeit
  /// dazu — vorher wurde er überschrieben, und die Zeit der ersten
  /// Übernahme fiel aus der Auslastung.
  Future<void> _ruestenDazu(DateTime tag, double minuten) async {
    final id = _zusatzzeitId('ruesten', tag);
    final vorhanden = await (_db.select(_db.zusatzzeiten)
          ..where((z) => z.id.equals(id)))
        .getSingleOrNull();
    final bisher = vorhanden != null && vorhanden.deletedAt == null
        ? vorhanden.minuten
        : 0.0;
    await _db.into(_db.zusatzzeiten).insert(
          ZusatzzeitenCompanion.insert(
            id: id,
            datum: _tag(tag),
            // Sammelspur der Abteilung — dieselbe Kennung wie im Board.
            spurId: '${_fuehrend.dbValue}|',
            art: 'ruesten',
            minuten: bisher + minuten,
            notiz: const Value('Aus Planungsvorschlag'),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  /// Endreinigung — genau ein Block je Tag.
  Future<void> _endreinigung(DateTime tag, double minuten) async {
    final id = _zusatzzeitId('reinigen', tag);
    final vorhanden = await (_db.select(_db.zusatzzeiten)
          ..where((z) => z.id.equals(id))
          ..where((z) => z.deletedAt.isNull()))
        .getSingleOrNull();
    if (vorhanden != null) return;
    await _db.into(_db.zusatzzeiten).insert(
          ZusatzzeitenCompanion.insert(
            id: id,
            datum: _tag(tag),
            spurId: '${_fuehrend.dbValue}|',
            art: 'reinigen',
            minuten: minuten,
            notiz: const Value('Endreinigung aus Planungsvorschlag'),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  // ── Kleinkram ────────────────────────────────────────────────────────

  /// Feste Kennung der Blöcke, die der Vorschlag anlegt: je Tag und Art
  /// genau einer.
  static String _zusatzzeitId(String art, DateTime tag) =>
      '${_fuehrend.dbValue}-$art-${_tag(tag).millisecondsSinceEpoch}';

  static DateTime _tag(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _schluessel(DateTime d) =>
      '${d.year}-${d.month}-${d.day}';

  static const _wochentage = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

  /// „Di 06.10."
  static String _datum(DateTime d) => '${_wochentage[d.weekday - 1]} '
      '${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.';
}
