import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart' show AppDatabase;
import '../../core/providers/database_provider.dart';
import '../../core/services/auftragsbestand_deckung.dart'
    show teileBezuegeZu;
import '../../core/services/auto_backup_trigger.dart';
import '../../core/theme/app_stil.dart';
import '../../core/ui/bausteine.dart';
import '../../core/utils/zeit.dart';
import '../bedarf/bedarf_screen.dart' show bedarfProvider;
import '../datenblatt/datenblatt.dart';
import '../whiteboard/whiteboard_provider.dart' show dailyTasksProvider;
import 'planungsvorschlag_service.dart';

/// Vorschlagsansicht: fragt zuerst, welche offenen Bedarfe hinein sollen,
/// zeigt dann, wie die nächsten Tage aussehen könnten, und überträgt
/// einzelne Tage ins Board.
///
/// Die Auswahl ist der Handlungsspielraum des Planers: Was noch nicht
/// dran ist oder wegen der Haltbarkeit nicht mit anderem gebündelt werden
/// soll, bleibt draußen. Was einen festen Tag braucht, steht schon im
/// Board — der Vorschlag plant nur drumherum.
///
/// Der Vorschlag ist ein **Entwurf**. Mengen lassen sich ändern, die
/// Reihenfolge umstellen, Posten entfernen oder auf einen Nachbartag
/// schieben — alles nur in der Ansicht. Erst „Tag ins Board übernehmen"
/// schreibt etwas. Nach jeder Änderung rechnet [Planungsrechner] die
/// Nebenzeiten neu, sodass sofort sichtbar ist, was eine Umstellung
/// kostet oder spart.
class PlanungsvorschlagScreen extends ConsumerStatefulWidget {
  const PlanungsvorschlagScreen({super.key});

  @override
  ConsumerState<PlanungsvorschlagScreen> createState() =>
      _PlanungsvorschlagScreenState();
}

