import '../../../core/constants/artikel_merkmale.dart';
import '../../../core/utils/format.dart';
import 'allergen_hervorhebung.dart';
import 'rechen_modell.dart';

// Der Rechenkern der Produktentwicklung: aus einer Rezeptur Endgewicht,
// Zutatenliste mit Mengenangaben (QUID), Nährwerte je 100 g, Allergene
// und Fleischanteil.
//
// Nachgebaut aus der alten Suite, mit diesen Korrekturen:
//
// * „hergestellt aus … g je 100 g" nennt die Gramm je 100 g Enderzeugnis,
//   nicht die Rohmasse der ganzen Charge.
// * Eine Unterrezeptur geht mit der eingesetzten fertigen Menge in die
//   Masse ein (F13) — ihr Verlust zählt nicht ein zweites Mal. Ihre
//   Zutaten stehen mit der Rohmenge in der Liste, die für diese fertige
//   Menge nötig war.
// * Liegen Fett und Bindegewebe zugleich über dem Grenzwert, werden beide
//   berücksichtigt (vorher nur das Fett).
// * Bindegewebe ist das Verhältnis Kollagen zu Fleischeiweiß (F14),
//   gemittelt nach Fleischeiweiß über die Zutaten, die einen Wert haben.
//   Die Rechnung folgt der Methode der irischen Lebensmittelbehörde FSAI
//   („Calculation of Meat Content", Abschnitt 8).
// * Allergene werden nur in ganzen Wortteilen hervorgehoben.
//
// Wie in der Suite (und nach Aussage des Nutzers) steht überschüssiges
// Bindegewebe nicht als eigene Zutat in der Liste — es senkt nur den
// Fleischanteil. Überschüssiges Fett steht als „Speck" bzw. „…fett" da.

/// Energie je Gramm (LMIV Anhang XIV).
const double _kjJeGrammFett = 37;
const double _kcalJeGrammFett = 9;
const double _kjJeGrammEiweiss = 17;
const double _kcalJeGrammEiweiss = 4;
const double _kjJeGrammKohlenhydrate = 17;
const double _kcalJeGrammKohlenhydrate = 4;

/// Bindegewebe aus Kollagen: Faktor der FSAI-Methode (37/8).
const double _bindegewebeJeKollagen = 4.625;

/// Zusammensetzung des Garsafts beim Braten oder Garen — eine Näherung
/// aus der Suite: Fleischsaft ist zum größten Teil Wasser, mit etwas
/// Eiweiß, Salz und gelöstem Zucker.
const double _saftEiweiss = 0.05;
const double _saftSalz = 0.01;
const double _saftZucker = 0.01;
const double _saftWasser = 0.93;

/// Zugesetztes Wasser bis zu diesem Anteil am Enderzeugnis muss nicht in
/// der Zutatenliste stehen (LMIV Anhang VII Teil A Nr. 1).
const double kWasserGrenzeProzent = 5;

/// Eine Zeile der Zutatenliste.
class EtikettZeile {
  const EtikettZeile({
    required this.name,
    required this.text,
    required this.masseKg,
    required this.anteilProzent,
    required this.quid,
    this.unterzutaten,
    this.istFleisch = false,
    this.istWasser = false,
    this.ausgelassen = false,
    this.allergene = const {},
  });

  /// Name ohne Hervorhebung.
  final String name;

  /// So steht die Zeile in der Zutatenliste.
  final String text;

  /// Masse, nach der sortiert wird: die Rohmasse zum Zeitpunkt der
  /// Verwendung — bei zugesetztem Wasser, was davon übrig bleibt.
  final double masseKg;

  /// [masseKg] bezogen auf das Endgewicht.
  final double anteilProzent;

  final bool quid;
  final String? unterzutaten;
  final bool istFleisch;
  final bool istWasser;

  /// Zugesetztes Wasser bis 5 %: steht nicht in der Liste.
  final bool ausgelassen;

  final Set<String> allergene;
}

/// Die Prüfung einer Tierart gegen die Grenzwerte für „Fleisch".
class TierartPruefung {
  const TierartPruefung({
    required this.tierart,
    required this.masseKg,
    required this.fettProzent,
    required this.eiweissProzent,
    required this.kollagenVerhaeltnis,
    required this.ueberschussFettKg,
    required this.ueberschussBindegewebeKg,
  });

