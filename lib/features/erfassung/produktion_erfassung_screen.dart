import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/druck/druck_fenster.dart';
import '../../core/providers/database_provider.dart';
import '../../core/providers/daten_waechter.dart';
import '../../core/ui/bausteine.dart';
import '../../core/utils/datum.dart';
import '../../core/utils/fehler_text.dart';
import '../../core/utils/format.dart';
import '../../core/utils/kalenderwoche.dart';
import '../articles/article_detail_providers.dart'
    show productionHistoryProvider;
import '../articles/production_entry_dialog.dart';
import '../bedarf/bedarf_screen.dart' show heuteProvider;
import 'erfassung_druck.dart';
import 'geplante_produktion.dart';

// ---------------------------------------------------------------------------
// Modell + Provider
// ---------------------------------------------------------------------------

/// Die zu erfassende Woche (Montag). Standard: aktuelle Woche.
final erfassungWocheProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return tagPlus(now, -(now.weekday - 1));
});

/// Alle geplanten Produktionen (Ketten-Wurzeln) der gewählten Woche,
/// gruppiert nach Wochentag (Mo–Fr). Nur die WURZEL jeder Kette zählt —
/// eine Produktion wird einmal erfasst, nicht je Abteilungsschritt.
final erfassungWocheDatenProvider = FutureProvider<
    Map<DateTime, List<GeplanteProduktion>>>((ref) async {
  final db = ref.watch(databaseProvider);
  // Hält sich selbst aktuell — siehe daten_waechter.dart.
  neuLadenBeiAenderung(ref, db);
  final montag = ref.watch(erfassungWocheProvider);
  return geplanteProduktionenLaden(db, montag, tagPlus(montag, 5));
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

const _wochentage = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag'];

class ProduktionErfassungScreen extends ConsumerStatefulWidget {
  const ProduktionErfassungScreen({super.key});

  @override
  ConsumerState<ProduktionErfassungScreen> createState() =>
      _ProduktionErfassungScreenState();
}

class _ProduktionErfassungScreenState
    extends ConsumerState<ProduktionErfassungScreen> {
  /// Das Druckfenster ist offen oder wird gerade geöffnet.
  bool _druckLaeuft = false;

  @override
  void initState() {
    super.initState();
    // Beim Öffnen frische Daten ziehen — so erscheinen Produktionen, die
    // gerade erst in der Planung angelegt wurden, sofort, ohne dass man
    // erst die Woche wechseln muss.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(erfassungWocheDatenProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final montag = ref.watch(erfassungWocheProvider);
    final async = ref.watch(erfassungWocheDatenProvider);
    final heute = ref.watch(heuteProvider);
    final kw = isoKalenderwoche(montag);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Produktionserfassung'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Erfassungsliste drucken',
            onPressed: () => _drucken(montag),
          ),
          // Was an der Anlage mit der App „Planer Erfassung" erfasst wurde,
          // kommt hier herein — derselbe Weg wie über die Einstellungen.
          if (MediaQuery.sizeOf(context).width < 720)
            IconButton(
              icon: const Icon(Icons.phone_android),
              tooltip: 'Vom Handy einlesen',
              onPressed: () => context.pushNamed('handy'),
            )
          else
            TextButton.icon(
              onPressed: () => context.pushNamed('handy'),
              icon: const Icon(Icons.phone_android, size: 18),
              label: const Text('Vom Handy einlesen'),
            ),
          const SizedBox(width: 8),
        ],
        // Die Woche als eigene Leiste unter dem Titel: links und rechts
        // blättern, in der Mitte die Kalenderwoche.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: theme.colorScheme.outline),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'Vorige Woche',
                  onPressed: () => ref
                      .read(erfassungWocheProvider.notifier)
                      .state = tagPlus(montag, -7),
                ),
                Expanded(
                  child: Text(
                    'KW $kw · ab ${_datum(montag)}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'Nächste Woche',
                  onPressed: () => ref
                      .read(erfassungWocheProvider.notifier)
                      .state = tagPlus(montag, 7),
                ),
              ],
            ),
          ),
        ),
      ),
      body: async.when(
        // Beim Neuladen bleibt der Stand stehen.
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(
          padding: const EdgeInsets.all(14),
          children: [
            HinweisBox(
              'Fehler: ${fehlerText(e)}',
              art: StatusArt.fehler,
              auswaehlbar: true,
            ),
          ],
        ),
        data: (gruppen) {
          if (gruppen.isEmpty) {
            // ConstrainedBox hat keinen const-Konstruktor — deshalb steht
            // `const` erst innen.
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: const LeerHinweis(
                  'Für diese Woche ist nichts geplant. Sobald im Wochenplan '
                  'Produktionen stehen, erscheinen sie hier zum Erfassen der '
                  'Ist-Daten.',
                  icon: Icons.fact_check_outlined,
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
            children: [
              for (var i = 0; i < 5; i++)
                ..._tagAbschnitt(
                  tagPlus(montag, i),
                  _wochentage[i],
                  gruppen[tagPlus(montag, i)] ?? const [],
                  heute,
                ),
            ],
          );
        },
      ),
    );
  }

  /// Ein Tag als Bereich — leer, wenn an dem Tag nichts zu erfassen ist.
  List<Widget> _tagAbschnitt(
    DateTime tag,
    String name,
    List<GeplanteProduktion> produktionen,
    DateTime heute,
  ) {
    if (produktionen.isEmpty) return const [];
    final n = produktionen.length;

    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Bereich(
          titel: '$name, ${_tagMonat(tag)}',
          untertitel: '$n ${n == 1 ? 'Produktion' : 'Produktionen'}',
          aktionen: [
            // Was hier steht, ist noch nicht erfasst. Liegt der Tag schon
            // zurück, ist das nachzuholen.
            if (tag.isBefore(heute))
              const StatusMarke('noch nicht erfasst', art: StatusArt.warnung)
            else if (tag == heute)
              const StatusMarke('heute', art: StatusArt.info),
            const SizedBox(width: 6),
          ],
          innenAbstand: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, prod) in produktionen.indexed)
                _ProduktionZeile(
                  prod: prod,
                  erste: i == 0,
                  onErfassen: () => _erfassen(prod),
                ),
            ],
          ),
        ),
      ),
    ];
  }

  /// Öffnet das Druckfenster mit der Erfassungsliste der Woche: die
  /// geplanten Produktionen mit Spalten, in die die Ist-Werte von Hand
  /// kommen.
  Future<void> _drucken(DateTime montag) async {
    // Ein Doppelklick öffnete sonst zwei Fenster.
    if (_druckLaeuft) return;
    _druckLaeuft = true;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final gruppen = await ref.read(erfassungWocheDatenProvider.future);
      if (!mounted) return;
      await druckFensterOeffnen(
        context,
        erfassungDruckAuftrag(montag: montag, gruppen: gruppen),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
            'Die Erfassungsliste ließ sich nicht drucken. (${fehlerText(e)})',
          ),
        ),
      );
    } finally {
      _druckLaeuft = false;
    }
  }

  Future<void> _erfassen(GeplanteProduktion prod) async {
    // Dasselbe Formular wie im Artikel. Vorgeschlagen werden die geplante
    // ROHWARE — die Menge der ersten Abteilung, mit allen Teilen — und die
    // geplante Fleischeinwaage; die Fertigmenge wird erst nach dem Wiegen
    // eingetragen.
    final erfasst = await ProductionEntryDialog.show(
      context,
      prod.task.productId,
      vorschlagRohKg: prod.rohKg,
      vorschlagFleischKg: prod.fleischKg,
      vorschlagDatum: prod.task.datum,
      vorschlagStart: prod.task.startZeit,
    );
    if (erfasst) {
      ref.invalidate(erfassungWocheDatenProvider);
      ref.invalidate(productionHistoryProvider(prod.task.productId));
    }
  }
}

