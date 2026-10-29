/// Was ein Dokument zum Auswählen anbietet — welche Teile, welche Blätter
/// — und die Wahl, die das Druckfenster daraus macht.
///
/// Bewusst ohne Flutter-Abhängigkeit: Die Dokumente bauen aus der Wahl
/// ihre Blätter, und das lässt sich ohne Oberfläche prüfen.
library;

import 'dart:async';

import 'druck_layout.dart';
import 'druck_satz.dart';

/// Eine Möglichkeit im Druckfenster.
sealed class DruckOption {
  const DruckOption({
    required this.schluessel,
    required this.titel,
    this.hinweis,
    this.gruppe,
    this.sichtbar,
    this.merken = true,
  });

  /// Unter diesem Namen steht der Wert in der [DruckWahl].
  final String schluessel;

  final String titel;

  /// Eine Zeile Erklärung darunter — null: keine.
  final String? hinweis;

  /// Überschrift, unter der die Möglichkeit steht. Folgen mehrere mit
  /// derselben Gruppe aufeinander, steht sie einmal darüber.
  final String? gruppe;

  /// Nur anbieten, wenn das für die bisherige Wahl gilt — etwa die Tage
  /// nur beim Wochenplan. null: immer.
  final bool Function(DruckWahl wahl)? sichtbar;

  /// Für das nächste Mal merken. Nein bei allem, was von den Daten
  /// abhängt — welche Abteilungen diese Woche etwas zu tun haben.
  final bool merken;

  Object get standardWert;

  /// Ein gemerkter Wert, wenn er noch passt — sonst null.
  Object? lesen(Object? json);

  /// Der Wert zum Merken.
  Object schreiben(Object wert) => wert;

  bool istSichtbar(DruckWahl wahl) => sichtbar?.call(wahl) ?? true;
}

/// Ein Häkchen: Teil drucken oder nicht.
class DruckSchalter extends DruckOption {
  const DruckSchalter({
    required super.schluessel,
    required super.titel,
    super.hinweis,
    super.gruppe,
    super.sichtbar,
    super.merken,
    this.standard = true,
  });

  final bool standard;

  @override
  Object get standardWert => standard;

  @override
  Object? lesen(Object? json) => json is bool ? json : null;
}

/// Ein Eintrag in einer Auswahl.
class DruckWert {
  const DruckWert(
    this.wert,
    this.titel, {
    this.hinweis,
    this.farbe,
    this.kuerzel,
  });

  final String wert;
  final String titel;
  final String? hinweis;

  /// Farbe als 0xAARRGGBB für eine Marke davor — etwa die der Abteilung.
  final int? farbe;

  /// Kürzel in der Marke („WK") — null: eine Marke ohne Text.
  final String? kuerzel;
}

/// Eins aus mehreren — „Woche oder Tag".
class DruckWahlEins extends DruckOption {
  const DruckWahlEins({
    required super.schluessel,
    required super.titel,
    required this.werte,
    required this.standard,
    super.hinweis,
    super.gruppe,
    super.sichtbar,
    super.merken,
  });

  final List<DruckWert> werte;
  final String standard;

  @override
  Object get standardWert => standard;

  @override
  Object? lesen(Object? json) =>
      werte.any((w) => w.wert == json) ? json as String : null;
}

/// Beliebig viele aus mehreren — „welche Abteilungen".
class DruckWahlMehrere extends DruckOption {
  const DruckWahlMehrere({
    required super.schluessel,
    required super.titel,
    required this.werte,
    required this.standard,
    super.hinweis,
    super.gruppe,
    super.sichtbar,
    super.merken,
  });

  final List<DruckWert> werte;
  final Set<String> standard;

  @override
  Object get standardWert => standard;

  @override
  Object? lesen(Object? json) {
    if (json is! List) return null;
    // Was es nicht mehr gibt, fällt weg — die Reihenfolge der Auswahl
    // gilt, nicht die gemerkte.
    final gemerkt = json.whereType<String>().toSet();
    return {
      for (final w in werte)
        if (gemerkt.contains(w.wert)) w.wert,
    };
  }

  @override
  Object schreiben(Object wert) => [...(wert as Set<String>)];
}

/// Was im Druckfenster gewählt ist: wie gedruckt wird ([layout]) und was
/// ([werte]).
class DruckWahl {
  const DruckWahl({required this.layout, required this.werte});

