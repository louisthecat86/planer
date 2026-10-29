import 'dart:convert';
import 'dart:typed_data';

// `show Value`: drift bringt eine eigene Klasse `Column` mit.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/druck/druck_layout.dart';
import 'package:produktion_planer/core/druck/druck_satz.dart';
import 'package:produktion_planer/core/services/entwicklung_daten.dart';
import 'package:produktion_planer/features/entwicklung/bericht/bericht_pdf.dart';
import 'package:produktion_planer/features/entwicklung/bericht/projekt_bericht.dart';
import 'package:produktion_planer/features/entwicklung/daten/dateien.dart';
import 'package:produktion_planer/features/entwicklung/daten/entwicklung_repository.dart';
import 'package:produktion_planer/features/entwicklung/entwicklung_zugang.dart';
import 'package:produktion_planer/features/entwicklung/mail/mail.dart';
import 'package:produktion_planer/features/entwicklung/mail/mail_ablage.dart';
import 'package:produktion_planer/features/entwicklung/projekte/entwicklungsstrang.dart';
import 'package:produktion_planer/features/entwicklung/projekte/gesamtprojekt_modell.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_modell.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_repository.dart';

import 'helpers/test_db.dart';

/// Tests für Gesamtprojekte mit Mustern: eine Anfrage, aus der mehrere
/// Muster entstehen. Das Gesamtprojekt sammelt Korrespondenz und
/// Unterlagen, jedes Muster ist ein Projekt mit eigenem Weg — und eines,
/// das nicht weiter verfolgt wird, ruht mit Grund. Alle Namen, Kunden und
/// Mails sind erfunden.
void main() {
  group('Regeln', () {
    test('Namen neuer Muster: leere nach ihrer Stelle', () {
      expect(musterNamen(['', ' Bratwurst grob ', '']), [
        'Muster 1',
        'Bratwurst grob',
        'Muster 3',
      ]);
      expect(musterNamen(const []), isEmpty);
    });

    test('Anhänge, die ein Mail-Eintrag nennt', () {
      expect(
        mailAnhangNamen([
          'Anhang: Angebot (2).pdf (12 KB)',
          'Anhang: Rezeptur.xlsx (1,2 MB)',
          'Status vorher: In Entwicklung',
          'Anhang: ohne Größe.pdf',
        ]),
        ['Angebot (2).pdf', 'Rezeptur.xlsx'],
      );
    });

    test('Zusammenfassung der Muster in der Reihenfolge der Phasen', () {
      expect(musterZusammenfassung(const []), 'Noch keine Muster');
      expect(
        musterZusammenfassung(const [
          ProjektStatus.eingestellt,
          ProjektStatus.entwicklung,
          ProjektStatus.produktion,
          ProjektStatus.entwicklung,
          ProjektStatus.eingestellt,
        ]),
        '5 Muster: 2 in Entwicklung, 1 in Produktion, '
        '2 nicht weiter verfolgt',
      );
      expect(
        musterZusammenfassung(const [ProjektStatus.validierung]),
        '1 Muster: 1 in Validierung',
      );
    });

    test('ein Gesamtprojekt erscheint, wenn eines seiner Muster passt', () {
      final a = _projekt('a', status: 'produktion');
      final b = _projekt('b', status: 'eingestellt');
      bool aktiv(ProjektStatus s) => !s.ruht;
      bool eingestellt(ProjektStatus s) => s == ProjektStatus.eingestellt;
      bool archiv(ProjektStatus s) => s == ProjektStatus.archiviert;
      expect(gesamtprojektPasst([a, b], aktiv, leerPasst: true), isTrue);
      expect(gesamtprojektPasst([a, b], eingestellt, leerPasst: false), isTrue);
      expect(gesamtprojektPasst([a, b], archiv, leerPasst: false), isFalse);
      // Noch ohne Muster: nur bei den laufenden.
      expect(gesamtprojektPasst(const [], aktiv, leerPasst: true), isTrue);
      expect(gesamtprojektPasst(const [], archiv, leerPasst: false), isFalse);
    });

    test('Gesamtprojekt zuletzt: das jüngste von ihm und seinen Mustern', () {
      final g = _gesamt(geaendert: DateTime(2026, 10, 1));
      expect(gesamtprojektZuletzt(g, const []), DateTime(2026, 10, 1));
      expect(
        gesamtprojektZuletzt(g, [
          _projekt('a', geaendert: DateTime(2026, 9, 1)),
          _projekt('b', geaendert: DateTime(2026, 10, 5)),
        ]),
        DateTime(2026, 10, 5),
      );
    });

    test('Verlauf eines Musters: mit dem Gesamtprojekt, gekennzeichnet', () {
      final eigene = [
        _eintrag('m2', 'a', tag: 5),
        _eintrag('m1', 'a', tag: 2),
      ];
      final gesamt = [
        _eintrag('g2', 'g', tag: 4, art: EintragArt.email),
        _eintrag('g1', 'g', tag: 1, art: EintragArt.email),
      ];
      final mit = musterVerlauf(eigene, gesamt);
      expect([for (final e in mit.eintraege) e.id], ['m2', 'g2', 'm1', 'g1']);
      expect(mit.herkunft, {
        'g2': kHerkunftGesamtprojekt,
        'g1': kHerkunftGesamtprojekt,
      });
      // Abgeschaltet: nur die eigenen.
      final ohne = musterVerlauf(eigene, gesamt, mitGesamtprojekt: false);
      expect([for (final e in ohne.eintraege) e.id], ['m2', 'm1']);
      expect(ohne.herkunft, isEmpty);
    });

    test('Verlauf eines Gesamtprojekts: mit den Meilensteinen der Muster', () {
      final muster = [_projekt('a', name: 'Grob'), _projekt('b', name: 'Fein')];
      final alle = [
        _eintrag('a1', 'a', tag: 3),
        _eintrag('a2', 'a', tag: 4, art: EintragArt.notiz),
        _eintrag('b1', 'b', tag: 6),
        _eintrag('x1', 'x', tag: 7),
      ];
      final eigene = [_eintrag('g1', 'g', tag: 1, art: EintragArt.email)];
      final v = gesamtprojektVerlauf(eigene, muster, alle);
      // Nur Meilensteine der eigenen Muster — keine Notizen, keine
      // fremden Projekte.
      expect([for (final e in v.eintraege) e.id], ['b1', 'a1', 'g1']);
      expect(v.herkunft, {'a1': 'Grob', 'b1': 'Fein'});
      final ohne =
          gesamtprojektVerlauf(eigene, muster, alle, mitMustern: false);
      expect([for (final e in ohne.eintraege) e.id], ['g1']);
    });

    test('Projektliste: Gesamtprojekte mit ihren Mustern, Filter, Suche',
        () {
      final g1 = _gesamt(id: 'g1', name: 'Grill', geaendert: DateTime(2026, 9));
      final g2 = _gesamt(
        id: 'g2',
        name: 'Snacks',
        kunde: 'Beispiel Feinkost',
        geaendert: DateTime(2026, 10, 9),
      );
      final ohneMuster =
          _gesamt(id: 'g3', name: 'Leer', geaendert: DateTime(2026, 8));
      final projekte = [
        _projekt(
          'a',
          name: 'Grob',
          gesamt: 'g1',
          angelegt: 2,
          geaendert: DateTime(2026, 10, 1),
        ),
        _projekt(
          'b',
          name: 'Fein',
          gesamt: 'g1',
          status: 'eingestellt',
        ),
        _projekt('c', name: 'Chips', gesamt: 'g2'),
        _projekt('d', name: 'Für sich', geaendert: DateTime(2026, 10, 5)),
        // Sein Gesamtprojekt gibt es nicht mehr: Es steht für sich.
        _projekt('e', name: 'Verwaist', gesamt: 'weg'),
      ];
      List<String> liste(
        bool Function(ProjektStatus) passt, {
        bool leer = true,
        String suche = '',
      }) =>
          [
            for (final p in projektListe(
              projekte: projekte,
              gesamtprojekte: [g1, g2, ohneMuster],
              passt: passt,
              leerPasst: leer,
              suche: suche,
            ))
              switch (p) {
                EinzelProjekt(:final projekt) => projekt.id,
                GesamtGruppe(:final gesamtprojekt, :final sichtbar) =>
                  '${gesamtprojekt.id}[${sichtbar.map((m) => m.id).join()}]',
              },
          ];
      bool aktiv(ProjektStatus s) => !s.ruht;
      // Das zuletzt bewegte zuerst — beim Gesamtprojekt zählt auch ein
      // Muster.
      expect(liste(aktiv), ['g2[c]', 'd', 'g1[a]', 'e', 'g3[]']);
      // Nicht weiter verfolgt: nur das eine Muster, mit seiner Gruppe.
      expect(
        liste((s) => s == ProjektStatus.eingestellt, leer: false),
        ['g1[b]'],
      );
      // Die Suche trifft das Gesamtprojekt — dann alle seine Muster.
      expect(liste(aktiv, suche: 'feinkost'), ['g2[c]']);
      expect(liste((_) => true, suche: 'GRILL'), ['g1[ba]']);
      // … oder ein einzelnes Muster.
      expect(liste((_) => true, suche: 'fein'), ['g2[c]', 'g1[b]']);
    });

    test('Ziele zum Verschieben: das Gesamtprojekt, dann die Muster', () {
      expect(verschiebeZiele(null, const []), isEmpty);
      final g = _gesamt(id: 'g', name: 'Grill', geaendert: DateTime(2026));
      expect(
        verschiebeZiele(g, [_projekt('a', name: 'Grob')]),
        [
          (id: 'g', name: 'Grill', gesamtprojekt: true),
          (id: 'a', name: 'Grob', gesamtprojekt: false),
        ],
      );
    });

    test('der Grund, warum ein Muster nicht weiter verfolgt wird', () {
      ProjektEintrag wechsel(String id, int tag, String w, String? text) =>
          _wechsel(id, tag, w).copyWith(beschreibung: Value(text));
      expect(nichtWeiterGrund(const []), isNull);
      expect(
        nichtWeiterGrund([
          wechsel(
            '1',
            1,
            'entwicklung>eingestellt',
            'Grund: Zu teuer\nStatus vorher: In Entwicklung',
          ),
        ]),
        'Zu teuer',
      );
      // Ohne Grund — oder längst wieder aufgenommen.
      expect(
        nichtWeiterGrund([
          wechsel(
            '1',
            1,
            'entwicklung>eingestellt',
            'Status vorher: In Entwicklung',
          ),
        ]),
        isNull,
      );
      expect(
        nichtWeiterGrund([
          wechsel('1', 1, 'entwicklung>eingestellt', 'Grund: Zu teuer'),
          wechsel('2', 2, 'eingestellt>entwicklung', null),
        ]),
        isNull,
      );
    });

    test('Wieder aufnehmen: die Phase vor dem Ruhen', () {
      // Validierung → nicht weiter verfolgt → archiviert: zurück in die
      // Validierung.
      final verlauf = [
        _wechsel('1', 1, 'entwicklung>validierung'),
        _wechsel('2', 3, 'validierung>eingestellt'),
        _wechsel('3', 5, 'eingestellt>archiviert'),
      ];
      expect(phaseVorDemArchiv(verlauf), ProjektStatus.validierung);
      expect(
        phaseVorDemArchiv(verlauf.take(2)),
        ProjektStatus.validierung,
      );
      expect(ProjektStatus.eingestellt.ruht, isTrue);
      expect(ProjektStatus.archiviert.ruht, isTrue);
      expect(ProjektStatus.produktion.ruht, isFalse);
      expect(ProjektStatus.aus('eingestellt'), ProjektStatus.eingestellt);
      expect(
        statusMeilensteinTitel(ProjektStatus.eingestellt),
        'Nicht weiter verfolgt',
      );
    });
  });

  group('Mit der Datenbank', () {
    late AppDatabase db;
    late ProjektRepository repo;
    late EntwicklungDateienDienst dateien;
    late MailAblage ablage;

    setUp(() async {
      db = testDatenbank();
      repo = ProjektRepository(db);
      dateien = EntwicklungDateienDienst(db);
      ablage = MailAblage(db, dateien);
      // Der Datenschlüssel entsteht mit dem Passwort.
      await EntwicklungZugang(
        DbEntwicklungsSpeicher(db),
        iterationen: 1000,
        imHintergrund: false,
      ).festlegen('geheim123');
    });
    tearDown(() => db.close());

    Future<List<ProjektEintrag>> verlauf(String id) =>
        repo.eintraegeBeobachten(id).first;

    test('anlegen: Gesamtprojekt mit Mustern, Kunde für alle', () async {
      final id = await repo.gesamtprojektAnlegen(
        name: 'Grillsortiment 2027',
        kunde: ' Beispiel Feinkost ',
        anfrage: 'Drei Bratwürste für die Grillsaison',
        muster: ['Bratwurst grob', '', 'Bratwurst Käse'],
        jetzt: DateTime(2026, 10, 1, 9),
      );
      final g = (await repo.gesamtprojekt(id))!;
      expect(g.name, 'Grillsortiment 2027');
      expect(g.kunde, 'Beispiel Feinkost');
      expect(g.anfrage, 'Drei Bratwürste für die Grillsaison');

      final muster = await repo.musterBeobachten(id).first;
      expect([for (final m in muster) m.name], [
        'Bratwurst grob',
        'Muster 2',
        'Bratwurst Käse',
      ]);
      for (final m in muster) {
        expect(m.gesamtprojektId, id);
        expect(m.kunde, 'Beispiel Feinkost');
        final v = await verlauf(m.id);
        expect(v.single.titel, 'Muster angelegt');
        expect(v.single.beschreibung, 'Im Gesamtprojekt „Grillsortiment 2027"');
      }
      // Im Verlauf des Gesamtprojekts: sein eigener Anfang.
      expect([for (final e in await verlauf(id)) e.titel], [
        'Gesamtprojekt angelegt',
      ]);
      // Ein Muster mehr — es bekommt den Kunden des Gesamtprojekts.
      final neu = await repo.projektAnlegen(
        name: 'Bratwurst fein',
        kunde: 'Anderer Kunde',
        gesamtprojektId: id,
      );
      expect((await repo.projekt(neu))!.kunde, 'Beispiel Feinkost');
      expect(await repo.muster(id), hasLength(4));
    });

    test('ein neuer Kunde gilt für alle Muster', () async {
      final id = await repo.gesamtprojektAnlegen(
        name: 'Snacks',
        muster: ['A', 'B'],
      );
      await repo.gesamtprojektAendern(
        id,
        const EntwicklungGesamtprojekteCompanion(kunde: Value('Muster AG')),
      );
      for (final m in await repo.muster(id)) {
        expect(m.kunde, 'Muster AG');
      }
      expect((await repo.gesamtprojekt(id))!.kunde, 'Muster AG');
    });

    test('nicht weiter verfolgt: mit Grund im Verlauf, wieder aufnehmen',
        () async {
      final id = await repo.gesamtprojektAnlegen(
        name: 'Snacks',
        muster: ['A'],
      );
      final a = (await repo.muster(id)).single;
      await repo.statusAendern(a.id, ProjektStatus.validierung);
      await repo.statusAendern(
        a.id,
        ProjektStatus.eingestellt,
        grund: ' Der Kunde nimmt Muster B. ',
      );
      expect((await repo.projekt(a.id))!.status, 'eingestellt');
      final e = (await verlauf(a.id))
          .firstWhere((e) => e.titel == 'Nicht weiter verfolgt');
      expect(e.beschreibung, 'Grund: Der Kunde nimmt Muster B.\n'
          'Status vorher: Validierung');
      expect(e.wert, 'status:validierung>eingestellt');
      // Wieder aufnehmen führt in die Validierung.
      expect(phaseVorDemArchiv(await verlauf(a.id)), ProjektStatus.validierung);
    });

    test('ein Projekt ins Gesamtprojekt aufnehmen und wieder lösen',
        () async {
      final g = await repo.gesamtprojektAnlegen(name: 'Grill');
      final p = await repo.projektAnlegen(
        name: 'Frikadelle',
        kunde: 'Beispiel Feinkost',
        jetzt: DateTime(2026, 10, 1),
      );
      // Das Gesamtprojekt hat noch keinen Kunden: Es übernimmt den des
      // Projekts.
      await repo.inGesamtprojektVerschieben(
        p,
        g,
        jetzt: DateTime(2026, 10, 2),
      );
      expect((await repo.projekt(p))!.gesamtprojektId, g);
      expect((await repo.gesamtprojekt(g))!.kunde, 'Beispiel Feinkost');
      expect(
        (await verlauf(p)).first.titel,
        'Ins Gesamtprojekt aufgenommen',
      );

      // Hat es einen, gilt der für das neue Muster.
      final q = await repo.projektAnlegen(name: 'Cevapcici', kunde: 'Alt');
      await repo.inGesamtprojektVerschieben(q, g);
      expect((await repo.projekt(q))!.kunde, 'Beispiel Feinkost');

      await repo.inGesamtprojektVerschieben(
        q,
        null,
        jetzt: DateTime.now().add(const Duration(days: 1)),
      );
      final geloest = (await repo.projekt(q))!;
      expect(geloest.gesamtprojektId, isNull);
      final v = await verlauf(q);
      expect(v.first.titel, 'Aus dem Gesamtprojekt gelöst');
      expect(v.first.beschreibung, 'Bisher in „Grill"');
      expect(await repo.muster(g), hasLength(1));
    });

    test('ein Gesamtprojekt um ein Projekt bilden — die Mails wandern mit',
        () async {
      final p = await repo.projektAnlegen(
        name: 'Bratwurst grob',
        kunde: 'Beispiel Feinkost',
        produktidee: 'Für den Grill',
      );
      final roh = Uint8List.fromList(utf8.encode(_mail));
      final bericht = await ablage.ablegen(p, [
        (name: 'Anfrage.eml', inhalt: roh),
        (
          name: 'Muster-Foto.txt',
          inhalt: Uint8List.fromList(utf8.encode('Foto')),
        ),
      ]);
      expect(bericht.mails, 1);
      expect(bericht.anhaenge, 1);
      expect((await repo.dateienBeobachten(p).first), hasLength(3));

      final g = await repo.gesamtprojektUmProjekt(p, name: 'Grill 2027');
      final gesamt = (await repo.gesamtprojekt(g))!;
      expect(gesamt.kunde, 'Beispiel Feinkost');
      expect(gesamt.anfrage, 'Für den Grill');
      expect((await repo.projekt(p))!.gesamtprojektId, g);

      // Die Mail mit Mail-Datei und Anhang ist jetzt im Gesamtprojekt …
      final imGesamt = await verlauf(g);
      expect(
        [for (final e in imGesamt) e.titel],
        containsAll(['Gesamtprojekt angelegt', 'Grillanfrage 2027']),
      );
      expect(
        [for (final d in await repo.dateienBeobachten(g).first) d.name]
          ..sort(),
        ['Anfrage.eml', 'Preisliste.pdf'],
      );
      // … die andere Datei bleibt beim Muster.
      final imMuster = await verlauf(p);
      expect(
        imMuster.where((e) => e.art == EintragArt.email.schluessel),
        isEmpty,
      );
      expect(
        [for (final d in await repo.dateienBeobachten(p).first) d.name],
        ['Muster-Foto.txt'],
      );
    });

    test('einen Eintrag verschieben: Datei mit, Bezug zum Stand weg',
        () async {
      final g = await repo.gesamtprojektAnlegen(name: 'Grill', muster: ['A']);
      final a = (await repo.muster(g)).single;
      final dateiId = await dateien.speichern(
        name: 'Spezifikation.pdf',
        inhalt: [1, 2, 3],
        projektId: a.id,
      );
      final rezepturen = EntwicklungRepository(db);
      final r = await rezepturen.rezepturAnlegen(name: 'A', projektId: a.id);
      final stand = (await rezepturen.neuesteVersion(r))!.id;
      final e = await repo.eintragAnlegen(
        projektId: a.id,
        art: EintragArt.datei,
        titel: 'Spezifikation des Kunden',
        datum: DateTime(2026, 10, 2),
        dateiId: dateiId,
        versionId: stand,
      );
      // Sie war das Produktfoto — im Gesamtprojekt ist sie es nicht mehr.
      await repo.produktfotoSetzen(a.id, dateiId);

      await repo.eintragVerschieben(e, g);
      final verschoben = (await repo.eintrag(e))!;
      expect(verschoben.projektId, g);
      expect(verschoben.versionId, isNull);
      expect((await dateien.datei(dateiId))!.projektId, g);
      expect((await repo.projekt(a.id))!.bildDateiId, isNull);
      // Zurück ins Muster über die Datei — der Eintrag geht mit.
      await repo.dateiVerschieben(dateiId, a.id);
      expect((await repo.eintrag(e))!.projektId, a.id);
      expect((await dateien.datei(dateiId))!.projektId, a.id);
    });

    test('ein Eintrag im Gesamtprojekt macht es zum zuletzt geänderten',
        () async {
      final g = await repo.gesamtprojektAnlegen(
        name: 'Grill',
        jetzt: DateTime(2026, 1, 1),
      );
      expect((await repo.gesamtprojekt(g))!.updatedAt, DateTime(2026, 1, 1));
      await repo.eintragAnlegen(
        projektId: g,
        art: EintragArt.notiz,
        titel: 'Anruf beim Kunden',
        datum: DateTime(2026, 10, 2),
      );
      expect(
        (await repo.gesamtprojekt(g))!.updatedAt.isAfter(DateTime(2026, 2)),
        isTrue,
      );
    });

    test('löschen: das Gesamtprojekt mit seinen Mustern', () async {
      final g = await repo.gesamtprojektAnlegen(name: 'Grill', muster: ['A']);
      final a = (await repo.muster(g)).single;
      final einzeln = await repo.projektAnlegen(name: 'Für sich');
      final rezepturen = EntwicklungRepository(db);
      final r = await rezepturen.rezepturAnlegen(name: 'A', projektId: a.id);

      await repo.gesamtprojektLoeschen(g);
      expect(await repo.gesamtprojekteBeobachten().first, isEmpty);
      expect(await repo.muster(g), isEmpty);
      expect(
        [for (final p in await repo.projekteBeobachten().first) p.id],
        [einzeln],
      );
      // Die Rezeptur bleibt — ohne Projekt.
      expect((await rezepturen.rezeptur(r))!.projektId, isNull);
      // Ein Muster für ein gelöschtes Gesamtprojekt gibt es nicht.
      expect(
        () => repo.projektAnlegen(name: 'Zu spät', gesamtprojektId: g),
        throwsStateError,
      );
    });

    test('ein Gesamtprojekt aus einer Mail: die Anfrage für alle Muster',
        () async {
      final roh = Uint8List.fromList(utf8.encode(_mail));
      final mail = alsMail('Anfrage.eml', roh)!;
      final id = await ablage.gesamtprojektAusMail(
        mail: mail,
        datei: (name: 'Anfrage.eml', inhalt: roh),
        name: 'Grill 2027',
        kunde: 'Beispiel Feinkost',
        anfrage: 'Drei Bratwürste',
        muster: ['Grob', 'Fein'],
      );
      expect(
        [for (final m in await repo.musterBeobachten(id).first) m.name],
        ['Grob', 'Fein'],
      );
      final v = await verlauf(id);
      expect(
        [for (final e in v) e.titel],
        containsAll(['Gesamtprojekt angelegt', 'Grillanfrage 2027']),
      );
      expect(
        [for (final d in await repo.dateienBeobachten(id).first) d.name]
          ..sort(),
        ['Anfrage.eml', 'Preisliste.pdf'],
      );
    });

    test('Projektbericht eines Musters: Gesamtprojekt und seine Mails',
        () async {
      final g = await repo.gesamtprojektAnlegen(
        name: 'Grill 2027',
        kunde: 'Beispiel Feinkost',
        anfrage: 'Drei Bratwürste für die Grillsaison',
        muster: ['Bratwurst grob', 'Bratwurst fein'],
        jetzt: DateTime(2026, 10, 1),
      );
      await ablage.ablegen(g, [
        (name: 'Anfrage.eml', inhalt: Uint8List.fromList(utf8.encode(_mail))),
      ]);
      final grob = (await repo.musterBeobachten(g).first).first;
      final b = await berichtLaden(db, dateien, grob);
      expect(b.gesamtprojekt!.name, 'Grill 2027');
      expect([for (final m in b.muster) m.name], [
        'Bratwurst grob',
        'Bratwurst fein',
      ]);
      expect([for (final e in b.gesamtVerlauf) e.titel], [
        'Grillanfrage 2027',
        'Gesamtprojekt angelegt',
      ]);
      // Im Verlauf des Berichts gekennzeichnet.
      expect(
        [for (final e in b.mitGesamtVerlauf().verlauf) e.titel],
        containsAll([
          'Muster angelegt',
          'Grillanfrage 2027 (Gesamtprojekt)',
        ]),
      );
      expect(
        b.verlauf.map((e) => e.titel),
        isNot(contains('Grillanfrage 2027')),
      );

      Future<String> text(BerichtInhalt inhalt) async {
        final e = await druckSetzen(
          berichtDruck(b, inhalt: inhalt, gedrucktAm: DateTime(2026, 10, 9)),
          const DruckLayout(),
          komprimiert: false,
        );
        return latin1.decode(e.bytes);
      }

      final mit = await text(const BerichtInhalt());
      // Auf dem Deckblatt und im Kapitel Projekt das Gesamtprojekt, die
      // Muster und die Mail aus dem Gesamtprojekt im Verlauf.
      expect(mit, contains('(Gesamtprojekt)'));
      expect(mit, contains(r'(\(dieser)'));
      expect(mit, contains('(Grillanfrage)'));
      expect(mit, contains(r'(\(Gesamtprojekt\))'));
      final ohne = await text(const BerichtInhalt(gesamtKorrespondenz: false));
      expect(ohne, isNot(contains('(Grillanfrage)')));
      expect(ohne, contains(r'(\(dieser)'));
    });

    test('Sicherung: Gesamtprojekte und Verweise kommen wieder', () async {
      final g = await repo.gesamtprojektAnlegen(
        name: 'Grill',
        kunde: 'Beispiel Feinkost',
        muster: ['A'],
      );
      final daten = jsonDecode(jsonEncode(await EntwicklungDaten.lesen(db)))
          as Map<String, dynamic>;
      expect(daten['gesamtprojekte'], hasLength(1));
      await EntwicklungDaten.leeren(db);
      expect(await repo.gesamtprojekteBeobachten().first, isEmpty);

      await EntwicklungDaten.schreiben(db, daten, const {});
      expect((await repo.gesamtprojekt(g))!.kunde, 'Beispiel Feinkost');
      expect((await repo.muster(g)).single.name, 'A');
    });
  });
}

