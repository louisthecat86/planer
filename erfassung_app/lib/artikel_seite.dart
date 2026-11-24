import 'package:erfassung_format/erfassung_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bausteine.dart';
import 'fotos.dart';
import 'modell.dart';
import 'stand.dart';
import 'stil.dart';

/// Die Liste der Artikel im Bereich „Anlagen": oben die Suche, ohne
/// Suchwort zuerst, was bis heute geplant ist und was zuletzt offen war,
/// darunter alle. Die grüne Zahl sagt, wie viel an einem Artikel geändert
/// ist. Antippen öffnet die Kette mit den Maschineneinstellungen — mit
/// [waehlen] gibt die Liste stattdessen den Artikel zurück.
class AnlagenAnsicht extends StatefulWidget {
  const AnlagenAnsicht({super.key, required this.modell, this.waehlen});

  final ErfassungsModell modell;

  /// Wählt einen Artikel aus, statt ihn zu öffnen.
  final void Function(PaketArtikel)? waehlen;

  @override
  State<AnlagenAnsicht> createState() => _AnlagenAnsichtState();
}

class _AnlagenAnsichtState extends State<AnlagenAnsicht> {
  final _suche = TextEditingController();
  String _text = '';

  @override
  void dispose() {
    _suche.dispose();
    super.dispose();
  }

  void _oeffnen(PaketArtikel a) {
    final waehlen = widget.waehlen;
    if (waehlen != null) {
      waehlen(a);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SchritteSeite(modell: widget.modell, artikel: a),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.modell,
      builder: (context, _) {
        final theme = Theme.of(context);
        final f = theme.colorScheme;
        final stand = widget.modell.stand;
        final paket = stand.paket;
        final alle = paket?.artikel ?? const <PaketArtikel>[];
        final q = _text.trim().toLowerCase();

        int geaendert(PaketArtikel a) =>
            a.schritte.map(stand.geaendertIn).fold(0, (s, n) => s + n) +
            stand.kettenAenderungenIn(a.id);

        Widget zeile(PaketArtikel a, {String abschnitt = ''}) {
          final n = geaendert(a);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TippZeile(
              key: ValueKey('artikel-$abschnitt${a.id}'),
              titel: a.name,
              unter: [
                if (a.nummer.isNotEmpty) a.nummer,
                a.schritte.length == 1
                    ? '1 Schritt'
                    : '${a.schritte.length} Schritte',
              ].join(' · '),
              rechts: n == 0 ? null : ZahlPunkt(n),
              onTap: () => _oeffnen(a),
            ),
          );
        }

        final jetzt = DateTime.now();
        // Geplant bis einschließlich heute und noch nicht erfasst.
        final morgen = DateTime(jetzt.year, jetzt.month, jetzt.day + 1);
        final geplantIds = <String>{
          for (final p in paket?.produktionen ?? const <PaketProduktion>[])
            if (p.datum.isBefore(morgen) &&
                stand.statusVon(p.id) != ProduktionsStatus.erfasst)
              p.artikelId,
        };
        final geplant = [
          for (final a in alle)
            if (geplantIds.contains(a.id)) a,
        ];
        final zuletzt = [
          for (final id in stand.zuletzt)
            if (paket?.artikelMit(id) case final a?)
              if (!geplantIds.contains(id)) a,
        ];
        final treffer = [
          for (final a in alle)
            if (q.isEmpty || a.suchtext.contains(q)) a,
        ];

        final kopf = <Widget>[
          TextField(
            controller: _suche,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Artikel oder Nummer suchen',
              fillColor: f.surface,
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
          if (q.isEmpty && geplant.isNotEmpty) ...[
            Abschnitt('Heute geplant', zusatz: '${geplant.length}'),
            for (final a in geplant) zeile(a, abschnitt: 'h-'),
          ],
          if (q.isEmpty && zuletzt.isNotEmpty) ...[
            const Abschnitt('Zuletzt geöffnet'),
            for (final a in zuletzt) zeile(a, abschnitt: 'z-'),
          ],
          if (treffer.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Text(
                alle.isEmpty
                    ? 'Im Paket steht kein Artikel.'
                    : 'Keine Treffer.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: f.onSurfaceVariant,
                ),
              ),
            )
          else
            Abschnitt(
              q.isEmpty ? 'Alle Artikel' : 'Treffer',
              zusatz: '${treffer.length}',
            ),
        ];
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 32),
          itemCount: kopf.length + treffer.length,
          itemBuilder: (context, i) =>
              i < kopf.length ? kopf[i] : zeile(treffer[i - kopf.length]),
        );
      },
    );
  }
}

