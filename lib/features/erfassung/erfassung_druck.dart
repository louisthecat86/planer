import 'package:pdf/widgets.dart' as pw;

import '../../core/constants/abteilungen.dart';
import '../../core/druck/druck_bausteine.dart';
import '../../core/druck/druck_optionen.dart';
import '../../core/druck/druck_satz.dart';
import '../../core/utils/datum.dart';
import '../../core/utils/format.dart';
import '../../core/utils/kalenderwoche.dart';
import 'geplante_produktion.dart';

// Die Erfassungsliste: die geplanten Produktionen der Woche auf Papier, mit
// leeren Spalten für die Ist-Werte — Rohware, Fertigware, Start und Ende,
// dazu Charge, Kürzel und Bemerkung. Was dort von Hand steht, kommt danach
// in die Produktionserfassung. Gedruckt wird, was die Erfassung zeigt: was
// noch nicht erfasst ist.

/// Schlüssel der Wahl im Druckfenster.
abstract final class ErfassungDruckWahl {
  static const tage = 'tage';
  static const aufteilung = 'aufteilung';
  static const abteilungen = 'abteilungen';
  static const plan = 'plan';
  static const leer = 'leer';
  static const charge = 'charge';
  static const kuerzel = 'kuerzel';
  static const bemerkung = 'bemerkung';
}

/// Was von der Erfassungsliste gedruckt wird — die Wahl im Druckfenster.
class ErfassungDruckInhalt {
  const ErfassungDruckInhalt({
    this.wochentage,
    this.jeTag = false,
    this.abteilungen,
    this.plan = true,
    this.leereZeilen = 3,
    this.charge = true,
    this.kuerzel = true,
    this.bemerkung = true,
  });

  /// Diese Wochentage (1 = Montag) — null: die mit Produktionen, gibt es
  /// keine, alle.
  final Set<int>? wochentage;

  /// Jeder Tag auf eigenem Blatt — zum Aushängen an der Linie.
  final bool jeTag;

  /// Nur Produktionen dieser Abteilungen (gespeicherter Wert) — null: alle.
  final Set<String>? abteilungen;

  /// Unter dem Artikel, was geplant ist: Mengen, Startzeit, Notiz.
  final bool plan;

  /// So viele leere Zeilen je Tag — zum Nachtragen von Ungeplantem.
  final int leereZeilen;

  /// Spalten zum Eintragen, außer Mengen und Zeiten.
  final bool charge;
  final bool kuerzel;
  final bool bemerkung;
}

/// Die Erfassungsliste der Woche ab [montag] (Montag bis Freitag) aus den
/// geplanten Produktionen je Tag ([gruppen]).
DruckDokument erfassungDruck({
  required DateTime montag,
  required Map<DateTime, List<GeplanteProduktion>> gruppen,
  ErfassungDruckInhalt inhalt = const ErfassungDruckInhalt(),
  DateTime? gedrucktAm,
}) {
  final kw = isoKalenderwoche(montag);
  final woche = _woche(montag);
  final gewaehlt = inhalt.wochentage ?? _vorschlag(woche, gruppen);
  final tage = [
    for (final t in woche)
      if (gewaehlt.contains(t.weekday)) t,
  ];
  if (tage.isEmpty) {
    throw ArgumentError('Kein Tag zum Drucken gewählt.');
  }
  final liste = _Erfassungsliste(
    gruppen: gruppen,
    inhalt: inhalt,
    tage: tage,
    kw: kw,
    gedruckt: druckGedruckt(gedrucktAm ?? DateTime.now()),
  );
  final einTag = tage.length == 1;
  return DruckDokument(
    titel: einTag
        ? 'Produktionserfassung ${Format.datum(tage.single)}'
        : 'Produktionserfassung KW $kw',
    dateiname: druckDateiname(
      einTag
          ? 'Produktionserfassung ${druckIsoDatum(tage.single)}'
          : 'Produktionserfassung KW $kw',
    ),
    blaetter: inhalt.jeTag
        ? [for (final t in tage) liste.blatt([t])]
        : [liste.blatt(tage)],
  );
}