  final Tierart tierart;

  /// Rohmasse aller Zutaten dieser Tierart.
  final double masseKg;

  final double fettProzent;

  /// Fleischeiweiß in Prozent der Masse.
  final double eiweissProzent;

  /// Kollagen zu Fleischeiweiß in Prozent — null, wenn keine Zutat einen
  /// Wert hat; dann wird das Bindegewebe nicht geprüft.
  final double? kollagenVerhaeltnis;

  final double ueberschussFettKg;
  final double ueberschussBindegewebeKg;

  /// Was als Fleisch zählt.
  double get fleischKg {
    final rest = masseKg - ueberschussFettKg - ueberschussBindegewebeKg;
    return rest < 0 ? 0 : rest;
  }

  bool get fettUeberGrenze => ueberschussFettKg > 0;
  bool get bindegewebeUeberGrenze => ueberschussBindegewebeKg > 0;
}

/// Alles, was der Rechenkern über eine Rezeptur weiß.
class RezepturErgebnis {
  const RezepturErgebnis({
    required this.eingesetztKg,
    required this.rohmasseKg,
    required this.endgewichtKg,
    required this.zeilen,
    required this.zutatenliste,
    required this.je100g,
    required this.fleischanteilProzent,
    required this.tierarten,
    required this.allergene,
    required this.verarbeitungshilfsstoffe,
    required this.warnungen,
    required this.ohneNaehrwerte,
  });

  /// Summe der Positionen: Zutaten roh, Unterrezepturen mit der
  /// eingesetzten fertigen Menge.
  final double eingesetztKg;

  /// Summe aller Rohstoffe, auch der in Unterrezepturen.
  final double rohmasseKg;

  /// Nach dem Verlust.
  final double endgewichtKg;

  /// Die Zeilen der Zutatenliste, absteigend nach Masse.
  final List<EtikettZeile> zeilen;

  /// Die fertige Zutatenliste mit Hervorhebung der Allergene.
  final String zutatenliste;

  /// Nährwerte je 100 g Enderzeugnis; die Energie ist aus Fett, Eiweiß
  /// und Kohlenhydraten berechnet.
  final Naehrwerte je100g;

  /// Fleisch im Sinne der LMIV, bezogen auf das Endgewicht.
  final double fleischanteilProzent;

  final List<TierartPruefung> tierarten;

  /// Allergen (Planer-Wert) → Zutaten, aus denen es kommt.
  final Map<String, List<String>> allergene;

  /// Verarbeitungshilfsstoff → Zutaten, aus denen er kommt.
  final Map<String, List<String>> verarbeitungshilfsstoffe;

  final List<String> warnungen;

  /// Zutaten ohne Nährwerte — die Tabelle ist dann zu niedrig.
  final List<String> ohneNaehrwerte;
}

