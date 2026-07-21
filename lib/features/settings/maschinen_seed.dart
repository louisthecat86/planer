// GENERIERT aus Maschinenparameter.xlsx — Standard-Maschinenpark.
// Einmalige Katalog-Befüllung: legt fehlende Maschinen + ihre
// Steckbrief-Parameter an. Bestehende Maschinen bleiben unberührt.

/// Ein Parameter im Standard-Steckbrief einer Maschine.
class SeedParam {
  const SeedParam(this.name, this.einheit);
  final String name;
  final String? einheit;
}

/// Eine Standard-Maschine mit Abteilung und Steckbrief.
class SeedMaschine {
  const SeedMaschine(this.name, this.abteilung, this.params);
  final String name;
  final String abteilung;
  final List<SeedParam> params;
}

/// Der komplette Standard-Maschinenpark (Anzahl-2-Anlagen einzeln
/// nummeriert, z.B. „Verbufa 1"/„Verbufa 2").
const kSeedMaschinen = <SeedMaschine>[
  SeedMaschine('Kutter', 'kutterabteilung', [SeedParam('Temperatur', '°C'), SeedParam('Messergeschwindigkeit', 'U/min'), SeedParam('Vakuum', 'ja/ Nein'), SeedParam('Mischen', 'Vorwärts/ Rückwärts')]),
  SeedMaschine('Wolf', 'kutterabteilung', [SeedParam('Lochgröße', 'mm'), SeedParam('Trennsatz', 'Ja/ Nein')]),
  SeedMaschine('Schrankfroster', 'wurstkueche', [SeedParam('Abkühltemperatur', '°C'), SeedParam('Temperatur', '°C'), SeedParam('Zeit', 'Min Sek.')]),
  SeedMaschine('Multivac Verpackung', 'verpackung', [SeedParam('Programm', 'Gas/ vakuum'), SeedParam('Gasschaltpunkt', 'mBar'), SeedParam('Vakuumschaltpunkt', 'mBar'), SeedParam('Plattenanzahl', 'Zahl'), SeedParam('Verpackungsformat', 'Lang/ Kurz')]),
  SeedMaschine('Injektor', 'wurstkueche', [SeedParam('Programmauswahl', 'Zahl'), SeedParam('Injektionsdurchläufe', 'Zahl')]),
  SeedMaschine('Polter groß 1', 'wurstkueche', [SeedParam('Programmauswahl', 'Zahl'), SeedParam('Vakuum', 'Ja/ Nein')]),
  SeedMaschine('Polter groß 2', 'wurstkueche', [SeedParam('Programmauswahl', 'Zahl'), SeedParam('Vakuum', 'Ja/ Nein')]),
  SeedMaschine('Polter Pökelraum', 'wurstkueche', [SeedParam('Programmauswahl', 'Zahl'), SeedParam('Vakuum', 'Ja/Nein')]),
  SeedMaschine('Verbufa 1', 'bratstrasse', [SeedParam('Form', 'Bällchen/ Sticks'), SeedParam('Einsätze', 'Rund/ Eckig/ blind'), SeedParam('Taktung', 'Takte'), SeedParam('Messergröße', 'mm'), SeedParam('Messeröffnung', 'mm'), SeedParam('Überschneidung', 'mm'), SeedParam('Bandgeschwindigkeit Oben', 'm/s'), SeedParam('Bandgeschwindigkeit Unten', 'm/s'), SeedParam('Wasserzugabe', 'ms'), SeedParam('Pause', 'ms')]),
  SeedMaschine('Verbufa 2', 'bratstrasse', [SeedParam('Form', 'Bällchen/ Sticks'), SeedParam('Einsätze', 'Rund/ Eckig/ blind'), SeedParam('Taktung', 'Takte'), SeedParam('Messergröße', 'mm'), SeedParam('Messeröffnung', 'mm'), SeedParam('Überschneidung', 'mm'), SeedParam('Bandgeschwindigkeit Oben', 'm/s'), SeedParam('Bandgeschwindigkeit Unten', 'm/s'), SeedParam('Wasserzugabe', 'ms'), SeedParam('Pause', 'ms')]),
  SeedMaschine('Füllmaschine Bratstraße 1', 'bratstrasse', [SeedParam('Taktung', 'Takte'), SeedParam('Volumen', 'cm³'), SeedParam('Rückzug', 'cm³'), SeedParam('Portionspause', 'ms'), SeedParam('Clippzeit', 'ms')]),
  SeedMaschine('Füllmaschine Bratstraße 2', 'bratstrasse', [SeedParam('Taktung', 'Takte'), SeedParam('Volumen', 'cm³'), SeedParam('Rückzug', 'cm³'), SeedParam('Portionspause', 'ms'), SeedParam('Clippzeit', 'ms')]),
  SeedMaschine('Plattierer', 'bratstrasse', [SeedParam('Höhe', 'mm'), SeedParam('Band', 'fein/grob')]),
  SeedMaschine('Kochkammer 1-4', 'wurstkueche', [SeedParam('Programm', 'Zahl'), SeedParam('Besonderheiten', 'Text')]),
  SeedMaschine('Bratstraße', 'bratstrasse', [SeedParam('Plattentemperatur 1-10 Oben', '°C'), SeedParam('Plattentemperatur 1-10 Unten', '°C'), SeedParam('Zeit', 'Min Sek.'), SeedParam('Höhe', 'mm')]),
  SeedMaschine('Kombiofen', 'bratstrasse', [SeedParam('Plattentemperatur 1-12', '°C'), SeedParam('Temperatur Eingang', '°C'), SeedParam('Temperatur Ausgang', '°C'), SeedParam('Umluft', 'Hz'), SeedParam('Dampf', 'kg'), SeedParam('Zeit Eingang', 'Min Sek.'), SeedParam('Zeit Ausgang', 'Min Sek.')]),
  SeedMaschine('Froster Tef2', 'bratstrasse', [SeedParam('Abluftgeschwindigkeit Tunneleingang', 'UpM'), SeedParam('Abluftgeschwindigkeit Tunnelausgang', 'UpM'), SeedParam('Scrollgeschwindigkeit Eingang', 'UpM'), SeedParam('Scrollgeschwindigkeit Ausgang', 'UpM'), SeedParam('LIN-Injektion Oben Band Eingang', '°C'), SeedParam('LIN-Injektion Oben Band Ausgang', '°C'), SeedParam('Verweilzeit Band', 'Min'), SeedParam('Gesch. Gebläse 1-6', 'UpM'), SeedParam('Gesch. Gebläse 7-12', 'UpM'), SeedParam('Gesch. Gebläse 13-17', 'UpM'), SeedParam('Gesch. Gebläse 18-22', 'UpM')]),
  SeedMaschine('Multivac Tef2', 'bratstrasse', [SeedParam('Programm', 'Gas/ Vakuum'), SeedParam('Vakuumschaltpunkt', 'mbar'), SeedParam('Vakuum', 'sek.'), SeedParam('Gasschaltpunkt', 'mbar'), SeedParam('Gaszeizt', 'sek.'), SeedParam('Gasverteilzeit', 'sek.'), SeedParam('Siegeln', 'sek.'), SeedParam('Verzögerung belüftung unten', 'sek.'), SeedParam('Verzögerung belüftung oben', 'sek.'), SeedParam('Sicherheitszeit', 'sek.')]),
  SeedMaschine('Füllmaschine Wurstküche 1', 'wurstkueche', [SeedParam('Programm', 'Zahl'), SeedParam('Taktung', 'Takte'), SeedParam('Länge', 'mm'), SeedParam('Gewicht', 'cm³')]),
  SeedMaschine('Füllmaschine Wurstküche 2', 'wurstkueche', [SeedParam('Programm', 'Zahl'), SeedParam('Taktung', 'Takte'), SeedParam('Länge', 'mm'), SeedParam('Gewicht', 'cm³')]),
  SeedMaschine('Weber Slicer', 'schneideabteilung', [SeedParam('Programm', 'Zahl')]),
  SeedMaschine('Multivac Slicer', 'schneideabteilung', [SeedParam('Verpackungsart', 'Gewogen/ egalisiert')]),
  SeedMaschine('Multivac Würstchen Paarweise', 'verpackung', [SeedParam('Keine Einstellung nötig', null)]),
  SeedMaschine('Treif Würfelschneider 1', 'zerlegung', [SeedParam('Gatter 1', 'mm'), SeedParam('Gatter 2', 'mm'), SeedParam('Vorschub', 'mm')]),
  SeedMaschine('Treif Würfelschneider 2', 'zerlegung', [SeedParam('Gatter 1', 'mm'), SeedParam('Gatter 2', 'mm'), SeedParam('Vorschub', 'mm')]),
  SeedMaschine('Multivac Tef1', 'verpackung_tef1', [SeedParam('Programm', 'Gas/ vakuum'), SeedParam('Gasschaltpunkt', 'mBar'), SeedParam('Vakuumschaltpunkt', 'mBar'), SeedParam('Plattenanzahl', 'Zahl')]),
  SeedMaschine('Mehrkopfwage', 'bratstrasse', [SeedParam('Programm', 'Zahl'), SeedParam('Gewicht', 'g'), SeedParam('Rotation', 'Text')]),
  SeedMaschine('Scan Veagt', 'zerlegung', [SeedParam('Programm', 'Zahl'), SeedParam('Gewichtskorridor', 'Zahl'), SeedParam('Sortierer', 'ja/nein')]),
  SeedMaschine('Marel', 'zerlegung', [SeedParam('Programm', 'Zahl'), SeedParam('Gewichtskorridor', 'Zahl'), SeedParam('Sortierer', 'ja/nein')]),
  SeedMaschine('Röntgendetektor', 'bratstrasse', [SeedParam('Programme', 'Zahl')]),
  SeedMaschine('Metalldetektoren', 'verpackung', [SeedParam('Programme', 'Zahl')]),
  SeedMaschine('Rollenschneider 1', 'zerlegung', [SeedParam('Messergröße', 'mm')]),
  SeedMaschine('Rollenschneider 2', 'zerlegung', [SeedParam('Messergröße', 'mm')]),
  SeedMaschine('Panieranlage', 'bratstrasse', []),
  SeedMaschine('Volleianlage', 'bratstrasse', []),
  SeedMaschine('Hebevorrichtung', 'bratstrasse', []),
  SeedMaschine('Öl-/ Wasserzugabe', 'bratstrasse', []),
  SeedMaschine('Abschneidevorrichtung', 'bratstrasse', []),
  SeedMaschine('Clipper', 'bratstrasse', []),
  SeedMaschine('Abfließer', 'bratstrasse', []),
  SeedMaschine('Säge', 'bratstrasse', []),
];
