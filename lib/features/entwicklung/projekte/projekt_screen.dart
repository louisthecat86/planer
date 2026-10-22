// `show Value`: drift bringt eine eigene Klasse `Column` mit.
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/services/auto_backup_trigger.dart';
import '../../../core/theme/app_stil.dart';
import '../../../core/ui/ablage.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/fehler_text.dart';
import '../bericht/bericht_drucken.dart';
import '../daten/entwicklung_repository.dart';
import '../entwicklung_format.dart';
import '../freigabe/freigabe_ansicht.dart';
import '../haccp/haccp_ansicht.dart';
import '../haccp/prozess_ansicht.dart';
import '../rechenkern/naehrwert_rundung.dart';
import '../rezepturen/rezeptur_screen.dart' show TextFeld;
import '../rezepturen/rezepturen_ansicht.dart';
import '../spezifikation/spezifikation_dialog.dart';
import '../spezifikation/spezifikation_reiter.dart';
import 'datei_aktionen.dart' show dateiOeffnen;
import 'fliessdiagramm_dienst.dart';
import 'fliessdiagramme_dialog.dart';
import 'projekt_checkliste.dart';
import 'projekt_dateien.dart';
import 'projekt_modell.dart';
import 'projekt_repository.dart';
import 'projekt_verlauf.dart';

/// Die Reiter einer Projektseite — vorn der Verlauf mit dem Zeitstrahl:
/// Wer ein Projekt öffnet, sieht zuerst, wie es sich entwickelt hat (F21).
enum ProjektReiter {
  verlauf('Verlauf'),
  uebersicht('Übersicht'),
  prozess('Prozess'),
  haccp('HACCP'),
  sensorik('Sensorik'),
  spezifikation('Spezifikation'),
  dateien('Dateien');

  const ProjektReiter(this.label);

  final String label;
}

/// Speichert eine Änderung am Projekt; Fehler erscheinen unten.
Future<void> projektSpeichern(
  BuildContext context,
  WidgetRef ref,
  String id,
  EntwicklungProjekteCompanion daten,
) async {
  try {
    await ref.read(projektRepositoryProvider).projektAendern(id, daten);
    ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Projekt');
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Speichern fehlgeschlagen: ${fehlerText(e)}')),
      );
    }
  }
}

/// Ändert den Status und hält den Wechsel im Verlauf fest; Fehler
/// erscheinen unten.
Future<void> projektStatusAendern(
  BuildContext context,
  WidgetRef ref,
  String id,
  ProjektStatus neu,
) async {
  try {
    await ref.read(projektRepositoryProvider).statusAendern(id, neu);
    ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Projektstatus');
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Speichern fehlgeschlagen: ${fehlerText(e)}')),
      );
    }
  }
}

String? _oderNull(String t) => t.trim().isEmpty ? null : t.trim();

/// Ein Projekt: Verlauf, Übersicht, Prozess, HACCP, Sensorik,
/// Spezifikation und Dateien.
class ProjektScreen extends ConsumerWidget {
  const ProjektScreen({super.key, required this.projektId});

  final String projektId;

