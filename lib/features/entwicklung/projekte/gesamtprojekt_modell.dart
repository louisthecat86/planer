import '../../../core/database/database.dart';
import 'entwicklungsstrang.dart';
import 'projekt_modell.dart';

// Gesamtprojekte mit Mustern — die reinen Regeln: wie Muster heißen, wie
// sich ihr Stand zusammenfassen lässt und wie die Verläufe von
// Gesamtprojekt und Muster ineinandergreifen.
//
// Ein Gesamtprojekt sammelt, was alle Muster betrifft (Korrespondenz,
// Unterlagen). Der Verlauf eines Musters zeigt dessen Einträge mit,
// gekennzeichnet; der Verlauf des Gesamtprojekts zeigt die Meilensteine
// der Muster mit, gekennzeichnet mit ihrem Namen.

/// So ist ein Eintrag aus dem Gesamtprojekt im Verlauf eines Musters
/// gekennzeichnet.
const String kHerkunftGesamtprojekt = 'Gesamtprojekt';

/// Die Namen neuer Muster: Ein leerer Name wird „Muster 1", „Muster 2" …
/// nach seiner Stelle.
List<String> musterNamen(List<String> eingaben) => [
      for (final (i, n) in eingaben.indexed)
        n.trim().isEmpty ? 'Muster ${i + 1}' : n.trim(),
    ];

/// Die Namen der Anhänge, die ein Mail-Eintrag nennt — aus Zeilen wie
/// „Anhang: Angebot (2).pdf (12 KB)".
List<String> mailAnhangNamen(List<String> aenderungen) => [
      for (final z in aenderungen)
        if (RegExp(r'^Anhang: (.+) \([^()]*\)$').firstMatch(z.trim())
            case final m?)
          m.group(1)!.trim(),
    ];

/// Wie ein Muster in seiner Phase in der Zusammenfassung heißt.
String _phaseKlein(ProjektStatus s) => switch (s) {
      ProjektStatus.entwicklung => 'in Entwicklung',
      ProjektStatus.validierung => 'in Validierung',
      ProjektStatus.produktion => 'in Produktion',
      ProjektStatus.eingestellt => 'nicht weiter verfolgt',
      ProjektStatus.archiviert => 'archiviert',
    };

/// „5 Muster: 2 in Entwicklung, 1 in Produktion, 2 nicht weiter verfolgt"
/// — „Noch keine Muster", wenn es keine gibt.
String musterZusammenfassung(Iterable<ProjektStatus> status) {
  final liste = status.toList();
  if (liste.isEmpty) return 'Noch keine Muster';
  final teile = [
    for (final s in ProjektStatus.values)
      if (liste.where((x) => x == s).length case final n when n > 0)
        '$n ${_phaseKlein(s)}',
  ];
  return '${liste.length} Muster: ${teile.join(', ')}';
}

/// Wann sich am Gesamtprojekt oder einem seiner Muster zuletzt etwas
/// getan hat.
DateTime gesamtprojektZuletzt(
  Gesamtprojekt g,
  Iterable<EntwicklungsProjekt> muster,
) {
  var zuletzt = g.updatedAt;
  for (final m in muster) {
    if (m.updatedAt.isAfter(zuletzt)) zuletzt = m.updatedAt;
  }
  return zuletzt;
}

/// Ob ein Gesamtprojekt bei dem Filter [passt] (auf den Status eines
/// Musters) erscheint: Eines seiner Muster passt — oder es hat noch keine
/// und der Filter zeigt die laufenden Projekte ([leerPasst]).
bool gesamtprojektPasst(
  Iterable<EntwicklungsProjekt> muster,
  bool Function(ProjektStatus) passt, {
  required bool leerPasst,
}) {
  if (muster.isEmpty) return leerPasst;
  return muster.any((m) => passt(ProjektStatus.aus(m.status)));
}

