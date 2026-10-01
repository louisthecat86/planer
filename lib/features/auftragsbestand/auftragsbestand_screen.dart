import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import '../../core/providers/artikel_providers.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/artikel_anlage_service.dart';
import '../../core/services/auftragsbestand_deckung.dart';
import '../../core/services/auftragsbestand_import_service.dart';
import '../../core/services/auftragsbestand_vergleich.dart';
import '../../core/services/auto_backup_trigger.dart';
import '../articles/article_list_screen.dart' show articlesProvider;
import '../bedarf/bedarf_screen.dart' show bedarfProvider, heuteProvider;
import '../datenblatt/datenblatt.dart';
import '../whiteboard/whiteboard_provider.dart'
    show Ausbeute, AusbeuteQuelle, dailyTasksProvider, ermittleAusbeute;
import 'auftrags_einplanung.dart';
import 'planung_pruefen.dart'
    show
        PlanungsKonflikt,
        PruefArt,
        ermittleKonflikte,
        verschobeneZiele,
        wieUmgehaengt;

// ═══════════════════════════════════════════════════════════════════════════
// Daten für die Ansicht
// ═══════════════════════════════════════════════════════════════════════════

/// Ein Artikel des Auftragsbestands samt Deckung aus Lager und Produktion.
class AuftragsbestandZeile {
  const AuftragsbestandZeile({
    required this.artikel,
    required this.positionen,
    required this.zugaenge,
    required this.deckung,
    this.vormerkungen = const [],
    this.verschoben = const {},
  });

  final AuftragsArtikel artikel;
  final List<AuftragsPosition> positionen;

  /// Produktionen der App für diesen Artikel — auch die, die nicht
  /// mitzählen (vor dem Bericht fertig, Menge unbekannt).
  final List<ProduktionsZugang> zugaenge;

  final ArtikelDeckung deckung;

  /// Offene Planungsaufträge für diesen Artikel: an den Planungsvorschlag
  /// übergeben, noch nicht (ganz) eingeplant.
  final List<Vormerkung> vormerkungen;

  /// Verschobene Aufträge, deren Planung noch am alten Tag hängt:
  /// Schlüssel der Zeile am neuen Tag → Konflikt. Diese Zeilen sind
  /// gesperrt, bis die Verschiebung geklärt ist.
  final Map<String, PlanungsKonflikt> verschoben;

  Set<String> get belege => {for (final p in positionen) p.beleg};
  Set<String> get kunden => {for (final p in positionen) p.debitor};

  /// Hier ist etwas zu tun: noch zu bündeln, zu spät eingeplant — oder
  /// ein verschobener Auftrag zu klären.
  bool get handlungsbedarf => !deckung.erledigt || verschoben.isNotEmpty;

  /// Eingeplante Produktionen ohne Fertigmenge — sie zählen nicht mit.
  int get ohneMenge => zugaenge
      .where((z) => z.kg == null && z.art != ZugangsArt.imLager)
      .length;
}

/// Der zuletzt eingelesene Auftragsbestand.
class AuftragsbestandAnsicht {
  const AuftragsbestandAnsicht({
    required this.zeilen,
    this.stand,
    this.von,
    this.bis,
    this.importiertAm,
    this.berichtTag,
    this.konflikte = const [],
  });

  final List<AuftragsbestandZeile> zeilen;
  final DateTime? stand;
  final DateTime? von;
  final DateTime? bis;
  final DateTime? importiertAm;

  /// Tag, gegen den die Produktionen eingeordnet wurden: der Tag des
  /// Berichts, ersatzweise der Tag des Einlesens.
  final DateTime? berichtTag;

  /// Planung, die nicht mehr zum Bericht passt — Planungsaufträge und
  /// Produktionen an verschobenen, verringerten oder entfallenen
  /// Aufträgen. Anzupassen in der Änderungsansicht.
  final List<PlanungsKonflikt> konflikte;

  bool get leer => zeilen.isEmpty;
}

/// Lädt den Auftragsbestand und rechnet je Artikel die Deckung: erst das
/// Lager, dann die Produktionen der App, zuletzt die Vormerkungen für den
/// Planungsvorschlag.
///
/// `autoDispose`: Beim nächsten Öffnen wird neu gelesen und gerechnet. Die
/// Rechnung ist billig — ein paar tausend Zeilen —, und so gibt es keinen
/// veralteten Zwischenstand.
final auftragsbestandProvider =
    FutureProvider.autoDispose<AuftragsbestandAnsicht>((ref) async {
  final db = ref.watch(databaseProvider);
  // Um Mitternacht rechnet die Ansicht neu: Was gestern eingeplant war,
  // ist heute produziert.
  final heute = ref.watch(heuteProvider);

  final artikel = await db.select(db.auftragsbestandArtikel).get();
  if (artikel.isEmpty) return const AuftragsbestandAnsicht(zeilen: []);

  final positionen = await db.select(db.auftragsbestandPositionen).get();
  final jeArtikel = <String, List<AuftragsPosition>>{};
  for (final p in positionen) {
    jeArtikel.putIfAbsent(p.artikelnummer, () => []).add(p);
  }

  final erster = artikel.first;
  final stand = erster.berichtStand ?? erster.importiertAm;
  final berichtTag = DateTime(stand.year, stand.month, stand.day);
  final zugaenge = await ladeProduktionsZugaenge(
    db,
    heute: heute,
    berichtTag: berichtTag,
  );
  final vormerkungen = await ladeVormerkungen(db);
  // Der vorige Bericht zeigt, ob ein Auftrag verschoben wurde: am alten
  // Tag verschwunden, am neuen aufgetaucht.
  final konflikte = ermittleKonflikte(
    bestand: bestandAusTabellen(artikel, positionen),
    vorher: await ladeVorherigenBestand(db),
    vormerkungen: vormerkungen,
    zugaenge: zugaenge,
  );
  // Verschobene Aufträge: gerechnet, als hinge ihre Planung schon am
  // neuen Tag — sonst stünden sie dort als offen da. Bündeln lassen sie
  // sich erst, wenn die Verschiebung geklärt ist.
  final gerechnet = wieUmgehaengt(
    vormerkungen: vormerkungen,
    zugaenge: zugaenge,
    konflikte: konflikte,
  );
  final verschoben = verschobeneZiele(konflikte);

  return AuftragsbestandAnsicht(
    stand: erster.berichtStand,
    von: erster.zeitraumVon,
    bis: erster.zeitraumBis,
    importiertAm: erster.importiertAm,
    berichtTag: berichtTag,
    konflikte: konflikte,
    zeilen: [
      for (final a in artikel)
        _zeile(
          a,
          jeArtikel[a.artikelnummer] ?? const [],
          zugaenge: zugaenge[a.artikelnummer] ?? const [],
          vormerkungen: vormerkungen[a.artikelnummer] ?? const [],
          zugaengeGerechnet: gerechnet.zugaenge[a.artikelnummer] ?? const [],
          vormerkungenGerechnet:
              gerechnet.vormerkungen[a.artikelnummer] ?? const [],
          verschoben: verschoben[a.artikelnummer] ?? const {},
        ),
    ],
  );
});

