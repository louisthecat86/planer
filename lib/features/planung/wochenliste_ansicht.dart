import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';
import '../../core/theme/app_stil.dart';
import '../../core/ui/bausteine.dart';
import '../../core/utils/fehler_text.dart';
import '../../core/utils/zeit.dart';
import '../bedarf/bedarf_screen.dart' show bedarfProvider;
import 'planungsvorschlag_service.dart';
import 'wochenliste.dart';

// ═══════════════════════════════════════════════════════════════════════
// Datenquelle
// ═══════════════════════════════════════════════════════════════════════

/// Ein Artikel, wie ihn die Suche der Wochenliste anbietet.
class WochenArtikel {
  const WochenArtikel({
    required this.id,
    required this.nummer,
    required this.bezeichnung,
  });

  final String id;
  final String nummer;
  final String bezeichnung;

  String get anzeige => '$nummer · $bezeichnung';
}

/// Woher die Wochenliste ihre Daten hat und wohin sie schreibt. Eigene
/// Schnittstelle, damit sich die Ansicht ohne Datenbank prüfen lässt.
abstract class WochenlisteQuelle {
  Future<List<WochenArtikel>> artikel();
  Future<List<WochenZeile>> lade();
  Future<String> speichere({
    String? bedarfId,
    required String productId,
    required DateTime? wunschtag,
    required MengenFeld feld,
    required double kg,
    required double fertigKg,
  });
  Future<void> loesche(String bedarfId);
  Future<ArtikelVerhaeltnisse> verhaeltnisse(String productId);
  Future<ZeilenDauer> dauer(String productId, double fertigKg);

  /// Tageskapazität der Bratstraße in Minuten.
  Future<double> tageskapazitaet();
}

class _DbQuelle implements WochenlisteQuelle {
  _DbQuelle(this._ref);

  final Ref _ref;

  WochenlisteService get _dienst =>
      WochenlisteService(_ref.read(databaseProvider));

  @override
  Future<List<WochenArtikel>> artikel() async {
    final db = _ref.read(databaseProvider);
    final produkte = await (db.select(db.products)
          ..where((p) => p.deletedAt.isNull())
          ..orderBy([(p) => OrderingTerm.asc(p.artikelnummer)]))
        .get();
    return [
      for (final p in produkte)
        WochenArtikel(
          id: p.id,
          nummer: p.artikelnummer,
          bezeichnung: p.artikelbezeichnung,
        ),
    ];
  }

  @override
  Future<List<WochenZeile>> lade() => _dienst.lade();

  @override
  Future<String> speichere({
    String? bedarfId,
    required String productId,
    required DateTime? wunschtag,
    required MengenFeld feld,
    required double kg,
    required double fertigKg,
  }) async {
    final id = await _dienst.speichere(
      bedarfId: bedarfId,
      productId: productId,
      wunschtag: wunschtag,
      feld: feld,
      kg: kg,
      fertigKg: fertigKg,
    );
    _danach();
    return id;
  }

  @override
  Future<void> loesche(String bedarfId) async {
    await _dienst.loesche(bedarfId);
    _danach();
  }

  /// Die Bedarfsliste zeigt die Zeilen mit — und gesichert wird wie nach
  /// jeder Änderung am Bedarf.
  void _danach() {
    _ref.invalidate(bedarfProvider);
    _ref
        .read(autoBackupTriggerProvider)
        .fireDebounced(reason: 'Wochenliste geändert');
  }

  @override
  Future<ArtikelVerhaeltnisse> verhaeltnisse(String productId) =>
      _dienst.verhaeltnisse(productId);

  @override
  Future<ZeilenDauer> dauer(String productId, double fertigKg) =>
      _dienst.dauer(productId, fertigKg);

  @override
  Future<double> tageskapazitaet() =>
      PlanungsvorschlagService(_ref.read(databaseProvider)).tageskapazitaet();
}

final wochenlisteQuelleProvider =
    Provider<WochenlisteQuelle>((ref) => _DbQuelle(ref));

// ═══════════════════════════════════════════════════════════════════════
// Zeile (Zustand der Ansicht)
// ═══════════════════════════════════════════════════════════════════════

