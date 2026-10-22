import '../../../core/constants/artikel_merkmale.dart';
import '../../../core/utils/format.dart';
import '../entwicklung_format.dart';
import '../rechenkern/naehrwert_rundung.dart';
import '../rechenkern/rechen_modell.dart';
import '../rechenkern/rechenkern.dart';

// Was sich von einem Rezepturstand zum nächsten ändert — für den
// Vergleich zweier Stände und als kurze Sätze im Verlauf, wenn ein Stand
// abgeschlossen wird: Zeilen, Verlust, Fleischanteil, die Nährwerte so,
// wie sie auf dem Etikett stehen, Allergene und Mengenangaben (QUID).

/// Eine Zeile des Vergleichs: dieselbe Zutat oder Unterrezeptur in zwei
/// Ständen.
class VergleichsZeile {
  const VergleichsZeile({required this.name, this.mengeA, this.mengeB});

  final String name;

  /// null: in diesem Stand nicht enthalten.
  final double? mengeA;
  final double? mengeB;

  bool get neu => mengeA == null && mengeB != null;
  bool get entfernt => mengeA != null && mengeB == null;
  bool get geaendert =>
      mengeA != null && mengeB != null && (mengeA! - mengeB!).abs() > 1e-9;
}

/// Stellt die Zeilen zweier Stände nebeneinander — gleiche Zutaten und
/// Unterrezepturen zusammen, in der Reihenfolge von [a], Neues dahinter.
List<VergleichsZeile> vergleicheZeilen(RechenRezeptur a, RechenRezeptur b) {
  String schluessel(RechenPosition p) =>
      p.zutat?.id ?? 'rezeptur:${p.unterrezeptur?.id}';
  String name(RechenPosition p) =>
      p.zutat?.name ?? p.unterrezeptur?.name ?? '?';

  final reihenfolge = <String>[];
  final namen = <String, String>{};
  final mengenA = <String, double>{};
  final mengenB = <String, double>{};
  for (final p in a.positionen) {
    final k = schluessel(p);
    if (!mengenA.containsKey(k)) reihenfolge.add(k);
    namen[k] = name(p);
    mengenA[k] = (mengenA[k] ?? 0) + p.mengeKg;
  }
  for (final p in b.positionen) {
    final k = schluessel(p);
    if (!mengenA.containsKey(k) && !mengenB.containsKey(k)) {
      reihenfolge.add(k);
    }
    namen[k] = name(p);
    mengenB[k] = (mengenB[k] ?? 0) + p.mengeKg;
  }
  return [
    for (final k in reihenfolge)
      VergleichsZeile(name: namen[k]!, mengeA: mengenA[k], mengeB: mengenB[k]),
  ];
}

/// Höchstens so viele geänderte Zeilen werden einzeln genannt.
const int kStandZeilenEinzeln = 8;

/// Die Nährstoffe, deren Änderung genannt wird — die Energie in kcal.
const List<Naehrstoff> _naehrstoffe = [
  Naehrstoff.energieKcal,
  Naehrstoff.fett,
  Naehrstoff.gesaettigteFettsaeuren,
  Naehrstoff.kohlenhydrate,
  Naehrstoff.zucker,
  Naehrstoff.eiweiss,
  Naehrstoff.salz,
];

/// Die Menge einer Zeile für die Sätze: „0,5 kg".
String _kg(double kg) => '${mengeText(kg)} kg';

/// Der Prozentwert einer Mengenangabe, wie er in der Zutatenliste steht.
String _quid(double prozent) => '${Format.zahl(prozent, nachkomma: 1)} %';

