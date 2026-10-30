import '../daten/entwicklung_repository.dart';
import '../projekte/projekt_repository.dart';
import 'rezepturblatt_druck.dart';
import 'standvergleich_druck.dart';

// Die Daten für Rezepturblatt und Vergleich der Stände. Ein
// abgeschlossener Stand kommt aus seinen eingefrorenen Daten, ein Entwurf
// so, wie er gerade ist.
//
// Ohne Oberfläche — so lässt sich das Laden mit einer Datenbank im
// Speicher prüfen.

/// Was das Rezepturblatt des Stands [versionId] braucht — null, wenn es
/// Stand oder Rezeptur nicht mehr gibt.
Future<RezepturblattDaten?> rezepturblattLaden(
  EntwicklungRepository repo,
  ProjektRepository projekte,
  String versionId,
) async {
  final v = await repo.version(versionId);
  if (v == null) return null;
  final r = await repo.rezeptur(v.rezepturId);
  final eingabe = await repo.rechenRezeptur(versionId);
  if (r == null || eingabe == null) return null;
  final projektId = r.projektId;
  final projekt = projektId == null ? null : await projekte.projekt(projektId);
  return RezepturblattDaten(
    name: r.name,
    artikelnummer: r.artikelnummer,
    beschreibung: r.beschreibung,
    version: v,
    eingabe: eingabe,
    freigegeben: projekt != null && projekt.freigabeVersionId == v.id,
  );
}

/// Alle Stände der Rezeptur [rezepturId] für den Vergleich — null, wenn
/// es sie nicht mehr gibt.
Future<StandvergleichDaten?> standvergleichLaden(
  EntwicklungRepository repo,
  ProjektRepository projekte,
  String rezepturId,
) async {
  final r = await repo.rezeptur(rezepturId);
  if (r == null) return null;
  final staende = <VergleichStand>[];
  for (final v in await repo.versionen(rezepturId)) {
    final eingabe = await repo.rechenRezeptur(v.id);
    if (eingabe != null) {
      staende.add(VergleichStand(version: v, eingabe: eingabe));
    }
  }
  final projektId = r.projektId;
  final projekt = projektId == null ? null : await projekte.projekt(projektId);
  return StandvergleichDaten(
    name: r.name,
    artikelnummer: r.artikelnummer,
    staende: staende,
    freigabeVersionId: projekt?.freigabeVersionId,
  );
}
