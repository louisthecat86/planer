import 'package:flutter/material.dart' show
    AlertDialog,
    BuildContext,
    CheckboxListTile,
    FilledButton,
    Navigator,
    StatefulBuilder,
    SwitchListTile,
    Text,
    TextButton,
    showDialog;
import 'package:flutter/widgets.dart' as w;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import 'article_detail_screen.dart';
import 'bratstrasse_schema.dart';

/// Auswahl des Druck-Dialogs: welche Abteilungen, und ob jede Abteilung
/// auf einer eigenen Seite gedruckt wird (zum getrennten Verteilen).
typedef _DruckAuswahl = ({Set<String> abteilungen, bool eigeneSeiten});

/// Erstellt ein druckfertiges DIN-A4-Prozessblatt für einen Artikel.
///
/// Aufbau (angelehnt an die Bratstraßen-Einstellvorlage):
/// - Kopf mit Artikelnummer, Bezeichnung, Produktgruppe und Druckdatum
/// - Je Abteilung ein farbiges Band (Abteilungsfarbe + Kurzcode)
/// - Je Maschine: Kennwerte (Personen / Menge / Dauer / Fixe Zeit / …)
///   und alle gefüllten Parameter, nach Gruppe geordnet
/// - Für Bratstraßen-Schritte: grafisches Plattenraster mit Laufrichtung
///   (Zone 1 = Einlauf rechts), Bratstraße 10+10 bzw. Kombiofen 12 Zonen
///
/// Vor dem Druck fragt ein Dialog, ob alle Abteilungen auf ein Blatt
/// sollen oder nur ausgewählte — optional jede auf eigener Seite,
/// damit die Blätter getrennt an die Abteilungen verteilt werden können.
class ArticlePrintService {
  ArticlePrintService._();

  /// Lädt alle Daten des Artikels, fragt die Druck-Auswahl ab und öffnet
  /// die System-Druckvorschau.
  static Future<void> drucke(
    BuildContext context,
    WidgetRef ref,
    String productId,
  ) async {
    final produkt = await ref.read(productProvider(productId).future);
    if (produkt == null) return;

    final steps = await ref.read(productStepsProvider(productId).future);
    if (steps.isEmpty) return;

    // Parameter + Maschine je Schritt vorab laden
    final parameterJeStep = <String, List<ProductStepParameter>>{};
    final maschineJeStep = <String, Machine?>{};
    for (final s in steps) {
      parameterJeStep[s.id] =
          await ref.read(stepParametersProvider(s.id).future);
      final mid = s.maschineId;
      maschineJeStep[s.id] =
          mid == null ? null : await ref.read(machineProvider(mid).future);
    }

    // Vorkommende Abteilungen in Prozess-Reihenfolge
    final abteilungen = <String>[];
    for (final s in steps) {
      if (!abteilungen.contains(s.abteilung)) abteilungen.add(s.abteilung);
    }

    if (!context.mounted) return;
    final auswahl = await _frageAuswahl(context, abteilungen);
    if (auswahl == null || auswahl.abteilungen.isEmpty) return;

    final doc = _baueDokument(
      produkt: produkt,
      steps: steps,
      parameterJeStep: parameterJeStep,
      maschineJeStep: maschineJeStep,
      gewaehlt: auswahl.abteilungen,
      eigeneSeiten: auswahl.eigeneSeiten,
    );

    await Printing.layoutPdf(
      name: 'Prozessblatt_${produkt.artikelnummer}',
      onLayout: (format) => doc.save(),
    );
  }

