import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';

/// Änderungen an der Prozesskette eines Artikels: Schritte einfügen,
/// verschieben, entfernen, einer anderen Abteilung zuordnen — und die
/// Leistungsdaten je Abteilung.
///
/// Leistungsdaten („Menge X kg in Zeit Y") gelten für eine Abteilung,
/// gespeichert werden sie aber an einem ihrer Schritte — in
/// `basisMengeKg`/`basisDauerMinuten`. Es zählt der erste Schritt der
/// Abteilung, der Werte trägt (siehe `leistungsdatenVon`). Damit sie beim
/// Umbauen der Kette weder verloren gehen noch in eine andere Abteilung
/// wandern, laufen alle Umbauten hier durch.
///
/// „Abteilung" meint dabei immer einen zusammenhängenden Block: Kommt eine
/// Abteilung zweimal in der Kette vor, hat jeder Block seine eigenen
/// Leistungsdaten — genau wie bei der Planung.
class ProzesskettenService {
  const ProzesskettenService._();

  /// Höchstzahl aktiver Schritte je Artikel — so viele Schritt-Spalten
  /// (B..U) hat das Artikelblatt der Excel-Vorlage. Der Wert muss zum
  /// Excel-Export und zur Spaltengrenze im Import passen.
  ///
  /// Zehn reichten nicht: Allein die Bratstraße durchläuft bei panierten
  /// Artikeln bis zu acht Anlagen, dazu kommen Zerlegung, Waage und
  /// Verpackung.
  static const int maxSchritte = 20;

