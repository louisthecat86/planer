import 'package:erfassung_format/erfassung_format.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'artikel_seite.dart';
import 'bausteine.dart';
import 'erfassen_seite.dart';
import 'fotos.dart';
import 'heute_seite.dart';
import 'modell.dart';
import 'qr_empfang.dart';
import 'senden.dart';
import 'stil.dart';

/// Der Rahmen der App: unten die drei Bereiche — Heute, Anlagen, Fotos —,
/// oben der Titel des Bereichs, die Kamera fürs Musterfoto und „An PC".
/// Ohne Paket steht hier nur, wie man eins öffnet.
///
/// Hier wird auch ein Paket geöffnet — über den Knopf oder wenn die App
/// mit einer Datei gestartet wird („Öffnen mit").
class StartSeite extends StatefulWidget {
  const StartSeite({super.key, required this.modell});

  final ErfassungsModell modell;

  @override
  State<StartSeite> createState() => _StartSeiteState();
}

class _StartSeiteState extends State<StartSeite> {
  ErfassungsModell get _modell => widget.modell;

  /// Der gewählte Bereich: 0 Heute, 1 Anlagen, 2 Fotos.
  int _bereich = 0;

  @override
  void initState() {
    super.initState();
    // Über „Öffnen mit" gestartet — oder bei laufender App geöffnet.
    GeoeffneteDatei.lauschen(_geoeffneteDateiHolen);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _geoeffneteDateiHolen();
      // Etwa: ein Foto, während dessen Aufnahme Android die App
      // geschlossen hatte.
      final meldung = _modell.meldung;
      if (meldung != null && mounted) {
        _modell.meldung = null;
        melde(context, meldung);
      }
    });
  }

  Future<void> _geoeffneteDateiHolen() async {
    final text = await GeoeffneteDatei.holen();
    if (text == null || !mounted) return;
    await _paketUebernehmen(() => ErfassungsPaket.ausText(text));
  }

  Future<void> _paketWaehlen() async {
    final FilePickerResult? gewaehlt;
    try {
      gewaehlt = await FilePicker.pickFiles(withData: true);
    } catch (e) {
      if (mounted) melde(context, 'Die Datei ließ sich nicht öffnen: $e');
      return;
    }
    final bytes = gewaehlt?.files.firstOrNull?.bytes;
    if (bytes == null || !mounted) return;
    await _paketUebernehmen(() => paketAusBytes(bytes));
  }

  /// Das Paket per Kamera von den QR-Codes am Bildschirm des Planers.
  Future<void> _paketPerQr() async {
    final lesen = await qrEmpfangen(context);
    if (lesen == null || !mounted) return;
    await _paketUebernehmen(lesen);
  }

  /// Öffnet das Paket aus [lesen] — fragt vorher, wenn dabei Erfasstes
  /// verloren ginge.
  Future<void> _paketUebernehmen(ErfassungsPaket Function() lesen) async {
    final ErfassungsPaket paket;
    try {
      paket = lesen();
    } on FormatFehler catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Die Datei passt nicht'),
          content: Text(e.meldung),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Schließen'),
            ),
          ],
        ),
      );
      return;
    }
    if (!mounted) return;
    if (_modell.istGeoeffnet(paket)) {
      melde(context, 'Dieses Paket ist schon geöffnet.');
      return;
    }
    final stand = _modell.stand;
    final begonnen = stand.entwuerfe.isNotEmpty;
    if (stand.hatErfasstes || begonnen) {
      // Begonnene Erfassungen stehen in keinem Ergebnis — sie gingen mit
      // dem neuen Paket auf jeden Fall verloren.
      const begonnenText = ' Begonnene und laufende Produktionen gehen '
          'dabei verloren — sie stehen in keinem Ergebnis.';
      final ok = await nachfragen(
        context,
        titel: 'Neues Paket öffnen?',
        text: stand.ungesichert
            ? 'Es gibt Erfasstes, das noch in keiner Ergebnis-Datei steht. '
                'Mit dem neuen Paket geht es verloren — besser erst an den '
                'PC senden.${begonnen ? begonnenText : ''}'
            : stand.hatErfasstes
                ? 'Das Erfasste zum alten Paket wird vom Handy gelöscht — '
                    'auch die Fotos. Das Ergebnis ist als Datei '
                    'gespeichert.${begonnen ? begonnenText : ''}'
                : 'Es gibt begonnene oder laufende Produktionen. Mit dem '
                    'neuen Paket gehen sie verloren.',
        ja: 'Neues Paket öffnen',
        gefaehrlich: stand.ungesichert || begonnen,
      );
      if (!ok || !mounted) return;
    }
    await _modell.paketOeffnen(paket);
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    setState(() => _bereich = 0);
    final n = paket.produktionen.length;
    melde(
      context,
      'Paket geöffnet: ${n == 1 ? '1 Produktion' : '$n Produktionen'}, '
      '${paket.artikel.length} Artikel.',
    );
  }

  Future<void> _kuerzelAendern() async {
    final feld = TextEditingController(text: _modell.stand.kuerzel);
    final neu = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dein Kürzel'),
        content: TextField(
          controller: feld,
          autofocus: true,
          maxLength: 12,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            hintText: 'z. B. AB',
            helperText: 'Steht bei allem, was du erfasst.',
          ),
          onSubmitted: (t) => Navigator.of(ctx).pop(t),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
            onPressed: () => Navigator.of(ctx).pop(feld.text),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (neu != null) await _modell.kuerzelSetzen(neu);
  }

  /// Ohne Plan: erst den Artikel wählen, dann erfassen.
  Future<void> _ohnePlan() async {
    final artikel = await Navigator.of(context).push(
      MaterialPageRoute<PaketArtikel>(
        builder: (_) => ArtikelSeite(modell: _modell, waehlen: true),
      ),
    );
    if (artikel == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ErfassenSeite(modell: _modell, artikel: artikel),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _modell,
      builder: (context, _) {
        final f = Theme.of(context).colorScheme;
        final stand = _modell.stand;
        final paket = stand.paket;
        final fehler = _modell.speicherFehler;
        if (paket == null) {
          return Scaffold(
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                children: [
                  if (fehler != null) ...[
                    Hinweis(fehler, farbe: f.error, icon: Icons.error_outline),
                    const SizedBox(height: 12),
                  ],
                  _OhnePaket(
                    kuerzel: stand.kuerzel,
                    onOeffnen: _paketWaehlen,
                    onQr: _paketPerQr,
                    onKuerzel: _kuerzelAendern,
                  ),
                ],
              ),
            ),
          );
        }
        final jetzt = DateTime.now();
        final (titel, unter) = switch (_bereich) {
          0 => (
              'Heute',
              [
                tagKurz(jetzt).replaceFirst(' ', ', '),
                if (stand.kuerzel.isNotEmpty) stand.kuerzel,
              ].join(' · '),
            ),
          1 => ('Anlagen', '${paket.artikel.length} Artikel'),
          _ => (
              'Fotos',
              stand.fotos.isEmpty
                  ? 'Muster und Produktion'
                  : fotoAnzahlText(stand.fotos.length, stand.fotoBytes),
            ),
        };
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Kopf(
                  titel: titel,
                  unter: unter,
                  posten: stand.ungesichert ? stand.postenAnzahl : 0,
                  gesichert: stand.hatErfasstes && !stand.ungesichert,
                  onSenden: () => ergebnisBlattZeigen(
                    context,
                    _modell,
                    onPaket: _paketWaehlen,
                  ),
                  onMusterfoto: () => musterfotoAufnehmen(context, _modell),
                  onMenue: (wahl) => switch (wahl) {
                    _Menue.ohnePlan => _ohnePlan(),
                    _Menue.kuerzel => _kuerzelAendern(),
                    _Menue.paket => _paketWaehlen(),
                    _Menue.qr => _paketPerQr(),
                  },
                  kuerzel: stand.kuerzel,
                ),
                if (fehler != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    child: Hinweis(
                      fehler,
                      farbe: f.error,
                      icon: Icons.error_outline,
                    ),
                  ),
                Expanded(
                  child: IndexedStack(
                    index: _bereich,
                    children: [
                      HeuteAnsicht(modell: _modell, onOhnePlan: _ohnePlan),
                      AnlagenAnsicht(modell: _modell),
                      FotosAnsicht(modell: _modell),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _bereich,
            onDestinationSelected: (i) => setState(() => _bereich = i),
            destinations: [
              NavigationDestination(
                key: const ValueKey('bereich-heute'),
                icon: Badge(
                  isLabelVisible: stand.uebersicht(jetzt).laeuft.isNotEmpty,
                  backgroundColor: Farben.von(context).warnung,
                  smallSize: 9,
                  child: const Icon(Icons.task_alt_outlined),
                ),
                selectedIcon: const Icon(Icons.task_alt),
                label: 'Heute',
              ),
              const NavigationDestination(
                key: ValueKey('bereich-anlagen'),
                icon: Icon(Icons.tune_outlined),
                selectedIcon: Icon(Icons.tune),
                label: 'Anlagen',
              ),
              const NavigationDestination(
                key: ValueKey('bereich-fotos'),
                icon: Icon(Icons.photo_library_outlined),
                selectedIcon: Icon(Icons.photo_library),
                label: 'Fotos',
              ),
            ],
          ),
        );
      },
    );
  }
}

