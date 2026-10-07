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

/// Kennzahlen der erfassten Produktionen. Ausbeute und Leistung sind der
/// Ø der letzten [kLetzteProduktionen] — genau die Zahlen, mit denen die
/// Planung rechnet.
class _KennzahlenCard extends StatelessWidget {
  const _KennzahlenCard({required this.rows});

  /// Neueste zuerst (siehe [productionHistoryProvider]).
  final List<ProductionHistoryData> rows;

  @override
  Widget build(BuildContext context) {
    double summeRoh = 0;
    double summeFertig = 0;
    var hatMengen = false;
    for (final r in rows) {
      if (r.kgRohware != null) {
        summeRoh += r.kgRohware!;
        hatMengen = true;
      }
      if (r.kgFertigware != null) summeFertig += r.kgFertigware!;
    }

    final ausbeute = ausbeuteAusProduktionen(rows);
    final leistung = leistungAusProduktionen(rows);

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
                if (ausbeute != null) ...[
                  _Kennzahl(
                    value: fmtProzent(ausbeute.faktor),
                    label: 'Ø Ausbeute',
                  ),
                  _Kennzahl(
                    value: fmtProzent(1 - ausbeute.faktor),
                    label: 'Ø Garverlust',
                    valueColor: const Color(0xFFFF8A65),
                  ),
                ],
                if (leistung != null)
                  _Kennzahl(
                    value: '${fmtKg(leistung.kgProStunde.roundToDouble())} '
                        'kg/h',
                    label: 'Ø Leistung roh',
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Ausbeute und Leistung: Ø der letzten $kLetzteProduktionen '
              'Produktionen — damit rechnet die Planung.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            if (hatMengen) ...[
              const SizedBox(height: 4),
              Text(
                'Gesamt: ${fmtKg(summeRoh)} kg Rohware → '
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
/// Kennzahl kg/h und schreibt die Werte beim Speichern über den
/// [ProzesskettenService] an den ersten Schritt jeder Abteilungsgruppe.
/// Damit skaliert die App die Dauer jeder Planmenge
/// (Dauer = Zeit × Planmenge ÷ Referenzmenge). Bleibt eine Abteilung
/// leer, rechnet sie mit den erfassten Produktionen.
///
/// Bewusst **personenunabhängig**: Wie viele Leute an einer Anlage stehen,
/// hängt am einzelnen Schritt (`basisMitarbeiter`) und wird dort im
/// Step-Editor gepflegt. Die Abteilungszahl ist die Summe über ihre
/// Schritte und wird nur angezeigt, nie hier geschrieben.
class _LeistungsdatenDialog extends ConsumerStatefulWidget {
  const _LeistungsdatenDialog({required this.eintraege});

  /// Je Abteilung: der erste Schritt (dort landen die Referenzwerte) und
  /// alle Schritte der Gruppe (für die geltenden Werte und die
  /// Personensumme in der Anzeige).
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

  /// Stand beim Öffnen — unveränderte Zeilen werden nicht geschrieben,
  /// und eine geleerte Zeile erkennt man nur im Vergleich.
  late final List<Leistungsdaten?> _vorher;
  late final List<String> _mengeVorher;

  /// Was die erfassten Produktionen sagen: die Grundlage, wenn für eine
  /// Abteilung nichts hinterlegt ist.
  HistorienLeistung? _historie;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _vorher = [
      for (final e in widget.eintraege) leistungsdatenVon(e.schritte),
    ];
    _mengeVorher = [
      for (final l in _vorher) l == null ? '' : l.mengeKg.round().toString(),
    ];
    _menge = [for (final t in _mengeVorher) TextEditingController(text: t)];
    _zeitMin = [for (final l in _vorher) l?.minuten];
    _ladeHistorie();
  }

  Future<void> _ladeHistorie() async {
    if (widget.eintraege.isEmpty) return;
    final db = ref.read(databaseProvider);
    final h = await historienLeistung(
      db,
      widget.eintraege.first.erster.productId,
    );
    if (mounted) setState(() => _historie = h);
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

  bool _istLeer(int i) => _menge[i].text.trim().isEmpty && _zeitMin[i] == null;

  /// Womit die Abteilung rechnet, solange ihre Zeile leer ist — und für
  /// die Bratstraße, ob hinterlegte Werte überhaupt zählen.
  String? _grundlage(int i) {
    final h = _historie;
    final bratstrasse =
        widget.eintraege[i].abteilung == Abteilung.bratstrasse;
    if (bratstrasse && h != null) {
      return 'Rechnet mit ${h.herkunft}: ${h.kennzahlen}. Hinterlegte '
          'Werte gelten hier nur ohne erfasste Produktionen.';
    }
    if (!_istLeer(i)) return null;
    if (h != null) return 'Leer: rechnet mit ${h.herkunft}: ${h.kennzahlen}';
    return 'Leer: noch keine Produktion mit Zeit erfasst — die Dauer ist '
        'dann ein Platzhalter.';
  }

  /// Geändert, aber weder vollständig noch ganz geleert — so lässt sich
  /// nichts speichern.
  bool _halbAusgefuellt(int i) {
    final text = _menge[i].text.trim();
    final min = _zeitMin[i];
    if (text == _mengeVorher[i] && min == _vorher[i]?.minuten) return false;
    final kg = double.tryParse(text.replaceAll(',', '.'));
    final vollstaendig = kg != null && kg > 0 && min != null && min > 0;
    return !vollstaendig && !_istLeer(i);
  }

  Future<void> _speichern() async {
    // Eine halb geleerte Zeile nicht stillschweigend verwerfen.
    for (var i = 0; i < widget.eintraege.length; i++) {
      if (!_halbAusgefuellt(i)) continue;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${widget.eintraege[i].abteilung.anzeigeName}: Menge und Zeit '
            'eintragen — oder beide Felder leeren, dann rechnet die '
            'Abteilung mit den erfassten Produktionen.',
          ),
        ),
      );
      return;
    }

    setState(() => _busy = true);
    final db = ref.read(databaseProvider);
    var geaendert = 0;
    try {
      for (var i = 0; i < widget.eintraege.length; i++) {
        final e = widget.eintraege[i];
        final vorher = _vorher[i];
        final text = _menge[i].text.trim();
        final kg = double.tryParse(text.replaceAll(',', '.'));
        final min = _zeitMin[i];
        if (text == _mengeVorher[i] && min == vorher?.minuten) continue;

        if (kg != null && kg > 0 && min != null && min > 0) {
          // Landet am ersten Schritt der Abteilung; ältere Werte an
          // anderen Schritten verschwinden — danach gibt es eine Stelle.
          await ProzesskettenService.setzeLeistungsdaten(
            db,
            productId: e.erster.productId,
            stepId: e.erster.id,
            mengeKg: kg,
            minuten: min,
          );
          geaendert++;
        } else if (_istLeer(i) && vorher != null) {
          // Beide Felder geleert: Die Abteilung rechnet wieder mit den
          // erfassten Produktionen.
          await ProzesskettenService.entferneLeistungsdaten(
            db,
            productId: e.erster.productId,
            stepId: e.erster.id,
          );
          geaendert++;
        }
        // Halb ausgefüllte Zeilen bleiben, wie sie waren.
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Speichern fehlgeschlagen: $e')),
        );
      }
      return;
    }

    if (geaendert > 0) {
      ref.read(autoBackupTriggerProvider).fireDebounced(
            reason: 'Leistungsdaten erfasst',
          );
    }
    if (mounted) Navigator.of(context).pop(geaendert > 0);
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
                'Welche Menge schafft die Abteilung bei diesem Artikel in '
                'welcher Zeit? Daraus rechnet die App die Dauer jeder '
                'Planmenge hoch. Bleibt eine Abteilung leer, rechnet sie mit '
                'dem Ø der letzten $kLetzteProduktionen erfassten '
                'Produktionen. Die Personen je Anlage pflegst du im '
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
                if (_grundlage(i) case final text?) ...[
                  const SizedBox(height: 4),
                  Text(
                    text,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
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


