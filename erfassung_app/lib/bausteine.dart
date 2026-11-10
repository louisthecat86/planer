import 'package:flutter/material.dart';

import 'stil.dart';

// Kleine Bausteine, die mehrere Seiten nutzen.

const _wochentage = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
const _wochentageLang = [
  'Montag',
  'Dienstag',
  'Mittwoch',
  'Donnerstag',
  'Freitag',
  'Samstag',
  'Sonntag',
];

String _zwei(int n) => n.toString().padLeft(2, '0');

/// „10.11.2026".
String datumText(DateTime d) => '${_zwei(d.day)}.${_zwei(d.month)}.${d.year}';

/// „Di 10.11.".
String tagKurz(DateTime d) =>
    '${_wochentage[d.weekday - 1]} ${_zwei(d.day)}.${_zwei(d.month)}.';

/// „Dienstag, 10.11." — heute und morgen beim Namen.
String tagLang(DateTime d, DateTime heute) {
  final tage = DateTime(d.year, d.month, d.day)
      .difference(DateTime(heute.year, heute.month, heute.day))
      .inHours;
  final datum = '${_zwei(d.day)}.${_zwei(d.month)}.';
  // In Stunden gerechnet und gerundet — die Zeitumstellung verschiebt
  // keinen Tag.
  final n = (tage / 24).round();
  if (n == 0) return 'Heute, $datum';
  if (n == 1) return 'Morgen, $datum';
  if (n == -1) return 'Gestern, $datum';
  return '${_wochentageLang[d.weekday - 1]}, $datum';
}

/// Eine Überschrift über einem Abschnitt.
class Abschnitt extends StatelessWidget {
  const Abschnitt(this.text, {super.key, this.zusatz});

  final String text;

  /// Steht rechts — etwa eine Anzahl.
  final String? zusatz;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stil = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
      child: Row(
        children: [
          Expanded(child: Text(text.toUpperCase(), style: stil)),
          if (zusatz != null) Text(zusatz!, style: stil),
        ],
      ),
    );
  }
}

/// Eine Fläche mit Rand — wie die Bereiche im Planer.
class Flaeche extends StatelessWidget {
  const Flaeche({super.key, required this.child, this.onTap, this.farbe});

  final Widget child;
  final VoidCallback? onTap;

  /// Die Farbe des Rands — sonst die graue Linie.
  final Color? farbe;

  @override
  Widget build(BuildContext context) {
    final f = Theme.of(context).colorScheme;
    return Material(
      color: f.surface,
      shape: RoundedRectangleBorder(
        borderRadius: Masse.ecken,
        side: BorderSide(color: farbe ?? f.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? child : InkWell(onTap: onTap, child: child),
    );
  }
}

/// Eine Zeile zum Antippen: vorn ein Streifen in der Farbe der Abteilung,
/// Titel, darunter ein Satz, rechts ein Pfeil oder eine Marke.
class TippZeile extends StatelessWidget {
  const TippZeile({
    super.key,
    required this.titel,
    required this.onTap,
    this.unter,
    this.streifen,
    this.rechts,
  });

  final String titel;
  final String? unter;
  final Color? streifen;
  final Widget? rechts;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = theme.colorScheme;
    return Flaeche(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Masse.tippHoehe),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (streifen != null) Container(width: 6, color: streifen),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        titel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (unter != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            unter!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: f.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Center(
                  child: rechts ??
                      Icon(Icons.chevron_right, color: f.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Eine kleine Marke: „erfasst", „3 geändert".
class Marke extends StatelessWidget {
  const Marke(this.text, {super.key, required this.farbe});

  final String text;
  final Color farbe;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: farbe.withValues(alpha: 0.14),
        borderRadius: Masse.ecken,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: farbe,
        ),
      ),
    );
  }
}

/// Ein Hinweis in einem farbigen Kasten.
class Hinweis extends StatelessWidget {
  const Hinweis(this.text, {super.key, required this.farbe, this.icon});

  final String text;
  final Color farbe;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: farbe.withValues(alpha: 0.10),
        borderRadius: Masse.ecken,
        border: Border.all(color: farbe.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? Icons.info_outline, size: 20, color: farbe),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// Fragt nach — true, wenn bestätigt.
Future<bool> nachfragen(
  BuildContext context, {
  required String titel,
  required String text,
  required String ja,
  bool gefaehrlich = false,
}) async {
  final antwort = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final f = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Text(titel),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: gefaehrlich
                ? FilledButton.styleFrom(
                    backgroundColor: f.error,
                    foregroundColor: f.onError,
                    minimumSize: const Size(64, 48),
                  )
                : FilledButton.styleFrom(minimumSize: const Size(64, 48)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ja),
          ),
        ],
      );
    },
  );
  return antwort ?? false;
}

/// Zeigt kurz einen Satz am unteren Rand.
void melde(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}
