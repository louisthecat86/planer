import 'dart:convert';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/constants/abteilungen.dart';
import '../../core/constants/parameter_namen.dart';
import '../../core/database/database.dart';
import '../../core/druck/druck_optionen.dart';
import '../../core/druck/druck_satz.dart';
import '../../core/utils/format.dart';
import '../../core/utils/pdf_text.dart';
import '../../core/utils/platten_raster_pdf.dart';
import '../../core/utils/zeit.dart' show Zeit;
import '../whiteboard/whiteboard_provider.dart' show leistungsdatenVon;

// Das Prozessblatt eines Artikels: je Abteilung ein farbiges Band mit
// ihren Leistungsdaten, je Anlage Kennwerte, Plattenraster,
// Maschineneinstellungen und Parameter — angelehnt an die
// Bratstraßen-Einstellvorlage.
//
// Bewusst ohne Oberfläche: Was gedruckt wird, entscheidet die Wahl im
// Druckfenster (prozessblattDruckAuftrag).

/// Was zum Prozessblatt eines Artikels geladen ist.
class ProzessblattDaten {
  const ProzessblattDaten({
    required this.produkt,
    required this.schritte,
    this.parameter = const {},
    this.maschinen = const {},
  });

  final Product produkt;

  /// Die Schritte in Prozessreihenfolge.
  final List<ProductStep> schritte;

  /// Die Parameter je Schritt-ID.
  final Map<String, List<ProductStepParameter>> parameter;

  /// Die Anlage je Schritt-ID — null: keine.
  final Map<String, Machine?> maschinen;

  /// Die Abteilungen in der Reihenfolge ihres ersten Schritts.
  List<String> get abteilungen => [
        for (final (i, s) in schritte.indexed)
          if (!schritte.take(i).any((v) => v.abteilung == s.abteilung))
            s.abteilung,
      ];

  /// Name der Anlage eines Schritts — oder „Ohne Anlage".
  String anlage(ProductStep s) {
    final maschine = maschinen[s.id]?.name;
    if (maschine != null) return maschine;
    final frei = s.maschine?.trim() ?? '';
    return frei.isNotEmpty ? frei : 'Ohne Anlage';
  }
}

/// Was auf das Prozessblatt kommt.
class ProzessblattInhalt {
  const ProzessblattInhalt({
    this.abteilungen,
    this.schritte,
    this.eigeneSeiten = false,
    this.leistung = true,
    this.kennwerte = true,
    this.platten = true,
    this.einstellungen = true,
    this.parameter = true,
    this.notizen = true,
    this.notizfeld = false,
  });

  /// Diese Abteilungen (dbValue) — null: alle.
  final Set<String>? abteilungen;

  /// Diese Schritte (ID) — null: alle der gewählten Abteilungen.
  final Set<String>? schritte;

  /// Jede Abteilung auf einem eigenen Blatt — zum Verteilen.
  final bool eigeneSeiten;

  /// Die Leistungsdaten im Band der Abteilung.
  final bool leistung;

  /// Personen und Kerntemperatur je Anlage.
  final bool kennwerte;

  /// Das Plattenraster von Bratstraße und Kombiofen.
  final bool platten;

  /// Die Maschineneinstellungen als Freitext.
  final bool einstellungen;

  /// Die Parameter der Anlagen, nach Gruppen.
  final bool parameter;

  /// Die Notizen der Schritte.
  final bool notizen;

  /// Unter jeder Abteilung Linien für Notizen von Hand.
  final bool notizfeld;
}

/// Schlüssel der Wahl im Druckfenster.
abstract final class ProzessblattWahl {
  static const abteilungen = 'abteilungen';
  static const schritte = 'schritte';
  static const eigeneSeiten = 'eigeneSeiten';
  static const leistung = 'leistung';
  static const kennwerte = 'kennwerte';
  static const platten = 'platten';
  static const einstellungen = 'einstellungen';
  static const parameter = 'parameter';
  static const notizen = 'notizen';
  static const notizfeld = 'notizfeld';
}

