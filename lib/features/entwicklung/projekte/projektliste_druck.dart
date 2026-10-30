import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/database/database.dart'
    show EntwicklungsProjekt, Gesamtprojekt;
import '../../../core/druck/druck_bausteine.dart';
import '../../../core/druck/druck_optionen.dart';
import '../../../core/druck/druck_satz.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/pdf_text.dart';
import 'faellig.dart';
import 'gesamtprojekt_modell.dart';
import 'projekt_checkliste.dart' show ProjektCheckStand, checkAufgabe;
import 'projekt_modell.dart';

// Die Projektliste auf Papier — wie auf dem Schirm: Gesamtprojekte mit
// ihren Mustern, je Projekt Artikelnummer, Kunde, Status, Checkliste und
// was als Nächstes zu tun ist. Gefiltert nach Status und Suche, geordnet
// wie die Liste, nach Name oder je Kunde.

/// Was die Projektliste zum Drucken braucht.
class ProjektlisteDaten {
  const ProjektlisteDaten({
    required this.projekte,
    this.gesamtprojekte = const [],
    this.checklisten = const {},
    this.offen = const {},
  });

  final List<EntwicklungsProjekt> projekte;
  final List<Gesamtprojekt> gesamtprojekte;

  /// Die Checkliste je Projekt (ID) — fehlt eine, bleibt die Spalte leer.
  final Map<String, ProjektCheckStand> checklisten;

  /// Die offenen Einträge im Verlauf je Projekt (ID).
  final Map<String, OffeneEintraege> offen;
}

/// Wie die Projekte geordnet sind.
enum ProjektReihenfolge {
  /// Das zuletzt bewegte zuerst — wie in der Liste.
  zuletzt,

  /// Nach dem Namen.
  name,

  /// Je Kunde ein Abschnitt, darin das zuletzt bewegte zuerst.
  kunde,
}

/// Schlüssel der Wahl im Druckfenster.
abstract final class ProjektlisteWahl {
  static const filter = 'filter';
  static const suche = 'suche';
  static const reihenfolge = 'reihenfolge';
  static const muster = 'muster';
  static const details = 'details';
  static const idee = 'idee';

  /// Der Wert für „alle Projekte" in [filter].
  static const alle = 'alle';
}

/// Was auf die Liste kommt — die Wahl im Druckfenster.
class ProjektlisteInhalt {
  const ProjektlisteInhalt({
    this.filter = ProjektFilter.aktiv,
    this.suche = '',
    this.reihenfolge = ProjektReihenfolge.zuletzt,
    this.muster = true,
    this.details = true,
    this.idee = false,
  });

  /// null: alle Projekte, auch ruhende.
  final ProjektFilter? filter;

  /// Nur, was diese Suche trifft — leer: alles.
  final String suche;

  final ProjektReihenfolge reihenfolge;

  /// Die Muster der Gesamtprojekte einzeln unter ihnen.
  final bool muster;

  /// Was als Nächstes zu tun ist und was im Verlauf offen ist.
  final bool details;

  /// Die Produktidee.
  final bool idee;
}

/// „Aktiv", „Archiv" — oder „Alle Projekte".
String projektFilterText(ProjektFilter? f) => f?.label ?? 'Alle Projekte';

/// Die Projektliste zum Drucken.
DruckDokument projektlisteDruck(
  ProjektlisteDaten daten, {
  ProjektlisteInhalt inhalt = const ProjektlisteInhalt(),
  DateTime? gedrucktAm,
}) {
  final gedruckt = gedrucktAm ?? DateTime.now();
  final liste = _Liste(daten, inhalt, druckGedruckt(gedruckt));
  return DruckDokument(
    titel: 'Projekte ${projektFilterText(inhalt.filter)}',
    dateiname: druckDateiname(
      'Projekte ${projektFilterText(inhalt.filter)} ${druckIsoDatum(gedruckt)}',
    ),
    blaetter: [liste.blatt()],
  );
}

