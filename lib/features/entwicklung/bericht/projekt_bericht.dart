import 'package:drift/drift.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/constants/artikel_merkmale.dart';
import '../../../core/constants/product_groups.dart';
import '../../../core/database/database.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/pdf_text.dart';
import '../../articles/article_print_service.dart';
import '../daten/dateien.dart';
import '../daten/entwicklung_repository.dart';
import '../haccp/haccp_modell.dart';
import '../haccp/prozess_kette.dart';
import '../haccp/prozess_modell.dart';
import '../projekte/entwicklungsstrang.dart';
import '../projekte/fliessdiagramm_liste.dart';
import '../projekte/projekt_checkliste.dart';
import '../projekte/projekt_modell.dart';
import '../rechenkern/naehrwert_rundung.dart';
import '../rechenkern/rechenkern.dart';
import '../spezifikation/spez_angaben.dart';

// Der Projektbericht als PDF: Stammdaten, Rezeptur mit Zutatenliste und
// Nährwerten, Sensorik, Prozess, HACCP, Checklisten und der
// Entwicklungsweg — von der Idee über jede Station bis zur Freigabe. Zum
// Weitergeben oder Ablegen.

/// Ein Stand, der gerade in Arbeit ist.
typedef InArbeit = ({String rezeptur, RezepturVersion version});

/// Ein Schritt aus dem freigegebenen Artikel mit den tatsächlich
/// gespeicherten Einstellungen.
typedef BerichtArtikelSchritt = ({
  ProductStep schritt,
  Machine? maschine,
  List<ProductStepParameter> parameter,
});

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
    this.artikelSchritte = const [],
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

  /// Die Prozessschritte des freigegebenen Artikels samt Maschinenwerten.
  final List<BerichtArtikelSchritt> artikelSchritte;

  /// Das Fließdiagramm mit Bezeichnung, etwa „FD_011 · Schnitzel paniert"
  /// — null: nur die Kennung aus dem Projekt.
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
  final artikelSchritte = <BerichtArtikelSchritt>[];
  if (artikel != null) {
    final schritte = await (db.select(db.productSteps)
          ..where((s) => s.productId.equals(artikel.id))
          ..where((s) => s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm.asc(s.reihenfolge)]))
        .get();
    for (final schritt in schritte) {
      final parameter = await (db.select(db.productStepParameters)
            ..where((p) => p.stepId.equals(schritt.id))
            ..where((p) => p.deletedAt.isNull())
            ..orderBy([
              (p) => OrderingTerm.asc(p.reihenfolge),
              (p) => OrderingTerm.asc(p.parameterGruppe),
            ]))
          .get();
      final maschineId = schritt.maschineId;
      final maschine = maschineId == null
          ? null
          : await (db.select(db.machines)
                ..where((m) => m.id.equals(maschineId)))
              .getSingleOrNull();
      artikelSchritte.add(
        (
          schritt: schritt,
          maschine: maschine,
          parameter: parameter,
        ),
      );
    }
  }

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
    artikelSchritte: artikelSchritte,
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

/// Kennung und Bezeichnung des Fließdiagramms.
Future<String?> _fliessdiagrammText(AppDatabase db, String? fdId) async {
  if (fdId == null || fdId.isEmpty) return null;
  final fd = await (db.select(db.entwicklungFliessdiagramme)
        ..where((f) => f.id.equals(fdId)))
      .getSingleOrNull();
  return fdText(fdId, bezeichnung: fd?.bezeichnung);
}

const PdfColor _grau = PdfColors.grey700;
const PdfColor _linie = PdfColors.grey400;
const PdfColor _blau = PdfColor.fromInt(0xFF174A70);
const PdfColor _hellBlau = PdfColor.fromInt(0xFFEAF1F6);

pw.Widget _kapitel(String titel, {String? untertitel}) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: const pw.BoxDecoration(
            color: _hellBlau,
            border: pw.Border(
              left: pw.BorderSide(color: _blau, width: 3),
              bottom: pw.BorderSide(color: _linie, width: .5),
            ),
          ),
          child: pw.Text(
            pdfText(titel),
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: _blau,
            ),
          ),
        ),
        if (untertitel != null && untertitel.trim().isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 5),
            child: _text(untertitel, groesse: 8, farbe: _grau),
          ),
        pw.SizedBox(height: 8),
      ],
    );