class _Zeile {
  _Zeile({
    this.bedarfId,
    this.artikel,
    this.wunschtag,
    this.feld = MengenFeld.fertig,
    this.imBoardKg = 0,
  }) : artikelText = TextEditingController(text: artikel?.anzeige ?? '');

  String? bedarfId;
  WochenArtikel? artikel;
  DateTime? wunschtag;
  MengenFeld feld;
  double imBoardKg;

  final TextEditingController artikelText;
  final FocusNode artikelFokus = FocusNode();
  final Map<MengenFeld, TextEditingController> felder = {
    for (final f in MengenFeld.values) f: TextEditingController(),
  };
  final Key schluessel = UniqueKey();

  ArtikelVerhaeltnisse verhaeltnisse = const ArtikelVerhaeltnisse();
  Mengen? mengen;
  ZeilenDauer dauer = ZeilenDauer.leer;

  /// Wartet aufs Speichern — wer weitertippt, schiebt es hinaus.
  Timer? warten;
  bool speichert = false;
  bool nochmal = false;

  /// Zählt jede Änderung; ein Ergebnis von früher wird verworfen.
  int stand = 0;
  String? fehler;

  bool get leer =>
      artikel == null && felder.values.every((c) => c.text.isEmpty);

  /// Eingetragene Menge im aktiven Feld.
  double? get kg => rechneMenge(felder[feld]!.text);

