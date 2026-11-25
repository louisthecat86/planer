import 'package:drift/drift.dart';

import '../constants/abteilungen.dart';
import '../constants/artikel_merkmale.dart';
import '../database/database.dart';
import 'produktion_erfassen_service.dart';

// Die Reihenfolge der Produktionen an einem Tag — nach den Regeln des
// Betriebs:
//
//  1. Allergene aufsteigend — sie stehen über allem.
//  2. Bio vor konventionell.
//  3. Gegart vor roh.
//  4. An der Bratstraße die Temperatur ohne Zickzack: Innerhalb eines
//     Blocks mit gleichen Allergenen, gleicher Qualität und gleichem
//     Garzustand steigt sie oder fällt sie, und der nächste Block setzt
//     dort an, wo der vorige aufgehört hat. So muss die Bratstraße nie
//     erst abkühlen und dann wieder aufheizen.
//
// Dazu der Nachlauf: wie lange die Ware nach dem Auflegen noch bis zum
// Ende der Verpackung braucht. Beim letzten Artikel des Tages steht die
// Anlage so lange, bevor gereinigt werden kann.
//
// Board und Planungsvorschlag ordnen nach denselben Regeln.

/// Was ein Artikel für die Reihenfolge mitbringt.
class ArtikelRegel {
  const ArtikelRegel({
    this.allergenRang = 0,
    this.bioRang = 1,
    this.rohRang = 0,
    this.plattenTemp = 0,
    this.hoehe = 0,
    this.allergeneGepflegt = true,
    this.nachlaufMinuten,
    this.nachlaufWerte = 0,
  });

  /// 0 = allergenfrei, sonst Position des „höchsten" Allergens.
  final int allergenRang;

  /// 0 = Bio, 1 = konventionell oder unbekannt.
  final int bioRang;

  /// 0 = gegart oder unbekannt, 1 = roh.
  final int rohRang;

  /// Höchste Plattentemperatur der Bratstraße — 0: keine.
  final double plattenTemp;

  /// Höhe der Bratstraße in mm — 0: keine.
  final double hoehe;

  /// Ob die Allergene gepflegt sind — sonst ist die Reihenfolge geraten.
  final bool allergeneGepflegt;

  /// Typischer Nachlauf in Minuten (Median der letzten Produktionen) —
  /// null: noch nie mit Ende Auflegen und Ende VPK erfasst.
  final double? nachlaufMinuten;

  /// Aus wie vielen Produktionen [nachlaufMinuten] stammt.
  final int nachlaufWerte;

  /// Der Block, in dem nur noch die Temperatur zählt.
  (int, int, int) get block => (allergenRang, bioRang, rohRang);
}

/// So viele der letzten Produktionen zählen für den Nachlauf.
const int kNachlaufLetzte = 10;

/// Der Median einer nicht leeren Liste.
double _median(List<double> werte) {
  final s = [...werte]..sort();
  final mitte = s.length ~/ 2;
  return s.length.isOdd ? s[mitte] : (s[mitte - 1] + s[mitte]) / 2;
}

/// Die Zahl aus einem Parametertext („230°C", „34 mm").
double? zahlAusText(String? text) {
  if (text == null) return null;
  final m = RegExp(r'-?\d+([.,]\d+)?').firstMatch(text);
  if (m == null) return null;
  return double.tryParse(m.group(0)!.replaceAll(',', '.'));
}

/// Typischer Nachlauf je Artikel aus seinen letzten erfassten
/// Produktionen mit beiden Uhrzeiten: (Median, Anzahl).
Map<String, (double, int)> nachlaufAusHistorie(
  Iterable<ProductionHistoryData> historie,
) {
  final jeArtikel = <String, List<(DateTime, double)>>{};
  for (final h in historie) {
    if (h.deletedAt != null) continue;
    final n = ProduktionErfassenService.nachlaufMinuten(h.endzeit, h.endeVpk);
    if (n == null) continue;
    (jeArtikel[h.productId] ??= []).add((h.datum, n));
  }
  return {
    for (final MapEntry(key: id, value: werte) in jeArtikel.entries)
      id: () {
        werte.sort((a, b) => b.$1.compareTo(a.$1));
        final letzte = [
          for (final w in werte.take(kNachlaufLetzte)) w.$2,
        ];
        return (_median(letzte), letzte.length);
      }(),
  };
}