pw.Widget _unterkapitel(String titel) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
      child: pw.Text(
        pdfText(titel),
        style: pw.TextStyle(
          fontSize: 10.5,
          fontWeight: pw.FontWeight.bold,
          color: _blau,
        ),
      ),
    );

String _produktWert(double? wert, {int nachkomma = 1, String einheit = ''}) =>
    wert == null ? '' : '${_zahl(wert, nachkomma: nachkomma)}$einheit';

String _auswahlText(Set<String> werte, List<SpezWahl> liste) => [
      for (final w in liste)
        if (werte.contains(w.schluessel)) w.label,
    ].join(', ');

String _wahlText(String schluessel, List<SpezWahl> liste) {
  for (final w in liste) {
    if (w.schluessel == schluessel) return w.label;
  }
  return schluessel;
}

List<(String, String)> _artikelZeilen(Product p) => [
      ('Bezeichnung', p.artikelbezeichnung),
      ('Artikelnummer', p.artikelnummer),
      ('Produktgruppe', produktgruppeLabel(p.produktgruppe)),
      ('Verpackungsart', p.verpackungsart ?? ''),
      (
        'Gebindegröße',
        _produktWert(p.gebindeGroesseKg, nachkomma: 3, einheit: ' kg'),
      ),
      (
        'Haltbarkeit',
        p.haltbarkeitTage == null ? '' : '${p.haltbarkeitTage} Tage'
      ),
      (
        'Mindestvorlauf',
        p.mindestVorlaufzeitTage == null
            ? ''
            : '${p.mindestVorlaufzeitTage} Tage',
      ),
      (
        'Gesamtausbeute',
        _produktWert(
          p.gesamtAusbeuteFaktor == null ? null : p.gesamtAusbeuteFaktor! * 100,
          einheit: ' %',
        ),
      ),
      ('Ziel-Kerntemperatur', _produktWert(p.zielKerntempC, einheit: ' °C')),
      ('Kutter-Endtemperatur', _produktWert(p.kutterEndtempC, einheit: ' °C')),
      ('Brätfeinheit', p.braetFeinheit ?? ''),
      ('Kochkammer-Programm', p.kochkammerProgramm ?? ''),
      ('Räucherart', p.raeucherart ?? ''),
      ('Starterkultur', p.startkultur ?? ''),
      (
        'Reifezeit',
        p.reifezeitTage == null ? '' : '${p.reifezeitTage} Tage',
      ),
      ('Klimaprogramm', p.klimaprogramm ?? ''),
      ('Ziel-pH', _produktWert(p.zielPh, nachkomma: 2)),
      ('Ziel-aw', _produktWert(p.zielAw, nachkomma: 2)),
      (
        'Gewichtsverlust',
        _produktWert(p.gewichtsverlustProzent, einheit: ' %'),
      ),
      ('Pökelart', p.poekelart ?? ''),
      (
        'Lake-Konzentration',
        _produktWert(p.lakeKonzentrationProzent, einheit: ' %'),
      ),
      (
        'Pökelzeit',
        p.poekelzeitTage == null ? '' : '${p.poekelzeitTage} Tage',
      ),
      ('Tumbelzeit', _produktWert(p.tumbelzeitMin, einheit: ' min')),
      ('Basisprodukt', p.basisProduktArtikelnummer ?? ''),
      ('Scheibendicke', _produktWert(p.scheibendickeMm, einheit: ' mm')),
      (
        'Scheiben je Packung',
        p.scheibenProPackung?.toString() ?? '',
      ),
      ('Packungsgewicht', _produktWert(p.packungsgewichtG, einheit: ' g')),
      ('MAP-Gasgemisch', p.mapGas ?? ''),
      ('Formgewicht', _produktWert(p.formgewichtG, einheit: ' g')),
      ('Form', p.form ?? ''),
      ('Bratgrad', p.bratgrad ?? ''),
      ('Panierart', p.panierart ?? ''),
      (
        'Panieraufnahme',
        _produktWert(p.panierAufnahmeProzent, einheit: ' %'),
      ),
      ('Fleischanteiltyp', p.fleischanteilTyp ?? ''),
      (
        'Max. Durchlaufzeit',
        _produktWert(p.gesamtdurchlaufzeitMaxStd, einheit: ' h'),
      ),
      ('Wolf-Lochscheibe', _produktWert(p.wolfLochscheibeMm, einheit: ' mm')),
      ('Abkühlgradient', p.abkuehlgradient ?? ''),
      ('Bratenvariante', p.bratenVariante ?? ''),
      ('Füllung', p.fuellung ?? ''),
      (
        'Netzbindung',
        p.netzbindung == null ? '' : (p.netzbindung! ? 'ja' : 'nein'),
      ),
      ('Sous-vide-Badtemperatur', _produktWert(p.svBadtempC, einheit: ' °C')),
      ('Sous-vide-Garzeit', _produktWert(p.svGarzeitStd, einheit: ' h')),
      ('Anbratgrad', p.anbratgrad ?? ''),
      ('Allergene', merkmaleLabel(p.allergene, kAllergene)),
      (
        'Qualitätsstufe',
        merkmalLabel(p.qualitaetsstufe, kQualitaetsstufen) ?? '',
      ),
      (
        'Verarbeitungsstufe',
        merkmaleLabel(p.verarbeitungsstufe, kVerarbeitungsstufen),
      ),
      (
        'Verpackungsformen',
        merkmaleLabel(p.verpackungsformen, kVerpackungsformen),
      ),
      ('Kartongröße', merkmalLabel(p.kartonGroesse, kKartonGroessen) ?? ''),
      (
        'Kartonbedruckung',
        merkmalLabel(p.kartonBedruckung, kKartonBedruckungen) ?? '',
      ),
      (
        'Packungen je Karton',
        p.packungenProKarton?.toString() ?? '',
      ),
      ('Nettofüllmenge', _produktWert(p.fuellmengeNettoG, einheit: ' g')),
      ('Abgabeart', merkmalLabel(p.abgabeart, kAbgabearten) ?? ''),
      ('Beschreibung', p.beschreibung ?? ''),
      ('Artikelnotizen', p.notizen ?? ''),
    ];

