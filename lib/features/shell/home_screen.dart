// `hide Column`: drift hat eine eigene Klasse Column, die sonst mit dem
// Flutter-Widget kollidiert. Gebraucht wird drift für die
// Datumsvergleiche in den Abfragen (isBiggerOrEqualValue & Co. sind
// Erweiterungsmethoden und ohne diesen Import unsichtbar).
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/backup_service.dart';
import '../../core/services/week_snapshot_service.dart' show montagDerWoche;
import '../../core/utils/kalenderwoche.dart';
import '../../core/utils/vollbild.dart';
import '../../core/utils/zeit.dart';
import '../bedarf/bedarf_screen.dart' show bedarfProvider, heuteProvider;
import '../board/board_providers.dart' show tageskapazitaetJeAbteilung;

/// Ausgewähltes Datum. Wird von anderen Screens (Board) genutzt und bleibt
/// daher als gemeinsamer Zustand erhalten, auch wenn das Home es selbst
/// nicht anzeigt.
final selectedDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

// ═══════════════════════════════════════════════════════════════════════════
// Daten der Tagesübersicht
// ═══════════════════════════════════════════════════════════════════════════

/// Ein Auftrag des heutigen Tages, so wie er im Board steht.
class _Auftrag {
  const _Auftrag({
    required this.abteilung,
    required this.nummer,
    required this.name,
    required this.mengeKg,
    required this.minuten,
    required this.erfasst,
  });

  final Abteilung? abteilung;
  final String nummer;
  final String name;
  final double mengeKg;
  final double minuten;

  /// Nur für Ketten-Wurzeln bedeutsam — eine Produktion wird einmal
  /// erfasst, nicht je Abteilungsschritt.
  final bool? erfasst;
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
    required this.produktionenHeute,
    required this.erfasstHeute,
    required this.kgHeute,
    required this.wocheMinuten,
    required this.wocheProduktionen,
    required this.hinweise,
  });

  final DateTime heute;
  final List<_Auftrag> auftraege;
  final List<_Auslastung> auslastung;
  final int produktionenHeute;
  final int erfasstHeute;
  final double kgHeute;
  final double wocheMinuten;
  final int wocheProduktionen;
  final List<_Hinweis> hinweise;

  _Auslastung? get hoechste {
    final belegt = auslastung.where((a) => a.belegt > 0).toList()
      ..sort((a, b) => b.anteil.compareTo(a.anteil));
    return belegt.isEmpty ? null : belegt.first;
  }
}

