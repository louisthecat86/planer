import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:erfassung_format/erfassung_format.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'kamera.dart';
import 'stand.dart';

/// Das Ergebnis als Datei: was darin steht, die Bytes zum Speichern und
/// wie viele Fotos fehlen, weil ihr Bild nicht mehr auf dem Handy liegt.
typedef ErgebnisDatei = ({
  ErfassungsErgebnis ergebnis,
  Uint8List bytes,
  int fotosFehlen,
});

/// Der Stand der Erfassung für die Oberfläche: Jede Änderung wird sofort
/// im Ordner der App gespeichert — die App darf jederzeit zugehen. Die
/// Fotos liegen als einzelne Dateien im Ordner `fotos` daneben.
class ErfassungsModell extends ChangeNotifier {
  ErfassungsModell({
    File? datei,
    Erfassungsstand? stand,
    Directory? fotoOrdner,
    Kamera? kamera,
    Random? zufall,
  })  : _datei = datei,
        _stand = stand ?? Erfassungsstand(),
        _fotoOrdner = fotoOrdner,
        _kamera = kamera,
        _zufall = zufall ?? Random.secure();

  final File? _datei;
  final Directory? _fotoOrdner;
  final Kamera? _kamera;
  final Random _zufall;
  Erfassungsstand _stand;

  Erfassungsstand get stand => _stand;

  /// Was beim Speichern zuletzt schiefging — null: alles gut.
  String? speicherFehler;

  /// Ein Satz, den die Startseite einmal zeigt — etwa nach einem Foto,
  /// während dessen Aufnahme Android die App geschlossen hatte.
  String? meldung;

  /// Lädt den gespeicherten Stand aus dem Ordner der App.
  static Future<ErfassungsModell> laden() async {
    try {
      final ordner = await getApplicationDocumentsDirectory();
      final datei = File('${ordner.path}/erfassung_stand.json');
      final text = datei.existsSync() ? await datei.readAsString() : null;
      final modell = ErfassungsModell(
        datei: datei,
        stand: Erfassungsstand.ausText(text),
        fotoOrdner: Directory('${ordner.path}/fotos'),
        kamera: GeraeteKamera(),
      );
      await modell.fotosAufraeumen();
      return modell;
    } catch (e) {
      return ErfassungsModell()
        ..speicherFehler = 'Der Speicher der App ist nicht erreichbar: $e';
    }
  }

  /// Nach jeder Änderung: speichern und die Oberfläche neu zeichnen.
  Future<void> _geaendert() async {
    notifyListeners();
    final datei = _datei;
    if (datei == null) return;
    try {
      // Erst daneben schreiben, dann umbenennen — so bleibt bei einem
      // Abbruch der alte Stand heil.
      final neu = File('${datei.path}.neu');
      await neu.writeAsString(_stand.alsText(), flush: true);
      await neu.rename(datei.path);
      if (speicherFehler != null) {
        speicherFehler = null;
        notifyListeners();
      }
    } catch (e) {
      speicherFehler = 'Der Stand ließ sich nicht speichern: $e';
      notifyListeners();
    }
  }

  /// Ob [paket] das geöffnete ist.
  bool istGeoeffnet(ErfassungsPaket paket) => _stand.paket?.id == paket.id;

  Future<void> paketOeffnen(ErfassungsPaket paket) async {
    if (!_stand.paketOeffnen(paket)) return;
    await _geaendert();
    await _fotoDateienAbgleichen();
  }

  Future<void> kuerzelSetzen(String kuerzel) async {
    _stand.kuerzel = kuerzel.trim();
    await _geaendert();
  }

  Future<void> produktionErfassen(ErfassteProduktion e) async {
    _stand.produktionErfassen(e);
    await _geaendert();
  }

  /// Speichert eine begonnene Erfassung zwischen — siehe
  /// [ProduktionsEntwurf].
  Future<void> entwurfMerken(ProduktionsEntwurf e) async {
    if (_stand.entwurfMerken(e)) await _geaendert();
  }

  Future<void> entwurfLoeschen(String produktionId) async {
    if (_stand.entwurfLoeschen(produktionId)) await _geaendert();
  }

  Future<void> produktionLoeschen(String produktionId) async {
    _stand.produktionLoeschen(produktionId);
    await _geaendert();
  }

  Future<void> wertSetzen({
    required PaketArtikel artikel,
    required PaketSchritt schritt,
    required PaketFeld feld,
    required String? neu,
  }) async {
    _stand.wertSetzen(
      artikel: artikel,
      schritt: schritt,
      feld: feld,
      neu: neu,
      jetzt: DateTime.now(),
    );
    await _geaendert();
  }

  /// Merkt, dass das Ergebnis als Datei gespeichert ist.
  Future<void> ergebnisGespeichert(DateTime am) async {
    _stand.gespeichertAm = am;
    await _geaendert();
  }

  /// Verwirft Paket und Erfasstes — das Kürzel bleibt.
  Future<void> leeren() async {
    _stand = Erfassungsstand(kuerzel: _stand.kuerzel);
    await _geaendert();
    await _fotoDateienAbgleichen();
  }

  // ── Fotos ───────────────────────────────────────────────────────────

  /// Die Datei mit dem Bild des Fotos [id] — null ohne Speicher.
  File? fotoDatei(String id) {
    final ordner = _fotoOrdner;
    return ordner == null ? null : File('${ordner.path}/$id.jpg');
  }

