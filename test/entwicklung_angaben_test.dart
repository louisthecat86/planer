import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/services/auto_backup_trigger.dart';
import 'package:produktion_planer/core/theme/app_theme.dart';
import 'package:produktion_planer/features/entwicklung/projekte/angaben_assistent.dart';
import 'package:produktion_planer/features/entwicklung/projekte/angaben_luecken.dart';
import 'package:produktion_planer/features/entwicklung/projekte/datei_aktionen.dart'
    show dateiInhaltProvider;
import 'package:produktion_planer/features/entwicklung/projekte/projekt_modell.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_repository.dart';
import 'package:produktion_planer/features/entwicklung/spezifikation/spez_angaben.dart';

/// Tests für den Assistenten „Angaben ergänzen…" (F39): was einem Projekt
/// fehlt — und wie er es eine Angabe nach der anderen abfragt. Alles
/// erfunden.
void main() {
  final zeit = DateTime(2026, 10, 22);

  EntwicklungsProjekt projekt({
    String? artikelnummer = 'T-100',
    String? artikelId,
    Sensorik sensorik = const Sensorik(
      aussehen: 'goldbraun',
      geruch: 'würzig',
      geschmack: 'kräftig',
      konsistenz: 'saftig',
    ),
    SpezAngaben angaben = const SpezAngaben(),
    String? bild,
    bool fotoSpaeter = false,
  }) =>
      EntwicklungsProjekt(
        id: 'p1',
        name: 'Frikadelle Testart',
        status: ProjektStatus.entwicklung.schluessel,
        neuerProzess: false,
        neueZutaten: false,
        artikelnummer: artikelnummer,
        artikelId: artikelId,
        sensorik: sensorik.alsJson(),
        spezifikation: angaben.alsJson(),
        bildDateiId: bild,
        checkliste: fotoSpaeter
            ? checklisteMit(null, 'produktfotoHinterlegt', kCheckSpaeter)
            : null,
        createdAt: zeit,
        updatedAt: zeit,
      );

  const vollstaendig = SpezAngaben(
    lagerung: 'gekühlt',
    haltbarkeit: '21',
    verpackung: Verpackung(um: {'e2_kiste'}),
  );

  group('Was fehlt', () {
    test('ein neues Projekt: alles, was die App nicht selbst weiß', () {
      expect(
        fehlendeAngaben(
          projekt(artikelnummer: null, sensorik: const Sensorik()),
        ),
        AngabeSchritt.values,
      );
      // Die Bezeichnung fragt sie nicht — ohne eigene ist es der
      // Projektname.
      expect(
        fehlendeAngaben(projekt(angaben: vollstaendig, bild: 'b1')),
        isEmpty,
      );
    });

    test('Sensorik zählt erst mit allen vier, Maße allein nicht', () {
      final halb = projekt(
        angaben: vollstaendig,
        bild: 'b1',
        sensorik: const Sensorik(aussehen: 'hell', gewicht: '80 g'),
      );
      expect(fehlendeAngaben(halb), [AngabeSchritt.sensorik]);
    });

    test('ein zurückgestelltes Foto fragt der Assistent nicht', () {
      expect(
        fehlendeAngaben(projekt(angaben: vollstaendig, fotoSpaeter: true)),
        isEmpty,
      );
      expect(
        fehlendeAngaben(projekt(angaben: vollstaendig)),
        [AngabeSchritt.produktfoto],
      );
    });

    test('nach der Freigabe stehen Nummer und Haltbarkeit im Artikel', () {
      final p = projekt(
        artikelnummer: null,
        artikelId: 'a1',
        bild: 'b1',
        angaben: const SpezAngaben(
          lagerung: 'gekühlt',
          verpackung: Verpackung(einzel: {'beutel'}),
        ),
      );
      expect(fehlendeAngaben(p), isEmpty);
    });

    test('Texte', () {
      expect(angabenAufzaehlen(const [AngabeSchritt.lagerung]), 'Lagerung');
      expect(
        angabenAufzaehlen(const [
          AngabeSchritt.sensorik,
          AngabeSchritt.lagerung,
          AngabeSchritt.verpackung,
        ]),
        'Sensorik, Lagerung und Verpackung',
      );
      expect(angabenFehlenText(1), '1 Angabe fehlt');
      expect(angabenFehlenText(3), '3 Angaben fehlen');
      expect(
        const AssistentErgebnis(
          eingetragen: [AngabeSchritt.lagerung, AngabeSchritt.haltbarkeit],
          spaeter: [AngabeSchritt.produktfoto],
        ).text,
        'Eingetragen: Lagerung und Haltbarkeit · Später: Produktfoto',
      );
      expect(const AssistentErgebnis().text, isEmpty);
    });
  });

  group('Assistent', () {
    late _Speicher speicher;
    setUp(() => speicher = _Speicher());

    Future<void> oeffne(WidgetTester tester, EntwicklungsProjekt p) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            projektProvider.overrideWith((ref, id) => Stream.value(p)),
            projektRepositoryProvider.overrideWithValue(speicher),
            autoBackupTriggerProvider.overrideWithValue(_OhneSicherung()),
            dateiInhaltProvider.overrideWith((ref, id) async => null),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () => angabenErgaenzen(context, p),
                    child: const Text('öffnen'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('öffnen'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> knopf(WidgetTester tester, String key) async {
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // Schließt sich das Fenster, blendet es danach noch aus.
      await tester.pump(const Duration(milliseconds: 300));
    }

    String stand(WidgetTester tester) => tester
        .widget<Text>(find.byKey(const ValueKey('assistent-stand')))
        .data!;

    testWidgets('eine Angabe nach der anderen: Weiter speichert, Später '
        'verschiebt', (tester) async {
      await oeffne(tester, projekt());
      expect(find.text('Angaben ergänzen'), findsOneWidget);
      // Es fehlen Foto, Lagerung, Haltbarkeit und Verpackung.
      expect(stand(tester), '1 von 4');
      expect(find.text('Gibt es schon ein Produktfoto?'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('assistent-foto-waehlen')),
        findsOneWidget,
      );
      // Noch kein Foto: „Später" stellt es zurück wie im Reiter „Produkt".
      await knopf(tester, 'assistent-spaeter');
      expect(speicher.zurueckgestellt, ['p1 produktfotoHinterlegt true']);

      expect(stand(tester), '2 von 4');
      expect(find.text('Wie wird das Produkt gelagert?'), findsOneWidget);
      await tester.tap(find.text('gekühlt bei +2 °C bis +7 °C'));
      await tester.pump();
      await knopf(tester, 'assistent-weiter');
      expect(
        SpezAngaben.aus(speicher.spezifikation).lagerung,
        'gekühlt bei +2 °C bis +7 °C',
      );

      expect(stand(tester), '3 von 4');
      await tester.enterText(
        find.byKey(const ValueKey('assistent-haltbarkeit')),
        '21',
      );
      await knopf(tester, 'assistent-weiter');
      // Jeder Schritt baut auf dem vorigen auf: die Lagerung bleibt.
      final angaben = SpezAngaben.aus(speicher.spezifikation);
      expect(angaben.haltbarkeit, '21');
      expect(angaben.lagerung, 'gekühlt bei +2 °C bis +7 °C');

      expect(stand(tester), '4 von 4');
      expect(find.text('Wie wird es verpackt?'), findsOneWidget);
      expect(find.text('Fertig'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilterChip, 'E2-Kiste'));
      await tester.pump();
      await tester.pump();
      expect(
        SpezAngaben.aus(speicher.spezifikation).verpackung.um,
        {'e2_kiste'},
      );
      await knopf(tester, 'assistent-weiter');

      // Fertig: das Fenster zu, eine Meldung, was geschah.
      expect(find.byKey(const ValueKey('angaben-assistent')), findsNothing);
      expect(
        find.text(
          'Eingetragen: Lagerung, Haltbarkeit und Verpackung · Später: '
          'Produktfoto',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('leer weiter heißt später; Schließen behält, was im Feld steht',
        (tester) async {
      await oeffne(
        tester,
        projekt(
          artikelnummer: null,
          sensorik: const Sensorik(aussehen: 'goldbraun'),
          bild: 'b1',
          angaben: vollstaendig,
        ),
      );
      expect(stand(tester), '1 von 2');
      expect(find.text('Wie lautet die Artikelnummer?'), findsOneWidget);
      // Ohne Eingabe: nichts gespeichert, weiter zur Sensorik.
      await knopf(tester, 'assistent-weiter');
      expect(speicher.gespeichert, isEmpty);
      expect(stand(tester), '2 von 2');
      // Was schon da ist, steht in den Feldern.
      expect(find.text('goldbraun'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('assistent-geruch')),
        'würzig',
      );
      await tester.pump();
      // Zwischendurch schließen: Was im offenen Schritt steht, bleibt.
      await knopf(tester, 'assistent-schliessen');
      expect(find.byKey(const ValueKey('angaben-assistent')), findsNothing);
      expect(Sensorik.aus(speicher.sensorik).geruch, 'würzig');
      expect(Sensorik.aus(speicher.sensorik).aussehen, 'goldbraun');
      expect(
        find.text('Eingetragen: Sensorik · Später: Artikelnummer'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Sensorik: alle vier auf einmal', (tester) async {
      await oeffne(
        tester,
        projekt(
          sensorik: const Sensorik(aussehen: 'goldbraun'),
          bild: 'b1',
          angaben: vollstaendig,
        ),
      );
      expect(find.text('Wie ist das fertige Produkt?'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('assistent-geruch')),
        'würzig',
      );
      await tester.enterText(
        find.byKey(const ValueKey('assistent-geschmack')),
        'kräftig',
      );
      await knopf(tester, 'assistent-weiter');
      final s = Sensorik.aus(speicher.sensorik);
      expect(
        (s.aussehen, s.geruch, s.geschmack, s.konsistenz),
        ('goldbraun', 'würzig', 'kräftig', ''),
      );
      expect(find.text('Eingetragen: Sensorik'), findsOneWidget);
    });
  });
}

/// Hält fest, was gespeichert wird — ohne Datenbank.
class _Speicher implements ProjektRepository {
  final gespeichert = <EntwicklungProjekteCompanion>[];
  final zurueckgestellt = <String>[];

  String? get spezifikation => gespeichert
      .lastWhere((d) => d.spezifikation.present)
      .spezifikation
      .value;

  String? get sensorik =>
      gespeichert.lastWhere((d) => d.sensorik.present).sensorik.value;

  @override
  Future<void> projektAendern(
    String id,
    EntwicklungProjekteCompanion daten,
  ) async =>
      gespeichert.add(daten);

  @override
  Future<void> checklisteZurueckstellen(
    String id, {
    required String schluessel,
    required bool zurueck,
  }) async =>
      zurueckgestellt.add('$id $schluessel $zurueck');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// Keine Sicherung im Test.
class _OhneSicherung implements AutoBackupTrigger {
  @override
  void fireDebounced({String reason = 'Daten-Änderung'}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}
