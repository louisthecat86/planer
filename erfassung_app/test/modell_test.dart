import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:erfassung/kamera.dart';
import 'package:erfassung/modell.dart';
import 'package:erfassung/stand.dart';
import 'package:erfassung_format/erfassung_format.dart';
import 'package:flutter_test/flutter_test.dart';

import 'beispiel.dart';

/// Eine Kamera, die fertige Dateien liefert — oder abbricht oder scheitert.
class _TestKamera implements Kamera {
  _TestKamera(this.ordner);

  final Directory ordner;

  /// Was die nächste Aufnahme liefert: Bytes, null (abgebrochen) oder ein
  /// Fehler.
  Object? naechstes;

  /// Was nach einem Neustart als verlorene Aufnahme wartet.
  List<int>? verloren;

  int _n = 0;

  String _datei(List<int> bytes) {
    final d = File('${ordner.path}/kamera_${_n++}.jpg')
      ..writeAsBytesSync(bytes);
    return d.path;
  }

  @override
  Future<String?> aufnehmen() async {
    final n = naechstes;
    if (n is FotoFehler) throw n;
    return n is List<int> ? _datei(n) : null;
  }

  @override
  Future<String?> verlorenes() async {
    final v = verloren;
    return v == null ? null : _datei(v);
  }
}

