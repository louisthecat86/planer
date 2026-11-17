import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';
import '../../core/services/navision_katalog.dart';
import '../../core/services/prozess_vorlagen.dart';
import '../../core/ui/bausteine.dart';
import '../../core/ui/rueckgaengig.dart';
import '../../core/utils/fehler_text.dart';

/// Ein Artikel ohne Prozess mit dem Vorschlag dazu.
class ZuordnungsZeile {
  ZuordnungsZeile({
    required this.artikel,
    required this.vorschlag,
    String? text,
  })  : text = text ?? artikel.artikelbezeichnung,
        gewaehlt = vorschlag.vorlage,
        an = vorschlag.sicher;

  final Product artikel;

  /// Bezeichnung und „Beschreibung 2" — darin wurde gesucht.
  final String text;
  final VorlagenVorschlag vorschlag;

  /// Die Vorlage, die er bekommen soll — null: keine.
  ProzessVorlage? gewaehlt;

  /// Ob er beim Anlegen dabei ist.
  bool an;
}

/// Die Artikel, die eine Vorlage bekommen können — ohne Schritte, keine
/// Muster —, nach Bezeichnung, mit dem Vorschlag aus [vorlagen].
Future<List<ZuordnungsZeile>> zuordnungLaden(
  AppDatabase db,
  List<ProzessVorlage> vorlagen,
) async {
  final mitSchritten = {
    for (final s in await (db.select(db.productSteps)
          ..where((s) => s.deletedAt.isNull()))
        .get())
      s.productId,
  };
  final muster = await NavisionKatalogSpeicher.musterNummern(db);
  final artikel = await (db.select(db.products)
        ..where((p) => p.deletedAt.isNull())
        ..orderBy([(p) => OrderingTerm.asc(p.artikelbezeichnung)]))
      .get();
  final texte = await vorschlagsTexte(db, artikel);
  return [
    for (final a in artikel)
      if (!mitSchritten.contains(a.id) && !muster.contains(a.artikelnummer))
        ZuordnungsZeile(
          artikel: a,
          text: texte[a.id] ?? a.artikelbezeichnung,
          vorschlag: vorlageVorschlagen(vorlagen, texte[a.id] ?? ''),
        ),
  ];
}

/// Welche Artikel die Liste zeigt.
enum _Filter {
  sicher('Eindeutig'),
  unsicher('Mehrere passen'),
  ohne('Ohne Vorschlag'),
  alle('Alle');

  const _Filter(this.label);
  final String label;

  bool zeigt(ZuordnungsZeile z) => switch (this) {
        _Filter.sicher => z.vorschlag.sicher,
        _Filter.unsicher => z.vorschlag.mehrdeutig,
        _Filter.ohne => z.vorschlag.passend.isEmpty,
        _Filter.alle => true,
      };
}

/// Vorlagen für viele Artikel auf einmal: Vorschläge prüfen, ändern,
/// anlegen.
class VorlagenZuordnen extends ConsumerStatefulWidget {
  const VorlagenZuordnen({super.key, required this.vorlagen});

  final List<ProzessVorlage> vorlagen;

  @override
  ConsumerState<VorlagenZuordnen> createState() => _VorlagenZuordnenState();
}

