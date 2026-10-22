// `show Value`: drift bringt eine eigene Klasse `Column` mit.
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/services/auto_backup_trigger.dart';
import '../../../core/theme/app_stil.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/fehler_text.dart';
import '../../../core/utils/format.dart';
import '../freigabe/freigabe.dart' show FreigabeStand;
import '../projekte/projekt_modell.dart';
import '../projekte/projekt_repository.dart';
import '../rezepturen/rezeptur_screen.dart' show TextFeld;
import 'spez_angaben.dart';
import 'spezifikation_dialog.dart';
import 'spezifikation_dienst.dart';
import 'spezifikation_vorschau.dart';
import 'spezifikation_werte.dart';

// Der Reiter „Spezifikation" eines Projekts: oben auf Knopfdruck die
// Spezifikation auf Deutsch oder Englisch, darunter was hineinkommt
// (Vorschau für den gewählten Stand) und was das Projekt dafür selbst
// angibt — Artikelnummer und -bezeichnung, Stückgewicht und Toleranz,
// Lagerung, Haltbarkeit, Produkthinweise, mögliche Spuren und die
// Verpackung. Zutaten, Allergene, Nährwerte und Hilfsstoffe kommen aus
// dem Rezepturstand, die Sensorik aus ihrem Reiter.

/// Die Spezifikation eines Projekts.
class ProjektSpezifikation extends ConsumerStatefulWidget {
  const ProjektSpezifikation({super.key, required this.projekt});

  final EntwicklungsProjekt projekt;

  @override
  ConsumerState<ProjektSpezifikation> createState() =>
      _ProjektSpezifikationState();
}

