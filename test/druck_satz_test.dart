import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:produktion_planer/core/druck/druck_layout.dart';
import 'package:produktion_planer/core/druck/druck_satz.dart';

/// Tests für den Satz eines Ausdrucks: Papier, Ausrichtung, Verkleinern,
/// „Alles auf eine Seite", Ränder, Graustufen. Gelesen wird das
/// unkomprimierte PDF — Text steht darin Wort für Wort.
void main() {
  /// Ein Blatt mit [zeilen] Zeilen Text und einer Fußzeile „S1v2"
  /// (Seite 1 von 2 im Blatt). [rahmen] bekommt jeden Rahmen.
  DruckBlatt blatt(
    int zeilen, {
    bool quer = false,
    pw.EdgeInsets rand = const pw.EdgeInsets.all(28),
    List<DruckRahmen>? rahmen,
  }) =>
      DruckBlatt(
        quer: quer,
        rand: rand,
        bauen: (r) {
          rahmen?.add(r);
          return DruckSeiten(
            fuss: (ctx) => pw.Text(
              'S${r.seiteImBlatt(ctx)}v${r.seitenImBlatt}',
            ),
            inhalt: (_) => [
              for (var i = 0; i < zeilen; i++) pw.Text('Zeile $i mit Text'),
            ],
          );
        },
      );

  Future<(DruckErgebnis, String)> setzen(
    List<DruckBlatt> blaetter, [
    DruckLayout layout = const DruckLayout(),
  ]) async {
    final e = await druckSetzen(
      DruckDokument(blaetter: blaetter),
      layout,
      komprimiert: false,
    );
    return (e, latin1.decode(e.bytes));
  }

  List<String> medienboxen(String pdf) => [
        for (final m in RegExp(r'/MediaBox\[([^\]]*)\]').allMatches(pdf))
          m.group(1)!,
      ];

  group('Papier und Größe', () {
    test('Originalgröße auf A4: kein Maßstab', () async {
      final (e, pdf) = await setzen([blatt(80)]);
      expect(e.blattSeiten, [2]);
      expect(e.massstaebe, [1]);
      expect(medienboxen(pdf), everyElement('0 0 595.27559 841.88976'));
      expect(pdf, isNot(contains(' 0 0 cm')));
      expect(pdf, contains('(S2v2)'));
      expect(e.beschreibung, '2 Seiten · A4 hoch · 100 %');
    });

    test('A3 vergrößert das ganze Blatt, A5 verkleinert es', () async {
      final (a3, pdf3) = await setzen(
        [blatt(80)],
        const DruckLayout(papier: DruckPapier.a3),
      );
      // Wie am Kopierer: dieselben Seiten, nur größer.
      expect(a3.blattSeiten, [2]);
      expect(medienboxen(pdf3), everyElement('0 0 841.88976 1190.55118'));
      expect(pdf3, contains('1.41414 0 0 1.41414 0 0 cm'));
      expect(a3.format.width, closeTo(PdfPageFormat.a3.width, .01));

      final (a5, pdf5) = await setzen(
        [blatt(80)],
        const DruckLayout(papier: DruckPapier.a5),
      );
      expect(a5.blattSeiten, [2]);
      expect(medienboxen(pdf5), everyElement('0 0 419.52756 595.27559'));
      // 148 zu 210 mm — A5 ist eine Spur schmaler als halb A4.
      expect(pdf5, contains('0.70476 0 0 0.70476 0 0 cm'));
    });

    test('Verkleinern auf 50 %: es passt mehr auf eine Seite', () async {
      final (e, pdf) = await setzen(
        [blatt(80)],
        const DruckLayout(anpassung: DruckAnpassung.verkleinern, prozent: 50),
      );
      expect(e.massstaebe, [.5]);
      expect(e.blattSeiten, [1]);
      expect(pdf, contains('0.5 0 0 0.5 0 0 cm'));
      // Das Papier bleibt A4.
      expect(medienboxen(pdf), ['0 0 595.27559 841.88976']);
      expect(e.beschreibung, '1 Seite · A4 hoch · 50 %');
    });

    test('Alles auf eine Seite: so groß wie möglich', () async {
      final (e, _) = await setzen(
        [blatt(150)],
        const DruckLayout(anpassung: DruckAnpassung.eineSeite),
      );
      expect(e.blattSeiten, [1]);
      expect(e.passtNicht, isFalse);
      final s = e.massstaebe.single;
      expect(s, lessThan(1));
      expect(s, greaterThan(kDruckKleinsterMassstab));
      // Nur wenig größer, und es wären zwei Seiten.
      final (groesser, _) = await setzen(
        [blatt(150)],
        DruckLayout(
          anpassung: DruckAnpassung.verkleinern,
          prozent: (s * 100).ceil() + 2,
        ),
      );
      expect(groesser.blattSeiten.single, greaterThan(1));
    });

    test('Alles auf eine Seite vergrößert nicht', () async {
      final (e, pdf) = await setzen(
        [blatt(5)],
        const DruckLayout(anpassung: DruckAnpassung.eineSeite),
      );
      expect(e.massstaebe, [1]);
      expect(pdf, isNot(contains(' 0 0 cm')));
    });

    test('Passt es auch klein nicht, sagt es das Ergebnis', () async {
      final (e, _) = await setzen(
        [blatt(1500)],
        const DruckLayout(anpassung: DruckAnpassung.eineSeite),
      );
      expect(e.passtNicht, isTrue);
      expect(e.massstaebe, [kDruckKleinsterMassstab]);
      expect(e.blattSeiten.single, greaterThan(1));
    });

    test('Auf höchstens zwei Seiten: größer als auf eine', () async {
      final (zwei, _) = await setzen(
        [blatt(300)],
        const DruckLayout(anpassung: DruckAnpassung.zweiSeiten),
      );
      final (eine, _) = await setzen(
        [blatt(300)],
        const DruckLayout(anpassung: DruckAnpassung.eineSeite),
      );
      expect(zwei.blattSeiten.single, lessThanOrEqualTo(2));
      expect(zwei.massstaebe.single, greaterThan(eine.massstaebe.single));
    });

    test('Jedes Blatt passt für sich, Seiten zählen je Blatt', () async {
      final (e, pdf) = await setzen(
        [blatt(150), blatt(3)],
        const DruckLayout(anpassung: DruckAnpassung.eineSeite),
      );
      expect(e.blattSeiten, [1, 1]);
      expect(e.massstaebe.last, 1);
      expect(e.massstaebe.first, lessThan(1));
      expect(RegExp(r'\(S1v1\)').allMatches(pdf), hasLength(2));
      expect(e.beschreibung, startsWith('2 Blätter · 2 Seiten · A4 hoch · '));

      final (original, pdfOriginal) = await setzen([blatt(80), blatt(3)]);
      expect(original.blattSeiten, [2, 1]);
      expect(pdfOriginal, contains('(S2v2)'));
      expect(pdfOriginal, contains('(S1v1)'));
    });
  });

  group('Ausrichtung und Ränder', () {
    test('Automatisch: wie das Blatt es vorsieht', () async {
      final (e, pdf) = await setzen([blatt(10, quer: true)]);
      expect(medienboxen(pdf), ['0 0 841.88976 595.27559']);
      expect(e.beschreibung, '1 Seite · A4 quer · 100 %');

      final (hoch, pdfHoch) = await setzen(
        [blatt(10, quer: true)],
        const DruckLayout(ausrichtung: DruckAusrichtung.hoch),
      );
      expect(medienboxen(pdfHoch), ['0 0 595.27559 841.88976']);
      expect(hoch.format.width, lessThan(hoch.format.height));
    });

    test('Querformat gibt dem Inhalt mehr Breite', () async {
      final rahmen = <DruckRahmen>[];
      await setzen(
        [blatt(10, rahmen: rahmen)],
        const DruckLayout(ausrichtung: DruckAusrichtung.quer),
      );
      expect(rahmen.last.quer, isTrue);
      expect(rahmen.last.breite, closeTo(841.89 - 56, .01));
    });

    test('Schmale Ränder, aber nie unter dem Mindestrand', () async {
      final rahmen = <DruckRahmen>[];
      await setzen([blatt(10, rahmen: rahmen)]);
      expect(rahmen.last.breite, closeTo(595.28 - 56, .01));

      await setzen(
        [blatt(10, rahmen: rahmen)],
        const DruckLayout(rand: DruckRand.schmal),
      );
      // 28 halbiert ist 14 — genau der Mindestrand.
      expect(rahmen.last.breite, closeTo(595.28 - 28, .01));

      await setzen(
        [blatt(10, rand: const pw.EdgeInsets.all(20), rahmen: rahmen)],
        const DruckLayout(rand: DruckRand.schmal),
      );
      expect(rahmen.last.breite, closeTo(595.28 - 2 * kDruckMindestrand, .01));
    });

    test('Auf A5 wird der Rand nicht schmaler als der Mindestrand', () async {
      final rahmen = <DruckRahmen>[];
      await setzen(
        [blatt(10, rand: const pw.EdgeInsets.all(16), rahmen: rahmen)],
        const DruckLayout(papier: DruckPapier.a5),
      );
      // Auf A4 gerechnet: 14 Punkt auf A5 sind knapp 20 auf A4.
      final rand = kDruckMindestrand / (PdfPageFormat.a5.width / 595.28);
      expect(rahmen.last.breite, closeTo(595.28 - 2 * rand, .05));
    });

    test('Verkleinert wird die gedachte Seite breiter', () async {
      final rahmen = <DruckRahmen>[];
      await setzen(
        [blatt(10, rahmen: rahmen)],
        const DruckLayout(anpassung: DruckAnpassung.verkleinern, prozent: 50),
      );
      expect(rahmen.last.massstab, .5);
      expect(rahmen.last.breite, closeTo((595.28 - 56) * 2, .05));
    });

    test('Umbrüche von Hand nur ohne Anpassen an Seiten', () async {
      final rahmen = <DruckRahmen>[];
      for (final a in DruckAnpassung.values) {
        await setzen([blatt(3, rahmen: rahmen)], DruckLayout(anpassung: a));
        expect(rahmen.last.umbrueche, a.hoechstens == null, reason: a.name);
      }
    });
  });

  group('Graustufen, Links, Sprungmarken', () {
    test('Graustufen: eine Fläche im Mischmodus Sättigung', () async {
      final (_, farbig) = await setzen([blatt(3)]);
      expect(farbig, isNot(contains('/BM/Saturation')));
      final (e, grau) = await setzen(
        [blatt(3)],
        const DruckLayout(graustufen: true),
      );
      expect(grau, contains('/BM/Saturation'));
      expect(e.beschreibung, endsWith('· Graustufen'));
    });

    test('Links und Sprungziele folgen dem Maßstab', () async {
      final dokument = DruckDokument(
        blaetter: [
          DruckBlatt(
            bauen: (_) => DruckSeiten(
              inhalt: (_) => [
                pw.Anchor(name: 'ziel', child: pw.Text('Ziel')),
                pw.Link(destination: 'ziel', child: pw.Text('Hin')),
              ],
            ),
          ),
        ],
      );
      Future<(double, double)> lage(DruckLayout layout) async {
        final e = await druckSetzen(dokument, layout, komprimiert: false);
        final pdf = latin1.decode(e.bytes);
        final ziel = RegExp(r'/XYZ null ([0-9.]+)').firstMatch(pdf)!;
        final link = RegExp(r'/Rect\[[0-9.]+ ([0-9.]+)').firstMatch(pdf)!;
        return (double.parse(ziel.group(1)!), double.parse(link.group(1)!));
      }

      final (zielA4, linkA4) = await lage(const DruckLayout());
      final (zielA3, linkA3) = await lage(
        const DruckLayout(papier: DruckPapier.a3),
      );
      expect(zielA3, closeTo(zielA4 * 1.41414, .5));
      expect(linkA3, closeTo(linkA4 * 1.41414, .5));
      // Oben auf der Seite — innerhalb des Papiers.
      expect(zielA3, lessThan(PdfPageFormat.a3.height));
      expect(zielA3, greaterThan(PdfPageFormat.a3.height - 60));
    });

    test('Sprungmarken: ein zweiter Durchgang kennt ihre Seiten', () async {
      final dokument = DruckDokument(
        blaetter: [
          DruckBlatt(
            bauen: (r) => DruckSeiten(
              inhalt: (_) => [
                pw.Text('ZielSeite${r.bekannt['ziel'] ?? 0}'),
                for (var i = 0; i < 100; i++) pw.Text('Zeile $i'),
                _Marke(r),
              ],
            ),
          ),
        ],
      );
      final e = await druckSetzen(
        dokument,
        const DruckLayout(),
        komprimiert: false,
      );
      expect(e.blattSeiten, [2]);
      expect(latin1.decode(e.bytes), contains('(ZielSeite2)'));

      // Auf eine Seite verkleinert, steht das Ziel auf Seite 1.
      final klein = await druckSetzen(
        dokument,
        const DruckLayout(anpassung: DruckAnpassung.eineSeite),
        komprimiert: false,
      );
      expect(latin1.decode(klein.bytes), contains('(ZielSeite1)'));
    });

    test('Ohne Blätter gibt es nichts zu drucken', () {
      expect(
        () => druckSetzen(
          const DruckDokument(blaetter: []),
          const DruckLayout(),
        ),
        throwsArgumentError,
      );
    });
  });

  group('Einstellungen merken', () {
    test('hin und zurück', () {
      const layout = DruckLayout(
        papier: DruckPapier.a3,
        ausrichtung: DruckAusrichtung.quer,
        anpassung: DruckAnpassung.verkleinern,
        prozent: 60,
        rand: DruckRand.schmal,
        graustufen: true,
      );
      final json = jsonDecode(jsonEncode(layout.toJson()));
      expect(DruckLayout.fromJson(json), layout);
    });

    test('Unbekanntes und Fehlendes kommt aus dem Standard', () {
      const standard = DruckLayout(anpassung: DruckAnpassung.eineSeite);
      expect(DruckLayout.fromJson(null, standard: standard), standard);
      expect(DruckLayout.fromJson('kaputt', standard: standard), standard);
      final gelesen = DruckLayout.fromJson(
        {'papier': 'a2', 'prozent': 33, 'rand': 'schmal', 'graustufen': 1},
        standard: standard,
      );
      expect(gelesen.papier, DruckPapier.a4);
      expect(gelesen.prozent, 80);
      expect(gelesen.rand, DruckRand.schmal);
      expect(gelesen.graustufen, isFalse);
      expect(gelesen.anpassung, DruckAnpassung.eineSeite);
    });
  });
}

/// Merkt sich beim Zeichnen die Seite, auf der sie steht.
class _Marke extends pw.StatelessWidget {
  _Marke(this.rahmen);

  final DruckRahmen rahmen;

  @override
  pw.Widget build(pw.Context context) => pw.Text('Ziel');

  @override
  void paint(pw.Context context) {
    super.paint(context);
    rahmen.merke('ziel', context.pageNumber);
  }
}