/// Alles, was die Startseite zeigt, in einem Durchgang.
///
/// Gerechnet wird mit denselben Bausteinen wie in den Fachscreens —
/// Kapazität wie im Board, offener Bedarf wie im Bedarf-Screen, „erfasst"
/// wie in der Produktionserfassung. Eine zweite, eigene Rechnung würde
/// früher oder später abweichen.
///
/// `autoDispose`, damit die Übersicht beim nächsten Öffnen frisch geladen
/// wird. Kehrt man aus einem Fachscreen zurück, lädt [_oeffne] sie
/// zusätzlich neu, weil das Home dabei im Stapel bleibt.
final _uebersichtProvider =
    FutureProvider.autoDispose<_Uebersicht>((ref) async {
  final db = ref.watch(databaseProvider);
  final heute = ref.watch(heuteProvider);
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

  final auftraege = [
    for (final t in heuteTasks)
      _Auftrag(
        abteilung: abteilungVon(t.abteilung),
        nummer: produktVon[t.productId]?.artikelnummer ?? '—',
        name: produktVon[t.productId]?.artikelbezeichnung ?? 'Unbekannt',
        mengeKg: t.mengeKg,
        minuten: t.geplanteDauerMinuten,
        erfasst: t.parentTaskId == null
            ? istErfasst(t.productId, heute)
            : null,
      ),
  ];

  final wurzelnHeute = heuteTasks.where((t) => t.parentTaskId == null);
  final erfasstHeute =
      wurzelnHeute.where((t) => istErfasst(t.productId, heute)).length;

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
        '${_wochentage[d.weekday - 1]} ${d.day}.${d.month}. ist noch nicht '
        'erfasst — $n ${n == 1 ? 'Produktion' : 'Produktionen'}',
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
    produktionenHeute: wurzelnHeute.length,
    erfasstHeute: erfasstHeute,
    kgHeute: wurzelnHeute.fold<double>(0, (s, t) => s + t.mengeKg),
    wocheMinuten:
        tasks.fold<double>(0, (s, t) => s + t.geplanteDauerMinuten),
    wocheProduktionen: tasks.where((t) => t.parentTaskId == null).length,
    hinweise: hinweise,
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// Screen
// ═══════════════════════════════════════════════════════════════════════════

/// Startseite: zuerst der heutige Tag, danach die Navigation.
///
/// Wer die App morgens öffnet, will wissen, was heute läuft, wie voll die
/// Abteilungen sind und was liegengeblieben ist. Die Wege in die
/// Fachscreens folgen darunter, nach Arbeitsschritten geordnet statt als
/// gleichförmige Kachelreihe.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daten = ref.watch(_uebersichtProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Produktion Planer'),
        actions: [
          IconButton(
            tooltip: 'Aktualisieren',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _neuLaden(ref),
          ),
          // Im Vollbild gibt es keine Titelleiste — also auch kein ✕ und
          // kein Minimieren. Deshalb alle drei hier, in der Reihenfolge der
          // Fensterknöpfe von Windows.
          const IconButton(
            tooltip: 'Minimieren',
            icon: Icon(Icons.minimize_rounded),
            onPressed: Vollbild.minimieren,
          ),
          ValueListenableBuilder<bool>(
            valueListenable: Vollbild.aktiv,
            builder: (context, vollbild, _) => IconButton(
              tooltip: vollbild ? 'Vollbild beenden (F11)' : 'Vollbild (F11)',
              icon: Icon(
                vollbild
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
              ),
              onPressed: Vollbild.umschalten,
            ),
          ),
          IconButton(
            tooltip: 'App beenden',
            icon: const Icon(Icons.power_settings_new_rounded),
            onPressed: () => _beendenFragen(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, c) {
          final breit = c.maxWidth >= 1000;
          return ListView(
            padding: EdgeInsets.symmetric(
              horizontal: breit ? 24 : 16,
              vertical: 20,
            ),
            children: [
              daten.when(
                loading: () => const _Kopf(uebersicht: null),
                error: (_, __) => const _Kopf(uebersicht: null),
                data: (u) => _Kopf(uebersicht: u),
              ),
              const SizedBox(height: 16),
              daten.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => _Karte(
                  titel: 'Übersicht nicht verfügbar',
                  icon: Icons.error_outline_rounded,
                  child: Text('$e'),
                ),
                data: (u) => _Tagesbereich(uebersicht: u, breit: breit),
              ),
              const SizedBox(height: 20),
              _Navigation(breit: breit),
            ],
          );
        },
      ),
    );
  }
}

void _neuLaden(WidgetRef ref) {
  ref
    ..invalidate(bedarfProvider)
    ..invalidate(_uebersichtProvider);
}

/// Nachfrage vor dem Beenden — der Knopf sitzt neben „Aktualisieren", und
/// ein versehentlicher Klick soll nicht die App schließen.
Future<void> _beendenFragen(BuildContext context) async {
  final ja = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('App beenden?'),
      content: const Text('Beim Beenden wird automatisch ein Backup '
          'geschrieben.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Beenden'),
        ),
      ],
    ),
  );
  if (ja == true) await Vollbild.beenden();
}

/// Öffnet einen Fachscreen und lädt die Übersicht nach der Rückkehr neu —
/// dort wurde vielleicht gerade geplant oder erfasst.
Future<void> _oeffne(BuildContext context, WidgetRef ref, String ziel) async {
  await context.pushNamed(ziel);
  _neuLaden(ref);
}

// ── Kopf ────────────────────────────────────────────────────────────────

class _Kopf extends ConsumerWidget {
  const _Kopf({required this.uebersicht});

  final _Uebersicht? uebersicht;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final heute = uebersicht?.heute ?? DateTime.now();
    final tag = heute.weekday <= DateTime.friday
        ? 'Tag ${heute.weekday} von 5'
        : 'Wochenende';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_wochentage[heute.weekday - 1]}, ${heute.day}. '
                '${_monate[heute.month - 1]} ${heute.year}',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                'KW ${isoKalenderwoche(heute)} · $tag',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: () => _oeffne(context, ref, 'board'),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Produkt planen'),
        ),
      ],
    );
  }
}

