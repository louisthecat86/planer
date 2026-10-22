import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/entwicklung.dart';
import '../../../core/database/database.dart';
import '../../../core/providers/database_provider.dart';
import '../daten/dateien.dart';
import '../daten/entwicklung_repository.dart';
import '../freigabe/freigabe.dart' show FreigabeStand;
import '../projekte/projekt_modell.dart';
import '../projekte/projekt_repository.dart';
import '../rechenkern/rechenkern.dart';
import 'deepl.dart';
import 'spez_angaben.dart';
import 'spezifikation_werte.dart';
import 'vorlage_einrichten.dart';
import 'xlsx_vorlage.dart';

// Spezifikationen aus der eigenen Excel-Vorlage erstellen. Die Vorlagen
// (je eine deutsche und eine englische) liegen verschlüsselt bei den
// Entwicklungsdateien und wandern so ins Backup — im Code steht keine.
//
// Eine Vorlage ohne Platzhalter — das Formblatt, wie es in der Firma
// liegt — richtet die App beim Speichern selbst ein
// (vorlage_einrichten.dart); fehlen einer Vorlage Platzhalter, die die
// App setzen kann, ergänzt sie sie — auch beim Erstellen, für Vorlagen,
// die noch aus einer früheren Fassung stammen.

/// Die IDs der Vorlagen unter den Entwicklungsdateien.
String spezVorlageId(SpezSprache s) => 'vorlage.spezifikation.${s.name}';

const String kXlsxMime =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// Übersetzt Texte — im Test ersetzbar.
typedef Uebersetzer = Future<List<String>> Function(
  List<String> texte,
  String schluessel,
);

/// Was beim Speichern einer Vorlage herauskam.
class VorlageGespeichert {
  const VorlageGespeichert({required this.platzhalter, this.einrichtung});

  /// Die Platzhalter der gespeicherten Vorlage.
  final Set<String> platzhalter;

  /// Was die App selbst eingerichtet oder ergänzt hat — null, wenn es
  /// nichts zu tun gab.
  final EinrichtenErgebnis? einrichtung;
}

/// Was beim Erstellen herauskam.
class SpezifikationErgebnis {
  const SpezifikationErgebnis({
    required this.bytes,
    required this.dateiname,
    required this.ersetzt,
    this.unbekannt = const {},
    this.uebersetzt = false,
    this.uebersetzungsFehler,
    this.kaestchen = 0,
    this.hinweise = const [],
  });

  final Uint8List bytes;
  final String dateiname;

  /// Wie viele Platzhalter ersetzt wurden.
  final int ersetzt;

  /// Platzhalter in der Vorlage, die die App nicht kennt.
  final Set<String> unbekannt;

  /// Mit DeepL übersetzt.
  final bool uebersetzt;

  /// Warum nicht übersetzt wurde — null, wenn es klappte oder nicht
  /// gewünscht war.
  final String? uebersetzungsFehler;

  /// Wie viele Kontrollkästchen angehakt wurden.
  final int kaestchen;

  /// Was in der Vorlage keinen Platz fand — etwa ein Allergen ohne Zeile.
  final List<String> hinweise;
}

/// Die Felder, die in keiner Spezifikation fehlen sollten — mit ihrem
/// Namen für die Meldungen.
const List<({String name, String label})> kSpezPflichtfelder = [
  (name: 'artikelnummer', label: 'Artikelnummer'),
  (name: 'bezeichnung', label: 'Artikelbezeichnung'),
  (name: 'zutaten', label: 'Zutaten'),
  (name: 'lagerung', label: 'Lagerbedingungen'),
  (name: 'haltbarkeit', label: 'Haltbarkeit'),
];

/// Was von den Pflichtfeldern fehlt: in der Vorlage kein Platz dafür
/// ([platzhalter]) oder leer geblieben ([werte]).
List<String> spezLuecken({
  required Set<String> platzhalter,
  required Map<String, String> werte,
}) {
  final ohnePlatz = [
    for (final f in kSpezPflichtfelder)
      if (!platzhalter.contains(f.name)) f.label,
  ];
  bool leer(String name) =>
      platzhalter.contains(name) && (werte[name]?.trim() ?? '').isEmpty;
  final eintragen = [
    for (final f in kSpezPflichtfelder)
      if (f.name != 'zutaten' && leer(f.name)) f.label,
  ];
  return [
    if (ohnePlatz.isNotEmpty)
      'Die Vorlage hat keinen Platz für ${_liste(ohnePlatz)} — trag dort '
          'Platzhalter wie {{artikelnummer}} ein oder wähl sie unter '
          '„Vorlagen und DeepL" noch einmal.',
    if (eintragen.isNotEmpty)
      'Leer geblieben: ${_liste(eintragen)} — einzutragen im Reiter '
          '„Spezifikation".',
    if (leer('zutaten'))
      'Der Rezepturstand hat keine Zutaten — die Zutatenliste bleibt leer.',
  ];
}

