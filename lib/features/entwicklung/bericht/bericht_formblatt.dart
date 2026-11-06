import 'dart:convert';

import '../../../core/utils/format.dart';
import '../daten/dateien.dart';
import '../spezifikation/spezifikation_dienst.dart' show spezVorlageId;
import '../spezifikation/spezifikation_werte.dart' show SpezSprache;
import '../spezifikation/xlsx_kopflogo.dart';

// Kopf- und Fußzeile des Projektberichts — wie auf den Formblättern im
// Betrieb: oben links die Nummer des Formblatts, rechts das Logo, das auch
// die Spezifikation trägt; unten links, wer das Formblatt erstellt und
// geprüft hat, und seine Version, rechts sein Stand, welchen Stand er
// ersetzt, und darunter die Seite.
//
// Die Angaben trägt jeder selbst ein (Werkzeuge » Projektbericht oder im
// Druckfenster des Berichts). Sie liegen verschlüsselt bei den Dateien der
// Produktentwicklung — unter einer festen ID wie die Spezifikations-
// vorlagen — und wandern mit ihnen ins Backup. Das Logo liest die App beim
// Drucken aus der Kopfzeile der Spezifikationsvorlage, so wie sie gerade
// ist: Eine neue Vorlage bringt ihr Logo gleich mit.

/// Unter dieser ID liegen die Angaben bei den Dateien der Entwicklung.
const String kBerichtFormblattId = 'einstellung.projektbericht';

/// Kopf- und Fußzeile des Projektberichts.
class BerichtFormblatt {
  const BerichtFormblatt({
    this.nummer = '',
    this.erstelltVon = '',
    this.geprueftVon = '',
    this.version = '',
    this.stand = '',
    this.ersetzt = '',
    this.logoZeigen = true,
    this.logo,
  });

  /// Liest die gespeicherten Angaben — Fehlendes und Unlesbares bleibt
  /// leer.
  factory BerichtFormblatt.ausJson(Object? json) {
    if (json is! Map<String, dynamic>) return const BerichtFormblatt();
    String t(String schluessel) {
      final w = json[schluessel];
      return w is String ? w.trim() : '';
    }

    return BerichtFormblatt(
      nummer: t('nummer'),
      erstelltVon: t('erstelltVon'),
      geprueftVon: t('geprueftVon'),
      version: t('version'),
      stand: t('stand'),
      ersetzt: t('ersetzt'),
      logoZeigen: json['logoZeigen'] != false,
    );
  }

  /// Die Nummer des Formblatts — oben links.
  final String nummer;

  final String erstelltVon;
  final String geprueftVon;

  /// Die Version und was sich geändert hat.
  final String version;

  /// Seit wann dieser Stand gilt — und welchen er ersetzt. Freier Text,
  /// meist ein Datum.
  final String stand;
  final String ersetzt;

  /// Oben rechts das Logo aus der Spezifikationsvorlage.
  final bool logoZeigen;

  /// Das Logo — beim Laden gelesen, nicht gespeichert.
  final KopfLogo? logo;

  /// Nichts für Kopf und Fuß eingetragen.
  bool get leer => [
        nummer,
        erstelltVon,
        geprueftVon,
        version,
        stand,
        ersetzt,
      ].every((t) => t.trim().isEmpty);

  /// Unten links, untereinander — nur, was eingetragen ist.
  List<String> get fussLinks => [
        if (_text(erstelltVon) case final t?) 'Erstellt von: $t',
        if (_text(geprueftVon) case final t?) 'Geprüft von: $t',
        if (_text(version) case final t?) 'Version: $t',
      ];

  /// Unten rechts, untereinander.
  List<String> get fussRechts => [
        if (_text(stand) case final t?) 'Stand: $t',
        if (_text(ersetzt) case final t?) 'ersetzt den Stand: $t',
      ];

  BerichtFormblatt kopie({
    String? nummer,
    String? erstelltVon,
    String? geprueftVon,
    String? version,
    String? stand,
    String? ersetzt,
    bool? logoZeigen,
  }) =>
      BerichtFormblatt(
        nummer: nummer ?? this.nummer,
        erstelltVon: erstelltVon ?? this.erstelltVon,
        geprueftVon: geprueftVon ?? this.geprueftVon,
        version: version ?? this.version,
        stand: stand ?? this.stand,
        ersetzt: ersetzt ?? this.ersetzt,
        logoZeigen: logoZeigen ?? this.logoZeigen,
        logo: logo,
      );

