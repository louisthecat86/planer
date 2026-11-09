import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_stil.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/fehler_text.dart';
import '../../../core/utils/format.dart';
import '../../statistik/statistik_diagramme.dart';
import '../bericht/bericht_drucken.dart' show entwicklungsberichtDrucken;
import '../bericht/bericht_pdf.dart' show EntwicklungsberichtDaten;
import '../daten/entwicklung_repository.dart';
import '../projekte/projekt_repository.dart';
import '../projekte/projekte_ansicht.dart' show oeffneProjekt;
import '../werkzeuge/entwicklung_statistik.dart';
import 'entwicklung_auswertung.dart';
import 'stand_heute.dart';

// Der Reiter „Statistik" der Produktentwicklung: wie die Entwicklung in
// einem Zeitraum lief — etwa für die Managementbewertung am Jahresende.
// Oben Zeitraum (Jahr, Quartal, Monat oder frei gewählt) und Kunde,
// daneben der Bericht als PDF; darunter die Kennzahlen mit dem Vorjahr,
// der Verlauf, was aus den Mustern wurde, die Kunden, die Gründe, die
// Muster im Einzelnen und der Stand heute. Gerechnet wird in
// entwicklung_auswertung.dart — dieselben Zahlen wie im Bericht.

/// Im Kundenfilter: alle Kunden.
const String _alleKunden = '\u0000alle';

/// Im Kundenfilter: Muster ohne Kunden.
const String _ohneKunden = '\u0000ohne';

/// Die Farbe eines Ergebnisses — in Säulen, Kreis und Balken.
Color _ergebnisFarbe(BuildContext context, MusterErgebnis e) {
  final dunkel = Theme.of(context).brightness == Brightness.dark;
  return switch (e) {
    MusterErgebnis.gelistet => AppFarben.von(context).ok,
    // Wie „nicht weiter verfolgt" im Projektbericht.
    MusterErgebnis.nichtWeiter =>
      dunkel ? const Color(0xFFA1887F) : const Color(0xFF8D6E63),
    MusterErgebnis.offen => reihenFarbe(context, 0),
    MusterErgebnis.archiviert => hellgrauFarbe(context),
  };
}

/// Die Marke eines Ergebnisses.
StatusArt _ergebnisArt(MusterErgebnis e) => switch (e) {
      MusterErgebnis.gelistet => StatusArt.ok,
      MusterErgebnis.offen => StatusArt.info,
      MusterErgebnis.nichtWeiter ||
      MusterErgebnis.archiviert =>
        StatusArt.neutral,
    };

DateTime _tag(DateTime d) => DateTime(d.year, d.month, d.day);

/// Der Reiter „Statistik".
class StatistikAnsicht extends ConsumerStatefulWidget {
  const StatistikAnsicht({super.key, this.heute});

  /// Für Tests: der Tag, an dem gerechnet wird — sonst heute.
  final DateTime? heute;

  @override
  ConsumerState<StatistikAnsicht> createState() => _StatistikAnsichtState();
}

class _StatistikAnsichtState extends ConsumerState<StatistikAnsicht> {
  late Zeitraum _zeitraum = Zeitraum.jahr(_heute.year);

  /// Der Kundenfilter — null: alle, [kOhneKunde]: ohne Kunden.
  String? _kunde;

  DateTime get _heute => _tag(widget.heute ?? DateTime.now());

  /// Der letzte Tag des Zeitraums — höchstens heute.
  DateTime get _ende => _zeitraum.bis.isAfter(_heute) ? _heute : _zeitraum.bis;

  void _art(ZeitraumArt art) {
    if (art == ZeitraumArt.frei) {
      // Frei beginnt mit dem bisherigen Zeitraum.
      setState(() => _zeitraum = Zeitraum.frei(_zeitraum.von, _ende));
      _freiWaehlen();
      return;
    }
    setState(() => _zeitraum = Zeitraum.um(art, _ende));
  }

  Future<void> _freiWaehlen() async {
    final neu = await showDialog<Zeitraum>(
      context: context,
      builder: (_) => _ZeitraumDialog(
        von: _zeitraum.von,
        bis: _ende,
        heute: _heute,
      ),
    );
    if (neu == null || !mounted) return;
    setState(() => _zeitraum = neu);
  }

