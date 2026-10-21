import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../../core/utils/format.dart';

// Fließdiagramme als PDF einlesen: aus einer ZIP-Datei oder einzeln.
//
// Der Dateiname trägt alles, was die App braucht — Kennung, Bezeichnung
// und den Stand: „FD_007 Schnitzel paniert 260731.pdf" ist FD_007,
// „Schnitzel paniert", Stand 31.07.2026. Ein „_" in der Bezeichnung steht
// für ein „/", das kein Dateiname tragen darf („frisch_TK" → „frisch/TK").
//
// Windows packt Dateinamen ohne Kennzeichen in der alten DOS-Codepage
// (850) — „ü" ist dort ein anderes Byte als in UTF-8. Die Namen werden
// deshalb aus dem Verzeichnis des ZIP selbst gelesen.
//
// Jede Fassung liegt bei den Entwicklungsdateien unter
// „fliessdiagramm:<Kennung>:<Stand>". Es gilt die neueste; ältere bleiben
// zum Nachsehen.

/// Was ein Dateiname über ein Fließdiagramm sagt.
typedef FdName = ({String id, String bezeichnung, DateTime? stand});

/// Eine eingelesene PDF-Datei.
typedef FdDatei = ({String name, Uint8List inhalt});

/// Liest Kennung, Bezeichnung und Stand aus einem Dateinamen — null,
/// wenn er nicht mit einer Kennung aus Großbuchstaben und Nummer wie
/// „FD_011" oder „FD 11" beginnt oder kein PDF ist.
FdName? fdAusDateiname(String dateiname) {
  var name = dateiname.replaceAll('\\', '/').split('/').last.trim();
  if (!name.toLowerCase().endsWith('.pdf')) return null;
  name = name.substring(0, name.length - 4).trim();
  final m =
      RegExp(r'^([A-Z]{1,6})[ _-]?(\d{1,4})(?![\d.])\s*[-–:_]?\s*(.*)$')
          .firstMatch(name);
  if (m == null) return null;
  final id = '${m[1]}_${m[2]}';
  var rest = m[3]!.trim();
  DateTime? stand;
  final datum = RegExp(r'[\s_-](\d{6}|\d{8}|\d{4}-\d{2}-\d{2})$')
      .firstMatch(' $rest');
  if (datum != null) {
    stand = _datumAus(datum[1]!);
    if (stand != null) {
      rest = rest.substring(0, rest.length - datum[1]!.length).trim();
    }
  }
  final bezeichnung = rest
      .replaceAll('_', '/')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[-–:/\s]+|[-–:/\s]+$'), '')
      .trim();
  return (
    id: id,
    bezeichnung: bezeichnung.isEmpty ? id : bezeichnung,
    stand: stand,
  );
}

/// „260731" (JJMMTT), „20260731" oder „2026-07-31" → Datum; null, wenn es
/// keins ist.
DateTime? _datumAus(String t) {
  int j;
  int m;
  int d;
  if (t.contains('-')) {
    final teile = t.split('-').map(int.parse).toList();
    (j, m, d) = (teile[0], teile[1], teile[2]);
  } else if (t.length == 8) {
    (j, m, d) = (
      int.parse(t.substring(0, 4)),
      int.parse(t.substring(4, 6)),
      int.parse(t.substring(6, 8)),
    );
  } else {
    (j, m, d) = (
      2000 + int.parse(t.substring(0, 2)),
      int.parse(t.substring(2, 4)),
      int.parse(t.substring(4, 6)),
    );
  }
  if (m < 1 || m > 12 || d < 1 || d > 31 || j < 1990 || j > 2100) return null;
  final datum = DateTime(j, m, d);
  // 31.02. gibt es nicht — DateTime rechnet es in den März.
  return datum.month == m && datum.day == d ? datum : null;
}

