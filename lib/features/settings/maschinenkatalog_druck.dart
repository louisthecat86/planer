import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart'
    show Machine, MachineParameterDef, ParameterGrenzenData;
import '../../core/druck/druck_bausteine.dart';
import '../../core/druck/druck_optionen.dart';
import '../../core/druck/druck_satz.dart';
import '../../core/utils/zeit.dart';
import 'maschinen_druck_daten.dart';

// Der Maschinen-Katalog auf Papier: je Abteilung ihre Anlagen — als
// Übersicht eine Zeile je Anlage, oder als Steckbriefe mit allen
// Parametern, ihren Grenzwerten und den Artikeln, die die Anlage nutzen.

/// Wie die Anlagen auf dem Blatt stehen.
enum KatalogDarstellung {
  /// Eine Zeile je Anlage.
  uebersicht,

  /// Je Anlage ihre Parameter mit Einheit und Grenzwerten.
  steckbriefe,
}

/// Schlüssel der Wahl im Druckfenster.
abstract final class KatalogWahl {
  static const darstellung = 'darstellung';
  static const abteilungen = 'abteilungen';
  static const artikel = 'artikel';
  static const abteilungSeite = 'abteilungSeite';
  static const anlageSeite = 'anlageSeite';
}

/// Was auf das Blatt kommt — die Wahl im Druckfenster.
class KatalogInhalt {
  const KatalogInhalt({
    this.darstellung = KatalogDarstellung.uebersicht,
    this.abteilungen,
    this.artikel = true,
    this.neueSeite = false,
  });

  final KatalogDarstellung darstellung;

  /// Nur diese Abteilungen (dbValues) — null: alle.
  final Set<String>? abteilungen;

  /// Die Artikel der Anlage: in der Übersicht ihre Zahl, im Steckbrief mit
  /// Nummer und Namen.
  final bool artikel;

  /// In der Übersicht jede Abteilung, bei Steckbriefen jede Anlage auf
  /// einer neuen Seite.
  final bool neueSeite;
}

String _maschinen(int n) => n == 1 ? '1 Maschine' : '$n Maschinen';

/// Die Abteilungen mit Anlagen, in der Reihenfolge der App — Anlagen mit
/// unbekannter Abteilung fallen weg.
List<(Abteilung, List<Machine>)> _jeAbteilung(MaschinenDruckDaten d) => [
      for (final a in Abteilung.values)
        if ([
          for (final m in d.maschinen)
            if (m.abteilung == a.dbValue) m,
        ]
            case final liste when liste.isNotEmpty)
          (a, liste),
    ];

/// Der Maschinen-Katalog zum Drucken.
DruckDokument maschinenkatalogDruck(
  MaschinenDruckDaten daten, {
  KatalogInhalt inhalt = const KatalogInhalt(),
  DateTime? gedrucktAm,
}) {
  final gedruckt = gedrucktAm ?? DateTime.now();
  final katalog = _Katalog(daten, inhalt, druckGedruckt(gedruckt));
  final titel = inhalt.darstellung == KatalogDarstellung.steckbriefe
      ? 'Maschinen-Steckbriefe'
      : 'Maschinen-Katalog';
  return DruckDokument(
    titel: titel,
    dateiname: druckDateiname('$titel ${druckIsoDatum(gedruckt)}'),
    blaetter: [katalog.blatt()],
  );
}