/// Der Druck des Prozessblatts für das Druckfenster.
DruckAuftrag prozessblattDruckAuftrag(
  ProzessblattDaten daten, {
  DateTime? gedrucktAm,
}) {
  final p = daten.produkt;
  final abteilungen = daten.abteilungen;
  const gruppe = 'Auf dem Blatt';
  return DruckAuftrag(
    art: 'prozessblatt',
    titel: 'Prozessblatt drucken',
    untertitel: '${p.artikelnummer} · ${p.artikelbezeichnung}',
    optionen: [
      DruckWahlMehrere(
        schluessel: ProzessblattWahl.abteilungen,
        titel: 'Abteilungen',
        werte: [
          for (final a in abteilungen)
            DruckWert(
              a,
              _abteilungName(a),
              hinweis: _schritteText(
                daten.schritte.where((s) => s.abteilung == a).length,
              ),
              farbe: _abteilung(a)?.farbwert,
              kuerzel: _abteilung(a)?.kurzcode,
            ),
        ],
        standard: abteilungen.toSet(),
        merken: false,
      ),
      if (daten.schritte.length > 1)
        DruckWahlMehrere(
          schluessel: ProzessblattWahl.schritte,
          titel: 'Schritte',
          hinweis: 'Gedruckt werden die der gewählten Abteilungen',
          werte: [
            for (final s in daten.schritte)
              DruckWert(
                s.id,
                [
                  daten.anlage(s),
                  if ((s.prozessschritt ?? '').trim().isNotEmpty)
                    s.prozessschritt!.trim(),
                ].join(' · '),
                hinweis: _abteilungName(s.abteilung),
              ),
          ],
          standard: {for (final s in daten.schritte) s.id},
          merken: false,
        ),
      const DruckSchalter(
        schluessel: ProzessblattWahl.eigeneSeiten,
        titel: 'Jede Abteilung auf eigener Seite',
        hinweis: 'Zum getrennten Verteilen an die Abteilungen',
        standard: false,
      ),
      const DruckSchalter(
        schluessel: ProzessblattWahl.leistung,
        titel: 'Leistungsdaten der Abteilungen',
        gruppe: gruppe,
      ),
      const DruckSchalter(
        schluessel: ProzessblattWahl.kennwerte,
        titel: 'Kennwerte',
        hinweis: 'Personen und Kerntemperatur',
        gruppe: gruppe,
      ),
      const DruckSchalter(
        schluessel: ProzessblattWahl.platten,
        titel: 'Plattenraster',
        hinweis: 'Bratstraße und Kombiofen',
        gruppe: gruppe,
      ),
      const DruckSchalter(
        schluessel: ProzessblattWahl.einstellungen,
        titel: 'Maschineneinstellungen',
        gruppe: gruppe,
      ),
      const DruckSchalter(
        schluessel: ProzessblattWahl.parameter,
        titel: 'Parameter der Anlagen',
        gruppe: gruppe,
      ),
      const DruckSchalter(
        schluessel: ProzessblattWahl.notizen,
        titel: 'Notizen zu den Schritten',
        gruppe: gruppe,
      ),
      const DruckSchalter(
        schluessel: ProzessblattWahl.notizfeld,
        titel: 'Platz für Notizen von Hand',
        hinweis: 'Linien unter jeder Abteilung',
        standard: false,
        gruppe: gruppe,
      ),
    ],
    bauen: (wahl) {
      final gewaehlt = wahl.mehrere(ProzessblattWahl.abteilungen);
      if (gewaehlt.isEmpty) {
        throw const DruckNichtsGewaehlt('Wähle mindestens eine Abteilung.');
      }
      final schritte = daten.schritte.length > 1
          ? wahl.mehrere(ProzessblattWahl.schritte)
          : null;
      final inhalt = ProzessblattInhalt(
        abteilungen: gewaehlt,
        schritte: schritte,
        eigeneSeiten: wahl.an(ProzessblattWahl.eigeneSeiten),
        leistung: wahl.an(ProzessblattWahl.leistung),
        kennwerte: wahl.an(ProzessblattWahl.kennwerte),
        platten: wahl.an(ProzessblattWahl.platten),
        einstellungen: wahl.an(ProzessblattWahl.einstellungen),
        parameter: wahl.an(ProzessblattWahl.parameter),
        notizen: wahl.an(ProzessblattWahl.notizen),
        notizfeld: wahl.an(ProzessblattWahl.notizfeld),
      );
      if (_gruppen(daten, inhalt).isEmpty) {
        throw const DruckNichtsGewaehlt(
          'Wähle mindestens einen Schritt der gewählten Abteilungen.',
        );
      }
      return prozessblattDruck(daten, inhalt: inhalt, gedrucktAm: gedrucktAm);
    },
  );
}

