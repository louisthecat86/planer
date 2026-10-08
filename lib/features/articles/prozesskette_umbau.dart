import '../../core/database/database.dart';
import '../../core/services/prozesskette_service.dart';

// Ziehen und Ablegen in der Prozesskette eines Artikels: was ein Zug auf
// einem Ziel bewirkt.
//
// Rein rechnerisch und ohne Oberfläche — die Ansicht
// (article_prozesskette.dart) fragt hier, ob ein Ziel einen Zug annimmt und
// was dann geschieht. So lassen sich die Regeln testen, ohne Widgets zu
// ziehen.
//
// Die Kette besteht aus Stationen: zusammenhängenden Schritten derselben
// Abteilung, genau so, wie die Planung sie bündelt.

/// Was gerade gezogen wird.
sealed class KettenZug {
  const KettenZug();
}

/// Eine Anlage (ein Schritt) der Kette.
class SchrittZug extends KettenZug {
  const SchrittZug(this.step);

  final ProductStep step;
}

/// Eine ganze Station — [index] in der Liste der Stationen.
class StationsZug extends KettenZug {
  const StationsZug(this.index);

  final int index;
}

/// Eine Anlage aus dem Katalog — sie wird als neuer Schritt eingefügt.
class AnlagenZug extends KettenZug {
  const AnlagenZug(this.maschine);

  final Machine maschine;
}

/// Wohin abgelegt wird.
sealed class KettenZiel {
  const KettenZiel();
}

/// Auf eine Anlage: davor einfügen. Innerhalb derselben Station wie beim
/// Umsortieren einer Liste — nach rechts gezogen landet sie dahinter.
class ZielAnlage extends KettenZiel {
  const ZielAnlage(this.step, this.station);

  final ProductStep step;

  /// Die Station, in der [step] steht.
  final int station;
}

/// Auf eine Station: ans Ende der Station. Eine gezogene Station rückt an
/// diese Stelle.
class ZielStation extends KettenZiel {
  const ZielStation(this.station);

  final int station;
}

/// In die Lücke vor Station [vorStation] (gleich der Anzahl der Stationen:
/// hinter der letzten). Eine Anlage behält dort ihre Abteilung und bildet
/// eine eigene Station — oder schließt an die Nachbarstation derselben
/// Abteilung an. Eine Anlage aus dem Katalog kommt mit ihrer
/// Stammabteilung.
class ZielLuecke extends KettenZiel {
  const ZielLuecke(this.vorStation);

  final int vorStation;
}

/// Was ein Ablegen an der Kette ändert.
sealed class KettenUmbau {
  const KettenUmbau();
}

/// Neue Abfolge aller Schritte, dazu Abteilungswechsel einzelner Schritte.
class NeueAbfolge extends KettenUmbau {
  const NeueAbfolge(this.ids, this.abteilungen);

  /// Alle aktiven Schritte in der neuen Abfolge.
  final List<String> ids;

  /// Schritt-ID → neue Abteilung (dbValue).
  final Map<String, String> abteilungen;
}

/// Eine Anlage als neuen Schritt einfügen.
class AnlageEinfuegen extends KettenUmbau {
  const AnlageEinfuegen({
    required this.index,
    required this.abteilung,
    required this.maschine,
  });

  /// Position in der Kette (0 = ganz vorn).
  final int index;

  /// Abteilung, für die die Anlage bei diesem Artikel arbeitet (dbValue).
  final String abteilung;
  final Machine maschine;
}

/// Die Kette eines Artikels, wie sie gerade angezeigt wird — und was ein
/// Zug auf einem Ziel an ihr ändert.
class Kettenbau {
  Kettenbau({required this.productId, required this.steps})
      : stationen = ProzesskettenService.bloecke(steps);

  final String productId;

  /// Aktive Schritte in Prozessreihenfolge.
  final List<ProductStep> steps;

  /// Die Stationen: zusammenhängende Schritte derselben Abteilung.
  final List<List<ProductStep>> stationen;

  List<String> get _ids => [for (final s in steps) s.id];

  /// Position von [stepId] in der Kette — -1, wenn es ihn nicht gibt.
  int indexVon(String stepId) => steps.indexWhere((s) => s.id == stepId);

  /// Station, in der [stepId] steht — -1, wenn es ihn nicht gibt.
  int stationVon(String stepId) =>
      stationen.indexWhere((b) => b.any((s) => s.id == stepId));

