import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'
    show ScaffoldMessengerState, SnackBar, Text;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/constants/artikel_merkmale.dart';
import '../../core/database/database.dart';
import '../../core/services/auftragsbestand_deckung.dart'
    show
        AuftragsBezug,
        kQuelleAuftragsbestand,
        ladeBedarfsPlanung,
        restBezuege;
import '../../core/utils/pdf_text.dart';
import '../whiteboard/whiteboard_provider.dart'
    show berechneSchrittPlan, ermittleAusbeute;

// ═══════════════════════════════════════════════════════════════════════
// Inhalt
// ═══════════════════════════════════════════════════════════════════════

/// Wofür der Tag auf dem Blatt steht.
enum DatenblattTag {
  /// Der Tag, an dem produziert wird.
  produktion,

  /// Der Tag, an dem eine mehrtägige Kette fertig wird (letzter Schritt).
  fertig,

  /// Der späteste Produktionstag — die Produktion hat noch keinen Tag.
  spaetestens,
}

/// Ein Abteilungsschritt auf dem Blatt.
class DatenblattSchritt {
  const DatenblattSchritt({
    required this.abteilung,
    this.tag,
    this.mengeKg,
    this.dauerMinuten,
  });

  /// Anzeigename der Abteilung.
  final String abteilung;
  final DateTime? tag;

  /// Eingangsmenge des Schritts.
  final double? mengeKg;
  final double? dauerMinuten;
}

/// Alles, was auf ein Datenblatt kommt: welcher Artikel, wie viel, bis
/// wann, für welche Aufträge.
///
/// Das Blatt begleitet eine gebündelte Planung in die Produktion — etwa
/// den Kochschinken für drei Versandtage.
class Datenblatt {
  const Datenblatt({
    required this.artikelnummer,
    required this.bezeichnung,
    this.bezeichnung2,
    this.fertigKg,
    this.fertigGeschaetzt = false,
    this.rohwareKg,
    this.ausbeuteProzent,
    this.tag,
    this.tagArt = DatenblattTag.produktion,
    this.status,
    this.bezuege = const [],
    this.merkmale = const [],
    this.schritte = const [],
    this.haltbarkeitTage,
    this.notiz,
  });

  final String artikelnummer;
  final String bezeichnung;
  final String? bezeichnung2;

  /// Zu produzierende Fertigware. null, wenn in Rohware geplant und die
  /// Ausbeute unbekannt ist.
  final double? fertigKg;

  /// [fertigKg] ist aus der Rohware über die Ausbeute geschätzt — die
  /// Kette wurde ohne Fertigmenge geplant.
  final bool fertigGeschaetzt;

  /// Benötigte Rohware, soweit bekannt.
  final double? rohwareKg;

  /// Ausbeute, mit der gerechnet wurde, in Prozent.
  final double? ausbeuteProzent;

  final DateTime? tag;
  final DatenblattTag tagArt;

  /// Stand der Planung, z.B. „Beim Planungsvorschlag vorgemerkt".
  final String? status;

  /// Die gebündelten Auftragszeilen.
  final List<AuftragsBezug> bezuege;

  /// Merkmale aus den Stammdaten, z.B. „Allergene: Eier, Milch".
  final List<String> merkmale;

  /// Abteilungen in Produktionsreihenfolge mit Menge und Dauer, bei einem
  /// festen Produktionstag auch mit Tag.
  final List<DatenblattSchritt> schritte;

  /// Haltbarkeit laut Stammdaten.
  final int? haltbarkeitTage;

  final String? notiz;

  /// Mindesthaltbarkeit: Produktions- bzw. Fertigtag plus Haltbarkeit. Nur,
  /// wenn beides bekannt ist — bei „spätestens" steht der Tag noch nicht
  /// fest.
  DateTime? get mhd {
    final t = tag;
    final h = haltbarkeitTage;
    if (t == null || h == null || h <= 0) return null;
    if (tagArt == DatenblattTag.spaetestens) return null;
    return DateTime(t.year, t.month, t.day + h);
  }

