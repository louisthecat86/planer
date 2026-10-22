// `show Value`: drift bringt eine eigene Klasse `Column` mit.
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_stil.dart';
import '../../../core/ui/bausteine.dart';
import '../projekte/projekt_screen.dart' show projektSpeichern;
import 'haccp_modell.dart';

// Gefahrenanalyse und Lenkungspunkte eines Projekts: Gefahren mit
// Bedeutung und Vorkommen bewerten, ab einem Risiko von 6 mit dem
// Entscheidungsbaum prüfen, ob der Schritt ein kritischer Lenkungspunkt
// ist.

/// Ab diesem Risiko (Bedeutung × Vorkommen) folgt der Entscheidungsbaum.
const int kRisikoHoch = 6;

const Uuid _uuid = Uuid();

/// Die Farbe eines Risikos: gering, mittel, hoch.
StatusArt risikoArt(int risiko) => risiko >= kRisikoHoch
    ? StatusArt.fehler
    : risiko >= 3
        ? StatusArt.warnung
        : StatusArt.ok;

/// „gering", „mittel", „hoch".
String risikoText(int risiko) => risiko >= kRisikoHoch
    ? 'hoch'
    : risiko >= 3
        ? 'mittel'
        : 'gering';

/// Die Farbe eines Ergebnisses im Entscheidungsbaum.
StatusArt lenkungsArt(Lenkungsart a) => switch (a) {
      Lenkungsart.ccp => StatusArt.fehler,
      Lenkungsart.cp => StatusArt.warnung,
      Lenkungsart.kp => StatusArt.neutral,
    };

/// Die HACCP-Gefahrenanalyse eines Projekts — im Reiter „Herstellung".
class ProjektHaccp extends ConsumerWidget {
  const ProjektHaccp({super.key, required this.projekt});

  final EntwicklungsProjekt projekt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final h = Haccp.aus(projekt.haccp);
    void speichern(Haccp neu) => projektSpeichern(
          context,
          ref,
          projekt.id,
          EntwicklungProjekteCompanion(haccp: Value(neu.alsJson())),
        );

    Future<void> assistent([Gefahr? vorhanden]) async {
      final ergebnis = await showDialog<HaccpErgebnis>(
        context: context,
        barrierDismissible: false,
        builder: (_) => HaccpAssistent(gefahr: vorhanden),
      );
      if (ergebnis == null) return;
      final gefahren = [
        for (final g in h.gefahren)
          if (g.id != ergebnis.gefahr.id) g,
      ];
      final index = vorhanden == null
          ? gefahren.length
          : h.gefahren.indexWhere((g) => g.id == vorhanden.id);
      gefahren.insert(
        index < 0 || index > gefahren.length ? gefahren.length : index,
        ergebnis.gefahr,
      );
      final punkt = ergebnis.lenkungspunkt;
      speichern(
        h.kopie(
          gefahren: gefahren,
          lenkungspunkte:
              punkt == null ? h.lenkungspunkte : [...h.lenkungspunkte, punkt],
        ),
      );
    }

    Future<void> gefahrBearbeiten(Gefahr g) async {
      final neu = await showDialog<Gefahr>(
        context: context,
        builder: (_) => GefahrDialog(gefahr: g),
      );
      if (neu == null) return;
      speichern(
        h.kopie(
          gefahren: [for (final x in h.gefahren) x.id == g.id ? neu : x],
        ),
      );
    }

    Future<void> punktBearbeiten(Lenkungspunkt? p) async {
      final neu = await showDialog<Lenkungspunkt>(
        context: context,
        builder: (_) => LenkungspunktDialog(punkt: p),
      );
      if (neu == null) return;
      speichern(
        h.kopie(
          lenkungspunkte: p == null
              ? [...h.lenkungspunkte, neu]
              : [for (final x in h.lenkungspunkte) x.id == p.id ? neu : x],
        ),
      );
    }

