import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/features/shell/app_rahmen.dart';
import 'package:produktion_planer/features/shell/schnellsuche.dart';

/// Tests für die Schnellsuche (Strg+K): Bereiche vor Artikeln, was mit der
/// Eingabe beginnt vorn, Artikel auch über die Nummer. Alles erfunden.
void main() {
  const bereiche = [
    SchnellZiel(titel: 'Übersicht', icon: Icons.home, route: 'home'),
    SchnellZiel(titel: 'Bedarf', icon: Icons.list, route: 'bedarf'),
    SchnellZiel(titel: 'Planungsboard', icon: Icons.view_week, route: 'board'),
    SchnellZiel(titel: 'Artikel', icon: Icons.inventory, route: 'articles'),
  ];
  const artikel = [
    SchnellZiel(
      titel: 'Testbratwurst grob',
      unter: '900010',
      icon: Icons.inventory,
      artikelId: 'p1',
    ),
    SchnellZiel(
      titel: 'Grobe Testwurst',
      unter: '900020',
      icon: Icons.inventory,
      artikelId: 'p2',
    ),
    SchnellZiel(
      titel: 'Testschinken',
      unter: '810099',
      icon: Icons.inventory,
      artikelId: 'p3',
    ),
  ];

  List<String> titel(String eingabe) => [
        for (final z in schnellTreffer(eingabe, bereiche, artikel)) z.titel,
      ];

  test('ohne Eingabe: alle Bereiche, kein Artikel', () {
    expect(titel(''), ['Übersicht', 'Bedarf', 'Planungsboard', 'Artikel']);
    expect(titel('   '), hasLength(4));
  });

  test('Bereiche stehen vor Artikeln', () {
    expect(titel('b'), [
      // Beginnt mit „b".
      'Bedarf',
      // Enthält „b".
      'Übersicht',
      'Planungsboard',
      // Dann die Artikel: erst, wo ein Wort mit „b" beginnt.
      'Testbratwurst grob',
      'Grobe Testwurst',
    ]);
  });

  test('was mit der Eingabe beginnt, steht vorn', () {
    expect(titel('grob'), ['Grobe Testwurst', 'Testbratwurst grob']);
    expect(titel('plan'), ['Planungsboard']);
  });

  test('Artikel über die Nummer', () {
    expect(titel('9000'), ['Testbratwurst grob', 'Grobe Testwurst']);
    expect(titel('900020'), ['Grobe Testwurst']);
    // Mitten in der Nummer zählt auch.
    expect(titel('0099'), ['Testschinken']);
  });

  test('mehrere Worte: jedes muss vorkommen', () {
    expect(titel('test grob'), ['Testbratwurst grob', 'Grobe Testwurst']);
    expect(titel('wurst 9000 grob'), ['Testbratwurst grob', 'Grobe Testwurst']);
    expect(titel('schinken grob'), isEmpty);
  });

  test('Groß und klein ist egal; nichts gefunden bleibt leer', () {
    expect(titel('BEDARF'), ['Bedarf']);
    expect(titel('xyz'), isEmpty);
  });

  test('höchstens zwölf Artikel', () {
    final viele = [
      for (var i = 0; i < 40; i++)
        SchnellZiel(
          titel: 'Testartikel $i',
          unter: '${700000 + i}',
          icon: Icons.inventory,
          artikelId: 'a$i',
        ),
    ];
    expect(
      schnellTreffer('testartikel', bereiche, viele),
      hasLength(kSchnellsucheArtikelMax),
    );
  });

  group('Bereiche der Leiste', () {
    test('Planer: die ersten neun mit Strg+1 … Strg+9', () {
      final ziele = schnellZiele(entwicklung: false);

      expect(ziele.first.titel, 'Übersicht');
      expect(ziele.first.kuerzel, 'Strg+1');
      expect(ziele[1].titel, 'Auftragsbestand');
      expect(ziele[4].titel, 'Planungsboard');
      expect(ziele[4].kuerzel, 'Strg+5');
      expect(ziele[8].kuerzel, 'Strg+9');
      expect(ziele[9].kuerzel, isNull);
      expect(ziele.last.titel, 'Einstellungen');
      // Jeder Bereich hat eine Route — und keine doppelt.
      expect(ziele.every((z) => z.route != null), isTrue);
      expect({for (final z in ziele) z.route}, hasLength(ziele.length));
    });

    test('Produktentwicklung: ihre Bereiche und der Weg zurück', () {
      final ziele = schnellZiele(entwicklung: true);

      expect(ziele.map((z) => z.titel), contains('Zutaten'));
      expect(ziele.map((z) => z.titel), contains('Zum Planer'));
      expect(ziele.map((z) => z.titel), isNot(contains('Planungsboard')));
      expect({for (final z in ziele) z.route}, hasLength(ziele.length));
    });
  });
}
