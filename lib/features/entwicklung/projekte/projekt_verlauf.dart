// `show Value`: drift bringt eine eigene Klasse `Column` mit.
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/services/auto_backup_trigger.dart';
import '../../../core/theme/app_stil.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/fehler_text.dart';
import '../../../core/utils/format.dart';
import '../daten/dateien.dart';
import '../daten/entwicklung_repository.dart';
import '../etikett/etikett_dialog.dart';
import '../haccp/prozess_kette.dart';
import '../haccp/prozess_modell.dart';
import 'datei_aktionen.dart';
import 'entwicklungsstrang.dart';
import 'entwicklungsweg_ansicht.dart';
import 'faellig.dart';
import 'gesamtprojekt_dialoge.dart';
import 'gesamtprojekt_modell.dart';
import 'projekt_dateien.dart';
import 'projekt_modell.dart';
import 'projekt_repository.dart';
import 'projekt_rezeptur.dart' show projektRezepturZeigen;
import 'zeitstrahl.dart';

/// Der zuletzt verwendete Name für Einträge und Kommentare — gilt, bis
/// die App schließt.
final entwicklungNameProvider = StateProvider<String>((ref) => '');

/// Die Stände der Rezepturen eines Projekts zur Auswahl („Zu Stand").
final projektStandWahlenProvider =
    Provider.autoDispose.family<List<StandWahl>, String>((ref, projektId) {
  final rezepturen =
      ref.watch(projektRezepturenProvider(projektId)).valueOrNull ??
          const <Rezeptur>[];
  final versionen =
      ref.watch(alleVersionenProvider).valueOrNull ?? const <RezepturVersion>[];
  return standWahlen(rezepturen, versionen);
});

/// Wie der Verlauf aussieht: als Zeitstrahl, als Entwicklungsweg (von
/// der Idee über die Stände zum Artikel) oder als Liste der Karten.
enum VerlaufAnsicht {
  zeitstrahl(
    'Zeitstrahl',
    Icons.timeline,
    'Alle Einträge nach Datum, der älteste links — mit den Phasen',
  ),
  entwicklungsweg(
    'Entwicklungsweg',
    Icons.route_outlined,
    'Von der Idee über die Rezepturstände bis zum Artikel',
  ),
  liste(
    'Liste',
    Icons.view_agenda_outlined,
    'Alle Einträge als Karten, der neueste zuerst',
  );

  const VerlaufAnsicht(this.label, this.icon, this.hinweis);

  final String label;
  final IconData icon;

  /// Was die Ansicht zeigt — als Hinweis am Knopf.
  final String hinweis;
}

/// Die gewählte Ansicht des Verlaufs — gilt, bis die App schließt.
final verlaufAnsichtProvider =
    StateProvider<VerlaufAnsicht>((ref) => VerlaufAnsicht.zeitstrahl);

/// Die Arten, die Zeitstrahl und Liste zeigen — gilt, bis die App
/// schließt.
final verlaufFilterProvider =
    StateProvider<Set<EintragArt>>((ref) => EintragArt.values.toSet());

/// Ob der Verlauf eines Musters die Einträge seines Gesamtprojekts zeigt
/// (F45) — gilt, bis die App schließt.
final verlaufMitGesamtprojektProvider = StateProvider<bool>((ref) => true);

/// Ob der Verlauf eines Gesamtprojekts die Meilensteine seiner Muster
/// zeigt — gilt, bis die App schließt.
final verlaufMitMusternProvider = StateProvider<bool>((ref) => true);

/// Ein Schalter über dem Verlauf, der Einträge aus einem anderen Verlauf
/// zeigt oder verbirgt.
typedef HerkunftSchalter = ({
  String label,
  IconData icon,
  bool an,
  ValueChanged<bool> onChanged,
});

/// Die Farbe eines Eintragsstatus.
StatusArt eintragStatusArt(EintragStatus s) => switch (s) {
      EintragStatus.offen => StatusArt.warnung,
      EintragStatus.erledigt => StatusArt.ok,
    };

/// Der Verlauf eines Projekts: Meilensteine, Rezepturstände, Mails,
/// Parameter, Dateien und Notizen — als Zeitstrahl (ältester links), als
/// Entwicklungsweg oder als Liste (neuester zuerst). Gehört das Projekt
/// als Muster zu einem Gesamtprojekt, stehen dessen Einträge mit darin —
/// gekennzeichnet und abschaltbar (F45).
class ProjektVerlauf extends ConsumerWidget {
  const ProjektVerlauf({super.key, required this.projekt});

  final EntwicklungsProjekt projekt;

