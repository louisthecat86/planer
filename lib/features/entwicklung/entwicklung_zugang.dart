import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/entwicklung.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/entwicklung_daten.dart';
import '../../core/services/entwicklung_sicherung.dart';
import '../../core/utils/krypto.dart';

// Der Zugang zur Produktentwicklung: ein eigenes Passwort.
//
// Gespeichert wird nie das Passwort, sondern ein Prüfwert: aus Passwort
// und Zufallssalz mit PBKDF2 abgeleitet. Daraus lässt sich das Passwort
// nicht zurückrechnen — wer die Datenbank hat, muss es raten, und jeder
// Versuch kostet die volle Ableitung.
//
// Aus derselben Ableitung entsteht ein zweiter Wert, der den
// Datenschlüssel verpackt. Mit dem Datenschlüssel ist die Produktent-
// wicklung im Backup verschlüsselt (EntwicklungSicherung). Er selbst liegt
// auf diesem Rechner im Klartext — damit das Auto-Backup beim Schließen
// ohne Passwort auskommt — und reist im Backup nur verpackt. Auf einem
// zweiten Rechner packt ihn das Passwort beim ersten Entsperren aus.
//
// Die Sperre schützt die Oberfläche. Die Datenbankdatei selbst ist nicht
// verschlüsselt — wer sie in die Hände bekommt, kann sie lesen.

/// Mindestlänge eines Passworts.
const int kPasswortMindestlaenge = 8;

/// So oft rechnet PBKDF2 beim Festlegen. Das macht massenhaftes Raten
/// teuer, kostet beim Öffnen aber nur einen Augenblick. Die Zahl steht im
/// gespeicherten Datensatz: Ein späterer, höherer Wert gilt für neu
/// festgelegte Passwörter, alte bleiben prüfbar.
const int kPasswortIterationen = 200000;

/// Länge des Zufallssalzes in Bytes.
const int _kSalzLaenge = 16;

/// Wofür ein abgeleiteter Wert steht. Aus derselben Ableitung entstehen
/// Prüfwert und Verpackung — mit verschiedenem Zweck, damit der
/// gespeicherte Prüfwert nichts über die Verpackung verrät.
const String _kZweckPruefwert = 'produktions-planer/entwicklung/pruefwert';
const String _kZweckVerpackung = 'produktions-planer/entwicklung/verpackung';

/// Warum [passwort] nicht taugt — null, wenn es taugt.
String? passwortFehler(String passwort) {
  if (passwort.trim().isEmpty) return 'Bitte ein Passwort eingeben.';
  if (passwort.length < kPasswortMindestlaenge) {
    return 'Mindestens $kPasswortMindestlaenge Zeichen.';
  }
  return null;
}

/// Die Grundableitung eines Passworts: PBKDF2 über Passwort und [salz].
Uint8List grundwertFuer(String passwort, List<int> salz, int iterationen) =>
    pbkdf2Sha256(utf8.encode(passwort), salz, iterationen: iterationen);

/// Der Prüfwert zu einer Grundableitung.
Uint8List pruefwertAus(List<int> grund) =>
    hmacSha256(grund, utf8.encode(_kZweckPruefwert));

/// Der Schlüssel, der den Datenschlüssel verpackt.
Uint8List verpackungAus(List<int> grund) =>
    hmacSha256(grund, utf8.encode(_kZweckVerpackung));

/// Der Prüfwert eines Passworts.
Uint8List pruefwertFuer(String passwort, List<int> salz, int iterationen) =>
    pruefwertAus(grundwertFuer(passwort, salz, iterationen));

/// Was zum Prüfen eines Passworts gespeichert wird — und der damit
/// verpackte Datenschlüssel.
class PasswortDatensatz {
  const PasswortDatensatz({
    required this.salz,
    required this.iterationen,
    required this.pruefwert,
    this.verpackterSchluessel,
  });

  final Uint8List salz;
  final int iterationen;
  final Uint8List pruefwert;

  /// Der Datenschlüssel, verschlüsselt mit [verpackungAus]. Fehlt bei
  /// Passwörtern aus dem ersten App-Stand; das nächste Entsperren trägt
  /// ihn nach.
  final Uint8List? verpackterSchluessel;

  PasswortDatensatz mitSchluessel(Uint8List verpackt) => PasswortDatensatz(
        salz: salz,
        iterationen: iterationen,
        pruefwert: pruefwert,
        verpackterSchluessel: verpackt,
      );