class _PlanungsvorschlagScreenState
    extends ConsumerState<PlanungsvorschlagScreen> {
  VorschlagEinstellungen _einstellungen = const VorschlagEinstellungen();

  bool _laedt = true;
  Object? _fehler;

  /// Die offenen Bedarfe zur Auswahl.
  List<OffenerBedarf> _bedarfe = const [];

  /// Angehakte Bedarfe — sie kommen in den Vorschlag.
  final Set<String> _auswahl = <String>{};

  /// Schon einmal angezeigte Bedarfe. Nach dem Neuladen behalten sie ihren
  /// Haken; nur neu hinzugekommene bekommen die Vorauswahl.
  final Set<String> _bekannt = <String>{};

  /// Auswahl aufgeklappt. Nach dem Rechnen klappt sie zu einer Zeile
  /// zusammen.
  bool _auswahlOffen = true;

  /// Es gibt einen berechneten Vorschlag.
  bool _berechnet = false;

  /// Die Einstellungen, mit denen er gerechnet wurde. Wer danach „möglichst
  /// früh" anklickt, sieht im Kopf weiter, wie der angezeigte Vorschlag
  /// entstanden ist — bis neu gerechnet wird.
  VorschlagEinstellungen? _berechnetMit;

  List<VorschlagTag> _tage = [];
  List<NichtPlanbar> _nichtPlanbar = [];

  /// Tage, die in dieser Sitzung schon übernommen wurden.
  final Set<String> _uebernommen = <String>{};

  /// Tage, deren Reihenfolge von Hand geändert wurde.
  final Set<String> _manuell = <String>{};

  bool _geaendert = false;

  @override
  void initState() {
    super.initState();
    _ladeBedarfe();
  }

  /// Lädt die offenen Bedarfe. Liefert false bei einem Fehler.
  Future<bool> _ladeBedarfe() async {
    setState(() {
      _laedt = true;
      _fehler = null;
    });
    try {
      final db = ref.read(databaseProvider);
      final bedarfe = await PlanungsvorschlagService(db).ladeOffeneBedarfe();
      if (!mounted) return false;
      final vor = vorauswahl(bedarfe, vorschlagsTage(_einstellungen));
      setState(() {
        final neu = <String>{
          for (final b in bedarfe)
            if (_bekannt.contains(b.bedarfId)
                ? _auswahl.contains(b.bedarfId)
                : vor.contains(b.bedarfId))
              b.bedarfId,
        };
        _bedarfe = bedarfe;
        _auswahl
          ..clear()
          ..addAll(neu);
        _bekannt.addAll([for (final b in bedarfe) b.bedarfId]);
        if (bedarfe.isEmpty) {
          _berechnet = false;
          _tage = [];
          _nichtPlanbar = [];
        }
        _laedt = false;
      });
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() {
        _fehler = e;
        _laedt = false;
      });
      return false;
    }
  }

  Future<void> _rechne() async {
    setState(() {
      _laedt = true;
      _fehler = null;
    });
    try {
      final db = ref.read(databaseProvider);
      final v = await PlanungsvorschlagService(db).berechne(
        _einstellungen.kopieMit(bedarfIds: {..._auswahl}),
      );
      if (!mounted) return;
      setState(() {
        _tage = [...v.tage];
        _nichtPlanbar = [...v.nichtPlanbar];
        _berechnetMit = v.einstellungen;
        _uebernommen.clear();
        _manuell.clear();
        _geaendert = false;
        _berechnet = true;
        _auswahlOffen = false;
        _laedt = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fehler = e;
        _laedt = false;
      });
    }
  }

  // ── Bearbeiten ───────────────────────────────────────────────────────

  void _ersetzeTag(int index, VorschlagTag neu) {
    setState(() {
      _tage[index] = neu;
      _geaendert = true;
    });
  }

  void _sortiereNeu(int tagIndex, int von, int nach) {
    final t = _tage[tagIndex];
    final posten = [...t.posten];
    // `onReorder` liefert den Zielindex VOR dem Entfernen des Elements —
    // beim Verschieben nach unten muss deshalb um eins zurückgezählt
    // werden. Das neuere `onReorderItem` täte das selbst, fehlt aber in
    // der Flutter-Version der CI; deshalb bleibt es bei onReorder.
    if (nach > von) nach -= 1;
    posten.insert(nach, posten.removeAt(von));
    _manuell.add(_key(t.tag));
    _ersetzeTag(
      tagIndex,
      t.kopieMit(
        posten: Planungsrechner.mitNebenzeiten(posten, _einstellungen),
      ),
    );
  }

  void _nachRegeln(int tagIndex) {
    final t = _tage[tagIndex];
    _manuell.remove(_key(t.tag));
    _ersetzeTag(
      tagIndex,
      t.kopieMit(
        posten: Planungsrechner.mitNebenzeiten(
          Planungsrechner.nachRegeln(t.posten),
          _einstellungen,
        ),
      ),
    );
  }

  void _entferne(int tagIndex, VorschlagPosten p) {
    final t = _tage[tagIndex];
    final posten = [...t.posten]..remove(p);
    _ersetzeTag(
      tagIndex,
      t.kopieMit(
        posten: Planungsrechner.mitNebenzeiten(posten, _einstellungen),
      ),
    );
    setState(() {
      _nichtPlanbar = [
        ..._nichtPlanbar,
        NichtPlanbar(
          artikelnummer: p.artikelnummer,
          bezeichnung: p.bezeichnung,
          mengeKg: p.mengeKg,
          grund: 'Von Hand aus dem Vorschlag genommen',
        ),
      ];
    });
  }

  /// Posten auf den Nachbartag schieben — den vorigen oder nächsten
  /// Arbeitstag des Zeitraums. Liegt der nach dem Termin, zeigt die Zeile
  /// das rot an.
  void _verschiebe(int tagIndex, VorschlagPosten p, int richtung) {
    final ziel = tagIndex + richtung;
    if (ziel < 0 || ziel >= _tage.length) return;

    final von = _tage[tagIndex];
    final nach = _tage[ziel];
    final vonPosten = [...von.posten]..remove(p);
    final nachPosten = Planungsrechner.nachRegeln([...nach.posten, p]);

    setState(() {
      _tage[tagIndex] = von.kopieMit(
        posten: Planungsrechner.mitNebenzeiten(vonPosten, _einstellungen),
      );
      _tage[ziel] = nach.kopieMit(
        posten: Planungsrechner.mitNebenzeiten(nachPosten, _einstellungen),
      );
      _manuell.remove(_key(nach.tag));
      _geaendert = true;
    });
  }

  Future<void> _aendereMenge(int tagIndex, VorschlagPosten p) async {
    final neu = await showDialog<double>(
      context: context,
      builder: (_) => _MengeDialog(posten: p),
    );
    if (neu == null || neu <= 0) return;
    final t = _tage[tagIndex];
    final posten = [
      for (final x in t.posten)
        if (identical(x, p)) p.mitMenge(neu) else x,
    ];
    _ersetzeTag(
      tagIndex,
      t.kopieMit(
        posten: Planungsrechner.mitNebenzeiten(posten, _einstellungen),
      ),
    );
  }

  Future<void> _uebernehmen(int tagIndex) async {
    final t = _tage[tagIndex];
    // Vor der ersten Wartestelle geholt: Der Container überlebt auch, wenn
    // jemand die Ansicht währenddessen schließt — Bedarfsliste und Board
    // müssen trotzdem neu laden.
    final container = ProviderScope.containerOf(context, listen: false);
    final db = ref.read(databaseProvider);
    final messenger = ScaffoldMessenger.of(context);
    final fehlerFarbe = AppFarben.von(context).fehler;
    try {
      final anzahl = await PlanungsvorschlagService(db).uebernehmeTag(t);
      container.invalidate(bedarfProvider);
      container.invalidate(dailyTasksProvider);
      container
          .read(autoBackupTriggerProvider)
          .fireDebounced(reason: 'Planungsvorschlag übernommen');
      if (!mounted) return;
      setState(() => _uebernommen.add(_key(t.tag)));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '$anzahl ${anzahl == 1 ? 'Auftrag' : 'Aufträge'} ins Board '
            'übernommen.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Fehler: $e'), backgroundColor: fehlerFarbe),
      );
    }
  }

  // ── Datenblatt ───────────────────────────────────────────────────────

  /// Datenblatt eines Postens: Artikel, Menge und Tag so, wie der
  /// Vorschlag ihn einplant — mit den Aufträgen, die seine Menge bedient.
  /// Genau diese Zeilen bekommt die Kette beim Übernehmen.
  Future<Datenblatt?> _blatt(
    AppDatabase db,
    VorschlagTag t,
    VorschlagPosten p,
  ) {
    final termin = p.termin;
    final status = [
      if (_uebernommen.contains(_key(t.tag)))
        'Aus dem Planungsvorschlag ins Board übernommen'
      else
        'Planungsvorschlag — noch nicht ins Board übernommen',
      if (termin != null) 'Termin spätestens ${_tagKurz(termin)}',
    ].join(' · ');
    return datenblattFuerMenge(
      db,
      productId: p.productId,
      fertigKg: p.mengeKg,
      tag: t.tag,
      bezuege: teileBezuegeZu(p.auftragsBezuege, p.mengeKg),
      status: status,
      notiz: _notiz(p),
    );
  }

  /// Die Notiz des Bedarfs — nicht bei einem Planungsauftrag aus dem
  /// Auftragsbestand, dessen Notiz nur die Aufträge aufzählt.
  String? _notiz(VorschlagPosten p) {
    for (final b in _bedarfe) {
      if (b.bedarfId != p.bedarfId) continue;
      if (b.ausAuftragsbestand) return null;
      final n = b.notizen?.trim();
      return (n == null || n.isEmpty) ? null : n;
    }
    return null;
  }

  Future<void> _datenblatt(int tagIndex, VorschlagPosten p) {
    final db = ref.read(databaseProvider);
    final t = _tage[tagIndex];
    return druckeDatenblaetterMitMeldung(
      ScaffoldMessenger.of(context),
      () => alsListe(_blatt(db, t, p)),
    );
  }

  /// Alle Datenblätter eines Tages in einem Druck — ein Blatt je Posten,
  /// in der Reihenfolge des Tages.
  Future<void> _datenblaetter(int tagIndex) {
    final db = ref.read(databaseProvider);
    final t = _tage[tagIndex];
    return druckeDatenblaetterMitMeldung(
      ScaffoldMessenger.of(context),
      () async {
        final blaetter = <Datenblatt>[];
        for (final p in t.posten) {
          final b = await _blatt(db, t, p);
          if (b != null) blaetter.add(b);
        }
        return blaetter;
      },
    );
  }

  // ── Auswahl ──────────────────────────────────────────────────────────

  void _waehle(String bedarfId, bool an) {
    setState(() {
      if (an) {
        _auswahl.add(bedarfId);
      } else {
        _auswahl.remove(bedarfId);
      }
    });
  }

  void _setzeAuswahl(Set<String> ids) {
    setState(() {
      _auswahl
        ..clear()
        ..addAll(ids);
    });
  }

  Future<void> _berechneAusAuswahl() async {
    if (_berechnet && !await _verwerfenOk()) return;
    if (!mounted) return;
    await _rechne();
  }

  // ── Aufbau ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final tage = vorschlagsTage(_einstellungen);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Planungsvorschlag'),
        actions: [
          IconButton(
            onPressed: _oeffneEinstellungen,
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Zeiten und Zeitraum',
          ),
          IconButton(
            onPressed: _laedt ? null : _neuLaden,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Bedarfe neu laden und neu berechnen',
          ),
          const SizedBox(width: 8),
        ],
      ),
      // Grauer Grund wie auf den übrigen Seiten, die Bereiche weiß darauf.
      // Vorher war die Seite selbst weiß und die Karten hoben sich kaum ab.
      body: _laedt
          ? const Center(child: CircularProgressIndicator())
          : _fehler != null
              ? ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    HinweisBox(
                      'Fehler: $_fehler',
                      art: StatusArt.fehler,
                      auswaehlbar: true,
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 40),
                  children: [
                    if (_bedarfe.isEmpty)
                      const _LeerKarte(
                        text: 'Kein offener Bedarf. Bedarfe entstehen in der '
                            'Bedarfsliste oder im Auftragsbestand über „Zur '
                            'Planung hinzufügen".',
                      )
                    else
                      _AuswahlKarte(
                        bedarfe: _bedarfe,
                        auswahl: _auswahl,
                        tage: tage,
                        offen: _auswahlOffen || !_berechnet,
                        berechnet: _berechnet,
                        moeglichstSpaet: _einstellungen.moeglichstSpaet,
                        onWaehle: _waehle,
                        onSetze: _setzeAuswahl,
                        onSpaet: (v) => setState(
                          () => _einstellungen =
                              _einstellungen.kopieMit(moeglichstSpaet: v),
                        ),
                        onAufklappen: () =>
                            setState(() => _auswahlOffen = true),
                        onZuklappen: () =>
                            setState(() => _auswahlOffen = false),
                        onBerechnen: _berechneAusAuswahl,
                      ),
                    if (_berechnet && _bedarfe.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _Kopfzeile(
                        tage: _tage,
                        einstellungen: _berechnetMit ?? _einstellungen,
                        geaendert: _geaendert,
                      ),
                      const SizedBox(height: 14),
                      if (_tage.every((t) => t.posten.isEmpty))
                        _LeerKarte(
                          text: _nichtPlanbar.isNotEmpty
                              ? 'Aus der Auswahl lässt sich gerade nichts '
                                  'einplanen. Die Liste unten nennt zu jedem '
                                  'Artikel den Grund.'
                              : 'Nichts einzuplanen.',
                        ),
                      for (var i = 0; i < _tage.length; i++)
                        if (_tage[i].posten.isNotEmpty)
                          _TagKarte(
                            tag: _tage[i],
                            manuellSortiert:
                                _manuell.contains(_key(_tage[i].tag)),
                            uebernommen:
                                _uebernommen.contains(_key(_tage[i].tag)),
                            kannZurueck: i > 0,
                            kannVor: i < _tage.length - 1,
                            onReorder: (von, nach) =>
                                _sortiereNeu(i, von, nach),
                            onNachRegeln: () => _nachRegeln(i),
                            onMenge: (p) => _aendereMenge(i, p),
                            onEntfernen: (p) => _entferne(i, p),
                            onVerschieben: (p, richtung) =>
                                _verschiebe(i, p, richtung),
                            onUebernehmen: () => _uebernehmen(i),
                            onDatenblatt: (p) => _datenblatt(i, p),
                            onDatenblaetter: () => _datenblaetter(i),
                          ),
                      if (_nichtPlanbar.isNotEmpty)
                        _NichtPlanbarKarte(eintraege: _nichtPlanbar),
                    ],
                  ],
                ),
    );
  }

  /// Nachfrage, bevor handgemachte Änderungen am Vorschlag verloren gehen.
  Future<bool> _verwerfenOk() async {
    if (!_geaendert) return true;
    final weiter = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Änderungen verwerfen?'),
        content: const Text(
          'Der Vorschlag wurde von Hand angepasst. Neu berechnen setzt '
          'Mengen und Reihenfolgen zurück.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Neu berechnen'),
          ),
        ],
      ),
    );
    return weiter ?? false;
  }

  /// Bedarfe neu laden — nach Änderungen in der Bedarfsliste, im
  /// Auftragsbestand oder im Board — und, wenn schon gerechnet war, neu
  /// rechnen.
  Future<void> _neuLaden() async {
    if (_berechnet && !await _verwerfenOk()) return;
    if (!mounted) return;
    final ok = await _ladeBedarfe();
    if (!mounted) return;
    if (ok && _berechnet && _bedarfe.isNotEmpty) await _rechne();
  }

  Future<void> _oeffneEinstellungen() async {
    // Mittiges Fenster statt Bottom-Sheet: Am Desktop klebt ein Sheet am
    // unteren Fensterrand und wird dort abgeschnitten.
    final neu = await showDialog<VorschlagEinstellungen>(
      context: context,
      builder: (_) => _EinstellungenDialog(start: _einstellungen),
    );
    if (neu == null || !mounted) return;
    if (_berechnet && !await _verwerfenOk()) return;
    if (!mounted) return;
    setState(() => _einstellungen = neu);
    if (_berechnet) await _rechne();
  }

  static String _key(DateTime d) => '${d.year}-${d.month}-${d.day}';
}