  double get auftragKg => bezuege.fold<double>(0, (s, b) => s + b.kg);
}

// ═══════════════════════════════════════════════════════════════════════
// Laden
// ═══════════════════════════════════════════════════════════════════════

/// Datenblatt für eine Menge eines Artikels, die noch keine Kette im Board
/// hat — etwa ein Posten des Planungsvorschlags oder ein Bedarf.
///
/// Rohware, Menge und Dauer je Abteilung rechnet dieselbe Planung wie
/// beim Einplanen ([berechneSchrittPlan]); das Blatt zeigt also, was das
/// Board später anlegt. Die Tage der Abteilungen stehen nur drauf, wenn
/// [tag] der Produktionstag ist.
///
/// null, wenn es den Artikel nicht gibt.
Future<Datenblatt?> datenblattFuerMenge(
  AppDatabase db, {
  required String productId,
  required double fertigKg,
  DateTime? tag,
  DatenblattTag tagArt = DatenblattTag.produktion,
  List<AuftragsBezug> bezuege = const [],
  String? status,
  String? notiz,
}) async {
  final produkt = await (db.select(db.products)
        ..where((p) => p.id.equals(productId)))
      .getSingleOrNull();
  if (produkt == null) return null;

  final mitTag = tag != null && tagArt != DatenblattTag.spaetestens;
  final plan = await berechneSchrittPlan(
    db: db,
    productId: productId,
    mengeKg: fertigKg,
    startTag: tag ?? DateTime.now(),
  );
  // Ohne Prozessschritte rechnet der Plan nichts aus — eine Ausbeute kann
  // es aus den erfassten Produktionen trotzdem geben.
  final ausbeute = plan.schritte.isEmpty
      ? await ermittleAusbeute(db, productId)
      : plan.ausbeute;

  return Datenblatt(
    artikelnummer: produkt.artikelnummer,
    bezeichnung: produkt.artikelbezeichnung,
    bezeichnung2: produkt.beschreibung,
    fertigKg: fertigKg,
    rohwareKg: ausbeute.bekannt ? ausbeute.rohAusFertig(fertigKg) : null,
    ausbeuteProzent: ausbeute.bekannt ? ausbeute.faktor * 100 : null,
    tag: tag,
    tagArt: tagArt,
    status: status,
    bezuege: bezuege,
    merkmale: _merkmale(produkt),
    schritte: [
      for (final s in plan.schritte)
        DatenblattSchritt(
          abteilung: _abteilungName(s.abteilungDbValue),
          tag: mitTag ? s.tag : null,
          mengeKg: s.mengeKg,
          dauerMinuten: s.dauerMinuten,
        ),
    ],
    haltbarkeitTage: produkt.haltbarkeitTage,
    notiz: notiz,
  );
}

/// Datenblatt für einen Bedarf — vor allem für einen Planungsauftrag aus
/// dem Auftragsbestand.
///
/// * Ohne [nurOffen]: der ganze Bedarf mit allen Auftragszeilen und dem
///   Termin als spätestem Produktionstag.
/// * Mit [nurOffen]: nur der Teil, der noch nicht im Board steht, mit den
///   Zeilen, die noch keine Produktion trägt — so, wie ihn der
///   Auftragsbestand als vorgemerkt zeigt.
///
/// null, wenn es den Bedarf oder seinen Artikel nicht gibt.
Future<Datenblatt?> datenblattFuerBedarf(
  AppDatabase db,
  String bedarfId, {
  bool nurOffen = false,
}) async {
  final bedarf = await (db.select(db.demands)
        ..where((d) => d.id.equals(bedarfId)))
      .getSingleOrNull();
  if (bedarf == null) return null;

  final planung = (await ladeBedarfsPlanung(db))[bedarf.id];
  final eingeplant = planung?.kg ?? 0;
  final alle = AuftragsBezug.dekodiere(bedarf.auftragsZeilen);

  final double fertig;
  final List<AuftragsBezug> bezuege;
  final String status;
  if (nurOffen) {
    final offen = bedarf.mengeKgFertig - eingeplant;
    fertig = offen > 0 ? offen : 0;
    bezuege = restBezuege(alle, planung?.bezuege ?? const []);
    status = eingeplant >= 0.5
        ? 'Beim Planungsvorschlag vorgemerkt · ${_kg(eingeplant)} kg davon '
            'stehen schon im Board'
        : 'Beim Planungsvorschlag vorgemerkt · noch nicht im Board';
  } else {
    fertig = bedarf.mengeKgFertig;
    bezuege = alle;
    status = eingeplant >= 0.5
        ? 'Davon im Board eingeplant: ${_kg(eingeplant)} kg'
        : 'Noch nicht im Board eingeplant';
  }

  // Bei einem Planungsauftrag stehen in den Notizen nur die gebündelten
  // Aufträge — die zeigt das Blatt ohnehin als Tabelle.
  final notiz = bedarf.quelle == kQuelleAuftragsbestand
      ? null
      : bedarf.notizen?.trim();

  return datenblattFuerMenge(
    db,
    productId: bedarf.productId,
    fertigKg: fertig,
    tag: bedarf.termin,
    tagArt: DatenblattTag.spaetestens,
    bezuege: bezuege,
    status: status,
    notiz: (notiz == null || notiz.isEmpty) ? null : notiz,
  );
}