/// Berechnet [rezeptur].
RezepturErgebnis berechne(RechenRezeptur rezeptur) {
  final warnungen = <String>[];
  final teil = _rechne(rezeptur, const <String>{}, warnungen);
  final endKg = teil.endKg;
  if (teil.eingesetztKg <= 0) {
    warnungen.add('Die Rezeptur hat noch keine Mengen.');
  } else if (endKg <= 0) {
    warnungen.add('Nach dem Verlust bleibt nichts übrig.');
  }

  double anteil(double kg) => endKg > 0 ? kg / endKg * 100 : 0;

  // ── Gleiche Zutaten zusammenfassen ──────────────────────────────────
  final zusammen = <String, _Blatt>{};
  for (final b in teil.blaetter) {
    final schluessel = '${b.zutat.id}|${b.quid}|${b.etikettName ?? ''}';
    final vorher = zusammen[schluessel];
    zusammen[schluessel] = vorher == null ? b : vorher.plus(b);
  }
  final blaetter = zusammen.values.where((b) => b.rohKg > 0).toList();

  // ── Fleisch je Tierart ──────────────────────────────────────────────
  final gruppen = <Tierart, List<_Blatt>>{};
  final uebrige = <_Blatt>[];
  for (final b in blaetter) {
    final art = b.zutat.tierart ?? Tierart.aus(b.zutat.name);
    if (b.zutat.istFleisch && art != null) {
      gruppen.putIfAbsent(art, () => []).add(b);
    } else {
      if (b.zutat.istFleisch) {
        warnungen.add(
          '„${b.zutat.name}" ist Fleisch ohne Tierart — es zählt nicht zum '
          'Fleischanteil und steht einzeln in der Liste.',
        );
      }
      uebrige.add(b);
    }
  }

  final pruefungen = <TierartPruefung>[];
  final zeilen = <_Zeile>[];
  for (final art in Tierart.values) {
    final gruppe = gruppen[art];
    if (gruppe == null) continue;
    final pruefung = _pruefe(art, gruppe);
    pruefungen.add(pruefung);
    zeilen.add(
      _Zeile(
        name: art.fleischName,
        masseKg: pruefung.fleischKg,
        quid: true,
        istFleisch: true,
        allergene: {for (final b in gruppe) ...b.zutat.allergene},
      ),
    );
    if (pruefung.fettUeberGrenze) {
      zeilen.add(
        _Zeile(
          name: art.fettName,
          masseKg: pruefung.ueberschussFettKg,
          quid: true,
        ),
      );
      warnungen.add(
        'Der Fettgehalt bei ${art.label} '
        '(${Format.zahl(pruefung.fettProzent, nachkomma: 1)} %) liegt über '
        '${Format.zahl(art.fettGrenze)} % — '
        '${Format.kg(pruefung.ueberschussFettKg)} stehen als '
        '„${art.fettName}" in der Liste.',
      );
    }
    if (pruefung.bindegewebeUeberGrenze) {
      warnungen.add(
        'Das Bindegewebe bei ${art.label} '
        '(${Format.zahl(pruefung.kollagenVerhaeltnis!, nachkomma: 1)} % '
        'Kollagen im Fleischeiweiß) liegt über '
        '${Format.zahl(art.bindegewebeGrenze)} % — der Fleischanteil sinkt '
        'um ${Format.kg(pruefung.ueberschussBindegewebeKg)}.',
      );
    }
  }
  for (final b in uebrige) {
    zeilen.add(
      _Zeile(
        name: b.anzeigeName,
        masseKg: b.zutat.istWasser ? b.wasserKg : b.rohKg,
        quid: b.quid,
        unterzutaten: b.zutat.unterzutaten,
        istWasser: b.zutat.istWasser,
        allergene: b.zutat.allergene,
      ),
    );
  }

  // Absteigend nach dem Gewicht zum Zeitpunkt der Verwendung; Wasser nach
  // dem, was im Enderzeugnis bleibt (LMIV Art. 18, Anhang VII Teil A).
  zeilen.sort((a, b) {
    final m = b.masseKg.compareTo(a.masseKg);
    return m != 0 ? m : a.name.compareTo(b.name);
  });

  final wasserKg = zeilen
      .where((z) => z.istWasser)
      .fold<double>(0, (s, z) => s + z.masseKg);
  final wasserAuslassen =
      wasserKg > 0 && anteil(wasserKg) <= kWasserGrenzeProzent;

  final fertig = <EtikettZeile>[];
  for (final z in zeilen) {
    final prozent = anteil(z.masseKg);
    final ausgelassen = z.istWasser && wasserAuslassen;
    final name = hebeAllergeneHervor(z.name, z.allergene);
    final unter = z.unterzutaten == null || z.unterzutaten!.trim().isEmpty
        ? null
        : hebeAllergeneHervor(z.unterzutaten!.trim(), z.allergene);
    final genannt = {...name.gefunden, ...?unter?.gefunden};
    if (!ausgelassen) {
      for (final a in z.allergene) {
        if (a == kAllergenKeine || genannt.contains(a)) continue;
        warnungen.add(
          'Allergen „${merkmalLabel(a, kAllergene) ?? a}" aus „${z.name}" '
          'wird in der Zutatenliste nicht genannt — Bezeichnung oder '
          'Unterzutaten ergänzen.',
        );
      }
    }
    fertig.add(
      EtikettZeile(
        name: z.name,
        text: _zeilenText(name.text, unter?.text, prozent, z.quid),
        masseKg: z.masseKg,
        anteilProzent: prozent,
        quid: z.quid,
        unterzutaten: z.unterzutaten,
        istFleisch: z.istFleisch,
        istWasser: z.istWasser,
        ausgelassen: ausgelassen,
        allergene: z.allergene,
      ),
    );
  }
  if (wasserAuslassen) {
    warnungen.add(
      'Zugesetztes Wasser bleibt mit '
      '${Format.zahl(anteil(wasserKg), nachkomma: 1)} % unter '
      '${Format.zahl(kWasserGrenzeProzent)} % und steht nicht in der Liste.',
    );
  }

  // ── Allergene und Hilfsstoffe mit Herkunft ──────────────────────────
  final allergene = <String, Set<String>>{};
  final hilfsstoffe = <String, Set<String>>{};
  for (final b in blaetter) {
    for (final a in b.zutat.allergene) {
      if (a == kAllergenKeine) continue;
      allergene.putIfAbsent(a, () => {}).add(b.anzeigeName);
    }
    for (final h in b.zutat.verarbeitungshilfsstoffe) {
      final name = h.trim();
      if (name.isEmpty) continue;
      hilfsstoffe.putIfAbsent(name, () => {}).add(b.anzeigeName);
    }
  }
  // Nach der Rangfolge der Planung, wie überall im Planer.
  final allergenSchluessel = allergene.keys.toList()
    ..sort((a, b) => _rang(a).compareTo(_rang(b)));

  final fleischKg = pruefungen.fold<double>(0, (s, p) => s + p.fleischKg);

  return RezepturErgebnis(
    eingesetztKg: teil.eingesetztKg,
    rohmasseKg: blaetter.fold<double>(0, (s, b) => s + b.rohKg),
    endgewichtKg: endKg,
    zeilen: fertig,
    zutatenliste: [
      for (final z in fertig)
        if (!z.ausgelassen) z.text,
    ].join(', '),
    je100g: _je100g(teil.naehrstoffe, endKg),
    fleischanteilProzent: anteil(fleischKg),
    tierarten: pruefungen,
    allergene: {
      for (final a in allergenSchluessel) a: allergene[a]!.toList()..sort(),
    },
    verarbeitungshilfsstoffe: {
      for (final MapEntry(:key, :value) in hilfsstoffe.entries)
        key: value.toList()..sort(),
    },
    warnungen: warnungen,
    ohneNaehrwerte: teil.ohneNaehrwerte.toList()..sort(),
  );
}

