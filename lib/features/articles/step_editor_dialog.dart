import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';

/// Dialog zum Bearbeiten eines bestehenden oder Anlegen eines neuen
/// Produktions-Schritts.
///
/// Zwei Modi:
/// - **Edit-Modus**: [step] gesetzt → bestehende Werte vorbelegt, `UPDATE`.
/// - **Insert-Modus**: [step] = null, [productId] gesetzt → leere Felder
///   mit Defaults, `INSERT` mit nächster freier `reihenfolge`.
///
/// Editierbare Felder (Phase A):
/// - Abteilung (Dropdown aus Abteilung-Enum)
/// - Prozessschritt (Freitext)
/// - Anlage (Dropdown aus Anlagen-Katalog, gefiltert nach Abteilung)
/// - Personen (Zahl, Default 1)
/// - Menge kg (Zahl)
/// - Dauer Minuten (Zahl)
///
/// **Reihenfolge-Logik im Insert-Modus:**
/// Die neue `reihenfolge` ist `MAX(reihenfolge) + 1` über **alle** Schritte
/// des Produkts — *inklusive* Soft-deleted. So erbt ein neuer Schritt nicht
/// die Excel-Spalte (B..U) eines gelöschten Schritts; die Spaltenzuordnung
/// im Excel-Export bleibt stabil (Variante 2: gelöschte Spalten unangetastet).
///
/// **Spalten-Sperre des Artikelblatts:**
/// Die v3-Excel-Vorlage hat 10 Schritt-Spalten (B..U). Bei `MAX(reihenfolge)
/// >= 10` wird der Insert blockiert und eine Fehlermeldung im Dialog
/// angezeigt. Der aufrufende Screen sollte zusätzlich vor dem Öffnen des
/// Dialogs prüfen und mit einer Snackbar abweisen — der Check hier ist
/// das Sicherheitsnetz.
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
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StepEditorDialog(
        step: step,
        stepNumber: stepNumber,
        productId: productId,
        startMaschine: startMaschine,
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
  late TextEditingController _mengeCtrl;
  late TextEditingController _dauerMinCtrl;
  late TextEditingController _fixZeitCtrl;

  List<Machine> _alleMaschinen = [];
  bool _maschinenGeladen = false;
  bool _isSaving = false;
  String? _saveError;

  /// Maximalzahl Schritte = Spalten des Artikelblatts (B..U = 20).
  ///
  /// Zehn reichten nicht: Allein die Bratstraße durchläuft bei panierten
  /// Artikeln bis zu acht Anlagen (Verbufa, Panieranlage, Öl-/Wasserzugabe,
  /// Bratstraße, Heißluftofen, Schockfroster …), dazu kommen Zerlegung,
  /// Waage und Verpackung. Der Wert muss mit `_maxSchritte` im
  /// Excel-Export und der Spaltengrenze im Import übereinstimmen.
  static const int _maxSchritte = 20;

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
      _mengeCtrl = TextEditingController(
        text: step.basisMengeKg > 0 ? _formatZahl(step.basisMengeKg) : '',
      );
      _dauerMinCtrl = TextEditingController(
        text: step.basisDauerMinuten > 0
            ? _formatZahl(step.basisDauerMinuten)
            : '',
      );
      _fixZeitCtrl = TextEditingController(
        text: (step.fixZeitMinuten ?? 0) > 0
            ? _formatZahl(step.fixZeitMinuten!)
            : '',
      );
    } else {
      // Insert-Modus: leere Felder mit sinnvollen Defaults
      final start = widget.startMaschine;
      _abteilungDbValue = start?.abteilung ?? Abteilung.values.first.dbValue;
      _prozessschrittCtrl = TextEditingController();
      _maschineId = start?.id;
      _personenCtrl = TextEditingController(text: '1');
      _mengeCtrl = TextEditingController();
      _dauerMinCtrl = TextEditingController();
      _fixZeitCtrl = TextEditingController();
    }
    _ladeMaschinen();
  }

  @override
  void dispose() {
    _prozessschrittCtrl.dispose();
    _personenCtrl.dispose();
    _mengeCtrl.dispose();
    _dauerMinCtrl.dispose();
    _fixZeitCtrl.dispose();
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
    final passend =
        _alleMaschinen.where((m) => m.abteilung == _abteilungDbValue).toList();
    return passend.isEmpty ? _alleMaschinen : passend;
  }

  /// Anlagen-Name für das Legacy-Feld `step.maschine`. Wird parallel zur
  /// FK-Spalte `step.maschineId` gepflegt, weil der Excel-Export teilweise
  /// noch das Freitext-Feld liest.
  String? _ermittleMaschinenName() {
    if (_maschineId == null) return null;
    if (_alleMaschinen.isEmpty) return null;
    return _alleMaschinen
        .firstWhere(
          (m) => m.id == _maschineId,
          orElse: () => _alleMaschinen.first,
        )
        .name;
  }

  /// `MAX(reihenfolge)` über alle Schritte des Produkts —
  /// **inklusive** Soft-deleted, damit gelöschte Excel-Spalten nicht
  /// neu vergeben werden. Liefert 0 wenn das Produkt noch keine Schritte hat.
  Future<int> _ermittleMaxReihenfolge(AppDatabase db) async {
    final productId = widget.productId!;
    final maxExpr = db.productSteps.reihenfolge.max();
    final row = await (db.selectOnly(db.productSteps)
          ..addColumns([maxExpr])
          ..where(db.productSteps.productId.equals(productId)))
        .getSingleOrNull();
    return row?.read(maxExpr) ?? 0;
  }

  Future<void> _speichere() async {
    setState(() {
      _isSaving = true;
      _saveError = null;
    });

    final personen = int.tryParse(_personenCtrl.text.trim()) ?? 1;
    final menge = _parseZahl(_mengeCtrl.text) ?? 0.0;
    final dauer = _parseZahl(_dauerMinCtrl.text) ?? 0.0;
    final fixZeit = _parseZahl(_fixZeitCtrl.text) ?? 0.0;
    final prozess = _prozessschrittCtrl.text.trim();
    final maschineName = _ermittleMaschinenName();

    try {
      final db = ref.read(databaseProvider);

      if (_isInsertMode) {
        // Pre-Check: Spaltenlimit des Artikelblatts (B..U = 20).
        final currentMax = await _ermittleMaxReihenfolge(db);
        if (currentMax >= _maxSchritte) {
          if (mounted) {
            setState(() {
              _saveError =
                  'Maximale Anzahl Schritte ($_maxSchritte) erreicht. '
                  'Bitte zuerst einen Schritt löschen.';
              _isSaving = false;
            });
          }
          return; // kein Pop — Dialog bleibt offen mit Fehlermeldung
        }

        await _insert(
          db: db,
          neueReihenfolge: currentMax + 1,
          personen: personen,
          menge: menge,
          dauer: dauer,
          fixZeit: fixZeit,
          prozess: prozess,
          maschineName: maschineName,
        );
      } else {
        await _update(
          db: db,
          personen: personen,
          menge: menge,
          dauer: dauer,
          fixZeit: fixZeit,
          prozess: prozess,
          maschineName: maschineName,
        );
      }

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

  Future<void> _insert({
    required AppDatabase db,
    required int neueReihenfolge,
    required int personen,
    required double menge,
    required double dauer,
    required double fixZeit,
    required String prozess,
    required String? maschineName,
  }) async {
    final neueId = const Uuid().v4();

    await db.into(db.productSteps).insert(
          ProductStepsCompanion(
            id: Value(neueId),
            productId: Value(widget.productId!),
            reihenfolge: Value(neueReihenfolge),
            abteilung: Value(_abteilungDbValue),
            prozessschritt: Value(prozess.isEmpty ? null : prozess),
            maschineId: Value(_maschineId),
            // Legacy-Feld parallel pflegen — Excel-Export liest beide.
            maschine: Value(maschineName),
            mengeKg: Value(menge > 0 ? menge : null),
            basisMengeKg: Value(menge),
            basisDauerMinuten: Value(dauer),
            fixZeitMinuten: Value(fixZeit > 0 ? fixZeit : null),
            basisMitarbeiter: Value(personen),
            // basisAnzahlMessungen: Default 0 aus dem Schema
            // createdAt / updatedAt: Default currentDateAndTime aus Schema
          ),
        );

    ref
        .read(autoBackupTriggerProvider)
        .fireDebounced(reason: 'Schritt angelegt');
  }

  Future<void> _update({
    required AppDatabase db,
    required int personen,
    required double menge,
    required double dauer,
    required double fixZeit,
    required String prozess,
    required String? maschineName,
  }) async {
    await (db.update(db.productSteps)
          ..where((s) => s.id.equals(widget.step!.id)))
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
        fixZeitMinuten: Value(fixZeit > 0 ? fixZeit : null),
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

              // ── Hinweis: Leistungsdaten zentral je Abteilung ─────────
              // Personen, Menge und Dauer werden nicht mehr pro Schritt
              // gepflegt, sondern zentral über „Leistungsdaten" je
              // Abteilung — das verhindert widersprüchliche Zeitangaben.
              // Die geladenen Werte bleiben erhalten (die Controller
              // behalten sie); hier sind sie nur nicht editierbar.
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
                        'Menge, Zeit und Personen werden zentral über '
                        '„Leistungsdaten" je Abteilung gepflegt.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── Fixe Zeit / Durchlauf (mengenunabhängig) ──────────────
              TextField(
                controller: _fixZeitCtrl,
                enabled: !_isSaving,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Fixe Zeit / Durchlauf',
                  suffixText: 'min',
                  helperText: 'Mengenunabhängig — z.B. Tunnel-Durchlauf, '
                      'Schockfrost, Transport + Verpacken. Wird bei der '
                      'Bratstraße auf die Auflagezeit aufaddiert.',
                  helperMaxLines: 3,
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
