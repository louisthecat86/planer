import 'dart:async';
import 'dart:isolate';

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';

/// Abschnitt, in dem das Einlesen gerade steckt.
enum NavisionPhase {
  /// Die Arbeitsmappe wird geöffnet. Dieser Abschnitt lässt sich nicht
  /// unterteilen — das Excel-Paket liest die Datei am Stück ein und meldet
  /// dabei nichts nach außen.
  datei,

  /// Die Datenzeilen werden ausgewertet. Hier gibt es echte Zwischenstände.
  zeilen,
}

/// Zwischenstand eines laufenden Einlesens.
class NavisionFortschritt {
  const NavisionFortschritt({
    required this.phase,
    this.aktuell = 0,
    this.gesamt = 0,
  });

  final NavisionPhase phase;
  final int aktuell;
  final int gesamt;

  /// Anteil 0..1, oder null wenn der Abschnitt keine Zwischenstände liefert
  /// (dann gehört ein unbestimmter Balken hin, kein Prozentwert).
  double? get anteil {
    if (gesamt <= 0) return null;
    return (aktuell / gesamt).clamp(0.0, 1.0);
  }

  String get beschriftung => switch (phase) {
        NavisionPhase.datei => 'Datei wird geöffnet …',
        NavisionPhase.zeilen => gesamt > 0
            ? 'Artikel werden gelesen … $aktuell von $gesamt'
            : 'Artikel werden gelesen …',
      };
}

/// Ein Artikel aus der Navision-Artikelübersicht.
class NavisionZeile {
  const NavisionZeile({
    required this.nummer,
    this.beschreibung = '',
    this.beschreibung2,
    this.suchbegriff,
    this.basiseinheit,
    this.produktbuchungsgruppe,
    this.artikelkategorie,
    this.produktgruppe,
  });

  /// Artikelnummer (Spalte „Nr.") — dieselbe wie in der App.
  final String nummer;
  final String beschreibung;
  final String? beschreibung2;

  /// Suchbegriff — trägt bei euch u.a. die Allergen-Hinweise.
  final String? suchbegriff;
  final String? basiseinheit;
  final String? produktbuchungsgruppe;
  final String? artikelkategorie;
  final String? produktgruppe;
}

/// Was aus einer Navision-Artikelübersicht gelesen wurde.
class NavisionKatalog {
  const NavisionKatalog({
    required this.zeilen,
    required this.warnungen,
    required this.gelesen,
  });

  final List<NavisionZeile> zeilen;
  final List<String> warnungen;

  /// Datenzeilen mit Artikelnummer.
  final int gelesen;
}

/// Liest die Navision-Artikelübersicht (Excel-Export aus NAV) ein.
///
/// Nur noch für den Artikelstamm: Nummer, Bezeichnungen, Gruppen und der
/// Suchbegriff mit den Allergen-Hinweisen. Bestand und offene Aufträge
/// liefert der Auftragsbestand — genauer, nämlich je Auftrag und
/// Versandtag.
///
/// Der Aufbau der Datei: Zeile 1 und 2 tragen Serverangabe und Titel,
/// Zeile 3 die Spaltenüberschriften, ab Zeile 4 die Artikel. Statt feste
/// Spaltenpositionen anzunehmen, wird die Kopfzeile ausgewertet — so
/// übersteht das Einlesen auch eine geänderte Spaltenreihenfolge oder
/// zusätzliche Felder aus NAV.
class NavisionImportService {
  const NavisionImportService._();

