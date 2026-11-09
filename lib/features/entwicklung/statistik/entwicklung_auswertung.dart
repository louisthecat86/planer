import 'dart:math' as math;

import '../../../core/database/database.dart';
import '../../../core/utils/format.dart';
import '../daten/entwicklung_repository.dart' show VersionStatus, nachName;
import '../projekte/entwicklungsstrang.dart'
    show statusWechsel, zeitlichSortiert;
import '../projekte/projekt_modell.dart';

// Die Produktentwicklung über einen Zeitraum — für die Statistik und den
// Bericht, etwa für die Managementbewertung am Jahresende: wie viele
// Muster entstanden, wie viele davon gelistet wurden, wie lange es bis
// dahin dauerte und woran es scheiterte. Reine Rechnung aus den Listen.
//
// Ein Muster ist jedes Projekt — ein Muster in einem Gesamtprojekt wie
// ein Projekt für sich. Gelistet ist es, sobald es in Produktion geht
// ([kGelistetAb]): mit der Freigabe als Artikel oder von Hand. Wann das
// war, steht im Verlauf — jeder Wechsel der Phase ist dort ein
// Meilenstein mit Datum.

/// Ab dieser Phase gilt ein Muster als gelistet.
const ProjektStatus kGelistetAb = ProjektStatus.produktion;

/// Im Kundenfilter: Muster ohne Kunden, etwa eigene Entwicklungen.
const String kOhneKunde = '';

