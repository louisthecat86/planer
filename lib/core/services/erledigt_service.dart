import 'package:drift/drift.dart';

import '../database/database.dart';
import '../utils/datum.dart';

/// Warum ein Auftrag als erledigt gilt.
enum Erledigt {
  /// Von Hand abgehakt — im Board oder in der Tagesansicht.
  abgehakt,

  /// Die Produktion ist erfasst. Das macht alle Schritte ihrer Kette
  /// erledigt, ohne dass jemand etwas abhaken muss.
  erfasst,
}

/// Abhaken von Aufträgen und die Frage, welche Aufträge erledigt sind.
///
/// Erledigt ist ein Auftrag auf zwei Wegen:
/// - **Von Hand abgehakt**: Status `fertig` am Auftrag. Jeder Schritt
///   einer Kette für sich — die Zerlegung ist vielleicht am Montag
///   fertig, die Bratstraße erst am Dienstag.
/// - **Produktion erfasst**: Dann ist die ganze Kette erledigt. Zugeordnet
///   wird wie in der Produktionserfassung und im Auftragsbestand — über
///   den Artikel und den Tag der Wurzel der Kette. Das ist der Tag, den
///   die Produktionserfassung beim Erfassen vorschlägt.
///
/// „Erfasst" wird nicht gespeichert, sondern bei jedem Laden aus der
/// Historie bestimmt. Wird eine Erfassung gelöscht oder umdatiert, stimmt
/// die Anzeige deshalb sofort wieder — ohne zweiten Stand, der aus dem
/// Tritt geraten könnte.
class ErledigtService {
  const ErledigtService._();

  /// Status eines abgehakten Auftrags. Der Wert ist in der Tabelle seit
  /// jeher vorgesehen (`geplant`, `in_arbeit`, `fertig`, `storniert`).
  static const String statusErledigt = 'fertig';

  /// Status eines offenen Auftrags.
  static const String statusOffen = 'geplant';

  /// Hakt die Aufträge [taskIds] ab — oder nimmt den Haken zurück.
  ///
  /// Stornierte Aufträge bleiben, wie sie sind: Ein Haken soll keinen
  /// stornierten Auftrag wieder ins Board holen.
  static Future<void> abhaken(
    AppDatabase db,
    Iterable<String> taskIds, {
    required bool erledigt,
  }) async {
    final ids = taskIds.toSet();
    if (ids.isEmpty) return;
    final jetzt = DateTime.now();
    await db.transaction(() async {
      for (final block in _bloecke(ids)) {
        await (db.update(db.productionTasks)
              ..where((t) => t.id.isIn(block))
              ..where((t) => t.status.isNotIn(const ['storniert'])))
            .write(
          ProductionTasksCompanion(
            status: Value(erledigt ? statusErledigt : statusOffen),
            updatedAt: Value(jetzt),
          ),
        );
      }
    });
  }

  /// Je Auftrag aus [auftraege] die Wurzel seiner Kette — den Auftrag
  /// selbst, wenn er keinen Vorgänger hat.
  ///
  /// Ketten sind verkettete Listen: Jeder Schritt zeigt über
  /// `parentTaskId` auf seinen Vorgänger. Fehlende Vorgänger werden Ebene
  /// für Ebene nachgeladen — auch gelöschte und stornierte. Wird im Board
  /// nur die Zerlegung gelöscht, bleibt sie trotzdem die Wurzel; so
  /// rechnet auch der Auftragsbestand.
  static Future<Map<String, ProductionTask>> wurzeln(
    AppDatabase db,
    Iterable<ProductionTask> auftraege,
  ) async {
    final liste = auftraege.toList();
    final bekannt = {for (final t in liste) t.id: t};

    Set<String> fehlendeVorgaenger(Iterable<ProductionTask> tasks) => {
          for (final t in tasks)
            if (t.parentTaskId case final p? when !bekannt.containsKey(p)) p,
        };

    var fehlend = fehlendeVorgaenger(liste);
    // Sicherung gegen Kreise in den Daten — echte Ketten sind kurz.
    for (var tiefe = 0; fehlend.isNotEmpty && tiefe < 20; tiefe++) {
      final geladen = <ProductionTask>[];
      for (final block in _bloecke(fehlend)) {
        geladen.addAll(
          await (db.select(db.productionTasks)
                ..where((t) => t.id.isIn(block)))
              .get(),
        );
      }
      for (final t in geladen) {
        bekannt[t.id] = t;
      }
      fehlend = fehlendeVorgaenger(geladen);
    }

    final ergebnis = <String, ProductionTask>{};
    for (final start in liste) {
      var aktuell = start;
      final weg = <String>{start.id};
      while (true) {
        final elternId = aktuell.parentTaskId;
        final eltern = elternId == null ? null : bekannt[elternId];
        // Kein Vorgänger (mehr) oder ein Kreis: Hier ist die Wurzel.
        if (eltern == null || !weg.add(eltern.id)) break;
        aktuell = eltern;
      }
      ergebnis[start.id] = aktuell;
    }
    return ergebnis;
  }