  /// Dialog: Abteilungen wählen + „jede Abteilung auf eigener Seite".
  static Future<_DruckAuswahl?> _frageAuswahl(
    BuildContext context,
    List<String> abteilungen,
  ) {
    final gewaehlt = {...abteilungen};
    var eigeneSeiten = false;

    return showDialog<_DruckAuswahl>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Prozessblatt drucken'),
          content: w.SizedBox(
            width: 360,
            child: w.Column(
              mainAxisSize: w.MainAxisSize.min,
              crossAxisAlignment: w.CrossAxisAlignment.start,
              children: [
                const Text('Welche Abteilungen sollen aufs Blatt?'),
                const w.SizedBox(height: 8),
                for (final a in abteilungen)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: w.EdgeInsets.zero,
                    title: Text(Abteilung.fromDbValue(a).anzeigeName),
                    value: gewaehlt.contains(a),
                    onChanged: (v) => setState(() {
                      if (v ?? false) {
                        gewaehlt.add(a);
                      } else {
                        gewaehlt.remove(a);
                      }
                    }),
                  ),
                const w.SizedBox(height: 4),
                SwitchListTile(
                  dense: true,
                  contentPadding: w.EdgeInsets.zero,
                  title: const Text('Jede Abteilung auf eigener Seite'),
                  subtitle: const Text(
                    'Zum getrennten Verteilen an die Abteilungen',
                  ),
                  value: eigeneSeiten,
                  onChanged: (v) => setState(() => eigeneSeiten = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: gewaehlt.isEmpty
                  ? null
                  : () => Navigator.of(ctx).pop(
                        (abteilungen: gewaehlt, eigeneSeiten: eigeneSeiten),
                      ),
              child: const Text('Drucken'),
            ),
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // Dokumentaufbau
  // ────────────────────────────────────────────────────────────────────

  static pw.Document _baueDokument({
    required Product produkt,
    required List<ProductStep> steps,
    required Map<String, List<ProductStepParameter>> parameterJeStep,
    required Map<String, Machine?> maschineJeStep,
    required Set<String> gewaehlt,
    required bool eigeneSeiten,
  }) {
    final doc = pw.Document();

    // Abteilungen in Reihenfolge des ersten Auftretens gruppieren —
    // nur die ausgewählten.
    final gruppen = <String, List<ProductStep>>{};
    for (final s in steps) {
      if (!gewaehlt.contains(s.abteilung)) continue;
      gruppen.putIfAbsent(s.abteilung, () => []).add(s);
    }

    pw.MultiPage seite(Iterable<MapEntry<String, List<ProductStep>>> teile) {
      return pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 30),
        theme: pw.ThemeData.withFont(
          base: pw.Font.helvetica(),
          bold: pw.Font.helveticaBold(),
          italic: pw.Font.helveticaOblique(),
        ),
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 6),
          child: pw.Text(
            'Seite ${ctx.pageNumber}/${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
          ),
        ),
        build: (ctx) => [
          _kopf(produkt),
          pw.SizedBox(height: 10),
          for (final eintrag in teile) ...[
            _abteilungsBand(eintrag.key),
            pw.SizedBox(height: 4),
            for (final s in eintrag.value) ...[
              _schrittBlock(
                step: s,
                maschine: maschineJeStep[s.id],
                parameter: parameterJeStep[s.id] ?? const [],
              ),
              pw.SizedBox(height: 6),
            ],
            pw.SizedBox(height: 4),
          ],
        ],
      );
    }

    if (eigeneSeiten) {
      // Jede Abteilung beginnt auf einer eigenen Seite (eigener Kopf) —
      // die Blätter lassen sich so getrennt verteilen.
      for (final eintrag in gruppen.entries) {
        doc.addPage(seite([eintrag]));
      }
    } else {
      doc.addPage(seite(gruppen.entries));
    }

    return doc;
  }

  // ── Kopf ──────────────────────────────────────────────────────────

