// `show Value`: drift bringt eine eigene Klasse `Column` mit.
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/services/auto_backup_trigger.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/fehler_text.dart';
import '../../../core/utils/format.dart';
import '../projekte/projekt_modell.dart';
import '../projekte/projekt_repository.dart';
import 'anlagen_katalog.dart';
import 'eingabe_dialoge.dart';
import 'kette_ansicht.dart';
import 'kette_bausteine.dart';
import 'prozess_kette.dart';
import 'prozess_modell.dart';
import 'schritt_blatt.dart';

// Der Prozess eines Projekts im Reiter „Herstellung": eine Kette wie im
// Artikel — Stationen nach Abteilung, je Schritt eine Anlage aus dem
// Katalog der Planung mit ihren Werten (F32). Ohne Personen und
// Leistungsdaten, die bekommt der Artikel (F33).
//
// Der Arbeitsstand speichert sich selbst (F29). „Version festhalten" legt
// ihn mit Nummer und Notiz ab: bei den festgehaltenen Versionen und als
// Eintrag im Verlauf. Abschnitte aus der Zeit vor der Kette werden beim
// ersten Öffnen zur Kette — samt den festgehaltenen Versionen (F34).

/// Der Prozess eines Projekts — im Reiter „Herstellung".
class ProjektProzess extends ConsumerStatefulWidget {
  const ProjektProzess({super.key, required this.projekt});

  final EntwicklungsProjekt projekt;

  @override
  ConsumerState<ProjektProzess> createState() => _ProjektProzessState();
}

