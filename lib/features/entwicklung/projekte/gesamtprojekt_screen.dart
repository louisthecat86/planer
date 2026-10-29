// `show Value`: drift bringt eine eigene Klasse `Column` mit.
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database.dart';
import '../../../core/services/auto_backup_trigger.dart';
import '../../../core/theme/app_stil.dart';
import '../../../core/ui/ablage.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/fehler_text.dart';
import '../../../core/utils/format.dart';
import '../daten/entwicklung_repository.dart';
import '../rezepturen/rezeptur_screen.dart' show TextFeld;
import 'faellig.dart';
import 'gesamtprojekt_dialoge.dart';
import 'gesamtprojekt_modell.dart';
import 'projekt_checkliste.dart';
import 'projekt_dateien.dart';
import 'projekt_modell.dart';
import 'projekt_repository.dart';
import 'projekt_verlauf.dart';
import 'projekte_ansicht.dart';
import 'zeitstrahl.dart' show phasenFarbe;

// Die Seite eines Gesamtprojekts: die Anfrage mit ihren Mustern
// (Übersicht), die Korrespondenz und die Meilensteine der Muster
// (Verlauf) und die Unterlagen (Dateien). Mails und Dateien lassen sich
// auf jeden Reiter ziehen — sie kommen ins Gesamtprojekt und stehen damit
// in jedem Muster mit drin.

/// Öffnet ein Gesamtprojekt auf seiner eigenen Seite.
Future<void> oeffneGesamtprojekt(BuildContext context, String id) =>
    context.pushNamed<void>(
      'entwicklungGesamtprojekt',
      pathParameters: {'id': id},
    );

/// Die Reiter eines Gesamtprojekts — vorn die Übersicht mit den Mustern.
enum GesamtprojektReiter {
  uebersicht('Übersicht'),
  verlauf('Verlauf'),
  dateien('Dateien');

  const GesamtprojektReiter(this.label);

  final String label;
}

/// Legt im Gesamtprojekt ein neues Muster an und öffnet es.
Future<void> neuesMuster(
  BuildContext context,
  Gesamtprojekt g, {
  int? nr,
}) async {
  final id = await showDialog<String>(
    context: context,
    builder: (_) => NeuesMusterDialog(gesamtprojekt: g, nr: nr),
  );
  if (id == null || !context.mounted) return;
  await oeffneProjekt(context, id);
}

/// Speichert eine Änderung am Gesamtprojekt; Fehler erscheinen unten.
Future<void> gesamtprojektSpeichern(
  BuildContext context,
  WidgetRef ref,
  String id,
  EntwicklungGesamtprojekteCompanion daten,
) async {
  try {
    await ref.read(projektRepositoryProvider).gesamtprojektAendern(id, daten);
    ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Gesamtprojekt');
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Speichern fehlgeschlagen: ${fehlerText(e)}')),
      );
    }
  }
}

String? _oderNull(String t) => t.trim().isEmpty ? null : t.trim();

/// Ein Gesamtprojekt: Übersicht, Verlauf und Dateien.
class GesamtprojektScreen extends ConsumerWidget {
  const GesamtprojektScreen({super.key, required this.gesamtprojektId});

  final String gesamtprojektId;

  Future<void> _umbenennen(
    BuildContext context,
    WidgetRef ref,
    Gesamtprojekt g,
  ) async {
    final name = await nameFragen(
      context,
      titel: 'Gesamtprojekt umbenennen',
      label: 'Name des Gesamtprojekts',
      name: g.name,
    );
    if (name == null || !context.mounted) return;
    await gesamtprojektSpeichern(
      context,
      ref,
      g.id,
      EntwicklungGesamtprojekteCompanion(name: Value(name)),
    );
  }