/// Fotos im Modell der App: Die Kamera liefert eine Datei, die App legt
/// sie in ihren Ordner; abgebrochene und gescheiterte Aufnahmen
/// hinterlassen nichts; das Ergebnis trägt die Bilder; und eine Aufnahme,
/// während der Android die App geschlossen hat, kommt beim nächsten Start
/// an. Ohne Oberfläche, in einem eigenen Ordner; alles erfunden.
void main() {
  late Directory ordner;
  late Directory zwischen;
  late _TestKamera kamera;
  late File standDatei;

  final bildA = [0xFF, 0xD8, 0xFF, 1, 2, 3, 4];
  final bildB = [0xFF, 0xD8, 0xFF, 9, 8];

  setUp(() {
    ordner = Directory.systemTemp.createTempSync('erfassung_modell_');
    zwischen = Directory('${ordner.path}/cache')..createSync();
    kamera = _TestKamera(zwischen);
    standDatei = File('${ordner.path}/erfassung_stand.json');
  });

  tearDown(() {
    if (ordner.existsSync()) ordner.deleteSync(recursive: true);
  });

  ErfassungsModell modell({Erfassungsstand? stand}) => ErfassungsModell(
        datei: standDatei,
        stand: stand ?? (Erfassungsstand(kuerzel: 'AB')),
        fotoOrdner: Directory('${ordner.path}/fotos'),
        kamera: kamera,
        zufall: Random(1),
      );

  List<String> fotoDateien() {
    final d = Directory('${ordner.path}/fotos');
    return d.existsSync()
        ? [for (final e in d.listSync()) e.uri.pathSegments.last]
        : [];
  }

  test('aufnehmen: das Bild liegt im Ordner der App, die Angaben im Stand',
      () async {
    final m = modell();
    await m.paketOeffnen(beispielPaket());

    kamera.naechstes = bildA;
    expect(
      await m.fotoAufnehmen(
        artikelId: 'a1',
        artikel: 'Grillwurst',
        produktionId: 't1',
      ),
      isTrue,
    );
    final foto = m.stand.fotos.values.single;
    expect(foto.art, FotoArt.produktion);
    expect(foto.artikelId, 'a1');
    expect(foto.produktionId, 't1');
    expect(foto.kuerzel, 'AB');
    expect(foto.groesse, bildA.length);
    expect(m.fotoDatei(foto.id)!.readAsBytesSync(), bildA);
    expect(m.stand.fotoWartend, isNull);
    expect(m.stand.ungesichert, isTrue);
    // Die Kopie der Kamera ist weg.
    expect(zwischen.listSync(), isEmpty);

    kamera.naechstes = bildB;
    expect(await m.fotoAufnehmen(bezeichnung: 'Pfeffer grob'), isTrue);
    expect(m.stand.musterfotos.single.bezeichnung, 'Pfeffer grob');
    expect(fotoDateien(), hasLength(2));

    // Gespeichert ist auch der Stand — ohne die Bilder.
    final gespeichert = Erfassungsstand.ausText(standDatei.readAsStringSync());
    expect(gespeichert.fotos.keys.toSet(), m.stand.fotos.keys.toSet());
    expect(standDatei.lengthSync(), lessThan(20000));
  });

  test('abgebrochen oder gescheitert: nichts bleibt zurück', () async {
    final m = modell();
    await m.paketOeffnen(beispielPaket());

    kamera.naechstes = null;
    expect(await m.fotoAufnehmen(bezeichnung: 'M'), isFalse);
    expect(m.stand.fotos, isEmpty);
    expect(m.stand.fotoWartend, isNull);
    expect(m.stand.hatErfasstes, isFalse);

    kamera.naechstes = const FotoFehler('Keine Kamera.');
    await expectLater(
      m.fotoAufnehmen(bezeichnung: 'M'),
      throwsA(isA<FotoFehler>()),
    );
    expect(m.stand.fotos, isEmpty);
    expect(m.stand.fotoWartend, isNull);
    expect(
      Erfassungsstand.ausText(standDatei.readAsStringSync()).fotoWartend,
      isNull,
    );
    expect(fotoDateien(), isEmpty);
  });

  test('das Ergebnis trägt die Bilder; ein fehlendes wird gezählt', () async {
    final m = modell();
    await m.paketOeffnen(beispielPaket());
    kamera.naechstes = bildA;
    await m.fotoAufnehmen(artikelId: 'a1', artikel: 'Grillwurst');
    kamera.naechstes = bildB;
    await m.fotoAufnehmen(bezeichnung: 'Pfeffer grob');

    final jetzt = DateTime(2026, 11, 10, 18);
    final datei = (await m.ergebnisDatei(jetzt))!;
    expect(datei.fotosFehlen, 0);
    final gelesen = ErfassungsErgebnis.ausText(utf8.decode(datei.bytes));
    expect([for (final f in gelesen.fotos) f.daten], [bildA, bildB]);
    expect(gelesen.fotos.last.bezeichnung, 'Pfeffer grob');

    // Ein Bild ist weg — das Ergebnis kommt trotzdem, mit dem anderen.
    m.fotoDatei(m.stand.musterfotos.single.id)!.deleteSync();
    final ohne = (await m.ergebnisDatei(jetzt))!;
    expect(ohne.fotosFehlen, 1);
    expect(ohne.ergebnis.fotos.single.daten, bildA);
  });

  test('löschen, neues Paket und Leeren nehmen die Bilder mit', () async {
    final m = modell();
    await m.paketOeffnen(beispielPaket());
    kamera.naechstes = bildA;
    await m.fotoAufnehmen(bezeichnung: 'eins');
    kamera.naechstes = bildB;
    await m.fotoAufnehmen(bezeichnung: 'zwei');
    expect(fotoDateien(), hasLength(2));

    await m.fotoLoeschen(m.stand.musterfotos.first.id);
    expect(m.stand.fotos, hasLength(1));
    expect(fotoDateien(), hasLength(1));

    // Dasselbe Paket noch einmal ändert nichts.
    await m.paketOeffnen(beispielPaket());
    expect(fotoDateien(), hasLength(1));
    await m.paketOeffnen(beispielPaket(id: 'paket-2'));
    expect(m.stand.fotos, isEmpty);
    expect(fotoDateien(), isEmpty);

    kamera.naechstes = bildA;
    await m.fotoAufnehmen(bezeichnung: 'drei');
    await m.leeren();
    expect(fotoDateien(), isEmpty);
  });

  test(
      'Android schließt die App an der Kamera: Das Foto kommt beim '
      'nächsten Start an', () async {
    // Der Stand, wie ihn die App vor dem Öffnen der Kamera gespeichert hat.
    final vorher = Erfassungsstand(kuerzel: 'AB')
      ..paketOeffnen(beispielPaket());
    vorher.fotoWartend = vorher.fotoAnlegen(
      id: 'f-wartend',
      jetzt: DateTime(2026, 11, 10, 9),
      artikelId: 'a1',
      artikel: 'Grillwurst',
    );
    // Und ein Bild im Ordner, zu dem es kein Foto gibt.
    Directory('${ordner.path}/fotos').createSync();
    File('${ordner.path}/fotos/verwaist.jpg').writeAsBytesSync(bildB);

    kamera.verloren = bildA;
    final m = modell(stand: Erfassungsstand.ausText(vorher.alsText()));
    await m.fotosAufraeumen();

    expect(m.meldung, isNotNull);
    expect(m.stand.fotoWartend, isNull);
    final foto = m.stand.fotos.values.single;
    expect(foto.id, 'f-wartend');
    expect(foto.artikelId, 'a1');
    expect(m.fotoDatei('f-wartend')!.readAsBytesSync(), bildA);
    expect(fotoDateien(), ['f-wartend.jpg']);

    // Ohne verlorene Aufnahme ist die offene einfach vorbei.
    kamera.verloren = null;
    final ohne = modell(stand: Erfassungsstand.ausText(vorher.alsText()));
    await ohne.fotosAufraeumen();
    expect(ohne.meldung, isNull);
    expect(ohne.stand.fotoWartend, isNull);
    expect(ohne.stand.fotos, isEmpty);
  });
}
