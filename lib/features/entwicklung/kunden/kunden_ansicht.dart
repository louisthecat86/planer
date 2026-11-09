import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_stil.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/fehler_text.dart';
import '../daten/entwicklung_repository.dart';
import '../projekte/gesamtprojekt_modell.dart';
import '../projekte/gesamtprojekt_screen.dart' show oeffneGesamtprojekt;
import '../projekte/projekt_checkliste.dart';
import '../projekte/projekt_modell.dart';
import '../projekte/projekt_repository.dart';
import '../projekte/projekte_ansicht.dart' show oeffneProjekt, projektStatusArt;
import '../uebersicht/angeheftet.dart';
import '../uebersicht/uebersicht_modell.dart';
import 'kunden_modell.dart';

// Der Bereich „Kunden": je Kunde ein Ordner zum Aufklappen, darin seine
// Gesamtprojekte mit ihren Mustern und seine Projekte für sich — die in
// Arbeit zuerst. Die Ordner und Zeilen nutzt auch die Übersicht.

/// Die aufgeklappten Kundenordner (KundenOrdner.id) — gilt, bis die App
/// schließt, auf der Übersicht wie im Bereich „Kunden".
final aufgeklappteKundenProvider =
    StateProvider<Set<String>>((ref) => const <String>{});

/// Der Bereich „Kunden".
class KundenAnsicht extends ConsumerStatefulWidget {
  const KundenAnsicht({super.key, this.heute});

  /// Für Tests: der Tag, an dem gerechnet wird — sonst heute.
  final DateTime? heute;

  @override
  ConsumerState<KundenAnsicht> createState() => _KundenAnsichtState();
}

class _KundenAnsichtState extends ConsumerState<KundenAnsicht> {
  final _suche = TextEditingController();
  String _text = '';

  /// Nur Kunden mit Projekten in Arbeit.
  bool _nurInArbeit = false;

  @override
  void dispose() {
    _suche.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final projekte = ref.watch(projekteProvider);
    final gesamt = ref.watch(gesamtprojekteProvider);
    final fehler = [projekte, gesamt].where((a) => a.hasError).firstOrNull;
    if (fehler != null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          HinweisBox(
            fehlerText(fehler.error),
            art: StatusArt.fehler,
            titel: 'Die Kunden ließen sich nicht laden',
            auswaehlbar: true,
          ),
        ],
      );
    }
    if (!projekte.hasValue || !gesamt.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    final heute = widget.heute ?? DateTime.now();
    final aktivitaet = projektAktivitaet(
      projekte: projekte.requireValue,
      eintraege: ref.watch(alleEintraegeProvider).valueOrNull ?? const [],
      rezepturen: ref.watch(rezepturenProvider).valueOrNull ?? const [],
      versionen: ref.watch(alleVersionenProvider).valueOrNull ?? const [],
      zeilen: ref.watch(zeilenAenderungenProvider).valueOrNull ?? const {},
    );
    final checklisten = ref.watch(projektChecklistenProvider);
    final alle = kundenOrdner(
      projekte: projekte.requireValue,
      gesamtprojekte: gesamt.requireValue,
      aktivitaet: aktivitaet,
      suche: _text,
    );
    final sichtbar = [
      for (final o in alle)
        if (!_nurInArbeit || o.inArbeit > 0) o,
    ];
    final suche = _text.trim().isNotEmpty;
    final offen = ref.watch(aufgeklappteKundenProvider);
    final alleOffen = sichtbar.every((o) => offen.contains(o.id));
    final kunden = alle.where((o) => o.name != null).length;
    final suchfeld = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: TextField(
        key: const ValueKey('kunden-suche'),
        controller: _suche,
        decoration: InputDecoration(
          hintText: 'Suche nach Kunde, Projekt oder Artikelnummer …',
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: _text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, size: 16),
                  tooltip: 'Suche leeren',
                  onPressed: () {
                    _suche.clear();
                    setState(() => _text = '');
                  },
                ),
        ),
        onChanged: (v) => setState(() => _text = v),
      ),
    );
    final inArbeitFilter = FilterChip(
      key: const ValueKey('kunden-in-arbeit'),
      label: const Text('Nur mit Projekten in Arbeit'),
      selected: _nurInArbeit,
      onSelected: (w) => setState(() => _nurInArbeit = w),
    );
    final kundenZaehler = Text(
      kunden == 1 ? '1 Kunde' : '$kunden Kunden',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.right,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    final alleKnopf = TextButton(
      key: const ValueKey('kunden-alle'),
      // Bei einer Suche ist ohnehin alles aufgeklappt.
      onPressed: suche || sichtbar.isEmpty
          ? null
          : () => ref.read(aufgeklappteKundenProvider.notifier).state =
              alleOffen
                  ? const <String>{}
                  : {for (final o in sichtbar) o.id},
      child: Text(alleOffen ? 'Alle zuklappen' : 'Alle aufklappen'),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 720) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: suchfeld,
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [inArbeitFilter, kundenZaehler, alleKnopf],
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Flexible(child: suchfeld),
                  const SizedBox(width: 12),
                  inArbeitFilter,
                  const SizedBox(width: 12),
                  Expanded(child: kundenZaehler),
                  const SizedBox(width: 8),
                  alleKnopf,
                ],
              );
            },
          ),
        ),
        Expanded(
          child: sichtbar.isEmpty
              ? Center(
                  child: LeerHinweis(
                    alle.isEmpty && !suche
                        ? 'Noch keine Projekte — und damit keine Kunden.'
                        : 'Keine Treffer.',
                    icon: alle.isEmpty && !suche
                        ? Icons.folder_shared_outlined
                        : Icons.search_off,
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: sichtbar.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => KundenOrdnerKachel(
                    ordner: sichtbar[i],
                    heute: heute,
                    aktivitaet: aktivitaet,
                    checklisten: checklisten,
                    immerOffen: suche,
                  ),
                ),
        ),
      ],
    );
  }
}

