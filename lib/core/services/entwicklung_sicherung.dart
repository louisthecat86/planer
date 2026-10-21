import 'dart:convert';
import 'dart:isolate';

import 'package:drift/drift.dart';

import '../constants/entwicklung.dart';
import '../database/database.dart';
import '../utils/krypto.dart';
import 'entwicklung_daten.dart';

// Die Produktentwicklung im Backup.
//
// Sie steht in einem eigenen Teil `data.entwicklung`:
//
//   format     2
//   passwort   der Passwort-Datensatz (Salz, Prüfwert, verpackter
//              Datenschlüssel) — so gilt auf beiden Rechnern dasselbe
//              Passwort
//   daten      Base64 der verschlüsselten Tabellen (EntwicklungDaten)
//   dateien    Base64 der Dateiinhalte je Datei — schon verschlüsselt
//
// Verschlüsselt wird mit dem Datenschlüssel dieses Rechners. Der liegt im
// Klartext in der Datenbank, damit das Auto-Backup beim Schließen ohne
// Passwort auskommt; im Backup steht er nur mit dem Passwort verpackt.
//
// Beim Einspielen gilt: Ein Backup ohne diesen Teil lässt die
// Produktentwicklung dieses Rechners stehen. Ein Backup mit ihm ersetzt
// sie. Lässt sich der Teil mit dem Schlüssel dieses Rechners öffnen, wird
// er sofort eingespielt, und das Passwort dieses Rechners bleibt — sonst
// wartet er, bis jemand mit dem Passwort des Backups entsperrt (siehe
// EntwicklungZugang).

/// Der entschlüsselte Inhalt eines Entwicklungsteils.
class EntwicklungsInhalt {
  const EntwicklungsInhalt({required this.daten, required this.dateien});

  /// Die Tabellen, aufgebaut wie bei [EntwicklungDaten.lesen].
  final Map<String, dynamic> daten;

  /// Die Dateiinhalte — weiterhin mit dem Datenschlüssel verschlüsselt.
  final Map<String, Uint8List> dateien;
}

/// Was ein Backup für die Produktentwicklung mitbringt.
enum EntwicklungsTeilArt {
  /// Kein Teil (oder einer in einem älteren Format): Der Stand dieses
  /// Rechners bleibt.
  keiner,

  /// Nur ein Passwort, keine Daten.
  nurPasswort,

  /// Daten, die sich mit dem Schlüssel dieses Rechners öffnen ließen.
  offen,

  /// Daten mit einem fremden Schlüssel — warten aufs Passwort.
  ausstehend,
}

/// Der vorbereitete Entwicklungsteil eines Backups — geprüft und, wenn
/// möglich, entschlüsselt, bevor die Datenbank angefasst wird.
class EntwicklungsTeil {
  const EntwicklungsTeil._(
    this.art, {
    this.passwort,
    this.inhalt,
    this.roh,
  });

  static const EntwicklungsTeil keiner =
      EntwicklungsTeil._(EntwicklungsTeilArt.keiner);

  final EntwicklungsTeilArt art;

  /// Der Passwort-Datensatz aus dem Backup.
  final String? passwort;

  /// Bei [EntwicklungsTeilArt.offen]: der Inhalt.
  final EntwicklungsInhalt? inhalt;

  /// Bei [EntwicklungsTeilArt.ausstehend]: der Teil, wie er im Backup
  /// steht.
  final Map<String, dynamic>? roh;
}

/// Ausfuhr und Einfuhr der Produktentwicklung im Backup.
class EntwicklungSicherung {
  EntwicklungSicherung._();

  /// Version des Teils im Backup.
  static const int format = 2;

  /// Die Einstellungen der Produktentwicklung dieses Rechners.
  static Future<List<AppSetting>> einstellungen(AppDatabase db) async =>
      (await db.select(db.appSettings).get())
          .where((s) => istEntwicklungsSchluessel(s.key))
          .toList();

