import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/providers/database_provider.dart';
import '../../core/utils/zeit.dart';
import 'planungsvorschlag_service.dart';

/// Vorschlagsansicht: zeigt, wie die nächsten Tage aussehen könnten, und
/// überträgt einzelne Tage ins Board.
///
/// Der Vorschlag ist ein **Entwurf**. Mengen lassen sich ändern, die
/// Reihenfolge umstellen, Posten entfernen oder auf einen Nachbartag
/// schieben — alles nur in der Ansicht. Erst „Tag ins Board übernehmen"
/// schreibt etwas. Nach jeder Änderung rechnet [Planungsrechner] die
/// Nebenzeiten neu, sodass sofort sichtbar ist, was eine Umstellung
/// kostet oder spart.
class PlanungsvorschlagScreen extends ConsumerStatefulWidget {
  const PlanungsvorschlagScreen({super.key});

  @override
  ConsumerState<PlanungsvorschlagScreen> createState() =>
      _PlanungsvorschlagScreenState();
}

class _PlanungsvorschlagScreenState
    extends ConsumerState<PlanungsvorschlagScreen> {
  VorschlagEinstellungen _einstellungen = const VorschlagEinstellungen();

  bool _laedt = true;
  Object? _fehler;

  List<VorschlagTag> _tage = [];
  List<NichtPlanbar> _nichtPlanbar = [];

  /// Tage, die in dieser Sitzung schon übernommen wurden.
  final Set<String> _uebernommen = <String>{};

  /// Tage, deren Reihenfolge von Hand geändert wurde.
  final Set<String> _manuell = <String>{};

  bool _geaendert = false;

  @override
  void initState() {
    super.initState();
    _rechne();
  }

  Future<void> _rechne() async {
    setState(() {
      _laedt = true;
      _fehler = null;
    });
    try {
      final db = ref.read(databaseProvider);
      final v = await PlanungsvorschlagService(db).berechne(_einstellungen);
      if (!mounted) return;
      setState(() {
        _tage = [...v.tage];
        _nichtPlanbar = [...v.nichtPlanbar];
        _uebernommen.clear();
        _manuell.clear();
        _geaendert = false;
        _laedt = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fehler = e;
        _laedt = false;
      });
    }
  }

  // ── Bearbeiten ───────────────────────────────────────────────────────

  void _ersetzeTag(int index, VorschlagTag neu) {
    setState(() {
      _tage[index] = neu;
      _geaendert = true;
    });
  }

  void _sortiereNeu(int tagIndex, int von, int nach) {
    final t = _tage[tagIndex];
    final posten = [...t.posten];
    // `onReorder` liefert den Zielindex VOR dem Entfernen des Elements —
    // beim Verschieben nach unten muss deshalb um eins zurückgezählt
    // werden. Das neuere `onReorderItem` täte das selbst, fehlt aber in
    // der Flutter-Version der CI; deshalb bleibt es bei onReorder.
    if (nach > von) nach -= 1;
    posten.insert(nach, posten.removeAt(von));
    _manuell.add(_key(t.tag));
    _ersetzeTag(
      tagIndex,
      t.kopieMit(
        posten: Planungsrechner.mitNebenzeiten(posten, _einstellungen),
      ),
    );
  }

  void _nachRegeln(int tagIndex) {
    final t = _tage[tagIndex];
    _manuell.remove(_key(t.tag));
    _ersetzeTag(
      tagIndex,
      t.kopieMit(
        posten: Planungsrechner.mitNebenzeiten(
          Planungsrechner.nachRegeln(t.posten),
          _einstellungen,
        ),
      ),
    );
  }

  void _entferne(int tagIndex, VorschlagPosten p) {
    final t = _tage[tagIndex];
    final posten = [...t.posten]..remove(p);
    _ersetzeTag(
      tagIndex,
      t.kopieMit(
        posten: Planungsrechner.mitNebenzeiten(posten, _einstellungen),
      ),
    );
    setState(() {
      _nichtPlanbar = [
        ..._nichtPlanbar,
        NichtPlanbar(
          artikelnummer: p.artikelnummer,
          bezeichnung: p.bezeichnung,
          mengeKg: p.mengeKg,
          grund: 'Von Hand aus dem Vorschlag genommen',
        ),
      ];
    });
  }

  /// Posten auf den Nachbartag schieben. Bewusst nur Nachbarn: Der
  /// Vorschlag ist fortlaufend, und alles andere bräuchte eine
  /// Datumsauswahl für wenig Gewinn.
  void _verschiebe(int tagIndex, VorschlagPosten p, int richtung) {
    final ziel = tagIndex + richtung;
    if (ziel < 0 || ziel >= _tage.length) return;

    final von = _tage[tagIndex];
    final nach = _tage[ziel];
    final vonPosten = [...von.posten]..remove(p);
    final nachPosten = Planungsrechner.nachRegeln([...nach.posten, p]);

    setState(() {
      _tage[tagIndex] = von.kopieMit(
        posten: Planungsrechner.mitNebenzeiten(vonPosten, _einstellungen),
      );
      _tage[ziel] = nach.kopieMit(
        posten: Planungsrechner.mitNebenzeiten(nachPosten, _einstellungen),
      );
      _manuell.remove(_key(nach.tag));
      _geaendert = true;
    });
  }

  Future<void> _aendereMenge(int tagIndex, VorschlagPosten p) async {
    final neu = await showDialog<double>(
      context: context,
      builder: (_) => _MengeDialog(posten: p),
    );
    if (neu == null || neu <= 0) return;
    final t = _tage[tagIndex];
    final posten = [
      for (final x in t.posten)
        if (identical(x, p)) p.mitMenge(neu) else x,
    ];
    _ersetzeTag(
      tagIndex,
      t.kopieMit(
        posten: Planungsrechner.mitNebenzeiten(posten, _einstellungen),
      ),
    );
  }

  Future<void> _uebernehmen(int tagIndex) async {
    final t = _tage[tagIndex];
    final db = ref.read(databaseProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final anzahl = await PlanungsvorschlagService(db).uebernehmeTag(t);
      if (!mounted) return;
      setState(() => _uebernommen.add(_key(t.tag)));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '$anzahl ${anzahl == 1 ? 'Auftrag' : 'Aufträge'} ins Board '
            'übernommen.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ── Aufbau ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Planungsvorschlag'),
        actions: [
          IconButton(
            onPressed: _oeffneEinstellungen,
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Zeiten und Zeitraum',
          ),
          IconButton(
            onPressed: _laedt ? null : _bestaetigeNeuberechnung,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Neu berechnen',
          ),
        ],
      ),
      body: _laedt
          ? const Center(child: CircularProgressIndicator())
          : _fehler != null
              ? Center(child: Text('Fehler: $_fehler'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                  children: [
                    _Kopfzeile(
                      tage: _tage,
                      einstellungen: _einstellungen,
                      geaendert: _geaendert,
                    ),
                    const SizedBox(height: 14),
                    if (_tage.every((t) => t.posten.isEmpty))
                      _LeerKarte(hatReste: _nichtPlanbar.isNotEmpty),
                    for (var i = 0; i < _tage.length; i++)
                      if (_tage[i].posten.isNotEmpty)
                        _TagKarte(
                          tag: _tage[i],
                          manuellSortiert:
                              _manuell.contains(_key(_tage[i].tag)),
                          uebernommen:
                              _uebernommen.contains(_key(_tage[i].tag)),
                          kannZurueck: i > 0,
                          kannVor: i < _tage.length - 1,
                          onReorder: (von, nach) => _sortiereNeu(i, von, nach),
                          onNachRegeln: () => _nachRegeln(i),
                          onMenge: (p) => _aendereMenge(i, p),
                          onEntfernen: (p) => _entferne(i, p),
                          onVerschieben: (p, richtung) =>
                              _verschiebe(i, p, richtung),
                          onUebernehmen: () => _uebernehmen(i),
                        ),
                    if (_nichtPlanbar.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _NichtPlanbarKarte(eintraege: _nichtPlanbar),
                    ],
                  ],
                ),
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
    );
  }

  Future<void> _bestaetigeNeuberechnung() async {
    if (_geaendert) {
      final weiter = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Änderungen verwerfen?'),
          content: const Text(
            'Der Vorschlag wurde von Hand angepasst. Neu berechnen setzt '
            'Mengen und Reihenfolgen zurück.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Neu berechnen'),
            ),
          ],
        ),
      );
      if (weiter != true) return;
    }
    await _rechne();
  }

  Future<void> _oeffneEinstellungen() async {
    final neu = await showModalBottomSheet<VorschlagEinstellungen>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EinstellungenSheet(start: _einstellungen),
    );
    if (neu == null) return;
    setState(() => _einstellungen = neu);
    await _rechne();
  }

  static String _key(DateTime d) => '${d.year}-${d.month}-${d.day}';
}

