import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart';

import '../database/database.dart';
import '../utils/krypto.dart';

// Die Ablage der angehängten Dateien der Produktentwicklung und der Fotos
// der Artikel neben den Backups: Jede Datei liegt dort einmal, benannt
// nach der Prüfsumme ihres Inhalts. Ein Auto-Backup nennt nur noch die
// Prüfsummen — eine PDF von 5 MB steht nicht mehr in jedem Backup, sondern
// einmal hier.
//
// Abgelegt wird der Inhalt so, wie er in der Datenbank steht: Die Dateien
// der Produktentwicklung mit dem Datenschlüssel verschlüsselt — ohne ihr
// Passwort lässt sich hier so wenig lesen wie im Backup selbst. Die Fotos
// der Artikel (FotoSicherung) liegen offen da, wie die übrigen
// Produktionsdaten im Backup.

/// Ab dieser Größe wird die Prüfsumme auf einem eigenen Isolate berechnet.
const int _imHintergrundAb = 256 * 1024;

/// Die Prüfsumme von [daten] — große Inhalte auf einem eigenen Isolate,
/// damit das Fenster nicht steht.
Future<String> pruefsummeVon(Uint8List daten) => daten.length < _imHintergrundAb
    ? Future.value(pruefsumme(daten))
    : Isolate.run(() => pruefsumme(daten));

/// Was beim Zurückholen herauskam: die Inhalte je Datei-ID und die IDs,
/// deren Inhalt nirgends zu finden war.
typedef AufgeloesteDateien = ({
  Map<String, Uint8List> dateien,
  List<String> fehlen,
});

/// Eine Ablage: ein Ordner mit je einer Datei `<Prüfsumme>.bin`.
class DateiAblage {
  DateiAblage(this.ordner);

  /// Die Ablage im Backup-Ordner [backupOrdner].
  factory DateiAblage.neben(Directory backupOrdner) => DateiAblage(
        Directory(
          '${backupOrdner.path}${Platform.pathSeparator}$ordnerName',
        ),
      );

  /// Name des Ordners neben den Backups.
  static const String ordnerName = 'planer_dateien';

  static const String _endung = '.bin';
  static const String _zwischen = '.tmp';
  static final RegExp _summe = RegExp(r'^[0-9a-f]{64}$');

  final Directory ordner;

  File _datei(String summe) =>
      File('${ordner.path}${Platform.pathSeparator}$summe$_endung');

  /// Liegt ein Inhalt unter [summe]?
  Future<bool> hat(String summe) async =>
      _summe.hasMatch(summe) && await _datei(summe).exists();

  /// Legt [inhalt] unter [summe] ab, wenn es ihn dort noch nicht gibt.
  /// Erst in eine Zwischendatei, dann umbenannt — so steht unter dem
  /// richtigen Namen nie eine halbe Datei.
  Future<void> ablegen(String summe, Uint8List inhalt) async {
    if (!_summe.hasMatch(summe)) {
      throw ArgumentError('Keine Prüfsumme: $summe');
    }
    final ziel = _datei(summe);
    if (await ziel.exists()) return;
    await ordner.create(recursive: true);
    final zwischen = File('${ziel.path}$_zwischen');
    await zwischen.writeAsBytes(inhalt, flush: true);
    try {
      await zwischen.rename(ziel.path);
    } on FileSystemException {
      // Inzwischen von anderswo abgelegt — etwa vom zweiten Rechner im
      // selben Ordner: gleicher Name, also gleicher Inhalt.
      if (!await ziel.exists()) rethrow;
      try {
        await zwischen.delete();
      } on FileSystemException {
        // Bleibt liegen; das Aufräumen nimmt sie mit.
      }
    }
  }

  /// Der Inhalt unter [summe] — null, wenn er fehlt oder nicht mehr zur
  /// Prüfsumme passt.
  Future<Uint8List?> lesen(String summe) async {
    if (!_summe.hasMatch(summe)) return null;
    try {
      final datei = _datei(summe);
      if (!await datei.exists()) return null;
      final inhalt = await datei.readAsBytes();
      return await pruefsummeVon(inhalt) == summe ? inhalt : null;
    } on FileSystemException {
      return null;
    }
  }

