import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../../core/database/database.dart';
import '../../core/services/auftragsbestand_deckung.dart';
import '../whiteboard/whiteboard_provider.dart';

/// Was beim Einplanen aus dem Auftragsbestand angelegt wurde.
class Einplanung {
  const Einplanung({
    required this.tag,
    required this.fertigwareKg,
    required this.rohwareKg,
    required this.schritte,
    this.wurzelId,
  });

  /// Produktionstag — alle Schritte der Kette liegen zunächst hier.
  final DateTime tag;
  final double fertigwareKg;
  final double rohwareKg;

  /// Anzahl der Abteilungsschritte, die im Board entstanden sind.
  final int schritte;

  /// ID des ersten Schritts der neuen Kette — für das Datenblatt.
  final String? wurzelId;
}

/// Plant [fertigKg] Fertigware für die Auftragszeilen [bezuege] ein: eine
/// komplette Kette über alle Abteilungen am [tag], an der Wurzel die
/// Zuordnung zu den Zeilen.
///
/// Alle Schritte landen auf demselben Tag. Wer Kutter und Bratstraße auf
/// verschiedene Tage legen will, verschiebt die Schritte danach im Board —
/// die Zuordnung bleibt dabei erhalten, sie hängt an der Kette.
///
/// Wirft einen [StateError], wenn der Artikel keine Prozessschritte hat.
Future<Einplanung> planeAuftragszeilen({
  required AppDatabase db,
  required String productId,
  required double fertigKg,
  required DateTime tag,
  required List<AuftragsBezug> bezuege,
}) async {
  final start = DateTime(tag.year, tag.month, tag.day);
  final plan = await berechneSchrittPlan(
    db: db,
    productId: productId,
    mengeKg: fertigKg,
    startTag: start,
  );
  if (plan.schritte.isEmpty) {
    throw StateError(
      'Für diesen Artikel sind noch keine Prozessschritte gepflegt. Erst '
      'in der Artikelliste die Schritte anlegen, dann einplanen.',
    );
  }
  final wurzelId = await erstelleTasksAusPlan(
    db: db,
    productId: productId,
    schritte: plan.schritte,
    fertigMengeKg: fertigKg,
    auftragsBezuege: bezuege,
  );
  return Einplanung(
    tag: start,
    fertigwareKg: fertigKg,
    rohwareKg: plan.rohwareKg,
    schritte: plan.schritte.length,
    wurzelId: wurzelId,
  );
}

/// Übergibt die Auftragszeilen [bezuege] an den Planungsvorschlag: Es
/// entsteht ein Bedarf über [fertigKg] Fertigware — ein Planungsauftrag —
/// mit [termin] als spätestem Produktionstag.
///
/// Im Board steht danach noch nichts. Die Zeilen sind im Auftragsbestand
/// vorgemerkt, bis der Planungsvorschlag den Auftrag in einen Tag legt und
/// der Tag übernommen wird; dann trägt die Produktion die Zeilen.
///
/// Gibt die ID des neuen Bedarfs zurück.
Future<String> uebergebeAnPlanungsvorschlag({
  required AppDatabase db,
  required String productId,
  required double fertigKg,
  required DateTime termin,
  required List<AuftragsBezug> bezuege,
}) async {
  final id = const Uuid().v4();
  final beschreibung = beschreibeBezuege(bezuege);
  await db.into(db.demands).insert(
        DemandsCompanion.insert(
          id: id,
          productId: productId,
          mengeKgFertig: fertigKg,
          termin: Value(DateTime(termin.year, termin.month, termin.day)),
          quelle: const Value(kQuelleAuftragsbestand),
          notizen: Value(beschreibung.isEmpty ? null : beschreibung),
          auftragsZeilen: Value(AuftragsBezug.kodiere(bezuege)),
        ),
      );
  return id;
}

/// Hebt eine Vormerkung auf: Der Planungsauftrag wird gelöscht, seine
/// Zeilen sind im Auftragsbestand wieder offen. Was davon schon im Board
/// steht, bleibt dort und trägt seine Zeilen weiter.
Future<void> hebeVormerkungAuf({
  required AppDatabase db,
  required String bedarfId,
}) async {
  final jetzt = DateTime.now();
  await (db.update(db.demands)..where((d) => d.id.equals(bedarfId))).write(
    DemandsCompanion(deletedAt: Value(jetzt), updatedAt: Value(jetzt)),
  );
}

/// Vorschlag für den Produktionstag: der Arbeitstag vor dem ersten
/// gewählten Versandtag — Samstag und Sonntag zählen nicht —, aber nicht
/// vor heute.
DateTime vorschlagProduktionstag(DateTime ersterVersand, DateTime heute) {
  final h = DateTime(heute.year, heute.month, heute.day);
  var tag = DateTime(
    ersterVersand.year,
    ersterVersand.month,
    ersterVersand.day - 1,
  );
  while (tag.weekday == DateTime.saturday || tag.weekday == DateTime.sunday) {
    tag = DateTime(tag.year, tag.month, tag.day - 1);
  }
  return tag.isBefore(h) ? h : tag;
}
