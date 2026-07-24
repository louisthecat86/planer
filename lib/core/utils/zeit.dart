import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// App-weite Zeitangaben — **immer** Stunden und Minuten, nie Dezimalstunden.
///
/// Hintergrund: „2,5 h" wurde in der Praxis als 2 h 50 min gelesen statt als
/// 2 h 30 min. In einer Produktionsplanung ist das eine echte Fehlerquelle.
/// Deshalb gibt es hier eine einzige Stelle für Formatierung und Umrechnung,
/// und für Eingaben das Widget [ZeitEingabe] mit zwei getrennten Feldern.
class Zeit {
  const Zeit._();

  /// Minuten in Stunden und Minuten zerlegen.
  static (int stunden, int minuten) zuHM(double gesamtMinuten) {
    final gerundet = gesamtMinuten.round();
    return (gerundet ~/ 60, gerundet % 60);
  }

  /// Stunden + Minuten zu Gesamtminuten.
  static double ausHM(int stunden, int minuten) =>
      (stunden * 60 + minuten).toDouble();

  /// Lange Schreibweise: „2 h 12 min", „45 min", „3 h".
  /// Für Fließtext und Detailansichten.
  static String lang(double? gesamtMinuten) {
    if (gesamtMinuten == null) return '—';
    final (h, m) = zuHM(gesamtMinuten);
    if (h == 0) return '$m min';
    if (m == 0) return '$h h';
    return '$h h $m min';
  }

  /// Kurze Schreibweise: „2:12 h". Für Chips, Tabellen und enge Zellen —
  /// bewusst mit Doppelpunkt, damit niemand sie als Dezimalzahl liest.
  static String kurz(double? gesamtMinuten) {
    if (gesamtMinuten == null) return '—';
    final (h, m) = zuHM(gesamtMinuten);
    return '$h:${m.toString().padLeft(2, '0')} h';
  }

  /// Wie [kurz], aber ohne Einheit — z.B. für „0:42 / 9:00".
  static String kurzOhneEinheit(double? gesamtMinuten) {
    if (gesamtMinuten == null) return '—';
    final (h, m) = zuHM(gesamtMinuten);
    return '$h:${m.toString().padLeft(2, '0')}';
  }

  /// Liest alte Textformate ein: „2:30", „2.5" (Stunden) oder „150"
  /// (Minuten). Wird für Bestandsdaten und den Excel-Import gebraucht.
  static double? ausText(String? text) {
    final t = (text ?? '').trim();
    if (t.isEmpty) return null;
    if (t.contains(':')) {
      final teile = t.split(':');
      final h = int.tryParse(teile[0].trim()) ?? 0;
      final m = teile.length > 1 ? (int.tryParse(teile[1].trim()) ?? 0) : 0;
      return ausHM(h, m);
    }
    // Ohne Doppelpunkt: reine Minutenzahl.
    return double.tryParse(t.replaceAll(',', '.'));
  }
}

/// Eingabe einer Dauer als zwei getrennte Felder (Stunden / Minuten).
///
/// Verhindert die klassische Verwechslung zwischen „2,5 Stunden" und
/// „2 Stunden 50 Minuten". Meldet die Gesamtdauer in Minuten zurück.
class ZeitEingabe extends StatefulWidget {
  const ZeitEingabe({
    super.key,
    required this.minuten,
    required this.onChanged,
    this.label,
    this.enabled = true,
    this.kompakt = false,
  });

  /// Aktuelle Dauer in Minuten (null = leer).
  final double? minuten;

  /// Neue Dauer in Minuten; null, wenn beide Felder leer sind.
  final ValueChanged<double?> onChanged;

  /// Überschrift über den Feldern (optional).
  final String? label;

  final bool enabled;

  /// Schmalere Darstellung für enge Dialoge.
  final bool kompakt;

  @override
  State<ZeitEingabe> createState() => _ZeitEingabeState();
}

class _ZeitEingabeState extends State<ZeitEingabe> {
  late final TextEditingController _std;
  late final TextEditingController _min;

  @override
  void initState() {
    super.initState();
    final m = widget.minuten;
    if (m == null) {
      _std = TextEditingController();
      _min = TextEditingController();
    } else {
      final (h, mm) = Zeit.zuHM(m);
      _std = TextEditingController(text: h == 0 ? '' : '$h');
      _min = TextEditingController(text: mm == 0 && h != 0 ? '' : '$mm');
    }
  }

  @override
  void dispose() {
    _std.dispose();
    _min.dispose();
    super.dispose();
  }

  void _melden() {
    final h = int.tryParse(_std.text.trim());
    final m = int.tryParse(_min.text.trim());
    if (h == null && m == null) {
      widget.onChanged(null);
      return;
    }
    widget.onChanged(Zeit.ausHM(h ?? 0, m ?? 0));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final feldBreite = widget.kompakt ? 66.0 : 84.0;

    Widget feld(
      TextEditingController c,
      String label,
      String suffix, {
      int? maxWert,
    }) {
      return SizedBox(
        width: feldBreite,
        child: TextField(
          controller: c,
          enabled: widget.enabled,
          textAlign: TextAlign.end,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: label,
            suffixText: suffix,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) {
            // Minuten über 59 in Stunden umrechnen — wer „90" tippt,
            // meint eineinhalb Stunden und soll das auch sehen.
            if (maxWert != null) {
              final zahl = int.tryParse(v.trim());
              if (zahl != null && zahl > maxWert) {
                final zusatz = zahl ~/ 60;
                final rest = zahl % 60;
                final bisher = int.tryParse(_std.text.trim()) ?? 0;
                _std.text = '${bisher + zusatz}';
                c.text = '$rest';
                c.selection =
                    TextSelection.collapsed(offset: c.text.length);
              }
            }
            _melden();
          },
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
        ],
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            feld(_std, 'Std.', 'h'),
            const SizedBox(width: 6),
            feld(_min, 'Min.', 'min', maxWert: 59),
          ],
        ),
      ],
    );
  }
}