/// Die Projektliste für das Druckfenster. Vorgewählt ist, was die Liste
/// zeigt: [filter] und — wenn gesetzt — [suche].
DruckAuftrag projektlisteDruckAuftrag(
  ProjektlisteDaten daten, {
  ProjektFilter? filter = ProjektFilter.aktiv,
  String suche = '',
  DateTime? gedrucktAm,
}) {
  final aktiv = [
    for (final p in daten.projekte)
      if (p.deletedAt == null) ProjektStatus.aus(p.status),
  ];
  String anzahl(int n) => n == 1 ? '1 Projekt' : '$n Projekte';
  final q = suche.trim();
  final mitGesamt = daten.gesamtprojekte.any((g) => g.deletedAt == null);
  return DruckAuftrag(
    art: 'projektliste',
    titel: 'Projektliste drucken',
    untertitel: [
      projektFilterText(filter),
      if (q.isNotEmpty) 'Suche „$q“',
    ].join(' · '),
    optionen: [
      DruckWahlEins(
        schluessel: ProjektlisteWahl.filter,
        titel: 'Projekte',
        werte: [
          for (final f in ProjektFilter.values)
            DruckWert(
              f.name,
              f.label,
              hinweis: anzahl(aktiv.where(f.passt).length),
            ),
          DruckWert(
            ProjektlisteWahl.alle,
            'Alle Projekte',
            hinweis: 'Auch ruhende — ${anzahl(aktiv.length)}',
          ),
        ],
        standard: filter?.name ?? ProjektlisteWahl.alle,
        merken: false,
      ),
      if (q.isNotEmpty)
        DruckSchalter(
          schluessel: ProjektlisteWahl.suche,
          titel: 'Nur Treffer der Suche „$q“',
          merken: false,
        ),
      const DruckWahlEins(
        schluessel: ProjektlisteWahl.reihenfolge,
        titel: 'Reihenfolge',
        werte: [
          DruckWert(
            'zuletzt',
            'Zuletzt bewegt zuerst',
            hinweis: 'Wie in der Liste',
          ),
          DruckWert('name', 'Nach Name'),
          DruckWert('kunde', 'Nach Kunde', hinweis: 'Je Kunde ein Abschnitt'),
        ],
        standard: 'zuletzt',
      ),
      if (mitGesamt)
        const DruckSchalter(
          schluessel: ProjektlisteWahl.muster,
          titel: 'Muster der Gesamtprojekte einzeln',
          hinweis: 'Sonst nur, wie die Muster zusammen stehen',
        ),
      const DruckSchalter(
        schluessel: ProjektlisteWahl.details,
        titel: 'Als Nächstes und Offenes',
        hinweis: 'Nächster Punkt der Checkliste, offene Einträge im Verlauf',
        gruppe: 'Je Projekt',
      ),
      const DruckSchalter(
        schluessel: ProjektlisteWahl.idee,
        titel: 'Produktidee',
        standard: false,
        gruppe: 'Je Projekt',
      ),
    ],
    bauen: (wahl) {
      final f = wahl.eins(ProjektlisteWahl.filter);
      return projektlisteDruck(
        daten,
        gedrucktAm: gedrucktAm,
        inhalt: ProjektlisteInhalt(
          filter: ProjektFilter.values
              .where((x) => x.name == f)
              .firstOrNull,
          suche: q.isNotEmpty && wahl.an(ProjektlisteWahl.suche) ? q : '',
          reihenfolge: ProjektReihenfolge.values.firstWhere(
            (r) => r.name == wahl.eins(ProjektlisteWahl.reihenfolge),
            orElse: () => ProjektReihenfolge.zuletzt,
          ),
          muster: !mitGesamt || wahl.an(ProjektlisteWahl.muster),
          details: wahl.an(ProjektlisteWahl.details),
          idee: wahl.an(ProjektlisteWahl.idee),
        ),
      );
    },
  );
}

