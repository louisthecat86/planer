import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';

const kProduktgruppen = <({String dbValue, String label})>[
  (dbValue: 'bruehwurst', label: 'Brühwurst'),
  (dbValue: 'rohwurst', label: 'Rohwurst'),
  (dbValue: 'kochpoekelware', label: 'Kochpökelware'),
  (dbValue: 'rohpoekelware', label: 'Rohpökelware'),
  (dbValue: 'aufschnitt', label: 'Aufschnitt'),
  (dbValue: 'bratstrasse_natur', label: 'Bratstraßenartikel Natur'),
  (dbValue: 'bratstrasse_paniert', label: 'Bratstraßenartikel paniert'),
  (dbValue: 'hackprodukt_gegart', label: 'Hackprodukte gegart'),
  (dbValue: 'hackprodukt_roh', label: 'Hackprodukte roh'),
  (dbValue: 'braten', label: 'Braten'),
  (dbValue: 'sous_vide', label: 'Sous Vide gegarte Produkte'),
  (dbValue: 'angebratene_bruehwurst', label: 'Angebratene Brühwürste'),
];

/// Bottom-Sheet zum Bearbeiten der Artikel-Stammdaten (Bezeichnung,
/// Produktgruppe, Beschreibung, Notizen). Die Artikelnummer ist der
/// Schlüssel zur Excel-Vorlage und bleibt unveränderlich.
class ArticleInfoEditorDialog extends ConsumerStatefulWidget {
  const ArticleInfoEditorDialog({super.key, required this.product});

  final Product product;

  static Future<bool> show(BuildContext context, Product product) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: ArticleInfoEditorDialog(product: product),
      ),
    );
    return result ?? false;
  }

  @override
  ConsumerState<ArticleInfoEditorDialog> createState() =>
      _ArticleInfoEditorDialogState();
}

class _ArticleInfoEditorDialogState
    extends ConsumerState<ArticleInfoEditorDialog> {
  late final TextEditingController _bezeichnung;
  late final TextEditingController _beschreibung;
  late final TextEditingController _notizen;
  String? _produktgruppe;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _bezeichnung = TextEditingController(text: p.artikelbezeichnung);
    _beschreibung = TextEditingController(text: p.beschreibung ?? '');
    _notizen = TextEditingController(text: p.notizen ?? '');
    // Nur gültige Gruppen vorbelegen (sonst zeigt der Dropdown nichts an).
    final gruppe = p.produktgruppe;
    if (gruppe != null && kProduktgruppen.any((g) => g.dbValue == gruppe)) {
      _produktgruppe = gruppe;
    }
  }

  @override
  void dispose() {
    _bezeichnung.dispose();
    _beschreibung.dispose();
    _notizen.dispose();
    super.dispose();
  }

  Future<void> _speichern() async {
    final bez = _bezeichnung.text.trim();
    if (bez.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte eine Bezeichnung eingeben.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      final beschr = _beschreibung.text.trim();
      final notizen = _notizen.text.trim();

      await (db.update(db.products)
            ..where((t) => t.id.equals(widget.product.id)))
          .write(
        ProductsCompanion(
          artikelbezeichnung: Value(bez),
          produktgruppe: Value(_produktgruppe),
          beschreibung: Value(beschr.isEmpty ? null : beschr),
          notizen: Value(notizen.isEmpty ? null : notizen),
          updatedAt: Value(DateTime.now()),
        ),
      );

      ref
          .read(autoBackupTriggerProvider)
          .fireDebounced(reason: 'Artikel-Stammdaten bearbeitet');

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Stammdaten bearbeiten',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),

              // Artikelnummer (read-only)
              InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Artikelnummer',
                  prefixIcon: const Icon(Icons.tag),
                  helperText: 'Schlüssel zur Excel — nicht änderbar',
                  helperStyle: TextStyle(color: colors.onSurfaceVariant),
                ),
                child: Text(widget.product.artikelnummer),
              ),
              const SizedBox(height: 14),

              // Bezeichnung
              TextField(
                controller: _bezeichnung,
                decoration: const InputDecoration(
                  labelText: 'Bezeichnung',
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 14),

              // Produktgruppe
              DropdownButtonFormField<String?>(
                initialValue: _produktgruppe,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Produktgruppe',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    child: Text('— keine —'),
                  ),
                  for (final g in kProduktgruppen)
                    DropdownMenuItem<String?>(
                      value: g.dbValue,
                      child: Text(g.label),
                    ),
                ],
                onChanged: (v) => setState(() => _produktgruppe = v),
              ),
              const SizedBox(height: 14),

              // Besonderheiten (⇄ Excel-Block „Sonstige Informationen")
              TextField(
                controller: _beschreibung,
                decoration: const InputDecoration(
                  labelText: 'Besonderheiten / Sonstige Informationen',
                  helperText: 'Wird mit der Excel synchronisiert '
                      '(Block „Sonstige Informationen")',
                  helperMaxLines: 2,
                  alignLabelWithHint: true,
                ),
                maxLines: 4,
                minLines: 2,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 20),

              // Notizen
              TextField(
                controller: _notizen,
                decoration: const InputDecoration(
                  labelText: 'Notizen',
                ),
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _speichern,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: Text(_saving ? 'Speichern …' : 'Speichern'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