DateTime _tag(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _tagPlus(DateTime d, int tage) =>
    DateTime(d.year, d.month, d.day + tage);

/// Ganze Tage von [a] bis [b] — unabhängig von der Uhrzeit und der
/// Umstellung auf Sommerzeit.
int tageZwischen(DateTime a, DateTime b) => DateTime.utc(b.year, b.month, b.day)
    .difference(DateTime.utc(a.year, a.month, a.day))
    .inDays;

String _zwei(int n) => n.toString().padLeft(2, '0');

String _monatKurz(int monat) => Format.monate[monat - 1].substring(0, 3);

// ── Zeitraum ──────────────────────────────────────────────────────────

/// Wie ein Zeitraum gewählt ist.
enum ZeitraumArt {
  jahr('Jahr'),
  quartal('Quartal'),
  monat('Monat'),
  frei('Frei');

  const ZeitraumArt(this.label);

  final String label;
}

/// Ein Zeitraum aus ganzen Tagen: von [von] bis vor [bisExkl].
class Zeitraum {
  const Zeitraum._(this.art, this.von, this.bisExkl);

  /// Das Jahr [jahr].
  factory Zeitraum.jahr(int jahr) =>
      Zeitraum._(ZeitraumArt.jahr, DateTime(jahr), DateTime(jahr + 1));

  /// Das Quartal [quartal] (1 bis 4) im Jahr [jahr].
  factory Zeitraum.quartal(int jahr, int quartal) {
    final q = quartal.clamp(1, 4);
    return Zeitraum._(
      ZeitraumArt.quartal,
      DateTime(jahr, 3 * q - 2),
      DateTime(jahr, 3 * q + 1),
    );
  }

  /// Der Monat [monat] im Jahr [jahr] — ein Monat über 12 zählt ins
  /// nächste Jahr, wie bei [DateTime].
  factory Zeitraum.monat(int jahr, int monat) {
    final anfang = DateTime(jahr, monat);
    return Zeitraum._(
      ZeitraumArt.monat,
      anfang,
      DateTime(anfang.year, anfang.month + 1),
    );
  }

  /// Von [von] bis einschließlich [bis] — vertauscht, wenn [bis] vor
  /// [von] liegt.
  factory Zeitraum.frei(DateTime von, DateTime bis) {
    var a = _tag(von);
    var b = _tag(bis);
    if (b.isBefore(a)) (a, b) = (b, a);
    return Zeitraum._(ZeitraumArt.frei, a, _tagPlus(b, 1));
  }

  /// Der Zeitraum der Art [art], in dem [tag] liegt. Frei: die zwölf
  /// Monate bis [tag].
  factory Zeitraum.um(ZeitraumArt art, DateTime tag) => switch (art) {
        ZeitraumArt.jahr => Zeitraum.jahr(tag.year),
        ZeitraumArt.quartal =>
          Zeitraum.quartal(tag.year, (tag.month - 1) ~/ 3 + 1),
        ZeitraumArt.monat => Zeitraum.monat(tag.year, tag.month),
        ZeitraumArt.frei =>
          Zeitraum.frei(DateTime(tag.year - 1, tag.month, tag.day + 1), tag),
      };

  final ZeitraumArt art;

  /// Der erste Tag, 00:00 Uhr.
  final DateTime von;

  /// Der Tag nach dem letzten, 00:00 Uhr.
  final DateTime bisExkl;

  /// Der letzte Tag.
  DateTime get bis => _tagPlus(bisExkl, -1);

  /// Wie viele Tage.
  int get tage => tageZwischen(von, bisExkl);

  int get _quartal => (von.month - 1) ~/ 3 + 1;

  bool enthaelt(DateTime zeit) => !zeit.isBefore(von) && zeit.isBefore(bisExkl);

  /// Der Zeitraum davor — ein frei gewählter um seine Länge.
  Zeitraum get davor => switch (art) {
        ZeitraumArt.jahr => Zeitraum.jahr(von.year - 1),
        ZeitraumArt.quartal => _quartal == 1
            ? Zeitraum.quartal(von.year - 1, 4)
            : Zeitraum.quartal(von.year, _quartal - 1),
        ZeitraumArt.monat => Zeitraum.monat(von.year, von.month - 1),
        ZeitraumArt.frei =>
          Zeitraum.frei(_tagPlus(von, -tage), _tagPlus(von, -1)),
      };

  /// Der Zeitraum danach — ein frei gewählter um seine Länge.
  Zeitraum get danach => switch (art) {
        ZeitraumArt.jahr => Zeitraum.jahr(von.year + 1),
        ZeitraumArt.quartal => _quartal == 4
            ? Zeitraum.quartal(von.year + 1, 1)
            : Zeitraum.quartal(von.year, _quartal + 1),
        ZeitraumArt.monat => Zeitraum.monat(von.year, von.month + 1),
        ZeitraumArt.frei => Zeitraum.frei(bisExkl, _tagPlus(bisExkl, tage - 1)),
      };

  /// Derselbe Zeitraum ein Jahr früher — zum Vergleich.
  Zeitraum get vorjahr => switch (art) {
        ZeitraumArt.jahr => Zeitraum.jahr(von.year - 1),
        ZeitraumArt.quartal => Zeitraum.quartal(von.year - 1, _quartal),
        ZeitraumArt.monat => Zeitraum.monat(von.year - 1, von.month),
        ZeitraumArt.frei => Zeitraum.frei(
            DateTime(von.year - 1, von.month, von.day),
            DateTime(bis.year - 1, bis.month, bis.day),
          ),
      };

  /// „2026", „3. Quartal 2026", „November 2026" oder
  /// „01.03.2026 – 15.09.2026".
  String get name => switch (art) {
        ZeitraumArt.jahr => '${von.year}',
        ZeitraumArt.quartal => '$_quartal. Quartal ${von.year}',
        ZeitraumArt.monat => '${Format.monate[von.month - 1]} ${von.year}',
        ZeitraumArt.frei => '${Format.datum(von)} – ${Format.datum(bis)}',
      };

  /// Kurz, etwa für Spalten: „2026", „Q3 2026", „Nov 2026" oder
  /// „01.03.26–15.09.26".
  String get kurz => switch (art) {
        ZeitraumArt.jahr => '${von.year}',
        ZeitraumArt.quartal => 'Q$_quartal ${von.year}',
        ZeitraumArt.monat => '${_monatKurz(von.month)} ${von.year}',
        ZeitraumArt.frei => '${_datumKurz(von)}–${_datumKurz(bis)}',
      };

  static String _datumKurz(DateTime d) =>
      '${_zwei(d.day)}.${_zwei(d.month)}.${_zwei(d.year % 100)}';

  /// Wie fein der Verlauf unterteilt ist: in Monate bis zu zwei Jahren,
  /// in Quartale bis zu acht, sonst in Jahre.
  ZeitRaster get raster {
    final monate = (bisExkl.year - von.year) * 12 +
        bisExkl.month -
        von.month +
        (bisExkl.day > 1 ? 1 : 0);
    return monate <= 24
        ? ZeitRaster.monat
        : monate <= 96
            ? ZeitRaster.quartal
            : ZeitRaster.jahr;
  }

  /// Die Abschnitte für den Verlauf ([raster]) — angeschnittene am Rand
  /// nur mit ihrem Teil.
  List<Zeitabschnitt> get abschnitte {
    final r = raster;
    final ergebnis = <Zeitabschnitt>[];
    var anfang = switch (r) {
      ZeitRaster.monat => DateTime(von.year, von.month),
      ZeitRaster.quartal => DateTime(von.year, ((von.month - 1) ~/ 3) * 3 + 1),
      ZeitRaster.jahr => DateTime(von.year),
    };
    while (anfang.isBefore(bisExkl)) {
      final ende = DateTime(anfang.year, anfang.month + r.monate);
      final q = (anfang.month - 1) ~/ 3 + 1;
      final label = switch (r) {
        ZeitRaster.monat => _monatKurz(anfang.month),
        ZeitRaster.quartal => 'Q$q ${_zwei(anfang.year % 100)}',
        ZeitRaster.jahr => '${anfang.year}',
      };
      final name = switch (r) {
        ZeitRaster.monat => '${Format.monate[anfang.month - 1]} ${anfang.year}',
        ZeitRaster.quartal => '$q. Quartal ${anfang.year}',
        ZeitRaster.jahr => '${anfang.year}',
      };
      ergebnis.add(
        Zeitabschnitt(
          label: label,
          name: name,
          von: anfang.isBefore(von) ? von : anfang,
          bisExkl: ende.isAfter(bisExkl) ? bisExkl : ende,
        ),
      );
      anfang = ende;
    }
    return ergebnis;
  }

  @override
  bool operator ==(Object other) =>
      other is Zeitraum &&
      other.art == art &&
      other.von == von &&
      other.bisExkl == bisExkl;

  @override
  int get hashCode => Object.hash(art, von, bisExkl);

  @override
  String toString() => 'Zeitraum($name)';
}

/// Wie fein ein Verlauf unterteilt ist.
enum ZeitRaster {
  monat('Monat', 1),
  quartal('Quartal', 3),
  jahr('Jahr', 12);

  const ZeitRaster(this.label, this.monate);

  final String label;

  /// So viele Monate hat ein Abschnitt.
  final int monate;
}

/// Ein Abschnitt im Verlauf: ein Monat, ein Quartal oder ein Jahr.
class Zeitabschnitt {
  const Zeitabschnitt({
    required this.label,
    required this.name,
    required this.von,
    required this.bisExkl,
  });

  /// Kurz unter der Säule: „Mär", „Q2 26", „2026".
  final String label;

  /// Ausgeschrieben: „März 2026", „2. Quartal 2026".
  final String name;

  final DateTime von;
  final DateTime bisExkl;

  bool enthaelt(DateTime zeit) => !zeit.isBefore(von) && zeit.isBefore(bisExkl);
}

// ── Ein Muster im Lauf der Zeit ───────────────────────────────────────

/// Was aus einem Muster wurde.
enum MusterErgebnis {
  gelistet('Gelistet'),
  nichtWeiter('Nicht weiter verfolgt'),
  offen('In Arbeit'),
  archiviert('Archiviert');

  const MusterErgebnis(this.label);

  final String label;
}

/// Ein Wechsel der Phase, wie ihn der Verlauf festhält.
typedef Phasenwechsel = ({
  DateTime datum,
  ProjektStatus? alt,
  ProjektStatus neu,

  /// Warum — beim Wechsel zu „nicht weiter verfolgt", wenn genannt.
  String? grund,
});

/// Der Grund aus einem Meilenstein („Grund: …") — null ohne.
String? _grundAus(ProjektEintrag e) {
  for (final z in (e.beschreibung ?? '').split('\n')) {
    if (z.startsWith('Grund: ')) {
      final g = z.substring(7).trim();
      if (g.isNotEmpty) return g;
    }
  }
  return null;
}

/// Ein Muster mit dem, was die Statistik von ihm braucht: wann es
/// angelegt, gelistet oder nicht weiter verfolgt wurde und mit wie vielen
/// Rezepturständen.
class MusterLauf {
  MusterLauf({
    required this.projekt,
    required this.wechsel,
    this.gesamtprojekt,
    this.staende = const [],
    this.neuerArtikel = false,
  });

  final EntwicklungsProjekt projekt;

  /// Der Name des Gesamtprojekts — null bei einem Projekt für sich.
  final String? gesamtprojekt;

  /// Die Wechsel der Phase, der älteste zuerst.
  final List<Phasenwechsel> wechsel;

  /// Die Stände seiner Rezepturen, der älteste zuerst.
  final List<RezepturVersion> staende;

  /// Mit der ersten Freigabe entstand ein neuer Artikel (statt einen
  /// vorhandenen zu ändern).
  final bool neuerArtikel;

  String get id => projekt.id;
  String get name => projekt.name;

  /// Der Kunde — null ohne.
  String? get kunde {
    final k = projekt.kunde?.trim() ?? '';
    return k.isEmpty ? null : k;
  }

  /// Der Tag, an dem es angelegt wurde.
  DateTime get angelegt => _tag(projekt.createdAt);

  /// Die Phase heute.
  ProjektStatus get jetzt => ProjektStatus.aus(projekt.status);

  /// Die Phase beim Anlegen: woher der erste Wechsel kam — ohne Wechsel
  /// die heutige (etwa bei Projekten aus der Suite).
  ProjektStatus get anfang =>
      wechsel.isEmpty ? jetzt : wechsel.first.alt ?? ProjektStatus.entwicklung;

  /// Der Tag der Freigabe als Artikel — null ohne.
  DateTime? get freigegebenAm {
    final f = projekt.freigegebenAm;
    return f == null ? null : _tag(f);
  }

  /// Der Tag, an dem es zum ersten Mal in Produktion ging — aus dem
  /// Verlauf oder der Freigabe. Null, solange es nicht gelistet ist oder
  /// wenn das Datum fehlt (etwa bei Projekten aus der Suite).
  DateTime? get gelistetAm {
    DateTime? tag;
    for (final w in wechsel) {
      if (w.neu == kGelistetAb) {
        tag = w.datum;
        break;
      }
    }
    final f = freigegebenAm;
    if (f != null && (tag == null || f.isBefore(tag))) tag = f;
    return tag;
  }

  /// Tage vom Anlegen bis zur Listung — null ohne Datum der Listung.
  int? get tageBisListung {
    final g = gelistetAm;
    return g == null ? null : math.max(0, tageZwischen(angelegt, g));
  }

  /// Rezepturstände, die bis zur Listung entstanden — null ohne Datum.
  int? get staendeBisListung {
    final g = gelistetAm;
    if (g == null) return null;
    final ende = _tagPlus(g, 1);
    return staende.where((v) => v.createdAt.isBefore(ende)).length;
  }

  /// Die Wechsel zu „nicht weiter verfolgt".
  Iterable<Phasenwechsel> get eingestellt =>
      wechsel.where((w) => w.neu == ProjektStatus.eingestellt);

  /// Die Phase am Ende von [tag] — null, wenn es das Muster da noch nicht
  /// gab. Nach dem letzten Wechsel im Verlauf gilt die heutige Phase.
  ProjektStatus? statusAm(DateTime tag) {
    final ende = _tagPlus(tag, 1);
    if (!projekt.createdAt.isBefore(ende)) return null;
    var status = anfang;
    for (final w in wechsel) {
      if (!w.datum.isBefore(ende)) return status;
      status = w.neu;
    }
    return jetzt;
  }

  /// Was am Ende von [tag] aus dem Muster geworden ist — null, wenn es
  /// das Muster da noch nicht gab. Gelistet bleibt gelistet, auch wenn es
  /// später archiviert wurde; ins Archiv aus „nicht weiter verfolgt"
  /// zählt als nicht weiter verfolgt.
  MusterErgebnis? ergebnisAm(DateTime tag) {
    final status = statusAm(tag);
    if (status == null) return null;
    final g = gelistetAm;
    final ende = _tagPlus(tag, 1);
    if (g != null && g.isBefore(ende)) return MusterErgebnis.gelistet;
    // In Produktion ohne Datum — oder schon so übernommen.
    if (status == kGelistetAb || anfang == kGelistetAb) {
      return MusterErgebnis.gelistet;
    }
    switch (status) {
      case ProjektStatus.entwicklung:
      case ProjektStatus.validierung:
        return MusterErgebnis.offen;
      case ProjektStatus.eingestellt:
        return MusterErgebnis.nichtWeiter;
      case ProjektStatus.produktion:
        return MusterErgebnis.gelistet;
      case ProjektStatus.archiviert:
        // Wie es ins Archiv kam: der letzte Wechsel bis [tag].
        ProjektStatus? vorher;
        for (final w in wechsel) {
          if (!w.datum.isBefore(ende)) break;
          if (w.neu == ProjektStatus.archiviert) vorher = w.alt;
        }
        return vorher == ProjektStatus.eingestellt
            ? MusterErgebnis.nichtWeiter
            : MusterErgebnis.archiviert;
    }
  }
}

/// Die Muster aus den Listen: Projekte (ohne gelöschte), dazu die
/// Gesamtprojekte für den Namen, die Einträge aller Projekte für die
/// Wechsel der Phase, Rezepturen und Stände für die Stände je Muster.
List<MusterLauf> musterLaeufe({
  required List<EntwicklungsProjekt> projekte,
  List<Gesamtprojekt> gesamtprojekte = const [],
  List<ProjektEintrag> eintraege = const [],
  List<Rezeptur> rezepturen = const [],
  List<RezepturVersion> versionen = const [],
}) {
  final gesamtNamen = {for (final g in gesamtprojekte) g.id: g.name};
  final ids = {for (final p in projekte) p.id};
  final eintraegeJe = <String, List<ProjektEintrag>>{};
  for (final e in eintraege) {
    if (ids.contains(e.projektId)) {
      eintraegeJe.putIfAbsent(e.projektId, () => []).add(e);
    }
  }
  final rezepturJe = <String, String>{
    for (final r in rezepturen)
      if (r.projektId != null && r.deletedAt == null) r.id: r.projektId!,
  };
  final staendeJe = <String, List<RezepturVersion>>{};
  for (final v in versionen) {
    final pid = rezepturJe[v.rezepturId];
    if (pid != null) staendeJe.putIfAbsent(pid, () => []).add(v);
  }
  return [
    for (final p in projekte)
      if (p.deletedAt == null) _lauf(p, gesamtNamen, eintraegeJe, staendeJe),
  ];
}

MusterLauf _lauf(
  EntwicklungsProjekt p,
  Map<String, String> gesamtNamen,
  Map<String, List<ProjektEintrag>> eintraegeJe,
  Map<String, List<RezepturVersion>> staendeJe,
) {
  final eigene = zeitlichSortiert(eintraegeJe[p.id] ?? const []);
  final wechsel = <Phasenwechsel>[];
  var neuerArtikel = false;
  var freigabe = false;
  for (final e in eigene) {
    if (statusWechsel(e) case final w?) {
      wechsel.add(
        (
          datum: _tag(e.datum),
          alt: w.alt,
          neu: w.neu,
          grund: w.neu == ProjektStatus.eingestellt ? _grundAus(e) : null,
        ),
      );
    }
    // Die erste Freigabe sagt, ob ein neuer Artikel entstand.
    if (!freigabe && e.titel.startsWith('Freigegeben ')) {
      if (e.titel.startsWith('Freigegeben als neuer Artikel')) {
        freigabe = true;
        neuerArtikel = true;
      } else if (e.titel.startsWith('Freigegeben für Artikel')) {
        freigabe = true;
      }
    }
  }
  final staende = [...?staendeJe[p.id]]
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return MusterLauf(
    projekt: p,
    gesamtprojekt:
        p.gesamtprojektId == null ? null : gesamtNamen[p.gesamtprojektId],
    wechsel: wechsel,
    staende: staende,
    neuerArtikel: neuerArtikel,
  );
}

// ── Kunden ────────────────────────────────────────────────────────────

/// Woran ein Kunde erkannt wird: klein geschrieben, ohne Leerraum am Rand
/// — null ohne Kunden. „Muster Markt" und „muster markt " sind derselbe.
String? kundeSchluessel(String? kunde) {
  final k = kunde?.trim().toLowerCase() ?? '';
  return k.isEmpty ? null : k;
}

/// Passt [kunde] zum Filter [filter]? null: alle, [kOhneKunde]: ohne
/// Kunden, sonst dieser Kunde (ohne auf Groß- und Kleinschreibung zu
/// achten).
bool kundePasst(String? kunde, String? filter) {
  if (filter == null) return true;
  final k = kundeSchluessel(kunde);
  if (filter == kOhneKunde) return k == null;
  return k == kundeSchluessel(filter);
}

/// Alle Kunden der Muster und Gesamtprojekte zur Auswahl — jeder einmal,
/// wie er zuerst geschrieben steht, nach Namen.
List<String> kundenListe(
  Iterable<MusterLauf> laeufe, [
  Iterable<Gesamtprojekt> gesamtprojekte = const [],
]) {
  final namen = <String, String>{};
  void merke(String? kunde) {
    final k = kundeSchluessel(kunde);
    if (k != null) namen.putIfAbsent(k, () => kunde!.trim());
  }

  for (final l in laeufe) {
    merke(l.projekt.kunde);
  }
  for (final g in gesamtprojekte) {
    if (g.deletedAt == null) merke(g.kunde);
  }
  return namen.values.toList()..sort(nachName);
}

// ── Die Zahlen eines Zeitraums ────────────────────────────────────────

/// Die Zahlen eines Zeitraums.
class ZeitraumZahlen {
  const ZeitraumZahlen({
    required this.neueMuster,
    required this.neueMusterImGesamtprojekt,
    required this.neueAnfragen,
    required this.gelistet,
    required this.freigegeben,
    required this.neueArtikel,
    required this.nichtWeiter,
    required this.tageBisListung,
    required this.tageBisListungMedian,
    required this.staendeBisListung,
    required this.inArbeitAmEnde,
    required this.neueProzesse,
    required this.neueZutaten,
    required this.staendeAngelegt,
    required this.staendeAbgeschlossen,
    required this.kohorte,
  });

  /// Im Zeitraum angelegte Muster …
  final int neueMuster;

  /// … davon in einem Gesamtprojekt.
  final int neueMusterImGesamtprojekt;

  /// Im Zeitraum angelegte Gesamtprojekte — die Anfragen.
  final int neueAnfragen;

  /// Muster, die im Zeitraum gelistet wurden — gleich, wann sie
  /// entstanden.
  final int gelistet;

  /// Freigaben als Artikel im Zeitraum …
  final int freigegeben;

  /// … davon als neuer Artikel.
  final int neueArtikel;

  /// Muster, die im Zeitraum nicht weiter verfolgt wurden.
  final int nichtWeiter;

  /// Im Mittel so viele Tage vom Anlegen bis zur Listung — über die
  /// Listungen im Zeitraum; null ohne.
  final double? tageBisListung;

  /// Der Median dazu.
  final double? tageBisListungMedian;

  /// Im Mittel so viele Rezepturstände bis zur Listung.
  final double? staendeBisListung;

  /// In Entwicklung oder Validierung am Ende des Zeitraums (oder heute,
  /// wenn er noch läuft).
  final int inArbeitAmEnde;

  /// Neue Muster mit einem neuen Prozess …
  final int neueProzesse;

  /// … und mit neuen Zutaten.
  final int neueZutaten;

  /// Rezepturstände, die im Zeitraum angelegt …
  final int staendeAngelegt;

  /// … und abgeschlossen wurden.
  final int staendeAbgeschlossen;

  /// Was aus den neuen Mustern wurde — Stand heute.
  final Map<MusterErgebnis, int> kohorte;

  int _kohorte(MusterErgebnis e) => kohorte[e] ?? 0;

  /// Anteil der neuen Muster, die gelistet sind — null ohne neue Muster.
  double? get listungsquote =>
      neueMuster == 0 ? null : _kohorte(MusterErgebnis.gelistet) / neueMuster;

  /// Anteil der Gelisteten unter den entschiedenen neuen Mustern
  /// (gelistet oder nicht weiter verfolgt) — null ohne entschiedene.
  double? get trefferquote {
    final ja = _kohorte(MusterErgebnis.gelistet);
    final entschieden = ja + _kohorte(MusterErgebnis.nichtWeiter);
    return entschieden == 0 ? null : ja / entschieden;
  }
}

double? _mittel(List<num> werte) => werte.isEmpty
    ? null
    : werte.fold<double>(0, (s, w) => s + w) / werte.length;

double? _median(List<num> werte) {
  if (werte.isEmpty) return null;
  final s = [...werte]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m].toDouble() : (s[m - 1] + s[m]) / 2;
}