  /// Feldname → mögliche Überschriften in der Navision-Ausgabe.
  ///
  /// Bewusst mit Aliasen: Jeder Mitarbeiter hat in Navision seine eigene
  /// Spaltenansicht — Spalten können fehlen, zusätzlich da sein, anders
  /// heißen oder in anderer Reihenfolge stehen. Verglichen wird
  /// normalisiert (klein, ohne Punkte/Leerzeichen, Umlaute aufgelöst),
  /// damit „Nr.", „Nr" und „Artikelnr." alle passen.
  static const Map<String, List<String>> _spaltenAliase = {
    'nummer': ['nr', 'nummer', 'artikelnr', 'artikelnummer', 'artikel'],
    'beschreibung': [
      'beschreibung',
      'beschreibung1',
      'bezeichnung',
      'artikelbeschreibung',
      'artikelbezeichnung',
      'name',
    ],
    'beschreibung2': ['beschreibung2', 'bezeichnung2'],
    'suchbegriff': ['suchbegriff'],
    'basiseinheit': [
      'basiseinheitencode',
      'basiseinheit',
      'einheitencode',
      'einheit',
      'masseinheit',
    ],
    'produktbuchungsgruppe': ['produktbuchungsgruppe', 'produktbuchungsgr'],
    'artikelkategorie': ['artikelkategoriencode', 'artikelkategorie'],
    'produktgruppe': ['produktgruppencode', 'produktgruppe'],
  };

  /// Umgekehrte Zuordnung Überschrift → Feldname (einmal aufgebaut).
  static final Map<String, String> _feldVonUeberschrift = {
    for (final e in _spaltenAliase.entries)
      for (final alias in e.value) alias: e.key,
  };

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll('.', '')
      .replaceAll('-', '')
      .replaceAll('/', '')
      .replaceAll(' ', '')
      .replaceAll('ä', 'a')
      .replaceAll('ö', 'o')
      .replaceAll('ü', 'u')
      .replaceAll('ß', 'ss');

  static String? _text(Data? zelle) {
    final v = zelle?.value;
    if (v == null) return null;
    if (v is TextCellValue) return v.value.text?.trim();
    if (v is IntCellValue) return v.value.toString();
    if (v is DoubleCellValue) {
      final d = v.value;
      return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
    }
    return v.toString().trim();
  }

  /// Liest die Navision-Artikelübersicht aus den Roh-Bytes einer .xlsx.
  ///
  /// Bewusst Bytes statt Dateipfad: Auf dem Desktop liefert der FilePicker
  /// mit Custom-Filter teils gar keinen Pfad (nur Bytes), und Bytes
  /// funktionieren auf jeder Plattform gleich.
  ///
  /// Geparst wird auf einem eigenen Isolate — gut 4.000 Zeilen durch den
  /// XML-Parser blockierten sonst das Fenster.
  static Future<NavisionKatalog> lese(
    Uint8List bytes, {
    void Function(NavisionFortschritt)? onFortschritt,
  }) async {
    // Grober Format-Check: echte .xlsx sind ZIP-Container und beginnen mit
    // der Signatur „PK" (0x50 0x4B). Ein umbenanntes altes .xls oder eine
    // als Excel getarnte HTML-Tabelle hat das nicht — dann sofort raus mit
    // klarer Ansage statt kryptischem Parser-Crash.
    if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
      throw const FormatException(
        'Das ist keine echte Excel-Datei (.xlsx). In Navision bitte über '
        '„Öffnen in Excel" bzw. „Nach Microsoft Excel" exportieren und die '
        'so erzeugte .xlsx wählen — ein umbenanntes .xls oder eine '
        'HTML-Tabelle kann die App nicht lesen.',
      );
    }

    onFortschritt?.call(
      const NavisionFortschritt(phase: NavisionPhase.datei),
    );

    // Fortschritt aus dem Isolate: Ein SendPort ist übertragbar, deshalb
    // kann das Parse-Isolate Zwischenstände zurückmelden.
    ReceivePort? port;
    StreamSubscription<dynamic>? lauscher;
    if (onFortschritt != null) {
      port = ReceivePort();
      lauscher = port.listen((dynamic nachricht) {
        if (nachricht is! List || nachricht.length != 2) return;
        final aktuell = nachricht[0];
        final gesamt = nachricht[1];
        if (aktuell is! int || gesamt is! int) return;
        onFortschritt(
          NavisionFortschritt(
            phase: NavisionPhase.zeilen,
            aktuell: aktuell,
            gesamt: gesamt,
          ),
        );
      });
    }

