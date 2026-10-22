import '../../../core/database/database.dart';
import '../daten/entwicklung_repository.dart';
import '../projekte/projekt_checkliste.dart';
import '../projekte/projekt_modell.dart';

// Die Produktentwicklung in Zahlen: wo die Projekte stehen, wie lange es
// bis zur Freigabe dauert, welche Projekte ruhen und wo im Katalog Angaben
// fehlen. Reine Rechnung aus den Listen — die Ansicht holt sie.

/// Nach so vielen Tagen ohne Änderung gilt ein aktives Projekt als ruhend.
const int kRuhendNachTagen = 30;

/// Ein aktives Projekt mit seinem Fortschritt.
class ProjektFortschritt {
  const ProjektFortschritt({
    required this.projekt,
    required this.checkliste,
    required this.staende,
    required this.letzteAktivitaet,
  });

  final EntwicklungsProjekt projekt;

  /// Die Projekt-Checkliste — gezählt wie überall.
  final ProjektCheckStand checkliste;

  /// Erledigte Punkte der Projekt-Checkliste.
  int get erledigt => checkliste.erledigt;
  int get punkte => checkliste.anzahl;

  /// Rezepturstände des Projekts.
  final int staende;

  /// Die letzte Änderung am Projekt, seinem Verlauf oder seinen
  /// Rezepturen.
  final DateTime letzteAktivitaet;

  double get anteil => checkliste.anteil;
}

/// Ein Monat im Verlauf.
class MonatsAktivitaet {
  const MonatsAktivitaet({
    required this.monat,
    required this.eintraege,
    required this.freigaben,
  });

  /// Der erste Tag des Monats.
  final DateTime monat;

  /// Einträge im Verlauf aller Projekte.
  final int eintraege;

  /// Freigaben als Artikel.
  final int freigaben;
}

/// Die Zahlen der Produktentwicklung.
class EntwicklungsStatistik {
  const EntwicklungsStatistik({
    required this.projekteJeStatus,
    required this.aktive,
    required this.freigaben,
    required this.tageBisFreigabe,
    required this.staendeBisFreigabe,
    required this.rezepturen,
    required this.staende,
    required this.abgeschlosseneStaende,
    required this.rezepturenOhneProjekt,
    required this.zutaten,
    required this.zutatenOhneNaehrwerte,
    required this.zutatenOhneAllergene,
    required this.verlauf,
  });

  final Map<ProjektStatus, int> projekteJeStatus;

  /// In Entwicklung oder Validierung — das zuletzt bewegte zuerst.
  final List<ProjektFortschritt> aktive;

  /// Projekte, die als Artikel freigegeben sind.
  final int freigaben;

  /// Im Mittel so viele Tage vom Anlegen bis zur Freigabe — null ohne
  /// Freigabe.
  final double? tageBisFreigabe;

  /// Im Mittel so viele Rezepturstände bis zur Freigabe.
  final double? staendeBisFreigabe;

  final int rezepturen;
  final int staende;
  final int abgeschlosseneStaende;
  final int rezepturenOhneProjekt;
  final int zutaten;

  /// Namen, sortiert.
  final List<String> zutatenOhneNaehrwerte;
  final List<String> zutatenOhneAllergene;

  /// Die letzten zwölf Monate, der älteste zuerst.
  final List<MonatsAktivitaet> verlauf;

  int get projekte => projekteJeStatus.values.fold<int>(0, (s, n) => s + n);

  /// Aktive Projekte, an denen sich seit [kRuhendNachTagen] Tagen nichts
  /// getan hat.
  List<ProjektFortschritt> ruhend(DateTime jetzt) => [
        for (final p in aktive)
          if (jetzt.difference(p.letzteAktivitaet).inDays >= kRuhendNachTagen)
            p,
      ];
}

