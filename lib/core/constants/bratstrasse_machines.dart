import 'dart:convert';

// ---------------------------------------------------------------------------
// Maschinen-Definitionen für die Bratstraße (und Vorbereitungsmaschinen)
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

/// Definition einer Maschine (Typ + mögliche Einstellungen).
class MachineDefinition {
  const MachineDefinition({
    required this.key,
    required this.label,
    required this.icon,
    required this.category,
    required this.settings,
  });

  final String key;
  final String label;
  final String icon; // Material-Icon-Name als Referenz
  final MachineCategory category;
  final List<MachineSetting> settings;
}

enum MachineCategory { vorbereitung, bratstrasse, nachbereitung }

// ---------------------------------------------------------------------------
// Alle bekannten Maschinen
// ---------------------------------------------------------------------------

const kAllMachines = <MachineDefinition>[
  // --- Vorbereitungsmaschinen ---
  MachineDefinition(
    key: 'verbufa',
    label: 'Verbufa',
    icon: 'precision_manufacturing',
    category: MachineCategory.vorbereitung,
    settings: [
      MachineSetting(key: 'geschwindigkeit', label: 'Geschwindigkeit', type: SettingType.number, unit: 'm/min'),
      MachineSetting(key: 'notizen', label: 'Notizen', type: SettingType.text),
    ],
  ),
  MachineDefinition(
    key: 'fuellmaschine',
    label: 'Füllmaschine',
    icon: 'water_drop',
    category: MachineCategory.vorbereitung,
    settings: [
      MachineSetting(key: 'portionsgewicht', label: 'Portionsgewicht', type: SettingType.number, unit: 'g'),
      MachineSetting(key: 'geschwindigkeit', label: 'Geschwindigkeit', type: SettingType.number, unit: 'Stk/min'),
      MachineSetting(key: 'notizen', label: 'Notizen', type: SettingType.text),
    ],
  ),
  MachineDefinition(
    key: 'panieranlage',
    label: 'Panieranlage',
    icon: 'layers',
    category: MachineCategory.vorbereitung,
    settings: [
      MachineSetting(key: 'panierart', label: 'Panierart', type: SettingType.text, hint: 'z.B. Mehl, Panko, Semmelbrösel'),
      MachineSetting(key: 'bandgeschwindigkeit', label: 'Bandgeschwindigkeit', type: SettingType.number, unit: 'm/min'),
      MachineSetting(key: 'notizen', label: 'Notizen', type: SettingType.text),
    ],
  ),
  MachineDefinition(
    key: 'volleimaschine',
    label: 'Volleimaschine',
    icon: 'egg',
    category: MachineCategory.vorbereitung,
    settings: [
      MachineSetting(key: 'menge', label: 'Menge', type: SettingType.number, unit: 'kg'),
      MachineSetting(key: 'notizen', label: 'Notizen', type: SettingType.text),
    ],
  ),
  MachineDefinition(
    key: 'abschneider',
    label: 'Abschneider',
    icon: 'content_cut',
    category: MachineCategory.vorbereitung,
    settings: [
      MachineSetting(key: 'schnittstaerke', label: 'Schnittstärke', type: SettingType.number, unit: 'mm'),
      MachineSetting(key: 'geschwindigkeit', label: 'Geschwindigkeit', type: SettingType.number, unit: 'Stk/min'),
      MachineSetting(key: 'notizen', label: 'Notizen', type: SettingType.text),
    ],
  ),
  MachineDefinition(
    key: 'plattierer',
    label: 'Plattierer',
    icon: 'compress',
    category: MachineCategory.vorbereitung,
    settings: [
      MachineSetting(key: 'zieldicke', label: 'Zieldicke', type: SettingType.number, unit: 'mm'),
      MachineSetting(key: 'notizen', label: 'Notizen', type: SettingType.text),
    ],
  ),
  MachineDefinition(
    key: 'rollenschneider',
    label: 'Rollenschneider',
    icon: 'rotate_right',
    category: MachineCategory.vorbereitung,
    settings: [
      MachineSetting(key: 'breite', label: 'Schnittbreite', type: SettingType.number, unit: 'mm'),
      MachineSetting(key: 'geschwindigkeit', label: 'Geschwindigkeit', type: SettingType.number, unit: 'm/min'),
      MachineSetting(key: 'notizen', label: 'Notizen', type: SettingType.text),
    ],
  ),
  MachineDefinition(
    key: 'oelzugabe',
    label: 'Ölzugabe',
    icon: 'opacity',
    category: MachineCategory.vorbereitung,
    settings: [
      MachineSetting(key: 'oelart', label: 'Ölart', type: SettingType.text, hint: 'z.B. Sonnenblumenöl, Rapsöl'),
      MachineSetting(key: 'menge', label: 'Menge', type: SettingType.number, unit: 'ml/kg'),
      MachineSetting(key: 'notizen', label: 'Notizen', type: SettingType.text),
    ],
  ),

  // --- Bratstraße ---
  MachineDefinition(
    key: 'bratplatten',
    label: 'Bratplatten',
    icon: 'local_fire_department',
    category: MachineCategory.bratstrasse,
    settings: [
      MachineSetting(key: 'tempOben', label: 'Temperatur oben', type: SettingType.number, unit: '°C'),
      MachineSetting(key: 'tempUnten', label: 'Temperatur unten', type: SettingType.number, unit: '°C'),
      MachineSetting(key: 'durchlaufzeit', label: 'Durchlaufzeit', type: SettingType.number, unit: 'min'),
      MachineSetting(key: 'hoehe', label: 'Höhe Bratplatten', type: SettingType.number, unit: 'mm'),
      MachineSetting(key: 'notizen', label: 'Notizen', type: SettingType.text),
    ],
  ),
  MachineDefinition(
    key: 'heissluftofen',
    label: 'Heißluftofen',
    icon: 'whatshot',
    category: MachineCategory.bratstrasse,
    settings: [
      MachineSetting(key: 'plattenTemp', label: 'Plattentemperatur', type: SettingType.number, unit: '°C'),
      MachineSetting(key: 'tempEingang', label: 'Temperatur Ofeneingang', type: SettingType.number, unit: '°C'),
      MachineSetting(key: 'tempAusgang', label: 'Temperatur Ofenausgang', type: SettingType.number, unit: '°C'),
      MachineSetting(key: 'luefterHz', label: 'Lüfter-Frequenz', type: SettingType.number, unit: 'Hz'),
      MachineSetting(key: 'dampfzugabe', label: 'Dampfzugabe', type: SettingType.bool_),
      MachineSetting(key: 'dampfKg', label: 'Dampf-Menge', type: SettingType.number, unit: 'kg'),
      MachineSetting(key: 'bandEingang', label: 'Bandgeschwindigkeit Eingang', type: SettingType.number, unit: 'm/min'),
      MachineSetting(key: 'bandAusgang', label: 'Bandgeschwindigkeit Ausgang', type: SettingType.number, unit: 'm/min'),
      MachineSetting(key: 'notizen', label: 'Notizen', type: SettingType.text),
    ],
  ),

  // --- Nachbereitung ---
  MachineDefinition(
    key: 'schockfrost',
    label: 'Schockfrosttunnel',
    icon: 'ac_unit',
    category: MachineCategory.nachbereitung,
    settings: [
      MachineSetting(key: 'zielTemp', label: 'Ziel-Kerntemperatur', type: SettingType.number, unit: '°C'),
      MachineSetting(key: 'tunnelTemp', label: 'Tunneltemperatur', type: SettingType.number, unit: '°C'),
      MachineSetting(key: 'durchlaufzeit', label: 'Durchlaufzeit', type: SettingType.number, unit: 'min'),
      MachineSetting(key: 'notizen', label: 'Notizen', type: SettingType.text),
    ],
  ),
  MachineDefinition(
    key: 'mehrkopfwaage',
    label: 'Mehrkopfwaage',
    icon: 'scale',
    category: MachineCategory.nachbereitung,
    settings: [
      MachineSetting(key: 'zielgewicht', label: 'Zielgewicht', type: SettingType.number, unit: 'g'),
      MachineSetting(key: 'toleranzPlus', label: 'Toleranz +', type: SettingType.number, unit: 'g'),
      MachineSetting(key: 'toleranzMinus', label: 'Toleranz −', type: SettingType.number, unit: 'g'),
      MachineSetting(key: 'geschwindigkeit', label: 'Geschwindigkeit', type: SettingType.number, unit: 'Pkg/min'),
      MachineSetting(key: 'notizen', label: 'Notizen', type: SettingType.text),
    ],
  ),
];

