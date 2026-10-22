import 'dart:typed_data';

// Verbunddateien (Compound File Binary, Version 3) schreiben — nur für
// Tests: So entstehen erfundene Outlook-Mails (.msg), ohne dass echte
// Mails im Repository liegen. Kleine Ströme (unter 4096 Bytes) liegen im
// Ministrom, große in eigenen Sektoren — wie bei Outlook.

const int _sektor = 512;
const int _mini = 64;
const int _miniGrenze = 4096;
const int _frei = 0xFFFFFFFF;
const int _ende = 0xFFFFFFFE;
const int _fatSektor = 0xFFFFFFFD;
const int _keiner = 0xFFFFFFFF;

/// Ein Eintrag zum Schreiben: ein Strom mit [daten] oder ein Ordner mit
/// [kinder].
class CfbKnoten {
  CfbKnoten.strom(this.name, List<int> daten)
      : daten = Uint8List.fromList(daten),
        kinder = const [];

  CfbKnoten.ordner(this.name, this.kinder) : daten = null;

  final String name;
  final Uint8List? daten;
  final List<CfbKnoten> kinder;
}

class _Eintrag {
  _Eintrag(this.name, this.typ, this.daten);

  final String name;

  /// 1 Ordner, 2 Strom, 5 Wurzel.
  final int typ;
  final Uint8List? daten;
  int links = _keiner;
  int rechts = _keiner;
  int kind = _keiner;
  int start = _ende;
  int groesse = 0;
}

/// Die Reihenfolge der Namen in einer Verbunddatei: erst nach Länge, dann
/// in Großbuchstaben.
int _vergleich(String a, String b) {
  if (a.length != b.length) return a.length.compareTo(b.length);
  return a.toUpperCase().compareTo(b.toUpperCase());
}