  /// „Datei ablegen" auf einem Muster: Wie beim Ziehen fragt die App, ob
  /// die Datei ins Gesamtprojekt gehört oder nur zum Muster (F46).
  Future<void> _dateiFuerMuster(
    BuildContext context,
    WidgetRef ref,
    Gesamtprojekt g,
  ) async {
    final d = await dateiWaehlen(context);
    if (d == null || !context.mounted) return;
    final ziel = await ablageZielFragen(
      context,
      gesamtprojekt: g,
      muster: projekt,
      dateien: [d],
    );
    if (ziel == null || !context.mounted) return;
    await projektAblage(context, ref, ziel, [d]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gid = projekt.gesamtprojektId;
    final g = gid == null
        ? null
        : ref.watch(gesamtprojektProvider(gid)).valueOrNull;
    final eintraege = ref.watch(projektEintraegeProvider(projekt.id));
    final mitGesamt = ref.watch(verlaufMitGesamtprojektProvider);
    final gesamt = gid == null
        ? const <ProjektEintrag>[]
        : ref.watch(projektEintraegeProvider(gid)).valueOrNull ??
            const <ProjektEintrag>[];
    final ziele = gid == null
        ? const <VerschiebeZiel>[]
        : ref.watch(verschiebeZieleProvider(gid));
    List<EntwicklungsDatei> dateienVon(String id) =>
        ref.watch(projektDateienProvider(id)).valueOrNull ??
        const <EntwicklungsDatei>[];
    final dateien = {
      for (final d in dateienVon(projekt.id)) d.id: d,
      if (gid != null)
        for (final d in dateienVon(gid)) d.id: d,
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
        final z = musterVerlauf(liste, gesamt, mitGesamtprojekt: mitGesamt);
        return VerlaufInhalt(
          zielId: projekt.id,
          eintraege: z.eintraege,
          herkunft: z.herkunft,
          dateien: dateien,
          versionen: versionen,
          phasen: statusJeEintrag(
            z.eintraege,
            ProjektStatus.aus(projekt.status),
          ),
          ziele: ziele,
          onDatei: g == null ? null : () => _dateiFuerMuster(context, ref, g),
          schalter: gesamt.isEmpty
              ? null
              : (
                  label: 'Aus dem Gesamtprojekt (${gesamt.length})',
                  icon: Icons.folder_outlined,
                  an: mitGesamt,
                  onChanged: (an) => ref
                      .read(verlaufMitGesamtprojektProvider.notifier)
                      .state = an,
                ),
          weg: (eintraege) => EntwicklungswegAnsicht(
            projekt: projekt,
            eintraege: eintraege,
            versionen: versionen,
            herkunft: z.herkunft,
          ),
        );
      },
    );
  }
}

/// Der Inhalt eines Verlaufs — eines Projekts oder eines Gesamtprojekts:
/// die Leiste mit Ansicht und Knöpfen, die Filter und die Einträge. Neue
/// Einträge und Dateien kommen nach [zielId].
class VerlaufInhalt extends ConsumerWidget {
  const VerlaufInhalt({
    super.key,
    required this.zielId,
    required this.eintraege,
    this.herkunft = const {},
    this.dateien = const {},
    this.versionen = const {},
    this.phasen = const {},
    this.ziele = const [],
    this.schalter,
    this.weg,
    this.onDatei,
  });

  /// Der Verlauf, in den neue Einträge kommen.
  final String zielId;

  /// Alle Einträge, der neueste zuerst.
  final List<ProjektEintrag> eintraege;

  /// Woher ein Eintrag aus einem anderen Verlauf kommt.
  final Map<String, String> herkunft;
  final Map<String, EntwicklungsDatei> dateien;
  final Map<String, RezepturVersion> versionen;

  /// Die Phase bei jedem Eintrag — leer: kein Phasenband.
  final Map<String, ProjektStatus> phasen;

  /// Wohin sich Einträge verschieben lassen.
  final List<VerschiebeZiel> ziele;

  /// Zeigt oder verbirgt die Einträge aus dem anderen Verlauf.
  final HerkunftSchalter? schalter;

  /// Der Entwicklungsweg — null: Den gibt es hier nicht.
  final Widget Function(List<ProjektEintrag> eintraege)? weg;

  /// „Datei ablegen" — null: Die Datei kommt nach [zielId].
  final VoidCallback? onDatei;

