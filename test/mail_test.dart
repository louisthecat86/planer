import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:produktion_planer/core/database/database.dart';
import 'package:produktion_planer/core/utils/ablage_dateien.dart';
import 'package:produktion_planer/features/entwicklung/daten/dateien.dart';
import 'package:produktion_planer/features/entwicklung/entwicklung_zugang.dart';
import 'package:produktion_planer/features/entwicklung/mail/eml_lesen.dart';
import 'package:produktion_planer/features/entwicklung/mail/mail.dart';
import 'package:produktion_planer/features/entwicklung/mail/mail_ablage.dart';
import 'package:produktion_planer/features/entwicklung/mail/msg_lesen.dart';
import 'package:produktion_planer/features/entwicklung/projekte/entwicklungsstrang.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_modell.dart';
import 'package:produktion_planer/features/entwicklung/projekte/projekt_repository.dart';

import 'helpers/test_db.dart';
import 'helpers/verbunddatei.dart';

/// Tests für Mails im Projekt: Internet-Mails (.eml) und Outlook-Mails
/// (.msg) lesen — Kopf, Text, Anhänge, Zeichensätze —, eine Mail in den
/// Verlauf legen, ein Projekt aus einer Mail, das Aufräumen nach dem
/// Ablegen. Alle Mails sind erfunden; die .msg entstehen hier im Test.
void main() {
  group('Internet-Mail (.eml)', () {
    test('Kopf, Text, Anhänge — mehrteilig und kodiert', () {
      final m = emlLesen(Uint8List.fromList(utf8.encode(_anfrage)));
      expect(m.betreff, 'AW: Anfrage Frikadelle für den Grill');
      expect(m.vonName, 'Müller, Hans');
      expect(m.vonAdresse, 'hans.mueller@muster-fleisch.de');
      expect(m.von, 'Müller, Hans <hans.mueller@muster-fleisch.de>');
      expect(m.an, 'Einkauf; Erika Beispiel');
      expect(m.cc, 'qs@beispiel.de');
      expect(m.datum!.toUtc(), DateTime.utc(2026, 10, 6, 12, 5));
      // Der reine Text hat Vorrang vor dem HTML; der weiche Umbruch ist
      // weg.
      expect(
        m.text,
        startsWith(
          'Guten Tag,\nwir suchen eine Frikadelle für den Grill, ca. 80 g, '
          'gut gewürzt.\n\nViele Grüße\nHans Müller',
        ),
      );
      expect(m.text, isNot(contains('HTML-Fassung')));
      // Das Logo aus der Signatur ist kein Anhang; der Name nach RFC 2231.
      expect(m.anhaenge, hasLength(1));
      final pdf = m.anhaenge.single;
      expect(pdf.name, 'Spezifikation Grüße.pdf');
      expect(pdf.mimeTyp, 'application/pdf');
      expect(latin1.decode(pdf.inhalt), '%PDF-1.4\n');
    });

    test('nur HTML, Windows-1252 ohne Angabe, Base64-Text', () {
      final html = Uint8List.fromList([
        ...latin1.encode(
          'Subject: Nur HTML\r\n'
          'From: info@gmail.com\r\n'
          'Content-Type: text/html\r\n'
          '\r\n'
          '<html><head><style>p{color:red}</style></head><body>'
          '<p>Erste&nbsp;Zeile</p><p>Zweite &amp; letzte<br>Zeile mit '
          'Grüßen</p><ul><li>Punkt</li></ul></body></html>',
        ),
      ]);
      final m = emlLesen(html);
      expect(m.betreff, 'Nur HTML');
      expect(m.text, 'Erste Zeile\nZweite & letzte\nZeile mit Grüßen\n• Punkt');
      expect(m.vonName, isEmpty);
      expect(m.vonAdresse, 'info@gmail.com');

      final b64 = emlLesen(
        Uint8List.fromList(
          utf8.encode(
            'Subject: =?iso-8859-15?B?pCB1bmQg9g==?=\r\n'
            'Content-Type: text/plain; charset="utf-8"\r\n'
            'Content-Transfer-Encoding: base64\r\n'
            '\r\n'
            '${base64.encode(utf8.encode('Grüße — mit Gedankenstrich'))}\r\n',
          ),
        ),
      );
      // ISO-8859-15 hat das Euro-Zeichen.
      expect(b64.betreff, '€ und ö');
      expect(b64.text, 'Grüße — mit Gedankenstrich');
    });

    test('keine Mail: ein verständlicher Fehler', () {
      expect(
        () => emlLesen(Uint8List.fromList(utf8.encode('Hallo Welt'))),
        throwsFormatException,
      );
      expect(alsMail('notiz.txt', Uint8List(0)), isNull);
      expect(alsMail('kaputt.eml', Uint8List.fromList([1, 2, 3])), isNull);
    });

    test('kodierte Wörter, Adressen, Datum', () {
      // Ein Zeichen, auf zwei kodierte Wörter verteilt, bleibt ganz.
      expect(
        kopfDekodieren('=?UTF-8?Q?Gr=C3?= =?UTF-8?Q?=BC=C3=9Fe?= aus Franken'),
        'Grüße aus Franken',
      );
      expect(kopfDekodieren('=?UTF-8?B?w7w=?=='), 'ü=');
      expect(
        adresseLesen('"Beispiel, Erika" <erika@beispiel.de>'),
        (name: 'Beispiel, Erika', adresse: 'erika@beispiel.de'),
      );
      expect(
        adresseLesen('erika@beispiel.de (Erika B.)'),
        (name: 'Erika B.', adresse: 'erika@beispiel.de'),
      );
      expect(
        adressenText('a@x.de, "B, C" <b@x.de>; D <d@x.de>'),
        'a@x.de; B, C; D',
      );
      expect(
        internetDatum('Mon, 5 Oct 2026 08:00:00 GMT')!.toUtc(),
        DateTime.utc(2026, 10, 5, 8),
      );
      expect(
        internetDatum('5 Okt 26 08:00 MEZ')!.toUtc(),
        DateTime.utc(2026, 10, 5, 7),
      );
      expect(internetDatum('irgendwann'), isNull);
    });

    test('HTML zu Text: Entitäten, Listen, Tabellen', () {
      expect(
        htmlZuText(
          '<div>A&#252;&#x00DF;&euro;</div><table><tr><td>Fett</td>'
          '<td>13 g</td></tr></table><!-- weg --><script>x()</script>',
        ),
        'Aüß€\nFett  13 g',
      );
    });
  });

  group('Outlook-Mail (.msg)', () {
    test('Kopf, Text in der Codepage, Anhänge — versteckte nicht', () {
      final m = mailLesen(_msg());
      expect(m.betreff, 'Anfrage Bratwurst fein');
      expect(m.vonName, 'Erika Beispiel');
      // Die Exchange-Adresse taugt nicht — die SMTP-Adresse schon.
      expect(m.vonAdresse, 'erika.beispiel@beispiel-wurst.de');
      expect(m.an, 'Einkauf; Qualität');
      expect(m.datum!.toUtc(), DateTime.utc(2026, 10, 6, 12, 5));
      expect(m.text, 'Grüße aus Musterstadt\nBitte um ein Muster.');
      expect([for (final a in m.anhaenge) a.name], [
        'Rezeptur Bratwurst.xlsx',
        'NOTIZ.TXT',
      ]);
      final gross = m.anhaenge.first;
      // Über 4096 Bytes: nicht im Ministrom — Byte für Byte.
      expect(gross.inhalt, hasLength(10000));
      expect(gross.inhalt[9999], 9999 % 251);
      expect(
        gross.mimeTyp,
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      expect(utf8.decode(m.anhaenge.last.inhalt), 'kurz');
    });

    test('Verbunddatei: Ordner und Ströme', () {
      final datei = Verbunddatei.lesen(
        verbunddatei([
          CfbKnoten.strom('Klein', [1, 2, 3]),
          CfbKnoten.ordner('Ordner', [
            CfbKnoten.strom('Groß', List.filled(5000, 7)),
            CfbKnoten.strom('Leer', const []),
          ]),
        ]),
      );
      final wurzel = datei.kinder(0);
      expect(wurzel.keys, containsAll(['KLEIN', 'ORDNER']));
      expect(datei.stromNamens(wurzel, 'klein'), [1, 2, 3]);
      final ordner = datei.kinder(wurzel['ORDNER']!);
      expect(datei.stromNamens(ordner, 'Groß')!.length, 5000);
      expect(datei.stromNamens(ordner, 'Leer'), isEmpty);
      expect(datei.stromNamens(ordner, 'Fehlt'), isNull);
    });

    test('keine Outlook-Mail: ein verständlicher Fehler', () {
      // Eine Verbunddatei ohne Mail-Eigenschaften.
      expect(
        () => msgLesen(verbunddatei([CfbKnoten.strom('Anderes', [1])])),
        throwsFormatException,
      );
      // Der Anfang stimmt, der Rest nicht.
      expect(
        () => msgLesen(
          Uint8List.fromList([
            0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, //
            ...List.filled(600, 0),
          ]),
        ),
        throwsFormatException,
      );
    });
  });

  group('Für das Projekt', () {
    test('Betreff, Kunde, Text ohne Zitat, Vorschlag, Beschreibung', () {
      expect(betreffOhneVorsatz('AW: WG: Re: Anfrage'), 'Anfrage');
      expect(betreffOhneVorsatz('Fwd [2]: Muster'), 'Muster');
      expect(betreffOhneVorsatz('Antwort zur Anfrage'), 'Antwort zur Anfrage');
      expect(
        kundeAusAbsender(
          const Mail(vonAdresse: 'einkauf@mail.muster-fleisch.co.uk'),
        ),
        'Muster-Fleisch',
      );
      expect(
        kundeAusAbsender(
          const Mail(vonName: 'Hans Müller', vonAdresse: 'hans@gmx.de'),
        ),
        'Hans Müller',
      );
      expect(
        ohneZitat('Bitte um ein Angebot.\n> alt\n\nAm 1.10. schrieb Max:\nalt'),
        'Bitte um ein Angebot.',
      );
      final m = emlLesen(Uint8List.fromList(utf8.encode(_anfrage)));
      final v = projektVorschlag(m);
      expect(v.name, 'Anfrage Frikadelle für den Grill');
      expect(v.kunde, 'Muster-Fleisch');
      expect(v.idee, endsWith('Hans Müller'));
      expect(v.idee, isNot(contains('Ursprüngliche')));
      expect(
        mailBeschreibung(m),
        startsWith('An: Einkauf; Erika Beispiel\nCc: qs@beispiel.de\n\nGuten '),
      );
      expect(mailBeschreibung(const Mail(text: 'abcdef'), maxZeichen: 3), 'abc …');
      expect(mailTitel(const Mail(vonName: 'Erika')), 'E-Mail von Erika');
      expect(mailTitel(const Mail()), 'E-Mail');
    });

    test('der Bericht nach dem Ablegen', () {
      expect(
        const AblageBericht(mails: 1, anhaenge: 2, dateien: 1).text,
        '1 Mail (2 Anhänge bei den Dateien) und 1 Datei im Verlauf.',
      );
      expect(
        const AblageBericht(dateien: 3, doppelt: ['Muster']).text,
        '3 Dateien im Verlauf. Schon im Verlauf: „Muster".',
      );
    });
  });

  group('Mit der Datenbank', () {
    late AppDatabase db;
    late ProjektRepository projekte;
    late EntwicklungDateienDienst dateien;
    late MailAblage ablage;

    setUp(() async {
      db = testDatenbank();
      projekte = ProjektRepository(db);
      dateien = EntwicklungDateienDienst(db);
      ablage = MailAblage(db, dateien);
      // Der Datenschlüssel entsteht mit dem Passwort.
      await EntwicklungZugang(
        DbEntwicklungsSpeicher(db),
        iterationen: 1000,
        imHintergrund: false,
      ).festlegen('geheim123');
    });
    tearDown(() => db.close());

    test('ein Projekt aus einer Mail: die Anfrage steht am Anfang', () async {
      final roh = Uint8List.fromList(utf8.encode(_anfrage));
      final mail = emlLesen(roh);
      final v = projektVorschlag(mail);
      final id = await ablage.projektAusMail(
        mail: mail,
        datei: (name: 'Anfrage.eml', inhalt: roh),
        name: v.name,
        kunde: v.kunde,
        produktidee: v.idee,
        jetzt: DateTime(2026, 10, 7, 9),
      );
      final p = (await projekte.projekt(id))!;
      expect(p.name, 'Anfrage Frikadelle für den Grill');
      expect(p.kunde, 'Muster-Fleisch');
      expect(p.produktidee, startsWith('Guten Tag,'));

      final verlauf = await projekte.eintraegeBeobachten(id).first;
      final e = verlauf.singleWhere(
        (e) => e.art == EintragArt.email.schluessel,
      );
      expect(e.titel, 'AW: Anfrage Frikadelle für den Grill');
      expect(e.datum, DateTime(2026, 10, 6));
      expect(e.benutzer, 'Müller, Hans');
      expect(e.status, EintragStatus.erhalten.schluessel);
      expect(e.beschreibung, contains('gut gewürzt'));
      expect(texteAus(e.aenderungen), ['Anhang: Spezifikation Grüße.pdf (9 B)']);
      // Die Mail selbst zum Öffnen, der Anhang bei den Dateien.
      final gespeichert = await projekte.dateienBeobachten(id).first;
      expect(
        [for (final d in gespeichert) d.name]..sort(),
        ['Anfrage.eml', 'Spezifikation Grüße.pdf'],
      );
      expect(await dateien.lesen(e.dateiId!), roh);
      // Auf dem Entwicklungsweg: die Anfrage vor dem ersten Stand.
      final weg = entwicklungsweg(verlauf);
      expect(
        [for (final x in (weg.first as WegAnfang).eintraege) x.id],
        contains(e.id),
      );
    });

    test('Mails und Dateien in den Verlauf, keine doppelt', () async {
      final id = await projekte.projektAnlegen(
        name: 'Bratwurst fein',
        jetzt: DateTime(2026, 10, 1, 8),
      );
      final msg = (name: 'Anfrage Bratwurst fein.msg', inhalt: _msg());
      final notiz = (
        name: 'Notiz.txt',
        inhalt: Uint8List.fromList(utf8.encode('Muster an Kunde')),
      );
      var bericht = await ablage.ablegen(id, [msg, notiz]);
      expect(bericht.mails, 1);
      expect(bericht.anhaenge, 2);
      expect(bericht.dateien, 1);
      expect(
        bericht.text,
        '1 Mail (2 Anhänge bei den Dateien) und 1 Datei im Verlauf.',
      );

      // Dieselbe Mail noch einmal: nicht doppelt.
      bericht = await ablage.ablegen(id, [msg]);
      expect(bericht.mails, 0);
      expect(bericht.doppelt, ['Anfrage Bratwurst fein']);

      final verlauf = await projekte.eintraegeBeobachten(id).first;
      final mails =
          verlauf.where((e) => e.art == EintragArt.email.schluessel).toList();
      expect(mails, hasLength(1));
      expect(mails.single.benutzer, 'Erika Beispiel');
      expect(mails.single.beschreibung, startsWith('An: Einkauf; Qualität'));
      final datei = verlauf.singleWhere(
        (e) => e.art == EintragArt.datei.schluessel,
      );
      expect(datei.titel, 'Notiz.txt');
      expect(
        (await projekte.dateienBeobachten(id).first).length,
        // Mail, zwei Anhänge, Notiz.
        4,
      );
    });
  });

  group('Abgelegte Dateien', () {
    test('lesen und nur die eigenen Kopien wegräumen', () async {
      final basis = await Directory.systemTemp.createTemp('ablage_test');
      addTearDown(() => basis.delete(recursive: true));
      final kopien = Directory(p.join(basis.path, kAblageOrdner, '123_0'));
      await kopien.create(recursive: true);
      final mail = File(p.join(kopien.path, 'Anfrage.msg'));
      await mail.writeAsBytes([1, 2, 3]);
      final fremd = File(p.join(basis.path, 'Eigene Datei.pdf'));
      await fremd.writeAsBytes([4]);
      final ordner = Directory(p.join(basis.path, 'Ordner'));
      await ordner.create();

      final gelesen = await ablageLesen([
        mail.path,
        fremd.path,
        ordner.path,
        p.join(basis.path, 'fehlt.txt'),
      ]);
      expect([for (final d in gelesen.dateien) d.name], [
        'Anfrage.msg',
        'Eigene Datei.pdf',
      ]);
      expect(gelesen.dateien.first.inhalt, [1, 2, 3]);
      expect(gelesen.fehlt, ['Ordner (Ordner)', 'fehlt.txt']);

      await ablageAufraeumen([mail.path, fremd.path]);
      // Die Kopie samt ihrem Ordner ist weg, die eigene Datei bleibt.
      expect(await kopien.exists(), isFalse);
      expect(await fremd.exists(), isTrue);
    });

    test('Kopien von früher wegräumen', () async {
      final basis = await Directory.systemTemp.createTemp('ablage_alt');
      addTearDown(() => basis.delete(recursive: true));
      final alt = await Directory(p.join(basis.path, '1_0')).create();
      await File(p.join(alt.path, 'Mail.msg')).writeAsBytes([1]);
      final datei = File(p.join(basis.path, 'liegt.txt'));
      await datei.writeAsBytes([2]);

      // Gerade erst angelegt: bleibt.
      await ablageAltesWegraeumen(basis: basis);
      expect(await alt.exists(), isTrue);
      // Zwei Stunden später: weg — nur Ordner, keine Dateien.
      await ablageAltesWegraeumen(
        basis: basis,
        jetzt: DateTime.now().add(const Duration(hours: 2)),
      );
      expect(await alt.exists(), isFalse);
      expect(await datei.exists(), isTrue);
      // Ohne Ordner nichts zu tun.
      await ablageAltesWegraeumen(
        basis: Directory(p.join(basis.path, 'gibt-es-nicht')),
      );
    });
  });
}

/// Eine erfundene Anfrage: mehrteilig, mit Text, HTML, Logo und PDF.
const String _anfrage =
    'From: =?ISO-8859-1?Q?M=FCller=2C_Hans?= <hans.mueller@muster-fleisch.de>\r\n'
    'To: Einkauf <einkauf@beispiel.de>, "Erika Beispiel" <erika@beispiel.de>\r\n'
    'Cc: qs@beispiel.de\r\n'
    'Subject: =?UTF-8?Q?AW:_Anfrage_Frikadelle_f=C3=BCr_den_?=\r\n'
    ' =?UTF-8?Q?Grill?=\r\n'
    'Date: Tue, 6 Oct 2026 14:05:00 +0200\r\n'
    'MIME-Version: 1.0\r\n'
    'Content-Type: multipart/mixed; boundary="aussen"\r\n'
    '\r\n'
    'Dies ist eine mehrteilige Nachricht.\r\n'
    '--aussen\r\n'
    'Content-Type: multipart/alternative; boundary=innen\r\n'
    '\r\n'
    '--innen\r\n'
    'Content-Type: text/plain; charset=utf-8\r\n'
    'Content-Transfer-Encoding: quoted-printable\r\n'
    '\r\n'
    'Guten Tag,\r\n'
    'wir suchen eine Frikadelle f=C3=BCr den Grill, ca. 80 g, gut gew=C3=BCr=\r\n'
    'zt.\r\n'
    '\r\n'
    'Viele Gr=C3=BC=C3=9Fe\r\n'
    'Hans M=C3=BCller\r\n'
    '\r\n'
    '-----Urspr=C3=BCngliche Nachricht-----\r\n'
    'Von: Erika\r\n'
    '> alter Text\r\n'
    '--innen\r\n'
    'Content-Type: text/html; charset=utf-8\r\n'
    '\r\n'
    '<html><body><p>HTML-Fassung</p></body></html>\r\n'
    '--innen--\r\n'
    '--aussen\r\n'
    'Content-Type: image/png\r\n'
    'Content-ID: <logo@beispiel>\r\n'
    'Content-Disposition: inline\r\n'
    'Content-Transfer-Encoding: base64\r\n'
    '\r\n'
    'iVBORw0KGgo=\r\n'
    '--aussen\r\n'
    'Content-Type: application/pdf; name="x.pdf"\r\n'
    'Content-Disposition: attachment;\r\n'
    " filename*=UTF-8''Spezifikation%20Gr%C3%BC%C3%9Fe.pdf\r\n"
    'Content-Transfer-Encoding: base64\r\n'
    '\r\n'
    'JVBERi0xLjQK\r\n'
    '--aussen--\r\n';

/// Eine erfundene Outlook-Mail: Betreff, Absender (Exchange und SMTP),
/// Empfänger, Datum, Text in Windows-1252, ein großer Anhang, ein
/// versteckter (Logo) und einer nur mit kurzem Namen.
Uint8List _msg() {
  List<int> unicode(String s) => [
        for (final c in s.codeUnits) ...[c & 0xFF, c >> 8],
      ];
  List<int> eigenschaften(List<(int, List<int>)> werte, {required int kopf}) {
    final b = BytesBuilder()..add(Uint8List(kopf));
    for (final (kennung, wert) in werte) {
      final eintrag = ByteData(16)
        ..setUint32(0, kennung, Endian.little)
        ..setUint32(4, 6, Endian.little);
      for (var i = 0; i < wert.length && i < 8; i++) {
        eintrag.setUint8(8 + i, wert[i]);
      }
      b.add(eintrag.buffer.asUint8List());
    }
    return b.takeBytes();
  }

  List<int> u64(int v) =>
      (ByteData(8)..setUint64(0, v, Endian.little)).buffer.asUint8List();
  final gesendet = DateTime.utc(2026, 10, 6, 12, 5)
          .difference(DateTime.utc(1601))
          .inMicroseconds *
      10;
  CfbKnoten text(String id, String wert) =>
      CfbKnoten.strom('__substg1.0_${id}001F', unicode(wert));

  return verbunddatei([
    CfbKnoten.strom(
      '__properties_version1.0',
      eigenschaften(
        [
          (0x00390040, u64(gesendet)),
          (0x3FFD0003, u64(1252)),
        ],
        kopf: 32,
      ),
    ),
    text('0037', 'Anfrage Bratwurst fein'),
    text('0C1A', 'Erika Beispiel'),
    text('0C1F', '/O=EXCHANGELABS/OU=EXCHANGE/CN=RECIPIENTS/CN=ERIKA'),
    text('5D01', 'erika.beispiel@beispiel-wurst.de'),
    text('0E04', 'Einkauf; Qualität'),
    CfbKnoten.strom(
      '__substg1.0_1000001E',
      latin1.encode('Grüße aus Musterstadt\r\nBitte um ein Muster.\u0000'),
    ),
    CfbKnoten.ordner('__recip_version1.0_#00000000', [
      text('3001', 'Einkauf'),
    ]),
    CfbKnoten.ordner('__attach_version1.0_#00000000', [
      CfbKnoten.strom('__properties_version1.0', eigenschaften([], kopf: 8)),
      text('3707', 'Rezeptur Bratwurst.xlsx'),
      text(
        '370E',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ),
      CfbKnoten.strom(
        '__substg1.0_37010102',
        List.generate(10000, (i) => i % 251),
      ),
    ]),
    CfbKnoten.ordner('__attach_version1.0_#00000001', [
      CfbKnoten.strom(
        '__properties_version1.0',
        eigenschaften([(0x7FFE000B, const [1, 0])], kopf: 8),
      ),
      text('3707', 'image001.png'),
      CfbKnoten.strom('__substg1.0_37010102', const [1, 2, 3]),
    ]),
    CfbKnoten.ordner('__attach_version1.0_#00000002', [
      text('3704', 'NOTIZ.TXT'),
      CfbKnoten.strom('__substg1.0_37010102', utf8.encode('kurz')),
    ]),
  ]);
}
