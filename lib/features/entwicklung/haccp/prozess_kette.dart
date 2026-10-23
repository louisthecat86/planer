import '../../../core/constants/abteilungen.dart';
import '../../../core/constants/parameter_namen.dart';
import 'prozess_modell.dart';

// Die Prozesskette eines Projekts, rein rechnerisch: Stationen, Umbauen
// durch Ziehen, die Werte eines Schritts, das Umsetzen der früheren
// Abschnitte (F34) und der Vergleich zweier Stände.
//
// Die Regeln sind die der Kette im Artikel (articles/prozesskette_umbau.dart)
// — nur hält das Projekt seine Kette selbst (F32), ohne Personen und
// Leistungsdaten (F33). In den Artikel kommt sie mit der Freigabe.

/// Höchstens so viele Schritte — so viele hat auch ein Artikel
/// (ProzesskettenService.maxSchritte, die Spalten der Excel-Vorlage).
const int kProzessMaxSchritte = 20;

/// Die Parametergruppe eigener Werte — wie im Artikel.
const String kEigeneWerteGruppe = 'CUSTOM';

// ── Katalog ────────────────────────────────────────────────────────────

/// Ein Feld im Steckbrief einer Anlage.
class SteckbriefFeld {
  const SteckbriefFeld(this.name, {this.einheit = ''});

  final String name;
  final String einheit;

  /// „Bandgeschwindigkeit (m/min)".
  String get label => einheit.trim().isEmpty ? name : '$name ($einheit)';
}

/// Eine Anlage aus dem Katalog der Planung — was die Kette von ihr
/// braucht.
class KatalogAnlage {
  const KatalogAnlage({
    required this.id,
    required this.name,
    required this.abteilung,
    this.steckbrief = const [],
  });

  final String id;
  final String name;

  /// Ihre Stammabteilung (der gespeicherte Wert).
  final String abteilung;

  /// Die Felder ihres Steckbriefs — ohne die Platten, die das Schema
  /// verwaltet.
  final List<SteckbriefFeld> steckbrief;
}

/// Zeilen, die nicht zum Steckbrief gehören: der Marker des Plattenrasters,
/// die Maschineneinstellungen (eigenes Feld) und die Platten (eigenes
/// Schema) — dieselbe Regel wie istVerstecktesPlattenParam im Artikel.
bool istVersteckterParameter(String name) =>
    name == kPlattenSchemaParam ||
    name == kMaschinenNotizParam ||
    kPlattenParamMuster.hasMatch(name);

/// Die Abteilung zu einem gespeicherten Wert — null, wenn leer oder
/// unbekannt.
Abteilung? abteilungAus(String wert) {
  for (final a in Abteilung.values) {
    if (a.dbValue == wert) return a;
  }
  return null;
}

/// „Zerlegung" — „Ohne Abteilung", wenn keine gewählt ist.
String abteilungsName(String wert) {
  if (wert.trim().isEmpty) return 'Ohne Abteilung';
  return abteilungAus(wert)?.anzeigeName ?? wert;
}

String _norm(String text) => text.trim().toLowerCase();

// ── Grenzen der Werte ──────────────────────────────────────────────────

/// Plausibilitätsgrenzen eines Werts — wie in der Planung (Einstellungen →
/// Parametergrenzen): außerhalb der harten ist ein Wert unmöglich, außerhalb
/// der weichen ungewöhnlich.
class ParameterGrenze {
  const ParameterGrenze({
    this.hartMin,
    this.hartMax,
    this.weichMin,
    this.weichMax,
  });

  final double? hartMin;
  final double? hartMax;
  final double? weichMin;
  final double? weichMax;
}

/// Alle Grenzen der Planung — je Anlage oder Parametergruppe und Name.
class GrenzenKatalog {
  const GrenzenKatalog([this._grenzen = const {}]);

  final Map<String, ParameterGrenze> _grenzen;

  /// Der Schlüssel aus [kontext] (Anlage oder Gruppe) und [name].
  static String schluessel(String kontext, String name) =>
      '${kontext.trim()}\u0000${name.trim()}';

  /// Die Grenze für den Wert [name] — wie im Artikel zuerst die der Anlage
  /// [maschine], sonst die der Gruppe [gruppe].
  ParameterGrenze? fuer({
    required String name,
    String maschine = '',
    String gruppe = '',
  }) {
    if (maschine.trim().isNotEmpty) {
      final g = _grenzen[schluessel(maschine, name)];
      if (g != null) return g;
    }
    return _grenzen[schluessel(gruppe, name)];
  }
}

