import 'dart:convert';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';

import '../database/database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Gelesener Bericht — reine Daten, ohne Datenbankbezug
// ═══════════════════════════════════════════════════════════════════════════

/// Eine Auftragszeile, wie sie im Bericht steht.
class BerichtPosition {
  const BerichtPosition({
    required this.beleg,
    required this.debitor,
    required this.warenausgang,
    required this.menge,
    required this.kg,
    this.lieferdatum,
    this.einheit,
  });

  final String beleg;
  final String debitor;
  final DateTime warenausgang;
  final DateTime? lieferdatum;
  final double menge;
  final String? einheit;
  final double kg;
}

/// Ein Artikelblock des Berichts: Kopf, Auftragszeilen, Gesamt, Lager.
class BerichtArtikel {
  BerichtArtikel(this.nummer);

  final String nummer;
  String bezeichnung = '';
  String bezeichnung2 = '';

  /// „Nettogewicht Auf Lager" in kg. null, wenn die Zeile fehlte.
  double? lagerKg;

  /// Aus der Zeile „Gesamt": Summe in kg und in der Berichtseinheit.
  double? gesamtKg;
  double? gesamtMenge;
  String? gesamtEinheit;

  final List<BerichtPosition> positionen = [];
}

/// Der ganze Bericht nach dem Lesen und Prüfen.
class AuftragsbestandBericht {
  const AuftragsbestandBericht({
    required this.artikel,
    required this.uebersprungen,
    required this.warnungen,
    this.stand,
    this.von,
    this.bis,
  });

  /// Nur echte Artikel — Artikelnummern aus Ziffern.
  final List<BerichtArtikel> artikel;

  /// Verpackung und Paletten (KT, EURO, H1 …): im Bericht, aber nichts,
  /// was produziert wird.
  final List<String> uebersprungen;

  final List<String> warnungen;

  /// Erzeugungszeitpunkt laut Berichtskopf.
  final DateTime? stand;

  /// Filterzeitraum (Warenausgang) laut Berichtskopf.
  final DateTime? von;
  final DateTime? bis;

  int get anzahlPositionen =>
      artikel.fold<int>(0, (summe, a) => summe + a.positionen.length);

  int get anzahlKunden => {
        for (final a in artikel)
          for (final p in a.positionen) p.debitor,
      }.length;
}

/// Was ein Import in der App angelegt hat.
class AuftragsbestandErgebnis {
  const AuftragsbestandErgebnis({
    required this.artikel,
    required this.positionen,
    required this.kunden,
    required this.uebersprungen,
    required this.warnungen,
    this.stand,
    this.von,
    this.bis,
  });

  final int artikel;
  final int positionen;
  final int kunden;
  final List<String> uebersprungen;
  final List<String> warnungen;
  final DateTime? stand;
  final DateTime? von;
  final DateTime? bis;
}

// ═══════════════════════════════════════════════════════════════════════════
// Import
// ═══════════════════════════════════════════════════════════════════════════

/// Liest den Navision-Bericht „Auftragsbestand" (Report 50018) ein, den
/// Navision über „Speichern unter → Excel" ausgibt.
///
/// Aufbau des Berichts: je Artikel ein Block aus Artikelnummer,
/// Bezeichnung, den Auftragszeilen (Beleg, Kunde, Warenausgang, Menge,
/// Einheit, Nettogewicht), Zwischensummen je Tag, einer Zeile „Gesamt" und
/// dem Lager in kg.
///
/// **Warum kein `excel`-Paket:** Navision schreibt die Datei ohne
/// `sharedStrings.xml` und mit absoluten Verweisen im Paket
/// („/xl/worksheets/sheet1.xml"). Genau daran scheitert das `excel`-Paket
/// mit „Null check operator used on a null value" — dieselbe Meldung wie
/// damals beim Stammdaten-Import. Der Bericht ist aber schlicht aufgebaut:
/// ein Blatt, Texte direkt in der Zelle, Zahlen als Zahl. Das liest dieser
/// Dienst selbst, mit dem `archive`-Paket, das die App ohnehin hat.
/// Speichert jemand die Datei in Excel neu, kommen `sharedStrings.xml` und
/// relative Verweise dazu — auch das wird gelesen.
///
/// **Selbstprüfung:** Jeder Artikelblock endet mit „Gesamt". Die App
/// addiert die gelesenen Zeilen und vergleicht. Weicht auch nur ein
/// Artikel ab, wird nichts gespeichert — ein halb gelesener Bericht wäre
/// schlimmer als keiner, weil er nach vollständigen Zahlen aussähe.
class AuftragsbestandImportService {
  AuftragsbestandImportService(this._db);

