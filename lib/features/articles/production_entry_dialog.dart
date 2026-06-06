import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';

/// Bottom-Sheet zum Erfassen **oder Bearbeiten** einer Produktion.
///
/// Ohne [existing] wird eine neue Zeile in `production_history` angelegt
/// (`quelle = 'app'`); mit [existing] wird die bestehende Zeile aktualisiert
/// oder gelöscht. Garverlust-Anteil, Produktionszeit und kg/h werden aus
/// Rohware, Fertigware und Start-/Endzeit berechnet — identisch zur
/// Excel-Vorlage (Verlust = 1 − Fertig/Roh, kg/h roh = Roh ÷ Stunden).
class ProductionEntryDialog extends ConsumerStatefulWidget {
  const ProductionEntryDialog({
    super.key,
    required this.productId,
    this.existing,
  });

  final String productId;
  final ProductionHistoryData? existing;

  /// Öffnet den Dialog. Gibt `true` zurück, wenn gespeichert/gelöscht wurde.
  static Future<bool> show(
    BuildContext context,
    String productId, {
    ProductionHistoryData? existing,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: ProductionEntryDialog(
          productId: productId,
          existing: existing,
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
  final _uuid = const Uuid();

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
      final now = DateTime.now();
      _datum = DateTime(now.year, now.month, now.day);
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

  /// "HH:MM" → Minuten seit Mitternacht.
  static int? _minuten(String s) {
    final parts = s.trim().split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  static String _kgText(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  }

  // ── Berechnete Werte (live) ───────────────────────────────────────────

  double? get _roh => _num(_rohController.text);
  double? get _fertig => _num(_fertigController.text);

  double? get _verlustAnteil {
    final r = _roh;
    final f = _fertig;
    if (r == null || r <= 0 || f == null) return null;
    return 1 - (f / r);
  }

  double? get _produktionszeitMinuten {
    final s = _minuten(_startController.text);
    final e = _minuten(_endController.text);
    if (s == null || e == null || e <= s) return null;
    return (e - s).toDouble();
  }

  double? get _kgProStundeRoh {
    final r = _roh;
    final t = _produktionszeitMinuten;
    if (r == null || t == null || t <= 0) return null;
    return r / (t / 60);
  }

  double? get _kgProStundeGegart {
    final f = _fertig;
    final t = _produktionszeitMinuten;
    if (f == null || t == null || t <= 0) return null;
    return f / (t / 60);
  }

  // ── Formatierung ──────────────────────────────────────────────────────

  static String _pad(int n) => n.toString().padLeft(2, '0');

  String get _datumLabel =>
      '${_pad(_datum.day)}.${_pad(_datum.month)}.${_datum.year}';

  static String _fmtKg(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  static String _fmtDauer(double minuten) {
    final h = (minuten / 60).floor();
    final m = (minuten % 60).round();
    if (h == 0) return '$m min';
    if (m == 0) return '$h h';
    return '$h h $m min';
  }

  // ── Aktionen ──────────────────────────────────────────────────────────

  Future<void> _datumWaehlen() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _datum,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
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

    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      final start = _startController.text.trim();
      final end = _endController.text.trim();
      final notizen = _notizenController.text.trim();
      final jetzt = DateTime.now();

      if (_istBearbeitung) {
        await (db.update(db.productionHistory)
              ..where((t) => t.id.equals(widget.existing!.id)))
            .write(
          ProductionHistoryCompanion(
            datum: Value(_datum),
            kgRohware: Value(roh),
            kgFertigware: Value(_fertig),
            verlustAnteil: Value(_verlustAnteil),
            startzeit: Value(start.isEmpty ? null : start),
            endzeit: Value(end.isEmpty ? null : end),
            produktionszeitMinuten: Value(_produktionszeitMinuten),
            kgProStundeRoh: Value(_kgProStundeRoh),
            kgProStundeGegart: Value(_kgProStundeGegart),
            notizen: Value(notizen.isEmpty ? null : notizen),
            updatedAt: Value(jetzt),
          ),
        );
      } else {
        await db.into(db.productionHistory).insert(
              ProductionHistoryCompanion(
                id: Value(_uuid.v4()),
                productId: Value(widget.productId),
                datum: Value(_datum),
                kgRohware: Value(roh),
                kgFertigware: Value(_fertig),
                verlustAnteil: Value(_verlustAnteil),
                startzeit: Value(start.isEmpty ? null : start),
                endzeit: Value(end.isEmpty ? null : end),
                produktionszeitMinuten: Value(_produktionszeitMinuten),
                kgProStundeRoh: Value(_kgProStundeRoh),
                kgProStundeGegart: Value(_kgProStundeGegart),
                notizen: Value(notizen.isEmpty ? null : notizen),
                quelle: const Value('app'),
              ),
            );
      }

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
                    color: Colors.grey.shade300,
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
                'Die Werte landen in der Historie dieses Artikels und '
                'können in die Excel zurückgeschrieben werden.',
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
                    border: OutlineInputBorder(),
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
                        border: OutlineInputBorder(),
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
                        border: OutlineInputBorder(),
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

              // Start + End
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _startController,
                      decoration: const InputDecoration(
                        labelText: 'Startzeit',
                        hintText: '06:35',
                        border: OutlineInputBorder(),
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
                        border: OutlineInputBorder(),
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
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),

              // Live-Vorschau der berechneten Werte
              _Vorschau(
                verlustAnteil: _verlustAnteil,
                produktionszeitMinuten: _produktionszeitMinuten,
                kgProStundeRoh: _kgProStundeRoh,
              ),
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

/// Zeigt die live berechneten Kennzahlen (Garverlust, Dauer, kg/h).
class _Vorschau extends StatelessWidget {
  const _Vorschau({
    required this.verlustAnteil,
    required this.produktionszeitMinuten,
    required this.kgProStundeRoh,
  });

  final double? verlustAnteil;
  final double? produktionszeitMinuten;
  final double? kgProStundeRoh;

  @override
  Widget build(BuildContext context) {
    final eintraege = <({String label, String wert})>[];
    if (verlustAnteil != null) {
      eintraege.add((
        label: 'Garverlust',
        wert: '${(verlustAnteil! * 100).toStringAsFixed(1)} %',
      ),);
    }
    if (produktionszeitMinuten != null) {
      eintraege.add((
        label: 'Dauer',
        wert: _ProductionEntryDialogState._fmtDauer(produktionszeitMinuten!),
      ),);
    }
    if (kgProStundeRoh != null) {
      eintraege.add((
        label: 'kg/h roh',
        wert: _ProductionEntryDialogState._fmtKg(kgProStundeRoh!),
      ),);
    }

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
          'Garverlust und kg/h erscheinen hier automatisch, sobald Roh-, '
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