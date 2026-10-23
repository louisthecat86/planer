import '../../../core/database/database.dart';
import '../spezifikation/spez_angaben.dart';
import 'projekt_modell.dart';

// Was einem Projekt an Angaben noch fehlt — für den Assistenten „Angaben
// ergänzen…" (F39), den Hinweis im Projektkopf und das Fenster der
// Spezifikation.
//
// Gefragt wird nur, was die App nicht selbst weiß: Die Artikelbezeichnung
// ist ohne eigene Angabe der Projektname, die Zutaten kommen aus der
// Rezeptur. Nach der Freigabe stehen Artikelnummer und Haltbarkeit im
// Artikel. Ein zurückgestelltes Produktfoto fragt die App nicht — daran
// erinnert der Kopf für sich (F37).

/// Eine Angabe, nach der der Assistent fragt — in seiner Reihenfolge.
enum AngabeSchritt {
  artikelnummer('Artikelnummer'),
  sensorik('Sensorik'),
  produktfoto('Produktfoto'),
  lagerung('Lagerung'),
  haltbarkeit('Haltbarkeit'),
  verpackung('Verpackung');

  const AngabeSchritt(this.label);

  final String label;
}

/// Was [p] an Angaben noch fehlt, in der Reihenfolge des Assistenten.
List<AngabeSchritt> fehlendeAngaben(EntwicklungsProjekt p) {
  final angaben = SpezAngaben.aus(p.spezifikation);
  final s = Sensorik.aus(p.sensorik);
  final freigegeben = p.artikelId != null;
  final fotoSpaeter = checklisteZurueckgestellt(p.checkliste)
      .contains('produktfotoHinterlegt');
  return [
    if (!freigegeben && (p.artikelnummer?.trim() ?? '').isEmpty)
      AngabeSchritt.artikelnummer,
    if ([s.aussehen, s.geruch, s.geschmack, s.konsistenz]
        .any((t) => t.trim().isEmpty))
      AngabeSchritt.sensorik,
    if (p.bildDateiId == null && !fotoSpaeter) AngabeSchritt.produktfoto,
    if (angaben.lagerung.trim().isEmpty) AngabeSchritt.lagerung,
    if (!freigegeben && angaben.haltbarkeit.trim().isEmpty)
      AngabeSchritt.haltbarkeit,
    if (angaben.verpackung.leer) AngabeSchritt.verpackung,
  ];
}

/// „Lagerung", „Lagerung und Haltbarkeit", „Sensorik, Lagerung und
/// Verpackung".
String angabenAufzaehlen(Iterable<AngabeSchritt> schritte) {
  final namen = [for (final s in schritte) s.label];
  if (namen.length < 2) return namen.join();
  return '${namen.sublist(0, namen.length - 1).join(', ')} und '
      '${namen.last}';
}

/// „1 Angabe fehlt", „3 Angaben fehlen".
String angabenFehlenText(int anzahl) =>
    anzahl == 1 ? '1 Angabe fehlt' : '$anzahl Angaben fehlen';

/// Was der Assistent erledigt hat.
class AssistentErgebnis {
  const AssistentErgebnis({
    this.eingetragen = const [],
    this.spaeter = const [],
  });

  final List<AngabeSchritt> eingetragen;
  final List<AngabeSchritt> spaeter;

  /// „Eingetragen: Lagerung und Haltbarkeit · Später: Produktfoto" — leer,
  /// wenn nichts geschah.
  String get text => [
        if (eingetragen.isNotEmpty)
          'Eingetragen: ${angabenAufzaehlen(eingetragen)}',
        if (spaeter.isNotEmpty) 'Später: ${angabenAufzaehlen(spaeter)}',
      ].join(' · ');
}
