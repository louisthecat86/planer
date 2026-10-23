import 'dart:convert';

import '../../../core/utils/format.dart';

// Der Prozess eines Projekts — wie im Artikel eine Kette von Schritten:
// Stationen nach Abteilung, je Schritt eine Anlage aus dem Katalog (oder
// nur ein Prozessschritt wie „Abkühlen") mit ihren Werten (F32).
//
// In der Datenbank als JSON-Text (EntwicklungProjekte.prozess) — der
// Arbeitsstand, der sich selbst speichert, mit Nummer und Datum der
// zuletzt festgehaltenen Version (F29). Die festgehaltenen Versionen
// stehen als Liste in prozessHistorie.
//
// Früher bestand der Prozess aus frei angelegten Abschnitten mit Feldern
// (auch aus der Suite). Beim ersten Öffnen werden sie zur Kette (F34,
// prozess_kette.dart); gelesen werden sie weiter, damit Einträge im
// Verlauf und nicht geöffnete Projekte lesbar bleiben.

/// Wie ein Feld eines früheren Abschnitts eingegeben wurde.
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

/// Ein Feld eines früheren Abschnitts.
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

/// Ein früherer Abschnitt, etwa „Garen und Braten" — aus der Zeit vor der
/// Kette.
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

/// Ein Wert eines Schritts — wie ein Parameter im Artikel.
class ProzessWert {
  const ProzessWert({
    required this.name,
    this.wert = '',
    this.einheit = '',
    this.gruppe = '',
    this.eigen = false,
  });

  final String name;
  final String wert;

  /// Die Einheit aus dem Steckbrief der Anlage, etwa „°C".
  final String einheit;

  /// Die Parametergruppe wie im Artikel: MASCHINENEINSTELLUNGEN für Werte
  /// aus dem Steckbrief, BRATSTRASSE oder DAMPFTUNNEL für die Platten,
  /// CUSTOM für eigene Werte. Aus einem Artikel übernommene Werte behalten
  /// ihre Gruppe.
  final String gruppe;

  /// Selbst angelegt — im Artikel `istCustom`.
  final bool eigen;

  bool get leer => wert.trim().isEmpty;

  /// „Kerntemperatur (°C)".
  String get label => einheit.trim().isEmpty ? name : '$name ($einheit)';

  /// Gruppe und Name — so werden Werte zweier Stände einander zugeordnet.
  String get schluessel =>
      '${gruppe.trim().toLowerCase()}/${name.trim().toLowerCase()}';

  ProzessWert kopie({String? name, String? wert}) => ProzessWert(
        name: name ?? this.name,
        wert: wert ?? this.wert,
        einheit: einheit,
        gruppe: gruppe,
        eigen: eigen,
      );

  Map<String, Object> toJson() => {
        'name': name,
        'wert': wert,
        if (einheit.isNotEmpty) 'einheit': einheit,
        if (gruppe.isNotEmpty) 'gruppe': gruppe,
        if (eigen) 'eigen': true,
      };

  static ProzessWert ausJson(Map<String, dynamic> j) {
    String t(String k) => j[k] is String ? j[k] as String : '';
    return ProzessWert(
      name: t('name'),
      wert: t('wert'),
      einheit: t('einheit'),
      gruppe: t('gruppe'),
      eigen: j['eigen'] == true,
    );
  }
}

/// Ein Schritt der Prozesskette: eine Anlage — oder nur ein
/// Prozessschritt, etwa „Abkühlen".
class ProzessSchritt {
  const ProzessSchritt({
    required this.id,
    this.abteilung = '',
    this.maschineId,
    this.maschine = '',
    this.prozessschritt = '',
    this.notiz = '',
    this.werte = const [],
  });

  final String id;

  /// Für welche Abteilung der Schritt arbeitet (der gespeicherte Wert der
  /// Abteilung) — leer: noch keine. Hintereinander stehende Schritte
  /// derselben Abteilung bilden eine Station.
  final String abteilung;

  /// Die Anlage im Katalog der Planung — null ohne Anlage.
  final String? maschineId;

  /// Ihr Name; er bleibt, auch wenn die Anlage aus dem Katalog
  /// verschwindet.
  final String maschine;

  /// Was hier geschieht, etwa „Braten" oder „Abkühlen".
  final String prozessschritt;

