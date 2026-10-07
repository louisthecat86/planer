import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';
import '../utils/datum.dart';

/// Schlüssel einer Zelle im Wochenboard: Abteilung (dbValue) und Tag
/// (00:00 Uhr). Records vergleichen nach Inhalt — taugen also direkt als
/// Map-Schlüssel.
typedef AufgabenZelle = (String abteilung, DateTime tag);

/// Sonstige Aufgaben je Abteilung und Tag: von Hand eingetragen, nicht aus
/// der Planung eines Artikels. Im Wochenboard hat jede Abteilung dafür eine
/// eigene Zeile; abhaken macht sie grün, und was liegen geblieben ist,
/// wandert auf einen anderen Tag.
class TagesaufgabenService {
  const TagesaufgabenService._();

  /// Alle Aufgaben von [von] (inklusive) bis [bisExkl] (exklusive), je
  /// Abteilung und Tag in ihrer Reihenfolge.
  static Future<Map<AufgabenZelle, List<Tagesaufgabe>>> fuerZeitraum(
    AppDatabase db, {
    required DateTime von,
    required DateTime bisExkl,
  }) async {
    final ab = tagOhneZeit(von);
    final bis = tagOhneZeit(bisExkl);
    final zeilen = await (db.select(db.tagesaufgaben)
          ..where((a) => a.deletedAt.isNull())
          ..where((a) => a.datum.isBiggerOrEqualValue(ab))
          ..where((a) => a.datum.isSmallerThanValue(bis))
          ..orderBy([
            (a) => OrderingTerm.asc(a.sortierung),
            (a) => OrderingTerm.asc(a.createdAt),
          ]))
        .get();
    final ergebnis = <AufgabenZelle, List<Tagesaufgabe>>{};
    for (final a in zeilen) {
      (ergebnis[(a.abteilung, tagOhneZeit(a.datum))] ??= []).add(a);
    }
    return ergebnis;
  }

  /// Legt eine Aufgabe für [abteilung] (dbValue) an [tag] an — ans Ende.
  /// Gibt ihre ID zurück.
  static Future<String> anlegen(
    AppDatabase db, {
    required DateTime tag,
    required String abteilung,
    required String inhalt,
  }) async {
    final text = _geprueft(inhalt);
    final datum = tagOhneZeit(tag);
    final id = const Uuid().v4();
    await db.into(db.tagesaufgaben).insert(
          TagesaufgabenCompanion.insert(
            id: id,
            datum: datum,
            abteilung: abteilung,
            inhalt: text,
            sortierung: Value(await _naechsteSortierung(db, datum, abteilung)),
          ),
        );
    return id;
  }

  /// Ändert den Text einer Aufgabe.
  static Future<void> aendern(
    AppDatabase db,
    String id, {
    required String inhalt,
  }) async {
    final text = _geprueft(inhalt);
    await _schreibe(
      db,
      id,
      TagesaufgabenCompanion(
        inhalt: Value(text),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Hakt eine Aufgabe ab — oder nimmt den Haken zurück.
  static Future<void> abhaken(
    AppDatabase db,
    String id, {
    required bool erledigt,
  }) {
    return _schreibe(
      db,
      id,
      TagesaufgabenCompanion(
        erledigt: Value(erledigt),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Legt eine Aufgabe auf [tag] — und, wenn angegeben, in eine andere
  /// [abteilung] (dbValue). Dort kommt sie ans Ende. Ändert sich weder Tag
  /// noch Abteilung, bleibt alles, wie es ist.
  static Future<void> verschieben(
    AppDatabase db,
    String id, {
    required DateTime tag,
    String? abteilung,
  }) async {
    final datum = tagOhneZeit(tag);
    final aufgabe = await (db.select(db.tagesaufgaben)
          ..where((a) => a.id.equals(id)))
        .getSingleOrNull();
    if (aufgabe == null) return;
    final ziel = abteilung ?? aufgabe.abteilung;
    if (tagOhneZeit(aufgabe.datum) == datum && aufgabe.abteilung == ziel) {
      return;
    }
    await _schreibe(
      db,
      id,
      TagesaufgabenCompanion(
        datum: Value(datum),
        abteilung: Value(ziel),
        sortierung: Value(await _naechsteSortierung(db, datum, ziel)),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Entfernt eine Aufgabe (Soft-Delete).
  static Future<void> loeschen(AppDatabase db, String id) {
    final jetzt = DateTime.now();
    return _schreibe(
      db,
      id,
      TagesaufgabenCompanion(
        deletedAt: Value(jetzt),
        updatedAt: Value(jetzt),
      ),
    );
  }

  /// Holt eine gelöschte Aufgabe zurück — „Rückgängig" nach dem Löschen.
  static Future<void> wiederherstellen(AppDatabase db, String id) {
    return _schreibe(
      db,
      id,
      TagesaufgabenCompanion(
        deletedAt: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Der nächste Arbeitstag nach [tag] (Montag bis Freitag) — das Ziel,
  /// wenn eine Aufgabe liegen geblieben ist.
  static DateTime naechsterArbeitstag(DateTime tag) {
    var d = tagPlus(tag, 1);
    while (d.weekday > DateTime.friday) {
      d = tagPlus(d, 1);
    }
    return d;
  }

  static String _geprueft(String inhalt) {
    final text = inhalt.trim();
    if (text.isEmpty) {
      throw ArgumentError('Die Aufgabe braucht einen Text.');
    }
    return text;
  }

  static Future<void> _schreibe(
    AppDatabase db,
    String id,
    TagesaufgabenCompanion werte,
  ) {
    return (db.update(db.tagesaufgaben)..where((a) => a.id.equals(id)))
        .write(werte);
  }

  /// Nächste freie Position am Ende von [abteilung] an [tag].
  static Future<int> _naechsteSortierung(
    AppDatabase db,
    DateTime tag,
    String abteilung,
  ) async {
    final vorhandene = await (db.select(db.tagesaufgaben)
          ..where((a) => a.deletedAt.isNull())
          ..where((a) => a.abteilung.equals(abteilung))
          ..where((a) => a.datum.isBiggerOrEqualValue(tag))
          ..where((a) => a.datum.isSmallerThanValue(tagPlus(tag, 1))))
        .get();
    var hoechste = -1;
    for (final a in vorhandene) {
      if (a.sortierung > hoechste) hoechste = a.sortierung;
    }
    return hoechste + 1;
  }
}