/// Der Tag, an dem [z] für die Phase am Ende gezählt wird: sein letzter —
/// oder [heute], wenn er noch läuft.
DateTime _stichtag(Zeitraum z, DateTime heute) =>
    z.bis.isAfter(_tag(heute)) ? _tag(heute) : z.bis;

/// Der letzte Tag in [z], an dem [l] nicht weiter verfolgt wurde — null,
/// wenn es dort nicht dazu kam oder es am Ende von [z] (heute, wenn er
/// noch läuft) wieder verfolgt wird.
DateTime? _nichtWeiterIn(MusterLauf l, Zeitraum z, DateTime heute) {
  DateTime? tag;
  for (final w in l.eingestellt) {
    if (z.enthaelt(w.datum)) tag = w.datum;
  }
  if (tag == null) return null;
  return l.ergebnisAm(_stichtag(z, heute)) == MusterErgebnis.nichtWeiter
      ? tag
      : null;
}

ZeitraumZahlen _zahlen(
  Zeitraum z,
  List<MusterLauf> laeufe,
  List<Gesamtprojekt> anfragen,
  List<RezepturVersion> staende,
  DateTime heute,
) {
  final neu = [
    for (final l in laeufe)
      if (z.enthaelt(l.projekt.createdAt)) l,
  ];
  final gelistet = [
    for (final l in laeufe)
      if (l.gelistetAm case final g? when z.enthaelt(g)) l,
  ];
  final freigegeben = [
    for (final l in laeufe)
      if (l.freigegebenAm case final f? when z.enthaelt(f)) l,
  ];
  final stichtag = _stichtag(z, heute);
  final kohorte = {for (final e in MusterErgebnis.values) e: 0};
  for (final l in neu) {
    final e = l.ergebnisAm(_tag(heute));
    if (e != null) kohorte[e] = kohorte[e]! + 1;
  }
  final tage = [for (final l in gelistet) l.tageBisListung!];
  return ZeitraumZahlen(
    neueMuster: neu.length,
    neueMusterImGesamtprojekt:
        neu.where((l) => l.projekt.gesamtprojektId != null).length,
    neueAnfragen: anfragen.where((g) => z.enthaelt(g.createdAt)).length,
    gelistet: gelistet.length,
    freigegeben: freigegeben.length,
    neueArtikel: freigegeben.where((l) => l.neuerArtikel).length,
    nichtWeiter:
        laeufe.where((l) => _nichtWeiterIn(l, z, heute) != null).length,
    tageBisListung: _mittel(tage),
    tageBisListungMedian: _median(tage),
    staendeBisListung: _mittel([
      for (final l in gelistet) l.staendeBisListung!,
    ]),
    inArbeitAmEnde: laeufe
        .where((l) => l.ergebnisAm(stichtag) == MusterErgebnis.offen)
        .length,
    neueProzesse: neu.where((l) => l.projekt.neuerProzess).length,
    neueZutaten: neu.where((l) => l.projekt.neueZutaten).length,
    staendeAngelegt: staende.where((v) => z.enthaelt(v.createdAt)).length,
    staendeAbgeschlossen: staende
        .where(
          (v) =>
              v.status == VersionStatus.abgeschlossen &&
              v.abgeschlossenAm != null &&
              z.enthaelt(v.abgeschlossenAm!),
        )
        .length,
    kohorte: kohorte,
  );
}