/// Der Maschinen-Katalog für das Druckfenster.
DruckAuftrag maschinenkatalogDruckAuftrag(
  MaschinenDruckDaten daten, {
  DateTime? gedrucktAm,
}) {
  final gruppen = _jeAbteilung(daten);
  final anzahl = gruppen.fold<int>(0, (s, g) => s + g.$2.length);
  return DruckAuftrag(
    art: 'maschinenkatalog',
    titel: 'Maschinen-Katalog drucken',
    untertitel: [
      _maschinen(anzahl),
      gruppen.length == 1 ? '1 Abteilung' : '${gruppen.length} Abteilungen',
    ].join(' · '),
    optionen: [
      const DruckWahlEins(
        schluessel: KatalogWahl.darstellung,
        titel: 'Darstellung',
        werte: [
          DruckWert(
            'uebersicht',
            'Übersicht',
            hinweis: 'Eine Zeile je Anlage',
          ),
          DruckWert(
            'steckbriefe',
            'Steckbriefe',
            hinweis: 'Je Anlage ihre Parameter mit Einheit und Grenzwerten',
          ),
        ],
        standard: 'uebersicht',
      ),
      if (gruppen.length > 1)
        DruckWahlMehrere(
          schluessel: KatalogWahl.abteilungen,
          titel: 'Abteilungen',
          werte: [
            for (final (a, liste) in gruppen)
              DruckWert(
                a.dbValue,
                a.anzeigeName,
                hinweis: _maschinen(liste.length),
                farbe: a.farbwert,
                kuerzel: a.kurzcode,
              ),
          ],
          standard: {for (final (a, _) in gruppen) a.dbValue},
          merken: false,
        ),
      const DruckSchalter(
        schluessel: KatalogWahl.artikel,
        titel: 'Artikel der Anlage',
        hinweis: 'Übersicht: wie viele · Steckbriefe: welche',
        gruppe: 'Auf dem Blatt',
      ),
      DruckSchalter(
        schluessel: KatalogWahl.abteilungSeite,
        titel: 'Jede Abteilung auf einer neuen Seite',
        standard: false,
        gruppe: 'Auf dem Blatt',
        sichtbar: (w) => w.eins(KatalogWahl.darstellung) != 'steckbriefe',
      ),
      DruckSchalter(
        schluessel: KatalogWahl.anlageSeite,
        titel: 'Jede Anlage auf einer neuen Seite',
        hinweis: 'Zum Aushängen an der Anlage',
        standard: false,
        gruppe: 'Auf dem Blatt',
        sichtbar: (w) => w.eins(KatalogWahl.darstellung) == 'steckbriefe',
      ),
    ],
    bauen: (wahl) {
      final darstellung = wahl.eins(KatalogWahl.darstellung) == 'steckbriefe'
          ? KatalogDarstellung.steckbriefe
          : KatalogDarstellung.uebersicht;
      Set<String>? abteilungen;
      if (gruppen.length > 1) {
        abteilungen = wahl.mehrere(KatalogWahl.abteilungen);
        if (abteilungen.isEmpty) {
          throw const DruckNichtsGewaehlt('Wähle mindestens eine Abteilung.');
        }
      }
      return maschinenkatalogDruck(
        daten,
        gedrucktAm: gedrucktAm,
        inhalt: KatalogInhalt(
          darstellung: darstellung,
          abteilungen: abteilungen,
          artikel: wahl.an(KatalogWahl.artikel),
          neueSeite: darstellung == KatalogDarstellung.steckbriefe
              ? wahl.an(KatalogWahl.anlageSeite)
              : wahl.an(KatalogWahl.abteilungSeite),
        ),
      );
    },
  );
}

class _Katalog {
  _Katalog(this.daten, this.inhalt, this.gedruckt)
      : grenzen = daten.grenzenJeKontext;

  final MaschinenDruckDaten daten;
  final KatalogInhalt inhalt;
  final String gedruckt;
  final Map<String, List<ParameterGrenzenData>> grenzen;

  bool get steckbriefe => inhalt.darstellung == KatalogDarstellung.steckbriefe;

  /// Die gewählten Abteilungen mit ihren Anlagen.
  List<(Abteilung, List<Machine>)> get gruppen => [
        for (final g in _jeAbteilung(daten))
          if (inhalt.abteilungen?.contains(g.$1.dbValue) ?? true) g,
      ];

  List<MachineParameterDef> steckbrief(Machine m) =>
      daten.steckbriefe[m.id] ?? const [];

  List<MaschinenArtikel> artikel(Machine m) => daten.artikel[m.id] ?? const [];