/// „A", „A und B", „A, B und C".
String _liste(List<String> teile) => teile.length < 2
    ? teile.join()
    : '${teile.sublist(0, teile.length - 1).join(', ')} und ${teile.last}';

/// Was in der Vorlage keinen Platz findet: Allergene ohne Zeile, mehr
/// Hilfsstoffe oder Produkthinweise als Plätze.
List<String> spezPlatzHinweise({
  required Set<String> platzhalter,
  required RezepturErgebnis ergebnis,
  required SpezAngaben angaben,
}) {
  final hinweise = <String>[];
  // Allergene: nur wenn die Vorlage eine Allergentabelle hat.
  final tabelle = platzhalter.any(
    (p) => p.startsWith('allergen.') && p.endsWith('.ja'),
  );
  if (tabelle && !platzhalter.contains('allergene')) {
    final ohneZeile = [
      for (final a in ergebnis.allergene.keys)
        if (!platzhalter.contains('allergen.$a.ja'))
          allergenName(a, SpezSprache.de),
    ];
    if (ohneZeile.isNotEmpty) {
      hinweise.add(
        'Die Rezeptur enthält ${ohneZeile.join(', ')} — die Vorlage hat dafür '
        'keine Zeile in der Allergentabelle.',
      );
    }
  }
  int plaetze(RegExp muster) {
    var n = 0;
    for (final p in platzhalter) {
      final m = muster.firstMatch(p);
      if (m != null) {
        final i = int.parse(m[1]!);
        if (i > n) n = i;
      }
    }
    return n;
  }

  final hilfsstoffe = ergebnis.verarbeitungshilfsstoffe.length;
  final hilfsPlaetze = plaetze(RegExp(r'^hilfsstoff\.(\d+)\.name$'));
  if (hilfsPlaetze > 0 && hilfsstoffe > hilfsPlaetze) {
    hinweise.add(
      'Die Rezeptur hat $hilfsstoffe Verarbeitungshilfsstoffe, die Vorlage '
      'Platz für $hilfsPlaetze — die übrigen fehlen.',
    );
  }
  final zeilen = angaben.hinweisZeilen.length;
  final hinweisPlaetze = plaetze(RegExp(r'^hinweis\.(\d+)$'));
  if (hinweisPlaetze > 0 &&
      zeilen > hinweisPlaetze &&
      !platzhalter.contains('hinweise')) {
    hinweise.add(
      'Es gibt $zeilen Produkthinweise, die Vorlage hat Platz für '
      '$hinweisPlaetze — die übrigen fehlen.',
    );
  }
  return hinweise;
}

/// Vorlagen verwalten und Spezifikationen erstellen.
class SpezifikationDienst {
  SpezifikationDienst(
    this._db,
    this._dateien, {
    Uebersetzer uebersetzer = _deepl,
  }) : _uebersetzer = uebersetzer;

  final AppDatabase _db;
  final EntwicklungDateienDienst _dateien;
  final Uebersetzer _uebersetzer;

  static Future<List<String>> _deepl(List<String> texte, String schluessel) =>
      deeplUebersetzen(texte, schluessel);

  /// Die gespeicherte Vorlage einer Sprache — null, wenn keine da ist.
  Future<EntwicklungsDatei?> vorlage(SpezSprache s) =>
      _dateien.datei(spezVorlageId(s));

  /// Der Inhalt der gespeicherten Vorlage — so, wie die App sie füllt.
  Future<Uint8List?> vorlageInhalt(SpezSprache s) =>
      _dateien.lesen(spezVorlageId(s));

  /// Speichert eine Vorlage. Die App richtet sie selbst ein — oder
  /// ergänzt, was fehlt, wenn sie schon Platzhalter hat. Wirft
  /// [FormatException], wenn sie keine Excel-Mappe ist.
  Future<VorlageGespeichert> vorlageSpeichern(
    SpezSprache s,
    String name,
    Uint8List bytes,
  ) async {
    final e = vorlageEinrichten(bytes);
    final einrichtung = e.felder.isEmpty ? null : e;
    final inhalt = e.bytes;
    final platzhalter = platzhalterIn(inhalt);
    await _dateien.speichern(
      id: spezVorlageId(s),
      name: name,
      inhalt: inhalt,
      mimeTyp: kXlsxMime,
    );
    return VorlageGespeichert(
      platzhalter: platzhalter,
      einrichtung: einrichtung,
    );
  }

