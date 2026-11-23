import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'datei.dart';
import 'paket.dart';

// Das Paket per QR-Code vom Bildschirm des Planers aufs Handy — ohne Netz,
// ohne Datei.
//
// Ein QR-Code fasst nur gut ein Kilobyte, ein Paket ist größer. Deshalb
// wird es gepackt (gzip) und auf mehrere Bilder verteilt, die der Planer
// im Kreis zeigt. Das Handy sammelt sie in beliebiger Reihenfolge ein;
// ein verpasstes Bild kommt in der nächsten Runde wieder. Ist alles da,
// wird ausgepackt — gzip prüft dabei mit seiner Prüfsumme, dass nichts
// verfälscht ist.
//
// Ein Bild ist reiner Text aus dem alphanumerischen Zeichensatz der
// QR-Codes (Ziffern, Großbuchstaben, „ $%*+-./:"), damit möglichst viel
// hineinpasst:
//
//   PQ1/<Lauf>/<Nummer>/<Anzahl>/<Daten in Base45>
//
// „Lauf" unterscheidet zwei Pakete: Zeigt der Planer ein neues, fängt das
// Handy von vorn an.

/// Kennung am Anfang jedes Bildes — mit der Fassung dieses Formats.
const String kQrKennung = 'PQ1';

/// So viele Bytes trägt ein Bild. Base45 macht daraus das Anderthalbfache
/// an Zeichen; mit dem Kopf passt das in einen QR-Code der Version 25 mit
/// der niedrigsten Fehlerkorrektur (1.853 Zeichen).
const int kQrBytesJeBild = 1000;

/// Das Paket als Folge von Bildern zum Anzeigen. [lauf] unterscheidet es
/// von anderen — vier Zeichen aus Ziffern und Großbuchstaben.
List<String> qrBilder(
  ErfassungsPaket paket, {
  required String lauf,
  int bytesJeBild = kQrBytesJeBild,
}) =>
    qrBilderAus(qrPacken(paket), lauf: lauf, bytesJeBild: bytesJeBild);

/// Das Paket gepackt — so wird es auf die Bilder verteilt
/// ([qrBilderAus]).
Uint8List qrPacken(ErfassungsPaket paket) =>
    Uint8List.fromList(gzip.encode(utf8.encode(paket.alsText())));

/// Beliebige Bytes als Folge von Bildern — siehe [qrBilder].
List<String> qrBilderAus(
  Uint8List daten, {
  required String lauf,
  int bytesJeBild = kQrBytesJeBild,
}) {
  if (!RegExp(r'^[0-9A-Z]{1,8}$').hasMatch(lauf)) {
    throw ArgumentError.value(lauf, 'lauf', 'nur Ziffern und Großbuchstaben');
  }
  final anzahl = daten.isEmpty ? 1 : (daten.length / bytesJeBild).ceil();
  return [
    for (var i = 0; i < anzahl; i++)
      '$kQrKennung/$lauf/${i + 1}/$anzahl/${base45Kodieren(
        Uint8List.sublistView(
          daten,
          i * bytesJeBild,
          (i + 1) * bytesJeBild > daten.length
              ? daten.length
              : (i + 1) * bytesJeBild,
        ),
      )}',
  ];
}

/// Sammelt die gescannten Bilder eines Pakets ein.
class QrSammler {
  String? _lauf;
  int _anzahl = 0;
  final Map<int, Uint8List> _teile = {};

  /// Wie viele Bilder es insgesamt sind — 0, solange noch keins da ist.
  int get anzahl => _anzahl;

  /// Wie viele schon da sind.
  int get vorhanden => _teile.length;

  /// Ob alle Bilder da sind.
  bool get fertig => _anzahl > 0 && _teile.length == _anzahl;

