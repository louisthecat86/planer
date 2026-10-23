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

/// Eine Datei als Zeile mit Öffnen, Speichern und Löschen.
class DateiZeile extends ConsumerWidget {
  const DateiZeile({
    super.key,
    required this.datei,
    this.zusatz,
    this.loeschbar = true,
  });

  final EntwicklungsDatei datei;

  /// Grauer Text unter dem Namen, etwa der Eintrag, zu dem sie gehört.
  final String? zusatz;

  final bool loeschbar;

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

/// Alle Dateien eines Projekts.
class ProjektDateien extends ConsumerWidget {
  const ProjektDateien({super.key, required this.projekt});

  final EntwicklungsProjekt projekt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dateien = ref.watch(projektDateienProvider(projekt.id));
    final eintraege =
        ref.watch(projektEintraegeProvider(projekt.id)).valueOrNull ??
            const <ProjektEintrag>[];
    final zuEintrag = {
      for (final e in eintraege)
        if (e.dateiId != null) e.dateiId!: e,
    };
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
                  onPressed: () => dateiAlsEintrag(context, ref, projekt.id),
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
              Material(
                color: theme.colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: AppMasse.ecken,
                  side: BorderSide(color: theme.colorScheme.outline),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                  child: Column(
                    children: [
                      for (final d in liste)
                        DateiZeile(
                          datei: d,
                          zusatz: d.id == projekt.bildDateiId
                              ? 'Produktfoto'
                              : zuEintrag[d.id] == null
                                  ? null
                                  : 'Verlauf: ${zuEintrag[d.id]!.titel}',
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
