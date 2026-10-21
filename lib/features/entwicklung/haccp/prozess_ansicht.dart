import 'dart:convert';

// `show Value`: drift bringt eine eigene Klasse `Column` mit.
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/services/auto_backup_trigger.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/fehler_text.dart';
import '../../../core/utils/format.dart';
import '../daten/dateien.dart';
import '../projekte/projekt_modell.dart';
import '../projekte/projekt_repository.dart';
import 'prozess_modell.dart';
import 'prozess_vorlage.dart';

// Die Prozessparameter eines Projekts: Abschnitte mit Feldern, frei
// erweiterbar. Geändert wird eine Arbeitskopie; „Neue Version speichern"
// legt sie mit Versionsnummer und Notiz ab — im Projekt, in seinen
// früheren Ständen und als Eintrag im Verlauf.

/// Die eigene Vorlage — verschlüsselt bei den Entwicklungsdateien, damit
/// sie mit ins Backup wandert und nicht im Code steht.
class ProzessVorlageDienst {
  ProzessVorlageDienst(this._dateien);

  final EntwicklungDateienDienst _dateien;

  /// Die gespeicherte eigene Vorlage — null, wenn es keine gibt.
  Future<Prozessparameter?> eigene() async =>
      vorlageAus(await _dateien.lesen(kProzessVorlageDateiId));

  /// Die eigene Vorlage oder sonst die eingebaute.
  Future<Prozessparameter> vorlage() async =>
      await eigene() ?? kNeutraleProzessVorlage;

  /// Speichert die Abschnitte und Felder von [p] — ohne Werte — als
  /// eigene Vorlage.
  Future<void> speichern(Prozessparameter p) => _dateien.speichern(
        id: kProzessVorlageDateiId,
        name: 'Prozessvorlage.json',
        mimeTyp: 'application/json',
        inhalt: utf8.encode(alsVorlage(p).alsJson() ?? '{}'),
      );

  /// Löscht die eigene Vorlage; danach gilt wieder die eingebaute.
  Future<void> zuruecksetzen() => _dateien.loeschen(kProzessVorlageDateiId);
}

final prozessVorlageProvider = Provider<ProzessVorlageDienst>(
  (ref) => ProzessVorlageDienst(ref.watch(entwicklungDateienProvider)),
);

/// Der Reiter „Prozess" eines Projekts.
class ProjektProzess extends ConsumerStatefulWidget {
  const ProjektProzess({super.key, required this.projekt});

  final EntwicklungsProjekt projekt;

  @override
  ConsumerState<ProjektProzess> createState() => _ProjektProzessState();
}

