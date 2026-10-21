import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/ui/bausteine.dart';
import '../daten/entwicklung_repository.dart';
import '../entwicklung_format.dart';
import '../rechenkern/rechen_modell.dart';
import '../rechenkern/rechenkern.dart';

/// Eine Zeile des Vergleichs: dieselbe Zutat oder Unterrezeptur in zwei
/// Ständen.
class VergleichsZeile {
  const VergleichsZeile({required this.name, this.mengeA, this.mengeB});

  final String name;

  /// null: in diesem Stand nicht enthalten.
  final double? mengeA;
  final double? mengeB;

  bool get neu => mengeA == null && mengeB != null;
  bool get entfernt => mengeA != null && mengeB == null;
  bool get geaendert =>
      mengeA != null && mengeB != null && (mengeA! - mengeB!).abs() > 1e-9;
}

/// Stellt die Zeilen zweier Stände nebeneinander — gleiche Zutaten und
/// Unterrezepturen zusammen, in der Reihenfolge von [a], Neues dahinter.
List<VergleichsZeile> vergleicheZeilen(RechenRezeptur a, RechenRezeptur b) {
  String schluessel(RechenPosition p) =>
      p.zutat?.id ?? 'rezeptur:${p.unterrezeptur?.id}';
  String name(RechenPosition p) =>
      p.zutat?.name ?? p.unterrezeptur?.name ?? '?';

  final reihenfolge = <String>[];
  final namen = <String, String>{};
  final mengenA = <String, double>{};
  final mengenB = <String, double>{};
  for (final p in a.positionen) {
    final k = schluessel(p);
    if (!mengenA.containsKey(k)) reihenfolge.add(k);
    namen[k] = name(p);
    mengenA[k] = (mengenA[k] ?? 0) + p.mengeKg;
  }
  for (final p in b.positionen) {
    final k = schluessel(p);
    if (!mengenA.containsKey(k) && !mengenB.containsKey(k)) {
      reihenfolge.add(k);
    }
    namen[k] = name(p);
    mengenB[k] = (mengenB[k] ?? 0) + p.mengeKg;
  }
  return [
    for (final k in reihenfolge)
      VergleichsZeile(name: namen[k]!, mengeA: mengenA[k], mengeB: mengenB[k]),
  ];
}

/// Vergleicht zwei Stände einer Rezeptur: Zusammensetzung, Verlust und
/// Ergebnis.
class VersionsVergleichDialog extends ConsumerStatefulWidget {
  const VersionsVergleichDialog({
    super.key,
    required this.versionen,
    required this.aId,
    required this.bId,
  });

  final List<RezepturVersion> versionen;
  final String aId;
  final String bId;

  @override
  ConsumerState<VersionsVergleichDialog> createState() =>
      _VersionsVergleichDialogState();
}

class _VersionsVergleichDialogState
    extends ConsumerState<VersionsVergleichDialog> {
  late String _a = widget.aId;
  late String _b = widget.bId;

  String _name(String id) {
    for (final v in widget.versionen) {
      if (v.id == id) {
        final b = v.bezeichnung?.trim();
        return 'Stand ${v.nummer}${b == null || b.isEmpty ? '' : ' · $b'}';
      }
    }
    return '?';
  }

  Widget _wahl(String wert, ValueChanged<String> setzen) =>
      DropdownButton<String>(
        value: wert,
        isDense: true,
        items: [
          for (final v in widget.versionen)
            DropdownMenuItem(value: v.id, child: Text(_name(v.id))),
        ],
        onChanged: (v) {
          if (v != null) setState(() => setzen(v));
        },
      );

  @override
  Widget build(BuildContext context) {
    final a = ref.watch(rechenRezepturProvider(_a)).valueOrNull;
    final b = ref.watch(rechenRezepturProvider(_b)).valueOrNull;
    final hoehe = math.max(
      240.0,
      math.min(620.0, MediaQuery.of(context).size.height - 220),
    );
    return AlertDialog(
      title: Row(
        children: [
          const Text('Vergleich'),
          const SizedBox(width: 16),
          _wahl(_a, (v) => _a = v),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.compare_arrows, size: 18),
          ),
          _wahl(_b, (v) => _b = v),
        ],
      ),
      content: SizedBox(
        width: 760,
        height: hoehe,
        child: a == null || b == null
            ? const Center(child: CircularProgressIndicator())
            : _Inhalt(
                a: a,
                b: b,
                nameA: _name(_a),
                nameB: _name(_b),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Schließen'),
        ),
      ],
    );
  }
}