/// Ein Verlauf aus mehreren Quellen: die Einträge, der neueste zuerst,
/// und je Eintrag, der nicht aus dem eigenen Verlauf stammt, woher er
/// kommt.
typedef ZusammenVerlauf = ({
  List<ProjektEintrag> eintraege,
  Map<String, String> herkunft,
});

/// Der neueste zuerst; bei gleichem Datum der später angelegte.
List<ProjektEintrag> _neuesteZuerst(Iterable<ProjektEintrag> eintraege) =>
    [...eintraege]..sort((a, b) {
        final d = b.datum.compareTo(a.datum);
        return d != 0 ? d : b.createdAt.compareTo(a.createdAt);
      });

/// Der Verlauf eines Musters: seine [eigenen] Einträge und — mit
/// [mitGesamtprojekt] — die seines Gesamtprojekts, gekennzeichnet als
/// [kHerkunftGesamtprojekt].
ZusammenVerlauf musterVerlauf(
  List<ProjektEintrag> eigene,
  List<ProjektEintrag> gesamtprojekt, {
  bool mitGesamtprojekt = true,
}) {
  if (!mitGesamtprojekt || gesamtprojekt.isEmpty) {
    return (eintraege: eigene, herkunft: const {});
  }
  return (
    eintraege: _neuesteZuerst([...eigene, ...gesamtprojekt]),
    herkunft: {for (final e in gesamtprojekt) e.id: kHerkunftGesamtprojekt},
  );
}

/// Der Verlauf eines Gesamtprojekts: seine [eigenen] Einträge und — mit
/// [mitMustern] — die Meilensteine seiner [muster] (aus [alle], den
/// Einträgen aller Projekte), gekennzeichnet mit dem Namen des Musters.
ZusammenVerlauf gesamtprojektVerlauf(
  List<ProjektEintrag> eigene,
  List<EntwicklungsProjekt> muster,
  List<ProjektEintrag> alle, {
  bool mitMustern = true,
}) {
  final namen = {for (final m in muster) m.id: m.name};
  final meilensteine = !mitMustern
      ? const <ProjektEintrag>[]
      : [
          for (final e in alle)
            if (namen.containsKey(e.projektId) &&
                EintragArt.aus(e.art) == EintragArt.meilenstein)
              e,
        ];
  return (
    eintraege: _neuesteZuerst([...eigene, ...meilensteine]),
    herkunft: {for (final e in meilensteine) e.id: namen[e.projektId]!},
  );
}

/// Wohin sich ein Eintrag oder eine Datei verschieben lässt: das
/// Gesamtprojekt oder eines seiner Muster.
typedef VerschiebeZiel = ({String id, String name, bool gesamtprojekt});

/// Die Ziele zum Verschieben innerhalb des Gesamtprojekts [g]: es selbst
/// und seine [muster], in dieser Reihenfolge. Ohne Gesamtprojekt keine.
List<VerschiebeZiel> verschiebeZiele(
  Gesamtprojekt? g,
  List<EntwicklungsProjekt> muster,
) =>
    g == null
        ? const []
        : [
            (id: g.id, name: g.name, gesamtprojekt: true),
            for (final m in muster)
              (id: m.id, name: m.name, gesamtprojekt: false),
          ];

/// Warum ein Projekt nicht weiter verfolgt wird — aus dem Meilenstein, mit
/// dem es dorthin kam („Grund: …"). Null, wenn es gerade nicht dort steht
/// oder kein Grund genannt ist.
String? nichtWeiterGrund(Iterable<ProjektEintrag> eintraege) {
  for (final e in zeitlichSortiert(eintraege).reversed) {
    final w = statusWechsel(e);
    if (w == null) continue;
    if (w.neu != ProjektStatus.eingestellt) return null;
    for (final z in (e.beschreibung ?? '').split('\n')) {
      if (z.startsWith('Grund: ')) return z.substring(7).trim();
    }
    return null;
  }
  return null;
}

// ── Die Projektliste ──────────────────────────────────────────────────

/// Ein Eintrag der Projektliste: ein Gesamtprojekt mit seinen Mustern
/// oder ein Projekt für sich.
sealed class ListenPunkt {
  const ListenPunkt();

