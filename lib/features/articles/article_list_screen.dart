import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/constants/product_groups.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';
import '../../core/theme/app_stil.dart';
import '../../core/ui/bausteine.dart';
import '../bedarf/bedarf_screen.dart';
import 'article_info_editor_dialog.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Alle aktiven Produkte mit Schritt-Anzahl.
///
/// Bewusst nur ZWEI Abfragen (Produkte + alle Schritte, im Speicher
/// gruppiert) statt einer Abfrage pro Artikel — bei ~60 Artikeln macht
/// das den Aufbau der Liste spürbar flüssiger.
final articlesProvider = FutureProvider<List<_ArticleInfo>>((ref) async {
  final db = ref.watch(databaseProvider);

  final products = await (db.select(db.products)
        ..where((p) => p.deletedAt.isNull())
        ..orderBy([(p) => OrderingTerm.asc(p.artikelbezeichnung)]))
      .get();

  final steps = await (db.select(db.productSteps)
        ..where((s) => s.deletedAt.isNull())
        ..orderBy([(s) => OrderingTerm.asc(s.reihenfolge)]))
      .get();

  final byProduct = <String, List<ProductStep>>{};
  for (final s in steps) {
    byProduct.putIfAbsent(s.productId, () => []).add(s);
  }

  return [
    for (final p in products)
      _ArticleInfo(product: p, steps: byProduct[p.id] ?? const []),
  ];
});

class _ArticleInfo {
  const _ArticleInfo({required this.product, required this.steps});
  final Product product;
  final List<ProductStep> steps;
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class ArticleListScreen extends ConsumerStatefulWidget {
  const ArticleListScreen({super.key});

  @override
  ConsumerState<ArticleListScreen> createState() => _ArticleListScreenState();
}

class _ArticleListScreenState extends ConsumerState<ArticleListScreen> {
  /// Hält den Text im Suchfeld. Vorher leerte das Kreuz nur den Filter —
  /// im Feld stand der alte Suchbegriff weiter, und die Liste zeigte
  /// trotzdem alles.
  final _suche = TextEditingController();

  String _search = '';
  _SortField _sortField = _SortField.bezeichnung;
  bool _sortAsc = true;
  bool _nurNichtEingepflegt = false;

  @override
  void dispose() {
    _suche.dispose();
    super.dispose();
  }

  List<_ArticleInfo> _filtered(
    List<_ArticleInfo> all,
    Map<String, double> bedarfKg,
  ) {
    var list = all;

    // Suche
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((a) {
        final p = a.product;
        return p.artikelbezeichnung.toLowerCase().contains(q) ||
            p.artikelnummer.toLowerCase().contains(q) ||
            (p.beschreibung?.toLowerCase().contains(q) ?? false) ||
            (p.planungsgruppe?.toLowerCase().contains(q) ?? false);
      }).toList();
    }

    // Pflegestatus-Filter
    if (_nurNichtEingepflegt) {
      list = list.where((a) => !a.product.istEingepflegt).toList();
    }

    // Sortierung
    list.sort((a, b) {
      int cmp;
      switch (_sortField) {
        case _SortField.bezeichnung:
          cmp = a.product.artikelbezeichnung
              .compareTo(b.product.artikelbezeichnung);
        case _SortField.artikelnr:
          cmp = a.product.artikelnummer.compareTo(b.product.artikelnummer);
        case _SortField.schritte:
          cmp = a.steps.length.compareTo(b.steps.length);
        case _SortField.bedarf:
          // Aufsteigend heißt: wenig Bedarf zuerst. Ein Tipp auf dasselbe
          // Feld dreht die Richtung — dann steht der größte Bedarf oben.
          cmp = (bedarfKg[a.product.artikelnummer] ?? 0)
              .compareTo(bedarfKg[b.product.artikelnummer] ?? 0);
        case _SortField.pflegestatus:
          // Offene Stubs zuerst, damit man sie abarbeiten kann.
          cmp = (a.product.istEingepflegt ? 1 : 0)
              .compareTo(b.product.istEingepflegt ? 1 : 0);
        case _SortField.produktgruppe:
          cmp = (a.product.produktgruppe ?? '~')
              .compareTo(b.product.produktgruppe ?? '~');
      }
      // Gleichstand alphabetisch auflösen — sonst springen Zeilen bei
      // jedem Neuaufbau umher.
      if (cmp == 0) {
        cmp = a.product.artikelbezeichnung
            .compareTo(b.product.artikelbezeichnung);
        return cmp;
      }
      return _sortAsc ? cmp : -cmp;
    });

