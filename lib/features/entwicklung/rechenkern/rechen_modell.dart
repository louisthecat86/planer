// Die Eingabe des Rechenkerns: Zutaten, Positionen, Rezepturen.
//
// Reines Dart ohne Datenbank und ohne Flutter — so lässt sich jede Regel
// in einem Test nachrechnen. Die Oberfläche baut diese Objekte aus den
// Tabellen; ein abgeschlossener Rezepturstand speichert sie als JSON
// ([RechenRezeptur.toJson]), damit spätere Änderungen am Katalog ihn
// nicht verschieben.

/// Wie die Rezeptur Masse verliert.
enum Verlustart {
  /// Trocknen, Reifen, Räuchern: Es geht nur Wasser (und das angegebene
  /// Fett).
  trocknung('trocknung', 'Trocknung'),

  /// Garen, Braten: Mit dem Saft gehen auch etwas Eiweiß, Salz und Zucker.
  garen('garen', 'Garen'),

  /// Kein Verlust — was hineingeht, kommt heraus.
  keiner('keiner', 'Kein Verlust');

  const Verlustart(this.schluessel, this.label);

  final String schluessel;
  final String label;

  static Verlustart aus(String? text) {
    switch (text?.trim().toLowerCase()) {
      case 'garen':
      case 'cooking':
        return Verlustart.garen;
      case 'keiner':
      case 'none':
        return Verlustart.keiner;
      default:
        return Verlustart.trocknung;
    }
  }
}

/// Eine Tierart mit den Grenzwerten für „Fleisch" nach LMIV Anhang VII
/// Teil B: Fett und Bindegewebe (Kollagen zu Fleischeiweiß), je in Prozent.
enum Tierart {
  schwein('schwein', 'Schwein', 'Schweinefleisch', 'Speck', 30, 25),
  rind('rind', 'Rind', 'Rindfleisch', 'Rinderfett', 25, 25),
  kalb('kalb', 'Kalb', 'Kalbfleisch', 'Kalbsfett', 25, 25),
  lamm('lamm', 'Lamm', 'Lammfleisch', 'Lammfett', 25, 25),
  saeugetier(
    'saeugetier',
    'Säugetier (gemischt)',
    'Säugetierfleisch',
    'Tierisches Fett',
    25,
    25,
  ),
  huhn('huhn', 'Huhn', 'Hühnerfleisch', 'Hühnerfett', 15, 10),
  pute('pute', 'Pute', 'Putenfleisch', 'Putenfett', 15, 10),
  ente('ente', 'Ente', 'Entenfleisch', 'Entenfett', 15, 10),
  gefluegel('gefluegel', 'Geflügel', 'Geflügelfleisch', 'Geflügelfett', 15, 10),
  kaninchen('kaninchen', 'Kaninchen', 'Kaninchenfleisch', 'Kaninchenfett', 15, 10);

  const Tierart(
    this.schluessel,
    this.label,
    this.fleischName,
    this.fettName,
    this.fettGrenze,
    this.bindegewebeGrenze,
  );

  /// Gespeicherter Wert, etwa „schwein".
  final String schluessel;

  /// Für Auswahllisten, etwa „Schwein".
  final String label;

  /// Name in der Zutatenliste, etwa „Schweinefleisch".
  final String fleischName;

  /// Name des Fetts über dem Grenzwert, etwa „Speck".
  final String fettName;

  /// Höchster Fettanteil in Prozent.
  final double fettGrenze;

  /// Höchstes Verhältnis Kollagen zu Fleischeiweiß in Prozent.
  final double bindegewebeGrenze;

