import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_stil.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/fehler_text.dart';
import '../../../core/utils/format.dart';
import '../daten/entwicklung_repository.dart';
import '../entwicklung_bereiche.dart';
import '../kunden/kunden_ansicht.dart';
import '../kunden/kunden_modell.dart';
import '../projekte/gesamtprojekt_screen.dart' show oeffneGesamtprojekt;
import '../projekte/projekt_checkliste.dart';
import '../projekte/projekt_modell.dart';
import '../projekte/projekt_repository.dart';
import '../projekte/projekte_ansicht.dart'
    show
        NeuAngelegt,
        NeuesProjektDialog,
        oeffneAngelegt,
        oeffneProjekt,
        projektStatusArt;
import '../rezepturen/rezepturen_ansicht.dart'
    show NeueRezepturDialog, oeffneRezeptur;
import '../werkzeuge/entwicklung_statistik.dart' show kRuhendNachTagen;
import 'angeheftet.dart';
import 'uebersicht_modell.dart';

// Die Übersicht der Produktentwicklung — ihre Startseite. Oben Suche und
// die Knöpfe für Neues, darunter vier Kacheln mit den Zahlen, die Projekte
// zuletzt bearbeitet (angeheftete zuerst) mit dem, was ihnen fehlt, die
// Kunden mit Projekten in Arbeit und was ansteht. Gerechnet wird in
// uebersicht_modell.dart.

/// Höchstens so viele Kunden zeigt die Übersicht — alle stehen unter
/// „Kunden".
const int _kundenHoechstens = 6;

/// Höchstens so viele Einträge und ruhende Projekte unter „Was ansteht".
const int _anstehtHoechstens = 10;

/// Die Übersicht der Produktentwicklung.
class EntwicklungUebersicht extends ConsumerStatefulWidget {
  const EntwicklungUebersicht({super.key, this.heute});

  /// Für Tests: der Tag, an dem gerechnet wird — sonst heute.
  final DateTime? heute;

  @override
  ConsumerState<EntwicklungUebersicht> createState() =>
      _EntwicklungUebersichtState();
}

class _EntwicklungUebersichtState extends ConsumerState<EntwicklungUebersicht> {
  final _suche = TextEditingController();
  String _text = '';

  /// „Was ansteht" — dorthin führen die Kacheln „Überfällig" und „Ruhen".
  final _ansteht = GlobalKey();

  @override
  void dispose() {
    _suche.dispose();
    super.dispose();
  }

  Future<void> _neuesProjekt() async {
    final neu = await showDialog<NeuAngelegt>(
      context: context,
      builder: (_) => NeuesProjektDialog(
        gesamtprojekte:
            ref.read(gesamtprojekteProvider).valueOrNull ?? const [],
      ),
    );
    if (neu == null || !mounted) return;
    await oeffneAngelegt(context, neu);
  }

  Future<void> _neueRezeptur() async {
    final id = await showDialog<String>(
      context: context,
      builder: (_) => const NeueRezepturDialog(),
    );
    if (id == null || !mounted) return;
    await oeffneRezeptur(context, id);
  }

  void _zuAnsteht() {
    final ziel = _ansteht.currentContext;
    if (ziel == null) return;
    Scrollable.ensureVisible(
      ziel,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final projekte = ref.watch(projekteProvider);
    final gesamt = ref.watch(gesamtprojekteProvider);
    final eintraege = ref.watch(alleEintraegeProvider);
    final rezepturen = ref.watch(rezepturenProvider);
    final versionen = ref.watch(alleVersionenProvider);
    final zeilen = ref.watch(zeilenAenderungenProvider).valueOrNull ??
        const <String, DateTime>{};
    final angeheftet = ref.watch(angehefteteProjekteProvider);
    final checklisten = ref.watch(projektChecklistenProvider);
    final alle = <AsyncValue<Object?>>[
      projekte,
      gesamt,
      eintraege,
      rezepturen,
      versionen,
    ];
    final fehler = alle.where((a) => a.hasError).firstOrNull;
    if (fehler != null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          HinweisBox(
            fehlerText(fehler.error),
            art: StatusArt.fehler,
            titel: 'Die Übersicht ließ sich nicht laden',
            auswaehlbar: true,
          ),
        ],
      );
    }
    if (alle.any((a) => !a.hasValue)) {
      return const Center(child: CircularProgressIndicator());
    }
    final p = projekte.requireValue;
    final g = gesamt.requireValue;
    final e = eintraege.requireValue;
    final r = rezepturen.requireValue;
    final v = versionen.requireValue;
    final heute = widget.heute ?? DateTime.now();
    final aktivitaet = projektAktivitaet(
      projekte: p,
      eintraege: e,
      rezepturen: r,
      versionen: v,
      zeilen: zeilen,
    );

