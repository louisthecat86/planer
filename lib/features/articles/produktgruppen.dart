import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/product_groups.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../entwicklung/projekte/fliessdiagramm_liste.dart' show fdText;

// Die Produktgruppen eines Artikels.
//
// Als Produktgruppe wählt man das Fließdiagramm — dieselbe Liste wie in
// der Produktentwicklung („FD_101 · Testware paniert"). Gespeichert wird
// die Kennung des Fließdiagramms in `products.produktgruppe`.
//
// Die früheren zwölf festen Gruppen (Brühwurst, Rohwurst …) gibt es nur
// noch für das, was schon da ist: Ein Artikel, der eine davon trägt,
// zeigt sie weiter, bis er ein Fließdiagramm bekommt. Und solange noch
// gar keine Fließdiagramme hinterlegt sind, stehen sie weiter zur Wahl —
// sonst gäbe es auf einem frischen Rechner nichts zu wählen.

/// Eine wählbare Produktgruppe: [wert] steht in der Datenbank, [label]
/// auf dem Schirm.
typedef Produktgruppe = ({String wert, String label});

/// Die wählbaren Produktgruppen aus den [fliessdiagramme]n — ohne
/// Fließdiagramme die früheren festen Gruppen.
List<Produktgruppe> produktgruppenAus(List<Fliessdiagramm> fliessdiagramme) {
  if (fliessdiagramme.isEmpty) {
    return [
      for (final g in ProductGroup.values) (wert: g.dbValue, label: g.label),
    ];
  }
  return [
    for (final f in fliessdiagramme)
      (wert: f.id, label: fdText(f.id, bezeichnung: f.bezeichnung)),
  ];
}

/// Liest die Fließdiagramme in ihrer Reihenfolge.
Future<List<Fliessdiagramm>> _fliessdiagramme(AppDatabase db) =>
    (db.select(db.entwicklungFliessdiagramme)
          ..orderBy([
            (f) => OrderingTerm.asc(f.sortierung),
            (f) => OrderingTerm.asc(f.id),
          ]))
        .get();

void _namenSetzen(List<Fliessdiagramm> liste) => eigeneProduktgruppenSetzen({
      for (final f in liste) f.id: fdText(f.id, bezeichnung: f.bezeichnung),
    });

/// Lädt die Namen der eigenen Produktgruppen, damit [produktgruppeLabel]
/// sie kennt — für Stellen ohne Oberfläche (Statistik, Druck), die nicht
/// darauf warten können, dass der Schirm sie schon geladen hat.
Future<void> produktgruppenNamenLaden(AppDatabase db) async =>
    _namenSetzen(await _fliessdiagramme(db));

/// Die wählbaren Produktgruppen — folgt der Liste der Fließdiagramme und
/// hält dabei die Namen für [produktgruppeLabel] aktuell.
final produktgruppenProvider = StreamProvider<List<Produktgruppe>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.entwicklungFliessdiagramme)
        ..orderBy([
          (f) => OrderingTerm.asc(f.sortierung),
          (f) => OrderingTerm.asc(f.id),
        ]))
      .watch()
      .map((liste) {
    _namenSetzen(liste);
    return produktgruppenAus(liste);
  });
});

/// Die Einträge für die Auswahl: „keine" (mit [mitKeine]), die
/// [gruppen] und — falls der Artikel noch eine Gruppe trägt, die nicht
/// zur Wahl steht — diese eine dazu, damit sie beim Speichern nicht
/// verloren geht.
List<Produktgruppe> produktgruppenWahl(
  List<Produktgruppe> gruppen, {
  String? aktuell,
  bool mitKeine = true,
}) {
  final wert = aktuell?.trim() ?? '';
  return [
    if (mitKeine) (wert: '', label: '— keine —'),
    ...gruppen,
    if (wert.isNotEmpty && !gruppen.any((g) => g.wert == wert))
      (wert: wert, label: '${produktgruppeLabel(wert)} (bisherige Gruppe)'),
  ];
}

/// Auswahl der Produktgruppe — wie die des Fließdiagramms in der
/// Produktentwicklung: Tippen sucht in Kennung und Bezeichnung.
class ProduktgruppeWahl extends ConsumerWidget {
  const ProduktgruppeWahl({
    super.key,
    required this.wert,
    required this.onWahl,
    this.label = 'Produktgruppe',
    this.mitKeine = true,
  });

  /// Der gespeicherte Wert — null: keine.
  final String? wert;

  /// Die neue Wahl — null: keine.
  final ValueChanged<String?> onWahl;
  final String label;

  /// Ob „keine" zur Wahl steht.
  final bool mitKeine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gruppen = ref.watch(produktgruppenProvider).valueOrNull ??
        const <Produktgruppe>[];
    final aktuell = wert?.trim() ?? '';
    final wahl = produktgruppenWahl(
      gruppen,
      aktuell: aktuell,
      mitKeine: mitKeine,
    );
    return DropdownMenu<String>(
      // Neu aufbauen, wenn sich Wert oder Liste ändern — das Feld hält
      // seinen Text sonst fest.
      key: ValueKey('produktgruppe-$aktuell-${wahl.length}'),
      initialSelection: wahl.any((g) => g.wert == aktuell) ? aktuell : null,
      expandedInsets: EdgeInsets.zero,
      enableFilter: true,
      requestFocusOnTap: true,
      menuHeight: 360,
      label: Text(label),
      dropdownMenuEntries: [
        for (final g in wahl) DropdownMenuEntry(value: g.wert, label: g.label),
      ],
      onSelected: (neu) {
        if (neu == null) return;
        onWahl(neu.isEmpty ? null : neu);
      },
    );
  }
}