  Future<void> _neu(BuildContext context, WidgetRef ref) async {
    final eingabe = await showDialog<EintragEingabe>(
      context: context,
      builder: (_) => EintragDialog(
        name: ref.read(entwicklungNameProvider),
        staende: ref.read(projektStandWahlenProvider(zielId)),
      ),
    );
    if (eingabe == null || !context.mounted) return;
    try {
      final datei = eingabe.datei;
      final dateiId = datei == null
          ? null
          : await dateiAblegen(ref, datei, projektId: zielId);
      await ref.read(projektRepositoryProvider).eintragAnlegen(
            projektId: zielId,
            art: eingabe.art,
            titel: eingabe.titel,
            datum: eingabe.datum,
            benutzer: eingabe.benutzer,
            beschreibung: eingabe.beschreibung,
            status: eingabe.status,
            ziel: eingabe.ziel,
            dateiId: dateiId,
            versionId: eingabe.versionId,
          );
      if (eingabe.benutzer != null) {
        ref.read(entwicklungNameProvider.notifier).state = eingabe.benutzer!;
      }
      ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Eintrag');
    } catch (e) {
      if (context.mounted) _fehler(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Hält die Stände für „Zu Stand" bereit.
    ref.watch(projektStandWahlenProvider(zielId));
    final liste = eintraege;
    final ansichten = [
      for (final a in VerlaufAnsicht.values)
        if (a != VerlaufAnsicht.entwicklungsweg || weg != null) a,
    ];
    final gewaehlt = ref.watch(verlaufAnsichtProvider);
    final ansicht = ansichten.contains(gewaehlt) ? gewaehlt : ansichten.first;
    final filter = ref.watch(verlaufFilterProvider);
    // Die Arten, die vorkommen, mit ihrer Zahl — in fester Reihenfolge.
    final arten = <EintragArt, int>{
      for (final a in EintragArt.values)
        if (liste.any((e) => EintragArt.aus(e.art) == a))
          a: liste.where((e) => EintragArt.aus(e.art) == a).length,
    };
    final sichtbar = [
      for (final e in liste)
        if (filter.contains(EintragArt.aus(e.art))) e,
    ];
    // Die Phasen, die auf dem Zeitstrahl vorkommen, in ihrer Folge.
    final legende = {
      for (final a in phasenAbschnitte(zeitlichSortiert(sichtbar), phasen))
        a.status,
    }.toList();
    final s = schalter;
    final artFilter =
        ansicht != VerlaufAnsicht.entwicklungsweg && arten.length > 1;
    final wegBauen = weg;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _Leiste(
          anzahl: liste.length,
          ansicht: ansicht,
          ansichten: ansichten,
          onDatei: onDatei ?? () => dateiAlsEintrag(context, ref, zielId),
          onNeu: () => _neu(context, ref),
        ),
        if (artFilter || s != null) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (artFilter)
                for (final MapEntry(key: art, value: anzahl) in arten.entries)
                  FilterChip(
                    avatar: Icon(art.icon, size: 16),
                    label: Text('${art.label} ($anzahl)'),
                    selected: filter.contains(art),
                    onSelected: (an) =>
                        ref.read(verlaufFilterProvider.notifier).state = an
                            ? {...filter, art}
                            : (filter.toSet()..remove(art)),
                  ),
              if (s != null)
                FilterChip(
                  key: const ValueKey('verlauf-herkunft'),
                  avatar: Icon(s.icon, size: 16),
                  label: Text(s.label),
                  selected: s.an,
                  onSelected: s.onChanged,
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        if (liste.isEmpty)
          const LeerHinweis(
            'Noch keine Einträge.',
            icon: Icons.history,
          )
        else if (ansicht == VerlaufAnsicht.entwicklungsweg && wegBauen != null)
          wegBauen(liste)
        else if (sichtbar.isEmpty)
          const LeerHinweis(
            'Keine Einträge dieser Arten.',
            icon: Icons.filter_alt_outlined,
          )
        else if (ansicht == VerlaufAnsicht.zeitstrahl) ...[
          Zeitstrahl(
            eintraege: sichtbar,
            dateien: dateien,
            versionen: versionen,
            phasen: phasen,
            herkunft: herkunft,
            onTippen: (e) => eintragZeigen(
              context,
              projektId: e.projektId,
              eintragId: e.id,
              herkunft: herkunft[e.id],
              ziele: ziele,
            ),
          ),
          if (legende.isNotEmpty) ...[
            const SizedBox(height: 4),
            PhasenLegende(phasen: legende),
          ],
        ] else
          for (final e in sichtbar)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: EintragKarte(
                eintrag: e,
                datei: dateien[e.dateiId],
                version: versionen[e.versionId],
                herkunft: herkunft[e.id],
                ziele: ziele,
              ),
            ),
      ],
    );
  }
}