/// Datenblatt für eine Produktion im Board — die ganze Kette, zu der der
/// Schritt [taskId] gehört: Menge, Tage je Abteilung und die
/// Auftragszeilen, für die sie eingeplant ist.
///
/// Die Wurzel wird auch über gelöschte Schritte gefunden: Fertigmenge und
/// Auftragszeilen stehen dort, selbst wenn der erste Schritt im Board
/// entfernt wurde.
///
/// null, wenn es den Schritt nicht gibt oder von der Kette nichts mehr im
/// Board steht.
Future<Datenblatt?> datenblattFuerKette(AppDatabase db, String taskId) async {
  final start = await (db.select(db.productionTasks)
        ..where((t) => t.id.equals(taskId)))
      .getSingleOrNull();
  if (start == null) return null;
  // Bewusst auch gelöschte und stornierte: Sie verbinden die Kette.
  final alle = await (db.select(db.productionTasks)
        ..where((t) => t.productId.equals(start.productId)))
      .get();
  final jeId = {for (final t in alle) t.id: t};

  var wurzel = start;
  final besucht = <String>{wurzel.id};
  while (true) {
    final elternId = wurzel.parentTaskId;
    final eltern = elternId == null ? null : jeId[elternId];
    if (eltern == null || !besucht.add(eltern.id)) break;
    wurzel = eltern;
  }

  // Alle Nachfahren der Wurzel mit ihrem Abstand zu ihr — für die
  // Reihenfolge innerhalb eines Tages.
  final tiefe = <String, int>{wurzel.id: 0};
  var geaendert = true;
  while (geaendert) {
    geaendert = false;
    for (final t in alle) {
      final p = t.parentTaskId;
      if (p == null || tiefe.containsKey(t.id)) continue;
      final elternTiefe = tiefe[p];
      if (elternTiefe == null) continue;
      tiefe[t.id] = elternTiefe + 1;
      geaendert = true;
    }
  }
  final schritte = [
    for (final t in alle)
      if (tiefe.containsKey(t.id) &&
          t.deletedAt == null &&
          t.status != 'storniert')
        t,
  ]..sort((a, b) {
      final d = a.datum.compareTo(b.datum);
      return d != 0 ? d : tiefe[a.id]!.compareTo(tiefe[b.id]!);
    });
  if (schritte.isEmpty) return null;

  final produkt = await (db.select(db.products)
        ..where((p) => p.id.equals(start.productId)))
      .getSingleOrNull();
  if (produkt == null) return null;

  final roh = wurzel.mengeKg;
  var fertig = wurzel.fertigMengeKg;
  var geschaetzt = false;
  if ((fertig == null || fertig <= 0) && roh > 0) {
    // In Rohware geplant: Fertigware über die Ausbeute schätzen, wenn
    // eine bekannt ist.
    final ausbeute = await ermittleAusbeute(db, produkt.id);
    if (ausbeute.bekannt) {
      fertig = ausbeute.fertigAusRoh(roh);
      geschaetzt = true;
    }
  }
  final beginn = schritte.first.datum;
  final ende = schritte.last.datum;
  final mehrtaegig = !_gleicherTag(beginn, ende);

  var status = 'Eingeplant im Board';
  if (mehrtaegig) status = '$status · Beginn ${_tagLang(beginn)}';
  final bedarfId = wurzel.bedarfId;
  if (bedarfId != null) {
    final bedarf = await (db.select(db.demands)
          ..where((d) => d.id.equals(bedarfId)))
        .getSingleOrNull();
    final termin = bedarf?.termin;
    if (termin != null) {
      status = '$status · Termin spätestens ${_datumLang(termin)}';
    }
  }

  return Datenblatt(
    artikelnummer: produkt.artikelnummer,
    bezeichnung: produkt.artikelbezeichnung,
    bezeichnung2: produkt.beschreibung,
    fertigKg: fertig != null && fertig > 0 ? fertig : null,
    fertigGeschaetzt: geschaetzt,
    rohwareKg: roh > 0 ? roh : null,
    ausbeuteProzent: fertig != null && fertig > 0 && roh > 0
        ? fertig / roh * 100
        : null,
    // Bei einer mehrtägigen Kette zählt der Tag, an dem die Ware fertig
    // wird — ab dann läuft die Haltbarkeit.
    tag: ende,
    tagArt: mehrtaegig ? DatenblattTag.fertig : DatenblattTag.produktion,
    status: status,
    bezuege: AuftragsBezug.dekodiere(wurzel.auftragsZeilen),
    merkmale: _merkmale(produkt),
    schritte: [
      for (final s in schritte)
        DatenblattSchritt(
          abteilung: _abteilungName(s.abteilung),
          tag: s.datum,
          mengeKg: s.mengeKg,
          dauerMinuten: s.geplanteDauerMinuten,
        ),
    ],
    haltbarkeitTage: produkt.haltbarkeitTage,
  );
}