  /// Position in der Kette, an der Station [k] beginnt — für [k] gleich der
  /// Anzahl der Stationen das Ende der Kette.
  int grenzeVor(int k) {
    var n = 0;
    for (var i = 0; i < k && i < stationen.length; i++) {
      n += stationen[i].length;
    }
    return n;
  }

  static bool _gleich(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Was [zug] auf [ziel] bewirkt — null, wenn sich nichts ändern würde
  /// oder das Ziel nicht (mehr) zur Kette passt. Dient zugleich als
  /// Prüfung, ob ein Ziel den Zug annimmt.
  KettenUmbau? umbau(KettenZug zug, KettenZiel ziel) {
    // Ziele kommen aus der angezeigten Kette; passt eins nicht mehr, wird
    // es abgelehnt statt zu werfen.
    final gueltig = switch (ziel) {
      ZielAnlage(:final step, :final station) =>
        station >= 0 &&
            station < stationen.length &&
            stationen[station].any((s) => s.id == step.id),
      ZielStation(:final station) =>
        station >= 0 && station < stationen.length,
      ZielLuecke(:final vorStation) =>
        vorStation >= 0 && vorStation <= stationen.length,
    };
    if (!gueltig) return null;

    switch (zug) {
      case AnlagenZug(:final maschine):
        final (index, abteilung) = switch (ziel) {
          ZielAnlage(:final step, :final station) => (
              indexVon(step.id),
              stationen[station].first.abteilung,
            ),
          ZielStation(:final station) => (
              grenzeVor(station + 1),
              stationen[station].first.abteilung,
            ),
          ZielLuecke(:final vorStation) => (
              grenzeVor(vorStation),
              maschine.abteilung,
            ),
        };
        return AnlageEinfuegen(
          index: index,
          abteilung: abteilung,
          maschine: maschine,
        );

      case StationsZug(index: final von):
        if (von < 0 || von >= stationen.length) return null;
        final nach = switch (ziel) {
          ZielAnlage(:final station) => station,
          ZielStation(:final station) => station,
          ZielLuecke(:final vorStation) =>
            von < vorStation ? vorStation - 1 : vorStation,
        };
        if (nach == von) return null;
        final neu = [...stationen];
        final gezogen = neu.removeAt(von);
        neu.insert(nach.clamp(0, neu.length), gezogen);
        return NeueAbfolge(
          [
            for (final b in neu)
              for (final s in b) s.id,
          ],
          const {},
        );

      case SchrittZug(:final step):
        final von = indexVon(step.id);
        if (von < 0) return null;
        final ids = _ids..removeAt(von);
        String? abteilung;
        switch (ziel) {
          case ZielAnlage(step: final aufAnlage, :final station):
            if (aufAnlage.id == step.id) return null;
            abteilung = stationen[station].first.abteilung;
            // In derselben Station wie beim Umsortieren einer Liste: auf
            // den Platz der Ziel-Anlage. Aus einer anderen Station: davor.
            final position = stationVon(step.id) == station
                ? indexVon(aufAnlage.id)
                : ids.indexOf(aufAnlage.id);
            ids.insert(position, step.id);
          case ZielStation(:final station):
            final rest = [
              for (final s in stationen[station])
                if (s.id != step.id) s,
            ];
            if (rest.isEmpty) return null;
            abteilung = rest.first.abteilung;
            ids.insert(ids.indexOf(rest.last.id) + 1, step.id);
          case ZielLuecke(:final vorStation):
            final grenze = grenzeVor(vorStation);
            ids.insert(von < grenze ? grenze - 1 : grenze, step.id);
        }
        final abteilungen = {
          if (abteilung != null && abteilung != step.abteilung)
            step.id: abteilung,
        };
        if (abteilungen.isEmpty && _gleich(ids, _ids)) return null;
        return NeueAbfolge(ids, abteilungen);
    }
  }

  /// Schreibt [umbau] über den [ProzesskettenService]. Wirft wie dieser:
  /// einen [StateError], wenn die Kette voll ist, einen [ArgumentError],
  /// wenn sie sich inzwischen geändert hat.
  Future<void> schreibe(AppDatabase db, KettenUmbau umbau) async {
    switch (umbau) {
      case NeueAbfolge(:final ids, :final abteilungen):
        await ProzesskettenService.ordneNeu(
          db,
          productId,
          ids,
          abteilungen: abteilungen,
        );
      case AnlageEinfuegen(:final index, :final abteilung, :final maschine):
        await ProzesskettenService.fuegeEin(
          db,
          productId: productId,
          abteilung: abteilung,
          index: index,
          maschineId: maschine.id,
          maschine: maschine.name,
        );
    }
  }
}