/// Die Erfassungsliste für das Druckfenster. Vorgeschlagen sind die Tage
/// und Abteilungen, an denen etwas zu erfassen ist — sie hängen an den
/// Daten und werden nicht gemerkt; alles andere schon.
DruckAuftrag erfassungDruckAuftrag({
  required DateTime montag,
  required Map<DateTime, List<GeplanteProduktion>> gruppen,
  DateTime? gedrucktAm,
}) {
  final kw = isoKalenderwoche(montag);
  final woche = _woche(montag);
  int anzahl(DateTime t) => gruppen[t]?.length ?? 0;

  final jeAbteilung = <Abteilung, int>{};
  for (final liste in gruppen.values) {
    for (final p in liste) {
      final a = _abteilung(p.task.abteilung);
      if (a != null) jeAbteilung[a] = (jeAbteilung[a] ?? 0) + 1;
    }
  }
  final abteilungen = [
    for (final a in Abteilung.values)
      if (jeAbteilung.containsKey(a)) a,
  ];
  // Nur wählbar, wenn es etwas zu wählen gibt.
  final abteilungWaehlbar = abteilungen.length > 1;

  return DruckAuftrag(
    art: 'erfassung',
    titel: 'Erfassungsliste drucken',
    untertitel: 'Produktionserfassung · KW $kw',
    optionen: [
      DruckWahlMehrere(
        schluessel: ErfassungDruckWahl.tage,
        titel: 'Tage',
        werte: [
          for (final t in woche)
            DruckWert(
              '${t.weekday}',
              Format.tagKurz(t),
              hinweis: _produktionenText(anzahl(t)),
            ),
        ],
        standard: {for (final nr in _vorschlag(woche, gruppen)) '$nr'},
        merken: false,
      ),
      const DruckWahlEins(
        schluessel: ErfassungDruckWahl.aufteilung,
        titel: 'Aufteilung',
        werte: [
          DruckWert(
            'woche',
            'Die Tage untereinander',
            hinweis: 'Eine Liste für die ganze Woche',
          ),
          DruckWert(
            'tage',
            'Jeder Tag auf eigenem Blatt',
            hinweis: 'Zum Aushängen an der Linie',
          ),
        ],
        standard: 'woche',
      ),
      if (abteilungWaehlbar)
        DruckWahlMehrere(
          schluessel: ErfassungDruckWahl.abteilungen,
          titel: 'Abteilungen',
          werte: [
            for (final a in abteilungen)
              DruckWert(
                a.dbValue,
                a.anzeigeName,
                hinweis: _produktionenText(jeAbteilung[a] ?? 0),
                farbe: a.farbwert,
                kuerzel: a.kurzcode,
              ),
          ],
          standard: {for (final a in abteilungen) a.dbValue},
          merken: false,
        ),
      const DruckSchalter(
        schluessel: ErfassungDruckWahl.plan,
        titel: 'Was geplant ist',
        hinweis: 'Mengen, Startzeit und Notiz unter dem Artikel',
        gruppe: 'Auf der Liste',
      ),
      const DruckSchalter(
        schluessel: ErfassungDruckWahl.leer,
        titel: 'Leere Zeilen zum Nachtragen',
        hinweis: 'Drei je Tag — für Ungeplantes',
        gruppe: 'Auf der Liste',
      ),
      const DruckSchalter(
        schluessel: ErfassungDruckWahl.charge,
        titel: 'Charge',
        gruppe: 'Spalten zum Eintragen',
      ),
      const DruckSchalter(
        schluessel: ErfassungDruckWahl.kuerzel,
        titel: 'Kürzel',
        gruppe: 'Spalten zum Eintragen',
      ),
      const DruckSchalter(
        schluessel: ErfassungDruckWahl.bemerkung,
        titel: 'Bemerkung',
        gruppe: 'Spalten zum Eintragen',
      ),
    ],
    bauen: (wahl) {
      final tage = {
        for (final t in wahl.mehrere(ErfassungDruckWahl.tage))
          if (int.tryParse(t) case final nr?) nr,
      };
      if (tage.isEmpty) {
        throw const DruckNichtsGewaehlt('Wähle mindestens einen Tag.');
      }
      final gewaehlteAbteilungen = abteilungWaehlbar
          ? wahl.mehrere(ErfassungDruckWahl.abteilungen)
          : null;
      if (gewaehlteAbteilungen != null && gewaehlteAbteilungen.isEmpty) {
        throw const DruckNichtsGewaehlt('Wähle mindestens eine Abteilung.');
      }
      return erfassungDruck(
        montag: montag,
        gruppen: gruppen,
        gedrucktAm: gedrucktAm,
        inhalt: ErfassungDruckInhalt(
          wochentage: tage,
          jeTag: wahl.eins(ErfassungDruckWahl.aufteilung) == 'tage',
          abteilungen: gewaehlteAbteilungen,
          plan: wahl.an(ErfassungDruckWahl.plan),
          leereZeilen: wahl.an(ErfassungDruckWahl.leer) ? 3 : 0,
          charge: wahl.an(ErfassungDruckWahl.charge),
          kuerzel: wahl.an(ErfassungDruckWahl.kuerzel),
          bemerkung: wahl.an(ErfassungDruckWahl.bemerkung),
        ),
      );
    },
  );
}

