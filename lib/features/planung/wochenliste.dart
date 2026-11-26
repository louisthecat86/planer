import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import '../../core/services/auftragsbestand_deckung.dart'
    show ladeBedarfsPlanung;
import '../whiteboard/produktions_mengen.dart'
    show Verhaeltnis, ausbeuteFuer, fleischanteilFuer;
import '../whiteboard/whiteboard_provider.dart' show berechneSchrittPlan;

// ═══════════════════════════════════════════════════════════════════════
// Wochenliste
//
// Die Liste, in die der Produktionsleiter untereinander schreibt, was er
// in den nächsten Tagen machen möchte — Artikel, Wunschtag und EINE
// Menge: Rohware, Fleischeinwaage oder Fertigware. Die anderen beiden
// rechnet der Planer aus, dazu die Dauer je Abteilung.
//
// Jede Zeile ist ein ganz normaler Bedarf mit der Herkunft „Wochenliste".
// Bedarfsliste, Deckung und Erledigt funktionieren dadurch unverändert,
// und der Planungsvorschlag plant die Zeilen wie jeden anderen Bedarf —
// nur dass der Termin hier ein Wunschtag ist und keine Frist.
//
// Welches der drei Felder eingetragen wurde, steht in `app_settings`:
// Der Bedarf kennt nur die Fertigware, der Produktionsleiter soll aber
// seine 270 kg Rohware wiedersehen und nicht 269,8.
// ═══════════════════════════════════════════════════════════════════════

/// Herkunft eines Bedarfs aus der Wochenliste.
const String kQuelleWochenliste = 'wochenliste';

/// Schlüssel in `app_settings`: welches Feld je Zeile eingetragen wurde.
const String kWochenlisteEingabenSchluessel = 'wochenliste_eingaben';

/// Das Feld, in das die Menge einer Zeile eingetragen wurde.
enum MengenFeld {
  roh('Rohware'),
  fleisch('Fleischeinwaage'),
  fertig('Fertigware');

  const MengenFeld(this.text);

  final String text;

  static MengenFeld? ausName(Object? name) {
    for (final f in values) {
      if (f.name == name) return f;
    }
    return null;
  }
}

/// Die drei Mengen einer Zeile. Was sich nicht rechnen lässt, ist null —
/// [fehlt] sagt dann, warum.
class Mengen {
  const Mengen({this.roh, this.fleisch, this.fertig, this.fehlt});

  final double? roh;
  final double? fleisch;
  final double? fertig;

  /// Warum die Fertigware fehlt — ohne sie lässt sich nichts planen.
  final String? fehlt;

  /// Mit Fertigware lässt sich planen: Der Bedarf rechnet in Fertigware.
  bool get planbar => fertig != null && fertig! > 0;

  double? von(MengenFeld f) => switch (f) {
        MengenFeld.roh => roh,
        MengenFeld.fleisch => fleisch,
        MengenFeld.fertig => fertig,
      };
}

/// Rechnet aus [kg] im Feld [feld] die beiden anderen Mengen.
///
/// [ausbeute] ist Fertigware je kg Rohware, [fleischanteil] Fleisch je kg
/// Rohware — beides wie in der Planung und im Fenster der Produktion.
/// Fehlt eins davon, bleibt die Menge offen, statt geraten zu werden.
/// Fertigware ohne Ausbeute ist trotzdem planbar: Die Planung rechnet die
/// Rohware dann eins zu eins, wie bei jedem anderen Bedarf.
Mengen rechneMengen(
  MengenFeld feld,
  double kg, {
  double? ausbeute,
  double? fleischanteil,
}) {
  final a = ausbeute != null && ausbeute > 0 ? ausbeute : null;
  final f = fleischanteil != null && fleischanteil > 0 ? fleischanteil : null;
  const ohneAusbeute = 'Ausbeute unbekannt — bitte Fertigware eintragen';
  switch (feld) {
    case MengenFeld.fertig:
      final roh = a == null ? null : kg / a;
      return Mengen(
        fertig: kg,
        roh: roh,
        fleisch: roh != null && f != null ? roh * f : null,
      );
    case MengenFeld.roh:
      return Mengen(
        roh: kg,
        fleisch: f == null ? null : kg * f,
        fertig: a == null ? null : kg * a,
        fehlt: a == null ? ohneAusbeute : null,
      );
    case MengenFeld.fleisch:
      if (f == null) {
        return Mengen(
          fleisch: kg,
          fehlt: 'Fleischanteil unbekannt — bitte Rohware oder Fertigware '
              'eintragen',
        );
      }
      final roh = kg / f;
      return Mengen(
        fleisch: kg,
        roh: roh,
        fertig: a == null ? null : roh * a,
        fehlt: a == null ? ohneAusbeute : null,
      );
  }
}

