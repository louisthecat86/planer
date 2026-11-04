import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/services/auto_backup_trigger.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/fehler_text.dart';
import '../spezifikation/spezifikation_dialog.dart' show mitEndung;
import 'zutaten_excel.dart';

// Die Zutaten als Excel: speichern — und einlesen, erst nach einer
// Vorschau, in der Konflikte je Zutat entschieden werden.

/// Lesen und Schreiben für den Import — im Test ersetzbar.
abstract class ZutatenImportDienst {
  /// Liest die Mappe und vergleicht sie mit der App. Wirft eine
  /// [FormatException], wenn die Datei keine Zutatenliste ist.
  Future<ZutatenAbgleich> abgleichen(Uint8List bytes);

  /// Schreibt den Abgleich — von den Konflikten die Zeilen in
  /// [dateiGewinnt].
  Future<({int neu, int geaendert})> uebernehmen(
    ZutatenAbgleich abgleich,
    Set<int> dateiGewinnt,
  );
}

/// Der Import in die Datenbank der App.
class DbZutatenImportDienst implements ZutatenImportDienst {
  DbZutatenImportDienst(this._db);

  final AppDatabase _db;

  @override
  Future<ZutatenAbgleich> abgleichen(Uint8List bytes) async {
    final datei = await _lesenImHintergrund(bytes);
    final alle = await _db.select(_db.entwicklungZutaten).get();
    return zutatenAbgleichen(datei, alle);
  }

  @override
  Future<({int neu, int geaendert})> uebernehmen(
    ZutatenAbgleich abgleich,
    Set<int> dateiGewinnt,
  ) =>
      zutatenUebernehmen(_db, abgleich, dateiGewinnt: dateiGewinnt);
}

final zutatenImportDienstProvider = Provider<ZutatenImportDienst>(
  (ref) => DbZutatenImportDienst(ref.watch(databaseProvider)),
);

// Lesen und Schreiben der Mappe auf einem eigenen Isolate: Bei tausend
// Zutaten dauert jedes eine halbe Sekunde, und das Fenster soll so lange
// nicht stehen. Eigene Funktionen, damit die Isolate-Aufgabe nur die Daten
// mitnimmt und nicht etwa den BuildContext.
Future<ZutatenDatei> _lesenImHintergrund(Uint8List bytes) =>
    Isolate.run(() => zutatenDateiLesen(bytes));

Future<Uint8List> _mappeImHintergrund(List<Zutat> zutaten, DateTime stand) =>
    Isolate.run(() => zutatenMappe(zutaten, stand: stand));

String _nachricht(Object e) => e is FileSystemException
    ? '${fehlerText(e)} Ist die Datei gerade in Excel geöffnet?'
    : fehlerText(e);

/// Speichert [zutaten] als Excel-Mappe; wohin, fragt der Speichern-Dialog.
/// Ohne Zutaten entsteht eine leere Vorlage.
Future<void> zutatenExportieren(
  BuildContext context,
  List<Zutat> zutaten,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final jetzt = DateTime.now();
    final pfad = await FilePicker.saveFile(
      dialogTitle: zutaten.isEmpty
          ? 'Leere Excel-Vorlage speichern'
          : 'Zutaten als Excel speichern',
      fileName: zutatenDateiname(jetzt),
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (pfad == null) return;
    final ziel = mitEndung(pfad, '.xlsx');
    final bytes = await _mappeImHintergrund(zutaten, jetzt);
    await File(ziel).writeAsBytes(bytes, flush: true);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          zutaten.isEmpty
              ? 'Vorlage gespeichert: $ziel'
              : '${zutaten.length} '
                  '${zutaten.length == 1 ? 'Zutat' : 'Zutaten'} '
                  'gespeichert: $ziel',
        ),
      ),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(
          'Die Zutaten ließen sich nicht als Excel speichern. '
          '(${_nachricht(e)})',
        ),
      ),
    );
  }
}

/// Wählt eine Excel-Datei und öffnet die Vorschau des Imports.
Future<void> zutatenImportStarten(BuildContext context) async {
  final gewaehlt = await FilePicker.pickFiles(
    dialogTitle: 'Excel-Datei mit Zutaten wählen',
    type: FileType.custom,
    allowedExtensions: ['xlsx'],
    withData: true,
  );
  if (gewaehlt == null || gewaehlt.files.isEmpty || !context.mounted) return;
  final datei = gewaehlt.files.first;
  var bytes = datei.bytes;
  final pfad = datei.path;
  // Füllt eine Plattform die Bytes trotz withData nicht, wird die Datei
  // selbst gelesen.
  if (bytes == null && pfad != null) {
    try {
      bytes = await File(pfad).readAsBytes();
    } on FileSystemException {
      bytes = null;
    }
    if (!context.mounted) return;
  }
  final inhalt = bytes;
  if (inhalt == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Die gewählte Datei ließ sich nicht lesen. Ist sie gerade in '
          'Excel geöffnet?',
        ),
      ),
    );
    return;
  }
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ZutatenImportDialog(bytes: inhalt, dateiname: datei.name),
  );
}