/// Das Prozessblatt zum Drucken.
DruckDokument prozessblattDruck(
  ProzessblattDaten daten, {
  ProzessblattInhalt inhalt = const ProzessblattInhalt(),
  DateTime? gedrucktAm,
}) {
  final gruppen = _gruppen(daten, inhalt);
  if (gruppen.isEmpty) {
    throw ArgumentError('Nichts für das Prozessblatt gewählt.');
  }
  final datum = Format.datum(gedrucktAm ?? DateTime.now());
  final p = daten.produkt;

  DruckBlatt blatt(List<MapEntry<String, List<ProductStep>>> teile) =>
      DruckBlatt(
        rand: const pw.EdgeInsets.fromLTRB(28, 26, 28, 30),
        bauen: (r) => DruckSeiten(
          fuss: (ctx) => pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(top: 6),
            child: pw.Text(
              pdfText('${p.artikelnummer} · ${r.seitenText(ctx)}'),
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
            ),
          ),
          inhalt: (ctx) => [
            _kopf(p, datum),
            pw.SizedBox(height: 10),
            for (final eintrag in teile) ...[
              _abteilungsBand(
                eintrag.key,
                leistung: inhalt.leistung ? _leistungText(eintrag.value) : null,
              ),
              pw.SizedBox(height: 4),
              for (final s in eintrag.value) ...[
                _schrittBlock(daten, s, inhalt),
                pw.SizedBox(height: 6),
              ],
              if (inhalt.notizfeld) ...[
                _notizfeld(),
                pw.SizedBox(height: 6),
              ],
              pw.SizedBox(height: 4),
            ],
          ],
        ),
      );

  return DruckDokument(
    titel: 'Prozessblatt ${p.artikelnummer}',
    dateiname: druckDateiname(
      inhalt.eigeneSeiten && gruppen.length == 1
          ? 'Prozessblatt ${p.artikelnummer} '
              '${_abteilungName(gruppen.keys.single)}'
          : 'Prozessblatt ${p.artikelnummer}',
    ),
    blaetter: inhalt.eigeneSeiten
        // Jede Abteilung beginnt auf einer eigenen Seite (eigener Kopf) —
        // die Blätter lassen sich so getrennt verteilen.
        ? [
            for (final eintrag in gruppen.entries) blatt([eintrag]),
          ]
        : [blatt(gruppen.entries.toList())],
  );
}

/// Die gewählten Schritte je gewählter Abteilung, in Prozessreihenfolge.
Map<String, List<ProductStep>> _gruppen(
  ProzessblattDaten daten,
  ProzessblattInhalt inhalt,
) {
  final gruppen = <String, List<ProductStep>>{};
  for (final s in daten.schritte) {
    if (inhalt.abteilungen?.contains(s.abteilung) == false) continue;
    if (inhalt.schritte?.contains(s.id) == false) continue;
    gruppen.putIfAbsent(s.abteilung, () => []).add(s);
  }
  return gruppen;
}

