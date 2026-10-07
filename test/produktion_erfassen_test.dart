import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/produktion_erfassen_service.dart';

import 'helpers/test_db.dart';

/// Tests für das Erfassen einer Produktion — die eine Rechnung, die das
/// Formular im Artikel und die Produktionserfassung gemeinsam nutzen.
/// Alle Daten sind erfunden.
void main() {
  late AppDatabase db;

  setUp(() => db = testDatenbank());
  tearDown(() => db.close());

  test('Kennzahlen auch über Mitternacht', () {
    // 22:00 bis 02:00 sind vier Stunden.
    final k = ProduktionErfassenService.kennzahlen(
      kgRohware: 400,
      kgFertigware: 300,
      startzeit: '22:00',
      endzeit: '02:00',
    );

    expect(k.produktionszeitMinuten, 240);
    expect(k.verlustAnteil, closeTo(0.25, 1e-9));
    expect(k.kgProStundeRoh, closeTo(100, 1e-9));
    expect(k.kgProStundeGegart, closeTo(75, 1e-9));
  });

  test('ohne Fertigware und Zeiten bleiben die Kennzahlen leer', () {
    final k = ProduktionErfassenService.kennzahlen(kgRohware: 400);

    expect(k.produktionszeitMinuten, isNull);
    expect(k.verlustAnteil, isNull);
    expect(k.kgProStundeRoh, isNull);
  });

  test('neu erfassen und danach ändern', () async {
    await seedArtikel(db, id: 'p1', nummer: '4001');

    await ProduktionErfassenService.speichere(
      db: db,
      productId: 'p1',
      datum: DateTime(2026, 9, 3, 14, 30),
      kgRohware: 500,
      kgFertigware: 400,
      startzeit: '06:00',
      endzeit: '10:00',
      notizen: '  ',
    );

    final neu = await db.select(db.productionHistory).getSingle();
    expect(neu.datum, DateTime(2026, 9, 3), reason: 'tagesgenau');
    expect(neu.quelle, 'app');
    expect(neu.verlustAnteil, closeTo(0.2, 1e-9));
    expect(neu.produktionszeitMinuten, 240);
    expect(neu.kgProStundeRoh, closeTo(125, 1e-9));
    expect(neu.notizen, isNull);

    await ProduktionErfassenService.speichere(
      db: db,
      productId: 'p1',
      datum: DateTime(2026, 9, 3),
      kgRohware: 500,
      kgFertigware: 450,
      startzeit: '',
      endzeit: '',
      vorhandeneId: neu.id,
    );

    final geaendert = await db.select(db.productionHistory).getSingle();
    expect(geaendert.verlustAnteil, closeTo(0.1, 1e-9));
    expect(geaendert.startzeit, isNull);
    expect(geaendert.produktionszeitMinuten, isNull);
    expect(geaendert.kgProStundeRoh, isNull);
  });
}
