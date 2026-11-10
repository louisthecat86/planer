import 'dart:convert';
import 'dart:io';

import 'package:erfassung_format/erfassung_format.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'stand.dart';

/// Der Stand der Erfassung für die Oberfläche: Jede Änderung wird sofort
/// im Ordner der App gespeichert — die App darf jederzeit zugehen.
class ErfassungsModell extends ChangeNotifier {
  ErfassungsModell({File? datei, Erfassungsstand? stand})
      : _datei = datei,
        _stand = stand ?? Erfassungsstand();

  final File? _datei;
  Erfassungsstand _stand;

  Erfassungsstand get stand => _stand;

  /// Was beim Speichern zuletzt schiefging — null: alles gut.
  String? speicherFehler;

  /// Lädt den gespeicherten Stand aus dem Ordner der App.
  static Future<ErfassungsModell> laden() async {
    try {
      final ordner = await getApplicationDocumentsDirectory();
      final datei = File('${ordner.path}/erfassung_stand.json');
      final text = datei.existsSync() ? await datei.readAsString() : null;
      return ErfassungsModell(
        datei: datei,
        stand: Erfassungsstand.ausText(text),
      );
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
    if (_stand.paketOeffnen(paket)) await _geaendert();
  }

  Future<void> kuerzelSetzen(String kuerzel) async {
    _stand.kuerzel = kuerzel.trim();
    await _geaendert();
  }

  Future<void> produktionErfassen(ErfassteProduktion e) async {
    _stand.produktionErfassen(e);
    await _geaendert();
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