  DruckBlatt blatt() {
    final teile = gruppen;
    final maschinen = [for (final (_, liste) in teile) ...liste];
    final zeile = [
      _maschinen(maschinen.length),
      if (inhalt.abteilungen != null)
        [for (final (a, _) in teile) a.anzeigeName].join(', ')
      else
        teile.length == 1 ? '1 Abteilung' : '${teile.length} Abteilungen',
    ].join(' · ');
    final titel = steckbriefe ? 'Maschinen-Steckbriefe' : 'Maschinen-Katalog';
    return DruckBlatt(
      bauen: (r) {
        final inhaltTeile = <pw.Widget>[
          // Steckbriefe zum Aushängen stehen je Anlage für sich — ohne die
          // Kennzahlen des ganzen Katalogs.
          if (!(steckbriefe && inhalt.neueSeite && r.umbrueche))
            ...kennzahlen(maschinen),
          if (teile.isEmpty)
            druckHinweis(
              daten.maschinen.isEmpty
                  ? 'Noch keine Maschinen angelegt.'
                  : 'Keine Maschinen.',
            ),
          for (final (i, (a, liste)) in teile.indexed)
            ...abteilung(r, a, liste, erste: i == 0),
        ];
        return DruckSeiten(
          kopf: (ctx) => druckKopf(
            titel: titel,
            zeile: zeile,
            gedruckt: gedruckt,
          ),
          fuss: (ctx) => druckFuss(titel, r.seitenText(ctx)),
          inhalt: (ctx) => inhaltTeile,
        );
      },
    );
  }

  /// Wie viele Anlagen, wie viele mit eigener Planungsspur, wie viele
  /// Parameter und Grenzwerte — und wie viele kein Artikel nutzt.
  List<pw.Widget> kennzahlen(List<Machine> maschinen) {
    if (maschinen.isEmpty) return const [];
    final spuren = maschinen.where((m) => m.istPlanungsressource).length;
    final parameter =
        maschinen.fold<int>(0, (s, m) => s + steckbrief(m).length);
    final grenzwerte =
        maschinen.fold<int>(0, (s, m) => s + (grenzen[m.name]?.length ?? 0));
    final ungenutzt = maschinen.where((m) => artikel(m).isEmpty).length;
    return [
      druckKennzahlen([
        DruckKennzahl(_maschinen(maschinen.length), 'im Katalog', betont: true),
        DruckKennzahl('$spuren', 'mit eigener Planungsspur'),
        DruckKennzahl('$parameter', 'Parameter in Steckbriefen'),
        DruckKennzahl('$grenzwerte', 'Grenzwerte'),
        if (inhalt.artikel)
          DruckKennzahl('$ungenutzt', 'von keinem Artikel genutzt'),
      ]),
    ];
  }

  /// Eine Abteilung: Leiste, darunter die Übersicht oder die Steckbriefe.
  List<pw.Widget> abteilung(
    DruckRahmen r,
    Abteilung a,
    List<Machine> liste, {
    required bool erste,
  }) {
    final spuren = liste.where((m) => m.istPlanungsressource).length;
    final leiste = druckLeiste(
      a.anzeigeName,
      rechts: [
        _maschinen(liste.length),
        if (spuren > 0)
          spuren == 1 ? '1 Planungsspur' : '$spuren Planungsspuren',
      ].join(' · '),
      farbe: a.farbwert,
    );
    final neueSeite = !erste && inhalt.neueSeite && !steckbriefe && r.umbrueche;
    if (!steckbriefe) {
      return [
        if (neueSeite) pw.NewPage(),
        ...druckGruppe(
          [pw.SizedBox(height: erste ? 0 : 8), leiste, uebersicht(a, liste)],
          zusammen: false,
          rahmen: r,
          frei: 100,
        ),
      ];
    }
    return [
      for (final (i, m) in liste.indexed) ...[
        if ((!erste || i > 0) && inhalt.neueSeite && r.umbrueche) pw.NewPage(),
        ...druckGruppe(
          [
            if (i == 0 || (inhalt.neueSeite && r.umbrueche)) ...[
              pw.SizedBox(height: erste && i == 0 ? 0 : 8),
              druckLeiste(
                a.anzeigeName,
                rechts: i == 0 ? _maschinen(liste.length) : null,
                farbe: a.farbwert,
              ),
            ],
            ...steckbriefBlock(a, m),
          ],
          zusammen: blockHoehe(m) <= r.hoehe - 60,
          rahmen: r,
          frei: 120,
        ),
      ],
    ];
  }

