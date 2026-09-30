import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';

/// Ein Artikel aus Navision, den es in der App noch nicht gibt.
class FehlenderArtikel {
  const FehlenderArtikel({
    required this.nummer,
    required this.bezeichnung,
    this.bezeichnung2,
  });

  final String nummer;
  final String bezeichnung;

  /// Zweite Zeile der Navision-Bezeichnung, z.B. „geschnitten, 500g Pack".
  final String? bezeichnung2;
}

/// Was beim Anlegen passiert ist.
class ArtikelAnlageErgebnis {
  const ArtikelAnlageErgebnis({
    this.angelegt = 0,
    this.reaktiviert = 0,
    this.schonVorhanden = 0,
  });

  /// Neu angelegte Artikelmasken.
  final int angelegt;

  /// Früher gelöschte Artikel mit derselben Nummer, wieder aktiviert.
  final int reaktiviert;

  /// Gab es schon als aktiven Artikel — nichts geändert.
  final int schonVorhanden;

  int get gesamt => angelegt + reaktiviert;
}

/// Legt Artikel an, die Navision kennt, die App aber noch nicht.
///
/// Angelegt wird nur eine Hülle: Nummer, Bezeichnung und die Markierung
/// „nicht eingepflegt". Prozessschritte und Stammdaten trägt man danach in
/// der Artikelliste nach — erst dann lässt sich der Artikel einplanen.
class ArtikelAnlageService {
  ArtikelAnlageService(this._db);

  final AppDatabase _db;

  /// Legt [artikel] an, alles in einer Transaktion.
  ///
  /// Abgeglichen wird über die Artikelnummer. Ein aktiver Artikel mit
  /// derselben Nummer bleibt unberührt. Ein früher GELÖSCHTER wird wieder
  /// aktiviert statt neu angelegt — die Nummer ist in der Datenbank
  /// eindeutig und auch nach dem Löschen noch belegt. So verhält sich auch
  /// „Neuer Artikel" in der Artikelliste. Seine alten Prozessschritte
  /// bleiben gelöscht, seine Produktionshistorie hängt wieder daran.
  Future<ArtikelAnlageErgebnis> legeAn(List<FehlenderArtikel> artikel) async {
    var angelegt = 0;
    var reaktiviert = 0;
    var schonVorhanden = 0;
    final jetzt = DateTime.now();

    await _db.transaction(() async {
      // Alle Artikel inklusive gelöschter, EINMAL geladen.
      final vorhandene = await _db.select(_db.products).get();
      final jeNummer = {for (final p in vorhandene) p.artikelnummer: p};
      final bearbeitet = <String>{};

      for (final a in artikel) {
        final nummer = a.nummer.trim();
        // Doppelt in der Liste? Die zweite Anlage ließe die ganze
        // Transaktion an der Eindeutigkeit der Nummer scheitern.
        if (nummer.isEmpty || !bearbeitet.add(nummer)) continue;

        final vorhanden = jeNummer[nummer];
        if (vorhanden != null && vorhanden.deletedAt == null) {
          schonVorhanden++;
          continue;
        }

        if (vorhanden != null) {
          final id = vorhanden.id;
          await (_db.update(_db.products)..where((p) => p.id.equals(id)))
              .write(
            ProductsCompanion(
              deletedAt: const Value(null),
              // Die alten Schritte bleiben gelöscht — der Artikel ist also
              // wieder eine Hülle, die gepflegt werden muss.
              istEingepflegt: const Value(false),
              updatedAt: Value(jetzt),
            ),
          );
          reaktiviert++;
          continue;
        }

        final bezeichnung = a.bezeichnung.trim();
        final zweite = (a.bezeichnung2 ?? '').trim();
        await _db.into(_db.products).insert(
              ProductsCompanion.insert(
                id: const Uuid().v4(),
                artikelnummer: nummer,
                artikelbezeichnung: bezeichnung.isEmpty ? nummer : bezeichnung,
                beschreibung: Value(zweite.isEmpty ? null : zweite),
                istEingepflegt: const Value(false),
              ),
            );
        angelegt++;
      }
    });

    return ArtikelAnlageErgebnis(
      angelegt: angelegt,
      reaktiviert: reaktiviert,
      schonVorhanden: schonVorhanden,
    );
  }
}
