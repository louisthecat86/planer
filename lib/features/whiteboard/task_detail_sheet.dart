import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';
import '../../core/theme/app_stil.dart';
import '../../core/ui/bausteine.dart';
import '../../core/utils/datum.dart';
import '../../core/utils/fehler_text.dart';
import '../../core/utils/format.dart';
import '../../core/utils/sheet_utils.dart';
import '../../core/utils/zeit.dart';
import '../datenblatt/datenblatt.dart';
import '../datenblatt/datenblatt_drucken.dart';
import 'produktions_mengen.dart';
import 'whiteboard_provider.dart';

/// Öffnet das Fenster mit allen Details zum Task — mittig, wie jedes
/// Bearbeitungsfenster der App.
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

  // ---- Mengen der Produktion ----
  //
  // Rohware, Fertigware und Fleischeinwaage gelten für die ganze
  // Produktion. Ändert sich eine, rechnen die anderen über Verlust und
  // Fleischanteil mit; dieser Auftrag nimmt davon, womit er arbeitet.

  final _rohController = TextEditingController();
  final _fertigController = TextEditingController();
  final _fleischController = TextEditingController();
  final _verlustController = TextEditingController();
  final _anteilController = TextEditingController();

  /// Die gekoppelten Mengen — null, solange sie laden oder wenn das Laden
  /// scheiterte ([_mengenFehler]).
  MengenEingabe? _eingabe;
  String? _mengenFehler;

  @override
  void initState() {
    super.initState();
    final t = widget.wbTask.task;
    _dauerController =
        TextEditingController(text: t.geplanteDauerMinuten.toStringAsFixed(0));
    _mitarbeiterController =
        TextEditingController(text: t.geplanteMitarbeiter.toString());
    _startZeitController = TextEditingController(text: t.startZeit ?? '');
    _notizenController = TextEditingController(text: t.notizen ?? '');

    _ladeModell();
    _ladeMengen();
  }

  /// Lädt Kette, Verlust und Fleischanteil der Produktion und füllt die
  /// Felder: was geplant ist, und was fehlt, über die Verhältnisse.
  Future<void> _ladeMengen() async {
    final ProduktionsMengen? m;
    try {
      m = await ladeProduktionsMengen(
        ref.read(databaseProvider),
        widget.wbTask.task.id,
      );
    } catch (e) {
      if (mounted) setState(() => _mengenFehler = fehlerText(e));
      return;
    }
    if (!mounted) return;
    if (m == null) {
      setState(() => _mengenFehler = 'Den Auftrag gibt es nicht mehr.');
      return;
    }
    final eingabe = MengenEingabe(m);
    setState(() {
      _eingabe = eingabe;
      _felderAus(eingabe);
    });
  }

  /// Schreibt die Texte von [e] in die Felder — außer in [ausser], in dem
  /// gerade getippt wird: Dort bliebe sonst der Cursor nicht stehen.
  void _felderAus(MengenEingabe e, {TextEditingController? ausser}) {
    void setze(TextEditingController c, String text) {
      if (!identical(c, ausser) && c.text != text) c.text = text;
    }

    setze(_rohController, e.roh);
    setze(_fertigController, e.fertig);
    setze(_fleischController, e.fleisch);
    setze(_verlustController, e.verlust);
    setze(_anteilController, e.anteil);
  }

  /// Dieser Auftrag, wie die Kette ihn kennt.
  ProductionTask get _auftrag {
    final t = widget.wbTask.task;
    return _eingabe?.mengen.kette.schritte
            .where((x) => x.id == t.id)
            .firstOrNull ??
        t;
  }

  /// Die Menge dieses Auftrags nach den Feldern — null, solange die
  /// Mengen laden.
  double? get _auftragsMenge => _eingabe?.auftragsMenge(_auftrag);

  /// Ein Feld der Mengen wurde geändert: die anderen nachziehen,
  /// speicherbar machen und die Dauer dieses Auftrags hochrechnen.
  void _mengeGeaendert(
    TextEditingController feld,
    void Function(MengenEingabe e) setze,
  ) {
    final e = _eingabe;
    if (e == null) return;
    setze(e);
    setState(() {
      _felderAus(e, ausser: feld);
      _isDirty = true;
    });
    final menge = _auftragsMenge;
    if (menge != null && menge > 0) _recalcDuration(menge);
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

  /// Die Menge dieses Auftrags nach den Feldern, solange sie gültig ist —
  /// sonst die eingeplante.
  double get _aktuelleMenge {
    final v = _auftragsMenge;
    return (v != null && v.isFinite && v > 0)
        ? v
        : widget.wbTask.task.mengeKg;
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
    final gesamtMenge = _aktuelleMenge;
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
                    'Je Tag: ${Format.kg(teilMenge)} · '
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
              '(je ${Format.kg(gesamtMenge / tage)}).',
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
              'geblieben. (${fehlerText(e)})',
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
    if (_modell == null || dauer == null) return null;
    final h = dauer.historie;
    switch (dauer.quelle) {
      case DauerQuelle.historie:
        return h == null ? null : 'Aus ${h.herkunft} hochgerechnet';
      case DauerQuelle.historieErsatz:
        return h == null
            ? null
            : 'Keine Leistungsdaten — aus ${h.herkunft} hochgerechnet';
      case DauerQuelle.leistungsdaten:
        return 'Aus den Leistungsdaten hochgerechnet';
      case DauerQuelle.platzhalter:
        return 'Platzhalter — weder Leistungsdaten noch Produktionen mit '
            'Zeit erfasst';
    }
  }

  /// Ob „Speichern" geht: Etwas ist geändert, und geänderte Mengen sind
  /// gültig. Ließen sich die Mengen nicht laden, speichert das Fenster ohne
  /// sie.
  bool get _kannSpeichern {
    if (_isSaving || !_isDirty) return false;
    final e = _eingabe;
    if (e == null) return _mengenFehler != null;
    return !e.geaendert || e.gueltig;
  }

  /// Speichert an diesem Auftrag Dauer, Personen, Start und Notiz — und,
  /// wenn sie geändert sind, die Mengen für die ganze Produktion: Alle
  /// Aufträge der Kette ziehen mit.
  Future<void> _save() async {
    final eingabe = _eingabe;
    setState(() => _isSaving = true);
    try {
      final db = ref.read(databaseProvider);
      // Nur endliche Werte (Format.lies lässt 'NaN'/'Infinity' weg) —
      // NaN würde als NULL gebunden und am NOT-NULL-Constraint scheitern.
      double? sicher(String text) {
        final v = Format.lies(text);
        return (v != null && v >= 0) ? v : null;
      }

      final newDauer = sicher(_dauerController.text) ??
          widget.wbTask.task.geplanteDauerMinuten;
      final newMa = int.tryParse(_mitarbeiterController.text) ??
          widget.wbTask.task.geplanteMitarbeiter;
      final startZeit = _startZeitController.text.trim();
      final notizen = _notizenController.text.trim();

      final auftrag = ProductionTasksCompanion(
        geplanteDauerMinuten: Value(newDauer),
        geplanteMitarbeiter: Value(newMa),
        startZeit: Value(startZeit.isEmpty ? null : startZeit),
        notizen: Value(notizen.isEmpty ? null : notizen),
      );
      if (eingabe != null && eingabe.geaendert) {
        await produktionsMengenSpeichern(
          db,
          eingabe.mengen.kette,
          rohKg: eingabe.rohKg,
          fertigKg: eingabe.fertigKg,
          fleischKg: eingabe.fleischKg,
          auftragId: widget.wbTask.task.id,
          auftrag: auftrag,
        );
      } else {
        // Mengen unverändert (oder nicht geladen): nur dieser Auftrag. Die
        // übrigen der Produktion bleiben, wie sie sind — auch eine
        // geschätzte Fleischeinwaage wird so nicht zur geplanten.
        await (db.update(db.productionTasks)
              ..where((t) => t.id.equals(widget.wbTask.task.id)))
            .write(auftrag.copyWith(updatedAt: Value(DateTime.now())));
      }

      ref
          .read(autoBackupTriggerProvider)
          .fireDebounced(reason: 'Auftrag im Board geändert');
      ref.invalidate(dailyTasksProvider);

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler: ${fehlerText(e)}'),
            backgroundColor: AppFarben.von(context).fehler,
          ),
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
      context,
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
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
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
          SnackBar(
            content: Text('Fehler: ${fehlerText(e)}'),
            backgroundColor: AppFarben.von(context).fehler,
          ),
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
    _rohController.dispose();
    _fertigController.dispose();
    _fleischController.dispose();
    _verlustController.dispose();
    _anteilController.dispose();
    _dauerController.dispose();
    _mitarbeiterController.dispose();
    _startZeitController.dispose();
    _notizenController.dispose();
    super.dispose();
  }

  // ---- UI ----

  /// Die drei Mengen untereinander, darunter Verlust und Fleischanteil —
  /// und womit dieser Auftrag arbeitet.
  List<Widget> _mengenFelder(ThemeData theme) {
    final grau = theme.colorScheme.onSurfaceVariant;
    final fehler = _mengenFehler;
    if (fehler != null) {
      return [
        HinweisBox(
          fehler,
          art: StatusArt.fehler,
          titel: 'Die Mengen der Produktion ließen sich nicht laden',
          auswaehlbar: true,
        ),
      ];
    }
    final e = _eingabe;
    if (e == null) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    final k = e.mengen.kette;
    final t = _auftrag;
    final teile = k.teileVon(t);
    final menge = _auftragsMenge;
    final mitRohware = k.bezugVon(t) == MengenBezug.rohware;
    final hinweis = [
      if (mitRohware && k.hatBratstrasse)
        'Dieser Auftrag arbeitet mit der Rohware, wie alle Schritte bis '
            'einschließlich Bratstraße.'
      else if (mitRohware)
        'Dieser Auftrag arbeitet mit der Rohware.'
      else
        'Dieser Auftrag arbeitet mit der Fertigware, wie alle Schritte nach '
            'der Bratstraße.',
      if (teile.length > 1 && menge != null)
        'Er ist auf ${teile.length} Tage verteilt — an diesem Tag '
            '${Format.kg(menge)}.',
      if (k.schritte.length > 1)
        'Die Mengen gelten für die ganze Produktion: Beim Speichern ziehen '
            'alle ${k.schritte.length} Aufträge mit.',
    ].join(' ');

    InputDecoration deko(
      String label,
      String einheit, {
      String? hilfe,
      String? fehler,
    }) =>
        InputDecoration(
          labelText: label,
          suffixText: einheit,
          helperText: hilfe,
          helperMaxLines: 2,
          errorText: fehler,
          errorMaxLines: 2,
        );

    Widget feld(
      String schluessel,
      TextEditingController controller,
      ValueChanged<String> onChanged,
      InputDecoration decoration,
    ) =>
        TextField(
          key: ValueKey(schluessel),
          controller: controller,
          decoration: decoration,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
          ],
          onChanged: onChanged,
        );

    return [
      feld(
        'menge-roh',
        _rohController,
        (text) => _mengeGeaendert(_rohController, (m) => m.setzeRoh(text)),
        deko('Rohware', 'kg', fehler: e.rohFehler),
      ),
      const SizedBox(height: 12),
      feld(
        'menge-fertig',
        _fertigController,
        (text) =>
            _mengeGeaendert(_fertigController, (m) => m.setzeFertig(text)),
        deko('Fertigware', 'kg', fehler: e.fertigFehler),
      ),
      const SizedBox(height: 12),
      feld(
        'menge-fleisch',
        _fleischController,
        (text) =>
            _mengeGeaendert(_fleischController, (m) => m.setzeFleisch(text)),
        deko('Fleischeinwaage', 'kg', fehler: e.fleischFehler),
      ),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: feld(
              'menge-verlust',
              _verlustController,
              (text) => _mengeGeaendert(
                _verlustController,
                (m) => m.setzeVerlust(text),
              ),
              deko(
                'Verlust',
                '%',
                hilfe: e.verlustHerkunft ??
                    'unbekannt — ergibt sich aus der Fertigware',
                fehler: e.verlustFehler,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: feld(
              'menge-anteil',
              _anteilController,
              (text) => _mengeGeaendert(
                _anteilController,
                (m) => m.setzeAnteil(text),
              ),
              deko(
                'Fleischanteil',
                '%',
                hilfe: e.anteilHerkunft ??
                    'unbekannt — ergibt sich aus der Fleischeinwaage',
                fehler: e.anteilFehler,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: grau),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hinweis,
              style: theme.textTheme.bodySmall?.copyWith(color: grau),
            ),
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final abt = widget.wbTask.abteilungEnum;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
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
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            children: [
              // Kopf wie bei jedem Fenster der App: Abteilungskürzel,
              // Artikel als Titel in Blau, rechts ein Kreuz. Vorher saßen
              // hier der Anfasser aus der Bottom-Sheet-Zeit und ein
              // eingefärbtes Band.
              Row(
                children: [
                  AbteilungsMarke(abteilung: abt, skala: 1.2),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.wbTask.produktName,
                          style: theme.dialogTheme.titleTextStyle ??
                              theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.wbTask.artikelnummer} · '
                          '${abt.anzeigeName}',
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Schließen ohne Speichern',
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).pop(false),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Rohware, Fertigware und Fleischeinwaage der Produktion —
              // gekoppelt über Verlust und Fleischanteil.
              ..._mengenFelder(theme),

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
              // Produktionen
              if (modell != null && dauer != null) ...[
                const SizedBox(height: 16),
                _GrundlageBox(modell: modell, dauer: dauer),
              ],

              const SizedBox(height: 16),

              // Weitere Aktionen: mehrtägige Prozesse (z.B. Spießen) auf
              // aufeinanderfolgende Tage aufteilen; das Datenblatt der
              // ganzen Produktion zum Mitgeben in die Produktion.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _isSaving ? null : _verteileAufTageDialog,
                    icon: const Icon(Icons.date_range, size: 18),
                    label: const Text('Auf mehrere Tage verteilen …'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _datenblatt,
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: const Text('Datenblatt drucken'),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Knöpfe unten wie in jedem Fenster der App: rechts
              // Abbrechen und Speichern, links das Löschen — abgesetzt,
              // damit man es nicht aus Versehen trifft.
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _isSaving ? null : _loeschen,
                    style: TextButton.styleFrom(
                      foregroundColor: colors.error,
                    ),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Aus Planung löschen …'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _kannSpeichern ? _save : null,
                    // Ohne feste Farbe: Der gesperrte Knopf ist hellgrau,
                    // ein weißer Kreisel wäre darauf unsichtbar.
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save, size: 18),
                    label: Text(_isSaving ? 'Speichern …' : 'Speichern'),
                  ),
                ],
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
/// hinterlegten Leistungsdaten oder aus den letzten Produktionen.
class _GrundlageBox extends StatelessWidget {
  const _GrundlageBox({required this.modell, required this.dauer});

  final AbteilungsDauerModell modell;
  final AbteilungsDauer dauer;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final h = dauer.historie;
    final leistung = modell.leistungsdaten;

    final zeilen = <Widget>[];
    // Was an der Grundlage fehlt: blau zur Info, orange, wenn die Dauer
    // nur ein Platzhalter ist.
    HinweisBox? hinweis;
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
        }
        if (dauer.quelle == DauerQuelle.historieErsatz) {
          hinweis = const HinweisBox(
            'Für diese Abteilung sind keine Leistungsdaten hinterlegt. '
            'Genauer wird es mit Leistungsdaten im Artikel.',
          );
        }
      case DauerQuelle.leistungsdaten:
        if (leistung != null) {
          zeilen.addAll([
            _infoRow('Grundlage', 'Hinterlegte Leistungsdaten'),
            _infoRow('Menge', '${_fmtKg(leistung.mengeKg)} kg'),
            _infoRow('Zeit', Zeit.lang(leistung.minuten)),
            _infoRow('Leistung', '${_fmtKg(leistung.kgProStunde)} kg/h'),
          ]);
        }
      case DauerQuelle.platzhalter:
        hinweis = const HinweisBox(
          'Weder Leistungsdaten noch eine Produktion mit Zeit erfasst — die '
          'Dauer ist ein Platzhalter. Leistungsdaten pflegst du im Artikel.',
          art: StatusArt.warnung,
        );
    }

    // Eine ruhige graue Fläche wie die Leisten der App: Hier steht, womit
    // gerechnet wird — keine Bewertung.
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppFarben.von(context).leiste,
        borderRadius: AppMasse.ecken,
        border: Border.all(color: colors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.insights, size: 16, color: colors.onSurfaceVariant),
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
              child: hinweis,
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
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

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
    final zusatz = grundlage;
    return HinweisBox(
      zusatz == null ? Zeit.lang(minuten) : '${Zeit.lang(minuten)} · $zusatz',
      titel: 'Neu hochgerechnet',
      icon: Icons.auto_fix_high,
      gross: true,
      aktion: TextButton(
        onPressed: onUebernehmen,
        child: const Text('Übernehmen'),
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
    final zusatz = hinweis;
    // Grau hinterlegt wie ein Feld, das man nicht ändern kann.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppFarben.von(context).leiste,
        borderRadius: AppMasse.ecken,
        border: Border.all(color: theme.colorScheme.outline),
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
                if (zusatz != null)
                  Text(
                    zusatz,
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
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