/// Über dem Verlauf: die Ansichten — beschriftet, erst ganz schmal nur
/// mit Symbol —, die Zahl der Einträge und die Knöpfe. Breit in einer
/// Zeile, sonst die Ansichten unter den Knöpfen.
class _Leiste extends ConsumerWidget {
  const _Leiste({
    required this.anzahl,
    required this.ansicht,
    required this.ansichten,
    required this.onDatei,
    required this.onNeu,
  });

  final int anzahl;
  final VerlaufAnsicht ansicht;

  /// Die Ansichten, die es hier gibt.
  final List<VerlaufAnsicht> ansichten;
  final VoidCallback onDatei;
  final VoidCallback onNeu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final wahl = SegmentedButton<VerlaufAnsicht>(
          key: const ValueKey('verlauf-ansicht'),
          segments: [
            for (final a in ansichten)
              ButtonSegment(
                value: a,
                icon: Icon(a.icon),
                label: c.maxWidth >= 520 ? Text(a.label) : null,
                tooltip: a.hinweis,
              ),
          ],
          selected: {ansicht},
          showSelectedIcon: false,
          onSelectionChanged: (s) =>
              ref.read(verlaufAnsichtProvider.notifier).state = s.first,
        );
        final zahl = Text(
          '$anzahl ${anzahl == 1 ? 'Eintrag' : 'Einträge'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        );
        final datei = OutlinedButton.icon(
          onPressed: onDatei,
          icon: const Icon(Icons.attach_file, size: 18),
          label: const Text('Datei ablegen'),
        );
        final neu = FilledButton.icon(
          onPressed: onNeu,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Neuer Eintrag'),
        );
        if (c.maxWidth >= 980) {
          return Row(
            children: [
              wahl,
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: zahl,
                    ),
                    datei,
                    neu,
                  ],
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: zahl),
                const SizedBox(width: 12),
                // In schmalen Fenstern rutschen die Knöpfe untereinander.
                Flexible(
                  flex: 3,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [datei, neu],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            wahl,
          ],
        );
      },
    );
  }
}

/// „Fällig bis …" an einem Eintrag — überfällig in der Farbe für Fehler.
class FaelligZeile extends StatelessWidget {
  const FaelligZeile({
    super.key,
    required this.text,
    this.ueberfaellig = false,
  });

  /// Wie es im Eintrag steht: „30.11.2026", „KW 48" oder ein Satz.
  final String text;
  final bool ueberfaellig;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final farbe = ueberfaellig
        ? AppFarben.von(context).fehler
        : theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          ueberfaellig ? Icons.event_busy_outlined : Icons.event_outlined,
          size: 14,
          color: farbe,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            ueberfaellig
                ? 'Fällig bis $text — überfällig'
                : 'Fällig bis $text',
            style: theme.textTheme.bodySmall?.copyWith(
              color: ueberfaellig ? farbe : null,
              fontWeight: ueberfaellig ? FontWeight.w600 : null,
            ),
          ),
        ),
      ],
    );
  }
}

void _fehler(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Speichern fehlgeschlagen: ${fehlerText(e)}')),
  );
}

/// Ein Eintrag im Verlauf als Karte.
class EintragKarte extends ConsumerWidget {
  const EintragKarte({
    super.key,
    required this.eintrag,
    this.datei,
    this.version,
    this.herkunft,
    this.ziele = const [],
    this.nachVerschieben,
  });

  final ProjektEintrag eintrag;

  /// Die angehängte Datei — null, wenn keine da ist.
  final EntwicklungsDatei? datei;

  /// Der Rezepturstand, um den es geht.
  final RezepturVersion? version;

  /// Woher der Eintrag kommt, wenn er in einem anderen Verlauf steht —
  /// etwa „Gesamtprojekt".
  final String? herkunft;

  /// Wohin sich der Eintrag verschieben lässt — der eigene Verlauf zählt
  /// nicht mit.
  final List<VerschiebeZiel> ziele;

  /// Nach dem Verschieben — etwa das Fenster schließen.
  final VoidCallback? nachVerschieben;

  /// Verschieben lassen sich Mails, Dateien und Notizen — Meilensteine,
  /// Rezepturstände und Parameter gehören zu ihrem Projekt.
  List<VerschiebeZiel> get _moeglich => switch (EintragArt.aus(eintrag.art)) {
        EintragArt.email || EintragArt.datei || EintragArt.notiz => [
            for (final z in ziele)
              if (z.id != eintrag.projektId) z,
          ],
        _ => const [],
      };