  void dispose() {
    warten?.cancel();
    artikelText.dispose();
    artikelFokus.dispose();
    for (final c in felder.values) {
      c.dispose();
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Ansicht
// ═══════════════════════════════════════════════════════════════════════

/// Spaltenbreiten — für Kopf und Zeilen dieselben.
abstract final class _Spalte {
  static const double wunsch = 140;
  static const double menge = 112;
  static const double dauer = 210;
  static const double weg = 40;
  static const double luecke = 8;

  /// Darunter wird die Tabelle waagerecht scrollbar.
  static const double mindestBreite = 980;
}

/// Die Wochenliste im Planungsvorschlag: Artikel untereinander, je Zeile
/// ein Wunschtag und EINE Menge. Die anderen beiden Mengen und die Dauer
/// je Abteilung stehen sofort daneben; unten die Summe gegen die
/// Kapazität der Bratstraße.
///
/// Jede vollständige Zeile wird sofort als Bedarf gespeichert und bleibt
/// stehen, bis sie im Board ist oder gelöscht wird. „Vorschlag rechnen"
/// übergibt an den Reiter „Vorschlag".
class WochenlisteAnsicht extends ConsumerStatefulWidget {
  const WochenlisteAnsicht({
    super.key,
    required this.tage,
    required this.onVorschlag,
    this.neuLaden = 0,
  });

  /// Die Arbeitstage, die als Wunschtag zur Wahl stehen.
  final List<DateTime> tage;

  /// Rechnet den Vorschlag mit den Zeilen der Liste.
  final Future<void> Function() onVorschlag;

  /// Steigt, wenn sich außerhalb etwas geändert hat (etwa ein Tag ins
  /// Board übernommen wurde) — die Liste lädt dann neu.
  final int neuLaden;

  @override
  ConsumerState<WochenlisteAnsicht> createState() => _WochenlisteAnsichtState();
}

class _WochenlisteAnsichtState extends ConsumerState<WochenlisteAnsicht>
    with AutomaticKeepAliveClientMixin {
  final List<_Zeile> _zeilen = [];
  List<WochenArtikel> _artikel = const [];
  double _kapazitaet = 0;
  bool _laedt = true;
  Object? _fehler;
  bool _rechnet = false;

  WochenlisteQuelle get _quelle => ref.read(wochenlisteQuelleProvider);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _lade();
  }

  @override
  void didUpdateWidget(WochenlisteAnsicht alt) {
    super.didUpdateWidget(alt);
    // Nicht mitten in eine Eingabe hinein neu laden.
    if (widget.neuLaden != alt.neuLaden &&
        !_zeilen.any((z) => z.warten != null || z.speichert)) {
      _lade();
    }
  }

  @override
  void dispose() {
    for (final z in _zeilen) {
      z.dispose();
    }
    super.dispose();
  }

  Future<void> _lade() async {
    setState(() {
      _laedt = true;
      _fehler = null;
    });
    try {
      final q = _quelle;
      final artikel = await q.artikel();
      final kapazitaet = await q.tageskapazitaet();
      final gespeichert = await q.lade();
      final jeId = {for (final a in artikel) a.id: a};
      final neu = <_Zeile>[];
      for (final w in gespeichert) {
        final z = _Zeile(
          bedarfId: w.bedarfId,
          artikel: jeId[w.productId] ??
              WochenArtikel(
                id: w.productId,
                nummer: w.artikelnummer,
                bezeichnung: w.bezeichnung,
              ),
          wunschtag: w.wunschtag,
          feld: w.feld,
          imBoardKg: w.imBoardKg,
        );
        z.felder[w.feld]!.text = _kgText(w.kg);
        z.verhaeltnisse = await q.verhaeltnisse(w.productId);
        _rechne(z);
        z.dauer = await q.dauer(w.productId, w.fertigKg);
        neu.add(z);
      }
      neu.add(_Zeile());
      if (!mounted) {
        for (final z in neu) {
          z.dispose();
        }
        return;
      }
      setState(() {
        for (final z in _zeilen) {
          z.dispose();
        }
        _zeilen
          ..clear()
          ..addAll(neu);
        _artikel = artikel;
        _kapazitaet = kapazitaet;
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

  // ── Rechnen und Speichern ────────────────────────────────────────────

  /// Füllt die beiden anderen Felder aus dem aktiven.
  void _rechne(_Zeile z) {
    final kg = z.kg;
    z.mengen =
        kg == null || kg <= 0 ? null : z.verhaeltnisse.rechne(z.feld, kg);
    for (final f in MengenFeld.values) {
      if (f == z.feld) continue;
      final wert = z.mengen?.von(f);
      z.felder[f]!.text = wert == null ? '' : _kgText(wert);
    }
  }

  void _eingabe(_Zeile z, MengenFeld f) {
    setState(() {
      z.feld = f;
      z.stand++;
      _rechne(z);
    });
    z.warten?.cancel();
    z.warten = Timer(const Duration(milliseconds: 600), () => _speichere(z));
  }

  Future<void> _waehleArtikel(_Zeile z, WochenArtikel a) async {
    setState(() {
      z.artikel = a;
      z.stand++;
      if (identical(z, _zeilen.last)) _zeilen.add(_Zeile());
    });
    try {
      final v = await _quelle.verhaeltnisse(a.id);
      if (!mounted || z.artikel?.id != a.id) return;
      setState(() {
        z.verhaeltnisse = v;
        _rechne(z);
      });
    } catch (_) {
      // Ohne Verhältnisse bleibt nur die Fertigware — die Zeile sagt das.
    }
    await _speichere(z);
  }

  void _waehleTag(_Zeile z, DateTime? tag) {
    setState(() {
      z.wunschtag = tag;
      z.stand++;
    });
    _speichere(z);
  }

  /// Speichert die Zeile, wenn sie vollständig ist, und holt die Dauer.
  Future<void> _speichere(_Zeile z) async {
    z.warten?.cancel();
    z.warten = null;
    if (z.speichert) {
      z.nochmal = true;
      return;
    }
    final a = z.artikel;
    final m = z.mengen;
    final kg = z.kg;
    if (a == null || m == null || !m.planbar || kg == null) {
      if (mounted) setState(() => z.dauer = ZeilenDauer.leer);
      return;
    }
    final stand = z.stand;
    setState(() => z.speichert = true);
    try {
      final id = await _quelle.speichere(
        bedarfId: z.bedarfId,
        productId: a.id,
        wunschtag: z.wunschtag,
        feld: z.feld,
        kg: kg,
        fertigKg: m.fertig!,
      );
      z.bedarfId = id;
      final dauer = await _quelle.dauer(a.id, m.fertig!);
      if (!mounted) return;
      setState(() {
        if (stand == z.stand) z.dauer = dauer;
        z.fehler = null;
      });
    } catch (e) {
      if (mounted) setState(() => z.fehler = fehlerText(e));
    } finally {
      z.speichert = false;
      if (mounted) setState(() {});
      if (z.nochmal && mounted) {
        z.nochmal = false;
        await _speichere(z);
      }
    }
  }

  Future<void> _entferne(_Zeile z) async {
    final id = z.bedarfId;
    final imBoard = z.imBoardKg;
    final messenger = ScaffoldMessenger.of(context);
    z.warten?.cancel();
    z.warten = null;
    setState(() {
      _zeilen.remove(z);
      if (_zeilen.isEmpty || !_zeilen.last.leer) _zeilen.add(_Zeile());
    });
    // Nach dem Bild entsorgen: Das Feld hängt in diesem Durchgang noch.
    WidgetsBinding.instance.addPostFrameCallback((_) => z.dispose());
    if (id == null) return;
    try {
      await _quelle.loesche(id);
      if (imBoard > 0) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Aus der Wochenliste genommen. Die ${_kgText(imBoard)} kg, die '
              'schon im Board stehen, bleiben dort.',
            ),
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Fehler: ${fehlerText(e)}')),
      );
    }
  }

  /// Enter im Mengenfeld: in die nächste Zeile, an den Artikel.
  void _weiter(_Zeile z) {
    final i = _zeilen.indexOf(z);
    if (i < 0) return;
    if (i < _zeilen.length - 1) {
      _zeilen[i + 1].artikelFokus.requestFocus();
      return;
    }
    // Neue Zeile: erst nach dem Bild fokussieren, wenn ihr Feld steht.
    final neu = _Zeile();
    setState(() => _zeilen.add(neu));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _zeilen.contains(neu)) neu.artikelFokus.requestFocus();
    });
  }

  Future<void> _vorschlag() async {
    setState(() => _rechnet = true);
    try {
      // Was noch wartet, zuerst speichern.
      for (final z in [..._zeilen]) {
        if (z.warten != null) await _speichere(z);
      }
      await widget.onVorschlag();
      if (mounted) DefaultTabController.maybeOf(context)?.animateTo(0);
    } finally {
      if (mounted) setState(() => _rechnet = false);
    }
  }

  // ── Aufbau ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_laedt) return const Center(child: CircularProgressIndicator());
    if (_fehler != null) {
      return ListView(
        padding: const EdgeInsets.all(14),
        children: [
          HinweisBox(
            'Fehler: ${fehlerText(_fehler!)}',
            art: StatusArt.fehler,
            auswaehlbar: true,
          ),
        ],
      );
    }

    final gespeichert = _zeilen.where((z) => z.bedarfId != null).length;
    final summe = summeJeAbteilung([for (final z in _zeilen) z.dauer]);

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 40),
      children: [
        Bereich(
          titel: 'Wochenliste',
          icon: Icons.edit_note_rounded,
          untertitel: gespeichert == 1 ? '1 Zeile' : '$gespeichert Zeilen',
          innenAbstand: EdgeInsets.zero,
          child: LayoutBuilder(
            builder: (context, box) {
              final breite = math.max(box.maxWidth, _Spalte.mindestBreite);
              final tabelle = SizedBox(
                width: breite,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Kopf(),
                    for (var i = 0; i < _zeilen.length; i++)
                      _ZeileAnsicht(
                        key: _zeilen[i].schluessel,
                        index: i,
                        zeile: _zeilen[i],
                        artikel: _artikel,
                        tage: widget.tage,
                        onArtikel: (a) => _waehleArtikel(_zeilen[i], a),
                        onTag: (t) => _waehleTag(_zeilen[i], t),
                        onEingabe: (f) => _eingabe(_zeilen[i], f),
                        onWeiter: () => _weiter(_zeilen[i]),
                        onEntfernen:
                            _zeilen[i].leer && _zeilen[i].bedarfId == null
                                ? null
                                : () => _entferne(_zeilen[i]),
                      ),
                  ],
                ),
              );
              if (breite <= box.maxWidth) return tabelle;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: tabelle,
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        _Summe(summe: summe, kapazitaet: _kapazitaet),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              key: const ValueKey('wochenliste-vorschlag'),
              onPressed: gespeichert == 0 || _rechnet ? null : _vorschlag,
              icon: _rechnet
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_rounded),
              label: const Text('Vorschlag rechnen'),
            ),
            Text(
              'Ein Feld je Zeile genügt — die anderen rechnet der Planer. '
              'Der Wunschtag ist ein Wunsch: Ist dort kein Platz, nimmt der '
              'Vorschlag den nächsten Tag mit Platz. Die Zeilen bleiben '
              'stehen, bis sie im Board sind oder gelöscht werden.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Bausteine
// ═══════════════════════════════════════════════════════════════════════

class _Kopf extends StatelessWidget {
  const _Kopf();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stil = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    Widget zelle(String text, double breite, {bool rechts = false}) => SizedBox(
          width: breite,
          child: Text(
            text,
            style: stil,
            textAlign: rechts ? TextAlign.right : TextAlign.left,
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(child: Text('Artikel', style: stil)),
          const SizedBox(width: _Spalte.luecke),
          zelle('Wunschtag', _Spalte.wunsch),
          for (final f in MengenFeld.values) ...[
            const SizedBox(width: _Spalte.luecke),
            zelle(f.text, _Spalte.menge, rechts: true),
          ],
          const SizedBox(width: _Spalte.luecke * 2),
          zelle('Dauer', _Spalte.dauer),
          const SizedBox(width: _Spalte.weg),
        ],
      ),
    );
  }
}

