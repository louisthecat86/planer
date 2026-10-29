import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/druck/druck_bausteine.dart';
import '../../core/druck/druck_optionen.dart';
import '../../core/druck/druck_satz.dart';
import '../../core/services/auftragsbestand_deckung.dart'
    show beschreibeBezuege, teileBezuegeZu;
import '../../core/utils/datum.dart';
import '../../core/utils/format.dart';
import '../../core/utils/pdf_text.dart';
import '../../core/utils/zeit.dart';
import 'planungsvorschlag_service.dart';

// Der Planungsvorschlag auf Papier: je Tag die Artikel in der Reihenfolge
// der Bratstraße, mit Menge, Rohware, Dauer und was vor jedem Artikel zu
// rüsten oder zu reinigen ist — so, wie er gerade in der Ansicht steht,
// auch von Hand angepasst. Ein Entwurf, bis der Tag ins Board übernommen
// ist; das steht auf dem Blatt.

/// Schlüssel der Wahl im Druckfenster.
abstract final class VorschlagDruckWahl {
  static const tage = 'tage';
  static const aufteilung = 'aufteilung';
  static const hinweise = 'hinweise';
  static const auftraege = 'auftraege';
  static const nichtPlanbar = 'nichtPlanbar';
}

/// Was vom Planungsvorschlag gedruckt wird — die Wahl im Druckfenster.
class VorschlagDruckInhalt {
  const VorschlagDruckInhalt({
    this.tage,
    this.jeTag = false,
    this.hinweise = true,
    this.auftraege = false,
    this.nichtPlanbar = true,
  });

  /// Diese Tage — null: alle mit Aufträgen.
  final Set<DateTime>? tage;

  /// Jeder Tag auf eigenem Blatt — zum Weitergeben.
  final bool jeTag;

  /// Unter jedem Tag seine Hinweise und Regelbrüche.
  final bool hinweise;

  /// Unter jedem Artikel die Aufträge aus dem Auftragsbestand, für die er
  /// produziert wird.
  final bool auftraege;

  /// Was der Vorschlag nicht unterbringen konnte.
  final bool nichtPlanbar;
}

const PdfColor _rot = PdfColor.fromInt(0xFFC62828);
const PdfColor _orange = PdfColor.fromInt(0xFFEF6C00);

/// Der Planungsvorschlag zum Drucken. [uebernommen]: Tage, die schon ins
/// Board übernommen sind. [angepasst]: von Hand geändert.
DruckDokument vorschlagDruck({
  required List<VorschlagTag> tage,
  required VorschlagEinstellungen einstellungen,
  List<NichtPlanbar> nichtPlanbar = const [],
  Set<DateTime> uebernommen = const {},
  bool angepasst = false,
  VorschlagDruckInhalt inhalt = const VorschlagDruckInhalt(),
  DateTime? gedrucktAm,
}) {
  final wahl = inhalt.tage == null
      ? null
      : {for (final t in inhalt.tage!) tagOhneZeit(t)};
  final gedruckt = [
    for (final t in tage)
      if (t.posten.isNotEmpty &&
          (wahl == null || wahl.contains(tagOhneZeit(t.tag))))
        t,
  ];
  final mitListe = inhalt.nichtPlanbar && nichtPlanbar.isNotEmpty;
  if (gedruckt.isEmpty && !mitListe) {
    throw ArgumentError('Kein Tag zum Drucken gewählt.');
  }
  final druck = _VorschlagDruck(
    einstellungen: einstellungen,
    nichtPlanbar: nichtPlanbar,
    uebernommen: {for (final t in uebernommen) tagOhneZeit(t)},
    angepasst: angepasst,
    inhalt: inhalt,
    gedruckt: druckGedruckt(gedrucktAm ?? DateTime.now()),
  );
  final erster = gedruckt.isEmpty ? null : gedruckt.first.tag;
  return DruckDokument(
    titel: 'Planungsvorschlag',
    dateiname: druckDateiname(
      erster == null
          ? 'Planungsvorschlag'
          : 'Planungsvorschlag ${druckIsoDatum(erster)}',
    ),
    blaetter: inhalt.jeTag
        ? [
            for (final t in gedruckt) druck.blatt([t], mitListe: false),
            if (mitListe) druck.blatt(const [], mitListe: true),
          ]
        : [druck.blatt(gedruckt, mitListe: mitListe)],
  );
}