enum _Phase { lesen, vorschau, schreiben, fertig, fehler }

/// Zeigt, was der Import ändern würde, lässt bei Konflikten je Zutat
/// wählen und übernimmt nach Bestätigung.
class ZutatenImportDialog extends ConsumerStatefulWidget {
  const ZutatenImportDialog({
    super.key,
    required this.bytes,
    required this.dateiname,
  });

  final Uint8List bytes;
  final String dateiname;

  @override
  ConsumerState<ZutatenImportDialog> createState() =>
      _ZutatenImportDialogState();
}

class _ZutatenImportDialogState extends ConsumerState<ZutatenImportDialog> {
  _Phase _phase = _Phase.lesen;
  ZutatenAbgleich? _abgleich;

  /// Die Zeilen der Konflikte, bei denen die Datei gewinnt.
  final Set<int> _dateiGewinnt = {};
  ({int neu, int geaendert})? _ergebnis;
  String _fehler = '';
  String _fehlerTitel = '';

  @override
  void initState() {
    super.initState();
    _lesen();
  }

  void _scheitern(Object e, String titel) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.fehler;
      _fehler = fehlerText(e);
      _fehlerTitel = titel;
    });
  }

  Future<void> _lesen() async {
    try {
      final a = await ref
          .read(zutatenImportDienstProvider)
          .abgleichen(widget.bytes);
      if (!mounted) return;
      setState(() {
        _abgleich = a;
        _phase = _Phase.vorschau;
      });
    } catch (e) {
      _scheitern(e, 'Die Datei ließ sich nicht einlesen');
    }
  }

  Future<void> _uebernehmen() async {
    final a = _abgleich;
    if (a == null) return;
    final sicherung = ref.read(autoBackupTriggerProvider);
    setState(() => _phase = _Phase.schreiben);
    try {
      final e = await ref
          .read(zutatenImportDienstProvider)
          .uebernehmen(a, {..._dateiGewinnt});
      sicherung.fireDebounced(reason: 'Zutaten aus Excel');
      if (!mounted) return;
      setState(() {
        _ergebnis = e;
        _phase = _Phase.fertig;
      });
    } catch (e) {
      _scheitern(
        e,
        'Nicht übernommen — in der App hat sich nichts geändert',
      );
    }
  }

  /// Wie viele Zutaten das Übernehmen anlegt oder ändert.
  int _anzahl(ZutatenAbgleich a) =>
      a.neu.length + a.geaendert.length + _dateiGewinnt.length;

  void _alle(ZutatenAbgleich a, {required bool datei}) => setState(() {
        _dateiGewinnt.clear();
        if (datei) _dateiGewinnt.addAll(a.konflikte.map((k) => k.zeile));
      });

  @override
  Widget build(BuildContext context) {
    final a = _abgleich;
    return AlertDialog(
      icon: const Icon(Icons.table_view_outlined),
      title: const Text('Zutaten aus Excel'),
      // Die Vorschau mit fester Breite: AlertDialog misst seinen Inhalt mit
      // IntrinsicWidth, und das können Aufklapplisten und Umschalter nicht.
      content: _phase == _Phase.vorschau && a != null
          ? SizedBox(
              width: 640,
              child: _Vorschau(
                abgleich: a,
                dateiname: widget.dateiname,
                dateiGewinnt: _dateiGewinnt,
                onWahl: (zeile, datei) => setState(() {
                  if (datei) {
                    _dateiGewinnt.add(zeile);
                  } else {
                    _dateiGewinnt.remove(zeile);
                  }
                }),
                onAlle: (datei) => _alle(a, datei: datei),
              ),
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560, minWidth: 380),
              child: switch (_phase) {
                _Phase.lesen || _Phase.vorschau =>
                  _Laeuft('„${widget.dateiname}" wird gelesen …'),
                _Phase.schreiben => const _Laeuft('Wird übernommen …'),
                _Phase.fehler => HinweisBox(
                    _fehler,
                    art: StatusArt.fehler,
                    titel: _fehlerTitel,
                    auswaehlbar: true,
                  ),
                _Phase.fertig => _Fertig(ergebnis: _ergebnis),
              },
            ),
      actions: switch (_phase) {
        _Phase.lesen || _Phase.schreiben => const [],
        _Phase.fehler || _Phase.fertig => [
            FilledButton(
              key: const ValueKey('zutaten-import-schliessen'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Schließen'),
            ),
          ],
        _Phase.vorschau => [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                a == null || !a.hatAenderungen ? 'Schließen' : 'Abbrechen',
              ),
            ),
            if (a != null && a.hatAenderungen)
              FilledButton.icon(
                key: const ValueKey('zutaten-import-uebernehmen'),
                onPressed: _anzahl(a) == 0 ? null : _uebernehmen,
                icon: const Icon(Icons.check, size: 18),
                label: Text(
                  _anzahl(a) == 0 ? 'Übernehmen' : 'Übernehmen (${_anzahl(a)})',
                ),
              ),
          ],
      },
    );
  }
}

