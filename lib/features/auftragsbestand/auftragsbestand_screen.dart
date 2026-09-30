import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auftragsbestand_import_service.dart';
import '../bedarf/bedarf_screen.dart' show heuteProvider;
import '../navision/navision_import_screen.dart'
    show abteilungenJeArtikelProvider, appArtikelnummernProvider;

// ═══════════════════════════════════════════════════════════════════════════
// Daten für die Ansicht
// ═══════════════════════════════════════════════════════════════════════════

/// Ein Artikel des Auftragsbestands samt Deckung aus dem Lager.
class AuftragsbestandZeile {
  const AuftragsbestandZeile({
    required this.artikel,
    required this.positionen,
    required this.deckung,
  });

  final AuftragsArtikel artikel;
  final List<AuftragsPosition> positionen;
  final ArtikelDeckung deckung;

  Set<String> get belege => {for (final p in positionen) p.beleg};
  Set<String> get kunden => {for (final p in positionen) p.debitor};
}

/// Der zuletzt eingelesene Auftragsbestand.
class AuftragsbestandAnsicht {
  const AuftragsbestandAnsicht({
    required this.zeilen,
    this.stand,
    this.von,
    this.bis,
    this.importiertAm,
  });

  final List<AuftragsbestandZeile> zeilen;
  final DateTime? stand;
  final DateTime? von;
  final DateTime? bis;
  final DateTime? importiertAm;

  bool get leer => zeilen.isEmpty;
}

