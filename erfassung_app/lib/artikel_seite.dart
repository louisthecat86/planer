import 'package:erfassung_format/erfassung_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bausteine.dart';
import 'modell.dart';
import 'stil.dart';

/// Die Artikel des Pakets mit Suche. Antippen öffnet die Schritte des
/// Artikels mit ihren Maschineneinstellungen — mit [waehlen] gibt die
/// Seite stattdessen den Artikel zurück.
class ArtikelSeite extends StatefulWidget {
  const ArtikelSeite({super.key, required this.modell, this.waehlen = false});

  final ErfassungsModell modell;
  final bool waehlen;

  @override
  State<ArtikelSeite> createState() => _ArtikelSeiteState();
}

class _ArtikelSeiteState extends State<ArtikelSeite> {
  final _suche = TextEditingController();
  String _text = '';

  @override
  void dispose() {
    _suche.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.modell,
      builder: (context, _) {
        final theme = Theme.of(context);
        final f = theme.colorScheme;
        final stand = widget.modell.stand;
        final q = _text.trim().toLowerCase();
        final alle = stand.paket?.artikel ?? const <PaketArtikel>[];
        final treffer = [
          for (final a in alle)
            if (q.isEmpty || a.suchtext.contains(q)) a,
        ];
        // Was heute und morgen geplant ist, steht ohne Suche oben.
        final geplant = <String>{
          for (final p in stand.offen) p.artikelId,
        };
        if (q.isEmpty) {
          treffer.sort((a, b) {
            final ga = geplant.contains(a.id) ? 0 : 1;
            final gb = geplant.contains(b.id) ? 0 : 1;
            return ga.compareTo(gb);
          });
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(
              widget.waehlen ? 'Artikel wählen' : 'Maschineneinstellungen',
            ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: TextField(
                    controller: _suche,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Artikel oder Nummer suchen',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Suche leeren',
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _suche.clear();
                                setState(() => _text = '');
                              },
                            ),
                    ),
                    onChanged: (t) => setState(() => _text = t),
                  ),
                ),
                Expanded(
                  child: treffer.isEmpty
                      ? Center(
                          child: Text(
                            alle.isEmpty
                                ? 'Im Paket steht kein Artikel.'
                                : 'Keine Treffer.',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: f.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                          itemCount: treffer.length,
                          itemBuilder: (context, i) {
                            final a = treffer[i];
                            final geaendert = a.schritte
                                .map(stand.geaendertIn)
                                .fold(0, (s, n) => s + n);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: TippZeile(
                                titel: a.name,
                                unter: [
                                  if (a.nummer.isNotEmpty) a.nummer,
                                  a.schritte.length == 1
                                      ? '1 Schritt'
                                      : '${a.schritte.length} Schritte',
                                  if (geplant.contains(a.id)) 'geplant',
                                ].join(' · '),
                                rechts: geaendert == 0
                                    ? null
                                    : Marke(
                                        '$geaendert geändert',
                                        farbe: Farben.von(context).ok,
                                      ),
                                onTap: () => widget.waehlen
                                    ? Navigator.of(context).pop(a)
                                    : Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => SchritteSeite(
                                            modell: widget.modell,
                                            artikel: a,
                                          ),
                                        ),
                                      ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Die Schritte eines Artikels mit ihren Maschineneinstellungen: je
/// Schritt die Anlage und ihre Felder. Antippen ändert einen Wert.
class SchritteSeite extends StatelessWidget {
  const SchritteSeite({super.key, required this.modell, required this.artikel});

  final ErfassungsModell modell;
  final PaketArtikel artikel;

  Future<void> _bearbeiten(
    BuildContext context,
    PaketSchritt schritt,
    PaketFeld feld,
  ) async {
    final stand = modell.stand;
    final ergebnis = await showModalBottomSheet<_Eingabe>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _WertBlatt(
        schritt: schritt,
        feld: feld,
        aktuell: stand.wertVon(schritt, feld),
        geaendert: stand.istGeaendert(schritt, feld),
      ),
    );
    if (ergebnis == null) return;
    await modell.wertSetzen(
      artikel: artikel,
      schritt: schritt,
      feld: feld,
      neu: ergebnis.zuruecksetzen ? feld.wert : ergebnis.wert,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: modell,
      builder: (context, _) {
        final theme = Theme.of(context);
        final f = theme.colorScheme;
        final stand = modell.stand;
        return Scaffold(
          appBar: AppBar(title: Text(artikel.name)),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                if (artikel.nummer.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Artikel ${artikel.nummer} · tippe einen Wert an, um '
                      'einzutragen, was an der Anlage eingestellt ist.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: f.onSurfaceVariant,
                      ),
                    ),
                  ),
                for (final s in artikel.schritte)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _SchrittKarte(
                      schritt: s,
                      wertVon: (feld) => stand.wertVon(s, feld),
                      istGeaendert: (feld) => stand.istGeaendert(s, feld),
                      onFeld: (feld) => _bearbeiten(context, s, feld),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SchrittKarte extends StatelessWidget {
  const _SchrittKarte({
    required this.schritt,
    required this.wertVon,
    required this.istGeaendert,
    required this.onFeld,
  });

  final PaketSchritt schritt;
  final String? Function(PaketFeld) wertVon;
  final bool Function(PaketFeld) istGeaendert;
  final void Function(PaketFeld) onFeld;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = theme.colorScheme;
    final farbe = schritt.abteilungFarbe == null
        ? f.primary
        : Color(schritt.abteilungFarbe!);
    final platten = [
      for (final x in schritt.felder)
        if (x.art == FeldArt.platte) x,
    ];
    final andere = [
      for (final x in schritt.felder)
        if (x.art != FeldArt.platte) x,
    ];
    final unter = [
      if (schritt.abteilungName.isNotEmpty) schritt.abteilungName,
      if (schritt.prozessschritt case final p? when p != schritt.anlage) p,
    ].join(' · ');
    return Flaeche(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: farbe, width: 6)),
              color: f.surfaceContainerHighest,
            ),
            padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: farbe,
                    borderRadius: Masse.ecken,
                  ),
                  child: Text(
                    '${schritt.nummer}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        schritt.anlage,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (unter.isNotEmpty)
                        Text(
                          unter,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: f.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (platten.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
              child: _Platten(
                felder: platten,
                wertVon: wertVon,
                istGeaendert: istGeaendert,
                onFeld: onFeld,
              ),
            ),
          for (final (i, feld) in andere.indexed) ...[
            if (i > 0 || platten.isNotEmpty) const Divider(),
            _FeldZeile(
              feld: feld,
              wert: wertVon(feld),
              geaendert: istGeaendert(feld),
              onTap: () => onFeld(feld),
            ),
          ],
        ],
      ),
    );
  }
}

/// Ein Feld als Zeile: Name, Wert groß, Grenzen klein darunter.
class _FeldZeile extends StatelessWidget {
  const _FeldZeile({
    required this.feld,
    required this.wert,
    required this.geaendert,
    required this.onTap,
  });

  final PaketFeld feld;
  final String? wert;
  final bool geaendert;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = theme.colorScheme;
    final farben = Farben.von(context);
    final pruefung = feld.grenze?.pruefe(wert) ?? GrenzPruefung.inOrdnung;
    final leer = wert == null;
    final notiz = feld.art == FeldArt.notiz;
    final einheit = feld.einheit?.trim() ?? '';
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Masse.tippHoehe),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      feld.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: f.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      leer
                          ? 'eintragen …'
                          : einheit.isEmpty || notiz
                              ? wert!
                              : '$wert $einheit',
                      maxLines: notiz ? 6 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: (notiz
                              ? theme.textTheme.bodyLarge
                              : theme.textTheme.titleMedium)
                          ?.copyWith(
                        fontWeight: leer ? null : FontWeight.w600,
                        color: leer
                            ? f.onSurfaceVariant
                            : pruefung.status == GrenzStatus.ok
                                ? null
                                : farben.warnung,
                      ),
                    ),
                    if (pruefung.meldung case final m?)
                      Text(
                        m,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: farben.warnung,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (geaendert)
                Marke('geändert', farbe: farben.ok)
              else
                Icon(Icons.edit_outlined, size: 20, color: f.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Die Plattentemperaturen als Raster: je Reihe (Oben, Unten) die Platten
/// nebeneinander.
class _Platten extends StatelessWidget {
  const _Platten({
    required this.felder,
    required this.wertVon,
    required this.istGeaendert,
    required this.onFeld,
  });

  final List<PaketFeld> felder;
  final String? Function(PaketFeld) wertVon;
  final bool Function(PaketFeld) istGeaendert;
  final void Function(PaketFeld) onFeld;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = theme.colorScheme;
    final farben = Farben.von(context);
    final reihen = <String, List<PaketFeld>>{};
    for (final x in felder) {
      final reihe = x.name.contains('Oben') ? 'Oben' : 'Unten';
      (reihen[reihe] ??= []).add(x);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final MapEntry(key: reihe, value: liste) in reihen.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 2, 2, 6),
            child: Text(
              'Platten ${reihe.toLowerCase()} (°C)',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: f.onSurfaceVariant,
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, c) {
              const luecke = 6.0;
              const spalten = 5;
              final breite = ((c.maxWidth - (spalten - 1) * luecke) / spalten)
                  .floorToDouble();
              return Wrap(
                spacing: luecke,
                runSpacing: luecke,
                children: [
                  for (final x in liste)
                    SizedBox(
                      width: breite,
                      height: Masse.tippHoehe,
                      child: Material(
                        color: istGeaendert(x)
                            ? farben.ok.withValues(alpha: 0.14)
                            : f.surfaceContainerHighest,
                        shape: RoundedRectangleBorder(
                          borderRadius: Masse.ecken,
                          side: BorderSide(
                            color: istGeaendert(x) ? farben.ok : f.outline,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => onFeld(x),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                x.name.split(' ').last,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: f.onSurfaceVariant,
                                ),
                              ),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  wertVon(x) ?? '—',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// Was das Blatt zum Ändern zurückgibt.
class _Eingabe {
  const _Eingabe(this.wert, {this.zuruecksetzen = false});

  final String? wert;

  /// Zurück auf den Stand aus dem Paket.
  final bool zuruecksetzen;
}

/// Das Blatt zum Ändern eines Werts — mit den Grenzen des Planers: Harte
/// blockieren, weiche warnen.
class _WertBlatt extends StatefulWidget {
  const _WertBlatt({
    required this.schritt,
    required this.feld,
    required this.aktuell,
    required this.geaendert,
  });

  final PaketSchritt schritt;
  final PaketFeld feld;
  final String? aktuell;
  final bool geaendert;

  @override
  State<_WertBlatt> createState() => _WertBlattState();
}

class _WertBlattState extends State<_WertBlatt> {
  late final _eingabe = TextEditingController(text: widget.aktuell ?? '');

  @override
  void dispose() {
    _eingabe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = theme.colorScheme;
    final farben = Farben.von(context);
    final feld = widget.feld;
    final notiz = feld.art == FeldArt.notiz;
    final pruefung =
        feld.grenze?.pruefe(_eingabe.text) ?? GrenzPruefung.inOrdnung;
    final blockiert = pruefung.status == GrenzStatus.blockiert;
    final pc = feld.wert;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            feld.beschriftung,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            [
              widget.schritt.anlage,
              if (feld.grenze?.text case final g?) g,
            ].join(' · '),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: f.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _eingabe,
            autofocus: true,
            keyboardType: feld.istZahl
                ? const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  )
                : notiz
                    ? TextInputType.multiline
                    : TextInputType.text,
            inputFormatters: feld.istZahl
                ? [FilteringTextInputFormatter.allow(RegExp('[0-9.,-]'))]
                : null,
            minLines: notiz ? 3 : 1,
            maxLines: notiz ? 8 : 1,
            style: TextStyle(
              fontSize: notiz ? 16 : 22,
              fontWeight: notiz ? null : FontWeight.w600,
            ),
            decoration: InputDecoration(
              suffixText: notiz ? null : feld.einheit,
              helperText: 'Am PC: ${pc ?? '—'}',
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (pruefung.meldung case final m?) ...[
            const SizedBox(height: 10),
            Hinweis(
              blockiert ? '$m So lässt sich der Wert nicht speichern.' : m,
              farbe: blockiert ? f.error : farben.warnung,
              icon: blockiert ? Icons.block : Icons.warning_amber_outlined,
            ),
          ],
          const SizedBox(height: 14),
          FilledButton(
            onPressed: blockiert
                ? null
                : () => Navigator.of(context).pop(_Eingabe(_eingabe.text)),
            child: const Text('Speichern'),
          ),
          if (widget.geaendert) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(
                const _Eingabe(null, zuruecksetzen: true),
              ),
              child: const Text('Zurück auf den Stand vom PC'),
            ),
          ],
        ],
      ),
    );
  }
}
