import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/database_provider.dart';
import '../../../core/services/auto_backup_trigger.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/fehler_text.dart';
import 'zutaten_navision.dart';

/// Öffnet den Abgleich des Zutatenkatalogs mit der Artikelübersicht aus
/// Navision.
Future<void> zutatenNavisionStarten(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const ZutatenNavisionDialog(),
    );

/// Welche Produktbuchungsgruppen sind Zutaten? Zeigt, wie viele Artikel
/// daraus im Katalog fehlen, und legt sie an.
class ZutatenNavisionDialog extends ConsumerStatefulWidget {
  const ZutatenNavisionDialog({super.key});

  @override
  ConsumerState<ZutatenNavisionDialog> createState() =>
      _ZutatenNavisionDialogState();
}

class _ZutatenNavisionDialogState extends ConsumerState<ZutatenNavisionDialog> {
  late final ZutatenNavision _dienst =
      ZutatenNavision(ref.read(databaseProvider));

  List<NavisionGruppe>? _gruppen;
  final Set<String> _gewaehlt = {};
  ZutatenAbgleich? _abgleich;
  bool _arbeitet = false;
  String? _fehler;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    try {
      final gruppen = await _dienst.gruppen();
      final gemerkt = await _dienst.gewaehlteGruppen();
      // Nur, was es im eingelesenen Stand noch gibt.
      final da = {for (final g in gruppen) g.gruppe};
      final gewaehlt = gemerkt.where(da.contains).toSet();
      final abgleich = await _dienst.abgleich(gewaehlt);
      if (!mounted) return;
      setState(() {
        _gruppen = gruppen;
        _gewaehlt
          ..clear()
          ..addAll(gewaehlt);
        _abgleich = abgleich;
      });
    } catch (e) {
      if (mounted) setState(() => _fehler = fehlerText(e));
    }
  }

  Future<void> _umschalten(String gruppe, bool an) async {
    setState(() {
      an ? _gewaehlt.add(gruppe) : _gewaehlt.remove(gruppe);
    });
    final stand = {..._gewaehlt};
    try {
      final abgleich = await _dienst.abgleich(stand);
      // Inzwischen weitergeklickt: Das Ergebnis gehört zur alten Auswahl.
      if (!mounted || !_gleich(stand, _gewaehlt)) return;
      setState(() => _abgleich = abgleich);
    } catch (e) {
      if (mounted) setState(() => _fehler = fehlerText(e));
    }
  }

  static bool _gleich(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  Future<void> _anlegen() async {
    final abgleich = _abgleich;
    if (abgleich == null || abgleich.neu.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _arbeitet = true;
      _fehler = null;
    });
    try {
      await _dienst.gruppenMerken(_gewaehlt);
      final n = await _dienst.anlegen(abgleich.neu);
      ref
          .read(autoBackupTriggerProvider)
          .fireDebounced(reason: 'Zutaten aus Navision angelegt');
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
            n == 1
                ? '1 Zutat aus Navision angelegt — „nicht gepflegt", bis '
                    'ihre Angaben eingetragen sind.'
                : '$n Zutaten aus Navision angelegt — „nicht gepflegt", '
                    'bis ihre Angaben eingetragen sind.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _arbeitet = false;
          _fehler = 'Anlegen fehlgeschlagen: ${fehlerText(e)}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final gruppen = _gruppen;
    final abgleich = _abgleich;
    final neu = abgleich?.neu.length ?? 0;

    final Widget inhalt;
    if (gruppen == null) {
      inhalt = _fehler == null
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          : HinweisBox(_fehler!, art: StatusArt.fehler, auswaehlbar: true);
    } else if (gruppen.isEmpty) {
      inhalt = const HinweisBox(
        'Noch keine Artikelübersicht aus Navision eingelesen — oder ohne '
        'die Spalte „Produktbuchungsgruppe". Einlesen unter '
        '„Navision-Artikel"; danach stehen die Gruppen hier.',
        art: StatusArt.info,
      );
    } else {
      inhalt = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Welche Produktbuchungsgruppen sind Rohwaren und Zutaten? Ihre '
            'Artikel kommen in den Zutatenkatalog — nur die, deren '
            'Artikelnummer es dort noch nicht gibt. Bestehende Zutaten '
            'bleiben, wie sie sind.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 10),
          Flexible(
            child: Material(
              color: theme.colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final g in gruppen)
                    CheckboxListTile(
                      key: ValueKey('zutaten-navision-${g.gruppe}'),
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _gewaehlt.contains(g.gruppe),
                      onChanged: _arbeitet
                          ? null
                          : (an) => _umschalten(g.gruppe, an ?? false),
                      title: Text(g.gruppe),
                      secondary: Text('${g.artikel} Artikel', style: grau),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _gewaehlt.isEmpty
                ? 'Noch keine Gruppe gewählt.'
                : '$neu neu · ${abgleich?.vorhanden ?? 0} gibt es schon',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (_fehler != null) ...[
            const SizedBox(height: 10),
            HinweisBox(_fehler!, art: StatusArt.fehler, auswaehlbar: true),
          ],
        ],
      );
    }

    return AlertDialog(
      title: const Text('Zutaten aus Navision'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
        child: SizedBox(width: 520, child: inhalt),
      ),
      actions: [
        TextButton(
          onPressed: _arbeitet ? null : () => Navigator.of(context).pop(),
          child: const Text('Schließen'),
        ),
        FilledButton(
          key: const ValueKey('zutaten-navision-anlegen'),
          onPressed: _arbeitet || neu == 0 ? null : _anlegen,
          child: Text(
            neu == 0
                ? 'Nichts anzulegen'
                : neu == 1
                    ? '1 Zutat anlegen'
                    : '$neu Zutaten anlegen',
          ),
        ),
      ],
    );
  }
}
