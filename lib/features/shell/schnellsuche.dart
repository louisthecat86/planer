import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/database_provider.dart';
import '../../core/theme/app_stil.dart';

// Die Schnellsuche (Strg+K): ein Feld, das zu jedem Bereich und zu jedem
// Artikel führt — ohne Maus. Tippen, mit den Pfeiltasten wählen, Enter.

/// Ein Ziel der Schnellsuche.
class SchnellZiel {
  const SchnellZiel({
    required this.titel,
    required this.icon,
    this.unter,
    this.kuerzel,
    this.route,
    this.artikelId,
  });

  final String titel;

  /// Zweite Zeile — beim Artikel die Nummer.
  final String? unter;
  final IconData icon;

  /// Das Tastenkürzel des Bereichs, etwa „Strg+2".
  final String? kuerzel;

  /// Name der Route eines Bereichs.
  final String? route;

  /// ID eines Artikels — öffnet seine Seite.
  final String? artikelId;
}

/// So viele Artikel zeigt die Suche höchstens — mehr passt nicht auf einen
/// Blick; wer mehr braucht, tippt genauer.
const int kSchnellsucheArtikelMax = 12;

/// Die Treffer für [eingabe]: erst die [bereiche], dann die [artikel].
///
/// Ohne Eingabe alle Bereiche und kein Artikel. Sonst muss jedes Wort der
/// Eingabe im Titel oder in der zweiten Zeile vorkommen; was mit der
/// Eingabe beginnt, steht vorn — bei Artikeln zählt dafür auch die Nummer.
List<SchnellZiel> schnellTreffer(
  String eingabe,
  List<SchnellZiel> bereiche,
  List<SchnellZiel> artikel,
) {
  final q = eingabe.trim().toLowerCase();
  if (q.isEmpty) return bereiche;
  final worte = q.split(RegExp(r'\s+'));

  bool passt(SchnellZiel z) {
    final text = '${z.titel} ${z.unter ?? ''}'.toLowerCase();
    return worte.every(text.contains);
  }

  // 0: beginnt mit der Eingabe, 1: ein Wort beginnt damit, 2: enthält sie.
  int rang(SchnellZiel z) {
    final titel = z.titel.toLowerCase();
    final unter = (z.unter ?? '').toLowerCase();
    if (titel.startsWith(q) || unter.startsWith(q)) return 0;
    if (titel.split(RegExp(r'[\s\-/]+')).any((w) => w.startsWith(q))) return 1;
    return 2;
  }

  List<SchnellZiel> sortiert(Iterable<SchnellZiel> ziele) {
    final liste = [
      for (final (i, z) in ziele.indexed)
        if (passt(z)) (rang(z), i, z),
    ]..sort((a, b) {
        final r = a.$1.compareTo(b.$1);
        // Bei gleichem Rang die gegebene Reihenfolge.
        return r != 0 ? r : a.$2.compareTo(b.$2);
      });
    return [for (final e in liste) e.$3];
  }

  return [
    ...sortiert(bereiche),
    ...sortiert(artikel).take(kSchnellsucheArtikelMax),
  ];
}

/// Öffnet die Schnellsuche über [bereiche] und allen Artikeln.
Future<void> schnellsucheOeffnen(
  BuildContext context,
  List<SchnellZiel> bereiche,
) async {
  final router = GoRouter.maybeOf(context);
  final ziel = await showDialog<SchnellZiel>(
    context: context,
    builder: (_) => SchnellsucheDialog(bereiche: bereiche),
  );
  if (ziel == null || router == null) return;
  final route = ziel.route;
  final artikelId = ziel.artikelId;
  if (route != null) {
    router.goNamed(route);
  } else if (artikelId != null) {
    router.pushNamed('articleDetail', pathParameters: {'productId': artikelId});
  }
}

/// Das Fenster der Schnellsuche. Gibt das gewählte Ziel zurück.
class SchnellsucheDialog extends ConsumerStatefulWidget {
  const SchnellsucheDialog({super.key, required this.bereiche, this.artikel});

  final List<SchnellZiel> bereiche;

  /// Die Artikel — sonst lädt das Fenster sie aus der Datenbank.
  final List<SchnellZiel>? artikel;

  @override
  ConsumerState<SchnellsucheDialog> createState() => _SchnellsucheDialogState();
}