  /// Liest einen gespeicherten Wert — auch die englischen Schlüssel der
  /// alten Suite und deutsche Wörter wie „Schweinebauch". null, wenn
  /// nichts passt.
  static Tierart? aus(String? text) {
    if (text == null) return null;
    final t = text.trim().toLowerCase();
    if (t.isEmpty) return null;
    for (final art in Tierart.values) {
      if (art.schluessel == t) return art;
    }
    const englisch = {
      'pork': Tierart.schwein,
      'beef': Tierart.rind,
      'veal': Tierart.kalb,
      'lamb': Tierart.lamm,
      'mammal': Tierart.saeugetier,
      'chicken': Tierart.huhn,
      'turkey': Tierart.pute,
      'duck': Tierart.ente,
      'poultry': Tierart.gefluegel,
      'rabbit': Tierart.kaninchen,
    };
    final ausEnglisch = englisch[t];
    if (ausEnglisch != null) return ausEnglisch;
    // Wörter, die die Tierart nennen — in dieser Reihenfolge, damit
    // „Kalbsleberwurst" nicht als Rind zählt.
    const woerter = [
      ('schwein', Tierart.schwein),
      ('kalb', Tierart.kalb),
      ('rind', Tierart.rind),
      ('lamm', Tierart.lamm),
      ('hähnchen', Tierart.huhn),
      ('haehnchen', Tierart.huhn),
      ('huhn', Tierart.huhn),
      ('hühner', Tierart.huhn),
      ('pute', Tierart.pute),
      ('truthahn', Tierart.pute),
      ('ente', Tierart.ente),
      ('kaninchen', Tierart.kaninchen),
      ('hase', Tierart.kaninchen),
      ('geflügel', Tierart.gefluegel),
      ('gefluegel', Tierart.gefluegel),
    ];
    for (final (wort, art) in woerter) {
      if (t.contains(wort)) return art;
    }
    return null;
  }
}

/// Nährwerte je 100 g. Fehlende Werte sind null — nicht 0: „unbekannt"
/// ist etwas anderes als „enthält nichts".
class Naehrwerte {
  const Naehrwerte({
    this.energieKj,
    this.energieKcal,
    this.fett,
    this.gesaettigteFettsaeuren,
    this.kohlenhydrate,
    this.zucker,
    this.eiweiss,
    this.salz,
    this.wasser,
    this.asche,
    this.beffe,
  });

  static const Naehrwerte leer = Naehrwerte();

  final double? energieKj;
  final double? energieKcal;
  final double? fett;
  final double? gesaettigteFettsaeuren;
  final double? kohlenhydrate;
  final double? zucker;
  final double? eiweiss;
  final double? salz;
  final double? wasser;
  final double? asche;

  /// Bindegewebseiweißfreies Fleischeiweiß.
  final double? beffe;

  /// Ob überhaupt ein Wert bekannt ist.
  bool get bekannt =>
      fett != null ||
      eiweiss != null ||
      kohlenhydrate != null ||
      salz != null ||
      wasser != null ||
      energieKj != null ||
      energieKcal != null;

  /// Wasser — angegeben oder geschätzt als Rest zu 100 g aus Fett,
  /// Eiweiß, Kohlenhydraten, Salz und Asche. null, wenn nichts bekannt ist.
  double? get wasserOderGeschaetzt {
    final w = wasser;
    if (w != null) return w;
    final teile = [fett, eiweiss, kohlenhydrate, salz, asche];
    if (teile.every((t) => t == null)) return null;
    final summe = teile.fold<double>(0, (s, t) => s + (t ?? 0));
    return summe >= 100 ? 0 : 100 - summe;
  }

  Map<String, Object?> toJson() => {
        if (energieKj != null) 'energieKj': energieKj,
        if (energieKcal != null) 'energieKcal': energieKcal,
        if (fett != null) 'fett': fett,
        if (gesaettigteFettsaeuren != null)
          'gesaettigteFettsaeuren': gesaettigteFettsaeuren,
        if (kohlenhydrate != null) 'kohlenhydrate': kohlenhydrate,
        if (zucker != null) 'zucker': zucker,
        if (eiweiss != null) 'eiweiss': eiweiss,
        if (salz != null) 'salz': salz,
        if (wasser != null) 'wasser': wasser,
        if (asche != null) 'asche': asche,
        if (beffe != null) 'beffe': beffe,
      };

