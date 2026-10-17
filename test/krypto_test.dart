import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:produktion_planer/core/utils/krypto.dart';

/// Tests für die kryptografischen Bausteine — gegen veröffentlichte
/// Testvektoren, damit ein Fehler in der Anbindung nicht unbemerkt bleibt.
void main() {
  String hex(List<int> bytes) =>
      [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

  group('PBKDF2-HMAC-SHA256 (RFC 7914, Abschnitt 11)', () {
    test('1 Iteration', () {
      final wert = pbkdf2Sha256(
        utf8.encode('passwd'),
        utf8.encode('salt'),
        iterationen: 1,
        laenge: 64,
      );
      expect(
        hex(wert),
        '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc'
        '49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783',
      );
    });

    test('80.000 Iterationen', () {
      final wert = pbkdf2Sha256(
        utf8.encode('Password'),
        utf8.encode('NaCl'),
        iterationen: 80000,
        laenge: 64,
      );
      expect(
        hex(wert),
        '4ddcd8f60b98be21830cee5ef22701f9641a4418d04c0414aeff08876b34ab56'
        'a1d425a1225833549adb841b51c9b3176a272bdebba1d078478f62b397f33c8d',
      );
    });

    test('Umlaute und 32 Bytes', () {
      final wert = pbkdf2Sha256(
        utf8.encode('Rezeptur-Geheimnis!'),
        List<int>.generate(16, (i) => i),
        iterationen: 1000,
      );
      expect(wert.length, 32);
      expect(
        hex(wert),
        '9c28995e34c41ad8209bd9d20afc749d90e8d5ecbe3633a1ec0c798d48e70681',
      );
    });
  });

  test('HMAC-SHA256', () {
    expect(
      hex(
        hmacSha256(
          utf8.encode('key'),
          utf8.encode('The quick brown fox jumps over the lazy dog'),
        ),
      ),
      'f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8',
    );
  });

  test('gleicheBytes', () {
    expect(gleicheBytes([1, 2, 3], [1, 2, 3]), isTrue);
    expect(gleicheBytes([1, 2, 3], [1, 2, 4]), isFalse);
    expect(gleicheBytes([1, 2, 3], [1, 2]), isFalse);
    expect(gleicheBytes(const [], const []), isTrue);
  });

  test('zufallsBytes', () {
    final a = zufallsBytes(16);
    final b = zufallsBytes(16);
    expect(a.length, 16);
    expect(gleicheBytes(a, b), isFalse, reason: 'zweimal derselbe Zufall');
  });

  group('Verschlüsseln mit ChaCha20-Poly1305', () {
    final schluessel = List<int>.generate(32, (i) => i);
    const zweck = 'produktions-planer/test';
    const text = 'Rezeptur: 60 % Schweinefleisch, Würze';

    test('bekannter Wert (mit Python cryptography gegengerechnet)', () {
      final paket = verschluesseln(
        schluessel,
        utf8.encode(text),
        zweck: zweck,
        nonce: List<int>.generate(12, (i) => 100 + i),
      );
      expect(
        hex(paket),
        '6465666768696a6b6c6d6e6f6674c1afe8d10320c1fe234fd2acf8c013aee551'
        'f63e8ecbaa5a9fc1995ae0d39d7a0e92d55f0d10749109b95a3fb5c5dec431e3'
        'ca11',
      );
      expect(
        utf8.decode(entschluesseln(schluessel, paket, zweck: zweck)),
        text,
      );
    });

    test('hin und zurück, jedes Mal mit neuer Nonce', () {
      final a = verschluesseln(schluessel, utf8.encode(text), zweck: zweck);
      final b = verschluesseln(schluessel, utf8.encode(text), zweck: zweck);
      expect(a.length, kNonceLaenge + 38 + kTagLaenge);
      expect(gleicheBytes(a, b), isFalse);
      expect(utf8.decode(entschluesseln(schluessel, a, zweck: zweck)), text);
      expect(utf8.decode(entschluesseln(schluessel, b, zweck: zweck)), text);
    });

    test('falscher Schlüssel, falscher Zweck oder verändert: abgelehnt', () {
      final paket =
          verschluesseln(schluessel, utf8.encode(text), zweck: zweck);
      final anderer = List<int>.generate(32, (i) => 31 - i);
      expect(
        () => entschluesseln(anderer, paket, zweck: zweck),
        throwsA(isA<KryptoFehler>()),
      );
      expect(
        () => entschluesseln(schluessel, paket, zweck: 'anderer Zweck'),
        throwsA(isA<KryptoFehler>()),
      );
      final veraendert = List<int>.of(paket);
      veraendert[20] ^= 0x01;
      expect(
        () => entschluesseln(schluessel, veraendert, zweck: zweck),
        throwsA(isA<KryptoFehler>()),
      );
      expect(
        () => entschluesseln(schluessel, paket.sublist(0, 20), zweck: zweck),
        throwsA(isA<KryptoFehler>()),
      );
    });

    test('auch große Mengen', () {
      final viel = List<int>.generate(300000, (i) => i % 251);
      final paket = verschluesseln(schluessel, viel, zweck: zweck);
      expect(entschluesseln(schluessel, paket, zweck: zweck), viel);
    });

    test('ein Schlüssel muss 32 Bytes haben', () {
      expect(
        () => verschluesseln([1, 2, 3], utf8.encode(text), zweck: zweck),
        throwsArgumentError,
      );
    });
  });
}
