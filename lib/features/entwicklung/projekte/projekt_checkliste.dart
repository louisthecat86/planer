import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/utils/format.dart';
import '../daten/entwicklung_repository.dart'
    show VersionStatus, alleVersionenProvider, rezepturenProvider;
import '../haccp/prozess_modell.dart';
import '../rechenkern/rechen_modell.dart';
import '../rechenkern/rechenkern.dart';
import 'projekt_modell.dart';
import 'projekt_repository.dart' show projekteProvider;

// Die Projekt-Checkliste rechnet sich selbst (F25): Acht ihrer neun
// Punkte sieht die App dem Projekt an — Artikel, Rezeptur, Nährwerte,
// Sensorik, Produktfoto, Prozess, Spezifikation und das Etikett an seinen
// Pflichtangaben (F28). Von Hand bleibt nur Navision. Gezählt wird
// überall gleich: in der Projektliste, in der Übersicht, in den Zahlen
// der Entwicklung und im Bericht.
//
// Das Produktfoto lässt sich zurückstellen, solange es keins gibt (F37):
// Es bleibt offen, „Als Nächstes" geht aber weiter, und der Kopf zeigt
// dezent, dass es noch fehlt.

/// Die Punkte, die man von Hand abhakt — die übrigen rechnet die App.
const Set<String> kChecklisteVonHand = {'navisionAngelegt'};

/// Was für einen offenen Punkt zu tun ist — für „Als Nächstes".
const Map<String, String> kCheckAufgabe = {
  'rezepturErstellt': 'Rezeptur erstellen',
  'naehrwerteErstellt': 'Nährwerte vervollständigen',
  'sensorikErstellt': 'Sensorik beschreiben',
  'produktfotoHinterlegt': 'Produktfoto hinterlegen',
  'prozessErstellt': 'Prozess beschreiben',
  'spezifikationErstellt': 'Spezifikation erstellen',
  'etikettErstellt': 'Pflichtangaben des Etiketts prüfen',
  'artikelAngelegt': 'Als Artikel freigeben',
  'navisionAngelegt': 'In Navision anlegen und abhaken',
};

/// Was ein zurückgestellter Punkt im Kopf sagt.
const Map<String, String> kCheckFehlt = {
  'produktfotoHinterlegt': 'Produktfoto fehlt noch',
};

/// Ein Punkt der Projekt-Checkliste, wie er gerade steht.
class CheckStand {
  const CheckStand({
    required this.punkt,
    required this.erledigt,
    this.text,
    this.rezepturId,
    this.zurueckgestellt = false,
  });

  final CheckPunkt punkt;
  final bool erledigt;

  /// Offen, aber mit „Später" zurückgestellt (F37): „Als Nächstes" geht
  /// an ihm vorbei.
  final bool zurueckgestellt;

  /// Woran die App den Punkt erkennt oder was noch fehlt — null, wenn es
  /// nichts zu sagen gibt (und bei Punkten von Hand).
  final String? text;

  /// Bei Rezeptur und Nährwerten: die Rezeptur, um die es geht — die des
  /// geprüften Stands, ohne ihn die einzige des Projekts.
  final String? rezepturId;

  /// Von Hand abzuhaken: Navision.
  bool get vonHand => kChecklisteVonHand.contains(punkt.schluessel);

  /// Lässt sich mit „Später" zurückstellen: das Produktfoto.
  bool get zurueckstellbar => kCheckZurueckstellbar.contains(punkt.schluessel);
}

/// Die Projekt-Checkliste, wie sie gerade steht.
class ProjektCheckStand {
  const ProjektCheckStand(this.punkte);

  final List<CheckStand> punkte;

  int get erledigt => punkte.where((p) => p.erledigt).length;
  int get anzahl => punkte.length;
  double get anteil => anzahl == 0 ? 0 : erledigt / anzahl;

  /// „5 von 8" — überall gleich.
  String get text => '$erledigt von $anzahl';

  CheckStand? punkt(String schluessel) =>
      punkte.where((p) => p.punkt.schluessel == schluessel).firstOrNull;

