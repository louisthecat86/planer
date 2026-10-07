import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';
import '../../core/utils/datum.dart';
import '../../core/utils/sheet_utils.dart';
import '../../core/utils/zeit.dart';
import '../datenblatt/datenblatt.dart';
import 'whiteboard_provider.dart';

/// Öffnet einen Bottom-Sheet-Dialog mit allen Details zum Task.
///
/// Gibt `true` zurück, wenn der Task geändert wurde (→ Board refreshen).
Future<bool> showTaskDetailSheet(
  BuildContext context,
  WidgetRef ref,
  WhiteboardTask wbTask,
) async {
  final result = await showSheetOhneAnimation<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => UncontrolledProviderScope(
      container: ProviderScope.containerOf(context),
      child: _TaskDetailSheet(wbTask: wbTask),
    ),
  );
  return result ?? false;
}

// ---------------------------------------------------------------------------
// Sheet-Inhalt
// ---------------------------------------------------------------------------

class _TaskDetailSheet extends ConsumerStatefulWidget {
  const _TaskDetailSheet({required this.wbTask});

  final WhiteboardTask wbTask;

  @override
  ConsumerState<_TaskDetailSheet> createState() => _TaskDetailSheetState();
}

class _TaskDetailSheetState extends ConsumerState<_TaskDetailSheet> {
  late final TextEditingController _mengeController;
  late final TextEditingController _dauerController;
  late final TextEditingController _mitarbeiterController;
  late final TextEditingController _startZeitController;
  late final TextEditingController _notizenController;

  /// Woraus sich die Dauer dieser Abteilung für jede Menge rechnet — nach
  /// denselben Regeln wie beim Einplanen. null, solange es lädt oder wenn
  /// der Artikel keinen Schritt in dieser Abteilung hat.
  AbteilungsDauerModell? _modell;

  /// „Hochrechnen nicht möglich" kommt einmal, nicht bei jedem Tastendruck.
  bool _hochrechnenHinweisGezeigt = false;

  bool _isDirty = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final t = widget.wbTask.task;
    _mengeController =
        TextEditingController(text: t.mengeKg.toStringAsFixed(1));
    _dauerController =
        TextEditingController(text: t.geplanteDauerMinuten.toStringAsFixed(0));
    _mitarbeiterController =
        TextEditingController(text: t.geplanteMitarbeiter.toString());
    _startZeitController = TextEditingController(text: t.startZeit ?? '');
    _notizenController = TextEditingController(text: t.notizen ?? '');