/// Eine Mengenangabe mit einfacher Rechnung: „270", „270,5", „27*10",
/// „100+80" — wie im Taschenrechner, Punkt vor Strich. Ein Punkt vor
/// genau drei Ziffern ist der Tausenderpunkt („1.200"), das Komma das
/// Dezimalzeichen. null, wenn der Text keine Zahl ergibt.
double? rechneMenge(String text) {
  var t = text.replaceAll(' ', '').replaceAll(RegExp('[x×X]'), '*');
  if (t.isEmpty) return null;
  t = t.replaceAll(RegExp(r'(?<=\d)\.(?=\d{3}(?!\d))'), '');
  t = t.replaceAll(',', '.');
  final tokens = <String>[];
  var pos = 0;
  for (final m in RegExp(r'\d+(?:\.\d+)?|\.\d+|[+\-*/]').allMatches(t)) {
    if (m.start != pos) return null;
    tokens.add(m.group(0)!);
    pos = m.end;
  }
  if (pos != t.length || tokens.isEmpty) return null;

  var i = 0;
  double? zahl() {
    var vorzeichen = 1.0;
    if (i < tokens.length && (tokens[i] == '-' || tokens[i] == '+')) {
      if (tokens[i] == '-') vorzeichen = -1;
      i++;
    }
    if (i >= tokens.length) return null;
    final z = double.tryParse(tokens[i]);
    if (z == null) return null;
    i++;
    return vorzeichen * z;
  }

  double? produkt() {
    final erste = zahl();
    if (erste == null) return null;
    var w = erste;
    while (i < tokens.length && (tokens[i] == '*' || tokens[i] == '/')) {
      final op = tokens[i++];
      final z = zahl();
      if (z == null) return null;
      if (op == '/') {
        if (z == 0) return null;
        w = w / z;
      } else {
        w = w * z;
      }
    }
    return w;
  }

  final erstes = produkt();
  if (erstes == null) return null;
  var summe = erstes;
  while (i < tokens.length) {
    final op = tokens[i++];
    if (op != '+' && op != '-') return null;
    final w = produkt();
    if (w == null) return null;
    summe = op == '+' ? summe + w : summe - w;
  }
  return summe;
}

// ═══════════════════════════════════════════════════════════════════════
// Was eingetragen wurde
// ═══════════════════════════════════════════════════════════════════════

/// Das eingetragene Feld einer Zeile und die Fertigware, die beim
/// Speichern daraus wurde.
class WochenEingabe {
  const WochenEingabe({
    required this.feld,
    required this.kg,
    required this.fertigKg,
  });

  final MengenFeld feld;
  final double kg;

  /// Fertigware beim Speichern. Steht im Bedarf eine andere Menge, wurde
  /// er inzwischen in der Bedarfsliste geändert — dann gilt die.
  final double fertigKg;

  Map<String, Object> alsJson() => {
        'feld': feld.name,
        'kg': kg,
        'fertig': fertigKg,
      };

  static WochenEingabe? ausJson(Object? j) {
    if (j is! Map) return null;
    final feld = MengenFeld.ausName(j['feld']);
    final kg = j['kg'], fertig = j['fertig'];
    if (feld == null || kg is! num || fertig is! num) return null;
    return WochenEingabe(
      feld: feld,
      kg: kg.toDouble(),
      fertigKg: fertig.toDouble(),
    );
  }
}

/// Liest die Eingaben aus `app_settings` — Unlesbares fällt weg.
Map<String, WochenEingabe> eingabenAusText(String? text) {
  if (text == null || text.isEmpty) return {};
  try {
    final j = jsonDecode(text);
    if (j is! Map) return {};
    return {
      for (final e in j.entries)
        if (WochenEingabe.ausJson(e.value) case final w?) '${e.key}': w,
    };
  } catch (_) {
    return {};
  }
}

String eingabenAlsText(Map<String, WochenEingabe> eingaben) => jsonEncode({
      for (final e in eingaben.entries) e.key: e.value.alsJson(),
    });

// ═══════════════════════════════════════════════════════════════════════
// Zeilen
// ═══════════════════════════════════════════════════════════════════════

/// Eine gespeicherte Zeile der Wochenliste.
class WochenZeile {
  const WochenZeile({
    required this.bedarfId,
    required this.productId,
    required this.artikelnummer,
    required this.bezeichnung,
    required this.feld,
    required this.kg,
    required this.fertigKg,
    this.wunschtag,
    this.imBoardKg = 0,
  });