  /// Nimmt ein Projekt, das noch für sich steht, als Muster auf.
  Future<void> _aufnehmen(
    BuildContext context,
    WidgetRef ref,
    Gesamtprojekt g,
  ) async {
    final frei = [
      for (final p in ref.read(projekteProvider).valueOrNull ??
          const <EntwicklungsProjekt>[])
        if (p.gesamtprojektId == null) p,
    ];
    if (frei.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Es gibt kein Projekt, das noch für sich steht.'),
        ),
      );
      return;
    }
    final p = await showDialog<EntwicklungsProjekt>(
      context: context,
      builder: (_) => _ProjektWahlDialog(projekte: frei, kunde: g.kunde),
    );
    if (p == null || !context.mounted) return;
    try {
      await ref.read(projektRepositoryProvider).inGesamtprojektVerschieben(
            p.id,
            g.id,
          );
      ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Muster');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Das ging nicht: ${fehlerText(e)}')),
        );
      }
    }
  }

  Future<void> _loeschen(
    BuildContext context,
    WidgetRef ref,
    Gesamtprojekt g,
  ) async {
    final muster = ref.read(musterProvider(g.id)).valueOrNull ??
        const <EntwicklungsProjekt>[];
    final mitMustern = muster.length == 1
        ? 'seinem Muster'
        : 'seinen ${muster.length} Mustern';
    final ja = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gesamtprojekt löschen?'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Text(
            muster.isEmpty
                ? '„${g.name}" wird mit seinem Verlauf und seinen Dateien '
                    'gelöscht.'
                : '„${g.name}" wird mit seinem Verlauf, seinen Dateien und '
                    '$mitMustern '
                    'gelöscht. Deren Rezepturen bleiben und stehen danach '
                    'ohne Projekt in der Liste. Ein Muster, das bleiben '
                    'soll, löst du vorher auf seiner Seite aus dem '
                    'Gesamtprojekt.',
          ),
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
    await ref.read(projektRepositoryProvider).gesamtprojektLoeschen(g.id);
    ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Gesamtprojekt');
    if (context.mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gesamt = ref.watch(gesamtprojektProvider(gesamtprojektId));
    final g = gesamt.valueOrNull;
    final muster = ref.watch(musterProvider(gesamtprojektId)).valueOrNull ??
        const <EntwicklungsProjekt>[];
    final kunde = g?.kunde?.trim() ?? '';
    final theme = Theme.of(context);
    return DefaultTabController(
      length: GesamtprojektReiter.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              const Icon(Icons.folder_outlined, size: 22),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  g == null
                      ? 'Gesamtprojekt'
                      : (kunde.isEmpty ? g.name : '${g.name} · $kunde'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          actions: [
            if (g != null && g.deletedAt == null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FilledButton.tonalIcon(
                  key: const ValueKey('gesamt-neues-muster'),
                  onPressed: () =>
                      neuesMuster(context, g, nr: muster.length + 1),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Neues Muster'),
                ),
              ),
              PopupMenuButton<VoidCallback>(
                key: const ValueKey('gesamt-mehr'),
                tooltip: 'Umbenennen, Projekt aufnehmen oder löschen',
                onSelected: (aktion) => aktion(),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: () => _umbenennen(context, ref, g),
                    child: const ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Umbenennen…'),
                    ),
                  ),
                  PopupMenuItem(
                    value: () => _aufnehmen(context, ref, g),
                    child: const ListTile(
                      leading: Icon(Icons.drive_file_move_outline),
                      title: Text('Projekt als Muster aufnehmen…'),
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: () => _loeschen(context, ref, g),
                    child: const ListTile(
                      leading: Icon(Icons.delete_outline),
                      title: Text('Gesamtprojekt löschen…'),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(width: 8),
          ],
        ),
        body: gesamt.when(
          skipLoadingOnReload: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: HinweisBox(
              fehlerText(e),
              art: StatusArt.fehler,
              titel: 'Das Gesamtprojekt ließ sich nicht laden',
              auswaehlbar: true,
            ),
          ),
          data: (g) => g == null || g.deletedAt != null
              ? const Center(
                  child: LeerHinweis(
                    'Dieses Gesamtprojekt gibt es nicht mehr.',
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Kopf(gesamtprojekt: g, muster: muster),
                    Material(
                      color: theme.colorScheme.surface,
                      child: TabBar(
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        tabs: [
                          for (final r in GesamtprojektReiter.values)
                            Tab(text: r.label),
                        ],
                      ),
                    ),
                    Expanded(
                      child: AblageZone(
                        hinweis: 'Mail oder Datei loslassen — kommt ins '
                            'Gesamtprojekt',
                        onAbgelegt: (dateien) =>
                            projektAblage(context, ref, g.id, dateien),
                        child: TabBarView(
                          children: [
                            GesamtprojektUebersicht(
                              gesamtprojekt: g,
                              muster: muster,
                            ),
                            GesamtprojektVerlauf(gesamtprojekt: g),
                            DateienListe(zielId: g.id, gesamtprojektId: g.id),
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

/// Über den Reitern: wie die Muster stehen.
class _Kopf extends StatelessWidget {
  const _Kopf({required this.gesamtprojekt, required this.muster});

  final Gesamtprojekt gesamtprojekt;
  final List<EntwicklungsProjekt> muster;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    return Container(
      key: const ValueKey('gesamt-kopf'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: AppFarben.von(context).leiste,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Text(
            'Gesamtprojekt',
            style: theme.textTheme.labelSmall?.copyWith(color: grau),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              musterZusammenfassung([
                for (final m in muster) ProjektStatus.aus(m.status),
              ]),
              key: const ValueKey('gesamt-zusammenfassung'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'seit ${Format.datum(gesamtprojekt.createdAt)}',
            style: theme.textTheme.bodySmall?.copyWith(color: grau),
          ),
        ],
      ),
    );
  }
}

/// Die Übersicht: die Muster als Karten, daneben Kunde, Anfrage und
/// Notizen.
class GesamtprojektUebersicht extends ConsumerWidget {
  const GesamtprojektUebersicht({
    super.key,
    required this.gesamtprojekt,
    required this.muster,
  });

  final Gesamtprojekt gesamtprojekt;
  final List<EntwicklungsProjekt> muster;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = gesamtprojekt;
    final checklisten = ref.watch(projektChecklistenProvider);
    final eintraege = ref.watch(alleEintraegeProvider).valueOrNull ??
        const <ProjektEintrag>[];
    final offen = offeneJeProjekt(eintraege, heute: DateTime.now());
    final jeMuster = <String, List<ProjektEintrag>>{};
    for (final e in eintraege) {
      jeMuster.putIfAbsent(e.projektId, () => []).add(e);
    }
    final musterBereich = Bereich(
      titel: 'Muster',
      icon: Icons.science_outlined,
      untertitel: '${muster.length}',
      aktionen: [
        IconButton(
          tooltip: 'Neues Muster',
          icon: const Icon(Icons.add, size: 18),
          onPressed: () => neuesMuster(context, g, nr: muster.length + 1),
        ),
      ],
      innenAbstand: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: muster.isEmpty
          ? LeerHinweis(
              'Noch keine Muster. Lege für jedes Produkt, das aus der Anfrage '
              'entsteht, ein Muster an — jedes mit eigener Rezeptur und '
              'eigenem Weg.',
              icon: Icons.science_outlined,
              aktion: TextButton.icon(
                onPressed: () => neuesMuster(context, g, nr: 1),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Erstes Muster anlegen'),
              ),
            )
          : LayoutBuilder(
              builder: (context, c) {
                final spalten = (c.maxWidth / 300).floor().clamp(1, 3);
                final breite = (c.maxWidth - (spalten - 1) * 10) / spalten;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final m in muster)
                      SizedBox(
                        width: breite,
                        child: MusterKarte(
                          muster: m,
                          checkliste: checklisten?[m.id],
                          offen: offen[m.id],
                          grund: ProjektStatus.aus(m.status) ==
                                  ProjektStatus.eingestellt
                              ? nichtWeiterGrund(
                                  jeMuster[m.id] ?? const <ProjektEintrag>[],
                                )
                              : null,
                        ),
                      ),
                  ],
                );
              },
            ),
    );
    final angaben = _Angaben(gesamtprojekt: g);
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= 1000) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: musterBereich),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: angaben),
              ],
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [musterBereich, const SizedBox(height: 16), angaben],
        );
      },
    );
  }
}

