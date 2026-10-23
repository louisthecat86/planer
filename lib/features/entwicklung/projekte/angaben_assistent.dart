// `show Value`: drift bringt eine eigene Klasse `Column` mit.
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/services/auto_backup_trigger.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/fehler_text.dart';
import '../spezifikation/spez_angaben.dart';
import 'angaben_luecken.dart';
import 'produkt_foto.dart';
import 'projekt_modell.dart';
import 'projekt_repository.dart';
import 'verpackung_eingabe.dart';

// Der Assistent „Angaben ergänzen…" (F39): fragt, was einem Projekt noch
// fehlt, eine Angabe nach der anderen — mit „Weiter" und „Später". Was
// eingetragen ist, steht sofort im Projekt; wer zwischendurch schließt,
// verliert nichts. „Später" beim Produktfoto stellt es zurück wie im
// Reiter „Produkt" (F37), bei allem anderen geht es nur weiter.
//
// Gestartet wird er aus dem Projektkopf („3 Angaben fehlen") und aus dem
// Fenster der Spezifikation, wenn dort etwas leer bliebe.

/// Öffnet den Assistenten für [projekt], wenn ihm etwas fehlt — danach
/// eine kurze Meldung, was eingetragen und was verschoben ist.
Future<void> angabenErgaenzen(
  BuildContext context,
  EntwicklungsProjekt projekt,
) async {
  final schritte = fehlendeAngaben(projekt);
  if (schritte.isEmpty) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final ergebnis = await showDialog<AssistentErgebnis>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AngabenAssistent(projekt: projekt, schritte: schritte),
  );
  final text = ergebnis?.text ?? '';
  if (text.isNotEmpty) {
    messenger?.showSnackBar(SnackBar(content: Text(text)));
  }
}

/// Vorschläge für die Lagerung — antippen trägt sie ein.
const List<String> kLagerungVorschlaege = [
  'gekühlt bei +2 °C bis +7 °C',
  'gekühlt bei 0 °C bis +4 °C',
  'tiefgefroren bei ≤ -18 °C',
];

/// Vorschläge für die Haltbarkeit.
const List<String> kHaltbarkeitVorschlaege = [
  '7 Tage',
  '14 Tage',
  '21 Tage',
  '12 Monate',
];

/// Frage und Erklärung eines Schritts.
(String, String) _texte(AngabeSchritt s) => switch (s) {
      AngabeSchritt.artikelnummer => (
          'Wie lautet die Artikelnummer?',
          'Sie steht in der Spezifikation; bei der Freigabe wird sie die '
              'Nummer des Artikels.',
        ),
      AngabeSchritt.sensorik => (
          'Wie ist das fertige Produkt?',
          'Aussehen, Geruch, Geschmack und Konsistenz — so steht es in der '
              'Spezifikation.',
        ),
      AngabeSchritt.produktfoto => (
          'Gibt es schon ein Produktfoto?',
          'Es kommt in der Spezifikation neben die Sensorik. Noch keins? '
              '„Später" stellt es zurück — der Kopf erinnert daran.',
        ),
      AngabeSchritt.lagerung => (
          'Wie wird das Produkt gelagert?',
          'Transport- und Lagerbedingungen für Spezifikation und Etikett.',
        ),
      AngabeSchritt.haltbarkeit => (
          'Wie lange ist es haltbar?',
          'Eine Zahl gilt als Tage. Die Freigabe übernimmt die Haltbarkeit '
              'für den Artikel.',
        ),
      AngabeSchritt.verpackung => (
          'Wie wird es verpackt?',
          'Umverpackung und Einzelverpackung für die Spezifikation — das '
              'Nettogewicht steht auch auf dem Etikett.',
        ),
    };

/// Der Assistent als Fenster.
class AngabenAssistent extends ConsumerStatefulWidget {
  const AngabenAssistent({
    super.key,
    required this.projekt,
    required this.schritte,
  });

  final EntwicklungsProjekt projekt;