  final AppDatabase _db;

  /// Liest [bytes] und ersetzt den gespeicherten Auftragsbestand.
  ///
  /// Wirft eine [FormatException] mit lesbarer Meldung, wenn die Datei
  /// kein Auftragsbestand ist oder die Prüfung fehlschlägt. In dem Fall
  /// bleibt der bisherige Stand unverändert.
  Future<AuftragsbestandErgebnis> importiere(Uint8List bytes) async {
    // Echte .xlsx-Dateien sind ZIP-Pakete und beginnen mit „PK".
    if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
      throw const FormatException(
        'Das ist keine Excel-Datei (.xlsx). In Navision den Bericht '
        '„Auftragsbestand" über „Speichern unter → Excel" sichern.',
      );
    }

    final bericht = await _leseImIsolate(bytes);
    final jetzt = DateTime.now();

    await _db.transaction(() async {
      await _db.delete(_db.auftragsbestandPositionen).go();
      await _db.delete(_db.auftragsbestandArtikel).go();
      await _db.batch((b) {
        b.insertAll(_db.auftragsbestandArtikel, [
          for (final a in bericht.artikel)
            AuftragsbestandArtikelCompanion.insert(
              artikelnummer: a.nummer,
              bezeichnung: Value(a.bezeichnung),
              bezeichnung2:
                  Value(a.bezeichnung2.isEmpty ? null : a.bezeichnung2),
              lagerKg: Value(a.lagerKg ?? 0),
              auftragKg: Value(a.gesamtKg ?? 0),
              auftragMenge: Value(a.gesamtMenge),
              auftragEinheit: Value(a.gesamtEinheit),
              berichtStand: Value(bericht.stand),
              zeitraumVon: Value(bericht.von),
              zeitraumBis: Value(bericht.bis),
              importiertAm: Value(jetzt),
            ),
        ]);
        b.insertAll(_db.auftragsbestandPositionen, [
          for (final a in bericht.artikel)
            for (final p in a.positionen)
              AuftragsbestandPositionenCompanion.insert(
                artikelnummer: a.nummer,
                beleg: p.beleg,
                debitor: Value(p.debitor),
                warenausgang: p.warenausgang,
                lieferdatum: Value(p.lieferdatum),
                menge: Value(p.menge),
                einheit: Value(p.einheit),
                kg: Value(p.kg),
              ),
        ]);
      });
    });

