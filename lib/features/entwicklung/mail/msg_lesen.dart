import 'dart:convert';
import 'dart:typed_data';

import 'eml_lesen.dart';
import 'mail.dart';

// Outlook-Mails lesen (.msg): Eine .msg ist eine Verbunddatei
// („Compound File", wie alte Office-Dateien) — ein kleines Dateisystem in
// einer Datei. Darin steht jede Eigenschaft der Mail in einem eigenen
// Strom („__substg1.0_0037001F" ist der Betreff als Unicode-Text), feste
// Werte wie das Datum stehen gesammelt in „__properties_version1.0", jeder
// Anhang in einem Ordner „__attach_version1.0_#00000000".

/// Liest eine Outlook-Mail. Wirft [FormatException], wenn [bytes] keine
/// ist.
Mail msgLesen(Uint8List bytes) {
  final datei = Verbunddatei.lesen(bytes);
  final wurzel = datei.kinder(0);
  if (!wurzel.keys.any((n) => n.startsWith('__SUBSTG1.0_'))) {
    throw const FormatException('Die Datei ist keine Outlook-Mail.');
  }
  final eigenschaften = _Eigenschaften(
    datei.stromNamens(wurzel, '__PROPERTIES_VERSION1.0'),
    kopf: 32,
  );
  final codepage = eigenschaften.zahl(0x3FDE) ?? eigenschaften.zahl(0x3FFD);
  String text(int id) => _text(datei, wurzel, id, codepage);

  // Die Kopfzeilen, mit denen die Mail kam — für Adresse und Datum, wenn
  // die Eigenschaften sie nicht haben.
  final kopf = kopfzeilenLesen(text(0x007D));
  final ausKopf = adresseLesen(kopf['from'] ?? '');

  String adresse() {
    for (final kandidat in [
      text(0x5D01), // Absender SMTP
      text(0x0C1F), // Absender — bei Exchange eine X.500-Adresse
      text(0x5D02), // „im Auftrag von" SMTP
      text(0x0065),
      ausKopf.adresse,
    ]) {
      if (kandidat.contains('@')) return kandidat.trim();
    }
    return '';
  }

  final vonName = [text(0x0C1A), text(0x0042), ausKopf.name]
      .firstWhere((n) => n.trim().isNotEmpty, orElse: () => '')
      .trim();

  var inhalt = text(0x1000);
  if (inhalt.trim().isEmpty) {
    final html = _html(datei, wurzel, codepage);
    if (html.isNotEmpty) inhalt = htmlZuText(html);
  }

  return Mail(
    betreff: text(0x0037).trim(),
    vonName: vonName,
    vonAdresse: adresse(),
    an: text(0x0E04).trim(),
    cc: text(0x0E03).trim(),
    datum: eigenschaften.zeit(0x0039) ??
        eigenschaften.zeit(0x0E06) ??
        internetDatum(kopf['date']) ??
        eigenschaften.zeit(0x3007),
    text: inhalt
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim(),
    // Die Anhänge in ihrer Reihenfolge: #00000000, #00000001, …
    anhaenge: [
      for (final name in wurzel.keys.toList()..sort())
        if (name.startsWith('__ATTACH_VERSION1.0_') &&
            datei.istOrdner(wurzel[name]!))
          if (_anhang(datei, wurzel[name]!, codepage) case final a?) a,
    ],
  );
}

/// Ein Text-Eigenschaft: Unicode („…001F") oder 8-Bit in der Codepage der
/// Mail („…001E") — leer, wenn sie fehlt.
String _text(Verbunddatei datei, Map<String, int> ordner, int id, int? cp) {
  final hex = id.toRadixString(16).toUpperCase().padLeft(4, '0');
  final unicode = datei.stromNamens(ordner, '__SUBSTG1.0_${hex}001F');
  if (unicode != null) return _bisNull(_utf16le(unicode));
  final acht = datei.stromNamens(ordner, '__SUBSTG1.0_${hex}001E');
  if (acht != null) return _bisNull(codepageDekodieren(acht, cp));
  return '';
}

