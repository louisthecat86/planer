import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/tagesaufgaben_service.dart';

import 'helpers/test_db.dart';

/// Tests für die sonstigen Aufgaben im Wochenboard: von Hand eingetragen,
/// je Abteilung und Tag. Alle Daten sind erfunden.
void main() {
  late AppDatabase db;

  setUp(() => db = testDatenbank());
  tearDown(() => db.close());

  final montag = DateTime(2026, 10, 5);
  final dienstag = DateTime(2026, 10, 6);

  Future<Tagesaufgabe> lade(String id) =>
      (db.select(db.tagesaufgaben)..where((a) => a.id.equals(id)))
          .getSingle();

  Future<Map<AufgabenZelle, List<Tagesaufgabe>>> woche() =>
      TagesaufgabenService.fuerZeitraum(
        db,
        von: montag,
        bisExkl: DateTime(2026, 10, 12),
      );

  Future<String> neu(
    DateTime tag,
    String inhalt, {
    String abteilung = 'zerlegung',
  }) =>
      TagesaufgabenService.anlegen(
        db,
        tag: tag,
        abteilung: abteilung,
        inhalt: inhalt,
      );

  test('neue Aufgaben kommen ans Ende ihrer Abteilung und ihres Tages',
      () async {
    final a = await neu(DateTime(2026, 10, 5, 14, 30), '  Messer schleifen  ');
    final b = await neu(montag, 'Kessel entkalken');
    final c = await neu(montag, 'Folie testen', abteilung: 'verpackung');
    final d = await neu(dienstag, 'Band reinigen');

    final erste = await lade(a);
    expect(erste.inhalt, 'Messer schleifen');
    expect(erste.datum, montag, reason: 'tagesgenau');
    expect(erste.abteilung, 'zerlegung');
    expect(erste.erledigt, isFalse);
    expect(erste.sortierung, 0);
    expect((await lade(b)).sortierung, 1);
    expect(
      (await lade(c)).sortierung,
      0,
      reason: 'Jede Abteilung zählt für sich',
    );
    expect((await lade(d)).sortierung, 0, reason: 'Jeder Tag zählt für sich');
  });

  test('ohne Text gibt es keine Aufgabe', () async {
    await expectLater(neu(montag, '   '), throwsArgumentError);
    final id = await neu(montag, 'Kessel entkalken');
    await expectLater(
      TagesaufgabenService.aendern(db, id, inhalt: ''),
      throwsArgumentError,
    );
    expect((await lade(id)).inhalt, 'Kessel entkalken');
  });

  test('abhaken, ändern, löschen und zurückholen', () async {
    final id = await neu(montag, 'Kessel entkalken');

    await TagesaufgabenService.abhaken(db, id, erledigt: true);
    await TagesaufgabenService.aendern(db, id, inhalt: 'Kessel 2 entkalken');

    final a = await lade(id);
    expect(a.erledigt, isTrue);
    expect(a.inhalt, 'Kessel 2 entkalken');

    await TagesaufgabenService.loeschen(db, id);

    expect((await lade(id)).deletedAt, isNotNull);
    expect(await woche(), isEmpty);

    // Rückgängig.
    await TagesaufgabenService.wiederherstellen(db, id);

    expect((await lade(id)).deletedAt, isNull);
    expect((await woche())[('zerlegung', montag)]?.single.id, id);
  });

  test('die Woche kommt je Abteilung und Tag in der Reihenfolge', () async {
    await neu(dienstag, 'Dienstag 1');
    await neu(montag, 'Montag Zerlegung');
    await neu(dienstag, 'Dienstag 2');
    await neu(montag, 'Montag Verpackung', abteilung: 'verpackung');
    await neu(DateTime(2026, 10, 12), 'Nächste Woche');

    final w = await woche();

    expect(w.keys.toSet(), {
      ('zerlegung', montag),
      ('zerlegung', dienstag),
      ('verpackung', montag),
    });
    expect(
      w[('zerlegung', dienstag)]!.map((a) => a.inhalt),
      ['Dienstag 1', 'Dienstag 2'],
    );
    expect(
      w[('verpackung', montag)]!.single.inhalt,
      'Montag Verpackung',
    );
  });

  test('verschoben wird ans Ende des Zieltags', () async {
    await neu(dienstag, 'Steht schon da');
    final id = await neu(montag, 'Kessel entkalken');

    await TagesaufgabenService.verschieben(db, id, tag: dienstag);

    final a = await lade(id);
    expect(a.datum, dienstag);
    expect(a.abteilung, 'zerlegung', reason: 'Abteilung bleibt');
    expect(a.sortierung, 1);

    // Auf denselben Tag: nichts passiert.
    await TagesaufgabenService.verschieben(db, id, tag: dienstag);
    expect((await lade(id)).sortierung, 1);
  });

  test('verschieben in eine andere Abteilung', () async {
    final id = await neu(montag, 'Folie testen');

    await TagesaufgabenService.verschieben(
      db,
      id,
      tag: montag,
      abteilung: 'verpackung',
    );

    final a = await lade(id);
    expect(a.abteilung, 'verpackung');
    expect(a.datum, montag);
  });

  test('der nächste Arbeitstag überspringt das Wochenende', () {
    final freitag = DateTime(2026, 10, 9);

    expect(TagesaufgabenService.naechsterArbeitstag(montag), dienstag);
    expect(
      TagesaufgabenService.naechsterArbeitstag(freitag),
      DateTime(2026, 10, 12),
    );
    // Die Zeitumstellung am 25.10. verschiebt nichts.
    expect(
      TagesaufgabenService.naechsterArbeitstag(DateTime(2026, 10, 23)),
      DateTime(2026, 10, 26),
    );
  });
}
