import 'dart:convert';

// ---------------------------------------------------------------------------
// Maschinen-Definitionen — pro Abteilung mit einzelnen Instanzen
// ---------------------------------------------------------------------------

/// Datentyp eines Maschineneinstellungs-Felds.
enum SettingType { number, bool_, text }

/// Ein einzelnes Einstellungsfeld einer Maschine.
class MachineSetting {
  const MachineSetting({
    required this.key,
    required this.label,
    required this.type,
    this.unit,
    this.hint,
  });

  final String key;
  final String label;
  final SettingType type;
  final String? unit;
  final String? hint;
}

/// Definition einer Maschine (Typ + Instanzen + Einstellungen).
class MachineDefinition {
  const MachineDefinition({
    required this.key,
    required this.label,
    required this.abteilung,
    required this.settings,
    this.instances = 1,
  });

  final String key;
  final String label;

  /// Abteilungs-dbValue, zu der diese Maschine gehört.
  final String abteilung;

  /// Mögliche Einstellungsfelder.
  final List<MachineSetting> settings;

  /// Anzahl Instanzen (z.B. 2 = "Verbufa 1", "Verbufa 2").
  final int instances;

  /// Key für eine bestimmte Instanz.
  String instanceKey(int nr) => instances > 1 ? '${key}_$nr' : key;

  /// Label für eine bestimmte Instanz.
  String instanceLabel(int nr) => instances > 1 ? '$label $nr' : label;
}

// ---------------------------------------------------------------------------
// Alle Maschinen gruppiert nach Abteilung
// ---------------------------------------------------------------------------