/// Ein Artikel samt Deckung. Angezeigt werden [zugaenge] und
/// [vormerkungen], wie sie in der Datenbank stehen; gerechnet wird mit den
/// umgehängten (siehe [wieUmgehaengt]).
AuftragsbestandZeile _zeile(
  AuftragsArtikel artikel,
  List<AuftragsPosition> positionen, {
  required List<ProduktionsZugang> zugaenge,
  required List<Vormerkung> vormerkungen,
  required List<ProduktionsZugang> zugaengeGerechnet,
  required List<Vormerkung> vormerkungenGerechnet,
  required Map<String, PlanungsKonflikt> verschoben,
}) {
  return AuftragsbestandZeile(
    artikel: artikel,
    positionen: positionen,
    zugaenge: zugaenge,
    vormerkungen: vormerkungen,
    verschoben: verschoben,
    deckung: berechneDeckung(
      lagerKg: artikel.lagerKg,
      positionen: positionen,
      zugaenge: zugaengeGerechnet,
      vormerkungen: vormerkungenGerechnet,
      gesperrt: verschoben.keys.toSet(),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Screen
// ═══════════════════════════════════════════════════════════════════════════

/// Sortierungen der Artikelliste.
enum _Sortierung {
  engpass('Frühester Engpass'),
  fehlmenge('Noch zu bündeln ↓'),
  auftrag('Auftragsmenge ↓'),
  nummer('Artikelnummer');

  const _Sortierung(this.label);
  final String label;
}

/// Auftragsbestand aus Navision: Aufträge je Artikel nach Warenausgang,
/// dagegen gerechnet das Lager und die Produktionen der App — und was
/// danach noch einzuplanen ist.
///
/// Abgehakte Versandtage gehen entweder an den Planungsvorschlag (als
/// Planungsauftrag mit spätestem Produktionstag) oder direkt an einem
/// festen Tag ins Board.
class AuftragsbestandScreen extends ConsumerStatefulWidget {
  const AuftragsbestandScreen({super.key});

  @override
  ConsumerState<AuftragsbestandScreen> createState() =>
      _AuftragsbestandScreenState();
}

class _AuftragsbestandScreenState
    extends ConsumerState<AuftragsbestandScreen> {
  final _suche = TextEditingController();

  /// Standard: nur Artikel, bei denen etwas fehlt oder zu spät kommt —
  /// das ist die Arbeit. Der Zähler zeigt, wie viele es sind.
  bool _nurOffene = true;
  String? _abteilung;
  _Sortierung _sortierung = _Sortierung.engpass;
  final Set<String> _offen = {};

  /// Abgehakte Versandtage je Artikelnummer — die Auswahl für „Zur
  /// Planung hinzufügen".
  final Map<String, Set<DateTime>> _markiert = {};

  bool _liest = false;
  bool _legtAn = false;
  bool _plant = false;
  String? _fehler;
  List<String> _hinweise = const [];

  @override
  void dispose() {
    _suche.dispose();
    super.dispose();
  }

  // ── Einlesen ─────────────────────────────────────────────────────────

  Future<void> _einlesen() async {
    final gewaehlt = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (gewaehlt == null || !mounted) return;
    final datei = gewaehlt.files.isNotEmpty ? gewaehlt.files.first : null;
    var bytes = datei?.bytes;
    final pfad = datei?.path;
    if (bytes == null && pfad != null) {
      try {
        bytes = await File(pfad).readAsBytes();
      } catch (_) {
        bytes = null;
      }
      if (!mounted) return;
    }
    if (bytes == null) {
      setState(() => _fehler = 'Die gewählte Datei ließ sich nicht lesen.');
      return;
    }

    // Vor der nächsten Wartestelle geholt: Container, Router und Messenger
    // überleben auch, wenn jemand den Bildschirm währenddessen schließt.
    final container = ProviderScope.containerOf(context, listen: false);
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final db = ref.read(databaseProvider);
    final service = AuftragsbestandImportService(db);

    setState(() {
      _liest = true;
      _fehler = null;
      _hinweise = const [];
    });
    try {
      final bericht = await service.lese(bytes);
      final bisher = await ladeBestand(db);
      final neu = BestandsStand.ausBericht(
        bericht,
        importiertAm: DateTime.now(),
      );

      // Sieht der Bericht gefiltert, veraltet oder verrutscht aus? Dann
      // erst fragen — er ersetzt den bisherigen vollständig, und was darin
      // fehlt, gälte als nicht mehr offen.
      final zweifel = [
        for (final h in pruefeUmfang(bisher, neu))
          if (h.ernst) h,
      ];
      if (zweifel.isNotEmpty) {
        if (!mounted) return;
        setState(() => _liest = false);
        final weiter = await showDialog<bool>(
          context: context,
          builder: (_) => _UmfangsDialog(hinweise: zweifel),
        );
        if (weiter != true || !mounted) return;
        setState(() => _liest = true);
      }

      final ergebnis = await service.speichere(bericht);
      container.invalidate(auftragsbestandProvider);

      final verpackung = ergebnis.uebersprungen.isEmpty
          ? ''
          : ' · ${ergebnis.uebersprungen.length} Verpackungs- und '
              'Palettenartikel ausgelassen';
      final vergleich = vergleicheBestand(bisher, neu);
      final kurz = vergleich.kurzfassung;
      final standBisher = bisher.stand;
      final standNeu = neu.stand;
      final String seitdem;
      if (vergleich.ohneVorher) {
        seitdem = '';
      } else if (standBisher != null &&
          standNeu != null &&
          standBisher.isAtSameMomentAs(standNeu)) {
        seitdem = '\nDerselbe Bericht wie zuvor — die Änderungen zeigen '
            'weiter den Vergleich mit dem Bericht davor.';
      } else if (kurz.isEmpty) {
        seitdem = '\nSeit dem vorigen Bericht keine wesentlichen Änderungen.';
      } else {
        seitdem = '\nSeit dem vorigen Bericht: $kurz';
      }
      // Die Meldung auch dann, wenn der Bildschirm inzwischen geschlossen
      // wurde — der Messenger gehört zur App.
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 10),
          // Mit Aktion blieben Meldungen sonst stehen, bis jemand klickt.
          persist: false,
          content: Text(
            '${ergebnis.artikel} Artikel · ${ergebnis.positionen} '
            'Auftragszeilen · ${ergebnis.kunden} Kunden eingelesen'
            '$verpackung$seitdem',
          ),
          action: vergleich.ohneVorher
              ? null
              : SnackBarAction(
                  label: 'Änderungen ansehen',
                  onPressed: () =>
                      router.pushNamed('auftragsbestandAenderungen'),
                ),
        ),
      );
      if (!mounted) return;
      setState(() {
        _offen.clear();
        _markiert.clear();
        _hinweise = ergebnis.warnungen;
      });
    } on FormatException catch (e) {
      if (mounted) setState(() => _fehler = e.message);
    } catch (e) {
      if (mounted) setState(() => _fehler = 'Einlesen fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _liest = false);
    }
  }

  // ── Fehlende Artikel anlegen ─────────────────────────────────────────

  /// Legt die gewählten Artikel des Auftragsbestands, die es in der App
  /// noch nicht gibt, als Hülle an („nicht eingepflegt").
  Future<void> _fehlendeAnlegen(List<AuftragsbestandZeile> fehlende) async {
    // Vor der ersten Wartestelle geholt: Der Container überlebt auch, wenn
    // jemand den Bildschirm währenddessen schließt — die Listen der App
    // müssen trotzdem neu geladen werden.
    final container = ProviderScope.containerOf(context, listen: false);
    final db = ref.read(databaseProvider);

    final auswahl = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _FehlendeDialog(zeilen: fehlende),
    );
    if (auswahl == null || auswahl.isEmpty || !mounted) return;

    setState(() => _legtAn = true);
    try {
      final ergebnis = await ArtikelAnlageService(db).legeAn([
        for (final z in fehlende)
          if (auswahl.contains(z.artikel.artikelnummer))
            FehlenderArtikel(
              nummer: z.artikel.artikelnummer,
              bezeichnung: z.artikel.bezeichnung,
              bezeichnung2: z.artikel.bezeichnung2,
            ),
      ]);
      container.invalidate(appArtikelnummernProvider);
      container.invalidate(articlesProvider);
      if (ergebnis.gesamt > 0) {
        container
            .read(autoBackupTriggerProvider)
            .fireDebounced(reason: 'Artikel aus dem Auftragsbestand angelegt');
      }
      if (!mounted) return;

      final teile = [
        if (ergebnis.angelegt > 0) '${ergebnis.angelegt} angelegt',
        if (ergebnis.reaktiviert > 0)
          '${ergebnis.reaktiviert} früher gelöschte wieder aktiviert',
        if (ergebnis.schonVorhanden > 0)
          '${ergebnis.schonVorhanden} gab es schon',
      ];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(
            ergebnis.gesamt == 0
                ? 'Nichts angelegt · ${teile.join(' · ')}.'
                : 'Artikel ${teile.join(' · ')}. Sie sind als „nicht '
                    'eingepflegt" markiert — Schritte und Stammdaten in der '
                    'Artikelliste nachtragen, dann lassen sie sich '
                    'einplanen.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
            'Anlegen fehlgeschlagen — es wurde nichts angelegt. ($e)',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _legtAn = false);
    }
  }

  // ── Einplanen ────────────────────────────────────────────────────────

  /// Plant die abgehakten Tage eines Artikels ein — mit genau den
  /// Auftragszeilen, die an diesen Tagen noch offen sind. Der Dialog fragt
  /// Menge, Tag und Weg ab:
  ///
  /// * **Planungsvorschlag** (Standard): Es entsteht ein Planungsauftrag
  ///   mit dem Tag als spätestem Produktionstag. Die Zeilen sind
  ///   vorgemerkt, bis der Vorschlag sie in einen Tag legt und der Tag
  ///   übernommen wird.
  /// * **Fester Tag**: Die Kette kommt sofort ins Board, an genau diesem
  ///   Tag. Der Planungsvorschlag plant drumherum.
  Future<void> _einplanen(AuftragsbestandZeile zeile) async {
    final nr = zeile.artikel.artikelnummer;
    final tage = _markiert[nr] ?? const <DateTime>{};
    final bezuege = bezuegeFuerTage(zeile.deckung, tage);
    if (bezuege.isEmpty) {
      setState(() => _markiert.remove(nr));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('An den markierten Tagen ist nichts mehr offen.'),
        ),
      );
      return;
    }

    // Vor der ersten Wartestelle geholt: Der Container überlebt auch, wenn
    // jemand den Bildschirm währenddessen schließt.
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final db = ref.read(databaseProvider);
    final heute = ref.read(heuteProvider);

    final produkt = await (db.select(db.products)
          ..where((p) => p.artikelnummer.equals(nr))
          ..where((p) => p.deletedAt.isNull()))
        .getSingleOrNull();
    if (!mounted) return;
    if (produkt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Artikel $nr gibt es in der App nicht — erst anlegen, dann '
            'einplanen.',
          ),
        ),
      );
      return;
    }

    final ausbeute = await ermittleAusbeute(db, produkt.id);
    if (!mounted) return;

    final gewaehlt = [
      for (final t in zeile.deckung.tage)
        if (tage.contains(t.tag) && t.einplanbar) t,
    ];
    final offenKg = bezuege.fold<double>(0, (s, b) => s + b.kg);
    final auswahl = await showDialog<_Wahl>(
      context: context,
      builder: (_) => _EinplanenDialog(
        artikel: zeile.artikel,
        tage: gewaehlt,
        offenKg: offenKg,
        ausbeute: ausbeute,
        vorschlag: vorschlagProduktionstag(gewaehlt.first.tag, heute),
        heute: heute,
      ),
    );
    if (auswahl == null || !mounted) return;

    setState(() => _plant = true);
    try {
      final String meldung;
      // Das Datenblatt der gerade gebündelten Planung — über die Aktion
      // der Meldung sofort zu drucken.
      final Future<List<Datenblatt>> Function() blatt;
      if (auswahl.fest) {
        final e = await planeAuftragszeilen(
          db: db,
          productId: produkt.id,
          fertigKg: auswahl.fertigKg,
          tag: auswahl.tag,
          bezuege: bezuege,
        );
        container.invalidate(dailyTasksProvider);
        meldung = 'Eingeplant am ${_tagKurz(e.tag)} · '
            '${_kg(e.fertigwareKg)} kg Fertigware '
            '(≈ ${_kg(e.rohwareKg)} kg Rohware) · ${e.schritte} '
            '${e.schritte == 1 ? 'Schritt' : 'Schritte'} im Board';
        final wurzelId = e.wurzelId;
        blatt = () async {
          if (wurzelId == null) return const <Datenblatt>[];
          return alsListe(datenblattFuerKette(db, wurzelId));
        };
      } else {
        final bedarfId = await uebergebeAnPlanungsvorschlag(
          db: db,
          productId: produkt.id,
          fertigKg: auswahl.fertigKg,
          termin: auswahl.tag,
          bezuege: bezuege,
        );
        meldung = 'An den Planungsvorschlag übergeben · '
            '${_kg(auswahl.fertigKg)} kg, spätestens am '
            '${_tagKurz(auswahl.tag)} zu produzieren. Dort mit den übrigen '
            'Bedarfen einplanen.';
        blatt = () => alsListe(datenblattFuerBedarf(db, bedarfId));
      }
      container.invalidate(auftragsbestandProvider);
      container.invalidate(bedarfProvider);
      container.read(autoBackupTriggerProvider).fireDebounced(
            reason: auswahl.fest
                ? 'Aus dem Auftragsbestand eingeplant'
                : 'An den Planungsvorschlag übergeben',
          );
      // Die Meldung samt Aktion auch dann, wenn der Bildschirm inzwischen
      // geschlossen wurde — der Messenger gehört zur App.
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 10),
          // Mit Aktion blieben Meldungen sonst stehen, bis jemand klickt.
          persist: false,
          content: Text(meldung),
          action: SnackBarAction(
            label: 'Datenblatt drucken',
            onPressed: () => druckeDatenblaetterMitMeldung(messenger, blatt),
          ),
        ),
      );
      if (!mounted) return;
      setState(() => _markiert.remove(nr));
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(e.message),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
            'Einplanen fehlgeschlagen — es wurde nichts angelegt. ($e)',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _plant = false);
    }
  }

  /// Hebt eine Vormerkung auf: Der Planungsauftrag wird gelöscht, seine
  /// Zeilen sind wieder offen.
  Future<void> _vormerkungAufheben(Vormerkung v) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final db = ref.read(databaseProvider);
    final termin = v.termin;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vormerkung aufheben?'),
        content: SizedBox(
          width: 460,
          child: Text(
            'Der Planungsauftrag über ${_kg(v.offenKg)} kg'
            '${termin == null ? '' : ' (spätestens ${_tagKurz(termin)})'} '
            'wird gelöscht. Seine Aufträge sind danach wieder offen und '
            'lassen sich neu bündeln. Was davon schon im Board steht, '
            'bleibt dort.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Aufheben'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await hebeVormerkungAuf(db: db, bedarfId: v.bedarfId);
      container.invalidate(auftragsbestandProvider);
      container.invalidate(bedarfProvider);
      container
          .read(autoBackupTriggerProvider)
          .fireDebounced(reason: 'Vormerkung aufgehoben');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text('Aufheben fehlgeschlagen. ($e)'),
        ),
      );
    }
  }

  // ── Datenblatt ───────────────────────────────────────────────────────

  /// Druckt das Datenblatt einer Vormerkung: der Teil des
  /// Planungsauftrags, der noch nicht im Board steht.
  Future<void> _datenblattVormerkung(Vormerkung v) {
    final db = ref.read(databaseProvider);
    return druckeDatenblaetterMitMeldung(
      ScaffoldMessenger.of(context),
      () => alsListe(datenblattFuerBedarf(db, v.bedarfId, nurOffen: true)),
    );
  }

  /// Druckt das Datenblatt einer Produktion der App.
  Future<void> _datenblattKette(ProduktionsZugang z) {
    final db = ref.read(databaseProvider);
    return druckeDatenblaetterMitMeldung(
      ScaffoldMessenger.of(context),
      () => alsListe(datenblattFuerKette(db, z.kettenId)),
    );
  }

  // ── Filtern und Sortieren ────────────────────────────────────────────

  List<AuftragsbestandZeile> _gefiltert(
    List<AuftragsbestandZeile> alle,
    Map<String, Set<String>> abteilungen,
  ) {
    final suche = _suche.text.trim().toLowerCase();
    final liste = alle.where((z) {
      if (_nurOffene && !z.handlungsbedarf) return false;
      final abteilung = _abteilung;
      if (abteilung != null &&
          !(abteilungen[z.artikel.artikelnummer]?.contains(abteilung) ??
              false)) {
        return false;
      }
      if (suche.isEmpty) return true;
      final a = z.artikel;
      if (a.artikelnummer.toLowerCase().contains(suche)) return true;
      if (a.bezeichnung.toLowerCase().contains(suche)) return true;
      if ((a.bezeichnung2 ?? '').toLowerCase().contains(suche)) return true;
      return z.positionen.any(
        (p) =>
            p.debitor.toLowerCase().contains(suche) ||
            p.beleg.toLowerCase().contains(suche),
      );
    }).toList();

    int nachNummer(AuftragsbestandZeile a, AuftragsbestandZeile b) =>
        a.artikel.artikelnummer.compareTo(b.artikel.artikelnummer);

    switch (_sortierung) {
      case _Sortierung.engpass:
        // Erst, was hier Arbeit macht — nach dem frühesten Tag, an dem
        // etwas zu bündeln ist oder zu spät kommt. Danach, was beim
        // Planungsvorschlag liegt oder gedeckt ist.
        liste.sort((a, b) {
          if (a.handlungsbedarf != b.handlungsbedarf) {
            return a.handlungsbedarf ? -1 : 1;
          }
          final x = a.deckung;
          final y = b.deckung;
          if (x.erledigt != y.erledigt) return x.erledigt ? 1 : -1;
          final ea = x.erledigt ? x.ersterEngpass : _handlungstag(x);
          final eb = y.erledigt ? y.ersterEngpass : _handlungstag(y);
          if (ea != null && eb != null) {
            final t = ea.compareTo(eb);
            if (t != 0) return t;
            return y.offenKg.compareTo(x.offenKg);
          }
          if (ea != null) return -1;
          if (eb != null) return 1;
          return nachNummer(a, b);
        });
      case _Sortierung.fehlmenge:
        liste.sort((a, b) {
          final f = b.deckung.offenKg.compareTo(a.deckung.offenKg);
          return f != 0 ? f : nachNummer(a, b);
        });
      case _Sortierung.auftrag:
        liste.sort((a, b) {
          final f = b.deckung.auftragKg.compareTo(a.deckung.auftragKg);
          return f != 0 ? f : nachNummer(a, b);
        });
      case _Sortierung.nummer:
        liste.sort(nachNummer);
    }
    return liste;
  }

  // ── Aufbau ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ansicht = ref.watch(auftragsbestandProvider);
    // null, solange die Artikel der App noch geladen werden — dann wird
    // nichts als „fehlt in der App" markiert, statt kurz alles.
    final appNummern = ref.watch(appArtikelnummernProvider).valueOrNull;
    final abteilungen = ref.watch(abteilungenJeArtikelProvider).valueOrNull ??
        const <String, Set<String>>{};
    final heute = ref.watch(heuteProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Auftragsbestand'),
        actions: [
          IconButton(
            onPressed: () => context.pushNamed('auftragsbestandAenderungen'),
            icon: const Icon(Icons.compare_arrows),
            tooltip: 'Änderungen seit dem vorigen Bericht',
          ),
          IconButton(
            onPressed: () => ref.invalidate(auftragsbestandProvider),
            icon: const Icon(Icons.refresh),
            tooltip: 'Neu rechnen — etwa nach Änderungen im Board',
          ),
          TextButton.icon(
            onPressed: _liest ? null : _einlesen,
            icon: const Icon(Icons.upload_file, size: 18),
            label: const Text('Auftragsbestand einlesen'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (_fehler != null)
                _Meldung(
                  text: _fehler!,
                  istFehler: true,
                  onSchliessen: () => setState(() => _fehler = null),
                ),
              if (_hinweise.isNotEmpty)
                _Meldung(
                  text: [
                    ..._hinweise.take(3),
                    if (_hinweise.length > 3)
                      '… und ${_hinweise.length - 3} weitere',
                  ].join('\n'),
                  istFehler: false,
                  onSchliessen: () =>
                      setState(() => _hinweise = const []),
                ),
              Expanded(
                child: ansicht.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Fehler: $e')),
                  data: (a) => a.leer
                      ? const _LeerHinweis()
                      : _inhalt(context, a, appNummern, abteilungen, heute),
                ),
              ),
            ],
          ),
          if (_liest) const _LeseSchleier(),
        ],
      ),
    );
  }

  Widget _inhalt(
    BuildContext context,
    AuftragsbestandAnsicht ansicht,
    Set<String>? appNummern,
    Map<String, Set<String>> abteilungen,
    DateTime heute,
  ) {
    final liste = _gefiltert(ansicht.zeilen, abteilungen);
    final fehlende = appNummern == null
        ? const <AuftragsbestandZeile>[]
        : [
            for (final z in ansicht.zeilen)
              if (!appNummern.contains(z.artikel.artikelnummer)) z,
          ];

    return Column(
      children: [
        _Kopf(ansicht: ansicht, heute: heute),
        if (ansicht.konflikte.isNotEmpty)
          _KonfliktBanner(
            konflikte: ansicht.konflikte,
            onPruefen: () => context.pushNamed('auftragsbestandAenderungen'),
          ),
        if (fehlende.isNotEmpty)
          _FehlendeBanner(
            anzahl: fehlende.length,
            onAnlegen: _legtAn ? null : () => _fehlendeAnlegen(fehlende),
          ),
        _filterLeiste(context, ansicht, abteilungen, liste.length),
        const Divider(height: 1),
        Expanded(
          child: liste.isEmpty
              ? Center(
                  child: Text(
                    'Keine Artikel passen zu den Filtern.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
                  itemCount: liste.length,
                  itemBuilder: (context, i) {
                    final z = liste[i];
                    final nr = z.artikel.artikelnummer;
                    final inApp = appNummern?.contains(nr) ?? true;
                    final markiert = _markiert[nr] ?? const <DateTime>{};
                    return _ArtikelKarte(
                      zeile: z,
                      inApp: inApp,
                      offen: _offen.contains(nr),
                      heute: heute,
                      markiert: markiert,
                      onMarkieren: inApp
                          ? (DateTime tag, bool an) => setState(() {
                                final auswahl = _markiert.putIfAbsent(
                                  nr,
                                  () => <DateTime>{},
                                );
                                if (an) {
                                  auswahl.add(tag);
                                } else {
                                  auswahl.remove(tag);
                                }
                                if (auswahl.isEmpty) _markiert.remove(nr);
                              })
                          : null,
                      onEinplanen: markiert.isEmpty || _plant
                          ? null
                          : () => _einplanen(z),
                      onAufheben: _vormerkungAufheben,
                      onDatenblattVormerkung: _datenblattVormerkung,
                      onDatenblattKette: _datenblattKette,
                      onPruefen: () =>
                          context.pushNamed('auftragsbestandAenderungen'),
                      onUmschalten: () => setState(() {
                        if (!_offen.remove(nr)) _offen.add(nr);
                      }),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _filterLeiste(
    BuildContext context,
    AuftragsbestandAnsicht ansicht,
    Map<String, Set<String>> abteilungen,
    int treffer,
  ) {
    final theme = Theme.of(context);

    // Artikel je Abteilung — gezählt gegen den ganzen Bestand, damit die
    // Zahl nicht bei jedem Tastendruck in der Suche springt.
    final anzahl = <String, int>{};
    for (final z in ansicht.zeilen) {
      for (final d
          in abteilungen[z.artikel.artikelnummer] ?? const <String>{}) {
        anzahl[d] = (anzahl[d] ?? 0) + 1;
      }
    }
    final offene = ansicht.zeilen.where((z) => z.handlungsbedarf).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 300,
                child: TextField(
                  controller: _suche,
                  decoration: const InputDecoration(
                    labelText: 'Suche (Nummer, Bezeichnung, Kunde, Beleg)',
                    prefixIcon: Icon(Icons.search, size: 18),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              SizedBox(
                width: 230,
                child: DropdownButtonFormField<String>(
                  initialValue: _abteilung,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Abteilung',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Alle')),
                    for (final a in Abteilung.values)
                      DropdownMenuItem(
                        value: a.dbValue,
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: a.farbe,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                '${a.anzeigeName} '
                                '(${anzahl[a.dbValue] ?? 0})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _abteilung = v),
                ),
              ),
              FilterChip(
                label: Text('Nur mit Handlungsbedarf ($offene)'),
                tooltip: 'Artikel, bei denen noch etwas zu bündeln ist, die '
                    'Produktion zu spät fertig wird oder ein verschobener '
                    'Auftrag zu klären ist. Was beim Planungsvorschlag '
                    'vorgemerkt ist, ist hier erledigt.',
                selected: _nurOffene,
                onSelected: (v) => setState(() => _nurOffene = v),
              ),
              SizedBox(
                width: 210,
                child: DropdownButtonFormField<_Sortierung>(
                  initialValue: _sortierung,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Sortierung',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  // Farbe ausdrücklich — ohne sie erbt der Text im hellen
                  // Modus Weiß (derselbe Fehler wie im Navision-Import).
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurface,
                  ),
                  items: [
                    for (final s in _Sortierung.values)
                      DropdownMenuItem(value: s, child: Text(s.label)),
                  ],
                  onChanged: (v) => setState(
                    () => _sortierung = v ?? _Sortierung.engpass,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$treffer von ${ansicht.zeilen.length} Artikeln',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Bausteine
// ═══════════════════════════════════════════════════════════════════════════

/// Grün für „gedeckt", passend zu hellem und dunklem Modus.
Color _gruen(ThemeData theme) => theme.brightness == Brightness.dark
    ? Colors.green.shade400
    : Colors.green.shade700;

/// Bernstein für „zu spät" und „knapp" — dunkel genug, um auf hellem
/// Grund lesbar zu bleiben.
Color _bernstein(ThemeData theme) => theme.brightness == Brightness.dark
    ? const Color(0xFFFBBF24)
    : const Color(0xFFB45309);

/// Blau für „beim Planungsvorschlag vorgemerkt": in Arbeit, aber noch
/// nicht im Board.
Color _blau(ThemeData theme) => theme.brightness == Brightness.dark
    ? const Color(0xFF60A5FA)
    : const Color(0xFF1D4ED8);

/// Lila für „verschoben": Die Planung hängt noch am alten Versandtag.
Color _lila(ThemeData theme) => theme.brightness == Brightness.dark
    ? const Color(0xFFC084FC)
    : const Color(0xFF7E22CE);

/// Erster Warenausgang, an dem hier etwas zu tun ist: noch zu bündeln
/// oder zu spät eingeplant.
DateTime? _handlungstag(ArtikelDeckung d) {
  final offen = d.ersterOffenTag;
  final spaet = d.ersterZuSpaet;
  if (offen == null) return spaet;
  if (spaet == null) return offen;
  return offen.isBefore(spaet) ? offen : spaet;
}

/// Stand, Zeitraum und Kennzahlen des eingelesenen Berichts.
class _Kopf extends StatelessWidget {
  const _Kopf({required this.ansicht, required this.heute});

  final AuftragsbestandAnsicht ansicht;
  final DateTime heute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final zeilen = ansicht.zeilen;
    final belege = <String>{};
    final kunden = <String>{};
    var auftragKg = 0.0;
    var lagerKg = 0.0;
    var planungKg = 0.0;
    var offenKg = 0.0;
    var vorgemerktKg = 0.0;
    var zuSpaetKg = 0.0;
    var offene = 0;
    for (final z in zeilen) {
      final d = z.deckung;
      belege.addAll(z.belege);
      kunden.addAll(z.kunden);
      auftragKg += d.auftragKg;
      lagerKg += d.ausLagerKg;
      planungKg += d.ausPlanungKg + d.zuSpaetKg;
      offenKg += d.offenKg;
      vorgemerktKg += d.vorgemerktKg;
      zuSpaetKg += d.zuSpaetKg;
      if (z.handlungsbedarf) offene++;
    }

    final stand = ansicht.stand;
    final von = ansicht.von;
    final bis = ansicht.bis;
    final importiert = ansicht.importiertAm;
    final zeile = [
      if (stand != null) 'Stand ${_datumLang(stand)}, ${_uhrzeit(stand)}',
      if (von != null && bis != null)
        'Warenausgang ${_datumKurz(von)}–${_datumLang(bis)}',
      if (importiert != null)
        'eingelesen ${_datumKurz(importiert)}, ${_uhrzeit(importiert)}',
    ].join(' · ');
    final berichtTag = ansicht.berichtTag;
    final veraltet = berichtTag != null && berichtTag.isBefore(heute);
    final grau = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(zeile, style: grau),
              if (veraltet)
                _Marke(
                  text: 'Bericht nicht von heute — frisch einlesen',
                  farbe: _bernstein(theme),
                ),
              TextButton.icon(
                onPressed: () => _zeigeRechenweg(context),
                icon: const Icon(Icons.help_outline, size: 16),
                label: const Text('So wird gerechnet'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _Kennzahl(wert: '${zeilen.length}', label: 'Artikel'),
              _Kennzahl(wert: '${belege.length}', label: 'Aufträge'),
              _Kennzahl(wert: '${kunden.length}', label: 'Kunden'),
              _Kennzahl(wert: '${_kg(auftragKg)} kg', label: 'bestellt'),
              _Kennzahl(wert: '${_kg(lagerKg)} kg', label: 'aus dem Lager'),
              _Kennzahl(
                wert: '${_kg(planungKg)} kg',
                label: 'aus Produktion',
              ),
              _Kennzahl(
                wert: '${_kg(offenKg)} kg',
                label: 'noch einzuplanen',
                farbe: offenKg >= 0.005 ? theme.colorScheme.error : null,
              ),
              if (vorgemerktKg >= 0.005)
                _Kennzahl(
                  wert: '${_kg(vorgemerktKg)} kg',
                  label: 'beim Planungsvorschlag',
                  farbe: _blau(theme),
                ),
              if (zuSpaetKg >= 0.005)
                _Kennzahl(
                  wert: '${_kg(zuSpaetKg)} kg',
                  label: 'zu spät eingeplant',
                  farbe: _bernstein(theme),
                ),
              _Kennzahl(
                wert: '$offene',
                label: 'Artikel mit Handlungsbedarf',
                farbe: offene > 0 ? theme.colorScheme.error : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const _rechenweg =
    'Je Artikel werden die Aufträge nach Warenausgang abgearbeitet, der '
    'früheste zuerst:\n\n'
    '1. Lager laut Bericht.\n'
    '2. Produktionen der App, die bis zum Versandtag fertig sind. Fertig '
    'heißt: der letzte Schritt der Kette im Board. Wird sie erst am '
    'Versandtag selbst fertig, zählt sie, ist aber knapp. Wurde eine '
    'Produktion über „Zur Planung hinzufügen" für bestimmte Aufträge '
    'angelegt, bekommen zuerst diese Aufträge ihre Ware.\n'
    '3. Produktionen, die erst nach dem Versandtag fertig werden, decken '
    'die Menge — aber zu spät.\n\n'
    'Was danach noch fehlt, ist einzuplanen. Termin ist der erste Tag, an '
    'dem es fehlt. Ist es an den Planungsvorschlag übergeben, ist es '
    'vorgemerkt — es fehlt noch, ist aber in Arbeit.\n\n'
    'Welche Produktionen mitzählen:\n'
    '• Eingeplant: letzter Schritt heute oder später.\n'
    '• Produziert am Tag des Berichts oder danach: im Lager des Berichts '
    'noch nicht enthalten, zählt dazu.\n'
    '• Vor dem Tag des Berichts produziert: Die App geht davon aus, dass '
    'Navision sie bis zum Bericht gebucht hat. Sie steckt im Lager und '
    'zählt nicht doppelt.\n\n'
    'Gerechnet wird mit der geplanten Fertigmenge, bei erfassten '
    'Produktionen mit der erfassten. Produktionen ohne Fertigmenge (in '
    'Rohware geplant, ohne bekannte Ausbeute) zählen nicht mit.\n\n'
    'Einplanen: Tage eines Artikels abhaken und „Zur Planung '
    'hinzufügen". Zwei Wege:\n'
    '• An den Planungsvorschlag übergeben (Standard): Es entsteht ein '
    'Planungsauftrag mit spätestem Produktionstag. Die Aufträge sind blau '
    'vorgemerkt, bis der Planungsvorschlag sie in einen Tag legt und der '
    'Tag übernommen wird. Er plant möglichst spät, aber nie nach dem '
    'Termin.\n'
    '• Fester Tag: Die Produktion kommt sofort ins Board, genau an diesem '
    'Tag. Der Planungsvorschlag plant drumherum.\n\n'
    'Eingeplante Aufträge werden grau und zeigen, wann produziert wird. '
    'Wird eine Produktion im Board gelöscht, ist ein übergebener Auftrag '
    'wieder vorgemerkt, ein fest eingeplanter wieder offen. Wird ein '
    'Planungsauftrag gelöscht — hier über „Vormerkung aufheben" oder in '
    'der Bedarfsliste —, sind seine Aufträge wieder offen.\n\n'
    'Nach jedem Einlesen vergleicht die App den Bericht mit dem vorigen '
    '(Symbol oben rechts): neu, mehr, weniger, verschoben, entfallen. '
    'Hängt Planung an einem Auftrag, der sich geändert hat, erscheint '
    'oben ein roter Hinweis — dort lässt sie sich anpassen.\n\n'
    'Verschobene Aufträge, deren Planung noch am alten Tag hängt, sind '
    'lila markiert. Gerechnet wird schon mit dem neuen Tag, gebündelt '
    'werden können sie aber erst, wenn die Verschiebung umgehängt oder '
    'verworfen ist — sonst würde dieselbe Menge zweimal eingeplant.';

Future<void> _zeigeRechenweg(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('So wird gerechnet'),
      content: const SizedBox(
        width: 520,
        child: SingleChildScrollView(child: Text(_rechenweg)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Schließen'),
        ),
      ],
    ),
  );
}

class _Kennzahl extends StatelessWidget {
  const _Kennzahl({
    required this.wert,
    required this.label,
    this.farbe,
  });

  final String wert;
  final String label;

  /// Hervorhebung des Werts; ohne Angabe die normale Textfarbe.
  final Color? farbe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            wert,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: farbe ?? theme.colorScheme.onSurface,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Hinweis über der Liste: Artikel aus dem Bericht, die es in der App
/// nicht gibt — für sie lässt sich nichts einplanen.
class _FehlendeBanner extends StatelessWidget {
  const _FehlendeBanner({required this.anzahl, required this.onAnlegen});

  final int anzahl;
  final VoidCallback? onAnlegen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final farbe = theme.colorScheme.onTertiaryContainer;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.playlist_add, size: 20, color: farbe),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              anzahl == 1
                  ? '1 Artikel aus dem Auftragsbestand gibt es in der App '
                      'noch nicht. Einplanen lässt er sich erst mit '
                      'Artikelmaske.'
                  : '$anzahl Artikel aus dem Auftragsbestand gibt es in der '
                      'App noch nicht. Einplanen lassen sie sich erst mit '
                      'Artikelmaske.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: farbe,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: onAnlegen,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Fehlende anlegen …'),
          ),
        ],
      ),
    );
  }
}

/// Hinweis über der Liste: Planung, die nicht mehr zum Bericht passt.
/// Vor dem nächsten Bündeln zu prüfen — ein verschobener Auftrag stünde
/// sonst am neuen Tag als offen da und würde ein zweites Mal eingeplant.
class _KonfliktBanner extends StatelessWidget {
  const _KonfliktBanner({required this.konflikte, required this.onPruefen});

  final List<PlanungsKonflikt> konflikte;
  final VoidCallback onPruefen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final farbe = theme.colorScheme.onErrorContainer;
    final n = konflikte.length;
    final arten = [
      for (final art in PruefArt.values)
        if (konflikte.any((k) => k.art == art)) art.label,
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.rule, size: 20, color: farbe),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${n == 1 ? 'An 1 Auftrag hängt' : 'An $n Aufträgen hängt'} '
              'Planung, die nicht mehr zum Bericht passt '
              '(${arten.join(', ')}). Erst prüfen, dann neu bündeln — '
              'sonst wird doppelt oder zu viel produziert.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: farbe,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: onPruefen,
            icon: const Icon(Icons.compare_arrows, size: 18),
            label: const Text('Prüfen …'),
          ),
        ],
      ),
    );
  }
}

/// Rückfrage beim Einlesen: Der Bericht sieht gefiltert, veraltet oder
/// verrutscht aus.
class _UmfangsDialog extends StatelessWidget {
  const _UmfangsDialog({required this.hinweise});

  final List<UmfangsHinweis> hinweise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: _bernstein(theme)),
      title: const Text('Diesen Bericht übernehmen?'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final h in hinweise)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  '),
                      Expanded(child: Text(h.text)),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                'Der Bericht ersetzt den bisherigen vollständig. Was darin '
                'fehlt, weil er gefiltert ist, gilt in der App als nicht '
                'mehr offen: Das Lager wird nur den gezeigten Aufträgen '
                'zugeteilt, und die Planungsprüfung schlägt vor, die '
                'Planung der fehlenden herauszunehmen.\n\n'
                'Am sichersten: in Navision immer mit demselben Grundfilter '
                'aufrufen — alle Kunden, alle Artikel, nur den Zeitraum '
                'anpassen.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Trotzdem übernehmen'),
        ),
      ],
    );
  }
}