List<List<BerichtArtikelSchritt>> _artikelStationen(
  List<BerichtArtikelSchritt> schritte,
) {
  final stationen = <List<BerichtArtikelSchritt>>[];
  for (final eintrag in schritte) {
    if (stationen.isNotEmpty &&
        stationen.last.first.schritt.abteilung == eintrag.schritt.abteilung) {
      stationen.last.add(eintrag);
    } else {
      stationen.add([eintrag]);
    }
  }
  return stationen;
}

/// Ein Schritt der Prozesskette: Nummer, Name und Prozessschritt, darunter
/// seine Werte — eingerückt unter seiner Station.
List<pw.Widget> _schritt(List<ProzessSchritt> kette, ProzessSchritt s) {
  final nummer = kette.indexOf(s) + 1;
  final prozess = s.prozessschritt.trim();
  final titel = s.maschine.trim().isNotEmpty && prozess.isNotEmpty
      ? '${s.bezeichnung(nummer)} — $prozess'
      : s.bezeichnung(nummer);
  final zeilen = schrittZeilen(s);
  return [
    pw.Padding(
      padding: const pw.EdgeInsets.only(left: 10, top: 3, bottom: 1),
      child: pw.Text(
        pdfText('$nummer. $titel'),
        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      ),
    ),
    if (zeilen.isNotEmpty)
      pw.Padding(
        padding: const pw.EdgeInsets.only(left: 22),
        child: _zeilen(zeilen),
      ),
  ];
}

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

pw.Widget _text(String text, {double groesse = 9, PdfColor? farbe}) => pw.Text(
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

({PdfColor akzent, PdfColor hintergrund, String label}) _risikoDarstellung(
  int risiko,
) =>
    risiko >= 6
        ? (
            akzent: PdfColor.fromHex('#B42318'),
            hintergrund: PdfColor.fromHex('#FDECEA'),
            label: 'KRITISCH',
          )
        : risiko >= 3
            ? (
                akzent: PdfColor.fromHex('#B54708'),
                hintergrund: PdfColor.fromHex('#FFF4E5'),
                label: 'MITTEL',
              )
            : (
                akzent: PdfColor.fromHex('#067647'),
                hintergrund: PdfColor.fromHex('#ECFDF3'),
                label: 'OK',
              );

pw.Widget _risikoLegende(String label, PdfColor farbe) => pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Container(
          width: 7,
          height: 7,
          decoration: pw.BoxDecoration(
            color: farbe,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
          ),
        ),
        pw.SizedBox(width: 3),
        _text(label, groesse: 7.5, farbe: _grau),
      ],
    );

