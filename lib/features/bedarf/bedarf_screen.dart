import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/database.dart';
import '../../core/druck/druck_fenster.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auftragsbestand_deckung.dart'
    show
        AuftragsBezug,
        beschreibeBezuege,
        kQuelleAuftragsbestand,
        ladeBedarfsPlanung;
import '../../core/services/auto_backup_trigger.dart';
import '../../core/theme/app_stil.dart';
import '../../core/ui/bausteine.dart';
import '../../core/utils/fehler_text.dart';
import '../../core/utils/sheet_utils.dart';
import '../datenblatt/datenblatt.dart';
import '../datenblatt/datenblatt_drucken.dart';
import 'bedarf_druck.dart';
import 'bedarf_modell.dart';

export 'bedarf_modell.dart' show BedarfInfo;

// ---------------------------------------------------------------------------
// Tag und Liste
// ---------------------------------------------------------------------------

/// Der aktuelle Kalendertag (auf 00:00 normiert), der sich um Mitternacht
/// selbst erneuert.
///
/// Der Bedarfs-Screen bewertet zwei Dinge gegen „heute": ob ein Termin
/// überschritten ist, und ob ein Produktionstag schon vorbei ist. Ohne
/// diesen Provider las das jeder Aufruf frisch aus `DateTime.now()` — die
/// Liste selbst wurde aber nie neu berechnet. Eine App, die über Nacht
/// offen bleibt (Schichtbetrieb), zeigte deshalb morgens noch den Stand
/// vom Vortag: Gestern geplante Produktionen galten weiter als „in
/// Planung" statt als gelaufen.
///
/// Der Timer feuert eine Sekunde nach Mitternacht und invalidiert den
/// Provider; alles, was ihn beobachtet, rechnet dann neu.
final heuteProvider = Provider<DateTime>((ref) {
  final jetzt = DateTime.now();
  final heute = DateTime(jetzt.year, jetzt.month, jetzt.day);
  // Bewusst über die Tageszahl statt per Duration: Bei Zeitumstellung hat
  // ein Tag 23 oder 25 Stunden, `add(Duration(days: 1))` läge dann daneben.
  final naechsteMitternacht = DateTime(heute.year, heute.month, heute.day + 1);

  final timer = Timer(
    naechsteMitternacht.difference(jetzt) + const Duration(seconds: 1),
    ref.invalidateSelf,
  );
  ref.onDispose(timer.cancel);

  return heute;
});

/// Alle offenen und erledigten Bedarfe, sortiert: überfällig → Termin →
/// Priorität.
final bedarfProvider = FutureProvider<List<BedarfInfo>>((ref) async {
  final db = ref.watch(databaseProvider);
  // Um Mitternacht erneuert sich der Tag — und damit diese Liste.
  final heuteNorm = ref.watch(heuteProvider);

  final bedarfe = await (db.select(db.demands)
        ..where((b) => b.deletedAt.isNull()))
      .get();
  if (bedarfe.isEmpty) return [];

  final produkte = await (db.select(db.products)
        ..where((p) => p.deletedAt.isNull()))
      .get();
  final nameById = {for (final p in produkte) p.id: p};

  // Geplante Fertigmengen je Bedarf — dieselbe Rechnung wie im
  // Auftragsbestand und im Planungsvorschlag. Was davon auf einem Tag vor
  // heute liegt, gilt als produziert.
  final planung = await ladeBedarfsPlanung(db);

  final result = [
    for (final b in bedarfe)
      BedarfInfo(
        bedarf: b,
        artikelName: nameById[b.productId]?.artikelbezeichnung ?? 'Unbekannt',
        artikelNummer: nameById[b.productId]?.artikelnummer ?? '—',
        geplantKg: planung[b.id]?.kg ?? 0,
        produziertKg: planung[b.id]?.produziertVor(heuteNorm) ?? 0,
        heute: heuteNorm,
      ),
  ];

  result.sort((a, b) {
    // Erledigte immer ans Ende
    if (a.erledigt != b.erledigt) return a.erledigt ? 1 : -1;
    // Überfällige nach oben
    if (a.ueberfaellig != b.ueberfaellig) return a.ueberfaellig ? -1 : 1;
    // Dann nach Termin (ohne Termin zuletzt)
    final ta = a.bedarf.termin;
    final tb = b.bedarf.termin;
    if (ta != null && tb != null && ta != tb) return ta.compareTo(tb);
    if (ta == null && tb != null) return 1;
    if (ta != null && tb == null) return -1;
    // Dann Priorität
    return b.bedarf.prioritaet.compareTo(a.bedarf.prioritaet);
  });
  return result;
});

