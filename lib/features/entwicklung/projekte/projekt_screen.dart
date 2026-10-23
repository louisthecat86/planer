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
import '../etikett/etikett_dialog.dart';
import '../freigabe/freigabe_ansicht.dart';
import '../haccp/herstellung_reiter.dart';
import '../rechenkern/naehrwert_rundung.dart';
import '../rezepturen/rezeptur_screen.dart' show TextFeld;
import '../rezepturen/rezepturen_ansicht.dart';
import '../spezifikation/spezifikation_dialog.dart';
import 'entwicklungsstrang.dart' show phaseVorDemArchiv;
import 'fliessdiagramme_dialog.dart';
import 'produkt_foto.dart';
import 'produkt_reiter.dart';
import 'projekt_checkliste.dart';
import 'projekt_dateien.dart';
import 'projekt_kopf.dart';
import 'projekt_modell.dart';
import 'projekt_repository.dart';
import 'projekt_verlauf.dart';

/// Die Reiter einer Projektseite — vorn der Verlauf mit dem Zeitstrahl:
/// Wer ein Projekt öffnet, sieht zuerst, wie es sich entwickelt hat (F21).
/// „Produkt" bündelt Sensorik mit Produktfoto, Angaben, Verpackung und
/// Spezifikation, „Herstellung" Prozess und HACCP (F26).
enum ProjektReiter {
  verlauf('Verlauf'),
  uebersicht('Übersicht'),
  produkt('Produkt'),
  herstellung('Herstellung'),
  dateien('Dateien');

  const ProjektReiter(this.label);

  final String label;
}

/// Springt auf der Projektseite zum Reiter [r].
void projektReiterZeigen(BuildContext context, ProjektReiter r) =>
    DefaultTabController.maybeOf(context)?.animateTo(r.index);

/// Wohin ein Punkt der Checkliste führt: in den Reiter, in dem er
/// entsteht, oder in die Rezeptur — null, wenn er in der Übersicht selbst
/// erledigt wird (Etikett, Freigabe, Navision).
VoidCallback? checkpunktZiel(BuildContext context, CheckStand c) {
  final rezeptur = c.rezepturId;
  return switch (c.punkt.schluessel) {
    'prozessErstellt' => () =>
        projektReiterZeigen(context, ProjektReiter.herstellung),
    'sensorikErstellt' ||
    'produktfotoHinterlegt' ||
    'spezifikationErstellt' =>
      () => projektReiterZeigen(context, ProjektReiter.produkt),
    'rezepturErstellt' || 'naehrwerteErstellt' when rezeptur != null => () =>
        oeffneRezeptur(context, rezeptur),
    _ => null,
  };
}