  Future<void> _umbenennen(
    BuildContext context,
    WidgetRef ref,
    EntwicklungsProjekt p,
  ) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(name: p.name),
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    await projektSpeichern(
      context,
      ref,
      p.id,
      EntwicklungProjekteCompanion(name: Value(name.trim())),
    );
  }

  Future<void> _loeschen(
    BuildContext context,
    WidgetRef ref,
    EntwicklungsProjekt p,
  ) async {
    final ja = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Projekt löschen?'),
        content: Text(
          '„${p.name}" wird mit seinem Verlauf gelöscht. Seine Rezepturen '
          'bleiben und stehen danach ohne Projekt in der Liste. Statt zu '
          'löschen kannst du ein fertiges Projekt auch archivieren.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ja != true) return;
    await ref.read(projektRepositoryProvider).projektLoeschen(p.id);
    ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Projekt');
    if (context.mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projekt = ref.watch(projektProvider(projektId));
    final p = projekt.valueOrNull;
    final kunde = p?.kunde?.trim();
    return DefaultTabController(
      length: ProjektReiter.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            p == null
                ? 'Projekt'
                : (kunde == null || kunde.isEmpty
                    ? p.name
                    : '${p.name} · $kunde'),
          ),
          actions: [
            if (p != null) ...[
              IconButton(
                tooltip: 'Spezifikation (Excel)',
                icon: const Icon(Icons.table_view_outlined),
                onPressed: () => spezifikationOeffnen(context, p),
              ),
              IconButton(
                tooltip: 'Projektbericht (PDF)',
                icon: const Icon(Icons.picture_as_pdf_outlined),
                onPressed: () => projektberichtDrucken(context, ref, p),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Umbenennen',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _umbenennen(context, ref, p),
              ),
              IconButton(
                tooltip: 'Projekt löschen',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _loeschen(context, ref, p),
              ),
            ],
            const SizedBox(width: 8),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final r in ProjektReiter.values) Tab(text: r.label),
            ],
          ),
        ),
        body: projekt.when(
          skipLoadingOnReload: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: HinweisBox(
              fehlerText(e),
              art: StatusArt.fehler,
              titel: 'Das Projekt ließ sich nicht laden',
              auswaehlbar: true,
            ),
          ),
          data: (p) => p == null || p.deletedAt != null
              ? const Center(
                  child: LeerHinweis('Dieses Projekt gibt es nicht mehr.'),
                )
              // Mails (auch direkt aus Outlook) und Dateien lassen sich auf
              // jeden Reiter ziehen — sie kommen in den Verlauf.
              : AblageZone(
                  hinweis: 'Mail oder Datei loslassen — kommt in den Verlauf',
                  onAbgelegt: (dateien) =>
                      projektAblage(context, ref, p.id, dateien),
                  child: TabBarView(
                    children: [
                      ProjektVerlauf(projekt: p),
                      ProjektUebersicht(projekt: p),
                      ProjektProzess(projekt: p),
                      ProjektHaccp(projekt: p),
                      ProjektSensorik(projekt: p),
                      ProjektSpezifikation(projekt: p),
                      ProjektDateien(projekt: p),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

/// Die Übersicht: Stammdaten, Ziele und Notizen links; Freigabe, Bild,
/// Rezepturen und Checklisten rechts.
class ProjektUebersicht extends StatelessWidget {
  const ProjektUebersicht({super.key, required this.projekt});

  final EntwicklungsProjekt projekt;

  @override
  Widget build(BuildContext context) {
    final links = <Widget>[
      ProjektStammdaten(projekt: projekt),
      const SizedBox(height: 16),
      ProjektZiele(projekt: projekt),
      const SizedBox(height: 16),
      _Notizen(projekt: projekt),
    ];
    final rechts = <Widget>[
      ProjektFreigabe(projekt: projekt),
      const SizedBox(height: 16),
      ProduktBild(projekt: projekt),
      const SizedBox(height: 16),
      ProjektRezepturen(projekt: projekt),
      const SizedBox(height: 16),
      ProjektCheckliste(projekt: projekt),
      const SizedBox(height: 16),
      ProjektCheckliste(projekt: projekt, etikett: true),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= 1000) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: links,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: rechts,
                  ),
                ),
              ],
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [...links, const SizedBox(height: 16), ...rechts],
        );
      },
    );
  }
}

/// Status, Kunde, Artikelnummer, Idee, Vereinbarungen, Fließdiagramm und
/// was neu ist.
class ProjektStammdaten extends ConsumerWidget {
  const ProjektStammdaten({super.key, required this.projekt});

