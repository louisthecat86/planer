import 'package:erfassung/stand.dart';
import 'package:erfassung_format/erfassung_format.dart';
import 'package:flutter_test/flutter_test.dart';

import 'beispiel.dart';

/// Der Stand der Erfassung ohne Oberfläche: Paket öffnen, Produktionen
/// und Werte erfassen, das Ergebnis — und dass alles ein Schließen der
/// App übersteht. Alles erfunden.
void main() {
  final jetzt = DateTime(2026, 11, 10, 9);

  ErfassteProduktion erfasst(String id, {String artikelId = 'a1'}) =>
      ErfassteProduktion(
        produktionId: id,
        artikelId: artikelId,
        artikel: 'Grillwurst',
        datum: DateTime(2026, 11, 10),
        rohKg: 1260,
        fertigKg: 1005,
        start: '06:00',
        ende: '13:30',
        kuerzel: 'AB',
        erfasstAm: jetzt,
      );

  test('Produktionen: offen, erfasst, ohne Plan, gelöscht', () {
    final s = Erfassungsstand()..paketOeffnen(beispielPaket());
    expect([for (final p in s.offen) p.id], ['t1', 't2']);
    expect(s.hatErfasstes, isFalse);

    s
      ..produktionErfassen(erfasst('t1'))
      ..produktionErfassen(erfasst('frei-1', artikelId: 'a2'));
    expect([for (final p in s.offen) p.id], ['t2']);
    expect([for (final e in s.frei) e.produktionId], ['frei-1']);
    expect(s.ungesichert, isTrue);

    s.gespeichertAm = jetzt;
    expect(s.ungesichert, isFalse);
    s.produktionLoeschen('frei-1');
    expect(s.frei, isEmpty);
    // Jede Änderung macht das gespeicherte Ergebnis alt.
    expect(s.ungesichert, isTrue);
  });

  test('Werte: ändern, zurück auf den Stand vom PC, löschen', () {
    final s = Erfassungsstand(kuerzel: 'AB')..paketOeffnen(beispielPaket());
    final artikel = s.paket!.artikelMit('a1')!;
    final schritt = artikel.schrittMit('s1')!;
    final gewicht = schritt.feldMit('s:füllgewicht')!;
    final programm = schritt.feldMit('s:programm')!;
    void setze(PaketFeld feld, String? neu) => s.wertSetzen(
          artikel: artikel,
          schritt: schritt,
          feld: feld,
          neu: neu,
          jetzt: jetzt,
        );

    expect(s.wertVon(schritt, gewicht), '120');
    setze(gewicht, ' 125 ');
    setze(programm, 'P4');
    expect(s.wertVon(schritt, gewicht), '125');
    expect(s.istGeaendert(schritt, gewicht), isTrue);
    expect(s.geaendertIn(schritt), 2);
    final w = s.werte[wertSchluessel('s1', 's:füllgewicht')]!;
    expect(
      (w.alt, w.neu, w.kuerzel, w.art),
      ('120', '125', 'AB', FeldArt.steckbrief),
    );

    // Wieder der Wert aus dem Paket: nicht mehr geändert.
    setze(gewicht, '120');
    expect(s.istGeaendert(schritt, gewicht), isFalse);
    // Leeren ist auch eine Änderung …
    setze(gewicht, '');
    expect(s.wertVon(schritt, gewicht), isNull);
    expect(s.werte[wertSchluessel('s1', 's:füllgewicht')]!.neu, isNull);
    // … außer das Feld war schon leer.
    setze(programm, '  ');
    expect(s.istGeaendert(schritt, programm), isFalse);
  });

  test('das Ergebnis, und der Stand übersteht das Schließen', () {
    final s = Erfassungsstand(kuerzel: 'AB')..paketOeffnen(beispielPaket());
    expect(Erfassungsstand().ergebnis(jetzt), isNull);
    final artikel = s.paket!.artikelMit('a1')!;
    s
      ..produktionErfassen(erfasst('t1'))
      ..wertSetzen(
        artikel: artikel,
        schritt: artikel.schrittMit('s2')!,
        feld: artikel.schrittMit('s2')!.feldMit('t:Platte Oben 1')!,
        neu: '175',
        jetzt: jetzt,
      );
    final e = s.ergebnis(jetzt)!;
    expect(
      (e.paketId, e.produktionen.length, e.werte.length),
      ('paket-1', 1, 1),
    );
    expect(ErfassungsErgebnis.ausText(e.alsText()).werte.single.neu, '175');

    final wieder = Erfassungsstand.ausText(s.alsText());
    expect(wieder.alsText(), s.alsText());
    expect(wieder.kuerzel, 'AB');
    expect(wieder.paket!.id, 'paket-1');
    expect(wieder.produktionen.keys, ['t1']);

    // Dasselbe Paket noch einmal ändert nichts, ein anderes leert.
    expect(wieder.paketOeffnen(beispielPaket()), isFalse);
    expect(wieder.hatErfasstes, isTrue);
    expect(wieder.paketOeffnen(beispielPaket(id: 'paket-2')), isTrue);
    expect(wieder.hatErfasstes, isFalse);
    expect(wieder.kuerzel, 'AB');

    // Ein kaputter Stand: leer beginnen statt nicht starten.
    expect(Erfassungsstand.ausText('kaputt').paket, isNull);
    expect(Erfassungsstand.ausText('{"paket": {"id": 3}}').paket, isNull);
    expect(Erfassungsstand.ausText(null).hatErfasstes, isFalse);
  });
}
