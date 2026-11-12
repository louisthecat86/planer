import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/entwicklung.dart';
import '../../../core/database/database.dart';

// Zutaten aus Navision.
//
// Die Artikelübersicht aus Navision enthält auch Rohwaren und Zutaten —
// erkennbar an der Produktbuchungsgruppe. Welche Gruppen das sind, hakt
// man einmal an; der Abgleich legt dann jede Zutat an, die es im Katalog
// noch nicht gibt: mit Nummer und Namen, alles Weitere pflegt man selbst.
//
// Zugeordnet wird allein über die Artikelnummer. Namen können sich
// doppeln oder leicht abweichen; die Nummer ist eindeutig. Eine Zutat,
// die es schon gibt, fasst der Abgleich nicht an.

/// Unter diesem Schlüssel steht in `app_settings`, welche
/// Produktbuchungsgruppen als Zutaten zählen (JSON-Liste).
const String kZutatenNavisionGruppen =
    '${kEntwicklungPraefix}zutaten_navision_gruppen';

/// Eine Produktbuchungsgruppe der Artikelübersicht mit der Zahl ihrer
/// Artikel.
typedef NavisionGruppe = ({String gruppe, int artikel});

/// Was der Abgleich für die gewählten Gruppen ergibt.
class ZutatenAbgleich {
  const ZutatenAbgleich({required this.neu, required this.vorhanden});

  /// Artikel der Gruppen, die es im Zutatenkatalog noch nicht gibt —
  /// nach Namen.
  final List<NavisionArtikelZeile> neu;

  /// So viele gibt es schon (über die Artikelnummer erkannt, auch
  /// gelöschte Zutaten: Was jemand entfernt hat, kommt nicht wieder).
  final int vorhanden;
}

/// Abgleich des Zutatenkatalogs mit dem Stand der Artikelübersicht.
class ZutatenNavision {
  ZutatenNavision(this._db);

  final AppDatabase _db;
  static const Uuid _uuid = Uuid();

  /// Die Produktbuchungsgruppen des eingelesenen Stands, nach Namen.
  /// Artikel ohne Gruppe zählen nicht.
  Future<List<NavisionGruppe>> gruppen() async {
    final anzahl = <String, int>{};
    for (final z in await _db.select(_db.navisionArtikel).get()) {
      final g = z.produktbuchungsgruppe?.trim() ?? '';
      if (g.isEmpty) continue;
      anzahl[g] = (anzahl[g] ?? 0) + 1;
    }
    return [
      for (final g in anzahl.keys.toList()..sort())
        (gruppe: g, artikel: anzahl[g]!),
    ];
  }

  /// Die zuletzt gewählten Gruppen.
  Future<Set<String>> gewaehlteGruppen() async {
    final zeile = await (_db.select(_db.appSettings)
          ..where((s) => s.key.equals(kZutatenNavisionGruppen)))
        .getSingleOrNull();
    if (zeile == null) return {};
    try {
      final liste = jsonDecode(zeile.value);
      if (liste is! List) return {};
      return {
        for (final g in liste)
          if (g is String && g.trim().isNotEmpty) g.trim(),
      };
    } on FormatException {
      return {};
    }
  }

  /// Merkt sich die gewählten [gruppen] fürs nächste Mal.
  Future<void> gruppenMerken(Set<String> gruppen) =>
      _db.into(_db.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: kZutatenNavisionGruppen,
              value: jsonEncode(gruppen.toList()..sort()),
              updatedAt: Value(DateTime.now()),
            ),
          );

  /// Vergleicht die Artikel der [gruppen] mit dem Zutatenkatalog.
  Future<ZutatenAbgleich> abgleich(Set<String> gruppen) async {
    if (gruppen.isEmpty) {
      return const ZutatenAbgleich(neu: [], vorhanden: 0);
    }
    final bekannt = {
      for (final z in await _db.select(_db.entwicklungZutaten).get())
        if ((z.artikelnummer ?? '').trim().isNotEmpty) z.artikelnummer!.trim(),
    };
    final neu = <NavisionArtikelZeile>[];
    var vorhanden = 0;
    for (final a in await _db.select(_db.navisionArtikel).get()) {
      if (!gruppen.contains(a.produktbuchungsgruppe?.trim())) continue;
      if (bekannt.contains(a.artikelnummer.trim())) {
        vorhanden++;
      } else {
        neu.add(a);
      }
    }
    neu.sort(
      (a, b) => zutatName(a).toLowerCase().compareTo(
            zutatName(b).toLowerCase(),
          ),
    );
    return ZutatenAbgleich(neu: neu, vorhanden: vorhanden);
  }

  /// Legt die [neuen] Artikel als Zutaten an — mit Nummer und Namen.
  /// Zurück kommt, wie viele es wurden: Gibt es zu einer Nummer inzwischen
  /// doch eine Zutat, bleibt die, wie sie ist.
  Future<int> anlegen(
    List<NavisionArtikelZeile> neue, {
    DateTime? jetzt,
  }) async {
    if (neue.isEmpty) return 0;
    final wann = jetzt ?? DateTime.now();
    return _db.transaction(() async {
      final bekannt = {
        for (final z in await _db.select(_db.entwicklungZutaten).get())
          if ((z.artikelnummer ?? '').trim().isNotEmpty)
            z.artikelnummer!.trim(),
      };
      final dazu = <EntwicklungZutatenCompanion>[];
      for (final a in neue) {
        final nummer = a.artikelnummer.trim();
        if (nummer.isEmpty || !bekannt.add(nummer)) continue;
        dazu.add(
          EntwicklungZutatenCompanion.insert(
            id: _uuid.v4(),
            name: zutatName(a),
            artikelnummer: Value(nummer),
            createdAt: Value(wann),
            updatedAt: Value(wann),
          ),
        );
      }
      await _db.batch((b) => b.insertAll(_db.entwicklungZutaten, dazu));
      return dazu.length;
    });
  }
}

/// Der Name der Zutat aus [a]: die Beschreibung, mit „Beschreibung 2"
/// dahinter, wenn sie etwas sagt — sonst die Nummer.
String zutatName(NavisionArtikelZeile a) {
  final teile = [
    a.beschreibung.trim(),
    a.beschreibung2?.trim() ?? '',
  ].where((t) => t.isNotEmpty).toList();
  return teile.isEmpty ? a.artikelnummer : teile.join(' ');
}