const kAllMachines = <MachineDefinition>[
  // ===== ZERLEGUNG =====
  MachineDefinition(
    key: 'scanveagt',
    label: 'ScanVeagt',
    abteilung: 'zerlegung',
    settings: [
      MachineSetting(key: 'programm', label: 'Programm', type: SettingType.text),
      MachineSetting(key: 'notizen', label: 'Hinweise', type: SettingType.text),
    ],
  ),
  MachineDefinition(
    key: 'saege',
    label: 'Säge',
    abteilung: 'zerlegung',
    settings: [
      MachineSetting(key: 'schnittstaerke', label: 'Schnittstärke', type: SettingType.number, unit: 'mm'),
      MachineSetting(key: 'notizen', label: 'Hinweise', type: SettingType.text),
    ],
  ),
  MachineDefinition(
    key: 'rollenschneider_z',
    label: 'Rollenschneider',
    abteilung: 'zerlegung',
    settings: [
      MachineSetting(key: 'breite', label: 'Schnittbreite', type: SettingType.number, unit: 'mm'),
      MachineSetting(key: 'geschwindigkeit', label: 'Geschwindigkeit', type: SettingType.number, unit: 'm/min'),
      MachineSetting(key: 'notizen', label: 'Hinweise', type: SettingType.text),
    ],
  ),
  MachineDefinition(
    key: 'plattierer_z',
    label: 'Plattierer',
    abteilung: 'zerlegung',
    settings: [
      MachineSetting(key: 'zieldicke', label: 'Zieldicke', type: SettingType.number, unit: 'mm'),
      MachineSetting(key: 'notizen', label: 'Hinweise', type: SettingType.text),
    ],
  ),
  MachineDefinition(
    key: 'abfliesser',
    label: 'Abfließer',
    abteilung: 'zerlegung',
    settings: [
      MachineSetting(key: 'notizen', label: 'Hinweise', type: SettingType.text),
    ],
  ),

  // ===== WURSTKÜCHE =====
  MachineDefinition(
    key: 'gekuehlte_polter',
    label: 'Gekühlte Polter',
    abteilung: 'wurstkueche',
    instances: 2,
    settings: [
      MachineSetting(key: 'temperatur', label: 'Temperatur', type: SettingType.number, unit: '°C'),
      MachineSetting(key: 'notizen', label: 'Hinweise', type: SettingType.text),
    ],
  ),
  MachineDefinition(
    key: 'kochkammer',
    label: 'Kochkammer',
    abteilung: 'wurstkueche',
    instances: 4,
    settings: [
      MachineSetting(key: 'kammerprogramm', label: 'Kammerprogramm', type: SettingType.text, hint: 'z.B. Programm 12 / Räuchern+Kochen'),
      MachineSetting(key: 'raeuchern', label: 'Räucherfunktion', type: SettingType.bool_),
      MachineSetting(key: 'notizen', label: 'Hinweise', type: SettingType.text),
    ],
  ),
  MachineDefinition(
    key: 'fuellmaschine_wk',
    label: 'Füllmaschine',
    abteilung: 'wurstkueche',
    instances: 2,
    settings: [
      MachineSetting(key: 'portionsgewicht', label: 'Portionsgewicht', type: SettingType.number, unit: 'g'),
      MachineSetting(key: 'geschwindigkeit', label: 'Geschwindigkeit', type: SettingType.number, unit: 'Stk/min'),
      MachineSetting(key: 'notizen', label: 'Hinweise', type: SettingType.text),
    ],
  ),
  MachineDefinition(
    key: 'hebevorrichtung_wk',
    label: 'Hebevorrichtung',
    abteilung: 'wurstkueche',
    settings: [
      MachineSetting(key: 'notizen', label: 'Hinweise', type: SettingType.text),
    ],
  ),
  MachineDefinition(
    key: 'clippanlage',
    label: 'Clippanlage',
    abteilung: 'wurstkueche',
    settings: [
      MachineSetting(key: 'clipgroesse', label: 'Clipgröße', type: SettingType.text),
      MachineSetting(key: 'notizen', label: 'Hinweise', type: SettingType.text),
    ],
  ),

  // ===== KUTTERABTEILUNG =====
  MachineDefinition(
    key: 'kutter',
    label: 'Kutter',
    abteilung: 'kutterabteilung',
    settings: [
      MachineSetting(key: 'drehzahl', label: 'Drehzahl', type: SettingType.number, unit: 'U/min'),
      MachineSetting(key: 'temperatur', label: 'Ziel-Temperatur', type: SettingType.number, unit: '°C'),
      MachineSetting(key: 'laufzeit', label: 'Laufzeit', type: SettingType.number, unit: 'min'),
      MachineSetting(key: 'notizen', label: 'Hinweise', type: SettingType.text),
    ],
  ),
  MachineDefinition(
    key: 'fleischwolf',
    label: 'Fleischwolf',
    abteilung: 'kutterabteilung',
    settings: [
      MachineSetting(key: 'lochscheibe', label: 'Lochscheibe', type: SettingType.number, unit: 'mm'),
      MachineSetting(key: 'notizen', label: 'Hinweise', type: SettingType.text),
    ],
  ),

  // ===== BRATSTRASSE =====
  MachineDefinition(
    key: 'bratplatten',
    label: 'Bratstraße',
    abteilung: 'bratstrasse',
    settings: [
      MachineSetting(key: 'tempOben', label: 'Temperatur oben', type: SettingType.number, unit: '°C'),
      MachineSetting(key: 'tempUnten', label: 'Temperatur unten', type: SettingType.number, unit: '°C'),
      MachineSetting(key: 'durchlaufzeit', label: 'Durchlaufzeit', type: SettingType.number, unit: 'min'),
      MachineSetting(key: 'hoehe', label: 'Höhe Bratplatten', type: SettingType.number, unit: 'mm'),
      MachineSetting(key: 'notizen', label: 'Hinweise', type: SettingType.text),
    ],
  ),
  MachineDefinition(
    key: 'heissluftofen',
    label: 'Heißluftofen',
    abteilung: 'bratstrasse',
    settings: [
      MachineSetting(key: 'plattenTemp', label: 'Plattentemperatur', type: SettingType.number, unit: '°C'),
      MachineSetting(key: 'tempEingang', label: 'Temperatur Ofeneingang', type: SettingType.number, unit: '°C'),
      MachineSetting(key: 'tempAusgang', label: 'Temperatur Ofenausgang', type: SettingType.number, unit: '°C'),
      MachineSetting(key: 'luefterHz', label: 'Lüfter-Frequenz', type: SettingType.number, unit: 'Hz'),
      MachineSetting(key: 'dampfzugabe', label: 'Dampfzugabe', type: SettingType.bool_),
      MachineSetting(key: 'dampfKg', label: 'Dampf-Menge', type: SettingType.number, unit: 'kg'),
      MachineSetting(key: 'bandEingang', label: 'Bandgeschwindigkeit Eingang', type: SettingType.number, unit: 'm/min'),
      MachineSetting(key: 'bandAusgang', label: 'Bandgeschwindigkeit Ausgang', type: SettingType.number, unit: 'm/min'),
      MachineSetting(key: 'notizen', label: 'Hinweise', type: SettingType.text),
    ],
  ),
  MachineDefinition(
    key: 'schockfroster',
    label: 'Schockfroster',
    abteilung: 'bratstrasse',
    settings: [
      MachineSetting(key: 'zielTemp', label: 'Ziel-Kerntemperatur', type: SettingType.number, unit: '°C'),
      MachineSetting(key: 'tunnelTemp', label: 'Tunneltemperatur', type: SettingType.number, unit: '°C'),
      MachineSetting(key: 'durchlaufzeit', label: 'Durchlaufzeit', type: SettingType.number, unit: 'min'),
      MachineSetting(key: 'notizen', label: 'Hinweise', type: SettingType.text),
    ],
  ),
  MachineDefinition(
    key: 'mehrkopfwaage',
    label: 'Mehrkopfwaage',
    abteilung: 'bratstrasse',
    settings: [
      MachineSetting(key: 'zielgewicht', label: 'Zielgewicht', type: SettingType.number, unit: 'g'),
      MachineSetting(key: 'toleranzPlus', label: 'Toleranz +', type: SettingType.number, unit: 'g'),
      MachineSetting(key: 'toleranzMinus', label: 'Toleranz −', type: SettingType.number, unit: 'g'),
      MachineSetting(key: 'geschwindigkeit', label: 'Geschwindigkeit', type: SettingType.number, unit: 'Pkg/min'),
      MachineSetting(key: 'notizen', label: 'Hinweise', type: SettingType.text),
    ],
  ),
  MachineDefinition(
    key: 'panieranlage',
    label: 'Panieranlage',
    abteilung: 'bratstrasse',
    settings: [
      MachineSetting(key: 'panierart', label: 'Panierart', type: SettingType.text, hint: 'z.B. Mehl, Panko, Semmelbrösel'),
      MachineSetting(key: 'bandgeschwindigkeit', label: 'Bandgeschwindigkeit', type: SettingType.number, unit: 'm/min'),
      MachineSetting(key: 'notizen', label: 'Hinweise', type: SettingType.text),
    ],
  ),
  MachineDefinition(
    key: 'volleimaschine',
    label: 'Volleimaschine',
    abteilung: 'bratstrasse',
    settings: [
      MachineSetting(key: 'menge', label: 'Menge', type: SettingType.number, unit: 'kg'),
      MachineSetting(key: 'notizen', label: 'Hinweise', type: SettingType.text),
    ],
  ),
  MachineDefinition(
    key: 'abschneider_b',
    label: 'Abschneidervorrichtung',
    abteilung: 'bratstrasse',
    settings: [
      MachineSetting(key: 'schnittstaerke', label: 'Schnittstärke', type: SettingType.number, unit: 'mm'),
      MachineSetting(key: 'geschwindigkeit', label: 'Geschwindigkeit', type: SettingType.number, unit: 'Stk/min'),
      MachineSetting(key: 'notizen', label: 'Hinweise', type: SettingType.text),
    ],
  ),
  MachineDefinition(
    key: 'hebevorrichtung_b',
    label: 'Hebevorrichtung',
    abteilung: 'bratstrasse',
    settings: [
      MachineSetting(key: 'notizen', label: 'Hinweise', type: SettingType.text),
    ],
  ),
  MachineDefinition(
    key: 'plattierer_b',
    label: 'Plattierer',
    abteilung: 'bratstrasse',
    settings: [
      MachineSetting(key: 'zieldicke', label: 'Zieldicke', type: SettingType.number, unit: 'mm'),
      MachineSetting(key: 'notizen', label: 'Hinweise', type: SettingType.text),
    ],
  ),
  MachineDefinition(
    key: 'verbufa',
    label: 'Verbufa',
    abteilung: 'bratstrasse',
    instances: 2,
    settings: [
      MachineSetting(key: 'geschwindigkeit', label: 'Geschwindigkeit', type: SettingType.number, unit: 'm/min'),
      MachineSetting(key: 'notizen', label: 'Hinweise', type: SettingType.text),
    ],
  ),
  MachineDefinition(
    key: 'fuellmaschine_b',
    label: 'Füllmaschine',
    abteilung: 'bratstrasse',
    instances: 2,
    settings: [
      MachineSetting(key: 'portionsgewicht', label: 'Portionsgewicht', type: SettingType.number, unit: 'g'),
      MachineSetting(key: 'geschwindigkeit', label: 'Geschwindigkeit', type: SettingType.number, unit: 'Stk/min'),
      MachineSetting(key: 'notizen', label: 'Hinweise', type: SettingType.text),
    ],
  ),

  // ===== SCHNEIDEABTEILUNG =====
  MachineDefinition(
    key: 'weberslicer',
    label: 'Weberslicer',
    abteilung: 'schneideabteilung',
    settings: [
      MachineSetting(key: 'schnittstaerke', label: 'Schnittstärke', type: SettingType.number, unit: 'mm'),
      MachineSetting(key: 'geschwindigkeit', label: 'Geschwindigkeit', type: SettingType.number, unit: 'Scheiben/min'),
      MachineSetting(key: 'notizen', label: 'Hinweise', type: SettingType.text),
    ],
  ),
  MachineDefinition(
    key: 'kotelethacker',
    label: 'Kotelethacker',
    abteilung: 'schneideabteilung',
    settings: [
      MachineSetting(key: 'schnittstaerke', label: 'Schnittstärke', type: SettingType.number, unit: 'mm'),
      MachineSetting(key: 'notizen', label: 'Hinweise', type: SettingType.text),
    ],
  ),

  // ===== VERPACKUNG =====
  MachineDefinition(
    key: 'multivac_alt',
    label: 'Multivac Anlage Alt',
    abteilung: 'verpackung',
    settings: [
      MachineSetting(key: 'programm', label: 'Programm', type: SettingType.text),
      MachineSetting(key: 'siegeltemp', label: 'Siegeltemperatur', type: SettingType.number, unit: '°C'),
      MachineSetting(key: 'vakuumzeit', label: 'Vakuumzeit', type: SettingType.number, unit: 's'),
      MachineSetting(key: 'notizen', label: 'Hinweise', type: SettingType.text),
    ],
  ),
  MachineDefinition(
    key: 'multivac_neu',
    label: 'Multivac Anlage Neu',
    abteilung: 'verpackung',
    settings: [
      MachineSetting(key: 'programm', label: 'Programm', type: SettingType.text),
      MachineSetting(key: 'siegeltemp', label: 'Siegeltemperatur', type: SettingType.number, unit: '°C'),
      MachineSetting(key: 'vakuumzeit', label: 'Vakuumzeit', type: SettingType.number, unit: 's'),
      MachineSetting(key: 'notizen', label: 'Hinweise', type: SettingType.text),
    ],
  ),

  // ===== VERPACKUNG TEF1 =====
  MachineDefinition(
    key: 'multivac_tef1',
    label: 'Multivac Anlage',
    abteilung: 'verpackung_tef1',
    settings: [
      MachineSetting(key: 'programm', label: 'Programm', type: SettingType.text),
      MachineSetting(key: 'siegeltemp', label: 'Siegeltemperatur', type: SettingType.number, unit: '°C'),
      MachineSetting(key: 'vakuumzeit', label: 'Vakuumzeit', type: SettingType.number, unit: 's'),
      MachineSetting(key: 'notizen', label: 'Hinweise', type: SettingType.text),
    ],
  ),
];