    return LayoutBuilder(
      builder: (context, c) {
        final breit = c.maxWidth >= 1000;
        final rand = breit ? 24.0 : 16.0;
        final suche = _text.trim().isNotEmpty;
        Widget kunden() => _KundenAuszug(
              projekte: p,
              gesamtprojekte: g,
              aktivitaet: aktivitaet,
              checklisten: checklisten,
              heute: heute,
            );
        Widget ansteht() => _AnstehtBereich(
              key: _ansteht,
              faellig: faelligeEintraege(
                eintraege: e,
                projekte: p,
                gesamtprojekte: g,
                heute: heute,
              ),
              ruhend: ruhendeProjekte(
                projekte: p,
                aktivitaet: aktivitaet,
                heute: heute,
              ),
              heute: heute,
            );
        // Alles gebaut, nicht erst beim Scrollen — sonst fände der Sprung
        // zu „Was ansteht" sein Ziel nicht.
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(rand, 16, rand, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Kopfzeile(
                suche: _suche,
                onSuche: (t) => setState(() => _text = t),
                onLeeren: () {
                  _suche.clear();
                  setState(() => _text = '');
                },
                onNeuesProjekt: _neuesProjekt,
                onNeueRezeptur: _neueRezeptur,
              ),
              const SizedBox(height: 16),
              if (suche)
                _Suchergebnis(
                  treffer: uebersichtSuchen(
                    _text,
                    projekte: p,
                    gesamtprojekte: g,
                    rezepturen: r,
                    aktivitaet: aktivitaet,
                  ),
                  projekte: p,
                  aktivitaet: aktivitaet,
                  checklisten: checklisten,
                  heute: heute,
                )
              else ...[
                _Kacheln(
                  zahlen: uebersichtZahlen(
                    projekte: p,
                    gesamtprojekte: g,
                    eintraege: e,
                    aktivitaet: aktivitaet,
                    heute: heute,
                    rezepturen: r,
                    versionen: v,
                  ),
                  onInArbeit: () =>
                      bereichOeffnen(context, EntwicklungsBereich.projekte),
                  onAnsteht: _zuAnsteht,
                  onGelistet: () =>
                      bereichOeffnen(context, EntwicklungsBereich.statistik),
                ),
                const SizedBox(height: 16),
                _ZuletztBereich(
                  projekte: zuletztBearbeitet(
                    projekte: p,
                    aktivitaet: aktivitaet,
                    angeheftet: angeheftet,
                  ),
                  angeheftet: angeheftet.toSet(),
                  gesamtprojekte: {for (final x in g) x.id: x.name},
                  eintraege: e,
                  rezepturen: r,
                  versionen: v,
                  aktivitaet: aktivitaet,
                  checklisten: checklisten,
                  heute: heute,
                ),
                const SizedBox(height: 16),
                if (breit)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: kunden()),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: ansteht()),
                    ],
                  )
                else ...[
                  kunden(),
                  const SizedBox(height: 16),
                  ansteht(),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

// ── Kopfzeile ─────────────────────────────────────────────────────────

class _Kopfzeile extends StatelessWidget {
  const _Kopfzeile({
    required this.suche,
    required this.onSuche,
    required this.onLeeren,
    required this.onNeuesProjekt,
    required this.onNeueRezeptur,
  });

  final TextEditingController suche;
  final ValueChanged<String> onSuche;
  final VoidCallback onLeeren;
  final VoidCallback onNeuesProjekt;
  final VoidCallback onNeueRezeptur;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: suche,
                builder: (context, wert, _) => TextField(
                  key: const ValueKey('uebersicht-suche'),
                  controller: suche,
                  decoration: InputDecoration(
                    hintText: 'Suche nach Projekt, Kunde, Rezeptur oder '
                        'Artikelnummer …',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: wert.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            tooltip: 'Suche leeren',
                            onPressed: onLeeren,
                          ),
                  ),
                  onChanged: onSuche,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          key: const ValueKey('uebersicht-neue-rezeptur'),
          onPressed: onNeueRezeptur,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Neue Rezeptur'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          key: const ValueKey('uebersicht-neues-projekt'),
          onPressed: onNeuesProjekt,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Neues Projekt'),
        ),
      ],
    );
  }
}