  /// Was gefragt wird — beim Öffnen festgelegt, damit sich die Reihe beim
  /// Eintragen nicht verschiebt.
  final List<AngabeSchritt> schritte;

  @override
  ConsumerState<AngabenAssistent> createState() => _AngabenAssistentState();
}

class _AngabenAssistentState extends ConsumerState<AngabenAssistent> {
  var _index = 0;
  final _eingetragen = <AngabeSchritt>[];
  final _spaeter = <AngabeSchritt>[];
  bool _laeuft = false;
  String? _fehler;

  /// Was der Assistent geschrieben hat — die Datenbank meldet es erst
  /// später zurück, und jeder Schritt baut auf dem vorigen auf.
  late SpezAngaben _angaben = SpezAngaben.aus(widget.projekt.spezifikation);
  late Sensorik _sensorik = Sensorik.aus(widget.projekt.sensorik);

  late final _nummer =
      TextEditingController(text: widget.projekt.artikelnummer ?? '');
  late final _lagerung = TextEditingController(text: _angaben.lagerung);
  late final _haltbarkeit = TextEditingController(text: _angaben.haltbarkeit);
  late final Map<String, TextEditingController> _sinne = {
    'aussehen': TextEditingController(text: _sensorik.aussehen),
    'geruch': TextEditingController(text: _sensorik.geruch),
    'geschmack': TextEditingController(text: _sensorik.geschmack),
    'konsistenz': TextEditingController(text: _sensorik.konsistenz),
  };

  AngabeSchritt get _schritt => widget.schritte[_index];
  bool get _letzter => _index >= widget.schritte.length - 1;
  String get _id => widget.projekt.id;
  ProjektRepository get _repo => ref.read(projektRepositoryProvider);

  AssistentErgebnis get _ergebnis => AssistentErgebnis(
        eingetragen: [..._eingetragen],
        spaeter: [..._spaeter],
      );

  /// Das Projekt, wie es gerade ist — mit einem eben gewählten Foto.
  EntwicklungsProjekt get _aktuell =>
      ref.read(projektProvider(_id)).valueOrNull ?? widget.projekt;

  @override
  void dispose() {
    _nummer.dispose();
    _lagerung.dispose();
    _haltbarkeit.dispose();
    for (final c in _sinne.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _angabenSchreiben(SpezAngaben neu) {
    _angaben = neu;
    return _repo.projektAendern(
      _id,
      EntwicklungProjekteCompanion(spezifikation: Value(neu.alsJson())),
    );
  }

  /// Die Verpackung schreibt jede Wahl gleich — wie im Reiter „Produkt".
  Future<void> _verpackung(Verpackung neu) async {
    setState(() => _angaben = _angaben.kopie(verpackung: neu));
    try {
      await _angabenSchreiben(_angaben);
      _sichern();
    } catch (e) {
      if (mounted) {
        setState(() => _fehler = 'Speichern fehlgeschlagen: ${fehlerText(e)}');
      }
    }
  }

  /// Speichert, was im Schritt [s] steht — true, wenn dabei etwas
  /// eingetragen wurde.
  Future<bool> _speichern(AngabeSchritt s) async {
    switch (s) {
      case AngabeSchritt.artikelnummer:
        final t = _nummer.text.trim();
        if (t.isEmpty) return false;
        await _repo.projektAendern(
          _id,
          EntwicklungProjekteCompanion(artikelnummer: Value(t)),
        );
        return true;
      case AngabeSchritt.sensorik:
        String t(String k) => _sinne[k]!.text.trim();
        final neu = _sensorik.kopie(
          aussehen: t('aussehen'),
          geruch: t('geruch'),
          geschmack: t('geschmack'),
          konsistenz: t('konsistenz'),
        );
        if (neu.alsJson() == _sensorik.alsJson()) return false;
        _sensorik = neu;
        await _repo.projektAendern(
          _id,
          EntwicklungProjekteCompanion(sensorik: Value(neu.alsJson())),
        );
        return true;
      case AngabeSchritt.produktfoto:
        return _aktuell.bildDateiId != null;
      case AngabeSchritt.lagerung:
        final t = _lagerung.text.trim();
        if (t.isEmpty) return false;
        await _angabenSchreiben(_angaben.kopie(lagerung: t));
        return true;
      case AngabeSchritt.haltbarkeit:
        final t = _haltbarkeit.text.trim();
        if (t.isEmpty) return false;
        await _angabenSchreiben(_angaben.kopie(haltbarkeit: t));
        return true;
      case AngabeSchritt.verpackung:
        return !_angaben.verpackung.leer;
    }
  }

  /// Was in einem Feld steht, zählt — auch ohne es vorher zu verlassen:
  /// Felder, die sich beim Verlassen melden (die der Verpackung), melden
  /// sich jetzt. Den Fokuswechsel wendet Flutter in einer Microtask an;
  /// eine Microtask danach haben die Felder ihn gehört — ohne auf einen
  /// Timer zu warten.
  Future<void> _felderVerlassen() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.microtask(() {});
  }

  void _sichern() =>
      ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Angaben');

  /// Schließt den Assistenten — was im offenen Schritt steht, bleibt.
  Future<void> _schliessen() async {
    if (_laeuft) return;
    await _felderVerlassen();
    if (!mounted) return;
    setState(() => _laeuft = true);
    final s = _schritt;
    try {
      if (!_eingetragen.contains(s) && await _speichern(s)) {
        _eingetragen.add(s);
        _sichern();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _laeuft = false;
        _fehler = 'Speichern fehlgeschlagen: ${fehlerText(e)}';
      });
      return;
    }
    if (mounted) Navigator.of(context).pop(_ergebnis);
  }

