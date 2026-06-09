import 'dart:convert';

import 'package:flutter/material.dart';

/// Schematische Darstellung der Plattentemperaturen einer Bratstraße bzw.
/// eines Kombiofens — analog zur Excel-Vorlage:
///
/// - Bratstraße: 10 Platten **oben** + 10 Platten **unten**
/// - Kombiofen:  12 Platten **unten** (kein oben)
///
/// Das Widget ist bewusst DB-agnostisch: es bekommt die Werte herein
/// ([PlattenTemperaturen]) und meldet Änderungen über [onChanged] zurück.
/// Die Persistenz (z. B. als JSON-Parameter am Schritt) liegt außerhalb.

/// Welche Anlage dargestellt wird.
enum BratschemaTyp { bratstrasse, kombiofen }

/// Anzahl Zonen je Anlagentyp.
const int kBratstrasseZonen = 10;
const int kKombiofenZonen = 12;

/// Plattentemperaturen als zwei Zonen-Listen (°C). `null` = nicht gesetzt.
class PlattenTemperaturen {
  const PlattenTemperaturen({required this.oben, required this.unten});

  final List<double?> oben;
  final List<double?> unten;

  /// Leere Werte passend zum Typ (Bratstraße 10/10, Kombiofen 0/12).
  factory PlattenTemperaturen.leer(BratschemaTyp typ) {
    switch (typ) {
      case BratschemaTyp.bratstrasse:
        return PlattenTemperaturen(
          oben: List<double?>.filled(kBratstrasseZonen, null),
          unten: List<double?>.filled(kBratstrasseZonen, null),
        );
      case BratschemaTyp.kombiofen:
        return PlattenTemperaturen(
          oben: const <double?>[],
          unten: List<double?>.filled(kKombiofenZonen, null),
        );
    }
  }

  /// Liest die Werte aus einem JSON-String. Fehlt/kaputt → leere Werte.
  /// Listen werden auf die zum Typ passende Länge gebracht.
  factory PlattenTemperaturen.fromJson(String? json, BratschemaTyp typ) {
    final leer = PlattenTemperaturen.leer(typ);
    if (json == null || json.trim().isEmpty) return leer;
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      List<double?> lese(String key, int laenge) {
        final raw = (map[key] as List?) ?? const [];
        return List<double?>.generate(laenge, (i) {
          if (i >= raw.length) return null;
          final v = raw[i];
          if (v == null) return null;
          if (v is num) return v.toDouble();
          return double.tryParse(v.toString().replaceAll(',', '.'));
        });
      }

      return PlattenTemperaturen(
        oben: lese('oben', leer.oben.length),
        unten: lese('unten', leer.unten.length),
      );
    } catch (_) {
      return leer;
    }
  }

  String toJson() => jsonEncode({'oben': oben, 'unten': unten});

  /// `true`, wenn überhaupt ein Wert gesetzt ist.
  bool get hatWerte =>
      oben.any((v) => v != null) || unten.any((v) => v != null);

  PlattenTemperaturen copyWith({List<double?>? oben, List<double?>? unten}) =>
      PlattenTemperaturen(
        oben: oben ?? this.oben,
        unten: unten ?? this.unten,
      );
}

// ---------------------------------------------------------------------------
// Schema-Widget
// ---------------------------------------------------------------------------

class BratstrasseSchema extends StatelessWidget {
  const BratstrasseSchema({
    super.key,
    required this.typ,
    required this.werte,
    required this.onChanged,
  });

  final BratschemaTyp typ;
  final PlattenTemperaturen werte;
  final void Function(PlattenTemperaturen) onChanged;

  bool get _zeigtOben => typ == BratschemaTyp.bratstrasse;

