import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/database/database.dart'
    show Machine, MachineParameterDef, ParameterGrenzenData;
import '../../core/druck/druck_bausteine.dart';
import '../../core/druck/druck_optionen.dart';
import '../../core/druck/druck_satz.dart';
import 'maschinen_druck_daten.dart';

// Die Grenzwerte der Maschinenparameter auf Papier — wie die Seite
// „Maschinen-Grenzen": je Anlage oder Parametergruppe eine Tabelle mit
// harter Grenze (sperrt das Speichern) und Warnung. Auf Wunsch mit den
// Parametern des Steckbriefs, die noch keine Grenze haben, und jede Anlage
// auf einer eigenen Seite zum Aushängen.

/// Schlüssel der Wahl im Druckfenster.
abstract final class GrenzenWahl {
  static const kontexte = 'kontexte';
  static const ohne = 'ohne';
  static const notizen = 'notizen';
  static const einzeln = 'einzeln';
}

/// Was auf das Blatt kommt — die Wahl im Druckfenster.
class GrenzenInhalt {
  const GrenzenInhalt({
    this.kontexte,
    this.ohne = false,
    this.notizen = true,
    this.einzeln = false,
  });

  /// Nur diese Anlagen und Gruppen — null: alle mit Grenzen.
  final Set<String>? kontexte;

  /// Die Parameter des Steckbriefs ohne Grenze, grau.
  final bool ohne;

  final bool notizen;

  /// Jede Anlage und Gruppe auf einer neuen Seite.
  final bool einzeln;
}

String _grenzen(int n) => n == 1 ? '1 Grenze' : '$n Grenzen';

/// Was harte Grenze und Warnung bedeuten.
const String _erklaerung =
    'Hart (sperrt): Werte außerhalb lassen sich nicht speichern. Warnung: '
    'Werte außerhalb werden gemeldet, lassen sich aber speichern.';

/// Die Grenzen zum Drucken.
DruckDokument grenzenDruck(
  MaschinenDruckDaten daten, {
  GrenzenInhalt inhalt = const GrenzenInhalt(),
  DateTime? gedrucktAm,
}) {
  final gedruckt = gedrucktAm ?? DateTime.now();
  final blatt = _Grenzen(daten, inhalt, druckGedruckt(gedruckt));
  return DruckDokument(
    titel: 'Maschinen-Grenzen',
    dateiname: druckDateiname('Maschinen-Grenzen ${druckIsoDatum(gedruckt)}'),
    blaetter: [blatt.blatt()],
  );
}

/// „Anlage · Bratstraße" oder „Parametergruppe".
String _art(MaschinenDruckDaten daten, String kontext) {
  final m = daten.maschineNamens(kontext);
  if (m == null) return 'Parametergruppe';
  final a = abteilungDer(m);
  return a == null ? 'Anlage' : 'Anlage · ${a.anzeigeName}';
}

/// Die Grenzen für das Druckfenster.
DruckAuftrag grenzenDruckAuftrag(
  MaschinenDruckDaten daten, {
  DateTime? gedrucktAm,
}) {
  final jeKontext = daten.grenzenJeKontext;
  final kontexte = jeKontext.keys.toList()..sort();
  return DruckAuftrag(
    art: 'grenzen',
    titel: 'Maschinen-Grenzen drucken',
    untertitel: [
      _grenzen(daten.grenzen.length),
      kontexte.length == 1
          ? '1 Anlage oder Gruppe'
          : '${kontexte.length} Anlagen und Gruppen',
    ].join(' · '),
    optionen: [
      if (kontexte.length > 1)
        DruckWahlMehrere(
          schluessel: GrenzenWahl.kontexte,
          titel: 'Anlagen und Gruppen',
          werte: [
            for (final k in kontexte)
              DruckWert(
                k,
                k,
                hinweis: '${_art(daten, k)} · '
                    '${_grenzen(jeKontext[k]!.length)}',
                farbe: switch (daten.maschineNamens(k)) {
                  final Machine m => abteilungDer(m)?.farbwert,
                  null => null,
                },
                kuerzel: switch (daten.maschineNamens(k)) {
                  final Machine m => abteilungDer(m)?.kurzcode,
                  null => null,
                },
              ),
          ],
          standard: kontexte.toSet(),
          merken: false,
        ),
      const DruckSchalter(
        schluessel: GrenzenWahl.ohne,
        titel: 'Parameter ohne Grenze',
        hinweis: 'Aus dem Steckbrief der Anlage, grau — so sieht man, wo '
            'Grenzen fehlen',
        standard: false,
        gruppe: 'Auf dem Blatt',
      ),
      const DruckSchalter(
        schluessel: GrenzenWahl.notizen,
        titel: 'Notizen',
        gruppe: 'Auf dem Blatt',
      ),
      const DruckSchalter(
        schluessel: GrenzenWahl.einzeln,
        titel: 'Jede Anlage auf einer neuen Seite',
        hinweis: 'Zum Aushängen an der Anlage',
        standard: false,
        gruppe: 'Auf dem Blatt',
      ),
    ],
    bauen: (wahl) {
      Set<String>? gewaehlt;
      if (kontexte.length > 1) {
        gewaehlt = wahl.mehrere(GrenzenWahl.kontexte);
        if (gewaehlt.isEmpty) {
          throw const DruckNichtsGewaehlt(
            'Wähle mindestens eine Anlage oder Gruppe.',
          );
        }
      }
      return grenzenDruck(
        daten,
        gedrucktAm: gedrucktAm,
        inhalt: GrenzenInhalt(
          kontexte: gewaehlt,
          ohne: wahl.an(GrenzenWahl.ohne),
          notizen: wahl.an(GrenzenWahl.notizen),
          einzeln: wahl.an(GrenzenWahl.einzeln),
        ),
      );
    },
  );
}

