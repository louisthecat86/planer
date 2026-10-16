import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/artikel_merkmale.dart';
import '../../core/database/database.dart';
import '../../core/providers/artikel_providers.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/artikel_anlage_service.dart';
import '../../core/services/artikelstamm_abgleich.dart';
import '../../core/services/auto_backup_trigger.dart';
import '../../core/services/navision_import_service.dart';
import '../../core/theme/app_stil.dart';
import '../../core/ui/bausteine.dart';
import '../articles/article_list_screen.dart' show articlesProvider;
import '../auftragsbestand/auftragsbestand_screen.dart'
    show auftragsbestandProvider;

/// Navision-Artikel: die Artikelübersicht aus Navision mit dem Artikelstamm
/// der App abgleichen.
///
/// Zwei Dinge kommen von hier: neue Artikel (als Hülle, „nicht
/// eingepflegt") und Allergene aus dem Navision-Suchbegriff — beides nur,
/// was der Anwender auswählt. Bestand und offene Aufträge liefert der
/// Auftragsbestand, genauer, nämlich je Auftrag und Versandtag. Bedarf
/// entsteht deshalb nicht mehr hier.
///
/// Die Datei wird nicht gespeichert: Der Abgleich gilt für diese Sitzung,
/// danach zählen nur die Artikel der App.
class NavisionImportScreen extends ConsumerStatefulWidget {
  const NavisionImportScreen({super.key});

  @override
  ConsumerState<NavisionImportScreen> createState() =>
      _NavisionImportScreenState();
}

/// Die drei Listen des Abgleichs.
enum _Ansicht { neu, ergaenzen, abweichend }

class _NavisionImportScreenState extends ConsumerState<NavisionImportScreen> {
  final _suche = TextEditingController();

  NavisionKatalog? _katalog;
  ArtikelstammAbgleich? _abgleich;
  String? _dateiname;

  /// Zählt die Einlesevorgänge — setzt Auswahlfelder beim nächsten
  /// Einlesen zurück.
  int _durchlauf = 0;

  /// Zwischenstand beim Einlesen (null = es läuft keins).
  NavisionFortschritt? _fortschritt;
  bool _speichert = false;
  String? _fehler;

  _Ansicht _ansicht = _Ansicht.neu;
  bool _nurAuftragsbestand = false;
  String? _produktgruppe;

  /// Allergen-Vorschläge aus dem Suchbegriff beim Anlegen mitnehmen.
  bool _allergeneMitAnlegen = true;

  /// Gewählte neue Artikel (Artikelnummern).
  final Set<String> _neuGewaehlt = {};

  /// Gewählte Allergen-Vorschläge (IDs der App-Artikel).
  final Set<String> _allergenGewaehlt = {};

  bool get _beschaeftigt => _fortschritt != null || _speichert;

  @override
  void dispose() {
    _suche.dispose();
    super.dispose();
  }

  // ── Einlesen ─────────────────────────────────────────────────────────