// ---------------------------------------------------------------------------
// Hilfsfunktionen
// ---------------------------------------------------------------------------

/// Alle Maschinen einer Abteilung (mit aufgelösten Instanzen).
List<MachineInstance> machinesForDepartment(String abteilungDbValue) {
  final result = <MachineInstance>[];
  for (final m in kAllMachines) {
    if (m.abteilung != abteilungDbValue) continue;
    for (var i = 1; i <= m.instances; i++) {
      result.add(MachineInstance(
        definition: m,
        instanceNr: i,
        key: m.instanceKey(i),
        label: m.instanceLabel(i),
      ),);
    }
  }
  return result;
}

/// Eine konkrete Maschineninstanz (z.B. "Verbufa 2").
class MachineInstance {
  const MachineInstance({
    required this.definition,
    required this.instanceNr,
    required this.key,
    required this.label,
  });

  final MachineDefinition definition;
  final int instanceNr;
  final String key;
  final String label;
}

/// Liest maschinenEinstellungenJson → Map<instanceKey, settings>.
Map<String, Map<String, dynamic>> parseMachineSettings(String? json) {
  if (json == null || json.isEmpty) return {};
  try {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    return decoded.map(
      (key, value) => MapEntry(key, (value as Map<String, dynamic>)),
    );
  } catch (_) {
    return {};
  }
}