class _ProjektProzessState extends ConsumerState<ProjektProzess>
    with AutomaticKeepAliveClientMixin {
  late Prozessparameter _arbeit = Prozessparameter.aus(widget.projekt.prozess);

  /// Es gibt Änderungen, die noch nicht als Version gespeichert sind.
  bool _geaendert = false;

  /// Hält die Arbeitskopie, solange sie ungespeichert ist — auch wenn man
  /// den Reiter wechselt.
  @override
  bool get wantKeepAlive => _geaendert;

  @override
  void didUpdateWidget(ProjektProzess alt) {
    super.didUpdateWidget(alt);
    if (!_geaendert && alt.projekt.prozess != widget.projekt.prozess) {
      _arbeit = Prozessparameter.aus(widget.projekt.prozess);
    }
  }

  void _setze(Prozessparameter neu) {
    setState(() {
      _arbeit = neu;
      _geaendert = true;
    });
    updateKeepAlive();
  }

  void _verwerfen() {
    setState(() {
      _arbeit = Prozessparameter.aus(widget.projekt.prozess);
      _geaendert = false;
    });
    updateKeepAlive();
  }

  void _melde(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ── Abschnitte und Felder ───────────────────────────────────────────

  void _abschnittErsetzen(ProzessAbschnitt neu) => _setze(
        _arbeit.kopie(
          abschnitte: [
            for (final a in _arbeit.abschnitte) a.id == neu.id ? neu : a,
          ],
        ),
      );

  void _wert(ProzessAbschnitt a, ProzessFeld f, String wert) =>
      _abschnittErsetzen(
        a.kopie(
          felder: [for (final x in a.felder) x.id == f.id ? x.mitWert(wert) : x],
        ),
      );

  Future<void> _abschnittNeu() async {
    final titel = await showDialog<String>(
      context: context,
      builder: (_) => const TextEingabeDialog(
        titel: 'Neuer Abschnitt',
        label: 'Bezeichnung',
        bestaetigen: 'Hinzufügen',
      ),
    );
    if (titel == null || titel.trim().isEmpty) return;
    final id = neueParameterId(titel, _arbeit.abschnitte.map((a) => a.id));
    _setze(
      _arbeit.kopie(
        abschnitte: [
          ..._arbeit.abschnitte,
          ProzessAbschnitt(id: id, titel: titel.trim()),
        ],
      ),
    );
  }

  Future<void> _abschnittUmbenennen(ProzessAbschnitt a) async {
    final titel = await showDialog<String>(
      context: context,
      builder: (_) => TextEingabeDialog(
        titel: 'Abschnitt umbenennen',
        label: 'Bezeichnung',
        wert: a.titel,
      ),
    );
    if (titel == null || titel.trim().isEmpty) return;
    _abschnittErsetzen(a.kopie(titel: titel.trim()));
  }

  void _abschnittVerschieben(ProzessAbschnitt a, int richtung) {
    final liste = [..._arbeit.abschnitte];
    final i = liste.indexWhere((x) => x.id == a.id);
    final j = i + richtung;
    if (i < 0 || j < 0 || j >= liste.length) return;
    liste
      ..removeAt(i)
      ..insert(j, a);
    _setze(_arbeit.kopie(abschnitte: liste));
  }

  void _abschnittLoeschen(ProzessAbschnitt a) => _setze(
        _arbeit.kopie(
          abschnitte: [
            for (final x in _arbeit.abschnitte)
              if (x.id != a.id) x,
          ],
        ),
      );

  Future<void> _feldBearbeiten(ProzessAbschnitt a, ProzessFeld? f) async {
    final neu = await showDialog<ProzessFeld>(
      context: context,
      builder: (_) => FeldDialog(
        feld: f,
        vorhandeneIds: a.felder.map((x) => x.id).toList(),
      ),
    );
    if (neu == null) return;
    _abschnittErsetzen(
      a.kopie(
        felder: f == null
            ? [...a.felder, neu]
            : [for (final x in a.felder) x.id == f.id ? neu : x],
      ),
    );
  }

  void _feldLoeschen(ProzessAbschnitt a, ProzessFeld f) => _abschnittErsetzen(
        a.kopie(
          felder: [
            for (final x in a.felder)
              if (x.id != f.id) x,
          ],
        ),
      );

  void _feldVerschieben(ProzessAbschnitt a, ProzessFeld f, int richtung) {
    final liste = [...a.felder];
    final i = liste.indexWhere((x) => x.id == f.id);
    final j = i + richtung;
    if (i < 0 || j < 0 || j >= liste.length) return;
    liste
      ..removeAt(i)
      ..insert(j, f);
    _abschnittErsetzen(a.kopie(felder: liste));
  }

  // ── Vorlage und Versionen ───────────────────────────────────────────

  Future<void> _vorlageVerwenden() async {
    try {
      final v = await ref.read(prozessVorlageProvider).vorlage();
      if (!mounted) return;
      _setze(v);
    } catch (e) {
      if (mounted) {
        _melde('Die Vorlage ließ sich nicht laden: ${fehlerText(e)}');
      }
    }
  }

  Future<void> _alsVorlage() async {
    final ja = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Als Vorlage speichern?'),
        content: const Text(
          'Abschnitte und Felder dieses Projekts — ohne die Werte — werden '
          'die Vorlage für neue Projekte. Eine frühere eigene Vorlage wird '
          'ersetzt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (ja != true) return;
    try {
      await ref.read(prozessVorlageProvider).speichern(_arbeit);
      ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Vorlage');
      if (mounted) _melde('Als Vorlage gespeichert.');
    } catch (e) {
      if (mounted) {
        _melde('Die Vorlage ließ sich nicht speichern: ${fehlerText(e)}');
      }
    }
  }

  Future<void> _vorlageZuruecksetzen() async {
    await ref.read(prozessVorlageProvider).zuruecksetzen();
    if (mounted) _melde('Ab jetzt gilt wieder die eingebaute Vorlage.');
  }

  Future<void> _speichern() async {
    final notiz = await showDialog<String>(
      context: context,
      builder: (_) => const TextEingabeDialog(
        titel: 'Neue Version speichern',
        label: 'Was hat sich geändert?',
        mehrzeilig: true,
        bestaetigen: 'Speichern',
        leerErlaubt: true,
      ),
    );
    if (notiz == null || !mounted) return;
    final p = widget.projekt;
    final gespeichert = Prozessparameter.aus(p.prozess);
    final historie = ProzessStand.listeAus(p.prozessHistorie);
    final version = gespeichert.leer && historie.isEmpty
        ? '1.0'
        : naechsteVersion(gespeichert.version);
    final jetzt = DateTime.now();
    final neu = _arbeit.kopie(version: version, stand: jetzt);
    try {
      final repo = ref.read(projektRepositoryProvider);
      await repo.projektAendern(
        p.id,
        EntwicklungProjekteCompanion(
          prozess: Value(neu.alsJson()),
          prozessHistorie: Value(
            ProzessStand.listeZuJson([
              ...historie,
              ProzessStand(
                version: version,
                datum: jetzt,
                notiz: notiz.trim(),
                parameter: neu,
              ),
            ]),
          ),
        ),
      );
      await repo.eintragAnlegen(
        projektId: p.id,
        art: EintragArt.parameter,
        titel: 'Prozessparameter $version',
        datum: DateTime(jetzt.year, jetzt.month, jetzt.day),
        beschreibung: notiz.trim().isEmpty ? null : notiz.trim(),
        status: EintragStatus.erledigt,
        wert: neu.alsJson(),
      );
      ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Prozess');
      if (!mounted) return;
      setState(() {
        _arbeit = neu;
        _geaendert = false;
      });
      updateKeepAlive();
    } catch (e) {
      if (mounted) _melde('Speichern fehlgeschlagen: ${fehlerText(e)}');
    }
  }

  Future<void> _vergleichen() async {
    final p = widget.projekt;
    final staende = ProzessStand.listeAus(p.prozessHistorie);
    final liste = <({String label, Prozessparameter parameter})>[
      for (final s in staende)
        (
          label: 'Version ${s.version} · ${Format.datum(s.datum)}',
          parameter: s.parameter,
        ),
      if (_geaendert) (label: 'Arbeitsstand (ungespeichert)', parameter: _arbeit),
    ];
    if (liste.length < 2) {
      _melde('Zum Vergleichen braucht es mindestens zwei Stände.');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => ParameterVergleichDialog(staende: liste),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final p = widget.projekt;
    final gespeichert = Prozessparameter.aus(p.prozess);
    final historie = ProzessStand.listeAus(p.prozessHistorie);

    if (_arbeit.leer && !_geaendert) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Bereich(
            titel: 'Prozessparameter',
            icon: Icons.precision_manufacturing_outlined,
            innenAbstand: const EdgeInsets.fromLTRB(12, 10, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Noch keine Prozessparameter. Beginne mit der Vorlage — '
                  'Rohware, Verarbeitung, Garen, Kühlen, Verpackung — oder '
                  'leer mit eigenen Abschnitten.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _vorlageVerwenden,
                      icon: const Icon(Icons.library_add_outlined, size: 18),
                      label: const Text('Vorlage verwenden'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _abschnittNeu,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Leer beginnen'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    }

    final stand = gespeichert.stand;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              gespeichert.leer
                  ? 'Noch nicht gespeichert'
                  : 'Version ${gespeichert.version}'
                      '${stand == null ? '' : ' · ${Format.datum(stand)}'}',
              style: theme.textTheme.titleSmall,
            ),
            if (_geaendert)
              const StatusMarke('ungespeichert', art: StatusArt.warnung),
            FilledButton.icon(
              onPressed: _geaendert ? _speichern : null,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('Neue Version speichern'),
            ),
            if (_geaendert)
              TextButton.icon(
                onPressed: _verwerfen,
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('Verwerfen'),
              ),
            OutlinedButton.icon(
              onPressed: _abschnittNeu,
              icon: const Icon(Icons.playlist_add, size: 18),
              label: const Text('Abschnitt'),
            ),
            PopupMenuButton<String>(
              tooltip: 'Mehr',
              icon: const Icon(Icons.more_vert),
              onSelected: (wahl) {
                switch (wahl) {
                  case 'vergleichen':
                    _vergleichen();
                  case 'vorlage':
                    _alsVorlage();
                  case 'zuruecksetzen':
                    _vorlageZuruecksetzen();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'vergleichen',
                  child: Text('Versionen vergleichen'),
                ),
                PopupMenuItem(
                  value: 'vorlage',
                  child: Text('Als Vorlage speichern'),
                ),
                PopupMenuItem(
                  value: 'zuruecksetzen',
                  child: Text('Eingebaute Vorlage wieder verwenden'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final (i, a) in _arbeit.abschnitte.indexed) ...[
          _AbschnittKarte(
            key: ValueKey('abschnitt-${a.id}'),
            abschnitt: a,
            erster: i == 0,
            letzter: i == _arbeit.abschnitte.length - 1,
            onWert: (f, w) => _wert(a, f, w),
            onUmbenennen: () => _abschnittUmbenennen(a),
            onVerschieben: (r) => _abschnittVerschieben(a, r),
            onLoeschen: () => _abschnittLoeschen(a),
            onFeld: (f) => _feldBearbeiten(a, f),
            onFeldLoeschen: (f) => _feldLoeschen(a, f),
            onFeldVerschieben: (f, r) => _feldVerschieben(a, f, r),
          ),
          const SizedBox(height: 12),
        ],
        if (historie.isNotEmpty)
          Bereich(
            titel: 'Versionen',
            icon: Icons.history,
            untertitel: '${historie.length}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final s in historie.reversed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      'Version ${s.version} · ${Format.datum(s.datum)}'
                      '${s.notiz.trim().isEmpty ? '' : ' — ${s.notiz.trim()}'}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AbschnittKarte extends StatelessWidget {
  const _AbschnittKarte({
    super.key,
    required this.abschnitt,
    required this.erster,
    required this.letzter,
    required this.onWert,
    required this.onUmbenennen,
    required this.onVerschieben,
    required this.onLoeschen,
    required this.onFeld,
    required this.onFeldLoeschen,
    required this.onFeldVerschieben,
  });

  final ProzessAbschnitt abschnitt;
  final bool erster;
  final bool letzter;
  final void Function(ProzessFeld feld, String wert) onWert;
  final VoidCallback onUmbenennen;
  final ValueChanged<int> onVerschieben;
  final VoidCallback onLoeschen;

  /// Feld bearbeiten — null: ein neues.
  final ValueChanged<ProzessFeld?> onFeld;
  final ValueChanged<ProzessFeld> onFeldLoeschen;
  final void Function(ProzessFeld feld, int richtung) onFeldVerschieben;

  @override
  Widget build(BuildContext context) {
    final a = abschnitt;
    return Bereich(
      titel: a.titel,
      icon: Icons.settings_outlined,
      aktionen: [
        IconButton(
          tooltip: 'Feld hinzufügen',
          icon: const Icon(Icons.add, size: 18),
          onPressed: () => onFeld(null),
        ),
        PopupMenuButton<String>(
          tooltip: 'Abschnitt',
          icon: const Icon(Icons.more_vert, size: 18),
          onSelected: (wahl) {
            switch (wahl) {
              case 'umbenennen':
                onUmbenennen();
              case 'hoch':
                onVerschieben(-1);
              case 'runter':
                onVerschieben(1);
              case 'loeschen':
                onLoeschen();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'umbenennen', child: Text('Umbenennen')),
            PopupMenuItem(
              value: 'hoch',
              enabled: !erster,
              child: const Text('Nach oben'),
            ),
            PopupMenuItem(
              value: 'runter',
              enabled: !letzter,
              child: const Text('Nach unten'),
            ),
            const PopupMenuItem(value: 'loeschen', child: Text('Löschen')),
          ],
        ),
      ],
      innenAbstand: const EdgeInsets.fromLTRB(12, 8, 4, 10),
      child: a.felder.isEmpty
          ? const LeerHinweis('Noch keine Felder.')
          : LayoutBuilder(
              builder: (context, c) {
                final breit = c.maxWidth >= 640;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, f) in a.felder.indexed)
                      _FeldZeile(
                        key: ValueKey('feld-${a.id}/${f.id}'),
                        feld: f,
                        breit: breit,
                        erster: i == 0,
                        letzter: i == a.felder.length - 1,
                        onWert: (w) => onWert(f, w),
                        onBearbeiten: () => onFeld(f),
                        onLoeschen: () => onFeldLoeschen(f),
                        onVerschieben: (r) => onFeldVerschieben(f, r),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

class _FeldZeile extends StatelessWidget {
  const _FeldZeile({
    super.key,
    required this.feld,
    required this.breit,
    required this.erster,
    required this.letzter,
    required this.onWert,
    required this.onBearbeiten,
    required this.onLoeschen,
    required this.onVerschieben,
  });

  final ProzessFeld feld;
  final bool breit;
  final bool erster;
  final bool letzter;
  final ValueChanged<String> onWert;
  final VoidCallback onBearbeiten;
  final VoidCallback onLoeschen;
  final ValueChanged<int> onVerschieben;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = Text(
      feld.label,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    final eingabe = FeldEingabe(feld: feld, onWert: onWert);
    final menue = PopupMenuButton<String>(
      tooltip: 'Feld',
      icon: const Icon(Icons.more_vert, size: 16),
      onSelected: (wahl) {
        switch (wahl) {
          case 'bearbeiten':
            onBearbeiten();
          case 'hoch':
            onVerschieben(-1);
          case 'runter':
            onVerschieben(1);
          case 'loeschen':
            onLoeschen();
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'bearbeiten', child: Text('Bearbeiten')),
        PopupMenuItem(
          value: 'hoch',
          enabled: !erster,
          child: const Text('Nach oben'),
        ),
        PopupMenuItem(
          value: 'runter',
          enabled: !letzter,
          child: const Text('Nach unten'),
        ),
        const PopupMenuItem(value: 'loeschen', child: Text('Löschen')),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: breit
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 240,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10, right: 12),
                    child: label,
                  ),
                ),
                Expanded(child: eingabe),
                menue,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [label, const SizedBox(height: 4), eingabe],
                  ),
                ),
                menue,
              ],
            ),
    );
  }
}

/// Die Eingabe eines Felds je nach Typ.
class FeldEingabe extends StatefulWidget {
  const FeldEingabe({super.key, required this.feld, required this.onWert});

  final ProzessFeld feld;
  final ValueChanged<String> onWert;

  @override
  State<FeldEingabe> createState() => _FeldEingabeState();
}

class _FeldEingabeState extends State<FeldEingabe> {
  late final TextEditingController _text =
      TextEditingController(text: widget.feld.wert);

  @override
  void didUpdateWidget(FeldEingabe alt) {
    super.didUpdateWidget(alt);
    // Von außen geändert (Verwerfen, Vorlage) — sonst bleibt die Eingabe.
    if (widget.feld.wert != _text.text) _text.text = widget.feld.wert;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.feld;
    if (f.typ == FeldTyp.auswahl && f.optionen.isNotEmpty) {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final o in f.optionen)
            ChoiceChip(
              label: Text(o),
              selected: f.wert == o,
              // Ein zweiter Klick nimmt die Wahl wieder weg.
              onSelected: (_) => widget.onWert(f.wert == o ? '' : o),
            ),
        ],
      );
    }
    final lang = f.typ == FeldTyp.langtext;
    return TextField(
      controller: _text,
      minLines: lang ? 2 : 1,
      maxLines: lang ? 6 : 1,
      keyboardType: f.typ == FeldTyp.zahl
          ? const TextInputType.numberWithOptions(decimal: true)
          : null,
      decoration: const InputDecoration(isDense: true),
      onChanged: widget.onWert,
    );
  }
}

/// Ein Feld anlegen oder ändern: Bezeichnung, Typ, Möglichkeiten.
class FeldDialog extends StatefulWidget {
  const FeldDialog({super.key, this.feld, this.vorhandeneIds = const []});

  /// null: ein neues Feld.
  final ProzessFeld? feld;

  /// IDs der Felder im Abschnitt — eine neue ID weicht ihnen aus.
  final List<String> vorhandeneIds;

  @override
  State<FeldDialog> createState() => _FeldDialogState();
}

class _FeldDialogState extends State<FeldDialog> {
  late final TextEditingController _label =
      TextEditingController(text: widget.feld?.label ?? '');
  late final TextEditingController _optionen =
      TextEditingController(text: widget.feld?.optionen.join(', ') ?? '');
  late FeldTyp _typ = widget.feld?.typ ?? FeldTyp.text;

  @override
  void dispose() {
    _label.dispose();
    _optionen.dispose();
    super.dispose();
  }

  static const Map<FeldTyp, String> _typen = {
    FeldTyp.text: 'Text',
    FeldTyp.langtext: 'Langer Text',
    FeldTyp.zahl: 'Zahl',
    FeldTyp.auswahl: 'Auswahl',
  };

  void _fertig() {
    final label = _label.text.trim();
    if (label.isEmpty) return;
    final alt = widget.feld;
    final optionen = _typ == FeldTyp.auswahl
        ? [
            for (final o in _optionen.text.split(RegExp('[,;\n]')))
              if (o.trim().isNotEmpty) o.trim(),
          ]
        : const <String>[];
    Navigator.of(context).pop(
      ProzessFeld(
        id: alt?.id ?? neueParameterId(label, widget.vorhandeneIds),
        label: label,
        wert: alt?.wert ?? '',
        typ: _typ,
        optionen: optionen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.feld == null ? 'Neues Feld' : 'Feld bearbeiten'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, minWidth: 340),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _label,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Bezeichnung'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final MapEntry(:key, :value) in _typen.entries)
                  ChoiceChip(
                    label: Text(value),
                    selected: _typ == key,
                    onSelected: (_) => setState(() => _typ = key),
                  ),
              ],
            ),
            if (_typ == FeldTyp.auswahl) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _optionen,
                decoration: const InputDecoration(
                  labelText: 'Möglichkeiten',
                  helperText: 'Durch Komma getrennt, etwa „Vakuum, offen"',
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(onPressed: _fertig, child: const Text('Übernehmen')),
      ],
    );
  }
}

/// Zwei Stände der Prozessparameter nebeneinander: was sich geändert hat.
class ParameterVergleichDialog extends StatefulWidget {
  const ParameterVergleichDialog({super.key, required this.staende});

  /// Älteste zuerst.
  final List<({String label, Prozessparameter parameter})> staende;

  @override
  State<ParameterVergleichDialog> createState() =>
      _ParameterVergleichDialogState();
}

class _ParameterVergleichDialogState extends State<ParameterVergleichDialog> {
  late int _a = widget.staende.length - 2;
  late int _b = widget.staende.length - 1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final liste = widget.staende;
    final aenderungen = vergleicheParameter(
      liste[_a].parameter,
      liste[_b].parameter,
    );
    DropdownButton<int> wahl(int wert, ValueChanged<int> onWahl) =>
        DropdownButton<int>(
          value: wert,
          isExpanded: true,
          items: [
            for (final (i, s) in liste.indexed)
              DropdownMenuItem(
                value: i,
                child: Text(s.label, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (i) {
            if (i != null) setState(() => onWahl(i));
          },
        );
    return AlertDialog(
      title: const Text('Versionen vergleichen'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, minWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: wahl(_a, (i) => _a = i)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward, size: 18),
                ),
                Expanded(child: wahl(_b, (i) => _b = i)),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: aenderungen.isEmpty
                  ? const LeerHinweis('Keine Unterschiede.')
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final a in aenderungen)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${a.abschnitt} · ${a.feld}',
                                  style: theme.textTheme.labelMedium,
                                ),
                                Text(
                                  '${a.alt == null || a.alt!.trim().isEmpty ? '—' : a.alt}'
                                  '  →  '
                                  '${a.neu == null || a.neu!.trim().isEmpty ? '—' : a.neu}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Schließen'),
        ),
      ],
    );
  }
}

