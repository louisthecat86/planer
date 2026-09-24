import 'package:drift/drift.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/constants/artikel_merkmale.dart';
import '../../core/database/database.dart';
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

  VorschlagEinstellungen kopieMit({
    double? ruestenMinuten,
    double? zwischenreinigungMinuten,
    double? endreinigungMinuten,
    int? maxArbeitstage,
    bool? planeSamstag,
    Set<DateTime>? gesperrteTage,
    Set<String>? ausgeschlosseneArtikel,
    DateTime? startTag,
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
    );
  }
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

  double get gesamtMinuten => dauerMinuten + nebenzeitMinuten;
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

  final double endreinigungMinuten;

  /// Hinweise, die den Tag nicht verhindern: nachgelagerte Abteilung
  /// läuft über, Merkmale fehlen, Wunschtermin überschritten.
  final List<String> warnungen;

  double get neuMinuten =>
      posten.fold<double>(0, (s, p) => s + p.gesamtMinuten) +
      (posten.isEmpty ? 0 : endreinigungMinuten);

  double get gesamtMinuten => belegtVorherMinuten + neuMinuten;

  double get auslastung =>
      kapazitaetMinuten > 0 ? gesamtMinuten / kapazitaetMinuten : 0;
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

  final List<VorschlagTag> tage;
  final List<NichtPlanbar> nichtPlanbar;
  final VorschlagEinstellungen einstellungen;

  bool get istLeer => tage.every((t) => t.posten.isEmpty);
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

  /// Braucht der Wechsel von [vorher] auf diesen Posten eine Reinigung?
  bool brauchtReinigungNach(_Kandidat vorher) =>
      allergenRang < vorher.allergenRang ||
      (bioRang < vorher.bioRang) ||
      (rohRang < vorher.rohRang);

  /// Gleiche Bratstraßen-Einstellung = kein Umstellen nötig.
  bool gleicheEinstellungWie(_Kandidat vorher) =>
      plattenTemp == vorher.plattenTemp && hoehe == vorher.hoehe;
}

// ═══════════════════════════════════════════════════════════════════════
// Service
// ═══════════════════════════════════════════════════════════════════════

/// Rechnet aus dem offenen Bedarf einen Vorschlag, wie die nächsten Tage
/// aussehen könnten — ohne irgendetwas zu speichern.
///
/// Bewusst kein Optimierer: Die Reihenfolge folgt den Regeln aus der
/// Produktion, nicht einer Zielfunktion. In dieser Rangfolge:
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
/// den verlässlichsten Daten. Die übrigen Abteilungen laufen mit und
/// werden nur als Warnung gemeldet, wenn sie überlaufen.
///
/// Der Vorschlag ist eine Rechnung, kein Plan. Geschrieben wird erst,
/// wenn der Anwender einen Tag oder eine Zeile übernimmt — dafür ist
/// [uebernehmeTag] da.
class PlanungsvorschlagService {
  PlanungsvorschlagService(this._db);

  final AppDatabase _db;

  /// Die führende Abteilung. Sie ist der Engpass und hat die besten Daten.
  static const _fuehrend = Abteilung.bratstrasse;

  Future<Planungsvorschlag> berechne(VorschlagEinstellungen e) async {
    final heute = DateTime.now();
    final start = _tag(
      e.startTag ?? DateTime(heute.year, heute.month, heute.day + 1),
    );

    final nichtPlanbar = <NichtPlanbar>[];
    final kandidaten = await _sammleKandidaten(e, nichtPlanbar);

    // Termin und Priorität entscheiden, WAS drankommt. Die Regeln oben
    // entscheiden, in welcher Reihenfolge es innerhalb eines Tages läuft.
    kandidaten.sort((a, b) {
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
    });

    final kapazitaet = await _kapazitaetFuehrend();
    final belegung = await _belegungJeTag();

    final tage = <VorschlagTag>[];
    final offen = [...kandidaten];
    var tag = start;
    var arbeitstage = 0;

    while (offen.isNotEmpty && arbeitstage < e.maxArbeitstage) {
      if (!_istArbeitstag(tag, e)) {
        tag = _tag(tag.add(const Duration(days: 1)));
        continue;
      }
      arbeitstage++;

      final belegtVorher = belegung[_schluessel(tag)] ?? 0;
      var frei = kapazitaet - belegtVorher - e.endreinigungMinuten;
      final gewaehlt = <_Kandidat>[];

      // Greedy füllen: Kandidat probeweise aufnehmen, Tag neu sortieren,
      // Nebenzeiten neu rechnen. Passt es nicht, bleibt er liegen und der
      // nächste wird probiert — ein kleiner Artikel kann eine Lücke noch
      // füllen, die ein großer sprengen würde.
      for (final k in [...offen]) {
        final probe = _sortiere([...gewaehlt, k]);
        final summe = _summeMitNebenzeiten(probe, e);
        if (summe <= frei) {
          gewaehlt
            ..clear()
            ..addAll(probe);
          offen.remove(k);
        }
      }

      if (gewaehlt.isEmpty) {
        // Nichts passt mehr an diesen Tag — nächster Tag.
        tag = _tag(tag.add(const Duration(days: 1)));
        continue;
      }

      frei = kapazitaet - belegtVorher;
      tage.add(
        _baueTag(
          tag: tag,
          gewaehlt: gewaehlt,
          kapazitaet: kapazitaet,
          belegtVorher: belegtVorher,
          e: e,
        ),
      );
      tag = _tag(tag.add(const Duration(days: 1)));
    }

    // Was nach dem letzten Tag übrig ist, gehört in die Restliste — sonst
    // verschwindet es stillschweigend.
    for (final k in offen) {
      nichtPlanbar.add(
        NichtPlanbar(
          artikelnummer: k.artikelnummer,
          bezeichnung: k.bezeichnung,
          mengeKg: k.mengeKg,
          grund: 'Passt nicht mehr in den Zeitraum von '
              '${e.maxArbeitstage} Arbeitstagen',
        ),
      );
    }

    return Planungsvorschlag(
      tage: tage,
      nichtPlanbar: nichtPlanbar,
      einstellungen: e,
    );
  }

