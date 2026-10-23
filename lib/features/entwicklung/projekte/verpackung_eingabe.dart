import 'package:flutter/material.dart';

import '../rezepturen/rezeptur_screen.dart' show TextFeld;
import '../spezifikation/spez_angaben.dart';

// Die Verpackung einer Spezifikation zum Eintragen: Umverpackung und
// Einzelverpackung mit Auswahl und Feldern. Dieselben Eingaben im Reiter
// „Produkt" und im Assistenten „Angaben ergänzen…" — jede Angabe gibt es
// nur einmal.

/// Umverpackung und Einzelverpackung zum Eintragen. Jede Änderung meldet
/// die ganze neue [Verpackung]; Felder melden sich beim Verlassen.
class VerpackungEingabe extends StatelessWidget {
  const VerpackungEingabe({
    super.key,
    required this.wert,
    required this.onAenderung,
  });

  final Verpackung wert;
  final ValueChanged<Verpackung> onAenderung;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = wert;
    const abstand = SizedBox(height: 10);

    Widget mehrfach(
      List<SpezWahl> liste,
      Set<String> gewaehlt,
      ValueChanged<Set<String>> neu,
    ) =>
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final w in liste)
              FilterChip(
                label: Text(w.label),
                selected: gewaehlt.contains(w.schluessel),
                onSelected: (an) => neu(
                  an
                      ? {...gewaehlt, w.schluessel}
                      : (gewaehlt.toSet()..remove(w.schluessel)),
                ),
              ),
          ],
        );

    Widget einfach(
      String titel,
      List<SpezWahl> liste,
      String gewaehlt,
      ValueChanged<String> neu,
    ) =>
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 92,
              child: Text(titel, style: theme.textTheme.bodySmall),
            ),
            for (final w in liste)
              ChoiceChip(
                label: Text(w.label),
                selected: gewaehlt == w.schluessel,
                // Noch einmal tippen nimmt die Wahl zurück.
                onSelected: (an) => neu(an ? w.schluessel : ''),
              ),
          ],
        );

    Widget feld(
      String schluessel,
      String wert,
      String label,
      ValueChanged<String> neu, {
      double breite = 150,
    }) =>
        SizedBox(
          width: breite,
          child: TextFeld(
            key: ValueKey('spez-$schluessel'),
            wert: wert,
            label: label,
            onFertig: neu,
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Umverpackung', style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        mehrfach(
          kUmverpackungen,
          v.um,
          (neu) => onAenderung(wert.kopie(um: neu)),
        ),
        abstand,
        einfach(
          'Karton',
          kKartonAufmachungen,
          v.karton,
          (neu) => onAenderung(wert.kopie(karton: neu)),
        ),
        const SizedBox(height: 6),
        einfach(
          'Befüllung',
          kUmFuellungen,
          v.umFuellung,
          (neu) => onAenderung(wert.kopie(umFuellung: neu)),
        ),
        abstand,
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            feld(
              'um-tara',
              v.umTara,
              'Taragewicht',
              (t) => onAenderung(wert.kopie(umTara: t)),
            ),
            feld(
              'um-netto',
              v.umNetto,
              'Nettogewicht',
              (t) => onAenderung(wert.kopie(umNetto: t)),
            ),
            feld(
              'um-material',
              v.umMaterial,
              'Material',
              (t) => onAenderung(wert.kopie(umMaterial: t)),
            ),
          ],
        ),
        const Divider(height: 28),
        Text('Einzelverpackung', style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        mehrfach(
          kEinzelverpackungen,
          v.einzel,
          (neu) => onAenderung(wert.kopie(einzel: neu)),
        ),
        abstand,
        einfach(
          'Atmosphäre',
          kAtmosphaeren,
          v.atmosphaere,
          (neu) => onAenderung(wert.kopie(atmosphaere: neu)),
        ),
        const SizedBox(height: 6),
        einfach(
          'Befüllung',
          kEinzelFuellungen,
          v.einzelFuellung,
          (neu) =>
              onAenderung(wert.kopie(einzelFuellung: neu)),
        ),
        abstand,
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            feld(
              'anzahl',
              v.anzahl,
              'Anzahl je Umverpackung',
              (t) => onAenderung(wert.kopie(anzahl: t)),
              breite: 200,
            ),
            feld(
              'stueckzahl',
              v.stueckzahl,
              'Stückzahl',
              (t) => onAenderung(wert.kopie(stueckzahl: t)),
            ),
            feld(
              'einzel-tara',
              v.einzelTara,
              'Taragewicht',
              (t) => onAenderung(wert.kopie(einzelTara: t)),
            ),
            feld(
              'einzel-netto',
              v.einzelNetto,
              'Nettogewicht',
              (t) => onAenderung(wert.kopie(einzelNetto: t)),
            ),
            feld(
              'einzel-material',
              v.einzelMaterial,
              'Material',
              (t) => onAenderung(wert.kopie(einzelMaterial: t)),
            ),
          ],
        ),
      ],
    );
  }
}
