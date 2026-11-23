import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'datei.dart';
import 'ergebnis.dart';

// Das Ergebnis verschlüsselt — damit es über jeden Weg zurück an den PC
// darf, auch über ein privates E-Mail-Postfach: Unterwegs ist es nur
// Zeichensalat, und wer es verändert, fällt auf.
//
// Den Schlüssel legt der Planer ins Paket, für jedes Paket einen eigenen
// (abgeleitet aus einem Geheimnis, das nur in seiner Datenbank steht).
// Kommt das Paket per QR-Code aufs Handy, geht der Schlüssel durch kein
// Netz. Die App verschlüsselt damit das Ergebnis, der Planer leitet den
// Schlüssel beim Einlesen aus der Paket-ID wieder ab.
//
// Verfahren wie beim Schutz der Entwicklungsdaten im Planer:
// ChaCha20-Poly1305 (RFC 8439) aus pointycastle. Verschlüsselt wird das
// gepackte (gzip) Ergebnis; die Paket-ID ist mitgeschützt, steht aber
// offen in der Datei — der Planer braucht sie, um den Schlüssel zu finden.
//
// Die Datei:
//   {"format":"planer-erfassung","art":"ergebnis-geschuetzt","version":1,
//    "paketId":"…","daten":"<Base64: Nonce ‖ Chiffretext ‖ Tag>"}

/// Länge des Schlüssels in Bytes.
const int kErgebnisSchluesselLaenge = 32;

const int _nonceLaenge = 12;
const int _tagLaenge = 16;

/// Ein verschlüsseltes Ergebnis, noch nicht geöffnet.
typedef GeschuetztesErgebnis = ({String paketId, Uint8List daten});

String _zweck(String paketId) => 'planer-erfassung-ergebnis:$paketId';

/// [ergebnis] verschlüsselt als Text der Datei. [nonce] nur für Tests —
/// sonst zufällig, und das muss sie sein.
String ergebnisGeschuetzt(
  ErfassungsErgebnis ergebnis,
  List<int> schluessel, {
  List<int>? nonce,
}) {
  final n = Uint8List.fromList(nonce ?? _zufall(_nonceLaenge));
  final klar = Uint8List.fromList(gzip.encode(utf8.encode(ergebnis.alsText())));
  final verfahren = _verfahren(
    verschluesseln: true,
    schluessel: schluessel,
    nonce: n,
    zweck: _zweck(ergebnis.paketId),
  );
  final aus = Uint8List(verfahren.getOutputSize(klar.length));
  var laenge = verfahren.processBytes(klar, 0, klar.length, aus, 0);
  laenge += verfahren.doFinal(aus, laenge);
  final daten = Uint8List(_nonceLaenge + laenge)
    ..setRange(0, _nonceLaenge, n)
    ..setRange(_nonceLaenge, _nonceLaenge + laenge, aus);
  return dateiText({
    ...dateiKopf(DateiArt.ergebnisGeschuetzt),
    'paketId': ergebnis.paketId,
    'daten': base64Encode(daten),
  });
}

/// Ist [text] ein verschlüsseltes Ergebnis, dessen Paket-ID und Daten —
/// sonst null (dann ist es ein offenes Ergebnis oder gar keins). Wirft
/// einen [FormatFehler], wenn es eins ist, aber beschädigt.
GeschuetztesErgebnis? geschuetztesErgebnis(String text) {
  final Object? daten;
  try {
    daten = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (daten is! JsonObjekt ||
      daten['format'] != kFormatName ||
      daten['art'] != DateiArt.ergebnisGeschuetzt.schluessel) {
    return null;
  }
  final version = daten['version'];
  if (version is! int || version > 1) {
    throw const FormatFehler(
      'Die Datei stammt aus einer neueren Fassung — bitte Planer und App '
      'auf denselben Stand bringen.',
    );
  }
  const wo = 'dem verschlüsselten Ergebnis';
  final Uint8List bytes;
  try {
    bytes = base64Decode(jsonText(daten, 'daten', wo));
  } on FormatException {
    throw const FormatFehler(
      'Die Datei ist beschädigt: Die verschlüsselten Daten sind unlesbar.',
    );
  }
  return (paketId: jsonText(daten, 'paketId', wo), daten: bytes);
}

/// Öffnet ein verschlüsseltes Ergebnis mit [schluessel]. Wirft einen
/// [FormatFehler], wenn der Schlüssel nicht passt oder die Datei
/// unterwegs verändert wurde — was davon, lässt sich bewusst nicht
/// unterscheiden.
ErfassungsErgebnis ergebnisEntschluesseln(
  GeschuetztesErgebnis g,
  List<int> schluessel,
) {
  const unpassend = FormatFehler(
    'Das Ergebnis ist verschlüsselt, lässt sich hier aber nicht öffnen: '
    'Es gehört zu einem Paket eines anderen Planers, oder die Datei wurde '
    'unterwegs verändert.',
  );
  if (g.daten.length < _nonceLaenge + _tagLaenge) throw unpassend;
  final verfahren = _verfahren(
    verschluesseln: false,
    schluessel: schluessel,
    nonce: Uint8List.sublistView(g.daten, 0, _nonceLaenge),
    zweck: _zweck(g.paketId),
  );
  final ein = Uint8List.sublistView(g.daten, _nonceLaenge);
  final aus = Uint8List(verfahren.getOutputSize(ein.length));
  final int laenge;
  try {
    final l = verfahren.processBytes(ein, 0, ein.length, aus, 0);
    laenge = l + verfahren.doFinal(aus, l);
  } on ArgumentError {
    // pointycastle meldet einen falschen Prüfwert als ArgumentError.
    throw unpassend;
  } on InvalidCipherTextException {
    throw unpassend;
  }
  final String text;
  try {
    text = utf8.decode(gzip.decode(Uint8List.sublistView(aus, 0, laenge)));
  } on Exception {
    throw unpassend;
  }
  final ergebnis = ErfassungsErgebnis.ausText(text);
  // Die ID ist mitgeschützt — das hier fängt nur Unsinn beim Schreiben.
  if (ergebnis.paketId != g.paketId) throw unpassend;
  return ergebnis;
}

ChaCha20Poly1305 _verfahren({
  required bool verschluesseln,
  required List<int> schluessel,
  required Uint8List nonce,
  required String zweck,
}) {
  if (schluessel.length != kErgebnisSchluesselLaenge) {
    throw ArgumentError(
      'Der Schlüssel muss $kErgebnisSchluesselLaenge Bytes haben.',
    );
  }
  return ChaCha20Poly1305(ChaCha7539Engine(), Poly1305())
    ..init(
      verschluesseln,
      AEADParameters(
        KeyParameter(Uint8List.fromList(schluessel)),
        _tagLaenge * 8,
        nonce,
        Uint8List.fromList(utf8.encode(zweck)),
      ),
    );
}

Uint8List _zufall(int anzahl) {
  final z = Random.secure();
  return Uint8List.fromList([for (var i = 0; i < anzahl; i++) z.nextInt(256)]);
}
