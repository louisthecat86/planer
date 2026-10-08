// `hide Column`: drift hat eine eigene Klasse Column, die sonst mit dem
// Flutter-Widget kollidiert. Gebraucht wird drift für die
// Datumsvergleiche in den Abfragen (isBiggerOrEqualValue & Co. sind
// Erweiterungsmethoden und ohne diesen Import unsichtbar).
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';
import '../../core/services/backup_service.dart';
import '../../core/services/erledigt_service.dart';
import '../../core/services/tagesaufgaben_service.dart';
import '../../core/services/week_snapshot_service.dart' show montagDerWoche;
import '../../core/theme/app_stil.dart';
import '../../core/ui/bausteine.dart';
import '../../core/utils/format.dart';
import '../../core/utils/kalenderwoche.dart';
import '../../core/utils/zeit.dart';
import '../bedarf/bedarf_screen.dart' show bedarfProvider, heuteProvider;
import '../board/board_providers.dart' show tageskapazitaetJeAbteilung;

// ═══════════════════════════════════════════════════════════════════════════
// Daten der Tagesübersicht
// ═══════════════════════════════════════════════════════════════════════════

/// Ein Auftrag des heutigen Tages, so wie er im Board steht.
class _Auftrag {
  const _Auftrag({
    required this.abteilung,
    required this.productId,
    required this.nummer,
    required this.name,
    required this.mengeKg,
    required this.minuten,
    required this.erledigt,
  });

  final Abteilung? abteilung;

  /// null, wenn es den Artikel nicht mehr gibt — dann gibt es auch keine
  /// Stammdaten zum Öffnen.
  final String? productId;
  final String nummer;
  final String name;
  final double mengeKg;
  final double minuten;

  /// Wie im Board: von Hand abgehakt oder die Produktion ist erfasst.
  /// null = offen.
  final Erledigt? erledigt;
}

class _Auslastung {
  const _Auslastung(
    this.abteilung, {
    required this.produktion,
    required this.nebenzeit,
    required this.kapazitaet,
  });

  final Abteilung abteilung;

  /// Geplante Produktionszeit der Aufträge.
  final double produktion;

  /// Rüst-, Reinigungs- und sonstige Nebenzeiten. Sie blockieren dieselbe
  /// Anlage wie die Produktion — so rechnet auch das Board.
  final double nebenzeit;

  final double kapazitaet;

  double get belegt => produktion + nebenzeit;
  double get anteil => kapazitaet <= 0 ? 0 : belegt / kapazitaet;
}

enum _Art { warnung, info, gut }

class _Hinweis {
  const _Hinweis(this.art, this.text, {this.ziel, this.aktion});

  final _Art art;
  final String text;

  /// Route, zu der ein Tippen führt — null, wenn es nichts zu tun gibt.
  final String? ziel;
  final String? aktion;
}

class _Uebersicht {
  const _Uebersicht({
    required this.heute,
    required this.auftraege,
    required this.auslastung,
    required this.aufgaben,
    required this.hinweise,
  });

  final DateTime heute;
  final List<_Auftrag> auftraege;

  /// Sonstige Aufgaben des Tages — wie im Board je Abteilung, hier in
  /// einer Liste in der Reihenfolge der Abteilungen.
  final List<Tagesaufgabe> aufgaben;
  final List<_Auslastung> auslastung;
  final List<_Hinweis> hinweise;
}

