import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';
import '../providers/database_provider.dart';
import 'prozesskette_service.dart';

// Prozessvorlagen: feste Prozessketten zum Wählen.
//
// Eine Vorlage ist eine Folge von Schritten — Abteilung, Anlage,
// Tätigkeit —, wie sie für eine Art von Artikeln immer gleich ist
// („Schnitzel paniert, gebraten"). Am Artikel angewendet, legt sie die
// Kette mit leeren Werten an; gefüllt und angepasst wird danach am
// Artikel selbst.
//
// Die Vorlagen sind Daten des Betriebs und stehen deshalb in der
// Datenbank (`app_settings`), nicht im Code. So wandern sie mit jedem
// Backup mit und lassen sich als Datei weitergeben.
//
// Welche Vorlage zu einem Artikel passt, schlägt die App über Stichworte
// in der Bezeichnung vor (siehe [ProzessVorlage.muss]).

/// Unter diesem Schlüssel stehen die Vorlagen in `app_settings`.
const String kProzessVorlagenSchluessel = 'prozess_vorlagen';

/// Kennung der Datei, mit der sich Vorlagen weitergeben lassen.
const String kProzessVorlagenFormat = 'planer-prozessvorlagen';

/// Ein Schritt einer Vorlage.
class VorlagenSchritt {
  const VorlagenSchritt({
    required this.abteilung,
    this.maschineId,
    this.maschine,
    this.prozessschritt,
  });

  /// Abteilung (dbValue).
  final String abteilung;

  /// Die Anlage aus dem Maschinen-Katalog — null: Handarbeit oder offen.
  final String? maschineId;

  /// Ihr Name. Damit findet die Vorlage ihre Anlage auch auf einem
  /// anderen Rechner wieder, wo sie eine andere ID hat.
  final String? maschine;

  /// Was hier geschieht („mit Lake poltern", „von Hand vereinzeln").
  final String? prozessschritt;

  VorlagenSchritt kopie({
    String? abteilung,
    Value<String?> maschineId = const Value.absent(),
    Value<String?> maschine = const Value.absent(),
    Value<String?> prozessschritt = const Value.absent(),
  }) =>
      VorlagenSchritt(
        abteilung: abteilung ?? this.abteilung,
        maschineId: maschineId.present ? maschineId.value : this.maschineId,
        maschine: maschine.present ? maschine.value : this.maschine,
        prozessschritt:
            prozessschritt.present ? prozessschritt.value : this.prozessschritt,
      );

  Map<String, Object?> toJson() => {
        'abteilung': abteilung,
        if (maschineId != null) 'maschineId': maschineId,
        if (maschine != null) 'maschine': maschine,
        if (prozessschritt != null) 'prozessschritt': prozessschritt,
      };

