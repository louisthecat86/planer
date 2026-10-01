import '../constants/artikel_merkmale.dart';
import '../database/database.dart';
import 'navision_import_service.dart';

// ═══════════════════════════════════════════════════════════════════════
// Allergene aus dem Navision-Suchbegriff
// ═══════════════════════════════════════════════════════════════════════

/// Wörter im Navision-Suchbegriff, die ein Allergen anzeigen → dbValue aus
/// [kAllergene].
///
/// Verglichen werden ganze Wörter in Großbuchstaben, Umlaute aufgelöst
/// („NÜSSE" → „NUESSE"). Ein Wort wie „MILCHKALB" oder „NUSSSCHINKEN"
/// zählt deshalb nicht.
///
/// Bewusst nur ausdrückliche Allergen-Wörter. Es fehlen:
/// * „NUSS" — in der Fleischerei ist die Nuss ein Teilstück (Kalbsnuss),
/// * „KAESE", „SAHNE", „BUTTER" — sonst träfe ein „LEBER KAESE" die Milch,
/// * „EIWEISS" — kann auch Soja- oder Milcheiweiß meinen.
const Map<String, String> kAllergenWoerter = {
  // Eier
  'EI': 'eier',
  'EIER': 'eier',
  'VOLLEI': 'eier',
  'EIGELB': 'eier',
  // Milch
  'MILCH': 'milch',
  'LAKTOSE': 'milch',
  'LACTOSE': 'milch',
  'MILCHEIWEISS': 'milch',
  // Senf
  'SENF': 'senf',
  'SENFSAAT': 'senf',
  'SENFMEHL': 'senf',
  // Schalenfrüchte
  'SCHALENFRUECHTE': 'schalenfruechte',
  'PISTAZIE': 'schalenfruechte',
  'PISTAZIEN': 'schalenfruechte',
  'HASELNUSS': 'schalenfruechte',
  'HASELNUESSE': 'schalenfruechte',
  'WALNUSS': 'schalenfruechte',
  'WALNUESSE': 'schalenfruechte',
  'MANDEL': 'schalenfruechte',
  'MANDELN': 'schalenfruechte',
  'CASHEW': 'schalenfruechte',
  'CASHEWS': 'schalenfruechte',
  'CASHEWNUSS': 'schalenfruechte',
  'PEKANNUSS': 'schalenfruechte',
  'PARANUSS': 'schalenfruechte',
  'MACADAMIA': 'schalenfruechte',
  // Gluten
  'GLUTEN': 'gluten',
  'WEIZEN': 'gluten',
  'ROGGEN': 'gluten',
  'GERSTE': 'gluten',
  'HAFER': 'gluten',
  'DINKEL': 'gluten',
  'KAMUT': 'gluten',
  // Soja
  'SOJA': 'soja',
  // Sellerie
  'SELLERIE': 'sellerie',
  // Sesam
  'SESAM': 'sesam',
  // Sulfit
  'SULFIT': 'sulfit',
  'SULFITE': 'sulfit',
  'SCHWEFELDIOXID': 'sulfit',
  'SO2': 'sulfit',
};

/// Die Allergene, die der Navision-Suchbegriff [suchbegriff] nennt, als
/// dbValues — etwa „EI LAKTOSE" → {eier, milch}.
///
/// Ein Wort nach „OHNE" oder vor „FREI" zählt nicht („OHNE EI",
/// „GLUTEN FREI"). Leer, wenn nichts erkannt wird. Das heißt NICHT
/// allergenfrei — „keine" setzt nur, wer es geprüft hat.
Set<String> allergeneAusSuchbegriff(String? suchbegriff) {
  if (suchbegriff == null || suchbegriff.trim().isEmpty) return <String>{};
  final text = suchbegriff
      .toUpperCase()
      .replaceAll('Ä', 'AE')
      .replaceAll('Ö', 'OE')
      .replaceAll('Ü', 'UE')
      .replaceAll('ß', 'SS');
  final woerter = [
    for (final w in text.split(RegExp('[^A-Z0-9]+')))
      if (w.isNotEmpty) w,
  ];
  final gefunden = <String>{};
  for (var i = 0; i < woerter.length; i++) {
    final allergen = kAllergenWoerter[woerter[i]];
    if (allergen == null) continue;
    final davor = i > 0 ? woerter[i - 1] : '';
    final danach = i + 1 < woerter.length ? woerter[i + 1] : '';
    if (davor == 'OHNE' || danach == 'FREI') continue;
    gefunden.add(allergen);
  }
  return gefunden;
}

// ═══════════════════════════════════════════════════════════════════════
// Abgleich Navision ↔ App
// ═══════════════════════════════════════════════════════════════════════

/// Ein Artikel aus Navision, den es in der App nicht (mehr) gibt.
class NeuerNavisionArtikel {
  const NeuerNavisionArtikel({
    required this.zeile,
    required this.allergene,
    this.imAuftragsbestand = false,
    this.geloescht = false,
  });

  final NavisionZeile zeile;

  /// Allergene laut Suchbegriff (dbValues). Leer, wenn keine erkannt.
  final Set<String> allergene;

  /// Steht im eingelesenen Auftragsbestand — wird also gebraucht.
  final bool imAuftragsbestand;

