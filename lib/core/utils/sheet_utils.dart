import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Öffnet ein Bearbeitungsfenster mittig auf dem Bildschirm.
///
/// Früher kam hier ein Bottom-Sheet: Es fuhr vom unteren Rand herein und
/// klebte dort. Auf einem Desktop-Bildschirm war es oft höher als der Platz
/// darunter und wurde unten abgeschnitten — in der Produktionserfassung,
/// im Maschinen-Katalog, im Board, überall gleich.
///
/// Jetzt:
///   * **mittig**, mit Abstand zu allen Rändern,
///   * **höchstens so hoch wie der Bildschirm**. Reicht der Platz nicht,
///     scrollt der Inhalt.
///
/// Das Scrollen übernimmt der Inhalt selbst. Alle Fenster der App sind schon
/// so gebaut: eine Liste mit `shrinkWrap`, eine `SingleChildScrollView` oder
/// ein `DraggableScrollableSheet`. Sie brauchen nur eine begrenzte Höhe, und
/// die liefert das Fenster. Ein zusätzliches Scrollen außen herum würde
/// diese Begrenzung wieder aufheben, und genau diese Inhalte brächen dann.
///
/// Name und Parameter bleiben wie bisher, damit kein Aufrufer angepasst
/// werden muss. `isScrollControlled`, `useSafeArea` und `shape` stammen
/// noch aus der Bottom-Sheet-Zeit und haben keine Wirkung mehr.
Future<T?> showSheetOhneAnimation<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  bool showDragHandle = false,
  BoxConstraints? constraints,
  ShapeBorder? shape,
}) {
  final breiteMax = constraints?.maxWidth ?? _standardBreite;
  return showGeneralDialog<T>(
    context: context,
    // Wie beim Bottom-Sheet: Ein Klick daneben oder Esc schließt.
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    // Sofort da, ohne Einblenden — wie bisher.
    transitionDuration: Duration.zero,
    pageBuilder: (dialogContext, _, __) {
      final theme = Theme.of(dialogContext);
      final mq = MediaQuery.of(dialogContext);
      final breite = math.min(breiteMax, mq.size.width - 2 * _rand);
      final hoehe = mq.size.height - 2 * _rand - mq.viewInsets.bottom;

      return SafeArea(
        child: Center(
          child: SizedBox(
            width: breite,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: math.max(hoehe, 200)),
              child: Material(
                color: theme.bottomSheetTheme.backgroundColor ??
                    theme.colorScheme.surfaceContainerLow,
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  // Die Inhalte beginnen oben ohne eigenen Abstand, weil dort
                  // früher der Anfasser des Bottom-Sheets saß.
                  padding: EdgeInsets.only(top: showDragHandle ? 20 : 8),
                  child: Builder(builder: builder),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Breite, wenn der Aufrufer keine vorgibt.
const double _standardBreite = 720;

/// Mindestabstand zu den Bildschirmrändern.
const double _rand = 24;
