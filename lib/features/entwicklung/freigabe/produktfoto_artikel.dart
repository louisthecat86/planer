import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/services/artikel_fotos.dart';
import '../daten/dateien.dart';

// Das Produktfoto eines Projekts wandert mit der Freigabe in die
// Artikelkarte: Es liegt dann bei den Fotos des Artikels und ist dort das
// Referenzbild — so soll das Produkt aussehen.
//
// Das gilt auch danach: Bekommt ein freigegebenes Projekt ein (anderes)
// Produktfoto, kommt es ebenfalls zum Artikel.
//
// Beim Artikel liegt eine eigene Kopie, als Foto aufbereitet (JPEG, längere
// Kante 1600 px) und — wie alle Daten der Produktion — unverschlüsselt.
// Das Foto im Projekt bleibt, wie es ist.

/// So beginnen die IDs der Fotos, die aus der Produktentwicklung zum
/// Artikel kamen.
const String kEntwicklungsFotoPraefix = 'entw-';

/// Was beim Foto im Artikel als Bemerkung steht.
const String kProduktfotoBemerkung = 'Produktfoto aus der Entwicklung';

/// Die ID, unter der die Datei [dateiId] beim Artikel [artikelId] liegt.
String entwicklungsFotoId(String artikelId, String dateiId) =>
    '$kEntwicklungsFotoPraefix$artikelId-$dateiId';

/// Ein Produktfoto, fertig für den Artikel.
typedef ArtikelProduktfoto = ({String dateiId, Uint8List bild, DateTime am});

class ProduktfotoUebernahme {
  ProduktfotoUebernahme(this._db)
      : _dateien = EntwicklungDateienDienst(_db),
        _fotos = ArtikelFotoDienst(_db);

  final AppDatabase _db;
  final EntwicklungDateienDienst _dateien;
  final ArtikelFotoDienst _fotos;

  /// Liest die Datei [dateiId] und bereitet sie als Foto auf — null, wenn
  /// es sie nicht gibt oder sie kein Bild ist, das sich lesen lässt.
  /// Das rechnet einen Moment; deshalb vor einer Transaktion aufrufen.
  Future<ArtikelProduktfoto?> vorbereiten(String? dateiId) async {
    if (dateiId == null) return null;
    try {
      final datei = await _dateien.datei(dateiId);
      final inhalt = await _dateien.lesen(dateiId);
      if (datei == null || inhalt == null) return null;
      final bild = await fotoAufbereiten(inhalt);
      if (bild == null) return null;
      return (dateiId: dateiId, bild: bild, am: datei.createdAt);
    } catch (_) {
      // Ohne Schlüssel oder mit beschädigtem Inhalt: dann eben kein Foto.
      return null;
    }
  }

  /// Legt [foto] zu den Fotos des Artikels. Es wird das Referenzbild, wenn
  /// der Artikel noch keins hat — oder seins selbst aus der
  /// Produktentwicklung kam; ein von Hand gewähltes bleibt. Liegt genau
  /// dieses Foto schon dort, geschieht nichts. Gibt zurück, ob es
  /// dazugekommen ist.
  Future<bool> ablegen(String artikelId, ArtikelProduktfoto foto) =>
      _db.transaction(() async {
        final id = entwicklungsFotoId(artikelId, foto.dateiId);
        if ((await _fotos.vorhandene([id])).isNotEmpty) return false;
        final referenz = await (_db.select(_db.artikelFotos)
              ..where((f) => f.productId.equals(artikelId) & f.istReferenz))
            .get();
        await _fotos.speichern(
          id: id,
          productId: artikelId,
          bild: foto.bild,
          aufgenommenAm: foto.am,
          bezeichnung: kProduktfotoBemerkung,
        );
        if (referenz.every((f) => f.id.startsWith(kEntwicklungsFotoPraefix))) {
          await _fotos.referenzSetzen(artikelId, id);
        }
        return true;
      });

  /// Für ein schon freigegebenes Projekt: legt sein Produktfoto zum
  /// Artikel. Gibt den Artikel zurück, wenn es dazugekommen ist — sonst
  /// null (nicht freigegeben, Artikel gelöscht, kein Foto oder schon
  /// dort).
  Future<Product?> uebernehmen(String projektId) async {
    final projekt = await (_db.select(_db.entwicklungProjekte)
          ..where((p) => p.id.equals(projektId)))
        .getSingleOrNull();
    final artikelId = projekt?.artikelId;
    if (projekt == null || artikelId == null) return null;
    final artikel = await (_db.select(_db.products)
          ..where((p) => p.id.equals(artikelId) & p.deletedAt.isNull()))
        .getSingleOrNull();
    if (artikel == null) return null;
    final foto = await vorbereiten(projekt.bildDateiId);
    if (foto == null) return null;
    return await ablegen(artikelId, foto) ? artikel : null;
  }
}

final produktfotoUebernahmeProvider = Provider<ProduktfotoUebernahme>(
  (ref) => ProduktfotoUebernahme(ref.watch(databaseProvider)),
);