/// Alles, was die Startseite zeigt, in einem Durchgang.
///
/// Gerechnet wird mit denselben Bausteinen wie in den Fachscreens —
/// Kapazität wie im Board, offener Bedarf wie im Bedarf-Screen, „erfasst"
/// wie in der Produktionserfassung. Eine zweite, eigene Rechnung würde
/// früher oder später abweichen.
///
/// `autoDispose`, damit die Übersicht beim nächsten Öffnen frisch geladen
/// wird. Kehrt man aus den Stammdaten eines Artikels zurück, lädt
/// [_oeffneArtikel] sie zusätzlich neu, weil die Startseite dabei im
/// Stapel bleibt.
/// Parameter ist der angezeigte Tag. Ohne Angabe (`null`) der heutige —
/// so bleibt „heute" die Voreinstellung und der Provider wird beim
/// Blättern für jeden Tag einzeln gehalten.
final _uebersichtProvider =
    FutureProvider.autoDispose.family<_Uebersicht, DateTime?>(
        (ref, gewaehlterTag) async {
  final db = ref.watch(databaseProvider);
  final DateTime heute = gewaehlterTag ?? ref.watch(heuteProvider);
  final montag = montagDerWoche(heute);
  // Kalenderarithmetik statt Duration: Über eine Zeitumstellung hinweg
  // wären 7 × 24 Stunden nicht genau eine Woche.
  final wochenEnde = DateTime(montag.year, montag.month, montag.day + 7);
  final morgen = DateTime(heute.year, heute.month, heute.day + 1);

  final tasks = await (db.select(db.productionTasks)
        ..where((t) => t.deletedAt.isNull())
        ..where((t) => t.status.isNotIn(const ['storniert']))
        ..where((t) => t.datum.isBiggerOrEqualValue(montag))
        ..where((t) => t.datum.isSmallerThanValue(wochenEnde)))
      .get();
  final produkte = await (db.select(db.products)
        ..where((p) => p.deletedAt.isNull()))
      .get();
  final produktVon = {for (final p in produkte) p.id: p};
  final historie = await (db.select(db.productionHistory)
        ..where((h) => h.deletedAt.isNull())
        ..where((h) => h.datum.isBiggerOrEqualValue(montag))
        ..where((h) => h.datum.isSmallerThanValue(wochenEnde)))
      .get();

  String tagKey(DateTime d) => '${d.year}-${d.month}-${d.day}';
  final erfasst = {
    for (final h in historie) '${h.productId}|${tagKey(h.datum)}',
  };
  bool istErfasst(String productId, DateTime d) =>
      erfasst.contains('$productId|${tagKey(d)}');
  bool istHeute(DateTime d) => !d.isBefore(heute) && d.isBefore(morgen);

  Abteilung? abteilungVon(String db) {
    for (final a in Abteilung.values) {
      if (a.dbValue == db) return a;
    }
    return null;
  }

  // ── Heute ─────────────────────────────────────────────────────────
  final heuteTasks = tasks.where((t) => istHeute(t.datum)).toList()
    ..sort((a, b) {
      final ia = abteilungVon(a.abteilung)?.index ?? 99;
      final ib = abteilungVon(b.abteilung)?.index ?? 99;
      if (ia != ib) return ia.compareTo(ib);
      return a.sortierung.compareTo(b.sortierung);
    });

  // Erledigt wie im Board: abgehakt, oder die Produktion ist erfasst —
  // dann jeder Schritt ihrer Kette, nicht nur der erste.
  final erledigt = await ErledigtService.stand(db, heuteTasks);
  final auftraege = [
    for (final t in heuteTasks)
      _Auftrag(
        abteilung: abteilungVon(t.abteilung),
        productId: produktVon.containsKey(t.productId) ? t.productId : null,
        nummer: produktVon[t.productId]?.artikelnummer ?? '—',
        name: produktVon[t.productId]?.artikelbezeichnung ?? 'Unbekannt',
        mengeKg: t.mengeKg,
        minuten: t.geplanteDauerMinuten,
        erledigt: erledigt[t.id],
      ),
  ];

  // ── Auslastung ────────────────────────────────────────────────────
  final kapazitaet =
      await tageskapazitaetJeAbteilung(db, wochenStart: montag);
  final produktion = <String, double>{};
  for (final t in heuteTasks) {
    produktion[t.abteilung] =
        (produktion[t.abteilung] ?? 0) + t.geplanteDauerMinuten;
  }

  // Rüst- und Reinigungszeiten. Sie hängen an einer Planungsspur, deren
  // Kennung mit der Abteilung beginnt („bratstrasse|<Anlage>"). Das Board
  // zählt sie voll in die Belegung, die Startseite deshalb auch — sonst
  // zeigte sie eine Abteilung als frei, die in Wahrheit voll ist.
  final nebenzeiten = await (db.select(db.zusatzzeiten)
        ..where((z) => z.deletedAt.isNull())
        ..where((z) => z.datum.isBiggerOrEqualValue(heute))
        ..where((z) => z.datum.isSmallerThanValue(morgen)))
      .get();
  final neben = <String, double>{};
  for (final z in nebenzeiten) {
    final abteilung = z.spurId.split('|').first;
    neben[abteilung] = (neben[abteilung] ?? 0) + z.minuten;
  }

  final auslastung = [
    for (final a in Abteilung.values)
      if ((kapazitaet[a.dbValue] ?? 0) > 0 ||
          (produktion[a.dbValue] ?? 0) > 0 ||
          (neben[a.dbValue] ?? 0) > 0)
        _Auslastung(
          a,
          produktion: produktion[a.dbValue] ?? 0,
          nebenzeit: neben[a.dbValue] ?? 0,
          kapazitaet: kapazitaet[a.dbValue] ?? 0,
        ),
  ];

  // ── Hinweise ──────────────────────────────────────────────────────
  final hinweise = <_Hinweis>[];

  // Vergangene Tage dieser Woche, an denen Produktionen noch nicht
  // erfasst sind. Ohne Erfassung lernt die Planung nichts dazu.
  for (var d = montag;
      d.isBefore(heute);
      d = DateTime(d.year, d.month, d.day + 1)) {
    if (d.weekday > DateTime.friday) continue;
    final offen = tasks.where(
      (t) =>
          t.parentTaskId == null &&
          tagKey(t.datum) == tagKey(d) &&
          !istErfasst(t.productId, d),
    );
    final n = offen.length;
    if (n == 0) continue;
    hinweise.add(
      _Hinweis(
        _Art.warnung,
        '${Format.wochentage[d.weekday - 1]} ${d.day}.${d.month}. ist noch '
        'nicht erfasst — $n ${n == 1 ? 'Produktion' : 'Produktionen'}',
        ziel: 'erfassung',
        aktion: 'Erfassen',
      ),
    );
  }

  for (final a in auslastung) {
    if (a.anteil <= 1) continue;
    hinweise.add(
      _Hinweis(
        _Art.warnung,
        '${a.abteilung.anzeigeName} ist heute überbucht '
        '(${(a.anteil * 100).round()} %)',
        ziel: 'board',
        aktion: 'Zum Board',
      ),
    );
  }

  final bedarfe = await ref.watch(bedarfProvider.future);
  final offeneBedarfe =
      bedarfe.where((b) => !b.erledigt && b.offenKg > 0.5).length;
  if (offeneBedarfe > 0) {
    hinweise.add(
      _Hinweis(
        _Art.info,
        offeneBedarfe == 1
            ? 'Ein Bedarf ist noch nicht vollständig eingeplant'
            : '$offeneBedarfe Bedarfe sind noch nicht vollständig eingeplant',
        ziel: 'bedarf',
        aktion: 'Bedarf',
      ),
    );
  }

  // Sonstige Aufgaben: die des Tages für die Karte, die liegen gebliebenen
  // der Woche für einen Hinweis.
  final aufgabenWoche = await TagesaufgabenService.fuerZeitraum(
    db,
    von: montag,
    bisExkl: wochenEnde,
  );
  final aufgabenHeute = [
    for (final e in aufgabenWoche.entries)
      if (e.key.$2 == heute) ...e.value,
  ]..sort((a, b) {
      final ia = abteilungVon(a.abteilung)?.index ?? 99;
      final ib = abteilungVon(b.abteilung)?.index ?? 99;
      if (ia != ib) return ia.compareTo(ib);
      return a.sortierung.compareTo(b.sortierung);
    });
  // Liegen geblieben: offen und ihr Tag ist vorbei. Vier Wochen zurück —
  // sonst verschwände am Montag still, was am Freitag offen blieb.
  final vorher = await TagesaufgabenService.fuerZeitraum(
    db,
    von: DateTime(heute.year, heute.month, heute.day - 28),
    bisExkl: heute,
  );
  final liegenGeblieben = [
    for (final liste in vorher.values) ...liste.where((a) => !a.erledigt),
  ]..sort((a, b) => a.datum.compareTo(b.datum));
  if (liegenGeblieben.isNotEmpty) {
    final n = liegenGeblieben.length;
    final d = liegenGeblieben.first.datum;
    final text = n == 1
        ? 'Eine Aufgabe aus den Vortagen ist noch offen — vom'
        : '$n Aufgaben aus den Vortagen sind noch offen — älteste vom';
    hinweise.add(
      _Hinweis(
        _Art.warnung,
        '$text ${Format.wochentage[d.weekday - 1]} ${d.day}.${d.month}.',
        ziel: 'board',
        aktion: 'Zum Board',
      ),
    );
  }

  final backup = await BackupService.getLatestBackup();
  if (backup == null) {
    hinweise.add(
      const _Hinweis(
        _Art.warnung,
        'Es gibt noch kein Backup',
        ziel: 'data',
        aktion: 'Sichern',
      ),
    );
  } else {
    final alter = DateTime.now().difference(backup.timestamp);
    hinweise.add(
      _Hinweis(
        alter.inDays >= 3 ? _Art.warnung : _Art.gut,
        'Letztes Backup ${_wann(backup.timestamp)}',
        ziel: alter.inDays >= 3 ? 'data' : null,
        aktion: alter.inDays >= 3 ? 'Sichern' : null,
      ),
    );
  }

  return _Uebersicht(
    heute: heute,
    auftraege: auftraege,
    auslastung: auslastung,
    aufgaben: aufgabenHeute,
    hinweise: hinweise,
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// Screen
// ═══════════════════════════════════════════════════════════════════════════

/// Startseite: der Tag auf einen Blick — was heute läuft, wie voll die
/// Abteilungen sind und was liegen geblieben ist.
///
/// Die Wege in die Fachbereiche stehen in der Navigationsleiste links
/// (siehe `AppRahmen`). Früher standen sie hier als farbige Kästen unter
/// der Übersicht.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// Angezeigter Tag. `null` heißt heute — dadurch wandert die Ansicht
  /// über Mitternacht automatisch mit, solange niemand geblättert hat.
  DateTime? _tag;

  bool get _istHeute => _tag == null;

  void _blaettere(int tage) {
    final DateTime basis = _tag ?? ref.read(heuteProvider);
    final neu = DateTime(basis.year, basis.month, basis.day + tage);
    final heute = ref.read(heuteProvider);
    setState(() {
      _tag = (neu.year == heute.year &&
              neu.month == heute.month &&
              neu.day == heute.day)
          ? null
          : neu;
    });
  }

  @override
  Widget build(BuildContext context) {
    final daten = ref.watch(_uebersichtProvider(_tag));
    // Ausdrücklich `DateTime`: Ohne den Typ leitet Dart aus `_tag` den
    // Rückgabetyp von `watch` als `DateTime?` ab.
    final DateTime tag = _tag ?? ref.watch(heuteProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Übersicht'),
        actions: [
          TextButton.icon(
            onPressed: () => _aktualisieren(ref),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Aktualisieren'),
          ),
          const SizedBox(width: 8),
          // Öffnet das Board gleich mit dem Planen-Fenster.
          FilledButton.icon(
            onPressed: () => context.goNamed('boardPlanen'),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Produkt planen'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, c) {
          final breit = c.maxWidth >= 1000;
          final rand = breit ? 24.0 : 16.0;
          return ListView(
            padding: EdgeInsets.fromLTRB(rand, 16, rand, 24),
            children: [
              _Kopf(
                tag: tag,
                istHeute: _istHeute,
                onZurueck: () => _blaettere(-1),
                onVor: () => _blaettere(1),
                onHeute: _istHeute ? null : () => setState(() => _tag = null),
              ),
              const SizedBox(height: 16),
              daten.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Bereich(
                  titel: 'Übersicht nicht verfügbar',
                  child: Text('$e'),
                ),
                data: (u) => _Tagesbereich(
                  uebersicht: u,
                  breit: breit,
                  istHeute: _istHeute,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

void _aktualisieren(WidgetRef ref) {
  ref
    ..invalidate(bedarfProvider)
    ..invalidate(_uebersichtProvider);
}

/// Öffnet die Stammdaten eines Artikels und lädt die Übersicht danach
/// neu: Im Artikel lässt sich eine Produktion erfassen, und die macht den
/// Auftrag grün.
Future<void> _oeffneArtikel(BuildContext context, String productId) async {
  // Vor dem Warten holen, damit nach der Rückkehr kein Kontext mehr nötig
  // ist. Verlässt man den Artikel über die Leiste statt zurück, endet das
  // Warten nicht — die Übersicht lädt beim nächsten Öffnen ohnehin neu.
  final container = ProviderScope.containerOf(context, listen: false);
  await context.pushNamed(
    'articleDetail',
    pathParameters: {'productId': productId},
  );
  container
    ..invalidate(bedarfProvider)
    ..invalidate(_uebersichtProvider);
}

// ── Kopf ────────────────────────────────────────────────────────────────

/// Der angezeigte Tag, zum Blättern direkt daneben.
class _Kopf extends StatelessWidget {
  const _Kopf({
    required this.tag,
    required this.istHeute,
    required this.onZurueck,
    required this.onVor,
    required this.onHeute,
  });

  final DateTime tag;
  final bool istHeute;
  final VoidCallback onZurueck;
  final VoidCallback onVor;

  /// `null`, wenn ohnehin heute angezeigt wird.
  final VoidCallback? onHeute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wochentag = tag.weekday <= DateTime.friday
        ? 'Tag ${tag.weekday} von 5'
        : 'Wochenende';

    return Row(
      children: [
        // Wie im Kalender: „Heute" und die Pfeile vor dem Datum, in fester
        // Reihenfolge — beim Blättern springt nichts.
        OutlinedButton(
          onPressed: onHeute,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            visualDensity: VisualDensity.standard,
          ),
          child: const Text('Heute'),
        ),
        const SizedBox(width: 6),
        _TagKnopf(
          icon: Icons.chevron_left,
          tooltip: 'Tag zurück',
          onPressed: onZurueck,
        ),
        const SizedBox(width: 4),
        _TagKnopf(
          icon: Icons.chevron_right,
          tooltip: 'Tag vor',
          onPressed: onVor,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                Format.datumLang(tag),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'KW ${isoKalenderwoche(tag)} · $wochentag'
                '${istHeute ? ' · heute' : ''}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Quadratischer Knopf zum Blättern.
class _TagKnopf extends StatelessWidget {
  const _TagKnopf({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(34, 34),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.standard,
        ),
        child: Icon(icon, size: 20),
      ),
    );
  }
}

// ── Tagesbereich ────────────────────────────────────────────────────────

class _Tagesbereich extends StatelessWidget {
  const _Tagesbereich({
    required this.uebersicht,
    required this.breit,
    required this.istHeute,
  });

  final _Uebersicht uebersicht;
  final bool breit;
  final bool istHeute;

  @override
  Widget build(BuildContext context) {
    final u = uebersicht;

    final heute = _HeuteKarte(
      auftraege: u.auftraege,
      titel: istHeute
          ? 'Heute in der Produktion'
          : 'Produktion am ${Format.datum(u.heute)}',
    );
    final auslastung = _AuslastungKarte(
      auslastung: u.auslastung,
      titel: istHeute ? 'Auslastung heute' : 'Auslastung',
    );
    final hinweise = _HinweisKarte(hinweise: u.hinweise);
    // Nur, wenn es für den Tag welche gibt — eingetragen wird im Board.
    final aufgaben =
        u.aufgaben.isEmpty ? null : _AufgabenKarte(aufgaben: u.aufgaben);

    if (!breit) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heute,
          const SizedBox(height: 12),
          auslastung,
          if (aufgaben != null) ...[
            const SizedBox(height: 12),
            aufgaben,
          ],
          const SizedBox(height: 12),
          hinweise,
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 3, child: heute),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                auslastung,
                if (aufgaben != null) ...[
                  const SizedBox(height: 12),
                  aufgaben,
                ],
                const SizedBox(height: 12),
                Expanded(child: hinweise),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Spaltenbreiten der Tagesliste — für Kopf und Zeilen dieselben.
abstract final class _Spalten {
  static const double abteilung = 30;
  static const double nummer = 60;
  static const double menge = 92;
  static const double dauer = 66;
  static const double status = 32;
}

/// Ziffern gleich breit, damit Mengen und Zeiten untereinander stehen.
const List<FontFeature> _ziffern = [FontFeature.tabularFigures()];

class _HeuteKarte extends StatefulWidget {
  const _HeuteKarte({required this.auftraege, required this.titel});

  final List<_Auftrag> auftraege;

  /// „Heute in der Produktion" oder, beim Blättern, das Datum.
  final String titel;

  /// Zoomstufe überlebt den Wechsel auf eine andere Seite und zurück —
  /// wer sich die Liste kleiner gestellt hat, will sie nicht bei jedem
  /// Besuch neu verkleinern.
  static double _skala = 1.0;

  /// Ausgeblendete Abteilungen, als dbValue. Gilt nur für diese Liste
  /// und überlebt wie die Zoomstufe den Seitenwechsel. Absichtlich eine
  /// Ausblend- und keine Einblendliste: Kommt später eine Abteilung
  /// dazu, ist sie sichtbar, statt still zu fehlen.
  static final Set<String> _versteckt = <String>{};

  @override
  State<_HeuteKarte> createState() => _HeuteKarteState();
}

class _HeuteKarteState extends State<_HeuteKarte> {
  /// Ab dieser Höhe wird gescrollt statt die Seite länger zu machen.
  static const double _maxHoehe = 560;

  static const double _minSkala = 0.7;
  static const double _maxSkala = 1.2;

  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _zoom(double delta) {
    final neu = (_HeuteKarte._skala + delta).clamp(_minSkala, _maxSkala);
    if (neu == _HeuteKarte._skala) return;
    setState(() => _HeuteKarte._skala = neu);
  }

  /// Abteilungen, die heute überhaupt vorkommen — nur die stehen im
  /// Filtermenü. Reihenfolge wie im Prozess, nicht wie in der Liste.
  List<Abteilung> get _abteilungenHeute {
    final vorhanden = <Abteilung>{
      for (final a in widget.auftraege)
        if (a.abteilung != null) a.abteilung!,
    };
    return Abteilung.values.where(vorhanden.contains).toList();
  }

  List<_Auftrag> get _sichtbare => widget.auftraege.where((a) {
        final abt = a.abteilung;
        return abt == null || !_HeuteKarte._versteckt.contains(abt.dbValue);
      }).toList();

  /// Antippen einer Zeile öffnet die Stammdaten des Artikels.
  VoidCallback? _oeffnerFuer(_Auftrag a) {
    final id = a.productId;
    if (id == null) return null;
    return () => _oeffneArtikel(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final skala = _HeuteKarte._skala;
    final sichtbare = _sichtbare;
    final ausgeblendet = widget.auftraege.length - sichtbare.length;

    final zumBoard = TextButton(
      onPressed: () => context.goNamed('board'),
      child: const Text('Zum Board'),
    );

    if (widget.auftraege.isEmpty) {
      return Bereich(
        titel: widget.titel,
        aktionen: [zumBoard],
        child: const LeerHinweis(
          'Für diesen Tag ist nichts geplant.',
          icon: Icons.event_note_outlined,
        ),
      );
    }

    final erledigt = widget.auftraege.where((a) => a.erledigt != null).length;
    final anzahl = widget.auftraege.length;

    return Bereich(
      titel: widget.titel,
      untertitel: '$anzahl ${anzahl == 1 ? 'Auftrag' : 'Aufträge'}'
          '${erledigt > 0 ? ' · $erledigt erledigt' : ''}',
      aktionen: [
        _AbteilungsFilter(
          abteilungen: _abteilungenHeute,
          versteckt: _HeuteKarte._versteckt,
          onGeaendert: () => setState(() {}),
        ),
        IconButton(
          onPressed: skala > _minSkala ? () => _zoom(-0.1) : null,
          icon: const Icon(Icons.remove, size: 18),
          tooltip: 'Kleiner anzeigen',
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
        Text(
          '${(skala * 100).round()} %',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontFeatures: _ziffern,
          ),
        ),
        IconButton(
          onPressed: skala < _maxSkala ? () => _zoom(0.1) : null,
          icon: const Icon(Icons.add, size: 18),
          tooltip: 'Größer anzeigen',
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
        const SizedBox(width: 4),
        zumBoard,
      ],
      innenAbstand: const EdgeInsets.fromLTRB(12, 0, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Spaltenköpfe stehen fest, nur die Zeilen scrollen.
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _TabellenKopf(skala: skala),
          ),
          // Deckel auf der Höhe: Sonst wächst die Liste mit jeder
          // Produktion weiter und schiebt Auslastung und Hinweise aus dem
          // Bild.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: _maxHoehe),
            child: Scrollbar(
              controller: _scroll,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (sichtbare.isEmpty)
                      const LeerHinweis('Alle Abteilungen ausgeblendet.'),
                    for (final a in sichtbare)
                      _AuftragZeile(
                        auftrag: a,
                        skala: skala,
                        onTap: _oeffnerFuer(a),
                      ),
                    if (ausgeblendet > 0 && sichtbare.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.filter_alt,
                              size: 13,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$ausgeblendet '
                              '${ausgeblendet == 1 ? 'Zeile' : 'Zeilen'} '
                              'ausgeblendet',
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
          ),
        ],
      ),
    );
  }
}

/// Filterknopf mit Abteilungsliste zum Ab- und Anwählen.
///
/// Bewusst ein eigenes Menü statt Chips über der Liste: Die Kopfzeile ist
/// schmal, und bei sieben Abteilungen bräuchten Chips mehr Platz als die
/// Liste selbst.
class _AbteilungsFilter extends StatelessWidget {
  const _AbteilungsFilter({
    required this.abteilungen,
    required this.versteckt,
    required this.onGeaendert,
  });

  final List<Abteilung> abteilungen;
  final Set<String> versteckt;
  final VoidCallback onGeaendert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aktiv = abteilungen.any((a) => versteckt.contains(a.dbValue));

    return PopupMenuButton<String>(
      tooltip: 'Abteilungen filtern',
      position: PopupMenuPosition.under,
      // Menü offen halten: Wer zwei Abteilungen ausblendet, will nicht
      // zweimal aufklappen. PopupMenuItem schließt sonst bei jedem Tipp.
      itemBuilder: (context) => [
        for (final a in abteilungen)
          PopupMenuItem<String>(
            value: a.dbValue,
            padding: EdgeInsets.zero,
            child: StatefulBuilder(
              builder: (context, setzeMenue) {
                final sichtbar = !versteckt.contains(a.dbValue);
                return InkWell(
                  onTap: () {
                    if (sichtbar) {
                      versteckt.add(a.dbValue);
                    } else {
                      versteckt.remove(a.dbValue);
                    }
                    setzeMenue(() {});
                    onGeaendert();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          sichtbar
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          size: 18,
                          color: sichtbar
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outline,
                        ),
                        const SizedBox(width: 10),
                        AbteilungsMarke(abteilung: a),
                        const SizedBox(width: 10),
                        Text(a.anzeigeName),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: '__alle__',
          enabled: aktiv,
          child: const Text('Alle einblenden'),
        ),
      ],
      onSelected: (wert) {
        if (wert == '__alle__') {
          versteckt.clear();
          onGeaendert();
        }
      },
      icon: Icon(
        aktiv ? Icons.filter_alt : Icons.filter_alt_outlined,
        size: 18,
        color: aktiv ? theme.colorScheme.primary : null,
      ),
      constraints: const BoxConstraints(minWidth: 240),
    );
  }
}

/// Spaltenköpfe der Tagesliste — dieselben Breiten wie [_AuftragZeile].
class _TabellenKopf extends StatelessWidget {
  const _TabellenKopf({required this.skala});

  final double skala;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stil = TextStyle(
      fontSize: 11.5 * skala,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurfaceVariant,
    );
    Widget rechts(String text, double breite) => SizedBox(
          width: breite * skala,
          child: Text(text, textAlign: TextAlign.right, style: stil),
        );

    return Container(
      padding: EdgeInsets.symmetric(vertical: 7 * skala),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outline),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _Spalten.abteilung * skala,
            child: Text('Abt.', style: stil),
          ),
          SizedBox(width: 10 * skala),
          SizedBox(
            width: _Spalten.nummer * skala,
            child: Text('Nr.', style: stil),
          ),
          Expanded(child: Text('Bezeichnung', style: stil)),
          rechts('Menge', _Spalten.menge),
          rechts('Dauer', _Spalten.dauer),
          SizedBox(width: _Spalten.status * skala),
        ],
      ),
    );
  }
}

class _AuftragZeile extends StatelessWidget {
  const _AuftragZeile({required this.auftrag, this.skala = 1.0, this.onTap});

  final _Auftrag auftrag;

  /// Zoomfaktor der Liste: skaliert Schrift, Abstände und die festen
  /// Spaltenbreiten gemeinsam, damit die Zeile im Raster bleibt.
  final double skala;

  /// Öffnet die Stammdaten des Artikels. null, wenn es ihn nicht mehr gibt.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = AppFarben.von(context);
    final a = auftrag;
    final grau = theme.colorScheme.onSurfaceVariant;

    final grund = theme.textTheme.bodyMedium;
    final stil = grund?.copyWith(fontSize: (grund.fontSize ?? 14) * skala);
    final zahlen = stil?.copyWith(fontFeatures: _ziffern);

    final haken = switch (a.erledigt) {
      null => null,
      Erledigt.erfasst => Tooltip(
          message: 'Produktion erfasst',
          child: Icon(Icons.fact_check, size: 16 * skala, color: f.ok),
        ),
      Erledigt.abgehakt => Tooltip(
          message: 'Erledigt',
          child: Icon(Icons.check_box, size: 16 * skala, color: f.ok),
        ),
    };

    // Material statt Farbe am Container: Die Tipp- und Hover-Welle des
    // InkWell malt auf das nächste Material. Läge die Farbe darüber, wäre
    // sie unsichtbar.
    return Material(
      color: a.erledigt == null ? Colors.transparent : f.okFlaeche,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 6 * skala),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              AbteilungsMarke(abteilung: a.abteilung, skala: skala),
              SizedBox(width: 10 * skala),
              SizedBox(
                width: _Spalten.nummer * skala,
                child: Text(
                  a.nummer,
                  maxLines: 1,
                  style: zahlen?.copyWith(
                    // Blau wie ein Link: Antippen öffnet den Artikel.
                    color: onTap == null ? null : theme.colorScheme.primary,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  a.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: stil,
                ),
              ),
              SizedBox(
                width: _Spalten.menge * skala,
                child: Text(
                  Format.kg(a.mengeKg),
                  maxLines: 1,
                  textAlign: TextAlign.right,
                  style: zahlen,
                ),
              ),
              SizedBox(
                width: _Spalten.dauer * skala,
                child: Text(
                  Zeit.kurz(a.minuten),
                  maxLines: 1,
                  textAlign: TextAlign.right,
                  style: zahlen?.copyWith(color: grau),
                ),
              ),
              SizedBox(
                width: _Spalten.status * skala,
                child: haken == null ? null : Center(child: haken),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuslastungKarte extends StatelessWidget {
  const _AuslastungKarte({required this.auslastung, required this.titel});

  final List<_Auslastung> auslastung;
  final String titel;

  @override
  Widget build(BuildContext context) {
    return Bereich(
      titel: titel,
      innenAbstand: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: auslastung.isEmpty
          ? const LeerHinweis('Keine Kapazität hinterlegt.')
          : Column(
              children: [
                for (final a in auslastung) _AuslastungZeile(auslastung: a),
              ],
            ),
    );
  }
}

/// Eine Abteilung: Name, Balken, Prozent.
///
/// Der Balken ist zweiteilig — kräftig die Produktion, heller die Rüst-
/// und Reinigungszeit. Beim Darüberfahren steht die Aufteilung in Stunden
/// dabei. So sieht man, ob eine volle Abteilung wirklich durch Aufträge
/// voll ist oder durch Nebenzeiten.
class _AuslastungZeile extends StatelessWidget {
  const _AuslastungZeile({required this.auslastung});

  final _Auslastung auslastung;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = AppFarben.von(context);
    final a = auslastung;
    final kap = a.kapazitaet;
    // Dieselben Bedeutungen wie im Board: grün gefüllt, rot überbucht.
    final farbe = a.anteil > 1 ? f.fehler : f.ok;
    final anteilBelegt = kap <= 0 ? 0.0 : (a.belegt / kap).clamp(0.0, 1.0);
    final anteilProduktion =
        kap <= 0 ? 0.0 : (a.produktion / kap).clamp(0.0, 1.0);

    final hinweis = [
      'Produktion ${Zeit.kurz(a.produktion)}',
      if (a.nebenzeit > 0) 'Rüsten/Reinigen ${Zeit.kurz(a.nebenzeit)}',
      'Kapazität ${Zeit.kurz(kap)}',
    ].join(' · ');

    return Tooltip(
      message: hinweis,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            SizedBox(
              width: 140,
              child: Text(
                a.abteilung.anzeigeName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Expanded(
              child: SizedBox(
                height: 8,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: theme.colorScheme.surfaceContainerHighest,
                    ),
                    // Gesamte Belegung, hell — der sichtbare Überstand über
                    // die Produktion ist die Nebenzeit.
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: anteilBelegt,
                      child: ColoredBox(color: farbe.withValues(alpha: .4)),
                    ),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: anteilProduktion,
                      child: ColoredBox(color: farbe),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 52,
              child: Text(
                a.belegt <= 0 ? '—' : '${(a.anteil * 100).round()} %',
                textAlign: TextAlign.right,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFeatures: _ziffern,
                  fontWeight: a.anteil > 1 ? FontWeight.w600 : null,
                  color: a.belegt <= 0
                      ? theme.colorScheme.onSurfaceVariant
                      : (a.anteil > 1 ? f.fehler : null),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Die sonstigen Aufgaben des Tages — abhakbar wie im Board. Antippen
/// einer Zeile setzt oder entfernt den Haken.
class _AufgabenKarte extends StatelessWidget {
  const _AufgabenKarte({required this.aufgaben});

  final List<Tagesaufgabe> aufgaben;

  /// Über den Container statt über `ref`: Baut die Übersicht während des
  /// Speicherns um, ist diese Karte womöglich schon weg — der Container
  /// nicht. Neu geladen wird nur die Übersicht, nicht der ganze Bedarf.
  Future<void> _abhaken(BuildContext context, Tagesaufgabe a) async {
    final container = ProviderScope.containerOf(context, listen: false);
    await TagesaufgabenService.abhaken(
      container.read(databaseProvider),
      a.id,
      erledigt: !a.erledigt,
    );
    container.read(autoBackupTriggerProvider).fireDebounced(
          reason: a.erledigt ? 'Haken entfernt' : 'Aufgabe abgehakt',
        );
    container.invalidate(_uebersichtProvider);
  }

  @override
  Widget build(BuildContext context) {
    final offen = aufgaben.where((a) => !a.erledigt).length;
    return Bereich(
      titel: 'Sonstige Aufgaben',
      aktionen: [
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: offen == 0
              ? const StatusMarke('alles erledigt', art: StatusArt.ok)
              : StatusMarke('$offen offen'),
        ),
      ],
      innenAbstand: const EdgeInsets.fromLTRB(4, 0, 4, 4),
      child: Column(
        children: [
          for (final a in aufgaben)
            _AufgabeZeile(aufgabe: a, onTap: () => _abhaken(context, a)),
        ],
      ),
    );
  }
}

class _AufgabeZeile extends StatelessWidget {
  const _AufgabeZeile({required this.aufgabe, required this.onTap});

  final Tagesaufgabe aufgabe;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = AppFarben.von(context);
    final a = aufgabe;
    final abteilung =
        Abteilung.values.where((x) => x.dbValue == a.abteilung).firstOrNull;

    // Material statt Farbe am Container: Die Tipp-Welle malt auf das
    // nächste Material und wäre unter einer Containerfarbe unsichtbar.
    return Material(
      color: a.erledigt ? f.okFlaeche : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              Tooltip(
                message:
                    a.erledigt ? 'Haken entfernen' : 'Als erledigt abhaken',
                child: Icon(
                  a.erledigt ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 18,
                  color:
                      a.erledigt ? f.ok : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 10),
              AbteilungsMarke(abteilung: abteilung),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  a.inhalt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: a.erledigt
                        ? theme.colorScheme.onSurfaceVariant
                        : null,
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

class _HinweisKarte extends StatelessWidget {
  const _HinweisKarte({required this.hinweise});

  final List<_Hinweis> hinweise;

  @override
  Widget build(BuildContext context) {
    return Bereich(
      titel: 'Hinweise',
      innenAbstand: const EdgeInsets.fromLTRB(4, 2, 4, 6),
      child: hinweise.isEmpty
          ? const LeerHinweis('Keine Hinweise.')
          : Column(
              children: [
                for (final h in hinweise) _HinweisZeile(hinweis: h),
              ],
            ),
    );
  }
}

class _HinweisZeile extends StatelessWidget {
  const _HinweisZeile({required this.hinweis});

  final _Hinweis hinweis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = AppFarben.von(context);
    final h = hinweis;
    final (symbol, farbe) = switch (h.art) {
      _Art.warnung => (Icons.warning_amber_outlined, f.warnung),
      _Art.info => (Icons.info_outline, f.info),
      _Art.gut => (Icons.cloud_done_outlined, f.ok),
    };
    final ziel = h.ziel;
    final aktion = h.aktion;

    return InkWell(
      onTap: ziel == null ? null : () => context.goNamed(ziel),
      borderRadius: AppMasse.ecken,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Row(
          children: [
            Icon(symbol, size: 17, color: farbe),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                h.text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: h.art == _Art.gut
                      ? theme.colorScheme.onSurfaceVariant
                      : null,
                ),
              ),
            ),
            if (aktion != null) ...[
              const SizedBox(width: 8),
              Text(
                '$aktion ›',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Formatierung
// ═══════════════════════════════════════════════════════════════════════════

/// „heute 07:41", „gestern 18:02", „vor 4 Tagen".
String _wann(DateTime t) {
  final jetzt = DateTime.now();
  final heute = DateTime(jetzt.year, jetzt.month, jetzt.day);
  final tag = DateTime(t.year, t.month, t.day);
  // In UTC gezählt, sonst ergibt eine Nacht mit Zeitumstellung 23 oder
  // 25 Stunden statt eines Tages.
  final tage = DateTime.utc(heute.year, heute.month, heute.day)
      .difference(DateTime.utc(tag.year, tag.month, tag.day))
      .inDays;
  if (tage <= 0) return 'heute ${Format.uhrzeit(t)}';
  if (tage == 1) return 'gestern ${Format.uhrzeit(t)}';
  return 'vor $tage Tagen';
}
