import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/artikel_merkmale.dart';
import '../../../core/database/database.dart';
import '../../../core/druck/druck_fenster.dart';
import '../../../core/theme/app_stil.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/fehler_text.dart';
import '../../../core/utils/sheet_utils.dart';
import '../daten/entwicklung_repository.dart';
import '../import/suite_import_dialog.dart';
import '../rechenkern/rechen_modell.dart';
import 'zutat_dialog.dart';
import 'zutatenkatalog_druck.dart';

/// Der Zutaten-Katalog: Rohstoffe mit Nährwerten, Allergenen und den
/// Angaben für Etikett und Fleischanteil.
class ZutatenAnsicht extends ConsumerStatefulWidget {
  const ZutatenAnsicht({super.key});

  @override
  ConsumerState<ZutatenAnsicht> createState() => _ZutatenAnsichtState();
}

class _ZutatenAnsichtState extends ConsumerState<ZutatenAnsicht> {
  final _suche = TextEditingController();
  String _text = '';

  @override
  void dispose() {
    _suche.dispose();
    super.dispose();
  }

  Future<void> _bearbeiten(Zutat? zutat) async {
    await showSheetOhneAnimation<void>(
      context: context,
      constraints: const BoxConstraints(maxWidth: 760),
      builder: (_) => ZutatDialog(zutat: zutat),
    );
  }

  bool _passt(Zutat z) => zutatTrifft(z, _text);

  /// Öffnet das Druckfenster — mit der Suche, wenn die Liste gerade sucht.
  Future<void> _drucken(List<Zutat> alle) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await druckFensterOeffnen(
        context,
        zutatenkatalogDruckAuftrag(alle, suche: _text),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
            'Die Zutaten ließen sich nicht drucken. (${fehlerText(e)})',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final zutaten = ref.watch(zutatenProvider);
    return zutaten.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: HinweisBox(
          fehlerText(e),
          art: StatusArt.fehler,
          titel: 'Die Zutaten ließen sich nicht laden',
          auswaehlbar: true,
        ),
      ),
      data: (alle) {
        final treffer = alle.where(_passt).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Row(
                children: [
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: TextField(
                        controller: _suche,
                        decoration: InputDecoration(
                          hintText: 'Suche nach Name oder Artikelnummer …',
                          prefixIcon: const Icon(Icons.search, size: 18),
                          suffixIcon: _text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  tooltip: 'Suche leeren',
                                  onPressed: () {
                                    _suche.clear();
                                    setState(() => _text = '');
                                  },
                                ),
                        ),
                        onChanged: (v) => setState(() => _text = v),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${treffer.length} von ${alle.length} Zutaten',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton.outlined(
                    key: const ValueKey('zutaten-drucken'),
                    tooltip: 'Zutaten drucken',
                    onPressed: alle.isEmpty ? null : () => _drucken(alle),
                    icon: const Icon(Icons.print_outlined, size: 18),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => _bearbeiten(null),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Neue Zutat'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Material(
                  color: theme.colorScheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppMasse.ecken,
                    side: BorderSide(color: theme.colorScheme.outline),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final breit = c.maxWidth >= 820;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Kopf(breit: breit),
                          Expanded(
                            child: treffer.isEmpty
                                ? Center(
                                    child: LeerHinweis(
                                      alle.isEmpty
                                          ? 'Noch keine Zutaten. Lege die '
                                              'erste an — oder übernimm den '
                                              'Katalog der alten Suite.'
                                          : 'Keine Treffer.',
                                      icon: alle.isEmpty
                                          ? Icons.egg_outlined
                                          : Icons.search_off,
                                      aktion: alle.isEmpty
                                          ? TextButton.icon(
                                              onPressed: () =>
                                                  suiteImportStarten(context),
                                              icon: const Icon(
                                                Icons.move_to_inbox_outlined,
                                                size: 18,
                                              ),
                                              label: const Text(
                                                'Aus der Suite übernehmen',
                                              ),
                                            )
                                          : null,
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: treffer.length,
                                    itemBuilder: (_, i) => _Zeile(
                                      zutat: treffer[i],
                                      breit: breit,
                                      onTap: () => _bearbeiten(treffer[i]),
                                    ),
                                  ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

abstract final class _Spalten {
  static const double nummer = 96;
  static const double art = 120;
  static const double allergene = 210;
  static const double naehrwerte = 92;
  static const double luecke = 12;
}

class _Kopf extends StatelessWidget {
  const _Kopf({required this.breit});

  final bool breit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stil = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurfaceVariant,
    );
    Widget spalte(String text, double breite) => SizedBox(
          width: breite,
          child: Text(text, maxLines: 1, style: stil),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: AppFarben.von(context).leiste,
        border: Border(bottom: BorderSide(color: theme.colorScheme.outline)),
      ),
      child: Row(
        children: [
          Expanded(child: Text('Zutat', style: stil)),
          const SizedBox(width: _Spalten.luecke),
          if (breit) ...[
            spalte('Art.-Nr.', _Spalten.nummer),
            const SizedBox(width: _Spalten.luecke),
          ],
          spalte('Art', _Spalten.art),
          if (breit) ...[
            const SizedBox(width: _Spalten.luecke),
            spalte('Allergene', _Spalten.allergene),
            const SizedBox(width: _Spalten.luecke),
            spalte('Nährwerte', _Spalten.naehrwerte),
          ],
        ],
      ),
    );
  }
}

class _Zeile extends StatelessWidget {
  const _Zeile({
    required this.zutat,
    required this.breit,
    required this.onTap,
  });

  final Zutat zutat;
  final bool breit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final stil = theme.textTheme.bodyMedium;
    final z = zutat;
    final tierart = Tierart.aus(z.tierart);
    final art = z.istWasser
        ? 'Wasser'
        : z.istFleisch
            ? (tierart == null ? 'Fleisch' : 'Fleisch · ${tierart.label}')
            : '—';
    final allergene = merkmaleLabel(z.allergene, kAllergene);
    final naehrwerteDa = rechenZutatAus(z).naehrwerte.bekannt || z.istWasser;
    final etikett = z.etikettName?.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      z.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: stil?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (etikett != null && etikett.isNotEmpty)
                      Text(
                        'Etikett: $etikett',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: grau,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: _Spalten.luecke),
              if (breit) ...[
                SizedBox(
                  width: _Spalten.nummer,
                  child: Text(
                    z.artikelnummer ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: stil?.copyWith(color: grau),
                  ),
                ),
                const SizedBox(width: _Spalten.luecke),
              ],
              SizedBox(
                width: _Spalten.art,
                child: Text(
                  art,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: stil?.copyWith(color: art == '—' ? grau : null),
                ),
              ),
              if (breit) ...[
                const SizedBox(width: _Spalten.luecke),
                SizedBox(
                  width: _Spalten.allergene,
                  child: Text(
                    allergene.isEmpty ? '—' : allergene,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: stil?.copyWith(color: allergene.isEmpty ? grau : null),
                  ),
                ),
                const SizedBox(width: _Spalten.luecke),
                SizedBox(
                  width: _Spalten.naehrwerte,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    heightFactor: 1,
                    child: naehrwerteDa
                        ? const StatusMarke('da', art: StatusArt.ok)
                        : const StatusMarke('fehlen', art: StatusArt.warnung),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
