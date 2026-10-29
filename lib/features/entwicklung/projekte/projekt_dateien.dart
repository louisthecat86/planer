import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/services/auto_backup_trigger.dart';
import '../../../core/theme/app_stil.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/fehler_text.dart';
import '../../../core/utils/format.dart';
import '../daten/dateien.dart';
import '../mail/mail_ablage.dart';
import 'datei_aktionen.dart';
import 'gesamtprojekt_dialoge.dart';
import 'gesamtprojekt_modell.dart';
import 'projekt_repository.dart';

/// Wählt eine Datei und legt sie als Eintrag „Datei" in den Verlauf.
Future<void> dateiAlsEintrag(
  BuildContext context,
  WidgetRef ref,
  String projektId,
) async {
  final datei = await dateiWaehlen(context);
  if (datei == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final ablage = ref.read(mailAblageProvider);
  final sicherung = ref.read(autoBackupTriggerProvider);
  try {
    // Eine Mail (.msg, .eml) kommt als E-Mail in den Verlauf.
    final bericht = await ablage.ablegen(projektId, [datei]);
    sicherung.fireDebounced(reason: 'Datei abgelegt');
    if (bericht.mails > 0 || bericht.doppelt.isNotEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(bericht.text)));
    }
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('Die Datei ließ sich nicht ablegen: ${fehlerText(e)}'),
      ),
    );
  }
}

/// Legt gezogene Dateien und Mails in den Verlauf des Projekts und sagt,
/// was dort angekommen ist.
Future<void> projektAblage(
  BuildContext context,
  WidgetRef ref,
  String projektId,
  List<AblageDatei> dateien,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final ablage = ref.read(mailAblageProvider);
  final sicherung = ref.read(autoBackupTriggerProvider);
  final bericht = await ablage.ablegen(projektId, dateien);
  sicherung.fireDebounced(reason: 'Abgelegt');
  messenger.showSnackBar(SnackBar(content: Text(bericht.text)));
}

/// Fragt, wohin eine Datei verschoben werden soll, und verschiebt sie —
/// hängt sie an einem Eintrag im Verlauf, wandert er mit.
Future<void> dateiVerschiebenFragen(
  BuildContext context,
  WidgetRef ref,
  EntwicklungsDatei datei,
  List<VerschiebeZiel> ziele, {
  bool mitEintrag = false,
}) async {
  final ziel = await zielWaehlen(
    context,
    [
      for (final z in ziele)
        if (z.id != datei.projektId) z,
    ],
    titel: '„${datei.name}" verschieben',
    hinweis: mitEintrag ? 'Der Eintrag im Verlauf wandert mit.' : null,
  );
  if (ziel == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref
        .read(projektRepositoryProvider)
        .dateiVerschieben(datei.id, ziel.id);
    ref
        .read(autoBackupTriggerProvider)
        .fireDebounced(reason: 'Datei verschoben');
    messenger.showSnackBar(SnackBar(content: Text(verschobenText(ziel))));
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Verschieben fehlgeschlagen: ${fehlerText(e)}')),
    );
  }
}

/// Löscht eine Datei nach Rückfrage — auch aus Verlauf und Produktfoto.
Future<void> dateiLoeschen(
  BuildContext context,
  WidgetRef ref,
  EntwicklungsDatei datei,
) async {
  final ja = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Datei löschen?'),
      content: Text(
        '„${datei.name}" wird gelöscht. Der Eintrag im Verlauf bleibt, nur '
        'ohne Datei.',
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
  await ref.read(entwicklungDateienProvider).loeschen(datei.id);
  await ref.read(projektRepositoryProvider).dateiVerweiseEntfernen(datei.id);
  ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Datei gelöscht');
}

/// Eine Datei als Zeile mit Öffnen, Speichern, Verschieben und Löschen.
class DateiZeile extends ConsumerWidget {
  const DateiZeile({
    super.key,
    required this.datei,
    this.zusatz,
    this.loeschbar = true,
    this.onVerschieben,
  });

  final EntwicklungsDatei datei;

  /// Grauer Text unter dem Namen, etwa der Eintrag, zu dem sie gehört.
  final String? zusatz;

  final bool loeschbar;

  /// Verschieben ins Gesamtprojekt oder zu einem Muster — null: geht nicht.
  final VoidCallback? onVerschieben;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final unter = [
      groesseText(datei.groesse),
      Format.datum(datei.createdAt),
      if (zusatz != null && zusatz!.isNotEmpty) zusatz!,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(dateiSymbol(datei.name, datei.mimeTyp), size: 20, color: grau),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  datei.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  unter,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: grau),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Öffnen',
            icon: const Icon(Icons.open_in_new, size: 18),
            onPressed: () => dateiOeffnen(context, ref, datei),
          ),
          IconButton(
            tooltip: 'Speichern unter …',
            icon: const Icon(Icons.save_alt, size: 18),
            onPressed: () => dateiSpeichernUnter(context, ref, datei),
          ),
          if (onVerschieben != null)
            IconButton(
              tooltip: 'Verschieben …',
              icon: const Icon(Icons.drive_file_move_outline, size: 18),
              onPressed: onVerschieben,
            ),
          if (loeschbar)
            IconButton(
              tooltip: 'Löschen',
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => dateiLoeschen(context, ref, datei),
            ),
        ],
      ),
    );
  }
}

/// Alle Dateien eines Projekts — bei einem Muster darunter die
/// Unterlagen seines Gesamtprojekts.
class ProjektDateien extends StatelessWidget {
  const ProjektDateien({super.key, required this.projekt});

  final EntwicklungsProjekt projekt;

  @override
  Widget build(BuildContext context) => DateienListe(
        zielId: projekt.id,
        bildDateiId: projekt.bildDateiId,
        gesamtprojektId: projekt.gesamtprojektId,
      );
}

