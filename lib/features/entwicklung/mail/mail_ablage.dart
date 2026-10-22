import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/providers/database_provider.dart';
import '../daten/datei_typen.dart';
import '../daten/dateien.dart';
import '../projekte/projekt_modell.dart';
import '../projekte/projekt_repository.dart';
import 'mail.dart';

// Mails und Dateien in ein Projekt legen — gezogen oder gewählt: Eine Mail
// kommt als E-Mail in den Verlauf (Betreff, Absender, Datum, Text, die
// Mail selbst als Datei zum Öffnen in Outlook), ihre Anhänge zu den
// Dateien des Projekts; jede andere Datei als Datei in den Verlauf. Aus
// einer Mail entsteht auf Wunsch auch ein neues Projekt — die Anfrage
// steht dann am Anfang seines Wegs.

/// Eine Datei, die abgelegt wird: Name und Inhalt.
typedef AblageDatei = ({String name, Uint8List inhalt});

/// Was beim Ablegen herauskam.
class AblageBericht {
  const AblageBericht({
    this.mails = 0,
    this.anhaenge = 0,
    this.dateien = 0,
    this.doppelt = const [],
  });

  final int mails;
  final int anhaenge;
  final int dateien;

  /// Mails, die schon im Verlauf standen — nicht noch einmal abgelegt.
  final List<String> doppelt;

  /// „1 Mail (2 Anhänge) und 1 Datei im Verlauf."
  String get text {
    final teile = [
      if (mails > 0)
        '${mails == 1 ? '1 Mail' : '$mails Mails'}'
            '${anhaenge == 0 ? '' : ' (${anhaenge == 1 ? '1 Anhang' : '$anhaenge Anhänge'} bei den Dateien)'}',
      if (dateien > 0) dateien == 1 ? '1 Datei' : '$dateien Dateien',
    ];
    return [
      if (teile.isNotEmpty) '${teile.join(' und ')} im Verlauf.',
      if (doppelt.isNotEmpty)
        'Schon im Verlauf: ${doppelt.map((t) => '„$t"').join(', ')}.',
    ].join(' ');
  }
}

/// Der Titel des Verlaufseintrags zu einer Mail.
String mailTitel(Mail m) {
  final betreff = m.betreff.trim();
  if (betreff.isNotEmpty) return betreff;
  final von = m.vonName.trim().isNotEmpty ? m.vonName.trim() : m.vonAdresse;
  return von.trim().isEmpty ? 'E-Mail' : 'E-Mail von ${von.trim()}';
}

/// Legt Mails und Dateien in Projekte.
class MailAblage {
  MailAblage(this._db, this._dateien) : _projekte = ProjektRepository(_db);

  final AppDatabase _db;
  final EntwicklungDateienDienst _dateien;
  final ProjektRepository _projekte;

  /// Legt [dateien] in den Verlauf des Projekts: Mails als E-Mail mit
  /// ihren Anhängen, alles andere als Datei.
  Future<AblageBericht> ablegen(
    String projektId,
    List<AblageDatei> dateien, {
    DateTime? jetzt,
  }) async {
    var mails = 0;
    var anhaenge = 0;
    var andere = 0;
    final doppelt = <String>[];
    for (final d in dateien) {
      final mail = alsMail(d.name, d.inhalt);
      if (mail == null) {
        await dateiAblegen(projektId, d, jetzt: jetzt);
        andere++;
        continue;
      }
      final id = await mailAblegen(projektId, mail, d, jetzt: jetzt);
      if (id == null) {
        doppelt.add(mailTitel(mail));
      } else {
        mails++;
        anhaenge += mail.anhaenge.length;
      }
    }
    return AblageBericht(
      mails: mails,
      anhaenge: anhaenge,
      dateien: andere,
      doppelt: doppelt,
    );
  }

