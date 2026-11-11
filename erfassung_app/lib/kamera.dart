import 'package:erfassung_format/erfassung_format.dart'
    show kFotoKante, kFotoQualitaet;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

// Die Kamera des Handys: Die App ruft die Kamera-App auf und bekommt das
// Bild zurück — schon verkleinert (längere Kante 1600 px, JPEG). Dafür
// braucht sie weder die Kamera-Berechtigung noch das Netz.

/// Ein Foto ließ sich nicht aufnehmen — mit einem Satz, der sagt, warum.
class FotoFehler implements Exception {
  const FotoFehler(this.meldung);

  final String meldung;

  @override
  String toString() => meldung;
}

/// Woher die Fotos kommen — für Tests austauschbar.
abstract class Kamera {
  /// Nimmt ein Foto auf und gibt den Pfad der Datei zurück — null, wenn
  /// abgebrochen wurde. Wirft einen [FotoFehler], wenn es nicht geht.
  Future<String?> aufnehmen();

  /// Das Foto einer Aufnahme, während der Android die App geschlossen
  /// hat — null: keins.
  Future<String?> verlorenes();
}

/// Die Kamera-App des Handys.
class GeraeteKamera implements Kamera {
  GeraeteKamera();

  final ImagePicker _picker = ImagePicker();

  @override
  Future<String?> aufnehmen() async {
    try {
      final bild = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: kFotoKante.toDouble(),
        maxHeight: kFotoKante.toDouble(),
        imageQuality: kFotoQualitaet,
      );
      return bild?.path;
    } on PlatformException catch (e) {
      throw FotoFehler(
        switch (e.code) {
          'no_available_camera' => 'Auf diesem Gerät gibt es keine Kamera-App.',
          'camera_access_denied' =>
            'Die Kamera ist für diese App gesperrt — in den Einstellungen '
                'von Android freigeben.',
          _ => 'Die Kamera ließ sich nicht öffnen: ${e.message ?? e.code}',
        },
      );
    } on MissingPluginException {
      throw const FotoFehler('Die Kamera gibt es hier nicht.');
    }
  }

  @override
  Future<String?> verlorenes() async {
    try {
      final antwort = await _picker.retrieveLostData();
      if (antwort.isEmpty) return null;
      return antwort.file?.path;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    } on UnimplementedError {
      // Nur Android kennt das.
      return null;
    }
  }
}