  /// Gab es in der App schon einmal; Anlegen aktiviert ihn wieder.
  final bool geloescht;

  String get nummer => zeile.nummer;
}

/// Ein Artikel der App, dem laut Navision-Suchbegriff Allergene fehlen.
class AllergenVorschlag {
  const AllergenVorschlag({
    required this.produkt,
    required this.zeile,
    required this.bisher,
    required this.vorschlag,
  });

  final Product produkt;
  final NavisionZeile zeile;

  /// In der App gepflegt (dbValues). Leer: nicht gepflegt.
  final Set<String> bisher;

  /// Laut Navision-Suchbegriff.
  final Set<String> vorschlag;

  /// Allergene aus Navision, die in der App fehlen.
  Set<String> get neu => vorschlag.difference(bisher);

  /// Die App sagt „keine", Navision nennt welche.
  bool get widerspruch => bisher.contains(kAllergenKeine);

  /// Was nach dem Übernehmen gespeichert wird: die bisherigen plus die aus
  /// Navision, ohne „keine". Nichts geht verloren — was die App mehr weiß
  /// als Navision, bleibt stehen.
  String? get ergebnis => merkmaleZuText(
        {...bisher, ...vorschlag}..remove(kAllergenKeine),
        kAllergene,
      );
}

/// Ergebnis des Abgleichs einer Navision-Artikelübersicht mit der App.
class ArtikelstammAbgleich {
  const ArtikelstammAbgleich({
    required this.neu,
    required this.ergaenzen,
    required this.abweichend,
    required this.unveraendert,
    required this.gelesen,
    this.warnungen = const [],
  });

  /// In Navision, aber nicht (mehr) in der App. Zuerst die aus dem
  /// Auftragsbestand, dann nach Nummer.
  final List<NeuerNavisionArtikel> neu;

  /// In der App ohne gepflegte Allergene, Navision nennt welche.
  final List<AllergenVorschlag> ergaenzen;

  /// In der App gepflegt, aber Navision nennt weitere — oder die App sagt
  /// „keine".
  final List<AllergenVorschlag> abweichend;

  /// In beiden, nichts zu tun.
  final int unveraendert;

  /// Datenzeilen mit Artikelnummer in der Datei.
  final int gelesen;

  /// Hinweise vom Einlesen, z.B. fehlende Spalten.
  final List<String> warnungen;
}

/// Gleicht die Navision-Artikelübersicht [katalog] mit den Artikeln der App
/// ab.
///
/// [produkte] sind ALLE Artikel der App, auch gelöschte: Die Nummer ist in
/// der Datenbank eindeutig und bleibt nach dem Löschen belegt. Ein
/// gelöschter Artikel steht deshalb unter „neu" und wird beim Anlegen
/// wieder aktiviert.
///
/// [imAuftragsbestand]: Artikelnummern des eingelesenen Auftragsbestands.
/// Neue Artikel daraus werden gebraucht und stehen vorn.
ArtikelstammAbgleich gleicheArtikelstammAb({
  required NavisionKatalog katalog,
  required List<Product> produkte,
  Set<String> imAuftragsbestand = const {},
}) {
  final jeNummer = {for (final p in produkte) p.artikelnummer.trim(): p};
  final neu = <NeuerNavisionArtikel>[];
  final ergaenzen = <AllergenVorschlag>[];
  final abweichend = <AllergenVorschlag>[];
  var unveraendert = 0;

  for (final z in katalog.zeilen) {
    final nummer = z.nummer.trim();
    if (nummer.isEmpty) continue;
    final vorschlag = allergeneAusSuchbegriff(z.suchbegriff);
    final p = jeNummer[nummer];

    if (p == null || p.deletedAt != null) {
      neu.add(
        NeuerNavisionArtikel(
          zeile: z,
          allergene: vorschlag,
          imAuftragsbestand: imAuftragsbestand.contains(nummer),
          geloescht: p != null,
        ),
      );
      continue;
    }

    final bisher = merkmaleAusText(p.allergene);
    if (vorschlag.isNotEmpty && !bisher.containsAll(vorschlag)) {
      final v = AllergenVorschlag(
        produkt: p,
        zeile: z,
        bisher: bisher,
        vorschlag: vorschlag,
      );
      if (bisher.isEmpty) {
        ergaenzen.add(v);
      } else {
        abweichend.add(v);
      }
      continue;
    }
    unveraendert++;
  }

  neu.sort((a, b) {
    if (a.imAuftragsbestand != b.imAuftragsbestand) {
      return a.imAuftragsbestand ? -1 : 1;
    }
    return a.nummer.compareTo(b.nummer);
  });
  int nachNummer(AllergenVorschlag a, AllergenVorschlag b) =>
      a.produkt.artikelnummer.compareTo(b.produkt.artikelnummer);
  ergaenzen.sort(nachNummer);
  abweichend.sort(nachNummer);

  return ArtikelstammAbgleich(
    neu: neu,
    ergaenzen: ergaenzen,
    abweichend: abweichend,
    unveraendert: unveraendert,
    gelesen: katalog.gelesen,
    warnungen: katalog.warnungen,
  );
}