// ── Verlauf, Kunden, Gründe ───────────────────────────────────────────

/// Die Zahlen eines Abschnitts im Verlauf.
class AbschnittZahlen {
  const AbschnittZahlen({
    required this.abschnitt,
    required this.neu,
    required this.gelistet,
    required this.nichtWeiter,
    required this.staende,
  });

  final Zeitabschnitt abschnitt;

  /// Die hier angelegten Muster, nach dem, was aus ihnen wurde (heute).
  final Map<MusterErgebnis, int> neu;

  /// Hier gelistete Muster.
  final List<MusterLauf> gelistet;

  /// Hier nicht weiter verfolgte Muster.
  final List<MusterLauf> nichtWeiter;

  /// Hier angelegte Rezepturstände.
  final int staende;

  int get neuGesamt => neu.values.fold(0, (s, n) => s + n);
}

/// Die neuen Muster eines Kunden — nach dem, was aus ihnen wurde.
class KundenZahlen {
  const KundenZahlen({required this.kunde, required this.ergebnis});

  /// Der Kunde — null: ohne Kunden.
  final String? kunde;

  final Map<MusterErgebnis, int> ergebnis;

  int get muster => ergebnis.values.fold(0, (s, n) => s + n);

  int anzahl(MusterErgebnis e) => ergebnis[e] ?? 0;

