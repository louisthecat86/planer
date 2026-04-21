import 'package:drift/drift.dart';

import 'product_steps.dart';

/// Flexible Parameter eines einzelnen [ProductSteps]-Schritts.
///
/// Jeder Schritt kann beliebig viele Parameter haben, gruppiert nach
/// Anlagen-Typ (z.B. „FÜLLMASCHINE / VERBUFA", „BRATSTRASSE",
/// „DAMPFTUNNEL", „SCHOCKFROSTER") — oder frei benennbar als „CUSTOM"
/// für die ZUSÄTZLICHE-PARAMETER-Slots der Vorlage.
///
/// Diese Tabelle löst das starre FieldSpec-Schema ab: Neue Parameter
/// erfordern keine Schema-Migration mehr, nur einen Eintrag in der
/// Vorlage.
@DataClassName('ProductStepParameter')
class ProductStepParameters extends Table {
  TextColumn get id => text()();

  /// Referenz auf den Schritt, zu dem der Parameter gehört.
  TextColumn get stepId => text().references(ProductSteps, #id)();

  /// Gruppenname (z.B. „FÜLLMASCHINE / VERBUFA", „BRATSTRASSE",
  /// „DAMPFTUNNEL", „SCHOCKFROSTER", „CUSTOM").
  /// Dient primär der Anzeige in der UI, keine Validierung.
  TextColumn get parameterGruppe => text()();

  /// Parameter-Name wie in Spalte A der v3-Vorlage (z.B. „Takte",
  /// „Volumen (cm³)", „Temp Oben (°C)").
  TextColumn get parameterName => text()();

  /// Wert als Freitext. Zahlen werden nicht typsicher gespeichert, weil
  /// die Vorlage heterogene Werte erlaubt („4:00", „230", „Papaya, 3mm").
  /// Die UI / Auswertung interpretiert je nach Parameter-Name.
  TextColumn get wert => text().nullable()();

  /// Reihenfolge innerhalb der Gruppe (Sortierung in der UI).
  IntColumn get reihenfolge => integer().withDefault(const Constant(0))();

  /// `true` wenn aus dem ZUSÄTZLICHE-PARAMETER-Block der Vorlage
  /// (vom Nutzer selbst benannt), `false` bei den Standard-Parametern.
  BoolColumn get istCustom =>
      boolean().withDefault(const Constant(false))();

  // ── Sync-Felder ───────────────────────────────────────────────────────

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}