  Future<void> _bericht(
    EntwicklungsAuswertung a, {
    required List<EntwicklungsProjekt> projekte,
    required List<Rezeptur> rezepturen,
    required List<RezepturVersion> versionen,
    required List<ProjektEintrag> eintraege,
  }) =>
      entwicklungsberichtDrucken(
        context,
        ref,
        EntwicklungsberichtDaten(
          auswertung: a,
          stand: entwicklungsStatistik(
            projekte: [
              for (final p in projekte)
                if (kundePasst(p.kunde, a.kunde)) p,
            ],
            rezepturen: rezepturen,
            versionen: versionen,
            zutaten: ref.read(zutatenProvider).valueOrNull ?? const [],
            eintraege: eintraege,
            jetzt: widget.heute ?? DateTime.now(),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final projekte = ref.watch(projekteProvider);
    final gesamt = ref.watch(gesamtprojekteProvider);
    final eintraege = ref.watch(alleEintraegeProvider);
    final rezepturen = ref.watch(rezepturenProvider);
    final versionen = ref.watch(alleVersionenProvider);
    final alle = <AsyncValue<Object?>>[
      projekte,
      gesamt,
      eintraege,
      rezepturen,
      versionen,
    ];
    final fehler = alle.where((a) => a.hasError).firstOrNull;
    if (fehler != null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          HinweisBox(
            fehlerText(fehler.error),
            art: StatusArt.fehler,
            titel: 'Die Statistik ließ sich nicht laden',
            auswaehlbar: true,
          ),
        ],
      );
    }
    if (alle.any((a) => !a.hasValue)) {
      return const Center(child: CircularProgressIndicator());
    }
    final laeufe = musterLaeufe(
      projekte: projekte.requireValue,
      gesamtprojekte: gesamt.requireValue,
      eintraege: eintraege.requireValue,
      rezepturen: rezepturen.requireValue,
      versionen: versionen.requireValue,
    );
    final a = entwicklungAuswerten(
      laeufe: laeufe,
      zeitraum: _zeitraum,
      heute: _heute,
      gesamtprojekte: gesamt.requireValue,
      rezepturen: rezepturen.requireValue,
      versionen: versionen.requireValue,
      kunde: _kunde,
    );
    final kunden = kundenListe(laeufe, gesamt.requireValue);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Filterleiste(
          zeitraum: _zeitraum,
          heute: _heute,
          kunde: _kunde,
          kunden: kunden,
          onArt: _art,
          onZeitraum: (z) => setState(() => _zeitraum = z),
          onFrei: _freiWaehlen,
          onKunde: (k) => setState(() => _kunde = k),
          onBericht: () => _bericht(
            a,
            projekte: projekte.requireValue,
            rezepturen: rezepturen.requireValue,
            versionen: versionen.requireValue,
            eintraege: eintraege.requireValue,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _KennzahlenBereich(auswertung: a),
              const SizedBox(height: 16),
              if (a.verlauf.length > 1) ...[
                _VerlaufBereich(auswertung: a),
                const SizedBox(height: 16),
              ],
              _ErgebnisBereich(auswertung: a),
              const SizedBox(height: 16),
              if (a.kunde == null && a.kunden.isNotEmpty) ...[
                _KundenBereich(
                  auswertung: a,
                  // So geschrieben wie in der Auswahl.
                  onKunde: (k) => setState(
                    () => _kunde = k == null
                        ? kOhneKunde
                        : kunden.firstWhere(
                            (x) => kundePasst(x, k),
                            orElse: () => k,
                          ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (a.gruende.isNotEmpty) ...[
                _GruendeBereich(auswertung: a),
                const SizedBox(height: 16),
              ],
              _MusterBereich(auswertung: a),
              const SizedBox(height: 16),
              EntwicklungsStatistikAnsicht(jetzt: widget.heute, kunde: _kunde),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Filter ────────────────────────────────────────────────────────────

class _Filterleiste extends StatelessWidget {
  const _Filterleiste({
    required this.zeitraum,
    required this.heute,
    required this.kunde,
    required this.kunden,
    required this.onArt,
    required this.onZeitraum,
    required this.onFrei,
    required this.onKunde,
    required this.onBericht,
  });

  final Zeitraum zeitraum;
  final DateTime heute;
  final String? kunde;
  final List<String> kunden;
  final ValueChanged<ZeitraumArt> onArt;
  final ValueChanged<Zeitraum> onZeitraum;
  final VoidCallback onFrei;
  final ValueChanged<String?> onKunde;
  final VoidCallback onBericht;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final frei = zeitraum.art == ZeitraumArt.frei;
    final k = kunde;
    final wahl = k == null
        ? _alleKunden
        : k == kOhneKunde
            ? _ohneKunden
            : k;
    // Ein gewählter Kunde bleibt wählbar, auch wenn es ihn so nicht mehr
    // gibt.
    final namen = [
      ...kunden,
      if (k != null && k != kOhneKunde && !kunden.contains(k)) k,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<ZeitraumArt>(
            key: const ValueKey('statistik-art'),
            segments: [
              for (final art in ZeitraumArt.values)
                ButtonSegment(value: art, label: Text(art.label)),
            ],
            selected: {zeitraum.art},
            showSelectedIcon: false,
            onSelectionChanged: (w) => onArt(w.first),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: const ValueKey('statistik-davor'),
                tooltip: 'Davor',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => onZeitraum(zeitraum.davor),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 150),
                child: frei
                    ? TextButton.icon(
                        key: const ValueKey('statistik-frei'),
                        onPressed: onFrei,
                        icon: const Icon(Icons.date_range, size: 18),
                        label: Text(zeitraum.name),
                      )
                    : Text(
                        zeitraum.name,
                        key: const ValueKey('statistik-zeitraum'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleSmall,
                      ),
              ),
              IconButton(
                key: const ValueKey('statistik-danach'),
                tooltip: 'Danach',
                icon: const Icon(Icons.chevron_right),
                // In die Zukunft nicht.
                onPressed: zeitraum.danach.von.isAfter(heute)
                    ? null
                    : () => onZeitraum(zeitraum.danach),
              ),
            ],
          ),
          SizedBox(
            width: 260,
            child: DropdownButtonFormField<String>(
              // Neu aufbauen, wenn der Kunde von außen wechselt (Zeile
              // unter „Nach Kunde" angetippt).
              key: ValueKey('statistik-kunde-$wahl'),
              initialValue: wahl,
              isExpanded: true,
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'Kunde',
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(
                  value: _alleKunden,
                  child: Text('Alle Kunden'),
                ),
                const DropdownMenuItem(
                  value: _ohneKunden,
                  child: Text('Ohne Kunden'),
                ),
                for (final n in namen)
                  DropdownMenuItem(
                    value: n,
                    child: Text(
                      n,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (w) => onKunde(
                w == null || w == _alleKunden
                    ? null
                    : w == _ohneKunden
                        ? kOhneKunde
                        : w,
              ),
            ),
          ),
          FilledButton.icon(
            key: const ValueKey('statistik-bericht'),
            onPressed: onBericht,
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: const Text('Bericht …'),
          ),
        ],
      ),
    );
  }
}

/// Einen Zeitraum frei wählen: von, bis — beide höchstens heute.
class _ZeitraumDialog extends StatefulWidget {
  const _ZeitraumDialog({
    required this.von,
    required this.bis,
    required this.heute,
  });

  final DateTime von;
  final DateTime bis;
  final DateTime heute;

  @override
  State<_ZeitraumDialog> createState() => _ZeitraumDialogState();
}

class _ZeitraumDialogState extends State<_ZeitraumDialog> {
  late DateTime _von = widget.von;
  late DateTime _bis = widget.bis;

  Future<void> _waehle({required bool anfang}) async {
    final erster = DateTime(2000);
    final aktuell = anfang ? _von : _bis;
    final d = await showDatePicker(
      context: context,
      initialDate: aktuell.isBefore(erster)
          ? erster
          : aktuell.isAfter(widget.heute)
              ? widget.heute
              : aktuell,
      firstDate: erster,
      lastDate: widget.heute,
    );
    if (d == null || !mounted) return;
    setState(() {
      if (anfang) {
        _von = d;
      } else {
        _bis = d;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget zeile(String label, DateTime d, {required bool anfang}) => Row(
          children: [
            SizedBox(width: 40, child: Text(label)),
            OutlinedButton.icon(
              onPressed: () => _waehle(anfang: anfang),
              icon: const Icon(Icons.event, size: 18),
              label: Text(Format.datum(d)),
            ),
          ],
        );
    return AlertDialog(
      title: const Text('Zeitraum wählen'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          zeile('Von', _von, anfang: true),
          const SizedBox(height: 10),
          zeile('Bis', _bis, anfang: false),
          if (_bis.isBefore(_von)) ...[
            const SizedBox(height: 10),
            const Text('Liegt „Bis" vor „Von", gilt es umgekehrt.'),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, Zeitraum.frei(_von, _bis)),
          child: const Text('Übernehmen'),
        ),
      ],
    );
  }
}

// ── Bausteine ─────────────────────────────────────────────────────────

/// Kleine Überschrift innerhalb eines Bereichs.
class _Zwischentitel extends StatelessWidget {
  const _Zwischentitel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Grauer Erklärtext.
class _Fussnote extends StatelessWidget {
  const _Fussnote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.35,
      ),
    );
  }
}

/// Kleine Quadrate in Farbe, daneben was sie bedeuten.
class _Legende extends StatelessWidget {
  const _Legende(this.eintraege);

  final List<(Color, String)> eintraege;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          for (final (farbe, text) in eintraege)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: farbe,
                    borderRadius: AppMasse.eckenKlein,
                  ),
                ),
                const SizedBox(width: 6),
                Text(text, style: theme.textTheme.bodySmall),
              ],
            ),
        ],
      ),
    );
  }
}