  /// Die IDs der Aufträge aus [auftraege], deren Produktion erfasst ist:
  /// Für den Artikel gibt es am Tag der Wurzel ihrer Kette eine
  /// Erfassung.
  ///
  /// [wurzelVon]: schon ermittelte Wurzeln (siehe [wurzeln]) — spart das
  /// zweite Hochlaufen, wenn der Aufrufer sie ohnehin braucht.
  static Future<Set<String>> erfassteAuftraege(
    AppDatabase db,
    Iterable<ProductionTask> auftraege, {
    Map<String, ProductionTask>? wurzelVon,
  }) async {
    final liste = auftraege.toList();
    if (liste.isEmpty) return <String>{};
    final wurzelVonAuftrag = wurzelVon ?? await wurzeln(db, liste);

    DateTime? von;
    DateTime? bis;
    final produkte = <String>{};
    for (final w in wurzelVonAuftrag.values) {
      final tag = tagOhneZeit(w.datum);
      if (von == null || tag.isBefore(von)) von = tag;
      if (bis == null || tag.isAfter(bis)) bis = tag;
      produkte.add(w.productId);
    }
    if (von == null || bis == null) return <String>{};
    final abTag = von;
    final bisExkl = tagPlus(bis, 1);

    final erfasst = <String>{};
    for (final block in _bloecke(produkte)) {
      final zeilen = await (db.select(db.productionHistory)
            ..where((h) => h.deletedAt.isNull())
            ..where((h) => h.productId.isIn(block))
            ..where((h) => h.datum.isBiggerOrEqualValue(abTag))
            ..where((h) => h.datum.isSmallerThanValue(bisExkl)))
          .get();
      for (final h in zeilen) {
        erfasst.add(_schluessel(h.productId, h.datum));
      }
    }

    return {
      for (final t in liste)
        if (wurzelVonAuftrag[t.id] case final w?
            when erfasst.contains(_schluessel(w.productId, w.datum)))
          t.id,
    };
  }

  /// Je Auftrag aus [auftraege], ob und warum er erledigt ist. Offene
  /// Aufträge fehlen in der Map.
  ///
  /// Ist die Produktion erfasst, zählt das vor dem Haken: Den nimmt man
  /// dann nicht mehr zurück, die Erfassung entscheidet.
  static Future<Map<String, Erledigt>> stand(
    AppDatabase db,
    Iterable<ProductionTask> auftraege, {
    Map<String, ProductionTask>? wurzelVon,
  }) async {
    final liste = auftraege.toList();
    final erfasst =
        await erfassteAuftraege(db, liste, wurzelVon: wurzelVon);
    return {
      for (final t in liste)
        if (erfasst.contains(t.id))
          t.id: Erledigt.erfasst
        else if (t.status == statusErledigt)
          t.id: Erledigt.abgehakt,
    };
  }

  static String _schluessel(String productId, DateTime d) =>
      '$productId|${d.year}-${d.month}-${d.day}';

  /// SQLite begrenzt die Zahl der Platzhalter je Abfrage.
  static Iterable<List<String>> _bloecke(Iterable<String> ids) sync* {
    final liste = ids.toList();
    for (var i = 0; i < liste.length; i += 400) {
      yield liste.sublist(i, i + 400 > liste.length ? liste.length : i + 400);
    }
  }
}