  /// Wann sich zuletzt etwas getan hat — danach ist die Liste geordnet.
  DateTime get zuletzt;
}

/// Ein Projekt für sich.
class EinzelProjekt extends ListenPunkt {
  const EinzelProjekt(this.projekt);

  final EntwicklungsProjekt projekt;

  @override
  DateTime get zuletzt => projekt.updatedAt;
}

/// Ein Gesamtprojekt mit seinen Mustern.
class GesamtGruppe extends ListenPunkt {
  const GesamtGruppe({
    required this.gesamtprojekt,
    required this.muster,
    required this.sichtbar,
  });

  final Gesamtprojekt gesamtprojekt;

  /// Alle Muster, in der Reihenfolge des Anlegens — für die
  /// Zusammenfassung.
  final List<EntwicklungsProjekt> muster;

  /// Die Muster, die Filter und Suche zeigen.
  final List<EntwicklungsProjekt> sichtbar;

  @override
  DateTime get zuletzt => gesamtprojektZuletzt(gesamtprojekt, muster);
}

/// Ob [text] den Suchbegriff [q] (klein geschrieben) enthält.
bool _trifft(String? text, String q) =>
    (text ?? '').toLowerCase().contains(q);

/// Die Projektliste: Gesamtprojekte mit ihren Mustern und Projekte für
/// sich, das zuletzt bewegte zuerst.
///
/// Ein Muster erscheint, wenn sein Status zu [passt] gehört und es — oder
/// sein Gesamtprojekt — die [suche] trifft (Name, Kunde, Artikelnummer;
/// beim Gesamtprojekt auch die Anfrage). Ein Gesamtprojekt erscheint mit
/// den Mustern, die erscheinen; ohne Muster nur mit [leerPasst]. Ein
/// Muster, dessen Gesamtprojekt es nicht mehr gibt, steht für sich.
List<ListenPunkt> projektListe({
  required List<EntwicklungsProjekt> projekte,
  required List<Gesamtprojekt> gesamtprojekte,
  required bool Function(ProjektStatus) passt,
  required bool leerPasst,
  String suche = '',
}) {
  final q = suche.trim().toLowerCase();
  bool projektTrifft(EntwicklungsProjekt p) =>
      q.isEmpty ||
      _trifft(p.name, q) ||
      _trifft(p.kunde, q) ||
      _trifft(p.artikelnummer, q);
  final gruppen = {
    for (final g in gesamtprojekte)
      if (g.deletedAt == null) g.id: g,
  };
  final jeGruppe = {for (final id in gruppen.keys) id: <EntwicklungsProjekt>[]};
  final punkte = <ListenPunkt>[];
  for (final p in projekte) {
    if (p.deletedAt != null) continue;
    final liste = jeGruppe[p.gesamtprojektId];
    if (liste != null) {
      liste.add(p);
    } else if (passt(ProjektStatus.aus(p.status)) && projektTrifft(p)) {
      punkte.add(EinzelProjekt(p));
    }
  }
  for (final MapEntry(key: id, value: muster) in jeGruppe.entries) {
    final g = gruppen[id]!;
    muster.sort((a, b) {
      final c = a.createdAt.compareTo(b.createdAt);
      return c != 0 ? c : a.name.compareTo(b.name);
    });
    final gTrifft = q.isEmpty ||
        _trifft(g.name, q) ||
        _trifft(g.kunde, q) ||
        _trifft(g.anfrage, q);
    final sichtbar = [
      for (final m in muster)
        if (passt(ProjektStatus.aus(m.status)) && (gTrifft || projektTrifft(m)))
          m,
    ];
    if (sichtbar.isNotEmpty || (muster.isEmpty && leerPasst && gTrifft)) {
      punkte.add(
        GesamtGruppe(gesamtprojekt: g, muster: muster, sichtbar: sichtbar),
      );
    }
  }
  punkte.sort((a, b) => b.zuletzt.compareTo(a.zuletzt));
  return punkte;
}
