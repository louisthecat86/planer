import 'dart:convert';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/entwicklung.dart';
import '../../../core/database/database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/utils/krypto.dart';

// Angehängte Dateien der Produktentwicklung: Der Inhalt liegt mit dem
// Datenschlüssel verschlüsselt in der Datenbank. Einmal beim Speichern
// verschlüsselt, wandert er unverändert ins Backup.

/// Ab dieser Größe wird auf einem eigenen Isolate verschlüsselt.
const int _imHintergrundAb = 256 * 1024;

/// Speichern, Lesen und Löschen angehängter Dateien.
class EntwicklungDateienDienst {
  EntwicklungDateienDienst(this._db);

  final AppDatabase _db;
  static const Uuid _uuid = Uuid();

  /// Der Datenschlüssel dieses Rechners. Ihn gibt es, sobald die
  /// Produktentwicklung einmal entsperrt war.
  Future<Uint8List> _schluessel() async {
    final zeile = await (_db.select(_db.appSettings)
          ..where((s) => s.key.equals(kEntwicklungDatenschluessel)))
        .getSingleOrNull();
    final text = zeile?.value;
    if (text == null) {
      throw StateError(
        'Kein Datenschlüssel — die Produktentwicklung ist noch nicht '
        'eingerichtet oder entsperrt.',
      );
    }
    return base64Decode(text);
  }

  /// Verschlüsselt [inhalt] — für den Import vorab, ohne zu speichern.
  Future<Uint8List> verschluesselt(List<int> inhalt) async {
    final schluessel = await _schluessel();
    final daten = Uint8List.fromList(inhalt);
    if (daten.length < _imHintergrundAb) {
      return verschluesseln(schluessel, daten, zweck: kZweckDatei);
    }
    return _verschluesseleImHintergrund(schluessel, daten);
  }

  /// Speichert eine Datei und gibt ihre ID zurück.
  Future<String> speichern({
    required String name,
    required List<int> inhalt,
    String? projektId,
    String? mimeTyp,
    String? id,
  }) async {
    final paket = await verschluesselt(inhalt);
    final neueId = id ?? _uuid.v4();
    await _db.transaction(() async {
      await _db.into(_db.entwicklungDateien).insertOnConflictUpdate(
            EntwicklungDateienCompanion.insert(
              id: neueId,
              name: name,
              projektId: Value(projektId),
              mimeTyp: Value(mimeTyp),
              groesse: Value(inhalt.length),
            ),
          );
      await _db.into(_db.entwicklungDateiInhalte).insertOnConflictUpdate(
            EntwicklungDateiInhalteCompanion.insert(
              dateiId: neueId,
              inhalt: paket,
            ),
          );
    });
    return neueId;
  }

  /// Der Inhalt einer Datei, entschlüsselt. null, wenn er fehlt.
  Future<Uint8List?> lesen(String dateiId) async {
    final zeile = await (_db.select(_db.entwicklungDateiInhalte)
          ..where((d) => d.dateiId.equals(dateiId)))
        .getSingleOrNull();
    if (zeile == null) return null;
    final schluessel = await _schluessel();
    if (zeile.inhalt.length < _imHintergrundAb) {
      return entschluesseln(schluessel, zeile.inhalt, zweck: kZweckDatei);
    }
    return _entschluesseleImHintergrund(schluessel, zeile.inhalt);
  }

  Future<EntwicklungsDatei?> datei(String dateiId) =>
      (_db.select(_db.entwicklungDateien)..where((d) => d.id.equals(dateiId)))
          .getSingleOrNull();

  /// Löscht eine Datei samt Inhalt.
  Future<void> loeschen(String dateiId) => _db.transaction(() async {
        await (_db.delete(_db.entwicklungDateiInhalte)
              ..where((d) => d.dateiId.equals(dateiId)))
            .go();
        await (_db.delete(_db.entwicklungDateien)
              ..where((d) => d.id.equals(dateiId)))
            .go();
      });

  // Statisch und ohne `async`: Die Funktion für das Isolate nimmt nur ihre
  // Argumente mit.

  static Future<Uint8List> _verschluesseleImHintergrund(
    Uint8List schluessel,
    Uint8List daten,
  ) =>
      Isolate.run(() => verschluesseln(schluessel, daten, zweck: kZweckDatei));

  static Future<Uint8List> _entschluesseleImHintergrund(
    Uint8List schluessel,
    Uint8List paket,
  ) =>
      Isolate.run(() => entschluesseln(schluessel, paket, zweck: kZweckDatei));
}

final entwicklungDateienProvider = Provider<EntwicklungDateienDienst>(
  (ref) => EntwicklungDateienDienst(ref.watch(databaseProvider)),
);

/// Liest eine `data:`-URL, wie die alte Suite Bilder und Anhänge ablegte:
/// Medientyp und Inhalt. null, wenn es keine ist.
({String? mimeTyp, Uint8List inhalt})? ausDatenUrl(String text) {
  if (!text.startsWith('data:')) return null;
  final komma = text.indexOf(',');
  if (komma < 0) return null;
  final kopf = text.substring(5, komma);
  final teile = kopf.split(';');
  final mime = teile.first.isEmpty ? null : teile.first;
  final roh = text.substring(komma + 1);
  try {
    final inhalt = teile.contains('base64')
        ? base64Decode(roh)
        : Uint8List.fromList(utf8.encode(Uri.decodeComponent(roh)));
    return (mimeTyp: mime, inhalt: inhalt);
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  }
}
