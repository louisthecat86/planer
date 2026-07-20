import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';
import '../../core/services/produktion_erfassen_service.dart';

class ProduktionErfassenSheet extends ConsumerStatefulWidget {
  const ProduktionErfassenSheet({
    super.key,
    required this.productId,
    required this.vorschlagMengeKg,
    required this.vorschlagDatum,
    this.vorschlagStart,
  });

  final String productId;
  final double vorschlagMengeKg;
  final DateTime vorschlagDatum;
  final String? vorschlagStart;

  @override
  ConsumerState<ProduktionErfassenSheet> createState() =>
      ProduktionErfassenSheetState();
}

class ProduktionErfassenSheetState
    extends ConsumerState<ProduktionErfassenSheet> {
  late final TextEditingController _roh;
  late final TextEditingController _fertig;
  late final TextEditingController _start;
  late final TextEditingController _ende;
  late final TextEditingController _notizen;
  late DateTime _datum;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Rohmenge als Vorschlag; Fertigmenge trägt der Nutzer nach dem Wiegen ein.
    _roh = TextEditingController(
      text: widget.vorschlagMengeKg.toStringAsFixed(0),
    );
    _fertig = TextEditingController();
    _start = TextEditingController(text: widget.vorschlagStart ?? '');
    _ende = TextEditingController();
    _notizen = TextEditingController();
    _datum = widget.vorschlagDatum;
  }

  @override
  void dispose() {
    _roh.dispose();
    _fertig.dispose();
    _start.dispose();
    _ende.dispose();
    _notizen.dispose();
    super.dispose();
  }

  double? get _rohKg => double.tryParse(_roh.text.replaceAll(',', '.'));
  double? get _fertigKg => double.tryParse(_fertig.text.replaceAll(',', '.'));

  Future<void> _speichern() async {
    final roh = _rohKg;
    final fertig = _fertigKg;
    if (roh == null || roh <= 0 || fertig == null || fertig <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte Roh- und Fertigmenge (kg) eingeben.'),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    final db = ref.read(databaseProvider);
    await ProduktionErfassenService.erfasse(
      db: db,
      productId: widget.productId,
      datum: _datum,
      kgRohware: roh,
      kgFertigware: fertig,
      startzeit: _start.text.trim().isEmpty ? null : _start.text.trim(),
      endzeit: _ende.text.trim().isEmpty ? null : _ende.text.trim(),
      notizen: _notizen.text.trim().isEmpty ? null : _notizen.text.trim(),
    );
    ref
        .read(autoBackupTriggerProvider)
        .fireDebounced(reason: 'Produktion erfasst');
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Live-Kennzahlen
    final roh = _rohKg;
    final fertig = _fertigKg;
    final dauerMin = ProduktionErfassenService.produktionszeitMinuten(
      _start.text.trim(),
      _ende.text.trim(),
    );
    final verlust = (roh != null && roh > 0 && fertig != null)
        ? (1 - fertig / roh)
        : null;
    final std = (dauerMin != null && dauerMin > 0) ? dauerMin / 60 : null;
    final kghRoh = (roh != null && std != null) ? roh / std : null;
    final kghGegart = (fertig != null && std != null) ? fertig / std : null;

    String fmt(double? v, {int dez = 0, String einheit = ''}) =>
        v == null ? '—' : '${v.toStringAsFixed(dez)}$einheit';
    String fmtDauer(double? m) {
      if (m == null) return '—';
      final h = m ~/ 60;
      final r = (m % 60).round();
      return h > 0 ? '$h:${r.toString().padLeft(2, '0')} h' : '$r min';
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(
            'Produktion abschließen',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Die Werte werden in die Historie geschrieben und verbessern '
            'künftige Zeitschätzungen.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),

          // Datum
          OutlinedButton.icon(
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _datum,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 1)),
              );
              if (d != null) setState(() => _datum = d);
            },
            icon: const Icon(Icons.event, size: 18),
            label: Text(
              '${_datum.day.toString().padLeft(2, '0')}.'
              '${_datum.month.toString().padLeft(2, '0')}.${_datum.year}',
            ),
          ),
          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _roh,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Rohware',
                    suffixText: 'kg',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _fertig,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Fertigware',
                    suffixText: 'kg',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _start,
                  decoration: const InputDecoration(
                    labelText: 'Startzeit (HH:MM)',
                    hintText: '08:30',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _ende,
                  decoration: const InputDecoration(
                    labelText: 'Endzeit (HH:MM)',
                    hintText: '12:15',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Live berechnete Kennzahlen
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                _ErfassenKennzahlZeile(
                  label: 'Produktionszeit',
                  wert: fmtDauer(dauerMin),
                ),
                _ErfassenKennzahlZeile(
                  label: 'Verlust',
                  wert: verlust == null
                      ? '—'
                      : '${(verlust * 100).toStringAsFixed(1)} %',
                ),
                _ErfassenKennzahlZeile(
                  label: 'kg/h roh',
                  wert: fmt(kghRoh, einheit: ' kg/h'),
                ),
                _ErfassenKennzahlZeile(
                  label: 'kg/h gegart',
                  wert: fmt(kghGegart, einheit: ' kg/h'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          TextField(
            controller: _notizen,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Notizen (optional)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _busy ? null : _speichern,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(_busy ? 'Speichern …' : 'In Historie speichern'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErfassenKennzahlZeile extends StatelessWidget {
  const _ErfassenKennzahlZeile({required this.label, required this.wert});

  final String label;
  final String wert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            wert,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
