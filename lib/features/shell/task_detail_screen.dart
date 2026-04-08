import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';

class TaskDetailScreen extends ConsumerWidget {
  const TaskDetailScreen({
    required this.database,
    required this.taskId,
    super.key,
  });

  final AppDatabase database;
  final String taskId;

  Future<_TaskDetailData> _loadTask() async {
    final task = await (database.select(database.productionTasks)
          ..where((tbl) => tbl.id.equals(taskId)))
        .getSingleOrNull();

    if (task == null) {
      throw Exception('Auftrag nicht gefunden.');
    }

    final product = await (database.select(database.products)
          ..where((tbl) => tbl.id.equals(task.productId)))
        .getSingleOrNull();

    return _TaskDetailData(task: task, product: product);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Auftragsdetails'),
      ),
      body: FutureBuilder<_TaskDetailData>(
        future: _loadTask(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  snapshot.error.toString(),
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final data = snapshot.data!;
          final task = data.task;
          final product = data.product;
          final statusColor = _statusColor(task.status);
          final department = Abteilung.fromDbValue(task.abteilung);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: department.farbe,
                            child: Text(
                              department.kurzcode,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              product != null
                                  ? '${product.artikelnummer} · ${product.artikelbezeichnung}'
                                  : task.productId,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Chip(
                            label: Text(_statusLabel(task.status)),
                            backgroundColor: statusColor.withOpacity(0.14),
                            labelStyle: TextStyle(color: statusColor),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _DetailBadge(
                            icon: Icons.calendar_today,
                            label: _formatDate(task.datum),
                          ),
                          _DetailBadge(
                            icon: Icons.schedule,
                            label: task.startZeit ?? 'Keine Startzeit',
                          ),
                          _DetailBadge(
                            icon: Icons.timer,
                            label: _formatDuration(task.geplanteDauerMinuten),
                          ),
                          _DetailBadge(
                            icon: Icons.people,
                            label: '${task.geplanteMitarbeiter} Mitarbeiter',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Details',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _InfoRow(label: 'Abteilung', value: department.anzeigeName),
                      _InfoRow(label: 'Auftrags-ID', value: task.id),
                      if (task.parentTaskId != null)
                        _InfoRow(label: 'Eltern-Auftrag', value: task.parentTaskId!),
                      _InfoRow(label: 'Produkt-ID', value: task.productId),
                      _InfoRow(label: 'Erstellt', value: _formatDateTime(task.createdAt)),
                      _InfoRow(label: 'Zuletzt aktualisiert', value: _formatDateTime(task.updatedAt)),
                    ],
                  ),
                ),
              ),
              if (task.notizen != null && task.notizen!.isNotEmpty)
                const SizedBox(height: 16),
              if (task.notizen != null && task.notizen!.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Notizen',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(task.notizen!),
                      ],
                    ),
                  ),
                ),
              if (product != null) const SizedBox(height: 16),
              if (product != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Produkt',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _InfoRow(label: 'Artikelnummer', value: product.artikelnummer),
                        _InfoRow(label: 'Bezeichnung', value: product.artikelbezeichnung),
                        if (product.beschreibung != null)
                          _InfoRow(label: 'Beschreibung', value: product.beschreibung!),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TaskDetailData {
  _TaskDetailData({required this.task, required this.product});

  final ProductionTask task;
  final Product? product;
}

class _DetailBadge extends StatelessWidget {
  const _DetailBadge({required this.icon, required this.label, super.key});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16, color: Colors.grey.shade700),
      label: Text(label),
      backgroundColor: Colors.grey.shade100,
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'in_arbeit':
      return 'In Arbeit';
    case 'fertig':
      return 'Fertig';
    case 'storniert':
      return 'Storniert';
    default:
      return 'Geplant';
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'in_arbeit':
      return const Color(0xFF0288D1);
    case 'fertig':
      return const Color(0xFF2E7D32);
    case 'storniert':
      return Colors.red;
    default:
      return const Color(0xFFFB8C00);
  }
}

String _formatDuration(double minutes) {
  final duration = Duration(minutes: minutes.round());
  final hours = duration.inHours;
  final remainingMinutes = duration.inMinutes % 60;
  return '${hours}h ${remainingMinutes.toString().padLeft(2, '0')}m';
}

String _formatDate(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

String _formatDateTime(DateTime dateTime) {
  return '${_formatDate(dateTime)} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
}