class _ProjektProzessState extends ConsumerState<ProjektProzess>
    with AutomaticKeepAliveClientMixin {
  late Prozessparameter _arbeit = Prozessparameter.aus(widget.projekt.prozess);

  /// Was in der Datenbank steht oder schon dorthin unterwegs ist.
  late String? _gespeichert = widget.projekt.prozess;

  /// Die festgehaltenen Versionen, wie sie hier zuletzt geschrieben wurden
  /// — bis das Projekt sie neu liefert.
  List<ProzessStand>? _historieLokal;

  /// Speichervorgänge, die noch laufen.
  int _laufend = 0;

  /// Ist das Umsetzen früherer Abschnitte schon angestoßen?
  bool _umsetzungGeplant = false;

  /// Was beim Umsetzen geschah — für den Hinweis darüber.
  ProzessUmsetzung? _umgesetzt;

  // Beim ersten Ändern geholt: Auch wenn der Reiter schließt, wird noch
  // gespeichert — dann ohne `ref`.
  ProjektRepository? _repo;
  AutoBackupTrigger? _sicherung;

  @override
  bool get wantKeepAlive => true;

  List<ProzessStand> get _historie =>
      _historieLokal ?? ProzessStand.listeAus(widget.projekt.prozessHistorie);

  @override
  void didUpdateWidget(ProjektProzess alt) {
    super.didUpdateWidget(alt);
    if (widget.projekt.prozessHistorie != alt.projekt.prozessHistorie) {
      _historieLokal = null;
    }
    final neu = widget.projekt.prozess;
    // Von woanders geändert — übernehmen, solange hier nichts aussteht.
    if (neu != alt.projekt.prozess && neu != _gespeichert && _laufend == 0) {
      _arbeit = Prozessparameter.aus(neu);
      _gespeichert = neu;
    }
  }

  void _dienste() {
    _repo ??= ref.read(projektRepositoryProvider);
    _sicherung ??= ref.read(autoBackupTriggerProvider);
  }

  /// Übernimmt [neu] und speichert ihn.
  void _setze(Prozessparameter neu) {
    _dienste();
    setState(() => _arbeit = neu);
    _sichern();
  }

  Future<void> _sichern() async {
    final json = _arbeit.alsJson();
    final repo = _repo;
    if (json == _gespeichert || repo == null) return;
    _gespeichert = json;
    _laufend++;
    try {
      await repo.projektAendern(
        widget.projekt.id,
        EntwicklungProjekteCompanion(prozess: Value(json)),
      );
      _sicherung?.fireDebounced(reason: 'Prozess');
    } catch (e) {
      if (mounted) _melde('Speichern fehlgeschlagen: ${fehlerText(e)}');
    } finally {
      _laufend--;
    }
  }

  void _melde(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ── Kette und Schritte ──────────────────────────────────────────────

  void _kette(List<ProzessSchritt> neu) => _setze(_arbeit.kopie(schritte: neu));

  void _schrittAendern(ProzessSchritt neu) =>
      _kette(ProjektKette(_arbeit.schritte).ersetzen(neu));

  void _schrittEntfernen(String id) =>
      _kette(ProjektKette(_arbeit.schritte).entfernen(id));

  void _oeffnen(
    ProzessSchritt s,
    List<KatalogAnlage> katalog,
    GrenzenKatalog grenzen,
  ) =>
      schrittOeffnen(
        context,
        schritt: s,
        nummer: ProjektKette(_arbeit.schritte).indexVon(s.id) + 1,
        katalog: katalog,
        grenzen: grenzen,
        onAenderung: _schrittAendern,
        onEntfernen: () => _schrittEntfernen(s.id),
      );

  Future<void> _ersterSchritt(List<KatalogAnlage> katalog) async {
    final neu = await neuerSchritt(context, katalog: katalog);
    if (neu == null || !mounted) return;
    _kette([..._arbeit.schritte, neu]);
  }

  /// Fragt nach, bevor eine Kette die jetzige ersetzt — ohne jetzige
  /// gleich ja.
  Future<bool> _ersetzenBestaetigt(String quelle) async {
    final n = _arbeit.schritte.length;
    if (n == 0) return true;
    final ja = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kette ersetzen?'),
        content: Text(
          'Die jetzige Kette mit ${n == 1 ? 'einem Schritt' : '$n Schritten'} '
          'wird durch die von $quelle ersetzt. Festgehaltene Versionen '
          'bleiben, wie sie sind.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Ersetzen'),
          ),
        ],
      ),
    );
    return ja == true;
  }

  Future<void> _ausArtikel() async {
    final wahl = await showDialog<ArtikelMitKette>(
      context: context,
      builder: (_) => const _ArtikelWahl(),
    );
    if (wahl == null || !mounted) return;
    final name = 'Artikel ${wahl.nummer}';
    if (!await _ersetzenBestaetigt(name) || !mounted) return;
    try {
      final katalog = ref.read(anlagenKatalogProvider).valueOrNull ??
          const <KatalogAnlage>[];
      final schritte = await ref.read(anlagenQuelleProvider).kette(
            wahl.id,
            katalog: katalog,
            neueId: neueSchrittId,
          );
      if (!mounted) return;
      if (schritte.isEmpty) {
        _melde('$name hat keine Prozesskette mehr.');
        return;
      }
      _kette(schritte);
      _melde('Kette von $name übernommen — ${_anzahl(schritte.length)}.');
    } catch (e) {
      if (mounted) _melde('Die Kette ließ sich nicht lesen: ${fehlerText(e)}');
    }
  }

  Future<void> _ausProjekt() async {
    final wahl = await showDialog<EntwicklungsProjekt>(
      context: context,
      builder: (_) => _ProjektWahl(ohne: widget.projekt.id),
    );
    if (wahl == null || !mounted) return;
    final name = '„${wahl.name}"';
    if (!await _ersetzenBestaetigt(name) || !mounted) return;
    var p = Prozessparameter.aus(wahl.prozess);
    // Hat das andere Projekt noch Abschnitte, werden sie hier zur Kette.
    if (p.abschnitte.isNotEmpty) {
      final katalog = ref.read(anlagenKatalogProvider).valueOrNull ??
          const <KatalogAnlage>[];
      p = prozessUmsetzen(p, katalog).prozess;
    }
    final schritte = mitNeuenIds(p.schritte, neueSchrittId);
    if (schritte.isEmpty) {
      _melde('$name hat keine Kette mit Inhalt.');
      return;
    }
    _kette(schritte);
    _melde('Kette von $name übernommen — ${_anzahl(schritte.length)}.');
  }

  static String _anzahl(int n) => n == 1 ? '1 Schritt' : '$n Schritte';

  // ── Frühere Abschnitte (F34) ────────────────────────────────────────

  /// Setzt frühere Abschnitte um, sobald der Katalog da ist — nach dem
  /// Bild, nicht mitten im Aufbau.
  void _umsetzenPlanen(List<KatalogAnlage> katalog) {
    if (_umsetzungGeplant) return;
    _umsetzungGeplant = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _umsetzen(katalog);
    });
  }

  Future<void> _umsetzen(List<KatalogAnlage> katalog) async {
    _umsetzungGeplant = false;
    if (_arbeit.abschnitte.isEmpty) return;
    final r = prozessUmsetzen(_arbeit, katalog);
    // Die festgehaltenen Versionen mit — so bleibt „seit Version …"
    // richtig, und Vergleiche finden dieselben Schritte.
    final historie = _historie;
    final mitAbschnitten =
        historie.any((s) => s.parameter.abschnitte.isNotEmpty);
    final neueHistorie = [
      for (final s in historie)
        s.parameter.abschnitte.isEmpty
            ? s
            : s.mitParameter(prozessUmsetzen(s.parameter, katalog).prozess),
    ];
    _dienste();
    setState(() {
      _arbeit = r.prozess;
      if (mitAbschnitten) _historieLokal = neueHistorie;
      _umgesetzt = r;
    });
    final json = r.prozess.alsJson();
    _gespeichert = json;
    _laufend++;
    try {
      await _repo!.projektAendern(
        widget.projekt.id,
        EntwicklungProjekteCompanion(
          prozess: Value(json),
          prozessHistorie: mitAbschnitten
              ? Value(ProzessStand.listeZuJson(neueHistorie))
              : const Value.absent(),
        ),
      );
      _sicherung?.fireDebounced(reason: 'Prozess');
    } catch (e) {
      if (mounted) _melde('Speichern fehlgeschlagen: ${fehlerText(e)}');
    } finally {
      _laufend--;
    }
  }

  String _umsetzungText(ProzessUmsetzung r) {
    if (r.schritte == 0) {
      return 'Die bisherigen Abschnitte waren leer und sind entfallen.';
    }
    final entfallen = switch (r.entfallen) {
      0 => '',
      1 => ', ein leerer Abschnitt ist entfallen',
      final n => ', $n leere Abschnitte sind entfallen',
    };
    return 'Die bisherigen Abschnitte sind jetzt Schritte der Kette: '
        '${_anzahl(r.schritte)}$entfallen. Prüf Abteilungen und Anlagen — '
        'was im Katalog keine Anlage fand, steht als Text da.';
  }

  // ── Versionen ───────────────────────────────────────────────────────

  /// Hält den Arbeitsstand als nächste Version fest — mit Notiz, bei den
  /// festgehaltenen Versionen und im Verlauf.
  Future<void> _festhalten() async {
    final p = widget.projekt;
    final historie = _historie;
    final version = naechsteProzessVersion(_arbeit, historie);
    final notiz = await showDialog<String>(
      context: context,
      builder: (_) => TextEingabeDialog(
        titel: 'Version $version festhalten',
        label: 'Was hat sich geändert?',
        mehrzeilig: true,
        bestaetigen: 'Festhalten',
        leerErlaubt: true,
      ),
    );
    if (notiz == null || !mounted) return;
    final repo = ref.read(projektRepositoryProvider);
    final sicherung = ref.read(autoBackupTriggerProvider);
    final jetzt = DateTime.now();
    final neu = _arbeit.kopie(version: version, stand: jetzt);
    final liste = [
      ...historie,
      ProzessStand(
        version: version,
        datum: jetzt,
        notiz: notiz.trim(),
        parameter: neu,
      ),
    ];
    setState(() {
      _arbeit = neu;
      _historieLokal = liste;
    });
    _gespeichert = neu.alsJson();
    _laufend++;
    try {
      await repo.projektAendern(
        p.id,
        EntwicklungProjekteCompanion(
          prozess: Value(neu.alsJson()),
          prozessHistorie: Value(ProzessStand.listeZuJson(liste)),
        ),
      );
      await repo.eintragAnlegen(
        projektId: p.id,
        art: EintragArt.parameter,
        titel: 'Prozessparameter $version',
        datum: DateTime(jetzt.year, jetzt.month, jetzt.day),
        beschreibung: notiz.trim().isEmpty ? null : notiz.trim(),
        status: EintragStatus.erledigt,
        wert: neu.alsJson(),
      );
      sicherung.fireDebounced(reason: 'Prozess');
      if (mounted) {
        _melde('Version $version festgehalten — sie steht im Verlauf.');
      }
    } catch (e) {
      if (mounted) _melde('Festhalten fehlgeschlagen: ${fehlerText(e)}');
    } finally {
      _laufend--;
    }
  }

  /// Setzt den Arbeitsstand auf die festgehaltene Version [s] zurück.
  Future<void> _zurueck(ProzessStand s) async {
    final ja = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Zurück zu Version ${s.version}?'),
        content: Text(
          'Was seit dem ${Format.datum(s.datum)} geändert wurde, geht '
          'verloren.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Zurücksetzen'),
          ),
        ],
      ),
    );
    if (ja != true || !mounted) return;
    _setze(s.parameter.kopie(version: s.version, stand: s.datum));
  }

  Future<void> _vergleichen() async {
    final staende = _historie;
    final fassung = prozessFassung(_arbeit, staende);
    final liste = <({String label, Prozessparameter parameter})>[
      for (final s in staende)
        (
          label: 'Version ${s.version} · ${Format.datum(s.datum)}',
          parameter: s.parameter,
        ),
      if (fassung.geaendert)
        (
          label: staende.isEmpty
              ? 'Arbeitsstand'
              : 'Arbeitsstand (seit Version ${staende.last.version})',
          parameter: _arbeit,
        ),
    ];
    if (liste.length < 2) {
      _melde('Zum Vergleichen braucht es mindestens zwei Stände.');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => ParameterVergleichDialog(staende: liste),
    );
  }

  // ── Aufbau ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final katalogStand = ref.watch(anlagenKatalogProvider);
    final katalog = katalogStand.valueOrNull ?? const <KatalogAnlage>[];
    final grenzen = ref.watch(parameterGrenzenProvider).valueOrNull ??
        const GrenzenKatalog();
    final umsetzen = _arbeit.abschnitte.isNotEmpty;
    if (umsetzen && katalogStand.hasValue) _umsetzenPlanen(katalog);

    final historie = _historie;
    final fassung = prozessFassung(_arbeit, historie);
    final letzte = historie.lastOrNull;
    final versionen = <MenueEintrag>[
      if (historie.length + (fassung.geaendert ? 1 : 0) >= 2)
        MenueEintrag(
          'Versionen vergleichen…',
          icon: Icons.compare_arrows,
          aktion: _vergleichen,
        ),
      if (letzte != null && fassung.geaendert)
        MenueEintrag(
          'Zurück zu Version ${letzte.version}…',
          icon: Icons.undo,
          aktion: () => _zurueck(letzte),
        ),
    ];
    final schritte = _arbeit.schritte;
    final fehler = katalogStand.error;
    final umgesetzt = _umgesetzt;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (schritte.isNotEmpty || historie.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                fassung.text,
                key: const ValueKey('prozess-fassung'),
                style: theme.textTheme.titleSmall,
              ),
              // Festhalten lohnt erst mit einer Kette, und nur, wenn sich
              // seit der letzten Version etwas geändert hat.
              if (fassung.geaendert && schritte.isNotEmpty)
                FilledButton.icon(
                  key: const ValueKey('prozess-festhalten'),
                  onPressed: _festhalten,
                  icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                  label: Text(
                    'Version ${naechsteProzessVersion(_arbeit, historie)} '
                    'festhalten…',
                  ),
                ),
              MenueKnopf(
                key: const ValueKey('prozess-mehr'),
                eintraege: [
                  ...versionen,
                  if (versionen.isNotEmpty) null,
                  MenueEintrag(
                    'Kette aus einem Artikel übernehmen…',
                    icon: Icons.inventory_2_outlined,
                    aktion: _ausArtikel,
                    key: const ValueKey('prozess-mehr-artikel'),
                  ),
                  MenueEintrag(
                    'Kette aus einem Projekt übernehmen…',
                    icon: Icons.content_copy_outlined,
                    aktion: _ausProjekt,
                    key: const ValueKey('prozess-mehr-projekt'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Änderungen speichern sich selbst. „Version festhalten" legt den '
            'Stand mit Nummer und Notiz im Verlauf ab; bei der Freigabe kommt '
            'die Kette in den Artikel.',
            style: theme.textTheme.bodySmall?.copyWith(color: grau),
          ),
          const SizedBox(height: 12),
        ],
        if (fehler != null) ...[
          HinweisBox(
            'Der Katalog der Anlagen ließ sich nicht laden: '
            '${fehlerText(fehler)}',
            art: StatusArt.fehler,
          ),
          const SizedBox(height: 12),
        ],
        if (umgesetzt != null) ...[
          HinweisBox(
            _umsetzungText(umgesetzt),
            key: const ValueKey('prozess-umgesetzt'),
            onSchliessen: () => setState(() => _umgesetzt = null),
          ),
          const SizedBox(height: 12),
        ],
        if (umsetzen)
          LeerHinweis(
            'Die bisherigen Abschnitte (${_arbeit.abschnitte.length}) werden '
            'zur Kette, sobald der Katalog der Anlagen geladen ist.',
            icon: Icons.account_tree_outlined,
          )
        else if (schritte.isEmpty)
          Bereich(
            titel: 'Prozesskette',
            icon: Icons.account_tree_outlined,
            innenAbstand: const EdgeInsets.fromLTRB(12, 10, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Noch keine Prozesskette. Stell sie aus den Anlagen der '
                  'Planung zusammen — Station für Station, wie im Artikel — '
                  'oder übernimm die Kette eines Artikels oder eines '
                  'anderen Projekts.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      key: const ValueKey('prozess-erste-anlage'),
                      onPressed: () => _ersterSchritt(katalog),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Anlage hinzufügen…'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('prozess-aus-artikel'),
                      onPressed: _ausArtikel,
                      icon: const Icon(Icons.inventory_2_outlined, size: 18),
                      label: const Text('Aus einem Artikel…'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('prozess-aus-projekt'),
                      onPressed: _ausProjekt,
                      icon: const Icon(Icons.content_copy_outlined, size: 18),
                      label: const Text('Aus einem Projekt…'),
                    ),
                  ],
                ),
              ],
            ),
          )
        else
          ProzessKetteAnsicht(
            schritte: schritte,
            katalog: katalog,
            katalogGeladen: katalogStand.hasValue,
            onKette: _kette,
            onOeffnen: (s) => _oeffnen(s, katalog, grenzen),
          ),
        if (historie.isNotEmpty) ...[
          const SizedBox(height: 16),
          Bereich(
            titel: 'Festgehaltene Versionen',
            icon: Icons.history,
            untertitel: '${historie.length}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final s in historie.reversed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      'Version ${s.version} · ${Format.datum(s.datum)}'
                      '${s.notiz.trim().isEmpty ? '' : ' — ${s.notiz.trim()}'}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Die Wahl eines Artikels mit Prozesskette — mit Suche nach Nummer und
/// Bezeichnung.
class _ArtikelWahl extends ConsumerStatefulWidget {
  const _ArtikelWahl();

  @override
  ConsumerState<_ArtikelWahl> createState() => _ArtikelWahlState();
}

class _ArtikelWahlState extends ConsumerState<_ArtikelWahl> {
  String _suche = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final stand = ref.watch(artikelMitKetteProvider);
    final s = _suche.trim().toLowerCase();
    final Widget liste = stand.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => LeerHinweis(
        'Die Artikel ließen sich nicht laden: ${fehlerText(e)}',
      ),
      data: (alle) {
        final treffer = [
          for (final a in alle)
            if (s.isEmpty ||
                a.nummer.toLowerCase().contains(s) ||
                a.bezeichnung.toLowerCase().contains(s))
              a,
        ];
        if (treffer.isEmpty) {
          return LeerHinweis(
            alle.isEmpty
                ? 'Noch kein Artikel hat eine Prozesskette.'
                : 'Kein Artikel passt zur Suche.',
          );
        }
        return ListView(
          children: [
            for (final a in treffer)
              ListTile(
                key: ValueKey('artikel-${a.id}'),
                dense: true,
                title: Text('${a.nummer} · ${a.bezeichnung}'),
                subtitle: Text(
                  a.schritte == 1 ? '1 Schritt' : '${a.schritte} Schritte',
                  style: TextStyle(color: grau),
                ),
                onTap: () => Navigator.of(context).pop(a),
              ),
          ],
        );
      },
    );
    return AlertDialog(
      title: const Text('Kette aus einem Artikel übernehmen'),
      content: SizedBox(
        width: 460,
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('artikel-suche'),
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Suchen',
                hintText: 'Artikelnummer oder Bezeichnung',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (t) => setState(() => _suche = t),
            ),
            const SizedBox(height: 8),
            Text(
              'Übernommen werden Abteilungen, Anlagen und Werte — ohne '
              'Personen und Leistungsdaten.',
              style: theme.textTheme.bodySmall?.copyWith(color: grau),
            ),
            const SizedBox(height: 8),
            Expanded(child: liste),
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

/// Die Wahl eines anderen Projekts, das einen Prozess hat.
class _ProjektWahl extends ConsumerStatefulWidget {
  const _ProjektWahl({required this.ohne});

  /// Das Projekt, in das übernommen wird — es steht nicht zur Wahl.
  final String ohne;

  @override
  ConsumerState<_ProjektWahl> createState() => _ProjektWahlState();
}

class _ProjektWahlState extends ConsumerState<_ProjektWahl> {
  String _suche = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final stand = ref.watch(projekteProvider);
    final s = _suche.trim().toLowerCase();
    final Widget liste = stand.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => LeerHinweis(
        'Die Projekte ließen sich nicht laden: ${fehlerText(e)}',
      ),
      data: (alle) {
        final mitProzess = [
          for (final p in alle)
            if (p.id != widget.ohne) (p, Prozessparameter.aus(p.prozess)),
        ].where((e) => e.$2.beschrieben).toList();
        final treffer = [
          for (final e in mitProzess)
            if (s.isEmpty || e.$1.name.toLowerCase().contains(s)) e,
        ];
        if (treffer.isEmpty) {
          return LeerHinweis(
            mitProzess.isEmpty
                ? 'Kein anderes Projekt hat bisher einen Prozess.'
                : 'Kein Projekt passt zur Suche.',
          );
        }
        return ListView(
          children: [
            for (final (p, prozess) in treffer)
              ListTile(
                key: ValueKey('projekt-${p.id}'),
                dense: true,
                title: Text(p.name),
                subtitle: Text(
                  prozessKurztext(prozess),
                  style: TextStyle(color: grau),
                ),
                onTap: () => Navigator.of(context).pop(p),
              ),
          ],
        );
      },
    );
    return AlertDialog(
      title: const Text('Kette aus einem Projekt übernehmen'),
      content: SizedBox(
        width: 460,
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('projekt-suche'),
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Suchen',
                hintText: 'Name des Projekts',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (t) => setState(() => _suche = t),
            ),
            const SizedBox(height: 8),
            Expanded(child: liste),
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

/// Zwei Stände des Prozesses nebeneinander: was sich geändert hat.
class ParameterVergleichDialog extends StatefulWidget {
  const ParameterVergleichDialog({super.key, required this.staende});

  /// Älteste zuerst.
  final List<({String label, Prozessparameter parameter})> staende;

  @override
  State<ParameterVergleichDialog> createState() =>
      _ParameterVergleichDialogState();
}

class _ParameterVergleichDialogState extends State<ParameterVergleichDialog> {
  late int _a = widget.staende.length - 2;
  late int _b = widget.staende.length - 1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final liste = widget.staende;
    final aenderungen = vergleicheParameter(
      liste[_a].parameter,
      liste[_b].parameter,
    );
    String zeigen(String? w) => w == null || w.trim().isEmpty ? '—' : w;
    DropdownButton<int> wahl(int wert, ValueChanged<int> onWahl) =>
        DropdownButton<int>(
          value: wert,
          isExpanded: true,
          items: [
            for (final (i, s) in liste.indexed)
              DropdownMenuItem(
                value: i,
                child: Text(s.label, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (i) {
            if (i != null) setState(() => onWahl(i));
          },
        );
    return AlertDialog(
      title: const Text('Versionen vergleichen'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, minWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: wahl(_a, (i) => _a = i)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward, size: 18),
                ),
                Expanded(child: wahl(_b, (i) => _b = i)),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: aenderungen.isEmpty
                  ? const LeerHinweis('Keine Unterschiede.')
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final a in aenderungen)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${a.abschnitt} · ${a.feld}',
                                  style: theme.textTheme.labelMedium,
                                ),
                                Text(
                                  '${zeigen(a.alt)}  →  ${zeigen(a.neu)}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Schließen'),
        ),
      ],
    );
  }
}
