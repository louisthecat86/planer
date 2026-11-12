import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';

// Ansichten, die sich selbst aktuell halten: Ein Provider, der aus der
// Datenbank liest, lädt neu, sobald sich dort etwas ändert — egal, wo in
// der App die Änderung herkommt. „Aktualisieren"-Knöpfe braucht es damit
// nicht mehr, und niemand muss daran denken, nach einer Änderung die
// richtigen Provider von Hand anzustoßen.
//
// Gedacht für Provider, die nur lesen. Einer, der beim Laden selbst
// schreibt, würde sich damit immer wieder anstoßen.

/// Wie lange nach einer Änderung gewartet wird, bevor neu geladen wird.
/// Ein Import schreibt viele Zeilen kurz hintereinander — so wird daraus
/// ein Laden statt hunderter.
const Duration kNeuLadenNach = Duration(milliseconds: 100);

/// Die Tabellen der Planung und der Stammdaten: alles, woraus Übersicht,
/// Board, Bedarf, Auftragsbestand, Erfassung und Artikelliste rechnen.
///
/// Nicht dabei sind die Tabellen der Produktentwicklung (sie hat eigene,
/// laufend beobachtete Abfragen), die Bilder der Fotos und die
/// Einstellungen: Dort stehen auch Dinge wie die eingeklappte Leiste — die
/// sollen kein Board neu rechnen lassen. Wer die Kapazität einer Abteilung
/// ändert, tut das in den Einstellungen; Übersicht und Board laden beim
/// Öffnen ohnehin frisch.
List<TableInfo<Table, dynamic>> planungsTabellen(AppDatabase db) => [
      db.products,
      db.productSteps,
      db.productStepParameters,
      db.machines,
      db.machineParameterDefs,
      db.parameterGrenzen,
      db.zusatzzeiten,
      db.productionTasks,
      db.productionHistory,
      db.demands,
      db.tagesaufgaben,
      db.weekSnapshots,
      db.auftragsbestandArtikel,
      db.auftragsbestandPositionen,
      db.auftragsbestandArtikelVorher,
      db.auftragsbestandPositionenVorher,
    ];

/// Lässt den Provider hinter [ref] neu laden, sobald sich eine der
/// [tabellen] ändert — ohne Angabe die [planungsTabellen].
///
/// Am Anfang des Providers aufrufen. Während neu geladen wird, behält die
/// Ansicht ihren bisherigen Stand; es flackert nichts.
void neuLadenBeiAenderung(
  Ref<Object?> ref,
  AppDatabase db, {
  Iterable<TableInfo<Table, dynamic>>? tabellen,
}) {
  Timer? gleich;
  final abo = db
      .tableUpdates(
    TableUpdateQuery.onAllTables(tabellen ?? planungsTabellen(db)),
  )
      .listen((_) {
    gleich?.cancel();
    gleich = Timer(kNeuLadenNach, ref.invalidateSelf);
  });
  ref.onDispose(() {
    gleich?.cancel();
    abo.cancel();
  });
}