class _ZeileAnsicht extends StatelessWidget {
  const _ZeileAnsicht({
    super.key,
    required this.index,
    required this.zeile,
    required this.artikel,
    required this.tage,
    required this.onArtikel,
    required this.onTag,
    required this.onEingabe,
    required this.onWeiter,
    required this.onEntfernen,
  });

  final int index;
  final _Zeile zeile;
  final List<WochenArtikel> artikel;
  final List<DateTime> tage;
  final ValueChanged<WochenArtikel> onArtikel;
  final ValueChanged<DateTime?> onTag;
  final ValueChanged<MengenFeld> onEingabe;
  final VoidCallback onWeiter;
  final VoidCallback? onEntfernen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final farben = theme.colorScheme;
    final z = zeile;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: farben.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: _ArtikelFeld(
              key: ValueKey('wochenliste-artikel-$index'),
              zeile: z,
              artikel: artikel,
              onArtikel: onArtikel,
            ),
          ),
          const SizedBox(width: _Spalte.luecke),
          SizedBox(
            width: _Spalte.wunsch,
            child: _TagWahl(
              key: ValueKey('wochenliste-wunsch-$index'),
              wert: z.wunschtag,
              tage: tage,
              onChanged: onTag,
            ),
          ),
          for (final f in MengenFeld.values) ...[
            const SizedBox(width: _Spalte.luecke),
            SizedBox(
              width: _Spalte.menge,
              child: TextField(
                key: ValueKey('wochenliste-${f.name}-$index'),
                controller: z.felder[f],
                textAlign: TextAlign.right,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => onEingabe(f),
                onSubmitted: (_) => onWeiter(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFeatures: _ziffern,
                  // Was gerechnet ist, steht grau — eingetragen ist eins.
                  color: z.feld == f ? null : farben.onSurfaceVariant,
                  fontStyle: z.feld == f ? null : FontStyle.italic,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  suffixText: 'kg',
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                ),
              ),
            ),
          ],
          const SizedBox(width: _Spalte.luecke * 2),
          SizedBox(width: _Spalte.dauer, child: _DauerZelle(zeile: z)),
          SizedBox(
            width: _Spalte.weg,
            child: onEntfernen == null
                ? null
                : IconButton(
                    key: ValueKey('wochenliste-weg-$index'),
                    onPressed: onEntfernen,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    tooltip: 'Aus der Wochenliste nehmen',
                    visualDensity: VisualDensity.compact,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Artikelsuche nach Nummer oder Name — Pfeiltasten und Enter wählen.
class _ArtikelFeld extends StatelessWidget {
  const _ArtikelFeld({
    super.key,
    required this.zeile,
    required this.artikel,
    required this.onArtikel,
  });

  final _Zeile zeile;
  final List<WochenArtikel> artikel;
  final ValueChanged<WochenArtikel> onArtikel;

  static const _hoechstens = 12;

  Iterable<WochenArtikel> _treffer(TextEditingValue wert) {
    final q = wert.text.trim().toLowerCase();
    if (q.isEmpty || q == zeile.artikel?.anzeige.toLowerCase()) {
      return const [];
    }
    final vorn = <WochenArtikel>[];
    final sonst = <WochenArtikel>[];
    for (final a in artikel) {
      if (a.nummer.toLowerCase().startsWith(q)) {
        vorn.add(a);
      } else if (a.bezeichnung.toLowerCase().contains(q) ||
          a.nummer.toLowerCase().contains(q)) {
        sonst.add(a);
      }
      if (vorn.length >= _hoechstens) break;
    }
    return [...vorn, ...sonst].take(_hoechstens);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RawAutocomplete<WochenArtikel>(
      textEditingController: zeile.artikelText,
      focusNode: zeile.artikelFokus,
      displayStringForOption: (a) => a.anzeige,
      optionsBuilder: _treffer,
      onSelected: onArtikel,
      fieldViewBuilder: (context, controller, fokus, abschicken) => TextField(
        controller: controller,
        focusNode: fokus,
        onSubmitted: (_) => abschicken(),
        style: theme.textTheme.bodyMedium,
        decoration: const InputDecoration(
          isDense: true,
          hintText: 'Nummer oder Name …',
          prefixIcon: Icon(Icons.search, size: 18),
          prefixIconConstraints: BoxConstraints(minWidth: 32),
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        ),
      ),
      optionsViewBuilder: (context, waehle, optionen) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: AppMasse.ecken,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300, maxWidth: 480),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: optionen.length,
              itemBuilder: (context, i) {
                final a = optionen.elementAt(i);
                final markiert = AutocompleteHighlightedOption.of(context) == i;
                return InkWell(
                  onTap: () => waehle(a),
                  child: Container(
                    color: markiert ? theme.focusColor : null,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 70,
                          child: Text(
                            a.nummer,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontFeatures: _ziffern,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            a.bezeichnung,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Wunschtag: einer der Arbeitstage des Vorschlags oder frei.
class _TagWahl extends StatelessWidget {
  const _TagWahl({
    super.key,
    required this.wert,
    required this.tage,
    required this.onChanged,
  });

  final DateTime? wert;
  final List<DateTime> tage;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final w = wert;
    final auswahl = [
      ...tage,
      if (w != null && !tage.any((t) => _gleicherTag(t, w))) w,
    ]..sort();
    final vorbei = w != null && tage.isNotEmpty && w.isBefore(tage.first);
    return DropdownButtonHideUnderline(
      child: DropdownButton<DateTime?>(
        isDense: true,
        isExpanded: true,
        value: w == null ? null : auswahl.firstWhere((t) => _gleicherTag(t, w)),
        hint: const Text('frei'),
        onChanged: onChanged,
        items: [
          const DropdownMenuItem<DateTime?>(child: Text('frei')),
          for (final t in auswahl)
            DropdownMenuItem<DateTime?>(
              value: t,
              child: Text(
                vorbei && _gleicherTag(t, w)
                    ? '${_tagKurz(t)} · vorbei'
                    : _tagKurz(t),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFeatures: _ziffern,
                  color: vorbei && _gleicherTag(t, w)
                      ? AppFarben.von(context).warnung
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Dauer je Abteilung — oder warum sich nichts rechnen lässt.
class _DauerZelle extends StatelessWidget {
  const _DauerZelle({required this.zeile});

  final _Zeile zeile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final farben = theme.colorScheme;
    final grau = theme.textTheme.bodySmall?.copyWith(
      color: farben.onSurfaceVariant,
    );
    final z = zeile;
    if (z.artikel == null) return const SizedBox.shrink();
    if (z.fehler != null) {
      return Text(
        'Nicht gespeichert: ${z.fehler}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: grau?.copyWith(color: AppFarben.von(context).fehler),
      );
    }
    final fehlt = z.mengen?.fehlt;
    if (fehlt != null) {
      return Text(
        fehlt,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: grau?.copyWith(color: AppFarben.von(context).warnung),
      );
    }
    if (z.mengen == null) return Text('Menge eintragen', style: grau);
    if (z.speichert && z.dauer.minuten.isEmpty) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: SizedBox.square(
          dimension: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (z.dauer.minuten.isEmpty) return Text('—', style: grau);

    final v = z.verhaeltnisse;
    final hinweis = [
      for (final e in z.dauer.minuten.entries)
        '${e.key.anzeigeName}: ${Zeit.lang(e.value)}',
      if (z.dauer.geschaetzt)
        'Ohne Produktionen und Leistungsdaten — die Zeit ist geschätzt.',
      if (v.ausbeute case final a?)
        'Ausbeute ${_prozent(a.wert)} % (${a.herkunft})',
      if (v.fleischanteil case final f?)
        'Fleischanteil ${_prozent(f.wert)} % (${f.herkunft})',
    ].join('\n');

    return Tooltip(
      message: hinweis,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            [
              if (z.dauer.geschaetzt) '≈',
              [
                for (final e in z.dauer.minuten.entries)
                  '${e.key.kurzcode} ${Zeit.kurzOhneEinheit(e.value)}',
              ].join(' · '),
            ].join(' '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFeatures: _ziffern,
            ),
          ),
          if (z.imBoardKg > 0)
            Text('davon ${_kgText(z.imBoardKg)} kg im Board', style: grau),
        ],
      ),
    );
  }
}

/// Summe je Abteilung; die Bratstraße zusätzlich in Tagen.
class _Summe extends StatelessWidget {
  const _Summe({required this.summe, required this.kapazitaet});

  final Map<Abteilung, double> summe;
  final double kapazitaet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (summe.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('wochenliste-summe'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppMasse.ecken,
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Summe', style: theme.textTheme.titleSmall),
          for (final e in summe.entries)
            StatusMarke(
              e.key == Abteilung.bratstrasse && kapazitaet > 0
                  ? '${e.key.anzeigeName} ${Zeit.kurz(e.value)} · '
                      '≈ ${_tage(e.value / kapazitaet)} Tage'
                  : '${e.key.anzeigeName} ${Zeit.kurz(e.value)}',
              hinweis: e.key == Abteilung.bratstrasse && kapazitaet > 0
                  ? 'Reine Produktionszeit. Die Bratstraße schafft '
                      '${Zeit.kurz(kapazitaet)} am Tag; Rüsten und '
                      'Reinigen rechnet der Vorschlag dazu.'
                  : 'Reine Produktionszeit',
            ),
        ],
      ),
    );
  }

  static String _tage(double t) => t.toStringAsFixed(1).replaceAll('.', ',');
}

// ═══════════════════════════════════════════════════════════════════════
// Formatierung
// ═══════════════════════════════════════════════════════════════════════

const List<FontFeature> _ziffern = [FontFeature.tabularFigures()];

const _wochentage = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

/// „Di 06.10."
String _tagKurz(DateTime d) => '${_wochentage[d.weekday - 1]} '
    '${d.day.toString().padLeft(2, '0')}.'
    '${d.month.toString().padLeft(2, '0')}.';

bool _gleicherTag(DateTime a, DateTime? b) =>
    b != null && a.year == b.year && a.month == b.month && a.day == b.day;

/// Kilo mit Tausenderpunkt, eine Nachkommastelle nur wenn nötig:
/// „1.250", „270,5".
String _kgText(double kg) {
  final zehntel = (kg * 10).round();
  final ganz = (zehntel ~/ 10).toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => '.',
      );
  final rest = zehntel % 10;
  return rest == 0 ? ganz : '$ganz,$rest';
}

String _prozent(double anteil) => (anteil * 100).round().toString();