/// Der HTML-Text der Mail — als Bytes in der Codepage oder als Unicode.
String _html(Verbunddatei datei, Map<String, int> ordner, int? cp) {
  final bytes = datei.stromNamens(ordner, '__SUBSTG1.0_10130102');
  if (bytes != null) {
    if (cp == null || cp == 65001) {
      return _bisNull(utf8.decode(bytes, allowMalformed: true));
    }
    return _bisNull(codepageDekodieren(bytes, cp));
  }
  return _text(datei, ordner, 0x1013, cp);
}

String _utf16le(Uint8List b) => String.fromCharCodes([
      for (var i = 0; i + 1 < b.length; i += 2) b[i] | (b[i + 1] << 8),
    ]);

String _bisNull(String s) {
  final i = s.indexOf('\u0000');
  return i < 0 ? s : s.substring(0, i);
}

/// Ein Anhang — null, wenn er nur ins Bild der Mail gehört (Logo in der
/// Signatur) oder keine Daten hat (etwa eine angehängte Mail).
MailAnhang? _anhang(Verbunddatei datei, int ordnerIndex, int? cp) {
  final ordner = datei.kinder(ordnerIndex);
  final eigenschaften = _Eigenschaften(
    datei.stromNamens(ordner, '__PROPERTIES_VERSION1.0'),
    kopf: 8,
  );
  if (eigenschaften.wahr(0x7FFE) ?? false) return null; // versteckt
  final daten = datei.stromNamens(ordner, '__SUBSTG1.0_37010102');
  if (daten == null) return null;
  String text(int id) => _text(datei, ordner, id, cp).trim();
  final mime = text(0x370E);
  // Ins HTML eingebettete Bilder (cid:) sind kein Anhang für sich.
  if (text(0x3712).isNotEmpty && mime.toLowerCase().startsWith('image/')) {
    return null;
  }
  final name = [text(0x3707), text(0x3704), text(0x3001)].firstWhere(
    (n) => n.isNotEmpty,
    orElse: () => 'Anhang',
  );
  return MailAnhang(
    name: name,
    inhalt: daten,
    mimeTyp: mime.isEmpty ? null : mime,
  );
}

/// Die festen Eigenschaften aus „__properties_version1.0": nach einem
/// Kopf je 16 Bytes — Kennung und Typ, Merker, Wert.
class _Eigenschaften {
  _Eigenschaften(Uint8List? daten, {required int kopf}) {
    if (daten == null) return;
    final b = ByteData.sublistView(daten);
    for (var o = kopf; o + 16 <= daten.length; o += 16) {
      final kennung = b.getUint32(o, Endian.little);
      _werte[kennung] = Uint8List.sublistView(daten, o + 8, o + 16);
    }
  }

  /// Kennung mit Typ (`id << 16 | typ`) → die acht Bytes des Werts.
  final Map<int, Uint8List> _werte = {};

  ByteData? _wert(int id, int typ) {
    final w = _werte[(id << 16) | typ];
    return w == null ? null : ByteData.sublistView(w);
  }

  /// Eine Zahl (PT_LONG).
  int? zahl(int id) => _wert(id, 0x0003)?.getInt32(0, Endian.little);

  /// Ja oder nein (PT_BOOLEAN).
  bool? wahr(int id) {
    final w = _wert(id, 0x000B);
    return w == null ? null : w.getUint16(0, Endian.little) != 0;
  }

  /// Ein Zeitpunkt (PT_SYSTIME: Zehntelmikrosekunden seit 1601, UTC) in
  /// Ortszeit.
  DateTime? zeit(int id) {
    final w = _wert(id, 0x0040);
    if (w == null) return null;
    final unten = w.getUint32(0, Endian.little);
    final oben = w.getUint32(4, Endian.little);
    final zehntel = oben * 4294967296 + unten;
    if (zehntel <= 0) return null;
    return DateTime.utc(1601)
        .add(Duration(microseconds: zehntel ~/ 10))
        .toLocal();
  }
}

// ── Verbunddatei ─────────────────────────────────────────────────────

/// Kennung einer leeren Verkettung.
const int _kettenEnde = 0xFFFFFFFE;
const int _keinEintrag = 0xFFFFFFFF;

/// Eine Verbunddatei (Microsoft Compound File Binary) zum Lesen: Ordner
/// und Ströme wie in einem Dateisystem.
class Verbunddatei {
  Verbunddatei._(this._bytes);