  Map<String, Object> toJson() {
    final verpackt = verpackterSchluessel;
    return {
      'verfahren': 'PBKDF2-HMAC-SHA256',
      'iterationen': iterationen,
      'salz': base64Encode(salz),
      'pruefwert': base64Encode(pruefwert),
      if (verpackt != null) 'schluessel': base64Encode(verpackt),
    };
  }

  /// Liest einen gespeicherten Datensatz — null, wenn er unlesbar ist.
  static PasswortDatensatz? ausJson(String text) {
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, dynamic>) return null;
      final iterationen = json['iterationen'];
      final salz = json['salz'];
      final pruefwert = json['pruefwert'];
      final schluessel = json['schluessel'];
      if (iterationen is! int || iterationen < 1) return null;
      if (salz is! String || pruefwert is! String) return null;
      return PasswortDatensatz(
        salz: base64Decode(salz),
        iterationen: iterationen,
        pruefwert: base64Decode(pruefwert),
        verpackterSchluessel:
            schluessel is String ? base64Decode(schluessel) : null,
      );
    } on FormatException {
      return null;
    }
  }
}

/// Wo der Zugang liest und schreibt. In der App die Datenbank; Tests
/// geben einen Speicher im Arbeitsspeicher vor.
abstract class EntwicklungsSpeicher {
  /// Eine Einstellung der Produktentwicklung.
  Future<String?> lesen(String schluessel);

  /// null entfernt die Einstellung.
  Future<void> schreiben(String schluessel, String? wert);

  /// Ersetzt alle Daten der Produktentwicklung durch [inhalt].
  Future<void> datenErsetzen(EntwicklungsInhalt inhalt);

  /// Löscht alle Daten der Produktentwicklung.
  Future<void> datenLoeschen();
}

/// Der Speicher der App: `app_settings` und die Entwicklungstabellen.
class DbEntwicklungsSpeicher implements EntwicklungsSpeicher {
  DbEntwicklungsSpeicher(this._db);

  final AppDatabase _db;

  @override
  Future<String?> lesen(String schluessel) async {
    final zeile = await (_db.select(_db.appSettings)
          ..where((s) => s.key.equals(schluessel))
          ..limit(1))
        .getSingleOrNull();
    return zeile?.value;
  }

  @override
  Future<void> schreiben(String schluessel, String? wert) async {
    if (wert == null) {
      await (_db.delete(_db.appSettings)
            ..where((s) => s.key.equals(schluessel)))
          .go();
      return;
    }
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: schluessel,
            value: wert,
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  @override
  Future<void> datenErsetzen(EntwicklungsInhalt inhalt) =>
      _db.transaction(() async {
        await EntwicklungDaten.leeren(_db);
        await EntwicklungDaten.schreiben(_db, inhalt.daten, inhalt.dateien);
      });

  @override
  Future<void> datenLoeschen() =>
      _db.transaction(() => EntwicklungDaten.leeren(_db));
}

/// Passwort festlegen, prüfen, ändern und zurücksetzen — und beim Öffnen
/// den Datenschlüssel bereitstellen.
class EntwicklungZugang {
  EntwicklungZugang(
    this._speicher, {
    this.iterationen = kPasswortIterationen,
    this.imHintergrund = true,
  });

  final EntwicklungsSpeicher _speicher;

  /// Iterationen für neu festgelegte Passwörter.
  final int iterationen;

  /// Die Ableitung auf einem eigenen Isolate rechnen, damit das Fenster
  /// nicht stockt. Tests rechnen direkt.
  final bool imHintergrund;

  Future<PasswortDatensatz?> _datensatz() async {
    final text = await _speicher.lesen(kEntwicklungPasswortSchluessel);
    return text == null ? null : PasswortDatensatz.ausJson(text);
  }

  Future<void> _schreibeDatensatz(PasswortDatensatz datensatz) =>
      _speicher.schreiben(
        kEntwicklungPasswortSchluessel,
        jsonEncode(datensatz.toJson()),
      );

  Future<Uint8List?> _lokalerSchluessel() async {
    final text = await _speicher.lesen(kEntwicklungDatenschluessel);
    if (text == null) return null;
    try {
      final schluessel = base64Decode(text);
      return schluessel.length == kSchluesselLaenge ? schluessel : null;
    } on FormatException {
      return null;
    }
  }

  /// Ob ein Passwort festgelegt ist.
  Future<bool> passwortGesetzt() async => await _datensatz() != null;

  /// Ob ein eingespieltes Backup von einem anderen Rechner auf das
  /// Passwort wartet.
  Future<bool> backupWartet() async =>
      await _speicher.lesen(kEntwicklungAusstehend) != null;

