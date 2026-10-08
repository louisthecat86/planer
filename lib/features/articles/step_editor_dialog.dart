import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';
import '../../core/services/prozesskette_service.dart';

/// Dialog zum Bearbeiten eines bestehenden oder Anlegen eines neuen
/// Produktions-Schritts.
///
/// Zwei Modi:
/// - **Edit-Modus**: [step] gesetzt → bestehende Werte vorbelegt, `UPDATE`.
/// - **Insert-Modus**: [step] = null, [productId] gesetzt → leere Felder
///   mit Defaults; der [ProzesskettenService] fügt den Schritt ein.
///
/// Editierbare Felder (Phase A):
/// - Abteilung (Dropdown aus Abteilung-Enum)
/// - Prozessschritt (Freitext)
/// - Anlage (Dropdown aus dem Anlagen-Katalog: zuerst die der Abteilung,
///   darunter die der anderen — eine Anlage darf bei einem Artikel auch für
///   eine fremde Abteilung arbeiten)
/// - Personen an diesem Schritt (Zahl, Default 1 beim Anlegen)
///
/// Zeiten gibt es am Schritt keine: Menge und Zeit sind Leistungsdaten der
/// Abteilung und werden dort gepflegt. Wechselt ein Schritt die Abteilung,
/// bleiben deren Leistungsdaten zurück (siehe [ProzesskettenService]).
///
/// **Position im Insert-Modus:** an [einfuegenAn], ohne Angabe ans Ende der
/// Abteilung — gibt es sie im Prozess noch nicht, ans Ende der Kette. Der
/// Service nummeriert danach alle Schritte lückenlos (Excel-Spalten B..U)
/// und lässt höchstens 20 aktive Schritte zu; darüber bleibt der Dialog mit
/// einer Fehlermeldung offen.
///
/// **Anlagen-Doppelpflege:**
/// Sowohl die FK-Spalte `maschineId` als auch das Legacy-Freitextfeld
/// `maschine` werden geschrieben. Der Excel-Export greift teilweise noch
/// auf das Freitextfeld zu.
///
/// Nicht in Phase A: Parameter-Gruppen-Editor. Custom-Parameter laufen
/// separat über den `CustomParameterEditorDialog`.
class StepEditorDialog extends ConsumerStatefulWidget {
  const StepEditorDialog({
    super.key,
    this.step,
    this.stepNumber,
    this.productId,
    this.startMaschine,
    this.startAbteilung,
    this.einfuegenAn,
  }) : assert(
          step != null || productId != null,
          'Entweder step (Edit-Modus) oder productId (Insert-Modus) muss '
          'gesetzt sein.',
        );

  /// Der zu bearbeitende Schritt. NULL → Insert-Modus.
  final ProductStep? step;

  /// Anzeige-Nummer im Dialogtitel. Optional.
  /// - Edit-Modus: aktuelle Listen-Position des Schritts.
  /// - Insert-Modus: geplante Listen-Position des neuen Schritts
  ///   (typischerweise `sichtbareSchritte.length + 1`).
  final int? stepNumber;

  /// Produkt-ID, für die ein neuer Schritt angelegt wird.
  /// Im Edit-Modus ignoriert (kommt aus [step]).
  final String? productId;

  /// Optional im Insert-Modus: vorausgewählte Maschine (z. B. aus der
  /// Produktionsmittel-Sidebar). Belegt Abteilung + Maschine vor.
  final Machine? startMaschine;

  /// Optional im Insert-Modus: Abteilung des neuen Schritts (dbValue) —
  /// etwa die Station, an deren „+ Anlage" getippt wurde. Geht vor der
  /// Stammabteilung von [startMaschine].
  final String? startAbteilung;

  /// Optional im Insert-Modus: Position in der Kette (0 = ganz vorn). Ohne
  /// Angabe kommt der Schritt ans Ende seiner Abteilung.
  final int? einfuegenAn;

  bool get _isInsertMode => step == null;