  final String bedarfId;
  final String productId;
  final String artikelnummer;
  final String bezeichnung;

  /// Der Tag, an dem der Artikel laufen soll — ein Wunsch, keine Frist.
  final DateTime? wunschtag;

  final MengenFeld feld;
  final double kg;

  /// Fertigware des Bedarfs.
  final double fertigKg;

  /// Davon schon ins Board übernommen.
  final double imBoardKg;
}

/// Zeit je Abteilung für eine Zeile — dieselbe Rechnung wie im
/// Planungsvorschlag und beim Einplanen von Hand.
class ZeilenDauer {
  const ZeilenDauer(this.minuten, {this.geschaetzt = false});

  /// In der Reihenfolge der Abteilungen.
  final Map<Abteilung, double> minuten;

  /// Weder Produktionen noch Leistungsdaten: Die Zeit ist ein Platzhalter.
  final bool geschaetzt;

  double get gesamt => minuten.values.fold(0.0, (s, m) => s + m);

  static const leer = ZeilenDauer({});
}

/// Summe je Abteilung über alle Zeilen, in der Reihenfolge der
/// Abteilungen.
Map<Abteilung, double> summeJeAbteilung(Iterable<ZeilenDauer> dauern) {
  final summe = <Abteilung, double>{};
  for (final d in dauern) {
    for (final e in d.minuten.entries) {
      summe[e.key] = (summe[e.key] ?? 0) + e.value;
    }
  }
  return {
    for (final a in Abteilung.values)
      if (summe[a] case final m? when m > 0) a: m,
  };
}

/// Ausbeute und Fleischanteil eines Artikels — woraus die Wochenliste
/// die Mengen umrechnet.
class ArtikelVerhaeltnisse {
  const ArtikelVerhaeltnisse({this.ausbeute, this.fleischanteil});

  final Verhaeltnis? ausbeute;
  final Verhaeltnis? fleischanteil;

  Mengen rechne(MengenFeld feld, double kg) => rechneMengen(
        feld,
        kg,
        ausbeute: ausbeute?.wert,
        fleischanteil: fleischanteil?.wert,
      );
}

/// Lädt, speichert und löscht die Zeilen der Wochenliste.
class WochenlisteService {
  WochenlisteService(this._db);

  final AppDatabase _db;

  /// Die offenen Zeilen: nicht gelöscht, nicht erledigt und noch nicht
  /// ganz im Board. Wunschtag zuerst, ohne Wunschtag zuletzt.
  Future<List<WochenZeile>> lade() async {
    final bedarfe = await (_db.select(_db.demands)
          ..where((d) => d.quelle.equals(kQuelleWochenliste))
          ..where((d) => d.deletedAt.isNull())
          ..where((d) => d.manuellErledigt.equals(false))
          ..orderBy([(d) => OrderingTerm.asc(d.createdAt)]))
        .get();
    if (bedarfe.isEmpty) return const [];
    final produkte = {
      for (final p in await (_db.select(_db.products)
            ..where((p) => p.id.isIn({for (final d in bedarfe) d.productId})))
          .get())
        p.id: p,
    };
    final planung = await ladeBedarfsPlanung(_db);
    final eingaben = await _eingaben();

    final zeilen = <WochenZeile>[];
    for (final d in bedarfe) {
      final p = produkte[d.productId];
      if (p == null) continue;
      final imBoard = planung[d.id]?.kg ?? 0;
      if (d.mengeKgFertig - imBoard <= 0.5) continue; // gedeckt
      var e = eingaben[d.id];
      if (e == null || (e.fertigKg - d.mengeKgFertig).abs() > 0.01) {
        e = WochenEingabe(
          feld: MengenFeld.fertig,
          kg: d.mengeKgFertig,
          fertigKg: d.mengeKgFertig,
        );
      }
      zeilen.add(
        WochenZeile(
          bedarfId: d.id,
          productId: p.id,
          artikelnummer: p.artikelnummer,
          bezeichnung: p.artikelbezeichnung,
          wunschtag: d.termin,
          feld: e.feld,
          kg: e.kg,
          fertigKg: d.mengeKgFertig,
          imBoardKg: imBoard,
        ),
      );
    }
    // Stabil sortieren: gleicher Wunschtag behält die Reihenfolge der
    // Eingabe.
    final index = {for (var i = 0; i < zeilen.length; i++) zeilen[i]: i};
    zeilen.sort((a, b) {
      final at = a.wunschtag, bt = b.wunschtag;
      if (at != null && bt != null) {
        final t = at.compareTo(bt);
        if (t != 0) return t;
      } else if (at != null) {
        return -1;
      } else if (bt != null) {
        return 1;
      }
      return index[a]!.compareTo(index[b]!);
    });
    return zeilen;
  }