/// Zwei Spalten nebeneinander — auf schmaleren Fenstern untereinander.
class _ZweiSpalten extends StatelessWidget {
  const _ZweiSpalten({required this.links, required this.rechts});

  final Widget links;
  final Widget rechts;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= 1000) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: links),
              const SizedBox(width: 32),
              Expanded(child: rechts),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [links, const SizedBox(height: 18), rechts],
        );
      },
    );
  }
}

/// Das obere Ende der Achse für ganze Zahlen bis [saeulen] — mindestens 4,
/// so, dass die Teilung ganzzahlig bleibt.
double _ganzeAchse(Iterable<Saeule> saeulen) {
  var oben = math.max(
    4.0,
    saeulen.fold<double>(0, (m, s) => math.max(m, s.wert ?? 0)).ceilToDouble(),
  );
  while (achsenSchritt(oben) % 1 != 0) {
    oben += 1;
  }
  return oben;
}

/// „Testwurst A, Testwurst B und 3 weitere".
String _namen(List<MusterLauf> muster, {int hoechstens = 4}) {
  final namen = [for (final l in muster.take(hoechstens)) l.name];
  final mehr = muster.length - namen.length;
  return mehr > 0 ? '${namen.join(', ')} und $mehr weitere' : namen.join(', ');
}

