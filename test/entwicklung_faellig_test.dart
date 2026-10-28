import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/utils/kalenderwoche.dart';
import 'package:produktion_planer/features/entwicklung/projekte/faellig.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_modell.dart';

/// Tests für „Fällig bis" an Verlaufseinträgen: was sich als Tag lesen
/// lässt, wann ein offener Eintrag überfällig ist und wie die Liste und
/// der Kopf es sagen. Rein, ohne Datenbank. Alles erfunden.
void main() {
  final eintragAm = DateTime(2026, 10, 28);

  group('faelligAm', () {
    test('Datum mit Jahr — auch zweistellig und als ISO-Datum', () {
      expect(faelligAm('30.11.2026', bezug: eintragAm), DateTime(2026, 11, 30));
      expect(faelligAm('3.2.27', bezug: eintragAm), DateTime(2027, 2, 3));
      expect(faelligAm('2026-12-01', bezug: eintragAm), DateTime(2026, 12));
      expect(
        faelligAm('bis 15.11.2026 (Muster)', bezug: eintragAm),
        DateTime(2026, 11, 15),
      );
    });

    test('ohne Jahr: das Jahr, das dem Eintrag am nächsten liegt', () {
      expect(faelligAm('30.11.', bezug: eintragAm), DateTime(2026, 11, 30));
      expect(faelligAm('30.11', bezug: eintragAm), DateTime(2026, 11, 30));
      // Über den Jahreswechsel …
      expect(
        faelligAm('10.01.', bezug: DateTime(2026, 12, 20)),
        DateTime(2027, 1, 10),
      );
      // … und zurück: ein Tag kurz vor dem Eintrag bleibt im selben Jahr.
      expect(faelligAm('20.10.', bezug: eintragAm), DateTime(2026, 10, 20));
    });

    test('Kalenderwoche: bis zu ihrem Sonntag', () {
      final kw48 = faelligAm('KW 48', bezug: eintragAm)!;
      expect(kw48, DateTime(2026, 11, 29));
      expect(kw48.weekday, DateTime.sunday);
      expect(isoKalenderwoche(kw48), 48);
      for (final text in [
        'KW48/2026',
        'kw 48/26',
        'KW 48 2026',
        'KW 48-2026',
      ]) {
        expect(faelligAm(text, bezug: eintragAm), kw48, reason: text);
      }
      expect(
        faelligAm('Ende KW 2', bezug: DateTime(2026, 12, 15)),
        DateTime(2027, 1, 17),
      );
      // Die erste Woche 2026 beginnt schon am 29.12.2025.
      expect(faelligAm('KW 1/2026', bezug: eintragAm), DateTime(2026, 1, 4));
      // 2026 hat 53 Wochen, 2027 nicht.
      expect(faelligAm('KW 53/2026', bezug: eintragAm), DateTime(2027, 1, 3));
      expect(faelligAm('KW 53/2027', bezug: eintragAm), isNull);
    });

    test('was sich nicht als Tag lesen lässt, bleibt ohne Tag', () {
      for (final text in [
        null,
        '',
        '  ',
        'nach der Verkostung',
        '31.02.2026',
        '14.30 Uhr',
        'KW 60',
      ]) {
        expect(faelligAm(text, bezug: eintragAm), isNull, reason: text);
      }
    });
  });

  group('überfällig', () {
    test('erst, wenn der Tag vorbei ist', () {
      bool am(DateTime heute) =>
          istUeberfaellig('30.11.2026', bezug: eintragAm, heute: heute);
      expect(am(DateTime(2026, 11, 30, 23, 59)), isFalse);
      expect(am(DateTime(2026, 12)), isTrue);
      bool woche(DateTime heute) =>
          istUeberfaellig('KW 48', bezug: eintragAm, heute: heute);
      expect(woche(DateTime(2026, 11, 29)), isFalse);
      expect(woche(DateTime(2026, 11, 30)), isTrue);
      expect(
        istUeberfaellig(
          'nach der Verkostung',
          bezug: eintragAm,
          heute: DateTime(2030),
        ),
        isFalse,
      );
    });

    test('nur offene Einträge zählen — je Projekt', () {
      ProjektEintrag eintrag(
        String id,
        String projektId, {
        EintragStatus status = EintragStatus.offen,
        String? ziel,
      }) =>
          ProjektEintrag(
            id: id,
            projektId: projektId,
            art: EintragArt.notiz.schluessel,
            titel: 'Muster $id',
            datum: eintragAm,
            status: status.schluessel,
            ziel: ziel,
            createdAt: eintragAm,
            updatedAt: eintragAm,
          );
      final heute = DateTime(2026, 12, 10);
      final eintraege = [
        eintrag('e1', 'p1', ziel: '30.11.'),
        eintrag('e2', 'p1', ziel: 'KW 52'),
        eintrag('e3', 'p1'),
        eintrag('e4', 'p1', status: EintragStatus.erledigt, ziel: '01.11.'),
        eintrag('e5', 'p2', status: EintragStatus.erledigt),
        eintrag('e6', 'p3', ziel: 'KW 45'),
      ];
      expect(eintragUeberfaellig(eintraege[0], heute: heute), isTrue);
      expect(eintragUeberfaellig(eintraege[3], heute: heute), isFalse);

      final je = offeneJeProjekt(eintraege, heute: heute);
      expect(je.keys, unorderedEquals(['p1', 'p3']));
      expect(je['p1'], (offen: 3, ueberfaellig: 1));
      expect(je['p3'], (offen: 1, ueberfaellig: 1));
      final p1 = eintraege.where((e) => e.projektId == 'p1');
      expect(offeneZaehlen(p1, heute: heute), (offen: 3, ueberfaellig: 1));
    });
  });

  test('so sagen es Liste und Kopf', () {
    expect(
      offeneEintraegeText((offen: 1, ueberfaellig: 0)),
      '1 offener Eintrag',
    );
    expect(
      offeneEintraegeText((offen: 1, ueberfaellig: 0), imVerlauf: true),
      '1 offener Eintrag im Verlauf',
    );
    expect(
      offeneEintraegeText((offen: 1, ueberfaellig: 1)),
      '1 offener Eintrag, überfällig',
    );
    expect(
      offeneEintraegeText((offen: 3, ueberfaellig: 2), imVerlauf: true),
      '3 offene Einträge im Verlauf, 2 überfällig',
    );
  });
}
