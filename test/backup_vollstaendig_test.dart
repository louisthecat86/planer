import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/backup_service.dart';
import 'package:produktion_planer/features/entwicklung/entwicklung_zugang.dart';

import 'helpers/test_db.dart';

/// Das Backup trägt alles: In jeder Tabelle der Datenbank steht eine
/// Zeile, jede Spalte gefüllt — nach Komplett-Backup und Wiederherstellen
/// auf einem leeren „anderen Rechner" steht dort dasselbe.
///
/// Der Test kennt die Tabellen nicht beim Namen, er fragt die Datenbank.
/// Kommt eine Tabelle dazu und fehlt im Backup, schlägt er fehl — statt
/// dass es erst beim Wiederherstellen auffällt. Alle Zeilen sind erfunden.
void main() {
  /// Bewusst nicht im Backup — zurzeit nichts. (Bis Backup-Version 1.7
  /// fehlte der Auftragsbestand; seit 1.8 steht er drin.)
  ///
  /// Wer hier eine Tabelle einträgt, entscheidet, dass ihr Inhalt ein
  /// Wiederherstellen nicht überstehen muss.
  const nichtImBackup = <String>{};

  /// Der Auftragsbestand: der eingelesene Bericht und der Stand davor.
  const auftragsbestand = [
    'auftragsbestand_artikel',
    'auftragsbestand_positionen',
    'auftragsbestand_artikel_vorher',
    'auftragsbestand_positionen_vorher',
  ];

  /// Spalten, die ohne Fremdschlüssel auf eine andere Tabelle zeigen: der
  /// Inhalt gehört zu seiner Datei, das Bild zu seinem Foto.
  const gehoertZu = {
    'artikel_foto_inhalte.foto_id': 'artikel_fotos',
    'entwicklung_datei_inhalte.datei_id': 'entwicklung_dateien',
  };

  // Zwei Datenbanken zugleich sind Absicht (der „andere Rechner").
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory ordner;

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('planer_vollstaendig_');
    BackupService.ordnerFuerTests = ordner;
  });

  tearDown(() {
    BackupService.ordnerFuerTests = null;
    if (ordner.existsSync()) ordner.deleteSync(recursive: true);
  });

  Future<List<String>> tabellen(AppDatabase db) async => [
        for (final z in await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table' "
              "AND name NOT LIKE 'sqlite_%' ORDER BY name",
            )
            .get())
          z.read<String>('name'),
      ];

  /// Schreibt in jede Tabelle eine Zeile: Texte „x", Zahlen 1 und 1,5,
  /// der Schlüssel „id-<tabelle>", ein Verweis auf den Schlüssel der
  /// Tabelle, auf die er zeigt.
  Future<void> fuellen(AppDatabase db) async {
    await db.customStatement('PRAGMA foreign_keys = OFF');
    for (final t in await tabellen(db)) {
      final verweise = {
        for (final z
            in await db.customSelect("PRAGMA foreign_key_list('$t')").get())
          z.read<String>('from'): z.read<String>('table'),
      };
      final spalten = await db.customSelect("PRAGMA table_info('$t')").get();
      final werte = <Object>[
        for (final s in spalten)
          switch (s.read<String>('type').toUpperCase()) {
            'INTEGER' => 1,
            'REAL' => 1.5,
            'BLOB' => [1, 2, 3],
            _ => switch (verweise[s.read<String>('name')] ??
                  gehoertZu['$t.${s.read<String>('name')}']) {
                final ziel? => 'id-$ziel',
                null => s.read<int>('pk') > 0 ? 'id-$t' : 'x',
              },
          },
      ];
      final namen = [
        for (final s in spalten) '"${s.read<String>('name')}"',
      ];
      await db.customStatement(
        'INSERT OR REPLACE INTO "$t" (${namen.join(', ')}) '
        'VALUES (${List.filled(namen.length, '?').join(', ')})',
        werte,
      );
    }
    await db.customStatement('PRAGMA foreign_keys = ON');
  }

  /// Alle Zeilen einer Tabelle, lesbar zum Vergleichen.
  ///
  /// Bei den Einstellungen ohne `updated_at`: Den Schlüssel der
  /// Produktentwicklung schreibt der andere Rechner beim Entsperren selbst
  /// — mit seiner Uhrzeit. Verglichen werden dort Name und Wert.
  Future<List<String>> zeilen(AppDatabase db, String tabelle) async => [
        for (final z in await db.customSelect('SELECT * FROM "$tabelle"').get())
          jsonEncode(
            {
              for (final MapEntry(:key, :value) in z.data.entries)
                if (tabelle != 'app_settings' || key != 'updated_at')
                  key: value,
            },
            toEncodable: (o) => '$o',
          ),
      ]..sort();

  test('jede Tabelle kommt aus dem Komplett-Backup zurück', () async {
    final db = testDatenbank();
    addTearDown(db.close);
    // Die Produktentwicklung ist eingerichtet — sonst stünde ihr Teil gar
    // nicht im Backup.
    await EntwicklungZugang(
      DbEntwicklungsSpeicher(db),
      iterationen: 1000,
      imHintergrund: false,
    ).festlegen('geheim123');
    await fuellen(db);

    final inhalt = await BackupService.backupInhalt(db);
    final datei = File('${ordner.path}/komplett.planerbackup')
      ..writeAsBytesSync(gzip.encode(utf8.encode(jsonEncode(inhalt))));

    final anderer = testDatenbank();
    addTearDown(anderer.close);
    await BackupService.importBackup(
      datei.path,
      anderer,
      sicherungAnlegen: false,
    );

    // Der Teil der Produktentwicklung wartet auf dem anderen Rechner, bis
    // dort das Passwort eingegeben ist, das hier galt.
    final zugang = EntwicklungZugang(
      DbEntwicklungsSpeicher(anderer),
      iterationen: 1000,
      imHintergrund: false,
    );
    expect(await zugang.backupWartet(), isTrue);
    expect(await zugang.oeffnen('geheim123'), isTrue);

    final alle = await tabellen(db);
    expect(alle, containsAll(nichtImBackup));
    for (final t in alle) {
      final vorher = await zeilen(db, t);
      expect(vorher, isNotEmpty, reason: 'Vorbedingung: $t ist gefüllt');
      final nachher = await zeilen(anderer, t);
      if (nichtImBackup.contains(t)) {
        expect(nachher, isEmpty, reason: '$t steht doch im Backup?');
      } else {
        expect(
          nachher,
          vorher,
          reason: '$t kommt nicht so aus dem Backup zurück, wie es '
              'hineinging. Eine neue Tabelle gehört in BackupService '
              '(_buildBackupPayload, Einspielen, _clearDatabase) — oder, '
              'als bewusste Entscheidung, in nichtImBackup.',
        );
      }
    }
  });

  test('ein Backup bringt seinen Auftragsbestand mit — auch einen leeren',
      () async {
    final db = testDatenbank();
    addTearDown(db.close);
    // Gesichert ohne Auftragsbestand, danach kommt einer dazu.
    final pfad = await BackupService.createAutoBackup(db);
    await fuellen(db);

    await BackupService.importBackup(pfad, db, sicherungAnlegen: false);

    // Wie zum Zeitpunkt der Sicherung: leer.
    for (final t in auftragsbestand) {
      expect(await zeilen(db, t), isEmpty, reason: t);
    }
  });

  test(
      'ein älteres Backup kennt den Auftragsbestand nicht — der des '
      'Rechners bleibt', () async {
    final db = testDatenbank();
    addTearDown(db.close);
    // Ein Backup, wie es die App bis Version 1.7 schrieb.
    final inhalt = await BackupService.backupInhalt(db);
    inhalt['version'] = '1.7';
    final daten = inhalt['data'] as Map<String, dynamic>;
    auftragsbestand.forEach(daten.remove);
    final datei = File('${ordner.path}/alt.planerbackup')
      ..writeAsBytesSync(gzip.encode(utf8.encode(jsonEncode(inhalt))));
    await fuellen(db);

    await BackupService.importBackup(
      datei.path,
      db,
      sicherungAnlegen: false,
    );

    for (final t in auftragsbestand) {
      expect(await zeilen(db, t), hasLength(1), reason: t);
    }
    // Alles andere ist wieder so leer wie im Backup.
    expect(await zeilen(db, 'products'), isEmpty);
  });

  test(
      'ein älteres Backup kennt den Stand der Navision-Artikelübersicht '
      'nicht — der des Rechners bleibt', () async {
    final db = testDatenbank();
    addTearDown(db.close);
    // Ein Backup, wie es die App bis Version 1.8 schrieb.
    final inhalt = await BackupService.backupInhalt(db);
    inhalt['version'] = '1.8';
    (inhalt['data'] as Map<String, dynamic>).remove('navision_artikel');
    final datei = File('${ordner.path}/alt18.planerbackup')
      ..writeAsBytesSync(gzip.encode(utf8.encode(jsonEncode(inhalt))));
    await fuellen(db);

    await BackupService.importBackup(
      datei.path,
      db,
      sicherungAnlegen: false,
    );

    expect(await zeilen(db, 'navision_artikel'), hasLength(1));
    expect(await zeilen(db, 'products'), isEmpty);
  });

  test('ein Backup ab 1.9 bringt seinen Stand mit — auch einen leeren',
      () async {
    final db = testDatenbank();
    addTearDown(db.close);
    final pfad = await BackupService.createAutoBackup(db);
    await fuellen(db);

    await BackupService.importBackup(pfad, db, sicherungAnlegen: false);

    expect(await zeilen(db, 'navision_artikel'), isEmpty);
  });
}
