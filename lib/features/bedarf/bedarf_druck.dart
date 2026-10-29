import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/druck/druck_bausteine.dart';
import '../../core/druck/druck_optionen.dart';
import '../../core/druck/druck_satz.dart';
import '../../core/services/auftragsbestand_deckung.dart'
    show kQuelleAuftragsbestand;
import '../../core/utils/datum.dart';
import '../../core/utils/format.dart';
import '../../core/utils/kalenderwoche.dart';
import 'bedarf_modell.dart';

// Die Bedarfsliste auf Papier: was noch einzuplanen ist — Überfälliges
// zuerst, dann je Kalenderwoche des Termins —, mit Menge, eingeplant und
// offen. Zum Besprechen oder zum Abhaken beim Planen.

/// Schlüssel der Wahl im Druckfenster.
abstract final class BedarfDruckWahl {
  static const umfang = 'umfang';
  static const herkunft = 'herkunft';
  static const gliederung = 'gliederung';
  static const notizen = 'notizen';
}

/// Was von der Bedarfsliste gedruckt wird — die Wahl im Druckfenster.
class BedarfDruckInhalt {
  const BedarfDruckInhalt({
    this.mitErledigten = false,
    this.quellen,
    this.nachArtikel = false,
    this.notizen = true,
  });

  /// Auch, was erledigt ist — grau, am Ende.
  final bool mitErledigten;

  /// Nur Bedarfe dieser Herkunft — null: alle.
  final Set<String>? quellen;

  /// Nach Artikelnummer statt nach Termin.
  final bool nachArtikel;

  /// Unter dem Artikel, woher der Bedarf kommt, und seine Notiz.
  final bool notizen;
}

/// Ab so viel gilt ein Bedarf als offen — wie in der Liste.
const double _halbesKilo = 0.5;

const PdfColor _rot = PdfColor.fromInt(0xFFC62828);

/// Die Bedarfsliste zum Drucken. [bedarfe] in der Reihenfolge der Liste:
/// erledigte am Ende, Überfälliges zuerst, dann nach Termin und Priorität.
DruckDokument bedarfDruck(
  List<BedarfInfo> bedarfe, {
  required DateTime heute,
  BedarfDruckInhalt inhalt = const BedarfDruckInhalt(),
  DateTime? gedrucktAm,
}) {
  final tag = tagOhneZeit(heute);
  final quellen = inhalt.quellen;
  final liste = [
    for (final b in bedarfe)
      if ((inhalt.mitErledigten || !b.erledigt) &&
          (quellen == null || quellen.contains(b.bedarf.quelle)))
        b,
  ];
  final druck = _BedarfDruck(
    liste,
    inhalt: inhalt,
    heute: tag,
    gedruckt: druckGedruckt(gedrucktAm ?? DateTime.now()),
  );
  return DruckDokument(
    titel: 'Bedarfsliste ${Format.datum(tag)}',
    dateiname: druckDateiname('Bedarfsliste ${druckIsoDatum(tag)}'),
    blaetter: [druck.blatt()],
  );
}