  /// Die Maschineneinstellungen als freier Text.
  final String notiz;

  final List<ProzessWert> werte;

  /// Wie der Schritt heißt: die Anlage, sonst der Prozessschritt — leer,
  /// wenn es beides nicht gibt.
  String get name {
    final m = maschine.trim();
    if (m.isNotEmpty) return m;
    return prozessschritt.trim();
  }

  /// [name] — ohne einen „Schritt n".
  String bezeichnung(int nummer) => name.isEmpty ? 'Schritt $nummer' : name;

  ProzessSchritt kopie({
    String? id,
    String? abteilung,
    String? prozessschritt,
    String? notiz,
    List<ProzessWert>? werte,
  }) =>
      ProzessSchritt(
        id: id ?? this.id,
        abteilung: abteilung ?? this.abteilung,
        maschineId: maschineId,
        maschine: maschine,
        prozessschritt: prozessschritt ?? this.prozessschritt,
        notiz: notiz ?? this.notiz,
        werte: werte ?? this.werte,
      );

  /// Mit einer anderen Anlage — [maschineId] null: keine aus dem Katalog,
  /// [maschine] bleibt dann als Text (leer: ohne Anlage).
  ProzessSchritt mitAnlage(String? maschineId, String maschine) =>
      ProzessSchritt(
        id: id,
        abteilung: abteilung,
        maschineId: maschineId,
        maschine: maschine,
        prozessschritt: prozessschritt,
        notiz: notiz,
        werte: werte,
      );

  Map<String, Object> toJson() => {
        'id': id,
        'abteilung': abteilung,
        if (maschineId != null) 'maschineId': maschineId!,
        if (maschine.isNotEmpty) 'maschine': maschine,
        if (prozessschritt.isNotEmpty) 'prozessschritt': prozessschritt,
        if (notiz.isNotEmpty) 'notiz': notiz,
        if (werte.isNotEmpty) 'werte': [for (final w in werte) w.toJson()],
      };

  static ProzessSchritt ausJson(Map<String, dynamic> j) {
    String t(String k) => j[k] is String ? j[k] as String : '';
    final werte = j['werte'];
    final maschineId = j['maschineId'];
    return ProzessSchritt(
      id: '${j['id'] ?? ''}',
      abteilung: t('abteilung'),
      maschineId:
          maschineId is String && maschineId.isNotEmpty ? maschineId : null,
      maschine: t('maschine'),
      prozessschritt: t('prozessschritt'),
      notiz: t('notiz'),
      werte: [
        if (werte is List)
          for (final w in werte)
            if (w is Map<String, dynamic>) ProzessWert.ausJson(w),
      ],
    );
  }
}

/// Der Prozess eines Projekts.
class Prozessparameter {
  const Prozessparameter({
    this.version = '1.0',
    this.stand,
    this.schritte = const [],
    this.abschnitte = const [],
  });

  final String version;
  final DateTime? stand;

  /// Die Kette, in Prozessreihenfolge.
  final List<ProzessSchritt> schritte;

  /// Abschnitte aus der Zeit vor der Kette — beim Öffnen werden sie zu
  /// Schritten (F34).
  final List<ProzessAbschnitt> abschnitte;

  bool get leer => schritte.isEmpty && abschnitte.isEmpty;

  /// Steht etwas darin — eine Kette, oder frühere Abschnitte mit Werten?
  bool get beschrieben =>
      schritte.isNotEmpty ||
      abschnitte.any((a) => a.felder.any((f) => f.wert.trim().isNotEmpty));

  Prozessparameter kopie({
    String? version,
    DateTime? stand,
    List<ProzessSchritt>? schritte,
  }) =>
      Prozessparameter(
        version: version ?? this.version,
        stand: stand ?? this.stand,
        schritte: schritte ?? this.schritte,
        abschnitte: abschnitte,
      );

  Map<String, Object> toJson() => {
        'version': version,
        if (stand != null) 'stand': stand!.toIso8601String(),
        if (schritte.isNotEmpty)
          'schritte': [for (final s in schritte) s.toJson()],
        if (abschnitte.isNotEmpty)
          'abschnitte': [for (final a in abschnitte) a.toJson()],
      };

  /// JSON für die Datenbank — null, wenn nichts darin steht.
  String? alsJson() => leer ? null : jsonEncode(toJson());

