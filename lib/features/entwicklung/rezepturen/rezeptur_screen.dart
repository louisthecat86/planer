// `show Value`: drift bringt eine eigene Klasse `Column` mit, die sich sonst
// mit der von Flutter beißt.
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/services/auto_backup_trigger.dart';
import '../../../core/theme/app_stil.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/fehler_text.dart';
import '../../../core/utils/format.dart';
import '../daten/entwicklung_repository.dart';
import '../entwicklung_format.dart';
import '../etikett/etikett_dialog.dart';
import '../rechenkern/rechen_modell.dart';
import 'fleischanteil_dialog.dart';
import 'rezeptur_ergebnis_ansicht.dart';
import 'rezepturen_ansicht.dart';
import 'stand_abschliessen_dialog.dart';
import 'versionsvergleich.dart';
import 'zutat_auswahl_dialog.dart';

/// Eine Rezeptur: ihre Stände, die Zusammensetzung des gewählten und das
/// Ergebnis daneben.
class RezepturScreen extends ConsumerStatefulWidget {
  const RezepturScreen({super.key, required this.rezepturId});

  final String rezepturId;

  @override
  ConsumerState<RezepturScreen> createState() => _RezepturScreenState();
}

class _RezepturScreenState extends ConsumerState<RezepturScreen> {
  /// Der gewählte Stand — null: der neueste.
  String? _versionId;

  EntwicklungRepository get _repo => ref.read(entwicklungRepositoryProvider);

  void _gesichert(String grund) =>
      ref.read(autoBackupTriggerProvider).fireDebounced(reason: grund);

