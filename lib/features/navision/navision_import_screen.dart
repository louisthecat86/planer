import 'dart:io';

import 'package:drift/drift.dart' hide Column;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';
import '../../core/services/navision_import_service.dart';
import '../bedarf/bedarf_screen.dart';

/// Der eingelesene Navision-Katalog.
final navisionKatalogProvider =
    FutureProvider<List<NavisionArtikel>>((ref) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.navisionArtikelKatalog)
        ..orderBy([(t) => OrderingTerm.asc(t.nummer)]))
      .get();
});

/// Artikelnummern, die es in der App bereits als Prozessartikel gibt —
/// nur für die brauchen wir keine Neuanlage.
final appArtikelnummernProvider = FutureProvider<Set<String>>((ref) async {
  final db = ref.watch(databaseProvider);
  final liste = await (db.select(db.products)
        ..where((p) => p.deletedAt.isNull()))
      .get();
  return liste.map((p) => p.artikelnummer).toSet();
});

/// Bereits im Bedarf liegende Fertigmenge je Artikelnummer, in kg — abgeleitet
/// aus dem [bedarfProvider], damit sich die Netto-Rechnung automatisch
/// aktualisiert, sobald im Bedarf-Screen etwas gelöscht, ergänzt oder abgehakt
/// wird. Manuell erledigte Positionen zählen nicht mehr als deckend; gelöschte
/// tauchen gar nicht erst auf und geben den Navision-Bedarf wieder frei.
final imBedarfKgProvider = FutureProvider<Map<String, double>>((ref) async {
  final bedarfe = await ref.watch(bedarfProvider.future);
  final map = <String, double>{};
  for (final b in bedarfe) {
    if (b.bedarf.manuellErledigt) continue;
    if (b.artikelNummer.isEmpty || b.artikelNummer == '—') continue;
    map[b.artikelNummer] =
        (map[b.artikelNummer] ?? 0) + b.bedarf.mengeKgFertig;
  }
  return map;
});

/// Gespeicherte Umrechnungsfaktoren (Artikelnummer → kg je Basiseinheit).
/// Nur ein Anzeige-Hinweis für die Netto-Rechnung bei nicht-kg-Artikeln;
/// die verbindliche Umrechnung passiert beim Übernehmen mit Einheitenprüfung.
final umrechnungsFaktorenProvider =
    FutureProvider<Map<String, double>>((ref) async {
  final db = ref.watch(databaseProvider);
  final rows = await db.select(db.navisionUmrechnungen).get();
  return {for (final u in rows) u.nummer: u.kgJeEinheit};
});

/// Navision-Import: Artikelkatalog ansehen, filtern und Bedarf übernehmen.
///
/// Bewusst als eigener Bereich neben den App-Artikeln: Navision liefert
/// *was* gebraucht wird (Bestand, offene Aufträge), die App-Artikel
/// beschreiben *wie* produziert wird. Hier ist die Brücke — von hier aus
/// zieht man Positionen in den Bedarf, der Rest bleibt unberührt.
class NavisionImportScreen extends ConsumerStatefulWidget {
  const NavisionImportScreen({super.key});

  @override
  ConsumerState<NavisionImportScreen> createState() =>
      _NavisionImportScreenState();
}

/// Sortierkriterien der Navision-Liste.
enum _NavSort {
  bedarfAbst('Offener Bedarf ↓'),
  bedarfAufst('Offener Bedarf ↑'),
  nummer('Artikelnummer'),
  bezeichnung('Bezeichnung A–Z'),
  bestandAbst('Lagerbestand ↓'),
  auftragAbst('Menge in Auftrag ↓');

  const _NavSort(this.label);
  final String label;
}