/// Ein Kundenordner — zugeklappt eine Zeile mit Name und Zahlen,
/// aufgeklappt darunter seine Gesamtprojekte und Projekte.
class KundenOrdnerKachel extends ConsumerWidget {
  const KundenOrdnerKachel({
    super.key,
    required this.ordner,
    required this.heute,
    this.aktivitaet = const {},
    this.checklisten,
    this.immerOffen = false,
    this.rahmen = true,
  });

  final KundenOrdner ordner;
  final DateTime heute;

  /// Je Projekt die letzte Aktivität.
  final Map<String, DateTime> aktivitaet;
  final Map<String, ProjektCheckStand>? checklisten;

  /// Aufgeklappt, gleich was gemerkt ist — etwa bei einer Suche.
  final bool immerOffen;

  /// Mit eigenem Rand — in der Liste der Kunden; auf der Übersicht steht
  /// er ohne in einem Bereich.
  final bool rahmen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final farben = theme.colorScheme;
    final grau = farben.onSurfaceVariant;
    final gemerkt = ref.watch(aufgeklappteKundenProvider);
    final offen = immerOffen || gemerkt.contains(ordner.id);
    final ohne = ordner.name == null;

    void klappen() => ref.read(aufgeklappteKundenProvider.notifier).state =
        gemerkt.contains(ordner.id)
            ? ({...gemerkt}..remove(ordner.id))
            : {...gemerkt, ordner.id};

    final kopf = InkWell(
      key: ValueKey('kunde-${ordner.id}'),
      onTap: immerOffen ? null : klappen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
        child: Row(
          children: [
            Icon(
              offen ? Icons.folder_open : Icons.folder,
              size: 22,
              color: ohne ? grau : farben.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    ordner.name ?? 'Ohne Kunden',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: ohne ? grau : null,
                    ),
                  ),
                  Text(
                    ordner.zusammenfassung,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: grau),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              vorWieLange(ordner.zuletzt, heute),
              style: theme.textTheme.bodySmall?.copyWith(color: grau),
            ),
            const SizedBox(width: 4),
            Icon(offen ? Icons.expand_less : Icons.expand_more, color: grau),
          ],
        ),
      ),
    );

    final spalte = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        kopf,
        if (offen) ...[
          Divider(height: 1, color: farben.outlineVariant),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final p in ordner.punkte)
                  ...switch (p) {
                    EinzelProjekt(:final projekt) => [
                        ProjektKurzZeile(
                          projekt: projekt,
                          zuletzt: aktivitaet[projekt.id] ?? projekt.updatedAt,
                          heute: heute,
                          checkliste: checklisten?[projekt.id],
                        ),
                      ],
                    GesamtGruppe(:final gesamtprojekt, :final muster) => [
                        GesamtKurzZeile(
                          gesamtprojekt: gesamtprojekt,
                          muster: muster,
                          heute: heute,
                          zuletzt: [
                            gesamtprojektZuletzt(gesamtprojekt, muster),
                            for (final m in muster)
                              if (aktivitaet[m.id] case final a?) a,
                          ].reduce((a, b) => a.isAfter(b) ? a : b),
                        ),
                        for (final m in muster)
                          ProjektKurzZeile(
                            projekt: m,
                            zuletzt: aktivitaet[m.id] ?? m.updatedAt,
                            heute: heute,
                            checkliste: checklisten?[m.id],
                            eingerueckt: true,
                          ),
                      ],
                  },
              ],
            ),
          ),
        ],
      ],
    );
    if (!rahmen) return spalte;
    return Material(
      color: farben.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppMasse.ecken,
        side: BorderSide(color: farben.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: spalte,
    );
  }
}