List<String> _merkmale(Product p) {
  final allergene = merkmaleAusText(p.allergene);
  final qualitaet = merkmalLabel(p.qualitaetsstufe, kQualitaetsstufen);
  final verarbeitung =
      merkmaleLabel(p.verarbeitungsstufe, kVerarbeitungsstufen);
  return [
    if (allergene.isEmpty)
      'Allergene: nicht gepflegt'
    else if (allergene.contains(kAllergenKeine))
      'Allergene: keine'
    else
      'Allergene: ${merkmaleLabel(p.allergene, kAllergene)}',
    if (qualitaet != null) qualitaet,
    if (verarbeitung.isNotEmpty) verarbeitung,
  ];
}

/// Anzeigename einer Abteilung — ein unbekannter Wert bleibt stehen, statt
/// das ganze Blatt scheitern zu lassen.
String _abteilungName(String dbValue) {
  try {
    return Abteilung.fromDbValue(dbValue).anzeigeName;
  } catch (_) {
    return dbValue;
  }
}

bool _gleicherTag(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

// ═══════════════════════════════════════════════════════════════════════
// Drucken
// ═══════════════════════════════════════════════════════════════════════

/// Öffnet die Druckvorschau mit einem Blatt je Eintrag.
Future<void> druckeDatenblaetter(List<Datenblatt> blaetter) async {
  if (blaetter.isEmpty) return;
  final bytes = await baueDatenblattPdf(blaetter);
  final name = blaetter.length == 1
      ? 'Datenblatt_${blaetter.single.artikelnummer}'
      : 'Datenblaetter';
  await Printing.layoutPdf(name: name, onLayout: (_) async => bytes);
}

/// Lädt die Blätter über [laden] und öffnet die Druckvorschau. Fehlt die
/// Planung inzwischen oder scheitert etwas, steht es als Meldung da.
///
/// [messenger] holt der Aufrufer vor der ersten Wartestelle
/// (`ScaffoldMessenger.of(context)`) — so hängt nichts an einem
/// BuildContext, der nach dem Laden vielleicht nicht mehr lebt.
Future<void> druckeDatenblaetterMitMeldung(
  ScaffoldMessengerState messenger,
  Future<List<Datenblatt>> Function() laden,
) async {
  try {
    final blaetter = await laden();
    if (blaetter.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Kein Datenblatt — diese Planung gibt es nicht mehr. Bitte die '
            'Ansicht neu laden.',
          ),
        ),
      );
      return;
    }
    await druckeDatenblaetter(blaetter);
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text('Das Datenblatt ließ sich nicht erstellen. ($e)'),
      ),
    );
  }
}