/// Auswahl, welche fehlenden Artikel angelegt werden. Vorausgewählt sind
/// die, bei denen das Lager nicht reicht — für die übrigen gibt es gerade
/// nichts zu produzieren, und jede Hülle will später gepflegt werden.
class _FehlendeDialog extends StatefulWidget {
  const _FehlendeDialog({required this.zeilen});

  final List<AuftragsbestandZeile> zeilen;

  @override
  State<_FehlendeDialog> createState() => _FehlendeDialogState();
}

class _FehlendeDialogState extends State<_FehlendeDialog> {
  late final Set<String> _gewaehlt = {
    for (final z in widget.zeilen)
      if (!z.deckung.gedeckt) z.artikel.artikelnummer,
  };

  void _waehle(bool Function(AuftragsbestandZeile z) passt) {
    setState(() {
      _gewaehlt
        ..clear()
        ..addAll([
          for (final z in widget.zeilen)
            if (passt(z)) z.artikel.artikelnummer,
        ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final zeilen = widget.zeilen;
    final mitFehlmenge = zeilen.where((z) => !z.deckung.gedeckt).length;
    final anzahl = _gewaehlt.length;

    return AlertDialog(
      title: const Text('Fehlende Artikel anlegen'),
      content: SizedBox(
        width: 580,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Die gewählten Artikel werden mit Nummer und Bezeichnung aus '
              'dem Auftragsbestand angelegt und als „nicht eingepflegt" '
              'markiert. Prozessschritte und Stammdaten trägst du danach in '
              'der Artikelliste nach. Gab es einen Artikel früher schon und '
              'wurde er gelöscht, wird er wieder aktiviert.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              children: [
                TextButton(
                  onPressed: () => _waehle((z) => !z.deckung.gedeckt),
                  child: Text('Nur wo das Lager nicht reicht ($mitFehlmenge)'),
                ),
                TextButton(
                  onPressed: () => _waehle((_) => true),
                  child: Text('Alle (${zeilen.length})'),
                ),
                TextButton(
                  onPressed: () => _waehle((_) => false),
                  child: const Text('Keine'),
                ),
              ],
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: zeilen.length,
                itemBuilder: (context, i) {
                  final z = zeilen[i];
                  final nr = z.artikel.artikelnummer;
                  final d = z.deckung;
                  final tag = d.ersterFehltag;
                  final status = d.gedeckt || tag == null
                      ? 'Lager reicht'
                      : 'fehlt ${_kg(d.fehltKg)} kg ab ${_tagKurz(tag)}';
                  return CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _gewaehlt.contains(nr),
                    onChanged: (v) => setState(() {
                      if (v ?? false) {
                        _gewaehlt.add(nr);
                      } else {
                        _gewaehlt.remove(nr);
                      }
                    }),
                    title: Text(
                      '$nr  ${z.artikel.bezeichnung}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '$status · ${_kg(d.auftragKg)} kg bestellt',
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: anzahl == 0
              ? null
              : () => Navigator.of(context).pop(Set<String>.of(_gewaehlt)),
          child: Text(
            anzahl == 1 ? '1 Artikel anlegen' : '$anzahl Artikel anlegen',
          ),
        ),
      ],
    );
  }
}

/// Was im Dialog „Zur Planung hinzufügen" gewählt wurde: Menge
/// Fertigware, Tag, und ob der Tag fest ist oder nur der späteste.
typedef _Wahl = ({double fertigKg, DateTime tag, bool fest});

/// Menge, Tag und Weg für die abgehakten Tage eines Artikels.
///
/// Vorgeschlagen ist genau das, was an diesen Tagen noch offen ist, und
/// als Tag der Arbeitstag vor dem ersten Versand. Beides lässt sich ändern
/// — etwa auf eine volle Charge aufrunden.
///
/// Standard ist die Übergabe an den Planungsvorschlag: Der Tag ist dann
/// der späteste Produktionstag, der Vorschlag sucht den passenden Tag
/// davor. „Fester Tag" legt die Produktion sofort ins Board.
class _EinplanenDialog extends StatefulWidget {
  const _EinplanenDialog({
    required this.artikel,
    required this.tage,
    required this.offenKg,
    required this.ausbeute,
    required this.vorschlag,
    required this.heute,
  });

  final AuftragsArtikel artikel;

  /// Die abgehakten Versandtage, frühester zuerst.
  final List<TagesDeckung> tage;

  /// Was an diesen Tagen noch offen ist.
  final double offenKg;
  final Ausbeute ausbeute;
  final DateTime vorschlag;
  final DateTime heute;

  @override
  State<_EinplanenDialog> createState() => _EinplanenDialogState();
}

class _EinplanenDialogState extends State<_EinplanenDialog> {
  late final TextEditingController _menge = TextEditingController(
    text: widget.offenKg.ceil().toString(),
  );
  late DateTime _tag = widget.vorschlag;

  /// Fester Tag statt Übergabe an den Planungsvorschlag.
  bool _fest = false;

  @override
  void dispose() {
    _menge.dispose();
    super.dispose();
  }

  double? get _fertigKg {
    final v = double.tryParse(_menge.text.trim().replaceAll(',', '.'));
    return (v != null && v.isFinite && v > 0) ? v : null;
  }

  Future<void> _waehleTag() async {
    final gewaehlt = await showDatePicker(
      context: context,
      initialDate: _tag,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (gewaehlt == null || !mounted) return;
    setState(
      () => _tag = DateTime(gewaehlt.year, gewaehlt.month, gewaehlt.day),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final klein = theme.textTheme.bodySmall;
    final grau = klein?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final fertig = _fertigKg;
    final a = widget.ausbeute;
    final ersterVersand = widget.tage.first.tag;
    final zuSpaet = _tag.isAfter(ersterVersand);
    final amVersandtag = _tag.isAtSameMomentAs(ersterVersand);
    final tagText = _fest ? 'Produktionstag' : 'Spätester Produktionstag';
    // Der Planungsvorschlag plant ab morgen. Muss es heute laufen, geht
    // das nur fest.
    final nurFest = !_fest && !_tag.isAfter(widget.heute);

    final String rohware;
    if (fertig == null) {
      rohware = '';
    } else if (!a.bekannt) {
      rohware = 'Ausbeute unbekannt — gerechnet ohne Verlust';
    } else {
      final quelle = switch (a.quelle) {
        AusbeuteQuelle.historie => 'Ø der erfassten Produktionen',
        AusbeuteQuelle.artikel => 'Gesamtausbeute des Artikels',
        AusbeuteQuelle.schritte => 'Ausbeute der Schritte',
        AusbeuteQuelle.eingabe || AusbeuteQuelle.keine => '',
      };
      final prozent = (a.faktor * 100).toStringAsFixed(1).replaceAll('.', ',');
      rohware = '≈ ${_kg(a.rohAusFertig(fertig))} kg Rohware · Ausbeute '
          '$prozent %${quelle.isEmpty ? '' : ' ($quelle)'}';
    }

    return AlertDialog(
      title: Text(
        '${widget.artikel.artikelnummer}  ${widget.artikel.bezeichnung}',
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Abgehakte Versandtage',
                style: klein?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              for (final t in widget.tage)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 92,
                        child: Text(_tagKurz(t.tag), style: klein),
                      ),
                      Expanded(
                        child: Text(
                          '${t.zeilen.length} '
                          '${t.zeilen.length == 1 ? 'Auftrag' : 'Aufträge'}'
                          ' · ${_kg(t.kg)} kg',
                          style: grau,
                        ),
                      ),
                      Text(
                        'offen ${_kg(t.einplanbarKg)} kg',
                        style: klein?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.auto_awesome_rounded, size: 18),
                    label: Text('An Planungsvorschlag'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.event, size: 18),
                    label: Text('Fester Tag'),
                  ),
                ],
                selected: {_fest},
                onSelectionChanged: (s) => setState(() => _fest = s.first),
                showSelectedIcon: false,
              ),
              const SizedBox(height: 6),
              Text(
                _fest
                    ? 'Die Produktion kommt sofort ins Board, genau an diesem '
                        'Tag — für Ware, die an diesem Tag laufen muss. Der '
                        'Planungsvorschlag plant drumherum.'
                    : 'Der Planungsvorschlag legt die Produktion mit den '
                        'übrigen Bedarfen in die Woche: so spät wie möglich, '
                        'aber nie nach dem spätesten Produktionstag. Bis '
                        'dahin sind die Aufträge hier vorgemerkt.',
                style: grau,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _menge,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Fertigware einplanen',
                  suffixText: 'kg',
                  helperText: 'Vorschlag: was an diesen Tagen noch offen ist '
                      '(${_kg(widget.offenKg)} kg)',
                  border: const OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              ),
              if (rohware.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(rohware, style: grau),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$tagText: ${_tagKurz(_tag)}${_tag.year}',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _waehleTag,
                    icon: const Icon(Icons.calendar_month, size: 18),
                    label: const Text('Ändern'),
                  ),
                ],
              ),
              if (zuSpaet)
                Text(
                  'Zu spät für den ersten Versandtag '
                  '(${_tagKurz(ersterVersand)}).',
                  style: klein?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: _bernstein(theme),
                  ),
                )
              else if (amVersandtag)
                Text(
                  'Knapp: Produktion am ersten Versandtag selbst.',
                  style: klein?.copyWith(color: _bernstein(theme)),
                ),
              if (nurFest)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Der Planungsvorschlag plant ab morgen. Muss es heute '
                    'laufen, „Fester Tag" wählen.',
                    style: klein?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: _bernstein(theme),
                    ),
                  ),
                ),
              if (_fest) ...[
                const SizedBox(height: 8),
                Text(
                  'Alle Abteilungen kommen zunächst auf diesen Tag. '
                  'Einzelne Schritte kannst du danach im Board verschieben.',
                  style: grau,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton.icon(
          onPressed: fertig == null
              ? null
              : () => Navigator.of(context)
                  .pop((fertigKg: fertig, tag: _tag, fest: _fest)),
          icon: Icon(
            _fest ? Icons.event_available : Icons.auto_awesome_rounded,
            size: 18,
          ),
          label: Text(_fest ? 'Einplanen' : 'Übergeben'),
        ),
      ],
    );
  }
}

