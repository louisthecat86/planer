import 'package:drift/drift.dart';

import 'products.dart';

/// Historische Produktionsdaten je Artikel — eine Zeile pro produzierter
/// Charge. Quelle ist der Block „HISTORISCHE DATEN" der v3-Excel-Vorlage
/// (Datum, Kg Rohware, Kg Fertigware, Verlust %, Start-/Endzeit,
/// Produktionszeit, kg/h roh). Wird beim Import befüllt und beim Export
/// wieder in dieselbe Vorlage zurückgeschrieben — so haben App und Excel
/// in beide Richtungen denselben Stand.
///
/// Bewusst getrennt von [ProductionRuns]: Letztere hängen an einer
/// konkreten Task und füttern die schrittweise Lernlogik. Diese Tabelle
/// bildet dagegen die artikelweite Bilanz einer kompletten Produktion ab
/// (Rohware rein → Fertigware raus), genau wie das Excel-Blatt.
class ProductionHistory extends Table {
  TextColumn get id => text()();
  TextColumn get productId => text().references(Products, #id)();

  /// Produktionsdatum (tagesgenau).
  DateTimeColumn get datum => dateTime()();

  /// Eingesetzte Rohware in kg (Excel: „Kg Rohware").
  RealColumn get kgRohware => real().nullable()();

  /// Erzeugte Fertigware in kg (Excel: „Kg Fertigware").
  RealColumn get kgFertigware => real().nullable()();

  /// Garverlust als Anteil 0..1 (Excel: „Verlust %", dort als 0,25 gespeichert).
  /// = 1 − Fertig/Roh. Beim Import direkt übernommen, beim App-Erfassen
  /// aus Roh/Fertig berechnet.
  RealColumn get verlustAnteil => real().nullable()();

  /// Startzeit der Produktion als "HH:MM".
  TextColumn get startzeit => text().nullable()();

  /// Endzeit der Produktion als "HH:MM".
  TextColumn get endzeit => text().nullable()();

  /// Reine Produktionsdauer in Minuten (Excel: „Produktionszeit").
  RealColumn get produktionszeitMinuten => real().nullable()();

  /// kg Rohware pro Stunde (Excel: „kg/h roh").
  RealColumn get kgProStundeRoh => real().nullable()();

  /// kg Fertigware pro Stunde (optionale Excel-Spalte „kg/h gegart").
  RealColumn get kgProStundeGegart => real().nullable()();

  TextColumn get notizen => text().nullable()();

  /// Herkunft der Zeile: 'import' (aus Excel geladen) oder 'app' (in der
  /// App erfasst). Steuert später, wie beim Export zurückgeschrieben wird.
  TextColumn get quelle =>
      text().withDefault(const Constant('import'))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}