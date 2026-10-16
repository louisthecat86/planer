import '../../core/database/database.dart';
import '../whiteboard/whiteboard_provider.dart'
    show leistungsdatenVon, produktionsMinutenVon, verlustAnteilVon;

/// Was an einem Artikel fehlt, damit die Planung richtig rechnet — und
/// was daraus folgt.
///
/// Statistik und Artikelliste zählen nach genau diesen Regeln: Die Zahl,
/// die die Statistik nennt, ist die Länge der Liste, die ein Klick darauf
/// öffnet. Die Regeln selbst sind die der Planung ([verlustAnteilVon],
/// [produktionsMinutenVon], [leistungsdatenVon]).
enum ArtikelLuecke {
  nichtEingepflegt(
    'Nicht eingepflegt',
    'Aus Navision angelegt, die Artikelmaske ist noch nicht ausgefüllt.',
  ),
  ohneProduktgruppe(
    'Ohne Produktgruppe',
    'Fehlt im Produktmix der Statistik und bei den Merkmalen der Gruppe.',
  ),
  ohneSchritte(
    'Ohne Prozessschritte',
    'Ohne Schritte kennt die Planung keine Abteilungen — der Artikel '
        'lässt sich nicht planen.',
  ),
  ohneAusbeute(
    'Ohne Ausbeute',
    'Keine erfasste Produktion mit Fertigware: Die Planung rechnet ohne '
        'Verlust, solange im Planen-Fenster keiner eingetragen wird.',
  ),
  zeitPlatzhalter(
    'Zeit nur Platzhalter',
    'Weder Leistungsdaten noch Produktionen mit Zeit: Die Planung setzt '
        'für die Abteilung 30 Minuten an.',
  );

  const ArtikelLuecke(this.titel, this.folge);

  /// Kurzer Name, etwa für Filter und Zeilen.
  final String titel;

  /// Was die Lücke für die Planung bedeutet.
  final String folge;
}

/// Was die erfassten Produktionen eines Artikels der Planung liefern.
class ProduktionsGrundlage {
  const ProduktionsGrundlage({
    this.mitAusbeute = false,
    this.mitZeit = false,
  });

  /// Mindestens eine Produktion mit plausibler Ausbeute.
  final bool mitAusbeute;

  /// Mindestens eine Produktion mit Rohware und Produktionszeit.
  final bool mitZeit;
}

/// Je Artikel, ob seine erfassten Produktionen eine Ausbeute und eine Zeit
/// liefern — nach denselben Regeln wie die Planung. Gelöschte zählen nicht.
Map<String, ProduktionsGrundlage> produktionsGrundlagen(
  Iterable<ProductionHistoryData> historie,
) {
  final mitAusbeute = <String>{};
  final mitZeit = <String>{};
  for (final h in historie) {
    if (h.deletedAt != null) continue;
    if (verlustAnteilVon(h) != null) mitAusbeute.add(h.productId);
    final kg = h.kgRohware;
    if (kg != null && kg.isFinite && kg > 0) {
      if (produktionsMinutenVon(h, kg) != null) mitZeit.add(h.productId);
    }
  }
  return {
    for (final id in {...mitAusbeute, ...mitZeit})
      id: ProduktionsGrundlage(
        mitAusbeute: mitAusbeute.contains(id),
        mitZeit: mitZeit.contains(id),
      ),
  };
}

/// Die Lücken des Artikels [produkt] mit seinen (nicht gelöschten)
/// [schritte]n und der [grundlage] aus seinen Produktionen.
Set<ArtikelLuecke> artikelLuecken(
  Product produkt,
  List<ProductStep> schritte,
  ProduktionsGrundlage? grundlage,
) {
  final g = grundlage ?? const ProduktionsGrundlage();
  return {
    if (!produkt.istEingepflegt) ArtikelLuecke.nichtEingepflegt,
    if ((produkt.produktgruppe ?? '').trim().isEmpty)
      ArtikelLuecke.ohneProduktgruppe,
    if (schritte.isEmpty) ArtikelLuecke.ohneSchritte,
    if (!g.mitAusbeute) ArtikelLuecke.ohneAusbeute,
    // Die Planung nimmt je Abteilung erst die Leistungsdaten, dann die
    // Zeit der letzten Produktionen (an der Bratstraße umgekehrt). Fehlt
    // beides, setzt sie einen Platzhalter.
    if (schritte.isNotEmpty && !g.mitZeit && _abteilungOhneLeistung(schritte))
      ArtikelLuecke.zeitPlatzhalter,
  };
}

/// Ob ein Abteilungsblock — aufeinanderfolgende Schritte derselben
/// Abteilung, wie in der Planung — ohne Leistungsdaten ist.
bool _abteilungOhneLeistung(List<ProductStep> schritte) {
  final sortiert = [...schritte]
    ..sort((a, b) => a.reihenfolge.compareTo(b.reihenfolge));
  var i = 0;
  while (i < sortiert.length) {
    final abteilung = sortiert[i].abteilung;
    final block = <ProductStep>[];
    while (i < sortiert.length && sortiert[i].abteilung == abteilung) {
      block.add(sortiert[i]);
      i++;
    }
    if (leistungsdatenVon(block) == null) return true;
  }
  return false;
}
