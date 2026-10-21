import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/services/auto_backup_trigger.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/fehler_text.dart';
import '../daten/entwicklung_repository.dart';
import '../freigabe/freigabe.dart' show FreigabeStand;
import '../projekte/datei_aktionen.dart' show groesseText;
import 'beispielvorlage.dart';
import 'spezifikation_dienst.dart';
import 'spezifikation_werte.dart';

// Das Fenster „Spezifikation erstellen": Rezepturstand und Sprache wählen,
// die eigene Excel-Vorlage hinterlegen, für Englisch auf Wunsch mit DeepL
// übersetzen — dann wird die gefüllte Mappe gespeichert.

/// Öffnet das Fenster für [projekt].
Future<void> spezifikationOeffnen(
  BuildContext context,
  EntwicklungsProjekt projekt,
) =>
    showDialog<void>(
      context: context,
      builder: (_) => SpezifikationDialog(projekt: projekt),
    );

/// Hängt [endung] an, wenn der Speichern-Dialog es nicht tat.
String mitEndung(String pfad, String endung) =>
    pfad.toLowerCase().endsWith(endung.toLowerCase()) ? pfad : '$pfad$endung';

/// Ein Stand für die Auswahl: Rezeptur, Nummer und ob er freigegeben oder
/// noch ein Entwurf ist.
String spezStandLabel(FreigabeStand s, {String? freigegebeneVersionId}) {
  final v = s.version;
  return [
    s.label,
    if (v.id == freigegebeneVersionId)
      'freigegeben'
    else if (v.status != VersionStatus.abgeschlossen)
      'Entwurf',
  ].join(' · ');
}

/// Der Stand, der vorgeschlagen wird: der freigegebene, sonst der erste
/// der Liste — der neueste abgeschlossene.
String? spezStandVorschlag(
  List<FreigabeStand> staende,
  String? freigegebeneVersionId,
) {
  if (staende.isEmpty) return null;
  if (freigegebeneVersionId != null &&
      staende.any((s) => s.version.id == freigegebeneVersionId)) {
    return freigegebeneVersionId;
  }
  return staende.first.version.id;
}

class SpezifikationDialog extends ConsumerStatefulWidget {
  const SpezifikationDialog({super.key, required this.projekt});

  final EntwicklungsProjekt projekt;

  @override
  ConsumerState<SpezifikationDialog> createState() =>
      _SpezifikationDialogState();
}

class _SpezifikationDialogState extends ConsumerState<SpezifikationDialog> {
  String? _versionId;
  SpezSprache _sprache = SpezSprache.de;
  bool _uebersetzen = true;
  bool _ablegen = true;
  bool _laeuft = false;
  String? _meldung;
  StatusArt _meldungArt = StatusArt.info;

  SpezifikationDienst get _dienst => ref.read(spezifikationDienstProvider);

  void _melde(String text, [StatusArt art = StatusArt.info]) {
    if (!mounted) return;
    setState(() {
      _meldung = text;
      _meldungArt = art;
    });
  }

  void _sicherungAnstossen(String grund) =>
      ref.read(autoBackupTriggerProvider).fireDebounced(reason: grund);

