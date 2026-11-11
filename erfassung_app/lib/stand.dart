import 'dart:convert';
import 'dart:typed_data';

import 'package:erfassung_format/erfassung_format.dart';

// Der Stand der Erfassung auf dem Handy: das geöffnete Paket, die
// erfassten Produktionen, die geänderten Maschineneinstellungen, die Fotos
// und das Kürzel. Ohne Flutter — die Oberfläche hängt über
// [ErfassungsModell] (modell.dart) daran, gespeichert wird als eine
// JSON-Datei im Ordner der App. Von den Fotos stehen hier nur die Angaben;
// jedes Bild liegt als eigene Datei daneben.

/// Der Schlüssel eines geänderten Werts: Schritt und Feld.
String wertSchluessel(String schrittId, String feld) => '$schrittId|$feld';

/// Eine ID für ein neues Foto — eindeutig auch über mehrere Handys:
/// der Augenblick und eine Zufallszahl.
String neueFotoId(DateTime jetzt, int zufall) =>
    'f-${jetzt.microsecondsSinceEpoch.toRadixString(36)}-'
    '${zufall.toRadixString(36)}';

String? _leerZuNull(String? s) {
  final t = s?.trim();
  return t == null || t.isEmpty ? null : t;
}

class Erfassungsstand {
  Erfassungsstand({
    this.paket,
    this.kuerzel = '',
    Map<String, ErfassteProduktion>? produktionen,
    Map<String, GeaenderterWert>? werte,
    Map<String, ErfasstesFoto>? fotos,
    this.fotoWartend,
    this.gespeichertAm,
  })  : produktionen = produktionen ?? {},
        werte = werte ?? {},
        fotos = fotos ?? {};

  /// Das geöffnete Paket — null: noch keins.
  ErfassungsPaket? paket;

  /// Wer erfasst.
  String kuerzel;

  /// Die erfassten Produktionen nach ihrer ID im Paket (frei erfasste:
  /// eine eigene).
  final Map<String, ErfassteProduktion> produktionen;

  /// Die geänderten Werte nach [wertSchluessel].
  final Map<String, GeaenderterWert> werte;

  /// Die Fotos nach ihrer ID — nur die Angaben, ohne Bild.
  final Map<String, ErfasstesFoto> fotos;

  /// Das Foto, für das gerade die Kamera offen ist. Android darf die App
  /// schließen, solange die Kamera vorn ist — beim nächsten Start weiß die
  /// App damit noch, wozu das Bild gehört.
  ErfasstesFoto? fotoWartend;

  /// Wann das Ergebnis zuletzt als Datei gespeichert wurde — null: seit
  /// der letzten Änderung noch nicht.
  DateTime? gespeichertAm;

  /// Ob etwas erfasst ist.
  bool get hatErfasstes =>
      produktionen.isNotEmpty || werte.isNotEmpty || fotos.isNotEmpty;

  /// Ob es Erfasstes gibt, das noch in keiner Ergebnis-Datei steht.
  bool get ungesichert => hatErfasstes && gespeichertAm == null;

  /// Die geplanten Produktionen, die noch nicht erfasst sind.
  List<PaketProduktion> get offen => [
        for (final p in paket?.produktionen ?? const <PaketProduktion>[])
          if (!produktionen.containsKey(p.id)) p,
      ];

  /// Die frei erfassten Produktionen — ohne Plan im Paket.
  List<ErfassteProduktion> get frei {
    final geplant = {
      for (final p in paket?.produktionen ?? const <PaketProduktion>[]) p.id,
    };
    return [
      for (final e in produktionen.values)
        if (!geplant.contains(e.produktionId)) e,
    ];
  }

  /// Öffnet [neu]. Dasselbe Paket noch einmal ändert nichts; ein anderes
  /// verwirft, was erfasst ist — danach fragt die Oberfläche vorher.
  /// Gibt zurück, ob sich etwas geändert hat.
  bool paketOeffnen(ErfassungsPaket neu) {
    if (paket?.id == neu.id) return false;
    paket = neu;
    produktionen.clear();
    werte.clear();
    fotos.clear();
    fotoWartend = null;
    gespeichertAm = null;
    return true;
  }

