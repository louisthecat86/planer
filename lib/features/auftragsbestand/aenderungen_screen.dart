import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/database_provider.dart';
import '../../core/services/auftragsbestand_vergleich.dart';
import '../../core/services/auto_backup_trigger.dart';
import '../../core/theme/app_stil.dart';
import '../../core/ui/bausteine.dart';
import '../bedarf/bedarf_screen.dart' show bedarfProvider, heuteProvider;
import '../whiteboard/whiteboard_provider.dart' show dailyTasksProvider;
import 'auftragsbestand_screen.dart' show auftragsbestandProvider;
import 'planung_pruefen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Daten für die Ansicht
// ═══════════════════════════════════════════════════════════════════════════

/// Was sich seit dem vorigen Auftragsbestand geändert hat — und welche
/// Planung deshalb nicht mehr passt.
class AenderungsAnsicht {
  const AenderungsAnsicht({
    required this.vergleich,
    this.konflikte = const [],
  });

  final BestandsVergleich vergleich;
  final List<PlanungsKonflikt> konflikte;

  /// Noch gar kein Auftragsbestand eingelesen.
  bool get ohneBericht => vergleich.neu.leer;
}

/// Lädt den aktuellen und den vorigen Auftragsbestand, vergleicht sie und
/// prüft die Planung gegen den aktuellen.
final auftragsbestandAenderungenProvider =
    FutureProvider.autoDispose<AenderungsAnsicht>((ref) async {
  final db = ref.watch(databaseProvider);
  // Um Mitternacht neu: Was gestern noch kam, ist heute vorbei.
  final heute = ref.watch(heuteProvider);
  final neu = await ladeBestand(db);
  final vorher = await ladeVorherigenBestand(db);
  final konflikte = await pruefePlanung(
    db,
    heute: heute,
    bestand: neu,
    vorher: vorher,
  );
  return AenderungsAnsicht(
    vergleich: vergleicheBestand(vorher, neu),
    konflikte: konflikte,
  );
});

/// Ein Eintrag der Änderungsliste: der Kopf eines Artikels (ohne Zeile)
/// oder eine seiner geänderten Zeilen.
typedef _Eintrag = ({ArtikelAenderung artikel, ZeilenAenderung? zeile});

// ═══════════════════════════════════════════════════════════════════════════
// Screen
// ═══════════════════════════════════════════════════════════════════════════

/// Änderungsansicht des Auftragsbestands: was seit dem vorigen Bericht
/// neu, mehr, weniger, verschoben, entfallen oder ausgeliefert ist.
///
/// Oben steht, welche Planung deshalb nicht mehr passt — Planungsaufträge
/// und Produktionen, die an Aufträgen hängen, die es so nicht mehr gibt —,
/// mit einem Vorschlag je Auftrag.
class AuftragsbestandAenderungenScreen extends ConsumerStatefulWidget {
  const AuftragsbestandAenderungenScreen({super.key});

  @override
  ConsumerState<AuftragsbestandAenderungenScreen> createState() =>
      _AenderungenState();
}

