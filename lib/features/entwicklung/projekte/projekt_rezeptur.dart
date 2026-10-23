// `show Value`: drift bringt eine eigene Klasse `Column` mit.
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/services/auto_backup_trigger.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/fehler_text.dart';
import '../daten/entwicklung_repository.dart';
import '../rezepturen/rezeptur_screen.dart';
import '../rezepturen/rezepturen_ansicht.dart'
    show NeueRezepturDialog, oeffneRezeptur;
import 'projekt_repository.dart';
import 'projekt_screen.dart' show ProjektReiter;

// Der Reiter „Rezeptur" eines Projekts: die Rezeptur gleich im Projekt —
// mit ihren Ständen, der Zusammensetzung und dem Ergebnis wie auf ihrer
// eigenen Seite. Hat das Projekt mehrere, wählt man sie oben.

/// Welche Rezeptur der Reiter „Rezeptur" eines Projekts zeigt — null: die
/// erste.
final projektRezepturWahlProvider =
    StateProvider.family<String?, String>((ref, projektId) => null);

/// Zeigt die Rezeptur [rezepturId] im Reiter „Rezeptur" des Projekts —
/// außerhalb einer Projektseite auf ihrer eigenen.
void projektRezepturZeigen(
  BuildContext context,
  String projektId,
  String rezepturId,
) {
  final reiter = DefaultTabController.maybeOf(context);
  if (reiter == null) {
    oeffneRezeptur(context, rezepturId);
    return;
  }
  ProviderScope.containerOf(context, listen: false)
      .read(projektRezepturWahlProvider(projektId).notifier)
      .state = rezepturId;
  reiter.animateTo(ProjektReiter.rezeptur.index);
}

/// Legt eine neue Rezeptur im Projekt an und zeigt sie.
Future<void> neueProjektRezeptur(
  BuildContext context,
  EntwicklungsProjekt projekt,
) async {
  final id = await showDialog<String>(
    context: context,
    builder: (_) => NeueRezepturDialog(
      projektId: projekt.id,
      vorschlag: projekt.name,
    ),
  );
  if (id == null || !context.mounted) return;
  projektRezepturZeigen(context, projekt.id, id);
}

/// Ordnet dem Projekt eine Rezeptur zu, die noch zu keinem gehört — gibt
/// ihre ID zurück, null ohne Wahl.
Future<String?> rezepturZuordnen(
  BuildContext context,
  WidgetRef ref,
  EntwicklungsProjekt projekt,
) async {
  final alle = await ref.read(rezepturenProvider.future);
  if (!context.mounted) return null;
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
  if (id == null) return null;
  try {
    await ref.read(entwicklungRepositoryProvider).rezepturAendern(
          id,
          EntwicklungRezepturenCompanion(projektId: Value(projekt.id)),
        );
    ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Rezeptur');
    return id;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Zuordnen fehlgeschlagen: ${fehlerText(e)}')),
      );
    }
    return null;
  }
}

/// Der Reiter „Rezeptur": die Rezeptur des Projekts — bei mehreren die
/// gewählte.
class ProjektRezeptur extends ConsumerStatefulWidget {
  const ProjektRezeptur({super.key, required this.projekt});

  final EntwicklungsProjekt projekt;

  @override
  ConsumerState<ProjektRezeptur> createState() => _ProjektRezepturState();
}

class _ProjektRezepturState extends ConsumerState<ProjektRezeptur>
    with AutomaticKeepAliveClientMixin {
  // Der gewählte Stand bleibt, wenn man zwischen den Reitern wechselt.
  @override
  bool get wantKeepAlive => true;

  void _waehle(String id) => ref
      .read(projektRezepturWahlProvider(widget.projekt.id).notifier)
      .state = id;

  Future<void> _zuordnen() async {
    final id = await rezepturZuordnen(context, ref, widget.projekt);
    if (id != null && mounted) _waehle(id);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final p = widget.projekt;
    final gewaehlt = ref.watch(projektRezepturWahlProvider(p.id));
    return ref.watch(projektRezepturenProvider(p.id)).when(
          skipLoadingOnReload: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: HinweisBox(
              fehlerText(e),
              art: StatusArt.fehler,
              titel: 'Die Rezepturen ließen sich nicht laden',
              auswaehlbar: true,
            ),
          ),
          data: (rezepturen) {
            if (rezepturen.isEmpty) {
              return Center(
                child: LeerHinweis(
                  'Noch keine Rezeptur im Projekt.',
                  icon: Icons.menu_book_outlined,
                  aktion: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        key: const ValueKey('projekt-rezeptur-neu'),
                        onPressed: () => neueProjektRezeptur(context, p),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Neue Rezeptur…'),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('projekt-rezeptur-zuordnen'),
                        onPressed: _zuordnen,
                        icon: const Icon(Icons.link, size: 18),
                        label: const Text('Vorhandene zuordnen…'),
                      ),
                    ],
                  ),
                ),
              );
            }
            final id = rezepturen.any((r) => r.id == gewaehlt)
                ? gewaehlt!
                : rezepturen.first.id;
            return RezepturScreen(
              key: ValueKey('projekt-rezeptur-$id'),
              rezepturId: id,
              eingebettet: true,
              kopf: rezepturen.length < 2
                  ? null
                  : _Wahl(
                      rezepturen: rezepturen,
                      gewaehlt: id,
                      onWahl: _waehle,
                    ),
              aktionen: [
                IconButton(
                  tooltip: 'Auf eigener Seite öffnen',
                  icon: const Icon(Icons.open_in_new, size: 18),
                  onPressed: () => oeffneRezeptur(context, id),
                ),
                IconButton(
                  key: const ValueKey('projekt-rezeptur-zuordnen'),
                  tooltip: 'Vorhandene Rezeptur zuordnen',
                  icon: const Icon(Icons.link, size: 18),
                  onPressed: _zuordnen,
                ),
                IconButton(
                  key: const ValueKey('projekt-rezeptur-neu'),
                  tooltip: 'Neue Rezeptur',
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: () => neueProjektRezeptur(context, p),
                ),
              ],
            );
          },
        );
  }
}

/// Die Rezepturen des Projekts zur Wahl.
class _Wahl extends StatelessWidget {
  const _Wahl({
    required this.rezepturen,
    required this.gewaehlt,
    required this.onWahl,
  });

  final List<Rezeptur> rezepturen;
  final String gewaehlt;
  final ValueChanged<String> onWahl;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final r in rezepturen)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  key: ValueKey('projekt-rezeptur-wahl-${r.id}'),
                  label: Text(r.name),
                  selected: r.id == gewaehlt,
                  onSelected: (_) => onWahl(r.id),
                ),
              ),
          ],
        ),
      );
}