  Future<void> _verschieben(BuildContext context, WidgetRef ref) async {
    final mail = EintragArt.aus(eintrag.art) == EintragArt.email;
    final ziel = await zielWaehlen(
      context,
      _moeglich,
      titel: '„${eintrag.titel}" verschieben',
      hinweis: mail
          ? 'Die Mail wandert mit ihren Anhängen.'
          : datei == null
              ? null
              : 'Die Datei wandert mit.',
    );
    if (ziel == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(projektRepositoryProvider)
          .eintragVerschieben(eintrag.id, ziel.id);
      ref
          .read(autoBackupTriggerProvider)
          .fireDebounced(reason: 'Eintrag verschoben');
      nachVerschieben?.call();
      messenger.showSnackBar(SnackBar(content: Text(verschobenText(ziel))));
    } catch (e) {
      if (context.mounted) _fehler(context, e);
    }
  }

  Future<void> _bearbeiten(BuildContext context, WidgetRef ref) async {
    final eingabe = await showDialog<EintragEingabe>(
      context: context,
      builder: (_) => EintragDialog(
        eintrag: eintrag,
        staende: ref.read(projektStandWahlenProvider(eintrag.projektId)),
      ),
    );
    if (eingabe == null || !context.mounted) return;
    try {
      await ref.read(projektRepositoryProvider).eintragAendern(
            eintrag.id,
            EntwicklungProjektEintraegeCompanion(
              art: Value(eingabe.art.schluessel),
              titel: Value(eingabe.titel),
              datum: Value(eingabe.datum),
              benutzer: Value(eingabe.benutzer),
              beschreibung: Value(eingabe.beschreibung),
              status: Value(eingabe.status.schluessel),
              ziel: Value(eingabe.ziel),
              versionId: Value(eingabe.versionId),
            ),
          );
      ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Eintrag');
    } catch (e) {
      if (context.mounted) _fehler(context, e);
    }
  }

  /// Schaltet zwischen offen und erledigt um.
  Future<void> _umschalten(BuildContext context, WidgetRef ref) async {
    final neu = EintragStatus.aus(eintrag.status).umgekehrt;
    try {
      await ref.read(projektRepositoryProvider).eintragStatusSetzen(
            eintrag.id,
            neu,
          );
      ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Eintrag');
    } catch (e) {
      if (context.mounted) _fehler(context, e);
    }
  }

  Future<void> _kommentieren(BuildContext context, WidgetRef ref) async {
    final kommentar = await showDialog<Kommentar>(
      context: context,
      builder: (_) => KommentarDialog(name: ref.read(entwicklungNameProvider)),
    );
    if (kommentar == null || !context.mounted) return;
    try {
      await ref
          .read(projektRepositoryProvider)
          .kommentieren(eintrag.id, kommentar);
      ref.read(entwicklungNameProvider.notifier).state = kommentar.name;
      ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Kommentar');
    } catch (e) {
      if (context.mounted) _fehler(context, e);
    }
  }