/// Ein Artikel: Kopfzeile mit Mengen und Status, aufgeklappt die Aufträge
/// nach Warenausgang und die Produktionen der App.
class _ArtikelKarte extends StatelessWidget {
  const _ArtikelKarte({
    required this.zeile,
    required this.inApp,
    required this.offen,
    required this.heute,
    required this.markiert,
    required this.onMarkieren,
    required this.onEinplanen,
    required this.onAufheben,
    required this.onDatenblattVormerkung,
    required this.onDatenblattKette,
    required this.onPruefen,
    required this.onUmschalten,
  });

  final AuftragsbestandZeile zeile;
  final bool inApp;
  final bool offen;
  final DateTime heute;
  final Set<DateTime> markiert;
  final void Function(DateTime tag, bool an)? onMarkieren;
  final VoidCallback? onEinplanen;
  final void Function(Vormerkung v) onAufheben;
  final void Function(Vormerkung v) onDatenblattVormerkung;
  final void Function(ProduktionsZugang z) onDatenblattKette;

  /// Öffnet die Änderungsansicht — dort wird eine Verschiebung geklärt.
  final VoidCallback onPruefen;

  final VoidCallback onUmschalten;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = zeile.artikel;
    final d = zeile.deckung;
    final offenAb = d.ersterOffenTag;
    final zuSpaetAb = d.ersterZuSpaet;

