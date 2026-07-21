import 'package:drift/drift.dart';

/// Plausibilitätsgrenzen für Maschinen-/Prozessparameter (Poka-Yoke).
///
/// Jede Zeile definiert für einen Parameter in einem Kontext die erlaubten
/// Bereiche. Der [kontext] ist entweder der Anlagen-Name aus dem
/// Maschinen-Katalog (z.B. "Füllmaschine B 1") oder eine Parametergruppe
/// (z.B. "BRATSTRASSE", "DAMPFTUNNEL") — so lassen sich sowohl
/// maschinenspezifische als auch gruppenweite Grenzen pflegen.
///
/// Zwei Stufen:
///  - HART  (hartMin/hartMax):  technisch unmöglich — Speichern blockiert.
///  - WEICH (weichMin/weichMax): ungewöhnlich — Warnung, Speichern erlaubt.
///
/// Alle vier Felder sind optional; nicht gesetzte Grenzen werden nicht
/// geprüft. Werte werden beim Prüfen numerisch verglichen (Parameter, die
/// keine Zahl sind, bleiben ungeprüft).
class ParameterGrenzen extends Table {
  /// UUID.
  TextColumn get id => text()();

  /// Anlagen-Name (machines.name) ODER Parametergruppe (z.B. "BRATSTRASSE").
  TextColumn get kontext => text()();

  /// Name des Parameters, wie er in product_step_parameters steht
  /// (z.B. "Bratzeit", "Temperatur", "Platte Oben 1"-Sammelname "Platten").
  TextColumn get parameterName => text()();

  /// Harte Untergrenze — darunter wird das Speichern blockiert.
  RealColumn get hartMin => real().nullable()();

  /// Harte Obergrenze — darüber wird das Speichern blockiert.
  RealColumn get hartMax => real().nullable()();

  /// Weiche Untergrenze — darunter erscheint eine Warnung.
  RealColumn get weichMin => real().nullable()();

  /// Weiche Obergrenze — darüber erscheint eine Warnung.
  RealColumn get weichMax => real().nullable()();

  /// Optionale Notiz (z.B. "Herstellerangabe Typenschild").
  TextColumn get notizen => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {kontext, parameterName},
      ];
}