/// Was für eine Produktion geplant ist, in einer Zeile: „Plan: 1.200 kg
/// Rohware · 950 kg Fertigware · Start 06:00 · Notiz" — von der Notiz nur
/// die erste Zeile.
String erfassungPlanText(GeplanteProduktion p) {
  final t = p.task;
  final fertig = t.fertigMengeKg;
  final start = t.startZeit?.trim() ?? '';
  final notiz = (t.notizen ?? '').trim().split('\n').first.trim();
  return 'Plan: ${[
    '${Format.kg(t.mengeKg)} Rohware',
    if (fertig != null) '${Format.kg(fertig)} Fertigware',
    if (start.isNotEmpty) 'Start $start',
    if (notiz.isNotEmpty) notiz,
  ].join(' · ')}';
}

/// Montag bis Freitag ab [montag].
List<DateTime> _woche(DateTime montag) => [
      for (var i = 0; i < 5; i++) tagPlus(montag, i),
    ];

/// Die Wochentage mit Produktionen — gibt es keine, alle: Dann wird ein
/// leeres Blatt zum Eintragen gedruckt.
Set<int> _vorschlag(
  List<DateTime> woche,
  Map<DateTime, List<GeplanteProduktion>> gruppen,
) {
  final mit = {
    for (final t in woche)
      if ((gruppen[t] ?? const <GeplanteProduktion>[]).isNotEmpty)
        t.weekday,
  };
  return mit.isNotEmpty ? mit : {for (final t in woche) t.weekday};
}

String _produktionenText(int n) => switch (n) {
      0 => 'nichts zu erfassen',
      1 => '1 Produktion',
      _ => '$n Produktionen',
    };

Abteilung? _abteilung(String wert) {
  for (final a in Abteilung.values) {
    if (a.dbValue == wert) return a;
  }
  return null;
}

/// Höhe einer Zeile ohne Plan — Platz zum Schreiben (rund 8,5 mm).
const double _zeilenHoehe = 24;

/// Bis zu so vielen Zeilen bleibt ein Tag samt Leiste auf einer Seite: Eine
/// Zeile ist höchstens rund 32 Punkt hoch, die Seite im Querformat bietet
/// über 450.
const int _zusammenBis = 11;

