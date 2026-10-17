// Allergene in der Zutatenliste hervorheben (LMIV Art. 21): Die Wortteile,
// die ein Allergen nennen, stehen in Großbuchstaben — „WEIZENmehl",
// „VollMILCHpulver", „SENF".
//
// Hervorgehoben wird nur, was die Zutat laut Katalog enthält: Eine Zutat
// ohne Milch bekommt kein „BUTTER", auch wenn es im Namen steht. Und es
// zählen ganze Wortteile — die alte Suite schrieb bei Eiern jedes „ei"
// groß („SpEIsesalz").

/// Das Ergebnis: der hervorgehobene Text und die Allergene, die darin
/// genannt sind.
class Hervorhebung {
  const Hervorhebung(this.text, this.gefunden);

  final String text;

  /// Die Allergene (Planer-Werte), die der Text nennt. Was fehlt, steht
  /// nicht in der Zutatenliste — dann muss Name oder Unterzutat ergänzt
  /// werden.
  final Set<String> gefunden;
}

/// Wörter je Allergen, längere zuerst — sonst träfe „krebs" schon das
/// Wort „Krebstiere" und hinge das „tiere" klein an.
const Map<String, List<String>> _woerter = {
  'gluten': [
    'grünkern',
    'einkorn',
    'gersten',
    'weizen',
    'roggen',
    'gerste',
    'dinkel',
    'gluten',
    'hafer',
    'kamut',
    'emmer',
  ],
  'krebstiere': [
    'krebstiere',
    'langusten',
    'krebstier',
    'garnelen',
    'languste',
    'garnele',
    'krabben',
    'shrimps',
    'hummer',
    'krabbe',
    'scampi',
    'shrimp',
    'krebs',
  ],
  'fisch': [
    'sardellen',
    'thunfisch',
    'kabeljau',
    'anchovis',
    'sardelle',
    'makrele',
    'forelle',
    'hering',
    'dorsch',
    'fisch',
    'lachs',
  ],
  'erdnuesse': ['erdnüsse', 'erdnuss'],
  'soja': ['edamame', 'soja', 'tofu'],
  'milch': [
    'laktose',
    'lactose',
    'joghurt',
    'schmand',
    'butter',
    'jogurt',
    'kasein',
    'casein',
    'milch',
    'sahne',
    'quark',
    'molke',
    'käse',
    'rahm',
  ],
  'schalenfruechte': [
    'schalenfrüchte',
    'cashewkerne',
    'haselnüsse',
    'macadamia',
    'pekannüsse',
    'pistazien',
    'haselnuss',
    'paranüsse',
    'pekannuss',
    'walnüsse',
    'paranuss',
    'pistazie',
    'walnuss',
    'mandeln',
    'cashew',
    'mandel',
  ],
  'sellerie': ['sellerie'],
  'senf': ['senf'],
  'sesam': ['sesam'],
  'sulfit': ['schwefeldioxid', 'sulfite', 'sulfit'],
  'lupinen': ['lupinen', 'lupine'],
  'weichtiere': [
    'tintenfisch',
    'weichtiere',
    'schnecken',
    'weichtier',
    'calamari',
    'muscheln',
    'schnecke',
    'muschel',
    'oktopus',
    'kalmar',
    'krake',
  ],
};

/// Wörter, in denen ein Allergen-Wort steckt, ohne das Allergen zu meinen.
const Map<String, List<String>> _ausnahmen = {
  'milch': [
    'kakaobutter',
    'erdnussbutter',
    'sheabutter',
    'leberkäse',
    'fleischkäse',
  ],
};

/// Eier: „ei" ist zu kurz für die Suche im Wort. Es zählt als ganzes Wort
/// oder als Teil der üblichen Ei-Wörter — Hühnerei, Vollei, Eigelb,
/// Eiklar, Eiweiß, Volleipulver.
final RegExp _eiWort = RegExp(
  r'^(hühner|huehner|voll|flüssig|fluessig|trocken|frisch|enten|wachtel|bio)?'
  r'(eier|ei)(gelb|klar|weiß|weiss|dotter)?(pulver)?$',
);

/// E-Nummern der Sulfite (E 220 bis E 228).
final RegExp _sulfitNummer = RegExp(r'\b[eE] ?22[0-8]\b');

final RegExp _wort = RegExp('[A-Za-zÄÖÜäöüßẞéèêàáâ]+');

/// Hebt in [text] die Wortteile hervor, die eines der [allergene] nennen.
Hervorhebung hebeAllergeneHervor(String text, Set<String> allergene) {
  if (text.isEmpty || allergene.isEmpty) return Hervorhebung(text, const {});
  final klein = text.toLowerCase();
  // Kleinschreibung verschiebt bei deutschen Texten keine Stellen; sollte
  // es doch einmal passieren, wird nichts hervorgehoben.
  if (klein.length != text.length) return Hervorhebung(text, const {});

  final stellen = <(int, int)>[];
  final gefunden = <String>{};

  bool frei(int von, int bis) =>
      stellen.every((s) => bis <= s.$1 || von >= s.$2);

  for (final treffer in _wort.allMatches(klein)) {
    final wort = treffer.group(0)!;
    final anfang = treffer.start;
    for (final allergen in allergene) {
      if (allergen == 'eier') {
        final ei = _eiWort.firstMatch(wort);
        if (ei != null) {
          final von = anfang + (ei.group(1)?.length ?? 0);
          final bis = von + ei.group(2)!.length + (ei.group(3)?.length ?? 0);
          if (frei(von, bis)) stellen.add((von, bis));
          gefunden.add(allergen);
        }
        continue;
      }
      final woerter = _woerter[allergen];
      if (woerter == null) continue;
      final ausnahmen = _ausnahmen[allergen] ?? const <String>[];
      if (ausnahmen.any(wort.contains)) continue;
      for (final w in woerter) {
        var i = wort.indexOf(w);
        while (i >= 0) {
          final von = anfang + i;
          final bis = von + w.length;
          if (frei(von, bis)) {
            stellen.add((von, bis));
            gefunden.add(allergen);
          }
          i = wort.indexOf(w, i + w.length);
        }
      }
    }
  }
  if (allergene.contains('sulfit') && _sulfitNummer.hasMatch(text)) {
    gefunden.add('sulfit');
  }

  if (stellen.isEmpty) return Hervorhebung(text, gefunden);
  stellen.sort((a, b) => a.$1.compareTo(b.$1));
  final aus = StringBuffer();
  var pos = 0;
  for (final (von, bis) in stellen) {
    aus
      ..write(text.substring(pos, von))
      ..write(text.substring(von, bis).toUpperCase());
    pos = bis;
  }
  aus.write(text.substring(pos));
  return Hervorhebung(aus.toString(), gefunden);
}
