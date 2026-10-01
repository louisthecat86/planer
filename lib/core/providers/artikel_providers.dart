import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database_provider.dart';

/// Artikelnummern, die es in der App als aktiven Artikel gibt.
///
/// Der Auftragsbestand markiert damit, was in der App noch fehlt, der
/// Navision-Abgleich, was neu anzulegen ist. Wer Artikel anlegt oder
/// löscht, invalidiert den Provider.
final appArtikelnummernProvider = FutureProvider<Set<String>>((ref) async {
  final db = ref.watch(databaseProvider);
  final liste = await (db.select(db.products)
        ..where((p) => p.deletedAt.isNull()))
      .get();
  return liste.map((p) => p.artikelnummer).toSet();
});

/// Abteilungen je Artikelnummer, abgeleitet aus den Prozessschritten.
///
/// Damit lassen sich Listen nach Abteilung filtern: Ein Artikel gehört zur
/// Bratstraße, wenn irgendein Schritt seines Prozesses dort läuft. Ein
/// Artikel ohne Prozess — etwa eine frische Hülle aus dem Navision-Abgleich
/// — hat keinen Eintrag und fällt bei gesetztem Filter heraus; genau das
/// ist gewollt, denn für ihn gibt es in der Abteilung noch nichts zu tun.
///
/// Verknüpft wird über die Artikelnummer, weil Navision die ID der App
/// nicht kennt.
///
/// `autoDispose`, damit die Zuordnung beim nächsten Öffnen eines
/// Bildschirms neu gelesen wird. Wer zwischendurch in einem Artikel einen
/// Schritt ergänzt, soll ihn sofort unter der neuen Abteilung finden und
/// nicht erst nach einem Neustart.
final abteilungenJeArtikelProvider =
    FutureProvider.autoDispose<Map<String, Set<String>>>((ref) async {
  final db = ref.watch(databaseProvider);

  final produkte = await (db.select(db.products)
        ..where((p) => p.deletedAt.isNull()))
      .get();
  final schritte = await (db.select(db.productSteps)
        ..where((s) => s.deletedAt.isNull()))
      .get();

  final nummerJeId = {for (final p in produkte) p.id: p.artikelnummer};
  final map = <String, Set<String>>{};
  for (final s in schritte) {
    final nummer = nummerJeId[s.productId];
    if (nummer == null || nummer.isEmpty) continue;
    map.putIfAbsent(nummer, () => <String>{}).add(s.abteilung);
  }
  return map;
});