/// Die Erfassungsliste beim Setzen.
class _Erfassungsliste {
  _Erfassungsliste({
    required this.gruppen,
    required this.inhalt,
    required this.tage,
    required this.kw,
    required this.gedruckt,
  }) : mitAbteilung = {
          for (final t in tage)
            for (final p in gruppen[t] ?? const <GeplanteProduktion>[])
              if (_gewaehlt(inhalt, p)) p.task.abteilung,
        }.length >
            1;

  final Map<DateTime, List<GeplanteProduktion>> gruppen;
  final ErfassungDruckInhalt inhalt;
  final List<DateTime> tage;
  final int kw;
  final String gedruckt;

  /// Stehen mehrere Abteilungen auf der Liste, nennt eine schmale Spalte
  /// die Abteilung jeder Produktion.
  final bool mitAbteilung;

  static bool _gewaehlt(ErfassungDruckInhalt inhalt, GeplanteProduktion p) {
    final abt = inhalt.abteilungen;
    return abt == null || abt.contains(p.task.abteilung);
  }

  /// Ein Blatt mit [tage] — bei einem einzigen Tag nennt der Kopf ihn, und
  /// die Leiste über dem Tag entfällt.
  DruckBlatt blatt(List<DateTime> tage) {
    final einTag = tage.length == 1;
    final zeile = einTag
        ? '${Format.datumLang(tage.single)} · KW $kw · Ist-Werte eintragen'
        : 'KW $kw · ${Format.tagKurz(tage.first)} - '
            '${Format.tagKurz(tage.last)}${tage.last.year} · '
            'Ist-Werte eintragen';
    final fuss = einTag
        ? 'Produktionserfassung ${Format.datum(tage.single)}'
        : 'Produktionserfassung KW $kw';
    return DruckBlatt(
      quer: true,
      rand: const pw.EdgeInsets.fromLTRB(24, 20, 24, 16),
      bauen: (r) {
        final teile = <pw.Widget>[
          for (final (i, t) in tage.indexed)
            ...tagTeile(t, r, leiste: !einTag, erster: i == 0),
        ];
        return DruckSeiten(
          kopf: (ctx) => druckKopf(
            titel: 'Produktionserfassung',
            zeile: zeile,
            gedruckt: gedruckt,
          ),
          fuss: (ctx) => druckFuss(fuss, r.seitenText(ctx)),
          inhalt: (ctx) =>
              teile.isEmpty ? [druckHinweis('Nichts zu erfassen.')] : teile,
        );
      },
    );
  }

  /// Ein Tag: Leiste und Tabelle — ohne Produktionen und ohne leere Zeilen
  /// nur ein Hinweis.
  List<pw.Widget> tagTeile(
    DateTime tag,
    DruckRahmen rahmen, {
    required bool leiste,
    required bool erster,
  }) {
    final liste = [
      for (final p in gruppen[tag] ?? const <GeplanteProduktion>[])
        if (_gewaehlt(inhalt, p)) p,
    ]..sort(_reihenfolge);
    final n = liste.length;
    final zusammen = n + inhalt.leereZeilen <= _zusammenBis;
    final teile = <pw.Widget>[
      if (leiste)
        druckLeiste(
          '${Format.wochentage[tag.weekday - 1]}, ${Format.datumKurz(tag)}',
          rechts: _produktionenText(n),
        ),
      if (n == 0 && inhalt.leereZeilen == 0)
        druckHinweis('Nichts zu erfassen.')
      else
        // Läuft der Tag über die Seite, nennt ihn die Kopfzeile der
        // Tabelle — sie steht auch auf der nächsten Seite.
        tabelle(liste, tag: leiste && !zusammen ? tag : null),
    ];
    return [
      if (!erster) pw.SizedBox(height: 10),
      ...druckGruppe(teile, zusammen: zusammen, rahmen: rahmen),
    ];
  }