  /// Anteil gelistet — null ohne Muster.
  double? get quote =>
      muster == 0 ? null : anzahl(MusterErgebnis.gelistet) / muster;
}

/// Ein Grund, warum Muster nicht weiter verfolgt wurden.
class GrundZahl {
  const GrundZahl({required this.grund, required this.muster});

  /// Der Grund, wie er zuerst genannt wurde — null: ohne Angabe.
  final String? grund;

  final List<MusterLauf> muster;

  int get anzahl => muster.length;
}

// ── Die Auswertung ────────────────────────────────────────────────────

/// Die Produktentwicklung in einem Zeitraum, mit dem Vorjahr zum
/// Vergleich.
class EntwicklungsAuswertung {
  const EntwicklungsAuswertung({
    required this.zeitraum,
    required this.kunde,
    required this.heute,
    required this.zahlen,
    required this.vorjahr,
    required this.neu,
    required this.gelistet,
    required this.nichtWeiter,
    required this.verlauf,
    required this.kunden,
    required this.gruende,
    required this.ohneDatumGelistet,
  });

  final Zeitraum zeitraum;

  /// Der Kundenfilter — null: alle, [kOhneKunde]: ohne Kunden.
  final String? kunde;

  /// Der Tag, an dem gerechnet wurde.
  final DateTime heute;