// ── Tagesbereich ────────────────────────────────────────────────────────

class _Tagesbereich extends StatelessWidget {
  const _Tagesbereich({required this.uebersicht, required this.breit});

  final _Uebersicht uebersicht;
  final bool breit;

  @override
  Widget build(BuildContext context) {
    final u = uebersicht;
    final hoch = u.hoechste;

    final kennzahlen = [
      _Kennzahl(
        titel: 'Heute geplant',
        wert: '${u.produktionenHeute}',
        zusatz: u.produktionenHeute == 0
            ? 'keine Produktion'
            : '${u.produktionenHeute == 1 ? 'Produktion' : 'Produktionen'}'
                ' · ${_kg(u.kgHeute)}',
      ),
      _Kennzahl(
        titel: 'Höchste Auslastung',
        wert: hoch == null ? '—' : '${(hoch.anteil * 100).round()} %',
        zusatz: hoch == null
            ? 'heute nichts belegt'
            : '${hoch.abteilung.anzeigeName} · '
                '${Zeit.kurz(hoch.belegt)} / ${Zeit.kurz(hoch.kapazitaet)}',
        warnung: hoch != null && hoch.anteil > 1,
      ),
      _Kennzahl(
        titel: 'Erfasst',
        wert: '${u.erfasstHeute} / ${u.produktionenHeute}',
        zusatz: u.produktionenHeute == 0
            ? 'nichts zu erfassen'
            : u.erfasstHeute == u.produktionenHeute
                ? 'alles erfasst'
                : 'heute noch offen',
      ),
      _Kennzahl(
        titel: 'Diese Woche',
        wert: Zeit.kurz(u.wocheMinuten),
        zusatz: '${u.wocheProduktionen} '
            '${u.wocheProduktionen == 1 ? 'Produktion' : 'Produktionen'}'
            ' geplant',
      ),
    ];

    final zeilen = LayoutBuilder(
      builder: (context, c) {
        final spalten = c.maxWidth >= 720 ? 4 : 2;
        const abstand = 12.0;
        final breite = (c.maxWidth - abstand * (spalten - 1)) / spalten;
        return Wrap(
          spacing: abstand,
          runSpacing: abstand,
          children: [
            for (final k in kennzahlen) SizedBox(width: breite, child: k),
          ],
        );
      },
    );

    final heute = _HeuteKarte(auftraege: u.auftraege);
    final auslastung = _AuslastungKarte(auslastung: u.auslastung);
    final hinweise = _HinweisKarte(hinweise: u.hinweise);

    if (!breit) {
      return Column(
        children: [
          zeilen,
          const SizedBox(height: 12),
          heute,
          const SizedBox(height: 12),
          auslastung,
          const SizedBox(height: 12),
          hinweise,
        ],
      );
    }
    return Column(
      children: [
        zeilen,
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 3, child: heute),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    auslastung,
                    const SizedBox(height: 12),
                    Expanded(child: hinweise),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Kennzahl extends StatelessWidget {
  const _Kennzahl({
    required this.titel,
    required this.wert,
    required this.zusatz,
    this.warnung = false,
  });

  final String titel;
  final String wert;
  final String zusatz;
  final bool warnung;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gedimmt = theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: .5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titel,
            style: theme.textTheme.labelMedium?.copyWith(color: gedimmt),
          ),
          const SizedBox(height: 6),
          Text(
            wert,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: warnung ? theme.colorScheme.error : null,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            zusatz,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: gedimmt),
          ),
        ],
      ),
    );
  }
}

/// Umrandete Karte mit kleiner Überschrift — der gemeinsame Rahmen aller
/// Bereiche, damit die Seite ruhig und gleichmäßig wirkt.
class _Karte extends StatelessWidget {
  const _Karte({
    required this.titel,
    required this.icon,
    required this.child,
    this.aktion,
  });

