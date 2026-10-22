import 'package:flutter/material.dart';

import '../../../core/database/database.dart';
import 'haccp_ansicht.dart';
import 'prozess_ansicht.dart';

// Der Reiter „Herstellung" eines Projekts (F26): der Prozess und seine
// HACCP-Gefahrenanalyse. Breit stehen beide nebeneinander, schmal schaltet
// man zwischen ihnen um.

/// Ab dieser Breite stehen Prozess und HACCP nebeneinander.
const double kHerstellungNebeneinander = 1200;

/// Prozess und HACCP eines Projekts.
class ProjektHerstellung extends StatefulWidget {
  const ProjektHerstellung({super.key, required this.projekt});

  final EntwicklungsProjekt projekt;

  @override
  State<ProjektHerstellung> createState() => _ProjektHerstellungState();
}

class _ProjektHerstellungState extends State<ProjektHerstellung> {
  // Beim Wechsel zwischen breit und schmal behalten beide ihren Stand —
  // auch einen noch nicht gespeicherten Prozess.
  final _prozess = GlobalKey();
  final _haccp = GlobalKey();

  /// Schmal: Ist HACCP zu sehen (sonst der Prozess)?
  bool _zeigeHaccp = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.projekt;
    final prozess = ProjektProzess(key: _prozess, projekt: p);
    final haccp = ProjektHaccp(key: _haccp, projekt: p);
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= kHerstellungNebeneinander) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: _Spalte(
                  titel: 'Prozess',
                  icon: Icons.precision_manufacturing_outlined,
                  child: prozess,
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                flex: 2,
                child: _Spalte(
                  titel: 'HACCP',
                  icon: Icons.health_and_safety_outlined,
                  child: haccp,
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<bool>(
                  key: const ValueKey('herstellung-umschalten'),
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.precision_manufacturing_outlined),
                      label: Text('Prozess'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.health_and_safety_outlined),
                      label: Text('HACCP'),
                    ),
                  ],
                  selected: {_zeigeHaccp},
                  onSelectionChanged: (wahl) =>
                      setState(() => _zeigeHaccp = wahl.first),
                ),
              ),
            ),
            Expanded(
              // Beide bleiben aufgebaut — der verdeckte nur unsichtbar.
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Visibility(
                    visible: !_zeigeHaccp,
                    maintainState: true,
                    child: prozess,
                  ),
                  Visibility(
                    visible: _zeigeHaccp,
                    maintainState: true,
                    child: haccp,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Eine Spalte mit Überschrift — breit nebeneinander.
class _Spalte extends StatelessWidget {
  const _Spalte({
    required this.titel,
    required this.icon,
    required this.child,
  });

  final String titel;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(titel, style: theme.textTheme.titleMedium),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