  final EntwicklungsProjekt projekt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = projekt;
    void speichern(EntwicklungProjekteCompanion daten) =>
        projektSpeichern(context, ref, p.id, daten);
    final status = ProjektStatus.aus(p.status);
    final diagramme = ref.watch(fliessdiagrammeProvider).valueOrNull ??
        const <Fliessdiagramm>[];
    final fd = p.fliessdiagramm ?? '';
    final fdPdfs = ref.watch(fliessdiagrammFassungenProvider).valueOrNull?[fd];
    final pdf = fdPdfs?.firstOrNull;
    final fdWahl = <String, String>{
      '': '— keins —',
      for (final f in diagramme)
        f.id: f.bezeichnung == f.id ? f.id : '${f.id} · ${f.bezeichnung}',
      if (fd.isNotEmpty && !diagramme.any((f) => f.id == fd)) fd: fd,
    };
    const abstand = SizedBox(height: 10);
    return Bereich(
      titel: 'Stammdaten',
      icon: Icons.info_outline,
      innenAbstand: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<ProjektStatus>(
                  key: ValueKey('status-${p.status}'),
                  initialValue: status,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: [
                    for (final s in ProjektStatus.values)
                      DropdownMenuItem(value: s, child: Text(s.label)),
                  ],
                  onChanged: (s) {
                    if (s != null && s != status) {
                      projektStatusAendern(context, ref, p.id, s);
                    }
                  },
                ),
              ),
              SizedBox(
                width: 240,
                child: TextFeld(
                  wert: p.kunde ?? '',
                  label: 'Kunde',
                  onFertig: (t) => speichern(
                    EntwicklungProjekteCompanion(kunde: Value(_oderNull(t))),
                  ),
                ),
              ),
              SizedBox(
                width: 160,
                child: TextFeld(
                  wert: p.artikelnummer ?? '',
                  label: 'Artikelnummer',
                  onFertig: (t) => speichern(
                    EntwicklungProjekteCompanion(
                      artikelnummer: Value(_oderNull(t)),
                    ),
                  ),
                ),
              ),
            ],
          ),
          abstand,
          TextFeld(
            wert: p.produktidee ?? '',
            label: 'Produktidee',
            mehrzeilig: true,
            onFertig: (t) => speichern(
              EntwicklungProjekteCompanion(produktidee: Value(_oderNull(t))),
            ),
          ),
          abstand,
          TextFeld(
            wert: p.kundenvereinbarungen ?? '',
            label: 'Kundenvereinbarungen',
            hinweis: 'Besondere Absprachen, etwa „ohne Geschmacksverstärker"',
            mehrzeilig: true,
            onFertig: (t) => speichern(
              EntwicklungProjekteCompanion(
                kundenvereinbarungen: Value(_oderNull(t)),
              ),
            ),
          ),
          abstand,
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('fd-$fd-${fdWahl.length}-${fdWahl[fd]}'),
                  initialValue: fd,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Fließdiagramm',
                    helperText: fdPdfHinweis(fdPdfs),
                  ),
                  items: [
                    for (final MapEntry(:key, :value) in fdWahl.entries)
                      DropdownMenuItem(
                        value: key,
                        child: Text(value, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (wahl) {
                    if (wahl == null || wahl == fd) return;
                    speichern(
                      EntwicklungProjekteCompanion(
                        fliessdiagramm: Value(wahl.isEmpty ? null : wahl),
                      ),
                    );
                  },
                ),
              ),
              IconButton(
                tooltip: fd.isEmpty
                    ? 'Kein Fließdiagramm gewählt'
                    : pdf == null
                        ? 'Zu $fd gibt es noch kein PDF'
                        : 'Fließdiagramm öffnen',
                icon: const Icon(Icons.picture_as_pdf_outlined),
                onPressed: pdf == null
                    ? null
                    : () => dateiOeffnen(context, ref, pdf.datei),
              ),
              IconButton(
                tooltip: 'Fließdiagramme pflegen',
                icon: const Icon(Icons.edit_note),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const FliessdiagrammeDialog(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: p.neuerProzess,
            title: const Text('Neuer Prozess'),
            subtitle: const Text(
              'Für einen neuen Ablauf gehört eine Gefahrenanalyse dazu.',
            ),
            onChanged: (v) => speichern(
              EntwicklungProjekteCompanion(neuerProzess: Value(v ?? false)),
            ),
          ),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: p.neueZutaten,
            title: const Text('Neue Zutaten'),
            subtitle: const Text(
              'Rohstoffe, die die Qualitätssicherung noch freigeben muss.',
            ),
            onChanged: (v) => speichern(
              EntwicklungProjekteCompanion(neueZutaten: Value(v ?? false)),
            ),
          ),
          if (p.neueZutaten) ...[
            const SizedBox(height: 4),
            TextFeld(
              wert: p.neueZutatenDetails ?? '',
              label: 'Welche Zutaten?',
              mehrzeilig: true,
              onFertig: (t) => speichern(
                EntwicklungProjekteCompanion(
                  neueZutatenDetails: Value(_oderNull(t)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Die Ziele des Projekts — und wie die neueste Rezeptur dazu steht.
class ProjektZiele extends ConsumerWidget {
  const ProjektZiele({super.key, required this.projekt});

  final EntwicklungsProjekt projekt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = projekt;

    Widget feld(
      String label,
      double? wert,
      EntwicklungProjekteCompanion Function(double? neu) daten,
    ) =>
        SizedBox(
          width: 170,
          child: TextFeld(
            wert: feldText(wert),
            label: label,
            onFertig: (t) {
              final zahl = zahlAus(t);
              if (t.trim().isNotEmpty && zahl == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('„$t" ist keine Zahl.')),
                );
                return;
              }
              projektSpeichern(context, ref, p.id, daten(zahl));
            },
          ),
        );

    // Die neueste Rezeptur des Projekts zum Vergleich.
    final rezepturen = ref.watch(projektRezepturenProvider(p.id)).valueOrNull ??
        const <Rezeptur>[];
    final versionen = ref.watch(alleVersionenProvider).valueOrNull ??
        const <RezepturVersion>[];
    RezepturVersion? neueste;
    for (final v in versionen) {
      if (!rezepturen.any((r) => r.id == v.rezepturId)) continue;
      if (neueste == null || v.updatedAt.isAfter(neueste.updatedAt)) {
        neueste = v;
      }
    }
    final ergebnis = neueste == null
        ? null
        : ref.watch(rezepturErgebnisProvider(neueste.id)).valueOrNull;
    final fett = ergebnis?.je100g.fett;
    final eiweiss = ergebnis?.je100g.eiweiss;

    final vergleich = <Widget>[];
    if (ergebnis != null) {
      final zielFett = p.zielFett;
      final zielEiweiss = p.zielEiweiss;
      String wert(Naehrstoff s, double? w) =>
          w == null ? '—' : '${naehrwertGerundet(s, w)} g';
      vergleich.addAll([
        const SizedBox(height: 10),
        Text(
          'Neuester Rezepturstand je 100 g: Fett '
          '${wert(Naehrstoff.fett, fett)}, Eiweiß '
          '${wert(Naehrstoff.eiweiss, eiweiss)}',
          style: theme.textTheme.bodySmall,
        ),
        if (zielFett != null && fett != null && fett > zielFett + 1e-9) ...[
          const SizedBox(height: 6),
          HinweisBox(
            'Fett liegt über dem Ziel von ${prozentText(zielFett)}.',
            art: StatusArt.warnung,
          ),
        ],
        if (zielEiweiss != null &&
            eiweiss != null &&
            eiweiss < zielEiweiss - 1e-9) ...[
          const SizedBox(height: 6),
          HinweisBox(
            'Eiweiß liegt unter dem Ziel von ${prozentText(zielEiweiss)}.',
            art: StatusArt.warnung,
          ),
        ],
      ]);
    }

    return Bereich(
      titel: 'Ziele',
      icon: Icons.flag_outlined,
      innenAbstand: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              feld(
                'Fett höchstens (%)',
                p.zielFett,
                (neu) => EntwicklungProjekteCompanion(zielFett: Value(neu)),
              ),
              feld(
                'Eiweiß mindestens (%)',
                p.zielEiweiss,
                (neu) => EntwicklungProjekteCompanion(zielEiweiss: Value(neu)),
              ),
              feld(
                'aw-Wert höchstens',
                p.grenzeAw,
                (neu) => EntwicklungProjekteCompanion(grenzeAw: Value(neu)),
              ),
            ],
          ),
          ...vergleich,
        ],
      ),
    );
  }
}