  final String titel;
  final IconData icon;
  final Widget child;
  final Widget? aktion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titel,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (aktion != null) aktion!,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _HeuteKarte extends ConsumerWidget {
  const _HeuteKarte({required this.auftraege});

  final List<_Auftrag> auftraege;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final zumBoard = TextButton.icon(
      onPressed: () => _oeffne(context, ref, 'board'),
      icon: const Icon(Icons.arrow_forward_rounded, size: 16),
      label: const Text('Zum Board'),
    );
    if (auftraege.isEmpty) {
      return _Karte(
        titel: 'Heute in der Produktion',
        icon: Icons.event_note_rounded,
        aktion: zumBoard,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text(
              'Für heute ist nichts geplant.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }
    return _Karte(
      titel: 'Heute in der Produktion',
      icon: Icons.event_note_rounded,
      aktion: zumBoard,
      child: Column(
        children: [
          for (final a in auftraege) _AuftragZeile(auftrag: a),
        ],
      ),
    );
  }
}

class _AuftragZeile extends StatelessWidget {
  const _AuftragZeile({required this.auftrag});

  final _Auftrag auftrag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = auftrag;
    final farbe = a.abteilung?.farbe ?? theme.colorScheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          // Gefüllt wie im Board: Als Schrift auf blassem Grund war das
          // Braun der Bratstraße im dunklen Modus kaum zu erkennen.
          Container(
            width: 30,
            padding: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: farbe,
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: Text(
              a.abteilung?.kurzcode ?? '?',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 52,
            child: Text(
              a.nummer,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
          ),
          Expanded(
            child: Text(
              a.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${_kg(a.mengeKg)} · ${Zeit.kurz(a.minuten)}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 18,
            child: a.erfasst == true
                ? Tooltip(
                    message: 'Erfasst',
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: Colors.green.shade600,
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _AuslastungKarte extends StatelessWidget {
  const _AuslastungKarte({required this.auslastung});

  final List<_Auslastung> auslastung;

  @override
  Widget build(BuildContext context) {
    return _Karte(
      titel: 'Auslastung heute',
      icon: Icons.speed_rounded,
      child: Column(
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
    final a = auslastung;
    final kap = a.kapazitaet;
    // Dieselben Farben wie im Board: grün gefüllt, rot überbucht.
    final farbe =
        a.anteil > 1 ? theme.colorScheme.error : Colors.green.shade600;
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
              width: 132,
              child: Text(
                a.abteilung.anzeigeName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  height: 6,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                      // Gesamte Belegung, hell — der sichtbare Überstand
                      // über die Produktion ist die Nebenzeit.
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: anteilBelegt,
                        child: ColoredBox(
                          color: farbe.withValues(alpha: .4),
                        ),
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
            ),
            SizedBox(
              width: 48,
              child: Text(
                a.belegt <= 0 ? '—' : '${(a.anteil * 100).round()} %',
                textAlign: TextAlign.right,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: a.belegt <= 0
                      ? theme.colorScheme.onSurfaceVariant
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HinweisKarte extends ConsumerWidget {
  const _HinweisKarte({required this.hinweise});

  final List<_Hinweis> hinweise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return _Karte(
      titel: 'Hinweise',
      icon: Icons.notifications_none_rounded,
      child: Column(
        children: [
          for (final h in hinweise)
            InkWell(
              onTap: h.ziel == null
                  ? null
                  : () => _oeffne(context, ref, h.ziel!),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Icon(
                      switch (h.art) {
                        _Art.warnung => Icons.warning_amber_rounded,
                        _Art.info => Icons.info_outline_rounded,
                        _Art.gut => Icons.cloud_done_outlined,
                      },
                      size: 18,
                      color: switch (h.art) {
                        _Art.warnung => Colors.orange.shade700,
                        _Art.info => theme.colorScheme.primary,
                        _Art.gut => Colors.green.shade600,
                      },
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        h.text,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: h.art == _Art.gut
                              ? theme.colorScheme.onSurfaceVariant
                              : null,
                        ),
                      ),
                    ),
                    if (h.aktion != null)
                      Text(
                        h.aktion!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.primary),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Navigation ─────────────────────────────────────────────────────────

class _Ziel {
  const _Ziel(this.icon, this.titel, this.zusatz, this.route);

  final IconData icon;
  final String titel;
  final String zusatz;
  final String route;
}

/// Die Wege in die Fachscreens, nach Arbeitsschritten gruppiert.
class _Navigation extends StatelessWidget {
  const _Navigation({required this.breit});

  final bool breit;

  // Jede Gruppe hat ihre eigene Farbe — so erkennt man sie auf einen
  // Blick, noch bevor man die Überschrift liest.
  static const _gruppen = <(String, IconData, Color, List<_Ziel>)>[
    (
      'Planen',
      Icons.edit_calendar_outlined,
      Color(0xFF1E88E5),
      [
        _Ziel(Icons.playlist_add_check_rounded, 'Bedarf',
            'Was produziert werden muss', 'bedarf',),
        _Ziel(Icons.swap_horiz_rounded, 'Navision-Import',
            'Artikel und Bedarf aus der Warenwirtschaft', 'navisionImport',),
        _Ziel(Icons.view_week_rounded, 'Planungsboard',
            'Woche im Board einplanen', 'board',),
      ],
    ),
    (
      'Auswerten',
      Icons.insights_rounded,
      Color(0xFF26A69A),
      [
        _Ziel(Icons.fact_check_outlined, 'Produktionserfassung',
            'Ist-Daten der Woche', 'erfassung',),
        _Ziel(Icons.history_rounded, 'Wochen-Historie',
            'Rückblick und Kennzahlen', 'wochenHistorie',),
      ],
    ),
    (
      'Stammdaten',
      Icons.folder_open_rounded,
      Color(0xFF9575CD),
      [
        _Ziel(Icons.inventory_2_outlined, 'Artikel',
            'Abläufe, Maschinen, Zeiten', 'articles',),
        _Ziel(Icons.precision_manufacturing_outlined, 'Maschinen-Katalog',
            'Anlagen und Steckbriefe', 'maschinen',),
        _Ziel(Icons.settings_outlined, 'Einstellungen',
            'Excel, Backup, Darstellung', 'settings',),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final karten = [
      for (final (titel, icon, farbe, ziele) in _gruppen)
        _NavGruppe(titel: titel, icon: icon, farbe: farbe, ziele: ziele),
    ];
    if (!breit) {
      return Column(
        children: [
          for (final k in karten) ...[k, const SizedBox(height: 12)],
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < karten.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: karten[i]),
          ],
        ],
      ),
    );
  }
}

class _NavGruppe extends ConsumerWidget {
  const _NavGruppe({
    required this.titel,
    required this.icon,
    required this.farbe,
    required this.ziele,
  });

  final String titel;
  final IconData icon;
  final Color farbe;
  final List<_Ziel> ziele;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
      decoration: BoxDecoration(
        // Ein Hauch der Gruppenfarbe — erkennbar, aber nicht bunt.
        color: farbe.withValues(alpha: .06),
        border: Border.all(color: farbe.withValues(alpha: .28)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(
              children: [
                Icon(icon, size: 20, color: farbe),
                const SizedBox(width: 8),
                Text(
                  titel,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: farbe,
                  ),
                ),
              ],
            ),
          ),
          for (final z in ziele)
            InkWell(
              onTap: () => _oeffne(context, ref, z.route),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(z.icon, size: 22, color: farbe),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            z.titel,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            z.zusatz,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Formatierung
// ═══════════════════════════════════════════════════════════════════════════

const _wochentage = [
  'Montag',
  'Dienstag',
  'Mittwoch',
  'Donnerstag',
  'Freitag',
  'Samstag',
  'Sonntag',
];

const _monate = [
  'Januar',
  'Februar',
  'März',
  'April',
  'Mai',
  'Juni',
  'Juli',
  'August',
  'September',
  'Oktober',
  'November',
  'Dezember',
];

/// „1.786 kg" — Tausenderpunkt ohne intl, dessen Sprachdaten die App
/// nicht initialisiert.
String _kg(double kg) {
  final s = kg.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return '$b kg';
}

/// „heute 07:41", „gestern 18:02", „vor 4 Tagen".
String _wann(DateTime t) {
  final jetzt = DateTime.now();
  final heute = DateTime(jetzt.year, jetzt.month, jetzt.day);
  final tag = DateTime(t.year, t.month, t.day);
  final uhr = '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
  // In UTC gezählt, sonst ergibt eine Nacht mit Zeitumstellung 23 oder
  // 25 Stunden statt eines Tages.
  final tage = DateTime.utc(heute.year, heute.month, heute.day)
      .difference(DateTime.utc(tag.year, tag.month, tag.day))
      .inDays;
  if (tage <= 0) return 'heute $uhr';
  if (tage == 1) return 'gestern $uhr';
  return 'vor $tage Tagen';
}