ProjektEintrag _eintrag(
  String id,
  String projektId, {
  required int tag,
  EintragArt art = EintragArt.meilenstein,
}) =>
    ProjektEintrag(
      id: id,
      projektId: projektId,
      art: art.schluessel,
      titel: id,
      datum: DateTime(2026, 10, tag),
      status: EintragStatus.erledigt.schluessel,
      createdAt: DateTime(2026, 10, tag),
      updatedAt: DateTime(2026, 10, tag),
    );

ProjektEintrag _wechsel(String id, int tag, String wechsel) => ProjektEintrag(
      id: id,
      projektId: 'p',
      art: EintragArt.meilenstein.schluessel,
      titel: id,
      datum: DateTime(2026, 10, tag),
      status: EintragStatus.erledigt.schluessel,
      wert: '$kStatusWertPraefix$wechsel',
      createdAt: DateTime(2026, 10, tag),
      updatedAt: DateTime(2026, 10, tag),
    );

EntwicklungsProjekt _projekt(
  String id, {
  String name = 'Projekt',
  String status = 'entwicklung',
  String? gesamt,
  int angelegt = 1,
  DateTime? geaendert,
}) =>
    EntwicklungsProjekt(
      id: id,
      name: name,
      status: status,
      neuerProzess: false,
      neueZutaten: false,
      gesamtprojektId: gesamt,
      createdAt: DateTime(2026, 9, angelegt),
      updatedAt: geaendert ?? DateTime(2026, 9),
    );