/// Die Farbe des Punkts vor dem Status — wie die Marke auf dem Schirm.
PdfColor _statusFarbe(ProjektStatus s) => switch (s) {
      ProjektStatus.entwicklung => const PdfColor.fromInt(0xFF1565C0),
      ProjektStatus.validierung => const PdfColor.fromInt(0xFFEF6C00),
      ProjektStatus.produktion => const PdfColor.fromInt(0xFF2E7D32),
      ProjektStatus.eingestellt ||
      ProjektStatus.archiviert =>
        PdfColors.grey500,
    };

const PdfColor _rot = PdfColor.fromInt(0xFFC62828);

/// Der Name, nach dem geordnet wird.
String _name(ListenPunkt p) => switch (p) {
      EinzelProjekt(:final projekt) => projekt.name,
      GesamtGruppe(:final gesamtprojekt) => gesamtprojekt.name,
    };

/// Der Kunde eines Eintrags — leer: keiner.
String _kunde(ListenPunkt p) => switch (p) {
      EinzelProjekt(:final projekt) => projekt.kunde?.trim() ?? '',
      GesamtGruppe(:final gesamtprojekt) => gesamtprojekt.kunde?.trim() ?? '',
    };

class _Liste {
  _Liste(this.daten, this.inhalt, this.gedruckt)
      : punkte = projektListe(
          projekte: daten.projekte,
          gesamtprojekte: daten.gesamtprojekte,
          passt: inhalt.filter?.passt ?? (_) => true,
          leerPasst: inhalt.filter == null ||
              inhalt.filter == ProjektFilter.aktiv,
          suche: inhalt.suche,
        );

  final ProjektlisteDaten daten;
  final ProjektlisteInhalt inhalt;
  final String gedruckt;
  final List<ListenPunkt> punkte;

  /// Die gezeigten Projekte — für sich und als Muster.
  List<EntwicklungsProjekt> get projekte => [
        for (final p in punkte)
          ...switch (p) {
            EinzelProjekt(:final projekt) => [projekt],
            GesamtGruppe(:final sichtbar) => sichtbar,
          },
      ];

  /// Die Abschnitte: je Kunde einer — sonst einer ohne Titel. Ohne
  /// Projekte keiner.
  List<({String? titel, List<ListenPunkt> punkte})> abschnitte() {
    if (punkte.isEmpty) return const [];
    int nachName(ListenPunkt a, ListenPunkt b) =>
        _name(a).toLowerCase().compareTo(_name(b).toLowerCase());
    switch (inhalt.reihenfolge) {
      case ProjektReihenfolge.zuletzt:
        return [(titel: null, punkte: punkte)];
      case ProjektReihenfolge.name:
        return [(titel: null, punkte: [...punkte]..sort(nachName))];
      case ProjektReihenfolge.kunde:
        final jeKunde = <String, List<ListenPunkt>>{};
        for (final p in punkte) {
          (jeKunde[_kunde(p)] ??= []).add(p);
        }
        // Alphabetisch, ohne Kunde zuletzt.
        final kunden = jeKunde.keys.toList()
          ..sort((a, b) {
            if (a.isEmpty != b.isEmpty) return a.isEmpty ? 1 : -1;
            return a.toLowerCase().compareTo(b.toLowerCase());
          });
        return [
          for (final k in kunden)
            (titel: k.isEmpty ? 'Ohne Kunde' : k, punkte: jeKunde[k]!),
        ];
    }
  }

