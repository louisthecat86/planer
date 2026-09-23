part of 'article_detail_screen.dart';

// ---------------------------------------------------------------------------
// Tab 3: Produktionsdaten
// ---------------------------------------------------------------------------

class _ProductionTab extends ConsumerWidget {
  const _ProductionTab({required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final histAsync = ref.watch(productionHistoryProvider(productId));

    return histAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Noch keine Produktionsdaten.\n\n'
                'Importiere eine Excel-Vorlage mit ausgefülltem Block '
                '„HISTORISCHE DATEN", dann erscheinen hier alle '
                'vergangenen Produktionen samt Ausbeute und kg/h.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _KennzahlenCard(rows: rows),
            const SizedBox(height: 16),
            Text(
              'Vergangene Produktionen (${rows.length})',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            for (final r in rows)
              _HistorieCard(
                eintrag: r,
                onTap: () async {
                  final geaendert = await ProductionEntryDialog.show(
                    context,
                    productId,
                    existing: r,
                  );
                  if (geaendert) {
                    ref.invalidate(productionHistoryProvider(productId));
                  }
                },
              ),
          ],
        );
      },
    );
  }
}

/// Aggregierte Kennzahlen über alle historischen Produktionen.
class _KennzahlenCard extends StatelessWidget {
  const _KennzahlenCard({required this.rows});

  final List<ProductionHistoryData> rows;

  @override
  Widget build(BuildContext context) {
    double summeRoh = 0;
    double summeFertig = 0;
    var hatMengen = false;

    final kgHWerte = <double>[];
    for (final r in rows) {
      if (r.kgRohware != null) {
        summeRoh += r.kgRohware!;
        hatMengen = true;
      }
      if (r.kgFertigware != null) summeFertig += r.kgFertigware!;
      if (r.kgProStundeRoh != null) kgHWerte.add(r.kgProStundeRoh!);
    }

    final double? ausbeute =
        (hatMengen && summeRoh > 0) ? summeFertig / summeRoh : null;
    final double? garverlust = ausbeute != null ? 1 - ausbeute : null;
    final double? avgKgH = kgHWerte.isNotEmpty
        ? kgHWerte.reduce((a, b) => a + b) / kgHWerte.length
        : null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF37474F), Color(0xFF455A64)],
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.insights, color: Colors.white, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Kennzahlen',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 20,
              runSpacing: 16,
              children: [
                _Kennzahl(
                  value: '${rows.length}',
                  label: 'Produktionen',
                ),
                if (ausbeute != null)
                  _Kennzahl(
                    value: fmtProzent(ausbeute),
                    label: 'Ø Ausbeute',
                  ),
                if (garverlust != null)
                  _Kennzahl(
                    value: fmtProzent(garverlust),
                    label: 'Ø Garverlust',
                    valueColor: const Color(0xFFFF8A65),
                  ),
                if (avgKgH != null)
                  _Kennzahl(
                    value: '${fmtKg(avgKgH)} kg/h',
                    label: 'Ø Durchsatz roh',
                  ),
              ],
            ),
            if (hatMengen) ...[
              const SizedBox(height: 14),
              Text(
                'Gesamt: ${fmtKg(summeRoh)} kg Rohware ? '
                '${fmtKg(summeFertig)} kg Fertigware',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Kennzahl extends StatelessWidget {
  const _Kennzahl({
    required this.value,
    required this.label,
    this.valueColor,
  });

  final String value;
  final String label;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 11),
        ),
      ],
    );
  }
}

/// Eine vergangene Produktion als Karte.
class _HistorieCard extends StatelessWidget {
  const _HistorieCard({required this.eintrag, this.onTap});

  final ProductionHistoryData eintrag;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Garverlust: gespeicherten Anteil bevorzugen, sonst aus Roh/Fertig.
    double? verlust = eintrag.verlustAnteil;
    if (verlust == null &&
        eintrag.kgRohware != null &&
        eintrag.kgFertigware != null &&
        eintrag.kgRohware! > 0) {
      verlust = 1 - (eintrag.kgFertigware! / eintrag.kgRohware!);
    }