  static VorlagenSchritt? ausJson(Object? j) {
    if (j is! Map) return null;
    final abteilung = _text(j['abteilung']);
    if (abteilung == null) return null;
    return VorlagenSchritt(
      abteilung: abteilung,
      maschineId: _text(j['maschineId']),
      maschine: _text(j['maschine']),
      prozessschritt: _text(j['prozessschritt']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VorlagenSchritt &&
      other.abteilung == abteilung &&
      other.maschineId == maschineId &&
      other.maschine == maschine &&
      other.prozessschritt == prozessschritt;

  @override
  int get hashCode =>
      Object.hash(abteilung, maschineId, maschine, prozessschritt);
}

/// Eine Prozessvorlage.
class ProzessVorlage {
  const ProzessVorlage({
    required this.id,
    required this.name,
    this.muss = const [],
    this.nicht = const [],
    this.schritte = const [],
  });

  final String id;
  final String name;

  /// Stichworte, die alle in der Bezeichnung stehen müssen, damit die
  /// Vorlage vorgeschlagen wird. Ein Eintrag darf Alternativen tragen
  /// („frikadell|hacksteak|burger"). Gesucht wird ohne Rücksicht auf
  /// Groß und klein und auf Umlaute; mit „=" davor zählt nur das ganze
  /// Wort („=roh" trifft „roh", nicht „Rohware").
  final List<String> muss;

  /// Stichworte, bei denen die Vorlage nicht vorgeschlagen wird — gleiche
  /// Schreibweise wie [muss].
  final List<String> nicht;

  final List<VorlagenSchritt> schritte;

  ProzessVorlage kopie({
    String? id,
    String? name,
    List<String>? muss,
    List<String>? nicht,
    List<VorlagenSchritt>? schritte,
  }) =>
      ProzessVorlage(
        id: id ?? this.id,
        name: name ?? this.name,
        muss: muss ?? this.muss,
        nicht: nicht ?? this.nicht,
        schritte: schritte ?? this.schritte,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        if (muss.isNotEmpty) 'muss': muss,
        if (nicht.isNotEmpty) 'nicht': nicht,
        'schritte': [for (final s in schritte) s.toJson()],
      };

  static ProzessVorlage? ausJson(Object? j) {
    if (j is! Map) return null;
    final id = _text(j['id']);
    final name = _text(j['name']);
    if (id == null || name == null) return null;
    return ProzessVorlage(
      id: id,
      name: name,
      muss: _texte(j['muss']),
      nicht: _texte(j['nicht']),
      schritte: [
        if (j['schritte'] is List)
          for (final s in j['schritte'] as List)
            if (VorlagenSchritt.ausJson(s) case final schritt?) schritt,
      ],
    );
  }
}

String? _text(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

List<String> _texte(Object? v) => [
      if (v is List)
        for (final e in v)
          if (_text(e) case final t?) t,
    ];

// ── Datei ────────────────────────────────────────────────────────────────

/// Die [vorlagen] als Text — für `app_settings` und für die Datei.
String vorlagenAlsText(List<ProzessVorlage> vorlagen) =>
    const JsonEncoder.withIndent('  ').convert({
      'format': kProzessVorlagenFormat,
      'version': 1,
      'vorlagen': [for (final v in vorlagen) v.toJson()],
    });

/// Liest Vorlagen aus [text]. Wirft eine [FormatException], wenn der
/// Text keine Vorlagen-Datei ist.
List<ProzessVorlage> vorlagenAusText(String text) {
  final Object? j;
  try {
    j = jsonDecode(text);
  } on FormatException {
    throw const FormatException('Die Datei ist keine Vorlagen-Datei.');
  }
  if (j is! Map || j['format'] != kProzessVorlagenFormat) {
    throw const FormatException('Die Datei ist keine Vorlagen-Datei.');
  }
  final version = j['version'];
  if (version is! int || version > 1) {
    throw const FormatException(
      'Die Vorlagen stammen aus einer neueren Version des Planers.',
    );
  }
  return [
    if (j['vorlagen'] is List)
      for (final v in j['vorlagen'] as List)
        if (ProzessVorlage.ausJson(v) case final vorlage?) vorlage,
  ];
}

/// Führt [neue] in [bisher] ein: Eine Vorlage mit derselben ID ersetzt
/// die bisherige an ihrem Platz, die übrigen kommen hinten dazu.
List<ProzessVorlage> vorlagenZusammenfuehren(
  List<ProzessVorlage> bisher,
  List<ProzessVorlage> neue,
) {
  final nachId = {for (final v in neue) v.id: v};
  return [
    for (final v in bisher) nachId.remove(v.id) ?? v,
    ...nachId.values,
  ];
}

/// Ordnet die Anlagen der [vorlagen] den [maschinen] dieses Rechners zu:
/// Gibt es die ID nicht, wird über den Namen gesucht (Groß und klein egal).
/// Findet sich keine Anlage, bleibt der Name stehen und die ID fällt weg.
/// Der Name folgt immer dem Katalog.
List<ProzessVorlage> anlagenZuordnen(
  List<ProzessVorlage> vorlagen,
  List<Machine> maschinen,
) {
  final nachId = {for (final m in maschinen) m.id: m};
  final nachName = {
    for (final m in maschinen) m.name.trim().toLowerCase(): m,
  };
  return [
    for (final v in vorlagen)
      v.kopie(
        schritte: [
          for (final s in v.schritte)
            if (nachId[s.maschineId] ??
                    nachName[s.maschine?.trim().toLowerCase()]
                case final m?)
              s.kopie(maschineId: Value(m.id), maschine: Value(m.name))
            else
              s.kopie(maschineId: const Value(null)),
        ],
      ),
  ];
}

// ── Speichern ────────────────────────────────────────────────────────────

/// Liest und schreibt die Vorlagen des Betriebs.
class ProzessVorlagenSpeicher {
  const ProzessVorlagenSpeicher._();

  static Future<List<ProzessVorlage>> laden(AppDatabase db) async {
    final zeile = await (db.select(db.appSettings)
          ..where((s) => s.key.equals(kProzessVorlagenSchluessel)))
        .getSingleOrNull();
    if (zeile == null) return const [];
    try {
      return vorlagenAusText(zeile.value);
    } on FormatException {
      return const [];
    }
  }

  static Future<void> speichern(
    AppDatabase db,
    List<ProzessVorlage> vorlagen,
  ) =>
      db.into(db.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: kProzessVorlagenSchluessel,
              value: vorlagenAlsText(vorlagen),
              updatedAt: Value(DateTime.now()),
            ),
          );
}

/// Die Vorlagen des Betriebs — folgt jeder Änderung.
final prozessVorlagenProvider = StreamProvider<List<ProzessVorlage>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.appSettings)
        ..where((s) => s.key.equals(kProzessVorlagenSchluessel)))
      .watchSingleOrNull()
      .map((zeile) {
    if (zeile == null) return const <ProzessVorlage>[];
    try {
      return vorlagenAusText(zeile.value);
    } on FormatException {
      return const <ProzessVorlage>[];
    }
  });
});

