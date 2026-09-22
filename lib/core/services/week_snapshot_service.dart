import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';
import '../providers/database_provider.dart';
import '../utils/kalenderwoche.dart';

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

/// Die dekodierten Inhalte eines Wochen-Snapshots inkl. einfacher Kennzahlen.
class WochenSnapshotDaten {
  const WochenSnapshotDaten({
    required this.tasks,
    required this.kapazitaeten,
    this.zusatzzeiten = const [],
  });

  final List<SnapshotTask> tasks;

  /// Tageskapazität je Abteilung (dbValue → Minuten), wie sie zum Zeitpunkt
  /// des Einfrierens galt.
  final Map<String, double> kapazitaeten;
  final List<SnapshotZusatzzeit> zusatzzeiten;

  Map<String, dynamic> toJson() => {
        'tasks': [for (final t in tasks) t.toJson()],
        'kapazitaeten': kapazitaeten,
        'zusatzzeiten': [for (final z in zusatzzeiten) z.toJson()],
      };

  factory WochenSnapshotDaten.fromJson(Map<String, dynamic> j) {
    final rawTasks = (j['tasks'] as List<dynamic>? ?? const []);
    final rawKap = (j['kapazitaeten'] as Map<String, dynamic>? ?? const {});
    final rawZusatz = (j['zusatzzeiten'] as List<dynamic>? ?? const []);
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
      tasks.fold(0, (summe, t) => summe + t.dauerMinuten) +
      zusatzzeiten.fold(0, (summe, z) => summe + z.minuten);

  int get anzahlAuftraege => tasks.length;
}

// ═══════════════════════════════════════════════════════════════════════════
// Service-Funktionen
// ═══════════════════════════════════════════════════════════════════════════

/// Friert die Woche, in die [wochenStart] fällt, als unveränderlichen Snapshot
/// ein. [kapazitaeten] sind die aktuell gültigen Tageskapazitäten je Abteilung
/// (dbValue → Minuten) — sie werden mitgespeichert, damit die Auslastung später
/// stabil bleibt.
Future<void> erstelleWochenSnapshot({
  required AppDatabase db,
  required DateTime wochenStart,
  required Map<String, double> kapazitaeten,
  String? titel,
}) async {
  final start = montagDerWoche(wochenStart);
  final endeExkl = start.add(const Duration(days: 7));

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
DateTime montagDerWoche(DateTime d) {
  final tag = DateTime(d.year, d.month, d.day);
  return tag.subtract(Duration(days: tag.weekday - 1));
}