enum _Menue { ohnePlan, kuerzel, paket, qr }

/// Der Kopf über jedem Bereich: großer Titel, darunter eine Zeile, rechts
/// Kamera, „An PC" und das Menü.
class _Kopf extends StatelessWidget {
  const _Kopf({
    required this.titel,
    required this.unter,
    required this.posten,
    required this.gesichert,
    required this.onSenden,
    required this.onMusterfoto,
    required this.onMenue,
    required this.kuerzel,
  });

  final String titel;
  final String unter;

  /// Wie viel noch an den PC muss — 0: nichts.
  final int posten;

  /// Alles Erfasste steht schon in einer Ergebnis-Datei.
  final bool gesichert;
  final VoidCallback onSenden;
  final VoidCallback onMusterfoto;
  final void Function(_Menue) onMenue;
  final String kuerzel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = theme.colorScheme;
    final farben = Farben.von(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titel,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  unter,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: f.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            key: const ValueKey('start-musterfoto'),
            tooltip: 'Musterfoto aufnehmen',
            style: IconButton.styleFrom(
              backgroundColor: farben.flaeche2,
              foregroundColor: f.onSurface,
              fixedSize: const Size(46, 46),
            ),
            onPressed: onMusterfoto,
            icon: const Icon(Icons.photo_camera_outlined),
          ),
          const SizedBox(width: 6),
          FilledButton.icon(
            key: const ValueKey('an-pc'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 46),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: const StadiumBorder(),
              backgroundColor: posten > 0 ? f.primary : farben.flaeche2,
              foregroundColor: posten > 0 ? f.onPrimary : f.onSurface,
            ),
            onPressed: onSenden,
            icon: Icon(
              gesichert ? Icons.cloud_done_outlined : Icons.upload_outlined,
              size: 20,
              color: gesichert ? farben.ok : null,
            ),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('An PC'),
                if (posten > 0) ...[
                  const SizedBox(width: 7),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: f.onPrimary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$posten',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: f.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          PopupMenuButton<_Menue>(
            key: const ValueKey('menue'),
            tooltip: 'Mehr',
            onSelected: onMenue,
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: _Menue.ohnePlan,
                child: ListTile(
                  leading: Icon(Icons.add),
                  title: Text('Ohne Plan erfassen'),
                ),
              ),
              PopupMenuItem(
                value: _Menue.kuerzel,
                child: ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(
                    kuerzel.isEmpty ? 'Kürzel eintragen' : 'Kürzel: $kuerzel',
                  ),
                ),
              ),
              const PopupMenuItem(
                value: _Menue.paket,
                child: ListTile(
                  leading: Icon(Icons.folder_open),
                  title: Text('Anderes Paket öffnen'),
                ),
              ),
              const PopupMenuItem(
                value: _Menue.qr,
                child: ListTile(
                  leading: Icon(Icons.qr_code_scanner),
                  title: Text('Paket per QR-Code'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Noch kein Paket: was zu tun ist.
class _OhnePaket extends StatelessWidget {
  const _OhnePaket({
    required this.kuerzel,
    required this.onOeffnen,
    required this.onQr,
    required this.onKuerzel,
  });

  final String kuerzel;
  final VoidCallback onOeffnen;
  final VoidCallback onQr;
  final VoidCallback onKuerzel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 40),
        Center(
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: f.primaryContainer,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(
              Icons.inventory_2_outlined,
              size: 44,
              color: f.primary,
            ),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'Planer Erfassung',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Im Planer unter Einstellungen → Handy-Erfassung „Per QR-Code '
          'aufs Handy" wählen und hier scannen — oder die Datei '
          'erstellen, aufs Handy ziehen und hier öffnen.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: f.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 28),
        FilledButton.icon(
          key: const ValueKey('paket-qr'),
          onPressed: onQr,
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Per QR-Code empfangen'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const ValueKey('paket-oeffnen'),
          onPressed: onOeffnen,
          icon: const Icon(Icons.folder_open),
          label: const Text('Datei öffnen'),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: onKuerzel,
          icon: const Icon(Icons.person_outline),
          label:
              Text(kuerzel.isEmpty ? 'Kürzel eintragen' : 'Kürzel: $kuerzel'),
        ),
      ],
    );
  }
}
