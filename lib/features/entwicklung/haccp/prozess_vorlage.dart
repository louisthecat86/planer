import 'dart:convert';

import 'prozess_modell.dart';

// Vorlage und Versionen der Prozessparameter.
//
// Die eingebaute Vorlage nennt nur allgemeine Arbeitsschritte der
// Fleischverarbeitung — keine Firma, keine Anlage. Wer eigene Abschnitte
// braucht, speichert ein Projekt als Vorlage; die liegt dann verschlüsselt
// bei den Entwicklungsdaten (siehe ProzessVorlageDienst).

/// Die ID der gespeicherten eigenen Vorlage unter den Entwicklungsdateien.
const String kProzessVorlageDateiId = 'vorlage.prozess';

/// Die eingebaute, neutrale Vorlage.
const Prozessparameter kNeutraleProzessVorlage = Prozessparameter(
  abschnitte: [
    ProzessAbschnitt(
      id: 'rohware',
      titel: 'Rohware und Vorbereitung',
      felder: [
        ProzessFeld(id: 'rohware', label: 'Rohware (Teilstück, Sortierung)'),
        ProzessFeld(id: 'temperatur', label: 'Temperatur der Rohware (°C)'),
        ProzessFeld(
          id: 'zerkleinern',
          label: 'Zerkleinern (Wolf, Lochscheibe, Schnitt)',
          typ: FeldTyp.langtext,
        ),
      ],
    ),
    ProzessAbschnitt(
      id: 'verarbeitung',
      titel: 'Verarbeitung',
      felder: [
        ProzessFeld(id: 'anlage', label: 'Anlage'),
        ProzessFeld(
          id: 'ablauf',
          label: 'Programm und Ablauf',
          typ: FeldTyp.langtext,
        ),
        ProzessFeld(id: 'endtemperatur', label: 'Endtemperatur (°C)'),
      ],
    ),
    ProzessAbschnitt(
      id: 'formen',
      titel: 'Formen und Füllen',
      felder: [
        ProzessFeld(id: 'huelle', label: 'Hülle oder Form'),
        ProzessFeld(id: 'kaliber', label: 'Kaliber oder Maße'),
        ProzessFeld(id: 'stueckgewicht', label: 'Stückgewicht (g)'),
      ],
    ),
    ProzessAbschnitt(
      id: 'garen',
      titel: 'Garen und Braten',
      felder: [
        ProzessFeld(id: 'anlage', label: 'Anlage'),
        ProzessFeld(id: 'temperaturen', label: 'Temperaturen (°C)'),
        ProzessFeld(id: 'zeit', label: 'Zeit oder Bandgeschwindigkeit'),
        ProzessFeld(id: 'kerntemperatur', label: 'Kerntemperatur Ziel (°C)'),
      ],
    ),
    ProzessAbschnitt(
      id: 'kuehlen',
      titel: 'Kühlen und Frosten',
      felder: [
        ProzessFeld(id: 'anlage', label: 'Anlage'),
        ProzessFeld(
          id: 'temperatur',
          label: 'Temperatur oder Zonen',
          typ: FeldTyp.langtext,
        ),
        ProzessFeld(id: 'dauer', label: 'Verweildauer'),
      ],
    ),
    ProzessAbschnitt(
      id: 'verpackung',
      titel: 'Verpackung',
      felder: [
        ProzessFeld(
          id: 'art',
          label: 'Verpackungsart',
          typ: FeldTyp.auswahl,
          optionen: ['Vakuum', 'Schutzatmosphäre', 'offen'],
        ),
        ProzessFeld(
          id: 'inhalt',
          label: 'Packungsinhalt',
          typ: FeldTyp.auswahl,
          optionen: ['egalisiert', 'gewogen'],
        ),
        ProzessFeld(id: 'zielgewicht', label: 'Zielgewicht (g)'),
        ProzessFeld(
          id: 'einstellungen',
          label: 'Maschine und Einstellungen',
          typ: FeldTyp.langtext,
        ),
      ],
    ),
    ProzessAbschnitt(
      id: 'umverpackung',
      titel: 'Umverpackung und Kennzeichnung',
      felder: [
        ProzessFeld(id: 'umverpackung', label: 'Umverpackung'),
        ProzessFeld(id: 'anzahl', label: 'Packungen je Umverpackung'),
        ProzessFeld(id: 'haltbarkeit', label: 'Haltbarkeit (Tage)'),
        ProzessFeld(id: 'lagerung', label: 'Lagerung'),
      ],
    ),
  ],
);