  Future<void> vorlageLoeschen(SpezSprache s) =>
      _dateien.loeschen(spezVorlageId(s));

  /// Die Stände der Rezepturen eines Projekts: abgeschlossene vor
  /// Entwürfen, jeweils der neueste zuerst.
  Future<List<FreigabeStand>> staende(String projektId) async {
    final rezepturen = await (_db.select(_db.entwicklungRezepturen)
          ..where((r) => r.projektId.equals(projektId))
          ..where((r) => r.deletedAt.isNull()))
        .get();
    final liste = <FreigabeStand>[];
    for (final r in rezepturen) {
      final versionen = await (_db.select(_db.entwicklungRezepturVersionen)
            ..where((v) => v.rezepturId.equals(r.id)))
          .get();
      for (final v in versionen) {
        liste.add(FreigabeStand(rezeptur: r, version: v));
      }
    }
    int rang(FreigabeStand s) =>
        s.version.status == VersionStatus.abgeschlossen ? 0 : 1;
    DateTime zeit(FreigabeStand s) =>
        s.version.abgeschlossenAm ?? s.version.updatedAt;
    liste.sort((a, b) {
      final r = rang(a).compareTo(rang(b));
      return r != 0 ? r : zeit(b).compareTo(zeit(a));
    });
    return liste;
  }

  /// Legt die Spezifikation verschlüsselt bei den Projektdateien ab und
  /// schreibt sie mit dem Rezepturstand in den Verlauf.
  Future<String> ablegen({
    required EntwicklungsProjekt projekt,
    required String versionId,
    required SpezSprache sprache,
    required SpezifikationErgebnis ergebnis,
    DateTime? jetzt,
  }) async {
    final heute = jetzt ?? DateTime.now();
    final dateiId = await _dateien.speichern(
      name: ergebnis.dateiname,
      inhalt: ergebnis.bytes,
      projektId: projekt.id,
      mimeTyp: kXlsxMime,
    );
    final version = await EntwicklungRepository(_db).version(versionId);
    await ProjektRepository(_db).eintragAnlegen(
      projektId: projekt.id,
      art: EintragArt.datei,
      titel: 'Spezifikation (${sprache.label})',
      datum: DateTime(heute.year, heute.month, heute.day),
      status: EintragStatus.erledigt,
      beschreibung: version == null
          ? null
          : 'Erstellt aus Rezepturstand ${version.nummer}'
              '${ergebnis.uebersetzt ? ', Texte mit DeepL übersetzt' : ''}.',
      dateiId: dateiId,
      versionId: versionId,
    );
    return dateiId;
  }

  /// Hakt „Spezifikation erstellt" in der Checkliste des Projekts ab.
  Future<void> abhaken(String projektId) =>
      ProjektRepository(_db).checklistePunkt(
        projektId,
        schluessel: 'spezifikationErstellt',
        erledigt: true,
      );

  Future<String?> _einstellung(String schluessel) async {
    final zeile = await (_db.select(_db.appSettings)
          ..where((s) => s.key.equals(schluessel)))
        .getSingleOrNull();
    final t = zeile?.value.trim();
    return t == null || t.isEmpty ? null : t;
  }

