/// Auswahllisten für die Artikelmerkmale aus der Infos-Karte.
///
/// Eine Stelle für alle: Die Maske baut daraus ihre Auswahlfelder, der
/// Planungs-Wizard leitet daraus seine Reihenfolge ab (Allergene
/// aufsteigend, Bio vor konventionell, roh nach gegart), und der Druck
/// zeigt die Klartexte.
///
/// Gespeichert wird in `products` immer der `dbValue`, bei
/// Mehrfachauswahl als kommagetrennte Liste. Bewusst kein eigenes
/// Zuordnungs-Schema: Die Listen sind kurz und ändern sich selten, und
/// eine Textspalte bleibt in Backup, Excel-Export und Sync lesbar.
library;

/// Ein Eintrag einer Auswahlliste.
typedef Merkmal = ({String dbValue, String label});

// ── Allergene ─────────────────────────────────────────────────────────
//
// Reihenfolge = Rangfolge für die Produktionsplanung: Ein Tag beginnt
// allergenfrei und arbeitet sich hoch, ein Rücksprung kostet die volle
// Reinigung. Neue Allergene deshalb an der fachlich richtigen Stelle
// einfügen, nicht einfach hinten anhängen.
const kAllergene = <Merkmal>[
  (dbValue: 'gluten', label: 'Gluten'),
  (dbValue: 'eier', label: 'Eier'),
  (dbValue: 'soja', label: 'Soja'),
  (dbValue: 'milch', label: 'Milch'),
  (dbValue: 'schalenfruechte', label: 'Schalenfrüchte'),
  (dbValue: 'sellerie', label: 'Sellerie'),
  (dbValue: 'senf', label: 'Senf'),
  (dbValue: 'sesam', label: 'Sesam'),
  (dbValue: 'sulfit', label: 'Sulfit'),
];

// ── Qualitätsstufe ────────────────────────────────────────────────────

const kQualitaetsstufen = <Merkmal>[
  (dbValue: 'bio', label: 'Bio'),
  (dbValue: 'konventionell', label: 'Konventionell'),
];

// ── Verarbeitungsstufe ────────────────────────────────────────────────
//
// Mehrfachauswahl, weil zwei unabhängige Dinge gemeint sind: der Garzu-
// stand (roh oder gegart) und der Zustand bei der Auslieferung (frisch
// oder tk). Ein rohes Hackprodukt tiefgekühlt ist „roh" + „tk".
const kVerarbeitungsstufen = <Merkmal>[
  (dbValue: 'roh', label: 'Roh'),
  (dbValue: 'gegart', label: 'Gegart'),
  (dbValue: 'frisch', label: 'Frisch'),
  (dbValue: 'tk', label: 'TK'),
];

// ── Verpackung ────────────────────────────────────────────────────────

const kVerpackungsformen = <Merkmal>[
  (dbValue: 'karton', label: 'Karton'),
  (dbValue: 'e2_kiste', label: 'E2 Kiste'),
  (dbValue: 'einschlagbeutel', label: 'Einschlagbeutel'),
];

const kKartonGroessen = <Merkmal>[
  (dbValue: 'gross', label: 'Großer Karton'),
  (dbValue: 'klein', label: 'Kleiner Karton'),
];

const kKartonBedruckungen = <Merkmal>[
  (dbValue: 'neutral', label: 'Neutral'),
  (dbValue: 'bedruckt', label: 'Bedruckt'),
];

/// Wie die Menge in die Packung kommt — entscheidet mit, welche Anlage
/// gebraucht wird (Zählen an der Mehrkopfwaage, Egalisieren am Band).
const kAbgabearten = <Merkmal>[
  (dbValue: 'gezaehlt', label: 'Gezählt'),
  (dbValue: 'gewogen', label: 'Gewogen'),
  (dbValue: 'egalisiert', label: 'Egalisiert'),
];

// ── Hilfen für gespeicherte Werte ─────────────────────────────────────

/// Kommaliste aus der Datenbank in einzelne dbValues zerlegen.
///
/// Leere Einträge fliegen raus, damit ein versehentliches „gluten,,eier"
/// nicht zu einem leeren Chip führt.
Set<String> merkmaleAusText(String? gespeichert) {
  if (gespeichert == null || gespeichert.trim().isEmpty) return <String>{};
  return gespeichert
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet();
}

/// Auswahl zurück in die Kommaliste — in der Reihenfolge der Liste,
/// nicht in der Klickreihenfolge, damit gleiche Auswahl immer denselben
/// Text ergibt (wichtig für Vergleiche im Excel-Diff).
String? merkmaleZuText(Iterable<String> auswahl, List<Merkmal> liste) {
  final gesetzt = auswahl.toSet();
  final sortiert = liste
      .map((m) => m.dbValue)
      .where(gesetzt.contains)
      .toList();
  return sortiert.isEmpty ? null : sortiert.join(',');
}

/// Klartext für die Anzeige, z.B. „Gluten, Eier".
String merkmaleLabel(String? gespeichert, List<Merkmal> liste) {
  final gesetzt = merkmaleAusText(gespeichert);
  return liste
      .where((m) => gesetzt.contains(m.dbValue))
      .map((m) => m.label)
      .join(', ');
}

/// Klartext einer Einfachauswahl.
String? merkmalLabel(String? dbValue, List<Merkmal> liste) {
  if (dbValue == null) return null;
  for (final m in liste) {
    if (m.dbValue == dbValue) return m.label;
  }
  return null;
}

/// Höchste Allergenstufe eines Artikels als Rang (0 = allergenfrei).
///
/// Der Wizard sortiert Tage danach aufsteigend. Rang = Position des
/// „spätesten" Allergens in [kAllergene], plus 1.
int allergenRang(String? gespeicherteAllergene) {
  final gesetzt = merkmaleAusText(gespeicherteAllergene);
  var rang = 0;
  for (var i = 0; i < kAllergene.length; i++) {
    if (gesetzt.contains(kAllergene[i].dbValue)) rang = i + 1;
  }
  return rang;
}