  /// Alles, wie das Dokument es vorsieht.
  factory DruckWahl.standard(
    List<DruckOption> optionen, {
    DruckLayout layout = const DruckLayout(),
  }) =>
      DruckWahl(
        layout: layout,
        werte: {for (final o in optionen) o.schluessel: o.standardWert},
      );

  /// Liest gemerkte Einstellungen ([DruckWahl.toJson]). Was fehlt, nicht
  /// mehr passt oder nicht gemerkt wird, kommt aus dem Standard.
  factory DruckWahl.fromJson(
    Object? json,
    List<DruckOption> optionen, {
    DruckLayout layout = const DruckLayout(),
  }) {
    final standard = DruckWahl.standard(optionen, layout: layout);
    if (json is! Map) return standard;
    final gemerkt = json['werte'];
    return DruckWahl(
      layout: DruckLayout.fromJson(json['layout'], standard: layout),
      werte: {
        for (final o in optionen)
          o.schluessel: (o.merken && gemerkt is Map
                  ? o.lesen(gemerkt[o.schluessel])
                  : null) ??
              o.standardWert,
      },
    );
  }

  final DruckLayout layout;
  final Map<String, Object> werte;

  /// Ein [DruckSchalter] — ohne Wert: an.
  bool an(String schluessel) => werte[schluessel] as bool? ?? true;

  /// Eine [DruckWahlEins].
  String eins(String schluessel) => werte[schluessel] as String? ?? '';

  /// Eine [DruckWahlMehrere].
  Set<String> mehrere(String schluessel) =>
      werte[schluessel] as Set<String>? ?? const {};

  DruckWahl mit(String schluessel, Object wert) =>
      DruckWahl(layout: layout, werte: {...werte, schluessel: wert});

  DruckWahl mitLayout(DruckLayout neu) => DruckWahl(layout: neu, werte: werte);

  /// Zum Merken — nur, was [DruckOption.merken] will.
  Map<String, Object> toJson(List<DruckOption> optionen) => {
        'layout': layout.toJson(),
        'werte': {
          for (final o in optionen)
            if (o.merken && werte.containsKey(o.schluessel))
              o.schluessel: o.schreiben(werte[o.schluessel]!),
        },
      };
}

/// Ein Dokument, das gedruckt werden kann: was sich auswählen lässt und
/// wie es aus der Wahl entsteht.
class DruckAuftrag {
  const DruckAuftrag({
    required this.art,
    required this.titel,
    required this.bauen,
    this.untertitel,
    this.optionen = const [],
    this.standardLayout = const DruckLayout(),
  });

  /// Unter diesem Namen merkt sich das Druckfenster die Einstellungen —
  /// für jede Art von Dokument eigene („plan", „datenblatt").
  final String art;

  /// Überschrift des Druckfensters: „Plan drucken".
  final String titel;

  /// Zeile darunter: „KW 44 · Do 29.10." — null: keine.
  final String? untertitel;

  final List<DruckOption> optionen;
  final DruckLayout standardLayout;

  /// Baut das Dokument aus der Wahl. Ist nichts gewählt, was sich drucken
  /// ließe, wirft es [DruckNichtsGewaehlt].
  final FutureOr<DruckDokument> Function(DruckWahl wahl) bauen;
}

/// Die Wahl ergibt nichts zu drucken — [text] sagt, was fehlt („Wähle
/// mindestens eine Abteilung.").
class DruckNichtsGewaehlt implements Exception {
  const DruckNichtsGewaehlt(this.text);

  final String text;

  @override
  String toString() => text;
}

/// Ein Dateiname ohne Umlaute, Leer- und Sonderzeichen:
/// „Wochenplan KW 44 Wurstküche" → „Wochenplan_KW_44_Wurstkueche".
String druckDateiname(String text) {
  const umlaute = {
    'ä': 'ae',
    'ö': 'oe',
    'ü': 'ue',
    'Ä': 'Ae',
    'Ö': 'Oe',
    'Ü': 'Ue',
    'ß': 'ss',
  };
  var name = text;
  for (final e in umlaute.entries) {
    name = name.replaceAll(e.key, e.value);
  }
  name = name
      .replaceAll(RegExp('[^A-Za-z0-9-]+'), '_')
      .replaceAll(RegExp('^_+|_+\$'), '');
  return name.isEmpty ? 'Druck' : name;
}