/// Die Zeichen 0x80–0xFF der DOS-Codepage 850 (Westeuropa).
const String _cp850 = 'ÇüéâäàåçêëèïîìÄÅ'
    'ÉæÆôöòûùÿÖÜø£Ø×ƒ'
    'áíóúñÑªº¿®¬½¼¡«»'
    '░▒▓│┤ÁÂÀ©╣║╗╝¢¥┐'
    '└┴┬├─┼ãÃ╚╔╩╦╠═╬¤'
    'ðÐÊËÈıÍÎÏ┘┌█▄¦Ì▀'
    'ÓßÔÒõÕµþÞÚÛÙýÝ¯´'
    '­±‗¾¶§÷¸°¨·¹³²■ ';

/// Bytes in der DOS-Codepage 850 als Text.
String cp850Text(List<int> bytes) => String.fromCharCodes([
      for (final b in bytes) b < 0x80 ? b : _cp850.codeUnitAt(b - 0x80),
    ]);

/// Ein Dateiname aus dem ZIP: UTF-8, wenn das ZIP es sagt oder die Bytes
/// gültiges UTF-8 sind, sonst die DOS-Codepage.
String zipDateiname(List<int> roh, {required bool utf8Kennzeichen}) {
  if (utf8Kennzeichen) return utf8.decode(roh, allowMalformed: true);
  if (roh.every((b) => b < 0x80)) return String.fromCharCodes(roh);
  try {
    return utf8.decode(roh);
  } on FormatException {
    return cp850Text(roh);
  }
}

/// Die Dateinamen eines ZIP in der Reihenfolge seines Verzeichnisses,
/// richtig dekodiert. Leer, wenn das Verzeichnis sich nicht lesen lässt.
List<String> zipDateinamen(Uint8List zip) {
  if (zip.length < 22) return const [];
  final d = ByteData.sublistView(zip);
  // Das Ende des Verzeichnisses: von hinten nach der Kennung suchen.
  var ende = -1;
  for (var i = zip.length - 22; i >= 0 && i >= zip.length - 22 - 65535; i--) {
    if (d.getUint32(i, Endian.little) == 0x06054b50) {
      ende = i;
      break;
    }
  }
  if (ende < 0) return const [];
  final anzahl = d.getUint16(ende + 10, Endian.little);
  var pos = d.getUint32(ende + 16, Endian.little);
  final namen = <String>[];
  for (var n = 0; n < anzahl; n++) {
    if (pos + 46 > zip.length ||
        d.getUint32(pos, Endian.little) != 0x02014b50) {
      break;
    }
    final kennzeichen = d.getUint16(pos + 8, Endian.little);
    final laenge = d.getUint16(pos + 28, Endian.little);
    final extra = d.getUint16(pos + 30, Endian.little);
    final kommentar = d.getUint16(pos + 32, Endian.little);
    if (pos + 46 + laenge > zip.length) break;
    namen.add(
      zipDateiname(
        zip.sublist(pos + 46, pos + 46 + laenge),
        utf8Kennzeichen: kennzeichen & 0x0800 != 0,
      ),
    );
    pos += 46 + laenge + extra + kommentar;
  }
  return namen;
}

/// Die PDF-Dateien eines ZIP — mit richtig dekodierten Namen, ohne
/// Ordner und ohne die Beigaben von macOS. Wirft [FormatException], wenn
/// es kein ZIP ist.
List<FdDatei> pdfsAusZip(Uint8List zip) {
  final Archive archiv;
  try {
    archiv = ZipDecoder().decodeBytes(zip);
  } catch (_) {
    throw const FormatException('Die Datei ist kein lesbares ZIP-Archiv.');
  }
  final namen = zipDateinamen(zip);
  final passt = namen.length == archiv.files.length;
  final dateien = <FdDatei>[];
  for (var i = 0; i < archiv.files.length; i++) {
    final f = archiv.files[i];
    if (!f.isFile) continue;
    final name = passt ? namen[i] : f.name;
    final kurz = name.replaceAll('\\', '/').split('/').last;
    if (name.startsWith('__MACOSX/') || kurz.startsWith('._')) continue;
    if (!kurz.toLowerCase().endsWith('.pdf')) continue;
    final inhalt = f.content;
    if (inhalt is! List<int>) continue;
    dateien.add((name: kurz, inhalt: Uint8List.fromList(inhalt)));
  }
  return dateien;
}

