import 'dart:convert';
import 'dart:typed_data';

import 'datei.dart';

/// Die längere Kante eines Fotos in Pixeln — darüber verkleinert die App
/// schon bei der Aufnahme. Reicht, um das Produkt am Bildschirm und im
/// Ausdruck gut zu erkennen, und hält ein Foto bei rund 300 KB.
const int kFotoKante = 1600;

/// Die JPEG-Qualität der Fotos (0–100).
const int kFotoQualitaet = 80;

/// Wozu ein Foto gehört.
enum FotoArt {
  /// Aus einer laufenden Produktion — gehört zum Artikel.
  produktion('produktion'),

  /// Ein Musterfoto — kommt im Planer in den Foto-Eingang der
  /// Produktentwicklung und wird dort einem Projekt zugeordnet.
  muster('muster');

  const FotoArt(this.schluessel);

  final String schluessel;

  static FotoArt aus(String? schluessel) {
    for (final a in values) {
      if (a.schluessel == schluessel) return a;
    }
    return FotoArt.muster;
  }
}

/// Ob [daten] wie ein JPEG beginnen.
bool istJpeg(List<int>? daten) =>
    daten != null &&
    daten.length > 3 &&
    daten[0] == 0xFF &&
    daten[1] == 0xD8 &&
    daten[2] == 0xFF;

/// Ein an der Anlage aufgenommenes Foto. In der Ergebnis-Datei steht das
/// Bild selbst dabei ([daten]); auf dem Handy liegt es als eigene Datei im
/// Ordner der App, der Stand der Erfassung kennt nur die Angaben.
class ErfasstesFoto {
  const ErfasstesFoto({
    required this.id,
    required this.art,
    required this.aufgenommenAm,
    this.artikelId,
    this.artikel,
    this.produktionId,
    this.bezeichnung,
    this.kuerzel,
    this.groesse = 0,
    this.daten,
  });

  /// Eindeutig über alle Handys — unter ihr legt der Planer das Foto ab
  /// und erkennt es wieder, wenn dieselbe Datei zweimal eingelesen wird.
  final String id;
  final FotoArt art;
  final DateTime aufgenommenAm;

  /// Der Artikel eines Produktionsfotos.
  final String? artikelId;

  /// Seine Bezeichnung — zur Anzeige.
  final String? artikel;

  /// Die geplante Produktion, bei der es aufgenommen wurde.
  final String? produktionId;

  /// Beim Musterfoto: wie das Muster heißt. Beim Produktionsfoto: eine
  /// freiwillige Bemerkung.
  final String? bezeichnung;

  final String? kuerzel;

  /// Größe des Bilds in Bytes.
  final int groesse;

  /// Das Bild als JPEG — null: liegt als Datei daneben.
  final Uint8List? daten;

  /// Dasselbe Foto mit seinem Bild.
  ErfasstesFoto mit(Uint8List bild) => ErfasstesFoto(
        id: id,
        art: art,
        aufgenommenAm: aufgenommenAm,
        artikelId: artikelId,
        artikel: artikel,
        produktionId: produktionId,
        bezeichnung: bezeichnung,
        kuerzel: kuerzel,
        groesse: bild.length,
        daten: bild,
      );

  /// „Musterfoto Pfeffer grob 2026-11-09_1745.jpg" — so heißt das Foto im
  /// Planer als Datei.
  String get dateiname {
    final name = (bezeichnung ?? artikel ?? '')
        .replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]'), ' ')
        .replaceAll(RegExp(' +'), ' ')
        .trim();
    final vorn = art == FotoArt.muster ? 'Musterfoto' : 'Foto';
    return '$vorn${name.isEmpty ? '' : ' $name'} '
        '${zeitstempelText(aufgenommenAm)}.jpg';
  }

  JsonObjekt toJson() => {
        'id': id,
        'art': art.schluessel,
        'aufgenommenAm': aufgenommenAm.toIso8601String(),
        if (artikelId != null) 'artikelId': artikelId,
        if (artikel != null) 'artikel': artikel,
        if (produktionId != null) 'produktion': produktionId,
        if (bezeichnung != null) 'bezeichnung': bezeichnung,
        if (kuerzel != null) 'kuerzel': kuerzel,
        'groesse': daten?.length ?? groesse,
        if (daten != null) 'daten': base64Encode(daten!),
      };

  static ErfasstesFoto ausJson(JsonObjekt j) {
    const wo = 'einem Foto';
    Uint8List? daten;
    final roh = jsonTextOder(j, 'daten');
    if (roh != null) {
      try {
        daten = base64Decode(roh);
      } on FormatException {
        throw const FormatFehler(
          'Die Datei ist beschädigt: Ein Foto lässt sich nicht lesen.',
        );
      }
    }
    return ErfasstesFoto(
      id: jsonText(j, 'id', wo),
      art: FotoArt.aus(jsonTextOder(j, 'art')),
      aufgenommenAm: jsonZeitpunkt(j, 'aufgenommenAm', wo),
      artikelId: jsonTextOder(j, 'artikelId'),
      artikel: jsonTextOder(j, 'artikel'),
      produktionId: jsonTextOder(j, 'produktion'),
      bezeichnung: jsonTextOder(j, 'bezeichnung'),
      kuerzel: jsonTextOder(j, 'kuerzel'),
      groesse: daten?.length ?? jsonGanzOder(j, 'groesse') ?? 0,
      daten: daten,
    );
  }
}
