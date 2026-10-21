import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';
import '../../core/ui/bausteine.dart';
import '../../core/utils/fehler_text.dart';

/// Dialog zum Anlegen oder Bearbeiten eines Custom-Parameters.
///
/// Custom-Parameter sind Parameter die nicht aus der Excel-Vorlage stammen,
/// sondern in der App vom Nutzer angelegt wurden. Sie haben:
/// - `parameterGruppe = 'CUSTOM'`
/// - `istCustom = true`
/// - frei wählbarer Name und Wert
///
/// Wird beim Excel-Export in den „ZUSÄTZLICHE PARAMETER"-Block der
/// Vorlage geschrieben.
class CustomParameterEditorDialog extends ConsumerStatefulWidget {
  const CustomParameterEditorDialog({
    super.key,
    required this.stepId,
    this.existingParameter,
  });

  final String stepId;

  /// Wenn nicht null: Bearbeiten-Modus. Sonst: Neu-Anlegen.
  final ProductStepParameter? existingParameter;

  /// Öffnet den Dialog. Gibt `true` zurück wenn gespeichert wurde,
  /// `false` bei Abbruch.
  static Future<bool> show(
    BuildContext context, {
    required String stepId,
    ProductStepParameter? existingParameter,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CustomParameterEditorDialog(
        stepId: stepId,
        existingParameter: existingParameter,
      ),
    );
    return result ?? false;
  }

  @override
  ConsumerState<CustomParameterEditorDialog> createState() =>
      _CustomParameterEditorDialogState();
}

class _CustomParameterEditorDialogState
    extends ConsumerState<CustomParameterEditorDialog> {
  late TextEditingController _nameCtrl;
  late TextEditingController _wertCtrl;
  bool _isSaving = false;
  String? _saveError;

  bool get _istBearbeiten => widget.existingParameter != null;

  @override
  void initState() {
    super.initState();
    final ex = widget.existingParameter;
    _nameCtrl = TextEditingController(text: ex?.parameterName ?? '');
    _wertCtrl = TextEditingController(text: ex?.wert ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _wertCtrl.dispose();
    super.dispose();
  }

  Future<void> _speichere() async {
    final name = _nameCtrl.text.trim();
    final wert = _wertCtrl.text.trim();

    if (name.isEmpty) {
      setState(() {
        _saveError = 'Name darf nicht leer sein.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _saveError = null;
    });

    try {
      final db = ref.read(databaseProvider);

      if (_istBearbeiten) {
        await (db.update(db.productStepParameters)
              ..where((p) => p.id.equals(widget.existingParameter!.id)))
            .write(
          ProductStepParametersCompanion(
            parameterName: Value(name),
            wert: Value(wert.isEmpty ? null : wert),
            updatedAt: Value(DateTime.now()),
          ),
        );
      } else {
        // Reihenfolge: nächster freier Slot in der Gruppe „CUSTOM"
        final letzte = await (db.select(db.productStepParameters)
              ..where((p) => p.stepId.equals(widget.stepId))
              ..where((p) => p.parameterGruppe.equals('CUSTOM'))
              ..orderBy([(p) => OrderingTerm.desc(p.reihenfolge)])
              ..limit(1))
            .getSingleOrNull();
        final naechsteReihenfolge = (letzte?.reihenfolge ?? -1) + 1;

        await db.into(db.productStepParameters).insert(
              ProductStepParametersCompanion(
                id: Value(const Uuid().v4()),
                stepId: Value(widget.stepId),
                parameterGruppe: const Value('CUSTOM'),
                parameterName: Value(name),
                wert: Value(wert.isEmpty ? null : wert),
                reihenfolge: Value(naechsteReihenfolge),
                istCustom: const Value(true),
              ),
            );
      }

      // Auto-Backup nach Daten-Änderung
      ref.read(autoBackupTriggerProvider).fireDebounced(
            reason: 'Custom-Parameter geändert',
          );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saveError = 'Speichern fehlgeschlagen: ${fehlerText(e)}';
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _istBearbeiten
            ? 'Parameter bearbeiten'
            : 'Neuen Parameter hinzufügen',
      ),
      content: SizedBox(
        width: 450,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Rahmen und Ecken der Felder kommen aus dem Theme.
            TextField(
              controller: _nameCtrl,
              enabled: !_isSaving,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name *',
                hintText: 'z.B. "Krustenfaktor", "Bratdauer-Modus"',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _wertCtrl,
              enabled: !_isSaving,
              decoration: const InputDecoration(
                labelText: 'Wert',
                hintText: 'z.B. "230", "4:00", "automatisch"',
              ),
            ),
            if (_saveError != null) ...[
              const SizedBox(height: 12),
              HinweisBox(_saveError!, art: StatusArt.fehler),
            ],
            const SizedBox(height: 12),
            const HinweisBox(
              'Eigene Parameter landen beim Excel-Export im Block '
              '„ZUSÄTZLICHE PARAMETER" deiner Vorlage.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton.icon(
          onPressed: _isSaving ? null : _speichere,
          // Ohne feste Farbe: Der gesperrte Knopf ist hellgrau, ein weißer
          // Kreisel war darauf unsichtbar.
          icon: _isSaving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save, size: 18),
          label: Text(_isSaving ? 'Speichern …' : 'Speichern'),
        ),
      ],
    );
  }
}