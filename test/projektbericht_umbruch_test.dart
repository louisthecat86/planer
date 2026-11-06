import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/features/entwicklung/bericht/projekt_bericht.dart';
import 'package:produktion_planer/features/entwicklung/daten/dateien.dart';
import 'package:produktion_planer/features/entwicklung/entwicklung_zugang.dart';
import 'package:produktion_planer/features/entwicklung/haccp/haccp_modell.dart';
import 'package:produktion_planer/features/entwicklung/haccp/prozess_modell.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_repository.dart';

import 'helpers/pdf_lesen.dart';
import 'helpers/test_db.dart';

/// Die Seitenumbrüche des Projektberichts: Jedes Kapitel beginnt auf einer
/// neuen Seite. Ein Block — etwa ein Schritt mit seinen Einstellungen —
/// bricht nicht, sondern beginnt auf der nächsten Seite. Was länger ist als
/// eine Seite, läuft weiter, ohne dass der Bericht hängen bleibt.
///
/// Die PDFs entstehen unkomprimiert: So steht jedes gesetzte Wort als
/// „(Wort)" im Inhalt seiner Seite. Alle Daten sind erfunden.
void main() {
  late AppDatabase db;
  late ProjektRepository projekte;
  late EntwicklungDateienDienst dateien;
  final datum = DateTime(2026, 11, 5);

  setUp(() async {
    db = testDatenbank();
    projekte = ProjektRepository(db);
    dateien = EntwicklungDateienDienst(db);
    // Der Datenschlüssel entsteht mit dem Passwort.
    await EntwicklungZugang(
      DbEntwicklungsSpeicher(db),
      iterationen: 1000,
      imHintergrund: false,
    ).festlegen('geheim123');
  });
  tearDown(() => db.close());

  /// Das PDF des Berichts zu Projekt [id], unkomprimiert als Text.
  Future<String> pdf(String id) async {
    final b = await berichtLaden(db, dateien, (await projekte.projekt(id))!);
    final bytes = await baueProjektPdf(
      b,
      gedrucktAm: datum,
      komprimiert: false,
    ).timeout(const Duration(seconds: 60));
    return latin1.decode(bytes);
  }

  test('jedes Kapitel beginnt oben auf einer neuen Seite', () async {
    final id = await projekte.projektAnlegen(name: 'Kurz Testart');
    final roh = await pdf(id);
    final anfaenge = kapitelAnfaenge(roh);
    // Ein junges Projekt — mit dem Meilenstein vom Anlegen im Verlauf.
    // Vorher folgten die Kapitel, die nur sagen, was noch fehlt, dem davor.
    expect(anfaenge, hasLength(7));
    expect([for (final a in anfaenge) a.seite], [2, 3, 4, 5, 6, 7, 8]);
    expect(
      anfaenge.every((a) => a.hoehe == anfaenge.first.hoehe),
      isTrue,
      reason: 'Jedes oben auf der Seite',
    );
    expect(pdfSeiten(roh), hasLength(8));
  });

  test(
      'ein Schritt bleibt bei seinen Einstellungen — die Überschrift bei '
      'der ersten Station', () async {
    final id = await projekte.projektAnlegen(name: 'Kette Testart');
    const abteilungen = ['zerlegung', 'wurstkueche', 'bratstrasse'];
    await projekte.projektAendern(
      id,
      EntwicklungProjekteCompanion(
        prozess: Value(
          Prozessparameter(
            schritte: [
              for (var i = 0; i < 16; i++)
                ProzessSchritt(
                  id: 's$i',
                  abteilung: abteilungen[i ~/ 6],
                  maschine: 'Anlage$i',
                  prozessschritt: 'Testen',
                  notiz: 'Wert$i\nBand mittig\nTemperatur prüfen',
                  werte: [
                    for (var w = 0; w < 7; w++)
                      ProzessWert(name: 'Einstellung $w', wert: '$w'),
                  ],
                ),
            ],
          ).alsJson(),
        ),
      ),
    );
    final s = pdfSeiten(await pdf(id));
    int seiteVon(String wort) => s.indexWhere((t) => t.contains('($wort)'));

    final verteilt = <int>{};
    for (var i = 0; i < 16; i++) {
      final titel = seiteVon('Anlage$i');
      expect(titel, isNonNegative, reason: 'Anlage$i');
      expect(seiteVon('Wert$i'), titel, reason: 'Anlage$i');
      verteilt.add(titel);
    }
    expect(verteilt.length, greaterThan(1), reason: 'Über mehrere Seiten');
    // Die Überschrift „Prozess" steht mit der ersten Station.
    expect(s[seiteVon('Anlage0')], contains('(Prozess)'));
  });

  test('länger als eine Seite: läuft weiter, nichts geht verloren', () async {
    final id = await projekte.projektAnlegen(name: 'Lang Testart');
    await projekte.projektAendern(
      id,
      EntwicklungProjekteCompanion(
        notizen: Value([for (var i = 0; i < 300; i++) 'Notiz$i'].join('\n')),
        prozess: Value(
          Prozessparameter(
            schritte: [
              ProzessSchritt(
                id: 's1',
                abteilung: 'wurstkueche',
                maschine: 'Testanlage',
                notiz: [for (var i = 0; i < 150; i++) 'Zeile$i'].join('\n'),
              ),
            ],
          ).alsJson(),
        ),
        haccp: Value(
          Haccp(
            gefahren: [
              for (var g = 0; g < 20; g++)
                Gefahr(
                  id: 'g$g',
                  gefahr: 'Gefahr$g',
                  massnahmen: 'Lange Maßnahme. ' * 40,
                ),
            ],
          ).alsJson(),
        ),
      ),
    );
    final s = pdfSeiten(await pdf(id));
    final alles = s.join();
    for (final wort in ['Notiz0', 'Notiz299', 'Zeile0', 'Zeile149']) {
      expect(alles, contains('($wort)'), reason: wort);
    }
    for (var g = 0; g < 20; g++) {
      expect(alles, contains('(Gefahr$g)'));
    }
    // Die langen Einstellungen laufen über mehrere Seiten — in voller
    // Größe, nicht auf eine Seite verkleinert.
    int seiteVon(String wort) => s.indexWhere((t) => t.contains('($wort)'));
    expect(seiteVon('Zeile149'), greaterThan(seiteVon('Zeile0')));
  });
}