// ── Kennzahlen ────────────────────────────────────────────────────────

/// Eine Kennzahl mit Zusatz und dem Vergleich mit dem Vorjahr darunter.
class _Zahl extends StatelessWidget {
  const _Zahl({
    required this.wert,
    required this.label,
    this.zusatz,
    this.vergleich,
  });

  final String wert;
  final String label;
  final String? zusatz;
  final String? vergleich;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final z = zusatz;
    final v = vergleich;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 130),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Kennzahl(wert: wert, label: label, gross: true),
          if (z != null)
            Text(z, style: theme.textTheme.bodySmall?.copyWith(color: grau)),
          if (v != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                v,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: grau,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _KennzahlenBereich extends StatelessWidget {
  const _KennzahlenBereich({required this.auswertung});

  final EntwicklungsAuswertung auswertung;

  @override
  Widget build(BuildContext context) {
    final a = auswertung;
    final z = a.zahlen;
    final v = a.vorjahr;
    final vj = a.zeitraum.vorjahr.kurz;
    String vergleich(num jetzt, num vorher) =>
        '$vj: ${Format.zahl(vorher)} (${veraenderungText(jetzt, vorher)})';
    final vorherTage =
        v.tageBisListung == null ? '—' : 'Ø ${tageText(v.tageBisListung)}';
    return Bereich(
      titel: 'Kennzahlen',
      icon: Icons.insights_outlined,
      untertitel: '${a.zeitraum.name} · verglichen mit '
          '${a.zeitraum.vorjahr.name}',
      innenAbstand: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 36,
            runSpacing: 18,
            children: [
              _Zahl(
                wert: '${z.neueMuster}',
                label: 'Neue Muster',
                zusatz: 'davon ${z.neueMusterImGesamtprojekt} in '
                    'Gesamtprojekten',
                vergleich: vergleich(z.neueMuster, v.neueMuster),
              ),
              _Zahl(
                wert: '${z.neueAnfragen}',
                label: 'Neue Anfragen',
                zusatz: 'Gesamtprojekte',
                vergleich: vergleich(z.neueAnfragen, v.neueAnfragen),
              ),
              _Zahl(
                wert: '${z.gelistet}',
                label: 'Gelistet',
                zusatz: 'davon ${z.freigegeben} als Artikel freigegeben',
                vergleich: vergleich(z.gelistet, v.gelistet),
              ),
              _Zahl(
                wert: '${z.nichtWeiter}',
                label: 'Nicht weiter verfolgt',
                vergleich: vergleich(z.nichtWeiter, v.nichtWeiter),
              ),
              _Zahl(
                wert: quoteText(z.listungsquote),
                label: 'Listungsquote',
                zusatz: 'unter den entschiedenen '
                    '${quoteText(z.trefferquote)}',
                vergleich: '$vj: ${quoteText(v.listungsquote)}',
              ),
              _Zahl(
                wert: z.tageBisListung == null
                    ? '—'
                    : 'Ø ${tageText(z.tageBisListung)}',
                label: 'Bis zur Listung',
                zusatz: z.tageBisListungMedian == null
                    ? null
                    : 'Median ${tageText(z.tageBisListungMedian)}',
                vergleich: '$vj: $vorherTage',
              ),
              _Zahl(
                wert: '${z.inArbeitAmEnde}',
                label: a.laeuftNoch
                    ? 'In Arbeit heute'
                    : 'In Arbeit am ${Format.datum(a.stichtag)}',
                vergleich: vergleich(z.inArbeitAmEnde, v.inArbeitAmEnde),
              ),
              _Zahl(
                wert: '${z.neueProzesse}',
                label: 'Mit neuem Prozess',
                zusatz: '${z.neueZutaten} mit neuen Zutaten',
              ),
              _Zahl(
                wert: '${z.staendeAngelegt}',
                label: 'Rezepturstände angelegt',
                zusatz: '${z.staendeAbgeschlossen} abgeschlossen',
                vergleich: vergleich(z.staendeAngelegt, v.staendeAngelegt),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _Fussnote(
            'Muster: jedes Projekt, auch in einem Gesamtprojekt. Gelistet: in '
            'Produktion gegangen (Freigabe als Artikel oder von Hand), '
            'gezählt am Tag des Wechsels. Nicht weiter verfolgt: im Zeitraum '
            'dazu gekommen und an seinem Ende noch so. Listungsquote: Anteil '
            'der im Zeitraum angelegten Muster, die heute gelistet sind — '
            'unter den entschiedenen: unter denen, die gelistet oder nicht '
            'weiter verfolgt sind.',
          ),
        ],
      ),
    );
  }
}

// ── Verlauf ───────────────────────────────────────────────────────────

class _VerlaufBereich extends StatelessWidget {
  const _VerlaufBereich({required this.auswertung});

  final EntwicklungsAuswertung auswertung;

  @override
  Widget build(BuildContext context) {
    final a = auswertung;
    final primaer = Theme.of(context).colorScheme.primary;
    Color farbe(MusterErgebnis e) => _ergebnisFarbe(context, e);

    final neu = [
      for (final x in a.verlauf)
        Saeule(
          label: x.abschnitt.label,
          wert: x.neuGesamt.toDouble(),
          farbe: primaer,
          hinweis: x.neuGesamt == 0
              ? '${x.abschnitt.name}: keine neuen Muster'
              : '${x.abschnitt.name}: ${x.neuGesamt} '
                  '${x.neuGesamt == 1 ? 'neues Muster' : 'neue Muster'}\n'
                  '${[
                  for (final e in MusterErgebnis.values)
                    if ((x.neu[e] ?? 0) > 0) '${x.neu[e]} ${e.label}',
                ].join(', ')}',
          segmente: [
            for (final e in MusterErgebnis.values)
              if ((x.neu[e] ?? 0) > 0) ((x.neu[e] ?? 0).toDouble(), farbe(e)),
          ],
        ),
    ];
    final entschieden = [
      for (final x in a.verlauf)
        Saeule(
          label: x.abschnitt.label,
          wert: (x.gelistet.length + x.nichtWeiter.length).toDouble(),
          farbe: farbe(MusterErgebnis.gelistet),
          hinweis: [
            x.abschnitt.name,
            if (x.gelistet.isNotEmpty)
              '${x.gelistet.length} gelistet: ${_namen(x.gelistet)}',
            if (x.nichtWeiter.isNotEmpty)
              '${x.nichtWeiter.length} nicht weiter verfolgt: '
                  '${_namen(x.nichtWeiter)}',
            if (x.gelistet.isEmpty && x.nichtWeiter.isEmpty)
              'nichts entschieden',
          ].join('\n'),
          segmente: [
            if (x.gelistet.isNotEmpty)
              (x.gelistet.length.toDouble(), farbe(MusterErgebnis.gelistet)),
            if (x.nichtWeiter.isNotEmpty)
              (
                x.nichtWeiter.length.toDouble(),
                farbe(MusterErgebnis.nichtWeiter),
              ),
          ],
        ),
    ];
    String achse(double w) => Format.zahl(w);
    return Bereich(
      titel: 'Verlauf',
      icon: Icons.bar_chart,
      untertitel: '${a.zeitraum.name} je ${a.zeitraum.raster.label}',
      innenAbstand: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ZweiSpalten(
            links: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Zwischentitel('NEUE MUSTER — UND WAS AUS IHNEN WURDE'),
                StatistikSaeulen(
                  key: const ValueKey('statistik-saeulen-neu'),
                  saeulen: neu,
                  achsenText: achse,
                  festesMax: _ganzeAchse(neu),
                ),
                _Legende([
                  for (final e in MusterErgebnis.values) (farbe(e), e.label),
                ]),
              ],
            ),
            rechts: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Zwischentitel('GELISTET UND NICHT WEITER VERFOLGT'),
                StatistikSaeulen(
                  key: const ValueKey('statistik-saeulen-entschieden'),
                  saeulen: entschieden,
                  achsenText: achse,
                  festesMax: _ganzeAchse(entschieden),
                ),
                _Legende([
                  (farbe(MusterErgebnis.gelistet), 'Gelistet'),
                  (farbe(MusterErgebnis.nichtWeiter), 'Nicht weiter verfolgt'),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const _Fussnote(
            'Links die im Abschnitt angelegten Muster, gefärbt nach dem, was '
            'heute aus ihnen geworden ist. Rechts, was im Abschnitt '
            'entschieden wurde — gleich, wann das Muster angelegt wurde. '
            'Darüberfahren zeigt die Muster.',
          ),
        ],
      ),
    );
  }
}

