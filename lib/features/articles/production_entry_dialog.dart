import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';
import '../../core/services/produktion_erfassen_service.dart';
import '../../core/utils/sheet_utils.dart';
import '../../core/utils/zeit.dart';

/// Das EINE Formular, mit dem Produktionen erfasst werden — aus dem
/// Artikel heraus genauso wie aus der Produktionserfassung der Woche.
///
/// Ohne [existing] entsteht eine neue Zeile in `production_history`
/// (`quelle = 'app'`); mit [existing] wird die bestehende Zeile geändert
/// oder gelöscht. Verlust, Produktionszeit und kg/h rechnet
/// [ProduktionErfassenService] — identisch zur Excel-Vorlage und auch über
/// Mitternacht richtig.
///
/// Aus diesen Zeilen stammen Ausbeute und Leistung der Planung (Ø der
/// letzten zehn Produktionen).
class ProductionEntryDialog extends ConsumerStatefulWidget {
  const ProductionEntryDialog({
    super.key,
    required this.productId,
    this.existing,
    this.vorschlagRohKg,
    this.vorschlagDatum,
    this.vorschlagStart,
  });

  final String productId;
  final ProductionHistoryData? existing;

  /// Vorbelegung für eine neue Produktion, etwa aus dem Wochenplan.
  final double? vorschlagRohKg;
  final DateTime? vorschlagDatum;
  final String? vorschlagStart;

  /// Öffnet das Formular. Gibt `true` zurück, wenn gespeichert oder
  /// gelöscht wurde.
  static Future<bool> show(
    BuildContext context,
    String productId, {
    ProductionHistoryData? existing,
    double? vorschlagRohKg,
    DateTime? vorschlagDatum,
    String? vorschlagStart,
  }) async {
    final result = await showSheetOhneAnimation<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: ProductionEntryDialog(
          productId: productId,
          existing: existing,
          vorschlagRohKg: vorschlagRohKg,
          vorschlagDatum: vorschlagDatum,
          vorschlagStart: vorschlagStart,
        ),
      ),
    );
    return result ?? false;
  }

  @override
  ConsumerState<ProductionEntryDialog> createState() =>
      _ProductionEntryDialogState();
}