  /// Legt die Inhalte aller angehängten Dateien aus [db] ab, die hier noch
  /// fehlen, und gibt je Datei-ID die Prüfsumme zurück.
  ///
  /// Gelesen wird nur, was noch nicht in der Ablage liegt oder noch keine
  /// Prüfsumme hat — die trägt die Datenbank dann nach. Alle übrigen
  /// Inhalte bleiben, wo sie sind: Ihre Prüfsumme steht schon bei den
  /// Angaben der Datei.
  Future<Map<String, String>> auslagern(AppDatabase db) async {
    final summen = <String, String?>{
      for (final d in await db.select(db.entwicklungDateien).get())
        d.id: d.pruefsumme,
    };
    final t = db.entwicklungDateiInhalte;
    // Nur die IDs — die Inhalte selbst bleiben in der Datenbank.
    final ids = await (db.selectOnly(t)..addColumns([t.dateiId]))
        .map((z) => z.read(t.dateiId)!)
        .get();
    final verweise = <String, String>{};
    for (final id in ids) {
      var summe = summen[id];
      if (summe == null || !await hat(summe)) {
        final zeile = await (db.select(t)..where((i) => i.dateiId.equals(id)))
            .getSingleOrNull();
        if (zeile == null) continue;
        final echt = await pruefsummeVon(zeile.inhalt);
        await ablegen(echt, zeile.inhalt);
        if (summen.containsKey(id) && summe != echt) {
          await (db.update(db.entwicklungDateien)
                ..where((d) => d.id.equals(id)))
              .write(EntwicklungDateienCompanion(pruefsumme: Value(echt)));
        }
        summe = echt;
      }
      verweise[id] = summe;
    }
    return verweise;
  }

  /// Holt die Inhalte zu [verweise] (Datei-ID → Prüfsumme) zurück: aus
  /// den [ablagen] der Reihe nach — und wo keine ihn hat, aus [db], wenn
  /// dort unter derselben ID genau dieser Inhalt liegt.
  static Future<AufgeloesteDateien> aufloesen(
    Map<String, String> verweise, {
    required List<DateiAblage> ablagen,
    AppDatabase? db,
  }) async {
    final dateien = <String, Uint8List>{};
    final fehlen = <String>[];
    for (final MapEntry(key: id, value: summe) in verweise.entries) {
      Uint8List? inhalt;
      for (final ablage in ablagen) {
        inhalt = await ablage.lesen(summe);
        if (inhalt != null) break;
      }
      if (inhalt == null && db != null) {
        final zeile = await (db.select(db.entwicklungDateiInhalte)
              ..where((i) => i.dateiId.equals(id)))
            .getSingleOrNull();
        if (zeile != null && await pruefsummeVon(zeile.inhalt) == summe) {
          inhalt = zeile.inhalt;
        }
      }
      if (inhalt == null) {
        fehlen.add(id);
      } else {
        dateien[id] = inhalt;
      }
    }
    return (dateien: dateien, fehlen: fehlen);
  }

  /// Löscht, was kein Backup mehr braucht: Inhalte, deren Prüfsumme nicht
  /// in [gebraucht] steht, und liegengebliebene Zwischendateien — beides
  /// erst ab einem Alter von [mindestAlter]. Ein eben abgelegter Inhalt
  /// gehört womöglich zu einem Backup, das gerade noch geschrieben wird.
  /// Gibt zurück, wie viele Dateien gelöscht wurden.
  Future<int> aufraeumen(
    Set<String> gebraucht, {
    required DateTime jetzt,
    Duration mindestAlter = const Duration(days: 1),
  }) async {
    if (!await ordner.exists()) return 0;
    var geloescht = 0;
    await for (final eintrag in ordner.list()) {
      if (eintrag is! File) continue;
      final name = eintrag.path.split(Platform.pathSeparator).last;
      if (!name.endsWith(_zwischen)) {
        if (!name.endsWith(_endung)) continue;
        final summe = name.substring(0, name.length - _endung.length);
        if (!_summe.hasMatch(summe) || gebraucht.contains(summe)) continue;
      }
      try {
        if (jetzt.difference(await eintrag.lastModified()) < mindestAlter) {
          continue;
        }
        await eintrag.delete();
        geloescht++;
      } on FileSystemException {
        // Beim nächsten Mal.
      }
    }
    return geloescht;
  }
}
