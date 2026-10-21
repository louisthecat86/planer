import 'dart:async';
import 'dart:convert';
import 'dart:io';

// Übersetzen mit DeepL — nur, wenn ein eigener Schlüssel hinterlegt ist.
// Der Schlüssel steht in den Einstellungen dieses Rechners, nicht im Code
// und nicht im Backup.

/// Free-Schlüssel enden auf „:fx" und haben eine eigene Adresse.
Uri deeplAdresse(String schluessel) => Uri.parse(
      schluessel.trim().endsWith(':fx')
          ? 'https://api-free.deepl.com/v2/translate'
          : 'https://api.deepl.com/v2/translate',
    );

/// Der Inhalt einer Anfrage: alle Texte auf einmal, aus dem Deutschen.
String deeplAnfrage(List<String> texte, {String ziel = 'EN-GB'}) => [
      for (final t in texte) 'text=${Uri.encodeQueryComponent(t)}',
      'source_lang=DE',
      'target_lang=${Uri.encodeQueryComponent(ziel)}',
    ].join('&');

/// Liest die Antwort: die übersetzten Texte in derselben Reihenfolge.
/// Wirft [DeepLFehler], wenn sie nicht passt.
List<String> deeplAntwort(String body, int anzahl) {
  final Object? json;
  try {
    json = jsonDecode(body);
  } on FormatException {
    throw const DeepLFehler('DeepL hat keine lesbare Antwort geschickt.');
  }
  final liste = json is Map<String, dynamic> ? json['translations'] : null;
  if (liste is! List || liste.length != anzahl) {
    throw const DeepLFehler('Die Antwort von DeepL passt nicht zur Anfrage.');
  }
  return [
    for (final t in liste)
      if (t is Map<String, dynamic> && t['text'] is String)
        t['text'] as String
      else
        throw const DeepLFehler('Die Antwort von DeepL ist unvollständig.'),
  ];
}

/// Ein Fehler beim Übersetzen — mit einer Meldung für die Oberfläche.
class DeepLFehler implements Exception {
  const DeepLFehler(this.meldung);

  final String meldung;

  @override
  String toString() => meldung;
}

/// Übersetzt [texte] mit DeepL nach [ziel]. Wirft [DeepLFehler].
Future<List<String>> deeplUebersetzen(
  List<String> texte,
  String schluessel, {
  String ziel = 'EN-GB',
  Duration zeitlimit = const Duration(seconds: 30),
}) async {
  if (texte.isEmpty) return const [];
  final client = HttpClient()..connectionTimeout = zeitlimit;
  try {
    final anfrage = await client.postUrl(deeplAdresse(schluessel));
    anfrage.headers
      ..set(
        HttpHeaders.authorizationHeader,
        'DeepL-Auth-Key ${schluessel.trim()}',
      )
      ..contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
    anfrage.add(utf8.encode(deeplAnfrage(texte, ziel: ziel)));
    final antwort = await anfrage.close().timeout(zeitlimit);
    final body = await antwort.transform(utf8.decoder).join();
    switch (antwort.statusCode) {
      case 200:
        return deeplAntwort(body, texte.length);
      case 403:
        throw const DeepLFehler('DeepL kennt den Schlüssel nicht.');
      case 456:
        throw const DeepLFehler(
          'Das Kontingent des DeepL-Schlüssels ist aufgebraucht.',
        );
      case 429:
        throw const DeepLFehler(
          'Zu viele Anfragen an DeepL — bitte gleich noch einmal.',
        );
      default:
        throw DeepLFehler('DeepL antwortet mit Fehler ${antwort.statusCode}.');
    }
  } on SocketException catch (e) {
    throw DeepLFehler('Keine Verbindung zu DeepL: ${e.message}');
  } on HandshakeException {
    throw const DeepLFehler('Die sichere Verbindung zu DeepL schlug fehl.');
  } on TimeoutException {
    throw const DeepLFehler('DeepL hat nicht rechtzeitig geantwortet.');
  } finally {
    client.close();
  }
}