  /// In der Reihenfolge des Plans: Abteilung, Reihenfolge im Board,
  /// Startzeit, Artikel.
  static int _reihenfolge(GeplanteProduktion a, GeplanteProduktion b) {
    int rang(GeplanteProduktion p) =>
        _abteilung(p.task.abteilung)?.index ?? Abteilung.values.length;
    final abt = rang(a).compareTo(rang(b));
    if (abt != 0) return abt;
    final sortierung = a.task.sortierung.compareTo(b.task.sortierung);
    if (sortierung != 0) return sortierung;
    final sa = a.task.startZeit;
    final sb = b.task.startZeit;
    if (sa != null && sb != null && sa != sb) return sa.compareTo(sb);
    if (sa != null && sb == null) return -1;
    if (sa == null && sb != null) return 1;
    return a.artikelName.compareTo(b.artikelName);
  }

  /// Die Tabelle eines Tages — mit [tag] nennt ihn die Kopfzeile.
  pw.Widget tabelle(List<GeplanteProduktion> liste, {DateTime? tag}) {
    // Die Spalten der Reihe nach — ohne die abgewählten rücken die
    // übrigen auf.
    var nr = 0;
    final breiten = <int, pw.TableColumnWidth>{
      if (mitAbteilung) nr++: const pw.FixedColumnWidth(34),
      nr++: const pw.FixedColumnWidth(52),
      nr++: const pw.FlexColumnWidth(),
      nr++: const pw.FixedColumnWidth(68),
      nr++: const pw.FixedColumnWidth(68),
      nr++: const pw.FixedColumnWidth(46),
      nr++: const pw.FixedColumnWidth(46),
      if (inhalt.charge) nr++: const pw.FixedColumnWidth(86),
      if (inhalt.kuerzel) nr++: const pw.FixedColumnWidth(46),
      if (inhalt.bemerkung) nr++: const pw.FixedColumnWidth(150),
    };
    // Was rechts vom Artikel steht, ist zum Eintragen da.
    final zumEintragen = breiten.length - (mitAbteilung ? 3 : 2);

    pw.TableRow zeile({
      pw.Widget? abteilung,
      pw.Widget? nummer,
      required pw.Widget artikel,
    }) =>
        pw.TableRow(
          children: [
            if (mitAbteilung) abteilung ?? pw.SizedBox(),
            nummer ?? pw.SizedBox(),
            pw.Container(
              constraints: const pw.BoxConstraints(minHeight: _zeilenHoehe),
              alignment: pw.Alignment.centerLeft,
              child: artikel,
            ),
            for (var i = 0; i < zumEintragen; i++) pw.SizedBox(),
          ],
        );

    return pw.Table(
      border: kDruckGitter,
      columnWidths: breiten,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        druckKopfzeile([
          if (mitAbteilung) druckKopfZelle('Abt.'),
          druckKopfZelle('Art.-Nr.'),
          druckKopfZelle(
            [
              if (tag != null) Format.tagKurz(tag),
              'Artikel',
              if (inhalt.plan) 'Plan',
            ].join(' · '),
          ),
          druckKopfZelle('Rohware kg', rechts: true),
          druckKopfZelle('Fertigware kg', rechts: true),
          druckKopfZelle('Start'),
          druckKopfZelle('Ende'),
          if (inhalt.charge) druckKopfZelle('Charge'),
          if (inhalt.kuerzel) druckKopfZelle('Kürzel'),
          if (inhalt.bemerkung) druckKopfZelle('Bemerkung'),
        ]),
        for (final p in liste)
          zeile(
            abteilung: druckZelle(
              _abteilung(p.task.abteilung)?.kurzcode ?? '',
              fett: true,
              groesse: 8.5,
            ),
            nummer: druckZelle(
              p.artikelNummer.trim().isEmpty ? '-' : p.artikelNummer.trim(),
              fett: true,
            ),
            artikel: druckZelleMitZeile(
              p.artikelName,
              inhalt.plan ? erfassungPlanText(p) : null,
              groesse: 9.5,
            ),
          ),
        for (var i = 0; i < inhalt.leereZeilen; i++)
          zeile(artikel: pw.SizedBox(height: _zeilenHoehe)),
      ],
    );
  }

}