  Future<void> _einstellungSpeichern(String schluessel, String? wert) async {
    final t = wert?.trim() ?? '';
    if (t.isEmpty) {
      await (_db.delete(_db.appSettings)..where((s) => s.key.equals(schluessel)))
          .go();
      return;
    }
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: schluessel, value: t),
        );
  }

  Future<String?> deeplSchluessel() => _einstellung(kEntwicklungDeeplSchluessel);

  /// Hinterlegt den DeepL-Schlüssel — leer löscht ihn.
  Future<void> deeplSpeichern(String? schluessel) =>
      _einstellungSpeichern(kEntwicklungDeeplSchluessel, schluessel);

  /// Das Kürzel dessen, der an diesem Rechner Spezifikationen erstellt.
  Future<String?> kuerzel() => _einstellung(kEntwicklungKuerzel);

  /// Merkt sich das Kürzel — leer löscht es.
  Future<void> kuerzelSpeichern(String? kuerzel) =>
      _einstellungSpeichern(kEntwicklungKuerzel, kuerzel);

  /// Woraus die Spezifikation des Stands [versionId] entsteht: Projekt,
  /// Rezepturstand, Artikel (nach der Freigabe) und die Angaben im Reiter
  /// „Spezifikation" — null, wenn es den Stand nicht gibt.
  Future<SpezifikationsQuelle?> quelle({
    required EntwicklungsProjekt projekt,
    required String versionId,
    String? kuerzel,
  }) async {
    final repo = EntwicklungRepository(_db);
    final eingabe = await repo.rechenRezeptur(versionId);
    final version = await repo.version(versionId);
    if (eingabe == null || version == null) return null;
    final artikelId = projekt.artikelId;
    final artikel = artikelId == null
        ? null
        : await (_db.select(_db.products)
              ..where((p) => p.id.equals(artikelId))
              ..where((p) => p.deletedAt.isNull()))
            .getSingleOrNull();
    final angaben = SpezAngaben.aus(projekt.spezifikation);
    final eigene = angaben.bezeichnung.trim();
    final nummer = artikel?.artikelnummer ?? projekt.artikelnummer;
    return SpezifikationsQuelle(
      projektName: projekt.name,
      ergebnis: berechne(eingabe),
      verlustProzent: eingabe.wirksamerVerlust,
      artikelnummer: nummer?.trim(),
      bezeichnung: eigene.isNotEmpty ? eigene : artikel?.artikelbezeichnung,
      kunde: projekt.kunde,
      standNummer: version.nummer,
      haltbarkeitTage: artikel?.haltbarkeitTage,
      aw: projekt.grenzeAw,
      sensorik: Sensorik.aus(projekt.sensorik),
      angaben: angaben,
      kuerzel: kuerzel,
    );
  }

  /// Ergänzt die gespeicherte Vorlage um Platzhalter, die ihr fehlen —
  /// etwa eine Vorlage aus einer früheren Fassung, die noch gar nicht
  /// eingerichtet war — und merkt sie sich so. Null, wenn nichts fehlte.
  Future<EinrichtenErgebnis?> _ergaenzen(SpezSprache s, Uint8List vorlage) async {
    final EinrichtenErgebnis e;
    try {
      e = vorlageEinrichten(vorlage);
    } on FormatException {
      return null;
    }
    if (e.felder.isEmpty) return null;
    final d = await this.vorlage(s);
    await _dateien.speichern(
      id: spezVorlageId(s),
      name: d?.name ?? 'Vorlage ${s.label}.xlsx',
      inhalt: e.bytes,
      mimeTyp: kXlsxMime,
    );
    return e;
  }

  /// Erstellt die Spezifikation des Stands [versionId] in [sprache].
  /// Wirft [StateError], wenn Vorlage oder Stand fehlen.
  Future<SpezifikationErgebnis> erstellen({
    required EntwicklungsProjekt projekt,
    required String versionId,
    required SpezSprache sprache,
    bool uebersetzen = true,
    DateTime? datum,
    String? kuerzel,
  }) async {
    var vorlage = await _dateien.lesen(spezVorlageId(sprache));
    if (vorlage == null) {
      throw StateError(
        'Für ${sprache.label} ist noch keine Vorlage gewählt.',
      );
    }
    final quelle = await this.quelle(
      projekt: projekt,
      versionId: versionId,
      kuerzel: kuerzel,
    );
    if (quelle == null) {
      throw StateError('Den Rezepturstand gibt es nicht.');
    }
    final ergaenzt = await _ergaenzen(sprache, vorlage);
    if (ergaenzt != null) vorlage = ergaenzt.bytes;
    final ergebnis = quelle.ergebnis;
    final angaben = quelle.angaben;
    var werte = spezifikationsWerte(
      quelle,
      sprache: sprache,
      datum: datum ?? DateTime.now(),
    );

    var uebersetzt = false;
    String? fehler;
    if (sprache == SpezSprache.en && uebersetzen) {
      final schluessel = await deeplSchluessel();
      if (schluessel == null) {
        fehler = 'Kein DeepL-Schlüssel hinterlegt — die Texte sind deutsch.';
      } else {
        final texte = uebersetzbareTexte(werte);
        final eindeutig = texte.values.toSet().toList();
        try {
          final englisch = await _uebersetzer(eindeutig, schluessel);
          final zuordnung = {
            for (var i = 0; i < eindeutig.length; i++)
              eindeutig[i]: englisch[i],
          };
          werte = {
            ...werte,
            for (final MapEntry(:key, :value) in texte.entries)
              key: zuordnung[value] ?? value,
          };
          uebersetzt = true;
        } on DeepLFehler catch (e) {
          fehler = '${e.meldung} Die Texte sind deutsch.';
        }
      }
    }

    final gefuellt = vorlageFuellen(vorlage, werte);
    final platzhalter = platzhalterIn(vorlage);
    // Der Dateiname mit der deutschen Bezeichnung — auch für Englisch.
    final bezeichnung = quelle.bezeichnung?.trim() ?? '';
    final name = (bezeichnung.isEmpty ? projekt.name : bezeichnung)
        .replaceAll(RegExp(r'[^A-Za-z0-9äöüßÄÖÜ \-]'), '_')
        .trim();
    return SpezifikationErgebnis(
      bytes: gefuellt.bytes,
      dateiname: '${name.isEmpty ? 'Artikel' : name}_'
          '${sprache == SpezSprache.de ? 'Spezifikation' : 'Specification'}'
          '.xlsx',
      ersetzt: gefuellt.ersetzt.length,
      unbekannt: gefuellt.unbekannt,
      uebersetzt: uebersetzt,
      uebersetzungsFehler: fehler,
      kaestchen: gefuellt.kaestchen,
      hinweise: [
        if (ergaenzt != null)
          'Die Vorlage war noch nicht ganz eingerichtet — die App hat '
              '${ergaenzt.felder.length} '
              '${ergaenzt.felder.length == 1 ? 'Feld' : 'Felder'} ergänzt '
              'und sich die Vorlage so gemerkt.',
        ...spezLuecken(platzhalter: platzhalter, werte: werte),
        ...spezPlatzHinweise(
          platzhalter: platzhalter,
          ergebnis: ergebnis,
          angaben: angaben,
        ),
      ],
    );
  }
}