  /// Der Teil fürs Backup — null, wenn auf diesem Rechner nichts
  /// eingerichtet ist.
  static Future<Map<String, Object?>?> exportieren(AppDatabase db) async {
    final werte = {for (final s in await einstellungen(db)) s.key: s.value};
    final passwort = werte[kEntwicklungPasswortSchluessel];
    if (passwort == null) return null;

    // Noch nicht entsperrt: Der Teil des zuletzt eingespielten Backups
    // geht unverändert weiter — ohne Passwort lässt er sich weder öffnen
    // noch neu verschlüsseln.
    final ausstehend = werte[kEntwicklungAusstehend];
    if (ausstehend != null) {
      final teil = _alsMap(ausstehend);
      if (teil != null) return teil;
    }

    final schluessel = _base64OderNull(werte[kEntwicklungDatenschluessel]);
    if (schluessel == null) {
      return {'format': format, 'passwort': passwort};
    }

    final klartext = Uint8List.fromList(
      utf8.encode(jsonEncode(await EntwicklungDaten.lesen(db))),
    );
    final paket = await _verschluesseleSicher(schluessel, klartext);
    final inhalte = await EntwicklungDaten.dateiInhalte(db);
    return {
      'format': format,
      'passwort': passwort,
      'daten': base64Encode(paket),
      'dateien': {
        for (final MapEntry(:key, :value) in inhalte.entries)
          key: base64Encode(value),
      },
    };
  }

  /// Prüft den Teil [roh] aus einem Backup und entschlüsselt ihn, wenn der
  /// Schlüssel dieses Rechners passt. Wirft [FormatException], wenn der
  /// Teil beschädigt ist — dann wird nichts eingespielt.
  static Future<EntwicklungsTeil> vorbereiten(
    AppDatabase db,
    Object? roh,
  ) async {
    if (roh is! Map<String, dynamic>) return EntwicklungsTeil.keiner;
    // Das erste Format (nur der Passwort-Datensatz im Klartext) zählt wie
    // kein Teil: Der Stand dieses Rechners bleibt.
    if (roh['format'] != format) return EntwicklungsTeil.keiner;

    final passwort = roh['passwort'];
    if (passwort is! String) {
      throw const FormatException(
        'Der Entwicklungsteil hat keinen Passwort-Datensatz.',
      );
    }
    final daten = roh['daten'];
    if (daten == null) {
      return EntwicklungsTeil._(
        EntwicklungsTeilArt.nurPasswort,
        passwort: passwort,
      );
    }
    if (daten is! String) {
      throw const FormatException('Die Entwicklungsdaten sind unlesbar.');
    }
    // Alles einmal dekodieren, bevor etwas angefasst wird.
    final paket = base64Decode(daten);
    final dateien = dateienAus(roh['dateien']);

    final schluessel = _base64OderNull(
      await _wert(db, kEntwicklungDatenschluessel),
    );
    if (schluessel != null) {
      try {
        final tabellen = await _oeffneImHintergrund(paket, schluessel);
        return EntwicklungsTeil._(
          EntwicklungsTeilArt.offen,
          passwort: passwort,
          inhalt: EntwicklungsInhalt(daten: tabellen, dateien: dateien),
        );
      } on KryptoFehler {
        // Ein anderer Datenschlüssel — das Passwort muss ihn auspacken.
      }
    }
    return EntwicklungsTeil._(
      EntwicklungsTeilArt.ausstehend,
      passwort: passwort,
      roh: roh,
    );
  }

  /// Spielt den vorbereiteten [teil] ein — innerhalb der Transaktion des
  /// Backups, nach den übrigen Tabellen. [bisher] sind die Einstellungen
  /// der Produktentwicklung von vor dem Einspielen; das Backup hat
  /// `app_settings` womöglich geleert.
  static Future<void> einspielen(
    AppDatabase db,
    EntwicklungsTeil teil,
    List<AppSetting> bisher,
  ) async {
    final lokal = {for (final s in bisher) s.key: s.value};
    final lokalerSchluessel = lokal[kEntwicklungDatenschluessel];
    final Map<String, String> neu;
    switch (teil.art) {
      case EntwicklungsTeilArt.keiner:
        neu = lokal;
      case EntwicklungsTeilArt.nurPasswort:
        await EntwicklungDaten.leeren(db);
        neu = {
          kEntwicklungPasswortSchluessel: teil.passwort!,
          if (lokalerSchluessel != null)
            kEntwicklungDatenschluessel: lokalerSchluessel,
        };
      case EntwicklungsTeilArt.offen:
        final inhalt = teil.inhalt!;
        await EntwicklungDaten.leeren(db);
        await EntwicklungDaten.schreiben(db, inhalt.daten, inhalt.dateien);
        // Derselbe Datenschlüssel: Das Passwort dieses Rechners bleibt —
        // ein älteres Backup bringt kein früheres (vielleicht bekannt
        // gewordenes) Passwort zurück. Beide verpacken denselben Schlüssel.
        neu = {
          kEntwicklungPasswortSchluessel:
              lokal[kEntwicklungPasswortSchluessel] ?? teil.passwort!,
          if (lokalerSchluessel != null)
            kEntwicklungDatenschluessel: lokalerSchluessel,
        };
      case EntwicklungsTeilArt.ausstehend:
        await EntwicklungDaten.leeren(db);
        // Der Schlüssel dieses Rechners passt nicht mehr zu den Daten,
        // die kommen — er fällt weg. Das Passwort packt den richtigen aus.
        neu = {
          kEntwicklungPasswortSchluessel: teil.passwort!,
          kEntwicklungAusstehend: jsonEncode(teil.roh),
        };
    }
    // Was nur diesem Rechner gehört (der DeepL-Schlüssel), bleibt.
    final alle = {
      for (final k in kEntwicklungNurLokal)
        if (lokal[k] case final wert?) k: wert,
      ...neu,
    };
    await (db.delete(db.appSettings)
          ..where((s) => s.key.like('$kEntwicklungPraefix%')))
        .go();
    if (alle.isEmpty) return;
    await db.batch(
      (b) => b.insertAllOnConflictUpdate(db.appSettings, [
        for (final MapEntry(:key, :value) in alle.entries)
          AppSettingsCompanion.insert(key: key, value: value),
      ]),
    );
  }

