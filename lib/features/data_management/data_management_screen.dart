import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers/backup_provider.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/auto_backup_trigger.dart';
import '../../core/services/backup_service.dart';
import '../../core/services/stammdaten_export_service.dart';
import '../../core/services/stammdaten_import_service.dart';
import '../../core/services/maschinen_katalog_excel_service.dart';
import '../../core/theme/app_stil.dart';
import '../../core/ui/bausteine.dart';
import '../articles/article_detail_providers.dart';
import '../articles/article_list_screen.dart';
import '../entwicklung/entwicklung_zugang.dart'
    show entwicklungNachWiederherstellen;

/// Zentraler „Daten verwalten"-Screen.
///
/// Vereint alle Daten-Operationen:
/// - Stammdaten-Mappe exportieren (vom Generator aus dem App-Stand gebaut)
/// - Stammdaten-Mappe importieren (dieselbe Mappe, in Excel bearbeitet)
/// - Backup erstellen / wiederherstellen
/// - Speicherort der DB / Backups anzeigen
///
/// Erreichbar über die Einstellungen („Import / Export").
class DataManagementScreen extends ConsumerStatefulWidget {
  const DataManagementScreen({super.key});

  @override
  ConsumerState<DataManagementScreen> createState() =>
      _DataManagementScreenState();
}