    final Color akzent;
    final String status;
    if (offenAb != null) {
      akzent = theme.colorScheme.error;
      status = 'fehlt ${_kg(d.offenKg)} kg ab ${_tagKurz(offenAb)}';
    } else if (zuSpaetAb != null) {
      akzent = _bernstein(theme);
      status = 'zu spät eingeplant · ${_tagKurz(zuSpaetAb)}';
    } else if (d.vorgemerktKg >= 0.005) {
      akzent = _blau(theme);
      final termin = d.fruehesterVormerkTermin;
      status = termin == null
          ? 'beim Planungsvorschlag'
          : 'beim Planungsvorschlag · spätestens ${_tagKurz(termin)}';
    } else if (d.lagerReicht) {
      akzent = _gruen(theme);
      status = 'Lager reicht';
    } else {
      akzent = _gruen(theme);
      status = 'gedeckt mit Produktion';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        // Farbiger Rand links: rot = fehlt, bernstein = zu spät, blau =
        // beim Planungsvorschlag vorgemerkt, grün = rechtzeitig gedeckt.
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: akzent, width: 4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: onUmschalten,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Row(
                  children: [
                    Expanded(child: _kopfText(theme, a, d)),
                    const SizedBox(width: 10),
                    _Marke(text: status, farbe: akzent, kraeftig: true),
                    const SizedBox(width: 4),
                    Icon(
                      offen ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            if (offen)
              _Details(
                deckung: d,
                zugaenge: zeile.zugaenge,
                vormerkungen: zeile.vormerkungen,
                verschoben: zeile.verschoben,
                heute: heute,
                inApp: inApp,
                markiert: markiert,
                onMarkieren: onMarkieren,
                onEinplanen: onEinplanen,
                onAufheben: onAufheben,
                onDatenblattVormerkung: onDatenblattVormerkung,
                onDatenblattKette: onDatenblattKette,
                onPruefen: onPruefen,
              ),
          ],
        ),
      ),
    );
  }

  Widget _kopfText(ThemeData theme, AuftragsArtikel a, ArtikelDeckung d) {
    final auftraege = zeile.belege.length;
    final tage = d.tage.length;
    final ohneMenge = zeile.ohneMenge;
    // Vorgemerkt UND noch etwas offen oder zu spät: Der Status rechts
    // zeigt das Dringendere, die Vormerkung steht deshalb hier.
    final vorgemerktNebenbei = d.vorgemerktKg >= 0.005 && !d.erledigt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${a.artikelnummer}  ${a.bezeichnung}',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (!inApp)
              _Marke(
                text: 'nicht in der App',
                farbe: theme.colorScheme.onSurfaceVariant,
              ),
            if (ohneMenge > 0)
              _Marke(
                text: ohneMenge == 1
                    ? '1 Planung ohne Fertigmenge'
                    : '$ohneMenge Planungen ohne Fertigmenge',
                farbe: _bernstein(theme),
              ),
            if (vorgemerktNebenbei)
              _Marke(
                text: '${_kg(d.vorgemerktKg)} kg beim Planungsvorschlag',
                farbe: _blau(theme),
              ),
            if (zeile.verschoben.isNotEmpty)
              Tooltip(
                message: 'Ein Auftrag steht an einem neuen Versandtag, seine '
                    'Planung hängt noch am alten. Bis das geklärt ist, lässt '
                    'er sich nicht bündeln.',
                child: _Marke(
                  text: zeile.verschoben.length == 1
                      ? '1 Auftrag verschoben'
                      : '${zeile.verschoben.length} Aufträge verschoben',
                  farbe: _lila(theme),
                ),
              ),
          ],
        ),
        if ((a.bezeichnung2 ?? '').isNotEmpty)
          Text(
            a.bezeichnung2!,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        const SizedBox(height: 4),
        Text(
          [
            'Aufträge ${_kg(d.auftragKg)} kg',
            'Lager ${_kg(d.lagerKg)} kg',
            if (d.zugangKg >= 0.005) 'Produktion ${_kg(d.zugangKg)} kg',
            '$auftraege ${auftraege == 1 ? 'Auftrag' : 'Aufträge'} an '
                '$tage ${tage == 1 ? 'Tag' : 'Tagen'}',
          ].join(' · '),
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// Aufgeklappt: je Warenausgangstag Summe und Deckung samt Aufträgen,
/// darunter die Vormerkungen und die Produktionen der App für diesen
/// Artikel.
///
/// Tage, an denen noch etwas offen ist, lassen sich abhaken und gemeinsam
/// einplanen. Zeilen, für die schon eine Produktion eingeplant ist, sind
/// grau und zeigen, wann; vorgemerkte zeigen blau, bis wann sie spätestens
/// produziert werden. Verschobene Aufträge, deren Planung noch am alten
/// Tag hängt, sind lila markiert und gesperrt.
class _Details extends StatelessWidget {
  const _Details({
    required this.deckung,
    required this.zugaenge,
    required this.vormerkungen,
    required this.verschoben,
    required this.heute,
    required this.inApp,
    required this.markiert,
    required this.onMarkieren,
    required this.onEinplanen,
    required this.onAufheben,
    required this.onDatenblattVormerkung,
    required this.onDatenblattKette,
    required this.onPruefen,
  });

  final ArtikelDeckung deckung;
  final List<ProduktionsZugang> zugaenge;
  final List<Vormerkung> vormerkungen;

  /// Schlüssel der Zeile am neuen Tag → Konflikt (siehe
  /// [AuftragsbestandZeile.verschoben]).
  final Map<String, PlanungsKonflikt> verschoben;

  final DateTime heute;
  final bool inApp;
  final Set<DateTime> markiert;

  /// null, wenn sich nichts abhaken lässt (Artikel nicht in der App).
  final void Function(DateTime tag, bool an)? onMarkieren;

  /// null, solange nichts abgehakt ist oder gerade eingeplant wird.
  final VoidCallback? onEinplanen;

  final void Function(Vormerkung v) onAufheben;
  final void Function(Vormerkung v) onDatenblattVormerkung;
  final void Function(ProduktionsZugang z) onDatenblattKette;
  final VoidCallback onPruefen;

  /// Breite der Spalte mit dem Haken und der mit dem Tag — die Aufträge
  /// darunter rücken um beide ein.
  static const double _hakenBreite = 36;
  static const double _tagBreite = 92;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final klein = theme.textTheme.bodySmall;
    final grau = klein?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final blass = klein?.copyWith(
      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
    );
    final rot = theme.colorScheme.error;
    final bernstein = _bernstein(theme);
    final gruen = _gruen(theme);
    final blau = _blau(theme);
    final lila = _lila(theme);
    final markieren = onMarkieren;

    final markierteTage = [
      for (final t in deckung.tage)
        if (markiert.contains(t.tag) && t.einplanbar) t,
    ];
    final offenMarkiert =
        markierteTage.fold<double>(0, (s, t) => s + t.einplanbarKg);

    Widget haken(TagesDeckung t) {
      if (markieren != null && t.einplanbar) {
        return Checkbox(
          value: markiert.contains(t.tag),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onChanged: (v) => markieren(t.tag, v ?? false),
        );
      }
      if (t.gesperrtKg >= 0.005) {
        return Tooltip(
          message: 'Gesperrt: ein verschobener Auftrag, dessen Planung noch '
              'am alten Tag hängt. Erst in „Änderungen" umhängen oder '
              'verwerfen, dann bündeln.',
          child: Icon(Icons.lock_outline, size: 18, color: lila),
        );
      }
      if (t.eingeplantIn.isNotEmpty) {
        return Tooltip(
          message: 'Eingeplant ${_geplantText(t.eingeplantIn)}',
          child: Icon(Icons.event_available, size: 18, color: gruen),
        );
      }
      if (t.vorgemerktIn.isNotEmpty) {
        return Tooltip(
          message: 'Beim Planungsvorschlag vorgemerkt'
              '${_terminText(t.vorgemerktIn)}',
          child: Icon(Icons.schedule_rounded, size: 18, color: blau),
        );
      }
      return const SizedBox.shrink();
    }

    Widget status(TagesDeckung t) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (t.offenKg >= 0.005)
            Text(
              'fehlt ${_kg(t.offenKg)} kg',
              textAlign: TextAlign.right,
              style: klein?.copyWith(fontWeight: FontWeight.w700, color: rot),
            ),
          if (t.gesperrtKg >= 0.005)
            Text(
              'davon gesperrt ${_kg(t.gesperrtKg)} kg',
              textAlign: TextAlign.right,
              style: klein?.copyWith(color: lila),
            ),
          if (t.vorgemerktKg >= 0.005)
            Text(
              'vorgemerkt ${_kg(t.vorgemerktKg)} kg',
              textAlign: TextAlign.right,
              style: klein?.copyWith(fontWeight: FontWeight.w700, color: blau),
            ),
          if (t.zuSpaetKg >= 0.005) ...[
            Text(
              'zu spät ${_kg(t.zuSpaetKg)} kg',
              textAlign: TextAlign.right,
              style: klein?.copyWith(
                fontWeight: FontWeight.w700,
                color: bernstein,
              ),
            ),
            if (t.zuSpaetBis != null)
              Text(
                'fertig erst ${_tagKurz(t.zuSpaetBis!)}',
                textAlign: TextAlign.right,
                style: grau,
              ),
          ],
          if (!t.offen)
            Text(
              t.eingeplantIn.isEmpty ? '—' : 'eingeplant',
              textAlign: TextAlign.right,
              style: t.eingeplantIn.isEmpty
                  ? klein
                  : klein?.copyWith(fontWeight: FontWeight.w700, color: gruen),
            ),
        ],
      );
    }

    Widget zeile(ZeilenDeckung z) {
      final p = z.position;
      // Grau heißt: eingeplant oder vorgemerkt und damit hier erledigt.
      // Fehlt trotzdem noch etwas — etwa weil der Kunde nachbestellt
      // hat —, bleibt die Zeile normal, damit der Rest auffällt.
      final stil = (z.geplant || z.vorgemerkt) && z.erledigt ? blass : grau;
      final umzug = verschoben[z.schluessel];
      final unsicher = umzug != null && !umzug.sicher
          ? ' Ob es derselbe Auftrag ist, lässt sich nicht sicher sagen.'
          : '';
      return Padding(
        padding: const EdgeInsets.only(left: _hakenBreite + _tagBreite, top: 1),
        child: Row(
          children: [
            SizedBox(width: 90, child: Text(p.beleg, style: stil)),
            Expanded(
              child: Text(
                p.debitor,
                style: stil,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (umzug != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Tooltip(
                  message: 'Stand vorher am ${_tagKurz(umzug.warenausgang)}. '
                      'Die Planung hängt noch am alten Tag — in „Änderungen" '
                      'umhängen oder verwerfen. Bis dahin lässt sich der '
                      'Auftrag nicht bündeln.$unsicher',
                  child: InkWell(
                    onTap: onPruefen,
                    borderRadius: BorderRadius.circular(6),
                    child: _Marke(
                      text: 'verschoben vom ${_tagKurz(umzug.warenausgang)}',
                      farbe: lila,
                      kraeftig: true,
                    ),
                  ),
                ),
              ),
            if (z.geplant)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _Marke(
                  text: 'geplant ${_geplantText(z.eingeplantIn)}',
                  farbe: gruen,
                ),
              ),
            if (z.vorgemerkt)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Tooltip(
                  message: 'An den Planungsvorschlag übergeben — er legt '
                      'die Produktion in einen Tag, nie nach dem Termin.',
                  child: _Marke(
                    text: 'vorgemerkt${_terminText(z.vorgemerktIn)}',
                    farbe: blau,
                  ),
                ),
              ),
            Text('${_zahl(p.menge)} ${p.einheit ?? ''}', style: stil),
            SizedBox(
              width: 110,
              child: Text(
                '${_kg(p.kg)} kg',
                textAlign: TextAlign.right,
                style: stil,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!inApp)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 2, 0, 4),
              child: Text(
                'Diesen Artikel gibt es in der App noch nicht. Erst über '
                '„Fehlende anlegen …" anlegen und die Schritte pflegen, dann '
                'lässt er sich einplanen.',
                style: grau,
              ),
            )
          else if (deckung.tage.any((t) => t.einplanbar))
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 2, 0, 4),
              child: Text(
                'Tage abhaken, die zusammen produziert werden sollen, dann '
                '„Zur Planung hinzufügen".',
                style: grau,
              ),
            ),
          for (final t in deckung.tage) ...[
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 2),
              child: Row(
                children: [
                  SizedBox(width: _hakenBreite, child: haken(t)),
                  SizedBox(
                    width: _tagBreite,
                    child: Text(
                      _tagKurz(t.tag),
                      style: klein?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (t.tag.isBefore(heute))
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _Marke(text: 'überfällig', farbe: rot),
                    ),
                  Expanded(
                    child: Text(
                      '${t.zeilen.length} '
                      '${t.zeilen.length == 1 ? 'Auftrag' : 'Aufträge'}'
                      ' · ${_kg(t.kg)} kg',
                      style: klein?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text('Lager ${_kg(t.ausLagerKg)} kg', style: grau),
                  if (t.ausPlanungKg >= 0.005) ...[
                    const SizedBox(width: 12),
                    Text(
                      'Produktion ${_kg(t.ausPlanungKg)} kg',
                      style: grau,
                    ),
                  ],
                  if (t.knappKg >= 0.005) ...[
                    const SizedBox(width: 6),
                    Tooltip(
                      message: '${_kg(t.knappKg)} kg werden erst am '
                          'Versandtag selbst fertig',
                      child: _Marke(text: 'knapp', farbe: bernstein),
                    ),
                  ],
                  const SizedBox(width: 12),
                  SizedBox(width: 150, child: status(t)),
                ],
              ),
            ),
            for (final z in t.zeilen) zeile(z),
          ],
          if (markierteTage.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${markierteTage.length} '
                      '${markierteTage.length == 1 ? 'Tag' : 'Tage'} '
                      'markiert · fehlen ${_kg(offenMarkiert)} kg',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: onEinplanen,
                    icon: const Icon(Icons.playlist_add, size: 18),
                    label: const Text('Zur Planung hinzufügen'),
                  ),
                ],
              ),
            ),
          ],
          if (vormerkungen.isNotEmpty) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                'Beim Planungsvorschlag vorgemerkt — spätester '
                'Produktionstag',
                style: klein?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            for (final v in vormerkungen)
              _VormerkungZeile(
                vormerkung: v,
                onAufheben: () => onAufheben(v),
                onDatenblatt: () => onDatenblattVormerkung(v),
              ),
          ],
          if (zugaenge.isNotEmpty) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                'Produktionen in der App — nach Tag der Fertigstellung',
                style: klein?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            for (final z in zugaenge)
              _ZugangZeile(
                zugang: z,
                onDatenblatt: () => onDatenblattKette(z),
              ),
          ],
          if (deckung.ueberschussKg >= 0.005)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 6),
              child: Text(
                '${_kg(deckung.ueberschussKg)} kg davon brauchen diese '
                'Aufträge nicht — Ware fürs Lager oder für Aufträge nach '
                'dem Berichtszeitraum.',
                style: grau,
              ),
            ),
        ],
      ),
    );
  }
}