/// Ein Verlaufseintrag mit getrennt erkennbaren Metadaten, Beschreibung,
/// Änderungen und Kommentaren.
List<pw.Widget> _eintrag(ProjektEintrag e, {double einzug = 0}) {
  final offen = EintragStatus.aus(e.status) == EintragStatus.offen;
  final beschreibung = e.beschreibung?.trim() ?? '';
  return [
    pw.Padding(
      padding: pw.EdgeInsets.only(left: einzug, top: 5),
      child: pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: const pw.BoxDecoration(
          color: PdfColors.grey100,
          border: pw.Border(
            left: pw.BorderSide(color: _blau, width: 2),
          ),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _text(e.titel, groesse: 9, farbe: PdfColors.grey900),
            pw.SizedBox(height: 2),
            _text(
              '${Format.datum(e.datum)} · ${EintragArt.aus(e.art).label}'
              '${offen ? ' · Offen' : ''}',
              groesse: 7.5,
              farbe: _grau,
            ),
          ],
        ),
      ),
    ),
    if (beschreibung.isNotEmpty) ...[
      pw.Padding(
        padding: pw.EdgeInsets.only(left: einzug + 8, top: 4, bottom: 1),
        child: _text('Beschreibung', groesse: 7.5, farbe: _grau),
      ),
      pw.Padding(
        padding: pw.EdgeInsets.only(left: einzug + 8),
        child: _fliesstext(beschreibung),
      ),
    ],
    if (texteAus(e.aenderungen).isNotEmpty) ...[
      pw.Padding(
        padding: pw.EdgeInsets.only(left: einzug + 8, top: 4, bottom: 1),
        child: _text('Änderungen', groesse: 7.5, farbe: _grau),
      ),
      for (final a in texteAus(e.aenderungen))
        _text(
          '• $a',
          groesse: 8,
          farbe: _grau,
        ),
    ],
    if (Kommentar.listeAus(e.kommentare).isNotEmpty) ...[
      pw.Padding(
        padding: pw.EdgeInsets.only(left: einzug + 8, top: 4, bottom: 1),
        child: _text('Kommentare', groesse: 7.5, farbe: _grau),
      ),
      for (final k in Kommentar.listeAus(e.kommentare))
        _text(
          '${k.name.isEmpty ? '' : '${k.name}: '}${k.text}',
          groesse: 8,
          farbe: _grau,
        ),
    ],
  ];
}

