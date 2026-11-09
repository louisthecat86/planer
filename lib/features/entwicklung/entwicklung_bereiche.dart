import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// Die Bereiche der Produktentwicklung. In der Produktentwicklung zeigt die
// Leiste links sie statt der Bereiche des Planers (AppRahmen); jeder hat
// eine eigene Seite. Unterseiten — ein Projekt, eine Rezeptur — heben den
// Bereich hervor, zu dem sie gehören.

/// Ein Bereich der Produktentwicklung.
enum EntwicklungsBereich {
  uebersicht(
    'Übersicht',
    Icons.space_dashboard_outlined,
    'entwicklung',
    '/entwicklung',
  ),
  projekte(
    'Projekte',
    Icons.folder_open_outlined,
    'entwicklungProjekte',
    '/entwicklung/projekte',
    ['/entwicklung/projekt', '/entwicklung/gesamtprojekt'],
  ),
  kunden(
    'Kunden',
    Icons.folder_shared_outlined,
    'entwicklungKunden',
    '/entwicklung/kunden',
  ),
  rezepturen(
    'Rezepturen',
    Icons.menu_book_outlined,
    'entwicklungRezepturen',
    '/entwicklung/rezepturen',
    ['/entwicklung/rezeptur'],
  ),
  zutaten(
    'Zutaten',
    Icons.egg_outlined,
    'entwicklungZutaten',
    '/entwicklung/zutaten',
  ),
  werkzeuge(
    'Werkzeuge',
    Icons.calculate_outlined,
    'entwicklungWerkzeuge',
    '/entwicklung/werkzeuge',
    ['/entwicklung/rueckrechnung'],
  ),
  statistik(
    'Statistik',
    Icons.query_stats,
    'entwicklungStatistik',
    '/entwicklung/statistik',
  );

  const EntwicklungsBereich(
    this.label,
    this.icon,
    this.route,
    this.pfad, [
    this.unterseiten = const <String>[],
  ]);

  final String label;
  final IconData icon;

  /// Name der Route (go_router).
  final String route;

  /// Pfad der Seite.
  final String pfad;

  /// Pfadanfänge der Unterseiten, die zu diesem Bereich gehören.
  final List<String> unterseiten;

  /// Ob [ort] zu diesem Bereich gehört — zur Übersicht nur sie selbst.
  bool passt(String ort) {
    if (ort == pfad) return true;
    if (this != uebersicht && ort.startsWith('$pfad/')) return true;
    return unterseiten.any((p) => ort == p || ort.startsWith('$p/'));
  }
}

/// Ob [ort] in der Produktentwicklung liegt.
bool istEntwicklungsOrt(String ort) =>
    ort == EntwicklungsBereich.uebersicht.pfad ||
    ort.startsWith('${EntwicklungsBereich.uebersicht.pfad}/');

/// Wechselt in den Bereich [b].
void bereichOeffnen(BuildContext context, EntwicklungsBereich b) =>
    context.goNamed(b.route);