// ---------------------------------------------------------------------------
// Hilfsfunktionen zum Lesen/Schreiben des JSON
// ---------------------------------------------------------------------------

/// Liest das maschinenEinstellungenJson und gibt eine Map zurück.
/// Beispiel-Struktur:
/// ```json
/// {
///   "bratplatten": { "enabled": true, "tempOben": 220, "tempUnten": 180, ... },
///   "heissluftofen": { "enabled": true, "plattenTemp": 200, ... },
///   "verbufa": { "enabled": false }
/// }
/// ```
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

/// Serialisiert die Maschineneinstellungen zurück in JSON.
String encodeMachineSettings(Map<String, Map<String, dynamic>> settings) {
  // Entferne Maschinen die nicht aktiviert sind
  final cleaned = Map<String, Map<String, dynamic>>.from(settings)
    ..removeWhere((_, v) => v['enabled'] != true);
  return jsonEncode(cleaned);
}

/// Gibt die MachineDefinition für einen Key zurück.
MachineDefinition? machineByKey(String key) {
  for (final m in kAllMachines) {
    if (m.key == key) return m;
  }
  return null;
}

/// Alle aktivierten Maschinen aus den Einstellungen.
List<MachineDefinition> enabledMachines(String? json) {
  final settings = parseMachineSettings(json);
  return settings.entries
      .where((e) => e.value['enabled'] == true)
      .map((e) => machineByKey(e.key))
      .whereType<MachineDefinition>()
      .toList();
}