// ═══════════════════════════════════════════════════════════════════════
// Kopf
// ═══════════════════════════════════════════════════════════════════════

class _Kopfzeile extends StatelessWidget {
  const _Kopfzeile({
    required this.tage,
    required this.einstellungen,
    required this.geaendert,
  });

  final List<VorschlagTag> tage;
  final VorschlagEinstellungen einstellungen;
  final bool geaendert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final farbe = Abteilung.bratstrasse.farbe;
    final posten = tage.fold<int>(0, (s, t) => s + t.posten.length);
    final tageMitInhalt = tage.where((t) => t.posten.isNotEmpty).length;
    final rohware = tage.fold<double>(0, (s, t) => s + t.rohwareKg);
    final e = einstellungen;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: [
            farbe.withValues(alpha: 0.14),
            farbe.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: farbe.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 20, color: farbe),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$posten ${posten == 1 ? 'Auftrag' : 'Aufträge'} · '
                  '$tageMitInhalt ${tageMitInhalt == 1 ? 'Tag' : 'Tage'} · '
                  '${rohware.round()} kg Rohware',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (geaendert)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'angepasst',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Allergene aufsteigend · Bio vor konventionell · roh nach '
            'gegart · dann ähnliche Bratstraßen-Einstellungen',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Pille('Rüsten ${e.ruestenMinuten.round()} min'),
              _Pille('Reinigen ${e.zwischenreinigungMinuten.round()} min'),
              _Pille('Endreinigung ${e.endreinigungMinuten.round()} min'),
              _Pille('${e.maxArbeitstage} Arbeitstage'),
              if (e.planeSamstag) const _Pille('inkl. Samstag'),
              if (e.gesperrteTage.isNotEmpty)
                _Pille('${e.gesperrteTage.length} gesperrt'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pille extends StatelessWidget {
  const _Pille(this.text, {this.farbe});

  final String text;
  final Color? farbe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = farbe ?? theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(fontSize: 11, color: c),
      ),
    );
  }
}

