// `show Value`: drift bringt eine eigene Klasse `Column` mit.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/features/entwicklung/daten/entwicklung_repository.dart';
import 'package:produktion_planer/features/entwicklung/entwicklung_format.dart';
import 'package:produktion_planer/features/entwicklung/rechenkern/rechen_modell.dart';
import 'package:produktion_planer/features/entwicklung/rechenkern/rechenkern.dart';
import 'package:produktion_planer/features/entwicklung/rezepturen/stand_vergleich.dart';

import 'helpers/test_db.dart';

/// Tests für Zutaten und Rezepturen in der Datenbank: Stände anlegen und
/// abschließen, Unterrezepturen laden, Zeilen bearbeiten — und dass der
/// Rechenkern damit dasselbe rechnet wie mit Hand gebauten Rezepturen.
/// Alle Rezepturen sind erfunden.
void main() {
  late AppDatabase db;
  late EntwicklungRepository repo;

  setUp(() {
    db = testDatenbank();
    repo = EntwicklungRepository(db);
  });
  tearDown(() => db.close());

  Future<String> zutat(
    String name, {
    bool fleisch = false,
    bool wasser = false,
    bool quid = false,
    double? fett,
    double? eiweiss,
    String? allergene,
  }) =>
      repo.zutatAnlegen(
        EntwicklungZutatenCompanion(
          name: Value(name),
          istFleisch: Value(fleisch),
          istWasser: Value(wasser),
          tierart: Value(fleisch ? 'schwein' : null),
          quidPflicht: Value(quid),
          fett: Value(fett),
          eiweiss: Value(eiweiss),
          allergene: Value(allergene),
        ),
      );

  Future<RezepturVersion> neuester(String rezepturId) async =>
      (await repo.neuesteVersion(rezepturId))!;

  Future<RezepturErgebnis> ergebnis(String versionId) async =>
      berechne((await repo.rechenRezeptur(versionId))!);

  test('eine neue Rezeptur hat einen leeren ersten Entwurf', () async {
    final id = await repo.rezepturAnlegen(name: 'Bratwurst fein');
    final v = await neuester(id);
    expect(v.nummer, 1);
    expect(v.status, VersionStatus.entwurf);
    expect(await repo.positionen(v.id), isEmpty);
  });

  test('Zeilen hinzufügen und rechnen', () async {
    final schwein = await zutat(
      'Schweineschulter S3',
      fleisch: true,
      fett: 20,
      eiweiss: 18,
    );
    final salz = await zutat('Speisesalz');
    final id = await repo.rezepturAnlegen(name: 'Bratwurst fein');
    final v = await neuester(id);
    await repo.positionHinzufuegen(v.id, zutatId: schwein, mengeKg: 98);
    await repo.positionHinzufuegen(v.id, zutatId: salz, mengeKg: 2);

    final e = await ergebnis(v.id);
    expect(e.zutatenliste, 'Schweinefleisch (98,0 %), Speisesalz');
  });

  test('ein neuer Stand übernimmt Zeilen und Verlust', () async {
    final salz = await zutat('Speisesalz');
    final id = await repo.rezepturAnlegen(name: 'Rohwurst');
    final v1 = await neuester(id);
    await repo.positionHinzufuegen(v1.id, zutatId: salz, mengeKg: 3);
    await repo.versionAendern(
      v1.id,
      const EntwicklungRezepturVersionenCompanion(verlustProzent: Value(30)),
    );

    final v2Id = await repo.versionAnlegen(id, vorlageId: v1.id);
    final v2 = (await repo.version(v2Id))!;
    expect(v2.nummer, 2);
    expect(v2.verlustProzent, 30);
    final zeilen = await repo.positionen(v2Id);
    expect(zeilen.single.zutatId, salz);
    expect(zeilen.single.mengeKg, 3);
  });

  test('ein abgeschlossener Stand bleibt, wie er war', () async {
    final schwein = await zutat(
      'Schweinebauch',
      fleisch: true,
      fett: 28,
      eiweiss: 16,
    );
    final id = await repo.rezepturAnlegen(name: 'Kochschinken');
    final v = await neuester(id);
    await repo.positionHinzufuegen(v.id, zutatId: schwein, mengeKg: 100);
    await repo.versionAbschliessen(v.id);

    // Der Katalog ändert sich: jetzt 40 % Fett — über der Grenze.
    await repo.zutatAendern(
      schwein,
      const EntwicklungZutatenCompanion(fett: Value(40)),
    );

    final eingefroren = await ergebnis(v.id);
    expect(eingefroren.zutatenliste, 'Schweinefleisch (100,0 %)');

    // Ein neuer Entwurf rechnet mit dem Katalog von heute.
    final v2 = await repo.versionAnlegen(id, vorlageId: v.id);
    final heute = await ergebnis(v2);
    expect(heute.zutatenliste, contains('Speck'));
  });

  test('abgeschlossen heißt: nicht mehr änderbar', () async {
    final salz = await zutat('Speisesalz');
    final id = await repo.rezepturAnlegen(name: 'Test');
    final v = await neuester(id);
    await repo.versionAbschliessen(v.id);

    await expectLater(
      repo.positionHinzufuegen(v.id, zutatId: salz),
      throwsStateError,
    );
    await expectLater(repo.versionLoeschen(v.id), throwsStateError);
  });

  test('Unterrezepturen kommen mit ihrem neuesten Stand', () async {
    final zwiebeln = await zutat('Zwiebeln', quid: true);
    final schwein = await zutat(
      'Schweinefleisch',
      fleisch: true,
      fett: 20,
      eiweiss: 18,
    );
    final roest = await repo.rezepturAnlegen(name: 'Röstzwiebeln');
    final rv = await neuester(roest);
    await repo.positionHinzufuegen(rv.id, zutatId: zwiebeln, mengeKg: 10);
    await repo.versionAendern(
      rv.id,
      const EntwicklungRezepturVersionenCompanion(verlustProzent: Value(50)),
    );

    final wurst = await repo.rezepturAnlegen(name: 'Zwiebelwurst');
    final wv = await neuester(wurst);
    await repo.positionHinzufuegen(wv.id, zutatId: schwein, mengeKg: 95);
    await repo.positionHinzufuegen(wv.id, unterrezepturId: roest, mengeKg: 5);

    final e = await ergebnis(wv.id);
    expect(e.endgewichtKg, 100);
    expect(e.zutatenliste, 'Schweinefleisch (95,0 %), Zwiebeln (10,0 %)');
  });

  test('Rezepturen, die sich gegenseitig enthalten, laden trotzdem',
      () async {
    final a = await repo.rezepturAnlegen(name: 'A');
    final b = await repo.rezepturAnlegen(name: 'B');
    final av = await neuester(a);
    final bv = await neuester(b);
    await repo.positionHinzufuegen(av.id, unterrezepturId: b, mengeKg: 1);
    await repo.positionHinzufuegen(bv.id, unterrezepturId: a, mengeKg: 1);

    final e = await ergebnis(av.id);
    expect(e.warnungen.any((w) => w.contains('sich selbst')), isTrue);
  });

  test('eine gelöschte Zutat rechnet weiter mit', () async {
    final salz = await zutat('Speisesalz');
    final id = await repo.rezepturAnlegen(name: 'Test');
    final v = await neuester(id);
    await repo.positionHinzufuegen(v.id, zutatId: salz, mengeKg: 1);
    await repo.zutatLoeschen(salz);

    expect(await repo.zutatVerwendungen(salz), 1);
    final e = await ergebnis(v.id);
    expect(e.zutatenliste, 'Speisesalz');
  });

  test('Zeilen verschieben', () async {
    final a = await zutat('A');
    final b = await zutat('B');
    final c = await zutat('C');
    final id = await repo.rezepturAnlegen(name: 'Test');
    final v = await neuester(id);
    for (final z in [a, b, c]) {
      await repo.positionHinzufuegen(v.id, zutatId: z, mengeKg: 1);
    }
    final vorher = await repo.positionen(v.id);
    await repo.positionVerschieben(vorher[2], nachOben: true);

    final nachher = await repo.positionen(v.id);
    expect(nachher.map((p) => p.zutatId), [a, c, b]);
  });

  test('Zeilen ziehen: an jede Stelle, die übrigen rücken nach', () async {
    final ids = [for (final n in ['A', 'B', 'C', 'D']) await zutat(n)];
    final [a, b, c, d] = ids;
    final id = await repo.rezepturAnlegen(name: 'Test');
    final v = await neuester(id);
    for (final z in ids) {
      await repo.positionHinzufuegen(v.id, zutatId: z, mengeKg: 1);
    }
    Future<List<String?>> reihe() async =>
        [for (final p in await repo.positionen(v.id)) p.zutatId];
    Future<void> ziehe(String zutatId, int ziel) async {
      final zeile =
          (await repo.positionen(v.id)).firstWhere((p) => p.zutatId == zutatId);
      await repo.positionVerschiebenNach(zeile, ziel);
    }

    // Die erste ganz nach unten.
    await ziehe(a, 3);
    expect(await reihe(), [b, c, d, a]);
    // Die letzte ganz nach oben.
    await ziehe(a, 0);
    expect(await reihe(), [a, b, c, d]);
    // Über mehrere Plätze in einem Zug.
    await ziehe(d, 1);
    expect(await reihe(), [a, d, b, c]);
    // Hinter das Ende: ans Ende; vor den Anfang: an den Anfang.
    await ziehe(d, 99);
    expect(await reihe(), [a, b, c, d]);
    await ziehe(c, -5);
    expect(await reihe(), [c, a, b, d]);
    // Dieselbe Stelle: bleibt.
    await ziehe(b, 2);
    expect(await reihe(), [c, a, b, d]);
    // Die Nummern sind danach lückenlos.
    expect(
      [for (final p in await repo.positionen(v.id)) p.reihenfolge],
      [0, 1, 2, 3],
    );

    // Ein abgeschlossener Stand bleibt, wie er ist.
    await repo.versionAbschliessen(v.id);
    final erste = (await repo.positionen(v.id)).first;
    await expectLater(
      repo.positionVerschiebenNach(erste, 3),
      throwsStateError,
    );
  });

  test('Zeile austauschen: Menge, Platz und Notiz bleiben', () async {
    final schwein = await zutat('Schweinefleisch', fleisch: true, quid: true);
    final rind = await zutat('Rindfleisch', fleisch: true);
    final salz = await zutat('Speisesalz');
    final roest = await repo.rezepturAnlegen(name: 'Röstzwiebeln');
    final id = await repo.rezepturAnlegen(name: 'Test');
    final v = await neuester(id);
    await repo.positionHinzufuegen(v.id, zutatId: salz, mengeKg: 2);
    await repo.positionHinzufuegen(v.id, zutatId: schwein, mengeKg: 95);
    await repo.positionHinzufuegen(v.id, zutatId: salz, mengeKg: 3);
    final zeile = (await repo.positionen(v.id))[1];
    await repo.positionAendern(
      zeile,
      const EntwicklungRezepturPositionenCompanion(
        etikettName: Value('Schweinefleisch aus der Region'),
        quidPflicht: Value(false),
        notiz: Value('Lieferant prüfen'),
      ),
    );
    Future<RezepturPosition> mitte() async => (await repo.positionen(v.id))[1];

    await repo.positionAustauschen(await mitte(), zutatId: rind);
    var neu = await mitte();
    expect(neu.id, zeile.id);
    expect(neu.zutatId, rind);
    expect(neu.unterrezepturId, isNull);
    expect(neu.mengeKg, 95);
    expect(neu.reihenfolge, zeile.reihenfolge);
    expect(neu.notiz, 'Lieferant prüfen');
    // Etikettname und QUID gehörten zur alten Zutat.
    expect(neu.etikettName, isNull);
    expect(neu.quidPflicht, isNull);
    // Die Zeilen davor und danach bleiben.
    expect(
      [for (final p in await repo.positionen(v.id)) p.zutatId],
      [salz, rind, salz],
    );

    // Eine Zutat gegen eine Unterrezeptur — und zurück.
    await repo.positionAustauschen(neu, unterrezepturId: roest);
    neu = await mitte();
    expect(neu.zutatId, isNull);
    expect(neu.unterrezepturId, roest);
    expect(neu.unterVersionId, isNull);
    expect(neu.mengeKg, 95);
    await repo.positionAustauschen(neu, zutatId: schwein);
    expect((await mitte()).zutatId, schwein);

    // Dieselbe gewählt: Ein eigener Etikettname bleibt dann stehen.
    await repo.positionAendern(
      await mitte(),
      const EntwicklungRezepturPositionenCompanion(
        etikettName: Value('Schweinefleisch'),
      ),
    );
    await repo.positionAustauschen(await mitte(), zutatId: schwein);
    expect((await mitte()).etikettName, 'Schweinefleisch');

    // Genau eines von beiden.
    await expectLater(
      repo.positionAustauschen(await mitte()),
      throwsArgumentError,
    );
    await expectLater(
      repo.positionAustauschen(
        await mitte(),
        zutatId: salz,
        unterrezepturId: roest,
      ),
      throwsArgumentError,
    );

    // Nur im Entwurf.
    await repo.versionAbschliessen(v.id);
    await expectLater(
      repo.positionAustauschen(await mitte(), zutatId: salz),
      throwsStateError,
    );
  });

  test('Artikelnummern aus dem Katalog — auch gelöschter', () async {
    final schwein = await repo.zutatAnlegen(
      const EntwicklungZutatenCompanion(
        name: Value('Schweinefleisch'),
        artikelnummer: Value(' 10010 '),
      ),
    );
    final ohne = await zutat('Speisesalz');
    final leer = await repo.zutatAnlegen(
      const EntwicklungZutatenCompanion(
        name: Value('Pfeffer'),
        artikelnummer: Value('  '),
      ),
    );
    final weg = await repo.zutatAnlegen(
      const EntwicklungZutatenCompanion(
        name: Value('Majoran'),
        artikelnummer: Value('30020'),
      ),
    );
    await repo.zutatLoeschen(weg);
    final braet = await repo.rezepturAnlegen(
      name: 'Kräuterbrät',
      artikelnummer: '50100',
    );
    final ohneNummer = await repo.rezepturAnlegen(name: 'Würzmischung');

    final n = await repo.artikelnummern();
    expect(n.zutaten, {schwein: '10010', weg: '30020'});
    expect(n.zutaten.containsKey(ohne), isFalse);
    expect(n.zutaten.containsKey(leer), isFalse);
    expect(n.rezepturen, {braet: '50100'});
    expect(n.rezepturen.containsKey(ohneNummer), isFalse);
  });

  test('Vergleich zweier Stände: neu, entfernt, geändert', () {
    const salz = RechenZutat(id: 'salz', name: 'Salz');
    const pfeffer = RechenZutat(id: 'pfeffer', name: 'Pfeffer');
    const muskat = RechenZutat(id: 'muskat', name: 'Muskat');
    const a = RechenRezeptur(
      id: 'r',
      name: 'R',
      positionen: [
        RechenPosition.zutat(salz, mengeKg: 2),
        RechenPosition.zutat(pfeffer, mengeKg: 1),
      ],
    );
    const b = RechenRezeptur(
      id: 'r',
      name: 'R',
      positionen: [
        RechenPosition.zutat(salz, mengeKg: 2.5),
        RechenPosition.zutat(muskat, mengeKg: 0.2),
      ],
    );
    final zeilen = vergleicheZeilen(a, b);
    expect(zeilen.map((z) => z.name), ['Salz', 'Pfeffer', 'Muskat']);
    expect(zeilen[0].geaendert, isTrue);
    expect(zeilen[1].entfernt, isTrue);
    expect(zeilen[2].neu, isTrue);
  });

  test('Mengen und Eingaben mit Komma', () {
    expect(mengeText(12.5), '12,5');
    expect(mengeText(0.125), '0,125');
    expect(mengeText(100), '100');
    expect(mengeText(1250), '1.250');
    expect(zahlAus('12,5'), 12.5);
    expect(zahlAus(' 0.25 '), 0.25);
    expect(zahlAus(''), isNull);
    expect(zahlAus('abc'), isNull);
    expect(feldText(12.5), '12,5');
    expect(feldText(100), '100');
    expect(feldText(null), '');
  });
}
