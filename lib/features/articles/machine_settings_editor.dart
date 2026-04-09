import 'package:flutter/material.dart';

import '../../core/constants/bratstrasse_machines.dart';

/// Editor-Widget für Maschineneinstellungen eines Produktionsschritts.
///
/// Zeigt alle Maschinen als Checkbox-Liste. Aktivierte Maschinen
/// klappen auf und zeigen die jeweiligen Einstellungsfelder.
class MachineSettingsEditor extends StatefulWidget {
  const MachineSettingsEditor({
    super.key,
    required this.initialJson,
    required this.onChanged,
  });

  /// Aktueller JSON-String aus `maschinenEinstellungenJson`.
  final String? initialJson;

  /// Wird bei jeder Änderung aufgerufen mit dem neuen JSON.
  final ValueChanged<String> onChanged;

  @override
  State<MachineSettingsEditor> createState() => _MachineSettingsEditorState();
}

class _MachineSettingsEditorState extends State<MachineSettingsEditor> {
  late Map<String, Map<String, dynamic>> _settings;

  @override
  void initState() {
    super.initState();
    _settings = parseMachineSettings(widget.initialJson);
  }

  void _notify() {
    widget.onChanged(encodeMachineSettings(_settings));
  }

  void _toggleMachine(String key, bool enabled) {
    setState(() {
      _settings.putIfAbsent(key, () => {});
      _settings[key]!['enabled'] = enabled;
    });
    _notify();
  }

  void _updateSetting(String machineKey, String settingKey, dynamic value) {
    setState(() {
      _settings.putIfAbsent(machineKey, () => {'enabled': true});
      _settings[machineKey]![settingKey] = value;
    });
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Maschinen nach Kategorie gruppieren
    final grouped = <MachineCategory, List<MachineDefinition>>{};
    for (final m in kAllMachines) {
      grouped.putIfAbsent(m.category, () => []).add(m);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final category in MachineCategory.values) ...[
          if (grouped.containsKey(category)) ...[
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Text(
                _categoryLabel(category),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            ...grouped[category]!.map((machine) => _MachineCard(
                  machine: machine,
                  settings: _settings[machine.key] ?? {},
                  onToggle: (v) => _toggleMachine(machine.key, v),
                  onSettingChanged: (sk, v) =>
                      _updateSetting(machine.key, sk, v),
                )),
          ],
        ],
      ],
    );
  }

  String _categoryLabel(MachineCategory cat) {
    switch (cat) {
      case MachineCategory.vorbereitung:
        return 'Vorbereitung';
      case MachineCategory.bratstrasse:
        return 'Bratstraße';
      case MachineCategory.nachbereitung:
        return 'Nachbereitung';
    }
  }
}

// ---------------------------------------------------------------------------
// Karte für eine einzelne Maschine (Checkbox + Settings)
// ---------------------------------------------------------------------------

class _MachineCard extends StatelessWidget {
  const _MachineCard({
    required this.machine,
    required this.settings,
    required this.onToggle,
    required this.onSettingChanged,
  });

  final MachineDefinition machine;
  final Map<String, dynamic> settings;
  final ValueChanged<bool> onToggle;
  final void Function(String settingKey, dynamic value) onSettingChanged;

  bool get _enabled => settings['enabled'] == true;

  IconData _iconForMachine() {
    // Mapping der Icon-String-Referenzen auf Material Icons
    switch (machine.icon) {
      case 'precision_manufacturing':
        return Icons.precision_manufacturing;
      case 'water_drop':
        return Icons.water_drop;
      case 'layers':
        return Icons.layers;
      case 'egg':
        return Icons.egg;
      case 'content_cut':
        return Icons.content_cut;
      case 'compress':
        return Icons.compress;
      case 'rotate_right':
        return Icons.rotate_right;
      case 'opacity':
        return Icons.opacity;
      case 'local_fire_department':
        return Icons.local_fire_department;
      case 'whatshot':
        return Icons.whatshot;
      case 'ac_unit':
        return Icons.ac_unit;
      case 'scale':
        return Icons.scale;
      default:
        return Icons.settings;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header: Checkbox + Maschinenname
          CheckboxListTile(
            value: _enabled,
            onChanged: (v) => onToggle(v ?? false),
            secondary: Icon(
              _iconForMachine(),
              color: _enabled ? theme.colorScheme.primary : theme.disabledColor,
            ),
            title: Text(
              machine.label,
              style: TextStyle(
                fontWeight: _enabled ? FontWeight.w600 : FontWeight.normal,
                color: _enabled ? null : theme.disabledColor,
              ),
            ),
            dense: true,
            controlAffinity: ListTileControlAffinity.trailing,
          ),

          // Einstellungsfelder (nur wenn aktiviert)
          if (_enabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                children: machine.settings.map((setting) {
                  return _SettingField(
                    setting: setting,
                    value: settings[setting.key],
                    onChanged: (v) => onSettingChanged(setting.key, v),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Einzelnes Einstellungsfeld
// ---------------------------------------------------------------------------

class _SettingField extends StatelessWidget {
  const _SettingField({
    required this.setting,
    required this.value,
    required this.onChanged,
  });

  final MachineSetting setting;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    switch (setting.type) {
      case SettingType.bool_:
        return SwitchListTile(
          title: Text(setting.label),
          value: value == true,
          onChanged: (v) => onChanged(v),
          dense: true,
          contentPadding: EdgeInsets.zero,
        );

      case SettingType.number:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: TextFormField(
            initialValue: value?.toString() ?? '',
            decoration: InputDecoration(
              labelText: setting.label,
              suffixText: setting.unit,
              hintText: setting.hint,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (text) {
              if (text.isEmpty) {
                onChanged(null);
              } else {
                onChanged(num.tryParse(text.replaceAll(',', '.')));
              }
            },
          ),
        );

      case SettingType.text:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: TextFormField(
            initialValue: value?.toString() ?? '',
            decoration: InputDecoration(
              labelText: setting.label,
              hintText: setting.hint,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onChanged: (text) => onChanged(text.isEmpty ? null : text),
          ),
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Read-only Anzeige der Maschineneinstellungen (z.B. im Task-Detail)
// ---------------------------------------------------------------------------

class MachineSettingsDisplay extends StatelessWidget {
  const MachineSettingsDisplay({super.key, required this.json});

  final String? json;

  @override
  Widget build(BuildContext context) {
    final machines = enabledMachines(json);
    if (machines.isEmpty) return const SizedBox.shrink();

    final settings = parseMachineSettings(json);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Maschineneinstellungen',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        ...machines.map((machine) {
          final ms = settings[machine.key] ?? {};
          final entries = machine.settings
              .where((s) => ms[s.key] != null)
              .toList();

          if (entries.isEmpty) return const SizedBox.shrink();

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    machine.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...entries.map((s) {
                    final v = ms[s.key];
                    String display;
                    if (s.type == SettingType.bool_) {
                      display = v == true ? 'Ja' : 'Nein';
                    } else {
                      display = '${v}${s.unit != null ? ' ${s.unit}' : ''}';
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 180,
                            child: Text(
                              s.label,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              display,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