  static pw.Widget _kopf(Product p) {
    final heute = DateTime.now();
    final datum = '${heute.day.toString().padLeft(2, '0')}.'
        '${heute.month.toString().padLeft(2, '0')}.${heute.year}';
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey900,
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Text(
                p.artikelnummer,
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: pw.Text(
                p.artikelbezeichnung,
                style: pw.TextStyle(
                  fontSize: 15,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'Prozessblatt',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.Text(
                  datum,
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey600,
                  ),
                ),
              ],
            ),
          ],
        ),
        if (p.produktgruppe != null && p.produktgruppe!.isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 2),
            child: pw.Text(
              p.produktgruppe!,
              style:
                  const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ),
        pw.SizedBox(height: 5),
        pw.Container(height: 2, color: PdfColors.grey900),
      ],
    );
  }

  // ── Abteilungsband ────────────────────────────────────────────────

  static pw.Widget _abteilungsBand(String abteilungDb) {
    final abt = Abteilung.fromDbValue(abteilungDb);
    final farbe = PdfColor.fromInt(abt.farbe.toARGB32());
    final name = abt.anzeigeName;
    final kurz = abt.kurzcode;
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: pw.BoxDecoration(
        color: farbe,
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Row(
        children: [
          if (kurz.isNotEmpty) ...[
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: pw.BorderRadius.circular(7),
              ),
              child: pw.Text(
                kurz,
                style: pw.TextStyle(
                  fontSize: 7,
                  fontWeight: pw.FontWeight.bold,
                  color: farbe,
                ),
              ),
            ),
            pw.SizedBox(width: 6),
          ],
          pw.Text(
            name,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ── Schritt-Block (Maschine + Werte + Parameter + ggf. Platten) ───

  static pw.Widget _schrittBlock({
    required ProductStep step,
    required Machine? maschine,
    required List<ProductStepParameter> parameter,
  }) {
    final maschinenName = maschine?.name ??
        ((step.maschine != null && step.maschine!.trim().isNotEmpty)
            ? step.maschine!
            : 'Ohne Anlage');

    // Kennwerte sammeln (nur belegte)
    final kennwerte = <({String label, String wert})>[];
    if (step.basisMitarbeiter > 0) {
      kennwerte.add((label: 'Personen', wert: '${step.basisMitarbeiter}'));
    }
    if (step.basisMengeKg > 0) {
      kennwerte
          .add((label: 'Menge (kg)', wert: _fmt(step.basisMengeKg)));
    }
    if (step.basisDauerMinuten > 0) {
      kennwerte.add(
        (label: 'Dauer (min)', wert: _fmt(step.basisDauerMinuten)),
      );
    }
    final num? fix = step.fixZeitMinuten;
    if (fix != null && fix > 0) {
      kennwerte.add((label: 'Fixe Zeit (min)', wert: _fmt(fix)));
    }
    final num? kt = step.kerntemperaturZiel;
    if (kt != null && kt > 0) {
      kennwerte.add((label: 'Kerntemp. (°C)', wert: _fmt(kt)));
    }
    final num? wz = step.wartezeitMinuten;
    if (wz != null && wz > 0) {
      kennwerte.add((label: 'Wartezeit (min)', wert: _fmt(wz)));
    }

    // Plattenschema ermitteln (nur Bratstraße)
    final typ = step.abteilung == kAbteilungBratstrasseDb
        ? _ermittlePlattenTyp(parameter)
        : null;

    // Sichtbare Parameter (versteckte Platten-Parameter + Marker raus,
    // leere Werte raus), nach Gruppe geordnet
    final sichtbare = parameter
        .where((p) => !istVerstecktesPlattenParam(p.parameterName))
        .where((p) => p.wert != null && p.wert!.trim().isNotEmpty)
        .toList();
    final paramGruppen = <String, List<ProductStepParameter>>{};
    for (final p in sichtbare) {
      paramGruppen.putIfAbsent(p.parameterGruppe, () => []).add(p);
    }

    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Maschinen-Zeile
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                maschinenName,
                style: pw.TextStyle(
                  fontSize: 10.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (step.prozessschritt != null &&
                  step.prozessschritt!.trim().isNotEmpty) ...[
                pw.SizedBox(width: 6),
                pw.Text(
                  step.prozessschritt!,
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    fontStyle: pw.FontStyle.italic,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ],
          ),

          // Kennwert-Kästen
          if (kennwerte.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Row(
              children: [
                for (var i = 0; i < kennwerte.length; i++) ...[
                  if (i > 0) pw.SizedBox(width: 4),
                  _kennwertBox(kennwerte[i].label, kennwerte[i].wert),
                ],
              ],
            ),
          ],

          // Plattenraster (Bratstraße / Kombiofen)
          if (typ != null) ...[
            pw.SizedBox(height: 6),
            _plattenRaster(typ, parameter),
          ],

          // Parameter nach Gruppen
          for (final g in paramGruppen.entries) ...[
            pw.SizedBox(height: 5),
            pw.Text(
              g.key,
              style: pw.TextStyle(
                fontSize: 7,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey600,
                letterSpacing: 0.5,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Wrap(
              spacing: 10,
              runSpacing: 2,
              children: [
                for (final p in g.value)
                  pw.SizedBox(
                    width: 158,
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          child: pw.Text(
                            p.parameterName,
                            style: const pw.TextStyle(
                              fontSize: 8,
                              color: PdfColors.grey800,
                            ),
                          ),
                        ),
                        pw.SizedBox(width: 4),
                        pw.Text(
                          p.wert!,
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],

          // Schritt-Notizen
          if (step.notizen != null && step.notizen!.trim().isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(
              'Notiz: ${step.notizen!}',
              style: pw.TextStyle(
                fontSize: 7.5,
                fontStyle: pw.FontStyle.italic,
                color: PdfColors.grey700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static pw.Widget _kennwertBox(String label, String wert) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style:
                const pw.TextStyle(fontSize: 6, color: PdfColors.grey600),
          ),
          pw.Text(
            wert,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ── Plattenraster ─────────────────────────────────────────────────

  static BratschemaTyp? _ermittlePlattenTyp(
    List<ProductStepParameter> parameter,
  ) {
    // 1) Expliziter Marker
    for (final p in parameter) {
      if (p.parameterName == kPlattenSchemaParam) {
        switch (p.wert) {
          case 'bratstrasse':
            return BratschemaTyp.bratstrasse;
          case 'kombiofen':
            return BratschemaTyp.kombiofen;
          case 'keine':
            return null;
        }
      }
    }
    // 2) Aus vorhandenen Zonen-Parametern ableiten
    final zonen = parameter
        .where((p) => istVerstecktesPlattenParam(p.parameterName))
        .where((p) => p.parameterName != kPlattenSchemaParam)
        .toList();
    if (zonen.isEmpty) return null;
    final hatKombiZone = zonen.any(
      (p) =>
          p.parameterGruppe == kPlattenGruppeKombi ||
          p.parameterName == 'Platte Unten 11' ||
          p.parameterName == 'Platte Unten 12',
    );
    return hatKombiZone ? BratschemaTyp.kombiofen : BratschemaTyp.bratstrasse;
  }

  static double? _plattenWert(
    List<ProductStepParameter> parameter,
    String name,
  ) {
    for (final p in parameter) {
      if (p.parameterName == name) {
        final w = p.wert;
        if (w == null || w.trim().isEmpty) return null;
        return double.tryParse(w.replaceAll(',', '.'));
      }
    }
    return null;
  }

  static pw.Widget _plattenRaster(
    BratschemaTyp typ,
    List<ProductStepParameter> parameter,
  ) {
    final istKombi = typ == BratschemaTyp.kombiofen;
    final zonen = istKombi ? kKombiofenZonen : kBratstrasseZonen;

    pw.Widget reihe(String prefix) {
      // Laufrichtung: Zone 1 = Einlauf rechts -> links steht die höchste Zone
      final zellen = <pw.Widget>[];
      for (var anzeige = 0; anzeige < zonen; anzeige++) {
        final zone = zonen - anzeige;
        // Kombiofen optisch in 2 Gruppen à 6 (wie auf der Vorlage)
        if (istKombi && anzeige == 6) {
          zellen.add(pw.SizedBox(width: 6));
        }
        zellen.add(
          _plattenZelle(
            zone: zone,
            wert: _plattenWert(parameter, '$prefix $zone'),
          ),
        );
      }
      return pw.Row(children: zellen);
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          children: [
            pw.Text(
              istKombi ? 'Kombiofen' : 'Bratstrasse',
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(width: 10),
            pw.Text(
              '<----- Laufrichtung (Zone 1 = Einlauf rechts)',
              style: const pw.TextStyle(
                fontSize: 7,
                color: PdfColors.grey600,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 3),
        if (!istKombi) ...[
          pw.Text(
            'Platten oben',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 1),
          reihe('Platte Oben'),
          pw.SizedBox(height: 3),
        ],
        pw.Text(
          'Platten unten',
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 1),
        reihe('Platte Unten'),
      ],
    );
  }

  static pw.Widget _plattenZelle({required int zone, double? wert}) {
    final hat = wert != null;
    PdfColor bg;
    if (!hat) {
      bg = PdfColors.grey200;
    } else if (wert <= 0) {
      bg = PdfColors.grey300;
    } else if (wert < 160) {
      bg = PdfColor.fromHex('#FFF3E0');
    } else if (wert < 230) {
      bg = PdfColor.fromHex('#FFE0B2');
    } else {
      bg = PdfColor.fromHex('#FFCC80');
    }
    return pw.Container(
      width: 36,
      height: 24,
      margin: const pw.EdgeInsets.only(right: 2),
      decoration: pw.BoxDecoration(
        color: bg,
        border: pw.Border.all(color: PdfColors.grey500, width: 0.5),
        borderRadius: pw.BorderRadius.circular(2),
      ),
      child: pw.Stack(
        children: [
          pw.Positioned(
            top: 1,
            left: 2,
            child: pw.Text(
              '$zone',
              style:
                  const pw.TextStyle(fontSize: 5, color: PdfColors.grey600),
            ),
          ),
          pw.Center(
            child: pw.Text(
              hat ? _fmt(wert) : '-',
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: hat ? PdfColors.grey900 : PdfColors.grey500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Format-Helfer ─────────────────────────────────────────────────

  static String _fmt(num v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1).replaceAll('.', ',');
  }
}