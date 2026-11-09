import '../../../core/database/database.dart';
import '../daten/entwicklung_repository.dart' show nachName;
import '../projekte/gesamtprojekt_modell.dart';
import '../projekte/projekt_modell.dart';
import '../statistik/entwicklung_auswertung.dart' show kundeSchluessel;

// Die Kundenordner der Produktentwicklung: je Kunde seine Gesamtprojekte
// (mit ihren Mustern) und seine Projekte für sich. Erkannt wird ein Kunde
// wie im Kundenfilter der Statistik — ohne auf Groß- und Kleinschreibung
// zu achten.

/// Ein Kundenordner.
class KundenOrdner {
  const KundenOrdner({
    required this.schluessel,
    required this.name,
    required this.punkte,
    required this.zuletzt,
  });

  /// Woran der Kunde erkannt wird — null: der Ordner ohne Kunden.
  final String? schluessel;

  /// Der Kunde, wie er geschrieben steht — null: ohne Kunden.
  final String? name;

  /// Gesamtprojekte mit ihren Mustern und Projekte für sich — die in
  /// Arbeit zuerst, dann die in Produktion, zuletzt die ruhenden; jeweils
  /// das zuletzt bewegte vorn.
  final List<ListenPunkt> punkte;

  /// Wann sich im Ordner zuletzt etwas getan hat.
  final DateTime zuletzt;

  /// Zum Merken, ob er aufgeklappt ist.
  String get id => schluessel ?? '';

  /// Alle Projekte im Ordner — die Muster der Gesamtprojekte mit.
  List<EntwicklungsProjekt> get projekte => [
        for (final p in punkte)
          ...switch (p) {
            EinzelProjekt(:final projekt) => [projekt],
            GesamtGruppe(:final muster) => muster,
          },
      ];

  int _zaehle(bool Function(ProjektStatus) passt) =>
      projekte.where((p) => passt(ProjektStatus.aus(p.status))).length;

  /// Projekte in Entwicklung oder Validierung.
  int get inArbeit => _zaehle(
        (s) => s == ProjektStatus.entwicklung || s == ProjektStatus.validierung,
      );

  /// Projekte in Produktion — gelistet.
  int get gelistet => _zaehle((s) => s == ProjektStatus.produktion);

  /// „2 in Arbeit · 7 Projekte · 3 gelistet" — nur, was es gibt.
  String get zusammenfassung {
    final n = projekte.length;
    final anfragen = punkte.whereType<GesamtGruppe>().length;
    return [
      if (inArbeit > 0) '$inArbeit in Arbeit',
      n == 1 ? '1 Projekt' : '$n Projekte',
      if (anfragen > 0)
        anfragen == 1 ? '1 Gesamtprojekt' : '$anfragen Gesamtprojekte',
      if (gelistet > 0) '$gelistet gelistet',
    ].join(' · ');
  }
}

/// Der Rang eines Punkts im Ordner: in Arbeit (auch ein Gesamtprojekt
/// ohne Muster), in Produktion, ruhend.
int _rang(ListenPunkt p) {
  final status = switch (p) {
    EinzelProjekt(:final projekt) => [ProjektStatus.aus(projekt.status)],
    GesamtGruppe(:final muster) => [
        for (final m in muster) ProjektStatus.aus(m.status),
      ],
  };
  if (status.isEmpty) return 0;
  if (status.any(
    (s) => s == ProjektStatus.entwicklung || s == ProjektStatus.validierung,
  )) {
    return 0;
  }
  if (status.contains(ProjektStatus.produktion)) return 1;
  return 2;
}

/// Die Kundenordner: je Kunde einer, nach Namen, zuletzt der für alles
/// ohne Kunden. Ein Gesamtprojekt steht beim Kunden des Gesamtprojekts,
/// mit allen seinen Mustern. [aktivitaet] (je Projekt) ordnet innerhalb
/// eines Ordners; ohne sie zählt die letzte Änderung.
///
/// [suche] trifft Kunde, Projekt (Name, Artikelnummer) und Gesamtprojekt
/// (Name, Anfrage) — ein Ordner erscheint dann mit den Treffern.
List<KundenOrdner> kundenOrdner({
  required List<EntwicklungsProjekt> projekte,
  required List<Gesamtprojekt> gesamtprojekte,
  Map<String, DateTime> aktivitaet = const {},
  String suche = '',
}) {
  final punkte = projektListe(
    projekte: projekte,
    gesamtprojekte: gesamtprojekte,
    passt: (_) => true,
    leerPasst: true,
    suche: suche,
  );
  DateTime wann(ListenPunkt p) => switch (p) {
        EinzelProjekt(:final projekt) =>
          aktivitaet[projekt.id] ?? projekt.updatedAt,
        GesamtGruppe(:final gesamtprojekt, :final muster) => [
            gesamtprojektZuletzt(gesamtprojekt, muster),
            for (final m in muster)
              if (aktivitaet[m.id] case final a?) a,
          ].reduce((a, b) => a.isAfter(b) ? a : b),
      };

  final namen = <String?, String?>{};
  final jeKunde = <String?, List<ListenPunkt>>{};
  for (final p in punkte) {
    final kunde = switch (p) {
      EinzelProjekt(:final projekt) => projekt.kunde,
      GesamtGruppe(:final gesamtprojekt) => gesamtprojekt.kunde,
    };
    final k = kundeSchluessel(kunde);
    namen.putIfAbsent(k, () => kunde?.trim());
    (jeKunde[k] ??= []).add(
      // Mit Suche nur die Muster, die sie trifft.
      switch (p) {
        GesamtGruppe(:final gesamtprojekt, :final muster, :final sichtbar)
            when sichtbar.length != muster.length && suche.trim().isNotEmpty =>
          GesamtGruppe(
            gesamtprojekt: gesamtprojekt,
            muster: sichtbar,
            sichtbar: sichtbar,
          ),
        _ => p,
      },
    );
  }

  final ordner = [
    for (final MapEntry(key: k, value: liste) in jeKunde.entries)
      KundenOrdner(
        schluessel: k,
        name: namen[k],
        punkte: liste
          ..sort((a, b) {
            final r = _rang(a).compareTo(_rang(b));
            return r != 0 ? r : wann(b).compareTo(wann(a));
          }),
        zuletzt: liste.map(wann).reduce((a, b) => a.isAfter(b) ? a : b),
      ),
  ];
  ordner.sort((a, b) {
    if (a.name == null) return b.name == null ? 0 : 1;
    if (b.name == null) return -1;
    return nachName(a.name!, b.name!);
  });
  return ordner;
}
