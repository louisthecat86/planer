import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/entwicklung.dart';
import '../../../core/database/database.dart';
import '../../../core/services/auto_backup_trigger.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/ui/foto_kachel.dart';
import '../../../core/utils/fehler_text.dart';
import '../../../core/utils/format.dart';
import '../daten/dateien.dart';
import '../freigabe/produktfoto_artikel.dart';
import 'datei_aktionen.dart';
import 'produkt_foto.dart' show produktfotoZumArtikel;
import 'projekt_repository.dart';

// Der Foto-Eingang der Produktentwicklung: die Musterfotos, die mit der
// App „Planer Erfassung" aufgenommen und unter Einstellungen →
// Handy-Erfassung eingelesen wurden. Auf dem Handy bekommt ein Musterfoto
// nur eine Bezeichnung — Projekte und Kunden stehen dort nicht. Hier wird
// es einem Projekt zugeordnet und ist danach eine Datei dieses Projekts.
//
// Die Fotos liegen wie alle Dateien der Produktentwicklung verschlüsselt
// in der Datenbank, unter der „Projekt"-ID [kEntwicklungFotoEingang].

/// Die Musterfotos, die noch keinem Projekt zugeordnet sind — das neueste
/// zuerst.
final fotoEingangProvider = StreamProvider.autoDispose<List<EntwicklungsDatei>>(
  (ref) => ref
      .watch(projektRepositoryProvider)
      .dateienBeobachten(kEntwicklungFotoEingang),
);

/// Wohin ein Musterfoto kommt.
typedef FotoZiel = ({
  String id,
  String name,
  bool gesamtprojekt,
  bool alsProduktfoto,
});

/// Der Foto-Eingang auf der Übersicht — nur zu sehen, wenn etwas darin
/// liegt.
class FotoEingang extends ConsumerWidget {
  const FotoEingang({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fotos = ref.watch(fotoEingangProvider).valueOrNull ?? const [];
    if (fotos.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Bereich(
        key: const ValueKey('foto-eingang'),
        titel: 'Foto-Eingang',
        icon: Icons.photo_camera_outlined,
        untertitel: '${fotos.length == 1 ? '1 Musterfoto' : '${fotos.length} '
            'Musterfotos'} vom Handy — einem Projekt zuordnen',
        innenAbstand: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final f in fotos) _FotoZeile(foto: f)],
        ),
      ),
    );
  }
}

class _FotoZeile extends ConsumerWidget {
  const _FotoZeile({required this.foto});

  final EntwicklungsDatei foto;

  /// Der Name ohne Endung.
  String get _titel => foto.name.replaceFirst(RegExp(r'\.jpe?g$'), '');

  Future<void> _zuordnen(BuildContext context, WidgetRef ref) async {
    final ziel = await showDialog<FotoZiel>(
      context: context,
      builder: (_) => _ZielDialog(titel: _titel),
    );
    if (ziel == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(projektRepositoryProvider);
    final uebernahme = ref.read(produktfotoUebernahmeProvider);
    try {
      await repo.dateiVerschieben(foto.id, ziel.id);
      String? dazu;
      if (ziel.alsProduktfoto && !ziel.gesamtprojekt) {
        // Ein früheres Produktfoto bleibt als Datei beim Projekt. Ist das
        // Muster schon freigegeben, kommt das Foto auch zum Artikel.
        await repo.produktfotoSetzen(ziel.id, foto.id);
        dazu = await produktfotoZumArtikel(uebernahme, ziel.id);
      }
      ref
          .read(autoBackupTriggerProvider)
          .fireDebounced(reason: 'Musterfoto zugeordnet');
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            ziel.alsProduktfoto && !ziel.gesamtprojekt
                ? [
                    'Das Foto ist jetzt das Produktfoto von „${ziel.name}".',
                    if (dazu != null) dazu,
                  ].join(' ')
                : 'Das Foto liegt jetzt bei den Dateien von '
                    '„${ziel.name}" — dort lässt es sich auch als '
                    'Produktfoto nehmen.',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Zuordnen fehlgeschlagen: ${fehlerText(e)}'),
        ),
      );
    }
  }

  Future<void> _loeschen(BuildContext context, WidgetRef ref) async {
    final ja = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Musterfoto löschen?'),
        content: Text('„$_titel" wird gelöscht.'),
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
    if (ja != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(entwicklungDateienProvider).loeschen(foto.id);
      ref
          .read(autoBackupTriggerProvider)
          .fireDebounced(reason: 'Musterfoto gelöscht');
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Löschen fehlgeschlagen: ${fehlerText(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final inhalt = ref.watch(dateiInhaltProvider(foto.id));
    final bild = inhalt.valueOrNull;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          FotoKachel(
            bild: bild,
            fehlt: inhalt.hasError || (inhalt.hasValue && bild == null),
            onTap: bild == null
                ? null
                : () => fotoGrossZeigen(
                      context,
                      bild: bild,
                      titel: _titel,
                      untertitel: 'eingelesen am '
                          '${Format.datum(foto.createdAt)}',
                    ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _titel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'eingelesen am ${Format.datum(foto.createdAt)} · '
                  '${groesseText(foto.groesse)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            key: ValueKey('foto-zuordnen-${foto.id}'),
            onPressed: () => _zuordnen(context, ref),
            child: const Text('Zuordnen …'),
          ),
          IconButton(
            key: ValueKey('foto-loeschen-${foto.id}'),
            tooltip: 'Löschen',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _loeschen(context, ref),
          ),
        ],
      ),
    );
  }
}

