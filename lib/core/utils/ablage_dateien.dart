import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

// Was auf das Fenster gezogen und losgelassen wurde, lesen — und die
// Kopien wegräumen, die das Fenster dafür angelegt hat (Mails aus Outlook
// gibt es vorher nirgends als Datei). Siehe core/ui/ablage.dart und
// windows/runner/ablage_ziel.cpp.

/// Eine abgelegte Datei, gelesen.
typedef AbgelegteDatei = ({String name, Uint8List inhalt});

/// Der Name des Ordners unter den temporären Dateien, in den das Fenster
/// Mails aus Outlook schreibt.
const String kAblageOrdner = 'planer_ablage';

/// Räumt die Kopien weg, die das Fenster für das Ablegen angelegt hat —
/// nur in seinem eigenen Ordner unter [kAblageOrdner].
Future<void> ablageAufraeumen(List<String> pfade) async {
  final ordner = <String>{};
  for (final pfad in pfade) {
    final o = p.dirname(pfad);
    if (p.basename(p.dirname(o)) != kAblageOrdner) continue;
    ordner.add(o);
  }
  for (final o in ordner) {
    try {
      await Directory(o).delete(recursive: true);
    } on FileSystemException {
      // Noch offen — beim nächsten Mal.
    }
  }
}

/// Liest die Dateien unter [pfade]. Ordner und Unlesbares stehen in
/// `fehlt`.
Future<({List<AbgelegteDatei> dateien, List<String> fehlt})> ablageLesen(
  List<String> pfade,
) async {
  final dateien = <AbgelegteDatei>[];
  final fehlt = <String>[];
  for (final pfad in pfade) {
    final name = p.basename(pfad);
    try {
      if (await FileSystemEntity.isDirectory(pfad)) {
        fehlt.add('$name (Ordner)');
        continue;
      }
      dateien.add((name: name, inhalt: await File(pfad).readAsBytes()));
    } on FileSystemException {
      fehlt.add(name);
    }
  }
  return (dateien: dateien, fehlt: fehlt);
}

/// Der Ordner, in den das Fenster Kopien zum Ablegen schreibt.
Directory ablageOrdner() =>
    Directory(p.join(Directory.systemTemp.path, kAblageOrdner));

/// Räumt Kopien weg, die von früher liegen geblieben sind — Ordner in
/// [basis] (sonst [ablageOrdner]), die älter sind als [alter].
Future<void> ablageAltesWegraeumen({
  Directory? basis,
  Duration alter = const Duration(hours: 1),
  DateTime? jetzt,
}) async {
  final ordner = basis ?? ablageOrdner();
  final grenze = (jetzt ?? DateTime.now()).subtract(alter);
  try {
    if (!await ordner.exists()) return;
    await for (final e in ordner.list()) {
      if (e is! Directory) continue;
      try {
        if ((await e.stat()).modified.isBefore(grenze)) {
          await e.delete(recursive: true);
        }
      } on FileSystemException {
        // Noch offen — beim nächsten Mal.
      }
    }
  } on FileSystemException {
    // Kein temporärer Ordner — dann gibt es nichts zu tun.
  }
}
