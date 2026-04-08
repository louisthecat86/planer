import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/database/database.dart';
import '../../core/providers/backup_provider.dart';
import '../../core/services/backup_service.dart';

class LandingScreen extends ConsumerStatefulWidget {
  const LandingScreen({required this.database, super.key});

  final AppDatabase database;

  @override
  ConsumerState<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends ConsumerState<LandingScreen> {
  bool _isImporting = false;

  Future<void> _handleImport(BuildContext context) async {
    if (_isImporting) return;

    final filepath = await pickBackupFile();
    if (filepath == null) return;

    setState(() {
      _isImporting = true;
    });

    try {
      await BackupService.importBackup(filepath, widget.database, clearExisting: true);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Backup erfolgreich geladen.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
        context.goNamed('home');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler beim Import: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              const Icon(Icons.production_quantity_limits, size: 72, color: Colors.blueAccent),
              const SizedBox(height: 24),
              const Text(
                'Produktions Planung',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Willkommen beim Produktionsplaner. Lade optional ein Backup oder gehe direkt zur App.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.black54),
              ),
              const SizedBox(height: 40),
              ElevatedButton.icon(
                onPressed: _isImporting ? null : () => _handleImport(context),
                icon: _isImporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.restore),
                label: const Text('Backup einspielen'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  if (context.mounted) {
                    context.goNamed('home');
                  }
                },
                icon: const Icon(Icons.home),
                label: const Text('Zur Produktionsplanung'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                margin: EdgeInsets.zero,
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  border: Border.all(color: Colors.blue.shade200),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Wie nutze ich den Produktionsplaner?',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      Text(
                        '1. Optional: Lade ein bestehendes Backup, um deine vorhandenen Daten wiederherzustellen.',
                      ),
                      SizedBox(height: 8),
                      Text(
                        '2. Wenn kein Backup benötigt wird, tippe auf "Zur Produktionsplanung", um direkt in die App zu wechseln.',
                      ),
                      SizedBox(height: 8),
                      Text(
                        '3. Nach dem Backup-Import sind deine aktuellen Daten ersetzt. Du kannst jederzeit neue Backups erstellen oder wiederherstellen.',
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
