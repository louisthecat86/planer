import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';

/// Dialog zum Bearbeiten eines einzelnen Produktions-Schritts.
///
/// Editierbare Felder (Phase A):
/// - Abteilung (Dropdown aus Abteilung-Enum)
/// - Prozessschritt (Freitext)
/// - Anlage (Dropdown aus Anlagen-Katalog, gefiltert nach Abteilung)
/// - Personen (Zahl, Default 1)
/// - Menge kg (Zahl)
/// - Dauer Minuten (Zahl)
///
/// Nicht in Phase A: Parameter-Gruppen, Reihenfolge ändern, Schritt
/// löschen. Das kommt in Phase B und C.
class StepEditorDialog extends ConsumerStatefulWidget {
  const StepEditorDialog({
    super.key,
    required this.step,
    required this.stepNumber,
  });

  final ProductStep step;
  final int stepNumber;

  /// Öffnet den Dialog. Gibt `true` zurück wenn gespeichert wurde,
  /// `false` wenn abgebrochen.
  static Future<bool> show(
    BuildContext context, {
    required ProductStep step,
    required int stepNumber,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StepEditorDialog(step: step, stepNumber: stepNumber),
    );
    return result ?? false;
  }

  @override
  ConsumerState<StepEditorDialog> createState() => _StepEditorDialogState();
}

class _StepEditorDialogState extends ConsumerState<StepEditorDialog> {
  // Form-State
  late String _abteilungDbValue;
  late TextEditingController _prozessschrittCtrl;
  String? _maschineId; // FK auf Machines
  late TextEditingController _personenCtrl;
  late TextEditingController _mengeCtrl;
  late TextEditingController _dauerMinCtrl;