  /// Eine Datei als Eintrag in den Verlauf. Gibt die ID des Eintrags
  /// zurück.
  Future<String> dateiAblegen(
    String projektId,
    AblageDatei datei, {
    DateTime? jetzt,
  }) async {
    final dateiId = await _dateien.speichern(
      name: datei.name,
      inhalt: datei.inhalt,
      projektId: projektId,
      mimeTyp: mimeTypAus(datei.name),
    );
    final heute = jetzt ?? DateTime.now();
    return _projekte.eintragAnlegen(
      projektId: projektId,
      art: EintragArt.datei,
      titel: datei.name,
      datum: DateTime(heute.year, heute.month, heute.day),
      status: EintragStatus.erledigt,
      dateiId: dateiId,
    );
  }

  /// Ob die Mail schon im Verlauf steht: gleicher Titel, gleicher Tag,
  /// gleicher Absender.
  Future<bool> _schonDa(
    String projektId,
    String titel,
    DateTime tag,
    String? absender,
  ) async {
    final treffer = await (_db.select(_db.entwicklungProjektEintraege)
          ..where(
            (e) =>
                e.projektId.equals(projektId) &
                e.art.equals(EintragArt.email.schluessel) &
                e.titel.equals(titel) &
                e.datum.equals(tag),
          ))
        .get();
    return treffer.any((e) => (e.benutzer ?? '') == (absender ?? ''));
  }

  /// Eine Mail in den Verlauf — die Mail als Datei, ihre Anhänge zu den
  /// Dateien des Projekts. Null, wenn sie schon dasteht.
  Future<String?> mailAblegen(
    String projektId,
    Mail mail,
    AblageDatei datei, {
    DateTime? jetzt,
  }) async {
    final wann = mail.datum ?? jetzt ?? DateTime.now();
    final tag = DateTime(wann.year, wann.month, wann.day);
    final titel = mailTitel(mail);
    final name = mail.vonName.trim();
    final absender = name.isNotEmpty
        ? name
        : (mail.vonAdresse.trim().isEmpty ? null : mail.vonAdresse.trim());
    if (await _schonDa(projektId, titel, tag, absender)) return null;

    final dateiId = await _dateien.speichern(
      name: datei.name,
      inhalt: datei.inhalt,
      projektId: projektId,
      mimeTyp: mimeTypAus(datei.name),
    );
    final anhaenge = <String>[];
    for (final a in mail.anhaenge) {
      await _dateien.speichern(
        name: a.name,
        inhalt: a.inhalt,
        projektId: projektId,
        mimeTyp: mimeTypAus(a.name) ?? a.mimeTyp,
      );
      anhaenge.add('Anhang: ${a.name} (${groesseText(a.inhalt.length)})');
    }
    final beschreibung = mailBeschreibung(mail);
    return _projekte.eintragAnlegen(
      projektId: projektId,
      art: EintragArt.email,
      titel: titel,
      datum: tag,
      benutzer: absender,
      beschreibung: beschreibung.isEmpty ? null : beschreibung,
      status: EintragStatus.erledigt,
      dateiId: dateiId,
      aenderungen: anhaenge,
    );
  }

  /// Legt aus einer Mail ein neues Projekt an — die Mail steht danach als
  /// Anfrage in seinem Verlauf. Gibt die ID des Projekts zurück.
  Future<String> projektAusMail({
    required Mail mail,
    required AblageDatei datei,
    required String name,
    String? kunde,
    String? artikelnummer,
    String? produktidee,
    DateTime? jetzt,
  }) async {
    final id = await _projekte.projektAnlegen(
      name: name,
      kunde: kunde,
      artikelnummer: artikelnummer,
      produktidee: produktidee,
      jetzt: jetzt,
    );
    await mailAblegen(id, mail, datei, jetzt: jetzt);
    return id;
  }
}

final mailAblageProvider = Provider<MailAblage>(
  (ref) => MailAblage(
    ref.watch(databaseProvider),
    ref.watch(entwicklungDateienProvider),
  ),
);