  /// Alles erledigt — auch nichts zurückgestellt.
  bool get fertig => anzahl > 0 && erledigt == anzahl;

  /// Der erste offene Punkt in der Reihenfolge der Arbeit, der nicht
  /// zurückgestellt ist — null, wenn es keinen mehr gibt.
  CheckStand? get naechster =>
      punkte.where((p) => !p.erledigt && !p.zurueckgestellt).firstOrNull;

  /// Offene Punkte, die zurückgestellt sind — für den Hinweis im Kopf.
  List<CheckStand> get zurueckgestellt => [
        for (final p in punkte)
          if (!p.erledigt && p.zurueckgestellt) p,
      ];
}

/// Was für [c] zu tun ist: „Sensorik beschreiben".
String checkAufgabe(CheckStand c) =>
    kCheckAufgabe[c.punkt.schluessel] ?? c.punkt.label;

/// Was ein zurückgestellter Punkt [c] im Kopf sagt: „Produktfoto fehlt
/// noch".
String checkFehlt(CheckStand c) =>
    kCheckFehlt[c.punkt.schluessel] ?? '${c.punkt.label}: zurückgestellt';

/// Was ein abgeschlossener Stand über seine Nährwerte sagt: ob er Mengen
/// hat und welche Zutaten ohne Nährwerte sind.
typedef NaehrwertBefund = ({bool mengen, List<String> ohne});

/// Die Befunde nach eingefrorenem Stand — ein abgeschlossener Stand ändert
/// sich nicht mehr, gerechnet wird also nur einmal.
final Map<String, NaehrwertBefund?> _befunde = {};

/// Der Befund eines abgeschlossenen Stands aus seinem eingefrorenen JSON —
/// null, wenn es fehlt oder sich nicht lesen lässt.
NaehrwertBefund? naehrwertBefund(RezepturVersion v) {
  final stand = v.stand;
  if (stand == null || stand.trim().isEmpty) return null;
  if (_befunde.containsKey(stand)) return _befunde[stand];
  if (_befunde.length >= 500) _befunde.clear();
  NaehrwertBefund? befund;
  try {
    final json = jsonDecode(stand);
    if (json is Map<String, dynamic>) {
      final e = berechne(RechenRezeptur.ausJson(json));
      befund = (mengen: e.eingesetztKg > 0, ohne: e.ohneNaehrwerte);
    }
  } catch (_) {
    befund = null;
  }
  return _befunde[stand] = befund;
}

/// Der neueste abgeschlossene Stand zuerst.
int _neuesteZuerst(RezepturVersion a, RezepturVersion b) {
  final z = (b.abgeschlossenAm ?? b.updatedAt)
      .compareTo(a.abgeschlossenAm ?? a.updatedAt);
  return z != 0 ? z : b.nummer.compareTo(a.nummer);
}

/// „A, B und C" — höchstens drei Namen, dann „und 2 weitere".
String _aufzaehlen(List<String> namen) {
  if (namen.length > 3) {
    return '${namen.take(3).join(', ')} und ${namen.length - 3} weitere';
  }
  if (namen.length <= 1) return namen.join();
  return '${namen.take(namen.length - 1).join(', ')} und ${namen.last}';
}