class _Notizen extends ConsumerWidget {
  const _Notizen({required this.projekt});

  final EntwicklungsProjekt projekt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Bereich(
      titel: 'Notizen',
      icon: Icons.sticky_note_2_outlined,
      innenAbstand: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: TextFeld(
        wert: projekt.notizen ?? '',
        label: 'Notizen',
        mehrzeilig: true,
        onFertig: (t) => projektSpeichern(
          context,
          ref,
          projekt.id,
          EntwicklungProjekteCompanion(notizen: Value(_oderNull(t))),
        ),
      ),
    );
  }
}

/// Die Projekt-Checkliste — sechs Punkte rechnet die App selbst, Etikett
/// und Navision hakt man ab (F25) — oder die Etiketten-Checkliste.
class ProjektCheckliste extends ConsumerWidget {
  const ProjektCheckliste({
    super.key,
    required this.projekt,
    this.etikett = false,
  });

  final EntwicklungsProjekt projekt;

  /// true: die Pflichtangaben des Etiketts, sonst die Projekt-Checkliste.
  final bool etikett;

  Future<void> _haken(
    WidgetRef ref,
    String schluessel, {
    required bool erledigt,
  }) async {
    await ref.read(projektRepositoryProvider).checklistePunkt(
          projekt.id,
          schluessel: schluessel,
          erledigt: erledigt,
          etikett: etikett,
        );
    ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Checkliste');
  }