/// Ein Muster als Karte: Phase, Name, Artikelnummer, was als Nächstes
/// kommt, die Checkliste — und bei einem, das nicht weiter verfolgt
/// wird, der Grund. Antippen öffnet das Muster.
class MusterKarte extends StatelessWidget {
  const MusterKarte({
    super.key,
    required this.muster,
    this.checkliste,
    this.offen,
    this.grund,
  });

  final EntwicklungsProjekt muster;
  final ProjektCheckStand? checkliste;
  final OffeneEintraege? offen;

  /// Warum es nicht weiter verfolgt wird.
  final String? grund;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final farben = AppFarben.von(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final m = muster;
    final status = ProjektStatus.aus(m.status);
    final ruht = status.ruht;
    final c = checkliste;
    final naechster = ruht ? null : c?.naechster;
    final o = ruht ? null : offen;
    final nummer = m.artikelnummer?.trim() ?? '';
    final idee = m.produktidee?.trim() ?? '';
    final g = grund?.trim() ?? '';
    return Material(
      key: ValueKey('muster-${m.id}'),
      color: ruht
          ? theme.colorScheme.surfaceContainerLow
          : theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppMasse.ecken,
        side: BorderSide(
          color: ruht
              ? theme.colorScheme.outlineVariant
              : phasenFarbe(context, status).withValues(alpha: 0.6),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => oeffneProjekt(context, m.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  StatusMarke(status.label, art: projektStatusArt(status)),
                  const Spacer(),
                  if (nummer.isNotEmpty)
                    Text(
                      nummer,
                      style: theme.textTheme.bodySmall?.copyWith(color: grau),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                m.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: ruht ? grau : theme.colorScheme.primary,
                ),
              ),
              if (g.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Grund: $g',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: phasenFarbe(context, status),
                  ),
                ),
              ] else if (naechster != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Als Nächstes: ${checkAufgabe(naechster)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ] else if (idee.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  idee,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: grau),
                ),
              ],
              if (o != null && o.offen > 0) ...[
                const SizedBox(height: 4),
                Text(
                  offeneEintraegeText(o),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: o.ueberfaellig > 0 ? farben.fehler : farben.warnung,
                    fontWeight: o.ueberfaellig > 0 ? FontWeight.w600 : null,
                  ),
                ),
              ],
              if (!ruht && c != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: c.anteil,
                          minHeight: 5,
                          color: farben.ok,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      c.text,
                      style: theme.textTheme.labelSmall?.copyWith(color: grau),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Kunde, Anfrage und Notizen — der Kunde gilt für alle Muster.
class _Angaben extends ConsumerWidget {
  const _Angaben({required this.gesamtprojekt});

  final Gesamtprojekt gesamtprojekt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = gesamtprojekt;
    void speichern(EntwicklungGesamtprojekteCompanion daten) =>
        gesamtprojektSpeichern(context, ref, g.id, daten);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Bereich(
          titel: 'Anfrage',
          icon: Icons.info_outline,
          innenAbstand: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFeld(
                key: const ValueKey('gesamt-kunde'),
                wert: g.kunde ?? '',
                label: 'Kunde',
                hinweis: 'Gilt für alle Muster',
                onFertig: (t) => speichern(
                  EntwicklungGesamtprojekteCompanion(
                    kunde: Value(_oderNull(t)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextFeld(
                key: const ValueKey('gesamt-anfrage'),
                wert: g.anfrage ?? '',
                label: 'Worum es geht',
                hinweis: 'Die Anfrage — etwa aus der ersten Mail',
                mehrzeilig: true,
                onFertig: (t) => speichern(
                  EntwicklungGesamtprojekteCompanion(
                    anfrage: Value(_oderNull(t)),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Bereich(
          titel: 'Notizen',
          icon: Icons.sticky_note_2_outlined,
          innenAbstand: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: TextFeld(
            key: const ValueKey('gesamt-notizen'),
            wert: g.notizen ?? '',
            label: 'Notizen',
            mehrzeilig: true,
            onFertig: (t) => speichern(
              EntwicklungGesamtprojekteCompanion(notizen: Value(_oderNull(t))),
            ),
          ),
        ),
      ],
    );
  }
}

/// Der Verlauf eines Gesamtprojekts: seine Korrespondenz, Dateien und
/// Notizen — dazu die Meilensteine seiner Muster, mit deren Namen und
/// abschaltbar.
class GesamtprojektVerlauf extends ConsumerWidget {
  const GesamtprojektVerlauf({super.key, required this.gesamtprojekt});

  final Gesamtprojekt gesamtprojekt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = gesamtprojekt;
    final eintraege = ref.watch(projektEintraegeProvider(g.id));
    final muster = ref.watch(musterProvider(g.id)).valueOrNull ??
        const <EntwicklungsProjekt>[];
    final alle = ref.watch(alleEintraegeProvider).valueOrNull ??
        const <ProjektEintrag>[];
    final mitMustern = ref.watch(verlaufMitMusternProvider);
    final ziele = ref.watch(verschiebeZieleProvider(g.id));
    final dateien = {
      for (final d in ref.watch(projektDateienProvider(g.id)).valueOrNull ??
          const <EntwicklungsDatei>[])
        d.id: d,
    };
    final versionen = {
      for (final v in ref.watch(alleVersionenProvider).valueOrNull ??
          const <RezepturVersion>[])
        v.id: v,
    };
    return eintraege.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: HinweisBox(
          fehlerText(e),
          art: StatusArt.fehler,
          titel: 'Der Verlauf ließ sich nicht laden',
          auswaehlbar: true,
        ),
      ),
      data: (liste) {
        final z = gesamtprojektVerlauf(
          liste,
          muster,
          alle,
          mitMustern: mitMustern,
        );
        final meilensteine =
            gesamtprojektVerlauf(const [], muster, alle).eintraege.length;
        return VerlaufInhalt(
          zielId: g.id,
          eintraege: z.eintraege,
          herkunft: z.herkunft,
          dateien: dateien,
          versionen: versionen,
          ziele: ziele,
          schalter: meilensteine == 0
              ? null
              : (
                  label: 'Meilensteine der Muster ($meilensteine)',
                  icon: Icons.science_outlined,
                  an: mitMustern,
                  onChanged: (an) =>
                      ref.read(verlaufMitMusternProvider.notifier).state = an,
                ),
        );
      },
    );
  }
}

/// Wählt ein Projekt, das noch für sich steht — Projekte desselben Kunden
/// zuerst.
class _ProjektWahlDialog extends StatelessWidget {
  const _ProjektWahlDialog({required this.projekte, this.kunde});

  final List<EntwicklungsProjekt> projekte;
  final String? kunde;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final k = kunde?.trim().toLowerCase() ?? '';
    bool gleich(EntwicklungsProjekt p) =>
        k.isNotEmpty && (p.kunde ?? '').trim().toLowerCase() == k;
    final liste = [
      ...projekte.where(gleich),
      ...projekte.where((p) => !gleich(p)),
    ];
    return SimpleDialog(
      title: const Text('Projekt als Muster aufnehmen'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(
            'Das Projekt wird ein Muster dieses Gesamtprojekts — mit allem, '
            'was es hat.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420, maxWidth: 460),
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final p in liste)
                  SimpleDialogOption(
                    key: ValueKey('aufnehmen-${p.id}'),
                    onPressed: () => Navigator.of(context).pop(p),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          [
                            if ((p.kunde ?? '').trim().isNotEmpty)
                              p.kunde!.trim(),
                            ProjektStatus.aus(p.status).label,
                          ].join(' · '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 4, 16, 0),
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Abbrechen'),
            ),
          ),
        ),
      ],
    );
  }
}