class _Laeuft extends StatelessWidget {
  const _Laeuft(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _Fertig extends StatelessWidget {
  const _Fertig({required this.ergebnis});

  final ({int neu, int geaendert})? ergebnis;

  @override
  Widget build(BuildContext context) {
    final e = ergebnis ?? (neu: 0, geaendert: 0);
    String zutaten(int n) => n == 1 ? '1 Zutat' : '$n Zutaten';
    return HinweisBox(
      [
        if (e.neu > 0) '${zutaten(e.neu)} angelegt.',
        if (e.geaendert > 0) '${zutaten(e.geaendert)} geändert.',
        if (e.neu > 0)
          'Am besten jetzt neu exportieren — dann tragen auch die neuen '
              'Zutaten in der Datei ihre ID.',
      ].join(' '),
      art: StatusArt.ok,
      titel: 'Übernommen',
    );
  }
}

/// Was der Import ändern würde: Zahlen, Hinweise, Konflikte zum Wählen,
/// Änderungen, neue Zutaten und Zeilen mit Fehlern.
class _Vorschau extends StatelessWidget {
  const _Vorschau({
    required this.abgleich,
    required this.dateiname,
    required this.dateiGewinnt,
    required this.onWahl,
    required this.onAlle,
  });

  final ZutatenAbgleich abgleich;
  final String dateiname;
  final Set<int> dateiGewinnt;
  final void Function(int zeile, bool datei) onWahl;
  final ValueChanged<bool> onAlle;

  @override
  Widget build(BuildContext context) {
    final a = abgleich;
    final theme = Theme.of(context);
    final grau = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    String zeilen(int n) => n == 1 ? '1 Zeile' : '$n Zeilen';
    final fehlerZeilen = a.fehler.map((f) => f.zeile).toSet().length;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('„$dateiname"', style: grau),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (a.neu.isNotEmpty)
                StatusMarke('${a.neu.length} neu', art: StatusArt.ok),
              if (a.geaendert.isNotEmpty)
                StatusMarke(
                  '${a.geaendert.length} geändert',
                  art: StatusArt.info,
                ),
              if (a.konflikte.isNotEmpty)
                StatusMarke(
                  '${a.konflikte.length} '
                  '${a.konflikte.length == 1 ? 'Konflikt' : 'Konflikte'}',
                  art: StatusArt.warnung,
                ),
              StatusMarke('${a.unveraendert} unverändert'),
              if (a.inAppNeuer > 0)
                StatusMarke(
                  '${a.inAppNeuer} in der App neuer',
                  hinweis: 'In der Datei unverändert, in der App seit dem '
                      'Export geändert — sie bleiben, wie die App sie hat.',
                ),
              if (a.fehler.isNotEmpty)
                StatusMarke(
                  '${zeilen(fehlerZeilen)} mit Fehlern',
                  art: StatusArt.fehler,
                ),
            ],
          ),
          if (!a.hatAenderungen) ...[
            const SizedBox(height: 4),
            const LeerHinweis(
              'Nichts zu übernehmen — die Datei passt zur App.',
              icon: Icons.check_circle_outline,
            ),
          ],
          for (final h in a.hinweise) ...[
            const SizedBox(height: 8),
            HinweisBox(h),
          ],
          if (a.konflikte.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Konflikte — welche Seite gilt?',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                TextButton(
                  key: const ValueKey('zutaten-import-alle-app'),
                  onPressed: () => onAlle(false),
                  child: const Text('Alle: App'),
                ),
                TextButton(
                  key: const ValueKey('zutaten-import-alle-datei'),
                  onPressed: () => onAlle(true),
                  child: const Text('Alle: Datei'),
                ),
              ],
            ),
            for (final k in a.konflikte)
              _KonfliktKarte(
                vorschlag: k,
                dateiGewinnt: dateiGewinnt.contains(k.zeile),
                onWahl: (datei) => onWahl(k.zeile, datei),
              ),
          ],
          if (a.geaendert.isNotEmpty)
            _Abschnitt(
              titel: '${a.geaendert.length} geändert',
              offen: a.geaendert.length <= 5,
              kinder: [
                for (final v in a.geaendert) _Aenderung(vorschlag: v),
              ],
            ),
          if (a.neu.isNotEmpty)
            _Abschnitt(
              titel: '${a.neu.length} neu',
              offen: a.neu.length <= 5,
              kinder: [
                for (final v in a.neu)
                  _Zeile(
                    titel: v.name,
                    unten: [
                      'Zeile ${v.zeile}',
                      if (v.hinweis case final h?) h,
                    ].join(' · '),
                  ),
              ],
            ),
          if (a.fehler.isNotEmpty)
            _Abschnitt(
              titel: 'Nicht übernommen: ${zeilen(fehlerZeilen)}',
              offen: true,
              kinder: [
                for (final f in a.fehler)
                  _Zeile(titel: 'Zeile ${f.zeile}', unten: f.text),
              ],
            ),
        ],
      ),
    );
  }
}

