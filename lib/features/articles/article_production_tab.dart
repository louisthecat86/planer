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
            child: LeerHinweis(
              'Noch keine Produktionsdaten.\n'
              'Oben rechts mit „Produktion erfassen" eintragen — oder eine '
              'Excel-Vorlage mit ausgefülltem Block „HISTORISCHE DATEN" '
              'importieren. Dann stehen hier alle vergangenen Produktionen '
              'samt Ausbeute und kg/h.',
              icon: Icons.insights,
            ),
          );
        }

        Future<void> bearbeiten(ProductionHistoryData r) async {
          final geaendert = await ProductionEntryDialog.show(
            context,
            productId,
            existing: r,
          );
          if (geaendert) {
            ref.invalidate(productionHistoryProvider(productId));
          }
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _KennzahlenCard(rows: rows),
            const SizedBox(height: 12),
            Bereich(
              titel: 'Vergangene Produktionen',
              untertitel: '${rows.length} · neueste zuerst',
              innenAbstand: EdgeInsets.zero,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Breit: eine Spalte je Kennzahl. Schmal: zweizeilig.
                  final breit = constraints.maxWidth >= 760;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (breit) const _HistorieKopf(),
                      for (var i = 0; i < rows.length; i++)
                        _HistorieZeile(
                          eintrag: rows[i],
                          breit: breit,
                          letzte: i == rows.length - 1,
                          onTap: () => bearbeiten(rows[i]),
                        ),
                    ],
                  );
                },
              ),
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
    final theme = Theme.of(context);
    final f = AppFarben.von(context);
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
    final hinweis = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    // Weiße Fläche wie jeder Bereich der App — vorher eine dunkle Karte mit
    // Farbverlauf, die als einzige aus dem Rahmen fiel.
    return Bereich(
      titel: 'Kennzahlen',
      icon: Icons.insights,
      innenAbstand: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 32,
            runSpacing: 14,
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
                // Der Verlust in Orange: die Zahl, auf die man schaut.
                _Kennzahl(
                  value: fmtProzent(1 - ausbeute.faktor),
                  label: 'Ø Garverlust',
                  valueColor: f.warnung,
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
          const SizedBox(height: 12),
          Text(
            'Ausbeute und Leistung: Ø der letzten $kLetzteProduktionen '
            'Produktionen — damit rechnet die Planung.',
            style: hinweis,
          ),
          if (hatMengen) ...[
            const SizedBox(height: 2),
            Text(
              'Gesamt: ${fmtKg(summeRoh)} kg Rohware → '
              '${fmtKg(summeFertig)} kg Fertigware',
              style: hinweis,
            ),
          ],
        ],
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
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? theme.colorScheme.onSurface,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Spaltenbreiten der Produktionsliste — für Kopf und Zeilen dieselben.
abstract final class _HistSpalten {
  static const double datum = 120;
  static const double menge = 96;
  static const double anteil = 84;
  static const double dauer = 104;
  static const double leistung = 80;
  static const double luecke = 16;
}

/// Ziffern gleich breit, damit Mengen untereinander stehen.
const List<FontFeature> _histZiffern = [FontFeature.tabularFigures()];

/// Spaltenköpfe der Produktionsliste — dieselben Breiten wie
/// [_HistorieZeile].
class _HistorieKopf extends StatelessWidget {
  const _HistorieKopf();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stil = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurfaceVariant,
    );
    Widget rechts(String text, double breite) => SizedBox(
          width: breite,
          child: Text(text, textAlign: TextAlign.right, style: stil),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: AppFarben.von(context).leiste,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outline),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _HistSpalten.datum,
            child: Text('Datum', style: stil),
          ),
          rechts('Rohware', _HistSpalten.menge),
          rechts('Fertigware', _HistSpalten.menge),
          rechts('Garverlust', _HistSpalten.anteil),
          rechts('Dauer', _HistSpalten.dauer),
          rechts('kg/h roh', _HistSpalten.leistung),
          const SizedBox(width: _HistSpalten.luecke),
          Expanded(child: Text('Quelle · Notiz', style: stil)),
        ],
      ),
    );
  }
}

/// Eine vergangene Produktion als Tabellenzeile. Antippen öffnet sie zum
/// Bearbeiten.
class _HistorieZeile extends StatelessWidget {
  const _HistorieZeile({
    required this.eintrag,
    required this.breit,
    required this.letzte,
    required this.onTap,
  });

  final ProductionHistoryData eintrag;

  /// Breite Tabelle mit allen Spalten — sonst zweizeilig.
  final bool breit;

  /// Letzte Zeile: ohne Linie darunter, die zieht der Bereich.
  final bool letzte;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final e = eintrag;

    // Garverlust: gespeicherten Anteil bevorzugen, sonst aus Roh/Fertig.
    var verlust = e.verlustAnteil;
    final roh = e.kgRohware;
    final fertig = e.kgFertigware;
    if (verlust == null && roh != null && fertig != null && roh > 0) {
      verlust = 1 - (fertig / roh);
    }

    final start = e.startzeit;
    final ende = e.endzeit;
    final zeitText = (start != null && ende != null)
        ? '$start – $ende'
        : (start ?? '');
    final notiz = e.notizen?.trim() ?? '';
    final ausApp = e.quelle == 'app';

    final stil = theme.textTheme.bodyMedium;
    final zahlen = stil?.copyWith(fontFeatures: _histZiffern);