Abteilung? _abteilung(String dbValue) {
  try {
    return Abteilung.fromDbValue(dbValue);
  } catch (_) {
    return null;
  }
}

/// Anzeigename einer Abteilung — ein unbekannter Wert bleibt stehen.
String _abteilungName(String dbValue) =>
    _abteilung(dbValue)?.anzeigeName ?? dbValue;

String _schritteText(int n) => n == 1 ? '1 Schritt' : '$n Schritte';

// ── Kopf ──────────────────────────────────────────────────────────────

pw.Widget _kopf(Product p, String datum) {
  final gruppe = p.produktgruppe?.trim() ?? '';
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey900,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(
              pdfText(p.artikelnummer),
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
              pdfText(p.artikelbezeichnung),
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
      if (gruppe.isNotEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 2),
          child: pw.Text(
            pdfText(gruppe),
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
      pw.SizedBox(height: 5),
      pw.Container(height: 2, color: PdfColors.grey900),
    ],
  );
}

// ── Abteilungsband ────────────────────────────────────────────────────

/// „Leistung: 600 kg in 1:00 h (600 kg/h)" — die hinterlegten
/// Leistungsdaten der Abteilung, null ohne.
String? _leistungText(List<ProductStep> schritte) {
  final l = leistungsdatenVon(schritte);
  if (l == null) return null;
  return 'Leistung: ${_fmt(l.mengeKg)} kg in ${Zeit.kurz(l.minuten)} '
      '(${_fmt(l.kgProStunde.roundToDouble())} kg/h)';
}

pw.Widget _abteilungsBand(String abteilungDb, {String? leistung}) {
  final abt = _abteilung(abteilungDb);
  final farbe =
      abt == null ? PdfColors.grey700 : PdfColor.fromInt(abt.farbwert);
  final kurz = abt?.kurzcode ?? '';
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
            padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(7),
            ),
            child: pw.Text(
              pdfText(kurz),
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
          pdfText(_abteilungName(abteilungDb)),
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
        ),
        if (leistung != null) ...[
          pw.Spacer(),
          pw.Text(
            pdfText(leistung),
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.white),
          ),
        ],
      ],
    ),
  );
}

// ── Schritt-Block (Anlage, Werte, Parameter, Platten) ─────────────────