  Widget _hakenZeile(
    WidgetRef ref,
    CheckPunkt c, {
    required bool erledigt,
    String? untertitel,
  }) =>
      CheckboxListTile(
        key: ValueKey('check-${c.schluessel}'),
        dense: true,
        visualDensity: VisualDensity.compact,
        controlAffinity: ListTileControlAffinity.leading,
        value: erledigt,
        title: Text(c.label),
        subtitle: untertitel == null ? null : Text(untertitel),
        onChanged: (v) => _haken(ref, c.schluessel, erledigt: v ?? false),
      );

  /// Wohin ein Punkt führt: in den Reiter, in dem er entsteht, oder in die
  /// Rezeptur — null, wenn er nirgendwohin führt.
  VoidCallback? _ziel(BuildContext context, CheckStand c) {
    void reiter(ProjektReiter r) =>
        DefaultTabController.maybeOf(context)?.animateTo(r.index);
    final rezeptur = c.rezepturId;
    return switch (c.punkt.schluessel) {
      'prozessErstellt' => () => reiter(ProjektReiter.prozess),
      'sensorikErstellt' => () => reiter(ProjektReiter.sensorik),
      'spezifikationErstellt' => () => reiter(ProjektReiter.spezifikation),
      'rezepturErstellt' || 'naehrwerteErstellt' when rezeptur != null => () =>
          oeffneRezeptur(context, rezeptur),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (etikett) {
      final erledigt = checklisteAus(projekt.etikettCheckliste);
      final anzahl = kEtikettCheckliste
          .where((c) => erledigt.contains(c.schluessel))
          .length;
      return Bereich(
        titel: 'Etikett (LMIV)',
        icon: Icons.label_outline,
        untertitel: '$anzahl von ${kEtikettCheckliste.length}',
        innenAbstand: const EdgeInsets.fromLTRB(4, 2, 4, 6),
        child: Column(
          children: [
            for (final c in kEtikettCheckliste)
              _hakenZeile(ref, c, erledigt: erledigt.contains(c.schluessel)),
          ],
        ),
      );
    }

    final theme = Theme.of(context);
    final rezepturen = ref.watch(projektRezepturenProvider(projekt.id));
    final versionen = ref.watch(alleVersionenProvider);
    final r = rezepturen.valueOrNull;
    final v = versionen.valueOrNull;
    final stand = r == null || v == null
        ? null
        : projektCheckStand(projekt: projekt, rezepturen: r, versionen: v);
    final Widget inhalt;
    if (stand != null) {
      inhalt = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final c in stand.punkte)
            if (c.vonHand)
              _hakenZeile(
                ref,
                c.punkt,
                erledigt: c.erledigt,
                untertitel: 'von Hand',
              )
            else
              _AutoPunkt(stand: c, onTap: _ziel(context, c)),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
            child: Text(
              'Die App hakt die Punkte selbst ab, sobald das Projekt sie '
              'erfüllt — von Hand nur Etikett und Navision.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    } else if (rezepturen.hasError || versionen.hasError) {
      inhalt = Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Die Checkliste ließ sich nicht rechnen: '
          '${fehlerText(rezepturen.error ?? versionen.error ?? '')}',
        ),
      );
    } else {
      inhalt = const Padding(
        padding: EdgeInsets.all(12),
        child: LinearProgressIndicator(),
      );
    }
    return Bereich(
      titel: 'Checkliste',
      icon: Icons.checklist,
      untertitel: stand?.text,
      innenAbstand: const EdgeInsets.fromLTRB(4, 2, 4, 6),
      child: inhalt,
    );
  }
}