    _ladeModell();
  }

  Future<void> _ladeModell() async {
    final db = ref.read(databaseProvider);
    final task = widget.wbTask.task;
    final modell = await ladeAbteilungsDauerModell(
      db,
      productId: task.productId,
      abteilung: task.abteilung,
      maschineId: task.maschineId,
    );
    if (modell == null || !mounted) return;
    setState(() => _modell = modell);
    // Wurde die Menge schon geändert, während das Modell noch lud, jetzt
    // nachrechnen — sonst gälte für die neue Menge die alte Dauer.
    if (_isDirty) _recalcDuration(_aktuelleMenge);
  }

  /// Die Menge im Feld, solange sie gültig ist — sonst die des Auftrags.
  double get _aktuelleMenge {
    final v = double.tryParse(_mengeController.text.replaceAll(',', '.'));
    return (v != null && v.isFinite && v > 0)
        ? v
        : widget.wbTask.task.mengeKg;
  }

  /// Menge geändert: speicherbar machen und die Dauer hochrechnen.
  void _mengeGeaendert() {
    final v = double.tryParse(_mengeController.text.replaceAll(',', '.'));
    if (v == null || !v.isFinite || v <= 0) return;
    // Auch wenn sich die Dauer nicht hochrechnen lässt, muss die neue
    // Menge speicherbar sein — vorher blieb „Speichern" dann gesperrt.
    setState(() => _isDirty = true);
    _recalcDuration(v);
  }

  /// Rechnet die Dauer aus der neuen Menge hoch — nach denselben Regeln
  /// wie beim Einplanen: mit den Leistungsdaten der Abteilung, ohne sie
  /// mit dem Ø der letzten Produktionen (in der Bratstraße immer mit
  /// diesem). Ohne beides bleibt die Dauer, wie sie ist.
  void _recalcDuration(double neueMenge) {
    final modell = _modell;
    if (modell == null) return;

    final dauer = modell.dauerFuer(neueMenge);
    if (dauer.quelle == DauerQuelle.platzhalter) {
      if (!_hochrechnenHinweisGezeigt) {
        _hochrechnenHinweisGezeigt = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Hochrechnen nicht möglich: Für diese Abteilung sind keine '
              'Leistungsdaten gepflegt, und es ist keine Produktion mit Zeit '
              'erfasst.',
            ),
          ),
        );
      }
      return;
    }
    if (!dauer.minuten.isFinite) return;

    _dauerController.text = dauer.minuten.roundToDouble().toStringAsFixed(0);
  }

  /// Dialog: Auftrag auf 2–5 aufeinanderfolgende Tage verteilen.
  ///
  /// Die Gesamtmenge wird gleichmäßig aufgeteilt; die Dauer je Tag wird —
  /// mit Leistungsdaten oder erfassten Produktionen — pro Teilmenge
  /// hochgerechnet (fixe Zeit fällt dann an jedem Tag an), sonst schlicht
  /// geteilt.
  Future<void> _verteileAufTageDialog() async {
    final task = widget.wbTask.task;
    final gesamtMenge = double.tryParse(
          _mengeController.text.replaceAll(',', '.'),
        ) ??
        task.mengeKg;
    final gesamtDauer =
        double.tryParse(_dauerController.text) ?? task.geplanteDauerMinuten;

    double dauerJeTag(int tage) {
      final teilMenge = gesamtMenge / tage;
      final modell = _modell;
      if (modell != null) {
        final d = modell.dauerFuer(teilMenge);
        if (d.quelle != DauerQuelle.platzhalter &&
            d.minuten.isFinite &&
            d.minuten > 0) {
          return d.minuten.roundToDouble();
        }
      }
      return gesamtDauer / tage;
    }

    String fmtTag(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.';

    final tage = await showDialog<int>(
      context: context,
      builder: (ctx) {
        var auswahl = 2;
        return StatefulBuilder(
          builder: (ctx, setState) {
            final teilMenge = gesamtMenge / auswahl;
            final dauer = dauerJeTag(auswahl);
            final tagesliste = List.generate(
              auswahl,
              (i) => fmtTag(tagPlus(task.datum, i)),
            ).join(' · ');
            return AlertDialog(
              title: const Text('Auf mehrere Tage verteilen'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Der Auftrag wird in gleich große Teil-Aufträge an '
                    'aufeinanderfolgenden Tagen aufgeteilt.',
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 2, label: Text('2 Tage')),
                      ButtonSegment(value: 3, label: Text('3 Tage')),
                      ButtonSegment(value: 4, label: Text('4 Tage')),
                      ButtonSegment(value: 5, label: Text('5 Tage')),
                    ],
                    selected: {auswahl},
                    onSelectionChanged: (s) =>
                        setState(() => auswahl = s.first),
                    showSelectedIcon: false,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Je Tag: ${teilMenge.toStringAsFixed(0)} kg · '
                    '${dauer.toStringAsFixed(0)} min\n'
                    'Tage: $tagesliste',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(auswahl),
                  child: const Text('Verteilen'),
                ),
              ],
            );
          },
        );
      },
    );

    if (tage == null || tage < 2) return;
    await _verteileAufTage(tage, gesamtMenge, dauerJeTag(tage));
  }

  Future<void> _verteileAufTage(
    int tage,
    double gesamtMenge,
    double dauerJeTag,
  ) async {
    setState(() => _isSaving = true);
    try {
      final db = ref.read(databaseProvider);
      final task = widget.wbTask.task;
      final teilMenge = gesamtMenge / tage;
      final jetzt = DateTime.now();
      const uuid = Uuid();

      // Die Teile gehören zur selben Kette wie das Original. Ist das
      // Original selbst eine Wurzel (parentTaskId == null), wird es zur
      // Wurzel seiner Teile — sonst hängen sie am selben Vorgänger.
      // Ohne das bekäme jedes Teilstück eine eigene kettenId: andere
      // Akzentfarbe auf dem Board, keine Kettenmarker, kein erkennbarer
      // Zusammenhang mehr zwischen den Tagen.
      final kettenAnker = task.parentTaskId ?? task.id;

      // Alles in EINER Transaktion: Zuerst wird das Original auf die
      // Teilmenge reduziert, dann entstehen die Folgetage. Bräche es
      // dazwischen ab, stünde nur noch ein Bruchteil der Menge im Plan —
      // der Rest wäre ersatzlos verschwunden, ohne jede Meldung.
      await db.transaction(() async {
        // Tag 1: bestehenden Auftrag auf Teilmenge reduzieren
        await (db.update(db.productionTasks)
              ..where((t) => t.id.equals(task.id)))
            .write(
          ProductionTasksCompanion(
            mengeKg: Value(teilMenge),
            geplanteDauerMinuten: Value(dauerJeTag),
            updatedAt: Value(jetzt),
          ),
        );

        // Tag 2..n: neue Teil-Aufträge an den Folgetagen
        for (var i = 1; i < tage; i++) {
          await db.into(db.productionTasks).insert(
                ProductionTasksCompanion(
                  // uuid.v4() wie überall sonst in der App. Der frühere
                  // Bastel-Schlüssel aus Original-ID + Zähler + Zeitstempel
                  // wuchs bei jedem erneuten Aufteilen weiter und konnte
                  // beim zweiten Aufteilen in derselben Millisekunde
                  // kollidieren.
                  id: Value(uuid.v4()),
                  productId: Value(task.productId),
                  mengeKg: Value(teilMenge),
                  // Über die Tageszahl: Über das Wochenende der
                  // Zeitumstellung landete ein Teil sonst einen Tag zu
                  // früh (Sonntag 23:00 statt Montag).
                  datum: Value(tagPlus(task.datum, i)),
                  abteilung: Value(task.abteilung),
                  // Ohne die Anlage landen die Folgetage in der Sammelspur
                  // der Abteilung statt auf der Maschine — die Auslastung
                  // der Anlage wäre dann zu niedrig, die der Sammelspur
                  // zu hoch.
                  maschineId: Value(task.maschineId),
                  startZeit: Value(task.startZeit),
                  geplanteDauerMinuten: Value(dauerJeTag),
                  geplanteMitarbeiter: Value(task.geplanteMitarbeiter),
                  sortierung: Value(task.sortierung),
                  parentTaskId: Value(kettenAnker),
                  notizen: Value(task.notizen),
                ),
              );
        }
      });

      ref.read(autoBackupTriggerProvider).fireDebounced(
            reason: 'Auftrag auf $tage Tage verteilt',
          );
      ref.invalidate(dailyTasksProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Auftrag auf $tage Tage verteilt '
              '(je ${(gesamtMenge / tage).toStringAsFixed(0)} kg).',
            ),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Verteilen fehlgeschlagen — der Auftrag ist unverändert '
              'geblieben. ($e)',
            ),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    }
  }

  /// Die hochgerechnete Dauer, wenn sie von der angezeigten abweicht —
  /// etwa bei einem Auftrag, der noch mit einem Platzhalter eingeplant
  /// wurde, bevor es Leistungsdaten oder erfasste Produktionen gab. null,
  /// wenn beide übereinstimmen oder sich nichts hochrechnen lässt.
  double? _abweichendeDauer(AbteilungsDauer? dauer) {
    if (dauer == null || dauer.quelle == DauerQuelle.platzhalter) return null;
    final neu = dauer.minuten.roundToDouble();
    final angezeigt = double.tryParse(_dauerController.text);
    if (angezeigt != null && (neu - angezeigt).abs() < 1) return null;
    return neu;
  }

  /// Hinweistext unter dem Dauerfeld: woher der Wert stammt.
  String? _dauerHinweis(AbteilungsDauer? dauer) {
    final modell = _modell;
    if (modell == null || dauer == null) return null;
    final h = dauer.historie;
    switch (dauer.quelle) {
      case DauerQuelle.historie:
        return h == null ? null : 'Aus ${h.herkunft} hochgerechnet';
      case DauerQuelle.historieErsatz:
        return h == null
            ? null
            : 'Keine Leistungsdaten — aus ${h.herkunft} hochgerechnet';
      case DauerQuelle.leistungsdaten:
        final messungen = modell.ersterSchritt.basisAnzahlMessungen;
        return messungen > 0
            ? 'Aus $messungen Messungen berechnet'
            : 'Aus den Leistungsdaten hochgerechnet';
      case DauerQuelle.platzhalter:
        return 'Platzhalter — weder Leistungsdaten noch Produktionen mit '
            'Zeit erfasst';
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final db = ref.read(databaseProvider);
      // double.tryParse akzeptiert auch 'NaN'/'Infinity' — solche Werte
      // dürfen nie in die Datenbank (NOT-NULL-Constraint schlägt fehl,
      // weil NaN als NULL gebunden wird).
      double? sicher(String text) {
        final v = double.tryParse(text.replaceAll(',', '.'));
        return (v != null && v.isFinite && v >= 0) ? v : null;
      }

      final newMenge = sicher(_mengeController.text) ??
          widget.wbTask.task.mengeKg;
      final newDauer = sicher(_dauerController.text) ??
          widget.wbTask.task.geplanteDauerMinuten;
      final newMa = int.tryParse(_mitarbeiterController.text) ??
          widget.wbTask.task.geplanteMitarbeiter;
      final startZeit = _startZeitController.text.trim();
      final notizen = _notizenController.text.trim();

      await (db.update(db.productionTasks)
            ..where((t) => t.id.equals(widget.wbTask.task.id)))
          .write(
        ProductionTasksCompanion(
          mengeKg: Value(newMenge),
          geplanteDauerMinuten: Value(newDauer),
          geplanteMitarbeiter: Value(newMa),
          startZeit: Value(startZeit.isEmpty ? null : startZeit),
          notizen: Value(notizen.isEmpty ? null : notizen),
          updatedAt: Value(DateTime.now()),
        ),
      );

      ref.invalidate(dailyTasksProvider);

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Druckt das Datenblatt der Kette, zu der dieser Auftrag gehört.
  /// Gedruckt wird der gespeicherte Stand — ungespeicherte Änderungen im
  /// Formular sind noch nicht drauf.
  Future<void> _datenblatt() {
    final db = ref.read(databaseProvider);
    final id = widget.wbTask.task.id;
    return druckeDatenblaetterMitMeldung(
      ScaffoldMessenger.of(context),
      () => alsListe(datenblattFuerKette(db, id)),
    );
  }

  /// Löscht den Task (Soft-Delete). Fragt, ob nur dieser Schritt oder die
  /// gesamte verkettete Produktion (alle Abteilungs-Schritte) entfernt wird.
  Future<void> _loeschen() async {
    final wahl = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aus der Planung löschen?'),
        content: const Text(
          'Nur diesen einen Schritt (diese Abteilung) entfernen oder die '
          'gesamte Produktion dieses Artikels — also alle verketteten '
          'Abteilungs-Schritte?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('abbrechen'),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('einzel'),
            child: const Text('Nur dieser Schritt'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop('ganze'),
            child: const Text('Ganze Produktion'),
          ),
        ],
      ),
    );
    if (wahl == null || wahl == 'abbrechen') return;

    setState(() => _isSaving = true);
    try {
      final db = ref.read(databaseProvider);
      final jetzt = DateTime.now();
      final ids = wahl == 'ganze'
          ? await _produktionsKettenIds(db, widget.wbTask.task)
          : [widget.wbTask.task.id];

      await (db.update(db.productionTasks)..where((t) => t.id.isIn(ids)))
          .write(
        ProductionTasksCompanion(
          deletedAt: Value(jetzt),
          updatedAt: Value(jetzt),
        ),
      );

      ref
          .read(autoBackupTriggerProvider)
          .fireDebounced(reason: 'Produktion aus Planung gelöscht');
      ref.invalidate(dailyTasksProvider);

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  /// Sammelt alle Task-IDs der verketteten Produktion (über
  /// [ProductionTask.parentTaskId]) zu der [start] gehört. Geht zur Wurzel
  /// hoch und von dort über alle Nachfahren — getrennte Planungen desselben
  /// Produkts bleiben unberührt, weil sie eigene Ketten bilden.
  Future<List<String>> _produktionsKettenIds(
    AppDatabase db,
    ProductionTask start,
  ) async {
    final alle = await (db.select(db.productionTasks)
          ..where((t) => t.productId.equals(start.productId))
          ..where((t) => t.deletedAt.isNull()))
        .get();
    final byId = {for (final t in alle) t.id: t};

    // Zur Wurzel hochlaufen.
    var root = start;
    final besucht = <String>{root.id};
    while (root.parentTaskId != null &&
        byId.containsKey(root.parentTaskId)) {
      final parent = byId[root.parentTaskId]!;
      if (!besucht.add(parent.id)) break; // Zyklus-Schutz
      root = parent;
    }

    // Von der Wurzel alle Nachfahren einsammeln.
    final kette = <String>{root.id};
    var geaendert = true;
    while (geaendert) {
      geaendert = false;
      for (final t in alle) {
        final p = t.parentTaskId;
        if (p != null && kette.contains(p) && kette.add(t.id)) {
          geaendert = true;
        }
      }
    }
    return kette.toList();
  }

  @override
  void dispose() {
    _mengeController.dispose();
    _dauerController.dispose();
    _mitarbeiterController.dispose();
    _startZeitController.dispose();
    _notizenController.dispose();
    super.dispose();
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    final abt = widget.wbTask.abteilungEnum;
    final colors = Theme.of(context).colorScheme;
    final modell = _modell;
    final dauer = modell?.dauerFuer(_aktuelleMenge);
    // Weicht die angezeigte Dauer von der hochgerechneten ab, steht sie
    // „wie eingeplant" da — und die neue Zahl wird zum Übernehmen
    // angeboten, statt die alte als hochgerechnet auszugeben.
    final abweichend = _abweichendeDauer(dauer);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
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
              // Drag-Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Kopf — Abteilungs-Farbband mit Kurzcode (einheitliche Kartensprache)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: abt.farbe.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: abt.farbe,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        abt.kurzcode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.wbTask.produktName,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${widget.wbTask.artikelnummer} · ${abt.anzeigeName}',
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Menge + automatische Neuberechnung
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _mengeController,
                      decoration: const InputDecoration(
                        labelText: 'Menge (kg)',
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[\d.,]'),
                        ),
                      ],
                      onChanged: (_) => _mengeGeaendert(),
                    ),
                  ),
                  if (modell != null) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Die Dauer wird aus der Menge hochgerechnet',
                      child: Icon(
                        Icons.auto_fix_high,
                        color: colors.primary,
                        size: 20,
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 14),

              // Dauer — reine Anzeige, vom System aus Menge und Historie
              // berechnet. Hier NICHT editierbar: Im Wochenplan-Sheet soll
              // nur die Menge angepasst werden, sonst nichts.
              _DauerAnzeige(
                dauerController: _dauerController,
                hinweis: abweichend == null
                    ? _dauerHinweis(dauer)
                    : 'Wie eingeplant',
              ),
              if (abweichend != null) ...[
                const SizedBox(height: 8),
                _NeuHochgerechnet(
                  minuten: abweichend,
                  grundlage: _dauerHinweis(dauer),
                  onUebernehmen: () => setState(() {
                    _dauerController.text = abweichend.toStringAsFixed(0);
                    _isDirty = true;
                  }),
                ),
              ],

              // Grundlage der Dauer: Leistungsdaten oder die letzten
              // Produktionen (Info-Box)
              if (modell != null && dauer != null) ...[
                const SizedBox(height: 20),
                _GrundlageBox(modell: modell, dauer: dauer),
              ],

              const SizedBox(height: 16),

              // Mehrtägige Prozesse (z.B. Spießen): Auftrag auf
              // aufeinanderfolgende Tage aufteilen.
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isSaving ? null : _verteileAufTageDialog,
                  icon: const Icon(Icons.date_range, size: 18),
                  label: const Text('Auf mehrere Tage verteilen'),
                ),
              ),

              const SizedBox(height: 8),

              // Datenblatt der ganzen Produktion (alle Abteilungen der
              // Kette) — zum Mitgeben in die Produktion.
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _datenblatt,
                  icon: const Icon(Icons.print_outlined, size: 18),
                  label: const Text('Datenblatt drucken'),
                ),
              ),

              const SizedBox(height: 16),

              // Speichern-Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: _isSaving || !_isDirty ? null : _save,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: Text(_isSaving ? 'Speichern …' : 'Speichern'),
                ),
              ),

              const SizedBox(height: 8),

              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: _isSaving ? null : _loeschen,
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  label: const Text(
                    'Aus Planung löschen',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Info-Box: Grundlage der Dauer
// ---------------------------------------------------------------------------

/// Kilogramm als ganze Zahl mit Tausenderpunkt: „12.857".
String _fmtKg(double kg) => kg.round().toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );

