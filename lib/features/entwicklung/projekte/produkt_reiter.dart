// `show Value`: drift bringt eine eigene Klasse `Column` mit.
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/services/auto_backup_trigger.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/fehler_text.dart';
import '../freigabe/freigabe.dart' show FreigabeStand;
import '../rezepturen/rezeptur_screen.dart' show TextFeld;
import '../spezifikation/spez_angaben.dart';
import '../spezifikation/spezifikation_dialog.dart';
import '../spezifikation/spezifikation_dienst.dart';
import '../spezifikation/spezifikation_vorschau.dart';
import '../spezifikation/spezifikation_werte.dart';
import 'produkt_foto.dart';
import 'projekt_modell.dart';
import 'projekt_repository.dart';
import 'verpackung_eingabe.dart';

// Der Reiter „Produkt" eines Projekts (F26): links, wie das fertige
// Produkt ist (Sensorik mit Produktfoto, Maßen und Stückgewicht — F38) und
// was die Spezifikation darüber hinaus braucht (Angaben, Verpackung);
// rechts, was mit einem Rezepturstand in der Spezifikation stünde — mit
// dem einen Weg zum Erstellen. Zutaten, Allergene, Nährwerte und
// Hilfsstoffe kommen aus dem Stand, die Artikelnummer aus den Stammdaten.

/// Das Produkt eines Projekts.
class ProjektProdukt extends ConsumerStatefulWidget {
  const ProjektProdukt({super.key, required this.projekt});

  final EntwicklungsProjekt projekt;

  @override
  ConsumerState<ProjektProdukt> createState() => _ProjektProduktState();
}

