import 'dart:convert' show latin1;

import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/druck/druck_layout.dart';
import 'package:produktion_planer/core/druck/druck_optionen.dart';
import 'package:produktion_planer/core/druck/druck_satz.dart';
import 'package:produktion_planer/features/auftragsbestand/lieferfaehigkeit.dart';
import 'package:produktion_planer/features/statistik/statistik_daten.dart';
import 'package:produktion_planer/features/statistik/statistik_ueberblick_daten.dart';
import 'package:produktion_planer/features/statistik/wochenbericht_druck.dart';

import 'helpers/statistik_beispiele.dart';

/// Tests für den Wochenbericht: eine Seite mit den Kennzahlen der Woche
/// gegen die Vorwoche, Lieferfähigkeit, Abteilungen, Abweichungen und
/// Ausblick. Die PDFs entstehen unkomprimiert, so steht jedes gedruckte
/// Wort als „(Wort)" im Dokument. Alle Daten sind erfunden.
void main() {
  final gedruckt = DateTime(2026, 10, 30, 16, 12);

  Lieferfaehigkeit liefer({bool gefaehrdet = true}) => Lieferfaehigkeit(
        von: DateTime(2026, 10, 30),
        bisExkl: DateTime(2026, 11, 6),
        auftragKg: 1000,
        gedecktKg: gefaehrdet ? 900 : 1000,
        fehltKg: gefaehrdet ? 100 : 0,
        zuSpaetKg: 0,
        versandtage: 12,
        gefaehrdet: [
          if (gefaehrdet)
            GefaehrdeterVersand(
              artikelnummer: '9001',
              bezeichnung: 'Testbraten',
              tag: DateTime(2026, 11, 2),
              fehltKg: 100,
              zuSpaetKg: 0,
            ),
        ],
        berichtTag: DateTime(2026, 10, 30),
        heute: DateTime(2026, 10, 30),
      );

  Future<(DruckErgebnis, String)> setze(DruckDokument d) async {
    final e = await druckSetzen(d, const DruckLayout(), komprimiert: false);
    return (e, latin1.decode(e.bytes));
  }

  test('Woche: Spanne von Montag bis Sonntag, Vergleich mit der Vorwoche', () {
    final s = StatistikSpanne.fuer(
      StatistikZeitraum.woche,
      DateTime(2026, 10, 30),
    );
    expect(s.von, DateTime(2026, 10, 26));
    expect(s.bisExkl, DateTime(2026, 11, 2));
    expect(s.wochen, 1);
    expect(s.vorher!.von, DateTime(2026, 10, 19));
    expect(wochenberichtTitel(s), 'Wochenbericht KW 44 · 2026');
  });

  test('Kennzahlen: Lieferfähigkeit zuerst, dann die fünf des Überblicks', () {
    final daten = bspStatistikDaten(zeitraum: StatistikZeitraum.woche);
    final k = berichtKennzahlen(werteUeberblickAus(daten), liefer());
    expect(k.first.name, 'Lieferfähigkeit');
    expect(k.first.wert, '90 %');
    // 90 % ist die untere Grenze von Gelb.
    expect(k.first.ampel, Ampel.warnung);
    expect(k, hasLength(6));
    final namen = [for (final z in k.skip(1)) z.name];
    expect(namen, [
      'Ø Auslastung',
      'Mengentreue',
      'Zeittreue',
      'Ø Ausbeute',
      'Planerfüllung',
    ]);
  });

  test('eine Seite mit allen Teilen', () async {
    final daten = bspStatistikDaten(zeitraum: StatistikZeitraum.woche);
    final (e, t) = await setze(
      wochenberichtDruck(daten, liefer(), gedrucktAm: gedruckt),
    );
    expect(e.seiten, 1);
    for (final wort in [
      '(Wochenbericht)',
      '(Kennzahlen)',
      '(Lieferfähigkeit)',
      '(Vorwoche)',
      '(Auslastung)',
      '(Gefährdete)',
      '(Testbraten)',
      '(Ausblick)',
      '(Bemerkungen)',
    ]) {
      expect(t, contains(wort), reason: wort);
    }
  });

  test('abgewählte Teile fehlen, ohne Gefährdung ein Satz', () async {
    final daten = bspStatistikDaten(zeitraum: StatistikZeitraum.woche);
    final (_, t) = await setze(
      wochenberichtDruck(
        daten,
        liefer(gefaehrdet: false),
        gedrucktAm: gedruckt,
        inhalt: const WochenberichtInhalt(
          abteilungen: false,
          ausblick: false,
          bemerkung: false,
        ),
      ),
    );
    expect(t, isNot(contains('(Bemerkungen)')));
    expect(t, isNot(contains('(Ausblick)')));
    expect(t, contains('(rechtzeitig)'));
  });

  test('das Druckfenster kennt die Teile', () async {
    final daten = bspStatistikDaten(zeitraum: StatistikZeitraum.woche);
    final auftrag = wochenberichtDruckAuftrag(daten, liefer());
    expect(auftrag.art, 'wochenbericht');
    final wahl = DruckWahl.standard(auftrag.optionen)
        .mit(WochenberichtWahl.versand, false);
    final (_, t) = await setze(await auftrag.bauen(wahl));
    expect(t, isNot(contains('(Gefährdete)')));
    expect(t, contains('(Kennzahlen)'));
  });
}
