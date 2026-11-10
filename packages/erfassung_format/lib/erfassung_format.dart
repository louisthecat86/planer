/// Das Austauschformat zwischen dem Produktions Planer am PC und der
/// Android-App „Planer Erfassung".
///
/// Der Weg ist eine Datei, wie beim Backup — kein Server, kein Netz:
///
/// 1. Der Planer schreibt unter Einstellungen → Handy-Erfassung ein
///    [ErfassungsPaket]: die noch nicht erfassten Produktionen der
///    gewählten Wochen und die Maschineneinstellungen aller Artikel.
/// 2. Die App öffnet die Datei, an der Anlage wird erfasst — offline.
/// 3. Die App schreibt ein [ErfassungsErgebnis]; der Planer liest es ein,
///    zeigt vorher, was er übernimmt, und trägt es ein.
///
/// Beide Seiten nutzen dieses Paket — so passen Planer und App immer
/// zusammen. Es hängt an nichts außer Dart selbst.
library;

export 'src/datei.dart';
export 'src/ergebnis.dart';
export 'src/grenze.dart';
export 'src/paket.dart';
export 'src/werte.dart';
