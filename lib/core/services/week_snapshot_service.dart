import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';
import '../providers/database_provider.dart';
import '../utils/datum.dart';
import '../utils/kalenderwoche.dart';
import 'erledigt_service.dart' show Erledigt;

// Früher hier definiert — jetzt zentral, hier nur weitergereicht.
export '../utils/kalenderwoche.dart' show isoKalenderwoche;

// ═══════════════════════════════════════════════════════════════════════════
// Modell der eingefrorenen Wochendaten
// ═══════════════════════════════════════════════════════════════════════════

/// Ein eingefrorener Auftrag innerhalb eines Wochen-Snapshots. Produktname ist
/// denormalisiert gespeichert, damit der Snapshot auch dann lesbar bleibt,
/// wenn der Artikel später umbenannt oder gelöscht wird.
class SnapshotTask {
  const SnapshotTask({
    required this.abteilung,
    required this.productId,
    required this.productName,
    required this.datum,
    required this.dauerMinuten,
    required this.mitarbeiter,
    required this.mengeKg,
    this.startZeit,
    this.notizen,
  });

  final String abteilung; // dbValue der Abteilung
  final String productId;
  final String productName;
  final DateTime datum;
  final double dauerMinuten;
  final int mitarbeiter;
  final double mengeKg;
  final String? startZeit;
  final String? notizen;

  Map<String, dynamic> toJson() => {
        'abteilung': abteilung,
        'productId': productId,
        'productName': productName,
        'datum': datum.toIso8601String(),
        'dauerMinuten': dauerMinuten,
        'mitarbeiter': mitarbeiter,
        'mengeKg': mengeKg,
        if (startZeit != null) 'startZeit': startZeit,
        if (notizen != null) 'notizen': notizen,
      };

  factory SnapshotTask.fromJson(Map<String, dynamic> j) => SnapshotTask(
        abteilung: j['abteilung'] as String,
        productId: j['productId'] as String? ?? '',
        productName: j['productName'] as String? ?? 'Unbekannt',
        datum: DateTime.parse(j['datum'] as String),
        dauerMinuten: (j['dauerMinuten'] as num?)?.toDouble() ?? 0,
        mitarbeiter: (j['mitarbeiter'] as num?)?.toInt() ?? 1,
        mengeKg: (j['mengeKg'] as num?)?.toDouble() ?? 0,
        startZeit: j['startZeit'] as String?,
        notizen: j['notizen'] as String?,
      );
}

/// Eine eingefrorene Rüst-, Reinigungs- oder sonstige Nebenzeit.
class SnapshotZusatzzeit {
  const SnapshotZusatzzeit({
    required this.datum,
    required this.spurId,
    required this.art,
    required this.minuten,
    this.notiz,
  });

  final DateTime datum;
  final String spurId;
  final String art;
  final double minuten;
  final String? notiz;

  Map<String, dynamic> toJson() => {
        'datum': datum.toIso8601String(),
        'spurId': spurId,
        'art': art,
        'minuten': minuten,
        if (notiz != null) 'notiz': notiz,
      };

