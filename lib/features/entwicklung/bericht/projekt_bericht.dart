import 'package:drift/drift.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/constants/artikel_merkmale.dart';
import '../../../core/database/database.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/pdf_text.dart';
import '../daten/dateien.dart';
import '../daten/entwicklung_repository.dart';
import '../haccp/haccp_modell.dart';
import '../haccp/prozess_modell.dart';
import '../projekte/fliessdiagramm_dateien.dart';
import '../projekte/projekt_modell.dart';
import '../rechenkern/naehrwert_rundung.dart';
import '../rechenkern/rechenkern.dart';

// Der Projektbericht als PDF: Stammdaten, Rezeptur mit Zutatenliste und
// Nährwerten, Sensorik, Prozess, HACCP, Checklisten und Verlauf — zum
// Weitergeben oder Ablegen.

/// Was im Bericht steht.
class ProjektBericht {
  const ProjektBericht({
    required this.projekt,
    this.rezepturName,
    this.version,
    this.ergebnis,
    this.verlauf = const [],
    this.bild,
    this.artikel,
    this.fliessdiagramm,
  });

  final EntwicklungsProjekt projekt;
  final String? rezepturName;

  /// Der Stand, dessen Zutatenliste und Nährwerte im Bericht stehen.
  final RezepturVersion? version;
  final RezepturErgebnis? ergebnis;

  /// Der neueste Eintrag zuerst.
  final List<ProjektEintrag> verlauf;

  /// Das Produktbild (PNG oder JPEG), entschlüsselt.
  final Uint8List? bild;

  final Product? artikel;

  /// Das Fließdiagramm mit Bezeichnung und Stand seines PDFs, etwa
  /// „FD_011 · Schnitzel paniert · Stand 31.07.2026" — null: nur die
  /// Kennung aus dem Projekt.
  final String? fliessdiagramm;
}

/// Lädt alles für den Bericht: den freigegebenen Stand, sonst den
/// neuesten abgeschlossenen, sonst den neuesten.
Future<ProjektBericht> berichtLaden(
  AppDatabase db,
  EntwicklungDateienDienst dateien,
  EntwicklungsProjekt projekt,
) async {
  final repo = EntwicklungRepository(db);
  final rezepturen = await (db.select(db.entwicklungRezepturen)
        ..where((r) => r.projektId.equals(projekt.id))
        ..where((r) => r.deletedAt.isNull()))
      .get();
  final versionen = <RezepturVersion>[];
  for (final r in rezepturen) {
    versionen.addAll(
      await (db.select(db.entwicklungRezepturVersionen)
            ..where((v) => v.rezepturId.equals(r.id)))
          .get(),
    );
  }
  RezepturVersion? version;
  for (final v in versionen) {
    if (v.id == projekt.freigabeVersionId) version = v;
  }
  if (version == null) {
    final abgeschlossen = versionen
        .where((v) => v.status == VersionStatus.abgeschlossen)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final alle = [...versionen]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    version = abgeschlossen.firstOrNull ?? alle.firstOrNull;
  }
  final eingabe =
      version == null ? null : await repo.rechenRezeptur(version.id);
  final rezepturId = version?.rezepturId;
  final rezeptur = rezepturId == null
      ? null
      : rezepturen.where((r) => r.id == rezepturId).firstOrNull;

  final verlauf = await (db.select(db.entwicklungProjektEintraege)
        ..where((e) => e.projektId.equals(projekt.id))
        ..orderBy([
          (e) => OrderingTerm.desc(e.datum),
          (e) => OrderingTerm.desc(e.createdAt),
        ]))
      .get();

  Uint8List? bild;
  final bildId = projekt.bildDateiId;
  if (bildId != null) {
    try {
      bild = await dateien.lesen(bildId);
    } catch (_) {
      bild = null;
    }
  }
  final artikelId = projekt.artikelId;
  final artikel = artikelId == null
      ? null
      : await (db.select(db.products)..where((p) => p.id.equals(artikelId)))
          .getSingleOrNull();

  return ProjektBericht(
    projekt: projekt,
    rezepturName: rezeptur?.name,
    version: version,
    ergebnis: eingabe == null ? null : berechne(eingabe),
    verlauf: verlauf,
    bild: bild,
    artikel: artikel,
    fliessdiagramm: await _fliessdiagrammText(db, projekt.fliessdiagramm),
  );
}

