import 'dart:convert';

import 'package:flutter/material.dart';

// Die festen Listen eines Entwicklungsprojekts: Status, Arten der
// Verlaufseinträge, Checklisten und die Sensorik.
//
// In der Datenbank stehen Checklisten und Sensorik als JSON-Text
// (EntwicklungProjekte) — hier die Schlüssel und das Lesen und Schreiben.

/// Wo ein Projekt steht. Zwei Zustände ruhen: Ein Muster, das nicht
/// weiter verfolgt wird (etwa weil der Kunde ein anderes gewählt hat), und
/// ein archiviertes Projekt. Beide lassen sich wieder aufnehmen.
enum ProjektStatus {
  entwicklung('entwicklung', 'In Entwicklung'),
  validierung('validierung', 'Validierung'),
  produktion('produktion', 'In Produktion'),
  eingestellt('eingestellt', 'Nicht weiter verfolgt'),
  archiviert('archiviert', 'Archiviert');

  const ProjektStatus(this.schluessel, this.label);

  final String schluessel;
  final String label;

  /// Ob das Projekt ruht — nicht weiter verfolgt oder archiviert.
  bool get ruht =>
      this == ProjektStatus.eingestellt || this == ProjektStatus.archiviert;

  static ProjektStatus aus(String? text) {
    switch (text?.trim().toLowerCase()) {
      case 'validierung':
      case 'validation':
        return ProjektStatus.validierung;
      case 'produktion':
      case 'production':
        return ProjektStatus.produktion;
      case 'eingestellt':
        return ProjektStatus.eingestellt;
      case 'archiviert':
      case 'archived':
        return ProjektStatus.archiviert;
      default:
        return ProjektStatus.entwicklung;
    }
  }
}

/// Welche Projekte die Projektliste zeigt — auf dem Schirm und im
/// Ausdruck.
enum ProjektFilter {
  aktiv('Aktiv'),
  entwicklung('In Entwicklung'),
  validierung('Validierung'),
  produktion('In Produktion'),
  eingestellt('Nicht weiter verfolgt'),
  archiv('Archiv');

  const ProjektFilter(this.label);

  final String label;

  /// „Aktiv" sind alle, die nicht ruhen.
  bool passt(ProjektStatus s) => switch (this) {
        ProjektFilter.aktiv => !s.ruht,
        ProjektFilter.entwicklung => s == ProjektStatus.entwicklung,
        ProjektFilter.validierung => s == ProjektStatus.validierung,
        ProjektFilter.produktion => s == ProjektStatus.produktion,
        ProjektFilter.eingestellt => s == ProjektStatus.eingestellt,
        ProjektFilter.archiv => s == ProjektStatus.archiviert,
      };
}

/// Art eines Eintrags im Verlauf.
enum EintragArt {
  meilenstein('meilenstein', 'Meilenstein', Icons.flag_outlined),
  rezeptur('rezeptur', 'Rezepturstand', Icons.menu_book_outlined),
  email('email', 'E-Mail', Icons.mail_outline),
  parameter('parameter', 'Parameter', Icons.tune),
  datei('datei', 'Datei', Icons.attach_file),
  notiz('notiz', 'Notiz', Icons.sticky_note_2_outlined);

  const EintragArt(this.schluessel, this.label, this.icon);

  final String schluessel;
  final String label;
  final IconData icon;

  static EintragArt aus(String? text) {
    switch (text?.trim().toLowerCase()) {
      case 'meilenstein':
      case 'milestone':
        return EintragArt.meilenstein;
      case 'rezeptur':
      case 'recipe':
        return EintragArt.rezeptur;
      case 'email':
        return EintragArt.email;
      case 'parameter':
        return EintragArt.parameter;
      case 'datei':
      case 'file':
        return EintragArt.datei;
      default:
        return EintragArt.notiz;
    }
  }
}

/// Stand eines Eintrags: Ist noch etwas zu tun oder nicht (F24)?
enum EintragStatus {
  offen('offen', 'offen'),
  erledigt('erledigt', 'erledigt');

  const EintragStatus(this.schluessel, this.label);

  final String schluessel;
  final String label;

  /// Der andere Status — zum Umschalten.
  EintragStatus get umgekehrt =>
      this == EintragStatus.offen ? EintragStatus.erledigt : EintragStatus.offen;

  /// Liest den Status. Frühere Werte — „erhalten" und „in Ordnung" (auch
  /// aus der Suite) — gelten als erledigt: Zu tun ist dort nichts mehr.
  static EintragStatus aus(String? text) {
    switch (text?.trim().toLowerCase()) {
      case 'erledigt':
      case 'completed':
      case 'erhalten':
      case 'received':
      case 'ok':
        return EintragStatus.erledigt;
      default:
        return EintragStatus.offen;
    }
  }
}