class _Inhalt extends StatelessWidget {
  const _Inhalt({
    required this.a,
    required this.b,
    required this.nameA,
    required this.nameB,
  });

  final RechenRezeptur a;
  final RechenRezeptur b;
  final String nameA;
  final String nameB;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final farben = theme.colorScheme;
    final ea = berechne(a);
    final eb = berechne(b);
    final zeilen = vergleicheZeilen(a, b);
    final zahlen = theme.textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    String menge(double? kg) => kg == null ? '—' : '${mengeText(kg)} kg';

    Widget zahlZeile(String label, String wa, String wb) {
      final anders = wa != wb;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            SizedBox(
              width: 120,
              child: Text(wa, textAlign: TextAlign.right, style: zahlen),
            ),
            SizedBox(
              width: 120,
              child: Text(
                wb,
                textAlign: TextAlign.right,
                style: zahlen?.copyWith(
                  fontWeight: anders ? FontWeight.w700 : null,
                  color: anders ? farben.primary : null,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      children: [
        Bereich(
          titel: 'Zusammensetzung',
          untertitel: '$nameA → $nameB',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final z in zeilen)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          z.name,
                          style: TextStyle(
                            color: z.entfernt ? grau : null,
                            decoration:
                                z.entfernt ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                      if (z.neu)
                        const StatusMarke('neu', art: StatusArt.ok)
                      else if (z.entfernt)
                        const StatusMarke('entfernt', art: StatusArt.fehler)
                      else if (z.geaendert)
                        const StatusMarke('geändert', art: StatusArt.info),
                      SizedBox(
                        width: 110,
                        child: Text(
                          menge(z.mengeA),
                          textAlign: TextAlign.right,
                          style: zahlen?.copyWith(color: grau),
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        child: Text(
                          menge(z.mengeB),
                          textAlign: TextAlign.right,
                          style: zahlen?.copyWith(
                            fontWeight:
                                z.neu || z.geaendert ? FontWeight.w700 : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Bereich(
          titel: 'Ergebnis',
          untertitel: '$nameA → $nameB',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              zahlZeile(
                'Verlust',
                prozentText(a.wirksamerVerlust),
                prozentText(b.wirksamerVerlust),
              ),
              zahlZeile(
                'Endgewicht',
                menge(ea.endgewichtKg),
                menge(eb.endgewichtKg),
              ),
              zahlZeile(
                'Fleischanteil',
                prozentText(ea.fleischanteilProzent),
                prozentText(eb.fleischanteilProzent),
              ),
              zahlZeile(
                'Fett je 100 g',
                prozentText(ea.je100g.fett ?? 0),
                prozentText(eb.je100g.fett ?? 0),
              ),
              zahlZeile(
                'Eiweiß je 100 g',
                prozentText(ea.je100g.eiweiss ?? 0),
                prozentText(eb.je100g.eiweiss ?? 0),
              ),
              zahlZeile(
                'Salz je 100 g',
                prozentText(ea.je100g.salz ?? 0, nachkomma: 2),
                prozentText(eb.je100g.salz ?? 0, nachkomma: 2),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Bereich(
          titel: 'Zutatenliste',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(nameA, style: theme.textTheme.labelMedium),
              SelectableText(ea.zutatenliste),
              const SizedBox(height: 10),
              Text(nameB, style: theme.textTheme.labelMedium),
              SelectableText(
                eb.zutatenliste,
                style: TextStyle(
                  fontWeight: ea.zutatenliste == eb.zutatenliste
                      ? null
                      : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
