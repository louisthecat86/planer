import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/produktion_erfassen_service.dart';
import 'package:produktion_planer/core/services/stammdaten_export_service.dart';
import 'package:produktion_planer/core/services/stammdaten_import_service.dart';

import 'helpers/test_db.dart';

/// Tests für den Block „HISTORISCHE DATEN" der Stammdaten-Mappe: Die
/// erfassten Produktionen gehen samt Fleischeinwaage hinaus und kommen
/// wieder herein — auch aus älteren Mappen, die die Spalte noch nicht
/// kennen. Alle Daten sind erfunden.
void main() {
  // Zwei Datenbanken zugleich sind Absicht: die eine exportiert, die andere
  // liest die Mappe ein — wie auf einem zweiten Rechner.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase quelle;

  setUp(() => quelle = testDatenbank());
  tearDown(() => quelle.close());

  /// Zwei Produktionen eines Artikels: eine mit, eine ohne Fleischeinwaage.
  Future<Uint8List> mappe() async {
    await seedArtikel(quelle, id: 'p1', nummer: '4711');
    await ProduktionErfassenService.speichere(
      db: quelle,
      productId: 'p1',
      datum: DateTime(2026, 11, 2),
      kgRohware: 1000,
      kgFleischeinwaage: 820,
      kgFertigware: 900,
      startzeit: '06:00',
      endzeit: '09:30',
    );
    await ProduktionErfassenService.speichere(
      db: quelle,
      productId: 'p1',
      datum: DateTime(2026, 11, 3),
      kgRohware: 500,
      kgFertigware: 440,
    );
    final ergebnis = await StammdatenExportService(quelle).exportiere();
    return ergebnis.bytes;
  }

  /// Liest [bytes] in eine frische Datenbank und gibt die Produktionen
  /// zurück, nach Rohware.
  Future<List<ProductionHistoryData>> einlesen(Uint8List bytes) async {
    final ziel = testDatenbank();
    addTearDown(ziel.close);
    final ergebnis = await StammdatenImportService(ziel).importiere(bytes);
    expect(ergebnis.fehler, isEmpty);
    expect(ergebnis.chargen, 2);
    return (await ziel.select(ziel.productionHistory).get())
      ..sort((a, b) => b.kgRohware!.compareTo(a.kgRohware!));
  }

  test('Fleischeinwaage hinaus und wieder herein', () async {
    final zeilen = await einlesen(await mappe());
    expect([for (final z in zeilen) z.kgRohware], [1000, 500]);
    expect([for (final z in zeilen) z.kgFleischeinwaage], [820, null]);
    expect(zeilen.first.kgFertigware, 900);
    expect(zeilen.first.startzeit, '06:00');
    expect(zeilen.first.quelle, 'excel');
  });

  test('eine ältere Mappe ohne die Spalte: ohne Fleischeinwaage', () async {
    // Dieselbe Mappe, nur trägt Spalte K nicht mehr die Überschrift — wie
    // bei einer Mappe aus der Zeit vor der Fleischeinwaage, die nach den
    // Notizen endete.
    final zeilen = await einlesen(_ohneFleischUeberschrift(await mappe()));
    expect([for (final z in zeilen) z.kgRohware], [1000, 500]);
    expect([for (final z in zeilen) z.kgFleischeinwaage], [null, null]);
  });
}

/// Benennt die Überschrift „Kg Fleischeinwaage" in der Mappe [xlsx] um.
/// Texte stehen in der Mappe als geteilte Zeichenketten — einmal.
Uint8List _ohneFleischUeberschrift(Uint8List xlsx) {
  final alt = ZipDecoder().decodeBytes(xlsx);
  final neu = Archive();
  var gefunden = false;
  for (final datei in alt.files) {
    if (datei.name == 'xl/sharedStrings.xml') {
      final text = utf8.decode(datei.content as List<int>);
      gefunden = text.contains('Kg Fleischeinwaage');
      final bytes = utf8.encode(
        text.replaceAll('Kg Fleischeinwaage', 'Bemerkung alt'),
      );
      neu.addFile(ArchiveFile(datei.name, bytes.length, bytes));
    } else {
      neu.addFile(datei);
    }
  }
  expect(gefunden, isTrue, reason: 'Die Mappe trägt die Überschrift.');
  return Uint8List.fromList(ZipEncoder().encode(neu)!);
}