// ── Was aus den Mustern wurde ─────────────────────────────────────────

class _ErgebnisBereich extends StatelessWidget {
  const _ErgebnisBereich({required this.auswertung});

  final EntwicklungsAuswertung auswertung;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = auswertung;
    final z = a.zahlen;
    final n = z.neueMuster;
    int anzahl(MusterErgebnis e) => z.kohorte[e] ?? 0;
    return Bereich(
      titel: 'Was aus den Mustern wurde',
      icon: Icons.donut_large_outlined,
      untertitel: 'die ${a.zeitraum.name} angelegten · Stand heute',
      innenAbstand: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: n == 0
          ? const LeerHinweis(
              'Im Zeitraum wurde kein Muster angelegt.',
              icon: Icons.inventory_2_outlined,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StatistikKreis(
                  stuecke: [
                    for (final e in MusterErgebnis.values)
                      if (anzahl(e) > 0)
                        KreisStueck(
                          name: e.label,
                          wert: anzahl(e).toDouble(),
                          farbe: _ergebnisFarbe(context, e),
                          wertText: '${anzahl(e)}',
                        ),
                  ],
                  summeText: '$n',
                  summeLabel: n == 1 ? 'neues Muster' : 'neue Muster',
                ),
                const SizedBox(height: 12),
                Text(
                  'Listungsquote ${quoteText(z.listungsquote)}: '
                  '${anzahl(MusterErgebnis.gelistet)} von $n '
                  '${n == 1 ? 'neuem Muster' : 'neuen Mustern'} '
                  '${anzahl(MusterErgebnis.gelistet) == 1 ? 'ist' : 'sind'} '
                  'gelistet. Unter den entschiedenen — gelistet oder nicht '
                  'weiter verfolgt — ${quoteText(z.trefferquote)}.',
                  style: theme.textTheme.bodyMedium,
                ),
                if (anzahl(MusterErgebnis.offen) > 0) ...[
                  const SizedBox(height: 4),
                  _Fussnote(
                    '${anzahl(MusterErgebnis.offen)} noch in Arbeit — '
                    '${anzahl(MusterErgebnis.offen) == 1 ? 'es kann' : 'sie '
                        'können'} noch gelistet werden.',
                  ),
                ],
                if (a.ohneDatumGelistet > 0) ...[
                  const SizedBox(height: 4),
                  _Fussnote(
                    '${a.ohneDatumGelistet} gelistet ohne Tag der Listung '
                    '(etwa aus der Suite übernommen) — sie zählen hier, '
                    'nicht bei den Listungen.',
                  ),
                ],
              ],
            ),
    );
  }
}

