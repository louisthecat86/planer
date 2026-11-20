import 'dart:convert';
import 'dart:typed_data';

import 'package:erfassung_format/erfassung_format.dart';

// Der Stand der Erfassung auf dem Handy: das geöffnete Paket, die
// erfassten Produktionen, die geänderten Maschineneinstellungen, die
// Maschinen, die in einer Prozesskette dazukamen oder wegfallen, die Fotos
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

/// Eine ID für einen neuen Schritt — wie [neueFotoId], damit sie auch
/// über mehrere Handys eindeutig ist. Der Planer legt den Schritt unter
/// genau dieser ID an.
String neueSchrittId(DateTime jetzt, int zufall) =>
    'h-${jetzt.microsecondsSinceEpoch.toRadixString(36)}-'
    '${zufall.toRadixString(36)}';

/// Ein Schritt, wie er auf dem Handy in der Kette eines Artikels steht.
typedef KettenSchritt = ({
  PaketSchritt schritt,

  /// Auf dem Handy dazugekommen.
  bool neu,

  /// Auf dem Handy herausgenommen — er steht noch da, damit er sich
  /// zurückholen lässt.
  bool entfernt,
});

/// Wohin eine neue Maschine kommt, wenn niemand etwas anderes wählt: hinter
/// den letzten Schritt ihrer Abteilung — gibt es keinen, ans Ende. Die ID
/// des Schritts davor, null: ganz vorn (nur in einer leeren Kette).
String? platzVorschlag(List<PaketSchritt> schritte, String abteilung) {
  for (final s in schritte.reversed) {
    if (s.abteilung == abteilung) return s.id;
  }
  return schritte.isEmpty ? null : schritte.last.id;
}

/// Wie weit eine Produktion ist.
enum ProduktionsStatus {
  /// Noch nicht gestartet — vielleicht schon etwas eingetragen.
  offen,

  /// Gestartet: Eine Startzeit ist eingetragen, erfasst ist sie noch nicht.
  laeuft,

  /// Erfasst.
  erfasst,
}

/// Eine Produktion auf der Seite „Heute": geplant ([plan]), begonnen
/// ([entwurf]) oder erfasst ([erfasst]) — oder mehreres davon.
class HeuteEintrag {
  const HeuteEintrag({
    required this.id,
    required this.status,
    this.plan,
    this.entwurf,
    this.erfasst,
  });

  final String id;
  final ProduktionsStatus status;
  final PaketProduktion? plan;
  final ProduktionsEntwurf? entwurf;
  final ErfassteProduktion? erfasst;

  String get artikelId =>
      plan?.artikelId ?? entwurf?.artikelId ?? erfasst?.artikelId ?? '';

  String get artikel =>
      plan?.artikel ?? entwurf?.artikel ?? erfasst?.artikel ?? '';

  /// Die Rohware, die zählt: erfasst, sonst eingetragen, sonst geplant.
  double? get rohKg =>
      erfasst?.rohKg ?? rechneAus(entwurf?.roh ?? '') ?? plan?.rohKg;

  /// Die eingetragene Startzeit („06:10") — null ohne.
  String? get start => zeitAus(erfasst?.start ?? entwurf?.start);

  /// Der Tag: erfasst, begonnen, sonst geplant.
  DateTime get datum =>
      erfasst?.datum ?? entwurf?.datum ?? plan?.datum ?? DateTime(2000);

  /// Ob schon etwas eingetragen ist, ohne dass sie läuft.
  bool get begonnen => status == ProduktionsStatus.offen && entwurf != null;
}

/// Die Produktionen fürs Handy sortiert: was läuft, was bis heute offen
/// ist, was erfasst ist — und was morgen und später geplant ist.
typedef HeuteUebersicht = ({
  List<HeuteEintrag> laeuft,
  List<HeuteEintrag> offen,
  List<HeuteEintrag> erfasst,
  List<HeuteEintrag> morgen,
  List<HeuteEintrag> spaeter,
});