  // ── Kandidaten ───────────────────────────────────────────────────────

  Future<List<_Kandidat>> _sammleKandidaten(
    VorschlagEinstellungen e,
    List<NichtPlanbar> nichtPlanbar,
  ) async {
    final bedarfe = await (_db.select(_db.demands)
          ..where((d) => d.deletedAt.isNull())
          ..where((d) => d.manuellErledigt.equals(false)))
        .get();

    final produkte = {
      for (final p in await _db.select(_db.products).get()) p.id: p,
    };

    // Bereits eingeplante Mengen je Bedarf abziehen: Ein Bedarf, der zur
    // Hälfte im Board steht, braucht nur noch den Rest.
    final tasks = await (_db.select(_db.productionTasks)
          ..where((t) => t.deletedAt.isNull())
          ..where((t) => t.bedarfId.isNotNull()))
        .get();
    final geplantJeBedarf = <String, double>{};
    for (final t in tasks) {
      final bid = t.bedarfId;
      final menge = t.fertigMengeKg;
      if (bid == null || menge == null) continue;
      geplantJeBedarf[bid] = (geplantJeBedarf[bid] ?? 0) + menge;
    }

    final kandidaten = <_Kandidat>[];
    for (final d in bedarfe) {
      final p = produkte[d.productId];
      final offen = d.mengeKgFertig - (geplantJeBedarf[d.id] ?? 0);
      if (offen <= 0.5) continue; // gedeckt
      if (p == null) continue;

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
          termin: d.termin,
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
  Future<Map<String, double>> _belegungJeTag() async {
    final belegung = <String, double>{};

    final tasks = await (_db.select(_db.productionTasks)
          ..where((t) => t.deletedAt.isNull())
          ..where((t) => t.abteilung.equals(_fuehrend.dbValue)))
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

  static double _summeMitNebenzeiten(
    List<_Kandidat> sortiert,
    VorschlagEinstellungen e,
  ) {
    var summe = 0.0;
    _Kandidat? vorher;
    for (final k in sortiert) {
      summe += k.dauerMinuten + _nebenzeit(k, vorher, e);
      vorher = k;
    }
    return summe + e.endreinigungMinuten;
  }

  static VorschlagTag _baueTag({
    required DateTime tag,
    required List<_Kandidat> gewaehlt,
    required double kapazitaet,
    required double belegtVorher,
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
        ),
      );

      for (final f in k.fehlendeMerkmale) {
        warnungen.add('$f fehlt bei ${k.artikelnummer}');
      }
      final termin = k.termin;
      if (termin != null && _tag(termin).isBefore(tag)) {
        warnungen.add('Wunschtermin von ${k.artikelnummer} liegt vor diesem '
            'Tag');
      }
      vorher = k;
    }

    return VorschlagTag(
      tag: tag,
      posten: posten,
      kapazitaetMinuten: kapazitaet,
      belegtVorherMinuten: belegtVorher,
      endreinigungMinuten: e.endreinigungMinuten,
      warnungen: warnungen.toList()..sort(),
    );
  }

  // ── Übernahme ────────────────────────────────────────────────────────

  /// Schreibt die Posten eines Vorschlagstags ins Board: je Artikel die
  /// komplette Auftragskette über alle Abteilungen, plus die Rüst- und
  /// Reinigungsblöcke als Zusatzzeit auf der führenden Spur.
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
      await erstelleTasksAusPlan(
        db: _db,
        productId: p.productId,
        schritte: plan.schritte,
        bedarfId: p.bedarfId,
        fertigMengeKg: p.mengeKg,
      );
      angelegt++;
    }

    final neben = t.posten.fold<double>(0, (s, p) => s + p.nebenzeitMinuten);
    if (neben > 0) {
      await _zusatzzeit(t.tag, 'ruesten', neben, 'Aus Planungsvorschlag');
    }
    if (t.posten.isNotEmpty && t.endreinigungMinuten > 0) {
      await _zusatzzeit(
        t.tag,
        'reinigen',
        t.endreinigungMinuten,
        'Endreinigung aus Planungsvorschlag',
      );
    }
    return angelegt;
  }

  Future<void> _zusatzzeit(
    DateTime tag,
    String art,
    double minuten,
    String notiz,
  ) async {
    await _db.into(_db.zusatzzeiten).insert(
          ZusatzzeitenCompanion.insert(
            id: '${_fuehrend.dbValue}-$art-${tag.millisecondsSinceEpoch}',
            datum: _tag(tag),
            // Sammelspur der Abteilung — dieselbe Kennung wie im Board.
            spurId: '${_fuehrend.dbValue}|',
            art: art,
            minuten: minuten,
            notiz: Value(notiz),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  // ── Kleinkram ────────────────────────────────────────────────────────

  static DateTime _tag(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _schluessel(DateTime d) =>
      '${d.year}-${d.month}-${d.day}';

  static bool _istArbeitstag(DateTime d, VorschlagEinstellungen e) {
    if (e.gesperrteTage.any((g) => _schluessel(g) == _schluessel(d))) {
      return false;
    }
    if (d.weekday == DateTime.sunday) return false;
    if (d.weekday == DateTime.saturday && !e.planeSamstag) return false;
    return true;
  }
}
