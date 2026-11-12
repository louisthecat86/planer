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

/// Eine begonnene Erfassung: was zu einer Produktion schon eingetragen
/// ist, ohne dass sie erfasst wäre — etwa Rohware und Startzeit, während
/// die Produktion noch läuft.
///
/// Die Felder stehen so da, wie sie getippt wurden: Ein Entwurf darf
/// unvollständig und sogar falsch sein, geprüft wird erst beim Erfassen.
/// Ins Ergebnis für den Planer geht er nicht.
class ProduktionsEntwurf {
  const ProduktionsEntwurf({
    required this.produktionId,
    required this.artikelId,
    required this.artikel,
    required this.datum,
    required this.geaendertAm,
    this.roh = '',
    this.fleisch = '',
    this.fertig = '',
    this.start = '',
    this.ende = '',
    this.bemerkung = '',
  });

  /// Die ID der Produktion im Paket — ohne Plan eine eigene („frei-…").
  final String produktionId;
  final String artikelId;
  final String artikel;
  final DateTime datum;

  /// Wann zuletzt zwischengespeichert wurde.
  final DateTime geaendertAm;

  final String roh;
  final String fleisch;
  final String fertig;
  final String start;
  final String ende;
  final String bemerkung;

  /// Ob gar nichts eingetragen ist — so ein Entwurf wird nicht gemerkt.
  bool get leer => [roh, fleisch, fertig, start, ende, bemerkung]
      .every((t) => t.trim().isEmpty);

  /// Ob [anderer] dieselben Eingaben trägt — der Zeitpunkt zählt nicht.
  bool gleicheEingaben(ProduktionsEntwurf anderer) =>
      datum == anderer.datum &&
      roh == anderer.roh &&
      fleisch == anderer.fleisch &&
      fertig == anderer.fertig &&
      start == anderer.start &&
      ende == anderer.ende &&
      bemerkung == anderer.bemerkung;

  JsonObjekt toJson() => {
        'produktionId': produktionId,
        'artikelId': artikelId,
        'artikel': artikel,
        'datum': datum.toIso8601String(),
        'geaendertAm': geaendertAm.toIso8601String(),
        if (roh.isNotEmpty) 'roh': roh,
        if (fleisch.isNotEmpty) 'fleisch': fleisch,
        if (fertig.isNotEmpty) 'fertig': fertig,
        if (start.isNotEmpty) 'start': start,
        if (ende.isNotEmpty) 'ende': ende,
        if (bemerkung.isNotEmpty) 'bemerkung': bemerkung,
      };

  /// Liest einen Entwurf — null, wenn ihm ID oder Tag fehlen.
  static ProduktionsEntwurf? ausJson(JsonObjekt j) {
    final id = jsonTextOder(j, 'produktionId');
    final datum = DateTime.tryParse(jsonTextOder(j, 'datum') ?? '');
    if (id == null || id.isEmpty || datum == null) return null;
    return ProduktionsEntwurf(
      produktionId: id,
      artikelId: jsonTextOder(j, 'artikelId') ?? '',
      artikel: jsonTextOder(j, 'artikel') ?? '',
      datum: datum,
      geaendertAm:
          DateTime.tryParse(jsonTextOder(j, 'geaendertAm') ?? '') ?? datum,
      roh: jsonTextOder(j, 'roh') ?? '',
      fleisch: jsonTextOder(j, 'fleisch') ?? '',
      fertig: jsonTextOder(j, 'fertig') ?? '',
      start: jsonTextOder(j, 'start') ?? '',
      ende: jsonTextOder(j, 'ende') ?? '',
      bemerkung: jsonTextOder(j, 'bemerkung') ?? '',
    );
  }
}

class Erfassungsstand {
  Erfassungsstand({
    this.paket,
    this.kuerzel = '',
    Map<String, ErfassteProduktion>? produktionen,
    Map<String, ProduktionsEntwurf>? entwuerfe,
    Map<String, GeaenderterWert>? werte,
    Map<String, ErfasstesFoto>? fotos,
    this.fotoWartend,
    this.gespeichertAm,
  })  : produktionen = produktionen ?? {},
        entwuerfe = entwuerfe ?? {},
        werte = werte ?? {},
        fotos = fotos ?? {};

  /// Das geöffnete Paket — null: noch keins.
  ErfassungsPaket? paket;

  /// Wer erfasst.
  String kuerzel;

  /// Die erfassten Produktionen nach ihrer ID im Paket (frei erfasste:
  /// eine eigene).
  final Map<String, ErfassteProduktion> produktionen;

  /// Die begonnenen Erfassungen nach derselben ID — zwischengespeichert,
  /// aber noch nicht erfasst. Sie stehen in keinem Ergebnis.
  final Map<String, ProduktionsEntwurf> entwuerfe;

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

  /// Die begonnenen Erfassungen ohne Plan im Paket, die neueste zuerst.
  List<ProduktionsEntwurf> get freiBegonnen {
    final geplant = {
      for (final p in paket?.produktionen ?? const <PaketProduktion>[]) p.id,
    };
    return [
      for (final e in entwuerfe.values)
        if (!geplant.contains(e.produktionId)) e,
    ]..sort((a, b) => b.geaendertAm.compareTo(a.geaendertAm));
  }

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
    entwuerfe.clear();
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

  /// Hält eine Produktion fest (oder ersetzt ihre Erfassung). Was zu ihr
  /// zwischengespeichert war, ist damit erledigt.
  void produktionErfassen(ErfassteProduktion e) {
    produktionen[e.produktionId] = e;
    entwuerfe.remove(e.produktionId);
    gespeichertAm = null;
  }

  /// Merkt eine begonnene Erfassung — ein leerer Entwurf entfernt sie.
  /// Am Ergebnis ändert das nichts: [gespeichertAm] bleibt. Gibt zurück,
  /// ob sich etwas geändert hat.
  bool entwurfMerken(ProduktionsEntwurf e) {
    if (e.leer) return entwuerfe.remove(e.produktionId) != null;
    final alt = entwuerfe[e.produktionId];
    if (alt != null && alt.gleicheEingaben(e)) return false;
    entwuerfe[e.produktionId] = e;
    return true;
  }

  bool entwurfLoeschen(String produktionId) =>
      entwuerfe.remove(produktionId) != null;

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
        if (entwuerfe.isNotEmpty)
          'entwuerfe': [for (final e in entwuerfe.values) e.toJson()],
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
      // Fehlt in älteren Ständen — dann gibt es keine.
      final entwuerfe = [
        for (final e in jsonListe(j, 'entwuerfe', 'dem Stand'))
          if (ProduktionsEntwurf.ausJson(e) case final entwurf?) entwurf,
      ];
      final wartend = jsonObjektOder(j, 'fotoWartend');
      return Erfassungsstand(
        paket: paket == null ? null : ErfassungsPaket.ausJson(paket),
        kuerzel: jsonTextOder(j, 'kuerzel') ?? '',
        produktionen: {for (final e in produktionen) e.produktionId: e},
        entwuerfe: {for (final e in entwuerfe) e.produktionId: e},
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