  /// Legt eine Zeile an oder ändert sie und gibt die Kennung des Bedarfs
  /// zurück. [fertigKg] muss schon gerechnet sein ([rechneMengen]).
  Future<String> speichere({
    String? bedarfId,
    required String productId,
    required DateTime? wunschtag,
    required MengenFeld feld,
    required double kg,
    required double fertigKg,
  }) async {
    final tag = wunschtag == null
        ? null
        : DateTime(wunschtag.year, wunschtag.month, wunschtag.day);
    final id = bedarfId ?? const Uuid().v4();
    await _db.transaction(() async {
      if (bedarfId == null) {
        await _db.into(_db.demands).insert(
              DemandsCompanion.insert(
                id: id,
                productId: productId,
                mengeKgFertig: fertigKg,
                termin: Value(tag),
                quelle: const Value(kQuelleWochenliste),
              ),
            );
      } else {
        await (_db.update(_db.demands)..where((d) => d.id.equals(id))).write(
          DemandsCompanion(
            productId: Value(productId),
            mengeKgFertig: Value(fertigKg),
            termin: Value(tag),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
      final eingaben = await _eingaben();
      eingaben[id] = WochenEingabe(feld: feld, kg: kg, fertigKg: fertigKg);
      await _speichereEingaben(eingaben);
    });
    return id;
  }

  /// Nimmt eine Zeile aus der Liste. Der Bedarf wird gelöscht wie in der
  /// Bedarfsliste; was davon schon im Board steht, bleibt dort.
  Future<void> loesche(String bedarfId) async {
    final jetzt = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.demands)..where((d) => d.id.equals(bedarfId)))
          .write(
        DemandsCompanion(deletedAt: Value(jetzt), updatedAt: Value(jetzt)),
      );
      final eingaben = await _eingaben();
      if (eingaben.remove(bedarfId) != null) {
        await _speichereEingaben(eingaben);
      }
    });
  }

  /// Ausbeute und Fleischanteil — wie im Fenster der Produktion: aus den
  /// letzten Produktionen, sonst aus der Rezeptur.
  Future<ArtikelVerhaeltnisse> verhaeltnisse(String productId) async =>
      ArtikelVerhaeltnisse(
        ausbeute: await ausbeuteFuer(_db, productId),
        fleischanteil: await fleischanteilFuer(_db, productId),
      );

  /// Die Zeit je Abteilung für [fertigKg] — dieselbe Rechnung wie im
  /// Planungsvorschlag.
  Future<ZeilenDauer> dauer(String productId, double fertigKg) async {
    if (fertigKg <= 0) return ZeilenDauer.leer;
    final plan = await berechneSchrittPlan(
      db: _db,
      productId: productId,
      mengeKg: fertigKg,
      startTag: DateTime.now(),
    );
    final minuten = <Abteilung, double>{};
    var platzhalter = false;
    for (final s in plan.schritte) {
      final a = s.abteilung;
      if (a == null) continue;
      minuten[a] = (minuten[a] ?? 0) + s.dauerMinuten;
      if (s.platzhalter) platzhalter = true;
    }
    return ZeilenDauer(
      {
        for (final a in Abteilung.values)
          if (minuten[a] case final m?) a: m,
      },
      geschaetzt: platzhalter,
    );
  }

  Future<Map<String, WochenEingabe>> _eingaben() async {
    final zeile = await (_db.select(_db.appSettings)
          ..where((s) => s.key.equals(kWochenlisteEingabenSchluessel)))
        .getSingleOrNull();
    return eingabenAusText(zeile?.value);
  }

  /// Schreibt die Eingaben zurück — nur die der noch lebenden Zeilen, damit
  /// die Einstellung nicht über die Jahre wächst.
  Future<void> _speichereEingaben(Map<String, WochenEingabe> eingaben) async {
    final lebend = {
      for (final d in await (_db.select(_db.demands)
            ..where((d) => d.quelle.equals(kQuelleWochenliste))
            ..where((d) => d.deletedAt.isNull()))
          .get())
        d.id,
    };
    eingaben.removeWhere((id, _) => !lebend.contains(id));
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: kWochenlisteEingabenSchluessel,
            value: eingabenAlsText(eingaben),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }
}
