import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/constants/entwicklung.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/backup_service.dart';
import 'package:produktion_planer/core/services/tagesaufgaben_service.dart';
import 'package:produktion_planer/features/entwicklung/entwicklung_zugang.dart';

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
  // Zwei Datenbanken zugleich sind hier Absicht (der „andere Rechner") —
  // jede mit eigenem Speicher, also ohne die Gefahr, vor der drift warnt.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

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

    test('spielt Tagesaufgaben ein und ersetzt die vorhandenen', () async {
      await TagesaufgabenService.anlegen(
        db,
        tag: DateTime(2026, 10, 6),
        abteilung: 'zerlegung',
        inhalt: 'Alter Eintrag',
      );

      final pfad = await schreibeBackup(
        {
          'tagesaufgaben': [
            {
              'id': 'a1',
              'datum': DateTime(2026, 10, 5).millisecondsSinceEpoch,
              'abteilung': 'wurstkueche',
              'inhalt': 'Kessel entkalken',
              'erledigt': true,
              'sortierung': 0,
              'createdAt': 0,
              'updatedAt': 0,
            },
          ],
        },
        version: '1.5',
      );

      await BackupService.importBackup(pfad, db, sicherungAnlegen: false);

      final aufgaben = await db.select(db.tagesaufgaben).get();
      expect(aufgaben.single.inhalt, 'Kessel entkalken');
      expect(aufgaben.single.abteilung, 'wurstkueche');
      expect(aufgaben.single.erledigt, isTrue);
      expect(aufgaben.single.datum, DateTime(2026, 10, 5));
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

  group('Produktentwicklung', () {
    Future<void> setze(String key, String value) => db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: key, value: value),
        );

    Future<Map<String, String>> einstellungen(AppDatabase d) async => {
          for (final s in await d.select(d.appSettings).get()) s.key: s.value,
        };

    EntwicklungZugang zugangFuer(AppDatabase d) => EntwicklungZugang(
          DbEntwicklungsSpeicher(d),
          iterationen: 1000,
          imHintergrund: false,
        );

    Future<void> zutat(AppDatabase d, String id, String name) => d
        .into(d.entwicklungZutaten)
        .insert(EntwicklungZutatenCompanion.insert(id: id, name: name));

    Future<List<String>> zutaten(AppDatabase d) async => [
          for (final z in await d.select(d.entwicklungZutaten).get()) z.name,
        ];

    var nummer = 0;
    Future<String> sichern(AppDatabase quelle) async {
      final inhalt = await BackupService.backupInhalt(quelle);
      final datei = File('${tempDir.path}/entwicklung_${++nummer}.planerbackup');
      await datei.writeAsString(jsonEncode(inhalt));
      return datei.path;
    }

    Map<String, dynamic> teilIn(Map<String, dynamic> inhalt) =>
        (inhalt['data'] as Map<String, dynamic>)['entwicklung']
            as Map<String, dynamic>;

    test('ohne Einrichtung steht kein Teil im Backup', () async {
      await setze('theme_mode', 'dark');
      final inhalt = await BackupService.backupInhalt(db);
      final daten = inhalt['data'] as Map<String, dynamic>;
      expect(daten.containsKey('entwicklung'), isFalse);
    });

    test('im Backup stehen die Daten nur verschlüsselt', () async {
      await setze('theme_mode', 'dark');
      await zugangFuer(db).festlegen('geheim123');
      await zutat(db, 'z1', 'Geheimgewürz Nr. 7');

      final inhalt = await BackupService.backupInhalt(db);

      expect(jsonEncode(inhalt), isNot(contains('Geheimgewürz')));
      final teil = teilIn(inhalt);
      expect(teil['format'], 2);
      expect(teil['daten'], isA<String>());
      expect(teil['passwort'], isA<String>());
      // Die allgemeinen Einstellungen tragen nichts davon — schon gar nicht
      // den Datenschlüssel im Klartext.
      final allgemein = [
        for (final z in (inhalt['data'] as Map<String, dynamic>)['app_settings']
            as List<dynamic>)
          (z as Map<String, dynamic>)['key'],
      ];
      expect(allgemein, ['theme_mode']);
      final schluessel = (await einstellungen(db))[kEntwicklungDatenschluessel];
      expect(jsonEncode(inhalt), isNot(contains(schluessel!)));
    });

    test('auf demselben Rechner zurückgespielt: sofort wieder da', () async {
      await zugangFuer(db).festlegen('geheim123');
      await zutat(db, 'z1', 'Geheimgewürz Nr. 7');
      final vorher = await einstellungen(db);
      final pfad = await sichern(db);
      await db.delete(db.entwicklungZutaten).go();

      await BackupService.importBackup(pfad, db, sicherungAnlegen: false);

      expect(await zutaten(db), ['Geheimgewürz Nr. 7']);
      final nachher = await einstellungen(db);
      expect(nachher[kEntwicklungDatenschluessel], vorher[kEntwicklungDatenschluessel]);
      expect(nachher[kEntwicklungAusstehend], isNull);
      expect(await zugangFuer(db).pruefen('geheim123'), isTrue);
    });

    test('auf einem anderen Rechner: wartet aufs Passwort des Backups',
        () async {
      final andere = testDatenbank();
      addTearDown(andere.close);
      await zugangFuer(andere).festlegen('geheim123');
      await zutat(andere, 'z1', 'Geheimgewürz Nr. 7');
      await andere.into(andere.entwicklungDateien).insert(
            EntwicklungDateienCompanion.insert(
              id: 'd1',
              name: 'Spezifikation.pdf',
            ),
          );
      await andere.into(andere.entwicklungDateiInhalte).insert(
            EntwicklungDateiInhalteCompanion.insert(
              dateiId: 'd1',
              inhalt: Uint8List.fromList([1, 2, 3]),
            ),
          );
      final pfad = await sichern(andere);

      // Dieser Rechner hat eigene Entwicklungsdaten mit eigenem Passwort.
      await zugangFuer(db).festlegen('anderes123');
      await zutat(db, 'hier', 'Alte Zutat');

      await BackupService.importBackup(pfad, db, sicherungAnlegen: false);

      // Noch gesperrt: Die alten Daten sind ersetzt, die neuen warten.
      expect(await zutaten(db), isEmpty);
      var werte = await einstellungen(db);
      expect(werte[kEntwicklungAusstehend], isNotNull);
      expect(werte[kEntwicklungDatenschluessel], isNull);

      // Es gilt das Passwort, das mit dem Backup kam.
      final zugang = zugangFuer(db);
      expect(await zugang.oeffnen('anderes123'), isFalse);
      expect(await zugang.oeffnen('geheim123'), isTrue);

      expect(await zutaten(db), ['Geheimgewürz Nr. 7']);
      final inhalte = await db.select(db.entwicklungDateiInhalte).get();
      expect(inhalte.single.inhalt, [1, 2, 3]);
      werte = await einstellungen(db);
      expect(werte[kEntwicklungAusstehend], isNull);
      expect(
        werte[kEntwicklungDatenschluessel],
        (await einstellungen(andere))[kEntwicklungDatenschluessel],
      );
    });

    test('ein wartender Teil geht unverändert ins nächste Backup', () async {
      final andere = testDatenbank();
      addTearDown(andere.close);
      await zugangFuer(andere).festlegen('geheim123');
      await zutat(andere, 'z1', 'Geheimgewürz Nr. 7');
      final pfad = await sichern(andere);
      final original = teilIn(
        jsonDecode(await File(pfad).readAsString()) as Map<String, dynamic>,
      );

      await BackupService.importBackup(pfad, db, sicherungAnlegen: false);
      final weiter = teilIn(await BackupService.backupInhalt(db));

      expect(weiter['daten'], original['daten']);
      expect(weiter['passwort'], original['passwort']);
    });

    test('ein Backup ohne ihren Teil lässt sie auf diesem Rechner stehen',
        () async {
      await zugangFuer(db).festlegen('geheim123');
      await zutat(db, 'z1', 'Geheimgewürz Nr. 7');
      final vorher = await einstellungen(db);

      final pfad = await schreibeBackup(
        {
          'app_settings': [
            {'key': 'theme_mode', 'value': 'dark', 'updatedAt': 0},
          ],
        },
        version: '1.5',
      );
      await BackupService.importBackup(pfad, db, sicherungAnlegen: false);

      expect(await zutaten(db), ['Geheimgewürz Nr. 7']);
      final nachher = await einstellungen(db);
      expect(nachher['theme_mode'], 'dark');
      expect(
        nachher[kEntwicklungPasswortSchluessel],
        vorher[kEntwicklungPasswortSchluessel],
      );
      expect(
        nachher[kEntwicklungDatenschluessel],
        vorher[kEntwicklungDatenschluessel],
      );
    });

    test('der DeepL-Schlüssel bleibt auf diesem Rechner', () async {
      await zugangFuer(db).festlegen('geheim123');
      await zutat(db, 'z1', 'Geheimgewürz Nr. 7');
      await setze(kEntwicklungDeeplSchluessel, 'schluessel-alt:fx');
      final pfad = await sichern(db);
      // Im Backup steht er nicht — weder offen noch im Entwicklungsteil.
      expect(await File(pfad).readAsString(), isNot(contains('schluessel-alt')));

      await setze(kEntwicklungDeeplSchluessel, 'schluessel-neu:fx');
      await BackupService.importBackup(pfad, db, sicherungAnlegen: false);

      // Das Einspielen ersetzt die Einstellungen der Entwicklung, lässt
      // aber den Schlüssel dieses Rechners stehen.
      expect(await zutaten(db), ['Geheimgewürz Nr. 7']);
      final werte = await einstellungen(db);
      expect(werte[kEntwicklungDeeplSchluessel], 'schluessel-neu:fx');
      expect(await zugangFuer(db).pruefen('geheim123'), isTrue);
    });

    test('ein Teil im ersten Format zählt wie keiner', () async {
      await setze(kEntwicklungPasswortSchluessel, 'datensatz-hier');

      final pfad = await schreibeBackup(
        {
          'entwicklung': {
            'einstellungen': {
              kEntwicklungPasswortSchluessel: 'datensatz-dort',
            },
          },
        },
        version: '1.5',
      );
      await BackupService.importBackup(pfad, db, sicherungAnlegen: false);

      final werte = await einstellungen(db);
      expect(werte[kEntwicklungPasswortSchluessel], 'datensatz-hier');
    });

    test('über die allgemeinen Einstellungen kommt nichts herein', () async {
      await setze(kEntwicklungPasswortSchluessel, 'datensatz-hier');

      final pfad = await schreibeBackup(
        {
          'app_settings': [
            {
              'key': kEntwicklungPasswortSchluessel,
              'value': 'eingeschmuggelt',
              'updatedAt': 0,
            },
          ],
        },
        version: '1.5',
      );
      await BackupService.importBackup(pfad, db, sicherungAnlegen: false);

      final werte = await einstellungen(db);
      expect(werte[kEntwicklungPasswortSchluessel], 'datensatz-hier');
    });

    test('ein beschädigter Teil bricht ab, bevor etwas gelöscht ist',
        () async {
      await seedArtikel(db, id: 'alt', nummer: '9999');

      final pfad = await schreibeBackup(
        {
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
          'entwicklung': {
            'format': 2,
            'passwort': '{}',
            'daten': '%%% kein Base64 %%%',
          },
        },
        version: '1.5',
      );

      await expectLater(
        BackupService.importBackup(pfad, db, sicherungAnlegen: false),
        throwsA(isA<Exception>()),
      );
      final artikel = await db.select(db.products).get();
      expect(artikel.single.artikelnummer, '9999');
    });
  });
}