  // ── Fotos ───────────────────────────────────────────────────────────

  /// Die Angaben eines neuen Fotos — noch ohne Bild. Mit [artikelId] ist
  /// es ein Foto aus der Produktion dieses Artikels, ohne ein Musterfoto.
  ErfasstesFoto fotoAnlegen({
    required String id,
    required DateTime jetzt,
    String? artikelId,
    String? artikel,
    String? produktionId,
    String? bezeichnung,
  }) =>
      ErfasstesFoto(
        id: id,
        art: artikelId == null ? FotoArt.muster : FotoArt.produktion,
        aufgenommenAm: jetzt,
        artikelId: artikelId,
        artikel: artikelId == null ? null : _leerZuNull(artikel),
        produktionId: artikelId == null ? null : produktionId,
        bezeichnung: _leerZuNull(bezeichnung),
        kuerzel: _leerZuNull(kuerzel),
      );

  /// Nimmt ein Foto auf, dessen Bild [groesse] Bytes hat.
  void fotoHinzu(ErfasstesFoto foto, {required int groesse}) {
    fotos[foto.id] = ErfasstesFoto(
      id: foto.id,
      art: foto.art,
      aufgenommenAm: foto.aufgenommenAm,
      artikelId: foto.artikelId,
      artikel: foto.artikel,
      produktionId: foto.produktionId,
      bezeichnung: foto.bezeichnung,
      kuerzel: foto.kuerzel,
      groesse: groesse,
    );
    gespeichertAm = null;
  }

  void fotoLoeschen(String id) {
    if (fotos.remove(id) != null) gespeichertAm = null;
  }

  /// Alle Fotos, das neueste zuerst.
  List<ErfasstesFoto> get fotoListe => fotos.values.toList()
    ..sort((a, b) => b.aufgenommenAm.compareTo(a.aufgenommenAm));

  /// Die Fotos zu einem Artikel, das neueste zuerst.
  List<ErfasstesFoto> fotosVon(String artikelId) => [
        for (final f in fotoListe)
          if (f.art == FotoArt.produktion && f.artikelId == artikelId) f,
      ];

  /// Die Musterfotos, das neueste zuerst.
  List<ErfasstesFoto> get musterfotos => [
        for (final f in fotoListe)
          if (f.art == FotoArt.muster) f,
      ];

  /// Wie viele Bytes die Bilder zusammen haben.
  int get fotoBytes => fotos.values.fold(0, (s, f) => s + f.groesse);

  /// Hält eine Produktion fest (oder ersetzt ihre Erfassung).
  void produktionErfassen(ErfassteProduktion e) {
    produktionen[e.produktionId] = e;
    gespeichertAm = null;
  }

  void produktionLoeschen(String produktionId) {
    if (produktionen.remove(produktionId) != null) gespeichertAm = null;
  }

  /// Der Wert, der für [feld] gerade gilt: der erfasste, sonst der aus
  /// dem Paket.
  String? wertVon(PaketSchritt schritt, PaketFeld feld) {
    final g = werte[wertSchluessel(schritt.id, feld.schluessel)];
    return g == null ? feld.wert : _leerZuNull(g.neu);
  }

  /// Ob [feld] gegenüber dem Paket geändert ist.
  bool istGeaendert(PaketSchritt schritt, PaketFeld feld) =>
      werte.containsKey(wertSchluessel(schritt.id, feld.schluessel));

  /// Wie viele Felder von [schritt] geändert sind.
  int geaendertIn(PaketSchritt schritt) =>
      schritt.felder.where((f) => istGeaendert(schritt, f)).length;

