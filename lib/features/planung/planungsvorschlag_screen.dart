import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/database_provider.dart';
import '../../core/utils/zeit.dart';
import 'planungsvorschlag_service.dart';

/// Vorschlagsansicht: zeigt, wie die nächsten Tage aussehen könnten, und
/// überträgt einzelne Tage ins Board.
///
/// Bewusst getrennt vom Board: Hier wird gerechnet und verworfen, dort
/// geplant. Nichts auf dieser Seite verändert Daten, bis der Anwender auf
/// „Tag übernehmen" tippt.
class PlanungsvorschlagScreen extends ConsumerStatefulWidget {
  const PlanungsvorschlagScreen({super.key});

  @override
  ConsumerState<PlanungsvorschlagScreen> createState() =>
      _PlanungsvorschlagScreenState();
}

class _PlanungsvorschlagScreenState
    extends ConsumerState<PlanungsvorschlagScreen> {
  VorschlagEinstellungen _einstellungen = const VorschlagEinstellungen();
  Future<Planungsvorschlag>? _lauf;

  /// Tage, die der Anwender in dieser Sitzung schon übernommen hat —
  /// sie bleiben stehen, aber ohne Knopf, damit nichts doppelt landet.
  final Set<String> _uebernommen = <String>{};

  @override
  void initState() {
    super.initState();
    _rechne();
  }

  void _rechne() {
    final db = ref.read(databaseProvider);
    setState(() {
      _uebernommen.clear();
      _lauf = PlanungsvorschlagService(db).berechne(_einstellungen);
    });
  }

  Future<void> _uebernehmen(VorschlagTag t) async {
    final db = ref.read(databaseProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final anzahl = await PlanungsvorschlagService(db).uebernehmeTag(t);
      if (!mounted) return;
      setState(() => _uebernommen.add(_key(t.tag)));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '$anzahl ${anzahl == 1 ? 'Auftrag' : 'Aufträge'} für '
            '${_datum(t.tag)} ins Board übernommen.',
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

  @override
  Widget build(BuildContext context) {
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
            onPressed: _rechne,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Neu berechnen',
          ),
        ],
      ),
      body: FutureBuilder<Planungsvorschlag>(
        future: _lauf,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Fehler: ${snap.error}'));
          }
          final v = snap.data;
          if (v == null) return const SizedBox.shrink();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Kopfzeile(vorschlag: v),
              const SizedBox(height: 12),
              if (v.istLeer)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Aus dem offenen Bedarf lässt sich gerade nichts '
                      'einplanen. Die Liste unten sagt warum.',
                    ),
                  ),
                ),
              for (final t in v.tage)
                _TagKarte(
                  tag: t,
                  bereitsUebernommen: _uebernommen.contains(_key(t.tag)),
                  onUebernehmen: () => _uebernehmen(t),
                ),
              if (v.nichtPlanbar.isNotEmpty) ...[
                const SizedBox(height: 8),
                _NichtPlanbarKarte(eintraege: v.nichtPlanbar),
              ],
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
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
    _rechne();
  }

  static String _key(DateTime d) => '${d.year}-${d.month}-${d.day}';

  static String _datum(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.';
}

// ═══════════════════════════════════════════════════════════════════════
// Kopf
// ═══════════════════════════════════════════════════════════════════════

class _Kopfzeile extends StatelessWidget {
  const _Kopfzeile({required this.vorschlag});

