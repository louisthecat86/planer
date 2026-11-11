import 'datei.dart';
import 'foto.dart';
import 'paket.dart';
import 'werte.dart';

/// Was vom Handy zurückkommt: die erfassten Produktionen, die an der
/// Anlage geänderten Maschineneinstellungen und die Fotos.
class ErfassungsErgebnis {
  const ErfassungsErgebnis({
    required this.paketId,
    required this.erstellt,
    this.paketErstellt,
    this.produktionen = const [],
    this.werte = const [],
    this.fotos = const [],
  });

  /// Das Paket, auf dem die Erfassung beruht.
  final String paketId;
  final DateTime? paketErstellt;

  final DateTime erstellt;
  final List<ErfassteProduktion> produktionen;
  final List<GeaenderterWert> werte;

  /// Die Fotos samt Bild.
  final List<ErfasstesFoto> fotos;

  bool get leer => produktionen.isEmpty && werte.isEmpty && fotos.isEmpty;

  /// „Planer-Erfassung-Ergebnis_2026-11-09_1810_AB.json".
  String dateiname({String? kuerzel}) {
    final k =
        (kuerzel ?? '').trim().replaceAll(RegExp(r'[^A-Za-z0-9ÄÖÜäöüß]'), '');
    return 'Planer-Erfassung-Ergebnis_${zeitstempelText(erstellt)}'
        '${k.isEmpty ? '' : '_$k'}.json';
  }

  JsonObjekt toJson() => {
        // Mit Fotos die neue Fassung: Ein Planer auf älterem Stand sagt
        // dann, dass er die Datei nicht liest — statt die Fotos
        // stillschweigend wegzulassen.
        ...dateiKopf(
          DateiArt.ergebnis,
          version: fotos.isEmpty ? kFormatVersionOhneFotos : kFormatVersion,
        ),
        'paket': paketId,
        if (paketErstellt != null)
          'paketErstellt': paketErstellt!.toIso8601String(),
        'erstellt': erstellt.toIso8601String(),
        'produktionen': [for (final p in produktionen) p.toJson()],
        'werte': [for (final w in werte) w.toJson()],
        if (fotos.isNotEmpty) 'fotos': [for (final f in fotos) f.toJson()],
      };

  /// Die Datei als Text.
  String alsText() => dateiText(toJson());

  /// Liest die Datei — oder wirft einen [FormatFehler] mit dem Grund.
  static ErfassungsErgebnis ausText(String text) =>
      ausJson(dateiLesen(text, DateiArt.ergebnis));

  static ErfassungsErgebnis ausJson(JsonObjekt j) {
    const wo = 'dem Ergebnis';
    final paketErstellt = jsonTextOder(j, 'paketErstellt');
    return ErfassungsErgebnis(
      paketId: jsonText(j, 'paket', wo),
      paketErstellt:
          paketErstellt == null ? null : DateTime.tryParse(paketErstellt),
      erstellt: jsonZeitpunkt(j, 'erstellt', wo),
      produktionen: [
        for (final p in jsonListe(j, 'produktionen', wo))
          ErfassteProduktion.ausJson(p),
      ],
      werte: [
        for (final w in jsonListe(j, 'werte', wo)) GeaenderterWert.ausJson(w),
      ],
      fotos: [
        for (final f in jsonListe(j, 'fotos', wo)) ErfasstesFoto.ausJson(f),
      ],
    );
  }
}

/// Was an einer Erfassung nicht stimmt — null, wenn alles passt. Gilt in
/// der App beim Speichern und im Planer beim Einlesen.
String? produktionFehler({
  required double? rohKg,
  double? fleischKg,
  double? fertigKg,
}) {
  if (rohKg == null || rohKg <= 0) {
    return 'Bitte die Rohware (kg) eintragen.';
  }
  if (fleischKg != null && fleischKg > rohKg) {
    return 'Die Fleischeinwaage ist ein Teil der Rohware — sie kann nicht '
        'größer sein.';
  }
  // Ein Schritt verliert Gewicht oder bleibt gleich — mehr Fertigware als
  // Rohware ist immer ein Tippfehler.
  if (fertigKg != null && fertigKg > rohKg) {
    return 'Mehr Fertigware als Rohware geht nicht — bitte prüfen.';
  }
  return null;
}

/// Eine an der Anlage erfasste Produktion.
class ErfassteProduktion {
  const ErfassteProduktion({
    required this.produktionId,
    required this.artikelId,
    required this.artikel,
    required this.datum,
    required this.rohKg,
    required this.erfasstAm,
    this.fleischKg,
    this.fertigKg,
    this.start,
    this.ende,
    this.charge,
    this.kuerzel,
    this.bemerkung,
  });

  /// Der Auftrag (Wurzel der Kette) aus dem Paket.
  final String produktionId;
  final String artikelId;