/// Eine geplante Produktion als Zeile im Bereich ihres Tages. Antippen
/// öffnet das Formular zum Erfassen.
class _ProduktionZeile extends StatelessWidget {
  const _ProduktionZeile({
    required this.prod,
    required this.erste,
    required this.onErfassen,
  });

  final GeplanteProduktion prod;

  /// Erste Zeile des Tages: ohne Linie darüber — dort steht schon die des
  /// Kopfes.
  final bool erste;
  final VoidCallback onErfassen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final farben = theme.colorScheme;
    final zahlen = theme.textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    // Material statt Farbe am Container: Die Hover- und Tipp-Welle des
    // InkWell malt auf das nächste Material.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onErfassen,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
          decoration: BoxDecoration(
            border: erste
                ? null
                : Border(
                    top: BorderSide(color: farben.outlineVariant),
                  ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 78,
                child: Text(
                  prod.artikelNummer,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: zahlen?.copyWith(
                    color: farben.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  prod.artikelName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${Format.kg(prod.mengeKg)} geplant',
                style: zahlen?.copyWith(color: farben.onSurfaceVariant),
              ),
              const SizedBox(width: 16),
              FilledButton.tonalIcon(
                onPressed: onErfassen,
                icon: const Icon(Icons.edit_note, size: 18),
                label: const Text('Erfassen'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Formatierung
// ---------------------------------------------------------------------------

String _zwei(int n) => n.toString().padLeft(2, '0');

/// „14.10."
String _tagMonat(DateTime d) => '${_zwei(d.day)}.${_zwei(d.month)}.';

/// „12.10.2026"
String _datum(DateTime d) => '${_tagMonat(d)}${d.year}';