/// Eine Zeile: Parameter, Einheit, die Grenze — null: keine.
typedef _Zeile = ({String name, String einheit, ParameterGrenzenData? grenze});

class _Grenzen {
  _Grenzen(this.daten, this.inhalt, this.gedruckt)
      : jeKontext = daten.grenzenJeKontext;

  final MaschinenDruckDaten daten;
  final GrenzenInhalt inhalt;
  final String gedruckt;
  final Map<String, List<ParameterGrenzenData>> jeKontext;

  /// Die gezeigten Anlagen und Gruppen, alphabetisch wie auf der Seite.
  List<String> get kontexte => [
        for (final k in jeKontext.keys.toList()..sort())
          if (inhalt.kontexte?.contains(k) ?? true) k,
      ];

  /// Die Zeilen einer Anlage oder Gruppe: bei einer Anlage in der
  /// Reihenfolge ihres Steckbriefs (mit Einheit), Grenzen zu anderen
  /// Parametern danach — sonst nach Parametername.
  List<_Zeile> zeilen(String kontext) {
    final grenzen = jeKontext[kontext] ?? const <ParameterGrenzenData>[];
    final m = daten.maschineNamens(kontext);
    final steckbrief = m == null
        ? const <MachineParameterDef>[]
        : (daten.steckbriefe[m.id] ?? const <MachineParameterDef>[]);
    final jeName = {for (final g in grenzen) g.parameterName: g};
    final namen = {for (final p in steckbrief) p.parameterName};
    return [
      for (final p in steckbrief)
        if (jeName[p.parameterName] != null || inhalt.ohne)
          (
            name: p.parameterName,
            einheit: p.einheit?.trim() ?? '',
            grenze: jeName[p.parameterName],
          ),
      for (final g in grenzen)
        if (!namen.contains(g.parameterName))
          (name: g.parameterName, einheit: '', grenze: g),
    ];
  }

  DruckBlatt blatt() {
    final liste = kontexte;
    final zahl = liste.fold<int>(0, (s, k) => s + jeKontext[k]!.length);
    final zeile = [
      _grenzen(zahl),
      liste.length == 1
          ? '1 Anlage oder Gruppe'
          : '${liste.length} Anlagen und Gruppen',
    ].join(' · ');
    return DruckBlatt(
      bauen: (r) {
        // Zum Aushängen steht jede Anlage für sich: ohne Kennzahlen, die
        // Erklärung unter jeder Tabelle.
        final aushang = inhalt.einzeln && r.umbrueche;
        final teile = <pw.Widget>[
          if (!aushang) ...[
            ...kennzahlen(liste),
            druckHinweis(_erklaerung, zeilen: 2),
          ],
          if (liste.isEmpty)
            druckHinweis(
              daten.grenzen.isEmpty
                  ? 'Noch keine Grenzen gepflegt.'
                  : 'Keine Grenzen.',
            ),
          for (final (i, k) in liste.indexed) ...[
            if (i > 0 && aushang) pw.NewPage(),
            ...kontextBlock(r, k, erklaerung: aushang),
          ],
        ];
        return DruckSeiten(
          kopf: (ctx) => druckKopf(
            titel: 'Maschinen-Grenzen',
            zeile: zeile,
            gedruckt: gedruckt,
          ),
          fuss: (ctx) => druckFuss('Maschinen-Grenzen', r.seitenText(ctx)),
          inhalt: (ctx) => teile,
        );
      },
    );
  }

