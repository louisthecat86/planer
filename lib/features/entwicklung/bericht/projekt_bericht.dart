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
import '../projekte/entwicklungsstrang.dart';
import '../projekte/fliessdiagramm_dateien.dart';
import '../projekte/projekt_checkliste.dart';
import '../projekte/projekt_modell.dart';
import '../rechenkern/naehrwert_rundung.dart';
import '../rechenkern/rechenkern.dart';

// Der Projektbericht als PDF: Stammdaten, Rezeptur mit Zutatenliste und
// Nährwerten, Sensorik, Prozess, HACCP, Checklisten und der
// Entwicklungsweg — von der Idee über jede Station bis zur Freigabe. Zum
// Weitergeben oder Ablegen.

/// Ein Stand, der gerade in Arbeit ist.
typedef InArbeit = ({String rezeptur, RezepturVersion version});

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
    this.checkliste,
    this.versionen = const {},
    this.kennzahlen = const {},
    this.inArbeit = const [],
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

  /// Die Projekt-Checkliste, wie sie gerade steht — null: aus dem Projekt
  /// allein gerechnet (ohne Rezepturen).
  final ProjektCheckStand? checkliste;

  /// Die Rezepturstände, um die es im Verlauf geht, nach ID.
  final Map<String, RezepturVersion> versionen;

  /// Je Station (Stand-ID) die Kennzahlen mit der Änderung zum vorigen
  /// Stand derselben Rezeptur.
  final Map<String, List<WegKennzahl>> kennzahlen;

  /// Stände, die noch nicht abgeschlossen sind — der älteste zuerst.
  final List<InArbeit> inArbeit;
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

  // Der Entwicklungsweg: die Stände seiner Stationen und Phasen — auch
  // solche, deren Rezeptur nicht mehr zum Projekt gehört.
  final versionenNachId = {for (final v in versionen) v.id: v};
  final weg = entwicklungsweg(verlauf);
  final stationen = weg.whereType<WegStation>().toList();
  for (final id in {
    for (final s in stationen) s.versionId,
    for (final w in weg.whereType<WegPhase>())
      if (w.eintrag.versionId case final id?) id,
  }) {
    if (versionenNachId.containsKey(id)) continue;
    final v = await repo.version(id);
    if (v != null) versionenNachId[id] = v;
  }
  // Die Kennzahlen jeder Station mit der Änderung zur vorigen Station
  // derselben Rezeptur — wie in der Ansicht „Entwicklungsweg".
  final ergebnisse = <String, RezepturErgebnis>{};
  for (final s in stationen) {
    final e = await repo.rechenRezeptur(s.versionId);
    if (e != null) ergebnisse[s.versionId] = berechne(e);
  }
  final kennzahlen = <String, List<WegKennzahl>>{};
  final letzte = <String, String>{};
  for (final s in stationen) {
    final rezepturId = versionenNachId[s.versionId]?.rezepturId;
    final davor = rezepturId == null ? null : letzte[rezepturId];
    final neu = ergebnisse[s.versionId];
    if (neu != null) {
      kennzahlen[s.versionId] = wegKennzahlen(
        neu,
        vorher: davor == null ? null : ergebnisse[davor],
      );
    }
    if (rezepturId != null) letzte[rezepturId] = s.versionId;
  }
  final stationIds = {for (final s in stationen) s.versionId};
  final namen = {for (final r in rezepturen) r.id: r.name};
  final inArbeit = <InArbeit>[
    for (final v in versionen)
      if (v.status == VersionStatus.entwurf && !stationIds.contains(v.id))
        (rezeptur: namen[v.rezepturId] ?? '', version: v),
  ]..sort((a, b) => a.version.updatedAt.compareTo(b.version.updatedAt));

  return ProjektBericht(
    projekt: projekt,
    rezepturName: rezeptur?.name,
    version: version,
    ergebnis: eingabe == null ? null : berechne(eingabe),
    verlauf: verlauf,
    bild: bild,
    artikel: artikel,
    fliessdiagramm: await _fliessdiagrammText(db, projekt.fliessdiagramm),
    checkliste: projektCheckStand(
      projekt: projekt,
      rezepturen: rezepturen,
      versionen: versionen,
    ),
    versionen: versionenNachId,
    kennzahlen: kennzahlen,
    inArbeit: inArbeit,
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
/// der Seite (auch eingerückt in einem Padding), nicht in Zeilen, Spalten
/// oder Tabellen.
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

/// Die Farbe einer Phase.
PdfColor _phasenFarbe(ProjektStatus s) => switch (s) {
      ProjektStatus.entwicklung => PdfColors.blue800,
      ProjektStatus.validierung => PdfColors.orange800,
      ProjektStatus.produktion => PdfColors.green800,
      ProjektStatus.archiviert => PdfColors.grey700,
    };

/// Die Farbe der Stationen — wie die Rezepturstände im Zeitstrahl.
const PdfColor _stationFarbe = PdfColor.fromInt(0xFF7E3FB8);

/// Ein Eintrag des Verlaufs: Kopfzeile, Beschreibung, Änderungen und
/// Kommentare; offene Einträge sind markiert. [einzug] rückt ihn unter
/// seine Station.
List<pw.Widget> _eintrag(ProjektEintrag e, {double einzug = 0}) {
  pw.Widget eingerueckt(pw.Widget w) => einzug == 0
      ? w
      : pw.Padding(padding: pw.EdgeInsets.only(left: einzug), child: w);
  final offen = EintragStatus.aus(e.status) == EintragStatus.offen;
  final beschreibung = e.beschreibung?.trim() ?? '';
  return [
    eingerueckt(
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 4),
        child: pw.Text(
          pdfText(
            '${Format.datum(e.datum)} · ${EintragArt.aus(e.art).label} · '
            '${e.titel}${offen ? ' (offen)' : ''}',
          ),
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        ),
      ),
    ),
    if (beschreibung.isNotEmpty) eingerueckt(_fliesstext(beschreibung)),
    for (final a in texteAus(e.aenderungen))
      eingerueckt(_text('- $a', groesse: 8, farbe: _grau)),
    for (final k in Kommentar.listeAus(e.kommentare))
      eingerueckt(
        _text(
          '${k.name.isEmpty ? '' : '${k.name}: '}${k.text}',
          groesse: 8,
          farbe: _grau,
        ),
      ),
  ];
}