Gesamtprojekt _gesamt({
  String id = 'g',
  String name = 'Grill',
  String? kunde,
  required DateTime geaendert,
}) =>
    Gesamtprojekt(
      id: id,
      name: name,
      kunde: kunde,
      createdAt: DateTime(2026, 8),
      updatedAt: geaendert,
    );

/// Eine erfundene Anfrage mit einem Anhang.
const String _mail = 'From: Erika Beispiel <erika@beispiel-feinkost.de>\r\n'
    'To: Entwicklung <entwicklung@beispiel.de>\r\n'
    'Subject: Grillanfrage 2027\r\n'
    'Date: Mon, 5 Oct 2026 10:00:00 +0200\r\n'
    'MIME-Version: 1.0\r\n'
    'Content-Type: multipart/mixed; boundary="teil"\r\n'
    '\r\n'
    '--teil\r\n'
    'Content-Type: text/plain; charset=utf-8\r\n'
    '\r\n'
    'Wir suchen drei Bratwürste für die Grillsaison.\r\n'
    '--teil\r\n'
    'Content-Type: application/pdf; name="Preisliste.pdf"\r\n'
    'Content-Disposition: attachment; filename="Preisliste.pdf"\r\n'
    'Content-Transfer-Encoding: base64\r\n'
    '\r\n'
    'JVBERi0xLjQK\r\n'
    '--teil--\r\n';