/// Lädt den Auftragsbestand und rechnet je Artikel die Deckung aus dem
/// Lager.
///
/// `autoDispose`: Beim nächsten Öffnen wird neu gelesen. Die Rechnung ist
/// billig — ein paar tausend Zeilen —, und so gibt es keinen veralteten
/// Zwischenstand.
final auftragsbestandProvider =
    FutureProvider.autoDispose<AuftragsbestandAnsicht>((ref) async {
  final db = ref.watch(databaseProvider);
  final artikel = await db.select(db.auftragsbestandArtikel).get();
  if (artikel.isEmpty) return const AuftragsbestandAnsicht(zeilen: []);

  final positionen = await db.select(db.auftragsbestandPositionen).get();
  final jeArtikel = <String, List<AuftragsPosition>>{};
  for (final p in positionen) {
    jeArtikel.putIfAbsent(p.artikelnummer, () => []).add(p);
  }

  final erster = artikel.first;
  return AuftragsbestandAnsicht(
    stand: erster.berichtStand,
    von: erster.zeitraumVon,
    bis: erster.zeitraumBis,
    importiertAm: erster.importiertAm,
    zeilen: [
      for (final a in artikel)
        AuftragsbestandZeile(
          artikel: a,
          positionen: jeArtikel[a.artikelnummer] ?? const [],
          deckung: berechneDeckung(
            lagerKg: a.lagerKg,
            positionen: jeArtikel[a.artikelnummer] ?? const [],
          ),
        ),
    ],
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// Screen
// ═══════════════════════════════════════════════════════════════════════════

/// Sortierungen der Artikelliste.
enum _Sortierung {
  engpass('Frühester Engpass'),
  fehlmenge('Fehlmenge ↓'),
  auftrag('Auftragsmenge ↓'),
  nummer('Artikelnummer');

  const _Sortierung(this.label);
  final String label;
}

/// Auftragsbestand aus Navision: Aufträge je Artikel nach Warenausgang,
/// das Lager dagegen gerechnet, und ab wann es nicht mehr reicht.
///
/// Erster Schritt: nur ansehen. Bedarf und Planungsvorschlag bleiben
/// vorerst, wie sie sind — der Auftragsbestand fließt erst in den nächsten
/// Schritten dort hinein.
class AuftragsbestandScreen extends ConsumerStatefulWidget {
  const AuftragsbestandScreen({super.key});

  @override
  ConsumerState<AuftragsbestandScreen> createState() =>
      _AuftragsbestandScreenState();
}

class _AuftragsbestandScreenState
    extends ConsumerState<AuftragsbestandScreen> {
  final _suche = TextEditingController();

  /// Standard: nur Artikel, bei denen das Lager nicht reicht — das ist
  /// die Arbeit. Der Zähler zeigt, wie viele ausgeblendet sind.
  bool _nurEngpaesse = true;
  String? _abteilung;
  _Sortierung _sortierung = _Sortierung.engpass;
  final Set<String> _offen = {};

  bool _liest = false;
  String? _fehler;
  List<String> _hinweise = const [];

  @override
  void dispose() {
    _suche.dispose();
    super.dispose();
  }

  // ── Einlesen ─────────────────────────────────────────────────────────

  Future<void> _einlesen() async {
    final gewaehlt = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (gewaehlt == null || !mounted) return;
    final datei = gewaehlt.files.isNotEmpty ? gewaehlt.files.first : null;
    var bytes = datei?.bytes;
    final pfad = datei?.path;
    if (bytes == null && pfad != null) {
      try {
        bytes = await File(pfad).readAsBytes();
      } catch (_) {
        bytes = null;
      }
      if (!mounted) return;
    }
    if (bytes == null) {
      setState(() => _fehler = 'Die gewählte Datei ließ sich nicht lesen.');
      return;
    }

    setState(() {
      _liest = true;
      _fehler = null;
      _hinweise = const [];
    });
    try {
      final ergebnis = await AuftragsbestandImportService(
        ref.read(databaseProvider),
      ).importiere(bytes);
      if (!mounted) return;
      ref.invalidate(auftragsbestandProvider);
      setState(() {
        _offen.clear();
        _hinweise = ergebnis.warnungen;
      });
      final verpackung = ergebnis.uebersprungen.isEmpty
          ? ''
          : ' · ${ergebnis.uebersprungen.length} Verpackungs- und '
              'Palettenartikel ausgelassen';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Text(
            '${ergebnis.artikel} Artikel · ${ergebnis.positionen} '
            'Auftragszeilen · ${ergebnis.kunden} Kunden eingelesen'
            '$verpackung',
          ),
        ),
      );
    } on FormatException catch (e) {
      if (mounted) setState(() => _fehler = e.message);
    } catch (e) {
      if (mounted) setState(() => _fehler = 'Einlesen fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _liest = false);
    }
  }

  // ── Filtern und Sortieren ────────────────────────────────────────────

  List<AuftragsbestandZeile> _gefiltert(
    List<AuftragsbestandZeile> alle,
    Map<String, Set<String>> abteilungen,
  ) {
    final suche = _suche.text.trim().toLowerCase();
    final liste = alle.where((z) {
      if (_nurEngpaesse && z.deckung.gedeckt) return false;
      final abteilung = _abteilung;
      if (abteilung != null &&
          !(abteilungen[z.artikel.artikelnummer]?.contains(abteilung) ??
              false)) {
        return false;
      }
      if (suche.isEmpty) return true;
      final a = z.artikel;
      if (a.artikelnummer.toLowerCase().contains(suche)) return true;
      if (a.bezeichnung.toLowerCase().contains(suche)) return true;
      if ((a.bezeichnung2 ?? '').toLowerCase().contains(suche)) return true;
      return z.positionen.any(
        (p) =>
            p.debitor.toLowerCase().contains(suche) ||
            p.beleg.toLowerCase().contains(suche),
      );
    }).toList();

    int nachNummer(AuftragsbestandZeile a, AuftragsbestandZeile b) =>
        a.artikel.artikelnummer.compareTo(b.artikel.artikelnummer);

    switch (_sortierung) {
      case _Sortierung.engpass:
        liste.sort((a, b) {
          final ea = a.deckung.ersterEngpass;
          final eb = b.deckung.ersterEngpass;
          if (ea != null && eb != null) {
            final t = ea.compareTo(eb);
            if (t != 0) return t;
            return b.deckung.fehltKg.compareTo(a.deckung.fehltKg);
          }
          if (ea != null) return -1;
          if (eb != null) return 1;
          return nachNummer(a, b);
        });
      case _Sortierung.fehlmenge:
        liste.sort((a, b) {
          final f = b.deckung.fehltKg.compareTo(a.deckung.fehltKg);
          return f != 0 ? f : nachNummer(a, b);
        });
      case _Sortierung.auftrag:
        liste.sort((a, b) {
          final f = b.deckung.auftragKg.compareTo(a.deckung.auftragKg);
          return f != 0 ? f : nachNummer(a, b);
        });
      case _Sortierung.nummer:
        liste.sort(nachNummer);
    }
    return liste;
  }

  // ── Aufbau ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ansicht = ref.watch(auftragsbestandProvider);
    final appNummern = ref.watch(appArtikelnummernProvider).valueOrNull ??
        const <String>{};
    final abteilungen = ref.watch(abteilungenJeArtikelProvider).valueOrNull ??
        const <String, Set<String>>{};
    final heute = ref.watch(heuteProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Auftragsbestand'),
        actions: [
          TextButton.icon(
            onPressed: _liest ? null : _einlesen,
            icon: const Icon(Icons.upload_file, size: 18),
            label: const Text('Auftragsbestand einlesen'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (_fehler != null)
                _Meldung(
                  text: _fehler!,
                  istFehler: true,
                  onSchliessen: () => setState(() => _fehler = null),
                ),
              if (_hinweise.isNotEmpty)
                _Meldung(
                  text: [
                    ..._hinweise.take(3),
                    if (_hinweise.length > 3)
                      '… und ${_hinweise.length - 3} weitere',
                  ].join('\n'),
                  istFehler: false,
                  onSchliessen: () =>
                      setState(() => _hinweise = const []),
                ),
              Expanded(
                child: ansicht.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Fehler: $e')),
                  data: (a) => a.leer
                      ? const _LeerHinweis()
                      : _inhalt(context, a, appNummern, abteilungen, heute),
                ),
              ),
            ],
          ),
          if (_liest) const _LeseSchleier(),
        ],
      ),
    );
  }

  Widget _inhalt(
    BuildContext context,
    AuftragsbestandAnsicht ansicht,
    Set<String> appNummern,
    Map<String, Set<String>> abteilungen,
    DateTime heute,
  ) {
    final liste = _gefiltert(ansicht.zeilen, abteilungen);
    return Column(
      children: [
        _Kopf(ansicht: ansicht),
        _filterLeiste(context, ansicht, abteilungen, liste.length),
        const Divider(height: 1),
        Expanded(
          child: liste.isEmpty
              ? Center(
                  child: Text(
                    'Keine Artikel passen zu den Filtern.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
                  itemCount: liste.length,
                  itemBuilder: (context, i) {
                    final z = liste[i];
                    final nr = z.artikel.artikelnummer;
                    return _ArtikelKarte(
                      zeile: z,
                      inApp: appNummern.contains(nr),
                      offen: _offen.contains(nr),
                      heute: heute,
                      onUmschalten: () => setState(() {
                        if (!_offen.remove(nr)) _offen.add(nr);
                      }),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _filterLeiste(
    BuildContext context,
    AuftragsbestandAnsicht ansicht,
    Map<String, Set<String>> abteilungen,
    int treffer,
  ) {
    final theme = Theme.of(context);

    // Artikel je Abteilung — gezählt gegen den ganzen Bestand, damit die
    // Zahl nicht bei jedem Tastendruck in der Suche springt.
    final anzahl = <String, int>{};
    for (final z in ansicht.zeilen) {
      for (final d
          in abteilungen[z.artikel.artikelnummer] ?? const <String>{}) {
        anzahl[d] = (anzahl[d] ?? 0) + 1;
      }
    }
    final engpaesse = ansicht.zeilen.where((z) => !z.deckung.gedeckt).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 300,
                child: TextField(
                  controller: _suche,
                  decoration: const InputDecoration(
                    labelText: 'Suche (Nummer, Bezeichnung, Kunde, Beleg)',
                    prefixIcon: Icon(Icons.search, size: 18),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              SizedBox(
                width: 230,
                child: DropdownButtonFormField<String>(
                  initialValue: _abteilung,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Abteilung',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Alle')),
                    for (final a in Abteilung.values)
                      DropdownMenuItem(
                        value: a.dbValue,
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: a.farbe,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                '${a.anzeigeName} '
                                '(${anzahl[a.dbValue] ?? 0})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _abteilung = v),
                ),
              ),
              FilterChip(
                label: Text('Nur wo das Lager nicht reicht ($engpaesse)'),
                selected: _nurEngpaesse,
                onSelected: (v) => setState(() => _nurEngpaesse = v),
              ),
              SizedBox(
                width: 210,
                child: DropdownButtonFormField<_Sortierung>(
                  initialValue: _sortierung,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Sortierung',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  // Farbe ausdrücklich — ohne sie erbt der Text im hellen
                  // Modus Weiß (derselbe Fehler wie im Navision-Import).
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurface,
                  ),
                  items: [
                    for (final s in _Sortierung.values)
                      DropdownMenuItem(value: s, child: Text(s.label)),
                  ],
                  onChanged: (v) => setState(
                    () => _sortierung = v ?? _Sortierung.engpass,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$treffer von ${ansicht.zeilen.length} Artikeln',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Bausteine
// ═══════════════════════════════════════════════════════════════════════════

/// Stand, Zeitraum und Kennzahlen des eingelesenen Berichts.
class _Kopf extends StatelessWidget {
  const _Kopf({required this.ansicht});

  final AuftragsbestandAnsicht ansicht;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final zeilen = ansicht.zeilen;
    final belege = <String>{};
    final kunden = <String>{};
    var auftragKg = 0.0;
    var fehltKg = 0.0;
    var engpaesse = 0;
    for (final z in zeilen) {
      belege.addAll(z.belege);
      kunden.addAll(z.kunden);
      auftragKg += z.deckung.auftragKg;
      fehltKg += z.deckung.fehltKg;
      if (!z.deckung.gedeckt) engpaesse++;
    }

    final stand = ansicht.stand;
    final von = ansicht.von;
    final bis = ansicht.bis;
    final importiert = ansicht.importiertAm;
    final zeile = [
      if (stand != null) 'Stand ${_datumLang(stand)}, ${_uhrzeit(stand)}',
      if (von != null && bis != null)
        'Warenausgang ${_datumKurz(von)}–${_datumLang(bis)}',
      if (importiert != null)
        'eingelesen ${_datumKurz(importiert)}, ${_uhrzeit(importiert)}',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            zeile,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _Kennzahl(wert: '${zeilen.length}', label: 'Artikel'),
              _Kennzahl(wert: '${belege.length}', label: 'Aufträge'),
              _Kennzahl(wert: '${kunden.length}', label: 'Kunden'),
              _Kennzahl(wert: '${_kg(auftragKg)} kg', label: 'bestellt'),
              _Kennzahl(
                wert: '$engpaesse',
                label: 'Artikel reichen nicht',
                warnung: engpaesse > 0,
              ),
              _Kennzahl(
                wert: '${_kg(fehltKg)} kg',
                label: 'fehlen gegen das Lager',
                warnung: fehltKg > 0,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Kennzahl extends StatelessWidget {
  const _Kennzahl({
    required this.wert,
    required this.label,
    this.warnung = false,
  });

  final String wert;
  final String label;
  final bool warnung;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final farbe =
        warnung ? theme.colorScheme.error : theme.colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            wert,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: farbe,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Ein Artikel: Kopfzeile mit Mengen und Status, aufgeklappt die Aufträge
/// nach Warenausgang.
class _ArtikelKarte extends StatelessWidget {
  const _ArtikelKarte({
    required this.zeile,
    required this.inApp,
    required this.offen,
    required this.heute,
    required this.onUmschalten,
  });

  final AuftragsbestandZeile zeile;
  final bool inApp;
  final bool offen;
  final DateTime heute;
  final VoidCallback onUmschalten;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = zeile.artikel;
    final d = zeile.deckung;
    final engpass = d.ersterEngpass;
    final rot = theme.colorScheme.error;
    final gruen = theme.brightness == Brightness.dark
        ? Colors.green.shade400
        : Colors.green.shade700;
    final akzent = d.gedeckt ? gruen : rot;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        // Farbiger Rand links: rot = Lager reicht nicht, grün = reicht.
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: akzent, width: 4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: onUmschalten,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Row(
                  children: [
                    Expanded(child: _kopfText(theme, a, d)),
                    const SizedBox(width: 10),
                    _Marke(
                      text: engpass == null
                          ? 'Lager reicht'
                          : 'fehlt ${_kg(d.fehltKg)} kg '
                              'ab ${_tagKurz(engpass)}',
                      farbe: akzent,
                      kraeftig: true,
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      offen ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            if (offen) _Tage(deckung: d, heute: heute),
          ],
        ),
      ),
    );
  }

  Widget _kopfText(ThemeData theme, AuftragsArtikel a, ArtikelDeckung d) {
    final auftraege = zeile.belege.length;
    final tage = d.tage.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${a.artikelnummer}  ${a.bezeichnung}',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (!inApp)
              _Marke(
                text: 'nicht in der App',
                farbe: theme.colorScheme.onSurfaceVariant,
              ),
          ],
        ),
        if ((a.bezeichnung2 ?? '').isNotEmpty)
          Text(
            a.bezeichnung2!,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        const SizedBox(height: 4),
        Text(
          'Aufträge ${_kg(d.auftragKg)} kg · Lager ${_kg(d.lagerKg)} kg · '
          '$auftraege ${auftraege == 1 ? 'Auftrag' : 'Aufträge'} an '
          '$tage ${tage == 1 ? 'Tag' : 'Tagen'}',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// Aufgeklappt: je Warenausgangstag Summe, Deckung und die Aufträge.
class _Tage extends StatelessWidget {
  const _Tage({required this.deckung, required this.heute});

  final ArtikelDeckung deckung;
  final DateTime heute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final klein = theme.textTheme.bodySmall;
    final grau = klein?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final rot = theme.colorScheme.error;

    return Container(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final t in deckung.tage) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(
                      _tagKurz(t.tag),
                      style: klein?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (t.tag.isBefore(heute))
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _Marke(text: 'überfällig', farbe: rot),
                    ),
                  Expanded(
                    child: Text(
                      '${t.positionen.length} '
                      '${t.positionen.length == 1 ? 'Auftrag' : 'Aufträge'}'
                      ' · ${_kg(t.kg)} kg',
                      style: klein?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text('aus Lager ${_kg(t.ausLagerKg)} kg', style: grau),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 110,
                    child: Text(
                      t.fehltKg >= 0.005 ? 'fehlt ${_kg(t.fehltKg)} kg' : '—',
                      textAlign: TextAlign.right,
                      style: klein?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: t.fehltKg >= 0.005 ? rot : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            for (final p in [...t.positionen]
              ..sort((a, b) => a.debitor.compareTo(b.debitor)))
              Padding(
                padding: const EdgeInsets.only(left: 92, top: 1),
                child: Row(
                  children: [
                    SizedBox(width: 90, child: Text(p.beleg, style: grau)),
                    Expanded(
                      child: Text(
                        p.debitor,
                        style: grau,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${_zahl(p.menge)} ${p.einheit ?? ''}',
                      style: grau,
                    ),
                    SizedBox(
                      width: 110,
                      child: Text(
                        '${_kg(p.kg)} kg',
                        textAlign: TextAlign.right,
                        style: grau,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Kleine Beschriftung mit Rahmen.
class _Marke extends StatelessWidget {
  const _Marke({
    required this.text,
    required this.farbe,
    this.kraeftig = false,
  });

  final String text;
  final Color farbe;
  final bool kraeftig;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: farbe.withValues(alpha: kraeftig ? 0.14 : 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: farbe.withValues(alpha: 0.45)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: kraeftig ? FontWeight.w700 : FontWeight.w500,
          color: farbe,
        ),
      ),
    );
  }
}

/// Fehler (rot) oder Hinweis (bernstein) über der Liste, zum Wegklicken.
class _Meldung extends StatelessWidget {
  const _Meldung({
    required this.text,
    required this.istFehler,
    required this.onSchliessen,
  });

  final String text;
  final bool istFehler;
  final VoidCallback onSchliessen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final farbe = istFehler ? theme.colorScheme.error : Colors.amber.shade800;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: farbe.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: farbe.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            istFehler ? Icons.error_outline : Icons.info_outline,
            color: farbe,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: farbe),
            ),
          ),
          IconButton(
            onPressed: onSchliessen,
            icon: const Icon(Icons.close, size: 18),
            visualDensity: VisualDensity.compact,
            tooltip: 'Schließen',
          ),
        ],
      ),
    );
  }
}

class _LeerHinweis extends StatelessWidget {
  const _LeerHinweis();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.local_shipping_outlined,
                size: 46,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 14),
              const Text(
                'Noch kein Auftragsbestand eingelesen.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'In Navision den Bericht „Auftragsbestand" mit dem '
                'gewünschten Zeitraum aufrufen, in der Vorschau „Speichern '
                'unter → Excel" wählen und die Datei hier einlesen.\n\n'
                'Tipp: Den Zeitraum ein paar Tage vor heute beginnen '
                'lassen. Dann sind auch überfällige, noch nicht versandte '
                'Aufträge dabei.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sperrt die Bedienung, solange eine Datei gelesen wird.
class _LeseSchleier extends StatelessWidget {
  const _LeseSchleier();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned.fill(
      child: ColoredBox(
        color: theme.colorScheme.surface.withValues(alpha: 0.85),
        child: const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 14),
                  Text('Auftragsbestand wird gelesen und geprüft …'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Formatierung
// ═══════════════════════════════════════════════════════════════════════════

const _wochentage = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

String _zweistellig(int n) => n.toString().padLeft(2, '0');

/// „Mi 02.10."
String _tagKurz(DateTime d) =>
    '${_wochentage[d.weekday - 1]} ${_zweistellig(d.day)}.'
    '${_zweistellig(d.month)}.';

/// „02.10."
String _datumKurz(DateTime d) =>
    '${_zweistellig(d.day)}.${_zweistellig(d.month)}.';

/// „02.10.2026"
String _datumLang(DateTime d) => '${_datumKurz(d)}${d.year}';

/// „12:09"
String _uhrzeit(DateTime d) =>
    '${_zweistellig(d.hour)}:${_zweistellig(d.minute)}';

/// Kilogramm mit deutschem Tausenderpunkt: ab 100 kg ganze Zahlen, darunter
/// eine Nachkommastelle, wenn es eine gibt („2.156", „68,3", „4").
String _kg(double v) {
  final ab100 = v.abs() >= 100;
  final zehntel = ab100 ? v.round() * 10 : (v * 10).round();
  final negativ = zehntel < 0;
  final betrag = zehntel.abs();
  final ganz = betrag ~/ 10;
  final rest = betrag % 10;
  final mitPunkten = ganz.toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => '.',
      );
  return '${negativ ? '-' : ''}$mitPunkten${rest == 0 ? '' : ',$rest'}';
}

/// Menge ohne unnötige Nachkommastellen („2", „1,5").
String _zahl(double v) => v == v.roundToDouble()
    ? v.round().toString()
    : v.toString().replaceAll('.', ',');