  /// Öffnet den Dialog. Liefert `true` wenn gespeichert/angelegt wurde,
  /// `false` wenn abgebrochen.
  ///
  /// Edit-Modus:
  /// ```dart
  /// StepEditorDialog.show(context, step: existing, stepNumber: 3);
  /// ```
  ///
  /// Insert-Modus:
  /// ```dart
  /// StepEditorDialog.show(
  ///   context,
  ///   productId: productId,
  ///   stepNumber: visibleSteps.length + 1,
  /// );
  /// ```
  static Future<bool> show(
    BuildContext context, {
    ProductStep? step,
    int? stepNumber,
    String? productId,
    Machine? startMaschine,
    String? startAbteilung,
    int? einfuegenAn,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StepEditorDialog(
        step: step,
        stepNumber: stepNumber,
        productId: productId,
        startMaschine: startMaschine,
        startAbteilung: startAbteilung,
        einfuegenAn: einfuegenAn,
      ),
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

  List<Machine> _alleMaschinen = [];
  bool _maschinenGeladen = false;
  bool _isSaving = false;
  String? _saveError;

  bool get _isInsertMode => widget._isInsertMode;

  @override
  void initState() {
    super.initState();
    if (widget.step != null) {
      // Edit-Modus: Werte aus dem bestehenden Schritt vorbelegen
      final step = widget.step!;
      _abteilungDbValue = step.abteilung;
      _prozessschrittCtrl =
          TextEditingController(text: step.prozessschritt ?? '');
      _maschineId = step.maschineId;
      _personenCtrl =
          TextEditingController(text: step.basisMitarbeiter.toString());
    } else {
      // Insert-Modus: leere Felder mit sinnvollen Defaults
      final start = widget.startMaschine;
      _abteilungDbValue = widget.startAbteilung ??
          start?.abteilung ??
          Abteilung.values.first.dbValue;
      _prozessschrittCtrl = TextEditingController();
      _maschineId = start?.id;
      _personenCtrl = TextEditingController(text: '1');
    }
    _ladeMaschinen();
  }

  @override
  void dispose() {
    _prozessschrittCtrl.dispose();
    _personenCtrl.dispose();
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

  /// Einträge der Anlagen-Auswahl: zuerst die Anlagen der gewählten
  /// Abteilung, darunter die der anderen — mit ihrer Abteilung dahinter.
  List<DropdownMenuItem<String?>> _anlagenEintraege(ThemeData theme) {
    Abteilung? abteilungVon(String dbValue) {
      for (final a in Abteilung.values) {
        if (a.dbValue == dbValue) return a;
      }
      return null;
    }

    String abteilungsName(String dbValue) =>
        abteilungVon(dbValue)?.anzeigeName ?? dbValue;

    final eigene = _alleMaschinen
        .where((m) => m.abteilung == _abteilungDbValue)
        .toList();
    final fremde = _alleMaschinen
        .where((m) => m.abteilung != _abteilungDbValue)
        .toList()
      ..sort((a, b) {
        final ia = abteilungVon(a.abteilung)?.index ?? 99;
        final ib = abteilungVon(b.abteilung)?.index ?? 99;
        return ia != ib ? ia.compareTo(ib) : a.name.compareTo(b.name);
      });
    final gedaempft = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    final gewaehlt = _maschineId;

    return [
      const DropdownMenuItem<String?>(
        value: null,
        child: Text(
          '— keine Anlage —',
          style: TextStyle(fontStyle: FontStyle.italic),
        ),
      ),
      for (final m in eigene)
        DropdownMenuItem<String?>(value: m.id, child: Text(m.name)),
      if (fremde.isNotEmpty)
        // Zwischenüberschrift — nicht wählbar.
        DropdownMenuItem<String?>(
          value: _kUeberschriftFremde,
          enabled: false,
          child: Text(
            'Aus anderen Abteilungen',
            style: gedaempft.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      for (final m in fremde)
        DropdownMenuItem<String?>(
          value: m.id,
          child: Text.rich(
            TextSpan(
              text: m.name,
              children: [
                TextSpan(
                  text: ' · ${abteilungsName(m.abteilung)}',
                  style: gedaempft,
                ),
              ],
            ),
          ),
        ),
      // Die Anlage des Schritts gibt es im Katalog nicht mehr: trotzdem
      // anzeigen, statt die Auswahl ins Leere zeigen zu lassen.
      if (gewaehlt != null && !_alleMaschinen.any((m) => m.id == gewaehlt))
        DropdownMenuItem<String?>(
          value: gewaehlt,
          child: Text(
            '${_ermittleMaschinenName() ?? 'Anlage'} (nicht mehr im Katalog)',
            style: gedaempft,
          ),
        ),
    ];
  }

  /// Wert der Zwischenüberschrift in der Anlagen-Auswahl — keine Anlage
  /// hat diese ID.
  static const String _kUeberschriftFremde = '__andere_abteilungen__';

  /// Anlagen-Name für das Legacy-Feld `step.maschine`. Wird parallel zur
  /// FK-Spalte `step.maschineId` gepflegt, weil der Excel-Export teilweise
  /// noch das Freitext-Feld liest.
  String? _ermittleMaschinenName() {
    final id = _maschineId;
    if (id == null) return null;
    final m = _alleMaschinen.where((m) => m.id == id).firstOrNull;
    if (m != null) return m.name;
    // Nicht mehr im Katalog: den bisherigen Namen behalten.
    return widget.step?.maschineId == id ? widget.step?.maschine : null;
  }

  Future<void> _speichere() async {
    setState(() {
      _isSaving = true;
      _saveError = null;
    });

    // Leeres Feld = 0 Personen. Früher stand hier 1 als Fallback — das
    // stammt aus der Zeit, als der Wert die ganze Abteilung meinte.
    final personen = int.tryParse(_personenCtrl.text.trim()) ?? 0;
    final prozess = _prozessschrittCtrl.text.trim();
    final maschineName = _ermittleMaschinenName();

    try {
      final db = ref.read(databaseProvider);

      if (_isInsertMode) {
        // Fügt ein und nummeriert die Kette lückenlos. Hat der Artikel schon
        // 20 Schritte (Spalten B..U der Vorlage), kommt ein StateError.
        await ProzesskettenService.fuegeEin(
          db,
          productId: widget.productId!,
          abteilung: _abteilungDbValue,
          index: widget.einfuegenAn,
          maschineId: _maschineId,
          maschine: maschineName,
          prozessschritt: prozess.isEmpty ? null : prozess,
          personen: personen,
        );
        ref
            .read(autoBackupTriggerProvider)
            .fireDebounced(reason: 'Schritt angelegt');
      } else {
        await _update(
          db: db,
          personen: personen,
          prozess: prozess,
          maschineName: maschineName,
        );
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on StateError catch (e) {
      // Kette voll — der Dialog bleibt mit dem Hinweis offen.
      if (mounted) {
        setState(() {
          _saveError = e.message;
          _isSaving = false;
        });
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

  Future<void> _update({
    required AppDatabase db,
    required int personen,
    required String prozess,
    required String? maschineName,
  }) async {
    final step = widget.step!;
    // Abteilung über den Service wechseln: Die Leistungsdaten der alten
    // Abteilung bleiben dort, statt mit dem Schritt mitzuwandern.
    if (_abteilungDbValue != step.abteilung) {
      await ProzesskettenService.wechsleAbteilung(
        db,
        step.id,
        _abteilungDbValue,
      );
    }
    await (db.update(db.productSteps)..where((s) => s.id.equals(step.id)))
        .write(
      ProductStepsCompanion(
        prozessschritt: Value(prozess.isEmpty ? null : prozess),
        maschineId: Value(_maschineId),
        maschine: Value(maschineName), // Legacy-Feld spiegeln
        basisMitarbeiter: Value(personen),
        updatedAt: Value(DateTime.now()),
      ),
    );

    ref
        .read(autoBackupTriggerProvider)
        .fireDebounced(reason: 'Schritt bearbeitet');
  }

  String get _titel {
    if (_isInsertMode) {
      return widget.stepNumber != null
          ? 'Schritt ${widget.stepNumber} anlegen'
          : 'Neuen Schritt anlegen';
    }
    return 'Schritt ${widget.stepNumber} bearbeiten';
  }

  String get _saveLabel {
    if (_isSaving) return _isInsertMode ? 'Anlegen …' : 'Speichern …';
    return _isInsertMode ? 'Anlegen' : 'Speichern';
  }

  IconData get _saveIcon => _isInsertMode ? Icons.add : Icons.save;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_titel),
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
                // Die Anlage bleibt: Sie darf bei diesem Artikel auch für
                // eine andere Abteilung als ihre eigene arbeiten.
                onChanged: _isSaving
                    ? null
                    : (v) {
                        if (v != null) setState(() => _abteilungDbValue = v);
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
                  ),
                  items: _anlagenEintraege(Theme.of(context)),
                  onChanged: _isSaving
                      ? null
                      : (v) => setState(() => _maschineId = v),
                ),
              const SizedBox(height: 16),

              // ── Personen an diesem Schritt ───────────────────────────
              // Personen hängen am einzelnen Schritt, nicht an der
              // Abteilung: Dieselbe Anlage kann bei Artikel A mit zwei
              // und bei Artikel B mit drei Personen besetzt sein. Die
              // Abteilung braucht die SUMME über ihre Schritte — so
              // rechnet der Whiteboard-Provider, und so zeigt es der
              // Leistungsdaten-Dialog an.
              TextField(
                controller: _personenCtrl,
                enabled: !_isSaving,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Personen an diesem Schritt',
                  suffixText: 'Pers.',
                  helperText: 'Gilt nur für diesen Artikel. Leer oder 0 '
                      'bedeutet: hier steht niemand dediziert.',
                  helperMaxLines: 3,
                ),
              ),

              const SizedBox(height: 12),

              // ── Hinweis: Zeiten gehören der Abteilung ────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Zeiten gibt es an der Anlage keine: Die Dauer kommt '
                        'aus den Leistungsdaten der Abteilung oder aus den '
                        'erfassten Produktionen.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
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
          onPressed:
              _isSaving ? null : () => Navigator.of(context).pop(false),
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
              : Icon(_saveIcon),
          label: Text(_saveLabel),
        ),
      ],
    );
  }
}