/// Der Planungsvorschlag für das Druckfenster — so, wie er in der Ansicht
/// steht. Welche Tage es gibt, hängt am Vorschlag und wird nicht gemerkt;
/// alles andere schon.
DruckAuftrag vorschlagDruckAuftrag({
  required List<VorschlagTag> tage,
  required VorschlagEinstellungen einstellungen,
  List<NichtPlanbar> nichtPlanbar = const [],
  Set<DateTime> uebernommen = const {},
  bool angepasst = false,
  DateTime? gedrucktAm,
}) {
  final mitPosten = [
    for (final t in tage)
      if (t.posten.isNotEmpty) t,
  ];
  final im = {for (final t in uebernommen) tagOhneZeit(t)};
  final auftraege = mitPosten.fold<int>(0, (s, t) => s + t.posten.length);
  final n = mitPosten.length;
  return DruckAuftrag(
    art: 'planungsvorschlag',
    titel: 'Planungsvorschlag drucken',
    untertitel: 'Entwurf · $auftraege '
        '${auftraege == 1 ? 'Auftrag' : 'Aufträge'} an $n '
        '${n == 1 ? 'Tag' : 'Tagen'}',
    optionen: [
      DruckWahlMehrere(
        schluessel: VorschlagDruckWahl.tage,
        titel: 'Tage',
        werte: [
          for (final t in mitPosten)
            DruckWert(
              druckIsoDatum(t.tag),
              Format.tagKurz(t.tag),
              hinweis: [
                _auftraegeText(t.posten.length),
                '${(t.auslastung * 100).round()} %',
                if (im.contains(tagOhneZeit(t.tag))) 'im Board',
              ].join(' · '),
            ),
        ],
        standard: {for (final t in mitPosten) druckIsoDatum(t.tag)},
        merken: false,
      ),
      const DruckWahlEins(
        schluessel: VorschlagDruckWahl.aufteilung,
        titel: 'Aufteilung',
        werte: [
          DruckWert('liste', 'Die Tage untereinander'),
          DruckWert(
            'tage',
            'Jeder Tag auf eigenem Blatt',
            hinweis: 'Zum Weitergeben an die Linie',
          ),
        ],
        standard: 'liste',
      ),
      const DruckSchalter(
        schluessel: VorschlagDruckWahl.hinweise,
        titel: 'Hinweise und Regelbrüche',
        gruppe: 'Auf dem Plan',
      ),
      const DruckSchalter(
        schluessel: VorschlagDruckWahl.auftraege,
        titel: 'Aufträge aus dem Auftragsbestand',
        hinweis: 'Versand, Aufträge und Kunden je Artikel',
        standard: false,
        gruppe: 'Auf dem Plan',
      ),
      if (nichtPlanbar.isNotEmpty)
        const DruckSchalter(
          schluessel: VorschlagDruckWahl.nichtPlanbar,
          titel: 'Nicht Eingeplantes',
          hinweis: 'Was der Vorschlag nicht unterbringen konnte — mit Grund',
          gruppe: 'Auf dem Plan',
        ),
    ],
    bauen: (wahl) {
      final gewaehlt = wahl.mehrere(VorschlagDruckWahl.tage);
      final tageGewaehlt = {
        for (final t in mitPosten)
          if (gewaehlt.contains(druckIsoDatum(t.tag))) t.tag,
      };
      if (tageGewaehlt.isEmpty) {
        throw const DruckNichtsGewaehlt('Wähle mindestens einen Tag.');
      }
      return vorschlagDruck(
        tage: tage,
        einstellungen: einstellungen,
        nichtPlanbar: nichtPlanbar,
        uebernommen: uebernommen,
        angepasst: angepasst,
        gedrucktAm: gedrucktAm,
        inhalt: VorschlagDruckInhalt(
          tage: tageGewaehlt,
          jeTag: wahl.eins(VorschlagDruckWahl.aufteilung) == 'tage',
          hinweise: wahl.an(VorschlagDruckWahl.hinweise),
          auftraege: wahl.an(VorschlagDruckWahl.auftraege),
          nichtPlanbar: nichtPlanbar.isNotEmpty &&
              wahl.an(VorschlagDruckWahl.nichtPlanbar),
        ),
      );
    },
  );
}

