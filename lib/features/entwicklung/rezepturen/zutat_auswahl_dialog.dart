import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/utils/sheet_utils.dart';
import '../daten/entwicklung_repository.dart';
import '../rechenkern/rechen_modell.dart';
import '../zutaten/zutat_dialog.dart';

/// Was im Auswahlfenster gewählt wurde: eine Zutat oder eine Rezeptur.
class ZutatAuswahl {
  const ZutatAuswahl.zutat(this.id) : istRezeptur = false;
  const ZutatAuswahl.rezeptur(this.id) : istRezeptur = true;

  final String id;
  final bool istRezeptur;
}

/// Wählt eine Zutat aus dem Katalog oder eine Rezeptur als Unterrezeptur.
class ZutatAuswahlDialog extends ConsumerStatefulWidget {
  const ZutatAuswahlDialog({
    super.key,
    required this.ohneRezepturId,
    this.nurZutaten = false,
  });

  /// Die Rezeptur, in die eingefügt wird — sie selbst steht nicht zur
  /// Wahl.
  final String ohneRezepturId;

  /// Nur Zutaten aus dem Katalog, keine Rezepturen.
  final bool nurZutaten;

  @override
  ConsumerState<ZutatAuswahlDialog> createState() =>
      _ZutatAuswahlDialogState();
}

class _ZutatAuswahlDialogState extends ConsumerState<ZutatAuswahlDialog> {
  final _suche = TextEditingController();
  String _text = '';

  @override
  void dispose() {
    _suche.dispose();
    super.dispose();
  }

  bool _passt(String name, String? nummer) {
    final t = _text.trim().toLowerCase();
    if (t.isEmpty) return true;
    return name.toLowerCase().contains(t) ||
        (nummer ?? '').toLowerCase().contains(t);
  }

  Future<void> _neueZutat() async {
    await showSheetOhneAnimation<void>(
      context: context,
      constraints: const BoxConstraints(maxWidth: 760),
      builder: (_) => const ZutatDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final zutaten = (ref.watch(zutatenProvider).valueOrNull ?? const [])
        .where((z) => _passt(z.name, z.artikelnummer))
        .toList();
    final rezepturen = (widget.nurZutaten
            ? const <Rezeptur>[]
            : ref.watch(rezepturenProvider).valueOrNull ?? const <Rezeptur>[])
        .where((r) => r.id != widget.ohneRezepturId)
        .where((r) => _passt(r.name, r.artikelnummer))
        .toList();
    final hoehe =
        math.max(200.0, math.min(460.0, MediaQuery.of(context).size.height - 260));

    Widget ueberschrift(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
          child: Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: grau,
            ),
          ),
        );

    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(
              widget.nurZutaten
                  ? 'Zutat wählen'
                  : 'Zutat oder Rezeptur einfügen',
            ),
          ),
          TextButton.icon(
            onPressed: _neueZutat,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Neue Zutat'),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        height: hoehe,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _suche,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Suche …',
                prefixIcon: Icon(Icons.search, size: 18),
              ),
              onChanged: (v) => setState(() => _text = v),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: ListView(
                children: [
                  ueberschrift('ZUTATEN'),
                  if (zutaten.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        'Keine passende Zutat.',
                        style: TextStyle(color: grau),
                      ),
                    ),
                  for (final z in zutaten)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        z.istFleisch
                            ? Icons.set_meal_outlined
                            : z.istWasser
                                ? Icons.water_drop_outlined
                                : Icons.egg_outlined,
                        size: 18,
                      ),
                      title: Text(z.name),
                      subtitle: Text(
                        [
                          if (z.artikelnummer != null) z.artikelnummer!,
                          if (z.istFleisch)
                            Tierart.aus(z.tierart)?.label ?? 'Fleisch',
                        ].join(' · '),
                      ),
                      onTap: () =>
                          Navigator.of(context).pop(ZutatAuswahl.zutat(z.id)),
                    ),
                  if (!widget.nurZutaten)
                    ueberschrift('REZEPTUREN — als Unterrezeptur'),
                  if (rezepturen.isEmpty && !widget.nurZutaten)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        'Keine passende Rezeptur.',
                        style: TextStyle(color: grau),
                      ),
                    ),
                  for (final r in rezepturen)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.menu_book_outlined, size: 18),
                      title: Text(r.name),
                      subtitle: r.artikelnummer == null
                          ? null
                          : Text(r.artikelnummer!),
                      onTap: () => Navigator.of(context)
                          .pop(ZutatAuswahl.rezeptur(r.id)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
      ],
    );
  }
}