/// Lädt die Regeln aller Artikel: Merkmale, Bratstraßen-Parameter und den
/// Nachlauf.
Future<Map<String, ArtikelRegel>> ladeArtikelRegeln(AppDatabase db) async {
  final produkte =
      await (db.select(db.products)..where((p) => p.deletedAt.isNull())).get();
  final schritte = await (db.select(db.productSteps)
        ..where((s) => s.deletedAt.isNull())
        ..where((s) => s.abteilung.equals(Abteilung.bratstrasse.dbValue)))
      .get();
  final schrittZuArtikel = {for (final s in schritte) s.id: s.productId};
  final params = schrittZuArtikel.isEmpty
      ? const <ProductStepParameter>[]
      : await (db.select(db.productStepParameters)
            ..where((p) => p.deletedAt.isNull()))
          .get();
  final temp = <String, double>{};
  final hoehe = <String, double>{};
  for (final p in params) {
    final artikel = schrittZuArtikel[p.stepId];
    if (artikel == null) continue;
    final v = zahlAusText(p.wert);
    if (v == null) continue;
    if (p.parameterName.startsWith('Platte ')) {
      if (v > (temp[artikel] ?? 0)) temp[artikel] = v;
    } else if (p.parameterName.startsWith('Höhe')) {
      hoehe.putIfAbsent(artikel, () => v);
    }
  }
  final historie = await (db.select(db.productionHistory)
        ..where((h) => h.deletedAt.isNull())
        ..where((h) => h.endeVpk.isNotNull()))
      .get();
  final nachlauf = nachlaufAusHistorie(historie);

  return {
    for (final p in produkte)
      p.id: ArtikelRegel(
        allergenRang: allergenRang(p.allergene),
        bioRang: p.qualitaetsstufe == 'bio' ? 0 : 1,
        rohRang: merkmaleAusText(p.verarbeitungsstufe).contains('roh') ? 1 : 0,
        plattenTemp: temp[p.id] ?? 0,
        hoehe: hoehe[p.id] ?? 0,
        allergeneGepflegt: allergeneGepflegt(p.allergene),
        nachlaufMinuten: nachlauf[p.id]?.$1,
        nachlaufWerte: nachlauf[p.id]?.$2 ?? 0,
      ),
  };
}

// ---------------------------------------------------------------------------
// Ordnen
// ---------------------------------------------------------------------------

int _vergleicheBlock((int, int, int) a, (int, int, int) b) {
  final x = a.$1.compareTo(b.$1);
  if (x != 0) return x;
  final y = a.$2.compareTo(b.$2);
  if (y != 0) return y;
  return a.$3.compareTo(b.$3);
}

/// [eintraege] nach den Regeln geordnet. [regel] liefert je Eintrag seine
/// Regel — null (unbekannter Artikel) gilt wie ein Artikel ohne Merkmale.
/// [name] entscheidet bei Gleichstand, damit die Reihenfolge fest ist.
///
/// Temperatur ohne Zickzack: Der erste Block steigt; jeder weitere läuft
/// in die Richtung, mit der er näher an der letzten Temperatur des
/// vorigen Blocks beginnt. Artikel ohne Temperatur stehen am Ende ihres
/// Blocks.
List<T> ordneNachRegeln<T>(
  List<T> eintraege,
  ArtikelRegel? Function(T) regel,
  String Function(T) name,
) {
  const leer = ArtikelRegel();
  ArtikelRegel r(T t) => regel(t) ?? leer;

  final bloecke = <(int, int, int), List<T>>{};
  for (final e in eintraege) {
    (bloecke[r(e).block] ??= []).add(e);
  }
  final schluessel = bloecke.keys.toList()..sort(_vergleicheBlock);

  int vergleiche(T a, T b, {required bool steigend}) {
    final ra = r(a), rb = r(b);
    final t = steigend
        ? ra.plattenTemp.compareTo(rb.plattenTemp)
        : rb.plattenTemp.compareTo(ra.plattenTemp);
    if (t != 0) return t;
    final h =
        steigend ? ra.hoehe.compareTo(rb.hoehe) : rb.hoehe.compareTo(ra.hoehe);
    if (h != 0) return h;
    return name(a).compareTo(name(b));
  }

  final ergebnis = <T>[];
  double? letzteTemp;
  for (final k in schluessel) {
    final block = bloecke[k]!;
    final mit = [
      for (final e in block)
        if (r(e).plattenTemp > 0) e,
    ];
    final ohne = [
      for (final e in block)
        if (r(e).plattenTemp <= 0) e,
    ]..sort((a, b) => name(a).compareTo(name(b)));
    final auf = [...mit]..sort((a, b) => vergleiche(a, b, steigend: true));
    var gewaehlt = auf;
    final vorher = letzteTemp;
    if (vorher != null && mit.length > 1) {
      final ab = [...mit]..sort((a, b) => vergleiche(a, b, steigend: false));
      final abstandAuf = (r(auf.first).plattenTemp - vorher).abs();
      final abstandAb = (r(ab.first).plattenTemp - vorher).abs();
      if (abstandAb < abstandAuf) gewaehlt = ab;
    }
    ergebnis
      ..addAll(gewaehlt)
      ..addAll(ohne);
    if (gewaehlt.isNotEmpty) letzteTemp = r(gewaehlt.last).plattenTemp;
  }
  return ergebnis;
}