  List<Machine> _alleMaschinen = [];
  bool _maschinenGeladen = false;
  bool _isSaving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    final step = widget.step;
    _abteilungDbValue = step.abteilung;
    _prozessschrittCtrl =
        TextEditingController(text: step.prozessschritt ?? '');
    _maschineId = step.maschineId;
    _personenCtrl =
        TextEditingController(text: step.basisMitarbeiter.toString());
    _mengeCtrl = TextEditingController(
      text: step.basisMengeKg > 0 ? _formatZahl(step.basisMengeKg) : '',
    );
    _dauerMinCtrl = TextEditingController(
      text: step.basisDauerMinuten > 0
          ? _formatZahl(step.basisDauerMinuten)
          : '',
    );
    _ladeMaschinen();
  }

  @override
  void dispose() {
    _prozessschrittCtrl.dispose();
    _personenCtrl.dispose();
    _mengeCtrl.dispose();
    _dauerMinCtrl.dispose();
    super.dispose();
  }

  Future<void> _ladeMaschinen() async {
    final db = ref.read(databaseProvider);
    final maschinen = await (db.select(db.machines)
          ..where((m) => m.deletedAt.isNull())
          ..orderBy([(m) => OrderingTerm.asc(m.name)]))
        .get();
    if (mounted) {
      setState(() {
        _alleMaschinen = maschinen;
        _maschinenGeladen = true;
      });
    }
  }

  /// Formatiert eine Zahl für die Anzeige im TextField (kein „123.0").
  String _formatZahl(double wert) {
    if (wert == wert.roundToDouble()) return wert.toInt().toString();
    return wert.toString();
  }

  /// Parst das Text-Feld zu einer Zahl (akzeptiert Komma und Punkt).
  double? _parseZahl(String text) {
    if (text.trim().isEmpty) return null;
    return double.tryParse(text.trim().replaceAll(',', '.'));
  }

  /// Maschinen gefiltert nach der gewählten Abteilung.
  /// Wenn keine Maschine zur Abteilung passt, werden alle gezeigt.
  List<Machine> get _maschinenGefiltert {
    final passend = _alleMaschinen
        .where((m) => m.abteilung == _abteilungDbValue)
        .toList();
    return passend.isEmpty ? _alleMaschinen : passend;
  }

  Future<void> _speichere() async {
    setState(() {
      _isSaving = true;
      _saveError = null;
    });

    final personen = int.tryParse(_personenCtrl.text.trim()) ?? 1;
    final menge = _parseZahl(_mengeCtrl.text) ?? 0.0;
    final dauer = _parseZahl(_dauerMinCtrl.text) ?? 0.0;
    final prozess = _prozessschrittCtrl.text.trim();

    try {
      final db = ref.read(databaseProvider);
      final maschineName = _maschineId != null
          ? _alleMaschinen
              .firstWhere(
                (m) => m.id == _maschineId,
                orElse: () => _alleMaschinen.first,
              )
              .name
          : null;

      await (db.update(db.productSteps)
            ..where((s) => s.id.equals(widget.step.id)))
          .write(
        ProductStepsCompanion(
          abteilung: Value(_abteilungDbValue),
          prozessschritt: Value(prozess.isEmpty ? null : prozess),
          maschineId: Value(_maschineId),
          maschine: Value(maschineName), // Legacy-Feld spiegeln
          basisMitarbeiter: Value(personen),
          basisMengeKg: Value(menge),
          mengeKg: Value(menge > 0 ? menge : null),
          basisDauerMinuten: Value(dauer),
          updatedAt: Value(DateTime.now()),
        ),
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saveError = 'Speichern fehlgeschlagen: $e';
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Schritt ${widget.stepNumber} bearbeiten'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Abteilung ────────────────────────────────────────────
              DropdownButtonFormField<String>(
                initialValue: _abteilungDbValue,
                decoration: const InputDecoration(
                  labelText: 'Abteilung',
                  border: OutlineInputBorder(),
                ),
                items: Abteilung.values
                    .map(
                      (a) => DropdownMenuItem(
                        value: a.dbValue,
                        child: Row(
                          children: [
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: a.farbe,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(a.anzeigeName),
                          ],
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _isSaving
                    ? null
                    : (v) {
                        if (v != null) {
                          setState(() {
                            _abteilungDbValue = v;
                            // Maschine zurücksetzen wenn sie nicht zur
                            // neuen Abteilung passt
                            if (_maschineId != null) {
                              final m = _alleMaschinen.firstWhere(
                                (x) => x.id == _maschineId,
                                orElse: () => _alleMaschinen.first,
                              );
                              if (m.abteilung != v) {
                                _maschineId = null;
                              }
                            }
                          });
                        }
                      },
              ),
              const SizedBox(height: 12),

              // ── Prozessschritt ───────────────────────────────────────
              TextField(
                controller: _prozessschrittCtrl,
                enabled: !_isSaving,
                decoration: const InputDecoration(
                  labelText: 'Prozessschritt (Freitext)',
                  hintText: 'z.B. "Braten", "Portionieren"',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // ── Anlage ───────────────────────────────────────────────
              if (!_maschinenGeladen)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                DropdownButtonFormField<String?>(
                  initialValue: _maschineId,
                  decoration: const InputDecoration(
                    labelText: 'Anlage',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text(
                        '— keine Anlage —',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ),
                    ..._maschinenGefiltert.map(
                      (m) => DropdownMenuItem<String?>(
                        value: m.id,
                        child: Text(m.name),
                      ),
                    ),
                  ],
                  onChanged: _isSaving
                      ? null
                      : (v) => setState(() => _maschineId = v),
                ),
              const SizedBox(height: 16),

              // ── Zahlen: Personen / Menge / Dauer ─────────────────────
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _personenCtrl,
                      enabled: !_isSaving,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Personen',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _mengeCtrl,
                      enabled: !_isSaving,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Menge',
                        suffixText: 'kg',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _dauerMinCtrl,
                      enabled: !_isSaving,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Dauer',
                        suffixText: 'min',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),

              if (_saveError != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _saveError!,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton.icon(
          onPressed: _isSaving || !_maschinenGeladen ? null : _speichere,
          icon: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save),
          label: Text(_isSaving ? 'Speichern …' : 'Speichern'),
        ),
      ],
    );
  }
}