/// Präfix aller Fassungen der Fließdiagramme bei den Entwicklungsdateien.
const String kFdDateiPraefix = 'fliessdiagramm:';

/// Die ID, unter der eine Fassung eines Fließdiagramms bei den
/// Entwicklungsdateien liegt: „fliessdiagramm:FD_011:2026-07-31".
String fdDateiId(String fdId, DateTime stand) =>
    '$kFdDateiPraefix$fdId:${stand.year.toString().padLeft(4, '0')}-'
    '${stand.month.toString().padLeft(2, '0')}-'
    '${stand.day.toString().padLeft(2, '0')}';

/// Kennung und Stand aus einer Datei-ID — null, wenn sie keine Fassung
/// eines Fließdiagramms ist.
({String fdId, DateTime stand})? fdAusDateiId(String id) {
  final m = RegExp(r'^fliessdiagramm:(.+):(\d{4})-(\d{2})-(\d{2})$')
      .firstMatch(id);
  if (m == null) return null;
  return (
    fdId: m[1]!,
    stand: DateTime(int.parse(m[2]!), int.parse(m[3]!), int.parse(m[4]!)),
  );
}

/// „FD_011 · Schnitzel paniert · Stand 31.07.2026" — ohne die Teile, die
/// fehlen.
String fdText(String id, {String? bezeichnung, DateTime? stand}) => [
      id,
      if (bezeichnung != null && bezeichnung.isNotEmpty && bezeichnung != id)
        bezeichnung,
      if (stand != null) 'Stand ${Format.datum(stand)}',
    ].join(' · ');

/// Sortiert Kennungen nach Buchstaben und Zahl: FD_2 vor FD_10.
int fdNachKennung(String a, String b) {
  final muster = RegExp(r'^(\D*)(\d+)');
  final ma = muster.firstMatch(a);
  final mb = muster.firstMatch(b);
  if (ma != null && mb != null && ma[1] == mb[1]) {
    final n = int.parse(ma[2]!).compareTo(int.parse(mb[2]!));
    if (n != 0) return n;
  }
  return a.compareTo(b);
}

/// Eine schon gespeicherte Fassung: Datei-ID, Dateiname und Größe.
typedef FdGespeichert = ({String dateiId, String name, int groesse});

/// Was das Einlesen tut — ausgerechnet, bevor etwas gespeichert wird.
class FdEinlesePlan {
  const FdEinlesePlan({
    this.anlegen = const [],
    this.umbenennen = const [],
    this.neuerStand = const [],
    this.speichern = const [],
    this.vorhanden = 0,
    this.uebersprungen = const [],
  });

  /// Neue Fließdiagramme in der Reihenfolge ihrer Kennung.
  final List<({String id, String bezeichnung})> anlegen;

  /// Bekannte Fließdiagramme, deren neue Fassung anders heißt.
  final List<({String id, String bezeichnung})> umbenennen;

  /// Bekannte Fließdiagramme mit neuerem Stand — oder dem ersten PDF.
  final List<String> neuerStand;

  /// Die Fassungen, die gespeichert werden.
  final List<({String dateiId, FdDatei datei})> speichern;

  /// PDFs, die genau so schon da sind (gleicher Name, gleiche Größe).
  final int vorhanden;

  /// Dateien ohne Kennung am Anfang des Namens.
  final List<String> uebersprungen;

  /// Die Meldung nach dem Einlesen.
  String get text {
    final n = speichern.length;
    final teile = [
      if (anlegen.isNotEmpty)
        '${anlegen.length} '
            '${anlegen.length == 1 ? 'Fließdiagramm' : 'Fließdiagramme'} neu',
      if (neuerStand.isNotEmpty) '${neuerStand.length} mit neuem Stand',
      if (n > 0) '$n ${n == 1 ? 'PDF' : 'PDFs'} gespeichert',
      if (vorhanden > 0)
        '$vorhanden ${vorhanden == 1 ? 'war' : 'waren'} schon da',
    ];
    final ohne = uebersprungen.length > 5
        ? '${uebersprungen.take(5).join(', ')} und '
            '${uebersprungen.length - 5} weitere'
        : uebersprungen.join(', ');
    return [
      if (teile.isEmpty)
        'Keine Fließdiagramme gefunden.'
      else
        '${teile.join(', ')}.',
      if (uebersprungen.isNotEmpty)
        'Ohne Kennung wie „FD_001" am Anfang des Namens übersprungen: $ohne',
    ].join('\n');
  }
}

