import 'dart:io';

import 'package:erfassung_format/erfassung_format.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/datei_wahl.dart';

// Das Ergebnis vom Handy kommt meist per E-Mail: Der Anhang landet beim
// Speichern im Download-Ordner. Die Seite Handy-Erfassung sieht dort (und
// in dem Ordner, aus dem zuletzt ein Ergebnis kam) nach und bietet das
// neueste an, das noch nicht übernommen ist — ein Klick statt Suchen.
//
// Gelesen wird nur der Dateiname; die Datei selbst erst, wenn jemand sie
// einlesen will. Verschoben oder gelöscht wird nichts.

/// Ein Ergebnis vom Handy, das in einem der Ordner liegt.
typedef GefundenesErgebnis = ({
  String pfad,
  String name,

  /// Wann das Handy es erstellt hat — „2026-11-23_1410", aus dem Namen.
  String zeitstempel,
});

/// „Planer-Erfassung-Ergebnis_2026-11-23_1410_AB.json" — mit allem, was
/// ein E-Mail-Programm noch anhängt („ (1)").
final RegExp _name = RegExp(
  r'^Planer-Erfassung-Ergebnis_(\d{4}-\d{2}-\d{2}_\d{4})[^\\/]*\.json$',
  caseSensitive: false,
);

/// Der Zeitstempel aus dem Namen einer Ergebnis-Datei — null, wenn der
/// Name nicht danach aussieht.
String? zeitstempelAusName(String name) => _name.firstMatch(name)?.group(1);

/// Das neueste Ergebnis in [ordner], das nach [uebernommenBis] erstellt
/// wurde (Zeitstempel wie [zeitstempelText]) — null: keins.
Future<GefundenesErgebnis?> neuestesErgebnis(
  Iterable<Directory> ordner, {
  String? uebernommenBis,
}) async {
  GefundenesErgebnis? bestes;
  final gesehen = <String>{};
  for (final o in ordner) {
    if (!gesehen.add(p.normalize(o.absolute.path))) continue;
    try {
      if (!await o.exists()) continue;
      await for (final e in o.list(followLinks: false)) {
        if (e is! File) continue;
        final name = p.basename(e.path);
        final z = zeitstempelAusName(name);
        if (z == null) continue;
        if (uebernommenBis != null && z.compareTo(uebernommenBis) <= 0) {
          continue;
        }
        if (bestes == null || z.compareTo(bestes.zeitstempel) > 0) {
          bestes = (pfad: e.path, name: name, zeitstempel: z);
        }
      }
    } on FileSystemException {
      // Ordner nicht lesbar — dann eben nicht.
    }
  }
  return bestes;
}

const _schluessel = 'handy_ergebnis_uebernommen_bis';

/// Sucht im Download-Ordner und im Ordner, aus dem zuletzt ein Ergebnis
/// kam.
Future<GefundenesErgebnis?> ergebnisInDownloads() async {
  final ordner = <Directory>[];
  try {
    final d = await getDownloadsDirectory();
    if (d != null) ordner.add(d);
  } catch (_) {
    // Ohne Download-Ordner.
  }
  final zuletzt = await GemerkterOrdner.lesen(EinleseArt.handyErgebnis);
  if (zuletzt != null) ordner.add(Directory(zuletzt));
  String? bis;
  try {
    bis = (await SharedPreferences.getInstance()).getString(_schluessel);
  } catch (_) {
    bis = null;
  }
  return neuestesErgebnis(ordner, uebernommenBis: bis);
}

/// Merkt, dass das Ergebnis vom [erstellt] übernommen ist — ältere bietet
/// die Seite dann nicht mehr an.
Future<void> ergebnisUebernommen(DateTime erstellt) async {
  final z = zeitstempelText(erstellt);
  try {
    final prefs = await SharedPreferences.getInstance();
    final alt = prefs.getString(_schluessel);
    if (alt == null || z.compareTo(alt) > 0) {
      await prefs.setString(_schluessel, z);
    }
  } catch (_) {
    // Dann bietet die Seite es noch einmal an — Einlesen schadet nicht.
  }
}
