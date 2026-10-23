import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/abteilungen.dart';
import '../../../core/theme/app_stil.dart';
import '../../../core/ui/bausteine.dart';
import 'prozess_kette.dart';
import 'prozess_modell.dart';

// Bausteine der Prozesskette eines Projekts, die Kette und Schritt-Fenster
// gemeinsam brauchen: die Nummer eines Schritts, die Wahl einer Anlage und
// das Fenster für Abteilung, Anlage und Prozessschritt.

/// Eine neue, eindeutige ID für einen Schritt.
String neueSchrittId() => const Uuid().v4();

/// Die Farbe der Abteilung [abteilung] — grau ohne Abteilung.
Color abteilungsFarbe(BuildContext context, String abteilung) =>
    abteilungAus(abteilung)?.farbe ?? Theme.of(context).colorScheme.outline;

/// Was gesagt wird, wenn die Kette voll ist.
const String kKetteVollText = 'Höchstens $kProzessMaxSchritte Schritte — '
    'so viele fasst auch die Kette eines Artikels.';

/// Die Nummer eines Schritts in der Kette, in der Farbe seiner Abteilung —
/// an der Kachel und im Kopf des Schritts, wie im Artikel.
class NummernMarke extends StatelessWidget {
  const NummernMarke({
    super.key,
    required this.nummer,
    required this.farbe,
    this.groesse = 20,
  });