    return list;
  }

  void _toggleSort(_SortField field) {
    setState(() {
      if (_sortField == field) {
        _sortAsc = !_sortAsc;
      } else {
        _sortField = field;
        _sortAsc = true;
      }
    });
  }

  void _sucheLeeren() {
    _suche.clear();
    setState(() => _search = '');
  }

  void _oeffne(BuildContext context, Product p) {
    context.pushNamed(
      'articleDetail',
      pathParameters: {'productId': p.id},
    );
  }

  /// Legt einen neuen Artikel an (Artikelnummer, Bezeichnung, Gruppe)
  /// und öffnet direkt die Detailansicht zum Pflegen der Prozessdaten.
  Future<void> _neuerArtikel(BuildContext context) async {
    final res = await showDialog<({String nummer, String bez, String? gruppe})>(
      context: context,
      builder: (_) => const _NeuerArtikelDialog(),
    );
    if (res == null) return;

    final db = ref.read(databaseProvider);

    // Artikelnummer muss unter den AKTIVEN eindeutig sein — sie ist der
    // Schlüssel zur Excel. Ein früher gelöschter Artikel mit derselben
    // Nummer wird reaktiviert statt doppelt angelegt.
    final gleicheNr = await (db.select(db.products)
          ..where((p) => p.artikelnummer.equals(res.nummer)))
        .get();
    final aktiverKonflikt =
        gleicheNr.where((p) => p.deletedAt == null).toList();
    if (aktiverKonflikt.isNotEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Artikelnummer ${res.nummer} existiert bereits '
            '(${aktiverKonflikt.first.artikelbezeichnung}).',
          ),
        ),
      );
      return;
    }

    // Wurde die Nummer früher gelöscht? Dann reaktivieren (die unique-
    // Bedingung auf artikelnummer verböte sonst einen zweiten Insert).
    final geloescht =
        gleicheNr.where((p) => p.deletedAt != null).toList();
    final String id;
    if (geloescht.isNotEmpty) {
      id = geloescht.first.id;
      await (db.update(db.products)..where((x) => x.id.equals(id))).write(
        ProductsCompanion(
          artikelbezeichnung: Value(res.bez),
          produktgruppe: Value(res.gruppe),
          deletedAt: const Value(null),
          updatedAt: Value(DateTime.now()),
        ),
      );
    } else {
      id = const Uuid().v4();
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: id,
              artikelnummer: res.nummer,
              artikelbezeichnung: res.bez,
              produktgruppe: Value(res.gruppe),
            ),
          );
    }

    ref
        .read(autoBackupTriggerProvider)
        .fireDebounced(reason: 'Artikel angelegt');
    ref.invalidate(articlesProvider);

    if (!context.mounted) return;
    context.pushNamed(
      'articleDetail',
      pathParameters: {'productId': id},
    );
  }

  /// Löscht einen Artikel per Soft-Delete (deletedAt) — samt seiner
  /// Schritte und Parameter. Der Artikel verschwindet aus der App;
  /// in der Excel bleibt das Sheet bestehen (dort ggf. von Hand löschen,
  /// sonst kommt er beim nächsten Import zurück).
  Future<void> _loescheArtikel(BuildContext context, _ArticleInfo info) async {
    final p = info.product;
    final bestaetigt = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final farben = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: const Text('Artikel löschen'),
          content: Text(
            '„${p.artikelbezeichnung}" (Nr. ${p.artikelnummer}) wirklich '
            'löschen? Die Prozessdaten des Artikels werden entfernt.\n\n'
            'Hinweis: In einer bereits exportierten Excel bleibt das '
            'Artikel-Blatt bestehen und muss dort separat gelöscht werden.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: farben.error,
                foregroundColor: farben.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Löschen'),
            ),
          ],
        );
      },
    );
    if (bestaetigt != true) return;

    final db = ref.read(databaseProvider);
    final jetzt = DateTime.now();

    // Schritte des Artikels ermitteln, um deren Parameter mitzulöschen.
    final steps = await (db.select(db.productSteps)
          ..where((s) => s.productId.equals(p.id)))
        .get();
    for (final s in steps) {
      await (db.update(db.productStepParameters)
            ..where((pp) => pp.stepId.equals(s.id)))
          .write(ProductStepParametersCompanion(deletedAt: Value(jetzt)));
    }
    await (db.update(db.productSteps)
          ..where((s) => s.productId.equals(p.id)))
        .write(ProductStepsCompanion(deletedAt: Value(jetzt)));
    await (db.update(db.products)..where((x) => x.id.equals(p.id)))
        .write(ProductsCompanion(deletedAt: Value(jetzt)));

    ref
        .read(autoBackupTriggerProvider)
        .fireDebounced(reason: 'Artikel gelöscht');
    ref.invalidate(articlesProvider);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('„${p.artikelbezeichnung}" gelöscht.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final articlesAsync = ref.watch(articlesProvider);
    // Offene Bedarfsmengen je Artikelnummer — Grundlage der Sortierung
    // „Offener Bedarf". Fehlt der Bedarf, wird mit 0 sortiert.
    final bedarfe = ref.watch(bedarfProvider).valueOrNull;
    final bedarfKg = <String, double>{};
    for (final b in bedarfe ?? const <BedarfInfo>[]) {
      if (b.bedarf.manuellErledigt) continue;
      bedarfKg[b.artikelNummer] =
          (bedarfKg[b.artikelNummer] ?? 0) + b.offenKg;
    }

    // Schmale Fenster: „Neuer Artikel" nur als Symbol, sonst bliebe für
    // den Titel kein Platz.
    final schmal = MediaQuery.sizeOf(context).width < 720;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Artikel-Stammdaten'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(articlesProvider),
            tooltip: 'Aktualisieren',
          ),
          const SizedBox(width: 8),
          // Die Hauptaktion der Seite steht oben rechts in der Kopfleiste —
          // wie „Produkt planen" im Board. Ein schwebender Knopf verdeckte
          // unten rechts die letzte Zeile der Liste.
          if (schmal)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Neuer Artikel',
              onPressed: () => _neuerArtikel(context),
            )
          else
            FilledButton.icon(
              onPressed: () => _neuerArtikel(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Neuer Artikel'),
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: articlesAsync.when(
        data: (articles) => articles.isEmpty
            ? const Center(
                child: LeerHinweis(
                  'Noch keine Artikel vorhanden.\n'
                  'Stammdaten über den Excel-Import einlesen — oder oben '
                  'rechts mit „Neuer Artikel" anlegen.',
                  icon: Icons.inventory_2_outlined,
                ),
              )
            : _buildBody(context, articles, bedarfKg),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<_ArticleInfo> all,
    Map<String, double> bedarfKg,
  ) {
    final theme = Theme.of(context);
    final filtered = _filtered(all, bedarfKg);

    final suchfeld = TextField(
      controller: _suche,
      decoration: InputDecoration(
        hintText: 'Suche nach Name, Artikelnr, Planungsgruppe…',
        prefixIcon: const Icon(Icons.search, size: 18),
        suffixIcon: _search.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 16),
                tooltip: 'Suche leeren',
                onPressed: _sucheLeeren,
              )
            : null,
      ),
      onChanged: (v) => setState(() => _search = v),
    );
    final filter = FilterChip(
      label: const Text('Nicht eingepflegt'),
      selected: _nurNichtEingepflegt,
      visualDensity: VisualDensity.compact,
      onSelected: (v) => setState(() => _nurNichtEingepflegt = v),
    );
    final anzahl = Text(
      '${filtered.length} von ${all.length} Artikel',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.right,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    final sortierung = _SortKnopf(
      feld: _sortField,
      aufsteigend: _sortAsc,
      onWahl: _toggleSort,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // --- Werkzeugleiste: Suche, Filter, Anzahl, Sortierung ---
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Schmal: Suche über die volle Breite, darunter der Rest.
              if (constraints.maxWidth < 720) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    suchfeld,
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        filter,
                        const SizedBox(width: 8),
                        Expanded(child: anzahl),
                        const SizedBox(width: 8),
                        sortierung,
                      ],
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Flexible(
                    flex: 3,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: suchfeld,
                    ),
                  ),
                  const SizedBox(width: 12),
                  filter,
                  const Spacer(),
                  anzahl,
                  const SizedBox(width: 8),
                  sortierung,
                ],
              );
            },
          ),
        ),

        // --- Artikel-Tabelle: weiße Fläche mit dünnem Rand, wie eine
        // Liste in Navision. Spaltenköpfe stehen fest, nur die Zeilen
        // scrollen. ---
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Material(
              color: theme.colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: AppMasse.ecken,
                side: BorderSide(color: theme.colorScheme.outline),
              ),
              clipBehavior: Clip.antiAlias,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Ab dieser Breite eigene Spalten für Gruppe, Prozess,
                  // Schritte und Anlagen — darunter rücken Prozess und
                  // Status unter die Bezeichnung.
                  final breit = constraints.maxWidth >= 860;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TabellenKopf(breit: breit),
                      Expanded(
                        child: filtered.isEmpty
                            ? const Center(
                                child: LeerHinweis(
                                  'Keine Treffer.',
                                  icon: Icons.search_off,
                                ),
                              )
                            : ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (_, i) => _ArtikelZeile(
                                  info: filtered[i],
                                  breit: breit,
                                  onOeffnen: () =>
                                      _oeffne(context, filtered[i].product),
                                  onLoeschen: () =>
                                      _loescheArtikel(context, filtered[i]),
                                ),
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sort-Optionen
// ---------------------------------------------------------------------------

enum _SortField {
  bezeichnung('Bezeichnung'),
  artikelnr('Artikelnr'),
  schritte('Schritte'),
  bedarf('Offener Bedarf'),
  pflegestatus('Pflegestatus'),
  produktgruppe('Produktgruppe');

  const _SortField(this.label);
  final String label;
}

/// Sortier-Menü. Zeigt die aktuelle Sortierung als Beschriftung — vorher
/// stand dort nur ein Symbol, und man sah nicht, wonach die Liste gerade
/// sortiert ist.
class _SortKnopf extends StatelessWidget {
  const _SortKnopf({
    required this.feld,
    required this.aufsteigend,
    required this.onWahl,
  });

  final _SortField feld;
  final bool aufsteigend;
  final void Function(_SortField) onWahl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    return PopupMenuButton<_SortField>(
      tooltip: 'Sortierung',
      position: PopupMenuPosition.under,
      onSelected: onWahl,
      itemBuilder: (_) => [
        for (final f in _SortField.values)
          PopupMenuItem<_SortField>(
            value: f,
            child: Row(
              children: [
                if (feld == f)
                  Icon(
                    aufsteigend ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 16,
                  )
                else
                  const SizedBox(width: 16),
                const SizedBox(width: 8),
                Text(f.label),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sort, size: 18, color: grau),
            const SizedBox(width: 6),
            Text(
              feld.label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              aufsteigend ? Icons.arrow_upward : Icons.arrow_downward,
              size: 14,
              color: grau,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tabelle
// ---------------------------------------------------------------------------

/// Spaltenbreiten der Artikelliste — für Kopf und Zeilen dieselben.
abstract final class _Spalten {
  static const double nummer = 78;
  static const double gruppe = 150;
  static const double prozess = 160;
  static const double zahl = 64;
  static const double status = 132;
  static const double menue = 40;

  /// Abstand zwischen zwei Spalten.
  static const double luecke = 12;
}

/// Ziffern gleich breit, damit Nummern und Anzahlen untereinander stehen.
const List<FontFeature> _ziffern = [FontFeature.tabularFigures()];

/// Abteilung aus dem dbValue — null bei unbekanntem Wert. Eine kaputte
/// Zeile in der Datenbank soll die Liste nicht abstürzen lassen.
Abteilung? _abteilungAus(String dbValue) {
  for (final a in Abteilung.values) {
    if (a.dbValue == dbValue) return a;
  }
  return null;
}

/// Spaltenköpfe der Tabelle — dieselben Breiten wie [_ArtikelZeile].
class _TabellenKopf extends StatelessWidget {
  const _TabellenKopf({required this.breit});

  final bool breit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stil = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurfaceVariant,
    );
    Widget spalte(String text, double breite, {bool rechts = false}) =>
        SizedBox(
          width: breite,
          child: Text(
            text,
            maxLines: 1,
            textAlign: rechts ? TextAlign.right : TextAlign.left,
            style: stil,
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppFarben.von(context).leiste,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outline),
        ),
      ),
      child: Row(
        children: [
          spalte('Nr.', _Spalten.nummer),
          Expanded(child: Text('Bezeichnung', style: stil)),
          if (breit) ...[
            const SizedBox(width: _Spalten.luecke),
            spalte('Gruppe', _Spalten.gruppe),
            const SizedBox(width: _Spalten.luecke),
            spalte('Prozess', _Spalten.prozess),
            spalte('Schritte', _Spalten.zahl, rechts: true),
            spalte('Anlagen', _Spalten.zahl, rechts: true),
            const SizedBox(width: _Spalten.luecke + 4),
            spalte('Status', _Spalten.status),
          ],
          const SizedBox(width: _Spalten.menue),
        ],
      ),
    );
  }
}

/// Eine Zeile der Artikelliste. Antippen öffnet den Artikel.
class _ArtikelZeile extends StatelessWidget {
  const _ArtikelZeile({
    required this.info,
    required this.breit,
    required this.onOeffnen,
    required this.onLoeschen,
  });

  final _ArticleInfo info;

  /// Breite Tabelle mit allen Spalten — sonst zweizeilig.
  final bool breit;
  final VoidCallback onOeffnen;
  final VoidCallback onLoeschen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final p = info.product;
    final steps = info.steps;

    // Abteilungen als farbige Kürzel — jede Abteilung nur einmal,
    // in Reihenfolge ihres ersten Auftretens im Prozess.
    final abteilungen = <Abteilung>[];
    for (final s in steps) {
      final a = _abteilungAus(s.abteilung);
      if (a != null && !abteilungen.contains(a)) abteilungen.add(a);
    }

    // Anlagen-Zähler: wie viele verschiedene Anlagen im Prozess stecken.
    //
    // Gezählt wird, was an den Schritten hängt. Vorher stand hier ein
    // Zähler über `maschinenEinstellungenJson` — eine Spalte aus der Zeit
    // vor dem Maschinen-Katalog, in die seit dessen Einführung niemand
    // mehr schreibt. Der Zähler stand deshalb bei jedem Artikel auf 0.
    //
    // Maßgeblich ist die Maschinen-ID; nur wenn ein Schritt noch keine
    // hat (alte Importe führten die Anlage als Freitext), zählt der Name.
    final anlagen = <String>{};
    for (final s in steps) {
      final id = s.maschineId;
      if (id != null && id.isNotEmpty) {
        anlagen.add(id);
        continue;
      }
      final name = s.maschine?.trim();
      if (name != null && name.isNotEmpty) anlagen.add(name);
    }

    // Gruppe: die Produktgruppe. Ältere Artikel haben oft nur die frühere
    // Freitext-Planungsgruppe — dann steht die da, grau.
    final produktgruppe = produktgruppeLabel(p.produktgruppe);
    final planungsgruppe = p.planungsgruppe?.trim() ?? '';
    final gruppe = produktgruppe.isNotEmpty
        ? produktgruppe
        : (planungsgruppe.isNotEmpty ? planungsgruppe : '—');

    final stil = theme.textTheme.bodyMedium;
    final zahlen = stil?.copyWith(fontFeatures: _ziffern);
    const status = StatusMarke('nicht eingepflegt', art: StatusArt.warnung);

    final nummer = SizedBox(
      width: _Spalten.nummer,
      child: Text(
        p.artikelnummer,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: zahlen?.copyWith(
          // Blau wie ein Link: Antippen öffnet den Artikel.
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    final bezeichnung = Text(
      p.artikelbezeichnung,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: stil?.copyWith(fontWeight: FontWeight.w600),
    );
    final menue = _ZeilenMenue(onOeffnen: onOeffnen, onLoeschen: onLoeschen);

    final Widget inhalt;
    if (breit) {
      inhalt = Row(
        children: [
          nummer,
          Expanded(child: bezeichnung),
          const SizedBox(width: _Spalten.luecke),
          SizedBox(
            width: _Spalten.gruppe,
            child: Text(
              gruppe,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: stil?.copyWith(color: grau),
            ),
          ),
          const SizedBox(width: _Spalten.luecke),
          SizedBox(
            width: _Spalten.prozess,
            child: _ProzessMarken(abteilungen: abteilungen),
          ),
          SizedBox(
            width: _Spalten.zahl,
            child: Text(
              steps.isEmpty ? '—' : '${steps.length}',
              textAlign: TextAlign.right,
              style: zahlen?.copyWith(color: steps.isEmpty ? grau : null),
            ),
          ),
          SizedBox(
            width: _Spalten.zahl,
            child: Text(
              anlagen.isEmpty ? '—' : '${anlagen.length}',
              textAlign: TextAlign.right,
              style: zahlen?.copyWith(color: grau),
            ),
          ),
          const SizedBox(width: _Spalten.luecke + 4),
          SizedBox(
            width: _Spalten.status,
            child: p.istEingepflegt
                ? null
                : const Align(
                    alignment: Alignment.centerLeft,
                    heightFactor: 1,
                    child: status,
                  ),
          ),
          menue,
        ],
      );
    } else {
      inhalt = Row(
        children: [
          nummer,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                bezeichnung,
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (abteilungen.isNotEmpty)
                      _ProzessMarken(abteilungen: abteilungen),
                    Text(
                      steps.length == 1 ? '1 Schritt' : '${steps.length} Schritte',
                      style: theme.textTheme.bodySmall?.copyWith(color: grau),
                    ),
                    if (!p.istEingepflegt) status,
                  ],
                ),
              ],
            ),
          ),
          menue,
        ],
      );
    }

    // Material statt Farbe am Container: Die Hover- und Tipp-Welle des
    // InkWell malt auf das nächste Material — so bleibt sie in der
    // scrollenden Liste an ihrer Zeile.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOeffnen,
        child: Container(
          constraints: const BoxConstraints(minHeight: 38),
          padding: EdgeInsets.fromLTRB(12, breit ? 3 : 6, 4, breit ? 3 : 6),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: inhalt,
        ),
      ),
    );
  }
}