  /// Nimmt ein gescanntes Bild auf. Gibt zurück, ob es neu war. Was kein
  /// Bild dieses Formats ist (ein fremder QR-Code), wird übergangen. Kommt
  /// ein Bild eines anderen Pakets, fängt das Sammeln von vorn an.
  bool aufnehmen(String text) {
    final teile = text.split('/');
    if (teile.length < 5 || teile[0] != kQrKennung) return false;
    final lauf = teile[1];
    final nummer = int.tryParse(teile[2]);
    final anzahl = int.tryParse(teile[3]);
    if (nummer == null || anzahl == null) return false;
    if (anzahl < 1 || nummer < 1 || nummer > anzahl) return false;
    // Die Daten selbst können „/" enthalten.
    final daten = teile.sublist(4).join('/');
    final Uint8List bytes;
    try {
      bytes = base45Dekodieren(daten);
    } on FormatException {
      return false;
    }
    if (lauf != _lauf || anzahl != _anzahl) {
      _lauf = lauf;
      _anzahl = anzahl;
      _teile.clear();
    }
    if (_teile.containsKey(nummer)) return false;
    _teile[nummer] = bytes;
    return true;
  }

  /// Die eingesammelten Bytes in der richtigen Reihenfolge. Wirft einen
  /// [StateError], solange nicht alles da ist.
  Uint8List bytes() {
    if (!fertig) throw StateError('Es fehlen noch Bilder.');
    final b = BytesBuilder(copy: false);
    for (var i = 1; i <= _anzahl; i++) {
      b.add(_teile[i]!);
    }
    return b.takeBytes();
  }

  /// Das Paket aus allen Bildern. Wirft einen [FormatFehler], wenn sich
  /// die Daten nicht auspacken oder lesen lassen.
  ErfassungsPaket paket() {
    final String text;
    try {
      text = utf8.decode(gzip.decode(bytes()));
    } on FormatException {
      throw const FormatFehler(
        'Die QR-Codes ergeben kein lesbares Paket. Bitte noch einmal '
        'scannen.',
      );
    } on Exception {
      throw const FormatFehler(
        'Die QR-Codes ergeben kein lesbares Paket. Bitte noch einmal '
        'scannen.',
      );
    }
    return ErfassungsPaket.ausText(text);
  }

  /// Fängt von vorn an.
  void leeren() {
    _lauf = null;
    _anzahl = 0;
    _teile.clear();
  }
}

// ── Base45 (RFC 9285) ─────────────────────────────────────────────────
//
// Je zwei Bytes werden drei Zeichen aus dem alphanumerischen Zeichensatz
// der QR-Codes, ein einzelnes am Ende zwei.

const String _base45 = r'0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:';

/// [daten] als Base45-Text.
String base45Kodieren(List<int> daten) {
  final s = StringBuffer();
  for (var i = 0; i + 1 < daten.length; i += 2) {
    var n = daten[i] * 256 + daten[i + 1];
    final c = n % 45;
    n ~/= 45;
    final d = n % 45;
    final e = n ~/ 45;
    s
      ..write(_base45[c])
      ..write(_base45[d])
      ..write(_base45[e]);
  }
  if (daten.length.isOdd) {
    final n = daten.last;
    s
      ..write(_base45[n % 45])
      ..write(_base45[n ~/ 45]);
  }
  return s.toString();
}

/// Base45-Text als Bytes. Wirft eine [FormatException] bei einem fremden
/// Zeichen oder einer unmöglichen Länge.
Uint8List base45Dekodieren(String text) {
  int wert(int i) {
    final w = _base45.indexOf(text[i]);
    if (w < 0) throw FormatException('Kein Base45-Zeichen', text, i);
    return w;
  }

  if (text.length % 3 == 1) {
    throw FormatException('Unmögliche Länge für Base45', text);
  }
  final out = BytesBuilder();
  var i = 0;
  for (; i + 2 < text.length; i += 3) {
    final n = wert(i) + wert(i + 1) * 45 + wert(i + 2) * 45 * 45;
    if (n > 0xFFFF) throw FormatException('Base45 zu groß', text, i);
    out
      ..addByte(n >> 8)
      ..addByte(n & 0xFF);
  }
  if (i < text.length) {
    final n = wert(i) + wert(i + 1) * 45;
    if (n > 0xFF) throw FormatException('Base45 zu groß', text, i);
    out.addByte(n);
  }
  return out.takeBytes();
}
