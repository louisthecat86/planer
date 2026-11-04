import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/backup_service.dart';
import 'package:produktion_planer/core/services/datei_ablage.dart';
import 'package:produktion_planer/core/utils/krypto.dart';
import 'package:produktion_planer/features/entwicklung/daten/dateien.dart';
import 'package:produktion_planer/features/entwicklung/entwicklung_zugang.dart';

import 'helpers/test_db.dart';

/// Tests für die schlanken Auto-Backups: gepackt, die angehängten Dateien
/// der Produktentwicklung einmal in der Ablage daneben, das Einspielen
/// daraus, gestaffeltes Aufbewahren, Aufräumen der Ablage und das Sichern
/// beim Beenden nur nach Änderungen. Alle Daten sind erfunden; jeder Test
/// arbeitet in einem eigenen Ordner.
void main() {
  // Zwei Datenbanken zugleich sind Absicht (der „andere Rechner").
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late Directory ordner;

  setUp(() async {
    db = testDatenbank();
    ordner = await Directory.systemTemp.createTemp('planer_ablage_');
    BackupService.ordnerFuerTests = ordner;
  });

  tearDown(() async {
    BackupService.ordnerFuerTests = null;
    await db.close();
    if (ordner.existsSync()) ordner.deleteSync(recursive: true);
  });

  final pdf = Uint8List.fromList(List.filled(300 * 1024, 7));
  final notiz = Uint8List.fromList(utf8.encode('Nur ein Muster.'));

  /// Richtet die Produktentwicklung ein und hängt zwei Dateien an — eine
  /// große und eine kleine. Gibt ihre IDs zurück.
  Future<List<String>> mitDateien(AppDatabase d) async {
    await EntwicklungZugang(
      DbEntwicklungsSpeicher(d),
      iterationen: 1000,
      imHintergrund: false,
    ).festlegen('geheim123');
    final dienst = EntwicklungDateienDienst(d);
    return [
      await dienst.speichern(name: 'Spezifikation.pdf', inhalt: pdf),
      await dienst.speichern(name: 'Notiz.txt', inhalt: notiz),
    ];
  }

  Directory ablage() => Directory(
        '${ordner.path}${Platform.pathSeparator}${DateiAblage.ordnerName}',
      );

  List<String> inAblage() => [
        for (final e in ablage().listSync())
          e.path.split(Platform.pathSeparator).last,
      ]..sort();

  Map<String, dynamic> lies(String pfad) {
    final bytes = File(pfad).readAsBytesSync();
    return jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>;
  }

  Map<String, dynamic> teilIn(Map<String, dynamic> backup) =>
      (backup['data'] as Map<String, dynamic>)['entwicklung']
          as Map<String, dynamic>;

  group('Auto-Backup', () {
    test('gepackt, die Dateien einmal in der Ablage daneben', () async {
      final ids = await mitDateien(db);

      final pfad = await BackupService.createAutoBackup(db);
      final bytes = File(pfad).readAsBytesSync();
      expect(bytes.take(2), [0x1f, 0x8b], reason: 'gepackt');
      final backup = lies(pfad);
      expect(backup['version'], '1.6');
      expect(backup['type'], 'auto');

      final teil = teilIn(backup);
      expect(teil.containsKey('dateien'), isFalse);
      final verweise = (teil['dateiVerweise'] as Map).cast<String, String>();
      expect(verweise.keys.toSet(), ids.toSet());
      expect(inAblage(), [for (final s in verweise.values) '$s.bin']..sort());
      // Die Prüfsummen stehen auch bei den Angaben der Dateien.
      for (final d in await db.select(db.entwicklungDateien).get()) {
        expect(d.pruefsumme, verweise[d.id]);
      }
      // Die große Datei steckt nicht im Backup.
      expect(bytes.length, lessThan(50 * 1024));
      // Keine Zwischendateien übrig.
      expect(
        ordner.listSync().where((e) => e.path.endsWith('.tmp')),
        isEmpty,
      );

      // Ein zweites Backup legt nichts neu ab.
      final zweites = await BackupService.createAutoBackup(db);
      expect(
        (teilIn(lies(zweites))['dateiVerweise'] as Map).cast<String, String>(),
        verweise,
      );
      expect(inAblage(), hasLength(2));

      // Die Liste liest die Version aus dem gepackten Kopf.
      final liste = await BackupService.listBackups();
      expect(liste.first.version, '1.6');
      expect(liste.first.isAuto, isTrue);
      expect(liste.first.istAeltereVersion, isFalse);
    });

    test('eine fehlende Prüfsumme trägt das nächste Backup nach', () async {
      final ids = await mitDateien(db);
      final inhalt = await (db.select(db.entwicklungDateiInhalte)
            ..where((i) => i.dateiId.equals(ids.first)))
          .getSingle();
      final erwartet = pruefsumme(inhalt.inhalt);
      final gespeichert = await (db.select(db.entwicklungDateien)
            ..where((d) => d.id.equals(ids.first)))
          .getSingle();
      expect(gespeichert.pruefsumme, erwartet, reason: 'beim Speichern');

      // Wie bei Dateien von vor der Ablage.
      await db.update(db.entwicklungDateien).write(
            const EntwicklungDateienCompanion(pruefsumme: Value(null)),
          );
      await BackupService.createAutoBackup(db);
      final nachher = await (db.select(db.entwicklungDateien)
            ..where((d) => d.id.equals(ids.first)))
          .getSingle();
      expect(nachher.pruefsumme, erwartet);
    });

    test('die Liste liest die Version aus dem Kopf einer gepackten Datei',
        () async {
      // Groß genug, dass nur der Anfang gelesen wird.
      final inhalt = jsonEncode({
        'version': '1.5',
        'timestamp': '2026-11-02T08:00:00.000',
        'data': {'notizen': List.filled(5000, 'Zeile mit etwas Text')},
      });
      File(
        '${ordner.path}${Platform.pathSeparator}'
        'planer_auto_backup_2026-11-02_080000.planerbackup',
      ).writeAsBytesSync(gzip.encode(utf8.encode(inhalt)));

      final info = (await BackupService.listBackups()).single;
      expect(info.version, '1.5');
      expect(info.timestamp, DateTime(2026, 11, 2, 8));
    });

    test('das Komplett-Backup trägt die Dateien selbst', () async {
      final ids = await mitDateien(db);
      final teil = teilIn(await BackupService.backupInhalt(db));
      expect(teil.containsKey('dateiVerweise'), isFalse);
      expect((teil['dateien'] as Map).keys.toSet(), ids.toSet());
    });
  });

  group('Einspielen', () {
    test('die Dateien kommen aus der Ablage zurück', () async {
      final ids = await mitDateien(db);
      final pfad = await BackupService.createAutoBackup(db);
      final dienst = EntwicklungDateienDienst(db);
      await dienst.loeschen(ids.first);
      expect(await dienst.lesen(ids.first), isNull);

      await BackupService.importBackup(pfad, db, sicherungAnlegen: false);

      expect(await dienst.lesen(ids.first), pdf);
      expect(await dienst.lesen(ids.last), notiz);
    });

    test('fehlt die Ablage, wird nichts eingespielt', () async {
      await mitDateien(db);
      final pfad = await BackupService.createAutoBackup(db);
      ablage().deleteSync(recursive: true);

      // Ein anderer Rechner — ohne die Dateien in seiner Datenbank.
      final anderer = testDatenbank();
      addTearDown(anderer.close);
      await seedArtikel(anderer, id: 'alt', nummer: '9999');
      await expectLater(
        BackupService.importBackup(pfad, anderer, sicherungAnlegen: false),
        throwsA(
          predicate(
            (e) => '$e'.contains('fehlen 2') && '$e'.contains('Komplett'),
          ),
        ),
      );
      // Nichts angefasst.
      final artikel = await anderer.select(anderer.products).get();
      expect(artikel.single.artikelnummer, '9999');
    });

    test('ohne Ablage, aber mit denselben Dateien in der Datenbank: geht',
        () async {
      final ids = await mitDateien(db);
      final pfad = await BackupService.createAutoBackup(db);
      ablage().deleteSync(recursive: true);

      await BackupService.importBackup(pfad, db, sicherungAnlegen: false);
      expect(await EntwicklungDateienDienst(db).lesen(ids.first), pdf);
    });

    test('ein verfälschter Inhalt in der Ablage zählt als fehlend', () async {
      await mitDateien(db);
      final pfad = await BackupService.createAutoBackup(db);
      for (final e in ablage().listSync().whereType<File>()) {
        final bytes = e.readAsBytesSync();
        bytes[bytes.length - 1] ^= 0xff;
        e.writeAsBytesSync(bytes);
      }
      final anderer = testDatenbank();
      addTearDown(anderer.close);
      await expectLater(
        BackupService.importBackup(pfad, anderer, sicherungAnlegen: false),
        throwsA(predicate((e) => '$e'.contains('fehlen 2'))),
      );
    });
  });

  group('Aufbewahren', () {
    // Mittwoch, 4. November 2026, mittags.
    final jetzt = DateTime(2026, 11, 4, 12);

    BackupInfo info(DateTime zeit) => BackupInfo(
          filename: 'planer_auto_backup_$zeit',
          filepath: '$zeit',
          timestamp: zeit,
          version: '1.6',
          sizeBytes: 1,
          isAuto: true,
        );

    test(
        'die letzten zehn, je Tag eins für sieben Tage, je Woche eins für '
        'vier Wochen', () {
      final heute = [
        for (var i = 0; i < 12; i++) DateTime(2026, 11, 4, 8, 20 * i),
      ];
      final frueher = [
        DateTime(2026, 11, 3, 10),
        DateTime(2026, 11, 3, 16),
        DateTime(2026, 11, 2, 9),
        DateTime(2026, 11, 1, 18),
        DateTime(2026, 10, 30, 7),
        DateTime(2026, 10, 28, 12),
        DateTime(2026, 10, 22, 8),
        DateTime(2026, 10, 19, 8),
        DateTime(2026, 10, 14, 8),
        DateTime(2026, 10, 7, 8),
      ];
      final alle = [...heute, ...frueher]..shuffle();
      final behalten = BackupService.behalteneBackups(
        [for (final z in alle) info(z)],
        jetzt,
      );

      expect(behalten, {
        // Die letzten zehn — alle von heute.
        for (final z in heute.skip(2)) '$z',
        // Je Tag das letzte: gestern, vorgestern, Sonntag, Freitag.
        '${DateTime(2026, 11, 3, 16)}',
        '${DateTime(2026, 11, 2, 9)}',
        '${DateTime(2026, 11, 1, 18)}',
        '${DateTime(2026, 10, 30, 7)}',
        // Je Woche das letzte: die Woche vom 19. und die vom 12. Oktober.
        '${DateTime(2026, 10, 22, 8)}',
        '${DateTime(2026, 10, 14, 8)}',
      });
    });

    test('Aufräumen im Ordner: nur Auto-Backups, Reste vom Schreiben',
        () async {
      String name(String art, DateTime z) =>
          '${art}_${z.year}-${z.month.toString().padLeft(2, '0')}-'
          '${z.day.toString().padLeft(2, '0')}_'
          '${z.hour.toString().padLeft(2, '0')}0000.planerbackup';
      File datei(String n) => File('${ordner.path}${Platform.pathSeparator}$n')
        ..writeAsStringSync('{"version":"1.5"}');

      // Elf Auto-Backups von heute, eines von vor sechs Wochen.
      for (var h = 0; h < 11; h++) {
        datei(name('planer_auto_backup', DateTime(2026, 11, 4, h)));
      }
      final alt = datei(name('planer_auto_backup', DateTime(2026, 9, 20, 8)));
      final komplett = datei(name('planer_komplett', DateTime(2026, 9, 1, 8)));
      final vorRestore =
          datei(name('planer_vor_restore', DateTime(2026, 9, 2, 8)));
      final rest = File(
        '${ordner.path}${Platform.pathSeparator}planer_auto_backup_x.'
        'planerbackup.tmp',
      )..writeAsStringSync('halb');
      rest.setLastModifiedSync(jetzt.subtract(const Duration(days: 2)));

      await BackupService.cleanupOldAutoBackups(jetzt: jetzt);

      final autos = [
        for (final b in await BackupService.listBackups())
          if (b.isAuto) b,
      ];
      // Die zehn neuesten von heute — das älteste von heute ist zugleich
      // nicht das letzte des Tages und fällt weg, ebenso das von vor sechs
      // Wochen.
      expect(autos, hasLength(10));
      expect(alt.existsSync(), isFalse);
      expect(komplett.existsSync(), isTrue);
      expect(vorRestore.existsSync(), isTrue);
      expect(rest.existsSync(), isFalse);
    });
  });

  group('Ablage aufräumen', () {
    test('weg kommt, was kein Backup nennt und älter als ein Tag ist',
        () async {
      await mitDateien(db);
      await BackupService.createAutoBackup(db);
      final gebraucht = inAblage();
      final jetzt = DateTime.now().add(const Duration(days: 3));
      // Auch die gebrauchten sind alt — sie bleiben trotzdem.
      for (final e in ablage().listSync().whereType<File>()) {
        e.setLastModifiedSync(jetzt.subtract(const Duration(days: 2)));
      }
      File fremd(String zeichen, DateTime zeit) => File(
            '${ablage().path}${Platform.pathSeparator}'
            '${zeichen * 64}.bin',
          )
            ..writeAsBytesSync([1, 2, 3])
            ..setLastModifiedSync(zeit);
      final altUndFremd = fremd('a', jetzt.subtract(const Duration(days: 2)));
      final frischUndFremd = fremd('b', jetzt);

      await BackupService.dateienAufraeumen(jetzt: jetzt);
      expect(altUndFremd.existsSync(), isFalse);
      expect(frischUndFremd.existsSync(), isTrue);
      for (final n in gebraucht) {
        expect(inAblage(), contains(n));
      }

      // Höchstens einmal am Tag.
      final spaeter = fremd('c', jetzt.subtract(const Duration(days: 2)));
      await BackupService.dateienAufraeumen(jetzt: jetzt);
      expect(spaeter.existsSync(), isTrue);
      await BackupService.dateienAufraeumen(
        jetzt: jetzt.add(const Duration(days: 1)),
      );
      expect(spaeter.existsSync(), isFalse);
    });
  });

  test('beim Beenden nur sichern, wenn sich etwas geändert hat', () async {
    expect(
      await BackupService.hatAenderungenSeitLetztemBackup(db),
      isTrue,
      reason: 'noch kein Backup in diesem Lauf',
    );
    await seedArtikel(db, id: 'p1', nummer: '4711');
    await BackupService.createAutoBackup(db);
    expect(await BackupService.hatAenderungenSeitLetztemBackup(db), isFalse);

    await seedArtikel(db, id: 'p2', nummer: '4712');
    expect(await BackupService.hatAenderungenSeitLetztemBackup(db), isTrue);
    await BackupService.createAutoBackup(db);
    expect(await BackupService.hatAenderungenSeitLetztemBackup(db), isFalse);
  });

  test('Versionen vergleichen: ältere Formate erkennen', () {
    expect(vergleicheVersion('1.10', '1.9'), greaterThan(0));
    expect(vergleicheVersion('1.6', '1.6'), 0);
    expect(vergleicheVersion('1.3', '1.4'), lessThan(0));
    BackupInfo mit(String v) => BackupInfo(
          filename: 'b',
          filepath: 'b',
          timestamp: DateTime(2026, 11, 4),
          version: v,
          sizeBytes: 1,
          isAuto: false,
        );
    expect(mit('1.3').istAeltereVersion, isTrue);
    expect(mit('1.5').istAeltereVersion, isFalse);
    expect(mit('1.6').istAeltereVersion, isFalse);
  });
}