class _Abschnitt extends StatelessWidget {
  const _Abschnitt({
    required this.titel,
    required this.offen,
    required this.kinder,
  });

  final String titel;
  final bool offen;
  final List<Widget> kinder;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(titel, style: Theme.of(context).textTheme.titleSmall),
      initiallyExpanded: offen,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      shape: const Border(),
      collapsedShape: const Border(),
      children: kinder,
    );
  }
}

class _Zeile extends StatelessWidget {
  const _Zeile({required this.titel, required this.unten});

  final String titel;
  final String unten;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titel, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(
            unten,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Die Felder in der Reihenfolge der Mappe.
List<ZutatFeld> _sortiert(Set<ZutatFeld> felder) => [
      for (final f in ZutatFeld.values)
        if (felder.contains(f)) f,
    ];

String _oderLeer(String text) => text.isEmpty ? 'leer' : text;

/// Eine geänderte Zutat: je Feld alt → neu.
class _Aenderung extends StatelessWidget {
  const _Aenderung({required this.vorschlag});

  final ZutatVorschlag vorschlag;

  @override
  Widget build(BuildContext context) {
    final v = vorschlag;
    final vorher = v.vorher;
    return _Zeile(
      titel: v.name,
      unten: [
        for (final f in _sortiert(v.felder))
          '${f.label}: ${_oderLeer(vorher?.anzeige(f) ?? '')} → '
              '${_oderLeer(v.werte.anzeige(f))}',
      ].join(' · '),
    );
  }
}

/// Ein Konflikt: was die App hat, was die Datei sagt — und die Wahl.
class _KonfliktKarte extends StatelessWidget {
  const _KonfliktKarte({
    required this.vorschlag,
    required this.dateiGewinnt,
    required this.onWahl,
  });

  final ZutatVorschlag vorschlag;
  final bool dateiGewinnt;
  final ValueChanged<bool> onWahl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = vorschlag;
    final vorher = v.vorher;
    final grau = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    TextStyle? wert(bool gilt) => theme.textTheme.bodySmall?.copyWith(
          fontWeight: gilt ? FontWeight.w600 : FontWeight.normal,
          color: gilt ? null : theme.colorScheme.onSurfaceVariant,
          decoration: gilt ? null : TextDecoration.lineThrough,
        );
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(6),
      ),
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
                      v.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      [
                        'Zeile ${v.zeile}',
                        if (v.hinweis case final h?) h,
                      ].join(' · '),
                      style: grau,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<bool>(
                key: ValueKey('zutaten-konflikt-${v.zeile}'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('App')),
                  ButtonSegment(value: true, label: Text('Datei')),
                ],
                selected: {dateiGewinnt},
                onSelectionChanged: (wahl) => onWahl(wahl.first),
              ),
            ],
          ),
          if (v.grund case final g?) ...[
            const SizedBox(height: 4),
            Text(g, style: grau),
          ],
          const SizedBox(height: 6),
          for (final f in _sortiert(v.felder))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 150,
                    child: Text(f.label, style: grau),
                  ),
                  Expanded(
                    child: Text(
                      'App: ${_oderLeer(vorher?.anzeige(f) ?? '')}',
                      style: wert(!dateiGewinnt),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Datei: ${_oderLeer(v.werte.anzeige(f))}',
                      style: wert(dateiGewinnt),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