/// Rechnet die Checkliste von [projekt] aus seinen [rezepturen] und deren
/// [versionen] — beide dürfen auch die anderer Projekte enthalten.
///
/// Geprüft wird am freigegebenen Stand, sonst am zuletzt abgeschlossenen:
/// Ein Entwurf kann sich noch ändern, ein abgeschlossener Stand nicht.
ProjektCheckStand projektCheckStand({
  required EntwicklungsProjekt projekt,
  required Iterable<Rezeptur> rezepturen,
  required Iterable<RezepturVersion> versionen,
}) {
  final p = projekt;
  final eigene = {
    for (final r in rezepturen)
      if (r.projektId == p.id && r.deletedAt == null) r.id: r,
  };
  final abgeschlossen = [
    for (final v in versionen)
      if (eigene.containsKey(v.rezepturId) &&
          v.status == VersionStatus.abgeschlossen)
        v,
  ]..sort(_neuesteZuerst);
  final bezug =
      abgeschlossen.where((v) => v.id == p.freigabeVersionId).firstOrNull ??
          abgeschlossen.firstOrNull;
  final haken = checklisteAus(p.checkliste);
  final spaeter = checklisteZurueckgestellt(p.checkliste);
  final rezepturId =
      bezug?.rezepturId ?? (eigene.length == 1 ? eigene.keys.single : null);

  CheckStand stand(CheckPunkt c) {
    final mitRezeptur = c.schluessel == 'rezepturErstellt' ||
        c.schluessel == 'naehrwerteErstellt';
    CheckStand erledigt([String? text]) => CheckStand(
          punkt: c,
          erledigt: true,
          text: text,
          rezepturId: mitRezeptur ? rezepturId : null,
        );
    CheckStand offen([String? text]) => CheckStand(
          punkt: c,
          erledigt: false,
          text: text,
          rezepturId: mitRezeptur ? rezepturId : null,
        );

    switch (c.schluessel) {
      case 'artikelAngelegt':
        if (p.artikelId != null) {
          final nummer = p.artikelnummer?.trim() ?? '';
          final am = p.freigegebenAm;
          final teile = [
            if (nummer.isNotEmpty) 'Artikel $nummer',
            if (am != null) 'freigegeben am ${Format.datum(am)}',
          ];
          return erledigt(
            teile.isEmpty ? 'Mit der Freigabe angelegt' : teile.join(' · '),
          );
        }
        // Vor der Freigabe im Planer (etwa in der Suite) von Hand
        // abgehakt — das gilt weiter.
        if (haken.contains(c.schluessel)) {
          return erledigt('Früher von Hand abgehakt');
        }
        return offen('Kommt mit der Freigabe');

      case 'rezepturErstellt':
        if (bezug != null) {
          final name = eigene[bezug.rezepturId]?.name ?? 'Rezeptur';
          return erledigt(
            '$name · Stand ${bezug.nummer} '
            '${bezug.id == p.freigabeVersionId ? 'freigegeben' : 'abgeschlossen'}',
          );
        }
        return offen(
          eigene.isEmpty ? 'Noch keine Rezeptur' : 'Noch kein Stand abgeschlossen',
        );

      case 'naehrwerteErstellt':
        if (bezug == null) {
          return offen('Kommt mit dem ersten abgeschlossenen Stand');
        }
        final name = 'Stand ${bezug.nummer}';
        final befund = naehrwertBefund(bezug);
        if (befund == null) return offen('$name ließ sich nicht lesen');
        if (!befund.mengen) return offen('$name hat keine Mengen');
        if (befund.ohne.isNotEmpty) {
          return offen('$name: ohne Nährwerte: ${_aufzaehlen(befund.ohne)}');
        }
        return erledigt('$name: alle Zutaten mit Nährwerten');

      case 'spezifikationErstellt':
        // Hakt die App beim Erstellen der Spezifikation selbst ab.
        return haken.contains(c.schluessel)
            ? erledigt()
            : offen('Im Reiter „Produkt" erstellen');

      case 'prozessErstellt':
        final prozess = Prozessparameter.aus(p.prozess);
        // Eine Kette mit Schritten — oder frühere Abschnitte mit Werten,
        // solange sie noch nicht zur Kette wurden (F34). Der Arbeitsstand
        // speichert sich selbst (F29); dazu, wie er zur zuletzt
        // festgehaltenen Version steht.
        if (prozess.beschrieben) {
          return erledigt(
            prozessFassung(
              prozess,
              ProzessStand.listeAus(p.prozessHistorie),
            ).text,
          );
        }
        return offen(
          prozess.leer
              ? 'Im Reiter „Herstellung" eintragen'
              : 'Noch keine Werte eingetragen',
        );

      case 'produktfotoHinterlegt':
        if (p.bildDateiId != null) return erledigt();
        // Solange es keins gibt, lässt es sich zurückstellen (F37).
        if (spaeter.contains(c.schluessel)) {
          return CheckStand(
            punkt: c,
            erledigt: false,
            text: 'Zurückgestellt, bis es ein Foto gibt',
            zurueckgestellt: true,
          );
        }
        return offen('Im Reiter „Produkt" hinterlegen');

      case 'sensorikErstellt':
        final s = Sensorik.aus(p.sensorik);
        final fehlt = [
          if (s.aussehen.trim().isEmpty) 'Aussehen',
          if (s.geruch.trim().isEmpty) 'Geruch',
          if (s.geschmack.trim().isEmpty) 'Geschmack',
          if (s.konsistenz.trim().isEmpty) 'Konsistenz',
        ];
        if (fehlt.isEmpty) return erledigt();
        return offen(
          fehlt.length == 4
              ? 'Im Reiter „Produkt" beschreiben'
              : 'Fehlt: ${_aufzaehlen(fehlt)}',
        );

      case 'etikettErstellt':
        // Die Pflichtangaben des Etiketts (F28): erledigt, wenn jede
        // abgehakt ist oder nicht zutrifft.
        final lmiv = lmivAus(p.etikettCheckliste);
        final alle = kEtikettCheckliste.length;
        final geprueft = kEtikettCheckliste
            .where((l) => lmivStand(lmiv, l.schluessel).geprueft)
            .length;
        if (geprueft == alle) {
          final nz = kEtikettCheckliste
              .where(
                (l) =>
                    lmivStand(lmiv, l.schluessel) == LmivStand.trifftNichtZu,
              )
              .length;
          final zusatz = switch (nz) {
            0 => '',
            1 => ' · 1 trifft nicht zu',
            _ => ' · $nz treffen nicht zu',
          };
          return erledigt('Alle $alle Pflichtangaben geprüft$zusatz');
        }
        // Vor F28 von Hand abgehakt — das gilt weiter.
        if (haken.contains(c.schluessel)) {
          return erledigt('Früher von Hand abgehakt');
        }
        return offen('$geprueft von $alle Pflichtangaben geprüft');

      default:
        // Von Hand: Navision.
        return CheckStand(punkt: c, erledigt: haken.contains(c.schluessel));
    }
  }

  return ProjektCheckStand([for (final c in kProjektCheckliste) stand(c)]);
}