/// Kennung, Bezeichnung und der Stand des neuesten PDFs.
Future<String?> _fliessdiagrammText(AppDatabase db, String? fdId) async {
  if (fdId == null || fdId.isEmpty) return null;
  final fd = await (db.select(db.entwicklungFliessdiagramme)
        ..where((f) => f.id.equals(fdId)))
      .getSingleOrNull();
  final dateien = await (db.select(db.entwicklungDateien)
        ..where((d) => d.id.like('$kFdDateiPraefix%')))
      .get();
  DateTime? stand;
  for (final d in dateien) {
    final f = fdAusDateiId(d.id);
    if (f == null || f.fdId != fdId) continue;
    if (stand == null || f.stand.isAfter(stand)) stand = f.stand;
  }
  return fdText(fdId, bezeichnung: fd?.bezeichnung, stand: stand);
}

const PdfColor _grau = PdfColors.grey700;
const PdfColor _linie = PdfColors.grey400;

pw.Widget _abschnitt(String titel) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
      child: pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 3),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: _linie)),
        ),
        child: pw.Text(
          pdfText(titel.toUpperCase()),
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: _grau,
            letterSpacing: 1,
          ),
        ),
      ),
    );

pw.Widget _zeilen(List<(String, String)> paare) => pw.Table(
      columnWidths: const {
        0: pw.FixedColumnWidth(150),
        1: pw.FlexColumnWidth(),
      },
      children: [
        for (final (label, wert) in paare)
          if (wert.trim().isNotEmpty)
            pw.TableRow(
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Text(
                    pdfText(label),
                    style: const pw.TextStyle(fontSize: 9, color: _grau),
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Text(
                    pdfText(wert),
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ),
              ],
            ),
      ],
    );

pw.Widget _text(String text, {double groesse = 9, PdfColor? farbe}) =>
    pw.Text(
      pdfText(text),
      style: pw.TextStyle(fontSize: groesse, color: farbe),
    );

/// Ein Absatz, der über das Seitenende hinauslaufen darf — nur direkt in
/// der Seite, nicht in Zeilen, Spalten oder Tabellen.
pw.Widget _fliesstext(String text) => pw.Text(
      pdfText(text),
      style: const pw.TextStyle(fontSize: 9),
      overflow: pw.TextOverflow.span,
    );

/// Ein längerer Text mit Überschrift — anders als eine Tabellenzeile darf
/// er über das Seitenende hinauslaufen.
List<pw.Widget> _absatz(String titel, String? text) {
  final t = text?.trim() ?? '';
  if (t.isEmpty) return const [];
  return [
    pw.Padding(
      padding: const pw.EdgeInsets.only(top: 6, bottom: 1),
      child: _text(titel, farbe: _grau),
    ),
    _fliesstext(t),
  ];
}

String _zahl(double? w, {int nachkomma = 1}) =>
    w == null ? '' : Format.zahl(w, nachkomma: nachkomma);

/// Das Produktbild für das PDF — null, wenn es fehlt oder das Format
/// unbekannt ist.
pw.ImageProvider? _bildAus(Uint8List? bytes) {
  if (bytes == null || bytes.isEmpty) return null;
  try {
    return pw.MemoryImage(bytes);
  } catch (_) {
    return null;
  }
}

