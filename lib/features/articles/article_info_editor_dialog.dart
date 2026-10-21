import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/artikel_merkmale.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';
import '../../core/utils/fehler_text.dart';
import '../../core/utils/sheet_utils.dart';

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

/// Fenster zum Bearbeiten der Artikel-Stammdaten (Bezeichnung,
/// Produktgruppe, Beschreibung, Merkmale, Notizen). Die Artikelnummer ist
/// der Schlüssel zur Excel-Vorlage und bleibt unveränderlich.
class ArticleInfoEditorDialog extends ConsumerStatefulWidget {
  const ArticleInfoEditorDialog({super.key, required this.product});

  final Product product;

  static Future<bool> show(BuildContext context, Product product) async {
    final result = await showSheetOhneAnimation<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
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

  // Mehrfachauswahlen als Menge von dbValues, Einfachauswahlen als
  // einzelner dbValue oder null.
  final Set<String> _allergene = <String>{};
  final Set<String> _verarbeitung = <String>{};
  final Set<String> _verpackungsformen = <String>{};
  String? _qualitaetsstufe;
  String? _kartonGroesse;
  String? _kartonBedruckung;
  String? _abgabeart;
  late final TextEditingController _packungenProKarton;
  late final TextEditingController _fuellmenge;

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

    _allergene.addAll(merkmaleAusText(p.allergene));
    _verarbeitung.addAll(merkmaleAusText(p.verarbeitungsstufe));
    _verpackungsformen.addAll(merkmaleAusText(p.verpackungsformen));
    _qualitaetsstufe = p.qualitaetsstufe;
    _kartonGroesse = p.kartonGroesse;
    _kartonBedruckung = p.kartonBedruckung;
    _abgabeart = p.abgabeart;
    _packungenProKarton = TextEditingController(
      text: p.packungenProKarton?.toString() ?? '',
    );
    _fuellmenge = TextEditingController(
      text: p.fuellmengeNettoG == null ? '' : _zahlText(p.fuellmengeNettoG!),
    );
  }