// ═══════════════════════════════════════════════════════════════════════
// Auswahl
// ═══════════════════════════════════════════════════════════════════════

/// Spaltenbreiten der Auswahl — für Kopf und Zeilen dieselben.
abstract final class _Auswahl {
  static const double haken = 40;
  static const double nummer = 78;
  static const double menge = 80;
  static const double termin = 170;
  static const double herkunft = 130;
  static const double prio = 28;

  /// Abstand zwischen zwei Spalten.
  static const double luecke = 12;

  /// Ab dieser Breite ist Platz für die Herkunft.
  static const double breitAb = 760;
}

/// Welche offenen Bedarfe in den Vorschlag kommen — und wie geplant wird.
class _AuswahlKarte extends StatelessWidget {
  const _AuswahlKarte({
    required this.bedarfe,
    required this.auswahl,
    required this.tage,
    required this.offen,
    required this.berechnet,
    required this.moeglichstSpaet,
    required this.onWaehle,
    required this.onSetze,
    required this.onSpaet,
    required this.onAufklappen,
    required this.onZuklappen,
    required this.onBerechnen,
  });

  final List<OffenerBedarf> bedarfe;
  final Set<String> auswahl;

  /// Arbeitstage des Zeitraums.
  final List<DateTime> tage;
  final bool offen;
  final bool berechnet;
  final bool moeglichstSpaet;
  final void Function(String bedarfId, bool an) onWaehle;
  final void Function(Set<String> ids) onSetze;
  final ValueChanged<bool> onSpaet;
  final VoidCallback onAufklappen;
  final VoidCallback onZuklappen;
  final VoidCallback onBerechnen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final farben = theme.colorScheme;
    final grau = theme.textTheme.bodySmall?.copyWith(
      color: farben.onSurfaceVariant,
    );
    final gewaehlt = [
      for (final b in bedarfe)
        if (auswahl.contains(b.bedarfId)) b,
    ];
    final kg = gewaehlt.fold<double>(0, (s, b) => s + b.offenKg);

