import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';
import '../providers/database_provider.dart';
import 'backup_service.dart';

/// Zentraler Trigger für automatische Backups nach Daten-Änderungen.
///
/// Architektur-Idee:
/// Statt an jeder Stelle, die Daten ändert (Excel-Import, Step-Editor-Save,
/// zukünftige Editor-Aktionen), manuell `BackupService.createAutoBackup`
/// aufzurufen, gibt es genau einen `AutoBackupTrigger` als Riverpod-Provider.
///
/// Aufrufer ruft einfach:
/// ```dart
/// await ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Excel-Import');
/// ```
///
/// Der Trigger:
/// - **debounct** (sammelt mehrere kurze Änderungen → ein Backup)
/// - **rate-limited** (mindestens X Sekunden zwischen Backups)
/// - **fire-and-forget** (Aufrufer wartet nicht auf den Backup-Abschluss,
///   schon gar nicht auf Cleanup)
/// - **schluckt Fehler** (ein fehlschlagendes Auto-Backup darf den
///   eigentlichen User-Workflow nicht stören)
///
/// So bleiben die Aufrufstellen einzeilig und einheitlich.
class AutoBackupTrigger {
  AutoBackupTrigger(this._db);

  final AppDatabase _db;

  /// Verzögerung nach dem letzten `fireDebounced`-Aufruf, bevor das Backup
  /// wirklich geschrieben wird. Verhindert dass z.B. mehrere
  /// Editor-Speicher-Aktionen schnell hintereinander zu mehreren Backups
  /// führen.
  static const Duration _debounce = Duration(seconds: 3);

  /// Mindestabstand zwischen zwei tatsächlich geschriebenen Backups.
  /// Schützt vor Backup-Spam wenn der User ständig Sachen ändert.
  static const Duration _minIntervall = Duration(minutes: 1);

  /// Maximalzahl der Auto-Backups im Backup-Ordner. Ältere werden
  /// nach dem Schreiben automatisch entsorgt.
  static const int _maxBackups = 30;

  Timer? _debounceTimer;
  DateTime? _letztesBackup;
  String? _ausstehenderGrund;
  Future<void>? _laufendesBackup;

  /// Zählt die bisher geschriebenen Auto-Backups in dieser App-Session.
  /// Nur für Debug / UI-Anzeige.
  int _backupZaehler = 0;

  int get backupZaehler => _backupZaehler;
  DateTime? get letztesBackupZeit => _letztesBackup;

  /// Plant ein Backup nach kurzer Verzögerung.
  /// Mehrere Aufrufe innerhalb der Debounce-Zeit fallen zusammen.
  void fireDebounced({String reason = 'Daten-Änderung'}) {
    _ausstehenderGrund = reason;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, _entscheideUndSchreibe);
  }

  /// Sofortiges Backup ohne Debounce. Für Stellen die sicher sein wollen
  /// dass die Sicherung vor dem nächsten Schritt steht (z.B. nach einem
  /// großen Excel-Import).
  ///
  /// Auch hier: Rate-Limit gilt — wenn vor weniger als [_minIntervall]
  /// schon eines geschrieben wurde, wird übersprungen.
  Future<void> fireImmediate({String reason = 'Daten-Änderung'}) async {
    _debounceTimer?.cancel();
    _ausstehenderGrund = reason;
    await _entscheideUndSchreibe();
  }

  /// Kernlogik: Prüft Rate-Limit, schreibt Backup, räumt auf.
  /// Schluckt alle Fehler bewusst.
  Future<void> _entscheideUndSchreibe() async {
    // Wenn schon ein Backup läuft: warten, dann nochmal entscheiden
    if (_laufendesBackup != null) {
      try {
        await _laufendesBackup;
      } catch (_) {}
    }

    final jetzt = DateTime.now();
    if (_letztesBackup != null &&
        jetzt.difference(_letztesBackup!) < _minIntervall) {
      // Rate-Limit greift — überspringen
      return;
    }

    final grund = _ausstehenderGrund ?? 'Daten-Änderung';
    _ausstehenderGrund = null;

    _laufendesBackup = _schreibeBackup(grund);
    try {
      await _laufendesBackup;
    } catch (_) {
      // bewusst geschluckt
    } finally {
      _laufendesBackup = null;
    }
  }

  Future<void> _schreibeBackup(String grund) async {
    try {
      await BackupService.createAutoBackup(_db);
      _letztesBackup = DateTime.now();
      _backupZaehler++;
      // Cleanup im Hintergrund — Fehler sind nicht kritisch
      unawaited(BackupService.cleanupOldAutoBackups(maxKeep: _maxBackups));
    } catch (_) {
      // Auto-Backup darf nicht den User-Flow stören.
      // Fehler werden geschluckt; eine nächste Änderung versucht es erneut.
    }
  }

  /// Beim App-Shutdown: ggf. ausstehendes Debounce-Backup noch ausführen.
  Future<void> finalize() async {
    _debounceTimer?.cancel();
    if (_ausstehenderGrund != null) {
      await _entscheideUndSchreibe();
    }
  }
}

/// Provider für den App-weiten [AutoBackupTrigger].
final autoBackupTriggerProvider = Provider<AutoBackupTrigger>((ref) {
  final db = ref.watch(databaseProvider);
  final trigger = AutoBackupTrigger(db);
  ref.onDispose(() => unawaited(trigger.finalize()));
  return trigger;
});