/// Zeigt, woraus die Dauer dieser Abteilung hochgerechnet wird: aus den
/// gepflegten Leistungsdaten oder — ohne sie — aus den letzten
/// Produktionen.
class _GrundlageBox extends StatelessWidget {
  const _GrundlageBox({required this.modell, required this.dauer});

  final AbteilungsDauerModell modell;
  final AbteilungsDauer dauer;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final step = modell.ersterSchritt;
    final h = dauer.historie;

    final zeilen = <Widget>[];
    String? hinweis;
    switch (dauer.quelle) {
      case DauerQuelle.historie:
      case DauerQuelle.historieErsatz:
        if (h != null) {
          zeilen.addAll([
            _infoRow(
              'Grundlage',
              h.anzahl == 1
                  ? 'Letzte Produktion'
                  : 'Letzte ${h.anzahl} Produktionen',
            ),
            _infoRow('Ø Menge', '${_fmtKg(h.mengeKg)} kg Rohware'),
            _infoRow('Ø Zeit', Zeit.lang(h.minuten)),
            _infoRow('Ø Leistung', '${_fmtKg(h.kgProStunde)} kg/h'),
          ]);
          // In der Bratstraße kommen die festen Durchlaufzeiten aller
          // Stationen dazu, sonst die Rüstzeit des Schritts.
          final dazu = modell.istBratstrasse
              ? modell.festeZeitMinuten
              : (step.fixZeitMinuten ?? 0.0);
          if (dazu > 0) {
            zeilen.add(
              _infoRow(
                modell.istBratstrasse ? 'Durchlauf/Verpacken' : 'Fixe Rüstzeit',
                Zeit.lang(dazu),
              ),
            );
          }
        }
        if (dauer.quelle == DauerQuelle.historieErsatz) {
          hinweis = 'Für diese Abteilung sind keine Leistungsdaten gepflegt. '
              'Genauer wird es mit Leistungsdaten im Artikel.';
        }
      case DauerQuelle.leistungsdaten:
        final messungen = step.basisAnzahlMessungen;
        zeilen.addAll([
          _infoRow(
            'Basismenge',
            '${step.basisMengeKg.toStringAsFixed(1)} kg',
          ),
          _infoRow(
            'Basisdauer',
            '${step.basisDauerMinuten.toStringAsFixed(0)} min',
          ),
          if (step.fixZeitMinuten != null && step.fixZeitMinuten! > 0)
            _infoRow(
              'Fixe Rüstzeit',
              '${step.fixZeitMinuten!.toStringAsFixed(0)} min',
            ),
          _infoRow(
            'Basismitarbeiter',
            '${step.basisMitarbeiter}',
          ),
          _infoRow(
            'Messungen',
            messungen == 0 ? 'Keine (Schätzwerte)' : '$messungen',
          ),
          if (step.dauerStdAbweichung != null)
            _infoRow(
              'Standardabweichung',
              '± ${step.dauerStdAbweichung!.toStringAsFixed(1)} min',
            ),
        ]);
      case DauerQuelle.platzhalter:
        hinweis = 'Weder Leistungsdaten noch eine Produktion mit Zeit '
            'erfasst — die Dauer ist ein Platzhalter. Leistungsdaten '
            'pflegst du im Artikel.';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights, size: 16, color: colors.primary),
              const SizedBox(width: 6),
              Text(
                'Grundlage der Dauer',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...zeilen,
          if (hinweis != null)
            Padding(
              padding: EdgeInsets.only(top: zeilen.isEmpty ? 0 : 4),
              child: Text(
                hinweis,
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Dialog zum Abschließen einer Produktion. Erfasst Datum, Roh-/Fertigmenge
/// und Zeiten und schreibt daraus eine Zeile in die Excel-Historie. Die
/// abgeleiteten Kennzahlen (Verlust, kg/h, Produktionszeit) werden live
/// vorgerechnet, damit man vor dem Speichern sieht, was gespeichert wird.

/// Bietet eine neu hochgerechnete Dauer zum Übernehmen an, wenn sie von
/// der eingeplanten abweicht.
class _NeuHochgerechnet extends StatelessWidget {
  const _NeuHochgerechnet({
    required this.minuten,
    required this.grundlage,
    required this.onUebernehmen,
  });

  final double minuten;
  final String? grundlage;
  final VoidCallback onUebernehmen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Neu hochgerechnet: ${Zeit.lang(minuten)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
                if (grundlage != null)
                  Text(
                    grundlage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onUebernehmen,
            child: const Text('Übernehmen'),
          ),
        ],
      ),
    );
  }
}

/// Reine Anzeige der geschätzten Dauer (nicht editierbar). Im Wochenplan-
/// Sheet soll nur die Menge angepasst werden; die Dauer errechnet das
/// System aus Menge und Historie und wird hier nur informativ gezeigt.
class _DauerAnzeige extends StatelessWidget {
  const _DauerAnzeige({required this.dauerController, this.hinweis});

  final TextEditingController dauerController;
  final String? hinweis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.schedule,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Geschätzte Dauer',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (hinweis != null)
                  Text(
                    hinweis!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.7),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Der Wert kommt aus demselben Controller, den die Mengen-Logik
          // fortschreibt — er aktualisiert sich also live beim Ändern der
          // Menge. AnimatedBuilder hält die Anzeige synchron.
          AnimatedBuilder(
            animation: dauerController,
            builder: (context, _) {
              final txt = dauerController.text.trim();
              // Immer Stunden + Minuten — „150 min" liest sich in der
              // Produktion schlechter als „2 h 30 min".
              final minuten = double.tryParse(txt);
              return Text(
                minuten == null ? '–' : Zeit.lang(minuten),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}