/// Ein Punkt, den die App selbst abhakt: Haken oder Kreis, dazu woran sie
/// es sieht oder was noch fehlt; antippen führt dorthin, wo er entsteht.
class _AutoPunkt extends StatelessWidget {
  const _AutoPunkt({required this.stand, this.onTap});

  final CheckStand stand;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = stand.text;
    return ListTile(
      key: ValueKey('check-${stand.punkt.schluessel}'),
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: Tooltip(
        message: stand.erledigt
            ? 'Erledigt — die App hat es abgehakt'
            : 'Offen — die App hakt es ab, sobald es erfüllt ist',
        child: Icon(
          stand.erledigt ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 22,
          color: stand.erledigt
              ? AppFarben.von(context).ok
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      title: Text(stand.punkt.label),
      subtitle: text == null ? null : Text(text),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right, size: 18),
      onTap: onTap,
    );
  }
}

/// Die Rezepturen des Projekts mit ihrem neuesten Stand.
class ProjektRezepturen extends ConsumerWidget {
  const ProjektRezepturen({super.key, required this.projekt});

  final EntwicklungsProjekt projekt;

  Future<void> _neu(BuildContext context) async {
    final id = await showDialog<String>(
      context: context,
      builder: (_) => NeueRezepturDialog(
        projektId: projekt.id,
        vorschlag: projekt.name,
      ),
    );
    if (id == null || !context.mounted) return;
    await oeffneRezeptur(context, id);
  }

