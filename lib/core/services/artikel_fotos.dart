import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:erfassung_format/erfassung_format.dart'
    show istJpeg, kFotoKante, kFotoQualitaet;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

import '../database/database.dart';
import '../providers/database_provider.dart';
import 'datei_ablage.dart';

// Fotos zum Artikel: an der Anlage mit der App „Planer Erfassung"
// aufgenommen oder am PC hinzugefügt. Die Angaben stehen in
// `artikel_fotos`, das Bild in `artikel_foto_inhalte`.
//
// Ein Foto bleibt klein — längere Kante 1600 px, JPEG, rund 300 KB. Im
// Auto-Backup steht es nur als Prüfsumme; das Bild liegt einmal in der
// Ablage neben den Backups ([DateiAblage]), wie die Dateien der
// Produktentwicklung. Das Komplett-Backup trägt alles in einer Datei.

/// Bis zu dieser Größe bleibt ein Foto vom Handy, wie es ist — nur seine
/// Aufnahmedaten fallen weg. Darüber wird es neu gerechnet.
const int kFotoHoechstens = 900 * 1024;

/// Rechnet ein Bild zum Foto um: aufrecht gedreht, längere Kante höchstens
/// [kante], ohne Aufnahmedaten, als JPEG. null, wenn es kein Bild ist.
Uint8List? fotoNeuRechnen(Uint8List bytes, {int kante = kFotoKante}) {
  img.Image? roh;
  try {
    roh = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (roh == null || roh.width == 0 || roh.height == 0) return null;
  var bild = roh;
  final ifd = bild.exif.imageIfd;
  if (ifd.hasOrientation && ifd.orientation != 1) {
    bild = img.bakeOrientation(bild);
  }
  if (bild.hasPalette) bild = bild.convert(numChannels: 3);
  if (math.max(bild.width, bild.height) > kante) {
    bild = bild.width >= bild.height
        ? img.copyResize(
            bild,
            width: kante,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            bild,
            height: kante,
            interpolation: img.Interpolation.average,
          );
  }
  // Ohne EXIF: kein Aufnahmeort, keine Kamera — und gedreht ist es schon.
  bild.exif = img.ExifData();
  return img.encodeJpg(bild, quality: kFotoQualitaet);
}

/// Nimmt einem JPEG die Aufnahmedaten (Ort, Kamera), ohne es neu zu
/// rechnen — nur die Drehung bleibt. Was dabei nicht gelingt oder zu groß
/// ist (in Bytes oder in Pixeln), wird neu gerechnet. null, wenn es kein
/// Bild ist.
Uint8List? fotoSaeubern(Uint8List bytes) {
  if (!istJpeg(bytes) || bytes.length > kFotoHoechstens) {
    return fotoNeuRechnen(bytes);
  }
  try {
    // Die Maße stehen im Kopf — dafür wird das Bild nicht entpackt.
    final kopf = img.JpegDecoder().startDecode(bytes);
    if (kopf == null || math.max(kopf.width, kopf.height) > kFotoKante) {
      return fotoNeuRechnen(bytes);
    }
    final alt = img.decodeJpgExif(bytes);
    if (alt == null || alt.isEmpty) return bytes;
    final neu = img.ExifData();
    final ifd = alt.imageIfd;
    if (ifd.hasOrientation) neu.imageIfd.orientation = ifd.orientation;
    final sauber = img.injectJpgExif(bytes, neu);
    if (sauber != null && istJpeg(sauber)) return sauber;
  } catch (_) {
    // Ungewöhnlich aufgebaut — dann eben neu rechnen.
  }
  return fotoNeuRechnen(bytes);
}

/// Bereitet ein Bild als Foto auf — auf einem eigenen Isolate, damit das
/// Fenster nicht steht. [vomHandy]: Die App hat es schon verkleinert.
/// null, wenn es kein Bild ist.
Future<Uint8List?> fotoAufbereiten(Uint8List bytes, {bool vomHandy = false}) =>
    Isolate.run(
      () => vomHandy ? fotoSaeubern(bytes) : fotoNeuRechnen(bytes),
    );

/// Speichern, Lesen und Löschen der Fotos eines Artikels.
class ArtikelFotoDienst {
  const ArtikelFotoDienst(this._db);

  final AppDatabase _db;

  /// Speichert das JPEG [bild] als Foto des Artikels und gibt seine ID
  /// zurück. Mit [id] ersetzt es ein Foto derselben ID.
  Future<String> speichern({
    required String productId,
    required Uint8List bild,
    required DateTime aufgenommenAm,
    String? bezeichnung,
    String? kuerzel,
    String? id,
  }) async {
    final summe = await pruefsummeVon(bild);
    final neueId = id ?? const Uuid().v4();
    await _db.transaction(() async {
      await _db.into(_db.artikelFotos).insertOnConflictUpdate(
            ArtikelFotosCompanion.insert(
              id: neueId,
              productId: productId,
              aufgenommenAm: aufgenommenAm,
              bezeichnung: Value(_leerZuNull(bezeichnung)),
              kuerzel: Value(_leerZuNull(kuerzel)),
              groesse: Value(bild.length),
              pruefsumme: Value(summe),
            ),
          );
      await _db.into(_db.artikelFotoInhalte).insertOnConflictUpdate(
            ArtikelFotoInhalteCompanion.insert(fotoId: neueId, inhalt: bild),
          );
    });
    return neueId;
  }

  /// Welche der [ids] es als Foto schon gibt.
  Future<Set<String>> vorhandene(Iterable<String> ids) async {
    final gesucht = ids.toSet();
    if (gesucht.isEmpty) return const {};
    final t = _db.artikelFotos;
    final zeilen = await (_db.selectOnly(t)
          ..addColumns([t.id])
          ..where(t.id.isIn(gesucht)))
        .map((z) => z.read(t.id)!)
        .get();
    return zeilen.toSet();
  }

  /// Die Fotos eines Artikels: das Referenzbild zuerst, dann die neuesten.
  Stream<List<ArtikelFoto>> beobachten(String productId) =>
      (_db.select(_db.artikelFotos)
            ..where((f) => f.productId.equals(productId))
            ..orderBy([
              (f) => OrderingTerm.desc(f.istReferenz),
              (f) => OrderingTerm.desc(f.aufgenommenAm),
              (f) => OrderingTerm.desc(f.createdAt),
            ]))
          .watch();

  /// Das Bild eines Fotos — null, wenn es fehlt.
  Future<Uint8List?> bild(String fotoId) async {
    final zeile = await (_db.select(_db.artikelFotoInhalte)
          ..where((i) => i.fotoId.equals(fotoId)))
        .getSingleOrNull();
    return zeile?.inhalt;
  }

  /// Macht [fotoId] zum Referenzbild des Artikels — null: keins mehr.
  Future<void> referenzSetzen(String productId, String? fotoId) =>
      _db.transaction(() async {
        await (_db.update(_db.artikelFotos)
              ..where(
                (f) => f.productId.equals(productId) & f.istReferenz,
              ))
            .write(const ArtikelFotosCompanion(istReferenz: Value(false)));
        if (fotoId == null) return;
        await (_db.update(_db.artikelFotos)
              ..where(
                (f) => f.id.equals(fotoId) & f.productId.equals(productId),
              ))
            .write(const ArtikelFotosCompanion(istReferenz: Value(true)));
      });

  Future<void> bezeichnungSetzen(String fotoId, String? bezeichnung) =>
      (_db.update(_db.artikelFotos)..where((f) => f.id.equals(fotoId))).write(
        ArtikelFotosCompanion(bezeichnung: Value(_leerZuNull(bezeichnung))),
      );

  /// Löscht ein Foto samt Bild.
  Future<void> loeschen(String fotoId) => _db.transaction(() async {
        await (_db.delete(_db.artikelFotoInhalte)
              ..where((i) => i.fotoId.equals(fotoId)))
            .go();
        await (_db.delete(_db.artikelFotos)..where((f) => f.id.equals(fotoId)))
            .go();
      });

  static String? _leerZuNull(String? s) {
    final t = s?.trim();
    return t == null || t.isEmpty ? null : t;
  }
}

final artikelFotoDienstProvider = Provider<ArtikelFotoDienst>(
  (ref) => ArtikelFotoDienst(ref.watch(databaseProvider)),
);

/// Die Fotos eines Artikels, laufend.
final artikelFotosProvider =
    StreamProvider.autoDispose.family<List<ArtikelFoto>, String>(
  (ref, productId) =>
      ref.watch(artikelFotoDienstProvider).beobachten(productId),
);

/// Das Bild eines Fotos — für Kachel und große Ansicht.
final artikelFotoBildProvider =
    FutureProvider.autoDispose.family<Uint8List?, String>(
  (ref, fotoId) => ref.watch(artikelFotoDienstProvider).bild(fotoId),
);

// ── Fotos im Backup ───────────────────────────────────────────────────
//
// Im Datenteil des Backups stehen:
//
//   artikel_fotos           die Angaben, Zeile für Zeile
//   artikel_foto_inhalte    je Foto das Bild (Base64) — Komplett-Backup
//   artikel_foto_verweise   je Foto die Prüfsumme seines Bilds — im
//                           Auto-Backup; das Bild liegt in der Ablage

/// Die Fotos eines Backups, vorbereitet, bevor die Datenbank angefasst
/// wird.
class FotoTeil {
  const FotoTeil({
    this.fotos = const [],
    this.bilder = const {},
    this.bleiben = const {},
  });

  /// Die Angaben der Fotos, deren Bild da ist.
  final List<ArtikelFoto> fotos;

  /// Die Bilder, die einzuspielen sind.
  final Map<String, Uint8List> bilder;

  /// Die Fotos, deren Bild schon genau so in der Datenbank liegt.
  final Set<String> bleiben;
}

/// Ausfuhr und Einfuhr der Fotos im Backup.
class FotoSicherung {
  FotoSicherung._();

  static const String kFotos = 'artikel_fotos';
  static const String kInhalte = 'artikel_foto_inhalte';
  static const String kVerweise = 'artikel_foto_verweise';

  /// Die Einträge fürs Backup — leer, wenn es keine Fotos gibt. Mit
  /// [ablage] stehen die Bilder dort statt im Backup.
  static Future<Map<String, Object?>> exportieren(
    AppDatabase db, {
    DateiAblage? ablage,
  }) async {
    final verweise = ablage == null ? null : await _auslagern(db, ablage);
    // Erst danach lesen: Das Auslagern trägt fehlende Prüfsummen nach.
    final fotos = await db.select(db.artikelFotos).get();
    if (fotos.isEmpty) return const {};
    return {
      kFotos: [for (final f in fotos) f.toJson()],
      if (verweise != null)
        kVerweise: verweise
      else
        kInhalte: {
          for (final i in await db.select(db.artikelFotoInhalte).get())
            i.fotoId: base64Encode(i.inhalt),
        },
    };
  }

  /// Legt die Bilder ab, die in [ablage] noch fehlen, und gibt je Foto die
  /// Prüfsumme zurück. Gelesen wird nur, was dort noch nicht liegt.
  static Future<Map<String, String>> _auslagern(
    AppDatabase db,
    DateiAblage ablage,
  ) async {
    final summen = <String, String?>{
      for (final f in await db.select(db.artikelFotos).get())
        f.id: f.pruefsumme,
    };
    final t = db.artikelFotoInhalte;
    final ids = await (db.selectOnly(t)..addColumns([t.fotoId]))
        .map((z) => z.read(t.fotoId)!)
        .get();
    final verweise = <String, String>{};
    for (final id in ids) {
      if (!summen.containsKey(id)) continue;
      var summe = summen[id];
      if (summe == null || !await ablage.hat(summe)) {
        final zeile = await (db.select(t)..where((i) => i.fotoId.equals(id)))
            .getSingleOrNull();
        if (zeile == null) continue;
        final echt = await pruefsummeVon(zeile.inhalt);
        await ablage.ablegen(echt, zeile.inhalt);
        if (summe != echt) {
          await (db.update(db.artikelFotos)..where((f) => f.id.equals(id)))
              .write(ArtikelFotosCompanion(pruefsumme: Value(echt)));
        }
        summe = echt;
      }
      verweise[id] = summe;
    }
    return verweise;
  }

  /// Liest die Fotos aus dem Datenteil [data] eines Backups und holt die
  /// Bilder eines Auto-Backups aus den [ablagen] zurück. Ein Bild, das
  /// schon genau so in [db] liegt, wird nicht gelesen — es bleibt einfach.
  ///
  /// Fehlen Bilder, gibt es eine [FormatException] mit der Anzahl: Dann
  /// wird nichts eingespielt, sonst stünden die Fotos danach leer da.
  static Future<FotoTeil> vorbereiten(
    Map<String, dynamic> data, {
    required List<DateiAblage> ablagen,
    required AppDatabase db,
  }) async {
    final zeilen = data[kFotos];
    if (zeilen is! List || zeilen.isEmpty) return const FotoTeil();
    final alle = [
      for (final z in zeilen)
        if (z is Map<String, dynamic>) ArtikelFoto.fromJson(z),
    ];
    final bilder = <String, Uint8List>{};
    final bleiben = <String>{};

    final inhalte = data[kInhalte];
    if (inhalte is Map<String, dynamic>) {
      for (final MapEntry(key: id, value: text) in inhalte.entries) {
        if (text is String) bilder[id] = base64Decode(text);
      }
    }

    final verweise = data[kVerweise];
    if (verweise is Map<String, dynamic>) {
      final hier = <String, String?>{
        for (final f in await db.select(db.artikelFotos).get())
          f.id: f.pruefsumme,
      };
      final t = db.artikelFotoInhalte;
      final mitBild = (await (db.selectOnly(t)..addColumns([t.fotoId]))
              .map((z) => z.read(t.fotoId)!)
              .get())
          .toSet();
      var fehlen = 0;
      for (final MapEntry(key: id, value: summe) in verweise.entries) {
        if (summe is! String) continue;
        if (hier[id] == summe && mitBild.contains(id)) {
          bleiben.add(id);
          continue;
        }
        Uint8List? bild;
        for (final ablage in ablagen) {
          bild = await ablage.lesen(summe);
          if (bild != null) break;
        }
        if (bild == null) {
          fehlen++;
        } else {
          bilder[id] = bild;
        }
      }
      if (fehlen > 0) {
        throw FormatException(
          'Dem Backup ${fehlen == 1 ? 'fehlt ein Foto' : 'fehlen $fehlen '
              'Fotos'} — die Bilder liegen im Ordner '
          '„${DateiAblage.ordnerName}" neben den Backups. Für einen '
          'anderen Rechner das Komplett-Backup nehmen oder den Ordner '
          'mitkopieren. Es wurde nichts verändert.',
        );
      }
    }

    return FotoTeil(
      fotos: [
        for (final f in alle)
          if (bilder.containsKey(f.id) || bleiben.contains(f.id)) f,
      ],
      bilder: bilder,
      bleiben: bleiben,
    );
  }

  /// Spielt die Fotos aus [teil] ein. Mit [ersetzen] sind danach genau
  /// sie in der Datenbank — sonst kommen sie zu den vorhandenen dazu.
  /// Bilder, die bleiben, werden nicht angefasst.
  static Future<void> einspielen(
    AppDatabase db,
    FotoTeil teil, {
    bool ersetzen = true,
  }) async {
    final ids = {for (final f in teil.fotos) f.id};
    final t = db.artikelFotoInhalte;
    if (ersetzen) {
      await db.delete(db.artikelFotos).go();
      final behalten = teil.bleiben.intersection(ids);
      if (behalten.isEmpty) {
        await db.delete(t).go();
      } else {
        await (db.delete(t)..where((i) => i.fotoId.isNotIn(behalten))).go();
      }
    }
    if (teil.fotos.isEmpty) return;
    await db.batch((b) {
      b.insertAllOnConflictUpdate(
        db.artikelFotos,
        [for (final f in teil.fotos) f.toCompanion(true)],
      );
    });
    // Einzeln: Ein Batch hielte alle Bilder zugleich im Speicher fest.
    for (final MapEntry(key: id, value: bild) in teil.bilder.entries) {
      if (!ids.contains(id)) continue;
      await db.into(t).insertOnConflictUpdate(
            ArtikelFotoInhalteCompanion.insert(fotoId: id, inhalt: bild),
          );
    }
  }

  /// Die Prüfsummen der Bilder, die der Datenteil [data] eines Backups
  /// nennt.
  static Set<String> verweiseIn(Map<String, dynamic> data) {
    final verweise = data[kVerweise];
    if (verweise is! Map<String, dynamic>) return const {};
    return {
      for (final v in verweise.values)
        if (v is String) v,
    };
  }
}
