import 'dart:convert';

// Prozessparameter eines Projekts: Abschnitte mit Feldern, etwa
// „Bratstraße" mit Plattentemperatur, Höhe und Geschwindigkeit.
//
// In der Datenbank als JSON-Text (EntwicklungProjekte.prozess), frühere
// Stände als Liste in prozessHistorie. Die Abschnitte legt jedes Projekt
// selbst an — eine Vorlage mit Firmenangaben gehört nicht in den Code.

/// Wie ein Feld eingegeben wird.
enum FeldTyp {
  text('text'),
  langtext('textarea'),
  zahl('number'),
  auswahl('radio');

  const FeldTyp(this.schluessel);

  final String schluessel;

  static FeldTyp aus(String? text) {
    switch (text?.trim().toLowerCase()) {
      case 'textarea':
        return FeldTyp.langtext;
      case 'number':
        return FeldTyp.zahl;
      case 'radio':
      case 'select':
      case 'checkbox':
        return FeldTyp.auswahl;
      default:
        return FeldTyp.text;
    }
  }
}

/// Ein Feld eines Abschnitts.
class ProzessFeld {
  const ProzessFeld({
    required this.id,
    required this.label,
    this.wert = '',
    this.typ = FeldTyp.text,
    this.optionen = const [],
  });

  final String id;
  final String label;
  final String wert;
  final FeldTyp typ;

  /// Bei [FeldTyp.auswahl]: die Möglichkeiten.
  final List<String> optionen;

  ProzessFeld mitWert(String neu) => ProzessFeld(
        id: id,
        label: label,
        wert: neu,
        typ: typ,
        optionen: optionen,
      );

  Map<String, Object> toJson() => {
        'id': id,
        'label': label,
        'wert': wert,
        'typ': typ.schluessel,
        if (optionen.isNotEmpty) 'optionen': optionen,
      };

  static ProzessFeld ausJson(Map<String, dynamic> j, {bool suite = false}) {
    String t(String k) => j[k] is String ? j[k] as String : '';
    final optionen = j[suite ? 'options' : 'optionen'];
    return ProzessFeld(
      id: '${j['id'] ?? ''}',
      label: t('label'),
      wert: t(suite ? 'value' : 'wert'),
      typ: FeldTyp.aus(t(suite ? 'type' : 'typ')),
      optionen: [
        if (optionen is List)
          for (final o in optionen)
            if (o is String) o,
      ],
    );
  }
}

/// Ein Abschnitt, etwa ein Anlagentyp.
class ProzessAbschnitt {
  const ProzessAbschnitt({
    required this.id,
    required this.titel,
    this.felder = const [],
  });

  final String id;
  final String titel;
  final List<ProzessFeld> felder;

  ProzessAbschnitt kopie({String? titel, List<ProzessFeld>? felder}) =>
      ProzessAbschnitt(
        id: id,
        titel: titel ?? this.titel,
        felder: felder ?? this.felder,
      );

  Map<String, Object> toJson() => {
        'id': id,
        'titel': titel,
        'felder': [for (final f in felder) f.toJson()],
      };

  static ProzessAbschnitt ausJson(
    Map<String, dynamic> j, {
    bool suite = false,
  }) {
    final felder = j[suite ? 'fields' : 'felder'];
    return ProzessAbschnitt(
      id: '${j['id'] ?? ''}',
      titel: j[suite ? 'title' : 'titel'] is String
          ? j[suite ? 'title' : 'titel'] as String
          : '',
      felder: [
        if (felder is List)
          for (final f in felder)
            if (f is Map<String, dynamic>) ProzessFeld.ausJson(f, suite: suite),
      ],
    );
  }
}

/// Die Prozessparameter eines Projekts.
class Prozessparameter {
  const Prozessparameter({
    this.version = '1.0',
    this.stand,
    this.abschnitte = const [],
  });

  final String version;
  final DateTime? stand;
  final List<ProzessAbschnitt> abschnitte;

  bool get leer => abschnitte.isEmpty;

  Prozessparameter kopie({
    String? version,
    DateTime? stand,
    List<ProzessAbschnitt>? abschnitte,
  }) =>
      Prozessparameter(
        version: version ?? this.version,
        stand: stand ?? this.stand,
        abschnitte: abschnitte ?? this.abschnitte,
      );

  Map<String, Object> toJson() => {
        'version': version,
        if (stand != null) 'stand': stand!.toIso8601String(),
        'abschnitte': [for (final a in abschnitte) a.toJson()],
      };

  /// JSON für die Datenbank — null ohne Abschnitte.
  String? alsJson() => leer ? null : jsonEncode(toJson());

  static Prozessparameter ausJson(Object? json, {bool suite = false}) {
    if (json is! Map<String, dynamic>) return const Prozessparameter();
    final abschnitte = json[suite ? 'sections' : 'abschnitte'];
    final stand = json[suite ? 'updatedAt' : 'stand'];
    return Prozessparameter(
      version: json['version'] is String ? json['version'] as String : '1.0',
      stand: stand is String ? DateTime.tryParse(stand) : null,
      abschnitte: [
        if (abschnitte is List)
          for (final a in abschnitte)
            if (a is Map<String, dynamic>)
              ProzessAbschnitt.ausJson(a, suite: suite),
      ],
    );
  }

  static Prozessparameter aus(String? text) {
    if (text == null || text.trim().isEmpty) return const Prozessparameter();
    try {
      return ausJson(jsonDecode(text));
    } on FormatException {
      return const Prozessparameter();
    }
  }
}

/// Ein früherer Stand der Prozessparameter.
class ProzessStand {
  const ProzessStand({
    required this.version,
    required this.datum,
    required this.parameter,
    this.notiz = '',
  });

  final String version;
  final DateTime datum;
  final String notiz;
  final Prozessparameter parameter;

  Map<String, Object> toJson() => {
        'version': version,
        'datum': datum.toIso8601String(),
        'notiz': notiz,
        'parameter': parameter.toJson(),
      };

  static List<ProzessStand> listeAus(String? text) {
    if (text == null || text.trim().isEmpty) return const [];
    try {
      final d = jsonDecode(text);
      if (d is! List) return const [];
      return [
        for (final s in d)
          if (s is Map<String, dynamic>)
            ProzessStand(
              version: s['version'] is String ? s['version'] as String : '',
              datum: DateTime.tryParse(
                    s['datum'] is String ? s['datum'] as String : '',
                  ) ??
                  DateTime(2000),
              notiz: s['notiz'] is String ? s['notiz'] as String : '',
              parameter: Prozessparameter.ausJson(s['parameter']),
            ),
      ];
    } on FormatException {
      return const [];
    }
  }

  static String? listeZuJson(List<ProzessStand> liste) => liste.isEmpty
      ? null
      : jsonEncode([for (final s in liste) s.toJson()]);

  /// Aus der Suite: processHistory mit version, date, note, settings.
  static List<ProzessStand> ausSuite(Object? json) {
    if (json is! List) return const [];
    return [
      for (final s in json)
        if (s is Map<String, dynamic>)
          ProzessStand(
            version: s['version'] is String ? s['version'] as String : '',
            datum: DateTime.tryParse(
                  s['date'] is String ? s['date'] as String : '',
                ) ??
                DateTime(2000),
            notiz: s['note'] is String ? s['note'] as String : '',
            parameter: Prozessparameter.ausJson(s['settings'], suite: true),
          ),
    ];
  }
}