  /// Setzt [feld] auf [neu]. Steht dort wieder der Wert aus dem Paket,
  /// gilt es nicht mehr als geändert.
  void wertSetzen({
    required PaketArtikel artikel,
    required PaketSchritt schritt,
    required PaketFeld feld,
    required String? neu,
    required DateTime jetzt,
  }) {
    final schluessel = wertSchluessel(schritt.id, feld.schluessel);
    final wert = _leerZuNull(neu);
    if (wert == _leerZuNull(feld.wert)) {
      if (werte.remove(schluessel) != null) gespeichertAm = null;
      return;
    }
    werte[schluessel] = GeaenderterWert(
      artikelId: artikel.id,
      schrittId: schritt.id,
      schluessel: feld.schluessel,
      art: feld.art,
      name: feld.name,
      alt: _leerZuNull(feld.wert),
      neu: wert,
      kuerzel: _leerZuNull(kuerzel),
      erfasstAm: jetzt,
    );
    gespeichertAm = null;
  }

  /// Das Ergebnis für den Planer — null ohne Paket. Die Fotos gehen mit,
  /// soweit ihr Bild in [bilder] steht (ID → JPEG).
  ErfassungsErgebnis? ergebnis(
    DateTime jetzt, {
    Map<String, Uint8List> bilder = const {},
  }) {
    final p = paket;
    if (p == null) return null;
    final liste = produktionen.values.toList()
      ..sort((a, b) {
        final t = a.datum.compareTo(b.datum);
        return t != 0 ? t : a.artikel.compareTo(b.artikel);
      });
    return ErfassungsErgebnis(
      paketId: p.id,
      paketErstellt: p.erstellt,
      erstellt: jetzt,
      produktionen: liste,
      werte: werte.values.toList(),
      fotos: [
        for (final f in fotoListe.reversed)
          if (bilder[f.id] case final bild?) f.mit(bild),
      ],
    );
  }

  // ── Speichern ───────────────────────────────────────────────────────

  String alsText() => jsonEncode({
        'kuerzel': kuerzel,
        if (paket != null) 'paket': paket!.toJson(),
        'produktionen': [for (final e in produktionen.values) e.toJson()],
        'werte': [for (final w in werte.values) w.toJson()],
        if (fotos.isNotEmpty)
          'fotos': [for (final f in fotos.values) f.toJson()],
        if (fotoWartend != null) 'fotoWartend': fotoWartend!.toJson(),
        if (gespeichertAm != null)
          'gespeichertAm': gespeichertAm!.toIso8601String(),
      });

  /// Liest den gespeicherten Stand — lässt er sich nicht lesen, beginnt
  /// die App leer, statt nicht zu starten.
  static Erfassungsstand ausText(String? text) {
    if (text == null || text.trim().isEmpty) return Erfassungsstand();
    try {
      final j = jsonDecode(text);
      if (j is! JsonObjekt) return Erfassungsstand();
      final paket = jsonObjektOder(j, 'paket');
      final gespeichert = jsonTextOder(j, 'gespeichertAm');
      final produktionen = [
        for (final e in jsonListe(j, 'produktionen', 'dem Stand'))
          ErfassteProduktion.ausJson(e),
      ];
      final werte = [
        for (final w in jsonListe(j, 'werte', 'dem Stand'))
          GeaenderterWert.ausJson(w),
      ];
      final fotos = [
        for (final f in jsonListe(j, 'fotos', 'dem Stand'))
          ErfasstesFoto.ausJson(f),
      ];
      final wartend = jsonObjektOder(j, 'fotoWartend');
      return Erfassungsstand(
        paket: paket == null ? null : ErfassungsPaket.ausJson(paket),
        kuerzel: jsonTextOder(j, 'kuerzel') ?? '',
        produktionen: {for (final e in produktionen) e.produktionId: e},
        werte: {
          for (final w in werte) wertSchluessel(w.schrittId, w.schluessel): w,
        },
        fotos: {for (final f in fotos) f.id: f},
        fotoWartend: wartend == null ? null : ErfasstesFoto.ausJson(wartend),
        gespeichertAm:
            gespeichert == null ? null : DateTime.tryParse(gespeichert),
      );
    } on FormatException {
      return Erfassungsstand();
    } on FormatFehler {
      return Erfassungsstand();
    }
  }
}
