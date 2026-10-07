import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';

/// Was sich aus einer erfassten Produktion ableitet.
class ProduktionsKennzahlen {
  const ProduktionsKennzahlen({
    this.produktionszeitMinuten,
    this.verlustAnteil,
    this.kgProStundeRoh,
    this.kgProStundeGegart,
  });

  /// Ende − Start in Minuten; über Mitternacht korrekt.
  final double? produktionszeitMinuten;

  /// 1 − Fertig / Roh.
  final double? verlustAnteil;

  /// Rohware je Stunde Produktionszeit.
  final double? kgProStundeRoh;

  /// Fertigware je Stunde Produktionszeit.
  final double? kgProStundeGegart;
}

/// Erfasst eine Produktion als Zeile in der artikelweiten
/// [ProductionHistory] — derselbe Topf, der auch aus der Excel importiert
/// und wieder dorthin exportiert wird. Es gibt damit nur EINE
/// Historien-Quelle und nur EINE Rechnung dafür: Das Formular im Artikel
/// und die Produktionserfassung nutzen beide diesen Service.
///
/// Aus den Eingaben (Datum, Rohmenge, Fertigmenge, Start-/Endzeit) werden
/// die abgeleiteten Kennzahlen berechnet — mit denselben Formeln wie im
/// Excel-Block „HISTORISCHE DATEN":
///   Verlust      = 1 − Fertig / Roh
///   Produktionszeit (min) = Ende − Start
///   kg/h roh     = Roh    / (Produktionszeit in Stunden)
///   kg/h gegart  = Fertig / (Produktionszeit in Stunden)
class ProduktionErfassenService {
  const ProduktionErfassenService._();

  /// Wandelt "HH:MM" in Minuten seit Mitternacht. Gibt null bei ungültigem
  /// Format zurück.
  static int? zeitZuMinuten(String? hhmm) {
    if (hhmm == null) return null;
    final teile = hhmm.trim().split(':');
    if (teile.length != 2) return null;
    final h = int.tryParse(teile[0]);
    final m = int.tryParse(teile[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return h * 60 + m;
  }

  /// Produktionsdauer in Minuten aus Start/Ende. Über-Mitternacht wird
  /// berücksichtigt (Ende < Start ⇒ +24 h).
  static double? produktionszeitMinuten(String? start, String? ende) {
    final s = zeitZuMinuten(start);
    final e = zeitZuMinuten(ende);
    if (s == null || e == null) return null;
    var diff = e - s;
    if (diff < 0) diff += 24 * 60;
    return diff.toDouble();
  }

  /// Die abgeleiteten Kennzahlen einer Produktion. Fehlt etwas, bleibt die
  /// betroffene Kennzahl leer.
  static ProduktionsKennzahlen kennzahlen({
    required double? kgRohware,
    double? kgFertigware,
    String? startzeit,
    String? endzeit,
  }) {
    final dauerMin = produktionszeitMinuten(startzeit, endzeit);
    final dauerStd = (dauerMin != null && dauerMin > 0) ? dauerMin / 60 : null;
    final roh = (kgRohware != null && kgRohware > 0) ? kgRohware : null;
    return ProduktionsKennzahlen(
      produktionszeitMinuten: dauerMin,
      verlustAnteil:
          (roh != null && kgFertigware != null) ? 1 - kgFertigware / roh : null,
      kgProStundeRoh: (roh != null && dauerStd != null) ? roh / dauerStd : null,
      kgProStundeGegart: (kgFertigware != null && dauerStd != null)
          ? kgFertigware / dauerStd
          : null,
    );
  }

  /// Speichert eine Produktion: neu mit `quelle = 'app'`, oder — mit
  /// [vorhandeneId] — als Änderung einer bestehenden Zeile. Alle
  /// abgeleiteten Werte werden hier berechnet, damit App und Excel
  /// denselben Stand haben.
  static Future<void> speichere({
    required AppDatabase db,
    required String productId,
    required DateTime datum,
    required double kgRohware,
    double? kgFertigware,
    String? startzeit,
    String? endzeit,
    String? notizen,
    String? vorhandeneId,
  }) async {
    String? leerZuNull(String? s) {
      final t = s?.trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    final start = leerZuNull(startzeit);
    final ende = leerZuNull(endzeit);
    final k = kennzahlen(
      kgRohware: kgRohware,
      kgFertigware: kgFertigware,
      startzeit: start,
      endzeit: ende,
    );
    final tag = DateTime(datum.year, datum.month, datum.day);

    if (vorhandeneId != null) {
      await (db.update(db.productionHistory)
            ..where((h) => h.id.equals(vorhandeneId)))
          .write(
        ProductionHistoryCompanion(
          datum: Value(tag),
          kgRohware: Value(kgRohware),
          kgFertigware: Value(kgFertigware),
          verlustAnteil: Value(k.verlustAnteil),
          startzeit: Value(start),
          endzeit: Value(ende),
          produktionszeitMinuten: Value(k.produktionszeitMinuten),
          kgProStundeRoh: Value(k.kgProStundeRoh),
          kgProStundeGegart: Value(k.kgProStundeGegart),
          notizen: Value(leerZuNull(notizen)),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return;
    }

    await db.into(db.productionHistory).insert(
          ProductionHistoryCompanion.insert(
            id: const Uuid().v4(),
            productId: productId,
            datum: tag,
            kgRohware: Value(kgRohware),
            kgFertigware: Value(kgFertigware),
            verlustAnteil: Value(k.verlustAnteil),
            startzeit: Value(start),
            endzeit: Value(ende),
            produktionszeitMinuten: Value(k.produktionszeitMinuten),
            kgProStundeRoh: Value(k.kgProStundeRoh),
            kgProStundeGegart: Value(k.kgProStundeGegart),
            notizen: Value(leerZuNull(notizen)),
            quelle: const Value('app'),
          ),
        );
  }
}
