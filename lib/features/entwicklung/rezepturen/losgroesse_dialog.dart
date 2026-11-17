import 'package:flutter/material.dart';

import '../../../core/utils/format.dart';
import '../entwicklung_format.dart';

/// Fragt, auf welche Losgröße die Rezeptur umgerechnet werden soll.
/// [summeKg] ist ihre Summe jetzt. Gibt die neue Losgröße in kg zurück —
/// null, wenn abgebrochen oder nichts zu ändern ist.
Future<double?> losgroesseErfragen(
  BuildContext context, {
  required double summeKg,
  double verlustProzent = 0,
}) =>
    showDialog<double>(
      context: context,
      builder: (_) => LosgroesseDialog(
        summeKg: summeKg,
        verlustProzent: verlustProzent,
      ),
    );

class LosgroesseDialog extends StatefulWidget {
  const LosgroesseDialog({
    super.key,
    required this.summeKg,
    this.verlustProzent = 0,
  });

  final double summeKg;

  /// Der Verlust des Stands in Prozent — damit steht dabei, was nach der
  /// Herstellung übrig bleibt.
  final double verlustProzent;

  @override
  State<LosgroesseDialog> createState() => _LosgroesseDialogState();
}

class _LosgroesseDialogState extends State<LosgroesseDialog> {
  late final _feld = TextEditingController(text: feldText(widget.summeKg));
  String? _fehler;

  @override
  void initState() {
    super.initState();
    // Alles markiert: Die neue Menge lässt sich gleich darübertippen.
    _feld.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _feld.text.length,
    );
  }

  @override
  void dispose() {
    _feld.dispose();
    super.dispose();
  }

  double? get _ziel {
    final v = zahlAus(_feld.text);
    return v == null || !v.isFinite || v <= 0 ? null : v;
  }

  void _fertig() {
    final ziel = _ziel;
    if (ziel == null) {
      setState(() => _fehler = 'Bitte eine Menge über 0 eingeben.');
      return;
    }
    Navigator.of(context).pop(ziel);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final ziel = _ziel;
    final faktor = ziel == null ? null : ziel / widget.summeKg;
    final verlust = widget.verlustProzent;

    return AlertDialog(
      title: const Text('Losgröße'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Auf wie viel Kilogramm soll die Rezeptur gerechnet werden? '
              'Jede Zeile wird im selben Verhältnis umgerechnet — die '
              'Anteile bleiben.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('losgroesse-feld'),
              controller: _feld,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Losgröße',
                suffixText: 'kg',
                errorText: _fehler,
              ),
              onChanged: (_) => setState(() => _fehler = null),
              onSubmitted: (_) => _fertig(),
            ),
            const SizedBox(height: 10),
            Text('Jetzt: ${mengeText(widget.summeKg)} kg', style: grau),
            if (faktor != null)
              Text(
                'Faktor: ${Format.zahl(faktor, nachkomma: 4)}'
                '${verlust > 0 && ziel != null ? ' · nach '
                    '${prozentText(verlust)} Verlust rund '
                    '${mengeText(ziel * (1 - verlust / 100))} kg' : ''}',
                style: grau,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          key: const ValueKey('losgroesse-umrechnen'),
          onPressed: _fertig,
          child: const Text('Umrechnen'),
        ),
      ],
    );
  }
}