class _NavisionImportScreenState extends ConsumerState<NavisionImportScreen> {
  final _suche = TextEditingController();
  String? _produktgruppe;
  String? _kategorie;
  String? _buchungsgruppe;
  String? _einheit;
  // Standardmäßig alle importierten Navision-Artikel anzeigen. Viele
  // Navision-Exporte enthalten vor allem Null-/0-Bedarf-Zeilen; der Filter
  // „Nur mit Bedarf“ würde sonst sofort die komplette Liste verbergen und
  // den Eindruck erwecken, der Import sei fehlgeschlagen.
  bool _nurBedarf = false;
  bool _nurBestand = false;
  _NavSort _sort = _NavSort.bedarfAbst;
  bool _busy = false;
  final Set<String> _markiert = {};

  @override
  void dispose() {
    _suche.dispose();
    super.dispose();
  }

  /// Offener Bedarf = bestellte Menge minus Lagerbestand.
  ///
  /// „Menge in FA" wird bewusst NICHT abgezogen: Sie steht in Navision
  /// nicht für eine geplante Produktionsmenge, sondern für eine erste
  /// Anfrage (z.B. pro Kutter), aus der erst manuell hochgerechnet wird.
  /// Sie abzuziehen würde den Bedarf systematisch zu klein rechnen.
  ///
  /// Achtung: Das Ergebnis trägt die Navision-Basiseinheit — nicht
  /// zwingend Kilogramm. Die Umrechnung passiert erst bei der Übernahme.
  static double offenerBedarf(NavisionArtikel a) {
    final rest = a.mengeInAuftrag - a.lagerbestand;
    return rest > 0 ? rest : 0;
  }

  static bool istKg(NavisionArtikel a) =>
      (a.basiseinheit ?? '').toUpperCase() == 'KG';

  /// Netto noch offener Bedarf in kg: Navision-Bedarf (in kg) minus die
  /// bereits offen im Bedarf liegende Menge. null, wenn die kg-Menge mangels
  /// Umrechnungsfaktor (noch) nicht bestimmbar ist.
  static double? nettoOffenKg(
    NavisionArtikel a,
    Map<String, double> imBedarfKg,
    Map<String, double> faktoren,
  ) {
    final double? navKg;
    if (istKg(a)) {
      navKg = offenerBedarf(a);
    } else {
      final f = faktoren[a.nummer];
      navKg = (f != null && f > 0) ? offenerBedarf(a) * f : null;
    }
    if (navKg == null) return null;
    final netto = navKg - (imBedarfKg[a.nummer] ?? 0);
    return netto > 0 ? netto : 0;
  }

  List<NavisionArtikel> _gefiltert(
    List<NavisionArtikel> alle,
    Map<String, double> imBedarfKg,
    Map<String, double> faktoren,
  ) {
    final suchText = _suche.text.trim().toLowerCase();
    final liste = alle.where((a) {
      if (_nurBedarf) {
        final netto = nettoOffenKg(a, imBedarfKg, faktoren);
        // netto == null → mangels Faktor nicht bestimmbar → sichtbar
        // lassen, solange Navision überhaupt Bedarf zeigt.
        if (netto == null) {
          if (offenerBedarf(a) <= 0) return false;
        } else if (netto <= 0) {
          return false;
        }
      }
      if (_nurBestand && a.lagerbestand <= 0) return false;
      if (_produktgruppe != null && a.produktgruppe != _produktgruppe) {
        return false;
      }
      if (_kategorie != null && a.artikelkategorie != _kategorie) return false;
      if (_buchungsgruppe != null &&
          a.produktbuchungsgruppe != _buchungsgruppe) {
        return false;
      }
      if (_einheit != null && a.basiseinheit != _einheit) return false;
      if (suchText.isEmpty) return true;
      return a.nummer.toLowerCase().contains(suchText) ||
          a.beschreibung.toLowerCase().contains(suchText) ||
          (a.beschreibung2 ?? '').toLowerCase().contains(suchText);
    }).toList();

    // Sortierung. Beim Bedarf wird der NETTO-Wert genutzt (Navision minus
    // was schon im Bedarf liegt) — das ist die Zahl, die tatsächlich
    // Arbeit bedeutet. Fehlt der Umrechnungsfaktor, greift ersatzweise
    // der reine Navision-Bedarf.
    double netto(NavisionArtikel a) =>
        nettoOffenKg(a, imBedarfKg, faktoren) ?? offenerBedarf(a);

    switch (_sort) {
      case _NavSort.bedarfAbst:
        liste.sort((a, b) => netto(b).compareTo(netto(a)));
      case _NavSort.bedarfAufst:
        liste.sort((a, b) => netto(a).compareTo(netto(b)));
      case _NavSort.nummer:
        liste.sort(
          (a, b) => a.nummer.toLowerCase().compareTo(b.nummer.toLowerCase()),
        );
      case _NavSort.bezeichnung:
        liste.sort(
          (a, b) => a.beschreibung
              .toLowerCase()
              .compareTo(b.beschreibung.toLowerCase()),
        );
      case _NavSort.bestandAbst:
        liste.sort((a, b) => b.lagerbestand.compareTo(a.lagerbestand));
      case _NavSort.auftragAbst:
        liste.sort((a, b) => b.mengeInAuftrag.compareTo(a.mengeInAuftrag));
    }
    return liste;
  }

