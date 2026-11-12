import 'package:erfassung_format/erfassung_format.dart';
import 'package:flutter/material.dart';

import 'artikel_seite.dart';
import 'bausteine.dart';
import 'erfassen_seite.dart';
import 'modell.dart';
import 'stand.dart';
import 'stil.dart';

/// Die geplanten Produktionen des Pakets, je Tag — offen oder erfasst —
/// und darunter, was ohne Plan erfasst wurde.
class ProduktionenSeite extends StatelessWidget {
  const ProduktionenSeite({super.key, required this.modell});

  final ErfassungsModell modell;

  void _erfassen(
    BuildContext context, {
    PaketProduktion? geplant,
    PaketArtikel? artikel,
    ErfassteProduktion? vorhanden,
    ProduktionsEntwurf? begonnen,
  }) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ErfassenSeite(
            modell: modell,
            geplant: geplant,
            artikel: artikel,
            vorhanden: vorhanden,
            begonnen: begonnen,
          ),
        ),
      );

  /// Ohne Plan: erst den Artikel wählen.
  Future<void> _freiErfassen(BuildContext context) async {
    final artikel = await Navigator.of(context).push(
      MaterialPageRoute<PaketArtikel>(
        builder: (_) => ArtikelSeite(modell: modell, waehlen: true),
      ),
    );
    if (artikel == null || !context.mounted) return;
    _erfassen(context, artikel: artikel);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: modell,
      builder: (context, _) {
        final f = Theme.of(context).colorScheme;
        final farben = Farben.von(context);
        final stand = modell.stand;
        final paket = stand.paket;
        final heute = DateTime.now();
        final jeTag = <DateTime, List<PaketProduktion>>{};
        for (final p in paket?.produktionen ?? const <PaketProduktion>[]) {
          (jeTag[p.datum] ??= []).add(p);
        }
        final tage = jeTag.keys.toList()..sort();
        final frei = stand.frei;
        final freiBegonnen = stand.freiBegonnen;
        return Scaffold(
          appBar: AppBar(title: const Text('Produktionen')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              children: [
                if (tage.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Hinweis(
                      'Im Paket steht keine geplante Produktion. Du kannst '
                      'trotzdem erfassen — unten über „Ohne Plan erfassen".',
                      farbe: f.primary,
                    ),
                  ),
                for (final tag in tage) ...[
                  Abschnitt(
                    tagLang(tag, heute),
                    zusatz: '${jeTag[tag]!.length}',
                  ),
                  for (final p in jeTag[tag]!)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TippZeile(
                        titel: p.artikel,
                        unter: [
                          if (p.artikelnummer.isNotEmpty) p.artikelnummer,
                          if (p.abteilungName.isNotEmpty) p.abteilungName,
                          'Rohware ${zahlText(p.rohKg)} kg',
                          if (p.start != null) 'ab ${p.start}',
                        ].join(' · '),
                        streifen: p.abteilungFarbe == null
                            ? null
                            : Color(p.abteilungFarbe!),
                        // Zwischengespeichert ist noch nicht erfasst.
                        rechts: stand.produktionen.containsKey(p.id)
                            ? Marke('erfasst', farbe: farben.ok)
                            : stand.entwuerfe.containsKey(p.id)
                                ? Marke('begonnen', farbe: f.primary)
                                : null,
                        onTap: () => _erfassen(
                          context,
                          geplant: p,
                          vorhanden: stand.produktionen[p.id],
                        ),
                      ),
                    ),
                ],
                if (freiBegonnen.isNotEmpty) ...[
                  Abschnitt(
                    'Ohne Plan begonnen',
                    zusatz: '${freiBegonnen.length}',
                  ),
                  for (final e in freiBegonnen)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TippZeile(
                        titel: e.artikel,
                        unter: [
                          tagKurz(e.datum),
                          if (e.roh.isNotEmpty) 'Rohware ${e.roh} kg',
                          if (e.start.isNotEmpty) 'ab ${e.start}',
                        ].join(' · '),
                        rechts: Marke('begonnen', farbe: f.primary),
                        onTap: () => _erfassen(
                          context,
                          artikel: paket?.artikelMit(e.artikelId),
                          begonnen: e,
                        ),
                      ),
                    ),
                ],
                if (frei.isNotEmpty) ...[
                  Abschnitt('Ohne Plan erfasst', zusatz: '${frei.length}'),
                  for (final e in frei)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TippZeile(
                        titel: e.artikel,
                        unter: '${tagKurz(e.datum)} · Rohware '
                            '${zahlText(e.rohKg)} kg',
                        rechts: Marke('erfasst', farbe: farben.ok),
                        onTap: () => _erfassen(
                          context,
                          artikel: paket?.artikelMit(e.artikelId),
                          vorhanden: e,
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => _freiErfassen(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Ohne Plan erfassen'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
