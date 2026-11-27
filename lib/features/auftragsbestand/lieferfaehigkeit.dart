import '../../core/utils/datum.dart';
import '../../core/utils/format.dart';
import '../statistik/statistik_ueberblick_daten.dart' show Ampel;
import 'auftragsbestand_ansicht.dart';

// ═══════════════════════════════════════════════════════════════════════
// Lieferfähigkeit
//
// Die eine Zahl, die Vertrieb und Geschäftsführung interessiert: Wie viel
// der Auftragsmenge der nächsten Tage ist rechtzeitig gedeckt — aus dem
// Lager oder aus Produktionen, die bis zum Versandtag fertig sind?
//
// Gerechnet wird aus dem zuletzt eingelesenen Auftragsbestand und seiner
// Deckung, genau wie auf der Seite Auftragsbestand. Bewusst ohne Flutter:
// Cockpit und Wochenbericht rechnen dasselbe.
// ═══════════════════════════════════════════════════════════════════════

/// So viele Kalendertage ab heute zählen: eine Woche Versand.
const int kLieferTage = 7;

/// Ab so viel rechtzeitig gedeckt ist die Ampel grün.
const double kLieferGut = 0.98;

/// Darunter rot.
const double kLieferWarnung = 0.90;

/// Ist der Bericht älter als so viele Tage, sagt die Zahl wenig — die
/// Ampel bleibt grau, bis neu eingelesen ist.
const int kBerichtAltTage = 3;

/// So viele gefährdete Versandtage nennt die Auswertung.
const int kGefaehrdetListe = 5;

/// Ein Versandtag eines Artikels, der nicht rechtzeitig gedeckt ist.
class GefaehrdeterVersand {
  const GefaehrdeterVersand({
    required this.artikelnummer,
    required this.bezeichnung,
    required this.tag,
    required this.fehltKg,
    required this.zuSpaetKg,
  });

  final String artikelnummer;
  final String bezeichnung;
  final DateTime tag;

  /// Weder im Lager noch eingeplant.
  final double fehltKg;

  /// Eingeplant, aber erst nach dem Versandtag fertig.
  final double zuSpaetKg;

  double get offenKg => fehltKg + zuSpaetKg;
}

/// Wie lieferfähig der Betrieb in den nächsten [kLieferTage] Tagen ist.
class Lieferfaehigkeit {
  const Lieferfaehigkeit({
    required this.von,
    required this.bisExkl,
    required this.auftragKg,
    required this.gedecktKg,
    required this.fehltKg,
    required this.zuSpaetKg,
    required this.versandtage,
    required this.gefaehrdet,
    this.berichtTag,
    this.heute,
  });

  /// Kein Auftragsbestand eingelesen.
  const Lieferfaehigkeit.leer()
      : von = null,
        bisExkl = null,
        auftragKg = 0,
        gedecktKg = 0,
        fehltKg = 0,
        zuSpaetKg = 0,
        versandtage = 0,
        gefaehrdet = const [],
        berichtTag = null,
        heute = null;

  final DateTime? von;
  final DateTime? bisExkl;

  /// Auftragsmenge mit Versand im Zeitraum.
  final double auftragKg;

  /// Davon rechtzeitig gedeckt — Lager und rechtzeitig fertige Produktion.
  final double gedecktKg;
  final double fehltKg;
  final double zuSpaetKg;

  /// Versandtage (Artikel × Tag) im Zeitraum.
  final int versandtage;

  /// Nicht rechtzeitig gedeckte Versandtage, der früheste zuerst — alle,
  /// nicht nur die ersten [kGefaehrdetListe].
  final List<GefaehrdeterVersand> gefaehrdet;

  /// Tag des Berichts.
  final DateTime? berichtTag;
  final DateTime? heute;

  /// Anteil rechtzeitig gedeckt — null ohne Aufträge im Zeitraum.
  double? get anteil => auftragKg > 0.005 ? gedecktKg / auftragKg : null;