/// Wie ernst ein Hinweis zur Reihenfolge ist.
enum RegelArt {
  /// Eine Regel ist gebrochen — dazwischen muss gereinigt werden.
  reinigung,

  /// Die Temperatur geht hin und her — kostet Zeit, ist aber erlaubt.
  temperatur,

  /// Die Allergene des Artikels sind nicht gepflegt — die Reihenfolge
  /// lässt sich nicht prüfen.
  ungeprueft,
}

/// Ein Hinweis zu einem Eintrag in der Reihenfolge.
typedef RegelHinweis = ({RegelArt art, String text});

/// Je Eintrag in der GEGEBENEN Reihenfolge: was an seiner Stelle gegen
/// die Regeln geht — null: nichts.
List<RegelHinweis?> regelHinweise<T>(
  List<T> eintraege,
  ArtikelRegel? Function(T) regel,
) {
  const leer = ArtikelRegel();
  final hinweise = <RegelHinweis?>[];
  ArtikelRegel? vorher;
  // Richtung der Temperatur im laufenden Block: 1 steigt, -1 fällt.
  var richtung = 0;
  double? letzteTemp;
  for (final e in eintraege) {
    final r = regel(e) ?? leer;
    RegelHinweis? h;
    final v = vorher;
    if (!r.allergeneGepflegt) {
      h = (
        art: RegelArt.ungeprueft,
        text: 'Allergene nicht gepflegt — Reihenfolge nicht prüfbar',
      );
    }
    if (v != null) {
      final gruende = <String>[
        if (r.allergenRang < v.allergenRang) 'weniger Allergene als davor',
        if (r.bioRang < v.bioRang) 'Bio nach konventionell',
        if (r.rohRang < v.rohRang) 'gegart nach roh',
      ];
      if (gruende.isNotEmpty) {
        h = (
          art: RegelArt.reinigung,
          text: '${gruende.join(', ')} — davor muss gereinigt werden',
        );
      }
      if (_vergleicheBlock(r.block, v.block) != 0) {
        richtung = 0;
      }
    }
    final t = r.plattenTemp;
    final lt = letzteTemp;
    if (t > 0) {
      if (lt != null && t != lt && (v == null || r.block == v.block)) {
        final neu = t > lt ? 1 : -1;
        if (richtung != 0 && neu != richtung && h == null) {
          h = (
            art: RegelArt.temperatur,
            text: t > lt
                ? 'Temperatur steigt wieder (${lt.round()} → ${t.round()} °C)'
                : 'Temperatur fällt wieder (${lt.round()} → ${t.round()} °C)',
          );
        }
        richtung = neu;
      }
      letzteTemp = t;
    }
    hinweise.add(h);
    vorher = r;
  }
  return hinweise;
}

// ---------------------------------------------------------------------------
// Reinigungsbeginn
// ---------------------------------------------------------------------------

/// Wann an einer Abteilung gereinigt wird: Arbeitsbeginn, das Ziel für
/// den Reinigungsbeginn und der späteste.
class ReinigungsVorgabe {
  const ReinigungsVorgabe({
    required this.arbeitsbeginn,
    required this.ziel,
    required this.spaetestens,
  });

  /// Minuten nach Mitternacht.
  final int arbeitsbeginn;
  final int ziel;
  final int spaetestens;

  /// „06:15;15:00;15:30" — so steht es in den Einstellungen.
  String get alsText =>
      '${uhrzeit(arbeitsbeginn)};${uhrzeit(ziel)};${uhrzeit(spaetestens)}';

  static ReinigungsVorgabe? ausText(String? text) {
    final teile = (text ?? '').split(';');
    if (teile.length != 3) return null;
    final a = ProduktionErfassenService.zeitZuMinuten(teile[0]);
    final z = ProduktionErfassenService.zeitZuMinuten(teile[1]);
    final s = ProduktionErfassenService.zeitZuMinuten(teile[2]);
    if (a == null || z == null || s == null || z > s || a >= z) return null;
    return ReinigungsVorgabe(arbeitsbeginn: a, ziel: z, spaetestens: s);
  }
}