class _DataManagementScreenState
    extends ConsumerState<DataManagementScreen> {
  // -- Allgemeine Status ----------------------------------------------
  bool _busy = false;
  String? _statusMessage;
  bool _statusFehler = false;

  // -- Import-Detailmeldungen (Fehler + Hinweise des letzten Imports) --
  List<String> _importFehler = [];
  List<String> _importWarnungen = [];

  /// Zwischenstand eines laufenden Stammdaten-Imports (null = keiner läuft).
  StammdatenFortschritt? _importFortschritt;

  // -- Speicherort-Pfade (nur Anzeige) --------------------------------
  String? _datenbankPfad;
  String? _backupPfad;

  /// Selbst gewählter Backup-Ordner (null = Standard).
  String? _eigenerOrdner;

  // -- Backup-Liste ---------------------------------------------------
  List<BackupInfo> _backups = [];
  bool _backupsGeladen = false;

  /// Liste der Backups aufgeklappt — im Alltag zugeklappt.
  bool _backupsOffen = false;

  @override
  void initState() {
    super.initState();
    _ladeUebersicht();
  }

  Future<void> _ladeUebersicht() async {
    final eigener = await BackupService.getEigenerBackupOrdner();
    if (mounted) setState(() => _eigenerOrdner = eigener);
    try {
      final dbDir = await BackupService.getDatabaseDirectoryPath();
      final bDir = await BackupService.getBackupDirectoryPath();
      final backups = await BackupService.listBackups();
      if (mounted) {
        setState(() {
          _datenbankPfad = dbDir;
          _backupPfad = bDir;
          _backups = backups;
          _backupsGeladen = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Fehler beim Laden: $e';
          _statusFehler = true;
        });
      }
    }
  }

  void _setBusy(bool busy, {String? msg, bool fehler = false}) {
    if (!mounted) return;
    setState(() {
      _busy = busy;
      _statusMessage = msg;
      _statusFehler = fehler;
      // Beim Start einer neuen Aktion alte Import-Details ausblenden.
      if (busy) {
        _importFehler = [];
        _importWarnungen = [];
      }
    });
  }

  /// Lädt alle Daten-Provider neu, deren Inhalt sich durch Import oder
  /// Backup-Restore geändert haben kann — siehe [invalidiereDatenNachImport].
  void _invalidiereDatenProvider() => invalidiereDatenNachImport(ref);

  /// Öffnet die Backup-Verwaltung und liest danach die Liste hier neu ein:
  /// Dort lassen sich Backups anlegen und löschen.
  Future<void> _backupVerwaltungOeffnen() async {
    // Die Liste dort frisch laden — der Provider merkt sich sonst den Stand
    // vom letzten Öffnen, auch wenn hier inzwischen Backups dazukamen.
    ref.invalidate(refreshableBackupListProvider);
    await context.pushNamed('backup');
    if (mounted) await _ladeUebersicht();
  }

  // ----------------------------------------------------------------------
  // EXCEL-IMPORT
  // ----------------------------------------------------------------------

  /// Liest eine Stammdaten-Arbeitsmappe ein.
  ///
  /// Erwartet das aktuelle Format mit den Blättern „Anlagen",
  /// „Steckbriefe" und je einem Blatt pro Artikel — also genau die Mappe,
  /// die der Export erzeugt.
  Future<void> _excelImport() async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (picked == null || picked.files.isEmpty) return;
      final bytes = picked.files.first.bytes ??
          (picked.files.first.path == null
              ? null
              : await File(picked.files.first.path!).readAsBytes());
      if (bytes == null) {
        _setBusy(
          false,
          msg: 'Die Datei ließ sich nicht lesen.',
          fehler: true,
        );
        return;
      }

      _setBusy(true, msg: 'Stammdaten werden eingelesen …');
      setState(() {
        _importFortschritt =
            const StammdatenFortschritt(phase: StammdatenPhase.datei);
      });

      final service = StammdatenImportService(ref.read(databaseProvider));
      final result = await service.importiere(
        bytes,
        onFortschritt: (stand) {
          if (!mounted) return;
          setState(() => _importFortschritt = stand);
        },
      );

      if (mounted) setState(() => _importFortschritt = null);

      if (result.hatFehler) {
        _setBusy(false, msg: result.fehler.first, fehler: true);
        if (mounted) setState(() => _importFehler = result.fehler);
        return;
      }

      _invalidiereDatenProvider();

      // Auto-Backup nach dem Import — hier ist der Schutzwert am höchsten,
      // weil gerade ein großer Datenstand hereingekommen ist.
      ref.read(autoBackupTriggerProvider).fireDebounced(
            reason: 'Stammdaten-Import',
          );

      _setBusy(
        false,
        msg: '${result.artikelNeu} Artikel neu · '
            '${result.artikelAktualisiert} aktualisiert · '
            '${result.schritte} Schritte · '
            '${result.parameter} Parameter · '
            '${result.chargen} Chargen'
            '${result.anlagen > 0 ? ' · ${result.anlagen} Anlagen' : ''}'
            '${result.steckbriefZeilen > 0 ? ' · '
                '${result.steckbriefZeilen} Steckbrief-Zeilen' : ''}',
      );

      if (mounted) {
        setState(() {
          _importFehler = [];
          _importWarnungen = result.warnungen;
        });
      }

      Future.delayed(const Duration(seconds: 5), _ladeUebersicht);
    } catch (e) {
      if (mounted) setState(() => _importFortschritt = null);
      _setBusy(false, msg: 'Import-Fehler: $e', fehler: true);
    }
  }

  // ----------------------------------------------------------------------
  // EXCEL-EXPORT
  // ----------------------------------------------------------------------

  // -- Backup-Ordner festlegen ----------------------------------------

  Future<void> _backupOrdnerWaehlen() async {
    final ordner = await FilePicker.getDirectoryPath(
      dialogTitle: 'Ordner für Backups wählen',
    );
    if (ordner == null || ordner.trim().isEmpty) return;
    try {
      await BackupService.setzeEigenenBackupOrdner(ordner);
      await _ladeUebersicht();
      _setBusy(false, msg: 'Backups werden ab jetzt hier abgelegt: $ordner');
    } catch (e) {
      _setBusy(
        false,
        msg: 'Ordner konnte nicht gesetzt werden: $e',
        fehler: true,
      );
    }
  }

  Future<void> _backupOrdnerZuruecksetzen() async {
    await BackupService.setzeEigenenBackupOrdner(null);
    await _ladeUebersicht();
    _setBusy(false, msg: 'Standard-Ordner wieder aktiv.');
  }

  // -- Maschinen-Katalog als eigene Excel -----------------------------

  Future<void> _katalogExport() async {
    try {
      _setBusy(true, msg: 'Katalog wird erstellt …');
      final pfad = await MaschinenKatalogExcelService.exportiere(
        ref.read(databaseProvider),
      );
      if (pfad == null) {
        _setBusy(false);
        return;
      }
      _setBusy(false, msg: 'Maschinen-Katalog gespeichert: $pfad');
    } catch (e) {
      _setBusy(
        false,
        msg: 'Katalog-Export fehlgeschlagen: $e',
        fehler: true,
      );
    }
  }

  Future<void> _katalogImport() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (picked == null) return;

    final datei = picked.files.isNotEmpty ? picked.files.first : null;
    var bytes = datei?.bytes;
    if (bytes == null && datei?.path != null) {
      try {
        bytes = await File(datei!.path!).readAsBytes();
      } catch (_) {
        bytes = null;
      }
    }
    if (bytes == null) {
      _setBusy(
        false,
        msg: 'Die Datei ließ sich nicht lesen.',
        fehler: true,
      );
      return;
    }

    try {
      _setBusy(true, msg: 'Katalog wird eingelesen …');
      final res = await MaschinenKatalogExcelService.importiere(
        ref.read(databaseProvider),
        bytes,
      );
      ref.read(autoBackupTriggerProvider).fireDebounced(
            reason: 'Maschinen-Katalog importiert',
          );
      setState(() {
        _importFehler = [];
        _importWarnungen = res.warnungen;
      });
      final anlagenWeg = res.anlagenEntfernt > 0
          ? ', ${res.anlagenEntfernt} entfernt'
          : '';
      final parameterWeg = res.parameterEntfernt > 0
          ? ', ${res.parameterEntfernt} entfernt'
          : '';
      _setBusy(
        false,
        msg: 'Katalog eingelesen · ${res.anlagenGesamt} Anlagen '
            '(${res.anlagenNeu} neu$anlagenWeg) · '
            '${res.parameterGesamt} Parameter '
            '(${res.parameterNeu} neu$parameterWeg)',
      );
    } catch (e) {
      _setBusy(
        false,
        msg: 'Katalog-Import fehlgeschlagen: $e',
        fehler: true,
      );
    }
  }

  /// Stammdaten-Export.
  ///
  /// Baut die Mappe vollständig aus dem App-Stand — keine Vorlage nötig.
  /// Der frühere Exporter schrieb in eine beim Import abgelegte Datei
  /// hinein und lief deshalb nach einem Reset nicht mehr.
  ///
  /// Das Gegenstück ist „Artikel importieren": Was hier entsteht, liest
  /// der Import wieder ein.
  Future<void> _excelExport() async {
    try {
      _setBusy(true, msg: 'Excel wird erstellt …');

      final svc = StammdatenExportService(ref.read(databaseProvider));
      final result = await svc.exportiere();

      final zielPfad = await FilePicker.saveFile(
        dialogTitle: 'Stammdaten speichern',
        fileName: result.dateiname,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (zielPfad == null) {
        _setBusy(false);
        return;
      }

      await File(zielPfad).writeAsBytes(result.bytes);

      _setBusy(
        false,
        msg: 'Excel erstellt · ${result.artikel} Artikel · '
            '${result.anlagen} Anlagen',
      );

      if (mounted && result.warnungen.isNotEmpty) {
        setState(() => _importWarnungen = result.warnungen);
      }
    } catch (e) {
      _setBusy(false, msg: 'Export-Fehler: $e', fehler: true);
    }
  }


  // ----------------------------------------------------------------------
  // BACKUP ERSTELLEN
  // ----------------------------------------------------------------------

  Future<void> _backupErstellenAuto() async {
    try {
      _setBusy(true, msg: 'Backup wird erstellt …');
      final db = ref.read(databaseProvider);
      final pfad = await BackupService.createAutoBackup(db);
      await BackupService.cleanupOldAutoBackups();
      await _ladeUebersicht();
      _setBusy(
        false,
        msg: 'Backup gespeichert: ${pfad.split(Platform.pathSeparator).last}',
      );
    } catch (e) {
      _setBusy(false, msg: 'Backup-Fehler: $e', fehler: true);
    }
  }

  Future<void> _backupErstellenManuell() async {
    try {
      _setBusy(true, msg: 'Backup-Datei wird vorbereitet …');
      final db = ref.read(databaseProvider);
      final pfad = await BackupService.exportBackup(db);
      if (pfad == null) {
        _setBusy(false);
        return;
      }
      await _ladeUebersicht();
      _setBusy(
        false,
        msg: 'Backup gespeichert: ${pfad.split(Platform.pathSeparator).last}',
      );
    } catch (e) {
      _setBusy(false, msg: 'Backup-Fehler: $e', fehler: true);
    }
  }

  // ----------------------------------------------------------------------
  // BACKUP WIEDERHERSTELLEN
  // ----------------------------------------------------------------------

  Future<void> _backupWiederherstellen(BackupInfo info) async {
    final bestaetigt = await _frageBestaetigung(
      titel: 'Backup wiederherstellen?',
      text:
          'Alle aktuellen Daten in der App werden ersetzt durch das Backup '
          'vom ${info.formattedTimestamp}. '
          'Diese Aktion kann nicht rückgängig gemacht werden.',
      confirmText: 'Wiederherstellen',
      destructive: true,
    );
    if (!bestaetigt) return;

    try {
      _setBusy(true, msg: 'Backup wird eingelesen …');
      final db = ref.read(databaseProvider);
      await BackupService.importBackup(info.filepath, db, clearExisting: true);

      _invalidiereDatenProvider();
      entwicklungNachWiederherstellen(ref);

      // Bewusst KEIN Auto-Backup nach Restore — wir haben gerade von
      // einem Backup wiederhergestellt, ein neues Backup wäre redundant
      // und würde den Restore-Stand nur verdoppeln.

      _setBusy(
        false,
        msg: 'Backup vom ${info.formattedTimestamp} wiederhergestellt',
      );
    } catch (e) {
      _setBusy(false, msg: 'Restore-Fehler: $e', fehler: true);
    }
  }

  Future<void> _backupAusDateiWaehlen() async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['planerbackup', 'json'],
      );
      if (picked == null || picked.files.isEmpty) return;
      final filePath = picked.files.first.path;
      if (filePath == null) return;

      final bestaetigt = await _frageBestaetigung(
        titel: 'Backup wiederherstellen?',
        text:
            'Alle aktuellen Daten werden ersetzt durch das Backup aus '
            'der gewählten Datei. Fortfahren?',
        confirmText: 'Wiederherstellen',
        destructive: true,
      );
      if (!bestaetigt) return;

      _setBusy(true, msg: 'Backup wird eingelesen …');
      final db = ref.read(databaseProvider);
      await BackupService.importBackup(filePath, db, clearExisting: true);

      _invalidiereDatenProvider();
      entwicklungNachWiederherstellen(ref);

      _setBusy(false, msg: 'Backup wiederhergestellt');
    } catch (e) {
      _setBusy(false, msg: 'Restore-Fehler: $e', fehler: true);
    }
  }

  Future<void> _backupLoeschen(BackupInfo info) async {
    final bestaetigt = await _frageBestaetigung(
      titel: 'Backup löschen?',
      text:
          'Backup vom ${info.formattedTimestamp} wird unwiderruflich gelöscht.',
      confirmText: 'Löschen',
      destructive: true,
    );
    if (!bestaetigt) return;

    try {
      await BackupService.deleteBackup(info.filepath);
      await _ladeUebersicht();
      _setBusy(false, msg: 'Backup gelöscht');
    } catch (e) {
      _setBusy(false, msg: 'Lösch-Fehler: $e', fehler: true);
    }
  }

  // ----------------------------------------------------------------------
  // HELPER
  // ----------------------------------------------------------------------

  Future<bool> _frageBestaetigung({
    required String titel,
    required String text,
    required String confirmText,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titel),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                    foregroundColor: Theme.of(ctx).colorScheme.onError,
                  )
                : null,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _kopiereInZwischenablage(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pfad kopiert'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ----------------------------------------------------------------------
  // BUILD
  // ----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final fortschritt = _importFortschritt;
    final meldung = _statusMessage;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daten verwalten'),
      ),
      body: LayoutBuilder(
        builder: (context, c) {
          // Nicht über die ganze Breite: Erklärung und Knöpfe einer Zeile
          // lägen sonst weit auseinander.
          final seite = math.max(14.0, (c.maxWidth - 1100) / 2);
          return ListView(
            padding: EdgeInsets.fromLTRB(seite, 12, seite, 24),
            children: [
              // -- Status: was gerade läuft oder wie es ausging ----------
              if (_busy) ...[
                HinweisBox(
                  meldung ?? 'Bitte warten …',
                  icon: Icons.hourglass_top,
                ),
                // Der Balken direkt unter dem Hinweis zeigt, dass etwas
                // läuft. Beim Stammdaten-Import zeigt er den Fortschritt;
                // `anteil == null` heißt: Der Abschnitt liefert keine
                // Zwischenstände (das Öffnen der Datei), dann läuft er
                // durch — wie bei allen anderen Aktionen.
                LinearProgressIndicator(
                  value: fortschritt?.anteil,
                  minHeight: 3,
                ),
                if (fortschritt != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    fortschritt.beschriftung,
                    style: theme.textTheme.bodySmall?.copyWith(color: grau),
                  ),
                ],
                const SizedBox(height: 12),
              ] else if (meldung != null) ...[
                HinweisBox(
                  meldung,
                  art: _statusFehler ? StatusArt.fehler : StatusArt.ok,
                  auswaehlbar: true,
                  onSchliessen: () => setState(() => _statusMessage = null),
                ),
                const SizedBox(height: 12),
              ],

              // -- Import-Detailmeldungen (aufklappbar) -----------------
              if (_importFehler.isNotEmpty || _importWarnungen.isNotEmpty) ...[
                _ImportDetails(
                  fehler: _importFehler,
                  warnungen: _importWarnungen,
                ),
                const SizedBox(height: 12),
              ],

              // -- Je Datenbereich eine Zeile mit Export und Import ------
              // Eine Tabelle statt Kacheln: Die Knöpfe stehen rechts
              // untereinander, gleich lange Zeilen, nichts springt.
              Bereich(
                titel: 'Import und Export',
                innenAbstand: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _KategorieZeile(
                      icon: Icons.inventory_2_outlined,
                      titel: 'Artikel & Prozesse',
                      beschreibung: 'Artikel, Prozesse, Anlagen und Historie '
                          'als Excel-Mappe — in Excel bearbeiten und wieder '
                          'einlesen.',
                      onExport: _busy ? null : _excelExport,
                      onImport: _busy ? null : _excelImport,
                    ),
                    _KategorieZeile(
                      icon: Icons.precision_manufacturing_outlined,
                      titel: 'Maschinen-Katalog',
                      beschreibung: 'Anlagen, Abteilung, Kapazität und '
                          'Parameter-Steckbriefe als Excel. Der Import '
                          'gleicht über den Anlagen-Namen ab.',
                      onExport: _busy ? null : _katalogExport,
                      onImport: _busy ? null : _katalogImport,
                    ),
                    _KategorieZeile(
                      icon: Icons.swap_horiz_rounded,
                      titel: 'Navision-Artikel',
                      beschreibung: 'Artikelübersicht aus Navision einlesen: '
                          'neue Artikel anlegen, Allergene aus dem '
                          'Suchbegriff übernehmen.',
                      exportLabel: null,
                      importLabel: 'Abgleichen …',
                      onExport: null,
                      onImport: _busy
                          ? null
                          : () => context.pushNamed('navisionImport'),
                    ),
                    _KategorieZeile(
                      icon: Icons.cloud_upload_outlined,
                      titel: 'Komplett-Backup',
                      beschreibung: 'Der gesamte Datenstand als JSON. Beim '
                          'Wiederherstellen werden alle aktuellen Daten '
                          'überschrieben.',
                      exportLabel: 'Backup speichern',
                      importLabel: 'Wiederherstellen',
                      onExport: _busy ? null : _backupErstellenManuell,
                      onImport: _busy ? null : _backupAusDateiWaehlen,
                      zusatzIcon: Icons.bolt,
                      zusatzTooltip: 'Schnell-Backup in den Backup-Ordner',
                      onZusatz: _busy ? null : _backupErstellenAuto,
                      letzte: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // -- Vorhandene Backups -----------------------------------
              Bereich(
                titel: 'Vorhandene Backups',
                untertitel: _backupsGeladen ? '${_backups.length}' : null,
                aktionen: [
                  TextButton.icon(
                    onPressed: _busy ? null : _backupVerwaltungOeffnen,
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Backup-Verwaltung …'),
                  ),
                  if (_backups.isNotEmpty)
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _backupsOffen = !_backupsOffen),
                      icon: Icon(
                        _backupsOffen ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                      ),
                      label: Text(_backupsOffen ? 'Ausblenden' : 'Anzeigen'),
                    ),
                ],
                innenAbstand: EdgeInsets.zero,
                child: _backupInhalt(context),
              ),
              const SizedBox(height: 12),

              // -- Speicherort ------------------------------------------
              Bereich(
                titel: 'Speicherort',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Hier liegen deine SQLite-Datenbank und alle '
                      'automatischen Backups. Die Pfade kannst du in den '
                      'Datei-Explorer kopieren.',
                      style: theme.textTheme.bodySmall?.copyWith(color: grau),
                    ),
                    const SizedBox(height: 8),
                    // Die Pfade als kleine Tabelle mit Rand.
                    Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
                        borderRadius: AppMasse.ecken,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _PfadZeile(
                            label: 'Datenbank-Ordner',
                            pfad: _datenbankPfad,
                            onCopy: _datenbankPfad != null
                                ? () =>
                                    _kopiereInZwischenablage(_datenbankPfad!)
                                : null,
                            letzte: false,
                          ),
                          _PfadZeile(
                            label: _eigenerOrdner == null
                                ? 'Backup-Ordner (Standard)'
                                : 'Backup-Ordner (selbst gewählt)',
                            pfad: _backupPfad,
                            onCopy: _backupPfad != null
                                ? () => _kopiereInZwischenablage(_backupPfad!)
                                : null,
                            letzte: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _backupOrdnerWaehlen,
                          icon: const Icon(Icons.drive_folder_upload, size: 18),
                          label: const Text('Backup-Ordner wählen …'),
                        ),
                        if (_eigenerOrdner != null)
                          TextButton.icon(
                            onPressed:
                                _busy ? null : _backupOrdnerZuruecksetzen,
                            icon: const Icon(
                              Icons.settings_backup_restore,
                              size: 18,
                            ),
                            label: const Text('Standard-Ordner wieder nutzen'),
                          ),
                        Text(
                          'z.B. Netzlaufwerk oder USB-Stick',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: grau,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Inhalt des Bereichs „Vorhandene Backups": zugeklappt nur das neueste,
  /// aufgeklappt alle als Tabelle.
  Widget _backupInhalt(BuildContext context) {
    final theme = Theme.of(context);
    if (!_backupsGeladen) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_backups.isEmpty) {
      return const LeerHinweis(
        'Keine Backups vorhanden.',
        icon: Icons.backup_outlined,
      );
    }
    if (!_backupsOffen) {
      // Zugeklappt: Die Liste ist im Alltag Beiwerk und soll die Übersicht
      // nicht füllen — nur das neueste Backup als Zeile.
      final neuestes = _backups.first;
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Text(
          'Neuestes Backup: ${neuestes.formattedTimestamp} '
          '(${neuestes.isAuto ? 'automatisch' : 'von Hand'}) — zum '
          'Wiederherstellen oder Löschen „Anzeigen".',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final letztes = _backups.last;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in _backups)
          _BackupListenEintrag(
            info: b,
            letzte: identical(b, letztes),
            onRestore: _busy ? null : () => _backupWiederherstellen(b),
            onDelete: _busy ? null : () => _backupLoeschen(b),
          ),
      ],
    );
  }
}

// --------------------------------------------------------------------------
// Import-Detailmeldungen (aufklappbare Liste der Fehler + Hinweise)
// --------------------------------------------------------------------------

/// Fehler und Hinweise des letzten Imports als Bereich — oben rechts die
/// Anzahl als Marken in der Statusfarbe und ein Knopf zum Zuklappen.
class _ImportDetails extends StatefulWidget {
  const _ImportDetails({
    required this.fehler,
    required this.warnungen,
  });

  final List<String> fehler;
  final List<String> warnungen;

  @override
  State<_ImportDetails> createState() => _ImportDetailsState();
}

class _ImportDetailsState extends State<_ImportDetails> {
  bool _offen = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = AppFarben.von(context);
    final fehler = widget.fehler;
    final warnungen = widget.warnungen;

    return Bereich(
      titel: 'Import-Details',
      aktionen: [
        if (fehler.isNotEmpty) ...[
          StatusMarke('${fehler.length} Fehler', art: StatusArt.fehler),
          const SizedBox(width: 6),
        ],
        if (warnungen.isNotEmpty) ...[
          StatusMarke(
            warnungen.length == 1
                ? '1 Hinweis'
                : '${warnungen.length} Hinweise',
            art: StatusArt.warnung,
          ),
          const SizedBox(width: 2),
        ],
        IconButton(
          icon: Icon(_offen ? Icons.expand_less : Icons.expand_more, size: 20),
          tooltip: _offen ? 'Zuklappen' : 'Aufklappen',
          visualDensity: VisualDensity.compact,
          onPressed: () => setState(() => _offen = !_offen),
        ),
      ],
      child: !_offen
          ? Text(
              'Aufklappen, um die Meldungen zu sehen.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (fehler.isNotEmpty) ...[
                  Text(
                    'Fehler',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: f.fehler,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final m in fehler)
                    _MeldungsZeile(text: m, farbe: f.fehler),
                  if (warnungen.isNotEmpty) const SizedBox(height: 12),
                ],
                if (warnungen.isNotEmpty) ...[
                  Text(
                    'Hinweise',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: f.warnung,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final m in warnungen)
                    _MeldungsZeile(text: m, farbe: f.warnung),
                ],
              ],
            ),
    );
  }
}