    return AuftragsbestandErgebnis(
      artikel: bericht.artikel.length,
      positionen: bericht.anzahlPositionen,
      kunden: bericht.anzahlKunden,
      uebersprungen: bericht.uebersprungen,
      warnungen: bericht.warnungen,
      stand: bericht.stand,
      von: bericht.von,
      bis: bericht.bis,
    );
  }

  /// Das Lesen läuft auf einem eigenen Isolate: gut 3 MB XML durchzugehen
  /// würde sonst das Fenster anhalten.
  ///
  /// MUSS statisch bleiben. Eine Closure in einer Instanzmethode nähme
  /// `this` mit — und damit die Datenbankverbindung, die sich nicht
  /// zwischen Isolaten übertragen lässt („object is unsendable").
  static Future<AuftragsbestandBericht> _leseImIsolate(Uint8List bytes) {
    return Isolate.run(() => leseBericht(bytes));
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Lesen
  // ═════════════════════════════════════════════════════════════════════════

  /// Liest und prüft den Bericht — ohne Datenbank, deshalb direkt testbar.
  static AuftragsbestandBericht leseBericht(Uint8List bytes) {
    final zeilen = _leseZellen(bytes);
    return _werteAus(zeilen);
  }

  static final _reZeile =
      RegExp(r'<row\b([^>]*?)(?:/>|>(.*?)</row>)', dotAll: true);
  static final _reZelle =
      RegExp(r'<c\b([^>]*?)(?:/>|>(.*?)</c>)', dotAll: true);
  static final _reZeilenNr = RegExp(r'\br="(\d+)"');
  static final _reZellbezug = RegExp(r'\br="([A-Z]+)\d+"');
  static final _reTyp = RegExp(r'\bt="([^"]+)"');
  static final _reWert = RegExp(r'<v>(.*?)</v>', dotAll: true);
  static final _reText = RegExp(r'<t(?:\s[^>]*)?>(.*?)</t>', dotAll: true);
  static final _reGeteilt = RegExp(r'<si\b[^>]*>(.*?)</si>', dotAll: true);

  /// Zellen des ersten Tabellenblatts: Zeilennummer → (Spalte → Wert).
  ///
  /// Werte sind entweder `double` (Zahlenzellen) oder `String`. Leere
  /// Zellen fehlen in der Map.
  static Map<int, Map<String, Object>> _leseZellen(Uint8List bytes) {
    final Archive archiv;
    try {
      archiv = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw FormatException('Die Datei ließ sich nicht öffnen: $e');
    }

    String? inhalt(String name) {
      final datei = archiv.findFile(name);
      if (datei == null) return null;
      final roh = datei.content;
      if (roh is! List<int>) return null;
      final text = utf8.decode(roh, allowMalformed: true);
      // Navision stellt ein Byte-Order-Mark voran.
      return text.startsWith('﻿') ? text.substring(1) : text;
    }

    final blattPfad = _erstesBlatt(
      inhalt('xl/workbook.xml'),
      inhalt('xl/_rels/workbook.xml.rels'),
    );
    final blatt = inhalt(blattPfad) ?? inhalt('xl/worksheets/sheet1.xml');
    if (blatt == null) {
      throw const FormatException('Die Datei enthält kein Tabellenblatt.');
    }

    final geteilt = [
      for (final m in _reGeteilt.allMatches(
        inhalt('xl/sharedStrings.xml') ?? '',
      ))
        _texteAus(m.group(1)!),
    ];

    final zeilen = <int, Map<String, Object>>{};
    for (final zm in _reZeile.allMatches(blatt)) {
      final nr = int.tryParse(
        _reZeilenNr.firstMatch(zm.group(1)!)?.group(1) ?? '',
      );
      final koerper = zm.group(2);
      if (nr == null || koerper == null) continue;

      final zellen = <String, Object>{};
      for (final cm in _reZelle.allMatches(koerper)) {
        final attribute = cm.group(1)!;
        final spalte = _reZellbezug.firstMatch(attribute)?.group(1);
        if (spalte == null) continue;
        final typ = _reTyp.firstMatch(attribute)?.group(1) ?? 'n';
        final innen = cm.group(2) ?? '';
        final roh = _reWert.firstMatch(innen)?.group(1);

        final Object? wert;
        switch (typ) {
          case 'inlineStr':
            wert = _texteAus(innen);
          case 's':
            final i = int.tryParse(roh ?? '');
            wert = (i != null && i >= 0 && i < geteilt.length)
                ? geteilt[i]
                : null;
          case 'n':
            wert = roh == null
                ? null
                : (double.tryParse(roh) ?? _entschluesseln(roh));
          default:
            wert = roh == null ? null : _entschluesseln(roh);
        }
        if (wert == null) continue;
        if (wert is String && wert.trim().isEmpty) continue;
        zellen[spalte] = wert;
      }
      if (zellen.isNotEmpty) zeilen[nr] = zellen;
    }
    return zeilen;
  }

  /// Pfad des ersten Tabellenblatts im Paket.
  ///
  /// Navision schreibt absolute Verweise („/xl/worksheets/sheet1.xml"),
  /// Excel relative („worksheets/sheet1.xml"). Beides führt zum Ziel.
  static String _erstesBlatt(String? workbook, String? verweise) {
    const standard = 'xl/worksheets/sheet1.xml';
    if (workbook == null || verweise == null) return standard;
    final id = RegExp(r'<sheet\b[^>]*?\br:id="([^"]+)"')
        .firstMatch(workbook)
        ?.group(1);
    if (id == null) return standard;
    for (final m in RegExp(r'<Relationship\b([^>]*)>').allMatches(verweise)) {
      final attribute = m.group(1)!;
      if (RegExp(r'\bId="([^"]+)"').firstMatch(attribute)?.group(1) != id) {
        continue;
      }
      final ziel =
          RegExp(r'\bTarget="([^"]+)"').firstMatch(attribute)?.group(1);
      if (ziel == null) return standard;
      return ziel.startsWith('/') ? ziel.substring(1) : 'xl/$ziel';
    }
    return standard;
  }

  /// Alle `<t>`-Texte eines Elements, aneinandergehängt. Formatierte
  /// Zellen bestehen aus mehreren Stücken mit je eigenem `<t>`.
  static String _texteAus(String xml) => _reText
      .allMatches(xml)
      .map((m) => _entschluesseln(m.group(1)!))
      .join();

  static final _reEntity =
      RegExp(r'&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos);');

  /// XML-Entities auflösen — in EINEM Durchgang, sonst würde aus
  /// „&amp;lt;" fälschlich „<".
  static String _entschluesseln(String s) {
    if (!s.contains('&')) return s;
    return s.replaceAllMapped(_reEntity, (m) {
      final k = m.group(1)!;
      switch (k) {
        case 'amp':
          return '&';
        case 'lt':
          return '<';
        case 'gt':
          return '>';
        case 'quot':
          return '"';
        case 'apos':
          return "'";
      }
      final code = k.startsWith('#x')
          ? int.tryParse(k.substring(2), radix: 16)
          : int.tryParse(k.substring(1));
      return code == null ? m.group(0)! : String.fromCharCode(code);
    });
  }

  // ── Auswertung ─────────────────────────────────────────────────────────

  static final _reNummer = RegExp(r'^\d+$');
  static final _reDatum = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{2}|\d{4})$');
  static final _reLangdatum =
      RegExp(r'^(\d{1,2})\.\s*([A-Za-zÄÖÜäöü]+)\s+(\d{4})$');
  static final _reUhrzeit = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$');

  static const _monate = {
    'januar': 1,
    'februar': 2,
    'märz': 3,
    'maerz': 3,
    'april': 4,
    'mai': 5,
    'juni': 6,
    'juli': 7,
    'august': 8,
    'september': 9,
    'oktober': 10,
    'november': 11,
    'dezember': 12,
  };

  static AuftragsbestandBericht _werteAus(
    Map<int, Map<String, Object>> zeilen,
  ) {
    // ── Spaltenköpfe ────────────────────────────────────────────────────
    // Über die Beschriftung statt über feste Buchstaben: Ändert jemand das
    // Berichtslayout, verschieben sich die Spalten, die Namen bleiben.
    int? kopfZeile;
    final spalte = <String, String>{};
    for (final e in zeilen.entries) {
      final nachText = {
        for (final z in e.value.entries) _text(z.value): z.key,
      };
      if (!nachText.containsKey('Belegnr.') ||
          !nachText.containsKey('Nettogewicht')) {
        continue;
      }
      kopfZeile = e.key;
      void merke(String feld, List<String> namen) {
        for (final n in namen) {
          final s = nachText[n];
          if (s != null) {
            spalte[feld] = s;
            return;
          }
        }
      }

      merke('beleg', ['Belegnr.']);
      merke('debitor', ['Debitor']);
      merke('warenausgang', ['Warenausg.', 'Warenausgang']);
      merke('lieferdatum', ['Lieferdatum']);
      merke('menge', ['Menge']);
      merke('einheit', ['Einheit']);
      merke('netto', ['Nettogewicht']);
      break;
    }
    if (kopfZeile == null) {
      throw const FormatException(
        'Das sieht nicht nach dem Auftragsbestand aus: Die Spalten '
        '„Belegnr." und „Nettogewicht" fehlen.',
      );
    }
    for (final pflicht in const {
      'warenausgang': 'Warenausg.',
      'debitor': 'Debitor',
    }.entries) {
      if (!spalte.containsKey(pflicht.key)) {
        throw FormatException(
          'Die Spalte „${pflicht.value}" fehlt im Bericht.',
        );
      }
    }

    // ── Berichtskopf: Stand und Zeitraum ────────────────────────────────
    String? langdatum;
    String? uhrzeit;
    DateTime? von;
    DateTime? bis;
    for (final e in zeilen.entries) {
      if (e.key >= kopfZeile) break;
      final werte = _inSpaltenfolge(e.value)
          .map(_text)
          .where((t) => t.isNotEmpty)
          .toList();
      final i = werte.indexOf('bis');
      if (i > 0 && i + 1 < werte.length) {
        von ??= _datum(werte[i - 1]);
        bis ??= _datum(werte[i + 1]);
      }
      for (final w in werte) {
        if (langdatum == null && _reLangdatum.hasMatch(w)) langdatum = w;
        if (uhrzeit == null && _reUhrzeit.hasMatch(w)) uhrzeit = w;
      }
    }

    // ── Artikelblöcke ───────────────────────────────────────────────────
    final alle = <BerichtArtikel>[];
    final warnungen = <String>[];
    final fehler = <String>[];
    BerichtArtikel? aktuell;
    var erwarteBezeichnung = false;

    for (final e in zeilen.entries) {
      final nr = e.key;
      if (nr <= kopfZeile) continue;
      final z = e.value;
      final texte = _inSpaltenfolge(z).map(_text).toList();

      // Kopf („Artikelnr.: 12981") oder Summe („Artikelnr.: 12981 …
      // Gesamt …") eines Artikelblocks. Die Beschriftungen werden in der
      // ganzen Zeile gesucht, nicht in einer bestimmten Spalte.
      final iArtikel = texte.indexWhere((t) => t.startsWith('Artikelnr.'));
      if (iArtikel >= 0) {
        final nummer = texte.skip(iArtikel + 1).firstWhere(
              (t) => t.isNotEmpty && t != 'Gesamt',
              orElse: () => '',
            );
        if (texte.contains('Gesamt')) {
          final block = aktuell;
          if (block == null || block.nummer != nummer) {
            fehler.add('Zeile $nr: Summe für $nummer ohne passenden Kopf');
            continue;
          }
          block.gesamtKg = _zahl(z[spalte['netto']]);
          block.gesamtMenge = _zahl(z[spalte['menge']]);
          block.gesamtEinheit = _leerZuNull(_text(z[spalte['einheit']]));
          erwarteBezeichnung = false;
          continue;
        }
        if (nummer.isEmpty) {
          fehler.add('Zeile $nr: Artikelkopf ohne Artikelnummer');
          continue;
        }
        aktuell = BerichtArtikel(nummer);
        alle.add(aktuell);
        erwarteBezeichnung = true;
        continue;
      }

      if (texte.any((t) => t.startsWith('Nettogewicht Auf Lager'))) {
        final fuerLager = aktuell;
        if (fuerLager != null) {
          fuerLager.lagerKg = _zahl(z[spalte['netto']]) ?? 0;
        }
        erwarteBezeichnung = false;
        continue;
      }

      if (texte.contains('Zwischensumme')) {
        erwarteBezeichnung = false;
        continue;
      }

      // Auftragszeile: Belegnummer und ein Warenausgangsdatum.
      final beleg = _text(z[spalte['beleg']]);
      final warenausgang = _datum(z[spalte['warenausgang']]);
      if (beleg.isNotEmpty && warenausgang != null) {
        final zuArtikel = aktuell;
        if (zuArtikel == null) {
          fehler.add('Zeile $nr: Auftrag $beleg vor dem ersten Artikel');
          continue;
        }
        final kg = _zahl(z[spalte['netto']]);
        if (kg == null) {
          fehler.add('${zuArtikel.nummer}, $beleg: Nettogewicht fehlt');
          continue;
        }
        zuArtikel.positionen.add(
          BerichtPosition(
            beleg: beleg,
            debitor: _text(z[spalte['debitor']]),
            warenausgang: warenausgang,
            lieferdatum: _datum(z[spalte['lieferdatum']]),
            menge: _zahl(z[spalte['menge']]) ?? 0,
            einheit: _leerZuNull(_text(z[spalte['einheit']])),
            kg: kg,
          ),
        );
        erwarteBezeichnung = false;
        continue;
      }

      // Die Zeile direkt nach dem Artikelkopf trägt die Bezeichnung:
      // erster Text = Bezeichnung, der Rest = zweite Zeile.
      final offen = aktuell;
      if (erwarteBezeichnung && offen != null) {
        final teile = texte.where((t) => t.isNotEmpty).toList();
        if (teile.isNotEmpty) {
          offen.bezeichnung = teile.first;
          offen.bezeichnung2 = teile.skip(1).join(' ');
        }
        erwarteBezeichnung = false;
        continue;
      }

      final rest = texte.where((t) => t.isNotEmpty).join(' | ');
      if (rest.isNotEmpty && warnungen.length < 20) {
        warnungen.add('Zeile $nr nicht zugeordnet: $rest');
      }
    }

    // ── Prüfen ──────────────────────────────────────────────────────────
    final artikel = <BerichtArtikel>[];
    final uebersprungen = <String>[];
    for (final a in alle) {
      if (!_reNummer.hasMatch(a.nummer)) {
        uebersprungen.add(a.nummer);
        continue;
      }
      final summe = a.positionen.fold<double>(0, (s, p) => s + p.kg);
      final gesamt = a.gesamtKg;
      if (gesamt == null) {
        fehler.add('${a.nummer}: Zeile „Gesamt" fehlt');
      } else if ((summe - gesamt).abs() > 0.011) {
        fehler.add(
          '${a.nummer}: Zeilen ergeben ${_fmt(summe)} kg, '
          'der Bericht sagt ${_fmt(gesamt)} kg',
        );
      }
      if (a.lagerKg == null) {
        warnungen.add('${a.nummer}: keine Lagerzeile, Lager als 0 gerechnet');
      }
      artikel.add(a);
    }

    if (fehler.isNotEmpty) {
      final gezeigt = fehler.take(5).join('\n');
      final mehr = fehler.length > 5
          ? '\n… und ${fehler.length - 5} weitere'
          : '';
      throw FormatException(
        'Der Bericht ließ sich nicht vollständig lesen — es wurde nichts '
        'gespeichert.\n$gezeigt$mehr',
      );
    }
    if (artikel.isEmpty) {
      throw const FormatException(
        'Im Bericht stehen keine Artikel. Ist der Zeitraum in Navision '
        'vielleicht leer?',
      );
    }

    return AuftragsbestandBericht(
      artikel: artikel,
      uebersprungen: uebersprungen,
      warnungen: warnungen,
      stand: _stand(langdatum, uhrzeit),
      von: von,
      bis: bis,
    );
  }

  /// Zellen einer Zeile von links nach rechts (A, B, …, Z, AA, AB …).
  static List<Object> _inSpaltenfolge(Map<String, Object> zeile) {
    final spalten = zeile.keys.toList()
      ..sort(
        (a, b) =>
            a.length != b.length ? a.length - b.length : a.compareTo(b),
      );
    return [for (final s in spalten) zeile[s]!];
  }

  static String _text(Object? v) {
    if (v == null) return '';
    if (v is double) {
      return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    }
    return v.toString().trim();
  }

  static String? _leerZuNull(String s) => s.isEmpty ? null : s;

  /// Zahl aus einer Zahlenzelle oder aus Text („1.234,5" wie „1234.5").
  static double? _zahl(Object? v) {
    if (v is double) return v;
    var t = _text(v).replaceAll(' ', '');
    if (t.isEmpty) return null;
    if (t.contains(',') && t.contains('.')) {
      t = t.replaceAll('.', '').replaceAll(',', '.');
    } else {
      t = t.replaceAll(',', '.');
    }
    return double.tryParse(t);
  }

  /// „30.09.26", „30.09.2026" oder ein Excel-Tageswert.
  static DateTime? _datum(Object? v) {
    if (v is double) {
      // Excel zählt Tage ab dem 30.12.1899. Nur plausible Werte, damit
      // keine Menge versehentlich als Datum durchgeht.
      if (v < 30000 || v > 80000) return null;
      return DateTime(1899, 12, 30 + v.floor());
    }
    final m = _reDatum.firstMatch(_text(v));
    if (m == null) return null;
    var jahr = int.parse(m.group(3)!);
    if (jahr < 100) jahr += 2000;
    final monat = int.parse(m.group(2)!);
    final tag = int.parse(m.group(1)!);
    if (monat < 1 || monat > 12 || tag < 1 || tag > 31) return null;
    return DateTime(jahr, monat, tag);
  }

  /// „30. September 2026" + „12:09:14" aus dem Berichtskopf.
  static DateTime? _stand(String? datum, String? zeit) {
    if (datum == null) return null;
    final m = _reLangdatum.firstMatch(datum);
    if (m == null) return null;
    final monat = _monate[m.group(2)!.toLowerCase()];
    if (monat == null) return null;
    var stunde = 0;
    var minute = 0;
    var sekunde = 0;
    final z = zeit == null ? null : _reUhrzeit.firstMatch(zeit);
    if (z != null) {
      stunde = int.parse(z.group(1)!);
      minute = int.parse(z.group(2)!);
      sekunde = int.parse(z.group(3) ?? '0');
    }
    return DateTime(
      int.parse(m.group(3)!),
      monat,
      int.parse(m.group(1)!),
      stunde,
      minute,
      sekunde,
    );
  }

  static String _fmt(double v) => v.toStringAsFixed(2).replaceAll('.', ',');
}

