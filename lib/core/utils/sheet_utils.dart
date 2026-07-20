import 'package:flutter/material.dart';

/// Zeigt ein modales Bottom-Sheet OHNE die Einfahr-Animation von unten.
///
/// Standardmäßig fährt `showModalBottomSheet` von unten ins Bild — auf dem
/// Desktop wirkt das träge und ruckelt. Hier wird die Animationsdauer auf
/// null gesetzt: Das Sheet ist sofort da, statt hereinzuscrollen.
///
/// Verhält sich sonst wie `showModalBottomSheet` und gibt denselben Wert
/// zurück, den das Sheet über `Navigator.pop(context, wert)` liefert.
Future<T?> showSheetOhneAnimation<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  bool showDragHandle = false,
  BoxConstraints? constraints,
}) {
  // Ein AnimationController mit Duration.zero unterdrückt das Ein- und
  // Ausfahren. Der Controller wird von showModalBottomSheet verwaltet und
  // nach dem Schließen automatisch entsorgt.
  final controller = AnimationController(
    vsync: Navigator.of(context),
    duration: Duration.zero,
    reverseDuration: Duration.zero,
  );

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    showDragHandle: showDragHandle,
    constraints: constraints,
    transitionAnimationController: controller,
    builder: builder,
  ).whenComplete(controller.dispose);
}
