import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Einstellungen — Sammelpunkt für alles, was nicht zum täglichen Planen
/// gehört: Stammdaten (Excel-Import/-Export, Backup, Wiederherstellung)
/// und die Kapazität je Abteilung.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
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
            subtitle: 'Verfügbare Stunden je Abteilung (Standard 8 h/Tag)',
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