  static Naehrwerte ausJson(Object? json) {
    if (json is! Map<String, dynamic>) return Naehrwerte.leer;
    double? zahl(String k) {
      final v = json[k];
      return v is num ? v.toDouble() : null;
    }

    return Naehrwerte(
      energieKj: zahl('energieKj'),
      energieKcal: zahl('energieKcal'),
      fett: zahl('fett'),
      gesaettigteFettsaeuren: zahl('gesaettigteFettsaeuren'),
      kohlenhydrate: zahl('kohlenhydrate'),
      zucker: zahl('zucker'),
      eiweiss: zahl('eiweiss'),
      salz: zahl('salz'),
      wasser: zahl('wasser'),
      asche: zahl('asche'),
      beffe: zahl('beffe'),
    );
  }
}

/// Eine Zutat, wie der Rechenkern sie braucht.
class RechenZutat {
  const RechenZutat({
    required this.id,
    required this.name,
    this.etikettName,
    this.istFleisch = false,
    this.istWasser = false,
    this.tierart,
    this.bindegewebe,
    this.quidPflicht = false,
    this.unterzutaten,
    this.verarbeitungshilfsstoffe = const [],
    this.allergene = const {},
    this.naehrwerte = Naehrwerte.leer,
  });

  final String id;
  final String name;
  final String? etikettName;
  final bool istFleisch;
  final bool istWasser;
  final Tierart? tierart;

  /// Kollagen zu Fleischeiweiß in Prozent (F14) — null: unbekannt.
  final double? bindegewebe;

  final bool quidPflicht;
  final String? unterzutaten;
  final List<String> verarbeitungshilfsstoffe;

  /// Allergene als Planer-Werte (kAllergene), etwa „eier".
  final Set<String> allergene;

  final Naehrwerte naehrwerte;

  /// Der Name in der Zutatenliste.
  String get anzeigeName {
    final e = etikettName?.trim();
    return e == null || e.isEmpty ? name : e;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        if (etikettName != null) 'etikettName': etikettName,
        if (istFleisch) 'istFleisch': true,
        if (istWasser) 'istWasser': true,
        if (tierart != null) 'tierart': tierart!.schluessel,
        if (bindegewebe != null) 'bindegewebe': bindegewebe,
        if (quidPflicht) 'quidPflicht': true,
        if (unterzutaten != null) 'unterzutaten': unterzutaten,
        if (verarbeitungshilfsstoffe.isNotEmpty)
          'verarbeitungshilfsstoffe': verarbeitungshilfsstoffe,
        if (allergene.isNotEmpty) 'allergene': allergene.toList()..sort(),
        'naehrwerte': naehrwerte.toJson(),
      };

  static RechenZutat ausJson(Map<String, dynamic> json) {
    final bg = json['bindegewebe'];
    return RechenZutat(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      etikettName: json['etikettName'] as String?,
      istFleisch: json['istFleisch'] == true,
      istWasser: json['istWasser'] == true,
      tierart: Tierart.aus(json['tierart'] as String?),
      bindegewebe: bg is num ? bg.toDouble() : null,
      quidPflicht: json['quidPflicht'] == true,
      unterzutaten: json['unterzutaten'] as String?,
      verarbeitungshilfsstoffe: [
        for (final v in (json['verarbeitungshilfsstoffe'] as List?) ?? const [])
          if (v is String) v,
      ],
      allergene: {
        for (final a in (json['allergene'] as List?) ?? const [])
          if (a is String) a,
      },
      naehrwerte: Naehrwerte.ausJson(json['naehrwerte']),
    );
  }
}

/// Eine Zeile der Rezeptur: eine Zutat oder eine Unterrezeptur.
class RechenPosition {
  const RechenPosition.zutat(
    RechenZutat this.zutat, {
    required this.mengeKg,
    this.quidPflicht,
    this.etikettName,
  }) : unterrezeptur = null;

  const RechenPosition.unterrezeptur(
    RechenRezeptur this.unterrezeptur, {
    required this.mengeKg,
    this.quidPflicht,
    this.etikettName,
  }) : zutat = null;

  final RechenZutat? zutat;
  final RechenRezeptur? unterrezeptur;

  /// Menge in kg. Bei einer Unterrezeptur die eingesetzte fertige Menge
  /// (F13).
  final double mengeKg;

  /// Mengenangabe in der Zutatenliste — null: wie bei der Zutat.
  final bool? quidPflicht;