class _ProjektSpezifikationState extends ConsumerState<ProjektSpezifikation>
    with AutomaticKeepAliveClientMixin {
  String? _versionId;
  DateTime _datum = DateUtils.dateOnly(DateTime.now());
  final _kuerzel = TextEditingController();
  bool _kuerzelGeladen = false;
  bool _laeuft = false;
  SpezMeldung? _meldung;

  /// Was zuletzt eingetragen wurde, bis die Datenbank es zurückmeldet —
  /// so geht beim schnellen Klicken nichts verloren.
  SpezAngaben? _lokal;

  @override
  bool get wantKeepAlive => true;

  @override
  void didUpdateWidget(ProjektSpezifikation alt) {
    super.didUpdateWidget(alt);
    final lokal = _lokal;
    if (lokal != null && widget.projekt.spezifikation == lokal.alsJson()) {
      _lokal = null;
    }
  }

  @override
  void dispose() {
    _kuerzel.dispose();
    super.dispose();
  }

  SpezAngaben get _angaben =>
      _lokal ?? SpezAngaben.aus(widget.projekt.spezifikation);

  Future<void> _aendern(EntwicklungProjekteCompanion daten) async {
    try {
      await ref
          .read(projektRepositoryProvider)
          .projektAendern(widget.projekt.id, daten);
      ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Projekt');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Speichern fehlgeschlagen: ${fehlerText(e)}')),
        );
      }
    }
  }

  void _speichern(SpezAngaben neu) {
    setState(() => _lokal = neu);
    _aendern(EntwicklungProjekteCompanion(spezifikation: Value(neu.alsJson())));
  }

  void _verpackung(Verpackung neu) =>
      _speichern(_angaben.kopie(verpackung: neu));

  Future<void> _datumWaehlen() async {
    final gewaehlt = await showDatePicker(
      context: context,
      initialDate: _datum,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (gewaehlt != null && mounted) setState(() => _datum = gewaehlt);
  }

  Future<void> _erstellen(SpezSprache sprache, String versionId) async {
    final hinterlegt = ref.read(deeplHinterlegtProvider).valueOrNull ?? false;
    setState(() {
      _laeuft = true;
      _meldung = null;
    });
    final m = await spezifikationErstellenUndSpeichern(
      ref,
      projekt: widget.projekt,
      versionId: versionId,
      sprache: sprache,
      uebersetzen: hinterlegt,
      datum: _datum,
      kuerzel: _kuerzel.text,
    );
    if (!mounted) return;
    setState(() {
      _laeuft = false;
      if (m != null) _meldung = m;
    });
  }

  /// Der gewählte Stand — sonst der vorgeschlagene.
  String? _stand(List<FreigabeStand> alle) =>
      alle.any((s) => s.version.id == _versionId)
          ? _versionId
          : spezStandVorschlag(alle, widget.projekt.freigabeVersionId);

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final staende =
        ref.watch(spezStaendeProvider(widget.projekt.id)).valueOrNull ??
            const <FreigabeStand>[];
    final versionId = _stand(staende);
    final erstellen = _erstellenBereich(context);
    final vorschau = versionId == null
        ? null
        : SpezVorschau(projektId: widget.projekt.id, versionId: versionId);
    final angaben = _angabenBereich(context);
    final verpackung = _verpackungBereich(context);
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= 1000) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                erstellen,
                if (vorschau != null) ...[
                  const SizedBox(height: 16),
                  vorschau,
                ],
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: angaben),
                    const SizedBox(width: 16),
                    Expanded(child: verpackung),
                  ],
                ),
              ],
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            erstellen,
            if (vorschau != null) ...[
              const SizedBox(height: 16),
              vorschau,
            ],
            const SizedBox(height: 16),
            angaben,
            const SizedBox(height: 16),
            verpackung,
          ],
        );
      },
    );
  }

  Widget _erstellenBereich(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final p = widget.projekt;
    final staende = ref.watch(spezStaendeProvider(p.id));
    final kuerzel = ref.watch(spezKuerzelProvider);
    if (!_kuerzelGeladen && kuerzel.hasValue) {
      _kuerzelGeladen = true;
      _kuerzel.text = kuerzel.value ?? '';
    }
    final versionId = _stand(staende.valueOrNull ?? const <FreigabeStand>[]);
    final meldung = _meldung;

    Widget vorlagenZeile(SpezSprache s) {
      final d = ref.watch(spezVorlageProvider(s)).valueOrNull;
      // Null, solange die Felder noch gezählt werden.
      final felder = ref.watch(spezVorlagePlatzhalterProvider(s)).valueOrNull;
      final zusatz = switch (felder) {
        null => '',
        Set(isEmpty: true) =>
          ' · noch nicht eingerichtet — das macht die App beim Erstellen',
        final f => ' · ${f.length} Felder',
      };
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            Icon(
              d == null ? Icons.error_outline : Icons.check_circle_outline,
              size: 16,
              color: d == null ? AppFarben.von(context).warnung : grau,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                d == null
                    ? 'Vorlage ${s.label}: noch keine — unter „Vorlagen und '
                        'DeepL" wählen'
                    : 'Vorlage ${s.label}: ${d.name}$zusatz',
                style: theme.textTheme.bodySmall?.copyWith(color: grau),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    bool kann(SpezSprache s) =>
        !_laeuft &&
        versionId != null &&
        ref.watch(spezVorlageProvider(s)).valueOrNull != null;

    return Bereich(
      titel: 'Spezifikation erstellen',
      icon: Icons.table_view_outlined,
      aktionen: [
        TextButton.icon(
          onPressed: _laeuft
              ? null
              : () => spezifikationOeffnen(context, widget.projekt),
          icon: const Icon(Icons.settings_outlined, size: 18),
          label: const Text('Vorlagen und DeepL…'),
        ),
      ],
      innenAbstand: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 380,
                child: staende.when(
                  skipLoadingOnReload: true,
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => HinweisBox(
                    fehlerText(e),
                    art: StatusArt.fehler,
                    auswaehlbar: true,
                  ),
                  data: (liste) => liste.isEmpty
                      ? const HinweisBox(
                          'Das Projekt hat noch keine Rezeptur.',
                          art: StatusArt.warnung,
                        )
                      : DropdownButtonFormField<String>(
                          key: ValueKey('spez-stand-$versionId'),
                          initialValue: versionId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Rezepturstand',
                          ),
                          items: [
                            for (final s in liste)
                              DropdownMenuItem(
                                value: s.version.id,
                                child: Text(
                                  spezStandLabel(
                                    s,
                                    freigegebeneVersionId: p.freigabeVersionId,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: _laeuft
                              ? null
                              : (id) => setState(() => _versionId = id),
                        ),
                ),
              ),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _kuerzel,
                  enabled: !_laeuft,
                  decoration: const InputDecoration(
                    labelText: 'Kürzel',
                    hintText: 'z. B. MM',
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _laeuft ? null : _datumWaehlen,
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text('gültig ab ${Format.datum(_datum)}'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: kann(SpezSprache.de)
                    ? () => _erstellen(SpezSprache.de, versionId!)
                    : null,
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Deutsch erstellen…'),
              ),
              FilledButton.tonalIcon(
                onPressed: kann(SpezSprache.en)
                    ? () => _erstellen(SpezSprache.en, versionId!)
                    : null,
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Englisch erstellen…'),
              ),
              if (_laeuft)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          vorlagenZeile(SpezSprache.de),
          vorlagenZeile(SpezSprache.en),
          if (meldung != null) ...[
            const SizedBox(height: 10),
            HinweisBox(
              meldung.text,
              art: meldung.art,
              auswaehlbar: true,
              onSchliessen: () => setState(() => _meldung = null),
            ),
          ],
        ],
      ),
    );
  }

  Widget _angabenBereich(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final a = _angaben;
    final p = widget.projekt;
    final sensorik = Sensorik.aus(p.sensorik);
    const abstand = SizedBox(height: 10);
    return Bereich(
      titel: 'Angaben',
      icon: Icons.fact_check_outlined,
      untertitel: 'Zutaten, Allergene und Nährwerte kommen aus dem Stand',
      innenAbstand: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 180,
                child: TextFeld(
                  key: const ValueKey('spez-artikelnummer'),
                  wert: p.artikelnummer ?? '',
                  label: 'Artikelnummer',
                  // Nach der Freigabe gilt die Nummer des Artikels.
                  bearbeitbar: p.artikelId == null,
                  hinweis: p.artikelId == null ? null : 'vom Artikel',
                  onFertig: (t) => _aendern(
                    EntwicklungProjekteCompanion(
                      artikelnummer: Value(t.isEmpty ? null : t),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 380,
                child: TextFeld(
                  key: const ValueKey('spez-bezeichnung'),
                  wert: a.bezeichnung,
                  label: 'Artikelbezeichnung',
                  hinweis: p.artikelId == null
                      ? 'leer: „${p.name}"'
                      : 'leer: die des Artikels',
                  onFertig: (t) => _speichern(_angaben.kopie(bezeichnung: t)),
                ),
              ),
            ],
          ),
          abstand,
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 180,
                child: TextFeld(
                  key: const ValueKey('spez-gewicht'),
                  wert: sensorik.gewicht,
                  label: 'Stückgewicht',
                  onFertig: (t) => _aendern(
                    EntwicklungProjekteCompanion(
                      sensorik: Value(sensorik.kopie(gewicht: t).alsJson()),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 180,
                child: TextFeld(
                  key: const ValueKey('spez-toleranz'),
                  wert: a.toleranz,
                  label: 'Toleranz',
                  hinweis: 'etwa „± 5"',
                  onFertig: (t) => _speichern(_angaben.kopie(toleranz: t)),
                ),
              ),
            ],
          ),
          abstand,
          TextFeld(
            key: const ValueKey('spez-lagerung'),
            wert: a.lagerung,
            label: 'Transport und Lagerung',
            hinweis: 'etwa „gekühlt bei +2 °C bis +7 °C" oder „≤ -18 °C"',
            onFertig: (t) => _speichern(_angaben.kopie(lagerung: t)),
          ),
          abstand,
          TextFeld(
            key: const ValueKey('spez-haltbarkeit'),
            wert: a.haltbarkeit,
            label: 'Haltbarkeit',
            hinweis: 'eine Zahl gilt als Tage; leer: aus dem Artikel, '
                'sobald freigegeben',
            onFertig: (t) => _speichern(_angaben.kopie(haltbarkeit: t)),
          ),
          abstand,
          TextFeld(
            key: const ValueKey('spez-hinweise'),
            wert: a.hinweise,
            label: 'Produkthinweise',
            hinweis: 'je Zeile ein Hinweis, etwa „Vor dem Verzehr vollständig '
                'durcherhitzen."',
            mehrzeilig: true,
            onFertig: (t) => _speichern(_angaben.kopie(hinweise: t)),
          ),
          const SizedBox(height: 14),
          Text('Spuren möglich von', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final x in kSpezAllergene)
                FilterChip(
                  label: Text(allergenName(x, SpezSprache.de)),
                  selected: a.spuren.contains(x),
                  onSelected: (an) => _speichern(
                    _angaben.kopie(
                      spuren: an
                          ? {..._angaben.spuren, x}
                          : (_angaben.spuren.toSet()..remove(x)),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Was die Rezeptur enthält, steht als „ja" in der Spezifikation — '
            'eine Spur zählt dann nicht.',
            style: theme.textTheme.bodySmall?.copyWith(color: grau),
          ),
        ],
      ),
    );
  }

  Widget _verpackungBereich(BuildContext context) {
    final theme = Theme.of(context);
    final v = _angaben.verpackung;
    const abstand = SizedBox(height: 10);

    Widget mehrfach(
      List<SpezWahl> liste,
      Set<String> gewaehlt,
      ValueChanged<Set<String>> neu,
    ) =>
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final w in liste)
              FilterChip(
                label: Text(w.label),
                selected: gewaehlt.contains(w.schluessel),
                onSelected: (an) => neu(
                  an
                      ? {...gewaehlt, w.schluessel}
                      : (gewaehlt.toSet()..remove(w.schluessel)),
                ),
              ),
          ],
        );

    Widget einfach(
      String titel,
      List<SpezWahl> liste,
      String gewaehlt,
      ValueChanged<String> neu,
    ) =>
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 92,
              child: Text(titel, style: theme.textTheme.bodySmall),
            ),
            for (final w in liste)
              ChoiceChip(
                label: Text(w.label),
                selected: gewaehlt == w.schluessel,
                // Noch einmal tippen nimmt die Wahl zurück.
                onSelected: (an) => neu(an ? w.schluessel : ''),
              ),
          ],
        );

    Widget feld(
      String schluessel,
      String wert,
      String label,
      ValueChanged<String> neu, {
      double breite = 150,
    }) =>
        SizedBox(
          width: breite,
          child: TextFeld(
            key: ValueKey('spez-$schluessel'),
            wert: wert,
            label: label,
            onFertig: neu,
          ),
        );

    return Bereich(
      titel: 'Verpackung',
      icon: Icons.inventory_2_outlined,
      innenAbstand: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Umverpackung', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          mehrfach(
            kUmverpackungen,
            v.um,
            (neu) => _verpackung(_angaben.verpackung.kopie(um: neu)),
          ),
          abstand,
          einfach(
            'Karton',
            kKartonAufmachungen,
            v.karton,
            (neu) => _verpackung(_angaben.verpackung.kopie(karton: neu)),
          ),
          const SizedBox(height: 6),
          einfach(
            'Befüllung',
            kUmFuellungen,
            v.umFuellung,
            (neu) => _verpackung(_angaben.verpackung.kopie(umFuellung: neu)),
          ),
          abstand,
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              feld(
                'um-tara',
                v.umTara,
                'Taragewicht',
                (t) => _verpackung(_angaben.verpackung.kopie(umTara: t)),
              ),
              feld(
                'um-netto',
                v.umNetto,
                'Nettogewicht',
                (t) => _verpackung(_angaben.verpackung.kopie(umNetto: t)),
              ),
              feld(
                'um-material',
                v.umMaterial,
                'Material',
                (t) => _verpackung(_angaben.verpackung.kopie(umMaterial: t)),
              ),
            ],
          ),
          const Divider(height: 28),
          Text('Einzelverpackung', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          mehrfach(
            kEinzelverpackungen,
            v.einzel,
            (neu) => _verpackung(_angaben.verpackung.kopie(einzel: neu)),
          ),
          abstand,
          einfach(
            'Atmosphäre',
            kAtmosphaeren,
            v.atmosphaere,
            (neu) => _verpackung(_angaben.verpackung.kopie(atmosphaere: neu)),
          ),
          const SizedBox(height: 6),
          einfach(
            'Befüllung',
            kEinzelFuellungen,
            v.einzelFuellung,
            (neu) =>
                _verpackung(_angaben.verpackung.kopie(einzelFuellung: neu)),
          ),
          abstand,
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              feld(
                'anzahl',
                v.anzahl,
                'Anzahl je Umverpackung',
                (t) => _verpackung(_angaben.verpackung.kopie(anzahl: t)),
                breite: 200,
              ),
              feld(
                'stueckzahl',
                v.stueckzahl,
                'Stückzahl',
                (t) => _verpackung(_angaben.verpackung.kopie(stueckzahl: t)),
              ),
              feld(
                'einzel-tara',
                v.einzelTara,
                'Taragewicht',
                (t) => _verpackung(_angaben.verpackung.kopie(einzelTara: t)),
              ),
              feld(
                'einzel-netto',
                v.einzelNetto,
                'Nettogewicht',
                (t) => _verpackung(_angaben.verpackung.kopie(einzelNetto: t)),
              ),
              feld(
                'einzel-material',
                v.einzelMaterial,
                'Material',
                (t) =>
                    _verpackung(_angaben.verpackung.kopie(einzelMaterial: t)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