/// Die Checklisten aller [projekte] nach ID.
Map<String, ProjektCheckStand> projektCheckStaende({
  required Iterable<EntwicklungsProjekt> projekte,
  required Iterable<Rezeptur> rezepturen,
  required Iterable<RezepturVersion> versionen,
}) {
  final rezepturenJeProjekt = <String, List<Rezeptur>>{};
  for (final r in rezepturen) {
    final pid = r.projektId;
    if (pid != null) rezepturenJeProjekt.putIfAbsent(pid, () => []).add(r);
  }
  final versionenJeRezeptur = <String, List<RezepturVersion>>{};
  for (final v in versionen) {
    versionenJeRezeptur.putIfAbsent(v.rezepturId, () => []).add(v);
  }
  return {
    for (final p in projekte)
      p.id: projektCheckStand(
        projekt: p,
        rezepturen: rezepturenJeProjekt[p.id] ?? const [],
        versionen: [
          for (final r in rezepturenJeProjekt[p.id] ?? const <Rezeptur>[])
            ...?versionenJeRezeptur[r.id],
        ],
      ),
  };
}

/// Die Checklisten aller Projekte nach ID — null, solange Projekte,
/// Rezepturen oder Stände noch laden.
final projektChecklistenProvider = Provider<Map<String, ProjektCheckStand>?>(
  (ref) {
    final projekte = ref.watch(projekteProvider).valueOrNull;
    final rezepturen = ref.watch(rezepturenProvider).valueOrNull;
    final versionen = ref.watch(alleVersionenProvider).valueOrNull;
    if (projekte == null || rezepturen == null || versionen == null) {
      return null;
    }
    return projektCheckStaende(
      projekte: projekte,
      rezepturen: rezepturen,
      versionen: versionen,
    );
  },
);
