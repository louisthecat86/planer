import 'dart:convert';
import 'dart:typed_data';

import 'package:erfassung/stand.dart';
import 'package:erfassung_format/erfassung_format.dart';
import 'package:flutter_test/flutter_test.dart';

import 'beispiel.dart';

/// Der Stand der Erfassung ohne Oberfläche: Paket öffnen, Produktionen,
/// Werte und Fotos erfassen, das Ergebnis — und dass alles ein Schließen
/// der App übersteht. Alles erfunden.
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

  test('Fotos: aus der Produktion und als Muster, im Ergebnis mit Bild', () {
    final s = Erfassungsstand(kuerzel: 'AB')..paketOeffnen(beispielPaket());
    final a = s.fotoAnlegen(
      id: neueFotoId(jetzt, 7),
      jetzt: jetzt,
      artikelId: 'a1',
      artikel: 'Grillwurst',
      produktionId: 't1',
    );
    expect(a.art, FotoArt.produktion);
    expect(a.kuerzel, 'AB');
    final m = s.fotoAnlegen(
      id: neueFotoId(jetzt.add(const Duration(minutes: 5)), 7),
      jetzt: jetzt.add(const Duration(minutes: 5)),
      // Ohne Artikel ein Musterfoto — eine Produktion gehört dann nicht
      // dazu.
      produktionId: 't1',
      bezeichnung: '  Pfeffer grob ',
    );
    expect(m.art, FotoArt.muster);
    expect(m.bezeichnung, 'Pfeffer grob');
    expect(m.produktionId, isNull);
    expect(a.id, isNot(m.id));

    // Noch ist nichts aufgenommen — nur gemerkt, wozu die Kamera offen ist.
    s.fotoWartend = a;
    expect(s.hatErfasstes, isFalse);

    s
      ..fotoHinzu(a, groesse: 300)
      ..fotoHinzu(m, groesse: 200)
      ..fotoWartend = null;
    expect(s.hatErfasstes, isTrue);
    expect(s.ungesichert, isTrue);
    expect([for (final f in s.fotoListe) f.id], [m.id, a.id]);
    expect([for (final f in s.fotosVon('a1')) f.id], [a.id]);
    expect(s.fotosVon('a2'), isEmpty);
    expect([for (final f in s.musterfotos) f.id], [m.id]);
    expect(s.fotoBytes, 500);

    // Im Ergebnis stehen die Fotos, deren Bild es gibt — das älteste
    // zuerst.
    final bild = Uint8List.fromList([0xFF, 0xD8, 0xFF, 1, 2, 3]);
    final nurEins = s.ergebnis(jetzt, bilder: {a.id: bild})!;
    expect([for (final f in nurEins.fotos) f.id], [a.id]);
    expect(nurEins.fotos.single.daten, bild);
    expect(nurEins.fotos.single.groesse, bild.length);
    expect((jsonDecode(nurEins.alsText()) as Map)['version'], 2);
    final beide = s.ergebnis(jetzt, bilder: {a.id: bild, m.id: bild})!;
    expect([for (final f in beide.fotos) f.id], [a.id, m.id]);
    // Ohne Bilder ein Ergebnis wie bisher.
    final ohne = s.ergebnis(jetzt)!;
    expect(ohne.fotos, isEmpty);
    expect((jsonDecode(ohne.alsText()) as Map)['version'], 1);

    s.gespeichertAm = jetzt;
    s.fotoLoeschen(m.id);
    expect(s.ungesichert, isTrue);
    expect(s.fotos.keys, [a.id]);
  });

  test('Fotos überstehen das Schließen — auch die offene Aufnahme', () {
    final s = Erfassungsstand(kuerzel: 'AB')..paketOeffnen(beispielPaket());
    final a = s.fotoAnlegen(
      id: 'f-1',
      jetzt: jetzt,
      artikelId: 'a1',
      artikel: 'Grillwurst',
    );
    final wartend = s.fotoAnlegen(id: 'f-2', jetzt: jetzt, bezeichnung: 'M');
    s
      ..fotoHinzu(a, groesse: 300)
      ..fotoWartend = wartend;

    final wieder = Erfassungsstand.ausText(s.alsText());
    expect(wieder.alsText(), s.alsText());
    expect(wieder.fotos.keys, ['f-1']);
    expect(wieder.fotos['f-1']!.groesse, 300);
    expect(wieder.fotos['f-1']!.daten, isNull);
    expect(wieder.fotoWartend!.id, 'f-2');
    expect(wieder.fotoWartend!.art, FotoArt.muster);

    // Ein anderes Paket verwirft auch die Fotos.
    wieder.paketOeffnen(beispielPaket(id: 'paket-2'));
    expect(wieder.fotos, isEmpty);
    expect(wieder.fotoWartend, isNull);
  });
}