DateTime _spaeter(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

/// Rechnet die Zahlen aus den Listen. Gelöschte Projekte, Rezepturen und
/// Zutaten müssen schon herausgefiltert sein; Stände und Einträge dürfen
/// alle kommen.
EntwicklungsStatistik entwicklungsStatistik({
  required List<EntwicklungsProjekt> projekte,
  required List<Rezeptur> rezepturen,
  required List<RezepturVersion> versionen,
  required List<Zutat> zutaten,
  required List<ProjektEintrag> eintraege,
  required DateTime jetzt,
}) {
  final jeStatus = {for (final s in ProjektStatus.values) s: 0};
  for (final p in projekte) {
    final s = ProjektStatus.aus(p.status);
    jeStatus[s] = jeStatus[s]! + 1;
  }

  final rezepturIds = {for (final r in rezepturen) r.id};
  final versionenJeRezeptur = <String, List<RezepturVersion>>{};
  for (final v in versionen) {
    if (!rezepturIds.contains(v.rezepturId)) continue;
    versionenJeRezeptur.putIfAbsent(v.rezepturId, () => []).add(v);
  }
  final rezepturenJeProjekt = <String, List<Rezeptur>>{};
  for (final r in rezepturen) {
    final pid = r.projektId;
    if (pid != null) rezepturenJeProjekt.putIfAbsent(pid, () => []).add(r);
  }
  final eintraegeJeProjekt = <String, List<ProjektEintrag>>{};
  for (final e in eintraege) {
    eintraegeJeProjekt.putIfAbsent(e.projektId, () => []).add(e);
  }

  List<RezepturVersion> staendeVon(String projektId) => [
        for (final r in rezepturenJeProjekt[projektId] ?? const <Rezeptur>[])
          ...?versionenJeRezeptur[r.id],
      ];

  final aktive = <ProjektFortschritt>[];
  final tage = <double>[];
  final standZahlen = <int>[];
  for (final p in projekte) {
    final staende = staendeVon(p.id);
    final freigegeben = p.freigegebenAm;
    if (freigegeben != null) {
      tage.add(freigegeben.difference(p.createdAt).inHours / 24);
      standZahlen.add(staende.length);
    }
    final status = ProjektStatus.aus(p.status);
    if (status != ProjektStatus.entwicklung &&
        status != ProjektStatus.validierung) {
      continue;
    }
    var letzte = p.updatedAt;
    for (final e in eintraegeJeProjekt[p.id] ?? const <ProjektEintrag>[]) {
      letzte = _spaeter(letzte, e.updatedAt);
    }
    for (final v in staende) {
      letzte = _spaeter(letzte, v.updatedAt);
    }
    aktive.add(
      ProjektFortschritt(
        projekt: p,
        checkliste: projektCheckStand(
          projekt: p,
          rezepturen: rezepturenJeProjekt[p.id] ?? const <Rezeptur>[],
          versionen: staende,
        ),
        staende: staende.length,
        letzteAktivitaet: letzte,
      ),
    );
  }
  aktive.sort((a, b) => b.letzteAktivitaet.compareTo(a.letzteAktivitaet));

  double? mittel(List<num> werte) => werte.isEmpty
      ? null
      : werte.fold<double>(0, (s, w) => s + w) / werte.length;

  final alleStaende = [
    for (final liste in versionenJeRezeptur.values) ...liste,
  ];

  final ohneNaehrwerte = <String>[];
  final ohneAllergene = <String>[];
  for (final z in zutaten) {
    if (!z.istWasser && !rechenZutatAus(z).naehrwerte.bekannt) {
      ohneNaehrwerte.add(z.name);
    }
    if ((z.allergene ?? '').trim().isEmpty) ohneAllergene.add(z.name);
  }
  ohneNaehrwerte.sort(nachName);
  ohneAllergene.sort(nachName);

  // Die letzten zwölf Monate, der laufende eingeschlossen.
  final monate = [
    for (var k = 11; k >= 0; k--) DateTime(jetzt.year, jetzt.month - k),
  ];
  int monatVon(DateTime d) => monate.indexWhere(
        (m) => m.year == d.year && m.month == d.month,
      );
  final eintraegeJeMonat = List<int>.filled(12, 0);
  final freigabenJeMonat = List<int>.filled(12, 0);
  for (final e in eintraege) {
    final i = monatVon(e.datum);
    if (i >= 0) eintraegeJeMonat[i]++;
  }
  for (final p in projekte) {
    final f = p.freigegebenAm;
    if (f == null) continue;
    final i = monatVon(f);
    if (i >= 0) freigabenJeMonat[i]++;
  }

  return EntwicklungsStatistik(
    projekteJeStatus: jeStatus,
    aktive: aktive,
    freigaben: tage.length,
    tageBisFreigabe: mittel(tage),
    staendeBisFreigabe: mittel(standZahlen),
    rezepturen: rezepturen.length,
    staende: alleStaende.length,
    abgeschlosseneStaende: alleStaende
        .where((v) => v.status == VersionStatus.abgeschlossen)
        .length,
    rezepturenOhneProjekt: rezepturen.where((r) => r.projektId == null).length,
    zutaten: zutaten.length,
    zutatenOhneNaehrwerte: ohneNaehrwerte,
    zutatenOhneAllergene: ohneAllergene,
    verlauf: [
      for (var i = 0; i < 12; i++)
        MonatsAktivitaet(
          monat: monate[i],
          eintraege: eintraegeJeMonat[i],
          freigaben: freigabenJeMonat[i],
        ),
    ],
  );
}
