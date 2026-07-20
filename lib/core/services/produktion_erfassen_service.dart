import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';

/// Erfasst eine abgeschlossene Produktion als Zeile in der artikelweiten
/// [ProductionHistory] — derselbe Topf, der auch aus der Excel importiert und
/// wieder dorthin exportiert wird. Es gibt damit nur EINE Historien-Quelle.
///
/// Aus den Eingaben (Datum, Rohmenge, Fertigmenge, Start-/Endzeit) werden die
/// abgeleiteten Kennzahlen berechnet — mit exakt denselben Formeln wie im
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

  /// Speichert die Produktion als neue History-Zeile mit `quelle = 'app'`.
  /// Alle abgeleiteten Werte werden hier berechnet, damit App und Excel
  /// denselben Stand haben.
  static Future<void> erfasse({
    required AppDatabase db,
    required String productId,
    required DateTime datum,
    required double kgRohware,
    required double kgFertigware,
    String? startzeit,
    String? endzeit,
    String? notizen,
  }) async {
    final dauerMin = produktionszeitMinuten(startzeit, endzeit);
    final dauerStd = (dauerMin != null && dauerMin > 0) ? dauerMin / 60 : null;

    final verlust =
        kgRohware > 0 ? (1 - kgFertigware / kgRohware) : null;
    final kgHRoh = dauerStd != null ? kgRohware / dauerStd : null;
    final kgHGegart = dauerStd != null ? kgFertigware / dauerStd : null;

    await db.into(db.productionHistory).insert(
          ProductionHistoryCompanion.insert(
            id: const Uuid().v4(),
            productId: productId,
            datum: datum,
            kgRohware: Value(kgRohware),
            kgFertigware: Value(kgFertigware),
            verlustAnteil: Value(verlust),
            startzeit: Value(startzeit),
            endzeit: Value(endzeit),
            produktionszeitMinuten: Value(dauerMin),
            kgProStundeRoh: Value(kgHRoh),
            kgProStundeGegart: Value(kgHGegart),
            notizen: Value(notizen),
            quelle: const Value('app'),
          ),
        );
  }
}