/// Ein einzelnes Blatt als Liste für [druckeDatenblaetterMitMeldung] —
/// leer, wenn es fehlt.
Future<List<Datenblatt>> alsListe(Future<Datenblatt?> blatt) async {
  final b = await blatt;
  return b == null ? const <Datenblatt>[] : [b];
}

/// Baut das PDF — ohne Drucken, damit es sich prüfen lässt.
Future<Uint8List> baueDatenblattPdf(
  List<Datenblatt> blaetter, {
  DateTime? gedrucktAm,
}) {
  final jetzt = gedrucktAm ?? DateTime.now();
  final doc = pw.Document(title: 'Datenblatt', creator: 'Produktion Planer');
  final theme = pw.ThemeData.withFont(
    base: pw.Font.helvetica(),
    bold: pw.Font.helveticaBold(),
  );
  for (final b in blaetter) {
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 32),
        theme: theme,
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            pdfText(
              '${b.artikelnummer} ${b.bezeichnung} · Seite '
              '${ctx.pageNumber}/${ctx.pagesCount}',
            ),
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
          ),
        ),
        build: (ctx) => _seite(b, jetzt),
      ),
    );
  }
  return doc.save();
}

List<pw.Widget> _seite(Datenblatt b, DateTime jetzt) {
  const grau = PdfColors.grey700;
  final mhd = b.mhd;
  final tag = b.tag;
  final tagLabel = switch (b.tagArt) {
    DatenblattTag.produktion => 'Produktionstag',
    DatenblattTag.fertig => 'Fertig am',
    DatenblattTag.spaetestens => 'Spätestens produzieren',
  };
  final fertigLabel = b.fertigGeschaetzt
      ? 'Zu produzieren (Fertigware, geschätzt)'
      : 'Zu produzieren (Fertigware)';

  final mitTag = b.schritte.any((s) => s.tag != null);
  final mitMenge = b.schritte.any((s) => s.mengeKg != null);
  final mitDauer = b.schritte.any((s) => s.dauerMinuten != null);

  return [
    // ── Kopf ────────────────────────────────────────────────────────────
    pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'DATENBLATT PRODUKTION',
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: grau,
            letterSpacing: 1.2,
          ),
        ),
        pw.Text(
          pdfText('Gedruckt ${_datumLang(jetzt)} ${_uhrzeit(jetzt)}'),
          style: const pw.TextStyle(fontSize: 8, color: grau),
        ),
      ],
    ),
    pw.SizedBox(height: 10),
    pw.Text(
      pdfText(b.artikelnummer),
      style: pw.TextStyle(fontSize: 30, fontWeight: pw.FontWeight.bold),
    ),
    pw.Text(
      pdfText(b.bezeichnung),
      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
    ),
    if ((b.bezeichnung2 ?? '').trim().isNotEmpty)
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 2),
        child: pw.Text(
          pdfText(b.bezeichnung2!.trim()),
          maxLines: 3,
          style: const pw.TextStyle(fontSize: 11, color: grau),
        ),
      ),
    pw.SizedBox(height: 14),

    // ── Mengen und Tag ──────────────────────────────────────────────────
    pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey800, width: 1.2),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 3,
            child: _feld(
              fertigLabel,
              b.fertigKg == null ? 'unbekannt' : '${_kg(b.fertigKg!)} kg',
              gross: true,
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: _feld(
              'Rohware (ca.)',
              b.rohwareKg == null ? '-' : '${_kg(b.rohwareKg!)} kg',
              zusatz: b.ausbeuteProzent == null
                  ? 'Ausbeute unbekannt'
                  : 'Ausbeute ${_prozent(b.ausbeuteProzent!)} %',
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: _feld(
              tagLabel,
              tag == null ? 'ohne Termin' : _datumLang(tag),
              zusatz: tag == null ? null : _wochentagLang(tag),
            ),
          ),
        ],
      ),
    ),
    if (b.status != null) ...[
      pw.SizedBox(height: 6),
      pw.Text(
        pdfText(b.status!),
        style: const pw.TextStyle(fontSize: 9, color: grau),
      ),
    ],
    pw.SizedBox(height: 12),

    // ── Merkmale ────────────────────────────────────────────────────────
    if (b.merkmale.isNotEmpty || b.haltbarkeitTage != null)
      pw.Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final m in b.merkmale) _chip(m),
          if (b.haltbarkeitTage != null)
            _chip(
              mhd == null
                  ? 'Haltbarkeit ${b.haltbarkeitTage} Tage'
                  : 'Haltbarkeit ${b.haltbarkeitTage} Tage · MHD ca. '
                      '${_datumLang(mhd)}',
            ),
        ],
      ),
    if (b.notiz != null) ...[
      pw.SizedBox(height: 8),
      pw.Text(
        pdfText('Notiz: ${b.notiz}'),
        style: const pw.TextStyle(fontSize: 9),
      ),
    ],

    // ── Abteilungen ─────────────────────────────────────────────────────
    if (b.schritte.isNotEmpty) ...[
      pw.SizedBox(height: 16),
      _ueberschrift('Ablauf'),
      pw.SizedBox(height: 4),
      _tabelle(
        kopf: [
          'Abteilung',
          if (mitTag) 'Tag',
          if (mitMenge) 'Menge',
          if (mitDauer) 'Dauer',
        ],
        breiten: [3, if (mitTag) 2, if (mitMenge) 2, if (mitDauer) 2],
        rechtsAb: 1 + (mitTag ? 1 : 0),
        zeilen: [
          for (final s in b.schritte)
            [
              s.abteilung,
              if (mitTag) s.tag == null ? '-' : _tagKurz(s.tag!),
              if (mitMenge) s.mengeKg == null ? '-' : '${_kg(s.mengeKg!)} kg',
              if (mitDauer)
                s.dauerMinuten == null ? '-' : _dauer(s.dauerMinuten!),
            ],
        ],
      ),
    ],

    // ── Aufträge ────────────────────────────────────────────────────────
    if (b.bezuege.isNotEmpty) ...[
      pw.SizedBox(height: 16),
      _ueberschrift(
        'Aufträge (${b.bezuege.length}) · zusammen ${_kg(b.auftragKg)} kg',
      ),
      pw.SizedBox(height: 4),
      _tabelle(
        kopf: const ['Versand', 'Beleg', 'Kunde', 'kg'],
        breiten: const [2, 2, 5, 2],
        rechtsAb: 3,
        zeilen: [
          for (final z in [...b.bezuege]..sort(_nachVersand))
            [
              _tagKurz(z.warenausgang),
              z.beleg,
              z.debitor.isEmpty ? '-' : z.debitor,
              _kg(z.kg),
            ],
        ],
      ),
    ],

    // ── Rückmeldung ─────────────────────────────────────────────────────
    pw.SizedBox(height: 22),
    pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(10, 10, 10, 14),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey500, width: 0.8),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Rückmeldung Produktion',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 14),
          pw.Row(
            children: [
              pw.Expanded(child: _linie('Produziert (kg)')),
              pw.SizedBox(width: 14),
              pw.Expanded(child: _linie('Charge')),
              pw.SizedBox(width: 14),
              pw.Expanded(child: _linie('Datum / Kürzel')),
            ],
          ),
        ],
      ),
    ),
  ];
}