    final ccp =
        h.lenkungspunkte.where((l) => l.ergebnis == Lenkungsart.ccp).length;
    final cp = h.lenkungspunkte.where((l) => l.ergebnis == Lenkungsart.cp).length;
    final hoch = h.gefahren.where((g) => g.risiko >= kRisikoHoch).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: assistent,
              icon: const Icon(Icons.health_and_safety_outlined, size: 18),
              label: const Text('Gefahr bewerten'),
            ),
            OutlinedButton.icon(
              onPressed: () => punktBearbeiten(null),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Lenkungspunkt von Hand'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (projekt.neuerProzess && h.gefahren.isEmpty) ...[
          const HinweisBox(
            'Das Projekt bringt einen neuen Prozess mit — die '
            'Gefahrenanalyse fehlt noch.',
            art: StatusArt.warnung,
          ),
          const SizedBox(height: 10),
        ],
        Bereich(
          titel: 'Gefahrenanalyse',
          icon: Icons.warning_amber_rounded,
          untertitel: h.gefahren.isEmpty
              ? null
              : '${h.gefahren.length} '
                  '${h.gefahren.length == 1 ? 'Gefahr' : 'Gefahren'}'
                  '${hoch == 0 ? '' : ', $hoch mit hohem Risiko'}',
          innenAbstand: const EdgeInsets.fromLTRB(12, 6, 4, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (h.gefahren.isEmpty)
                const LeerHinweis(
                  'Noch keine Gefahr bewertet.',
                  icon: Icons.warning_amber_rounded,
                ),
              for (final g in h.gefahren)
                _GefahrZeile(
                  gefahr: g,
                  onPruefen: () => assistent(g),
                  onBearbeiten: () => gefahrBearbeiten(g),
                  onLoeschen: () => speichern(
                    h.kopie(
                      gefahren: [
                        for (final x in h.gefahren)
                          if (x.id != g.id) x,
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'Risiko = Bedeutung × Vorkommen (je 1 bis 3). Ab '
                '$kRisikoHoch prüft der Entscheidungsbaum, ob der Schritt '
                'ein kritischer Lenkungspunkt ist; darunter genügt die gute '
                'Hygienepraxis.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Bereich(
          titel: 'Lenkungspunkte',
          icon: Icons.account_tree_outlined,
          untertitel: h.lenkungspunkte.isEmpty ? null : '$ccp CCP · $cp CP',
          innenAbstand: const EdgeInsets.fromLTRB(12, 6, 4, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (h.lenkungspunkte.isEmpty)
                const LeerHinweis(
                  'Keine Lenkungspunkte. Sie entstehen, wenn eine Gefahr mit '
                  'hohem Risiko den Entscheidungsbaum durchläuft.',
                  icon: Icons.account_tree_outlined,
                ),
              for (final l in h.lenkungspunkte)
                _PunktZeile(
                  punkt: l,
                  onBearbeiten: () => punktBearbeiten(l),
                  onLoeschen: () => speichern(
                    h.kopie(
                      lenkungspunkte: [
                        for (final x in h.lenkungspunkte)
                          if (x.id != l.id) x,
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GefahrZeile extends StatelessWidget {
  const _GefahrZeile({
    required this.gefahr,
    required this.onPruefen,
    required this.onBearbeiten,
    required this.onLoeschen,
  });

  final Gefahr gefahr;
  final VoidCallback onPruefen;
  final VoidCallback onBearbeiten;
  final VoidCallback onLoeschen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final g = gefahr;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  g.gefahr.trim().isEmpty ? '(ohne Bezeichnung)' : g.gefahr,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${g.art.label} · Bedeutung ${g.schwere} × Vorkommen '
                  '${g.wahrscheinlichkeit}',
                  style: theme.textTheme.bodySmall?.copyWith(color: grau),
                ),
                if (g.massnahmen.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Maßnahmen: ${g.massnahmen.trim()}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusMarke(
            'Risiko ${g.risiko} · ${risikoText(g.risiko)}',
            art: risikoArt(g.risiko),
          ),
          IconButton(
            tooltip: 'Mit dem Entscheidungsbaum prüfen',
            icon: const Icon(Icons.account_tree_outlined, size: 18),
            onPressed: onPruefen,
          ),
          PopupMenuButton<bool>(
            tooltip: 'Mehr',
            icon: const Icon(Icons.more_vert, size: 18),
            onSelected: (loeschen) => loeschen ? onLoeschen() : onBearbeiten(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: false, child: Text('Bearbeiten')),
              PopupMenuItem(value: true, child: Text('Löschen')),
            ],
          ),
        ],
      ),
    );
  }
}

class _PunktZeile extends StatelessWidget {
  const _PunktZeile({
    required this.punkt,
    required this.onBearbeiten,
    required this.onLoeschen,
  });

  final Lenkungspunkt punkt;
  final VoidCallback onBearbeiten;
  final VoidCallback onLoeschen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final l = punkt;
    final antworten = [
      for (final f in kEntscheidungsbaum.values)
        if (l.antworten[f.schluessel] case final a?)
          '${f.kurz} ${a ? 'Ja' : 'Nein'}',
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.schritt.trim().isEmpty ? '(ohne Schritt)' : l.schritt,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  [
                    l.art.label,
                    if (antworten.isNotEmpty) antworten.join(' · '),
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(color: grau),
                ),
                if (l.beschreibung.trim().isNotEmpty)
                  Text(l.beschreibung.trim(), style: theme.textTheme.bodySmall),
                if (l.lenkung.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Lenkung: ${l.lenkung.trim()}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusMarke(l.ergebnis.kuerzel, art: lenkungsArt(l.ergebnis)),
          PopupMenuButton<bool>(
            tooltip: 'Mehr',
            icon: const Icon(Icons.more_vert, size: 18),
            onSelected: (loeschen) => loeschen ? onLoeschen() : onBearbeiten(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: false, child: Text('Bearbeiten')),
              PopupMenuItem(value: true, child: Text('Löschen')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Eine Stufe 1 bis 3 als Knopfreihe.
class _Stufe extends StatelessWidget {
  const _Stufe({
    required this.label,
    required this.wert,
    required this.onWahl,
    required this.texte,
  });

  final String label;
  final int wert;
  final ValueChanged<int> onWahl;

  /// Was die Stufen 1, 2 und 3 bedeuten.
  final List<String> texte;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            for (var i = 1; i <= 3; i++)
              ButtonSegment(value: i, label: Text('$i · ${texte[i - 1]}')),
          ],
          selected: {wert},
          onSelectionChanged: (s) => onWahl(s.first),
        ),
      ],
    );
  }
}

const List<String> _schwereTexte = ['leicht', 'mittel', 'schwer'];
const List<String> _vorkommenTexte = ['selten', 'möglich', 'häufig'];

/// Die Art einer Gefahr als Auswahl.
class _ArtWahl extends StatelessWidget {
  const _ArtWahl({required this.wert, required this.onWahl});

  final Gefahrenart wert;
  final ValueChanged<Gefahrenart> onWahl;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final a in Gefahrenart.values)
          ChoiceChip(
            label: Text(a.label),
            selected: wert == a,
            onSelected: (_) => onWahl(a),
          ),
      ],
    );
  }
}

/// Eine Gefahr bearbeiten.
class GefahrDialog extends StatefulWidget {
  const GefahrDialog({super.key, required this.gefahr});

  final Gefahr gefahr;

  @override
  State<GefahrDialog> createState() => _GefahrDialogState();
}

class _GefahrDialogState extends State<GefahrDialog> {
  late final TextEditingController _gefahr =
      TextEditingController(text: widget.gefahr.gefahr);
  late final TextEditingController _massnahmen =
      TextEditingController(text: widget.gefahr.massnahmen);
  late Gefahrenart _art = widget.gefahr.art;
  late int _schwere = widget.gefahr.schwere;
  late int _vorkommen = widget.gefahr.wahrscheinlichkeit;

  @override
  void dispose() {
    _gefahr.dispose();
    _massnahmen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final risiko = _schwere * _vorkommen;
    return AlertDialog(
      title: const Text('Gefahr bearbeiten'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, minWidth: 380),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _gefahr,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Gefahr'),
              ),
              const SizedBox(height: 10),
              _ArtWahl(wert: _art, onWahl: (a) => setState(() => _art = a)),
              const SizedBox(height: 12),
              _Stufe(
                label: 'Bedeutung',
                wert: _schwere,
                texte: _schwereTexte,
                onWahl: (s) => setState(() => _schwere = s),
              ),
              const SizedBox(height: 10),
              _Stufe(
                label: 'Vorkommen',
                wert: _vorkommen,
                texte: _vorkommenTexte,
                onWahl: (s) => setState(() => _vorkommen = s),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: StatusMarke(
                  'Risiko $risiko · ${risikoText(risiko)}',
                  art: risikoArt(risiko),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _massnahmen,
                minLines: 2,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'Maßnahmen'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            widget.gefahr.kopie(
              gefahr: _gefahr.text.trim(),
              art: _art,
              schwere: _schwere,
              wahrscheinlichkeit: _vorkommen,
              massnahmen: _massnahmen.text.trim(),
            ),
          ),
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}

/// Einen Lenkungspunkt anlegen oder bearbeiten.
class LenkungspunktDialog extends StatefulWidget {
  const LenkungspunktDialog({super.key, this.punkt});

  /// null: ein neuer.
  final Lenkungspunkt? punkt;

  @override
  State<LenkungspunktDialog> createState() => _LenkungspunktDialogState();
}

class _LenkungspunktDialogState extends State<LenkungspunktDialog> {
  late final TextEditingController _schritt =
      TextEditingController(text: widget.punkt?.schritt ?? '');
  late final TextEditingController _beschreibung =
      TextEditingController(text: widget.punkt?.beschreibung ?? '');
  late final TextEditingController _lenkung =
      TextEditingController(text: widget.punkt?.lenkung ?? '');
  late Gefahrenart _art = widget.punkt?.art ?? Gefahrenart.physikalisch;
  late Lenkungsart _ergebnis = widget.punkt?.ergebnis ?? Lenkungsart.cp;

  @override
  void dispose() {
    _schritt.dispose();
    _beschreibung.dispose();
    _lenkung.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alt = widget.punkt;
    return AlertDialog(
      title: Text(alt == null ? 'Neuer Lenkungspunkt' : 'Lenkungspunkt'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, minWidth: 380),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _schritt,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Prozessschritt'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _beschreibung,
                decoration: const InputDecoration(labelText: 'Gefahr'),
              ),
              const SizedBox(height: 10),
              _ArtWahl(wert: _art, onWahl: (a) => setState(() => _art = a)),
              const SizedBox(height: 12),
              SegmentedButton<Lenkungsart>(
                showSelectedIcon: false,
                segments: [
                  for (final a in Lenkungsart.values)
                    ButtonSegment(value: a, label: Text(a.kuerzel)),
                ],
                selected: {_ergebnis},
                onSelectionChanged: (s) => setState(() => _ergebnis = s.first),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _lenkung,
                minLines: 2,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Lenkung',
                  hintText: 'Grenzwerte, Überwachung, Korrekturmaßnahmen',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () {
            final punkt = (alt ?? Lenkungspunkt(id: _uuid.v4())).kopie(
              schritt: _schritt.text.trim(),
              beschreibung: _beschreibung.text.trim(),
              art: _art,
              ergebnis: _ergebnis,
              lenkung: _lenkung.text.trim(),
            );
            Navigator.of(context).pop(punkt);
          },
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}

/// Was der Assistent zurückgibt: die bewertete Gefahr und, bei hohem
/// Risiko, ihren Lenkungspunkt.
class HaccpErgebnis {
  const HaccpErgebnis(this.gefahr, this.lenkungspunkt);

  final Gefahr gefahr;
  final Lenkungspunkt? lenkungspunkt;
}

enum _Stufen { gefahr, baum, lenkung }

/// Der Assistent: Gefahr bewerten, bei hohem Risiko den Entscheidungsbaum
/// durchgehen, dann die Maßnahmen festhalten.
class HaccpAssistent extends StatefulWidget {
  const HaccpAssistent({super.key, this.gefahr});

  /// Eine schon erfasste Gefahr, die geprüft wird — null: eine neue.
  final Gefahr? gefahr;

  @override
  State<HaccpAssistent> createState() => _HaccpAssistentState();
}

class _HaccpAssistentState extends State<HaccpAssistent> {
  late final TextEditingController _gefahr =
      TextEditingController(text: widget.gefahr?.gefahr ?? '');
  final _schritt = TextEditingController();
  late final TextEditingController _massnahmen =
      TextEditingController(text: widget.gefahr?.massnahmen ?? '');
  late Gefahrenart _art = widget.gefahr?.art ?? Gefahrenart.physikalisch;
  late int _schwere = widget.gefahr?.schwere ?? 1;
  late int _vorkommen = widget.gefahr?.wahrscheinlichkeit ?? 1;
  _Stufen _stufe = _Stufen.gefahr;

  /// Die Antworten in der Reihenfolge, in der sie gegeben wurden.
  final List<(String, bool)> _antworten = [];

  int get _risiko => _schwere * _vorkommen;

  Map<String, bool> get _antwortMap => {
        for (final (f, a) in _antworten) f: a,
      };

  @override
  void dispose() {
    _gefahr.dispose();
    _schritt.dispose();
    _massnahmen.dispose();
    super.dispose();
  }

  void _weiter() {
    setState(() {
      _antworten.clear();
      _stufe = _risiko >= kRisikoHoch ? _Stufen.baum : _Stufen.lenkung;
    });
  }

  void _antwort(String frage, bool ja) {
    setState(() {
      _antworten.add((frage, ja));
      if (baumWeg(_antwortMap).ende != null) _stufe = _Stufen.lenkung;
    });
  }

  /// Nach dem Modifizieren: die Prüfung beginnt wieder bei Frage 1.
  void _neuPruefen() {
    setState(() {
      _antworten.clear();
      _stufe = _Stufen.baum;
    });
  }

  void _zurueck() {
    setState(() {
      if (_stufe == _Stufen.lenkung && _risiko >= kRisikoHoch) {
        if (_antworten.isNotEmpty) _antworten.removeLast();
        _stufe = _Stufen.baum;
      } else if (_stufe == _Stufen.baum && _antworten.isNotEmpty) {
        _antworten.removeLast();
      } else {
        _stufe = _Stufen.gefahr;
      }
    });
  }

  void _fertig() {
    final gefahr = Gefahr(
      id: widget.gefahr?.id ?? _uuid.v4(),
      gefahr: _gefahr.text.trim(),
      art: _art,
      schwere: _schwere,
      wahrscheinlichkeit: _vorkommen,
      massnahmen: _massnahmen.text.trim(),
    );
    Lenkungspunkt? punkt;
    if (_risiko >= kRisikoHoch) {
      final ende = baumWeg(_antwortMap).ende;
      final lenkung = _massnahmen.text.trim();
      punkt = Lenkungspunkt(
        id: _uuid.v4(),
        schritt: _schritt.text.trim(),
        beschreibung: gefahr.gefahr,
        art: _art,
        antworten: _antwortMap,
        ergebnis: ende == BaumEnde.ccp ? Lenkungsart.ccp : Lenkungsart.cp,
        // Wer erst modifizieren muss, sieht das am Lenkungspunkt.
        lenkung: ende == BaumEnde.modifizieren && lenkung.isEmpty
            ? 'Schritt, Verfahren oder Produkt modifizieren — danach neu '
                'prüfen.'
            : lenkung,
      );
    }
    Navigator.of(context).pop(HaccpErgebnis(gefahr, punkt));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weg = baumWeg(_antwortMap);
    final Widget inhalt;
    final List<Widget> knoepfe;
    switch (_stufe) {
      case _Stufen.gefahr:
        inhalt = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _gefahr,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Gefahr',
                hintText: 'z. B. Metallteile, Listerien, Allergen-Verschleppung',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _schritt,
              decoration: const InputDecoration(
                labelText: 'Prozessschritt',
                hintText: 'z. B. Metalldetektion, Garen, Abfüllen',
              ),
            ),
            const SizedBox(height: 10),
            _ArtWahl(wert: _art, onWahl: (a) => setState(() => _art = a)),
            const SizedBox(height: 12),
            _Stufe(
              label: 'Bedeutung',
              wert: _schwere,
              texte: _schwereTexte,
              onWahl: (s) => setState(() => _schwere = s),
            ),
            const SizedBox(height: 10),
            _Stufe(
              label: 'Vorkommen',
              wert: _vorkommen,
              texte: _vorkommenTexte,
              onWahl: (s) => setState(() => _vorkommen = s),
            ),
            const SizedBox(height: 10),
            HinweisBox(
              _risiko >= kRisikoHoch
                  ? 'Risiko $_risiko: hoch — weiter mit dem Entscheidungsbaum.'
                  : 'Risiko $_risiko: ${risikoText(_risiko)} — die gute '
                      'Hygienepraxis genügt, es folgen nur die Maßnahmen.',
              art: risikoArt(_risiko),
            ),
          ],
        );
        knoepfe = [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(onPressed: _weiter, child: const Text('Weiter')),
        ];
      case _Stufen.baum:
        final frage = kEntscheidungsbaum[weg.frage ?? 'f1']!;
        inhalt = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (f, a) in _antworten)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${kEntscheidungsbaum[f]!.nummer}: '
                  '${kEntscheidungsbaum[f]!.text}  →  ${a ? 'Ja' : 'Nein'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (_antworten.isNotEmpty) const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: AppMasse.ecken,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    frage.nummer,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(frage.text, style: theme.textTheme.titleSmall),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _antwort(frage.schluessel, false),
                    child: const Text('Nein'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _antwort(frage.schluessel, true),
                    child: const Text('Ja'),
                  ),
                ),
              ],
            ),
          ],
        );
        knoepfe = [
          TextButton(onPressed: _zurueck, child: const Text('Zurück')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
        ];
      case _Stufen.lenkung:
        final hoch = _risiko >= kRisikoHoch;
        final ende = weg.ende;
        final (String text, StatusArt art) = !hoch
            ? (
                'Kein Lenkungspunkt — die Gefahr wird über die gute '
                    'Hygienepraxis beherrscht.',
                StatusArt.ok,
              )
            : switch (ende) {
                BaumEnde.ccp => (
                    'Kritischer Lenkungspunkt (CCP): Grenzwerte, Überwachung '
                        'und Korrekturmaßnahmen festlegen.',
                    StatusArt.fehler,
                  ),
                BaumEnde.modifizieren => (
                    'Schritt, Verfahren oder Produkt modifizieren — danach '
                        'beginnt die Prüfung wieder bei Frage 1. Wer jetzt '
                        'übernimmt, hat die Gefahr bis dahin als '
                        'Lenkungspunkt (CP) in der Liste.',
                    StatusArt.warnung,
                  ),
                _ => (
                    'Lenkungspunkt (CP): Die Gefahr wird an diesem Schritt '
                        'beherrscht.',
                    StatusArt.warnung,
                  ),
              };
        inhalt = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HinweisBox(
              text,
              art: art,
              titel: 'Ergebnis',
              aktion: hoch && ende == BaumEnde.modifizieren
                  ? TextButton.icon(
                      onPressed: _neuPruefen,
                      icon: const Icon(Icons.replay, size: 16),
                      label: const Text('Neu prüfen'),
                    )
                  : null,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _massnahmen,
              autofocus: true,
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(
                labelText: hoch ? 'Lenkung' : 'Maßnahmen',
                hintText: hoch
                    ? 'Grenzwerte, Überwachung, Korrekturmaßnahmen'
                    : 'Maßnahmen der guten Hygienepraxis',
              ),
            ),
          ],
        );
        knoepfe = [
          TextButton(onPressed: _zurueck, child: const Text('Zurück')),
          FilledButton(onPressed: _fertig, child: const Text('Übernehmen')),
        ];
    }
    return AlertDialog(
      icon: const Icon(Icons.health_and_safety_outlined),
      title: Text(
        switch (_stufe) {
          _Stufen.gefahr => 'Gefahr bewerten',
          _Stufen.baum => 'Entscheidungsbaum',
          _Stufen.lenkung => 'Maßnahmen',
        },
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, minWidth: 400),
        child: SingleChildScrollView(child: inhalt),
      ),
      actions: knoepfe,
    );
  }
}
