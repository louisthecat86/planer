import 'dart:convert';
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

// Kryptografische Bausteine — dünne Hüllen um pointycastle.
//
// Bewusst nur bewährte Verfahren aus einer geprüften Bibliothek, nichts
// Selbstgebautes. Die Tests prüfen sie gegen veröffentlichte Testvektoren.

/// PBKDF2 mit HMAC-SHA256 (RFC 8018): leitet aus [passwort] und [salz]
/// [laenge] Bytes ab. Die [iterationen] machen massenhaftes Raten teuer.
Uint8List pbkdf2Sha256(
  List<int> passwort,
  List<int> salz, {
  required int iterationen,
  int laenge = 32,
}) {
  final ableitung = PBKDF2KeyDerivator(HMac.withDigest(SHA256Digest()))
    ..init(Pbkdf2Parameters(Uint8List.fromList(salz), iterationen, laenge));
  return ableitung.process(Uint8List.fromList(passwort));
}

/// HMAC-SHA256 von [daten] mit [schluessel].
Uint8List hmacSha256(List<int> schluessel, List<int> daten) {
  final mac = HMac.withDigest(SHA256Digest())
    ..init(KeyParameter(Uint8List.fromList(schluessel)));
  return mac.process(Uint8List.fromList(daten));
}

/// [anzahl] Bytes aus dem sicheren Zufallsgenerator des Systems.
Uint8List zufallsBytes(int anzahl) {
  final zufall = Random.secure();
  return Uint8List.fromList([
    for (var i = 0; i < anzahl; i++) zufall.nextInt(256),
  ]);
}

/// Vergleicht zwei Bytefolgen in gleichbleibender Zeit. Ein Vergleich, der
/// beim ersten Unterschied abbricht, verriete über die Laufzeit, ab
/// welchem Byte ein geratener Wert falsch ist.
bool gleicheBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var unterschied = 0;
  for (var i = 0; i < a.length; i++) {
    unterschied |= a[i] ^ b[i];
  }
  return unterschied == 0;
}

// ── Verschlüsseln ─────────────────────────────────────────────────────
//
// ChaCha20-Poly1305 (RFC 8439): verschlüsselt und schützt zugleich vor
// Veränderung — ein manipuliertes oder mit falschem Schlüssel gelesenes
// Paket wird abgelehnt, statt Unsinn zu liefern. AES-GCM wäre ebenso
// geeignet, rechnet in pointycastle aber Bit für Bit und ist für einige
// Megabyte zu langsam.

/// Länge eines Schlüssels in Bytes.
const int kSchluesselLaenge = 32;

/// Länge der Nonce, die jedem Paket vorne mitgegeben wird.
const int kNonceLaenge = 12;

/// Länge des Prüfwerts (Tag) am Ende jedes Pakets.
const int kTagLaenge = 16;

/// Ein Paket ließ sich nicht entschlüsseln: falscher Schlüssel, beschädigt
/// oder verändert. Was davon, lässt sich bewusst nicht unterscheiden.
class KryptoFehler implements Exception {
  const KryptoFehler(this.meldung);

  final String meldung;

  @override
  String toString() => meldung;
}

/// Verschlüsselt [klartext] mit [schluessel]. Das Paket ist
/// `Nonce ‖ Chiffretext ‖ Tag`.
///
/// [zweck] wird mitgeschützt, aber nicht verschlüsselt: Ein Paket für den
/// einen Zweck lässt sich nicht als eines für einen anderen ausgeben.
/// [nonce] nur für Tests — sonst ist sie zufällig, und das muss sie sein:
/// Dieselbe Nonce zweimal mit demselben Schlüssel bricht das Verfahren.
Uint8List verschluesseln(
  List<int> schluessel,
  List<int> klartext, {
  required String zweck,
  List<int>? nonce,
}) {
  final n = Uint8List.fromList(nonce ?? zufallsBytes(kNonceLaenge));
  final verfahren = _verfahren(
    verschluesseln: true,
    schluessel: schluessel,
    nonce: n,
    zweck: zweck,
  );
  final eingabe = Uint8List.fromList(klartext);
  final ausgabe = Uint8List(verfahren.getOutputSize(eingabe.length));
  var laenge = verfahren.processBytes(eingabe, 0, eingabe.length, ausgabe, 0);
  laenge += verfahren.doFinal(ausgabe, laenge);
  return Uint8List(kNonceLaenge + laenge)
    ..setRange(0, kNonceLaenge, n)
    ..setRange(kNonceLaenge, kNonceLaenge + laenge, ausgabe);
}

/// Entschlüsselt ein Paket aus [verschluesseln]. Wirft [KryptoFehler],
/// wenn Schlüssel oder [zweck] nicht passen oder das Paket verändert ist.
Uint8List entschluesseln(
  List<int> schluessel,
  List<int> paket, {
  required String zweck,
}) {
  if (paket.length < kNonceLaenge + kTagLaenge) {
    throw const KryptoFehler('Das verschlüsselte Paket ist zu kurz.');
  }
  final daten = Uint8List.fromList(paket);
  final verfahren = _verfahren(
    verschluesseln: false,
    schluessel: schluessel,
    nonce: Uint8List.sublistView(daten, 0, kNonceLaenge),
    zweck: zweck,
  );
  final eingabe = Uint8List.sublistView(daten, kNonceLaenge);
  final ausgabe = Uint8List(verfahren.getOutputSize(eingabe.length));
  try {
    var laenge =
        verfahren.processBytes(eingabe, 0, eingabe.length, ausgabe, 0);
    laenge += verfahren.doFinal(ausgabe, laenge);
    return Uint8List.sublistView(ausgabe, 0, laenge);
  } on ArgumentError {
    // pointycastle meldet einen falschen Tag als ArgumentError.
    throw const KryptoFehler(
      'Entschlüsseln fehlgeschlagen — falscher Schlüssel oder '
      'beschädigte Daten.',
    );
  }
}

ChaCha20Poly1305 _verfahren({
  required bool verschluesseln,
  required List<int> schluessel,
  required Uint8List nonce,
  required String zweck,
}) {
  if (schluessel.length != kSchluesselLaenge) {
    throw ArgumentError('Der Schlüssel muss $kSchluesselLaenge Bytes haben.');
  }
  return ChaCha20Poly1305(ChaCha7539Engine(), Poly1305())
    ..init(
      verschluesseln,
      AEADParameters(
        KeyParameter(Uint8List.fromList(schluessel)),
        kTagLaenge * 8,
        nonce,
        Uint8List.fromList(utf8.encode(zweck)),
      ),
    );
}
