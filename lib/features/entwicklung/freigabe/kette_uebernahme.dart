import '../../../core/constants/parameter_namen.dart';
import '../haccp/prozess_kette.dart';
import '../haccp/prozess_modell.dart';

// Bei der Freigabe wird die Kette des Projekts die des Artikels (F35):
// Schritte, die einander entsprechen, bleiben derselbe Schritt im Artikel —
// mit Personen und Leistungsdaten —, neue kommen dazu, und was das Projekt
// nicht mehr hat, entfällt nach Rückfrage. Hier rein rechnerisch: die
// Zuordnung, die Kette danach, die Vorschau und was mit den Werten eines
// Schritts geschieht. Geschrieben wird in freigabe.dart.

String _norm(String text) => text.trim().toLowerCase();

bool _istPlatte(String name) => kPlattenParamMuster.hasMatch(name.trim());

/// Entsprechen sich [a] (im Artikel) und [p] (im Projekt)? Dieselbe Anlage
/// — ohne Anlage aus dem Katalog derselbe Name (Anlage oder
/// Prozessschritt).
bool schritteEntsprechen(ProzessSchritt a, ProzessSchritt p) {
  final ma = a.maschineId;
  final mp = p.maschineId;
  if (ma != null && mp != null) return ma == mp;
  final name = _norm(a.name);
  return name.isNotEmpty && name == _norm(p.name);
}

/// Je Schritt des Projekts die ID des Schritts im Artikel, der ihm
/// entspricht — null, wenn er neu ist. In der Reihenfolge der Kette; jeder
/// Schritt des Artikels höchstens einmal, bei mehreren passenden zuerst
/// einer derselben Abteilung.
List<String?> schritteZuordnen(
  List<ProzessSchritt> artikel,
  List<ProzessSchritt> projekt,
) {
  final frei = [...artikel];
  final ergebnis = <String?>[];
  for (final p in projekt) {
    final passend = frei.where((a) => schritteEntsprechen(a, p)).toList();
    final treffer =
        passend.where((a) => a.abteilung == p.abteilung).firstOrNull ??
            passend.firstOrNull;
    if (treffer != null) frei.remove(treffer);
    ergebnis.add(treffer?.id);
  }
  return ergebnis;
}

/// Ein Schritt der Kette, wie der Artikel sie bekommt.
class ZielSchritt {
  const ZielSchritt({required this.schritt, this.artikelId});

  /// Der Schritt im Artikel — null: Er entsteht neu.
  final String? artikelId;

  /// Abteilung, Anlage, Prozessschritt und Werte.
  final ProzessSchritt schritt;
}

/// [p] mit den Gruppen, unter denen der Artikelschritt [a] dieselben Werte
/// führt — so ändert sich ein Wert an seiner Stelle, statt doppelt
/// dazuzukommen. Die Anlage aus dem Katalog bleibt, wenn das Projekt nur
/// ihren Namen kennt.
ProzessSchritt _angeglichen(ProzessSchritt p, ProzessSchritt a) {
  final gruppen = <String, String>{
    for (final w in a.werte)
      if (!w.eigen && !istPlattenWert(w)) _norm(w.name): w.gruppe,
  };
  var s = p.kopie(
    werte: [
      for (final w in p.werte)
        if (!w.eigen && !istPlattenWert(w) && gruppen[_norm(w.name)] != null)
          ProzessWert(
            name: w.name,
            wert: w.wert,
            einheit: w.einheit,
            gruppe: gruppen[_norm(w.name)]!,
          )
        else
          w,
    ],
  );
  final id = a.maschineId;
  if (p.maschineId == null &&
      id != null &&
      p.maschine.trim().isNotEmpty &&
      _norm(p.maschine) == _norm(a.maschine)) {
    s = s.mitAnlage(id, p.maschine);
  }
  return s;
}

/// Die Werte von [a], die [p] nicht hat — nicht leer, und ohne die, die
/// [p] unter anderem Namen in derselben Gruppe führt.
List<ProzessWert> werteNurIn(ProzessSchritt a, ProzessSchritt p) {
  final schluessel = {for (final w in p.werte) w.schluessel};
  final namen = {
    for (final w in p.werte)
      if (!w.eigen && !istPlattenWert(w)) _norm(w.name),
  };
  return [
    for (final w in a.werte)
      if (!w.leer &&
          !schluessel.contains(w.schluessel) &&
          (w.eigen || istPlattenWert(w) || !namen.contains(_norm(w.name))))
        w,
  ];
}

/// [s] mit den Werten von [a], die es selbst nicht hat — und dessen
/// Maschineneinstellungen, wenn es keine hat.
ProzessSchritt _mitWertenVon(ProzessSchritt s, ProzessSchritt a) =>
    s.kopie(
      notiz: s.notiz.trim().isEmpty ? a.notiz : null,
      werte: [...s.werte, ...werteNurIn(a, s)],
    );