  Future<void> _bearbeite(BuildContext context, bool oben, int index) async {
    final aktuell = oben ? werte.oben[index] : werte.unten[index];
    final res = await _ZahlDialog.show(
      context,
      titel: 'Platte ${oben ? "oben" : "unten"} ${index + 1} (°C)',
      aktuell: aktuell,
    );
    if (res == null) return; // abgebrochen
    final liste = List<double?>.of(oben ? werte.oben : werte.unten);
    liste[index] = res.wert;
    onChanged(
      oben ? werte.copyWith(oben: liste) : werte.copyWith(unten: liste),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titel = _zeigtOben
        ? 'Plattentemperaturen (oben / unten)'
        : 'Plattentemperaturen unten';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                titel,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const Spacer(),
              Icon(
                Icons.arrow_forward,
                size: 13,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 4),
              Text(
                'Laufrichtung',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_zeigtOben) ...[
            _ZonenReihe(
              label: 'oben',
              werte: werte.oben,
              onTap: (i) => _bearbeite(context, true, i),
            ),
            const SizedBox(height: 6),
            _BandBalken(),
            const SizedBox(height: 6),
          ],
          _ZonenReihe(
            label: 'unten',
            werte: werte.unten,
            onTap: (i) => _bearbeite(context, false, i),
          ),
        ],
      ),
    );
  }
}

/// Eine Zonen-Reihe (Platten oben oder unten) mit antippbaren Zellen.
class _ZonenReihe extends StatelessWidget {
  const _ZonenReihe({
    required this.label,
    required this.werte,
    required this.onTap,
  });

  final String label;
  final List<double?> werte;
  final void Function(int) onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 48,
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Platten\n$label',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                height: 1.1,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (var i = 0; i < werte.length; i++)
                _ZonenZelle(
                  index: i,
                  wert: werte[i],
                  onTap: () => onTap(i),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Eine einzelne Platten-Zelle — Farbe nach Temperatur, tippen zum Ändern.
class _ZonenZelle extends StatelessWidget {
  const _ZonenZelle({
    required this.index,
    required this.wert,
    required this.onTap,
  });

  final int index;
  final double? wert;
  final VoidCallback onTap;

  static Color _tempFarbe(double? t) {
    if (t == null) return const Color(0x1F9E9E9E); // neutral, dezent
    final anteil = (t.clamp(0, 300) / 300).toDouble();
    return Color.lerp(
      const Color(0xFFFAEEDA),
      const Color(0xFFEF9F27),
      anteil,
    )!;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gesetzt = wert != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 44,
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          color: _tempFarbe(wert),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.25),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: 9,
                color: gesetzt
                    ? const Color(0xFF854F0B)
                    : theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            Text(
              gesetzt ? '${wert!.round()}°' : '–',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: gesetzt
                    ? const Color(0xFF6B3E08)
                    : theme.colorScheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Der laufende Band-Balken zwischen oben und unten (rein visuell).
class _BandBalken extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 16,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.25),
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        'Band',
        style: theme.textTheme.bodySmall?.copyWith(
          fontSize: 10,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Zahl-Eingabe-Dialog (liefert null = abgebrochen, sonst Wert/Leeren)
// ---------------------------------------------------------------------------

class _ZahlDialog extends StatefulWidget {
  const _ZahlDialog({required this.titel, required this.aktuell});

  final String titel;
  final double? aktuell;

  static Future<({double? wert})?> show(
    BuildContext context, {
    required String titel,
    required double? aktuell,
  }) {
    return showDialog<({double? wert})>(
      context: context,
      builder: (_) => _ZahlDialog(titel: titel, aktuell: aktuell),
    );
  }

  @override
  State<_ZahlDialog> createState() => _ZahlDialogState();
}

class _ZahlDialogState extends State<_ZahlDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.aktuell == null ? '' : '${widget.aktuell!.round()}',
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titel),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          suffixText: '°C',
          border: OutlineInputBorder(),
          hintText: 'leer = nicht gesetzt',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () {
            final txt = _ctrl.text.trim().replaceAll(',', '.');
            final wert = txt.isEmpty ? null : double.tryParse(txt);
            Navigator.of(context).pop((wert: wert));
          },
          child: const Text('OK'),
        ),
      ],
    );
  }
}