  final ZeitraumZahlen zahlen;

  /// Dieselben Zahlen ein Jahr früher.
  final ZeitraumZahlen vorjahr;

  /// Die im Zeitraum angelegten Muster, das älteste zuerst.
  final List<MusterLauf> neu;

  /// Die im Zeitraum gelisteten Muster, nach dem Tag der Listung.
  final List<MusterLauf> gelistet;

  /// Die im Zeitraum nicht weiter verfolgten Muster, nach dem Tag.
  final List<MusterLauf> nichtWeiter;

  final List<AbschnittZahlen> verlauf;

  /// Die neuen Muster je Kunde — die meisten zuerst.
  final List<KundenZahlen> kunden;

  /// Warum Muster im Zeitraum nicht weiter verfolgt wurden — die
  /// häufigsten zuerst.
  final List<GrundZahl> gruende;

  /// Neue Muster, die gelistet sind, ohne dass der Tag bekannt ist —
  /// sie zählen beim Ergebnis, nicht bei den Listungen.
  final int ohneDatumGelistet;

  /// Der Tag, für den „in Arbeit" gilt: das Ende des Zeitraums oder
  /// heute, wenn er noch läuft.
  DateTime get stichtag => _stichtag(zeitraum, heute);

  /// Läuft der Zeitraum noch?
  bool get laeuftNoch => zeitraum.bis.isAfter(_tag(heute));