  Future<void> _import() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true, // Desktop liefert sonst teils nur einen Pfad, keine Bytes
    );
    if (picked == null) return; // Auswahl abgebrochen — bewusst still

    final datei = picked.files.isNotEmpty ? picked.files.first : null;
    var bytes = datei?.bytes;

    // Fallback: füllt eine Plattform die Bytes trotz withData nicht, liefert
    // aber einen Pfad, dann lesen wir die Datei selbst ein.
    if (bytes == null && datei?.path != null) {
      try {
        bytes = await File(datei!.path!).readAsBytes();
      } catch (e) {
        debugPrint('[NAV] Datei über Pfad lesen fehlgeschlagen: $e');
      }
    }

    if (bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Die gewählte Datei ließ sich nicht lesen (weder Inhalt noch '
            'Pfad verfügbar). Bitte erneut versuchen.',
          ),
        ),
      );
      return;
    }

    debugPrint('[NAV] Datei gewählt: ${datei?.name} · ${bytes.length} Bytes');
    setState(() => _busy = true);
    try {
      final service = NavisionImportService(ref.read(databaseProvider));
      final res = await service.importiere(bytes);
      ref.invalidate(navisionKatalogProvider);
      ref
          .read(autoBackupTriggerProvider)
          .fireDebounced(reason: 'Navision-Import');
      if (!mounted) return;
      final warnHinweis =
          res.warnungen.isEmpty ? '' : ' · ${res.warnungen.length} Hinweis(e)';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Text(
            res.uebernommen == 0
                ? 'Keine Artikel eingelesen (${res.gelesen} Datenzeilen '
                    'geprüft). Details siehe Log-Ausgabe.'
                : '${res.uebernommen} Artikel übernommen · '
                    '${res.mitAuftrag} mit offenen Aufträgen$warnHinweis',
          ),
        ),
      );
    } catch (e, st) {
      debugPrint('[NAV] Import fehlgeschlagen: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text('Import fehlgeschlagen: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Überträgt die markierten Positionen als Bedarf.
  ///
  /// Zwei Dinge müssen dabei stimmen: Der Bedarf wird in KILOGRAMM
  /// gespeichert (so rechnet die ganze Planung), und ein Artikel muss in
  /// der App existieren. Für Positionen in Beutel, Pack oder Stück fragt
  /// die App vorher nach dem Umrechnungsfaktor — und merkt ihn sich für
  /// das nächste Mal.
  Future<void> _inBedarf(List<NavisionArtikel> kandidaten) async {
    final offen = kandidaten.where((a) => offenerBedarf(a) > 0).toList();
    if (offen.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keine der Positionen hat Bedarf.')),
      );
      return;
    }

    final db = ref.read(databaseProvider);

    // Bekannte Faktoren laden — nur die, die noch zur aktuellen Einheit
    // passen (Navision kann die Basiseinheit ändern).
    final gespeichert = await db.select(db.navisionUmrechnungen).get();
    final faktorVon = <String, double>{};
    for (final u in gespeichert) {
      faktorVon[u.nummer] = u.kgJeEinheit;
    }
    final einheitVon = {for (final u in gespeichert) u.nummer: u.einheit};

    final offeneUmrechnung = offen
        .where(
          (a) =>
              !istKg(a) &&
              (faktorVon[a.nummer] == null ||
                  einheitVon[a.nummer] != (a.basiseinheit ?? '')),
        )
        .toList();

    if (offeneUmrechnung.isNotEmpty) {
      if (!mounted) return;
      final eingaben = await showDialog<Map<String, double>>(
        context: context,
        builder: (_) => _UmrechnungDialog(artikel: offeneUmrechnung),
      );
      if (eingaben == null) return; // abgebrochen
      for (final e in eingaben.entries) {
        faktorVon[e.key] = e.value;
        await db.into(db.navisionUmrechnungen).insertOnConflictUpdate(
              NavisionUmrechnungenCompanion.insert(
                nummer: e.key,
                einheit: offen
                        .firstWhere((a) => a.nummer == e.key)
                        .basiseinheit ??
                    '',
                kgJeEinheit: e.value,
                updatedAt: Value(DateTime.now()),
              ),
            );
      }
    }

    final vorhandene = await (db.select(db.products)
          ..where((p) => p.deletedAt.isNull()))
        .get();
    final idVonNummer = {for (final p in vorhandene) p.artikelnummer: p.id};

    // Was liegt je Produkt bereits OFFEN im Bedarf? Nur die Differenz zu
    // Navision wird neu angelegt — so entstehen über Tage keine Doppelungen.
    final offeneDemands = await (db.select(db.demands)
          ..where((d) => d.deletedAt.isNull())
          ..where((d) => d.manuellErledigt.equals(false)))
        .get();
    final bereitsKgVon = <String, double>{};
    for (final d in offeneDemands) {
      bereitsKgVon[d.productId] =
          (bereitsKgVon[d.productId] ?? 0) + d.mengeKgFertig;
    }

    var angelegt = 0;
    var uebernommen = 0;
    var uebersprungen = 0;
    var bereitsGedeckt = 0;

    for (final a in offen) {
      final menge = offenerBedarf(a);
      final double kg;
      if (istKg(a)) {
        kg = menge;
      } else {
        final f = faktorVon[a.nummer];
        if (f == null || f <= 0) {
          uebersprungen++;
          continue; // ohne Faktor keine belastbare kg-Menge
        }
        kg = menge * f;
      }

      var productId = idVonNummer[a.nummer];
      if (productId == null) {
        productId = const Uuid().v4();
        await db.into(db.products).insert(
              ProductsCompanion.insert(
                id: productId,
                artikelnummer: a.nummer,
                artikelbezeichnung:
                    a.beschreibung.isEmpty ? a.nummer : a.beschreibung,
                beschreibung: Value(a.beschreibung2),
                istEingepflegt: const Value(false),
              ),
            );
        idVonNummer[a.nummer] = productId;
        angelegt++;
      }

      // Delta: nur der noch nicht gedeckte Teil des Navision-Bedarfs.
      final bereits = bereitsKgVon[productId] ?? 0;
      final delta = kg - bereits;
      if (delta < 0.5) {
        bereitsGedeckt++;
        continue; // schon vollständig im Bedarf → nichts Doppeltes anlegen
      }

      final abzug =
          bereits > 0 ? ' · abzügl. ${_fmt(bereits)} kg im Bedarf' : '';
      final herkunft = istKg(a)
          ? 'Aus Navision · Auftrag ${_fmt(a.mengeInAuftrag)} kg · '
              'Bestand ${_fmt(a.lagerbestand)} kg$abzug'
          : 'Aus Navision · ${_fmt(menge)} ${a.basiseinheit} '
              '× ${_fmt(faktorVon[a.nummer] ?? 0)} kg$abzug';

      await db.into(db.demands).insert(
            DemandsCompanion.insert(
              id: const Uuid().v4(),
              productId: productId,
              mengeKgFertig: delta,
              quelle: const Value('bestellung'),
              notizen: Value(herkunft),
            ),
          );
      bereitsKgVon[productId] = bereits + delta;
      uebernommen++;
    }

    ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Bedarf aus NAV');
    ref.invalidate(appArtikelnummernProvider);
    ref.invalidate(bedarfProvider);
    ref.invalidate(imBedarfKgProvider);
    ref.invalidate(umrechnungsFaktorenProvider);
    if (!mounted) return;
    setState(_markiert.clear);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$uebernommen Bedarfspositionen angelegt'
          '${angelegt > 0 ? ' · $angelegt Artikel neu erstellt' : ''}'
          '${bereitsGedeckt > 0 ? ' · $bereitsGedeckt bereits gedeckt' : ''}'
          '${uebersprungen > 0 ? ' · $uebersprungen ohne Umrechnung '
              'übersprungen' : ''}',
        ),
      ),
    );
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final katalog = ref.watch(navisionKatalogProvider);
    final appNummern = ref.watch(appArtikelnummernProvider).valueOrNull ??
        const <String>{};
    final imBedarfKg = ref.watch(imBedarfKgProvider).valueOrNull ??
        const <String, double>{};
    final faktoren = ref.watch(umrechnungsFaktorenProvider).valueOrNull ??
        const <String, double>{};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Navision-Import'),
        actions: [
          TextButton.icon(
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.upload_file, size: 18),
            label: const Text('Artikelübersicht einlesen'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: katalog.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (alle) {
          if (alle.isEmpty) return _leerHinweis(context);
          final liste = _gefiltert(alle, imBedarfKg, faktoren);
          final markierte =
              liste.where((a) => _markiert.contains(a.nummer)).toList();
          final fehlendeMitBedarf = alle
              .where(
                (a) => offenerBedarf(a) > 0 && !appNummern.contains(a.nummer),
              )
              .toList();

          return Column(
            children: [
              _filterLeiste(context, alle, liste.length),
              if (fehlendeMitBedarf.isNotEmpty)
                _fehlendeBanner(context, fehlendeMitBedarf),
              const Divider(height: 1),
              Expanded(
                child: _tabelle(
                  context,
                  liste,
                  appNummern,
                  imBedarfKg,
                  faktoren,
                ),
              ),
              if (markierte.isNotEmpty)
                _aktionsLeiste(context, markierte),
            ],
          );
        },
      ),
    );
  }

  Widget _leerHinweis(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.table_view,
              size: 46,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            const Text(
              'Noch kein Navision-Stand eingelesen.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Zieh in Navision die Artikelübersicht nach Excel und lies '
              'sie hier ein. Aus Bestand, Menge in Auftrag und Menge in FA '
              'errechnet die App den offenen Bedarf.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }

  Widget _filterLeiste(
    BuildContext context,
    List<NavisionArtikel> alle,
    int treffer,
  ) {
    final theme = Theme.of(context);
    List<String> werte(String? Function(NavisionArtikel) f) {
      final s = <String>{};
      for (final a in alle) {
        final v = f(a);
        if (v != null && v.trim().isNotEmpty) s.add(v);
      }
      final l = s.toList()..sort();
      return l;
    }

    Widget dropdown(
      String label,
      String? wert,
      List<String> optionen,
      ValueChanged<String?> onChanged,
    ) {
      return SizedBox(
        width: 210,
        child: DropdownButtonFormField<String>(
          initialValue: wert,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            const DropdownMenuItem(value: null, child: Text('Alle')),
            for (final o in optionen)
              DropdownMenuItem(value: o, child: Text(o)),
          ],
          onChanged: (v) => setState(() => onChanged(v)),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _suche,
                  decoration: const InputDecoration(
                    labelText: 'Suche (Nummer oder Bezeichnung)',
                    prefixIcon: Icon(Icons.search, size: 18),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              dropdown(
                'Produktgruppe',
                _produktgruppe,
                werte((a) => a.produktgruppe),
                (v) => _produktgruppe = v,
              ),
              dropdown(
                'Kategorie',
                _kategorie,
                werte((a) => a.artikelkategorie),
                (v) => _kategorie = v,
              ),
              dropdown(
                'Buchungsgruppe',
                _buchungsgruppe,
                werte((a) => a.produktbuchungsgruppe),
                (v) => _buchungsgruppe = v,
              ),
              dropdown(
                'Einheit',
                _einheit,
                werte((a) => a.basiseinheit),
                (v) => _einheit = v,
              ),
              FilterChip(
                label: const Text('Nur mit Bedarf'),
                selected: _nurBedarf,
                onSelected: (v) => setState(() => _nurBedarf = v),
              ),
              FilterChip(
                label: const Text('Nur mit Bestand'),
                selected: _nurBestand,
                onSelected: (v) => setState(() => _nurBestand = v),
              ),
              // Sortierung der Liste
              SizedBox(
                height: 38,
                child: DropdownButtonFormField<_NavSort>(
                  initialValue: _sort,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Sortierung',
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  ),
                  style: const TextStyle(fontSize: 12.5),
                  items: [
                    for (final s in _NavSort.values)
                      DropdownMenuItem(value: s, child: Text(s.label)),
                  ],
                  onChanged: (v) =>
                      setState(() => _sort = v ?? _NavSort.bedarfAbst),
                ),
              ),
              if (_produktgruppe != null ||
                  _kategorie != null ||
                  _buchungsgruppe != null ||
                  _einheit != null ||
                  _suche.text.isNotEmpty)
                TextButton.icon(
                  onPressed: () => setState(() {
                    _produktgruppe = null;
                    _kategorie = null;
                    _buchungsgruppe = null;
                    _einheit = null;
                    _suche.clear();
                  }),
                  icon: const Icon(Icons.filter_alt_off, size: 18),
                  label: const Text('Filter zurücksetzen'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$treffer von ${alle.length} Artikeln'
            '${alle.isEmpty ? '' : ' · Stand '
                '${_fmtDatum(alle.first.importiertAm)}'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtDatum(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.${d.year}';

  Widget _tabelle(
    BuildContext context,
    List<NavisionArtikel> liste,
    Set<String> appNummern,
    Map<String, double> imBedarfKg,
    Map<String, double> faktoren,
  ) {
    final theme = Theme.of(context);
    if (liste.isEmpty) {
      return Center(
        child: Text(
          'Keine Artikel passen zu den Filtern.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: liste.length,
      itemBuilder: (context, i) {
        final a = liste[i];
        final bedarf = offenerBedarf(a);
        final inApp = appNummern.contains(a.nummer);
        final bereitsKg = imBedarfKg[a.nummer] ?? 0;
        final nettoKg = nettoOffenKg(a, imBedarfKg, faktoren);
        final imBedarfBereits = bereitsKg > 0;
        final gedeckt = imBedarfBereits && nettoKg != null && nettoKg <= 0;
        final markiert = _markiert.contains(a.nummer);
        return InkWell(
          onTap: () => setState(() {
            markiert ? _markiert.remove(a.nummer) : _markiert.add(a.nummer);
          }),
          child: Container(
            decoration: BoxDecoration(
              color: markiert
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
                  : (gedeckt
                      ? Colors.green.withValues(alpha: 0.07)
                      : null),
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              children: [
                SizedBox(
                  width: 26,
                  child: Icon(
                    markiert
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    size: 18,
                    color: markiert
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(
                  width: 84,
                  child: Text(
                    a.nummer,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.primary,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.beschreibung,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if ((a.beschreibung2 ?? '').isNotEmpty)
                        Text(
                          a.beschreibung2!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      if (imBedarfBereits)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                gedeckt
                                    ? Icons.check_circle
                                    : Icons.playlist_add_check,
                                size: 13,
                                color: gedeckt
                                    ? Colors.green.shade700
                                    : Colors.orange.shade800,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                nettoKg == null
                                    ? 'im Bedarf: ${_fmt(bereitsKg)} kg'
                                    : (gedeckt
                                        ? 'komplett im Bedarf '
                                            '(${_fmt(bereitsKg)} kg)'
                                        : 'im Bedarf ${_fmt(bereitsKg)} kg · '
                                            'offen ${_fmt(nettoKg)} kg'),
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: gedeckt
                                      ? Colors.green.shade700
                                      : Colors.orange.shade800,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 62,
                  child: Tooltip(
                    message: istKg(a)
                        ? 'Basiseinheit Kilogramm'
                        : 'Basiseinheit ${a.basiseinheit} — '
                            'muss für die Planung in kg umgerechnet werden',
                    child: Text(
                      a.basiseinheit ?? '—',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: istKg(a)
                            ? theme.colorScheme.onSurfaceVariant
                            : Colors.orange.shade800,
                      ),
                    ),
                  ),
                ),
                _zahlSpalte('Bestand', a.lagerbestand, theme),
                _zahlSpalte(
                  'Auftrag',
                  a.mengeInAuftrag,
                  theme,
                ),
                _zahlSpalte(
                  'Bedarf',
                  bedarf,
                  theme,
                  hervorheben: bedarf > 0,
                ),
                SizedBox(
                  width: 34,
                  child: inApp
                      ? Tooltip(
                          message: 'Prozess in der App vorhanden',
                          child: Icon(
                            Icons.link,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : Tooltip(
                          message: 'Noch kein App-Artikel — '
                              'wird bei Übernahme angelegt',
                          child: Icon(
                            Icons.link_off,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.5),
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _zahlSpalte(
    String label,
    double wert,
    ThemeData theme, {
    bool hervorheben = false,
  }) {
    return SizedBox(
      width: 92,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            _fmt(wert),
            style: TextStyle(
              fontSize: 13,
              fontWeight: hervorheben ? FontWeight.w800 : FontWeight.w500,
              color: hervorheben ? theme.colorScheme.primary : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _aktionsLeiste(
    BuildContext context,
    List<NavisionArtikel> markierte,
  ) {
    final summe = markierte.fold<double>(0, (s, a) => s + offenerBedarf(a));
    return Material(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          children: [
            Text(
              '${markierte.length} markiert · ${_fmt(summe)} kg Bedarf',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => setState(_markiert.clear),
              child: const Text('Auswahl aufheben'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _inBedarf(markierte),
              icon: const Icon(Icons.playlist_add, size: 18),
              label: const Text('In Bedarf übernehmen'),
            ),
          ],
        ),
      ),
    );
  }

  /// Kompakter Hinweis über der Tabelle: N Artikel mit offenem Bedarf haben
  /// noch keine Artikelmaske. Ein Klick legt für alle eine Stub-Maske an.
  Widget _fehlendeBanner(
    BuildContext context,
    List<NavisionArtikel> fehlende,
  ) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 18,
              color: theme.colorScheme.onTertiaryContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${fehlende.length} Artikel mit Bedarf haben noch keine '
                'Artikelmaske in der App.',
                style: TextStyle(
                  color: theme.colorScheme.onTertiaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _busy ? null : () => _fehlendeAnlegen(fehlende),
              icon: const Icon(Icons.playlist_add_check, size: 18),
              label: Text('Fehlende anlegen (${fehlende.length})'),
            ),
          ],
        ),
      ),
    );
  }

  /// Legt für alle übergebenen Navision-Artikel eine „nicht eingepflegte"
  /// Stub-Artikelmaske an — aber nur, wenn die Artikelnummer noch nicht
  /// existiert. Der Abgleich läuft über die eindeutige Artikelnummer, es
  /// wird also nichts doppelt angelegt und keine bereits gepflegte Maske
  /// überschrieben.
  Future<void> _fehlendeAnlegen(List<NavisionArtikel> fehlende) async {
    final anzahl = fehlende.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Fehlende Artikel anlegen?'),
        content: Text(
          'Für $anzahl Artikel mit offenem Bedarf, die es in der Artikelliste '
          'noch nicht gibt, wird je eine Artikelmaske angelegt und als '
          '„nicht eingepflegt" markiert. Bereits vorhandene Artikel bleiben '
          'unberührt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('$anzahl anlegen'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final db = ref.read(databaseProvider);
      var angelegt = 0;
      await db.transaction(() async {
        // Alle bestehenden Nummern EINMAL laden (inkl. soft-deleted — die
        // Unique-Spalte artikelnummer ist auch dann noch belegt).
        final vorhandene = await db.select(db.products).get();
        final nummern = vorhandene.map((p) => p.artikelnummer).toSet();
        for (final a in fehlende) {
          if (nummern.contains(a.nummer)) continue;
          await db.into(db.products).insert(
                ProductsCompanion.insert(
                  id: const Uuid().v4(),
                  artikelnummer: a.nummer,
                  artikelbezeichnung:
                      a.beschreibung.isEmpty ? a.nummer : a.beschreibung,
                  beschreibung: Value(a.beschreibung2),
                  istEingepflegt: const Value(false),
                ),
              );
          nummern.add(a.nummer);
          angelegt++;
        }
      });
      ref.invalidate(appArtikelnummernProvider);
      ref
          .read(autoBackupTriggerProvider)
          .fireDebounced(reason: 'Navision-Stubs angelegt');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Text(
            '$angelegt Artikelmaske(n) angelegt · als „nicht eingepflegt" '
            'markiert. Du findest sie in der Artikelliste.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Anlegen fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Fragt für Artikel ohne Kilogramm-Basiseinheit den Umrechnungsfaktor ab.
///
/// Navision führt viele Fertigwaren in Beutel oder Pack. Für die Planung
/// zählt aber, wie viel Masse durch die Anlagen geht — deshalb hier die
/// einmalige Angabe „wie viel kg ist eine Einheit". Der Wert wird
/// gespeichert und beim nächsten Import wiederverwendet.
class _UmrechnungDialog extends StatefulWidget {
  const _UmrechnungDialog({required this.artikel});

  final List<NavisionArtikel> artikel;

  @override
  State<_UmrechnungDialog> createState() => _UmrechnungDialogState();
}

class _UmrechnungDialogState extends State<_UmrechnungDialog> {
  final Map<String, TextEditingController> _felder = {};

  @override
  void initState() {
    super.initState();
    for (final a in widget.artikel) {
      _felder[a.nummer] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in _felder.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, double> _werte() {
    final res = <String, double>{};
    for (final e in _felder.entries) {
      final v = double.tryParse(e.value.text.trim().replaceAll(',', '.'));
      if (v != null && v > 0) res[e.key] = v;
    }
    return res;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gefuellt = _werte().length;
    return AlertDialog(
      title: const Text('Einheiten umrechnen'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Diese Artikel führt Navision nicht in Kilogramm. Trag ein, '
              'wie viel kg eine Einheit entspricht — die Angabe wird '
              'gespeichert und künftig automatisch verwendet. '
              'Leer gelassene Zeilen werden übersprungen.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.artikel.length,
                itemBuilder: (context, i) {
                  final a = widget.artikel[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 76,
                          child: Text(
                            a.nummer,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            a.beschreibung,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 128,
                          child: TextField(
                            controller: _felder[a.nummer],
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textAlign: TextAlign.end,
                            decoration: InputDecoration(
                              labelText: 'kg je ${a.basiseinheit}',
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                  );
                },
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
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_werte()),
          child: Text(
            gefuellt == 0
                ? 'Ohne Umrechnung fortfahren'
                : '$gefuellt übernehmen',
          ),
        ),
      ],
    );
  }
}