/// Wählt eine Datei für ein Muster und fragt, ob sie ins Gesamtprojekt
/// gehört oder nur zum Muster.
Future<void> _hinzufuegen(
  BuildContext context,
  WidgetRef ref,
  Gesamtprojekt g,
  EntwicklungsProjekt muster,
) async {
  final d = await dateiWaehlen(context);
  if (d == null || !context.mounted) return;
  final ziel = await ablageZielFragen(
    context,
    gesamtprojekt: g,
    muster: muster,
    dateien: [d],
  );
  if (ziel == null || !context.mounted) return;
  await projektAblage(context, ref, ziel, [d]);
}

/// Die Dateien eines Projekts oder Gesamtprojekts [zielId]. Gehört es zu
/// einem Gesamtprojekt ([gesamtprojektId]: beim Muster das, zu dem es
/// gehört, beim Gesamtprojekt es selbst), lassen sich Dateien dorthin
/// oder zu einem anderen Muster verschieben; ein Muster zeigt darunter die
/// Unterlagen des Gesamtprojekts.
class DateienListe extends ConsumerWidget {
  const DateienListe({
    super.key,
    required this.zielId,
    this.bildDateiId,
    this.gesamtprojektId,
  });

  final String zielId;

  /// Das Produktfoto — es ist in der Liste gekennzeichnet.
  final String? bildDateiId;
  final String? gesamtprojektId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final gid = gesamtprojektId;
    final istMuster = gid != null && gid != zielId;
    final dateien = ref.watch(projektDateienProvider(zielId));
    final eintraege = ref.watch(projektEintraegeProvider(zielId)).valueOrNull ??
        const <ProjektEintrag>[];
    final ziele = gid == null
        ? const <VerschiebeZiel>[]
        : ref.watch(verschiebeZieleProvider(gid));
    final ausGesamt = istMuster
        ? ref.watch(projektDateienProvider(gid)).valueOrNull ??
            const <EntwicklungsDatei>[]
        : const <EntwicklungsDatei>[];
    final gesamtEintraege = istMuster
        ? ref.watch(projektEintraegeProvider(gid)).valueOrNull ??
            const <ProjektEintrag>[]
        : const <ProjektEintrag>[];
    // Beim Muster fragt „Datei hinzufügen", wohin die Datei gehört (F46).
    final gesamt =
        istMuster ? ref.watch(gesamtprojektProvider(gid)).valueOrNull : null;
    final muster =
        istMuster ? ref.watch(projektProvider(zielId)).valueOrNull : null;
    Map<String, ProjektEintrag> zuEintrag(List<ProjektEintrag> liste) => {
          for (final e in liste)
            if (e.dateiId != null) e.dateiId!: e,
        };
    final eigeneEintraege = zuEintrag(eintraege);
    final fremdeEintraege = zuEintrag(gesamtEintraege);
    VoidCallback? verschieben(
      EntwicklungsDatei d,
      Map<String, ProjektEintrag> zu,
    ) =>
        ziele.length < 2
            ? null
            : () => dateiVerschiebenFragen(
                  context,
                  ref,
                  d,
                  ziele,
                  mitEintrag: zu.containsKey(d.id),
                );
    Widget kasten(List<Widget> zeilen) => Material(
          color: theme.colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: AppMasse.ecken,
            side: BorderSide(color: theme.colorScheme.outline),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            child: Column(children: zeilen),
          ),
        );
    return dateien.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: HinweisBox(
          fehlerText(e),
          art: StatusArt.fehler,
          titel: 'Die Dateien ließen sich nicht laden',
          auswaehlbar: true,
        ),
      ),
      data: (liste) {
        final summe = liste.fold<int>(0, (s, d) => s + d.groesse);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${liste.length} '
                    '${liste.length == 1 ? 'Datei' : 'Dateien'} · '
                    '${groesseText(summe)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => muster == null || gesamt == null
                      ? dateiAlsEintrag(context, ref, zielId)
                      : _hinzufuegen(context, ref, gesamt, muster),
                  icon: const Icon(Icons.attach_file, size: 18),
                  label: const Text('Datei hinzufügen'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const HinweisBox(
              'Dateien liegen verschlüsselt in der Datenbank und wandern so '
              'ins Backup. Zum Öffnen wird eine Datei entschlüsselt in einen '
              'temporären Ordner gelegt, den das Sperren wieder leert.',
            ),
            const SizedBox(height: 10),
            if (liste.isEmpty)
              const LeerHinweis(
                'Noch keine Dateien. Hänge Datenblätter, Fotos oder Mails an '
                'Einträge im Verlauf — oder lege sie hier ab.',
                icon: Icons.attach_file,
              )
            else
              kasten([
                for (final d in liste)
                  DateiZeile(
                    datei: d,
                    zusatz: d.id == bildDateiId
                        ? 'Produktfoto'
                        : eigeneEintraege[d.id] == null
                            ? null
                            : 'Verlauf: ${eigeneEintraege[d.id]!.titel}',
                    onVerschieben: verschieben(d, eigeneEintraege),
                  ),
              ]),
            if (ausGesamt.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Unterlagen aus dem Gesamtprojekt '
                      '(${ausGesamt.length})',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              kasten([
                for (final d in ausGesamt)
                  DateiZeile(
                    key: ValueKey('gesamt-datei-${d.id}'),
                    datei: d,
                    loeschbar: false,
                    zusatz: fremdeEintraege[d.id] == null
                        ? 'Gesamtprojekt'
                        : 'Gesamtprojekt · ${fremdeEintraege[d.id]!.titel}',
                    onVerschieben: verschieben(d, fremdeEintraege),
                  ),
              ]),
            ],
          ],
        );
      },
    );
  }
}