// ── Kacheln ───────────────────────────────────────────────────────────

class _Kacheln extends StatelessWidget {
  const _Kacheln({
    required this.zahlen,
    required this.onInArbeit,
    required this.onAnsteht,
    required this.onGelistet,
  });

  final UebersichtZahlen zahlen;
  final VoidCallback onInArbeit;
  final VoidCallback onAnsteht;
  final VoidCallback onGelistet;

  @override
  Widget build(BuildContext context) {
    final farben = AppFarben.von(context);
    final grau = Theme.of(context).colorScheme.onSurfaceVariant;
    final z = zahlen;
    final kacheln = [
      _Kachel(
        key: const ValueKey('kachel-in-arbeit'),
        icon: Icons.science_outlined,
        wert: '${z.inArbeit}',
        titel: 'In Arbeit',
        zusatz: z.inValidierung == 0
            ? 'in Entwicklung oder Validierung'
            : 'davon ${z.inValidierung} in Validierung',
        onTap: onInArbeit,
      ),
      _Kachel(
        key: const ValueKey('kachel-ueberfaellig'),
        icon: Icons.event_busy_outlined,
        wert: '${z.ueberfaellig}',
        titel: 'Überfällig',
        zusatz: z.offen == 1
            ? 'von 1 offenen Eintrag'
            : 'von ${z.offen} offenen Einträgen',
        farbe: z.ueberfaellig > 0 ? farben.fehler : grau,
        onTap: onAnsteht,
      ),
      _Kachel(
        key: const ValueKey('kachel-ruhen'),
        icon: Icons.bedtime_outlined,
        wert: '${z.ruhend}',
        titel: z.ruhend == 1 ? 'Ruht' : 'Ruhen',
        zusatz: 'in Arbeit, aber seit $kRuhendNachTagen Tagen nichts getan',
        farbe: z.ruhend > 0 ? farben.warnung : grau,
        onTap: onAnsteht,
      ),
      _Kachel(
        key: const ValueKey('kachel-gelistet'),
        icon: Icons.verified_outlined,
        wert: '${z.gelistet}',
        titel: 'Gelistet ${z.jahr}',
        zusatz: 'in Produktion gegangen',
        farbe: farben.ok,
        onTap: onGelistet,
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        const luecke = 12.0;
        final spalten = c.maxWidth >= 960 ? 4 : 2;
        final breite =
            ((c.maxWidth - (spalten - 1) * luecke) / spalten).floorToDouble();
        return Wrap(
          spacing: luecke,
          runSpacing: luecke,
          children: [
            for (final k in kacheln) SizedBox(width: breite, child: k),
          ],
        );
      },
    );
  }
}

/// Eine Kachel: Symbol, die Zahl groß, darunter was sie zählt.
class _Kachel extends StatelessWidget {
  const _Kachel({
    super.key,
    required this.icon,
    required this.wert,
    required this.titel,
    required this.zusatz,
    required this.onTap,
    this.farbe,
  });

  final IconData icon;
  final String wert;
  final String titel;
  final String zusatz;
  final VoidCallback onTap;