/// Einzelne Melde-Zeile mit Aufzählungspunkt; Text ist markier-/kopierbar.
class _MeldungsZeile extends StatelessWidget {
  const _MeldungsZeile({
    required this.text,
    required this.farbe,
  });

  final String text;
  final Color farbe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 8),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: farbe,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              text,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------
// Ein Datenbereich als Tabellenzeile
// --------------------------------------------------------------------------

/// Ein Datenbereich als Zeile: Symbol, Titel und kurze Erklärung, rechts
/// die Knöpfe für Export und Import. In schmalen Fenstern rutschen die
/// Knöpfe unter die Erklärung.
///
/// Ohne [exportLabel] gibt es nur den Import-Knopf — für Bereiche, die nur
/// eingelesen werden.
class _KategorieZeile extends StatelessWidget {
  const _KategorieZeile({
    required this.icon,
    required this.titel,
    required this.beschreibung,
    required this.onExport,
    required this.onImport,
    this.exportLabel = 'Exportieren',
    this.importLabel = 'Importieren',
    this.zusatzIcon,
    this.zusatzTooltip,
    this.onZusatz,
    this.letzte = false,
  });

  final IconData icon;
  final String titel;
  final String beschreibung;
  final String? exportLabel;
  final String importLabel;
  final VoidCallback? onExport;
  final VoidCallback? onImport;