  Future<void> _einlesen() async {
    final db = ref.read(databaseProvider);
    final gewaehlt = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (gewaehlt == null || !mounted) return;
    final datei = gewaehlt.files.isNotEmpty ? gewaehlt.files.first : null;
    var bytes = datei?.bytes;
    final pfad = datei?.path;
    // Füllt eine Plattform die Bytes trotz withData nicht, liefert aber
    // einen Pfad, wird die Datei selbst gelesen.
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
      _fehler = null;
      _fortschritt = const NavisionFortschritt(phase: NavisionPhase.datei);
    });
    try {
      final katalog = await NavisionImportService.lese(
        bytes,
        onFortschritt: (stand) {
          if (mounted) setState(() => _fortschritt = stand);
        },
      );
      final abgleich = await _gleicheAb(db, katalog);
      if (!mounted) return;
      setState(() {
        _katalog = katalog;
        _abgleich = abgleich;
        _dateiname = datei?.name;
        _durchlauf++;
        // Vorausgewählt: was im Auftragsbestand steht und damit gebraucht
        // wird. Allergene nur auf ausdrücklichen Klick.
        _neuGewaehlt
          ..clear()
          ..addAll([
            for (final n in abgleich.neu)
              if (n.imAuftragsbestand) n.nummer,
          ]);
        _allergenGewaehlt.clear();
        _nurAuftragsbestand = abgleich.neu.any((n) => n.imAuftragsbestand);
        _produktgruppe = null;
        _suche.clear();
        _ansicht = abgleich.neu.isNotEmpty
            ? _Ansicht.neu
            : abgleich.ergaenzen.isNotEmpty
                ? _Ansicht.ergaenzen
                : abgleich.abweichend.isNotEmpty
                    ? _Ansicht.abweichend
                    : _Ansicht.neu;
      });
    } on FormatException catch (e) {
      if (mounted) setState(() => _fehler = e.message);
    } catch (e) {
      if (mounted) setState(() => _fehler = 'Einlesen fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _fortschritt = null);
    }
  }

  /// Gleicht [katalog] mit dem aktuellen Stand der App ab: alle Artikel
  /// (auch gelöschte) und die Nummern des eingelesenen Auftragsbestands.
  Future<ArtikelstammAbgleich> _gleicheAb(
    AppDatabase db,
    NavisionKatalog katalog,
  ) async {
    final produkte = await db.select(db.products).get();
    final auftrag = await db.select(db.auftragsbestandArtikel).get();
    return gleicheArtikelstammAb(
      katalog: katalog,
      produkte: produkte,
      imAuftragsbestand: {for (final a in auftrag) a.artikelnummer.trim()},
    );
  }

  // ── Übernehmen ───────────────────────────────────────────────────────

  Future<void> _uebernehmen() async {
    final abgleich = _abgleich;
    final katalog = _katalog;
    if (abgleich == null || katalog == null) return;

    final neue = [
      for (final n in abgleich.neu)
        if (_neuGewaehlt.contains(n.nummer)) n,
    ];
    final vorschlaege = [
      for (final v in [...abgleich.ergaenzen, ...abgleich.abweichend])
        if (_allergenGewaehlt.contains(v.produkt.id)) v,
    ];
    if (neue.isEmpty && vorschlaege.isEmpty) return;
    final mitAllergenen = _allergeneMitAnlegen;

    // Vor der ersten Wartestelle geholt: Der Container überlebt auch, wenn
    // jemand den Bildschirm währenddessen schließt.
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final db = ref.read(databaseProvider);

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _BestaetigenDialog(
        neue: neue.length,
        wiederAktiviert: neue.where((n) => n.geloescht).length,
        neueMitAllergenen: mitAllergenen
            ? neue.where((n) => n.allergene.isNotEmpty).length
            : 0,
        allergene: vorschlaege.length,
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _speichert = true);
    try {
      final ergebnis = await ArtikelAnlageService(db).legeAn(
        [
          for (final n in neue)
            FehlenderArtikel(
              nummer: n.nummer,
              bezeichnung: n.zeile.beschreibung,
              bezeichnung2: n.zeile.beschreibung2,
              allergene: mitAllergenen
                  ? merkmaleZuText(n.allergene, kAllergene)
                  : null,
            ),
        ],
        allergeneJeId: {
          for (final v in vorschlaege)
            if (v.ergebnis != null) v.produkt.id: v.ergebnis!,
        },
      );
      container.invalidate(appArtikelnummernProvider);
      container.invalidate(articlesProvider);
      container.invalidate(auftragsbestandProvider);
      if (ergebnis.geaendert) {
        container
            .read(autoBackupTriggerProvider)
            .fireDebounced(reason: 'Artikel aus Navision abgeglichen');
      }

      final teile = [
        if (ergebnis.angelegt > 0) '${ergebnis.angelegt} Artikel angelegt',
        if (ergebnis.reaktiviert > 0)
          '${ergebnis.reaktiviert} früher gelöschte wieder aktiviert',
        if (ergebnis.schonVorhanden > 0)
          '${ergebnis.schonVorhanden} gab es schon',
        if (ergebnis.allergeneGesetzt > 0)
          'Allergene bei ${ergebnis.allergeneGesetzt} Artikeln gesetzt',
      ];
      final pflege = ergebnis.gesamt > 0
          ? ' Neue Artikel sind als „nicht eingepflegt" markiert — Schritte '
              'und Stammdaten in der Artikelliste nachtragen.'
          : '';
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 7),
          content: Text(
            teile.isEmpty
                ? 'Nichts geändert.'
                : '${teile.join(' · ')}.$pflege',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
            'Übernehmen fehlgeschlagen — es wurde nichts gespeichert. ($e)',
          ),
        ),
      );
      if (mounted) setState(() => _speichert = false);
      return;
    }

    // Neu abgleichen: Was übernommen ist, verschwindet aus den Listen.
    // Scheitert das, ist trotzdem alles gespeichert — die Listen zeigen
    // dann bis zum nächsten Einlesen den alten Stand.
    ArtikelstammAbgleich? neu;
    try {
      neu = await _gleicheAb(db, katalog);
    } catch (_) {
      neu = null;
    }
    if (!mounted) return;
    final aktuell = neu;
    setState(() {
      if (aktuell != null) _abgleich = aktuell;
      _neuGewaehlt.removeAll([for (final n in neue) n.nummer]);
      _allergenGewaehlt.removeAll([for (final v in vorschlaege) v.produkt.id]);
      _speichert = false;
    });
  }

  // ── Filtern ──────────────────────────────────────────────────────────

  static bool _passt(String suche, List<String?> felder) {
    if (suche.isEmpty) return true;
    for (final f in felder) {
      if (f != null && f.toLowerCase().contains(suche)) return true;
    }
    return false;
  }

  List<NeuerNavisionArtikel> _neuGefiltert(ArtikelstammAbgleich a) {
    final suche = _suche.text.trim().toLowerCase();
    final gruppe = _produktgruppe;
    return [
      for (final n in a.neu)
        if ((!_nurAuftragsbestand || n.imAuftragsbestand) &&
            (gruppe == null || n.zeile.produktgruppe == gruppe) &&
            _passt(suche, [
              n.nummer,
              n.zeile.beschreibung,
              n.zeile.beschreibung2,
              n.zeile.suchbegriff,
            ]))
          n,
    ];
  }

  List<AllergenVorschlag> _vorschlaegeGefiltert(
    List<AllergenVorschlag> liste,
  ) {
    final suche = _suche.text.trim().toLowerCase();
    return [
      for (final v in liste)
        if (_passt(suche, [
          v.produkt.artikelnummer,
          v.produkt.artikelbezeichnung,
          v.zeile.beschreibung,
          v.zeile.suchbegriff,
        ]))
          v,
    ];
  }

  // ── Aufbau ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final abgleich = _abgleich;
    final fortschritt = _fortschritt;
    // Schmale Fenster: der Knopf der Kopfleiste nur als Symbol.
    final schmal = MediaQuery.sizeOf(context).width < 720;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Navision-Artikel'),
        actions: [
          // Vor dem ersten Einlesen trägt der Einstieg den Knopf — oben
          // stünde sonst derselbe noch einmal.
          if (abgleich != null) ...[
            if (schmal)
              IconButton(
                onPressed: _beschaeftigt ? null : _einlesen,
                icon: const Icon(Icons.upload_file),
                tooltip: 'Neu einlesen',
              )
            else
              OutlinedButton.icon(
                onPressed: _beschaeftigt ? null : _einlesen,
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Neu einlesen …'),
              ),
            const SizedBox(width: 12),
          ],
        ],
      ),
      body: Stack(
        children: [
          if (abgleich == null)
            _Einstieg(
              fehler: _fehler,
              onEinlesen: _beschaeftigt ? null : _einlesen,
            )
          else
            _inhalt(context, abgleich),
          if (fortschritt != null) _Fortschritt(stand: fortschritt),
        ],
      ),
    );
  }

  Widget _inhalt(BuildContext context, ArtikelstammAbgleich a) {
    final theme = Theme.of(context);
    final farben = theme.colorScheme;
    final grau = theme.textTheme.bodySmall?.copyWith(
      color: farben.onSurfaceVariant,
    );
    final meldung = _fehler;

    final Widget liste;
    final Widget filter;
    final Widget spaltenKopf;
    switch (_ansicht) {
      case _Ansicht.neu:
        final sichtbar = _neuGefiltert(a);
        filter = _neuFilter(context, a, sichtbar);
        spaltenKopf =
            const _SpaltenKopf(mitte: 'Beschreibung', rechts: 'Hinweise');
        liste = sichtbar.isEmpty
            ? Center(
                child: LeerHinweis(
                  a.neu.isEmpty
                      ? 'Alle Artikel der Datei gibt es in der App.'
                      : 'Keine neuen Artikel passen zu den Filtern.',
                ),
              )
            : ListView.builder(
                itemCount: sichtbar.length,
                itemBuilder: (context, i) {
                  final n = sichtbar[i];
                  return _NeuZeile(
                    artikel: n,
                    gewaehlt: _neuGewaehlt.contains(n.nummer),
                    mitAllergenen: _allergeneMitAnlegen,
                    onChanged: (an) => setState(() {
                      if (an) {
                        _neuGewaehlt.add(n.nummer);
                      } else {
                        _neuGewaehlt.remove(n.nummer);
                      }
                    }),
                  );
                },
              );
      case _Ansicht.ergaenzen:
      case _Ansicht.abweichend:
        final ergaenzen = _ansicht == _Ansicht.ergaenzen;
        final alle = ergaenzen ? a.ergaenzen : a.abweichend;
        final sichtbar = _vorschlaegeGefiltert(alle);
        filter = _allergenFilter(context, sichtbar, ergaenzen: ergaenzen);
        spaltenKopf =
            const _SpaltenKopf(mitte: 'Artikel', rechts: 'Allergene');
        liste = sichtbar.isEmpty
            ? Center(
                child: LeerHinweis(
                  alle.isEmpty
                      ? (ergaenzen
                          ? 'Kein Artikel der App ohne Allergene, für den '
                              'der Suchbegriff welche nennt.'
                          : 'Keine Abweichungen zwischen App und Navision.')
                      : 'Keine Artikel passen zur Suche.',
                ),
              )
            : ListView.builder(
                itemCount: sichtbar.length,
                itemBuilder: (context, i) {
                  final v = sichtbar[i];
                  return _AllergenZeile(
                    vorschlag: v,
                    gewaehlt: _allergenGewaehlt.contains(v.produkt.id),
                    onChanged: (an) => setState(() {
                      if (an) {
                        _allergenGewaehlt.add(v.produkt.id);
                      } else {
                        _allergenGewaehlt.remove(v.produkt.id);
                      }
                    }),
                  );
                },
              );
    }

    final neuWahl = _neuGewaehlt.length;
    final allergenWahl = _allergenGewaehlt.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (meldung != null) ...[
                HinweisBox(
                  meldung,
                  art: StatusArt.fehler,
                  auswaehlbar: true,
                  onSchliessen: () => setState(() => _fehler = null),
                ),
                const SizedBox(height: 10),
              ],
              _Kopf(abgleich: a, dateiname: _dateiname),
              if (a.warnungen.isNotEmpty) ...[
                const SizedBox(height: 10),
                _Hinweise(warnungen: a.warnungen),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<_Ansicht>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: _Ansicht.neu,
                    icon: const Icon(Icons.new_releases_outlined, size: 18),
                    label: Text('Neu (${a.neu.length})'),
                  ),
                  ButtonSegment(
                    value: _Ansicht.ergaenzen,
                    icon: const Icon(
                      Icons.playlist_add_check_rounded,
                      size: 18,
                    ),
                    label: Text('Allergene fehlen (${a.ergaenzen.length})'),
                  ),
                  ButtonSegment(
                    value: _Ansicht.abweichend,
                    icon: const Icon(Icons.compare_arrows_rounded, size: 18),
                    label: Text('Abweichungen (${a.abweichend.length})'),
                  ),
                ],
                selected: {_ansicht},
                onSelectionChanged: (s) => setState(() => _ansicht = s.first),
              ),
              SizedBox(
                width: 300,
                child: TextField(
                  controller: _suche,
                  decoration: const InputDecoration(
                    labelText: 'Suche (Nummer, Bezeichnung, Suchbegriff)',
                    prefixIcon: Icon(Icons.search, size: 18),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        ),
        filter,
        // Die Liste als weiße Fläche mit Spaltenkopf — wie die Listen in
        // Navision. Vorher liefen die Zeilen ohne Rahmen über die Seite.
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Material(
              color: farben.surface,
              shape: RoundedRectangleBorder(
                borderRadius: AppMasse.ecken,
                side: BorderSide(color: farben.outline),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  spaltenKopf,
                  Expanded(child: liste),
                ],
              ),
            ),
          ),
        ),
        // Die Knopfzeile unten auf der Fläche der Leisten: was gewählt ist,
        // und rechts der Knopf zum Übernehmen.
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            color: AppFarben.von(context).leiste,
            border: Border(top: BorderSide(color: farben.outline)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$neuWahl ${neuWahl == 1 ? 'neuer Artikel' : 'neue Artikel'}'
                  ' · $allergenWahl '
                  '${allergenWahl == 1 ? 'Allergenangabe' : 'Allergenangaben'}'
                  ' ausgewählt',
                  style: grau,
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: neuWahl + allergenWahl == 0 || _beschaeftigt
                    ? null
                    : _uebernehmen,
                icon: _speichert
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.done_all_rounded, size: 18),
                label: const Text('Übernehmen …'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _neuFilter(
    BuildContext context,
    ArtikelstammAbgleich a,
    List<NeuerNavisionArtikel> sichtbar,
  ) {
    final theme = Theme.of(context);
    final imAuftrag = a.neu.where((n) => n.imAuftragsbestand).length;
    final gruppen = {
      for (final n in a.neu)
        if ((n.zeile.produktgruppe ?? '').isNotEmpty) n.zeile.produktgruppe!,
    }.toList()
      ..sort();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilterChip(
            label: Text('Nur im Auftragsbestand ($imAuftrag)'),
            tooltip: 'Artikel, die im eingelesenen Auftragsbestand stehen — '
                'sie werden gebraucht und sind vorausgewählt.',
            selected: _nurAuftragsbestand,
            onSelected: (v) => setState(() => _nurAuftragsbestand = v),
          ),
          if (gruppen.isNotEmpty)
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                // Neuer Schlüssel je Einlesen: Die Auswahl gilt für eine
                // Datei, nicht darüber hinaus.
                key: ValueKey('gruppe-$_durchlauf'),
                initialValue: _produktgruppe,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Produktgruppe (Navision)',
                ),
                // Farbe ausdrücklich — ohne sie erbt der Text im hellen
                // Modus Weiß.
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurface,
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Alle')),
                  for (final g in gruppen)
                    DropdownMenuItem(
                      value: g,
                      child: Text(g, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _produktgruppe = v),
              ),
            ),
          Tooltip(
            message: 'Erkannte Allergene aus dem Suchbegriff gleich beim '
                'Anlegen speichern. Ohne: Die neuen Artikel bekommen keine '
                'Allergenangabe.',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: _allergeneMitAnlegen,
                  onChanged: (v) => setState(() => _allergeneMitAnlegen = v),
                ),
                const SizedBox(width: 4),
                const Text('Allergen-Vorschläge mitnehmen'),
              ],
            ),
          ),
          TextButton(
            onPressed: sichtbar.isEmpty
                ? null
                : () => setState(
                      () => _neuGewaehlt
                          .addAll([for (final n in sichtbar) n.nummer]),
                    ),
            child: Text('Alle ${sichtbar.length} auswählen'),
          ),
          TextButton(
            onPressed: _neuGewaehlt.isEmpty
                ? null
                : () => setState(_neuGewaehlt.clear),
            child: const Text('Auswahl aufheben'),
          ),
        ],
      ),
    );
  }

  Widget _allergenFilter(
    BuildContext context,
    List<AllergenVorschlag> sichtbar, {
    required bool ergaenzen,
  }) {
    final theme = Theme.of(context);
    final ids = [for (final v in sichtbar) v.produkt.id];
    final alleGewaehlt =
        ids.isNotEmpty && ids.every(_allergenGewaehlt.contains);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              ergaenzen
                  ? 'In der App sind hier keine Allergene gepflegt, der '
                      'Navision-Suchbegriff nennt welche. Übernommen wird '
                      'nur, was du auswählst. Was Navision nicht nennt, '
                      'fehlt auch hier — die Angabe in der Artikelmaske '
                      'prüfen.'
                  : 'In der App gepflegt, aber Navision nennt weitere '
                      'Allergene — oder die App sagt „keine". Übernehmen '
                      'ergänzt sie; was die App mehr weiß, bleibt stehen.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: sichtbar.isEmpty || alleGewaehlt
                ? null
                : () => setState(() => _allergenGewaehlt.addAll(ids)),
            child: Text('Alle ${sichtbar.length} auswählen'),
          ),
          TextButton(
            onPressed: ids.any(_allergenGewaehlt.contains)
                ? () => setState(() => _allergenGewaehlt.removeAll(ids))
                : null,
            child: const Text('Auswahl aufheben'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Bausteine
// ═══════════════════════════════════════════════════════════════════════

/// Klartext einer Allergen-Auswahl, z.B. „Eier, Milch".
String _allergenText(Set<String> werte) =>
    merkmaleLabel(merkmaleZuText(werte, kAllergene), kAllergene);

/// Spaltenbreiten der Abgleich-Listen — für Kopf und Zeilen dieselben.
abstract final class _Spalten {
  static const double auswahl = 40;
  static const double nummer = 96;
  static const double marken = 300;
}

/// Vor dem ersten Einlesen: was hier passiert, und der Knopf.
class _Einstieg extends StatelessWidget {
  const _Einstieg({required this.fehler, required this.onEinlesen});

  final String? fehler;
  final VoidCallback? onEinlesen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme.bodyMedium?.copyWith(height: 1.4);
    final meldung = fehler;

    Widget punkt(String t) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 7, right: 10),
                child: Icon(
                  Icons.circle,
                  size: 6,
                  color: theme.colorScheme.primary,
                ),
              ),
              Expanded(child: Text(t, style: text)),
            ],
          ),
        );

    // Ein Bereich mit Kopfzeile wie überall — vorher eine Karte mit
    // eigenem, größerem Titel.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: Bereich(
            titel: 'Artikelstamm aus Navision abgleichen',
            icon: Icons.swap_horiz_rounded,
            innenAbstand: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Die Artikelübersicht aus Navision (als Excel '
                  'exportiert) wird mit den Artikeln der App verglichen:',
                  style: text,
                ),
                punkt(
                  'Neue Artikel anlegen — vorausgewählt sind die, die im '
                  'Auftragsbestand stehen.',
                ),
                punkt(
                  'Allergene aus dem Suchbegriff vorschlagen, etwa „EI" '
                  '→ Eier, „LAKTOSE" → Milch, „SENFSAAT" → Senf. '
                  'Übernommen wird nur, was du auswählst.',
                ),
                punkt(
                  'Bestand und offene Aufträge kommen nicht von hier, '
                  'sondern aus dem Auftragsbestand — je Auftrag und '
                  'Versandtag.',
                ),
                if (meldung != null) ...[
                  const SizedBox(height: 14),
                  HinweisBox(
                    meldung,
                    art: StatusArt.fehler,
                    auswaehlbar: true,
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onEinlesen,
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: const Text('Artikelübersicht einlesen …'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Datei und Kennzahlen des Abgleichs.
class _Kopf extends StatelessWidget {
  const _Kopf({required this.abgleich, required this.dateiname});

  final ArtikelstammAbgleich abgleich;
  final String? dateiname;

  @override
  Widget build(BuildContext context) {
    final f = AppFarben.von(context);
    final a = abgleich;
    // Farbe nur, wo etwas zu prüfen ist.
    return Bereich(
      titel: 'Abgleich',
      untertitel: dateiname,
      child: Wrap(
        spacing: 28,
        runSpacing: 8,
        children: [
          Kennzahl(wert: '${a.gelesen}', label: 'Artikel gelesen'),
          Kennzahl(wert: '${a.neu.length}', label: 'neu'),
          Kennzahl(
            wert: '${a.ergaenzen.length}',
            label: 'Allergene fehlen',
            farbe: a.ergaenzen.isEmpty ? null : f.warnung,
          ),
          Kennzahl(
            wert: '${a.abweichend.length}',
            label: 'Abweichungen',
            farbe: a.abweichend.isEmpty ? null : f.warnung,
          ),
          Kennzahl(wert: '${a.unveraendert}', label: 'unverändert'),
        ],
      ),
    );
  }
}

/// Hinweise vom Einlesen, z.B. eine fehlende Spalte.
class _Hinweise extends StatelessWidget {
  const _Hinweise({required this.warnungen});

  final List<String> warnungen;

  @override
  Widget build(BuildContext context) {
    return HinweisBox(
      [
        ...warnungen.take(4),
        if (warnungen.length > 4) '… und ${warnungen.length - 4} weitere',
      ].join('\n'),
      art: StatusArt.warnung,
    );
  }
}

/// Spaltenköpfe einer Abgleich-Liste auf der Fläche der Leisten.
class _SpaltenKopf extends StatelessWidget {
  const _SpaltenKopf({required this.mitte, required this.rechts});

  final String mitte;
  final String rechts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stil = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 8, 14, 8),
      decoration: BoxDecoration(
        color: AppFarben.von(context).leiste,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outline),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: _Spalten.auswahl),
          SizedBox(
            width: _Spalten.nummer,
            child: Text('Nummer', style: stil),
          ),
          Expanded(child: Text(mitte, style: stil)),
          const SizedBox(width: 12),
          Text(rechts, style: stil),
        ],
      ),
    );
  }
}