  /// Farbe von Symbol und Zahl — sonst die Akzentfarbe.
  final Color? farbe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final farben = theme.colorScheme;
    final f = farbe ?? farben.primary;
    return Material(
      color: farben.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppMasse.ecken,
        side: BorderSide(color: farben.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: f.withValues(alpha: 0.12),
                  borderRadius: AppMasse.ecken,
                ),
                child: Icon(icon, size: 20, color: f),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      wert,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: farbe,
                      ),
                    ),
                    Text(
                      titel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      zusatz,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: farben.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: farben.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Zuletzt bearbeitet ────────────────────────────────────────────────

class _ZuletztBereich extends StatelessWidget {
  const _ZuletztBereich({
    required this.projekte,
    required this.angeheftet,
    required this.gesamtprojekte,
    required this.eintraege,
    required this.rezepturen,
    required this.versionen,
    required this.aktivitaet,
    required this.checklisten,
    required this.heute,
  });

  final List<EntwicklungsProjekt> projekte;
  final Set<String> angeheftet;

  /// Die Namen der Gesamtprojekte nach ihrer ID.
  final Map<String, String> gesamtprojekte;
  final List<ProjektEintrag> eintraege;
  final List<Rezeptur> rezepturen;
  final List<RezepturVersion> versionen;
  final Map<String, DateTime> aktivitaet;
  final Map<String, ProjektCheckStand>? checklisten;
  final DateTime heute;

  @override
  Widget build(BuildContext context) {
    final ids = {for (final p in projekte) p.id};
    final eintraegeJe = <String, List<ProjektEintrag>>{};
    for (final e in eintraege) {
      if (ids.contains(e.projektId)) (eintraegeJe[e.projektId] ??= []).add(e);
    }
    final projektVon = {
      for (final r in rezepturen)
        if (r.projektId case final pid? when ids.contains(pid)) r.id: pid,
    };
    final entwuerfeJe = <String, List<RezepturVersion>>{};
    for (final v in versionen) {
      final pid = projektVon[v.rezepturId];
      if (pid != null && v.status == VersionStatus.entwurf) {
        (entwuerfeJe[pid] ??= []).add(v);
      }
    }
    return Bereich(
      titel: 'Zuletzt bearbeitet',
      icon: Icons.history,
      untertitel: angeheftet.isEmpty
          ? 'Projekte in Arbeit, das zuletzt bewegte zuerst'
          : 'angeheftete zuerst, dann die zuletzt bewegten',
      aktionen: [
        TextButton(
          onPressed: () =>
              bereichOeffnen(context, EntwicklungsBereich.projekte),
          child: const Text('Alle Projekte'),
        ),
      ],
      innenAbstand: const EdgeInsets.all(12),
      child: projekte.isEmpty
          ? const LeerHinweis(
              'Kein Projekt in Arbeit. Lege ein neues an — oder hefte ein '
              'Projekt mit der Nadel an, dann steht es hier.',
              icon: Icons.inventory_2_outlined,
            )
          : LayoutBuilder(
              builder: (context, c) {
                const luecke = 12.0;
                const mindestens = 230.0;
                final spalten = math.max(
                  1,
                  ((c.maxWidth + luecke) / (mindestens + luecke)).floor(),
                );
                final breite = ((c.maxWidth - (spalten - 1) * luecke) / spalten)
                    .floorToDouble();
                return Wrap(
                  spacing: luecke,
                  runSpacing: luecke,
                  children: [
                    for (final p in projekte)
                      SizedBox(
                        width: breite,
                        child: _ProjektKarte(
                          projekt: p,
                          gesamtprojekt: gesamtprojekte[p.gesamtprojektId],
                          zuletzt: aktivitaet[p.id] ?? p.updatedAt,
                          heute: heute,
                          checkliste: checklisten?[p.id],
                          angeheftet: angeheftet.contains(p.id),
                          hinweise: projektHinweise(
                            projekt: p,
                            zuletzt: aktivitaet[p.id] ?? p.updatedAt,
                            heute: heute,
                            checkliste: checklisten?[p.id],
                            eintraege: eintraegeJe[p.id] ?? const [],
                            entwuerfe: entwuerfeJe[p.id] ?? const [],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

/// Ein Projekt als Karte: Name, wo es hingehört und wann sich zuletzt
/// etwas getan hat, Status und Checkliste — darunter kurz, was fehlt.
class _ProjektKarte extends StatelessWidget {
  const _ProjektKarte({
    required this.projekt,
    required this.gesamtprojekt,
    required this.zuletzt,
    required this.heute,
    required this.checkliste,
    required this.angeheftet,
    required this.hinweise,
  });

  final EntwicklungsProjekt projekt;

  /// Der Name des Gesamtprojekts, zu dem es als Muster gehört.
  final String? gesamtprojekt;
  final DateTime zuletzt;
  final DateTime heute;
  final ProjektCheckStand? checkliste;
  final bool angeheftet;
  final List<ProjektHinweis> hinweise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final farben = theme.colorScheme;
    final grau = farben.onSurfaceVariant;
    final status = ProjektStatus.aus(projekt.status);
    final c = checkliste;
    final kunde = projekt.kunde?.trim() ?? '';
    final wo = [
      if (gesamtprojekt case final g?) g,
      if (kunde.isNotEmpty) kunde else 'ohne Kunden',
      vorWieLange(zuletzt, heute),
    ].join(' · ');
    return Material(
      key: ValueKey('karte-${projekt.id}'),
      color: farben.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppMasse.ecken,
        side: BorderSide(
          color: angeheftet ? farben.primary : farben.outline,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => oeffneProjekt(context, projekt.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        projekt.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  AnheftenKnopf(projektId: projekt.id),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  wo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: grau),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  children: [
                    // Die Marke so breit, wie sie ist — in einer sehr
                    // schmalen Karte gekürzt.
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: StatusMarke(
                          status.label,
                          art: projektStatusArt(status),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (c != null)
                      Tooltip(
                        message: 'Checkliste: ${c.text} erledigt',
                        child: Text(
                          c.text,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: grau,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (c != null) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: c.anteil,
                      minHeight: 4,
                      color: AppFarben.von(context).ok,
                      backgroundColor: farben.surfaceContainerHighest,
                    ),
                  ),
                ),
              ],
              if (hinweise.isNotEmpty) const SizedBox(height: 10),
              for (final h in hinweise.take(2))
                Padding(
                  padding: const EdgeInsets.only(right: 8, top: 2),
                  child: _HinweisZeile(hinweis: h),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ein Hinweis auf der Karte: Symbol und ein kurzer Satz.
class _HinweisZeile extends StatelessWidget {
  const _HinweisZeile({required this.hinweis});

  final ProjektHinweis hinweis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final farben = AppFarben.von(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final (icon, farbe) = switch (hinweis.art) {
      HinweisArt.ueberfaellig => (Icons.event_busy_outlined, farben.fehler),
      HinweisArt.ruht => (Icons.bedtime_outlined, farben.warnung),
      HinweisArt.naechster => (Icons.arrow_forward, theme.colorScheme.primary),
      HinweisArt.erledigt => (Icons.check_circle_outline, farben.ok),
      HinweisArt.faellig => (Icons.event_outlined, grau),
      HinweisArt.entwurf => (Icons.edit_note, grau),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 15, color: farbe),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            hinweis.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: hinweis.art == HinweisArt.ueberfaellig ? farbe : null,
              fontWeight: hinweis.art == HinweisArt.ueberfaellig
                  ? FontWeight.w600
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Kunden ────────────────────────────────────────────────────────────

/// Die Kunden mit Projekten in Arbeit — der zuletzt bewegte zuerst.
class _KundenAuszug extends StatelessWidget {
  const _KundenAuszug({
    required this.projekte,
    required this.gesamtprojekte,
    required this.aktivitaet,
    required this.checklisten,
    required this.heute,
  });

  final List<EntwicklungsProjekt> projekte;
  final List<Gesamtprojekt> gesamtprojekte;
  final Map<String, DateTime> aktivitaet;
  final Map<String, ProjektCheckStand>? checklisten;
  final DateTime heute;

  @override
  Widget build(BuildContext context) {
    final ordner = [
      for (final o in kundenOrdner(
        projekte: projekte,
        gesamtprojekte: gesamtprojekte,
        aktivitaet: aktivitaet,
      ))
        if (o.name != null && o.inArbeit > 0) o,
    ]..sort((a, b) => b.zuletzt.compareTo(a.zuletzt));
    final farben = Theme.of(context).colorScheme;
    return Bereich(
      titel: 'Kunden',
      icon: Icons.folder_shared_outlined,
      untertitel: ordner.isEmpty
          ? null
          : ordner.length == 1
              ? '1 mit Projekten in Arbeit'
              : '${ordner.length} mit Projekten in Arbeit',
      aktionen: [
        TextButton(
          onPressed: () => bereichOeffnen(context, EntwicklungsBereich.kunden),
          child: const Text('Alle Kunden'),
        ),
      ],
      innenAbstand: EdgeInsets.zero,
      child: ordner.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: LeerHinweis(
                'Kein Kunde mit Projekten in Arbeit.',
                icon: Icons.folder_shared_outlined,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, o)
                    in ordner.take(_kundenHoechstens).indexed) ...[
                  if (i > 0) Divider(height: 1, color: farben.outlineVariant),
                  KundenOrdnerKachel(
                    ordner: o,
                    heute: heute,
                    aktivitaet: aktivitaet,
                    checklisten: checklisten,
                    rahmen: false,
                  ),
                ],
                if (ordner.length > _kundenHoechstens)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () =>
                            bereichOeffnen(context, EntwicklungsBereich.kunden),
                        child: Text(
                          'und ${ordner.length - _kundenHoechstens} weitere',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

// ── Was ansteht ───────────────────────────────────────────────────────

class _AnstehtBereich extends StatelessWidget {
  const _AnstehtBereich({
    super.key,
    required this.faellig,
    required this.ruhend,
    required this.heute,
  });

  final List<FaelligerEintrag> faellig;
  final List<RuhendesProjekt> ruhend;
  final DateTime heute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final farben = AppFarben.von(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final ueber = faellig.where((f) => f.ueberfaellig).length;
    return Bereich(
      titel: 'Was ansteht',
      icon: Icons.event_note_outlined,
      untertitel: ueber > 0
          ? '$ueber überfällig'
          : 'die nächsten $kBaldFaelligTage Tage',
      innenAbstand: const EdgeInsets.fromLTRB(0, 4, 0, 6),
      child: faellig.isEmpty && ruhend.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: LeerHinweis(
                'Nichts überfällig, nichts fällig in den nächsten '
                '$kBaldFaelligTage Tagen und kein Projekt, das ruht.',
                icon: Icons.event_available_outlined,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final f in faellig.take(_anstehtHoechstens))
                  _AnstehtZeile(
                    key: ValueKey('ansteht-${f.eintrag.id}'),
                    icon: f.ueberfaellig
                        ? Icons.event_busy_outlined
                        : Icons.event_outlined,
                    farbe: f.ueberfaellig ? farben.fehler : grau,
                    titel: f.eintrag.titel,
                    unter: f.ueberfaellig
                        ? '${f.zielName} · überfällig seit '
                            '${Format.datumKurz(f.am)}'
                        : '${f.zielName} · fällig '
                            '${faelligText(f.am, heute)}',
                    onTap: () => f.gesamtprojekt
                        ? oeffneGesamtprojekt(context, f.zielId)
                        : oeffneProjekt(context, f.zielId),
                  ),
                if (faellig.length > _anstehtHoechstens)
                  _Mehr(
                    text: 'und ${faellig.length - _anstehtHoechstens} '
                        'weitere Einträge',
                  ),
                for (final r in ruhend.take(_anstehtHoechstens))
                  _AnstehtZeile(
                    key: ValueKey('ruht-${r.projekt.id}'),
                    icon: Icons.bedtime_outlined,
                    farbe: farben.warnung,
                    titel: r.projekt.name,
                    unter: 'in Arbeit, seit ${r.tage} Tagen nichts getan',
                    onTap: () => oeffneProjekt(context, r.projekt.id),
                  ),
                if (ruhend.length > _anstehtHoechstens)
                  _Mehr(
                    text: 'und ${ruhend.length - _anstehtHoechstens} weitere '
                        'ruhende Projekte',
                  ),
              ],
            ),
    );
  }
}

class _AnstehtZeile extends StatelessWidget {
  const _AnstehtZeile({
    super.key,
    required this.icon,
    required this.farbe,
    required this.titel,
    required this.unter,
    required this.onTap,
  });

  final IconData icon;
  final Color farbe;
  final String titel;
  final String unter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 18, color: farbe),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    titel,
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
    );
  }
}

/// „und 3 weitere" unter einer gekürzten Liste.
class _Mehr extends StatelessWidget {
  const _Mehr({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 4, 12, 4),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

// ── Suche ─────────────────────────────────────────────────────────────

class _Suchergebnis extends StatelessWidget {
  const _Suchergebnis({
    required this.treffer,
    required this.projekte,
    required this.aktivitaet,
    required this.checklisten,
    required this.heute,
  });

  final UebersichtTreffer treffer;

  /// Alle Projekte — für die Muster der Gesamtprojekte und die Projekte
  /// der Rezepturen.
  final List<EntwicklungsProjekt> projekte;
  final Map<String, DateTime> aktivitaet;
  final Map<String, ProjektCheckStand>? checklisten;
  final DateTime heute;

  @override
  Widget build(BuildContext context) {
    final t = treffer;
    final anzahl =
        t.projekte.length + t.gesamtprojekte.length + t.rezepturen.length;
    final namen = {for (final p in projekte) p.id: p.name};
    return Bereich(
      titel: 'Suche',
      icon: Icons.search,
      untertitel: anzahl == 0
          ? 'keine Treffer'
          : anzahl == 1
              ? '1 Treffer'
              : '$anzahl Treffer',
      innenAbstand: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: anzahl == 0
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: LeerHinweis('Keine Treffer.', icon: Icons.search_off),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (t.projekte.isNotEmpty) ...[
                  const _Zwischentitel('PROJEKTE'),
                  for (final p in t.projekte)
                    ProjektKurzZeile(
                      projekt: p,
                      zuletzt: aktivitaet[p.id] ?? p.updatedAt,
                      heute: heute,
                      checkliste: checklisten?[p.id],
                      zusatz: p.kunde,
                    ),
                ],
                if (t.gesamtprojekte.isNotEmpty) ...[
                  const _Zwischentitel('GESAMTPROJEKTE'),
                  for (final g in t.gesamtprojekte)
                    GesamtKurzZeile(
                      gesamtprojekt: g,
                      muster: [
                        for (final p in projekte)
                          if (p.gesamtprojektId == g.id) p,
                      ],
                      zuletzt: g.updatedAt,
                      heute: heute,
                    ),
                ],
                if (t.rezepturen.isNotEmpty) ...[
                  const _Zwischentitel('REZEPTUREN'),
                  for (final r in t.rezepturen)
                    _RezepturZeile(
                      rezeptur: r,
                      projekt: namen[r.projektId],
                    ),
                ],
              ],
            ),
    );
  }
}

class _Zwischentitel extends StatelessWidget {
  const _Zwischentitel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _RezepturZeile extends StatelessWidget {
  const _RezepturZeile({required this.rezeptur, required this.projekt});

  final Rezeptur rezeptur;

  /// Der Name des Projekts, zu dem sie gehört.
  final String? projekt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final nummer = rezeptur.artikelnummer?.trim() ?? '';
    final unter = [
      if (nummer.isNotEmpty) 'Nr. $nummer',
      if (projekt case final p?) 'im Projekt $p' else 'ohne Projekt',
    ].join(' · ');
    return InkWell(
      key: ValueKey('rezepturzeile-${rezeptur.id}'),
      onTap: () => oeffneRezeptur(context, rezeptur.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Row(
          children: [
            Icon(Icons.menu_book_outlined, size: 20, color: grau),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    rezeptur.name,
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
          ],
        ),
      ),
    );
  }
}