    final zeitText = (eintrag.startzeit != null && eintrag.endzeit != null)
        ? '${eintrag.startzeit} – ${eintrag.endzeit}'
        : (eintrag.startzeit ?? '');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.event,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  fmtDatum(eintrag.datum),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (eintrag.quelle == 'app')
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'in App erfasst',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFF2E7D32),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 18,
              runSpacing: 10,
              children: [
                _HistWert(
                  label: 'Rohware',
                  value: '${fmtKg(eintrag.kgRohware)} kg',
                ),
                _HistWert(
                  label: 'Fertigware',
                  value: '${fmtKg(eintrag.kgFertigware)} kg',
                ),
                if (verlust != null)
                  _HistWert(
                    label: 'Garverlust',
                    value: fmtProzent(verlust),
                  ),
                if (eintrag.produktionszeitMinuten != null)
                  _HistWert(
                    label: 'Dauer',
                    value: fmtDauer(eintrag.produktionszeitMinuten),
                  ),
                if (eintrag.kgProStundeRoh != null)
                  _HistWert(
                    label: 'kg/h roh',
                    value: fmtKg(eintrag.kgProStundeRoh),
                  ),
              ],
            ),
            if (zeitText.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.schedule,
                    size: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    zeitText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
            if (eintrag.notizen != null && eintrag.notizen!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                eintrag.notizen!,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
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

class _HistWert extends StatelessWidget {
  const _HistWert({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Leistungsdaten-Dialog: Referenzleistung je Abteilung erfassen
// ---------------------------------------------------------------------------

/// Geführte Maske: fragt für jede Abteilung des Prozesses die
/// Referenzleistung ab — „Menge X kg in Zeit Y". Daraus zeigt sie live die
/// Kennzahl kg/h und schreibt die Werte beim Speichern auf den ersten
/// Schritt jeder Abteilungsgruppe. Mit diesen Basiswerten skaliert die App
/// die Dauer jeder Planmenge
/// (Dauer = Fixzeit + Zeit × Planmenge ÷ Referenzmenge).
///
/// Bewusst **personenunabhängig**: Wie viele Leute an einer Anlage stehen,
/// hängt am einzelnen Schritt (`basisMitarbeiter`) und wird dort im
/// Step-Editor gepflegt. Die Abteilungszahl ist die Summe über ihre
/// Schritte und wird nur angezeigt, nie hier geschrieben.
class _LeistungsdatenDialog extends ConsumerStatefulWidget {
  const _LeistungsdatenDialog({required this.eintraege});

  /// Je Abteilung: der erste Schritt (trägt die Referenzwerte) und alle
  /// Schritte der Gruppe (für die Personensumme in der Anzeige).
  final List<
      ({
        Abteilung abteilung,
        ProductStep erster,
        List<ProductStep> schritte,
      })> eintraege;

  @override
  ConsumerState<_LeistungsdatenDialog> createState() =>
      _LeistungsdatenDialogState();
}

class _LeistungsdatenDialogState
    extends ConsumerState<_LeistungsdatenDialog> {
  late final List<TextEditingController> _menge;
  /// Dauer je Abteilung in MINUTEN (aus der Stunden/Minuten-Eingabe).
  late List<double?> _zeitMin;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _menge = [
      for (final e in widget.eintraege)
        TextEditingController(
          text: e.erster.basisMengeKg > 0
              ? e.erster.basisMengeKg.round().toString()
              : '',
        ),
    ];
    _zeitMin = [
      for (final e in widget.eintraege)
        e.erster.basisDauerMinuten > 0 ? e.erster.basisDauerMinuten : null,
    ];
  }

  @override
  void dispose() {
    for (final c in _menge) {
      c.dispose();
    }
    super.dispose();
  }

  /// Personen der Abteilung = Summe über ihre Schritte. Reine Anzeige;
  /// gepflegt wird die Zahl je Schritt im Step-Editor.
  int _personenSumme(int i) => widget.eintraege[i].schritte
      .fold<int>(0, (sum, s) => sum + s.basisMitarbeiter);

  String _kgProStunde(int i) {
    final kg = double.tryParse(_menge[i].text.replaceAll(',', '.'));
    final min = _zeitMin[i];
    if (kg == null || kg <= 0 || min == null || min <= 0) return '—';
    final kgh = kg / (min / 60);
    return '${kgh.toStringAsFixed(0)} kg/h';
  }

  Future<void> _speichern() async {
    setState(() => _busy = true);
    final db = ref.read(databaseProvider);
    final jetzt = DateTime.now();
    var geschrieben = 0;

    for (var i = 0; i < widget.eintraege.length; i++) {
      final kg = double.tryParse(_menge[i].text.replaceAll(',', '.'));
      final min = _zeitMin[i];
      // Nur vollständig ausgefüllte Abteilungen schreiben — leere Zeilen
      // lassen den bestehenden Stand unangetastet.
      if (kg == null || kg <= 0 || min == null || min <= 0) continue;

      await (db.update(db.productSteps)
            ..where((st) => st.id.equals(widget.eintraege[i].erster.id)))
          .write(
        ProductStepsCompanion(
          mengeKg: Value(kg),
          basisMengeKg: Value(kg),
          basisDauerMinuten: Value(min),
          // basisMitarbeiter bleibt unangetastet — die Zahl gehört dem
          // einzelnen Schritt, nicht der Abteilung.
          updatedAt: Value(jetzt),
        ),
      );
      geschrieben++;
    }

    if (geschrieben > 0) {
      ref.read(autoBackupTriggerProvider).fireDebounced(
            reason: 'Leistungsdaten erfasst',
          );
    }
    if (mounted) Navigator.of(context).pop(geschrieben > 0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Leistungsdaten je Abteilung'),
      content: SizedBox(
        // Breit genug für Menge + Std./Min. + die Kennzahlen rechts.
        // Bei 560 lief der Minutenwert in seine eigene Beschriftung.
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Referenz: Welche Menge schafft die Abteilung bei diesem '
                'Artikel in welcher Zeit? Daraus skaliert die App die Dauer '
                'jeder Planmenge. Die Personen je Anlage pflegst du im '
                'jeweiligen Schritt.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              for (var i = 0; i < widget.eintraege.length; i++) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.eintraege[i].abteilung.anzeigeName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      '${_personenSumme(i)} Pers.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _kgProStunde(i),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _menge[i],
                        decoration: const InputDecoration(
                          labelText: 'Menge',
                          suffixText: 'kg',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Getrennte Stunden-/Minutenfelder: „0:08" war als
                    // Freitext fehleranfällig und ließ offen, ob 8 Minuten
                    // oder 8 Stunden gemeint sind.
                    //
                    // Nicht kompakt: Die schmalen Felder (66pt) sind zu eng,
                    // sobald Wert und Einheit zusammen darin stehen.
                    ZeitEingabe(
                      kompakt: false,
                      minuten: _zeitMin[i],
                      onChanged: (m) => setState(() => _zeitMin[i] = m),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _busy ? null : _speichern,
          child: Text(_busy ? 'Speichern …' : 'Speichern'),
        ),
      ],
    );
  }
}