  /// Optionale dritte Aktion (z.B. Schnell-Backup) als reines Icon.
  final IconData? zusatzIcon;
  final String? zusatzTooltip;
  final VoidCallback? onZusatz;

  /// Letzte Zeile: ohne Linie darunter, dort schließt der Rand.
  final bool letzte;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final exportText = exportLabel;
    final zusatz = zusatzIcon;

    final kopf = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 20, color: colors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titel,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                beschreibung,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final knoepfe = Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (zusatz != null)
          IconButton(
            icon: Icon(zusatz, size: 19),
            tooltip: zusatzTooltip,
            visualDensity: VisualDensity.compact,
            onPressed: onZusatz,
          ),
        if (exportText != null)
          OutlinedButton.icon(
            onPressed: onExport,
            icon: const Icon(Icons.file_upload_outlined, size: 17),
            label: Text(exportText),
          ),
        FilledButton.tonalIcon(
          onPressed: onImport,
          icon: const Icon(Icons.file_download_outlined, size: 17),
          label: Text(importLabel),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        border: letzte
            ? null
            : Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          if (c.maxWidth < 640) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                kopf,
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: knoepfe),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: kopf),
              const SizedBox(width: 16),
              knoepfe,
            ],
          );
        },
      ),
    );
  }
}

// --------------------------------------------------------------------------
// Pfad-Zeile mit Kopier-Button
// --------------------------------------------------------------------------