/// Was sich von [vorher] zu [nachher] geändert hat — kurze Sätze für den
/// Verlauf. Ohne [vorher] (der erste Stand) eine Zusammenfassung: Zeilen,
/// Endgewicht und Fleischanteil. [vorherNummer] nennt den verglichenen
/// Stand, wenn sich nichts geändert hat.
List<String> standAenderungen(
  RechenRezeptur? vorher,
  RechenRezeptur nachher, {
  int? vorherNummer,
}) {
  final eb = berechne(nachher);
  if (vorher == null) {
    final n = nachher.positionen.length;
    return [
      'Endgewicht ${_kg(eb.endgewichtKg)} aus ${_kg(eb.eingesetztKg)}',
      n == 1 ? '1 Zeile' : '$n Zeilen',
      if (eb.fleischanteilProzent > 0)
        'Fleischanteil ${prozentText(eb.fleischanteilProzent)}',
    ];
  }
  final ea = berechne(vorher);
  final saetze = <String>[];

  // ── Zeilen ──────────────────────────────────────────────────────────
  final zeilen = [
    for (final z in vergleicheZeilen(vorher, nachher))
      if (z.neu)
        'Neu: ${z.name} (${_kg(z.mengeB!)})'
      else if (z.entfernt)
        'Entfernt: ${z.name}'
      else if (z.geaendert)
        '${z.name}: ${mengeText(z.mengeA!)} → ${_kg(z.mengeB!)}',
  ];
  saetze.addAll(zeilen.take(kStandZeilenEinzeln));
  if (zeilen.length > kStandZeilenEinzeln) {
    final rest = zeilen.length - kStandZeilenEinzeln;
    saetze.add(
      'und $rest weitere ${rest == 1 ? 'Zeile' : 'Zeilen'} geändert',
    );
  }

  // ── Verlust und Fleischanteil ───────────────────────────────────────
  if (vorher.verlustart != nachher.verlustart) {
    saetze.add(
      'Verlustart: ${vorher.verlustart.label} → ${nachher.verlustart.label}',
    );
  }
  final va = prozentText(vorher.wirksamerVerlust);
  final vb = prozentText(nachher.wirksamerVerlust);
  if (va != vb) saetze.add('Verlust: $va → $vb');
  final fa = prozentText(ea.fleischanteilProzent);
  final fb = prozentText(eb.fleischanteilProzent);
  if (fa != fb) saetze.add('Fleischanteil: $fa → $fb');

  // ── Nährwerte, wie sie auf dem Etikett stehen ───────────────────────
  for (final s in _naehrstoffe) {
    final a = naehrwertGerundet(s, naehrstoffWert(ea.je100g, s));
    final b = naehrwertGerundet(s, naehrstoffWert(eb.je100g, s));
    if (a == b) continue;
    final name = s.label.replaceFirst(RegExp(r'^davon '), '');
    saetze.add('$name je 100 g: $a → $b ${s.einheit}');
  }

  // ── Allergene ───────────────────────────────────────────────────────
  String allergen(String a) => merkmalLabel(a, kAllergene) ?? a;
  for (final a in eb.allergene.keys) {
    if (!ea.allergene.containsKey(a)) saetze.add('Allergen neu: ${allergen(a)}');
  }
  for (final a in ea.allergene.keys) {
    if (!eb.allergene.containsKey(a)) {
      saetze.add('Allergen entfällt: ${allergen(a)}');
    }
  }

  // ── Mengenangaben und Zutatenliste ──────────────────────────────────
  final quidVorher = {
    for (final z in ea.zeilen)
      if (z.quid && !z.ausgelassen) z.name: _quid(z.anteilProzent),
  };
  for (final z in eb.zeilen) {
    if (!z.quid || z.ausgelassen) continue;
    final alt = quidVorher[z.name];
    final neu = _quid(z.anteilProzent);
    if (alt != null && alt != neu) saetze.add('QUID ${z.name}: $alt → $neu');
  }
  if (ea.zutatenliste != eb.zutatenliste) saetze.add('Zutatenliste geändert');

  if (saetze.isEmpty) {
    return [
      vorherNummer == null
          ? 'Keine Änderung zum vorigen Stand'
          : 'Keine Änderung zu Stand $vorherNummer',
    ];
  }
  return saetze;
}
