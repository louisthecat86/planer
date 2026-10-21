import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/database/database.dart';
import '../../../core/utils/fehler_text.dart';
import '../../../core/utils/format.dart';
import '../daten/dateien.dart';

// Angehängte Dateien öffnen, speichern und hinzufügen. Zum Öffnen wird der
// Inhalt entschlüsselt in einen eigenen Ordner unter den temporären
// Dateien gelegt; beim Sperren der Produktentwicklung wird er geleert.

/// Der Inhalt einer Datei, entschlüsselt — für Vorschaubilder.
final dateiInhaltProvider =
    FutureProvider.autoDispose.family<Uint8List?, String>(
  (ref, dateiId) => ref.watch(entwicklungDateienProvider).lesen(dateiId),
);

/// „12 KB", „3,4 MB".
String groesseText(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${Format.zahl(bytes / 1024)} KB';
  return '${Format.zahl(bytes / (1024 * 1024), nachkomma: 1)} MB';
}

/// Der Medientyp nach der Endung — null, wenn sie unbekannt ist.
String? mimeTypAus(String name) {
  switch (p.extension(name).toLowerCase()) {
    case '.pdf':
      return 'application/pdf';
    case '.png':
      return 'image/png';
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg';
    case '.gif':
      return 'image/gif';
    case '.webp':
      return 'image/webp';
    case '.txt':
      return 'text/plain';
    case '.csv':
      return 'text/csv';
    case '.msg':
      return 'application/vnd.ms-outlook';
    case '.eml':
      return 'message/rfc822';
    case '.xlsx':
      return 'application/vnd.openxmlformats-officedocument.'
          'spreadsheetml.sheet';
    case '.xls':
      return 'application/vnd.ms-excel';
    case '.docx':
      return 'application/vnd.openxmlformats-officedocument.'
          'wordprocessingml.document';
    case '.doc':
      return 'application/msword';
  }
  return null;
}

/// Ist die Datei ein Bild, das sich in der App zeigen lässt?
bool istBild(EntwicklungsDatei d) {
  final mime = d.mimeTyp ?? mimeTypAus(d.name) ?? '';
  return mime.startsWith('image/');
}

/// Ein Symbol passend zur Art der Datei.
IconData dateiSymbol(String name, String? mimeTyp) {
  final mime = mimeTyp ?? mimeTypAus(name) ?? '';
  if (mime.startsWith('image/')) return Icons.image_outlined;
  if (mime == 'application/pdf') return Icons.picture_as_pdf_outlined;
  if (mime.contains('outlook') || mime.startsWith('message/')) {
    return Icons.mail_outline;
  }
  if (mime.contains('sheet') || mime.contains('excel') || mime == 'text/csv') {
    return Icons.table_chart_outlined;
  }
  return Icons.insert_drive_file_outlined;
}

/// Der Ordner für entschlüsselte Dateien zum Öffnen.
Future<Directory> _tempOrdner() async {
  final basis = await getTemporaryDirectory();
  return Directory(p.join(basis.path, 'produktions_planer_entwicklung'));
}

/// Leert den Ordner mit entschlüsselten Dateien — so gut es geht: Was ein
/// anderes Programm noch offen hat, bleibt bis zum nächsten Mal.
Future<void> entwicklungTempLeeren() async {
  try {
    final ordner = await _tempOrdner();
    if (!await ordner.exists()) return;
    await for (final e in ordner.list()) {
      try {
        await e.delete(recursive: true);
      } on FileSystemException {
        // Noch geöffnet.
      }
    }
  } on Exception {
    // Kein temporärer Ordner (etwa im Test) — dann gibt es nichts zu tun.
  }
}

/// Ein Dateiname, den jedes Dateisystem annimmt.
String sichererDateiname(String name) {
  final sauber = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
  return sauber.isEmpty ? 'Datei' : sauber;
}

void _melde(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

/// Entschlüsselt die Datei in den temporären Ordner und öffnet sie mit
/// dem Programm, das das System dafür vorsieht.
Future<void> dateiOeffnen(
  BuildContext context,
  WidgetRef ref,
  EntwicklungsDatei datei,
) async {
  try {
    final inhalt = await ref.read(entwicklungDateienProvider).lesen(datei.id);
    if (inhalt == null) {
      if (context.mounted) _melde(context, 'Der Inhalt der Datei fehlt.');
      return;
    }
    final ordner = Directory(p.join((await _tempOrdner()).path, datei.id));
    await ordner.create(recursive: true);
    final ziel = File(p.join(ordner.path, sichererDateiname(datei.name)));
    await ziel.writeAsBytes(inhalt, flush: true);
    if (Platform.isWindows) {
      await Process.run('explorer', [ziel.path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [ziel.path]);
    } else {
      await Process.run('xdg-open', [ziel.path]);
    }
  } catch (e) {
    if (context.mounted) {
      _melde(context, 'Die Datei ließ sich nicht öffnen: ${fehlerText(e)}');
    }
  }
}

/// Speichert die Datei entschlüsselt an einem Ort, den man wählt.
Future<void> dateiSpeichernUnter(
  BuildContext context,
  WidgetRef ref,
  EntwicklungsDatei datei,
) async {
  try {
    final inhalt = await ref.read(entwicklungDateienProvider).lesen(datei.id);
    if (inhalt == null) {
      if (context.mounted) _melde(context, 'Der Inhalt der Datei fehlt.');
      return;
    }
    final pfad = await FilePicker.saveFile(
      dialogTitle: 'Datei speichern',
      fileName: sichererDateiname(datei.name),
    );
    if (pfad == null) return;
    await File(pfad).writeAsBytes(inhalt, flush: true);
    if (context.mounted) _melde(context, 'Gespeichert: $pfad');
  } catch (e) {
    if (context.mounted) {
      _melde(context, 'Die Datei ließ sich nicht speichern: ${fehlerText(e)}');
    }
  }
}

/// Eine gewählte Datei, noch nicht gespeichert.
typedef GewaehlteDatei = ({String name, Uint8List inhalt});

/// Lässt eine Datei wählen und liest sie. null bei Abbruch oder Fehler.
Future<GewaehlteDatei?> dateiWaehlen(
  BuildContext context, {
  bool nurBilder = false,
}) async {
  final gewaehlt = await FilePicker.pickFiles(
    dialogTitle: nurBilder ? 'Bild wählen' : 'Datei wählen',
    type: nurBilder ? FileType.image : FileType.any,
    withData: true,
  );
  if (gewaehlt == null || gewaehlt.files.isEmpty) return null;
  final datei = gewaehlt.files.first;
  var bytes = datei.bytes;
  final pfad = datei.path;
  if (bytes == null && pfad != null) {
    try {
      bytes = await File(pfad).readAsBytes();
    } on FileSystemException {
      bytes = null;
    }
  }
  if (bytes == null) {
    if (context.mounted) {
      _melde(context, 'Die gewählte Datei ließ sich nicht lesen.');
    }
    return null;
  }
  return (name: datei.name, inhalt: bytes);
}

/// Speichert eine gewählte Datei verschlüsselt und gibt ihre ID zurück.
Future<String> dateiAblegen(
  WidgetRef ref,
  GewaehlteDatei datei, {
  String? projektId,
}) =>
    ref.read(entwicklungDateienProvider).speichern(
          name: datei.name,
          inhalt: datei.inhalt,
          projektId: projektId,
          mimeTyp: mimeTypAus(datei.name),
        );