// ═══════════════════════════════════════════════════════════════════════════
// Deckung aus dem Lager
// ═══════════════════════════════════════════════════════════════════════════

/// Aufträge eines Artikels an einem Warenausgangstag.
class TagesDeckung {
  const TagesDeckung({
    required this.tag,
    required this.positionen,
    required this.kg,
    required this.ausLagerKg,
  });

  final DateTime tag;
  final List<AuftragsPosition> positionen;

  /// Summe der Aufträge an diesem Tag.
  final double kg;

  /// Davon aus dem Lager gedeckt.
  final double ausLagerKg;

  double get fehltKg => kg - ausLagerKg > 0 ? kg - ausLagerKg : 0.0;
}

/// Wie weit das Lager eines Artikels die Aufträge trägt.
class ArtikelDeckung {
  const ArtikelDeckung({required this.lagerKg, required this.tage});

  final double lagerKg;

  /// Nach Warenausgang sortiert, der früheste zuerst.
  final List<TagesDeckung> tage;

  double get auftragKg => tage.fold<double>(0, (s, t) => s + t.kg);
  double get fehltKg => tage.fold<double>(0, (s, t) => s + t.fehltKg);

  /// Kleiner als 5 g gilt als gedeckt — Rundung, kein Bedarf.
  bool get gedeckt => fehltKg < 0.005;