    final datum = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          fmtDatum(e.datum),
          style: zahlen?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (zeitText.isNotEmpty)
          Text(
            zeitText,
            style: theme.textTheme.bodySmall?.copyWith(color: grau),
          ),
      ],
    );
    final quelle = Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (ausApp)
          const StatusMarke('in App erfasst', art: StatusArt.ok),
        if (notiz.isNotEmpty)
          Text(
            notiz,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontStyle: FontStyle.italic,
              color: grau,
            ),
          ),
      ],
    );

    // Fehlt eine Menge, steht nur „—" da, nicht „— kg".
    String kg(double? wert) => wert == null ? '—' : '${fmtKg(wert)} kg';

    Widget zelle(String text, double breite) => SizedBox(
          width: breite,
          child: Text(
            text,
            maxLines: 1,
            textAlign: TextAlign.right,
            style: zahlen,
          ),
        );

    final Widget inhalt;
    if (breit) {
      inhalt = Row(
        children: [
          SizedBox(width: _HistSpalten.datum, child: datum),
          zelle(kg(roh), _HistSpalten.menge),
          zelle(kg(fertig), _HistSpalten.menge),
          zelle(
            verlust == null ? '—' : fmtProzent(verlust),
            _HistSpalten.anteil,
          ),
          zelle(fmtDauer(e.produktionszeitMinuten), _HistSpalten.dauer),
          zelle(fmtKg(e.kgProStundeRoh), _HistSpalten.leistung),
          const SizedBox(width: _HistSpalten.luecke),
          Expanded(child: quelle),
        ],
      );
    } else {
      // Schmal: Datum und Quelle oben, die Zahlen als eine Zeile darunter.
      final teile = <String>[
        '${kg(roh)} → ${kg(fertig)}',
        if (verlust != null) '${fmtProzent(verlust)} Verlust',
        if (e.produktionszeitMinuten != null)
          fmtDauer(e.produktionszeitMinuten),
        if (e.kgProStundeRoh != null) '${fmtKg(e.kgProStundeRoh)} kg/h roh',
      ];
      inhalt = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              datum,
              const SizedBox(width: 12),
              Expanded(child: quelle),
            ],
          ),
          const SizedBox(height: 4),
          Text(teile.join(' · '), style: zahlen),
        ],
      );
    }

    // Material statt Farbe am Container: Die Hover- und Tipp-Welle malt auf
    // das nächste Material.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            border: letzte
                ? null
                : Border(
                    bottom: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
          ),
          child: inhalt,
        ),
      ),
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

  /// Je Station: ihre Nummer in der Prozesskette, die Abteilung, der erste
  /// Schritt (dort landen die Referenzwerte) und alle Schritte der Station
  /// (für die geltenden Werte und die Personensumme in der Anzeige).
  final List<
      ({
        int nummer,
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
    final grau = theme.colorScheme.onSurfaceVariant;
    final linie = theme.colorScheme.outlineVariant;
    final anzahl = widget.eintraege.length;
    return AlertDialog(
      title: Text(
        anzahl == 1
            ? 'Leistungsdaten · ${widget.eintraege.first.abteilung.anzeigeName}'
            : 'Leistungsdaten je Abteilung',
      ),
      content: SizedBox(
        // Breit genug für Menge + Std./Min. + die Kennzahlen rechts.
        // Bei 560 lief der Minutenwert in seine eigene Beschriftung.
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const HinweisBox(
                'Welche Menge schafft die Abteilung bei diesem Artikel in '
                'welcher Zeit? Daraus rechnet die App die Dauer jeder '
                'Planmenge hoch. Bleibt eine Abteilung leer, rechnet sie mit '
                'dem Ø der letzten $kLetzteProduktionen erfassten '
                'Produktionen. Die Personen je Anlage pflegst du im '
                'jeweiligen Schritt.',
              ),
              const SizedBox(height: 4),
              for (var i = 0; i < anzahl; i++)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: i == anzahl - 1
                        ? null
                        : Border(bottom: BorderSide(color: linie)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          AbteilungsMarke(
                            abteilung: widget.eintraege[i].abteilung,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            // Mit der Nummer der Station — so passt die
                            // Zeile zur Kette, auch wenn eine Abteilung
                            // zweimal darin vorkommt.
                            child: Text(
                              '${widget.eintraege[i].nummer} · '
                              '${widget.eintraege[i].abteilung.anzeigeName}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Text(
                            '${_personenSumme(i)} Pers.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: grau,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _kgProStunde(i),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.primary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _menge[i],
                              decoration: const InputDecoration(
                                labelText: 'Menge',
                                suffixText: 'kg',
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Getrennte Stunden-/Minutenfelder: „0:08" war als
                          // Freitext fehleranfällig und ließ offen, ob 8
                          // Minuten oder 8 Stunden gemeint sind.
                          //
                          // Nicht kompakt: Die schmalen Felder (66pt) sind
                          // zu eng, sobald Wert und Einheit zusammen darin
                          // stehen.
                          ZeitEingabe(
                            kompakt: false,
                            minuten: _zeitMin[i],
                            onChanged: (m) => setState(() => _zeitMin[i] = m),
                          ),
                        ],
                      ),
                      if (_grundlage(i) case final text?) ...[
                        const SizedBox(height: 6),
                        Text(
                          text,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: grau,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
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