/// Die Vorgabe der Bratstraße, solange niemand eine andere einträgt:
/// Arbeitsbeginn 6:15, Reinigung ab 15:00, spätestens 15:30.
const ReinigungsVorgabe kBratstrasseVorgabe = ReinigungsVorgabe(
  arbeitsbeginn: 6 * 60 + 15,
  ziel: 15 * 60,
  spaetestens: 15 * 60 + 30,
);

/// Schlüssel der Vorgabe einer Abteilung in den Einstellungen.
String reinigungsSchluessel(Abteilung a) => 'reinigung_${a.dbValue}';

/// „06:15" aus Minuten nach Mitternacht.
String uhrzeit(num minuten) {
  final m = minuten.round() % (24 * 60);
  return '${(m ~/ 60).toString().padLeft(2, '0')}:'
      '${(m % 60).toString().padLeft(2, '0')}';
}

/// Lädt die Vorgaben je Abteilung — die Bratstraße hat immer eine.
Future<Map<Abteilung, ReinigungsVorgabe>> ladeReinigungsVorgaben(
  AppDatabase db,
) async {
  final zeilen = await (db.select(db.appSettings)
        ..where((s) => s.key.like('reinigung_%')))
      .get();
  final ergebnis = <Abteilung, ReinigungsVorgabe>{
    Abteilung.bratstrasse: kBratstrasseVorgabe,
  };
  for (final z in zeilen) {
    for (final a in Abteilung.values) {
      if (z.key != reinigungsSchluessel(a)) continue;
      final v = ReinigungsVorgabe.ausText(z.value);
      if (v != null) {
        ergebnis[a] = v;
      } else if (z.value.isEmpty) {
        ergebnis.remove(a);
      }
    }
  }
  return ergebnis;
}

/// Speichert die Vorgabe einer Abteilung — null: keine (bei der
/// Bratstraße heißt das: ausgeschaltet).
Future<void> speichereReinigungsVorgabe(
  AppDatabase db,
  Abteilung abteilung,
  ReinigungsVorgabe? vorgabe,
) async {
  await db.into(db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: reinigungsSchluessel(abteilung),
          value: vorgabe?.alsText ?? '',
        ),
      );
}

/// Wie der Reinigungsbeginn zur Vorgabe steht.
enum ReinigungsStand { gut, knapp, zuSpaet }

/// Wann an einer Anlage gereinigt werden kann: Arbeitsbeginn (oder die
/// Startzeit des ersten Auftrags) plus Aufträge und Nebenzeiten, plus der
/// Nachlauf des letzten Artikels.
class ReinigungsPlan {
  const ReinigungsPlan({
    required this.produktionsEnde,
    required this.nachlaufMinuten,
    required this.nachlaufBekannt,
    required this.vorgabe,
  });

  /// Minuten nach Mitternacht, an denen der letzte Artikel aufgelegt ist.
  final double produktionsEnde;

  /// Der Nachlauf des letzten Artikels — 0, wenn unbekannt.
  final double nachlaufMinuten;
  final bool nachlaufBekannt;
  final ReinigungsVorgabe vorgabe;

  /// Minuten nach Mitternacht, ab denen gereinigt werden kann.
  double get reinigungAb => produktionsEnde + nachlaufMinuten;

  ReinigungsStand get stand => reinigungAb <= vorgabe.ziel
      ? ReinigungsStand.gut
      : reinigungAb <= vorgabe.spaetestens
          ? ReinigungsStand.knapp
          : ReinigungsStand.zuSpaet;

  /// Wie viel zu spät gegenüber dem spätesten Beginn — 0 bei rechtzeitig.
  double get ueberzogen =>
      reinigungAb > vorgabe.spaetestens ? reinigungAb - vorgabe.spaetestens : 0;
}

/// Der Reinigungsplan einer Anlage an einem Tag — null ohne Aufträge.
/// [startZeit] ist die Startzeit des ersten Auftrags, falls eingetragen.
ReinigungsPlan? reinigungsPlan({
  required ReinigungsVorgabe vorgabe,
  required double belegtOhneNachlauf,
  required bool hatAuftraege,
  required double? nachlaufLetzter,
  String? startZeit,
}) {
  if (!hatAuftraege) return null;
  final start = ProduktionErfassenService.zeitZuMinuten(startZeit) ??
      vorgabe.arbeitsbeginn;
  return ReinigungsPlan(
    produktionsEnde: start + belegtOhneNachlauf,
    nachlaufMinuten: nachlaufLetzter ?? 0,
    nachlaufBekannt: nachlaufLetzter != null,
    vorgabe: vorgabe,
  );
}