/// Ein Punkt einer Checkliste: Schlüssel im JSON und Text.
typedef CheckPunkt = ({String schluessel, String label});

/// Die Projekt-Checkliste — was bis zur Freigabe erledigt sein muss, in
/// der Reihenfolge der Arbeit. Die meisten Punkte rechnet die App selbst
/// (projekt_checkliste.dart).
const List<CheckPunkt> kProjektCheckliste = [
  (schluessel: 'rezepturErstellt', label: 'Rezeptur erstellt'),
  (schluessel: 'naehrwerteErstellt', label: 'Nährwerte berechnet'),
  (schluessel: 'sensorikErstellt', label: 'Sensorik beschrieben'),
  (schluessel: 'produktfotoHinterlegt', label: 'Produktfoto hinterlegt'),
  (schluessel: 'prozessErstellt', label: 'Prozess beschrieben'),
  (schluessel: 'spezifikationErstellt', label: 'Spezifikation erstellt'),
  (schluessel: 'etikettErstellt', label: 'Etikett erstellt'),
  (schluessel: 'artikelAngelegt', label: 'Artikel angelegt'),
  (schluessel: 'navisionAngelegt', label: 'In Navision angelegt'),
];

/// Die Etiketten-Checkliste — die Pflichtangaben nach LMIV Art. 9.
const List<CheckPunkt> kEtikettCheckliste = [
  (schluessel: 'bezeichnung', label: 'Bezeichnung des Lebensmittels'),
  (schluessel: 'zutaten', label: 'Zutatenverzeichnis'),
  (schluessel: 'allergene', label: 'Allergene hervorgehoben'),
  (schluessel: 'quid', label: 'Mengenangaben (QUID)'),
  (schluessel: 'nettofuellmenge', label: 'Nettofüllmenge'),
  (schluessel: 'mhd', label: 'Mindesthaltbarkeits- oder Verbrauchsdatum'),
  (schluessel: 'lagerung', label: 'Lager- und Verwendungsbedingungen'),
  (schluessel: 'anschrift', label: 'Name und Anschrift'),
  (schluessel: 'herkunft', label: 'Herkunft'),
  (schluessel: 'zubereitung', label: 'Gebrauchs- und Zubereitungshinweise'),
  (schluessel: 'naehrwerte', label: 'Nährwertdeklaration'),
  (schluessel: 'schutzgas', label: 'Unter Schutzatmosphäre verpackt'),
];

/// Schlüssel der alten Suite → Schlüssel hier.
const Map<String, String> kSuiteProjektCheckliste = {
  'articleCreated': 'artikelAngelegt',
  'recipeCreated': 'rezepturErstellt',
  'labelCreated': 'etikettErstellt',
  'nutritionCreated': 'naehrwerteErstellt',
  'specCreated': 'spezifikationErstellt',
  'processCreated': 'prozessErstellt',
  'navisionCreated': 'navisionAngelegt',
  'sensoryCreated': 'sensorikErstellt',
};

const Map<String, String> kSuiteEtikettCheckliste = {
  'name': 'bezeichnung',
  'ingredients': 'zutaten',
  'allergens': 'allergene',
  'quantity': 'quid',
  'netWeight': 'nettofuellmenge',
  'bestBefore': 'mhd',
  'storage': 'lagerung',
  'address': 'anschrift',
  'origin': 'herkunft',
  'instructions': 'zubereitung',
  'nutrition': 'naehrwerte',
  'gas': 'schutzgas',
};

/// Liest eine Checkliste aus dem JSON der Datenbank: erledigte Schlüssel.
Set<String> checklisteAus(String? json) {
  if (json == null || json.trim().isEmpty) return <String>{};
  try {
    final daten = jsonDecode(json);
    if (daten is! Map<String, dynamic>) return <String>{};
    return {
      for (final MapEntry(:key, :value) in daten.entries)
        if (value == true) key,
    };
  } on FormatException {
    return <String>{};
  }
}

/// Schreibt eine Checkliste als JSON — null, wenn nichts erledigt ist.
String? checklisteZuJson(Set<String> erledigt) => erledigt.isEmpty
    ? null
    : jsonEncode({for (final s in erledigt.toList()..sort()) s: true});

/// So steht „Später" im JSON der Projekt-Checkliste (F37): Der Punkt
/// bleibt offen, „Als Nächstes" geht aber an ihm vorbei. Ein erledigter
/// Punkt steht dort als `true`.
const String kCheckSpaeter = 'spaeter';