/// Stammt [b] aus dem früheren Weg „Navision-Artikelübersicht → Bedarf"?
///
/// Der Weg ist entfernt; Bedarf aus Navision entsteht jetzt im
/// Auftragsbestand, je Auftrag und Versandtag. Die alten Einträge trugen
/// als Notiz „Aus Navision · …". Offen gelassen würden sie neben den
/// Planungsaufträgen ein zweites Mal gegen dieselbe Ware zählen.
bool ausAltemNavisionImport(Demand b) =>
    b.quelle == 'bestellung' &&
    (b.notizen ?? '').trimLeft().startsWith('Aus Navision');

/// Nur die noch offenen Bedarfe — für die Auswahl beim Planen.
final offeneBedarfeProvider = FutureProvider<List<BedarfInfo>>((ref) async {
  final alle = await ref.watch(bedarfProvider.future);
  return alle.where((b) => !b.erledigt).toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class BedarfScreen extends ConsumerWidget {
  const BedarfScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(bedarfProvider);
    final geladen = async.valueOrNull;
    // Schmale Fenster: der Knopf der Kopfleiste nur als Symbol.
    final schmal = MediaQuery.sizeOf(context).width < 720;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bedarfsliste'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Bedarfsliste drucken',
            onPressed: geladen == null || geladen.isEmpty
                ? null
                : () => druckFensterOeffnen(
                      context,
                      bedarfDruckAuftrag(
                        geladen,
                        heute: ref.read(heuteProvider),
                      ),
                    ),
          ),
          const SizedBox(width: 4),
          // Die Hauptaktion der Seite oben rechts — wie „Neuer Artikel" in
          // der Artikelliste.
          if (schmal)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Bedarf hinzufügen',
              onPressed: () => _bearbeiten(context, ref, null),
            )
          else
            FilledButton.icon(
              onPressed: () => _bearbeiten(context, ref, null),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Bedarf hinzufügen'),
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: async.when(
        data: (liste) {
          if (liste.isEmpty) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: LeerHinweis(
                  'Noch kein Bedarf erfasst. Trage hier ein, was produziert '
                  'werden muss — Bestellungen oder Bestandsauffüllung. Beim '
                  'Planen wählst du dann direkt daraus aus.',
                  icon: Icons.playlist_add,
                  aktion: FilledButton.icon(
                    onPressed: () => _bearbeiten(context, ref, null),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Ersten Bedarf anlegen'),
                  ),
                ),
              ),
            );
          }

          final farben = Theme.of(context).colorScheme;
          final offen = liste.where((b) => !b.erledigt).toList();
          final offenSumme =
              offen.fold<double>(0, (s, b) => s + b.offenKg);
          final ueberfaellig = offen.where((b) => b.ueberfaellig).length;
          final erledigt = liste.length - offen.length;
          final altNavision = [
            for (final b in offen)
              if (ausAltemNavisionImport(b.bedarf)) b,
          ];

          return Column(
            children: [
              // Kennzahlen in einem Bereich wie im Auftragsbestand — vorher
              // ein grau hinterlegter Streifen.
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                child: Bereich(
                  titel: 'Offener Bedarf',
                  icon: Icons.assignment_outlined,
                  untertitel: erledigt == 0 ? null : '$erledigt erledigt',
                  innenAbstand: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Wrap(
                    spacing: 28,
                    runSpacing: 10,
                    children: [
                      Kennzahl(wert: '${offen.length}', label: 'offen'),
                      Kennzahl(
                        wert: '${offenSumme.round()} kg',
                        label: 'noch einzuplanen',
                      ),
                      if (ueberfaellig > 0)
                        Kennzahl(
                          wert: '$ueberfaellig',
                          label: 'überfällig',
                          farbe: AppFarben.von(context).fehler,
                        ),
                    ],
                  ),
                ),
              ),
              if (altNavision.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: HinweisBox(
                    altNavision.length == 1
                        ? '1 offener Bedarf stammt noch aus dem früheren '
                            'Navision-Import. Bedarf aus Navision entsteht '
                            'jetzt im Auftragsbestand.'
                        : '${altNavision.length} offene Bedarfe stammen noch '
                            'aus dem früheren Navision-Import. Bedarf aus '
                            'Navision entsteht jetzt im Auftragsbestand.',
                    art: StatusArt.warnung,
                    icon: Icons.history_toggle_off_rounded,
                    aktion: TextButton(
                      onPressed: () =>
                          _altNavisionErledigen(context, ref, altNavision),
                      child: const Text('Als erledigt markieren …'),
                    ),
                  ),
                ),
              // Die Bedarfe als Zeilen einer weißen Fläche mit Spaltenkopf —
              // wie die Listen in Navision. Vorher stand jeder Bedarf auf
              // einer eigenen Karte.
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Material(
                    color: farben.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppMasse.ecken,
                      side: BorderSide(color: farben.outline),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // Ab dieser Breite steht der Fortschritt als Balken
                        // in der Zeile.
                        final breit = constraints.maxWidth >= 900;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _BedarfKopf(breit: breit),
                            Expanded(
                              child: ListView.builder(
                                itemCount: liste.length,
                                itemBuilder: (context, i) {
                                  final info = liste[i];
                                  return _BedarfZeile(
                                    info: info,
                                    breit: breit,
                                    onTap: () =>
                                        _bearbeiten(context, ref, info.bedarf),
                                    onErledigt: () =>
                                        _erledigtUmschalten(ref, info),
                                    onLoeschen: () =>
                                        _loeschen(context, ref, info),
                                    onDatenblatt: () =>
                                        _datenblatt(context, ref, info),
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: ${fehlerText(e)}')),
      ),
    );
  }

  /// Druckt das Datenblatt des Bedarfs: Artikel, Menge, spätester
  /// Produktionstag und — bei einem Planungsauftrag — die Aufträge.
  Future<void> _datenblatt(
    BuildContext context,
    WidgetRef ref,
    BedarfInfo info,
  ) {
    final db = ref.read(databaseProvider);
    return druckeDatenblaetterMitMeldung(
      context,
      () => alsListe(datenblattFuerBedarf(db, info.bedarf.id)),
    );
  }

  /// Setzt die offenen Bedarfe aus dem früheren Navision-Import auf
  /// erledigt. Nichts wird gelöscht: Wer einen davon doch braucht, öffnet
  /// ihn über das Menü der Karte wieder.
  Future<void> _altNavisionErledigen(
    BuildContext context,
    WidgetRef ref,
    List<BedarfInfo> alte,
  ) async {
    final summe = alte.fold<double>(0, (s, b) => s + b.offenKg);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Alte Navision-Bedarfe schließen?'),
        content: SizedBox(
          width: 480,
          child: Text(
            '${alte.length} offene Bedarfe (${summe.round()} kg) stammen '
            'noch aus dem früheren Import der Navision-Artikelübersicht. '
            'Bedarf aus Navision entsteht jetzt im Auftragsbestand — je '
            'Auftrag und Versandtag. Offen gelassen würden die alten '
            'Einträge dieselbe Ware ein zweites Mal verlangen.\n\n'
            'Sie werden als erledigt markiert, nicht gelöscht. Über das '
            'Menü einer Karte lässt sich jeder wieder öffnen.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Als erledigt markieren'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final db = ref.read(databaseProvider);
    final ids = [for (final b in alte) b.bedarf.id];
    await (db.update(db.demands)..where((b) => b.id.isIn(ids))).write(
      DemandsCompanion(
        manuellErledigt: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
    ref
        .read(autoBackupTriggerProvider)
        .fireDebounced(reason: 'Alte Navision-Bedarfe erledigt');
    ref.invalidate(bedarfProvider);
  }

  Future<void> _erledigtUmschalten(WidgetRef ref, BedarfInfo info) async {
    final db = ref.read(databaseProvider);
    await (db.update(db.demands)..where((b) => b.id.equals(info.bedarf.id)))
        .write(
      DemandsCompanion(
        manuellErledigt: Value(!info.bedarf.manuellErledigt),
        updatedAt: Value(DateTime.now()),
      ),
    );
    ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Bedarf geändert');
    ref.invalidate(bedarfProvider);
  }

  Future<void> _loeschen(
    BuildContext context,
    WidgetRef ref,
    BedarfInfo info,
  ) async {
    // Ein Planungsauftrag hält Zeilen im Auftragsbestand fest — die werden
    // mit dem Löschen wieder frei.
    final zusatz = info.bedarf.quelle == kQuelleAuftragsbestand
        ? ' Was davon noch nicht eingeplant ist, ist im Auftragsbestand '
            'danach wieder offen.'
        : '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bedarf löschen?'),
        content: Text(
          '${info.artikelName}\n${info.bedarf.mengeKgFertig.round()} kg\n\n'
          'Bereits geplante Aufträge bleiben bestehen.$zusatz',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final db = ref.read(databaseProvider);
    await (db.update(db.demands)..where((b) => b.id.equals(info.bedarf.id)))
        .write(DemandsCompanion(deletedAt: Value(DateTime.now())));
    ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Bedarf gelöscht');
    ref.invalidate(bedarfProvider);
  }

  Future<void> _bearbeiten(
    BuildContext context,
    WidgetRef ref,
    Demand? vorhanden,
  ) async {
    // Ohne Anfasser: Das Fenster hat einen eigenen Kopf mit Titel und
    // Kreuz wie jedes Fenster der App.
    final geaendert = await showSheetOhneAnimation<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => _BedarfEditor(bedarf: vorhanden),
    );
    if (geaendert == true) ref.invalidate(bedarfProvider);
  }
}

/// Spaltenbreiten der Bedarfsliste — für Kopf und Zeilen dieselben.
abstract final class _Spalten {
  static const double nummer = 78;
  static const double termin = 150;
  static const double menge = 80;
  static const double fortschritt = 170;
  static const double status = 150;
  static const double prio = 28;
  static const double menue = 40;

  /// Abstand zwischen zwei Spalten.
  static const double luecke = 12;
}

/// Spaltenköpfe der Bedarfsliste auf der Fläche der Leisten.
class _BedarfKopf extends StatelessWidget {
  const _BedarfKopf({required this.breit});

  /// Breit genug für den Fortschritt.
  final bool breit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stil = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurfaceVariant,
    );
    Widget spalte(String text, double breite, {bool rechts = false}) =>
        SizedBox(
          width: breite,
          child: Text(
            text,
            maxLines: 1,
            textAlign: rechts ? TextAlign.right : TextAlign.left,
            style: stil,
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4 + _Spalten.menue, 8),
      decoration: BoxDecoration(
        color: AppFarben.von(context).leiste,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outline),
        ),
      ),
      child: Row(
        children: [
          spalte('Nr.', _Spalten.nummer),
          Expanded(child: Text('Artikel', style: stil)),
          const SizedBox(width: _Spalten.luecke),
          spalte('Termin', _Spalten.termin),
          spalte('Menge', _Spalten.menge, rechts: true),
          if (breit) ...[
            const SizedBox(width: _Spalten.luecke + 4),
            spalte('Fortschritt', _Spalten.fortschritt),
          ],
          const SizedBox(width: _Spalten.luecke + 4),
          spalte('Status', _Spalten.status),
          const SizedBox(width: _Spalten.prio),
        ],
      ),
    );
  }
}

/// Ein Bedarf als Zeile der Liste. Antippen öffnet ihn zum Bearbeiten.
class _BedarfZeile extends StatelessWidget {
  const _BedarfZeile({
    required this.info,
    required this.breit,
    required this.onTap,
    required this.onErledigt,
    required this.onLoeschen,
    required this.onDatenblatt,
  });

  final BedarfInfo info;

  /// Breit genug für den Fortschritt.
  final bool breit;
  final VoidCallback onTap;
  final VoidCallback onErledigt;
  final VoidCallback onLoeschen;
  final VoidCallback onDatenblatt;

  String _fortschrittText(BedarfInfo info) {
    final b = info.bedarf;
    if (info.produziertKg >= 0.5 && info.produziertKg < b.mengeKgFertig - 0.5) {
      return '${info.produziertKg.round()} kg produziert · '
          '${info.geplantKg.round()} von ${b.mengeKgFertig.round()} kg geplant';
    }
    return '${info.geplantKg.round()} von '
        '${b.mengeKgFertig.round()} kg eingeplant';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final farben = theme.colorScheme;
    final f = AppFarben.von(context);
    final b = info.bedarf;
    final stil = theme.textTheme.bodyMedium;
    final zahlen = stil?.copyWith(fontFeatures: _ziffern);
    final grau = theme.textTheme.bodySmall?.copyWith(
      color: farben.onSurfaceVariant,
    );

    // Farbe des Fortschritts: grün gedeckt, rot überfällig, sonst blau.
    final akzent = info.erledigt
        ? f.ok
        : info.ueberfaellig
            ? f.fehler
            : f.info;

    // Der Status nennt das Wichtigste: gedeckt, was noch offen ist — rot,
    // wenn der Termin vorbei ist —, oder was schon eingeplant ist.
    final StatusMarke status;
    if (info.erledigt) {
      final vonHand =
          b.manuellErledigt && info.produziertKg < b.mengeKgFertig - 0.5;
      status = StatusMarke(
        vonHand ? 'erledigt' : 'gedeckt',
        art: StatusArt.ok,
        hinweis: vonHand ? 'Von Hand als erledigt markiert' : null,
      );
    } else if (info.offenKg >= 0.5) {
      status = StatusMarke(
        '${info.offenKg.round()} kg offen',
        art: info.ueberfaellig ? StatusArt.fehler : StatusArt.warnung,
      );
    } else {
      status = StatusMarke(
        '${info.inPlanungKg.round()} kg geplant',
        art: StatusArt.info,
      );
    }

    final termin = b.termin;
    final Widget terminAnzeige;
    if (termin == null) {
      terminAnzeige = Text(
        'ohne Termin',
        style: stil?.copyWith(color: farben.onSurfaceVariant),
      );
    } else if (info.ueberfaellig) {
      terminAnzeige = StatusMarke(
        'überfällig · ${_tagKurz(termin)}',
        art: StatusArt.fehler,
        hinweis: 'Termin ${_datum(termin)} überschritten',
      );
    } else {
      terminAnzeige = Text(
        termin.year == info.heute.year ? _tagKurz(termin) : _datum(termin),
        style: zahlen,
      );
    }

    // Unter der Bezeichnung grau: woher der Bedarf kommt und die Notiz.
    final notiz = b.notizen?.trim() ?? '';
    final herkunft = [
      bedarfQuelleText(b.quelle),
      if (notiz.isNotEmpty) notiz,
    ].join(' · ');

    // Material statt Farbe am Container: Die Hover- und Tipp-Welle des
    // InkWell malt auf das nächste Material.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.fromLTRB(12, 5, 4, 5),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: farben.outlineVariant),
            ),
          ),
          // Erledigte blass — sie stehen am Ende der Liste.
          child: Opacity(
            opacity: info.erledigt ? 0.55 : 1,
            child: Row(
              children: [
                SizedBox(
                  width: _Spalten.nummer,
                  child: Text(
                    info.artikelNummer,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: zahlen?.copyWith(
                      // Blau wie ein Link: Antippen öffnet den Bedarf.
                      color: farben.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        info.artikelName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: stil?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        herkunft,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: grau,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: _Spalten.luecke),
                SizedBox(
                  width: _Spalten.termin,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    heightFactor: 1,
                    child: terminAnzeige,
                  ),
                ),
                SizedBox(
                  width: _Spalten.menge,
                  child: Text(
                    '${b.mengeKgFertig.round()} kg',
                    maxLines: 1,
                    textAlign: TextAlign.right,
                    style: zahlen,
                  ),
                ),
                if (breit) ...[
                  const SizedBox(width: _Spalten.luecke + 4),
                  SizedBox(
                    width: _Spalten.fortschritt,
                    child: Tooltip(
                      message: _fortschrittText(info),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Zweistufig: kräftig = schon produziert (Tag
                          // vorbei), blasser = eingeplant, aber noch offen.
                          ClipRRect(
                            borderRadius: AppMasse.eckenKlein,
                            child: Stack(
                              children: [
                                LinearProgressIndicator(
                                  value: info.fortschritt,
                                  minHeight: 6,
                                  backgroundColor: farben.outlineVariant,
                                  color: akzent.withValues(alpha: 0.35),
                                ),
                                LinearProgressIndicator(
                                  value: info.produziertAnteil,
                                  minHeight: 6,
                                  backgroundColor: Colors.transparent,
                                  color: akzent,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _fortschrittText(info),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: grau?.copyWith(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: _Spalten.luecke + 4),
                SizedBox(
                  width: _Spalten.status,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    heightFactor: 1,
                    // Wird es mit großer Schrift zu eng, wird die Marke
                    // kleiner, statt über den Rand zu laufen.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: status,
                    ),
                  ),
                ),
                SizedBox(
                  width: _Spalten.prio,
                  child: b.prioritaet > 0
                      ? Tooltip(
                          message: 'Hohe Priorität',
                          child: Icon(
                            Icons.priority_high,
                            size: 18,
                            color: f.fehler,
                          ),
                        )
                      : null,
                ),
                SizedBox(
                  width: _Spalten.menue,
                  child: PopupMenuButton<String>(
                    tooltip: 'Mehr',
                    icon: const Icon(Icons.more_vert, size: 18),
                    onSelected: (v) {
                      if (v == 'datenblatt') onDatenblatt();
                      if (v == 'erledigt') onErledigt();
                      if (v == 'loeschen') onLoeschen();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'datenblatt',
                        child: Text('Datenblatt drucken'),
                      ),
                      PopupMenuItem(
                        value: 'erledigt',
                        child: Text(
                          b.manuellErledigt
                              ? 'Wieder öffnen'
                              : 'Als erledigt markieren',
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'loeschen',
                        child: Text('Löschen'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Editor
// ---------------------------------------------------------------------------

class _BedarfEditor extends ConsumerStatefulWidget {
  const _BedarfEditor({required this.bedarf});

  final Demand? bedarf;

  @override
  ConsumerState<_BedarfEditor> createState() => _BedarfEditorState();
}

class _BedarfEditorState extends ConsumerState<_BedarfEditor> {
  final _suche = TextEditingController();
  final _menge = TextEditingController();
  final _notizen = TextEditingController();

  String? _productId;
  String _quelle = 'bestellung';
  int _prioritaet = 0;
  DateTime? _termin;
  bool _busy = false;

  /// Planungsauftrag aus dem Auftragsbestand: Artikel und Herkunft stehen
  /// fest — die gebündelten Auftragszeilen gehören zu genau diesem Artikel.
  bool get _ausAuftragsbestand => _quelle == kQuelleAuftragsbestand;

  @override
  void initState() {
    super.initState();
    final b = widget.bedarf;
    if (b != null) {
      _productId = b.productId;
      _menge.text = b.mengeKgFertig.toStringAsFixed(0);
      _notizen.text = b.notizen ?? '';
      _quelle = b.quelle;
      _prioritaet = b.prioritaet;
      _termin = b.termin;
    }
  }

  @override
  void dispose() {
    _suche.dispose();
    _menge.dispose();
    _notizen.dispose();
    super.dispose();
  }

  Future<void> _speichern() async {
    final pid = _productId;
    final menge = double.tryParse(_menge.text.replaceAll(',', '.'));
    if (pid == null || menge == null || menge <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte Artikel wählen und eine Menge > 0 eingeben.'),
        ),
      );
      return;
    }

    setState(() => _busy = true);
    final db = ref.read(databaseProvider);
    final jetzt = DateTime.now();
    final notiz = _notizen.text.trim().isEmpty ? null : _notizen.text.trim();

    if (widget.bedarf == null) {
      await db.into(db.demands).insert(
            DemandsCompanion.insert(
              id: const Uuid().v4(),
              productId: pid,
              mengeKgFertig: menge,
              termin: Value(_termin),
              quelle: Value(_quelle),
              prioritaet: Value(_prioritaet),
              notizen: Value(notiz),
            ),
          );
    } else {
      await (db.update(db.demands)
            ..where((b) => b.id.equals(widget.bedarf!.id)))
          .write(
        DemandsCompanion(
          productId: Value(pid),
          mengeKgFertig: Value(menge),
          termin: Value(_termin),
          quelle: Value(_quelle),
          prioritaet: Value(_prioritaet),
          notizen: Value(notiz),
          updatedAt: Value(jetzt),
        ),
      );
    }

    ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Bedarf erfasst');
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _terminWaehlen() async {
    final jetzt = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _termin ?? jetzt,
      firstDate: jetzt.subtract(const Duration(days: 30)),
      lastDate: jetzt.add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _termin = d);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final produkteAsync = ref.watch(_produkteProvider);
    final termin = _termin;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          // Kopf wie bei jedem Fenster der App: Titel in Blau, rechts ein
          // Kreuz. Vorher saß hier der Anfasser aus der Bottom-Sheet-Zeit.
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.bedarf == null
                      ? 'Bedarf hinzufügen'
                      : 'Bedarf bearbeiten',
                  style: theme.dialogTheme.titleTextStyle ??
                      theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                tooltip: 'Schließen ohne Speichern',
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Menge in Fertigware — die benötigte Rohware rechnet die '
            'Planung daraus zurück.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),

          // Artikelauswahl
          produkteAsync.when(
            data: (produkte) {
              final gewaehlt = _productId == null
                  ? null
                  : produkte.where((p) => p.id == _productId).firstOrNull;
              if (gewaehlt != null) {
                return Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text(gewaehlt.artikelbezeichnung),
                    subtitle: Text(gewaehlt.artikelnummer),
                    trailing: _ausAuftragsbestand
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Anderen Artikel wählen',
                            onPressed: () =>
                                setState(() => _productId = null),
                          ),
                  ),
                );
              }
              final q = _suche.text.trim().toLowerCase();
              final gefiltert = q.isEmpty
                  ? produkte
                  : produkte
                      .where(
                        (p) =>
                            p.artikelbezeichnung
                                .toLowerCase()
                                .contains(q) ||
                            p.artikelnummer.toLowerCase().contains(q),
                      )
                      .toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _suche,
                    decoration: const InputDecoration(
                      labelText: 'Artikel suchen',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  // Die Treffer in einer Fläche mit Rand — wie eine Liste
                  // der App, nicht frei im Fenster.
                  Container(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.3,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.colorScheme.outline),
                      borderRadius: AppMasse.ecken,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Material(
                      color: Colors.transparent,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: gefiltert.length,
                        itemBuilder: (context, i) {
                          final p = gefiltert[i];
                          return ListTile(
                            dense: true,
                            title: Text(p.artikelbezeichnung),
                            subtitle: Text(p.artikelnummer),
                            onTap: () => setState(() => _productId = p.id),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => HinweisBox(
              'Artikel konnten nicht geladen werden: ${fehlerText(e)}',
              art: StatusArt.fehler,
              auswaehlbar: true,
            ),
          ),

          const SizedBox(height: 16),
          TextField(
            controller: _menge,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Benötigte Menge (kg Fertigware)',
              suffixText: 'kg',
            ),
          ),
          const SizedBox(height: 14),

          // Termin — ein Feld wie das Datum beim Erfassen einer Produktion.
          InkWell(
            onTap: _terminWaehlen,
            borderRadius: AppMasse.ecken,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Termin',
                prefixIcon: const Icon(Icons.event),
                suffixIcon: termin == null
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Termin entfernen',
                        onPressed: () => setState(() => _termin = null),
                      ),
              ),
              child: Text(termin == null ? 'ohne Termin' : _datum(termin)),
            ),
          ),
          const SizedBox(height: 16),

          // Quelle — ein Planungsauftrag aus dem Auftragsbestand behält
          // seine Herkunft, sonst verlöre er die Verbindung zu den
          // Auftragszeilen.
          if (_ausAuftragsbestand)
            _AuftragsbestandHinweis(
              bezuege: AuftragsBezug.dekodiere(widget.bedarf?.auftragsZeilen),
            )
          else
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'bestellung', label: Text('Bestellung')),
                ButtonSegment(value: 'bestand', label: Text('Bestand')),
                ButtonSegment(value: 'sonstiges', label: Text('Sonstiges')),
              ],
              selected: {_quelle},
              onSelectionChanged: (s) => setState(() => _quelle = s.first),
              showSelectedIcon: false,
            ),
          const SizedBox(height: 12),

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Hohe Priorität'),
            subtitle: const Text('Wird in der Liste oben einsortiert'),
            value: _prioritaet > 0,
            onChanged: (v) => setState(() => _prioritaet = v ? 1 : 0),
          ),

          TextField(
            controller: _notizen,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Notizen (Kunde, Auftragsnummer …)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 20),

          // Knöpfe unten rechts wie in jedem Fenster der App.
          Row(
            children: [
              const Spacer(),
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: const Text('Abbrechen'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _busy ? null : _speichern,
                // Ohne feste Farbe: Der gesperrte Knopf ist hellgrau, ein
                // weißer Kreisel wäre darauf unsichtbar.
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save, size: 18),
                label: Text(_busy ? 'Speichern …' : 'Speichern'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Herkunft eines Planungsauftrags: welche Aufträge aus dem
/// Auftragsbestand er bündelt.
class _AuftragsbestandHinweis extends StatelessWidget {
  const _AuftragsbestandHinweis({required this.bezuege});

  final List<AuftragsBezug> bezuege;

  @override
  Widget build(BuildContext context) {
    final beschreibung = beschreibeBezuege(bezuege);
    return HinweisBox(
      'Planungsauftrag aus dem Auftragsbestand'
      '${beschreibung.isEmpty ? '' : ' · $beschreibung'}.\n'
      'Der Termin ist der späteste Produktionstag — der '
      'Planungsvorschlag plant nie danach. Wird der Bedarf '
      'gelöscht, sind die Aufträge im Auftragsbestand wieder offen.',
      icon: Icons.local_shipping_outlined,
    );
  }
}

/// Alle aktiven Artikel (für die Auswahl im Editor).
final _produkteProvider = FutureProvider<List<Product>>((ref) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.products)
        ..where((p) => p.deletedAt.isNull())
        ..orderBy([(p) => OrderingTerm.asc(p.artikelbezeichnung)]))
      .get();
});

// ---------------------------------------------------------------------------
// Formatierung
// ---------------------------------------------------------------------------

/// Ziffern gleich breit, damit Nummern und Mengen untereinander stehen.
const List<FontFeature> _ziffern = [FontFeature.tabularFigures()];

const _wochentage = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

String _zwei(int n) => n.toString().padLeft(2, '0');

/// „Mo 19.10."
String _tagKurz(DateTime d) =>
    '${_wochentage[d.weekday - 1]} ${_zwei(d.day)}.${_zwei(d.month)}.';

/// „19.10.2026"
String _datum(DateTime d) => '${_zwei(d.day)}.${_zwei(d.month)}.${d.year}';