/// Die Artikel als eigene Seite — zum Wählen eines Artikels für eine
/// Erfassung ohne Plan ([waehlen]: gibt den Artikel zurück) oder zum
/// Öffnen.
class ArtikelSeite extends StatelessWidget {
  const ArtikelSeite({super.key, required this.modell, this.waehlen = false});

  final ErfassungsModell modell;
  final bool waehlen;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(waehlen ? 'Artikel wählen' : 'Maschineneinstellungen'),
      ),
      body: SafeArea(
        child: AnlagenAnsicht(
          modell: modell,
          waehlen: waehlen ? (a) => Navigator.of(context).pop(a) : null,
        ),
      ),
    );
  }
}

/// Die Prozesskette eines Artikels mit ihren Maschineneinstellungen —
/// als Zeitstrahl: je Schritt die Anlage, ihre Platten und ihre Werte als
/// Kacheln. Antippen ändert einen Wert; geänderte stehen grün da.
class SchritteSeite extends StatefulWidget {
  const SchritteSeite({super.key, required this.modell, required this.artikel});

  final ErfassungsModell modell;
  final PaketArtikel artikel;

  @override
  State<SchritteSeite> createState() => _SchritteSeiteState();
}

class _SchritteSeiteState extends State<SchritteSeite> {
  @override
  void initState() {
    super.initState();
    // Für „Zuletzt geöffnet" — nach dem ersten Bild, nicht mittendrin.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.modell.artikelGeoeffnet(widget.artikel.id),
    );
  }

  Future<void> _bearbeiten(
    BuildContext context,
    PaketSchritt schritt,
    PaketFeld feld,
  ) async {
    final stand = widget.modell.stand;
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
    await widget.modell.wertSetzen(
      artikel: widget.artikel,
      schritt: schritt,
      feld: feld,
      neu: ergebnis.zuruecksetzen ? feld.wert : ergebnis.wert,
    );
  }

  Future<void> _entfernen(BuildContext context, KettenSchritt k) async {
    final s = k.schritt;
    final ja = await nachfragen(
      context,
      titel: '${s.anlage} entfernen?',
      text: k.neu
          ? 'Die Maschine kommt wieder aus der Kette — was an ihr '
              'eingetragen ist, fällt weg.'
          : 'Beim Einlesen am PC fällt der Schritt aus der Prozesskette. '
              'Bis dahin lässt er sich hier mit „Behalten" zurückholen.',
      ja: 'Entfernen',
      gefaehrlich: true,
    );
    if (!ja) return;
    await widget.modell.schrittEntfernen(artikel: widget.artikel, schritt: s);
  }

  Future<void> _hinzufuegen(
    BuildContext context,
    List<KettenSchritt> kette,
    List<PaketMaschine> katalog,
  ) async {
    final maschine = await Navigator.of(context).push<PaketMaschine>(
      MaterialPageRoute(
        builder: (_) => MaschineWaehlenSeite(maschinen: katalog),
      ),
    );
    if (maschine == null || !context.mounted) return;
    final bleiben = [
      for (final k in kette)
        if (!k.entfernt) k.schritt,
    ];
    final platz = await showModalBottomSheet<_Platz>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PlatzBlatt(
        maschine: maschine,
        schritte: bleiben,
        vorschlag: platzVorschlag(bleiben, maschine.abteilung),
      ),
    );
    if (platz == null) return;
    await widget.modell.maschineHinzu(
      artikel: widget.artikel,
      maschine: maschine,
      nachSchrittId: platz.nachSchrittId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final modell = widget.modell;
    final artikel = widget.artikel;
    return ListenableBuilder(
      listenable: modell,
      builder: (context, _) {
        final theme = Theme.of(context);
        final f = theme.colorScheme;
        final stand = modell.stand;
        final kette = stand.ketteVon(artikel);
        final katalog = stand.paket?.maschinen ?? const <PaketMaschine>[];
        final geaendert =
            artikel.schritte.map(stand.geaendertIn).fold(0, (s, n) => s + n) +
                stand.kettenAenderungenIn(artikel.id);
        final bleiben = kette.where((k) => !k.entfernt).length;
        final fotosHier = stand.fotosVon(artikel.id).length;
        final fotoSchonDa = fotosHier == 0 &&
            (stand.paket?.fotosImPlanerVon(artikel.id) ?? 0) > 0;
        return Scaffold(
          appBar: AppBar(
            actions: [
              IconButton(
                key: const ValueKey('schritte-foto'),
                tooltip: fotoSchonDa
                    ? 'Im Programm ist schon ein Foto'
                    : 'Foto aus der Produktion',
                // Ausgegraut, wenn der Planer schon eins hat — ein neues
                // gibt es in der Erfassung mit „Trotzdem".
                onPressed: fotoSchonDa
                    ? null
                    : () => produktionsfotoAufnehmen(
                          context,
                          modell,
                          artikelId: artikel.id,
                          artikel: artikel.name,
                        ),
                icon: Badge(
                  isLabelVisible: fotosHier > 0,
                  label: Text('$fotosHier'),
                  child: const Icon(Icons.photo_camera_outlined),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        artikel.name,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (artikel.nummer.isNotEmpty) artikel.nummer,
                          bleiben == 1 ? '1 Schritt' : '$bleiben Schritte',
                          if (geaendert > 0) '$geaendert geändert',
                        ].join(' · '),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: f.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                for (final (i, k) in kette.indexed)
                  _KettenGlied(
                    schritt: k.schritt,
                    entfernt: k.entfernt,
                    letztes: i == kette.length - 1 && katalog.isEmpty,
                    child: _SchrittKarte(
                      schritt: k.schritt,
                      neu: k.neu,
                      entfernt: k.entfernt,
                      wertVon: (feld) => stand.wertVon(k.schritt, feld),
                      istGeaendert: (feld) =>
                          stand.istGeaendert(k.schritt, feld),
                      onFeld: (feld) => _bearbeiten(context, k.schritt, feld),
                      onEntfernen: () => _entfernen(context, k),
                      onBehalten: () => modell.schrittBehalten(k.schritt.id),
                    ),
                  ),
                if (katalog.isEmpty)
                  Hinweis(
                    'Im Paket steht kein Maschinenkatalog — es stammt aus '
                    'einem älteren Planer. Für „Maschine hinzufügen" am PC '
                    'ein neues Paket erstellen.',
                    farbe: f.onSurfaceVariant,
                    icon: Icons.info_outline,
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(left: 44),
                    child: OutlinedButton.icon(
                      key: const ValueKey('maschine-hinzu'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(Masse.tippHoehe),
                        foregroundColor: f.primary,
                        side: BorderSide(color: f.outline, width: 1.5),
                      ),
                      onPressed: () => _hinzufuegen(context, kette, katalog),
                      icon: const Icon(Icons.add),
                      label: const Text('Maschine hinzufügen'),
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

/// Ein Glied im Zeitstrahl: links die Nummer im Kreis in der Farbe der
/// Abteilung und die Linie zum nächsten Schritt, rechts die Karte.
class _KettenGlied extends StatelessWidget {
  const _KettenGlied({
    required this.schritt,
    required this.entfernt,
    required this.letztes,
    required this.child,
  });

  final PaketSchritt schritt;
  final bool entfernt;
  final bool letztes;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final f = Theme.of(context).colorScheme;
    final farbe = entfernt
        ? f.outline
        : schritt.abteilungFarbe == null
            ? f.primary
            : Color(schritt.abteilungFarbe!);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration:
                      BoxDecoration(color: farbe, shape: BoxShape.circle),
                  child: Text(
                    entfernt ? '–' : '${schritt.nummer}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: ThemeData.estimateBrightnessForColor(farbe) ==
                              Brightness.dark
                          ? Colors.white
                          : Colors.black,
                    ),
                  ),
                ),
                if (!letztes)
                  Expanded(
                    child: Container(width: 2, color: f.outline),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _SchrittKarte extends StatelessWidget {
  const _SchrittKarte({
    required this.schritt,
    required this.wertVon,
    required this.istGeaendert,
    required this.onFeld,
    required this.onEntfernen,
    required this.onBehalten,
    this.neu = false,
    this.entfernt = false,
  });

  final PaketSchritt schritt;
  final bool neu;
  final bool entfernt;
  final VoidCallback onEntfernen;
  final VoidCallback onBehalten;
  final String? Function(PaketFeld) wertVon;
  final bool Function(PaketFeld) istGeaendert;
  final void Function(PaketFeld) onFeld;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = theme.colorScheme;
    final farben = Farben.von(context);
    final platten = [
      for (final x in schritt.felder)
        if (x.art == FeldArt.platte) x,
    ];
    final werte = [
      for (final x in schritt.felder)
        if (x.art != FeldArt.platte && x.art != FeldArt.notiz) x,
    ];
    final notizen = [
      for (final x in schritt.felder)
        if (x.art == FeldArt.notiz) x,
    ];
    final unter = [
      if (schritt.abteilungName.isNotEmpty) schritt.abteilungName,
      if (schritt.prozessschritt case final p? when p != schritt.anlage) p,
    ].join(' · ');
    return Flaeche(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        schritt.anlage,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: entfernt ? f.onSurfaceVariant : null,
                          decoration:
                              entfernt ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      if (unter.isNotEmpty)
                        Text(
                          unter,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: f.onSurfaceVariant,
                          ),
                        ),
                      if (neu || entfernt)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: entfernt
                              ? Marke('wird entfernt', farbe: farben.warnung)
                              : Marke('neu', farbe: farben.ok),
                        ),
                    ],
                  ),
                ),
                if (entfernt)
                  TextButton(
                    key: ValueKey('schritt-behalten-${schritt.id}'),
                    onPressed: onBehalten,
                    child: const Text('Behalten'),
                  )
                else
                  IconButton(
                    key: ValueKey('schritt-entfernen-${schritt.id}'),
                    tooltip: 'Aus der Kette nehmen',
                    onPressed: onEntfernen,
                    icon: Icon(Icons.delete_outline, color: f.onSurfaceVariant),
                  ),
              ],
            ),
            // Ein herausgenommener Schritt zeigt seine Felder nicht mehr —
            // sie gehen nicht mit, bleiben aber für „Behalten" stehen.
            if (!entfernt) ...[
              if (platten.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 10, 8, 2),
                  child: _Platten(
                    felder: platten,
                    wertVon: wertVon,
                    istGeaendert: istGeaendert,
                    onFeld: onFeld,
                  ),
                ),
              if (werte.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 10, 8, 0),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final feld in werte)
                        _WertKachel(
                          key:
                              ValueKey('feld-${schritt.id}-${feld.schluessel}'),
                          feld: feld,
                          wert: wertVon(feld),
                          geaendert: istGeaendert(feld),
                          onTap: () => onFeld(feld),
                        ),
                    ],
                  ),
                ),
              for (final feld in notizen)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 6, 8, 0),
                  child: _WertKachel(
                    key: ValueKey('feld-${schritt.id}-${feld.schluessel}'),
                    feld: feld,
                    wert: wertVon(feld),
                    geaendert: istGeaendert(feld),
                    onTap: () => onFeld(feld),
                    breit: true,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Ein Wert als kleine Kachel: oben der Name, darunter der Wert. Geändert
/// grün, außerhalb der üblichen Grenzen orange, leer mit „eintragen".
class _WertKachel extends StatelessWidget {
  const _WertKachel({
    super.key,
    required this.feld,
    required this.wert,
    required this.geaendert,
    required this.onTap,
    this.breit = false,
  });

  final PaketFeld feld;
  final String? wert;
  final bool geaendert;
  final VoidCallback onTap;

  /// Über die ganze Breite — für die Notiz.
  final bool breit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = theme.colorScheme;
    final farben = Farben.von(context);
    final pruefung = feld.grenze?.pruefe(wert) ?? GrenzPruefung.inOrdnung;
    final warnung = pruefung.status != GrenzStatus.ok;
    final leer = wert == null;
    final einheit = feld.einheit?.trim() ?? '';
    final farbe = geaendert ? farben.ok : null;
    final text = leer
        ? 'eintragen'
        : einheit.isEmpty || breit
            ? wert!
            : '$wert $einheit';
    return Material(
      color: geaendert ? farben.ok.withValues(alpha: 0.14) : farben.flaeche2,
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: breit ? double.infinity : null,
          constraints: const BoxConstraints(minHeight: 52, minWidth: 72),
          padding: const EdgeInsets.fromLTRB(11, 7, 11, 7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                breit ? 'Notiz' : feld.name,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: farbe ?? f.onSurfaceVariant,
                ),
              ),
              Text(
                text,
                maxLines: breit ? 6 : 2,
                overflow: TextOverflow.ellipsis,
                style: (breit
                        ? theme.textTheme.bodyMedium
                        : theme.textTheme.titleSmall)
                    ?.copyWith(
                  fontWeight: leer || breit ? FontWeight.w500 : FontWeight.w800,
                  color: leer
                      ? f.onSurfaceVariant
                      : warnung
                          ? farben.warnung
                          : farbe,
                ),
              ),
              if (pruefung.meldung case final m? when warnung)
                Text(
                  m,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: farben.warnung,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Die Plattentemperaturen als Raster — angeordnet wie im Planer und an
/// der Anlage: oben, darunter das Band, dann unten; Platte 1 (Einlauf)
/// steht rechts, die Laufrichtung geht nach links.
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

  /// Die Nummer der Platte aus „Platte Oben 3".
  static int _nummer(PaketFeld f) => int.tryParse(f.name.split(' ').last) ?? 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = theme.colorScheme;
    final grau = f.onSurfaceVariant;
    List<PaketFeld> reihe(String wort) => [
          for (final x in felder)
            if (x.name.contains(wort)) x,
        ]..sort((a, b) => _nummer(a).compareTo(_nummer(b)));
    final oben = reihe('Oben');
    final unten = reihe('Unten');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Plattentemperaturen (°C)',
                style: theme.textTheme.bodyMedium?.copyWith(color: grau),
              ),
            ),
            Icon(Icons.arrow_back, size: 14, color: grau),
            const SizedBox(width: 4),
            Text(
              'Laufrichtung',
              style: theme.textTheme.bodySmall?.copyWith(color: grau),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (oben.isNotEmpty) ...[
          _PlattenReihe(
            label: 'oben',
            felder: oben,
            wertVon: wertVon,
            istGeaendert: istGeaendert,
            onFeld: onFeld,
          ),
          const SizedBox(height: 6),
          // Das Band zwischen den Platten oben und unten.
          Container(
            height: 6,
            decoration: BoxDecoration(
              color: f.outline,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 6),
        ],
        _PlattenReihe(
          label: 'unten',
          felder: unten,
          wertVon: wertVon,
          istGeaendert: istGeaendert,
          onFeld: onFeld,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Eine Reihe Platten in einer Zeile, von rechts nach links: Platte 1
/// steht rechts.
class _PlattenReihe extends StatelessWidget {
  const _PlattenReihe({
    required this.label,
    required this.felder,
    required this.wertVon,
    required this.istGeaendert,
    required this.onFeld,
  });

  final String label;
  final List<PaketFeld> felder;
  final String? Function(PaketFeld) wertVon;
  final bool Function(PaketFeld) istGeaendert;
  final void Function(PaketFeld) onFeld;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = theme.colorScheme;
    final farben = Farben.von(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 4),
          child: Text(
            label,
            textAlign: TextAlign.right,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: f.onSurfaceVariant,
            ),
          ),
        ),
        // Immer eine Zeile, damit die Straße auf einen Blick zu lesen ist —
        // die Platten teilen sich die Breite.
        Row(
          textDirection: TextDirection.rtl,
          children: [
            for (final (i, x) in felder.indexed) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(
                child: SizedBox(
                  height: Masse.tippHoehe,
                  child: Material(
                    color: istGeaendert(x)
                        ? farben.ok.withValues(alpha: 0.14)
                        : farben.flaeche2,
                    shape: RoundedRectangleBorder(
                      borderRadius: const BorderRadius.all(Radius.circular(8)),
                      side: istGeaendert(x)
                          ? BorderSide(color: farben.ok)
                          : BorderSide.none,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: ValueKey('platte-${x.name}'),
                      onTap: () => onFeld(x),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            x.name.split(' ').last,
                            maxLines: 1,
                            softWrap: false,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: f.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 1),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                wertVon(x) ?? '—',
                                maxLines: 1,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
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
    // Nur Plattentemperaturen sind immer Zahlen. Alles andere bekommt die
    // volle Tastatur — dort stehen auch Programme, Stufen oder „2 x 30".
    final zahl = feld.art == FeldArt.platte;
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
            keyboardType: zahl
                ? const TextInputType.numberWithOptions(decimal: true)
                : notiz
                    ? TextInputType.multiline
                    : TextInputType.text,
            inputFormatters: zahl
                ? [FilteringTextInputFormatter.allow(RegExp('[0-9.,]'))]
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

/// Der gewählte Platz: hinter [nachSchrittId], null ganz vorn.
class _Platz {
  const _Platz(this.nachSchrittId);

  final String? nachSchrittId;
}

/// Wählt, wo in der Kette die neue Maschine steht.
class _PlatzBlatt extends StatefulWidget {
  const _PlatzBlatt({
    required this.maschine,
    required this.schritte,
    required this.vorschlag,
  });

  final PaketMaschine maschine;
  final List<PaketSchritt> schritte;
  final String? vorschlag;

  @override
  State<_PlatzBlatt> createState() => _PlatzBlattState();
}

class _PlatzBlattState extends State<_PlatzBlatt> {
  late String? _nach = widget.vorschlag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = theme.colorScheme;
    Widget option(String? nach, String text) {
      final gewaehlt = _nach == nach;
      return ListTile(
        key: ValueKey('platz-${nach ?? 'vorn'}'),
        minTileHeight: Masse.tippHoehe,
        selected: gewaehlt,
        leading: Icon(
          gewaehlt ? Icons.radio_button_checked : Icons.radio_button_off,
        ),
        title: Text(text),
        onTap: () => setState(() => _nach = nach),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.maschine.name,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            '${widget.maschine.abteilungName} · wo steht sie in der Kette?',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: f.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                option(null, 'Ganz vorn'),
                for (final s in widget.schritte)
                  option(s.id, 'Nach ${s.nummer} · ${s.anlage}'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const ValueKey('platz-hinzu'),
            onPressed: () => Navigator.of(context).pop(_Platz(_nach)),
            child: const Text('Hinzufügen'),
          ),
        ],
      ),
    );
  }
}

/// Der Maschinenkatalog aus dem Paket mit Suche, nach Abteilung. Antippen
/// gibt die Maschine zurück.
class MaschineWaehlenSeite extends StatefulWidget {
  const MaschineWaehlenSeite({super.key, required this.maschinen});

  final List<PaketMaschine> maschinen;

  @override
  State<MaschineWaehlenSeite> createState() => _MaschineWaehlenSeiteState();
}

class _MaschineWaehlenSeiteState extends State<MaschineWaehlenSeite> {
  final _suche = TextEditingController();
  String _text = '';

  @override
  void dispose() {
    _suche.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = theme.colorScheme;
    final q = _text.trim().toLowerCase();
    final treffer = [
      for (final m in widget.maschinen)
        if (q.isEmpty || m.suchtext.contains(q)) m,
    ];
    final zeilen = <Widget>[];
    String? abteilung;
    for (final m in treffer) {
      if (m.abteilungName != abteilung) {
        abteilung = m.abteilungName;
        zeilen.add(Abschnitt(m.abteilungName));
      }
      zeilen.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TippZeile(
            key: ValueKey('maschine-${m.id}'),
            titel: m.name,
            streifen:
                m.abteilungFarbe == null ? null : Color(m.abteilungFarbe!),
            onTap: () => Navigator.of(context).pop(m),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Maschine hinzufügen')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: TextField(
                controller: _suche,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Maschine oder Abteilung suchen',
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
                        'Keine Treffer.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: f.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                      children: zeilen,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