/// „ · spätestens Mi 01.10." — der früheste Termin der Planungsaufträge,
/// leer ohne Termin.
String _terminText(List<Vormerkung> vormerkungen) {
  DateTime? frueh;
  for (final v in vormerkungen) {
    final t = v.termin;
    if (t != null && (frueh == null || t.isBefore(frueh))) frueh = t;
  }
  return frueh == null ? '' : ' · spätestens ${_tagKurz(frueh)}';
}

/// Ein offener Planungsauftrag: bis wann, für welche Aufträge, wie viel —
/// und der Knopf, ihn aufzuheben.
class _VormerkungZeile extends StatelessWidget {
  const _VormerkungZeile({
    required this.vormerkung,
    required this.onAufheben,
    required this.onDatenblatt,
  });

  final Vormerkung vormerkung;
  final VoidCallback onAufheben;
  final VoidCallback onDatenblatt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = vormerkung;
    final stil = theme.textTheme.bodySmall;
    final termin = v.termin;

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              termin == null ? 'ohne Termin' : _tagKurz(termin),
              style: stil?.copyWith(
                fontWeight: FontWeight.w700,
                color: _blau(theme),
              ),
            ),
          ),
          Expanded(
            child: Text(
              beschreibeBezuege(v.bezuege),
              style: stil,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              '${_kg(v.offenKg)} kg',
              textAlign: TextAlign.right,
              style: stil?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            onPressed: onDatenblatt,
            icon: const Icon(Icons.print_outlined, size: 16),
            tooltip: 'Datenblatt drucken — Artikel, Menge und Aufträge',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: onAufheben,
            icon: const Icon(Icons.close, size: 16),
            tooltip: 'Vormerkung aufheben — die Aufträge sind dann wieder '
                'offen',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

/// „Mi 01.10." oder „Mi 01.10.–Do 02.10." je Produktion, durch Komma
/// getrennt.
String _geplantText(List<ProduktionsZugang> produktionen) {
  return produktionen.map((p) {
    final von = p.beginn;
    final bis = p.fertigAm;
    return von.isAtSameMomentAs(bis)
        ? _tagKurz(von)
        : '${_tagKurz(von)}–${_tagKurz(bis)}';
  }).join(', ');
}

/// Eine Produktion der App: wann fertig, wie viel, und ob sie mitzählt.
class _ZugangZeile extends StatelessWidget {
  const _ZugangZeile({required this.zugang, required this.onDatenblatt});

  final ProduktionsZugang zugang;
  final VoidCallback onDatenblatt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final z = zugang;
    final zaehlt = z.zaehlt;
    final farbe = zaehlt
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75);
    final stil = theme.textTheme.bodySmall?.copyWith(color: farbe);

    final art = z.kg == null
        ? 'Menge unbekannt — ohne Fertigmenge geplant, zählt nicht mit'
        : switch (z.art) {
            ZugangsArt.eingeplant =>
              z.erfasst ? 'eingeplant · schon erfasst' : 'eingeplant',
            ZugangsArt.nachBericht =>
              'produziert, im Lager des Berichts noch nicht enthalten',
            ZugangsArt.imLager =>
              'vor dem Bericht produziert — steckt im Lager, zählt nicht '
                  'doppelt',
          };
    final n = z.bezuege.length;
    final fuer = n == 0
        ? ''
        : ' · für ${n == 1 ? '1 Auftragszeile' : '$n Auftragszeilen'}';
    final text = '$art$fuer';

    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(_tagKurz(z.fertigAm), style: stil),
          ),
          Expanded(child: Text(text, style: stil)),
          SizedBox(
            width: 110,
            child: Text(
              z.kg == null ? '—' : '${_kg(z.kg!)} kg',
              textAlign: TextAlign.right,
              style: stil?.copyWith(
                fontWeight: zaehlt ? FontWeight.w700 : FontWeight.w400,
                decoration: zaehlt ? null : TextDecoration.lineThrough,
              ),
            ),
          ),
          IconButton(
            onPressed: onDatenblatt,
            icon: const Icon(Icons.print_outlined, size: 16),
            tooltip: 'Datenblatt dieser Produktion drucken',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

/// Kleine Beschriftung mit Rahmen.
class _Marke extends StatelessWidget {
  const _Marke({
    required this.text,
    required this.farbe,
    this.kraeftig = false,
  });

  final String text;
  final Color farbe;
  final bool kraeftig;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: farbe.withValues(alpha: kraeftig ? 0.14 : 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: farbe.withValues(alpha: 0.45)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: kraeftig ? FontWeight.w700 : FontWeight.w500,
          color: farbe,
        ),
      ),
    );
  }
}

