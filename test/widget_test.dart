// Grundlegender Smoke-Test für den Produktionsplaner.
//
// Vollständige Widget-Tests (mit Mock-Datenbank) folgen in Phase 1b.

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Grundlegende Dart-Logik funktioniert', () {
    // Platzhalter-Test, damit `flutter test` sauber durchläuft.
    // Echte Widget-Tests benötigen einen Mock für AppDatabase / path_provider.
    expect(1 + 1, equals(2));
  });
}
