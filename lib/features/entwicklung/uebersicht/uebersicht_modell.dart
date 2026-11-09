import 'dart:math' as math;

import '../../../core/database/database.dart';
import '../../../core/utils/format.dart';
import '../daten/entwicklung_repository.dart' show VersionStatus, nachName;
import '../projekte/faellig.dart';
import '../projekte/projekt_checkliste.dart';
import '../projekte/projekt_modell.dart';
import '../statistik/entwicklung_auswertung.dart';
import '../werkzeuge/entwicklung_statistik.dart' show kRuhendNachTagen;

// Was die Übersicht der Produktentwicklung rechnet: wann sich an einem
// Projekt zuletzt etwas getan hat, welche Projekte oben stehen, was ein
// Projekt kurz über sich sagt, was ansteht, die Zahlen der Kacheln und
// die Suche. Alles ohne Datenbank — die Listen kommen aus den Providern.

/// Wie weit „Was ansteht" nach vorn schaut, in Tagen.
const int kBaldFaelligTage = 14;

DateTime _tag(DateTime d) => DateTime(d.year, d.month, d.day);

/// Ob ein Projekt in Arbeit ist — in Entwicklung oder Validierung.
bool istInArbeit(ProjektStatus s) =>
    s == ProjektStatus.entwicklung || s == ProjektStatus.validierung;

/// „heute", „gestern", „vor 3 Tagen" — ab zwei Wochen das Datum.
String vorWieLange(DateTime am, DateTime heute) {
  final tage = tageZwischen(am, heute);
  if (tage <= 0) return 'heute';
  if (tage == 1) return 'gestern';
  if (tage < 14) return 'vor $tage Tagen';
  return Format.datum(am);
}

/// „heute", „morgen", sonst „Do 12.11.".
String faelligText(DateTime am, DateTime heute) {
  final tage = tageZwischen(heute, am);
  if (tage == 0) return 'heute';
  if (tage == 1) return 'morgen';
  return Format.tagKurz(am);
}

// ── Aktivität ─────────────────────────────────────────────────────────

/// Wann sich an jedem Projekt (ID) zuletzt etwas getan hat: am Projekt
/// selbst, in seinem Verlauf, an seinen Rezepturen, ihren Ständen und —
/// aus [zeilen] — an deren Zeilen.
Map<String, DateTime> projektAktivitaet({
  required Iterable<EntwicklungsProjekt> projekte,
  Iterable<ProjektEintrag> eintraege = const [],
  Iterable<Rezeptur> rezepturen = const [],
  Iterable<RezepturVersion> versionen = const [],
  Map<String, DateTime> zeilen = const {},
}) {
  final zuletzt = {for (final p in projekte) p.id: p.updatedAt};
  void merke(String? id, DateTime am) {
    final bisher = zuletzt[id];
    if (id != null && bisher != null && am.isAfter(bisher)) {
      zuletzt[id] = am;
    }
  }

  for (final e in eintraege) {
    merke(e.projektId, e.updatedAt);
  }
  final projektVon = <String, String>{};
  for (final r in rezepturen) {
    final pid = r.projektId;
    if (pid == null) continue;
    projektVon[r.id] = pid;
    merke(pid, r.updatedAt);
  }
  for (final v in versionen) {
    merke(projektVon[v.rezepturId], v.updatedAt);
  }
  for (final MapEntry(:key, :value) in zeilen.entries) {
    merke(key, value);
  }
  return zuletzt;
}

/// Die Projekte für „Zuletzt bearbeitet": die angehefteten, dann die in
/// Arbeit mit der jüngsten Aktivität — bis es [anzahl] sind. Angeheftete
/// stehen immer da, auch wenn es mehr als [anzahl] sind.
List<EntwicklungsProjekt> zuletztBearbeitet({
  required Iterable<EntwicklungsProjekt> projekte,
  required Map<String, DateTime> aktivitaet,
  Iterable<String> angeheftet = const [],
  int anzahl = 5,
}) {
  final an = angeheftet.toSet();
  DateTime wann(EntwicklungsProjekt p) => aktivitaet[p.id] ?? p.updatedAt;
  int neuesteZuerst(EntwicklungsProjekt a, EntwicklungsProjekt b) =>
      wann(b).compareTo(wann(a));
  final oben = [
    for (final p in projekte)
      if (p.deletedAt == null && an.contains(p.id)) p,
  ]..sort(neuesteZuerst);
  final aktive = [
    for (final p in projekte)
      if (p.deletedAt == null &&
          !an.contains(p.id) &&
          istInArbeit(ProjektStatus.aus(p.status)))
        p,
  ]..sort(neuesteZuerst);
  return [...oben, ...aktive.take(math.max(0, anzahl - oben.length))];
}

