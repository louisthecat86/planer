import '../../../core/database/database.dart';
import '../../../core/utils/format.dart';
import '../daten/entwicklung_repository.dart' show VersionStatus, nachName;
import '../rechenkern/naehrwert_rundung.dart';
import '../rechenkern/rechenkern.dart';
import 'projekt_modell.dart';

// Der Entwicklungsstrang eines Produkts: von der Idee über die
// Rezepturstände (die Stationen) bis zum fertigen Artikel. Hier die
// reinen Regeln dafür — welche Phase wann gilt, welcher Eintrag zu welcher
// Station gehört und wie sich die Kennzahlen von Stand zu Stand ändern.

/// Präfix im Feld `wert` eines Meilensteins, der einen Statuswechsel
/// festhält: „status:entwicklung>validierung".
const String kStatusWertPraefix = 'status:';

/// Der Wert für einen Statuswechsel von [alt] zu [neu].
String statusWert(ProjektStatus alt, ProjektStatus neu) =>
    '$kStatusWertPraefix${alt.schluessel}>${neu.schluessel}';

/// Der Titel des Meilensteins zu einem Statuswechsel.
String statusMeilensteinTitel(ProjektStatus neu) => switch (neu) {
      ProjektStatus.entwicklung => 'Wieder in Entwicklung',
      ProjektStatus.validierung => 'Validierung begonnen',
      ProjektStatus.produktion => 'In Produktion',
      ProjektStatus.eingestellt => 'Nicht weiter verfolgt',
      ProjektStatus.archiviert => 'Archiviert',
    };

/// Der Statuswechsel, den ein Eintrag festhält — null, wenn er keinen
/// festhält. [alt] ist null, wenn der Eintrag ihn nicht nennt.
({ProjektStatus? alt, ProjektStatus neu})? statusWechsel(ProjektEintrag e) {
  final w = e.wert?.trim() ?? '';
  if (EintragArt.aus(e.art) != EintragArt.meilenstein ||
      !w.startsWith(kStatusWertPraefix)) {
    return null;
  }
  final teile = w.substring(kStatusWertPraefix.length).split('>');
  if (teile.last.trim().isEmpty) return null;
  return (
    alt: teile.length > 1 ? ProjektStatus.aus(teile.first) : null,
    neu: ProjektStatus.aus(teile.last),
  );
}

/// Die Phase, bevor das Projekt zu ruhen begann (archiviert oder nicht
/// weiter verfolgt) — dort geht es beim Wiederaufnehmen weiter. Ging es
/// von einem Ruhen ins andere, zählt die Phase davor. Ohne Angabe im
/// Verlauf: die Entwicklung.
ProjektStatus phaseVorDemArchiv(Iterable<ProjektEintrag> eintraege) {
  for (final e in zeitlichSortiert(eintraege).reversed) {
    final w = statusWechsel(e);
    if (w == null || !w.neu.ruht) continue;
    final alt = w.alt;
    if (alt == null) return ProjektStatus.entwicklung;
    if (!alt.ruht) return alt;
  }
  return ProjektStatus.entwicklung;
}

/// Ältester zuerst; bei gleichem Datum der früher angelegte.
List<ProjektEintrag> zeitlichSortiert(Iterable<ProjektEintrag> eintraege) =>
    [...eintraege]..sort((a, b) {
        final d = a.datum.compareTo(b.datum);
        return d != 0 ? d : a.createdAt.compareTo(b.createdAt);
      });

/// Der Status, der bei jedem Eintrag galt — nach den Statuswechseln im
/// Verlauf. Jedes Projekt beginnt in der Entwicklung: Bis zum ersten
/// Wechsel gilt sie, wenn er von ihr ausgeht, ohne Wechsel, solange das
/// Projekt ([aktuell]) noch in ihr ist. Sonst ist unbekannt, wann das
/// Projekt in seinen Status kam (etwa bei Projekten aus der Suite) — die
/// Einträge bis dahin fehlen im Ergebnis.
Map<String, ProjektStatus> statusJeEintrag(
  Iterable<ProjektEintrag> eintraege,
  ProjektStatus aktuell,
) {
  final sortiert = zeitlichSortiert(eintraege);
  final wechsel = [
    for (final e in sortiert)
      if (statusWechsel(e) case final w?) w,
  ];
  final anfang = wechsel.isEmpty ? aktuell : wechsel.first.alt;
  ProjektStatus? status =
      anfang == null || anfang == ProjektStatus.entwicklung
          ? ProjektStatus.entwicklung
          : null;
  final ergebnis = <String, ProjektStatus>{};
  for (final e in sortiert) {
    status = statusWechsel(e)?.neu ?? status;
    if (status != null) ergebnis[e.id] = status;
  }
  return ergebnis;
}

