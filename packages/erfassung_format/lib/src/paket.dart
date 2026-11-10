import 'datei.dart';
import 'grenze.dart';
import 'werte.dart';

/// Was der Planer fürs Handy mitgibt: die noch nicht erfassten
/// Produktionen der gewählten Wochen und die Maschineneinstellungen der
/// Artikel, so wie sie am PC stehen.
class ErfassungsPaket {
  const ErfassungsPaket({
    required this.id,
    required this.erstellt,
    required this.von,
    required this.bis,
    this.produktionen = const [],
    this.artikel = const [],
  });

  /// Kennung — das Ergebnis nennt sie, damit der Planer weiß, auf welchen
  /// Stand es sich bezieht.
  final String id;
  final DateTime erstellt;

  /// Die Tage der Produktionen: [von] bis einschließlich [bis].
  final DateTime von;
  final DateTime bis;

  final List<PaketProduktion> produktionen;
  final List<PaketArtikel> artikel;

  /// Der Artikel mit [id] — null, wenn er nicht im Paket steht.
  PaketArtikel? artikelMit(String id) {
    for (final a in artikel) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// „Planer-Erfassung_2026-11-09_1745.json".
  String get dateiname => 'Planer-Erfassung_${zeitstempelText(erstellt)}.json';

  JsonObjekt toJson() => {
        ...dateiKopf(DateiArt.paket),
        'id': id,
        'erstellt': erstellt.toIso8601String(),
        'von': tagText(von),
        'bis': tagText(bis),
        'produktionen': [for (final p in produktionen) p.toJson()],
        'artikel': [for (final a in artikel) a.toJson()],
      };

  /// Die Datei als Text.
  String alsText() => dateiText(toJson());

  /// Liest die Datei — oder wirft einen [FormatFehler] mit dem Grund.
  static ErfassungsPaket ausText(String text) =>
      ausJson(dateiLesen(text, DateiArt.paket));

  static ErfassungsPaket ausJson(JsonObjekt j) {
    const wo = 'dem Paket';
    return ErfassungsPaket(
      id: jsonText(j, 'id', wo),
      erstellt: jsonZeitpunkt(j, 'erstellt', wo),
      von: jsonTag(j, 'von', wo),
      bis: jsonTag(j, 'bis', wo),
      produktionen: [
        for (final p in jsonListe(j, 'produktionen', wo))
          PaketProduktion.ausJson(p),
      ],
      artikel: [
        for (final a in jsonListe(j, 'artikel', wo)) PaketArtikel.ausJson(a),
      ],
    );
  }
}

/// Eine geplante Produktion, die noch nicht erfasst ist — die Wurzel
/// ihrer Kette, wie in der Produktionserfassung des Planers.
class PaketProduktion {
  const PaketProduktion({
    required this.id,
    required this.artikelId,
    required this.artikelnummer,
    required this.artikel,
    required this.datum,
    required this.abteilung,
    required this.abteilungName,
    required this.rohKg,
    this.abteilungFarbe,
    this.start,
    this.fleischKg,
    this.fertigKg,
  });

  /// Der Auftrag (Wurzel der Kette) im Planer.
  final String id;
  final String artikelId;
  final String artikelnummer;

  /// Die Bezeichnung des Artikels.
  final String artikel;

  /// Der geplante Tag.
  final DateTime datum;

  /// Die erste Abteilung der Kette — Schlüssel, Name und Farbe wie im
  /// Planer.
  final String abteilung;
  final String abteilungName;
  final int? abteilungFarbe;

  /// Die geplante Startzeit („06:00").
  final String? start;

  /// Geplant: Rohware, davon Fleisch, Fertigware.
  final double rohKg;
  final double? fleischKg;
  final double? fertigKg;

