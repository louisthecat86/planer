import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/features/entwicklung/spezifikation/betriebs_spuren.dart';

import 'helpers/test_db.dart';

/// Tests für die Spuren aus dem Betrieb: eine Liste für alle Produkte,
/// ohne Enthaltenes, nie Sulfit.
void main() {
  test('wirksame Spuren: Betrieb plus Produkt, ohne Enthaltenes und Sulfit',
      () {
    expect(
      wirksameSpuren(
        betrieb: {'gluten', 'eier', 'soja', 'senf', 'sulfit'},
        eigene: {'sellerie'},
        enthalten: ['gluten', 'eier'],
      ),
      ['soja', 'sellerie', 'senf'],
    );
    expect(wirksameSpuren(betrieb: {}, enthalten: const []), isEmpty);
  });

  test('speichern und laden, Unbekanntes fällt weg', () async {
    final AppDatabase db = testDatenbank();
    addTearDown(db.close);
    expect(await ladeBetriebsSpuren(db), isEmpty);
    await speichereBetriebsSpuren(db, {'senf', 'gluten', 'milch'});
    expect(await ladeBetriebsSpuren(db), {'gluten', 'milch', 'senf'});
    await speichereBetriebsSpuren(db, {});
    expect(await ladeBetriebsSpuren(db), isEmpty);
    expect(betriebsSpurenAusText('["senf","quark","keine"]'), {'senf'});
    expect(betriebsSpurenAusText('kaputt'), isEmpty);
  });
}
