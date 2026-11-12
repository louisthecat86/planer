import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';

import 'helpers/test_db.dart';

/// Eine Datenbank aus jedem früheren Stand der App öffnet sich mit dem
/// heutigen: Danach hat sie dasselbe Schema wie eine neu angelegte, keine
/// Zeile ist verloren, und jede Tabelle lässt sich lesen.
///
/// `test/schemata/vNN.sql` ist das Schema, wie die App es in Version NN
/// frisch angelegt hat — erzeugt aus dem Stand des Repositories, in dem
/// diese Version galt. Daten stehen dort keine; die Zeilen hier sind
/// erfunden: je Tabelle eine, jede Spalte gefüllt.
///
/// Ändert sich eine Tabelle, muss `schemaVersion` steigen und `onUpgrade`
/// den Schritt bekommen. Der erste Test hier merkt, wenn eins von beiden
/// fehlt. Für eine neue Version legt er `vNN.sql` selbst an und sagt das —
/// die Datei gehört dann mit eingecheckt; von da an prüft der Test auch
/// den neuen Schritt.
void main() {
  final dateien = Directory('test/schemata')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  int versionVon(File f) => int.parse(
        RegExp(r'v(\d+)\.sql$').firstMatch(f.path)!.group(1)!,
      );

  /// Ein Wert, der zur Spalte passt.
  Object wertFuer(String tabelle, String spalte, String typ, bool pk) =>
      switch (typ.toUpperCase()) {
        'INTEGER' => 1,
        'REAL' => 1.5,
        'BLOB' => [1, 2, 3],
        _ => pk ? 'id-$tabelle' : 'x',
      };

  /// Bekannte Abweichung: Diese Vorgabe hat sich zwischen Version 4 und
  /// 21 geändert (540 und 480 statt heute 600 Minuten), und SQLite ändert
  /// die Vorgabe einer bestehenden Spalte nicht. Auf einer so alten
  /// Datenbank bekommt eine Anlage, die ohne Kapazität angelegt wird, den
  /// alten Wert — die Anlagen-Verwaltung setzt sie immer selbst.
  const vorgabeDarfAbweichen = {'machines.kapazitaet_minuten_pro_tag'};

  /// Spalten einer Tabelle: Name → „TYP [NOT NULL] [PK] [DEFAULT …]".
  Future<Map<String, String>> spalten(AppDatabase db, String tabelle) async => {
        for (final z
            in await db.customSelect("PRAGMA table_info('$tabelle')").get())
          z.read<String>('name'): [
            z.read<String>('type').toUpperCase(),
            if (z.read<int>('notnull') == 1) 'NOT NULL',
            if (z.read<int>('pk') > 0) 'PK',
            if (!vorgabeDarfAbweichen
                .contains('$tabelle.${z.read<String>('name')}'))
              if (z.readNullable<String>('dflt_value') case final d?)
                'DEFAULT $d',
          ].join(' '),
      };

  /// Das Schema von [db], wie es in `vNN.sql` steht.
  Future<String> schemaText(AppDatabase db) async {
    final zeilen = await db
        .customSelect(
          "SELECT sql FROM sqlite_master "
          "WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' "
          "ORDER BY CASE type WHEN 'table' THEN 0 ELSE 1 END, name",
        )
        .get();
    return [
      for (final z in zeilen)
        '${z.read<String>('sql').replaceAll('\n', ' ')};\n',
    ].join();
  }

  Future<Set<String>> namen(AppDatabase db, String art) async => {
        for (final z in await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = '$art' "
              "AND name NOT LIKE 'sqlite_%'",
            )
            .get())
          z.read<String>('name'),
      };

  /// Bekannte Abweichung: Diese Indizes legt nur die Migration an, nicht
  /// `onCreate` — einer neu angelegten Datenbank fehlen sie. Das kostet
  /// dort höchstens Tempo, keine Daten. Wer sie nachzieht, leert die Liste.
  const nurNachMigration = {
    'idx_week_snapshots_start',
    'idx_production_tasks_maschine',
    'idx_production_tasks_bedarf',
  };

  /// [db] hat dieselben Tabellen, Spalten und Indizes wie [neu] — an
  /// Indizes höchstens [mehrIndizes] dazu.
  Future<void> gleichesSchema(
    AppDatabase db,
    AppDatabase neu, {
    Set<String> mehrIndizes = const {},
  }) async {
    final tabellenNeu = await namen(neu, 'table');
    expect(
      (await namen(db, 'table')).difference(tabellenNeu),
      isEmpty,
      reason: 'Tabellen, die es in einer neuen Datenbank nicht gibt',
    );
    for (final t in tabellenNeu) {
      expect(
        await spalten(db, t),
        await spalten(neu, t),
        reason: 'Spalten von $t',
      );
    }
    final indizes = await namen(db, 'index');
    final indizesNeu = await namen(neu, 'index');
    expect(
      indizesNeu.difference(indizes),
      isEmpty,
      reason: 'Indizes, die fehlen',
    );
    expect(
      indizes.difference(indizesNeu).difference(mehrIndizes),
      isEmpty,
      reason: 'Indizes, die eine neue Datenbank nicht hat',
    );
  }

  test('das heutige Schema liegt als vNN.sql vor — und passt dazu', () async {
    final db = testDatenbank();
    addTearDown(db.close);
    final heute = await schemaText(db);
    final nn = db.schemaVersion.toString().padLeft(2, '0');
    final datei = File('test/schemata/v$nn.sql');

    if (!datei.existsSync()) {
      datei.writeAsStringSync(heute);
      fail(
        'Für Schema-Version ${db.schemaVersion} gab es noch kein '
        '${datei.path} — die Datei ist jetzt angelegt. Bitte mit '
        'einchecken und die Tests noch einmal laufen lassen: Dann wird '
        'auch der Schritt von der vorigen Version geprüft.',
      );
    }
    // Eine Datenbank aus der Datei, schon auf der heutigen Version: Sie
    // wird nicht migriert und muss doch aussehen wie eine neue. Tut sie
    // das nicht, haben sich die Tabellen geändert, die schemaVersion in
    // database.dart aber nicht. Jede Änderung an einer Tabelle braucht
    // eine höhere schemaVersion und einen Schritt in onUpgrade — sonst
    // fehlt sie den Datenbanken, die es schon gibt.
    final ausDatei = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (roh) => roh
          ..execute(datei.readAsStringSync())
          ..execute('PRAGMA user_version = ${db.schemaVersion}'),
      ),
    );
    addTearDown(ausDatei.close);
    await gleichesSchema(ausDatei, db);
  });

  for (final datei in dateien) {
    final version = versionVon(datei);

    test('von Version $version auf heute', () async {
      final schema = datei.readAsStringSync();
      final vorher = <String, int>{};

      final db = AppDatabase.forTesting(
        NativeDatabase.memory(
          setup: (roh) {
            roh.execute(schema);
            final tabellen = [
              for (final z in roh.select(
                "SELECT name FROM sqlite_master WHERE type = 'table' "
                "AND name NOT LIKE 'sqlite_%'",
              ))
                z['name'] as String,
            ];
            for (final t in tabellen) {
              final spalten = roh.select("PRAGMA table_info('$t')");
              final namen = [for (final s in spalten) '"${s['name']}"'];
              roh.execute(
                'INSERT INTO "$t" (${namen.join(', ')}) '
                'VALUES (${List.filled(namen.length, '?').join(', ')})',
                [
                  for (final s in spalten)
                    wertFuer(
                      t,
                      s['name'] as String,
                      s['type'] as String,
                      (s['pk'] as int) > 0,
                    ),
                ],
              );
              vorher[t] = 1;
            }
            roh.execute('PRAGMA user_version = $version');
          },
        ),
      );
      addTearDown(db.close);
      final neu = testDatenbank();
      addTearDown(neu.close);

      // Der erste Zugriff stößt die Migration an.
      await db.customSelect('SELECT 1').get();

      // Dasselbe Schema wie eine neu angelegte Datenbank.
      await gleichesSchema(db, neu, mehrIndizes: nurNachMigration);
      final tabellenNeu = await namen(neu, 'table');

      // Keine Zeile verloren.
      for (final t in vorher.keys.where(tabellenNeu.contains)) {
        final n = await db
            .customSelect('SELECT COUNT(*) AS n FROM "$t"')
            .map((z) => z.read<int>('n'))
            .getSingle();
        expect(n, greaterThanOrEqualTo(1), reason: 'Zeilen in $t');
      }

      // Und die App kann jede Tabelle lesen.
      for (final t in db.allTables) {
        await db.select(t).get();
      }
    });
  }
}