  /// Weiter zum nächsten Schritt — mit „Später", ohne zu speichern.
  Future<void> _weiter({bool spaeter = false}) async {
    if (_laeuft) return;
    await _felderVerlassen();
    if (!mounted) return;
    setState(() {
      _laeuft = true;
      _fehler = null;
    });
    final s = _schritt;
    try {
      if (spaeter) {
        // Schon da (ein eben gewähltes Foto, eine gewählte Verpackung):
        // dann ist es eingetragen.
        final schonDa = switch (s) {
          AngabeSchritt.produktfoto => _aktuell.bildDateiId != null,
          AngabeSchritt.verpackung => !_angaben.verpackung.leer,
          _ => false,
        };
        if (schonDa) {
          _eingetragen.add(s);
        } else {
          if (s == AngabeSchritt.produktfoto) {
            await _repo.checklisteZurueckstellen(
              _id,
              schluessel: 'produktfotoHinterlegt',
              zurueck: true,
            );
          }
          _spaeter.add(s);
        }
      } else if (await _speichern(s)) {
        _eingetragen.add(s);
      } else {
        _spaeter.add(s);
      }
      if (_eingetragen.contains(s) || s == AngabeSchritt.produktfoto) {
        _sichern();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _laeuft = false;
        _fehler = 'Speichern fehlgeschlagen: ${fehlerText(e)}';
      });
      return;
    }
    if (!mounted) return;
    if (_letzter) {
      Navigator.of(context).pop(_ergebnis);
      return;
    }
    setState(() {
      _index++;
      _laeuft = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final aktuell =
        ref.watch(projektProvider(_id)).valueOrNull ?? widget.projekt;
    final s = _schritt;
    final anzahl = widget.schritte.length;
    final (frage, erklaerung) = _texte(s);
    final fehler = _fehler;
    return AlertDialog(
      key: const ValueKey('angaben-assistent'),
      title: Row(
        children: [
          const Expanded(child: Text('Angaben ergänzen')),
          Text(
            '${_index + 1} von $anzahl',
            key: const ValueKey('assistent-stand'),
            style: theme.textTheme.labelLarge?.copyWith(color: grau),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: (_index + 1) / anzahl,
                  minHeight: 4,
                ),
              ),
              const SizedBox(height: 16),
              Text(frage, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                erklaerung,
                style: theme.textTheme.bodySmall?.copyWith(color: grau),
              ),
              const SizedBox(height: 14),
              KeyedSubtree(
                key: ValueKey('schritt-${s.name}'),
                child: _eingabe(context, s, aktuell),
              ),
              if (fehler != null) ...[
                const SizedBox(height: 12),
                HinweisBox(fehler, art: StatusArt.fehler),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('assistent-schliessen'),
          onPressed: _laeuft ? null : _schliessen,
          child: const Text('Schließen'),
        ),
        TextButton(
          key: const ValueKey('assistent-spaeter'),
          onPressed: _laeuft ? null : () => _weiter(spaeter: true),
          child: const Text('Später'),
        ),
        FilledButton(
          key: const ValueKey('assistent-weiter'),
          onPressed: _laeuft ? null : _weiter,
          child: Text(_letzter ? 'Fertig' : 'Weiter'),
        ),
      ],
    );
  }

  Widget _eingabe(
    BuildContext context,
    AngabeSchritt s,
    EntwicklungsProjekt aktuell,
  ) {
    Widget vorschlaege(List<String> liste, TextEditingController c) => Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final v in liste)
              ActionChip(
                label: Text(v),
                onPressed: () => setState(() => c.text = v),
              ),
          ],
        );

    switch (s) {
      case AngabeSchritt.artikelnummer:
        return TextField(
          controller: _nummer,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Artikelnummer'),
          onSubmitted: (_) => _weiter(),
        );
      case AngabeSchritt.sensorik:
        // Das erste leere Feld bekommt den Cursor.
        final erstesLeeres = _sinne.entries
            .where((e) => e.value.text.trim().isEmpty)
            .firstOrNull
            ?.key;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (k, label) in const [
              ('aussehen', 'Aussehen'),
              ('geruch', 'Geruch'),
              ('geschmack', 'Geschmack'),
              ('konsistenz', 'Konsistenz'),
            ]) ...[
              TextField(
                key: ValueKey('assistent-$k'),
                controller: _sinne[k],
                autofocus: k == erstesLeeres,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(labelText: label),
              ),
              const SizedBox(height: 10),
            ],
          ],
        );
      case AngabeSchritt.produktfoto:
        final bildId = aktuell.bildDateiId;
        if (bildId != null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 180, child: FotoAnsicht(dateiId: bildId)),
              const SizedBox(height: 6),
              Align(
                child: TextButton.icon(
                  onPressed: _laeuft
                      ? null
                      : () => produktfotoWaehlen(context, ref, aktuell),
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Anderes Foto…'),
                ),
              ),
            ],
          );
        }
        return Align(
          child: FilledButton.tonalIcon(
            key: const ValueKey('assistent-foto-waehlen'),
            onPressed: _laeuft
                ? null
                : () => produktfotoWaehlen(context, ref, aktuell),
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Foto wählen…'),
          ),
        );
      case AngabeSchritt.lagerung:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('assistent-lagerung'),
              controller: _lagerung,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Transport und Lagerung',
              ),
              onSubmitted: (_) => _weiter(),
            ),
            const SizedBox(height: 10),
            vorschlaege(kLagerungVorschlaege, _lagerung),
          ],
        );
      case AngabeSchritt.haltbarkeit:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('assistent-haltbarkeit'),
              controller: _haltbarkeit,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Haltbarkeit',
                hintText: 'etwa „21" oder „12 Monate bei -18 °C"',
              ),
              onSubmitted: (_) => _weiter(),
            ),
            const SizedBox(height: 10),
            vorschlaege(kHaltbarkeitVorschlaege, _haltbarkeit),
          ],
        );
      case AngabeSchritt.verpackung:
        return VerpackungEingabe(
          wert: _angaben.verpackung,
          onAenderung: _verpackung,
        );
    }
  }
}