  /// Name in der Zutatenliste nur für diese Rezeptur.
  final String? etikettName;

  /// Dieselbe Zeile mit anderer Menge.
  RechenPosition mitMenge(double kg) {
    final z = zutat;
    if (z != null) {
      return RechenPosition.zutat(
        z,
        mengeKg: kg,
        quidPflicht: quidPflicht,
        etikettName: etikettName,
      );
    }
    return RechenPosition.unterrezeptur(
      unterrezeptur!,
      mengeKg: kg,
      quidPflicht: quidPflicht,
      etikettName: etikettName,
    );
  }

  Map<String, Object?> toJson() => {
        if (zutat != null) 'zutat': zutat!.toJson(),
        if (unterrezeptur != null) 'unterrezeptur': unterrezeptur!.toJson(),
        'mengeKg': mengeKg,
        if (quidPflicht != null) 'quidPflicht': quidPflicht,
        if (etikettName != null) 'etikettName': etikettName,
      };

  /// null, wenn die Zeile weder Zutat noch Unterrezeptur enthält.
  static RechenPosition? ausJson(Map<String, dynamic> json) {
    final menge = json['mengeKg'];
    final mengeKg = menge is num ? menge.toDouble() : 0.0;
    final quid = json['quidPflicht'];
    final etikett = json['etikettName'] as String?;
    final zutat = json['zutat'];
    if (zutat is Map<String, dynamic>) {
      return RechenPosition.zutat(
        RechenZutat.ausJson(zutat),
        mengeKg: mengeKg,
        quidPflicht: quid is bool ? quid : null,
        etikettName: etikett,
      );
    }
    final unter = json['unterrezeptur'];
    if (unter is Map<String, dynamic>) {
      return RechenPosition.unterrezeptur(
        RechenRezeptur.ausJson(unter),
        mengeKg: mengeKg,
        quidPflicht: quid is bool ? quid : null,
        etikettName: etikett,
      );
    }
    return null;
  }
}

/// Eine Rezeptur: Positionen und Verlust.
class RechenRezeptur {
  const RechenRezeptur({
    required this.id,
    required this.name,
    required this.positionen,
    this.verlustProzent = 0,
    this.fettVerlustProzent = 0,
    this.verlustart = Verlustart.trocknung,
  });

  /// Kennung — erkennt Unterrezepturen, die sich selbst enthalten.
  final String id;
  final String name;
  final List<RechenPosition> positionen;

  /// Gesamtverlust in Prozent der eingesetzten Masse.
  final double verlustProzent;

  /// Davon Fett in Prozent der eingesetzten Masse.
  final double fettVerlustProzent;

  final Verlustart verlustart;

  /// Dieselbe Rezeptur mit anderen Positionen oder anderem Verlust.
  RechenRezeptur kopie({
    List<RechenPosition>? positionen,
    double? verlustProzent,
    double? fettVerlustProzent,
    Verlustart? verlustart,
  }) =>
      RechenRezeptur(
        id: id,
        name: name,
        positionen: positionen ?? this.positionen,
        verlustProzent: verlustProzent ?? this.verlustProzent,
        fettVerlustProzent: fettVerlustProzent ?? this.fettVerlustProzent,
        verlustart: verlustart ?? this.verlustart,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'verlustProzent': verlustProzent,
        'fettVerlustProzent': fettVerlustProzent,
        'verlustart': verlustart.schluessel,
        'positionen': [for (final p in positionen) p.toJson()],
      };

  static RechenRezeptur ausJson(Map<String, dynamic> json) {
    double zahl(String k) {
      final v = json[k];
      return v is num ? v.toDouble() : 0;
    }

    return RechenRezeptur(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      verlustProzent: zahl('verlustProzent'),
      fettVerlustProzent: zahl('fettVerlustProzent'),
      verlustart: Verlustart.aus(json['verlustart'] as String?),
      positionen: [
        for (final p in (json['positionen'] as List?) ?? const [])
          if (p is Map<String, dynamic>) RechenPosition.ausJson(p),
      ].whereType<RechenPosition>().toList(),
    );
  }
}
