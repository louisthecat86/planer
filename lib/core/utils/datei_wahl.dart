import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'ablage_dateien.dart';

// Eine Datei zum Einlesen holen — über den Dateidialog oder aufs Fenster
// gezogen.
//
// Der Dateidialog öffnet je Art von Datei in dem Ordner, aus dem zuletzt
// eine solche Datei kam: Der Navision-Bericht liegt woanders als das
// Ergebnis vom Handy, und Windows merkt sich für das ganze Programm nur
// einen Ordner — den vom letzten Speichern oder Öffnen, egal wovon.

/// Wofür eine Datei eingelesen wird. Je Art merkt sich die App den Ordner.
enum EinleseArt {
  /// Navision-Bericht „Auftragsbestand".
  auftragsbestand('auftragsbestand'),

  /// Artikelübersicht aus Navision.
  navisionArtikel('navision_artikel'),

  /// Ergebnis-Datei der Handy-Erfassung.
  handyErgebnis('handy_ergebnis');

  const EinleseArt(this.kennung);

  /// Teil des Schlüssels in den Einstellungen — nicht ändern, sonst sind
  /// die gemerkten Ordner weg.
  final String kennung;
}

/// Der Ordner, aus dem zuletzt eine Datei dieser Art kam.
///
/// In den SharedPreferences und nicht in `app_settings`: Der Pfad gehört
/// zum Rechner — ein Backup soll ihn nicht auf einen anderen tragen.
class GemerkterOrdner {
  const GemerkterOrdner._();

  static String _schluessel(EinleseArt art) => 'einlese_ordner_${art.kennung}';

  /// Der gemerkte Ordner — null, wenn es keinen gibt oder er inzwischen
  /// fehlt (Netzlaufwerk nicht verbunden, Ordner umbenannt). Dann öffnet
  /// der Dateidialog dort, wo Windows ihn hinstellt.
  static Future<String?> lesen(EinleseArt art) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ordner = prefs.getString(_schluessel(art));
      if (ordner == null || ordner.trim().isEmpty) return null;
      return await Directory(ordner).exists() ? ordner : null;
    } catch (_) {
      return null;
    }
  }

  /// Merkt den Ordner, in dem [dateiPfad] liegt. Ohne Pfad bleibt alles,
  /// wie es ist.
  static Future<void> merken(EinleseArt art, String? dateiPfad) async {
    if (dateiPfad == null || dateiPfad.trim().isEmpty) return;
    final ordner = p.dirname(dateiPfad);
    if (ordner.isEmpty || ordner == '.') return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_schluessel(art), ordner);
    } catch (_) {
      // Dann eben beim nächsten Mal — am Einlesen ändert das nichts.
    }
  }
}

/// Eine über den Dateidialog gewählte Datei. [inhalt] ist null, wenn sie
/// sich nicht lesen ließ.
typedef GewaehlteDatei = ({String name, Uint8List? inhalt});

/// Öffnet den Dateidialog für eine Datei mit einer der [endungen] (ohne
/// Punkt) — in dem Ordner, aus dem zuletzt eine Datei dieser [art] kam —
/// und liest sie. null, wenn niemand etwas gewählt hat.
Future<GewaehlteDatei?> dateiWaehlen({
  required EinleseArt art,
  required List<String> endungen,
  String? titel,
}) async {
  final gewaehlt = await FilePicker.pickFiles(
    dialogTitle: titel,
    initialDirectory: await GemerkterOrdner.lesen(art),
    type: FileType.custom,
    allowedExtensions: endungen,
    withData: true,
  );
  final datei =
      gewaehlt == null || gewaehlt.files.isEmpty ? null : gewaehlt.files.first;
  if (datei == null) return null;
  final pfad = datei.path;
  await GemerkterOrdner.merken(art, pfad);
  var inhalt = datei.bytes;
  // Füllt eine Plattform die Bytes trotz withData nicht, liefert aber
  // einen Pfad, wird die Datei selbst gelesen.
  if (inhalt == null && pfad != null) {
    try {
      inhalt = await File(pfad).readAsBytes();
    } catch (_) {
      inhalt = null;
    }
  }
  return (name: datei.name, inhalt: inhalt);
}

/// Die erste der aufs Fenster gezogenen [dateien] mit einer der
/// [endungen] (ohne Punkt, Groß- und Kleinschreibung egal) — null, wenn
/// keine passt.
AbgelegteDatei? ersteMitEndung(
  List<AbgelegteDatei> dateien,
  List<String> endungen,
) {
  final erlaubt = {for (final e in endungen) '.${e.toLowerCase()}'};
  for (final d in dateien) {
    if (erlaubt.contains(p.extension(d.name).toLowerCase())) return d;
  }
  return null;
}

/// Meldung, wenn nichts Passendes aufs Fenster gezogen wurde: „Hier lässt
/// sich nur eine .xlsx-Datei einlesen."
String falscheDateiText(List<String> endungen) {
  final arten = [for (final e in endungen) '.${e.toLowerCase()}'];
  final was = arten.length == 1
      ? 'eine ${arten.single}-Datei'
      : 'eine Datei mit ${arten.join(' oder ')}';
  return 'Hier lässt sich nur $was einlesen.';
}