// ── Nach Kunde ────────────────────────────────────────────────────────

class _KundenBereich extends StatelessWidget {
  const _KundenBereich({required this.auswertung, required this.onKunde});

  final EntwicklungsAuswertung auswertung;

  /// Filtert nach dem Kunden — null: ohne Kunden.
  final ValueChanged<String?> onKunde;

  static const int _hoechstens = 15;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final kunden = auswertung.kunden;
    final groesster = kunden.fold<int>(0, (m, k) => math.max(m, k.muster));
    final kopfStil = theme.textTheme.labelMedium?.copyWith(
      color: grau,
      fontWeight: FontWeight.w600,
    );
    Widget zahl(String text, {TextStyle? stil}) => SizedBox(
          width: 72,
          child: Text(text, textAlign: TextAlign.right, style: stil),
        );
    return Bereich(
      titel: 'Nach Kunde',
      icon: Icons.storefront_outlined,
      untertitel: 'neue Muster · Antippen filtert',
      innenAbstand: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                Expanded(child: Text('Kunde', style: kopfStil)),
                zahl('Muster', stil: kopfStil),
                zahl('Gelistet', stil: kopfStil),
                zahl('Nicht weiter', stil: kopfStil),
                zahl('In Arbeit', stil: kopfStil),
                zahl('Quote', stil: kopfStil),
                const SizedBox(width: 16),
                const SizedBox(width: 200),
              ],
            ),
          ),
          for (final k in kunden.take(_hoechstens))
            InkWell(
              onTap: () => onKunde(k.kunde),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        k.kunde ?? 'Ohne Kunden',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: k.kunde == null
                            ? theme.textTheme.bodyMedium?.copyWith(color: grau)
                            : theme.textTheme.bodyMedium,
                      ),
                    ),
                    zahl(
                      '${k.muster}',
                      stil: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    zahl('${k.anzahl(MusterErgebnis.gelistet)}'),
                    zahl('${k.anzahl(MusterErgebnis.nichtWeiter)}'),
                    zahl('${k.anzahl(MusterErgebnis.offen)}'),
                    zahl(
                      quoteText(k.quote),
                      stil: theme.textTheme.bodyMedium?.copyWith(color: grau),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 200,
                      child: SegmentBalken(
                        max: groesster.toDouble(),
                        segmente: [
                          for (final e in MusterErgebnis.values)
                            (
                              k.anzahl(e).toDouble(),
                              _ergebnisFarbe(context, e),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (kunden.length > _hoechstens)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: _Fussnote(
                'und ${kunden.length - _hoechstens} weitere Kunden — der '
                'Bericht nennt alle.',
              ),
            ),
        ],
      ),
    );
  }
}

