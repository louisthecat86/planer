import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/product_groups.dart';
import '../../../core/database/database.dart';
import '../../../core/services/auto_backup_trigger.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/fehler_text.dart';
import '../../../core/utils/format.dart';
import '../entwicklung_format.dart';
import '../spezifikation/spez_angaben.dart' show SpezAngaben;
import 'freigabe.dart';

/// Öffnet den Artikel im Planer.
void oeffneArtikel(BuildContext context, String artikelId) =>
    context.pushNamed<void>(
      'articleDetail',
      pathParameters: {'productId': artikelId},
    );

/// Die Freigabe in der Übersicht eines Projekts: Artikel, Stand und der
/// Abgleich mit den erfassten Produktionen.
class ProjektFreigabe extends ConsumerWidget {
  const ProjektFreigabe({super.key, required this.projekt});

  final EntwicklungsProjekt projekt;

  Future<void> _freigeben(
    BuildContext context,
    WidgetRef ref,
    List<FreigabeStand> staende,
  ) async {
    final artikelId = await showDialog<String>(
      context: context,
      builder: (_) => FreigabeDialog(projekt: projekt, staende: staende),
    );
    if (artikelId == null || !context.mounted) return;
    ref.invalidate(freigabeUebersichtProvider(projekt.id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Freigegeben.'),
        action: SnackBarAction(
          label: 'Artikel öffnen',
          onPressed: () => oeffneArtikel(context, artikelId),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final uebersicht = ref.watch(freigabeUebersichtProvider(projekt.id));
    return Bereich(
      titel: 'Freigabe',
      icon: Icons.verified_outlined,
      innenAbstand: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: uebersicht.when(
        skipLoadingOnReload: true,
        loading: () => const Padding(
          padding: EdgeInsets.all(12),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => HinweisBox(
          fehlerText(e),
          art: StatusArt.fehler,
          titel: 'Die Freigabe ließ sich nicht laden',
          auswaehlbar: true,
        ),
        data: (u) {
          final artikel = u.artikel;
          final stand = u.stand;
          final abgleich = u.abgleich;
          final freigegeben = projekt.freigegebenAm;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (artikel == null)
                Text(
                  projekt.artikelId == null
                      ? 'Noch nicht als Artikel freigegeben.'
                      : 'Der freigegebene Artikel ist gelöscht.',
                  style: theme.textTheme.bodyMedium,
                )
              else ...[
                InkWell(
                  onTap: () => oeffneArtikel(context, artikel.id),
                  child: Text(
                    '${artikel.artikelnummer} · ${artikel.artikelbezeichnung}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (stand != null) stand.label,
                    if (freigegeben != null)
                      'freigegeben am ${Format.datum(freigegeben)}',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(color: grau),
                ),
                const SizedBox(height: 10),
                if (abgleich == null)
                  Text(
                    'Noch keine Produktion mit Roh- und Fertigware erfasst — '
                    'dann vergleicht sich hier der Verlust mit der Rezeptur.',
                    style: theme.textTheme.bodySmall?.copyWith(color: grau),
                  )
                else
                  VerlustAbgleichAnzeige(abgleich: abgleich),
              ],
              const SizedBox(height: 10),
              if (u.staende.isEmpty)
                const HinweisBox(
                  'Freigeben lässt sich ein abgeschlossener Rezepturstand. '
                  'Lege eine Rezeptur des Projekts an und schließe einen '
                  'Stand ab.',
                )
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: () => _freigeben(context, ref, u.staende),
                    icon: const Icon(Icons.verified_outlined, size: 18),
                    label: Text(
                      artikel == null ? 'Freigeben …' : 'Erneut freigeben …',
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Gemessener gegen gerechneten Verlust — und was das für den
/// Fleischanteil auf dem Etikett heißt.
class VerlustAbgleichAnzeige extends StatelessWidget {
  const VerlustAbgleichAnzeige({super.key, required this.abgleich});

  final VerlustAbgleich abgleich;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = abgleich;
    final quelle = a.produktionen == 1
        ? 'der letzten Produktion'
        : 'Ø der letzten ${a.produktionen} Produktionen';
    final zeilen = <Widget>[
      Text(
        'Verlust $quelle: ${prozentText(a.gemessenProzent)} — die Rezeptur '
        'rechnet mit ${prozentText(a.rezepturProzent)}.',
        style: theme.textTheme.bodySmall,
      ),
    ];
    final fr = a.fleischRezeptur;
    final fg = a.fleischGemessen;
    if (a.fleischZuHoch && fr != null && fg != null) {
      zeilen.addAll([
        const SizedBox(height: 6),
        HinweisBox(
          'Mit dem gemessenen Verlust enthält das Produkt '
          '${prozentText(fg)} Fleisch — die Rezeptur und damit das Etikett '
          'nennen ${prozentText(fr)}. Verlust in der Rezeptur anpassen und '
          'die Mengenangaben prüfen.',
          art: StatusArt.fehler,
          titel: 'Fleischanteil zu hoch angegeben',
        ),
      ]);
    } else if (a.fleischZuNiedrig && fr != null && fg != null) {
      zeilen.addAll([
        const SizedBox(height: 6),
        HinweisBox(
          'Mit dem gemessenen Verlust enthält das Produkt '
          '${prozentText(fg)} Fleisch — das Etikett nennt nur '
          '${prozentText(fr)}. Das ist zulässig, verschenkt aber Anteil.',
          art: StatusArt.info,
          titel: 'Fleischanteil vorsichtig angegeben',
        ),
      ]);
    } else if (a.verlustWeichtAb) {
      zeilen.addAll([
        const SizedBox(height: 6),
        HinweisBox(
          'Der gemessene Verlust weicht um '
          '${prozentText(a.differenz.abs())}punkte ab — Nährwerte und '
          'Mengenangaben stimmen nur ungefähr.',
          art: StatusArt.warnung,
        ),
      ]);
    } else {
      zeilen.addAll([
        const SizedBox(height: 6),
        const HinweisBox(
          'Rezeptur und Produktion passen zusammen.',
          art: StatusArt.ok,
        ),
      ]);
    }
    final rz = a.zutatenlisteRezeptur;
    final gz = a.zutatenlisteGemessen;
    if (rz != null && gz != null && rz != gz) {
      zeilen.addAll([
        const SizedBox(height: 8),
        Text(
          'Zutatenliste mit gemessenem Verlust:',
          style: theme.textTheme.labelSmall,
        ),
        SelectableText(gz, style: theme.textTheme.bodySmall),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: zeilen,
    );
  }
}

/// Einen Stand freigeben: Artikelnummer, Bezeichnung, Produktgruppe und
/// Haltbarkeit — vorbelegt mit dem, was im Projekt schon steht; bei einem
/// vorhandenen Artikel die Felder, die sich ändern.
class FreigabeDialog extends ConsumerStatefulWidget {
  const FreigabeDialog({
    super.key,
    required this.projekt,
    required this.staende,
  });

  final EntwicklungsProjekt projekt;

  /// Die abgeschlossenen Stände, neueste zuerst.
  final List<FreigabeStand> staende;

  @override
  ConsumerState<FreigabeDialog> createState() => _FreigabeDialogState();
}

class _FreigabeDialogState extends ConsumerState<FreigabeDialog> {
  late String _versionId = widget.staende.first.version.id;
  FreigabeWerte? _vorschlag;
  Product? _artikel;
  final _nummer = TextEditingController();
  final _bezeichnung = TextEditingController();
  final _haltbarkeit = TextEditingController();
  String? _gruppe;
  final Set<FreigabeFeld> _felder = {...FreigabeFeld.values}
    ..remove(FreigabeFeld.bezeichnung);
  bool _laedt = true;
  bool _speichert = false;
  String? _fehler;

  /// Zählt Ladevorgänge — ein älterer, langsamerer schreibt nicht über
  /// einen neueren.
  int _ladeNr = 0;

  @override
  void initState() {
    super.initState();
    _laden(neu: true);
  }

  @override
  void dispose() {
    _nummer.dispose();
    _bezeichnung.dispose();
    _haltbarkeit.dispose();
    super.dispose();
  }

  FreigabeDienst get _dienst => ref.read(freigabeDienstProvider);

  /// Die Haltbarkeit aus den Angaben im Reiter „Produkt" — null ohne.
  String? get _haltbarkeitAngabe {
    final t = SpezAngaben.aus(widget.projekt.spezifikation).haltbarkeit.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _laden({bool neu = false}) async {
    final nr = ++_ladeNr;
    if (!_laedt) setState(() => _laedt = true);
    try {
      final v = await _dienst.vorschlag(widget.projekt, _versionId);
      if (!mounted || nr != _ladeNr) return;
      if (neu) {
        _nummer.text = v.artikelnummer;
        _bezeichnung.text = v.bezeichnung;
        _gruppe = v.produktgruppe;
        _haltbarkeit.text = v.haltbarkeitTage?.toString() ?? '';
      }
      final artikel = await _dienst.artikelZuNummer(_nummer.text);
      if (!mounted || nr != _ladeNr) return;
      setState(() {
        _vorschlag = v;
        _artikel = artikel;
        _laedt = false;
      });
    } catch (e) {
      if (!mounted || nr != _ladeNr) return;
      setState(() {
        _laedt = false;
        _fehler = fehlerText(e);
      });
    }
  }

  Future<void> _nummerGeaendert() async {
    final nr = ++_ladeNr;
    final artikel = await _dienst.artikelZuNummer(_nummer.text);
    if (!mounted || nr != _ladeNr) return;
    setState(() => _artikel = artikel);
  }

  FreigabeWerte? get _werte {
    final v = _vorschlag;
    if (v == null) return null;
    return FreigabeWerte(
      artikelnummer: _nummer.text.trim(),
      bezeichnung: _bezeichnung.text.trim(),
      produktgruppe: _gruppe,
      haltbarkeitTage: int.tryParse(_haltbarkeit.text.trim()),
      allergene: v.allergene,
      verlustProzent: v.verlustProzent,
      aw: v.aw,
    );
  }

  Future<void> _freigeben() async {
    final werte = _werte;
    if (werte == null) return;
    if (werte.artikelnummer.isEmpty) {
      setState(() => _fehler = 'Bitte eine Artikelnummer eingeben.');
      return;
    }
    setState(() {
      _speichert = true;
      _fehler = null;
    });
    try {
      final id = await _dienst.freigeben(
        projekt: widget.projekt,
        versionId: _versionId,
        werte: werte,
        felder: _felder,
      );
      ref
          .read(autoBackupTriggerProvider)
          .fireDebounced(reason: 'Freigabe als Artikel');
      if (mounted) Navigator.of(context).pop(id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _speichert = false;
        _fehler = 'Freigabe fehlgeschlagen: ${fehlerText(e)}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final werte = _werte;
    final artikel = _artikel;
    final fehler = _fehler;
    final aenderungen = artikel == null || werte == null
        ? const <FreigabeFeld>[]
        : [
            for (final f in FreigabeFeld.values)
              if (aendertFeld(artikel, werte, f)) f,
          ];

    return AlertDialog(
      icon: const Icon(Icons.verified_outlined),
      title: const Text('Als Artikel freigeben'),
      content: SizedBox(
        width: 620,
        child: _laedt && werte == null
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _versionId,
                      isExpanded: true,
                      decoration:
                          const InputDecoration(labelText: 'Rezepturstand'),
                      items: [
                        for (final s in widget.staende)
                          DropdownMenuItem(
                            value: s.version.id,
                            child: Text(
                              s.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (id) {
                        if (id == null || id == _versionId) return;
                        setState(() => _versionId = id);
                        _laden();
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        SizedBox(
                          width: 160,
                          child: TextField(
                            controller: _nummer,
                            decoration: const InputDecoration(
                              labelText: 'Artikelnummer',
                            ),
                            onChanged: (_) => _nummerGeaendert(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _bezeichnung,
                            decoration: const InputDecoration(
                              labelText: 'Bezeichnung',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _gruppe,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Produktgruppe',
                            ),
                            items: [
                              for (final g in ProductGroup.values)
                                DropdownMenuItem(
                                  value: g.dbValue,
                                  child: Text(
                                    g.label,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (g) => setState(() => _gruppe = g),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 160,
                          child: TextField(
                            controller: _haltbarkeit,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Haltbarkeit',
                              suffixText: 'Tage',
                              // Steht sie schon in den Angaben, kommt sie
                              // von dort.
                              helperText: _haltbarkeitAngabe == null
                                  ? null
                                  : 'Angaben: $_haltbarkeitAngabe',
                              helperMaxLines: 2,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (werte != null) ...[
                      Text('Aus der Rezeptur', style: theme.textTheme.labelMedium),
                      const SizedBox(height: 4),
                      for (final f in const [
                        FreigabeFeld.allergene,
                        FreigabeFeld.aw,
                      ])
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            '${f.label}: ${werte.text(f)}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          werte.verlustProzent == null
                              ? 'Verlust: keiner — die Planung fragt ihn ab, '
                                  'bis eine Produktion erfasst ist.'
                              : 'Verlust: '
                                  '${prozentText(werte.verlustProzent!)} — '
                                  'gilt in der Planung als Vorgabe, bis '
                                  'eine Produktion erfasst ist.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      if (werte.allergene == null) ...[
                        const SizedBox(height: 6),
                        const HinweisBox(
                          'Nicht bei allen Zutaten sind Allergene gepflegt — '
                          'der Artikel bekommt deshalb keine Angabe und gilt '
                          'in der Planung als ungepflegt.',
                          art: StatusArt.warnung,
                        ),
                      ],
                    ],
                    const SizedBox(height: 12),
                    if (artikel == null)
                      HinweisBox(
                        _nummer.text.trim().isEmpty
                            ? 'Bitte eine Artikelnummer eingeben.'
                            : 'Neuer Artikel ${_nummer.text.trim()} — '
                                'Prozessschritte trägst du danach in der '
                                'Artikelliste nach.',
                      )
                    else ...[
                      HinweisBox(
                        artikel.deletedAt != null
                            ? 'Den Artikel ${artikel.artikelnummer} gibt es '
                                'gelöscht — er wird wieder aktiviert.'
                            : 'Artikel ${artikel.artikelnummer} gibt es '
                                'schon: ${artikel.artikelbezeichnung}. '
                                'Angehakte Felder werden überschrieben.',
                        art: StatusArt.warnung,
                      ),
                      const SizedBox(height: 6),
                      if (aenderungen.isEmpty)
                        Text(
                          'Nichts zu ändern — alle Felder stimmen schon.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: grau,
                          ),
                        ),
                      for (final f in aenderungen)
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: _felder.contains(f),
                          title: Text(f.label),
                          subtitle: Text(
                            '${artikelText(artikel, f)}  →  ${werte!.text(f)}',
                          ),
                          onChanged: (v) => setState(() {
                            if (v ?? false) {
                              _felder.add(f);
                            } else {
                              _felder.remove(f);
                            }
                          }),
                        ),
                    ],
                    if (fehler != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        fehler,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _speichert ? null : () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _speichert || _laedt ? null : _freigeben,
          child: const Text('Freigeben'),
        ),
      ],
    );
  }
}