/// Fragt, zu welchem Projekt ein Musterfoto gehört.
class _ZielDialog extends ConsumerStatefulWidget {
  const _ZielDialog({required this.titel});

  final String titel;

  @override
  ConsumerState<_ZielDialog> createState() => _ZielDialogState();
}

class _ZielDialogState extends ConsumerState<_ZielDialog> {
  String _suche = '';
  bool _alsProduktfoto = false;

  bool _passt(String name, String? kunde, [String? nummer]) {
    final q = _suche.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.toLowerCase().contains(q) ||
        (kunde ?? '').toLowerCase().contains(q) ||
        (nummer ?? '').toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final gesamt = ref.watch(gesamtprojekteProvider).valueOrNull ?? const [];
    final projekte = ref.watch(projekteProvider).valueOrNull ?? const [];
    final gruppe = {for (final g in gesamt) g.id: g.name};

    String? unter(EntwicklungsProjekt p) {
      final teile = [
        if (gruppe[p.gesamtprojektId] case final g?) g,
        if ((p.kunde ?? '').isNotEmpty) p.kunde!,
      ];
      return teile.isEmpty ? null : teile.join(' · ');
    }

    final zeilen = <Widget>[
      // Zuerst die Muster — dorthin gehört ein Musterfoto meist.
      for (final p in projekte)
        if (_passt(p.name, p.kunde, p.artikelnummer))
          ListTile(
            key: ValueKey('foto-ziel-${p.id}'),
            dense: true,
            leading: const Icon(Icons.science_outlined, size: 20),
            title: Text(p.name),
            subtitle: unter(p) == null ? null : Text(unter(p)!),
            onTap: () => Navigator.of(context).pop<FotoZiel>(
              (
                id: p.id,
                name: p.name,
                gesamtprojekt: false,
                alsProduktfoto: _alsProduktfoto,
              ),
            ),
          ),
      for (final g in gesamt)
        if (_passt(g.name, g.kunde))
          ListTile(
            key: ValueKey('foto-ziel-${g.id}'),
            dense: true,
            leading: const Icon(Icons.folder_outlined, size: 20),
            title: Text(g.name),
            subtitle: Text(
              [
                'Gesamtprojekt',
                if ((g.kunde ?? '').isNotEmpty) g.kunde!,
              ].join(' · '),
            ),
            onTap: () => Navigator.of(context).pop<FotoZiel>(
              (
                id: g.id,
                name: g.name,
                gesamtprojekt: true,
                alsProduktfoto: false,
              ),
            ),
          ),
    ];

    return AlertDialog(
      title: Text('„${widget.titel}" zuordnen'),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: 520,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                key: const ValueKey('foto-ziel-suche'),
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search, size: 20),
                  hintText: 'Projekt, Kunde oder Artikelnummer',
                  isDense: true,
                ),
                onChanged: (t) => setState(() => _suche = t),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: zeilen.isEmpty
                  ? Center(
                      child: Text(
                        projekte.isEmpty && gesamt.isEmpty
                            ? 'Es gibt noch kein Projekt.'
                            : 'Kein Projekt gefunden.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: grau,
                        ),
                      ),
                    )
                  : ListView(children: zeilen),
            ),
            const Divider(height: 1),
            CheckboxListTile(
              key: const ValueKey('foto-ziel-produktfoto'),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: _alsProduktfoto,
              onChanged: (an) => setState(() => _alsProduktfoto = an ?? false),
              title: const Text('Als Produktfoto des Musters verwenden'),
              subtitle: const Text(
                'Sonst liegt das Foto bei den Dateien des Projekts.',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
      ],
    );
  }
}
