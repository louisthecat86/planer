import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:erfassung_format/erfassung_format.dart'
    show istJpeg, kFotoKante;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:produktion_planer/core/constants/artikel_merkmale.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/artikel_fotos.dart';
import 'package:produktion_planer/features/entwicklung/daten/dateien.dart';
import 'package:produktion_planer/features/entwicklung/daten/entwicklung_repository.dart';
import 'package:produktion_planer/features/entwicklung/entwicklung_zugang.dart';
import 'package:produktion_planer/features/entwicklung/freigabe/freigabe.dart';
import 'package:produktion_planer/features/entwicklung/freigabe/produktfoto_artikel.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_modell.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_repository.dart';

import 'helpers/test_db.dart';

/// Das Produktfoto eines Projekts wandert mit der Freigabe in die
/// Artikelkarte — und auch danach, wenn ein freigegebenes Projekt ein
/// (anderes) Produktfoto bekommt. Projekt, Rezeptur und Bilder sind
/// erfunden.
void main() {
  late AppDatabase db;
  late EntwicklungRepository rezepte;
  late ProjektRepository projekte;
  late FreigabeDienst dienst;
  late EntwicklungDateienDienst dateien;
  late ArtikelFotoDienst fotos;
  late ProduktfotoUebernahme uebernahme;

  setUp(() async {
    db = testDatenbank();
    rezepte = EntwicklungRepository(db);
    projekte = ProjektRepository(db);
    dienst = FreigabeDienst(db);
    dateien = EntwicklungDateienDienst(db);
    fotos = ArtikelFotoDienst(db);
    uebernahme = ProduktfotoUebernahme(db);
    await EntwicklungZugang(
      DbEntwicklungsSpeicher(db),
      iterationen: 1000,
      imHintergrund: false,
    ).festlegen('geheim123');
  });
  tearDown(() => db.close());

  Uint8List png(int breite, int hoehe, {int farbe = 0}) {
    final bild = img.Image(width: breite, height: hoehe);
    for (final p in bild) {
      p
        ..r = (p.x * 255 ~/ breite + farbe) % 256
        ..g = (p.y * 255 ~/ hoehe) % 256
        ..b = farbe % 256;
    }
    return img.encodePng(bild);
  }

  /// Ein Projekt mit einer Rezeptur, Stand 1 abgeschlossen.
  Future<({String projektId, String versionId})> anlegen() async {
    final id = await projekte.projektAnlegen(
      name: 'Schnitzel Wiener Art',
      artikelnummer: 'A-100',
    );
    final rezeptur = await rezepte.rezepturAnlegen(
      name: 'Schnitzel Wiener Art',
      projektId: id,
    );
    final fleisch = await rezepte.zutatAnlegen(
      const EntwicklungZutatenCompanion(
        name: Value('Schweineoberschale'),
        istFleisch: Value(true),
        tierart: Value('schwein'),
        allergene: Value(kAllergenKeine),
      ),
    );
    final v = (await rezepte.neuesteVersion(rezeptur))!;
    await rezepte.positionHinzufuegen(v.id, zutatId: fleisch, mengeKg: 100);
    await rezepte.versionAbschliessen(v.id);
    return (projektId: id, versionId: v.id);
  }

  /// Hängt ein Bild ans Projekt und macht es zum Produktfoto.
  Future<String> produktfoto(
    String projektId,
    Uint8List inhalt, {
    String name = 'Schnitzel.png',
  }) async {
    final id = await dateien.speichern(
      name: name,
      inhalt: inhalt,
      projektId: projektId,
      mimeTyp: 'image/png',
    );
    await projekte.produktfotoSetzen(projektId, id);
    return id;
  }

  Future<String> freigeben(({String projektId, String versionId}) a) async {
    final p = (await projekte.projekt(a.projektId))!;
    final w = (await dienst.vorschlag(p, a.versionId))
        .kopie(produktgruppe: 'bratstrasse_paniert');
    return dienst.freigeben(projekt: p, versionId: a.versionId, werte: w);
  }

  Future<List<String>> meilenstein(String projektId) async => [
        for (final e in await projekte.eintraegeBeobachten(projektId).first)
          if (e.titel.startsWith('Freigegeben')) ...texteAus(e.aenderungen),
      ];

  test(
      'mit der Freigabe kommt das Produktfoto in die Artikelkarte — als '
      'Referenzbild, einmal', () async {
    final a = await anlegen();
    final dateiId = await produktfoto(a.projektId, png(2000, 1000));

    final artikelId = await freigeben(a);

    final foto = (await fotos.beobachten(artikelId).first).single;
    expect(foto.id, entwicklungsFotoId(artikelId, dateiId));
    expect(foto.istReferenz, isTrue);
    expect(foto.bezeichnung, kProduktfotoBemerkung);
    // Als Foto aufbereitet: JPEG, längere Kante 1600 px — und offen, wie
    // alles am Artikel.
    final bild = (await fotos.bild(foto.id))!;
    expect(istJpeg(bild), isTrue);
    final gelesen = img.decodeJpg(bild)!;
    expect((gelesen.width, gelesen.height), (kFotoKante, 800));
    expect(
      await meilenstein(a.projektId),
      contains('Produktfoto zu den Fotos des Artikels gelegt'),
    );
    // Das Projekt behält sein Foto.
    expect((await projekte.projekt(a.projektId))!.bildDateiId, dateiId);
    expect(await dateien.lesen(dateiId), isNotNull);

    // Erneut freigegeben: kein zweites Mal.
    await freigeben(a);
    expect(await fotos.beobachten(artikelId).first, hasLength(1));
    expect(
      (await meilenstein(a.projektId))
          .where((t) => t.startsWith('Produktfoto')),
      hasLength(1),
    );
  });

  test(
      'ein anderes Produktfoto nach der Freigabe kommt auch zum Artikel — '
      'und löst das Referenzbild aus der Entwicklung ab', () async {
    final a = await anlegen();
    final erstes = await produktfoto(a.projektId, png(64, 48));
    final artikelId = await freigeben(a);

    final zweites = await produktfoto(a.projektId, png(64, 48, farbe: 90));
    final artikel = await uebernahme.uebernehmen(a.projektId);
    expect(artikel!.artikelnummer, 'A-100');

    final liste = await fotos.beobachten(artikelId).first;
    final referenz = {for (final f in liste) f.id: f.istReferenz};
    expect(referenz, {
      entwicklungsFotoId(artikelId, zweites): true,
      entwicklungsFotoId(artikelId, erstes): false,
    });
    // Noch einmal: nichts Neues.
    expect(await uebernahme.uebernehmen(a.projektId), isNull);
    expect(await fotos.beobachten(artikelId).first, hasLength(2));
  });

  test('ein von Hand gewähltes Referenzbild bleibt', () async {
    final a = await anlegen();
    final artikelId = await freigeben(a);
    // In der Produktion aufgenommen und zum Referenzbild gemacht.
    final eigenes = await fotos.speichern(
      productId: artikelId,
      bild: img.encodeJpg(img.Image(width: 32, height: 24)),
      aufgenommenAm: DateTime(2026, 11, 9),
    );
    await fotos.referenzSetzen(artikelId, eigenes);

    final dateiId = await produktfoto(a.projektId, png(64, 48));
    expect(await uebernahme.uebernehmen(a.projektId), isNotNull);

    final liste = await fotos.beobachten(artikelId).first;
    final referenz = {for (final f in liste) f.id: f.istReferenz};
    expect(referenz, {
      eigenes: true,
      entwicklungsFotoId(artikelId, dateiId): false,
    });
  });

  test(
      'ohne Freigabe, ohne Foto oder mit einer Datei, die kein Bild ist: '
      'nichts — und die Freigabe geht trotzdem', () async {
    final a = await anlegen();
    // Kein Foto, nicht freigegeben.
    expect(await uebernahme.uebernehmen(a.projektId), isNull);
    // Ein Foto, aber noch nicht freigegeben.
    await produktfoto(a.projektId, png(64, 48));
    expect(await uebernahme.uebernehmen(a.projektId), isNull);
    expect(await db.select(db.artikelFotos).get(), isEmpty);

    // Als Produktfoto steht etwas, das kein Bild ist.
    await produktfoto(
      a.projektId,
      Uint8List.fromList(utf8.encode('kein Bild')),
      name: 'Notiz.png',
    );
    final artikelId = await freigeben(a);
    expect(await fotos.beobachten(artikelId).first, isEmpty);
    expect(
      (await projekte.projekt(a.projektId))!.status,
      ProjektStatus.produktion.schluessel,
    );
    expect(
      (await meilenstein(a.projektId))
          .where((t) => t.startsWith('Produktfoto')),
      isEmpty,
    );
  });
}