/// Baut den Bericht als PDF.
Future<Uint8List> baueProjektPdf(
  ProjektBericht b, {
  DateTime? gedrucktAm,
}) {
  final jetzt = gedrucktAm ?? DateTime.now();
  final p = b.projekt;
  final doc = pw.Document(
    title: 'Projektbericht ${p.name}',
    creator: 'Produktions Planer',
  );
  final theme = pw.ThemeData.withFont(
    base: pw.Font.helvetica(),
    bold: pw.Font.helveticaBold(),
  );

  final bild = _bildAus(b.bild);
  final artikel = b.artikel;
  final version = b.version;

  final e = b.ergebnis;
  final sensorik = Sensorik.aus(p.sensorik);
  final prozess = Prozessparameter.aus(p.prozess);
  final haccp = Haccp.aus(p.haccp);
  final erledigt = checklisteAus(p.checkliste);
  final etikett = checklisteAus(p.etikettCheckliste);
  final status = ProjektStatus.aus(p.status);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 36),
      maxPages: 200,
      theme: theme,
      footer: (ctx) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 8),
        child: _text(
          '${p.name} · Projektbericht vom ${Format.datum(jetzt)} · Seite '
          '${ctx.pageNumber}/${ctx.pagesCount}',
          groesse: 7,
          farbe: PdfColors.grey600,
        ),
      ),
      build: (ctx) => [
        // ── Kopf ──────────────────────────────────────────────────────
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _text('PROJEKTBERICHT', groesse: 9, farbe: _grau),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    pdfText(p.name),
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  if ((p.kunde ?? '').trim().isNotEmpty)
                    _text(p.kunde!.trim(), groesse: 12),
                  pw.SizedBox(height: 4),
                  _text(
                    [
                      status.label,
                      if (p.artikelnummer != null)
                        'Artikel ${p.artikelnummer}',
                      'angelegt ${Format.datum(p.createdAt)}',
                    ].join(' · '),
                    farbe: _grau,
                  ),
                ],
              ),
            ),
            if (bild != null)
              pw.Container(
                width: 140,
                height: 105,
                margin: const pw.EdgeInsets.only(left: 12),
                child: pw.Image(bild, fit: pw.BoxFit.contain),
              ),
          ],
        ),

        // ── Stammdaten ────────────────────────────────────────────────
        _abschnitt('Stammdaten'),
        _zeilen([
          ('Fließdiagramm', b.fliessdiagramm ?? p.fliessdiagramm ?? ''),
          ('Neuer Prozess', p.neuerProzess ? 'ja' : 'nein'),
          (
            'Neue Zutaten',
            p.neueZutaten
                ? 'ja${(p.neueZutatenDetails ?? '').isEmpty ? '' : ': ${p.neueZutatenDetails}'}'
                : 'nein',
          ),
          (
            'Ziel Fett',
            p.zielFett == null ? '' : 'max. ${_zahl(p.zielFett)} %',
          ),
          (
            'Ziel Eiweiß',
            p.zielEiweiss == null ? '' : 'min. ${_zahl(p.zielEiweiss)} %',
          ),
          (
            'aw-Wert',
            p.grenzeAw == null
                ? ''
                : 'max. ${_zahl(p.grenzeAw, nachkomma: 2)}',
          ),
          if (artikel != null)
            (
              'Freigegeben',
              '${artikel.artikelnummer} ${artikel.artikelbezeichnung}'
                  '${p.freigegebenAm == null ? '' : ' am ${Format.datum(p.freigegebenAm!)}'}',
            ),
        ]),
        ..._absatz('Produktidee', p.produktidee),
        ..._absatz('Kundenvereinbarungen', p.kundenvereinbarungen),
        ..._absatz('Notizen', p.notizen),

        // ── Rezeptur ──────────────────────────────────────────────────
        if (e != null && version != null) ...[
          _abschnitt(
            'Rezeptur — ${b.rezepturName ?? ''} Stand ${version.nummer}'
            '${version.status == VersionStatus.abgeschlossen ? '' : ' (Entwurf)'}',
          ),
          _fliesstext(e.zutatenliste),
          pw.SizedBox(height: 6),
          _zeilen([
            (
              'Endgewicht',
              '${_zahl(e.endgewichtKg, nachkomma: 3)} kg aus '
                  '${_zahl(e.eingesetztKg, nachkomma: 3)} kg',
            ),
            (
              'Fleischanteil',
              e.fleischanteilProzent > 0
                  ? '${_zahl(e.fleischanteilProzent)} %'
                  : '',
            ),
            if (e.je100g.beffe case final beffe?)
              (
                'BEFFE',
                '${_zahl(beffe)} %'
                    '${e.ohneBeffe.isEmpty ? '' : ' (ohne ${e.ohneBeffe.join(', ')})'}',
              ),
            (
              'Allergene',
              e.allergene.isEmpty
                  ? 'keine'
                  : merkmaleLabel(e.allergene.keys.join(','), kAllergene),
            ),
            (
              'Verarbeitungshilfsstoffe',
              e.verarbeitungshilfsstoffe.keys.join(', '),
            ),
          ]),
          pw.SizedBox(height: 6),
          _text('Nährwerte je 100 g', farbe: _grau),
          pw.SizedBox(height: 2),
          _zeilen([
            for (final s in Naehrstoff.values)
              (
                '${s.label} (${s.einheit})',
                naehrwertGerundet(s, naehrstoffWert(e.je100g, s)),
              ),
          ]),
          if (e.warnungen.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            for (final w in e.warnungen)
              _text('Hinweis: $w', groesse: 8, farbe: PdfColors.orange800),
          ],
        ],

        // ── Sensorik ──────────────────────────────────────────────────
        if (!sensorik.leer) ...[
          _abschnitt('Sensorik'),
          _zeilen([
            ('Aussehen', sensorik.aussehen),
            ('Geruch', sensorik.geruch),
            ('Geschmack', sensorik.geschmack),
            ('Konsistenz', sensorik.konsistenz),
            ('Länge', sensorik.laenge),
            ('Durchmesser', sensorik.durchmesser),
            ('Stückgewicht', sensorik.gewicht),
            ('Zubereitung', sensorik.zubereitung),
          ]),
        ],

        // ── Prozess ───────────────────────────────────────────────────
        if (!prozess.leer) ...[
          _abschnitt('Prozessparameter — Version ${prozess.version}'),
          for (final a in prozess.abschnitte) ...[
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4, bottom: 2),
              child: pw.Text(
                pdfText(a.titel),
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            _zeilen([for (final f in a.felder) (f.label, f.wert)]),
          ],
        ],

        // ── HACCP ─────────────────────────────────────────────────────
        if (!haccp.leer) ...[
          _abschnitt('HACCP'),
          for (final g in haccp.gefahren)
            _text(
              '${g.gefahr} (${g.art.label}) — Risiko ${g.risiko} '
              '(${g.schwere} × ${g.wahrscheinlichkeit})'
              '${g.massnahmen.trim().isEmpty ? '' : ': ${g.massnahmen.trim()}'}',
            ),
          if (haccp.lenkungspunkte.isNotEmpty) pw.SizedBox(height: 4),
          for (final l in haccp.lenkungspunkte)
            _text(
              '${l.ergebnis.kuerzel} — ${l.schritt}'
              '${l.lenkung.trim().isEmpty ? '' : ': ${l.lenkung.trim()}'}',
            ),
        ],

        // ── Checklisten ───────────────────────────────────────────────
        _abschnitt('Checklisten'),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  for (final c in kProjektCheckliste)
                    _text(
                      '${erledigt.contains(c.schluessel) ? '[x]' : '[ ]'} '
                      '${c.label}',
                    ),
                ],
              ),
            ),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  for (final c in kEtikettCheckliste)
                    _text(
                      '${etikett.contains(c.schluessel) ? '[x]' : '[ ]'} '
                      '${c.label}',
                    ),
                ],
              ),
            ),
          ],
        ),

        // ── Verlauf ───────────────────────────────────────────────────
        if (b.verlauf.isNotEmpty) ...[
          _abschnitt('Verlauf'),
          for (final v in b.verlauf) ...[
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Text(
                pdfText(
                  '${Format.datum(v.datum)} · '
                  '${EintragArt.aus(v.art).label} · ${v.titel} '
                  '(${EintragStatus.aus(v.status).label})',
                ),
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            if ((v.beschreibung ?? '').trim().isNotEmpty)
              _fliesstext(v.beschreibung!.trim()),
            for (final a in texteAus(v.aenderungen))
              _text('- $a', groesse: 8, farbe: _grau),
            for (final k in Kommentar.listeAus(v.kommentare))
              _text(
                '${k.name.isEmpty ? '' : '${k.name}: '}${k.text}',
                groesse: 8,
                farbe: _grau,
              ),
          ],
        ],
      ],
    ),
  );
  return doc.save();
}
