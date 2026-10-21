import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/providers/database_provider.dart';
import '../daten/dateien.dart';
import 'fliessdiagramm_dateien.dart';
import 'projekt_repository.dart';

// Die PDFs der Fließdiagramme: Jede Fassung liegt verschlüsselt bei den
// Entwicklungsdateien (siehe fliessdiagramm_dateien.dart) und wandert so
// mit ins Backup.

/// Eine gespeicherte Fassung eines Fließdiagramms.
typedef FdFassung = ({DateTime stand, EntwicklungsDatei datei});

/// Die Fassungen je Kennung, die neueste zuerst.
Map<String, List<FdFassung>> fassungenNachKennung(
  List<EntwicklungsDatei> dateien,
) {
  final ergebnis = <String, List<FdFassung>>{};
  for (final d in dateien) {
    final f = fdAusDateiId(d.id);
    if (f == null) continue;
    ergebnis.putIfAbsent(f.fdId, () => []).add((stand: f.stand, datei: d));
  }
  for (final liste in ergebnis.values) {
    liste.sort((a, b) => b.stand.compareTo(a.stand));
  }
  return ergebnis;
}

/// Fließdiagramme einlesen, ihre PDFs ablegen und löschen.
class FliessdiagrammDienst {
  FliessdiagrammDienst(this._db, this._dateien);

  final AppDatabase _db;
  final EntwicklungDateienDienst _dateien;

  ProjektRepository get _repo => ProjektRepository(_db);

  SimpleSelectStatement<$EntwicklungDateienTable, EntwicklungsDatei>
      _alleFassungen() => _db.select(_db.entwicklungDateien)
        ..where((d) => d.id.like('$kFdDateiPraefix%'));

  /// Die Fassungen je Kennung, die neueste zuerst.
  Stream<Map<String, List<FdFassung>>> fassungenBeobachten() =>
      _alleFassungen().watch().map(fassungenNachKennung);

  /// Die Fassungen eines Fließdiagramms, die neueste zuerst.
  Future<List<FdFassung>> fassungen(String fdId) async =>
      fassungenNachKennung(await _alleFassungen().get())[fdId] ?? const [];

  /// Liest PDFs ein (siehe [fdEinlesePlan]) und meldet nach jeder
  /// gespeicherten Datei, wie weit es ist.
  Future<FdEinlesePlan> einlesen(
    List<FdDatei> dateien, {
    DateTime? heute,
    void Function(int fertig, int gesamt)? fortschritt,
  }) async {
    final plan = fdEinlesePlan(
      dateien: dateien,
      bezeichnungen: {
        for (final f in await _db.select(_db.entwicklungFliessdiagramme).get())
          f.id: f.bezeichnung,
      },
      gespeichert: [
        for (final d in await _alleFassungen().get())
          (dateiId: d.id, name: d.name, groesse: d.groesse),
      ],
      heute: heute ?? DateTime.now(),
    );
    for (final f in [...plan.anlegen, ...plan.umbenennen]) {
      await _repo.fliessdiagrammSpeichern(id: f.id, bezeichnung: f.bezeichnung);
    }
    final gesamt = plan.speichern.length;
    fortschritt?.call(0, gesamt);
    var fertig = 0;
    for (final s in plan.speichern) {
      await _dateien.speichern(
        id: s.dateiId,
        name: s.datei.name,
        inhalt: s.datei.inhalt,
        mimeTyp: 'application/pdf',
      );
      fortschritt?.call(++fertig, gesamt);
    }
    return plan;
  }

  /// Hängt ein PDF als Fassung an das Fließdiagramm [fdId]. Den Stand
  /// sagt der Dateiname, sonst gilt [heute].
  Future<void> pdfHinzufuegen(
    String fdId,
    String name,
    List<int> inhalt, {
    DateTime? heute,
  }) {
    final stand = fdAusDateiname(name)?.stand ?? heute ?? DateTime.now();
    return _dateien.speichern(
      id: fdDateiId(fdId, DateTime(stand.year, stand.month, stand.day)),
      name: name,
      inhalt: inhalt,
      mimeTyp: 'application/pdf',
    );
  }

  /// Löscht alle Fassungen des Fließdiagramms [fdId].
  Future<void> pdfsLoeschen(String fdId) async {
    for (final f in await fassungen(fdId)) {
      await _dateien.loeschen(f.datei.id);
    }
  }
}

final fliessdiagrammDienstProvider = Provider<FliessdiagrammDienst>(
  (ref) => FliessdiagrammDienst(
    ref.watch(databaseProvider),
    ref.watch(entwicklungDateienProvider),
  ),
);

/// Die PDFs der Fließdiagramme je Kennung, die neueste Fassung zuerst.
final fliessdiagrammFassungenProvider =
    StreamProvider<Map<String, List<FdFassung>>>(
  (ref) => ref.watch(fliessdiagrammDienstProvider).fassungenBeobachten(),
);
