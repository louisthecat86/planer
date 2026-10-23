import 'package:flutter/material.dart';

import '../../../core/ui/bausteine.dart';
import 'prozess_kette.dart';

// Kleine Eingabefenster des Prozesses: ein Text, ein Wert mit seinen
// Grenzen, ein eigener Wert mit Namen.

/// Ein Text in einem kleinen Fenster — für Namen und Notizen.
class TextEingabeDialog extends StatefulWidget {
  const TextEingabeDialog({
    super.key,
    required this.titel,
    required this.label,
    this.wert = '',
    this.mehrzeilig = false,
    this.bestaetigen = 'Speichern',
    this.leerErlaubt = false,
    this.hinweis,
  });

  final String titel;
  final String label;
  final String wert;
  final bool mehrzeilig;
  final String bestaetigen;

  /// Darf leer bestätigt werden (etwa eine Notiz)?
  final bool leerErlaubt;

  /// Ein Beispiel im leeren Feld.
  final String? hinweis;

  @override
  State<TextEingabeDialog> createState() => _TextEingabeDialogState();
}

class _TextEingabeDialogState extends State<TextEingabeDialog> {
  late final TextEditingController _text =
      TextEditingController(text: widget.wert);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _fertig() {
    if (!widget.leerErlaubt && _text.text.trim().isEmpty) return;
    Navigator.of(context).pop(_text.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titel),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, minWidth: 320),
        child: TextField(
          controller: _text,
          autofocus: true,
          minLines: widget.mehrzeilig ? 3 : 1,
          maxLines: widget.mehrzeilig ? 8 : 1,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hinweis,
            alignLabelWithHint: widget.mehrzeilig,
          ),
          onSubmitted: widget.mehrzeilig ? null : (_) => _fertig(),
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

/// Ein Wert eines Schritts — mit den Grenzen aus der Planung: Außerhalb
/// der harten lässt er sich nicht speichern, außerhalb der weichen gibt es
/// einen Hinweis. Liefert den Wert ohne Leerzeichen am Rand (leer: keiner),
/// null bei Abbruch.
class WertDialog extends StatefulWidget {
  const WertDialog({
    super.key,
    required this.titel,
    this.wert = '',
    this.einheit = '',
    this.grenze,
  });

  final String titel;
  final String wert;
  final String einheit;
  final ParameterGrenze? grenze;

  @override
  State<WertDialog> createState() => _WertDialogState();
}

class _WertDialogState extends State<WertDialog> {
  late final TextEditingController _text =
      TextEditingController(text: widget.wert);
  late GrenzPruefung _pruefung = grenzePruefen(widget.grenze, widget.wert);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _pruefen(String wert) =>
      setState(() => _pruefung = grenzePruefen(widget.grenze, wert));

  void _speichern() {
    final wert = _text.text.trim();
    final p = grenzePruefen(widget.grenze, wert);
    if (p.blockiert) {
      setState(() => _pruefung = p);
      return;
    }
    Navigator.of(context).pop(wert);
  }

  @override
  Widget build(BuildContext context) {
    final p = _pruefung;
    final warnung = p.blockiert ? null : p.meldung;
    return AlertDialog(
      title: Text(widget.titel),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, minWidth: 300),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('wert-eingabe'),
              controller: _text,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Wert',
                suffixText:
                    widget.einheit.trim().isEmpty ? null : widget.einheit,
                errorText: p.blockiert ? p.meldung : null,
                helperText: 'Leer nimmt den Wert heraus.',
              ),
              onChanged: _pruefen,
              onSubmitted: (_) => _speichern(),
            ),
            if (warnung != null) ...[
              const SizedBox(height: 8),
              HinweisBox(warnung, art: StatusArt.warnung),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(onPressed: _speichern, child: const Text('Speichern')),
      ],
    );
  }
}

/// Ein eigener Wert: Name und Wert. Liefert beides ohne Leerzeichen am
/// Rand — null bei Abbruch.
class EigenerWertDialog extends StatefulWidget {
  const EigenerWertDialog({
    super.key,
    this.name = '',
    this.wert = '',
    this.vergeben = const {},
  });

  final String name;
  final String wert;

  /// Namen, die der Schritt schon hat (klein geschrieben) — ein zweiter
  /// Wert gleichen Namens wäre nicht vom ersten zu unterscheiden.
  final Set<String> vergeben;

  @override
  State<EigenerWertDialog> createState() => _EigenerWertDialogState();
}

class _EigenerWertDialogState extends State<EigenerWertDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.name);
  late final TextEditingController _wert =
      TextEditingController(text: widget.wert);
  String? _fehler;

  @override
  void dispose() {
    _name.dispose();
    _wert.dispose();
    super.dispose();
  }

  void _fertig() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _fehler = 'Wie heißt der Wert?');
      return;
    }
    if (widget.vergeben.contains(name.toLowerCase())) {
      setState(() => _fehler = 'Einen Wert „$name" gibt es schon.');
      return;
    }
    Navigator.of(context).pop((name: name, wert: _wert.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.name.isEmpty ? 'Eigener Wert' : 'Wert bearbeiten'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, minWidth: 300),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('eigener-wert-name'),
              controller: _name,
              autofocus: widget.name.isEmpty,
              decoration: InputDecoration(
                labelText: 'Name',
                hintText: 'etwa „Kerntemperatur"',
                errorText: _fehler,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('eigener-wert-wert'),
              controller: _wert,
              autofocus: widget.name.isNotEmpty,
              decoration: const InputDecoration(labelText: 'Wert'),
              onSubmitted: (_) => _fertig(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(onPressed: _fertig, child: const Text('Übernehmen')),
      ],
    );
  }
}