  List<pw.Widget> kennzahlen(List<String> liste) {
    if (liste.isEmpty) return const [];
    final anlagen = liste.where((k) => daten.maschineNamens(k) != null).length;
    final gruppen = liste.length - anlagen;
    final grenzen = [for (final k in liste) ...jeKontext[k]!];
    final hart =
        grenzen.where((g) => g.hartMin != null || g.hartMax != null).length;
    final ohne = inhalt.ohne
        ? liste.fold<int>(
            0,
            (s, k) => s + zeilen(k).where((z) => z.grenze == null).length,
          )
        : 0;
    return [
      druckKennzahlen([
        DruckKennzahl(_grenzen(grenzen.length), 'gepflegt', betont: true),
        DruckKennzahl('$hart', 'mit harter Grenze'),
        DruckKennzahl('$anlagen', anlagen == 1 ? 'Anlage' : 'Anlagen'),
        if (gruppen > 0)
          DruckKennzahl(
            '$gruppen',
            gruppen == 1 ? 'Parametergruppe' : 'Parametergruppen',
          ),
        if (inhalt.ohne) DruckKennzahl('$ohne', 'Parameter ohne Grenze'),
      ]),
    ];
  }

  /// Eine Anlage oder Gruppe: Leiste und Tabelle — zusammen, wenn sie
  /// sicher auf eine Seite passen.
  List<pw.Widget> kontextBlock(
    DruckRahmen r,
    String kontext, {
    bool erklaerung = false,
  }) {
    final m = daten.maschineNamens(kontext);
    final farbe = m == null ? null : abteilungDer(m)?.farbwert;
    final liste = zeilen(kontext);
    final n = jeKontext[kontext]?.length ?? 0;
    return druckGruppe(
      [
        pw.SizedBox(height: 8),
        druckLeiste(
          kontext,
          rechts: '${_art(daten, kontext)} · ${_grenzen(n)}',
          farbe: farbe,
        ),
        tabelle(liste),
        if (erklaerung)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 3),
            child: druckHinweis(_erklaerung, zeilen: 2),
          ),
      ],
      zusammen: 90 + (liste.length + 1) * 22 <= r.hoehe - 60,
      rahmen: r,
      frei: 100,
    );
  }

  pw.Widget tabelle(List<_Zeile> liste) {
    final mitNotiz = inhalt.notizen &&
        liste.any((z) => (z.grenze?.notizen ?? '').trim().isNotEmpty);
    final mitEinheit = liste.any((z) => z.einheit.isNotEmpty);
    return pw.Table(
      border: kDruckGitter,
      columnWidths: <pw.TableColumnWidth>[
        const pw.FlexColumnWidth(),
        if (mitEinheit) const pw.FixedColumnWidth(84),
        const pw.FixedColumnWidth(90),
        const pw.FixedColumnWidth(90),
        if (mitNotiz) const pw.FlexColumnWidth(.9),
      ].asMap(),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        druckKopfzeile([
          druckKopfZelle('Parameter'),
          if (mitEinheit) druckKopfZelle('Einheit'),
          druckKopfZelle('Hart (sperrt)'),
          druckKopfZelle('Warnung'),
          if (mitNotiz) druckKopfZelle('Notiz'),
        ]),
        for (final z in liste)
          pw.TableRow(
            children: [
              druckZelle(
                z.name,
                fett: z.grenze != null,
                zeilen: 2,
                groesse: 8.5,
                farbe: z.grenze == null ? kDruckGrau : PdfColors.black,
              ),
              if (mitEinheit)
                druckZelle(
                  z.einheit,
                  zeilen: 2,
                  groesse: 8,
                  farbe: z.grenze == null ? kDruckGrau : PdfColors.black,
                ),
              druckZelle(
                grenzText(z.grenze?.hartMin, z.grenze?.hartMax),
                groesse: 8.5,
                fett: z.grenze?.hartMin != null || z.grenze?.hartMax != null,
                farbe: z.grenze == null ? kDruckGrau : PdfColors.black,
              ),
              druckZelle(
                grenzText(z.grenze?.weichMin, z.grenze?.weichMax),
                groesse: 8.5,
                farbe: z.grenze == null ? kDruckGrau : PdfColors.black,
              ),
              if (mitNotiz)
                druckZelle(
                  z.grenze?.notizen?.trim() ?? '',
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