// ── Was ein Projekt kurz über sich sagt ───────────────────────────────

/// Wovon ein Hinweis spricht — danach Symbol und Farbe.
enum HinweisArt {
  /// Ein offener Eintrag ist über seinen Tag.
  ueberfaellig,

  /// Seit [kRuhendNachTagen] Tagen hat sich nichts getan.
  ruht,

  /// Der nächste offene Punkt der Checkliste.
  naechster,

  /// Die Checkliste ist erledigt.
  erledigt,

  /// Ein offener Eintrag wird bald fällig.
  faellig,

  /// Ein Rezepturstand ist in Arbeit.
  entwurf,
}

/// Ein Satz über ein Projekt.
typedef ProjektHinweis = ({String text, HinweisArt art});

/// Ein offener Eintrag mit dem Tag, an dem er fällig ist.
typedef _MitTag = ({ProjektEintrag eintrag, DateTime am});

/// Die offenen unter [eintraege], deren „Fällig bis" sich als Tag lesen
/// lässt — der früheste zuerst.
List<_MitTag> _offenMitTag(Iterable<ProjektEintrag> eintraege) => [
      for (final e in eintraege)
        if (EintragStatus.aus(e.status) == EintragStatus.offen)
          if (faelligAm(e.ziel, bezug: e.datum) case final am?)
            (eintrag: e, am: am),
    ]..sort((a, b) => a.am.compareTo(b.am));

/// Was einem Projekt fehlt oder ansteht, das Wichtigste zuerst:
/// überfällige Einträge, ob es ruht, was als Nächstes zu tun ist, was
/// bald fällig ist und ein Rezepturstand in Arbeit. [eintraege] sind die
/// des Projekts, [entwuerfe] die Entwürfe seiner Rezepturen, [zuletzt]
/// seine letzte Aktivität. Ein ruhendes Projekt sagt nichts — das zeigt
/// sein Status.
List<ProjektHinweis> projektHinweise({
  required EntwicklungsProjekt projekt,
  required DateTime zuletzt,
  required DateTime heute,
  ProjektCheckStand? checkliste,
  Iterable<ProjektEintrag> eintraege = const [],
  Iterable<RezepturVersion> entwuerfe = const [],
}) {
  final status = ProjektStatus.aus(projekt.status);
  if (status.ruht) return const [];
  final tag = _tag(heute);
  final mitTag = _offenMitTag(eintraege);
  final hinweise = <ProjektHinweis>[];

  final ueber = [
    for (final x in mitTag)
      if (x.am.isBefore(tag)) x,
  ];
  if (ueber.isNotEmpty) {
    final erster = ueber.first;
    hinweise.add(
      (
        text: ueber.length == 1
            ? 'Überfällig seit ${Format.datumKurz(erster.am)}: '
                '${erster.eintrag.titel}'
            : '${ueber.length} Einträge überfällig, zuerst: '
                '${erster.eintrag.titel}',
        art: HinweisArt.ueberfaellig,
      ),
    );
  }

  if (istInArbeit(status)) {
    final tage = tageZwischen(zuletzt, heute);
    if (tage >= kRuhendNachTagen) {
      hinweise
          .add((text: 'Seit $tage Tagen nichts getan', art: HinweisArt.ruht));
    }
  }

  final naechster = checkliste?.naechster;
  if (naechster != null) {
    hinweise.add(
      (
        text: 'Als Nächstes: ${checkAufgabe(naechster)}',
        art: HinweisArt.naechster,
      ),
    );
  } else if (checkliste != null && checkliste.fertig) {
    hinweise.add((text: 'Checkliste erledigt', art: HinweisArt.erledigt));
  }

  final bald = [
    for (final x in mitTag)
      if (!x.am.isBefore(tag) && tageZwischen(heute, x.am) <= kBaldFaelligTage)
        x,
  ];
  if (bald.isNotEmpty) {
    final b = bald.first;
    hinweise.add(
      (
        text: 'Fällig ${faelligText(b.am, heute)}: ${b.eintrag.titel}',
        art: HinweisArt.faellig,
      ),
    );
  }

  RezepturVersion? entwurf;
  for (final v in entwuerfe) {
    if (v.status != VersionStatus.entwurf) continue;
    if (entwurf == null || v.nummer > entwurf.nummer) entwurf = v;
  }
  if (entwurf != null) {
    hinweise.add(
      (text: 'Stand ${entwurf.nummer} in Arbeit', art: HinweisArt.entwurf),
    );
  }
  return hinweise;
}