pw.Widget _schrittBlock(
  ProzessblattDaten daten,
  ProductStep step,
  ProzessblattInhalt inhalt,
) {
  final maschinenName = daten.anlage(step);
  final parameter = daten.parameter[step.id] ?? const <ProductStepParameter>[];

  // Kennwerte sammeln (nur belegte). Menge und Zeit sind Leistungsdaten
  // der Abteilung und stehen im Band — an der Anlage gibt es keine Zeiten.
  final kennwerte = <({String label, String wert})>[
    if (inhalt.kennwerte && step.basisMitarbeiter > 0)
      (label: 'Personen', wert: '${step.basisMitarbeiter}'),
    if (inhalt.kennwerte &&
        step.kerntemperaturZiel != null &&
        step.kerntemperaturZiel! > 0)
      (label: 'Kerntemp. (°C)', wert: _fmt(step.kerntemperaturZiel!)),
  ];

  // Plattenraster nur an Bratstraße und Kombiofen — NICHT an der Abteilung
  // festmachen: Verbufa und Füllmaschine stehen in der Abteilung
  // Bratstraße, haben aber kein Raster.
  final platten = istPlattenMaschine(maschinenName);
  final kombiofen =
      inhalt.platten && platten ? _plattenTyp(parameter) : null;

  // Freitext „Maschineneinstellungen" — an allen Anlagen außer denen mit
  // Raster. Er ist als verstecktes Parameter markiert (damit er nicht
  // doppelt in der Liste steht), steht im Druck aber für sich.
  final notiz = !inhalt.einstellungen || platten
      ? null
      : parameter
          .where((p) => p.parameterName == kMaschinenNotizParam)
          .map((p) => p.wert?.trim() ?? '')
          .where((w) => w.isNotEmpty)
          .firstOrNull;

  // Sichtbare Parameter nach Gruppe: ohne die versteckten und ohne leere.
  final paramGruppen = <String, List<({String name, String wert})>>{};
  if (inhalt.parameter) {
    for (final p in parameter) {
      final wert = p.wert?.trim() ?? '';
      if (istVerstecktesPlattenParam(p.parameterName) || wert.isEmpty) {
        continue;
      }
      paramGruppen
          .putIfAbsent(p.parameterGruppe, () => [])
          .add((name: p.parameterName, wert: wert));
    }
    for (final (name, wert)
        in _alteMaschinenWerte(step.maschinenEinstellungenJson)) {
      paramGruppen
          .putIfAbsent(kMaschinenNotizGruppe, () => [])
          .add((name: name, wert: wert));
    }
  }
  final schrittNotiz = inhalt.notizen ? step.notizen?.trim() ?? '' : '';
  final prozessschritt = step.prozessschritt?.trim() ?? '';

  return pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(8, 6, 8, 6),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Anlage und Prozessschritt
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              pdfText(maschinenName),
              style: pw.TextStyle(
                fontSize: 10.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            if (prozessschritt.isNotEmpty) ...[
              pw.SizedBox(width: 6),
              pw.Text(
                pdfText(prozessschritt),
                style: pw.TextStyle(
                  fontSize: 8.5,
                  fontStyle: pw.FontStyle.italic,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ],
        ),

        // Kennwert-Kästen — Wrap statt Row: Bei vielen Kennwerten lief
        // die Zeile sonst über den Rand des Blocks hinaus.
        if (kennwerte.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final k in kennwerte) _kennwertBox(k.label, k.wert),
            ],
          ),
        ],

        // Plattenraster — derselbe Baustein wie im Projektbericht.
        if (kombiofen != null) ...[
          pw.SizedBox(height: 6),
          plattenRasterPdf(
            kombiofen: kombiofen,
            zonen: kombiofen ? kKombiofenZonen : kBratstrasseZonen,
            wert: (name) => _plattenWert(parameter, name),
          ),
        ],

        // Freitext „Maschineneinstellungen"
        if (notiz != null) ...[
          pw.SizedBox(height: 6),
          pw.Text(
            kMaschinenNotizGruppe,
            style: pw.TextStyle(
              fontSize: 7,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey700,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(5),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(3),
            ),
            child: pw.Text(
              pdfText(notiz),
              style: const pw.TextStyle(fontSize: 8.5),
            ),
          ),
        ],

        // Parameter nach Gruppen
        for (final g in paramGruppen.entries) ...[
          pw.SizedBox(height: 5),
          pw.Text(
            pdfText(g.key),
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
              for (final p in g.value) _parameterZeile(p.name, p.wert),
            ],
          ),
        ],

        // Notiz zum Schritt
        if (schrittNotiz.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Text(
            pdfText('Notiz: $schrittNotiz'),
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

/// Linien für Notizen von Hand.
pw.Widget _notizfeld() => pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(8, 5, 8, 8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            'NOTIZEN',
            style: pw.TextStyle(
              fontSize: 7,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey600,
              letterSpacing: 0.5,
            ),
          ),
          for (var i = 0; i < 3; i++) ...[
            pw.SizedBox(height: 16),
            pw.Container(height: 0.5, color: PdfColors.grey500),
          ],
        ],
      ),
    );