final spezifikationDienstProvider = Provider<SpezifikationDienst>(
  (ref) => SpezifikationDienst(
    ref.watch(databaseProvider),
    ref.watch(entwicklungDateienProvider),
  ),
);

/// Die gespeicherte Vorlage je Sprache — null, wenn keine gewählt ist.
final spezVorlageProvider =
    FutureProvider.autoDispose.family<EntwicklungsDatei?, SpezSprache>(
  (ref, s) => ref.watch(spezifikationDienstProvider).vorlage(s),
);

/// Die Platzhalter der gespeicherten Vorlage je Sprache.
final spezVorlagePlatzhalterProvider =
    FutureProvider.autoDispose.family<Set<String>, SpezSprache>(
  (ref, s) async {
    ref.watch(spezVorlageProvider(s));
    final inhalt = await ref.watch(spezifikationDienstProvider).vorlageInhalt(s);
    if (inhalt == null) return const {};
    try {
      return platzhalterIn(inhalt);
    } on FormatException {
      return const {};
    }
  },
);

/// Ob auf diesem Rechner ein DeepL-Schlüssel hinterlegt ist.
final deeplHinterlegtProvider = FutureProvider.autoDispose<bool>(
  (ref) async =>
      await ref.watch(spezifikationDienstProvider).deeplSchluessel() != null,
);

/// Das Kürzel dieses Rechners.
final spezKuerzelProvider = FutureProvider.autoDispose<String?>(
  (ref) => ref.watch(spezifikationDienstProvider).kuerzel(),
);

/// Die Rezepturstände eines Projekts zur Auswahl.
final spezStaendeProvider =
    FutureProvider.autoDispose.family<List<FreigabeStand>, String>(
  (ref, projektId) =>
      ref.watch(spezifikationDienstProvider).staende(projektId),
);

/// Was mit dem Stand [versionId] in der Spezifikation stünde (deutsch) —
/// für die Vorschau im Reiter. Null, wenn es Projekt oder Stand nicht
/// gibt. Rechnet neu, wenn sich Projekt, Rezeptur oder Katalog ändern.
final spezVorschauProvider = FutureProvider.autoDispose
    .family<Map<String, String>?, ({String projektId, String versionId})>(
  (ref, a) async {
    ref.watch(entwicklungAenderungProvider);
    final projekt = await ref.watch(projektProvider(a.projektId).future);
    if (projekt == null) return null;
    final q = await ref
        .watch(spezifikationDienstProvider)
        .quelle(projekt: projekt, versionId: a.versionId);
    if (q == null) return null;
    return spezifikationsWerte(
      q,
      sprache: SpezSprache.de,
      datum: DateTime.now(),
    );
  },
);