    if (!offen) {
      // Zugeklappt: eine Zeile mit Rahmen — wie der Kopf eines Bereichs.
      return Material(
        color: farben.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppMasse.ecken,
          side: BorderSide(color: farben.outline),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppMasse.kopfHoehe),
          child: Padding(
            padding: const EdgeInsets.only(left: 12, right: 6),
            child: Row(
              children: [
                Icon(
                  Icons.checklist_rounded,
                  size: 16,
                  color: farben.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${gewaehlt.length} von ${bedarfe.length} offenen '
                    'Bedarfen im Vorschlag',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                TextButton(
                  onPressed: onAufklappen,
                  child: const Text('Auswahl ändern'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final faellig = vorauswahl(bedarfe, tage);
    final letzter = tage.isEmpty ? null : tage.last;
    final bis = letzter == null ? 'im Zeitraum' : 'bis ${_tagKurz(letzter)}';

    return Bereich(
      titel: 'Was soll eingeplant werden?',
      icon: Icons.checklist_rounded,
      untertitel: '${bedarfe.length} offene '
          '${bedarfe.length == 1 ? 'Bedarf' : 'Bedarfe'}',
      aktionen: [
        if (berechnet)
          IconButton(
            onPressed: onZuklappen,
            icon: const Icon(Icons.expand_less, size: 20),
            tooltip: 'Zuklappen',
            visualDensity: VisualDensity.compact,
          ),
      ],
      innenAbstand: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final breit = constraints.maxWidth >= _Auswahl.breitAb;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
                child: Text(
                  'Vorausgewählt ist, was $bis fällig ist, und alles ohne '
                  'Termin. Was noch nicht dran ist oder wegen der '
                  'Haltbarkeit nicht mitgebündelt werden soll, einfach '
                  'abhaken. Nach dem Termin plant der Vorschlag nie — passt '
                  'es vorher nicht mehr, steht es unten in der Restliste.',
                  style: grau,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                child: Wrap(
                  spacing: 4,
                  children: [
                    TextButton(
                      onPressed: () => onSetze(faellig),
                      child: Text('Vorauswahl (${faellig.length})'),
                    ),
                    TextButton(
                      onPressed: () =>
                          onSetze({for (final b in bedarfe) b.bedarfId}),
                      child: Text('Alle (${bedarfe.length})'),
                    ),
                    TextButton(
                      onPressed: () => onSetze(<String>{}),
                      child: const Text('Keine'),
                    ),
                  ],
                ),
              ),
              _AuswahlKopf(breit: breit),
              for (final b in bedarfe)
                _AuswahlZeile(
                  bedarf: b,
                  gewaehlt: auswahl.contains(b.bedarfId),
                  tage: tage,
                  breit: breit,
                  onChanged: (v) => onWaehle(b.bedarfId, v),
                ),
              // Unten wie eine Aktionsleiste: wie geplant wird, was
              // gewählt ist, und der Knopf.
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                color: AppFarben.von(context).leiste,
                child: Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: true,
                          label: Text('Möglichst spät'),
                          tooltip: 'Nah am Termin: frische Ware, wenig Lager',
                        ),
                        ButtonSegment(
                          value: false,
                          label: Text('Möglichst früh'),
                          tooltip: 'Früh produzieren, hinten bleibt Luft',
                        ),
                      ],
                      selected: {moeglichstSpaet},
                      onSelectionChanged: (s) => onSpaet(s.first),
                      showSelectedIcon: false,
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${gewaehlt.length} gewählt · ${kg.round()} kg',
                          style: grau,
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: gewaehlt.isEmpty ? null : onBerechnen,
                          icon: const Icon(
                            Icons.auto_awesome_rounded,
                            size: 18,
                          ),
                          label: Text(
                            berechnet
                                ? 'Neu berechnen'
                                : 'Vorschlag berechnen',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Spaltenköpfe der Auswahl auf der Fläche der Leisten.
class _AuswahlKopf extends StatelessWidget {
  const _AuswahlKopf({required this.breit});

  /// Breit genug für die Herkunft.
  final bool breit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stil = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(4 + _Auswahl.haken, 7, 12, 7),
      decoration: BoxDecoration(
        color: AppFarben.von(context).leiste,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outline),
          bottom: BorderSide(color: theme.colorScheme.outline),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _Auswahl.nummer,
            child: Text('Nr.', style: stil),
          ),
          Expanded(child: Text('Artikel', style: stil)),
          const SizedBox(width: _Auswahl.luecke),
          SizedBox(
            width: _Auswahl.menge,
            child: Text('offen', textAlign: TextAlign.right, style: stil),
          ),
          const SizedBox(width: _Auswahl.luecke + 4),
          SizedBox(
            width: _Auswahl.termin,
            child: Text('Termin', style: stil),
          ),
          if (breit)
            SizedBox(
              width: _Auswahl.herkunft,
              child: Text('Herkunft', style: stil),
            ),
          const SizedBox(width: _Auswahl.prio),
        ],
      ),
    );
  }
}

/// Ein offener Bedarf in der Auswahl — eine Zeile der Tabelle. Ein Klick
/// irgendwo in der Zeile setzt oder entfernt den Haken.
class _AuswahlZeile extends StatelessWidget {
  const _AuswahlZeile({
    required this.bedarf,
    required this.gewaehlt,
    required this.tage,
    required this.breit,
    required this.onChanged,
  });

  final OffenerBedarf bedarf;
  final bool gewaehlt;
  final List<DateTime> tage;

  /// Breit genug für die Herkunft.
  final bool breit;
  final ValueChanged<bool> onChanged;

  static const _quellen = {
    'bestellung': 'Bestellung',
    'bestand': 'Bestand',
    'sonstiges': 'Sonstiges',
    'auftragsbestand': 'Auftragsbestand',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final farben = theme.colorScheme;
    final b = bedarf;
    final stil = theme.textTheme.bodyMedium;
    final zahlen = stil?.copyWith(fontFeatures: _ziffern);
    final grau = theme.textTheme.bodySmall?.copyWith(
      color: farben.onSurfaceVariant,
    );

    // Der Termin als Text — überschritten als rote Marke.
    final termin = b.termin;
    final Widget terminAnzeige;
    if (termin == null) {
      terminAnzeige = Text(
        'ohne Termin',
        style: stil?.copyWith(color: farben.onSurfaceVariant),
      );
    } else if (tage.isNotEmpty && _tagVon(termin).isBefore(tage.first)) {
      terminAnzeige = StatusMarke(
        'überfällig · ${_tagKurz(termin)}',
        art: StatusArt.fehler,
        hinweis: 'Termin ${_tagKurz(termin)} überschritten',
      );
    } else if (tage.isNotEmpty && _tagVon(termin).isAfter(tage.last)) {
      terminAnzeige = Text(
        'fällig erst ${_tagKurz(termin)}',
        style: zahlen?.copyWith(color: farben.onSurfaceVariant),
      );
    } else {
      terminAnzeige = Text('spätestens ${_tagKurz(termin)}', style: zahlen);
    }
    final notiz = b.notizen?.trim() ?? '';

    // Material statt Farbe am Container: Die Hover- und Tipp-Welle des
    // InkWell malt auf das nächste Material.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!gewaehlt),
        child: Container(
          constraints: const BoxConstraints(minHeight: 38),
          padding: const EdgeInsets.fromLTRB(4, 3, 12, 3),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: farben.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: _Auswahl.haken,
                child: Checkbox(
                  value: gewaehlt,
                  onChanged: (v) => onChanged(v ?? false),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              SizedBox(
                width: _Auswahl.nummer,
                child: Text(
                  b.artikelnummer,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: zahlen?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      b.bezeichnung,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: stil,
                    ),
                    if (notiz.isNotEmpty)
                      Text(
                        notiz,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: grau,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: _Auswahl.luecke),
              SizedBox(
                width: _Auswahl.menge,
                child: Text(
                  '${b.offenKg.round()} kg',
                  maxLines: 1,
                  textAlign: TextAlign.right,
                  style: zahlen,
                ),
              ),
              const SizedBox(width: _Auswahl.luecke + 4),
              SizedBox(
                width: _Auswahl.termin,
                child: Align(
                  alignment: Alignment.centerLeft,
                  heightFactor: 1,
                  child: terminAnzeige,
                ),
              ),
              if (breit)
                SizedBox(
                  width: _Auswahl.herkunft,
                  child: Text(
                    _quellen[b.quelle] ?? b.quelle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: grau,
                  ),
                ),
              SizedBox(
                width: _Auswahl.prio,
                child: b.prioritaet > 0
                    ? Tooltip(
                        message: 'Hohe Priorität',
                        child: Icon(
                          Icons.priority_high,
                          size: 18,
                          color: AppFarben.von(context).fehler,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Kopf
// ═══════════════════════════════════════════════════════════════════════

/// Die Zusammenfassung des Vorschlags: wie viel, nach welchen Regeln und
/// mit welchen Zeiten gerechnet.
class _Kopfzeile extends StatelessWidget {
  const _Kopfzeile({
    required this.tage,
    required this.einstellungen,
    required this.geaendert,
  });

  final List<VorschlagTag> tage;
  final VorschlagEinstellungen einstellungen;
  final bool geaendert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final farben = theme.colorScheme;
    final farbe = _bratFarbe(theme);
    final posten = tage.fold<int>(0, (s, t) => s + t.posten.length);
    final tageMitInhalt = tage.where((t) => t.posten.isNotEmpty).length;
    final rohware = tage.fold<double>(0, (s, t) => s + t.rohwareKg);
    final e = einstellungen;
    final wann =
        e.moeglichstSpaet ? 'So spät wie möglich' : 'So früh wie möglich';

    // Weiße Fläche mit Rand wie jeder Bereich, links eine Kante in der
    // Farbe der Bratstraße — für sie plant der Vorschlag. Vorher ein
    // Farbverlauf. Ohne Rundung: Eine Kante auf nur einer Seite lässt
    // sich nicht runden.
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: farben.surface,
        border: Border(
          left: BorderSide(color: farbe, width: 3),
          top: BorderSide(color: farben.outline),
          right: BorderSide(color: farben.outline),
          bottom: BorderSide(color: farben.outline),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 18, color: farbe),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$posten ${posten == 1 ? 'Auftrag' : 'Aufträge'} · '
                  '$tageMitInhalt ${tageMitInhalt == 1 ? 'Tag' : 'Tage'} · '
                  '${rohware.round()} kg Rohware',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: _ziffern,
                  ),
                ),
              ),
              if (geaendert)
                const StatusMarke(
                  'angepasst',
                  art: StatusArt.info,
                  hinweis: 'Von Hand geändert. Ins Board kommt erst etwas '
                      'mit „Tag ins Board übernehmen".',
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$wann, nie nach dem Termin · Allergene aufsteigend · Bio vor '
            'konventionell · roh nach gegart · dann ähnliche '
            'Bratstraßen-Einstellungen',
            style: theme.textTheme.bodySmall?.copyWith(
              color: farben.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              StatusMarke(
                e.moeglichstSpaet ? 'möglichst spät' : 'möglichst früh',
                art: StatusArt.info,
              ),
              StatusMarke('Rüsten ${e.ruestenMinuten.round()} min'),
              StatusMarke(
                'Reinigen ${e.zwischenreinigungMinuten.round()} min',
              ),
              StatusMarke(
                'Endreinigung ${e.endreinigungMinuten.round()} min',
              ),
              StatusMarke('${e.maxArbeitstage} Arbeitstage'),
              if (e.planeSamstag) const StatusMarke('inkl. Samstag'),
              if (e.gesperrteTage.isNotEmpty)
                StatusMarke(
                  '${e.gesperrteTage.length} gesperrt',
                  art: StatusArt.warnung,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Hinweis, wenn es nichts einzuplanen gibt — auf einer Fläche wie ein
/// Bereich.
class _LeerKarte extends StatelessWidget {
  const _LeerKarte({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: farben.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppMasse.ecken,
          side: BorderSide(color: farben.outline),
        ),
        child: LeerHinweis(text, icon: Icons.inbox_outlined),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Tageskarte
// ═══════════════════════════════════════════════════════════════════════

/// Ein Tag des Vorschlags: Kopf mit Auslastung, darunter die Posten zum
/// Umsortieren, unten Hinweise und die Aktionen.
class _TagKarte extends StatelessWidget {
  const _TagKarte({
    required this.tag,
    required this.manuellSortiert,
    required this.uebernommen,
    required this.kannZurueck,
    required this.kannVor,
    required this.onReorder,
    required this.onNachRegeln,
    required this.onMenge,
    required this.onEntfernen,
    required this.onVerschieben,
    required this.onUebernehmen,
    required this.onDatenblatt,
    required this.onDatenblaetter,
  });

  final VorschlagTag tag;
  final bool manuellSortiert;
  final bool uebernommen;
  final bool kannZurueck;
  final bool kannVor;
  final void Function(int von, int nach) onReorder;
  final VoidCallback onNachRegeln;
  final void Function(VorschlagPosten) onMenge;
  final void Function(VorschlagPosten) onEntfernen;
  final void Function(VorschlagPosten, int richtung) onVerschieben;
  final VoidCallback onUebernehmen;
  final void Function(VorschlagPosten) onDatenblatt;
  final VoidCallback onDatenblaetter;

  static const _wochentage = [
    'Montag',
    'Dienstag',
    'Mittwoch',
    'Donnerstag',
    'Freitag',
    'Samstag',
    'Sonntag',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final farben = theme.colorScheme;
    final f = AppFarben.von(context);
    final voll = tag.auslastung > 1;
    final balken = voll ? f.fehler : _bratFarbe(theme);
    final brueche = Planungsrechner.regelbrueche(tag.posten);
    final grau = theme.textTheme.bodySmall?.copyWith(
      color: farben.onSurfaceVariant,
    );

    // Ein Bereich wie die übrigen: Kopf auf der Fläche der Leisten, weiße
    // Posten darunter. Material statt bemalter Box: Die Klick-Welle der
    // Posten malt darauf.
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
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
            // ── Kopf mit Auslastungsbalken ────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                color: f.leiste,
                border: Border(bottom: BorderSide(color: farben.outline)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_wochentage[tag.tag.weekday - 1]}, '
                          '${_zwei(tag.tag.day)}.${_zwei(tag.tag.month)}.'
                          '${tag.tag.year}',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (uebernommen) ...[
                        const StatusMarke(
                          'übernommen',
                          art: StatusArt.ok,
                          icon: Icons.check,
                        ),
                        const SizedBox(width: 10),
                      ],
                      Text(
                        '${(tag.auslastung * 100).round()} %',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFeatures: _ziffern,
                          color: voll ? f.fehler : farben.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: AppMasse.eckenKlein,
                    child: LinearProgressIndicator(
                      value: tag.auslastung.clamp(0, 1).toDouble(),
                      minHeight: 6,
                      backgroundColor: farben.outlineVariant,
                      valueColor: AlwaysStoppedAnimation(balken),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (tag.belegtVorherMinuten > 0)
                        StatusMarke(
                          'im Board ${Zeit.kurz(tag.belegtVorherMinuten)}',
                        ),
                      StatusMarke('neu ${Zeit.kurz(tag.neuMinuten)}'),
                      StatusMarke('von ${Zeit.kurz(tag.kapazitaetMinuten)}'),
                      StatusMarke('${tag.rohwareKg.round()} kg Rohware'),
                      if (manuellSortiert)
                        const StatusMarke(
                          'manuell sortiert',
                          art: StatusArt.info,
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Posten, per Griff umsortierbar ────────────────────────
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: tag.posten.length,
              // Die Flutter-Version der CI kennt `onReorderItem` noch
              // nicht, die lokale hält `onReorder` bereits für veraltet.
              // Bis beide auf derselben Version sind, gewinnt die CI — ein
              // Fehler dort wiegt schwerer als ein Hinweis im Terminal.
              // ignore: deprecated_member_use
              onReorder: onReorder,
              itemBuilder: (context, i) {
                final p = tag.posten[i];
                return _PostenZeile(
                  key: ValueKey('${p.productId}-${p.bedarfId}-$i'),
                  index: i,
                  posten: p,
                  tag: tag.tag,
                  kannZurueck: kannZurueck,
                  kannVor: kannVor,
                  onMenge: () => onMenge(p),
                  onEntfernen: () => onEntfernen(p),
                  onVerschieben: (r) => onVerschieben(p, r),
                  onDatenblatt: () => onDatenblatt(p),
                );
              },
            ),

            // ── Hinweise ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (tag.endreinigungMinuten > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.cleaning_services_outlined,
                            size: 15,
                            color: farben.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Endreinigung '
                            '${Zeit.kurz(tag.endreinigungMinuten)}',
                            style: grau,
                          ),
                        ],
                      ),
                    ),
                  // Von Hand gegen die Regeln sortiert: kostet eine
                  // Reinigung — Achtung, kein Fehler.
                  for (final b in brueche)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: HinweisBox(b, art: StatusArt.warnung),
                    ),
                  if (tag.warnungen.isNotEmpty)
                    Theme(
                      data: theme.copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(bottom: 8),
                        dense: true,
                        leading: Icon(
                          Icons.info_outline,
                          size: 16,
                          color: farben.onSurfaceVariant,
                        ),
                        title: Text(
                          tag.warnungen.length == 1
                              ? '1 Hinweis'
                              : '${tag.warnungen.length} Hinweise',
                          style: grau,
                        ),
                        children: [
                          for (final w in tag.warnungen)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 2),
                                child: Text(w, style: grau),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // ── Aktionen ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: farben.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  if (manuellSortiert)
                    TextButton.icon(
                      onPressed: onNachRegeln,
                      icon: const Icon(Icons.sort_rounded, size: 18),
                      label: const Text('Nach Regeln sortieren'),
                    ),
                  TextButton.icon(
                    onPressed: onDatenblaetter,
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: Text(
                      tag.posten.length == 1
                          ? 'Datenblatt'
                          : 'Datenblätter (${tag.posten.length})',
                    ),
                  ),
                  const Spacer(),
                  if (uebernommen)
                    const StatusMarke(
                      'Tag ist im Board',
                      art: StatusArt.ok,
                      icon: Icons.check,
                    )
                  else
                    FilledButton.icon(
                      onPressed: onUebernehmen,
                      icon: const Icon(Icons.playlist_add_rounded, size: 18),
                      label: const Text('Tag ins Board übernehmen'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _zwei(int v) => v.toString().padLeft(2, '0');
}

// ═══════════════════════════════════════════════════════════════════════
// Postenzeile
// ═══════════════════════════════════════════════════════════════════════

class _PostenZeile extends StatelessWidget {
  const _PostenZeile({
    required super.key,
    required this.index,
    required this.posten,
    required this.tag,
    required this.kannZurueck,
    required this.kannVor,
    required this.onMenge,
    required this.onEntfernen,
    required this.onVerschieben,
    required this.onDatenblatt,
  });

  final int index;
  final VorschlagPosten posten;

  /// Der Tag, auf dem der Posten gerade liegt.
  final DateTime tag;
  final bool kannZurueck;
  final bool kannVor;
  final VoidCallback onMenge;
  final VoidCallback onEntfernen;
  final void Function(int richtung) onVerschieben;
  final VoidCallback onDatenblatt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final farben = theme.colorScheme;
    final f = AppFarben.von(context);
    final reinigen = posten.wechselGrund == WechselGrund.reinigen;
    final grau = theme.textTheme.bodySmall?.copyWith(
      fontSize: 11,
      color: farben.onSurfaceVariant,
    );
    // Reinigen kostet Zeit — orange als Achtung, kein Fehler.
    final wechselFarbe = reinigen ? f.warnung : farben.onSurfaceVariant;

    // Der Wechsel gehört zum ÜBERGANG, nicht zum Artikel — deshalb steht
    // er als eigene, eingerückte Zeile darüber.
    final wechsel = switch (posten.wechselGrund) {
      WechselGrund.tagesstart => null,
      WechselGrund.ohneUmstellung => 'kein Umstellen nötig',
      WechselGrund.umstellen =>
        'umrüsten ${Zeit.kurz(posten.nebenzeitMinuten)}',
      WechselGrund.reinigen =>
        'reinigen ${Zeit.kurz(posten.nebenzeitMinuten)}',
    };

    // Termin und Herkunft: Liegt der Tag nach dem Termin — etwa nach
    // einem Verschieben —, steht das rot da.
    final termin = posten.termin;
    final zuSpaet = posten.zuSpaetAm(tag);
    final auftraege = {for (final b in posten.auftragsBezuege) b.beleg};
    final herkunft = [
      if (termin != null)
        zuSpaet
            ? 'nach dem Termin (${_tagKurz(termin)})!'
            : 'spätestens ${_tagKurz(termin)}',
      if (auftraege.isNotEmpty)
        'Auftragsbestand, ${auftraege.length} '
            '${auftraege.length == 1 ? 'Auftrag' : 'Aufträge'}',
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (wechsel != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(52, 2, 16, 2),
            child: Row(
              children: [
                Icon(
                  reinigen
                      ? Icons.cleaning_services_rounded
                      : Icons.swap_horiz_rounded,
                  size: 13,
                  color: wechselFarbe,
                ),
                const SizedBox(width: 6),
                Text(wechsel, style: grau?.copyWith(color: wechselFarbe)),
              ],
            ),
          ),
        InkWell(
          onTap: onMenge,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      size: 18,
                      color: farben.outline,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Die Nummer als blasse Marke — der Griff für den Blick.
                Container(
                  width: 56,
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: f.infoFlaeche,
                    borderRadius: AppMasse.eckenKlein,
                  ),
                  child: Text(
                    posten.artikelnummer,
                    maxLines: 1,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: farben.primary,
                      fontWeight: FontWeight.w600,
                      fontFeatures: _ziffern,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        posten.bezeichnung,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (posten.begruendung.isNotEmpty)
                        Text(posten.begruendung, style: grau),
                      if (herkunft.isNotEmpty)
                        Text(
                          herkunft,
                          style: zuSpaet
                              ? grau?.copyWith(
                                  color: f.fehler,
                                  fontWeight: FontWeight.w700,
                                )
                              : grau,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${posten.mengeKg.round()} kg',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFeatures: _ziffern,
                      ),
                    ),
                    Text(
                      '${Zeit.kurz(posten.dauerMinuten)} · '
                      '${posten.rohwareKg.round()} kg roh',
                      style: grau?.copyWith(fontFeatures: _ziffern),
                    ),
                  ],
                ),
                PopupMenuButton<String>(
                  tooltip: 'Ändern',
                  icon: Icon(
                    Icons.more_vert_rounded,
                    size: 18,
                    color: farben.onSurfaceVariant,
                  ),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'menge',
                      child: Text('Menge ändern …'),
                    ),
                    if (kannZurueck)
                      const PopupMenuItem(
                        value: 'zurueck',
                        child: Text('Einen Arbeitstag früher'),
                      ),
                    if (kannVor)
                      const PopupMenuItem(
                        value: 'vor',
                        child: Text('Einen Arbeitstag später'),
                      ),
                    const PopupMenuItem(
                      value: 'weg',
                      child: Text('Aus dem Vorschlag nehmen'),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'datenblatt',
                      child: Text('Datenblatt drucken'),
                    ),
                  ],
                  onSelected: (w) {
                    switch (w) {
                      case 'datenblatt':
                        onDatenblatt();
                      case 'menge':
                        onMenge();
                      case 'zurueck':
                        onVerschieben(-1);
                      case 'vor':
                        onVerschieben(1);
                      case 'weg':
                        onEntfernen();
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Mengendialog
// ═══════════════════════════════════════════════════════════════════════

class _MengeDialog extends StatefulWidget {
  const _MengeDialog({required this.posten});

  final VorschlagPosten posten;

  @override
  State<_MengeDialog> createState() => _MengeDialogState();
}

class _MengeDialogState extends State<_MengeDialog> {
  late final TextEditingController _menge;

  @override
  void initState() {
    super.initState();
    _menge = TextEditingController(
      text: widget.posten.mengeKg.round().toString(),
    );
  }

  @override
  void dispose() {
    _menge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.posten;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('${p.artikelnummer} — Menge'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.bezeichnung, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _menge,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Fertigmenge',
              suffixText: 'kg',
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Dauer und Rohware skalieren mit. Feste Durchlaufzeiten der '
            'Anlagen tun das nicht — bei großen Änderungen lieber neu '
            'berechnen lassen. Weniger als der Bedarf: Der Rest bleibt '
            'offen und kommt beim nächsten Vorschlag wieder.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            double.tryParse(_menge.text.trim().replaceAll(',', '.')),
          ),
          child: const Text('Übernehmen'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Restliste
// ═══════════════════════════════════════════════════════════════════════

/// Was nicht in den Vorschlag passt — je Artikel mit dem Grund.
class _NichtPlanbarKarte extends StatefulWidget {
  const _NichtPlanbarKarte({required this.eintraege});

  final List<NichtPlanbar> eintraege;

  @override
  State<_NichtPlanbarKarte> createState() => _NichtPlanbarKarteState();
}

class _NichtPlanbarKarteState extends State<_NichtPlanbarKarte> {
  /// Anfangs offen: Der Grund soll gleich zu sehen sein.
  bool _offen = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final farben = theme.colorScheme;
    final eintraege = widget.eintraege;
    final zahlen = theme.textTheme.bodyMedium?.copyWith(
      fontFeatures: _ziffern,
    );
    final grau = theme.textTheme.bodySmall?.copyWith(
      color: farben.onSurfaceVariant,
    );

    return Bereich(
      titel: 'Nicht eingeplant',
      icon: Icons.inbox_rounded,
      untertitel: '${eintraege.length}',
      aktionen: [
        IconButton(
          onPressed: () => setState(() => _offen = !_offen),
          icon: Icon(_offen ? Icons.expand_less : Icons.expand_more, size: 20),
          tooltip: _offen ? 'Zuklappen' : 'Aufklappen',
          visualDensity: VisualDensity.compact,
        ),
      ],
      innenAbstand: EdgeInsets.zero,
      child: !_offen
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, n) in eintraege.indexed)
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                    decoration: BoxDecoration(
                      border: i == 0
                          ? null
                          : Border(
                              top: BorderSide(color: farben.outlineVariant),
                            ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: _Auswahl.nummer,
                          child: Text(
                            n.artikelnummer,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: zahlen?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                n.bezeichnung,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium,
                              ),
                              Text(n.grund, style: grau),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${n.mengeKg.round()} kg',
                          style: zahlen?.copyWith(
                            color: farben.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Einstellungen
// ═══════════════════════════════════════════════════════════════════════

class _EinstellungenDialog extends StatefulWidget {
  const _EinstellungenDialog({required this.start});

  final VorschlagEinstellungen start;

  @override
  State<_EinstellungenDialog> createState() => _EinstellungenDialogState();
}

class _EinstellungenDialogState extends State<_EinstellungenDialog> {
  late final TextEditingController _ruesten;
  late final TextEditingController _reinigen;
  late final TextEditingController _endreinigung;
  late final TextEditingController _tage;
  late bool _samstag;
  late bool _spaet;
  late DateTime? _start;
  late Set<DateTime> _gesperrt;

  @override
  void initState() {
    super.initState();
    final e = widget.start;
    _ruesten =
        TextEditingController(text: e.ruestenMinuten.round().toString());
    _reinigen = TextEditingController(
      text: e.zwischenreinigungMinuten.round().toString(),
    );
    _endreinigung = TextEditingController(
      text: e.endreinigungMinuten.round().toString(),
    );
    _tage = TextEditingController(text: e.maxArbeitstage.toString());
    _samstag = e.planeSamstag;
    _spaet = e.moeglichstSpaet;
    _start = e.startTag;
    _gesperrt = {...e.gesperrteTage};
  }

  @override
  void dispose() {
    _ruesten.dispose();
    _reinigen.dispose();
    _endreinigung.dispose();
    _tage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Höchstens 70 % der Fensterhöhe, der Inhalt scrollt darin. So bleiben
    // Titel und Knöpfe immer erreichbar, egal wie klein das Fenster ist.
    final maxHoehe = MediaQuery.sizeOf(context).height * 0.7;

    // Der Titel steht im Kopf des Fensters wie bei den übrigen Fenstern —
    // vorher stand er als Text im Inhalt.
    return AlertDialog(
      title: const Text('Zeiten und Zeitraum'),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: maxHoehe),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Die Nebenzeiten sind Pauschalen. Sobald beim Erfassen echte '
                'Rüst- und Reinigungszeiten anfallen, lassen sie sich daran '
                'ausrichten.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _zahlFeld(_ruesten, 'Umrüsten', 'min')),
                  const SizedBox(width: 10),
                  Expanded(child: _zahlFeld(_reinigen, 'Reinigen', 'min')),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _zahlFeld(_endreinigung, 'Endreinigung', 'min'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: _zahlFeld(_tage, 'Zeitraum', 'Tage')),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _spaet,
                onChanged: (v) => setState(() => _spaet = v),
                title: const Text('Möglichst spät planen'),
                subtitle: const Text(
                  'Nah am Termin: frische Ware, wenig Lager. Aus: so früh '
                  'wie möglich. Nach dem Termin plant der Vorschlag nie.',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _samstag,
                onChanged: (v) => setState(() => _samstag = v),
                title: const Text('Samstag mitplanen'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_rounded),
                title: const Text('Beginn'),
                subtitle: Text(_start == null ? 'morgen' : _datum(_start!)),
                trailing: TextButton(
                  onPressed: _waehleStart,
                  child: const Text('ändern'),
                ),
              ),
              // Gesperrte Tage sind der Platz für alles Äußere: fehlende
              // Rohware, Wartung, Feiertag, Inventur.
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.block_rounded),
                title: const Text('Gesperrte Tage'),
                subtitle: Text(
                  _gesperrt.isEmpty
                      ? 'keine — z.B. Feiertag oder fehlende Rohware'
                      : (_gesperrt.toList()..sort()).map(_datum).join(', '),
                ),
                trailing: TextButton(
                  onPressed: _waehleGesperrt,
                  child: const Text('hinzufügen'),
                ),
              ),
              if (_gesperrt.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(_gesperrt.clear),
                    child: const Text('Sperren aufheben'),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _fertig,
          child: const Text('Übernehmen'),
        ),
      ],
    );
  }

  Widget _zahlFeld(TextEditingController c, String label, String suffix) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, suffixText: suffix),
    );
  }

  Future<void> _waehleStart() async {
    final heute = DateTime.now();
    final von = DateTime(heute.year, heute.month, heute.day - 1);
    final bis = DateTime(heute.year, heute.month, heute.day + 180);
    final gewaehlt = await showDatePicker(
      context: context,
      initialDate: _imBereich(_start, von, bis, heute),
      firstDate: von,
      lastDate: bis,
    );
    if (gewaehlt != null) {
      setState(
        () => _start = DateTime(gewaehlt.year, gewaehlt.month, gewaehlt.day),
      );
    }
  }

  Future<void> _waehleGesperrt() async {
    final heute = DateTime.now();
    final von = DateTime(heute.year, heute.month, heute.day);
    final bis = DateTime(heute.year, heute.month, heute.day + 180);
    final gewaehlt = await showDatePicker(
      context: context,
      initialDate: _imBereich(_start, von, bis, heute),
      firstDate: von,
      lastDate: bis,
      helpText: 'Tag sperren',
    );
    if (gewaehlt == null) return;
    setState(
      () => _gesperrt.add(
        DateTime(gewaehlt.year, gewaehlt.month, gewaehlt.day),
      ),
    );
  }

  void _fertig() {
    double zahl(TextEditingController c, double standard) =>
        double.tryParse(c.text.trim().replaceAll(',', '.')) ?? standard;

    Navigator.of(context).pop(
      widget.start.kopieMit(
        ruestenMinuten: zahl(_ruesten, widget.start.ruestenMinuten),
        zwischenreinigungMinuten:
            zahl(_reinigen, widget.start.zwischenreinigungMinuten),
        endreinigungMinuten:
            zahl(_endreinigung, widget.start.endreinigungMinuten),
        maxArbeitstage:
            int.tryParse(_tage.text.trim()) ?? widget.start.maxArbeitstage,
        planeSamstag: _samstag,
        moeglichstSpaet: _spaet,
        gesperrteTage: _gesperrt,
        startTag: _start,
      ),
    );
  }

  /// Vorbelegung der Datumsauswahl: der gewählte Beginn, sonst morgen —
  /// aber immer innerhalb dessen, was die Auswahl anbietet. Sonst stürzt
  /// sie ab, etwa bei einem Beginn, der inzwischen in der Vergangenheit
  /// liegt.
  static DateTime _imBereich(
    DateTime? wunsch,
    DateTime von,
    DateTime bis,
    DateTime heute,
  ) {
    final d = wunsch ?? DateTime(heute.year, heute.month, heute.day + 1);
    if (d.isBefore(von)) return von;
    if (d.isAfter(bis)) return bis;
    return d;
  }

  static String _datum(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.';
}

// ═══════════════════════════════════════════════════════════════════════
// Farben und Formatierung
// ═══════════════════════════════════════════════════════════════════════

/// Die Farbe der Bratstraße — für sie plant der Vorschlag. Im Dunkelmodus
/// aufgehellt: Das dunkle Braun verschwände sonst auf der dunklen Fläche.
Color _bratFarbe(ThemeData theme) {
  final farbe = Abteilung.bratstrasse.farbe;
  return theme.brightness == Brightness.dark
      ? Color.alphaBlend(Colors.white.withValues(alpha: 0.45), farbe)
      : farbe;
}

/// Ziffern gleich breit, damit Mengen und Zeiten ruhig stehen.
const List<FontFeature> _ziffern = [FontFeature.tabularFigures()];

const _wochentageKurz = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

DateTime _tagVon(DateTime d) => DateTime(d.year, d.month, d.day);

/// „Di 06.10."
String _tagKurz(DateTime d) => '${_wochentageKurz[d.weekday - 1]} '
    '${d.day.toString().padLeft(2, '0')}.'
    '${d.month.toString().padLeft(2, '0')}.';