/// Werte aus dem früheren Feld für Maschineneinstellungen: JSON als
/// Liste oder Zuordnung — alter Freitext bleibt, wie er ist.
List<(String, String)> _alteMaschinenWerte(String? json) {
  final raw = json?.trim() ?? '';
  if (raw.isEmpty) return const [];
  try {
    final daten = jsonDecode(raw);
    if (daten is Map<String, dynamic>) {
      return [
        for (final MapEntry(:key, :value) in daten.entries)
          if (value != null && '$value'.trim().isNotEmpty) (key, '$value'),
      ];
    }
    if (daten is List) {
      return [
        for (final (index, value) in daten.indexed)
          if (value != null && '$value'.trim().isNotEmpty)
            ('Einstellung ${index + 1}', '$value'),
      ];
    }
  } on FormatException {
    // Alte Freitextwerte bleiben lesbar.
  }
  return [('Maschineneinstellungen', raw)];
}

/// Breite einer Parameterspalte im Druck. Zwei Spalten passen neben-
/// einander in den Schritt-Block.
const double _paramSpalte = 158;

/// Eine Parameterzeile „Bezeichnung … Wert".
///
/// Kurze Werte stehen rechts neben der Bezeichnung. Lange Werte — etwa
/// eine ganze Prozessbeschreibung unter „Sonstige Informationen" —
/// bekommen eine eigene Zeile darunter und brechen dort um.
///
/// Die Grenze ist an der Zeichenzahl festgemacht und nicht an einer
/// gemessenen Textbreite: Für „eine oder zwei Zeilen" reicht die Schätzung.
pw.Widget _parameterZeile(String name, String wert) {
  // Bezeichnung und Wert in 8 pt Helvetica passen bis etwa 38 Zeichen in
  // eine Zeile von 158 pt.
  final einzeilig = (name.length + wert.length) <= 38 && !wert.contains('\n');
  const nameStil = pw.TextStyle(fontSize: 8, color: PdfColors.grey800);
  final wertStil = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);

  if (einzeilig) {
    return pw.SizedBox(
      width: _paramSpalte,
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: pw.Text(pdfText(name), style: nameStil)),
          pw.SizedBox(width: 4),
          pw.Text(pdfText(wert), style: wertStil),
        ],
      ),
    );
  }

  // Lange Werte dürfen die volle Blockbreite nutzen und umbrechen.
  return pw.SizedBox(
    width: _paramSpalte * 2 + 10,
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(pdfText(name), style: nameStil),
        pw.SizedBox(height: 1),
        pw.Text(pdfText(wert), style: wertStil),
      ],
    ),
  );
}

pw.Widget _kennwertBox(String label, String wert) => pw.Container(
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
            pdfText(label),
            style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey600),
          ),
          pw.Text(
            pdfText(wert),
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );

// ── Plattenraster ─────────────────────────────────────────────────────

/// Welches Raster der Schritt zeigt: true der Kombiofen, false die
/// Bratstraße, null keins.
bool? _plattenTyp(List<ProductStepParameter> parameter) {
  // 1) Ausdrücklich gesetzt
  for (final p in parameter) {
    if (p.parameterName == kPlattenSchemaParam) {
      switch (p.wert) {
        case 'bratstrasse':
          return false;
        case 'kombiofen':
          return true;
        case 'keine':
          return null;
      }
    }
  }
  // 2) Aus vorhandenen Zonen abgeleitet
  final zonen = [
    for (final p in parameter)
      if (istVerstecktesPlattenParam(p.parameterName) &&
          p.parameterName != kPlattenSchemaParam &&
          p.parameterName != kMaschinenNotizParam)
        p,
  ];
  if (zonen.isEmpty) return null;
  return zonen.any(
    (p) =>
        p.parameterGruppe == kPlattenGruppeKombi ||
        p.parameterName == 'Platte Unten 11' ||
        p.parameterName == 'Platte Unten 12',
  );
}

double? _plattenWert(List<ProductStepParameter> parameter, String name) {
  for (final p in parameter) {
    if (p.parameterName == name) {
      final w = p.wert;
      if (w == null || w.trim().isEmpty) return null;
      return double.tryParse(w.replaceAll(',', '.'));
    }
  }
  return null;
}

String _fmt(num v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(1).replaceAll('.', ',');
}