/// Ein Text in einem kleinen Fenster — für Namen und Notizen.
class TextEingabeDialog extends StatefulWidget {
  const TextEingabeDialog({
    super.key,
    required this.titel,
    required this.label,
    this.wert = '',
    this.mehrzeilig = false,
    this.bestaetigen = 'Speichern',
    this.leerErlaubt = false,
  });

  final String titel;
  final String label;
  final String wert;
  final bool mehrzeilig;
  final String bestaetigen;

  /// Darf leer bestätigt werden (etwa eine Notiz)?
  final bool leerErlaubt;

  @override
  State<TextEingabeDialog> createState() => _TextEingabeDialogState();
}

class _TextEingabeDialogState extends State<TextEingabeDialog> {
  late final TextEditingController _text =
      TextEditingController(text: widget.wert);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _fertig() {
    if (!widget.leerErlaubt && _text.text.trim().isEmpty) return;
    Navigator.of(context).pop(_text.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titel),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, minWidth: 320),
        child: TextField(
          controller: _text,
          autofocus: true,
          minLines: widget.mehrzeilig ? 3 : 1,
          maxLines: widget.mehrzeilig ? 6 : 1,
          decoration: InputDecoration(labelText: widget.label),
          onSubmitted: widget.mehrzeilig ? null : (_) => _fertig(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(onPressed: _fertig, child: Text(widget.bestaetigen)),
      ],
    );
  }
}