  DruckBlatt blatt() {
    final n = projekte.length;
    final zeile = [
      projektFilterText(inhalt.filter),
      if (inhalt.suche.trim().isNotEmpty) 'Suche „${inhalt.suche.trim()}“',
      n == 1 ? '1 Projekt' : '$n Projekte',
    ].join(' · ');
    return DruckBlatt(
      quer: true,
      bauen: (r) {
        final teile = <pw.Widget>[
          ...kennzahlen(),
          if (punkte.isEmpty)
            druckHinweis(
              daten.projekte.isEmpty
                  ? 'Noch keine Projekte.'
                  : 'Keine Treffer.',
            ),
          for (final a in abschnitte())
            if (a.titel case final titel?)
              ...druckGruppe(
                [
                  pw.SizedBox(height: 8),
                  druckLeiste(titel, rechts: _anzahlText(a.punkte)),
                  tabelle(a.punkte),
                ],
                zusammen: false,
                rahmen: r,
                frei: 90,
              )
            else
              tabelle(a.punkte),
        ];
        return DruckSeiten(
          kopf: (ctx) => druckKopf(
            titel: 'Projekte',
            zeile: zeile,
            gedruckt: gedruckt,
          ),
          fuss: (ctx) => druckFuss(
            'Projektliste · ${projektFilterText(inhalt.filter)}',
            r.seitenText(ctx),
          ),
          inhalt: (ctx) => teile,
        );
      },
    );
  }

  /// „3 Projekte" — die Muster eines Gesamtprojekts einzeln gezählt.
  String _anzahlText(List<ListenPunkt> liste) {
    final n = liste.fold<int>(
      0,
      (s, p) => s + (p is GesamtGruppe ? p.sichtbar.length : 1),
    );
    return n == 1 ? '1 Projekt' : '$n Projekte';
  }

  /// Wie viele Projekte in welchem Status, wie viele mit Überfälligem.
  List<pw.Widget> kennzahlen() {
    final liste = projekte;
    if (liste.isEmpty) return const [];
    final status = [for (final p in liste) ProjektStatus.aus(p.status)];
    final ueberfaellig = liste
        .where((p) => (daten.offen[p.id]?.ueberfaellig ?? 0) > 0)
        .length;
    final gesamt = punkte.whereType<GesamtGruppe>().length;
    return [
      druckKennzahlen([
        for (final s in ProjektStatus.values)
          if (status.where((x) => x == s).length case final n when n > 0)
            DruckKennzahl('$n', s.label, betont: !s.ruht),
        if (gesamt > 0)
          DruckKennzahl(
            '$gesamt',
            gesamt == 1 ? 'Gesamtprojekt' : 'Gesamtprojekte',
          ),
        if (ueberfaellig > 0)
          DruckKennzahl('$ueberfaellig', 'mit Überfälligem', betont: true),
      ]),
    ];
  }

