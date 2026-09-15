import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/backup_service.dart';

import 'helpers/test_db.dart';

/// Tests für `BackupService.importBackup` — das Wiederherstellen.
///
/// Warum nur die Import-Hälfte: Der Export geht über den FilePicker und den
/// Anwendungsordner (`path_provider`), beides Flutter-Plugins, die im
/// reinen Dart-Test nicht zur Verfügung stehen. Der Import lässt sich
/// dagegen vollständig prüfen, wenn man ihm eine selbst geschriebene Datei
/// vorlegt — und genau dort sitzt das Risiko: Diese Funktion LÖSCHT
/// zuerst alles.
///
/// `sicherungAnlegen: false` ist in den Tests nötig, weil die
/// Sicherungskopie in den Backup-Ordner schreiben würde.
void main() {
  late AppDatabase db;
  late Directory tempDir;

  setUp(() async {
    db = testDatenbank();
    tempDir = await Directory.systemTemp.createTemp('planer_test_');
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Schreibt eine Backup-Datei mit den übergebenen Tabellen.
  Future<String> schreibeBackup(
    Map<String, dynamic> daten, {
    String version = '1.4',
  }) async {
    final datei = File('${tempDir.path}/test.planerbackup');
    await datei.writeAsString(
      jsonEncode({
        'version': version,
        'timestamp': DateTime.now().toIso8601String(),
        'data': daten,
      }),
    );
    return datei.path;
  }

  group('Wiederherstellen', () {
    test('spielt Artikel und Schritte ein', () async {
      final pfad = await schreibeBackup({
        'products': [
          {
            'id': 'p1',
            'artikelnummer': '1001',
            'artikelbezeichnung': 'Testwurst',
            'istEingepflegt': true,
            'createdAt': 0,
            'updatedAt': 0,
          },
        ],
        'product_steps': [
          {
            'id': 's1',
            'productId': 'p1',
            'reihenfolge': 1,
            'abteilung': 'zerlegung',
            'basisMengeKg': 100.0,
            'basisDauerMinuten': 60.0,
            'basisMitarbeiter': 2,
            'basisAnzahlMessungen': 0,
            'createdAt': 0,
            'updatedAt': 0,
          },
        ],
      });

      await BackupService.importBackup(pfad, db, sicherungAnlegen: false);

      final artikel = await db.select(db.products).get();
      final schritte = await db.select(db.productSteps).get();
      expect(artikel.length, 1);
      expect(artikel.single.artikelbezeichnung, 'Testwurst');
      expect(schritte.length, 1);
    });

    test('löscht vorhandene Daten, wenn clearExisting gesetzt ist', () async {
      await seedArtikel(db, id: 'alt', nummer: '9999');

      final pfad = await schreibeBackup({
        'products': [
          {
            'id': 'p1',
            'artikelnummer': '1001',
            'artikelbezeichnung': 'Neu',
            'istEingepflegt': true,
            'createdAt': 0,
            'updatedAt': 0,
          },
        ],
      });

      await BackupService.importBackup(pfad, db, sicherungAnlegen: false);

      final artikel = await db.select(db.products).get();
      expect(artikel.length, 1);
      expect(artikel.single.artikelnummer, '1001');
    });

    test('ergänzt istEingepflegt in alten Backups', () async {
      // Backups vor Einführung der Spalte kennen den Schlüssel nicht.
      // Fehlt die Ergänzung, scheitert der Import mit einem Null-Fehler.
      final pfad = await schreibeBackup(
        {
          'products': [
            {
              'id': 'p1',
              'artikelnummer': '1001',
              'artikelbezeichnung': 'Altbestand',
              'createdAt': 0,
              'updatedAt': 0,
            },
          ],
        },
        version: '1.0',
      );

      await BackupService.importBackup(pfad, db, sicherungAnlegen: false);

      final artikel = await db.select(db.products).get();
      expect(artikel.single.istEingepflegt, isTrue);
    });
  });

  group('Fehlerfälle — nichts darf zerstört werden', () {
    test('unbekannte Version wird abgelehnt', () async {
      await seedArtikel(db, id: 'alt', nummer: '9999');
      final pfad = await schreibeBackup({}, version: '99.0');

      await expectLater(
        BackupService.importBackup(pfad, db, sicherungAnlegen: false),
        throwsA(isA<Exception>()),
      );

      // Der Bestand muss unangetastet sein.
      final artikel = await db.select(db.products).get();
      expect(artikel.length, 1);
      expect(artikel.single.artikelnummer, '9999');
    });

    test('beschädigte Datei wird abgelehnt', () async {
      await seedArtikel(db, id: 'alt', nummer: '9999');
      final datei = File('${tempDir.path}/kaputt.planerbackup');
      // Abgeschnitten, wie nach einem abgebrochenen USB-Transfer.
      await datei.writeAsString('{"version":"1.4","timestamp":"2026');

      await expectLater(
        BackupService.importBackup(datei.path, db, sicherungAnlegen: false),
        throwsA(isA<Exception>()),
      );

      final artikel = await db.select(db.products).get();
      expect(artikel.length, 1);
    });

    test('fehlende Datei wird abgelehnt', () async {
      await expectLater(
        BackupService.importBackup(
          '${tempDir.path}/gibtesnicht.planerbackup',
          db,
          sicherungAnlegen: false,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('ein Fehler mitten im Import rollt alles zurück', () async {
      await seedArtikel(db, id: 'alt', nummer: '9999');

      // Zweiter Artikel mit derselben Artikelnummer — die Spalte ist
      // unique, der zweite Insert muss scheitern. Entscheidend: Auch der
      // erste darf danach NICHT in der Datenbank stehen.
      final pfad = await schreibeBackup({
        'products': [
          {
            'id': 'p1',
            'artikelnummer': '1001',
            'artikelbezeichnung': 'Erster',
            'istEingepflegt': true,
            'createdAt': 0,
            'updatedAt': 0,
          },
          {
            'id': 'p2',
            'artikelnummer': '1001',
            'artikelbezeichnung': 'Doppelte Nummer',
            'istEingepflegt': true,
            'createdAt': 0,
            'updatedAt': 0,
          },
        ],
      });

      await expectLater(
        BackupService.importBackup(pfad, db, sicherungAnlegen: false),
        throwsA(isA<Exception>()),
      );

      final artikel = await db.select(db.products).get();
      expect(
        artikel.where((p) => p.artikelbezeichnung == 'Erster'),
        isEmpty,
        reason: 'Die Transaktion hat nicht zurückgerollt — '
            'es stehen Teildaten in der Datenbank.',
      );
    });
  });
}