/// Die Bedarfsliste für das Druckfenster. Welche Herkunft vorkommt, hängt
/// an den Daten und wird nicht gemerkt; alles andere schon.
DruckAuftrag bedarfDruckAuftrag(
  List<BedarfInfo> bedarfe, {
  required DateTime heute,
  DateTime? gedrucktAm,
}) {
  final offen = bedarfe.where((b) => !b.erledigt).length;
  final jeQuelle = <String, int>{};
  for (final b in bedarfe) {
    jeQuelle[b.bedarf.quelle] = (jeQuelle[b.bedarf.quelle] ?? 0) + 1;
  }
  // In fester Reihenfolge, Unbekanntes danach.
  const bekannt = [
    'bestellung',
    'bestand',
    'sonstiges',
    kQuelleAuftragsbestand,
  ];
  final quellen = [
    for (final q in bekannt)
      if (jeQuelle.containsKey(q)) q,
    for (final q in jeQuelle.keys)
      if (!bekannt.contains(q)) q,
  ];
  final waehlbar = quellen.length > 1;

  return DruckAuftrag(
    art: 'bedarf',
    titel: 'Bedarfsliste drucken',
    untertitel: _offeneText(offen),
    optionen: [
      const DruckWahlEins(
        schluessel: BedarfDruckWahl.umfang,
        titel: 'Was',
        werte: [
          DruckWert('offen', 'Nur offene Bedarfe'),
          DruckWert(
            'alle',
            'Auch erledigte',
            hinweis: 'Grau, am Ende der Liste',
          ),
        ],
        standard: 'offen',
      ),
      if (waehlbar)
        DruckWahlMehrere(
          schluessel: BedarfDruckWahl.herkunft,
          titel: 'Herkunft',
          werte: [
            for (final q in quellen)
              DruckWert(
                q,
                bedarfQuelleText(q),
                hinweis: _bedarfeText(jeQuelle[q] ?? 0),
              ),
          ],
          standard: {...quellen},
          merken: false,
        ),
      const DruckWahlEins(
        schluessel: BedarfDruckWahl.gliederung,
        titel: 'Reihenfolge',
        werte: [
          DruckWert(
            'termin',
            'Nach Termin',
            hinweis: 'Überfälliges zuerst, dann je Kalenderwoche',
          ),
          DruckWert('artikel', 'Nach Artikelnummer'),
        ],
        standard: 'termin',
      ),
      const DruckSchalter(
        schluessel: BedarfDruckWahl.notizen,
        titel: 'Herkunft und Notiz',
        hinweis: 'Unter dem Artikel',
      ),
    ],
    bauen: (wahl) {
      final gewaehlt =
          waehlbar ? wahl.mehrere(BedarfDruckWahl.herkunft) : null;
      if (gewaehlt != null && gewaehlt.isEmpty) {
        throw const DruckNichtsGewaehlt('Wähle mindestens eine Herkunft.');
      }
      return bedarfDruck(
        bedarfe,
        heute: heute,
        gedrucktAm: gedrucktAm,
        inhalt: BedarfDruckInhalt(
          mitErledigten: wahl.eins(BedarfDruckWahl.umfang) == 'alle',
          quellen: gewaehlt,
          nachArtikel: wahl.eins(BedarfDruckWahl.gliederung) == 'artikel',
          notizen: wahl.an(BedarfDruckWahl.notizen),
        ),
      );
    },
  );
}

String _bedarfeText(int n) => n == 1 ? '1 Bedarf' : '$n Bedarfe';

String _offeneText(int n) =>
    n == 1 ? '1 offener Bedarf' : '$n offene Bedarfe';

/// Ein Abschnitt der Liste: eine Überschrift und ihre Bedarfe.
typedef _Abschnitt = ({String titel, List<BedarfInfo> bedarfe});

/// Bis zu so vielen Bedarfen bleibt ein Abschnitt auf einer Seite.
const int _zusammenBis = 16;

class _BedarfDruck {
  _BedarfDruck(
    this.bedarfe, {
    required this.inhalt,
    required this.heute,
    required this.gedruckt,
  });

  final List<BedarfInfo> bedarfe;
  final BedarfDruckInhalt inhalt;
  final DateTime heute;
  final String gedruckt;

  static const _breiten = <int, pw.TableColumnWidth>{
    0: pw.FixedColumnWidth(50),
    1: pw.FlexColumnWidth(),
    2: pw.FixedColumnWidth(70),
    3: pw.FixedColumnWidth(56),
    4: pw.FixedColumnWidth(60),
    5: pw.FixedColumnWidth(58),
    6: pw.FixedColumnWidth(18),
  };