/// Fehler (rot) oder Hinweis (bernstein) über der Liste, zum Wegklicken.
class _Meldung extends StatelessWidget {
  const _Meldung({
    required this.text,
    required this.istFehler,
    required this.onSchliessen,
  });

  final String text;
  final bool istFehler;
  final VoidCallback onSchliessen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final farbe = istFehler ? theme.colorScheme.error : Colors.amber.shade800;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: farbe.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: farbe.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            istFehler ? Icons.error_outline : Icons.info_outline,
            color: farbe,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: farbe),
            ),
          ),
          IconButton(
            onPressed: onSchliessen,
            icon: const Icon(Icons.close, size: 18),
            visualDensity: VisualDensity.compact,
            tooltip: 'Schließen',
          ),
        ],
      ),
    );
  }
}

class _LeerHinweis extends StatelessWidget {
  const _LeerHinweis();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.local_shipping_outlined,
                size: 46,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 14),
              const Text(
                'Noch kein Auftragsbestand eingelesen.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'In Navision den Bericht „Auftragsbestand" mit dem '
                'gewünschten Zeitraum aufrufen, in der Vorschau „Speichern '
                'unter → Excel" wählen und die Datei hier einlesen.\n\n'
                'Tipp: Immer mit demselben Grundfilter aufrufen — alle '
                'Kunden, alle Artikel, nur den Zeitraum anpassen — und ihn '
                'ein paar Tage vor heute beginnen lassen. Dann sind auch '
                'überfällige Aufträge dabei, und der Vergleich mit dem '
                'vorigen Bericht stimmt.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sperrt die Bedienung, solange eine Datei gelesen wird.
class _LeseSchleier extends StatelessWidget {
  const _LeseSchleier();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned.fill(
      child: ColoredBox(
        color: theme.colorScheme.surface.withValues(alpha: 0.85),
        child: const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 14),
                  Text('Auftragsbestand wird gelesen und geprüft …'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Formatierung
// ═══════════════════════════════════════════════════════════════════════════

const _wochentage = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

String _zweistellig(int n) => n.toString().padLeft(2, '0');

/// „Mi 02.10."
String _tagKurz(DateTime d) =>
    '${_wochentage[d.weekday - 1]} ${_zweistellig(d.day)}.'
    '${_zweistellig(d.month)}.';

/// „02.10."
String _datumKurz(DateTime d) =>
    '${_zweistellig(d.day)}.${_zweistellig(d.month)}.';

/// „02.10.2026"
String _datumLang(DateTime d) => '${_datumKurz(d)}${d.year}';

/// „12:09"
String _uhrzeit(DateTime d) =>
    '${_zweistellig(d.hour)}:${_zweistellig(d.minute)}';

/// Kilogramm mit deutschem Tausenderpunkt: ab 100 kg ganze Zahlen, darunter
/// eine Nachkommastelle, wenn es eine gibt („2.156", „68,3", „4").
String _kg(double v) {
  final ab100 = v.abs() >= 100;
  final zehntel = ab100 ? v.round() * 10 : (v * 10).round();
  final negativ = zehntel < 0;
  final betrag = zehntel.abs();
  final ganz = betrag ~/ 10;
  final rest = betrag % 10;
  final mitPunkten = ganz.toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => '.',
      );
  return '${negativ ? '-' : ''}$mitPunkten${rest == 0 ? '' : ',$rest'}';
}

/// Menge ohne unnötige Nachkommastellen („2", „1,5").
String _zahl(double v) => v == v.roundToDouble()
    ? v.round().toString()
    : v.toString().replaceAll('.', ',');