  /// Öffnet einen Teil im Format von [exportieren] mit [schluessel].
  /// Wirft [KryptoFehler] bei falschem Schlüssel, [FormatException] bei
  /// beschädigtem Teil.
  static EntwicklungsInhalt oeffnen(
    Map<String, dynamic> teil,
    List<int> schluessel,
  ) {
    final daten = teil['daten'];
    if (daten is! String) {
      throw const FormatException('Die Entwicklungsdaten fehlen.');
    }
    return EntwicklungsInhalt(
      daten: _tabellenAus(base64Decode(daten), schluessel),
      dateien: dateienAus(teil['dateien']),
    );
  }

  /// Die Dateiinhalte aus dem Teil: Base64 je Datei-ID.
  static Map<String, Uint8List> dateienAus(Object? roh) {
    if (roh == null) return const {};
    if (roh is! Map<String, dynamic>) {
      throw const FormatException('Die Dateien im Backup sind unlesbar.');
    }
    return {
      for (final MapEntry(:key, :value) in roh.entries)
        if (value is String) key: base64Decode(value),
    };
  }

  static Map<String, dynamic> _tabellenAus(
    List<int> paket,
    List<int> schluessel,
  ) {
    final klartext = entschluesseln(schluessel, paket, zweck: kZweckDaten);
    final json = jsonDecode(utf8.decode(klartext));
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Die Entwicklungsdaten sind unlesbar.');
    }
    return json;
  }

  /// Verschlüsselt auf einem eigenen Isolate — und im Notfall hier: lieber
  /// kurz ruckeln als ohne Entwicklungsdaten sichern.
  static Future<Uint8List> _verschluesseleSicher(
    Uint8List schluessel,
    Uint8List klartext,
  ) async {
    try {
      return await _verschluesseleImHintergrund(schluessel, klartext);
    } catch (_) {
      return verschluesseln(schluessel, klartext, zweck: kZweckDaten);
    }
  }

  // Statisch und ohne `async`: Die Funktionen für das Isolate nehmen nur
  // ihre Argumente mit, nichts aus einem umgebenden Zustand.

  static Future<Uint8List> _verschluesseleImHintergrund(
    Uint8List schluessel,
    Uint8List klartext,
  ) =>
      Isolate.run(
        () => verschluesseln(schluessel, klartext, zweck: kZweckDaten),
      );

  static Future<Map<String, dynamic>> _oeffneImHintergrund(
    Uint8List paket,
    Uint8List schluessel,
  ) =>
      Isolate.run(() => _tabellenAus(paket, schluessel));

  static Future<String?> _wert(AppDatabase db, String schluessel) async {
    final zeile = await (db.select(db.appSettings)
          ..where((s) => s.key.equals(schluessel)))
        .getSingleOrNull();
    return zeile?.value;
  }

  static Uint8List? _base64OderNull(String? text) {
    if (text == null) return null;
    try {
      return base64Decode(text);
    } on FormatException {
      return null;
    }
  }

  static Map<String, dynamic>? _alsMap(String text) {
    try {
      final json = jsonDecode(text);
      return json is Map<String, dynamic> ? json : null;
    } on FormatException {
      return null;
    }
  }
}