  final Planungsvorschlag vorschlag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = vorschlag.einstellungen;
    final posten =
        vorschlag.tage.fold<int>(0, (s, t) => s + t.posten.length);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$posten ${posten == 1 ? 'Auftrag' : 'Aufträge'} auf '
              '${vorschlag.tage.length} '
              '${vorschlag.tage.length == 1 ? 'Tag' : 'Tagen'}',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Reihenfolge: Allergene aufsteigend, Bio vor konventionell, '
              'roh nach gegart, dann ähnliche Bratstraßen-Einstellungen '
              'gebündelt.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _Pille('Rüsten ${e.ruestenMinuten.round()} min'),
                _Pille('Reinigen ${e.zwischenreinigungMinuten.round()} min'),
                _Pille('Endreinigung ${e.endreinigungMinuten.round()} min'),
                _Pille('max. ${e.maxArbeitstage} Arbeitstage'),
                if (e.planeSamstag) const _Pille('inkl. Samstag'),
                if (e.gesperrteTage.isNotEmpty)
                  _Pille('${e.gesperrteTage.length} Tage gesperrt'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Pille extends StatelessWidget {
  const _Pille(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: theme.textTheme.bodySmall),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Tageskarte
// ═══════════════════════════════════════════════════════════════════════

class _TagKarte extends StatelessWidget {
  const _TagKarte({
    required this.tag,
    required this.bereitsUebernommen,
    required this.onUebernehmen,
  });

  final VorschlagTag tag;
  final bool bereitsUebernommen;
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
    final voll = tag.auslastung > 1;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_wochentage[tag.tag.weekday - 1]}, '
                    '${tag.tag.day.toString().padLeft(2, '0')}.'
                    '${tag.tag.month.toString().padLeft(2, '0')}.'
                    '${tag.tag.year}',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  '${(tag.auslastung * 100).round()} %',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: voll
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (tag.belegtVorherMinuten > 0)
                  'bereits im Board ${Zeit.kurz(tag.belegtVorherMinuten)}',
                'neu ${Zeit.kurz(tag.neuMinuten)}',
                'Kapazität ${Zeit.kurz(tag.kapazitaetMinuten)}',
                '${tag.posten.fold<double>(0, (s, p) => s + p.rohwareKg).round()} kg Rohware',
              ].join(' · '),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            for (final p in tag.posten) _PostenZeile(posten: p),
            if (tag.endreinigungMinuten > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.cleaning_services_outlined,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Endreinigung '
                      '${Zeit.kurz(tag.endreinigungMinuten)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            if (tag.warnungen.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final w in tag.warnungen)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        w,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: bereitsUebernommen
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          size: 18,
                          color: Colors.green.shade600,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'übernommen',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    )
                  : FilledButton.icon(
                      onPressed: onUebernehmen,
                      icon: const Icon(Icons.playlist_add_rounded, size: 18),
                      label: const Text('Tag ins Board übernehmen'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostenZeile extends StatelessWidget {
  const _PostenZeile({required this.posten});

  final VorschlagPosten posten;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Der Wechselgrund steht ÜBER der Zeile, nicht daneben: Er gehört
    // zum Übergang vom vorherigen Artikel, nicht zum Artikel selbst.
    final wechsel = switch (posten.wechselGrund) {
      WechselGrund.tagesstart => null,
      WechselGrund.ohneUmstellung => 'ohne Umstellung',
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
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  posten.wechselGrund == WechselGrund.reinigen
                      ? Icons.cleaning_services_outlined
                      : Icons.swap_horiz_rounded,
                  size: 14,
                  color: posten.wechselGrund == WechselGrund.reinigen
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  wechsel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: posten.wechselGrund == WechselGrund.reinigen
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 54,
                child: Text(
                  posten.artikelnummer,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
              ),
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
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${posten.mengeKg.round()} kg · '
                    '${Zeit.kurz(posten.dauerMinuten)}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  // Rohware ist die Zahl, die für Bestellung und
                  // Verfügbarkeit zählt — sie kommt über die Ausbeute aus
                  // der Historie und steht deshalb gleich daneben.
                  Text(
                    '${posten.rohwareKg.round()} kg roh'
                    '${posten.ausHistorie ? ' · Ø Historie' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nicht eingeplant (${eintraege.length})',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final n in eintraege)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 54,
                      child: Text(
                        n.artikelnummer,
                        style: theme.textTheme.bodyMedium
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
    _ruesten = TextEditingController(text: e.ruestenMinuten.round().toString());
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

  Widget _zahlFeld(
    TextEditingController c,
    String label,
    String suffix,
  ) {
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
