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

  group('Zwischenspeichern', () {
    ProduktionsEntwurf entwurf(
      String id, {
      String roh = '1250',
      String start = '06:10',
      String fertig = '',
      DateTime? am,
    }) =>
        ProduktionsEntwurf(
          produktionId: id,
          artikelId: 'a1',
          artikel: 'Grillwurst',
          datum: DateTime(2026, 11, 10),
          geaendertAm: am ?? jetzt,
          roh: roh,
          start: start,
          fertig: fertig,
        );

    test('begonnen ist nicht erfasst — und steht in keinem Ergebnis', () {
      final s = Erfassungsstand()..paketOeffnen(beispielPaket());

      expect(s.entwurfMerken(entwurf('t1')), isTrue);

      expect(s.entwuerfe.keys, ['t1']);
      // Die Produktion bleibt offen, und am Ergebnis ändert sich nichts.
      expect([for (final p in s.offen) p.id], ['t1', 't2']);
      expect(s.hatErfasstes, isFalse);
      expect(s.ungesichert, isFalse);
      expect(s.ergebnis(jetzt)!.produktionen, isEmpty);
    });

    test('ein gespeichertes Ergebnis bleibt gespeichert', () {
      final s = Erfassungsstand()
        ..paketOeffnen(beispielPaket())
        ..produktionErfassen(erfasst('t2'))
        ..gespeichertAm = jetzt;

      s.entwurfMerken(entwurf('t1'));

      expect(s.ungesichert, isFalse);
    });

    test('dieselben Eingaben noch einmal ändern nichts', () {
      final s = Erfassungsstand()..paketOeffnen(beispielPaket());
      s.entwurfMerken(entwurf('t1'));

      final spaeter = jetzt.add(const Duration(minutes: 5));
      expect(s.entwurfMerken(entwurf('t1', am: spaeter)), isFalse);
      expect(s.entwuerfe['t1']!.geaendertAm, jetzt);

      expect(
        s.entwurfMerken(entwurf('t1', fertig: '1000', am: spaeter)),
        isTrue,
      );
      expect(s.entwuerfe['t1']!.fertig, '1000');
      expect(s.entwuerfe['t1']!.geaendertAm, spaeter);
    });

    test('ohne Eingaben wird nichts gemerkt — und Gemerktes entfernt', () {
      final s = Erfassungsstand()..paketOeffnen(beispielPaket());

      expect(s.entwurfMerken(entwurf('t1', roh: '', start: ' ')), isFalse);
      expect(s.entwuerfe, isEmpty);

      s.entwurfMerken(entwurf('t1'));
      expect(s.entwurfMerken(entwurf('t1', roh: '', start: '')), isTrue);
      expect(s.entwuerfe, isEmpty);
    });

    test('mit dem Erfassen ist das Zwischengespeicherte erledigt', () {
      final s = Erfassungsstand()..paketOeffnen(beispielPaket());
      s
        ..entwurfMerken(entwurf('t1'))
        ..entwurfMerken(entwurf('t2'))
        ..produktionErfassen(erfasst('t1'));

      expect(s.entwuerfe.keys, ['t2']);
      expect(s.entwurfLoeschen('t2'), isTrue);
      expect(s.entwurfLoeschen('t2'), isFalse);
      expect(s.entwuerfe, isEmpty);
    });

    test('ohne Plan begonnen: eigene Liste, das Neueste zuerst', () {
      final s = Erfassungsstand()..paketOeffnen(beispielPaket());
      s
        ..entwurfMerken(entwurf('t1'))
        ..entwurfMerken(entwurf('frei-1'))
        ..entwurfMerken(
          entwurf('frei-2', am: jetzt.add(const Duration(hours: 1))),
        );

      expect(
        [for (final e in s.freiBegonnen) e.produktionId],
        ['frei-2', 'frei-1'],
      );
    });

    test('übersteht das Schließen der App — so wie getippt', () {
      final s = Erfassungsstand()..paketOeffnen(beispielPaket());
      s.entwurfMerken(
        ProduktionsEntwurf(
          produktionId: 't1',
          artikelId: 'a1',
          artikel: 'Grillwurst',
          datum: DateTime(2026, 11, 10),
          geaendertAm: jetzt,
          roh: '1250,5',
          fleisch: '1000',
          start: '0610',
          bemerkung: 'Charge 2',
        ),
      );

      final wieder = Erfassungsstand.ausText(s.alsText());

      final e = wieder.entwuerfe['t1']!;
      expect(e.artikelId, 'a1');
      expect(e.artikel, 'Grillwurst');
      expect(e.datum, DateTime(2026, 11, 10));
      expect(e.geaendertAm, jetzt);
      expect(e.roh, '1250,5');
      expect(e.fleisch, '1000');
      expect(e.fertig, '');
      expect(e.start, '0610');
      expect(e.ende, '');
      expect(e.bemerkung, 'Charge 2');
    });

    test('ein Stand von früher kennt keine Entwürfe', () {
      final s = Erfassungsstand()
        ..paketOeffnen(beispielPaket())
        ..produktionErfassen(erfasst('t1'));
      final alt = (jsonDecode(s.alsText()) as Map<String, Object?>)
        ..remove('entwuerfe');

      final wieder = Erfassungsstand.ausText(jsonEncode(alt));

      expect(wieder.entwuerfe, isEmpty);
      expect(wieder.produktionen.keys, ['t1']);
    });

    test('ein neues Paket verwirft sie', () {
      final s = Erfassungsstand()..paketOeffnen(beispielPaket());
      s.entwurfMerken(entwurf('t1'));

      s.paketOeffnen(beispielPaket(id: 'paket-2'));

      expect(s.entwuerfe, isEmpty);
    });
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