/// Was die Erfahrung über die Dauer einer Produktion sagt: [minuten] und
/// [ende] nur, wenn sie sich ermitteln lassen; [text] sagt es in Worten —
/// auch, warum nicht.
typedef Prognose = ({double? minuten, String? ende, String text});

/// „3:40 h".
String _dauer(double minuten) {
  final m = minuten.round();
  return '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')} h';
}

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
    this.endeVpk = '',
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

  /// Ende des Auflegens.
  final String ende;

  /// Ende an der Verpackung.
  final String endeVpk;
  final String bemerkung;

  /// Ob gar nichts eingetragen ist — so ein Entwurf wird nicht gemerkt.
  bool get leer => [roh, fleisch, fertig, start, ende, endeVpk, bemerkung]
      .every((t) => t.trim().isEmpty);

  /// Ob [anderer] dieselben Eingaben trägt — der Zeitpunkt zählt nicht.
  bool gleicheEingaben(ProduktionsEntwurf anderer) =>
      datum == anderer.datum &&
      roh == anderer.roh &&
      fleisch == anderer.fleisch &&
      fertig == anderer.fertig &&
      start == anderer.start &&
      ende == anderer.ende &&
      endeVpk == anderer.endeVpk &&
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
        if (endeVpk.isNotEmpty) 'endeVpk': endeVpk,
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
      endeVpk: jsonTextOder(j, 'endeVpk') ?? '',
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
    Map<String, NeuerSchritt>? neueSchritte,
    Map<String, EntfernterSchritt>? entfernteSchritte,
    List<String>? zuletzt,
    this.fotoWartend,
    this.gespeichertAm,
  })  : zuletzt = zuletzt ?? [],
        produktionen = produktionen ?? {},
        entwuerfe = entwuerfe ?? {},
        werte = werte ?? {},
        fotos = fotos ?? {},
        neueSchritte = neueSchritte ?? {},
        entfernteSchritte = entfernteSchritte ?? {};

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

  /// Maschinen, die in eine Kette dazugekommen sind, nach der ID ihres
  /// Schritts — in der Reihenfolge, in der sie dazukamen.
  final Map<String, NeuerSchritt> neueSchritte;

  /// Schritte aus dem Paket, die aus ihrer Kette fallen, nach ihrer ID.
  final Map<String, EntfernterSchritt> entfernteSchritte;

  /// Die zuletzt geöffneten Artikel, der jüngste zuerst — höchstens
  /// [kZuletztMax].
  final List<String> zuletzt;

  static const int kZuletztMax = 8;

  /// Das Foto, für das gerade die Kamera offen ist. Android darf die App
  /// schließen, solange die Kamera vorn ist — beim nächsten Start weiß die
  /// App damit noch, wozu das Bild gehört.
  ErfasstesFoto? fotoWartend;

  /// Wann das Ergebnis zuletzt als Datei gespeichert wurde — null: seit
  /// der letzten Änderung noch nicht.
  DateTime? gespeichertAm;

  /// Ob etwas erfasst ist.
  bool get hatErfasstes =>
      produktionen.isNotEmpty ||
      werte.isNotEmpty ||
      fotos.isNotEmpty ||
      neueSchritte.isNotEmpty ||
      entfernteSchritte.isNotEmpty;

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
    neueSchritte.clear();
    entfernteSchritte.clear();
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
      // Damit der Planer den Schritt auch findet, wenn die Kette am PC
      // neu angelegt wurde.
      anlage: schritt.anlage,
      nummer: schritt.nummer > 0 ? schritt.nummer : null,
      erfasstAm: jetzt,
    );
    gespeichertAm = null;
  }

  // ── Heute ───────────────────────────────────────────────────────────

  /// Wie weit die Produktion [produktionId] ist.
  ProduktionsStatus statusVon(String produktionId) {
    if (produktionen.containsKey(produktionId)) {
      return ProduktionsStatus.erfasst;
    }
    final e = entwuerfe[produktionId];
    return e != null && zeitAus(e.start) != null
        ? ProduktionsStatus.laeuft
        : ProduktionsStatus.offen;
  }

  /// Alle Produktionen nach [ProduktionsStatus] und Tag, bezogen auf
  /// [jetzt]: Was läuft, steht oben, egal für welchen Tag es geplant war.
  /// Offen heißt: geplant bis heute — auch Liegengebliebenes von gestern.
  HeuteUebersicht uebersicht(DateTime jetzt) {
    final heute = DateTime(jetzt.year, jetzt.month, jetzt.day);
    final morgen = DateTime(heute.year, heute.month, heute.day + 1);
    final laeuft = <HeuteEintrag>[];
    final offen = <HeuteEintrag>[];
    final erfasst = <HeuteEintrag>[];
    final spaeterMorgen = <HeuteEintrag>[];
    final spaeter = <HeuteEintrag>[];
    void einordnen(HeuteEintrag e) {
      switch (e.status) {
        case ProduktionsStatus.laeuft:
          laeuft.add(e);
        case ProduktionsStatus.erfasst:
          erfasst.add(e);
        case ProduktionsStatus.offen:
          final tag = DateTime(e.datum.year, e.datum.month, e.datum.day);
          if (!tag.isAfter(heute)) {
            offen.add(e);
          } else if (tag == morgen) {
            spaeterMorgen.add(e);
          } else {
            spaeter.add(e);
          }
      }
    }

    final geplant = <String>{};
    for (final p in paket?.produktionen ?? const <PaketProduktion>[]) {
      geplant.add(p.id);
      einordnen(
        HeuteEintrag(
          id: p.id,
          status: statusVon(p.id),
          plan: p,
          entwurf: entwuerfe[p.id],
          erfasst: produktionen[p.id],
        ),
      );
    }
    // Ohne Plan: begonnen oder erfasst.
    final frei = <String>{
      ...entwuerfe.keys,
      ...produktionen.keys,
    }.where((id) => !geplant.contains(id));
    for (final id in frei) {
      einordnen(
        HeuteEintrag(
          id: id,
          status: statusVon(id),
          entwurf: entwuerfe[id],
          erfasst: produktionen[id],
        ),
      );
    }
    int nachStart(HeuteEintrag a, HeuteEintrag b) =>
        (a.start ?? '').compareTo(b.start ?? '');
    int nachTag(HeuteEintrag a, HeuteEintrag b) {
      final t = a.datum.compareTo(b.datum);
      if (t != 0) return t;
      return (a.plan?.start ?? '99').compareTo(b.plan?.start ?? '99');
    }

    laeuft.sort(nachStart);
    offen.sort(nachTag);
    spaeterMorgen.sort(nachTag);
    spaeter.sort(nachTag);
    erfasst.sort(
      (a, b) => b.erfasst!.erfasstAm.compareTo(a.erfasst!.erfasstAm),
    );
    return (
      laeuft: laeuft,
      offen: offen,
      erfasst: erfasst,
      morgen: spaeterMorgen,
      spaeter: spaeter,
    );
  }

  /// Startet die Produktion [produktionId] jetzt: Die Uhrzeit von [jetzt]
  /// wird als Start festgehalten — als begonnene Erfassung, wie beim
  /// Zwischenspeichern. Was schon eingetragen war, bleibt; eine schon
  /// eingetragene Startzeit auch. Gibt zurück, ob sich etwas geändert hat.
  bool produktionStarten({
    required String produktionId,
    required String artikelId,
    required String artikel,
    required DateTime jetzt,
  }) {
    if (produktionen.containsKey(produktionId)) return false;
    final alt = entwuerfe[produktionId];
    if (alt != null && zeitAus(alt.start) != null) return false;
    entwuerfe[produktionId] = ProduktionsEntwurf(
      produktionId: produktionId,
      artikelId: alt?.artikelId ?? artikelId,
      artikel: alt?.artikel ?? artikel,
      // Der Tag, an dem wirklich produziert wird.
      datum: DateTime(jetzt.year, jetzt.month, jetzt.day),
      geaendertAm: jetzt,
      roh: alt?.roh ?? '',
      fleisch: alt?.fleisch ?? '',
      fertig: alt?.fertig ?? '',
      start: uhrzeit(jetzt),
      ende: alt?.ende ?? '',
      endeVpk: alt?.endeVpk ?? '',
      bemerkung: alt?.bemerkung ?? '',
    );
    return true;
  }

  /// Wie lange eine Produktion von [artikelId] mit [kg] Rohware nach den
  /// bisherigen Produktionen dauert — und, mit [start], wann sie fertig
  /// ist. Ohne erfasste Produktionen des Artikels oder ohne Menge sagt der
  /// Text, warum sich keine Dauer ermitteln lässt.
  Prognose prognose({
    required String artikelId,
    required double? kg,
    String? start,
  }) {
    final e = paket?.erfahrungFuer(artikelId);
    if (e == null || e.mengeKg <= 0 || e.minuten <= 0) {
      return (
        minuten: null,
        ende: null,
        text: 'Keine Dauer ermittelbar — für diesen Artikel ist noch keine '
            'Produktion mit Menge und Zeit erfasst.',
      );
    }
    final herkunft = e.anzahl == 1
        ? 'der letzten Produktion'
        : 'den letzten ${e.anzahl} Produktionen';
    final leistung = 'Ø ${zahlText(e.kgProStunde, nachkomma: 0)} kg/h aus '
        '$herkunft';
    if (kg == null || !kg.isFinite || kg <= 0) {
      return (
        minuten: null,
        ende: null,
        text: 'Keine Dauer ermittelbar — es ist keine Rohware geplant oder '
            'eingetragen. Bisher $leistung.',
      );
    }
    final minuten = e.minutenFuer(kg);
    String? ende;
    final ab = zeitAus(start);
    if (ab != null) {
      final teile = ab.split(':');
      final summe =
          int.parse(teile[0]) * 60 + int.parse(teile[1]) + minuten.round();
      final m = summe % (24 * 60);
      ende = '${(m ~/ 60).toString().padLeft(2, '0')}:'
          '${(m % 60).toString().padLeft(2, '0')}';
    }
    return (
      minuten: minuten,
      ende: ende,
      text: 'Voraussichtlich ${_dauer(minuten)} für ${zahlText(kg)} kg '
          'Rohware${ende == null ? '' : ' — fertig gegen $ende'}. '
          'Erfahrung: $leistung.',
    );
  }

  /// Merkt [artikelId] als zuletzt geöffnet. Gibt zurück, ob sich etwas
  /// geändert hat.
  bool artikelGeoeffnet(String artikelId) {
    if (zuletzt.isNotEmpty && zuletzt.first == artikelId) return false;
    zuletzt
      ..remove(artikelId)
      ..insert(0, artikelId);
    if (zuletzt.length > kZuletztMax) {
      zuletzt.removeRange(kZuletztMax, zuletzt.length);
    }
    return true;
  }

  /// Wie viele Posten das Ergebnis hätte: Produktionen, geänderte Werte,
  /// Änderungen an Ketten und Fotos.
  int get postenAnzahl =>
      produktionen.length +
      werte.length +
      neueSchritte.length +
      entfernteSchritte.length +
      fotos.length;

  // ── Prozessketten ───────────────────────────────────────────────────

  /// Die Kette von [artikel], wie sie auf dem Handy steht: die Schritte
  /// aus dem Paket, die neuen an ihrem Platz, die herausgenommenen noch
  /// mit dabei. Gezählt werden nur die Schritte, die bleiben — ein
  /// herausgenommener hat die Nummer 0.
  List<KettenSchritt> ketteVon(PaketArtikel artikel) {
    final p = paket;
    final ids = [for (final s in artikel.schritte) s.id];
    final neu = <String, PaketSchritt>{};
    for (final n in neueSchritte.values) {
      if (n.artikelId != artikel.id) continue;
      final m = p?.maschineMit(n.maschineId);
      neu[n.id] = PaketSchritt(
        id: n.id,
        nummer: 0,
        abteilung: n.abteilung,
        abteilungName: m?.abteilungName ?? n.abteilung,
        abteilungFarbe: m?.abteilungFarbe,
        anlage: m?.name ?? n.maschine,
        felder: m?.felder ?? const [],
      );
      final nach = n.nachSchrittId;
      final i = nach == null ? -1 : ids.indexOf(nach);
      if (nach != null && i < 0) {
        ids.add(n.id);
      } else {
        ids.insert(i + 1, n.id);
      }
    }
    final ausPaket = {for (final s in artikel.schritte) s.id: s};
    var nummer = 0;
    return [
      for (final id in ids)
        () {
          final s = ausPaket[id] ?? neu[id]!;
          final weg = entfernteSchritte.containsKey(id);
          if (!weg) nummer++;
          return (
            schritt: PaketSchritt(
              id: s.id,
              nummer: weg ? 0 : nummer,
              abteilung: s.abteilung,
              abteilungName: s.abteilungName,
              abteilungFarbe: s.abteilungFarbe,
              anlage: s.anlage,
              prozessschritt: s.prozessschritt,
              felder: s.felder,
            ),
            neu: neu.containsKey(id),
            entfernt: weg,
          );
        }(),
    ];
  }

  /// Wie viele Maschinen in der Kette von [artikelId] dazukamen oder
  /// wegfallen.
  int kettenAenderungenIn(String artikelId) =>
      neueSchritte.values.where((n) => n.artikelId == artikelId).length +
      entfernteSchritte.values.where((e) => e.artikelId == artikelId).length;

  /// Holt [maschine] in die Kette von [artikel] — hinter [nachSchrittId],
  /// ohne ganz nach vorn.
  void maschineHinzu({
    required String id,
    required PaketArtikel artikel,
    required PaketMaschine maschine,
    required String? nachSchrittId,
    required DateTime jetzt,
  }) {
    neueSchritte[id] = NeuerSchritt(
      id: id,
      artikelId: artikel.id,
      maschineId: maschine.id,
      maschine: maschine.name,
      abteilung: maschine.abteilung,
      nachSchrittId: nachSchrittId,
      kuerzel: _leerZuNull(kuerzel),
      erfasstAm: jetzt,
    );
    gespeichertAm = null;
  }

  /// Nimmt [schritt] aus der Kette von [artikel]. Ein Schritt aus dem
  /// Paket bleibt sichtbar und lässt sich mit [schrittBehalten]
  /// zurückholen, samt seiner Werte. Ein neuer verschwindet ganz — mit
  /// dem, was an ihm eingetragen war; wer hinter ihm stand, rückt an
  /// seinen Platz.
  void schrittEntfernen({
    required PaketArtikel artikel,
    required PaketSchritt schritt,
    required DateTime jetzt,
  }) {
    final neu = neueSchritte.remove(schritt.id);
    if (neu != null) {
      for (final MapEntry(:key, :value) in neueSchritte.entries.toList()) {
        if (value.nachSchrittId != schritt.id) continue;
        neueSchritte[key] = NeuerSchritt(
          id: value.id,
          artikelId: value.artikelId,
          maschineId: value.maschineId,
          maschine: value.maschine,
          abteilung: value.abteilung,
          nachSchrittId: neu.nachSchrittId,
          kuerzel: value.kuerzel,
          erfasstAm: value.erfasstAm,
        );
      }
      werte.removeWhere((_, w) => w.schrittId == schritt.id);
    } else {
      entfernteSchritte[schritt.id] = EntfernterSchritt(
        artikelId: artikel.id,
        schrittId: schritt.id,
        anlage: schritt.anlage,
        kuerzel: _leerZuNull(kuerzel),
        erfasstAm: jetzt,
      );
    }
    gespeichertAm = null;
  }

  /// Holt einen herausgenommenen Schritt aus dem Paket zurück.
  bool schrittBehalten(String schrittId) {
    if (entfernteSchritte.remove(schrittId) == null) return false;
    gespeichertAm = null;
    return true;
  }

  /// Die neuen Schritte fürs Ergebnis: je Artikel in der Reihenfolge der
  /// Kette, und jeder hinter dem nächsten Schritt davor, der bleibt.
  List<NeuerSchritt> _neueFuersErgebnis() {
    final p = paket;
    if (p == null || neueSchritte.isEmpty) return const [];
    final artikelIds = <String>{
      for (final n in neueSchritte.values) n.artikelId,
    };
    final liste = <NeuerSchritt>[];
    for (final artikelId in artikelIds) {
      final artikel = p.artikelMit(artikelId) ??
          PaketArtikel(id: artikelId, nummer: '', name: '');
      String? davor;
      for (final k in ketteVon(artikel)) {
        if (k.entfernt) continue;
        final n = neueSchritte[k.schritt.id];
        if (n != null) {
          liste.add(
            NeuerSchritt(
              id: n.id,
              artikelId: n.artikelId,
              maschineId: n.maschineId,
              maschine: n.maschine,
              abteilung: n.abteilung,
              nachSchrittId: davor,
              kuerzel: n.kuerzel,
              erfasstAm: n.erfasstAm,
            ),
          );
        }
        davor = k.schritt.id;
      }
    }
    return liste;
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
      // Werte an einem herausgenommenen Schritt gehen nicht mit — sie
      // bleiben aber auf dem Handy, falls er zurückgeholt wird.
      werte: [
        for (final w in werte.values)
          if (!entfernteSchritte.containsKey(w.schrittId)) w,
      ],
      neueSchritte: _neueFuersErgebnis(),
      entfernteSchritte: entfernteSchritte.values.toList(),
      fotos: [
        for (final f in fotoListe.reversed)
          if (bilder[f.id] case final bild?) f.mit(bild),
      ],
    );
  }

  // ── Speichern ───────────────────────────────────────────────────────

  String alsText() => jsonEncode({
        'kuerzel': kuerzel,
        if (zuletzt.isNotEmpty) 'zuletzt': zuletzt,
        if (paket != null) 'paket': paket!.toJson(),
        'produktionen': [for (final e in produktionen.values) e.toJson()],
        if (entwuerfe.isNotEmpty)
          'entwuerfe': [for (final e in entwuerfe.values) e.toJson()],
        'werte': [for (final w in werte.values) w.toJson()],
        if (fotos.isNotEmpty)
          'fotos': [for (final f in fotos.values) f.toJson()],
        if (neueSchritte.isNotEmpty)
          'neueSchritte': [for (final n in neueSchritte.values) n.toJson()],
        if (entfernteSchritte.isNotEmpty)
          'entfernteSchritte': [
            for (final e in entfernteSchritte.values) e.toJson(),
          ],
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
      // Fehlen in älteren Ständen — dann gibt es keine.
      final neueSchritte = [
        for (final n in jsonListe(j, 'neueSchritte', 'dem Stand'))
          NeuerSchritt.ausJson(n),
      ];
      final entfernteSchritte = [
        for (final e in jsonListe(j, 'entfernteSchritte', 'dem Stand'))
          EntfernterSchritt.ausJson(e),
      ];
      final wartend = jsonObjektOder(j, 'fotoWartend');
      final zuletzt = j['zuletzt'];
      return Erfassungsstand(
        paket: paket == null ? null : ErfassungsPaket.ausJson(paket),
        kuerzel: jsonTextOder(j, 'kuerzel') ?? '',
        zuletzt: zuletzt is List ? [...zuletzt.whereType<String>()] : null,
        produktionen: {for (final e in produktionen) e.produktionId: e},
        entwuerfe: {for (final e in entwuerfe) e.produktionId: e},
        werte: {
          for (final w in werte) wertSchluessel(w.schrittId, w.schluessel): w,
        },
        fotos: {for (final f in fotos) f.id: f},
        neueSchritte: {for (final n in neueSchritte) n.id: n},
        entfernteSchritte: {
          for (final e in entfernteSchritte) e.schrittId: e,
        },
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
