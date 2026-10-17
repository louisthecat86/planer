import 'dart:convert';

// Gefahrenanalyse (FMEA) und Lenkungspunkte eines Projekts.
//
// In der Datenbank steht beides als ein JSON-Text (EntwicklungProjekte.
// haccp). Die Entscheidung, ob ein Schritt ein kritischer Lenkungspunkt
// ist, folgt dem Codex-Entscheidungsbaum mit vier Fragen
// (CAC/RCP 1-1969, Anhang).

/// Art einer Gefahr.
enum Gefahrenart {
  physikalisch('physikalisch', 'Physikalisch'),
  mikrobiologisch('mikrobiologisch', 'Mikrobiologisch'),
  chemisch('chemisch', 'Chemisch'),
  allergene('allergene', 'Allergene');

  const Gefahrenart(this.schluessel, this.label);

  final String schluessel;
  final String label;

  static Gefahrenart aus(String? text) {
    final t = text?.trim().toLowerCase() ?? '';
    for (final a in Gefahrenart.values) {
      if (a.schluessel == t) return a;
    }
    return Gefahrenart.physikalisch;
  }
}

/// Ergebnis des Entscheidungsbaums.
enum Lenkungsart {
  ccp('CCP', 'Kritischer Lenkungspunkt'),
  cp('CP', 'Lenkungspunkt'),
  kp('KP', 'Kein Lenkungspunkt');

  const Lenkungsart(this.kuerzel, this.label);

  final String kuerzel;
  final String label;

  static Lenkungsart aus(String? text) {
    switch (text?.trim().toUpperCase()) {
      case 'CCP':
        return Lenkungsart.ccp;
      case 'CP':
        return Lenkungsart.cp;
      default:
        return Lenkungsart.kp;
    }
  }
}

/// Eine Zeile der Gefahrenanalyse.
class Gefahr {
  const Gefahr({
    required this.id,
    this.gefahr = '',
    this.art = Gefahrenart.physikalisch,
    this.schwere = 1,
    this.wahrscheinlichkeit = 1,
    this.massnahmen = '',
  });

  final String id;
  final String gefahr;
  final Gefahrenart art;

  /// Bedeutung 1 (leicht) bis 3 (schwer).
  final int schwere;

  /// Vorkommen 1 (unwahrscheinlich) bis 3 (wahrscheinlich).
  final int wahrscheinlichkeit;

  final String massnahmen;

  /// Risiko = Bedeutung × Vorkommen, 1 bis 9.
  int get risiko => schwere * wahrscheinlichkeit;

  Gefahr kopie({
    String? gefahr,
    Gefahrenart? art,
    int? schwere,
    int? wahrscheinlichkeit,
    String? massnahmen,
  }) =>
      Gefahr(
        id: id,
        gefahr: gefahr ?? this.gefahr,
        art: art ?? this.art,
        schwere: schwere ?? this.schwere,
        wahrscheinlichkeit: wahrscheinlichkeit ?? this.wahrscheinlichkeit,
        massnahmen: massnahmen ?? this.massnahmen,
      );

  Map<String, Object> toJson() => {
        'id': id,
        'gefahr': gefahr,
        'art': art.schluessel,
        'schwere': schwere,
        'wahrscheinlichkeit': wahrscheinlichkeit,
        'massnahmen': massnahmen,
      };

  static Gefahr ausJson(Map<String, dynamic> j) => Gefahr(
        id: '${j['id'] ?? ''}',
        gefahr: j['gefahr'] is String ? j['gefahr'] as String : '',
        art: Gefahrenart.aus(j['art'] as String?),
        schwere: _stufe(j['schwere']),
        wahrscheinlichkeit: _stufe(j['wahrscheinlichkeit']),
        massnahmen: j['massnahmen'] is String ? j['massnahmen'] as String : '',
      );
}

/// Ein Prozessschritt mit seiner Einstufung im Entscheidungsbaum.
class Lenkungspunkt {
  const Lenkungspunkt({
    required this.id,
    this.schritt = '',
    this.beschreibung = '',
    this.art = Gefahrenart.physikalisch,
    this.antworten = const {},
    this.ergebnis = Lenkungsart.kp,
    this.lenkung = '',
  });

  final String id;
  final String schritt;
  final String beschreibung;
  final Gefahrenart art;

  /// Antworten auf die Fragen des Baums, etwa {'f1': true, 'f2': false}.
  final Map<String, bool> antworten;

  final Lenkungsart ergebnis;

  /// Lenkungsmaßnahmen, Grenzwerte, Überwachung.
  final String lenkung;

  Lenkungspunkt kopie({
    String? schritt,
    String? beschreibung,
    Gefahrenart? art,
    Map<String, bool>? antworten,
    Lenkungsart? ergebnis,
    String? lenkung,
  }) =>
      Lenkungspunkt(
        id: id,
        schritt: schritt ?? this.schritt,
        beschreibung: beschreibung ?? this.beschreibung,
        art: art ?? this.art,
        antworten: antworten ?? this.antworten,
        ergebnis: ergebnis ?? this.ergebnis,
        lenkung: lenkung ?? this.lenkung,
      );

  Map<String, Object> toJson() => {
        'id': id,
        'schritt': schritt,
        'beschreibung': beschreibung,
        'art': art.schluessel,
        'antworten': antworten,
        'ergebnis': ergebnis.kuerzel,
        'lenkung': lenkung,
      };