  /// Liest die Struktur. Wirft [FormatException], wenn [bytes] keine
  /// Verbunddatei ist.
  factory Verbunddatei.lesen(Uint8List bytes) {
    if (!istVerbunddatei(bytes) || bytes.length < 512) {
      throw const FormatException('Die Datei ist keine Outlook-Mail.');
    }
    final d = Verbunddatei._(bytes).._einlesen();
    return d;
  }

  final Uint8List _bytes;
  late final ByteData _b = ByteData.sublistView(_bytes);
  late int _sektor;
  late int _version;
  int _miniGrenze = 4096;
  final List<int> _fat = [];
  final List<int> _miniFat = [];
  final List<_Eintrag> _eintraege = [];
  Uint8List _miniStrom = Uint8List(0);

  int _u32(int o) => o + 4 <= _bytes.length ? _b.getUint32(o, Endian.little) : 0;
  int _u16(int o) => o + 2 <= _bytes.length ? _b.getUint16(o, Endian.little) : 0;

  /// Wo ein Sektor beginnt — der Kopf belegt den ersten.
  int _ort(int sektor) => (sektor + 1) * _sektor;

  int get _sektorZahl => (_bytes.length + _sektor - 1) ~/ _sektor;

  void _einlesen() {
    _version = _u16(0x1A);
    final verschiebung = _u16(0x1E);
    if (verschiebung != 9 && verschiebung != 12) {
      throw const FormatException('Die Verbunddatei hat ein unbekanntes '
          'Format.');
    }
    _sektor = 1 << verschiebung;
    final fatSektoren = _u32(0x2C);
    final ersterOrdner = _u32(0x30);
    _miniGrenze = _u32(0x38) == 0 ? 4096 : _u32(0x38);
    final ersterMiniFat = _u32(0x3C);
    final ersterDifat = _u32(0x44);
    final difatSektoren = _u32(0x48);

    // Die Sektoren der Belegungstabelle: 109 im Kopf, der Rest in einer
    // eigenen Kette.
    final fatOrte = <int>[];
    for (var i = 0; i < 109 && fatOrte.length < fatSektoren; i++) {
      final s = _u32(0x4C + i * 4);
      if (s >= _keinEintrag - 1) break;
      fatOrte.add(s);
    }
    var difat = ersterDifat;
    for (var n = 0;
        n < difatSektoren && difat < _kettenEnde && fatOrte.length < fatSektoren;
        n++) {
      final o = _ort(difat);
      final proSektor = _sektor ~/ 4 - 1;
      for (var i = 0; i < proSektor && fatOrte.length < fatSektoren; i++) {
        fatOrte.add(_u32(o + i * 4));
      }
      difat = _u32(o + proSektor * 4);
    }
    for (final s in fatOrte) {
      final o = _ort(s);
      for (var i = 0; i < _sektor ~/ 4; i++) {
        _fat.add(_u32(o + i * 4));
      }
    }

    // Das Verzeichnis: je 128 Bytes ein Eintrag.
    final ordner = _kette(ersterOrdner);
    for (var o = 0; o + 128 <= ordner.length; o += 128) {
      final e = ByteData.sublistView(ordner, o, o + 128);
      final laenge = e.getUint16(0x40, Endian.little).clamp(0, 64);
      // Die Länge zählt die abschließende Null mit.
      final name = String.fromCharCodes([
        for (var i = 0; i + 1 < laenge - 1; i += 2)
          e.getUint16(i, Endian.little),
      ]);
      final groesse = _version == 4
          ? e.getUint32(0x78, Endian.little) +
              e.getUint32(0x7C, Endian.little) * 4294967296
          : e.getUint32(0x78, Endian.little);
      _eintraege.add(
        _Eintrag(
          name: _ohneNull(name),
          typ: e.getUint8(0x42),
          links: e.getUint32(0x44, Endian.little),
          rechts: e.getUint32(0x48, Endian.little),
          kind: e.getUint32(0x4C, Endian.little),
          start: e.getUint32(0x74, Endian.little),
          groesse: groesse,
        ),
      );
    }
    if (_eintraege.isEmpty || _eintraege.first.typ != 5) {
      throw const FormatException('Die Verbunddatei hat kein Verzeichnis.');
    }

    // Der Ministrom (kleine Ströme in 64-Byte-Stücken) liegt im Strom der
    // Wurzel, seine Belegung in einer eigenen Kette.
    final wurzel = _eintraege.first;
    _miniStrom = _kette(wurzel.start, groesse: wurzel.groesse);
    final miniFat = _kette(ersterMiniFat);
    final m = ByteData.sublistView(miniFat);
    for (var o = 0; o + 4 <= miniFat.length; o += 4) {
      _miniFat.add(m.getUint32(o, Endian.little));
    }
  }

