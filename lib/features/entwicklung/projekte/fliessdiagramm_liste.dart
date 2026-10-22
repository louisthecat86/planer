import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/database_provider.dart';
import '../daten/dateien.dart';

// Die Fließdiagramme als Auswahlliste: Kennung und Bezeichnung, etwa
// „FD_101 · Testware paniert". Die Diagramme selbst pflegt die
// Qualitätssicherung — hier steht nur, welches zu einem Produkt gehört.
// Die Liste gehört zu den Entwicklungsdaten (verschlüsselt im Backup) und
// steht nicht im Code: Jede Firma hat ihre eigene.

/// Unter diesem Präfix legten frühere Versionen PDFs der Fließdiagramme bei
/// den Entwicklungsdateien ab. Gebraucht werden sie nicht mehr — sie lassen
/// sich entfernen.
const String kFdPdfPraefix = 'fliessdiagramm:';

/// Liest eine eingefügte Liste: je Zeile Kennung und Bezeichnung, getrennt
/// durch Tabulator, Semikolon oder Leerzeichen — etwa
/// „FD_101 Testware natur". Leere Zeilen fallen weg, eine Kennung
/// zählt nur einmal; ohne Bezeichnung gilt die Kennung.
List<({String id, String bezeichnung})> fliessdiagrammeAusText(String text) {
  final ergebnis = <({String id, String bezeichnung})>[];
  final gesehen = <String>{};
  for (final roh in text.split(RegExp(r'\r?\n'))) {
    final zeile = roh.trim();
    if (zeile.isEmpty) continue;
    final trenner = RegExp(r'\t|;').firstMatch(zeile);
    final teile = zeile.split(RegExp(r'\s+'));
    // „FD_101:" — ein Doppelpunkt oder Strich am Ende gehört nicht dazu.
    final id = (trenner == null
            ? teile.first
            : zeile.substring(0, trenner.start).trim())
        .replaceFirst(RegExp(r'[-–:]+$'), '');
    // „FD_101 – Testware" oder „FD_101: Testware".
    final rest = (trenner == null
            ? teile.skip(1).join(' ')
            : zeile.substring(trenner.end))
        .trim()
        .replaceFirst(RegExp(r'^[-–:]\s*'), '')
        .trim();
    if (id.isEmpty || !gesehen.add(id)) continue;
    ergebnis.add((id: id, bezeichnung: rest.isEmpty ? id : rest));
  }
  return ergebnis;
}

/// „FD_101 · Testware paniert" — die Bezeichnung nur, wenn sie etwas
/// sagt.
String fdText(String id, {String? bezeichnung}) => [
      id,
      if (bezeichnung != null && bezeichnung.isNotEmpty && bezeichnung != id)
        bezeichnung,
    ].join(' · ');

/// Die IDs der PDFs, die frühere Versionen bei den Fließdiagrammen
/// ablegten.
final fliessdiagrammAltePdfsProvider = StreamProvider<List<String>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.entwicklungDateien)
        ..where((d) => d.id.like('$kFdPdfPraefix%')))
      .watch()
      .map((liste) => [for (final d in liste) d.id]);
});

/// Entfernt die PDFs [ids] samt Inhalt.
Future<void> fdAltePdfsEntfernen(
  EntwicklungDateienDienst dateien,
  List<String> ids,
) async {
  for (final id in ids) {
    await dateien.loeschen(id);
  }
}