  /// Ob [passwort] stimmt. false auch, wenn noch keins festgelegt ist.
  Future<bool> pruefen(String passwort) async {
    final datensatz = await _datensatz();
    if (datensatz == null) return false;
    final grund = await _ableiten(passwort, datensatz);
    return gleicheBytes(pruefwertAus(grund), datensatz.pruefwert);
  }

  /// Öffnet die Produktentwicklung mit [passwort]: prüft es, stellt den
  /// Datenschlüssel bereit und spielt einen wartenden Backup-Teil ein.
  /// false, wenn das Passwort nicht stimmt.
  Future<bool> oeffnen(String passwort) async {
    final datensatz = await _datensatz();
    if (datensatz == null) return false;
    final grund = await _ableiten(passwort, datensatz);
    if (!gleicheBytes(pruefwertAus(grund), datensatz.pruefwert)) return false;
    await _schluesselBereitstellen(datensatz, verpackungAus(grund));
    return true;
  }

  /// Legt das erste Passwort fest und richtet den Datenschlüssel ein.
  /// Ändern geht nur mit dem alten ([aendern]).
  Future<void> festlegen(String passwort) async {
    final fehler = passwortFehler(passwort);
    if (fehler != null) throw ArgumentError(fehler);
    if (await passwortGesetzt()) {
      throw StateError('Es ist bereits ein Passwort festgelegt.');
    }
    final vorhanden = await _lokalerSchluessel();
    final schluessel = vorhanden ?? zufallsBytes(kSchluesselLaenge);
    await _speichere(passwort, schluessel);
    if (vorhanden == null) {
      await _speicher.schreiben(
        kEntwicklungDatenschluessel,
        base64Encode(schluessel),
      );
    }
  }

  /// Ersetzt das Passwort — nur mit dem richtigen [alt]. false, wenn das
  /// alte nicht stimmt; dann bleibt alles, wie es war. Der Datenschlüssel
  /// bleibt derselbe, er wird nur neu verpackt.
  Future<bool> aendern(String alt, String neu) async {
    final fehler = passwortFehler(neu);
    if (fehler != null) throw ArgumentError(fehler);
    final datensatz = await _datensatz();
    if (datensatz == null) return false;
    final grund = await _ableiten(alt, datensatz);
    if (!gleicheBytes(pruefwertAus(grund), datensatz.pruefwert)) return false;
    final schluessel =
        await _schluesselBereitstellen(datensatz, verpackungAus(grund));
    await _speichere(neu, schluessel);
    return true;
  }

  /// Entfernt Passwort, Schlüssel und alle Daten der Produktentwicklung
  /// auf diesem Rechner. Wiederherstellen lässt sich nur aus einem Backup
  /// — und das nur mit dem alten Passwort.
  Future<void> zuruecksetzen() async {
    await _speicher.datenLoeschen();
    await _speicher.schreiben(kEntwicklungAusstehend, null);
    await _speicher.schreiben(kEntwicklungDatenschluessel, null);
    await _speicher.schreiben(kEntwicklungPasswortSchluessel, null);
  }

  /// Sorgt dafür, dass dieser Rechner den Datenschlüssel hat und der
  /// Datensatz ihn verpackt enthält; spielt einen wartenden Backup-Teil
  /// ein. Gibt den Datenschlüssel zurück.
  Future<Uint8List> _schluesselBereitstellen(
    PasswortDatensatz datensatz,
    Uint8List verpackung,
  ) async {
    final verpackt = datensatz.verpackterSchluessel;
    final ausDatensatz = verpackt == null
        ? null
        : entschluesseln(verpackung, verpackt, zweck: kZweckSchluessel);

    // Ein Backup von einem anderen Rechner wartet: Sein Datensatz trägt
    // den Schlüssel, der es öffnet.
    final ausstehend = await _speicher.lesen(kEntwicklungAusstehend);
    if (ausstehend != null) {
      if (ausDatensatz == null) {
        throw const KryptoFehler(
          'Das eingespielte Backup bringt keinen Schlüssel für seine '
          'Entwicklungsdaten mit.',
        );
      }
      final teil = jsonDecode(ausstehend);
      if (teil is! Map<String, dynamic>) {
        throw const FormatException('Der wartende Backup-Teil ist unlesbar.');
      }
      final inhalt = await _oeffne(teil, ausDatensatz);
      await _speicher.datenErsetzen(inhalt);
      await _speicher.schreiben(
        kEntwicklungDatenschluessel,
        base64Encode(ausDatensatz),
      );
      await _speicher.schreiben(kEntwicklungAusstehend, null);
      return ausDatensatz;
    }

    final lokal = await _lokalerSchluessel();
    if (lokal != null) {
      // Der Schlüssel dieses Rechners gilt — mit ihm sind die Daten hier
      // verschlüsselt. Fehlt er im Datensatz oder weicht er ab, wird er
      // hineingepackt.
      if (ausDatensatz == null || !gleicheBytes(lokal, ausDatensatz)) {
        await _schreibeDatensatz(
          datensatz.mitSchluessel(
            verschluesseln(verpackung, lokal, zweck: kZweckSchluessel),
          ),
        );
      }
      return lokal;
    }

    final schluessel = ausDatensatz ?? zufallsBytes(kSchluesselLaenge);
    if (ausDatensatz == null) {
      await _schreibeDatensatz(
        datensatz.mitSchluessel(
          verschluesseln(verpackung, schluessel, zweck: kZweckSchluessel),
        ),
      );
    }
    await _speicher.schreiben(
      kEntwicklungDatenschluessel,
      base64Encode(schluessel),
    );
    return schluessel;
  }