// ── Was ansteht ───────────────────────────────────────────────────────

/// Ein offener Eintrag mit Tag — in einem Projekt oder Gesamtprojekt.
class FaelligerEintrag {
  const FaelligerEintrag({
    required this.eintrag,
    required this.am,
    required this.ueberfaellig,
    required this.zielId,
    required this.zielName,
    this.gesamtprojekt = false,
  });

  final ProjektEintrag eintrag;

  /// Der Tag aus „Fällig bis".
  final DateTime am;
  final bool ueberfaellig;

  /// Projekt oder Gesamtprojekt, zu dem der Eintrag gehört.
  final String zielId;
  final String zielName;
  final bool gesamtprojekt;
}

/// Was ansteht: offene Einträge mit Tag, die überfällig sind oder in den
/// nächsten [tage] Tagen fällig werden — der früheste zuerst, also die
/// überfälligen vorn. Einträge ruhender und gelöschter Projekte fehlen.
List<FaelligerEintrag> faelligeEintraege({
  required Iterable<ProjektEintrag> eintraege,
  required Iterable<EntwicklungsProjekt> projekte,
  required DateTime heute,
  Iterable<Gesamtprojekt> gesamtprojekte = const [],
  int tage = kBaldFaelligTage,
}) {
  final tag = _tag(heute);
  final ziele = <String, ({String name, bool gesamt})>{
    for (final p in projekte)
      if (p.deletedAt == null && !ProjektStatus.aus(p.status).ruht)
        p.id: (name: p.name, gesamt: false),
    for (final g in gesamtprojekte)
      if (g.deletedAt == null) g.id: (name: g.name, gesamt: true),
  };
  return [
    for (final x in _offenMitTag(eintraege))
      if (ziele[x.eintrag.projektId] case final z?)
        if (tageZwischen(heute, x.am) <= tage)
          FaelligerEintrag(
            eintrag: x.eintrag,
            am: x.am,
            ueberfaellig: x.am.isBefore(tag),
            zielId: x.eintrag.projektId,
            zielName: z.name,
            gesamtprojekt: z.gesamt,
          ),
  ];
}

/// Ein Projekt in Arbeit, an dem sich lange nichts getan hat.
typedef RuhendesProjekt = ({EntwicklungsProjekt projekt, int tage});

/// Projekte in Arbeit, an denen sich seit [kRuhendNachTagen] Tagen nichts
/// getan hat — das am längsten ruhende zuerst.
List<RuhendesProjekt> ruhendeProjekte({
  required Iterable<EntwicklungsProjekt> projekte,
  required Map<String, DateTime> aktivitaet,
  required DateTime heute,
}) {
  return [
    for (final p in projekte)
      if (p.deletedAt == null && istInArbeit(ProjektStatus.aus(p.status)))
        if (tageZwischen(aktivitaet[p.id] ?? p.updatedAt, heute) case final t
            when t >= kRuhendNachTagen)
          (projekt: p, tage: t),
  ]..sort((a, b) => b.tage.compareTo(a.tage));
}

// ── Die Kacheln ───────────────────────────────────────────────────────

/// Die Zahlen der Kacheln oben auf der Übersicht.
class UebersichtZahlen {
  const UebersichtZahlen({
    required this.inArbeit,
    required this.inValidierung,
    required this.ueberfaellig,
    required this.offen,
    required this.ruhend,
    required this.gelistet,
    required this.jahr,
  });

  /// Projekte in Entwicklung oder Validierung …
  final int inArbeit;

  /// … davon in Validierung.
  final int inValidierung;

  /// Offene Einträge, die überfällig sind …
  final int ueberfaellig;

  /// … von allen offenen Einträgen.
  final int offen;

  /// Projekte in Arbeit, an denen sich lange nichts getan hat.
  final int ruhend;