int _rang(String allergen) {
  final i = kAllergene.indexWhere((m) => m.dbValue == allergen);
  return i < 0 ? kAllergene.length : i;
}

/// Text einer Zeile: Name, Unterzutaten in Klammern, Menge.
String _zeilenText(
  String name,
  String? unterzutaten,
  double prozent,
  bool quid,
) {
  final grund = unterzutaten == null ? name : '$name ($unterzutaten)';
  if (!quid) return grund;
  if (prozent <= 100) {
    return '$grund (${Format.zahl(prozent, nachkomma: 1)} %)';
  }
  // Über 100 %: die Gramm, die für 100 g Enderzeugnis nötig waren
  // (LMIV Anhang VIII Nr. 3).
  final unter = unterzutaten == null ? '' : ' ($unterzutaten)';
  return 'hergestellt aus ${Format.zahl(prozent)} g $name '
      'je 100 g des Enderzeugnisses$unter';
}

/// Prüft eine Tierart nach der FSAI-Methode: zuerst das Bindegewebe, dann
/// das Fett auf der um das Bindegewebe verminderten Masse.
TierartPruefung _pruefe(Tierart art, List<_Blatt> gruppe) {
  var masse = 0.0;
  var fett = 0.0;
  var eiweiss = 0.0;
  var kollagenBekannt = 0.0;
  var eiweissBekannt = 0.0;
  for (final b in gruppe) {
    masse += b.rohKg;
    final n = b.zutat.naehrwerte;
    fett += b.rohKg * (n.fett ?? 0) / 100;
    final e = b.rohKg * (n.eiweiss ?? 0) / 100;
    eiweiss += e;
    final verhaeltnis = b.zutat.bindegewebe;
    if (verhaeltnis != null && e > 0) {
      kollagenBekannt += e * verhaeltnis / 100;
      eiweissBekannt += e;
    }
  }
  if (masse <= 0) {
    return TierartPruefung(
      tierart: art,
      masseKg: 0,
      fettProzent: 0,
      eiweissProzent: 0,
      kollagenVerhaeltnis: null,
      ueberschussFettKg: 0,
      ueberschussBindegewebeKg: 0,
    );
  }
  final f = fett / masse * 100;
  final p = eiweiss / masse * 100;
  final verhaeltnis =
      eiweissBekannt > 0 ? kollagenBekannt / eiweissBekannt * 100 : null;

  // Bindegewebe: Kollagen über dem Grenzwert, umgerechnet in Gewebe.
  var exct = 0.0;
  if (verhaeltnis != null) {
    final c = p * verhaeltnis / 100;
    final grenze = art.bindegewebeGrenze;
    final maxcol = grenze * (p - c) / (100 - grenze);
    final excol = c - maxcol;
    if (excol > 0) exct = excol * _bindegewebeJeKollagen;
  }
  // Fett: auf der Masse ohne das überschüssige Bindegewebe.
  final maxfat = art.fettGrenze * (100 - exct - f) / (100 - art.fettGrenze);
  final exfat = f > maxfat ? f - maxfat : 0.0;

  return TierartPruefung(
    tierart: art,
    masseKg: masse,
    fettProzent: f,
    eiweissProzent: p,
    kollagenVerhaeltnis: verhaeltnis,
    ueberschussFettKg: masse * exfat / 100,
    ueberschussBindegewebeKg: masse * exct / 100,
  );
}