  Future<void> _fehler(Object e) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(fehlerText(e))),
    );
  }

  Future<void> _bearbeiten(Rezeptur r) async {
    final neu = await showDialog<_Angaben>(
      context: context,
      builder: (_) => _AngabenDialog(rezeptur: r),
    );
    if (neu == null) return;
    try {
      await _repo.rezepturAendern(
        r.id,
        EntwicklungRezepturenCompanion(
          name: Value(neu.name),
          artikelnummer: Value(neu.artikelnummer),
          beschreibung: Value(neu.beschreibung),
        ),
      );
      _gesichert('Rezeptur bearbeitet');
    } catch (e) {
      await _fehler(e);
    }
  }

  Future<void> _loeschen(Rezeptur r) async {
    final verwendet = await _repo.rezepturVerwendungen(r.id);
    if (!mounted) return;
    final ja = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rezeptur löschen?'),
        content: Text(
          verwendet == 0
              ? '„${r.name}" wird mit allen Ständen gelöscht.'
              : '„${r.name}" steckt als Unterrezeptur in $verwendet '
                  '${verwendet == 1 ? 'Stand' : 'Ständen'} anderer '
                  'Rezepturen. Diese rechnen weiter mit ihr.',
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
    await _repo.rezepturLoeschen(r.id);
    _gesichert('Rezeptur gelöscht');
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _neuerStand(RezepturVersion? vorlage) async {
    try {
      final id = await _repo.versionAnlegen(
        widget.rezepturId,
        vorlageId: vorlage?.id,
      );
      setState(() => _versionId = id);
      _gesichert('Neuer Rezepturstand');
    } catch (e) {
      await _fehler(e);
    }
  }

  Future<void> _abschliessen(RezepturVersion v) async {
    final repo = _repo;
    final List<String> aenderungen;
    final RezepturVersion? vorher;
    final bool imProjekt;
    try {
      aenderungen = await repo.standAenderungenVon(v.id);
      vorher = await repo.vorigerStand(v);
      imProjekt = (await repo.rezeptur(v.rezepturId))?.projektId != null;
    } catch (e) {
      await _fehler(e);
      return;
    }
    if (!mounted) return;
    final grund = await standAbschliessenFragen(
      context,
      version: v,
      aenderungen: aenderungen,
      vorherNummer: vorher?.nummer,
      imProjekt: imProjekt,
    );
    if (grund == null) return;
    try {
      await repo.versionAbschliessen(v.id, grund: grund);
      _gesichert('Rezepturstand abgeschlossen');
    } catch (e) {
      await _fehler(e);
    }
  }

  Future<void> _standLoeschen(RezepturVersion v) async {
    final ja = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Stand ${v.nummer} löschen?'),
        content: const Text('Der Entwurf wird mit allen Zeilen gelöscht.'),
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
    if (ja != true) return;
    try {
      await _repo.versionLoeschen(v.id);
      setState(() => _versionId = null);
      _gesichert('Rezepturstand gelöscht');
    } catch (e) {
      await _fehler(e);
    }
  }

  Future<void> _fleischanteil(RezepturVersion v) async {
    final id = await fleischanteilOeffnen(
      context,
      rezepturId: widget.rezepturId,
      version: v,
    );
    if (id != null && mounted) setState(() => _versionId = id);
  }

  Future<void> _vergleichen(
    List<RezepturVersion> versionen,
    RezepturVersion aktuell,
  ) async {
    final andere = versionen.firstWhere(
      (v) => v.id != aktuell.id,
      orElse: () => aktuell,
    );
    await showDialog<void>(
      context: context,
      builder: (_) => VersionsVergleichDialog(
        versionen: versionen,
        aId: andere.id,
        bId: aktuell.id,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rezeptur = ref.watch(rezepturProvider(widget.rezepturId));
    final versionen = ref.watch(versionenProvider(widget.rezepturId));
    final r = rezeptur.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(r?.name ?? 'Rezeptur'),
        actions: [
          if (r != null)
            PopupMenuButton<VoidCallback>(
              key: const ValueKey('rezeptur-mehr'),
              tooltip: 'Name und Angaben ändern oder Rezeptur löschen',
              onSelected: (aktion) => aktion(),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: () => _bearbeiten(r),
                  child: const ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Name und Angaben…'),
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: () => _loeschen(r),
                  child: const ListTile(
                    leading: Icon(Icons.delete_outline),
                    title: Text('Rezeptur löschen…'),
                  ),
                ),
              ],
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: versionen.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: HinweisBox(
            fehlerText(e),
            art: StatusArt.fehler,
            titel: 'Die Rezeptur ließ sich nicht laden',
            auswaehlbar: true,
          ),
        ),
        data: (liste) {
          if (r == null && !rezeptur.isLoading) {
            return const Center(
              child: LeerHinweis('Diese Rezeptur gibt es nicht mehr.'),
            );
          }
          if (liste.isEmpty) {
            return Center(
              child: LeerHinweis(
                'Diese Rezeptur hat noch keinen Stand.',
                icon: Icons.menu_book_outlined,
                aktion: FilledButton.icon(
                  onPressed: () => _neuerStand(null),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Ersten Stand anlegen'),
                ),
              ),
            );
          }
          final aktuell = liste.firstWhere(
            (v) => v.id == _versionId,
            orElse: () => liste.first,
          );
          final leiste = _StandLeiste(
            versionen: liste,
            aktuell: aktuell,
            onWahl: (id) => setState(() => _versionId = id),
            onNeu: () => _neuerStand(aktuell),
            onAbschliessen: () => _abschliessen(aktuell),
            onVergleichen: () => _vergleichen(liste, aktuell),
            onEtikett: () => etikettZeigen(context, aktuell.id),
            onFleisch: () => _fleischanteil(aktuell),
            onLoeschen: liste.length > 1 &&
                    aktuell.status == VersionStatus.entwurf
                ? () => _standLoeschen(aktuell)
                : null,
          );
          final zusammensetzung = Zusammensetzung(
            rezepturId: widget.rezepturId,
            version: aktuell,
          );
          final ergebnis = RezepturErgebnisAnsicht(versionId: aktuell.id);
          return LayoutBuilder(
            builder: (context, c) {
              if (c.maxWidth >= 1100) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    leiste,
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 11,
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(16, 12, 8, 24),
                              children: [zusammensetzung],
                            ),
                          ),
                          Expanded(
                            flex: 9,
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(8, 12, 16, 24),
                              children: [ergebnis],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }
              return ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  leiste,
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: zusammensetzung,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: ergebnis,
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// Die Stände als Reiter, dahinter für den gewählten in Worten, was mit
/// ihm ist, und ein Hauptknopf je nach Lage: Ein Entwurf wird
/// abgeschlossen, ein abgeschlossener Stand weiterentwickelt — oder, wenn
/// schon ein Entwurf in Arbeit ist, geht es zu ihm. Alles andere steht
/// unter „Mehr".
class _StandLeiste extends StatelessWidget {
  const _StandLeiste({
    required this.versionen,
    required this.aktuell,
    required this.onWahl,
    required this.onNeu,
    required this.onAbschliessen,
    required this.onVergleichen,
    required this.onLoeschen,
    this.onEtikett,
    this.onFleisch,
  });

  /// Die Stände, der neueste zuerst.
  final List<RezepturVersion> versionen;
  final RezepturVersion aktuell;
  final ValueChanged<String> onWahl;

  /// Ein neuer Entwurf als Kopie des gewählten Stands.
  final VoidCallback onNeu;
  final VoidCallback onAbschliessen;
  final VoidCallback onVergleichen;
  final VoidCallback? onLoeschen;

  /// Das Etikett des Stands — null: kein Eintrag.
  final VoidCallback? onEtikett;

  /// „Fleischanteil einstellen" — null: kein Eintrag.
  final VoidCallback? onFleisch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entwurf = aktuell.status == VersionStatus.entwurf;
    final abgeschlossenAm = aktuell.abgeschlossenAm;
    // Ein anderer Entwurf, an dem schon gearbeitet wird — der neueste.
    final inArbeit = versionen
        .where((v) => v.status == VersionStatus.entwurf && v.id != aktuell.id)
        .firstOrNull;

    final Widget haupt;
    if (entwurf) {
      haupt = FilledButton.icon(
        key: const ValueKey('stand-haupt'),
        onPressed: onAbschliessen,
        icon: const Icon(Icons.lock_outline, size: 18),
        label: const Text('Stand abschließen…'),
      );
    } else if (inArbeit != null) {
      haupt = FilledButton.tonalIcon(
        key: const ValueKey('stand-haupt'),
        onPressed: () => onWahl(inArbeit.id),
        icon: const Icon(Icons.edit_outlined, size: 18),
        label: Text('Zum Entwurf (Stand ${inArbeit.nummer})'),
      );
    } else {
      haupt = Tooltip(
        message: 'Legt einen neuen Entwurf als Kopie dieses Stands an',
        child: FilledButton.icon(
          key: const ValueKey('stand-haupt'),
          onPressed: onNeu,
          icon: const Icon(Icons.arrow_forward, size: 18),
          label: const Text('Weiterentwickeln'),
        ),
      );
    }

    final etikett = onEtikett;
    final fleisch = onFleisch;
    final loeschen = onLoeschen;
    final mehr = MenueKnopf(
      key: const ValueKey('stand-mehr'),
      eintraege: [
        if (versionen.length > 1)
          MenueEintrag(
            'Mit anderem Stand vergleichen…',
            icon: Icons.compare_arrows,
            aktion: onVergleichen,
          ),
        if (etikett != null)
          MenueEintrag(
            'Etikett ansehen…',
            icon: Icons.label_outline,
            aktion: etikett,
          ),
        if (fleisch != null)
          MenueEintrag(
            'Fleischanteil einstellen…',
            icon: Icons.tune,
            aktion: fleisch,
          ),
        // Weiterentwickeln steht sonst schon als Hauptknopf da.
        if (entwurf || inArbeit != null)
          MenueEintrag(
            'Neuen Stand daraus anlegen',
            icon: Icons.add,
            aktion: onNeu,
          ),
        if (loeschen != null) ...[
          null,
          MenueEintrag(
            'Entwurf löschen…',
            icon: Icons.delete_outline,
            aktion: loeschen,
          ),
        ],
      ],
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      decoration: BoxDecoration(
        color: AppFarben.von(context).leiste,
        border: Border(bottom: BorderSide(color: theme.colorScheme.outline)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Ältester links, neuester rechts — wie eine Zeitleiste.
          for (final v in versionen.reversed)
            ChoiceChip(
              selected: v.id == aktuell.id,
              tooltip: v.status == VersionStatus.abgeschlossen
                  ? 'Abgeschlossen'
                  : 'Entwurf',
              avatar: Icon(
                v.status == VersionStatus.abgeschlossen
                    ? Icons.lock_outline
                    : Icons.edit_outlined,
                size: 15,
              ),
              label: Text(
                v.bezeichnung == null || v.bezeichnung!.trim().isEmpty
                    ? 'Stand ${v.nummer}'
                    : 'Stand ${v.nummer} · ${v.bezeichnung!.trim()}',
              ),
              onSelected: (_) => onWahl(v.id),
            ),
          const SizedBox(width: 8),
          // In Worten, was mit dem gewählten Stand ist.
          Text(
            entwurf
                ? 'Entwurf · in Arbeit'
                : abgeschlossenAm == null
                    ? 'abgeschlossen'
                    : 'abgeschlossen am ${Format.datum(abgeschlossenAm)}',
            key: const ValueKey('stand-zustand'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          haupt,
          mehr,
        ],
      ),
    );
  }
}

/// Die Zusammensetzung eines Stands: Zeilen, Mengen, Verlust. Ein Entwurf
/// lässt sich hier bearbeiten.
class Zusammensetzung extends ConsumerWidget {
  const Zusammensetzung({
    super.key,
    required this.rezepturId,
    required this.version,
  });

  final String rezepturId;
  final RezepturVersion version;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final positionen =
        ref.watch(positionenProvider(version.id)).valueOrNull ?? const [];
    final zutaten = ref.watch(alleZutatenProvider).valueOrNull ?? const {};
    final rezepturen =
        ref.watch(alleRezepturenProvider).valueOrNull ?? const {};
    // Erst beim Handeln holen: Die Anzeige allein braucht keine Datenbank.
    EntwicklungRepository repo() => ref.read(entwicklungRepositoryProvider);
    final entwurf = version.status == VersionStatus.entwurf;
    final summe = positionen.fold<double>(0, (s, p) => s + p.mengeKg);

    void gesichert(String grund) =>
        ref.read(autoBackupTriggerProvider).fireDebounced(reason: grund);

    Future<void> ausfuehren(Future<void> Function() tun, String grund) async {
      try {
        await tun();
        gesichert(grund);
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(fehlerText(e))),
        );
      }
    }

    Future<void> einfuegen() async {
      final wahl = await showDialog<ZutatAuswahl>(
        context: context,
        builder: (_) => ZutatAuswahlDialog(ohneRezepturId: rezepturId),
      );
      if (wahl == null) return;
      await ausfuehren(
        () => repo().positionHinzufuegen(
          version.id,
          zutatId: wahl.istRezeptur ? null : wahl.id,
          unterrezepturId: wahl.istRezeptur ? wahl.id : null,
        ),
        'Rezepturzeile eingefügt',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Bereich(
          titel: 'Zusammensetzung',
          untertitel: entwurf
              ? 'Stand ${version.nummer} · Entwurf'
              : 'Stand ${version.nummer} · abgeschlossen',
          innenAbstand: EdgeInsets.zero,
          aktionen: [
            if (entwurf)
              TextButton.icon(
                onPressed: einfuegen,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Einfügen'),
              ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _ZeilenKopf(),
              if (positionen.isEmpty)
                LeerHinweis(
                  entwurf
                      ? 'Noch leer — füge Zutaten oder Unterrezepturen ein.'
                      : 'Dieser Stand hat keine Zeilen.',
                  icon: Icons.egg_outlined,
                ),
              for (var i = 0; i < positionen.length; i++)
                _ZeilenAnsicht(
                  key: ValueKey(positionen[i].id),
                  position: positionen[i],
                  zutat: positionen[i].zutatId == null
                      ? null
                      : zutaten[positionen[i].zutatId],
                  unterrezeptur: positionen[i].unterrezepturId == null
                      ? null
                      : rezepturen[positionen[i].unterrezepturId],
                  summeKg: summe,
                  bearbeitbar: entwurf,
                  erste: i == 0,
                  letzte: i == positionen.length - 1,
                  ausfuehren: ausfuehren,
                ),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Summe',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: _ZeilenKopf.menge,
                      child: Text(
                        '${mengeText(summe)} kg',
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(
                      width: _ZeilenKopf.anteil +
                          _ZeilenKopf.quid +
                          _ZeilenKopf.menue,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Bereich(
          titel: 'Verlust und Angaben',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<Verlustart>(
                    segments: [
                      for (final art in Verlustart.values)
                        ButtonSegment(value: art, label: Text(art.label)),
                    ],
                    selected: {Verlustart.aus(version.verlustArt)},
                    showSelectedIcon: false,
                    onSelectionChanged: entwurf
                        ? (wahl) => ausfuehren(
                              () => repo().versionAendern(
                                version.id,
                                EntwicklungRezepturVersionenCompanion(
                                  verlustArt: Value(wahl.first.schluessel),
                                ),
                              ),
                              'Verlustart geändert',
                            )
                        : null,
                  ),
                  if (Verlustart.aus(version.verlustArt) != Verlustart.keiner) ...[
                    ZahlFeld(
                      key: ValueKey('verlust-${version.id}'),
                      wert: version.verlustProzent,
                      label: 'Verlust',
                      suffix: '%',
                      bearbeitbar: entwurf,
                      onFertig: (v) => ausfuehren(
                        () => repo().versionAendern(
                          version.id,
                          EntwicklungRezepturVersionenCompanion(
                            verlustProzent: Value(v),
                          ),
                        ),
                        'Verlust geändert',
                      ),
                    ),
                    ZahlFeld(
                      key: ValueKey('fett-${version.id}'),
                      wert: version.fettVerlustProzent,
                      label: 'davon Fett',
                      suffix: '%',
                      bearbeitbar: entwurf,
                      onFertig: (v) => ausfuehren(
                        () => repo().versionAendern(
                          version.id,
                          EntwicklungRezepturVersionenCompanion(
                            fettVerlustProzent: Value(v),
                          ),
                        ),
                        'Fettverlust geändert',
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              TextFeld(
                key: ValueKey('bezeichnung-${version.id}'),
                wert: version.bezeichnung ?? '',
                label: 'Bezeichnung des Stands',
                hinweis: 'etwa „Muster 2 für den Kunden"',
                bearbeitbar: entwurf,
                onFertig: (t) => ausfuehren(
                  () => repo().versionAendern(
                    version.id,
                    EntwicklungRezepturVersionenCompanion(
                      bezeichnung: Value(t.isEmpty ? null : t),
                    ),
                  ),
                  'Stand benannt',
                ),
              ),
              const SizedBox(height: 10),
              TextFeld(
                key: ValueKey('notiz-${version.id}'),
                wert: version.notiz ?? '',
                label: 'Notiz',
                mehrzeilig: true,
                bearbeitbar: entwurf,
                onFertig: (t) => ausfuehren(
                  () => repo().versionAendern(
                    version.id,
                    EntwicklungRezepturVersionenCompanion(
                      notiz: Value(t.isEmpty ? null : t),
                    ),
                  ),
                  'Notiz geändert',
                ),
              ),
              if (!entwurf) ...[
                const SizedBox(height: 10),
                Text(
                  'Abgeschlossen — geändert wird nur ein Entwurf: oben '
                  '„Weiterentwickeln" oder „Zum Entwurf".',
                  style: theme.textTheme.bodySmall?.copyWith(color: grau),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ZeilenKopf extends StatelessWidget {
  const _ZeilenKopf();

  static const double menge = 110;
  static const double anteil = 70;
  static const double quid = 56;
  static const double menue = 40;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stil = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        color: AppFarben.von(context).leiste,
        border: Border(bottom: BorderSide(color: theme.colorScheme.outline)),
      ),
      child: Row(
        children: [
          Expanded(child: Text('Zutat', style: stil)),
          SizedBox(
            width: menge,
            child: Text('Menge', textAlign: TextAlign.right, style: stil),
          ),
          SizedBox(
            width: anteil,
            child: Text('Anteil', textAlign: TextAlign.right, style: stil),
          ),
          SizedBox(
            width: quid,
            child: Text('QUID', textAlign: TextAlign.center, style: stil),
          ),
          const SizedBox(width: menue),
        ],
      ),
    );
  }
}

/// Eine Zeile der Zusammensetzung.
class _ZeilenAnsicht extends ConsumerWidget {
  const _ZeilenAnsicht({
    super.key,
    required this.position,
    required this.zutat,
    required this.unterrezeptur,
    required this.summeKg,
    required this.bearbeitbar,
    required this.erste,
    required this.letzte,
    required this.ausfuehren,
  });

  final RezepturPosition position;
  final Zutat? zutat;
  final Rezeptur? unterrezeptur;
  final double summeKg;
  final bool bearbeitbar;
  final bool erste;
  final bool letzte;
  final Future<void> Function(Future<void> Function() tun, String grund)
      ausfuehren;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    EntwicklungRepository repo() => ref.read(entwicklungRepositoryProvider);
    final p = position;
    final z = zutat;
    final u = unterrezeptur;
    final istUnter = p.unterrezepturId != null;
    final name = z?.name ?? u?.name ?? 'fehlt';
    final geloescht = (z?.deletedAt ?? u?.deletedAt) != null;
    final fehlt = z == null && u == null;
    final etikett = p.etikettName?.trim();
    final quid = p.quidPflicht ?? z?.quidPflicht ?? false;
    final anteil = summeKg > 0 ? p.mengeKg / summeKg * 100 : 0.0;

    Future<void> etikettAendern() async {
      final text = await showDialog<String>(
        context: context,
        builder: (_) => _TextDialog(
          titel: 'Name auf dem Etikett',
          hinweis: 'Nur in dieser Rezeptur — leer: wie bei der Zutat',
          wert: p.etikettName ?? '',
        ),
      );
      if (text == null) return;
      await ausfuehren(
        () => repo().positionAendern(
          p,
          EntwicklungRezepturPositionenCompanion(
            etikettName: Value(text.trim().isEmpty ? null : text.trim()),
          ),
        ),
        'Etikettname geändert',
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
      constraints: const BoxConstraints(minHeight: 44),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          if (istUnter)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(Icons.subdirectory_arrow_right, size: 16, color: grau),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: istUnter && !fehlt
                          ? InkWell(
                              onTap: () =>
                                  oeffneRezeptur(context, p.unterrezepturId!),
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            )
                          : Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: fehlt ? theme.colorScheme.error : null,
                              ),
                            ),
                    ),
                    if (geloescht) ...[
                      const SizedBox(width: 6),
                      const StatusMarke('gelöscht', art: StatusArt.warnung),
                    ],
                  ],
                ),
                if (istUnter || (etikett != null && etikett.isNotEmpty))
                  Text(
                    [
                      if (istUnter)
                        'Unterrezeptur · eingesetzte fertige Menge',
                      if (etikett != null && etikett.isNotEmpty)
                        'Etikett: $etikett',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: grau),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: _ZeilenKopf.menge,
            child: Align(
              alignment: Alignment.centerRight,
              child: ZahlFeld(
                wert: p.mengeKg,
                suffix: 'kg',
                breite: 104,
                bearbeitbar: bearbeitbar,
                onFertig: (v) => ausfuehren(
                  () => repo().positionAendern(
                    p,
                    EntwicklungRezepturPositionenCompanion(mengeKg: Value(v)),
                  ),
                  'Menge geändert',
                ),
              ),
            ),
          ),
          SizedBox(
            width: _ZeilenKopf.anteil,
            child: Text(
              prozentText(anteil),
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(color: grau),
            ),
          ),
          SizedBox(
            width: _ZeilenKopf.quid,
            child: istUnter
                ? Text('—', textAlign: TextAlign.center, style: TextStyle(color: grau))
                : Checkbox(
                    value: quid,
                    onChanged: bearbeitbar
                        ? (v) => ausfuehren(
                              () => repo().positionAendern(
                                p,
                                EntwicklungRezepturPositionenCompanion(
                                  quidPflicht: Value(v ?? false),
                                ),
                              ),
                              'QUID geändert',
                            )
                        : null,
                  ),
          ),
          SizedBox(
            width: _ZeilenKopf.menue,
            child: bearbeitbar
                ? PopupMenuButton<String>(
                    tooltip: 'Zeile',
                    icon: const Icon(Icons.more_vert, size: 18),
                    onSelected: (wahl) {
                      switch (wahl) {
                        case 'hoch':
                          ausfuehren(
                            () => repo().positionVerschieben(p, nachOben: true),
                            'Zeile verschoben',
                          );
                        case 'runter':
                          ausfuehren(
                            () => repo().positionVerschieben(p, nachOben: false),
                            'Zeile verschoben',
                          );
                        case 'etikett':
                          etikettAendern();
                        case 'weg':
                          ausfuehren(
                            () => repo().positionLoeschen(p),
                            'Zeile entfernt',
                          );
                      }
                    },
                    itemBuilder: (_) => [
                      if (!erste)
                        const PopupMenuItem(
                          value: 'hoch',
                          child: Text('Nach oben'),
                        ),
                      if (!letzte)
                        const PopupMenuItem(
                          value: 'runter',
                          child: Text('Nach unten'),
                        ),
                      if (!istUnter)
                        const PopupMenuItem(
                          value: 'etikett',
                          child: Text('Name auf dem Etikett …'),
                        ),
                      const PopupMenuItem(
                        value: 'weg',
                        child: Text('Entfernen'),
                      ),
                    ],
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

/// Ein Zahlenfeld, das beim Verlassen oder mit Enter speichert.
class ZahlFeld extends StatefulWidget {
  const ZahlFeld({
    super.key,
    required this.wert,
    required this.onFertig,
    this.label,
    this.suffix,
    this.breite = 120,
    this.bearbeitbar = true,
  });

  final double wert;
  final ValueChanged<double> onFertig;
  final String? label;
  final String? suffix;
  final double breite;
  final bool bearbeitbar;

  @override
  State<ZahlFeld> createState() => _ZahlFeldState();
}

class _ZahlFeldState extends State<ZahlFeld> {
  late final TextEditingController _text =
      TextEditingController(text: feldText(widget.wert));
  final FocusNode _fokus = FocusNode();

  @override
  void initState() {
    super.initState();
    _fokus.addListener(() {
      if (!_fokus.hasFocus) _fertig();
    });
  }

  @override
  void didUpdateWidget(ZahlFeld alt) {
    super.didUpdateWidget(alt);
    if (alt.wert != widget.wert && !_fokus.hasFocus) {
      _text.text = feldText(widget.wert);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _fokus.dispose();
    super.dispose();
  }

  void _fertig() {
    final wert =
        zahlAus(_text.text) ?? (_text.text.trim().isEmpty ? 0.0 : null);
    if (wert == null || wert < 0) {
      _text.text = feldText(widget.wert);
      return;
    }
    if ((wert - widget.wert).abs() > 1e-12) widget.onFertig(wert);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.breite,
      child: TextField(
        controller: _text,
        focusNode: _fokus,
        enabled: widget.bearbeitbar,
        textAlign: TextAlign.right,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          isDense: true,
          labelText: widget.label,
          suffixText: widget.suffix,
        ),
        onSubmitted: (_) => _fertig(),
      ),
    );
  }
}

/// Ein Textfeld, das beim Verlassen oder mit Enter speichert.
class TextFeld extends StatefulWidget {
  const TextFeld({
    super.key,
    required this.wert,
    required this.onFertig,
    required this.label,
    this.hinweis,
    this.mehrzeilig = false,
    this.bearbeitbar = true,
  });

  final String wert;
  final ValueChanged<String> onFertig;
  final String label;
  final String? hinweis;
  final bool mehrzeilig;
  final bool bearbeitbar;

  @override
  State<TextFeld> createState() => _TextFeldState();
}

class _TextFeldState extends State<TextFeld> {
  late final TextEditingController _text =
      TextEditingController(text: widget.wert);
  final FocusNode _fokus = FocusNode();

  @override
  void initState() {
    super.initState();
    _fokus.addListener(() {
      if (!_fokus.hasFocus) _fertig();
    });
  }

  @override
  void didUpdateWidget(TextFeld alt) {
    super.didUpdateWidget(alt);
    if (alt.wert != widget.wert && !_fokus.hasFocus) {
      _text.text = widget.wert;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _fokus.dispose();
    super.dispose();
  }

  void _fertig() {
    final t = _text.text.trim();
    if (t != widget.wert.trim()) widget.onFertig(t);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _text,
      focusNode: _fokus,
      enabled: widget.bearbeitbar,
      minLines: 1,
      maxLines: widget.mehrzeilig ? 5 : 1,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.hinweis,
      ),
      onSubmitted: widget.mehrzeilig ? null : (_) => _fertig(),
    );
  }
}

/// Name, Artikelnummer und Beschreibung einer Rezeptur.
class _Angaben {
  const _Angaben(this.name, this.artikelnummer, this.beschreibung);

  final String name;
  final String? artikelnummer;
  final String? beschreibung;
}

class _AngabenDialog extends StatefulWidget {
  const _AngabenDialog({required this.rezeptur});

  final Rezeptur rezeptur;

  @override
  State<_AngabenDialog> createState() => _AngabenDialogState();
}

class _AngabenDialogState extends State<_AngabenDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.rezeptur.name);
  late final TextEditingController _nummer =
      TextEditingController(text: widget.rezeptur.artikelnummer ?? '');
  late final TextEditingController _beschreibung =
      TextEditingController(text: widget.rezeptur.beschreibung ?? '');

  @override
  void dispose() {
    _name.dispose();
    _nummer.dispose();
    _beschreibung.dispose();
    super.dispose();
  }

  void _fertig() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final nummer = _nummer.text.trim();
    final beschreibung = _beschreibung.text.trim();
    Navigator.of(context).pop(
      _Angaben(
        name,
        nummer.isEmpty ? null : nummer,
        beschreibung.isEmpty ? null : beschreibung,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rezeptur'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            // Im Projekt steht die Artikelnummer in den Stammdaten.
            if (widget.rezeptur.projektId == null) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _nummer,
                decoration: const InputDecoration(labelText: 'Artikelnummer'),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _beschreibung,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Beschreibung'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(onPressed: _fertig, child: const Text('Speichern')),
      ],
    );
  }
}

/// Fragt einen Text ab.
class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.titel,
    required this.wert,
    this.hinweis,
  });

  final String titel;
  final String wert;
  final String? hinweis;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final TextEditingController _text =
      TextEditingController(text: widget.wert);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titel),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: TextField(
          controller: _text,
          autofocus: true,
          decoration: InputDecoration(helperText: widget.hinweis),
          onSubmitted: (t) => Navigator.of(context).pop(t),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_text.text),
          child: const Text('Übernehmen'),
        ),
      ],
    );
  }
}