/// Ein Projekt in einer Zeile: Name, darunter Nummer und Checkliste, dann
/// Status, wann sich zuletzt etwas getan hat, und die Nadel zum Anheften.
/// Antippen öffnet es.
class ProjektKurzZeile extends StatelessWidget {
  const ProjektKurzZeile({
    super.key,
    required this.projekt,
    required this.zuletzt,
    required this.heute,
    this.checkliste,
    this.zusatz,
    this.eingerueckt = false,
  });

  final EntwicklungsProjekt projekt;
  final DateTime zuletzt;
  final DateTime heute;
  final ProjektCheckStand? checkliste;

  /// Steht vorn in der zweiten Zeile — etwa der Kunde.
  final String? zusatz;

  /// Als Muster unter seinem Gesamtprojekt.
  final bool eingerueckt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final status = ProjektStatus.aus(projekt.status);
    final c = checkliste;
    final nummer = projekt.artikelnummer?.trim() ?? '';
    final unter = [
      if (zusatz case final z? when z.trim().isNotEmpty) z.trim(),
      if (nummer.isNotEmpty) 'Nr. $nummer',
      if (c != null && !status.ruht) 'Checkliste ${c.text}',
    ];
    return InkWell(
      key: ValueKey('projektzeile-${projekt.id}'),
      onTap: () => oeffneProjekt(context, projekt.id),
      child: Padding(
        padding: EdgeInsets.fromLTRB(eingerueckt ? 46 : 12, 3, 4, 3),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    projekt.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: status.ruht ? grau : null,
                    ),
                  ),
                  if (unter.isNotEmpty)
                    Text(
                      unter.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: grau),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            StatusMarke(status.label, art: projektStatusArt(status)),
            SizedBox(
              width: 96,
              child: Text(
                vorWieLange(zuletzt, heute),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: theme.textTheme.bodySmall?.copyWith(color: grau),
              ),
            ),
            const SizedBox(width: 4),
            AnheftenKnopf(projektId: projekt.id),
          ],
        ),
      ),
    );
  }
}

/// Ein Gesamtprojekt in einer Zeile: Name und was aus seinen Mustern
/// geworden ist. Antippen öffnet es.
class GesamtKurzZeile extends StatelessWidget {
  const GesamtKurzZeile({
    super.key,
    required this.gesamtprojekt,
    required this.muster,
    required this.zuletzt,
    required this.heute,
  });

  final Gesamtprojekt gesamtprojekt;
  final List<EntwicklungsProjekt> muster;
  final DateTime zuletzt;
  final DateTime heute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    return InkWell(
      key: ValueKey('gesamtzeile-${gesamtprojekt.id}'),
      onTap: () => oeffneGesamtprojekt(context, gesamtprojekt.id),
      child: Padding(
        // Rechts so weit eingerückt, dass die Zeit unter der der Projekte
        // steht — dort sitzt bei ihnen die Nadel.
        padding: const EdgeInsets.fromLTRB(12, 5, 40, 5),
        child: Row(
          children: [
            Icon(
              Icons.folder_copy_outlined,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    gesamtprojekt.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    musterZusammenfassung([
                      for (final m in muster) ProjektStatus.aus(m.status),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: grau),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 96,
              child: Text(
                vorWieLange(zuletzt, heute),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: theme.textTheme.bodySmall?.copyWith(color: grau),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