/// Serialisiert — entfernt nicht-aktivierte Maschinen.
String encodeMachineSettings(Map<String, Map<String, dynamic>> settings) {
  final cleaned = Map<String, Map<String, dynamic>>.from(settings)
    ..removeWhere((_, v) => v['enabled'] != true);
  return jsonEncode(cleaned);
}

/// Gibt die MachineDefinition für einen Key zurück (ohne Instanznummer).
MachineDefinition? machineDefByKey(String key) {
  // Entferne ggf. Instanznummer (_1, _2, ...)
  final baseKey = key.replaceAll(RegExp(r'_\d+$'), '');
  for (final m in kAllMachines) {
    if (m.key == key || m.key == baseKey) return m;
  }
  return null;
}

/// Alle aktivierten Maschinen-Instanzen aus dem Settings-JSON.
List<MachineInstance> enabledMachines(String? json) {
  final settings = parseMachineSettings(json);
  final result = <MachineInstance>[];
  for (final entry in settings.entries) {
    if (entry.value['enabled'] != true) continue;
    final def = machineDefByKey(entry.key);
    if (def == null) continue;
    // Instanznummer aus Key extrahieren
    final match = RegExp(r'_(\d+)$').firstMatch(entry.key);
    final nr = match != null ? int.parse(match.group(1)!) : 1;
    result.add(MachineInstance(
      definition: def,
      instanceNr: nr,
      key: entry.key,
      label: def.instances > 1 ? '${def.label} $nr' : def.label,
    ),);
  }
  return result;
}