class _ProductionEntryDialogState
    extends ConsumerState<ProductionEntryDialog> {
  late DateTime _datum;
  final _rohController = TextEditingController();
  final _fertigController = TextEditingController();
  final _startController = TextEditingController();
  final _endController = TextEditingController();
  final _notizenController = TextEditingController();

  bool _saving = false;

  bool get _istBearbeitung => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _datum = DateTime(e.datum.year, e.datum.month, e.datum.day);
      _rohController.text = _kgText(e.kgRohware);
      _fertigController.text = _kgText(e.kgFertigware);
      _startController.text = e.startzeit ?? '';
      _endController.text = e.endzeit ?? '';
      _notizenController.text = e.notizen ?? '';
    } else {
      final d = widget.vorschlagDatum ?? DateTime.now();
      _datum = DateTime(d.year, d.month, d.day);
      final roh = widget.vorschlagRohKg;
      if (roh != null && roh > 0) _rohController.text = roh.round().toString();
      _startController.text = widget.vorschlagStart ?? '';
    }
  }

  @override
  void dispose() {
    _rohController.dispose();
    _fertigController.dispose();
    _startController.dispose();
    _endController.dispose();
    _notizenController.dispose();
    super.dispose();
  }

  // ── Parsing-Helfer ────────────────────────────────────────────────────

  static double? _num(String s) =>
      double.tryParse(s.trim().replaceAll(',', '.'));

  static String _kgText(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  }

  double? get _roh => _num(_rohController.text);
  double? get _fertig => _num(_fertigController.text);

  /// Live gerechnet — mit derselben Rechnung, mit der gespeichert wird.
  ProduktionsKennzahlen get _kennzahlen => ProduktionErfassenService.kennzahlen(
        kgRohware: _roh,
        kgFertigware: _fertig,
        startzeit: _startController.text,
        endzeit: _endController.text,
      );

  // ── Formatierung ──────────────────────────────────────────────────────

  static String _pad(int n) => n.toString().padLeft(2, '0');

  String get _datumLabel =>
      '${_pad(_datum.day)}.${_pad(_datum.month)}.${_datum.year}';

  static String _fmtKg(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  // ── Aktionen ──────────────────────────────────────────────────────────

  Future<void> _datumWaehlen() async {
    // Produktionen liegen in der Vergangenheit; morgen ist das Äußerste.
    // Ein bestehender Eintrag außerhalb dieser Spanne bleibt wählbar.
    final morgen = DateTime.now().add(const Duration(days: 1));
    final frueheste = DateTime(2020);
    final picked = await showDatePicker(
      context: context,
      initialDate: _datum,
      firstDate: _datum.isBefore(frueheste) ? _datum : frueheste,
      lastDate: _datum.isAfter(morgen) ? _datum : morgen,
    );
    if (picked != null) {
      setState(() => _datum = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _speichern() async {
    final roh = _roh;
    if (roh == null || roh <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte mindestens die Rohware-Menge (kg) eingeben.'),
        ),
      );
      return;
    }
    final fertig = _fertig;

    setState(() => _saving = true);
    try {
      await ProduktionErfassenService.speichere(
        db: ref.read(databaseProvider),
        productId: widget.productId,
        datum: _datum,
        kgRohware: roh,
        kgFertigware: (fertig != null && fertig > 0) ? fertig : null,
        startzeit: _startController.text,
        endzeit: _endController.text,
        notizen: _notizenController.text,
        vorhandeneId: widget.existing?.id,
      );

      ref
          .read(autoBackupTriggerProvider)
          .fireDebounced(reason: 'Produktion erfasst/bearbeitet');

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _loeschen() async {
    final bestaetigt = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Produktion löschen?'),
        content: const Text(
          'Diese historische Produktion wird entfernt. Beim nächsten '
          'Excel-Export ist sie nicht mehr enthalten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (bestaetigt != true) return;

    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      final jetzt = DateTime.now();
      await (db.update(db.productionHistory)
            ..where((t) => t.id.equals(widget.existing!.id)))
          .write(
        ProductionHistoryCompanion(
          deletedAt: Value(jetzt),
          updatedAt: Value(jetzt),
        ),
      );
      ref
          .read(autoBackupTriggerProvider)
          .fireDebounced(reason: 'Produktion gelöscht');
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
        setState(() => _saving = false);
      }
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final k = _kennzahlen;
    final fertig = _fertig;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colors.onSurface.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                _istBearbeitung
                    ? 'Produktion bearbeiten'
                    : 'Produktion erfassen',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Aus den erfassten Produktionen rechnet die Planung Ausbeute '
                'und Leistung (Ø der letzten zehn). Die Werte lassen sich in '
                'die Excel zurückschreiben.',
                style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 16),

              // Datum
              InkWell(
                onTap: _datumWaehlen,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Datum',
                    prefixIcon: Icon(Icons.event),
                  ),
                  child: Text(_datumLabel),
                ),
              ),
              const SizedBox(height: 14),

              // Roh + Fertig
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _rohController,
                      decoration: const InputDecoration(
                        labelText: 'Rohware (kg)',
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                      ],
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _fertigController,
                      decoration: const InputDecoration(
                        labelText: 'Fertigware (kg)',
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                      ],
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Start + Ende
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _startController,
                      decoration: const InputDecoration(
                        labelText: 'Startzeit',
                        hintText: '06:35',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _endController,
                      decoration: const InputDecoration(
                        labelText: 'Endzeit',
                        hintText: '09:15',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Notizen
              TextField(
                controller: _notizenController,
                decoration: const InputDecoration(
                  labelText: 'Notizen (optional)',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),

              // Live-Vorschau der berechneten Werte
              _Vorschau(kennzahlen: k),
              if (fertig == null || fertig <= 0) ...[
                const SizedBox(height: 8),
                Text(
                  'Ohne Fertigware zählt diese Produktion nicht für die '
                  'Ausbeute, ohne Start- und Endzeit nicht für die Leistung.',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _speichern,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: Text(
                    _saving
                        ? 'Speichern …'
                        : (_istBearbeitung
                            ? 'Änderungen speichern'
                            : 'Produktion speichern'),
                  ),
                ),
              ),

              if (_istBearbeitung) ...[
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    onPressed: _saving ? null : _loeschen,
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text(
                      'Produktion löschen',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Zeigt die live berechneten Kennzahlen (Verlust, Dauer, kg/h).
class _Vorschau extends StatelessWidget {
  const _Vorschau({required this.kennzahlen});

  final ProduktionsKennzahlen kennzahlen;

  @override
  Widget build(BuildContext context) {
    final k = kennzahlen;
    final eintraege = <({String label, String wert})>[
      if (k.verlustAnteil != null)
        (
          label: 'Verlust',
          wert: '${(k.verlustAnteil! * 100).toStringAsFixed(1)} %',
        ),
      if (k.produktionszeitMinuten != null)
        (label: 'Dauer', wert: Zeit.lang(k.produktionszeitMinuten)),
      if (k.kgProStundeRoh != null)
        (
          label: 'kg/h roh',
          wert: _ProductionEntryDialogState._fmtKg(k.kgProStundeRoh!),
        ),
      if (k.kgProStundeGegart != null)
        (
          label: 'kg/h gegart',
          wert: _ProductionEntryDialogState._fmtKg(k.kgProStundeGegart!),
        ),
    ];

    if (eintraege.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          'Verlust und kg/h erscheinen hier automatisch, sobald Roh-, '
          'Fertigmenge und Zeiten ausgefüllt sind.',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF2E7D32).withValues(alpha: 0.4),
        ),
      ),
      child: Wrap(
        spacing: 24,
        runSpacing: 10,
        children: [
          for (final e in eintraege)
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.wert,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2E7D32),
                  ),
                ),
                Text(
                  e.label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