/// Was die Prüfung eines Werts ergab: [blockiert] — so lässt er sich nicht
/// speichern; sonst höchstens ein Hinweis in [meldung].
typedef GrenzPruefung = ({bool blockiert, String? meldung});

/// Prüft [wert] gegen [grenze] — mit denselben Regeln und Texten wie im
/// Artikel. Was keine Zahl ist, bleibt ungeprüft.
GrenzPruefung grenzePruefen(ParameterGrenze? grenze, String wert) {
  const ok = (blockiert: false, meldung: null);
  final g = grenze;
  if (g == null) return ok;
  final zahl = double.tryParse(wert.trim().replaceAll(',', '.'));
  if (zahl == null) return ok;
  String z(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();
  final hartMin = g.hartMin;
  final hartMax = g.hartMax;
  final weichMin = g.weichMin;
  final weichMax = g.weichMax;
  if (hartMin != null && zahl < hartMin) {
    return (
      blockiert: true,
      meldung: 'Unter der technischen Untergrenze (${z(hartMin)}).',
    );
  }
  if (hartMax != null && zahl > hartMax) {
    return (
      blockiert: true,
      meldung: 'Über der technischen Obergrenze (${z(hartMax)}).',
    );
  }
  if (weichMin != null && zahl < weichMin) {
    return (
      blockiert: false,
      meldung: 'Ungewöhnlich niedrig — üblich ist ab ${z(weichMin)}.',
    );
  }
  if (weichMax != null && zahl > weichMax) {
    return (
      blockiert: false,
      meldung: 'Ungewöhnlich hoch — üblich ist bis ${z(weichMax)}.',
    );
  }
  return ok;
}

// ── Stationen und Umbau ────────────────────────────────────────────────

/// Die Stationen: hintereinander stehende Schritte derselben Abteilung —
/// so, wie die Planung sie bündelt.
List<List<ProzessSchritt>> stationenAus(List<ProzessSchritt> schritte) {
  final ergebnis = <List<ProzessSchritt>>[];
  for (final s in schritte) {
    if (ergebnis.isNotEmpty && ergebnis.last.first.abteilung == s.abteilung) {
      ergebnis.last.add(s);
    } else {
      ergebnis.add([s]);
    }
  }
  return ergebnis;
}

/// „4 Schritte · 3 Stationen" — bei früheren Abschnitten „3 Abschnitte",
/// leer ohne Inhalt.
String prozessKurztext(Prozessparameter p) {
  if (p.schritte.isNotEmpty) {
    final n = p.schritte.length;
    final k = stationenAus(p.schritte).length;
    return '${n == 1 ? '1 Schritt' : '$n Schritte'} · '
        '${k == 1 ? '1 Station' : '$k Stationen'}';
  }
  final a = p.abschnitte.length;
  if (a == 0) return '';
  return a == 1 ? '1 Abschnitt' : '$a Abschnitte';
}

/// Was gerade gezogen wird.
sealed class ProzessZug {
  const ProzessZug();
}

/// Ein Schritt der Kette.
class ProzessSchrittZug extends ProzessZug {
  const ProzessSchrittZug(this.id);

  final String id;
}

/// Eine ganze Station — [index] in der Liste der Stationen.
class ProzessStationsZug extends ProzessZug {
  const ProzessStationsZug(this.index);

  final int index;
}

/// Wohin abgelegt wird.
sealed class ProzessZiel {
  const ProzessZiel();
}

/// Auf einen Schritt: davor. In derselben Station wie beim Umsortieren
/// einer Liste — nach rechts gezogen landet er dahinter.
class ProzessZielSchritt extends ProzessZiel {
  const ProzessZielSchritt(this.id, this.station);

  final String id;

  /// Die Station, in der der Schritt [id] steht.
  final int station;
}

/// Auf eine Station: an ihr Ende. Eine gezogene Station rückt an diese
/// Stelle.
class ProzessZielStation extends ProzessZiel {
  const ProzessZielStation(this.station);

  final int station;
}

/// In die Lücke vor Station [vorStation] (gleich der Anzahl der Stationen:
/// hinter der letzten). Ein Schritt behält dort seine Abteilung.
class ProzessZielLuecke extends ProzessZiel {
  const ProzessZielLuecke(this.vorStation);

  final int vorStation;
}

/// Die Kette eines Projekts, wie sie gerade angezeigt wird — und was sich
/// an ihr ändern lässt. Jede Änderung liefert eine neue Liste.
class ProjektKette {
  ProjektKette(this.schritte) : stationen = stationenAus(schritte);

  final List<ProzessSchritt> schritte;

  /// Hintereinander stehende Schritte derselben Abteilung.
  final List<List<ProzessSchritt>> stationen;

  /// Passt kein Schritt mehr hinein?
  bool get voll => schritte.length >= kProzessMaxSchritte;

  /// Position von [id] in der Kette — -1, wenn es ihn nicht gibt.
  int indexVon(String id) => schritte.indexWhere((s) => s.id == id);

  /// Station, in der [id] steht — -1, wenn es ihn nicht gibt.
  int stationVon(String id) =>
      stationen.indexWhere((b) => b.any((s) => s.id == id));

  /// Position in der Kette, an der Station [k] beginnt — für [k] gleich der
  /// Anzahl der Stationen das Ende der Kette.
  int grenzeVor(int k) {
    var n = 0;
    for (var i = 0; i < k && i < stationen.length; i++) {
      n += stationen[i].length;
    }
    return n;
  }

  /// [neu] an Position [index] — null, wenn die Kette voll ist.
  List<ProzessSchritt>? einfuegen(int index, ProzessSchritt neu) {
    if (voll) return null;
    return [...schritte]..insert(index.clamp(0, schritte.length), neu);
  }

  /// [neu] an die Stelle des Schritts mit derselben ID.
  List<ProzessSchritt> ersetzen(ProzessSchritt neu) => [
        for (final s in schritte) s.id == neu.id ? neu : s,
      ];

  List<ProzessSchritt> entfernen(String id) => [
        for (final s in schritte)
          if (s.id != id) s,
      ];

  /// Alle Schritte der Station [station] arbeiten für [abteilung] — etwa
  /// wenn sie aus früheren Abschnitten noch keine hat.
  List<ProzessSchritt> stationAbteilung(int station, String abteilung) {
    if (station < 0 || station >= stationen.length) return schritte;
    final ids = {for (final s in stationen[station]) s.id};
    return [
      for (final s in schritte)
        ids.contains(s.id) ? s.kopie(abteilung: abteilung) : s,
    ];
  }

  static bool _gleich(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Was [zug] auf [ziel] bewirkt: die neue Kette — null, wenn sich nichts
  /// ändern würde oder das Ziel nicht (mehr) zur Kette passt. Dient
  /// zugleich als Prüfung, ob ein Ziel den Zug annimmt.
  List<ProzessSchritt>? umbau(ProzessZug zug, ProzessZiel ziel) {
    final gueltig = switch (ziel) {
      ProzessZielSchritt(:final id, :final station) => station >= 0 &&
          station < stationen.length &&
          stationen[station].any((s) => s.id == id),
      ProzessZielStation(:final station) =>
        station >= 0 && station < stationen.length,
      ProzessZielLuecke(:final vorStation) =>
        vorStation >= 0 && vorStation <= stationen.length,
    };
    if (!gueltig) return null;
    final alt = [for (final s in schritte) s.id];
    final nachId = {for (final s in schritte) s.id: s};

    switch (zug) {
      case ProzessStationsZug(index: final von):
        if (von < 0 || von >= stationen.length) return null;
        final nach = switch (ziel) {
          ProzessZielSchritt(:final station) => station,
          ProzessZielStation(:final station) => station,
          ProzessZielLuecke(:final vorStation) =>
            von < vorStation ? vorStation - 1 : vorStation,
        };
        if (nach == von) return null;
        final neu = [...stationen];
        final gezogen = neu.removeAt(von);
        neu.insert(nach.clamp(0, neu.length), gezogen);
        return [
          for (final b in neu) ...b,
        ];

      case ProzessSchrittZug(:final id):
        final von = indexVon(id);
        if (von < 0) return null;
        final ids = [...alt]..removeAt(von);
        String? abteilung;
        switch (ziel) {
          case ProzessZielSchritt(id: final aufId, :final station):
            if (aufId == id) return null;
            abteilung = stationen[station].first.abteilung;
            // In derselben Station wie beim Umsortieren einer Liste: auf
            // den Platz des Ziels. Aus einer anderen Station: davor.
            final position = stationVon(id) == station
                ? indexVon(aufId)
                : ids.indexOf(aufId);
            ids.insert(position, id);
          case ProzessZielStation(:final station):
            final rest = [
              for (final s in stationen[station])
                if (s.id != id) s,
            ];
            if (rest.isEmpty) return null;
            abteilung = rest.first.abteilung;
            ids.insert(ids.indexOf(rest.last.id) + 1, id);
          case ProzessZielLuecke(:final vorStation):
            final grenze = grenzeVor(vorStation);
            ids.insert(von < grenze ? grenze - 1 : grenze, id);
        }
        final wechsel = abteilung != null && abteilung != nachId[id]!.abteilung;
        if (!wechsel && _gleich(ids, alt)) return null;
        return [
          for (final i in ids)
            i == id && wechsel
                ? nachId[i]!.kopie(abteilung: abteilung)
                : nachId[i]!,
        ];
    }
  }
}

// ── Werte eines Schritts ───────────────────────────────────────────────

/// Gehört [w] zu den Platten — Name „Platte Oben 3" in der Gruppe der
/// Bratstraße oder des Kombiofens?
bool istPlattenWert(ProzessWert w) =>
    (w.gruppe == kPlattenGruppeBrat || w.gruppe == kPlattenGruppeKombi) &&
    kPlattenParamMuster.hasMatch(w.name);

/// Die Gruppe der Plattenwerte einer Anlage — null, wenn sie kein
/// Plattenraster hat.
String? plattenGruppe(String maschine) {
  if (istDampftunnelMaschine(maschine)) return kPlattenGruppeKombi;
  if (istPlattenMaschine(maschine)) return kPlattenGruppeBrat;
  return null;
}

/// [s] mit der Anlage [anlage] — ohne sie bleibt [name] als Text (etwa eine
/// Anlage, die nicht im Katalog steht; leer: ohne Anlage). Platten, die zur
/// neuen Anlage nicht passen, entfallen; alle anderen Werte bleiben.
ProzessSchritt anlageSetzen(
  ProzessSchritt s,
  KatalogAnlage? anlage, {
  String name = '',
}) {
  final maschine = anlage?.name ?? name.trim();
  final gruppe = plattenGruppe(maschine);
  return s.mitAnlage(anlage?.id, maschine).kopie(
    werte: [
      for (final w in s.werte)
        if (!istPlattenWert(w) || w.gruppe == gruppe) w,
    ],
  );
}

/// Der Wert der Platte [name] — leer, wenn sie nicht gesetzt ist.
String plattenWert(ProzessSchritt s, String name, String gruppe) {
  for (final w in s.werte) {
    if (w.gruppe == gruppe && w.name == name) return w.wert;
  }
  return '';
}

/// Setzt die Platten aus [werte] (Name → Wert, leer: nicht gesetzt).
ProzessSchritt mitPlatten(
  ProzessSchritt s,
  String gruppe,
  Map<String, String> werte,
) {
  // Vorhandene Platten bleiben an ihrem Platz — so ändert ein Wert, der
  // wieder auf den alten zurückgeht, nichts an der Kette.
  final offen = {...werte};
  final neu = <ProzessWert>[];
  for (final w in s.werte) {
    final wert = w.gruppe == gruppe ? offen.remove(w.name) : null;
    if (wert == null) {
      neu.add(w);
    } else if (wert.trim().isNotEmpty) {
      neu.add(w.kopie(wert: wert.trim()));
    }
  }
  for (final MapEntry(:key, :value) in offen.entries) {
    if (value.trim().isEmpty) continue;
    neu.add(ProzessWert(name: key, wert: value.trim(), gruppe: gruppe));
  }
  return s.kopie(werte: neu);
}

/// Der Wert zum Steckbrief-Feld [name] — wie im Artikel nur über den
/// Namen, gleich in welcher Gruppe; eine Zeile außerhalb von
/// MASCHINENEINSTELLUNGEN hat Vorrang.
ProzessWert? steckbriefWert(ProzessSchritt s, String name) {
  final gesucht = _norm(name);
  ProzessWert? treffer;
  for (final w in s.werte) {
    if (w.eigen || istPlattenWert(w) || _norm(w.name) != gesucht) continue;
    if (w.gruppe != kMaschinenNotizGruppe) return w;
    treffer ??= w;
  }
  return treffer;
}

/// In welche Gruppe ein neuer Wert aus dem Steckbrief kommt: in die, die
/// der Schritt schon für Maschinenwerte benutzt — sonst
/// MASCHINENEINSTELLUNGEN. Wie im Artikel, damit er im Export im richtigen
/// Block steht.
String steckbriefGruppe(ProzessSchritt s) {
  for (final w in s.werte) {
    if (w.eigen || w.gruppe.trim().isEmpty) continue;
    if (w.gruppe == kMaschinenNotizGruppe) continue;
    return w.gruppe;
  }
  return kMaschinenNotizGruppe;
}

/// Setzt den Wert des Steckbrief-Felds [feld] — leer nimmt ihn heraus.
ProzessSchritt mitSteckbriefWert(
  ProzessSchritt s,
  SteckbriefFeld feld,
  String wert,
) {
  final neu = wert.trim();
  final vorhanden = steckbriefWert(s, feld.name);
  if (vorhanden != null) {
    return s.kopie(
      werte: [
        for (final w in s.werte)
          if (!identical(w, vorhanden))
            w
          else if (neu.isNotEmpty)
            w.kopie(wert: neu),
      ],
    );
  }
  if (neu.isEmpty) return s;
  return s.kopie(
    werte: [
      ...s.werte,
      ProzessWert(
        name: feld.name,
        wert: neu,
        einheit: feld.einheit,
        gruppe: steckbriefGruppe(s),
      ),
    ],
  );
}

/// Die Werte, die weder im Steckbrief [steckbrief] stehen noch Platten oder
/// eigene sind — etwa aus einem Artikel mit Excel-Vorlage übernommene.
List<ProzessWert> weitereWerte(
  ProzessSchritt s,
  List<SteckbriefFeld> steckbrief,
) {
  final namen = {for (final f in steckbrief) _norm(f.name)};
  return [
    for (final w in s.werte)
      if (!w.eigen && !istPlattenWert(w) && !namen.contains(_norm(w.name))) w,
  ];
}

/// Die eigenen Werte eines Schritts.
List<ProzessWert> eigeneWerte(ProzessSchritt s) => [
      for (final w in s.werte)
        if (w.eigen) w,
    ];

/// Ersetzt den Wert mit dem Schlüssel von [alt] durch [neu] — null nimmt
/// ihn heraus. Ohne [alt] kommt [neu] dazu.
ProzessSchritt wertSetzen(
  ProzessSchritt s, {
  ProzessWert? alt,
  ProzessWert? neu,
}) {
  if (alt == null) {
    return neu == null ? s : s.kopie(werte: [...s.werte, neu]);
  }
  final schluessel = alt.schluessel;
  return s.kopie(
    werte: [
      for (final w in s.werte)
        if (w.schluessel != schluessel) w else if (neu != null) neu,
    ],
  );
}

/// Ein eigener Wert [name] mit [wert] — null, wenn der Schritt schon einen
/// so nennt.
ProzessSchritt? mitEigenemWert(
  ProzessSchritt s,
  String name, {
  String wert = '',
}) {
  final n = name.trim();
  if (n.isEmpty) return null;
  if (eigeneWerte(s).any((w) => _norm(w.name) == _norm(n))) return null;
  return s.kopie(
    werte: [
      ...s.werte,
      ProzessWert(
        name: n,
        wert: wert.trim(),
        gruppe: kEigeneWerteGruppe,
        eigen: true,
      ),
    ],
  );
}

/// Wie viele Werte eines Schritts eingetragen sind, von allen, die er
/// haben kann: die Felder des Steckbriefs, weitere und eigene Werte — die
/// Platten zählen zusammen als einer.
({int eingetragen, int gesamt}) werteStand(
  ProzessSchritt s,
  KatalogAnlage? anlage,
) {
  var eingetragen = 0;
  var gesamt = 0;
  final steckbrief = anlage?.steckbrief ?? const <SteckbriefFeld>[];
  for (final f in steckbrief) {
    gesamt++;
    if (!(steckbriefWert(s, f.name)?.leer ?? true)) eingetragen++;
  }
  for (final w in [...weitereWerte(s, steckbrief), ...eigeneWerte(s)]) {
    gesamt++;
    if (!w.leer) eingetragen++;
  }
  if (plattenGruppe(s.maschine) != null) {
    gesamt++;
    if (s.werte.any((w) => istPlattenWert(w) && !w.leer)) eingetragen++;
  }
  return (eingetragen: eingetragen, gesamt: gesamt);
}

/// Was von einem Schritt im Bericht steht: die Maschineneinstellungen, die
/// eingetragenen Werte und die Platten je Reihe — „180 · 180 · – · …".
List<(String, String)> schrittZeilen(ProzessSchritt s) {
  final zeilen = <(String, String)>[
    if (s.notiz.trim().isNotEmpty) ('Maschineneinstellungen', s.notiz.trim()),
    for (final w in s.werte)
      if (!istPlattenWert(w) && !w.leer) (w.label, w.wert.trim()),
  ];
  final gruppe = plattenGruppe(s.maschine);
  if (gruppe == null) return zeilen;
  final namen = plattenZeilenFuer(s.maschine);
  for (final (label, praefix) in const [
    ('Platten oben (°C)', 'Platte Oben '),
    ('Platten unten (°C)', 'Platte Unten '),
  ]) {
    final reihe = [
      for (final n in namen)
        if (n.startsWith(praefix)) plattenWert(s, n, gruppe).trim(),
    ];
    if (reihe.every((w) => w.isEmpty)) continue;
    zeilen
        .add((label, [for (final w in reihe) w.isEmpty ? '–' : w].join(' · ')));
  }
  return zeilen;
}

// ── Aus dem Artikel ────────────────────────────────────────────────────

/// Ein Parameter eines Schritts im Artikel.
typedef ArtikelParameter = ({
  String gruppe,
  String name,
  String? wert,
  bool eigen,
});

/// Ein Schritt aus der Kette eines Artikels als Schritt des Projekts. Die
/// Maschineneinstellungen werden die Notiz, der Marker des Plattenrasters
/// bleibt weg; leere Werte nur, wenn sie eigene sind.
ProzessSchritt schrittAusArtikel({
  required String id,
  required String abteilung,
  String? maschineId,
  String? maschine,
  String? prozessschritt,
  List<ArtikelParameter> parameter = const [],
  KatalogAnlage? anlage,
}) {
  final einheiten = {
    for (final f in anlage?.steckbrief ?? const <SteckbriefFeld>[])
      _norm(f.name): f.einheit,
  };
  var notiz = '';
  final werte = <ProzessWert>[];
  for (final p in parameter) {
    final wert = p.wert?.trim() ?? '';
    if (p.name == kPlattenSchemaParam) continue;
    if (p.name == kMaschinenNotizParam) {
      notiz = wert;
      continue;
    }
    if (wert.isEmpty && !p.eigen) continue;
    werte.add(
      ProzessWert(
        name: p.name,
        wert: wert,
        einheit: p.eigen ? '' : einheiten[_norm(p.name)] ?? '',
        gruppe: p.gruppe,
        eigen: p.eigen,
      ),
    );
  }
  return ProzessSchritt(
    id: id,
    abteilung: abteilung,
    maschineId: anlage?.id ?? maschineId,
    maschine: anlage?.name ?? maschine?.trim() ?? '',
    prozessschritt: prozessschritt?.trim() ?? '',
    notiz: notiz,
    werte: werte,
  );
}

/// [schritte] mit neuen IDs — zum Übernehmen aus einem anderen Projekt.
List<ProzessSchritt> mitNeuenIds(
  List<ProzessSchritt> schritte,
  String Function() neueId,
) =>
    [for (final s in schritte) s.kopie(id: neueId())];

// ── Frühere Abschnitte (F34) ───────────────────────────────────────────

/// Was beim Umsetzen geschah.
typedef ProzessUmsetzung = ({
  Prozessparameter prozess,
  int schritte,
  int entfallen,
});

/// Die Anlage zu [text]: gleich benannt (ohne Groß-/Kleinschreibung) —
/// sonst die einzige, deren Name so beginnt.
KatalogAnlage? anlageZu(String text, List<KatalogAnlage> katalog) {
  final t = _norm(text);
  if (t.isEmpty) return null;
  for (final k in katalog) {
    if (_norm(k.name) == t) return k;
  }
  final beginnt = [
    for (final k in katalog)
      if (_norm(k.name).startsWith(t)) k,
  ];
  return beginnt.length == 1 ? beginnt.single : null;
}

/// Eine Abteilung, die so heißt wie [text] — leer, wenn keine.
String _abteilungZu(String text) {
  final t = _norm(text);
  for (final a in Abteilung.values) {
    if (_norm(a.anzeigeName) == t || a.dbValue == t) return a.dbValue;
  }
  return '';
}

const Set<String> _anlagenFelder = {'anlage', 'maschine'};

const Set<String> _einstellungsFelder = {
  'maschineneinstellungen',
  'maschine und einstellungen',
  'einstellungen',
};

/// „Kerntemperatur (°C)" → „kerntemperatur".
String _ohneEinheit(String label) =>
    _norm(label.replaceAll(RegExp(r'\s*\([^)]*\)\s*$'), ''));

/// Setzt die Abschnitte aus der Zeit vor der Kette in Schritte um (F34).
///
/// Je Abschnitt ein Schritt: Seine Anlage ist die, die im Feld „Anlage"
/// steht oder so heißt wie der Abschnitt; deren Abteilung gilt (sonst eine
/// Abteilung, die so heißt wie der Abschnitt). Der Titel wird der
/// Prozessschritt. Felder mit Werten werden Werte des Steckbriefs, wenn
/// die Anlage ein Feld dieses Namens hat, sonst eigene; Einstellungen als
/// Text werden die Notiz. Abschnitte ohne Anlage und ohne jeden Wert — das
/// Gerüst der früheren Vorlage — entfallen.
ProzessUmsetzung prozessUmsetzen(
  Prozessparameter p,
  List<KatalogAnlage> katalog,
) {
  if (p.abschnitte.isEmpty) {
    return (prozess: p, schritte: 0, entfallen: 0);
  }
  final vergeben = {for (final s in p.schritte) s.id};
  String id(ProzessAbschnitt a, int i) {
    final basis = 's-${a.id.trim().isEmpty ? i + 1 : a.id.trim()}';
    var kandidat = basis;
    var n = 2;
    while (vergeben.contains(kandidat)) {
      kandidat = '$basis-${n++}';
    }
    vergeben.add(kandidat);
    return kandidat;
  }

  final neu = <ProzessSchritt>[];
  var entfallen = 0;
  for (final (i, a) in p.abschnitte.indexed) {
    final anlagenFeld = a.felder
        .where(
          (f) =>
              _anlagenFelder.contains(_norm(f.label)) &&
              f.wert.trim().isNotEmpty,
        )
        .firstOrNull;
    final ausFeld =
        anlagenFeld == null ? null : anlageZu(anlagenFeld.wert, katalog);
    final ausTitel = ausFeld == null ? anlageZu(a.titel, katalog) : null;
    final anlage = ausFeld ?? ausTitel;
    // Das Feld „Anlage" nennt die Anlage — oder ist ihr Name, wenn es sie
    // im Katalog nicht gibt. Fand sie erst der Titel, bleibt es ein Wert.
    final feldIstAnlage =
        anlagenFeld != null && (ausFeld != null || anlage == null);
    final steckbrief = {
      for (final f in anlage?.steckbrief ?? const <SteckbriefFeld>[])
        _norm(f.name): f,
    };

    final notizen = <String>[];
    final werte = <ProzessWert>[];
    for (final f in a.felder) {
      final wert = f.wert.trim();
      if (wert.isEmpty || (feldIstAnlage && identical(f, anlagenFeld))) {
        continue;
      }
      if (_einstellungsFelder.contains(_norm(f.label))) {
        notizen.add(wert);
        continue;
      }
      final def =
          steckbrief[_norm(f.label)] ?? steckbrief[_ohneEinheit(f.label)];
      werte.add(
        def != null
            ? ProzessWert(
                name: def.name,
                wert: wert,
                einheit: def.einheit,
                gruppe: kMaschinenNotizGruppe,
              )
            : ProzessWert(
                name: f.label.trim().isEmpty ? 'Wert' : f.label.trim(),
                wert: wert,
                gruppe: kEigeneWerteGruppe,
                eigen: true,
              ),
      );
    }
    final feldText = switch (anlagenFeld) {
      final f? when feldIstAnlage => f.wert.trim(),
      _ => '',
    };
    final maschine = anlage?.name ?? feldText;
    if (anlage == null &&
        maschine.isEmpty &&
        werte.isEmpty &&
        notizen.isEmpty) {
      entfallen++;
      continue;
    }
    neu.add(
      ProzessSchritt(
        id: id(a, i),
        abteilung: anlage?.abteilung ?? _abteilungZu(a.titel),
        maschineId: anlage?.id,
        maschine: maschine,
        // Hieß der Abschnitt wie die Anlage, ist er kein eigener Schritt.
        prozessschritt: ausTitel != null ? '' : a.titel.trim(),
        notiz: notizen.join('\n'),
        werte: werte,
      ),
    );
  }
  return (
    prozess: Prozessparameter(
      version: p.version,
      stand: p.stand,
      schritte: [...p.schritte, ...neu],
    ),
    schritte: neu.length,
    entfallen: entfallen,
  );
}

// ── Vergleich ──────────────────────────────────────────────────────────

/// Eine Abweichung zwischen zwei Ständen des Prozesses.
class ParameterAenderung {
  const ParameterAenderung({
    required this.abschnitt,
    required this.feld,
    required this.alt,
    required this.neu,
  });

  /// Der Schritt (oder frühere Abschnitt), um den es geht.
  final String abschnitt;
  final String feld;

  /// null: Das gab es vorher nicht.
  final String? alt;

  /// null: Das gibt es nicht mehr.
  final String? neu;
}

/// Was sich von [alt] nach [neu] geändert hat — Schritte über ihre IDs,
/// Werte über Gruppe und Name, frühere Abschnitte über die IDs von
/// Abschnitt und Feld.
List<ParameterAenderung> vergleicheParameter(
  Prozessparameter alt,
  Prozessparameter neu,
) =>
    [
      ..._vergleicheKette(alt.schritte, neu.schritte),
      ..._vergleicheAbschnitte(alt, neu),
    ];

List<ParameterAenderung> _vergleicheKette(
  List<ProzessSchritt> alt,
  List<ProzessSchritt> neu,
) {
  final ergebnis = <ParameterAenderung>[];
  final vorher = {for (final s in alt) s.id: s};
  final nachher = {for (final s in neu) s.id: s};
  String name(ProzessSchritt s, List<ProzessSchritt> kette) =>
      s.bezeichnung(kette.indexOf(s) + 1);
  String ort(ProzessSchritt s, List<ProzessSchritt> kette) =>
      'Schritt ${kette.indexOf(s) + 1} · ${abteilungsName(s.abteilung)}';

  for (final s in neu) {
    final n = name(s, neu);
    final v = vorher[s.id];
    if (v == null) {
      ergebnis.add(
        ParameterAenderung(
          abschnitt: n,
          feld: 'In der Kette',
          alt: null,
          neu: ort(s, neu),
        ),
      );
      continue;
    }
    void feld(String label, String a, String b) {
      if (a.trim() == b.trim()) return;
      ergebnis
          .add(ParameterAenderung(abschnitt: n, feld: label, alt: a, neu: b));
    }

    feld('Abteilung', abteilungsName(v.abteilung), abteilungsName(s.abteilung));
    feld('Anlage', v.maschine, s.maschine);
    feld('Prozessschritt', v.prozessschritt, s.prozessschritt);
    feld('Maschineneinstellungen', v.notiz, s.notiz);
    final werteVorher = {for (final w in v.werte) w.schluessel: w};
    final werteNachher = {for (final w in s.werte) w.schluessel: w};
    for (final w in s.werte) {
      final x = werteVorher[w.schluessel];
      if (x == null) {
        if (!w.leer) {
          ergebnis.add(
            ParameterAenderung(
              abschnitt: n,
              feld: w.label,
              alt: null,
              neu: w.wert,
            ),
          );
        }
      } else if (x.wert.trim() != w.wert.trim()) {
        ergebnis.add(
          ParameterAenderung(
            abschnitt: n,
            feld: w.label,
            alt: x.wert,
            neu: w.wert,
          ),
        );
      }
    }
    for (final x in v.werte) {
      if (!werteNachher.containsKey(x.schluessel) && !x.leer) {
        ergebnis.add(
          ParameterAenderung(
            abschnitt: n,
            feld: x.label,
            alt: x.wert,
            neu: null,
          ),
        );
      }
    }
  }
  for (final v in alt) {
    if (nachher.containsKey(v.id)) continue;
    ergebnis.add(
      ParameterAenderung(
        abschnitt: name(v, alt),
        feld: 'In der Kette',
        alt: ort(v, alt),
        neu: null,
      ),
    );
  }
  // Die Reihenfolge der Schritte, die es in beiden gibt.
  final reiheVorher = [
    for (final s in alt)
      if (nachher.containsKey(s.id)) s,
  ];
  final reiheNachher = [
    for (final s in neu)
      if (vorher.containsKey(s.id)) s,
  ];
  if (!ProjektKette._gleich(
    [for (final s in reiheVorher) s.id],
    [for (final s in reiheNachher) s.id],
  )) {
    ergebnis.add(
      ParameterAenderung(
        abschnitt: 'Prozesskette',
        feld: 'Reihenfolge',
        alt: [for (final s in reiheVorher) name(s, alt)].join(' → '),
        neu: [for (final s in reiheNachher) name(s, neu)].join(' → '),
      ),
    );
  }
  return ergebnis;
}

List<ParameterAenderung> _vergleicheAbschnitte(
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