/// Plant das Einlesen von [dateien]: Was neu ist, legt es an; heißt die
/// neueste Fassung anders, gilt ihre Bezeichnung — aber nur, wenn sie
/// neuer ist als alles Gespeicherte, damit eine eigene Bezeichnung beim
/// erneuten Einlesen bleibt. Jede Fassung wird gespeichert, außer sie ist
/// schon da. Dateien ohne Datum im Namen gelten mit dem Stand [heute].
FdEinlesePlan fdEinlesePlan({
  required List<FdDatei> dateien,
  required Map<String, String> bezeichnungen,
  required List<FdGespeichert> gespeichert,
  required DateTime heute,
}) {
  final tag = DateTime(heute.year, heute.month, heute.day);
  final alt = <String, List<FdGespeichert>>{};
  final altStand = <String, DateTime>{};
  for (final g in gespeichert) {
    final f = fdAusDateiId(g.dateiId);
    if (f == null) continue;
    alt.putIfAbsent(f.fdId, () => []).add(g);
    final bisher = altStand[f.fdId];
    if (bisher == null || f.stand.isAfter(bisher)) altStand[f.fdId] = f.stand;
  }

  final gruppen = <String, List<(FdName, FdDatei)>>{};
  final uebersprungen = <String>[];
  for (final d in dateien) {
    final n = fdAusDateiname(d.name);
    if (n == null) {
      uebersprungen.add(d.name);
    } else {
      gruppen.putIfAbsent(n.id, () => []).add((n, d));
    }
  }

  final anlegen = <({String id, String bezeichnung})>[];
  final umbenennen = <({String id, String bezeichnung})>[];
  final neuerStand = <String>[];
  final speichern = <String, ({String dateiId, FdDatei datei})>{};
  var vorhanden = 0;
  for (final id in gruppen.keys.toList()..sort(fdNachKennung)) {
    // Die neueste Fassung — bei gleichem Stand die zuletzt genannte.
    FdName? neueste;
    FdName? neuesteNeu;
    for (final (n, d) in gruppen[id]!) {
      final stand = n.stand ?? tag;
      if (neueste == null || !stand.isBefore(neueste.stand ?? tag)) {
        neueste = n;
      }
      final schonDa = alt[id]?.any(
            (g) => g.name == d.name && g.groesse == d.inhalt.length,
          ) ??
          false;
      if (schonDa) {
        vorhanden++;
        continue;
      }
      if (neuesteNeu == null || !stand.isBefore(neuesteNeu.stand ?? tag)) {
        neuesteNeu = n;
      }
      final dateiId = fdDateiId(id, stand);
      speichern.remove(dateiId);
      speichern[dateiId] = (dateiId: dateiId, datei: d);
    }
    final name = bezeichnungen[id];
    if (name == null) {
      anlegen.add((id: id, bezeichnung: neueste!.bezeichnung));
      continue;
    }
    if (neuesteNeu == null) continue;
    final standAlt = altStand[id];
    if (standAlt == null || (neuesteNeu.stand ?? tag).isAfter(standAlt)) {
      neuerStand.add(id);
      if (neuesteNeu.bezeichnung != name) {
        umbenennen.add((id: id, bezeichnung: neuesteNeu.bezeichnung));
      }
    }
  }
  return FdEinlesePlan(
    anlegen: anlegen,
    umbenennen: umbenennen,
    neuerStand: neuerStand,
    speichern: speichern.values.toList(),
    vorhanden: vorhanden,
    uebersprungen: uebersprungen,
  );
}