  JsonObjekt toJson() => {
        'id': id,
        'artikelId': artikelId,
        'artikelnummer': artikelnummer,
        'artikel': artikel,
        'datum': tagText(datum),
        'abteilung': abteilung,
        'abteilungName': abteilungName,
        if (abteilungFarbe != null) 'abteilungFarbe': abteilungFarbe,
        if (start != null) 'start': start,
        'rohKg': rohKg,
        if (fleischKg != null) 'fleischKg': fleischKg,
        if (fertigKg != null) 'fertigKg': fertigKg,
      };

  static PaketProduktion ausJson(JsonObjekt j) {
    const wo = 'einer Produktion';
    return PaketProduktion(
      id: jsonText(j, 'id', wo),
      artikelId: jsonText(j, 'artikelId', wo),
      artikelnummer: jsonTextOder(j, 'artikelnummer') ?? '',
      artikel: jsonTextOder(j, 'artikel') ?? '',
      datum: jsonTag(j, 'datum', wo),
      abteilung: jsonTextOder(j, 'abteilung') ?? '',
      abteilungName: jsonTextOder(j, 'abteilungName') ?? '',
      abteilungFarbe: jsonGanzOder(j, 'abteilungFarbe'),
      start: zeitAus(jsonTextOder(j, 'start')),
      rohKg: jsonZahl(j, 'rohKg', wo),
      fleischKg: jsonZahlOder(j, 'fleischKg'),
      fertigKg: jsonZahlOder(j, 'fertigKg'),
    );
  }
}

/// Ein Artikel mit den Schritten seiner Prozesskette und ihren
/// Maschineneinstellungen.
class PaketArtikel {
  const PaketArtikel({
    required this.id,
    required this.nummer,
    required this.name,
    this.schritte = const [],
  });

  final String id;
  final String nummer;
  final String name;
  final List<PaketSchritt> schritte;

  /// Wonach die Suche in der App sucht: Nummer und Name, klein.
  String get suchtext => '$nummer $name'.toLowerCase();

  /// Der Schritt mit [id] — null, wenn es ihn nicht gibt.
  PaketSchritt? schrittMit(String id) {
    for (final s in schritte) {
      if (s.id == id) return s;
    }
    return null;
  }

  JsonObjekt toJson() => {
        'id': id,
        'nummer': nummer,
        'name': name,
        'schritte': [for (final s in schritte) s.toJson()],
      };

  static PaketArtikel ausJson(JsonObjekt j) {
    const wo = 'einem Artikel';
    return PaketArtikel(
      id: jsonText(j, 'id', wo),
      nummer: jsonTextOder(j, 'nummer') ?? '',
      name: jsonTextOder(j, 'name') ?? '',
      schritte: [
        for (final s in jsonListe(j, 'schritte', wo)) PaketSchritt.ausJson(s),
      ],
    );
  }
}

/// Ein Schritt der Prozesskette: an welcher Anlage, in welcher Abteilung,
/// und welche Einstellungen er hat.
class PaketSchritt {
  const PaketSchritt({
    required this.id,
    required this.nummer,
    required this.abteilung,
    required this.abteilungName,
    required this.anlage,
    this.abteilungFarbe,
    this.prozessschritt,
    this.felder = const [],
  });

  final String id;

  /// Die Position in der Kette, ab 1.
  final int nummer;

  final String abteilung;
  final String abteilungName;
  final int? abteilungFarbe;

  /// Der Name der Anlage — oder der Prozessschritt, wenn keine
  /// zugeordnet ist.
  final String anlage;
  final String? prozessschritt;

  final List<PaketFeld> felder;

  /// Das Feld mit [schluessel] — null, wenn es das nicht gibt.
  PaketFeld? feldMit(String schluessel) {
    for (final f in felder) {
      if (f.schluessel == schluessel) return f;
    }
    return null;
  }