  Future<void> _zuordnen(BuildContext context, WidgetRef ref) async {
    final alle = await ref.read(rezepturenProvider.future);
    if (!context.mounted) return;
    final frei = alle.where((r) => r.projektId == null).toList();
    final id = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Rezeptur zuordnen'),
        children: [
          if (frei.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Alle Rezepturen gehören schon zu einem Projekt.'),
            ),
          for (final r in frei)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(r.id),
              child: Text(
                r.artikelnummer == null
                    ? r.name
                    : '${r.name} (${r.artikelnummer})',
              ),
            ),
        ],
      ),
    );
    if (id == null) return;
    await ref.read(entwicklungRepositoryProvider).rezepturAendern(
          id,
          EntwicklungRezepturenCompanion(projektId: Value(projekt.id)),
        );
    ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Rezeptur');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final rezepturen = ref.watch(projektRezepturenProvider(projekt.id))
            .valueOrNull ??
        const <Rezeptur>[];
    final versionen = ref.watch(alleVersionenProvider).valueOrNull ??
        const <RezepturVersion>[];
    RezepturVersion? neuesteVon(String id) {
      RezepturVersion? n;
      for (final v in versionen) {
        if (v.rezepturId == id && (n == null || v.nummer > n.nummer)) n = v;
      }
      return n;
    }

    return Bereich(
      titel: 'Rezepturen',
      icon: Icons.menu_book_outlined,
      untertitel: '${rezepturen.length}',
      aktionen: [
        IconButton(
          tooltip: 'Vorhandene Rezeptur zuordnen',
          icon: const Icon(Icons.link, size: 18),
          onPressed: () => _zuordnen(context, ref),
        ),
        IconButton(
          tooltip: 'Neue Rezeptur',
          icon: const Icon(Icons.add, size: 18),
          onPressed: () => _neu(context),
        ),
      ],
      child: rezepturen.isEmpty
          ? const LeerHinweis(
              'Noch keine Rezeptur.',
              icon: Icons.menu_book_outlined,
            )
          : Column(
              children: [
                for (final r in rezepturen)
                  InkWell(
                    onTap: () => oeffneRezeptur(context, r.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              r.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (neuesteVon(r.id) case final v?)
                            StandMarke(version: v),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Die sensorische Beschreibung des Produkts.
class ProjektSensorik extends ConsumerWidget {
  const ProjektSensorik({super.key, required this.projekt});

  final EntwicklungsProjekt projekt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Sensorik.aus(projekt.sensorik);
    void speichern(Sensorik neu) => projektSpeichern(
          context,
          ref,
          projekt.id,
          EntwicklungProjekteCompanion(sensorik: Value(neu.alsJson())),
        );
    const abstand = SizedBox(height: 10);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Bereich(
              titel: 'Sensorik',
              icon: Icons.restaurant_menu,
              untertitel: 'das fertige Produkt',
              innenAbstand: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFeld(
                    wert: s.aussehen,
                    label: 'Aussehen',
                    mehrzeilig: true,
                    onFertig: (t) => speichern(s.kopie(aussehen: t)),
                  ),
                  abstand,
                  TextFeld(
                    wert: s.geruch,
                    label: 'Geruch',
                    mehrzeilig: true,
                    onFertig: (t) => speichern(s.kopie(geruch: t)),
                  ),
                  abstand,
                  TextFeld(
                    wert: s.geschmack,
                    label: 'Geschmack',
                    mehrzeilig: true,
                    onFertig: (t) => speichern(s.kopie(geschmack: t)),
                  ),
                  abstand,
                  TextFeld(
                    wert: s.konsistenz,
                    label: 'Konsistenz',
                    mehrzeilig: true,
                    onFertig: (t) => speichern(s.kopie(konsistenz: t)),
                  ),
                  abstand,
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      SizedBox(
                        width: 180,
                        child: TextFeld(
                          wert: s.laenge,
                          label: 'Länge',
                          onFertig: (t) => speichern(s.kopie(laenge: t)),
                        ),
                      ),
                      SizedBox(
                        width: 180,
                        child: TextFeld(
                          wert: s.durchmesser,
                          label: 'Durchmesser',
                          onFertig: (t) => speichern(s.kopie(durchmesser: t)),
                        ),
                      ),
                      SizedBox(
                        width: 180,
                        child: TextFeld(
                          wert: s.gewicht,
                          label: 'Stückgewicht',
                          onFertig: (t) => speichern(s.kopie(gewicht: t)),
                        ),
                      ),
                    ],
                  ),
                  abstand,
                  TextFeld(
                    wert: s.zubereitung,
                    label: 'Zubereitung',
                    mehrzeilig: true,
                    onFertig: (t) => speichern(s.kopie(zubereitung: t)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.name});

  final String name;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Projekt umbenennen'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, minWidth: 320),
        child: TextField(
          controller: _name,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Projektname'),
          onSubmitted: (t) => Navigator.of(context).pop(t),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_name.text),
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}