  /// Die Bezeichnung des Artikels — zur Anzeige.
  final String artikel;

  /// Der Tag der Produktion.
  final DateTime datum;

  final double rohKg;
  final double? fleischKg;
  final double? fertigKg;

  /// „HH:MM".
  final String? start;
  final String? ende;

  final String? charge;
  final String? kuerzel;
  final String? bemerkung;

  final DateTime erfasstAm;

  /// Die Notiz, wie sie im Planer an der Produktion steht: Bemerkung,
  /// Charge und wer erfasst hat.
  String? get notiz {
    String? leerZuNull(String? s) {
      final t = s?.trim();
      return t == null || t.isEmpty ? null : t;
    }

    final teile = [
      if (leerZuNull(bemerkung) case final b?) b,
      if (leerZuNull(charge) case final c?) 'Charge $c',
      if (leerZuNull(kuerzel) case final k?) 'erfasst von $k',
    ];
    return teile.isEmpty ? null : teile.join(' · ');
  }

  /// Minuten von Start bis Ende.
  double? get dauerMin => dauerMinuten(start, ende);

  JsonObjekt toJson() => {
        'produktion': produktionId,
        'artikelId': artikelId,
        'artikel': artikel,
        'datum': tagText(datum),
        'rohKg': rohKg,
        if (fleischKg != null) 'fleischKg': fleischKg,
        if (fertigKg != null) 'fertigKg': fertigKg,
        if (start != null) 'start': start,
        if (ende != null) 'ende': ende,
        if (charge != null) 'charge': charge,
        if (kuerzel != null) 'kuerzel': kuerzel,
        if (bemerkung != null) 'bemerkung': bemerkung,
        'erfasstAm': erfasstAm.toIso8601String(),
      };

  static ErfassteProduktion ausJson(JsonObjekt j) {
    const wo = 'einer erfassten Produktion';
    return ErfassteProduktion(
      produktionId: jsonText(j, 'produktion', wo),
      artikelId: jsonText(j, 'artikelId', wo),
      artikel: jsonTextOder(j, 'artikel') ?? '',
      datum: jsonTag(j, 'datum', wo),
      rohKg: jsonZahl(j, 'rohKg', wo),
      fleischKg: jsonZahlOder(j, 'fleischKg'),
      fertigKg: jsonZahlOder(j, 'fertigKg'),
      start: zeitAus(jsonTextOder(j, 'start')),
      ende: zeitAus(jsonTextOder(j, 'ende')),
      charge: jsonTextOder(j, 'charge'),
      kuerzel: jsonTextOder(j, 'kuerzel'),
      bemerkung: jsonTextOder(j, 'bemerkung'),
      erfasstAm: jsonZeitpunkt(j, 'erfasstAm', wo),
    );
  }
}

/// Eine an der Anlage geänderte Maschineneinstellung: der Stand im Paket
/// und der neue Wert. Der Planer übernimmt sie nur, wenn am PC noch der
/// alte Stand steht — sonst zeigt er den Unterschied.
class GeaenderterWert {
  const GeaenderterWert({
    required this.artikelId,
    required this.schrittId,
    required this.schluessel,
    required this.art,
    required this.name,
    required this.erfasstAm,
    this.alt,
    this.neu,
    this.kuerzel,
  });

  final String artikelId;
  final String schrittId;

  /// Der Schlüssel des Felds im Schritt (PaketFeld.schluessel).
  final String schluessel;
  final FeldArt art;
  final String name;

  /// Der Stand im Paket.
  final String? alt;

  /// Der erfasste Wert — leer heißt: Wert löschen.
  final String? neu;

  final String? kuerzel;
  final DateTime erfasstAm;

  JsonObjekt toJson() => {
        'artikelId': artikelId,
        'schrittId': schrittId,
        'schluessel': schluessel,
        'art': art.schluessel,
        'name': name,
        if (alt != null) 'alt': alt,
        if (neu != null) 'neu': neu,
        if (kuerzel != null) 'kuerzel': kuerzel,
        'erfasstAm': erfasstAm.toIso8601String(),
      };

  static GeaenderterWert ausJson(JsonObjekt j) {
    const wo = 'einem geänderten Wert';
    return GeaenderterWert(
      artikelId: jsonText(j, 'artikelId', wo),
      schrittId: jsonText(j, 'schrittId', wo),
      schluessel: jsonText(j, 'schluessel', wo),
      art: FeldArt.aus(jsonTextOder(j, 'art')),
      name: jsonTextOder(j, 'name') ?? '',
      alt: jsonTextOder(j, 'alt'),
      neu: jsonTextOder(j, 'neu'),
      kuerzel: jsonTextOder(j, 'kuerzel'),
      erfasstAm: jsonZeitpunkt(j, 'erfasstAm', wo),
    );
  }
}