/// Kleine Marke im Stil der [StatusMarke], aber mit Umbruch: Eine Liste
/// von Allergenen kann länger sein als die Spalte.
class _Marke extends StatelessWidget {
  const _Marke({required this.text, this.art = StatusArt.neutral});

  final String text;
  final StatusArt art;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = AppFarben.von(context);
    final (vorne, hinten) = switch (art) {
      StatusArt.ok => (f.ok, f.okFlaeche),
      StatusArt.warnung => (f.warnung, f.warnungFlaeche),
      StatusArt.fehler => (f.fehler, f.fehlerFlaeche),
      StatusArt.info => (f.info, f.infoFlaeche),
      StatusArt.neutral => (
          theme.colorScheme.onSurfaceVariant,
          theme.colorScheme.surfaceContainerHighest,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: hinten,
        borderRadius: AppMasse.eckenKlein,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: vorne,
        ),
      ),
    );
  }
}

/// Ein neuer Artikel aus Navision.
class _NeuZeile extends StatelessWidget {
  const _NeuZeile({
    required this.artikel,
    required this.gewaehlt,
    required this.mitAllergenen,
    required this.onChanged,
  });

  final NeuerNavisionArtikel artikel;
  final bool gewaehlt;

  /// Die Allergen-Vorschläge werden beim Anlegen mitgenommen.
  final bool mitAllergenen;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final z = artikel.zeile;
    final grau = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final angaben = [
      'Suchbegriff: ${z.suchbegriff ?? '—'}',
      if ((z.produktgruppe ?? '').isNotEmpty) 'Produktgruppe ${z.produktgruppe}',
      if ((z.basiseinheit ?? '').isNotEmpty) 'Einheit ${z.basiseinheit}',
    ].join(' · ');