/// Nährwerte je 100 g aus den Gesamtmengen in Gramm.
Naehrwerte _je100g(Map<_Stoff, double> gramm, double endKg) {
  if (endKg <= 0) return Naehrwerte.leer;
  double je(_Stoff s) => (gramm[s] ?? 0) / (endKg * 10);
  final fett = je(_Stoff.fett);
  final eiweiss = je(_Stoff.eiweiss);
  final kh = je(_Stoff.kohlenhydrate);
  final beffe = gramm[_Stoff.beffe];
  return Naehrwerte(
    energieKj: fett * _kjJeGrammFett +
        eiweiss * _kjJeGrammEiweiss +
        kh * _kjJeGrammKohlenhydrate,
    energieKcal: fett * _kcalJeGrammFett +
        eiweiss * _kcalJeGrammEiweiss +
        kh * _kcalJeGrammKohlenhydrate,
    fett: fett,
    gesaettigteFettsaeuren: je(_Stoff.gesaettigt),
    kohlenhydrate: kh,
    zucker: je(_Stoff.zucker),
    eiweiss: eiweiss,
    salz: je(_Stoff.salz),
    wasser: je(_Stoff.wasser),
    asche: je(_Stoff.asche),
    beffe: beffe == null ? null : beffe / (endKg * 10),
  );
}

// ── Die Rechnung je Rezeptur-Ebene ────────────────────────────────────

enum _Stoff {
  fett,
  gesaettigt,
  kohlenhydrate,
  zucker,
  eiweiss,
  salz,
  wasser,
  asche,
  beffe,
}

/// Eine Zutat mit der Rohmasse, die in der berechneten Charge steckt.
class _Blatt {
  const _Blatt({
    required this.zutat,
    required this.rohKg,
    required this.wasserKg,
    required this.quid,
    this.etikettName,
  });

  final RechenZutat zutat;
  final double rohKg;

  /// Nur bei zugesetztem Wasser: was nach allen Verlusten bisher übrig ist.
  final double wasserKg;

  final bool quid;
  final String? etikettName;

  String get anzeigeName {
    final e = etikettName?.trim();
    return e == null || e.isEmpty ? zutat.anzeigeName : e;
  }

  _Blatt skaliert(double faktor, {double wasserFaktor = 1}) => _Blatt(
        zutat: zutat,
        rohKg: rohKg * faktor,
        wasserKg: wasserKg * faktor * wasserFaktor,
        quid: quid,
        etikettName: etikettName,
      );