  /// Im laufenden [jahr] gelistet — gezählt wie in der Statistik.
  final int gelistet;
  final int jahr;
}

/// Rechnet die Kacheln aus den Listen.
UebersichtZahlen uebersichtZahlen({
  required List<EntwicklungsProjekt> projekte,
  required List<Gesamtprojekt> gesamtprojekte,
  required List<ProjektEintrag> eintraege,
  required Map<String, DateTime> aktivitaet,
  required DateTime heute,
  List<Rezeptur> rezepturen = const [],
  List<RezepturVersion> versionen = const [],
}) {
  var inArbeit = 0;
  var inValidierung = 0;
  for (final p in projekte) {
    final s = ProjektStatus.aus(p.status);
    if (p.deletedAt != null || !istInArbeit(s)) continue;
    inArbeit++;
    if (s == ProjektStatus.validierung) inValidierung++;
  }
  // Offen zählt, was nicht in einem ruhenden oder gelöschten Projekt
  // steht — wie bei „Was ansteht".
  final zaehlen = {
    for (final p in projekte)
      if (p.deletedAt == null && !ProjektStatus.aus(p.status).ruht) p.id,
    for (final g in gesamtprojekte)
      if (g.deletedAt == null) g.id,
  };
  final offen = offeneZaehlen(
    [
      for (final e in eintraege)
        if (zaehlen.contains(e.projektId)) e,
    ],
    heute: heute,
  );
  final jahr = entwicklungAuswerten(
    laeufe: musterLaeufe(
      projekte: projekte,
      gesamtprojekte: gesamtprojekte,
      eintraege: eintraege,
      rezepturen: rezepturen,
      versionen: versionen,
    ),
    zeitraum: Zeitraum.jahr(heute.year),
    heute: heute,
    gesamtprojekte: gesamtprojekte,
  );
  return UebersichtZahlen(
    inArbeit: inArbeit,
    inValidierung: inValidierung,
    ueberfaellig: offen.ueberfaellig,
    offen: offen.offen,
    ruhend: ruhendeProjekte(
      projekte: projekte,
      aktivitaet: aktivitaet,
      heute: heute,
    ).length,
    gelistet: jahr.zahlen.gelistet,
    jahr: heute.year,
  );
}

// ── Suche ─────────────────────────────────────────────────────────────

/// Was die Suche auf der Übersicht findet.
typedef UebersichtTreffer = ({
  List<EntwicklungsProjekt> projekte,
  List<Gesamtprojekt> gesamtprojekte,
  List<Rezeptur> rezepturen,
});

/// Sucht [suche] in Projekten (Name, Kunde, Artikelnummer),
/// Gesamtprojekten (Name, Kunde, Anfrage) und Rezepturen (Name,
/// Artikelnummer) — Projekte nach ihrer letzten Aktivität, der Rest nach
/// Namen; je Art höchstens [hoechstens].
UebersichtTreffer uebersichtSuchen(
  String suche, {
  required Iterable<EntwicklungsProjekt> projekte,
  Iterable<Gesamtprojekt> gesamtprojekte = const [],
  Iterable<Rezeptur> rezepturen = const [],
  Map<String, DateTime> aktivitaet = const {},
  int hoechstens = 30,
}) {
  final q = suche.trim().toLowerCase();
  bool trifft(String? text) =>
      q.isNotEmpty && (text ?? '').toLowerCase().contains(q);
  final p = [
    for (final x in projekte)
      if (x.deletedAt == null &&
          (trifft(x.name) || trifft(x.kunde) || trifft(x.artikelnummer)))
        x,
  ]..sort(
      (a, b) => (aktivitaet[b.id] ?? b.updatedAt)
          .compareTo(aktivitaet[a.id] ?? a.updatedAt),
    );
  final g = [
    for (final x in gesamtprojekte)
      if (x.deletedAt == null &&
          (trifft(x.name) || trifft(x.kunde) || trifft(x.anfrage)))
        x,
  ]..sort((a, b) => nachName(a.name, b.name));
  final r = [
    for (final x in rezepturen)
      if (x.deletedAt == null && (trifft(x.name) || trifft(x.artikelnummer))) x,
  ]..sort((a, b) => nachName(a.name, b.name));
  return (
    projekte: p.take(hoechstens).toList(),
    gesamtprojekte: g.take(hoechstens).toList(),
    rezepturen: r.take(hoechstens).toList(),
  );
}
