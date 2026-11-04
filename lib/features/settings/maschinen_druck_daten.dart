import 'package:drift/drift.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import '../../core/utils/format.dart';

// Was der Maschinen-Katalog und die Grenzwerte zum Drucken brauchen —
// geladen in wenigen Abfragen, ohne Oberfläche.

/// Ein Artikel, dessen Prozessschritte eine Anlage nutzen.
typedef MaschinenArtikel = ({String nummer, String bezeichnung});

/// Die Anlagen mit Steckbrief, Grenzwerten und den Artikeln, die sie nutzen.
class MaschinenDruckDaten {
  const MaschinenDruckDaten({
    required this.maschinen,
    this.steckbriefe = const {},
    this.grenzen = const [],
    this.artikel = const {},
  });

  /// Die Anlagen, nach Namen.
  final List<Machine> maschinen;

  /// Je Maschinen-ID ihr Steckbrief, in der Reihenfolge der Maske.
  final Map<String, List<MachineParameterDef>> steckbriefe;

  /// Alle gepflegten Grenzen — je Anlage (Name) oder Parametergruppe.
  final List<ParameterGrenzenData> grenzen;

  /// Je Maschinen-ID die Artikel, deren Schritte sie nutzen, nach Nummer.
  final Map<String, List<MaschinenArtikel>> artikel;

  /// Die Anlage mit diesem Namen — null bei einer Parametergruppe.
  Machine? maschineNamens(String name) {
    for (final m in maschinen) {
      if (m.name == name) return m;
    }
    return null;
  }

  /// Die Grenzen je Anlage oder Gruppe, nach Parametername.
  Map<String, List<ParameterGrenzenData>> get grenzenJeKontext {
    final map = <String, List<ParameterGrenzenData>>{};
    for (final g in grenzen) {
      (map[g.kontext] ??= []).add(g);
    }
    for (final liste in map.values) {
      liste.sort((a, b) => a.parameterName.compareTo(b.parameterName));
    }
    return map;
  }
}

/// Die Abteilung einer Anlage — null bei einem unbekannten Wert.
Abteilung? abteilungDer(Machine m) {
  for (final a in Abteilung.values) {
    if (a.dbValue == m.abteilung) return a;
  }
  return null;
}

/// Ein Grenzbereich als Text: „10 bis 20", „min. 10", „max. 20" — oder
/// „-" ohne Grenze. Zahlen mit Komma, ohne Nullen am Ende.
String grenzText(double? min, double? max) {
  String z(double v) => Format.eingabe(v, nachkomma: 3);
  if (min != null && max != null) return '${z(min)} bis ${z(max)}';
  if (min != null) return 'min. ${z(min)}';
  if (max != null) return 'max. ${z(max)}';
  return '-';
}

/// Lädt Anlagen, Steckbriefe, Grenzen und die Artikel je Anlage. Gelöschtes
/// zählt nicht — auch keine Schritte gelöschter Artikel.
Future<MaschinenDruckDaten> maschinenDruckLaden(AppDatabase db) async {
  final maschinen = await (db.select(db.machines)
        ..where((m) => m.deletedAt.isNull())
        ..orderBy([(m) => OrderingTerm.asc(m.name)]))
      .get();
  final defs = await (db.select(db.machineParameterDefs)
        ..where((d) => d.deletedAt.isNull())
        ..orderBy([
          (d) => OrderingTerm.asc(d.sortierung),
          (d) => OrderingTerm.asc(d.parameterName),
        ]))
      .get();
  final grenzen = await (db.select(db.parameterGrenzen)
        ..where((g) => g.deletedAt.isNull())
        ..orderBy([
          (g) => OrderingTerm.asc(g.kontext),
          (g) => OrderingTerm.asc(g.parameterName),
        ]))
      .get();
  final schritte = await (db.select(db.productSteps)
        ..where((s) => s.deletedAt.isNull() & s.maschineId.isNotNull()))
      .get();
  final produkte = {
    for (final p in await (db.select(db.products)
          ..where((p) => p.deletedAt.isNull()))
        .get())
      p.id: p,
  };

  final steckbriefe = <String, List<MachineParameterDef>>{};
  for (final d in defs) {
    (steckbriefe[d.maschineId] ??= []).add(d);
  }

  final jeMaschine = <String, Map<String, MaschinenArtikel>>{};
  for (final s in schritte) {
    final p = produkte[s.productId];
    final id = s.maschineId;
    if (p == null || id == null) continue;
    (jeMaschine[id] ??= {})[p.id] =
        (nummer: p.artikelnummer, bezeichnung: p.artikelbezeichnung);
  }
  int nachNummer(MaschinenArtikel a, MaschinenArtikel b) {
    final x = int.tryParse(a.nummer.trim());
    final y = int.tryParse(b.nummer.trim());
    return x != null && y != null
        ? x.compareTo(y)
        : a.nummer.compareTo(b.nummer);
  }

  return MaschinenDruckDaten(
    maschinen: maschinen,
    steckbriefe: steckbriefe,
    grenzen: grenzen,
    artikel: {
      for (final MapEntry(:key, :value) in jeMaschine.entries)
        key: value.values.toList()..sort(nachNummer),
    },
  );
}