  String _ohneNull(String s) {
    final i = s.indexOf('\u0000');
    return i < 0 ? s : s.substring(0, i);
  }

  /// Die Bytes einer Sektorkette ab [start] — höchstens [groesse].
  Uint8List _kette(int start, {int? groesse}) {
    final aus = BytesBuilder(copy: false);
    var s = start;
    var schritte = 0;
    final grenze = _sektorZahl + 1;
    while (s < _kettenEnde && s < _fat.length && schritte++ < grenze) {
      final o = _ort(s);
      if (o >= _bytes.length) break;
      final ende = (o + _sektor).clamp(0, _bytes.length);
      aus.add(Uint8List.sublistView(_bytes, o, ende));
      if (groesse != null && aus.length >= groesse) break;
      s = _fat[s];
    }
    final b = aus.takeBytes();
    return groesse == null || b.length <= groesse
        ? b
        : Uint8List.sublistView(b, 0, groesse);
  }

  /// Die Bytes einer Kette im Ministrom.
  Uint8List _miniKette(int start, int groesse) {
    final aus = BytesBuilder(copy: false);
    var s = start;
    var schritte = 0;
    final grenze = _miniFat.length + 1;
    while (s < _kettenEnde &&
        s < _miniFat.length &&
        aus.length < groesse &&
        schritte++ < grenze) {
      final o = s * 64;
      if (o >= _miniStrom.length) break;
      aus.add(
        Uint8List.sublistView(
          _miniStrom,
          o,
          (o + 64).clamp(0, _miniStrom.length),
        ),
      );
      s = _miniFat[s];
    }
    final b = aus.takeBytes();
    return b.length <= groesse ? b : Uint8List.sublistView(b, 0, groesse);
  }

  bool istOrdner(int i) =>
      i >= 0 && i < _eintraege.length && (_eintraege[i].typ == 1 ||
          _eintraege[i].typ == 5);

  /// Die Kinder des Ordners [ordner] (0 ist die Wurzel): Name in
  /// Großbuchstaben → Index.
  Map<String, int> kinder(int ordner) {
    final ergebnis = <String, int>{};
    if (!istOrdner(ordner)) return ergebnis;
    final besucht = <int>{};
    final offen = <int>[_eintraege[ordner].kind];
    while (offen.isNotEmpty) {
      final i = offen.removeLast();
      if (i >= _eintraege.length || !besucht.add(i)) continue;
      final e = _eintraege[i];
      if (e.typ != 0) ergebnis[e.name.toUpperCase()] = i;
      offen
        ..add(e.links)
        ..add(e.rechts);
    }
    return ergebnis;
  }

  /// Der Inhalt des Stroms [i] — null, wenn [i] keiner ist.
  Uint8List? strom(int i) {
    if (i < 0 || i >= _eintraege.length || _eintraege[i].typ != 2) {
      return null;
    }
    final e = _eintraege[i];
    if (e.groesse == 0) return Uint8List(0);
    return e.groesse < _miniGrenze
        ? _miniKette(e.start, e.groesse)
        : _kette(e.start, groesse: e.groesse);
  }

  /// Der Inhalt des Stroms [name] in [ordner] (aus [kinder]).
  Uint8List? stromNamens(Map<String, int> ordner, String name) {
    final i = ordner[name.toUpperCase()];
    return i == null ? null : strom(i);
  }
}

class _Eintrag {
  const _Eintrag({
    required this.name,
    required this.typ,
    required this.links,
    required this.rechts,
    required this.kind,
    required this.start,
    required this.groesse,
  });

  final String name;

  /// 0 leer, 1 Ordner, 2 Strom, 5 Wurzel.
  final int typ;
  final int links;
  final int rechts;
  final int kind;
  final int start;
  final int groesse;
}