/// Der Entwicklungsweg als zeitlich geordnete Stationen mit klar
/// bezeichneten Rückmeldungen, Rezepturänderungen und Phasenwechseln.
List<pw.Widget> _entwicklungsweg(ProjektBericht b) {
  final p = b.projekt;
  final kunde = p.kunde?.trim() ?? '';
  final widgets = <pw.Widget>[];
  final weg = entwicklungsweg(b.verlauf);
  for (final punkt in weg) {
    switch (punkt) {
      case WegAnfang(:final eintraege):
        widgets.add(
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 5),
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: const pw.BoxDecoration(
              color: PdfColors.blue50,
              border: pw.Border(
                left: pw.BorderSide(color: _blau, width: 3),
              ),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _text('START · Idee und Anfrage', groesse: 10, farbe: _blau),
                pw.SizedBox(height: 2),
                _text(
                  [
                    'Projektstart ${Format.datum(p.createdAt)}',
                    if (kunde.isNotEmpty) 'Kunde: $kunde',
                  ].join(' · '),
                  groesse: 8,
                  farbe: _grau,
                ),
              ],
            ),
          ),
        );
        for (final e in eintraege) {
          widgets.addAll(_eintrag(e, einzug: 8));
        }
      case WegStation():
        final e = punkt.eintrag;
        final beschreibung = e.beschreibung?.trim() ?? '';
        final kennzahlen = b.kennzahlen[punkt.versionId] ?? const [];
        widgets.add(
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 12, bottom: 4),
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: const pw.BoxDecoration(
              color: PdfColors.purple50,
              border: pw.Border(
                left: pw.BorderSide(color: _stationFarbe, width: 3),
              ),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _text(
                  'STATION ${punkt.nummer} · ${e.titel}',
                  groesse: 10,
                  farbe: _stationFarbe,
                ),
                pw.SizedBox(height: 2),
                _text(
                  [
                    'Rezepturstand ${b.versionen[punkt.versionId]?.nummer ?? ''}',
                    Format.datum(e.datum),
                    if (p.freigabeVersionId == punkt.versionId) 'Freigegeben',
                  ].where((s) => s.isNotEmpty).join(' · '),
                  groesse: 8,
                  farbe: _grau,
                ),
              ],
            ),
          ),
        );
        if (beschreibung.isNotEmpty) {
          widgets.addAll(_absatz('Standbeschreibung', beschreibung));
        }
        final aenderungen = texteAus(e.aenderungen);
        if (aenderungen.isNotEmpty) {
          widgets.add(_unterkapitel('Änderungen an der Rezeptur'));
          for (final a in aenderungen) {
            widgets.add(_text('• $a', groesse: 8.5));
          }
        }
        if (kennzahlen.isNotEmpty) {
          widgets.add(
            _unterkapitel(
              'Nährwerte und Kennzahlen je 100 g'
              ' · Änderung zum vorherigen Stand',
            ),
          );
          widgets.add(
            _zeilen([
              for (final k in kennzahlen)
                (
                  k.label,
                  '${k.wert}'
                      '${k.aenderung == null ? '' : ' · ${k.aenderung}'}',
                ),
            ]),
          );
        }
        final kommentare = Kommentar.listeAus(e.kommentare);
        if (kommentare.isNotEmpty) {
          widgets.add(_unterkapitel('Kommentare zum Stand'));
          for (final k in kommentare) {
            widgets.add(
              _text(
                '${k.name.isEmpty ? '' : '${k.name}: '}${k.text}',
                groesse: 8,
                farbe: _grau,
              ),
            );
          }
        }
        if (punkt.rueckmeldungen.isNotEmpty) {
          widgets.add(_unterkapitel('Rückmeldungen nach dieser Station'));
          for (final r in punkt.rueckmeldungen) {
            widgets.addAll(_eintrag(r, einzug: 8));
          }
        }
      case WegPhase():
        final e = punkt.eintrag;
        final stand = b.versionen[e.versionId]?.nummer;
        final wechsel = statusWechsel(e);
        widgets.add(
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 12),
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              border: pw.Border(
                left: pw.BorderSide(
                  color: _phasenFarbe(punkt.status),
                  width: 3,
                ),
              ),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _text(
                  'PHASENWECHSEL · ${wechsel == null ? punkt.status.label : '${wechsel.alt?.label ?? ''} → ${wechsel.neu.label}'}',
                  groesse: 9.5,
                  farbe: _phasenFarbe(punkt.status),
                ),
                pw.SizedBox(height: 2),
                _text(
                  [
                    e.titel,
                    if (stand != null) 'Stand $stand',
                    Format.datum(e.datum),
                  ].join(' · '),
                  groesse: 8,
                  farbe: _grau,
                ),
              ],
            ),
          ),
        );
        final aenderungen = texteAus(e.aenderungen);
        if (aenderungen.isNotEmpty) {
          for (final a in aenderungen) {
            widgets.add(_text('• $a', groesse: 8, farbe: _grau));
          }
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
      pw.Container(
        margin: const pw.EdgeInsets.only(top: 12),
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: const pw.BoxDecoration(
          color: PdfColors.orange50,
          border: pw.Border(
            left: pw.BorderSide(color: PdfColors.orange800, width: 3),
          ),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _text(
              'IN ARBEIT · Entwurf',
              groesse: 9.5,
              farbe: PdfColors.orange800,
            ),
            pw.SizedBox(height: 2),
            _text(
              '${a.rezeptur} · Stand ${a.version.nummer}',
              groesse: 8.5,
              farbe: _grau,
            ),
          ],
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
  final abgeschlossenAm = version?.abgeschlossenAm;
  final e = b.ergebnis;
  final sensorik = Sensorik.aus(p.sensorik);
  final spezifikation = SpezAngaben.aus(p.spezifikation);
  final prozess = Prozessparameter.aus(p.prozess);
  final haccp = Haccp.aus(p.haccp);
  final checkliste = b.checkliste ??
      projektCheckStand(projekt: p, rezepturen: const [], versionen: const []);
  final etikett = lmivAus(p.etikettCheckliste);
  final etikettGeprueft = kEtikettCheckliste
      .where((c) => lmivStand(etikett, c.schluessel).geprueft)
      .length;
  final status = ProjektStatus.aus(p.status);
  final hatProduktDaten =
      artikel != null || !sensorik.leer || !spezifikation.leer;
  final hatRezeptur = e != null && version != null;
  final hatProzess =
      artikel != null || !prozess.leer || b.artikelSchritte.isNotEmpty;
  final hatVerlauf = b.verlauf.isNotEmpty || b.inArbeit.isNotEmpty;

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 48, 40, 44),
      maxPages: 200,
      theme: theme,
      header: (_) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 8),
        padding: const pw.EdgeInsets.only(bottom: 5),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: _linie, width: .5)),
        ),
        child: pw.Row(
          children: [
            _text('ARTIKELENTWICKLUNG', groesse: 8, farbe: _blau),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: pw.Text(
                pdfText(p.name),
                textAlign: pw.TextAlign.right,
                maxLines: 1,
                style: const pw.TextStyle(fontSize: 8, color: _grau),
              ),
            ),
          ],
        ),
      ),
      footer: (ctx) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 8),
        padding: const pw.EdgeInsets.only(top: 5),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: _linie, width: .5)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            _text(
              'Projektbericht · ${Format.datum(jetzt)}',
              groesse: 7,
              farbe: PdfColors.grey600,
            ),
            _text(
              'Seite ${ctx.pageNumber}/${ctx.pagesCount}',
              groesse: 7,
              farbe: PdfColors.grey600,
            ),
          ],
        ),
      ),
      build: (ctx) => [
        _kapitel('Projektübersicht'),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    pdfText(p.name),
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  if ((p.kunde ?? '').trim().isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 3),
                      child: _text(p.kunde!.trim(), groesse: 11, farbe: _grau),
                    ),
                ],
              ),
            ),
            if (bild != null)
              pw.Container(
                width: 125,
                height: 90,
                margin: const pw.EdgeInsets.only(left: 12),
                child: pw.Image(bild, fit: pw.BoxFit.contain),
              ),
          ],
        ),
        pw.SizedBox(height: 10),
        _zeilen([
          ('Projektphase', status.label),
          ('Artikelnummer', artikel?.artikelnummer ?? p.artikelnummer ?? ''),
          ('Angelegt', Format.datum(p.createdAt)),
          (
            'Freigegeben am',
            p.freigegebenAm == null ? '' : Format.datum(p.freigegebenAm!),
          ),
          ('Fließdiagramm', b.fliessdiagramm ?? p.fliessdiagramm ?? ''),
          ('Neuer Prozess', p.neuerProzess ? 'ja' : 'nein'),
          (
            'Neue Zutaten',
            p.neueZutaten
                ? 'ja${(p.neueZutatenDetails ?? '').trim().isEmpty ? '' : ': ${p.neueZutatenDetails!.trim()}'}'
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
            'Ziel aw',
            p.grenzeAw == null ? '' : 'max. ${_zahl(p.grenzeAw, nachkomma: 2)}',
          ),
          (
            'Freigegebener Artikel',
            artikel == null
                ? ''
                : '${artikel.artikelnummer} · ${artikel.artikelbezeichnung}',
          ),
          (
            'Rezepturstand',
            version == null
                ? ''
                : '${b.rezepturName ?? 'Rezeptur'} · Stand ${version.nummer}'
                    '${version.status == VersionStatus.abgeschlossen ? ' · abgeschlossen' : ' · Entwurf'}',
          ),
        ]),
        ..._absatz('Produktidee', p.produktidee),
        ..._absatz('Kundenvereinbarungen', p.kundenvereinbarungen),
        ..._absatz('Projekt-Notizen', p.notizen),
        if (hatRezeptur) ...[
          pw.NewPage(),
          _kapitel(
            'Rezeptur und Nährwerte',
            untertitel:
                '${b.rezepturName ?? 'Rezeptur'} · Stand ${version.nummer}'
                '${version.status == VersionStatus.abgeschlossen ? ' · abgeschlossen' : ' · Entwurf'}'
                '${abgeschlossenAm == null ? '' : ' · abgeschlossen am ${Format.datum(abgeschlossenAm)}'}',
          ),
          _unterkapitel('Zutatenverzeichnis'),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(9),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _linie, width: .5),
            ),
            child: _fliesstext(e.zutatenliste),
          ),
          pw.SizedBox(height: 8),
          _zeilen([
            (
              'Einsatzmenge',
              '${_zahl(e.eingesetztKg, nachkomma: 3)} kg',
            ),
            ('Fertige Menge', '${_zahl(e.endgewichtKg, nachkomma: 3)} kg'),
            (
              'Verlust',
              '${_zahl(version.verlustProzent)} % · ${version.verlustArt}',
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
          _unterkapitel('Nährwerte je 100 g'),
          _zeilen([
            for (final s in Naehrstoff.values)
              (
                '${s.label} (${s.einheit})',
                naehrwertGerundet(s, naehrstoffWert(e.je100g, s)),
              ),
          ]),
          if (e.warnungen.isNotEmpty) ...[
            _unterkapitel('Berechnungshinweise'),
            for (final w in e.warnungen)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: _text(w, groesse: 8, farbe: PdfColors.orange800),
              ),
          ],
        ],
        if (hatProduktDaten) ...[
          pw.NewPage(),
          _kapitel('Produktdaten und Spezifikation'),
          if (artikel != null) ...[
            _unterkapitel('Freigegebener Artikel im Planer'),
            _zeilen(_artikelZeilen(artikel)),
          ],
          if (!sensorik.leer) ...[
            _unterkapitel('Sensorik und Produktmerkmale'),
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
          if (!spezifikation.leer) ...[
            _unterkapitel('Spezifikation und Verpackung'),
            _zeilen([
              ('Artikelbezeichnung', spezifikation.bezeichnung),
              ('Gewichtstoleranz', spezifikation.toleranz),
              ('Lagerung', spezifikation.lagerung),
              ('Haltbarkeit', spezifikation.haltbarkeit),
              ('Produkthinweise', spezifikation.hinweise),
              (
                'Allergene als Spuren',
                merkmaleLabel(spezifikation.spuren.join(','), kAllergene),
              ),
              (
                'Umverpackung',
                _auswahlText(spezifikation.verpackung.um, kUmverpackungen),
              ),
              (
                'Karton',
                _wahlText(
                  spezifikation.verpackung.karton,
                  kKartonAufmachungen,
                ),
              ),
              (
                'Füllart Umverpackung',
                _wahlText(
                  spezifikation.verpackung.umFuellung,
                  kUmFuellungen,
                ),
              ),
              ('Tara Umverpackung', spezifikation.verpackung.umTara),
              ('Netto Umverpackung', spezifikation.verpackung.umNetto),
              ('Material Umverpackung', spezifikation.verpackung.umMaterial),
              (
                'Einzelverpackung',
                _auswahlText(
                  spezifikation.verpackung.einzel,
                  kEinzelverpackungen,
                ),
              ),
              ('Einheiten je Umverpackung', spezifikation.verpackung.anzahl),
              (
                'Atmosphäre',
                _wahlText(
                  spezifikation.verpackung.atmosphaere,
                  kAtmosphaeren,
                ),
              ),
              (
                'Füllart Einzelverpackung',
                _wahlText(
                  spezifikation.verpackung.einzelFuellung,
                  kEinzelFuellungen,
                ),
              ),
              (
                'Stück je Einzelverpackung',
                spezifikation.verpackung.stueckzahl
              ),
              ('Tara Einzelverpackung', spezifikation.verpackung.einzelTara),
              ('Netto Einzelverpackung', spezifikation.verpackung.einzelNetto),
              (
                'Material Einzelverpackung',
                spezifikation.verpackung.einzelMaterial,
              ),
            ]),
          ],
        ],
        if (hatProzess) ...[
          pw.NewPage(),
          _kapitel(
            'Prozess und Maschineneinstellungen',
            untertitel: artikel != null
                ? 'Artikel ${artikel.artikelnummer} · Prozessblattdarstellung'
                : 'Prozessstand aus der Produktentwicklung',
          ),
          if (b.artikelSchritte.isNotEmpty) ...[
            for (final station in _artikelStationen(b.artikelSchritte)) ...[
              pw.Padding(
                padding: const pw.EdgeInsets.only(
                  top: 8,
                  bottom: 4,
                ),
                child: ArticlePrintService.berichtAbteilungsBand(
                  station.first.schritt.abteilung,
                  [for (final eintrag in station) eintrag.schritt],
                ),
              ),
              for (final eintrag in station)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 6),
                  child: ArticlePrintService.berichtSchrittBlock(
                    step: eintrag.schritt,
                    maschine: eintrag.maschine,
                    parameter: eintrag.parameter,
                  ),
                ),
            ],
          ] else if (artikel != null)
            _text(
              'Im freigegebenen Artikel sind keine aktiven Prozessschritte hinterlegt.',
              farbe: _grau,
            ),
          if (b.artikelSchritte.isEmpty && !prozess.leer) ...[
            _unterkapitel(
              'Prozesskette des Projekts',
            ),
            _text(
              [
                prozessKurztext(prozess),
                prozessFassung(
                  prozess,
                  ProzessStand.listeAus(p.prozessHistorie),
                ).text,
              ].join(' · '),
              farbe: _grau,
            ),
            for (final (k, station)
                in stationenAus(prozess.schritte).indexed) ...[
              _unterkapitel(
                'Station ${k + 1} · '
                '${abteilungsName(station.first.abteilung)}',
              ),
              for (final s in station) ..._schritt(prozess.schritte, s),
            ],
            for (final abschnitt in prozess.abschnitte) ...[
              _unterkapitel(abschnitt.titel),
              _zeilen([
                for (final f in abschnitt.felder) (f.label, f.wert),
              ]),
            ],
          ],
        ],
        if (!haccp.leer) ...[
          pw.NewPage(),
          _kapitel('Lebensmittelsicherheit und Freigabe'),
          _unterkapitel('HACCP-Gefahrenanalyse'),
          pw.Wrap(
            spacing: 12,
            children: [
              _risikoLegende('1–2 · OK', PdfColor.fromHex('#067647')),
              _risikoLegende('3–4 · Mittel', PdfColor.fromHex('#B54708')),
              _risikoLegende('6–9 · Kritisch', PdfColor.fromHex('#B42318')),
            ],
          ),
          pw.SizedBox(height: 5),
          for (final g in haccp.gefahren) ...[
            () {
              final risiko = _risikoDarstellung(g.risiko);
              return pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 6),
                padding: const pw.EdgeInsets.all(7),
                decoration: pw.BoxDecoration(
                  color: risiko.hintergrund,
                  border: pw.Border.all(color: risiko.akzent, width: .7),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      children: [
                        pw.Expanded(
                          child: _text(
                            'Risiko ${g.risiko} · ${g.schwere} × ${g.wahrscheinlichkeit}',
                            groesse: 9,
                            farbe: risiko.akzent,
                          ),
                        ),
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: pw.BoxDecoration(
                            color: risiko.akzent,
                            borderRadius: const pw.BorderRadius.all(
                              pw.Radius.circular(3),
                            ),
                          ),
                          child: _text(
                            risiko.label,
                            groesse: 7,
                            farbe: PdfColors.white,
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    _zeilen([
                      ('Gefahr', g.gefahr),
                      ('Art', g.art.label),
                      ('Maßnahmen', g.massnahmen),
                    ]),
                  ],
                ),
              );
            }(),
          ],
          if (haccp.lenkungspunkte.isNotEmpty) ...[
            _unterkapitel('Lenkungspunkte'),
            for (final l in haccp.lenkungspunkte)
              pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 6),
                padding: const pw.EdgeInsets.all(7),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _linie, width: .5),
                ),
                child: _zeilen([
                  ('Einstufung', l.ergebnis.kuerzel),
                  ('Prozessschritt', l.schritt),
                  ('Lenkungsmaßnahme', l.lenkung),
                  (
                    'Entscheidungsbaum',
                    [
                      for (final antwort in l.antworten.entries)
                        '${kEntscheidungsbaum[antwort.key]?.kurz ?? antwort.key}: '
                            '${antwort.value ? 'Ja' : 'Nein'}',
                    ].join(' · '),
                  ),
                ]),
              ),
          ],
        ],
        pw.NewPage(),
        _kapitel('Checklisten und Bearbeitungsstand'),
        _unterkapitel('Projekt-Checkliste · ${checkliste.text} erledigt'),
        for (final c in checkliste.punkte)
          _text(
            '${c.erledigt ? '[x]' : '[ ]'} ${c.punkt.label}'
            '${c.vonHand ? ' (von Hand)' : c.text == null ? '' : ': ${c.text}'}',
          ),
        _unterkapitel(
          'Etikett (LMIV) · $etikettGeprueft von '
          '${kEtikettCheckliste.length} Pflichtangaben geprüft',
        ),
        for (final c in kEtikettCheckliste)
          _text(
            switch (lmivStand(etikett, c.schluessel)) {
              LmivStand.erledigt => '[x] ${c.label}',
              LmivStand.trifftNichtZu => '[-] ${c.label} (trifft nicht zu)',
              LmivStand.offen => '[ ] ${c.label}',
            },
          ),
        if (hatVerlauf) ...[
          pw.NewPage(),
          _kapitel('Entwicklungsverlauf'),
          ..._entwicklungsweg(b),
        ],
      ],
    ),
  );
  return doc.save();
}
