import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Rechenregeln
// ═══════════════════════════════════════════════════════════════════════════

/// Offener Bedarf = bestellte Menge minus Lagerbestand.
///
/// „Menge in FA" wird bewusst NICHT abgezogen: Sie steht in Navision nicht
/// für eine geplante Produktionsmenge, sondern für eine erste Anfrage
/// (z.B. pro Kutter), aus der erst manuell hochgerechnet wird. Sie
/// abzuziehen würde den Bedarf systematisch zu klein rechnen.
///
/// Achtung: Das Ergebnis trägt die Navision-Basiseinheit — nicht zwingend
/// Kilogramm. Die Umrechnung passiert erst bei der Übernahme.
double offenerBedarf(NavisionArtikel a) {
  final rest = a.mengeInAuftrag - a.lagerbestand;
  return rest > 0 ? rest : 0;
}

/// Ist die Basiseinheit des Artikels bereits Kilogramm?
bool istKg(NavisionArtikel a) =>
    (a.basiseinheit ?? '').toUpperCase() == 'KG';

/// Netto noch offener Bedarf in kg: Navision-Bedarf (in kg) minus die
/// bereits offen im Bedarf liegende Menge. null, wenn die kg-Menge mangels
/// Umrechnungsfaktor (noch) nicht bestimmbar ist.
double? nettoOffenKg(
  NavisionArtikel a,
  Map<String, double> imBedarfKg,
  Map<String, double> faktoren,
) {
  final double? navKg;
  if (istKg(a)) {
    navKg = offenerBedarf(a);
  } else {
    final f = faktoren[a.nummer];
    navKg = (f != null && f > 0) ? offenerBedarf(a) * f : null;
  }
  if (navKg == null) return null;
  final netto = navKg - (imBedarfKg[a.nummer] ?? 0);
  return netto > 0 ? netto : 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// Ergebnis
// ═══════════════════════════════════════════════════════════════════════════

/// Was bei einer Übernahme herausgekommen ist.
class BedarfUebernahmeErgebnis {
  const BedarfUebernahmeErgebnis({
    this.uebernommen = 0,
    this.angelegt = 0,
    this.uebersprungen = 0,
    this.bereitsGedeckt = 0,
  });

  /// Neu angelegte Bedarfspositionen.
  final int uebernommen;

  /// Neu erstellte Artikelmasken (als „nicht eingepflegt" markiert).
  final int angelegt;

  /// Übersprungen, weil kein Umrechnungsfaktor vorlag.
  final int uebersprungen;

  /// Übersprungen, weil der Bedarf bereits vollständig offen im Bedarf lag.
  final int bereitsGedeckt;
}

// ═══════════════════════════════════════════════════════════════════════════
// Service
// ═══════════════════════════════════════════════════════════════════════════

/// Überträgt Navision-Positionen in die Bedarfsliste der App.
///
/// Bewusst ohne jeden UI-Bezug: Die Rückfrage nach fehlenden
/// Umrechnungsfaktoren bleibt im Screen, hier liegt nur die Rechnung. Das
/// ist der Grund für diese Klasse — solange die Logik im Widget steckte,
/// war sie nur mit einem Widget-Test zu prüfen, und die Delta-Rechnung ist
/// genau die Stelle, an der ein stiller Fehler doppelte Produktionsaufträge
/// erzeugen würde.
class BedarfUebernahmeService {
  BedarfUebernahmeService(this._db);

  final AppDatabase _db;

  /// Gespeicherte Umrechnungsfaktoren samt der Einheit, für die sie
  /// erfasst wurden.
  ///
  /// Die Einheit gehört dazu, weil Navision die Basiseinheit eines Artikels
  /// ändern kann. Ein Faktor „0,48 kg je BTL" ist wertlos, sobald derselbe
  /// Artikel plötzlich in KT geführt wird — dann muss neu gefragt werden.
  Future<({Map<String, double> faktoren, Map<String, String> einheiten})>
      ladeUmrechnungen() async {
    final rows = await _db.select(_db.navisionUmrechnungen).get();
    return (
      faktoren: {for (final u in rows) u.nummer: u.kgJeEinheit},
      einheiten: {for (final u in rows) u.nummer: u.einheit},
    );
  }

  /// Welche Artikel brauchen (noch) einen Umrechnungsfaktor?
  List<NavisionArtikel> fehlendeUmrechnungen(
    List<NavisionArtikel> kandidaten,
    ({Map<String, double> faktoren, Map<String, String> einheiten}) bekannt,
  ) {
    return kandidaten
        .where(
          (a) =>
              !istKg(a) &&
              (bekannt.faktoren[a.nummer] == null ||
                  bekannt.einheiten[a.nummer] != (a.basiseinheit ?? '')),
        )
        .toList();
  }

  /// Merkt sich die vom Nutzer eingegebenen Faktoren.
  ///
  /// Alle auf einmal — ein Batch läuft in einer Transaktion. Halb
  /// gespeicherte Faktoren wären besonders tückisch, weil die App danach
  /// nicht mehr nachfragt.
  Future<void> merkeFaktoren(
    Map<String, double> faktoren,
    Map<String, String> einheitJeNummer,
  ) async {
    if (faktoren.isEmpty) return;
    final jetzt = DateTime.now();
    final zeilen = [
      for (final e in faktoren.entries)
        NavisionUmrechnungenCompanion.insert(
          nummer: e.key,
          einheit: einheitJeNummer[e.key] ?? '',
          kgJeEinheit: e.value,
          updatedAt: Value(jetzt),
        ),
    ];
    await _db.batch(
      (b) => b.insertAllOnConflictUpdate(_db.navisionUmrechnungen, zeilen),
    );
  }

  /// Überträgt [kandidaten] als Bedarf.
  ///
  /// Angelegt wird nur das DELTA: Liegt für einen Artikel schon etwas offen
  /// im Bedarf, wird nur die Differenz zum Navision-Stand ergänzt. Sonst
  /// entstünde bei jedem Import derselben Bestellung ein zweiter Auftrag —
  /// und produziert würde am Ende doppelt.
  ///
  /// Die Schleife rechnet nur; geschrieben wird danach in EINER Transaktion.
  /// Bräche das mittendrin ab, stünde eine halbe Bedarfsliste in der
  /// Datenbank, ohne dass jemand sehen könnte, wo sie abgerissen ist.
  Future<BedarfUebernahmeErgebnis> uebernehmen({
    required List<NavisionArtikel> kandidaten,
    required Map<String, double> faktorVon,
  }) async {
    final offen = kandidaten.where((a) => offenerBedarf(a) > 0).toList();
    if (offen.isEmpty) return const BedarfUebernahmeErgebnis();

    final vorhandene = await (_db.select(_db.products)
          ..where((p) => p.deletedAt.isNull()))
        .get();
    final idVonNummer = {for (final p in vorhandene) p.artikelnummer: p.id};

    final offeneDemands = await (_db.select(_db.demands)
          ..where((d) => d.deletedAt.isNull())
          ..where((d) => d.manuellErledigt.equals(false)))
        .get();
    final bereitsKgVon = <String, double>{};
    for (final d in offeneDemands) {
      bereitsKgVon[d.productId] =
          (bereitsKgVon[d.productId] ?? 0) + d.mengeKgFertig;
    }

    var angelegt = 0;
    var uebernommen = 0;
    var uebersprungen = 0;
    var bereitsGedeckt = 0;

    final neueProdukte = <ProductsCompanion>[];
    final neueBedarfe = <DemandsCompanion>[];

    for (final a in offen) {
      final menge = offenerBedarf(a);
      final double kg;
      if (istKg(a)) {
        kg = menge;
      } else {
        final f = faktorVon[a.nummer];
        if (f == null || f <= 0) {
          uebersprungen++;
          continue; // ohne Faktor keine belastbare kg-Menge
        }
        kg = menge * f;
      }

      var productId = idVonNummer[a.nummer];
      if (productId == null) {
        productId = const Uuid().v4();
        neueProdukte.add(
          ProductsCompanion.insert(
            id: productId,
            artikelnummer: a.nummer,
            artikelbezeichnung:
                a.beschreibung.isEmpty ? a.nummer : a.beschreibung,
            beschreibung: Value(a.beschreibung2),
            istEingepflegt: const Value(false),
          ),
        );
        // Sofort merken: Steht dieselbe Artikelnummer weiter unten noch
        // einmal in der Liste, darf die Maske kein zweites Mal entstehen —
        // die Spalte artikelnummer ist unique, sonst fällt die ganze
        // Transaktion.
        idVonNummer[a.nummer] = productId;
        angelegt++;
      }

      final bereits = bereitsKgVon[productId] ?? 0;
      final delta = kg - bereits;
      if (delta < 0.5) {
        bereitsGedeckt++;
        continue;
      }

      final abzug =
          bereits > 0 ? ' · abzügl. ${formatMenge(bereits)} kg im Bedarf' : '';
      final herkunft = istKg(a)
          ? 'Aus Navision · Auftrag ${formatMenge(a.mengeInAuftrag)} kg · '
              'Bestand ${formatMenge(a.lagerbestand)} kg$abzug'
          : 'Aus Navision · ${formatMenge(menge)} ${a.basiseinheit} '
              '× ${formatMenge(faktorVon[a.nummer] ?? 0)} kg$abzug';

      neueBedarfe.add(
        DemandsCompanion.insert(
          id: const Uuid().v4(),
          productId: productId,
          mengeKgFertig: delta,
          quelle: const Value('bestellung'),
          notizen: Value(herkunft),
        ),
      );
      bereitsKgVon[productId] = bereits + delta;
      uebernommen++;
    }

    await _db.transaction(() async {
      // Artikelmasken zuerst: Ohne sie zeigen die Bedarfszeilen auf nichts,
      // was die Planung darstellen könnte.
      if (neueProdukte.isNotEmpty) {
        await _db.batch((b) => b.insertAll(_db.products, neueProdukte));
      }
      if (neueBedarfe.isNotEmpty) {
        await _db.batch((b) => b.insertAll(_db.demands, neueBedarfe));
      }
    });

    return BedarfUebernahmeErgebnis(
      uebernommen: uebernommen,
      angelegt: angelegt,
      uebersprungen: uebersprungen,
      bereitsGedeckt: bereitsGedeckt,
    );
  }
}

/// Mengen ohne unnötige Nachkommastelle — „500" statt „500.0".
String formatMenge(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