/// Die Kette, die der Artikel bekommt: die Schritte des Projekts, die
/// entsprechenden mit der ID ihres Schritts im Artikel.
///
/// Mit [entfernen] fallen Schritte und Werte des Artikels weg, die das
/// Projekt nicht hat. Ohne bleiben sie: ein Schritt hinter dem, hinter dem
/// er vorher stand — und hinter den neuen Schritten, die das Projekt dort
/// einfügt —, ein Wert an seinem Schritt.
List<ZielSchritt> zielKette(
  List<ProzessSchritt> artikel,
  List<ProzessSchritt> projekt, {
  required bool entfernen,
}) {
  final zuordnung = schritteZuordnen(artikel, projekt);
  final nachId = {for (final a in artikel) a.id: a};
  final ziel = <ZielSchritt>[];
  for (final (i, p) in projekt.indexed) {
    final id = zuordnung[i];
    final a = id == null ? null : nachId[id];
    var s = p;
    if (a != null) {
      s = _angeglichen(p, a);
      if (!entfernen) s = _mitWertenVon(s, a);
    }
    ziel.add(ZielSchritt(artikelId: id, schritt: s));
  }
  if (entfernen) return ziel;
  final vergeben = {...zuordnung.whereType<String>()};
  for (final (i, a) in artikel.indexed) {
    if (vergeben.contains(a.id)) continue;
    // Hinter den nächsten Schritt davor, der in der Kette steht — die
    // neuen dahinter bleiben, wo das Projekt sie hat.
    var position = 0;
    for (var j = i - 1; j >= 0; j--) {
      final k = ziel.indexWhere((z) => z.artikelId == artikel[j].id);
      if (k >= 0) {
        position = k + 1;
        break;
      }
    }
    while (position < ziel.length && ziel[position].artikelId == null) {
      position++;
    }
    ziel.insert(position, ZielSchritt(artikelId: a.id, schritt: a));
  }
  return ziel;
}

/// Was die Übernahme der Kette am Artikel ändert — für das Fenster der
/// Freigabe.
class UebernahmeVorschau {
  const UebernahmeVorschau({
    required this.ziel,
    required this.vorher,
    required this.nachher,
    required this.bleiben,
    required this.neu,
    required this.nurImArtikel,
    required this.werteNurImArtikel,
    required this.aenderungen,
  });

  /// Die Kette danach.
  final List<ZielSchritt> ziel;

  /// Die Kette des Artikels jetzt und danach — zum Vergleichen; Schritte
  /// unter ihrer ID im Artikel, neue unter einer, die es dort nicht gibt.
  final Prozessparameter vorher;
  final Prozessparameter nachher;

  /// Schritte des Artikels, die einem des Projekts entsprechen.
  final int bleiben;

  /// Schritte, die neu entstehen.
  final int neu;

  /// Schritte des Artikels, die das Projekt nicht hat.
  final List<ProzessSchritt> nurImArtikel;

  /// Werte (und Maschineneinstellungen) in Schritten, die bleiben, die das
  /// Projekt nicht hat.
  final int werteNurImArtikel;

  /// Was sich am Artikel ändert — Schritte, Werte, Reihenfolge.
  final List<ParameterAenderung> aenderungen;

  /// Gibt es etwas, das wegfallen könnte?
  bool get etwasEntfaellt =>
      nurImArtikel.isNotEmpty || werteNurImArtikel > 0;
}

/// Die Vorschau der Übernahme von [projekt] in die Kette [artikel].
UebernahmeVorschau uebernahmeVorschau(
  List<ProzessSchritt> artikel,
  List<ProzessSchritt> projekt, {
  required bool entfernen,
}) {
  final ziel = zielKette(artikel, projekt, entfernen: entfernen);
  final zuordnung = schritteZuordnen(artikel, projekt);
  final vergeben = {...zuordnung.whereType<String>()};
  final nachId = {for (final a in artikel) a.id: a};
  var werte = 0;
  for (final (i, p) in projekt.indexed) {
    final id = zuordnung[i];
    final a = id == null ? null : nachId[id];
    if (a == null) continue;
    werte += werteNurIn(a, _angeglichen(p, a)).length;
    if (a.notiz.trim().isNotEmpty && p.notiz.trim().isEmpty) werte++;
  }
  final vorher = Prozessparameter(schritte: artikel);
  final nachher = Prozessparameter(
    schritte: [
      for (final (i, z) in ziel.indexed)
        z.schritt.kopie(id: z.artikelId ?? '\u0000neu$i'),
    ],
  );
  return UebernahmeVorschau(
    ziel: ziel,
    vorher: vorher,
    nachher: nachher,
    bleiben: vergeben.length,
    neu: ziel.where((z) => z.artikelId == null).length,
    nurImArtikel: [
      for (final a in artikel)
        if (!vergeben.contains(a.id)) a,
    ],
    werteNurImArtikel: werte,
    aenderungen: vergleicheParameter(vorher, nachher),
  );
}