  Future<void> _loeschen(BuildContext context, WidgetRef ref) async {
    final mitDatei = datei != null;
    final ja = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eintrag löschen?'),
        content: Text(
          mitDatei
              ? '„${eintrag.titel}" wird mit der angehängten Datei gelöscht.'
              : '„${eintrag.titel}" wird gelöscht.',
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
    final d = datei;
    if (d != null) {
      await ref.read(entwicklungDateienProvider).loeschen(d.id);
      await ref.read(projektRepositoryProvider).dateiVerweiseEntfernen(d.id);
    }
    await ref.read(projektRepositoryProvider).eintragLoeschen(eintrag.id);
    ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Eintrag');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final e = eintrag;
    final art = EintragArt.aus(e.art);
    // Hält die Stände für „Zu Stand" beim Bearbeiten bereit.
    ref.watch(projektStandWahlenProvider(e.projektId));
    final status = EintragStatus.aus(e.status);
    final kopfzeile = [
      Format.datum(e.datum),
      if ((e.benutzer ?? '').trim().isNotEmpty) e.benutzer!.trim(),
      art.label,
    ].join(' · ');
    final beschreibung = e.beschreibung?.trim() ?? '';
    final ziel = e.ziel?.trim() ?? '';
    final aenderungen = texteAus(e.aenderungen);
    final kommentare = Kommentar.listeAus(e.kommentare);
    final parameter =
        art == EintragArt.parameter ? Prozessparameter.aus(e.wert) : null;
    final v = version;
    final d = datei;

    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppMasse.ecken,
        side: BorderSide(color: theme.colorScheme.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: AppMasse.ecken,
              ),
              child: Icon(art.icon, size: 18, color: grau),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          e.titel,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (herkunft case final h?) ...[
                        const SizedBox(width: 8),
                        StatusMarke(
                          h,
                          key: const ValueKey('eintrag-herkunft'),
                          icon: h == kHerkunftGesamtprojekt
                              ? Icons.folder_outlined
                              : Icons.science_outlined,
                          hinweis: h == kHerkunftGesamtprojekt
                              ? 'Aus dem Verlauf des Gesamtprojekts'
                              : 'Aus dem Verlauf des Musters „$h"',
                        ),
                      ],
                      const SizedBox(width: 8),
                      StatusMarke(
                        status.label,
                        key: const ValueKey('eintrag-status-umschalten'),
                        art: eintragStatusArt(status),
                        hinweis: status == EintragStatus.offen
                            ? 'Antippen: erledigt'
                            : 'Antippen: wieder offen',
                        onTap: () => _umschalten(context, ref),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    kopfzeile,
                    style: theme.textTheme.bodySmall?.copyWith(color: grau),
                  ),
                  if (beschreibung.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    SelectableText(beschreibung),
                  ],
                  if (ziel.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    FaelligZeile(
                      text: ziel,
                      ueberfaellig: eintragUeberfaellig(
                        e,
                        heute: DateTime.now(),
                      ),
                    ),
                  ],
                  if (aenderungen.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    for (final a in aenderungen)
                      Text(
                        '• $a',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: grau,
                        ),
                      ),
                  ],
                  if (parameter != null && !parameter.leer) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Prozessparameter Version ${parameter.version} · '
                      '${prozessKurztext(parameter)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  if (e.versionId != null) ...[
                    const SizedBox(height: 4),
                    if (v == null)
                      Text(
                        'Der Rezepturstand ist nicht mehr da.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: grau,
                        ),
                      )
                    else
                      Wrap(
                        spacing: 4,
                        children: [
                          TextButton.icon(
                            // Im Reiter „Rezeptur".
                            onPressed: () => projektRezepturZeigen(
                              context,
                              e.projektId,
                              v.rezepturId,
                            ),
                            icon: const Icon(
                              Icons.menu_book_outlined,
                              size: 16,
                            ),
                            label: Text('Rezepturstand ${v.nummer} öffnen'),
                          ),
                          if (art == EintragArt.rezeptur)
                            TextButton.icon(
                              onPressed: () => etikettZeigen(context, v.id),
                              icon: const Icon(Icons.label_outline, size: 16),
                              label: const Text('Etikett'),
                            ),
                        ],
                      ),
                  ],
                  if (d != null) ...[
                    const SizedBox(height: 4),
                    DateiZeile(datei: d, loeschbar: false),
                  ] else if (e.dateiId != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Die Datei ist nicht mehr da.',
                      style: theme.textTheme.bodySmall?.copyWith(color: grau),
                    ),
                  ],
                  if (kommentare.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final (i, k) in kommentare.indexed)
                      _KommentarZeile(
                        kommentar: k,
                        onLoeschen: () => ref
                            .read(projektRepositoryProvider)
                            .kommentarLoeschen(e.id, i),
                      ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Mehr',
              icon: const Icon(Icons.more_vert, size: 18),
              onSelected: (wahl) {
                switch (wahl) {
                  case 'bearbeiten':
                    _bearbeiten(context, ref);
                  case 'umschalten':
                    _umschalten(context, ref);
                  case 'kommentieren':
                    _kommentieren(context, ref);
                  case 'verschieben':
                    _verschieben(context, ref);
                  case 'loeschen':
                    _loeschen(context, ref);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'umschalten',
                  child: Text(
                    status == EintragStatus.offen
                        ? 'Als erledigt markieren'
                        : 'Wieder auf offen setzen',
                  ),
                ),
                const PopupMenuItem(
                  value: 'kommentieren',
                  child: Text('Kommentieren'),
                ),
                const PopupMenuItem(
                  value: 'bearbeiten',
                  child: Text('Bearbeiten'),
                ),
                if (_moeglich.isNotEmpty)
                  const PopupMenuItem(
                    value: 'verschieben',
                    child: Text('Verschieben …'),
                  ),
                const PopupMenuItem(value: 'loeschen', child: Text('Löschen')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _KommentarZeile extends StatelessWidget {
  const _KommentarZeile({required this.kommentar, required this.onLoeschen});

  final Kommentar kommentar;
  final VoidCallback onLoeschen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final k = kommentar;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(left: BorderSide(color: theme.colorScheme.outline, width: 2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  [
                    if (k.name.trim().isNotEmpty) k.name.trim(),
                    Format.datum(k.datum),
                  ].join(' · '),
                  style: theme.textTheme.labelSmall?.copyWith(color: grau),
                ),
                const SizedBox(height: 2),
                SelectableText(k.text, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Kommentar löschen',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 14),
            onPressed: onLoeschen,
          ),
        ],
      ),
    );
  }
}