  /// Öffnet die Kamera und hält das Foto fest: mit [artikelId] als Foto
  /// aus der Produktion dieses Artikels, ohne als Musterfoto mit
  /// [bezeichnung]. Gibt zurück, ob ein Foto dazugekommen ist — false,
  /// wenn an der Kamera abgebrochen wurde. Wirft einen [FotoFehler], wenn
  /// es nicht geht.
  Future<bool> fotoAufnehmen({
    String? artikelId,
    String? artikel,
    String? produktionId,
    String? bezeichnung,
  }) async {
    final kamera = _kamera;
    if (kamera == null || _fotoOrdner == null) {
      throw const FotoFehler('Der Speicher der App ist nicht erreichbar.');
    }
    final jetzt = DateTime.now();
    final foto = _stand.fotoAnlegen(
      id: neueFotoId(jetzt, _zufall.nextInt(1 << 32)),
      jetzt: jetzt,
      artikelId: artikelId,
      artikel: artikel,
      produktionId: produktionId,
      bezeichnung: bezeichnung,
    );
    // Vor der Kamera merken, wozu das Bild gehört: Schließt Android die
    // App, solange die Kamera vorn ist, findet der nächste Start es so
    // wieder (fotosAufraeumen).
    _stand.fotoWartend = foto;
    await _geaendert();
    final String? pfad;
    try {
      pfad = await kamera.aufnehmen();
    } catch (_) {
      _stand.fotoWartend = null;
      await _geaendert();
      rethrow;
    }
    return _fotoAblegen(foto, pfad);
  }

  /// Legt das Bild unter [pfad] als Datei des Fotos ab.
  Future<bool> _fotoAblegen(ErfasstesFoto foto, String? pfad) async {
    _stand.fotoWartend = null;
    if (pfad == null) {
      await _geaendert();
      return false;
    }
    try {
      final quelle = File(pfad);
      final ziel = fotoDatei(foto.id)!;
      await ziel.parent.create(recursive: true);
      await quelle.copy(ziel.path);
      _stand.fotoHinzu(foto, groesse: await ziel.length());
      try {
        // Die Kopie der Kamera im Zwischenspeicher braucht niemand mehr.
        await quelle.delete();
      } on FileSystemException {
        // Android räumt den Zwischenspeicher selbst auf.
      }
      return true;
    } on FileSystemException catch (e) {
      throw FotoFehler('Das Foto ließ sich nicht speichern: ${e.message}');
    } finally {
      await _geaendert();
    }
  }

  Future<void> fotoLoeschen(String id) async {
    _stand.fotoLoeschen(id);
    await _geaendert();
    try {
      final datei = fotoDatei(id);
      if (datei != null && await datei.exists()) await datei.delete();
    } on FileSystemException {
      // Bleibt liegen — der nächste Start räumt auf.
    }
  }

  /// Beim Start: Holt ein Foto nach, während dessen Aufnahme Android die
  /// App geschlossen hat, und löscht Bilder, die zu keinem Foto gehören.
  Future<void> fotosAufraeumen() async {
    final wartend = _stand.fotoWartend;
    if (wartend != null) {
      try {
        final pfad = await _kamera?.verlorenes();
        if (await _fotoAblegen(wartend, pfad)) {
          meldung = 'Das Foto von eben ist gespeichert.';
        }
      } catch (_) {
        _stand.fotoWartend = null;
        await _geaendert();
      }
    }
    await _fotoDateienAbgleichen();
  }

  /// Löscht die Bilder im Foto-Ordner, die zu keinem Foto des Stands
  /// gehören.
  Future<void> _fotoDateienAbgleichen() async {
    final ordner = _fotoOrdner;
    try {
      if (ordner == null || !await ordner.exists()) return;
      final behalten = {
        for (final id in _stand.fotos.keys) fotoDatei(id)!.path,
      };
      await for (final e in ordner.list()) {
        if (e is File && !behalten.contains(e.path)) await e.delete();
      }
    } on FileSystemException {
      // Beim nächsten Mal.
    }
  }

  /// Das Ergebnis für den Planer samt der Bilder der Fotos — null ohne
  /// Paket.
  Future<ErgebnisDatei?> ergebnisDatei(DateTime jetzt) async {
    final bilder = <String, Uint8List>{};
    for (final id in _stand.fotos.keys) {
      try {
        final datei = fotoDatei(id);
        if (datei != null && await datei.exists()) {
          bilder[id] = await datei.readAsBytes();
        }
      } on FileSystemException {
        // Zählt unten als fehlend.
      }
    }
    final ergebnis = _stand.ergebnis(jetzt, bilder: bilder);
    if (ergebnis == null) return null;
    return (
      ergebnis: ergebnis,
      bytes: utf8.encode(ergebnis.alsText()),
      fotosFehlen: _stand.fotos.length - bilder.length,
    );
  }
}

/// Liest ein Paket aus den Bytes einer Datei — oder wirft einen
/// [FormatFehler] mit dem Grund.
ErfassungsPaket paketAusBytes(List<int> bytes) =>
    ErfassungsPaket.ausText(utf8.decode(bytes, allowMalformed: true));

/// Die Datei, mit der die App über „Öffnen mit" gestartet wurde.
class GeoeffneteDatei {
  GeoeffneteDatei._();

  static const _kanal = MethodChannel('planer_erfassung/datei');

  /// Der Text der Datei, die auf das Öffnen wartet — null: keine.
  static Future<String?> holen() async {
    try {
      return await _kanal.invokeMethod<String>('geoeffneteDatei');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Ruft [beiDatei], wenn bei laufender App eine Datei geöffnet wird.
  static void lauschen(VoidCallback beiDatei) {
    _kanal.setMethodCallHandler((aufruf) async {
      if (aufruf.method == 'dateiGeoeffnet') beiDatei();
    });
  }
}