/// Die Struktur ohne Werte — so wird ein Projekt zur Vorlage.
Prozessparameter alsVorlage(Prozessparameter p) => Prozessparameter(
      abschnitte: [
        for (final a in p.abschnitte)
          a.kopie(felder: [for (final f in a.felder) f.mitWert('')]),
      ],
    );

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

/// Eine Abweichung zwischen zwei Ständen der Prozessparameter.
class ParameterAenderung {
  const ParameterAenderung({
    required this.abschnitt,
    required this.feld,
    required this.alt,
    required this.neu,
  });

  final String abschnitt;
  final String feld;

  /// null: Das Feld gab es vorher nicht.
  final String? alt;

  /// null: Das Feld gibt es nicht mehr.
  final String? neu;
}

/// Was sich von [alt] nach [neu] geändert hat — Felder werden über die IDs
/// von Abschnitt und Feld zugeordnet.
List<ParameterAenderung> vergleicheParameter(
  Prozessparameter alt,
  Prozessparameter neu,
) {
  final ergebnis = <ParameterAenderung>[];
  Map<String, (ProzessAbschnitt, ProzessFeld)> felder(Prozessparameter p) => {
        for (final a in p.abschnitte)
          for (final f in a.felder) '${a.id}/${f.id}': (a, f),
      };
  final vorher = felder(alt);
  final nachher = felder(neu);
  for (final MapEntry(:key, value: (a, f)) in nachher.entries) {
    final v = vorher[key];
    if (v == null) {
      if (f.wert.trim().isNotEmpty) {
        ergebnis.add(
          ParameterAenderung(
            abschnitt: a.titel,
            feld: f.label,
            alt: null,
            neu: f.wert,
          ),
        );
      }
    } else if (v.$2.wert.trim() != f.wert.trim()) {
      ergebnis.add(
        ParameterAenderung(
          abschnitt: a.titel,
          feld: f.label,
          alt: v.$2.wert,
          neu: f.wert,
        ),
      );
    }
  }
  for (final MapEntry(:key, value: (a, f)) in vorher.entries) {
    if (!nachher.containsKey(key) && f.wert.trim().isNotEmpty) {
      ergebnis.add(
        ParameterAenderung(
          abschnitt: a.titel,
          feld: f.label,
          alt: f.wert,
          neu: null,
        ),
      );
    }
  }
  return ergebnis;
}

/// Liest eine gespeicherte Vorlage (JSON wie in der Datenbank). null, wenn
/// sie fehlt oder leer ist.
Prozessparameter? vorlageAus(List<int>? bytes) {
  if (bytes == null) return null;
  final p = Prozessparameter.aus(utf8.decode(bytes, allowMalformed: true));
  return p.leer ? null : p;
}

/// Eine eindeutige ID für einen neuen Abschnitt oder ein neues Feld.
String neueParameterId(String basis, Iterable<String> vorhanden) {
  final sauber = basis
      .toLowerCase()
      .replaceAll('ä', 'ae')
      .replaceAll('ö', 'oe')
      .replaceAll('ü', 'ue')
      .replaceAll('ß', 'ss')
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final grund = sauber.isEmpty ? 'feld' : sauber;
  final belegt = vorhanden.toSet();
  if (!belegt.contains(grund)) return grund;
  var i = 2;
  while (belegt.contains('$grund-$i')) {
    i++;
  }
  return '$grund-$i';
}