/// Die Punkte, die sich zurückstellen lassen — das Produktfoto, das es oft
/// erst gibt, wenn das Produkt fertig ist.
const Set<String> kCheckZurueckstellbar = {'produktfotoHinterlegt'};

/// Die zurückgestellten Punkte einer Checkliste.
Set<String> checklisteZurueckgestellt(String? json) {
  if (json == null || json.trim().isEmpty) return <String>{};
  try {
    final daten = jsonDecode(json);
    if (daten is! Map<String, dynamic>) return <String>{};
    return {
      for (final MapEntry(:key, :value) in daten.entries)
        if (value == kCheckSpaeter) key,
    };
  } on FormatException {
    return <String>{};
  }
}

/// Setzt [schluessel] im JSON einer Checkliste auf [wert]: `true`
/// (erledigt), [kCheckSpaeter] (zurückgestellt) oder null (offen). Alle
/// anderen Punkte bleiben, wie sie sind — null, wenn danach keiner mehr
/// drinsteht.
String? checklisteMit(String? json, String schluessel, Object? wert) {
  final daten = <String, Object?>{};
  if (json != null && json.trim().isNotEmpty) {
    try {
      final d = jsonDecode(json);
      if (d is Map<String, dynamic>) daten.addAll(d);
    } on FormatException {
      // Unlesbar: Es zählt, was jetzt gesetzt wird.
    }
  }
  if (wert == null) {
    daten.remove(schluessel);
  } else {
    daten[schluessel] = wert;
  }
  if (daten.isEmpty) return null;
  return jsonEncode({
    for (final k in daten.keys.toList()..sort()) k: daten[k],
  });
}

/// Wie eine Pflichtangabe des Etiketts steht (F28): offen, abgehakt oder
/// für dieses Produkt nicht zutreffend — etwa die Schutzatmosphäre bei
/// Vakuum.
enum LmivStand {
  offen,
  erledigt,
  trifftNichtZu;

  /// Geprüft: abgehakt oder „trifft nicht zu".
  bool get geprueft => this != LmivStand.offen;
}

/// So steht „trifft nicht zu" im JSON der Etiketten-Checkliste; ein
/// abgehakter Punkt steht dort wie in jeder Checkliste als `true`.
const String kLmivTrifftNichtZu = 'trifftNichtZu';

/// Liest die Etiketten-Checkliste: je Punkt abgehakt oder „trifft nicht
/// zu" — was nicht drinsteht, ist offen.
Map<String, LmivStand> lmivAus(String? json) {
  if (json == null || json.trim().isEmpty) return <String, LmivStand>{};
  try {
    final daten = jsonDecode(json);
    if (daten is! Map<String, dynamic>) return <String, LmivStand>{};
    return {
      for (final MapEntry(:key, :value) in daten.entries)
        if (value == true)
          key: LmivStand.erledigt
        else if (value == kLmivTrifftNichtZu)
          key: LmivStand.trifftNichtZu,
    };
  } on FormatException {
    return <String, LmivStand>{};
  }
}

/// Der Stand des Punkts [schluessel] — ohne Eintrag offen.
LmivStand lmivStand(Map<String, LmivStand> staende, String schluessel) =>
    staende[schluessel] ?? LmivStand.offen;

/// Schreibt die Etiketten-Checkliste als JSON — null, wenn alles offen ist.
String? lmivZuJson(Map<String, LmivStand> staende) {
  final schluessel = [
    for (final MapEntry(:key, :value) in staende.entries)
      if (value.geprueft) key,
  ]..sort();
  if (schluessel.isEmpty) return null;
  return jsonEncode(<String, Object>{
    for (final s in schluessel)
      s: staende[s] == LmivStand.erledigt ? true : kLmivTrifftNichtZu,
  });
}

/// Die sensorische Beschreibung eines Produkts.
class Sensorik {
  const Sensorik({
    this.aussehen = '',
    this.geruch = '',
    this.geschmack = '',
    this.konsistenz = '',
    this.laenge = '',
    this.durchmesser = '',
    this.gewicht = '',
    this.zubereitung = '',
  });

  final String aussehen;
  final String geruch;
  final String geschmack;
  final String konsistenz;
  final String laenge;
  final String durchmesser;
  final String gewicht;
  final String zubereitung;

  bool get leer => [
        aussehen,
        geruch,
        geschmack,
        konsistenz,
        laenge,
        durchmesser,
        gewicht,
        zubereitung,
      ].every((t) => t.trim().isEmpty);