  static Prozessparameter ausJson(Object? json, {bool suite = false}) {
    if (json is! Map<String, dynamic>) return const Prozessparameter();
    final abschnitte = json[suite ? 'sections' : 'abschnitte'];
    final schritte = suite ? null : json['schritte'];
    final stand = json[suite ? 'updatedAt' : 'stand'];
    return Prozessparameter(
      version: json['version'] is String ? json['version'] as String : '1.0',
      stand: stand is String ? DateTime.tryParse(stand) : null,
      schritte: [
        if (schritte is List)
          for (final s in schritte)
            if (s is Map<String, dynamic>) ProzessSchritt.ausJson(s),
      ],
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

/// Ein festgehaltener Stand des Prozesses.
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

  ProzessStand mitParameter(Prozessparameter neu) => ProzessStand(
        version: version,
        datum: datum,
        notiz: notiz,
        parameter: neu,
      );

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

  static String? listeZuJson(List<ProzessStand> liste) =>
      liste.isEmpty ? null : jsonEncode([for (final s in liste) s.toJson()]);

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

/// Ob zwei Stände dieselbe Kette (und dieselben früheren Abschnitte) mit
/// denselben Werten haben — Nummer und Datum zählen nicht.
bool gleicheParameter(Prozessparameter a, Prozessparameter b) {
  String inhalt(Prozessparameter p) => jsonEncode([
        [for (final s in p.schritte) s.toJson()],
        [for (final x in p.abschnitte) x.toJson()],
      ]);
  return inhalt(a) == inhalt(b);
}

/// Wie der Arbeitsstand zu den festgehaltenen Versionen steht (F29).
class ProzessFassung {
  const ProzessFassung({this.version, this.datum, required this.geaendert});

  /// Die zuletzt festgehaltene Version — null, wenn es keine gibt.
  final String? version;
  final DateTime? datum;

  /// Weicht der Arbeitsstand von ihr ab — ohne Version: hat er Inhalt?
  final bool geaendert;

  /// „Version 1.1 vom 30.09.2026", „…, seitdem geändert" oder „Noch keine
  /// Version festgehalten".
  String get text {
    final v = version;
    final d = datum;
    if (v == null || d == null) return 'Noch keine Version festgehalten';
    return 'Version $v vom ${Format.datum(d)}'
        '${geaendert ? ', seitdem geändert' : ''}';
  }
}

/// Wie [arbeit] zu den festgehaltenen Versionen in [historie] steht.
ProzessFassung prozessFassung(
  Prozessparameter arbeit,
  List<ProzessStand> historie,
) {
  final letzte = historie.lastOrNull;
  if (letzte != null) {
    return ProzessFassung(
      version: letzte.version,
      datum: letzte.datum,
      geaendert: !gleicheParameter(letzte.parameter, arbeit),
    );
  }
  // Ohne festgehaltene Versionen: eine Nummer aus der Suite oder aus einer
  // früheren Version steht im Stand selbst.
  final stand = arbeit.stand;
  if (stand != null) {
    return ProzessFassung(
      version: arbeit.version,
      datum: stand,
      geaendert: false,
    );
  }
  return ProzessFassung(geaendert: !arbeit.leer);
}

/// Die nächste Versionsnummer nach [version]: „1.0" → „1.1" … „1.9" →
/// „2.0". Ohne lesbare Nummer beginnt es mit „1.0".
String naechsteVersion(String? version) {
  final v = double.tryParse((version ?? '').replaceAll(',', '.'));
  if (v == null) return '1.0';
  return ((v * 10).round() + 1).toString().replaceAllMapped(
        RegExp(r'^(\d*)(\d)$'),
        (m) => '${m[1]!.isEmpty ? '0' : m[1]}.${m[2]}',
      );
}

/// Die Nummer der nächsten Version, die festgehalten wird: nach der
/// zuletzt festgehaltenen — ohne sie nach einer Nummer im Stand selbst
/// (aus der Suite), sonst „1.0".
String naechsteProzessVersion(
  Prozessparameter arbeit,
  List<ProzessStand> historie,
) {
  final letzte = historie.lastOrNull;
  if (letzte != null) return naechsteVersion(letzte.version);
  return arbeit.stand == null ? '1.0' : naechsteVersion(arbeit.version);
}