/// Ein Abschnitt des Phasenbands über den sichtbaren Einträgen: vom
/// ersten bis zum letzten Index (je einschließlich) gilt [status].
typedef PhasenAbschnitt = ({int von, int bis, ProjektStatus status});

/// Die Abschnitte des Phasenbands über [sichtbar] (in der Reihenfolge des
/// Zeitstrahls) — [phasen] sagt, welcher Status bei welchem Eintrag galt
/// (siehe [statusJeEintrag]). Ein Eintrag ohne Angabe bleibt in der Phase
/// davor; vor der ersten Angabe gibt es kein Band.
List<PhasenAbschnitt> phasenAbschnitte(
  List<ProjektEintrag> sichtbar,
  Map<String, ProjektStatus> phasen,
) {
  final abschnitte = <PhasenAbschnitt>[];
  for (var i = 0; i < sichtbar.length; i++) {
    final s = phasen[sichtbar[i].id] ?? abschnitte.lastOrNull?.status;
    if (s == null) continue;
    final letzter = abschnitte.lastOrNull;
    if (letzter != null && letzter.status == s) {
      abschnitte[abschnitte.length - 1] = (von: letzter.von, bis: i, status: s);
    } else {
      abschnitte.add((von: i, bis: i, status: s));
    }
  }
  return abschnitte;
}

/// Ein Stand zur Auswahl: „Frikadelle · Stand 2 · Muster für den Kunden".
typedef StandWahl = ({String versionId, String label});

/// Die Stände der [rezepturen] zur Auswahl — Rezepturen nach Namen, je
/// Rezeptur der neueste Stand zuerst; Entwürfe sind gekennzeichnet.
List<StandWahl> standWahlen(
  Iterable<Rezeptur> rezepturen,
  Iterable<RezepturVersion> versionen,
) {
  final liste = <StandWahl>[];
  for (final r in [...rezepturen]..sort((a, b) => nachName(a.name, b.name))) {
    final staende = versionen.where((v) => v.rezepturId == r.id).toList()
      ..sort((a, b) => b.nummer.compareTo(a.nummer));
    for (final v in staende) {
      final b = v.bezeichnung?.trim() ?? '';
      final entwurf = v.status == VersionStatus.entwurf;
      liste.add(
        (
          versionId: v.id,
          label: '${r.name} · Stand ${v.nummer}'
              '${b.isEmpty ? '' : ' · $b'}${entwurf ? ' (Entwurf)' : ''}',
        ),
      );
    }
  }
  return liste;
}

// ── Der Entwicklungsweg ───────────────────────────────────────────────

/// Ein Punkt auf dem Entwicklungsweg.
sealed class WegPunkt {
  const WegPunkt();
}

/// Der Anfang: die Idee und was vor dem ersten Stand geschah — etwa die
/// Anfrage per Mail.
class WegAnfang extends WegPunkt {
  const WegAnfang(this.eintraege);

  final List<ProjektEintrag> eintraege;
}

/// Eine Station: ein abgeschlossener Rezepturstand, dazu was ihn betrifft
/// — Einträge, die ihm zugeordnet sind, und solche, die nach ihm kamen,
/// bevor der nächste Stand fertig war.
class WegStation extends WegPunkt {
  const WegStation({
    required this.eintrag,
    required this.nummer,
    this.rueckmeldungen = const [],
  });

  /// Der Eintrag des Stands im Verlauf.
  final ProjektEintrag eintrag;

  /// Die wievielte Station: 1, 2, 3 …
  final int nummer;

  final List<ProjektEintrag> rueckmeldungen;

  String get versionId => eintrag.versionId!;
}

/// Ein Wechsel der Phase: Validierung, Produktion …
class WegPhase extends WegPunkt {
  const WegPhase({required this.eintrag, required this.status});

