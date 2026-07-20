import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/ui_scale_provider.dart';

/// Einstellungen — Sammelpunkt für alles, was nicht zum täglichen Planen
/// gehört: Stammdaten (Excel-Import/-Export, Backup, Wiederherstellung)
/// und die Kapazität je Abteilung.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const _AnzeigeGroesse(),
          const SizedBox(height: 8),
          _SettingsTile(
            icon: Icons.folder_open_rounded,
            color: const Color(0xFF00838F),
            title: 'Stammdaten',
            subtitle: 'Excel importieren & exportieren, Backup und '
                'Wiederherstellung',
            onTap: () => context.pushNamed('data'),
          ),
          const SizedBox(height: 8),
          _SettingsTile(
            icon: Icons.bar_chart_rounded,
            color: const Color(0xFF1565C0),
            title: 'Kapazität',
            subtitle: 'Verfügbare Stunden je Abteilung (Standard 9 h/Tag)',
            onTap: () => context.pushNamed('capacity'),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Produktion Planer · offline',
              style: TextStyle(
                fontSize: 12,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
    );
  }
}

/// Regler für die app-weite Anzeigegröße.
///
/// Skaliert die gesamte Schrift über `MediaQuery.textScaler`. Die Auswahl
/// wird dauerhaft gespeichert und gilt sofort in der ganzen App.
class _AnzeigeGroesse extends ConsumerWidget {
  const _AnzeigeGroesse();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scale = ref.watch(uiScaleProvider);
    final notifier = ref.read(uiScaleProvider.notifier);
    final prozent = (scale * 100).round();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6A1B9A).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.format_size_rounded,
                    color: Color(0xFF6A1B9A),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Anzeigegröße',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Schrift und Bedienelemente in der ganzen App',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                IconButton.filledTonal(
                  onPressed:
                      scale <= 0.25 ? null : () => notifier.kleiner(),
                  icon: const Icon(Icons.remove),
                  tooltip: 'Kleiner',
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        '$prozent %',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (prozent == 100)
                        Text(
                          'Normal',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  onPressed:
                      scale >= 2.0 ? null : () => notifier.groesser(),
                  icon: const Icon(Icons.add),
                  tooltip: 'Größer',
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Direkte Stufenauswahl — schneller als mehrfaches Tippen.
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final stufe in kUiScaleStufen)
                  ChoiceChip(
                    label: Text('${(stufe * 100).round()} %'),
                    selected: (scale - stufe).abs() < 0.001,
                    onSelected: (_) => notifier.setzen(stufe),
                  ),
              ],
            ),
            if (prozent != 100) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => notifier.zuruecksetzen(),
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: const Text('Auf 100 % zurücksetzen'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