  /// Aktive Schritte des Artikels in Prozessreihenfolge.
  static Future<List<ProductStep>> schritte(
    AppDatabase db,
    String productId,
  ) {
    return (db.select(db.productSteps)
          ..where((s) => s.productId.equals(productId))
          ..where((s) => s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm.asc(s.reihenfolge)]))
        .get();
  }

  /// Der zusammenhängende Block derselben Abteilung, in dem [stepId] liegt.
  /// Leer, wenn es den Schritt in [schritte] nicht gibt.
  static List<ProductStep> blockVon(
    List<ProductStep> schritte,
    String stepId,
  ) {
    final i = schritte.indexWhere((s) => s.id == stepId);
    if (i < 0) return const [];
    final abteilung = schritte[i].abteilung;
    var von = i;
    while (von > 0 && schritte[von - 1].abteilung == abteilung) {
      von--;
    }
    var bis = i + 1;
    while (bis < schritte.length && schritte[bis].abteilung == abteilung) {
      bis++;
    }
    return schritte.sublist(von, bis);
  }

  /// Zerlegt die Kette in zusammenhängende Blöcke derselben Abteilung —
  /// genau so, wie die Planung sie bündelt.
  static List<List<ProductStep>> bloecke(List<ProductStep> schritte) {
    final ergebnis = <List<ProductStep>>[];
    for (final s in schritte) {
      if (ergebnis.isNotEmpty &&
          ergebnis.last.first.abteilung == s.abteilung) {
        ergebnis.last.add(s);
      } else {
        ergebnis.add([s]);
      }
    }
    return ergebnis;
  }

  static bool _hatWerte(ProductStep s) =>
      s.basisMengeKg > 0 && s.basisDauerMinuten > 0;

  /// Die Leistungsdaten eines Blocks: die des ersten Schritts, der welche
  /// trägt — wie `leistungsdatenVon` bei der Planung.
  static ({double mengeKg, double minuten})? _werteDes(
    List<ProductStep> block,
  ) {
    final traeger = block.where(_hatWerte).firstOrNull;
    if (traeger == null) return null;
    return (mengeKg: traeger.basisMengeKg, minuten: traeger.basisDauerMinuten);
  }

  static ProductStepsCompanion _werte(double mengeKg, double minuten) =>
      ProductStepsCompanion(
        basisMengeKg: Value(mengeKg),
        basisDauerMinuten: Value(minuten),
        // Spiegel der Menge für die Excel-Vorlage.
        mengeKg: Value(mengeKg),
        updatedAt: Value(DateTime.now()),
      );

  static ProductStepsCompanion _ohneWerte() => ProductStepsCompanion(
        basisMengeKg: const Value(0),
        basisDauerMinuten: const Value(0),
        mengeKg: const Value(null),
        updatedAt: Value(DateTime.now()),
      );

  static Future<void> _schreibe(
    AppDatabase db,
    String stepId,
    ProductStepsCompanion werte,
  ) {
    return (db.update(db.productSteps)..where((s) => s.id.equals(stepId)))
        .write(werte);
  }

  /// Hinterlegt die Leistungsdaten der Abteilung, zu der [stepId] gehört:
  /// am ersten Schritt ihres Blocks. Ältere Werte an anderen Schritten des
  /// Blocks werden entfernt — danach gibt es genau eine Stelle.
  static Future<void> setzeLeistungsdaten(
    AppDatabase db, {
    required String productId,
    required String stepId,
    required double mengeKg,
    required double minuten,
  }) async {
    if (!(mengeKg > 0) || !(minuten > 0)) {
      throw ArgumentError('Menge und Zeit müssen größer als 0 sein.');
    }
    await db.transaction(() async {
      final block = blockVon(await schritte(db, productId), stepId);
      if (block.isEmpty) return;
      await _schreibe(db, block.first.id, _werte(mengeKg, minuten));
      for (final s in block.skip(1)) {
        if (_hatWerte(s)) await _schreibe(db, s.id, _ohneWerte());
      }
    });
  }

  /// Entfernt die hinterlegten Leistungsdaten der Abteilung, zu der
  /// [stepId] gehört. Die Planung rechnet danach mit den erfassten
  /// Produktionen.
  static Future<void> entferneLeistungsdaten(
    AppDatabase db, {
    required String productId,
    required String stepId,
  }) async {
    await db.transaction(() async {
      final block = blockVon(await schritte(db, productId), stepId);
      for (final s in block) {
        if (_hatWerte(s)) await _schreibe(db, s.id, _ohneWerte());
      }
    });
  }

  /// Ordnet die Kette neu: [ids] sind alle aktiven Schritte in der neuen
  /// Abfolge. [abteilungen] ordnet einzelne Schritte einer anderen
  /// Abteilung zu (dbValue) — etwa den Rollenschneider aus dem Katalog der
  /// Zerlegung, der bei diesem Artikel an der Bratstraße arbeitet. Die
  /// Anlage bleibt dabei im Katalog ihrer Stammabteilung.
  ///
  /// Wirft einen [ArgumentError], wenn [ids] nicht genau die aktiven
  /// Schritte enthält — dann hat sich die Kette inzwischen geändert.
  static Future<void> ordneNeu(
    AppDatabase db,
    String productId,
    List<String> ids, {
    Map<String, String> abteilungen = const {},
  }) async {
    await db.transaction(() async {
      final vorher = await schritte(db, productId);
      final aktiv = {for (final s in vorher) s.id};
      if (ids.length != aktiv.length ||
          !ids.every(aktiv.contains) ||
          ids.toSet().length != ids.length) {
        throw ArgumentError(
          'Die Prozesskette hat sich inzwischen geändert — bitte neu laden.',
        );
      }
      await _schreibeKette(db, vorher, ids, abteilungen: abteilungen);
    });
  }

  /// Fügt einen Schritt in die Kette ein und gibt seine ID zurück.
  ///
  /// [index]: Position in der Kette (0 = ganz vorn). Ohne Angabe kommt der
  /// Schritt ans Ende der letzten Station seiner [abteilung] — gibt es die
  /// Abteilung noch nicht, ans Ende der Kette.
  ///
  /// Ein neuer Schritt bringt keine Leistungsdaten mit: Die gehören der
  /// Abteilung, in die er kommt.
  ///
  /// Wirft einen [StateError], wenn die Kette schon [maxSchritte] Schritte
  /// hat.
  static Future<String> fuegeEin(
    AppDatabase db, {
    required String productId,
    required String abteilung,
    int? index,
    String? maschineId,
    String? maschine,
    String? prozessschritt,
    int personen = 1,
  }) {
    return db.transaction(() async {
      final vorher = await schritte(db, productId);
      if (vorher.length >= maxSchritte) {
        throw StateError(
          'Höchstens $maxSchritte Schritte je Artikel — so viele Spalten hat '
          'das Artikelblatt der Excel-Vorlage. Bitte zuerst einen Schritt '
          'entfernen.',
        );
      }
      final ziel = (index ?? _endeDerAbteilung(vorher, abteilung))
          .clamp(0, vorher.length);

      final id = const Uuid().v4();
      await db.into(db.productSteps).insert(
            ProductStepsCompanion.insert(
              id: id,
              productId: productId,
              // Vorläufig — gleich danach wird die ganze Kette nummeriert.
              reihenfolge: vorher.length + 1,
              abteilung: abteilung,
              maschineId: Value(maschineId),
              // Legacy-Feld parallel pflegen — der Excel-Export liest beide.
              maschine: Value(maschine),
              prozessschritt: Value(prozessschritt),
              basisMengeKg: 0,
              basisDauerMinuten: 0,
              basisMitarbeiter: personen,
            ),
          );
      final neu = await (db.select(db.productSteps)
            ..where((s) => s.id.equals(id)))
          .getSingle();

      final ids = [for (final s in vorher) s.id]..insert(ziel, id);
      await _schreibeKette(db, vorher, ids, neue: [neu]);
      return id;
    });
  }

  /// Position hinter dem letzten Schritt von [abteilung] — ohne einen
  /// solchen das Ende der Kette.
  static int _endeDerAbteilung(List<ProductStep> kette, String abteilung) {
    final letzter = kette.lastIndexWhere((s) => s.abteilung == abteilung);
    return letzter < 0 ? kette.length : letzter + 1;
  }

  /// Nimmt [stepId] aus dem Prozess (Soft-Delete) und nummeriert die
  /// übrigen Schritte lückenlos neu. Trug er die Leistungsdaten seiner
  /// Abteilung, gehen sie an den nächsten Schritt der Abteilung über.
  static Future<void> entferneSchritt(AppDatabase db, String stepId) async {
    await db.transaction(() async {
      final schritt = await (db.select(db.productSteps)
            ..where((s) => s.id.equals(stepId)))
          .getSingleOrNull();
      if (schritt == null) return;
      final vorher = await schritte(db, schritt.productId);

      final jetzt = DateTime.now();
      await _schreibe(
        db,
        stepId,
        ProductStepsCompanion(
          deletedAt: Value(jetzt),
          updatedAt: Value(jetzt),
        ),
      );

      await _schreibeKette(
        db,
        vorher,
        [
          for (final s in vorher)
            if (s.id != stepId) s.id,
        ],
      );
    });
  }

  /// Stellt [stepId] in die Abteilung [neueAbteilung] (dbValue). Die
  /// Anlage bleibt im Katalog ihrer Stammabteilung — im Prozess dieses
  /// Artikels arbeitet sie für die neue.
  ///
  /// Leistungsdaten, die der Schritt für seine bisherige Abteilung trug,
  /// bleiben dort; in die neue Abteilung nimmt er keine mit — sie gehörten
  /// zu einer anderen Abteilung.
  static Future<void> wechsleAbteilung(
    AppDatabase db,
    String stepId,
    String neueAbteilung,
  ) async {
    await db.transaction(() async {
      final schritt = await (db.select(db.productSteps)
            ..where((s) => s.id.equals(stepId)))
          .getSingleOrNull();
      if (schritt == null || schritt.abteilung == neueAbteilung) return;
      final vorher = await schritte(db, schritt.productId);
      await _schreibeKette(
        db,
        vorher,
        [for (final s in vorher) s.id],
        abteilungen: {stepId: neueAbteilung},
      );
    });
  }

  /// Schreibt die Kette in der Abfolge [ids]: `reihenfolge` 1..n, die
  /// Abteilungen aus [abteilungen] — und die Leistungsdaten so, dass jeder
  /// Block die seines Vorgängers behält.
  ///
  /// Leistungsdaten gehören dem Block, nicht dem Schritt, der sie gerade
  /// trägt. Jeder neue Block übernimmt deshalb die Werte seines Vorgängers:
  /// des alten Blocks derselben Abteilung, der den größten Anteil seiner
  /// Schritte in ihn gibt — bei Gleichstand der mit mehr Schritten darin,
  /// dann der frühere. Hat der Vorgänger keine Werte, hat der neue Block
  /// auch keine. Das deckt alle Umbauten ab, ohne sie einzeln zu kennen:
  /// - Fällt der Schritt mit den Werten weg oder wandert er innerhalb des
  ///   Blocks, behält der Block seine Werte — am neuen ersten Schritt.
  /// - Zerfällt ein Block in zwei, haben danach beide die Werte.
  /// - Ein Schritt, der die Abteilung wechselt oder in einen anderen Block
  ///   zieht, nimmt nichts mit — auch nicht in einen Block derselben
  ///   Abteilung an anderer Stelle der Kette: Der behält seine eigenen
  ///   Werte (oder bleibt ohne).
  /// - Wird eine ganze Station verschoben, ziehen ihre Werte mit.
  ///
  /// Geschrieben wird nur, was sich wirklich ändert. [vorher] ist die Kette
  /// vor dem Umbau, [neue] sind gerade eingefügte Schritte.
  static Future<void> _schreibeKette(
    AppDatabase db,
    List<ProductStep> vorher,
    List<String> ids, {
    Map<String, String> abteilungen = const {},
    List<ProductStep> neue = const [],
  }) async {
    final alteBloecke = bloecke(vorher);
    final alteWerte = [for (final b in alteBloecke) _werteDes(b)];
    final alterBlock = <String, int>{
      for (var i = 0; i < alteBloecke.length; i++)
        for (final s in alteBloecke[i]) s.id: i,
    };

    final jeId = {
      for (final s in vorher) s.id: s,
      for (final s in neue) s.id: s,
    };
    String abteilungVon(String id) => abteilungen[id] ?? jeId[id]!.abteilung;

    // Neue Blöcke — wie `bloecke`, nur auf den neuen Abteilungen.
    final neueBloecke = <List<String>>[];
    for (final id in ids) {
      if (neueBloecke.isNotEmpty &&
          abteilungVon(neueBloecke.last.first) == abteilungVon(id)) {
        neueBloecke.last.add(id);
      } else {
        neueBloecke.add([id]);
      }
    }

    // Je neuem Block die Werte seines Vorgängers, am ersten Schritt.
    final sollWerte = <String, ({double mengeKg, double minuten})>{};
    for (final block in neueBloecke) {
      final abteilung = abteilungVon(block.first);
      // Je altem Block: wie viele seiner Schritte jetzt in diesem stehen.
      // Auch Blöcke ohne Werte zählen — wer in eine Station ohne
      // Leistungsdaten zieht, bringt keine mit.
      final treffer = <int, int>{};
      for (final id in block) {
        final alt = alterBlock[id];
        // Neu eingefügt, oder der Schritt kommt aus einer anderen
        // Abteilung: Er zählt nicht.
        if (alt == null || alteBloecke[alt].first.abteilung != abteilung) {
          continue;
        }
        treffer[alt] = (treffer[alt] ?? 0) + 1;
      }
      int? vorgaenger;
      for (final alt in treffer.keys) {
        final bisher = vorgaenger;
        if (bisher == null) {
          vorgaenger = alt;
          continue;
        }
        // Anteile (Treffer je Blockgröße) über Kreuz verglichen, statt zu
        // teilen.
        final anteil = treffer[alt]! * alteBloecke[bisher].length;
        final anteilBisher = treffer[bisher]! * alteBloecke[alt].length;
        final mehrTreffer = treffer[alt]! > treffer[bisher]!;
        final gleichViele = treffer[alt] == treffer[bisher];
        if (anteil > anteilBisher ||
            (anteil == anteilBisher &&
                (mehrTreffer || (gleichViele && alt < bisher)))) {
          vorgaenger = alt;
        }
      }
      final werte = vorgaenger == null ? null : alteWerte[vorgaenger];
      if (werte != null) sollWerte[block.first] = werte;
    }

    final jetzt = DateTime.now();
    for (var i = 0; i < ids.length; i++) {
      final s = jeId[ids[i]]!;
      final abteilung = abteilungVon(s.id);
      final werte = sollWerte[s.id];
      final werteAendern = werte == null
          ? _hatWerte(s)
          : s.basisMengeKg != werte.mengeKg ||
              s.basisDauerMinuten != werte.minuten;
      if (s.reihenfolge == i + 1 &&
          s.abteilung == abteilung &&
          !werteAendern) {
        continue;
      }
      await _schreibe(
        db,
        s.id,
        ProductStepsCompanion(
          reihenfolge: Value(i + 1),
          abteilung: Value(abteilung),
          basisMengeKg: werteAendern
              ? Value(werte?.mengeKg ?? 0.0)
              : const Value.absent(),
          basisDauerMinuten: werteAendern
              ? Value(werte?.minuten ?? 0.0)
              : const Value.absent(),
          // Spiegel der Menge für die Excel-Vorlage.
          mengeKg: werteAendern ? Value(werte?.mengeKg) : const Value.absent(),
          updatedAt: Value(jetzt),
        ),
      );
    }
  }
}