String _auftraegeText(int n) => n == 1 ? '1 Auftrag' : '$n Aufträge';

/// Bis zu so vielen Aufträgen bleibt ein Tag samt Leiste auf einer Seite:
/// Eine Zeile ist höchstens rund 36 Punkt hoch, die Seite bietet über 650.
const int _zusammenBis = 14;

class _VorschlagDruck {
  _VorschlagDruck({
    required this.einstellungen,
    required this.nichtPlanbar,
    required this.uebernommen,
    required this.angepasst,
    required this.inhalt,
    required this.gedruckt,
  });

  final VorschlagEinstellungen einstellungen;
  final List<NichtPlanbar> nichtPlanbar;
  final Set<DateTime> uebernommen;
  final bool angepasst;
  final VorschlagDruckInhalt inhalt;
  final String gedruckt;

  bool imBoard(VorschlagTag t) => uebernommen.contains(tagOhneZeit(t.tag));

  /// Ein Blatt mit [tage] — bei einem einzigen Tag nennt ihn der Kopf. Mit
  /// [mitListe] steht am Ende, was nicht eingeplant wurde.
  DruckBlatt blatt(List<VorschlagTag> tage, {required bool mitListe}) {
    final auftraege = tage.fold<int>(0, (s, t) => s + t.posten.length);
    final rohware = tage.fold<double>(0, (s, t) => s + t.rohwareKg);
    final String zeile;
    if (tage.isEmpty) {
      zeile = 'Nicht eingeplant';
    } else if (tage.length == 1) {
      zeile = '${Format.datumLang(tage.single.tag)} · '
          '${_auftraegeText(auftraege)} · ${Format.kg(rohware)} Rohware';
    } else {
      zeile = '${Format.tagKurz(tage.first.tag)} - '
          '${Format.tagKurz(tage.last.tag)}${tage.last.tag.year} · '
          '${_auftraegeText(auftraege)} an ${tage.length} Tagen · '
          '${Format.kg(rohware)} Rohware';
    }
    return DruckBlatt(
      rand: const pw.EdgeInsets.fromLTRB(28, 24, 28, 20),
      bauen: (r) {
        final teile = <pw.Widget>[
          ...vorspann(tage),
          for (final t in tage) ...tag(t, r, leiste: tage.length > 1),
          if (mitListe) ...nichtEingeplant(r),
        ];
        return DruckSeiten(
          kopf: (ctx) => druckKopf(
            titel: 'Planungsvorschlag',
            zeile: zeile,
            gedruckt: gedruckt,
          ),
          fuss: (ctx) => druckFuss(
            'Planungsvorschlag · $gedruckt',
            r.seitenText(ctx),
          ),
          inhalt: (ctx) => teile,
        );
      },
    );
  }

