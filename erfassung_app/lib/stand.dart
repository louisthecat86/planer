import 'dart:convert';

import 'package:erfassung_format/erfassung_format.dart';

// Der Stand der Erfassung auf dem Handy: das geöffnete Paket, die
// erfassten Produktionen, die geänderten Maschineneinstellungen und das
// Kürzel. Ohne Flutter — die Oberfläche hängt über [ErfassungsModell]
// (modell.dart) daran, gespeichert wird als eine JSON-Datei im Ordner der
// App.

/// Der Schlüssel eines geänderten Werts: Schritt und Feld.
String wertSchluessel(String schrittId, String feld) => '$schrittId|$feld';

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
    this.gespeichertAm,
  })  : produktionen = produktionen ?? {},
        werte = werte ?? {};

  /// Das geöffnete Paket — null: noch keins.
  ErfassungsPaket? paket;

  /// Wer erfasst.
  String kuerzel;

  /// Die erfassten Produktionen nach ihrer ID im Paket (frei erfasste:
  /// eine eigene).
  final Map<String, ErfassteProduktion> produktionen;

  /// Die geänderten Werte nach [wertSchluessel].
  final Map<String, GeaenderterWert> werte;

  /// Wann das Ergebnis zuletzt als Datei gespeichert wurde — null: seit
  /// der letzten Änderung noch nicht.
  DateTime? gespeichertAm;

  /// Ob etwas erfasst ist.
  bool get hatErfasstes => produktionen.isNotEmpty || werte.isNotEmpty;

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
    gespeichertAm = null;
    return true;
  }

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

  /// Das Ergebnis für den Planer — null ohne Paket.
  ErfassungsErgebnis? ergebnis(DateTime jetzt) {
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
    );
  }

  // ── Speichern ───────────────────────────────────────────────────────

  String alsText() => jsonEncode({
        'kuerzel': kuerzel,
        if (paket != null) 'paket': paket!.toJson(),
        'produktionen': [for (final e in produktionen.values) e.toJson()],
        'werte': [for (final w in werte.values) w.toJson()],
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
      return Erfassungsstand(
        paket: paket == null ? null : ErfassungsPaket.ausJson(paket),
        kuerzel: jsonTextOder(j, 'kuerzel') ?? '',
        produktionen: {for (final e in produktionen) e.produktionId: e},
        werte: {
          for (final w in werte) wertSchluessel(w.schrittId, w.schluessel): w,
        },
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