int _nachVersand(AuftragsBezug a, AuftragsBezug b) {
  final t = a.warenausgang.compareTo(b.warenausgang);
  return t != 0 ? t : a.beleg.compareTo(b.beleg);
}

pw.Widget _feld(
  String label,
  String wert, {
  String? zusatz,
  bool gross = false,
}) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        pdfText(label),
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
      ),
      pw.SizedBox(height: 3),
      pw.Text(
        pdfText(wert),
        style: pw.TextStyle(
          fontSize: gross ? 24 : 15,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
      if (zusatz != null)
        pw.Text(
          pdfText(zusatz),
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
    ],
  );
}

pw.Widget _chip(String text) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: pw.BoxDecoration(
      color: PdfColors.grey200,
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Text(pdfText(text), style: const pw.TextStyle(fontSize: 9)),
  );
}

pw.Widget _ueberschrift(String text) {
  return pw.Text(
    pdfText(text),
    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
  );
}

pw.Widget _linie(String label) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(height: 14),
      pw.Container(height: 0.8, color: PdfColors.grey600),
      pw.SizedBox(height: 2),
      pw.Text(
        pdfText(label),
        style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
      ),
    ],
  );
}

/// Tabelle mit grauer Kopfzeile, die auf jeder Folgeseite wiederholt wird.
/// Spalten ab [rechtsAb] stehen rechtsbündig (Zahlen).
pw.Widget _tabelle({
  required List<String> kopf,
  required List<int> breiten,
  required int rechtsAb,
  required List<List<String>> zeilen,
}) {
  pw.Widget zelle(String text, int spalte, {bool fett = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      child: pw.Text(
        pdfText(text),
        textAlign: spalte >= rechtsAb ? pw.TextAlign.right : null,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: fett ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
    columnWidths: {
      for (var i = 0; i < breiten.length; i++)
        i: pw.FlexColumnWidth(breiten[i].toDouble()),
    },
    children: [
      pw.TableRow(
        repeat: true,
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          for (var i = 0; i < kopf.length; i++) zelle(kopf[i], i, fett: true),
        ],
      ),
      for (final z in zeilen)
        pw.TableRow(
          children: [
            for (var i = 0; i < z.length; i++) zelle(z[i], i),
          ],
        ),
    ],
  );
}

// ═══════════════════════════════════════════════════════════════════════
// Formatierung
// ═══════════════════════════════════════════════════════════════════════

const _wochentageKurz = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
const _wochentageLang = [
  'Montag',
  'Dienstag',
  'Mittwoch',
  'Donnerstag',
  'Freitag',
  'Samstag',
  'Sonntag',
];

String _zwei(int n) => n.toString().padLeft(2, '0');

/// „Di 06.10."
String _tagKurz(DateTime d) =>
    '${_wochentageKurz[d.weekday - 1]} ${_zwei(d.day)}.${_zwei(d.month)}.';

/// „Di 06.10.2026"
String _tagLang(DateTime d) =>
    '${_wochentageKurz[d.weekday - 1]} ${_datumLang(d)}';

/// „06.10.2026"
String _datumLang(DateTime d) => '${_zwei(d.day)}.${_zwei(d.month)}.${d.year}';

String _wochentagLang(DateTime d) => _wochentageLang[d.weekday - 1];

/// „20:41"
String _uhrzeit(DateTime d) => '${_zwei(d.hour)}:${_zwei(d.minute)}';

/// Kilogramm mit deutschem Tausenderpunkt: ab 100 kg ganze Zahlen,
/// darunter eine Nachkommastelle, wenn es eine gibt.
String _kg(double v) {
  final ab100 = v.abs() >= 100;
  final zehntel = ab100 ? v.round() * 10 : (v * 10).round();
  final negativ = zehntel < 0;
  final betrag = zehntel.abs();
  final ganz = betrag ~/ 10;
  final rest = betrag % 10;
  final mitPunkten = ganz.toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => '.',
      );
  return '${negativ ? '-' : ''}$mitPunkten${rest == 0 ? '' : ',$rest'}';
}

String _prozent(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

/// „2:15 h"
String _dauer(double minuten) {
  final m = minuten.round();
  return '${m ~/ 60}:${_zwei(m % 60)} h';
}
