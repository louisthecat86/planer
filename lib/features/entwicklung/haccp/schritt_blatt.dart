import 'package:flutter/material.dart';

import '../../../core/constants/parameter_namen.dart';
import '../../../core/theme/app_stil.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/sheet_utils.dart';
import '../../articles/bratstrasse_schema.dart';
import 'eingabe_dialoge.dart';
import 'kette_bausteine.dart';
import 'prozess_kette.dart';
import 'prozess_modell.dart';

// Ein Schritt der Prozesskette mit seinen Werten — wie die Details einer
// Anlage im Artikel (articles/article_maschinen_ansicht.dart): Kopf mit
// Nummer, Name und Abteilung; das Plattenschema einer Bratstraße oder eines
// Kombiofens, sonst die Maschineneinstellungen als Text; darunter der
// Steckbrief der Anlage, weitere Werte und eigene. Jede Änderung geht
// sofort an die Kette — sie speichert sich selbst.

/// Öffnet [schritt] mit seinen Werten.
Future<void> schrittOeffnen(
  BuildContext context, {
  required ProzessSchritt schritt,
  required int nummer,
  required List<KatalogAnlage> katalog,
  required GrenzenKatalog grenzen,
  required ValueChanged<ProzessSchritt> onAenderung,
  required VoidCallback onEntfernen,
}) =>
    showSheetOhneAnimation<void>(
      context: context,
      constraints: const BoxConstraints(maxWidth: 820),
      builder: (_) => SchrittBlatt(
        schritt: schritt,
        nummer: nummer,
        katalog: katalog,
        grenzen: grenzen,
        onAenderung: onAenderung,
        onEntfernen: onEntfernen,
      ),
    );

/// Ein Schritt mit seinen Werten.
class SchrittBlatt extends StatefulWidget {
  const SchrittBlatt({
    super.key,
    required this.schritt,
    required this.nummer,
    required this.katalog,
    required this.grenzen,
    required this.onAenderung,
    required this.onEntfernen,
  });

  final ProzessSchritt schritt;
  final int nummer;
  final List<KatalogAnlage> katalog;
  final GrenzenKatalog grenzen;
  final ValueChanged<ProzessSchritt> onAenderung;
  final VoidCallback onEntfernen;

  @override
  State<SchrittBlatt> createState() => _SchrittBlattState();
}

class _SchrittBlattState extends State<SchrittBlatt> {
  late ProzessSchritt _s = widget.schritt;

  KatalogAnlage? get _anlage {
    final id = _s.maschineId;
    if (id == null) return null;
    for (final a in widget.katalog) {
      if (a.id == id) return a;
    }
    return null;
  }

  void _aendern(ProzessSchritt neu) {
    setState(() => _s = neu);
    widget.onAenderung(neu);
  }

  Future<void> _bearbeiten() async {
    final neu = await showDialog<ProzessSchritt>(
      context: context,
      builder: (_) => SchrittDialog(
        schritt: _s,
        katalog: widget.katalog,
        titel: 'Schritt ${widget.nummer} bearbeiten',
      ),
    );
    if (neu == null || !mounted) return;
    _aendern(neu);
  }