/// Schreibt eine Verbunddatei mit [wurzel] als Inhalt der Wurzel.
Uint8List verbunddatei(List<CfbKnoten> wurzel) {
  final eintraege = <_Eintrag>[_Eintrag('Root Entry', 5, null)];

  // Ein Ordner: seine Kinder als ausgeglichener Suchbaum.
  int baum(List<int> ids, int von, int bis) {
    if (von > bis) return _keiner;
    final mitte = (von + bis) ~/ 2;
    final e = eintraege[ids[mitte]];
    e.links = baum(ids, von, mitte - 1);
    e.rechts = baum(ids, mitte + 1, bis);
    return ids[mitte];
  }

  void aufnehmen(int ordner, List<CfbKnoten> kinder) {
    final ids = <int>[];
    final unter = <int, List<CfbKnoten>>{};
    for (final k in kinder) {
      final daten = k.daten;
      eintraege.add(_Eintrag(k.name, daten == null ? 1 : 2, daten));
      final id = eintraege.length - 1;
      ids.add(id);
      if (daten == null) unter[id] = k.kinder;
    }
    ids.sort((a, b) => _vergleich(eintraege[a].name, eintraege[b].name));
    eintraege[ordner].kind = baum(ids, 0, ids.length - 1);
    for (final MapEntry(:key, :value) in unter.entries) {
      aufnehmen(key, value);
    }
  }

  aufnehmen(0, wurzel);

  // Kleine Ströme in den Ministrom.
  final miniStrom = BytesBuilder();
  final miniFat = <int>[];
  final grosse = <_Eintrag>[];
  for (final e in eintraege) {
    final daten = e.daten;
    if (daten == null) continue;
    e.groesse = daten.length;
    if (daten.isEmpty) continue;
    if (daten.length >= _miniGrenze) {
      grosse.add(e);
      continue;
    }
    final stuecke = (daten.length + _mini - 1) ~/ _mini;
    e.start = miniFat.length;
    for (var i = 0; i < stuecke; i++) {
      miniFat.add(i == stuecke - 1 ? _ende : miniFat.length + 1);
    }
    miniStrom.add(daten);
    final rest = daten.length % _mini;
    if (rest != 0) miniStrom.add(Uint8List(_mini - rest));
  }
  final mini = miniStrom.takeBytes();

  int sektoren(int bytes) => (bytes + _sektor - 1) ~/ _sektor;
  final ordnerSektoren = sektoren(eintraege.length * 128);
  final miniFatSektoren = sektoren(miniFat.length * 4);
  final miniSektoren = sektoren(mini.length);
  final grossSektoren = [for (final e in grosse) sektoren(e.groesse)];
  final uebrige = ordnerSektoren +
      miniFatSektoren +
      miniSektoren +
      grossSektoren.fold<int>(0, (a, b) => a + b);
  var fatSektoren = 1;
  while ((uebrige + fatSektoren) > fatSektoren * (_sektor ~/ 4)) {
    fatSektoren++;
  }
  if (fatSektoren > 109) {
    throw ArgumentError('Zu groß für diesen einfachen Schreiber.');
  }

  final fat = List<int>.filled(fatSektoren * (_sektor ~/ 4), _frei);
  var naechster = 0;
  for (var i = 0; i < fatSektoren; i++) {
    fat[naechster++] = _fatSektor;
  }
  int kette(int anzahl) {
    if (anzahl == 0) return _ende;
    final start = naechster;
    for (var i = 0; i < anzahl; i++) {
      fat[naechster] = i == anzahl - 1 ? _ende : naechster + 1;
      naechster++;
    }
    return start;
  }

  final ordnerStart = kette(ordnerSektoren);
  final miniFatStart = kette(miniFatSektoren);
  final miniStart = kette(miniSektoren);
  for (var i = 0; i < grosse.length; i++) {
    grosse[i].start = kette(grossSektoren[i]);
  }
  eintraege.first
    ..start = mini.isEmpty ? _ende : miniStart
    ..groesse = mini.length;

  final gesamt = _sektor + naechster * _sektor;
  final aus = Uint8List(gesamt);
  final b = ByteData.sublistView(aus);
  void u32(int o, int v) => b.setUint32(o, v, Endian.little);
  void u16(int o, int v) => b.setUint16(o, v, Endian.little);
  int ort(int s) => _sektor + s * _sektor;

  // Der Kopf.
  aus.setAll(0, const [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]);
  u16(0x18, 0x003E);
  u16(0x1A, 0x0003);
  u16(0x1C, 0xFFFE);
  u16(0x1E, 9);
  u16(0x20, 6);
  u32(0x2C, fatSektoren);
  u32(0x30, ordnerStart);
  u32(0x38, _miniGrenze);
  u32(0x3C, miniFatSektoren == 0 ? _ende : miniFatStart);
  u32(0x40, miniFatSektoren);
  u32(0x44, _ende);
  u32(0x48, 0);
  for (var i = 0; i < 109; i++) {
    u32(0x4C + i * 4, i < fatSektoren ? i : _frei);
  }

  // Die Belegung.
  for (var i = 0; i < fat.length; i++) {
    u32(ort(0) + i * 4, fat[i]);
  }

  // Das Verzeichnis.
  for (var i = 0; i < ordnerSektoren * (_sektor ~/ 128); i++) {
    final o = ort(ordnerStart) + i * 128;
    if (i >= eintraege.length) {
      u32(o + 0x44, _keiner);
      u32(o + 0x48, _keiner);
      u32(o + 0x4C, _keiner);
      continue;
    }
    final e = eintraege[i];
    final name = e.name.codeUnits.take(31).toList();
    for (var j = 0; j < name.length; j++) {
      u16(o + j * 2, name[j]);
    }
    u16(o + 0x40, (name.length + 1) * 2);
    aus[o + 0x42] = e.typ;
    aus[o + 0x43] = 1;
    u32(o + 0x44, e.links);
    u32(o + 0x48, e.rechts);
    u32(o + 0x4C, e.kind);
    u32(o + 0x74, e.typ == 1 ? 0 : e.start);
    u32(o + 0x78, e.groesse);
  }

  // Die Belegung des Ministroms, der Ministrom, die großen Ströme.
  for (var i = 0; i < miniFatSektoren * (_sektor ~/ 4); i++) {
    u32(ort(miniFatStart) + i * 4, i < miniFat.length ? miniFat[i] : _frei);
  }
  if (mini.isNotEmpty) aus.setAll(ort(miniStart), mini);
  for (final e in grosse) {
    aus.setAll(ort(e.start), e.daten!);
  }
  return aus;
}