/// Was das Eintragsfenster zurückgibt.
class EintragEingabe {
  const EintragEingabe({
    required this.art,
    required this.titel,
    required this.datum,
    required this.status,
    this.benutzer,
    this.beschreibung,
    this.ziel,
    this.datei,
    this.versionId,
  });

  final EintragArt art;
  final String titel;
  final DateTime datum;
  final EintragStatus status;
  final String? benutzer;
  final String? beschreibung;

  /// „Fällig bis" — frei geschrieben: ein Datum, eine Kalenderwoche oder
  /// ein Satz.
  final String? ziel;

  /// Eine neu gewählte Datei — nur beim Anlegen.
  final GewaehlteDatei? datei;

  /// Der Rezepturstand, zu dem der Eintrag gehört — null: zu keinem.
  final String? versionId;
}

/// Neuer Eintrag oder Eintrag bearbeiten.
class EintragDialog extends StatefulWidget {
  const EintragDialog({
    super.key,
    this.eintrag,
    this.name = '',
    this.staende = const [],
  });

  /// Der Eintrag zum Bearbeiten — null: ein neuer.
  final ProjektEintrag? eintrag;

  /// Der Name, der beim neuen Eintrag vorbelegt ist.
  final String name;

  /// Die Stände des Projekts für „Zu Stand".
  final List<StandWahl> staende;

  @override
  State<EintragDialog> createState() => _EintragDialogState();
}

class _EintragDialogState extends State<EintragDialog> {
  late EintragArt _art;
  late EintragStatus _status;
  late DateTime _datum;
  late final TextEditingController _titel;
  late final TextEditingController _benutzer;
  late final TextEditingController _beschreibung;
  late final TextEditingController _ziel;
  GewaehlteDatei? _datei;
  String? _fehler;

  /// Der Stand, zu dem der Eintrag gehört — '' für keinen.
  late String _stand = widget.eintrag?.versionId ?? '';

  /// Arten, die man von Hand anlegt — Rezepturstände und Parameter
  /// entstehen beim Abschließen bzw. Speichern von selbst.
  static const List<EintragArt> _waehlbar = [
    EintragArt.meilenstein,
    EintragArt.notiz,
    EintragArt.email,
    EintragArt.datei,
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.eintrag;
    final heute = DateTime.now();
    _art = e == null ? EintragArt.meilenstein : EintragArt.aus(e.art);
    _status = e == null ? EintragStatus.offen : EintragStatus.aus(e.status);
    _datum = e?.datum ?? DateTime(heute.year, heute.month, heute.day);
    _titel = TextEditingController(text: e?.titel ?? '');
    _benutzer = TextEditingController(text: e?.benutzer ?? widget.name);
    _beschreibung = TextEditingController(text: e?.beschreibung ?? '');
    _ziel = TextEditingController(text: e?.ziel ?? '');
  }

  @override
  void dispose() {
    _titel.dispose();
    _benutzer.dispose();
    _beschreibung.dispose();
    _ziel.dispose();
    super.dispose();
  }

  Future<void> _datumWaehlen() async {
    final gewaehlt = await showDatePicker(
      context: context,
      initialDate: _datum,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (gewaehlt != null && mounted) setState(() => _datum = gewaehlt);
  }

  /// Der Tag für „Fällig bis" aus dem Kalender — steht schon einer im
  /// Feld, beginnt der Kalender dort.
  Future<void> _faelligWaehlen() async {
    final erster = DateTime(2000);
    final letzter = DateTime(2100);
    var start = faelligAm(_ziel.text, bezug: _datum) ?? _datum;
    if (start.isBefore(erster) || start.isAfter(letzter)) start = _datum;
    final gewaehlt = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: erster,
      lastDate: letzter,
      helpText: 'Fällig bis',
    );
    if (gewaehlt != null && mounted) {
      setState(() => _ziel.text = Format.datum(gewaehlt));
    }
  }

  Future<void> _dateiWaehlen() async {
    final d = await dateiWaehlen(context);
    if (d == null || !mounted) return;
    setState(() {
      _datei = d;
      if (_titel.text.trim().isEmpty) _titel.text = d.name;
    });
  }

