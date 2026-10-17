import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
// `show Value`: drift bringt eigene Klassen `Column` und `Table` mit.
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/constants/artikel_merkmale.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/features/entwicklung/daten/dateien.dart';
import 'package:produktion_planer/features/entwicklung/daten/entwicklung_repository.dart';
import 'package:produktion_planer/features/entwicklung/entwicklung_zugang.dart';
import 'package:produktion_planer/features/entwicklung/haccp/haccp_modell.dart';
import 'package:produktion_planer/features/entwicklung/haccp/prozess_modell.dart';
import 'package:produktion_planer/features/entwicklung/import/suite_import.dart';
import 'package:produktion_planer/features/entwicklung/import/suite_import_dialog.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_modell.dart';
import 'package:produktion_planer/features/entwicklung/rechenkern/rechen_modell.dart';
import 'package:produktion_planer/features/entwicklung/rechenkern/rechenkern.dart';

import 'helpers/test_db.dart';

/// Tests für die Übernahme aus der alten Development-Suite. Das Backup ist
/// erfunden und hier im Test gebaut — Kunden, Projekte und Rezepturen
/// gibt es nicht.
void main() {
  Map<String, dynamic> zeile(
    String name,
    double kg, {
    String? nummer,
    bool fleisch = false,
    bool quid = false,
    String? tierart,
    double? bindegewebe,
    Map<String, num>? naehrwerte,
    List<String> allergene = const [],
  }) =>
      {
        'name': name,
        if (nummer != null) 'articleNumber': nummer,
        'rawWeight': kg,
        'quidRequired': quid,
        'isMeat': fleisch,
        if (tierart != null) 'meatSpecies': tierart,
        if (bindegewebe != null) 'connectiveTissuePercent': bindegewebe,
        if (naehrwerte != null) 'nutrition': naehrwerte,
        'allergens': allergene,
      };

  const schulter = {'fat': 20, 'protein': 18, 'salt': 0.1, 'water': 61};
  const mehl = {'carbohydrates': 71, 'protein': 10, 'fat': 1};

  Map<String, dynamic> schulterZeile(double kg, [Map<String, num>? werte]) =>
      zeile(
        'Schweineschulter S3',
        kg,
        nummer: 'R-100',
        fleisch: true,
        quid: true,
        tierart: 'pork',
        bindegewebe: 12,
        naehrwerte: werte ?? schulter,
      );

  List<Map<String, dynamic>> panadeZutaten() => [
        zeile(
          'Weizenmehl Type 550',
          1,
          nummer: 'R-300',
          naehrwerte: mehl,
          allergene: ['gluten', 'ei'],
        ),
        zeile('Paniermehl', 1, allergene: ['gluten']),
      ];

  Map<String, dynamic> panadeZeile(double kg) => {
        'name': 'Panade',
        'rawWeight': kg,
        'quidRequired': false,
        'isMeat': false,
        'isRecipe': true,
        'processLoss': 10,
        'originalEndWeight': 1.8,
        'originalSubIngredients': panadeZutaten(),
      };

  final katalog = [
    {
      'id': 'ing-1',
      'name': 'Schweineschulter S3',
      'articleNumber': 'R-100',
      'isMeat': true,
      'meatSpecies': 'pork',
      'connectiveTissuePercent': 12,
      'meatProteinLimit': 15,
      'quidRequiredDefault': true,
      'nutrition': schulter,
      'allergens': <String>[],
    },
    {
      'id': 'ing-2',
      'name': 'Speisesalz',
      'articleNumber': 'R-200',
      'nutrition': {'salt': 100},
      'allergens': <String>[],
    },
    {
      'id': 'ing-3',
      'name': 'Weizenmehl Type 550',
      'articleNumber': 'R-300',
      'nutrition': mehl,
      // Der alte Excel-Import der Suite machte aus „Weizen" ein Ei.
      'allergens': ['gluten', 'ei'],
    },
    {
      'id': 'ing-4',
      'name': 'Senfsaat gemahlen',
      'allergens': ['senf', 'lupine', 'Hafer'],
      'processingAids': 'Trennmittel; Rieselhilfe',
    },
    {
      'id': 'ing-5',
      'name': 'Trinkwasser',
      'isWater': true,
      'nutrition': {'water': 100},
    },
    {
      'id': 'ing-6',
      'name': 'Vollei flüssig',
      'labelName': 'Vollei',
      'allergens': ['eggs'],
    },
  ];

  final bibliothek = [
    {
      'id': 'rec-1',
      'name': 'Grundbrät fein',
      'articleNumber': 'V-10',
      'description': 'Basis',
      'updatedAt': '2025-03-01T10:00:00.000Z',
      'cookingLoss': 0,
      'lossType': 'none',
      'ingredients': [
        schulterZeile(9.8),
        zeile('Speisesalz', 0.2, nummer: 'R-200', naehrwerte: {'salt': 100}),
      ],
    },
    {
      'id': 'rec-2',
      'name': 'Panade',
      'cookingLoss': 10,
      'fatLoss': 0,
      'lossType': 'drying',
      'ingredients': panadeZutaten(),
    },
  ];

  final stand1 = {
    'id': 'cur',
    'name': 'Schnitzel Wiener Art',
    'cookingLoss': 10,
    'fatLoss': 0,
    'lossType': 'cooking',
    'ingredients': [
      // Mit anderen Werten als im Katalog.
      schulterZeile(8, {'fat': 22, 'protein': 18}),
      panadeZeile(2),
    ],
  };
  final stand2 = {
    ...stand1,
    'ingredients': [
      schulterZeile(9),
      panadeZeile(1.5),
      {
        'name': 'Würzpaste Kräuter',
        'rawWeight': 0.5,
        'quidRequired': false,
        'isMeat': false,
        'isRecipe': true,
        'processLoss': 0,
        'originalSubIngredients': [
          zeile(
            'Butter',
            0.4,
            allergene: ['milch'],
            naehrwerte: {'fat': 82},
          ),
          zeile('Petersilie', 0.1),
        ],
      },
    ],
  };
  final aktuell = {
    ...stand2,
    'ingredients': [
      ...stand2['ingredients']! as List,
      zeile('Speisesalz', 0.1, nummer: 'R-200', naehrwerte: {'salt': 100}),
    ],
  };

  final prozess = {
    'version': '1.1',
    'updatedAt': '2025-03-01T00:00:00.000Z',
    'sections': [
      {
        'id': 's1',
        'title': 'Panierstraße',
        'fields': [
          {
            'id': 'f1',
            'label': 'Bandgeschwindigkeit',
            'value': '4',
            'type': 'number',
          },
          {
            'id': 'f2',
            'label': 'Panade',
            'value': 'fein',
            'type': 'radio',
            'options': ['fein', 'grob'],
          },
        ],
      },
    ],
  };

  final projekte = [
    {
      'id': 'p-1',
      'name': 'Schnitzel Wiener Art',
      'articleNumber': 'A-500',
      'status': 'validation',
      'customer': 'Muster GmbH',
      'createdAt': '2025-01-10T08:00:00.000Z',
      'updatedAt': '2025-04-01T08:00:00.000Z',
      'productIdea': 'Paniertes Schnitzel',
      'customerAgreements': 'ohne Geschmacksverstärker',
      'processFlow': 'FD_011',
      'isNewProcess': true,
      'hasNewIngredients': false,
      'parameters': {'fatTarget': 12, 'proteinTarget': 16, 'awLimit': 0.97},
      'notes': 'Erste Muster gut.',
      'riskAnalysis': 'Metall prüfen',
      'productImage': 'data:image/png;base64,iVBORw0KGgo=',
      'sensory': {
        'appearance': 'goldbraun',
        'taste': 'mild',
        'dimensions': {'weight': '150 g'},
      },
      'checklist': {
        'articleCreated': true,
        'recipeCreated': true,
        'labelCreated': false,
      },
      'labelChecklist': {'name': true, 'allergens': true, 'gas': false},
      'processSettings': prozess,
      'processHistory': [
        {
          'version': '1.0',
          'date': '2025-02-01T00:00:00.000Z',
          'user': 'User',
          'note': 'erster Stand',
          'settings': {'version': '1.0', 'sections': <Object>[]},
        },
      ],
      'fmeaData': {
        'hazards': [
          {
            'id': 'h1',
            'hazard': 'Metallteile',
            'category': 'Physikalisch',
            'severity': 3,
            'occurrence': 1,
            'measures': 'Metalldetektor',
          },
        ],
        'ccps': [
          {
            'id': 'c1',
            'step': 'Metalldetektion',
            'description': '',
            'hazardType': 'Physikalisch',
            'q1': true,
            'q2': true,
            'q3': null,
            'q4': null,
            'result': 'CCP',
            'controlMeasures': 'Prüfkörper je Schicht',
          },
        ],
      },
      // Wie in der Suite: das Neueste zuerst.
      'timeline': [
        {
          'id': 1714000000400,
          'type': 'file',
          'title': 'Foto',
          'date': '2025-03-06',
          'user': 'User',
          'status': 'received',
          'attachment': 'fehlt.jpg',
        },
        {
          'id': 1714000000300,
          'type': 'file',
          'title': 'Datenblatt',
          'date': '2025-03-05',
          'user': 'User',
          'status': 'received',
          'attachment': 'Datenblatt Muster.pdf',
        },
        {
          'id': 1714000000250,
          'type': 'email',
          'title': 'Mail Kunde',
          'date': '2025-03-04',
          'user': 'User',
          'description': 'Freigabe',
          'status': 'ok',
          'attachment': 'Antwort.msg',
          // Die Suite legte gleiche Inhalte nur einmal ins ZIP.
          'attachmentRef':
              'Kunden/Muster GmbH/Schnitzel Wiener Art/Dateien/Datenblatt '
                  'Muster.pdf',
        },
        {
          'id': 1714000000200,
          'type': 'recipe',
          'title': 'Rezeptur Version 1.1',
          'date': '2025-03-01',
          'user': 'User',
          'status': 'completed',
          'value': jsonEncode(stand2),
          'changes': ['Endgewicht: 9.900 kg', '3 Zutaten'],
          'comments': [
            {'id': 1, 'user': 'QS', 'text': 'passt', 'date': '2025-03-02'},
          ],
        },
        {
          'id': 1714000000100,
          'type': 'recipe',
          'title': 'Rezeptur Version 1.0',
          'date': '2025-02-01',
          'user': 'User',
          'status': 'completed',
          'value': jsonEncode(stand1),
        },
        {
          'id': 1714000000050,
          'type': 'parameter',
          'title': 'Prozess-Parameter v1.1',
          'date': '2025-02-01',
          'user': 'User',
          'description': 'Band schneller',
          'status': 'completed',
          'value': jsonEncode(prozess),
        },
        {
          'id': 1714000000010,
          'type': 'milestone',
          'title': 'Projektstart',
          'date': '2025-01-10',
          'user': 'User',
          'status': 'completed',
          'target': 'KW 12',
        },
      ],
      'currentRecipe': aktuell,
    },
    {
      'id': 'p-2',
      'name': 'Bratwürstchen fein',
      'status': 'development',
      'createdAt': '2025-05-01T00:00:00.000Z',
      'updatedAt': '2025-05-02T00:00:00.000Z',
      'parameters': <String, Object>{},
      'timeline': [
        {
          'id': 5,
          'type': 'file',
          'title': 'Probe',
          'date': '2025-05-02',
          'user': 'User',
          'status': 'received',
          'attachment': 'Probe.txt',
        },
      ],
    },
    {
      'id': 'p-3',
      'name': 'Altprojekt',
      'status': 'archived',
      'createdAt': '2024-01-01T00:00:00.000Z',
      'updatedAt': '2024-02-01T00:00:00.000Z',
      'parameters': <String, Object>{},
      'timeline': <Object>[],
    },
  ];

  final pdf = utf8.encode('%PDF-Muster');
  final probe = utf8.encode('Probe');
  const png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

  Uint8List zip(Map<String, List<int>> dateien) {
    final archiv = Archive();
    for (final MapEntry(:key, :value) in dateien.entries) {
      archiv.addFile(ArchiveFile(key, value.length, value));
    }
    return Uint8List.fromList(ZipEncoder().encode(archiv)!);
  }

  List<int> json(Object daten) => utf8.encode(jsonEncode(daten));

  Uint8List backup() => zip({
        'projects.json': json(projekte),
        'ingredients.json': json(katalog),
        'recipes.json': json(bibliothek),
        'ingredients.xlsx': [1, 2, 3],
        'Kunden/Muster GmbH/Schnitzel Wiener Art/README.txt':
            utf8.encode('Projekt'),
        'Kunden/Muster GmbH/Schnitzel Wiener Art/Dateien/Datenblatt '
            'Muster.pdf': pdf,
        // Umlaute im Ordnernamen anders kodiert, wie es beim Entpacken
        // vorkommt.
        'Kunden/Allgemein/BratwÃ¼rstchen fein/Dateien/Probe.txt': probe,
      });

  SuiteImportPlan planen({Set<String> vorhanden = const {}}) =>
      suiteImportPlanen(
        suiteDatenLesen(backup()),
        vorhandeneZutaten: vorhanden,
        jetzt: DateTime(2025, 6, 1),
      );

  group('Allergene der Suite', () {
    test('werden auf die Werte des Planers abgebildet', () {
      expect(planerAllergen('ei'), 'eier');
      expect(planerAllergen('eggs'), 'eier');
      expect(planerAllergen('Schalenfrüchte'), 'schalenfruechte');
      expect(planerAllergen('lupine'), 'lupinen');
      expect(planerAllergen('peanuts'), 'erdnuesse');
      expect(planerAllergen('sulphites'), 'sulfit');
      expect(planerAllergen('Krebstiere'), 'krebstiere');
      expect(planerAllergen('Hafer'), isNull);
      // Jeder Wert ist einer der Liste.
      final werte = {for (final m in kAllergene) m.dbValue};
      for (final a in [
        'gluten',
        'ei',
        'soja',
        'milch',
        'schalenfrüchte',
        'sellerie',
        'senf',
        'sesam',
        'sulfit',
        'lupine',
        'weichtiere',
        'erdnuesse',
        'fisch',
        'krebstiere',
      ]) {
        expect(werte, contains(planerAllergen(a)), reason: a);
      }
    });
  });

  group('Lesen', () {
    test('das ZIP mit Projekten, Zutaten, Rezepturen und Anhängen', () {
      final d = suiteDatenLesen(backup());
      expect(d.zutaten, hasLength(6));
      expect(d.rezepturen, hasLength(2));
      expect(d.projekte, hasLength(3));
      expect(
        d.datei(
          'Kunden/Muster GmbH/Schnitzel Wiener Art/Dateien/Datenblatt '
          'Muster.pdf',
        ),
        pdf,
      );
      // Über den vereinfachten Pfad.
      expect(
        d.datei('Kunden/Allgemein/Bratwürstchen fein/Dateien/Probe.txt'),
        probe,
      );
      expect(d.datei('Kunden/Allgemein/Anderes/Dateien/Probe.txt'), isNull);
    });

    test('eine einzelne JSON-Datei, auch mit Byte-Order-Mark', () {
      final zutaten = suiteDatenLesen(
        Uint8List.fromList(utf8.encode('﻿${jsonEncode(katalog)}')),
      );
      expect(zutaten.zutaten, hasLength(6));
      expect(zutaten.projekte, isEmpty);
      final rezepturen =
          suiteDatenLesen(Uint8List.fromList(json(bibliothek)));
      expect(rezepturen.rezepturen, hasLength(2));
      final p = suiteDatenLesen(Uint8List.fromList(json(projekte)));
      expect(p.projekte, hasLength(3));
    });

    test('anderes wird abgelehnt', () {
      expect(
        () => suiteDatenLesen(Uint8List.fromList(utf8.encode('kein json'))),
        throwsFormatException,
      );
      expect(
        () => suiteDatenLesen(
          Uint8List.fromList(json({'name': 'keine Liste'})),
        ),
        throwsFormatException,
      );
      expect(
        () => suiteDatenLesen(zip({'readme.txt': utf8.encode('hallo')})),
        throwsFormatException,
      );
    });
  });

  group('Planen', () {
    test('zählt, was übernommen wird', () {
      final plan = planen();
      // 6 aus dem Katalog, dazu Paniermehl, Butter und Petersilie aus
      // Rezepturen.
      expect(plan.zutaten, hasLength(9));
      expect(plan.zutatenAusRezepturen, 3);
      // Grundbrät, Panade, die Würzpaste aus einer Unterrezeptur und die
      // Rezeptur des Projekts.
      expect(plan.rezepturen, hasLength(4));
      expect(plan.bibliothek, 3);
      // Drei Entwürfe der Bibliothek, im Projekt zwei abgeschlossene
      // Stände und der aktuelle als Entwurf.
      expect(plan.versionen, hasLength(6));
      expect(plan.positionen, hasLength(2 + 2 + 2 + 2 + 3 + 4));
      expect(plan.projekte, hasLength(3));
      expect(plan.archiviert, 1);
      expect(plan.eintraege, hasLength(8));
      // Produktbild, Datenblatt, die Mail über den Verweis und die Probe.
      expect(plan.dateien, hasLength(4));
      expect(plan.fehlendeDateien, ['fehlt.jpg']);
      expect(plan.fliessdiagramme, hasLength(1));
      expect(plan.leer, isFalse);
    });

    test('meldet, was auffällt', () {
      final plan = planen(vorhanden: {'speisesalz'});
      bool hinweis(String a, [String b = '']) =>
          plan.hinweise.any((h) => h.contains(a) && h.contains(b));
      expect(hinweis('Ei', 'Weizenmehl Type 550'), isTrue);
      // Vollei nennt das Ei — kein Hinweis.
      expect(hinweis('Ei', 'Vollei'), isFalse);
      expect(hinweis('andere Werte', 'Schweineschulter S3'), isTrue);
      expect(hinweis('Gibt es hier schon', 'Speisesalz'), isTrue);
      expect(hinweis('Unbekannte Allergene', 'Hafer'), isTrue);
      expect(hinweis('Ohne Inhalt', 'fehlt.jpg'), isTrue);
      expect(plan.hinweise, hasLength(5));
    });

    test('ein gleicher Plan hat dieselben IDs', () {
      final a = planen();
      final b = planen();
      expect(
        [for (final z in a.zutaten) z.id.value],
        [for (final z in b.zutaten) z.id.value],
      );
      expect(
        [for (final r in a.rezepturen) r.id.value],
        [for (final r in b.rezepturen) r.id.value],
      );
    });
  });

  group('Übernehmen', () {
    late AppDatabase db;
    late EntwicklungRepository repo;
    late EntwicklungDateienDienst dateien;

    setUp(() async {
      db = testDatenbank();
      repo = EntwicklungRepository(db);
      dateien = EntwicklungDateienDienst(db);
      // Der Datenschlüssel entsteht mit dem Passwort.
      await EntwicklungZugang(
        DbEntwicklungsSpeicher(db),
        iterationen: 1000,
        imHintergrund: false,
      ).festlegen('geheim123');
    });
    tearDown(() => db.close());

    Future<void> uebernehmen() =>
        suiteImportAusfuehren(db, planen(), dateien);

    Future<Zutat> zutatNamens(String name) async =>
        (await db.select(db.entwicklungZutaten).get())
            .singleWhere((z) => z.name == name);

    test('Zutaten mit Allergenen, Art und Nährwerten', () async {
      await uebernehmen();
      expect(await db.select(db.entwicklungZutaten).get(), hasLength(9));

      final schulter = await zutatNamens('Schweineschulter S3');
      expect(schulter.id, 'suite-z-ing-1');
      expect(schulter.istFleisch, isTrue);
      expect(schulter.tierart, 'schwein');
      expect(schulter.bindegewebe, 12);
      expect(schulter.fleischeiweissGrenze, 15);
      expect(schulter.quidPflicht, isTrue);
      expect(schulter.fett, 20);
      expect(schulter.artikelnummer, 'R-100');

      final mehl = await zutatNamens('Weizenmehl Type 550');
      expect(merkmaleAusText(mehl.allergene), {'gluten', 'eier'});
      final senf = await zutatNamens('Senfsaat gemahlen');
      expect(merkmaleAusText(senf.allergene), {'senf', 'lupinen'});
      expect(senf.verarbeitungshilfsstoffe, 'Trennmittel, Rieselhilfe');
      expect((await zutatNamens('Trinkwasser')).istWasser, isTrue);
      expect((await zutatNamens('Vollei flüssig')).etikettName, 'Vollei');
      expect(
        (await zutatNamens('Paniermehl')).id,
        startsWith('suite-zr-'),
      );
    });

    test('Rezepturen der Bibliothek werden Entwürfe und rechnen', () async {
      await uebernehmen();
      final v = (await repo.neuesteVersion('suite-r-rec-1'))!;
      expect(v.status, VersionStatus.entwurf);
      expect(v.verlustArt, Verlustart.keiner.schluessel);
      expect((await repo.rezeptur('suite-r-rec-1'))!.artikelnummer, 'V-10');
      final e = berechne((await repo.rechenRezeptur(v.id))!);
      expect(e.zutatenliste, 'Schweinefleisch (98,0 %), Speisesalz');

      final panade = (await repo.neuesteVersion('suite-r-rec-2'))!;
      expect(panade.verlustProzent, 10);
      expect(await repo.positionen(panade.id), hasLength(2));
    });

    test('die Rezeptur eines Projekts mit ihren Ständen', () async {
      await uebernehmen();
      final rezeptur = (await repo.rezeptur('suite-p-p-1-r'))!;
      expect(rezeptur.projektId, 'suite-p-p-1');
      final staende = [
        for (final v in await db.select(db.entwicklungRezepturVersionen).get())
          if (v.rezepturId == rezeptur.id) v,
      ]..sort((a, b) => a.nummer.compareTo(b.nummer));
      expect([for (final v in staende) v.status], [
        VersionStatus.abgeschlossen,
        VersionStatus.abgeschlossen,
        VersionStatus.entwurf,
      ]);
      expect(staende[0].bezeichnung, 'Rezeptur Version 1.0');
      expect(staende[0].abgeschlossenAm, DateTime(2025, 2, 1));
      expect(staende[1].bezeichnung, 'Rezeptur Version 1.1');
      expect(staende[0].verlustArt, Verlustart.garen.schluessel);

      // Der erste Stand rechnet mit den Werten von damals.
      final eins = (await repo.rechenRezeptur(staende[0].id))!;
      expect(eins.positionen.first.zutat!.naehrwerte.fett, 22);
      expect(eins.positionen[1].unterrezeptur!.positionen, hasLength(2));
      expect(eins.positionen[1].unterrezeptur!.verlustProzent, 10);
      expect(berechne(eins).eingesetztKg, closeTo(10, 1e-9));

      // Der Entwurf verweist auf Katalog und Bibliothek.
      final zeilen = await repo.positionen(staende[2].id);
      expect(zeilen, hasLength(4));
      expect(zeilen[0].zutatId, 'suite-z-ing-1');
      expect(zeilen[1].unterrezepturId, 'suite-r-rec-2');
      expect(zeilen[1].mengeKg, 1.5);
      expect(zeilen[2].unterrezepturId, startsWith('suite-u-'));
      expect(zeilen[3].zutatId, 'suite-z-ing-2');
      final entwurf = berechne((await repo.rechenRezeptur(staende[2].id))!);
      expect(entwurf.allergene.keys, containsAll(['gluten', 'milch']));
    });

    test('Projekt mit Stammdaten, Checklisten, Prozess und HACCP', () async {
      await uebernehmen();
      final p = await (db.select(db.entwicklungProjekte)
            ..where((p) => p.id.equals('suite-p-p-1')))
          .getSingle();
      expect(p.name, 'Schnitzel Wiener Art');
      expect(p.kunde, 'Muster GmbH');
      expect(p.status, ProjektStatus.validierung.schluessel);
      expect(p.fliessdiagramm, 'FD_011');
      expect(p.neuerProzess, isTrue);
      expect(p.zielFett, 12);
      expect(p.grenzeAw, 0.97);
      expect(p.notizen, contains('Erste Muster gut.'));
      expect(p.notizen, contains('Risikoanalyse'));
      expect(checklisteAus(p.checkliste), {
        'artikelAngelegt',
        'rezepturErstellt',
      });
      expect(checklisteAus(p.etikettCheckliste), {'bezeichnung', 'allergene'});
      final sensorik = Sensorik.aus(p.sensorik);
      expect(sensorik.aussehen, 'goldbraun');
      expect(sensorik.gewicht, '150 g');
      final prozess = Prozessparameter.aus(p.prozess);
      expect(prozess.version, '1.1');
      expect(prozess.abschnitte.single.felder[1].optionen, ['fein', 'grob']);
      expect(
        ProzessStand.listeAus(p.prozessHistorie).single.notiz,
        'erster Stand',
      );
      final haccp = Haccp.aus(p.haccp);
      expect(haccp.gefahren.single.risiko, 3);
      expect(haccp.lenkungspunkte.single.ergebnis, Lenkungsart.ccp);
      expect(haccp.lenkungspunkte.single.antworten, {'f1': true, 'f2': true});

      final archiv = await (db.select(db.entwicklungProjekte)
            ..where((p) => p.id.equals('suite-p-p-3')))
          .getSingle();
      expect(archiv.status, ProjektStatus.archiviert.schluessel);

      final fd = await db.select(db.entwicklungFliessdiagramme).get();
      expect([for (final f in fd) f.id], ['FD_011']);
    });

    test('Verlauf mit Kommentaren, Ständen und Dateien', () async {
      await uebernehmen();
      final eintraege = {
        for (final e in await db.select(db.entwicklungProjektEintraege).get())
          e.id: e,
      };
      expect(eintraege, hasLength(8));

      final stand = eintraege['suite-p-p-1-e1714000000200']!;
      expect(stand.art, EintragArt.rezeptur.schluessel);
      expect(stand.versionId, 'suite-p-p-1-r-v2');
      expect(stand.wert, isNull);
      expect(texteAus(stand.aenderungen), hasLength(2));
      final kommentar = Kommentar.listeAus(stand.kommentare).single;
      expect(kommentar.name, 'QS');
      expect(kommentar.text, 'passt');

      final parameter = eintraege['suite-p-p-1-e1714000000050']!;
      expect(
        Prozessparameter.aus(parameter.wert).abschnitte.single.titel,
        'Panierstraße',
      );
      final start = eintraege['suite-p-p-1-e1714000000010']!;
      expect(start.art, EintragArt.meilenstein.schluessel);
      expect(start.ziel, 'KW 12');
      expect(start.status, EintragStatus.erledigt.schluessel);
      expect(start.datum, DateTime(2025, 1, 10));
      expect(eintraege['suite-p-p-1-e1714000000400']!.dateiId, isNull);

      // Dateien: verschlüsselt gespeichert, entschlüsselt wie vorher.
      final mail = eintraege['suite-p-p-1-e1714000000250']!;
      expect(await dateien.lesen(mail.dateiId!), pdf);
      final datenblatt = eintraege['suite-p-p-1-e1714000000300']!;
      expect(await dateien.lesen(datenblatt.dateiId!), pdf);
      final roh = await db.select(db.entwicklungDateiInhalte).get();
      expect(roh.every((r) => r.inhalt.length > 16), isTrue);
      expect(
        await dateien.lesen(eintraege['suite-p-p-2-e5']!.dateiId!),
        probe,
      );
      final p = await (db.select(db.entwicklungProjekte)
            ..where((p) => p.id.equals('suite-p-p-1')))
          .getSingle();
      expect(await dateien.lesen(p.bildDateiId!), png);
      expect((await dateien.datei(p.bildDateiId!))!.name, 'Produktbild.png');
    });

    test('ein zweiter Import legt nichts doppelt an', () async {
      // Von Hand Angelegtes und gepflegte Bezeichnungen bleiben.
      await repo.zutatAnlegen(
        const EntwicklungZutatenCompanion(name: Value('Eigene Zutat')),
      );
      await db.into(db.entwicklungFliessdiagramme).insert(
            EntwicklungFliessdiagrammeCompanion.insert(
              id: 'FD_011',
              bezeichnung: 'Panierte Ware',
            ),
          );
      await uebernehmen();
      await uebernehmen();
      expect(await db.select(db.entwicklungZutaten).get(), hasLength(10));
      expect(await db.select(db.entwicklungRezepturen).get(), hasLength(4));
      expect(
        await db.select(db.entwicklungRezepturVersionen).get(),
        hasLength(6),
      );
      expect(
        await db.select(db.entwicklungRezepturPositionen).get(),
        hasLength(15),
      );
      expect(await db.select(db.entwicklungProjekte).get(), hasLength(3));
      expect(
        await db.select(db.entwicklungProjektEintraege).get(),
        hasLength(8),
      );
      expect(await db.select(db.entwicklungDateien).get(), hasLength(4));
      expect(await db.select(db.entwicklungDateiInhalte).get(), hasLength(4));
      final fd = await db.select(db.entwicklungFliessdiagramme).getSingle();
      expect(fd.bezeichnung, 'Panierte Ware');
    });
  });

  group('Fenster', () {
    testWidgets('zeigt die Vorschau und übernimmt nach Bestätigung',
        (tester) async {
      final dienst = _Dienst(planen());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [suiteImportDienstProvider.overrideWithValue(dienst)],
          child: MaterialApp(
            home: Scaffold(
              body: SuiteImportDialog(
                bytes: Uint8List(0),
                dateiname: 'quid_full_backup.zip',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('„quid_full_backup.zip" enthält:'), findsOneWidget);
      expect(find.text('3 nur aus Rezepturen'), findsOneWidget);
      expect(find.textContaining('Weizenmehl Type 550'), findsOneWidget);
      // Es gibt schon Übernommenes.
      expect(find.textContaining('wird mit dem Stand'), findsOneWidget);

      await tester.tap(find.text('Übernehmen'));
      await tester.pump();
      await tester.pump();
      expect(dienst.geschrieben, 1);
      expect(find.text('Übernommen'), findsOneWidget);
      expect(find.text('Schließen'), findsOneWidget);
    });

    testWidgets('zeigt einen Fehler beim Lesen', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            suiteImportDienstProvider.overrideWithValue(
              _Dienst(planen(), fehler: 'Das ZIP ließ sich nicht öffnen'),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SuiteImportDialog(
                bytes: Uint8List(0),
                dateiname: 'kaputt.zip',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Das ZIP ließ sich nicht öffnen'), findsOneWidget);
      expect(find.text('Übernehmen'), findsNothing);
    });
  });
}

class _Dienst implements SuiteImportDienst {
  _Dienst(this.plan, {this.fehler});

  final SuiteImportPlan plan;
  final String? fehler;
  int geschrieben = 0;

  @override
  Future<({SuiteImportPlan plan, bool frueher})> vorbereiten(
    Uint8List bytes,
  ) async {
    final f = fehler;
    if (f != null) throw FormatException(f);
    return (plan: plan, frueher: true);
  }

  @override
  Future<void> ausfuehren(SuiteImportPlan plan) async {
    geschrieben++;
  }
}
