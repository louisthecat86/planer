import 'package:flutter/material.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/services/prozess_vorlagen.dart';

/// Name einer Abteilung zum dbValue — der Wert selbst, wenn es sie nicht
/// gibt.
String abteilungsName(String dbValue) {
  for (final a in Abteilung.values) {
    if (a.dbValue == dbValue) return a.anzeigeName;
  }
  return dbValue;
}

/// „Anlage · Tätigkeit" eines Schritts — oder „Handarbeit".
String schrittText(VorlagenSchritt s) {
  final teile = [
    if (s.maschine?.trim() case final m? when m.isNotEmpty) m,
    if (s.prozessschritt?.trim() case final p? when p.isNotEmpty) p,
  ];
  return teile.isEmpty ? 'ohne Anlage' : teile.join(' · ');
}

/// Die Stichworte einer Vorlage als eine Zeile.
String stichwortText(ProzessVorlage v) {
  if (v.muss.isEmpty) return 'Keine Stichworte — wird nie vorgeschlagen';
  final muss = v.muss.map((m) => m.replaceAll('|', ' oder ')).join(' + ');
  return v.nicht.isEmpty ? muss : '$muss · nicht: ${v.nicht.join(', ')}';
}

/// Die Schritte einer Vorlage untereinander: Nummer, Abteilung, Anlage
/// und Tätigkeit.
class VorlagenSchritte extends StatelessWidget {
  const VorlagenSchritte({super.key, required this.vorlage});

  final ProzessVorlage vorlage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    if (vorlage.schritte.isEmpty) {
      return Text('Noch keine Schritte.', style: grau);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, s) in vorlage.schritte.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(
                  width: 26,
                  child: Text('${i + 1}.', style: grau),
                ),
                SizedBox(
                  width: 150,
                  child: Text(
                    abteilungsName(s.abteilung),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    schrittText(s),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