  JsonObjekt toJson() => {
        'id': id,
        'nummer': nummer,
        'abteilung': abteilung,
        'abteilungName': abteilungName,
        if (abteilungFarbe != null) 'abteilungFarbe': abteilungFarbe,
        'anlage': anlage,
        if (prozessschritt != null) 'prozessschritt': prozessschritt,
        'felder': [for (final f in felder) f.toJson()],
      };

  static PaketSchritt ausJson(JsonObjekt j) {
    const wo = 'einem Schritt';
    return PaketSchritt(
      id: jsonText(j, 'id', wo),
      nummer: jsonGanzOder(j, 'nummer') ?? 0,
      abteilung: jsonTextOder(j, 'abteilung') ?? '',
      abteilungName: jsonTextOder(j, 'abteilungName') ?? '',
      abteilungFarbe: jsonGanzOder(j, 'abteilungFarbe'),
      anlage: jsonTextOder(j, 'anlage') ?? '',
      prozessschritt: jsonTextOder(j, 'prozessschritt'),
      felder: [
        for (final f in jsonListe(j, 'felder', wo)) PaketFeld.ausJson(f),
      ],
    );
  }
}

/// Woher ein Feld stammt — danach schreibt der Planer es zurück.
enum FeldArt {
  /// Ein Feld aus dem Steckbrief der Anlage.
  steckbrief('steckbrief'),

  /// Ein weiterer Parameter des Schritts (aus der Excel oder selbst
  /// angelegt).
  parameter('parameter'),

  /// Eine Plattentemperatur (Bratstraße, Kombiofen).
  platte('platte'),

  /// Die freie Notiz „Maschineneinstellungen".
  notiz('notiz');

  const FeldArt(this.schluessel);

  final String schluessel;

  static FeldArt aus(String? text) {
    for (final a in values) {
      if (a.schluessel == text) return a;
    }
    return parameter;
  }
}

/// Ein Wert, den man an der Anlage ablesen und eintragen kann.
class PaketFeld {
  const PaketFeld({
    required this.schluessel,
    required this.art,
    required this.name,
    this.einheit,
    this.gruppe,
    this.wert,
    this.grenze,
  });

  /// Eindeutig im Schritt — der Planer findet das Feld darüber wieder.
  final String schluessel;
  final FeldArt art;
  final String name;
  final String? einheit;

  /// Die Parametergruppe im Planer — nur zur Anzeige.
  final String? gruppe;

  /// Der Stand am PC beim Erstellen des Pakets.
  final String? wert;

  final Grenze? grenze;

  /// Ob eine Zahl erwartet wird — dann zeigt die App die Zahlentastatur.
  bool get istZahl {
    if (art == FeldArt.platte) return true;
    if (art == FeldArt.notiz) return false;
    final w = wert?.trim() ?? '';
    final zahlenhaft = w.isEmpty || zahlAus(w) != null;
    return zahlenhaft && (grenze != null || (einheit ?? '').trim().isNotEmpty);
  }

  /// „Temperatur (°C)".
  String get beschriftung {
    final e = einheit?.trim() ?? '';
    return e.isEmpty ? name : '$name ($e)';
  }

  JsonObjekt toJson() => {
        'schluessel': schluessel,
        'art': art.schluessel,
        'name': name,
        if (einheit != null) 'einheit': einheit,
        if (gruppe != null) 'gruppe': gruppe,
        if (wert != null) 'wert': wert,
        if (grenze != null) 'grenze': grenze!.toJson(),
      };

  static PaketFeld ausJson(JsonObjekt j) {
    const wo = 'einem Feld';
    return PaketFeld(
      schluessel: jsonText(j, 'schluessel', wo),
      art: FeldArt.aus(jsonTextOder(j, 'art')),
      name: jsonText(j, 'name', wo),
      einheit: jsonTextOder(j, 'einheit'),
      gruppe: jsonTextOder(j, 'gruppe'),
      wert: jsonTextOder(j, 'wert'),
      grenze: Grenze.ausJson(jsonObjektOder(j, 'grenze')),
    );
  }
}