class _LeerKarte extends StatelessWidget {
  const _LeerKarte({required this.hatReste});

  final bool hatReste;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          hatReste
              ? 'Aus dem offenen Bedarf lässt sich gerade nichts einplanen. '
                  'Die Liste unten nennt zu jedem Artikel den Grund.'
              : 'Kein offener Bedarf.',
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Tageskarte
// ═══════════════════════════════════════════════════════════════════════

class _TagKarte extends StatelessWidget {
  const _TagKarte({
    required this.tag,
    required this.manuellSortiert,
    required this.uebernommen,
    required this.kannZurueck,
    required this.kannVor,
    required this.onReorder,
    required this.onNachRegeln,
    required this.onMenge,
    required this.onEntfernen,
    required this.onVerschieben,
    required this.onUebernehmen,
  });

  final VorschlagTag tag;
  final bool manuellSortiert;
  final bool uebernommen;
  final bool kannZurueck;
  final bool kannVor;
  final void Function(int von, int nach) onReorder;
  final VoidCallback onNachRegeln;
  final void Function(VorschlagPosten) onMenge;
  final void Function(VorschlagPosten) onEntfernen;
  final void Function(VorschlagPosten, int richtung) onVerschieben;
  final VoidCallback onUebernehmen;

  static const _wochentage = [
    'Montag',
    'Dienstag',
    'Mittwoch',
    'Donnerstag',
    'Freitag',
    'Samstag',
    'Sonntag',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final farbe = Abteilung.bratstrasse.farbe;
    final voll = tag.auslastung > 1;
    final brueche = Planungsrechner.regelbrueche(tag.posten);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Kopf mit Auslastungsbalken ──────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              color: farbe.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(13),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_wochentage[tag.tag.weekday - 1]}, '
                        '${_zwei(tag.tag.day)}.${_zwei(tag.tag.month)}.'
                        '${tag.tag.year}',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (uebernommen) ...[
                      Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: Colors.green.shade600,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      '${(tag.auslastung * 100).round()} %',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: voll ? theme.colorScheme.error : farbe,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: tag.auslastung.clamp(0, 1).toDouble(),
                    minHeight: 6,
                    backgroundColor:
                        theme.colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(
                      voll ? theme.colorScheme.error : farbe,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (tag.belegtVorherMinuten > 0)
                      _Pille(
                        'im Board ${Zeit.kurz(tag.belegtVorherMinuten)}',
                      ),
                    _Pille('neu ${Zeit.kurz(tag.neuMinuten)}'),
                    _Pille('von ${Zeit.kurz(tag.kapazitaetMinuten)}'),
                    _Pille('${tag.rohwareKg.round()} kg Rohware'),
                    if (manuellSortiert)
                      _Pille(
                        'manuell sortiert',
                        farbe: theme.colorScheme.primary,
                      ),
                  ],
                ),
              ],
            ),
          ),

          // ── Posten, per Griff umsortierbar ──────────────────────────
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: tag.posten.length,
            // Die Flutter-Version der CI kennt `onReorderItem` noch nicht,
            // die lokale hält `onReorder` bereits für veraltet. Bis beide
            // auf derselben Version sind, gewinnt die CI — ein Fehler dort
            // wiegt schwerer als ein Hinweis im Terminal.
            // ignore: deprecated_member_use
            onReorder: onReorder,
            itemBuilder: (context, i) {
              final p = tag.posten[i];
              return _PostenZeile(
                key: ValueKey('${p.productId}-${p.bedarfId}-$i'),
                index: i,
                posten: p,
                kannZurueck: kannZurueck,
                kannVor: kannVor,
                onMenge: () => onMenge(p),
                onEntfernen: () => onEntfernen(p),
                onVerschieben: (r) => onVerschieben(p, r),
              );
            },
          ),

          // ── Fuß ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (tag.endreinigungMinuten > 0)
                  _Hinweis(
                    icon: Icons.cleaning_services_outlined,
                    text:
                        'Endreinigung ${Zeit.kurz(tag.endreinigungMinuten)}',
                  ),
                for (final b in brueche)
                  _Hinweis(
                    icon: Icons.warning_amber_rounded,
                    text: b,
                    farbe: theme.colorScheme.error,
                  ),
                if (tag.warnungen.isNotEmpty)
                  Theme(
                    data: theme.copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: 8),
                      dense: true,
                      leading: Icon(
                        Icons.info_outline,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      title: Text(
                        '${tag.warnungen.length} '
                        '${tag.warnungen.length == 1 ? 'Hinweis' : 'Hinweise'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      children: [
                        for (final w in tag.warnungen)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                w,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (manuellSortiert)
                      TextButton.icon(
                        onPressed: onNachRegeln,
                        icon: const Icon(Icons.sort_rounded, size: 18),
                        label: const Text('Nach Regeln sortieren'),
                      ),
                    const Spacer(),
                    if (uebernommen)
                      Text('übernommen', style: theme.textTheme.bodySmall)
                    else
                      FilledButton.icon(
                        onPressed: onUebernehmen,
                        icon: const Icon(Icons.playlist_add_rounded, size: 18),
                        label: const Text('Tag ins Board übernehmen'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _zwei(int v) => v.toString().padLeft(2, '0');
}

class _Hinweis extends StatelessWidget {
  const _Hinweis({required this.icon, required this.text, this.farbe});

  final IconData icon;
  final String text;
  final Color? farbe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = farbe ?? theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: c),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: c),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Postenzeile
// ═══════════════════════════════════════════════════════════════════════

class _PostenZeile extends StatelessWidget {
  const _PostenZeile({
    required super.key,
    required this.index,
    required this.posten,
    required this.kannZurueck,
    required this.kannVor,
    required this.onMenge,
    required this.onEntfernen,
    required this.onVerschieben,
  });

  final int index;
  final VorschlagPosten posten;
  final bool kannZurueck;
  final bool kannVor;
  final VoidCallback onMenge;
  final VoidCallback onEntfernen;
  final void Function(int richtung) onVerschieben;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reinigen = posten.wechselGrund == WechselGrund.reinigen;

    // Der Wechsel gehört zum ÜBERGANG, nicht zum Artikel — deshalb steht
    // er als eigene, eingerückte Zeile darüber.
    final wechsel = switch (posten.wechselGrund) {
      WechselGrund.tagesstart => null,
      WechselGrund.ohneUmstellung => 'kein Umstellen nötig',
      WechselGrund.umstellen =>
        'umrüsten ${Zeit.kurz(posten.nebenzeitMinuten)}',
      WechselGrund.reinigen =>
        'reinigen ${Zeit.kurz(posten.nebenzeitMinuten)}',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (wechsel != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(52, 2, 16, 2),
            child: Row(
              children: [
                Icon(
                  reinigen
                      ? Icons.cleaning_services_rounded
                      : Icons.swap_horiz_rounded,
                  size: 13,
                  color: reinigen
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  wechsel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: reinigen
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        InkWell(
          onTap: onMenge,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    size: 18,
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 46,
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    posten.artikelnummer,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        posten.bezeichnung,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (posten.begruendung.isNotEmpty)
                        Text(
                          posten.begruendung,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${posten.mengeKg.round()} kg',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${Zeit.kurz(posten.dauerMinuten)} · '
                      '${posten.rohwareKg.round()} kg roh',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                PopupMenuButton<String>(
                  tooltip: 'Ändern',
                  icon: Icon(
                    Icons.more_vert_rounded,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'menge',
                      child: Text('Menge ändern …'),
                    ),
                    if (kannZurueck)
                      const PopupMenuItem(
                        value: 'zurueck',
                        child: Text('Einen Tag früher'),
                      ),
                    if (kannVor)
                      const PopupMenuItem(
                        value: 'vor',
                        child: Text('Einen Tag später'),
                      ),
                    const PopupMenuItem(
                      value: 'weg',
                      child: Text('Aus dem Vorschlag nehmen'),
                    ),
                  ],
                  onSelected: (w) {
                    switch (w) {
                      case 'menge':
                        onMenge();
                      case 'zurueck':
                        onVerschieben(-1);
                      case 'vor':
                        onVerschieben(1);
                      case 'weg':
                        onEntfernen();
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Mengendialog
// ═══════════════════════════════════════════════════════════════════════

class _MengeDialog extends StatefulWidget {
  const _MengeDialog({required this.posten});

  final VorschlagPosten posten;

  @override
  State<_MengeDialog> createState() => _MengeDialogState();
}

class _MengeDialogState extends State<_MengeDialog> {
  late final TextEditingController _menge;

  @override
  void initState() {
    super.initState();
    _menge = TextEditingController(
      text: widget.posten.mengeKg.round().toString(),
    );
  }

  @override
  void dispose() {
    _menge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.posten;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('${p.artikelnummer} — Menge'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.bezeichnung, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _menge,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Fertigmenge',
              suffixText: 'kg',
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Dauer und Rohware skalieren mit. Feste Durchlaufzeiten der '
            'Anlagen tun das nicht — bei großen Änderungen lieber neu '
            'berechnen lassen.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            double.tryParse(_menge.text.trim().replaceAll(',', '.')),
          ),
          child: const Text('Übernehmen'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Restliste
// ═══════════════════════════════════════════════════════════════════════

class _NichtPlanbarKarte extends StatelessWidget {
  const _NichtPlanbarKarte({required this.eintraege});

  final List<NichtPlanbar> eintraege;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          leading: Icon(
            Icons.inbox_rounded,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          title: Text(
            'Nicht eingeplant (${eintraege.length})',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          children: [
            for (final n in eintraege)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 52,
                      child: Text(
                        n.artikelnummer,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.primary),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            n.bezeichnung,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                          Text(
                            n.grund,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${n.mengeKg.round()} kg',
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

// ═══════════════════════════════════════════════════════════════════════
// Einstellungen
// ═══════════════════════════════════════════════════════════════════════

class _EinstellungenSheet extends StatefulWidget {
  const _EinstellungenSheet({required this.start});

  final VorschlagEinstellungen start;

  @override
  State<_EinstellungenSheet> createState() => _EinstellungenSheetState();
}

class _EinstellungenSheetState extends State<_EinstellungenSheet> {
  late final TextEditingController _ruesten;
  late final TextEditingController _reinigen;
  late final TextEditingController _endreinigung;
  late final TextEditingController _tage;
  late bool _samstag;
  late DateTime? _start;
  late Set<DateTime> _gesperrt;

  @override
  void initState() {
    super.initState();
    final e = widget.start;
    _ruesten =
        TextEditingController(text: e.ruestenMinuten.round().toString());
    _reinigen = TextEditingController(
      text: e.zwischenreinigungMinuten.round().toString(),
    );
    _endreinigung = TextEditingController(
      text: e.endreinigungMinuten.round().toString(),
    );
    _tage = TextEditingController(text: e.maxArbeitstage.toString());
    _samstag = e.planeSamstag;
    _start = e.startTag;
    _gesperrt = {...e.gesperrteTage};
  }

  @override
  void dispose() {
    _ruesten.dispose();
    _reinigen.dispose();
    _endreinigung.dispose();
    _tage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Zeiten und Zeitraum',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Die Nebenzeiten sind Pauschalen. Sobald beim Erfassen echte '
              'Rüst- und Reinigungszeiten anfallen, lassen sie sich daran '
              'ausrichten.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _zahlFeld(_ruesten, 'Umrüsten', 'min')),
                const SizedBox(width: 10),
                Expanded(child: _zahlFeld(_reinigen, 'Reinigen', 'min')),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _zahlFeld(_endreinigung, 'Endreinigung', 'min'),
                ),
                const SizedBox(width: 10),
                Expanded(child: _zahlFeld(_tage, 'Zeitraum', 'Tage')),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _samstag,
              onChanged: (v) => setState(() => _samstag = v),
              title: const Text('Samstag mitplanen'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_rounded),
              title: const Text('Beginn'),
              subtitle: Text(_start == null ? 'morgen' : _datum(_start!)),
              trailing: TextButton(
                onPressed: _waehleStart,
                child: const Text('ändern'),
              ),
            ),
            // Gesperrte Tage sind der Platz für alles Äußere: fehlende
            // Rohware, Wartung, Feiertag, Inventur.
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.block_rounded),
              title: const Text('Gesperrte Tage'),
              subtitle: Text(
                _gesperrt.isEmpty
                    ? 'keine — z.B. Feiertag oder fehlende Rohware'
                    : (_gesperrt.toList()..sort()).map(_datum).join(', '),
              ),
              trailing: TextButton(
                onPressed: _waehleGesperrt,
                child: const Text('hinzufügen'),
              ),
            ),
            if (_gesperrt.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(_gesperrt.clear),
                  child: const Text('Sperren aufheben'),
                ),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _fertig,
                child: const Text('Neu berechnen'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _zahlFeld(TextEditingController c, String label, String suffix) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, suffixText: suffix),
    );
  }

  Future<void> _waehleStart() async {
    final heute = DateTime.now();
    final gewaehlt = await showDatePicker(
      context: context,
      initialDate: _start ?? heute.add(const Duration(days: 1)),
      firstDate: heute.subtract(const Duration(days: 1)),
      lastDate: heute.add(const Duration(days: 180)),
    );
    if (gewaehlt != null) setState(() => _start = gewaehlt);
  }

  Future<void> _waehleGesperrt() async {
    final heute = DateTime.now();
    final gewaehlt = await showDatePicker(
      context: context,
      initialDate: _start ?? heute.add(const Duration(days: 1)),
      firstDate: heute,
      lastDate: heute.add(const Duration(days: 180)),
      helpText: 'Tag sperren',
    );
    if (gewaehlt == null) return;
    setState(
      () => _gesperrt.add(
        DateTime(gewaehlt.year, gewaehlt.month, gewaehlt.day),
      ),
    );
  }

  void _fertig() {
    double zahl(TextEditingController c, double standard) =>
        double.tryParse(c.text.trim().replaceAll(',', '.')) ?? standard;

    Navigator.of(context).pop(
      widget.start.kopieMit(
        ruestenMinuten: zahl(_ruesten, widget.start.ruestenMinuten),
        zwischenreinigungMinuten:
            zahl(_reinigen, widget.start.zwischenreinigungMinuten),
        endreinigungMinuten:
            zahl(_endreinigung, widget.start.endreinigungMinuten),
        maxArbeitstage:
            int.tryParse(_tage.text.trim()) ?? widget.start.maxArbeitstage,
        planeSamstag: _samstag,
        gesperrteTage: _gesperrt,
        startTag: _start,
      ),
    );
  }

  static String _datum(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.';
}