// ── Vorschlagen ──────────────────────────────────────────────────────────

/// Kleinbuchstaben, Umlaute ausgeschrieben, alles außer Buchstaben und
/// Ziffern als Leerzeichen.
String _falten(String text) => text
    .toLowerCase()
    .replaceAll('ä', 'ae')
    .replaceAll('ö', 'oe')
    .replaceAll('ü', 'ue')
    .replaceAll('ß', 'ss')
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim();

/// Ob ein Stichwort-Eintrag (mit Alternativen, siehe [ProzessVorlage.muss])
/// in der gefalteten Bezeichnung [text] steht.
bool _trifft(String eintrag, String text, Set<String> worte) {
  for (final roh in eintrag.split('|')) {
    final r = roh.trim();
    if (r.isEmpty) continue;
    if (r.startsWith('=')) {
      final wort = _falten(r.substring(1));
      if (wort.isNotEmpty && worte.contains(wort)) return true;
    } else {
      final teil = _falten(r);
      if (teil.isNotEmpty && text.contains(teil)) return true;
    }
  }
  return false;
}

/// Wie gut [vorlage] zur [bezeichnung] passt: die Zahl ihrer Stichworte —
/// null, wenn sie nicht passt (ein Stichwort fehlt, ein ausgeschlossenes
/// steht darin, oder sie hat gar keine).
int? vorlagePasst(ProzessVorlage vorlage, String bezeichnung) {
  if (vorlage.muss.isEmpty) return null;
  final text = _falten(bezeichnung);
  final worte = text.split(' ').toSet();
  for (final n in vorlage.nicht) {
    if (_trifft(n, text, worte)) return null;
  }
  for (final m in vorlage.muss) {
    if (!_trifft(m, text, worte)) return null;
  }
  return vorlage.muss.length;
}

/// Der Text, in dem die Stichworte gesucht werden: die Bezeichnung des
/// Artikels und dahinter „Beschreibung 2" aus Navision — dort steht oft,
/// ob er geschnitten oder tiefgekühlt ist.
String vorschlagsText(Product artikel, NavisionArtikelZeile? navision) => [
      artikel.artikelbezeichnung,
      if (navision?.beschreibung2 case final b2? when b2.trim().isNotEmpty) b2,
    ].join(' ');

/// [vorschlagsText] für alle [artikel] — nach Artikel-ID.
Future<Map<String, String>> vorschlagsTexte(
  AppDatabase db,
  Iterable<Product> artikel,
) async {
  final navision = {
    for (final n in await db.select(db.navisionArtikel).get())
      n.artikelnummer: n,
  };
  return {
    for (final a in artikel) a.id: vorschlagsText(a, navision[a.artikelnummer]),
  };
}

/// Der Vorschlag für einen Artikel.
class VorlagenVorschlag {
  const VorlagenVorschlag({required this.passend, this.mehrdeutig = false});

  /// Die passenden Vorlagen, die genaueste zuerst (die mit den meisten
  /// Stichworten).
  final List<ProzessVorlage> passend;