// ── Gründe ────────────────────────────────────────────────────────────

class _GruendeBereich extends StatelessWidget {
  const _GruendeBereich({required this.auswertung});

  final EntwicklungsAuswertung auswertung;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final a = auswertung;
    final groesster = a.gruende.fold<int>(0, (m, g) => math.max(m, g.anzahl));
    return Bereich(
      titel: 'Warum nicht weiter verfolgt',
      icon: Icons.do_not_disturb_on_outlined,
      untertitel: '${a.nichtWeiter.length} Muster im Zeitraum',
      innenAbstand: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final g in a.gruende)
            Tooltip(
              message: _namen(g.muster, hoechstens: 12),
              waitDuration: const Duration(milliseconds: 500),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        g.grund ?? 'Ohne Angabe',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: g.grund == null
                            ? theme.textTheme.bodyMedium?.copyWith(color: grau)
                            : theme.textTheme.bodyMedium,
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text(
                        '${g.anzahl}',
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 200,
                      child: SegmentBalken(
                        max: groesster.toDouble(),
                        segmente: [
                          (
                            g.anzahl.toDouble(),
                            _ergebnisFarbe(context, MusterErgebnis.nichtWeiter),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Muster im Einzelnen ───────────────────────────────────────────────

/// Welche Muster die Liste zeigt.
enum _Liste { angelegt, gelistet, nichtWeiter }

class _MusterBereich extends StatefulWidget {
  const _MusterBereich({required this.auswertung});

  final EntwicklungsAuswertung auswertung;

  @override
  State<_MusterBereich> createState() => _MusterBereichState();
}

class _MusterBereichState extends State<_MusterBereich> {
  _Liste _liste = _Liste.angelegt;
  bool _alle = false;

  static const int _zuerst = 25;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final a = widget.auswertung;
    final muster = switch (_liste) {
      _Liste.angelegt => a.neu,
      _Liste.gelistet => a.gelistet,
      _Liste.nichtWeiter => a.nichtWeiter,
    };
    final sichtbar = _alle ? muster : muster.take(_zuerst).toList();
    final kopfStil = theme.textTheme.labelMedium?.copyWith(
      color: grau,
      fontWeight: FontWeight.w600,
    );
    return Bereich(
      titel: 'Muster im Einzelnen',
      icon: Icons.list_alt_outlined,
      untertitel: a.zeitraum.name,
      innenAbstand: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<_Liste>(
              key: const ValueKey('statistik-liste'),
              segments: [
                ButtonSegment(
                  value: _Liste.angelegt,
                  label: Text('Angelegt (${a.neu.length})'),
                ),
                ButtonSegment(
                  value: _Liste.gelistet,
                  label: Text('Gelistet (${a.gelistet.length})'),
                ),
                ButtonSegment(
                  value: _Liste.nichtWeiter,
                  label:
                      Text('Nicht weiter verfolgt (${a.nichtWeiter.length})'),
                ),
              ],
              selected: {_liste},
              showSelectedIcon: false,
              onSelectionChanged: (w) => setState(() {
                _liste = w.first;
                _alle = false;
              }),
            ),
          ),
          const SizedBox(height: 8),
          if (muster.isEmpty)
            LeerHinweis(
              switch (_liste) {
                _Liste.angelegt => 'Im Zeitraum wurde kein Muster angelegt.',
                _Liste.gelistet => 'Im Zeitraum wurde kein Muster gelistet.',
                _Liste.nichtWeiter =>
                  'Im Zeitraum wurde kein Muster nicht weiter verfolgt.',
              },
              icon: Icons.inventory_2_outlined,
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                children: [
                  Expanded(flex: 3, child: Text('Muster', style: kopfStil)),
                  Expanded(flex: 2, child: Text('Kunde', style: kopfStil)),
                  SizedBox(
                    width: 92,
                    child: Text('Angelegt', style: kopfStil),
                  ),
                  SizedBox(
                    width: 176,
                    child: Text('Heute', style: kopfStil),
                  ),
                  SizedBox(
                    width: 104,
                    child: Text(
                      _liste == _Liste.nichtWeiter
                          ? 'Nicht weiter'
                          : 'Gelistet am',
                      style: kopfStil,
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    child: Text(
                      'Tage',
                      textAlign: TextAlign.right,
                      style: kopfStil,
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    child: Text(
                      'Stände',
                      textAlign: TextAlign.right,
                      style: kopfStil,
                    ),
                  ),
                ],
              ),
            ),
            for (final l in sichtbar)
              _MusterZeile(lauf: l, auswertung: a, liste: _liste),
            if (muster.length > sichtbar.length)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _alle = true),
                  child: Text('Alle ${muster.length} zeigen'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _MusterZeile extends StatelessWidget {
  const _MusterZeile({
    required this.lauf,
    required this.auswertung,
    required this.liste,
  });

  final MusterLauf lauf;
  final EntwicklungsAuswertung auswertung;
  final _Liste liste;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final klein = theme.textTheme.bodySmall;
    final l = lauf;
    final a = auswertung;
    final e = a.ergebnis(l);
    final datum =
        liste == _Liste.nichtWeiter ? a.eingestelltAm(l) : l.gelistetAm;
    final tage = l.tageBisListung;
    final unter = [
      if (l.gesamtprojekt case final g?) g,
      if (liste == _Liste.nichtWeiter)
        if (a.grund(l) case final g?) 'Grund: $g',
    ];
    return InkWell(
      onTap: () => oeffneProjekt(context, l.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (unter.isNotEmpty)
                    Text(
                      unter.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: klein?.copyWith(color: grau),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                l.kunde ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: klein?.copyWith(color: grau),
              ),
            ),
            SizedBox(
              width: 92,
              child: Text(Format.datum(l.angelegt), style: klein),
            ),
            SizedBox(
              width: 176,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: StatusMarke(e.label, art: _ergebnisArt(e)),
                ),
              ),
            ),
            SizedBox(
              width: 104,
              child: Text(
                datum == null ? '—' : Format.datum(datum),
                style: klein,
              ),
            ),
            SizedBox(
              width: 52,
              child: Text(
                tage == null ? '—' : '$tage',
                textAlign: TextAlign.right,
                style: klein,
              ),
            ),
            SizedBox(
              width: 60,
              child: Text(
                '${l.staende.length}',
                textAlign: TextAlign.right,
                style: klein?.copyWith(color: grau),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