  Map<String, String> toJson() => {
        if (aussehen.isNotEmpty) 'aussehen': aussehen,
        if (geruch.isNotEmpty) 'geruch': geruch,
        if (geschmack.isNotEmpty) 'geschmack': geschmack,
        if (konsistenz.isNotEmpty) 'konsistenz': konsistenz,
        if (laenge.isNotEmpty) 'laenge': laenge,
        if (durchmesser.isNotEmpty) 'durchmesser': durchmesser,
        if (gewicht.isNotEmpty) 'gewicht': gewicht,
        if (zubereitung.isNotEmpty) 'zubereitung': zubereitung,
      };

  /// JSON für die Datenbank — null, wenn nichts beschrieben ist.
  String? alsJson() => leer ? null : jsonEncode(toJson());

  static Sensorik aus(String? json) {
    if (json == null || json.trim().isEmpty) return const Sensorik();
    try {
      final d = jsonDecode(json);
      if (d is! Map<String, dynamic>) return const Sensorik();
      String t(String k) => d[k] is String ? d[k] as String : '';
      return Sensorik(
        aussehen: t('aussehen'),
        geruch: t('geruch'),
        geschmack: t('geschmack'),
        konsistenz: t('konsistenz'),
        laenge: t('laenge'),
        durchmesser: t('durchmesser'),
        gewicht: t('gewicht'),
        zubereitung: t('zubereitung'),
      );
    } on FormatException {
      return const Sensorik();
    }
  }

  /// Aus dem Format der alten Suite (englische Schlüssel, Maße
  /// verschachtelt).
  static Sensorik ausSuite(Object? json) {
    if (json is! Map<String, dynamic>) return const Sensorik();
    String t(Map<String, dynamic> m, String k) =>
        m[k] is String ? m[k] as String : '';
    final masse = json['dimensions'];
    final m = masse is Map<String, dynamic> ? masse : const <String, dynamic>{};
    return Sensorik(
      aussehen: t(json, 'appearance'),
      geruch: t(json, 'odor'),
      geschmack: t(json, 'taste'),
      konsistenz: t(json, 'texture'),
      laenge: t(m, 'length'),
      durchmesser: t(m, 'diameter'),
      gewicht: t(m, 'weight'),
      zubereitung: t(json, 'preparation'),
    );
  }

  Sensorik kopie({
    String? aussehen,
    String? geruch,
    String? geschmack,
    String? konsistenz,
    String? laenge,
    String? durchmesser,
    String? gewicht,
    String? zubereitung,
  }) =>
      Sensorik(
        aussehen: aussehen ?? this.aussehen,
        geruch: geruch ?? this.geruch,
        geschmack: geschmack ?? this.geschmack,
        konsistenz: konsistenz ?? this.konsistenz,
        laenge: laenge ?? this.laenge,
        durchmesser: durchmesser ?? this.durchmesser,
        gewicht: gewicht ?? this.gewicht,
        zubereitung: zubereitung ?? this.zubereitung,
      );
}

/// Ein Kommentar zu einem Eintrag im Verlauf.
class Kommentar {
  const Kommentar({required this.name, required this.text, required this.datum});

  final String name;
  final String text;
  final DateTime datum;

  Map<String, Object> toJson() => {
        'name': name,
        'text': text,
        'datum': datum.toIso8601String(),
      };

  static List<Kommentar> listeAus(String? json) {
    if (json == null || json.trim().isEmpty) return const [];
    try {
      final d = jsonDecode(json);
      if (d is! List) return const [];
      return [
        for (final k in d)
          if (k is Map<String, dynamic>)
            Kommentar(
              name: k['name'] is String ? k['name'] as String : '',
              text: k['text'] is String ? k['text'] as String : '',
              datum: DateTime.tryParse(
                    k['datum'] is String ? k['datum'] as String : '',
                  ) ??
                  DateTime(2000),
            ),
      ];
    } on FormatException {
      return const [];
    }
  }

  static String? listeZuJson(List<Kommentar> liste) => liste.isEmpty
      ? null
      : jsonEncode([for (final k in liste) k.toJson()]);
}

/// Liest eine JSON-Liste von Texten (etwa die Änderungen eines
/// Rezepturstands).
List<String> texteAus(String? json) {
  if (json == null || json.trim().isEmpty) return const [];
  try {
    final d = jsonDecode(json);
    if (d is! List) return const [];
    return [
      for (final t in d)
        if (t is String) t,
    ];
  } on FormatException {
    return const [];
  }
}

/// Schreibt eine Liste von Texten als JSON — null, wenn sie leer ist.
String? texteZuJson(List<String> texte) =>
    texte.isEmpty ? null : jsonEncode(texte);
