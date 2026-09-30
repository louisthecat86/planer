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
  });

  /// Produktionstag — alle Schritte der Kette liegen zunächst hier.
  final DateTime tag;
  final double fertigwareKg;
  final double rohwareKg;

  /// Anzahl der Abteilungsschritte, die im Board entstanden sind.
  final int schritte;
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
  await erstelleTasksAusPlan(
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