/// Ein Speicherort als Tabellenzeile: Bezeichnung, Pfad zum Markieren und
/// ein Knopf zum Kopieren.
class _PfadZeile extends StatelessWidget {
  const _PfadZeile({
    required this.label,
    required this.pfad,
    required this.onCopy,
    required this.letzte,
  });

  final String label;
  final String? pfad;
  final VoidCallback? onCopy;

  /// Letzte Zeile: ohne Linie darunter, dort schließt der Rand.
  final bool letzte;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 2, 2, 2),
      decoration: BoxDecoration(
        color: AppFarben.von(context).leiste,
        border: letzte
            ? null
            : Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 190,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              pfad ?? '…',
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 11.5,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            tooltip: 'Pfad kopieren',
            onPressed: onCopy,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------
// Einzelner Backup-Listen-Eintrag
// --------------------------------------------------------------------------

/// Ein Backup als Tabellenzeile: Zeitpunkt, Größe, Art und Version, rechts
/// Wiederherstellen und Löschen.
class _BackupListenEintrag extends StatelessWidget {
  const _BackupListenEintrag({
    required this.info,
    required this.letzte,
    required this.onRestore,
    required this.onDelete,
  });

  final BackupInfo info;

  /// Letzte Zeile: ohne Linie darunter, dort schließt der Rand.
  final bool letzte;
  final VoidCallback? onRestore;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final f = AppFarben.von(context);
    final relativeZeit = _formatRelativeTime(info.timestamp);
    final versionsHinweis = info.versionsHinweis;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        border: letzte
            ? null
            : Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          Tooltip(
            message:
                info.isAuto ? 'Automatisch gesichert' : 'Von Hand gesichert',
            child: Icon(
              info.isAuto ? Icons.auto_awesome : Icons.save_outlined,
              size: 18,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.formattedTimestamp,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  '$relativeZeit · ${info.formattedSize} · '
                  '${info.isAuto ? "Auto" : "Manuell"} · '
                  'Version ${info.version}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                // Ältere Formate enthalten Bedarf, Historie und
                // Wochen-Snapshots nicht. Das sieht man einem Backup sonst
                // erst an, wenn es eingespielt ist und die Listen leer sind.
                if (versionsHinweis != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 13,
                          color: f.warnung,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            versionsHinweis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: f.warnung,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.restore, size: 20),
            tooltip: 'Wiederherstellen',
            onPressed: onRestore,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: 'Löschen',
            onPressed: onDelete,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  String _formatRelativeTime(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return 'gerade eben';
    if (diff.inHours < 1) return 'vor ${diff.inMinutes} min';
    if (diff.inDays < 1) return 'vor ${diff.inHours} Std';
    if (diff.inDays < 7) return 'vor ${diff.inDays} Tag(en)';
    return DateFormat('dd.MM.yyyy').format(when);
  }
}

/// Lädt alle Daten-Provider neu, deren Inhalt sich durch einen Import oder
/// ein Wiederherstellen geändert haben kann. Ohne dies zeigen Artikelkarte,
/// Schritte und Historie weiterhin den alten (gemerkten) Stand.
///
/// Öffentlich, weil auch die Backup-Verwaltung wiederherstellt — beide Wege
/// laden danach dieselben Daten neu.
void invalidiereDatenNachImport(WidgetRef ref) {
  ref.invalidate(articlesProvider);
  ref.invalidate(productProvider);
  ref.invalidate(productStepsProvider);
  ref.invalidate(stepParametersProvider);
  ref.invalidate(machineProvider);
  ref.invalidate(productionHistoryProvider);
}