  /// Geschätzte Höhe eines Steckbriefs — lieber zu hoch als zu niedrig.
  double blockHoehe(Machine m) {
    final zeilen = steckbriefZeilen(m).length;
    final n = artikel(m).length;
    return 110 + (zeilen + 1) * 20 + (inhalt.artikel ? 14.0 * (1 + n ~/ 6) : 0);
  }

  // ── Übersicht ─────────────────────────────────────────────────────────

  pw.Widget uebersicht(Abteilung a, List<Machine> liste) => pw.Table(
        border: kDruckGitter,
        columnWidths: <pw.TableColumnWidth>[
          const pw.FlexColumnWidth(),
          const pw.FixedColumnWidth(76),
          const pw.FlexColumnWidth(1.3),
          const pw.FixedColumnWidth(44),
          if (inhalt.artikel) const pw.FixedColumnWidth(42),
        ].asMap(),
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
        children: [
          druckKopfzeile([
            druckKopfZelle('Anlage'),
            druckKopfZelle('Planungsspur', rechts: true),
            druckKopfZelle('Steckbrief'),
            druckKopfZelle('Grenzen', rechts: true),
            if (inhalt.artikel) druckKopfZelle('Artikel', rechts: true),
          ]),
          for (final m in liste) uebersichtZeile(m),
        ],
      );

  pw.TableRow uebersichtZeile(Machine m) {
    final eignung = (m.eignungHinweis ?? '').trim();
    final parameter = steckbrief(m);
    final g = grenzen[m.name]?.length ?? 0;
    final n = artikel(m).length;
    return pw.TableRow(
      children: [
        druckZelleMitZeile(
          m.name,
          eignung,
          fett: true,
          zeilenOben: 2,
          zeilenUnten: 2,
          groesse: 9,
        ),
        druckZelle(
          m.istPlanungsressource
              ? '${Zeit.kurz(m.kapazitaetMinutenProTag)}/Tag'
              : '-',
          rechts: true,
          groesse: 8.5,
          farbe: m.istPlanungsressource ? PdfColors.black : kDruckGrau,
        ),
        druckZelle(
          parameter.isEmpty
              ? '-'
              : [for (final p in parameter) _mitEinheit(p)].join(', '),
          zeilen: 4,
          groesse: 8,
          farbe: parameter.isEmpty ? kDruckGrau : PdfColors.black,
        ),
        druckZelle(
          g == 0 ? '-' : '$g',
          rechts: true,
          groesse: 8.5,
          farbe: g == 0 ? kDruckGrau : PdfColors.black,
        ),
        if (inhalt.artikel)
          druckZelle(
            n == 0 ? '-' : '$n',
            rechts: true,
            groesse: 8.5,
            farbe: n == 0 ? kDruckGrau : PdfColors.black,
          ),
      ],
    );
  }

  // ── Steckbriefe ───────────────────────────────────────────────────────

  /// Die Zeilen eines Steckbriefs: die Parameter in der Reihenfolge der
  /// Maske mit ihren Grenzen, danach Grenzen zu Parametern, die nicht (mehr)
  /// im Steckbrief stehen.
  List<(String, String, ParameterGrenzenData?, bool)> steckbriefZeilen(
    Machine m,
  ) {
    final jeName = {
      for (final g in grenzen[m.name] ?? const <ParameterGrenzenData>[])
        g.parameterName: g,
    };
    final parameter = steckbrief(m);
    final namen = {for (final p in parameter) p.parameterName};
    return [
      for (final p in parameter)
        (
          p.parameterName,
          p.einheit?.trim() ?? '',
          jeName[p.parameterName],
          true
        ),
      for (final g in grenzen[m.name] ?? const <ParameterGrenzenData>[])
        if (!namen.contains(g.parameterName)) (g.parameterName, '', g, false),
    ];
  }