  /// Neuer Datensatz für [passwort] mit frischem Salz; [schluessel] wird
  /// damit verpackt.
  Future<void> _speichere(String passwort, Uint8List schluessel) async {
    final salz = zufallsBytes(_kSalzLaenge);
    final grund = await _rechne(passwort, salz, iterationen);
    await _schreibeDatensatz(
      PasswortDatensatz(
        salz: salz,
        iterationen: iterationen,
        pruefwert: pruefwertAus(grund),
        verpackterSchluessel: verschluesseln(
          verpackungAus(grund),
          schluessel,
          zweck: kZweckSchluessel,
        ),
      ),
    );
  }

  Future<Uint8List> _ableiten(String passwort, PasswortDatensatz datensatz) =>
      _rechne(passwort, datensatz.salz, datensatz.iterationen);

  Future<Uint8List> _rechne(String passwort, Uint8List salz, int anzahl) {
    if (!imHintergrund) {
      return Future.value(grundwertFuer(passwort, salz, anzahl));
    }
    return _ableitenImHintergrund(passwort, salz, anzahl);
  }

  Future<EntwicklungsInhalt> _oeffne(
    Map<String, dynamic> teil,
    Uint8List schluessel,
  ) {
    if (!imHintergrund) {
      return Future.value(EntwicklungSicherung.oeffnen(teil, schluessel));
    }
    return _oeffneImHintergrund(teil, schluessel);
  }

  // Statisch und ohne `async`: Die Funktion für das Isolate darf nichts
  // mitnehmen, was sich nicht verschicken lässt — weder den Speicher noch
  // den Zustand einer laufenden async-Methode.

  static Future<Uint8List> _ableitenImHintergrund(
    String passwort,
    Uint8List salz,
    int anzahl,
  ) =>
      Isolate.run(() => grundwertFuer(passwort, salz, anzahl));

  static Future<EntwicklungsInhalt> _oeffneImHintergrund(
    Map<String, dynamic> teil,
    Uint8List schluessel,
  ) =>
      Isolate.run(() => EntwicklungSicherung.oeffnen(teil, schluessel));
}

/// Der Zugang der App.
final entwicklungZugangProvider = Provider<EntwicklungZugang>(
  (ref) => EntwicklungZugang(
    DbEntwicklungsSpeicher(ref.watch(databaseProvider)),
  ),
);

/// Ob ein Passwort festgelegt ist.
final entwicklungPasswortGesetztProvider = FutureProvider<bool>(
  (ref) => ref.watch(entwicklungZugangProvider).passwortGesetzt(),
);

/// Ob ein Backup von einem anderen Rechner auf das Passwort wartet.
final entwicklungBackupWartetProvider = FutureProvider<bool>(
  (ref) => ref.watch(entwicklungZugangProvider).backupWartet(),
);

/// Ob die Produktentwicklung gerade offen ist. Nur im Speicher: Nach dem
/// Start der App ist sie immer gesperrt.
final entwicklungEntsperrtProvider = StateProvider<bool>((ref) => false);

/// Nach dem Einspielen eines Backups: neu sperren — es kann ein anderes
/// Passwort und andere Daten mitgebracht haben.
void entwicklungNachWiederherstellen(WidgetRef ref) {
  ref.read(entwicklungEntsperrtProvider.notifier).state = false;
  ref.invalidate(entwicklungPasswortGesetztProvider);
  ref.invalidate(entwicklungBackupWartetProvider);
}