  Future<void> _vorlageWaehlen() async {
    final sprache = _sprache;
    final gewaehlt = await FilePicker.pickFiles(
      dialogTitle: 'Vorlage für ${sprache.label} wählen',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (gewaehlt == null || gewaehlt.files.isEmpty) return;
    final datei = gewaehlt.files.first;
    try {
      var bytes = datei.bytes;
      final pfad = datei.path;
      if (bytes == null && pfad != null) {
        bytes = await File(pfad).readAsBytes();
      }
      if (bytes == null) {
        _melde('Die gewählte Datei ließ sich nicht lesen.', StatusArt.fehler);
        return;
      }
      final platzhalter =
          await _dienst.vorlageSpeichern(sprache, datei.name, bytes);
      ref.invalidate(spezVorlageProvider(sprache));
      _sicherungAnstossen('Spezifikationsvorlage');
      final bekannt = {for (final p in kSpezifikationPlatzhalter) p.name};
      final unbekannt = platzhalter.difference(bekannt).toList()..sort();
      if (platzhalter.isEmpty) {
        _melde(
          'Die Vorlage für ${sprache.label} ist gespeichert, enthält aber '
          'keine Platzhalter — es würde nichts gefüllt. Schreib in die '
          'Zellen Platzhalter wie {{artikelnummer}}; die Beispielvorlage '
          'zeigt alle.',
          StatusArt.warnung,
        );
      } else if (unbekannt.isNotEmpty) {
        _melde(
          'Die Vorlage für ${sprache.label} ist gespeichert: '
          '${platzhalter.length - unbekannt.length} Platzhalter erkannt. '
          'Diese kennt die App nicht (Tippfehler?): '
          '${unbekannt.map((n) => '{{$n}}').join(', ')}',
          StatusArt.warnung,
        );
      } else {
        _melde(
          'Die Vorlage für ${sprache.label} ist gespeichert: '
          '${platzhalter.length} Platzhalter erkannt.',
          StatusArt.ok,
        );
      }
    } on FormatException catch (e) {
      _melde(e.message, StatusArt.fehler);
    } catch (e) {
      _melde(
        'Die Vorlage ließ sich nicht speichern: ${fehlerText(e)}',
        StatusArt.fehler,
      );
    }
  }

  Future<void> _vorlageEntfernen() async {
    final sprache = _sprache;
    final ja = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vorlage entfernen?'),
        content: Text(
          'Die Vorlage für ${sprache.label} wird aus der App entfernt. Die '
          'Datei auf deinem Rechner bleibt, wo sie ist.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Entfernen'),
          ),
        ],
      ),
    );
    if (ja != true) return;
    try {
      await _dienst.vorlageLoeschen(sprache);
      ref.invalidate(spezVorlageProvider(sprache));
      _sicherungAnstossen('Spezifikationsvorlage');
      _melde('Die Vorlage für ${sprache.label} ist entfernt.');
    } catch (e) {
      _melde(
        'Die Vorlage ließ sich nicht entfernen: ${fehlerText(e)}',
        StatusArt.fehler,
      );
    }
  }

  Future<void> _beispielSpeichern() async {
    try {
      final pfad = await FilePicker.saveFile(
        dialogTitle: 'Beispielvorlage speichern',
        fileName: 'Spezifikation_Beispielvorlage.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (pfad == null) return;
      final ziel = mitEndung(pfad, '.xlsx');
      await File(ziel).writeAsBytes(beispielvorlage(), flush: true);
      _melde(
        'Beispielvorlage gespeichert: $ziel\nSie zeigt jeden Platzhalter an '
        'einer Stelle — übertrage die, die du brauchst, in eure eigene '
        'Spezifikation und wähle diese dann als Vorlage.',
        StatusArt.ok,
      );
    } catch (e) {
      _melde(
        'Die Beispielvorlage ließ sich nicht speichern: ${fehlerText(e)}',
        StatusArt.fehler,
      );
    }
  }

  Future<void> _schluesselEingeben(bool hinterlegt) async {
    final eingabe = await showDialog<String>(
      context: context,
      builder: (_) => DeeplSchluesselDialog(hinterlegt: hinterlegt),
    );
    if (eingabe == null || !mounted) return;
    try {
      await _dienst.deeplSpeichern(eingabe);
      ref.invalidate(deeplHinterlegtProvider);
      if (!mounted) return;
      if (eingabe.trim().isNotEmpty) setState(() => _uebersetzen = true);
      _melde(
        eingabe.trim().isEmpty
            ? 'Der DeepL-Schlüssel ist entfernt.'
            : 'Der DeepL-Schlüssel ist auf diesem Rechner hinterlegt.',
        StatusArt.ok,
      );
    } catch (e) {
      _melde(
        'Der Schlüssel ließ sich nicht speichern: ${fehlerText(e)}',
        StatusArt.fehler,
      );
    }
  }

  Future<void> _erstellen() async {
    final staende =
        ref.read(spezStaendeProvider(widget.projekt.id)).valueOrNull ??
            const <FreigabeStand>[];
    final versionId = _versionId ??
        spezStandVorschlag(staende, widget.projekt.freigabeVersionId);
    if (versionId == null) return;
    final sprache = _sprache;
    final ablegen = _ablegen;
    final hinterlegt = ref.read(deeplHinterlegtProvider).valueOrNull ?? false;
    setState(() {
      _laeuft = true;
      _meldung = null;
    });
    try {
      final e = await _dienst.erstellen(
        projekt: widget.projekt,
        versionId: versionId,
        sprache: sprache,
        uebersetzen: _uebersetzen && hinterlegt,
      );
      final pfad = await FilePicker.saveFile(
        dialogTitle: 'Spezifikation (${sprache.label}) speichern',
        fileName: e.dateiname,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (pfad == null) {
        if (mounted) setState(() => _laeuft = false);
        return;
      }
      final ziel = mitEndung(pfad, '.xlsx');
      await File(ziel).writeAsBytes(e.bytes, flush: true);
      if (ablegen) {
        await _dienst.ablegen(
          projekt: widget.projekt,
          versionId: versionId,
          sprache: sprache,
          ergebnis: e,
        );
      }
      await _dienst.abhaken(widget.projekt.id);
      _sicherungAnstossen('Spezifikation');
      final hinweise = [
        'Gespeichert: $ziel',
        '${e.ersetzt} Platzhalter gefüllt.',
        if (e.uebersetzt)
          'Die Texte sind mit DeepL übersetzt — bitte prüfen, besonders die '
              'Zutatenliste mit den hervorgehobenen Allergenen.',
        if (e.uebersetzungsFehler case final fehler?) fehler,
        if (sprache == SpezSprache.en && !hinterlegt)
          'Ohne DeepL-Schlüssel sind die Texte deutsch geblieben.',
        if (e.unbekannt.isNotEmpty)
          'Diese Platzhalter kennt die App nicht, sie stehen noch in der '
              'Mappe: ${(e.unbekannt.toList()..sort()).map((n) => '{{$n}}').join(', ')}',
        if (ablegen) 'Bei den Projektdateien abgelegt und im Verlauf vermerkt.',
        '„Spezifikation erstellt" ist in der Checkliste abgehakt.',
      ];
      if (!mounted) return;
      setState(() {
        _laeuft = false;
        _meldung = hinweise.join('\n');
        _meldungArt = e.unbekannt.isEmpty && e.uebersetzungsFehler == null
            ? StatusArt.ok
            : StatusArt.warnung;
      });
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() {
        _laeuft = false;
        _meldung = e.message;
        _meldungArt = StatusArt.fehler;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _laeuft = false;
        _meldung = 'Die Spezifikation ließ sich nicht erstellen: '
            '${fehlerText(e)}';
        _meldungArt = StatusArt.fehler;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final freigegeben = widget.projekt.freigabeVersionId;
    final staende = ref.watch(spezStaendeProvider(widget.projekt.id));
    final vorlage = ref.watch(spezVorlageProvider(_sprache));
    final hinterlegt = ref.watch(deeplHinterlegtProvider).valueOrNull ?? false;
    final alle = staende.valueOrNull ?? const <FreigabeStand>[];
    final versionId = _versionId ?? spezStandVorschlag(alle, freigegeben);
    final kann =
        !_laeuft && versionId != null && vorlage.valueOrNull != null;
    final meldung = _meldung;

    return AlertDialog(
      icon: const Icon(Icons.table_view_outlined),
      title: const Text('Spezifikation erstellen'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              staende.when(
                skipLoadingOnReload: true,
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => HinweisBox(
                  fehlerText(e),
                  art: StatusArt.fehler,
                  titel: 'Die Rezepturstände ließen sich nicht laden',
                  auswaehlbar: true,
                ),
                data: (liste) => liste.isEmpty
                    ? const HinweisBox(
                        'Das Projekt hat noch keine Rezeptur. Leg auf der '
                        'Übersicht eine an oder ordne eine zu.',
                        art: StatusArt.warnung,
                      )
                    : DropdownButtonFormField<String>(
                        initialValue: versionId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Rezepturstand',
                        ),
                        items: [
                          for (final s in liste)
                            DropdownMenuItem(
                              value: s.version.id,
                              child: Text(
                                spezStandLabel(
                                  s,
                                  freigegebeneVersionId: freigegeben,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _laeuft
                            ? null
                            : (id) => setState(() => _versionId = id),
                      ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('Sprache', style: theme.textTheme.bodyMedium),
                  const SizedBox(width: 16),
                  SegmentedButton<SpezSprache>(
                    segments: [
                      for (final s in SpezSprache.values)
                        ButtonSegment(value: s, label: Text(s.label)),
                    ],
                    selected: {_sprache},
                    onSelectionChanged: _laeuft
                        ? null
                        : (auswahl) => setState(() {
                              _sprache = auswahl.first;
                              _meldung = null;
                            }),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Vorlage (${_sprache.label})',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              vorlage.when(
                skipLoadingOnReload: true,
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => HinweisBox(
                  fehlerText(e),
                  art: StatusArt.fehler,
                  auswaehlbar: true,
                ),
                data: (d) => Row(
                  children: [
                    Icon(
                      d == null
                          ? Icons.upload_file_outlined
                          : Icons.description_outlined,
                      size: 20,
                      color: grau,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        d == null
                            ? 'Noch keine Vorlage für ${_sprache.label} '
                                'gewählt.'
                            : '${d.name} · ${groesseText(d.groesse)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: d == null ? grau : null,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _laeuft ? null : _vorlageWaehlen,
                      child: Text(d == null ? 'Vorlage wählen…' : 'Ersetzen…'),
                    ),
                    if (d != null)
                      IconButton(
                        tooltip: 'Vorlage entfernen',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _laeuft ? null : _vorlageEntfernen,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              const HinweisBox(
                'Die Vorlage ist eure eigene Spezifikation als Excel-Mappe. '
                'In die Zellen, die gefüllt werden sollen, kommen Platzhalter '
                'wie {{artikelnummer}} oder {{naehrwert.fett}} — alle stehen '
                'unten und in der Beispielvorlage. Formatierung, Logo und '
                'Aufbau bleiben, wie sie sind. Die Vorlage liegt '
                'verschlüsselt bei der Produktentwicklung und wandert mit '
                'ins Backup.',
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _laeuft ? null : _beispielSpeichern,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Beispielvorlage speichern…'),
                ),
              ),
              if (_sprache == SpezSprache.en) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: hinterlegt && _uebersetzen,
                        onChanged: !hinterlegt || _laeuft
                            ? null
                            : (v) => setState(() => _uebersetzen = v),
                        title: const Text('Texte mit DeepL übersetzen'),
                        subtitle: Text(
                          hinterlegt
                              ? 'Bezeichnung, Zutatenliste, Sensorik und '
                                  'Hilfsstoffe. Zahlen, Daten und Allergen-'
                                  'namen schreibt die App selbst englisch.'
                              : 'Ohne DeepL-Schlüssel bleiben die Texte '
                                  'deutsch; Zahlen, Daten und Allergennamen '
                                  'sind trotzdem englisch.',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed:
                          _laeuft ? null : () => _schluesselEingeben(hinterlegt),
                      icon: const Icon(Icons.key_outlined, size: 18),
                      label: Text(
                        hinterlegt ? 'Schlüssel ändern…' : 'Schlüssel eingeben…',
                      ),
                    ),
                  ],
                ),
              ],
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _ablegen,
                onChanged: _laeuft
                    ? null
                    : (v) => setState(() => _ablegen = v ?? true),
                title: const Text('Auch bei den Projektdateien ablegen'),
                subtitle: const Text(
                  'Mit dem Rezepturstand im Verlauf — so bleibt nachvollziehbar, '
                  'welche Spezifikation verschickt wurde.',
                ),
              ),
              PlatzhalterListe(
                onKopiert: (name) => _melde('{{$name}} ist kopiert.'),
              ),
              if (meldung != null) ...[
                const SizedBox(height: 12),
                HinweisBox(
                  meldung,
                  art: _meldungArt,
                  auswaehlbar: true,
                  onSchliessen: () => setState(() => _meldung = null),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _laeuft ? null : () => Navigator.of(context).pop(),
          child: const Text('Schließen'),
        ),
        FilledButton.icon(
          onPressed: kann ? _erstellen : null,
          icon: _laeuft
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_outlined, size: 18),
          label: const Text('Erstellen…'),
        ),
      ],
    );
  }
}

/// Alle Platzhalter zum Nachschlagen; ein Klick kopiert einen.
class PlatzhalterListe extends StatelessWidget {
  const PlatzhalterListe({super.key, this.onKopiert});

  /// Meldet den kopierten Platzhalter (ohne Klammern).
  final ValueChanged<String>? onKopiert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final klein = theme.textTheme.bodySmall;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      title: const Text('Alle Platzhalter'),
      subtitle: Text(
        '${kSpezifikationPlatzhalter.length} Stück — ein Klick kopiert einen',
        style: klein?.copyWith(color: grau),
      ),
      children: [
        for (final p in kSpezifikationPlatzhalter)
          InkWell(
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: '{{${p.name}}}'));
              onKopiert?.call(p.name);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 260,
                    child: Text(
                      '{{${p.name}}}',
                      style: klein?.copyWith(fontFamily: 'monospace'),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      p.erklaerung,
                      style: klein?.copyWith(color: grau),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Fragt den DeepL-Schlüssel ab. Gibt den neuen Schlüssel zurück, einen
/// leeren Text zum Entfernen oder null bei Abbruch.
class DeeplSchluesselDialog extends StatefulWidget {
  const DeeplSchluesselDialog({super.key, required this.hinterlegt});

  final bool hinterlegt;

  @override
  State<DeeplSchluesselDialog> createState() => _DeeplSchluesselDialogState();
}

class _DeeplSchluesselDialogState extends State<DeeplSchluesselDialog> {
  final _feld = TextEditingController();
  bool _zeigen = false;

  @override
  void dispose() {
    _feld.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.translate),
      title: const Text('DeepL-Schlüssel'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _feld,
              autofocus: true,
              obscureText: !_zeigen,
              decoration: InputDecoration(
                labelText: widget.hinterlegt
                    ? 'Neuer Schlüssel'
                    : 'Schlüssel der DeepL-API',
                suffixIcon: IconButton(
                  tooltip: _zeigen ? 'Verbergen' : 'Zeigen',
                  icon: Icon(
                    _zeigen
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () => setState(() => _zeigen = !_zeigen),
                ),
              ),
              onSubmitted: (t) {
                if (t.trim().isNotEmpty) Navigator.of(context).pop(t.trim());
              },
            ),
            const SizedBox(height: 12),
            const HinweisBox(
              'Den Schlüssel gibt es im eigenen DeepL-Konto unter „API-'
              'Schlüssel"; Schlüssel des kostenlosen Zugangs enden auf „:fx". '
              'Er bleibt auf diesem Rechner: Kein Backup nimmt ihn mit. '
              'Übersetzt werden nur die Texte der Spezifikation.',
            ),
          ],
        ),
      ),
      actions: [
        if (widget.hinterlegt)
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: const Text('Entfernen'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        ListenableBuilder(
          listenable: _feld,
          builder: (context, _) => FilledButton(
            onPressed: _feld.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop(_feld.text.trim()),
            child: const Text('Speichern'),
          ),
        ),
      ],
    );
  }
}