  /// Mehrere Vorlagen passen gleich gut.
  final bool mehrdeutig;

  /// Genau eine Vorlage passt am besten.
  bool get sicher => passend.isNotEmpty && !mehrdeutig;

  /// Die vorgeschlagene Vorlage — null, wenn keine passt oder mehrere
  /// gleich gut.
  ProzessVorlage? get vorlage => sicher ? passend.first : null;
}

/// Welche der [vorlagen] zur [bezeichnung] passen.
VorlagenVorschlag vorlageVorschlagen(
  List<ProzessVorlage> vorlagen,
  String bezeichnung,
) {
  final treffer = [
    for (final (i, v) in vorlagen.indexed)
      if (vorlagePasst(v, bezeichnung) case final punkte?) (punkte, i, v),
  ]..sort((a, b) {
      final p = b.$1.compareTo(a.$1);
      return p != 0 ? p : a.$2.compareTo(b.$2);
    });
  return VorlagenVorschlag(
    passend: [for (final t in treffer) t.$3],
    mehrdeutig: treffer.length > 1 && treffer[0].$1 == treffer[1].$1,
  );
}

// ── Anwenden ─────────────────────────────────────────────────────────────

/// Legt die Schritte von [vorlage] beim Artikel [productId] an — hinter
/// denen, die er schon hat; die bleiben, wie sie sind. Werte tragen die
/// neuen Schritte keine, gepflegt wird am Artikel. Gibt die IDs der neuen
/// Schritte zurück.
///
/// Wirft einen [StateError], wenn die Kette damit mehr als
/// [ProzesskettenService.maxSchritte] Schritte hätte.
Future<List<String>> vorlageAnwenden(
  AppDatabase db,
  String productId,
  ProzessVorlage vorlage,
) {
  return db.transaction(() async {
    final vorher = await ProzesskettenService.schritte(db, productId);
    final anlagen = {
      for (final m in await db.select(db.machines).get()) m.id,
    };
    final ids = await ProzesskettenService.uebernehmen(db, productId, [
      for (final s in vorher)
        (
          id: s.id,
          abteilung: s.abteilung,
          maschineId: s.maschineId,
          maschine: s.maschine,
          prozessschritt: s.prozessschritt,
        ),
      for (final s in vorlage.schritte)
        (
          id: null,
          abteilung: s.abteilung,
          // Eine Anlage, die es nicht mehr gibt, bleibt nur als Name.
          maschineId: anlagen.contains(s.maschineId) ? s.maschineId : null,
          maschine: s.maschine,
          prozessschritt: s.prozessschritt,
        ),
    ]);
    return ids.sublist(vorher.length);
  });
}

/// Legt für jeden Artikel aus [zuordnung] (Artikel-ID → Vorlage) die
/// Kette an — aber nur bei Artikeln, die noch keine Schritte haben: Wer
/// inzwischen gepflegt wurde, bleibt unberührt. Gibt die IDs aller neuen
/// Schritte zurück, für [vorlagenZuruecknehmen].
Future<List<String>> vorlagenZuordnen(
  AppDatabase db,
  Map<String, ProzessVorlage> zuordnung,
) {
  return db.transaction(() async {
    final neu = <String>[];
    for (final e in zuordnung.entries) {
      if ((await ProzesskettenService.schritte(db, e.key)).isNotEmpty) {
        continue;
      }
      neu.addAll(await vorlageAnwenden(db, e.key, e.value));
    }
    return neu;
  });
}

/// Nimmt die Schritte [stepIds] wieder heraus, die [vorlagenZuordnen]
/// angelegt hat (sie werden als gelöscht markiert).
Future<void> vorlagenZuruecknehmen(
  AppDatabase db,
  List<String> stepIds,
) async {
  if (stepIds.isEmpty) return;
  final jetzt = DateTime.now();
  await (db.update(db.productSteps)
        ..where((s) => s.id.isIn(stepIds) & s.deletedAt.isNull()))
      .write(
    ProductStepsCompanion(deletedAt: Value(jetzt), updatedAt: Value(jetzt)),
  );
}

/// Eine neue, leere Vorlage.
ProzessVorlage neueVorlage(String name) =>
    ProzessVorlage(id: const Uuid().v4(), name: name);