class _ProjektProduktState extends ConsumerState<ProjektProdukt>
    with AutomaticKeepAliveClientMixin {
  String? _versionId;

  /// Was zuletzt eingetragen wurde, bis die Datenbank es zurückmeldet —
  /// so geht beim schnellen Wechsel zwischen den Feldern nichts verloren.
  SpezAngaben? _angabenLokal;
  Sensorik? _sensorikLokal;

  @override
  bool get wantKeepAlive => true;

  @override
  void didUpdateWidget(ProjektProdukt alt) {
    super.didUpdateWidget(alt);
    final angaben = _angabenLokal;
    if (angaben != null && widget.projekt.spezifikation == angaben.alsJson()) {
      _angabenLokal = null;
    }
    final sensorik = _sensorikLokal;
    if (sensorik != null && widget.projekt.sensorik == sensorik.alsJson()) {
      _sensorikLokal = null;
    }
  }

  SpezAngaben get _angaben =>
      _angabenLokal ?? SpezAngaben.aus(widget.projekt.spezifikation);

  Sensorik get _sensorik =>
      _sensorikLokal ?? Sensorik.aus(widget.projekt.sensorik);

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

  void _angabenSpeichern(SpezAngaben neu) {
    setState(() => _angabenLokal = neu);
    _aendern(EntwicklungProjekteCompanion(spezifikation: Value(neu.alsJson())));
  }

  void _sensorikSpeichern(Sensorik neu) {
    setState(() => _sensorikLokal = neu);
    _aendern(EntwicklungProjekteCompanion(sensorik: Value(neu.alsJson())));
  }

  void _verpackung(Verpackung neu) =>
      _angabenSpeichern(_angaben.kopie(verpackung: neu));

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
    final eingaben = [
      _sensorikBereich(context),
      const SizedBox(height: 16),
      _angabenBereich(context),
      const SizedBox(height: 16),
      _verpackungBereich(context),
    ];
    final spezifikation = [
      _spezifikationBereich(context),
      if (versionId != null) ...[
        const SizedBox(height: 16),
        SpezVorschau(
          projektId: widget.projekt.id,
          versionId: versionId,
          produktfoto: widget.projekt.bildDateiId != null,
        ),
      ],
    ];
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= 1000) {
          // Links die Eingaben, rechts was daraus in der Spezifikation
          // steht.
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: eingaben,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: spezifikation,
                  ),
                ),
              ],
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            ...eingaben,
            const SizedBox(height: 16),
            ...spezifikation,
          ],
        );
      },
    );
  }

  Widget _sensorikBereich(BuildContext context) {
    final s = _sensorik;
    const abstand = SizedBox(height: 10);

    Widget text(
      String schluessel,
      String wert,
      String label,
      Sensorik Function(String t) neu,
    ) =>
        TextFeld(
          key: ValueKey('sensorik-$schluessel'),
          wert: wert,
          label: label,
          mehrzeilig: true,
          onFertig: (t) => _sensorikSpeichern(neu(t)),
        );

    Widget mass(
      String schluessel,
      String wert,
      String label,
      ValueChanged<String> neu, {
      String? hinweis,
    }) =>
        SizedBox(
          width: 160,
          child: TextFeld(
            key: ValueKey(schluessel),
            wert: wert,
            label: label,
            hinweis: hinweis,
            onFertig: neu,
          ),
        );

    final beschreibung = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        text(
          'aussehen',
          s.aussehen,
          'Aussehen',
          (t) => _sensorik.kopie(aussehen: t),
        ),
        abstand,
        text(
          'geruch',
          s.geruch,
          'Geruch',
          (t) => _sensorik.kopie(geruch: t),
        ),
        abstand,
        text(
          'geschmack',
          s.geschmack,
          'Geschmack',
          (t) => _sensorik.kopie(geschmack: t),
        ),
        abstand,
        text(
          'konsistenz',
          s.konsistenz,
          'Konsistenz',
          (t) => _sensorik.kopie(konsistenz: t),
        ),
      ],
    );
    final foto = ProduktFoto(projekt: widget.projekt);

    return Bereich(
      titel: 'Sensorik',
      icon: Icons.restaurant_menu,
      untertitel: 'das fertige Produkt',
      innenAbstand: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Das Foto neben der Beschreibung — so steht es auch in der
          // Spezifikation; schmal darunter.
          LayoutBuilder(
            builder: (context, c) => c.maxWidth >= 520
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: beschreibung),
                      const SizedBox(width: 12),
                      SizedBox(width: 220, child: foto),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [beschreibung, abstand, foto],
                  ),
          ),
          abstand,
          // Maße und Stückgewicht — einmal für Sensorik und Spezifikation.
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              mass(
                'sensorik-laenge',
                s.laenge,
                'Länge',
                (t) => _sensorikSpeichern(_sensorik.kopie(laenge: t)),
              ),
              mass(
                'sensorik-durchmesser',
                s.durchmesser,
                'Durchmesser',
                (t) => _sensorikSpeichern(_sensorik.kopie(durchmesser: t)),
              ),
              mass(
                'spez-gewicht',
                s.gewicht,
                'Stückgewicht',
                (t) => _sensorikSpeichern(_sensorik.kopie(gewicht: t)),
              ),
              mass(
                'spez-toleranz',
                _angaben.toleranz,
                'Toleranz',
                (t) => _angabenSpeichern(_angaben.kopie(toleranz: t)),
                hinweis: 'etwa „± 5"',
              ),
            ],
          ),
          abstand,
          text(
            'zubereitung',
            s.zubereitung,
            'Zubereitung',
            (t) => _sensorik.kopie(zubereitung: t),
          ),
        ],
      ),
    );
  }

  Widget _angabenBereich(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final a = _angaben;
    final p = widget.projekt;
    const abstand = SizedBox(height: 10);
    return Bereich(
      titel: 'Angaben',
      icon: Icons.fact_check_outlined,
      untertitel: 'Zutaten, Allergene und Nährwerte kommen aus dem Stand',
      innenAbstand: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFeld(
            key: const ValueKey('spez-bezeichnung'),
            wert: a.bezeichnung,
            label: 'Artikelbezeichnung',
            hinweis: p.artikelId == null
                ? 'leer: „${p.name}"'
                : 'leer: die des Artikels',
            onFertig: (t) => _angabenSpeichern(_angaben.kopie(bezeichnung: t)),
          ),
          abstand,
          TextFeld(
            key: const ValueKey('spez-lagerung'),
            wert: a.lagerung,
            label: 'Transport und Lagerung',
            hinweis: 'etwa „gekühlt bei +2 °C bis +7 °C" oder „≤ -18 °C"',
            onFertig: (t) => _angabenSpeichern(_angaben.kopie(lagerung: t)),
          ),
          abstand,
          TextFeld(
            key: const ValueKey('spez-haltbarkeit'),
            wert: a.haltbarkeit,
            label: 'Haltbarkeit',
            hinweis: 'eine Zahl gilt als Tage; leer: aus dem Artikel, '
                'sobald freigegeben',
            onFertig: (t) => _angabenSpeichern(_angaben.kopie(haltbarkeit: t)),
          ),
          abstand,
          TextFeld(
            key: const ValueKey('spez-hinweise'),
            wert: a.hinweise,
            label: 'Produkthinweise',
            hinweis: 'je Zeile ein Hinweis, etwa „Vor dem Verzehr vollständig '
                'durcherhitzen."',
            mehrzeilig: true,
            onFertig: (t) => _angabenSpeichern(_angaben.kopie(hinweise: t)),
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
                  onSelected: (an) => _angabenSpeichern(
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

  Widget _verpackungBereich(BuildContext context) => Bereich(
        titel: 'Verpackung',
        icon: Icons.inventory_2_outlined,
        innenAbstand: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: VerpackungEingabe(
          wert: _angaben.verpackung,
          onAenderung: _verpackung,
        ),
      );

  /// Der Stand für Vorschau und Spezifikation und der eine Weg zum
  /// Erstellen: das Fenster mit Sprache, Vorlage, Kürzel und Datum.
  Widget _spezifikationBereich(BuildContext context) {
    final theme = Theme.of(context);
    final p = widget.projekt;
    final staende = ref.watch(spezStaendeProvider(p.id));
    final versionId = _stand(staende.valueOrNull ?? const <FreigabeStand>[]);
    return Bereich(
      titel: 'Spezifikation',
      icon: Icons.table_view_outlined,
      innenAbstand: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          staende.when(
            skipLoadingOnReload: true,
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => HinweisBox(
              fehlerText(e),
              art: StatusArt.fehler,
              auswaehlbar: true,
            ),
            data: (liste) => liste.isEmpty
                ? const HinweisBox(
                    'Das Projekt hat noch keine Rezeptur — in der Übersicht '
                    'unter „Rezepturen" anlegen.',
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
                    onChanged: (id) => setState(() => _versionId = id),
                  ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const ValueKey('spez-erstellen'),
              onPressed: () =>
                  spezifikationOeffnen(context, p, versionId: versionId),
              icon: const Icon(Icons.download_outlined, size: 18),
              label: const Text('Spezifikation erstellen…'),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Sprache, Vorlage, Kürzel und Datum wählst du im nächsten '
            'Schritt.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