class _VorlagenZuordnenState extends ConsumerState<VorlagenZuordnen> {
  List<ZuordnungsZeile>? _zeilen;
  _Filter _filter = _Filter.sicher;
  String _suche = '';
  bool _arbeitet = false;
  String? _fehler;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    try {
      final zeilen =
          await zuordnungLaden(ref.read(databaseProvider), widget.vorlagen);
      if (mounted) setState(() => _zeilen = zeilen);
    } catch (e) {
      if (mounted) setState(() => _fehler = fehlerText(e));
    }
  }

  List<ZuordnungsZeile> get _sichtbar {
    final q = _suche.trim().toLowerCase();
    return [
      for (final z in _zeilen ?? const <ZuordnungsZeile>[])
        if (_filter.zeigt(z) &&
            (q.isEmpty ||
                z.artikel.artikelbezeichnung.toLowerCase().contains(q) ||
                z.artikel.artikelnummer.contains(q)))
          z,
    ];
  }

  Iterable<ZuordnungsZeile> get _dabei =>
      (_zeilen ?? const []).where((z) => z.an && z.gewaehlt != null);

  Future<void> _anlegen() async {
    final zuordnung = {
      for (final z in _dabei) z.artikel.id: z.gewaehlt!,
    };
    if (zuordnung.isEmpty) return;
    final db = ref.read(databaseProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _arbeitet = true);
    try {
      final neu = await vorlagenZuordnen(db, zuordnung);
      container
          .read(autoBackupTriggerProvider)
          .fireDebounced(reason: 'Prozessvorlagen zugeordnet');
      if (!mounted) return;
      Navigator.of(context).pop();
      geloeschtMelden(
        messenger,
        text: '${zuordnung.length} Artikel haben ihre Prozesskette aus der '
            'Vorlage bekommen.',
        zurueck: () async {
          await vorlagenZuruecknehmen(db, neu);
          container
              .read(autoBackupTriggerProvider)
              .fireDebounced(reason: 'Prozessvorlagen zurückgenommen');
        },
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
    final zeilen = _zeilen;
    final sichtbar = _sichtbar;
    final dabei = _dabei.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vorlagen zuordnen'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              key: const ValueKey('zuordnen-anlegen'),
              onPressed: _arbeitet || dabei == 0 ? null : _anlegen,
              child: Text(
                dabei == 1 ? '1 Artikel anlegen' : '$dabei Artikel anlegen',
              ),
            ),
          ),
        ],
      ),
      body: zeilen == null
          ? Center(
              child: _fehler == null
                  ? const CircularProgressIndicator()
                  : HinweisBox(_fehler!, art: StatusArt.fehler),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    'Artikel ohne Prozessschritte, ohne Muster. Angehakte '
                    'bekommen die gewählte Vorlage — mit leeren Werten. '
                    'Artikel, die schon Schritte haben, bleiben unberührt.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                if (_fehler != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: HinweisBox(_fehler!, art: StatusArt.fehler),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final f in _Filter.values)
                        ChoiceChip(
                          label: Text(
                            '${f.label} (${zeilen.where(f.zeigt).length})',
                          ),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                      SizedBox(
                        width: 260,
                        child: TextField(
                          decoration: const InputDecoration(
                            isDense: true,
                            prefixIcon: Icon(Icons.search, size: 18),
                            hintText: 'Name oder Nummer',
                          ),
                          onChanged: (t) => setState(() => _suche = t),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          for (final z in sichtbar) {
                            z.an = z.gewaehlt != null;
                          }
                        }),
                        child: const Text('Alle angezeigten anhaken'),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          for (final z in sichtbar) {
                            z.an = false;
                          }
                        }),
                        child: const Text('Keine'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: sichtbar.isEmpty
                      ? Center(child: Text('Keine Artikel.', style: grau))
                      : ListView.builder(
                          itemCount: sichtbar.length,
                          itemBuilder: (_, i) {
                            final z = sichtbar[i];
                            return _Zeile(
                              key: ValueKey('zuordnen-${z.artikel.id}'),
                              zeile: z,
                              vorlagen: widget.vorlagen,
                              onGeaendert: () => setState(() {}),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _Zeile extends StatelessWidget {
  const _Zeile({
    super.key,
    required this.zeile,
    required this.vorlagen,
    required this.onGeaendert,
  });

  final ZuordnungsZeile zeile;
  final List<ProzessVorlage> vorlagen;
  final VoidCallback onGeaendert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final passend = zeile.vorschlag.passend;
    // Die passenden oben in der Auswahl.
    final sortiert = [
      ...passend,
      for (final v in vorlagen)
        if (!passend.contains(v)) v,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 16, 2),
      child: Row(
        children: [
          Checkbox(
            value: zeile.an && zeile.gewaehlt != null,
            onChanged: zeile.gewaehlt == null
                ? null
                : (an) {
                    zeile.an = an ?? false;
                    onGeaendert();
                  },
          ),
          SizedBox(
            width: 80,
            child: Text(zeile.artikel.artikelnummer, style: grau),
          ),
          Expanded(
            child: Text(
              zeile.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 300,
            child: DropdownButton<String>(
              value: zeile.gewaehlt?.id ?? '',
              isExpanded: true,
              underline: const SizedBox.shrink(),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('— keine Vorlage —'),
                ),
                for (final v in sortiert)
                  DropdownMenuItem(
                    value: v.id,
                    child: Text(
                      passend.contains(v) ? '${v.name}  ✓' : v.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (id) {
                zeile.gewaehlt = vorlagen.where((v) => v.id == id).firstOrNull;
                zeile.an = zeile.gewaehlt != null;
                onGeaendert();
              },
            ),
          ),
        ],
      ),
    );
  }
}