/// Führt zu einem Punkt der Checkliste — ohne eigenes Ziel in die
/// Übersicht, wo er abgehakt oder freigegeben wird.
void checkpunktOeffnen(BuildContext context, CheckStand c) {
  final ziel = checkpunktZiel(context, c);
  if (ziel != null) {
    ziel();
  } else {
    projektReiterZeigen(context, ProjektReiter.uebersicht);
  }
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

/// Ein Projekt: Verlauf, Übersicht, Produkt, Herstellung und Dateien.
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

  /// Das Etikett des Stands, um den es gerade geht: des freigegebenen,
  /// sonst des zuletzt abgeschlossenen, sonst des neuesten Entwurfs.
  void _etikett(BuildContext context, WidgetRef ref, EntwicklungsProjekt p) {
    final rezepturen =
        ref.read(projektRezepturenProvider(p.id)).valueOrNull ?? const [];
    final ids = {for (final r in rezepturen) r.id};
    final staende = [
      for (final v in ref.read(alleVersionenProvider).valueOrNull ??
          const <RezepturVersion>[])
        if (ids.contains(v.rezepturId)) v,
    ];
    DateTime zeit(RezepturVersion v) => v.abgeschlossenAm ?? v.updatedAt;
    final abgeschlossen = staende
        .where((v) => v.status == VersionStatus.abgeschlossen)
        .toList()
      ..sort((a, b) => zeit(b).compareTo(zeit(a)));
    final entwuerfe = staende
        .where((v) => v.status != VersionStatus.abgeschlossen)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final stand =
        staende.where((v) => v.id == p.freigabeVersionId).firstOrNull ??
            abgeschlossen.firstOrNull ??
            entwuerfe.firstOrNull;
    if (stand == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Noch keine Rezeptur — in der Übersicht unter „Rezepturen" '
            'anlegen.',
          ),
        ),
      );
      return;
    }
    etikettZeigen(context, stand.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projekt = ref.watch(projektProvider(projektId));
    final p = projekt.valueOrNull;
    final kunde = p?.kunde?.trim();
    final theme = Theme.of(context);
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
              PopupMenuButton<VoidCallback>(
                key: const ValueKey('projekt-erstellen'),
                tooltip: 'Spezifikation, Etikett oder Projektbericht',
                onSelected: (aktion) => aktion(),
                itemBuilder: (_) => [
                  // Sprache, Stand und Vorlage wählt man im Fenster.
                  PopupMenuItem(
                    value: () => spezifikationOeffnen(context, p),
                    child: const ListTile(
                      leading: Icon(Icons.table_view_outlined),
                      title: Text('Spezifikation…'),
                    ),
                  ),
                  PopupMenuItem(
                    value: () => _etikett(context, ref, p),
                    child: const ListTile(
                      leading: Icon(Icons.label_outline),
                      title: Text('Etikett…'),
                    ),
                  ),
                  PopupMenuItem(
                    value: () => projektberichtDrucken(context, ref, p),
                    child: const ListTile(
                      leading: Icon(Icons.picture_as_pdf_outlined),
                      title: Text('Projektbericht (PDF)…'),
                    ),
                  ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.file_open_outlined, size: 20),
                      const SizedBox(width: 6),
                      Text('Erstellen', style: theme.textTheme.labelLarge),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ),
              PopupMenuButton<VoidCallback>(
                key: const ValueKey('projekt-mehr'),
                tooltip: 'Umbenennen, archivieren oder löschen',
                onSelected: (aktion) => aktion(),
                itemBuilder: (_) {
                  final archiviert =
                      ProjektStatus.aus(p.status) == ProjektStatus.archiviert;
                  return [
                    PopupMenuItem(
                      value: () => _umbenennen(context, ref, p),
                      child: const ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Umbenennen…'),
                      ),
                    ),
                    PopupMenuItem(
                      value: () => phaseWechseln(
                        context,
                        ref,
                        p,
                        archiviert
                            ? phaseVorDemArchiv(
                                ref
                                        .read(projektEintraegeProvider(p.id))
                                        .valueOrNull ??
                                    const [],
                              )
                            : ProjektStatus.archiviert,
                      ),
                      child: ListTile(
                        leading: Icon(
                          archiviert
                              ? Icons.unarchive_outlined
                              : Icons.archive_outlined,
                        ),
                        title: Text(
                          archiviert ? 'Wieder aufnehmen…' : 'Archivieren…',
                        ),
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: () => _loeschen(context, ref, p),
                      child: const ListTile(
                        leading: Icon(Icons.delete_outline),
                        title: Text('Projekt löschen…'),
                      ),
                    ),
                  ];
                },
              ),
            ],
            const SizedBox(width: 8),
          ],
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
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Auf jedem Reiter: Phase, Fortschritt, was als Nächstes
                    // kommt.
                    ProjektKopf(projekt: p),
                    Material(
                      color: theme.colorScheme.surface,
                      child: TabBar(
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        tabs: [
                          for (final r in ProjektReiter.values)
                            Tab(text: r.label),
                        ],
                      ),
                    ),
                    // Mails (auch direkt aus Outlook) und Dateien lassen sich
                    // auf jeden Reiter ziehen — sie kommen in den Verlauf.
                    Expanded(
                      child: AblageZone(
                        hinweis:
                            'Mail oder Datei loslassen — kommt in den Verlauf',
                        onAbgelegt: (dateien) =>
                            projektAblage(context, ref, p.id, dateien),
                        child: TabBarView(
                          children: [
                            ProjektVerlauf(projekt: p),
                            ProjektUebersicht(projekt: p),
                            ProjektProdukt(projekt: p),
                            ProjektHerstellung(projekt: p),
                            ProjektDateien(projekt: p),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Die Übersicht: Stammdaten, Ziele und Notizen links; Freigabe,
/// Produktfoto (klein — gepflegt wird es im Reiter „Produkt"), Rezepturen
/// und die Checkliste rechts.
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
      ProduktFotoUebersicht(projekt: projekt),
      const SizedBox(height: 16),
      ProjektRezepturen(projekt: projekt),
      const SizedBox(height: 16),
      ProjektCheckliste(projekt: projekt),
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

/// Kunde, Artikelnummer, Idee, Vereinbarungen, Fließdiagramm und was neu
/// ist.
class ProjektStammdaten extends ConsumerWidget {
  const ProjektStammdaten({super.key, required this.projekt});

  final EntwicklungsProjekt projekt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = projekt;
    void speichern(EntwicklungProjekteCompanion daten) =>
        projektSpeichern(context, ref, p.id, daten);
    final diagramme = ref.watch(fliessdiagrammeProvider).valueOrNull ??
        const <Fliessdiagramm>[];
    final fd = p.fliessdiagramm ?? '';
    final fdWahl = <String, String>{
      '': '— keins —',
      for (final f in diagramme) f.id: fdText(f.id, bezeichnung: f.bezeichnung),
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
                  key: const ValueKey('stamm-artikelnummer'),
                  wert: p.artikelnummer ?? '',
                  label: 'Artikelnummer',
                  // Nach der Freigabe gilt die Nummer des Artikels.
                  bearbeitbar: p.artikelId == null,
                  hinweis: p.artikelId == null ? null : 'vom Artikel',
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
              // Tippen sucht in Kennung und Bezeichnung.
              Expanded(
                child: DropdownMenu<String>(
                  key: ValueKey('fd-$fd-${fdWahl.length}-${fdWahl[fd]}'),
                  initialSelection: fd,
                  expandedInsets: EdgeInsets.zero,
                  enableFilter: true,
                  requestFocusOnTap: true,
                  menuHeight: 360,
                  label: const Text('Fließdiagramm'),
                  helperText: diagramme.isEmpty
                      ? 'Noch keine Liste — rechts daneben anlegen'
                      : null,
                  dropdownMenuEntries: [
                    for (final MapEntry(:key, :value) in fdWahl.entries)
                      DropdownMenuEntry(value: key, label: value),
                  ],
                  onSelected: (wahl) {
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
                tooltip: 'Liste der Fließdiagramme bearbeiten',
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

/// Die Projekt-Checkliste: Acht Punkte rechnet die App selbst — das
/// Etikett aus seinen Pflichtangaben, die man darunter abhakt (F28) —,
/// Navision hakt man von Hand ab (F25). Das Produktfoto lässt sich
/// zurückstellen, solange es keins gibt (F37).
class ProjektCheckliste extends ConsumerWidget {
  const ProjektCheckliste({super.key, required this.projekt});

  final EntwicklungsProjekt projekt;

  Future<void> _haken(
    WidgetRef ref,
    String schluessel, {
    required bool erledigt,
  }) async {
    await ref.read(projektRepositoryProvider).checklistePunkt(
          projekt.id,
          schluessel: schluessel,
          erledigt: erledigt,
        );
    ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Checkliste');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            if (c.punkt.schluessel == 'etikettErstellt')
              _EtikettPunkt(
                projekt: projekt,
                stand: c,
                // Ist das Etikett als Nächstes dran, steht die Liste offen.
                aufgeklappt:
                    stand.naechster?.punkt.schluessel == 'etikettErstellt',
              )
            else if (c.vonHand)
              CheckboxListTile(
                key: ValueKey('check-${c.punkt.schluessel}'),
                dense: true,
                visualDensity: VisualDensity.compact,
                controlAffinity: ListTileControlAffinity.leading,
                value: c.erledigt,
                title: Text(c.punkt.label),
                subtitle: const Text('von Hand'),
                onChanged: (neu) =>
                    _haken(ref, c.punkt.schluessel, erledigt: neu ?? false),
              )
            else
              _AutoPunkt(stand: c, onTap: checkpunktZiel(context, c)),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
            child: Text(
              'Die App hakt die Punkte selbst ab, sobald das Projekt sie '
              'erfüllt. Beim Etikett hakst du die Pflichtangaben ab, '
              'Navision von Hand. Ein fehlendes Produktfoto lässt sich im '
              'Reiter „Produkt" zurückstellen.',
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

/// Haken oder Kreis vor einem Punkt, den die App abhakt — eine Uhr, wenn
/// er zurückgestellt ist.
class _CheckSymbol extends StatelessWidget {
  const _CheckSymbol({
    required this.erledigt,
    required this.hinweis,
    this.zurueckgestellt = false,
  });

  final bool erledigt;
  final String hinweis;
  final bool zurueckgestellt;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: hinweis,
      child: Icon(
        erledigt
            ? Icons.check_circle
            : (zurueckgestellt ? Icons.schedule : Icons.radio_button_unchecked),
        size: 22,
        color: erledigt
            ? AppFarben.von(context).ok
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
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
    final text = stand.text;
    return ListTile(
      key: ValueKey('check-${stand.punkt.schluessel}'),
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: _CheckSymbol(
        erledigt: stand.erledigt,
        zurueckgestellt: stand.zurueckgestellt,
        hinweis: stand.erledigt
            ? 'Erledigt — die App hat es abgehakt'
            : stand.zurueckgestellt
                ? 'Zurückgestellt — „Als Nächstes" geht weiter'
                : 'Offen — die App hakt es ab, sobald es erfüllt ist',
      ),
      title: Text(stand.punkt.label),
      subtitle: text == null ? null : Text(text),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right, size: 18),
      onTap: onTap,
    );
  }
}

/// „Etikett erstellt" mit den Pflichtangaben nach LMIV zum Aufklappen
/// (F28): erledigt, sobald jede abgehakt ist oder nicht zutrifft.
class _EtikettPunkt extends ConsumerWidget {
  const _EtikettPunkt({
    required this.projekt,
    required this.stand,
    this.aufgeklappt = false,
  });

  final EntwicklungsProjekt projekt;
  final CheckStand stand;

  /// Aufgeklappt beginnen.
  final bool aufgeklappt;

  Future<void> _setze(WidgetRef ref, String schluessel, LmivStand neu) async {
    await ref.read(projektRepositoryProvider).lmivPunkt(
          projekt.id,
          schluessel: schluessel,
          stand: neu,
        );
    ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Etikett');
  }

  Future<void> _alterHakenWeg(WidgetRef ref) async {
    await ref.read(projektRepositoryProvider).checklistePunkt(
          projekt.id,
          schluessel: 'etikettErstellt',
          erledigt: false,
        );
    ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Checkliste');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final lmiv = lmivAus(projekt.etikettCheckliste);
    final alleGeprueft = kEtikettCheckliste
        .every((l) => lmivStand(lmiv, l.schluessel).geprueft);
    // Vor F28 von Hand abgehakt: Das zählt, bis man den Haken zurücknimmt.
    final alterHaken = !alleGeprueft &&
        checklisteAus(projekt.checkliste).contains('etikettErstellt');
    final text = stand.text;
    return ExpansionTile(
      key: const ValueKey('check-etikettErstellt'),
      dense: true,
      visualDensity: VisualDensity.compact,
      initiallyExpanded: aufgeklappt,
      shape: const Border(),
      collapsedShape: const Border(),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      leading: _CheckSymbol(
        erledigt: stand.erledigt,
        hinweis: 'Erledigt, sobald jede Pflichtangabe abgehakt ist oder '
            'nicht zutrifft',
      ),
      title: Text(stand.punkt.label),
      subtitle: text == null ? null : Text(text),
      children: [
        for (final l in kEtikettCheckliste)
          _LmivZeile(
            punkt: l,
            stand: lmivStand(lmiv, l.schluessel),
            onAendern: (neu) => _setze(ref, l.schluessel, neu),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
          child: Text(
            'Abhaken, was auf dem Etikett steht — „trifft nicht zu", wenn '
            'eine Angabe für dieses Produkt nicht gilt, etwa die '
            'Schutzatmosphäre bei Vakuum.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (alterHaken)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('etikett-alter-haken'),
              onPressed: () => _alterHakenWeg(ref),
              icon: const Icon(Icons.undo, size: 16),
              label: const Text('Früheren Haken zurücknehmen'),
            ),
          ),
      ],
    );
  }
}

/// Eine Pflichtangabe des Etiketts: abhaken oder „trifft nicht zu".
class _LmivZeile extends StatelessWidget {
  const _LmivZeile({
    required this.punkt,
    required this.stand,
    required this.onAendern,
  });

  final CheckPunkt punkt;
  final LmivStand stand;
  final ValueChanged<LmivStand> onAendern;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final erledigt = stand == LmivStand.erledigt;
    final nz = stand == LmivStand.trifftNichtZu;
    void haken() =>
        onAendern(erledigt ? LmivStand.offen : LmivStand.erledigt);
    return Row(
      children: [
        Expanded(
          child: InkWell(
            borderRadius: AppMasse.ecken,
            onTap: haken,
            child: Row(
              children: [
                Checkbox(
                  key: ValueKey('lmiv-${punkt.schluessel}'),
                  value: erledigt,
                  visualDensity: VisualDensity.compact,
                  onChanged: (_) => haken(),
                ),
                Expanded(
                  child: Text(
                    punkt.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: nz ? theme.colorScheme.onSurfaceVariant : null,
                      decoration: nz ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        FilterChip(
          key: ValueKey('lmiv-nz-${punkt.schluessel}'),
          label: const Text('trifft nicht zu'),
          selected: nz,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onSelected: (an) =>
              onAendern(an ? LmivStand.trifftNichtZu : LmivStand.offen),
        ),
      ],
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