/// Der Entwicklungsweg — von oben nach unten: die Idee mit dem, was vor
/// dem ersten Stand geschah, dann jede Station (ein abgeschlossener
/// Rezepturstand) mit Grund, Änderungen, Kennzahlen und dem, was danach
/// kam, dazwischen die Wechsel der Phase; am Ende, was in Arbeit ist.
List<pw.Widget> _entwicklungsweg(ProjektBericht b) {
  final p = b.projekt;
  final kunde = p.kunde?.trim() ?? '';
  final widgets = <pw.Widget>[];
  final weg = entwicklungsweg(b.verlauf);
  for (final punkt in weg) {
    switch (punkt) {
      case WegAnfang(:final eintraege):
        widgets.add(
          pw.Text(
            pdfText(
              [
                'Idee und Anfrage',
                'seit ${Format.datum(p.createdAt)}',
                if (kunde.isNotEmpty) kunde,
              ].join(' · '),
            ),
            style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
          ),
        );
        for (final e in eintraege) {
          widgets.addAll(_eintrag(e, einzug: 10));
        }
      case WegStation():
        final e = punkt.eintrag;
        final beschreibung = e.beschreibung?.trim() ?? '';
        final kennzahlen = b.kennzahlen[punkt.versionId] ?? const [];
        widgets.addAll([
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 10),
            child: pw.Text(
              pdfText('Station ${punkt.nummer} · ${e.titel}'),
              style: pw.TextStyle(
                fontSize: 10.5,
                fontWeight: pw.FontWeight.bold,
                color: _stationFarbe,
              ),
            ),
          ),
          _text(
            [
              Format.datum(e.datum),
              if (p.freigabeVersionId == punkt.versionId) 'freigegeben',
            ].join(' · '),
            groesse: 8,
            farbe: _grau,
          ),
          if (beschreibung.isNotEmpty) _fliesstext(beschreibung),
          for (final a in texteAus(e.aenderungen)) _text('- $a', groesse: 8.5),
          if (kennzahlen.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 3),
              child: _text(
                [
                  for (final k in kennzahlen)
                    '${k.label} ${k.wert}'
                        '${k.aenderung == null ? '' : ' (${k.aenderung})'}',
                ].join(' · '),
                groesse: 8,
                farbe: _grau,
              ),
            ),
          for (final k in Kommentar.listeAus(e.kommentare))
            _text(
              '${k.name.isEmpty ? '' : '${k.name}: '}${k.text}',
              groesse: 8,
              farbe: _grau,
            ),
        ]);
        if (punkt.rueckmeldungen.isNotEmpty) {
          widgets.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4),
              child: _text('Danach', groesse: 8, farbe: _grau),
            ),
          );
          for (final r in punkt.rueckmeldungen) {
            widgets.addAll(_eintrag(r, einzug: 10));
          }
        }
      case WegPhase():
        final e = punkt.eintrag;
        final stand = b.versionen[e.versionId]?.nummer;
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 10),
            child: pw.Text(
              pdfText(
                [
                  e.titel,
                  if (stand != null) 'Stand $stand',
                  Format.datum(e.datum),
                ].join(' · '),
              ),
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: _phasenFarbe(punkt.status),
              ),
            ),
          ),
        );
        for (final a in texteAus(e.aenderungen)) {
          widgets.add(_text('- $a', groesse: 8, farbe: _grau));
        }
    }
  }
  if (!weg.any((w) => w is WegStation)) {
    widgets.add(
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 8),
        child: _text('Noch kein abgeschlossener Stand.', farbe: _grau),
      ),
    );
  }
  for (final a in b.inArbeit) {
    widgets.add(
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 8),
        child: _text(
          'In Arbeit: ${a.rezeptur} · Stand ${a.version.nummer} (Entwurf)',
          farbe: _grau,
        ),
      ),
    );
  }
  return widgets;
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
  final checkliste = b.checkliste ??
      projektCheckStand(projekt: p, rezepturen: const [], versionen: const []);
  final etikett = checklisteAus(p.etikettCheckliste);
  final etikettErledigt =
      kEtikettCheckliste.where((c) => etikett.contains(c.schluessel)).length;
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
              flex: 3,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _text(
                    'Projekt · ${checkliste.text} erledigt',
                    farbe: _grau,
                  ),
                  pw.SizedBox(height: 2),
                  for (final c in checkliste.punkte)
                    _text(
                      '${c.erledigt ? '[x]' : '[ ]'} ${c.punkt.label}'
                      '${c.vonHand ? ' (von Hand)' : c.text == null ? '' : ': ${c.text}'}',
                    ),
                ],
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              flex: 2,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _text(
                    'Etikett (LMIV) · $etikettErledigt von '
                    '${kEtikettCheckliste.length} erledigt',
                    farbe: _grau,
                  ),
                  pw.SizedBox(height: 2),
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

        // ── Entwicklungsweg ───────────────────────────────────────────
        if (b.verlauf.isNotEmpty || b.inArbeit.isNotEmpty) ...[
          _abschnitt('Entwicklungsweg'),
          ..._entwicklungsweg(b),
        ],
      ],
    ),
  );
  return doc.save();
}