  /// Erster Warenausgang, den das Lager nicht mehr voll trägt.
  DateTime? get ersterEngpass {
    for (final t in tage) {
      if (t.fehltKg >= 0.005) return t.tag;
    }
    return null;
  }
}

/// Teilt das Lager den Aufträgen in der Reihenfolge ihres Warenausgangs zu.
///
/// Der früheste Auftrag bekommt zuerst. Das ist die Reihenfolge, in der
/// die Ware auch das Haus verlässt — was am Ende fehlt, fehlt beim
/// spätesten Auftrag, und dort hat die Produktion noch am meisten Zeit.
///
/// Rechnet bewusst NUR mit dem Lager. Was in der App schon produziert
/// oder eingeplant ist, kommt in einem späteren Schritt dazu.
ArtikelDeckung berechneDeckung({
  required double lagerKg,
  required List<AuftragsPosition> positionen,
}) {
  final jeTag = <DateTime, List<AuftragsPosition>>{};
  for (final p in positionen) {
    final w = p.warenausgang;
    jeTag.putIfAbsent(DateTime(w.year, w.month, w.day), () => []).add(p);
  }
  final tage = jeTag.keys.toList()..sort();

  var rest = lagerKg > 0 ? lagerKg : 0.0;
  final ergebnis = <TagesDeckung>[];
  for (final tag in tage) {
    final liste = jeTag[tag]!;
    final kg = liste.fold<double>(0, (s, p) => s + p.kg);
    final ausLager = kg < rest ? kg : rest;
    rest -= ausLager;
    ergebnis.add(
      TagesDeckung(
        tag: tag,
        positionen: liste,
        kg: kg,
        ausLagerKg: ausLager,
      ),
    );
  }
  return ArtikelDeckung(lagerKg: lagerKg, tage: ergebnis);
}