  /// Die Tabelle der Einträge [liste]: je Gesamtprojekt seine Zeile und
  /// die Muster darunter.
  pw.Widget tabelle(List<ListenPunkt> liste) {
    final zeilen = <pw.TableRow>[];
    for (final p in liste) {
      switch (p) {
        case EinzelProjekt(:final projekt):
          zeilen.add(projektZeile(projekt));
        case GesamtGruppe():
          zeilen.add(gesamtZeile(p));
          if (inhalt.muster) {
            for (final m in p.sichtbar) {
              zeilen.add(projektZeile(m, muster: true));
            }
          }
      }
    }
    return pw.Table(
      border: kDruckGitter,
      columnWidths: <pw.TableColumnWidth>[
        const pw.FixedColumnWidth(66),
        const pw.FlexColumnWidth(),
        if (mitKunde) const pw.FixedColumnWidth(140),
        const pw.FixedColumnWidth(104),
        const pw.FixedColumnWidth(58),
        const pw.FixedColumnWidth(60),
      ].asMap(),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        druckKopfzeile([
          druckKopfZelle('Art.-Nr.'),
          druckKopfZelle('Projekt'),
          if (mitKunde) druckKopfZelle('Kunde'),
          druckKopfZelle('Status'),
          druckKopfZelle('Checkliste', rechts: true),
          druckKopfZelle('Geändert', rechts: true),
        ]),
        ...zeilen,
      ],
    );
  }

  /// Nach Kunde steht der Kunde über dem Abschnitt — nicht in jeder Zeile.
  bool get mitKunde => inhalt.reihenfolge != ProjektReihenfolge.kunde;

  /// Der Name, darunter, was als Nächstes zu tun und was offen ist — rot,
  /// wenn etwas überfällig ist —, darunter die Produktidee.
  pw.Widget projektZelle(
    String name, {
    String details = '',
    bool rot = false,
    String idee = '',
    bool fett = true,
    double einzug = 0,
  }) {
    const klein = 7.5;
    return pw.Padding(
      padding: pw.EdgeInsets.fromLTRB(4 + einzug, 3, 4, 3),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            pdfText(name),
            maxLines: 1,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: fett ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
          if (details.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 1),
              child: pw.Text(
                pdfText(details),
                maxLines: 1,
                style: pw.TextStyle(
                  fontSize: klein,
                  color: rot ? _rot : kDruckGrau,
                  fontWeight: rot ? pw.FontWeight.bold : pw.FontWeight.normal,
                ),
              ),
            ),
          if (idee.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 1),
              child: pw.Text(
                pdfText(idee),
                maxLines: 2,
                style: pw.TextStyle(
                  fontSize: klein,
                  color: kDruckGrau,
                  fontStyle: pw.FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Die Zeile eines Projekts — ein Muster eingerückt und ohne Kunden, der
  /// steht beim Gesamtprojekt.
  pw.TableRow projektZeile(EntwicklungsProjekt p, {bool muster = false}) {
    final status = ProjektStatus.aus(p.status);
    final ruht = status.ruht;
    final check = daten.checklisten[p.id];
    final naechster = ruht ? null : check?.naechster;
    final o = ruht ? null : daten.offen[p.id];
    final details = inhalt.details
        ? [
            if (naechster != null) 'Als Nächstes: ${checkAufgabe(naechster)}',
            if (o != null && o.offen > 0) offeneEintraegeText(o),
          ].join(' · ')
        : '';
    final nummer = p.artikelnummer?.trim() ?? '';
    return pw.TableRow(
      children: [
        druckZelle(nummer.isEmpty ? '-' : nummer, groesse: 8.5),
        projektZelle(
          p.name,
          details: details,
          rot: inhalt.details && (o?.ueberfaellig ?? 0) > 0,
          idee: inhalt.idee ? (p.produktidee?.trim() ?? '') : '',
          fett: !muster,
          einzug: muster ? 12 : 0,
        ),
        if (mitKunde)
          druckZelle(muster ? '' : (p.kunde?.trim() ?? ''), groesse: 8.5),
        druckZelleMitPunkt(status.label, _statusFarbe(status), zeilen: 1),
        druckZelle(check?.text ?? '', rechts: true, groesse: 8.5),
        druckZelle(Format.datum(p.updatedAt), rechts: true, groesse: 8.5),
      ],
    );
  }

  /// Die Zeile eines Gesamtprojekts: wie seine Muster stehen.
  pw.TableRow gesamtZeile(GesamtGruppe gruppe) {
    final g = gruppe.gesamtprojekt;
    final verborgen = gruppe.muster.length - gruppe.sichtbar.length;
    final details = [
      musterZusammenfassung([
        for (final m in gruppe.muster) ProjektStatus.aus(m.status),
      ]),
      if (verborgen > 0 && gruppe.sichtbar.isNotEmpty)
        '$verborgen hier nicht gezeigt',
    ].join(' · ');
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: kDruckZeilenFlaeche),
      children: [
        druckZelle(''),
        projektZelle(g.name, details: details),
        if (mitKunde) druckZelle(g.kunde?.trim() ?? '', groesse: 8.5),
        druckZelle('Gesamtprojekt', groesse: 8.5),
        druckZelle(''),
        druckZelle(Format.datum(gruppe.zuletzt), rechts: true, groesse: 8.5),
      ],
    );
  }
}