  List<pw.Widget> steckbriefBlock(Abteilung a, Machine m) {
    final eignung = (m.eignungHinweis ?? '').trim();
    final typisch = (m.typischeParameter ?? '').trim();
    final info = [
      if (eignung.isNotEmpty) eignung,
      if (m.istPlanungsressource)
        'Eigene Planungsspur, ${Zeit.kurz(m.kapazitaetMinutenProTag)} am Tag',
    ].join(' · ');
    final zeilen = steckbriefZeilen(m);
    final liste = artikel(m);
    return [
      druckZwischentitel(m.name, farbe: a.farbwert),
      if (info.isNotEmpty) druckHinweis(info, zeilen: 2),
      if (typisch.isNotEmpty) druckHinweis('Typisch: $typisch', zeilen: 3),
      if (zeilen.isEmpty)
        druckHinweis('Kein Steckbrief — für die Anlage sind keine Parameter '
            'angelegt.')
      else
        steckbriefTabelle(zeilen),
      if (inhalt.artikel)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 3),
          child: druckHinweis(
            liste.isEmpty
                ? 'Von keinem Artikel genutzt.'
                : '${liste.length == 1 ? 'Genutzt von 1 Artikel' : 'Genutzt '
                    'von ${liste.length} Artikeln'}: ${[
                    for (final x in liste) '${x.nummer} ${x.bezeichnung}',
                  ].join(', ')}',
            zeilen: 8,
          ),
        ),
    ];
  }

  pw.Widget steckbriefTabelle(
    List<(String, String, ParameterGrenzenData?, bool)> zeilen,
  ) {
    final mitNotiz = zeilen.any((z) => (z.$3?.notizen ?? '').trim().isNotEmpty);
    return pw.Table(
      border: kDruckGitter,
      columnWidths: <pw.TableColumnWidth>[
        const pw.FlexColumnWidth(),
        const pw.FixedColumnWidth(84),
        const pw.FixedColumnWidth(86),
        const pw.FixedColumnWidth(86),
        if (mitNotiz) const pw.FlexColumnWidth(.9),
      ].asMap(),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        druckKopfzeile([
          druckKopfZelle('Parameter'),
          druckKopfZelle('Einheit'),
          druckKopfZelle('Hart (sperrt)'),
          druckKopfZelle('Warnung'),
          if (mitNotiz) druckKopfZelle('Notiz'),
        ]),
        for (final (name, einheit, g, imSteckbrief) in zeilen)
          pw.TableRow(
            children: [
              druckZelleMitZeile(
                name,
                imSteckbrief ? null : 'nicht im Steckbrief',
                fett: true,
                zeilenOben: 2,
                groesse: 8.5,
              ),
              druckZelle(einheit, zeilen: 2, groesse: 8),
              druckZelle(
                grenzText(g?.hartMin, g?.hartMax),
                groesse: 8.5,
                farbe: g == null ? kDruckGrau : PdfColors.black,
              ),
              druckZelle(
                grenzText(g?.weichMin, g?.weichMax),
                groesse: 8.5,
                farbe: g == null ? kDruckGrau : PdfColors.black,
              ),
              if (mitNotiz)
                druckZelle(
                  g?.notizen?.trim() ?? '',
                  zeilen: 2,
                  groesse: 8,
                  farbe: kDruckGrau,
                ),
            ],
          ),
      ],
    );
  }
}

/// „Temperatur (°C)" — ohne Einheit nur der Name.
String _mitEinheit(MachineParameterDef p) {
  final e = p.einheit?.trim() ?? '';
  return e.isEmpty ? p.parameterName : '${p.parameterName} ($e)';
}