    // Material statt Farbe am Container: Die Hover- und Tipp-Welle des
    // InkWell malt auf das nächste Material.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!gewaehlt),
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 2, 14, 6),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _Spalten.auswahl,
                child: Checkbox(
                  value: gewaehlt,
                  onChanged: (v) => onChanged(v ?? false),
                ),
              ),
              SizedBox(
                width: _Spalten.nummer,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    z.nummer,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        z.beschreibung.isEmpty
                            ? '(ohne Beschreibung)'
                            : z.beschreibung,
                        style: theme.textTheme.bodyMedium,
                      ),
                      if ((z.beschreibung2 ?? '').isNotEmpty)
                        Text(z.beschreibung2!, style: grau),
                      Text(angaben, style: grau),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _Spalten.marken),
                child: Padding(
                  padding: const EdgeInsets.only(top: 9),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    alignment: WrapAlignment.end,
                    children: [
                      if (artikel.imAuftragsbestand)
                        // Blau wie „vorgemerkt" im Auftragsbestand.
                        const _Marke(
                          text: 'im Auftragsbestand',
                          art: StatusArt.info,
                        ),
                      if (artikel.geloescht)
                        const _Marke(
                          text: 'früher gelöscht — wird wieder aktiviert',
                        ),
                      if (artikel.allergene.isEmpty)
                        const _Marke(text: 'keine Allergene im Suchbegriff')
                      else
                        Tooltip(
                          message: mitAllergenen
                              ? 'Wird beim Anlegen als Allergenangabe '
                                  'gespeichert.'
                              : 'Wird nicht gespeichert — „Allergen-'
                                  'Vorschläge mitnehmen" ist aus.',
                          child: _Marke(
                            text: 'Allergene: '
                                '${_allergenText(artikel.allergene)}',
                            art: mitAllergenen
                                ? StatusArt.warnung
                                : StatusArt.neutral,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ein Artikel der App mit einem Allergen-Vorschlag aus Navision.
class _AllergenZeile extends StatelessWidget {
  const _AllergenZeile({
    required this.vorschlag,
    required this.gewaehlt,
    required this.onChanged,
  });

  final AllergenVorschlag vorschlag;
  final bool gewaehlt;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = vorschlag;
    final p = v.produkt;
    final grau = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final navision = [
      if (v.zeile.beschreibung.isNotEmpty) 'Navision: ${v.zeile.beschreibung}',
      'Suchbegriff: ${v.zeile.suchbegriff ?? '—'}',
    ].join(' · ');
    final bisher = v.bisher.isEmpty
        ? 'nicht gepflegt'
        : _allergenText(v.bisher);

    // Material statt Farbe am Container: Die Hover- und Tipp-Welle des
    // InkWell malt auf das nächste Material.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!gewaehlt),
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 2, 14, 6),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _Spalten.auswahl,
                child: Checkbox(
                  value: gewaehlt,
                  onChanged: (x) => onChanged(x ?? false),
                ),
              ),
              SizedBox(
                width: _Spalten.nummer,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    p.artikelnummer,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.artikelbezeichnung,
                        style: theme.textTheme.bodyMedium,
                      ),
                      Text(navision, style: grau),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _Spalten.marken),
                child: Padding(
                  padding: const EdgeInsets.only(top: 9),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'App: $bisher',
                        textAlign: TextAlign.right,
                        style: v.widerspruch
                            ? grau?.copyWith(
                                color: AppFarben.von(context).fehler,
                                fontWeight: FontWeight.w700,
                              )
                            : grau,
                      ),
                      const SizedBox(height: 3),
                      _Marke(
                        text: '+ ${_allergenText(v.neu)}',
                        art: StatusArt.warnung,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rückfrage vor dem Schreiben.
class _BestaetigenDialog extends StatelessWidget {
  const _BestaetigenDialog({
    required this.neue,
    required this.wiederAktiviert,
    required this.neueMitAllergenen,
    required this.allergene,
  });

  final int neue;
  final int wiederAktiviert;
  final int neueMitAllergenen;
  final int allergene;

  @override
  Widget build(BuildContext context) {
    final davonAktiviert = wiederAktiviert > 0
        ? ' (davon $wiederAktiviert früher gelöschte wieder aktivieren)'
        : '';
    final mitAllergenen = neueMitAllergenen > 0
        ? ', $neueMitAllergenen mit Allergenen aus dem Suchbegriff'
        : '';
    final bestehende = allergene == 1 ? 'Artikel' : 'Artikeln';
    final punkte = [
      if (neue > 0) '$neue Artikel anlegen$davonAktiviert$mitAllergenen.',
      if (allergene > 0)
        'Bei $allergene bestehenden $bestehende die Allergene aus Navision '
            'übernehmen.',
    ];
    return AlertDialog(
      title: const Text('Übernehmen?'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final p in punkte)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('• $p'),
              ),
            if (neue > 0)
              Text(
                'Neue Artikel sind danach als „nicht eingepflegt" markiert. '
                'Prozessschritte und Stammdaten in der Artikelliste '
                'nachtragen, dann lassen sie sich einplanen.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Übernehmen'),
        ),
      ],
    );
  }
}

/// Halbtransparenter Schleier mit Ladebalken beim Einlesen.
///
/// Bewusst kein Dialog: Der Schleier sperrt die Bedienung, ohne den
/// Navigations-Stack anzufassen — scheitert das Einlesen, bleibt kein
/// offener Dialog stehen.
class _Fortschritt extends StatelessWidget {
  const _Fortschritt({required this.stand});

  final NavisionFortschritt stand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned.fill(
      child: ColoredBox(
        color: theme.colorScheme.surface.withValues(alpha: 0.85),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            // Kantig mit dünnem Rand wie jedes Fenster der App — vorher
            // eine Karte.
            child: Material(
              color: theme.colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: AppMasse.ecken,
                side: BorderSide(color: theme.colorScheme.outline),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Artikelübersicht einlesen',
                      style: theme.dialogTheme.titleTextStyle ??
                          theme.textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 18),
                    // anteil == null → unbestimmter Balken: Das Öffnen der
                    // Datei meldet keine Zwischenstände.
                    LinearProgressIndicator(
                      value: stand.anteil,
                      minHeight: 6,
                      borderRadius: AppMasse.eckenKlein,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      stand.beschriftung,
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