  /// Dieselben Angaben mit [logo].
  BerichtFormblatt mitLogo(KopfLogo? logo) => BerichtFormblatt(
        nummer: nummer,
        erstelltVon: erstelltVon,
        geprueftVon: geprueftVon,
        version: version,
        stand: stand,
        ersetzt: ersetzt,
        logoZeigen: logoZeigen,
        logo: logo,
      );

  /// Eine neue Version ab [heute]: Beginnt die Version mit einer Zahl,
  /// zählt sie eins weiter (mit führenden Nullen) — was sich geändert
  /// hat, trägt man dahinter ein. Der Stand wird [heute], der bisherige
  /// zu dem, den er ersetzt.
  BerichtFormblatt neueVersion(DateTime heute) {
    final m = RegExp(r'^\s*(\d+)').firstMatch(version);
    final nr = m?[1];
    return kopie(
      version: nr == null
          ? version
          : '${'${int.parse(nr) + 1}'.padLeft(nr.length, '0')} ',
      stand: Format.datum(heute),
      ersetzt: stand.trim().isEmpty ? ersetzt : stand.trim(),
    );
  }

  Map<String, Object> toJson() => {
        if (_text(nummer) case final t?) 'nummer': t,
        if (_text(erstelltVon) case final t?) 'erstelltVon': t,
        if (_text(geprueftVon) case final t?) 'geprueftVon': t,
        if (_text(version) case final t?) 'version': t,
        if (_text(stand) case final t?) 'stand': t,
        if (_text(ersetzt) case final t?) 'ersetzt': t,
        'logoZeigen': logoZeigen,
      };

  static String? _text(String t) => t.trim().isEmpty ? null : t.trim();
}

/// Liest die Angaben — ohne gespeicherte leer — und, wenn es gezeigt
/// werden soll, das Logo aus der Spezifikationsvorlage ([mitLogo]: false
/// lässt es weg). Lässt sich etwas nicht lesen, druckt der Bericht ohne:
/// Ein Formblatt soll nie den Druck verhindern.
Future<BerichtFormblatt> berichtFormblattLaden(
  EntwicklungDateienDienst dateien, {
  bool mitLogo = true,
}) async {
  var formblatt = const BerichtFormblatt();
  try {
    final inhalt = await dateien.lesen(kBerichtFormblattId);
    if (inhalt != null) {
      formblatt = BerichtFormblatt.ausJson(jsonDecode(utf8.decode(inhalt)));
    }
  } catch (_) {
    // Unlesbar — dann eben ohne Angaben.
  }
  if (!mitLogo || !formblatt.logoZeigen) return formblatt;
  return formblatt.mitLogo(await spezifikationsLogo(dateien));
}

/// Speichert die Angaben (ohne das Logo — das kommt aus der Vorlage).
Future<void> berichtFormblattSpeichern(
  EntwicklungDateienDienst dateien,
  BerichtFormblatt formblatt,
) async {
  await dateien.speichern(
    id: kBerichtFormblattId,
    name: 'Projektbericht Kopf- und Fußzeile.json',
    inhalt: utf8.encode(jsonEncode(formblatt.toJson())),
    mimeTyp: 'application/json',
  );
}

/// Das Logo aus der Kopfzeile der Spezifikationsvorlage — erst der
/// deutschen, dann der englischen. null ohne Vorlage oder ohne Logo darin.
Future<KopfLogo?> spezifikationsLogo(EntwicklungDateienDienst dateien) async {
  for (final sprache in SpezSprache.values) {
    try {
      final xlsx = await dateien.lesen(spezVorlageId(sprache));
      if (xlsx == null) continue;
      final logo = kopfzeilenLogo(xlsx);
      if (logo != null) return logo;
    } catch (_) {
      // Diese Vorlage lässt sich nicht lesen — die nächste.
    }
  }
  return null;
}