  /// Was aus [l] bis heute wurde.
  MusterErgebnis ergebnis(MusterLauf l) =>
      l.ergebnisAm(_tag(heute)) ?? MusterErgebnis.offen;

  /// Der Grund, aus dem [l] im Zeitraum nicht weiter verfolgt wurde —
  /// der zuletzt genannte.
  String? grund(MusterLauf l) => _grundIn(l, zeitraum);

  /// Der letzte Tag im Zeitraum, an dem [l] nicht weiter verfolgt wurde.
  DateTime? eingestelltAm(MusterLauf l) {
    DateTime? d;
    for (final w in l.eingestellt) {
      if (zeitraum.enthaelt(w.datum)) d = w.datum;
    }
    return d;
  }
}

/// Der Grund des letzten Wechsels zu „nicht weiter verfolgt" in [z].
String? _grundIn(MusterLauf l, Zeitraum z) {
  String? g;
  for (final w in l.eingestellt) {
    if (z.enthaelt(w.datum)) g = w.grund;
  }
  return g;
}

/// Wertet [laeufe] für [zeitraum] aus — mit dem Kundenfilter [kunde]
/// (null: alle, [kOhneKunde]: ohne Kunden). [versionen] sind alle
/// Rezepturstände; ohne Filter zählen auch die von Rezepturen ohne
/// Projekt ([rezepturen] ohne gelöschte).
EntwicklungsAuswertung entwicklungAuswerten({
  required List<MusterLauf> laeufe,
  required Zeitraum zeitraum,
  required DateTime heute,
  List<Gesamtprojekt> gesamtprojekte = const [],
  List<Rezeptur> rezepturen = const [],
  List<RezepturVersion> versionen = const [],
  String? kunde,
}) {
  final auswahl = [
    for (final l in laeufe)
      if (kundePasst(l.projekt.kunde, kunde)) l,
  ];
  final anfragen = [
    for (final g in gesamtprojekte)
      if (g.deletedAt == null && kundePasst(g.kunde, kunde)) g,
  ];
  // Die Stände: mit Filter nur die der gewählten Muster.
  final List<RezepturVersion> staende;
  if (kunde == null) {
    final ids = {
      for (final r in rezepturen)
        if (r.deletedAt == null) r.id,
    };
    staende = [
      for (final v in versionen)
        if (ids.contains(v.rezepturId)) v,
    ];
  } else {
    staende = [for (final l in auswahl) ...l.staende];
  }

  final tag = _tag(heute);
  final neu = [
    for (final l in auswahl)
      if (zeitraum.enthaelt(l.projekt.createdAt)) l,
  ]..sort((a, b) => a.projekt.createdAt.compareTo(b.projekt.createdAt));
  final gelistet = [
    for (final l in auswahl)
      if (l.gelistetAm case final g? when zeitraum.enthaelt(g)) l,
  ]..sort((a, b) => a.gelistetAm!.compareTo(b.gelistetAm!));

  // Nicht weiter verfolgt: im Zeitraum dazu gekommen und am Ende noch so.
  final eingestelltAm = {
    for (final l in auswahl)
      if (_nichtWeiterIn(l, zeitraum, heute) case final d?) l.id: d,
  };
  final nichtWeiter = [
    for (final l in auswahl)
      if (eingestelltAm.containsKey(l.id)) l,
  ]..sort((a, b) => eingestelltAm[a.id]!.compareTo(eingestelltAm[b.id]!));

  final verlauf = [
    for (final a in zeitraum.abschnitte)
      AbschnittZahlen(
        abschnitt: a,
        neu: {
          for (final e in MusterErgebnis.values)
            e: neu
                .where(
                  (l) =>
                      a.enthaelt(l.projekt.createdAt) &&
                      (l.ergebnisAm(tag) ?? MusterErgebnis.offen) == e,
                )
                .length,
        },
        gelistet: [
          for (final l in gelistet)
            if (a.enthaelt(l.gelistetAm!)) l,
        ],
        nichtWeiter: [
          for (final l in nichtWeiter)
            if (a.enthaelt(eingestelltAm[l.id]!)) l,
        ],
        staende: staende.where((v) => a.enthaelt(v.createdAt)).length,
      ),
  ];

  // Je Kunde — die Schreibweise, wie sie zuerst vorkommt.
  final jeKunde = <String?, Map<MusterErgebnis, int>>{};
  final kundenNamen = <String?, String?>{};
  for (final l in neu) {
    final k = kundeSchluessel(l.projekt.kunde);
    kundenNamen.putIfAbsent(k, () => l.kunde);
    final e = l.ergebnisAm(tag) ?? MusterErgebnis.offen;
    final m = jeKunde.putIfAbsent(
      k,
      () => {for (final x in MusterErgebnis.values) x: 0},
    );
    m[e] = m[e]! + 1;
  }
  final kunden = [
    for (final MapEntry(:key, :value) in jeKunde.entries)
      KundenZahlen(kunde: kundenNamen[key], ergebnis: value),
  ]..sort((a, b) {
      final d = b.muster.compareTo(a.muster);
      if (d != 0) return d;
      // Ohne Kunden zuletzt.
      if (a.kunde == null) return 1;
      if (b.kunde == null) return -1;
      return nachName(a.kunde!, b.kunde!);
    });

  // Die Gründe — der letzte im Zeitraum je Muster.
  final jeGrund = <String?, List<MusterLauf>>{};
  final grundNamen = <String?, String?>{};
  for (final l in nichtWeiter) {
    final g = _grundIn(l, zeitraum);
    final schluessel = g?.toLowerCase();
    grundNamen.putIfAbsent(schluessel, () => g);
    jeGrund.putIfAbsent(schluessel, () => []).add(l);
  }
  final gruende = [
    for (final MapEntry(:key, :value) in jeGrund.entries)
      GrundZahl(grund: grundNamen[key], muster: value),
  ]..sort((a, b) {
      final d = b.anzahl.compareTo(a.anzahl);
      if (d != 0) return d;
      // Ohne Angabe zuletzt.
      if (a.grund == null) return 1;
      if (b.grund == null) return -1;
      return nachName(a.grund!, b.grund!);
    });

  return EntwicklungsAuswertung(
    zeitraum: zeitraum,
    kunde: kunde,
    heute: tag,
    zahlen: _zahlen(zeitraum, auswahl, anfragen, staende, heute),
    vorjahr: _zahlen(zeitraum.vorjahr, auswahl, anfragen, staende, heute),
    neu: neu,
    gelistet: gelistet,
    nichtWeiter: nichtWeiter,
    verlauf: verlauf,
    kunden: kunden,
    gruende: gruende,
    ohneDatumGelistet: neu
        .where(
          (l) =>
              l.gelistetAm == null &&
              l.ergebnisAm(tag) == MusterErgebnis.gelistet,
        )
        .length,
  );
}

/// „+3", „−2" oder „±0" — die Veränderung von [vorher] zu [jetzt].
String veraenderungText(num jetzt, num vorher, {int nachkomma = 0}) {
  final d = jetzt - vorher;
  if (d.abs() < 1e-9) return '±0';
  final betrag = Format.zahl(d.abs(), nachkomma: nachkomma);
  return d > 0 ? '+$betrag' : '−$betrag';
}

/// „30 %" — ein Anteil in ganzen Prozent; „—" ohne.
String quoteText(double? anteil) =>
    anteil == null ? '—' : Format.prozent(anteil, nachkomma: 0);

/// „84 Tage" — „1 Tag", „—" ohne.
String tageText(double? tage) {
  if (tage == null) return '—';
  final n = tage.round();
  return n == 1 ? '1 Tag' : '${Format.zahl(n)} Tage';
}