  /// Ganze Zahlen ohne Nachkomma anzeigen: „400" statt „400.0".
  static String _zahlText(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  @override
  void dispose() {
    _bezeichnung.dispose();
    _beschreibung.dispose();
    _notizen.dispose();
    _packungenProKarton.dispose();
    _fuellmenge.dispose();
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
          // Merkmale: leere Auswahl wird zu NULL. Nicht gepflegt und
          // „nichts davon" sind damit dasselbe — beim Allergen ist das
          // der Grund, warum der Planungs-Wizard später einen Artikel
          // ohne Eintrag nicht als allergenfrei behandeln darf.
          allergene: Value(merkmaleZuText(_allergene, kAllergene)),
          qualitaetsstufe: Value(_qualitaetsstufe),
          verarbeitungsstufe:
              Value(merkmaleZuText(_verarbeitung, kVerarbeitungsstufen)),
          verpackungsformen: Value(
            merkmaleZuText(_verpackungsformen, kVerpackungsformen),
          ),
          kartonGroesse: Value(_kartonGroesse),
          kartonBedruckung: Value(_kartonBedruckung),
          packungenProKarton:
              Value(int.tryParse(_packungenProKarton.text.trim())),
          fuellmengeNettoG: Value(
            double.tryParse(_fuellmenge.text.trim().replaceAll(',', '.')),
          ),
          abgabeart: Value(_abgabeart),
          // Sobald eine Produktgruppe gesetzt ist, gilt der Artikel als
          // eingepflegt — das „nicht eingepflegt"-Badge verschwindet. Ohne
          // Gruppe bleibt der Status unverändert (ein Stub bleibt Stub, ein
          // bereits gepflegter Altdaten-Artikel bleibt eingepflegt).
          istEingepflegt: _produktgruppe != null
              ? const Value(true)
              : const Value.absent(),
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
          SnackBar(
            content: Text('Fehler: ${fehlerText(e)}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

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
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            children: [
              // Kopf wie bei jedem Dialog der App: Titel in Blau, rechts
              // ein Kreuz. Der graue Anfasser oben stammte aus der Zeit,
              // als das Fenster ein Bottom-Sheet war.
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Stammdaten bearbeiten',
                      style: theme.dialogTheme.titleTextStyle ??
                          theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Schließen ohne Speichern',
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 12),

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

              // ── Allergene ───────────────────────────────────────────
              // Reihenfolge wie in kAllergene: Die Liste ist zugleich die
              // Rangfolge für die Produktionsplanung.
              _abschnitt('Allergene'),
              _allergenChips(),
              const SizedBox(height: 18),

              // ── Qualitätsstufe ──────────────────────────────────────
              _abschnitt('Qualitätsstufe'),
              _einfach(
                kQualitaetsstufen,
                _qualitaetsstufe,
                (v) => setState(() => _qualitaetsstufe = v),
              ),
              const SizedBox(height: 18),

              // ── Verarbeitungsstufe ──────────────────────────────────
              // Mehrfach, weil Garzustand und Lieferzustand gemeint sind.
              _abschnitt('Verarbeitungsstufe'),
              _mehrfach(kVerarbeitungsstufen, _verarbeitung),
              const SizedBox(height: 18),

              // ── Verpackung ──────────────────────────────────────────
              _abschnitt('Verpackung'),
              _mehrfach(kVerpackungsformen, _verpackungsformen),

              // Karton-Details nur zeigen, wenn Karton gewählt ist —
              // sonst stehen zwei Auswahlen ohne Bezug herum.
              if (_verpackungsformen.contains('karton')) ...[
                const SizedBox(height: 10),
                _unterzeile('Karton'),
                _einfach(
                  kKartonGroessen,
                  _kartonGroesse,
                  (v) => setState(() => _kartonGroesse = v),
                ),
                const SizedBox(height: 6),
                _einfach(
                  kKartonBedruckungen,
                  _kartonBedruckung,
                  (v) => setState(() => _kartonBedruckung = v),
                ),
              ],

              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _packungenProKarton,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Packungen pro Karton',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _fuellmenge,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Füllmenge netto',
                        suffixText: 'g',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _unterzeile('Abgabe'),
              _einfach(
                kAbgabearten,
                _abgabeart,
                (v) => setState(() => _abgabeart = v),
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

              // Knöpfe unten rechts wie in jedem Dialog der App.
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saving ? null : _speichern,
                    // Ohne feste Farbe: Der gesperrte Knopf ist hellgrau,
                    // ein weißer Kreisel war darauf unsichtbar.
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save, size: 18),
                    label: Text(_saving ? 'Speichern …' : 'Speichern'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Bausteine für die Auswahlfelder ──────────────────────────────────

  /// Überschrift eines Abschnitts — mit dünner Linie darunter, damit die
  /// lange Maske in Blöcke zerfällt.
  Widget _abschnitt(String titel) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Text(
        titel,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _unterzeile(String titel) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          titel,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );

  /// Allergene: wie eine normale Mehrfachauswahl, aber „Keine" schließt
  /// die übrigen aus und umgekehrt. Leer bleibt „noch nicht gepflegt".
  Widget _allergenChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final m in kAllergene)
          FilterChip(
            label: Text(m.label),
            selected: _allergene.contains(m.dbValue),
            onSelected: _saving
                ? null
                : (an) => setState(() {
                      if (!an) {
                        _allergene.remove(m.dbValue);
                        return;
                      }
                      if (m.dbValue == kAllergenKeine) {
                        _allergene
                          ..clear()
                          ..add(kAllergenKeine);
                      } else {
                        _allergene
                          ..remove(kAllergenKeine)
                          ..add(m.dbValue);
                      }
                    }),
          ),
      ],
    );
  }

  /// Mehrfachauswahl als anklickbare Chips.
  Widget _mehrfach(List<Merkmal> liste, Set<String> auswahl) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final m in liste)
          FilterChip(
            label: Text(m.label),
            selected: auswahl.contains(m.dbValue),
            onSelected: _saving
                ? null
                : (an) => setState(() {
                      if (an) {
                        auswahl.add(m.dbValue);
                      } else {
                        auswahl.remove(m.dbValue);
                      }
                    }),
          ),
      ],
    );
  }

  /// Einfachauswahl: Nochmal antippen hebt die Auswahl wieder auf, damit
  /// ein versehentlich gesetzter Wert ohne Umweg verschwindet.
  Widget _einfach(
    List<Merkmal> liste,
    String? aktuell,
    ValueChanged<String?> onChanged,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final m in liste)
          ChoiceChip(
            label: Text(m.label),
            selected: aktuell == m.dbValue,
            onSelected:
                _saving ? null : (an) => onChanged(an ? m.dbValue : null),
          ),
      ],
    );
  }
}


