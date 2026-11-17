import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';
import '../../core/services/prozess_vorlagen.dart';
import '../../core/ui/bausteine.dart';
import '../../core/ui/rueckgaengig.dart';
import '../../core/utils/datei_wahl.dart';
import '../../core/utils/fehler_text.dart';
import 'vorlage_anzeige.dart';
import 'vorlage_bearbeiten.dart';
import 'vorlagen_zuordnen.dart';

/// Die Prozessvorlagen des Betriebs: anlegen, bearbeiten, als Datei
/// weitergeben und vielen Artikeln auf einmal zuordnen.
class ProzessvorlagenScreen extends ConsumerWidget {
  const ProzessvorlagenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(prozessVorlagenProvider);
    final vorlagen = async.valueOrNull ?? const <ProzessVorlage>[];

    Future<void> speichern(
      List<ProzessVorlage> neu,
      String grund,
    ) async {
      await ProzessVorlagenSpeicher.speichern(ref.read(databaseProvider), neu);
      ref.read(autoBackupTriggerProvider).fireDebounced(reason: grund);
    }

    Future<void> melde(String text) async {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text)));
    }

    Future<void> bearbeiten(ProzessVorlage v, {bool neu = false}) async {
      final geaendert = await vorlageBearbeiten(context, v);
      if (geaendert == null) return;
      await speichern(
        neu
            ? [...vorlagen, geaendert]
            : [
                for (final x in vorlagen)
                  if (x.id == geaendert.id) geaendert else x,
              ],
        neu ? 'Prozessvorlage angelegt' : 'Prozessvorlage geändert',
      );
    }

    Future<void> loeschen(ProzessVorlage v) async {
      final messenger = ScaffoldMessenger.of(context);
      final vorher = vorlagen;
      await speichern(
        [
          for (final x in vorlagen)
            if (x.id != v.id) x,
        ],
        'Prozessvorlage gelöscht',
      );
      geloeschtMelden(
        messenger,
        text: 'Vorlage „${v.name}" gelöscht.',
        zurueck: () => speichern(vorher, 'Prozessvorlage wiederhergestellt'),
      );
    }

    Future<void> verschieben(int i, int nach) {
      final neu = [...vorlagen];
      neu.insert(nach, neu.removeAt(i));
      return speichern(neu, 'Prozessvorlagen umsortiert');
    }

    Future<void> einlesen() async {
      try {
        final datei = await dateiWaehlen(
          art: EinleseArt.prozessVorlagen,
          endungen: const ['json'],
          titel: 'Prozessvorlagen einlesen',
        );
        final inhalt = datei?.inhalt;
        if (datei == null) return;
        if (inhalt == null) {
          await melde('Die Datei ließ sich nicht lesen.');
          return;
        }
        final db = ref.read(databaseProvider);
        final gelesen = anlagenZuordnen(
          vorlagenAusText(utf8.decode(inhalt, allowMalformed: true)),
          await db.select(db.machines).get(),
        );
        final bekannt = {for (final v in vorlagen) v.id};
        final ersetzt = gelesen.where((v) => bekannt.contains(v.id)).length;
        await speichern(
          vorlagenZusammenfuehren(vorlagen, gelesen),
          'Prozessvorlagen eingelesen',
        );
        await melde(
          '${gelesen.length} Vorlagen eingelesen'
          '${ersetzt > 0 ? ' — $ersetzt davon ersetzt' : ''}.',
        );
      } on FormatException catch (e) {
        await melde(e.message);
      } catch (e) {
        await melde('Einlesen fehlgeschlagen: ${fehlerText(e)}');
      }
    }

    Future<void> alsDatei() async {
      try {
        final pfad = await FilePicker.saveFile(
          dialogTitle: 'Prozessvorlagen speichern',
          fileName: 'Prozessvorlagen.json',
          type: FileType.custom,
          allowedExtensions: const ['json'],
        );
        if (pfad == null) return;
        final ziel = pfad.toLowerCase().endsWith('.json') ? pfad : '$pfad.json';
        await File(ziel).writeAsString(vorlagenAlsText(vorlagen), flush: true);
        await melde('Gespeichert: $ziel');
      } catch (e) {
        await melde('Speichern fehlgeschlagen: ${fehlerText(e)}');
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prozessvorlagen'),
        actions: [
          MenueKnopf(
            label: 'Datei',
            icon: Icons.swap_vert_rounded,
            eintraege: [
              MenueEintrag(
                'Vorlagen einlesen…',
                icon: Icons.file_open_outlined,
                aktion: einlesen,
              ),
              if (vorlagen.isNotEmpty)
                MenueEintrag(
                  'Als Datei speichern…',
                  icon: Icons.save_alt,
                  aktion: alsDatei,
                ),
            ],
          ),
          const SizedBox(width: 8),
          if (vorlagen.isNotEmpty)
            TextButton.icon(
              key: const ValueKey('vorlagen-zuordnen'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => VorlagenZuordnen(vorlagen: vorlagen),
                ),
              ),
              icon: const Icon(Icons.playlist_add_check, size: 18),
              label: const Text('Artikeln zuordnen'),
            ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              key: const ValueKey('vorlage-neu'),
              onPressed: () =>
                  bearbeiten(neueVorlage('Neue Vorlage'), neu: true),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Neue Vorlage'),
            ),
          ),
        ],
      ),
      body: async.isLoading && async.valueOrNull == null
          ? const Center(child: CircularProgressIndicator())
          : vorlagen.isEmpty
              ? const Center(
                  child: LeerHinweis(
                    'Noch keine Prozessvorlagen.\nEine Vorlage ist eine feste '
                    'Prozesskette für eine Art von Artikeln — am Artikel '
                    'gewählt, legt sie die Schritte an. Neu anlegen oder '
                    'eine Vorlagen-Datei einlesen.',
                    icon: Icons.account_tree_outlined,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    for (final (i, v) in vorlagen.indexed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 900),
                            child: Bereich(
                              key: ValueKey('vorlage-${v.id}'),
                              titel: v.name,
                              untertitel: '${v.schritte.length} Schritte · '
                                  '${stichwortText(v)}',
                              aktionen: [
                                IconButton(
                                  tooltip: 'Nach oben',
                                  onPressed: i == 0
                                      ? null
                                      : () => verschieben(i, i - 1),
                                  icon: const Icon(
                                    Icons.arrow_upward,
                                    size: 18,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Nach unten',
                                  onPressed: i == vorlagen.length - 1
                                      ? null
                                      : () => verschieben(i, i + 1),
                                  icon: const Icon(
                                    Icons.arrow_downward,
                                    size: 18,
                                  ),
                                ),
                                MenueKnopf(
                                  label: 'Mehr',
                                  icon: Icons.more_horiz,
                                  eintraege: [
                                    MenueEintrag(
                                      'Bearbeiten',
                                      icon: Icons.edit_outlined,
                                      aktion: () => bearbeiten(v),
                                    ),
                                    MenueEintrag(
                                      'Duplizieren',
                                      icon: Icons.copy_outlined,
                                      aktion: () => bearbeiten(
                                        v.kopie(
                                          id: neueVorlage('').id,
                                          name: '${v.name} (Kopie)',
                                        ),
                                        neu: true,
                                      ),
                                    ),
                                    MenueEintrag(
                                      'Löschen',
                                      icon: Icons.delete_outline,
                                      aktion: () => loeschen(v),
                                    ),
                                  ],
                                ),
                              ],
                              child: InkWell(
                                onTap: () => bearbeiten(v),
                                child: VorlagenSchritte(vorlage: v),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}
