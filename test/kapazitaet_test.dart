import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/constants/abteilungen.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/features/board/board_providers.dart';

import 'helpers/test_db.dart';

/// Tests für `tageskapazitaetJeAbteilung` — die Kapazitätsrechnung, die
/// sowohl das Wochenboard als auch die Wochen-Historie speist.
///
/// Hintergrund: Bis vor Kurzem rechnete die Historie mit einer festen
/// Kapazität JE ABTEILUNG. Seit die planbare Einheit die Anlage ist, war
/// das falsch — in der Verpackung laufen mehrere Anlagen parallel, dort
/// meldete die Auswertung dauerhaft Überbuchung, obwohl der Plan aufging.
///
/// Diese Tests halten den korrigierten Zustand fest.
void main() {
  late AppDatabase db;
  final montag = DateTime(2026, 9, 14);

  setUp(() => db = testDatenbank());
  tearDown(() => db.close());

  test('Abteilung ohne Anlagen bekommt die Regelarbeitszeit', () async {
    final kap = await tageskapazitaetJeAbteilung(db, wochenStart: montag);

    expect(kap[Abteilung.zerlegung.dbValue], 600);
  });

  test('drei Anlagen in der Verpackung ergeben die dreifache Kapazität',
      () async {
    await seedAnlage(
      db,
      id: 'm1',
      name: 'Multivac',
      abteilung: Abteilung.verpackung.dbValue,
    );
    await seedAnlage(
      db,
      id: 'm2',
      name: 'Tiefzieher',
      abteilung: Abteilung.verpackung.dbValue,
    );
    await seedAnlage(
      db,
      id: 'm3',
      name: 'Kleinbeutel',
      abteilung: Abteilung.verpackung.dbValue,
    );

    final kap = await tageskapazitaetJeAbteilung(db, wochenStart: montag);

    // Das ist der Kern von Q7: 3 × 600, nicht 600.
    expect(kap[Abteilung.verpackung.dbValue], 1800);
    // Andere Abteilungen bleiben davon unberührt.
    expect(kap[Abteilung.zerlegung.dbValue], 600);
  });

  test('abweichende Anlagen-Kapazitäten werden einzeln summiert', () async {
    await seedAnlage(
      db,
      id: 'm1',
      name: 'Anlage A',
      abteilung: Abteilung.verpackung.dbValue,
      kapazitaetMinutenProTag: 540,
    );
    await seedAnlage(
      db,
      id: 'm2',
      name: 'Anlage B',
      abteilung: Abteilung.verpackung.dbValue,
      // Halbe Schicht — zum Beispiel nur vormittags besetzt.
      kapazitaetMinutenProTag: 270,
    );

    final kap = await tageskapazitaetJeAbteilung(db, wochenStart: montag);

    expect(kap[Abteilung.verpackung.dbValue], 810);
  });

  test('Anlagen ohne Planungsressourcen-Kennzeichen zählen nicht', () async {
    await seedAnlage(
      db,
      id: 'm1',
      name: 'Nur Steckbrief',
      abteilung: Abteilung.verpackung.dbValue,
      istPlanungsressource: false,
    );

    final kap = await tageskapazitaetJeAbteilung(db, wochenStart: montag);

    // Keine Planungsspur → es bleibt bei der Sammelspur mit 600.
    expect(kap[Abteilung.verpackung.dbValue], 600);
  });

  test('jede Abteilung hat einen Wert — nie null oder 0', () async {
    final kap = await tageskapazitaetJeAbteilung(db, wochenStart: montag);

    for (final a in Abteilung.values) {
      expect(
        kap[a.dbValue],
        isNotNull,
        reason: 'Abteilung ${a.dbValue} ohne Kapazität — '
            'die Auslastung wäre eine Division durch null.',
      );
      expect(kap[a.dbValue]! > 0, isTrue);
    }
  });
}