class _AenderungenState
    extends ConsumerState<AuftragsbestandAenderungenScreen> {
  final _suche = TextEditingController();

  /// Standard: die wesentlichen Änderungen. Was der Zeitraum mitbringt,
  /// was planmäßig rausging und was außerhalb liegt, lässt sich dazuholen.
  final Set<AenderungsArt> _arten = {
    for (final a in AenderungsArt.values)
      if (a.wesentlich) a,
  };

  bool _passtAn = false;

  @override
  void dispose() {
    _suche.dispose();
    super.dispose();
  }

  // ── Anpassen ─────────────────────────────────────────────────────────

  /// Übernimmt die Vorschläge zu [konflikte] — mehrere erst nach
  /// Rückfrage.
  Future<void> _uebernehme(List<PlanungsKonflikt> konflikte) async {
    if (konflikte.isEmpty) return;
    // Vor der ersten Wartestelle geholt: Container und Messenger überleben
    // auch, wenn jemand den Bildschirm währenddessen schließt.
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final db = ref.read(databaseProvider);
    final heute = ref.read(heuteProvider);

    if (konflikte.length > 1) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => _SammelDialog(konflikte: konflikte),
      );
      if (ok != true || !mounted) return;
    }

    setState(() => _passtAn = true);
    try {
      final n = await passeAn(db, konflikte, heute: heute);
      container
        ..invalidate(auftragsbestandAenderungenProvider)
        ..invalidate(auftragsbestandProvider)
        ..invalidate(bedarfProvider)
        ..invalidate(dailyTasksProvider);
      if (n > 0) {
        container
            .read(autoBackupTriggerProvider)
            .fireDebounced(reason: 'Planung an den Auftragsbestand angepasst');
      }
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Text(
            n == 0
                ? 'Nichts geändert — die Planung war schon angepasst.'
                : n == 1
                    ? 'Planung angepasst.'
                    : '$n Planungen angepasst.',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
            'Anpassen fehlgeschlagen — es wurde nichts geändert. ($e)',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _passtAn = false);
    }
  }

  // ── Filtern ──────────────────────────────────────────────────────────

  /// Die Änderungen, die zu Auswahl und Suche passen — je Artikel erst der
  /// Kopf, dann seine Zeilen.
  List<_Eintrag> _eintraege(BestandsVergleich v) {
    final suche = _suche.text.trim().toLowerCase();
    bool trifft(String? text) =>
        text != null && text.toLowerCase().contains(suche);

    final liste = <_Eintrag>[];
    for (final a in v.artikel) {
      final artikelTrifft = suche.isEmpty ||
          trifft(a.artikelnummer) ||
          trifft(a.bezeichnung) ||
          trifft(a.bezeichnung2);
      final zeilen = [
        for (final z in a.zeilen)
          if (_arten.contains(z.art) &&
              (artikelTrifft || trifft(z.beleg) || trifft(z.debitor)))
            z,
      ];
      if (zeilen.isEmpty) continue;
      liste.add((artikel: a, zeile: null));
      for (final z in zeilen) {
        liste.add((artikel: a, zeile: z));
      }
    }
    return liste;
  }

  // ── Aufbau ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ansicht = ref.watch(auftragsbestandAenderungenProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Änderungen im Auftragsbestand'),
        actions: [
          IconButton(
            onPressed: () =>
                ref.invalidate(auftragsbestandAenderungenProvider),
            icon: const Icon(Icons.refresh),
            tooltip: 'Neu prüfen — etwa nach Änderungen im Board',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          ansicht.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (a) => a.ohneBericht
                ? const Center(
                    child: LeerHinweis(
                      'Noch kein Auftragsbestand eingelesen — es gibt nichts '
                      'zu vergleichen.',
                      icon: Icons.local_shipping_outlined,
                    ),
                  )
                : _inhalt(context, a),
          ),
          if (_passtAn) const _Schleier(),
        ],
      ),
    );
  }

  Widget _inhalt(BuildContext context, AenderungsAnsicht ansicht) {
    final theme = Theme.of(context);
    final v = ansicht.vergleich;
    final konflikte = ansicht.konflikte;
    final eindeutig = [
      for (final k in konflikte)
        if (k.sicher) k,
    ];
    final eintraege = v.ohneVorher ? const <_Eintrag>[] : _eintraege(v);

    return CustomScrollView(
      slivers: [
        SliverPadding(
          // Ohne Änderungsliste darunter endet die Seite hier.
          padding: EdgeInsets.fromLTRB(14, 12, 14, v.ohneVorher ? 24 : 0),
          sliver: SliverList.list(
            children: [
              _Kopf(vergleich: v),
              if (konflikte.isNotEmpty) ...[
                const SizedBox(height: 14),
                _PruefBereich(
                  konflikte: konflikte,
                  eindeutig: eindeutig.length,
                  zweifelhaft: v.zweifelhaft,
                  onAlle: _passtAn ? null : () => _uebernehme(eindeutig),
                  onAnpassen: _passtAn
                      ? null
                      : (PlanungsKonflikt k) => _uebernehme([k]),
                  onVerwerfen: _passtAn
                      ? null
                      : (PlanungsKonflikt k) => _uebernehme([k.alsEntfallen]),
                ),
              ],
            ],
          ),
        ),
        if (!v.ohneVorher)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
            // Ein Bereich wie die übrigen — nur werden seine Zeilen erst
            // beim Scrollen gebaut, auch bei Hunderten Änderungen. Fläche
            // und Rand malen deshalb die Slivers: die weiße Fläche hinter
            // den Zeilen, den Rand davor, damit graue Kopfzeilen nicht über
            // ihn malen.
            sliver: DecoratedSliver(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: AppMasse.ecken,
              ),
              sliver: DecoratedSliver(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: AppMasse.ecken,
                  border: Border.all(color: theme.colorScheme.outline),
                ),
                sliver: SliverMainAxisGroup(
                  slivers: [
                    SliverToBoxAdapter(
                      child: _listenKopf(context, v, eintraege),
                    ),
                    if (eintraege.isEmpty)
                      SliverToBoxAdapter(
                        child: v.artikel.isEmpty
                            ? const LeerHinweis(
                                'Keine Änderungen gegenüber dem vorigen '
                                'Bericht.',
                                icon: Icons.check_circle_outline,
                              )
                            : const LeerHinweis(
                                'Keine Änderungen passen zu Suche und '
                                'Auswahl.',
                                icon: Icons.filter_alt_off_outlined,
                              ),
                      )
                    else
                      SliverList.builder(
                        itemCount: eintraege.length,
                        itemBuilder: (context, i) {
                          final e = eintraege[i];
                          final zeile = e.zeile;
                          return zeile == null
                              ? _ArtikelKopf(
                                  artikel: e.artikel,
                                  erste: i == 0,
                                )
                              : _AenderungsZeile(zeile: zeile);
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Kopf der Änderungsliste: Titel mit Anzahl, Suche und Auswahl der
  /// Arten, darunter die Spaltenköpfe.
  Widget _listenKopf(
    BuildContext context,
    BestandsVergleich v,
    List<_Eintrag> eintraege,
  ) {
    final theme = Theme.of(context);
    final zeilen = eintraege.where((e) => e.zeile != null).length;
    final artikel = eintraege.length - zeilen;
    final stil = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BereichKopf(
          titel: 'Änderungen seit dem vorigen Bericht',
          icon: Icons.difference_outlined,
          untertitel: zeilen == 0
              ? null
              : '$zeilen ${zeilen == 1 ? 'Zeile' : 'Zeilen'} bei $artikel '
                  '${artikel == 1 ? 'Artikel' : 'Artikeln'}',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Rahmen, Ecken und Dichte des Felds kommen aus dem Theme.
              SizedBox(
                width: 300,
                child: TextField(
                  controller: _suche,
                  decoration: const InputDecoration(
                    labelText: 'Suche (Nummer, Bezeichnung, Kunde, Beleg)',
                    prefixIcon: Icon(Icons.search, size: 18),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              for (final art in AenderungsArt.values)
                if (v.anzahl(art) > 0)
                  FilterChip(
                    label: Text('${art.label} (${v.anzahl(art)})'),
                    tooltip: _artErklaerung(art),
                    selected: _arten.contains(art),
                    onSelected: (an) => setState(() {
                      if (an) {
                        _arten.add(art);
                      } else {
                        _arten.remove(art);
                      }
                    }),
                  ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _app(theme).leiste,
            border: Border(
              top: BorderSide(color: theme.colorScheme.outline),
              bottom: BorderSide(color: theme.colorScheme.outline),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: _Spalten.art,
                child: Text('Änderung', style: stil),
              ),
              SizedBox(
                width: _Spalten.tag,
                child: Text('Versand', style: stil),
              ),
              Expanded(child: Text('Beleg · Kunde', style: stil)),
              const SizedBox(width: _Spalten.luecke),
              SizedBox(
                width: _Spalten.menge,
                child: Text(
                  'Menge',
                  textAlign: TextAlign.right,
                  style: stil,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Kopf
// ═══════════════════════════════════════════════════════════════════════════

/// Stand und Zeitraum beider Berichte, die Änderungen als Kennzahlen und
/// die Hinweise, ob der neue Bericht zum bisherigen passt.
class _Kopf extends StatelessWidget {
  const _Kopf({required this.vergleich});

  final BestandsVergleich vergleich;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = vergleich;
    final grau = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    // Wie die Kurzfassung beim Einlesen: nur, was für die Planung zählt.
    final arten = [
      for (final a in AenderungsArt.values)
        if (a.wesentlich && v.anzahl(a) > 0) a,
    ];

    // „Jetzt" und „Vorher" untereinander, die Angaben bündig.
    Widget bericht(String wann, BestandsStand s) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 56,
              child: Text(
                wann,
                style: grau?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              child: Text(_standText(s), style: theme.textTheme.bodySmall),
            ),
          ],
        );

    return Bereich(
      titel: 'Vergleich',
      icon: Icons.compare_arrows,
      aktionen: [
        TextButton.icon(
          onPressed: () => _zeigeErklaerung(context),
          icon: const Icon(Icons.help_outline, size: 16),
          label: const Text('So wird verglichen'),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
      innenAbstand: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          bericht('Jetzt', v.neu),
          if (!v.ohneVorher) ...[
            const SizedBox(height: 2),
            bericht('Vorher', v.vorher),
          ],
          const SizedBox(height: 10),
          if (v.ohneVorher)
            const HinweisBox(
              'Noch kein Vergleich: Bisher ist erst ein Bericht eingelesen. '
              'Ab dem nächsten Einlesen steht hier, was sich seitdem '
              'geändert hat. Die Planung wird trotzdem schon gegen den '
              'Bericht geprüft.',
            )
          else if (arten.isEmpty)
            Text(
              'Keine wesentlichen Änderungen seit dem vorigen Bericht.',
              style: theme.textTheme.bodyMedium,
            )
          else
            Wrap(
              spacing: 28,
              runSpacing: 10,
              children: [
                for (final a in arten)
                  Kennzahl(
                    wert: '${v.anzahl(a)}',
                    label: a.label,
                    farbe: _artFarbe(theme, a),
                  ),
              ],
            ),
          for (final h in v.hinweise) ...[
            const SizedBox(height: 8),
            HinweisBox(
              h.text,
              art: h.ernst ? StatusArt.warnung : StatusArt.info,
            ),
          ],
        ],
      ),
    );
  }
}

const _soWirdVerglichen =
    'Verglichen wird der zuletzt eingelesene Bericht mit dem davor, Zeile '
    'für Zeile. Eine Zeile ist ein Auftrag (Beleg) für einen Artikel an '
    'einem Versandtag.\n\n'
    '• neu: zum ersten Mal im Bericht, an einem Tag, den auch der vorige '
    'zeigte.\n'
    '• erstmals im Zeitraum: neu, aber an einem Tag, den der vorige '
    'Bericht gar nicht zeigte — etwa weil der Zeitraum jetzt weiter '
    'reicht. Ob neu bestellt, lässt sich daran nicht sagen.\n'
    '• mehr / weniger: dieselbe Zeile mit anderer Menge.\n'
    '• verschoben: derselbe Beleg an einem anderen Versandtag.\n'
    '• entfallen: fehlt, obwohl der Versandtag noch kommt — storniert oder '
    'geändert.\n'
    '• ausgeliefert: fehlt, und der Versandtag ist vorbei oder heute. Ob '
    'ausgeliefert oder storniert, steht nicht im Bericht. Für die Planung '
    'ist es dasselbe: Die Menge wird nicht mehr gebraucht.\n'
    '• außerhalb des Zeitraums: Der neue Bericht deckt den Tag nicht ab und '
    'sagt darüber nichts.\n\n'
    'Erledigt oder nur herausgefiltert? Den Zeitraum liest die App aus dem '
    'Berichtskopf — eine Zeile außerhalb gilt nie als erledigt. Filter nach '
    'Kunden, Artikeln oder Lagerorten stehen dagegen nicht im Bericht. '
    'Deshalb prüft die App beim Einlesen, ob auffällig viele künftige '
    'Aufträge fehlen: Die verschwinden sonst nicht, höchstens einzelne '
    'werden storniert. Fehlen sie doch, fragt sie nach, bevor sie den '
    'Bericht übernimmt.\n\n'
    'Am zuverlässigsten: in Navision immer mit demselben Grundfilter '
    'aufrufen — alle Kunden, alle Artikel, nur den Zeitraum anpassen. '
    'Beginn ein paar Tage vor heute, damit auch überfällige Aufträge dabei '
    'sind. Wer nur einen Kunden sehen will, filtert hier in der App über '
    'die Suche, nicht in Navision.\n\n'
    'Planung prüfen: Planungsaufträge und Produktionen, die für bestimmte '
    'Aufträge angelegt wurden, hängen an Beleg und Versandtag. Ändert sich '
    'ein Auftrag, schlägt die App vor, die Planung mitzunehmen: verschoben → '
    'an den neuen Tag hängen, weniger → verringern, entfallen oder '
    'ausgeliefert → aus der Planung nehmen. Ist ein „verschobener" Auftrag '
    'in Wahrheit ein neuer, weil der alte entfallen ist: „Nicht '
    'verschoben". Bis das geklärt ist, ist der Auftrag im Auftragsbestand '
    'gesperrt und lässt sich nicht ein zweites Mal bündeln. Bei '
    'Produktionen im Board ändert die App nur die Zuordnung zu den '
    'Aufträgen, nie Menge oder Tag — das entscheidet der Planer im Board.';

Future<void> _zeigeErklaerung(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('So wird verglichen'),
      content: const SizedBox(
        width: 540,
        child: SingleChildScrollView(child: Text(_soWirdVerglichen)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Schließen'),
        ),
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Planung prüfen
// ═══════════════════════════════════════════════════════════════════════════

/// Der Abschnitt „Planung prüfen": warum, die Sammelaktion im Kopf, darunter
/// je Auftrag Befund, betroffene Planung und Vorschlag.
class _PruefBereich extends StatelessWidget {
  const _PruefBereich({
    required this.konflikte,
    required this.eindeutig,
    required this.zweifelhaft,
    required this.onAlle,
    required this.onAnpassen,
    required this.onVerwerfen,
  });

  final List<PlanungsKonflikt> konflikte;

  /// Davon eindeutig — nur die übernimmt die Sammelaktion.
  final int eindeutig;

  /// Der Bericht sieht gefiltert oder verrutscht aus: keine Sammelaktion.
  final bool zweifelhaft;

  /// null, solange gerade angepasst wird.
  final VoidCallback? onAlle;
  final void Function(PlanungsKonflikt k)? onAnpassen;

  /// Nur bei „verschoben": Es ist kein Umzug — der alte Auftrag ist
  /// entfallen, der am neuen Tag ist ein eigener.
  final void Function(PlanungsKonflikt k)? onVerwerfen;

  @override
  Widget build(BuildContext context) {
    final n = konflikte.length;
    final anpassen = onAnpassen;
    final verwerfen = onVerwerfen;

    return Bereich(
      titel: 'Planung prüfen',
      icon: Icons.rule,
      untertitel: '$n ${n == 1 ? 'Auftrag' : 'Aufträge'}'
          '${eindeutig == n ? '' : ', davon $eindeutig eindeutig'}',
      aktionen: [
        FilledButton.tonalIcon(
          onPressed: zweifelhaft || eindeutig == 0 ? null : onAlle,
          icon: const Icon(Icons.done_all, size: 18),
          label: Text('Alle eindeutigen übernehmen ($eindeutig)'),
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(width: 4),
      ],
      innenAbstand: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const HinweisBox(
                  'An diesen Aufträgen hängt Planung, die nicht mehr zum '
                  'Bericht passt. Ein verschobener Auftrag stünde am neuen '
                  'Tag sonst ein zweites Mal als offen da; was entfallen '
                  'oder ausgeliefert ist, würde trotzdem produziert.',
                  art: StatusArt.fehler,
                  icon: Icons.rule,
                ),
                if (zweifelhaft) ...[
                  const SizedBox(height: 8),
                  const HinweisBox(
                    'Der Bericht sieht gefiltert oder verrutscht aus '
                    '(Hinweise oben). Vorschläge deshalb nur einzeln '
                    'übernehmen — oder erst einen vollständigen Bericht '
                    'einlesen.',
                    art: StatusArt.warnung,
                  ),
                ],
              ],
            ),
          ),
          for (final k in konflikte)
            _KonfliktEintrag(
              konflikt: k,
              onAnpassen: anpassen == null ? null : () => anpassen(k),
              onVerwerfen: verwerfen == null || k.art != PruefArt.verschoben
                  ? null
                  : () => verwerfen(k),
            ),
        ],
      ),
    );
  }
}

/// Ein Auftrag, an dem Planung hängt, die nicht mehr passt — mit Befund,
/// der betroffenen Planung und dem Vorschlag samt Knopf.
class _KonfliktEintrag extends StatelessWidget {
  const _KonfliktEintrag({
    required this.konflikt,
    required this.onAnpassen,
    this.onVerwerfen,
  });

  final PlanungsKonflikt konflikt;
  final VoidCallback? onAnpassen;

  /// Nur bei „verschoben": Es ist kein Umzug — der alte Auftrag ist
  /// entfallen, der am neuen Tag ist ein eigener.
  final VoidCallback? onVerwerfen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final k = konflikt;
    final grau = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final fett = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );

    // Eine Zeile im Bereich, durch eine Linie von der vorigen getrennt —
    // vorher stand jeder Auftrag auf einer eigenen Karte.
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _pruefMarke(theme, k.art),
              if (!k.sicher)
                const StatusMarke('bitte prüfen', art: StatusArt.warnung),
              Text(
                k.artikelnummer,
                style: fett?.copyWith(fontFeatures: _ziffern),
              ),
              if (k.bezeichnung.isNotEmpty) Text(k.bezeichnung, style: fett),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              k.beleg,
              if (k.debitor.isNotEmpty) k.debitor,
              'Versand ${_tagKurz(k.warenausgang)}',
            ].join(' · '),
            style: grau,
          ),
          const SizedBox(height: 8),
          Text(_befund(k), style: theme.textTheme.bodyMedium),
          for (final v in k.verplant)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    v.istVormerkung
                        ? Icons.pending_actions
                        : Icons.view_week_outlined,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_verplanungText(v), style: grau)),
                ],
              ),
            ),
          const SizedBox(height: 10),
          // Vorschlag und Knopf als eine Einheit — der Knopf tut genau, was
          // links steht.
          HinweisBox(
            _vorschlag(k),
            icon: Icons.lightbulb_outline,
            aktion: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (k.art == PruefArt.verschoben) ...[
                  Tooltip(
                    message: 'Der alte Auftrag ist entfallen, der am neuen '
                        'Tag ist ein eigener: die alte Zeile aus der Planung '
                        'nehmen. Der neue lässt sich danach normal bündeln.',
                    child: TextButton(
                      onPressed: onVerwerfen,
                      child: const Text('Nicht verschoben'),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                // Gefüllt, nicht getönt: Die getönte Fläche wäre auf dem
                // Blau des Hinweises kaum zu sehen.
                FilledButton(
                  onPressed: onAnpassen,
                  child: Text(_aktion(k)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Rückfrage vor der Sammelaktion.
class _SammelDialog extends StatelessWidget {
  const _SammelDialog({required this.konflikte});

  final List<PlanungsKonflikt> konflikte;

  @override
  Widget build(BuildContext context) {
    int anzahl(bool Function(PlanungsKonflikt k) passt) =>
        konflikte.where(passt).length;
    final umhaengen = anzahl((k) => k.art == PruefArt.verschoben);
    final verringern = anzahl((k) => k.art == PruefArt.weniger);
    final heraus = anzahl(
      (k) => k.art == PruefArt.entfallen || k.art == PruefArt.ausgeliefert,
    );
    final produktionen = anzahl((k) => k.mitProduktion);

    return AlertDialog(
      title: Text('${konflikte.length} Vorschläge übernehmen?'),
      content: SizedBox(
        width: 480,
        child: Text(
          [
            if (umhaengen > 0) '• $umhaengen × an den neuen Versandtag hängen',
            if (verringern > 0) '• $verringern × verringern',
            if (heraus > 0) '• $heraus × aus der Planung nehmen',
            '',
            'Planungsaufträge werden angepasst — bleibt von einem nichts '
                'übrig, wird er gelöscht.',
            if (produktionen > 0)
              'Bei Produktionen im Board ändert sich nur die Zuordnung zu '
                  'den Aufträgen, Menge und Tag bleiben. Ob sie noch so '
                  'gebraucht werden, im Board entscheiden.',
          ].join('\n'),
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

/// Was an der Zeile nicht mehr passt.
String _befund(PlanungsKonflikt k) {
  final neu = k.neuerWarenausgang;
  return switch (k.art) {
    PruefArt.weniger => 'Bestellt sind jetzt ${_kg(k.imBerichtKg)} kg, '
        'verplant ${_kg(k.geplantKg)} kg — ${_kg(k.zuVielKg)} kg zu viel.',
    PruefArt.verschoben => [
        'Derselbe Auftrag steht jetzt am '
            '${neu == null ? '?' : _tagKurz(neu)} statt am '
            '${_tagKurz(k.warenausgang)}.',
        if ((k.imBerichtKg - k.geplantKg).abs() >= 0.01)
          'Am neuen Tag sind ${_kg(k.imBerichtKg)} kg bestellt.',
        if (!k.sicher)
          'Dass es derselbe Auftrag ist, lässt sich nicht sicher sagen.',
      ].join(' '),
    PruefArt.ausgeliefert => k.vorZeitraum
        ? 'Der Versandtag liegt vor dem Zeitraum des Berichts — ob der '
            'Auftrag noch offen ist, zeigt er nicht. Vermutlich '
            'ausgeliefert.'
        : 'Nicht mehr im Bericht, der Versandtag ist vorbei — vermutlich '
            'ausgeliefert.',
    PruefArt.entfallen => 'Nicht mehr im Bericht, obwohl der Versandtag '
        'noch kommt — storniert oder geändert.',
  };
}

/// Was der Vorschlag tut.
String _vorschlag(PlanungsKonflikt k) {
  final auftrag = k.mitVormerkung;
  final produktion = k.mitProduktion;
  final zuViel = k.zuVielKg >= 0.01;
  final neu = k.neuerWarenausgang;
  final frueher = neu != null && neu.isBefore(k.warenausgang);
  const bleibt = 'Die Produktion im Board behält Menge und Tag.';

  return switch (k.art) {
    PruefArt.verschoben => [
        'Vorschlag: die Planung an den neuen Tag hängen'
            '${zuViel ? ' und um ${_kg(k.zuVielKg)} kg verringern' : ''}.',
        if (auftrag && frueher)
          'Der Termin des Planungsauftrags rückt entsprechend vor.',
        if (k.produktionZuSpaet)
          'Danach die Produktion im Board vorziehen — sie wird erst nach '
              'dem neuen Versandtag fertig.',
        'Bis das geklärt ist, ist der Auftrag im Auftragsbestand gesperrt.',
      ].join(' '),
    PruefArt.weniger => auftrag && !produktion
        ? 'Vorschlag: den Planungsauftrag um ${_kg(k.zuVielKg)} kg '
            'verringern.'
        : !auftrag
            ? 'Vorschlag: die Zuordnung der Produktion auf '
                '${_kg(k.imBerichtKg)} kg kürzen. $bleibt Ob sie kleiner '
                'werden soll, im Board entscheiden.'
            : 'Vorschlag: um ${_kg(k.zuVielKg)} kg verringern — zuerst '
                'beim Planungsauftrag, den Rest bei der Zuordnung der '
                'Produktion. $bleibt',
    PruefArt.ausgeliefert || PruefArt.entfallen => [
        if (auftrag)
          'Vorschlag: aus dem Planungsauftrag nehmen — seine Menge sinkt um '
              'den noch offenen Teil. Bleibt nichts übrig, wird er '
              'gelöscht.'
        else
          'Vorschlag: die Zuordnung lösen.',
        if (produktion)
          '$bleibt Ihre Ware zählt dann für andere Aufträge oder fürs '
              'Lager — wird sie nicht mehr gebraucht, im Board ändern oder '
              'löschen.',
      ].join(' '),
  };
}

String _aktion(PlanungsKonflikt k) => switch (k.art) {
      PruefArt.verschoben => 'Umhängen',
      PruefArt.weniger => 'Verringern',
      PruefArt.ausgeliefert || PruefArt.entfallen =>
        k.mitVormerkung ? 'Aus der Planung nehmen' : 'Zuordnung lösen',
    };

String _verplanungText(Verplanung v) {
  final tag = v.tag;
  if (v.istVormerkung) {
    return 'Planungsauftrag, noch nicht im Board: ${_kg(v.kg)} kg'
        '${tag == null ? '' : ', spätestens ${_tagKurz(tag)}'}';
  }
  final beginn = v.beginn;
  final wann = tag == null
      ? ''
      : beginn != null && beginn.isBefore(tag)
          ? ', ${_tagKurz(beginn)}–${_tagKurz(tag)}'
          : ', am ${_tagKurz(tag)}';
  return 'Produktion im Board: ${_kg(v.kg)} kg für diesen Auftrag$wann';
}

// ═══════════════════════════════════════════════════════════════════════════
// Änderungsliste
// ═══════════════════════════════════════════════════════════════════════════

/// Spaltenbreiten der Änderungsliste — für Kopf und Zeilen dieselben.
abstract final class _Spalten {
  static const double art = 180;
  static const double tag = 170;
  static const double menge = 210;

  /// Abstand vor der Menge.
  static const double luecke = 12;
}

/// Kopf eines Artikels in der Änderungsliste: Nummer, Bezeichnung, Lager —
/// grau hinterlegt wie eine Gruppenzeile in Navision.
class _ArtikelKopf extends StatelessWidget {
  const _ArtikelKopf({required this.artikel, required this.erste});

  final ArtikelAenderung artikel;

  /// Erster Artikel der Liste: ohne Linie darüber — dort steht schon die
  /// der Spaltenköpfe.
  final bool erste;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = artikel;
    final grau = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final fett = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final zusatz = a.bezeichnung2;
    final vorher = a.lagerVorherKg;
    final jetzt = a.lagerKg;
    final String? lager;
    if (jetzt == null) {
      lager = vorher == null ? null : 'Lager vorher ${_kg(vorher)} kg';
    } else if (vorher != null && a.lagerGeaendert) {
      lager = 'Lager ${_kg(vorher)} → ${_kg(jetzt)} kg';
    } else {
      lager = 'Lager ${_kg(jetzt)} kg';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
      decoration: BoxDecoration(
        color: _app(theme).leiste,
        border: erste
            ? null
            : Border(top: BorderSide(color: theme.colorScheme.outline)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            a.artikelnummer,
            style: fett?.copyWith(fontFeatures: _ziffern),
          ),
          if (a.bezeichnung.isNotEmpty) Text(a.bezeichnung, style: fett),
          if (zusatz != null && zusatz.isNotEmpty) Text(zusatz, style: grau),
          if (lager != null) Text(lager, style: grau),
          if (a.neuImBericht)
            const StatusMarke('neu im Bericht', art: StatusArt.ok),
          if (a.nichtMehrImBericht) const StatusMarke('nicht mehr im Bericht'),
        ],
      ),
    );
  }
}

/// Eine geänderte Auftragszeile — dieselben Spalten wie der Kopf.
class _AenderungsZeile extends StatelessWidget {
  const _AenderungsZeile({required this.zeile});

  final ZeilenAenderung zeile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final z = zeile;
    final vorher = z.warenausgangVorher;
    final jetzt = z.warenausgang;
    final tag = z.art == AenderungsArt.verschoben &&
            vorher != null &&
            jetzt != null
        ? '${_tagKurz(vorher)} → ${_tagKurz(jetzt)}'
        : _tagKurz(z.tag);
    final menge = switch (z.art) {
      AenderungsArt.mehr || AenderungsArt.weniger =>
        '${_kg(z.kgVorher)} → ${_kg(z.kg)} kg '
            '(${_mitVorzeichen(z.differenzKg)})',
      AenderungsArt.verschoben => z.differenzKg.abs() < 0.005
          ? '${_kg(z.kg)} kg'
          : '${_kg(z.kgVorher)} → ${_kg(z.kg)} kg',
      AenderungsArt.neu || AenderungsArt.erstmals => '${_kg(z.kg)} kg',
      AenderungsArt.entfallen ||
      AenderungsArt.ausgeliefert ||
      AenderungsArt.ausserhalb =>
        '${_kg(z.kgVorher)} kg',
    };
    final weg = z.warenausgang == null;
    final stil = theme.textTheme.bodyMedium;
    final zahlen = stil?.copyWith(fontFeatures: _ziffern);

    return Container(
      constraints: const BoxConstraints(minHeight: 34),
      padding: const EdgeInsets.fromLTRB(12, 3, 12, 3),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _Spalten.art,
            child: Align(
              alignment: Alignment.centerLeft,
              heightFactor: 1,
              // Wird es mit großer Schrift zu eng, wird die Marke kleiner,
              // statt über den Rand zu laufen.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: _artMarke(theme, z.art),
              ),
            ),
          ),
          SizedBox(
            width: _Spalten.tag,
            child: Text(tag, maxLines: 1, style: zahlen),
          ),
          Expanded(
            child: Text(
              [z.beleg, if (z.debitor.isNotEmpty) z.debitor].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: stil,
            ),
          ),
          const SizedBox(width: _Spalten.luecke),
          SizedBox(
            width: _Spalten.menge,
            child: Text(
              menge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              // Was nicht mehr im Bericht steht, durchgestrichen.
              style: zahlen?.copyWith(
                fontWeight: FontWeight.w600,
                decoration: weg ? TextDecoration.lineThrough : null,
                color: weg ? theme.colorScheme.onSurfaceVariant : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _artErklaerung(AenderungsArt art) => switch (art) {
      AenderungsArt.neu =>
        'Zum ersten Mal im Bericht, an einem Tag, den auch der vorige zeigte.',
      AenderungsArt.erstmals => 'Neu, aber an einem Tag, den der vorige '
          'Bericht gar nicht zeigte — etwa weil der Zeitraum weiter reicht.',
      AenderungsArt.mehr => 'Dieselbe Zeile mit mehr Menge.',
      AenderungsArt.weniger => 'Dieselbe Zeile mit weniger Menge.',
      AenderungsArt.verschoben =>
        'Derselbe Beleg an einem anderen Versandtag.',
      AenderungsArt.entfallen => 'Fehlt, obwohl der Versandtag noch kommt — '
          'storniert oder geändert.',
      AenderungsArt.ausgeliefert => 'Fehlt, der Versandtag ist vorbei oder '
          'heute — vermutlich ausgeliefert.',
      AenderungsArt.ausserhalb => 'Der neue Bericht deckt den Versandtag '
          'nicht ab und sagt darüber nichts.',
    };

// ═══════════════════════════════════════════════════════════════════════════
// Bausteine
// ═══════════════════════════════════════════════════════════════════════════

/// Die Statusfarben der App — dieselben wie im Board und in den Marken,
/// jeweils passend zu hellem und dunklem Modus.
AppFarben _app(ThemeData theme) =>
    theme.extension<AppFarben>() ?? AppFarben.hell;

/// Lila für „verschoben" — wie im Auftragsbestand. Diesen Zustand gibt es
/// nur hier, deshalb steht Lila nicht bei den Statusfarben der App.
Color _lila(ThemeData theme) => theme.brightness == Brightness.dark
    ? const Color(0xFFC084FC)
    : const Color(0xFF7E22CE);

/// Ziffern gleich breit, damit Nummern und Mengen untereinander stehen.
const List<FontFeature> _ziffern = [FontFeature.tabularFigures()];

/// Farbe einer Änderungsart als Wert einer Kennzahl — null: normale
/// Textfarbe.
Color? _artFarbe(ThemeData theme, AenderungsArt a) => switch (a) {
      AenderungsArt.neu || AenderungsArt.mehr => _app(theme).ok,
      AenderungsArt.weniger => _app(theme).warnung,
      AenderungsArt.verschoben => _lila(theme),
      AenderungsArt.entfallen => _app(theme).fehler,
      AenderungsArt.erstmals ||
      AenderungsArt.ausgeliefert ||
      AenderungsArt.ausserhalb =>
        null,
    };

/// Die Marke einer Änderungsart: grün mehr, orange weniger, rot entfallen,
/// lila verschoben, grau, was für die Planung nichts ändert.
Widget _artMarke(ThemeData theme, AenderungsArt a) => switch (a) {
      AenderungsArt.verschoben => _Marke(text: a.label, farbe: _lila(theme)),
      AenderungsArt.neu || AenderungsArt.mehr =>
        StatusMarke(a.label, art: StatusArt.ok),
      AenderungsArt.weniger => StatusMarke(a.label, art: StatusArt.warnung),
      AenderungsArt.entfallen => StatusMarke(a.label, art: StatusArt.fehler),
      AenderungsArt.erstmals ||
      AenderungsArt.ausgeliefert ||
      AenderungsArt.ausserhalb =>
        StatusMarke(a.label),
    };

/// Die Marke eines Befunds in „Planung prüfen" — in denselben Farben.
Widget _pruefMarke(ThemeData theme, PruefArt p) => switch (p) {
      PruefArt.verschoben => _Marke(text: p.label, farbe: _lila(theme)),
      PruefArt.weniger => StatusMarke(p.label, art: StatusArt.warnung),
      PruefArt.entfallen => StatusMarke(p.label, art: StatusArt.fehler),
      PruefArt.ausgeliefert => StatusMarke(p.label),
    };

/// Marke in einer Farbe, die die [StatusMarke] nicht kennt — hier das Lila
/// für „verschoben". Sieht aus wie eine [StatusMarke]: blasse Fläche,
/// Schrift in der Farbe, kein Rand.
class _Marke extends StatelessWidget {
  const _Marke({required this.text, required this.farbe});

  final String text;
  final Color farbe;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        // Deckend gemischt statt durchscheinend: So sieht die Marke auf
        // weißen und grauen Flächen gleich aus.
        color: Color.alphaBlend(
          farbe.withValues(alpha: 0.12),
          Theme.of(context).colorScheme.surface,
        ),
        borderRadius: AppMasse.eckenKlein,
      ),
      child: Text(
        text,
        maxLines: 1,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: farbe,
        ),
      ),
    );
  }
}

/// Sperrt die Bedienung, solange die Planung angepasst wird.
class _Schleier extends StatelessWidget {
  const _Schleier();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned.fill(
      child: ColoredBox(
        color: theme.colorScheme.surface.withValues(alpha: 0.7),
        child: const Center(child: CircularProgressIndicator()),
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

/// „Stand 01.10.2026, 06:05 · Warenausgang 28.09.–31.10.2026 · eingelesen
/// 01.10., 06:10"
String _standText(BestandsStand s) {
  final stand = s.stand;
  final von = s.von;
  final bis = s.bis;
  final importiert = s.importiertAm;
  return [
    if (stand != null) 'Stand ${_datumLang(stand)}, ${_uhrzeit(stand)}',
    if (von != null && bis != null)
      'Warenausgang ${_datumKurz(von)}–${_datumLang(bis)}',
    if (importiert != null)
      'eingelesen ${_datumKurz(importiert)}, ${_uhrzeit(importiert)}',
  ].join(' · ');
}

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

/// „+20" oder „−4,5".
String _mitVorzeichen(double v) => '${v < 0 ? '−' : '+'}${_kg(v.abs())}';