  static Lenkungspunkt ausJson(Map<String, dynamic> j) {
    final a = j['antworten'];
    return Lenkungspunkt(
      id: '${j['id'] ?? ''}',
      schritt: j['schritt'] is String ? j['schritt'] as String : '',
      beschreibung:
          j['beschreibung'] is String ? j['beschreibung'] as String : '',
      art: Gefahrenart.aus(j['art'] as String?),
      antworten: {
        if (a is Map<String, dynamic>)
          for (final MapEntry(:key, :value) in a.entries)
            if (value is bool) key: value,
      },
      ergebnis: Lenkungsart.aus(j['ergebnis'] as String?),
      lenkung: j['lenkung'] is String ? j['lenkung'] as String : '',
    );
  }
}

/// Gefahrenanalyse und Lenkungspunkte eines Projekts.
class Haccp {
  const Haccp({this.gefahren = const [], this.lenkungspunkte = const []});

  final List<Gefahr> gefahren;
  final List<Lenkungspunkt> lenkungspunkte;

  bool get leer => gefahren.isEmpty && lenkungspunkte.isEmpty;

  Haccp kopie({List<Gefahr>? gefahren, List<Lenkungspunkt>? lenkungspunkte}) =>
      Haccp(
        gefahren: gefahren ?? this.gefahren,
        lenkungspunkte: lenkungspunkte ?? this.lenkungspunkte,
      );

  /// JSON für die Datenbank — null, wenn nichts erfasst ist.
  String? alsJson() => leer
      ? null
      : jsonEncode({
          'gefahren': [for (final g in gefahren) g.toJson()],
          'lenkungspunkte': [for (final l in lenkungspunkte) l.toJson()],
        });

  static Haccp aus(String? json) {
    if (json == null || json.trim().isEmpty) return const Haccp();
    try {
      final d = jsonDecode(json);
      if (d is! Map<String, dynamic>) return const Haccp();
      return Haccp(
        gefahren: [
          for (final g in (d['gefahren'] as List?) ?? const [])
            if (g is Map<String, dynamic>) Gefahr.ausJson(g),
        ],
        lenkungspunkte: [
          for (final l in (d['lenkungspunkte'] as List?) ?? const [])
            if (l is Map<String, dynamic>) Lenkungspunkt.ausJson(l),
        ],
      );
    } on FormatException {
      return const Haccp();
    }
  }

  /// Aus dem Format der alten Suite (fmeaData: hazards, ccps).
  static Haccp ausSuite(Object? json) {
    if (json is! Map<String, dynamic>) return const Haccp();
    String t(Map<String, dynamic> m, String k) =>
        m[k] is String ? m[k] as String : '';
    Gefahrenart art(Object? text) =>
        Gefahrenart.aus(text is String ? text : null);
    return Haccp(
      gefahren: [
        for (final h in (json['hazards'] as List?) ?? const [])
          if (h is Map<String, dynamic>)
            Gefahr(
              id: '${h['id'] ?? ''}',
              gefahr: t(h, 'hazard'),
              art: art(h['category']),
              schwere: _stufe(h['severity']),
              wahrscheinlichkeit: _stufe(h['occurrence']),
              massnahmen: t(h, 'measures'),
            ),
      ],
      lenkungspunkte: [
        for (final c in (json['ccps'] as List?) ?? const [])
          if (c is Map<String, dynamic>)
            Lenkungspunkt(
              id: '${c['id'] ?? ''}',
              schritt: t(c, 'step'),
              beschreibung: t(c, 'description'),
              art: art(c['hazardType']),
              antworten: {
                for (final f in const ['q1', 'q2', 'q3', 'q4'])
                  if (c[f] is bool) 'f${f.substring(1)}': c[f] as bool,
              },
              ergebnis: Lenkungsart.aus(c['result'] as String?),
              lenkung: t(c, 'controlMeasures'),
            ),
      ],
    );
  }
}

int _stufe(Object? wert) {
  final n = wert is num ? wert.round() : int.tryParse('$wert') ?? 1;
  return n < 1 ? 1 : (n > 3 ? 3 : n);
}

// ── Der Entscheidungsbaum ─────────────────────────────────────────────

/// Eine Frage des Baums.
class BaumFrage {
  const BaumFrage(this.schluessel, this.text, this.ja, this.nein);

  final String schluessel;
  final String text;

  /// Nächste Frage oder Ergebnis bei Ja bzw. Nein: ein Fragenschlüssel
  /// oder `ergebnis:CCP`, `ergebnis:KP`, `ergebnis:ANPASSEN`.
  final String ja;
  final String nein;
}

/// Die Fragen des Codex-Entscheidungsbaums.
const Map<String, BaumFrage> kEntscheidungsbaum = {
  'f1': BaumFrage(
    'f1',
    'Gibt es für die Gefahr vorbeugende Maßnahmen?',
    'f2',
    'f1b',
  ),
  'f1b': BaumFrage(
    'f1b',
    'Ist eine Beherrschung an diesem Schritt für die Sicherheit nötig?',
    'ergebnis:ANPASSEN',
    'ergebnis:KP',
  ),
  'f2': BaumFrage(
    'f2',
    'Ist der Schritt eigens dafür da, die Gefahr zu beseitigen oder auf ein '
        'annehmbares Maß zu senken?',
    'ergebnis:CCP',
    'f3',
  ),
  'f3': BaumFrage(
    'f3',
    'Kann eine Verunreinigung mit der Gefahr über das annehmbare Maß '
        'hinausgehen oder darauf ansteigen?',
    'f4',
    'ergebnis:KP',
  ),
  'f4': BaumFrage(
    'f4',
    'Beseitigt ein späterer Schritt die Gefahr oder senkt sie auf ein '
        'annehmbares Maß?',
    'ergebnis:KP',
    'ergebnis:CCP',
  ),
};