  DruckBlatt blatt() {
    final offen = [
      for (final b in bedarfe)
        if (!b.erledigt) b,
    ];
    final zeile = [
      _offeneText(offen.length),
      'Stand ${Format.datum(heute)}',
    ].join(' · ');
    return DruckBlatt(
      rand: const pw.EdgeInsets.fromLTRB(28, 24, 28, 20),
      bauen: (r) {
        final teile = <pw.Widget>[
          for (final a in abschnitte()) ...abschnitt(a, r),
        ];
        return DruckSeiten(
          kopf: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              druckKopf(
                titel: 'Bedarfsliste',
                zeile: zeile,
                gedruckt: gedruckt,
              ),
              if (r.seiteImBlatt(ctx) == 1) druckKennzahlen(kennzahlen()),
              if (teile.isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Table(
                    border: kDruckGitter,
                    columnWidths: _breiten,
                    children: [
                      druckKopfzeile([
                        druckKopfZelle('Art.-Nr.'),
                        druckKopfZelle('Artikel'),
                        druckKopfZelle('Termin'),
                        druckKopfZelle('Bedarf', rechts: true),
                        druckKopfZelle('eingeplant', rechts: true),
                        druckKopfZelle('offen', rechts: true),
                        pw.SizedBox(),
                      ]),
                    ],
                  ),
                ),
            ],
          ),
          fuss: (ctx) => druckFuss(
            'Bedarfsliste ${Format.datum(heute)}',
            r.seitenText(ctx),
          ),
          inhalt: (ctx) => teile.isEmpty
              ? [
                  druckHinweis(
                    inhalt.mitErledigten
                        ? 'Kein Bedarf erfasst.'
                        : 'Kein offener Bedarf.',
                  ),
                ]
              : teile,
        );
      },
    );
  }

  List<DruckKennzahl> kennzahlen() {
    final offen = [
      for (final b in bedarfe)
        if (!b.erledigt) b,
    ];
    final ueberfaellig = offen.where((b) => b.ueberfaellig).length;
    final einzuplanen = offen.fold<double>(0, (s, b) => s + b.offenKg);
    final erledigt = bedarfe.length - offen.length;
    return [
      DruckKennzahl('${offen.length}', 'offen'),
      DruckKennzahl(
        Format.kg(einzuplanen),
        'noch einzuplanen',
        betont: einzuplanen >= _halbesKilo,
      ),
      if (ueberfaellig > 0)
        DruckKennzahl('$ueberfaellig', 'überfällig', betont: true),
      if (erledigt > 0) DruckKennzahl('$erledigt', 'erledigt'),
    ];
  }

  /// Nach Termin: Überfällig, je Kalenderwoche, ohne Termin, erledigt.
  /// Nach Artikel: ein Abschnitt, nach Artikelnummer und Termin.
  List<_Abschnitt> abschnitte() {
    if (bedarfe.isEmpty) return const [];
    if (inhalt.nachArtikel) {
      final liste = [...bedarfe]..sort((a, b) {
          final n = a.artikelNummer.compareTo(b.artikelNummer);
          if (n != 0) return n;
          final ta = a.bedarf.termin;
          final tb = b.bedarf.termin;
          if (ta != null && tb != null) return ta.compareTo(tb);
          if (ta != null) return -1;
          if (tb != null) return 1;
          return 0;
        });
      return [(titel: '', bedarfe: liste)];
    }
    final ueberfaellig = <BedarfInfo>[];
    final jeWoche = <(int, int), List<BedarfInfo>>{};
    final ohneTermin = <BedarfInfo>[];
    final erledigt = <BedarfInfo>[];
    for (final b in bedarfe) {
      final t = b.bedarf.termin;
      if (b.erledigt) {
        erledigt.add(b);
      } else if (b.ueberfaellig) {
        ueberfaellig.add(b);
      } else if (t == null) {
        ohneTermin.add(b);
      } else {
        (jeWoche[(isoKalenderjahr(t), isoKalenderwoche(t))] ??= []).add(b);
      }
    }
    final wochen = jeWoche.keys.toList()
      ..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
    return [
      if (ueberfaellig.isNotEmpty)
        (titel: 'Überfällig', bedarfe: ueberfaellig),
      for (final w in wochen)
        (
          titel: wochenTitel(jeWoche[w]!.first.bedarf.termin!),
          bedarfe: jeWoche[w]!,
        ),
      if (ohneTermin.isNotEmpty) (titel: 'Ohne Termin', bedarfe: ohneTermin),
      if (erledigt.isNotEmpty) (titel: 'Erledigt', bedarfe: erledigt),
    ];
  }

  /// „KW 45 · 02.11. - 08.11.2026"
  static String wochenTitel(DateTime tag) {
    final montag = tagPlus(tag, 1 - tag.weekday);
    final sonntag = tagPlus(montag, 6);
    return 'KW ${isoKalenderwoche(tag)} · ${Format.datumKurz(montag)} - '
        '${Format.datum(sonntag)}';
  }

  List<pw.Widget> abschnitt(_Abschnitt a, DruckRahmen r) {
    final offen = a.bedarfe.fold<double>(0, (s, b) => s + b.offenKg);
    final n = a.bedarfe.length;
    final zeilen = [for (final b in a.bedarfe) zeile(b)];
    return druckGruppe(
      [
        if (a.titel.isNotEmpty)
          druckLeiste(
            a.titel,
            rechts: [
              _bedarfeText(n),
              if (offen >= _halbesKilo) 'offen ${Format.kg(offen)}',
            ].join(' · '),
          ),
        pw.Table(
          border: kDruckGitter,
          columnWidths: _breiten,
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
          children: zeilen,
        ),
        pw.SizedBox(height: 8),
      ],
      zusammen: n <= _zusammenBis,
      rahmen: r,
    );
  }

  pw.TableRow zeile(BedarfInfo info) {
    final b = info.bedarf;
    final blass = info.erledigt;
    final farbe = blass ? kDruckGrau : PdfColors.black;
    final notiz = (b.notizen ?? '').trim();
    final unten = inhalt.notizen
        ? [bedarfQuelleText(b.quelle), if (notiz.isNotEmpty) notiz].join(' · ')
        : null;
    final termin = b.termin;
    final pw.Widget terminZelle;
    if (termin == null) {
      terminZelle = druckZelle('ohne', farbe: kDruckGrau, groesse: 8.5);
    } else {
      final text = termin.year == heute.year
          ? Format.tagKurz(termin)
          : Format.datum(termin);
      terminZelle = info.ueberfaellig
          ? druckZelleMitZeile(
              text,
              'überfällig',
              fett: true,
              groesse: 8.5,
              farbe: _rot,
            )
          : druckZelle(text, groesse: 8.5, farbe: farbe);
    }
    final String offenText;
    if (info.erledigt) {
      final vonHand = b.manuellErledigt &&
          info.produziertKg < b.mengeKgFertig - _halbesKilo;
      offenText = vonHand ? 'erledigt' : 'gedeckt';
    } else {
      offenText =
          info.offenKg >= _halbesKilo ? Format.kg(info.offenKg) : '–';
    }
    return pw.TableRow(
      children: [
        druckZelle(info.artikelNummer, fett: true, farbe: farbe),
        druckZelleMitZeile(
          info.artikelName,
          unten,
          farbe: farbe,
          zeilenUnten: 2,
        ),
        terminZelle,
        druckZelle(
          Format.kg(b.mengeKgFertig),
          rechts: true,
          groesse: 8.5,
          farbe: farbe,
        ),
        druckZelle(
          info.geplantKg >= _halbesKilo ? Format.kg(info.geplantKg) : '–',
          rechts: true,
          groesse: 8.5,
          farbe: info.geplantKg >= _halbesKilo ? farbe : kDruckGrau,
        ),
        druckZelle(
          offenText,
          rechts: true,
          fett: !info.erledigt && info.offenKg >= _halbesKilo,
          groesse: 8.5,
          farbe: info.erledigt || info.offenKg < _halbesKilo
              ? kDruckGrau
              : PdfColors.black,
        ),
        b.prioritaet > 0 && !info.erledigt
            ? druckZelle('!', fett: true, farbe: _rot, rechts: true)
            : pw.SizedBox(),
      ],
    );
  }
}