  final ProjektEintrag eintrag;
  final ProjektStatus status;
}

/// Ob [e] eine Station ist: ein Rezepturstand mit Bezug.
bool istStation(ProjektEintrag e) =>
    EintragArt.aus(e.art) == EintragArt.rezeptur && e.versionId != null;

/// Ordnet den Verlauf zum Entwicklungsweg: der Anfang, dann die Stationen
/// und Phasenwechsel in ihrer zeitlichen Folge. Jeder übrige Eintrag
/// gehört zur Station, der er zugeordnet ist — sonst zur letzten Station
/// davor, vor der ersten Station zum Anfang.
List<WegPunkt> entwicklungsweg(Iterable<ProjektEintrag> eintraege) {
  final sortiert = zeitlichSortiert(eintraege);
  // Je Stand ist der erste Eintrag die Station.
  final station = <String, ProjektEintrag>{};
  for (final e in sortiert) {
    if (istStation(e)) station.putIfAbsent(e.versionId!, () => e);
  }
  final zugehoerig = {for (final v in station.keys) v: <ProjektEintrag>[]};
  final anfang = <ProjektEintrag>[];
  final reihe = <Object>[];
  String? letzte;
  for (final e in sortiert) {
    if (istStation(e) && identical(station[e.versionId], e)) {
      reihe.add(e);
      letzte = e.versionId;
      continue;
    }
    final wechsel = statusWechsel(e);
    if (wechsel != null) {
      reihe.add(WegPhase(eintrag: e, status: wechsel.neu));
      continue;
    }
    final bezug = e.versionId;
    final ziel =
        bezug != null && zugehoerig.containsKey(bezug) ? bezug : letzte;
    if (ziel == null) {
      anfang.add(e);
    } else {
      zugehoerig[ziel]!.add(e);
    }
  }
  var nummer = 0;
  return [
    WegAnfang(anfang),
    for (final r in reihe)
      if (r is ProjektEintrag)
        WegStation(
          eintrag: r,
          nummer: ++nummer,
          rueckmeldungen: zugehoerig[r.versionId]!,
        )
      else if (r is WegPunkt)
        r,
  ];
}

/// Eine Kennzahl eines Stands mit ihrer Änderung zum vorigen Stand
/// derselben Rezeptur.
typedef WegKennzahl = ({String label, String wert, String? aenderung});

/// Die Kennzahlen eines Stands: Fleischanteil, Energie, Fett, Eiweiß und
/// Salz je 100 g — die Nährwerte gerundet wie auf dem Etikett. Mit
/// [vorher] die Änderung als „+1,2" / „−0,5" (null: unverändert).
List<WegKennzahl> wegKennzahlen(
  RezepturErgebnis neu, {
  RezepturErgebnis? vorher,
}) {
  String? differenz(double? a, double? b, {int nachkomma = 1}) {
    if (a == null || b == null) return null;
    final d = b - a;
    final text = Format.zahl(d.abs(), nachkomma: nachkomma);
    if (text == Format.zahl(0, nachkomma: nachkomma)) return null;
    return '${d > 0 ? '+' : '−'}$text';
  }

  WegKennzahl naehrstoff(Naehrstoff s, String label) {
    final b = naehrstoffWert(neu.je100g, s);
    final a = vorher == null ? null : naehrstoffWert(vorher.je100g, s);
    final gerundetA = naehrwertGerundet(s, a);
    final gerundetB = naehrwertGerundet(s, b);
    return (
      label: label,
      wert: '$gerundetB ${s.einheit}',
      aenderung: vorher == null || gerundetA == gerundetB
          ? null
          : differenz(a, b, nachkomma: s == Naehrstoff.energieKcal ? 0 : 1),
    );
  }

  return [
    (
      label: 'Fleischanteil',
      wert: '${Format.zahl(neu.fleischanteilProzent, nachkomma: 1)} %',
      aenderung: vorher == null
          ? null
          : differenz(vorher.fleischanteilProzent, neu.fleischanteilProzent),
    ),
    naehrstoff(Naehrstoff.energieKcal, 'Energie'),
    naehrstoff(Naehrstoff.fett, 'Fett'),
    naehrstoff(Naehrstoff.eiweiss, 'Eiweiß'),
    naehrstoff(Naehrstoff.salz, 'Salz'),
  ];
}