/// Die Stationen ohne Abteilung — ihre Nummern (ab 1). Ohne Abteilung
/// lässt sich ein Schritt nicht in den Artikel schreiben.
List<int> stationenOhneAbteilung(List<ProzessSchritt> schritte) => [
      for (final (i, s) in stationenAus(schritte).indexed)
        if (abteilungAus(s.first.abteilung) == null) i + 1,
    ];

// ── Werte eines Schritts ───────────────────────────────────────────────

/// Ein Wert eines Schritts im Artikel.
typedef ArtikelWert = ({
  String id,
  String gruppe,
  String name,
  String? wert,
  bool eigen,
  int reihenfolge,
});

/// Was mit einem Wert im Artikel geschieht.
sealed class WertAktion {
  const WertAktion();
}

/// Ein vorhandener Wert ändert sich — null leert ihn (die Zeile bleibt,
/// etwa für die Excel-Vorlage).
class WertSetzen extends WertAktion {
  const WertSetzen(this.id, this.wert);

  final String id;
  final String? wert;
}

/// Ein Wert kommt dazu.
class WertAnlegen extends WertAktion {
  const WertAnlegen({
    required this.gruppe,
    required this.name,
    required this.wert,
    required this.eigen,
    required this.reihenfolge,
  });

  final String gruppe;
  final String name;
  final String? wert;
  final bool eigen;
  final int reihenfolge;
}

/// Ein eigener Wert fällt weg.
class WertLoeschen extends WertAktion {
  const WertLoeschen(this.id);

  final String id;
}

/// Was an den Werten [vorhanden] eines Artikelschritts geschieht, damit
/// er die Werte von [soll] hat: vorhandene ändern sich an ihrer Stelle
/// (dieselbe Gruppe und derselbe Name, sonst derselbe Name), fehlende
/// kommen dazu. Mit [entfernen] werden Werte geleert, die [soll] nicht hat
/// — eigene fallen ganz weg, die Zeilen der Vorlage bleiben leer stehen.
/// Der Marker des Plattenrasters bleibt, wie er ist; fehlt er bei
/// eingetragenen Platten, kommt er dazu.
List<WertAktion> werteAbgleichen(
  List<ArtikelWert> vorhanden,
  ProzessSchritt soll, {
  required bool entfernen,
}) {
  final aktionen = <WertAktion>[];
  final frei = [
    for (final v in vorhanden)
      if (v.name != kPlattenSchemaParam) v,
  ];
  var naechste = vorhanden.fold<int>(
        0,
        (m, v) => v.reihenfolge > m ? v.reihenfolge : m,
      ) +
      1;
  ArtikelWert? nimm(bool Function(ArtikelWert v) passt) {
    final treffer = frei.where(passt).firstOrNull;
    if (treffer != null) frei.remove(treffer);
    return treffer;
  }

  void setze(String gruppe, String name, String wert, {bool eigen = false}) {
    final n = name.trim();
    final w = wert.trim();
    final v = nimm(
          (v) => v.eigen == eigen && v.gruppe == gruppe && v.name.trim() == n,
        ) ??
        (eigen || _istPlatte(n)
            ? null
            : nimm(
                (v) => !v.eigen && !_istPlatte(v.name) && _norm(v.name) == _norm(n),
              ));
    if (v != null) {
      if ((v.wert ?? '').trim() != w) {
        aktionen.add(WertSetzen(v.id, w.isEmpty ? null : w));
      }
    } else if (w.isNotEmpty || eigen) {
      aktionen.add(
        WertAnlegen(
          gruppe: gruppe,
          name: n,
          wert: w.isEmpty ? null : w,
          eigen: eigen,
          reihenfolge: naechste++,
        ),
      );
    }
  }

  if (soll.notiz.trim().isNotEmpty) {
    setze(kMaschinenNotizGruppe, kMaschinenNotizParam, soll.notiz);
  }
  for (final w in soll.werte) {
    if (w.leer && !w.eigen) continue;
    final gruppe = w.gruppe.trim().isNotEmpty
        ? w.gruppe
        : (w.eigen ? kEigeneWerteGruppe : kMaschinenNotizGruppe);
    setze(gruppe, w.name, w.wert, eigen: w.eigen);
  }
  final platten = plattenGruppe(soll.maschine);
  if (platten != null &&
      soll.werte.any((w) => istPlattenWert(w) && !w.leer) &&
      !vorhanden.any((v) => v.name == kPlattenSchemaParam)) {
    aktionen.add(
      WertAnlegen(
        gruppe: platten,
        name: kPlattenSchemaParam,
        wert: platten == kPlattenGruppeKombi ? 'kombiofen' : 'bratstrasse',
        eigen: false,
        reihenfolge: 0,
      ),
    );
  }
  if (entfernen) {
    for (final v in frei) {
      if (v.eigen) {
        aktionen.add(WertLoeschen(v.id));
      } else if ((v.wert ?? '').trim().isNotEmpty) {
        aktionen.add(WertSetzen(v.id, null));
      }
    }
  }
  return aktionen;
}
