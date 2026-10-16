// `show Value` statt eines vollen drift-Imports: drift bringt eine eigene
// Klasse `Column` mit, die sich sonst mit der von Flutter beißen kann.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/providers/database_provider.dart';
import 'package:produktion_planer/features/articles/article_list_screen.dart';
import 'package:produktion_planer/features/articles/artikel_luecken.dart';
import 'package:produktion_planer/features/statistik/statistik_daten.dart';

import 'helpers/test_db.dart';

/// Tests für die Lücken in den Stammdaten: was einem Artikel fehlt, damit
/// die Planung richtig rechnet — nach ihren eigenen Regeln —, und dass
/// Artikelliste und Statistik genau dieselben Artikel zählen. Alle Daten
/// sind erfunden.
void main() {
  late AppDatabase db;
  late ProviderContainer container;
  final heute = DateTime(2026, 10, 16);

  setUp(() {
    db = testDatenbank();
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  var nummern = 7000;
  Future<void> artikel(
    String id, {
    String? gruppe,
    bool eingepflegt = true,
  }) =>
      db.into(db.products).insert(
            ProductsCompanion.insert(
              id: id,
              artikelnummer: '${++nummern}',
              artikelbezeichnung: 'Testartikel $id',
              produktgruppe: Value(gruppe),
              istEingepflegt: Value(eingepflegt),
            ),
          );

  var schritte = 0;
  Future<void> schritt(
    String productId,
    String abteilung, {
    bool mitLeistung = true,
  }) =>
      seedSchritt(
        db,
        id: 's${++schritte}',
        productId: productId,
        reihenfolge: schritte,
        abteilung: abteilung,
        basisMengeKg: mitLeistung ? 100 : 0,
        basisDauerMinuten: mitLeistung ? 60 : 0,
      );

  var erfassungen = 0;
  Future<void> produktion(
    String productId, {
    double? fertig,
    double? minuten,
    double? kgProStunde,
    DateTime? geloescht,
  }) =>
      db.into(db.productionHistory).insert(
            ProductionHistoryCompanion.insert(
              id: 'h${++erfassungen}',
              productId: productId,
              datum: DateTime(2026, 10, 12),
              kgRohware: const Value(100),
              kgFertigware: Value(fertig),
              produktionszeitMinuten: Value(minuten),
              kgProStundeRoh: Value(kgProStunde),
              deletedAt: Value(geloescht),
            ),
          );

  /// Artikel mit allen Arten von Lücken — und ohne.
  Future<void> legeArtikelAn() async {
    // Gepflegt: Gruppe, Schritte mit Leistungsdaten, eine Ausbeute.
    await artikel('voll', gruppe: 'bruehwurst');
    await schritt('voll', 'zerlegung');
    await schritt('voll', 'verpackung');
    await produktion('voll', fertig: 80);

    // Aus Navision angelegt, sonst nichts.
    await artikel('stub', eingepflegt: false);

    // Die Bratstraße ohne Leistungsdaten, keine Produktion mit Zeit.
    await artikel('platz', gruppe: 'braten');
    await schritt('platz', 'zerlegung');
    await schritt('platz', 'bratstrasse', mitLeistung: false);
    await produktion('platz', fertig: 70);

    // Ebenso — aber eine Produktion mit Zeit ersetzt die Leistungsdaten …
    await artikel('gemessen', gruppe: 'braten');
    await schritt('gemessen', 'bratstrasse', mitLeistung: false);
    await produktion('gemessen', fertig: 70, minuten: 50);

    // … auch nur mit kg/h.
    await artikel('kgh', gruppe: 'braten');
    await schritt('kgh', 'bratstrasse', mitLeistung: false);
    await produktion('kgh', fertig: 75, kgProStunde: 200);

    // Zwei Schritte einer Abteilung: Leistungsdaten am zweiten genügen.
    await artikel('block', gruppe: 'rohwurst');
    await schritt('block', 'wurstkueche', mitLeistung: false);
    await schritt('block', 'wurstkueche');
    await produktion('block', fertig: 90);

    // Mehr heraus als hinein zählt nicht als Ausbeute, Gelöschtes auch
    // nicht.
    await artikel('tipp', gruppe: 'braten');
    await schritt('tipp', 'zerlegung');
    await produktion('tipp', fertig: 120);
    await produktion('tipp', fertig: 80, geloescht: DateTime(2026, 10, 13));
  }

  test('je Artikel, was der Planung fehlt', () async {
    await legeArtikelAn();
    final daten = await ladeStatistik(
      db,
      StatistikZeitraum.quartal,
      heute: heute,
    );

    expect(
      {for (final a in daten.artikel.values) a.id: a.luecken},
      {
        'voll': <ArtikelLuecke>{},
        'stub': {
          ArtikelLuecke.nichtEingepflegt,
          ArtikelLuecke.ohneProduktgruppe,
          ArtikelLuecke.ohneSchritte,
          ArtikelLuecke.ohneAusbeute,
        },
        'platz': {ArtikelLuecke.zeitPlatzhalter},
        'gemessen': <ArtikelLuecke>{},
        'kgh': <ArtikelLuecke>{},
        'block': <ArtikelLuecke>{},
        'tipp': {ArtikelLuecke.ohneAusbeute},
      },
    );
  });

  test('Artikelliste und Statistik zählen dieselben Artikel', () async {
    await legeArtikelAn();
    final liste = await container.read(articlesProvider.future);
    final daten = await ladeStatistik(
      db,
      StatistikZeitraum.quartal,
      heute: heute,
    );

    expect(liste.length, daten.artikel.length);
    for (final info in liste) {
      expect(
        info.luecken,
        daten.artikel[info.product.id]?.luecken,
        reason: info.product.id,
      );
    }

    // Die Zahl in der Statistik ist die Länge der gefilterten Liste.
    final pflege = wertePflegeAus(daten.artikel, daten.aktiveArtikel);
    for (final zeile in pflege.zeilen) {
      expect(
        zeile.anzahl,
        liste.where((a) => a.luecken.contains(zeile.luecke)).length,
        reason: zeile.luecke.titel,
      );
    }
    expect(
      pflege.vollstaendig,
      liste.where((a) => a.luecken.isEmpty).length,
    );
  });
}