  _Blatt plus(_Blatt anderes) => _Blatt(
        zutat: zutat,
        rohKg: rohKg + anderes.rohKg,
        wasserKg: wasserKg + anderes.wasserKg,
        quid: quid,
        etikettName: etikettName,
      );
}

/// Ergebnis einer Rezeptur-Ebene.
class _Teil {
  const _Teil({
    required this.eingesetztKg,
    required this.endKg,
    required this.blaetter,
    required this.naehrstoffe,
    required this.ohneNaehrwerte,
  });

  final double eingesetztKg;
  final double endKg;
  final List<_Blatt> blaetter;

  /// Gesamtmengen im Enderzeugnis dieser Ebene, in Gramm.
  final Map<_Stoff, double> naehrstoffe;

  final Set<String> ohneNaehrwerte;
}

/// Eine Zeile vor der Formatierung.
class _Zeile {
  const _Zeile({
    required this.name,
    required this.masseKg,
    required this.quid,
    this.unterzutaten,
    this.istFleisch = false,
    this.istWasser = false,
    this.allergene = const {},
  });

  final String name;
  final double masseKg;
  final bool quid;
  final String? unterzutaten;
  final bool istFleisch;
  final bool istWasser;
  final Set<String> allergene;
}

_Teil _rechne(
  RechenRezeptur rezeptur,
  Set<String> pfad,
  List<String> warnungen,
) {
  if (pfad.contains(rezeptur.id)) {
    warnungen.add(
      '„${rezeptur.name}" enthält sich selbst als Unterrezeptur — diese '
      'Stelle zählt nicht mit.',
    );
    return const _Teil(
      eingesetztKg: 0,
      endKg: 0,
      blaetter: <_Blatt>[],
      naehrstoffe: <_Stoff, double>{},
      ohneNaehrwerte: <String>{},
    );
  }
  final weiter = {...pfad, rezeptur.id};

  var eingesetzt = 0.0;
  final blaetter = <_Blatt>[];
  final gramm = <_Stoff, double>{};
  final ohneNaehrwerte = <String>{};
  var beffeBekannt = false;

  void addiere(_Stoff s, double wert) {
    gramm[s] = (gramm[s] ?? 0) + wert;
  }

  for (final position in rezeptur.positionen) {
    final menge = position.mengeKg > 0 ? position.mengeKg : 0.0;
    eingesetzt += menge;
    final zutat = position.zutat;
    final unter = position.unterrezeptur;
    if (zutat != null) {
      blaetter.add(
        _Blatt(
          zutat: zutat,
          rohKg: menge,
          wasserKg: zutat.istWasser ? menge : 0,
          quid: position.quidPflicht ?? zutat.quidPflicht,
          etikettName: position.etikettName,
        ),
      );
      final n = zutat.naehrwerte;
      // Masse in Gramm durch 100 — mal den Wert je 100 g ergibt Gramm.
      final g = menge * 10;
      if (zutat.istWasser) {
        addiere(_Stoff.wasser, g * (n.wasser ?? 100));
      } else {
        if (!n.bekannt && menge > 0) ohneNaehrwerte.add(zutat.anzeigeName);
        addiere(_Stoff.fett, g * (n.fett ?? 0));
        addiere(_Stoff.gesaettigt, g * (n.gesaettigteFettsaeuren ?? 0));
        addiere(_Stoff.kohlenhydrate, g * (n.kohlenhydrate ?? 0));
        addiere(_Stoff.zucker, g * (n.zucker ?? 0));
        addiere(_Stoff.eiweiss, g * (n.eiweiss ?? 0));
        addiere(_Stoff.salz, g * (n.salz ?? 0));
        addiere(_Stoff.wasser, g * (n.wasserOderGeschaetzt ?? 0));
        addiere(_Stoff.asche, g * (n.asche ?? 0));
      }
      final beffe = n.beffe;
      if (beffe != null) {
        beffeBekannt = true;
        addiere(_Stoff.beffe, g * beffe);
      }
    } else if (unter != null) {
      final teil = _rechne(unter, weiter, warnungen);
      if (teil.endKg <= 0) {
        if (menge > 0) {
          warnungen.add(
            'Die Unterrezeptur „${unter.name}" hat kein Endgewicht — sie '
            'zählt nicht mit.',
          );
        }
        continue;
      }
      // Die eingesetzte fertige Menge, bezogen auf die ganze Charge der
      // Unterrezeptur.
      final faktor = menge / teil.endKg;
      for (final b in teil.blaetter) {
        blaetter.add(b.skaliert(faktor));
      }
      for (final MapEntry(:key, :value) in teil.naehrstoffe.entries) {
        addiere(key, value * faktor);
      }
      if (teil.naehrstoffe.containsKey(_Stoff.beffe)) beffeBekannt = true;
      ohneNaehrwerte.addAll(teil.ohneNaehrwerte);
    }
  }

  // ── Verlust dieser Ebene ────────────────────────────────────────────
  var verlust = rezeptur.verlustart == Verlustart.keiner
      ? 0.0
      : rezeptur.verlustProzent;
  if (verlust < 0) verlust = 0;
  if (verlust > 100) {
    warnungen.add(
      'Der Verlust von „${rezeptur.name}" liegt über 100 % — gerechnet wird '
      'mit 100 %.',
    );
    verlust = 100;
  }
  final endKg = eingesetzt * (1 - verlust / 100);
  final verlustKg = eingesetzt - endKg;

  // Der Verlust geht zuerst zulasten des zugesetzten Wassers — so hat es
  // der Nutzer für die Suite festgelegt.
  final wasserVorher = blaetter
      .where((b) => b.zutat.istWasser)
      .fold<double>(0, (s, b) => s + b.wasserKg);
  final wasserNachher =
      wasserVorher > verlustKg ? wasserVorher - verlustKg : 0.0;
  final bleibt = wasserVorher > 0 ? wasserNachher / wasserVorher : 0.0;
  final nachVerlust = [
    for (final b in blaetter)
      b.zutat.istWasser ? b.skaliert(1, wasserFaktor: bleibt) : b,
  ];

  // Nährstoffe: Fett nach Angabe, der Rest des Verlusts als Wasser oder
  // beim Garen als Saft.
  if (verlustKg > 0) {
    final verlustG = verlustKg * 1000;
    var fettG = eingesetzt * 1000 * rezeptur.fettVerlustProzent / 100;
    if (fettG < 0) fettG = 0;
    if (fettG > verlustG) fettG = verlustG;
    final fettVorher = gramm[_Stoff.fett] ?? 0;
    final fettNachher = fettVorher > fettG ? fettVorher - fettG : 0.0;
    if (fettVorher > 0) {
      gramm[_Stoff.gesaettigt] =
          (gramm[_Stoff.gesaettigt] ?? 0) * fettNachher / fettVorher;
    }
    gramm[_Stoff.fett] = fettNachher;

    final rest = verlustG - fettG;
    final wasserVor = gramm[_Stoff.wasser] ?? 0;
    if (rezeptur.verlustart == Verlustart.garen) {
      void minus(_Stoff s, double wert) {
        final v = (gramm[s] ?? 0) - wert;
        gramm[s] = v < 0 ? 0 : v;
      }

      minus(_Stoff.eiweiss, rest * _saftEiweiss);
      minus(_Stoff.salz, rest * _saftSalz);
      minus(_Stoff.zucker, rest * _saftZucker);
      minus(_Stoff.kohlenhydrate, rest * _saftZucker);
      minus(_Stoff.wasser, rest * _saftWasser);
      if (wasserVor < rest * _saftWasser) _zuWenigWasser(rezeptur, warnungen);
    } else {
      gramm[_Stoff.wasser] = wasserVor > rest ? wasserVor - rest : 0;
      if (wasserVor < rest) _zuWenigWasser(rezeptur, warnungen);
    }
  }
  if (!beffeBekannt) gramm.remove(_Stoff.beffe);

  return _Teil(
    eingesetztKg: eingesetzt,
    endKg: endKg,
    blaetter: nachVerlust,
    naehrstoffe: gramm,
    ohneNaehrwerte: ohneNaehrwerte,
  );
}

void _zuWenigWasser(RechenRezeptur rezeptur, List<String> warnungen) {
  warnungen.add(
    'Der Verlust von „${rezeptur.name}" ist größer als das Wasser darin — '
    'Verlust oder Wassergehalt der Zutaten prüfen.',
  );
}
