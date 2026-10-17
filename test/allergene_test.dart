import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/constants/artikel_merkmale.dart';

/// Tests für die Allergenliste: alle 14 Hauptallergene der LMIV und ihre
/// Rangfolge für die Planung.
void main() {
  test('alle 14 Hauptallergene und „keine"', () {
    final werte = [for (final m in kAllergene) m.dbValue];
    expect(werte.first, kAllergenKeine);
    expect(werte.length, 15);
    expect(werte.toSet().length, 15, reason: 'kein Eintrag doppelt');
    expect(
      werte,
      containsAll(<String>[
        'gluten',
        'krebstiere',
        'eier',
        'fisch',
        'erdnuesse',
        'soja',
        'milch',
        'schalenfruechte',
        'sellerie',
        'senf',
        'sesam',
        'sulfit',
        'lupinen',
        'weichtiere',
      ]),
    );
  });

  test('die fünf seltenen laufen nach allen bisherigen', () {
    final sulfit = allergenRang('sulfit');
    for (final selten in [
      'krebstiere',
      'fisch',
      'erdnuesse',
      'lupinen',
      'weichtiere',
    ]) {
      expect(allergenRang(selten), greaterThan(sulfit), reason: selten);
    }
    // Die bisherige Reihenfolge bleibt, wie sie war.
    expect(allergenRang('gluten'), lessThan(allergenRang('eier')));
    expect(allergenRang('senf'), lessThan(sulfit));
  });

  test('das späteste Allergen bestimmt den Rang', () {
    expect(allergenRang(null), 0);
    expect(allergenRang('keine'), 0);
    expect(allergenRang('gluten,weichtiere'), allergenRang('weichtiere'));
  });

  test('Klartexte hin und zurück', () {
    expect(
      merkmaleLabel('fisch,erdnuesse', kAllergene),
      'Fisch, Erdnüsse',
    );
    expect(
      merkmaleAusLabels('Erdnüsse; Lupinen', kAllergene),
      'erdnuesse,lupinen',
    );
  });
}