  String? _oderNull(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  void _fertig() {
    final titel = _titel.text.trim();
    if (titel.isEmpty) {
      setState(() => _fehler = 'Bitte einen Titel eingeben.');
      return;
    }
    Navigator.of(context).pop(
      EintragEingabe(
        art: _art,
        titel: titel,
        datum: _datum,
        status: _status,
        benutzer: _oderNull(_benutzer),
        beschreibung: _oderNull(_beschreibung),
        ziel: _oderNull(_ziel),
        datei: _datei,
        versionId: _stand.isEmpty ? null : _stand,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final neu = widget.eintrag == null;
    final arten = _waehlbar.contains(_art) ? _waehlbar : [..._waehlbar, _art];
    final fehler = _fehler;
    final datei = _datei;
    final staende = widget.staende;
    return AlertDialog(
      title: Text(neu ? 'Neuer Eintrag' : 'Eintrag bearbeiten'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, minWidth: 360),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final a in arten)
                    ChoiceChip(
                      avatar: Icon(a.icon, size: 16),
                      label: Text(a.label),
                      selected: _art == a,
                      onSelected: (_) => setState(() => _art = a),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titel,
                autofocus: neu,
                decoration: const InputDecoration(labelText: 'Titel'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _datumWaehlen,
                      icon: const Icon(Icons.event_note, size: 18),
                      label: Text(Format.datum(_datum)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SegmentedButton<EintragStatus>(
                      key: const ValueKey('eintrag-status'),
                      showSelectedIcon: false,
                      // Ohne Symbole: So passen beide auch ins schmale
                      // Fenster.
                      segments: const [
                        ButtonSegment(
                          value: EintragStatus.offen,
                          label: Text('offen'),
                        ),
                        ButtonSegment(
                          value: EintragStatus.erledigt,
                          label: Text('erledigt'),
                        ),
                      ],
                      selected: {_status},
                      onSelectionChanged: (s) =>
                          setState(() => _status = s.first),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _benutzer,
                      decoration: const InputDecoration(labelText: 'Von'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('eintrag-faellig'),
                      controller: _ziel,
                      decoration: InputDecoration(
                        labelText: 'Fällig bis',
                        hintText: 'z. B. 30.11. oder KW 48',
                        suffixIcon: IconButton(
                          tooltip: 'Tag im Kalender wählen',
                          icon: const Icon(
                            Icons.edit_calendar_outlined,
                            size: 18,
                          ),
                          onPressed: _faelligWaehlen,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              // Ein Rezepturstand im Verlauf ist sein Stand selbst.
              if (_art != EintragArt.rezeptur &&
                  (staende.isNotEmpty || _stand.isNotEmpty)) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  key: const ValueKey('eintrag-stand'),
                  initialValue: _stand,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Zu Stand',
                    helperText: 'Worauf sich der Eintrag bezieht — etwa die '
                        'Rückmeldung zu einem Muster',
                  ),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('— keinem —')),
                    for (final w in staende)
                      DropdownMenuItem(
                        value: w.versionId,
                        child: Text(w.label, overflow: TextOverflow.ellipsis),
                      ),
                    if (_stand.isNotEmpty &&
                        !staende.any((w) => w.versionId == _stand))
                      DropdownMenuItem(
                        value: _stand,
                        child: const Text('ein Stand, der nicht mehr da ist'),
                      ),
                  ],
                  onChanged: (v) => setState(() => _stand = v ?? ''),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: _beschreibung,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(labelText: 'Beschreibung'),
              ),
              if (neu) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _dateiWaehlen,
                    icon: const Icon(Icons.attach_file, size: 18),
                    label: Text(
                      datei == null
                          ? 'Datei anhängen'
                          : '${datei.name} (${groesseText(datei.inhalt.length)})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              if (fehler != null) ...[
                const SizedBox(height: 10),
                Text(
                  fehler,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _fertig,
          child: Text(neu ? 'Anlegen' : 'Speichern'),
        ),
      ],
    );
  }
}

/// Ein Kommentar: Name und Text.
class KommentarDialog extends StatefulWidget {
  const KommentarDialog({super.key, this.name = ''});

  final String name;

  @override
  State<KommentarDialog> createState() => _KommentarDialogState();
}

class _KommentarDialogState extends State<KommentarDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.name);
  final _text = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _text.dispose();
    super.dispose();
  }

  void _fertig() {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(
      Kommentar(name: _name.text.trim(), text: text, datum: DateTime.now()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Kommentar'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, minWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Von'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _text,
              autofocus: true,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Kommentar'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(onPressed: _fertig, child: const Text('Hinzufügen')),
      ],
    );
  }
}
