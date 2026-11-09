import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/entwicklung.dart';
import '../../../core/database/database.dart';
import '../../../core/providers/database_provider.dart';

// Angeheftete Projekte: Sie stehen auf der Übersicht oben bei „Zuletzt
// bearbeitet", auch wenn sich an ihnen lange nichts getan hat. Gemerkt
// wird das nur auf diesem Rechner (kEntwicklungNurLokal) — wie die Leiste,
// die jemand ein- oder ausgeklappt hat.

/// Die angehefteten Projekte (IDs), in der Reihenfolge des Anheftens.
class AngeheftetNotifier extends StateNotifier<List<String>> {
  /// Ohne [_db] (in Tests) wird nichts gespeichert.
  AngeheftetNotifier(this._db) : super(const <String>[]) {
    _laden();
  }

  final AppDatabase? _db;

  Future<void> _laden() async {
    final db = _db;
    if (db == null) return;
    try {
      final zeile = await (db.select(db.appSettings)
            ..where((t) => t.key.equals(kEntwicklungAngeheftet))
            ..limit(1))
          .getSingleOrNull();
      if (!mounted || zeile == null) return;
      state = idsAus(zeile.value);
    } catch (_) {
      // Ohne gemerkte Projekte geht es auch — angeheftet wird neu.
    }
  }

  /// Heftet [projektId] an oder löst es wieder.
  Future<void> umschalten(String projektId) async {
    state = state.contains(projektId)
        ? [
            for (final id in state)
              if (id != projektId) id,
          ]
        : [...state, projektId];
    final db = _db;
    if (db == null) return;
    await db.into(db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: kEntwicklungAngeheftet,
            value: jsonEncode(state),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  /// Die IDs aus dem gespeicherten Text — leer, wenn er sich nicht lesen
  /// lässt.
  static List<String> idsAus(String? text) {
    if (text == null || text.trim().isEmpty) return const <String>[];
    try {
      final daten = jsonDecode(text);
      if (daten is! List) return const <String>[];
      return [
        for (final id in daten)
          if (id is String && id.isNotEmpty) id,
      ];
    } on FormatException {
      return const <String>[];
    }
  }
}

final angehefteteProjekteProvider =
    StateNotifierProvider<AngeheftetNotifier, List<String>>(
  (ref) => AngeheftetNotifier(ref.watch(databaseProvider)),
);

/// Die Nadel zum Anheften eines Projekts auf der Übersicht.
class AnheftenKnopf extends ConsumerWidget {
  const AnheftenKnopf({super.key, required this.projektId});

  final String projektId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final an = ref.watch(angehefteteProjekteProvider).contains(projektId);
    final farben = Theme.of(context).colorScheme;
    return IconButton(
      key: ValueKey('anheften-$projektId'),
      tooltip: an ? 'Nicht mehr anheften' : 'Auf der Übersicht anheften',
      onPressed: () =>
          ref.read(angehefteteProjekteProvider.notifier).umschalten(projektId),
      icon: Icon(
        an ? Icons.push_pin : Icons.push_pin_outlined,
        size: 18,
        color: an ? farben.primary : farben.onSurfaceVariant,
      ),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }
}