class _SchnellsucheDialogState extends ConsumerState<SchnellsucheDialog> {
  final _eingabe = TextEditingController();
  final _rollen = ScrollController();
  late List<SchnellZiel> _artikel = widget.artikel ?? const [];
  int _gewaehlt = 0;

  static const double _zeilenHoehe = 44;

  @override
  void initState() {
    super.initState();
    if (widget.artikel == null) _artikelLaden();
  }

  Future<void> _artikelLaden() async {
    try {
      final db = ref.read(databaseProvider);
      final produkte = await (db.select(db.products)
            ..where((p) => p.deletedAt.isNull())
            ..orderBy([(p) => OrderingTerm.asc(p.artikelbezeichnung)]))
          .get();
      if (!mounted) return;
      setState(() {
        _artikel = [
          for (final p in produkte)
            SchnellZiel(
              titel: p.artikelbezeichnung,
              unter: p.artikelnummer,
              icon: Icons.inventory_2_outlined,
              artikelId: p.id,
            ),
        ];
      });
    } catch (_) {
      // Dann eben nur die Bereiche.
    }
  }

  @override
  void dispose() {
    _eingabe.dispose();
    _rollen.dispose();
    super.dispose();
  }

  List<SchnellZiel> get _treffer =>
      schnellTreffer(_eingabe.text, widget.bereiche, _artikel);

  void _bewege(int schritt) {
    final n = _treffer.length;
    if (n == 0) return;
    setState(() => _gewaehlt = (_gewaehlt + schritt).clamp(0, n - 1));
    // Die gewählte Zeile im Blick halten.
    if (!_rollen.hasClients) return;
    final oben = _gewaehlt * _zeilenHoehe;
    final unten = oben + _zeilenHoehe;
    final pos = _rollen.position;
    if (oben < pos.pixels) {
      _rollen.jumpTo(oben);
    } else if (unten > pos.pixels + pos.viewportDimension) {
      _rollen.jumpTo(unten - pos.viewportDimension);
    }
  }

  void _waehle([int? index]) {
    final treffer = _treffer;
    final i = index ?? _gewaehlt;
    if (i < 0 || i >= treffer.length) return;
    Navigator.of(context).pop(treffer[i]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = theme.colorScheme;
    final treffer = _treffer;
    final gewaehlt =
        treffer.isEmpty ? -1 : _gewaehlt.clamp(0, treffer.length - 1);

    return Dialog(
      alignment: const Alignment(0, -0.5),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              // Pfeiltasten und Enter gehören der Liste, alles andere dem
              // Feld.
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                      _bewege(1),
                  const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                      _bewege(-1),
                },
                child: TextField(
                  key: const ValueKey('schnellsuche-feld'),
                  controller: _eingabe,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Bereich oder Artikel — Name oder Nummer …',
                    prefixIcon: Icon(Icons.search, size: 20),
                  ),
                  onChanged: (_) => setState(() => _gewaehlt = 0),
                  onSubmitted: (_) => _waehle(),
                ),
              ),
            ),
            Flexible(
              child: treffer.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Nichts gefunden.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: f.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _rollen,
                      shrinkWrap: true,
                      itemExtent: _zeilenHoehe,
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: treffer.length,
                      itemBuilder: (_, i) => _Zeile(
                        ziel: treffer[i],
                        gewaehlt: i == gewaehlt,
                        onTap: () => _waehle(i),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(
                '↑ ↓ wählen · Enter öffnen · Esc schließen',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: f.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Zeile extends StatelessWidget {
  const _Zeile({
    required this.ziel,
    required this.gewaehlt,
    required this.onTap,
  });

  final SchnellZiel ziel;
  final bool gewaehlt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = theme.colorScheme;
    final grau = theme.textTheme.bodySmall?.copyWith(
      color: f.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: gewaehlt ? f.primaryContainer : Colors.transparent,
        borderRadius: AppMasse.ecken,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppMasse.ecken,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Icon(ziel.icon, size: 18, color: f.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    ziel.titel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: gewaehlt ? FontWeight.w600 : null,
                    ),
                  ),
                ),
                if (ziel.unter case final unter?) ...[
                  const SizedBox(width: 12),
                  Text(unter, style: grau),
                ],
                if (ziel.kuerzel case final kuerzel?) ...[
                  const SizedBox(width: 12),
                  Text(kuerzel, style: grau),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
