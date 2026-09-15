import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:produktion_planer/core/database/database.dart';

/// Legt eine frische, leere Datenbank im Arbeitsspeicher an.
///
/// `NativeDatabase.memory()` braucht kein Dateisystem und keinen
/// Flutter-Kontext. Jeder Test bekommt seine eigene Instanz — es gibt also
/// keinen Zustand, der von einem Test in den nächsten überschwappt.
///
/// `onCreate` der App legt dabei dasselbe Schema an wie auf dem echten
/// Rechner, inklusive `PRAGMA foreign_keys = ON` aus `beforeOpen`. Genau
/// das ist der Punkt: Ein Test, der gegen ein anderes Schema läuft, prüft
/// nichts Nützliches.
AppDatabase testDatenbank() => AppDatabase.forTesting(NativeDatabase.memory());

/// Legt einen Artikel an und gibt seine ID zurück.
Future<String> seedArtikel(
  AppDatabase db, {
  required String id,
  required String nummer,
  String? bezeichnung,
}) async {
  await db.into(db.products).insert(
        ProductsCompanion.insert(
          id: id,
          artikelnummer: nummer,
          artikelbezeichnung: bezeichnung ?? 'Testartikel $nummer',
        ),
      );
  return id;
}

/// Legt einen Produktionsschritt an.
///
/// [basisMengeKg] und [basisDauerMinuten] bilden das Leistungsverhältnis:
/// „für [basisMengeKg] Kilo brauchen wir [basisDauerMinuten] Minuten".
/// Daraus skaliert die App die Dauer für jede andere Menge.
Future<void> seedSchritt(
  AppDatabase db, {
  required String id,
  required String productId,
  required int reihenfolge,
  required String abteilung,
  double basisMengeKg = 100,
  double basisDauerMinuten = 60,
  int basisMitarbeiter = 2,
  double? ausbeuteFaktor,
  String? maschineId,
  String? prozessschritt,
}) async {
  await db.into(db.productSteps).insert(
        ProductStepsCompanion.insert(
          id: id,
          productId: productId,
          reihenfolge: reihenfolge,
          abteilung: abteilung,
          basisMengeKg: basisMengeKg,
          basisDauerMinuten: basisDauerMinuten,
          basisMitarbeiter: basisMitarbeiter,
          ausbeuteFaktor: Value(ausbeuteFaktor),
          maschineId: Value(maschineId),
          prozessschritt: Value(prozessschritt),
        ),
      );
}

/// Legt eine Anlage an, die als eigene Planungsspur zählt.
Future<void> seedAnlage(
  AppDatabase db, {
  required String id,
  required String name,
  required String abteilung,
  double kapazitaetMinutenProTag = 540,
  bool istPlanungsressource = true,
}) async {
  await db.into(db.machines).insert(
        MachinesCompanion.insert(
          id: id,
          name: name,
          abteilung: abteilung,
          istPlanungsressource: Value(istPlanungsressource),
          kapazitaetMinutenProTag: Value(kapazitaetMinutenProTag),
        ),
      );
}

/// Legt eine Navision-Katalogzeile an.
///
/// [mengeInAuftrag] minus [lagerbestand] ergibt den offenen Bedarf — in der
/// Basiseinheit, nicht zwingend in Kilogramm.
Future<void> seedNavisionArtikel(
  AppDatabase db, {
  required String nummer,
  String beschreibung = 'Navision-Testartikel',
  String basiseinheit = 'KG',
  double lagerbestand = 0,
  double mengeInAuftrag = 0,
  double mengeInFa = 0,
}) async {
  await db.into(db.navisionArtikelKatalog).insert(
        NavisionArtikelKatalogCompanion.insert(
          nummer: nummer,
          beschreibung: Value(beschreibung),
          basiseinheit: Value(basiseinheit),
          lagerbestand: Value(lagerbestand),
          mengeInAuftrag: Value(mengeInAuftrag),
          mengeInFa: Value(mengeInFa),
        ),
      );
}

/// Legt eine Bedarfsposition an.
Future<void> seedBedarf(
  AppDatabase db, {
  required String id,
  required String productId,
  required double mengeKgFertig,
  bool manuellErledigt = false,
}) async {
  await db.into(db.demands).insert(
        DemandsCompanion.insert(
          id: id,
          productId: productId,
          mengeKgFertig: mengeKgFertig,
          manuellErledigt: Value(manuellErledigt),
        ),
      );
}

/// Liest den Navision-Katalog als Liste.
Future<List<NavisionArtikel>> ladeNavisionArtikel(AppDatabase db) =>
    db.select(db.navisionArtikelKatalog).get();