  Future<void> _entfernen() async {
    final ja = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final farben = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('Aus der Kette entfernen?'),
          content: Text(
            '„${_s.bezeichnung(widget.nummer)}" wird aus dem Prozess dieses '
            'Projekts entfernt — mit seinen Werten. Festgehaltene Versionen '
            'behalten den Schritt.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: farben.error,
                foregroundColor: farben.onError,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Entfernen'),
            ),
          ],
        );
      },
    );
    if (ja != true || !mounted) return;
    widget.onEntfernen();
    Navigator.of(context).pop();
  }

  Future<void> _notiz() async {
    final neu = await showDialog<String>(
      context: context,
      builder: (_) => TextEingabeDialog(
        titel: 'Maschineneinstellungen',
        label: 'Einstellungen',
        wert: _s.notiz,
        mehrzeilig: true,
        leerErlaubt: true,
        hinweis: 'Programm, Geschwindigkeit, Temperatur, Sonderhinweise …',
      ),
    );
    if (neu == null || !mounted) return;
    _aendern(_s.kopie(notiz: neu.trim()));
  }

  Future<void> _steckbrief(SteckbriefFeld f) async {
    final neu = await showDialog<String>(
      context: context,
      builder: (_) => WertDialog(
        titel: f.name,
        wert: steckbriefWert(_s, f.name)?.wert ?? '',
        einheit: f.einheit,
        grenze: widget.grenzen.fuer(
          name: f.name,
          maschine: _s.maschine,
          gruppe: kMaschinenNotizGruppe,
        ),
      ),
    );
    if (neu == null || !mounted) return;
    _aendern(mitSteckbriefWert(_s, f, neu));
  }

  Future<void> _weiterer(ProzessWert w) async {
    final neu = await showDialog<String>(
      context: context,
      builder: (_) => WertDialog(
        titel: w.name,
        wert: w.wert,
        einheit: w.einheit,
        grenze: widget.grenzen.fuer(
          name: w.name,
          maschine: _s.maschine,
          gruppe: w.gruppe,
        ),
      ),
    );
    if (neu == null || !mounted) return;
    // Leer nimmt ihn heraus — er stammt nicht aus dem Steckbrief.
    _aendern(
      wertSetzen(_s, alt: w, neu: neu.isEmpty ? null : w.kopie(wert: neu)),
    );
  }

  Set<String> _eigeneNamen({ProzessWert? ohne}) => {
        for (final w in eigeneWerte(_s))
          if (ohne == null || w.schluessel != ohne.schluessel)
            w.name.trim().toLowerCase(),
      };

  Future<void> _eigenerNeu() async {
    final r = await showDialog<({String name, String wert})>(
      context: context,
      builder: (_) => EigenerWertDialog(vergeben: _eigeneNamen()),
    );
    if (r == null || !mounted) return;
    final neu = mitEigenemWert(_s, r.name, wert: r.wert);
    if (neu != null) _aendern(neu);
  }

  Future<void> _eigenerBearbeiten(ProzessWert w) async {
    final r = await showDialog<({String name, String wert})>(
      context: context,
      builder: (_) => EigenerWertDialog(
        name: w.name,
        wert: w.wert,
        vergeben: _eigeneNamen(ohne: w),
      ),
    );
    if (r == null || !mounted) return;
    _aendern(
      wertSetzen(
        _s,
        alt: w,
        neu: ProzessWert(
          name: r.name,
          wert: r.wert,
          gruppe: w.gruppe.trim().isEmpty ? kEigeneWerteGruppe : w.gruppe,
          eigen: true,
        ),
      ),
    );
  }

  Future<void> _eigenerLoeschen(ProzessWert w) async {
    final ja = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wert löschen?'),
        content: Text('„${w.name}" wird gelöscht.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ja != true || !mounted) return;
    _aendern(wertSetzen(_s, alt: w));
  }

  /// Die Platten im Schema — gelesen wie im Artikel.
  PlattenTemperaturen _platten(String gruppe, BratschemaTyp typ) {
    final leer = PlattenTemperaturen.leer(typ);
    double? wert(String name) =>
        double.tryParse(plattenWert(_s, name, gruppe).replaceAll(',', '.'));
    return PlattenTemperaturen(
      oben: [
        for (var i = 0; i < leer.oben.length; i++) wert('Platte Oben ${i + 1}'),
      ],
      unten: [
        for (var i = 0; i < leer.unten.length; i++)
          wert('Platte Unten ${i + 1}'),
      ],
    );
  }

  void _plattenSetzen(String gruppe, PlattenTemperaturen neu) {
    // Geschrieben wie im Artikel: „180", „180.5" — leer heißt keine.
    String text(double? v) {
      if (v == null) return '';
      return v == v.roundToDouble() ? v.round().toString() : v.toString();
    }

    _aendern(
      mitPlatten(_s, gruppe, {
        for (var i = 0; i < neu.oben.length; i++)
          'Platte Oben ${i + 1}': text(neu.oben[i]),
        for (var i = 0; i < neu.unten.length; i++)
          'Platte Unten ${i + 1}': text(neu.unten[i]),
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final s = _s;
    final anlage = _anlage;
    final farbe = abteilungsFarbe(context, s.abteilung);
    final untertitel = [
      abteilungsName(s.abteilung),
      if (s.maschine.trim().isNotEmpty && s.prozessschritt.trim().isNotEmpty)
        s.prozessschritt.trim(),
    ].join(' · ');
    final gruppe = plattenGruppe(s.maschine);
    final steckbrief = anlage?.steckbrief ?? const <SteckbriefFeld>[];
    final eigene = eigeneWerte(s);
    final jeGruppe = <String, List<ProzessWert>>{};
    for (final w in weitereWerte(s, steckbrief)) {
      jeGruppe.putIfAbsent(w.gruppe.trim(), () => []).add(w);
    }

    return SingleChildScrollView(
      key: const ValueKey('schritt-blatt'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Kopf: Nummer in der Abteilungsfarbe — wie an der Kachel —,
          // Name, darunter Abteilung und Prozessschritt.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NummernMarke(nummer: widget.nummer, farbe: farbe, groesse: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.bezeichnung(widget.nummer),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      untertitel,
                      style: theme.textTheme.bodyMedium?.copyWith(color: grau),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('schritt-bearbeiten'),
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: 'Abteilung, Anlage und Prozessschritt',
                visualDensity: VisualDensity.compact,
                onPressed: _bearbeiten,
              ),
              IconButton(
                key: const ValueKey('schritt-entfernen'),
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: 'Aus der Kette entfernen',
                visualDensity: VisualDensity.compact,
                color: theme.colorScheme.error,
                onPressed: _entfernen,
              ),
              IconButton(
                key: const ValueKey('schritt-schliessen'),
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Schließen',
                visualDensity: VisualDensity.compact,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (anlage == null && s.maschine.trim().isNotEmpty) ...[
            HinweisBox(
              '„${s.maschine.trim()}" steht nicht im Katalog der Anlagen. '
              'Ordne über „Bearbeiten" eine zu — dann erscheint ihr '
              'Steckbrief.',
              art: StatusArt.warnung,
            ),
            const SizedBox(height: 12),
          ],

          // Das Plattenschema nur an Bratstraße und Kombiofen — wie im
          // Artikel; alle anderen Anlagen haben die Einstellungen als Text.
          if (gruppe != null) ...[
            Builder(
              builder: (context) {
                final typ = gruppe == kPlattenGruppeKombi
                    ? BratschemaTyp.kombiofen
                    : BratschemaTyp.bratstrasse;
                return BratstrasseSchema(
                  typ: typ,
                  werte: _platten(gruppe, typ),
                  onChanged: (neu) => _plattenSetzen(gruppe, neu),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
          if (gruppe == null || s.notiz.trim().isNotEmpty) ...[
            _NotizFeld(notiz: s.notiz, onTap: _notiz),
            const SizedBox(height: 12),
          ],

          Row(
            children: [
              Icon(Icons.tune, size: 16, color: grau),
              const SizedBox(width: 6),
              Text(
                'Parameter',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (steckbrief.isNotEmpty) ...[
            Bereich(
              titel: anlage!.name,
              icon: Icons.precision_manufacturing,
              untertitel: 'Steckbrief',
              innenAbstand: const EdgeInsets.fromLTRB(12, 0, 12, 2),
              child: _Trennzeilen(
                children: [
                  for (final f in steckbrief)
                    _WertZeile(
                      key: ValueKey('steckbrief-${f.name}'),
                      label: f.label,
                      wert: steckbriefWert(s, f.name)?.wert ?? '',
                      rechts: true,
                      onTap: () => _steckbrief(f),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          for (final MapEntry(:key, :value) in jeGruppe.entries) ...[
            Bereich(
              titel: key.isEmpty ? 'Weitere Werte' : key,
              innenAbstand: const EdgeInsets.fromLTRB(12, 0, 12, 2),
              child: _Trennzeilen(
                children: [
                  for (final w in value)
                    _WertZeile(
                      key: ValueKey('wert-${w.schluessel}'),
                      label: w.label,
                      wert: w.wert,
                      onTap: () => _weiterer(w),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          Bereich(
            titel: 'Zusätzliche Parameter',
            aktionen: [
              TextButton.icon(
                key: const ValueKey('eigener-wert-neu'),
                onPressed: _eigenerNeu,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Neu'),
              ),
            ],
            innenAbstand: const EdgeInsets.fromLTRB(12, 0, 4, 2),
            child: eigene.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Keine — über „Neu" legst du eigene Werte an.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: grau,
                      ),
                    ),
                  )
                : _Trennzeilen(
                    children: [
                      for (final w in eigene)
                        _EigeneZeile(
                          key: ValueKey('eigener-wert-${w.name}'),
                          wert: w,
                          onEdit: () => _eigenerBearbeiten(w),
                          onDelete: () => _eigenerLoeschen(w),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Die Maschineneinstellungen als Text — antippen zum Bearbeiten.
class _NotizFeld extends StatelessWidget {
  const _NotizFeld({required this.notiz, required this.onTap});

  final String notiz;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final text = notiz.trim();
    final hatText = text.isNotEmpty;
    // Material statt bemalter Box: Die Tipp-Welle malt auf das nächste
    // Material und wäre unter einer weißen Box unsichtbar.
    return Material(
      key: const ValueKey('schritt-notiz'),
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppMasse.ecken,
        side: BorderSide(color: theme.colorScheme.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.settings_outlined, size: 16, color: grau),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Maschineneinstellungen',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    hatText ? Icons.edit_outlined : Icons.add,
                    size: 16,
                    color: grau,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                hatText ? text : 'Tippen, um Einstellungen zu erfassen …',
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.35,
                  color: hatText ? theme.colorScheme.onSurface : grau,
                  fontStyle: hatText ? FontStyle.normal : FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Zeilen untereinander, getrennt durch dünne Linien — wie im Artikel.
class _Trennzeilen extends StatelessWidget {
  const _Trennzeilen({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final linie = Theme.of(context).colorScheme.outlineVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++)
          DecoratedBox(
            decoration: BoxDecoration(
              border: i == children.length - 1
                  ? null
                  : Border(bottom: BorderSide(color: linie)),
            ),
            child: children[i],
          ),
      ],
    );
  }
}

/// Eine Zeile mit Bezeichnung und Wert — antippen zum Bearbeiten. Leer
/// steht „eintragen …".
class _WertZeile extends StatelessWidget {
  const _WertZeile({
    super.key,
    required this.label,
    required this.wert,
    required this.onTap,
    this.rechts = false,
  });

  final String label;
  final String wert;
  final VoidCallback onTap;

  /// Den Wert am rechten Rand ausrichten (Steckbrief) statt am linken.
  final bool rechts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final text = wert.trim();
    final ausrichtung = rechts ? TextAlign.right : TextAlign.left;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(color: grau),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: text.isEmpty
                  ? Text(
                      'eintragen …',
                      textAlign: ausrichtung,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: grau,
                      ),
                    )
                  : Text(
                      text,
                      softWrap: true,
                      textAlign: ausrichtung,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
            if (!rechts) ...[
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.edit_outlined, size: 15, color: grau),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Ein eigener Wert mit Bearbeiten und Löschen.
class _EigeneZeile extends StatelessWidget {
  const _EigeneZeile({
    super.key,
    required this.wert,
    required this.onEdit,
    required this.onDelete,
  });

  final ProzessWert wert;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final text = wert.wert.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                wert.name,
                style: theme.textTheme.bodyMedium?.copyWith(color: grau),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                text.isEmpty ? '—' : text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: text.isEmpty ? null : FontWeight.w600,
                  color: text.isEmpty ? grau : null,
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.edit_outlined, size: 16, color: grau),
            tooltip: 'Bearbeiten',
            onPressed: onEdit,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              size: 16,
              color: theme.colorScheme.error,
            ),
            tooltip: 'Löschen',
            onPressed: onDelete,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