  /// Ob der Plan schon im Board steht, und womit gerechnet wurde.
  List<pw.Widget> vorspann(List<VorschlagTag> tage) {
    if (tage.isEmpty) return const [];
    final im = tage.where(imBoard).length;
    final stand = switch (im) {
      0 => 'Entwurf — noch nicht im Board. Erst „Tag ins Board übernehmen" '
          'legt die Aufträge an.',
      _ when im == tage.length => tage.length == 1
          ? 'Dieser Tag ist ins Board übernommen.'
          : 'Alle Tage sind ins Board übernommen.',
      _ => 'Entwurf — $im von ${tage.length} Tagen sind ins Board '
          'übernommen.',
    };
    final e = einstellungen;
    final regeln = [
      '${e.moeglichstSpaet ? 'So spät' : 'So früh'} wie möglich, nie nach '
          'dem Termin',
      'Rüsten ${e.ruestenMinuten.round()} min',
      'Reinigen ${e.zwischenreinigungMinuten.round()} min',
      'Endreinigung ${e.endreinigungMinuten.round()} min',
    ].join(' · ');
    return [
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 2),
        child: pw.Text(
          pdfText('$stand${angepasst ? ' Von Hand angepasst.' : ''}'),
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        ),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: druckHinweis(regeln, zeilen: 2),
      ),
    ];
  }

  /// Ein Tag: Leiste (in der Liste), was er belegt, die Aufträge, Hinweise.
  List<pw.Widget> tag(
    VorschlagTag t,
    DruckRahmen rahmen, {
    required bool leiste,
  }) {
    final voll = t.auslastung > 1;
    final belegung = [
      '${(t.auslastung * 100).round()} %',
      'neu ${Zeit.kurz(t.neuMinuten)} von ${Zeit.kurz(t.kapazitaetMinuten)}',
      if (imBoard(t)) 'im Board',
    ].join(' · ');
    final angaben = [
      if (!leiste) belegung,
      if (t.belegtVorherMinuten > 0)
        'im Board schon ${Zeit.kurz(t.belegtVorherMinuten)}',
      '${Format.kg(t.rohwareKg)} Rohware',
      if (t.endreinigungMinuten > 0)
        'Endreinigung ${Zeit.kurz(t.endreinigungMinuten)}',
      if (voll) 'überbucht',
    ].join(' · ');
    final hinweise = inhalt.hinweise
        ? [
            for (final b in Planungsrechner.regelbrueche(t.posten))
              druckZelleMitPunkt(b, _orange, groesse: 8),
            for (final w in t.warnungen) druckHinweis(w, zeilen: 3),
          ]
        : const <pw.Widget>[];
    return [
      ...druckGruppe(
        [
          if (leiste)
            druckLeiste(
              '${Format.wochentage[t.tag.weekday - 1]}, '
              '${Format.datum(t.tag)}',
              rechts: belegung,
            ),
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3),
            child: druckHinweis(angaben, zeilen: 2),
          ),
          tabelle(t),
        ],
        zusammen: t.posten.length <= _zusammenBis,
        rahmen: rahmen,
      ),
      ...hinweise,
      pw.SizedBox(height: 12),
    ];
  }

  static const _breiten = <int, pw.TableColumnWidth>{
    0: pw.FixedColumnWidth(18),
    1: pw.FixedColumnWidth(50),
    2: pw.FlexColumnWidth(),
    3: pw.FixedColumnWidth(60),
    4: pw.FixedColumnWidth(58),
    5: pw.FixedColumnWidth(44),
    6: pw.FixedColumnWidth(84),
  };

  pw.Widget tabelle(VorschlagTag t) {
    return pw.Table(
      border: kDruckGitter,
      columnWidths: _breiten,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        druckKopfzeile([
          druckKopfZelle('#', rechts: true),
          druckKopfZelle('Art.-Nr.'),
          druckKopfZelle('Artikel'),
          druckKopfZelle('Fertigware', rechts: true),
          druckKopfZelle('Rohware', rechts: true),
          druckKopfZelle('Dauer', rechts: true),
          druckKopfZelle('Wechsel davor'),
        ]),
        for (final (i, p) in t.posten.indexed) posten(i, p, amTag: t.tag),
      ],
    );
  }

  pw.TableRow posten(int i, VorschlagPosten p, {required DateTime amTag}) {
    final termin = p.termin;
    final zuSpaet = p.zuSpaetAm(amTag);
    // Beim Übernehmen bekommt die Produktion so viele Aufträge, wie ihre
    // Menge bedient — der früheste Versand zuerst.
    final fuer = teileBezuegeZu(p.auftragsBezuege, p.mengeKg);
    final belege = {for (final b in p.auftragsBezuege) b.beleg};
    final unten = [
      if (p.begruendung.isNotEmpty) p.begruendung,
      if (termin != null)
        zuSpaet
            ? 'nach dem Termin (${Format.tagKurz(termin)})!'
            : 'spätestens ${Format.tagKurz(termin)}',
      if (inhalt.auftraege && fuer.isNotEmpty)
        'für ${beschreibeBezuege(fuer)}'
      else if (belege.isNotEmpty)
        'Auftragsbestand, ${_auftraegeText(belege.length)}',
    ].join(' · ');
    final (wechsel, wechselFarbe, fett) = switch (p.wechselGrund) {
      WechselGrund.tagesstart => ('–', kDruckGrau, false),
      WechselGrund.ohneUmstellung => ('ohne Umstellen', kDruckGrau, false),
      WechselGrund.umstellen => (
          'umrüsten ${Zeit.kurz(p.nebenzeitMinuten)}',
          PdfColors.black,
          false,
        ),
      WechselGrund.reinigen => (
          'reinigen ${Zeit.kurz(p.nebenzeitMinuten)}',
          _orange,
          true,
        ),
    };
    return pw.TableRow(
      children: [
        druckZelle('${i + 1}', rechts: true, farbe: kDruckGrau, groesse: 8.5),
        druckZelle(p.artikelnummer, fett: true),
        druckZelleMitZeile(
          p.bezeichnung,
          unten,
          farbeUnten: zuSpaet ? _rot : kDruckGrau,
        ),
        druckZelle(Format.kg(p.mengeKg), rechts: true, fett: true),
        druckZelle(Format.kg(p.rohwareKg), rechts: true, groesse: 8.5),
        druckZelle(Zeit.kurz(p.dauerMinuten), rechts: true, groesse: 8.5),
        druckZelle(wechsel, fett: fett, farbe: wechselFarbe, groesse: 8.5),
      ],
    );
  }

  /// Was der Vorschlag nicht unterbringen konnte — mit Grund.
  List<pw.Widget> nichtEingeplant(DruckRahmen r) {
    final n = nichtPlanbar.length;
    return druckGruppe(
      [
        druckLeiste(
          'Nicht eingeplant',
          rechts: n == 1 ? '1 Artikel' : '$n Artikel',
        ),
        pw.Table(
          border: kDruckGitter,
          columnWidths: const {
            0: pw.FixedColumnWidth(50),
            1: pw.FlexColumnWidth(),
            2: pw.FixedColumnWidth(60),
            3: pw.FixedColumnWidth(200),
          },
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
          children: [
            druckKopfzeile([
              druckKopfZelle('Art.-Nr.'),
              druckKopfZelle('Artikel'),
              druckKopfZelle('Menge', rechts: true),
              druckKopfZelle('Grund'),
            ]),
            for (final x in nichtPlanbar)
              pw.TableRow(
                children: [
                  druckZelle(x.artikelnummer, fett: true),
                  druckZelle(x.bezeichnung, zeilen: 2),
                  druckZelle(Format.kg(x.mengeKg), rechts: true),
                  druckZelle(x.grund, zeilen: 3, groesse: 8.5),
                ],
              ),
          ],
        ),
      ],
      zusammen: n <= _zusammenBis,
      rahmen: r,
    );
  }
}
