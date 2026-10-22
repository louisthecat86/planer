import '../../../core/constants/artikel_merkmale.dart';
import '../projekte/projekt_modell.dart';
import '../rechenkern/naehrwert_rundung.dart';
import '../rechenkern/rechenkern.dart';
import '../spezifikation/spez_angaben.dart';

// Das Etikett eines Rezepturstands als Entwurf: Bezeichnung,
// Zutatenliste mit hervorgehobenen Allergenen und Mengenangaben,
// mögliche Spuren, die Nährwerttabelle gerundet nach EU-Leitfaden und die
// Hinweise aus der Spezifikation (Lagerung, Zubereitung, Schutzgas,
// Nettofüllmenge). Mindesthaltbarkeit, Los und Anschrift setzt erst der
// Etikettendruck ein.

/// Eine Zeile der Nährwerttabelle: „davon …" ist eingerückt.
typedef EtikettNaehrwert = ({String label, String wert, bool davon});

/// Was auf dem Etikett eines Stands steht.
class EtikettInhalt {
  const EtikettInhalt({
    required this.bezeichnung,
    required this.zutatenliste,
    this.allergene = const [],
    this.spuren = const [],
    this.naehrwerte = const [],
    this.lagerung = '',
    this.zubereitung = '',
    this.hinweise = const [],
    this.schutzgas = false,
    this.nettofuellmenge = '',
    this.stand = '',
    this.fehlt = const [],
  });

  /// Die Bezeichnung des Lebensmittels.
  final String bezeichnung;

  /// Die Zutatenliste — Allergene in GROSSBUCHSTABEN, Mengen in Klammern.
  final String zutatenliste;

  /// Die enthaltenen Allergene, in der Rangfolge der Planung.
  final List<String> allergene;

  /// Allergene, die als Spuren vorkommen können (aus der Spezifikation).
  final List<String> spuren;

  final List<EtikettNaehrwert> naehrwerte;
  final String lagerung;
  final String zubereitung;

  /// Produkthinweise, je Zeile einer.
  final List<String> hinweise;

  /// „Unter Schutzatmosphäre verpackt."
  final bool schutzgas;

  /// „500 g" — leer: noch nicht angegeben.
  final String nettofuellmenge;

  /// Woher das Etikett kommt: „Frikadelle · Stand 2 · abgeschlossen am …".
  final String stand;

  /// Was für das fertige Etikett noch fehlt und sich in der App angeben
  /// lässt — oder was an den Zahlen nicht stimmt.
  final List<String> fehlt;

  /// „Kann Spuren von Sellerie und Senf enthalten." — leer ohne Spuren.
  String get spurenSatz => spuren.isEmpty
      ? ''
      : 'Kann Spuren von ${aufzaehlung(spuren)} enthalten.';
}

/// „A", „A und B", „A, B und C".
String aufzaehlung(List<String> teile) {
  if (teile.length <= 1) return teile.join();
  return '${teile.take(teile.length - 1).join(', ')} und ${teile.last}';
}

/// Der Wert eines Nährstoffs mit Einheit, gerundet wie auf dem Etikett.
String _naehrwert(RezepturErgebnis e, Naehrstoff s) =>
    '${naehrwertGerundet(s, naehrstoffWert(e.je100g, s))} ${s.einheit}';

/// Baut das Etikett eines Stands aus dem Ergebnis des Rechenkerns und den
/// Angaben des Projekts.
EtikettInhalt etikettAus({
  required String bezeichnung,
  required RezepturErgebnis ergebnis,
  SpezAngaben angaben = const SpezAngaben(),
  Sensorik sensorik = const Sensorik(),
  String stand = '',
}) {
  final e = ergebnis;
  String label(String a) => merkmalLabel(a, kAllergene) ?? a;
  final spuren = [
    for (final m in kAllergene)
      if (angaben.spuren.contains(m.dbValue) &&
          !e.allergene.containsKey(m.dbValue))
        m.label,
  ];
  final lagerung = angaben.lagerung.trim();
  final netto = angaben.verpackung.einzelNetto.trim();
  return EtikettInhalt(
    bezeichnung: bezeichnung.trim(),
    zutatenliste: e.zutatenliste,
    allergene: [for (final a in e.allergene.keys) label(a)],
    spuren: spuren,
    naehrwerte: [
      (
        label: 'Energie',
        wert: '${_naehrwert(e, Naehrstoff.energieKj)} / '
            '${_naehrwert(e, Naehrstoff.energieKcal)}',
        davon: false,
      ),
      for (final s in const [
        Naehrstoff.fett,
        Naehrstoff.gesaettigteFettsaeuren,
        Naehrstoff.kohlenhydrate,
        Naehrstoff.zucker,
        Naehrstoff.eiweiss,
        Naehrstoff.salz,
      ])
        (label: s.label, wert: _naehrwert(e, s), davon: s.label.startsWith('davon')),
    ],
    lagerung: lagerung,
    zubereitung: sensorik.zubereitung.trim(),
    hinweise: angaben.hinweisZeilen,
    schutzgas: angaben.verpackung.atmosphaere == 'schutzgas',
    nettofuellmenge: netto,
    stand: stand,
    fehlt: [
      if (e.zutatenliste.trim().isEmpty) 'Zutaten mit Menge',
      if (lagerung.isEmpty) 'Lagerbedingungen (Reiter „Spezifikation")',
      if (netto.isEmpty) 'Nettofüllmenge (Reiter „Spezifikation", Verpackung)',
      if (e.ohneNaehrwerte.isNotEmpty)
        'Nährwerte für ${aufzaehlung(e.ohneNaehrwerte)} — die Tabelle ist '
            'sonst zu niedrig',
    ],
  );
}

/// Das Etikett als Text zum Kopieren — ohne die Platzhalter des Entwurfs.
String etikettText(EtikettInhalt e) {
  final teile = <String>[
    if (e.bezeichnung.isNotEmpty) e.bezeichnung,
    [
      'Zutaten: ${e.zutatenliste}',
      if (e.spurenSatz.isNotEmpty) e.spurenSatz,
    ].join('\n'),
    [
      'Durchschnittliche Nährwerte je 100 g:',
      for (final n in e.naehrwerte)
        '${n.davon ? '- ' : ''}${n.label} ${n.wert}',
    ].join('\n'),
    [
      if (e.lagerung.isNotEmpty) 'Lagerung: ${e.lagerung}',
      if (e.zubereitung.isNotEmpty) 'Zubereitung: ${e.zubereitung}',
      ...e.hinweise,
      if (e.schutzgas) 'Unter Schutzatmosphäre verpackt.',
      if (e.nettofuellmenge.isNotEmpty) 'Nettofüllmenge: ${e.nettofuellmenge}',
    ].join('\n'),
  ];
  return teile.where((t) => t.trim().isNotEmpty).join('\n\n');
}