  factory SnapshotZusatzzeit.fromJson(Map<String, dynamic> j) =>
      SnapshotZusatzzeit(
        datum: DateTime.parse(j['datum'] as String),
        spurId: j['spurId'] as String? ?? '',
        art: j['art'] as String? ?? 'sonstiges',
        minuten: (j['minuten'] as num?)?.toDouble() ?? 0,
        notiz: j['notiz'] as String?,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// Der Wochenplan, wie er im Board stand
// ═══════════════════════════════════════════════════════════════════════════

/// Der Wochenplan einer archivierten Woche, so wie er beim Archivieren im
/// Wochenboard stand: die Spuren (Abteilungen und Anlagen), die Karten, die
/// sonstigen Aufgaben und die Hinweise auf Vor- und Folgestufen in anderen
/// Wochen. Daraus entsteht im Archiv die Ansicht „Wochenplan".
///
/// Wochen, die archiviert wurden, bevor es den Plan gab, haben keinen. Aus
/// ihren Aufträgen allein ließe er sich nicht nachbauen: Anlage, Kette und
/// Haken wurden damals nicht mitgespeichert.
class ArchivPlan {
  const ArchivPlan({
    required this.tage,
    required this.spuren,
    required this.karten,
    this.aufgaben = const [],
    this.kettenNachbarn = const {},
  });

  /// Die Tage des Boards (Mo–Fr), 00:00 Uhr.
  final List<DateTime> tage;

  /// Die Zeilen des Boards in ihrer Reihenfolge.
  final List<ArchivSpur> spuren;

  /// Die Karten — je Zelle in der Reihenfolge des Boards.
  final List<ArchivKarte> karten;

  /// Sonstige Aufgaben je Abteilung und Tag, in ihrer Reihenfolge.
  final List<ArchivAufgabe> aufgaben;

  /// Vor- und Folgestufen außerhalb der Woche, je Kette
  /// ([ArchivKarte.kettenId]).
  final Map<String, ArchivKettenNachbar> kettenNachbarn;

  Map<String, dynamic> toJson() => {
        'tage': [for (final t in tage) t.toIso8601String()],
        'spuren': [for (final s in spuren) s.toJson()],
        'karten': [for (final k in karten) k.toJson()],
        'aufgaben': [for (final a in aufgaben) a.toJson()],
        'ketten': {
          for (final e in kettenNachbarn.entries) e.key: e.value.toJson(),
        },
      };

  factory ArchivPlan.fromJson(Map<String, dynamic> j) {
    final rawTage = j['tage'] as List<dynamic>? ?? const [];
    final rawSpuren = j['spuren'] as List<dynamic>? ?? const [];
    final rawKarten = j['karten'] as List<dynamic>? ?? const [];
    final rawAufgaben = j['aufgaben'] as List<dynamic>? ?? const [];
    final rawKetten = j['ketten'] as Map<String, dynamic>? ?? const {};
    return ArchivPlan(
      tage: [for (final t in rawTage) DateTime.parse(t as String)],
      spuren: [
        for (final s in rawSpuren)
          ArchivSpur.fromJson(s as Map<String, dynamic>),
      ],
      karten: [
        for (final k in rawKarten)
          ArchivKarte.fromJson(k as Map<String, dynamic>),
      ],
      aufgaben: [
        for (final a in rawAufgaben)
          ArchivAufgabe.fromJson(a as Map<String, dynamic>),
      ],
      kettenNachbarn: {
        for (final e in rawKetten.entries)
          e.key: ArchivKettenNachbar.fromJson(e.value as Map<String, dynamic>),
      },
    );
  }
}

/// Eine Zeile des archivierten Boards: die Spur einer Anlage oder die
/// Sammelspur einer Abteilung.
class ArchivSpur {
  const ArchivSpur({
    required this.abteilung,
    required this.kapazitaetMinuten,
    this.maschineId,
    this.maschineName,
    this.eignungHinweis,
  });

  /// dbValue der Abteilung.
  final String abteilung;

  /// null = Sammelspur der Abteilung.
  final String? maschineId;
  final String? maschineName;
  final String? eignungHinweis;

  /// Tageskapazität der Spur in Minuten, wie sie beim Archivieren galt.
  final double kapazitaetMinuten;

  /// Kennung wie im Board: „<abteilung>|<maschineId>".
  String get id => '$abteilung|${maschineId ?? ''}';

  Map<String, dynamic> toJson() => {
        'abteilung': abteilung,
        if (maschineId != null) 'maschineId': maschineId,
        if (maschineName != null) 'maschineName': maschineName,
        if (eignungHinweis != null) 'eignung': eignungHinweis,
        'kapazitaet': kapazitaetMinuten,
      };

  factory ArchivSpur.fromJson(Map<String, dynamic> j) => ArchivSpur(
        abteilung: j['abteilung'] as String,
        maschineId: j['maschineId'] as String?,
        maschineName: j['maschineName'] as String?,
        eignungHinweis: j['eignung'] as String?,
        kapazitaetMinuten: (j['kapazitaet'] as num?)?.toDouble() ?? 0,
      );
}

/// Eine Karte des archivierten Boards — gebündelt wie im Board: gleicher
/// Artikel in derselben Spur am selben Tag ist eine Karte.
class ArchivKarte {
  const ArchivKarte({
    required this.spurId,
    required this.abteilung,
    required this.datum,
    required this.productId,
    required this.productName,
    required this.dauerMinuten,
    required this.mengeKg,
    required this.kettenId,
    this.artikelnummer = '',
    this.startZeit,
    this.sortierung = 0,
    this.status = 'geplant',
    this.erledigt,
    this.auftraege = 1,
  });

  /// Spur, in der die Karte stand ([ArchivSpur.id]).
  final String spurId;

  /// dbValue der Abteilung.
  final String abteilung;

  /// Tag, 00:00 Uhr.
  final DateTime datum;
  final String productId;
  final String productName;
  final String artikelnummer;
  final String? startZeit;
  final double dauerMinuten;
  final double mengeKg;
  final int sortierung;

  /// 'geplant' | 'in_arbeit' | 'fertig'.
  final String status;

  /// Kennung der Auftragskette — alle Karten einer Produktion tragen
  /// dieselbe und damit dieselbe Farbe.
  final String kettenId;

  /// Erledigt-Stand beim Archivieren — null: offen.
  final Erledigt? erledigt;

  /// Wie viele Aufträge die Karte bündelt.
  final int auftraege;

  Map<String, dynamic> toJson() => {
        'spurId': spurId,
        'abteilung': abteilung,
        'datum': datum.toIso8601String(),
        'productId': productId,
        'productName': productName,
        if (artikelnummer.isNotEmpty) 'artikelnummer': artikelnummer,
        if (startZeit != null) 'startZeit': startZeit,
        'dauerMinuten': dauerMinuten,
        'mengeKg': mengeKg,
        'sortierung': sortierung,
        'status': status,
        'kettenId': kettenId,
        if (erledigt != null) 'erledigt': erledigt?.name,
        'auftraege': auftraege,
      };

  factory ArchivKarte.fromJson(Map<String, dynamic> j) => ArchivKarte(
        spurId: j['spurId'] as String? ?? '',
        abteilung: j['abteilung'] as String,
        datum: DateTime.parse(j['datum'] as String),
        productId: j['productId'] as String? ?? '',
        productName: j['productName'] as String? ?? 'Unbekannt',
        artikelnummer: j['artikelnummer'] as String? ?? '',
        startZeit: j['startZeit'] as String?,
        dauerMinuten: (j['dauerMinuten'] as num?)?.toDouble() ?? 0,
        mengeKg: (j['mengeKg'] as num?)?.toDouble() ?? 0,
        sortierung: (j['sortierung'] as num?)?.toInt() ?? 0,
        status: j['status'] as String? ?? 'geplant',
        kettenId: j['kettenId'] as String? ?? '',
        erledigt: Erledigt.values.asNameMap()[j['erledigt'] as String?],
        auftraege: (j['auftraege'] as num?)?.toInt() ?? 1,
      );
}

/// Eine sonstige Aufgabe des archivierten Boards.
class ArchivAufgabe {
  const ArchivAufgabe({
    required this.abteilung,
    required this.datum,
    required this.inhalt,
    this.erledigt = false,
  });

  /// dbValue der Abteilung.
  final String abteilung;

  /// Tag, 00:00 Uhr.
  final DateTime datum;
  final String inhalt;
  final bool erledigt;

  Map<String, dynamic> toJson() => {
        'abteilung': abteilung,
        'datum': datum.toIso8601String(),
        'inhalt': inhalt,
        'erledigt': erledigt,
      };

  factory ArchivAufgabe.fromJson(Map<String, dynamic> j) => ArchivAufgabe(
        abteilung: j['abteilung'] as String,
        datum: DateTime.parse(j['datum'] as String),
        inhalt: j['inhalt'] as String? ?? '',
        erledigt: j['erledigt'] as bool? ?? false,
      );
}

/// Vor- und Folgestufe einer Kette außerhalb der archivierten Woche.
class ArchivKettenNachbar {
  const ArchivKettenNachbar({this.vorher, this.nachher});

  final ArchivKettenSchritt? vorher;
  final ArchivKettenSchritt? nachher;

  Map<String, dynamic> toJson() => {
        if (vorher != null) 'vorher': vorher?.toJson(),
        if (nachher != null) 'nachher': nachher?.toJson(),
      };

  factory ArchivKettenNachbar.fromJson(Map<String, dynamic> j) {
    final v = j['vorher'] as Map<String, dynamic>?;
    final n = j['nachher'] as Map<String, dynamic>?;
    return ArchivKettenNachbar(
      vorher: v == null ? null : ArchivKettenSchritt.fromJson(v),
      nachher: n == null ? null : ArchivKettenSchritt.fromJson(n),
    );
  }
}

/// Ein Schritt einer Kette in einer anderen Woche.
class ArchivKettenSchritt {
  const ArchivKettenSchritt({
    required this.abteilung,
    required this.datum,
    required this.kw,
  });

  /// dbValue der Abteilung.
  final String abteilung;

  /// Tag, 00:00 Uhr.
  final DateTime datum;

  /// ISO-Kalenderwoche des Schritts.
  final int kw;

  Map<String, dynamic> toJson() => {
        'abteilung': abteilung,
        'datum': datum.toIso8601String(),
        'kw': kw,
      };

  factory ArchivKettenSchritt.fromJson(Map<String, dynamic> j) =>
      ArchivKettenSchritt(
        abteilung: j['abteilung'] as String,
        datum: DateTime.parse(j['datum'] as String),
        kw: (j['kw'] as num?)?.toInt() ?? 0,
      );
}

/// Die dekodierten Inhalte eines Wochen-Snapshots inkl. einfacher Kennzahlen.
class WochenSnapshotDaten {
  const WochenSnapshotDaten({
    required this.tasks,
    required this.kapazitaeten,
    this.zusatzzeiten = const [],
    this.plan,
  });

  final List<SnapshotTask> tasks;

  /// Tageskapazität je Abteilung (dbValue → Minuten), wie sie zum Zeitpunkt
  /// des Einfrierens galt.
  final Map<String, double> kapazitaeten;
  final List<SnapshotZusatzzeit> zusatzzeiten;

  /// Der Wochenplan, wie er im Board stand — null bei Wochen, die vor
  /// Einführung des Plans archiviert wurden.
  final ArchivPlan? plan;

  Map<String, dynamic> toJson() {
    final p = plan;
    return {
      'tasks': [for (final t in tasks) t.toJson()],
      'kapazitaeten': kapazitaeten,
      'zusatzzeiten': [for (final z in zusatzzeiten) z.toJson()],
      if (p != null) 'plan': p.toJson(),
    };
  }

  factory WochenSnapshotDaten.fromJson(Map<String, dynamic> j) {
    final rawTasks = (j['tasks'] as List<dynamic>? ?? const []);
    final rawKap = (j['kapazitaeten'] as Map<String, dynamic>? ?? const {});
    final rawZusatz = (j['zusatzzeiten'] as List<dynamic>? ?? const []);
    final rawPlan = j['plan'] as Map<String, dynamic>?;
    return WochenSnapshotDaten(
      tasks: [
        for (final t in rawTasks)
          SnapshotTask.fromJson(t as Map<String, dynamic>),
      ],
      kapazitaeten: {
        for (final e in rawKap.entries) e.key: (e.value as num).toDouble(),
      },
      zusatzzeiten: [
        for (final z in rawZusatz)
          SnapshotZusatzzeit.fromJson(z as Map<String, dynamic>),
      ],
      plan: rawPlan == null ? null : ArchivPlan.fromJson(rawPlan),
    );
  }

  // ── Kennzahlen (für die Auswertung) ──────────────────────────────────────

  /// Geplante Minuten je Abteilung (Summe über die Woche).
  Map<String, double> get belegtMinutenJeAbteilung {
    final m = <String, double>{};
    for (final t in tasks) {
      m[t.abteilung] = (m[t.abteilung] ?? 0) + t.dauerMinuten;
    }
    for (final z in zusatzzeiten) {
      final abteilung = z.spurId.split('|').first;
      m[abteilung] = (m[abteilung] ?? 0) + z.minuten;
    }
    return m;
  }

  Map<String, double> get zusatzMinutenJeAbteilung {
    final m = <String, double>{};
    for (final z in zusatzzeiten) {
      final abteilung = z.spurId.split('|').first;
      m[abteilung] = (m[abteilung] ?? 0) + z.minuten;
    }
    return m;
  }

  /// Durchgesetzte kg je Abteilung (Summe der Auftragsmengen der Abteilung).
  Map<String, double> get kgJeAbteilung {
    final m = <String, double>{};
    for (final t in tasks) {
      m[t.abteilung] = (m[t.abteilung] ?? 0) + t.mengeKg;
    }
    return m;
  }

  /// Anzahl Aufträge je Abteilung.
  Map<String, int> get auftraegeJeAbteilung {
    final m = <String, int>{};
    for (final t in tasks) {
      m[t.abteilung] = (m[t.abteilung] ?? 0) + 1;
    }
    return m;
  }

  double get gesamtBelegtMinuten =>
      tasks.fold<double>(0, (summe, t) => summe + t.dauerMinuten) +
      zusatzzeiten.fold<double>(0, (summe, z) => summe + z.minuten);

  int get anzahlAuftraege => tasks.length;
}

// ═══════════════════════════════════════════════════════════════════════════
// Service-Funktionen
// ═══════════════════════════════════════════════════════════════════════════

/// Friert die Woche, in die [wochenStart] fällt, als unveränderlichen Snapshot
/// ein. [kapazitaeten] sind die aktuell gültigen Tageskapazitäten je Abteilung
/// (dbValue → Minuten) — sie werden mitgespeichert, damit die Auslastung später
/// stabil bleibt.
///
/// [plan] ist der Wochenplan, wie ihn das Board gerade zeigt — daraus
/// entsteht im Archiv die Ansicht „Wochenplan".
Future<void> erstelleWochenSnapshot({
  required AppDatabase db,
  required DateTime wochenStart,
  required Map<String, double> kapazitaeten,
  String? titel,
  ArchivPlan? plan,
}) async {
  final start = montagDerWoche(wochenStart);
  final endeExkl = tagPlus(start, 7);

  final rows = await (db.select(db.productionTasks)
        ..where((t) => t.deletedAt.isNull())
        ..where((t) => t.datum.isBiggerOrEqualValue(start))
        ..where((t) => t.datum.isSmallerThanValue(endeExkl))
        ..where((t) => t.status.isNotIn(const ['storniert'])))
      .get();

  final productIds = rows.map((t) => t.productId).toSet().toList();
  final produkte = productIds.isEmpty
      ? <Product>[]
      : await (db.select(db.products)..where((p) => p.id.isIn(productIds)))
          .get();
  final nameById = {for (final p in produkte) p.id: p.artikelbezeichnung};

  final tasks = [
    for (final t in rows)
      SnapshotTask(
        abteilung: t.abteilung,
        productId: t.productId,
        productName: nameById[t.productId] ?? 'Unbekannt',
        datum: DateTime(t.datum.year, t.datum.month, t.datum.day),
        dauerMinuten: t.geplanteDauerMinuten,
        mitarbeiter: t.geplanteMitarbeiter,
        mengeKg: t.mengeKg,
        startZeit: t.startZeit,
        notizen: t.notizen,
      ),
  ];

  final zusatzRows = await (db.select(db.zusatzzeiten)
        ..where((z) => z.deletedAt.isNull())
        ..where((z) => z.datum.isBiggerOrEqualValue(start))
        ..where((z) => z.datum.isSmallerThanValue(endeExkl)))
      .get();
  final zusatzzeiten = [
    for (final z in zusatzRows)
      SnapshotZusatzzeit(
        datum: DateTime(z.datum.year, z.datum.month, z.datum.day),
        spurId: z.spurId,
        art: z.art,
        minuten: z.minuten,
        notiz: z.notiz,
      ),
  ];

  final daten = WochenSnapshotDaten(
    tasks: tasks,
    kapazitaeten: kapazitaeten,
    zusatzzeiten: zusatzzeiten,
    plan: plan,
  );

  await db.into(db.weekSnapshots).insert(
        WeekSnapshotsCompanion.insert(
          id: const Uuid().v4(),
          wochenStart: start,
          kw: isoKalenderwoche(start),
          jahr: start.year,
          datenJson: jsonEncode(daten.toJson()),
          titel: Value(titel),
        ),
      );
}

/// Dekodiert die eingefrorenen Daten eines Snapshots.
WochenSnapshotDaten dekodiereSnapshot(WeekSnapshot snap) =>
    WochenSnapshotDaten.fromJson(
      jsonDecode(snap.datenJson) as Map<String, dynamic>,
    );

/// Löscht einen Snapshot (Soft-Delete).
Future<void> loescheWochenSnapshot(AppDatabase db, String id) async {
  await (db.update(db.weekSnapshots)..where((s) => s.id.equals(id))).write(
    WeekSnapshotsCompanion(
      deletedAt: Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
    ),
  );
}

/// Aktualisiert die freie Notiz/Erkenntnis eines Snapshots.
Future<void> aktualisiereSnapshotNotiz(
  AppDatabase db,
  String id,
  String? notiz,
) async {
  await (db.update(db.weekSnapshots)..where((s) => s.id.equals(id))).write(
    WeekSnapshotsCompanion(
      notiz: Value(notiz == null || notiz.isEmpty ? null : notiz),
      updatedAt: Value(DateTime.now()),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Provider
// ═══════════════════════════════════════════════════════════════════════════

/// Liste aller Snapshots, neueste Woche zuerst.
final weekSnapshotsProvider =
    FutureProvider<List<WeekSnapshot>>((ref) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.weekSnapshots)
        ..where((s) => s.deletedAt.isNull())
        ..orderBy([(s) => OrderingTerm.desc(s.wochenStart)]))
      .get();
});

/// Einzelner Snapshot nach ID.
final weekSnapshotProvider =
    FutureProvider.family<WeekSnapshot?, String>((ref, id) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.weekSnapshots)..where((s) => s.id.equals(id)))
      .getSingleOrNull();
});

// ═══════════════════════════════════════════════════════════════════════════
// Datums-Helfer
// ═══════════════════════════════════════════════════════════════════════════

/// Montag der Woche von [d], normalisiert auf 00:00 Uhr.
DateTime montagDerWoche(DateTime d) => tagPlus(d, -(d.weekday - 1));