/// Die Abteilungen des Prozesses als Kürzel in Prozessreihenfolge. Passen
/// nicht alle in die Spalte, steht der Rest als „+2" dahinter.
class _ProzessMarken extends StatelessWidget {
  const _ProzessMarken({required this.abteilungen});

  final List<Abteilung> abteilungen;

  static const int _maxSichtbar = 5;

  @override
  Widget build(BuildContext context) {
    if (abteilungen.isEmpty) {
      return Text(
        '—',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }
    final zuViele = abteilungen.length > _maxSichtbar;
    final sichtbar =
        zuViele ? abteilungen.take(_maxSichtbar - 1) : abteilungen;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final a in sichtbar)
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Tooltip(
              message: a.anzeigeName,
              child: AbteilungsMarke(abteilung: a, skala: 0.85),
            ),
          ),
        if (zuViele)
          Text(
            '+${abteilungen.length - (_maxSichtbar - 1)}',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// Drei-Punkte-Menü am Zeilenende: Öffnen oder Löschen.
class _ZeilenMenue extends StatelessWidget {
  const _ZeilenMenue({required this.onOeffnen, required this.onLoeschen});

  final VoidCallback onOeffnen;
  final VoidCallback onLoeschen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rot = theme.colorScheme.error;
    // Feste Größe, damit der Knopf die Zeile nicht auf 48 px aufbläst.
    return SizedBox(
      width: _Spalten.menue,
      height: 32,
      child: PopupMenuButton<String>(
        tooltip: 'Aktionen',
        padding: EdgeInsets.zero,
        icon: Icon(
          Icons.more_vert,
          size: 18,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        onSelected: (v) {
          switch (v) {
            case 'oeffnen':
              onOeffnen();
            case 'loeschen':
              onLoeschen();
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem<String>(
            value: 'oeffnen',
            child: Row(
              children: [
                Icon(Icons.edit_outlined, size: 18),
                SizedBox(width: 10),
                Text('Öffnen / Bearbeiten'),
              ],
            ),
          ),
          PopupMenuItem<String>(
            value: 'loeschen',
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 18, color: rot),
                const SizedBox(width: 10),
                Text('Löschen', style: TextStyle(color: rot)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialog: neuen Artikel anlegen
// ---------------------------------------------------------------------------

class _NeuerArtikelDialog extends StatefulWidget {
  const _NeuerArtikelDialog();

  @override
  State<_NeuerArtikelDialog> createState() => _NeuerArtikelDialogState();
}

class _NeuerArtikelDialogState extends State<_NeuerArtikelDialog> {
  final _nummer = TextEditingController();
  final _bez = TextEditingController();
  String? _gruppe;

  @override
  void dispose() {
    _nummer.dispose();
    _bez.dispose();
    super.dispose();
  }

  void _ok() {
    final nummer = _nummer.text.trim();
    final bez = _bez.text.trim();
    if (nummer.isEmpty || bez.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte Artikelnummer und Bezeichnung angeben.'),
        ),
      );
      return;
    }
    Navigator.of(context).pop((nummer: nummer, bez: bez, gruppe: _gruppe));
  }

  @override
  Widget build(BuildContext context) {
    // Rahmen, Ecken und Dichte der Felder kommen aus dem Theme.
    return AlertDialog(
      title: const Text('Neuen Artikel anlegen'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nummer,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Artikelnummer',
                hintText: 'z.B. 12345',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bez,
              decoration: const InputDecoration(
                labelText: 'Bezeichnung',
                hintText: 'z.B. Schweinefrikadelle 60g, gebraten',
              ),
              onSubmitted: (_) => _ok(),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _gruppe,
              decoration: const InputDecoration(
                labelText: 'Produktgruppe (optional)',
              ),
              items: [
                for (final g in kProduktgruppen)
                  DropdownMenuItem(value: g.dbValue, child: Text(g.label)),
              ],
              onChanged: (v) => setState(() => _gruppe = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(onPressed: _ok, child: const Text('Anlegen')),
      ],
    );
  }
}