    final Map<String, Object?> roh;
    try {
      roh = await _parseImIsolate(bytes, port?.sendPort);
    } finally {
      await lauscher?.cancel();
      port?.close();
    }

    final zeilen = <NavisionZeile>[];
    for (final z in (roh['zeilen']! as List<Object?>)) {
      if (z is! Map) continue;
      final nummer = z['nummer'];
      if (nummer is! String) continue;
      zeilen.add(
        NavisionZeile(
          nummer: nummer,
          beschreibung: (z['beschreibung'] as String?) ?? '',
          beschreibung2: z['beschreibung2'] as String?,
          suchbegriff: z['suchbegriff'] as String?,
          basiseinheit: z['basiseinheit'] as String?,
          produktbuchungsgruppe: z['produktbuchungsgruppe'] as String?,
          artikelkategorie: z['artikelkategorie'] as String?,
          produktgruppe: z['produktgruppe'] as String?,
        ),
      );
    }
    final warnungen = [
      for (final w in (roh['warnungen']! as List<Object?>))
        if (w is String) w,
    ];

    debugPrint(
      '[NAV] gelesen=${roh['gelesen']} · Artikel=${zeilen.length} · '
      'Hinweise=${warnungen.length}',
    );

    return NavisionKatalog(
      zeilen: zeilen,
      warnungen: warnungen,
      gelesen: roh['gelesen']! as int,
    );
  }

  /// Startet [_parseKatalog] auf einem eigenen Isolate.
  ///
  /// Diese Methode MUSS statisch bleiben: Eine Closure übernimmt beim
  /// Erzeugen ihren umgebenden Kontext, und eine offene
  /// Datenbankverbindung ist nicht zwischen Isolaten übertragbar. In einer
  /// statischen Methode gibt es kein `this` — übertragen wird nur [bytes].
  static Future<Map<String, Object?>> _parseImIsolate(
    Uint8List bytes,
    SendPort? fortschritt,
  ) {
    return Isolate.run(() => _parseKatalog(bytes, fortschritt));
  }

  /// Parst die Arbeitsmappe zu reinen Daten.
  ///
  /// Läuft auf einem eigenen Isolate und gibt deshalb eine schlichte Map
  /// aus Listen, Maps, Strings und Zahlen zurück.
  static Map<String, Object?> _parseKatalog(
    Uint8List bytes,
    SendPort? fortschritt,
  ) {
    final warnungen = <String>[];

    final Excel excel;
    try {
      excel = Excel.decodeBytes(bytes);
    } catch (e) {
      throw FormatException('Die Datei ließ sich nicht als Excel öffnen: $e');
    }

    if (excel.tables.isEmpty) {
      throw const FormatException('Die Datei enthält kein Tabellenblatt.');
    }
    final tabelle = excel.tables[excel.tables.keys.first];
    if (tabelle == null) {
      throw const FormatException('Die Datei enthält keine Daten.');
    }
    // EINMAL auslesen und festhalten: `Sheet.rows` baut bei jedem Zugriff
    // die komplette Zeilenliste neu auf.
    final zeilenRoh = tabelle.rows;
    final anzahlZeilen = zeilenRoh.length;
    if (anzahlZeilen == 0) {
      throw const FormatException('Die Datei enthält keine Daten.');
    }

    // Kopfzeile suchen — die Zeile mit den MEISTEN erkannten Spalten, in
    // der die Artikelnummer vorkommt.
    int? kopfZeile;
    Map<String, int> spalteVon = {};
    var besteTreffer = 0;
    final maxPruefen = anzahlZeilen < 40 ? anzahlZeilen : 40;
    for (var r = 0; r < maxPruefen; r++) {
      final zeile = zeilenRoh[r];
      final treffer = <String, int>{};
      for (var c = 0; c < zeile.length; c++) {
        final feld = _feldVonUeberschrift[_norm(_text(zeile[c]) ?? '')];
        // Erste Fundstelle gewinnt — doppelte Überschriften kippen die
        // Zuordnung damit nicht.
        if (feld != null && !treffer.containsKey(feld)) treffer[feld] = c;
      }
      if (!treffer.containsKey('nummer')) continue;
      if (treffer.length > besteTreffer) {
        besteTreffer = treffer.length;
        kopfZeile = r;
        spalteVon = treffer;
      }
    }

    if (kopfZeile == null) {
      final gefunden = <String>[];
      for (var r = 0; r < maxPruefen && gefunden.length < 15; r++) {
        for (final c in zeilenRoh[r]) {
          final t = _text(c);
          if (t != null && t.isNotEmpty) gefunden.add(t);
          if (gefunden.length >= 15) break;
        }
      }
      throw FormatException(
        'Keine Kopfzeile mit einer Artikelnummer-Spalte gefunden. Erwartet '
        'wird eine Spalte „Nr." (auch „Artikelnr." o.ä.). '
        'Gefundene Überschriften: ${gefunden.join(' | ')}',
      );
    }

    // Ab hier bricht nichts mehr ab: Fehlende Spalten werden gemeldet,
    // die betroffenen Felder bleiben leer.
    if (!spalteVon.containsKey('beschreibung')) {
      warnungen.add(
        'Spalte „Beschreibung" fehlt in dieser Ansicht — neue Artikel '
        'bekommen die Nummer als Bezeichnung.',
      );
    }
    if (!spalteVon.containsKey('suchbegriff')) {
      warnungen.add(
        'Spalte „Suchbegriff" fehlt — ohne sie gibt es keine '
        'Allergen-Vorschläge. In Navision bitte einblenden.',
      );
    }

    String? feld(List<Data?> zeile, String name) {
      final c = spalteVon[name];
      if (c == null || c >= zeile.length) return null;
      final t = _text(zeile[c]);
      return (t == null || t.isEmpty) ? null : t;
    }

    final zeilen = <Map<String, Object?>>[];
    final gesehen = <String>{};
    var gelesen = 0;

    final ersteDatenZeile = kopfZeile + 1;
    final gesamtZeilen = anzahlZeilen - ersteDatenZeile;
    void melde(int fertig) =>
        fortschritt?.send(<Object?>[fertig, gesamtZeilen]);

    melde(0);
    for (var r = ersteDatenZeile; r < anzahlZeilen; r++) {
      // Alle 200 Zeilen melden — oft genug für einen flüssigen Balken,
      // selten genug, dass das Verschicken nicht ins Gewicht fällt.
      if ((r - ersteDatenZeile) % 200 == 0) melde(r - ersteDatenZeile);
      final zeile = zeilenRoh[r];
      final nummer = feld(zeile, 'nummer');
      if (nummer == null) continue;
      gelesen++;
      // Doppelte Nummern: die erste gewinnt.
      if (!gesehen.add(nummer)) continue;

      zeilen.add(<String, Object?>{
        'nummer': nummer,
        'beschreibung': feld(zeile, 'beschreibung') ?? '',
        'beschreibung2': feld(zeile, 'beschreibung2'),
        'suchbegriff': feld(zeile, 'suchbegriff'),
        'basiseinheit': feld(zeile, 'basiseinheit'),
        'produktbuchungsgruppe': feld(zeile, 'produktbuchungsgruppe'),
        'artikelkategorie': feld(zeile, 'artikelkategorie'),
        'produktgruppe': feld(zeile, 'produktgruppe'),
      });
    }
    melde(gesamtZeilen);

    return <String, Object?>{
      'zeilen': zeilen,
      'warnungen': warnungen,
      'gelesen': gelesen,
    };
  }
}