  final int nummer;
  final Color farbe;
  final double groesse;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: groesse,
      height: groesse,
      decoration: BoxDecoration(
        color: farbe,
        borderRadius: AppMasse.eckenKlein,
      ),
      alignment: Alignment.center,
      child: Text(
        '$nummer',
        style: TextStyle(
          fontSize: groesse * 0.55,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Die Anlagen nach Abteilung (in der Reihenfolge der Produktion), darin
/// nach Namen.
List<KatalogAnlage> nachAbteilung(Iterable<KatalogAnlage> anlagen) {
  int rang(KatalogAnlage a) => abteilungAus(a.abteilung)?.index ?? 99;
  return [...anlagen]..sort((a, b) {
      final r = rang(a).compareTo(rang(b));
      return r != 0 ? r : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
}

/// Was in der Wahl einer Anlage gewählt wurde — `anlage` null: ein Schritt
/// ohne Anlage.
typedef AnlagenWahlErgebnis = ({KatalogAnlage? anlage});

/// Die Wahl einer Anlage aus dem Katalog der Planung. Für eine Station
/// ([abteilung]) zuerst die ihrer Abteilung, darunter auf Wunsch alle
/// anderen — eine Anlage darf im Projekt auch für eine fremde Abteilung
/// arbeiten. Für eine neue Station (ohne [abteilung]) alle nach Abteilung.
/// Ganz unten ein Schritt ohne Anlage. Liefert null bei Abbruch.
class AnlagenWahl extends StatefulWidget {
  const AnlagenWahl({super.key, required this.katalog, this.abteilung});

  final List<KatalogAnlage> katalog;

  /// Die Abteilung der Station — null: eine neue Station.
  final String? abteilung;

  @override
  State<AnlagenWahl> createState() => _AnlagenWahlState();
}

class _AnlagenWahlState extends State<AnlagenWahl> {
  bool _andere = false;

  void _waehlen(KatalogAnlage? a) =>
      Navigator.of(context).pop<AnlagenWahlErgebnis>((anlage: a));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final abteilung = widget.abteilung;
    final alle = nachAbteilung(widget.katalog);

    Widget zeile(KatalogAnlage a, {bool mitAbteilung = false}) => ListTile(
          key: ValueKey('anlage-${a.id}'),
          dense: true,
          leading: AbteilungsMarke(abteilung: abteilungAus(a.abteilung)),
          title: Text(a.name),
          subtitle: mitAbteilung ? Text(abteilungsName(a.abteilung)) : null,
          onTap: () => _waehlen(a),
        );

    Widget leer(String text) => Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              fontStyle: FontStyle.italic,
              color: grau,
            ),
          ),
        );

    final List<Widget> anlagen;
    if (abteilung != null) {
      final passend = [
        for (final a in alle)
          if (a.abteilung == abteilung) a,
      ];
      final fremde = [
        for (final a in alle)
          if (a.abteilung != abteilung) a,
      ];
      anlagen = [
        if (passend.isEmpty)
          leer('Für diese Abteilung sind keine Anlagen angelegt.'),
        for (final a in passend) zeile(a),
        if (fremde.isNotEmpty) ...[
          const Divider(),
          ListTile(
            key: const ValueKey('anlage-andere'),
            dense: true,
            leading: Icon(_andere ? Icons.expand_less : Icons.expand_more),
            title: const Text('Anlage aus einer anderen Abteilung'),
            subtitle: const Text(
              'Sie bleibt im Katalog ihrer Abteilung und arbeitet in diesem '
              'Projekt hier mit.',
            ),
            onTap: () => setState(() => _andere = !_andere),
          ),
          if (_andere)
            for (final a in fremde) zeile(a, mitAbteilung: true),
        ],
      ];
    } else {
      // Je Abteilung eine Zwischenüberschrift.
      anlagen = [
        if (alle.isEmpty)
          leer('Im Katalog der Planung sind noch keine Anlagen angelegt.'),
      ];
      String? vorige;
      for (final a in alle) {
        if (a.abteilung != vorige) {
          vorige = a.abteilung;
          anlagen.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
              child: Text(
                abteilungsName(a.abteilung),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: grau,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }
        anlagen.add(zeile(a));
      }
    }

    return AlertDialog(
      title: Text(
        abteilung == null
            ? 'Neue Station'
            : 'Anlage für ${abteilungsName(abteilung)}',
      ),
      contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      content: SizedBox(
        width: 420,
        height: 440,
        child: ListView(
          children: [
            ...anlagen,
            const Divider(),
            ListTile(
              key: const ValueKey('anlage-ohne'),
              dense: true,
              leading: const Icon(Icons.edit_note),
              title: const Text('Schritt ohne Anlage …'),
              subtitle: const Text('Nur ein Prozessschritt, etwa „Abkühlen"'),
              onTap: () => _waehlen(null),
            ),
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

/// Ein neuer Schritt: erst die Anlage, ohne Anlage dann Abteilung und
/// Prozessschritt. Für eine Station arbeitet er für deren [abteilung],
/// sonst für die seiner Anlage. Null bei Abbruch.
Future<ProzessSchritt?> neuerSchritt(
  BuildContext context, {
  required List<KatalogAnlage> katalog,
  String? abteilung,
}) async {
  final wahl = await showDialog<AnlagenWahlErgebnis>(
    context: context,
    builder: (_) => AnlagenWahl(katalog: katalog, abteilung: abteilung),
  );
  if (wahl == null || !context.mounted) return null;
  final anlage = wahl.anlage;
  if (anlage != null) {
    return ProzessSchritt(
      id: neueSchrittId(),
      abteilung: abteilung ?? anlage.abteilung,
      maschineId: anlage.id,
      maschine: anlage.name,
    );
  }
  return showDialog<ProzessSchritt>(
    context: context,
    builder: (_) => SchrittDialog(
      schritt: ProzessSchritt(id: neueSchrittId(), abteilung: abteilung ?? ''),
      katalog: katalog,
      titel: 'Schritt ohne Anlage',
      bestaetigen: 'Hinzufügen',
    ),
  );
}

/// Ein Name einer Anlage, die nicht im Katalog steht — als Wahl im Feld
/// „Anlage".
const String _kAlsText = '\u0000text';

/// Die Zwischenüberschrift im Feld „Anlage" — nicht wählbar.
const String _kUeberschrift = '\u0000fremde';

/// Abteilung, Anlage und Prozessschritt eines Schritts. Liefert den
/// geänderten Schritt, null bei Abbruch.
class SchrittDialog extends StatefulWidget {
  const SchrittDialog({
    super.key,
    required this.schritt,
    required this.katalog,
    this.titel = 'Schritt bearbeiten',
    this.bestaetigen = 'Übernehmen',
  });

  final ProzessSchritt schritt;
  final List<KatalogAnlage> katalog;
  final String titel;
  final String bestaetigen;

  @override
  State<SchrittDialog> createState() => _SchrittDialogState();
}

class _SchrittDialogState extends State<SchrittDialog> {
  late String _abteilung = widget.schritt.abteilung;

  /// Die Anlage, wie der Schritt sie hat — die Wahl im Feld beim Öffnen.
  late final String? _anfang = _wahlVon(widget.schritt);
  late String? _anlage = _anfang;
  late final TextEditingController _prozess =
      TextEditingController(text: widget.schritt.prozessschritt);
  String? _fehler;

  @override
  void dispose() {
    _prozess.dispose();
    super.dispose();
  }

  KatalogAnlage? _imKatalog(String? id) {
    if (id == null) return null;
    for (final a in widget.katalog) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Der Name einer Anlage, die nicht (mehr) im Katalog steht — leer, wenn
  /// es keinen gibt.
  String get _textName => _imKatalog(widget.schritt.maschineId) == null
      ? widget.schritt.maschine.trim()
      : '';

  String? _wahlVon(ProzessSchritt s) {
    if (_imKatalog(s.maschineId) != null) return s.maschineId;
    return s.maschine.trim().isEmpty ? null : _kAlsText;
  }

  void _fertig() {
    final prozess = _prozess.text.trim();
    final anlage = _imKatalog(_anlage);
    final name = _anlage == _kAlsText ? _textName : '';
    if (anlage == null && name.isEmpty && prozess.isEmpty) {
      setState(
        () => _fehler = 'Ohne Anlage braucht der Schritt einen Prozessschritt.',
      );
      return;
    }
    var s =
        widget.schritt.kopie(abteilung: _abteilung, prozessschritt: prozess);
    if (_anlage != _anfang) s = anlageSetzen(s, anlage, name: name);
    Navigator.of(context).pop(s);
  }

  List<DropdownMenuItem<String?>> _anlagen(ThemeData theme) {
    final alle = nachAbteilung(widget.katalog);
    final eigene = [
      for (final a in alle)
        if (a.abteilung == _abteilung) a,
    ];
    final fremde = [
      for (final a in alle)
        if (a.abteilung != _abteilung) a,
    ];
    final text = _textName;
    return [
      const DropdownMenuItem<String?>(
        value: null,
        child: Text(
          '— keine Anlage —',
          style: TextStyle(fontStyle: FontStyle.italic),
        ),
      ),
      if (text.isNotEmpty)
        DropdownMenuItem<String?>(
          value: _kAlsText,
          child: Text('$text (nicht im Katalog)'),
        ),
      for (final a in eigene)
        DropdownMenuItem<String?>(value: a.id, child: Text(a.name)),
      if (fremde.isNotEmpty)
        DropdownMenuItem<String?>(
          value: _kUeberschrift,
          enabled: false,
          child: Text(
            'Aus anderen Abteilungen',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      for (final a in fremde)
        DropdownMenuItem<String?>(
          value: a.id,
          child: Text('${a.name} · ${abteilungsName(a.abteilung)}'),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bisher = widget.schritt.abteilung;
    return AlertDialog(
      title: Text(widget.titel),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                key: const ValueKey('schritt-abteilung'),
                initialValue: _abteilung,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Abteilung'),
                items: [
                  // Ohne oder mit unbekannter Abteilung bleibt sie wählbar.
                  if (abteilungAus(bisher) == null)
                    DropdownMenuItem(
                      value: bisher,
                      child: Text(abteilungsName(bisher)),
                    ),
                  for (final a in Abteilung.values)
                    DropdownMenuItem(
                      value: a.dbValue,
                      child: Row(
                        children: [
                          AbteilungsMarke(abteilung: a),
                          const SizedBox(width: 8),
                          Text(a.anzeigeName),
                        ],
                      ),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _abteilung = v);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: const ValueKey('schritt-anlage'),
                initialValue: _anlage,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Anlage'),
                items: _anlagen(theme),
                onChanged: (v) => setState(() => _anlage = v),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('schritt-prozessschritt'),
                controller: _prozess,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Prozessschritt',
                  hintText: 'etwa „Braten" oder „Abkühlen"',
                  errorText: _fehler,
                ),
                onSubmitted: (_) => _fertig(),
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
        FilledButton(onPressed: _fertig, child: Text(widget.bestaetigen)),
      ],
    );
  }
}