  /// Wie viele Tage der Bericht alt ist — null ohne Bericht.
  int? get berichtAlterTage {
    final b = berichtTag;
    final h = heute;
    if (b == null || h == null) return null;
    // In UTC gezählt: Eine Nacht mit Zeitumstellung hat 23 oder 25 Stunden.
    return DateTime.utc(h.year, h.month, h.day)
        .difference(DateTime.utc(b.year, b.month, b.day))
        .inDays;
  }

  bool get berichtAlt => (berichtAlterTage ?? 0) > kBerichtAltTage;

  Ampel get ampel {
    final a = anteil;
    if (a == null || berichtAlt) return Ampel.neutral;
    if (a >= kLieferGut) return Ampel.gut;
    if (a >= kLieferWarnung) return Ampel.warnung;
    return Ampel.kritisch;
  }

  /// „3 von 42 Versandtagen gefährdet" — oder warum es keine Zahl gibt.
  String get unterText {
    if (berichtTag == null) return 'kein Auftragsbestand eingelesen';
    if (anteil == null) {
      return 'kein Versand in den nächsten $kLieferTage Tagen';
    }
    final n = gefaehrdet.length;
    if (n == 0) return 'alle $versandtage Versandtage gedeckt';
    return '$n von $versandtage Versandtagen gefährdet';
  }

  /// „Bericht vom 27.11., Versand bis 03.12." — oder der Hinweis, neu
  /// einzulesen.
  String? get herkunftText {
    final b = berichtTag;
    final bis = bisExkl;
    if (b == null || bis == null) return null;
    if (berichtAlt) {
      return 'Bericht vom ${Format.datumKurz(b)} — bitte neu einlesen';
    }
    return 'Bericht vom ${Format.datumKurz(b)}, Versand bis '
        '${Format.datumKurz(tagPlus(bis, -1))}';
  }
}

/// Die Lieferfähigkeit aus dem Auftragsbestand [ansicht]: Versand von
/// [heute] an für [tage] Kalendertage. Was vor heute versandt werden
/// sollte, zählt nicht — das ist meist längst unterwegs, nur noch nicht
/// gebucht.
Lieferfaehigkeit werteLieferfaehigkeitAus(
  AuftragsbestandAnsicht ansicht, {
  required DateTime heute,
  int tage = kLieferTage,
}) {
  if (ansicht.leer) return const Lieferfaehigkeit.leer();
  final von = tagOhneZeit(heute);
  final bisExkl = tagPlus(von, tage);
  var auftrag = 0.0, gedeckt = 0.0, fehlt = 0.0, spaet = 0.0;
  var versandtage = 0;
  final gefaehrdet = <GefaehrdeterVersand>[];
  for (final z in ansicht.zeilen) {
    for (final t in z.deckung.tage) {
      final tag = tagOhneZeit(t.tag);
      if (tag.isBefore(von) || !tag.isBefore(bisExkl)) continue;
      if (t.kg <= 0.005) continue;
      versandtage++;
      auftrag += t.kg;
      gedeckt += t.ausLagerKg + t.ausPlanungKg;
      fehlt += t.fehltKg;
      spaet += t.zuSpaetKg;
      if (t.offen) {
        gefaehrdet.add(
          GefaehrdeterVersand(
            artikelnummer: z.artikel.artikelnummer,
            bezeichnung: z.artikel.bezeichnung,
            tag: tag,
            fehltKg: t.fehltKg,
            zuSpaetKg: t.zuSpaetKg,
          ),
        );
      }
    }
  }
  gefaehrdet.sort((a, b) {
    final t = a.tag.compareTo(b.tag);
    if (t != 0) return t;
    return b.offenKg.compareTo(a.offenKg);
  });
  return Lieferfaehigkeit(
    von: von,
    bisExkl: bisExkl,
    auftragKg: auftrag,
    // Rundung: gedeckt nie über der Auftragsmenge.
    gedecktKg: gedeckt > auftrag ? auftrag : gedeckt,
    fehltKg: fehlt,
    zuSpaetKg: spaet,
    versandtage: versandtage,
    gefaehrdet: gefaehrdet,
    berichtTag: ansicht.berichtTag,
    heute: von,
  );
}
